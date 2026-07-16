#!/usr/bin/env rust-script
//! ```cargo
//! [dependencies]
//! typst = "0.15.0"
//! typst-library = "0.15.0"
//! serde = { version = "1.0", features = ["derive"] }
//! serde_json = "1.0"
//! ```
use serde_json::{json, Value};
use std::collections::{BTreeMap, HashSet};
use std::fs::File;
use std::io::Write;
use std::path::PathBuf;
use typst::foundations::{Binding, Scope, Symbol, Value as TypstValue};
use typst::{Library, LibraryExt};

/// Characters that are considered "filterable" (non-printable, zero-width, etc.)
/// If a string consists ONLY of these characters, the entire key is removed.
fn is_filterable_char(c: char) -> bool {
    match c as u32 {
        // C0 control characters (0x00-0x1F) except tab (0x09) and newline (0x0A)
        0x00..=0x08 | 0x0B | 0x0E..=0x1F | 0x7F => true,
        // C1 control characters (0x80-0x9F)
        0x80..=0x9F => true,
        // Soft hyphen (U+00AD)
        0xAD => true,
        // Zero-width and invisible characters (ZWJ, ZWNJ, ZWS, etc.)
        0x200B | 0x200C | 0x200D | 0x200E | 0x200F | 0x2060 | 0xFEFF => true,
        // Directional formatting characters
        0x061C | 0x202A..=0x202E => true,
        // Variation selectors - keep them (they are meaningful)
        // 0xFE00..=0xFE0F => false,
        // 0xE0100..=0xE01EF => false,
        _ => false,
    }
}

/// Returns true if the string consists ONLY of filterable characters
fn is_only_filterable(s: &str) -> bool {
    if s.is_empty() {
        return true;
    }
    s.chars().all(|c| is_filterable_char(c))
}

fn main() {
    let lib = Library::default();
    let global_scope = lib.global.scope();

    let mut math_symbols: BTreeMap<String, String> = BTreeMap::new();
    let mut other_symbols: BTreeMap<String, BTreeMap<String, String>> = BTreeMap::new();
    let mut deprecated_symbols: HashSet<String> = HashSet::new();

    // Collect symbols from all modules
    for (mod_name, binding) in global_scope.iter() {
        let value = binding.read();
        if let TypstValue::Module(module) = value {
            let mut module_symbols = BTreeMap::new();
            let mut module_deprecated = HashSet::new();

            if mod_name == "math" {
                extract_from_scope(module.scope(), &mut module_symbols, &mut module_deprecated, Some(&binding), true);
                math_symbols = module_symbols;
                deprecated_symbols = module_deprecated;
            } else {
                extract_from_scope(module.scope(), &mut module_symbols, &mut module_deprecated, Some(&binding), false);
                other_symbols.insert(mod_name.to_string(), module_symbols);
                deprecated_symbols.extend(module_deprecated);
            }
        }
    }

    // Remove deprecated symbols from math_symbols
    for sym in &deprecated_symbols {
        math_symbols.remove(sym);
    }

    // Remove deprecated symbols from other sections
    for (_, module_map) in &mut other_symbols {
        for sym in &deprecated_symbols {
            module_map.remove(sym);
        }
    }

    let mut emoji_symbols: BTreeMap<String, String> = BTreeMap::new();
    let mut all_other: BTreeMap<String, String> = BTreeMap::new();

    for (mod_name, module_map) in other_symbols {
        if mod_name == "emoji" {
            emoji_symbols = module_map;
        } else {
            for (key, value) in module_map {
                all_other.insert(key, value);
            }
        }
    }

    // Remove duplicates from other that exist in math
    let mut to_remove = Vec::new();
    for key in all_other.keys() {
        if math_symbols.contains_key(key) {
            to_remove.push(key.clone());
        }
    }
    for key in to_remove {
        all_other.remove(&key);
    }

    // Build initial JSON
    let mut output_json = json!({
        "conceal": math_symbols
    });

    if !emoji_symbols.is_empty() {
        output_json["emoji"] = json!(emoji_symbols);
    }

    if !all_other.is_empty() {
        output_json["other"] = json!(all_other);
    }

    // Filter entire keys whose values consist ONLY of filterable characters
    fn filter_keys_by_value(value: &mut Value) {
        match value {
            Value::Object(map) => {
                let mut to_remove = Vec::new();
                for (key, val) in map.iter_mut() {
                    if let Value::String(s) = val {
                        // If the string consists ONLY of filterable characters, remove the key
                        if is_only_filterable(s) {
                            to_remove.push(key.clone());
                        }
                    } else {
                        filter_keys_by_value(val);
                    }
                }
                for key in to_remove {
                    map.remove(&key);
                }
            }
            Value::Array(arr) => {
                for val in arr {
                    filter_keys_by_value(val);
                }
            }
            _ => {}
        }
    }
    filter_keys_by_value(&mut output_json);

    // Load custom symbols from file
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

            // Add/replace custom sections
            for (section_name, custom_section) in custom_obj {
                if let Some(custom_map) = custom_section.as_object() {
                    if !output_json.as_object().unwrap().contains_key(section_name) {
                        output_json[section_name] = json!({});
                    }

                    if let Some(output_map) = output_json[section_name].as_object_mut() {
                        for (k, v) in custom_map {
                            if let Some(s) = v.as_str() {
                                // Custom symbols should be added as-is
                                // But if they consist ONLY of filterable chars, skip them
                                if !is_only_filterable(s) {
                                    output_map.insert(k.clone(), json!(s));
                                }
                            } else {
                                output_map.insert(k.clone(), v.clone());
                            }
                        }
                    }
                } else {
                    output_json[section_name] = custom_section.clone();
                }
            }
        }
    }

    // Final filtering after adding custom symbols
    filter_keys_by_value(&mut output_json);

    let output_path = "lua/math-conceal/conceal/math_symbols_typst.json";
    let mut file = File::create(output_path).expect("Failed to create output file");
    let serialized = serde_json::to_string_pretty(&output_json).expect("Failed to serialize JSON");
    file.write_all(serialized.as_bytes()).expect("Failed to write to output file");
}

fn extract_from_scope(scope: &Scope,
    map: &mut BTreeMap<String, String>,
    deprecated: &mut HashSet<String>,
    parent_binding: Option<&Binding>,
    skip_nested: bool
) {
    for (name, binding) in scope.iter() {
        let value = binding.read();

        // Check if this binding or its parent is marked as deprecated
        let is_deprecated = parent_binding
            .and_then(|p| p.deprecation())
            .is_some()
            || binding.deprecation().is_some();

        if let TypstValue::Symbol(sym) = value {
            if is_deprecated {
                deprecated.insert(name.to_string());
                for variant_name in sym.modifiers() {
                    let full_variant_name = format!("{}.{}", name, variant_name);
                    deprecated.insert(full_variant_name);
                }
            } else {
                walk_symbol(name, sym, map);
            }
        } else if let TypstValue::Module(module) = value {
            if !skip_nested {
                extract_from_scope(module.scope(), map, deprecated, Some(&binding), skip_nested);
            }
        }
    }
}

fn walk_symbol(name: &str, sym: &Symbol, map: &mut BTreeMap<String, String>) {
    let char_str = sym.get().to_string();
    // Store as-is, filtering happens later based on content
    map.insert(name.to_string(), char_str);

    for variant_name in sym.modifiers() {
        let full_variant_name = format!("{}.{}", name, variant_name);
        if let Ok(variant_sym) = sym.clone().modified((), variant_name) {
            walk_symbol(&full_variant_name, &variant_sym, map);
        }
    }
}