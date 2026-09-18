-- pret-faithful GBA sprite pool + OAM blit for game3 (240×160).
-- CreateSprite x/y are CENTER; hardware TL = x+x2+centerToCornerVec.

local Fx = require("src.core.game3.gba_fx")

local Oam = {}

Oam.MAX_SPRITES = 64
Oam.DISPLAY_WIDTH = 240
Oam.DISPLAY_HEIGHT = 160

-- ST_OAM shape
Oam.SHAPE_SQUARE = 0
Oam.SHAPE_H_RECT = 1
Oam.SHAPE_V_RECT = 2

-- ST_OAM size index 0..3
Oam.SIZE_0 = 0
Oam.SIZE_1 = 1
Oam.SIZE_2 = 2
Oam.SIZE_3 = 3

Oam.AFFINE_OFF = 0
Oam.AFFINE_NORMAL = 1
Oam.AFFINE_ERASE = 2
Oam.AFFINE_DOUBLE = 3

-- Convenient aliases matching common pret SPRITE_SHAPE/SIZE macros
Oam.SQUARE_8 = { shape = 0, size = 0, w = 8, h = 8 }
Oam.SQUARE_16 = { shape = 0, size = 1, w = 16, h = 16 }
Oam.SQUARE_32 = { shape = 0, size = 2, w = 32, h = 32 }
Oam.SQUARE_64 = { shape = 0, size = 3, w = 64, h = 64 }
Oam.HRECT_16x8 = { shape = 1, size = 0, w = 16, h = 8 }
Oam.HRECT_32x8 = { shape = 1, size = 1, w = 32, h = 8 }
Oam.HRECT_32x16 = { shape = 1, size = 2, w = 32, h = 16 }
Oam.HRECT_64x32 = { shape = 1, size = 3, w = 64, h = 32 }
Oam.VRECT_8x16 = { shape = 2, size = 0, w = 8, h = 16 }
Oam.VRECT_8x32 = { shape = 2, size = 1, w = 8, h = 32 }
Oam.VRECT_16x32 = { shape = 2, size = 2, w = 16, h = 32 }
Oam.VRECT_32x64 = { shape = 2, size = 3, w = 32, h = 64 }

-- pret sCenterToCornerVecTable[shape][size] = {x, y} (signed)
local CENTER_TO_CORNER = {
  [0] = { -- square
    [0] = { -4, -4 },
    [1] = { -8, -8 },
    [2] = { -16, -16 },
    [3] = { -32, -32 },
  },
  [1] = { -- horizontal rectangle
    [0] = { -8, -4 },
    [1] = { -16, -4 },
    [2] = { -16, -8 },
    [3] = { -32, -16 },
  },
  [2] = { -- vertical rectangle
    [0] = { -4, -8 },
    [1] = { -4, -16 },
    [2] = { -8, -16 },
    [3] = { -16, -32 },
  },
}

local function dummy_callback(_sprite) end
Oam.DUMMY_CALLBACK = dummy_callback

local function new_slot()
  return {
    inUse = false,
    oam = {
      shape = 0,
      size = 0,
      priority = 0,
      affineMode = 0,
      hFlip = false,
      vFlip = false,
      matrixNum = 0,
    },
    x = 0,
    y = 0,
    x2 = 0,
    y2 = 0,
    centerToCornerVecX = 0,
    centerToCornerVecY = 0,
    subpriority = 0,
    invisible = false,
    callback = dummy_callback,
    data = { 0, 0, 0, 0, 0, 0, 0, 0 },
    image = nil,
    quad = nil,
    animPaused = false,
  }
end

Oam._sprites = nil
Oam._buffer = nil -- sorted draw list for this frame
Oam._coordOffsetX = 0
Oam._coordOffsetY = 0

local function ensure_pool()
  if Oam._sprites then return end
  Oam._sprites = {}
  for i = 0, Oam.MAX_SPRITES - 1 do
    Oam._sprites[i] = new_slot()
  end
end

