local bit = require("bit")

local AnimCoords = {}

local function xy(x, y) return { x = x, y = y, x, y } end

-- pokefirered/src/battle_anim_mons.c:31
AnimCoords.SINGLES = { [0] = xy(72, 80), xy(176, 40), xy(48, 40), xy(112, 80) }
AnimCoords.DOUBLES = { [0] = xy(32, 80), xy(200, 40), xy(90, 88), xy(152, 32) }

-- pokefirered/src/battle_anim_mons.c:1908
AnimCoords.SUBPRIORITY = { [0] = 30, 40, 20, 50 }

-- pokefirered/src/battle_anim_mons.c:1934
AnimCoords.BG_PRIORITY_RANK = { [0] = 2, 1, 1, 2 }

AnimCoords.DRAW_ORDER_SINGLES = { 1, 0 }
AnimCoords.DRAW_ORDER_DOUBLES = { 3, 1, 0, 2 }

AnimCoords._double = nil
AnimCoords._bind = nil

local function battle_state()
  local Battle = package.loaded["src.core.game3.battle"]
  return Battle and Battle._st
end
AnimCoords.battleState = battle_state

function AnimCoords.setDouble(v)
  if v == nil then AnimCoords._double = nil else AnimCoords._double = v and true or false end
end

function AnimCoords.isDouble(st)
  if AnimCoords._double ~= nil then return AnimCoords._double end
  st = st or battle_state()
  return type(st) == "table" and st.double == true
end

function AnimCoords.sideOf(id)
  id = tonumber(id) or 0
  return (id % 2 == 0) and "player" or "enemy"
end

function AnimCoords.partner(id)
  return bit.bxor(tonumber(id) or 0, 2)
end

function AnimCoords.fixedId(key)
  if type(key) == "number" then return key end
  if key == "enemy" then return 1 end
  if key == "player" then return 0 end
  return nil
end

function AnimCoords.idOf(key)
  local t = type(key)
  if t == "number" then
    if key >= 0 and key <= 3 then return math.floor(key) end
    return nil
  end
  if key == "player" then
    local b = AnimCoords._bind
    return (b and b.player) or 0
  end
  if key == "enemy" then
    local b = AnimCoords._bind
    return (b and b.enemy) or 1
  end
  if t == "table" then
    if type(key.id) == "number" then return key.id end
    if key.side then return AnimCoords.idOf(key.side) end
  end
  return nil
end

function AnimCoords.bind(atkId, tgtId)
  if atkId == nil then
    AnimCoords._bind = nil
    return
  end
  tgtId = tgtId or atkId
  local b = {}
  b[AnimCoords.sideOf(tgtId)] = tgtId
  b[AnimCoords.sideOf(atkId)] = atkId
  if b.player == nil then b.player = 0 end
  if b.enemy == nil then b.enemy = 1 end
  AnimCoords._bind = b
end

function AnimCoords.withBattler(id, fn, ...)
  local prev = AnimCoords._bind
  local b = { player = (prev and prev.player) or 0, enemy = (prev and prev.enemy) or 1 }
  b[AnimCoords.sideOf(id)] = id
  AnimCoords._bind = b
  local r = { pcall(fn, AnimCoords.sideOf(id), ...) }
  AnimCoords._bind = prev
  if not r[1] then error(r[2], 0) end
  return unpack(r, 2)
end

function AnimCoords.sideArg(fn, idx)
  return function(...)
    local args = { n = select("#", ...), ... }
    local v = args[idx]
    if type(v) ~= "number" or v < 0 or v > 3 then return fn(...) end
    return AnimCoords.withBattler(v, function(side)
      args[idx] = side
      return fn(unpack(args, 1, args.n))
    end)
  end
end

function AnimCoords.coords(st, key)
  local id = AnimCoords.idOf(key)
  if id == nil then return nil end
  local t = AnimCoords.isDouble(st) and AnimCoords.DOUBLES or AnimCoords.SINGLES
  return t[id]
