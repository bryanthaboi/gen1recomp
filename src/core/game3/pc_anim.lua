-- pokefirered/src/field_specials.c:212
local PcAnim = {}

PcAnim.task = nil

-- pokefirered/src/field_specials.c:265
local PC_LABELS = {
  [0] = { off = "METATILE_Building_PCOff", on = "METATILE_Building_PCOn" },
  [1] = { off = "METATILE_GenericBuilding1_PlayersPCOff", on = "METATILE_GenericBuilding1_PlayersPCOn" },
  [2] = { off = "METATILE_GenericBuilding1_PlayersPCOff", on = "METATILE_GenericBuilding1_PlayersPCOn" },
}
PcAnim.PC_LABELS = PC_LABELS

function PcAnim.metatile(var, on)
  local row = PC_LABELS[var]
  if not row then return nil end
  return require("src.core.game3.constants").active():require("metatile_labels", on and row.on or row.off)
end

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

local function set_mid(mid)
  local x, y = target()
  if PcAnim._set then
    PcAnim._set(x, y, mid, true)
    return
  end
  local Field = require("src.core.game3.field")
  Field.setMetatile(x, y, mid, true)
end

function PcAnim.turnOn(ctx)
  PcAnim.task = { state = 0, timer = 0, ctx = ctx }
end

-- pokefirered/src/field_specials.c:225
function PcAnim.update()
  local t = PcAnim.task
  if not t then return end
  if t.timer >= 6 then
    local var = var8004(t.ctx)
    local flickerOff = (t.state % 2) == 1
    local mid = PcAnim.metatile(var, not flickerOff)
    if not mid then
      PcAnim.task = nil
      return
    end
    set_mid(mid)
    t.timer = 0
    t.state = t.state + 1
    if t.state >= 5 then
      PcAnim.task = nil
      return
    end
  end
  t.timer = t.timer + 1
end

-- pokefirered/src/field_specials.c:286
function PcAnim.turnOff(ctx)
  local t = PcAnim.task
  local effectiveCtx = ctx or (t and t.ctx)
  PcAnim.task = nil
  set_mid(PcAnim.metatile(var8004(effectiveCtx), false) or 0)
end

function PcAnim.reset()
  PcAnim.task = nil
end

return PcAnim
