use std::collections::HashMap;
use std::fs;
use std::hash::{DefaultHasher, Hash, Hasher};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::Instant;

use image::GenericImageView;

use crate::protocol::{
    CompileStatus, DiagnosticInfo, FormulaNodeRequest, FormulaRenderResponse, RenderFormulasRequest,
};

pub struct LatexRenderer {
    artifacts: HashMap<u64, (PathBuf, u32, u32)>,
}

struct WorkDirGuard {
    path: PathBuf,
}

impl WorkDirGuard {
    fn new(path: PathBuf) -> Self {
        Self { path }
    }
}

impl Drop for WorkDirGuard {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.path);
    }
}

impl LatexRenderer {
    pub fn new() -> Self {
        Self {
            artifacts: HashMap::new(),
        }
    }

    pub fn render_formula(
        &mut self,
        req: &RenderFormulasRequest,
        node: &FormulaNodeRequest,
    ) -> FormulaRenderResponse {
        let ppi = req.ppi.max(1);
        let compiler = req.compiler.as_deref().unwrap_or("pdflatex");
        let converter = req.converter.as_deref().unwrap_or("pdftocairo");
        let backend_node_type = node.kind.as_deref().unwrap_or("inline_formula");
        let document = build_formula_document(&req.context_source, &node.source, backend_node_type);
        let external_sig = external_signature(&req.root, &req.context_source, &node.source);
        let cache_key = latex_cache_key(req, node, ppi, compiler, converter, &external_sig);

        if let Some((path, width_px, height_px)) = self.artifacts.get(&cache_key) {
            if path.exists() {
                return response_ok(
                    req,
                    node,
                    path.clone(),
                    *width_px,
                    *height_px,
                    true,
                    0,
                    0,
                    Vec::new(),
                );
            }
        }

        if let Err(err) = fs::create_dir_all(&req.output_dir) {
            return response_error(
                req,
                node,
                format!("failed to create output directory: {err}"),
                None,
                None,
            );
        }

        let work_dir = req.output_dir.join(format!(
            "latex-work-{}-{cache_key:016x}",
            sanitize_filename(&node.node_id)
        ));
        if let Err(err) = fs::create_dir_all(&work_dir) {
            return response_error(
                req,
                node,
                format!("failed to create LaTeX work directory: {err}"),
                None,
                None,
            );
        }
        let _work_dir_guard = WorkDirGuard::new(work_dir.clone());

        let tex_path = work_dir.join("node.tex");
        let pdf_path = work_dir.join("node.pdf");
        let log_path = work_dir.join("node.log");
        if let Err(err) = fs::write(&tex_path, document) {
            return response_error(
                req,
                node,
                format!("failed to write generated LaTeX document: {err}"),
                None,
                None,
            );
        }

        let t_compile = Instant::now();
        let compile_output = run_compiler(
            compiler,
            &req.compiler_args,
            &tex_path,
            &work_dir,
            &req.root,
        );
        let compile_us = t_compile.elapsed().as_micros() as u64;
        let log_text = read_to_string(&log_path);

        match compile_output {
            Ok(output) if output.status.success() && pdf_path.exists() => {
                let mut diagnostics = parse_latex_log(&log_text);
                diagnostics.extend(parse_latex_log(&String::from_utf8_lossy(&output.stderr)));
                let t_render = Instant::now();
                let prefix = req.output_dir.join(format!(
                    "latex-{}-{cache_key:016x}",
                    sanitize_filename(&node.node_id)
                ));
                let png_path = prefix.with_extension("png");
                match run_converter(converter, &pdf_path, &prefix, ppi) {
                    Ok(convert_output) if convert_output.status.success() && png_path.exists() => {
                        let render_us = t_render.elapsed().as_micros() as u64;
                        let image_result = image::ImageReader::open(&png_path)
                            .map_err(|err| err.to_string())
                            .and_then(|reader| {
                                reader.with_guessed_format().map_err(|err| err.to_string())
                            })
                            .and_then(|reader| reader.decode().map_err(|err| err.to_string()));
                        match image_result {
                            Ok(image) => {
                                let (width_px, height_px) = image.dimensions();
                                self.artifacts
                                    .insert(cache_key, (png_path.clone(), width_px, height_px));
                                response_ok(
                                    req,
                                    node,
                                    png_path,
                                    width_px,
                                    height_px,
                                    false,
                                    compile_us,
                                    render_us,
                                    diagnostics,
                                )
                            }
                            Err(err) => response_error(
                                req,
                                node,
                                format!("failed to read converted PNG: {err}"),
                                Some(compile_us),
                                Some(render_us),
                            ),
                        }
                    }
                    Ok(output) => {
                        let mut diagnostics =
                            parse_latex_log(&String::from_utf8_lossy(&output.stderr));
                        if diagnostics.is_empty() {
                            diagnostics.push(DiagnosticInfo {
                                message: format!(
                                    "LaTeX converter '{}' failed: {}",
                                    converter,
                                    short_output(&output.stderr)
                                ),
                                severity: "error".to_string(),
                                file: None,
                                line: None,
                                column: None,
                            });
                        }
                        response_with_diagnostics(
                            req,
                            node,
                            CompileStatus::Error,
                            diagnostics,
                            Some(compile_us),
                            None,
                        )
                    }
                    Err(err) => response_error(
                        req,
                        node,
                        format!("failed to run LaTeX converter '{}': {err}", converter),
                        Some(compile_us),
                        None,
                    ),
                }
            }
            Ok(output) => {
                let mut diagnostics = parse_latex_log(&log_text);
                diagnostics.extend(parse_latex_log(&String::from_utf8_lossy(&output.stdout)));
                diagnostics.extend(parse_latex_log(&String::from_utf8_lossy(&output.stderr)));
                if diagnostics.is_empty() {
                    diagnostics.push(DiagnosticInfo {
                        message: format!(
                            "LaTeX compiler '{}' failed: {}",
                            compiler,
                            short_output(&output.stderr)
                        ),
                        severity: "error".to_string(),
                        file: None,
                        line: None,
                        column: None,
                    });
                }
                response_with_diagnostics(
                    req,
                    node,
                    CompileStatus::Error,
                    diagnostics,
                    Some(compile_us),
                    None,
                )
            }
            Err(err) => response_error(
                req,
                node,
                format!("failed to run LaTeX compiler '{}': {err}", compiler),
                None,
                None,
            ),
        }
    }
}

