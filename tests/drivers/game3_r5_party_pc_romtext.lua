local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_r5_party_pc_romtext"

local CHARMANDER, PIDGEY = 4, 16
local MOVE_CUT = 15
local ITEM_POTION = 13

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS r5_party_pc_romtext")
    love.event.quit(0)
  else
    print("FAIL r5_party_pc_romtext failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Storage = require("src.core.game3.storage")
  local FrlgFont = require("src.ui.game3.frlg_font")
  local PartyMenu = require("src.ui.game3.party_menu")
  local BoxStorageUI = require("src.ui.game3.box_storage_ui")
  local ReleaseSeq = require("src.ui.game3.release_seq")
  local PcMenu = require("src.ui.game3.pc_menu")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local drawn = {}
  local realDraw = FrlgFont.draw
  FrlgFont.draw = function(text, ...)
    drawn[#drawn + 1] = tostring(text)
    return realDraw(text, ...)
  end
  local function capture(n)
    drawn = {}
    U.wait(n or 2)
    for _ = 1, 4000 do
      if #drawn > 0 then break end
      U.wait(1)
    end
    return table.concat(drawn, " | ")
  end
  local function has(s, needle) return s:find(needle, 1, true) ~= nil end

  session.party = {}
  local _, _, lead = Party.giveMon(session, CHARMANDER, 12)
  lead.moves[2] = MOVE_CUT
  for _ = 1, 5 do Party.giveMon(session, PIDGEY, 5) end

  PartyMenu.show(session.party, { session = session })
  U.wait(20)
  U.tap(game, "a")
  U.wait(10)
  result(PartyMenu.mode == "action", "A on the lead opens the action menu")
  result(PartyMenu.ACTIONS[1] == "SUMMARY" and PartyMenu.ACTIONS[2] == "CUT",
    "pret order SUMMARY, CUT (got " .. table.concat(PartyMenu.ACTIONS, ",") .. ")")
  local actionText = capture()
  result(has(actionText, "Do what with this") and has(actionText, "SUMMARY") and has(actionText, "CUT")
    and has(actionText, "SWITCH") and has(actionText, "CANCEL"), "action menu draws ROM labels: " .. actionText)
  U.shot(game, DIR .. "/r5_party_action_menu.png")
  U.tap(game, "b")
  U.wait(10)
  U.tap(game, "up")
  U.wait(6)
  U.tap(game, "up")
  U.wait(6)
  result(PartyMenu.cursor == 6, "cursor on the sixth slot (" .. tostring(PartyMenu.cursor) .. ")")
  U.tap(game, "a")
  U.wait(10)
  U.shot(game, DIR .. "/r5_party_action_menu_slot6.png")
  U.tap(game, "b")
  U.wait(10)
  PartyMenu.showMessage(require("src.core.game3.rom_text").plain("gText_WontHaveEffect"),
    function() PartyMenu.mode = "list" end)
  U.wait(10)
  U.shot(game, DIR .. "/r5_party_message_over_slot6.png")
  U.tap(game, "a")
  U.wait(10)
  PartyMenu.close()
  U.wait(10)

  local storage = Storage.ensure(session)
  storage.currentBox = 1
  storage.boxes[1].mons[1] = table.remove(session.party)
  BoxStorageUI.show({ session = session, subMode = "withdraw" })
  U.wait(30)
  BoxStorageUI.cursorSlot = 1
  U.tap(game, "a")
  U.wait(10)
  result(BoxStorageUI.mode == "action_menu", "A on a box mon opens the storage action menu")
  local boxText = capture()
  result(has(boxText, "WITHDRAW") and has(boxText, "RELEASE") and has(boxText, "SUMMARY"),
    "storage menu draws sMenuTexts labels: " .. boxText)
  U.shot(game, DIR .. "/r5_box_action_menu.png")
  U.tap(game, "down")
  U.wait(4)
  U.tap(game, "down")
  U.wait(4)
  U.tap(game, "a")
  U.wait(10)
  result(ReleaseSeq.isActive() and ReleaseSeq.state == "confirm", "RELEASE opens the release confirm")
  local confirmText = capture()
  result(has(confirmText, "Release this POKéMON?"), "confirm reads gText_ReleaseThisPokemon: " .. confirmText)
  U.shot(game, DIR .. "/r5_release_confirm.png")
  U.tap(game, "up")
  U.wait(4)
  U.tap(game, "a")
  U.wait(90)
  result(ReleaseSeq.state == "released", "after the float the box shows was released (" .. tostring(ReleaseSeq.state) .. ")")
  local releasedText = capture()
  result(has(releasedText, "PIDGEY was released."), "gText_PkmnWasReleased: " .. releasedText)
  U.shot(game, DIR .. "/r5_release_was_released.png")
  U.tap(game, "right")
  U.wait(6)
  local byeText = capture()
  result(ReleaseSeq.state == "bye" and has(byeText, "Bye-bye, PIDGEY!"), "d-pad advances to gText_ByeByePkmn: " .. byeText)
  U.shot(game, DIR .. "/r5_release_bye_bye.png")
  U.tap(game, "down")
  U.wait(6)
  result(not ReleaseSeq.isActive(), "d-pad closes the release sequence")
  BoxStorageUI.close()
  U.wait(10)

  storage.items = { { id = ITEM_POTION, qty = 5 } }
  PcMenu.show({ session = session, startMode = "player_pc", closeOnExit = true })
  U.wait(10)
  local topText = capture()
  result(has(topText, "ITEM STORAGE") and has(topText, "MAILBOX") and has(topText, "TURN OFF"),
    "player PC top menu: " .. topText)
  U.tap(game, "a")
  U.wait(6)
  U.tap(game, "a")
  U.wait(6)
  local ItemPc = require("src.ui.game3.item_pc")
  for _ = 1, 120 do
    if ItemPc.isOpen() and not ItemPc._fx then break end
    U.wait(1)
  end
  result(ItemPc.isOpen() and not ItemPc._fx, "WITHDRAW ITEM opens the item PC")
  U.shot(game, DIR .. "/r5_pc_withdraw_list.png")
  U.tap(game, "a")
  U.wait(6)
  U.tap(game, "a")
  U.wait(6)
  local qtyText = capture()
  result(ItemPc.mode == "qty" and has(qtyText, "Withdraw how many"),
    "quantity prompt is gText_WithdrawHowMany: " .. qtyText)
  U.shot(game, DIR .. "/r5_pc_withdraw_how_many.png")
  U.tap(game, "up")
  U.wait(4)
  U.tap(game, "a")
  U.wait(6)
  result(ItemPc.mode == "result" and has(tostring(ItemPc.resultText), "Withdrew 2"),
    "withdraw result is gText_WithdrewQuantItem: " .. tostring(ItemPc.resultText))
  U.shot(game, DIR .. "/r5_pc_withdrew.png")
  U.tap(game, "a")
  U.wait(6)
  U.tap(game, "b")
  for _ = 1, 120 do
    if not ItemPc.isOpen() then break end
    U.wait(1)
  end
  PcMenu.close()
  U.wait(6)

  FrlgFont.draw = realDraw
  finish()
end
