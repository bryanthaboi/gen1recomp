-- A sandboxed mod can distinguish an engine developer boot without reading
-- the host environment or using a legacy compatibility shim.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local FILES = {
  ["mods/dev_probe/manifest.json"] = [[{
    "id": "dev_probe",
    "name": "Developer Mode Probe",
    "version": "1.0.0",
    "entry": "main.lua",
    "api": 2
  }]],
  ["mods/dev_probe/main.lua"] = [[
local mod = ...
mod.exports.value = mod.dev
mod.exports.valueType = type(mod.dev)
]],
}

for _, enabled in ipairs({ false, true, "yes", 1 }) do
  local expectedDev = enabled == true
  local run = T.sdk.loadMod("mods/dev_probe", {
    fs = T.sdk.memfs(FILES), dev = enabled,
  })
  T.eq(#run.errors, 0,
    "developer-mode probe loads cleanly")
  local out = run.loader.exports.dev_probe or {}
  T.eq(out.value, expectedDev,
    "mod.dev reflects the fixed engine developer-mode state")
  T.eq(run.loader.dev, expectedDev,
    "loader developer-mode state is a strict boolean")
  T.eq(out.valueType, "boolean",
    "mod.dev is always a strict boolean")
  T.eq(#run.loader:legacyReport("dev_probe"), 0,
    "reading mod.dev needs no legacy host-environment shim")
  run.release()
end

T.finish("public mod developer-mode signal")
