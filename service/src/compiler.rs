use std::collections::HashMap;
use std::fs;
use std::hash::{DefaultHasher, Hash, Hasher};
use std::path::{Path, PathBuf};
use std::time::Instant;

use image::codecs::png::{CompressionType, FilterType, PngEncoder};
use image::{ColorType, ImageEncoder};
use typst::diag::{Severity, SourceDiagnostic};
use typst::layout::PagedDocument;

use crate::protocol::{
    CompileRequest, CompileResponse, CompileStatus, DiagnosticInfo, FormulaNodeRequest,
    FormulaRenderResponse, PageResult, RenderFormulasRequest,
};
use crate::world::ConcealerWorld;

pub struct Compiler {
    world: ConcealerWorld,
    /// Hash of Page (frame + fill) from previous compile, indexed by page.
    prev_frame_hashes: Vec<u64>,
    prev_page_paths: Vec<PathBuf>,
    prev_page_dims: Vec<(u32, u32)>,
    prev_ppi: u32,
    formula_artifacts: HashMap<u64, (PathBuf, u32, u32)>,
}

impl Compiler {
    pub fn new() -> Self {
        Self {
            world: ConcealerWorld::new(),
            prev_frame_hashes: Vec::new(),
            prev_page_paths: Vec::new(),
            prev_page_dims: Vec::new(),
            prev_ppi: 0,
            formula_artifacts: HashMap::new(),
        }
    }

