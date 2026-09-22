#!/usr/bin/env luajit
-- Game3: in-battle item use must read the LIVE battle party, not the stale
-- session.party snapshot.
--
-- session.party is only written back once the battle ends, so reading it
-- mid-battle shows pre-battle HP: a Potion was refused with "It won't have any
-- effect." on a Pokémon the battle had already hurt (issue #2316).  The battle
-- fights a deep copy held in st.playerParty; that copy is the source of truth
-- while the battle is running.

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").requireData("game3_battle_item_party_test")

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
local Pokemon = require("src.core.game3.pokemon")
local Battle = require("src.core.game3.battle")
local State = require("src.core.game3.battle.state")
local PartyView = require("src.core.game3.battle.party_view")

ItemsData.install(nil)
Pokemon.install(nil)

local POTION = 13
local REVIVE = 24
local ORAN_BERRY = 139
local BERRY_POUCH_ITEM = 365

local fakeInputA = {
  wasPressed = function(self, k) local key = (k ~= nil) and k or self return key == "a" end,
}
local fakeInputB = {
  wasPressed = function(self, k) local key = (k ~= nil) and k or self return key == "b" end,
}

local function mon(species, name, hp, maxHp)
  return {
    species = species, name = name, level = 10,
    hp = hp, maxHp = maxHp, moves = { 33 }, pp = { 35 },
  }
end

-- session.party is the frozen pre-battle snapshot; liveParty is the working
-- copy the battle fights with.  They deliberately disagree -- reading the wrong
-- one is the bug under test.
local function make_session()
  local s = {
    name = "RED",
    bag = Bag.new(),
    dex = { seen = {}, owned = {} },
    party = {
      mon(1, "BULBASAUR", 20, 20),  -- frozen: full
      mon(4, "CHARMANDER", 20, 20), -- frozen: alive
      mon(7, "SQUIRTLE", 20, 20),   -- frozen: full
    },
  }
  s.liveParty = {
    mon(1, "BULBASAUR", 5, 20),   -- live: hurt
    mon(4, "CHARMANDER", 0, 20),  -- live: fainted
    mon(7, "SQUIRTLE", 20, 20),   -- live: full
  }
  return s
end

local Runtime = { _session = nil }
function Runtime.getSession() return Runtime._session end
package.loaded["src.core.game3.runtime"] = Runtime

local Ui = require("src.core.game3.battle.ui")
local BagMenu = require("src.ui.game3.bag_menu")
local PartyMenu = require("src.ui.game3.party_menu")
local BerryPouch = require("src.ui.game3.berry_pouch")

local function start_battle(s, activeSlot, extra)
  activeSlot = activeSlot or 1
  Runtime._session = s
  Battle._active = true
  Battle._phase = "command"
  local st = {
    player = State.makeBattler(s.liveParty[activeSlot], "player",
      { partyIndex = activeSlot }),
    playerParty = s.liveParty,
  }
  for k, v in pairs(extra or {}) do st[k] = v end
  Battle._st = st
  Ui._session = s
  Ui._pendingCommand = nil
  Ui._mode = "menu"
  Ui._queue = {}
  Ui._showing = false
  Ui._linger = false
  Ui.bindState(st)
  return st
end

local function open_bag_from_battle()
  Ui._menuIndex = 2 -- BAG
  Ui.handleInput(fakeInputA)
  BagMenu.settle()
end

local function find_row(itemId)
  local rows = BagMenu.list(BagMenu.currentPocket())
  for i, r in ipairs(rows) do
    if ItemsData.toNumericId(r.id) == itemId then return i end
  end
  return nil
end

-- Walk the bag's own list -> action menu -> USE, leaving the party menu open.
local function choose_use(itemId)
  local i = find_row(itemId)
  if not i then
    return false, "item " .. tostring(itemId) .. " not in " .. tostring(BagMenu.currentPocket())
  end
  BagMenu.cursor = i
  BagMenu.mode = "list"
  BagMenu.handleInput(fakeInputA) -- open the action menu
  BagMenu.actionCursor = 1        -- in battle USE is the first action
  BagMenu.handleInput(fakeInputA) -- USE
  BagMenu.settle()                -- field USE opens the submenu via begin_exit
  return true
end

local function select_party_row(row)
  PartyMenu.cursor = row
  PartyMenu.handleInput(fakeInputA)
  -- BagMenu.battleUse reports back to the battle only after its exit
  -- transition finishes.
  BagMenu.settle()
end

------------------------------------------------------------------------
print("[test] 1. PartyView.live falls back to session.party outside battle")
local s = make_session()
check(PartyView.live(s) == s.party, "no battle -> returns session.party itself")
check(type(PartyView.live(nil)) == "table" and next(PartyView.live(nil)) == nil,
  "nil session -> empty table")

------------------------------------------------------------------------
print("[test] 2. Heal accepted when the snapshot is full but the battle party is hurt")
s = make_session()
Bag.add(s.bag, POTION, 2)
local st = start_battle(s)
check(st.playerParty == s.liveParty, "battle fights the live copy, not session.party")
check(st.playerParty ~= s.party, "live copy is a different table from session.party")

open_bag_from_battle()
local ok, err = choose_use(POTION)
check(ok, "Potion row reachable in battle bag (" .. tostring(err) .. ")")
check(PartyMenu.open == true, "party menu opened for the Potion")
select_party_row(1) -- live[1] is hurt (5/20) even though session.party[1] is full
check(Ui._pendingCommand ~= nil, "Potion handed to the battle system")
check(Ui._pendingCommand and Ui._pendingCommand.itemId == POTION,
  "pending command carries the Potion")
check(Ui._pendingCommand and Ui._pendingCommand.partySlot == 1,
  "pending command targets party slot 1 (got "
    .. tostring(Ui._pendingCommand and Ui._pendingCommand.partySlot) .. ")")
