local P = {}

local bit = require("bit")
local AnimPal = require("src.core.game3.battle.anim_pal")
local AnimCoords = require("src.core.game3.battle.anim_coords")
P.band, P.bor, P.bxor, P.lshift, P.rshift = bit.band, bit.bor, bit.bxor, bit.lshift, bit.rshift

local SINE = {
  0, 6, 12, 18, 25, 31, 37, 43, 49, 56, 62, 68, 74, 80, 86, 92,
  97, 103, 109, 115, 120, 126, 131, 136, 142, 147, 152, 157, 162, 167, 171, 176,
  181, 185, 189, 193, 197, 201, 205, 209, 212, 216, 219, 222, 225, 228, 231, 234,
  236, 238, 241, 243, 244, 246, 248, 249, 251, 252, 253, 254, 255, 255, 256, 256,
  256, 256, 256, 255, 255, 254, 253, 252, 251, 249, 248, 246, 244, 243, 241, 238,
  236, 234, 231, 228, 225, 222, 219, 216, 212, 209, 205, 201, 197, 193, 189, 185,
  181, 176, 171, 167, 162, 157, 152, 147, 142, 136, 131, 126, 120, 115, 109, 103,
  97, 92, 86, 80, 74, 68, 62, 56, 49, 43, 37, 31, 25, 18, 12, 6,
  0, -6, -12, -18, -25, -31, -37, -43, -49, -56, -62, -68, -74, -80, -86, -92,
  -97, -103, -109, -115, -120, -126, -131, -136, -142, -147, -152, -157, -162, -167, -171, -176,
  -181, -185, -189, -193, -197, -201, -205, -209, -212, -216, -219, -222, -225, -228, -231, -234,
  -236, -238, -241, -243, -244, -246, -248, -249, -251, -252, -253, -254, -255, -255, -256, -256,
  -256, -256, -256, -255, -255, -254, -253, -252, -251, -249, -248, -246, -244, -243, -241, -238,
  -236, -234, -231, -228, -225, -222, -219, -216, -212, -209, -205, -201, -197, -193, -189, -185,
  -181, -176, -171, -167, -162, -157, -152, -147, -142, -136, -131, -126, -120, -115, -109, -103,
  -97, -92, -86, -80, -74, -68, -62, -56, -49, -43, -37, -31, -25, -18, -12, -6,
}
P.SINE = SINE

local floor = math.floor

function P.s16(v)
  v = floor(v) % 65536
  if v >= 32768 then v = v - 65536 end
  return v
end
function P.u16(v) return floor(v) % 65536 end
function P.u8(v) return floor(v) % 256 end
function P.s8(v)
  v = floor(v) % 256
  if v >= 128 then v = v - 256 end
  return v
end
function P.shr(v, n) return floor(v / (2 ^ n)) end
function P.div(a, b)
  if b == 0 then return 0 end
  local q = a / b
  if q >= 0 then return floor(q) end
  return -floor(-q)
end
function P.mod(a, b)
  if b == 0 then return 0 end
  return a - P.div(a, b) * b
end
function P.abs(v) return v < 0 and -v or v end

-- pokefirered/src/trig.c:514
function P.Sin(index, amp)
  return P.s16(floor(SINE[(floor(index) % 256) + 1] * amp / 256))
end
function P.Cos(index, amp)
  return P.s16(floor(SINE[((floor(index) + 64) % 256) + 1] * amp / 256))
end
local SINE_DEG = { 0, 71, 143, 214, 286, 357, 428, 499, 570, 641, 711, 782, 852, 921, 991, 1060, 1129, 1198, 1266, 1334, 1401, 1468, 1534, 1600, 1666, 1731, 1796, 1860, 1923, 1986, 2048, 2110, 2171, 2231, 2290, 2349, 2408, 2465, 2522, 2578, 2633, 2687, 2741, 2793, 2845, 2896, 2946, 2996, 3044, 3091, 3138, 3183, 3228, 3271, 3314, 3355, 3396, 3435, 3474, 3511, 3547, 3582, 3617, 3650, 3681, 3712, 3742, 3770, 3798, 3824, 3849, 3873, 3896, 3917, 3937, 3956, 3974, 3991, 4006, 4021, 4034, 4046, 4056, 4065, 4073, 4080, 4086, 4090, 4093, 4095, 4096, 4095, 4093, 4090, 4086, 4080, 4073, 4065, 4056, 4046, 4034, 4021, 4006, 3991, 3974, 3956, 3937, 3917, 3896, 3873, 3849, 3824, 3798, 3770, 3742, 3712, 3681, 3650, 3617, 3582, 3547, 3511, 3474, 3435, 3396, 3355, 3314, 3271, 3228, 3183, 3138, 3091, 3044, 2996, 2946, 2896, 2845, 2793, 2741, 2687, 2633, 2578, 2522, 2465, 2408, 2349, 2290, 2231, 2171, 2110, 2048, 1986, 1923, 1860, 1796, 1731, 1666, 1600, 1534, 1468, 1401, 1334, 1266, 1198, 1129, 1060, 991, 921, 852, 782, 711, 641, 570, 499, 428, 357, 286, 214, 143, 71 }

-- pokefirered/src/trig.c:526
function P.Sin2(angle)
  angle = P.u16(angle)
  local v = SINE_DEG[(angle % 180) + 1] or 0
  if floor(angle / 180) % 2 == 1 then return -v end
  return v
end
function P.Cos2(deg) return P.Sin2(floor(deg) + 90) end

function P.ArcTan2(x, y)
  local a = math.atan2(y, x)
  if a < 0 then a = a + 2 * math.pi end
  return floor(a / (2 * math.pi) * 65536 + 0.5) % 65536
end
-- pokefirered/src/battle_anim_mons.c:1281
function P.ArcTan2Neg(x, y)
  return (-P.ArcTan2(x, y)) % 65536
end

function P.Random() return math.random(0, 65535) end

P.ANIM_ATTACKER, P.ANIM_TARGET, P.ANIM_ATK_PARTNER, P.ANIM_DEF_PARTNER = 0, 1, 2, 3
P.COORD_X, P.COORD_Y, P.COORD_X_2, P.COORD_Y_PIC, P.COORD_Y_PIC_DEF = 0, 1, 2, 3, 4
P.ARG_RET_ID = 7

local AnimMod = nil
local AnimSpritesMod = nil
local AnimTasksMod = nil

local function Anim()
  if not AnimMod then AnimMod = require("src.core.game3.battle.anim") end
  return AnimMod
end
P.Anim = Anim
function P.vm() return Anim()._vm end
function P.AnimSprites()
  if not AnimSpritesMod then AnimSpritesMod = require("src.core.game3.battle.anim_sprites") end
  return AnimSpritesMod
end
function P.AnimTasks()
  if not AnimTasksMod then
    AnimTasksMod = package.loaded["src.core.game3.battle.anim_tasks"] or require("src.core.game3.battle.anim_tasks")
  end
  return AnimTasksMod
end

function P.atk(vm)
  if vm.allyPair and vm:allyPair() then return vm:attackerId() end
  return vm:attackerSide()
end
function P.tgt(vm)
  if vm.allyPair and vm:allyPair() then return vm:targetId() end
  return vm:targetSide()
end
function P.side(vm, animBattler)
  animBattler = tonumber(animBattler) or 0
  if animBattler == 0 then return vm:attackerSide() end
  if animBattler == 1 then return vm:targetSide() end
  return nil
