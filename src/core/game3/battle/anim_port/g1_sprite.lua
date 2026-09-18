local bit = require("bit")
local P = require("src.core.game3.battle.anim_port.g1_pret")
local AnimSprites = require("src.core.game3.battle.anim_sprites")
local AnimPal = require("src.core.game3.battle.anim_pal")

local band, bor, rshift, arshift, lshift = bit.band, bit.bor, bit.rshift, bit.arshift, bit.lshift
local floor = math.floor
local s16, u16 = P.s16, P.u16

local S = {}

function S.destroy(s)
  if not s.active then return end
  AnimSprites.release(s)
end

S.DestroyAnimSprite = S.destroy
S.DestroySpriteAndMatrix = S.destroy

function S.setCb(s, fn)
  s._cb = fn
end

-- pokefirered/src/battle_anim_mons.c:377
function S.store(s, fn)
  s._stored = fn
end

function S.runStored(s)
  s._cb = s._stored or S.destroy
end

function S.invisible(s)
  return s.visible == false
end

function S.setInvisible(s, v)
  s.visible = not v
end

local function apply_flip(s, h, v)
  if s.affineMode and s.affineMode ~= 0 then return end
  s._oamH = (h and true or false) ~= (s._hFlip and true or false)
  s._oamV = (v and true or false) ~= (s._vFlip and true or false)
end

-- pokefirered/src/sprite.c:1236
function S.setFlipBits(s, h, v)
  apply_flip(s, h, v)
end

function S.setOamFlip(s, h, v)
  s._oamH = h and true or false
  s._oamV = v and true or false
end

local function anim_frame(s, c)
  local d = c.d or 0
  if d > 0 then d = d - 1 end
  s.animDelayCounter = d
  apply_flip(s, c.h, c.v)
  s._tile = (s._sheetTileStart or 0) + (c.f or 0)
end

local continue_anim

local function anim_cmd(s, seq, c)
  if c.e then
    s.animCmdIndex = s.animCmdIndex - 1
    s.animEnded = true
  elseif c.jump ~= nil then
    s.animCmdIndex = c.jump
    local f = seq[s.animCmdIndex + 1]
    if f then anim_frame(s, f) end
  elseif c.loop ~= nil then
    if (s.animLoopCounter or 0) ~= 0 then
      s.animLoopCounter = s.animLoopCounter - 1
    else
      s.animLoopCounter = c.loop
    end
    if s.animLoopCounter ~= 0 then
      s.animCmdIndex = s.animCmdIndex - 1
      while true do
        local prev = seq[s.animCmdIndex]
        if prev and prev.loop ~= nil then break end
        if s.animCmdIndex == 0 then break end
        s.animCmdIndex = s.animCmdIndex - 1
      end
      s.animCmdIndex = s.animCmdIndex - 1
    end
    continue_anim(s)
  else
    anim_frame(s, c)
  end
end

-- pokefirered/src/sprite.c:939
continue_anim = function(s)
  local seq = s._anims and s._anims[s.animNum or 0]
  if not seq then return end
  if (s.animDelayCounter or 0) > 0 then
    if not s.animPaused then s.animDelayCounter = s.animDelayCounter - 1 end
    local c = seq[(s.animCmdIndex or 0) + 1]
    if c and c.f then apply_flip(s, c.h, c.v) end
  elseif not s.animPaused then
    s.animCmdIndex = (s.animCmdIndex or 0) + 1
    local c = seq[s.animCmdIndex + 1]
    if not c then
      s.animCmdIndex = s.animCmdIndex - 1
      s.animEnded = true
      return
    end
    anim_cmd(s, seq, c)
  end
end

-- pokefirered/src/sprite.c:905
local function begin_anim(s)
  local seq = s._anims and s._anims[s.animNum or 0]
  s.animCmdIndex = 0
  s.animEnded = false
  s.animLoopCounter = 0
  if not seq then return end
  local c = seq[1]
  if c and c.f ~= nil then
    s.animBeginning = false
    anim_frame(s, c)
  end
end

