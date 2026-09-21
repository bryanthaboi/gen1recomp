#!/usr/bin/env luajit
-- pokefirered/src/safari_zone.c:60 CB2_EndSafariBattle
-- pokefirered/data/scripts/safari_zone.inc:1 SafariZone_EventScript_OutOfBallsMidBattle
-- pokefirered/data/scripts/safari_zone.inc:31 SafariZone_EventScript_OutOfBalls

package.path = "./?.lua;./?/init.lua;" .. package.path

package.loaded["src.core.game3.audio"] = setmetatable({}, {
  __index = function() return function() end end,
})

local failed, passed = 0, 0
local function check(cond, msg)
  if cond then
    passed = passed + 1
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function finish()
  print(string.format("\n%d passed, %d failed", passed, failed))
  if failed == 0 then print("STITCHBATTLE_SAFARI_EXIT PASS") end
  os.exit(failed == 0 and 0 or 1)
end

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] game3_stitchbattle_safari_exit_test: " .. tostring(Cache.reason))
  os.exit(0)
end

local Pokemon = require("src.core.game3.pokemon")
Pokemon.install(nil)
local FOE_SPECIES = 16

local Dataset = require("src.core.game3.dataset")
local Collision = require("src.core.game3.collision")
local Objects = require("src.core.game3.objects")
local Field = require("src.core.game3.field")
local Space = require("src.core.game3.scripting.space")
local Flags = require("src.core.game3.scripting.flags")
local Warp = require("src.core.game3.warp")
local Runtime = require("src.core.game3.runtime")
local Map = require("src.core.game3.map")
local Safari = require("src.core.game3.safari")
local Battle = require("src.core.game3.battle")
local Ui = require("src.core.game3.battle.ui")
local Commands = require("src.core.game3.battle.commands")
local Natives = require("src.core.game3.scripting.natives")

local SAFARI_MAP = "FR_SAFARI_ZONE_CENTER"

local game = { data = {} }
Dataset.hydrate(game)
local session = {
  map = nil, flags = {}, vars = {}, name = "RED",
  dex = { seen = {}, owned = {} },
  party = {
    { species = 1, name = "BULBASAUR", level = 10, hp = 30, maxHp = 30,
      attack = 12, defense = 12, spAtk = 12, spDef = 12, speed = 12,
      moves = { 33 }, pp = { 35 } },
  },
}
game.session = session
Runtime.session = session
Runtime._game = game

