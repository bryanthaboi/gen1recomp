#!/usr/bin/env luajit
-- pokefirered/src/heal_location.c:119 SetWhiteoutRespawnHealerNpcAsLastTalked

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local function done()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

require("src.core.GameVersion").set("firered")

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] game3_stitchfield_whiteout_test: " .. tostring(Cache.reason))
  done()
end

local Dataset = require("src.core.game3.dataset")
local Runtime = require("src.core.game3.runtime")
local Map = require("src.core.game3.map")
local Field = require("src.core.game3.field")
local Space = require("src.core.game3.scripting.space")
local Flags = require("src.core.game3.scripting.flags")
local Ctx = require("src.core.game3.scripting.ctx")
local HealLocations = require("src.core.game3.heal_locations")
local Schema = require("src.core.game3.save_schema_firered")

local game = { data = {} }
Dataset.hydrate(game)
local session = Schema.newGame({ rngSeed = 0x4141 })
game.session = session
Runtime.start(nil, game, session, { reason = "new_game" })
Field._game = game
Field._session = session
Field.running = true

-- pokefirered/src/data/heal_locations.h:129 sWhiteoutRespawnHealCenterMapIdxs
local PEWTER, PEWTER_ID
for id = 1, 20 do
  local loc = HealLocations.get(id)
  if loc and type(loc.map) == "string" and loc.map:find("PEWTER", 1, true) then
    PEWTER, PEWTER_ID = loc, id
    break
  end
end
check(PEWTER ~= nil, "the baked heal locations carry a Pewter City row")
if not PEWTER then done() end
check(game.data.maps[PEWTER.map] ~= nil, PEWTER.map .. " is in the cache")
if not game.data.maps[PEWTER.map] then done() end

print("[test] 1. setrespawn stores the healer NPC beside the tile")
check(HealLocations.applyToSession(session, PEWTER_ID), "the respawn point applied")
eq(session.healMap, PEWTER.map, "the whiteout map is the Pewter centre")
eq(session.healHealerLocalId, PEWTER.healerLocalId, "and its healer local id came with it")
check(tonumber(session.healHealerLocalId) ~= 1,
  "Pewter's nurse is not the default localId 1 (" .. tostring(session.healHealerLocalId) .. ")")

print("[test] 2. whiting out talks to that NPC")
local START = "FR_VIRIDIAN_FOREST"
Map.load(nil, game, START, { x = 5, y = 9, facing = "down" })
Flags.setVar(Space.store, Space.vm and Space.vm.ctx, Ctx.VAR_LAST_TALKED, 0)
-- pokefirered/src/overworld.c:626 Overworld_SetWhiteoutRespawnPoint
Field.respawnAtHeal({})
eq(session.map, PEWTER.map, "the whiteout landed in the Pewter centre")
eq(Flags.getVar(Space.store, Space.vm and Space.vm.ctx, Ctx.VAR_LAST_TALKED),
  tonumber(PEWTER.healerLocalId),
  "gSpecialVar_LastTalked is the healer the nurse script faces")

print("[test] 3. a DIG out of a cave does not touch it")
Map.load(nil, game, START, { x = 5, y = 9, facing = "down" })
-- pokefirered/src/field_effect.c:2126 SetWarpDestinationToEscapeWarp
Field.respawnAtHeal({ fieldMove = true })
eq(session.map, PEWTER.map, "the field move still warps")
eq(Flags.getVar(Space.store, Space.vm and Space.vm.ctx, Ctx.VAR_LAST_TALKED), 0,
  "but only CB2_WhiteOut sets the healer NPC")

done()