-- pokefirered/src/sprite.c:1336
function S.startAnim(s, num)
  s.animNum = num
  s.animBeginning = true
  s.animEnded = false
end

-- pokefirered/src/sprite.c:1343
function S.startAnimIfDifferent(s, num)
  if s.animNum ~= num then S.startAnim(s, num) end
end

-- pokefirered/src/sprite.c:1349
function S.seekAnim(s, idx)
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

function S.convertScale(scale)
  if scale == 0 then return 0 end
  return s16(P.cdiv(0x10000, scale))
end

function S.setMatrix(s, xs, ys, rot)
  s._matX, s._matY, s._matRot = xs, ys, u16(rot)
end

local function aff_update(s)
  local a = s._aff
  S.setMatrix(s, S.convertScale(a.xScale), S.convertScale(a.yScale), a.rotation)
end

-- pokefirered/src/sprite.c:1292
local function aff_rel(s, c)
  local a = s._aff
  a.xScale = s16(a.xScale + (c.xs or 0))
  a.yScale = s16(a.yScale + (c.ys or 0))
  a.rotation = band(a.rotation + lshift(c.r or 0, 8), 0xFF00)
  aff_update(s)
end

-- pokefirered/src/sprite.c:1320
local function aff_frame(s, c)
  local a = s._aff
  local d = c.d or 0
  if d ~= 0 then
    aff_rel(s, c)
    a.delay = d - 1
  else
    a.xScale = c.xs or 0
    a.yScale = c.ys or 0
    a.rotation = band(lshift(c.r or 0, 8), 0xFFFF)
    aff_rel(s, {})
    a.delay = 0
  end
end

local continue_affine

local function aff_cmd(s, seq, c)
  local a = s._aff
  if c.e then
    s.affineAnimEnded = true
    a.idx = a.idx - 1
    aff_rel(s, {})
  elseif c.jump ~= nil then
    a.idx = c.jump
    local f = seq[a.idx + 1]
    if f then aff_frame(s, f) end
  elseif c.loop ~= nil then
    if (a.loop or 0) ~= 0 then a.loop = a.loop - 1 else a.loop = c.loop end
    if a.loop ~= 0 then
      a.idx = a.idx - 1
      while true do
        local prev = seq[a.idx]
        if prev and prev.loop ~= nil then break end
        if a.idx == 0 then break end
        a.idx = a.idx - 1
      end
      a.idx = a.idx - 1
    end
    continue_affine(s)
  else
    aff_frame(s, c)
  end
end

-- pokefirered/src/sprite.c:1080
continue_affine = function(s)
  local a = s._aff
  local seq = s._affAnims and s._affAnims[a.animNum or 0]
  if not seq then return end
  if (a.delay or 0) > 0 then
    if not s.affineAnimPaused then
      a.delay = a.delay - 1
      local c = seq[a.idx + 1]
      if c then aff_rel(s, c) end
    end
  elseif s.affineAnimPaused then
    return
  else
    a.idx = a.idx + 1
    local c = seq[a.idx + 1]
    if not c then
      a.idx = a.idx - 1
      s.affineAnimEnded = true
      return
    end
    aff_cmd(s, seq, c)
  end
end

local function aff_state(s)
  if not s._aff then
    s._aff = { animNum = 0, idx = 0, delay = 0, loop = 0, xScale = 0x100, yScale = 0x100, rotation = 0 }
  end
  return s._aff
end

-- pokefirered/src/sprite.c:1063
local function begin_affine(s)
  local a = aff_state(s)
  local seq = s._affAnims and s._affAnims[a.animNum or 0]
  if not seq or not seq[1] or seq[1].e then return end
  a.idx = 0
  a.delay = 0
  a.loop = 0
  s.affineAnimBeginning = false
  s.affineAnimEnded = false
  aff_frame(s, seq[1])
end

-- pokefirered/src/sprite.c:1363
function S.startAffineAnim(s, num)
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

-- pokefirered/src/sprite.c:1378
function S.changeAffineAnim(s, num)
  local a = aff_state(s)
  a.animNum = num
  s.affineAnimBeginning = true
  s.affineAnimEnded = false
