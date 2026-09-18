local bit = require("bit")
local Trig = require("src.core.game3.trig")
local AnimSprites = require("src.core.game3.battle.anim_sprites")
local AnimPal = require("src.core.game3.battle.anim_pal")
local AnimCoords = require("src.core.game3.battle.anim_coords")

local band, bor, bxor, rshift, arshift, lshift = bit.band, bit.bor, bit.bxor, bit.rshift, bit.arshift, bit.lshift
local floor = math.floor

local P = {}

P.ANIM_ATTACKER = 0
P.ANIM_TARGET = 1
P.ANIM_ATK_PARTNER = 2
P.ANIM_DEF_PARTNER = 3
P.ARG_RET_ID = 7

P.SOUND_PAN_ATTACKER = -64
P.SOUND_PAN_TARGET = 63

P.X = 0
P.Y = 1
P.X_2 = 2
P.Y_PIC_OFFSET = 3
P.Y_PIC_OFFSET_DEFAULT = 4

-- pokefirered/src/battle_anim_mons.c:31
P.COORDS = setmetatable({}, { __index = function(_, k) return AnimCoords.coords(nil, k) end })

function P.s16(v)
  v = band(floor(tonumber(v) or 0), 0xFFFF)
  if v >= 0x8000 then v = v - 0x10000 end
  return v
end

function P.u16(v)
  return band(floor(tonumber(v) or 0), 0xFFFF)
end

function P.u8(v)
  return band(floor(tonumber(v) or 0), 0xFF)
end

function P.s8(v)
  v = band(floor(tonumber(v) or 0), 0xFF)
  if v >= 0x80 then v = v - 0x100 end
  return v
end

function P.asr(v, n)
  return arshift(floor(v), n)
end

function P.cdiv(a, b)
  if b == 0 then return 0 end
  local q = a / b
  if q >= 0 then return floor(q) end
  return -floor(-q)
end

-- pokefirered/include/trig.h:8
function P.Sin(angle, amp)
  local v = Trig.SINE[band(floor(angle), 0xFF) + 1]
  return arshift(v * floor(amp), 8)
end

function P.Cos(angle, amp)
  local v = Trig.SINE[band(floor(angle), 0xFF) + 65]
  return arshift(v * floor(amp), 8)
end

function P.gSine(i)
  return Trig.SINE[floor(i) + 1] or 0
end

function P.ArcTan2(x, y)
  local a = math.atan2(y, x)
  return band(floor(a * 65536 / (2 * math.pi) + 0.5), 0xFFFF)
end

-- pokefirered/src/battle_anim_mons.c:1281
function P.ArcTan2Neg(x, y)
  return band(-P.ArcTan2(x, y), 0xFFFF)
end

function P.other(side)
  return side == "player" and "enemy" or "player"
end

function P.atk(vm)
  if vm and vm.allyPair and vm:allyPair() then return vm:attackerId() end
  return vm and vm.attackerSide and vm:attackerSide() or "player"
end

function P.tgt(vm)
  if vm and vm.allyPair and vm:allyPair() then return vm:targetId() end
  return vm and vm.targetSide and vm:targetSide() or "enemy"
end

function P.sideId(side)
  if type(side) == "number" then return side % 2 end
  return side == "player" and 0 or 1
end

function P.battlerSide(vm, animBattler)
  animBattler = tonumber(animBattler) or 0
  if animBattler == 0 then return P.atk(vm) end
  if animBattler == 1 then return P.tgt(vm) end
  if (animBattler == 2 or animBattler == 3) and vm and vm.battlerId then return vm:battlerId(animBattler) end
  return nil
end

local function species_offsets(side, species)
  local ok, PicCoords = pcall(require, "src.core.game3.battle.pic_coords")
  if not ok or type(PicCoords) ~= "table" then return 0, 0 end
  local sp = tonumber(species)
  if not sp then return 0, 0 end
  if side == "player" then
    return (PicCoords.back and PicCoords.back[sp]) or 0, 0
  end
  return (PicCoords.front and PicCoords.front[sp]) or 0, (PicCoords.elev and PicCoords.elev[sp]) or 0
end

function P.species(vm, side)
  if not vm then return nil end
  if vm._speciesBySide and vm._speciesBySide[side] ~= nil then return vm._speciesBySide[side] end
  if vm.speciesForSide then return vm:speciesForSide(side) end
  return nil
