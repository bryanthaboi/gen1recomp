package.path = "./?.lua;./?/init.lua;" .. package.path
local S = require("tests.harness").suite("UWP picker build routing")
local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end
local dll = read("ports/uwp/third_party/love/bin/love.dll")
S.check(dll:find("gb,gbc,gba", 1, true) ~= nil,
  "shipped love.dll is built with the descriptor-format picker patch")
S.check(dll:find((".g1rcart"):gsub(".", "%0\0"), 1, true) ~= nil
    and dll:find("picked_cart.g1rcart", 1, true) ~= nil,
  "shipped love.dll offers the .g1rcart cart picker")
local manifest = require("src.link.Json").decode(read("ports/uwp/third_party/manifest.json"))
local patch = read("ports/uwp/third_party/" .. manifest.sources.love.patch)
S.check(patch:find('luaL_optstring(L, 2, nullptr)', 1, true) ~= nil,
  "the build's declared patch exposes the optional format argument")
S.check(patch:find('uwp::pickFile(kind, formats)', 1, true) ~= nil
    and patch:find('openPicker(requestedKind, extensions)', 1, true) ~= nil,
  "declared native patch carries formats through the asynchronous picker")
S.finish()
