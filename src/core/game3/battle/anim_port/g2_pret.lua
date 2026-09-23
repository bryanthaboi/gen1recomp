local AnimSprites = require("src.core.game3.battle.anim_sprites")
local AnimPal = require("src.core.game3.battle.anim_pal")
local AnimCoords = require("src.core.game3.battle.anim_coords")
local Trig = require("src.core.game3.trig")

local _pfxBlendOpts = { coeff = 0, color = 0 }

local P = {}

local floor = math.floor

local function trunc(x)
  if x >= 0 then return floor(x) end
  return -floor(-x)
end
P.trunc = trunc

function P.div(a, b)
  if b == 0 then return 0 end
  return trunc(a / b)
end

function P.mod(a, b)
  if b == 0 then return 0 end
  return a - trunc(a / b) * b
end

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

function P.asr(v, n) return floor(v / 2 ^ n) end

-- pokefirered/src/math_util.c:4
function P.Q88mul(x, y)
  return P.s16(P.div(P.s16(x) * P.s16(y), 256))
end

-- pokefirered/src/math_util.c:65
function P.Q88inv(y)
  y = P.s16(y)
  if y == 0 then return 0 end
  return P.s16(P.div(0x10000, y))
end

-- pokefirered/src/trig.c:4
local SINE = Trig.SINE

function P.sine(i)
  return SINE[floor(i) % 256 + 1]
end

function P.Sin(i, amp)
  return P.s16(floor(amp * SINE[floor(i) % 256 + 1] / 256))
end

function P.Cos(i, amp)
  return P.s16(floor(amp * SINE[(floor(i) + 64) % 256 + 1] / 256))
end

function P.ArcTan2(x, y)
  return Trig.arcTan2(x, y)
end

function P.ArcTan2Neg(x, y)
  return (-P.ArcTan2(x, y)) % 65536
end

function P.Random()
  if love and love.math and love.math.random then
    return love.math.random(0, 65535)
  end
  return math.random(0, 65535)
end

P.ANIM_ATTACKER = 0
P.ANIM_TARGET = 1
P.COORD_X = 0
P.COORD_Y = 1
P.COORD_X_2 = 2
P.COORD_Y_PIC_OFFSET = 3
P.COORD_Y_PIC_OFFSET_DEFAULT = 4
P.ATTR_HEIGHT = 0
P.ATTR_WIDTH = 1
P.ATTR_TOP = 2
P.ATTR_BOTTOM = 3
P.ATTR_LEFT = 4
P.ATTR_RIGHT = 5
P.ATTR_RAW_BOTTOM = 6
P.DISPLAY_WIDTH = 240
P.DISPLAY_HEIGHT = 160

P.vm = nil

function P.setVm(vm)
  if vm then P.vm = vm end
  return P.vm
end

function P.atk()
  local vm = P.vm
  if vm and vm.allyPair and vm:allyPair() then return vm:attackerId() end
  return vm and vm:attackerSide() or "player"
end

function P.tgt()
  local vm = P.vm
  if vm and vm.allyPair and vm:allyPair() then return vm:targetId() end
  return vm and vm:targetSide() or "enemy"
end

function P.battler(which)
  if which == 0 or which == "attacker" then return P.atk() end
  if which == 1 or which == "target" then return P.tgt() end
  if which == "player" or which == "enemy" then return which end
  return nil
end

function P.side(b)
  if b == "player" then return 0 end
  return 1
end

function P.isPlayer(b) return b == "player" end

function P.args()
  local vm = P.vm
  if vm and vm.args then return vm.args end
  P._args = P._args or {}
  return P._args
end

function P.arg(i)
  local a = P.args()[i]
  return tonumber(a) or 0
end

function P.setArg(i, v)
  P.args()[i] = v
end

function P.turn()
  local vm = P.vm
  return (vm and (vm._turn or vm.moveTurn)) or 0
end

local PicCoords, MonSizes
local function pic()
  if PicCoords == nil then
    local ok, m = pcall(require, "src.core.game3.battle.pic_coords")
    PicCoords = ok and m or false
    local ok2, s = pcall(require, "src.core.game3.battle.anim_port.g2_mon_sizes")
    MonSizes = ok2 and s or false
  end
  return PicCoords, MonSizes
end

function P.species(b)
  local vm = P.vm
  if not vm then return nil end
  local sp = vm.speciesForSide and vm:speciesForSide(b)
  return tonumber(sp)
end

local BASE = setmetatable({}, { __index = function(_, k) return AnimCoords.coords(nil, k) end })
P.BASE = BASE

-- pokefirered/src/battle_anim_mons.c:233
local function final_y(b, sp, a3)
  local pc = pic()
  local base = BASE[b] or BASE.enemy
  local offset = 0
  if pc and sp then
    if b == "player" then
      offset = pc.back and pc.back[sp] or 0
    else
      offset = (pc.front and pc.front[sp] or 0) - (pc.elev and pc.elev[sp] or 0)
    end
  end
  local y = (offset + base[2]) % 256
  if a3 then
    if b == "player" then y = (y + 8) % 256 end
    if y > P.DISPLAY_HEIGHT - 64 + 8 then y = P.DISPLAY_HEIGHT - 64 + 8 end
  end
  return y
end

-- pokefirered/src/battle_anim_mons.c:105
function P.coord(b, ctype)
  local base = BASE[b] or BASE.enemy
  if ctype == 0 or ctype == 2 then return base[1] end
  if ctype == 1 then return base[2] end
  return final_y(b, P.species(b), ctype == 3)
end

function P.defaultY(b)
  return P.coord(b, 4)
end

-- pokefirered/src/battle_anim_mons.c:305
function P.yWithElevation(b)
  local y = P.coord(b, 1)
  if b ~= "player" then
    local pc = pic()
    local sp = P.species(b)
    if pc and sp and pc.elev then y = y - (pc.elev[sp] or 0) end
  end
  return y % 256
end

-- pokefirered/src/battle_anim_mons.c:1999
function P.coordAttr(b, attr)
  local pc, ms = pic()
  local sp = P.species(b) or 0
  local size = 0x88
  local yoff = 0
  if ms then
    local tbl = (b == "player") and ms.back or ms.front
    size = tbl[sp] or tbl[0] or 0x88
  end
  if pc then
    local tbl = (b == "player") and pc.back or pc.front
    yoff = tbl and tbl[sp] or 0
  end
  local w = floor(size / 16) * 8
  local h = (size % 16) * 8
  if attr == 0 then return h end
  if attr == 1 then return w end
  if attr == 4 then return P.coord(b, 2) - P.div(w, 2) end
  if attr == 5 then return P.coord(b, 2) + P.div(w, 2) end
  if attr == 2 then return P.coord(b, 3) - P.div(h, 2) end
  if attr == 3 then return P.coord(b, 3) + P.div(h, 2) end
  if attr == 6 then return P.coord(b, 1) + 31 - yoff end
  return 0
end

P.coord = AnimCoords.sideArg(P.coord, 1)
P.defaultY = AnimCoords.sideArg(P.defaultY, 1)
P.yWithElevation = AnimCoords.sideArg(P.yWithElevation, 1)
P.coordAttr = AnimCoords.sideArg(P.coordAttr, 1)

-- pokefirered/src/battle_anim_mons.c:1908
function P.subpriorityOf(b)
  return AnimCoords.subpriority(b)