function Oam.reset()
  ensure_pool()
  for i = 0, Oam.MAX_SPRITES - 1 do
    local s = Oam._sprites[i]
    s.inUse = false
    s.image = nil
    s.quad = nil
    s.callback = dummy_callback
    s.invisible = false
    s.x2, s.y2 = 0, 0
    s.fx, s.blend, s.clip = nil, nil, nil
    s.anims, s.animQuads, s.affineAnim = nil, nil, nil
  end
  Oam._buffer = nil
  Oam._clip = nil
  Oam._fx = nil
  Oam._blend = nil
end

--- pret CalcCenterToCornerVec (signed).
function Oam.calcCenterToCornerVec(shape, size, affineMode)
  shape = tonumber(shape) or 0
  size = tonumber(size) or 0
  affineMode = tonumber(affineMode) or 0
  local row = CENTER_TO_CORNER[shape] and CENTER_TO_CORNER[shape][size]
  if not row then return 0, 0 end
  local x, y = row[1], row[2]
  -- ST_OAM_AFFINE_DOUBLE_MASK = 0x2
  if math.floor(affineMode / 2) % 2 == 1 then
    x, y = x * 2, y * 2
  end
  return x, y
end

function Oam.applyCenterToCorner(sprite)
  local cx, cy = Oam.calcCenterToCornerVec(
    sprite.oam.shape, sprite.oam.size, sprite.oam.affineMode)
  sprite.centerToCornerVecX = cx
  sprite.centerToCornerVecY = cy
end

--- Hardware OAM top-left (pret sprite.c BuildOamBuffer path).
function Oam.oamTopLeft(sprite)
  local ox = (sprite.x or 0) + (sprite.x2 or 0) + (sprite.centerToCornerVecX or 0)
    + (Oam._coordOffsetX or 0)
  local oy = (sprite.y or 0) + (sprite.y2 or 0) + (sprite.centerToCornerVecY or 0)
    + (Oam._coordOffsetY or 0)
  return ox, oy
end

local function copy_oam(dst, src)
  if not src then return end
  dst.shape = src.shape or 0
  dst.size = src.size or 0
  dst.priority = src.priority or 0
  dst.affineMode = src.affineMode or 0
  dst.hFlip = src.hFlip and true or false
  dst.vFlip = src.vFlip and true or false
  dst.matrixNum = src.matrixNum or 0
end

--- CreateSprite — x/y are CENTER. template fields:
--   oam | shape,size,priority | image, quad | callback | w,h (optional dims hint)
function Oam.createSprite(template, x, y, subpriority)
  ensure_pool()
  template = template or {}
  for i = 0, Oam.MAX_SPRITES - 1 do
    local s = Oam._sprites[i]
    if not s.inUse then
      s.inUse = true
      s.oam.affineMode = 0
      s.oam.hFlip, s.oam.vFlip = false, false
      s.oam.matrixNum = 0
      copy_oam(s.oam, template.oam)
      if template.shape ~= nil then s.oam.shape = template.shape end
      if template.size ~= nil then s.oam.size = template.size end
      if template.priority ~= nil then s.oam.priority = template.priority end
      -- Convenience: pass Oam.SQUARE_32 etc.
      if template.dims then
        s.oam.shape = template.dims.shape
        s.oam.size = template.dims.size
      end
      s.x = tonumber(x) or 0
      s.y = tonumber(y) or 0
      s.x2 = 0
      s.y2 = 0
      s.subpriority = tonumber(subpriority) or 0
      s.invisible = false
      s.callback = template.callback or dummy_callback
      s.image = template.image
      s.quad = template.quad
      s.animPaused = template.animPaused and true or false
      s.layer = template.layer or Oam._layer or "ui"
      s.fx, s.blend, s.clip = nil, nil, nil
      s.anims = template.anims
      s.animQuads = template.animQuads
      s.animNum = 0
      s.animBeginning = template.anims ~= nil
      s.animEnded = false
      s.animCmdIndex = 0
      s.animDelayCounter = 0
      s.affineAnim = nil
      s.affineScale = nil
      s.affineMatrixA = nil
      s.affineAnimEnded = false
      s.anchored = false
      s.anchorX, s.anchorY = nil, nil
      s.objWindow, s.palSlot, s.objBlend = nil, nil, nil
      for d = 1, 8 do s.data[d] = 0 end
      Oam.applyCenterToCorner(s)
      s._id = i
      return i, s
    end
  end
  return nil, nil
