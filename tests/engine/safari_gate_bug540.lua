-- Regression coverage for #540 "Safari Zone: wrong start tile / step count,
-- black leaving-early dialogue, wrong early-leave tile" (T2, ROM-free).
--
-- pret/pokered scripts/SafariZoneGate.asm:
--   .success (186-198) ends `ld a, PAD_UP / ld c, 3 /
--   SafariZoneEntranceAutoWalk`, so paying walks the player up through the
--   gate's north warp instead of leaving him at the counter.  Two of those
--   steps happen with EVENT_IN_SAFARI_ZONE already set, and home/overworld.asm
--   :307-310 charges every step against wSafariSteps, which is why the game
--   starts at 502 but reads 500/500 on arrival.  The port only counts steps on
--   the nine interior maps, so the script pays those two itself.
--   SafariZoneGateSafariZoneWorker1LeavingEarlyText (227-254): YES prints the
--   return-balls text and auto-walks `PAD_DOWN, c = 3` down to the counter row,
--   NO prints "Good Luck!" and walks back up through the warp.
--
-- The leaving-early prompt must be QUEUED, never pushed: onEnter runs at the
-- arriving warp Transition's midpoint and Transition:finish pops the top state
-- on the same frame, so a box pushed there is swallowed (or, on an older
-- build, drawn over a screen still faded to black).

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local MapScripts = require("src.script.MapScripts")
local ScriptRunner = require("src.script.ScriptRunner")

-- ---- stubs for the two UI modules safari.lua requires lazily.  A pushed
-- box runs its continuation immediately, so a whole prompt chain resolves
-- inside the push that started it.

local answer = true
package.loaded["src.render.TextBox"] = {
  new = function(_, text, done) return { text = text, done = done } end,
}
package.loaded["src.ui.ChoiceBox"] = {
  new = function(_, cb) return { done = function() cb(answer) end } end,
}

local contribution = dofile("data/scripts/safari.lua")
local gate = contribution.SAFARI_ZONE_GATE
T.check(gate ~= nil, "the contribution still carries SAFARI_ZONE_GATE")