end

-- pokefirered/src/battle_anim_mons.c:1924
function P.bgPriority(b)
  local vm = P.vm
  local bp = vm and vm._bgPrio
  if bp then
    return bp[AnimCoords.bgPriorityRank(b)] or 2
  end
  return 2
end

-- pokefirered/src/battle_anim_mons.c:1934
function P.bgPriorityRank(b)
  return AnimCoords.bgPriorityRank(b)
end

function P.present(b)
  local ok, Anim = pcall(require, "src.core.game3.battle.anim")
  if not ok or not Anim then return nil end
  return Anim.present(b)
end

local MonMT = {}
local MonMethods = {}

MonMT.__index = function(m, k)
  local p = rawget(m, "_p")
  if k == "x2" then return (p.ox or 0) - (p._g2bx or 0) end
  if k == "y2" then return (p.oy or 0) - (p._g2by or 0) end
  if k == "x" then return rawget(m, "_bxBase") + (p._g2bx or 0) end
  if k == "y" then return rawget(m, "_byBase") + (p._g2by or 0) end
  if k == "invisible" then return p.visible == false end
  return MonMethods[k]
end

MonMT.__newindex = function(m, k, v)
  local p = rawget(m, "_p")
  if k == "x2" then
    p.ox = (p._g2bx or 0) + v
  elseif k == "y2" then
    p.oy = (p._g2by or 0) + v
  elseif k == "x" then
    local x2 = (p.ox or 0) - (p._g2bx or 0)
    p._g2bx = v - rawget(m, "_bxBase")
    p.ox = p._g2bx + x2
  elseif k == "y" then
    local y2 = (p.oy or 0) - (p._g2by or 0)
    p._g2by = v - rawget(m, "_byBase")
    p.oy = p._g2by + y2
  elseif k == "invisible" then
    p.visible = not v
  else
    rawset(m, k, v)
  end
end

-- pokefirered/src/battle_anim_mons.c:1174
function MonMethods.setRotScale(m, xScale, yScale, rotation)
  local p = rawget(m, "_p")
  xScale = P.s16(xScale)
  yScale = P.s16(yScale)
  rotation = P.u16(rotation)
  local th = rotation / 65536 * 2 * math.pi
  local c, s = math.cos(th), math.sin(th)
  m.matA = trunc(xScale * c)
  m.matB = trunc(-xScale * s)
  m.matC = trunc(yScale * s)
  m.matD = trunc(yScale * c)
  p.sx = (xScale ~= 0) and (256 / xScale) or 0
  p.sy = (yScale ~= 0) and (256 / yScale) or 0
  p.rotation = -th
  p._g2affine = true
end

function MonMethods.resetRotScale(m)
  local p = rawget(m, "_p")
  m.matA, m.matB, m.matC, m.matD = 256, 0, 0, 256
  p.sx = 1
  p.sy = 1
  p.rotation = 0
  p._g2affine = nil
end

function MonMethods.present(m) return rawget(m, "_p") end

function P.mon(b)
  if not b then return nil end
  local p = P.present(b)
  if not p then return nil end
  local m = {
    _p = p,
    _side = b,
    _bxBase = P.coord(b, 0),
    _byBase = P.defaultY(b),
    matA = 256, matB = 0, matC = 0, matD = 256,
  }
  if p._g2mat then
    m.matA, m.matB, m.matC, m.matD = p._g2mat[1], p._g2mat[2], p._g2mat[3], p._g2mat[4]
  end
  return setmetatable(m, MonMT)
end

function P.monById(which)
  return P.mon(P.battler(which))
end

function P.setSpriteRotScale(m, xs, ys, rot)
  if not m then return end
  m:setRotScale(xs, ys, rot)
  local p = m:present()
  p._g2mat = { m.matA, m.matB, m.matC, m.matD }
end

function P.resetSpriteRotScale(m)
  if not m then return end
  m:resetRotScale()
  m:present()._g2mat = nil
end

-- pokefirered/src/battle_anim_mons.c:1233
function P.setYOffsetFromRotation(m)
  if not m then return end
  local c = m.matC
  if c < 0 then c = -c end
  m.y2 = P.asr(c, 3)
end

-- pokefirered/src/battle_anim_mons.c:1762
function P.setYOffsetFromYScale(m)
  if not m then return end
  local pc = pic()
  local sp = P.species(m._side)
  local yd = 64
  if pc and sp then
    local tbl = (m._side == "player") and pc.back or pc.front
    yd = tbl and tbl[sp] or 0
  end
  local var = 64 - yd * 2
  local d = m.matD
  local var2 = (d ~= 0) and P.div(var * 256, d) or 0
  if var2 > 128 then var2 = 128 end
  m.y2 = P.div(var - var2, 2)
end

local function F(img, dur, h, v) return { img = img, dur = dur or 0, h = h and true or false, v = v and true or false } end
local function J(t) return { jump = t } end
local function L(n) return { loop = n } end
local END = { stop = true }
P.F, P.J, P.L, P.END = F, J, L, END

local function A(xs, ys, rot, dur) return { xs = xs, ys = ys, rot = rot, dur = dur } end
local function AJ(t) return { jump = t } end
local function AL(n) return { loop = n } end
local AEND = { stop = true }
P.A, P.AJ, P.AL, P.AEND = A, AJ, AL, AEND

P.DUMMY_ANIMS = { { END } }
P.DUMMY_AFFINE = { { AEND } }

P.TEMPLATES = {}

function P.affineCmds(name)
  P.tmpl("")
  local t = P._affineTables
  return t and t[name]
end

function P.tmpl(name)
  if not name then return nil end
  if not P._tmplLoaded then
    P._tmplLoaded = true
    local ok, t = pcall(require, "src.core.game3.battle.anim_port.g2_templates")
    if ok and type(t) == "table" then
      for k, v in pairs(t) do
        if k == "_affine" then
          P._affineTables = v
        elseif P.TEMPLATES[k] == nil then
          P.TEMPLATES[k] = v
        end
      end
    end
  end
  return P.TEMPLATES[name]
end

local function cmd(s, idx)
  local a = s.anims and s.anims[s.animNum + 1]
  return a and a[idx + 1] or END
end

local function flip_bits(s, h, v)
  s.fh = h and true or false
  s.fv = v and true or false
end

local function set_frame(s, c)
  local dur = c.dur or 0
  if dur > 0 then dur = dur - 1 end
  s.animDelayCounter = dur
  if (s.affineMode % 2) == 0 then flip_bits(s, c.h, c.v) end
  s.tileNum = c.img
end

-- pokefirered/src/sprite.c:905
local function begin_anim(s)
  s.animCmdIndex = 0
  s.animEnded = false
  s.animLoopCounter = 0
  local c = cmd(s, 0)
  if c.img ~= nil then
    s.animBeginning = false
    set_frame(s, c)
  end
end

local continue_anim

local function jump_to_top_of_loop(s)
  if s.animLoopCounter ~= 0 then
    s.animCmdIndex = s.animCmdIndex - 1
    while true do
      local prev = cmd(s, s.animCmdIndex - 1)
      if prev.loop ~= nil then break end
      if s.animCmdIndex == 0 then break end
      s.animCmdIndex = s.animCmdIndex - 1
    end
    s.animCmdIndex = s.animCmdIndex - 1
  end
end

