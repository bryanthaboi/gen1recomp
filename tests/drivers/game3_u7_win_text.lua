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
  end

  U.wait(30)
  game:_handleBootAction({ action = "new_game", name = "RED", rivalName = "BLUE", gender = 0 })
  U.wait(120)
  local Runtime = require("src.core.game3.runtime")
  local session = Runtime.getSession()
  local Party = require("src.core.game3.party")
  session.party = {}
  Party.giveMon(session, 6, 60)
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Ui = require("src.core.game3.battle.ui")
  local Anim = require("src.core.game3.battle.anim")

  local function onScreen()
    if not Ui._showing then return "" end
    local log = Ui.log() or {}
    return log[#log - #(Ui._queue or {})] or ""
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
      if f % 20 == 0 then U.tap(game, "a") end
    end
    return false
  end
  local function trainerSprite()
    local ok, s = pcall(Anim.stage)
    local t = ok and s and s.trainer and s.trainer.enemy
    return t and t.visible, t and t.ox
  end

  local ok = BattleBridge.startWild(Runtime._mod, game, { species = 16, level = 2 }, {})
  check(ok, "u7 wild battle started")
  local sawExp = advanceUntil(function() return onScreen():find("EXP. Points", 1, true) ~= nil end, 3000)
  check(sawExp, "u7 wild EXP line reached")
  if sawExp then
    check(#(Ui._queue or {}) == 0, "u7 wild EXP line is the last queued text")
    U.wait(150)
    U.shot(game, DIR .. "/u7_01_wild_exp_is_last_text.png")
  end
  local sawWon = false
  local ended = advanceUntil(function()
    if anyLine("won the battle") then sawWon = true end
    return not Battle.isActive()
  end, 3000)
  check(ended, "u7 wild battle ended")
  check(not sawWon, "u7 wild win shows no 'You won the battle!'")
  U.wait(90)
  U.shot(game, DIR .. "/u7_02_wild_back_on_overworld.png")

  U.wait(30)
  ok = BattleBridge.start(Runtime._mod, game, { species = 7, level = 5, trainerId = 326 }, { trainerId = 326 })
  check(ok, "u7 trainer battle started")
  local sawDefeated = advanceUntil(function() return onScreen():find("defeated\n", 1, true) ~= nil end, 4000)
  check(sawDefeated, "u7 trainer defeated line reached")
  local sawLose
  if sawDefeated then
    check(not anyLine("wrong"), "u7 defeated line printed before lose text")
    local vis, ox = trainerSprite()
    check(not (vis and ox == 0), "u7 trainer not slid in while defeated line shows")
    U.wait(150)
    U.shot(game, DIR .. "/u7_03_trainer_defeated_before_slide_in.png")
    sawLose = advanceUntil(function() return onScreen():find("wrong", 1, true) ~= nil end, 2000)
    check(sawLose, "u7 trainer lose text follows defeated line")
    if sawLose then
      U.wait(150)
      local vis2, ox2 = trainerSprite()
      check(vis2 and ox2 == 0, "u7 trainer slid in for lose text")
      U.shot(game, DIR .. "/u7_04_trainer_lose_text_after_slide_in.png")
    end
  end
  local tEnded = advanceUntil(function() return not Battle.isActive() end, 3000)
  check(tEnded, "u7 trainer battle ended")

  for i, t in ipairs(Ui.log() or {}) do print("U7 LOG", i, (t:gsub("\n", " / "))) end
  if fails == 0 then
    print("PASS u7 win text")
    love.event.quit(0)
  else
    print("FAIL u7 win text")
    love.event.quit(1)
  end
end
