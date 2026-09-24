local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_evolution_learn_in_battle"

local RATTATA, MAGIKARP = 19, 129
local FOCUS_ENERGY, SCARY_FACE = 116, 184

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print(failures == 0 and "PASS evolution_learn_in_battle" or ("FAIL evolution_learn_in_battle failures=" .. failures))
  love.event.quit(failures == 0 and 0 or 1)
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
  local Pokemon = require("src.core.game3.pokemon")
  local SummaryData = require("src.core.game3.summary_data")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local Ui = require("src.core.game3.battle.ui")
  local Choice = require("src.ui.game3.choice")
  local Message = require("src.ui.game3.message")
  local SummaryMenu = require("src.ui.game3.summary_menu")
  local EvolutionScene = require("src.ui.game3.evolution_scene")
  local Stack = require("src.ui.game3.stack")

  local closePressed, leaked = nil, 0
  local origClose = SummaryMenu.close
  SummaryMenu.close = function(...)
    closePressed = game.input.pressed
    return origClose(...)
  end
  local origEvoInput = EvolutionScene.handleInput
  EvolutionScene.handleInput = function(input)
    if closePressed and input.pressed == closePressed
        and (input:wasPressed("a") or input:wasPressed("b")) then
      leaked = leaked + 1
    end
    return origEvoInput(input)
  end

  local session = Runtime.getSession()
  if not result(session ~= nil, "field reached") then return finish() end
  session.party = {}
  Party.giveMon(session, RATTATA, 19)
  local mine = session.party[1]
  mine.moves = { 33, 39, 98, 158 }
  mine.pp = { 35, 30, 30, 15 }
  mine.maxPp = { 35, 30, 30, 15 }
  mine.exp = SummaryData.expForLevel(Pokemon.growthRate(RATTATA), 20) - 1

  local ok, err = BattleBridge.startWild(Runtime._mod, game, { species = MAGIKARP, level = 30 }, { fade = false })
  if not result(ok == true, "battle started " .. tostring(err or "")) then return finish() end

  local lastTap, f = 0, 0
  local prompts, summaries = 0, 0
  local sawEvoPrompt = false
  for _ = 1, 20000 do
    f = f + 1
    local evoOpen = EvolutionScene.isOpen()
    if not Battle.isActive() and not evoOpen then break end
    if Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu" then
      local est = Battle.getState() and Battle.getState().enemy
      if est and est.mon then
        est.mon.moves = { 150, 0, 0, 0 }
        est.mon.pp = { 40, 0, 0, 0 }
        est.mon.hp = 1
        local ep = Anim.present("enemy")
        if ep then ep.displayHp = 1 end
      end
      Ui._pendingCommand = { kind = "move", move = 33, slot = 1, user = "player" }
      Ui._mode = "none"
      U.wait(2)
    elseif SummaryMenu.isOpen() and SummaryMenu._mode == "select_move" then
      summaries = summaries + 1
      local tag = evoOpen and "evolving" or "awarding"
      U.wait(30)
      U.still(game, DIR .. "/2450_" .. tag .. "_forget_summary.png")
      local target = evoOpen and 2 or 4
      local stepsOk = true
      while SummaryMenu._moveCursor < target do
        local before = SummaryMenu._moveCursor
        U.tap(game, "down")
        U.wait(4)
        if SummaryMenu._moveCursor ~= before + 1 then stepsOk = false break end
      end
      result(stepsOk and SummaryMenu._moveCursor == target, string.format(
        "%s summary DOWN steps one slot per press (cursor=%s target=%d phase=%s top=%s)", tag,
        tostring(SummaryMenu._moveCursor), target, tostring(Battle._phase), tostring(Stack.top() and Stack.top().id)))
      if not stepsOk then return finish() end
      U.tap(game, "a")
      U.wait(10)
      if not result(not SummaryMenu.isOpen(), tag .. " summary closes on A") then
        U.shot(game, DIR .. "/2450_" .. tag .. "_summary_frozen.png")
        return finish()
      end
      U.still(game, DIR .. "/2450_" .. tag .. "_after_forget.png")
      if summaries > 3 then result(false, "summary loop") return finish() end
    elseif Choice.active and Message.isWaiting() then
      prompts = prompts + 1
      local page = (Message.currentPage and Message.currentPage() or ""):gsub("\n", " / ")
      local tag = evoOpen and "evolving" or "awarding"
      if evoOpen then sawEvoPrompt = true end
      local before = Choice.cursor
      U.tap(game, "down")
      U.wait(4)
      result(before == 1 and Choice.cursor == 2, string.format("%s yes/no #%d DOWN lands on NO (%s -> %s)",
        tag, prompts, tostring(before), tostring(Choice.cursor)))
      U.still(game, DIR .. "/2450_" .. tag .. "_yesno_" .. prompts .. ".png")
      if evoOpen then
        U.tap(game, "down")
        U.wait(4)
        result(Choice.cursor == 2, string.format("%s yes/no #%d DOWN on NO stays on NO (%s)",
          tag, prompts, tostring(Choice.cursor)))
      end
      U.tap(game, "up")
      U.wait(4)
      result(Choice.cursor == 1, string.format("%s yes/no #%d UP lands on YES (%s)", tag, prompts, tostring(Choice.cursor)))
      U.tap(game, "a")
      U.wait(6)
      if prompts > 8 then result(false, "prompt loop") return finish() end
    elseif Anim.vm() and Anim.vm():busy() then
      U.wait(1)
    elseif f - lastTap >= 12 and not Choice.active and not SummaryMenu.isOpen()
        and not (Message.isOpen() and (Message.currentPage and Message.currentPage() or ""):find("Delete a move", 1, true)) then
      lastTap = f
      U.tap(game, "a")
    else
      U.wait(1)
    end
  end
  local mon = session.party[1]
  local moves = mon.moves or {}
  print("[d] final species=" .. tostring(Pokemon.speciesOf(mon)) .. " moves=" .. table.concat(moves, ","))
  result(sawEvoPrompt, "evolution learn prompt reached in battle")
  result(summaries == 2, "both forget-move summaries opened (" .. summaries .. ")")
  result(Pokemon.speciesOf(mon) == 20, "evolved into RATICATE")
  result(moves[4] == FOCUS_ENERGY, "level-up FOCUS ENERGY replaced slot 4")
  result(moves[2] == SCARY_FACE, "evolution SCARY FACE replaced slot 2")
  result(moves[1] == 33 and moves[3] == 98, "untouched slots kept")
  result(leaked == 0, "summary close press not replayed into the evolution scene (" .. leaked .. ")")
  finish()
end