local function run_anim_cmd(s)
  local c = cmd(s, s.animCmdIndex)
  if c.loop ~= nil then
    if s.animLoopCounter ~= 0 then
      s.animLoopCounter = s.animLoopCounter - 1
    else
      s.animLoopCounter = c.loop
    end
    jump_to_top_of_loop(s)
    continue_anim(s)
  elseif c.jump ~= nil then
    s.animCmdIndex = c.jump
    set_frame(s, cmd(s, s.animCmdIndex))
  elseif c.stop then
    s.animCmdIndex = s.animCmdIndex - 1
    s.animEnded = true
  else
    set_frame(s, c)
  end
end

-- pokefirered/src/sprite.c:939
continue_anim = function(s)
  if s.animDelayCounter ~= 0 then
    if not s.animPaused then s.animDelayCounter = s.animDelayCounter - 1 end
    local c = cmd(s, s.animCmdIndex)
    if (s.affineMode % 2) == 0 then flip_bits(s, c.h, c.v) end
  elseif not s.animPaused then
    s.animCmdIndex = s.animCmdIndex + 1
    run_anim_cmd(s)
  end
end

local function acmd(s, idx)
  local st = s.aff
  local a = s.affine and s.affine[st.animNum + 1]
  return a and a[idx + 1] or AEND
end

-- pokefirered/src/sprite.c:1292
local function update_matrix(s)
  local st = s.aff
  local xs = (st.xScale ~= 0) and P.div(0x10000, st.xScale) or 0
  local ys = (st.yScale ~= 0) and P.div(0x10000, st.yScale) or 0
  local th = st.rotation / 65536 * 2 * math.pi
  local c, sn = math.cos(th), math.sin(th)
  s.matA = trunc(xs * c)
  s.matB = trunc(-xs * sn)
  s.matC = trunc(ys * sn)
  s.matD = trunc(ys * c)
end

local function apply_relative(s, f)
  local st = s.aff
  st.xScale = P.s16(st.xScale + (f.xs or 0))
  st.yScale = P.s16(st.yScale + (f.ys or 0))
  local r = P.s8(f.rot or 0) * 256
  st.rotation = P.u16(st.rotation + r)
  st.rotation = st.rotation - st.rotation % 256
  update_matrix(s)
end

local function apply_frame(s, f)
  local dur = f.dur or 0
  if dur > 0 then
    apply_relative(s, f)
    return dur - 1
  end
  local st = s.aff
  st.xScale = P.s16(f.xs or 0)
  st.yScale = P.s16(f.ys or 0)
  st.rotation = P.u16(P.s8(f.rot or 0) * 256)
  apply_relative(s, { xs = 0, ys = 0, rot = 0 })
  return 0
end

local continue_affine

local function affine_jump_to_top(s)
  local st = s.aff
  if st.loopCounter ~= 0 then
    st.animCmdIndex = st.animCmdIndex - 1
    while true do
      local prev = acmd(s, st.animCmdIndex - 1)
      if prev.loop ~= nil then break end
      if st.animCmdIndex == 0 then break end
      st.animCmdIndex = st.animCmdIndex - 1
    end
    st.animCmdIndex = st.animCmdIndex - 1
  end
end

-- pokefirered/src/sprite.c:1063
local function begin_affine(s)
  if (s.affineMode % 2) == 1 then
    local first = s.affine and s.affine[1] and s.affine[1][1]
    if first and not first.stop then
      local st = s.aff
      st.animCmdIndex = 0
      st.delayCounter = 0
      st.loopCounter = 0
      local f = acmd(s, 0)
      s.affineAnimBeginning = false
      s.affineAnimEnded = false
      st.delayCounter = apply_frame(s, f)
    end
  end
end

-- pokefirered/src/sprite.c:1080
continue_affine = function(s)
  if (s.affineMode % 2) ~= 1 then return end
  local st = s.aff
  if st.delayCounter ~= 0 then
    if not s.affineAnimPaused then
      st.delayCounter = st.delayCounter - 1
      apply_relative(s, acmd(s, st.animCmdIndex))
    end
  elseif s.affineAnimPaused then
    return
  else
    st.animCmdIndex = st.animCmdIndex + 1
    local c = acmd(s, st.animCmdIndex)
    if c.loop ~= nil then
      if st.loopCounter ~= 0 then
        st.loopCounter = st.loopCounter - 1
      else
        st.loopCounter = c.loop
      end
      affine_jump_to_top(s)
      continue_affine(s)
    elseif c.jump ~= nil then
      st.animCmdIndex = c.jump
      st.delayCounter = apply_frame(s, acmd(s, st.animCmdIndex))
    elseif c.stop then
      s.affineAnimEnded = true
      st.animCmdIndex = st.animCmdIndex - 1
      apply_relative(s, { xs = 0, ys = 0, rot = 0 })
    else
      st.delayCounter = apply_frame(s, c)
    end
  end
end

-- pokefirered/src/sprite.c:897
function P.animateSprite(s)
  if s.animBeginning then begin_anim(s) else continue_anim(s) end
  if s.affineAnimBeginning then begin_affine(s) else continue_affine(s) end
end

-- pokefirered/src/sprite.c:1336
function P.startAnim(s, n)
  s.animNum = floor(n or 0)
  s.animBeginning = true
  s.animEnded = false
end

-- pokefirered/src/sprite.c:1349
function P.seekAnim(s, idx)
  local paused = s.animPaused
  s.animCmdIndex = floor(idx) - 1
  s.animDelayCounter = 0
  s.animBeginning = false
  s.animEnded = false
  s.animPaused = false
  continue_anim(s)
  if s.animDelayCounter ~= 0 then s.animDelayCounter = s.animDelayCounter + 1 end
  s.animPaused = paused
end

local function reset_affine_state(s, n)
  s.aff = s.aff or {}
  local st = s.aff
  st.animNum = n or 0
  st.animCmdIndex = 0
  st.delayCounter = 0
  st.loopCounter = 0
  st.xScale = 0x100
  st.yScale = 0x100
  st.rotation = 0
end

-- pokefirered/src/sprite.c:1363
function P.startAffineAnim(s, n)
  reset_affine_state(s, floor(n or 0))
  s.affineAnimBeginning = true
  s.affineAnimEnded = false
end

function P.changeAffineAnim(s, n)
  s.aff.animNum = floor(n or 0)
  s.affineAnimBeginning = true
  s.affineAnimEnded = false
end

-- pokefirered/src/battle_anim_mons.c:1244
function P.trySetRotScale(s, recalc, xScale, yScale, rotation)
  if (s.affineMode % 2) == 1 then
    s.affineAnimPaused = true
    xScale = P.s16(xScale)
    yScale = P.s16(yScale)
    local th = P.u16(rotation) / 65536 * 2 * math.pi
    local c, sn = math.cos(th), math.sin(th)
    s.matA = trunc(xScale * c)
    s.matB = trunc(-xScale * sn)
    s.matC = trunc(yScale * sn)
    s.matD = trunc(yScale * c)
  end
end

function P.tryResetAffine(s)
  P.trySetRotScale(s, true, 0x100, 0x100, 0)
  s.affineAnimPaused = false
end

function P.setMatrix(s, a, b, c, d)
  s.matA, s.matB, s.matC, s.matD = a, b, c, d
end

