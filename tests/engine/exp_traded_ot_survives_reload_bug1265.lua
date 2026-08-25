-- engine/battle/experience.asm:69

package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.harness")
local BattleState = require("src.battle.BattleState")

local function newSave()
  return { player = { id = 12345, name = "RED" } }
end

do
  local save = newSave()
  local homegrown = {}
  BattleState.stampOT(save, homegrown)
  T.eq(homegrown.otId, 12345, "a home-grown mon is still stamped with the player id")
  T.eq(homegrown.ot, "RED", "and the player's own name")
end

-- The bug: a mon that arrived traded (traded = true) but whose OT id was
-- never recorded (a legacy peer, a link mon with no otId in its packet) used
-- to get save.player.id written into otId on the very first load, which then
-- reads identically to a mon the player caught -- awardExp's OT-id compare
-- (BattleState.lua ~4009) permanently loses the 1.5x boost.
do
  local save = newSave()
  local tradedNoId = { traded = true }
  BattleState.stampOT(save, tradedNoId)
  T.eq(tradedNoId.otId, nil,
    "a traded mon with no OT id is left unstamped, not silently adopted")
  T.eq(tradedNoId.ot, "RED",
    "the OT NAME fill still happens (cosmetic, not the boost gate)")
  -- a second stampOT pass (a second save/load cycle) must not adopt it either
  BattleState.stampOT(save, tradedNoId)
  T.eq(tradedNoId.otId, nil, "repeated reloads do not eventually stamp it")
end

-- A mon with its own foreign OT id (the ordinary traded-in case) is untouched
-- either way; this is the arm the regression never broke.
do
  local save = newSave()
  local tradedWithId = { traded = true, otId = 777 }
  BattleState.stampOT(save, tradedWithId)
  T.eq(tradedWithId.otId, 777, "a recorded foreign OT id is never overwritten")
end

-- #1461: saves that passed through 0.1.82-0.1.9x already have the player's
-- own id written onto traded mons, so stamping correctly from now on does
-- not help them.  The repair is a one-shot pre-format-5 migration.
do
  local SaveData = require("src.core.SaveData")
  local save = newSave()
  local poisoned = { traded = true, otId = 12345 }
  local foreign = { traded = true, otId = 777 }
  local caught = { otId = 12345 }
  save.party = { poisoned, foreign, caught }
  save.boxes = { { { traded = true, otId = 12345 } } }

  T.eq(SaveData.repairTradedOtIds(save), 2, "both poisoned mons are repaired")
  T.eq(poisoned.otId, nil, "a traded mon carrying the player id is cleared")
  T.eq(save.boxes[1][1].otId, nil, "boxed mons are repaired too")
  T.eq(foreign.otId, 777, "a real foreign OT id is left alone")
  T.eq(caught.otId, 12345, "a caught mon keeps the player id")
  T.eq(caught.traded, nil, "and is never marked traded")

  T.eq(SaveData.repairTradedOtIds(save), 0, "the repair is idempotent")

  -- and after the repair the stamp loop must not re-adopt it
  BattleState.stampOT(save, poisoned)
  T.eq(poisoned.otId, nil, "the stamp loop does not undo the repair")
end

T.finish("exp traded ot survives reload bug 1265")
