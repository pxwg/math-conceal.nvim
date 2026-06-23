local wrapper = require("math-conceal.image.renderers.typst.wrapper")

return {
  name = "typst",
  source_kind = "typst",
  backend = "typst",
  scanner = require("math-conceal.image.renderers.typst.scanner"),
  display_projection = require("math-conceal.image.renderers.typst.display"),
  flow = require("math-conceal.image.renderers.typst.flow"),
  preview = require("math-conceal.image.renderers.typst.preview"),
  build_context_document = wrapper.build_context_document,
  build_flow_context_document = wrapper.build_flow_context_document,
  build_slot_document = wrapper.build_slot_document,
  build_flow_source = wrapper.build_flow_source,
  render_size_key = wrapper.render_size_key,
  render_layout_key = wrapper.render_layout_key,
  count_lines = wrapper.count_lines,
}