function P.zFor(prio, sub)
  prio = prio or 2
  sub = sub or 0
  if prio < 2 then
    return 250 + (2 - prio) * 20 + (255 - sub) / 64
  elseif prio > 2 then
    return 2 + (255 - sub) / 64
  end
  if sub < 30 then
    return 201 + (30 - sub) / 2
  elseif sub < 40 then
    return 101 + (40 - sub) / 2
  end
  return 10 + (255 - sub) / 4
end

function P.sync(s)
  s.ox = s.x2
  s.oy = s.y2
  s.visible = not s.invisible
  s.z = P.zFor(s.oamPriority, s.subpriority)
  s._pz = true
end

local runner

local SHEET_CACHE = setmetatable({}, { __mode = "k" })

local function tag_info(tag)
  local vm = P.vm
  local pack = vm and vm._pack
  if not pack then
    local ok, Anim = pcall(require, "src.core.game3.battle.anim")
    pack = ok and Anim and Anim._pack
  end
  local t = pack and pack.tags and pack.tags[tag]
  return t
end
P.tagInfo = tag_info

local function quad_for(img, sx, sy, w, h)
  local iw, ih = img:getDimensions()
  local key = sx .. ":" .. sy .. ":" .. w .. ":" .. h
  local c = SHEET_CACHE[img]
  if not c then c = {}; SHEET_CACHE[img] = c end
  local q = c[key]
  if not q then
    q = love.graphics.newQuad(sx, sy, w, h, iw, ih)
    c[key] = q
  end
  return q
end

local SHADERS = {}

local BLEND_SRC = [[
extern float coeff;
extern vec3 target;
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec4 c = Texel(tex, tc);
  vec3 c5 = floor(c.rgb * 31.0 + 0.5);
  vec3 o = c5 + floor((target - c5) * coeff / 16.0);
  return vec4(o / 31.0, c.a) * color;
}
]]

local ROT_SRC = [[
extern float rot;
extern float lo;
extern float hi;
extern float count;
extern vec3 cols[16];
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec4 c = Texel(tex, tc);
  if (c.a < 0.01) return c * color;
  float best = 1e9;
  float bi = -1.0;
  for (int i = 1; i < 16; i++) {
    float fi = float(i);
    if (fi >= lo && fi <= hi) {
      vec3 d = c.rgb - cols[i];
      float e = dot(d, d);
      if (e < best) { best = e; bi = fi; }
    }
  }
  if (bi < 0.0 || best > 0.002) return c * color;
  float src = mod(bi - lo - rot, count) + lo;
  vec3 o = c.rgb;
  for (int j = 1; j < 16; j++) {
    if (float(j) == src) o = cols[j];
  }
  return vec4(o, c.a) * color;
}
]]

local GRAY_SRC = [[
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec4 c = Texel(tex, tc);
  vec3 c5 = floor(c.rgb * 31.0 + 0.5);
  float g = floor((c5.r + c5.g + c5.b) / 3.0);
  return vec4(vec3(g / 31.0), c.a) * color;
}
]]

local MAP_SRC = [[
extern vec3 src[16];
extern vec3 dst[16];
vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec4 c = Texel(tex, tc);
  if (c.a < 0.01) return c * color;
  float best = 1e9;
  vec3 o = c.rgb;
  for (int i = 1; i < 16; i++) {
    vec3 d = c.rgb - src[i];
    float e = dot(d, d);
    if (e < best) { best = e; o = dst[i]; }
  }
  if (best > 0.002) o = c.rgb;
  return vec4(o, c.a) * color;
}
]]

local function shader(name, src)
  if SHADERS[name] == nil then
    if love and love.graphics and love.graphics.newShader then
      local ok, sh = pcall(love.graphics.newShader, src)
      SHADERS[name] = ok and sh or false
    else
      SHADERS[name] = false
    end
  end
  return SHADERS[name]
end

local function rgb555(c)
  c = tonumber(c) or 0
  return c % 32, floor(c / 32) % 32, floor(c / 1024) % 32
end
P.rgb555 = rgb555

local function current_blend(s)
  if s.palBlend and (s.palBlend[1] or 0) > 0 then
    local r, g, b = rgb555(s.palBlend[2])
    return s.palBlend[1], r, g, b
  end
  local tb
  local vm = P.vm
  if vm and vm._tagBlend then tb = vm._tagBlend[s.tag] end
  if not tb then
    local ok, Anim = pcall(require, "src.core.game3.battle.anim")
    tb = ok and Anim and Anim._tagBlend and Anim._tagBlend[s.tag]
  end
  if tb and (tb.coeff or 0) > 0 then
    local r, g, b = rgb555(tb.color)
    return tb.coeff, r, g, b
  end
  return 0
end

P.palRot = {}
P.tagFx = {}

function P.tagState(tag)
  local vm = P.vm
  local key = vm and vm.loadedTags
  if P._tagKey ~= key then
    P._tagKey = key
    P.tagFx = {}
  end
  local st = P.tagFx[tag]
  if not st then
    st = {}
    P.tagFx[tag] = st
  end
  return st
end

function P.tagFxFor(tag)
  if not tag then return nil end
  local vm = P.vm
  if P._tagKey ~= (vm and vm.loadedTags) then return nil end
  return P.tagFx[tag]
end

function P.palRotState(tag)
  local vm = P.vm
  local key = vm and vm.loadedTags
  if P._palKey ~= key then
    P._palKey = key
    P.palRot = {}
  end
  local st = P.palRot[tag]
  if not st then
    st = { rot = 0, lo = 1, hi = 8 }
    P.palRot[tag] = st
  end
  return st
end

function P.palRotateFor(tag)
  if not tag then return nil end
  local vm = P.vm
  if P._palKey ~= (vm and vm.loadedTags) then return nil end
  local st = P.palRot[tag]
  if st and st.cols and st.rot ~= 0 then return st end
  return nil
end

