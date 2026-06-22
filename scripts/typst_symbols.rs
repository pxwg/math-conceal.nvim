#!/usr/bin/env rust-script
//! ```cargo
//! [dependencies]
//! typst = "0.15.0"
//! typst-library = "0.15.0"
//! serde = { version = "1.0", features = ["derive"] }
//! serde_json = "1.0"
//! ```
use serde_json::json;
use std::collections::BTreeMap;
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

    let output_json = json!({
        "conceal": symbol_map
    });

    let mut file = File::create("lua/math-conceal/conceal/math_symbols_typst.json")
        .expect("Failed to create output file");
    let mut serialized =
        serde_json::to_string_pretty(&output_json).expect("Failed to serialize JSON");
    serialized.push('\n');
    file.write_all(serialized.as_bytes())
        .expect("Failed to write to output file");
}

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