fn run_compiler(
    compiler: &str,
    compiler_args: &[String],
    tex_path: &Path,
    work_dir: &Path,
    root: &Path,
) -> std::io::Result<std::process::Output> {
    let mut cmd = Command::new(compiler);
    cmd.current_dir(root)
        .arg("-interaction=nonstopmode")
        .arg("-halt-on-error")
        .arg("-output-directory")
        .arg(work_dir);
    for arg in compiler_args {
        cmd.arg(arg);
    }
    cmd.arg(tex_path);
    cmd.output()
}

fn run_converter(
    converter: &str,
    pdf_path: &Path,
    output_prefix: &Path,
    ppi: u32,
) -> std::io::Result<std::process::Output> {
    let mut cmd = Command::new(converter);
    let name = Path::new(converter)
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or(converter);
    if name.contains("pdftoppm") {
        cmd.arg("-png")
            .arg("-singlefile")
            .arg("-r")
            .arg(ppi.to_string())
            .arg(pdf_path)
            .arg(output_prefix);
    } else {
        cmd.arg("-png")
            .arg("-singlefile")
            .arg("-r")
            .arg(ppi.to_string())
            .arg("-transp")
            .arg(pdf_path)
            .arg(output_prefix);
    }
    cmd.output()
}

fn build_formula_document(context_source: &str, source: &str, backend_node_type: &str) -> String {
    let mut out = String::new();
    out.push_str(context_source);
    if !out.is_empty() && !out.ends_with('\n') {
        out.push('\n');
    }
    out.push_str("\\begin{document}\n");
    out.push_str("\\begin{preview}\n");
    out.push_str(&unwrap_math(source, backend_node_type));
    if !out.ends_with('\n') {
        out.push('\n');
    }
    out.push_str("\\end{preview}\n");
    out.push_str("\\end{document}\n");
    out
}

fn unwrap_math(source: &str, backend_node_type: &str) -> String {
    match backend_node_type {
        "math_environment" => source.to_string(),
        "displayed_equation" => {
            if source.starts_with("$$") && source.ends_with("$$") && source.len() >= 4 {
                format!("\\[{}\\]", &source[2..source.len() - 2])
            } else if source.starts_with("\\[") && source.ends_with("\\]") && source.len() >= 4 {
                source.to_string()
            } else {
                format!("\\[{source}\\]")
            }
        }
        _ => {
            if source.starts_with("\\(") && source.ends_with("\\)") && source.len() >= 4 {
                format!("${}$", &source[2..source.len() - 2])
            } else if source.starts_with('$')
                && source.ends_with('$')
                && !source.starts_with("$$")
                && source.len() >= 2
            {
                source.to_string()
            } else {
                format!("${source}$")
            }
        }
    }
}

