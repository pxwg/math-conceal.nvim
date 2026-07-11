use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::SystemTime;

use time::OffsetDateTime;
use typst::diag::{FileError, FileResult};
use typst::foundations::{Bytes, Datetime, Dict, IntoValue, Str};
use typst::syntax::{FileId, Source, Span, VirtualPath};
use typst::text::{Font, FontBook};
use typst::utils::LazyHash;
use typst::{Library, LibraryExt, World};
use typst_kit::download::{Downloader, ProgressSink};
use typst_kit::fonts::{FontSlot, Fonts};
use typst_kit::package::PackageStorage;

type LibraryKey = Vec<(String, String)>;
type SharedLibraries = Mutex<HashMap<LibraryKey, Arc<LazyHash<Library>>>>;

// Expensive immutable Typst resources are process-wide so full and preview
// lane compilers do not repeat font discovery or package/library state.
struct SharedWorldResources {
    book: LazyHash<FontBook>,
    fonts: Vec<FontSlot>,
    packages: PackageStorage,
    libraries: SharedLibraries,
}

fn shared_world_resources() -> Arc<SharedWorldResources> {
    static SHARED: OnceLock<Arc<SharedWorldResources>> = OnceLock::new();
    Arc::clone(SHARED.get_or_init(|| {
        let fonts = Fonts::searcher().search();
        Arc::new(SharedWorldResources {
            book: LazyHash::new(fonts.book),
            fonts: fonts.fonts,
            packages: PackageStorage::new(
                std::env::var_os("TYPST_PACKAGE_CACHE_PATH").map(PathBuf::from),
                std::env::var_os("TYPST_PACKAGE_PATH").map(PathBuf::from),
                Downloader::new("typst-concealer-service"),
            ),
            libraries: Mutex::new(HashMap::new()),
        })
    }))
}

fn shared_library(
    shared: &SharedWorldResources,
    inputs: &HashMap<String, String>,
) -> Arc<LazyHash<Library>> {
    let mut key: Vec<_> = inputs
        .iter()
        .map(|(key, value)| (key.clone(), value.clone()))
        .collect();
    key.sort_unstable();
    let mut libraries = shared.libraries.lock().unwrap();
    Arc::clone(libraries.entry(key).or_insert_with(|| {
        Arc::new(LazyHash::new(
            Library::builder()
                .with_inputs(to_dict(inputs.clone()))
                .build(),
        ))
    }))
}

pub struct ConcealerWorld {
    entry_id: FileId,
    source: Source,
    root: PathBuf,
    library: Arc<LazyHash<Library>>,
    shared: Arc<SharedWorldResources>,
    virtual_sources: Mutex<HashMap<FileId, Source>>,
    sources: Mutex<HashMap<FileId, Source>>,
    files: Mutex<HashMap<FileId, Bytes>>,
    prev_inputs: HashMap<String, String>,
    file_mtimes: Mutex<HashMap<FileId, SystemTime>>,
}

impl ConcealerWorld {
    pub fn new() -> Self {
        let entry_id = FileId::new(None, VirtualPath::new("/main.typ"));
        let shared = shared_world_resources();
        Self {
            entry_id,
            source: Source::new(entry_id, String::new()),
            root: std::env::current_dir().unwrap_or_else(|_| PathBuf::from(".")),
            library: shared_library(&shared, &HashMap::new()),
            shared,
            virtual_sources: Mutex::new(HashMap::new()),
            sources: Mutex::new(HashMap::new()),
            files: Mutex::new(HashMap::new()),
            prev_inputs: HashMap::new(),
            file_mtimes: Mutex::new(HashMap::new()),
        }
    }

    pub fn update(&mut self, source_text: String, root: PathBuf, inputs: HashMap<String, String>) {
        self.update_with_virtuals(source_text, "/main.typ", root, inputs, Vec::new());
    }

    pub fn update_with_virtuals(
        &mut self,
        source_text: String,
        entry_path: &str,
        root: PathBuf,
        inputs: HashMap<String, String>,
        virtual_sources: Vec<(String, String)>,
    ) {
        self.entry_id = FileId::new(None, VirtualPath::new(entry_path));
        self.source = Source::new(self.entry_id, source_text);

        let mut next_virtuals = HashMap::new();
        for (path, text) in virtual_sources {
            let id = FileId::new(None, VirtualPath::new(&path));
            next_virtuals.insert(id, Source::new(id, text));
        }
        *self.virtual_sources.lock().unwrap() = next_virtuals;

        // Phase 1: Only rebuild library when inputs change
        if inputs != self.prev_inputs {
            self.library = shared_library(&self.shared, &inputs);
            self.prev_inputs = inputs;
        }

        // Phase 2: Only clear caches when root changes
        if self.root != root {
            self.root = root;
            self.sources.lock().unwrap().clear();
            self.files.lock().unwrap().clear();
            self.file_mtimes.lock().unwrap().clear();
        }
    }

    pub fn path_for_id(&self, id: FileId) -> Option<PathBuf> {
        self.real_path(id).ok()
    }