end

-- pokefirered/src/battle_anim_mons.c:105
function P.coord(vm, side, coordType)
  local base = P.COORDS[side] or P.COORDS.enemy
  if coordType == P.X or coordType == P.X_2 then return base.x end
  if coordType == P.Y then return base.y end
  local yoff, elev = species_offsets(side, P.species(vm, side))
  local y = band(yoff - elev + base.y, 0xFF)
  if coordType == P.Y_PIC_OFFSET then
    if side == "player" then y = band(y + 8, 0xFF) end
    if y > 160 - 64 + 8 then y = 160 - 64 + 8 end
  end
  return y
end

-- pokefirered/src/battle_anim_mons.c:305
function P.yWithElevation(vm, side)
  local y = P.coord(vm, side, P.Y)
  if side ~= "player" then
    local _, elev = species_offsets(side, P.species(vm, side))
    y = band(y - elev, 0xFF)
  end
  return y
end

P.coord = AnimCoords.sideArg(P.coord, 2)
P.yWithElevation = AnimCoords.sideArg(P.yWithElevation, 2)

-- pokefirered/src/battle_anim_mons.c:286
function P.substituteY(side)
  local id = AnimCoords.idOf(side) or 1
  return P.COORDS[id].y + (AnimCoords.sideOf(id) ~= "player" and 16 or 17)
end

-- pokefirered/src/battle_anim_mons.c:1908
function P.subpriorityOf(side)
  return AnimCoords.subpriority(side)
end

function P.zFor(priority, subpriority)
  priority = tonumber(priority) or 2
  subpriority = tonumber(subpriority) or 0
  if AnimCoords.isDouble() then
    local Anim = package.loaded["src.core.game3.battle.anim"]
    return AnimCoords.zFor(priority, subpriority, Anim and Anim._vm)
  end
  if priority <= 1 then return 900 + (255 - subpriority) % 100 end
  local z = 500 - 10 * subpriority - 1
  if priority >= 3 then z = math.min(z, 99) end
  if z < 0 then z = 0 end
  if z > 899 then z = 899 end
  return z
end

function P.setPriority(s, priority, subpriority)
  s.oamPriority = priority or s.oamPriority or 2
  if subpriority ~= nil then s.subpriority = subpriority end
  s.z = P.zFor(s.oamPriority, s.subpriority)
end

function P.args(vm)
  return vm and vm.args or {}
end

-- pokefirered/src/battle_anim_mons.c:735
function P.setInitialXOffset(vm, s, xOffset)
  local ax = P.coord(vm, P.atk(vm), P.X)
  local tx = P.coord(vm, P.tgt(vm), P.X)
  if ax > tx then
    s.x = s.x - xOffset
  elseif ax < tx then
    s.x = s.x + xOffset
  elseif P.atk(vm) ~= "player" then
    s.x = s.x - xOffset
  else
    s.x = s.x + xOffset
  end
end

-- pokefirered/src/battle_anim_mons.c:792
function P.initPosToTarget(vm, s, respect)
  local a = P.args(vm)
  if not respect then
    s.x = P.coord(vm, P.tgt(vm), P.X)
    s.y = P.coord(vm, P.tgt(vm), P.Y)
  end
  P.setInitialXOffset(vm, s, a[0] or 0)
  s.y = s.y + (a[1] or 0)
end

-- pokefirered/src/battle_anim_mons.c:805
function P.initPosToAttacker(vm, s, respect)
  local a = P.args(vm)
  local side = P.atk(vm)
  if not respect then
    s.x = P.coord(vm, side, P.X)
    s.y = P.coord(vm, side, P.Y)
  else
    s.x = P.coord(vm, side, P.X_2)
    s.y = P.coord(vm, side, P.Y_PIC_OFFSET)
  end
  P.setInitialXOffset(vm, s, a[0] or 0)
  s.y = s.y + (a[1] or 0)
end

-- pokefirered/src/battle_anim_mons.c:2098
function P.averagePositions(vm, side, respect)
  local xt, yt = P.X, P.Y
  if respect then xt, yt = P.X_2, P.Y_PIC_OFFSET end
  local id = AnimCoords.idOf(side) or 1
  local x, y = P.coord(vm, id, xt), P.coord(vm, id, yt)
  if not AnimCoords.isDouble() then return x, y end
  local partner = AnimCoords.partner(id)
  local px, py = P.coord(vm, partner, xt), P.coord(vm, partner, yt)
  return P.cdiv(x + px, 2), P.cdiv(y + py, 2)