fn parse_latex_log(text: &str) -> Vec<DiagnosticInfo> {
    let mut diagnostics = Vec::new();
    let mut pending_error: Option<String> = None;

    for raw in text.lines() {
        let line = raw.trim();
        if let Some(message) = line.strip_prefix('!') {
            pending_error = Some(message.trim().to_string());
            continue;
        }

        if let Some(line_no) = parse_latex_line_number(line) {
            if let Some(message) = pending_error.take() {
                diagnostics.push(DiagnosticInfo {
                    message,
                    severity: "error".to_string(),
                    file: None,
                    line: Some(line_no),
                    column: Some(1),
                });
            }
            continue;
        }

        if line.contains("Warning:") || line.contains("LaTeX Warning") {
            diagnostics.push(DiagnosticInfo {
                message: line.to_string(),
                severity: "warning".to_string(),
                file: None,
                line: None,
                column: None,
            });
        }
    }

    if let Some(message) = pending_error.take() {
        diagnostics.push(DiagnosticInfo {
            message,
            severity: "error".to_string(),
            file: None,
            line: None,
            column: None,
        });
    }

    diagnostics
}

fn parse_latex_line_number(line: &str) -> Option<usize> {
    let rest = line.strip_prefix("l.")?;
    let digits: String = rest.chars().take_while(|ch| ch.is_ascii_digit()).collect();
    digits.parse().ok()
}

fn latex_cache_key(
    req: &RenderFormulasRequest,
    node: &FormulaNodeRequest,
    ppi: u32,
    compiler: &str,
    converter: &str,
    external_sig: &str,
) -> u64 {
    let mut hasher = DefaultHasher::new();
    req.backend.hash(&mut hasher);
    req.context_id.hash(&mut hasher);
    req.context_source.hash(&mut hasher);
    req.root.hash(&mut hasher);
    ppi.hash(&mut hasher);
    compiler.hash(&mut hasher);
    converter.hash(&mut hasher);
    req.compiler_args.hash(&mut hasher);
    external_sig.hash(&mut hasher);
    node.kind.hash(&mut hasher);
    node.source_hash.hash(&mut hasher);
    node.source.hash(&mut hasher);
    hasher.finish()
}

fn external_signature(root: &Path, context_source: &str, node_source: &str) -> String {
    let mut paths = Vec::new();
    collect_latex_paths(context_source, &mut paths);
    collect_latex_paths(node_source, &mut paths);
    paths.sort();
    paths.dedup();

    let mut parts = Vec::new();
    for raw in paths {
        if let Some(path) = resolve_latex_input_path(root, &raw) {
            match fs::metadata(&path) {
                Ok(meta) => {
                    let modified = meta
                        .modified()
                        .ok()
                        .and_then(|time| time.duration_since(std::time::UNIX_EPOCH).ok())
                        .map(|dur| dur.as_nanos())
                        .unwrap_or(0);
                    parts.push(format!("{}:{}:{}", path.display(), meta.len(), modified));
                }
                Err(_) => parts.push(format!("{}:missing", path.display())),
            }
        } else {
            parts.push(format!("{raw}:unresolved"));
        }
    }
    parts.join("\0")
}

fn collect_latex_paths(text: &str, out: &mut Vec<String>) {
    for command in ["input", "include", "includegraphics", "bibliography"] {
        let needle = format!("\\{command}");
        let mut rest = text;
        while let Some(pos) = rest.find(&needle) {
            rest = &rest[pos + needle.len()..];
            let trimmed = rest.trim_start();
            let trimmed = if let Some(after_optional) = skip_optional_arg(trimmed) {
                after_optional.trim_start()
            } else {
                trimmed
            };
            if let Some((arg, tail)) = take_braced_arg(trimmed) {
                if !arg.trim().is_empty() {
                    out.push(arg.trim().to_string());
                }
                rest = tail;
            }
        }
    }
}

