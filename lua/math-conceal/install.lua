local M = {}
local active = {}
local source = debug.getinfo(1, "S").source:sub(2)
local default_root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fn.fnamemodify(source, ":p"))))

local function display(message, percent)
  local bar = ""
  if percent then
    local filled = math.floor(percent / 5)
    bar = string.format(" [%s%s] %3d%%", string.rep("=", filled), string.rep(" ", 20 - filled), percent)
  end
  vim.api.nvim_echo({ { "math-conceal: " .. message .. bar, "Normal" } }, false, {})
end

--- Download the service matching this checkout. Returns a handle with done/error/path.
--- By default runs asynchronously; wait=true keeps a package-manager build pending.
--- @param opts? {root?: string, wait?: boolean, on_progress?: fun(message: string, percent?: number)}
function M.install(opts)
  opts = opts or {}
  local root = opts.root or default_root
  if active[root] then
    error("A service installation is already running for " .. root)
  end
  local release = dofile(root .. "/lua/math-conceal/service_release.lua")
  local handle = { done = false }
  active[root] = handle
  local progress = opts.on_progress or display
  local function report(message, percent)
    -- UI callbacks must not interrupt installation or leave staging files behind.
    pcall(progress, message, percent)
  end
  local task
  local function resume(...)
    local ok, err = coroutine.resume(task, ...)
    if not ok then
      handle.error = tostring(err)
    end
    if not ok or coroutine.status(task) == "dead" then
      handle.done = true
      active[root] = nil
      if handle.error then
        vim.notify("Service installation failed: " .. handle.error, vim.log.levels.ERROR, { title = "math-conceal" })
      else
        report("Service installed", 100)
        vim.notify(
          "Service installed. Restart Neovim if the service is already running.",
          vim.log.levels.INFO,
          { title = "math-conceal" }
        )
      end
    end
  end
  task = coroutine.create(function()
    local tag = release.release_tag(root)
    local uname = vim.uv.os_uname()
    local asset = release.asset_name(uname.sysname, uname.machine)
    local function fetch(url, path)
      local checksum = url:match("%.sha256$") ~= nil
      local label = checksum and "Downloading checksum" or ("Downloading service " .. tag)
      report(label, 0)
      local stderr, last_percent = "", -1
      vim.system({
        "curl",
        "--fail",
        "--location",
        "--progress-bar",
        "--connect-timeout",
        "30",
        "--max-time",
        "300",
        "--retry",
        "2",
        "--output",
        path,
        url,
      }, {
        stderr = function(_, data)
          if not data then
            return
          end
          stderr = (stderr .. data):sub(-8192)
          local percent
          for value in stderr:gmatch("(%d+%.?%d*)%%") do
            percent = math.min(100, math.floor(tonumber(value)))
          end
          if percent and percent ~= last_percent then
            last_percent = percent
            vim.schedule(function()
              if not handle.done then
                report(label, percent)
              end
            end)
          end
        end,
      }, function(result)
        vim.schedule(function()
          resume(result.code == 0, result.code == 0 and nil or ("curl exited " .. result.code .. ": " .. stderr))
        end)
      end)
      local ok, err = coroutine.yield()
      assert(ok, err)
      report(checksum and "Checksum downloaded" or "Verifying service", 100)
    end
    handle.path = release.install(root, tag, asset, fetch)
  end)
  resume()
  if opts.wait then
    -- Process UI/events while keeping lazy.nvim's build task pending until completion.
    vim.wait(2147483647, function()
      return handle.done
    end, 50)
    if not handle.done then
      error("Interrupted while waiting for service installation")
    end
    if handle.error then
      error(handle.error, 0)
    end
  end
  return handle
end

return M