end
function P.isPlayer(side) return side == "player" end
function P.atkIsPlayer(vm) return vm:attackerSide() == "player" end
function P.tgtIsPlayer(vm) return vm:targetSide() == "player" end

local PicCoords
local function picCoords()
  if PicCoords == nil then
    local ok, m = pcall(require, "src.core.game3.battle.pic_coords")
    PicCoords = ok and m or false
  end
  return PicCoords or nil
end

local BASE = setmetatable({}, { __index = function(_, k) return AnimCoords.coords(nil, k) end })

function P.species(vm, side)
  local sp = vm and vm.speciesForSide and vm:speciesForSide(side)
  return tonumber(sp)
end

-- pokefirered/src/battle_anim_mons.c:148
function P.yDelta(vm, side)
  local pc = picCoords()
  local sp = P.species(vm, side)
  if not pc or not sp then return 0 end
  if side == "player" then return (pc.back and pc.back[sp]) or 0 end
  return (pc.front and pc.front[sp]) or 0
end

function P.elevation(vm, side)
  local pc = picCoords()
  local sp = P.species(vm, side)
  if side == "player" or not pc or not sp then return 0 end
  return (pc.elev and pc.elev[sp]) or 0
end

-- pokefirered/src/battle_anim_mons.c:105
function P.coord(vm, side, kind)
  local b = BASE[side] or BASE.enemy
  if kind == P.COORD_X or kind == P.COORD_X_2 then return b[1] end
  if kind == P.COORD_Y then return b[2] end
  local y = P.yDelta(vm, side)
  if side ~= "player" then y = y - P.elevation(vm, side) end
  y = P.u8(y + b[2])
  if kind == P.COORD_Y_PIC then
    if side == "player" then y = P.u8(y + 8) end
    if y > 104 then y = 104 end
  end
  return y
end

function P.coordAtk(vm, kind) return P.coord(vm, vm:attackerSide(), kind) end
function P.coordTgt(vm, kind) return P.coord(vm, vm:targetSide(), kind) end

-- pokefirered/src/battle_anim_mons.c:305
function P.yWithElevation(vm, side)
  local y = P.coord(vm, side, P.COORD_Y)
  if side ~= "player" then y = y - P.elevation(vm, side) end
  return y
end

P.yDelta = AnimCoords.sideArg(P.yDelta, 2)
P.elevation = AnimCoords.sideArg(P.elevation, 2)
P.coord = AnimCoords.sideArg(P.coord, 2)
P.yWithElevation = AnimCoords.sideArg(P.yWithElevation, 2)

-- pokefirered/src/battle_anim_mons.c:1908
function P.subpriorityOf(side)
  return AnimCoords.subpriority(side)
end

function P.atkId(vm) return vm:attackerId() end
function P.tgtId(vm) return vm:targetId() end

function P.monPresent(side)
  return Anim().present(side)
end

function P.monCenter(vm, side)
  local p = Anim().present(side)
  local Ui = package.loaded["src.core.game3.battle.ui"]
  local b = BASE[side] or BASE.enemy
  local cx, cy
  if Ui and Ui.battlerSpriteCenter then
    cx, cy = Ui.battlerSpriteCenter(side, P.species(vm, side), { x = b[1], y = b[2] })
  else
    cx, cy = b[1], P.coord(vm, side, P.COORD_Y_PIC_DEF)
  end
  return cx + ((p and p.ox) or 0), cy + ((p and p.oy) or 0)
end

function P.monImage(vm, side)
  local ok, Pokemon = pcall(require, "src.core.game3.pokemon")
  if not ok then return nil end
  local sp = P.species(vm, side)
  if not sp then return nil end
  local e
  local okU, Ui = pcall(require, "src.core.game3.battle.ui")
  if okU and Ui.battlerPic then e = Ui.battlerPic(side, nil, sp) end
  if not e and side == "player" and Pokemon.backPic then e = Pokemon.backPic(sp) end
  if not e and Pokemon.frontPic then e = Pokemon.frontPic(sp) end
  return e and e.image
end

-- pokefirered/src/battle_anim_mons.c:1174
function P.monRotScale(p, xs, ys, rot)
  if not p then return end
  xs = (xs == 0) and 1 or xs
  ys = (ys == 0) and 1 or ys
  p.sx = 256 / xs
  p.sy = 256 / ys
  p.rotation = -((rot or 0) % 65536) / 65536 * 2 * math.pi
  p._g3mat = { xs, ys, (rot or 0) % 65536 }
end

function P.monResetRotScale(p)
  if not p then return end
  p.sx, p.sy, p.rotation = 1, 1, 0
  p._g3mat = nil
end

local function matrixD(p)
  local m = p and p._g3mat
  if not m then return 256 end
  local c = SINE[((floor(m[3] / 256) + 64) % 256) + 1]
  return floor(m[2] * c / 256)
end

local function matrixC(p)
  local m = p and p._g3mat
  if not m then return 0 end
  local s = SINE[(floor(m[3] / 256) % 256) + 1]
  return floor(m[2] * s / 256)
end

-- pokefirered/src/battle_anim_mons.c:1762
function P.monYOffsetFromYScale(vm, side, otherSide)
  local p = Anim().present(side)
  if not p then return end
  local var = 64 - P.yDelta(vm, otherSide or side) * 2
  local d = matrixD(p)
  local var2 = (d == 0) and 0 or P.div(var * 256, d)
  if var2 > 128 then var2 = 128 end
  p.oy = P.div(var - var2, 2)
end

-- pokefirered/src/battle_anim_mons.c:1233
function P.monYOffsetFromRotation(side)
  local p = Anim().present(side)
  if not p then return end
  local c = matrixC(p)
  if c < 0 then c = -c end
  p.oy = P.shr(c, 3)
end

function P.setBld(vm, eva, evb)
  if not vm then return end
  if eva == nil then
    vm.bldAlpha = nil
  else
    vm.bldAlpha = { eva, evb or 0, eva = eva, evb = evb or 0 }
  end
end

function P.bldAlphaValue(vm)
  local b = vm and vm.bldAlpha
  if not b then return 1 end
  local a = (b.eva or b[1] or 16) / 16
  if a > 1 then a = 1 end
  if a < 0 then a = 0 end
  return a
end

function P.playSE(vm, se, pan)
  local ok, Audio = pcall(require, "src.core.game3.audio")
  if not ok or not se then return end
  if pan ~= nil then
    pcall(Audio.playSe, se, { pan = pan })
  else
    pcall(Audio.playSe, se)
  end
end

-- pokefirered/src/battle_anim.c:1160
function P.adjustPan(vm, pan)
  return vm:adjustPanning(pan)
end

function P.playSEPan(vm, se, pan)
  P.playSE(vm, se, vm:adjustPanning(pan))
end

local function tagInfo(vm, tag)
  if not tag then return nil end
  tag = tostring(tag):upper():gsub("^ANIM_TAG_", "")
  local pack = vm and vm._pack
  return pack and pack.tags and pack.tags[tag]
end

local sheetCache = setmetatable({}, { __mode = "k" })

