#!/usr/bin/env luajit
-- A trainer party row's heldItem and nickname reach the battle mon (#3133, #3134).
--   luajit tests/game3_trainer_party_row_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then print("[skip] game3_trainer_party_row_test: " .. tostring(Cache.reason)) os.exit(0) end
local Space = require("src.core.game3.scripting.space")
local ExtractScripts = require("src.import.gba.extract_scripts")
Space.bundle = ExtractScripts.loadBundle(Cache.cache(), cacheRoot, { allowIncomplete = true })

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local BattleBridge = require("src.core.game3.battle_bridge")
local Battle = require("src.core.game3.battle")
local Dataset = require("src.core.game3.dataset")
local Runtime = require("src.core.game3.runtime")
local Party = require("src.core.game3.party")
local Trainers = require("src.core.game3.scripting.trainers")
local Pokemon = require("src.core.game3.pokemon")
local Ui = require("src.core.game3.battle.ui")
local ModRuntime = require("src.mods.Runtime")
local hooks = require("src.mods.Hooks").new()
ModRuntime.install(require("src.mods.Events").new(), hooks)

local game = { data = {} }
Dataset.hydrate(game)
local session = { map = "FR_PALLET_TOWN", x = 12, y = 20, facing = "down", flags = {}, vars = {}, party = {}, name = "RED" }
game.session = session
Runtime.start(nil, game, session, { reason = "new_game" })
Party.giveMon(session, 6, 100)

-- the first cart trainer whose lead holds an item, and the first single-battle
-- trainer with two itemless mons whose species carry a wild held item
local function wildItem(species)
  local meta = Pokemon.speciesMeta and Pokemon.speciesMeta(species)
  return meta and ((tonumber(meta.itemCommon) or 0) ~= 0 or (tonumber(meta.itemRare) or 0) ~= 0)
end
local heldId, plainId
for id = 1, 742 do
  local t = Trainers.get(id)
  local lead = t and t.party and t.party[1]
  if lead then
    if (tonumber(lead.heldItem) or 0) > 0 and not heldId then heldId = id end
    if not plainId and #t.party >= 2 and not t.doubleBattle then
      local fits = true
      for _, m in ipairs(t.party) do
        if (tonumber(m.heldItem) or 0) ~= 0 or not wildItem(tonumber(m.species)) then fits = false end
      end
      if fits then plainId = id end
    end
  end
  if heldId and plainId then break end
end
check(heldId ~= nil, "the cart has a trainer whose lead holds an item")
check(plainId ~= nil, "the cart has an itemless trainer whose species carry wild items")

local function start(trainerId)
  Battle.reset()
  local foe = Trainers.foeFromId(trainerId)
  local ok = BattleBridge.start(nil, game, foe, { trainerId = trainerId, headless = true, fade = false })
  return ok, Battle.getState(), foe
end

print("[test] 1. a trainer mon holds its row's item")
if heldId then
  local ok, st, foe = start(heldId)
  check(ok, "trainer " .. heldId .. " battle starts")
  local want = tonumber(foe.party[1].heldItem)
  check(st and st.foeParty and tonumber(st.foeParty[1].item) == want,
    "the lead's item is the row's heldItem (" .. tostring(want) .. ")")
  check(st and st.enemy and tonumber(st.enemy.item or (st.enemy.mon and st.enemy.mon.item)) == want,
    "the active foe battler holds it")
end

print("[test] 2. a trainer mon with no held item never rolls a wild one")
if plainId then
  for round = 1, 40 do
    local ok, st = start(plainId)
    local clean = ok and st and st.foeParty
    for _, mon in ipairs(clean and st.foeParty or {}) do
      if (tonumber(mon.item) or 0) ~= 0 then clean = false end
    end
    if not clean then
      check(false, "round " .. round .. ": an itemless trainer row stays itemless")
      break
    end
    if round == 40 then check(true, "40 starts: an itemless trainer row stays itemless") end
  end
end

print("[test] 3. a trainer.party row's nickname names every slot, the lead included")
if plainId then
  local ok, st = start(plainId)
  local species = st and st.foeParty and st.foeParty[1].species
  check(ok and st.foeParty[1].nickname == nil and st.enemy.mon.nickname == nil,
    "with no hook the lead has no nickname")
  local unsub = hooks:wrap("trainer.party", function(nextFn, class, index, party)
    local out = {}
    for i, row in ipairs(nextFn(class, index, party)) do
      local copy = {}
      for k, v in pairs(row) do copy[k] = v end
      copy.nickname = "ROWNICK" .. i
      out[i] = copy
    end
    return out
  end)
  ok, st = start(plainId)
  unsub()
  check(ok, "hooked trainer battle starts")
  check(st.foeParty[1].nickname == "ROWNICK1" and st.foeParty[2].nickname == "ROWNICK2",
    "every party slot carries its row's nickname")
  -- the lead is built from the foe's own lead fields, not from party[1]
  local said = false
  for _, line in ipairs(Ui.log and Ui.log() or {}) do
    if type(line) == "string" and line:find("ROWNICK1", 1, true) then said = true end
  end
  check(said, "the send-out line names the lead by its row nickname")
  check(st.enemy.mon.species == species and Pokemon.name(species) ~= "ROWNICK1",
    "the species is unchanged")
end

print("[test] 4. a row a hook adds from scratch is a trainer's mon too")
if plainId then
  local species = Trainers.get(plainId).party[1].species
  local unsub = hooks:wrap("trainer.party", function(nextFn, class, index, party)
    local out = {}
    for i, row in ipairs(nextFn(class, index, party)) do out[i] = row end
    out[#out + 1] = { species = out[1].species, level = 5 }
    return out
  end)
  local clean, size = true, 0
  for _ = 1, 40 do
    local ok, st = start(plainId)
    size = ok and st and st.foeParty and #st.foeParty or 0
    for _, mon in ipairs(size > 0 and st.foeParty or {}) do
      if (tonumber(mon.item) or 0) ~= 0 then clean = false end
    end
    if size == 0 then clean = false end
  end
  unsub()
  check(size == #Trainers.get(plainId).party + 1, "the added row joins the party")
  check(clean and wildItem(tonumber(species)), "40 starts: it never rolls a wild held item")
end

Battle.reset()
os.exit(failed > 0 and 1 or 0)
