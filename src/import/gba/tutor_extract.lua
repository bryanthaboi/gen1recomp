-- src/data/pokemon/tutor_learnsets.h:1 sTutorMoves, :22 sTutorLearnsets

local Versions = require("src.import.gba.versions")

local TutorExtract = {}

TutorExtract.CACHE_SUB = "pokemon"
TutorExtract.CACHE_FILE = "tutor.lua"
TutorExtract.FORMAT_VERSION = 1

local function default_cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then
    return Extract.CACHE_ROOT
  end
  return "data/generated/gba"
end

function TutorExtract.read(rom)
  local moves, learnsets = {}, {}
  for i = 0, Versions.TUTOR_MOVE_COUNT - 1 do
    moves[i] = rom:u16(Versions.TUTOR_MOVES + i * 2)
  end
  for species = 0, Versions.NUM_SPECIES - 1 do
    learnsets[species] = rom:u16(Versions.TUTOR_LEARNSETS + species * 2)
  end
  return moves, learnsets
end

function TutorExtract.run(rom, cache, opts)
  opts = opts or {}
  local cacheRoot = opts.cacheRoot or default_cache_root()
  local rel = cacheRoot .. "/" .. TutorExtract.CACHE_SUB .. "/" .. TutorExtract.CACHE_FILE
  local moves, learnsets = TutorExtract.read(rom)

  local lines = {
    "-- Auto-generated FRLG sTutorMoves / sTutorLearnsets.",
    "return {",
    string.format("  format_version = %d,", TutorExtract.FORMAT_VERSION),
    "  moves = {",
  }
  for i = 0, Versions.TUTOR_MOVE_COUNT - 1 do
    lines[#lines + 1] = string.format("    [%d] = %d,", i, moves[i])
  end
  lines[#lines + 1] = "  },"
  lines[#lines + 1] = "  learnsets = {"
  for species = 0, Versions.NUM_SPECIES - 1 do
    if learnsets[species] ~= 0 then
      lines[#lines + 1] = string.format("    [%d] = %d,", species, learnsets[species])
    end
  end
  lines[#lines + 1] = "  },"
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  cache:write(rel, table.concat(lines, "\n"))

  local rows = 0
  for _, bits in pairs(learnsets) do
    if bits ~= 0 then rows = rows + 1 end
  end
  print(string.format("[tutor_extract] %d tutor moves, %d species with a tutor bit -> %s",
    Versions.TUTOR_MOVE_COUNT, rows, rel))
  return { rel = rel, species = rows }
end

function TutorExtract.ready(cache, cacheRoot)
  local rel = (cacheRoot or default_cache_root()) .. "/"
    .. TutorExtract.CACHE_SUB .. "/" .. TutorExtract.CACHE_FILE
  if not (cache and cache.exists) then return false end
  return cache:exists(rel)
end

return TutorExtract