end

function P.destroy(s)
  AnimSprites.release(s)
end

function P.storeCb(s, fn)
  s._stored = fn
end

function P.runStored(s)
  s.callback = s._stored or P.destroy
end

function P.dummy() end

function P.isInvisible(s)
  return s.visible == false
end

function P.setInvisible(s, v)
  s.visible = not v
end

-- pokefirered/src/battle_anim_mons.c:988
function P.initLinear(s)
  local d = s.data
  local x = d[2] - d[1]
  local y = d[4] - d[3]
  local speed = d[0]
  local xd = band(lshift(math.abs(x), 8), 0xFFFF)
  local yd = band(lshift(math.abs(y), 8), 0xFFFF)
  if speed ~= 0 then
    xd = band(floor(xd / speed), 0xFFFF)
    yd = band(floor(yd / speed), 0xFFFF)
  end
  if x < 0 then xd = bor(xd, 1) else xd = band(xd, 0xFFFE) end
  if y < 0 then yd = bor(yd, 1) else yd = band(yd, 0xFFFE) end
  d[1] = P.s16(xd)
  d[2] = P.s16(yd)
  d[4] = 0
  d[3] = 0
end

-- pokefirered/src/battle_anim_mons.c:1034
function P.translateLinear(s)
  local d = s.data
  if d[0] == 0 then return true end
  local v1 = P.u16(d[1])
  local v2 = P.u16(d[2])
  local x = P.u16(P.u16(d[3]) + v1)
  local y = P.u16(P.u16(d[4]) + v2)
  if band(v1, 1) ~= 0 then s.ox = -rshift(x, 8) else s.ox = rshift(x, 8) end
  if band(v2, 1) ~= 0 then s.oy = -rshift(y, 8) else s.oy = rshift(y, 8) end
  d[3] = P.s16(x)
  d[4] = P.s16(y)
  d[0] = P.s16(d[0] - 1)
  return false
end

function P.translateLinearFollowup(s)
  if P.translateLinear(s) then P.runStored(s) end
end

-- pokefirered/src/battle_anim_mons.c:1016
function P.startLinear(s)
  s.data[1] = s.x
  s.data[3] = s.y
  P.initLinear(s)
  s.callback = P.translateLinearFollowup
  s.callback(s)
end

-- pokefirered/src/battle_anim_mons.c:1074
function P.initLinearWithSpeed(s)
  local d = s.data
  local v1 = lshift(math.abs(d[2] - d[1]), 8)
  if d[0] ~= 0 then d[0] = P.s16(P.cdiv(v1, d[0])) end
  P.initLinear(s)
end

function P.initLinearWithSpeedAndPos(s)
  s.data[1] = s.x
  s.data[3] = s.y
  P.initLinearWithSpeed(s)
  s.callback = P.translateLinearFollowup
  s.callback(s)
end

-- pokefirered/src/battle_anim_mons.c:757
function P.initArc(s)
  s.data[1] = s.x
  s.data[3] = s.y
  P.initLinear(s)
  local speed = s.data[0]
  s.data[6] = speed ~= 0 and P.s16(P.cdiv(0x8000, speed)) or 0
  s.data[7] = 0
end

-- pokefirered/src/battle_anim_mons.c:766
function P.translateHArc(s)
  if P.translateLinear(s) then return true end
  s.data[7] = P.s16(s.data[7] + s.data[6])
  s.oy = s.oy + P.Sin(band(rshift(P.u16(s.data[7]), 8), 0xFF), s.data[5])
  return false
end

function P.translateVArc(s)
  if P.translateLinear(s) then return true end
  s.data[7] = P.s16(s.data[7] + s.data[6])
  s.ox = s.ox + P.Sin(band(rshift(P.u16(s.data[7]), 8), 0xFF), s.data[5])
  return false
end