local problems = MapScripts.validateContribution(gate)
T.eq(#problems, 0, "safari contribution validates cleanly")
for _, p in ipairs(problems) do T.check(false, "unexpected finding: " .. p) end

-- ---- a minimal game/overworld pair

local NORTH_WARP = { x = 4, y = 0, destMap = "SAFARI_ZONE_CENTER", destWarp = 2 }

local function newWorld(cellX, cellY)
  local w = {
    pushed = {}, moves = {}, warps = {}, queued = {},
    player = { cellX = cellX, cellY = cellY },
  }
  w.map = {
    id = "SAFARI_ZONE_GATE",
    warpAtCell = function(_, cx, cy)
      if cy == 0 and (cx == 3 or cx == 4) then
        return { index = cx == 3 and 3 or 4, def = NORTH_WARP }
      end
    end,
  }
  w.scriptMove = function(_, entity, dir, tiles, onDone)
    w.moves[#w.moves + 1] = { entity = entity, dir = dir, tiles = tiles,
                              onDone = onDone }
  end
  w.takeWarp = function(_, def) w.warps[#w.warps + 1] = def end
  w.startWarpTo = function(_, mapId, x, y, facing)
    w.warps[#w.warps + 1] = { startWarpTo = mapId, x = x, y = y,
                              facing = facing }
  end
  w.queueScript = function(_, rows) w.queued[#w.queued + 1] = rows end
  return w
end

local function newGame(world, money)
  local game = {
    data = {
      text = {},
      maps = { SAFARI_ZONE_CENTER = {
        warps = { { x = 14, y = 25 }, { x = 15, y = 25 } } } },
    },
    save = { player = { name = "RED" }, money = money or 3000 },
  }
  game.stack = { push = function(_, state)
    world.pushed[#world.pushed + 1] = state
    if state.done then state.done() end
  end }
  return game
end

-- ---- paying walks into the zone and pays the two gate steps

answer = true
local ow = newWorld(4, 2)
local game = newGame(ow)
T.eq(gate.onStep(game, ow, 4, 2), true, "the trigger cell claims the step")
T.check(game.save.safari ~= nil, "paying starts the game")
T.eq(game.save.safari.steps, 502, "wSafariSteps is written as 502")
T.eq(game.save.safari.balls, 30, "SAFARI_BALLS_RECEIVED is 30")
T.eq(game.save.money, 2500, "the ¥500 fee is taken")

T.eq(#ow.moves, 1, "the payment text is followed by the entrance auto-walk")
T.eq(ow.moves[1].dir, "up", "SafariZoneEntranceAutoWalk walks PAD_UP")
T.eq(ow.moves[1].tiles, 2, "two cells reach the north warp row")
T.eq(#ow.warps, 0, "the warp is not taken until the walk lands on it")
ow.moves[1].onDone()
T.eq(game.save.safari.steps, 500,
  "the two gate steps are charged, so the counter reads 500/500 on arrival")
T.eq(ow.warps[1], NORTH_WARP,
  "a scripted step skips CheckWarpsNoCollision, so the script takes the warp")

-- talking to the worker from anywhere else has no warp above the player, so
-- the auto-walk stays out of the way and he walks in himself
answer = true
local far = newWorld(2, 4)
local farGame = newGame(far)
farGame.save.safari = nil
gate.talk.TEXT_SAFARIZONEGATE_SAFARI_ZONE_WORKER1(farGame, far, nil, nil)
T.check(farGame.save.safari ~= nil, "the talk path still starts the game")
T.eq(#far.moves, 0, "no auto-walk from a cell with no warp above it")

-- declining walks the player back off the trigger cell, unchanged
answer = false
local no = newWorld(4, 2)
local noGame = newGame(no)
gate.onStep(noGame, no, 4, 2)
T.eq(noGame.save.safari, nil, "declining starts no game")
T.eq(no.moves[1] and no.moves[1].dir, "down", "declining walks you back down")

-- ---- leaving early: queued, never pushed

local back = newWorld(4, 0)
local backGame = newGame(back)
backGame.save.safari = { balls = 7, steps = 300 }
gate.onEnter(backGame, back)
T.eq(#back.pushed, 0,
  "onEnter pushes nothing: the arriving Transition pops the top state on the "
  .. "same frame")
T.eq(#back.queued, 1, "the leaving-early prompt is queued for an idle frame")

local rows = back.queued[1]
T.eq(#ScriptRunner.validate(rows), 0, "the queued rows validate")

local function runRows(script, yes)
  local pc, texts, out = 1, {}, { fields = {}, moves = {}, warps = {} }
  local lastCheck = nil
  while pc <= #script do
    local row = script[pc]
    local verb = row[1]
    local jump = nil
    if verb == "ask" then
      texts[#texts + 1] = row[2]
      lastCheck = yes
    elseif verb == "show_text" then
      texts[#texts + 1] = row[2]
    elseif verb == "jump_if_false" then
      if not lastCheck then jump = row[2] end
    elseif verb == "jump" then
      jump = row[2]
    elseif verb == "set_field" then
      out.fields[#out.fields + 1] = { key = row[2], value = row[3] }
    elseif verb == "move_player" then
      out.moves[#out.moves + 1] = { dir = row[2], tiles = row[3] }
    elseif verb == "warp" then
      out.warps[#out.warps + 1] = { map = row[2], x = row[3], y = row[4],
                                    facing = row[5] }
    end
    if jump == "end" then break end
    if jump then
      local target
      for i, r in ipairs(script) do
        if r[1] == "label" and r[2] == jump then target = i break end
      end
      T.check(target ~= nil, "jump target '" .. tostring(jump) .. "' exists")
      pc = target
    else
      pc = pc + 1
    end
  end
  out.texts = texts
  return out
end

local yes = runRows(rows, true)
T.eq(yes.texts[1], "_SafariZoneGateSafariZoneWorker1LeavingEarlyText",
  "the worker asks first")
T.eq(yes.texts[2], "_SafariZoneGateSafariZoneWorker1ReturnSafariBallsText",
  "YES takes the leftover balls back")
T.eq(yes.texts[3], "_SafariZoneGateSafariZoneWorker1GoodHaulComeAgainText",
  "the good-haul sign-off stays reachable on this branch")
T.eq(#yes.fields, 1, "the game state is cleared once")
T.eq(yes.fields[1].key, "safari", "save.safari is the field cleared")
T.eq(yes.fields[1].value, nil, "set_field with no value assigns nil")
T.eq(#yes.moves, 1, "YES ends with the exit auto-walk")
T.eq(yes.moves[1].dir, "down", "SafariZoneEntranceAutoWalk walks PAD_DOWN")
T.eq(yes.moves[1].tiles, 3, "three cells reach the counter row")
T.eq(#yes.warps, 0, "the YES branch never warps back into the zone")

local stay = runRows(rows, false)
T.eq(stay.texts[2], "_SafariZoneGateSafariZoneWorker1GoodLuckText",
  "NO wishes you good luck")
T.eq(#stay.moves, 0, "NO does not walk you to the counter")
T.eq(#stay.warps, 1, "NO puts you back in the zone")
T.eq(stay.warps[1].map, "SAFARI_ZONE_CENTER", "back through the entrance")
T.eq(stay.warps[1].x, 15, "the right-hand warp column comes back on column 15")
T.eq(stay.warps[1].y, 25, "the entrance row of SAFARI_ZONE_CENTER")

-- the left-hand column pairs with the left-hand destination warp
local left = newWorld(3, 0)
local leftGame = newGame(left)
leftGame.save.safari = { balls = 7, steps = 300 }
gate.onEnter(leftGame, left)
local leftStay = runRows(left.queued[1], false)
T.eq(leftStay.warps[1].x, 14, "the left-hand warp column comes back on 14")

-- no game running, or arriving from the town side, asks nothing
local idle = newWorld(4, 0)
local idleGame = newGame(idle)
gate.onEnter(idleGame, idle)
T.eq(#idle.queued, 0, "no safari game, no prompt")

local south = newWorld(4, 5)
local southGame = newGame(south)
southGame.save.safari = { balls = 7, steps = 300 }
gate.onEnter(southGame, south)
T.eq(#south.queued, 0, "arriving from Fuchsia asks nothing")

package.loaded["src.render.TextBox"] = nil
package.loaded["src.ui.ChoiceBox"] = nil

T.finish("safari_gate_bug540")
