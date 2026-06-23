mod compiler;
mod latex;
mod protocol;
mod world;

use std::collections::{HashMap, VecDeque};
use std::io::{self, BufRead, Write};
use std::sync::{Arc, Mutex, mpsc};
use std::thread;

use compiler::Compiler;
use latex::LatexRenderer;
use protocol::{
    ClassifyFlowRequest, FlowClassifyResponse, FlowNodeRequest, FormulaNodeRequest,
    FormulaRenderResponse, IncomingMessage, OutgoingMessage, RenderFormulasRequest,
};

const MAX_COMPILERS: usize = 16;
const MAX_FORMULA_WORKERS: usize = 8;

struct CachedCompiler {
    compiler: Compiler,
    last_used: u64,
}

#[derive(Clone)]
struct FlowTask {
    node: FlowNodeRequest,
    cache_key: String,
    last_used: u64,
}

#[derive(Clone)]
struct FormulaTask {
    node: FormulaNodeRequest,
    cache_key: String,
    last_used: u64,
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let stdin = io::stdin();
    let mut stdout = io::BufWriter::new(io::stdout());
    let mut compilers: HashMap<String, CachedCompiler> = HashMap::new();
    let mut latex_renderer = LatexRenderer::new();
    let mut use_clock: u64 = 0;

    for line in stdin.lock().lines() {
        let line = line?;
        if line.trim().is_empty() {
            continue;
        }

        let msg: IncomingMessage = match serde_json::from_str(&line) {
            Ok(msg) => msg,
            Err(err) => {
                eprintln!("failed to decode request: {err}");
                continue;
            }
        };

        match msg {
            IncomingMessage::Compile(req) => {
                let cache_key = req
                    .cache_key
                    .clone()
                    .unwrap_or_else(|| "default".to_string());
                use_clock = use_clock.saturating_add(1);
                let compiler =
                    compilers
                        .entry(cache_key.clone())
                        .or_insert_with(|| CachedCompiler {
                            compiler: Compiler::new(),
                            last_used: use_clock,
                        });
                compiler.last_used = use_clock;
                let resp = compiler.compiler.compile(req);
                evict_stale_compilers(&mut compilers, &cache_key);
                serde_json::to_writer(&mut stdout, &OutgoingMessage::CompileResult(resp))?;
                stdout.write_all(b"\n")?;
                stdout.flush()?;
            }
            IncomingMessage::RenderFormulas(req) => {
                if req.backend.as_deref() == Some("latex") {
                    render_latex_formulas(&mut stdout, req, &mut latex_renderer)?;
                } else if formula_worker_count(&req) <= 1 {
                    render_formulas_sequential(&mut stdout, req, &mut compilers, &mut use_clock)?;
                } else {
                    render_formulas_parallel(&mut stdout, req, &mut compilers, &mut use_clock)?;
                }
            }
            IncomingMessage::ClassifyFlow(req) => {
                if req.nodes.len() <= 1 {
                    classify_flow_sequential(&mut stdout, req, &mut compilers, &mut use_clock)?;
                } else {
                    classify_flow_parallel(&mut stdout, req, &mut compilers, &mut use_clock)?;
                }
            }
            IncomingMessage::Shutdown => break,
        }
    }

    Ok(())
}

fn classify_flow_sequential(
    stdout: &mut impl Write,
    req: ClassifyFlowRequest,
    compilers: &mut HashMap<String, CachedCompiler>,
    use_clock: &mut u64,
) -> Result<(), Box<dyn std::error::Error>> {
    let base_cache_key = flow_base_cache_key(&req);
    let mut active_keys = Vec::new();

    for node in &req.nodes {
        let cache_key = flow_node_cache_key(&base_cache_key, node);
        active_keys.push(cache_key.clone());
        *use_clock = (*use_clock).saturating_add(1);
        let compiler = compilers
            .entry(cache_key.clone())
            .or_insert_with(|| CachedCompiler {
                compiler: Compiler::new(),
                last_used: *use_clock,
            });
        compiler.last_used = *use_clock;
        let resp = compiler.compiler.classify_flow(&req, node);
        write_flow_response(stdout, resp)?;
    }

    evict_stale_compilers_except(compilers, &active_keys);
    Ok(())
}