-- pokefirered/src/battle_anim_mons.c:1091
function P.initFastLinear(s)
  local d = s.data
  local x = d[2] - d[1]
  local y = d[4] - d[3]
  local x2 = band(lshift(math.abs(x), 4), 0xFFFF)
  local y2 = band(lshift(math.abs(y), 4), 0xFFFF)
  if d[0] ~= 0 then
    x2 = band(floor(x2 / d[0]), 0xFFFF)
    y2 = band(floor(y2 / d[0]), 0xFFFF)
  end
  if x < 0 then x2 = bor(x2, 1) else x2 = band(x2, 0xFFFE) end
  if y < 0 then y2 = bor(y2, 1) else y2 = band(y2, 0xFFFE) end
  d[1] = P.s16(x2)
  d[2] = P.s16(y2)
  d[4] = 0
  d[3] = 0
end

function P.fastTranslateLinear(s)
  local d = s.data
  if d[0] == 0 then return true end
  local v1 = P.u16(d[1])
  local v2 = P.u16(d[2])
  local x = P.u16(P.u16(d[3]) + v1)
  local y = P.u16(P.u16(d[4]) + v2)
  if band(v1, 1) ~= 0 then s.ox = -rshift(x, 4) else s.ox = rshift(x, 4) end
  if band(v2, 1) ~= 0 then s.oy = -rshift(y, 4) else s.oy = rshift(y, 4) end
  d[3] = P.s16(x)
  d[4] = P.s16(y)
  d[0] = P.s16(d[0] - 1)
  return false
end

-- pokefirered/src/battle_anim_mons.c:1116
function P.initAndRunFastLinear(s)
  s.data[1] = s.x
  s.data[3] = s.y
  P.initFastLinear(s)
  s.callback = function(sp)
    if P.fastTranslateLinear(sp) then P.runStored(sp) end
  end
  s.callback(s)
end

-- pokefirered/src/battle_anim_mons.c:521
function P.waitAnimForDuration(s)
  if s.data[0] > 0 then
    s.data[0] = s.data[0] - 1
  else
    P.runStored(s)
  end
end

-- pokefirered/src/battle_anim_mons.c:576
function P.translateSpriteLinearFixedPoint(s)
  local d = s.data
  if d[0] > 0 then
    d[0] = d[0] - 1
    d[3] = P.s16(d[3] + d[1])
    d[4] = P.s16(d[4] + d[2])
    s.ox = arshift(d[3], 8)
    s.oy = arshift(d[4], 8)
  else
    P.runStored(s)
  end
end

-- pokefirered/src/battle_anim_mons.c:562
function P.translateSpriteLinear(s)
  local d = s.data
  if d[0] > 0 then
    d[0] = d[0] - 1
    s.ox = s.ox + d[1]
    s.oy = s.oy + d[2]
  else
    P.runStored(s)
  end
end

-- pokefirered/src/battle_anim_mons.c:412
function P.translateInCircle(s)
  local d = s.data
  if d[3] ~= 0 then
    s.ox = P.Sin(d[0], d[1])
    s.oy = P.Cos(d[0], d[1])
    d[0] = d[0] + d[2]
    if d[0] >= 0x100 then d[0] = d[0] - 0x100 elseif d[0] < 0 then d[0] = d[0] + 0x100 end
    d[3] = d[3] - 1
  else
    P.runStored(s)
  end
end

-- pokefirered/src/battle_anim_mons.c:486
function P.translateInEllipse(s)
  local d = s.data
  if d[3] ~= 0 then
    s.ox = P.Sin(d[0], d[1])
    s.oy = P.Cos(d[0], d[4])
    d[0] = d[0] + d[2]
    if d[0] >= 0x100 then d[0] = d[0] - 0x100 elseif d[0] < 0 then d[0] = d[0] + 0x100 end
    d[3] = d[3] - 1
  else
    P.runStored(s)
  end
end

-- pokefirered/src/battle_anim_mons.c:701
function P.runStoredWhenAffineEnds(s)
  if s.affineAnimEnded then P.runStored(s) end
end

function P.runStoredWhenAnimEnds(s)
  if s.animEnded then P.runStored(s) end
end

-- pokefirered/src/sprite.c:897
local function frame_tiles(s)
  local bw = s._baseW or s.w or 16
  local bh = s._baseH or s.h or 16
  return bw, bh
end

function P.Random()
  local ok, Rng = pcall(require, "src.core.game3.rng")
  if ok and Rng and Rng.Random then return Rng.Random() end
  return math.random(0, 0xFFFF)
end