check(Bag.get(s.bag, POTION) == 2, "Potion not consumed by the bag itself")

------------------------------------------------------------------------
print("[test] 3. Refusal still works when the battle party really is full")
s = make_session()
Bag.add(s.bag, POTION, 2)
start_battle(s)
open_bag_from_battle()
choose_use(POTION)
check(PartyMenu.open == true, "party menu opened")
select_party_row(3) -- live[3] is 20/20
check(Ui._pendingCommand == nil, "no pending command for a full-HP target")
check(PartyMenu.open == true, "party menu stays open after the refusal")
check(Bag.get(s.bag, POTION) == 2, "Potion not consumed on a refused heal")

------------------------------------------------------------------------
print("[test] 4. battleOrder maps the tapped row to the right party slot")
-- Active mon is party slot 2, so battleOrder returns { 2, 1, 3 }: row 1 is
-- slot 2 and row 2 is slot 1.  Mapping the slot twice (row 1 -> order[1] = 2,
-- then order[2] = 1) would heal slot 1 instead of slot 2.
s = make_session()
s.liveParty = {
  mon(1, "BULBASAUR", 20, 20),  -- slot 1: full  -> a Potion must be refused
  mon(4, "CHARMANDER", 5, 20),  -- slot 2: hurt  -> a Potion must work
  mon(7, "SQUIRTLE", 20, 20),   -- slot 3: full
}
Bag.add(s.bag, POTION, 2)
start_battle(s, 2, { _partyOrder = { 2, 1, 3 } })
check(table.concat(PartyMenu.battleOrder(Battle._st), ",") == "2,1,3",
  "battleOrder is non-identity (2,1,3)")
open_bag_from_battle()
choose_use(POTION)
select_party_row(1) -- row 1 == party slot 2, the hurt mon
check(Ui._pendingCommand ~= nil, "row 1 accepted the Potion")
check(Ui._pendingCommand and Ui._pendingCommand.partySlot == 2,
  "row 1 resolved to party slot 2, not slot 1 (got "
    .. tostring(Ui._pendingCommand and Ui._pendingCommand.partySlot) .. ")")

------------------------------------------------------------------------
print("[test] 5. Revive targets a mon fainted in battle but alive in the snapshot")
s = make_session()
Bag.add(s.bag, REVIVE, 2)
start_battle(s)
open_bag_from_battle()
choose_use(REVIVE)
check(PartyMenu.open == true, "party menu opened for the Revive")
select_party_row(2) -- live[2] is fainted (0/20), session.party[2] is 20/20
check(Ui._pendingCommand ~= nil, "Revive accepted on the fainted battler")
check(Ui._pendingCommand and Ui._pendingCommand.partySlot == 2,
  "Revive targets party slot 2")

------------------------------------------------------------------------
print("[test] 6. Berry Pouch hands a berry to the battle system too")
s = make_session()
Bag.add(s.bag, ORAN_BERRY, 2)
Bag.add(s.bag, BERRY_POUCH_ITEM, 1)
start_battle(s)
open_bag_from_battle()
BagMenu.pocketIdx = 2 -- KEY_ITEMS
local pouchRow = find_row(BERRY_POUCH_ITEM)
check(pouchRow ~= nil, "BERRY POUCH key item present")
BagMenu.cursor = pouchRow
BagMenu.mode = "list"
BagMenu.handleInput(fakeInputA) -- action menu -> { OPEN, CANCEL }
BagMenu.actionCursor = 1
BagMenu.handleInput(fakeInputA) -- OPEN
BagMenu.settle()
check(BerryPouch.isOpen() == true, "Berry Pouch opened from the battle bag")

BerryPouch.cursor = 1 -- first berry row
BerryPouch.handleInput(fakeInputA)
BerryPouch.handleInput(fakeInputA) -- USE
check(PartyMenu.open == true, "party menu opened from the Berry Pouch")
select_party_row(1) -- live[1] is hurt (5/20), session.party[1] is full
BagMenu.settle()
check(Ui._pendingCommand ~= nil, "berry handed to the battle system")
check(Ui._pendingCommand and Ui._pendingCommand.itemId == ORAN_BERRY,
  "pending command carries the Oran Berry (got "
    .. tostring(Ui._pendingCommand and Ui._pendingCommand.itemId) .. ")")
check(Bag.get(s.bag, ORAN_BERRY) == 2, "berry not consumed by the pouch itself")
check(BerryPouch.isOpen() == false, "Berry Pouch closed after the hand-off")

------------------------------------------------------------------------
print("[test] 7. Field (non-battle) party item use still heals session.party")
s = make_session()
s.party[1].hp = 5 -- hurt in the real save, since there is no battle copy
Runtime._session = s
Battle._active = false
Battle._st = nil
Ui._session = s
Ui._pendingCommand = nil
Bag.add(s.bag, POTION, 2)
BagMenu.show(s.bag, { session = s })
BagMenu.settle()
check(BagMenu._battle == false, "bag is not in battle mode")
local ok7, err7 = choose_use(POTION)
check(ok7, "Potion row reachable in the field bag (" .. tostring(err7) .. ")")
check(PartyMenu.open == true, "field party menu opened")
select_party_row(1)
check(s.party[1].hp > 5, "field Potion healed session.party (hp="
  .. tostring(s.party[1].hp) .. ")")
check(Ui._pendingCommand == nil, "field use does not queue a battle command")

Battle._active = false
Battle._st = nil

------------------------------------------------------------------------
if failed > 0 then
  print(string.format("\n%d FAILED", failed))
  os.exit(1)
end
print("\nAll battle item party tests passed.")
os.exit(0)
