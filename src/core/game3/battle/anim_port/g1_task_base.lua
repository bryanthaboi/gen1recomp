local P = require("src.core.game3.battle.anim_port.g1_pret")

local K = {}

local function to_num(v)
  if type(v) == "string" then
    local l = v:lower()
    if l:find("target") then return 1 end
    if l:find("attacker") then return 0 end
    return tonumber(v) or 0
  end
  return tonumber(v) or 0
end

-- pokefirered/src/task.c:30
function K.wrap(initFn)
  return function(t, vm)
    if t._g1 then
      local fn = t._fn or initFn
      return fn(t, t._vm or vm)
    end
    t._g1 = true
    P.hookVmReset()
    t._vm = vm
    local A = {}
    for i = 0, 7 do A[i] = P.s16(to_num(t.data[i])) end
    t._A = A
    for i = 0, 15 do t.data[i] = 0 end
    t._fn = initFn
    return initFn(t, vm)
  end
end

function K.destroy(t)
  P.destroyTask(t)
end

-- pokefirered/src/battle_anim_mons.c:333
function K.battlerSide(vm, animBattler)
  animBattler = tonumber(animBattler) or 0
  if animBattler == 0 then return P.atk(vm) end
  if animBattler == 1 then return P.tgt(vm) end
  if (animBattler == 2 or animBattler == 3) and vm and vm.battlerId then return vm:battlerId(animBattler) end
  return nil
end

function K.mon(side)
  if not side then return nil end
  return P.present(side)
end

function K.monX(vm, side)
  return P.coord(vm, side, P.X_2)
end

function K.monY(vm, side)
  return P.coord(vm, side, P.Y_PIC_OFFSET_DEFAULT)
end

function K.ctx(vm, key, fallback)
  local c = vm and vm.ctx
  if c and c[key] ~= nil then return c[key] end
  if vm and vm[key] ~= nil then return vm[key] end
  return fallback
end

function K.sideFromCtx(v)
  if v == "player" or v == "enemy" then return v end
  local n = tonumber(v)
  if n == nil or n < 0 or n > 3 then return nil end
  return n
end

function K.battleState()
  local Battle = package.loaded["src.core.game3.battle"]
  return Battle and Battle._st or nil
end

return K
