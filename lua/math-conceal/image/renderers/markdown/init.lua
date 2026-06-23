local wrapper = require("math-conceal.image.renderers.markdown.wrapper")

return {
  name = "markdown",
  source_kind = "markdown",
  backend = "typst",
  scanner = require("math-conceal.image.renderers.markdown.scanner"),
  build_context_document = wrapper.build_context_document,
  build_slot_document = wrapper.build_slot_document,
  render_size_key = wrapper.render_size_key,
  count_lines = wrapper.count_lines,
}