function P.drawTileRun(s, vm)
  local img = s.image
  if not img or s.visible == false then return end
  local bw, bh = frame_tiles(s)
  local iw, ih = img:getDimensions()
  local tw = math.max(1, floor(iw / 8))
  local cols, rows = math.max(1, floor(bw / 8)), math.max(1, floor(bh / 8))
  s._runQuads = s._runQuads or {}
  love.graphics.push()
  love.graphics.translate(floor(s.x + (s.ox or 0) + 0.5), floor(s.y + (s.oy or 0) + 0.5))
  love.graphics.rotate(s.rotation or 0)
  love.graphics.scale((s.scaleX or 1) * (s.hFlip and -1 or 1), (s.scaleY or 1) * (s.vFlip and -1 or 1))
  love.graphics.setColor(1, 1, 1, s._drawAlpha or s.alpha or 1)
  local pimg = AnimPal.beginSprite(s, img, vm)
  if pimg then img = pimg end
  for r = 0, rows - 1 do
    for c = 0, cols - 1 do
      local idx = s._tileRun + r * cols + c
      local q = s._runQuads[idx]
      if not q then
        q = love.graphics.newQuad((idx % tw) * 8, floor(idx / tw) * 8, 8, 8, iw, ih)
        s._runQuads[idx] = q
      end
      love.graphics.draw(img, q, c * 8 - bw / 2, r * 8 - bh / 2)
    end
  end
  if pimg then AnimPal.finish() end
  love.graphics.pop()
end

function P.applyTile(s, tile)
  if tile == nil or tile < 0 then return end
  local bw = frame_tiles(s)
  local iw = s._sheetW
  if not iw and s.image and s.image.getWidth then iw = s.image:getWidth() end
  iw = iw or bw
  local tilesWide = math.max(1, floor(iw / 8))
  s._tile = tile
  s.quadX = (tile % tilesWide) * 8
  s.quadY = floor(tile / tilesWide) * 8
  if s.quadX + bw > iw then
    s._tileRun = tile
    s.customDraw = P.drawTileRun
  elseif s.customDraw == P.drawTileRun then
    s._tileRun = nil
    s.customDraw = nil
  end
end

function P.addTile(s, n)
  P.applyTile(s, (s._tile or 0) + n)
end

local function apply_flip(s, cmd)
  if s.affineMode and s.affineMode ~= 0 then return end
  local hf = cmd.h and true or false
  local vf = cmd.v and true or false
  s.hFlip = (hf ~= (s.pretHFlip and true or false))
  s.vFlip = (vf ~= (s.pretVFlip and true or false))
end

local function anim_frame(s, cmd)
  local dur = cmd.d or 0
  if dur > 0 then dur = dur - 1 end
  s.animDelayCounter = dur
  apply_flip(s, cmd)
  P.applyTile(s, cmd.f)
end

local ANIM_CMD

local function continue_anim(s)
  local anims = s._g4a and s._g4a[s.animNum or 0]
  if not anims then return end
  if (s.animDelayCounter or 0) > 0 then
    if not s.animPaused then s.animDelayCounter = s.animDelayCounter - 1 end
    local c = anims[(s.animCmdIndex or 0) + 1]
    if c and c.f then apply_flip(s, c) end
  elseif not s.animPaused then
    s.animCmdIndex = (s.animCmdIndex or 0) + 1
    local c = anims[s.animCmdIndex + 1]
    if not c then
      s.animCmdIndex = s.animCmdIndex - 1
      s.animEnded = true
      return
    end
    ANIM_CMD(s, anims, c)
  end
end

local function jump_to_loop_top(s, anims)
  if (s.animLoopCounter or 0) ~= 0 then
    s.animCmdIndex = s.animCmdIndex - 1
    while true do
      local prev = anims[s.animCmdIndex]
      if prev and prev.loop ~= nil then break end
      if s.animCmdIndex == 0 then break end
      s.animCmdIndex = s.animCmdIndex - 1
    end
    s.animCmdIndex = s.animCmdIndex - 1
  end
end

ANIM_CMD = function(s, anims, c)
  if c.e then
    s.animCmdIndex = s.animCmdIndex - 1
    s.animEnded = true
  elseif c.jump ~= nil then
    s.animCmdIndex = c.jump
    local f = anims[s.animCmdIndex + 1]
    if f then anim_frame(s, f) end
  elseif c.loop ~= nil then
    if (s.animLoopCounter or 0) ~= 0 then
      s.animLoopCounter = s.animLoopCounter - 1
    else
      s.animLoopCounter = c.loop
    end
    jump_to_loop_top(s, anims)
    continue_anim(s)
  else
    anim_frame(s, c)
  end