    pub fn position(&self, span: Span) -> (Option<PathBuf>, Option<usize>, Option<usize>) {
        let Some(id) = span.id() else {
            return (None, None, None);
        };

        let file = if id == self.entry_id {
            None
        } else {
            self.path_for_id(id)
        };

        let Ok(source) = self.source(id) else {
            return (file, None, None);
        };

        let byte = source
            .range(span)
            .or_else(|| span.range())
            .map(|range| range.start);
        let Some(byte) = byte else {
            return (file, None, None);
        };

        let Some((line, column)) = source.lines().byte_to_line_column(byte) else {
            return (file, None, None);
        };

        (file, Some(line + 1), Some(column + 1))
    }

    pub fn cached_external_files_fresh(&self) -> bool {
        let ids: Vec<_> = self.file_mtimes.lock().unwrap().keys().cloned().collect();
        ids.into_iter()
            .all(|id| id.package().is_some() || !self.is_stale(id))
    }

    /// Check if a cached file's mtime has changed since we last read it.
    fn is_stale(&self, id: FileId) -> bool {
        let mtimes = self.file_mtimes.lock().unwrap();
        let Some(&cached_mtime) = mtimes.get(&id) else {
            // No recorded mtime — treat as stale to force a re-read
            return true;
        };
        drop(mtimes);

        let Ok(path) = self.real_path(id) else {
            return true;
        };
        match fs::metadata(&path).and_then(|m| m.modified()) {
            Ok(disk_mtime) => disk_mtime != cached_mtime,
            Err(_) => true,
        }
    }

    fn record_mtime(&self, id: FileId, path: &std::path::Path) {
        if let Ok(mtime) = fs::metadata(path).and_then(|m| m.modified()) {
            self.file_mtimes.lock().unwrap().insert(id, mtime);
        }
    }

    fn real_path(&self, id: FileId) -> FileResult<PathBuf> {
        if id == self.entry_id {
            return Err(FileError::NotFound(PathBuf::from("/main.typ")));
        }

        if self.virtual_sources.lock().unwrap().contains_key(&id) {
            return Ok(id.vpath().as_rooted_path().into());
        }

        if let Some(spec) = id.package() {
            let mut progress = ProgressSink;
            let root = self.shared.packages.prepare_package(spec, &mut progress)?;
            return id
                .vpath()
                .resolve(&root)
                .ok_or_else(|| FileError::NotFound(id.vpath().as_rooted_path().into()));
        }

        id.vpath()
            .resolve(&self.root)
            .ok_or_else(|| FileError::NotFound(id.vpath().as_rooted_path().into()))
    }
}

impl World for ConcealerWorld {
    fn library(&self) -> &LazyHash<Library> {
        &self.library
    }

    fn book(&self) -> &LazyHash<FontBook> {
        &self.shared.book
    }

    fn main(&self) -> FileId {
        self.entry_id
    }

    fn source(&self, id: FileId) -> FileResult<Source> {
        if id == self.entry_id {
            return Ok(self.source.clone());
        }

        if let Some(source) = self.virtual_sources.lock().unwrap().get(&id).cloned() {
            return Ok(source);
        }

        let is_package = id.package().is_some();

        if let Some(source) = self.sources.lock().unwrap().get(&id).cloned() {
            // Package files are immutable — skip mtime check
            if is_package || !self.is_stale(id) {
                return Ok(source);
            }
        }

        let path = self.real_path(id)?;
        if path.extension().is_some_and(|ext| ext != "typ") {
            return Err(FileError::NotSource);
        }

        let text = fs::read_to_string(&path).map_err(|err| FileError::from_io(err, &path))?;
        let source = Source::new(id, text);
        self.sources.lock().unwrap().insert(id, source.clone());
        self.record_mtime(id, &path);
        Ok(source)
    }

    fn file(&self, id: FileId) -> FileResult<Bytes> {
        if id == self.entry_id {
            return Ok(Bytes::new(self.source.text().as_bytes().to_vec()));
        }

        if let Some(source) = self.virtual_sources.lock().unwrap().get(&id).cloned() {
            return Ok(Bytes::new(source.text().as_bytes().to_vec()));
        }

        let is_package = id.package().is_some();

        if let Some(bytes) = self.files.lock().unwrap().get(&id).cloned() {
            if is_package || !self.is_stale(id) {
                return Ok(bytes);
            }
        }

        let path = self.real_path(id)?;
        let data = fs::read(&path).map_err(|err| FileError::from_io(err, &path))?;
        let bytes = Bytes::new(data);
        self.files.lock().unwrap().insert(id, bytes.clone());
        self.record_mtime(id, &path);
        Ok(bytes)
    }

    fn font(&self, index: usize) -> Option<Font> {
        self.shared.fonts.get(index)?.get()
    }

    fn today(&self, offset: Option<i64>) -> Option<Datetime> {
        let now = if let Some(hours) = offset {
            let hours = i8::try_from(hours).ok()?;
            let offset = time::UtcOffset::from_hms(hours, 0, 0).ok()?;
            OffsetDateTime::now_utc().to_offset(offset)
        } else {
            OffsetDateTime::now_local().unwrap_or_else(|_| OffsetDateTime::now_utc())
        };

        Datetime::from_ymd(now.year(), u8::from(now.month()), now.day())
    }
}

fn to_dict(inputs: HashMap<String, String>) -> Dict {
    let mut dict = Dict::new();
    for (key, value) in inputs {
        dict.insert(Str::from(key), value.into_value());
    }
    dict
}
