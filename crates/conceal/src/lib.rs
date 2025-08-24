pub mod lookup_conceal;
use lookup_conceal::{
    lookup_escape_symbol, lookup_font_symbol, lookup_math_symbol, lookup_subsup_symbol,
};
use mlua::Lua;
// fn normalize_font_type(font_type: &str) -> &str {
//     match font_type {
//         "bb" => "blackboard",
//         "bf" => "bold",
//         _ => font_type,
//     }
// }

#[mlua::lua_module]
pub fn lookup_conceal(lua: &Lua) -> mlua::Result<mlua::Table> {
    let exports = lua.create_table()?;
    
    // Original single lookup function for compatibility
    exports.set(
        "lookup_math_symbol",
        lua.create_function(|_, args: mlua::Table| {
            let text: String = args.get("text")?;
            let pattern: String = args.get("pattern")?;
            let mode: String = args.get("mode")?;
            match pattern.as_str() {
                "conceal" => Ok(lookup_math_symbol(&text).to_string()),
                "font" => Ok(lookup_font_symbol(&text, &mode).to_string()),
                "sub" => Ok(lookup_subsup_symbol(&text, &"sub").to_string()),
                "sup" => Ok(lookup_subsup_symbol(&text, &"sup").to_string()),
                "escape" => Ok(lookup_escape_symbol(&text, &"escape").to_string()),
                _ => Ok(lookup_math_symbol(&text).to_string()), // Return original text if pattern is unknown
            }
        })?,
    )?;
    
    // Optimized batch lookup function
    exports.set(
        "lookup_batch",
        lua.create_function(|lua, batch: mlua::Table| {
            let results = lua.create_table()?;
            for pair in batch.sequence_values::<mlua::Table>() {
                let item = pair?;
                let text: String = item.get("text")?;
                let pattern: String = item.get("pattern")?;
                let mode: String = item.get("mode").unwrap_or_default();
                
                let result = match pattern.as_str() {
                    "conceal" => lookup_math_symbol(&text),
                    "font" => lookup_font_symbol(&text, &mode),
                    "sub" => lookup_subsup_symbol(&text, "sub"),
                    "sup" => lookup_subsup_symbol(&text, "sup"), 
                    "escape" => lookup_escape_symbol(&text, "escape"),
                    _ => lookup_math_symbol(&text),
                };
                
                results.push(result)?;
            }
            Ok(results)
        })?,
    )?;
    
    Ok(exports)
}
