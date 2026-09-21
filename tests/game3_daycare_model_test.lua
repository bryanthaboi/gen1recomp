#!/usr/bin/env luajit
-- pokefirered/src/daycare.c:370

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

local function finish()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

package.loaded["src.core.game3.audio"] = setmetatable({}, {
  __index = function() return function() end end,
})

local store = { flags = {}, vars = {} }
local session = {
  store = store, map = "FR_ROUTE_5_POKEMON_DAY_CARE", party = {},
  name = "RED", trainerId = 4242, vars = {}, flags = {},
}
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  isActive = function() return true end,
}

local Daycare = require("src.core.game3.daycare")
local Natives = require("src.core.game3.scripting.natives")
local Std = require("src.core.game3.scripting.stdscripts")
local Flags = require("src.core.game3.scripting.flags")
local NativesDaycare = require("src.core.game3.scripting.natives_daycare")
local StepEvents = require("src.core.game3.step_events")

local VAR_0x8004 = 0x8004
local VAR_0x8005 = 0x8005

local function newCtx()
  return { specialVars = {}, stringVars = { [1] = "", [2] = "", [3] = "" } }
end

local function getVar(ctx, id) return tonumber(Flags.getVar(store, ctx, id)) or 0 end
local function setVar(ctx, id, v) Flags.setVar(store, ctx, id, v) end

print("[test] 1. the specials layer and the model are one source of truth")
eq(NativesDaycare.stateOf, Daycare.stateOf, "natives_daycare.stateOf is the model's")
eq(NativesDaycare.route5Of, Daycare.route5Of, "natives_daycare.route5Of is the model's")
eq(NativesDaycare.cost, Daycare.cost, "natives_daycare.cost is the model's")
eq(Daycare.DAYCARE_MON_COUNT, 2, "the Four Island day care holds two")

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("meta.json")
if not cacheRoot then
  print("[skip] game3_daycare_model_test needs species data: " .. tostring(Cache.reason))
  finish()
end
print("[info] FireRed cache at " .. cacheRoot)

local Pokemon = require("src.core.game3.pokemon")
Pokemon.install(nil)
local Experience = require("src.core.game3.battle.experience")
local SummaryData = require("src.core.game3.summary_data")
local Party = require("src.core.game3.party")

local function makeMon(species, level)
  local scratch = { party = {}, name = "RED", trainerId = 4242 }
  local ok, _, mon = Party.giveMon(scratch, species, level, "")
  check(ok, "built a level " .. level .. " species " .. species)
  return mon
end

local function stepsForLevels(mon, toLevel)
  local growth = Experience.growthRate(mon)
  return SummaryData.expForLevel(growth, toLevel)
    - SummaryData.expForLevel(growth, tonumber(mon.level) or 1)
end

local function walk(n)
  for _ = 1, n do StepEvents.onStepTaken(session, nil) end
end

local function deepCopy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local out = {}
  seen[value] = out
  for k, v in pairs(value) do out[deepCopy(k, seen)] = deepCopy(v, seen) end
  return out
end

print("[test] 2. the two day cares are separate records")
session.party = { makeMon(19, 5), makeMon(16, 5), makeMon(21, 5) }
session.modData = nil
session.daycare = nil
session.route5Daycare = nil
local ctx = newCtx()
setVar(ctx, VAR_0x8004, 0)
Natives.special(ctx, Std.SPECIAL.PutMonInRoute5Daycare, nil)
ctx = newCtx()
setVar(ctx, VAR_0x8004, 0)
Natives.special(ctx, Std.SPECIAL.StoreSelectedPokemonInDaycare, nil)
local r5 = Daycare.route5Of(session)
local dc = Daycare.stateOf(session)
eq(r5.mon and r5.mon.species, 19, "the Route 5 slot holds the RATTATA")
eq(Daycare.mon(dc, 1) and Daycare.mon(dc, 1).species, 16,
  "the Four Island slot 1 holds the PIDGEY")
