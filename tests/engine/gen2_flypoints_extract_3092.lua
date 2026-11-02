-- pokegold data/maps/flypoints.asm:1, data/events/engine_flags.asm:75-101
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local F = require("tests.engine._xgen_fixture")
local Fixture = require("tests.fixtures.gen2_flypoints")

local seen = 0
for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local root = F.cacheRoot(version)
  local prefix = require("src.core.GameVersion").cachePrefix(version)
  local chunk = root and loadfile(root .. "/" .. prefix .. "data/generated/landmarks.lua")
  if chunk then
    seen = seen + 1
    local landmarks = chunk()
    local rows = landmarks.flypoints
    T.check(type(rows) == "table", version .. ": landmarks.lua carries flypoints")
    rows = type(rows) == "table" and rows or {}
    local count = 0
    for _ in pairs(rows) do count = count + 1 end
    T.eq(count, 24, version .. ": 24 Flypoints rows")
    for spawn, want in pairs(Fixture.rows(version)) do
      local got = rows[spawn] or {}
      T.eq(got.landmark, want.landmark, version .. ": " .. spawn .. " landmark")
      T.eq(got.region, want.region, version .. ": " .. spawn .. " region")
      T.eq(got.order, want.order, version .. ": " .. spawn .. " order")
      T.eq(got.flag, want.flag, version .. ": " .. spawn .. " engine flag")
    end
    T.eq((rows.SPAWN_AZALEA or {}).flag, version == "crystal" and 68 or 67,
      version .. ": AZALEA is bit 18, SPAWN_UNION_CAVE has no flag")
    local FieldMoves = require("src.world.gen2.FieldMoves")
    FieldMoves.bindFlypoints(rows, landmarks.spawns)
    T.eq(#FieldMoves.FLYPOINTS, 24, version .. ": every row has a spawn")
    T.eq(FieldMoves.KANTO_FLYPOINT, 13, version .. ": Kanto starts at Pallet")
    T.eq((FieldMoves.FLYPOINTS[1] or {}).spawn, "SPAWN_NEW_BARK",
      version .. ": New Bark first")
    T.eq((FieldMoves.FLYPOINTS[24] or {}).spawn, "SPAWN_INDIGO",
      version .. ": Indigo last")
    FieldMoves.bindFlypoints(nil)
  end
end
if seen == 0 then
  print("[skip] gen2 flypoints extract: no Gold/Silver/Crystal cache")
  os.exit(0)
end
T.finish("gen2 flypoints extract 3092")
