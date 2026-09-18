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
      print("PASS u8 learn move four-move paths")
      love.event.quit(0)
    else
      print("FAIL u8 learn move four-move paths")
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
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local LearnMove = require("src.core.game3.battle.learn_move")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local SummaryMenu = require("src.ui.game3.summary_menu")

  local session = Schema.newGame({ name = "RED", rivalName = "BLUE", gender = 0 })

  local function fresh_charmander()
    session.party = {}
    Party.giveMon(session, 4, 6)
    local mon = session.party[1]
    Experience.syncExpToLevel(mon)
    mon.exp = SummaryData.expForLevel(Experience.growthRate(mon), 7) - 3
    mon.moves = { 10, 45, 33, 39 }
    mon.pp = { 35, 40, 35, 30 }
    mon.maxPp = { 35, 40, 35, 30 }
    return mon
  end

  local function page()
    return (Message.isOpen() and Message.currentPage and Message.currentPage()) or ""
  end
  local function anyLine(needle)
    for _, t in ipairs(Ui.log() or {}) do
      if t:find(needle, 1, true) then return true end
    end
    return false
  end
  local function advanceUntil(pred, limit)
    for f = 1, limit do
      U.wait(1)
      if pred() then return true end
      if f % 6 == 0 and not Choice.active and not Message._stay and not SummaryMenu.isOpen() then U.tap(game, "a") end
    end
    return false
  end
  local function promptUp(needle)
    return function()
      return Choice.active and Choice.kind == "yesno" and Message.isWaiting()
        and page():find(needle, 1, true) ~= nil
    end
  end
  local function start_wild()
    return BattleBridge.startWild(Runtime._mod, game, { species = 16, level = 3 }, { fade = false })
  end

  fresh_charmander()
  session.map = "FR_ROUTE_1"
  session.x = 10
  session.y = 20
  session.flags = session.flags or {}
  game:_enterField(session, "new_game")
  U.wait(90)

  local function countLines(needle)
    local n = 0
    for _, t in ipairs(Ui.log() or {}) do
      if t:find(needle, 1, true) then n = n + 1 end
    end
    return n
  end

  check(start_wild(), "u8 stop-path battle started")
  if not check(advanceUntil(promptUp("Delete a move to make"), 6000), "u8b TRYTOLEARNMOVE3 prompt shows with Yes/No") then
    U.shot(game, DIR .. "/u8b_98_softlock_before_delete_prompt.png")
    return finish()
  end
  check(anyLine("is trying to\nlearn EMBER.") and anyLine("can't learn\nmore than four moves."),
    "u8b TRYTOLEARNMOVE1 and TRYTOLEARNMOVE2 shown first")
  check(Choice.style == "battle" and Choice.left == 24 and Choice.top == 9
    and Choice.options[1] == "Yes" and Choice.options[2] == "No",
    "u8b Yes/No window at cart tiles 23..29 x 8..13")
  U.wait(20)
  U.shot(game, DIR .. "/u8b_01_delete_prompt_yesno.png")
  U.tap(game, "down")
  U.wait(4)
  U.tap(game, "a")
  if not check(advanceUntil(promptUp("Stop learning\nEMBER?"), 600), "u8b NO opens Stop learning prompt") then
    return finish()
  end
  U.wait(20)
  U.shot(game, DIR .. "/u8b_02_stop_learning_prompt.png")
  U.tap(game, "down")
  U.wait(4)
  U.tap(game, "a")
  if not check(advanceUntil(promptUp("Delete a move to make"), 900), "u8b NO to stop re-asks") then
    return finish()
  end
  check(countLines("is trying to\nlearn EMBER.") == 2, "u8b re-ask reprints TRYTOLEARNMOVE1")
  U.tap(game, "down")
  U.wait(4)
  U.tap(game, "a")
  if not check(advanceUntil(promptUp("Stop learning\nEMBER?"), 600), "u8b second Stop learning prompt") then
    return finish()
  end
  U.wait(10)
  U.tap(game, "a")
  local sawDidNot = advanceUntil(function()
    return Message.isWaiting() and page():find("did not learn\nEMBER.", 1, true) ~= nil
  end, 600)
  if check(sawDidNot, "u8b YES to stop prints DIDNOTLEARNMOVE") then
    U.wait(10)
    U.shot(game, DIR .. "/u8b_03_did_not_learn.png")
  end
  check(advanceUntil(function() return not Battle.isActive() end, 3000), "u8 stop-path battle ended")
  local m1 = session.party[1]
  check(m1 and table.concat(m1.moves, ",") == "10,45,33,39" and m1.level == 7, "u8 stop path kept moves at LV. 7")
  check(not LearnMove.busy(), "u8 LearnMove idle after stop path")
  U.wait(60)

  fresh_charmander()
  check(start_wild(), "u8 forget-path battle started")
  if not check(advanceUntil(promptUp("Delete a move to make"), 6000), "u8 forget path reaches delete prompt") then
    return finish()
  end
  U.wait(10)
  U.tap(game, "a")
  local function summaryUp()
    return SummaryMenu.isOpen() and SummaryMenu._mode == "select_move"
  end
  if not check(advanceUntil(summaryUp, 600), "u8b YES opens summary move-select") then
    return finish()
  end
  check(not (Choice.active and Choice.kind == "multi"), "u8b no Choice forget list")
  check(tonumber(SummaryMenu._moveToLearn) == 52, "u8b summary fifth move is EMBER")
  U.wait(30)
  U.shot(game, DIR .. "/u8b_04_summary_select_move.png")
  U.tap(game, "b")
  if not check(advanceUntil(promptUp("Stop learning\nEMBER?"), 600), "u8b summary B goes to Stop learning") then
    return finish()
  end
  U.tap(game, "down")
  U.wait(4)
  U.tap(game, "a")
  if not check(advanceUntil(promptUp("Delete a move to make"), 900), "u8b NO re-asks after summary cancel") then
    return finish()
  end
  U.wait(10)
  U.tap(game, "a")
  if not check(advanceUntil(summaryUp, 600), "u8b summary reopens") then
    return finish()
  end
  U.wait(20)
  U.tap(game, "a")
  local sawLearned = advanceUntil(function()
    return Message.isWaiting() and page():find("learned", 1, true) ~= nil and anyLine("Poof!")
  end, 900)
  if check(sawLearned, "u8 Poof chain reaches learned EMBER") then
    check(anyLine("1, 2, and… … … Poof!"), "u8b 123POOF text")
    check(anyLine("CHARMANDER forgot\nSCRATCH.") and anyLine("And…"), "u8b PKMNFORGOTMOVE and ANDELLIPSIS text")
    U.wait(10)
    U.shot(game, DIR .. "/u8b_05_learned_ember.png")
  end
  check(advanceUntil(function() return not Battle.isActive() end, 3000), "u8 forget-path battle ended")
  local m2 = session.party[1]
  check(m2 and m2.moves[1] == 52 and m2.level == 7, "u8 EMBER replaced SCRATCH at LV. 7")
  U.wait(60)
  U.shot(game, DIR .. "/u8_06_back_on_route1.png")
  finish()
end
