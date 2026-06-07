#!/usr/bin/env rust-script
//! ```cargo
//! [dependencies]
//! typst = "0.14.2"
//! typst-library = "0.14.2"
//! serde = { version = "1.0", features = ["derive"] }
//! serde_json = "1.0"
//! ```
use serde_json::{json, Value};
use std::collections::{BTreeMap, HashSet};
use std::fs::File;
use std::io::Write;
use std::path::PathBuf;
use typst::foundations::{Scope, Symbol, Value as TypstValue};
use typst::{Library, LibraryExt};

fn main() {
    let lib = Library::default();
    let global_scope = lib.global.scope();

    let mut math_symbols: BTreeMap<String, String> = BTreeMap::new();
    let mut other_symbols: BTreeMap<String, BTreeMap<String, String>> = BTreeMap::new();

    // Collect symbols from all modules
    for (mod_name, binding) in global_scope.iter() {
        let value = binding.read();
        if let TypstValue::Module(module) = value {
            let mut module_symbols = BTreeMap::new();
            extract_from_scope(module.scope(), &mut module_symbols);

            if mod_name == "math" {
                math_symbols = module_symbols;
            } else {
                other_symbols.insert(mod_name.to_string(), module_symbols);
            }
        }
    }

    // Remove duplicates within downloaded data: remove from other sections keys that exist in math
    for (_, module_map) in &mut other_symbols {
        let mut to_remove = Vec::new();
        for key in module_map.keys() {
            if math_symbols.contains_key(key) {
                to_remove.push(key.clone());
            }
        }
        for key in to_remove {
            module_map.remove(&key);
        }
    }

    // Build initial JSON
    let mut output_json = json!({
        "conceal": math_symbols
    });

    for (mod_name, module_map) in other_symbols {
        if !module_map.is_empty() {
            output_json[mod_name] = json!(module_map);
        }
    }

    // Load custom symbols
    let custom_path = PathBuf::from("scripts/symbols_typst_custom.json");
    if custom_path.exists() {
        let file = File::open(&custom_path).expect("Failed to open custom JSON file");
        let custom_json: Value = serde_json::from_reader(file)
            .expect("Failed to parse custom JSON file");

        if let Some(custom_obj) = custom_json.as_object() {
            // Collect ALL keys from ALL custom sections
            let mut all_custom_keys = HashSet::new();
            for custom_section in custom_obj.values() {
                if let Some(custom_map) = custom_section.as_object() {
                    for key in custom_map.keys() {
                        all_custom_keys.insert(key.clone());
                    }
                }
            }

            // Remove these keys from EVERY section in output_json
            for section_value in output_json.as_object_mut().unwrap().values_mut() {
                if let Some(section_map) = section_value.as_object_mut() {
                    for key in &all_custom_keys {
                        section_map.remove(key);
                    }
                }
            }

            // Now add/replace custom sections
            for (section_name, custom_section) in custom_obj {
                if let Some(custom_map) = custom_section.as_object() {
                    if !output_json.as_object().unwrap().contains_key(section_name) {
                        output_json[section_name] = json!({});
                    }

                    if let Some(output_map) = output_json[section_name].as_object_mut() {
                        for (k, v) in custom_map {
                            if let Some(s) = v.as_str() {
                                output_map.insert(k.clone(), json!(s));
                            }
                        }
                    }
                } else {
                    output_json[section_name] = custom_section.clone();
                }
            }
        }
    }

    let output_path = "lua/math-conceal/conceal/math_symbols_typst.json";
    let mut file = File::create(output_path).expect("Failed to create output file");
    let serialized = serde_json::to_string_pretty(&output_json).expect("Failed to serialize JSON");
    file.write_all(serialized.as_bytes()).expect("Failed to write to output file");
}

fn extract_from_scope(scope: &Scope, map: &mut BTreeMap<String, String>) {
    for (name, binding) in scope.iter() {
        let value = binding.read();
        if let TypstValue::Symbol(sym) = value {
            walk_symbol(name, sym, map);
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
