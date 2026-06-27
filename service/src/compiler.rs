use std::collections::HashMap;
use std::fs;
use std::hash::{DefaultHasher, Hash, Hasher};
use std::path::{Path, PathBuf};
use std::time::Instant;

use comemo::Track;
use image::codecs::png::{CompressionType, FilterType, PngEncoder};
use image::{ColorType, ImageEncoder};
use typst::diag::{Severity, SourceDiagnostic};
use typst::engine::{Engine, Route, Sink, Traced};
use typst::foundations::{
    Content, Label, SequenceElem, Str, StyleChain, StyledElem, Styles, Target, TargetElem, Value,
};
use typst::introspection::{Introspector, Locator, MetadataElem};
use typst::layout::PagedDocument;
use typst::routines::{Arenas, FragmentKind, RealizationKind};
use typst::syntax::{LinkedNode, Side, Source, Span, ast};
use typst::{Document, World};

use crate::protocol::{
    CodeFlowNodeRequest, CodeFlowRenderResponse, CompileRequest, CompileResponse, CompileStatus,
    DiagnosticInfo, FlowRole, FormulaNodeRequest, FormulaRenderResponse, PageResult,
    RenderCodeFlowRequest, RenderFormulasRequest,
};
use crate::world::ConcealerWorld;

const FLOW_TARGET_MARKER: &str = "__math_conceal_flow_target__";
const FLOW_LAYOUT_BEFORE_LABEL: &str = "__math_conceal_layout_before__";
const FLOW_LAYOUT_AFTER_LABEL: &str = "__math_conceal_layout_after__";

struct FlowClassifyDocument {
    source_text: String,
    node_start: usize,
    node_end: usize,
}

struct FlowLayoutClassification {
    role: FlowRole,
    breaks: bool,
    reason: Option<String>,
    diagnostics: Vec<DiagnosticInfo>,
}

