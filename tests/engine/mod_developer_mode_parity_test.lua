-- No-mod and API-v1 parity for the additive mod.developer surface.
--
-- The production break this catches is a developer-mode loader path that
-- mutates vanilla data, creates mod state, or changes existing API-v1
-- behavior merely because the new public signal exists.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local function pristine()
  return {
    pokemon = { KEEP = { hp = 7 } },
    moves = {},
  }
end

for _, dev in ipairs({ false, true }) do
  local data = pristine()
  local files = {}
  local run = T.sdk.loadNone({
    data = data,
    fs = T.sdk.memfs(files),
    dev = dev,
  })
  T.eq(#run.errors, 0,
    "no-mod load stays clean with developer=" .. tostring(dev))
  T.eq(next(run.loader.mods), nil,
    "no-mod load discovers nothing with developer=" .. tostring(dev))
  T.eq(data.pokemon.KEEP.hp, 7,
    "no-mod load preserves vanilla data with developer=" .. tostring(dev))
  T.eq(next(files), nil,
    "no-mod load creates no files with developer=" .. tostring(dev))
  run.release()
end

local V1 = {
  ["mods/v1_probe/manifest.json"] = [[{
    "id": "v1_probe",
    "name": "V1 Probe",
    "version": "1.0.0",
    "entry": "main.lua",
    "api": 1
  }]],
  ["mods/v1_probe/main.lua"] = [[
    local mod = ...
    mod.exports.identity = mod.id .. "@" .. mod.version
    mod.exports.payload = mod:read("payload.txt")
    mod.options:define({ { key = "enabled", type = "toggle", default = true } })
    mod.exports.defaultOption = mod.options:get("enabled")
  ]],
  ["mods/v1_probe/payload.txt"] = "unchanged-v1",
}

local legacy = T.sdk.loadMods({ "mods/v1_probe" }, {
  fs = T.sdk.memfs(V1),
  dev = false,
})
T.eq(#legacy.errors, 0, "existing API-v1 mod loads unchanged")
local out = legacy.loader.exports.v1_probe
T.eq(out.identity, "v1_probe@1.0.0", "API-v1 identity stays unchanged")
T.eq(out.payload, "unchanged-v1", "API-v1 mod:read stays unchanged")
T.eq(out.defaultOption, true, "API-v1 options stay unchanged")
legacy.release()

T.finish("mod developer mode parity")