    pub fn compile(&mut self, req: CompileRequest) -> CompileResponse {
        let request_id = req.request_id;
        let output_dir = req.output_dir;
        let ppi = req.ppi.max(1);

        self.world.update(req.source_text, req.root, req.inputs);

        // Evict stale comemo memoization entries so incremental compilation
        // remains effective without unbounded memory growth.
        comemo::evict(30);

        if let Err(err) = fs::create_dir_all(&output_dir) {
            return CompileResponse {
                request_id,
                status: CompileStatus::Error,
                pages: vec![],
                diagnostics: vec![DiagnosticInfo {
                    message: format!("failed to create output directory: {err}"),
                    severity: "error".to_string(),
                    file: None,
                    line: None,
                    column: None,
                }],
                compile_us: None,
                render_us: None,
                rendered_pages: None,
            };
        }

        let t_compile = Instant::now();
        let warned = typst::compile::<PagedDocument>(&self.world);
        let compile_us = t_compile.elapsed().as_micros() as u64;

        let warnings = self.format_diagnostics(warned.warnings.iter());
        let document = match warned.output {
            Ok(document) => document,
            Err(errors) => {
                let mut diagnostics = warnings;
                diagnostics.extend(self.format_diagnostics(errors.iter()));
                return CompileResponse {
                    request_id,
                    status: CompileStatus::Error,
                    pages: vec![],
                    diagnostics,
                    compile_us: Some(compile_us),
                    render_us: None,
                    rendered_pages: None,
                };
            }
        };

        let pixel_per_pt = ppi as f32 / 72.0;
        let ppi_changed = ppi != self.prev_ppi;
        let mut pages = Vec::new();
        let mut diagnostics = warnings;
        let mut new_frame_hashes = Vec::with_capacity(document.pages.len());
        let mut new_paths = Vec::with_capacity(document.pages.len());
        let mut new_dims = Vec::with_capacity(document.pages.len());

        let t_render = Instant::now();
        let mut rendered_count = 0usize;

        for (i, page) in document.pages.iter().enumerate() {
            // Hash the compiled page frame (cheap) to detect unchanged pages
            // before doing the expensive pixel rendering.
            let mut hasher = DefaultHasher::new();
            page.hash(&mut hasher);
            ppi.hash(&mut hasher);
            let frame_hash = hasher.finish();

            let can_reuse = !ppi_changed
                && i < self.prev_frame_hashes.len()
                && self.prev_frame_hashes[i] == frame_hash
                && self.prev_page_paths[i].exists();

            if can_reuse {
                let dims = self.prev_page_dims[i];
                new_frame_hashes.push(frame_hash);
                new_paths.push(self.prev_page_paths[i].clone());
                new_dims.push(dims);

                pages.push(PageResult {
                    page_index: i,
                    path: self.prev_page_paths[i].clone(),
                    width_px: dims.0,
                    height_px: dims.1,
                    cached: true,
                });
                continue;
            }

            // Page changed — render to pixels and write PNG.
            rendered_count += 1;
            let pixmap = typst_render::render(page, pixel_per_pt);
            let dims = (pixmap.width(), pixmap.height());

            // Use pixel hash for the filename so identical renders share a path.
            let mut px_hasher = DefaultHasher::new();
            pixmap.data().hash(&mut px_hasher);
            let px_hash = px_hasher.finish();

            let path = output_dir.join(format!("page-{i}-{px_hash:016x}.png"));
            if !path.exists() {
                if let Err(err) = write_pixmap_png(&path, &pixmap) {
                    diagnostics.push(DiagnosticInfo {
                        message: format!("failed to write rendered page: {err}"),
                        severity: "error".to_string(),
                        file: None,
                        line: None,
                        column: None,
                    });
                    return CompileResponse {
                        request_id,
                        status: CompileStatus::Error,
                        pages,
                        diagnostics,
                        compile_us: Some(compile_us),
                        render_us: Some(t_render.elapsed().as_micros() as u64),
                        rendered_pages: Some(rendered_count),
                    };
                }
            }

            new_frame_hashes.push(frame_hash);
            new_paths.push(path.clone());
            new_dims.push(dims);

            pages.push(PageResult {
                page_index: i,
                path,
                width_px: dims.0,
                height_px: dims.1,
                cached: false,
            });
        }

        let render_us = t_render.elapsed().as_micros() as u64;

        // Do NOT clean up old PNG files here.  The Lua plugin manages page
        // lifecycles (retire_overlay / cleanup_service_cache_dir) and the same
        // Compiler instance serves both full-render and preview requests, so
        // deleting pages from a previous compile would race with the terminal
        // still reading those files via the kitty graphics protocol.

        self.prev_frame_hashes = new_frame_hashes;
        self.prev_page_paths = new_paths;
        self.prev_page_dims = new_dims;
        self.prev_ppi = ppi;

        CompileResponse {
            request_id,
            status: CompileStatus::Ok,
            pages,
            diagnostics,
            compile_us: Some(compile_us),
            render_us: Some(render_us),
            rendered_pages: Some(rendered_count),
        }
    }

