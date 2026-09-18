local bit = require("bit")
local Trig = require("src.core.game3.trig")
local AnimSprites = require("src.core.game3.battle.anim_sprites")
local AnimCoords = require("src.core.game3.battle.anim_coords")

local band, bor, bxor, rshift, arshift, lshift = bit.band, bit.bor, bit.bxor, bit.rshift, bit.arshift, bit.lshift
local floor = math.floor

local P = {}

P.ANIM_ATTACKER = 0
P.ANIM_TARGET = 1
P.X = 0
P.Y = 1
P.X_2 = 2
P.Y_PIC_OFFSET = 3
P.Y_PIC_OFFSET_DEFAULT = 4
P.ATTR_HEIGHT = 0
P.ATTR_WIDTH = 1
P.ATTR_TOP = 2
P.ATTR_BOTTOM = 3
P.ATTR_LEFT = 4
P.ATTR_RIGHT = 5
P.ATTR_RAW_BOTTOM = 6
P.DISPLAY_WIDTH = 240
P.DISPLAY_HEIGHT = 160
P.SOUND_PAN_ATTACKER = -64
P.SOUND_PAN_TARGET = 63

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

function P.cmod(a, b)
  if b == 0 then return 0 end
  return a - P.cdiv(a, b) * b
end

P.band, P.bor, P.bxor, P.rshift, P.lshift, P.arshift = band, bor, bxor, rshift, lshift, arshift

-- pokefirered/src/trig.c:514
function P.Sin(index, amp)
  local v = Trig.SINE[band(floor(index), 0xFF) + 1]
  return P.s16(arshift(v * floor(amp), 8))
end

function P.Cos(index, amp)
  local v = Trig.SINE[band(floor(index), 0xFF) + 65]
  return P.s16(arshift(v * floor(amp), 8))
end

function P.gSine(i)
  return Trig.SINE[band(floor(i), 0xFF) + 1]
end

function P.anim()
  return package.loaded["src.core.game3.battle.anim"] or require("src.core.game3.battle.anim")
end

function P.hookVmReset()
  local AnimVm = package.loaded["src.core.game3.battle.anim_vm"]
  if type(AnimVm) ~= "table" or AnimVm._g1ResetHooked or type(AnimVm.reset) ~= "function" then return end
  AnimVm._g1ResetHooked = true
  local orig = AnimVm.reset
  AnimVm.reset = function(self, ...)
    local r = orig(self, ...)
    P.Pal.reset()
    P.Fade.active = false
    P.Fade.mode = nil
    self.hwFade = nil
    P.Pal.flush()
    return r
  end
end

function P.vm()
  local Anim = P.anim()
  P.hookVmReset()
  return Anim and Anim._vm
end

function P.atk(vm)
  vm = vm or P.vm()
  if vm and vm.allyPair and vm:allyPair() then return vm:attackerId() end
  return vm and vm.attackerSide and vm:attackerSide() or "player"
end

function P.tgt(vm)
  vm = vm or P.vm()
  if vm and vm.allyPair and vm:allyPair() then return vm:targetId() end
  return vm and vm.targetSide and vm:targetSide() or "enemy"
end

function P.other(side)
  return side == "player" and "enemy" or "player"
end

function P.sideOf(vm, animBattler)
  if tonumber(animBattler) == 0 then return P.atk(vm) end
  return P.tgt(vm)
end

-- pokefirered/src/battle_anim_mons.c:821
function P.isOpponent(side)
  if type(side) == "number" then return AnimCoords.sideOf(side) ~= "player" end
  return side ~= "player"
end

function P.atkId(vm)
  vm = vm or P.vm()
  return vm and vm.attackerId and vm:attackerId() or 0
end

function P.tgtId(vm)
  vm = vm or P.vm()
  return vm and vm.targetId and vm:targetId() or 1
end

-- pokefirered/src/battle_anim.c:617
function P.spriteVisible(id)
  if not AnimCoords.spritePresent(nil, id) then return false end
  local p = P.anim().present(id)
  return p ~= nil
end

