-- src/trainer_tower_sets.c:8951, src/trainer_tower.c:105, :191, :204, :382

local Versions = require("src.import.gba.versions")
local TextIR = require("src.core.game3.scripting.text_ir")

local TrainerTowerExtract = {}

TrainerTowerExtract.CACHE_REL = "trainer_tower.lua"
TrainerTowerExtract.CACHE_SUB = "trainer_tower"
TrainerTowerExtract.FORMAT_VERSION = 1
-- src/battle_records.c:37 sTiles, :38 sPalette, :39 sTilemap
TrainerTowerExtract.SCREEN_W = 240
TrainerTowerExtract.SCREEN_H = 160

-- include/cereader_tool.h:7
local TRAINER_STRIDE = 328
local TRAINER_NAME_LEN = 11
local SPEECH_WORDS = 6
local MON_STRIDE = 44
local PARTY_SIZE = 6
local MON_BASE = 0x40

local function default_cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then
    return Extract.CACHE_ROOT
  end
  return "data/generated/gba"
end

local function decode_name(rom, off, len)
  local bytes = {}
  for i = 0, len - 1 do
    local b = rom:get(off + i)
    bytes[#bytes + 1] = b
    if b == 0xFF then break end
  end
  local out = {}
  for _, seg in ipairs(TextIR.decode(bytes)) do
    if seg.t == "text" then out[#out + 1] = seg.s end
  end
  return table.concat(out)
end

local function words(rom, off)
  local list = {}
  for i = 0, SPEECH_WORDS - 1 do
    list[#list + 1] = tostring(rom:u16(off + i * 2))
  end
  return table.concat(list, ", ")
end

-- include/pokemon.h:143
local function mon_row(rom, off)
  local ivs = rom:u32(off + 0x18)
  local function field(shift)
    return math.floor(ivs / 2 ^ shift) % 32
  end
  local moves = {}
  for i = 0, 3 do moves[#moves + 1] = tostring(rom:u16(off + 4 + i * 2)) end
  return string.format(
    "{ species = %d, heldItem = %d, moves = { %s }, level = %d, ppBonuses = %d, "
    .. "hpEV = %d, attackEV = %d, defenseEV = %d, speedEV = %d, spAttackEV = %d, spDefenseEV = %d, "
    .. "otId = %d, hpIV = %d, attackIV = %d, defenseIV = %d, speedIV = %d, spAttackIV = %d, "
    .. "spDefenseIV = %d, abilityNum = %d, personality = %d, nickname = %q, friendship = %d }",
    rom:u16(off), rom:u16(off + 2), table.concat(moves, ", "),
    rom:get(off + 0x0C), rom:get(off + 0x0D),
    rom:get(off + 0x0E), rom:get(off + 0x0F), rom:get(off + 0x10),
    rom:get(off + 0x11), rom:get(off + 0x12), rom:get(off + 0x13),
    rom:u32(off + 0x14),
    field(0), field(5), field(10), field(15), field(20), field(25),
    math.floor(ivs / 2 ^ 31) % 2,
    rom:u32(off + 0x1C),
    decode_name(rom, off + 0x20, 11), rom:get(off + 0x2B))
end

local function trainer_row(rom, off)
  local mons = {}
  for i = 0, PARTY_SIZE - 1 do
    mons[#mons + 1] = "        " .. mon_row(rom, off + MON_BASE + i * MON_STRIDE) .. ","
  end
  return string.format([[
      { name = %q, facilityClass = %d, textColor = %d,
        speechBefore = { %s }, speechWin = { %s },
        speechLose = { %s }, speechAfter = { %s },
        mons = {
%s
        } },]],
    decode_name(rom, off, TRAINER_NAME_LEN), rom:get(off + 0x0B), rom:get(off + 0x0C),
    words(rom, off + 0x0E), words(rom, off + 0x1A),
    words(rom, off + 0x26), words(rom, off + 0x32),
    table.concat(mons, "\n"))
end

local function floor_rows(rom, floorOff)
  local trainers = {}
  for i = 0, Versions.TRAINER_TOWER_TRAINERS_PER_FLOOR - 1 do
    trainers[#trainers + 1] = trainer_row(rom, floorOff + 4 + i * TRAINER_STRIDE)
  end
  return string.format([[
    { id = %d, floorIdx = %d, challengeType = %d, prize = %d,
      trainers = {
%s
      } },]],
    rom:get(floorOff), rom:get(floorOff + 1), rom:get(floorOff + 2), rom:get(floorOff + 3),
    table.concat(trainers, "\n"))
end

-- src/trainer_tower.c:960
local function encounter_music(rom)
  local lut = {}
  for i = 0, Versions.TT_ENCOUNTER_MUSIC_LUT_COUNT - 1 do
    local off = Versions.TT_ENCOUNTER_MUSIC_LUT + i * 4
    lut[#lut + 1] = { klass = rom:get(off), music = rom:get(off + 1) }
  end
  local songs = {}
  for i = 0, Versions.TT_ENCOUNTER_MUSIC_COUNT - 1 do
    songs[i] = rom:u16(Versions.TT_ENCOUNTER_MUSIC + i * 2)
  end
  local out = {}
  for klass = 0, Versions.FACILITY_CLASS_COUNT - 1 do
    local trainerClass = rom:get(Versions.FACILITY_CLASS_TO_TRAINER_CLASS + klass)
    local idx = 0
    for _, row in ipairs(lut) do
      if row.klass == trainerClass then
        idx = row.music
        break
      end
    end
    out[#out + 1] = string.format("  [%d] = %d,", klass, songs[idx] or songs[0] or 0)
  end
  return table.concat(out, "\n")
end

function TrainerTowerExtract.run(rom, cache, opts)
  opts = opts or {}
  local cacheRoot = opts.cacheRoot or default_cache_root()
  local rel = cacheRoot .. "/" .. TrainerTowerExtract.CACHE_REL

  local lines = {
    "-- Auto-generated FRLG gTrainerTowerFloors and facility-class lookups.",
    "return {",
    string.format("  format_version = %d,", TrainerTowerExtract.FORMAT_VERSION),
    string.format("  header = { numFloors = %d, id = %d },",
      rom:get(Versions.TRAINER_TOWER_HEADER), rom:get(Versions.TRAINER_TOWER_HEADER + 1)),
    "  floors = {",
  }

  local floorCount = 0
  for challenge = 0, Versions.TRAINER_TOWER_CHALLENGE_TYPES - 1 do
    lines[#lines + 1] = string.format("  [%d] = {", challenge)
    for floor = 0, Versions.TRAINER_TOWER_MAX_FLOORS - 1 do
      local ptr = Versions.TRAINER_TOWER_FLOORS
        + (challenge * Versions.TRAINER_TOWER_MAX_FLOORS + floor) * 4
      local floorOff = rom:ptrOffset(rom:u32(ptr))
      if not floorOff then
        error(string.format("trainer_tower: bad floor pointer %d/%d", challenge, floor))
      end
      lines[#lines + 1] = floor_rows(rom, floorOff)
      floorCount = floorCount + 1
    end
    lines[#lines + 1] = "  },"
  end
  lines[#lines + 1] = "  },"

  lines[#lines + 1] = "  singlesTrainerInfo = {"
  for i = 0, Versions.TT_SINGLES_INFO_COUNT - 1 do
    local off = Versions.TT_SINGLES_INFO + i * 4
    lines[#lines + 1] = string.format("  [%d] = { objGfx = %d, gender = %d },",
      rom:get(off + 1), rom:get(off), rom:get(off + 2))
  end
  lines[#lines + 1] = "  },"

  lines[#lines + 1] = "  doublesTrainerInfo = {"
  for i = 0, Versions.TT_DOUBLES_INFO_COUNT - 1 do
    local off = Versions.TT_DOUBLES_INFO + i * 8
    lines[#lines + 1] = string.format(
      "  [%d] = { objGfx1 = %d, objGfx2 = %d, gender1 = %d, gender2 = %d },",
      rom:get(off + 2), rom:get(off), rom:get(off + 1), rom:get(off + 3), rom:get(off + 4))
  end
  lines[#lines + 1] = "  },"

  lines[#lines + 1] = "  encounterMusic = {"
  lines[#lines + 1] = encounter_music(rom)
  lines[#lines + 1] = "  },"

  lines[#lines + 1] = "  facilityClassPic = {"
  for klass = 0, Versions.FACILITY_CLASS_COUNT - 1 do
    lines[#lines + 1] = string.format("  [%d] = %d,",
      klass, rom:get(Versions.FACILITY_CLASS_TO_PIC + klass))
  end
  lines[#lines + 1] = "  },"

  -- src/trainer_tower.c:447, src/battle_tower.c:1340
  lines[#lines + 1] = "  facilityClassTrainerClass = {"
  for klass = 0, Versions.FACILITY_CLASS_COUNT - 1 do
    lines[#lines + 1] = string.format("  [%d] = %d,",
      klass, rom:get(Versions.FACILITY_CLASS_TO_TRAINER_CLASS + klass))
  end
  lines[#lines + 1] = "  },"

  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  cache:write(rel, table.concat(lines, "\n"))

  local dir = cacheRoot .. "/" .. TrainerTowerExtract.CACHE_SUB
  local BgBake = require("src.import.gba.bg_bake")
  local function raw(off, n)
    local out = {}
    for i = 1, n do out[i] = rom:get(off + i - 1) end
    out._len = n
    return out
  end
  -- src/battle_records.c:563 LoadFrameGfxOnBg, BG_PLTT_ID(0)
  local recordsGfx = raw(Versions.BATTLE_RECORDS_GFX, 0xC0)
  local recordsMap = raw(Versions.BATTLE_RECORDS_TILEMAP, 2048)
  local recordsBanks = BgBake.loadPalBanks(raw(Versions.BATTLE_RECORDS_PAL, 32), 1)
  cache:write(dir .. "/records_bg.rgba",
    BgBake.bakeBgRgba(recordsGfx, recordsBanks, recordsMap,
      TrainerTowerExtract.SCREEN_W, TrainerTowerExtract.SCREEN_H))
  cache:write(dir .. "/manifest.lua", string.format([[
return {
  format_version = %d,
  recordsBg = { width = %d, height = %d },
}
]], TrainerTowerExtract.FORMAT_VERSION,
    TrainerTowerExtract.SCREEN_W, TrainerTowerExtract.SCREEN_H))

  print(string.format("[trainer_tower_extract] %d floors, %d singles classes, %d doubles classes, records bg %dx%d -> %s",
    floorCount, Versions.TT_SINGLES_INFO_COUNT, Versions.TT_DOUBLES_INFO_COUNT,
    TrainerTowerExtract.SCREEN_W, TrainerTowerExtract.SCREEN_H, rel))
  return { rel = rel, floors = floorCount, dir = dir }
end

function TrainerTowerExtract.ready(cache, cacheRoot)
  local root = cacheRoot or default_cache_root()
  local rel = root .. "/" .. TrainerTowerExtract.CACHE_REL
  if not (cache and cache.exists) then return false end
  if not cache:exists(rel) then return false end
  local dir = root .. "/" .. TrainerTowerExtract.CACHE_SUB
  return cache:exists(dir .. "/records_bg.rgba") and cache:exists(dir .. "/manifest.lua")
end

return TrainerTowerExtract