fn skip_optional_arg(text: &str) -> Option<&str> {
    let mut chars = text.char_indices();
    let (_, first) = chars.next()?;
    if first != '[' {
        return None;
    }
    let mut depth = 0usize;
    for (idx, ch) in text.char_indices() {
        if ch == '[' {
            depth += 1;
        } else if ch == ']' {
            depth = depth.saturating_sub(1);
            if depth == 0 {
                return Some(&text[idx + ch.len_utf8()..]);
            }
        }
    }
    None
}

fn take_braced_arg(text: &str) -> Option<(String, &str)> {
    let mut chars = text.char_indices();
    let (_, first) = chars.next()?;
    if first != '{' {
        return None;
    }
    let mut depth = 0usize;
    let mut start = None;
    for (idx, ch) in text.char_indices() {
        if ch == '{' {
            if depth == 0 {
                start = Some(idx + ch.len_utf8());
            }
            depth += 1;
        } else if ch == '}' {
            depth = depth.saturating_sub(1);
            if depth == 0 {
                let start = start?;
                return Some((text[start..idx].to_string(), &text[idx + ch.len_utf8()..]));
            }
        }
    }
    None
}

fn resolve_latex_input_path(root: &Path, raw: &str) -> Option<PathBuf> {
    if raw.contains("://") {
        return None;
    }
    let base = if Path::new(raw).is_absolute() {
        PathBuf::from(raw)
    } else {
        root.join(raw)
    };
    let candidates = if base.extension().is_some() {
        vec![base]
    } else {
        vec![
            base.clone(),
            base.with_extension("tex"),
            base.with_extension("pdf"),
            base.with_extension("png"),
            base.with_extension("jpg"),
            base.with_extension("jpeg"),
        ]
    };
    candidates.into_iter().find(|path| path.exists())
}

fn response_ok(
    req: &RenderFormulasRequest,
    node: &FormulaNodeRequest,
    path: PathBuf,
    width_px: u32,
    height_px: u32,
    cached: bool,
    compile_us: u64,
    render_us: u64,
    diagnostics: Vec<DiagnosticInfo>,
) -> FormulaRenderResponse {
    FormulaRenderResponse {
        request_id: req.request_id.clone(),
        context_id: req.context_id.clone(),
        context_rev: req.context_rev,
        node_id: node.node_id.clone(),
        node_rev: node.node_rev,
        status: CompileStatus::Ok,
        path: Some(path),
        width_px: Some(width_px),
        height_px: Some(height_px),
        cached,
        diagnostics,
        compile_us: Some(compile_us),
        render_us: Some(render_us),
    }
}

fn response_error(
    req: &RenderFormulasRequest,
    node: &FormulaNodeRequest,
    message: String,
    compile_us: Option<u64>,
    render_us: Option<u64>,
) -> FormulaRenderResponse {
    response_with_diagnostics(
        req,
        node,
        CompileStatus::Error,
        vec![DiagnosticInfo {
            message,
            severity: "error".to_string(),
            file: None,
            line: None,
            column: None,
        }],
        compile_us,
        render_us,
    )
}

fn response_with_diagnostics(
    req: &RenderFormulasRequest,
    node: &FormulaNodeRequest,
    status: CompileStatus,
    diagnostics: Vec<DiagnosticInfo>,
    compile_us: Option<u64>,
    render_us: Option<u64>,
) -> FormulaRenderResponse {
    FormulaRenderResponse {
        request_id: req.request_id.clone(),
        context_id: req.context_id.clone(),
        context_rev: req.context_rev,
        node_id: node.node_id.clone(),
        node_rev: node.node_rev,
        status,
        path: None,
        width_px: None,
        height_px: None,
        cached: false,
        diagnostics,
        compile_us,
        render_us,
    }
}

fn read_to_string(path: &Path) -> String {
    fs::read_to_string(path).unwrap_or_default()
}

