local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/cursor2766"
return function(game)
  local failures = 0
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. "cursor2766_native " .. label)
    if not ok then failures = failures + 1 end
    return ok
  end
  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Bag = require("src.core.game3.bag")
  local Items = require("src.core.game3.items_data")
  local Bridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local BagMenu = require("src.ui.game3.bag_menu")
  local PartyMenu = require("src.ui.game3.party_menu")
  local Anim = require("src.core.game3.battle.anim")
  local AnimSeq = require("src.core.game3.battle.anim_seq")
  local Intro = require("src.core.game3.battle.intro_seq")
  local session = Runtime.getSession()
  session.party = {}
  Party.giveMon(session, 1, 20)
  Party.giveMon(session, 4, 20)
  Party.giveMon(session, 7, 20)
  for _, mon in ipairs(session.party) do mon.moves, mon.pp = { 150 }, { 40 } end
  session.party[1].hp = math.max(1, session.party[1].hp - 15)
  session.bag = Bag.new()
  Bag.add(session.bag, 13, 3)
  Bag.add(session.bag, 4, 3)
  local tick, lastTap = 0, 0
  local function busy()
    local step = AnimSeq._steps and AnimSeq._steps[AnimSeq._i]
    return (Anim.vm() and Anim.vm():busy()) or (step and step.kind ~= "msg") or Intro._waitingGen
  end
  local function untilState(predicate, limit)
    for _ = 1, limit or 5000 do
      tick = tick + 1
      if predicate() then return true end
      if not busy() and Ui.dialogPending() and tick - lastTap >= 14 then
        lastTap = tick
        U.tap(game, "a")
      else
        U.wait(1)
      end
    end
    return false
  end
  local function menu()
    return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu"
  end
  local function waitFor(predicate)
    for _ = 1, 600 do
      if predicate() then return true end
      U.wait(1)
    end
    return false
  end
  local function itemRow(item)
    for pocket = 1, #Items.BAG_POCKET_ORDER do
      BagMenu.pocketIdx = pocket
      for row, entry in ipairs(BagMenu.list(BagMenu.currentPocket())) do
        if Items.toNumericId(entry.id) == item then
          BagMenu.cursor, BagMenu.scroll = row, 0
          return true
        end
      end
    end
    return false
  end
  check(Bridge.startWild(Runtime._mod, game, { species = 150, level = 2 }, { fade = false }),
    "wild_battle_started")
  if not check(untilState(menu), "initial_command_menu") then love.event.quit(1) return end
  local st = Battle.getState()
  st.enemy.mon.moves, st.enemy.mon.pp = { 150 }, { 40 }
  local old, turn = st.player, st.turn
  U.tap(game, "right")
  U.tap(game, "a")
  if not check(waitFor(function() return BagMenu.open and BagMenu.mode == "list" and not BagMenu._open end),
      "Potion_Bag_open") then love.event.quit(1) return end
  assert(itemRow(13))
  U.tap(game, "a")
  U.wait(10)
  U.tap(game, "a")
  if not check(waitFor(function() return PartyMenu.open and PartyMenu.mode == "use" end),
      "Potion_Party_target_open") then love.event.quit(1) return end
  PartyMenu.cursor = 1
  U.wait(20)
  U.tap(game, "a")
  for _ = 1, 1200 do
    if not PartyMenu.open then break end
    U.tap(game, "a")
    U.wait(3)
  end
  if not check(untilState(function() return menu() and st.turn > turn end),
      "Potion_next_turn") then love.event.quit(1) return end
  check(st.player == old and Bag.get(session.bag, 13) == 2 and Ui._menuIndex == 2,
    "Potion_next_turn_Bag_selected")
  check(U.still(game, DIR .. "/2766_potion_next_turn_Bag_selected.png"), "Potion_Bag_shot")
  U.tap(game, "a")
  check(waitFor(function() return BagMenu.open and BagMenu.mode == "list" and not BagMenu._open end),
    "Potion_next_A_reopens_Bag")
  U.tap(game, "b")
  check(waitFor(menu) and Ui._menuIndex == 2, "Bag_cancel_retains_Bag")
  U.tap(game, "a")
  if not check(waitFor(function() return BagMenu.open and BagMenu.mode == "list" and not BagMenu._open end),
      "Ball_Bag_open") then love.event.quit(1) return end
  assert(itemRow(4))
  turn = st.turn
  local Catching = require("src.core.game3.battle.catching")
  local tryCatch = Catching.tryCatch
  Catching.tryCatch = function() return false, 0 end
  U.tap(game, "a")
  U.wait(10)
  U.tap(game, "a")
  local returned = untilState(function() return menu() and st.turn > turn end)
  Catching.tryCatch = tryCatch
  if not check(returned, "failed_Ball_next_turn") then love.event.quit(1) return end
  check(Bag.get(session.bag, 4) == 2 and Ui._menuIndex == 2, "failed_Ball_next_turn_Bag_selected")
  check(U.still(game, DIR .. "/2766_failed_ball_next_turn_Bag_selected.png"), "failed_Ball_Bag_shot")
  U.tap(game, "a")
  check(waitFor(function() return BagMenu.open and BagMenu.mode == "list" and not BagMenu._open end),
    "failed_Ball_next_A_reopens_Bag")
  U.tap(game, "b")
  if not waitFor(menu) then love.event.quit(1) return end
  U.tap(game, "left")
  U.tap(game, "down")
  U.tap(game, "a")
  if not check(waitFor(function() return PartyMenu.open end), "switch_Party_open") then
    love.event.quit(1) return
  end
  old, turn = st.player, st.turn
  PartyMenu.cursor = 2
  U.wait(60)
  U.tap(game, "a")
  U.wait(10)
  U.tap(game, "a")
  check(untilState(function() return menu() and st.player ~= old and st.turn > turn end),
    "real_switch_next_turn")
  check(Ui._menuIndex == 1 and st.player.partyIndex == 2, "real_switch_resets_Fight")
  check(U.still(game, DIR .. "/2766_switched_Pokemon_Fight_selected.png"), "switch_Fight_shot")
  local State = require("src.core.game3.battle.state")
  local Engine = require("src.core.game3.battle.engine")
  st.double, st.absent = true, {}
  st.battlers = { [0] = st.player, [1] = st.enemy,
    [2] = State.makeBattler(st.playerParty[1], "player", { partyIndex = 1, id = 2 }),
    [3] = State.makeBattler(st.enemy.mon, "enemy", { partyIndex = 1, id = 3 }) }
  local function direct(key)
    Ui.handleInput({ wasPressed = function(_, k) return k == key end })
  end
  Ui.openMenu(0)
  direct("right")
  Ui.openMenu(2)
  direct("down")
  Ui.openMenu(0)
  check(Ui._menuIndex == 2, "double_slot0_Bag_independent")
  assert(Engine.performSwitch(st, Battle._adapter, 2, 3, { reason = "switch" }))
  Ui.openMenu(2)
  check(Ui._menuIndex == 1, "real_double_slot2_switch_Fight")
  Ui.openMenu(0)
  check(Ui._menuIndex == 2, "double_partner_switch_preserves_Bag")
  print((failures == 0 and "PASS " or "FAIL ") .. "cursor2766_native_complete")
  love.event.quit(failures == 0 and 0 or 1)
end
