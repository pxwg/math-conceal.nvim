-- Run after building: nvim --headless -u NONE -i NONE -l scripts/package-service.lua <target>
local release = dofile("lua/math-conceal/service_release.lua")
local target = assert(arg[1], "Expected Rust target")
assert(target:match("^[%w_-]+$"), "Invalid Rust target")
local asset = "typst-concealer-service-" .. target
vim.fn.mkdir("dist", "p")
assert(vim.uv.fs_copyfile("service/target/" .. target .. "/release/typst-concealer-service", "dist/" .. asset))
local digest = vim.fn.sha256(release.read("dist/" .. asset))
release.write("dist/" .. asset .. ".sha256", digest .. "  " .. asset .. "\n")
print("Packaged " .. asset)
