local P = require("src.core.game3.battle.anim_port.g4_pret")
local T = require("src.core.game3.battle.anim_port.g4_templates")

return function(host)
  local K = { P = P, T = T, host = host }
  local nextId = 0

  function K.destroy(t)
    host._destroy(t)
  end

  function K.cb()
    local AnimCallbacks = package.loaded["src.core.game3.battle.anim_callbacks"]
    return AnimCallbacks and AnimCallbacks._g4
  end

  -- pokefirered/src/battle_anim.c:1214
  function K.keepPan(pan)
    if pan > P.SOUND_PAN_TARGET then return P.SOUND_PAN_TARGET end
    if pan < P.SOUND_PAN_ATTACKER then return P.SOUND_PAN_ATTACKER end
    return pan
  end

  -- pokefirered/src/battle_anim.c:1226
  function K.panInc(src, tgt, inc)
    inc = math.abs(inc)
    if src < tgt then return inc end
    if src > tgt then return -inc end
    return 0
  end

  local function fresh(t, vm)
    nextId = nextId + 1
    t._g4id = nextId
    t._g4init = true
    for i = 0, 15 do t.data[i] = 0 end
  end

  function K.spawnAux(vm, fn, priority)
    local t = host.spawn("_G4Aux", priority or 2, {}, vm)
    if not t then return nil end
    fresh(t, vm)
    t._g4kind = "aux"
    t.func = fn
    return t
  end
  host.REGISTRY._G4Aux = host._stub

  -- pokefirered/src/battle_anim_mons.c:1999
  function K.monSize(vm, side)
    local ok, sizes = pcall(require, "src.core.game3.battle.anim_port.g1_pic_sizes")
    local sp = tonumber(P.species(vm, side))
    if ok and type(sizes) == "table" and sp then
      local tbl = (side == "player") and (sizes.back or sizes) or (sizes.front or sizes)
      local e = tbl[sp]
      if type(e) == "table" then return e.w or e[1] or 64, e.h or e[2] or 64 end
      if type(e) == "number" and e > 0 then return P.rshift(e, 8), P.band(e, 0xFF) end
    end
    return 64, 64
  end

  local TABLE = {}
  for k, v in pairs(require("src.core.game3.battle.anim_port.g4_tasks_a")(K)) do TABLE[k] = v end
  for k, v in pairs(require("src.core.game3.battle.anim_port.g4_tasks_b")(K)) do TABLE[k] = v end

  local OUT = {}
  for name, fn in pairs(TABLE) do
    OUT[name] = function(t, vm)
      if not t._g4init then fresh(t, vm) end
      return fn(t, vm)
    end
  end
  return OUT
end