fn classify_flow_parallel(
    stdout: &mut impl Write,
    req: ClassifyFlowRequest,
    compilers: &mut HashMap<String, CachedCompiler>,
    use_clock: &mut u64,
) -> Result<(), Box<dyn std::error::Error>> {
    let base_cache_key = flow_base_cache_key(&req);
    let tasks = flow_tasks(&req, &base_cache_key, use_clock);
    let active_keys: Vec<_> = tasks.iter().map(|task| task.cache_key.clone()).collect();
    let worker_count = MAX_FORMULA_WORKERS.min(tasks.len().max(1));
    let req = Arc::new(req);
    let queue = Arc::new(Mutex::new(VecDeque::from(tasks)));
    let (tx, rx) = mpsc::channel();

    {
        let compilers = Mutex::new(&mut *compilers);
        thread::scope(|scope| -> Result<(), Box<dyn std::error::Error>> {
            for _ in 0..worker_count {
                let req = Arc::clone(&req);
                let queue = Arc::clone(&queue);
                let tx = tx.clone();
                let compilers = &compilers;
                scope.spawn(move || {
                    loop {
                        let Some(task) = queue.lock().unwrap().pop_front() else {
                            break;
                        };
                        let mut compiler = {
                            let mut compilers = compilers.lock().unwrap();
                            compilers
                                .remove(&task.cache_key)
                                .map(|cached| cached.compiler)
                                .unwrap_or_else(Compiler::new)
                        };
                        let resp = compiler.classify_flow(&req, &task.node);
                        {
                            let mut compilers = compilers.lock().unwrap();
                            compilers.insert(
                                task.cache_key,
                                CachedCompiler {
                                    compiler,
                                    last_used: task.last_used,
                                },
                            );
                        }
                        if tx.send(resp).is_err() {
                            break;
                        }
                    }
                });
            }

            drop(tx);
            for resp in rx {
                write_flow_response(stdout, resp)?;
            }

            Ok(())
        })?;
    }

    evict_stale_compilers_except(compilers, &active_keys);
    Ok(())
}

fn render_latex_formulas(
    stdout: &mut impl Write,
    req: RenderFormulasRequest,
    renderer: &mut LatexRenderer,
) -> Result<(), Box<dyn std::error::Error>> {
    for node in &req.nodes {
        let resp = renderer.render_formula(&req, node);
        write_formula_response(stdout, resp)?;
    }
    Ok(())
}

fn render_formulas_sequential(
    stdout: &mut impl Write,
    req: RenderFormulasRequest,
    compilers: &mut HashMap<String, CachedCompiler>,
    use_clock: &mut u64,
) -> Result<(), Box<dyn std::error::Error>> {
    let base_cache_key = formula_base_cache_key(&req);
    let mut active_keys = Vec::new();
    for node in &req.nodes {
        let cache_key = formula_node_cache_key(&base_cache_key, node);
        active_keys.push(cache_key.clone());
        *use_clock = (*use_clock).saturating_add(1);
        let compiler = compilers
            .entry(cache_key.clone())
            .or_insert_with(|| CachedCompiler {
                compiler: Compiler::new(),
                last_used: *use_clock,
            });
        compiler.last_used = *use_clock;
        let resp = compiler.compiler.render_formula(&req, node);
        write_formula_response(stdout, resp)?;
    }
    evict_stale_compilers_except(compilers, &active_keys);
    Ok(())
}

fn render_formulas_parallel(
    stdout: &mut impl Write,
    req: RenderFormulasRequest,
    compilers: &mut HashMap<String, CachedCompiler>,
    use_clock: &mut u64,
) -> Result<(), Box<dyn std::error::Error>> {
    let base_cache_key = formula_base_cache_key(&req);
    let tasks = formula_tasks(&req, &base_cache_key, use_clock);
    let active_keys: Vec<_> = tasks.iter().map(|task| task.cache_key.clone()).collect();
    let worker_count = formula_worker_count(&req).min(tasks.len());
    let req = Arc::new(req);
    let queue = Arc::new(Mutex::new(VecDeque::from(tasks)));
    let (tx, rx) = mpsc::channel();

    {
        let compilers = Mutex::new(&mut *compilers);
        thread::scope(|scope| -> Result<(), Box<dyn std::error::Error>> {
            for _ in 0..worker_count {
                let req = Arc::clone(&req);
                let queue = Arc::clone(&queue);
                let tx = tx.clone();
                let compilers = &compilers;
                scope.spawn(move || {
                    let mut math_compiler = None;
                    loop {
                        let Some(task) = queue.lock().unwrap().pop_front() else {
                            break;
                        };
                        let resp = if is_code_formula_node(&task.node) {
                            let mut compiler = {
                                let mut compilers = compilers.lock().unwrap();
                                compilers
                                    .remove(&task.cache_key)
                                    .map(|cached| cached.compiler)
                                    .unwrap_or_else(Compiler::new)
                            };
                            let resp = compiler.render_formula(&req, &task.node);
                            {
                                let mut compilers = compilers.lock().unwrap();
                                compilers.insert(
                                    task.cache_key,
                                    CachedCompiler {
                                        compiler,
                                        last_used: task.last_used,
                                    },
                                );
                            }
                            resp
                        } else {
                            math_compiler
                                .get_or_insert_with(Compiler::new)
                                .render_formula(&req, &task.node)
                        };
                        if tx.send(resp).is_err() {
                            break;
                        }
                    }
                });
            }

            drop(tx);
            for resp in rx {
                write_formula_response(stdout, resp)?;
            }

            Ok(())
        })?;
    }

    evict_stale_compilers_except(compilers, &active_keys);
    Ok(())
}

