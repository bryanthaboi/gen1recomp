-- Extract FRLG trainer tables + player back pics into data/generated/gba/trainers/.
-- Extracts: gTrainers metadata, AI behavior flags, 4-tier TrainerMon parties (with flat IV math),
-- and overworld trainer / boss dialogue strings.

local Versions = require("src.import.gba.versions")
local TextIR = require("src.core.game3.scripting.text_ir")
local Lz77 = require("src.import.gba.lz77")

local TrainerExtract = {}

TrainerExtract.FORMAT_VERSION = 5
TrainerExtract.CACHE_SUB = "trainers"

-- Party mon strides (ARM EABI sizes used by FRLG gTrainers parties).
local PARTY_STRIDE = {
  [0] = 8,  -- NoItemDefaultMoves
  [1] = 16, -- NoItemCustomMoves
  [2] = 8,  -- ItemDefaultMoves
  [3] = 16, -- ItemCustomMoves
}

local function gba_off(ptr)
  if type(ptr) ~= "number" then return nil end
  if ptr >= 0x08000000 and ptr < 0x0A000000 then
    return ptr - 0x08000000
  end
  return nil
end

local function decompose_ai_flags(flags)
  flags = tonumber(flags) or 0
  return {
    checkBadMove = (flags % 2 == 1),
    checkViability = (math.floor(flags / 2) % 2 == 1),
    tryToFaint = (math.floor(flags / 4) % 2 == 1),
    setupFirstTurn = (math.floor(flags / 8) % 2 == 1),
    risky = (math.floor(flags / 16) % 2 == 1),
    preferStrongestMove = (math.floor(flags / 32) % 2 == 1),
    preferBatonPass = (math.floor(flags / 64) % 2 == 1),
    doubleBattle = (math.floor(flags / 128) % 2 == 1),
    hpAware = (math.floor(flags / 256) % 2 == 1),
    roaming = (math.floor(flags / 0x20000000) % 2 == 1),
    safari = (math.floor(flags / 0x40000000) % 2 == 1),
    firstBattle = (flags >= 0x80000000),
  }
end