end

local function begin_anim(s)
  local anims = s._g4a and s._g4a[s.animNum or 0]
  s.animCmdIndex = 0
  s.animEnded = false
  s.animLoopCounter = 0
  if not anims then return end
  local c = anims[1]
  if c and c.f ~= nil and c.f ~= -1 then
    s.animBeginning = false
    anim_frame(s, c)
  end
end

function P.startAnim(s, num)
  s.animNum = num
  s.animBeginning = true
  s.animEnded = false
end

-- pokefirered/src/sprite.c:1360
function P.seekAnim(s, idx)
  local paused = s.animPaused
  s.animCmdIndex = idx - 1
  s.animDelayCounter = 0
  s.animBeginning = false
  s.animEnded = false
  s.animPaused = false
  continue_anim(s)
  if (s.animDelayCounter or 0) ~= 0 then s.animDelayCounter = s.animDelayCounter + 1 end
  s.animPaused = paused
end

local function convert_scale(scale)
  if scale == 0 then return 0 end
  return P.s16(P.cdiv(0x10000, scale))
end

function P.setMatrix(s, sxParam, syParam, rot)
  s._mat = s._mat or {}
  s._mat.sx, s._mat.sy, s._mat.rot = sxParam, syParam, rot
  s.scaleX = sxParam ~= 0 and (256 / sxParam) or 0
  s.scaleY = syParam ~= 0 and (256 / syParam) or 0
  s.rotation = -(P.u16(rot) / 65536) * 2 * math.pi
end

local function aff_update_matrix(s)
  local a = s._g4as
  P.setMatrix(s, convert_scale(a.xScale), convert_scale(a.yScale), a.rotation)
end

local function aff_apply_rel(s, cmd)
  local a = s._g4as
  a.xScale = P.s16(a.xScale + (cmd.xs or 0))
  a.yScale = P.s16(a.yScale + (cmd.ys or 0))
  a.rotation = band(a.rotation + lshift(cmd.r or 0, 8), 0xFF00)
  aff_update_matrix(s)
end

local function aff_apply_frame(s, cmd)
  local a = s._g4as
  local dur = cmd.d or 0
  if dur ~= 0 then
    aff_apply_rel(s, cmd)
    a.delay = dur - 1
  else
    a.xScale = cmd.xs or 0
    a.yScale = cmd.ys or 0
    a.rotation = band(lshift(cmd.r or 0, 8), 0xFFFF)
    aff_apply_rel(s, {})
    a.delay = 0
  end
end

local AFF_CMD

local function continue_affine(s)
  local a = s._g4as
  local cmds = s._g4af and s._g4af[a.animNum or 0]
  if not cmds then return end
  if (a.delay or 0) > 0 then
    if not s.affineAnimPaused then
      a.delay = a.delay - 1
      local c = cmds[a.idx + 1]
      if c then aff_apply_rel(s, c) end
    end
  elseif s.affineAnimPaused then
    return
  else
    a.idx = a.idx + 1
    local c = cmds[a.idx + 1]
    if not c then
      a.idx = a.idx - 1
      s.affineAnimEnded = true
      return
    end
    AFF_CMD(s, cmds, c)
  end
end

AFF_CMD = function(s, cmds, c)
  local a = s._g4as
  if c.e then
    s.affineAnimEnded = true
    a.idx = a.idx - 1
    aff_apply_rel(s, {})
  elseif c.jump ~= nil then
    a.idx = c.jump
    local f = cmds[a.idx + 1]
    if f then aff_apply_frame(s, f) end
  elseif c.loop ~= nil then
    if (a.loop or 0) ~= 0 then
      a.loop = a.loop - 1
    else
      a.loop = c.loop
    end
    if a.loop ~= 0 then
      a.idx = a.idx - 1
      while true do
        local prev = cmds[a.idx]
        if prev and prev.loop ~= nil then break end
        if a.idx == 0 then break end
        a.idx = a.idx - 1
      end
      a.idx = a.idx - 1
    end
    continue_affine(s)
  else
    aff_apply_frame(s, c)
  end
end

