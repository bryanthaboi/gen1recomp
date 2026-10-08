package.path = "./?.lua;./?/init.lua;" .. package.path
local version = os.getenv("POKEPORT_VERSION") or "firered"
require("src.core.GameVersion").set(version)
require("src.import.gba.versions").select(version)
local Cache = require("tests.game3_cache")
if not Cache.mount() then
  print("[skip] cursor2766 integration: " .. tostring(Cache.reason))
  os.exit(0)
end
if version == "ruby" or version == "sapphire" then
  local Kit = require("src.ui.game3.rse.scene_kit")
  local cache = require("src.core.game3.dataset").cache()
  Kit.loadLua = function(path)
    return assert(loadstring(assert(cache:read(path))))()
  end
  require("src.ui.game3.frlg_font").measure = function(text) return #tostring(text) * 6 end
end
local Bag = require("src.core.game3.bag")
local ItemsData = require("src.core.game3.items_data")
local Pokemon = require("src.core.game3.pokemon")
ItemsData.install(nil)
Pokemon.install(nil)
local Runtime = { session = nil }
function Runtime.getSession() return Runtime.session end
package.loaded["src.core.game3.runtime"] = Runtime
local Battle = require("src.core.game3.battle")
local Ui = require("src.core.game3.battle.ui")
local State = require("src.core.game3.battle.state")
local Engine = require("src.core.game3.battle.engine")
local BagMenu = require("src.ui.game3.bag_menu")
local PartyMenu = require("src.ui.game3.party_menu")
local function input(key)
  return { wasPressed = function(_, k) return k == key end }
end
local function press(key) Ui.handleInput(input(key)) end
local function check(ok, label)
  assert(ok, "FAIL cursor2766 " .. version .. " " .. label)
  print("PASS cursor2766 " .. version .. " " .. label)
end
local function mon(species, hp)
  return { species = species, level = 20, hp = hp or 1000, maxHp = 1000,
    moves = { 150 }, pp = { 40 } }
end
local function setup()
  Battle.abort()
  BagMenu.close()
  PartyMenu.close()
  local session = { version = version, name = "PLAYER", bag = Bag.new(),
    dex = { seen = {}, owned = {} }, party = { mon(1, 5), mon(4), mon(7) } }
  Bag.add(session.bag, 13, 3)
  Bag.add(session.bag, 4, 3)
  Runtime.session = session
  assert(Battle.start({ session = session, headless = true, autoFight = false,
    playerParty = session.party, foe = mon(150), wild = true }))
  for _ = 1, 50 do
    Battle.update(1 / 60, nil)
    if Ui._mode == "menu" then break end
  end
  assert(Ui._mode == "menu")
  return session, Battle.getState()
end
local function openBag()
  press("right")
  assert(Ui._menuIndex == 2)
  press("a")
  BagMenu.settle()
  assert(BagMenu.open)
end
local function choose(item)
  for pocket = 1, #ItemsData.BAG_POCKET_ORDER do
    BagMenu.pocketIdx = pocket
    for row, entry in ipairs(BagMenu.list(BagMenu.currentPocket())) do
      if ItemsData.toNumericId(entry.id) == item then
        BagMenu.cursor, BagMenu.scroll, BagMenu.mode = row, 0, "list"
        BagMenu.handleInput(input("a"))
        BagMenu.actionCursor = 1
        BagMenu.handleInput(input("a"))
        BagMenu.settle()
        return
      end
    end
  end
  error("missing item " .. item)
end
local function nextTurn(st)
  local turn = st.turn
  Battle._headless = false
  for _ = 1, 2000 do
    Battle.update(1 / 60, { input = input(nil) })
    if Battle._phase == "command" and Ui._mode == "menu" and st.turn > turn then
      Battle._headless = true
      return
    end
    assert(not st.over, "battle ended")
  end
  error("next turn unavailable " .. tostring(Battle._phase))
end
local session, st = setup()
openBag()
BagMenu.handleInput(input("b"))
BagMenu.settle()
check(Ui._mode == "menu" and Ui._menuIndex == 2, "Bag_cancel_retains_Bag")
session, st = setup()
openBag()
choose(13)
assert(PartyMenu.open)
PartyMenu.cursor = 1
for _ = 1, 100 do
  if not PartyMenu.open then break end
  PartyMenu.update(1 / 60)
  PartyMenu.handleInput(input("a"))
end
BagMenu.settle()
assert(Ui._pendingCommand and Ui._pendingCommand.usedInMenu)
local old = st.player
nextTurn(st)
check(Bag.get(session.bag, 13) == 2 and st.player == old and Ui._menuIndex == 2,
  "Potion_real_callback_next_turn_Bag")
press("a")
BagMenu.settle()
check(BagMenu.open and Ui._mode == "bag", "Potion_next_A_reopens_Bag")
BagMenu.close()
session, st = setup()
openBag()
choose(4)
assert(Ui._pendingCommand and Ui._pendingCommand.itemId == 4)
local Catching = require("src.core.game3.battle.catching")
local tryCatch = Catching.tryCatch
Catching.tryCatch = function() return false, 0 end
nextTurn(st)
Catching.tryCatch = tryCatch
check(Bag.get(session.bag, 4) == 2 and Ui._menuIndex == 2,
  "failed_Ball_real_callback_next_turn_Bag")
press("a")
BagMenu.settle()
check(BagMenu.open and Ui._mode == "bag", "failed_Ball_next_A_reopens_Bag")
BagMenu.close()
press("left")
press("down")
press("a")
assert(PartyMenu.open)
for _ = 1, 60 do PartyMenu.update(1 / 60) end
PartyMenu.handleInput(input("b"))
check(Ui._mode == "menu" and Ui._menuIndex == 3, "Pokemon_cancel_retains_Pokemon")
old = st.player
assert(Engine.performSwitch(st, Battle._adapter, 0, 2, { reason = "switch" }))
Ui.openMenu()
check(st.player ~= old and Ui._menuIndex == 1, "real_single_switch_resets_Fight")
session, st = setup()
st.double = true
st.absent = {}
st.battlers = { [0] = st.player, [1] = st.enemy,
  [2] = State.makeBattler(st.playerParty[2], "player", { partyIndex = 2, id = 2 }),
  [3] = State.makeBattler(st.enemy.mon, "enemy", { partyIndex = 1, id = 3 }) }
Ui.openMenu(0)
openBag()
choose(4)
local command = Ui.takeCommand()
check(command and command.battler == 0, "double_Bag_callback_owns_slot0")
Ui.openMenu(2, { partnerAction = command })
press("down")
Ui.openMenu(0)
check(Ui._menuIndex == 2, "double_slot0_retains_Bag")
assert(Engine.performSwitch(st, Battle._adapter, 2, 3, { reason = "switch" }))
Ui.openMenu(2)
check(Ui._menuIndex == 1, "real_double_slot2_switch_resets_Fight")
Ui.openMenu(0)
check(Ui._menuIndex == 2, "double_slot2_switch_preserves_slot0_Bag")
assert(Engine.performSwitch(st, Battle._adapter, 0, 2, { reason = "switch" }))
Ui.openMenu(0)
check(Ui._menuIndex == 1, "real_double_slot0_switch_resets_Fight")
Ui.reset({ headless = true })
check(next(Ui._actionCursor) == nil and next(Ui._actionCursorBattler) == nil,
  "new_battle_clears_cursor_ownership")
Battle.abort()
print("PASS cursor2766_cache_integration " .. version)
