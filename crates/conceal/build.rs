use serde_json::Value;
use std::env;
use std::fs::File;
use std::io::{BufWriter, Write};
use std::path::Path;

fn main() {
    let out_dir = env::var("OUT_DIR").unwrap();
    let dest_path = Path::new(&out_dir).join("math_symbols_map.rs");
    let mut file = BufWriter::new(File::create(dest_path).unwrap());

    let json_path = Path::new("src").join("math_symbols.json");
    let json_file = File::open(json_path).expect("Failed to open math_symbols.json");
    let json_data: Value = serde_json::from_reader(json_file).expect("Failed to parse JSON");

    writeln!(
        file,
        "pub static MATH_SYMBOLS: phf::Map<&'static str, &'static str> = phf_map! {{"
    )
    .unwrap();

    if let Value::Object(obj) = json_data {
        for (key, value) in obj {
            if let Value::String(val_str) = value {
                if key.contains("\\") {
                    writeln!(file, "    r\"{}\" => \"{}\",", key, val_str).unwrap();
                } else {
                    writeln!(file, "    \"{}\" => \"{}\",", key, val_str).unwrap();
                }
            }
        }
    }

    writeln!(file, "}};").unwrap();
}
