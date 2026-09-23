-- Move table: ROM gBattleMoves pack.

local Types = require("src.core.game3.battle.types")
local EffectIds = require("src.core.game3.battle.effect_ids")
local Extract = require("src.import.gba.extract_island1")

local Moves = {}

Moves._rom = nil -- { [id] = row }
Moves._romLoaded = false

Moves.BY_NUM = {}
Moves._numByName = nil

local function const_name(romName)
  return (tostring(romName):upper():gsub("%s+", "_"):gsub("-", "_"))
end

local function build_names()
  local Pokemon = require("src.core.game3.pokemon")
  local byNum, byName = {}, {}
  for id = 1, require("src.import.gba.versions").MOVES_COUNT - 1 do
    local n = Pokemon.romMoveName(id)
    if n and n ~= "" then
      local key = const_name(n)
      byNum[id] = key
      if not byName[key] then byName[key] = id end
    end
  end
  for k in pairs(Moves.BY_NUM) do Moves.BY_NUM[k] = nil end
  for id, key in pairs(byNum) do Moves.BY_NUM[id] = key end
  Moves._numByName = next(byName) and byName or nil
  return byName
end

function Moves.loadRomPack(cache)
  Moves._romLoaded = true
  local root = (Extract.CACHE_ROOT or "data/generated/gba") .. "/pokemon/battle_moves.lua"
  cache = cache or require("src.core.game3.dataset").cache()
  local src = assert(cache:read(root), "pokemon/battle_moves.lua is not in the cache")
  local pack = assert(load(src, "@" .. root, "t", {}))()
  Moves._rom = assert(pack and pack.moves, "pokemon/battle_moves.lua has no moves")
  Moves._numByName = nil
  build_names()
  Moves._runReloadHooks()
  return true
end

Moves._reloadHooks = {}

function Moves.onReload(fn, key)
  if type(fn) ~= "function" then return function() end end
  local hooks = Moves._reloadHooks
  for i = #hooks, 1, -1 do
    local h = hooks[i]
    if h.fn == fn or (key ~= nil and h.key == key) then
      table.remove(hooks, i)
    end
  end
  local entry = { fn = fn, key = key }
  hooks[#hooks + 1] = entry
  return function()
    for i = #hooks, 1, -1 do
      if hooks[i] == entry then table.remove(hooks, i) end
    end
  end
end

function Moves._runReloadHooks()
  local snapshot = {}
  for i, h in ipairs(Moves._reloadHooks) do snapshot[i] = h end
  for _, h in ipairs(snapshot) do
    local ok, err = pcall(h.fn, Moves)
    if not ok then print("[game3/moves] onReload callback failed: " .. tostring(err)) end
  end
end

function Moves.romReady()
  if not Moves._romLoaded then Moves.loadRomPack(nil) end
  return Moves._rom ~= nil
end

local function unwrap_move(moveId)
  if type(moveId) == "table" then
    return moveId.id or moveId.move or moveId.moveId or moveId.num or moveId.name or moveId[1]
  end
  return moveId
end

function Moves.normalizeId(moveId)
  moveId = unwrap_move(moveId)
  if moveId == nil or moveId == 0 or moveId == "" then return nil end
  if type(moveId) == "number" then
    return Moves.constName(moveId) or tostring(moveId)
  end
  if type(moveId) ~= "string" then return nil end
  local s = moveId:upper():gsub("%s+", "_"):gsub("-", "_")
  if s == "THUNDER_SHOCK" then return "THUNDERSHOCK" end
  if s == "WILLOWISP" then return "WILL_O_WISP" end
  if s == "DOUBLE_SLAP" then return "DOUBLESLAP" end
  return s
end

function Moves.constName(numId)
  if not Moves._numByName then build_names() end
  return Moves.BY_NUM[tonumber(numId) or -1]
end

function Moves.numForName(name)
  name = unwrap_move(name)
  if not name then return nil end
  if type(name) == "number" then return name end
  local byName = Moves._numByName or build_names()
  return byName[const_name(name)] or byName[name]
end

local function from_rom(numId)
  Moves.romReady()
  if not Moves._rom then return nil end
  local row = Moves._rom[numId]
  if not row then return nil end
  local cat = Types.isPhysical(row.type) and "physical" or "special"
  if (row.power or 0) == 0 then cat = "status" end
  return {
    id = Moves.constName(numId) or error("no ROM name for move " .. tostring(numId)),
    numId = numId,
    power = row.power,
    type = row.type,
    category = cat,
    accuracy = row.accuracy,
    pp = row.pp,
    effect = row.effect,
    secondaryChance = row.secondaryChance,
    target = row.target,
    priority = row.priority,
    flags = row.flags,
    effectId = EffectIds.STATUS_SETUP[row.effect],
  }
end

-- src/data/battle_moves.h:1
function Moves.get(moveId)
  moveId = unwrap_move(moveId)
  local num = tonumber(moveId)
  if not num and type(moveId) == "string" then
    num = Moves.numForName(Moves.normalizeId(moveId))
  end
  local m = num and from_rom(num)
  if not m then error("no ROM move row for move " .. tostring(moveId), 2) end
  return m
end

function Moves.displayName(moveId)
  moveId = unwrap_move(moveId)
  if not moveId or moveId == 0 or moveId == "" or moveId == "-------" then
    return "-------"
  end

  local num = tonumber(moveId)
  if not num and type(moveId) == "string" then
    num = Moves.numForName(Moves.normalizeId(moveId))
  end
  return require("src.core.game3.pokemon").moveName(num or moveId)
end

local PRIORITY_FALLBACK = {
  [98] = 1,   -- QUICK_ATTACK
  [182] = 2,  -- PROTECT
  [197] = 2,  -- DETECT
  [183] = 1,  -- MACH_PUNCH
  [245] = 2,  -- EXTREMESPEED
  [252] = 1,  -- FAKE_OUT
  [283] = 3,  -- HELPING_HAND
  [264] = 4,  -- MAGIC_COAT
  [268] = 4,  -- SNATCH
  [279] = -3, -- REVENGE
  [263] = -3, -- FOCUS_PUNCH
  [233] = -5, -- VITAL_THROW
  [46] = -6,  -- ROAR
  [18] = -6,  -- WHIRLWIND
  [309] = -6, -- COUNTER
  [310] = -6, -- MIRROR_COAT
}

function Moves.priority(moveId)
  if not moveId or moveId == 0 or moveId == "" then return 0 end
  local ok, m = pcall(Moves.get, moveId)
  if ok and m and m.priority ~= nil then return tonumber(m.priority) or 0 end
  local num = tonumber(moveId)
  if not num and type(moveId) == "string" then
    num = Moves.numForName(Moves.normalizeId(moveId))
  end
  return (num and PRIORITY_FALLBACK[num]) or 0
end

return Moves
