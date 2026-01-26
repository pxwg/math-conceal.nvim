#!/usr/bin/env rust-script
//! ```cargo
//! [dependencies]
//! typst = "0.14.2"
//! typst-library = "0.14.2"
//! serde = { version = "1.0", features = ["derive"] }
//! serde_json = "1.0"
//! reqwest = { version = "0.11", features = ["blocking", "json"] }
//! semver = "1.0"
//! ```
use serde_json::json;
use std::collections::BTreeMap;
use std::fs::File;
use std::io::Write;
use typst::foundations::{Scope, Symbol, Value};
use typst::{Library, LibraryExt};

fn main() {
    let current_version = "0.14.2";
    let latest_version = fetch_latest_typst_version().unwrap_or(current_version.to_string());

    if latest_version != current_version {
        println!("New typst version detected: {latest_version}, updating symbols...");
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

        let mut file = File::create("../lua/math-conceal/conceal/math_symbols_typst.json")
            .expect("Failed to create output file");
        file.write_all(
            serde_json::to_string_pretty(&output_json)
                .expect("Failed to serialize JSON")
                .as_bytes(),
        )
        .expect("Failed to write to output file");
    } else {
        println!("Typst is up to date ({current_version})");
    }
}

fn fetch_latest_typst_version() -> Option<String> {
    let url = "https://crates.io/api/v1/crates/typst";
    let resp = reqwest::blocking::get(url).ok()?;
    let json: serde_json::Value = resp.json().ok()?;
    let version = json.get("crate")?.get("newest_version")?.as_str()?;
    Some(version.to_string())
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