end

-- pokefirered/src/sprite.c:897
function S.animate(s)
  if s.animBeginning then begin_anim(s) else continue_anim(s) end
  if s.affineMode and band(s.affineMode, 1) ~= 0 then
    aff_state(s)
    if s.affineAnimBeginning then begin_affine(s) else continue_affine(s) end
  end
end

-- pokefirered/src/battle_anim_mons.c:1244
function S.trySetRotScale(s, _recalc, xs, ys, rot)
  if s.affineMode and band(s.affineMode, 1) ~= 0 then
    s.affineAnimPaused = true
    S.setMatrix(s, xs, ys, rot)
  end
end

function S.tryResetAffine(s)
  S.trySetRotScale(s, true, 0x100, 0x100, 0)
  s.affineAnimPaused = false
end

local shader
local shaderFailed = false
local SHADER_SRC = [[
extern vec3 blendColor;
extern float blendCoeff;
extern float blendM;
extern int nRemap;
extern vec3 remapSrc[16];
extern vec3 remapDst[16];
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec4 c = Texel(tex, tc);
  for (int i = 0; i < 16; i++) {
    if (i < nRemap) {
      vec3 d = abs(c.rgb - remapSrc[i]);
      if (d.r < 0.01 && d.g < 0.01 && d.b < 0.01) { c.rgb = remapDst[i]; }
    }
  }
  c.rgb = c.rgb * blendM + blendColor;
  return c * color;
}
]]

local function get_shader()
  if shader or shaderFailed then return shader end
  if not (love and love.graphics and love.graphics.newShader) then shaderFailed = true return nil end
  local ok, sh = pcall(love.graphics.newShader, SHADER_SRC)
  if ok then shader = sh else shaderFailed = true print("[g1] shader: " .. tostring(sh)) end
  return shader
end

local quad
local zeroVec, srcBuf, dstBuf = { 0, 0, 0 }, {}, {}

local function palette_state(s)
  local key = "tag:" .. tostring(s._palTag or s.tag)
  local st = P.Pal.faded[key] or P.Pal.unfaded[key]
  local remap = P.Pal.remap[s._palTag or s.tag]
  if s.palBlend and not st then
    local k = (tonumber(s.palBlend.coeff) or 0) / 16
    local r, g, b = P.rgb555(s.palBlend.color)
    st = { m = 1 - k, r = r * k, g = g * k, b = b * k }
  end
  return st, remap
end

