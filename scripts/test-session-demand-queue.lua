-- Run with:
--   nvim --headless -u NONE -l scripts/test-session-demand-queue.lua

local function run()
  local cwd = vim.fn.getcwd()
  vim.opt.runtimepath:append(cwd)
  package.path = table.concat({ cwd .. "/lua/?.lua", cwd .. "/lua/?/init.lua", package.path }, ";")

  local function assert_eq(label, actual, expected)
    if actual ~= expected then
      error(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)), 2)
    end
  end

  local sent = {}
  local old_executable = vim.fn.executable
  local old_jobstart = vim.fn.jobstart
  local old_jobwait = vim.fn.jobwait
  local old_chansend = vim.fn.chansend
  vim.fn.executable = function()
    return 1
  end
  vim.fn.jobstart = function()
    return 91
  end
  vim.fn.jobwait = function()
    return { -1 }
  end
  vim.fn.chansend = function(_, data)
    sent[#sent + 1] = vim.json.decode(data)
    return 1
  end

  local session = require("math-conceal.image.session")
  local bufnr = vim.api.nvim_create_buf(false, true)
  local binding = { service_binary = "fake-service" }
  local function submit(request_id, cache_key, realization_key)
    return session.render_code_flow(bufnr, binding, {
      type = "render_code_flow",
      request_id = request_id,
      cache_key = cache_key,
      nodes = { { node_id = realization_key } },
    }, {
      kind = "realization",
      node_meta = {
        [realization_key] = { key = realization_key },
      },
    })
  end

  assert_eq("active request sent", submit("active", "layout-a", "a"), true)
  assert_eq("first layout queued", submit("pending-a", "layout-a", "old"), true)
  assert_eq("second layout queued", submit("pending-b", "layout-b", "b"), true)
  local pending = session._state()[bufnr].pending_full
  assert_eq("two layout buckets retained", #pending.order, 2)

  session.prune_full(bufnr, { b = true })
  pending = session._state()[bufnr].pending_full
  assert_eq("obsolete pending layout removed", #pending.order, 1)
  assert_eq("wanted realization remains", pending.by_key[pending.order[1]].payload.nodes[1].node_id, "b")
  assert_eq("active request remains in flight", session._state()[bufnr].active_request_ids.full, "active")

  vim.fn.executable = old_executable
  vim.fn.jobstart = old_jobstart
  vim.fn.jobwait = old_jobwait
  vim.fn.chansend = old_chansend
  print("session-demand-queue-ok")
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end
vim.cmd("qa!")
