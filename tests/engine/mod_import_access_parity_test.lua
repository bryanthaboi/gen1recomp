-- No-mod and API-v1 parity coverage for additive mod.imports/mod.cache.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

-- No mod installed: no generated cache namespace is touched.
local emptyFiles = {}
local none = T.sdk.loadNone({ fs = T.sdk.memfs(emptyFiles) })
T.eq(#none.errors, 0, "zero-mod load remains clean")
for path in pairs(emptyFiles) do
  T.check(path:sub(1, 10) ~= "mod_cache/",
    "zero-mod load creates no installation cache data")
end
none.release()

-- Existing API-v1 style file access still behaves exactly as before. The new
-- facades are additive members; mod:read remains the same scoped read path.
local files = {
  ["mods/v1_read_probe/manifest.json"] = [[{
    "id": "v1_read_probe",
    "name": "V1 Read Probe",
    "version": "1.0.0",
    "entry": "main.lua",
    "api": 1
  }]],
  ["mods/v1_read_probe/main.lua"] = [[
    local mod = ...
    mod.exports.payload = mod:read("payload.txt")
    mod.exports.hasImports = type(mod.imports) == "table"
    mod.exports.hasCache = type(mod.cache) == "table"
  ]],
  ["mods/v1_read_probe/payload.txt"] = "unchanged-v1-read",
}
local run = T.sdk.loadMods({ "mods/v1_read_probe" }, { fs = T.sdk.memfs(files) })
T.eq(#run.errors, 0, "API-v1 probe still loads")
local out = run.loader.exports.v1_read_probe
T.eq(out.payload, "unchanged-v1-read", "mod:read keeps its v1 behavior")
T.eq(out.hasImports, true, "new import facade is additive")
T.eq(out.hasCache, true, "new cache facade is additive")
run.release()

T.finish("mod_import_access_parity")
