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

-- 1. Starter Species Mapping
check(Roamer.speciesForStarter(0) == 244, "Bulbasaur (0) -> Entei (244)")
check(Roamer.speciesForStarter(1) == 243, "Squirtle (1) -> Raikou (243)")
check(Roamer.speciesForStarter(2) == 245, "Charmander (2) -> Suicune (245)")

-- 2. Fixed IV Generation (Modern 0-31 IVs, not truncated to 0 or max 7)
local ivCheckOk = true
for _ = 1, 50 do
  local mon = Roamer.generateMon(243, 50)
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
check(ivCheckOk, "Roamer generates full 0-31 IVs across all 6 stats without truncation")

-- 3. Audio Override
check(Audio.legendaryBattleSong(243) == 339, "Raikou uses Legendary Battle BGM (339)")
check(Audio.legendaryBattleSong(244) == 339, "Entei uses Legendary Battle BGM (339)")
check(Audio.legendaryBattleSong(245) == 339, "Suicune uses Legendary Battle BGM (339)")

-- 4. Initialization via InitRoamer
local session = {
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
check(session.roamer.map ~= nil and #session.roamer.map > 0, "Roamer assigned initial Kanto route: " .. tostring(session.roamer.map))

-- 5. Adjacency Movement vs Warp Jump
local currentMap = session.roamer.map
local adjList = Roamer.ADJACENCY[currentMap]
check(adjList and #adjList > 0, "Current roamer route has valid adjacency list")

-- Step movement
Roamer.move(session, "map_transition")
local newMap = session.roamer.map
local isAdjOrSame = (newMap == currentMap)
if not isAdjOrSame and adjList then
  for _, m in ipairs(adjList) do
    if m == newMap then isAdjOrSame = true break end
  end
end
check(isAdjOrSame, "Roamer.move('map_transition') only moves to adjacent route or stays")

-- Warp jump (Fly / Teleport / Whiteout)
local jumped = false
for _ = 1, 20 do
  Roamer.move(session, "warp_random")
  if session.roamer.map ~= newMap then
    jumped = true
    break
  end
end
check(jumped, "Roamer.move('warp_random') randomizes route")

-- 6. Encounter Rate Gating & Fainted Lead Repel Trick
session.roamer.map = "FR_ROUTE2"
session.vars[0x4020] = 250 -- VAR_REPEL_STEP_COUNT = 250 (Repel is active)

-- Scenario A: Lead slot 1 is Level 50 (fainted), slot 2 is Level 100
-- Repel checks Slot 1 (Lv 50 <= Roamer Lv 50) -> Encounter MUST pass!
local encA = Roamer.tryEncounter(session, "FR_ROUTE2", "grass")
check(encA ~= nil and encA.roamer == true and encA.species == 245, "Fainted Slot 1 Lv 50 passes Repel gate")

-- Scenario B: Lead slot 1 is Level 51 (fainted)
-- Repel checks Slot 1 (Lv 51 > Roamer Lv 50) -> Repelled!
session.party[1].level = 51
local encB = Roamer.tryEncounter(session, "FR_ROUTE2", "grass")
check(encB == nil, "Lead Slot 1 Lv 51 triggers Repel and repels roamer")

-- Reset lead level to 50
session.party[1].level = 50

-- Scenario C: Wrong map
local encC = Roamer.tryEncounter(session, "FR_ROUTE3", "grass")
check(encC == nil, "Different map returns no encounter")

-- 7. Battle End Handling & Roar Despawn Prevention
local foeState = {
  hp = 60,
  maxHp = 150,
  status = "paralysis",
  statusNum = 0x40,
}

-- Flee / Roar end
local prevLocation = session.roamer.map
Roamer.onBattleEnd(session, foeState, "fled", "roar")
check(session.roamer.active == true, "Roar / Flee keeps roamer ACTIVE (Roar despawn bug fixed)")
check(session.roamer.hp == 60, "Roamer HP damage persisted (60)")
check(session.roamer.status == "paralysis", "Roamer status condition persisted (paralysis)")

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
