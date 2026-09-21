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

local Space = require("src.core.game3.scripting.space")
local Natives = require("src.core.game3.scripting.natives")
local BattleBridge = require("src.core.game3.battle_bridge")
local Battle = require("src.core.game3.battle")

local B_OUTCOME = Natives.B_OUTCOME

-- pokefirered/include/constants/flags.h:1334
local FLAG_SYS_SPECIAL_WILD_BATTLE = 0x807
-- pokefirered/include/constants/flags.h:109
local FLAG_HIDE_ZAPDOS = 0x05D
-- pokefirered/include/constants/flags.h:149
local FLAG_HIDE_POWER_PLANT_ELECTRODE_1 = 0x085
-- pokefirered/include/constants/flags.h:730
local FLAG_FOUGHT_ZAPDOS = 0x2BF
-- pokefirered/include/constants/flags.h:747
local FLAG_FOUGHT_POWER_PLANT_ELECTRODE_1 = 0x2D0
local VAR_LAST_TALKED = 0x800F

local POWER_PLANT = "FR_POWER_PLANT"
local LOCAL_ZAPDOS, LOCAL_ELECTRODE_2, LOCAL_ELECTRODE_1 = 6, 7, 8
local LOCAL_ROUTE_12_FISHER = 1

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] game3_static_encounter_test: " .. tostring(Cache.reason))
  done()
end
print("[info] FireRed cache at " .. cacheRoot)

local ExtractScripts = require("src.import.gba.extract_scripts")
Space.bundle = ExtractScripts.loadBundle(Cache.cache(), cacheRoot, { allowIncomplete = true })

local Dataset = require("src.core.game3.dataset")
local Runtime = require("src.core.game3.runtime")
local Map = require("src.core.game3.map")
local Objects = require("src.core.game3.objects")
local Party = require("src.core.game3.party")
local Flags = require("src.core.game3.scripting.flags")

local game = { data = {} }
Dataset.hydrate(game)
local session = { map = "FR_PALLET_TOWN", x = 12, y = 20, facing = "down",
  flags = {}, vars = {}, party = {} }
game.session = session
Runtime.start(nil, game, session, { reason = "new_game" })
Party.giveMon(session, 150, 100)

local function drain(n)
  for _ = 1, (n or 4000) do
    if not Space.vm:isRunning() then break end
    Space.vm:tick()
  end
end

local function goTo(mapId, x, y, facing)
  Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "up" })
  drain(512)
end

local function runOnResume(mapId)
  if type(Space.runOnResume) ~= "function" then return false end
  return Space.runOnResume(mapId)
end

local function flag(id) return Flags.getFlag(Space.store, Space.vm.ctx, id) and true or false end
local function setFlag(id, on) Flags.setFlag(Space.store, Space.vm.ctx, id, on ~= false) end
local function visible(localId)
  local eo = Objects.find(localId)
  return eo ~= nil and eo.visible == true
end

local function fightStatic(localId, result)
  local eo = Objects.find(localId)
  if not eo then return false end
  Space.vm:startTalk(eo.def.scriptKey, localId, 2)
  drain(4000)
  if not Space.vm:isRunning() then return false end
  if BattleBridge._finish == nil
    and not (Battle.isActive and Battle.isActive()) then
    return false
  end
  BattleBridge.finishPending(result)
  drain(4000)
  return true
end

print("[test] 1. the battle return hook records the outcome for GetBattleOutcome")
check(session.battleOutcome == nil, "a fresh session carries no battle outcome")
local ok = BattleBridge.start(nil, game, { species = 100, level = 34 },
  { wild = true, headless = true, fade = false })
check(ok == true, "a headless wild battle starts")
if Battle.isActive and Battle.isActive() then BattleBridge.finishPending("win") end
check(session.battleOutcome == B_OUTCOME.WON,
  "the finished battle left B_OUTCOME_WON on the session, got "
  .. tostring(session.battleOutcome))
local outcomeVm = Space.vm
check(outcomeVm ~= nil, "the field script VM is up")

print("[test] 2. a lost static battle leaves no FLAG_SYS_SPECIAL_WILD_BATTLE behind")
goTo(POWER_PLANT, 30, 39, "up")
check(visible(LOCAL_ELECTRODE_2), "Electrode 2 spawns on a fresh Power Plant")
check(fightStatic(LOCAL_ELECTRODE_2, "lose") == true,
  "the real Electrode script parked on the battle")
check(session.battleOutcome == B_OUTCOME.LOST,
  "the loss left B_OUTCOME_LOST on the session, got " .. tostring(session.battleOutcome))
check(flag(FLAG_SYS_SPECIAL_WILD_BATTLE) == false,
  "the respawn map load cleared it (pokefirered ClearTempFieldEventData, src/event_data.c:56), got "
  .. tostring(flag(FLAG_SYS_SPECIAL_WILD_BATTLE)))

print("[test] 3. an ordinary Route 12 trainer survives the battle return")
goTo("FR_ROUTE_12", 14, 60, "up")
check(flag(FLAG_SYS_SPECIAL_WILD_BATTLE) == false,
  "the flag is still clear on Route 12, whose ON_RESUME removes VAR_LAST_TALKED behind it")
local Message = require("src.ui.game3.message")
local fisher = Objects.find(LOCAL_ROUTE_12_FISHER)
check(fisher ~= nil and fisher.visible == true and fisher.def.trainerType == 1,
  "the Route 12 Fisher (localId 1) is on the map")
Space.vm:startTalk(fisher.def.scriptKey, LOCAL_ROUTE_12_FISHER, 2)
for _ = 1, 600 do
  if BattleBridge._finish then break end
  if Message.isOpen() then
    Message.skipReveal()
    Message.tick()
    Message.advance()
  end
  Message.tick()
  Space.vm:tick()