-- pokefirered/src/sprite.c:474
function S.draw(s, vm)
  local img = s.image
  if not img or s.visible == false then return end
  local w, h = s._w or 16, s._h or 16
  local sheetW = img:getWidth()
  local sheetH = img:getHeight()
  local tw = floor(w / 8)
  local sw = math.max(1, floor(sheetW / 8))
  local tile = s._tile or 0
  local x = floor(s.x + (s.ox or 0))
  local y = floor(s.y + (s.oy or 0))
  local sx, sy, rot = 1, 1, 0
  local fx, fy = 1, 1
  if s.affineMode and band(s.affineMode, 1) ~= 0 then
    local mx, my = s._matX or 0x100, s._matY or 0x100
    sx = mx ~= 0 and (256 / mx) or 0
    sy = my ~= 0 and (256 / my) or 0
    rot = -((s._matRot or 0) / 65536) * 2 * math.pi
  else
    if s._oamH then fx = -1 end
    if s._oamV then fy = -1 end
  end
  local alpha = s._drawAlpha
  if alpha == nil then
    alpha = s.alpha or 1
    local bld = vm and vm.bldAlpha
    if s.objBlend and bld then
      alpha = alpha * math.max(0, math.min(16, tonumber(bld.eva or bld[1]) or 16)) / 16
    end
  end
  if s._alphaOverride then alpha = s._alphaOverride end
  local st, remap = palette_state(s)
  local sh = nil
  local pimg = AnimPal.begin(s, img, st and { affine = st } or nil)
  if pimg then
    img = pimg
  elseif st or remap then
    sh = get_shader()
    if sh then
      local m = st and st.m or 1
      sh:send("blendM", m)
      sh:send("blendColor", st and { st.r, st.g, st.b } or zeroVec)
      local n = remap and math.min(16, #remap.src) or 0
      sh:send("nRemap", n)
      if n > 0 then
        for i = 1, 16 do
          srcBuf[i] = remap.src[i] or zeroVec
          dstBuf[i] = remap.dst[i] or zeroVec
        end
        sh:send("remapSrc", unpack(srcBuf))
        sh:send("remapDst", unpack(dstBuf))
      end
      love.graphics.setShader(sh)
    end
  end
  love.graphics.setColor(1, 1, 1, alpha)
  love.graphics.push()
  love.graphics.translate(x, y)
  if rot ~= 0 then love.graphics.rotate(rot) end
  love.graphics.scale(sx * fx, sy * fy)
  if not quad then quad = love.graphics.newQuad(0, 0, 8, 8, sheetW, sheetH) end
  for r = 0, floor(h / 8) - 1 do
    local t0 = tile + r * tw
    local c = 0
    while c < tw do
      local tt = t0 + c
      local col = tt % sw
      local row = floor(tt / sw)
      local n = math.min(tw - c, sw - col)
      if row * 8 < sheetH then
        quad:setViewport(col * 8, row * 8, n * 8, 8, sheetW, sheetH)
        love.graphics.draw(img, quad, -w / 2 + c * 8, -h / 2 + r * 8)
      end
      c = c + n
    end
  end
  love.graphics.pop()
  if sh or pimg then love.graphics.setShader() end
  love.graphics.setColor(1, 1, 1, 1)
end

local function runner(s)
  local cb = s._cb
  if cb then cb(s) end
  if not s.active or not s._g1 then return end
  S.animate(s)
  s.oamPriority = s._pri or 2
  s._pz = true
  P.updateZ(s)
end

-- pokefirered/src/sprite.c:494
function S.applyTemplate(s, tplName, vm)
  local T = P.templates()
  local tpl = T[tplName]
  local info = tpl and tpl.tag and P.tagInfo(vm, tpl.tag)
  if tpl and tpl.tag then
    s.tag = tpl.tag
    s.image = info and info.image or s.image
  end
  s._tpl = tpl
  s._w = tpl and tpl.w or s._baseW or 16
  s._h = tpl and tpl.h or s._baseH or 16
  s._anims = tpl and tpl.anims
  s._affAnims = tpl and tpl.affine
  s.affineMode = tpl and tpl.affineMode or 0
  s.objBlend = tpl and tpl.objBlend or false
  s._pri = tpl and tpl.priority or 2
  s._palTag = tpl and tpl.pal or s.tag
  s._tile = 0
  s._sheetTileStart = 0
  s.animNum = 0
  s.animCmdIndex = 0
  s.animDelayCounter = 0
  s.animLoopCounter = 0
  s.animEnded = false
  s.animPaused = false
  s.animBeginning = true
  s._aff = nil
  s.affineAnimPaused = false
  s.affineAnimEnded = false
  s.affineAnimBeginning = true
  s._hFlip = false
  s._vFlip = false
  s._oamH = false
  s._oamV = false
  s.hFlip = false
  s.vFlip = false
  s.rotation = 0
  s.scaleX = 1
  s.scaleY = 1
  s._matX, s._matY, s._matRot = 0x100, 0x100, 0
  s.customDraw = S.draw
  s._g1 = true
  if s.affineMode ~= 0 and s._affAnims then aff_state(s) end
end

local function init_from_vm(s, initFn)
  P.hookVmReset()
  local vm = s._vm or P.vm()
  s._vm = vm
  local op = s._op
  local args = (op and op.args) or s._args or {}
  local A = {}
  for i = 0, 7 do
    local v = args[i + 1]
    if v == nil and vm and vm.args then v = vm.args[i] end
    if type(v) == "string" then
      local l = v:lower()
      if l:find("target") then v = 1 elseif l:find("attacker") then v = 0 else v = tonumber(v) or 0 end
    end
    A[i] = s16(tonumber(v) or 0)
  end
  s._A = A
  for i = 0, 7 do s.data[i] = 0 end
  local tgt = P.tgt(vm)
  s.x = P.coord(vm, tgt, P.X_2)
  s.y = P.coord(vm, tgt, P.Y_PIC_OFFSET)
  s.ox, s.oy = 0, 0
  s.visible = true
  s.alpha = 1
  S.applyTemplate(s, s.template or (op and op.template), vm)
  if op then
    s.subpriority = (function()
      local raw = tonumber(op.subpriority) or 0
      local side = (op.animBattler == "target") and P.tgt(vm) or P.atk(vm)
      local sub
      if raw >= 64 then sub = P.subpriorityOf(side) + (raw - 64) else sub = P.subpriorityOf(side) - raw end
      if sub < 3 then sub = 3 end
      return sub
    end)()
  else
    local side = s._anchorSide or tgt
    s.subpriority = P.subpriorityOf(side) - (tonumber(s.subpriority) or 2)
  end
  s.callback = runner
  s._cb = initFn
  runner(s)
end

S.inits = setmetatable({}, { __mode = "k" })

function S.wrap(initFn)
  local f = function(s)
    if s._g1 then return runner(s) end
    return init_from_vm(s, initFn)
  end
  S.inits[f] = initFn
  return f
end

-- pokefirered/src/sprite.c:494
function S.create(vm, tplName, x, y, subpriority, cb)
  local T = P.templates()
  local tpl = T[tplName]
  local info = tpl and tpl.tag and P.tagInfo(vm, tpl.tag)
  local s = AnimSprites.acquire({ x = x, y = y, image = info and info.image, tag = tpl and tpl.tag, w = tpl and tpl.w or 16, h = tpl and tpl.h or 16 })
  if not s then return nil end
  s._vm = vm
  s.template = tplName
  s.ox, s.oy = 0, 0
  S.applyTemplate(s, tplName, vm)
  s.subpriority = subpriority or 0
  s._A = {}
  for i = 0, 7 do s._A[i] = s16(vm and vm.args and vm.args[i] or 0) end
  s._cb = cb or function() end
  s.callback = runner
  s.oamPriority = s._pri or 2
  s._pz = true
  P.updateZ(s)
  return s
end

-- pokefirered/src/sprite.c:1336
function S.createAndAnimate(vm, tplName, x, y, subpriority, cb, args)
  local s = S.create(vm, tplName, x, y, subpriority, cb)
  if not s then return nil end
  if args then for i = 0, 7 do s._A[i] = s16(args[i] or 0) end end
  runner(s)
  return s
end

S.runner = runner

-- pokefirered/src/battle_anim_mons.c:727
function S.setToAttackerCoords(s)
  local vm = s._vm
  s.x = P.coord(vm, P.atk(vm), P.X_2)
  s.y = P.coord(vm, P.atk(vm), P.Y_PIC_OFFSET)
end

-- pokefirered/src/battle_anim_mons.c:735
function S.setInitialXOffset(s, xOffset)
  local vm = s._vm
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
function S.initPosToTarget(s, respect)
  local vm = s._vm
  if not respect then
    s.x = P.coord(vm, P.tgt(vm), P.X)
    s.y = P.coord(vm, P.tgt(vm), P.Y)
  end
  S.setInitialXOffset(s, s._A[0])
  s.y = s.y + s._A[1]
end

-- pokefirered/src/battle_anim_mons.c:805
function S.initPosToAttacker(s, respect)
  local vm = s._vm
  local side = P.atk(vm)
  if not respect then
    s.x = P.coord(vm, side, P.X)
    s.y = P.coord(vm, side, P.Y)
  else
    s.x = P.coord(vm, side, P.X_2)
    s.y = P.coord(vm, side, P.Y_PIC_OFFSET)
  end
  S.setInitialXOffset(s, s._A[0])
  s.y = s.y + s._A[1]
end

-- pokefirered/src/battle_anim_mons.c:521
function S.waitAnimForDuration(s)
  if s.data[0] > 0 then
    s.data[0] = s.data[0] - 1
  else
    S.runStored(s)
  end
end

-- pokefirered/src/battle_anim_mons.c:548
function S.convertPosDataToTranslateLinear(s)
  local d = s.data
  if d[1] > d[2] then d[0] = -d[0] end
  local xDiff = d[2] - d[1]
  local old = d[0]
  d[0] = s16(math.abs(P.cdiv(xDiff, d[0])))
  d[2] = s16(P.cdiv(d[4] - d[3], d[0]))
  d[1] = old
end

-- pokefirered/src/battle_anim_mons.c:562
function S.translateSpriteLinear(s)
  local d = s.data
  if d[0] > 0 then
    d[0] = d[0] - 1
    s.ox = s.ox + d[1]
    s.oy = s.oy + d[2]
  else
    S.runStored(s)
  end
end

-- pokefirered/src/battle_anim_mons.c:576
function S.translateSpriteLinearFixedPoint(s)
  local d = s.data
  if d[0] > 0 then
    d[0] = d[0] - 1
    d[3] = s16(d[3] + d[1])
    d[4] = s16(d[4] + d[2])
    s.ox = arshift(d[3], 8)
    s.oy = arshift(d[4], 8)
  else
    S.runStored(s)
  end
end

-- pokefirered/src/battle_anim_mons.c:651
function S.translateSpriteLinearAndFlicker(s)
  local d = s.data
  if d[0] > 0 then
    d[0] = d[0] - 1
    s.ox = arshift(d[2], 8)
    d[2] = s16(d[2] + d[1])
    s.oy = arshift(d[4], 8)
    d[4] = s16(d[4] + d[3])
    if d[5] ~= 0 and P.cmod(d[0], d[5]) == 0 then s.visible = not s.visible end
  else
    S.runStored(s)
  end
end

-- pokefirered/src/battle_anim_mons.c:433
function S.translateInGrowingCircle(s)
  local d = s.data
  if d[3] ~= 0 then
    local amp = arshift(d[5], 8) + d[1]
    s.ox = P.Sin(d[0], amp)
    s.oy = P.Cos(d[0], amp)
    d[0] = d[0] + d[2]
    d[5] = s16(d[5] + d[4])
    if d[0] >= 0x100 then d[0] = d[0] - 0x100 elseif d[0] < 0 then d[0] = d[0] + 0x100 end
    d[3] = d[3] - 1
  else
    S.runStored(s)
  end
end

-- pokefirered/src/battle_anim_mons.c:988
function S.initLinear(s)
  local d = s.data
  local x = d[2] - d[1]
  local y = d[4] - d[3]
  local speed = d[0]
  local xd = band(lshift(math.abs(x), 8), 0xFFFF)
  local yd = band(lshift(math.abs(y), 8), 0xFFFF)
  if speed ~= 0 then
    xd = band(P.cdiv(xd, speed), 0xFFFF)
    yd = band(P.cdiv(yd, speed), 0xFFFF)
  end
  if x < 0 then xd = bor(xd, 1) else xd = band(xd, 0xFFFE) end
  if y < 0 then yd = bor(yd, 1) else yd = band(yd, 0xFFFE) end
  d[1] = s16(xd)
  d[2] = s16(yd)
  d[4] = 0
  d[3] = 0
end

-- pokefirered/src/battle_anim_mons.c:1034
function S.translateLinear(s)
  local d = s.data
  if d[0] == 0 then return true end
  local v1 = u16(d[1])
  local v2 = u16(d[2])
  local x = u16(u16(d[3]) + v1)
  local y = u16(u16(d[4]) + v2)
  if band(v1, 1) ~= 0 then s.ox = -rshift(x, 8) else s.ox = rshift(x, 8) end
  if band(v2, 1) ~= 0 then s.oy = -rshift(y, 8) else s.oy = rshift(y, 8) end
  d[3] = s16(x)
  d[4] = s16(y)
  d[0] = s16(d[0] - 1)
  return false
end

function S.translateLinearFollowup(s)
  if S.translateLinear(s) then S.runStored(s) end
end

-- pokefirered/src/battle_anim_mons.c:1016
function S.startLinear(s)
  s.data[1] = s.x
  s.data[3] = s.y
  S.initLinear(s)
  s._cb = S.translateLinearFollowup
  s._cb(s)
end

-- pokefirered/src/battle_anim_mons.c:757
function S.initArc(s)
  s.data[1] = s.x
  s.data[3] = s.y
  S.initLinear(s)
  local speed = s.data[0]
  s.data[6] = speed ~= 0 and s16(P.cdiv(0x8000, speed)) or 0
  s.data[7] = 0
end

-- pokefirered/src/battle_anim_mons.c:766
function S.translateHArc(s)
  if S.translateLinear(s) then return true end
  s.data[7] = s16(s.data[7] + s.data[6])
  s.oy = s.oy + P.Sin(band(rshift(u16(s.data[7]), 8), 0xFF), s.data[5])
  return false
end

-- pokefirered/src/battle_anim_mons.c:1091
function S.initFastLinear(s)
  local d = s.data
  local x = d[2] - d[1]
  local y = d[4] - d[3]
  local x2 = band(lshift(math.abs(x), 4), 0xFFFF)
  local y2 = band(lshift(math.abs(y), 4), 0xFFFF)
  if d[0] ~= 0 then
    x2 = band(P.cdiv(x2, d[0]), 0xFFFF)
    y2 = band(P.cdiv(y2, d[0]), 0xFFFF)
  end
  if x < 0 then x2 = bor(x2, 1) else x2 = band(x2, 0xFFFE) end
  if y < 0 then y2 = bor(y2, 1) else y2 = band(y2, 0xFFFE) end
  d[1] = s16(x2)
  d[2] = s16(y2)
  d[4] = 0
  d[3] = 0
end

-- pokefirered/src/battle_anim_mons.c:1125
function S.fastTranslateLinear(s)
  local d = s.data
  if d[0] == 0 then return true end
  local v1 = u16(d[1])
  local v2 = u16(d[2])
  local x = u16(u16(d[3]) + v1)
  local y = u16(u16(d[4]) + v2)
  if band(v1, 1) ~= 0 then s.ox = -rshift(x, 4) else s.ox = rshift(x, 4) end
  if band(v2, 1) ~= 0 then s.oy = -rshift(y, 4) else s.oy = rshift(y, 4) end
  d[3] = s16(x)
  d[4] = s16(y)
  d[0] = s16(d[0] - 1)
  return false
end

local function fast_wait_end(s)
  if S.fastTranslateLinear(s) then S.runStored(s) end
end

-- pokefirered/src/battle_anim_mons.c:1116
function S.initAndRunFastLinear(s)
  s.data[1] = s.x
  s.data[3] = s.y
  S.initFastLinear(s)
  s._cb = fast_wait_end
  s._cb(s)
end

-- pokefirered/src/battle_anim_mons.c:1157
function S.initFastLinearWithSpeed(s)
  local d = s.data
  local xDiff = lshift(math.abs(d[2] - d[1]), 4)
  d[0] = s16(P.cdiv(xDiff, d[0]))
  S.initFastLinear(s)
end

-- pokefirered/src/battle_anim_mons.c:701
function S.runStoredWhenAffineEnds(s)
  if s.affineAnimEnded then S.runStored(s) end
end

-- pokefirered/src/battle_anim_mons.c:707
function S.runStoredWhenAnimEnds(s)
  if s.animEnded then S.runStored(s) end
end

-- pokefirered/src/battle_anim_mons.c:672
function S.destroyAfterTimer(s)
  if s.data[0] > 0 then
    s.data[0] = s.data[0] - 1
  else
    S.destroy(s)
  end
end

-- pokefirered/src/battle_anim_mons.c:1174
function S.setMonRotScale(side, xs, ys, rot)
  local p = P.present(side)
  if not p then return end
  p.sx = xs ~= 0 and (256 / xs) or 0
  p.sy = ys ~= 0 and (256 / ys) or 0
  p.rotation = -(u16(rot) / 65536) * 2 * math.pi
  p._g1Rot = u16(rot)
  p._g1Ys = ys
end

-- pokefirered/src/battle_anim_mons.c:1222
function S.resetMonRotScale(side)
  local p = P.present(side)
  if not p then return end
  p.sx, p.sy, p.rotation = 1, 1, 0
  p._g1Rot = 0
  p._g1Ys = 0x100
end

local function clone_draw(s, vm)
  if s.visible == false then return end
  local side = s._cloneSide
  local sp = P.species(vm, side)
  local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
  if not okP then return end
  local entry
  local okU, Ui = pcall(require, "src.core.game3.battle.ui")
  if okU and Ui.battlerPic then entry = Ui.battlerPic(side, nil, sp) end
  if not entry and side == "player" and Pokemon.backPic then entry = Pokemon.backPic(sp) end
  if not entry and Pokemon.frontPic then entry = Pokemon.frontPic(sp) end
  if not (entry and entry.image) then return end
  local cx, cy = s.x, s.y
  if okU and Ui.battlerSpriteCenter then
    cx, cy = Ui.battlerSpriteCenter(side, sp, P.COORDS[side])
  end
  local alpha = s._drawAlpha
  if alpha == nil then
    alpha = s.alpha or 1
    local bld = vm and vm.bldAlpha
    if bld then alpha = alpha * math.max(0, math.min(16, tonumber(bld.eva or bld[1]) or 16)) / 16 end
  end
  local st = s._cloneBlend
  local sh = st and get_shader()
  if sh then
    sh:send("blendM", st.m)
    sh:send("blendColor", { st.r, st.g, st.b })
    sh:send("nRemap", 0)
    love.graphics.setShader(sh)
  end
  love.graphics.setColor(1, 1, 1, alpha)
  local fx = s._cloneHFlip and -1 or 1
  love.graphics.draw(entry.image, cx + (s.ox or 0), cy + (s.oy or 0), s._cloneRot or 0,
    (s._cloneSx or 1) * fx, s._cloneSy or 1, 32, 32)
  if sh then love.graphics.setShader() end
  love.graphics.setColor(1, 1, 1, 1)
end

-- pokefirered/src/battle_anim_mons.c:1517
function S.cloneMon(vm, side, blendState)
  local p = P.present(side)
  if not p then return nil end
  local s = AnimSprites.acquire({ x = P.coord(vm, side, P.X_2), y = P.coord(vm, side, P.Y_PIC_OFFSET_DEFAULT), w = 64, h = 64 })
  if not s then return nil end
  s._vm = vm
  s._g1 = true
  s._g1Clone = true
  s._cloneSide = side
  s._cloneSx, s._cloneSy, s._cloneRot, s._cloneHFlip = p.sx or 1, p.sy or 1, p.rotation or 0, p.hFlip
  s._cloneBlend = blendState
  s.ox, s.oy = p.ox or 0, p.oy or 0
  s.objBlend = true
  s.visible = true
  s._pri = 2
  s.oamPriority = 2
  s._pz = true
  s.subpriority = P.subpriorityOf(side)
  s.customDraw = clone_draw
  s._cb = function() end
  s.callback = runner
  P.updateZ(s)
  return s
end

-- pokefirered/src/battle_anim_mons.c:1762
function S.monYOffsetFromYScale(vm, side)
  local p = P.present(side)
  if not p then return end
  local var = 64 - P.yDelta(vm, side) * 2
  local d = p._g1Ys or 0x100
  local var2 = d ~= 0 and P.cdiv(lshift(var, 8), d) or 0
  if var2 > 128 then var2 = 128 end
  p.oy = P.cdiv(var - var2, 2)
end

-- pokefirered/src/battle_anim_mons.c:1233
function S.monYOffsetFromRotation(side)
  local p = P.present(side)
  if not p then return end
  local rot = p._g1Rot or 0
  local ys = p._g1Ys or 0x100
  local c = floor(math.sin((band(rshift(rot, 8), 0xFF) / 256) * 2 * math.pi) * 16384)
  local mc = arshift(c * ys, 14)
  if mc < 0 then mc = -mc end
  p.oy = arshift(mc, 3)
end

return S
