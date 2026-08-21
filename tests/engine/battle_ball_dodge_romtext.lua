-- BattleState:throwBall()'s can't-be-caught path used to queue two
-- separate Strings() literals ("It dodged the\nthrown BALL!" then "This
-- POKéMON\ncan't be caught!"). The real ROM label _ItemUseBallText00
-- combines both as one \f-paged string. TextBox.new() would split \f
-- itself, but throwBall() queues through self:sayNext(), which goes
-- through the battle queue's own BattleState:startMessage() -- and that
-- one only splits on \n/\v, not \f (confirmed live: the \f landed
-- mid-line and the second sentence overflowed off the box instead of
-- starting a fresh page). The fix resolves the label once, then splits
-- it the same way TextBox.lua does and queues one sayNext per page. This
-- test fakes the label and checks the two pages reach the queue as two
-- separate messages, in order, not merged into one with a raw \f still
-- inside it.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)

local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")

local function mkbattle()
  local save = SaveData.newGame()
  save.party = { Pokemon.new(Data, "FIXMON_A", 10) }
  local game = { data = Data, save = save,
                 stack = { top = function() return nil end, push = function() end } }
  local battle = BattleState.newWild(game, "FIXMON_C", 8)
  battle.ghost = true -- forces the can't-be-caught path
  return battle
end

-- throwBall defers its message-queuing work into self.queue via one
-- top-level self:act(fn); run only that one function to reach the
-- say() calls the fix touches. It's the last entry throwBall itself
-- appends (after the immediate sayAuto), and it further queues its own
-- self:act(function() self:executeAction(...) end) for the actual enemy
-- turn -- deliberately NOT run here (out of scope, and running the queue
-- generically after mutation risks looping into a real turn simulation)
local function runThrowBallAct(battle)
  for i = #battle.queue, 1, -1 do
    if battle.queue[i].fn then
      battle.queue[i].fn()
      return
    end
  end
end

local function textEntries(battle)
  local out = {}
  for _, entry in ipairs(battle.queue) do
    if entry.text then out[#out + 1] = entry.text end
  end
  return out
end

-- translated: the faked label's two \f-separated pages reach the queue
-- as two separate messages, in order, and neither one still contains a
-- raw \f (which would mean the battle queue's own renderer has to deal
-- with it, and it can't)
do
  local battle = mkbattle()
  Data.text._ItemUseBallText00 = "FAKE-DODGE!\fFAKE-CANTCATCH!"
  battle:throwBall("FIX_BALL")
  runThrowBallAct(battle)
  local texts = textEntries(battle)
  T.eq(texts[1], "FAKE-DODGE!", "page 1 reaches the queue on its own")
  T.eq(texts[2], "FAKE-CANTCATCH!", "page 2 follows right after, still in order")
  for _, t in ipairs(texts) do
    T.check(not t:find("\f", 1, true), "no queued message still carries a raw \\f")
  end
  Data.text._ItemUseBallText00 = nil
end

-- vanilla: no catalog entry still falls back to the two English pages,
-- split the same way
do
  local battle = mkbattle()
  battle:throwBall("FIX_BALL")
  runThrowBallAct(battle)
  local texts = textEntries(battle)
  T.eq(texts[1], "It dodged the\nthrown BALL!", "vanilla page 1")
  T.eq(texts[2], "This POKéMON\ncan't be caught!", "vanilla page 2")
end

T.finish("battle_ball_dodge_romtext")
