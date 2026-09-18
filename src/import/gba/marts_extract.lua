-- Bake FRLG pokemart item lists (u16[] → ITEM_NONE) into CacheFS.
-- Keys: raw GBA ptr number, decimal string, and Opcodes.key (g3:%08x).

local Opcodes = require("src.core.game3.scripting.opcodes")
local Versions = require("src.import.gba.versions")

local MartsExtract = {}

MartsExtract.CACHE_SUB = "scripts"
MartsExtract.FORMAT_VERSION = 1
MartsExtract.MAX_ITEMS = 64

local function default_cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then
    return Extract.CACHE_ROOT
  end
  return "data/generated/gba"
end

local function is_rom_ptr(p)
  p = tonumber(p)
  return p and p >= 0x08000000 and p < 0x0A000000
end

--- Read one mart list from ROM (halfwords until ITEM_NONE / 0).
function MartsExtract.readList(rom, gbaPtr)
  local off = rom:ptrOffset(tonumber(gbaPtr) or 0)
  if not off then return nil end
  local items = {}
  for _ = 1, MartsExtract.MAX_ITEMS do
    local id = rom:u16(off)
    off = off + 2
    if id == 0 then break end
    items[#items + 1] = id
  end
  return items
end

--- Collect unique pokemart pointers from a scripts table (extract IR).
function MartsExtract.collectPtrs(scripts)
  local seen, list = {}, {}
  for _, rows in pairs(scripts or {}) do
    if type(rows) == "table" then
      for _, row in ipairs(rows) do
        if row and (row.op == "pokemart"
            or row.op == "pokemartdecoration"
            or row.op == "pokemartdecoration2") then
          local ptr = tonumber(row[1] or row.ptr or row.items)
          if not ptr and type(row[1]) == "string" then
            local hex = row[1]:match("^g3:(%x+)$")
            if hex then ptr = tonumber(hex, 16) end
          end
          if is_rom_ptr(ptr) and not seen[ptr] then
            seen[ptr] = true
            list[#list + 1] = ptr
          end
        end
      end
    end
  end
  table.sort(list)
  return list
end

--- Build marts map from ROM + script IR.
function MartsExtract.build(rom, scripts)
  local marts = {}
  local ptrs = MartsExtract.collectPtrs(scripts)
  for _, ptr in ipairs(ptrs) do
    local items = MartsExtract.readList(rom, ptr)
    if items and #items > 0 then
      local key = Opcodes.key(ptr)
      local entry = {
        ptr = ptr,
        key = key,
        items = items,
      }
      marts[ptr] = entry
      marts[tostring(ptr)] = entry
      marts[key] = entry
    end
  end
  return marts, #ptrs
end

local function serialize_lua(val, indent)
  indent = indent or 0
  local sp = string.rep("  ", indent)
  local sp1 = string.rep("  ", indent + 1)
  local t = type(val)
  if t == "nil" then return "nil" end
  if t == "boolean" then return val and "true" or "false" end
  if t == "number" then return tostring(val) end
  if t == "string" then return string.format("%q", val) end
  if t ~= "table" then return "nil" end
  local keys = {}
  for k in pairs(val) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    local ta, tb = type(a), type(b)
    if ta == tb then
      if ta == "number" then return a < b end
      return tostring(a) < tostring(b)
    end
    return ta < tb
  end)
  local parts = { "{\n" }
  for _, k in ipairs(keys) do
    local keyRepr
    if type(k) == "number" then
      keyRepr = string.format("[%d]", k)
    elseif type(k) == "string" and k:match("^[%a_][%w_]*$") then
      keyRepr = k
    else
      keyRepr = string.format("[%q]", tostring(k))
    end
    parts[#parts + 1] = sp1 .. keyRepr .. " = " .. serialize_lua(val[k], indent + 1) .. ",\n"
  end
  parts[#parts + 1] = sp .. "}"
  return table.concat(parts)
end

--- Write data/generated/gba/scripts/marts.lua
function MartsExtract.write(cache, root, marts, meta)
  root = root or default_cache_root()
  local rel = root .. "/" .. MartsExtract.CACHE_SUB .. "/marts.lua"
  local pack = {
    format_version = MartsExtract.FORMAT_VERSION,
    cache_version = Versions.CACHE_VERSION,
    count = meta and meta.count or 0,
    marts = marts or {},
  }
  cache:write(rel, "return " .. serialize_lua(pack) .. "\n")
  return rel
end

--- Full extract: scripts IR + ROM → marts.lua
function MartsExtract.run(rom, cache, opts)
  opts = opts or {}
  local root = opts.cacheRoot or default_cache_root()
  local scripts = opts.scripts
  if not scripts then
    local src = cache:read(root .. "/" .. MartsExtract.CACHE_SUB .. "/scripts.lua")
    if src then
      local chunk = load(src, "@scripts.lua", "t", {})
      scripts = chunk and chunk()
    end
  end
  if type(scripts) ~= "table" then
    return nil, "scripts.lua missing — run script extract first"
  end
  local marts, nPtr = MartsExtract.build(rom, scripts)
  local nLists = 0
  local seen = {}
  for k, e in pairs(marts) do
    if type(k) == "number" and e and e.items and not seen[e.ptr] then
      seen[e.ptr] = true
      nLists = nLists + 1
    end
  end
  local rel = MartsExtract.write(cache, root, marts, { count = nLists })
  return {
    path = rel,
    ptrCount = nPtr,
    listCount = nLists,
    marts = marts,
  }
end

--- Remap pokemart word operands in-place during script BFS (ptr → g3:key).
-- Also fills `outMarts` keyed like MartsExtract.build.
function MartsExtract.remapRow(rom, row, outMarts)
  if not row then return end
  if row.op ~= "pokemart" and row.op ~= "pokemartdecoration"
      and row.op ~= "pokemartdecoration2" then
    return
  end
  local ptr = tonumber(row[1] or row.ptr)
  if not is_rom_ptr(ptr) then return end
  local key = Opcodes.key(ptr)
  if outMarts and not outMarts[ptr] then
    local items = MartsExtract.readList(rom, ptr)
    if items and #items > 0 then
      local entry = { ptr = ptr, key = key, items = items }
      outMarts[ptr] = entry
      outMarts[tostring(ptr)] = entry
      outMarts[key] = entry
    end
  end
  row[1] = key
  row.ptr = key
  row.items = key
end

return MartsExtract