local function read_party(rom, partyFlags, partySize, partyPtr)
  partyFlags = (tonumber(partyFlags) or 0) % 4
  partySize = tonumber(partySize) or 0
  local partyOff = gba_off(partyPtr)
  if partySize < 1 or not partyOff then
    return {}, 1
  end

  local party = {}
  local pStride = PARTY_STRIDE[partyFlags] or 8
  local highestLevel = 1

  for p = 0, partySize - 1 do
    local mOff = partyOff + p * pStride
    if mOff + pStride > rom.size then break end

    local rawIvWord = rom:u16(mOff) or 0
    local rawIv = rawIvWord % 256
    -- The Flat IV Math Trap: (rawIv * 31) / 255 uniform across all 6 stats
    local iv = math.floor((rawIv * 31) / 255)
    local lvl = rom:get(mOff + 2) or 5
    if lvl > highestLevel then highestLevel = lvl end
    local species = rom:u16(mOff + 4) or 1

    local mon = {
      species = species,
      level = lvl,
      rawIv = rawIv,
      iv = iv,
      ivs = { hp = iv, atk = iv, def = iv, spa = iv, spd = iv, spe = iv },
      -- Trainer EVs are Zero across all stats
      evs = { hp = 0, atk = 0, def = 0, spa = 0, spd = 0, spe = 0 },
    }

    if partyFlags == 0 then
      -- NoItemDefaultMoves
    elseif partyFlags == 1 then
      -- NoItemCustomMoves
      local moves = {}
      for mi = 0, 3 do
        local mv = rom:u16(mOff + 6 + mi * 2) or 0
        if mv > 0 then moves[#moves + 1] = mv end
      end
      mon.moves = moves
    elseif partyFlags == 2 then
      -- ItemDefaultMoves
      local held = rom:u16(mOff + 6) or 0
      if held > 0 then mon.heldItem = held end
    elseif partyFlags == 3 then
      -- ItemCustomMoves
      local held = rom:u16(mOff + 6) or 0
      if held > 0 then mon.heldItem = held end
      local moves = {}
      for mi = 0, 3 do
        local mv = rom:u16(mOff + 8 + mi * 2) or 0
        if mv > 0 then moves[#moves + 1] = mv end
      end
      mon.moves = moves
    end

    party[#party + 1] = mon
  end

  return party, highestLevel
end

local function read_items(rom, off)
  local items = {}
  for i = 0, 3 do
    local it = rom:u16(off + 0x10 + i * 2) or 0
    items[i + 1] = it
  end
  return items
end

local function default_cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then
    return Extract.CACHE_ROOT
  end
  return "data/generated/gba"
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

local function decode_name(rom, off, length)
  length = length or 12
  local chars = {}
  local i = 0
  while i < length do
    local b = rom:get(off + i)
    if b == 0xFF then break end
    if b == 0x53 and i + 1 < length and rom:get(off + i + 1) == 0x54 then
      chars[#chars + 1] = "POKéMON"
      i = i + 2
    else
      local ch = TextIR.CHARMAP[b]
      if ch and ch ~= "" then
        chars[#chars + 1] = ch
      elseif b >= 0xBB and b <= 0xD4 then
        chars[#chars + 1] = string.char(string.byte("A") + (b - 0xBB))
      elseif b >= 0xD5 and b <= 0xEE then
        chars[#chars + 1] = string.char(string.byte("a") + (b - 0xD5))
      elseif b == 0x00 then
        chars[#chars + 1] = " "
      end
      i = i + 1
    end
  end
  return table.concat(chars):gsub("%s+$", "")
end

local function lua_quote(s)
  return string.format("%q", tostring(s or ""))
end

local function party_to_lua(party)
  if not party or #party == 0 then return "{}" end
  local parts = { "{\n" }
  for _, m in ipairs(party) do
    local movesStr = "nil"
    if m.moves and #m.moves > 0 then
      movesStr = "{" .. table.concat(m.moves, ",") .. "}"
    end
    parts[#parts + 1] = string.format(
      "        { species=%d, level=%d, rawIv=%d, iv=%d, heldItem=%s, moves=%s },\n",
      m.species or 1, m.level or 5, m.rawIv or 0, m.iv or 0,
      m.heldItem and tostring(m.heldItem) or "nil",
      movesStr)
  end
  parts[#parts + 1] = "      }"
  return table.concat(parts)
end

local function dialogs_to_lua(d)
  if not d then return "{}" end
  local parts = { "{\n" }
  if d.intro then parts[#parts + 1] = string.format("        intro = %s,\n", lua_quote(d.intro)) end
  if d.defeat then parts[#parts + 1] = string.format("        defeat = %s,\n", lua_quote(d.defeat)) end
  if d.victory then parts[#parts + 1] = string.format("        victory = %s,\n", lua_quote(d.victory)) end
  if d.notEnough then parts[#parts + 1] = string.format("        notEnough = %s,\n", lua_quote(d.notEnough)) end
  parts[#parts + 1] = "      }"
  return table.concat(parts)
end

local function pack_to_lua(pack)
  local lines = {
    "-- Auto-generated FRLG gTrainers with parties, AI flags, and dialogs.",
    "return {",
    string.format("  version = %d,", pack.version or 5),
    string.format("  trainerCount = %d,", pack.trainerCount or 0),
    string.format("  classCount = %d,", pack.classCount or 0),
    "  classNames = {",
  }
  for id = 0, (pack.classCount or 0) - 1 do
    lines[#lines + 1] = string.format("    [%d] = %s,", id, lua_quote(pack.classNames[id] or ""))
  end
  lines[#lines + 1] = "  },"
  lines[#lines + 1] = "  trainers = {"
  for id = 0, (pack.trainerCount or 0) - 1 do
    local t = pack.trainers[id]
    if t then
      lines[#lines + 1] = string.format("    [%d] = {", id)
      lines[#lines + 1] = string.format("      class = %d,", t.class or 0)
      lines[#lines + 1] = string.format("      className = %s,", lua_quote(t.className or ""))
      lines[#lines + 1] = string.format("      pic = %d,", t.pic or 0)
      lines[#lines + 1] = string.format("      name = %s,", lua_quote(t.name or ""))
      lines[#lines + 1] = string.format("      gender = %d,", t.gender or 0)
      lines[#lines + 1] = string.format("      doubleBattle = %s,", t.doubleBattle and "true" or "false")
      lines[#lines + 1] = string.format("      partySize = %d,", t.partySize or 0)
      lines[#lines + 1] = string.format("      partyFlags = %d,", t.partyFlags or 0)
      lines[#lines + 1] = string.format("      lastLevel = %d,", t.lastLevel or 1)
      lines[#lines + 1] = string.format("      aiFlags = %d,", t.aiFlags or 0)
      lines[#lines + 1] = string.format("      items = {%d,%d,%d,%d},",
        (t.items and t.items[1]) or 0, (t.items and t.items[2]) or 0,
        (t.items and t.items[3]) or 0, (t.items and t.items[4]) or 0)
      if t.scriptKey then
        lines[#lines + 1] = string.format("      scriptKey = %s,", lua_quote(t.scriptKey))
      end
      if t.introTextKey then
        lines[#lines + 1] = string.format("      introTextKey = %s,", lua_quote(t.introTextKey))
      end
      if t.defeatTextKey then
        lines[#lines + 1] = string.format("      defeatTextKey = %s,", lua_quote(t.defeatTextKey))
      end
      lines[#lines + 1] = "      party = " .. party_to_lua(t.party) .. ","
      lines[#lines + 1] = "      dialogs = " .. dialogs_to_lua(t.dialogs) .. ","
      lines[#lines + 1] = "    },"
    end
  end
  lines[#lines + 1] = "  },"
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

local function decode_sheet_rgba(tiles, palBytes, frames)
  frames = math.max(1, tonumber(frames) or 1)
  local pal = {}
  for c = 0, 15 do
    local lo = palBytes[c * 2 + 1] or 0
    local hi = palBytes[c * 2 + 2] or 0
    pal[c] = lo + hi * 256
  end
  local rgb = {}
  for c = 0, 15 do
    local r, g, b = bgr555_to_rgb8(pal[c] or 0)
    rgb[c] = { r, g, b }
  end
  local w, h = 64, 64 * frames
  local chunks = {}
  local ti = 0
  local tilesH = 8 * frames
  for ty = 0, tilesH - 1 do
    for tx = 0, 7 do
      local tileOff = ti * 32
      for row = 0, 7 do
        for bx = 0, 3 do
          local bi = tileOff + row * 4 + bx + 1
          local byte = tiles[bi] or 0
          local p0 = byte % 16
          local p1 = math.floor(byte / 16) % 16
          local x0 = tx * 8 + bx * 2
          local y0 = ty * 8 + row
          local function put(x, y, idx)
            local i = y * w + x + 1
            if idx == 0 then
              chunks[i] = string.char(0, 0, 0, 0)
            else
              local c = rgb[idx] or rgb[0]
              chunks[i] = string.char(c[1], c[2], c[3], 255)
            end
          end
          put(x0, y0, p0)
          put(x0 + 1, y0, p1)
        end
      end
      ti = ti + 1
    end
  end
  return table.concat(chunks), w, h
end

local function bake_back_pic(rom, gender)
  gender = tonumber(gender) or 0
  local picTable = Versions.TRAINER_BACK_PIC_TABLE or 0x239FA4
  local palTable = Versions.TRAINER_BACK_PIC_PAL_TABLE or 0x239FD4
  local sheetOff = picTable + gender * 8
  local palOff = palTable + gender * 8
  local function get(i) return rom:get(i) end
  local function u32(off)
    if rom.u32 then return rom:u32(off) end
    return rom:get(off)
      + rom:get(off + 1) * 256
      + rom:get(off + 2) * 65536
      + rom:get(off + 3) * 16777216
  end
  local tilePtr = u32(sheetOff)
  local palPtr = u32(palOff)
  local tileFile = Versions.gbaToFile(tilePtr)
  local palFile = Versions.gbaToFile(palPtr)
  if not tileFile or not palFile then return nil end
  local sizeLo = rom:get(sheetOff + 4) or 0
  local sizeHi = rom:get(sheetOff + 5) or 0
  local size = sizeLo + sizeHi * 256
  if size < 0x800 then size = 0x2800 end
  local frames = math.max(1, math.floor(size / 0x800))
  local tiles = {}
  for i = 0, size - 1 do
    tiles[i + 1] = rom:get(tileFile + i) or 0
  end
  local okP, palBytes = pcall(Lz77.decompress, get, palFile)
  if not okP or type(palBytes) ~= "table" then return nil end
  return decode_sheet_rgba(tiles, palBytes, frames)
end

local function bake_front_pic(rom, picId)
  picId = tonumber(picId)
  if not picId or picId < 0 then return nil end
  local picTable = Versions.TRAINER_FRONT_PIC_TABLE or 0x23957C
  local palTable = Versions.TRAINER_FRONT_PIC_PAL_TABLE or 0x239A1C
  local sheetOff = picTable + picId * 8
  local palOff = palTable + picId * 8
  local function get(i) return rom:get(i) end
  local function u32(off)
    if rom.u32 then return rom:u32(off) end
    return rom:get(off)
      + rom:get(off + 1) * 256
      + rom:get(off + 2) * 65536
      + rom:get(off + 3) * 16777216
  end
  local tilePtr = u32(sheetOff)
  local palPtr = u32(palOff)
  local tileFile = Versions.gbaToFile(tilePtr)
  local palFile = Versions.gbaToFile(palPtr)
  if not tileFile or not palFile then return nil end
  local sizeLo = rom:get(sheetOff + 4) or 0
  local sizeHi = rom:get(sheetOff + 5) or 0
  local size = sizeLo + sizeHi * 256
  local okT, tiles = pcall(Lz77.decompress, get, tileFile)
  if not okT or type(tiles) ~= "table" then return nil end
  if size >= 0x1000 and #tiles > 2048 then
    local trimmed = {}
    for i = 1, 2048 do trimmed[i] = tiles[i] end
    tiles = trimmed
  end
  local okP, palBytes = pcall(Lz77.decompress, get, palFile)
  if not okP or type(palBytes) ~= "table" then return nil end
  return decode_sheet_rgba(tiles, palBytes, 1)
end

--- Scan script bytecode to extract and cross-index dialogue per trainerId,
-- resolving The Boss Text Disconnect via backwards message/loadword search.
function TrainerExtract.extractDialogs(scripts, text)
  local dialogsByTrainer = {}
  if not scripts or not text then return dialogsByTrainer end

  for scriptKey, rows in pairs(scripts) do
    if type(rows) == "table" then
      for idx, row in ipairs(rows) do
        if row.op == "trainerbattle" or row.op == "dotrainerbattle" then
          local tid = tonumber(row.trainer or row[1])
          if tid and not dialogsByTrainer[tid] then
            local introKey = row.introText
            -- The Boss Text Disconnect fallback:
            if not introKey then
              for b = idx - 1, math.max(1, idx - 15), -1 do
                local prev = rows[b]
                local tk = prev.ptr or (prev.dest == 0 and prev.value) or (prev.op == "loadword" and prev.value)
                if tk and text[tk] then
                  introKey = tk
                  break
                end
              end
            end

            local defeatKey = row.defeatText
            local victoryKey = row.victoryText
            local notEnoughKey = row.notEnoughText

            local function resolveText(k)
              if not k or not text[k] then return nil end
              return TextIR.toPlain(text[k])
            end

            dialogsByTrainer[tid] = {
              scriptKey = scriptKey,
              battleType = row.type,
              introKey = introKey,
              intro = resolveText(introKey),
              defeatKey = defeatKey,
              defeat = resolveText(defeatKey),
              victoryKey = victoryKey,
              victory = resolveText(victoryKey),
              notEnoughKey = notEnoughKey,
              notEnough = resolveText(notEnoughKey),
            }
          end
        end
      end
    end
  end

  return dialogsByTrainer
end

function TrainerExtract.extract(rom, opts)
  opts = opts or {}
  local classBase = Versions.TRAINER_CLASS_NAMES or 0x23E558
  local classStride = Versions.TRAINER_CLASS_NAME_STRIDE or 13
  local classCount = Versions.TRAINER_CLASS_COUNT or 107
  local trainersBase = Versions.TRAINERS_TABLE or 0x23EAC8
  local stride = Versions.TRAINER_STRIDE or 0x28
  local trainerCount = Versions.TRAINERS_COUNT or 743

  local classNames = {}
  for id = 0, classCount - 1 do
    classNames[id] = decode_name(rom, classBase + id * classStride, classStride)
  end

  local dialogsByTrainer = {}
  if opts.scripts and opts.text then
    dialogsByTrainer = TrainerExtract.extractDialogs(opts.scripts, opts.text)
  end

  local trainers = {}
  for id = 0, trainerCount - 1 do
    local off = trainersBase + id * stride
    local partyFlags = rom:get(off) or 0
    local class = rom:get(off + 1) or 0
    local encGender = rom:get(off + 2) or 0
    local gender = (encGender >= 128) and 1 or 0
    local encounterMusic = encGender % 128
    local pic = rom:get(off + 3) or 0
    local name = decode_name(rom, off + 4, 12)
    local items = read_items(rom, off)
    local doubleBattle = (rom:get(off + 0x18) ~= 0)
    local aiFlags = rom:u32(off + 0x1C) or 0
    local partySize = rom:get(off + 0x20) or 0
    local partyPtr = rom:u32(off + 0x24)

    local party, lastLevel = read_party(rom, partyFlags, partySize, partyPtr)
    local d = dialogsByTrainer[id]

    trainers[id] = {
      class = class,
      className = classNames[class] or "",
      pic = pic,
      name = name,
      gender = gender,
      encounterMusic = encounterMusic,
      doubleBattle = doubleBattle,
      partySize = #party,
      partyFlags = partyFlags,
      lastLevel = lastLevel or 1,
      aiFlags = aiFlags,
      ai = decompose_ai_flags(aiFlags),
      items = items,
      party = party,
      dialogs = d and {
        intro = d.intro,
        defeat = d.defeat,
        victory = d.victory,
        notEnough = d.notEnough,
      } or {},
      scriptKey = d and d.scriptKey,
      introTextKey = d and d.introKey,
      defeatTextKey = d and d.defeatKey,
      victoryTextKey = d and d.victoryKey,
      notEnoughTextKey = d and d.notEnoughKey,
    }
  end

  return {
    version = TrainerExtract.FORMAT_VERSION,
    classCount = classCount,
    trainerCount = trainerCount,
    classNames = classNames,
    trainers = trainers,
  }
end

function TrainerExtract.run(rom, cache, opts)
  opts = opts or {}
  local cacheRoot = opts.cacheRoot or default_cache_root()
  local root = cacheRoot .. "/" .. TrainerExtract.CACHE_SUB

  -- If script/text tables exist in cache or opts, load them for dialog cross-indexing
  if not opts.scripts or not opts.text then
    local scriptsSub = cacheRoot .. "/scripts"
    local function loadLua(rel)
      local src = cache:read(rel)
      if not src then return nil end
      local chunk = load(src, "@" .. rel, "t", {})
      if not chunk then return nil end
      local ok, res = pcall(chunk)
      return ok and res or nil
    end
    opts.scripts = opts.scripts or loadLua(scriptsSub .. "/scripts.lua")
    opts.text = opts.text or loadLua(scriptsSub .. "/text.lua")
  end

  local pack = TrainerExtract.extract(rom, opts)
  cache:write(cacheRoot .. "/trainers.lua", pack_to_lua(pack))
  cache:write(root .. "/manifest.lua", string.format(
    "return { version = %d, trainerCount = %d, classCount = %d }\n",
    pack.version, pack.trainerCount, pack.classCount))

  for gender = 0, 1 do
    local rgba = bake_back_pic(rom, gender)
    if rgba then
      cache:write(root .. "/back_" .. gender .. ".rgba", rgba)
    end
  end

  local picCount = Versions.TRAINER_PIC_COUNT or 148
  local baked = 0
  for picId = 0, picCount - 1 do
    local rgba = bake_front_pic(rom, picId)
    if rgba then
      cache:write(root .. "/front/" .. picId .. ".rgba", rgba)
      baked = baked + 1
    end
  end

  return { pack = pack, root = root, frontPics = baked }
end

function TrainerExtract.ready(cache, cacheRoot)
  local root = (cacheRoot or default_cache_root())
  if cache and cache.exists and cache:exists(root .. "/trainers.lua") then
    return true
  end
  if cache and cache.read and cache:read(root .. "/trainers.lua") then
    return true
  end
  return false
end

return TrainerExtract
