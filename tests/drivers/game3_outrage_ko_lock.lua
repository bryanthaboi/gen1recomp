local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_outrage_ko_lock"

return function(game)
  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED", rivalName = "BLUE", gender = 0 })
  U.wait(180)
  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local session = Runtime.getSession()
  session.party = {}
  Party.giveMon(session, 149, 100)
  Party.giveMon(session, 6, 50)
  local lead = session.party[1]
  lead.moves, lead.pp, lead.maxPp = { 200, 19, 58, 53 }, { 15, 15, 10, 15 }, { 15, 15, 10, 15 }
  lead.item, lead.heldItem = 200, 200
  lead.hp = 100

  local foe = { trainerId = 326, party = {} }
  for i = 1, 4 do foe.party[i] = { species = 44, level = 20, moves = { 71 } } end
  local ok, err = BattleBridge.start(Runtime._mod, game, foe, { trainerId = 326, fade = false })
  if not ok then
    print("FAIL outrage_ko_lock battle did not start", tostring(err))
    love.event.quit(1)
    return
  end

  local fails = 0
  local function expect(cond, label)
    if cond then print("PASS " .. label) else print("FAIL " .. label); fails = fails + 1 end
  end

  local function logText()
    return (table.concat(Ui.log() or {}, "\n"):gsub("%s+", " "))
  end
  local function count(s, pat)
    local n = 0
    for _ in s:gmatch(pat) do n = n + 1 end
    return n
  end

  local lockedMenus = 0
  local rampageAtSendOut = {}
  local lastEnemyIdx = nil
  local lastTap = 0
  local frames = 0
  local function step(pred)
    for _ = 1, 20000 do
      if not Battle.isActive() then return false end
      if pred and pred() then return true end
      frames = frames + 1
      local st = Battle.getState()
      if st and st.enemy and st.enemy.partyIndex ~= lastEnemyIdx then
        if lastEnemyIdx then rampageAtSendOut[#rampageAtSendOut + 1] = st.player.expRampageTurns or 0 end
        lastEnemyIdx = st.enemy.partyIndex
      end
      if st and Battle._phase == "command" and Ui._mode == "menu" then
        if st.player.expLockedMove then lockedMenus = lockedMenus + 1 end
        U.wait(10)
        U.tap(game, "a")
        U.wait(20)
        U.tap(game, "a")
        U.wait(20)
      elseif Ui.choiceActive and Ui.choiceActive() then
        U.wait(10)
        U.tap(game, "b")
        U.wait(20)
      elseif Ui.dialogPending and Ui.dialogPending() and frames - lastTap >= 14 then
        lastTap = frames
        U.tap(game, "a")
      else
        U.wait(1)
      end
    end
    return false
  end

  local Message = require("src.ui.game3.message")
  local function shownNow(pat)
    return function()
      if not Message.isWaiting() then return false end
      local page = (Message.currentPage() or ""):gsub("%s+", " ")
      return page:find(pat) ~= nil
    end
  end

  local sawLeftovers = step(function()
    local s = logText()
    return count(s, "fainted!") >= 1 and shownNow("LEFTOVERS")()
  end)
  expect(sawLeftovers, "outrage_ko_lock leftovers_on_ko_turn")
  if sawLeftovers then
    local p = Battle.getState().player
    print("INFO rampage_after_ko_turn=" .. tostring(p.expRampageTurns))
    expect(p.expLockedMove ~= nil and (p.expRampageTurns or 0) >= 1, "outrage_ko_lock still_locked_after_ko_turn")
    U.still(game, DIR .. "/2431_leftovers_after_ko.png")
  end

  local sawFatigue = step(shownNow("fatigue"))
  expect(sawFatigue, "outrage_ko_lock fatigue_confusion")
  if sawFatigue then U.still(game, DIR .. "/2431_fatigue_after_ko.png") end

  local st = Battle.getState()
  expect(st and st.player.expLockedMove == nil, "outrage_ko_lock lock_released")
  expect(lockedMenus == 0, "outrage_ko_lock no_menu_while_locked")
  local s = logText()
  local outrages = count(s, "used OUTRAGE!")
  expect(outrages >= 2 and outrages <= 3, "outrage_ko_lock rampage_2_or_3_turns (" .. outrages .. ")")
  print("INFO rampage_at_sendout=" .. table.concat(rampageAtSendOut, ","))

  step(nil)
  if fails == 0 then
    print("PASS outrage_ko_lock")
    love.event.quit(0)
  else
    print("FAIL outrage_ko_lock (" .. fails .. ")")
    love.event.quit(1)
  end
end