end

function AnimCoords.subpriority(key)
  local id = AnimCoords.idOf(key)
  return AnimCoords.SUBPRIORITY[id or 1]
end

function AnimCoords.bgPriorityRank(key)
  local id = AnimCoords.idOf(key)
  return AnimCoords.BG_PRIORITY_RANK[id or 1]
end

function AnimCoords.battler(st, id)
  st = st or battle_state()
  if type(st) ~= "table" or id == nil then return nil end
  local bs = rawget(st, "battlers") or st.battlers
  local b = bs and bs[id]
  if b == nil and id == 0 then b = st.player end
  if b == nil and id == 1 then b = st.enemy end
  return b
end

function AnimCoords.ids(st)
  if AnimCoords.isDouble(st) then return { 0, 1, 2, 3 } end
  return { 0, 1 }
end

-- pokefirered/src/battle_anim_mons.c:841
function AnimCoords.spritePresent(st, id)
  if id == nil then return false end
  st = st or battle_state()
  if id >= 2 and not AnimCoords.isDouble(st) then return false end
  if type(st) ~= "table" then return id < 2 end
  if st.absent and st.absent[id] then return false end
  local b = AnimCoords.battler(st, id)
  if not b then return id < 2 end
  local mon = b.mon
  if mon and (tonumber(mon.hp) or 0) <= 0 then return false end
  return true
end

function AnimCoords.monDrawOrder(st)
  if AnimCoords.isDouble(st) then return AnimCoords.DRAW_ORDER_DOUBLES end
  return AnimCoords.DRAW_ORDER_SINGLES
end

function AnimCoords.monBehindZ(key, st)
  local id = AnimCoords.idOf(key) or 1
  local order = AnimCoords.monDrawOrder(st)
  for k, v in ipairs(order) do
    if v == id then return (k - 1) * 100 + 95 end
  end
  return 95
end

function AnimCoords.particleBand(k, st)
  local n = #AnimCoords.monDrawOrder(st)
  if k <= 0 then return 0, 99 end
  if k >= n then return k * 100 + 1, 999 end
  return k * 100 + 1, k * 100 + 99
end

-- pokefirered/src/battle_anim.c:630
function AnimCoords.layerZ(sub, monbg, bgPrio, st)
  sub = tonumber(sub) or 0
  local order = AnimCoords.monDrawOrder(st)
  local layer = 0
  for k = #order, 1, -1 do
    local id = order[k]
    local front
    if monbg and rawget(monbg, id) then
      front = ((bgPrio and bgPrio[AnimCoords.BG_PRIORITY_RANK[id]]) or 2) >= 2
    else
      front = sub < AnimCoords.SUBPRIORITY[id]
    end
    if front then
      layer = k
      break
    end
  end
  local rank = math.max(0, math.min(98, 98 - sub))
  if layer == 0 then return rank end
  return layer * 100 + 1 + rank
end

function AnimCoords.zFor(pri, sub, vm, st)
  pri = tonumber(pri) or 2
  sub = tonumber(sub) or 0
  if pri <= 1 then return 900 + (255 - sub) % 99 end
  if pri >= 3 then return math.max(1, math.min(98, 98 - sub)) end
  return AnimCoords.layerZ(sub, vm and vm._monbg, vm and vm._bgPrio, st)
end

local SIDE_KEY_MT = {
  __index = function(t, k)
    if k == "player" or k == "enemy" then return rawget(t, AnimCoords.idOf(k)) end
    return nil
  end,
  __newindex = function(t, k, v)
    if k == "player" or k == "enemy" then k = AnimCoords.idOf(k) end
    rawset(t, k, v)
  end,
}

function AnimCoords.idTable(init)
  local t = setmetatable({}, SIDE_KEY_MT)
  if init then
    for k, v in pairs(init) do t[k] = v end
  end
  return t
end

return AnimCoords
