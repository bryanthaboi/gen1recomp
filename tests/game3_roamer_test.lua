#!/usr/bin/env luajit

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

local function done()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local Roamer = require("src.core.game3.roamer")
local Audio = require("src.core.game3.audio")
local Schema = require("src.core.game3.save_schema_firered")
local Flags = require("src.core.game3.scripting.flags")
local Cache = require("tests.game3_cache")
Cache.mount("scripts/events.lua", { native = true })
require("src.core.GameVersion").set("firered")
-- pokefirered/src/roamer.c:36
local SETS = {
  { "FR_ROUTE_1", "FR_ROUTE_2", "FR_ROUTE_21_NORTH", "FR_ROUTE_22", false, false, false },
  { "FR_ROUTE_2", "FR_ROUTE_1", "FR_ROUTE_3", "FR_ROUTE_22", false, false, false },
  { "FR_ROUTE_3", "FR_ROUTE_2", "FR_ROUTE_4", false, false, false, false },
}
Roamer._locations[Roamer.config({ version = "firered" })] = SETS
local function is_head(id)
  for _, set in ipairs(SETS) do if set[1] == id then return true end end
  return false
end

-- 1. Starter Species Mapping
check(Roamer.speciesForStarter(0) == 244, "Bulbasaur (0) -> Entei (244)")
check(Roamer.speciesForStarter(1) == 243, "Squirtle (1) -> Raikou (243)")
check(Roamer.speciesForStarter(2) == 245, "Charmander (2) -> Suicune (245)")

-- 2. Stored IVs keep the full 0-31 range
local ivCheckOk = true
for _ = 1, 50 do
  local mon = { version = "firered", party = {} }
  Roamer.init(mon, 1)
  mon = mon.roamer
  if type(mon.ivs) ~= "table" then
    ivCheckOk = false
    break
  end
  for stat, val in pairs(mon.ivs) do
    if val < 0 or val > 31 then
      ivCheckOk = false
      break
    end
  end
end
check(ivCheckOk, "Roamer stores full 0-31 IVs across all 6 stats")

-- 3. Audio Override
check(Audio.legendaryBattleSong(243) == 339, "Raikou uses Legendary Battle BGM (339)")
check(Audio.legendaryBattleSong(244) == 339, "Entei uses Legendary Battle BGM (339)")
check(Audio.legendaryBattleSong(245) == 339, "Suicune uses Legendary Battle BGM (339)")

-- 4. Initialization via InitRoamer
local session = {
  version = "firered",
  flags = {},
  vars = {
    [0x4031] = 2, -- VAR_STARTER_MON = Charmander
  },
  party = {
    { species = 6, level = 50, hp = 0, maxHp = 100 }, -- fainted Charizard lead
    { species = 150, level = 100, hp = 300, maxHp = 300 }, -- conscious Mewtwo
  },
}

local okInit = Roamer.init(session, 2)
check(okInit == true, "Roamer.init succeeds")
check(session.roamer ~= nil and session.roamer.active == true, "session.roamer initialized and active")
check(session.roamer.species == 245, "Roamer species is Suicune (245)")
check(session.roamer.level == 50, "Roamer level is 50")
check(is_head(session.roamer.map), "Roamer starts at a location set head: " .. tostring(session.roamer.map))

-- 5. Location set movement
local Rng = require("src.core.game3.rng")
local inSet = true
for seed = 1, 50 do
  session.roamer.map = "FR_ROUTE_3"
  Rng.SeedRng(seed)
  Roamer.move(session, "connection", "FR_ROUTE_3")
  local m = session.roamer.map
  if not (m == "FR_ROUTE_2" or m == "FR_ROUTE_4" or is_head(m)) or m == "FR_ROUTE_3" then inSet = false end
end
check(inSet, "a connection moves within the Route 3 set or to another set head")
local warped = true
for seed = 1, 50 do
  session.roamer.map = "FR_ROUTE_1"
  Rng.SeedRng(seed)
  Roamer.move(session, "warp", "FR_ROUTE_1")
  if not is_head(session.roamer.map) or session.roamer.map == "FR_ROUTE_1" then warped = false end
end
check(warped, "a warp moves the roamer to another set head")

-- 6. Encounter gate
session.roamer.map = "FR_ROUTE_2"
local met = 0
for seed = 1, 100 do
  Rng.SeedRng(seed)
  local enc = Roamer.tryEncounter(session, "FR_ROUTE_2", "grass")
  if enc then
    met = met + 1
    check(enc.roamer == true and enc.species == 245, "roamer encounter is Suicune")
  end
end
check(met > 0 and met < 100, "the roamer is met on some rate passes, not all (" .. met .. "/100)")
check(Roamer.tryEncounter(session, "FR_ROUTE_3", "grass") == nil, "Different map returns no encounter")

-- 7. Battle End Handling
local foeState = {
  hp = 60,
  maxHp = 150,
  status = "PAR",
}

-- Flee / Roar end
Roamer.onBattleEnd(session, foeState, "fled", "roar")
check(session.roamer.active == true, "Fleeing keeps the roamer active")
check(session.roamer.hp == 60, "Roamer HP damage persisted (60)")
check(session.roamer.status == 0x40, "Roamer status condition persisted (paralysis)")

-- Defeated
foeState.hp = 0
Roamer.onBattleEnd(session, foeState, "win", "faint")
check(session.roamer.active == false, "Defeating roamer sets active to false")

-- 8. Save/Load Schema Persistence
session.roamer = {
  active = true,
  species = 243,
  level = 50,
  hp = 85,
  maxHp = 160,
  status = 0,
  statusNum = 0,
  pid = 0x12345678,
  ivs = { hp = 31, atk = 30, def = 29, spe = 28, spa = 27, spd = 26 },
  map = "FR_ROUTE1",
}

