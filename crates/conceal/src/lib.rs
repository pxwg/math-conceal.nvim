pub mod lookup_conceal;
use lookup_conceal::lookup_math_symbol;
use mlua::{Lua, UserData, UserDataMethods};

#[derive(Clone)]
struct MathSymbols;

impl UserData for MathSymbols {
    fn add_methods<M: UserDataMethods<Self>>(methods: &mut M) {
        methods.add_function("lookup_conceal", |_, text: String| {
            Ok(lookup_math_symbol(&text))
        });
    }
}

#[mlua::lua_module]
pub fn lookup_conceal(lua: &Lua) -> mlua::Result<mlua::Table> {
    let exports = lua.create_table()?;
    exports.set(
        "lookup_math_symbol",
        lua.create_function(|_, text: String| Ok(lookup_math_symbol(&text)))?,
    )?;
    Ok(exports)
}