end

function Oam.destroySprite(id)
  ensure_pool()
  id = tonumber(id)
  if id == nil or id < 0 or id >= Oam.MAX_SPRITES then return end
  local s = Oam._sprites[id]
  s.inUse = false
  s.image = nil
  s.quad = nil
  s.callback = dummy_callback
  s.invisible = true
end

function Oam.destroyAll()
  Oam.reset()
end

function Oam.get(id)
  ensure_pool()
  id = tonumber(id)
  if id == nil then return nil end
  local s = Oam._sprites[id]
  if s and s.inUse then return s end
  return nil
end

function Oam.setPos(id, x, y)
  local s = Oam.get(id)
  if not s then return end
  if x ~= nil then s.x = x end
  if y ~= nil then s.y = y end
end

function Oam.setOffset(id, x2, y2)
  local s = Oam.get(id)
  if not s then return end
  if x2 ~= nil then s.x2 = x2 end
  if y2 ~= nil then s.y2 = y2 end
end

function Oam.setImage(id, image, quad)
  local s = Oam.get(id)
  if not s then return end
  s.image = image
  s.quad = quad
end

function Oam.setInvisible(id, inv)
  local s = Oam.get(id)
  if not s then return end
  s.invisible = not not inv
end

function Oam.setCallback(id, cb)
  local s = Oam.get(id)
  if not s then return end
  s.callback = cb or dummy_callback
end

function Oam.setPriority(id, priority)
  local s = Oam.get(id)
  if not s then return end
  s.oam.priority = math.max(0, math.min(3, tonumber(priority) or 0))
end

function Oam.setSubpriority(id, sub)
  local s = Oam.get(id)
  if not s then return end
  s.subpriority = tonumber(sub) or 0
end

--- Begin frame (pret: clear shadow OAM build).
function Oam.resetFrame()
  ensure_pool()
  Oam._buffer = {}
end

Oam._layer = "ui"

function Oam.setLayer(layer)
  local prev = Oam._layer
  Oam._layer = layer or "ui"
  return prev
end

local function layer_of(sprite)
  return sprite.layer or "ui"
end

function Oam.setCoordOffset(ox, oy)
  Oam._coordOffsetX = tonumber(ox) or 0
  Oam._coordOffsetY = tonumber(oy) or 0
end

local function applyAnimFrame(s, cmd)
  local dur = cmd.dur or 0
  if dur > 0 then dur = dur - 1 end
  s.animDelayCounter = dur
  if s.animQuads and s.animQuads[cmd.img] then
    s.quad = s.animQuads[cmd.img]
  end
end

local function stepAnim(s)
  local list = s.anims[s.animNum]
  if not list then return end
  if s.animBeginning then
    s.animBeginning = false
    s.animCmdIndex = 1
    s.animEnded = false
    applyAnimFrame(s, list[1])
    return
  end
  if s.animDelayCounter > 0 then
    if not s.animPaused then s.animDelayCounter = s.animDelayCounter - 1 end
    return
  end
  if s.animPaused then return end
  s.animCmdIndex = s.animCmdIndex + 1
  local cmd = list[s.animCmdIndex]
  if cmd == nil or cmd == "end" then
    s.animCmdIndex = s.animCmdIndex - 1
    s.animEnded = true
  elseif cmd.jump then
    s.animCmdIndex = cmd.jump + 1
    applyAnimFrame(s, list[s.animCmdIndex])
  else
    applyAnimFrame(s, cmd)
  end
end

-- pokefirered/src/sprite.c:1066
function Oam.startAnim(s, animNum)
  s.animNum = animNum or 0
  s.animBeginning = true
  s.animEnded = false
end

local SPRITE_DIMS = {
  [0] = { [0] = { 8, 8 }, { 16, 16 }, { 32, 32 }, { 64, 64 } },
  [1] = { [0] = { 16, 8 }, { 32, 8 }, { 32, 16 }, { 64, 32 } },
  [2] = { [0] = { 8, 16 }, { 8, 32 }, { 16, 32 }, { 32, 64 } },
}

local function idiv(a, b)
  local q = a / b
  return q >= 0 and math.floor(q) or math.ceil(q)
end