local function draw_pret(s, vm)
  if s.callback ~= runner then
    s.customDraw = nil
    return
  end
  if s.invisible or not s.image then return end
  local img = s.image
  local w, h = s.w, s.h
  local iw = img:getWidth()
  local tile = floor(s.tileNum or 0) + floor(s.tileBase or 0)
  local x = floor(s.x + s.x2 + 0.5)
  local y = floor(s.y + s.y2 + 0.5)
  if s.x + s.x2 < -128 or s.x + s.x2 > 368 or s.y + s.y2 < -128 or s.y + s.y2 > 288 then return end

  local alpha = s._drawAlpha
  if alpha == nil then
    alpha = s.alpha or 1
    if s.objBlend then
      local ba = vm and vm.bldAlpha
      if ba then
        alpha = math.min(1, (tonumber(ba.eva or ba[1]) or 16) / 16)
      end
    end
  end
  if s.alphaOverride then alpha = s.alphaOverride end

  local sh = nil
  local coeff, br, bg, bb = current_blend(s)
  local pr = s.palRotate or P.palRotateFor(s.tag)
  local tfx = P.tagFxFor(s.tag)
  local pmap = s.palMap
  _pfxBlendOpts.coeff = coeff
  _pfxBlendOpts.color = AnimPal.pack(br or 0, bg or 0, bb or 0)
  _pfxBlendOpts.gray = ((tfx and tfx.gray) or s.gray) and true or nil
  local pimg = AnimPal.begin(s, img, _pfxBlendOpts)
  if pimg then
    img = pimg
  elseif pmap then
    sh = shader("map", MAP_SRC)
    if sh then
      pcall(function()
        sh:send("src", unpack(pmap.src))
        sh:send("dst", unpack(pmap.dst))
      end)
    end
  elseif (tfx and tfx.gray) or s.gray then
    sh = shader("gray", GRAY_SRC)
  elseif pr then
    sh = shader("rot", ROT_SRC)
    if sh then
      pcall(function()
        sh:send("rot", pr.rot or 0)
        sh:send("lo", pr.lo or 1)
        sh:send("hi", pr.hi or 8)
        sh:send("count", (pr.hi or 8) - (pr.lo or 1) + 1)
        sh:send("cols", unpack(pr.cols))
      end)
    end
  elseif coeff and coeff > 0 then
    sh = shader("blend", BLEND_SRC)
    if sh then
      pcall(function()
        sh:send("coeff", coeff)
        sh:send("target", { br, bg, bb })
      end)
    end
  end

  love.graphics.push()
  love.graphics.translate(x, y)
  if (s.affineMode % 2) == 1 then
    local a, b, c, d = (s.matA or 256) / 256, (s.matB or 0) / 256, (s.matC or 0) / 256, (s.matD or 256) / 256
    local det = a * d - b * c
    if math.abs(det) < 1e-6 then
      love.graphics.pop()
      return
    end
    local ia, ib, ic, id = d / det, -b / det, -c / det, a / det
    if love.math and love.math.newTransform then
      local t = s._g2xf or love.math.newTransform()
      s._g2xf = t
      t:setMatrix(ia, ib, 0, 0, ic, id, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
      love.graphics.applyTransform(t)
    end
  else
    local fh = (s.fh and not s.pHFlip) or (not s.fh and s.pHFlip)
    local fv = (s.fv and not s.pVFlip) or (not s.fv and s.pVFlip)
    love.graphics.scale(fh and -1 or 1, fv and -1 or 1)
  end
  if sh then love.graphics.setShader(sh) end
  love.graphics.setColor(1, 1, 1, alpha)
  local tpr = math.max(1, floor(iw / 8))
  local fw = floor(w / 8)
  local ih = img:getHeight()
  if iw == w and (tile % fw) == 0 then
    local sy = floor(tile / fw) * 8
    if sy < ih then
      love.graphics.draw(img, quad_for(img, 0, sy, w, h), -w / 2, -h / 2)
    end
  else
    for r = 0, floor(h / 8) - 1 do
      for cc = 0, fw - 1 do
        local ti = tile + r * fw + cc
        local sx = (ti % tpr) * 8
        local sy = floor(ti / tpr) * 8
        if sy < ih then
          love.graphics.draw(img, quad_for(img, sx, sy, 8, 8), -w / 2 + cc * 8, -h / 2 + r * 8)
        end
      end
    end
  end
  if sh or pimg then love.graphics.setShader() end
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1, 1)
end
P.drawPret = draw_pret

local function clear_pret(s)
  s.pret = nil
  s.pcb = nil
  s.customDraw = nil
  s.stored = nil
  s.anims = nil
  s.affine = nil
  s.aff = nil
  s.palRotate = nil
  s.palBlend = nil
  s.palMap = nil
  s.gray = nil
  s.objBlend = nil
  s.alphaOverride = nil
  s.g2 = nil
  s.tileBase = nil
  s._g2xf = nil
end

-- pokefirered/src/battle_anim.c:250
function P.destroy(s)
  if not s then return end
  clear_pret(s)
  AnimSprites.release(s)
end

function P.alive(s)
  return s and s.active and s.callback == runner
end

runner = function(s)
  if s.pcb then s.pcb(s) end
  if s.active and s.callback == runner then
    P.animateSprite(s)
    P.sync(s)
  end
end
P.runner = runner

local function init_pret(s, def, x, y, sub)
  s.pret = true
  s.x = x or 0
  s.y = y or 0
  s.x2 = 0
  s.y2 = 0
  s.ox = 0
  s.oy = 0
  s.invisible = false
  s.pHFlip = false
  s.pVFlip = false
  s.hFlip = false
  s.vFlip = false
  s.fh = false
  s.fv = false
  s.rotation = 0
  s.scaleX = 1
  s.scaleY = 1
  s.alpha = 1
  for i = 0, 7 do s.data[i] = 0 end
  s.g2 = {}
  s.w = def and def.w or s.w or 32
  s.h = def and def.h or s.h or 32
  s._baseW = s.w
  s._baseH = s.h
  s.anims = def and def.anims or P.DUMMY_ANIMS
  s.affine = def and def.affine or P.DUMMY_AFFINE
  s.affineMode = def and def.affineMode or 0
  s.objBlend = def and def.blend or false
  s.oamPriority = def and def.priority or 2
  s.subpriority = sub or 0
  s.tileNum = 0
  s.tileBase = 0
  s.animNum = 0
  s.animCmdIndex = 0
  s.animDelayCounter = 0
  s.animBeginning = true
  s.animEnded = false
  s.animPaused = false
  s.animLoopCounter = 0
  reset_affine_state(s, 0)
  s.affineAnimBeginning = true
  s.affineAnimEnded = false
  s.affineAnimPaused = false
  s.matA, s.matB, s.matC, s.matD = 256, 0, 0, 256
  s.blendMode = "alpha"
  s.callback = runner
  s.customDraw = draw_pret
  if def and def.tag and not s.image then
    local ti = tag_info(def.tag)
    if ti then s.image = ti.image end
  end
end

local function op_subpriority(op)
  local raw = tonumber(op and op.subpriority) or 0
  local b = (op and op.animBattler == "target") and P.tgt() or P.atk()
  local v
  if raw >= 64 then v = raw - 64 else v = -raw end
  local sub = P.subpriorityOf(b) + v
  if sub < 3 then sub = 3 end
  return sub
end
P.opSubpriority = op_subpriority

-- pokefirered/src/battle_anim.c:349
function P.enter(s, cb)
  local vm = s._vm or P.vm
  P.setVm(vm)
  local def = P.tmpl(s.template)
  if not def then
    def = { w = s._baseW or s.w or 32, h = s._baseH or s.h or 32, tag = s.tag }
  end
  local op = s._op
  local args = s._args or (op and op.args) or {}
  local ga = P.args()
  for i, v in ipairs(args) do ga[i - 1] = tonumber(v) or 0 end
  local tb = P.tgt()
  init_pret(s, def, P.coord(tb, 2), P.coord(tb, 3), op_subpriority(op))
  s.pcb = cb
  cb(s)
  if s.active and s.callback == runner then
    P.animateSprite(s)
    P.sync(s)
  end
end

