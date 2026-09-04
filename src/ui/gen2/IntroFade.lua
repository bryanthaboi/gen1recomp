-- ../pokecrystal/home/fade.asm:22-101 RotateFourPalettes* / RotateThreePalettes*
-- (src/ui/gen2/MenuFade.lua is the other ramp, home/map.asm:1910-1940.)

local IntroFade = {}
IntroFade.__index = IntroFade

-- ../pokecrystal/home/fade.asm:56-57, :99-100
local STEP_FRAMES = 8
IntroFade.STEP_FRAMES = STEP_FRAMES

-- ../pokecrystal/home/fade.asm:106-113
-- outBlack  RotateFourPalettesLeft   03 02 01 00
-- inBlack   RotateFourPalettesRight  00 01 02 03
-- outWhite  RotateThreePalettesRight 05 06 07
-- inWhite   RotateThreePalettesLeft  06 05 04
local LEVELS = {
  outBlack = { 0, 1 / 3, 2 / 3, 1 },
  inBlack = { 1, 2 / 3, 1 / 3, 0 },
  outWhite = { 1 / 3, 2 / 3, 1 },
  inWhite = { 2 / 3, 1 / 3, 0 },
}

local BLACK, WHITE = { 0, 0, 0 }, { 1, 1, 1 }
local COLORS = {
  outBlack = BLACK, inBlack = BLACK, outWhite = WHITE, inWhite = WHITE,
}

IntroFade.FOUR_FRAMES = 4 * STEP_FRAMES
IntroFade.THREE_FRAMES = 3 * STEP_FRAMES

function IntroFade.frames(kind)
  local levels = LEVELS[kind]
  return levels and #levels * STEP_FRAMES or 0
end

function IntroFade.new(kind)
  local levels = LEVELS[kind]
  if not levels then return nil end
  return setmetatable({
    kind = kind,
    levels = levels,
    color = COLORS[kind],
    frame = 0,
    total = #levels * STEP_FRAMES,
  }, IntroFade)
end

function IntroFade:done() return self.frame >= self.total end

function IntroFade:tick()
  if self.frame < self.total then self.frame = self.frame + 1 end
  return self:done()
end

function IntroFade:level()
  local k = math.floor(self.frame / STEP_FRAMES) + 1
  if k > #self.levels then k = #self.levels end
  return self.levels[k]
end

function IntroFade:draw(w, h)
  local a = self:level()
  if a <= 0 then return end
  local G = love.graphics
  local c = self.color
  G.setColor(c[1], c[2], c[3], a)
  G.rectangle("fill", 0, 0, w, h)
  G.setColor(1, 1, 1, 1)
end

function IntroFade:blend(r, g, b)
  local a = self:level()
  local c = self.color
  return r + (c[1] - r) * a, g + (c[2] - g) * a, b + (c[3] - b) * a
end

-- ---------------------------------------------------------- owner-side mixin

function IntroFade.step(owner)
  owner.fadeAt = (owner.fadeAt or 0) + 1
  local kind = owner.fadeQueue and owner.fadeQueue[owner.fadeAt]
  if not kind then
    owner.fade, owner.fadeQueue, owner.fadeAt = nil, nil, nil
    local fn = owner.fadeDone
    owner.fadeDone = nil
    if fn then fn() end
    return
  end
  owner.fade = IntroFade.new(kind)
end

function IntroFade.run(owner, kinds, onDone)
  owner.fadeQueue, owner.fadeAt, owner.fadeDone = kinds, 0, onDone
  IntroFade.step(owner)
end

function IntroFade.busy(owner)
  return owner.fade ~= nil
end

-- True when the fade owned this frame, so the caller returns before its input.
function IntroFade.advance(owner)
  if not owner.fade then return false end
  if owner.fade:tick() then IntroFade.step(owner) end
  return true
end

function IntroFade.paint(owner, w, h)
  if owner.fade then owner.fade:draw(w, h) end
end

function IntroFade.surround(owner, r, g, b)
  if not owner.fade then return r, g, b end
  return owner.fade:blend(r, g, b)
end

return IntroFade
