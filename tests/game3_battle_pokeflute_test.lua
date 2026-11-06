#!/usr/bin/env luajit
-- pokefirered/data/battle_scripts_2.s:192

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cart_cache").mountOrSkip("game3_battle_pokeflute_test")
require("tests.fixture_data.game3_items").install()

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local Bag = require("src.core.game3.bag")
local BattleItems = require("src.core.game3.battle.items")
local BattleText = require("src.core.game3.battle.battle_text")
local Pokemon = require("src.core.game3.pokemon")
local State = require("src.core.game3.battle.state")
local Adapter = require("src.core.game3.battle.adapter")

Pokemon.install(nil)

local POKE_FLUTE = 350

local function setup(playerMons, foeMons)
  local bag = Bag.new()
  Bag.add(bag, POKE_FLUTE, 1)
  local session = { name = "RED", bag = bag, party = playerMons, dex = { seen = {}, owned = {} } }
  local st = {
    wild = true,
    turn = 2,
    player = State.makeBattler(playerMons[1], "player", { partyIndex = 1 }),
    enemy = State.makeBattler(foeMons[1], "enemy", { partyIndex = 1 }),
    playerParty = playerMons,
    foeParty = foeMons,
  }
  st.player.status = playerMons[1].status
  st.enemy.status = foeMons[1].status
  local said = {}
  local ad = Adapter.new(st, function(t) said[#said + 1] = t end)
  return st, ad, bag, session, said
end

local function mon(species, status, sleep)
  return { species = species, level = 30, hp = 50, maxHp = 50, moves = { 33 }, pp = { 35 },
    status = status, sleep = sleep }
end

print("[test] 1. sleeping wild foe and sleeping bench mon wake")
local player = { mon(9, nil), mon(25, "SLP", 3), mon(4, "PSN") }
local foe = { mon(143, "SLP", 4) }
local st, ad, bag, session, said = setup(player, foe)
st.enemy.sleepTurns = 4
local r, msgs, endsTurn, endsBattle, detail = BattleItems.use(st, ad, bag, session, POKE_FLUTE, nil)
check(r == "flute", "result is flute (got " .. tostring(r) .. ")")
check(endsTurn == true and endsBattle == false, "flute uses the turn and does not end the battle")
check(detail and detail.woke == true, "chooser reports a wake")
check(st.enemy.status == nil and foe[1].status == nil, "sleeping foe woke")
check(st.enemy.sleepTurns == nil, "foe sleep counter cleared")
check(player[2].status == nil and (tonumber(player[2].sleep) or 0) == 0, "sleeping bench mon woke")
check(player[3].status == "PSN", "non-sleep status untouched")
check(Bag.get(bag, POKE_FLUTE) == 1, "POKE FLUTE not consumed")
local fill = Adapter.fill(st, { lastItem = POKE_FLUTE, playerName = "RED" })
check(msgs[1] == BattleText.get("STRINGID_POKEFLUTE", fill), "first line is STRINGID_POKEFLUTE")
check(msgs[2] == BattleText.get("STRINGID_MONHEARINGFLUTEAWOKE", fill), "second line is STRINGID_MONHEARINGFLUTEAWOKE")
check(#said == 0, "texts are left to the battle presenter")
local ids = {}
for _, id in ipairs(detail and detail.battlers or {}) do ids[id] = true end
check(ids[0] and ids[1], "status icons refresh for both battlers")

print("[test] 2. nobody asleep plays the catchy tune")
st, ad, bag, session = setup({ mon(9, nil) }, { mon(143, "PAR") })
r, msgs, endsTurn, _, detail = BattleItems.use(st, ad, bag, session, POKE_FLUTE, nil)
fill = Adapter.fill(st, { lastItem = POKE_FLUTE, playerName = "RED" })
check(r == "flute" and endsTurn == true, "flute still uses the turn")
check(detail and detail.woke == false, "chooser reports no wake")
check(#msgs == 1 and msgs[1] == BattleText.get("STRINGID_POKEFLUTECATCHY", fill), "line is STRINGID_POKEFLUTECATCHY")
check(st.enemy.status == "PAR", "paralysis untouched")

print("[test] 3. Soundproof sleeper stays asleep")
local mime = mon(122, "SLP", 3)
st, ad, bag, session = setup({ mon(9, nil) }, { mime })
st.enemy.ability = "SOUNDPROOF"
r, msgs, _, _, detail = BattleItems.use(st, ad, bag, session, POKE_FLUTE, nil)
check(st.enemy.status == "SLP" and mime.status == "SLP", "Soundproof foe still asleep")
check(detail and detail.woke == false, "Soundproof sleeper does not count as woken")

print("[test] 4. sleeping bench mon in a trainer party wakes")
local trainerParty = { mon(143, nil), mon(143, "SLP", 2) }
st, ad, bag, session = setup({ mon(9, nil) }, trainerParty)
st.wild = false
r, msgs, _, _, detail = BattleItems.use(st, ad, bag, session, POKE_FLUTE, nil)
check(detail and detail.woke == true and trainerParty[2].status == nil, "foe bench sleeper woke")

print("[test] 5. doubles: all four battlers wake, Soundproof bench mon stays asleep")
local dPlayer = { mon(9, "SLP", 2), mon(25, "SLP", 3), mon(122, "SLP", 4) }
local dFoe = { mon(143, "SLP", 2), mon(19, "SLP", 3) }
local dBag = Bag.new()
Bag.add(dBag, POKE_FLUTE, 1)
local dSession = { name = "RED", bag = dBag, party = dPlayer, dex = { seen = {}, owned = {} } }
local dSt = {
  wild = false,
  double = true,
  turn = 2,
  playerParty = dPlayer,
  foeParty = dFoe,
  battlers = {
    [0] = State.makeBattler(dPlayer[1], "player", { id = 0, partyIndex = 1 }),
    [1] = State.makeBattler(dFoe[1], "enemy", { id = 1, partyIndex = 1 }),
    [2] = State.makeBattler(dPlayer[2], "player", { id = 2, partyIndex = 2 }),
    [3] = State.makeBattler(dFoe[2], "enemy", { id = 3, partyIndex = 2 }),
  },
}
dSt.player, dSt.enemy = dSt.battlers[0], dSt.battlers[1]
for id = 0, 3 do
  dSt.battlers[id].status = "SLP"
  dSt.battlers[id].sleepTurns = 2
end
local dAd = Adapter.new(dSt, function() end)
r, msgs, endsTurn, _, detail = BattleItems.use(dSt, dAd, dBag, dSession, POKE_FLUTE, nil)
check(r == "flute" and endsTurn == true, "doubles flute uses the turn")
check(detail and detail.woke == true, "doubles chooser reports a wake")
for id = 0, 3 do
  local b = dSt.battlers[id]
  check(b.status == nil and b.sleepTurns == nil and b.mon.status == nil, "doubles battler " .. id .. " woke")
end
check(dPlayer[3].status == "SLP", "Soundproof bench MR. MIME stays asleep")
local dIds = {}
for _, id in ipairs(detail and detail.battlers or {}) do dIds[id] = true end
check(dIds[0] and dIds[1] and dIds[2] and dIds[3], "status icons refresh for all four battlers")

if failed > 0 then
  print(("%d POKE FLUTE check(s) failed"):format(failed))
  os.exit(1)
end
print("All battle POKE FLUTE tests passed.")