local function begin_affine(s)
  local a = s._g4as
  local cmds = s._g4af and s._g4af[a.animNum or 0]
  if not cmds or not cmds[1] then return end
  a.idx = 0
  a.delay = 0
  a.loop = 0
  s.affineAnimBeginning = false
  s.affineAnimEnded = false
  aff_apply_frame(s, cmds[1])
end

local function aff_state(s)
  if not s._g4as then
    s._g4as = { animNum = 0, idx = 0, delay = 0, loop = 0, xScale = 0x100, yScale = 0x100, rotation = 0 }
  end
  return s._g4as
end

-- pokefirered/src/sprite.c:1363
function P.startAffineAnim(s, num)
  local a = aff_state(s)
  a.animNum = num
  a.idx = 0
  a.delay = 0
  a.loop = 0
  a.xScale = 0x100
  a.yScale = 0x100
  a.rotation = 0
  s.affineAnimBeginning = true
  s.affineAnimEnded = false
end

function P.changeAffineAnim(s, num)
  local a = aff_state(s)
  a.animNum = num
  s.affineAnimBeginning = true
  s.affineAnimEnded = false
end

-- pokefirered/src/battle_anim_mons.c:1244
function P.trySetRotScale(s, xs, ys, rot)
  if s.affineMode and s.affineMode ~= 0 then
    s.affineAnimPaused = true
    P.setMatrix(s, xs, ys, rot)
  end
end

function P.tryResetAffine(s)
  P.trySetRotScale(s, 0x100, 0x100, 0)
  s.affineAnimPaused = false
end

-- pokefirered/src/sprite.c:897
function P.animate(s)
  if s._g4a then
    if s.animBeginning then begin_anim(s) else continue_anim(s) end
  end
  if s._g4af and s.affineMode and s.affineMode ~= 0 then
    aff_state(s)
    if s.affineAnimBeginning then begin_affine(s) else continue_affine(s) end
  end
end

AnimSprites.animate = P.animate

function P.hasAnims(s)
  return s._g4anim == true
end

function P.setupTemplate(s, tpl)
  if s._g4tpl == tpl then return end
  s._g4tpl = tpl
  s._g4a = tpl.anims
  s._g4af = tpl.affine
  s._g4anim = true
  s.affineMode = tpl.affineMode or 0
  s.objBlend = tpl.objBlend and true or false
  s.animNum = 0
  s.animCmdIndex = 0
  s.animDelayCounter = 0
  s.animLoopCounter = 0
  s.animEnded = false
  s.animPaused = false
  s.animBeginning = true
  s._g4as = nil
  s.affineAnimPaused = false
  s.affineAnimEnded = false
  s.affineAnimBeginning = true
  s.pretHFlip = false
  s.pretVFlip = false
  s.hFlip = false
  s.vFlip = false
  s.scaleX = 1
  s.scaleY = 1
  s.rotation = 0
  if tpl.priority then P.setPriority(s, tpl.priority, s.subpriority) end
  if tpl.anims and tpl.anims[0] and tpl.anims[0][1] then
    P.applyTile(s, tpl.anims[0][1].f or 0)
  else
    P.applyTile(s, 0)
  end
end

function P.setHFlip(s, v)
  s.pretHFlip = v and true or false
  if not (s.affineMode and s.affineMode ~= 0) then s.hFlip = s.pretHFlip end
end

function P.setVFlip(s, v)
  s.pretVFlip = v and true or false
  if not (s.affineMode and s.affineMode ~= 0) then s.vFlip = s.pretVFlip end
end

function P.tagImage(vm, tag)
  local pack = vm and vm._pack
  local t = pack and pack.tags and pack.tags[tag]
  return t and t.image or nil, t
end

function P.createSprite(vm, tag, tpl, x, y, subpriority, cb, w, h)
  local img, info = P.tagImage(vm, tag)
  local sheetW = info and info.w
  local fw = w or (info and info.frameW) or 16
  if img then
    local AnimVm = package.loaded["src.core.game3.battle.anim_vm"]
    if AnimVm and AnimVm.sheetImage then img, sheetW = AnimVm.sheetImage(vm, tag, fw) end
  end
  local s = AnimSprites.acquire({
    x = x,
    y = y,
    image = img,
    tag = tag,
    w = w or (info and info.frameW) or 16,
    h = h or (info and info.frameH) or 16,
    subpriority = subpriority or 0,
  })
  if not s then return nil end
  s._baseW = w or (info and info.frameW) or 16
  s._baseH = h or (info and info.frameH) or 16
  s._sheetW = sheetW
  s._vm = vm
  s._pz = true
  s._g4counted = nil
  s._g4tpl = nil
  s.ox, s.oy = 0, 0
  s.subpriority = subpriority or 0
  P.setPriority(s, (tpl and tpl.priority) or 2, s.subpriority)
  if tpl then P.setupTemplate(s, tpl) end
  s.callback = cb or P.dummy
  return s