    pub fn render_formula(
        &mut self,
        req: &RenderFormulasRequest,
        node: &FormulaNodeRequest,
    ) -> FormulaRenderResponse {
        let ppi = req.ppi.max(1);
        let node_path = formula_node_path(&node.node_id);
        let source_text = build_formula_entry_document(&req.context_source, &node_path);
        self.world.update_with_virtuals(
            source_text,
            "/__typst_concealer__/main.typ",
            req.root.clone(),
            req.inputs.clone(),
            vec![(node_path, node.source.clone())],
        );
        comemo::evict(30);

        let cache_key = formula_cache_key(req, node, ppi);
        if let Some((path, width_px, height_px)) = self.formula_artifacts.get(&cache_key) {
            if path.exists() && self.world.cached_external_files_fresh() {
                return FormulaRenderResponse {
                    request_id: req.request_id.clone(),
                    context_id: req.context_id.clone(),
                    context_rev: req.context_rev,
                    node_id: node.node_id.clone(),
                    node_rev: node.node_rev,
                    status: CompileStatus::Ok,
                    path: Some(path.clone()),
                    width_px: Some(*width_px),
                    height_px: Some(*height_px),
                    cached: true,
                    diagnostics: Vec::new(),
                    compile_us: Some(0),
                    render_us: Some(0),
                };
            }
        }

        if let Err(err) = fs::create_dir_all(&req.output_dir) {
            return FormulaRenderResponse {
                request_id: req.request_id.clone(),
                context_id: req.context_id.clone(),
                context_rev: req.context_rev,
                node_id: node.node_id.clone(),
                node_rev: node.node_rev,
                status: CompileStatus::Error,
                path: None,
                width_px: None,
                height_px: None,
                cached: false,
                diagnostics: vec![DiagnosticInfo {
                    message: format!("failed to create output directory: {err}"),
                    severity: "error".to_string(),
                    file: None,
                    line: None,
                    column: None,
                }],
                compile_us: None,
                render_us: None,
            };
        }

        let t_compile = Instant::now();
        let warned = typst::compile::<PagedDocument>(&self.world);
        let compile_us = t_compile.elapsed().as_micros() as u64;

        let warnings = self.format_diagnostics(warned.warnings.iter());
        let document = match warned.output {
            Ok(document) => document,
            Err(errors) => {
                let mut diagnostics = warnings;
                diagnostics.extend(self.format_diagnostics(errors.iter()));
                return FormulaRenderResponse {
                    request_id: req.request_id.clone(),
                    context_id: req.context_id.clone(),
                    context_rev: req.context_rev,
                    node_id: node.node_id.clone(),
                    node_rev: node.node_rev,
                    status: CompileStatus::Error,
                    path: None,
                    width_px: None,
                    height_px: None,
                    cached: false,
                    diagnostics,
                    compile_us: Some(compile_us),
                    render_us: None,
                };
            }
        };

        let Some(page) = document.pages.last() else {
            return FormulaRenderResponse {
                request_id: req.request_id.clone(),
                context_id: req.context_id.clone(),
                context_rev: req.context_rev,
                node_id: node.node_id.clone(),
                node_rev: node.node_rev,
                status: CompileStatus::Error,
                path: None,
                width_px: None,
                height_px: None,
                cached: false,
                diagnostics: vec![DiagnosticInfo {
                    message: "formula rendered no pages".to_string(),
                    severity: "error".to_string(),
                    file: None,
                    line: None,
                    column: None,
                }],
                compile_us: Some(compile_us),
                render_us: None,
            };
        };

        let pixel_per_pt = ppi as f32 / 72.0;
        let t_render = Instant::now();
        let pixmap = typst_render::render(page, pixel_per_pt);
        let render_us = t_render.elapsed().as_micros() as u64;
        let dims = (pixmap.width(), pixmap.height());

        let mut px_hasher = DefaultHasher::new();
        pixmap.data().hash(&mut px_hasher);
        let px_hash = px_hasher.finish();
        let path = req.output_dir.join(format!(
            "formula-{}-{px_hash:016x}.png",
            sanitize_filename(&node.node_id)
        ));

        if !path.exists() {
            if let Err(err) = write_pixmap_png(&path, &pixmap) {
                let mut diagnostics = warnings;
                diagnostics.push(DiagnosticInfo {
                    message: format!("failed to write rendered formula: {err}"),
                    severity: "error".to_string(),
                    file: None,
                    line: None,
                    column: None,
                });
                return FormulaRenderResponse {
                    request_id: req.request_id.clone(),
                    context_id: req.context_id.clone(),
                    context_rev: req.context_rev,
                    node_id: node.node_id.clone(),
                    node_rev: node.node_rev,
                    status: CompileStatus::Error,
                    path: None,
                    width_px: None,
                    height_px: None,
                    cached: false,
                    diagnostics,
                    compile_us: Some(compile_us),
                    render_us: Some(render_us),
                };
            }
        }

        self.formula_artifacts
            .insert(cache_key, (path.clone(), dims.0, dims.1));

        FormulaRenderResponse {
            request_id: req.request_id.clone(),
            context_id: req.context_id.clone(),
            context_rev: req.context_rev,
            node_id: node.node_id.clone(),
            node_rev: node.node_rev,
            status: CompileStatus::Ok,
            path: Some(path),
            width_px: Some(dims.0),
            height_px: Some(dims.1),
            cached: false,
            diagnostics: warnings,
            compile_us: Some(compile_us),
            render_us: Some(render_us),
        }
    }