eq(Daycare.count(dc), 1, "one mon in the Four Island day care")
eq(#session.party, 1, "the party kept only the third mon")
local _, state = Natives.special(newCtx(), Std.SPECIAL.GetDaycareState, nil)
eq(state, 2, "GetDaycareState is DAYCARE_ONE_MON")

print("[test] 3. every field step feeds both day cares one experience point")
local r5Before, dcBefore = r5.steps, dc.steps[1]
local partyExpBefore = session.party[1].exp
walk(40)
eq(r5.steps - r5Before, 40, "the Route 5 mon banked 40 steps")
eq(dc.steps[1] - dcBefore, 40, "the Four Island slot 1 banked 40 steps")
eq(dc.steps[2], 0, "the empty second slot banks nothing")
eq(dc.stepCounter, 40 % 256, "the shared step counter advanced with them")
eq(session.party[1].exp, partyExpBefore, "a mon in the party gains nothing from walking")

print("[test] 4. the level menu and the cost follow the banked steps")
local stored = r5.mon
local want = stepsForLevels(stored, 8)
walk(want - r5.steps)
eq(r5.steps, want, "walked exactly to the level 8 threshold")
eq(Daycare.levelAfterSteps(stored, r5.steps), 8, "GetLevelAfterDaycareSteps reads level 8")
ctx = newCtx()
local _, gained = Natives.special(ctx, Std.SPECIAL.GetNumLevelsGainedForRoute5DaycareMon, nil)
eq(gained, 3, "three levels gained")
eq(ctx.stringVars[2], "3", "STR_VAR_2 carries the level count")
ctx = newCtx()
Natives.special(ctx, Std.SPECIAL.GetCostToWithdrawRoute5DaycareMon, nil)
eq(getVar(ctx, VAR_0x8005), 400, "the cost is 100 + 100 * 3")
eq(Daycare.cost(stored, 0), 100, "no levels gained costs the flat 100")
eq(Daycare.cost(stored, stepsForLevels(stored, 6)), 200, "one level costs 200")

print("[test] 5. the stay survives a save and reload")
local Schema = require("src.core.game3.save_schema_firered")
local saved = deepCopy(Schema.toSaveTable(session))
local loaded = Schema.fromSaveTable(saved)
package.loaded["src.core.game3.runtime"].getSession = function() return loaded end
local prevSession = session
session = loaded
session.store = store
local loadedR5 = Daycare.route5Of(session)
local loadedDc = Daycare.stateOf(session)
eq(loadedR5.mon and loadedR5.mon.species, 19, "the Route 5 mon came back from the save")
eq(loadedR5.steps, want, "with its banked steps")
eq(loadedDc.steps[1], want, "and the Four Island slot kept its own count")
check(loadedR5.mon ~= prevSession.route5Daycare.mon, "the reload really rebuilt the record")
walk(10)
eq(Daycare.route5Of(session).steps, want + 10, "steps keep accruing after the reload")

print("[test] 6. taking the mon back applies the levels and the moves it learned")
local learnLevel, learnMove
for _, entry in ipairs(Pokemon.learnset(19)) do
  local lv = entry[1] or entry.level or 0
  if lv > 5 and lv <= 8 then
    learnLevel, learnMove = lv, tonumber(entry[2] or entry.move)
    break
  end
end
check(learnMove ~= nil, "RATTATA learns something between level 6 and 8")
ctx = newCtx()
local _, taken = Natives.special(ctx, Std.SPECIAL.TakePokemonFromRoute5Daycare, nil)
eq(taken, 19, "TakePokemonFromRoute5Daycare returns the species")
local back = session.party[#session.party]
eq(back.species, 19, "the mon is back in the party")
eq(back.level, 8, "three levels higher")
eq(back.hp, back.maxHp, "at full HP, as BoxMonToMon leaves it")
eq(Daycare.route5Of(session).mon, nil, "the Route 5 slot is empty again")
local knows = false
for _, mv in ipairs(back.moves or {}) do if mv == learnMove then knows = true end end
check(knows, "it knows the move it learned at level " .. tostring(learnLevel))

print("[test] 7. a full moveset drops the first move for the one learned away")
local crammed = makeMon(19, 5)
local pool = {}
for _, entry in ipairs(Pokemon.learnset(19)) do
  local mv = tonumber(entry[2] or entry.move)
  local dup = (mv == learnMove)
  for _, have in ipairs(pool) do if have == mv then dup = true end end
  if mv and mv > 0 and not dup and #pool < 4 then pool[#pool + 1] = mv end
end
eq(#pool, 4, "four distinct level-up moves to cram in")
crammed.moves = { pool[1], pool[2], pool[3], pool[4] }
crammed.pp = { 10, 10, 10, 10 }
crammed.maxPp = { 10, 10, 10, 10 }
session.party[#session.party + 1] = crammed
ctx = newCtx()
setVar(ctx, VAR_0x8004, #session.party - 1)
Natives.special(ctx, Std.SPECIAL.PutMonInRoute5Daycare, nil)
r5 = Daycare.route5Of(session)
eq(r5.mon, crammed, "the crammed mon went in")
walk(stepsForLevels(crammed, learnLevel))
ctx = newCtx()
Natives.special(ctx, Std.SPECIAL.TakePokemonFromRoute5Daycare, nil)
eq(crammed.level, learnLevel, "it came back at the level it learned the move")
eq(#crammed.moves, 4, "still four moves")
eq(crammed.moves[4], learnMove, "the new move landed in the last slot")
eq(crammed.moves[1], pool[2], "and the first move it knew was deleted")

print("[test] 8. the Four Island slots shift up when the first one leaves")
session.daycare = nil
session.modData[Daycare.SAVE_KEY].daycare = nil
dc = Daycare.stateOf(session)
local first, second = makeMon(19, 5), makeMon(16, 5)
session.party = { first, second }
for slot = 1, 2 do
  ctx = newCtx()
  setVar(ctx, VAR_0x8004, 0)
  Natives.special(ctx, Std.SPECIAL.StoreSelectedPokemonInDaycare, nil)
end
eq(Daycare.count(dc), 2, "both mons are boarded")
eq(#session.party, 0, "and the party is empty")
walk(30)
eq(dc.steps[1], 30, "slot 1 banked its steps")
eq(dc.steps[2], 30, "slot 2 banked its own")
local _, two = Natives.special(newCtx(), Std.SPECIAL.GetDaycareState, nil)
eq(two, 3, "GetDaycareState is DAYCARE_TWO_MONS")
ctx = newCtx()
setVar(ctx, VAR_0x8004, 0)
local _, outSpecies = Natives.special(ctx, Std.SPECIAL.TakePokemonFromDaycare, nil)
eq(outSpecies, 19, "TakePokemonFromDaycare returned the first mon")
eq(Daycare.mon(dc, 1), second, "ShiftDaycareSlots moved the second mon into slot 1")
eq(Daycare.mon(dc, 2), nil, "and emptied slot 2")
eq(dc.steps[1], 30, "the shifted mon kept its banked steps")
eq(dc.steps[2], 0, "slot 2's counter is cleared")

print("[test] 9. withdrawal never grows the party past six")
session.party = {}
for i = 1, 6 do session.party[i] = makeMon(21, 5) end
ctx = newCtx()
setVar(ctx, VAR_0x8004, 0)
Natives.special(ctx, Std.SPECIAL.TakePokemonFromDaycare, nil)
eq(#session.party, 6, "the party is still six mons")
eq(session.party[6], second, "pret's gPlayerParty[PARTY_SIZE - 1] write holds the mon")

print("[test] 10. ChooseSendDaycareMon picks the mon through the party seam")
local asked
local adapters = {
  chooseParty = function(opts, done)
    asked = opts
    done(2)
  end,
  setStringVar = function() end,
}
ctx = newCtx()
setVar(ctx, VAR_0x8004, 0)
Natives.special(ctx, Std.SPECIAL.ChooseSendDaycareMon, adapters)
-- pokefirered/src/party_menu.c:6318 InitPartyMenu(PARTY_MENU_TYPE_DAYCARE, ...)
eq(asked and asked.menuType, 6, "the party opened as PARTY_MENU_TYPE_DAYCARE")
eq(getVar(ctx, VAR_0x8004), 2, "VAR_0x8004 carries the slot the player chose")
adapters.chooseParty = function(opts, done)
  asked = opts
  done(nil)
end
ctx = newCtx()
setVar(ctx, VAR_0x8004, 0)
Natives.special(ctx, Std.SPECIAL.ChooseSendDaycareMon, adapters)
-- pokefirered/data/maps/FourIsland_PokemonDayCare/scripts.inc:25 goto_if_ge PARTY_SIZE
check(getVar(ctx, VAR_0x8004) >= 6, "backing out returns a slot the script reads as a cancel")

print("[test] 11. GetDaycareMonNicknames fills the three string vars")
session.daycare = nil
session.modData[Daycare.SAVE_KEY].daycare = nil
dc = Daycare.stateOf(session)
session.party = { makeMon(19, 5), makeMon(16, 5) }
for _ = 1, 2 do
  ctx = newCtx()
  setVar(ctx, VAR_0x8004, 0)
  Natives.special(ctx, Std.SPECIAL.StoreSelectedPokemonInDaycare, nil)
end
ctx = newCtx()
Natives.special(ctx, Std.SPECIAL.GetDaycareMonNicknames, nil)
eq(ctx.stringVars[1], Pokemon.name(19), "STR_VAR_1 is the first slot's nickname")
eq(ctx.stringVars[2], Pokemon.name(16), "STR_VAR_2 is the second slot's nickname")
eq(ctx.stringVars[3], "RED", "STR_VAR_3 is the first mon's OT name")

finish()
