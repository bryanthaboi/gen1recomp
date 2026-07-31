-- Leaving a battle: the fade the way back to the map never had.
--
-- Going IN is a whole production -- one of the original's eight wipes, picked by
-- three bits, over a flash (src/render/BattleTransition.lua). Coming OUT was a
-- hard cut: BattleState:finish pops itself and the map is simply THERE on the
-- next frame. On the flat battle screen that is a cut between a white field and
-- a tile map, which the original got away with. In this mode it is a cut between
-- a placed camera looking across an arena and a diorama looking down on a
-- walking player, and a jump that big reads as a glitch rather than as an edit.
--
-- So the battle fades out, closes behind the black, and the map fades up out of
-- it. The timing is a transitions record this mod registers rather than a
-- constant in here, so it is retunable in data like the engine's own eight.
--
-- WHEN. Only while voxel mode is on: this is the diorama's own exit, and a
-- vanilla battle keeps the cut it always had. While the mode IS on, every battle
-- gets it -- including one that found no arena and drew on the flat battle
-- screen -- because what is being smoothed over is the return to the MAP, and
-- the map is a diorama either way.
--
-- HOW IT IS DRAWN, which is the part worth reading. Not by this state: it draws
-- nothing at all. It owns a NUMBER, and one black rectangle over the FINISHED
-- composite in a wrap around Renderer:endFrame paints it -- after the world
-- blit, after the letterbox, after the UI blit, which is the only point where a
-- single rect covers everything on screen at once.
--
-- The renderer's own fade (worldFadeAlpha, which the warp fade uses) is painted
-- BETWEEN the world and the UI, because a warp has no UI over it. A fade that
-- borrowed it would darken the arena and leave the battle's text box sitting
-- bright on top of the black -- and the letterbox bars of a flat battle screen,
-- painted by the renderer's clear before any state draws, would not darken at
-- all.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local BattleExit = {}
BattleExit.__index = BattleExit

-- The battle underneath keeps drawing while this is up -- what fades is its own
-- last live frame, camera drift, HUD and all. Only the top state UPDATES, so
-- nothing the battle does can outrun the fade either.
BattleExit.isOpaque = false

-- The registered record's id, and the fallback timing if it is missing (a
-- headless caller, or a total conversion that dropped the namespace). Per HALF,
-- matching the engine's warp fade, so the whole edit is 24 frames.
BattleExit.ID = "voxel_battle_exit"
BattleExit.FRAMES = 12

-- The fade in progress, or nil. Kept here rather than on the state so the
-- endFrame wrap has one place to look and nothing can go stale the frame after
-- the state leaves the stack.
local live = nil

-- How black the composite is this frame: 0 on the battle's last live frame, 1 at
-- the cut, 0 again once the map is up. nil when no fade is running, which is
-- every other frame the game ever draws.
function BattleExit.veil()
  if not live then return nil end
  -- A fade can be taken off the stack by something that is not the fade: a
  -- script or a shot driver popping down to the overworld, a state teardown.
  -- Then it is not running, whatever its counter says -- and a veil left behind
  -- would black the game out for good, because nothing is going to fade it back
  -- in. Checked here rather than trusted, because this is the one place the
  -- answer is used. The walk only happens while a fade is live.
  local stack = live.game and live.game.stack
  local states = stack and stack.states
  local onStack = false
  for i = #(states or {}), 1, -1 do
    if states[i] == live then onStack = true break end
  end
  if not onStack then live = nil; return nil end
  local a = live.t / live.frames
  if live.phase == "in" then a = 1 - a end
  return math.max(0, math.min(1, a))
end

local function framesFor(game)
  local records = game and game.data and game.data.transitions
  local record = records and records[BattleExit.ID]
  local frames = record and record.frames
  if type(frames) == "number" and frames > 0 then return frames end
  return BattleExit.FRAMES
end

function BattleExit.new(game, battle, onMidpoint)
  return setmetatable({ game = game, battle = battle, onMidpoint = onMidpoint,
                        frames = framesFor(game), t = 0, phase = "out" },
                      BattleExit)
end