function P.sheet(vm, tag, w, h)
  local info = tagInfo(vm, tag)
  local img = info and info.image
  if not img or not img.getDimensions then return img, 1 end
  local per = sheetCache[img]
  if not per then per = {}; sheetCache[img] = per end
  local key = w .. "x" .. h
  if per[key] then return per[key].image, per[key].frames end
  local iw, ih = img:getDimensions()
  if iw == w or not (love and love.graphics and love.graphics.newCanvas) then
    per[key] = { image = img, frames = math.max(1, floor(ih / h)) }
    return img, per[key].frames
  end
  local tw = floor(iw / 8)
  local total = tw * floor(ih / 8)
  local cw = math.max(1, floor(w / 8))
  local perFrame = cw * math.max(1, floor(h / 8))
  local nframes = math.max(1, floor(total / perFrame))
  local ok, canvas = pcall(love.graphics.newCanvas, w, h * nframes)
  if not ok or not canvas then
    per[key] = { image = img, frames = 1 }
    return img, 1
  end
  canvas:setFilter("nearest", "nearest")
  local function relay(src, dstCanvas)
    love.graphics.push("all")
    love.graphics.setCanvas(dstCanvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.origin()
    love.graphics.setShader()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setBlendMode("replace", "premultiplied")
    for t = 0, nframes * perFrame - 1 do
      local f = floor(t / perFrame)
      local r = t % perFrame
      local dx = (r % cw) * 8
      local dy = f * h + floor(r / cw) * 8
      local q = love.graphics.newQuad((t % tw) * 8, floor(t / tw) * 8, 8, 8, iw, ih)
      love.graphics.draw(src, q, dx, dy)
    end
    love.graphics.pop()
  end
  relay(img, canvas)
  local idxImg, idxTag = AnimPal.indexImage(img)
  if idxImg then
    local okc, ic = pcall(love.graphics.newCanvas, w, h * nframes)
    if okc and ic then
      ic:setFilter("nearest", "nearest")
      relay(idxImg, ic)
      AnimPal.register(canvas, ic, idxTag)
    end
  end
  per[key] = { image = canvas, frames = nframes }
  return canvas, nframes
end

local DATA
function P.data()
  if not DATA then DATA = require("src.core.game3.battle.anim_port.g3_data") end
  return DATA
end

function P.template(name)
  return name and P.data().templates[tostring(name)]
end

local function destroy(s)
  P.AnimSprites().release(s)
end
P.DestroyAnimSprite = destroy
P.DestroySpriteAndMatrix = destroy

-- pokefirered/src/battle_anim.c:630
function P.zFor(pri, sub, vm)
  pri = pri or 2
  sub = sub or 0
  if pri <= 1 then
    local z = 900 + (2 - pri) * 40 + (100 - sub) * 0.1
    if z > 998 then z = 998 end
    return z
  elseif pri >= 3 then
    return 2 + (100 - sub) * 0.01
  end
  return AnimCoords.layerZ(sub, vm and vm._monbg, vm and vm._bgPrio)
end

-- pokefirered/src/sprite.c:905
local function beginAnim(s)
  local A = s._anims
  local cmds = A and A[(s.animNum or 0) + 1]
  s.animCmdIndex = 0
  s.animEnded = false
  s.animLoopCounter = 0
  s.animBeginning = false
  if not cmds then return end
  local c = cmds[1]
  if c and c.f then
    local d = c.d or 0
    if d > 0 then d = d - 1 end
    s.animDelayCounter = d
    s.animH, s.animV = c.h == 1, c.v == 1
    s.imageValue = c.f
  end
end

local continueAnim

local function jumpToTopOfAnimLoop(s, cmds)
  if s.animLoopCounter ~= 0 then
    s.animCmdIndex = s.animCmdIndex - 1
    while true do
      local prev = cmds[s.animCmdIndex]
      if prev and prev.l then break end
      if s.animCmdIndex == 0 then break end
      s.animCmdIndex = s.animCmdIndex - 1
    end
    s.animCmdIndex = s.animCmdIndex - 1
  end
end

continueAnim = function(s)
  local A = s._anims
  local cmds = A and A[(s.animNum or 0) + 1]
  if not cmds then return end
  if (s.animDelayCounter or 0) > 0 then
    if not s.animPaused then s.animDelayCounter = s.animDelayCounter - 1 end
    local c = cmds[s.animCmdIndex + 1]
    if c and c.f then s.animH, s.animV = c.h == 1, c.v == 1 end
  elseif not s.animPaused then
    s.animCmdIndex = s.animCmdIndex + 1
    local c = cmds[s.animCmdIndex + 1]
    if not c or c.e then
      s.animCmdIndex = s.animCmdIndex - 1
      s.animEnded = true
    elseif c.j then
      s.animCmdIndex = c.j
      local f = cmds[s.animCmdIndex + 1]
      if f and f.f then
        local d = f.d or 0
        if d > 0 then d = d - 1 end
        s.animDelayCounter = d
        s.animH, s.animV = f.h == 1, f.v == 1
        s.imageValue = f.f
      end
    elseif c.l then
      if (s.animLoopCounter or 0) ~= 0 then
        s.animLoopCounter = s.animLoopCounter - 1
      else
        s.animLoopCounter = c.l
      end
      jumpToTopOfAnimLoop(s, cmds)
      continueAnim(s)
    elseif c.f then
      local d = c.d or 0
      if d > 0 then d = d - 1 end
      s.animDelayCounter = d
      s.animH, s.animV = c.h == 1, c.v == 1
      s.imageValue = c.f
    end
  end
end

local function affCmds(s)
  local F = s._affine
  return F and F[(s.affAnimNum or 0) + 1]
end

local function affApplyRelative(s, x, y, r)
  s.affX = P.s16((s.affX or 256) + x)
  s.affY = P.s16((s.affY or 256) + y)
  s.affRot = P.band(P.u16((s.affRot or 0) + P.lshift(r, 8)), 0xFF00)
end

local function affApplyFrame(s, c)
  local d = c.d or 0
  if d > 0 then
    d = d - 1
    affApplyRelative(s, c.x, c.y, c.r)
  else
    s.affX, s.affY, s.affRot = c.x, c.y, P.u16(P.lshift(c.r, 8))
    affApplyRelative(s, 0, 0, 0)
  end
  return d
end

-- pokefirered/src/sprite.c:1063
local function beginAffineAnim(s)
  local cmds = affCmds(s)
  if not (s._aff and s._aff ~= 0) or not cmds then return end
  s.affCmdIndex, s.affDelay, s.affLoop = 0, 0, 0
  s.affineAnimBeginning = false
  s.affineAnimEnded = false
  local c = cmds[1]
  if c and c.x then
    s.affDelay = affApplyFrame(s, c)
  elseif c and c.e then
    s.affineAnimEnded = true
  end
end

local continueAffineAnim
continueAffineAnim = function(s)
  if not (s._aff and s._aff ~= 0) then return end
  local cmds = affCmds(s)
  if not cmds then return end
  if (s.affDelay or 0) > 0 then
    if not s.affineAnimPaused then
      s.affDelay = s.affDelay - 1
      local c = cmds[s.affCmdIndex + 1]
      if c and c.x then affApplyRelative(s, c.x, c.y, c.r) end
    end
  elseif s.affineAnimPaused then
    return
  else
    s.affCmdIndex = s.affCmdIndex + 1
    local c = cmds[s.affCmdIndex + 1]
    if not c or c.e then
      s.affineAnimEnded = true
      s.affCmdIndex = s.affCmdIndex - 1
    elseif c.j then
      s.affCmdIndex = c.j
      local f = cmds[s.affCmdIndex + 1]
      if f and f.x then s.affDelay = affApplyFrame(s, f) end
    elseif c.l then
      if (s.affLoop or 0) ~= 0 then
        s.affLoop = s.affLoop - 1
      else
        s.affLoop = c.l
      end
      if s.affLoop ~= 0 then
        s.affCmdIndex = s.affCmdIndex - 1
        while true do
          local prev = cmds[s.affCmdIndex]
          if prev and prev.l then break end
          if s.affCmdIndex == 0 then break end
          s.affCmdIndex = s.affCmdIndex - 1
        end
        s.affCmdIndex = s.affCmdIndex - 1
      end
      continueAffineAnim(s)
    elseif c.x then
      s.affDelay = affApplyFrame(s, c)
    end
  end
end

-- pokefirered/src/sprite.c:897
function P.animate(s)
  if s._anims then
    if s.animBeginning then beginAnim(s) else continueAnim(s) end
  end
  if s._aff and s._aff ~= 0 and s._affine then
    if s.affineAnimBeginning then beginAffineAnim(s) else continueAffineAnim(s) end
  end
end

function P.StartSpriteAnim(s, n)
  s.animNum = n
  s.animBeginning = true
  s.animEnded = false
end

-- pokefirered/src/sprite.c:1349
function P.SeekSpriteAnim(s, idx)
  local paused = s.animPaused
  s.animCmdIndex = idx - 1
  s.animDelayCounter = 0
  s.animBeginning = false
  s.animEnded = false
  s.animPaused = false
  continueAnim(s)
  if (s.animDelayCounter or 0) > 0 then s.animDelayCounter = s.animDelayCounter + 1 end
  s.animPaused = paused
end

function P.StartSpriteAffineAnim(s, n)
  s.affAnimNum = n
  s.affCmdIndex, s.affDelay, s.affLoop = 0, 0, 0
  s.affX, s.affY, s.affRot = 256, 256, 0
  s.affineAnimBeginning = true
  s.affineAnimEnded = false
end

function P.ChangeSpriteAffineAnim(s, n)
  s.affAnimNum = n
  s.affineAnimBeginning = true
  s.affineAnimEnded = false
end

-- pokefirered/src/battle_anim_mons.c:1244
function P.TrySetSpriteRotScale(s, recalc, xs, ys, rot)
  if s._aff and (s._aff % 2) == 1 then
    s.affineAnimPaused = true
    s._mat = { xs, ys, P.u16(rot or 0) }
  end
end

function P.TryResetSpriteAffineState(s)
  P.TrySetSpriteRotScale(s, true, 256, 256, 0)
  s._mat = nil
  s.affX, s.affY, s.affRot = 256, 256, 0
  s.affineAnimPaused = false
end

function P.sync(s, vm)
  local cellH = s._baseH or s.h or 32
  local per = math.max(1, floor((s._baseW or 32) / 8) * floor(cellH / 8))
  local frame = floor((s.imageValue or 0) / per)
  if s._frames and frame >= s._frames then frame = s._frames - 1 end
  s.quadX = 0
  s.quadY = frame * cellH
  local affOn = s._aff and s._aff ~= 0
  if affOn then
    s.hFlip = s._hFlipBase and true or false
    s.vFlip = s._vFlipBase and true or false
    if s._mat then
      local m = s._mat
      s.scaleX = 256 / ((m[1] == 0) and 1 or m[1])
      s.scaleY = 256 / ((m[2] == 0) and 1 or m[2])
      s.rotation = -(m[3] / 65536) * 2 * math.pi
    else
      s.scaleX = (s.affX or 256) / 256
      s.scaleY = (s.affY or 256) / 256
      s.rotation = -((s.affRot or 0) / 65536) * 2 * math.pi
    end
  else
    s.hFlip = (s.animH and true or false) ~= (s._hFlipBase and true or false)
    s.vFlip = (s.animV and true or false) ~= (s._vFlipBase and true or false)
    s.scaleX, s.scaleY, s.rotation = 1, 1, 0
  end
  s.visible = not s.invisible and not s._objWindow
  if s.zOverride then
    s.z = s.zOverride
  else
    s.z = P.zFor(s.pri, s.sub, vm)
  end
  s.subpriority = 0
  s.objBlend = s._objBlend and true or nil
  s.alpha = s.alphaMul or 1
end

local function setup(s, vm, tmplName)
  for i = 0, 7 do s.data[i] = 0 end
  local T = P.template(tmplName or s.template) or {}
  s._tmpl = T
  s._anims = T.anims
  s._affine = T.affine
  s._aff = T.aff or 0
  s._objBlend = T.blend == 1
  s._g3 = true
  s.palBlend = nil
  local w = T.w or s._baseW or s.w or 32
  local h = T.h or s._baseH or s.h or 32
  s._baseW, s._baseH = w, h
  s.w, s.h = w, h
  s.originX, s.originY = nil, nil
  s.ox, s.oy = 0, 0
  s.invisible = false
  s.alphaMul = nil
  s.zOverride = nil
  s.blendMode = "alpha"
  s._hFlipBase, s._vFlipBase = false, false
  s.hFlip, s.vFlip = false, false
  s.animNum, s.animCmdIndex, s.animDelayCounter, s.animLoopCounter = 0, 0, 0, 0
  s.animBeginning, s.animEnded, s.animPaused = true, false, false
  s.animH, s.animV = false, false
  s.imageValue = 0
  s.affAnimNum, s.affCmdIndex, s.affDelay, s.affLoop = 0, 0, 0, 0
  s.affX, s.affY, s.affRot = 256, 256, 0
  s.affineAnimBeginning = s._aff ~= 0 and s._affine ~= nil
  s.affineAnimEnded = false
  s.affineAnimPaused = false
  s._mat = nil
  local tag = T.tag or s.tag
  if tag and vm then
    local img, frames = P.sheet(vm, tag, w, h)
    if img then s.image = img end
    s._frames = frames
    s.quad = nil
  end
  s.pri = 2
  s.callbackData = nil
end

local function argsOf(list)
  local ga = {}
  for i = 0, 7 do ga[i] = 0 end
  if list then
    for k, v in ipairs(list) do
      if k <= 8 then ga[k - 1] = tonumber(v) or 0 end
    end
  end
  return ga
end
P.argsOf = argsOf

local function vmSubpriority(s, vm)
  local op = s._op
  local off = tonumber(op and op.subpriority) or tonumber(s.subpriority) or 2
  local ab = op and op.animBattler
  local side
  if ab == nil then
    side = s._anchorSide or vm:targetSide()
  else
    side = vm:resolveBattlerSide(ab)
  end
  side = side or vm:targetSide()
  local base = P.subpriorityOf(side)
  local sub
  if off >= 64 then sub = base + (off - 64) else sub = base - off end
  if sub < 3 then sub = 3 end
  return sub
end

local tokN = 0
local function newTok()
  tokN = tokN + 1
  return tokN
end

local function runStep(s, vm)
  local fn = s.callbackFn
  if fn then fn(s, vm) end
end

-- pokefirered/src/sprite.c:583
function P.cb(entry)
  return function(s)
    local vm = s._vm or P.vm()
    if not vm then return end
    if not s._inited then
      s._inited = true
      s._vm = vm
      setup(s, vm, s.template)
      s.x = P.coordTgt(vm, P.COORD_X_2)
      s.y = P.coordTgt(vm, P.COORD_Y_PIC)
      if s._args then
        s.ga = argsOf(s._args)
      else
        s.ga = {}
        for i = 0, 7 do s.ga[i] = tonumber(vm.args and vm.args[i]) or 0 end
      end
      s.sub = vmSubpriority(s, vm)
      s.callbackFn = entry
      s._g3tok = newTok()
    end
    local tok = s._g3tok
    runStep(s, vm)
    if not (s.active and s._inited and s._g3tok == tok) then return end
    P.animate(s)
    P.sync(s, vm)
  end
end

function P.setCallback(s, fn)
  s.callbackFn = fn
end

local function genericCallback(s)
  local vm = s._vm or P.vm()
  if not vm then return end
  s._inited = true
  local tok = s._g3tok
  runStep(s, vm)
  if not (s.active and s._inited and s._g3tok == tok) then return end
  P.animate(s)
  P.sync(s, vm)
end
P.genericCallback = genericCallback

function P.CreateSprite(vm, tmplName, x, y, sub, fn, opts)
  opts = opts or {}
  local AnimSprites = P.AnimSprites()
  local T = P.template(tmplName) or {}
  local s = AnimSprites.acquire({
    x = x, y = y, z = 150, template = tmplName, tag = T.tag,
    w = T.w or 32, h = T.h or 32, hostId = opts.hostId,
    callback = genericCallback,
  })
  if not s then return nil end
  s._args = nil
  s._op = nil
  s._vm = vm
  s._baseW, s._baseH = T.w or 32, T.h or 32
  setup(s, vm, tmplName)
  s.x, s.y = x, y
  s.sub = sub or 2
  s.ga = opts.ga or argsOf(nil)
  s.callbackFn = fn
  s._g3tok = newTok()
  s._inited = false
  if opts.animate then
    s._inited = true
    runStep(s, vm)
    if s.active then
      P.animate(s)
      P.sync(s, vm)
    end
  else
    P.sync(s, vm)
  end
  return s
end

function P.spriteReady(s)
  if s and not s._g3tok then s._g3tok = newTok() end
end

-- pokefirered/src/battle_anim_mons.c:1517
function P.CloneMon(vm, side)
  local AnimSprites = P.AnimSprites()
  local p = Anim().present(side)
  if not p then return nil end
  local cx, cy = P.monCenter(vm, side)
  local img = P.monImage(vm, side)
  local s = AnimSprites.acquire({
    x = cx, y = cy, z = AnimCoords.monBehindZ(side), hostId = side,
    w = 64, h = 64, image = img, callback = genericCallback,
  })
  if not s then return nil end
  s._args, s._op = nil, nil
  s._vm = vm
  s._baseW, s._baseH = 64, 64
  s.template = nil
  setup(s, vm, "__clone")
  s.image = img
  s._frames = 1
  s.x, s.y = cx, cy
  s.ox, s.oy = 0, 0
  s._aff = 3
  s._objBlend = true
  s.zOverride = (side == "player") and 195 or 95
  s.isClone = side
  s.ga = argsOf(nil)
  s.callbackFn = nil
  s._g3tok = newTok()
  s._inited = true
  if p then
    s._mat = { math.floor(256 / (p.sx ~= 0 and p.sx or 1)), math.floor(256 / (p.sy ~= 0 and p.sy or 1)), 0 }
    if s._mat[1] == 256 and s._mat[2] == 256 then s._mat = nil end
  end
  P.sync(s, vm)
  return s
end

function P.task(entry)
  return function(t, vm)
    if not t._inited then
      t._inited = true
      local ga = {}
      for i = 0, 7 do
        local v = t.data[i]
        if type(v) == "string" then
          local s = v:lower()
          if s:find("target") then v = 1 elseif s:find("attacker") then v = 0 else v = tonumber(v) or 0 end
        end
        ga[i] = tonumber(v) or 0
      end
      t.ga = ga
      for i = 0, 15 do t.data[i] = 0 end
      t.fn = entry
      t._g3 = {}
    end
    t.fn(t, vm)
  end
end

function P.DestroyAnimVisualTask(t)
  P.AnimTasks()._destroy(t)
end

local BG_PRIO_Z = { [0] = 999, [1] = 850, [2] = 3, [3] = 2 }
function P.bgZ(prio) return BG_PRIO_Z[prio] or 2 end

-- pokefirered/src/battle_anim_mons.c:926
function P.bg1Layer(t, vm, key, prio, palOverride)
  AnimPal.bgLoad("bg1", key, palOverride)
  t.z = P.bgZ(prio)
  t._bg1key = key
  t.draw = function(tt, v)
    AnimPal.bgLayerDraw(tt._bg1key, "bg1", tt._bg1x or 0, tt._bg1y or 0, v or vm)
  end
end

function P.bg1Clear(t)
  t.draw = nil
  t._bg1key = nil
end

function P.setRet(vm, v)
  if vm and vm.args then vm.args[P.ARG_RET_ID] = v end
end

function P.retVal(vm)
  return (vm and vm.args and tonumber(vm.args[P.ARG_RET_ID])) or 0
end


function P.StoreSpriteCallbackInData6(s, fn)
  s._stored = fn
end

function P.SetCallbackToStoredInData6(s)
  s.callbackFn = s._stored
end

-- pokefirered/src/battle_anim_mons.c:521
function P.WaitAnimForDuration(s)
  if s.data[0] > 0 then
    s.data[0] = s.data[0] - 1
  else
    P.SetCallbackToStoredInData6(s)
  end
end

function P.RunStoredCallbackWhenAnimEnds(s)
  if s.animEnded then P.SetCallbackToStoredInData6(s) end
end

function P.RunStoredCallbackWhenAffineAnimEnds(s)
  if s.affineAnimEnded then P.SetCallbackToStoredInData6(s) end
end

function P.DestroyAnimSpriteAndDisableBlend(s, vm)
  P.setBld(vm or s._vm, nil)
  destroy(s)
end

function P.DestroyAnimVisualTaskAndDisableBlend(t, vm)
  P.setBld(vm, nil)
  P.DestroyAnimVisualTask(t)
end

-- pokefirered/src/battle_anim_mons.c:412
function P.TranslateSpriteInCircle(s)
  local d = s.data
  if d[3] ~= 0 then
    s.ox = P.Sin(d[0], d[1])
    s.oy = P.Cos(d[0], d[1])
    d[0] = d[0] + d[2]
    if d[0] >= 256 then d[0] = d[0] - 256 elseif d[0] < 0 then d[0] = d[0] + 256 end
    d[3] = d[3] - 1
  else
    P.SetCallbackToStoredInData6(s)
  end
end

function P.TranslateSpriteInGrowingCircle(s)
  local d = s.data
  if d[3] ~= 0 then
    s.ox = P.Sin(d[0], P.shr(d[5], 8) + d[1])
    s.oy = P.Cos(d[0], P.shr(d[5], 8) + d[1])
    d[0] = d[0] + d[2]
    d[5] = P.s16(d[5] + d[4])
    if d[0] >= 256 then d[0] = d[0] - 256 elseif d[0] < 0 then d[0] = d[0] + 256 end
    d[3] = d[3] - 1
  else
    P.SetCallbackToStoredInData6(s)
  end
end

function P.TranslateSpriteInEllipse(s)
  local d = s.data
  if d[3] ~= 0 then
    s.ox = P.Sin(d[0], d[1])
    s.oy = P.Cos(d[0], d[4])
    d[0] = d[0] + d[2]
    if d[0] >= 256 then d[0] = d[0] - 256 elseif d[0] < 0 then d[0] = d[0] + 256 end
    d[3] = d[3] - 1
  else
    P.SetCallbackToStoredInData6(s)
  end
end

-- pokefirered/src/battle_anim_mons.c:548
function P.ConvertPosDataToTranslateLinearData(s)
  local d = s.data
  if d[1] > d[2] then d[0] = -d[0] end
  local xDiff = d[2] - d[1]
  local old = d[0]
  d[0] = P.abs(P.div(xDiff, d[0]))
  d[2] = P.s16(P.div(d[4] - d[3], d[0]))
  d[1] = old
end

function P.TranslateSpriteLinear(s)
  local d = s.data
  if d[0] > 0 then
    d[0] = d[0] - 1
    s.ox = s.ox + d[1]
    s.oy = s.oy + d[2]
  else
    P.SetCallbackToStoredInData6(s)
  end
end

function P.TranslateSpriteLinearFixedPoint(s)
  local d = s.data
  if d[0] > 0 then
    d[0] = d[0] - 1
    d[3] = P.s16(d[3] + d[1])
    d[4] = P.s16(d[4] + d[2])
    s.ox = P.shr(d[3], 8)
    s.oy = P.shr(d[4], 8)
  else
    P.SetCallbackToStoredInData6(s)
  end
end

-- pokefirered/src/battle_anim_mons.c:977
function P.InitSpriteDataForLinearTranslation(s)
  local d = s.data
  local x = P.s16((d[2] - d[1]) * 256)
  local y = P.s16((d[4] - d[3]) * 256)
  d[1] = P.s16(P.div(x, d[0]))
  d[2] = P.s16(P.div(y, d[0]))
  d[4] = 0
  d[3] = 0
end

-- pokefirered/src/battle_anim_mons.c:988
function P.InitAnimLinearTranslation(s)
  local d = s.data
  local x = d[2] - d[1]
  local y = d[4] - d[3]
  local movingLeft = x < 0
  local movingUp = y < 0
  local xDelta = P.u16(P.abs(x) * 256)
  local yDelta = P.u16(P.abs(y) * 256)
  local sp = d[0]
  xDelta = P.u16(P.div(xDelta, sp))
  yDelta = P.u16(P.div(yDelta, sp))
  if movingLeft then xDelta = P.bor(xDelta, 1) else xDelta = P.band(xDelta, 0xFFFE) end
  if movingUp then yDelta = P.bor(yDelta, 1) else yDelta = P.band(yDelta, 0xFFFE) end
  d[1] = P.s16(xDelta)
  d[2] = P.s16(yDelta)
  d[4] = 0
  d[3] = 0
end

-- pokefirered/src/battle_anim_mons.c:1034
function P.AnimTranslateLinear(s)
  local d = s.data
  if d[0] == 0 then return true end
  local v1 = P.u16(d[1])
  local v2 = P.u16(d[2])
  local x = P.u16(P.u16(d[3]) + v1)
  local y = P.u16(P.u16(d[4]) + v2)
  if P.band(v1, 1) ~= 0 then s.ox = -P.rshift(x, 8) else s.ox = P.rshift(x, 8) end
  if P.band(v2, 1) ~= 0 then s.oy = -P.rshift(y, 8) else s.oy = P.rshift(y, 8) end
  d[3] = P.s16(x)
  d[4] = P.s16(y)
  d[0] = d[0] - 1
  return false
end

function P.AnimTranslateLinear_WithFollowup(s)
  if P.AnimTranslateLinear(s) then P.SetCallbackToStoredInData6(s) end
end

function P.StartAnimLinearTranslation(s, vm)
  s.data[1] = s.x
  s.data[3] = s.y
  P.InitAnimLinearTranslation(s)
  s.callbackFn = P.AnimTranslateLinear_WithFollowup
  s.callbackFn(s, vm)
end

-- pokefirered/src/battle_anim_mons.c:1074
function P.InitAnimLinearTranslationWithSpeed(s)
  local d = s.data
  local v1 = P.abs(d[2] - d[1]) * 256
  d[0] = P.s16(P.div(v1, d[0]))
  P.InitAnimLinearTranslation(s)
end

function P.InitAnimLinearTranslationWithSpeedAndPos(s, vm)
  s.data[1] = s.x
  s.data[3] = s.y
  P.InitAnimLinearTranslationWithSpeed(s)
  s.callbackFn = P.AnimTranslateLinear_WithFollowup
  s.callbackFn(s, vm)
end

-- pokefirered/src/battle_anim_mons.c:1091
function P.InitAnimFastLinearTranslation(s)
  local d = s.data
  local xDiff = d[2] - d[1]
  local yDiff = d[4] - d[3]
  local x2 = P.u16(P.abs(xDiff) * 16)
  local y2 = P.u16(P.abs(yDiff) * 16)
  x2 = P.u16(P.div(x2, d[0]))
  y2 = P.u16(P.div(y2, d[0]))
  if xDiff < 0 then x2 = P.bor(x2, 1) else x2 = P.band(x2, 0xFFFE) end
  if yDiff < 0 then y2 = P.bor(y2, 1) else y2 = P.band(y2, 0xFFFE) end
  d[1] = P.s16(x2)
  d[2] = P.s16(y2)
  d[4] = 0
  d[3] = 0
end

function P.AnimFastTranslateLinear(s)
  local d = s.data
  if d[0] == 0 then return true end
  local v1 = P.u16(d[1])
  local v2 = P.u16(d[2])
  local x = P.u16(P.u16(d[3]) + v1)
  local y = P.u16(P.u16(d[4]) + v2)
  if P.band(v1, 1) ~= 0 then s.ox = -P.rshift(x, 4) else s.ox = P.rshift(x, 4) end
  if P.band(v2, 1) ~= 0 then s.oy = -P.rshift(y, 4) else s.oy = P.rshift(y, 4) end
  d[3] = P.s16(x)
  d[4] = P.s16(y)
  d[0] = d[0] - 1
  return false
end

function P.AnimFastTranslateLinearWaitEnd(s)
  if P.AnimFastTranslateLinear(s) then P.SetCallbackToStoredInData6(s) end
end

function P.InitAndRunAnimFastLinearTranslation(s, vm)
  s.data[1] = s.x
  s.data[3] = s.y
  P.InitAnimFastLinearTranslation(s)
  s.callbackFn = P.AnimFastTranslateLinearWaitEnd
  s.callbackFn(s, vm)
end

-- pokefirered/src/battle_anim_mons.c:757
function P.InitAnimArcTranslation(s)
  s.data[1] = s.x
  s.data[3] = s.y
  P.InitAnimLinearTranslation(s)
  s.data[6] = P.s16(P.div(0x8000, s.data[0]))
  s.data[7] = 0
end

function P.TranslateAnimHorizontalArc(s)
  if P.AnimTranslateLinear(s) then return true end
  s.data[7] = P.s16(s.data[7] + s.data[6])
  s.oy = s.oy + P.Sin(P.band(P.rshift(P.u16(s.data[7]), 8), 0xFF), s.data[5])
  return false
end

function P.TranslateAnimVerticalArc(s)
  if P.AnimTranslateLinear(s) then return true end
  s.data[7] = P.s16(s.data[7] + s.data[6])
  s.ox = s.ox + P.Sin(P.band(P.rshift(P.u16(s.data[7]), 8), 0xFF), s.data[5])
  return false
end

function P.SetSpritePrimaryCoordsFromSecondaryCoords(s)
  s.x = s.x + s.ox
  s.y = s.y + s.oy
  s.ox = 0
  s.oy = 0
end

-- pokefirered/src/battle_anim_mons.c:735
function P.SetAnimSpriteInitialXOffset(s, vm, xOffset)
  local ax = P.coordAtk(vm, P.COORD_X)
  local tx = P.coordTgt(vm, P.COORD_X)
  if ax > tx then
    s.x = s.x - xOffset
  elseif ax < tx then
    s.x = s.x + xOffset
  elseif not P.atkIsPlayer(vm) then
    s.x = s.x - xOffset
  else
    s.x = s.x + xOffset
  end
end

-- pokefirered/src/battle_anim_mons.c:792
function P.InitSpritePosToAnimTarget(s, vm, respect)
  if not respect then
    s.x = P.coordTgt(vm, P.COORD_X)
    s.y = P.coordTgt(vm, P.COORD_Y)
  end
  P.SetAnimSpriteInitialXOffset(s, vm, s.ga[0])
  s.y = s.y + s.ga[1]
end

function P.InitSpritePosToAnimAttacker(s, vm, respect)
  if not respect then
    s.x = P.coordAtk(vm, P.COORD_X)
    s.y = P.coordAtk(vm, P.COORD_Y)
  else
    s.x = P.coordAtk(vm, P.COORD_X_2)
    s.y = P.coordAtk(vm, P.COORD_Y_PIC)
  end
  P.SetAnimSpriteInitialXOffset(s, vm, s.ga[0])
  s.y = s.y + s.ga[1]
end

function P.SetSpriteCoordsToAnimAttackerCoords(s, vm)
  s.x = P.coordAtk(vm, P.COORD_X_2)
  s.y = P.coordAtk(vm, P.COORD_Y_PIC)
end

-- pokefirered/src/battle_anim_mons.c:1409
function P.AnimSpriteOnMonPos(s, vm)
  if s.data[0] == 0 then
    local respect = s.ga[3] == 0
    if s.ga[2] == 0 then
      P.InitSpritePosToAnimAttacker(s, vm, respect)
    else
      P.InitSpritePosToAnimTarget(s, vm, respect)
    end
    s.data[0] = s.data[0] + 1
  elseif s.animEnded or s.affineAnimEnded then
    destroy(s)
  end
end

-- pokefirered/src/battle_anim_mons.c:1440
function P.TranslateAnimSpriteToTargetMonLocation(s, vm)
  local respect = P.band(s.ga[5], 0xFF00) == 0
  local coordType = (P.band(s.ga[5], 0xFF) == 0) and P.COORD_Y_PIC or P.COORD_Y
  P.InitSpritePosToAnimAttacker(s, vm, respect)
  if not P.atkIsPlayer(vm) then s.ga[2] = -s.ga[2] end
  s.data[0] = s.ga[4]
  s.data[2] = P.coordTgt(vm, P.COORD_X_2) + s.ga[2]
  s.data[4] = P.coordTgt(vm, coordType) + s.ga[3]
  s.callbackFn = P.StartAnimLinearTranslation
  P.StoreSpriteCallbackInData6(s, destroy)
end

-- pokefirered/src/battle_anim_mons.c:1463
function P.AnimThrowProjectile(s, vm)
  P.InitSpritePosToAnimAttacker(s, vm, true)
  if not P.atkIsPlayer(vm) then s.ga[2] = -s.ga[2] end
  s.data[0] = s.ga[4]
  s.data[2] = P.coordTgt(vm, P.COORD_X_2) + s.ga[2]
  s.data[4] = P.coordTgt(vm, P.COORD_Y_PIC) + s.ga[3]
  s.data[5] = s.ga[5]
  P.InitAnimArcTranslation(s)
  s.callbackFn = function(sp)
    if P.TranslateAnimHorizontalArc(sp) then destroy(sp) end
  end
end

function P.monSprite(vm, animBattler)
  local side = P.side(vm, animBattler)
  if not side then return nil, nil end
  return Anim().present(side), side
end

-- pokefirered/src/scanline_effect.c:221
function P.Wave(startLine, endLine, frequency, amplitude, delayInterval)
  local w = {
    startLine = startLine, endLine = endLine,
    waveLength = floor(256 / frequency), offset = 0,
    framesUntilMove = delayInterval, delay = delayInterval, buf = {},
  }
  local theta = 0
  for i = 0, 255 do
    w.buf[i] = P.div(SINE[theta + 1] * amplitude, 256)
    theta = (theta + frequency) % 256
  end
  function w.step(self, base)
    base = base or 0
    local out = {}
    local off = self.offset
    for i = self.startLine, self.endLine - 1 do
      out[i] = (self.buf[off] or 0) + base
      off = off + 1
    end
    if self.framesUntilMove ~= 0 then
      self.framesUntilMove = self.framesUntilMove - 1
    else
      self.framesUntilMove = self.delay
      self.offset = self.offset + 1
      if self.offset == self.waveLength then self.offset = 0 end
    end
    return out
  end
  return w
end

function P.hShiftFromHofs(hofs)
  local out = {}
  for k, v in pairs(hofs) do out[k] = -v end
  return out
end

function P.rgb555(c)
  c = tonumber(c) or 0
  return { (c % 32) / 31, (floor(c / 32) % 32) / 31, (floor(c / 1024) % 32) / 31 }
end

-- pokefirered/src/blend_palette.c:5
function P.monBlend(p, coeff, color)
  if not p then return end
  if (coeff or 0) <= 0 then
    p.blendCoeff = 0
    p.blendColor = nil
    return
  end
  p.blendColor = type(color) == "table" and color or P.rgb555(color)
  p.blendCoeff = coeff / 16
end

function P.bgBlend(coeff, color)
  local A = Anim()
  if (coeff or 0) <= 0 then
    A._bgBlend = nil
  else
    A._bgBlend = { coeff = coeff, color = color or 0 }
  end
end


P.ATTR_HEIGHT, P.ATTR_WIDTH, P.ATTR_TOP, P.ATTR_BOTTOM, P.ATTR_LEFT, P.ATTR_RIGHT, P.ATTR_RAW_BOTTOM = 0, 1, 2, 3, 4, 5, 6

local PicSize
-- pokefirered/src/battle_anim_mons.c:1999
function P.coordAttr(vm, side, attr)
  if PicSize == nil then
    local ok, m = pcall(require, "src.core.game3.battle.anim_port.g3_pic_size")
    PicSize = ok and m or false
  end
  local sp = P.species(vm, side) or 0
  local packed = PicSize and ((side == "player") and PicSize.back[sp] or PicSize.front[sp]) or nil
  local w = packed and floor(packed / 256) or 64
  local h = packed and (packed % 256) or 64
  if attr == P.ATTR_HEIGHT then return h end
  if attr == P.ATTR_WIDTH then return w end
  if attr == P.ATTR_LEFT then return P.coord(vm, side, P.COORD_X_2) - P.div(w, 2) end
  if attr == P.ATTR_RIGHT then return P.coord(vm, side, P.COORD_X_2) + P.div(w, 2) end
  if attr == P.ATTR_TOP then return P.coord(vm, side, P.COORD_Y_PIC) - P.div(h, 2) end
  if attr == P.ATTR_BOTTOM then return P.coord(vm, side, P.COORD_Y_PIC) + P.div(h, 2) end
  if attr == P.ATTR_RAW_BOTTOM then return P.coord(vm, side, P.COORD_Y) + 31 - P.yDelta(vm, side) end
  return 0
end

function P.monHidden(vm, side)
  local p = Anim().present(side)
  return (not p) or p.visible == false
end


function P.isMonBg(side)
  local p = Anim().present(side)
  if not p then return false end
  if p.monbg ~= nil then return p.monbg and true or false end
  return p.z == 10
end


function P.setBg3(vm, x, y)
  local A = Anim()
  A._bg3Scroll = { x = x or 0, y = y or 0 }
  if vm then
    vm.bg3 = vm.bg3 or {}
    vm.bg3.x = x or 0
    vm.bg3.y = y or 0
  end
end


P.WININ_WIN0_CLR, P.WININ_WIN1_CLR = 0x20, 0x2000
P.WINOUT_OUT_CLR, P.WINOUT_OBJ_CLR = 0x20, 0x2000

function P.win(vm)
  if not vm then return nil end
  local w = vm._g3win
  if not w then
    w = { winin = 0x3F3F, winout = 0x3F3F, win0 = nil, win1 = nil, objwin = false }
    vm._g3win = w
  end
  return w
end

local MASK_SHADER_SRC = [[
extern float value;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec4 c = Texel(tex, tc);
  if (c.a < 0.01) discard;
  return vec4(value, 0.0, 0.0, 1.0);
}
]]
local OVERLAY_SHADER_SRC = [[
extern vec3 fx;
extern float amount;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  float m = Texel(tex, tc).r;
  return vec4(fx, amount * m);
}
]]
local overlayRes = nil

