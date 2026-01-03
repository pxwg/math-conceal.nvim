use serde_json::Value;
use std::env;
use std::fs::File;
use std::io::{BufWriter, Write};
use std::path::Path;

fn main() {
    let out_dir = env::var("OUT_DIR").unwrap();
    let dest_path = Path::new(&out_dir).join("math_symbols_map.rs");
    let mut file = BufWriter::new(File::create(dest_path).unwrap());

    let json_paths = [
        Path::new("src").join("math_symbols_typst.json"),
        Path::new("src").join("math_symbols_latex.json"),
        Path::new("src").join("math_fonts_latex.json"),
        Path::new("src").join("math_fonts_typst.json"),
    ];

    let mut merged = serde_json::Map::new();
    for json_path in &json_paths {
        let json_file = File::open(json_path).expect("Failed to open math_symbols json");
        let json_data: Value = serde_json::from_reader(json_file).expect("Failed to parse JSON");
        if let Value::Object(obj) = json_data {
            for (k, v) in obj {
                merged.insert(k, v);
            }
        }
    }

    writeln!(
        file,
        "pub static MATH_SYMBOLS: phf::Map<&'static str, &'static str> = phf_map! {{"
    )
    .unwrap();

    for (key, value) in &merged {
        if let Value::String(val_str) = value {
            writeln!(file, "    {:?} => {:?},", key, val_str).unwrap();
        }
    }

    writeln!(file, "}};").unwrap();
}