    fn format_diagnostics<'a>(
        &self,
        diagnostics: impl IntoIterator<Item = &'a SourceDiagnostic>,
    ) -> Vec<DiagnosticInfo> {
        diagnostics
            .into_iter()
            .map(|diag| {
                let (file, line, column) = self.world.position(diag.span);
                DiagnosticInfo {
                    message: diag.message.to_string(),
                    severity: match diag.severity {
                        Severity::Error => "error",
                        Severity::Warning => "warning",
                    }
                    .to_string(),
                    file,
                    line,
                    column,
                }
            })
            .collect()
    }
}

fn write_pixmap_png(
    path: &Path,
    pixmap: &tiny_skia::Pixmap,
) -> Result<(), Box<dyn std::error::Error>> {
    let file = fs::File::create(path)?;
    let rgba = unpremultiply_to_rgba(pixmap);
    PngEncoder::new_with_quality(file, CompressionType::Fast, FilterType::NoFilter).write_image(
        &rgba,
        pixmap.width(),
        pixmap.height(),
        ColorType::Rgba8.into(),
    )?;
    Ok(())
}

fn build_formula_entry_document(context_source: &str, node_path: &str) -> String {
    let mut source = String::new();
    if !context_source.is_empty() {
        source.push_str(context_source);
        if !context_source.ends_with('\n') {
            source.push('\n');
        }
        source.push_str("#pagebreak(weak: true)\n");
    }
    source.push_str("#include \"");
    source.push_str(node_path);
    source.push_str("\"\n");
    source
}

fn formula_node_path(node_id: &str) -> String {
    format!(
        "/__typst_concealer__/nodes/{}.typ",
        sanitize_filename(node_id)
    )
}

fn formula_cache_key(req: &RenderFormulasRequest, node: &FormulaNodeRequest, ppi: u32) -> u64 {
    let mut hasher = DefaultHasher::new();
    req.context_id.hash(&mut hasher);
    req.context_source.hash(&mut hasher);
    req.root.hash(&mut hasher);
    ppi.hash(&mut hasher);
    let mut inputs: Vec<_> = req.inputs.iter().collect();
    inputs.sort_by(|a, b| a.0.cmp(b.0));
    for (key, value) in inputs {
        key.hash(&mut hasher);
        value.hash(&mut hasher);
    }
    node.kind.hash(&mut hasher);
    node.source_hash.hash(&mut hasher);
    node.source.hash(&mut hasher);
    hasher.finish()
}

fn sanitize_filename(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for ch in value.chars() {
        if ch.is_ascii_alphanumeric() || ch == '-' || ch == '_' {
            out.push(ch);
        } else {
            out.push('-');
        }
    }
    if out.is_empty() {
        "node".to_string()
    } else {
        out
    }
}

#[cfg(test)]
mod tests {
    use std::thread;
    use std::time::{Duration, SystemTime, UNIX_EPOCH};

    use super::*;

