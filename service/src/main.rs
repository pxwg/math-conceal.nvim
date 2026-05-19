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
use protocol::{FormulaRenderResponse, IncomingMessage, OutgoingMessage, RenderFormulasRequest};

const MAX_COMPILERS: usize = 16;
const MAX_FORMULA_WORKERS: usize = 8;

struct CachedCompiler {
    compiler: Compiler,
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
                    render_formulas_parallel(&mut stdout, req)?;
                }
            }
            IncomingMessage::Shutdown => break,
        }
    }

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
    let base_cache_key = req
        .cache_key
        .clone()
        .unwrap_or_else(|| format!("formula:{}:{}", req.context_id, req.context_rev));
    let mut active_cache_key = base_cache_key.clone();
    for node in &req.nodes {
        let cache_key = format!("{base_cache_key}:{}", node.node_id);
        active_cache_key = cache_key.clone();
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
    evict_stale_compilers(compilers, &active_cache_key);
    Ok(())
}

fn render_formulas_parallel(
    stdout: &mut impl Write,
    req: RenderFormulasRequest,
) -> Result<(), Box<dyn std::error::Error>> {
    let worker_count = formula_worker_count(&req).min(req.nodes.len());
    let req = Arc::new(req);
    let queue = Arc::new(Mutex::new(VecDeque::from(req.nodes.clone())));
    let (tx, rx) = mpsc::channel();

    thread::scope(|scope| -> Result<(), Box<dyn std::error::Error>> {
        for _ in 0..worker_count {
            let req = Arc::clone(&req);
            let queue = Arc::clone(&queue);
            let tx = tx.clone();
            scope.spawn(move || {
                let mut compiler = Compiler::new();
                loop {
                    let Some(node) = queue.lock().unwrap().pop_front() else {
                        break;
                    };
                    let resp = compiler.render_formula(&req, &node);
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
    })
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

fn evict_stale_compilers(compilers: &mut HashMap<String, CachedCompiler>, active_key: &str) {
    while compilers.len() > MAX_COMPILERS {
        let Some(evict_key) = compilers
            .iter()
            .filter(|(key, _)| key.as_str() != active_key)
            .min_by_key(|(_, compiler)| compiler.last_used)
            .map(|(key, _)| key.clone())
        else {
            break;
        };
        compilers.remove(&evict_key);
    }
}
