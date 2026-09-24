-- Extract FRLG species pack from ROM into data/generated/gba/pokemon/.
-- FireRed USA 1.0: names, types, base stats, abilities, national dex, icons.
-- Also runs party_chrome_extract into pokemon/party/.

local Versions = require("src.import.gba.versions")
local TextIR = require("src.core.game3.scripting.text_ir")
local Lz77 = require("src.import.gba.lz77")

local PokemonExtract = {}

PokemonExtract.MAGIC = "SVPK"
PokemonExtract.FORMAT_VERSION = 6
PokemonExtract.CACHE_SUB = "pokemon"

local function default_cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then
    return Extract.CACHE_ROOT
  end
  return "data/generated/gba"
end

local function put(cache, rel, bytes)
  local ok, err = cache:write(rel, bytes)
  if ok == false then
    error("pokemon_extract: could not write " .. rel .. ": " .. tostring(err))
  end
  return true
end

local function bgr555_to_rgb8(c)
  c = (tonumber(c) or 0) % 32768
  local r5 = c % 32
  local g5 = math.floor(c / 32) % 32
  local b5 = math.floor(c / 1024) % 32
  return math.floor(r5 * 255 / 31 + 0.5),
    math.floor(g5 * 255 / 31 + 0.5),
    math.floor(b5 * 255 / 31 + 0.5)
end

local SPECIES_CASTFORM = 385
local SPECIES_SPINDA = 308

local function gba_off(ptr)
  return Versions.gbaToFile(ptr)
end

