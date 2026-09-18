-- Extract FRLG gBattleMoves into {cacheRoot}/pokemon/battle_moves.lua.

local Versions = require("src.import.gba.versions")

local BattleMovesExtract = {}

BattleMovesExtract.FORMAT_VERSION = 1
BattleMovesExtract.CACHE_SUB = "pokemon"

local function default_cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then
    return Extract.CACHE_ROOT
  end
  return "data/generated/gba"
end

--- Decode one BattleMove (9 meaningful bytes + 3 pad).
function BattleMovesExtract.decodeRow(bytes, off)
  off = off or 1
  local effect = bytes[off] or 0
  local power = bytes[off + 1] or 0
  local typeId = bytes[off + 2] or 0
  local accuracy = bytes[off + 3] or 0
  local pp = bytes[off + 4] or 0
  local secondaryChance = bytes[off + 5] or 0
  local target = bytes[off + 6] or 0
  local priority = bytes[off + 7] or 0
  if priority >= 128 then priority = priority - 256 end -- s8
  local flags = bytes[off + 8] or 0
  return {
    effect = effect,
    power = power,
    type = typeId,
    accuracy = accuracy,
    pp = pp,
    secondaryChance = secondaryChance,
    target = target,
    priority = priority,
    flags = flags,
  }
end

function BattleMovesExtract.extract(rom, opts)
  opts = opts or {}
  local base = Versions.BATTLE_MOVES or 0x250C04
  local stride = Versions.BATTLE_MOVE_SIZE or 12
  local count = Versions.MOVES_COUNT or 355 -- 0 .. 354
  local rows = {}
  for id = 0, count - 1 do
    local off = base + id * stride
    local buf = {}
    for i = 0, 8 do
      buf[i + 1] = rom:get(off + i)
    end
    rows[id] = BattleMovesExtract.decodeRow(buf, 1)
  end
  return {
    version = BattleMovesExtract.FORMAT_VERSION,
    base = base,
    stride = stride,
    count = count,
    moves = rows,
  }
end

function BattleMovesExtract.packToLua(pack)
  local lines = {
    "-- Auto-generated FRLG gBattleMoves (internal move id).",
    "-- effect/power/type/accuracy/pp/secondaryChance/target/priority/flags",
    "return {",
    string.format("  version = %d,", pack.version or 1),
    string.format("  count = %d,", pack.count or 0),
    "  moves = {",
  }
  for id = 0, (pack.count or 0) - 1 do
    local m = pack.moves[id]
    if m then
      lines[#lines + 1] = string.format(
        "    [%d] = { effect=%d, power=%d, type=%d, accuracy=%d, pp=%d, secondaryChance=%d, target=%d, priority=%d, flags=%d },",
        id, m.effect, m.power, m.type, m.accuracy, m.pp,
        m.secondaryChance, m.target, m.priority, m.flags)
    end
  end
  lines[#lines + 1] = "  },"
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

--- Write via cache object (preferred) or filesystem outDir.
function BattleMovesExtract.writeCache(pack, cacheOrDir, opts)
  opts = opts or {}
  local body = BattleMovesExtract.packToLua(pack)
  if type(cacheOrDir) == "table" and cacheOrDir.write then
    local root = (opts.cacheRoot or default_cache_root()) .. "/" .. BattleMovesExtract.CACHE_SUB
    cacheOrDir:write(root .. "/battle_moves.lua", body)
    return root .. "/battle_moves.lua"
  end
  local outDir = cacheOrDir or (default_cache_root() .. "/" .. BattleMovesExtract.CACHE_SUB)
  os.execute('mkdir -p "' .. outDir .. '"')
  local f = assert(io.open(outDir .. "/battle_moves.lua", "wb"))
  f:write(body)
  f:close()
  return outDir .. "/battle_moves.lua"
end

function BattleMovesExtract.run(rom, cache, opts)
  opts = opts or {}
  local pack = BattleMovesExtract.extract(rom, opts)
  local path = BattleMovesExtract.writeCache(pack, cache, opts)
  return { pack = pack, path = path }
end

function BattleMovesExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or default_cache_root()) .. "/pokemon/battle_moves.lua"
  if cache and cache.exists and cache:exists(root) then return true end
  if cache and cache.read and cache:read(root) then return true end
  return false
end

return BattleMovesExtract