local function overlayResources()
  if overlayRes ~= nil then return overlayRes or nil end
  if not (love and love.graphics and love.graphics.newCanvas and love.graphics.newShader) then
    overlayRes = false
    return nil
  end
  local ok1, canvas = pcall(love.graphics.newCanvas, 240, 160)
  local ok2, mask = pcall(love.graphics.newShader, MASK_SHADER_SRC)
  local ok3, over = pcall(love.graphics.newShader, OVERLAY_SHADER_SRC)
  if not (ok1 and ok2 and ok3) then
    overlayRes = false
    return nil
  end
  canvas:setFilter("nearest", "nearest")
  overlayRes = { canvas = canvas, mask = mask, over = over, quad = love.graphics.newQuad(0, 0, 240, 112, 240, 160) }
  return overlayRes
end

local function drawWindowSprite(sp)
  local img = sp.image
  if not img or sp.invisible or not sp.active then return end
  local bw = sp._baseW or sp.w or 32
  local bh = sp._baseH or sp.h or 32
  local iw, ih = img:getDimensions()
  local q = love.graphics.newQuad(sp.quadX or 0, sp.quadY or 0, bw, bh, iw, ih)
  local sx = (sp.scaleX or 1) * (sp.hFlip and -1 or 1)
  local sy = (sp.scaleY or 1) * (sp.vFlip and -1 or 1)
  love.graphics.draw(img, q, math.floor(sp.x + (sp.ox or 0) + 0.5), math.floor(sp.y + (sp.oy or 0) + 0.5),
    sp.rotation or 0, sx, sy, bw / 2, bh / 2)