end
check(Space.vm:isRunning() and BattleBridge._finish ~= nil,
  "his real trainerbattle script parked on the battle")
BattleBridge.finishPending("win")
drain(4000)
check(visible(LOCAL_ROUTE_12_FISHER),
  "the Fisher is still standing after an ordinary trainer battle")

print("[test] 4. a caught Electrode is removed by the Power Plant ON_RESUME")
goTo(POWER_PLANT, 30, 39, "up")
check(visible(LOCAL_ELECTRODE_1), "Electrode 1 spawns on a fresh Power Plant")
check(flag(FLAG_HIDE_POWER_PLANT_ELECTRODE_1) == false,
  "ON_TRANSITION cleared its hide flag")
check(fightStatic(LOCAL_ELECTRODE_1, "catch") == true,
  "the real Electrode script parked on the battle")
check(session.battleOutcome == B_OUTCOME.CAUGHT,
  "the catch left B_OUTCOME_CAUGHT on the session, got "
  .. tostring(session.battleOutcome))
check(visible(LOCAL_ELECTRODE_1) == false, "the caught Electrode is off the map")
check(flag(FLAG_HIDE_POWER_PLANT_ELECTRODE_1) == true,
  "removeobject set its hide flag (pokefirered RemoveObjectEventByLocalIdAndMap)")
check(flag(FLAG_FOUGHT_POWER_PLANT_ELECTRODE_1) == true,
  "the script ran on past the catch and set FLAG_FOUGHT_POWER_PLANT_ELECTRODE_1")
check(flag(FLAG_SYS_SPECIAL_WILD_BATTLE) == false,
  "the script cleared FLAG_SYS_SPECIAL_WILD_BATTLE after the battle")

print("[test] 5. it stays gone after leaving and re-entering the map")
goTo("FR_ROUTE_10", 10, 10, "down")
goTo(POWER_PLANT, 30, 39, "up")
check(visible(LOCAL_ELECTRODE_1) == false,
  "ON_TRANSITION does not re-show a fought Electrode")
check(visible(LOCAL_ZAPDOS), "and Zapdos, untouched, is still there")

print("[test] 6. ON_RESUME is inert once the script cleared the special-battle flag")
check(session.battleOutcome == B_OUTCOME.CAUGHT, "the outcome is still CAUGHT")
Flags.setVar(Space.store, Space.vm.ctx, VAR_LAST_TALKED, LOCAL_ZAPDOS)
check(runOnResume(POWER_PLANT) == true, "ON_RESUME ran")
check(visible(LOCAL_ZAPDOS),
  "call_if_set FLAG_SYS_SPECIAL_WILD_BATTLE did not fire, so Zapdos stands")

print("[test] 7. a fled battle leaves the ON_RESUME branch alone")
check(fightStatic(LOCAL_ELECTRODE_2, "run") == true,
  "the second Electrode script parked on the battle")
check(session.battleOutcome == B_OUTCOME.RAN,
  "the flee left B_OUTCOME_RAN on the session, got " .. tostring(session.battleOutcome))
setFlag(FLAG_SYS_SPECIAL_WILD_BATTLE, true)
Flags.setVar(Space.store, Space.vm.ctx, VAR_LAST_TALKED, LOCAL_ZAPDOS)
check(runOnResume(POWER_PLANT) == true, "ON_RESUME ran with the flag set")
check(visible(LOCAL_ZAPDOS),
  "goto_if_ne VAR_RESULT, B_OUTCOME_CAUGHT skipped the removeobject, Zapdos stands")
check(flag(FLAG_HIDE_ZAPDOS) == false, "and his hide flag is untouched")
check(flag(FLAG_FOUGHT_ZAPDOS) == false, "nothing marked Zapdos as fought")

print("[test] 8. the decoded ON_RESUME is pret's shape and every op is reachable")
local ms = Space.bundle.events[POWER_PLANT].mapScripts
local rows = Space.bundle.scripts[ms.onResume]
check(type(rows) == "table" and rows[1] and rows[1].op == "checkflag"
  and rows[1][1] == FLAG_SYS_SPECIAL_WILD_BATTLE,
  "ON_RESUME opens on checkflag FLAG_SYS_SPECIAL_WILD_BATTLE")
local branch = nil
for _, row in ipairs(rows) do
  if row.op == "call_if" and row.cond == 1 then branch = row.target end
end
local body = branch and Space.bundle.scripts[branch]
check(type(body) == "table", "call_if TRUE points at a decoded body")
local sawSpecialVar, sawCompare, sawGotoIfNe, sawRemove = false, false, false, false
for _, row in ipairs(body or {}) do
  if row.op == "specialvar" and row[2] == 180 then sawSpecialVar = true end
  if row.op == "compare_var_to_value" and row.value == B_OUTCOME.CAUGHT then
    sawCompare = true
  end
  -- pokefirered/src/script.c:246 goto_if cond 5 = NE
  if row.op == "goto_if" and row.cond == 5 then sawGotoIfNe = true end
  if row.op == "removeobject" and row.localId == VAR_LAST_TALKED then sawRemove = true end
end
check(sawSpecialVar, "specialvar VAR_RESULT, GetBattleOutcome (special 180)")
check(sawCompare, "compared against B_OUTCOME_CAUGHT (7)")
check(sawGotoIfNe, "goto_if_ne jumps away when it is not a catch")
check(sawRemove, "removeobject VAR_LAST_TALKED")
check(Natives.ALLOW["special:180"] ~= nil,
  "special 180 has a handler, so the specialvar is not skipped")

done()
