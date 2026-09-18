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

local function pcMid()
  local Map = require("src.core.game3.map")
  local def = Map.currentDef and Map.currentDef()
  local layout = def and def.midLayout
  return layout and layout:midAt(1, 1)
end

local function finish()
  if failures == 0 then
    print("PASS u1b_pc_fidelity")
    love.event.quit(0)
  else
    print("FAIL u1b_pc_fidelity failures=" .. failures)
    love.event.quit(1)
  end
end

local function tapWait(game, btn, n)
  U.tap(game, btn)
  U.wait(n or 12)
end

return function(game)
  U.wait(30)
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(120)
  local Map = require("src.core.game3.map")
  Map.load(nil, game, "FR_PLAYERS_HOUSE_2F", { x = 1, y = 2, facing = "up" })
  game.session.x, game.session.y, game.session.facing = 1, 2, "up"
  U.wait(90)

  result(pcMid() == 0x28F, string.format("bedroom PC starts off 0x28F (got %s)", tostring(pcMid())))

  U.tap(game, "a")
  local seen, last = {}, pcMid()
  for _ = 1, 90 do
    local m = pcMid()
    if m ~= last then
      seen[#seen + 1] = string.format("%X", m or 0)
      last = m
    end
    U.wait(1)
  end
  local seq = table.concat(seen, ",")
  local PcAnim = require("src.core.game3.pc_anim")
  local canLight = PcAnim.drawable(0x28A)
  print("[u1b] turn-on metatile sequence " .. seq .. " atlasHas28A=" .. tostring(canLight))
  local _, Message = mods()
  if canLight then
    result(seq == "28A,28F,28A,28F,28A", "AnimatePcTurnOn flickers on/off/on/off/on")
    result(pcMid() == 0x28A and Message and Message.isOpen and Message.isOpen(), "PC lit behind booted-up message")
  else
    result(seq == "" and pcMid() == 0x28F and Message and Message.isOpen and Message.isOpen(),
      "PlayersPCOn 0x28A not in this cache's atlas: swap skipped, no black tile")
  end
  U.shot(game, DIR .. "/u1b_01_pc_lit_booted_msg.png")

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
  if not result(opened and PcMenu.mode == "player_pc", "bedroom PC opens the player PC top menu") then
    return finish()
  end
  local labels = {}
  for i, a in ipairs(PcMenu.TOP_ACTIONS or {}) do labels[i] = a.label end
  result(table.concat(labels, "/") == "ITEM STORAGE/MAILBOX/TURN OFF"
    and PcMenu._status == "What would you like to do?", "top menu ITEM STORAGE / MAILBOX / TURN OFF")
  U.shot(game, DIR .. "/u1b_02_top_menu.png")

  tapWait(game, "a")
  result(PcMenu.mode == "item_storage" and PcMenu._status == "Take out items from the PC.",
    "ITEM STORAGE submenu with WITHDRAW description")
  U.shot(game, DIR .. "/u1b_03_item_storage_withdraw_desc.png")

  tapWait(game, "down")
  result(PcMenu._status == "Store items in the PC.", "DEPOSIT ITEM description")
  U.shot(game, DIR .. "/u1b_04_item_storage_deposit_desc.png")

  tapWait(game, "down")
  result(PcMenu._status == "Go back to the\nprevious menu.", "CANCEL description")
  U.shot(game, DIR .. "/u1b_05_item_storage_cancel_desc.png")

  tapWait(game, "up")
  tapWait(game, "up")
  tapWait(game, "a")
  result(PcMenu.mode == "withdraw_item", "WITHDRAW ITEM lists PC items")
  tapWait(game, "a")
  local Bag = require("src.core.game3.bag")
  local sess = PcMenu._session or game.session
  result(PcMenu.mode == "msg" and Bag.has(sess.bag, 13, 1), "POTION withdrawn into bag")
  tapWait(game, "a")
  result(PcMenu.mode == "item_storage" and PcMenu.cursor == 1, "back in ITEM STORAGE after withdraw")

  tapWait(game, "b")
  result(PcMenu.mode == "player_pc" and PcMenu.cursor == 1, "B returns to top menu")
  tapWait(game, "down")
  tapWait(game, "a")
  result(PcMenu.mode == "msg" and PcMenu._status == "There's no MAIL here.", "MAILBOX shows There's no MAIL here.")
  U.shot(game, DIR .. "/u1b_06_mailbox_no_mail.png")
  tapWait(game, "a")
  result(PcMenu.mode == "player_pc" and PcMenu._status == "What would you like to do?", "mail message returns to top menu")

  tapWait(game, "down")
  tapWait(game, "down")
  U.tap(game, "a")
  local closedOk = waitFor(function()
    local _, Msg, Space = mods()
    local running = Space and Space.vm and Space.vm.isRunning and Space.vm:isRunning()
    return not PcMenu.isOpen() and not running and not (Msg and Msg.isOpen and Msg.isOpen())
  end, 120)
  U.wait(20)
  result(closedOk, "TURN OFF closes the PC and releases the player")
  result(pcMid() == 0x28F, string.format("ShutDownPC swaps the PC back to 0x28F (got %s)", tostring(pcMid())))
  local Natives = package.loaded["src.core.game3.scripting.natives"]
  local logged = Natives and Natives._logged or {}
  result(not logged["special:214"] and not logged["special:215"] and not logged["special:249"],
    "AnimatePcTurnOn / AnimatePcTurnOff / BedroomPC not skipped")
  U.shot(game, DIR .. "/u1b_07_turned_off_field.png")

  local Schema = require("src.core.game3.save_schema_firered")
  local live = PcMenu._session or game.session
  live.storage.items[1] = { id = 17, qty = 3 }
  local saved = Schema.toSaveTable(live)
  local restored = Schema.fromSaveTable(saved)
  result(saved.pc == nil and live.pc == nil and restored.storage and restored.storage.items[1]
    and restored.storage.items[1].id == 17 and restored.storage.items[1].qty == 3,
    "PC items live in session.storage only and survive save/continue")
  live.storage.items[1] = nil

  finish()
end