end

local function clrOf(bits, mask) return (P.band(bits or 0, mask) ~= 0) and 1 or 0 end

-- pokefirered/src/palette.c:701
function P.drawColorEffect(vm, effect, y)
  if not (love and love.graphics) then return end
  y = tonumber(y) or 0
  if y <= 0 then return end
  if y > 16 then y = 16 end
  local col
  if effect == 2 then col = { 1, 1, 1 } elseif effect == 3 then col = { 0, 0, 0 } else return end
  local w = P.win(vm)
  local windowed = w and (w.win0 or w.win1 or w.objwin)
  if not windowed then
    love.graphics.setColor(col[1], col[2], col[3], y / 16)
    love.graphics.rectangle("fill", 0, 0, 240, 112)
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  local R = overlayResources()
  if not R then return end
  love.graphics.push("all")
  love.graphics.setCanvas(R.canvas)
  love.graphics.origin()
  love.graphics.setBlendMode("replace", "premultiplied")
  love.graphics.setColor(1, 1, 1, 1)
  local outV = clrOf(w.winout, P.WINOUT_OUT_CLR)
  love.graphics.clear(outV, 0, 0, 1)
  if w.objwin then
    love.graphics.setShader(R.mask)
    R.mask:send("value", clrOf(w.winout, P.WINOUT_OBJ_CLR))
    for _, sp in ipairs(w.objSprites or {}) do drawWindowSprite(sp) end
    love.graphics.setShader()
  end
  if w.win1 then
    local v = clrOf(w.winin, P.WININ_WIN1_CLR)
    love.graphics.setColor(v, 0, 0, 1)
    love.graphics.rectangle("fill", w.win1[1], w.win1[3], w.win1[2] - w.win1[1], w.win1[4] - w.win1[3])
  end
  if w.win0 then
    local v = clrOf(w.winin, P.WININ_WIN0_CLR)
    love.graphics.setColor(v, 0, 0, 1)
    love.graphics.rectangle("fill", w.win0[1], w.win0[3], w.win0[2] - w.win0[1], w.win0[4] - w.win0[3])
  end
  love.graphics.pop()
  love.graphics.push("all")
  love.graphics.setShader(R.over)
  R.over:send("fx", col)
  R.over:send("amount", y / 16)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(R.canvas, R.quad, 0, 0)
  love.graphics.pop()
