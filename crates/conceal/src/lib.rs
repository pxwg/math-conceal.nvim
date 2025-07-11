pub mod lookup_conceal;
use lookup_conceal::{lookup_font_symbol, lookup_math_symbol};
use mlua::{Lua, UserData, UserDataMethods};

#[mlua::lua_module]
pub fn lookup_conceal(lua: &Lua) -> mlua::Result<mlua::Table> {
    let exports = lua.create_table()?;
    exports.set(
        "lookup_math_symbol",
        lua.create_function(|_, (text, pattern, mode): (String, String, String)| {
            match pattern.as_str() {
                "conceal" => Ok(lookup_math_symbol(&text)),
                "font" => Ok(lookup_font_symbol(&text, &mode)),
                _ => Ok(text), // Return original text if pattern is unknown
            }
        })?,
    )?;
    Ok(exports)
}