function P.visibleIds(except1, except2)
  local out = {}
  for _, id in ipairs(AnimCoords.ids()) do
    if id ~= except1 and id ~= except2 and (id < 2 or P.spriteVisible(id)) then out[#out + 1] = id end
  end
  return out
end

function P.species(vm, side)
  vm = vm or P.vm()
  if not vm then return nil end
  if vm._speciesBySide and vm._speciesBySide[side] ~= nil then return tonumber(vm._speciesBySide[side]) end
  if vm.speciesForSide then return tonumber(vm:speciesForSide(side)) end
  return nil
end

local PicCoords, PicSizes
local function pic_tables()
  if PicCoords == nil then
    local ok, t = pcall(require, "src.core.game3.battle.pic_coords")
    PicCoords = ok and type(t) == "table" and t or false
    local ok2, t2 = pcall(require, "src.core.game3.battle.anim_port.g1_pic_sizes")
    PicSizes = ok2 and type(t2) == "table" and t2 or false
  end
  return PicCoords, PicSizes
end

-- pokefirered/src/battle_anim_mons.c:148
local function y_delta(side, sp)
  local pc = pic_tables()
  if not pc or not sp then return 0 end
  if side == "player" then return (pc.back and pc.back[sp]) or 0 end
  return (pc.front and pc.front[sp]) or 0
end

function P.yDelta(vm, side)
  return y_delta(side, P.species(vm, side))
end

-- pokefirered/src/battle_anim_mons.c:217
local function elevation(side, sp)
  local pc = pic_tables()
  if side == "player" or not pc or not sp then return 0 end
  return (pc.elev and pc.elev[sp]) or 0
end

-- pokefirered/src/battle_anim_mons.c:233
local function final_y(side, sp, withOffset)
  local offset = y_delta(side, sp)
  if side ~= "player" then offset = offset - elevation(side, sp) end
  local y = band(offset + P.COORDS[side].y, 0xFF)
  if withOffset then
    if side == "player" then y = band(y + 8, 0xFF) end
    if y > P.DISPLAY_HEIGHT - 64 + 8 then y = P.DISPLAY_HEIGHT - 64 + 8 end
  end
  return y
end

-- pokefirered/src/battle_anim_mons.c:105
function P.coord(vm, side, coordType)
  local base = P.COORDS[side] or P.COORDS.enemy
  if coordType == P.X or coordType == P.X_2 then return base.x end
  if coordType == P.Y then return base.y end
  local sp = P.species(vm, side)
  return final_y(side, sp, coordType == P.Y_PIC_OFFSET)
end

P.coord2 = P.coord

-- pokefirered/src/battle_anim_mons.c:305
function P.yWithElevation(vm, side)
  local y = P.coord(vm, side, P.Y)
  if side ~= "player" then
    y = band(y - elevation(side, P.species(vm, side)), 0xFF)
  end
  return y
end

-- pokefirered/src/battle_anim_mons.c:1999
function P.attr(vm, side, attr)
  local sp = P.species(vm, side)
  local _, ps = pic_tables()
  local packed = ps and sp and (side == "player" and ps.back[sp] or ps.front[sp]) or (64 * 256 + 64)
  local w = floor(packed / 256)
  local h = packed % 256
  if attr == P.ATTR_HEIGHT then return h end
  if attr == P.ATTR_WIDTH then return w end
  if attr == P.ATTR_LEFT then return P.coord(vm, side, P.X_2) - floor(w / 2) end
  if attr == P.ATTR_RIGHT then return P.coord(vm, side, P.X_2) + floor(w / 2) end
  if attr == P.ATTR_TOP then return P.coord(vm, side, P.Y_PIC_OFFSET) - floor(h / 2) end
  if attr == P.ATTR_BOTTOM then return P.coord(vm, side, P.Y_PIC_OFFSET) + floor(h / 2) end
  if attr == P.ATTR_RAW_BOTTOM then return P.coord(vm, side, P.Y) + 31 - y_delta(side, sp) end
  return 0
end

function P.bySide(fn)
  return AnimCoords.sideArg(fn, 2)
end
P.coord = P.bySide(P.coord)
P.coord2 = P.coord
P.yDelta = P.bySide(P.yDelta)
P.yWithElevation = P.bySide(P.yWithElevation)
P.attr = P.bySide(P.attr)

-- pokefirered/src/battle_anim_mons.c:1908
function P.subpriorityOf(side)
  return AnimCoords.subpriority(side)
end

-- pokefirered/src/battle_anim_mons.c:1924
function P.bgPriorityOf(_side)
  return 2
end

-- pokefirered/src/battle_anim.c:1160
function P.adjustPanning(vm, pan)
  vm = vm or P.vm()
  if vm and vm.adjustPanning then return vm:adjustPanning(pan) end
  return pan
end

function P.playSe(se, pan)
  if not se then return end
  local ok, Audio = pcall(require, "src.core.game3.audio")
  if ok and Audio and Audio.playSe then pcall(Audio.playSe, se, { pan = pan }) end
end

function P.seId(name)
  local ok, SE = pcall(require, "src.core.game3.se_ids")
  return ok and SE and SE[name] or nil
end

function P.present(side)
  return P.anim().present(side)
end

local function mon_in_bg(side)
  local p = P.present(side)
  return p and p.z == 10
end

local function in_front_of(pri, sub, side)
  if pri < 2 then return true end
  if pri > 2 then return false end
  if mon_in_bg(side) then return true end
  return sub < P.subpriorityOf(side)
end

function P.zFor(pri, sub)
  pri = tonumber(pri) or 2
  sub = tonumber(sub) or 0
  if AnimCoords.isDouble() then return AnimCoords.zFor(pri, sub, P.anim()._vm) end
  local key = (3 - math.max(0, math.min(3, pri))) * 100 + (99 - math.max(0, math.min(99, sub)))
  local off = floor(key * 97 / 400)
  local fp = in_front_of(pri, sub, "player")
  local fe = in_front_of(pri, sub, "enemy")
  if fp and fe then return 201 + off end
  if fe then return 101 + off end
  return 1 + off
end

function P.updateZ(s)
  s.z = P.zFor(s._pri or 2, s.subpriority or 0)
end

-- pokefirered/src/battle_anim.c:349
local function op_subpriority(vm, op)
  local raw = tonumber(op.subpriority) or 0
  local side = (op.animBattler == "target") and P.tgtId(vm) or P.atkId(vm)
  local sub
  if raw >= 64 then sub = P.subpriorityOf(side) + (raw - 64) else sub = P.subpriorityOf(side) - raw end
  if sub < 3 then sub = 3 end
  return sub
end

local Templates
function P.templates()
  if not Templates then Templates = require("src.core.game3.battle.anim_port.g1_templates") end
  return Templates
end

function P.tagInfo(vm, tag)
  vm = vm or P.vm()
  local pack = vm and vm._pack
  return pack and pack.tags and tag and pack.tags[tag] or nil
end

function P.tagIdToName(vm, id)
  id = tonumber(id)
  if not id then return nil end
  vm = vm or P.vm()
  local pack = vm and vm._pack
  if not pack then return nil end
  if not pack._g1TagById then
    local map = {}
    local function scan(s)
      if type(s) ~= "table" then return end
      for _, op in ipairs(s) do
        if type(op) == "table" and op.op == "loadspritegfx" and op.tag and op.tag_idx then
          map[10000 + op.tag_idx] = op.tag
        end
      end
    end
    for _, k in ipairs({ "moves", "general", "special", "status", "labels" }) do
      if type(pack[k]) == "table" then for _, s in pairs(pack[k]) do scan(s) end end
    end
    pack._g1TagById = map
  end
  return pack._g1TagById[id]
end

P.Pal = {}
local Pal = P.Pal

Pal.faded = AnimCoords.idTable()
Pal.unfaded = AnimCoords.idTable()
Pal.remap = {}
Pal.backup = {}
Pal.tagsTouched = {}

local IDENT = { m = 1, r = 0, g = 0, b = 0 }

function P.rgb555(c)
  c = tonumber(c) or 0
  return band(c, 31) / 31, band(rshift(c, 5), 31) / 31, band(rshift(c, 10), 31) / 31
end

function P.RGB(r, g, b)
  return bor(r, lshift(g, 5), lshift(b, 10))
end

function Pal.get(key)
  return Pal.faded[key] or Pal.unfaded[key] or IDENT
end

function Pal.getUnfaded(key)
  return Pal.unfaded[key] or IDENT
end

local function lerp_state(u, coeff, color)
  local k = math.max(0, math.min(16, coeff)) / 16
  local r, g, b = P.rgb555(color)
  return {
    m = u.m * (1 - k),
    r = u.r * (1 - k) + r * k,
    g = u.g * (1 - k) + g * k,
    b = u.b * (1 - k) + b * k,
  }
end

-- pokefirered/src/palette.c:779
function Pal.blend(key, coeff, color)
  Pal.faded[key] = lerp_state(Pal.getUnfaded(key), coeff, color)
  Pal.dirty = true
end

function Pal.setFaded(key, st)
  Pal.faded[key] = st
  Pal.dirty = true
end

function Pal.invert(key)
  local u = Pal.get(key)
  Pal.faded[key] = { m = -u.m, r = 1 - u.r, g = 1 - u.g, b = 1 - u.b }
  Pal.dirty = true
end

function Pal.restore(key)
  Pal.faded[key] = nil
  Pal.dirty = true
end

function Pal.copyFadedToUnfaded(key)
  Pal.unfaded[key] = Pal.get(key)
  Pal.dirty = true
end

function Pal.toBackup(slot, key)
  Pal.backup[slot] = Pal.getUnfaded(key)
end

function Pal.fromBackup(slot, key)
  local st = Pal.backup[slot]
  if st == IDENT then st = nil end
  Pal.unfaded[key] = st
  Pal.dirty = true
end

function Pal.reset()
  Pal.faded = AnimCoords.idTable()
  Pal.unfaded = AnimCoords.idTable()
  Pal.remap = {}
  Pal.backup = {}
  Pal.dirty = true
end

local function to_lerp(st)
  if not st or (st.m == 1 and st.r == 0 and st.g == 0 and st.b == 0) then return 0, 0, 0, 0 end
  local k = 1 - st.m
  if k <= 0.0001 then return 0, 0, 0, 0 end
  return k, math.max(0, math.min(1, st.r / k)), math.max(0, math.min(1, st.g / k)), math.max(0, math.min(1, st.b / k))
end
Pal.toLerp = to_lerp

function Pal.flush()
  if not Pal.dirty then return end
  Pal.dirty = false
  local Anim = P.anim()
  for id = 0, 3 do
    local p = (id < 2) and Anim.present(id) or rawget(Anim._present, id)
    local st = rawget(Pal.faded, id) or rawget(Pal.unfaded, id)
    if p and (st or p._g1Blend) then
      local k, r, g, b = to_lerp(st)
      p.blendCoeff = k
      p.blendColor = { r, g, b }
      p._g1Blend = st and true or nil
      p.palAffine = (st and st.m < 0) and st or nil
      if p.palAffine then p.blendCoeff = 0 end
    end
  end
  local bst = Pal.faded.bg or Pal.unfaded.bg
  Anim._bgPalAffine = (bst and bst.m < 0) and bst or nil
  if Anim._bgPalAffine then
    Anim._bgBlend = nil
    Anim._g1BgBlend = nil
  elseif bst or Anim._g1BgBlend then
    local k, r, g, b = to_lerp(bst)
    if k > 0 then
      Anim._bgBlend = { coeff = floor(k * 16 + 0.5), color = P.RGB(floor(r * 31 + 0.5), floor(g * 31 + 0.5), floor(b * 31 + 0.5)) }
      Anim._g1BgBlend = true
    else
      Anim._bgBlend = nil
      Anim._g1BgBlend = nil
    end
  end
  Anim._tagBlend = Anim._tagBlend or {}
  local vm = Anim._vm
  for key, st in pairs(Pal.faded) do
    local tag = type(key) == "string" and key:match("^tag:(.+)$")
    if tag then
      local k, r, g, b = to_lerp(st)
      local coeff = floor(k * 16 + 0.5)
      local color = P.RGB(floor(r * 31 + 0.5), floor(g * 31 + 0.5), floor(b * 31 + 0.5))
      if coeff > 0 then
        Anim._tagBlend[tag] = { coeff = coeff, color = color }
      else
        Anim._tagBlend[tag] = nil
      end
      if vm and vm.setTagBlend then vm:setTagBlend(tag, coeff, color) end
      Pal.tagsTouched[tag] = true
    end
  end
  for tag in pairs(Pal.tagsTouched) do
    if not Pal.faded["tag:" .. tag] then
      Anim._tagBlend[tag] = nil
      if vm and vm.setTagBlend then vm:setTagBlend(tag, 0, 0) end
      Pal.tagsTouched[tag] = nil
    end
  end
end

-- pokefirered/src/battle_anim_mons.c:1315
function P.palettesMask(vm, bg, atk, tgt, atkPartner, tgtPartner, anim1, anim2)
  local keys = {}
  if bg then keys[#keys + 1] = "bg" end
  if atk then keys[#keys + 1] = P.atkId(vm) end
  if tgt then keys[#keys + 1] = P.tgtId(vm) end
  if atkPartner then
    local id = AnimCoords.partner(P.atkId(vm))
    if P.spriteVisible(id) then keys[#keys + 1] = id end
  end
  if tgtPartner then
    local id = AnimCoords.partner(P.tgtId(vm))
    if P.spriteVisible(id) then keys[#keys + 1] = id end
  end
  if anim1 then keys[#keys + 1] = "anim1" end
  if anim2 then keys[#keys + 1] = "anim2" end
  return keys
end

-- pokefirered/src/battle_anim_normal.c:302
function P.unpackSelected(vm, selector)
  selector = floor(tonumber(selector) or 0)
  return P.palettesMask(vm, band(selector, 1) ~= 0, band(selector, 2) ~= 0, band(selector, 4) ~= 0,
    band(selector, 8) ~= 0, band(selector, 16) ~= 0, band(selector, 32) ~= 0, band(selector, 64) ~= 0)
end

function P.blendPalettes(keys, coeff, color)
  for _, key in ipairs(keys) do Pal.blend(key, coeff, color) end
  Pal.flush()
end

P.Fade = { active = false }
local Fade = P.Fade

-- pokefirered/src/palette.c:151
function P.beginNormalPaletteFade(keys, delay, startY, targetY, color)
  if Fade.active then return false end
  Fade.mode = nil
  delay = P.s8(delay)
  Fade.deltaY = 2
  if delay < 0 then
    Fade.deltaY = 2 + (-delay)
    delay = 0
  end
  Fade.keys = keys
  Fade.delayCounter = delay
  Fade.delay = delay
  Fade.y = startY
  Fade.targetY = targetY
  Fade.color = color
  Fade.active = true
  Fade.finishing = false
  Fade.finishCounter = 0
  Fade.toggle = 0
  Fade.yDec = startY >= targetY
  P.ensureFadeTicker()
  P.updatePaletteFade()
  return true
end

-- pokefirered/src/palette.c:684
function P.beginHardwarePaletteFade(blendCnt, delay, y, targetY, shouldReset)
  Fade.mode = "hw"
  Fade.blendCnt = P.u8(blendCnt)
  Fade.delayCounter = P.u8(delay)
  Fade.delay = P.u8(delay)
  Fade.y = P.u8(y)
  Fade.targetY = P.u8(targetY)
  Fade.active = true
  Fade.shouldReset = band(tonumber(shouldReset) or 0, 1) ~= 0
  Fade.hwFinishing = false
  Fade.yDec = not (Fade.y < Fade.targetY)
  local vm = P.vm()
  if vm then vm.hwFade = { cnt = Fade.blendCnt, y = Fade.y } end
  P.ensureFadeTicker()
end

-- pokefirered/src/palette.c:701
local function update_hw_fade()
  if Fade.delayCounter < Fade.delay then
    Fade.delayCounter = Fade.delayCounter + 1
  else
    Fade.delayCounter = 0
    if not Fade.yDec then
      Fade.y = Fade.y + 1
      if Fade.y > Fade.targetY then
        Fade.hwFinishing = true
        Fade.y = Fade.y - 1
      end
    else
      Fade.y = Fade.y - 1
      if Fade.y < Fade.targetY then
        Fade.hwFinishing = true
        Fade.y = Fade.y + 1
      end
    end
    if Fade.hwFinishing then
      if Fade.shouldReset then
        Fade.blendCnt = 0
        Fade.y = 0
      end
      Fade.shouldReset = false
    end
  end
  local vm = P.vm()
  if vm then vm.hwFade = { cnt = Fade.blendCnt, y = Fade.y } end
  if Fade.hwFinishing then
    Fade.hwFinishing = false
    Fade.mode = nil
    Fade.blendCnt = 0
    Fade.y = 0
    Fade.active = false
  end
end

-- pokefirered/src/palette.c:393
function P.updatePaletteFade()
  if not Fade.active then return end
  if Fade.mode == "hw" then return update_hw_fade() end
  if Fade.finishing then
    if Fade.finishCounter == 4 then
      Fade.active = false
      Fade.finishing = false
      Fade.finishCounter = 0
    else
      Fade.finishCounter = Fade.finishCounter + 1
    end
    return
  end
  if Fade.toggle == 0 then
    if Fade.delayCounter < Fade.delay then
      Fade.delayCounter = Fade.delayCounter + 1
      return
    end
    Fade.delayCounter = 0
  end
  for _, key in ipairs(Fade.keys or {}) do
    local isObj = key ~= "bg" and key ~= "anim1" and key ~= "anim2"
    if isObj == (Fade.toggle == 1) then Pal.blend(key, Fade.y, Fade.color) end
  end
  Pal.flush()
  Fade.toggle = 1 - Fade.toggle
  if Fade.toggle == 0 then
    if Fade.y == Fade.targetY then
      Fade.keys = {}
      Fade.finishing = true
    else
      local v
      if not Fade.yDec then
        v = Fade.y + Fade.deltaY
        if v > Fade.targetY then v = Fade.targetY end
      else
        v = Fade.y - Fade.deltaY
        if v < Fade.targetY then v = Fade.targetY end
      end
      Fade.y = v
    end
  end
end

function P.fadeActive()
  return Fade.active == true
end

local function fade_ticker(t)
  P.updatePaletteFade()
  if not Fade.active then P.destroyTask(t) end
end

function P.ensureFadeTicker()
  local AnimTasks = package.loaded["src.core.game3.battle.anim_tasks"]
  if not AnimTasks or not AnimTasks._pool then return end
  for i = 1, AnimTasks.MAX do
    local t = AnimTasks._pool[i]
    if t.active and t._g1FadeTicker then return end
  end
  for i = 1, AnimTasks.MAX do
    local t = AnimTasks._pool[i]
    if not t.active then
      if AnimTasks._clear then AnimTasks._clear(t) end
      t.active = true
      t.name = "G1PaletteFade"
      t.priority = 0
      t.func = fade_ticker
      t._g1FadeTicker = true
      t._uncounted = true
      t._g1Skip = true
      return
    end
  end
end

function P.destroyTask(t)
  local AnimTasks = package.loaded["src.core.game3.battle.anim_tasks"]
  if AnimTasks and AnimTasks._destroy then AnimTasks._destroy(t) else t.active = false end
end

function P.setBldAlpha(vm, eva, evb)
  vm = vm or P.vm()
  if vm then vm.bldAlpha = { eva = eva, evb = evb } end
end

function P.clearBld(vm)
  vm = vm or P.vm()
  if vm then vm.bldAlpha = nil end
end

return P
