#!/usr/bin/env luajit
-- pokefirered/src/field_effect.c:2126 SetWarpDestinationToEscapeWarp

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

package.loaded["src.core.game3.audio"] = setmetatable({}, {
  __index = function() return function() end end,
})

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] game3_moveteach_dig_escape_test: " .. tostring(Cache.reason))
  done()
end

local Dataset = require("src.core.game3.dataset")
local MapCatalog = require("src.import.gba.map_catalog")
local Runtime = require("src.core.game3.runtime")
local Map = require("src.core.game3.map")
local Player = require("src.core.game3.player")
local Field = require("src.core.game3.field")
local FieldMoves = require("src.core.game3.field_moves")
local PartyMenu = require("src.ui.game3.party_menu")
local Schema = require("src.core.game3.save_schema_firered")

local CAVE = MapCatalog.pretToEngine("RockTunnel_1F")
local TOWN = MapCatalog.pretToEngine("LavenderTown")

local game = { data = {} }
Dataset.hydrate(game)
check(game.data.maps[CAVE] ~= nil, CAVE .. " is in the cache")
check(game.data.maps[TOWN] ~= nil, TOWN .. " is in the cache")
if not (game.data.maps[CAVE] and game.data.maps[TOWN]) then done() end

local session = Schema.newGame({ rngSeed = 0x5151 })
game.session = session
Runtime.start(nil, game, session, { reason = "new_game" })
Field._game = game
Field._session = session
Field.running = true

-- pokefirered/src/overworld.c:651 SetEscapeWarp
local ESCAPE = { map = TOWN, warpId = 255, x = 5, y = 7 }
session.healMap = "FR_PLAYERS_HOUSE_1F"
session.healX, session.healY = 8, 5
session.escapeWarp = ESCAPE

local function enterCave()
  Map.load(nil, game, CAVE, { x = 4, y = 4, facing = "down" })
  Player.reset(4, 4, "down")
end

print("[test] 1. the party menu hands DIG the stored escape warp")
enterCave()
local captured = nil
local realExec = Field.executeFieldMove
Field.executeFieldMove = function(payload) captured = payload end

local mon = {
  species = 6, level = 40, hp = 100, maxHp = 100,
  stats = { hp = 100 }, moves = { "DIG" }, pp = { 10, 10, 10, 10 },
}
local function press(key)
  PartyMenu.handleInput({
    wasPressed = function(_, k) return k == key end,
    isDown = function(_, k) return k == key end,
  })
end

PartyMenu.show({ mon }, nil, { session = session })
press("a")
local target = nil
for i, label in ipairs(PartyMenu.ACTIONS) do
  if label == "DIG" then target = i end
end
check(target ~= nil, "DIG is on the action list")
while target and PartyMenu.actionCursor ~= target do press("down") end
press("a")
if PartyMenu.open then PartyMenu.close() end
Field.executeFieldMove = realExec

check(type(captured) == "table", "DIG ran a field move (" .. tostring(captured) .. ")")
if type(captured) ~= "table" then done() end
eq(captured.action, "dig", "the payload is a dig")
eq(captured.warp, ESCAPE, "and it carries session.escapeWarp, not nil")

print("[test] 2. the dig warp is the escape warp, not the heal spot")
enterCave()
Field.respawnAtHeal({ fieldMove = true, warp = captured.warp })
eq(session.map, TOWN, "DIG dropped the player on the escape warp's map")
eq(Player.cellX, ESCAPE.x, "at its column")
eq(Player.cellY, ESCAPE.y, "and its row")

print("[test] 2b. the real executeFieldMove hands payload.warp on")
enterCave()
local FieldEffects = require("src.core.game3.field_effects")
local realSpin = FieldEffects.startWarpSpin
FieldEffects.startWarpSpin = function(_, cb) cb() end
session.party = { mon }
mon.hp, mon.status = 1, "PSN"
Field.executeFieldMove({ action = "dig", warp = ESCAPE })
FieldEffects.startWarpSpin = realSpin
eq(session.map, TOWN, "executeFieldMove reached respawnAtHeal with payload.warp")
eq(Player.cellX, ESCAPE.x, "and landed on the escape warp's column")
eq(Player.cellY, ESCAPE.y, "and its row")
-- pokefirered/src/overworld.c:1553 CB2_WhiteOut
eq(mon.hp, 1, "DIG did not heal the party")
eq(mon.status, "PSN", "and did not cure its status")

print("[test] 3. with no escape warp recorded it still falls back to the heal spot")
enterCave()
session.escapeWarp = nil
local ctx = { mapType = game.data.maps[CAVE].mapType, isCave = true, canEscapeRope = true,
  party = { mon }, escapeWarp = session.escapeWarp }
local res = FieldMoves.digFromMenu(ctx)
check(res.ok == true, "DIG is still allowed in the cave")
eq(res.warp, nil, "with nothing to warp to")
Field.respawnAtHeal({ fieldMove = true, warp = res.warp })
eq(session.map, session.healMap, "so the player lands on the last heal location")
eq(Player.cellX, session.healX, "at the heal tile")

print("[test] 4. TELEPORT keeps the heal location whatever the escape warp says")
enterCave()
session.escapeWarp = ESCAPE
-- pokefirered/src/field_effect.c:2431 SetWarpDestinationToLastHealLocation
local tp = FieldMoves.teleportFromMenu({ mapType = 1, party = { mon },
  lastHealWarp = { map = session.healMap, x = session.healX, y = session.healY } })
check(tp.ok == true, "TELEPORT is allowed outdoors")
eq((tp.warp or {}).map, session.healMap, "and it aims at the heal location")

done()
