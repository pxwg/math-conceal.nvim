-- Run: nvim --headless -u NONE -i NONE -l scripts/test-install-service.lua
local release = dofile("lua/math-conceal/service_release.lua")
local original_system, original_notify = vim.system, vim.notify
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local function fails(pattern, fn)
  local ok, err = pcall(fn)
  assert(not ok and tostring(err):find(pattern, 1, true), tostring(err))
end
local ok, err = xpcall(function()
  local asset = release.asset_name("Linux", "x86_64")
  local payload = "a\0b"
  -- Independent SHA-256 fixture includes NUL: binary data must not be truncated.
  local digest = "59b271ae1bbcb1d31d41929817f4b16fb439eb4f31520b5ad1d5ce98920a7138"
  assert(vim.fn.sha256(payload) == digest)
  -- Exercise the actual packaging entry point, then install its artifacts.
  local target = "x86_64-unknown-linux-gnu"
  vim.fn.mkdir(root .. "/service/target/" .. target .. "/release", "p")
  vim.fn.mkdir(root .. "/lua/math-conceal", "p")
  assert(vim.uv.fs_copyfile("lua/math-conceal/service_release.lua", root .. "/lua/math-conceal/service_release.lua"))
  release.write(root .. "/service/target/" .. target .. "/release/typst-concealer-service", payload)
  local packed = vim
    .system({
      vim.v.progpath,
      "--headless",
      "-u",
      "NONE",
      "-i",
      "NONE",
      "-l",
      vim.fn.fnamemodify("scripts/package-service.lua", ":p"),
      target,
    }, { cwd = root, text = true })
    :wait()
  assert(packed.code == 0, packed.stderr)
  assert(release.read(root .. "/dist/" .. asset) == payload)
  assert(release.read(root .. "/dist/" .. asset .. ".sha256") == digest .. "  " .. asset .. "\n")
  local urls = {}
  local function fetch(url, path)
    table.insert(urls, url)
    release.write(path, url:match("%.sha256$") and (digest .. "  " .. asset .. "\n") or payload)
  end
  local binary = release.install(root, "v1.2.3", asset, fetch)
  assert(release.read(binary) == payload)
  assert(vim.fn.executable(binary) == 1)
  for _, url in ipairs(urls) do
    assert(url:find("/releases/download/v1.2.3/", 1, true))
  end
  digest = string.rep("0", 64)
  fails("checksum mismatch", function()
    release.install(root, "v1.2.4", asset, fetch)
  end)
  assert(release.read(binary) == payload)
  fails("network interrupted", function()
    release.install(root, "v1.2.4", asset, function(_, path)
      release.write(path, "partial")
      error("network interrupted")
    end)
  end)
  assert(release.read(binary) == payload)
  assert(#vim.fn.readdir(vim.fs.dirname(binary)) == 1)
  digest = "invalid"
  fails("Invalid release checksum", function()
    release.install(root, "v1.2.4", asset, fetch)
  end)
  fails("No prebuilt service", function()
    release.asset_name("Linux", "aarch64")
  end)
  assert(release.asset_name("Darwin", "arm64"):match("aarch64%-apple%-darwin$"))
  assert(release.asset_name("Darwin", "x86_64"):match("x86_64%-apple%-darwin$"))
  local function git(args)
    local command = { "git", "-C", root }
    vim.list_extend(command, args)
    local result = vim.system(command, { text = true }):wait()
    assert(result.code == 0, result.stderr)
  end
  local function commit()
    git({
      "-c",
      "user.name=Test",
      "-c",
      "user.email=test@example.invalid",
      "-c",
      "commit.gpgsign=false",
      "commit",
      "--allow-empty",
      "-m",
      "test",
    })
  end
  git({ "init" })
  commit()
  fails("not a release tag", function()
    release.release_tag(root)
  end)
  git({ "tag", "v1.2.3" })
  assert(release.release_tag(root) == "v1.2.3")
  commit()
  fails("not a release tag", function()
    release.release_tag(root)
  end)
  -- Exercise the public async function with simulated curl progress and failures.
  git({ "tag", "v1.2.4" })
  local installer = dofile("lua/math-conceal/install.lua")
  local uname = vim.uv.os_uname()
  local native_asset = release.asset_name(uname.sysname, uname.machine)
  local expected = vim.fn.sha256(payload)
  local mode, notifications = "success", {}
  vim.notify = function(message)
    table.insert(notifications, message)
  end
  vim.system = function(command, options, callback)
    if command[1] ~= "curl" then
      return original_system(command, options, callback)
    end
    local output
    for i, value in ipairs(command) do
      if value == "--output" then
        output = command[i + 1]
      end
    end
    local url = command[#command]
    vim.schedule(function()
      if mode == "network" then
        options.stderr(nil, "curl: connection interrupted")
        callback({ code = 22 })
        return
      end
      local data = url:match("%.sha256$") and (expected .. "  " .. native_asset .. "\n") or payload
      release.write(output, data)
      options.stderr(nil, "\r#### 25.")
      options.stderr(nil, "0%\r######## 50.0%")
      callback({ code = 0 })
    end)
    return {}
  end
  local events = {}
  local function progress(message, percent)
    table.insert(events, { message, percent })
  end
  local handle = installer.install({ root = root, on_progress = progress })
  assert(not handle.done, "default install must return before download completes")
  fails("already running", function()
    installer.install({ root = root })
  end)
  assert(vim.wait(2000, function()
    return handle.done
  end))
  assert(not handle.error and handle.path == binary, tostring(handle.error))
  local saw_progress = false
  for _, event in ipairs(events) do
    if event[2] == 50 then
      saw_progress = true
    end
  end
  assert(saw_progress, "curl progress reaches the UI callback")
  assert(release.read(binary) == payload)
  mode = "network"
  fails("connection interrupted", function()
    installer.install({ root = root, wait = true, on_progress = progress })
  end)
  assert(release.read(binary) == payload)
  mode = "success"
  expected = string.rep("0", 64)
  local bad = installer.install({ root = root, on_progress = progress })
  assert(vim.wait(2000, function()
    return bad.done
  end))
  assert(bad.error:find("checksum mismatch", 1, true))
  assert(release.read(binary) == payload)
  expected = vim.fn.sha256(payload)
  local final = installer.install({
    root = root,
    wait = true,
    on_progress = function()
      error("UI unavailable")
    end,
  })
  assert(final.done and not final.error, "UI errors must not break installation")
  assert(#vim.fn.readdir(vim.fs.dirname(binary)) == 1)
end, debug.traceback)
vim.system, vim.notify = original_system, original_notify
vim.fn.delete(root, "rf")
if not ok then
  io.stderr:write(err .. "\n")
  vim.cmd("cquit")
end
print("service-installer-ok")
