-- Run with:
--   nvim --headless -u NONE -l scripts/test-projection-window-demands.lua

local function run()
  local cwd = vim.fn.getcwd()
  vim.opt.runtimepath:append(cwd)
  package.path = table.concat({ cwd .. "/lua/?.lua", cwd .. "/lua/?/init.lua", package.path }, ";")

  local function assert_eq(label, actual, expected)
    if actual ~= expected then
      error(string.format("%s: expected %s, got %s", label, vim.inspect(expected), vim.inspect(actual)), 2)
    end
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "$x$", "#rect(width: 100%)" })
  vim.cmd("vsplit")
  local wins = vim.api.nvim_tabpage_list_wins(0)
  vim.api.nvim_win_set_width(wins[1], 30)

  local tracks = {
    {
      bufnr = bufnr,
      tracker_generation = 1,
      generation = 1,
      track_id = 1,
      rev = 1,
      state = "valid",
      row = 0,
      col = 0,
      end_row = 0,
      end_col = 3,
      source_hash = "math-v1",
      source_rows = 1,
      source_display_kind = "inline",
      object_kind = "math",
    },
    {
      bufnr = bufnr,
      tracker_generation = 1,
      generation = 1,
      track_id = 2,
      rev = 1,
      state = "valid",
      row = 1,
      col = 0,
      end_row = 1,
      end_col = 18,
      source_hash = "code-v1",
      source_rows = 1,
      source_display_kind = "inline",
      object_kind = "code",
    },
  }
  local function track_key(track)
    return "track:" .. tostring(track.track_id)
  end
  package.loaded["math-conceal.image.tracker"] = {
    get_tracks = function()
      return tracks
    end,
    get_context = function()
      return {}
    end,
    track_ref_key = track_key,
    resolve_ref = function(ref)
      for _, track in ipairs(tracks) do
        if track.track_id == ref.track_id then
          return track
        end
      end
    end,
    source_line = function(_, row)
      return vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
    end,
  }
  package.loaded["math-conceal.image.context"] = {
    resolve = function()
      return { context_id = "ctx", context_rev = 1, workspace = { outputs_dir = "/tmp" } }
    end,
  }

  local transactions = {}
  package.loaded["math-conceal.image.placement"] = {
    reconcile_window = function(winid, transaction)
      transactions[winid] = transaction
      return true
    end,
    close_window = function() end,
    close_buffer = function() end,
    release_image = function() end,
  }
  local deleted = {}
  package.loaded["math-conceal.image.terminal"] = {
    send_image = function()
      return true
    end,
    delete_image = function(image_id)
      deleted[#deleted + 1] = image_id
    end,
  }
  package.loaded["math-conceal.image.preview"] = {
    schedule = function() end,
    refresh = function() end,
    detach = function() end,
  }
  package.loaded["math-conceal.image.session"] = {
    prune_full = function() end,
    stop = function() end,
  }

  local dispatched = {}
  local adapter = {}
  function adapter.layout(track, window)
    if track.object_kind == "code" then
      return { key = "window:" .. window.signature, signature = window.signature, window = window }
    end
    return { key = "shared", signature = "shared" }
  end
  function adapter.describe(track, ctx, layout, _config, projection_key)
    local key = track.source_hash .. ":" .. layout.key
    return {
      adapter = "typst",
      batch_kind = track.object_kind == "code" and "code_flow" or "formula",
      key = key,
      layout_key = layout.key,
      layout = layout,
      pending_visibility = track.object_kind == "code" and "source" or "previous",
      source_rows = 1,
      display_kind = "inline",
      node = { node_id = projection_key, node_rev = track.rev },
      meta = {
        projection_key = projection_key,
        realization_key = key,
        track_rev = track.rev,
        context_id = ctx.context_id,
        context_rev = ctx.context_rev,
      },
    }
  end
  function adapter.dispatch_batch(_, _, batch)
    dispatched[#dispatched + 1] = batch
    return true
  end
  function adapter.accept_response(resp, descriptor)
    return {
      status = "ready",
      path = resp.path,
      width_px = 20,
      height_px = 10,
      display_kind = descriptor.display_kind,
      source_rows = 1,
    }
  end
  function adapter.placement_request(asset, track)
    return {
      state = "ready",
      ref = { bufnr = bufnr, tracker_generation = 1, track_id = track.track_id },
      realization_key = asset.key,
      image_id = asset.image_id,
      natural_grid = asset.natural_grid,
      display_kind = asset.display_kind,
    }
  end
  package.loaded["math-conceal.image.realization"] = {
    require = function()
      return adapter
    end,
  }
  package.loaded["math-conceal.image"] = {
    config = { conceal_in_normal = false },
    get_binding = function()
      return { source_kind = "typst" }
    end,
  }

  local projection = require("math-conceal.image.projection")
  projection.on_tracker_repair({ bufnr = bufnr, retired_refs = {} })
  assert_eq("shared math plus two code layouts", #dispatched, 3)
  local descriptor_count = 0
  for _, batch in ipairs(dispatched) do
    descriptor_count = descriptor_count + #batch.descriptors
  end
  assert_eq("three realization descriptors", descriptor_count, 3)

  for _, batch in ipairs(vim.deepcopy(dispatched)) do
    for _, descriptor in ipairs(batch.descriptors) do
      projection.handle_service_response(bufnr, {
        type = "test",
        request_id = batch.request_id,
        node_id = descriptor.node.node_id,
        node_rev = descriptor.meta.track_rev,
        context_id = descriptor.meta.context_id,
        context_rev = descriptor.meta.context_rev,
        path = "/tmp/" .. descriptor.key .. ".png",
      }, {
        kind = "realization",
        adapter = "typst",
        node_meta = { [descriptor.node.node_id] = descriptor },
      })
    end
  end
  for _, winid in ipairs(wins) do
    assert_eq("math ready in each window", transactions[winid].upsert["track:1"].state, "ready")
    assert_eq("code ready in each window", transactions[winid].upsert["track:2"].state, "ready")
  end

  dispatched = {}
  tracks[1].rev, tracks[1].source_hash = 2, "math-v2"
  tracks[2].rev, tracks[2].source_hash = 2, "code-v2"
  projection.on_tracker_repair({ bufnr = bufnr, retired_refs = {} })
  for _, winid in ipairs(wins) do
    assert_eq("math pending keeps previous asset", transactions[winid].upsert["track:1"].state, "ready")
    assert_eq("code pending reveals source", transactions[winid].upsert["track:2"].state, "source")
  end

  print("projection-window-demands-ok")
end

local ok, err = xpcall(run, debug.traceback)
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end
vim.cmd("qa!")
