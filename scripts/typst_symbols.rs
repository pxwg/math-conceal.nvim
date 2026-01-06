#!/usr/bin/env rust-script
//! ```cargo
//! [dependencies]
//! typst = "0.*"
//! typst-library = "0.*"
//! serde = { version = "1.0", features = ["derive"] }
//! serde_json = "1.0"
//! ```
use std::collections::BTreeMap;
use std::collections::HashSet;
use std::fs::File;
use std::io::Write;
use typst::foundations::{Scope, Symbol, Value};
use typst::{Library, LibraryExt};

fn main() {
    let lib = Library::default();
    let global_scope = lib.global.scope();

    let mut symbol_map: BTreeMap<String, String> = BTreeMap::new();

    for (name, binding) in global_scope.iter() {
        if name == "math" {
            let value = binding.read();
            if let Value::Module(module) = value {
                extract_from_scope(module.scope(), &mut symbol_map);
                break;
            }
        }
    }

    let ignored_symbols: HashSet<&str> = [
        "alpha",
        "beta",
        "gamma",
        "delta",
        "epsilon",
        "varepsilon",
        "zeta",
        "eta",
        "theta",
        "vartheta",
        "iota",
        "kappa",
        "lambda",
        "mu",
        "nu",
        "xi",
        "pi",
        "varpi",
        "rho",
        "varrho",
        "sigma",
        "varsigma",
        "tau",
        "upsilon",
        "phi",
        "varphi",
        "chi",
        "psi",
        "omega",
        "nabla",
        "Gamma",
        "Delta",
        "Theta",
        "Lambda",
        "Xi",
        "Pi",
        "Sigma",
        "Upsilon",
        "Phi",
        "Chi",
        "Psi",
        "Omega",
    ]
    .iter()
    .copied()
    .collect();

    let mut simple_symbols: Vec<String> = Vec::new();
    let mut dotted_symbols: Vec<String> = Vec::new();

    for name in symbol_map.keys() {
        if ignored_symbols.contains(name.as_str()) {
            continue;
        }

        if name.contains('.') {
            dotted_symbols.push(name.clone());
        } else {
            simple_symbols.push(name.clone());
        }
    }

    let json_output = serde_json::to_string_pretty(&symbol_map).expect("Failed to serialize JSON");
    let mut file = File::create("crates/conceal/src/math_symbols_typst.json")
        .expect("Failed to create output.json");
    file.write_all(json_output.as_bytes())
        .expect("Failed to write to output.json");

    let bare_content = std::fs::read_to_string("queries/typst/conceal_math_bare.scm")
        .expect("Failed to read queries/typst/conceal_math_bare.scm");

    let simple_content = generate_simple_symbols_query(&simple_symbols);
    let dotted_content = generate_dotted_symbols_query(&dotted_symbols);

    // bare + \n\n + simple + \n\n + dotted
    let final_scm_content = format!(
        "{}\n\n{}\n\n{}",
        bare_content.trim(),
        simple_content.trim(),
        dotted_content.trim()
    );

    let mut scm_file = File::create("queries/typst/conceal_math.scm")
        .expect("Failed to create queries/typst/conceal_math.scm");
    scm_file
        .write_all(final_scm_content.as_bytes())
        .expect("Failed to write to queries/typst/conceal_math.scm");
}

/// Generates a Tree-sitter query string for simple math symbols (no dot modifiers).
/// `symbols`: List of symbol names.
fn generate_simple_symbols_query(symbols: &[String]) -> String {
    let mut output = String::new();

    output.push_str("; Math operators and symbols\n");
    output.push_str("(((ident) @typ_math_symbol\n");
    output.push_str(&format!(
        "  (#match? @typ_math_symbol \"^({})$\"))\n",
        symbols.join("|")
    ));
    output.push_str("  (#has-ancestor? @typ_math_symbol math formula)\n");
    output.push_str("  ; (#not-has-ancestor? @typ_math_symbol call)\n");
    output.push_str("  (#set! priority 101)\n");
    output.push_str("  (#set-conceal! @typ_math_symbol \"conceal\"))\n");

    output
}

/// Generates a Tree-sitter query string for math symbols with dot modifiers.
/// `symbols`: List of symbol names with dot modifiers.
fn generate_dotted_symbols_query(symbols: &[String]) -> String {
    let mut output = String::new();

    let escaped_symbols: Vec<String> = symbols.iter().map(|s| s.replace(".", "\\\\.")).collect();

    output.push_str("; Math operators and symbols with modifiers\n");
    output.push_str("(((field) @typ_math_symbol\n");
    output.push_str(&format!(
        "  (#match? @typ_math_symbol \"^({})$\"))\n",
        escaped_symbols.join("|")
    ));
    output.push_str("  (#set! priority 102)\n");
    output.push_str("  (#has-ancestor? @typ_math_symbol math formula)\n");
    output.push_str("  ; (#not-has-ancestor? @typ_math_symbol call)\n");
    output.push_str("  (#set-conceal! @typ_math_symbol \"conceal\")\n");
    output.push_str("  )\n");

    output
}

/// Recursively extracts all symbol names and their Unicode values from a scope.
/// Adds them to the provided map.
fn extract_from_scope(scope: &Scope, map: &mut BTreeMap<String, String>) {
    for (name, binding) in scope.iter() {
        let value = binding.read();
        match value {
            Value::Symbol(sym) => {
                walk_symbol(name, sym, map);
            }
            Value::Module(_module) => {}
            _ => {}
        }
    }
}

/// Inserts a symbol and all its modifier variants into the map.
/// `name`: Symbol name.
/// `sym`: Symbol object.
/// `map`: Output map.
fn walk_symbol(name: &str, sym: &Symbol, map: &mut BTreeMap<String, String>) {
    let char_str = sym.get().to_string();
    map.insert(name.to_string(), char_str);

    for variant_name in sym.modifiers() {
        let full_variant_name = format!("{}.{}", name, variant_name);

        if let Ok(variant_sym) = sym.clone().modified((), variant_name) {
            walk_symbol(&full_variant_name, &variant_sym, map);
        }
    }
}