local announced = {}
Safari.presenter = {
  message = function(text, onDone) announced[#announced + 1] = text; onDone() end,
  yesNo = function(onPick) onPick(true) end,
  close = function() end,
}

local function enterSafariMap()
  local def = game.data.maps[SAFARI_MAP]
  Field._game = game
  Field._session = session
  session.map = SAFARI_MAP
  Field.running = true
  Field.locked = false
  Space.activate(nil, SAFARI_MAP, game, nil)
  Collision.bindMap(game, SAFARI_MAP, def)
  Objects.loadMap(game, SAFARI_MAP, def)
  return def
end

local function sceneVar()
  return Flags.getVar(Space.store, nil, Safari.VAR_ENTRANCE_SCENE)
end

local function logHas(text)
  for _, t in ipairs(Ui.log() or {}) do
    if tostring(t):find(text, 1, true) then return true end
  end
  return false
end

local function throwLastBall(catches)
  announced = {}
  Warp.clear()
  enterSafariMap()
  Safari.enter(session)
  session.safari.balls = 1
  Flags.setVar(Space.store, nil, Safari.VAR_ENTRANCE_SCENE, 0)
  Battle.abort()
  Battle.start({
    headless = true,
    autoFight = false,
    wild = true,
    safari = true,
    session = session,
    playerParty = session.party,
    rng = function(lo, hi) return catches and lo or hi end,
    foe = { species = FOE_SPECIES, level = 8, hp = 24, maxHp = 24,
      attack = 10, defense = 10, spAtk = 10, spDef = 10, speed = 30,
      moves = { 33 }, pp = { 35 } },
  })
  local st = Battle.getState()
  for _ = 1, 60 do
    if Battle._phase == "command" then break end
    Battle.update(0, nil)
  end
  Ui._log = {}
  Ui._pendingCommand = Commands.playerAction(st, 1, nil)
  for _ = 1, 40 do
    if not Battle.isActive() then break end
    Battle.update(0, nil)
  end
  return st
end

print("[test] 1. the last ball misses: OutOfBallsMidBattle, no PA line")
do
  local st = throwLastBall(false)
  check(not Battle.isActive(), "the safari battle is over")
  -- pokefirered/data/battle_scripts_2.s:110
  check(logHas("out of\nSAFARI BALLS"), "the ANNOUNCER line played inside the battle")
  -- pokefirered/data/battle_scripts_2.s:112
  check(st.result == "no_safari_balls", "outcome is B_OUTCOME_NO_SAFARI_BALLS, not RAN (got "
    .. tostring(st.result) .. ")")
  check(Natives.outcome_to_code(st.result) == Natives.B_OUTCOME.NO_SAFARI_BALLS,
    "which battle_bridge writes to session.battleOutcome as 8")
  -- pokefirered/src/safari_zone.c:68
  check(#announced == 0, "no field PA announcement on the mid-battle branch (got "
    .. tostring(#announced) .. ")")
  -- pokefirered/data/scripts/safari_zone.inc:2
  check(sceneVar() == 3, "VAR_MAP_SCENE_FUCHSIA_CITY_SAFARI_ZONE_ENTRANCE is 3 for ExitWalkIn (got "
    .. tostring(sceneVar()) .. ")")
  -- pokefirered/data/scripts/safari_zone.inc:3
  check(Safari.isActive(session) == false, "ExitSafariMode ran")
  -- pokefirered/data/scripts/safari_zone.inc:4
  check(Map.current == Safari.EXIT_MAP, "the player is at the Fuchsia gate (got "
    .. tostring(Map.current) .. ")")
  check(#session.party == 1, "nothing was caught")
  -- pokefirered/src/safari_zone.c:62
  check(Field.pollSafariBalls(game) == false, "the field poll does not run the exit a second time")
  check(#announced == 0, "and still no PA line")
end

print("[test] 2. the last ball catches: the mon is kept, then OutOfBalls")
do
  local st = throwLastBall(true)
  check(not Battle.isActive(), "the safari battle is over")
  -- pokefirered/data/battle_scripts_2.s:96
  check(st.result == "catch", "outcome is B_OUTCOME_CAUGHT (got " .. tostring(st.result) .. ")")
  check(logHas("was caught!"), "the Gotcha line played inside the battle")
  check(#session.party == 2, "the caught mon is kept (party " .. tostring(#session.party) .. ")")
  -- pokefirered/src/safari_zone.c:73
  check(#announced == 0, "the announcement has not run yet when the battle ends")
  check(Safari.isActive(session) == true, "and safari mode is still on")
  check(sceneVar() ~= 3, "the mid-battle branch did not run (scene " .. tostring(sceneVar()) .. ")")
  -- pokefirered/src/safari_zone.c:75
  check(Field.pollSafariBalls(game) == true, "CB2_EndSafariBattle runs OutOfBalls after the catch")
  check(#announced == 1 and tostring(announced[1]):find("out of SAFARI BALLS", 1, true) ~= nil,
    "SafariZone_Text_OutOfBalls is the PA line")
  -- pokefirered/data/scripts/safari_zone.inc:8
  check(sceneVar() == 1, "VAR_MAP_SCENE_FUCHSIA_CITY_SAFARI_ZONE_ENTRANCE is 1 for ExitWarpIn (got "
    .. tostring(sceneVar()) .. ")")
  check(Safari.isActive(session) == false, "ExitSafariMode ran")
  check(Warp._pending ~= nil and Warp._pending.mapId == Safari.EXIT_MAP,
    "with a warp to the Fuchsia gate")
  check(#session.party == 2, "the caught mon survived the exit")
  Warp.clear()
end

print("[test] 3. balls left keeps the SAFARI GAME going")
do
  announced = {}
  Warp.clear()
  enterSafariMap()
  Safari.enter(session)
  session.safari.balls = 2
  Flags.setVar(Space.store, nil, Safari.VAR_ENTRANCE_SCENE, 0)
  Battle.abort()
  Battle.start({
    headless = true, autoFight = false, wild = true, safari = true,
    session = session, playerParty = session.party,
    rng = function(_, hi) return hi end,
    foe = { species = FOE_SPECIES, level = 8, hp = 24, maxHp = 24,
      attack = 10, defense = 10, spAtk = 10, spDef = 10, speed = 30,
      moves = { 33 }, pp = { 35 } },
  })
  local st = Battle.getState()
  for _ = 1, 60 do
    if Battle._phase == "command" then break end
    Battle.update(0, nil)
  end
  Ui._pendingCommand = Commands.playerAction(st, 1, nil)
  for _ = 1, 40 do Battle.update(0, nil) end
  -- pokefirered/src/safari_zone.c:62
  check(Battle.isActive() == true, "one ball left, the battle carries on")
  check(st.safariState.balls == 1, "and one ball is left")
  Battle.abort()
  check(sceneVar() ~= 3 and Safari.isActive(session) == true,
    "no exit was staged while balls remain")
  Safari.exit(session)
  Warp.clear()
end

finish()
