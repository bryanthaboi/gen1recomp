-- #2324: the level-up stat window gates the EXP sequence; it is never run past.
--
-- pokefirered draws the lvlup box from Cmd_drawlvlupbox and then *waits* for the
-- player (battle_script_commands.c: Cmd_drawlvlupbox ends the command, the
-- controller only returns after LvlUpBoxInput sees A/B).  The FRLG rewrite
-- opened the box and kept pumping, so the box outlived its own step: it could
-- no longer be dismissed (input routing is phase-gated) and sat on screen over
-- the win/money text.
--
--   luajit tests/engine/battle_levelup_statwindow_bug2324.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local check, eq = T.check, T.eq

local Experience = require("src.core.game3.battle.experience")
local ExpSeq = require("src.core.game3.battle.exp_seq")
local StatGrowth = require("src.ui.game3.stat_growth")
local Ui = require("src.core.game3.battle.ui")
local Anim = require("src.core.game3.battle.anim")
local Battle = require("src.core.game3.battle.init")

local A_PRESS = { wasPressed = function(_, key) return key == "a" end }
local NO_PRESS = { wasPressed = function() return false end }

-- A mon one award away from a level, so the sequence always grows stats.
local function levelUpMon()
  return {
    species = 1,
    level = 5,
    hp = 20,
    maxHp = 20,
    attack = 10,
    defense = 10,
    spAtk = 12,
    spDef = 12,
    speed = 9,
    exp = Experience.expForLevel(3, 5),
    growthRate = 3,
  }
end

--- Runs the sequence up to the point the stat window opens.
--- Returns the pushMsg log and the ExpSeq step index at that moment.
local function pumpToStatWindow()
  local mon = levelUpMon()
  local res = Experience.apply(mon, 100)
  local messages = {}
  local awards = { { mon = mon, result = res, partyIndex = 1 } }

  Ui.reset({ headless = false })
  check(ExpSeq.begin(awards, function(t) messages[#messages + 1] = t end, nil,
    { headless = false }), "the level-up award starts an EXP sequence")

  -- exp-gain text, then the bar, then the grew-to-LV text
  for _ = 1, 4 do
    ExpSeq.update()
    Ui._showing = false
    Ui._queue = {}
    Anim.reset({ headless = false })
  end

  check(StatGrowth.isOpen(), "the stat window opened on level up")
  eq(StatGrowth._page, 1, "the stat window starts on Page 1 (diffs)")
  return messages, ExpSeq._i, mon, res
end

do
  local messages, stepBefore = pumpToStatWindow()
  local msgsBefore = #messages

  -- The box waits for the player: idle pumps must not move the sequence.
  for i = 1, 20 do
    eq(ExpSeq.update(), false, "pump " .. i .. " reports busy while the box is open")
  end
  eq(ExpSeq._i, stepBefore, "idle pumps did not advance the sequence")
  eq(#messages, msgsBefore, "idle pumps pushed no further battle text")
  check(StatGrowth.isOpen(), "the box is still open after 20 idle pumps")
  eq(StatGrowth._page, 1, "the box is still on Page 1 after 20 idle pumps")

  -- Page 2 is still a wait.
  check(StatGrowth.handleInput(A_PRESS), "A consumed on Page 1")
  eq(StatGrowth._page, 2, "the box flipped to Page 2 (new values)")
  check(StatGrowth.isOpen(), "the box is still open on Page 2")
  for _ = 1, 20 do
    eq(ExpSeq.update(), false, "pump reports busy while Page 2 is open")
  end
  eq(ExpSeq._i, stepBefore, "Page 2 idle pumps did not advance the sequence")
  eq(#messages, msgsBefore, "Page 2 idle pumps pushed no further battle text")

  -- The second A press is what releases the sequence.
  check(StatGrowth.handleInput(A_PRESS), "A consumed on Page 2")
  check(not StatGrowth.isOpen(), "the second A press closed the box")
  eq(ExpSeq._i, stepBefore + 1, "the sequence advanced only once the box closed")

  -- And it can be driven to the end from there without the box coming back.
  local guard = 0
  while not ExpSeq.update() and guard < 200 do
    guard = guard + 1
    Ui._showing = false
    Ui._queue = {}
    Anim.reset({ headless = false })
  end
  check(guard < 200, "the sequence finishes after the box is dismissed")
  check(not StatGrowth.isOpen(), "no stat window survives the finished sequence")
  check(ExpSeq.busy() == false, "ExpSeq.busy() is false once the sequence is done")
end

do
  -- A box whose phase can no longer dismiss it must not linger: input routing is
  -- phase-gated, so a box left open outside those phases would be undismissable
  -- and would draw over the win/money text.
  local _, _, mon, res = pumpToStatWindow()

  local savedActive, savedPhase, savedHeadless = Battle._active, Battle._phase, Battle._headless
  Battle._active, Battle._phase, Battle._headless = true, nil, true
  StatGrowth.open(mon, res.steps[1].oldStats, res.steps[1].newStats, function()
    error("a torn-down stat window must not fire its onDone callback")
  end)
  check(StatGrowth.isOpen(), "a stale box is open before Battle.update")
  Battle.update(1 / 60, { input = NO_PRESS })
  check(not StatGrowth.isOpen(), "Battle.update tears down a box outside its phases")
  Battle._active, Battle._phase, Battle._headless = savedActive, savedPhase, savedHeadless
end

T.finish("battle_levelup_statwindow_bug2324")