-- pokefirered/src/sprite.c:494
function P.createSprite(name, x, y, sub, andAnimate, counted, cbOverride)
  local def = P.tmpl(name)
  if not def then return nil end
  local img
  local ti = def.tag and tag_info(def.tag)
  if ti then img = ti.image end
  local s = AnimSprites.acquire({ x = x, y = y, image = img, tag = def.tag, template = name, w = def.w, h = def.h })
  if not s then return nil end
  s._vm = P.vm
  s._g4counted = counted and true or nil
  init_pret(s, def, x, y, sub)
  local own = def.cbName and P.CB[def.cbName]
  if cbOverride ~= nil then own = cbOverride end
  if cbOverride == nil and not own and def.cbName and def.cbName ~= "SpriteCallbackDummy" then
    local AnimCallbacks = require("src.core.game3.battle.anim_callbacks")
    local fn = AnimCallbacks.get(def.cbName)
    local ga = P.args()
    local a = {}
    for i = 0, 7 do a[i + 1] = ga[i] or 0 end
    s._args = a
    s._cbName = def.cbName
    s._op = { template = name, args = a, animBattler = "target", subpriority = 0, callback = def.cbName }
    s.customDraw = nil
    s.pret = nil
    s.callback = fn
    s.ox, s.oy = 0, 0
    s._baseW, s._baseH = def.w, def.h
    if andAnimate and fn then fn(s) end
    return s
  end
  s.pcb = own or nil
  if andAnimate then
    if s.pcb then s.pcb(s) end
    if s.active and s.callback == runner then
      P.animateSprite(s)
      P.sync(s)
    end
  else
    P.sync(s)
  end
  return s
end

P.CB = {}

function P.setCallback(s, fn)
  s.pcb = fn
end

function P.storeCallback(s, fn)
  s.stored = fn
end

function P.runStored(s)
  s.pcb = s.stored
end

-- pokefirered/src/battle_anim_mons.c:521
function P.WaitAnimForDuration(s)
  if s.data[0] > 0 then
    s.data[0] = s.data[0] - 1
  else
    P.runStored(s)
  end
end

function P.DestroyAnimSprite(s) P.destroy(s) end
P.DestroySpriteAndMatrix = P.DestroyAnimSprite

function P.RunStoredCallbackWhenAnimEnds(s)
  if s.animEnded then P.runStored(s) end
end

function P.RunStoredCallbackWhenAffineAnimEnds(s)
  if s.affineAnimEnded then P.runStored(s) end
end

-- pokefirered/src/battle_anim_mons.c:412
function P.TranslateSpriteInCircle(s)
  local d = s.data
  if d[3] ~= 0 then
    s.x2 = P.Sin(d[0], d[1])
    s.y2 = P.Cos(d[0], d[1])
    d[0] = d[0] + d[2]
    if d[0] >= 0x100 then d[0] = d[0] - 0x100 elseif d[0] < 0 then d[0] = d[0] + 0x100 end
    d[3] = d[3] - 1
  else
    P.runStored(s)
  end
end

-- pokefirered/src/battle_anim_mons.c:433
function P.TranslateSpriteInGrowingCircle(s)
  local d = s.data
  if d[3] ~= 0 then
    local amp = P.asr(d[5], 8) + d[1]
    s.x2 = P.Sin(d[0], amp)
    s.y2 = P.Cos(d[0], amp)
    d[0] = d[0] + d[2]
    d[5] = P.s16(d[5] + d[4])
    if d[0] >= 0x100 then d[0] = d[0] - 0x100 elseif d[0] < 0 then d[0] = d[0] + 0x100 end
    d[3] = d[3] - 1
  else
    P.runStored(s)
  end
end

-- pokefirered/src/battle_anim_mons.c:486
function P.TranslateSpriteInEllipse(s)
  local d = s.data
  if d[3] ~= 0 then
    s.x2 = P.Sin(d[0], d[1])
    s.y2 = P.Cos(d[0], d[4])
    d[0] = d[0] + d[2]
    if d[0] >= 0x100 then d[0] = d[0] - 0x100 elseif d[0] < 0 then d[0] = d[0] + 0x100 end
    d[3] = d[3] - 1
  else
    P.runStored(s)
  end
end

-- pokefirered/src/battle_anim_mons.c:562
function P.TranslateSpriteLinear(s)
  local d = s.data
  if d[0] > 0 then
    d[0] = d[0] - 1
    s.x2 = s.x2 + d[1]
    s.y2 = s.y2 + d[2]
  else
    P.runStored(s)
  end
end

-- pokefirered/src/battle_anim_mons.c:576
function P.TranslateSpriteLinearFixedPoint(s)
  local d = s.data
  if d[0] > 0 then
    d[0] = d[0] - 1
    d[3] = P.s16(d[3] + d[1])
    d[4] = P.s16(d[4] + d[2])
    s.x2 = P.asr(d[3], 8)
    s.y2 = P.asr(d[4], 8)
  else
    P.runStored(s)
  end
end

-- pokefirered/src/battle_anim_mons.c:651
function P.TranslateSpriteLinearAndFlicker(s)
  local d = s.data
  if d[0] > 0 then
    d[0] = d[0] - 1
    s.x2 = P.asr(d[2], 8)
    d[2] = P.s16(d[2] + d[1])
    s.y2 = P.asr(d[4], 8)
    d[4] = P.s16(d[4] + d[3])
    if d[5] ~= 0 and P.mod(d[0], d[5]) == 0 then
      s.invisible = not s.invisible
    end
  else
    P.runStored(s)
  end
end

-- pokefirered/src/battle_anim_mons.c:735
function P.SetAnimSpriteInitialXOffset(s, xOffset)
  local ax = P.coord(P.atk(), 0)
  local tx = P.coord(P.tgt(), 0)
  if ax > tx then
    s.x = s.x - xOffset
  elseif ax < tx then
    s.x = s.x + xOffset
  else
    if P.atk() ~= "player" then s.x = s.x - xOffset else s.x = s.x + xOffset end
  end
end

-- pokefirered/src/battle_anim_mons.c:792
function P.InitSpritePosToAnimTarget(s, respect)
  if not respect then
    s.x = P.coord(P.tgt(), 0)
    s.y = P.coord(P.tgt(), 1)
  end
  P.SetAnimSpriteInitialXOffset(s, P.arg(0))
  s.y = s.y + P.arg(1)
end

-- pokefirered/src/battle_anim_mons.c:805
function P.InitSpritePosToAnimAttacker(s, respect)
  if not respect then
    s.x = P.coord(P.atk(), 0)
    s.y = P.coord(P.atk(), 1)
  else
    s.x = P.coord(P.atk(), 2)
    s.y = P.coord(P.atk(), 3)
  end
  P.SetAnimSpriteInitialXOffset(s, P.arg(0))
  s.y = s.y + P.arg(1)
end

function P.SetSpriteCoordsToAnimAttackerCoords(s)
  s.x = P.coord(P.atk(), 2)
  s.y = P.coord(P.atk(), 3)
end

-- pokefirered/src/battle_anim_mons.c:988
function P.InitAnimLinearTranslation(s)
  local d = s.data
  local x = d[2] - d[1]
  local y = d[4] - d[3]
  local left = x < 0
  local up = y < 0
  local xd = P.u16(math.abs(x) * 256)
  local yd = P.u16(math.abs(y) * 256)
  local sp = d[0]
  xd = P.u16(P.div(xd, sp))
  yd = P.u16(P.div(yd, sp))
  if left then xd = xd - xd % 2 + 1 else xd = xd - xd % 2 end
  if up then yd = yd - yd % 2 + 1 else yd = yd - yd % 2 end
  d[1] = P.s16(xd)
  d[2] = P.s16(yd)
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
  if v1 % 2 == 1 then s.x2 = -floor(x / 256) else s.x2 = floor(x / 256) end
  if v2 % 2 == 1 then s.y2 = -floor(y / 256) else s.y2 = floor(y / 256) end
  d[3] = P.s16(x)
  d[4] = P.s16(y)
  d[0] = d[0] - 1
  return false
