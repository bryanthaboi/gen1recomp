#!/usr/bin/env luajit
-- Game3 battle bag: catch odds, medicine, X items, doll.

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

local Bag = require("src.core.game3.bag")
local ItemsData = require("src.core.game3.items_data")
local BattleItems = require("src.core.game3.battle.items")
local Pokemon = require("src.core.game3.pokemon")
local Battle = require("src.core.game3.battle")
local State = require("src.core.game3.battle.state")
local Adapter = require("src.core.game3.battle.adapter")

ItemsData.install(nil)
Pokemon.install(nil)

print("[test] 1. Catch odds / Master Ball")
local foe = State.makeBattler({
  species = 16, level = 5, hp = 20, maxHp = 20,
  moves = { 33 }, pp = { 35 },
}, "enemy")
local odds = BattleItems.catchOdds(4, foe, { turn = 1 })
check(odds > 0, "POKE BALL odds > 0 (" .. tostring(odds) .. ")")
local lowHp = State.makeBattler({
  species = 16, level = 5, hp = 1, maxHp = 20,
  moves = { 33 }, pp = { 35 },
}, "enemy")
local oddsLow = BattleItems.catchOdds(4, lowHp, { turn = 1 })
check(oddsLow > odds, "lower HP raises catch odds")
local caught, shakes = BattleItems.tryCatch(1, foe, { turn = 1 }, function() return 0 end)
check(caught == true and shakes == 4, "MASTER BALL always catches")

print("[test] 2. Battle medicine / X item / doll")
local bag = Bag.new()
Bag.add(bag, 13, 2)
Bag.add(bag, 75, 1)
Bag.add(bag, 80, 1)
Bag.add(bag, 4, 5)

local session = {
  name = "RED",
  bag = bag,
  party = {
    { species = 1, name = "BULBASAUR", hp = 5, maxHp = 20, moves = { 33 }, pp = { 35 } },
  },
  dex = { seen = {}, owned = {} },
}
local player = State.makeBattler(session.party[1], "player", { partyIndex = 1 })
local st = {
  wild = true,
  turn = 3,
  player = player,
  enemy = foe,
  playerParty = session.party,
}
local msgs = {}
local ad = Adapter.new(st, function(t) msgs[#msgs + 1] = t end)

local r1 = BattleItems.use(st, ad, bag, session, 13, 1)
check(r1 == "heal", "POTION heals in battle")
check(session.party[1].hp > 5, "HP restored")
check(Bag.get(bag, 13) == 1, "POTION consumed")

local r2 = BattleItems.use(st, ad, bag, session, 75, nil)
check(r2 == "xitem", "X ATTACK used")
check((player.stages.attack or 0) >= 1, "attack stage rose")

local r3 = BattleItems.use(st, ad, bag, session, 80, nil)
check(r3 == "doll", "POKE DOLL flees wild")

print("[test] 3. Catch stores mon")
bag = Bag.new()
Bag.add(bag, 1, 1) -- Master Ball
session = {
  name = "RED",
  bag = bag,
  party = {
    { species = 1, name = "BULBASAUR", hp = 20, maxHp = 20, moves = { 33 }, pp = { 35 } },
  },
  dex = { seen = {}, owned = {} },
}
st = {
  wild = true,
  turn = 1,
  player = State.makeBattler(session.party[1], "player", { partyIndex = 1 }),
  enemy = State.makeBattler({
    species = 19, level = 3, hp = 10, maxHp = 15, moves = { 33 }, pp = { 35 },
  }, "enemy"),
  playerParty = session.party,
}
ad = Adapter.new(st, function() end)
local rc = BattleItems.use(st, ad, bag, session, 1, nil)
check(rc == "catch", "Master Ball catch result")
check(#session.party == 2, "caught mon added to party")
check(session.dex.owned[19] == true, "dex owned RATTATA")
check(Bag.get(bag, 1) == 0, "Master Ball consumed")

print("[test] 4. Trainer blocks balls")
st.wild = false
Bag.add(bag, 4, 1)
local rt = BattleItems.use(st, ad, bag, session, 4, nil)
check(rt == "error", "ball blocked in trainer battle")
check(Bag.get(bag, 4) == 1, "ball not consumed when blocked")

print("[test] 5. Meta bag catch ends battle")
local Runtime = {
  _session = {
    name = "RED",
    bag = Bag.new(),
    party = {
      { species = 1, level = 5, hp = 20, maxHp = 20, moves = { 33, 45 }, pp = { 35, 40 } },
    },
    dex = { seen = {}, owned = {} },
  },
}
function Runtime.getSession() return Runtime._session end
package.loaded["src.core.game3.runtime"] = Runtime
Bag.add(Runtime._session.bag, 1, 1)

if Battle.isActive() then
  -- force clean
  Battle._active = false
end
local Ui = require("src.core.game3.battle.ui")
local started = Battle.start({
  wild = true,
  playerParty = Runtime._session.party,
  foe = { species = 16, level = 2, hp = 5, maxHp = 15, moves = { 33 }, pp = { 35 } },
  onDone = function(r) Runtime._lastResult = r end,
})
check(started == true, "battle started (interactive)")
Ui._headless = true
Ui._queue = {}
Ui._showing = false
Battle._phase = "actions"
Battle._actions = {}
Battle._actionI = 1
Battle._metaAct = { kind = "bag", itemId = 1, user = "player" }
Battle.update(0, nil)
check(Battle._pendingEnd == "catch" or Battle.getResult() == "catch"
    or #Runtime._session.party >= 2,
  "catch meta sets catch / stores mon (pending="
    .. tostring(Battle._pendingEnd) .. " party=" .. tostring(#Runtime._session.party) .. ")")
for _ = 1, 20 do
  if not Battle.isActive() then break end
  Battle._phase = Battle._phase == "ending" and "ending" or "ending"
  Ui._queue = {}
  Battle.update(0, nil)
end
check(Runtime._lastResult == "catch" or #Runtime._session.party >= 2,
  "onDone catch or mon stored")

if failed > 0 then
  print(string.format("\n%d FAILED", failed))
  os.exit(1)
end
print("\nAll battle-bag tests passed.")
os.exit(0)
