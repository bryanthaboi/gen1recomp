#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then print("[skip] game3_trainer_party_item_test: " .. tostring(Cache.reason)) os.exit(0) end
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
local Pokemon = require("src.core.game3.pokemon")
local Trainers = require("src.core.game3.scripting.trainers")

local game = { data = {} }
Dataset.hydrate(game)
local session = { map = "FR_PALLET_TOWN", x = 12, y = 20, facing = "down", flags = {}, vars = {}, party = {}, name = "RED" }
game.session = session
Runtime.start(nil, game, session, { reason = "new_game" })
Party.giveMon(session, 150, 70)

local ORAN_BERRY, SITRUS_BERRY = 139, 142

local function finish()
  if Battle.isActive() then
    Battle.runToEnd()
    if Battle.isActive() then BattleBridge.finishPending("win") end
  end
end

local function heldBy(mon)
  return tonumber(mon and mon.item) or 0
end

local trainerId
for id = 1, 900 do
  local foe = Trainers.foeFromId(id)
  if foe and foe.party and #foe.party >= 2 and not foe.doubleBattle then trainerId = id break end
end
check(trainerId ~= nil, "found a single-battle trainer with two Pokemon")

print("[test] 1. a trainer row's heldItem reaches the battle")
do
  local foe = Trainers.foeFromId(trainerId)
  foe.heldItem = ORAN_BERRY
  foe.party[1].heldItem = ORAN_BERRY
  foe.party[2].heldItem = SITRUS_BERRY
  local ok = BattleBridge.start(nil, game, foe, { trainerId = trainerId, headless = true, autoFight = false, fade = false })
  check(ok, "trainer battle starts")
  local st = Battle.getState()
  check(heldBy(st and st.enemy and st.enemy.mon) == ORAN_BERRY, "the lead holds its row's item")
  check(heldBy(st and st.foeParty and st.foeParty[1]) == ORAN_BERRY, "party slot 1 holds its row's item")
  check(heldBy(st and st.foeParty and st.foeParty[2]) == SITRUS_BERRY, "party slot 2 holds its row's item")
  finish()
end

local wildItemSpecies
for sp = 1, 386 do
  local meta = Pokemon.speciesMeta(sp)
  if meta and (tonumber(meta.itemCommon) or 0) ~= 0 then wildItemSpecies = sp break end
end
check(wildItemSpecies ~= nil, "found a species with a common wild held item")

print("[test] 2. a trainer's Pokemon never takes the wild held-item roll")
do
  local rolled = 0
  for _ = 1, 40 do
    local foe = Trainers.foeFromId(trainerId)
    foe.species, foe.heldItem = wildItemSpecies, nil
    for _, row in ipairs(foe.party) do
      row.species, row.heldItem, row.moves = wildItemSpecies, nil, nil
    end
    foe.moves = nil
    BattleBridge.start(nil, game, foe, { trainerId = trainerId, headless = true, autoFight = false, fade = false })
    local st = Battle.getState()
    if heldBy(st and st.enemy and st.enemy.mon) ~= 0 then rolled = rolled + 1 end
    for _, mon in ipairs(st and st.foeParty or {}) do
      if heldBy(mon) ~= 0 then rolled = rolled + 1 end
    end
    finish()
  end
  check(rolled == 0, "no trainer Pokemon picked up a wild item in 40 battles (" .. rolled .. ")")
end

print("[test] 3. a wild Pokemon still takes the roll")
do
  local rolled = 0
  for _ = 1, 40 do
    BattleBridge.start(nil, game, { species = wildItemSpecies, level = 5 }, { wild = true, headless = true, autoFight = false, fade = false })
    local st = Battle.getState()
    if heldBy(st and st.enemy and st.enemy.mon) ~= 0 then rolled = rolled + 1 end
    finish()
  end
  check(rolled > 0, "a wild Pokemon held its species item at least once in 40 battles (" .. rolled .. ")")
end

if failed > 0 then
  print(("game3_trainer_party_item_test: %d failed"):format(failed))
  os.exit(1)
end
print("game3_trainer_party_item_test: ok")