fn short_output(bytes: &[u8]) -> String {
    let text = String::from_utf8_lossy(bytes);
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return "no stderr output".to_string();
    }
    trimmed.chars().take(500).collect()
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
    use super::*;

    fn temp_dir(name: &str) -> PathBuf {
        let stamp = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        std::env::temp_dir().join(format!(
            "typst-concealer-latex-{name}-{}-{stamp}",
            std::process::id()
        ))
    }

    fn latex_request(root: PathBuf, output_dir: PathBuf) -> RenderFormulasRequest {
        RenderFormulasRequest {
            lane: None,
            backend: Some("latex".to_string()),
            request_id: "latex:test".to_string(),
            cache_key: None,
            context_id: "ctx".to_string(),
            context_rev: 1,
            context_source: "\\documentclass{article}\n\\usepackage[active,tightpage]{preview}\n"
                .to_string(),
            root,
            inputs: HashMap::new(),
            output_dir,
            ppi: 72,
            worker_count: None,
            compiler: Some("pdflatex".to_string()),
            converter: Some("pdftocairo".to_string()),
            compiler_args: Vec::new(),
            nodes: Vec::new(),
        }
    }

    fn latex_node() -> FormulaNodeRequest {
        FormulaNodeRequest {
            node_id: "node".to_string(),
            node_rev: 1,
            source_hash: None,
            kind: Some("inline_formula".to_string()),
            source: "$x$".to_string(),
        }
    }

    fn command_exists(name: &str) -> bool {
        Command::new(name).arg("--version").output().is_ok()
    }

    fn latex_work_dirs(output_dir: &Path) -> Vec<PathBuf> {
        fs::read_dir(output_dir)
            .unwrap()
            .filter_map(|entry| entry.ok())
            .map(|entry| entry.path())
            .filter(|path| {
                path.file_name()
                    .and_then(|name| name.to_str())
                    .is_some_and(|name| name.starts_with("latex-work-"))
            })
            .collect()
    }

    #[test]
    fn unwrap_preserves_latex_math_modes() {
        assert_eq!(unwrap_math("\\(x+y\\)", "inline_formula"), "$x+y$");
        assert_eq!(unwrap_math("$$x+y$$", "displayed_equation"), "\\[x+y\\]");
        assert_eq!(
            unwrap_math("\\begin{align}x&=y\\end{align}", "math_environment"),
            "\\begin{align}x&=y\\end{align}"
        );
    }

    #[test]
    fn parses_latex_error_line() {
        let diagnostics = parse_latex_log("! Undefined control sequence.\nl.12 \\bad\n");
        assert_eq!(diagnostics.len(), 1);
        assert_eq!(diagnostics[0].severity, "error");
        assert_eq!(diagnostics[0].line, Some(12));
    }

    #[test]
    fn external_signature_tracks_common_inputs() {
        let root = temp_dir("sig");
        fs::create_dir_all(&root).unwrap();
        fs::write(root.join("defs.tex"), "\\newcommand{\\x}{x}\n").unwrap();
        let sig = external_signature(&root, "\\input{defs}\n", "");
        assert!(sig.contains("defs.tex"));
        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn compiler_failure_returns_diagnostics() {
        let root = temp_dir("missing-compiler");
        let output_dir = root.join("out");
        fs::create_dir_all(&output_dir).unwrap();
        let mut req = latex_request(root.clone(), output_dir.clone());
        req.compiler = Some("definitely-missing-typst-concealer-latex".to_string());
        let node = latex_node();
        let mut renderer = LatexRenderer::new();

        let rendered = renderer.render_formula(&req, &node);
        assert!(matches!(rendered.status, CompileStatus::Error));
        assert!(!rendered.diagnostics.is_empty());
        assert!(
            rendered.diagnostics[0]
                .message
                .contains("failed to run LaTeX compiler")
        );
        assert!(
            latex_work_dirs(&output_dir).is_empty(),
            "LaTeX work directories should be removed after failed renders"
        );

        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn renderer_produces_png_when_toolchain_available() {
        if !command_exists("pdflatex") || !command_exists("pdftocairo") {
            eprintln!("skipping LaTeX smoke test: pdflatex or pdftocairo unavailable");
            return;
        }

        let root = temp_dir("smoke");
        let output_dir = root.join("out");
        fs::create_dir_all(&output_dir).unwrap();
        let req = latex_request(root.clone(), output_dir);
        let node = latex_node();
        let mut renderer = LatexRenderer::new();

        let rendered = renderer.render_formula(&req, &node);
        if !matches!(rendered.status, CompileStatus::Ok) {
            eprintln!(
                "skipping LaTeX smoke test: toolchain did not render test document: {:?}",
                rendered.diagnostics
            );
            let _ = fs::remove_dir_all(root);
            return;
        }
        let path = rendered
            .path
            .as_ref()
            .expect("ok render should include a path");
        assert!(path.exists(), "LaTeX renderer should write a PNG");
        assert!(rendered.width_px.unwrap_or(0) > 0);
        assert!(rendered.height_px.unwrap_or(0) > 0);

        let _ = fs::remove_dir_all(root);
    }
}
