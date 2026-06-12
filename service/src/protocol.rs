use std::collections::HashMap;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize)]
#[serde(tag = "type")]
pub enum IncomingMessage {
    #[serde(rename = "compile")]
    Compile(CompileRequest),
    #[serde(rename = "render_formulas")]
    RenderFormulas(RenderFormulasRequest),
    #[serde(rename = "shutdown")]
    Shutdown,
}

#[derive(Debug, Deserialize)]
pub struct CompileRequest {
    pub request_id: String,
    #[serde(default)]
    pub cache_key: Option<String>,
    pub source_text: String,
    pub root: PathBuf,
    #[serde(default)]
    pub inputs: HashMap<String, String>,
    pub output_dir: PathBuf,
    pub ppi: u32,
}

#[derive(Clone, Debug, Deserialize)]
pub struct RenderFormulasRequest {
    #[serde(default)]
    pub backend: Option<String>,
    pub request_id: String,
    #[serde(default)]
    pub cache_key: Option<String>,
    pub context_id: String,
    pub context_rev: u64,
    #[serde(default)]
    pub context_source: String,
    pub root: PathBuf,
    #[serde(default)]
    pub inputs: HashMap<String, String>,
    pub output_dir: PathBuf,
    pub ppi: u32,
    #[serde(default)]
    pub worker_count: Option<usize>,
    #[serde(default)]
    pub compiler: Option<String>,
    #[serde(default)]
    pub converter: Option<String>,
    #[serde(default)]
    pub compiler_args: Vec<String>,
    pub nodes: Vec<FormulaNodeRequest>,
}

#[derive(Clone, Debug, Deserialize)]
pub struct FormulaNodeRequest {
    pub node_id: String,
    pub node_rev: u64,
    #[serde(default)]
    pub source_hash: Option<String>,
    #[serde(default)]
    pub kind: Option<String>,
    pub source: String,
}

#[derive(Debug, Serialize)]
#[serde(tag = "type")]
pub enum OutgoingMessage {
    #[serde(rename = "compile_result")]
    CompileResult(CompileResponse),
    #[serde(rename = "formula_rendered")]
    FormulaRendered(FormulaRenderResponse),
}

#[derive(Debug, Serialize)]
pub struct CompileResponse {
    pub request_id: String,
    pub status: CompileStatus,
    pub pages: Vec<PageResult>,
    pub diagnostics: Vec<DiagnosticInfo>,
    /// Microseconds spent in typst::compile().
    #[serde(skip_serializing_if = "Option::is_none")]
    pub compile_us: Option<u64>,
    /// Microseconds spent rendering pages to PNG.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub render_us: Option<u64>,
    /// Number of pages that were re-rendered (not cached).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rendered_pages: Option<usize>,
}

#[derive(Debug, Serialize)]
pub enum CompileStatus {
    #[serde(rename = "ok")]
    Ok,
    #[serde(rename = "error")]
    Error,
}

#[derive(Debug, Serialize)]
pub struct PageResult {
    pub page_index: usize,
    pub path: PathBuf,
    pub width_px: u32,
    pub height_px: u32,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub cached: bool,
}

#[derive(Debug, Serialize)]
pub struct DiagnosticInfo {
    pub message: String,
    pub severity: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub file: Option<PathBuf>,
    pub line: Option<usize>,
    pub column: Option<usize>,
}

#[derive(Debug, Serialize)]
pub struct FormulaRenderResponse {
    pub request_id: String,
    pub context_id: String,
    pub context_rev: u64,
    pub node_id: String,
    pub node_rev: u64,
    pub status: CompileStatus,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub path: Option<PathBuf>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub width_px: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub height_px: Option<u32>,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub cached: bool,
    pub diagnostics: Vec<DiagnosticInfo>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub compile_us: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub render_us: Option<u64>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_latex_formula_request() {
        let req: IncomingMessage = serde_json::from_str(
            r#"{
              "type":"render_formulas",
              "backend":"latex",
              "request_id":"r1",
              "context_id":"ctx",
              "context_rev":1,
              "context_source":"\\documentclass{article}\n",
              "root":"/tmp",
              "output_dir":"/tmp/out",
              "ppi":144,
              "compiler":"pdflatex",
              "converter":"pdftocairo",
              "compiler_args":["-shell-escape"],
              "nodes":[{"node_id":"n1","node_rev":1,"kind":"inline_formula","source":"$x$"}]
            }"#,
        )
        .unwrap();

        match req {
            IncomingMessage::RenderFormulas(req) => {
                assert_eq!(req.backend.as_deref(), Some("latex"));
                assert_eq!(req.compiler.as_deref(), Some("pdflatex"));
                assert_eq!(req.converter.as_deref(), Some("pdftocairo"));
                assert_eq!(req.compiler_args, vec!["-shell-escape"]);
                assert_eq!(req.nodes[0].kind.as_deref(), Some("inline_formula"));
            }
            _ => panic!("expected render_formulas request"),
        }
    }
}