end

function P.AnimTranslateLinear_WithFollowup(s)
  if P.AnimTranslateLinear(s) then P.runStored(s) end
end

-- pokefirered/src/battle_anim_mons.c:1016
function P.StartAnimLinearTranslation(s)
  s.data[1] = s.x
  s.data[3] = s.y
  P.InitAnimLinearTranslation(s)
  s.pcb = P.AnimTranslateLinear_WithFollowup
  s.pcb(s)
end

-- pokefirered/src/battle_anim_mons.c:1074
function P.InitAnimLinearTranslationWithSpeed(s)
  local v1 = math.abs(s.data[2] - s.data[1]) * 256
  s.data[0] = P.div(v1, s.data[0])
  P.InitAnimLinearTranslation(s)
end

function P.InitAnimLinearTranslationWithSpeedAndPos(s)
  s.data[1] = s.x
  s.data[3] = s.y
  P.InitAnimLinearTranslationWithSpeed(s)
  s.pcb = P.AnimTranslateLinear_WithFollowup
  s.pcb(s)
end

-- pokefirered/src/battle_anim_mons.c:1091
local function init_fast_linear(s)
  local d = s.data
  local xd = d[2] - d[1]
  local yd = d[4] - d[3]
  local xs = xd < 0
  local ys = yd < 0
  local x2 = P.u16(math.abs(xd) * 16)
  local y2 = P.u16(math.abs(yd) * 16)
  x2 = P.u16(P.div(x2, d[0]))
  y2 = P.u16(P.div(y2, d[0]))
  if xs then x2 = x2 - x2 % 2 + 1 else x2 = x2 - x2 % 2 end
  if ys then y2 = y2 - y2 % 2 + 1 else y2 = y2 - y2 % 2 end
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
  if v1 % 2 == 1 then s.x2 = -floor(x / 16) else s.x2 = floor(x / 16) end
  if v2 % 2 == 1 then s.y2 = -floor(y / 16) else s.y2 = floor(y / 16) end
  d[3] = P.s16(x)
  d[4] = P.s16(y)
  d[0] = d[0] - 1
  return false
end

local function fast_wait_end(s)
  if P.AnimFastTranslateLinear(s) then P.runStored(s) end
end

function P.InitAndRunAnimFastLinearTranslation(s)
  s.data[1] = s.x
  s.data[3] = s.y
  init_fast_linear(s)
  s.pcb = fast_wait_end
  s.pcb(s)
end

-- pokefirered/src/battle_anim_mons.c:757
function P.InitAnimArcTranslation(s)
  s.data[1] = s.x
  s.data[3] = s.y
  P.InitAnimLinearTranslation(s)
  s.data[6] = P.div(0x8000, s.data[0])
  s.data[7] = 0
end

function P.TranslateAnimHorizontalArc(s)
  if P.AnimTranslateLinear(s) then return true end
  s.data[7] = P.s16(s.data[7] + s.data[6])
  s.y2 = s.y2 + P.Sin(P.u8(floor(s.data[7] / 256)), s.data[5])
  return false
end

function P.TranslateAnimVerticalArc(s)
  if P.AnimTranslateLinear(s) then return true end
  s.data[7] = P.s16(s.data[7] + s.data[6])
  s.x2 = s.x2 + P.Sin(P.u8(floor(s.data[7] / 256)), s.data[5])
  return false
end

-- pokefirered/src/battle_anim_mons.c:977
function P.InitSpriteDataForLinearTranslation(s)
  local d = s.data
  local x = P.s16((d[2] - d[1]) * 256)
  local y = P.s16((d[4] - d[3]) * 256)
  d[1] = P.div(x, d[0])
  d[2] = P.div(y, d[0])
  d[4] = 0
  d[3] = 0
end

-- pokefirered/src/battle_anim_mons.c:2098
function P.SetAverageBattlerPositions(b, respect)
  local xt, yt = 0, 1
  if respect then xt, yt = 2, 3 end
  local id = AnimCoords.idOf(b) or 1
  local x, y = P.coord(id, xt), P.coord(id, yt)
  if not AnimCoords.isDouble() then return x, y end
  local partner = AnimCoords.partner(id)
  return P.div(x + P.coord(partner, xt), 2), P.div(y + P.coord(partner, yt), 2)
end

-- pokefirered/src/battle_anim_mons.c:1482
function P.AnimTravelDiagonally(s)
  local r4, ctype = true, 3
  if P.arg(6) ~= 0 then r4, ctype = false, 1 end
  local battler
  if P.arg(5) == 0 then
    P.InitSpritePosToAnimAttacker(s, r4)
    battler = P.atk()
  else
    P.InitSpritePosToAnimTarget(s, r4)
    battler = P.tgt()
  end
  if P.atk() ~= "player" then P.setArg(2, -P.arg(2)) end
  P.InitSpritePosToAnimTarget(s, r4)
  s.data[0] = P.arg(4)
  s.data[2] = P.coord(battler, 2) + P.arg(2)
  s.data[4] = P.coord(battler, ctype) + P.arg(3)
  s.pcb = P.StartAnimLinearTranslation
  P.storeCallback(s, P.DestroyAnimSprite)
end

function P.taskEnter(t, vm)
  P.setVm(vm)
  local ga = P.args()
  for i = 0, 7 do
    local v = tonumber(t.data[i])
    if v and v ~= 0 then ga[i] = v end
  end
  for i = 0, 15 do t.data[i] = 0 end
  t.g2 = {}
end

function P.destroyTask(t)
  local AnimTasks = require("src.core.game3.battle.anim_tasks")
  t.g2 = nil
  AnimTasks._destroy(t)
end

function P.task(entry)
  return function(t, vm)
    P.taskEnter(t, vm)
    entry(t, vm)
  end
end

function P.cb(entry)
  return function(s)
    P.enter(s, entry)
  end
end

-- pokefirered/src/battle_anim_mons.c:1677
function P.PrepareAffineAnimInTaskData(t, m, cmds)
  t.data[7] = 0
  t.data[8] = 0
  t.data[9] = 0
  t.g2.affMon = m
  t.data[10] = 0x100
  t.data[11] = 0x100
  t.data[12] = 0
  t.g2.affCmds = cmds
end

-- pokefirered/src/battle_anim_mons.c:1690
function P.RunAffineAnimFromTaskData(t)
  local cmds = t.g2.affCmds
  local m = t.g2.affMon
  local c = cmds[t.data[7] + 1] or AEND
  if c.jump ~= nil then
    t.data[7] = c.jump
  elseif c.loop ~= nil then
    if c.loop ~= 0 then
      if t.data[9] ~= 0 then
        t.data[9] = t.data[9] - 1
        if t.data[9] == 0 then
          t.data[7] = t.data[7] + 1
          return true
        end
      else
        t.data[9] = c.loop
      end
      if t.data[7] == 0 then return true end
      while true do
        t.data[7] = t.data[7] - 1
        local prev = cmds[t.data[7] + 1]
        if prev and prev.loop ~= nil then
          t.data[7] = t.data[7] + 1
          return true
        end
        if t.data[7] == 0 then return true end
      end
    end
    t.data[7] = t.data[7] + 1
  elseif c.stop then
    if m then
      m.y2 = 0
      P.resetSpriteRotScale(m)
    end
    return false
  else
    if (c.dur or 0) == 0 then
      t.data[10] = c.xs
      t.data[11] = c.ys
      t.data[12] = P.u8(c.rot or 0)
      t.data[7] = t.data[7] + 1
      c = cmds[t.data[7] + 1] or AEND
    end
    t.data[10] = P.s16(t.data[10] + (c.xs or 0))
    t.data[11] = P.s16(t.data[11] + (c.ys or 0))
    t.data[12] = P.s16(t.data[12] + P.u8(c.rot or 0))
    if m then
      P.setSpriteRotScale(m, t.data[10], t.data[11], t.data[12])
      P.setYOffsetFromYScale(m)
    end
    t.data[8] = t.data[8] + 1
    if t.data[8] >= (c.dur or 0) then
      t.data[8] = 0
      t.data[7] = t.data[7] + 1
    end
  end
  return true
