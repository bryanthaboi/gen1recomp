-- Screen fade used for warps: fade out, run a callback (map switch), fade in.
-- Pushed on the state stack above the overworld.

local Timing = require("src.core.Timing")

local Transition = {}
Transition.__index = Transition

-- PlayMapChangeSound tail-calls GBFadeOutToBlack on every map change
-- (home/overworld.asm:703), which is four palette steps of DelayFrames 8 --
-- 32 frames.  There is no matching fade in: the new map is built while the
-- palettes are still blacked out and OverworldLoop's LoadGBPal
-- (home/overworld.asm:45) restores them in a single write, so the map pops
-- in.  The old symmetric 12/12 fade was both too fast and a shape the
-- hardware never had.
local FRAMES = Timing.WARP_FADE_OUT
local FRAMES_IN = Timing.WARP_FADE_IN
local FLASH_FRAMES = 7

-- Every fade in home/fade.asm holds each palette write with
-- `ld c, 8 / call DelayFrames`, so eight frames is the step of all of them.
local FADE_STEP_FRAMES = 8

-- Veil alpha `t` frames into a `len`-frame fade out.  GBFadeOutToBlack
-- (home/fade.asm:43-46) walks FadePal4 -> FadePal3 -> FadePal2 -> FadePal1
-- with b = 4, and FadePal4 IS the normal palette while FadePal1 is solid
-- black (:64-67) -- so the screen sits untouched through the first eight
-- frames and then drops a whole shade per step, reaching black for the last
-- hold.  The port tweened the veil instead, which reads as a dissolve rather
-- than a Game Boy fade (#607).  A record retimed shorter than two steps
-- (mods) keeps the old ramp so it still reaches black.
local function fadeAlpha(t, len)
  if not len or len <= 0 then return 1 end
  local steps = math.floor(len / FADE_STEP_FRAMES)
  if steps < 2 then return t / len end
  local step = math.min(steps - 1, math.floor(t / (len / steps)))
  return step / (steps - 1)
end

-- The two fades as transitions records, so a mod retimes a warp fade the
-- same way it retimes a battle wipe.  BattleTransition.registerInto pulls
-- these in with its eight wipes -- one registrant owns the registry.
Transition.STYLES = {
  warp_fade = { kind = "fade", frames = FRAMES, framesIn = FRAMES_IN },
  white_flash = { kind = "fade", frames = FLASH_FRAMES },
}

function Transition.registerInto(registry, _, owner)
  for id, record in pairs(Transition.STYLES) do
    registry:register(id, record, owner)
  end
end

-- the merged record, falling back to the built-in when no data is around
-- (headless callers, and any state built before Data:load)
local function styleOf(game, id)
  local data = game and game.data
  local record = data and data.transitions and data.transitions[id]
  return record or Transition.STYLES[id]
end

-- `warp` marks the map-change fade: PlayMapChangeSound's GBFadeOutToBlack
-- has no matching fade in (LoadGBPal restores the palettes in one write), so
-- warps land with framesIn 0.  Script fades that bracket a HideObject
-- (ViridianGym.asm .afterBeat, RocketHideoutB4F BeatGiovanniScript) call
-- GBFadeOutToBlack -> GBFadeInFromBlack instead, so the default keeps the
-- symmetric 32-frame fade back in (home/fade.asm:21, b = 4).
function Transition.new(game, onMidpoint, onDone, warp)
  local self = setmetatable({}, Transition)
  self.game = game
  self.onMidpoint = onMidpoint
  self.onDone = onDone
  self.t = 0
  self.phase = "out"
  local style = styleOf(game, "warp_fade")
  self.frames = style.frames or FRAMES
  if warp then
    -- a style may still ask for a fade in (mods, and the record is
    -- data-driven); the built-in warp is 0, matching hardware
    self.framesIn = style.framesIn or FRAMES_IN
  else
    self.framesIn = Timing.FADE_IN_FROM_BLACK
  end
  return self
end

function Transition:finish()
  if self.done then return end
  self.done = true
  if not self.offStack then self.game.stack:pop() end
  if self.onDone then self.onDone() end
end

function Transition:update(dt)
  self.t = self.t + 1
  local len = (self.phase == "out") and self.frames or self.framesIn
  if self.t >= len then
    self.t = 0
    if self.phase == "out" then
      self.phase = "in"
      -- LoadGBPal restores the palettes in one write, so with no fade in the
      -- map is simply there on the next frame
      if (self.framesIn or 0) <= 0 then
        self.offStack = true
        self.game.stack:pop()
        if self.onMidpoint then self.onMidpoint() end
        self:finish()
      elseif self.onMidpoint then
        self.onMidpoint()
      end
    else
      self:finish()
    end
  end
end

-- The veil alpha for this frame, exposed the way BattleReturn:alpha is so
-- the staircase can be asserted without stubbing love.graphics.
function Transition:alpha()
  local len = (self.phase == "out") and self.frames or self.framesIn
  local a = fadeAlpha(self.t, len)
  if self.phase == "in" then a = 1 - a end
  return a
end

function Transition:draw()
  local alpha = self:alpha()
  -- Survey zoom draws the overworld into a window-filling world canvas
  -- while the UI pass stays the classic 160x144 letterbox.  A rect on the
  -- UI canvas only darkens that center box (issue #121); when the world
  -- pass ran this frame, hand the alpha to Renderer:endFrame so it paints
  -- a screen-space overlay over the full composite instead.
  local r = self.game and self.game.renderer
  if r and r.worldActive then
    r.worldFadeAlpha = alpha
    return
  end
  love.graphics.setColor(0, 0, 0, alpha)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  love.graphics.setColor(1, 1, 1, 1)
end

-- GBPalWhiteOutWithDelay3 (home/palettes.asm): the field moves that close
-- the party menu (start_sub_menus.asm .goBackToMap paths) white out the
-- palettes, and they stay white through Delay3 + the screen-tile restore
-- until CloseTextDisplay's LoadGBPal -- a ~7-frame solid-white blink.
-- Instant white, hold, instant restore (a palette write, not a fade).
local WhiteFlash = {}
WhiteFlash.__index = WhiteFlash
WhiteFlash.isOpaque = true

function Transition.whiteFlash(game, frames, onDone)
  return setmetatable({ game = game,
                        frames = frames or styleOf(game, "white_flash").frames
                                 or FLASH_FRAMES,
                        onDone = onDone, t = 0 }, WhiteFlash)
end

function WhiteFlash:update(dt)
  self.t = self.t + 1
  if self.t >= self.frames then
    self.game.stack:pop()
    if self.onDone then self.onDone() end
  end
end

function WhiteFlash:draw()
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
end

-- Coming back to the overworld after a battle.
--
-- The battle screen is torn down with the palettes still whited out, the
-- caller spends `ld c, 10 / call DelayFrames` (home/overworld.asm:351-352),
-- and then EnterMap sees BIT_BATTLE_OVER_OR_BLACKOUT set and runs
-- MapEntryAfterBattle (:22, :749-753), which is GBFadeInFromWhite -- three
-- palette steps of DelayFrames 8, so 24 frames.  The port had none of it and
-- simply cut from the battle to the map.
--
-- A dark map takes the other branch: wMapPalOffset is nonzero there, so
-- MapEntryAfterBattle does a plain LoadGBPal and the map is just there.  Pass
-- opts.instant for that case.
local BattleReturn = {}
BattleReturn.__index = BattleReturn
BattleReturn.isOpaque = false -- the overworld draws underneath

function Transition.battleReturn(game, onDone, opts)
  opts = opts or {}
  return setmetatable({
    game = game, onDone = onDone, t = 0,
    hold = opts.hold or Timing.POST_BATTLE_RETURN,
    frames = opts.instant and 0 or (opts.frames or Timing.FADE_IN_FROM_WHITE),
  }, BattleReturn)
end

function BattleReturn:update(dt)
  self.t = self.t + 1
  if self.t >= self.hold + self.frames then
    self.game.stack:pop()
    if self.onDone then self.onDone() end
  end
end

-- GBFadeInFromWhite is a palette staircase, not a smooth ramp: GBFadeIncCommon
-- writes one palette then holds it with `ld c, 8 / call DelayFrames`
-- (home/fade.asm:30-41), three times over.  Stepping the veil the same way
-- keeps the fade reading like a Game Boy palette fade rather than a tween.
-- The hold is the same eight frames the warp fade steps on, so both share
-- FADE_STEP_FRAMES at the top of the file.

function BattleReturn:alpha()
  if self.t < self.hold then return 1 end
  if self.frames <= 0 then return 0 end
  local steps = math.max(1, math.floor(self.frames / FADE_STEP_FRAMES))
  local step = math.floor((self.t - self.hold) / FADE_STEP_FRAMES)
  if step >= steps then return 0 end
  return (steps - step - 1) / steps
end

function BattleReturn:draw()
  local a = self:alpha()
  -- the fade is a palette write, so it covers the whole surface; the
  -- renderer paints it in screen space (see Renderer.screenVeil)
  local r = self.game and self.game.renderer
  if r then
    r.screenVeil = { 1, a }
    return
  end
  love.graphics.setColor(1, 1, 1, a)
  love.graphics.rectangle("fill", 0, 0, 160, 144)
  love.graphics.setColor(1, 1, 1, 1)
end

return Transition