local function decode_name(rom, off, length)
  length = length or Versions.SPECIES_NAME_LENGTH
  local chars = {}
  for i = 0, length - 1 do
    local b = rom:get(off + i)
    -- GBA charmap: 0x00 is space; only 0xFF is EOS.
    if b == 0xFF then break end
    local ch = TextIR.CHARMAP[b]
    if ch and ch ~= "" then
      chars[#chars + 1] = ch
    elseif b >= 0xBB and b <= 0xD4 then
      chars[#chars + 1] = string.char(string.byte("A") + (b - 0xBB))
    elseif b >= 0xD5 and b <= 0xEE then
      chars[#chars + 1] = string.char(string.byte("a") + (b - 0xD5))
    else
      chars[#chars + 1] = "?"
    end
  end
  return table.concat(chars)
end

local function decode_text(rom, off, max)
  max = max or 256
  local chars = {}
  for i = 0, max - 1 do
    local b = rom:get(off + i)
    if b == 0xFF then break end
    if b == 0xFE or b == 0xFA or b == 0xFB then
      chars[#chars + 1] = "\n"
    else
      local ch = TextIR.CHARMAP[b]
      if ch and ch ~= "" then
        chars[#chars + 1] = ch
      elseif b >= 0xBB and b <= 0xD4 then
        chars[#chars + 1] = string.char(string.byte("A") + (b - 0xBB))
      elseif b >= 0xD5 and b <= 0xEE then
        chars[#chars + 1] = string.char(string.byte("a") + (b - 0xD5))
      else
        chars[#chars + 1] = "?"
      end
    end
  end
  return table.concat(chars)
end

local ffi
do
  local ok, mod = pcall(require, "ffi")
  if ok and mod and mod.new and mod.string then
    ffi = mod
  end
end

local bit = rawget(_G, "bit") or rawget(_G, "bit32")
if not bit then
  local ok, mod = pcall(require, "bit")
  if ok and mod then bit = mod end
end

local static_rgba_buf = nil
local static_rgba_cap = 0
local function get_rgba_buffer(size_bytes)
  if not ffi then return nil end
  if static_rgba_cap < size_bytes then
    static_rgba_cap = math.max(size_bytes + 1024, 65536)
    static_rgba_buf = ffi.new("uint8_t[?]", static_rgba_cap)
  end
  return static_rgba_buf
end

--- Decode GBA 4bpp tiles → flat 1-based index buffer (w*h).
local function decode_4bpp(bytes, w, h)
  local tilesW = bit and bit.rshift(w, 3) or math.floor(w / 8)
  local tilesH = bit and bit.rshift(h, 3) or math.floor(h / 8)
  local pixels = {}
  local ti = 0
  local band = bit and bit.band
  local rshift = bit and bit.rshift
  for ty = 0, tilesH - 1 do
    for tx = 0, tilesW - 1 do
      local tileOff = ti * 32 -- 32 bytes / 4bpp tile
      for row = 0, 7 do
        for bx = 0, 3 do
          local bi = tileOff + row * 4 + bx + 1
          local byte = bytes[bi] or 0
          local p0, p1
          if band and rshift then
            p0 = band(byte, 0x0F)
            p1 = rshift(byte, 4)
          else
            p0 = byte % 16
            p1 = math.floor(byte / 16) % 16
          end
          local x0 = tx * 8 + bx * 2
          local y0 = ty * 8 + row
          pixels[y0 * w + x0 + 1] = p0
          pixels[y0 * w + x0 + 2] = p1
        end
      end
      ti = ti + 1
    end
  end
  return pixels
end

local function load_icon_pals(rom)
  local base = Versions.MON_ICON_PALETTES
  local pals = {}
  for i = 0, Versions.MON_ICON_PAL_COUNT - 1 do
    local colors = {}
    local off = base + i * 32 -- 16 × u16
    for c = 0, 15 do
      colors[c] = rom:u16(off + c * 2)
    end
    pals[i] = colors
  end
  return pals
end

local function bake_icon_rgba(pixels, pal, w, h)
  local rgb = {}
  for c = 0, 15 do
    local r, g, b = bgr555_to_rgb8(pal[c] or 0)
    rgb[c] = { r, g, b }
  end
  local total_pixels = w * h
  local total_bytes = total_pixels * 4
  local buf = get_rgba_buffer(total_bytes)
  if buf then
    local ptr = 0
    for i = 1, total_pixels do
      local idx = pixels[i] or 0
      if idx == 0 then
        buf[ptr] = 0
        buf[ptr + 1] = 0
        buf[ptr + 2] = 0
        buf[ptr + 3] = 0
      else
        local c = rgb[idx] or rgb[0]
        buf[ptr] = c[1]
        buf[ptr + 1] = c[2]
        buf[ptr + 2] = c[3]
        buf[ptr + 3] = 255
      end
      ptr = ptr + 4
    end
    return ffi.string(buf, total_bytes)
  end

  local chunks = {}
  for i = 1, total_pixels do
    local idx = pixels[i] or 0
    if idx == 0 then
      chunks[i] = string.char(0, 0, 0, 0)
    else
      local c = rgb[idx] or rgb[0]
      chunks[i] = string.char(c[1], c[2], c[3], 255)
    end
  end
  return table.concat(chunks)
end

local function decode_pic_sheet(tiles, palBytes, frame, bank)
  if not tiles or not palBytes then return nil end
  local palBase = (tonumber(bank) or 0) * 32
  local tileBase = (tonumber(frame) or 0) * 2048
  local pal = {}
  for c = 0, 15 do
    local lo = palBytes[palBase + c * 2 + 1] or 0
    local hi = palBytes[palBase + c * 2 + 2] or 0
    pal[c] = lo + hi * 256
  end
  local w, h = 64, 64
  local rgb = {}
  for c = 0, 15 do
    local r, g, b = bgr555_to_rgb8(pal[c] or 0)
    rgb[c] = { r, g, b }
  end
  local tilesW, tilesH = 8, 8
  local total_bytes = w * h * 4
  local buf = get_rgba_buffer(total_bytes)
  local band = bit and bit.band
  local rshift = bit and bit.rshift

  if buf and band and rshift then
    local ti = 0
    for ty = 0, tilesH - 1 do
      for tx = 0, tilesW - 1 do
        local tileOff = ti * 32
        for row = 0, 7 do
          for bx = 0, 3 do
            local bi = tileBase + tileOff + row * 4 + bx + 1
            local byte = tiles[bi] or 0
            local p0 = band(byte, 0x0F)
            local p1 = rshift(byte, 4)
            local x0 = tx * 8 + bx * 2
            local y0 = ty * 8 + row

            local offset0 = (y0 * w + x0) * 4
            if p0 == 0 then
              buf[offset0] = 0
              buf[offset0 + 1] = 0
              buf[offset0 + 2] = 0
              buf[offset0 + 3] = 0
            else
              local c = rgb[p0] or rgb[0]
              buf[offset0] = c[1]
              buf[offset0 + 1] = c[2]
              buf[offset0 + 2] = c[3]
              buf[offset0 + 3] = 255
            end

            local offset1 = (y0 * w + x0 + 1) * 4
            if p1 == 0 then
              buf[offset1] = 0
              buf[offset1 + 1] = 0
              buf[offset1 + 2] = 0
              buf[offset1 + 3] = 0
            else
              local c = rgb[p1] or rgb[0]
              buf[offset1] = c[1]
              buf[offset1 + 1] = c[2]
              buf[offset1 + 2] = c[3]
              buf[offset1 + 3] = 255
            end
          end
        end
        ti = ti + 1
      end
    end
    return ffi.string(buf, total_bytes)
  end

  local chunks = {}
  local ti = 0
  for ty = 0, tilesH - 1 do
    for tx = 0, tilesW - 1 do
      local tileOff = ti * 32
      for row = 0, 7 do
        for bx = 0, 3 do
          local bi = tileBase + tileOff + row * 4 + bx + 1
          local byte = tiles[bi] or 0
          local p0 = byte % 16
          local p1 = math.floor(byte / 16) % 16
          local x0 = tx * 8 + bx * 2
          local y0 = ty * 8 + row
          local i0 = y0 * w + x0 + 1
          if p0 == 0 then
            chunks[i0] = string.char(0, 0, 0, 0)
          else
            local c = rgb[p0] or rgb[0]
            chunks[i0] = string.char(c[1], c[2], c[3], 255)
          end
          local i1 = y0 * w + x0 + 2
          if p1 == 0 then
            chunks[i1] = string.char(0, 0, 0, 0)
          else
            local c = rgb[p1] or rgb[0]
            chunks[i1] = string.char(c[1], c[2], c[3], 255)
          end
        end
      end
      ti = ti + 1
    end
  end
  return table.concat(chunks)
end

local function lua_escape(s)
  return (tostring(s or ""):gsub("\\", "\\\\"):gsub("\"", "\\\""):gsub("\n", "\\n"))
end

local function write_names_lua(names)
  local lines = {
    "-- Auto-generated FRLG gSpeciesNames (internal SPECIES id).",
    "return {",
  }
  for id = 0, #names do
    local n = names[id]
    if n and n ~= "" then
      lines[#lines + 1] = string.format("  [%d] = \"%s\",", id, lua_escape(n))
    end
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

local function write_types_lua(types)
  local lines = {
    "-- Auto-generated FRLG BaseStats type1/type2 (internal SPECIES id).",
    "return {",
  }
  local ids = {}
  for id in pairs(types) do
    if type(id) == "number" then ids[#ids + 1] = id end
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local t = types[id]
    lines[#lines + 1] = string.format(
      "  [%d] = { %d, %d },", id, t[1] or 0, t[2] or 0)
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

local function write_national_lua(toNat)
  local lines = {
    "-- Auto-generated sSpeciesToNationalPokedexNum (+ reverse).",
    "local M = { toNational = {}, toSpecies = {} }",
  }
  local ids = {}
  for sp in pairs(toNat) do
    if type(sp) == "number" then ids[#ids + 1] = sp end
  end
  table.sort(ids)
  for _, sp in ipairs(ids) do
    local nat = toNat[sp]
    if nat and nat > 0 then
      lines[#lines + 1] = string.format("M.toNational[%d] = %d", sp, nat)
      lines[#lines + 1] = string.format("M.toSpecies[%d] = %d", nat, sp)
    end
  end
  lines[#lines + 1] = "return M"
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

local function write_stats_lua(stats)
  local lines = {
    "-- Auto-generated FRLG BaseStats (hp/atk/def/spe/spa/spd).",
    "return {",
  }
  local ids = {}
  for id in pairs(stats) do
    if type(id) == "number" then ids[#ids + 1] = id end
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local s = stats[id]
    lines[#lines + 1] = string.format(
      "  [%d] = { hp = %d, atk = %d, def = %d, spe = %d, spa = %d, spd = %d },",
      id, s.hp or 0, s.atk or 0, s.def or 0, s.spe or 0, s.spa or 0, s.spd or 0)
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

local function write_abilities_lua(abilities)
  local lines = {
    "-- Auto-generated FRLG BaseStats abilities[2] (ability ids).",
    "return {",
  }
  local ids = {}
  for id in pairs(abilities) do
    if type(id) == "number" then ids[#ids + 1] = id end
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local a = abilities[id]
    lines[#lines + 1] = string.format(
      "  [%d] = { %d, %d },", id, a[1] or 0, a[2] or 0)
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

local function write_ability_names_lua(names)
  local lines = {
    "-- Auto-generated FRLG gAbilityNames.",
    "return {",
  }
  for id = 0, #names do
    local n = names[id]
    if n and n ~= "" then
      lines[#lines + 1] = string.format("  [%d] = \"%s\",", id, lua_escape(n))
    end
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

local function write_species_meta_lua(meta)
  local lines = {
    "-- Auto-generated FRLG BaseStats catch/exp/gender/growth/egg extras.",
    "return {",
  }
  local ids = {}
  for id in pairs(meta) do
    if type(id) == "number" then ids[#ids + 1] = id end
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local m = meta[id]
    local link = ""
    if type(m.linkStats) == "table" then
      local ls = m.linkStats
      link = string.format(", linkStats = { %d, %d, %d, %d, %d, %d }",
        ls[1], ls[2], ls[3], ls[4], ls[5], ls[6])
    end
    lines[#lines + 1] = string.format(
      "  [%d] = { catchRate = %d, expYield = %d, genderRatio = %d, eggCycles = %d, friendship = %d, growthRate = %d, eggGroup1 = %d, eggGroup2 = %d, itemCommon = %d, itemRare = %d, evHp = %d, evAtk = %d, evDef = %d, evSpe = %d, evSpa = %d, evSpd = %d, safariZoneFleeRate = %d%s },",
      id,
      m.catchRate or 0, m.expYield or 0, m.genderRatio or 0,
      m.eggCycles or 0, m.friendship or 0, m.growthRate or 0,
      m.eggGroup1 or 0, m.eggGroup2 or 0,
      m.itemCommon or 0, m.itemRare or 0,
      m.evHp or 0, m.evAtk or 0, m.evDef or 0,
      m.evSpe or 0, m.evSpa or 0, m.evSpd or 0,
      m.safariZoneFleeRate or 0, link)
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

local function write_manifest(count, version)
  return string.format(
    "return { magic = \"%s\", format = %d, pokemonVersion = %d, numSpecies = %d, iconW = %d, iconH = %d, iconSheetH = %d, iconFrames = %d, abilitiesCount = %d, movesCount = %d }\n",
    PokemonExtract.MAGIC,
    PokemonExtract.FORMAT_VERSION,
    version or Versions.POKEMON_VERSION,
    count,
    Versions.MON_ICON_W or 32,
    Versions.MON_ICON_H or 32,
    64,
    2,
    Versions.ABILITIES_COUNT or 78,
    Versions.MOVES_COUNT or 355)
end

local function write_move_names_lua(names)
  local lines = {
    "-- Auto-generated FRLG gMoveNames.",
    "return {",
  }
  local count = Versions.MOVES_COUNT or 355
  for id = 0, count - 1 do
    local n = names[id]
    if n and n ~= "" then
      lines[#lines + 1] = string.format("  [%d] = \"%s\",", id, lua_escape(n))
    end
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

local function write_learnsets_lua(learnsets)
  local lines = {
    "-- Auto-generated FRLG gLevelUpLearnsets (packed level/move).",
    "return {",
  }
  local ids = {}
  for id in pairs(learnsets) do
    if type(id) == "number" then ids[#ids + 1] = id end
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local list = learnsets[id] or {}
    local parts = {}
    for _, e in ipairs(list) do
      parts[#parts + 1] = string.format("{%d,%d}", e.level or 0, e.move or 0)
    end
    lines[#lines + 1] = string.format("  [%d] = { %s },", id, table.concat(parts, ", "))
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

local function write_egg_moves_lua(eggMoves)
  local lines = {
    "-- Auto-generated FRLG gEggMoves: [species] = { move ids }.",
    "return {",
  }
  local ids = {}
  for id in pairs(eggMoves) do
    if type(id) == "number" then ids[#ids + 1] = id end
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local list = eggMoves[id] or {}
    if #list > 0 then
      lines[#lines + 1] = string.format("  [%d] = { %s },",
        id, table.concat(list, ", "))
    end
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

local function write_evolutions_lua(evos)
  local lines = {
    "-- Auto-generated FRLG gEvolutionTable (method, param, targetSpecies).",
    "return {",
  }
  local ids = {}
  for id in pairs(evos) do
    if type(id) == "number" then ids[#ids + 1] = id end
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local list = evos[id] or {}
    if #list > 0 then
      local parts = {}
      for _, e in ipairs(list) do
        parts[#parts + 1] = string.format(
          "{method=%d,param=%d,target=%d}",
          e.method or 0, e.param or 0, e.target or 0)
      end
      lines[#lines + 1] = string.format("  [%d] = { %s },", id, table.concat(parts, ", "))
    end
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

local function write_tmhm_lua(tmhm, tmMoves)
  local lines = {
    "-- Auto-generated FRLG sTMHMLearnsets + sTMHMMoves.",
    "local M = { machines = {}, learnsets = {} }",
  }
  for i = 0, (Versions.TMHM_COUNT or 58) - 1 do
    lines[#lines + 1] = string.format("M.machines[%d] = %d", i, tmMoves[i] or 0)
  end
  local ids = {}
  for id in pairs(tmhm) do
    if type(id) == "number" then ids[#ids + 1] = id end
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local bits = tmhm[id]
    if bits and (bits.lo ~= 0 or bits.hi ~= 0) then
      lines[#lines + 1] = string.format(
        "M.learnsets[%d] = { lo = %u, hi = %u }",
        id, bits.lo or 0, bits.hi or 0)
    end
  end
  lines[#lines + 1] = "return M"
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

local function write_dex_lua(dex)
  local lines = {
    "-- Auto-generated FRLG gPokedexEntries (national index): category/height/weight.",
    "return {",
  }
  local ids = {}
  for id in pairs(dex) do
    if type(id) == "number" then ids[#ids + 1] = id end
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local e = dex[id]
    lines[#lines + 1] = string.format(
      "  [%d] = { category = \"%s\", height = %d, weight = %d },",
      id, lua_escape(e.category or ""), e.height or 0, e.weight or 0)
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

--- Decode gEggMoves into `{ [species] = { moveId, … } }`.
---
--- Not a pointer table: one flat u16 stream of runs, each opened by
--- `species + EGG_MOVES_SPECIES_OFFSET` (a move id is always < 355, so the
--- offset is what tells a header from a move) and closed by 0xFFFF.  The table
--- stops after its last run, so the first word that is neither a header nor a
--- plausible move id ends the scan.  Species without egg moves are absent.
local function extract_egg_moves(rom, num)
  local eggMoves = {}
  local base = Versions.EGG_MOVES
  if not base then return eggMoves end
  local offset = Versions.EGG_MOVES_SPECIES_OFFSET or 20000
  local terminator = Versions.EGG_MOVES_TERMINATOR or 0xFFFF
  local maxMoves = Versions.EGG_MOVES_MAX or 16
  local moveCount = Versions.MOVES_COUNT or 355
  local limit = math.min(rom.size or Versions.ROM_SIZE or base, base + 0x10000)
  local species
  local o = base
  while o + 1 < limit do
    local word = rom:u16(o)
    o = o + 2
    if word == terminator then
      if not species then break end -- the table's own terminator
      species = nil
    elseif word >= offset then
      local id = word - offset
      species = (id < num) and id or nil
      if species then eggMoves[species] = eggMoves[species] or {} end
    elseif species and word > 0 and word < moveCount then
      local list = eggMoves[species]
      if #list < maxMoves then list[#list + 1] = word end
    else
      break -- not a gEggMoves stream: stop rather than invent data
    end
  end
  return eggMoves
end

-- gMonIconTable / gMonIconPaletteIndices entry for one species, both frames
-- (32x64 RGBA); they run past NUM_SPECIES, so SPECIES_EGG has its own icon.
local function icon_rgba(rom, sp, pals)
  pals = pals or load_icon_pals(rom)
  local w = Versions.MON_ICON_W or 32
  local iconH = (Versions.MON_ICON_H or 32) * 2 -- 64 (2 frames)
  local iconBytes = Versions.MON_ICON_BYTES or math.floor(w * iconH / 2) -- 1024 for 32x64
  local off = gba_off(rom:u32(Versions.MON_ICON_TABLE + sp * 4))
  if not off then return string.rep(string.char(0, 0, 0, 0), w * iconH * 4) end
  local palIdx = rom:get(Versions.MON_ICON_PAL_INDICES + sp) or 0
  if palIdx >= Versions.MON_ICON_PAL_COUNT then palIdx = 0 end
  local pixels = decode_4bpp(rom:readBytes(off, iconBytes), w, iconH)
  return bake_icon_rgba(pixels, pals[palIdx] or pals[0], w, iconH)
end

-- Exposed for tests (tests/engine/game3_egg_moves.lua).
PokemonExtract.eggMovesFromRom = extract_egg_moves
PokemonExtract.writeEggMovesLua = write_egg_moves_lua
-- src/import/gba/egg_extract.lua bakes the SPECIES_EGG icon with it.
PokemonExtract.iconRgba = icon_rgba

--- Extract full pack into cache under {cacheRoot}/pokemon/.
function PokemonExtract.run(rom, cache, opts)
  opts = opts or {}
  local cacheRoot = opts.cacheRoot or default_cache_root()
  local root = cacheRoot .. "/" .. PokemonExtract.CACHE_SUB
  local num = opts.numSpecies or Versions.NUM_SPECIES
  local progress = opts.progress

  local names = {}
  local types = {}
  local stats = {}
  local abilities = {}
  local meta = {}
  local toNat = {}
  local nameBase = Versions.SPECIES_NAMES
  local infoBase = Versions.SPECIES_INFO
  local natBase = Versions.SPECIES_TO_NATIONAL
  local pals = load_icon_pals(rom)
  local frontPicTable = (Versions.INTRO and Versions.INTRO.mon_front_pic_table) or 0x2350AC
  local backPicTable = Versions.MON_BACK_PIC_TABLE or 0x23654C
  local palTable = (Versions.INTRO and Versions.INTRO.mon_palette_table) or 0x23730C

  local picsWritten = { icons = 0, front = 0, back = 0 }
  local picsMissing = {}
  local function noteMissing(kind, sp)
    picsMissing[#picsMissing + 1] = kind .. "/" .. sp
  end

  local function lz(off)
    local ok, out = pcall(Lz77.decompress, function(i) return rom:get(i) end, off)
    if ok then return out end
    return nil
  end

  -- src/pokemon.c:5904
  local function write_pics(sp)
    local palOff = gba_off(rom:u32(palTable + sp * 8))
    local shinyOff = gba_off(rom:u32(Versions.MON_SHINY_PALETTE_TABLE + sp * 8))
    local palBytes = palOff and lz(palOff)
    local shinyBytes = shinyOff and lz(shinyOff)
    for _, kind in ipairs({ "front", "back" }) do
      local tableOff = kind == "front" and frontPicTable or backPicTable
      local picOff = gba_off(rom:u32(tableOff + sp * 8))
      if picOff and palOff then
        local tiles = lz(picOff)
        local rgba = tiles and palBytes and decode_pic_sheet(tiles, palBytes)
        local shiny = tiles and shinyBytes and decode_pic_sheet(tiles, shinyBytes)
        if rgba and shiny then
          put(cache, root .. "/" .. kind .. "/" .. sp .. ".rgba", rgba)
          put(cache, root .. "/" .. kind .. "_shiny/" .. sp .. ".rgba", shiny)
          picsWritten[kind] = picsWritten[kind] + 1
          -- pokefirered/graphics_file_rules.mk:29
          -- src/pokemon.c:1350, :5339
          if sp == SPECIES_SPINDA and kind == "front" then
            local function raw(t, n)
              local out = {}
              for i = 1, n do out[i] = string.char(t[i] or 0) end
              return table.concat(out)
            end
            local spots = {}
            for i = 0, 143 do spots[i + 1] = string.char(rom:get(Versions.SPINDA_SPOT_GRAPHICS + i)) end
            put(cache, root .. "/spinda/front.4bpp", raw(tiles, 2048))
            put(cache, root .. "/spinda/normal.gbapal", raw(palBytes, 32))
            put(cache, root .. "/spinda/shiny.gbapal", raw(shinyBytes, 32))
            put(cache, root .. "/spinda/spots.bin", table.concat(spots))
          end
          if sp == SPECIES_CASTFORM then
            for form = 1, 3 do
              put(cache, root .. "/" .. kind .. "/" .. sp .. "_" .. form .. ".rgba",
                decode_pic_sheet(tiles, palBytes, form, form))
              put(cache, root .. "/" .. kind .. "_shiny/" .. sp .. "_" .. form .. ".rgba",
                decode_pic_sheet(tiles, shinyBytes, form, form))
            end
          end
        else
          noteMissing(kind, sp)
        end
      end
    end
  end

  for sp = 0, num - 1 do
    if progress and sp % 40 == 0 then
      progress("pokemon", sp, num)
    end
    names[sp] = decode_name(rom, nameBase + sp * Versions.SPECIES_NAME_LENGTH)
    local ioff = infoBase + sp * Versions.SPECIES_INFO_SIZE
    stats[sp] = {
      hp = rom:get(ioff + 0),
      atk = rom:get(ioff + 1),
      def = rom:get(ioff + 2),
      spe = rom:get(ioff + 3),
      spa = rom:get(ioff + 4),
      spd = rom:get(ioff + 5),
    }
    local linkStats
    if sp == 410 then
      local r = stats[sp]
      -- pokefirered/src/pokemon.c:6163
      linkStats = { r.hp, r.atk, r.def, r.spe, r.spa, r.spd }
      local base = Versions.DEOXYS_BASE_STATS
      for i, key in ipairs({ "hp", "atk", "def", "spe", "spa", "spd" }) do
        stats[sp][key] = rom:u16(base + (i - 1) * 2)
      end
    end
    types[sp] = { rom:get(ioff + 6), rom:get(ioff + 7) }
    abilities[sp] = { rom:get(ioff + 0x16), rom:get(ioff + 0x17) }
    -- pokefirered/include/pokemon.h:219
    local evLo, evHi = rom:get(ioff + 0x0A), rom:get(ioff + 0x0B)
    meta[sp] = {
      catchRate = rom:get(ioff + 0x08),
      expYield = rom:get(ioff + 0x09),
      evHp = evLo % 4,
      evAtk = math.floor(evLo / 4) % 4,
      evDef = math.floor(evLo / 16) % 4,
      evSpe = math.floor(evLo / 64) % 4,
      evSpa = evHi % 4,
      evSpd = math.floor(evHi / 4) % 4,
      itemCommon = rom:u16(ioff + 0x0C),
      itemRare = rom:u16(ioff + 0x0E),
      genderRatio = rom:get(ioff + 0x10),
      eggCycles = rom:get(ioff + 0x11),
      friendship = rom:get(ioff + 0x12),
      growthRate = rom:get(ioff + 0x13),
      eggGroup1 = rom:get(ioff + 0x14),
      eggGroup2 = rom:get(ioff + 0x15),
      -- pokefirered/include/pokemon.h:233
      safariZoneFleeRate = rom:get(ioff + 0x18),
      linkStats = linkStats,
    }
    -- Table omits SPECIES_NONE; SpeciesToNationalPokedexNum uses [species - 1].
    toNat[sp] = (sp >= 1) and rom:u16(natBase + (sp - 1) * 2) or 0

    put(cache, root .. "/icons/" .. sp .. ".rgba", icon_rgba(rom, sp, pals))
    picsWritten.icons = picsWritten.icons + 1
    write_pics(sp)
  end

  -- include/constants/species.h:425
  for sp = Versions.SPECIES_UNOWN_B, Versions.SPECIES_UNOWN_QMARK do
    put(cache, root .. "/icons/" .. sp .. ".rgba", icon_rgba(rom, sp, pals))
    write_pics(sp)
  end

  if #picsMissing > 0 then
    local shown = {}
    for i = 1, math.min(8, #picsMissing) do shown[i] = picsMissing[i] end
    error(("pokemon_extract: %d species sprites with valid ROM pointers produced no file (%s%s)")
      :format(#picsMissing, table.concat(shown, ", "), #picsMissing > #shown and ", ..." or ""))
  end
  if picsWritten.icons < num or picsWritten.front < 1 or picsWritten.back < 1 then
    error(("pokemon_extract: sprite pass wrote %d icons, %d front, %d back for %d species")
      :format(picsWritten.icons, picsWritten.front, picsWritten.back, num))
  end

  -- pokefirered/src/battle_gfx_sfx_util.c:422
  local ghostPic = Versions.GHOST_FRONT_PIC
  local ghostPal = Versions.GHOST_PALETTE
  if ghostPic and ghostPal then
    local okT, tiles = pcall(Lz77.decompress, function(i) return rom:get(i) end, ghostPic)
    local okP, palBytes = pcall(Lz77.decompress, function(i) return rom:get(i) end, ghostPal)
    if okT and okP and tiles and palBytes then
      local rgba = decode_pic_sheet(tiles, palBytes)
      if rgba then cache:write(root .. "/front/ghost.rgba", rgba) end
    end
  end

  local abilityNames = {}
  local abilBase = Versions.ABILITY_NAMES
  local abilLen = (Versions.ABILITY_NAME_LENGTH or 12) + 1
  local abilCount = Versions.ABILITIES_COUNT or 78
  for id = 0, abilCount - 1 do
    abilityNames[id] = decode_name(rom, abilBase + id * abilLen, abilLen)
  end

  -- Move names
  local moveNames = {}
  local moveNameBase = Versions.MOVE_NAMES or 0x247094
  local moveNameLen = (Versions.MOVE_NAME_LENGTH or 12) + 1
  local moveCount = Versions.MOVES_COUNT or 355
  for id = 0, moveCount - 1 do
    moveNames[id] = decode_name(rom, moveNameBase + id * moveNameLen, moveNameLen)
  end

  -- Level-up learnsets
  local learnsets = {}
  local learnPtrBase = Versions.LEVEL_UP_LEARNSETS or 0x25D7B4
  for sp = 0, num - 1 do
    if progress and sp % 80 == 0 then
      progress("learnsets", sp, num)
    end
    local ptr = rom:u32(learnPtrBase + sp * 4)
    local off = gba_off(ptr)
    local list = {}
    if off then
      for i = 0, 39 do
        local word = rom:u16(off + i * 2)
        if word == 0xFFFF then break end
        list[#list + 1] = {
          move = word % 512,
          level = math.floor(word / 512) % 128,
        }
      end
    end
    learnsets[sp] = list
  end

  -- Evolutions
  local evolutions = {}
  local evoBase = Versions.EVOLUTION_TABLE or 0x259754
  local evoPer = Versions.EVOS_PER_MON or 5
  local evoSize = Versions.EVOLUTION_ENTRY_SIZE or 8
  local evoStride = evoPer * evoSize
  for sp = 0, num - 1 do
    local list = {}
    local base = evoBase + sp * evoStride
    for slot = 0, evoPer - 1 do
      local off = base + slot * evoSize
      local method = rom:u16(off)
      if method ~= 0 then
        list[#list + 1] = {
          method = method,
          param = rom:u16(off + 2),
          target = rom:u16(off + 4),
        }
      end
    end
    evolutions[sp] = list
  end

  -- TM/HM learnsets + machine → move map
  local tmhm = {}
  local tmMoves = {}
  local tmBase = Versions.TMHM_LEARNSETS or 0x252BC8
  local tmMoveBase = Versions.TMHM_MOVES or 0x45A5A4
  local tmCount = Versions.TMHM_COUNT or 58
  for i = 0, tmCount - 1 do
    tmMoves[i] = rom:u16(tmMoveBase + i * 2)
  end
  for sp = 0, num - 1 do
    local off = tmBase + sp * 8
    tmhm[sp] = {
      lo = rom:u32(off),
      hi = rom:u32(off + 4),
    }
  end

  -- Egg moves (gEggMoves): sparse, so a species with no egg move is absent
  -- rather than an empty list.
  local eggMoves = extract_egg_moves(rom, num)

  -- National dex entries (category / height / weight)
  local dex = {}
  local dexBase = Versions.POKEDEX_ENTRIES or 0x44E850
  local dexSize = Versions.POKEDEX_ENTRY_SIZE or 36
  local dexCount = (Versions.NATIONAL_DEX_COUNT or 386) + 1
  for nat = 0, dexCount - 1 do
    local off = dexBase + nat * dexSize
    dex[nat] = {
      category = decode_name(rom, off, 12),
      height = rom:u16(off + 0x0C),
      weight = rom:u16(off + 0x0E),
    }
  end

  -- Ability and move descriptions extracted from ROM pointer tables
  local abilityDescs = {}
  local abilityDescBase = Versions.ABILITY_DESCRIPTIONS or 0x24FB08
  local abilityCount = Versions.ABILITIES_COUNT or 78
  for i = 0, abilityCount - 1 do
    local ptr = rom:u32(abilityDescBase + i * 4)
    local off = gba_off(ptr)
    local name = abilityNames[i] or ("ABILITY_" .. i)
    local desc = off and decode_text(rom, off, 256) or ""
    local const = "ABILITY_" .. name:upper():gsub("%s+", "_"):gsub("[^%w_]", "")
    abilityDescs[const] = desc
  end

  local moveDescs = {}
  local moveDescBase = Versions.MOVE_DESCRIPTIONS or 0x4886E8
  local moveCount = (Versions.MOVES_COUNT or 355) - 1
  for i = 0, moveCount - 1 do
    local ptr = rom:u32(moveDescBase + i * 4)
    local off = gba_off(ptr)
    local name = moveNames[i + 1] or ("MOVE_" .. (i + 1))
    local desc = off and decode_text(rom, off, 256) or ""
    local const = "MOVE_" .. name:upper():gsub("%s+", "_"):gsub("[^%w_]", "")
    moveDescs[const] = desc
  end

  local function write_descriptions_lua(abils, mvs)
    local lines = {
      "-- Auto-generated FRLG Ability & Move Descriptions from ROM.",
      "return {",
      "  ABILITIES = {",
    }
    local a_keys = {}
    for k in pairs(abils) do a_keys[#a_keys + 1] = k end
    table.sort(a_keys)
    for _, k in ipairs(a_keys) do
      lines[#lines + 1] = string.format("    [%q] = %q,", k, abils[k])
    end
    lines[#lines + 1] = "  },"
    lines[#lines + 1] = "  MOVES = {"
    local m_keys = {}
    for k in pairs(mvs) do m_keys[#m_keys + 1] = k end
    table.sort(m_keys)
    for _, k in ipairs(m_keys) do
      lines[#lines + 1] = string.format("    [%q] = %q,", k, mvs[k])
    end
    lines[#lines + 1] = "  },"
    lines[#lines + 1] = "}"
    lines[#lines + 1] = ""
    return table.concat(lines, "\n")
  end

  put(cache, root .. "/names.lua", write_names_lua(names))
  put(cache, root .. "/types.lua", write_types_lua(types))
  put(cache, root .. "/stats.lua", write_stats_lua(stats))
  put(cache, root .. "/abilities.lua", write_abilities_lua(abilities))
  put(cache, root .. "/ability_names.lua", write_ability_names_lua(abilityNames))
  put(cache, root .. "/descriptions.lua", write_descriptions_lua(abilityDescs, moveDescs))
  put(cache, root .. "/meta.lua", write_species_meta_lua(meta))
  put(cache, root .. "/national.lua", write_national_lua(toNat))
  put(cache, root .. "/move_names.lua", write_move_names_lua(moveNames))
  put(cache, root .. "/learnsets.lua", write_learnsets_lua(learnsets))
  put(cache, root .. "/evolutions.lua", write_evolutions_lua(evolutions))
  put(cache, root .. "/tmhm.lua", write_tmhm_lua(tmhm, tmMoves))
  put(cache, root .. "/egg_moves.lua", write_egg_moves_lua(eggMoves))
  put(cache, root .. "/dex.lua", write_dex_lua(dex))
  put(cache, root .. "/manifest.lua", write_manifest(num, Versions.POKEMON_VERSION))

  if progress then progress("battle_moves", 0, 1) end
  local BattleMovesExtract = require("src.import.gba.battle_moves_extract")
  local battle = BattleMovesExtract.run(rom, cache, { cacheRoot = cacheRoot })
  if progress then progress("battle_moves", 1, 1) end

  local PartyChromeExtract = require("src.import.gba.party_chrome_extract")
  if progress then progress("party_chrome", 0, 1) end
  local chrome = PartyChromeExtract.run(rom, cache, {
    cacheRoot = cacheRoot,
  })
  if progress then progress("party_chrome", 1, 1) end

  if progress then progress("battle_chrome", 0, 1) end
  local BattleChromeExtract = require("src.import.gba.battle_chrome_extract")
  local battleChrome = BattleChromeExtract.run(rom, cache, {
    cacheRoot = cacheRoot,
  })
  if progress then progress("battle_chrome", 1, 1) end

  local BallOpenExtract = require("src.import.gba.ball_open_extract")
  BallOpenExtract.run(rom, cache, { cacheRoot = cacheRoot })

  local PokedexChromeExtract = require("src.import.gba.pokedex_chrome_extract")
  pcall(function()
    PokedexChromeExtract.run(rom, cache, { cacheRoot = cacheRoot, progress = progress })
  end)

  local StorageChromeExtract = require("src.import.gba.storage_chrome_extract")
  pcall(function()
    StorageChromeExtract.run(rom, cache, { cacheRoot = cacheRoot })
  end)

  if progress then progress("battle_transition", 0, 1) end
  local BattleTransitionExtract = require("src.import.gba.battle_transition_extract")
  local battleTransition = BattleTransitionExtract.run(rom, cache, {
    cacheRoot = cacheRoot,
  })
  if progress then progress("battle_transition", 1, 1) end

  if progress then progress("summary_chrome", 0, 1) end
  local SummaryChromeExtract = require("src.import.gba.summary_chrome_extract")
  local summaryChrome = SummaryChromeExtract.run(rom, cache, {
    cacheRoot = cacheRoot,
  })
  if progress then progress("summary_chrome", 1, 1) end

  if progress then progress("bag_chrome", 0, 1) end
  local BagChromeExtract = require("src.import.gba.bag_chrome_extract")
  local bagChrome = BagChromeExtract.run(rom, cache, { cacheRoot = cacheRoot })
  if progress then progress("bag_chrome", 1, 1) end

  if progress then progress("shop_chrome", 0, 1) end
  local ShopChromeExtract = require("src.import.gba.shop_chrome_extract")
  local shopChrome = ShopChromeExtract.run(rom, cache, { cacheRoot = cacheRoot })
  if progress then progress("shop_chrome", 1, 1) end

  local TextChromeExtract = require("src.import.gba.text_chrome_extract")
  pcall(function()
    TextChromeExtract.run(rom, cache, { cacheRoot = cacheRoot })
  end)

  local ItemsExtract = require("src.import.gba.items_extract")
  pcall(function()
    ItemsExtract.run(rom, cache, { cacheRoot = cacheRoot })
  end)

  local TrainerCardExtract = require("src.import.gba.trainer_card_extract")
  pcall(function()
    TrainerCardExtract.run(rom, cache, { cacheRoot = cacheRoot })
  end)

  local TmCaseExtract = require("src.import.gba.tm_case_extract")
  pcall(function()
    TmCaseExtract.run(rom, cache, { cacheRoot = cacheRoot })
  end)

  local BerryPouchExtract = require("src.import.gba.berry_pouch_extract")
  pcall(function()
    BerryPouchExtract.run(rom, cache, { cacheRoot = cacheRoot })
  end)

  require("src.import.gba.easy_chat_extract").run(rom, cache, { cacheRoot = cacheRoot })

  if progress then progress("trainers", 0, 1) end
  local TrainerExtract = require("src.import.gba.trainer_extract")
  local trainers = TrainerExtract.run(rom, cache, { cacheRoot = cacheRoot })
  if progress then progress("trainers", 1, 1) end

  if progress then progress("battle_ai", 0, 1) end
  local BattleAiExtract = require("src.import.gba.battle_ai_extract")
  local battleAi = BattleAiExtract.run(rom, cache, { cacheRoot = cacheRoot or default_cache_root() })
  if progress then progress("battle_ai", 1, 1) end

  return {
    root = root,
    numSpecies = num,
    picsWritten = picsWritten,
    names = names,
    types = types,
    stats = stats,
    abilities = abilities,
    abilityNames = abilityNames,
    moveNames = moveNames,
    learnsets = learnsets,
    eggMoves = eggMoves,
    evolutions = evolutions,
    battleMoves = battle and battle.pack,
    partyChrome = chrome,
    battleChrome = battleChrome,
    battleTransition = battleTransition,
    summaryChrome = summaryChrome,
    trainers = trainers,
    battleAi = battleAi,
  }
end

function PokemonExtract.ready(cache, cacheRoot)
  local baseRoot = cacheRoot or default_cache_root()
  local root = baseRoot .. "/" .. PokemonExtract.CACHE_SUB
  local last = (Versions.NUM_SPECIES or 412) - 1
  local iconBytes = (Versions.MON_ICON_W or 32) * (Versions.MON_ICON_H or 32) * 2 * 4
  local function valid_file(rel, minSize)
    minSize = minSize or 1
    if cache then
      if cache.read then
        local data = cache:read(rel)
        return (data and #data >= minSize) or false
      elseif cache.exists then
        return cache:exists(rel) or false
      end
      return false
    end
    local okC, CacheFs = pcall(require, "src.import.CacheFs")
    if okC and CacheFs and CacheFs.readActive then
      local data = CacheFs.readActive(rel)
      if data and #data >= minSize then return true end
    end
    if love and love.filesystem and love.filesystem.read then
      local ok, data = pcall(love.filesystem.read, rel)
      if ok and data and #data >= minSize then return true end
    end
    local f = io.open(rel, "rb")
    if f then
      local data = f:read(minSize)
      f:close()
      if data and #data >= minSize then return true end
    end
    return false
  end

  local function manifest_text()
    if cache then
      if cache.read then return cache:read(root .. "/manifest.lua") end
      return nil
    end
    local okC, CacheFs = pcall(require, "src.import.CacheFs")
    if okC and CacheFs and CacheFs.readActive then
      local data = CacheFs.readActive(root .. "/manifest.lua")
      if data then return data end
    end
    if love and love.filesystem and love.filesystem.read then
      local okL, data = pcall(love.filesystem.read, root .. "/manifest.lua")
      if okL and data then return data end
    end
    local f = io.open(root .. "/manifest.lua", "rb")
    if f then
      local data = f:read("*a")
      f:close()
      return data
    end
    return nil
  end

  local manifest = manifest_text()
  if type(manifest) == "string" then
    local format = tonumber(manifest:match("format%s*=%s*(%d+)"))
    if format ~= PokemonExtract.FORMAT_VERSION then return false end
    local count = tonumber(manifest:match("numSpecies%s*=%s*(%d+)"))
    if count and count < (Versions.NUM_SPECIES or 412) then return false end
  end

  if valid_file(root .. "/manifest.lua", 20)
      and valid_file(root .. "/names.lua", 20)
      and valid_file(root .. "/stats.lua", 20)
      and valid_file(root .. "/learnsets.lua", 20)
      and valid_file(root .. "/egg_moves.lua", 20)
      and valid_file(root .. "/move_names.lua", 20)
      and valid_file(root .. "/party/slot_main.rgba", 80 * 56 * 4)
      and valid_file(root .. "/summary/page_info.rgba", 240 * 160 * 4)
      and valid_file(root .. "/storage/manifest.lua", 20)
      and valid_file(baseRoot .. "/chrome/menu_message_rgba.rgba", 20)
      and valid_file(baseRoot .. "/trainer_card/bg.rgba", 240 * 160 * 4)
      and valid_file(baseRoot .. "/items/pack.lua", 20)
      and valid_file(baseRoot .. "/chrome/fonts/braille.lua", 20)
      and valid_file(baseRoot .. "/seagallop/manifest.lua", 20)
      and valid_file(baseRoot .. "/seagallop/wb.rgba", 32 * 8 * 32 * 8 * 4)
      and valid_file(root .. "/pokedex/paper_bg.rgba", 240 * 160 * 4)
      and valid_file(root .. "/pokedex/footprints/1.rgba", 16 * 16 * 4)
      and valid_file(root .. "/pokedex/footprints/question_mark.rgba", 16 * 16 * 4)
      and valid_file(root .. "/battle/terrain_cave.rgba", 256 * 256 * 4)
      and valid_file(root .. "/battle/terrain_water.rgba", 256 * 256 * 4)
      and valid_file(root .. "/battle/terrain_champion.rgba", 256 * 256 * 4)
      and valid_file(root .. "/front/1.rgba", 64 * 64 * 4)
      and valid_file(root .. "/back/1.rgba", 64 * 64 * 4)
      and valid_file(root .. "/icons/1.rgba", iconBytes)
      and valid_file(root .. "/front/" .. last .. ".rgba", 64 * 64 * 4)
      and valid_file(root .. "/back/" .. last .. ".rgba", 64 * 64 * 4)
      and valid_file(root .. "/icons/" .. last .. ".rgba", iconBytes) then
    return true
  end
  return false
end

return PokemonExtract
