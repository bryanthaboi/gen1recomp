-- Parity test: a ball thrown at the POKEMON_TOWER_6F RESTLESS SOUL is
-- always dodged, scope or no scope.
--
-- ItemUseBall reaches the $10 "can't be caught" anim data by TWO
-- independent routes (engine/items/item_effects.asm):
--
--   :149-153  callfar IsGhostBattle / ld b, $10 / jp z, .setAnimData
--   :166-175  .notOldManBattle -- wCurMap == POKEMON_TOWER_6F and
--             wEnemyMonSpecies2 == RESTLESS_SOUL -> the same $10
--
-- The port only had the first, as the scope-less disguise flag
-- self.ghost.  Once the SILPH_SCOPE revealed the MAROWAK the battle was
-- an ordinary wild one, so throwBall ran the capture roll and a MASTER
-- BALL caught it outright.  That result is "caught", not "win" or the
-- POKE DOLL escape, so PokemonTower6F's script never set
-- EVENT_BEAT_GHOST_MAROWAK and the (10,16) trigger re-fired forever
-- (#444).  The map+species half sits BEFORE .loop, hence before the
-- MASTER_BALL shortcut, so even a Master Ball is dodged.
--
-- Run-away parity is the other side of this: only IsGhostBattle grants
-- the free escape (engine/battle/core.asm TryRunningFromBattle), so a
-- revealed MAROWAK keeps normal flee rolls and self.ghost stays the sole
-- gate there.
--
-- Self-contained; run via `luajit tests/parity_marowak_ball.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity marowak ball")
local check, eq = S.check, S.eq

local BattleState = require("src.battle.BattleState")

-- ---- 1. the 6F script arms noCatch with and without the scope -----------
do
  local realTextBox = package.loaded["src.render.TextBox"]
  local realBattleState = package.loaded["src.battle.BattleState"]
  package.loaded["src.render.TextBox"] = {
    new = function(_, text, done) return { text = text, done = done } end,
  }
  local made = {}
  package.loaded["src.battle.BattleState"] = {
    newWild = function(_, species, level)
      local b = { species = species, level = level, ghost = false }
      b.makeGhost = function(self) self.ghost = true end
      made[#made + 1] = b
      return b
    end,
  }

  local tower = dofile("data/scripts/story3.lua").POKEMON_TOWER_6F
  local function trigger(inventory)
    local pushed = {}
    local game = {
      save = { inventory = inventory, flags = {} },
      data = { text = {} },
      stack = { push = function(_, box) pushed[#pushed + 1] = box end },
    }
    local ow = {
      player = {},
      scriptMove = function() end,
      afterBattle = function() end,
    }
    check(tower.onStep(game, ow, 10, 16), "the trigger fires on (10,16)")
    pushed[1].done()
    return made[#made]
  end

  local noScope = trigger({})
  check(noScope.ghost, "without the scope the battle is still disguised")
  check(noScope.noCatch, "and noCatch is set")

  local withScope = trigger({ SILPH_SCOPE = 1 })
  check(not withScope.ghost, "with the scope the disguise is gone")
  check(withScope.noCatch,
        "but noCatch survives it -- balls are dodged either way")

  package.loaded["src.render.TextBox"] = realTextBox
  package.loaded["src.battle.BattleState"] = realBattleState
end

-- ---- 2. throwBall takes the dodge branch on noCatch alone ---------------
local realSound = package.loaded["src.core.Sound"]
package.loaded["src.core.Sound"] = { play = function() end }

-- A real BattleState minus the pieces the decision does not touch: the
-- capture roll and the ball chain record that they were reached, which is
-- exactly the bug (a MASTER BALL catching the revealed MAROWAK).
local function throw(flags, ball)
  local self = setmetatable({
    kind = "wild",
    ghost = flags.ghost or false,
    noCatch = flags.noCatch or false,
    queue = {},
    rolled = false,
    chained = false,
    enemyMoved = false,
    turnEnded = false,
    data = { items = { MASTER_BALL = { name = "MASTER BALL" },
                       POKE_BALL = { name = "POKé BALL" } },
             text = {} },
    game = { save = { player = { name = "RED" } } },
    player = {},
    enemy = {},
  }, BattleState)
  self.ballDef = function() return nil end
  self.catchAttempt = function(s) s.rolled = true return false, 3 end
  self.ballChain = function(s) s.chained = true end
  self.enemyAction = function() return {} end
  self.executeAction = function(s) s.enemyMoved = true end
  self.endOfTurn = function(s) s.turnEnded = true end
  self:throwBall(ball)
  -- the whole outcome lives in the act() closure throwBall queues, and
  -- that closure queues more rows, so drain like updateQueue does: run
  -- each fn row once, with nextInsert pointing at it.
  local ran = {}
  local more = true
  while more do
    more = false
    for i, row in ipairs(self.queue) do
      if row.fn and not ran[row] then
        ran[row] = true
        self.nextInsert = i
        row.fn()
        more = true
        break
      end
    end
  end
  local texts = {}
  for _, row in ipairs(self.queue) do
    if row.text then texts[#texts + 1] = tostring(row.text) end
  end
  self.texts = table.concat(texts, "|")
  return self
end

local function assertDodge(b, label)
  check(not b.rolled, label .. ": no capture roll")
  check(not b.chained, label .. ": no wobble chain")
  check(b.texts:find("It dodged the", 1, true) ~= nil,
        label .. ": ItemUseBallText00 line 1")
  check(b.texts:find("can't be caught", 1, true) ~= nil,
        label .. ": ItemUseBallText00 line 2")
  check(b.enemyMoved, label .. ": the turn is spent, the foe moves")
  check(b.turnEnded, label .. ": and the turn ends")
end

assertDodge(throw({ ghost = true }, "POKE_BALL"), "IsGhostBattle exit")
assertDodge(throw({ noCatch = true }, "POKE_BALL"), ".notOldManBattle exit")
-- the regression itself: revealed by the scope, so ghost is false
assertDodge(throw({ noCatch = true }, "MASTER_BALL"), "MASTER BALL")

do
  local plain = throw({}, "MASTER_BALL")
  check(plain.rolled,
        "an ordinary wild mon still rolls -- the guard is not global")
end

-- The dodged toss keeps the arc the thrown ball picked (TossBallAnimation
-- reads wCurItem), so the Master Ball flicker is not lost.
do
  local b = throw({ noCatch = true }, "MASTER_BALL")
  local anim
  for _, row in ipairs(b.queue) do
    if row.anim then anim = row.anim break end
  end
  eq("ULTRATOSS_ANIM", anim, "a dodged MASTER BALL still tosses as ULTRATOSS")
end

package.loaded["src.core.Sound"] = realSound

-- ---- 3. noCatch grants no free escape ----------------------------------
do
  local function roll(flags)
    local b = { ghost = flags.ghost or false, noCatch = flags.noCatch or false,
                runAttempts = 1, rng = function() return 255 end }
    return BattleState.runRollVanilla(b, 10, 100)
  end
  check(roll({ ghost = true }), "IsGhostBattle still always escapes")
  check(not roll({ noCatch = true }),
        "a revealed MAROWAK takes the normal flee roll")
end

S.finish()
