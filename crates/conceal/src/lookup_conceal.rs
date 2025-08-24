use phf::phf_map;
// TODO: Add custumizeable math symbols with treesitter

include!(concat!(env!("OUT_DIR"), "/math_symbols_map.rs"));

// Return the actual Unicode character or the original string
pub fn lookup_math_symbol(s: &str) -> &str {
    MATH_SYMBOLS.get(s).copied().unwrap_or(s)
}

// Return the font-styled character based on font type in typst
// TODO: better handling of font types
pub fn lookup_font_symbol<'a>(text: &'a str, font_type: &'a str) -> &'a str {
    // let key = format!("{font_type}:{text}");
    let key = [font_type, ":", text].concat();
    MATH_SYMBOLS.get(key.as_str()).copied().unwrap_or(text)
}

// Return the sub/superscript type and character based on typst notation
pub fn lookup_subsup_symbol<'a>(text: &'a str, sub_or_sup: &'a str) -> &'a str {
    // let key = format!("{sub_or_sup}:{text}");
    let key = [sub_or_sup, ":", text].concat();
    MATH_SYMBOLS.get(key.as_str()).copied().unwrap_or(text)
}
pub fn lookup_escape_symbol<'a>(text: &'a str, escape: &'a str) -> &'a str {
    let key = [escape, ":", text].concat();
    MATH_SYMBOLS.get(key.as_str()).copied().unwrap_or(text)
}
