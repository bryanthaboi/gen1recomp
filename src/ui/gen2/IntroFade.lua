-- ../pokecrystal/home/fade.asm:22-101 RotateFourPalettes* / RotateThreePalettes*
-- (src/ui/gen2/MenuFade.lua is the other ramp, home/map.asm:1910-1940.)

local GbcPalette = require("src.render.GbcPalette")

local IntroFade = {}
IntroFade.__index = IntroFade

-- ../pokecrystal/home/fade.asm:56-57, :99-100
local STEP_FRAMES = 8
IntroFade.STEP_FRAMES = STEP_FRAMES

-- pokecrystal/home/fade.asm:106-113; pokecrystal/home/palettes.asm:69-113
-- outBlack  RotateFourPalettesLeft   03 02 01 00
-- inBlack   RotateFourPalettesRight  00 01 02 03
-- outWhite  RotateThreePalettesRight 05 06 07
-- inWhite   RotateThreePalettesLeft  06 05 04
local ROWS = {
  outBlack = { 0xe4, 0xf9, 0xfe, 0xff },
  inBlack = { 0xff, 0xfe, 0xf9, 0xe4 },
  outWhite = { 0x90, 0x40, 0x00 },
  inWhite = { 0x40, 0x90, 0xe4 },
}
IntroFade.ROWS = ROWS

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
  local rows = ROWS[kind]
  return rows and #rows * STEP_FRAMES or 0
end

function IntroFade.new(kind)
  local rows = ROWS[kind]
  if not rows then return nil end
  return setmetatable({
    kind = kind,
    rows = rows,
    levels = LEVELS[kind],
    color = COLORS[kind],
    frame = 0,
    total = #rows * STEP_FRAMES,
  }, IntroFade)
end

function IntroFade:done() return self.frame >= self.total end

function IntroFade:tick()
  if self.frame < self.total then self.frame = self.frame + 1 end
  return self:done()
end

function IntroFade:index()
  local k = math.floor(self.frame / STEP_FRAMES) + 1
  if k > #self.rows then k = #self.rows end
  return k
end

-- pokecrystal/home/palettes.asm:69-113
function IntroFade:bgp()
  return self.rows[self:index()]
end

function IntroFade:level()
  return self.levels[self:index()]
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

-- pokecrystal/home/palettes.asm:69-113
function IntroFade.paint(owner, w, h, drawFn)
  local fade = owner.fade
  if not fade then return drawFn() end
  if not GbcPalette.available() then
    drawFn()
    return fade:draw(w, h)
  end
  local previous = GbcPalette.setBgp(fade:bgp())
  local ok, err = pcall(drawFn)
  GbcPalette.setBgp(previous)
  if not ok then error(err, 0) end
end

function IntroFade.surround(owner, palette, r, g, b, index)
  local fade = owner.fade
  if not fade then return r, g, b end
  if GbcPalette.available() and palette then
    local c = GbcPalette.remap(GbcPalette.resolve(palette), fade:bgp())
    c = c and c[index or 1]
    if c then return c[1] / 255, c[2] / 255, c[3] / 255 end
  end
  return fade:blend(r, g, b)
end

return IntroFade