end

function P.se(id, pan)
  local ok, Audio = pcall(require, "src.core.game3.audio")
  if ok and Audio and Audio.playSe and id then
    pcall(Audio.playSe, id, { pan = pan })
  end
end

function P.present(side)
  local Anim = package.loaded["src.core.game3.battle.anim"] or require("src.core.game3.battle.anim")
  return Anim.present(side)
end

function P.stage()
  local Anim = package.loaded["src.core.game3.battle.anim"] or require("src.core.game3.battle.anim")
  return Anim.stage and Anim.stage() or nil
end

function P.setMonRotScale(p, xs, ys, rot)
  if not p then return end
  p.sx = xs ~= 0 and (256 / xs) or 0
  p.sy = ys ~= 0 and (256 / ys) or 0
  p.rotation = -(P.u16(rot) / 65536) * 2 * math.pi
  p._rsX, p._rsY, p._rsRot = xs, ys, rot
end

function P.resetMonRotScale(p)
  if not p then return end
  p.sx, p.sy, p.rotation = 1, 1, 0
  p._rsX, p._rsY, p._rsRot = 0x100, 0x100, 0
end

-- pokefirered/src/battle_anim_mons.c:1762
function P.monYOffsetFromYScale(p, side, vm)
  if not p then return end
  local sp = P.species(vm, side)
  local ok, PicCoords = pcall(require, "src.core.game3.battle.pic_coords")
  local yoff = 0
  if ok and type(PicCoords) == "table" and sp then
    if side == "player" then yoff = (PicCoords.back and PicCoords.back[tonumber(sp)]) or 0
    else yoff = (PicCoords.front and PicCoords.front[tonumber(sp)]) or 0 end
  end
  local var = 64 - yoff * 2
  local d = p._rsY or 0x100
  local rot = p._rsRot or 0
  d = P.s16(floor(d * math.cos(P.u16(rot) / 65536 * 2 * math.pi)))
  local var2 = d ~= 0 and P.cdiv(lshift(var, 8), d) or 0
  if var2 > 128 then var2 = 128 end
  p.oy = P.cdiv(var - var2, 2)
end

-- pokefirered/src/palette.c
function P.blend555(color, coeff, target)
  local r = band(color, 31)
  local g = band(rshift(color, 5), 31)
  local b = band(rshift(color, 10), 31)
  local tr = band(target, 31)
  local tg = band(rshift(target, 5), 31)
  local tb = band(rshift(target, 10), 31)
  r = r + arshift((tr - r) * coeff, 4)
  g = g + arshift((tg - g) * coeff, 4)
  b = b + arshift((tb - b) * coeff, 4)
  return bor(r, lshift(g, 5), lshift(b, 10))
end

function P.rgb(r, g, b)
  return bor(r, lshift(g, 5), lshift(b, 10))
end

function P.rgbFloats(c)
  c = tonumber(c) or 0
  return band(c, 31) / 31, band(rshift(c, 5), 31) / 31, band(rshift(c, 10), 31) / 31
end

function P.blendMon(side, coeff, color)
  local p = P.present(side)
  if not p then return end
  local r, g, b = P.rgbFloats(color)
  p.blendColor = { r, g, b }
  p.blendCoeff = (tonumber(coeff) or 0) / 16
  p.darken = (color == 0) and p.blendCoeff or 0
end

function P.setBattlers(vm, atkSide, tgtSide)
  if vm and vm.setBattlers then vm:setBattlers(atkSide, tgtSide) end
end

function P.ctx(vm)
  return (vm and vm.ctx) or {}
end

function P.band(a, b) return band(a, b) end
function P.bor(a, b) return bor(a, b) end
function P.bxor(a, b) return bxor(a, b) end
function P.lshift(a, b) return lshift(a, b) end
function P.rshift(a, b) return rshift(a, b) end

return P
