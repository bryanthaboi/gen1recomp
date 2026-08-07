-- Standalone Gen-1 text decoder, output-compatible with the engine's
-- RomExtractor (src/import/RomExtractor.lua). The mod cannot require that
-- module -- it is engine-internal and only exists while an import runs --
-- so the small part of it the translation needs is mirrored here: the
-- text-command stream walker, the 0x50-terminated string reader, and the
-- glyph mapping with its overrides. Byte-for-byte output parity with the
-- extractor matters because every decoded line overrides a label the US
-- extraction already filled: same placeholders, same {_CONT}/{SCROLL}
-- macros, same directive arity, or the engine rejects the line at draw
-- time and falls back to English.
--
-- Everything here is pure Lua over a ROM byte string: no love.*, no engine
-- requires, so the whole module runs under the headless test loader.
--
-- Unlike the extractor, a bad read is a soft failure: decode returns
-- nil + reason for that label and the caller skips it, because one
-- corrupt label in a player's dump must not take the whole mod down.

local Decoder = {}

local BANK_SIZE = 0x4000

-- RomExtractor.TEXT_GLYPH_OVERRIDES, applied before the charmap so the
-- dialogue macros come out spelled the way the engine's renderer expects.
local GLYPH_OVERRIDES = {
  [0x4B] = "{_CONT}", [0x4C] = "{SCROLL}",
  [0x6D] = "{COLON}", [0xF0] = "¥",
}

local function offset(bank, address)
  if bank == 0 then
    if address < 0 or address >= BANK_SIZE then return nil end
    return address
  end
  if address < BANK_SIZE or address >= BANK_SIZE * 2 then return nil end
  return bank * BANK_SIZE + address - BANK_SIZE
end

local function byteAt(data, bank, address)
  local at = offset(bank, address)
  if not at or at + 1 > #data then return nil end
  return data:byte(at + 1)
end

-- RomExtractor:textGlyph -- overrides, then the charmap, then the <X> ->
-- {X} respelling; an unmapped byte keeps the {BYTE:XX} escape so parity
-- with the US extraction holds even for oddball bytes.
local function glyph(charmap, value)
  if GLYPH_OVERRIDES[value] then return GLYPH_OVERRIDES[value] end
  local mapped = charmap[value] or ("{BYTE:%02X}"):format(value)
  if mapped:sub(1, 1) == "<" and mapped:sub(-1) == ">" then
    return "{" .. mapped:sub(2, -2) .. "}"
  end
  return mapped
end
Decoder.glyph = glyph