end

-- pokefirered/src/battle_anim_mons.c:1831
function P.SetSpriteSquashParams(t, m, xs0, ys0, xs1, ys1, dur)
  t.data[8] = dur
  t.g2.squashMon = m
  t.data[9] = xs0
  t.data[10] = ys0
  t.data[13] = xs1
  t.data[14] = ys1
  t.data[11] = P.div(xs1 - xs0, dur)
  t.data[12] = P.div(ys1 - ys0, dur)
end

function P.RunSpriteSquash(t)
  if t.data[8] == 0 then return 0 end
  t.data[8] = t.data[8] - 1
  if t.data[8] ~= 0 then
    t.data[9] = t.data[9] + t.data[11]
    t.data[10] = t.data[10] + t.data[12]
  else
    t.data[9] = t.data[13]
    t.data[10] = t.data[14]
  end
  local m = t.g2.squashMon
  if m then
    P.setSpriteRotScale(m, t.data[9], t.data[10], 0)
    if t.data[8] ~= 0 then P.setYOffsetFromYScale(m) else m.y2 = 0 end
  end
  return t.data[8]
end

function P.playSE(name, pan)
  pcall(function()
    local Audio = require("src.core.game3.audio")
    local SE = require("src.core.game3.se_ids")
    local id = SE[name] or name
    Audio.playSe(id, { pan = pan or 0 })
  end)
end

function P.customPanning()
  local vm = P.vm
  return vm and tonumber(vm.animCustomPanning) or 0
end

function P.pal()
  local ok, G1 = pcall(require, "src.core.game3.battle.anim_port.g1_pret")
  if ok and type(G1) == "table" and type(G1.Pal) == "table" and G1.Pal.blend then return G1.Pal end
  return nil
end

function P.palBlend(key, coeff, color)
  local Pal = P.pal()
  if Pal then
    if coeff and coeff > 0 then
      Pal.blend(key, coeff, color)
    elseif Pal.restore then
      Pal.restore(key)
    end
    if Pal.flush then pcall(Pal.flush) end
    return
  end
  local Anim = P.anim()
  if not Anim then return end
  local r, g, b = rgb555(color)
  if key == "bg" then
    Anim._bgBlend = (coeff and coeff > 0) and { coeff = coeff, color = color } or nil
  elseif key == "player" or key == "enemy" then
    local p = Anim.present(key)
    if p then
      p.blendCoeff = (coeff or 0) / 16
      p.blendColor = { r / 31, g / 31, b / 31 }
    end
  else
    local tag = tostring(key):match("^tag:(.+)$")
    if tag then
      Anim._tagBlend = Anim._tagBlend or {}
      Anim._tagBlend[tag] = (coeff and coeff > 0) and { coeff = coeff, color = color } or nil
    end
  end
end

function P.setMonGray(b, on)
  local p = P.present(b)
  if p then p.grayscale = on and true or nil end
end

-- pokefirered/src/battle_anim_mons.c:1409
function P.AnimSpriteOnMonPos(s)
  if s.data[0] == 0 then
    local var = P.arg(3) == 0
    if P.arg(2) == 0 then
      P.InitSpritePosToAnimAttacker(s, var)
    else
      P.InitSpritePosToAnimTarget(s, var)
    end
    s.data[0] = s.data[0] + 1
  elseif s.animEnded or s.affineAnimEnded then
    P.destroy(s)
  end
end

local function mon_pic(b)
  local sp = P.species(b)
  local entry
  local okU, Ui = pcall(require, "src.core.game3.battle.ui")
  if okU and Ui.battlerPic then entry = Ui.battlerPic(b, nil, sp) end
  return entry and entry.image
end

local function mon_draw_center(b)
  local okU, Ui = pcall(require, "src.core.game3.battle.ui")
  local base = BASE[b] or BASE.enemy
  local cx, cy = base[1], P.defaultY(b)
  if okU and Ui and Ui.battlerSpriteCenter then
    cx, cy = Ui.battlerSpriteCenter(b, P.species(b), { x = base[1], y = base[2] })
  end
  return cx, cy
end

local function draw_clone(s, vm)
  if s.callback ~= runner then
    s.customDraw = nil
    return
  end
  local img = s.g2 and s.g2.monImage
  if s.invisible or not img then return end
  local alpha = s._drawAlpha
  if alpha == nil then
    alpha = 1
    local ba = vm and vm.bldAlpha
    if s.objBlend and ba then alpha = math.min(1, (tonumber(ba.eva or ba[1]) or 16) / 16) end
  end
  love.graphics.push()
  love.graphics.translate(floor(s.g2.cx + s.x2 + 0.5), floor(s.g2.cy + s.y2 + 0.5))
  if (s.affineMode % 2) == 1 then
    local a, b, c, d = (s.matA or 256) / 256, (s.matB or 0) / 256, (s.matC or 0) / 256, (s.matD or 256) / 256
    local det = a * d - b * c
    if math.abs(det) > 1e-6 and love.math and love.math.newTransform then
      local t = s._g2xf or love.math.newTransform()
      s._g2xf = t
      t:setMatrix(d / det, -b / det, 0, 0, -c / det, a / det, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)
      love.graphics.applyTransform(t)
    end
  end
  local sh = s.gray and shader("gray", GRAY_SRC)
  if sh then love.graphics.setShader(sh) end
  love.graphics.setColor(1, 1, 1, alpha)
  love.graphics.draw(img, -32, -32)
  if sh then love.graphics.setShader() end
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1, 1)
end

-- pokefirered/src/battle_anim_mons.c:1517
function P.cloneMon(which, sub)
  local b = P.battler(which)
  if not b then return nil end
  local p = P.present(b)
  if not p or p.visible == false then return nil end
  local s = AnimSprites.acquire({ x = 0, y = 0 })
  if not s then return nil end
  s._vm = P.vm
  init_pret(s, { w = 64, h = 64 }, 0, 0, sub or P.subpriorityOf(b))
  local cx, cy = mon_draw_center(b)
  s.g2.cx = cx + (p.ox or 0)
  s.g2.cy = cy + (p.oy or 0)
  s.g2.monImage = mon_pic(b)
  s.objBlend = true
  s.customDraw = draw_clone
  s.pcb = nil
  P.sync(s)
  return s
end

function P.anim()
  local ok, Anim = pcall(require, "src.core.game3.battle.anim")
  return ok and Anim or nil
end

function P.monVisible(b)
  local p = P.present(b)
  return p and p.visible ~= false
end

return P