struct FlowClassificationResult {
    status: CompileStatus,
    flow_role: FlowRole,
    layout_role: FlowRole,
    layout_break: bool,
    layout_reason: Option<String>,
    diagnostics: Vec<DiagnosticInfo>,
    compile_us: Option<u64>,
}

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

    fn classify_code_flow(
        &mut self,
        req: &RenderCodeFlowRequest,
        node: &CodeFlowNodeRequest,
    ) -> FlowClassificationResult {
        let _cache_identity = (&node.source_hash, &node.kind);
        let flow_context_source = code_flow_context_source(req);
        let document = build_flow_classify_document(
            flow_context_source,
            &node.flow_source,
            node.target_start,
            node.target_end,
        );
        let node_start = document.node_start;
        let node_end = document.node_end;
        self.world
            .update(document.source_text, req.root.clone(), req.inputs.clone());
        comemo::evict(30);

        let t_compile = Instant::now();
        let mut sink = Sink::new();
        let result = self.classify_current_world_flow(node_start, node_end, &mut sink);

        match result {
            Ok(kind) => {
                let warnings = sink.warnings();
                let flow_role = match kind {
                    FragmentKind::Inline => FlowRole::Inline,
                    FragmentKind::Block => FlowRole::Block,
                };
                let mut diagnostics = self.format_diagnostics(warnings.iter());
                let layout = self.classify_flow_layout(req, node, flow_role);
                diagnostics.extend(layout.diagnostics);
                let compile_us = t_compile.elapsed().as_micros() as u64;
                FlowClassificationResult {
                    status: CompileStatus::Ok,
                    flow_role,
                    layout_role: layout.role,
                    layout_break: layout.breaks,
                    layout_reason: layout.reason,
                    diagnostics,
                    compile_us: Some(compile_us),
                }
            }
            Err(mut diagnostics) => {
                let warnings = sink.warnings();
                diagnostics.splice(0..0, self.format_diagnostics(warnings.iter()));
                let compile_us = t_compile.elapsed().as_micros() as u64;
                FlowClassificationResult {
                    status: CompileStatus::Error,
                    flow_role: FlowRole::Unknown,
                    layout_role: FlowRole::Unknown,
                    layout_break: false,
                    layout_reason: None,
                    diagnostics,
                    compile_us: Some(compile_us),
                }
            }
        }
    }

    fn classify_current_world_flow(
        &self,
        node_start: usize,
        node_end: usize,
        sink: &mut Sink,
    ) -> Result<FragmentKind, Vec<DiagnosticInfo>> {
        let world = (&self.world as &dyn World).track();
        let main = self.world.main();
        let main_source = self.world.source(main).map_err(|err| {
            vec![DiagnosticInfo {
                message: format!("failed to read classifier source: {err}"),
                severity: "error".to_string(),
                file: None,
                line: None,
                column: None,
            }]
        })?;

        let Some(target_span) = find_target_expr_span(&main_source, node_start, node_end) else {
            return Err(vec![DiagnosticInfo {
                message: "failed to locate target node expression in classifier source".to_string(),
                severity: "error".to_string(),
                file: None,
                line: None,
                column: None,
            }]);
        };

        let traced = Traced::new(target_span);
        let module = typst_eval::eval(
            &typst::ROUTINES,
            world,
            traced.track(),
            sink.track_mut(),
            Route::default().track(),
            &main_source,
        )
        .map_err(|errors| self.format_diagnostics(errors.iter()))?;

        let traced_values = sink.clone().values();
        let Some((value, _)) = traced_values.into_iter().next() else {
            return Err(vec![DiagnosticInfo {
                message: "failed to inspect target node value".to_string(),
                severity: "error".to_string(),
                file: None,
                line: None,
                column: None,
            }]);
        };

        let module_content = module.content();
        let active_styles = styles_at_marker(&module_content).ok_or_else(|| {
            vec![DiagnosticInfo {
                message: "failed to locate target style marker in classifier source".to_string(),
                severity: "error".to_string(),
                file: None,
                line: None,
                column: None,
            }]
        })?;

        let content = value.display();
        self.classify_content_flow(&content, &active_styles, sink)
    }

    fn classify_content_flow(
        &self,
        content: &Content,
        active_styles: &Styles,
        sink: &mut Sink,
    ) -> Result<FragmentKind, Vec<DiagnosticInfo>> {
        let world = (&self.world as &dyn World).track();
        let traced = Traced::default();
        let library = self.world.library();
        let base = StyleChain::new(&library.styles);
        let target = TargetElem::target.set(Target::Paged).wrap();
        let target_styles = base.chain(&target);
        let styles = target_styles.chain(active_styles);
        let introspector = Introspector::default();
        let mut engine = Engine {
            routines: &typst::ROUTINES,
            world,
            introspector: introspector.track(),
            traced: traced.track(),
            sink: sink.track_mut(),
            route: Route::default(),
        };
        let arenas = Arenas::default();
        let mut locator = Locator::root().split();
        let mut kind = FragmentKind::Block;

        (engine.routines.realize)(
            RealizationKind::LayoutFragment { kind: &mut kind },
            &mut engine,
            &mut locator,
            &arenas,
            content,
            styles,
        )
        .map_err(|errors| self.format_diagnostics(errors.iter()))?;

        Ok(kind)
    }

    fn classify_flow_layout(
        &mut self,
        req: &RenderCodeFlowRequest,
        node: &CodeFlowNodeRequest,
        flow_role: FlowRole,
    ) -> FlowLayoutClassification {
        if !matches!(flow_role, FlowRole::Inline) {
            return FlowLayoutClassification {
                role: flow_role,
                breaks: false,
                reason: None,
                diagnostics: Vec::new(),
            };
        }

        let Some(width_pt) = req
            .layout_width_pt
            .filter(|width| width.is_finite() && *width > 0.0)
        else {
            return FlowLayoutClassification {
                role: flow_role,
                breaks: false,
                reason: None,
                diagnostics: Vec::new(),
            };
        };
        let baseline_pt = req
            .layout_baseline_pt
            .filter(|baseline| baseline.is_finite() && *baseline > 0.0)
            .unwrap_or(11.0);

        let document = build_flow_layout_document(
            code_flow_context_source(req),
            &node.flow_source,
            node.target_start,
            node.target_end,
            width_pt,
            baseline_pt,
        );
        self.world
            .update(document.source_text, req.root.clone(), req.inputs.clone());
        comemo::evict(30);

        let warned = typst::compile::<PagedDocument>(&self.world);
        let mut diagnostics = self.format_diagnostics(warned.warnings.iter());
        let document = match warned.output {
            Ok(document) => document,
            Err(errors) => {
                diagnostics.extend(self.format_diagnostics(errors.iter()));
                return FlowLayoutClassification {
                    role: FlowRole::Unknown,
                    breaks: false,
                    reason: Some("layout_probe_failed".to_string()),
                    diagnostics,
                };
            }
        };

        let Some(before) = labelled_position(&document, FLOW_LAYOUT_BEFORE_LABEL) else {
            diagnostics.push(DiagnosticInfo {
                message: "failed to locate flow layout before marker".to_string(),
                severity: "warning".to_string(),
                file: None,
                line: None,
                column: None,
            });
            return FlowLayoutClassification {
                role: FlowRole::Unknown,
                breaks: false,
                reason: Some("layout_probe_missing_marker".to_string()),
                diagnostics,
            };
        };
        let Some(after) = labelled_position(&document, FLOW_LAYOUT_AFTER_LABEL) else {
            diagnostics.push(DiagnosticInfo {
                message: "failed to locate flow layout after marker".to_string(),
                severity: "warning".to_string(),
                file: None,
                line: None,
                column: None,
            });
            return FlowLayoutClassification {
                role: FlowRole::Unknown,
                breaks: false,
                reason: Some("layout_probe_missing_marker".to_string()),
                diagnostics,
            };
        };

        let y_delta = (after.point.y - before.point.y).abs().to_pt();
        let page_break = after.page != before.page;
        if page_break || y_delta > 0.1 {
            FlowLayoutClassification {
                role: FlowRole::Block,
                breaks: true,
                reason: Some("layout_probe_break".to_string()),
                diagnostics,
            }
        } else {
            FlowLayoutClassification {
                role: FlowRole::Inline,
                breaks: false,
                reason: None,
                diagnostics,
            }
        }
    }

    pub fn render_code_flow(
        &mut self,
        req: &RenderCodeFlowRequest,
        node: &CodeFlowNodeRequest,
    ) -> CodeFlowRenderResponse {
        let flow = self.classify_code_flow(req, node);
        if !matches!(flow.status, CompileStatus::Ok)
            || !matches!(flow.layout_role, FlowRole::Inline | FlowRole::Block)
        {
            return CodeFlowRenderResponse {
                request_id: req.request_id.clone(),
                context_id: req.context_id.clone(),
                context_rev: req.context_rev,
                node_id: node.node_id.clone(),
                node_rev: node.node_rev,
                flow_status: flow.status,
                render_status: CompileStatus::Error,
                flow_role: flow.flow_role,
                layout_role: flow.layout_role,
                layout_break: flow.layout_break,
                layout_reason: flow.layout_reason,
                render_policy: None,
                selected_variant: None,
                selected_variant_hash: None,
                path: None,
                width_px: None,
                height_px: None,
                cached: false,
                flow_diagnostics: flow.diagnostics,
                render_diagnostics: Vec::new(),
                flow_compile_us: flow.compile_us,
                render_compile_us: None,
                render_us: None,
            };
        }

        let (selected_variant, render_policy, variant) = match (flow.flow_role, flow.layout_role) {
            (FlowRole::Inline, FlowRole::Inline) => {
                ("inline", "inline_naturalized", &node.variants.inline)
            }
            (FlowRole::Inline, FlowRole::Block) => {
                ("block", "block_constrained", &node.variants.block)
            }
            (FlowRole::Block, FlowRole::Block) => ("block", "block", &node.variants.block),
            _ => {
                return CodeFlowRenderResponse {
                    request_id: req.request_id.clone(),
                    context_id: req.context_id.clone(),
                    context_rev: req.context_rev,
                    node_id: node.node_id.clone(),
                    node_rev: node.node_rev,
                    flow_status: flow.status,
                    render_status: CompileStatus::Error,
                    flow_role: flow.flow_role,
                    layout_role: flow.layout_role,
                    layout_break: flow.layout_break,
                    layout_reason: flow.layout_reason,
                    render_policy: None,
                    selected_variant: None,
                    selected_variant_hash: None,
                    path: None,
                    width_px: None,
                    height_px: None,
                    cached: false,
                    flow_diagnostics: flow.diagnostics,
                    render_diagnostics: Vec::new(),
                    flow_compile_us: flow.compile_us,
                    render_compile_us: None,
                    render_us: None,
                };
            }
        };

        let render_req = RenderFormulasRequest {
            backend: None,
            request_id: req.request_id.clone(),
            cache_key: req.cache_key.clone(),
            context_id: req.context_id.clone(),
            context_rev: req.context_rev,
            context_source: req.context_source.clone(),
            root: req.root.clone(),
            inputs: req.inputs.clone(),
            output_dir: req.output_dir.clone(),
            ppi: req.ppi,
            worker_count: None,
            compiler: None,
            converter: None,
            compiler_args: Vec::new(),
            nodes: Vec::new(),
        };
        let render_node = FormulaNodeRequest {
            node_id: node.node_id.clone(),
            node_rev: node.node_rev,
            source_hash: variant.source_hash.clone(),
            kind: Some("code_flow".to_string()),
            source: variant.source.clone(),
        };
        let rendered = self.render_formula(&render_req, &render_node);

        CodeFlowRenderResponse {
            request_id: req.request_id.clone(),
            context_id: req.context_id.clone(),
            context_rev: req.context_rev,
            node_id: node.node_id.clone(),
            node_rev: node.node_rev,
            flow_status: flow.status,
            render_status: rendered.status,
            flow_role: flow.flow_role,
            layout_role: flow.layout_role,
            layout_break: flow.layout_break,
            layout_reason: flow.layout_reason,
            render_policy: Some(render_policy.to_string()),
            selected_variant: Some(selected_variant.to_string()),
            selected_variant_hash: variant.source_hash.clone(),
            path: rendered.path,
            width_px: rendered.width_px,
            height_px: rendered.height_px,
            cached: rendered.cached,
            flow_diagnostics: flow.diagnostics,
            render_diagnostics: rendered.diagnostics,
            flow_compile_us: flow.compile_us,
            render_compile_us: rendered.compile_us,
            render_us: rendered.render_us,
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

fn code_flow_context_source(req: &RenderCodeFlowRequest) -> &str {
    if req.flow_context_source.is_empty() {
        &req.context_source
    } else {
        &req.flow_context_source
    }
}

fn build_flow_classify_document(
    context_source: &str,
    node_source: &str,
    target_start: Option<usize>,
    target_end: Option<usize>,
) -> FlowClassifyDocument {
    let mut source = String::new();
    let context_source = context_source.trim_end();
    if !context_source.is_empty() {
        source.push_str(context_source);
        source.push('\n');
    }

    let target_start = clamp_char_boundary(node_source, target_start.unwrap_or(0));
    let target_end = clamp_char_boundary(node_source, target_end.unwrap_or(node_source.len()));
    let (target_start, target_end) = if target_start <= target_end {
        (target_start, target_end)
    } else {
        (target_end, target_end)
    };

    source.push_str(&node_source[..target_start]);
    source.push_str("#metadata(\"");
    source.push_str(FLOW_TARGET_MARKER);
    source.push_str("\")\n");
    let node_start = source.len();
    source.push_str(&node_source[target_start..target_end]);
    let node_end = source.len();
    source.push_str(&node_source[target_end..]);
    if !node_source.ends_with('\n') {
        source.push('\n');
    }

    FlowClassifyDocument {
        source_text: source,
        node_start,
        node_end,
    }
}

fn build_flow_layout_document(
    context_source: &str,
    node_source: &str,
    target_start: Option<usize>,
    target_end: Option<usize>,
    width_pt: f64,
    baseline_pt: f64,
) -> FlowClassifyDocument {
    let mut source = String::new();
    let context_source = context_source.trim_end();
    if !context_source.is_empty() {
        source.push_str(context_source);
        source.push('\n');
    }
    source.push_str(&format!(
        "#set page(width: {width_pt}pt, height: auto, margin: (x: 0pt, y: 0pt), fill: none)\n#set text(size: {baseline_pt}pt)\n"
    ));

    let target_start = clamp_char_boundary(node_source, target_start.unwrap_or(0));
    let target_end = clamp_char_boundary(node_source, target_end.unwrap_or(node_source.len()));
    let (target_start, target_end) = if target_start <= target_end {
        (target_start, target_end)
    } else {
        (target_end, target_end)
    };

    if let Some(line_start) = node_source[..target_start].rfind('\n') {
        source.push_str(&node_source[..=line_start]);
    }
    source.push_str("x #box(width: 0pt)[#metadata(\"");
    source.push_str(FLOW_LAYOUT_BEFORE_LABEL);
    source.push_str("\") <");
    source.push_str(FLOW_LAYOUT_BEFORE_LABEL);
    source.push_str(">]");
    let node_start = source.len();
    source.push_str(&node_source[target_start..target_end]);
    let node_end = source.len();
    source.push_str("#metadata(\"");
    source.push_str(FLOW_LAYOUT_AFTER_LABEL);
    source.push_str("\") <");
    source.push_str(FLOW_LAYOUT_AFTER_LABEL);
    source.push('>');
    source.push('\n');

    FlowClassifyDocument {
        source_text: source,
        node_start,
        node_end,
    }
}

fn clamp_char_boundary(source: &str, offset: usize) -> usize {
    let mut offset = offset.min(source.len());
    while offset > 0 && !source.is_char_boundary(offset) {
        offset -= 1;
    }
    offset
}

fn labelled_position(document: &PagedDocument, label: &str) -> Option<typst::layout::Position> {
    let label = Label::construct(Str::from(label)).ok()?;
    let content = document.introspector().query_label(label).ok()?;
    let location = content.location()?;
    Some(document.introspector().position(location))
}

fn find_target_expr_span(source: &Source, node_start: usize, node_end: usize) -> Option<Span> {
    if node_start >= node_end {
        return None;
    }

    let root = LinkedNode::new(source.root());
    for cursor in node_start..node_end {
        if let Some(span) = find_target_expr_span_from_cursor(&root, cursor, node_start, node_end) {
            return Some(span);
        }
    }

    None
}

fn find_target_expr_span_from_cursor(
    root: &LinkedNode,
    cursor: usize,
    node_start: usize,
    node_end: usize,
) -> Option<Span> {
    let mut node = root.leaf_at(cursor, Side::After)?;
    let mut best = None;
    loop {
        let range = node.range();
        if range.start >= node_start
            && range.end <= node_end
            && node.get().cast::<ast::Expr>().is_some()
        {
            best = Some(node.span());
        }

        let Some(parent) = node.parent().cloned() else {
            break;
        };
        node = parent;
    }

    best
}

fn styles_at_marker(content: &Content) -> Option<Styles> {
    find_marker_styles(content, &Styles::new())
}

fn find_marker_styles(content: &Content, active_styles: &Styles) -> Option<Styles> {
    if is_flow_marker(content) {
        return Some(active_styles.clone());
    }

    if let Some(styled) = content.to_packed::<StyledElem>() {
        let mut child_styles = styled.styles.clone();
        child_styles.apply(active_styles.clone());
        return find_marker_styles(&styled.child, &child_styles);
    }

    if let Some(sequence) = content.to_packed::<SequenceElem>() {
        for child in &sequence.children {
            if let Some(styles) = find_marker_styles(child, active_styles) {
                return Some(styles);
            }
        }
    }

    None
}

fn is_flow_marker(content: &Content) -> bool {
    let Some(metadata) = content.to_packed::<MetadataElem>() else {
        return false;
    };
    matches!(&metadata.value, Value::Str(value) if value.as_str() == FLOW_TARGET_MARKER)
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

    use crate::protocol::{CodeFlowVariant, CodeFlowVariants};

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

    fn code_flow_case(context_source: &str, source: &str) -> CodeFlowRenderResponse {
        code_flow_case_with_target(context_source, source, None, None)
    }

    fn code_flow_case_with_target(
        context_source: &str,
        source: &str,
        target_start: Option<usize>,
        target_end: Option<usize>,
    ) -> CodeFlowRenderResponse {
        code_flow_case_with_layout(context_source, source, target_start, target_end, None)
    }

    fn code_flow_case_with_layout(
        context_source: &str,
        source: &str,
        target_start: Option<usize>,
        target_end: Option<usize>,
        layout_width_pt: Option<f64>,
    ) -> CodeFlowRenderResponse {
        let root = temp_dir("code-flow-root");
        let variant_source = source.to_string();
        let req = RenderCodeFlowRequest {
            request_id: "flow:test".to_string(),
            cache_key: None,
            context_id: "ctx".to_string(),
            context_rev: 1,
            context_source: context_source.to_string(),
            flow_context_source: context_source.to_string(),
            root: root.clone(),
            inputs: HashMap::new(),
            layout_width_pt,
            layout_baseline_pt: Some(11.0),
            output_dir: root.join("out"),
            ppi: 72,
            worker_count: None,
            nodes: Vec::new(),
        };
        let node = CodeFlowNodeRequest {
            node_id: "node".to_string(),
            node_rev: 1,
            source_hash: None,
            kind: Some("code".to_string()),
            flow_source: source.to_string(),
            target_start,
            target_end,
            variants: CodeFlowVariants {
                inline: CodeFlowVariant {
                    source: variant_source.clone(),
                    source_hash: None,
                },
                block: CodeFlowVariant {
                    source: variant_source,
                    source_hash: None,
                },
            },
        };

        let mut compiler = Compiler::new();
        let resp = compiler.render_code_flow(&req, &node);
        let _ = fs::remove_dir_all(root);
        resp
    }

    #[test]
    fn flow_classifier_uses_target_node_not_whole_context_document() {
        let resp = code_flow_case(
            "#let chip() = box[GEOMETRY]\n\n#let tag = (geometry: chip())\n",
            "#tag.geometry",
        );

        assert!(matches!(&resp.flow_status, CompileStatus::Ok), "{resp:?}");
        assert!(matches!(resp.flow_role, FlowRole::Inline), "{resp:?}");
    }

    #[test]
    fn flow_classifier_uses_target_range_inside_node_source() {
        let source = "#let chip() = box[GEOMETRY]\n\n#let tag = (geometry: chip())\n#tag.geometry";
        let target_start = source.find("#tag.geometry").unwrap();
        let resp = code_flow_case_with_target(
            "",
            source,
            Some(target_start),
            Some(target_start + "#tag.geometry".len()),
        );

        assert!(matches!(&resp.flow_status, CompileStatus::Ok), "{resp:?}");
        assert!(matches!(resp.flow_role, FlowRole::Inline), "{resp:?}");
    }

    #[test]
    fn flow_classifier_respects_selector_show_rules_at_target_position() {
        let resp = code_flow_case("#show strong: it => block(it.body)\n", "#strong[hi]");

        assert!(matches!(&resp.flow_status, CompileStatus::Ok), "{resp:?}");
        assert!(matches!(resp.flow_role, FlowRole::Block), "{resp:?}");
        assert_eq!(resp.selected_variant.as_deref(), Some("block"));
        assert_eq!(resp.render_policy.as_deref(), Some("block"));
    }

    #[test]
    fn flow_classifier_distinguishes_inline_and_block_values() {
        let inline = code_flow_case("", "#box[hi]");
        assert!(
            matches!(&inline.flow_status, CompileStatus::Ok),
            "{inline:?}"
        );
        assert!(
            matches!(&inline.render_status, CompileStatus::Ok),
            "{inline:?}"
        );
        assert!(matches!(inline.flow_role, FlowRole::Inline), "{inline:?}");
        assert_eq!(inline.selected_variant.as_deref(), Some("inline"));
        assert_eq!(inline.render_policy.as_deref(), Some("inline_naturalized"));

        let block = code_flow_case("", "#block[hi]");
        assert!(matches!(&block.flow_status, CompileStatus::Ok), "{block:?}");
        assert!(
            matches!(&block.render_status, CompileStatus::Ok),
            "{block:?}"
        );
        assert!(matches!(block.flow_role, FlowRole::Block), "{block:?}");
        assert_eq!(block.selected_variant.as_deref(), Some("block"));
        assert_eq!(block.render_policy.as_deref(), Some("block"));

        let let_block = code_flow_case("#let b = block[hi]\n", "#b");
        assert!(
            matches!(&let_block.flow_status, CompileStatus::Ok),
            "{let_block:?}"
        );
        assert!(
            matches!(let_block.flow_role, FlowRole::Block),
            "{let_block:?}"
        );
    }

    #[test]
    fn code_flow_render_uses_render_context_source() {
        let root = temp_dir("code-flow-render-context");
        let req = RenderCodeFlowRequest {
            request_id: "flow:test".to_string(),
            cache_key: None,
            context_id: "ctx".to_string(),
            context_rev: 1,
            context_source:
                "#set page(width: auto, height: auto, margin: (x: 0pt, y: 0pt), fill: none)\n"
                    .to_string(),
            flow_context_source: String::new(),
            root: root.clone(),
            inputs: HashMap::new(),
            layout_width_pt: None,
            layout_baseline_pt: Some(11.0),
            output_dir: root.join("out"),
            ppi: 72,
            worker_count: None,
            nodes: Vec::new(),
        };
        let node = CodeFlowNodeRequest {
            node_id: "node".to_string(),
            node_rev: 1,
            source_hash: None,
            kind: Some("code".to_string()),
            flow_source: "#box[hi]".to_string(),
            target_start: None,
            target_end: None,
            variants: CodeFlowVariants {
                inline: CodeFlowVariant {
                    source: "#box[hi]".to_string(),
                    source_hash: None,
                },
                block: CodeFlowVariant {
                    source: "#box[hi]".to_string(),
                    source_hash: None,
                },
            },
        };

        let mut compiler = Compiler::new();
        let resp = compiler.render_code_flow(&req, &node);
        let _ = fs::remove_dir_all(root);

        assert!(matches!(&resp.flow_status, CompileStatus::Ok), "{resp:?}");
        assert!(matches!(&resp.render_status, CompileStatus::Ok), "{resp:?}");
        assert_eq!(resp.selected_variant.as_deref(), Some("inline"));
        assert!(
            resp.width_px.unwrap_or(u32::MAX) < 200,
            "render context page setup was not applied: {resp:?}"
        );
    }

    #[test]
    fn flow_layout_probe_promotes_full_width_inline_box_after_prefix() {
        let source = "Hello #box(width: 100%)[hello, test]";
        let target_start = source.find("#box").unwrap();
        let resp = code_flow_case_with_layout(
            "",
            source,
            Some(target_start),
            Some(source.len()),
            Some(100.0),
        );

        assert!(matches!(&resp.flow_status, CompileStatus::Ok), "{resp:?}");
        assert!(matches!(resp.flow_role, FlowRole::Inline), "{resp:?}");
        assert!(matches!(resp.layout_role, FlowRole::Block), "{resp:?}");
        assert!(resp.layout_break, "{resp:?}");
        assert_eq!(resp.selected_variant.as_deref(), Some("block"));
        assert_eq!(resp.render_policy.as_deref(), Some("block_constrained"));
    }

    #[test]
    fn flow_layout_probe_keeps_small_relative_width_inline_box_on_same_line() {
        let source = "x #box(width: 1%)[hi]";
        let target_start = source.find("#box").unwrap();
        let resp = code_flow_case_with_layout(
            "",
            source,
            Some(target_start),
            Some(source.len()),
            Some(100.0),
        );

        assert!(matches!(&resp.flow_status, CompileStatus::Ok), "{resp:?}");
        assert!(matches!(resp.flow_role, FlowRole::Inline), "{resp:?}");
        assert!(matches!(resp.layout_role, FlowRole::Inline), "{resp:?}");
        assert!(!resp.layout_break, "{resp:?}");
    }

    #[test]
    fn flow_layout_probe_promotes_full_width_inline_box_at_line_start() {
        let source = "#box(width: 100%)[hi]";
        let resp = code_flow_case_with_layout("", source, Some(0), Some(source.len()), Some(100.0));

        assert!(matches!(&resp.flow_status, CompileStatus::Ok), "{resp:?}");
        assert!(matches!(resp.flow_role, FlowRole::Inline), "{resp:?}");
        assert!(matches!(resp.layout_role, FlowRole::Block), "{resp:?}");
        assert!(resp.layout_break, "{resp:?}");
        assert_eq!(resp.layout_reason.as_deref(), Some("layout_probe_break"));
    }

    #[test]
    fn flow_layout_probe_promotes_multiline_full_width_inline_box_at_line_start() {
        let source = "#box(width: 100%)[hi\n  $ sin(alpha) $\n  hello]";
        let resp = code_flow_case_with_layout("", source, Some(0), Some(source.len()), Some(100.0));

        assert!(matches!(&resp.flow_status, CompileStatus::Ok), "{resp:?}");
        assert!(matches!(resp.flow_role, FlowRole::Inline), "{resp:?}");
        assert!(matches!(resp.layout_role, FlowRole::Block), "{resp:?}");
        assert!(resp.layout_break, "{resp:?}");
        assert_eq!(resp.layout_reason.as_deref(), Some("layout_probe_break"));
    }

    #[test]
    fn flow_layout_probe_keeps_auto_width_inline_box_on_same_line() {
        let source = "Hello #box(width: auto)[hello, test]";
        let target_start = source.find("#box").unwrap();
        let resp = code_flow_case_with_layout(
            "",
            source,
            Some(target_start),
            Some(source.len()),
            Some(100.0),
        );

        assert!(matches!(&resp.flow_status, CompileStatus::Ok), "{resp:?}");
        assert!(matches!(resp.flow_role, FlowRole::Inline), "{resp:?}");
        assert!(matches!(resp.layout_role, FlowRole::Inline), "{resp:?}");
        assert!(!resp.layout_break, "{resp:?}");
    }

    #[test]
    fn flow_layout_probe_keeps_multiline_text_call_inline() {
        let source = "#text[\n  hello\n] world";
        let target_end = source.find(" world").unwrap();
        let resp = code_flow_case_with_layout("", source, Some(0), Some(target_end), Some(1000.0));

        assert!(matches!(&resp.flow_status, CompileStatus::Ok), "{resp:?}");
        assert!(matches!(resp.flow_role, FlowRole::Inline), "{resp:?}");
        assert!(matches!(resp.layout_role, FlowRole::Inline), "{resp:?}");
        assert!(!resp.layout_break, "{resp:?}");
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
