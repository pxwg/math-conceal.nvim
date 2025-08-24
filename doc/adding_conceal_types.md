# Adding New Conceal Types

The optimized math-conceal.nvim now makes it easy to add new conceal types through a declarative configuration system.

## Simple Method (Automatic Handler)

For basic concealment patterns, you can use the automatic handler generation:

```lua
local treesitter_query = require('treesitter_query')

-- Register a new conceal type for vector notation
treesitter_query.register_conceal_type("vector", "conceal", "set-vector!")
```

This will automatically:
- Create a handler function for the "vector" pattern
- Register the tree-sitter directive "set-vector!"
- Use the standard concealment lookup logic

## Manual Configuration

For more complex patterns requiring custom handler logic, you can manually add to the configuration:

```lua
-- In lua/treesitter_query.lua, add to conceal_config:
local conceal_config = {
  -- ... existing entries ...
  vector = { 
    pattern = "vector", 
    directive_name = "set-vector!", 
    handler_key = "vector" 
  },
}

-- And add custom handler to handler_dispatch:
handler_dispatch.vector = function(match, _, source, predicate, metadata)
  -- Custom handler logic here
end
```

## Tree-sitter Query Usage

Once registered, use the new directive in your `.scm` files:

```scheme
((ident) @vector_symbol
  (#any-of? @vector_symbol "vec" "vector" "V")
  (#set-vector! @vector_symbol "conceal"))
```

## Performance Benefits

The new system provides:
- **O(1) handler lookup** vs. O(n) if-elseif chains
- **Automatic caching** of frequently used symbols
- **Batch processing** capability for multiple symbols
- **Reduced FFI overhead** through optimized Rust interface

Adding new conceal types no longer requires modifying multiple functions or the core dispatch logic.