end

function P.registerObjWindow(vm, s)
  local w = P.win(vm)
  if not w then return end
  w.objSprites = w.objSprites or {}
  for i = #w.objSprites, 1, -1 do
    local o = w.objSprites[i]
    if not o.active or not o._objWindow then table.remove(w.objSprites, i) end
  end
  s._objWindow = true
  w.objSprites[#w.objSprites + 1] = s
end

local function overlayStep(s, vm)
  local w = vm._g3win
  local live = vm.hwFade ~= nil or (w and (w.objwin or w.win0 or w.win1))
  if not live then P.DestroyAnimSprite(s) end
end

local function overlayDraw(s, vm)
  vm = vm or s._vm
  local hw = vm and vm.hwFade
  if not hw then return end
  local cnt = tonumber(hw.cnt or hw[1]) or 0
  local y = tonumber(hw.y or hw[2]) or 0
  P.drawColorEffect(vm, P.band(P.rshift(cnt, 6), 3), y)
end

function P.ensureColorOverlay(vm)
  if not vm then return end
  local cur = vm._g3overlay
  if cur and cur.active and cur._g3overlayTok == cur._g3tok then return cur end
  local AnimSprites = P.AnimSprites()
  local s = AnimSprites.acquire({ x = 0, y = 0, z = 997, callback = genericCallback, w = 8, h = 8 })
  if not s then return nil end
  s._args, s._op, s._vm = nil, nil, vm
  s.template = nil
  s.image = nil
  s._g3 = true
  s._g3tok = newTok()
  s._g3overlayTok = s._g3tok
  s._inited = true
  s.callbackFn = overlayStep
  s.customDraw = overlayDraw
  s.zOverride = 997
  s.pri, s.sub = 0, 0
  vm._g3overlay = s
  return s
end

P.coordAttr = AnimCoords.sideArg(P.coordAttr, 2)
P.monCenter = AnimCoords.sideArg(P.monCenter, 2)
P.monImage = AnimCoords.sideArg(P.monImage, 2)

return P
