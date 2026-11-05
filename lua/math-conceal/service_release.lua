-- Shared release helpers, loaded by the installer, packager, and headless tests.
local M = {}

local function run(argv)
  local result = vim.system(argv, { text = true }):wait()
  if result.code ~= 0 then
    error(table.concat(argv, " ") .. ": " .. (result.stderr or "command failed"), 0)
  end
  return vim.trim(result.stdout or "")
end

function M.read(path)
  local file = assert(io.open(path, "rb"))
  local data = file:read("*a")
  file:close()
  return data
end

function M.write(path, data)
  local file = assert(io.open(path, "wb"))
  assert(file:write(data))
  assert(file:close())
end

function M.asset_name(system, machine)
  local targets = {
    Linux = { x86_64 = "x86_64-unknown-linux-gnu" },
    Darwin = { arm64 = "aarch64-apple-darwin", x86_64 = "x86_64-apple-darwin" },
  }
  local target = targets[system] and targets[system][machine]
  assert(target, "No prebuilt service for " .. system .. "/" .. machine .. "; build from source with Cargo.")
  return "typst-concealer-service-" .. target
end

function M.release_tag(root)
  local result = vim
    .system({ "git", "-C", root, "describe", "--tags", "--exact-match", "HEAD" }, { text = true })
    :wait()
  local tag = vim.trim(result.stdout or "")
  local version, suffix = tag:match("^v?(%d+%.%d+%.%d+)(.*)$")
  local valid_suffix = suffix == "" or (suffix and suffix:match("^[-+][%w.-]+$"))
  assert(
    result.code == 0 and version and valid_suffix,
    "Checkout is not a release tag. Use a tagged release, or run cargo build --release --locked --manifest-path service/Cargo.toml."
  )
  return tag
end

function M.download(url, path)
  run({
    "curl",
    "--fail",
    "--location",
    "--silent",
    "--show-error",
    "--connect-timeout",
    "30",
    "--max-time",
    "300",
    "--retry",
    "2",
    "--output",
    path,
    url,
  })
end

function M.install(root, tag, asset, fetch)
  fetch = fetch or M.download
  local destination = root .. "/service/target/release"
  vim.fn.mkdir(destination, "p")
  local binary = destination .. "/typst-concealer-service"
  local encoded_tag = tag:gsub("[^%w._~-]", function(char)
    return string.format("%%%02X", char:byte())
  end)
  local base = "https://github.com/pxwg/math-conceal.nvim/releases/download/" .. encoded_tag
  -- Keep staging on the same filesystem for atomic replacement.
  local staging = assert(vim.uv.fs_mkdtemp(destination .. "/.service-download-XXXXXX"))
  local ok, err = pcall(function()
    local checksum, payload = staging .. "/checksum", staging .. "/" .. asset
    fetch(base .. "/" .. asset .. ".sha256", checksum)
    local digest, filename = M.read(checksum):match("^(%x+)%s+(%S+)%s*$")
    assert(digest and #digest == 64 and filename == asset, "Invalid release checksum file")
    fetch(base .. "/" .. asset, payload)
    assert(vim.fn.sha256(M.read(payload)) == digest:lower(), "Service checksum mismatch; existing binary was preserved")
    assert(vim.uv.fs_chmod(payload, 493)) -- 0755
    assert(vim.uv.fs_rename(payload, binary))
  end)
  vim.fn.delete(staging, "rf")
  if not ok then
    error(err, 0)
  end
  return binary
end

return M
