local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp"

local failures = 0
local function result(ok, label)
  if ok then
    print("PASS " .. label)
  else
    failures = failures + 1
    print("FAIL " .. label)
  end
  return ok
end

local function mods()
  return package.loaded["src.ui.game3.pc_menu"], package.loaded["src.ui.game3.message"],
    package.loaded["src.core.game3.scripting.space"]
end

local function waitFor(pred, n)
  for _ = 1, n do
    if pred() then return true end
    U.wait(1)
  end
  return pred()
end

local function finish()
  if failures == 0 then
    print("PASS u1_bedroom_pc")
    love.event.quit(0)
  else
    print("FAIL u1_bedroom_pc failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  U.wait(30)
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(120)
  local Map = require("src.core.game3.map")
  Map.load(nil, game, "FR_PLAYERS_HOUSE_2F", { x = 1, y = 2, facing = "up" })
  game.session.x, game.session.y, game.session.facing = 1, 2, "up"
  U.wait(90)

  local st = game.session.storage
  result(st and st.items[1] and st.items[1].id == 13 and st.items[1].qty == 1, "new game PC holds POTION x1")

  U.tap(game, "a")
  local booted = waitFor(function()
    local _, Message = mods()
    return Message and Message.isOpen and Message.isOpen()
  end, 120)
  U.wait(20)
  if result(booted, "booted up the PC message") then
    U.shot(game, DIR .. "/u1_01_booted_pc_msg.png")
  end

  local PcMenu
  local opened = false
  for _ = 1, 6 do
    U.tap(game, "a")
    opened = waitFor(function()
      PcMenu = mods()
      return PcMenu and PcMenu.isOpen and PcMenu.isOpen()
    end, 60)
    if opened then break end
  end
  U.wait(10)
  local Natives = package.loaded["src.core.game3.scripting.natives"]
  result(not (Natives and Natives._logged and Natives._logged["special:249"]), "special 0xF9 not skipped")
  if not result(opened and PcMenu.mode == "player_pc", "bedroom PC opens straight to player PC menu") then
    return finish()
  end
  U.shot(game, DIR .. "/u1_02_player_pc_menu.png")

  U.tap(game, "a")
  U.wait(15)
  result(PcMenu.mode == "item_storage", "ITEM STORAGE opens the item submenu")
  U.tap(game, "a")
  local ItemPc = require("src.ui.game3.item_pc")
  if result(waitFor(function() return ItemPc.isOpen() and not ItemPc._fx end, 120), "WITHDRAW ITEM opens the item PC") then
    U.shot(game, DIR .. "/u1_03_withdraw_list_potion.png")
  end

  U.tap(game, "a")
  U.wait(15)
  U.tap(game, "a")
  U.wait(15)
  local Bag = require("src.core.game3.bag")
  local got = Bag.has(game.session.bag, 13, 1)
  if result(ItemPc.mode == "result" and got, "POTION withdrawn into bag") then
    U.shot(game, DIR .. "/u1_04_withdrew_potion.png")
  end

  U.tap(game, "a")
  U.wait(15)
  U.tap(game, "b")
  waitFor(function() return not ItemPc.isOpen() end, 120)
  U.wait(15)
  U.tap(game, "b")
  U.wait(15)
  U.tap(game, "b")
  local closedOk = waitFor(function()
    local _, Message, Space = mods()
    local running = Space and Space.vm and Space.vm.isRunning and Space.vm:isRunning()
    return not PcMenu.isOpen() and not running and not (Message and Message.isOpen and Message.isOpen())
  end, 120)
  U.wait(20)
  if result(closedOk, "B turns the PC off and returns to the field") then
    U.shot(game, DIR .. "/u1_05_pc_off_field.png")
  end

  finish()
end
