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
    #[serde(rename = "render_code_flow")]
    RenderCodeFlow(RenderCodeFlowRequest),
    #[serde(rename = "reset_lane")]
    ResetLane(ResetLaneRequest),
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

#[derive(Debug, Deserialize)]
pub struct ResetLaneRequest {
    pub lane: String,
}

#[derive(Clone, Debug, Deserialize)]
pub struct RenderFormulasRequest {
    #[serde(default)]
    pub lane: Option<String>,
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

#[derive(Clone, Debug, Deserialize)]
pub struct RenderCodeFlowRequest {
    pub request_id: String,
    #[serde(default)]
    pub cache_key: Option<String>,
    pub context_id: String,
    pub context_rev: u64,
    #[serde(default)]
    pub context_source: String,
    #[serde(default)]
    pub flow_context_source: String,
    pub root: PathBuf,
    #[serde(default)]
    pub inputs: HashMap<String, String>,
    #[serde(default)]
    pub layout_width_pt: Option<f64>,
    #[serde(default)]
    pub layout_baseline_pt: Option<f64>,
    pub output_dir: PathBuf,
    pub ppi: u32,
    #[serde(default)]
    pub worker_count: Option<usize>,
    pub nodes: Vec<CodeFlowNodeRequest>,
}

#[derive(Clone, Debug, Deserialize)]
pub struct CodeFlowNodeRequest {
    pub node_id: String,
    pub node_rev: u64,
    #[serde(default)]
    pub source_hash: Option<String>,
    #[serde(default)]
    pub kind: Option<String>,
    pub flow_source: String,
    #[serde(default)]
    pub target_start: Option<usize>,
    #[serde(default)]
    pub target_end: Option<usize>,
    pub variants: CodeFlowVariants,
}

#[derive(Clone, Debug, Deserialize)]
pub struct CodeFlowVariants {
    pub inline: CodeFlowVariant,
    pub block: CodeFlowVariant,
}

#[derive(Clone, Debug, Deserialize)]
pub struct CodeFlowVariant {
    pub source: String,
    #[serde(default)]
    pub source_hash: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(tag = "type")]
pub enum OutgoingMessage {
    #[serde(rename = "compile_result")]
    CompileResult(CompileResponse),
    #[serde(rename = "formula_rendered")]
    FormulaRendered(FormulaRenderResponse),
    #[serde(rename = "code_flow_rendered")]
    CodeFlowRendered(CodeFlowRenderResponse),
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

#[derive(Debug, Copy, Clone, Serialize)]
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

#[derive(Debug, Serialize)]
pub struct CodeFlowRenderResponse {
    pub request_id: String,
    pub context_id: String,
    pub context_rev: u64,
    pub node_id: String,
    pub node_rev: u64,
    pub flow_status: CompileStatus,
    pub render_status: CompileStatus,
    pub flow_role: FlowRole,
    pub layout_role: FlowRole,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub layout_break: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub layout_reason: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub render_policy: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub selected_variant: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub selected_variant_hash: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub path: Option<PathBuf>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub width_px: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub height_px: Option<u32>,
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub cached: bool,
    pub flow_diagnostics: Vec<DiagnosticInfo>,
    pub render_diagnostics: Vec<DiagnosticInfo>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub flow_compile_us: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub render_compile_us: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub render_us: Option<u64>,
}

#[derive(Debug, Copy, Clone, Serialize)]
pub enum FlowRole {
    #[serde(rename = "inline")]
    Inline,
    #[serde(rename = "block")]
    Block,
    #[serde(rename = "unknown")]
    Unknown,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_preview_lane_reset() {
        let req: IncomingMessage =
            serde_json::from_str(r#"{"type":"reset_lane","lane":"preview"}"#).unwrap();
        match req {
            IncomingMessage::ResetLane(req) => assert_eq!(req.lane, "preview"),
            _ => panic!("expected reset_lane request"),
        }
    }

    #[test]
    fn decodes_preview_formula_lane() {
        let req: IncomingMessage = serde_json::from_str(
            r##"{
              "type":"render_formulas",
              "lane":"preview",
              "request_id":"preview:1",
              "context_id":"ctx",
              "context_rev":1,
              "root":"/tmp",
              "output_dir":"/tmp/out",
              "ppi":144,
              "nodes":[]
            }"##,
        )
        .unwrap();

        match req {
            IncomingMessage::RenderFormulas(req) => {
                assert_eq!(req.lane.as_deref(), Some("preview"));
            }
            _ => panic!("expected render_formulas request"),
        }
    }

    #[test]
    fn decodes_latex_formula_request() {
        let req: IncomingMessage = serde_json::from_str(
            r##"{
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
            }"##,
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

    #[test]
    fn decodes_code_flow_render_request() {
        let req: IncomingMessage = serde_json::from_str(
            r##"{
              "type":"render_code_flow",
              "request_id":"r-code",
              "context_id":"ctx",
              "context_rev":1,
              "context_source":"#show strong: it => block(it.body)\n",
              "flow_context_source":"#show strong: it => block(it.body)\n",
              "root":"/tmp",
              "inputs":{},
              "output_dir":"/tmp/out",
              "ppi":144,
              "worker_count":2,
              "layout_width_pt":320.0,
              "layout_baseline_pt":11.0,
              "nodes":[{
                "node_id":"n1",
                "node_rev":3,
                "kind":"code",
                "flow_source":"#strong[hi]",
                "target_start":0,
                "target_end":11,
                "variants":{
                  "inline":{"source":"#strong[hi]\n","source_hash":"i"},
                  "block":{"source":"#strong[hi]\n","source_hash":"b"}
                }
              }]
            }"##,
        )
        .unwrap();

        match req {
            IncomingMessage::RenderCodeFlow(req) => {
                assert_eq!(req.request_id, "r-code");
                assert_eq!(
                    req.flow_context_source,
                    "#show strong: it => block(it.body)\n"
                );
                assert_eq!(req.nodes[0].flow_source, "#strong[hi]");
                assert_eq!(
                    req.nodes[0].variants.inline.source_hash.as_deref(),
                    Some("i")
                );
            }
            _ => panic!("expected render_code_flow request"),
        }
    }

    #[test]
    fn rejects_legacy_classify_flow_request() {
        let err = serde_json::from_str::<IncomingMessage>(
            r#"{
              "type":"classify_flow",
              "request_id":"legacy",
              "context_id":"ctx",
              "context_rev":1,
              "root":"/tmp",
              "nodes":[]
            }"#,
        )
        .unwrap_err();

        assert!(err.to_string().contains("classify_flow"), "{err}");
    }
}