fn is_code_formula_node(node: &FormulaNodeRequest) -> bool {
    node.kind.as_deref() == Some("code")
}

fn flow_base_cache_key(req: &ClassifyFlowRequest) -> String {
    req.cache_key
        .clone()
        .unwrap_or_else(|| format!("flow:{}:{}", req.context_id, req.context_rev))
}

fn formula_base_cache_key(req: &RenderFormulasRequest) -> String {
    req.cache_key
        .clone()
        .unwrap_or_else(|| format!("formula:{}:{}", req.context_id, req.context_rev))
}

fn code_node_cache_key(base: &str, node_id: &str) -> String {
    format!("{base}:code:{node_id}")
}

fn flow_node_cache_key(base: &str, node: &FlowNodeRequest) -> String {
    code_node_cache_key(base, &node.node_id)
}

fn formula_node_cache_key(base: &str, node: &FormulaNodeRequest) -> String {
    if is_code_formula_node(node) {
        code_node_cache_key(base, &node.node_id)
    } else {
        format!("{base}:formula:{}", node.node_id)
    }
}

fn flow_tasks(
    req: &ClassifyFlowRequest,
    base_cache_key: &str,
    use_clock: &mut u64,
) -> Vec<FlowTask> {
    req.nodes
        .iter()
        .map(|node| {
            *use_clock = (*use_clock).saturating_add(1);
            FlowTask {
                node: node.clone(),
                cache_key: flow_node_cache_key(base_cache_key, node),
                last_used: *use_clock,
            }
        })
        .collect()
}

fn formula_tasks(
    req: &RenderFormulasRequest,
    base_cache_key: &str,
    use_clock: &mut u64,
) -> Vec<FormulaTask> {
    req.nodes
        .iter()
        .map(|node| {
            *use_clock = (*use_clock).saturating_add(1);
            FormulaTask {
                node: node.clone(),
                cache_key: formula_node_cache_key(base_cache_key, node),
                last_used: *use_clock,
            }
        })
        .collect()
}

fn formula_worker_count(req: &RenderFormulasRequest) -> usize {
    req.worker_count
        .unwrap_or(1)
        .clamp(1, MAX_FORMULA_WORKERS)
        .min(req.nodes.len().max(1))
}

fn write_formula_response(
    stdout: &mut impl Write,
    resp: FormulaRenderResponse,
) -> Result<(), Box<dyn std::error::Error>> {
    serde_json::to_writer(stdout.by_ref(), &OutgoingMessage::FormulaRendered(resp))?;
    stdout.write_all(b"\n")?;
    stdout.flush()?;
    Ok(())
}

fn write_flow_response(
    stdout: &mut impl Write,
    resp: FlowClassifyResponse,
) -> Result<(), Box<dyn std::error::Error>> {
    serde_json::to_writer(stdout.by_ref(), &OutgoingMessage::FlowClassified(resp))?;
    stdout.write_all(b"\n")?;
    stdout.flush()?;
    Ok(())
}

fn evict_stale_compilers(compilers: &mut HashMap<String, CachedCompiler>, active_key: &str) {
    evict_stale_compilers_except(compilers, &[active_key.to_string()]);
}

fn evict_stale_compilers_except(
    compilers: &mut HashMap<String, CachedCompiler>,
    active_keys: &[String],
) {
    while compilers.len() > MAX_COMPILERS {
        let Some(evict_key) = compilers
            .iter()
            .filter(|(key, _)| !active_keys.iter().any(|active| active == *key))
            .min_by_key(|(_, compiler)| compiler.last_used)
            .map(|(key, _)| key.clone())
        else {
            break;
        };
        compilers.remove(&evict_key);
    }
}