    fn temp_dir(name: &str) -> PathBuf {
        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!(
            "typst-concealer-service-{name}-{}-{stamp}",
            std::process::id()
        ))
    }

    #[test]
    fn formula_cache_revalidates_imported_files() {
        let root = temp_dir("formula-cache");
        let output_dir = root.join("out");
        fs::create_dir_all(&output_dir).unwrap();
        fs::write(
            root.join("dep.typ"),
            "#rect(width: 8pt, height: 8pt, fill: red)\n",
        )
        .unwrap();

        let req = RenderFormulasRequest {
            backend: None,
            request_id: "formula:test".to_string(),
            cache_key: None,
            context_id: "ctx".to_string(),
            context_rev: 1,
            context_source: String::new(),
            root: root.clone(),
            inputs: HashMap::new(),
            output_dir: output_dir.clone(),
            ppi: 72,
            worker_count: None,
            compiler: None,
            converter: None,
            compiler_args: Vec::new(),
            nodes: Vec::new(),
        };
        let node = FormulaNodeRequest {
            node_id: "node".to_string(),
            node_rev: 1,
            source_hash: None,
            kind: None,
            source: "#include \"/dep.typ\"\n".to_string(),
        };

        let mut compiler = Compiler::new();
        let first = compiler.render_formula(&req, &node);
        assert!(matches!(&first.status, CompileStatus::Ok));
        assert!(!first.cached);

        let second = compiler.render_formula(&req, &node);
        assert!(matches!(&second.status, CompileStatus::Ok));
        assert!(second.cached);

        thread::sleep(Duration::from_millis(20));
        fs::write(
            root.join("dep.typ"),
            "#rect(width: 8pt, height: 8pt, fill: blue)\n",
        )
        .unwrap();

        let third = compiler.render_formula(&req, &node);
        assert!(matches!(&third.status, CompileStatus::Ok));
        assert!(!third.cached);

        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn formula_context_prelude_controls_page_setup() {
        let root = temp_dir("formula-context-page");
        let output_dir = root.join("out");
        fs::create_dir_all(&output_dir).unwrap();

        let req = RenderFormulasRequest {
            backend: None,
            request_id: "formula:test".to_string(),
            cache_key: None,
            context_id: "ctx".to_string(),
            context_rev: 1,
            context_source:
                "#set page(width: auto, height: auto, margin: (x: 0pt, y: 0pt), fill: none)\n"
                    .to_string(),
            root: root.clone(),
            inputs: HashMap::new(),
            output_dir: output_dir.clone(),
            ppi: 72,
            worker_count: None,
            compiler: None,
            converter: None,
            compiler_args: Vec::new(),
            nodes: Vec::new(),
        };
        let node = FormulaNodeRequest {
            node_id: "node".to_string(),
            node_rev: 1,
            source_hash: None,
            kind: None,
            source: "$x$\n".to_string(),
        };

        let mut compiler = Compiler::new();
        let rendered = compiler.render_formula(&req, &node);
        assert!(matches!(&rendered.status, CompileStatus::Ok));
        let width = rendered.width_px.unwrap();
        let height = rendered.height_px.unwrap();
        assert!(
            width < 200,
            "expected auto-width formula page, got {width}px"
        );
        assert!(
            height < 200,
            "expected auto-height formula page, got {height}px"
        );

        let image = image::ImageReader::open(rendered.path.unwrap())
            .unwrap()
            .decode()
            .unwrap()
            .to_rgba8();
        assert_eq!(
            image.get_pixel(0, 0).0[3],
            0,
            "formula page prelude should keep the background transparent"
        );

        let _ = fs::remove_dir_all(root);
    }
}

fn unpremultiply_to_rgba(pixmap: &tiny_skia::Pixmap) -> Vec<u8> {
    let mut out = Vec::with_capacity(pixmap.data().len());
    for pixel in pixmap.pixels() {
        let alpha = pixel.alpha();
        if alpha == 0 {
            out.extend_from_slice(&[0, 0, 0, 0]);
        } else {
            out.push(unpremultiply(pixel.red(), alpha));
            out.push(unpremultiply(pixel.green(), alpha));
            out.push(unpremultiply(pixel.blue(), alpha));
            out.push(alpha);
        }
    }
    out
}

fn unpremultiply(channel: u8, alpha: u8) -> u8 {
    let value = (u16::from(channel) * 255 + u16::from(alpha) / 2) / u16::from(alpha);
    value.min(255) as u8
}
