-- Runtime lookup for extracted pokemart item lists (CacheFS scripts/marts.lua).

local Marts = {}

Marts._byKey = nil

local function default_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then
    return Extract.CACHE_ROOT
  end
  return "data/generated/gba"
end

local function love_cache()
  local ok, Dataset = pcall(require, "src.core.game3.dataset")
  if ok and Dataset and Dataset.cache then
    return Dataset.cache()
  end
  return nil
end

function Marts.install(pack)
  Marts._byKey = {}
  if type(pack) ~= "table" then return 0 end
  local src = pack.marts or pack
  local n = 0
  local seen = {}
  for k, e in pairs(src) do
    if type(e) == "table" and type(e.items) == "table" then
      Marts._byKey[k] = e
      if e.ptr then Marts._byKey[e.ptr] = e end
      if e.key then Marts._byKey[e.key] = e end
      if e.ptr and not seen[e.ptr] then
        seen[e.ptr] = true
        n = n + 1
      end
    end
  end
  return n
end

function Marts.load(cache, root)
  cache = cache or love_cache()
  root = root or default_root()
  if not cache or not cache.read then
    Marts._byKey = {}
    return 0
  end
  local rel = root .. "/scripts/marts.lua"
  local src = cache:read(rel)
  if not src then
    Marts._byKey = {}
    return 0
  end
  local chunk = load(src, "@" .. rel, "t", {})
  local pack = chunk and chunk()
  return Marts.install(pack)
end

function Marts.ensure(cache, root)
  if Marts._byKey then return true end
  Marts.load(cache, root)
  return Marts._byKey ~= nil
end

--- Resolve mart list for a pokemart operand (number ptr, decimal string, or g3:key).
function Marts.itemsFor(key)
  Marts.ensure()
  if not Marts._byKey then return nil end
  local e = Marts._byKey[key]
  if not e and type(key) == "string" then
    local n = tonumber(key)
    if n then e = Marts._byKey[n] end
    if not e then
      local hex = key:match("^g3:(%x+)$")
      if hex then e = Marts._byKey[tonumber(hex, 16)] or Marts._byKey[key] end
    end
  elseif type(key) == "number" then
    e = Marts._byKey[key] or Marts._byKey[tostring(key)]
    if not e then
      local Opcodes = require("src.core.game3.scripting.opcodes")
      e = Marts._byKey[Opcodes.key(key)]
    end
  end
  if e and e.items then return e.items, e end
  return nil
end

return Marts