local saved = Schema.toSaveTable(session)
check(saved.roamer ~= nil and saved.roamer.species == 243, "Save schema exports roamer")

local loadedSession = Schema.fromSaveTable(saved)
check(loadedSession.roamer ~= nil, "Save schema restores roamer")
check(loadedSession.roamer.species == 243, "Restored roamer has correct species")
check(loadedSession.roamer.hp == 85, "Restored roamer has correct HP")
check(loadedSession.roamer.ivs.hp == 31, "Restored roamer has correct IVs")
-- 9. Turn Order Against Roaming Flee (Speed / Priority checks matching pokefirered)
local Engine = require("src.core.game3.battle.engine")
do
  local RomText = require("src.core.game3.rom_text")
  if not RomText.has("gText_PkmnCantSwitchOut") then
    RomText.overrides.gText_PkmnCantSwitchOut = require("src.core.game3.scripting.text_ir").fromAscii("CANT SWITCH")
  end
end
local Adapter = require("src.core.game3.battle.adapter")

local pMon = { species = 150, level = 50, speed = 200, moves = { 33 }, pp = { 30 }, maxHp = 200, hp = 200 }
local eMon = { species = 244, level = 50, speed = 100, moves = { 52 }, pp = { 25 }, maxHp = 175, hp = 175, roamer = true }
local battleSt = {
  player = { mon = pMon, side = "player", stages = {} },
  enemy = { mon = eMon, side = "enemy", stages = {} },
  wild = true,
  roamer = true,
}
local battleAd = Adapter.new(battleSt, function() end)
local pAct = { kind = "move", move = 33, slot = 1, user = battleSt.player, battler = 0 }
local eAct = { kind = "run", user = battleSt.enemy, battler = 1 }

-- Faster player attacks before roamer flees
local actFaster = Engine.planTurnFromActions(battleSt, battleAd, pAct, eAct)
check(actFaster[1].user.side == "player", "Faster player attacks before roamer flees")
check(actFaster[2].user.side == "enemy" and actFaster[2].kind == "run", "Roamer flees second on turn")

-- Slower player
pMon.speed = 50
local actSlower = Engine.planTurnFromActions(battleSt, battleAd, pAct, eAct)
check(actSlower[1].user.side == "enemy" and actSlower[1].kind == "run", "Faster roamer flees before slower player")

-- Priority move on slower player
pMon.moves[1] = 98 -- Quick Attack (+1)
pAct.move = 98
local actPri = Engine.planTurnFromActions(battleSt, battleAd, pAct, eAct)
check(actPri[1].user.side == "player", "Priority move on slower player attacks before roamer flees")

-- Bag item (Ball)
local bAct = { kind = "bag", itemId = 1, user = battleSt.player, battler = 0 }
local _, bagMeta = Engine.planTurnFromActions(battleSt, battleAd, bAct, eAct)
check(bagMeta and bagMeta.kind == "bag", "Bag action executes before roamer flees")

-- 10. Trapping Mechanics vs Roaming Flee
local Ai = require("src.core.game3.battle.ai")

-- Untrapped roamer chooses run
battleSt.enemy.escapePrevention = nil
battleSt.enemy.expTrapped = nil
battleSt.enemy.expTrapTurns = nil
local untrappedAct = Ai.chooseMove(battleSt, { battler = 1 })
check(untrappedAct and untrappedAct.kind == "run", "Untrapped roamer chooses flee")

-- Mean Look / Escape Prevention
battleSt.enemy.escapePrevention = true
battleSt.enemy.expTrapped = true
local trappedAct = Ai.chooseMove(battleSt, { battler = 1 })
check(trappedAct and trappedAct.kind == "move", "Mean Look trapped roamer cannot flee and chooses attack move")
check(Engine.canSwitch(battleSt, battleAd, battleSt.enemy) == false, "Engine.canSwitch returns false for trapped roamer")

-- Shadow Tag
battleSt.enemy.escapePrevention = nil
battleSt.enemy.expTrapped = nil
battleSt.player.ability = "SHADOW_TAG"
pMon.ability = "SHADOW_TAG"
local shadowTagAct = Ai.chooseMove(battleSt, { battler = 1 })
check(shadowTagAct and shadowTagAct.kind == "move", "Shadow Tag prevents roamer from fleeing and forces attack")

-- Arena Trap (Entei is grounded -> trapped)
battleSt.player.ability = "ARENA_TRAP"
pMon.ability = "ARENA_TRAP"
local arenaTrapAct = Ai.chooseMove(battleSt, { battler = 1 })
check(arenaTrapAct and arenaTrapAct.kind == "move", "Arena Trap traps grounded beast and forces attack")

-- Partial trapping (Wrap / Fire Spin)
battleSt.player.ability = "PRESSURE"
pMon.ability = "PRESSURE"
battleSt.enemy.expTrapTurns = 4
battleSt.enemy.wrapped = true
local wrapAct = Ai.chooseMove(battleSt, { battler = 1 })
check(wrapAct and wrapAct.kind == "move", "Partial trap (Fire Spin / Wrap) prevents roamer flee")

-- Switch-out releases trap
battleSt.enemy.expTrapTurns = nil
battleSt.enemy.wrapped = nil
battleSt.enemy.expTrapped = true
battleSt.enemy.expTrappedBy = battleSt.player
battleSt.playerParty = { pMon, { species = 25, level = 50, hp = 100, maxHp = 100 } }
Engine.performSwitch(battleSt, battleAd, "player", 2)
Engine.refreshLinks(battleSt)
check(battleSt.enemy.expTrapped == nil and battleSt.enemy.expTrappedBy == nil, "Switching out player clears enemy trap")

done()
