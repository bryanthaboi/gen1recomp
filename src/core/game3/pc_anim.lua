-- pokefirered/src/field_specials.c:212
local PcAnim = {}

PcAnim.task = nil

PcAnim.METATILE_OFF = { [0] = 0x062, [1] = 0x28F, [2] = 0x28F } -- pokefirered/include/constants/metatile_labels.h:5
PcAnim.METATILE_ON = { [0] = 0x063, [1] = 0x28A, [2] = 0x28A } -- pokefirered/include/constants/metatile_labels.h:74

local function var8004(ctx)
  local Flags = require("src.core.game3.scripting.flags")
  return tonumber(Flags.getVar(nil, ctx, 0x8004)) or 0
end

-- pokefirered/src/field_specials.c:249
local function target()
  local P = package.loaded["src.core.game3.player"] or require("src.core.game3.player")
  local dx, dy = 0, 0
  if P.facing == "up" then
    dx, dy = 0, -1
  elseif P.facing == "left" then
    dx, dy = -1, -1
  elseif P.facing == "right" then
    dx, dy = 1, -1
  end
  return (tonumber(P.cellX) or 0) + dx, (tonumber(P.cellY) or 0) + dy
end

function PcAnim.setter(fn)
  PcAnim._set = fn
end

function PcAnim.drawable(mid)
  local Map = package.loaded["src.core.game3.map"]
  local def = Map and Map.currentDef and Map.currentDef()
  local pair = def and (def.pair or (def.midLayout and def.midLayout.pair))
  local okN, NativeTileset = pcall(require, "src.core.game3.tileset_native")
  if not (pair and okN and NativeTileset and NativeTileset.ready and NativeTileset.ready(pair)) then
    return true
  end
  local ts = NativeTileset.get(pair)
  return not (ts and ts.midToSlot) or ts.midToSlot[mid] ~= nil
end

local function set_mid(mid)
  local x, y = target()
  if PcAnim._set then
    PcAnim._set(x, y, mid, true)
    return
  end
  if not PcAnim.drawable(mid) then return end
  local Field = require("src.core.game3.field")
  Field.setMetatile(x, y, mid, true)
end

function PcAnim.turnOn(ctx)
  if PcAnim.task then return end
  PcAnim.task = { state = 0, timer = 0, ctx = ctx }
end

-- pokefirered/src/field_specials.c:225
function PcAnim.update()
  local t = PcAnim.task
  if not t then return end
  if t.timer == 6 then
    local var = var8004(t.ctx)
    local flickerOff = (t.state % 2) == 1
    set_mid((flickerOff and PcAnim.METATILE_OFF[var] or PcAnim.METATILE_ON[var]) or 0)
    t.timer = 0
    t.state = t.state + 1
    if t.state == 5 then
      PcAnim.task = nil
    end
  end
  t.timer = t.timer + 1
end

-- pokefirered/src/field_specials.c:286
function PcAnim.turnOff(ctx)
  set_mid(PcAnim.METATILE_OFF[var8004(ctx)] or 0)
end

function PcAnim.reset()
  PcAnim.task = nil
end

return PcAnim