-- pokefirered/src/sprite.c:1233
local function anchorCoord(baseDim, xformed, modifier)
  local sub = xformed - baseDim
  local shift
  if sub < 0 then
    shift = math.floor(-sub / 512)
  else
    shift = -math.floor(sub / 512)
  end
  return modifier - (math.floor((modifier * xformed) / baseDim) + shift)
end

local function updateAnchor(s)
  local a = s.affineMatrixA or 0x100
  local dims = SPRITE_DIMS[s.oam.shape][s.oam.size]
  if s.anchorX then
    local dim = dims[1]
    s.x2 = anchorCoord(dim * 256, idiv(dim * 65536, a), s.anchorX)
  end
  if s.anchorY then
    local dim = dims[2]
    s.y2 = anchorCoord(dim * 256, idiv(dim * 65536, a), s.anchorY)
  end
end

local function setAffineScale(s, scale)
  s.affineScaleRaw = scale
  local a = scale ~= 0 and idiv(0x10000, scale) or 0x100
  s.affineMatrixA = a
  s.affineScale = 256 / a
end

-- pokefirered/src/sprite.c:1203
function Oam.setMatrixAnchor(s, x, y)
  s.anchorX, s.anchorY = x, y
  s.anchored = true
end

-- pokefirered/src/sprite.c:1062
function Oam.startAffineAnim(s, cmds)
  s.affineAnim = { cmds = cmds, index = 1, delay = 0, begin = true, scale = 256 }
  s.affineAnimEnded = false
end

-- pokefirered/src/sprite.c:1274
local function applyAffineFrame(s, st, c)
  if (c.dur or 0) > 0 then
    st.delay = c.dur - 1
    st.scale = st.scale + c.v
  else
    st.delay = 0
    st.scale = c.v
  end
  setAffineScale(s, st.scale)
end

local function stepAffine(s)
  local st = s.affineAnim
  local cmds = st.cmds
  if st.begin then
    st.begin = false
    st.index = 1
    s.affineAnimEnded = false
    applyAffineFrame(s, st, cmds[1])
  elseif st.delay > 0 then
    st.delay = st.delay - 1
    st.scale = st.scale + (cmds[st.index].v or 0)
    setAffineScale(s, st.scale)
  else
    st.index = st.index + 1
    local c = cmds[st.index]
    if c == nil or c == "end" then
      st.index = st.index - 1
      s.affineAnimEnded = true
    else
      applyAffineFrame(s, st, c)
    end
  end
  if s.anchored then updateAnchor(s) end
end

function Oam.animateSprite(s)
  if s.inUse and s.anims then stepAnim(s) end
  if s.inUse and s.affineAnim then stepAffine(s) end
end

function Oam.animateSprites(layer)
  ensure_pool()
  for i = 0, Oam.MAX_SPRITES - 1 do
    local s = Oam._sprites[i]
    if s.inUse and s.callback and (not layer or (s.layer or "ui") == layer) then
      s.callback(s)
      if s.inUse and s.anims then stepAnim(s) end
      if s.inUse and s.affineAnim then stepAffine(s) end
    end
  end
end

local function sprite_priority_key(sprite)
  -- pret: gSpritePriorities[i] = subpriority | (oam.priority << 8)
  local oamPri = (sprite.oam and sprite.oam.priority) or 0
  local sub = sprite.subpriority or 0
  return oamPri * 256 + sub
end

local function sort_sprites(a, b)
  -- pret SortSprites: lower priority key first (drawn behind), then lower y.
  local pa, pb = sprite_priority_key(a), sprite_priority_key(b)
  if pa ~= pb then return pa < pb end
  local _, ya = Oam.oamTopLeft(a)
  local _, yb = Oam.oamTopLeft(b)
  return ya < yb
end

--- Collect visible sprites into draw buffer (BuildOamBuffer).
local function sort_sprites_pret(a, b)
  -- pokefirered/src/sprite.c:368
  local pa, pb = sprite_priority_key(a), sprite_priority_key(b)
  if pa ~= pb then return pa > pb end
  local _, ya = Oam.oamTopLeft(a)
  local _, yb = Oam.oamTopLeft(b)
  if ya ~= yb then return ya < yb end
  return (a._id or 0) > (b._id or 0)