-- RomExtractor:decodeTextCommands. `dynamic` is the manifest's
-- substitution list for this label: { {command, replacement}, ... }.
-- Returns the decoded string, or nil + reason.
function Decoder.text(data, bank, address, charmap, dynamic)
  dynamic = dynamic or {}
  local pending = 1
  local out = {}
  for _ = 1, 4096 do
    local command = byteAt(data, bank, address)
    if not command then return nil, "read past end of ROM" end
    address = address + 1
    if command == 0x50 then
      if pending <= #dynamic then return nil, "unused dynamic substitutions" end
      return table.concat(out)
    elseif command == 0 then
      while true do
        local value = byteAt(data, bank, address)
        if not value then return nil, "read past end of ROM" end
        address = address + 1
        if value == 0x50 then break end
        if value == 0x57 or value == 0x58 or value == 0x5F then
          if pending <= #dynamic then
            return nil, "unused dynamic substitutions"
          end
          return table.concat(out)
        end
        out[#out + 1] = glyph(charmap, value)
      end
    elseif command == 1 or command == 2 or command == 9 then
      local expected = dynamic[pending]
      if not expected then return nil, "missing dynamic substitution" end
      if command ~= expected[1] then
        return nil, ("dynamic command mismatch: $%02X vs $%02X")
          :format(command, expected[1])
      end
      out[#out + 1] = expected[2]
      pending = pending + 1
      address = address + (command == 1 and 2 or 3)
    else
      return nil, ("unsupported text command $%02X"):format(command)
    end
  end
  return nil, "text command stream is too long"
end

-- Rom:readString -- a 0x50-terminated string (name tables). Returns the
-- string and the bytes consumed, or nil + reason. No glyph overrides here,
-- mirroring the extractor's name path.
function Decoder.string(data, bank, address, charmap, maxLength)
  local out = {}
  for at = 0, (maxLength or 4096) - 1 do
    local value = byteAt(data, bank, address + at)
    if not value then return nil, "read past end of ROM" end
    if value == 0x50 then return table.concat(out), at + 1 end
    out[#out + 1] = charmap[value] or ("{BYTE:%02X}"):format(value)
  end
  return nil, "unterminated string"
end

-- Rom:decodeText over a fixed-width cell (the 10-byte species names).
function Decoder.fixed(data, bank, address, charmap, width)
  local out = {}
  for at = 0, width - 1 do
    local value = byteAt(data, bank, address + at)
    if not value then return nil, "read past end of ROM" end
    if value == 0x50 then break end
    out[#out + 1] = charmap[value] or ("{BYTE:%02X}"):format(value)
  end
  return table.concat(out)
end

local function wordAt(data, bank, address)
  local lo = byteAt(data, bank, address)
  local hi = byteAt(data, bank, address + 1)
  if not lo or not hi then return nil end
  return lo + hi * 0x100
end

-- The EUR Pokedex entry table: per dex number, a pointer to the entry
-- block -- kind string, then the metric layout the localizations use
-- (db decimeters, dw hectograms; see tools/build_rom_data.py).
local function decodeDex(data, spec, catalogs, stats)
  local table_ = spec.dex
  if not table_ then return end
  local out = {}
  for index, id in ipairs(table_.order) do
    local address = not (id:find("^MISSINGNO") or id:find("^UNUSED"))
      and wordAt(data, table_.bank, table_.address + (index - 1) * 2)
    if address then
      local kind, consumed = Decoder.string(
        data, table_.bank, address, spec.charmap, 32)
      if kind then
        local dm = byteAt(data, table_.bank, address + consumed)
        local hg = wordAt(data, table_.bank, address + consumed + 1)
        if dm and hg then
          out[id] = { kind = kind, heightM = dm / 10, weightKg = hg / 10 }
          stats.decoded = stats.decoded + 1
        end
      else
        stats.skipped[#stats.skipped + 1] = "dex." .. id .. ": " ..
          tostring(consumed)
      end
    end
  end
  catalogs.dex = out
end

-- Walk a whole spec against a ROM: every dialogue label plus the four name
-- tables. Returns catalogs shaped for main.lua's registration pass --
-- { dialogue = { label = text }, names = { moves = { id = name }, ... } }
-- -- and a stats table with per-section counts and the skipped labels.
function Decoder.catalogs(data, spec)
  local catalogs = { dialogue = {}, names = {} }
  local stats = { decoded = 0, skipped = {} }

  for label, place in pairs(spec.dialogue) do
    local text, reason = Decoder.text(
      data, place[1], place[2], spec.charmap, spec.dynamic[label])
    if text then
      catalogs.dialogue[label] = text
      stats.decoded = stats.decoded + 1
    else
      stats.skipped[#stats.skipped + 1] = label .. ": " .. reason
    end
  end

  for section, table_ in pairs(spec.names) do
    local out = {}
    local address = table_.address
    for index, id in ipairs(table_.order) do
      local name, consumed
      if table_.width then
        name = Decoder.fixed(
          data, table_.bank, address + (index - 1) * table_.width,
          spec.charmap, table_.width)
      else
        name, consumed = Decoder.string(
          data, table_.bank, address, spec.charmap, 32)
        if not name then
          stats.skipped[#stats.skipped + 1] =
            section .. "." .. id .. ": " .. tostring(consumed)
          break
        end
        address = address + consumed
      end
      -- MISSINGNO/UNUSED slots pad the species table; the extractor skips
      -- them and the registry has no such ids to patch anyway
      if name and not id:find("^MISSINGNO") and not id:find("^UNUSED") then
        out[id] = name
        stats.decoded = stats.decoded + 1
      end
    end
    catalogs.names[section] = out
  end

  decodeDex(data, spec, catalogs, stats)

  local types = {}
  for _, entry in ipairs(spec.types or {}) do
    local name = Decoder.string(data, entry.bank, entry.address,
      spec.charmap, 16)
    if name then
      types[entry.id] = name
      stats.decoded = stats.decoded + 1
    end
  end
  catalogs.types = types

  return catalogs, stats
end

return Decoder
