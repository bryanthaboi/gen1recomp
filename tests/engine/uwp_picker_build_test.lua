-- Packaging must compile the native bridge rather than ship the old DLL.
package.path = "./?.lua;./?/init.lua;" .. package.path
local S = require("tests.harness").suite("UWP picker build routing")
local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end
for _, path in ipairs({ ".github/workflows/ci.yml", ".github/workflows/release.yml" }) do
  local workflow = read(path)
  local rebuild = workflow:find("run: ./scripts/xbox-uwp/rebuild_dependencies.ps1 -SkipAngle -SkipPackage", 1, true)
  local package = workflow:find("- name: Build Xbox UWP package", 1, true)
  S.check(rebuild and package and rebuild < package,
    path .. " rebuilds the native picker before packaging")
end
local manifest = require("src.link.Json").decode(read("ports/uwp/third_party/manifest.json"))
local patch = read("ports/uwp/third_party/" .. manifest.sources.love.patch)
S.check(patch:find('luaL_optstring(L, 2, nullptr)', 1, true) ~= nil,
  "the build's declared patch exposes the optional format argument")
S.check(patch:find('uwp::pickFile(kind, formats)', 1, true) ~= nil
    and patch:find('openPicker(requestedKind, extensions)', 1, true) ~= nil,
  "declared native patch carries formats through the asynchronous picker")
S.finish()