-- Push the fade over the battle it is closing.
function BattleExit.start(battle, onMidpoint)
  local game = battle.game
  local self = BattleExit.new(game, battle, onMidpoint)
  live = self
  game.stack:push(self)
  return self
end

function BattleExit:update()
  self.t = self.t + 1
  if self.t < self.frames then return end
  self.t = 0

  if self.phase == "in" then
    live = nil
    self.game.stack:pop()
    return
  end

  -- ------- the cut, at full black
  --
  -- Off the stack FIRST. BattleState:finish pops whatever is on TOP, and while
  -- this fade is up that is the fade -- so a fade that stayed would eat the
  -- battle's own pop and leave the battle running underneath, finished but
  -- still on the stack. Popping ourselves hands the top back to the battle so
  -- its pop lands on itself.
  self.phase = "in"
  local stack = self.game.stack
  stack:pop()
  if self.onMidpoint then self.onMidpoint() end
  if stack:top() == self.game.overworld then
    stack:push(self)                       -- and the map comes up out of it
    return
  end

  -- We are not going back to the map after all. Either the battle did not
  -- actually leave -- finish() can be a false start, and wanted() mirrors the
  -- one the engine has today -- or something else took the screen on the way
  -- out: a blackout's own warp fade, an evolution prompt. Whatever it is owns
  -- the transition from here, so this one ends at the cut instead of fading in
  -- over the top of it. The flag goes back too, so a second finish() that does
  -- leave gets its own fade.
  live = nil
  if self.battle then self.battle.dramaticShapeLeaving = nil end
end

-- "Voxel mode is on", as the ENGINE answers it: switched on, not retired by a
-- fault, and runnable on this machine. A function on the table rather than an
-- inline call so a driver or a headless test can pin it -- the test harness has
-- no depth buffer, where the honest answer is no on every rung.
function BattleExit.modeOn()
  return require("src.render.Pipelines").eligible("voxel") and true or false
end

-- Whether this ending gets the fade.
function BattleExit.wanted(battle)
  local game = battle and battle.game
  if not (game and game.stack) then return false end
  -- finish() is not always the end: an unpaid PAY DAY prints its takings and
  -- comes back through here a moment later (BattleState:finish's first branch).
  -- Mirrored read-only, so the fade starts on the call that really leaves rather
  -- than fading to black and snapping back for one more message.
  if battle.payDay and battle.result == "win" then return false end
  return BattleExit.modeOn()
end

-- ------- engine seams
--
-- Two wraps, each idempotent so a hot reload cannot stack them.
function BattleExit.install()
  local BattleState = require("src.battle.BattleState")
  if not BattleState.dramaticShapeExitHook then
    local inner = BattleState.finish
    -- The one place a battle ends. Wrapped rather than listened for: the
    -- battle.ended event is emitted AFTER the pop, and by then the battle
    -- screen is gone and there is nothing left to fade out.
    function BattleState:finish()
      if self.dramaticShapeLeaving or not BattleExit.wanted(self) then
        return inner(self)
      end
      self.dramaticShapeLeaving = true
      BattleExit.start(self, function() inner(self) end)
    end
    BattleState.dramaticShapeExitHook = true
  end

  local Renderer = require("src.render.Renderer")
  if not Renderer.dramaticShapeExitHook then
    local inner = Renderer.endFrame
    function Renderer:endFrame(zones, worldZones)
      inner(self, zones, worldZones)
      local a = BattleExit.veil()
      if not a or a <= 0 then return end
      -- The composite is on the screen by now, in LOVE units, so one rect over
      -- the window darkens the world, the letterbox bars, the text box and
      -- anything a present pass put on top, all by the same amount. Left to
      -- last on purpose: this is a shutter closing on the finished frame, not a
      -- layer inside it.
      local w, h = love.graphics.getDimensions()
      love.graphics.setColor(0, 0, 0, a)
      love.graphics.rectangle("fill", 0, 0, w, h)
      love.graphics.setColor(1, 1, 1, 1)
    end
    Renderer.dramaticShapeExitHook = true
  end
end

return BattleExit
