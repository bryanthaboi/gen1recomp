local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp"

return function(game)
  local fails = 0
  local function check(cond, label)
    if cond then
      print("PASS " .. label)
    else
      fails = fails + 1
      print("FAIL " .. label)
    end
    return cond
  end
  local function finish()
    if fails == 0 then
      print("PASS u8c battle yes/no user frame")
      love.event.quit(0)
    else
      print("FAIL u8c battle yes/no user frame")
      love.event.quit(1)
    end
  end

  U.wait(30)
  local Schema = require("src.core.game3.save_schema_firered")
  local Party = require("src.core.game3.party")
  local Experience = require("src.core.game3.battle.experience")
  local SummaryData = require("src.core.game3.summary_data")
  local Runtime = require("src.core.game3.runtime")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local SummaryMenu = require("src.ui.game3.summary_menu")
  local Chrome = require("src.ui.game3.chrome")

  local draws = {}
  local origUser, origStd = Chrome.userFrame, Chrome.stdFrame
  Chrome.userFrame = function(frameType, tx, ty, tw, th)
    draws[#draws + 1] = { kind = "user", frameType = frameType, tx, ty, tw, th }
    return origUser(frameType, tx, ty, tw, th)
  end
  Chrome.stdFrame = function(tx, ty, tw, th)
    draws[#draws + 1] = { kind = "std", tx, ty, tw, th }
    return origStd(tx, ty, tw, th)
  end
  local function yesNoFrame()
    local user, std
    for _, d in ipairs(draws) do
      if d[1] == 24 and d[2] == 9 and d[3] == 5 and d[4] == 4 then
        if d.kind == "user" then user = d else std = d end
      end
    end
    return user, std
  end

  local session = Schema.newGame({ name = "RED", rivalName = "BLUE", gender = 0 })
  session.party = {}
  Party.giveMon(session, 4, 6)
  local mon = session.party[1]
  Experience.syncExpToLevel(mon)
  mon.exp = SummaryData.expForLevel(Experience.growthRate(mon), 7) - 3
  mon.moves = { 10, 45, 33, 39 }
  mon.pp = { 35, 40, 35, 30 }
  mon.maxPp = { 35, 40, 35, 30 }
  session.map = "FR_ROUTE_1"
  session.x = 10
  session.y = 20
  session.flags = session.flags or {}
  game:_enterField(session, "new_game")
  U.wait(90)

  local live = Runtime.getSession() or session
  live.options = live.options or {}
  live.options.frameType = 3

  local function page()
    return (Message.isOpen() and Message.currentPage and Message.currentPage()) or ""
  end
  local function advanceUntil(pred, limit)
    for f = 1, limit do
      U.wait(1)
      if pred() then return true end
      if f % 6 == 0 and not Choice.active and not Message._stay and not SummaryMenu.isOpen() then U.tap(game, "a") end
    end
    return false
  end

  check(BattleBridge.startWild(Runtime._mod, game, { species = 16, level = 3 }, { fade = false }),
    "u8c battle started")
  local up = advanceUntil(function()
    return Choice.active and Choice.kind == "yesno" and Message.isWaiting()
      and page():find("Delete a move to make", 1, true) ~= nil
  end, 6000)
  if not check(up, "u8c TRYTOLEARNMOVE3 Yes/No box up") then
    U.shot(game, DIR .. "/u8c_98_no_yesno.png")
    return finish()
  end

  for i = #draws, 1, -1 do draws[i] = nil end
  U.wait(20)
  local user, std = yesNoFrame()
  check(user ~= nil and user.frameType == 3, "u8c Yes/No drawn with user frame 3 at content 24,9 5x4")
  check(std == nil, "u8c Yes/No no longer drawn with the std frame")
  U.shot(game, DIR .. "/u8c_01_battle_yesno_user_frame_3.png")

  live.options.frameType = 0
  for i = #draws, 1, -1 do draws[i] = nil end
  U.wait(10)
  user, std = yesNoFrame()
  check(user ~= nil and user.frameType == 0 and std == nil, "u8c Yes/No follows options frame 0")
  U.shot(game, DIR .. "/u8c_02_battle_yesno_user_frame_0.png")

  local Window = require("src.ui.game3.window")
  local cursors = {}
  local origCursorPx = Window.cursorPx
  Window.cursorPx = function(px, py, o)
    cursors[#cursors + 1] = { px, py }
    return origCursorPx(px, py, o)
  end
  local function cursorAt(px, py)
    for _, c in ipairs(cursors) do
      if c[1] == px and c[2] == py then return true end
    end
    return false
  end
  local function rowsSeen()
    local seen, out = {}, {}
    for _, c in ipairs(cursors) do seen[c[2]] = true end
    for k in pairs(seen) do out[#out + 1] = k end
    table.sort(out)
    return table.concat(out, ",")
  end
  U.wait(10)
  check(cursorAt(24 * 8, 9 * 8) and not cursorAt(24 * 8, 9 * 8 + 2),
    "u8c Yes cursor drawn at tile (24,9) = px (192,72), no +2 (y seen: " .. rowsSeen() .. ")")
  for i = #cursors, 1, -1 do cursors[i] = nil end
  U.tap(game, "down")
  U.wait(10)
  check(Choice.cursor == 2 and cursorAt(24 * 8, 11 * 8), "u8c No cursor drawn at tile (24,11) = px (192,88)")
  U.shot(game, DIR .. "/u8c_03_battle_yesno_cursor_no_row11.png")
  Window.cursorPx = origCursorPx

  Chrome.userFrame, Chrome.stdFrame = origUser, origStd
  finish()
end