end

function Oam.buildOamBuffer(pretOrder)
  ensure_pool()
  local buf = {}
  for i = 0, Oam.MAX_SPRITES - 1 do
    local s = Oam._sprites[i]
    if s.inUse and not s.invisible and s.image then
      buf[#buf + 1] = s
    end
  end
  table.sort(buf, pretOrder and sort_sprites_pret or sort_sprites)
  Oam._buffer = buf
  return buf
end

function Oam.setClip(clip)
  Oam._clip = clip
end

function Oam.setFx(fx, blend)
  Oam._fx = fx
  Oam._blend = blend
end

local blit_plain

local function blit_affine(s)
  local img, q = s.image, s.quad
  local dims = SPRITE_DIMS[s.oam.shape][s.oam.size]
  local w, h = dims[1], dims[2]
  local m = s.affineScale or 1
  local cx = (s.x or 0) + (s.x2 or 0) + (Oam._coordOffsetX or 0)
  local cy = (s.y or 0) + (s.y2 or 0) + (Oam._coordOffsetY or 0)
  if not (math.floor(s.oam.affineMode / 2) % 2 == 1) then
    cx = cx + (s.centerToCornerVecX or 0) + w / 2
    cy = cy + (s.centerToCornerVecY or 0) + h / 2
  end
  if q then
    love.graphics.draw(img, q, cx, cy, 0, m, m, w / 2, h / 2)
  else
    love.graphics.draw(img, cx, cy, 0, m, m, w / 2, h / 2)
  end
end

local function blit_sprite(s)
  local fx = s.fx or Oam._fx
  local blend = s.blend or Oam._blend
  local clip = s.clip or Oam._clip
  if clip and (clip.w <= 0 or clip.h <= 0) then return end
  local draw = s.affineScale and function() blit_affine(s) end or function() blit_plain(s) end
  if not fx and not blend and not clip then
    draw()
    return
  end
  Fx.withClip(clip, function() Fx.draw(draw, fx, blend) end)
end

blit_plain = function(s)
  local tlx, tly = Oam.oamTopLeft(s)
  local img, q = s.image, s.quad
  if not img then return end
  local sx = s.oam.hFlip and -1 or 1
  local sy = s.oam.vFlip and -1 or 1
  if sx < 0 or sy < 0 then
    local dims = CENTER_TO_CORNER[s.oam.shape] and CENTER_TO_CORNER[s.oam.shape][s.oam.size]
    local halfW = dims and -dims[1] or 16
    local halfH = dims and -dims[2] or 16
    local w, h = halfW * 2, halfH * 2
    local dx = sx < 0 and (tlx + w) or tlx
    local dy = sy < 0 and (tly + h) or tly
    if q then
      love.graphics.draw(img, q, dx, dy, 0, sx, sy)
    else
      love.graphics.draw(img, dx, dy, 0, sx, sy)
    end
  else
    if q then
      love.graphics.draw(img, q, tlx, tly)
    else
      love.graphics.draw(img, tlx, tly)
    end
  end
end

function Oam.flushOne(s)
  love.graphics.setColor(1, 1, 1, 1)
  blit_sprite(s)
end

--- Blit sorted OAM to the current Love canvas (all priorities).
function Oam.flush(layer)
  if not love or not love.graphics then return end
  local buf = Oam._buffer
  if not buf then buf = Oam.buildOamBuffer() end
  love.graphics.setColor(1, 1, 1, 1)
  for _, s in ipairs(buf) do
    if not layer or layer_of(s) == layer then
      blit_sprite(s)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

--- Blit only sprites at a given OAM priority (for BG×OBJ interleave).
--- Buffer must already be sorted (buildOamBuffer). Same-pri order preserved.
function Oam.flushPriority(priority, layer)
  if not love or not love.graphics then return end
  local buf = Oam._buffer
  if not buf then buf = Oam.buildOamBuffer() end
  priority = tonumber(priority) or 0
  love.graphics.setColor(1, 1, 1, 1)
  for _, s in ipairs(buf) do
    local p = (s.oam and s.oam.priority) or 0
    if p == priority and (not layer or layer_of(s) == layer) then
      blit_sprite(s)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Oam
