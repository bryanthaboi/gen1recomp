local bit = require("bit")
local band, bor, bxor, lshift, rshift = bit.band, bit.bor, bit.bxor, bit.lshift, bit.rshift
local ImagePack = require("src.save_convert.gen3_port.imagepack")

local function build(L)
  local Gen3Save = {}

  Gen3Save.MSG = {
    size = "A FireRed/LeafGreen save must be 128 KB (or 64 KB); this one is %d bytes.",
    notFrlg = "That is a Ruby/Sapphire/Emerald save, not FireRed/LeafGreen.",
    rs = "That is a Ruby/Sapphire save, not FireRed/LeafGreen.",
    emerald = "That is an Emerald save, not FireRed/LeafGreen.",
    japanese = "Japanese FireRed/LeafGreen saves can't be imported.",
    empty = "That save file is empty (no game was ever saved).",
    corrupt = "Both copies of the save in that file are damaged.",
    damagedTemplate = "Cannot export because the preserved cartridge image is damaged. Reimport the original cartridge save to restore it.",
    olderSlot = "The newest copy of that save was damaged, so the previous save was imported.",
  }
  if L.FAMILY == "emerald" then
    Gen3Save.MSG.size = "An Emerald save must be 128 KB; this one is %d bytes."
    Gen3Save.MSG.japanese = "Japanese Emerald saves can't be imported."
    Gen3Save.MSG.notFrlg = nil
    Gen3Save.MSG.frlg = "That is a FireRed/LeafGreen save, not Emerald."
    Gen3Save.MSG.rs = "That is a Ruby/Sapphire save, not Emerald."
  end
  if L.FAMILY == "rs" then
    Gen3Save.MSG.size = "A Ruby/Sapphire save must be 128 KB; this one is %d bytes."
    Gen3Save.MSG.japanese = "Japanese Ruby/Sapphire saves can't be imported."
    Gen3Save.MSG.notFrlg, Gen3Save.MSG.rs = nil, nil
    Gen3Save.MSG.frlg = "That is a FireRed/LeafGreen save, not Ruby/Sapphire."
    Gen3Save.MSG.emerald = "That is an Emerald save, not Ruby/Sapphire."
  end
  Gen3Save.L = L
  local BOX_FLAGS_OFFSET = L.FAMILY == "rs" and 0x312F or L.FAMILY == "emerald" and 0x31C7 or 0x30BB
  Gen3Save.BOX_FLAGS_OFFSET = BOX_FLAGS_OFFSET

  function Gen3Save.boxFlagsOf(save)
    return require("src.core.game3.save_mon").boxFlags(save)
  end

  local U32 = 4294967296

  local function u8(s, o) return s:byte(o + 1) end
  local function u16(s, o) local a, b = s:byte(o + 1, o + 2); return a + b * 256 end
  local function u32(s, o) local a, b, c, d = s:byte(o + 1, o + 4); return a + b * 256 + c * 65536 + d * 16777216 end
  local function s8(s, o) local v = u8(s, o); return v >= 128 and v - 256 or v end
  local function s16(s, o) local v = u16(s, o); return v >= 32768 and v - 65536 or v end
  local function tou32(x) return x % U32 end
  local function bits(v, shift, width) return band(rshift(v, shift), lshift(1, width) - 1) end

  Gen3Save.u8, Gen3Save.u16, Gen3Save.u32 = u8, u16, u32

  local CHARMAP
  local REVERSE
  local EXTRA
  local EXTRA_REVERSE
  -- charmap.txt:837
  local EXTRA_PREFIX = 0xF9

  local function charmap()
    if not CHARMAP then
      local TextIR = require("src.core.game3.scripting.text_ir")
      CHARMAP, EXTRA = {}, TextIR.EXTRA_SYMBOL or {}
      for code, ch in pairs(TextIR.CHARMAP) do CHARMAP[code] = ch end
      for code, ch in pairs(L.CHARMAP_LATIN or {}) do
        if CHARMAP[code] == nil then CHARMAP[code] = ch end
      end
    end
    return CHARMAP
  end

  local function reverse()
    if REVERSE then return REVERSE end
    REVERSE, EXTRA_REVERSE = {}, {}
    for code, ch in pairs(charmap()) do
      if REVERSE[ch] == nil or code < REVERSE[ch] then REVERSE[ch] = code end
    end
    for code, ch in pairs(EXTRA) do
      if EXTRA_REVERSE[ch] == nil or code < EXTRA_REVERSE[ch] then EXTRA_REVERSE[ch] = code end
    end
    return REVERSE
  end

  local JAPANESE, JAPANESE_REVERSE
  local function japanese()
    if not JAPANESE then
      JAPANESE, JAPANESE_REVERSE = {}, {}
      for ch, code in pairs(require("src.ui.game3.frlg_font").JAPANESE_GLYPHS) do
        if JAPANESE[code] == nil or ch < JAPANESE[code] then JAPANESE[code] = ch end
        JAPANESE_REVERSE[ch] = code
      end
    end
    return JAPANESE, JAPANESE_REVERSE
  end

  local function latin(c, kana) return c == 0x00 or c >= 0xA1 and c <= 0xAA or c >= 0xB1 or not kana and c >= 0xAB end

  function Gen3Save.decodeString(s, off, len, language, fullwidth)
    local map, out = charmap(), {}
    local jp = language == L.LANGUAGE_JAPANESE and japanese() or nil
    local kana = false
    if jp then
      for k = 0, len - 1 do
        local c = u8(s, off + k)
        if c == 0xFF then break end
        if c >= 0x01 and c <= 0xA0 then kana = true; break end
      end
    end
    local i = 0
    while i < len do
      local c = u8(s, off + i)
      if c == 0xFF then break end
      local sym = c == EXTRA_PREFIX and i + 1 < len and EXTRA[u8(s, off + i + 1)]
      if sym then
        out[#out + 1] = sym
        i = i + 2
      else
        out[#out + 1] = jp and (fullwidth or not latin(c, kana) or not map[c]) and jp[c] or map[c] or string.format("{%02X}", c)
        i = i + 1
      end
    end
    return table.concat(out)
  end

  function Gen3Save.encodeString(str, len, pad, language)
    local r, out, i = reverse(), {}, 1
    local jr = language == L.LANGUAGE_JAPANESE and select(2, japanese()) or nil
    str = str or ""
    local function put(tok)
      local code = jr and jr[tok] or r[tok]
      if code then
        out[#out + 1] = code
      elseif EXTRA_REVERSE[tok] and #out + 2 <= len then
        out[#out + 1] = EXTRA_PREFIX
        out[#out + 1] = EXTRA_REVERSE[tok]
      else
        out[#out + 1] = r["?"]
      end
    end
    while i <= #str and #out < len do
      local hex = str:match("^{(%x%x)}", i)
      local tag = not hex and str:match("^{[%u%d_]+}", i)
      if hex then
        out[#out + 1] = tonumber(hex, 16)
        i = i + 4
      elseif tag then
        put(tag)
        i = i + #tag
      else
        local c = str:byte(i)
        local n = c < 0x80 and 1 or c < 0xE0 and 2 or c < 0xF0 and 3 or 4
        put(str:sub(i, i + n - 1))
        i = i + n
      end
    end
    if #out < len then out[#out + 1] = 0xFF end
    while #out < len do out[#out + 1] = pad or 0 end
    local t = {}
    for k = 1, len do t[k] = string.char(out[k]) end
    return table.concat(t)
  end

  local function rawName(x, key)
    return type(x) == "table" and type(x[key]) == "table" and string.char(unpack(x[key])) or nil
  end

  local function eggOf(mon)
    if mon.isEgg == true or mon.isEggFlag == true then return true end
    local flags = type(mon.cartExtra) == "table" and tonumber(mon.cartExtra.flagsRaw) or nil
    return flags ~= nil and band(flags, lshift(1, L.BOX_MON_FLAGS.isEgg)) ~= 0
  end

  function Gen3Save.repairJapaneseNames(mon)
    if type(mon) ~= "table" or tonumber(mon.language) ~= L.LANGUAGE_JAPANESE then return false end
    local B, changed = L.BOX_MON, false
    if eggOf(mon) then
      local current = mon.otName
      if type(current) ~= "string" or not current:find("[\128-\255]") then return false end
      local len = B.otNameLength
      local bytes = rawName(mon.cartExtra, "otNameRaw")
      if not bytes or Gen3Save.decodeString(bytes, 0, len, L.LANGUAGE_JAPANESE, true) ~= current then
        bytes = Gen3Save.encodeString(current, len, 0xFF, L.LANGUAGE_JAPANESE)
        if Gen3Save.decodeString(bytes, 0, len, L.LANGUAGE_JAPANESE, true) ~= current then return false end
      end
      local fixed = Gen3Save.decodeString(bytes, 0, len)
      if fixed == current or fixed:find("{%x%x}") then return false end
      for _, k in ipairs({ "otName", "ot" }) do
        if mon[k] == current then mon[k] = fixed end
      end
      return true
    end
    local function fix(keys, rawKey, len)
      local current = mon[keys[1]]
      if type(current) ~= "string" or current == "" then return end
      local bytes = rawName(mon.cartExtra, rawKey)
      if not bytes or Gen3Save.decodeString(bytes, 0, len) ~= current then
        if not current:find("{%x%x}") then return end
        bytes = Gen3Save.encodeString(current, len, 0xFF)
        if Gen3Save.decodeString(bytes, 0, len) ~= current then return end
      end
      local fixed = Gen3Save.decodeString(bytes, 0, len, L.LANGUAGE_JAPANESE)
      if fixed == current then return end
      for _, k in ipairs(keys) do
        if mon[k] == current then mon[k] = fixed end
      end
      changed = true
    end
    if not mon.isEgg then fix({ "nickname", "name" }, "nicknameRaw", B.nicknameLength) end
    fix({ "otName", "ot" }, "otNameRaw", B.otNameLength)
    return changed
  end

  -- src/save.c:614
  function Gen3Save.checksum(s, off, size)
    local sum = 0
    for o = off, off + size - 4, 4 do sum = (sum + u32(s, o)) % U32 end
    return (math.floor(sum / 65536) + sum) % 65536
  end

  local function readValue(s, off, kind, n)
    if kind == "u8" then return u8(s, off) end
    if kind == "u16" then return u16(s, off) end
    if kind == "u32" then return u32(s, off) end
    if kind == "s8" then return s8(s, off) end
    if kind == "s16" then return s16(s, off) end
    if kind == "str" or kind == "strFF" then return Gen3Save.decodeString(s, off, n) end
    if kind == "warp" then
      local w = {}
      for k, spec in pairs(L.WARP) do w[k] = readValue(s, off + spec[1], spec[2]) end
      return w
    end
    if kind == "bits" then
      local list = {}
      for i = 0, n * 8 - 1 do
        if band(u8(s, off + math.floor(i / 8)), lshift(1, i % 8)) ~= 0 then list[#list + 1] = i end
      end
      return list
    end
    error("unknown field kind " .. tostring(kind))
  end

  local function applyKey(v, xor, key)
    if xor == "key32" then return tou32(bxor(v, key)) end
    if xor == "key16" then return bxor(v, key % 65536) % 65536 end
    return v
  end

  function Gen3Save.readFields(s, fields, out, key)
    out = out or {}
    for _, f in ipairs(fields) do
      local v = readValue(s, f[2], f[3], f[4])
      if f[5] then v = applyKey(v, f[5], key) end
      out[f[1]] = v
    end
    return out
  end

  function Gen3Save.normalizeSize(bytes)
    local n = #bytes
    if n >= L.FLASH_SIZE and n <= L.FLASH_SIZE + L.MAX_TRAILER then
      return bytes:sub(1, L.FLASH_SIZE), 2, bytes:sub(L.FLASH_SIZE + 1)
    end
    if n >= L.HALF_FLASH_SIZE and n <= L.HALF_FLASH_SIZE + L.MAX_TRAILER then
      return bytes:sub(1, L.HALF_FLASH_SIZE), 1, ""
    end
    return nil
  end

  -- src/save.c:466
  local function scanSlot(s, slot)
    local found, counter, sig = {}, nil, false
    for i = 0, L.SECTORS_PER_SLOT - 1 do
      local base = (slot * L.SECTORS_PER_SLOT + i) * L.SECTOR_SIZE
      if u32(s, base + L.FOOTER.signature) == L.SIGNATURE then
        sig = true
        local id = u16(s, base + L.FOOTER.id)
        local size = L.CHUNK_SIZES[id]
        if size and u16(s, base + L.FOOTER.checksum) == Gen3Save.checksum(s, base, size) then
          found[id] = base
          counter = u32(s, base + L.FOOTER.counter)
        end
      end
    end
    if not sig then return { status = "empty" } end
    for id = 0, L.SECTORS_PER_SLOT - 1 do
      if not found[id] then return { status = "error" } end
    end
    return { status = "ok", counter = counter, base = found, slot = slot }
  end

  -- src/save.c:536
  function Gen3Save.pickSlot(s, slots)
    local a = scanSlot(s, 0)
    local b = slots >= 2 and scanSlot(s, 1) or { status = "empty" }
    local counter, older
    if a.status == "ok" and b.status == "ok" then
      local c1, c2 = a.counter, b.counter
      if (c1 == U32 - 1 and c2 == 0) or (c1 == 0 and c2 == U32 - 1) then
        counter = ((c1 + 1) % U32 < (c2 + 1) % U32) and c2 or c1
      else
        counter = (c1 < c2) and c2 or c1
      end
      older = false
    elseif a.status == "ok" then
      counter, older = a.counter, b.status == "error"
    elseif b.status == "ok" then
      counter, older = b.counter, a.status == "error"
    end
    if counter then
      if slots < 2 then return a, older end
      -- src/save.c:444
      local chosen = (counter % L.NUM_SLOTS == 0) and a or b
      if chosen.status ~= "ok" then return nil, "corrupt" end
      return chosen, older
    end
    if a.status == "empty" and b.status == "empty" then return nil, "empty" end
    return nil, "corrupt"
  end

  function Gen3Save.readBlocks(bytes)
    if type(bytes) ~= "string" then return nil, "size" end
    local s, slots, trailer = Gen3Save.normalizeSize(bytes)
    if not s then return nil, "size" end
    local slot, extra = Gen3Save.pickSlot(s, slots)
    if not slot then return nil, extra end
    local out = { counter = slot.counter, slot = slot.slot, olderSlot = extra == true, image = s, trailer = trailer }
    for _, blk in ipairs(L.BLOCKS) do
      local parts = {}
      for id = blk.first, blk.last do
        parts[#parts + 1] = s:sub(slot.base[id] + 1, slot.base[id] + L.CHUNK_SIZES[id])
      end
      out[blk.key] = table.concat(parts):sub(1, blk.size)
    end
    return out
  end

  -- src/pokemon.c:2807
  local function decryptSecure(raw, personality, otId)
    local key = bxor(personality, otId)
    local words = {}
    for i = 0, L.BOX_MON.secureWords - 1 do
      local w = tou32(bxor(u32(raw, L.BOX_MON.secure + i * 4), key))
      words[#words + 1] = string.char(w % 256, rshift(w, 8) % 256, rshift(w, 16) % 256, rshift(w, 24) % 256)
    end
    return table.concat(words)
  end

  -- src/pokemon.c:2069
  local function secureChecksum(sec)
    local sum = 0
    for i = 0, L.BOX_MON.secureWords * 2 - 1 do sum = (sum + u16(sec, i * 2)) % 65536 end
    return sum
  end

  local function isBlank(raw)
    for i = 1, #raw do if raw:byte(i) ~= 0 then return false end end
    return true
  end

  function Gen3Save.decodeBoxMon(raw)
    if isBlank(raw) then return nil end
    local B = L.BOX_MON
    local personality, otId = u32(raw, B.personality), u32(raw, B.otId)
    local flags = u8(raw, B.flags)
    local language = u8(raw, B.language)
    local sec = decryptSecure(raw, personality, otId)
    local pos = L.SUBSTRUCT_ORDER[personality % 24]
    local g, a, e, m = pos[1] * L.SUBSTRUCT_SIZE, pos[2] * L.SUBSTRUCT_SIZE, pos[3] * L.SUBSTRUCT_SIZE, pos[4] * L.SUBSTRUCT_SIZE
    local mon = {
      personality = personality,
      otIdRaw = otId,
      otId = otId % 65536,
      otSecretId = math.floor(otId / 65536),
      nickname = Gen3Save.decodeString(raw, B.nickname, B.nicknameLength, language),
      language = language,
      flagsRaw = flags,
      isBadEgg = band(flags, lshift(1, L.BOX_MON_FLAGS.isBadEgg)) ~= 0,
      hasSpecies = band(flags, lshift(1, L.BOX_MON_FLAGS.hasSpecies)) ~= 0,
      isEggFlag = band(flags, lshift(1, L.BOX_MON_FLAGS.isEgg)) ~= 0,
      markings = u8(raw, B.markings),
      checksum = u16(raw, B.checksum),
      unknown = u16(raw, B.unknown),
    }
    if mon.isEggFlag then mon.nicknameBytes = raw:sub(B.nickname + 1, B.nickname + B.nicknameLength) end
    if L.KEEP_RAW_NAMES then
      mon.nicknameRaw = raw:sub(B.nickname + 1, B.nickname + B.nicknameLength)
      mon.otNameRaw = raw:sub(B.otName + 1, B.otName + B.otNameLength)
    end
    mon.checksumOk = secureChecksum(sec) == mon.checksum
    for _, f in ipairs(L.SUBSTRUCT0) do mon[f[1]] = readValue(sec, g + f[2], f[3]) end
    mon.moves, mon.pp = {}, {}
    for i = 0, 3 do
      mon.moves[i + 1] = u16(sec, a + L.SUBSTRUCT1.moves + i * 2)
      mon.pp[i + 1] = u8(sec, a + L.SUBSTRUCT1.pp + i)
    end
    mon.evs, mon.contest = {}, {}
    for i, k in ipairs(L.EV_KEYS) do mon.evs[k] = u8(sec, e + i - 1) end
    for i, k in ipairs(L.CONTEST_KEYS) do mon.contest[k] = u8(sec, e + 6 + i - 1) end
    local S3 = L.SUBSTRUCT3
    mon.pokerus = u8(sec, m + S3.pokerus)
    mon.metLocation = u8(sec, m + S3.metLocation)
    local origins = u16(sec, m + S3.origins)
    for _, f in ipairs(L.ORIGINS_BITS) do mon[f[1]] = bits(origins, f[2], f[3]) end
    local ivw = u32(sec, m + S3.ivWord)
    mon.ivs = {}
    for i, k in ipairs(L.IV_KEYS) do mon.ivs[k] = bits(ivw, (i - 1) * 5, 5) end
    mon.isEgg = bits(ivw, L.IV_EGG_BIT, 1) == 1
    -- pokeemerald/src/daycare.c:866
    mon.otName = Gen3Save.decodeString(raw, B.otName, B.otNameLength,
      not (mon.isEgg or mon.isEggFlag) and language or nil)
    mon.abilityNum = bits(ivw, L.IV_ABILITY_BIT, 1)
    local rib = u32(sec, m + S3.ribbons)
    mon.ribbons = rib
    mon.championRibbon = bits(rib, L.RIBBON_CHAMPION_BIT, 1) == 1
    mon.modernFatefulEncounter = bits(rib, L.RIBBON_FATEFUL_BIT, 1) == 1
    -- src/pokemon.c:2994
    if not mon.checksumOk then
      mon.isBadEgg, mon.isEggFlag, mon.isEgg = true, true, true
      mon.raw = raw
    end
    return mon
  end

  function Gen3Save.decodePartyMon(raw)
    local mon = Gen3Save.decodeBoxMon(raw:sub(1, L.BOX_MON_SIZE))
    if not mon then return nil end
    if mon.raw then mon.raw = raw end
    for _, f in ipairs(L.PARTY_EXTRA) do mon[f[1]] = readValue(raw, f[2], f[3]) end
    return mon
  end

  local Buf = {}
  Buf.__index = Buf

  function Gen3Save.newBuf(n, template)
    local b = setmetatable({ n = n, b = {} }, Buf)
    if template then
      for i = 1, math.min(n, #template) do b.b[i - 1] = template:byte(i) end
    end
    return b
  end
  local newBuf = Gen3Save.newBuf

  function Buf:w8(o, v) self.b[o] = v % 256 end
  function Buf:w16(o, v) v = v % 65536; self.b[o] = v % 256; self.b[o + 1] = math.floor(v / 256) end
  function Buf:w32(o, v)
    v = v % U32
    for i = 0, 3 do self.b[o + i] = math.floor(v / 256 ^ i) % 256 end
  end
  function Buf:bytes(o, s) for i = 1, #s do self.b[o + i - 1] = s:byte(i) end end
  function Buf:fill(o, n, v) for i = 0, n - 1 do self.b[o + i] = v end end
  function Buf:str()
    local t = {}
    for i = 0, self.n - 1 do t[#t + 1] = string.char(self.b[i] or 0) end
    return table.concat(t)
  end

  local function writeValue(buf, off, kind, n, v)
    if kind == "u8" or kind == "s8" then return buf:w8(off, v or 0) end
    if kind == "u16" or kind == "s16" then return buf:w16(off, v or 0) end
    if kind == "u32" then return buf:w32(off, v or 0) end
    if kind == "str" then return buf:bytes(off, Gen3Save.encodeString(v, n)) end
    if kind == "strFF" then return buf:bytes(off, Gen3Save.encodeString(v, n, 0xFF)) end
    if kind == "warp" then
      local w = v or L.EMPTY_WARP
      for k, spec in pairs(L.WARP) do writeValue(buf, off + spec[1], spec[2], nil, w[k] or -1) end
      return
    end
    if kind == "bits" then
      buf:fill(off, n, 0)
      for _, i in ipairs(v or {}) do
        local o = off + math.floor(i / 8)
        buf.b[o] = bor(buf.b[o] or 0, lshift(1, i % 8))
      end
      return
    end
    error("unknown field kind " .. tostring(kind))
  end

  function Gen3Save.writeFields(buf, fields, t, key)
    for _, f in ipairs(fields) do
      local v = t[f[1]]
      if f[5] then v = applyKey(v or 0, f[5], key) end
      writeValue(buf, f[2], f[3], f[4], v)
    end
  end

  -- src/pokemon.c:2797
  function Gen3Save.encodeBoxMon(mon)
    if type(mon.raw) == "string" and #mon.raw >= L.BOX_MON_SIZE then return mon.raw:sub(1, L.BOX_MON_SIZE) end
    local B = L.BOX_MON
    local sec = newBuf(L.BOX_MON.secureWords * 4)
    local pos = L.SUBSTRUCT_ORDER[mon.personality % 24]
    local g, a, e, m = pos[1] * L.SUBSTRUCT_SIZE, pos[2] * L.SUBSTRUCT_SIZE, pos[3] * L.SUBSTRUCT_SIZE, pos[4] * L.SUBSTRUCT_SIZE
    for _, f in ipairs(L.SUBSTRUCT0) do writeValue(sec, g + f[2], f[3], nil, mon[f[1]] or 0) end
    for i = 1, 4 do
      sec:w16(a + L.SUBSTRUCT1.moves + (i - 1) * 2, (mon.moves or {})[i] or 0)
      sec:w8(a + L.SUBSTRUCT1.pp + i - 1, (mon.pp or {})[i] or 0)
    end
    local ev, c = mon.evs or {}, mon.contest or {}
    for i, k in ipairs(L.EV_KEYS) do sec:w8(e + i - 1, ev[k] or 0) end
    for i, k in ipairs(L.CONTEST_KEYS) do sec:w8(e + 6 + i - 1, c[k] or 0) end
    local S3 = L.SUBSTRUCT3
    sec:w8(m + S3.pokerus, mon.pokerus or 0)
    sec:w8(m + S3.metLocation, mon.metLocation or 0)
    local origins = 0
    for _, f in ipairs(L.ORIGINS_BITS) do origins = origins + ((mon[f[1]] or 0) % 2 ^ f[3]) * 2 ^ f[2] end
    sec:w16(m + S3.origins, origins)
    local iv, ivw = mon.ivs or {}, 0
    for i, k in ipairs(L.IV_KEYS) do ivw = ivw + ((iv[k] or 0) % 32) * 2 ^ ((i - 1) * 5) end
    if mon.isEgg then ivw = ivw + 2 ^ L.IV_EGG_BIT end
    if mon.abilityNum == 1 then ivw = ivw + 2 ^ L.IV_ABILITY_BIT end
    sec:w32(m + S3.ivWord, ivw)
    sec:w32(m + S3.ribbons, mon.ribbons or 0)
    local plain = sec:str()
    local out = newBuf(L.BOX_MON_SIZE)
    local otIdRaw = mon.otIdRaw or ((mon.otId or 0) + (mon.otSecretId or 0) * 65536)
    out:w32(B.personality, mon.personality)
    out:w32(B.otId, otIdRaw)
    if mon.nicknameBytes then
      out:fill(B.nickname, B.nicknameLength, 0xFF)
      out:bytes(B.nickname, mon.nicknameBytes:sub(1, B.nicknameLength))
    elseif mon.nicknameRaw and Gen3Save.decodeString(mon.nicknameRaw, 0, B.nicknameLength, mon.language) == mon.nickname then
      out:bytes(B.nickname, mon.nicknameRaw)
    else
      out:bytes(B.nickname, Gen3Save.encodeString(mon.nickname, B.nicknameLength, 0xFF, mon.language))
    end
    out:w8(B.language, mon.language or 2)
    local F = L.BOX_MON_FLAGS
    local flags = band(mon.flagsRaw or 0, 0xF8)
      + (mon.isBadEgg and 2 ^ F.isBadEgg or 0) + 2 ^ F.hasSpecies
      + ((mon.isEggFlag or mon.isEgg) and 2 ^ F.isEgg or 0)
    out:w8(B.flags, flags)
    local otLanguage = not (mon.isEggFlag or mon.isEgg) and mon.language or nil
    if mon.otNameRaw and Gen3Save.decodeString(mon.otNameRaw, 0, B.otNameLength, otLanguage) == mon.otName then
      out:bytes(B.otName, mon.otNameRaw)
    else
      local bytes = Gen3Save.encodeString(mon.otName, B.otNameLength, 0xFF, otLanguage)
      if not otLanguage and Gen3Save.decodeString(bytes, 0, B.otNameLength) ~= mon.otName then
        local jp = Gen3Save.encodeString(mon.otName, B.otNameLength, 0xFF, L.LANGUAGE_JAPANESE)
        if Gen3Save.decodeString(jp, 0, B.otNameLength, L.LANGUAGE_JAPANESE, true) == mon.otName then bytes = jp end
      end
      out:bytes(B.otName, bytes)
    end
    out:w8(B.markings, mon.markings or 0)
    out:w16(B.checksum, secureChecksum(plain))
    out:w16(B.unknown, mon.unknown or 0)
    local key = bxor(mon.personality, otIdRaw)
    for i = 0, B.secureWords - 1 do out:w32(B.secure + i * 4, tou32(bxor(u32(plain, i * 4), key))) end
    return out:str()
  end

  function Gen3Save.encodePartyMon(mon)
    if type(mon.raw) == "string" and #mon.raw >= L.PARTY_MON_SIZE then return mon.raw:sub(1, L.PARTY_MON_SIZE) end
    local b = newBuf(L.PARTY_MON_SIZE)
    b:bytes(0, Gen3Save.encodeBoxMon(mon))
    for _, f in ipairs(L.PARTY_EXTRA) do writeValue(b, f[2], f[3], nil, mon[f[1]] or (f[1] == "mail" and 0xFF or 0)) end
    return b:str()
  end

  local function readItems(s, off, count, key)
    local out = {}
    for i = 0, count - 1 do
      local id = u16(s, off + i * L.ITEM_SLOT_SIZE)
      local q = u16(s, off + i * L.ITEM_SLOT_SIZE + 2)
      if key then q = bxor(q, key % 65536) % 65536 end
      if id ~= 0 then out[#out + 1] = { id = id, qty = q } end
    end
    return out
  end

  local function writeItems(buf, off, count, list, key)
    for i = 1, count do
      local it = (list or {})[i]
      local o = off + (i - 1) * L.ITEM_SLOT_SIZE
      local qty = it and it.qty or 0
      buf:w16(o, it and it.id or 0)
      buf:w16(o + 2, key and bxor(qty, key % 65536) % 65536 or qty)
    end
  end

  local function isMailItem(id)
    return id >= L.MAIL_ITEM_FIRST and id <= L.MAIL_ITEM_LAST
  end

  local function decodeMail(s, off)
    local M = L.MAIL
    local rec = { words = {} }
    for i = 1, M.wordCount do rec.words[i] = u16(s, off + M.words + (i - 1) * 2) end
    rec.playerName = Gen3Save.decodeString(s, off + M.playerName, M.playerNameLength):gsub(" +$", "")
    rec.trainerIdRaw = u32(s, off + M.trainerId)
    rec.trainerId = rec.trainerIdRaw % 65536
    rec.species = u16(s, off + M.species)
    rec.itemId = u16(s, off + M.itemId)
    if L.FAMILY == "rs" then
      rec._rsNativeBytes = {}
      for i = 1, M.size do rec._rsNativeBytes[i] = s:byte(off + i) end
    end
    return rec
  end

  -- src/mail_data.c:18
  local function writeMail(buf, off, rec)
    local M = L.MAIL
    rec = type(rec) == "table" and rec or {}
    local item = tonumber(rec.itemId) or 0
    local words = type(rec.words) == "table" and rec.words or {}
    if L.FAMILY == "rs" then
      local raw = type(rec._rsNativeBytes) == "table" and rec._rsNativeBytes
      if raw and #raw == M.size then
        for i = 1, M.size do buf:w8(off + i - 1, raw[i]) end
      end
      for i = 1, M.wordCount do buf:w16(off + M.words + (i - 1) * 2, tonumber(words[i]) or L.EC_WORD_UNDEFINED) end
      local name = tostring(rec.playerName or "")
      local original
      if raw and #raw == M.size then
        local bytes = {}; for i = 1, M.size do bytes[i] = string.char(raw[i]) end
        original = Gen3Save.decodeString(table.concat(bytes), M.playerName, M.playerNameLength):gsub(" +$", "")
      end
      if rec._rsNewMail or original ~= name then
        local n = 0; for _ in name:gmatch("[^\128-\191]") do n = n + 1 end
        if item ~= 0 or rec._rsNewMail then
          if n < L.MAIL_NAME_PAD then name = name .. string.rep(" ", L.MAIL_NAME_PAD - n) end
          buf:bytes(off + M.playerName, Gen3Save.encodeString(name, M.playerNameLength - 1, 0xFF))
        elseif raw then
          buf:bytes(off + M.playerName, Gen3Save.encodeString(name, M.playerNameLength - 1, 0xFF))
        else buf:fill(off + M.playerName, M.playerNameLength, 0xFF) end
      end
      buf:w32(off + M.trainerId, tonumber(rec.trainerIdRaw) or tonumber(rec.trainerId) or 0)
      buf:w16(off + M.species, tonumber(rec.species) or L.MAIL_CLEAR_SPECIES)
      buf:w16(off + M.itemId, item)
      return
    end
    if L.FAMILY == "emerald" and type(rec._recordMixNativeBytes) == "table" then
      local cross = require("src.core.game3.link.rs_record_cross_bytes")
      if cross.raw(rec._recordMixNativeBytes, M.size) then
        buf:bytes(off, cross.renderMessage(Gen3Save, rec))
        if item == 0 then buf:fill(off + M.playerName, M.playerNameLength, 0xFF) end
        return
      end
    end
    for i = 1, M.wordCount do buf:w16(off + M.words + (i - 1) * 2, tonumber(words[i]) or L.EC_WORD_UNDEFINED) end
    buf:fill(off + M.playerName, M.playerNameLength, 0xFF)
    if item ~= 0 then
      local name = rec.playerName or ""
      local n = 0
      for _ in tostring(name):gmatch("[^\128-\191]") do n = n + 1 end
      -- src/mail_data.c:58
      if n < L.MAIL_NAME_PAD then name = name .. string.rep(" ", L.MAIL_NAME_PAD - n) end
      buf:bytes(off + M.playerName, Gen3Save.encodeString(name, M.playerNameLength - 1, 0xFF))
    end
    buf:w32(off + M.trainerId, item ~= 0 and (tonumber(rec.trainerIdRaw) or tonumber(rec.trainerId) or 0) or 0)
    buf:w16(off + M.species, item ~= 0 and (tonumber(rec.species) or L.MAIL_CLEAR_SPECIES) or L.MAIL_CLEAR_SPECIES)
    buf:w16(off + M.itemId, item)
  end

  local function decodeDaycareMail(s, off)
    local D = L.DAYCARE_MAIL
    if L.FAMILY == "rs" then
      return require("src.save_convert.gen3_port.sections.rs_daycare_mail").read(s:sub(off + 1, off + 56), Gen3Save)
    end
    local message = decodeMail(s, off + D.off)
    if message.itemId == 0 then return nil end
    return {
      message = message,
      otName = Gen3Save.decodeString(s, off + D.off + D.otName, D.otNameLength),
      monName = Gen3Save.decodeString(s, off + D.off + D.monName, D.monNameLength),
    }
  end

  -- src/daycare.c:425
  local function writeDaycareMail(buf, off, mail)
    local D = L.DAYCARE_MAIL
    local base = off + D.off
    if L.FAMILY == "rs" then
      local rendered = require("src.save_convert.gen3_port.sections.rs_daycare_mail").render(
        Gen3Save, buf:str():sub(base + 1, base + 56), mail, writeMail)
      buf:bytes(base, rendered)
      return
    end
    if L.FAMILY == "emerald" and type(mail) == "table" and mail._recordMixNativeBytes then
      local cross = require("src.core.game3.link.rs_record_cross_bytes")
      buf:bytes(base, cross.renderMail(Gen3Save, mail, buf:str():sub(base + 1, base + 56), true))
      return
    end
    if type(mail) == "table" and type(mail.message) == "table" and (tonumber(mail.message.itemId) or 0) ~= 0 then
      buf:fill(base + D.otName, D.otNameLength, 0)
      buf:fill(base + D.monName, D.monNameLength, 0)
      writeMail(buf, base, mail.message)
      -- src/daycare.c:431
      buf:bytes(base + D.otName, Gen3Save.encodeString(mail.otName, D.otNameLength))
      buf:bytes(base + D.monName, Gen3Save.encodeString(mail.monName, D.monNameLength))
    else
      buf:w16(base + L.MAIL.itemId, 0)
    end
  end

  local function decodeDaycareMon(sb1, off)
    local D = L.DAYCARE
    local mon = Gen3Save.decodeBoxMon(sb1:sub(off + 1, off + L.BOX_MON_SIZE))
    if mon and not mon.hasSpecies then mon = nil end
    return mon, u32(sb1, off + D.stepsOff), mon and decodeDaycareMail(sb1, off) or nil
  end

  -- src/hall_of_fame.c:32
  local function decodeHof(image)
    local parts = {}
    for _, id in ipairs({ L.SECTOR_ID_HOF_1, L.SECTOR_ID_HOF_2 }) do
      local base = id * L.SECTOR_SIZE
      if #image < base + L.SECTOR_SIZE then return {} end
      if u32(image, base + L.FOOTER.signature) ~= L.SIGNATURE then return {} end
      -- src/save.c:592
      if u16(image, base + L.FOOTER.id) ~= Gen3Save.checksum(image, base, L.SECTOR_DATA_SIZE) then return {} end
      parts[#parts + 1] = image:sub(base + 1, base + L.SECTOR_DATA_SIZE)
    end
    local data, H, teams = table.concat(parts), L.HOF, {}
    for t = 0, H.teams - 1 do
      local team = {}
      for i = 0, H.monsPerTeam - 1 do
        local o = (t * H.monsPerTeam + i) * H.monSize
        local sl = u16(data, o + H.speciesLevel)
        local species = sl % 512
        if species == 0 then break end
        team[#team + 1] = {
          tid = u32(data, o + H.tid),
          personality = u32(data, o + H.personality),
          species = species,
          level = math.floor(sl / 512),
          nickname = Gen3Save.decodeString(data, o + H.nick, H.nickLength),
        }
      end
      if #team == 0 then break end
      teams[#teams + 1] = team
    end
    return teams
  end

  -- src/hall_of_fame.c:32
  function Gen3Save.encodeHof(teams)
    local H = L.HOF
    local b = newBuf(L.HOF_SECTORS * L.SECTOR_DATA_SIZE)
    b:fill(0, b.n, 0)
    for t, team in ipairs(teams or {}) do
      if t > H.teams then break end
      for i, m in ipairs(team) do
        if i > H.monsPerTeam then break end
        local o = ((t - 1) * H.monsPerTeam + i - 1) * H.monSize
        b:w32(o + H.tid, m.tid or 0)
        b:w32(o + H.personality, m.personality or 0)
        b:w16(o + H.speciesLevel, (m.species or 0) % 512 + ((m.level or 0) % 128) * 512)
        b:bytes(o + H.nick, Gen3Save.encodeString(m.nickname, H.nickLength, 0xFF))
      end
    end
    return b:str()
  end

  function Gen3Save.decode(bytes)
    local blocks, why = Gen3Save.readBlocks(bytes)
    if not blocks then
      local fam = why == "corrupt" and Gen3Save.sniff(bytes)
      if fam and fam ~= L.FAMILY then return nil, L.MARKER and (Gen3Save.MSG[fam] and fam or "notFrlg") or fam end
      return nil, why
    end
    local sb2, sb1, st = blocks.sb2, blocks.sb1, blocks.storage
    if L.MARKER then
      -- src/new_game.c:121
      if u32(sb2, L.MARKER.off) ~= L.MARKER.value then
        return nil, Gen3Save.sniff(bytes) == "rs" and "rs" or "notFrlg"
      end
    else
      local fam = Gen3Save.sniff(bytes)
      if fam and fam ~= L.FAMILY then return nil, fam end
    end
    if u16(sb2, 0x006) == 0 then return nil, "japanese" end
    local key = L.UNENCRYPTED and 0 or u32(sb2, L.KEY_OFF)
    local out = { counter = blocks.counter, slot = blocks.slot, olderSlot = blocks.olderSlot }
    if L.RSE and L.RSE.sb1 and L.RSE.sb1.tvShows then
      local o = L.RSE.sb1.tvShows
      out.tvShowsRawPrefix = sb1:sub(o + 1, o + 256)
    end
    Gen3Save.readFields(sb2, L.SB2, out, key)
    out.options = {}
    for _, f in ipairs(L.OPTIONS_BITS) do out.options[f[1]] = bits(out.optionsWord, f[2], f[3]) end
    out.options.buttonMode = out.buttonMode
    Gen3Save.readFields(sb1, L.SB1, out, key)
    out.boxFlags = u8(sb1, BOX_FLAGS_OFFSET)
    out.party = {}
    for i = 0, math.min(out.partyCount, L.PARTY_SIZE) - 1 do
      local o = L.PARTY_OFFSET + i * L.PARTY_MON_SIZE
      out.party[#out.party + 1] = Gen3Save.decodePartyMon(sb1:sub(o + 1, o + L.PARTY_MON_SIZE))
    end
    out.pcItems = readItems(sb1, L.PC_ITEMS.off, L.PC_ITEMS.count, nil)
    out.pockets = {}
    -- src/load_save.c:286
    for _, p in ipairs(L.POCKETS) do out.pockets[p.key] = readItems(sb1, p.off, p.count, key) end
    local OE, E = L.OBJECT_EVENTS, L.OBJECT_EVENT
    for i = 0, OE.count - 1 do
      local o = OE.off + i * OE.size
      if band(u8(sb1, o + E.flags), 1) == 1 and band(u8(sb1, o + E.isPlayerByte), 1) == 1 then
        out.player = {
          offset = o,
          facing = band(u8(sb1, o + E.facing), 15),
          graphicsId = u8(sb1, o + E.graphicsId),
          x = s16(sb1, o + E.currentX) - L.MAP_OFFSET,
          y = s16(sb1, o + E.currentY) - L.MAP_OFFSET,
        }
        break
      end
    end
    out.vars = {}
    for i = 0, L.VARS.count - 1 do
      local v = u16(sb1, L.VARS.off + i * 2)
      if v ~= 0 then out.vars[L.VARS.first + i] = v end
    end
    out.gameStats = {}
    for i = 0, L.GAME_STATS.count - 1 do
      -- src/overworld.c:384
      local v = tou32(bxor(u32(sb1, L.GAME_STATS.off + i * 4), key))
      if v ~= 0 then out.gameStats[i] = v end
    end
    out.easyChatProfile = {}
    for i = 0, L.EASY_CHAT_PROFILE.count - 1 do
      out.easyChatProfile[i + 1] = u16(sb1, L.EASY_CHAT_PROFILE.off + i * 2)
    end
    local EB = L.EASY_CHAT_BATTLE
    out.easyChatBattle = {}
    for _, k in ipairs({ "start", "won", "lost" }) do
      out.easyChatBattle[k] = {}
      for i = 0, EB.count - 1 do out.easyChatBattle[k][i + 1] = u16(sb1, EB[k] + i * 2) end
    end
    local M = L.MAIL
    out.mail = {}
    for i = 0, M.count - 1 do out.mail[i + 1] = decodeMail(sb1, M.off + i * M.size) end
    local FC = L.FAME_CHECKER
    if FC then
      out.fameChecker = {}
      for i = 0, FC.count - 1 do
        local w = u16(sb1, FC.off + i * FC.stride)
        out.fameChecker[i + 1] = { pickState = bits(w, 0, FC.pickBits), flavorTextFlags = bits(w, FC.flavorShift, FC.flavorBits),
          unk = bits(w, FC.unkShift, 2) }
      end
    end
    local RT = L.REGISTERED_TEXTS
    if RT then
      out.registeredTexts = {}
      for i = 0, RT.count - 1 do out.registeredTexts[i + 1] = Gen3Save.decodeString(sb1, RT.off + i * RT.size, RT.size) end
    end
    local TT = L.TRAINER_TOWER
    if TT then
      out.trainerTowerBest = {}
      for i = 0, TT.count - 1 do
        -- src/trainer_tower.c:1082
        out.trainerTowerBest[i + 1] = tou32(bxor(u32(sb1, TT.off + i * TT.size + TT.bestTime), key))
      end
    end
    local D = L.DAYCARE
    out.daycare = { mons = {}, steps = {}, mail = {} }
    for i = 0, 1 do
      local mon, steps, mail
      if D.mailOffset then
        local at = D.off + i * D.monSize
        mon = Gen3Save.decodeBoxMon(sb1:sub(at + 1, at + L.BOX_MON_SIZE))
        if mon and not mon.hasSpecies then mon = nil end
        steps = u32(sb1, D.off + D.stepsOffset + i * 4)
        mail = (L.FAMILY == "rs" or mon) and decodeDaycareMail(sb1, D.off + D.mailOffset + i * D.mailSize) or nil
      else
        mon, steps, mail = decodeDaycareMon(sb1, D.off + i * D.monSize)
      end
      out.daycare.mons[i + 1] = mon
      out.daycare.steps[i + 1] = steps
      out.daycare.mail[i + 1] = mail
    end
    out.daycare.offspringPersonality = (D.offspringKind == "u32" and u32 or u16)(sb1, D.off + D.offspringPersonality)
    out.daycare.stepCounter = u8(sb1, D.off + D.stepCounter)
    if L.ROUTE5_DAYCARE then
      local r5mon, r5steps, r5mail = decodeDaycareMon(sb1, L.ROUTE5_DAYCARE)
      out.route5Daycare = { mon = r5mon, steps = r5steps, mail = r5mail }
    end
    local roamer = {}
    for _, f in ipairs(L.ROAMER) do roamer[f[1]] = readValue(sb1, L.ROAMER_OFFSET + f[2], f[3]) end
    out.roamer = roamer
    local S = L.STORAGE
    out.storage = { currentBox = u8(st, S.currentBox), boxes = {} }
    for bx = 0, S.totalBoxes - 1 do
      local box = {
        name = Gen3Save.decodeString(st, S.boxNames + bx * S.boxNameLength, S.boxNameLength),
        wallpaper = u8(st, S.wallpapers + bx),
        mons = {},
      }
      for sl = 0, S.inBox - 1 do
        local o = S.boxes + (bx * S.inBox + sl) * L.BOX_MON_SIZE
        local mon = Gen3Save.decodeBoxMon(st:sub(o + 1, o + L.BOX_MON_SIZE))
        if mon and mon.hasSpecies then box.mons[sl + 1] = mon end
      end
      out.storage.boxes[bx + 1] = box
    end
    out.hallOfFame = decodeHof(blocks.image)
    return out, blocks
  end

  function Gen3Save.encodeBlocks(t, template)
    template = template or {}
    local key = L.UNENCRYPTED and 0 or (t.encryptionKey or 0)
    local sb2 = newBuf(L.BLOCKS[1].size, template.sb2)
    if not template.sb2 then
      for _, p in ipairs(L.NEW_GAME_SB2 or {}) do sb2:w8(p[1], p[2]) end
    end
    local o = t.options or {}
    local word = 0
    for _, f in ipairs(L.OPTIONS_BITS) do word = word + ((o[f[1]] or 0) % 2 ^ f[3]) * 2 ^ f[2] end
    local fields = {}
    for k, v in pairs(t) do fields[k] = v end
    fields.optionsWord = word
    fields.buttonMode = o.buttonMode or t.buttonMode or 0
    if L.MARKER then fields.frlgMarker = L.MARKER.value end
    fields.dexUnused = t.dexUnused or L.DEX_UNUSED_DEFAULT or 0
    Gen3Save.writeFields(sb2, L.SB2, fields, key)

    local sb1 = newBuf(L.BLOCKS[2].size, template.sb1)
    if t.clearLinkRecords then
      local LR = L.LINK_BATTLE_RECORDS
      local lb = LR.block == "sb1" and sb1 or sb2
      -- src/battle_records.c:274
      for i = 0, LR.count - 1 do
        lb:fill(LR.off + i * LR.size, LR.size, 0)
        lb:w8(LR.off + i * LR.size, 0xFF)
      end
    end
    if t.resetMapState then
      local OE, MV = L.OBJECT_EVENTS, L.MAP_VIEW
      sb1:fill(OE.off, OE.count * OE.size, 0)
      if MV then (MV.block == "sb2" and sb2 or sb1):fill(MV.off, MV.size, 0) end
      -- src/quest_log.c:202
      if L.QUEST_LOG then sb1:fill(L.QUEST_LOG.off, L.QUEST_LOG.size, 0) end
    elseif t.player and t.playerFacing then
      local at = t.player.offset + L.OBJECT_EVENT.facing
      sb1:w8(at, t.playerFacing % 16 + t.playerFacing % 16 * 16)
    end
    fields.partyCount = #(t.party or {})
    Gen3Save.writeFields(sb1, L.SB1, fields, key)
    if t.boxFlags ~= nil then sb1:w8(BOX_FLAGS_OFFSET, t.boxFlags) end
    sb1:fill(L.PARTY_OFFSET, L.PARTY_SIZE * L.PARTY_MON_SIZE, 0)
    for i = 0, L.PARTY_SIZE - 1 do
      -- src/pokemon.c:1737
      sb1:w8(L.PARTY_OFFSET + i * L.PARTY_MON_SIZE + L.PARTY_MAIL, 0xFF)
    end
    for i, mon in ipairs(t.party or {}) do
      sb1:bytes(L.PARTY_OFFSET + (i - 1) * L.PARTY_MON_SIZE, Gen3Save.encodePartyMon(mon))
    end
    writeItems(sb1, L.PC_ITEMS.off, L.PC_ITEMS.count, t.pcItems, nil)
    for _, p in ipairs(L.POCKETS) do writeItems(sb1, p.off, p.count, (t.pockets or {})[p.key], key) end
    for i = 0, L.VARS.count - 1 do sb1:w16(L.VARS.off + i * 2, (t.vars or {})[L.VARS.first + i] or 0) end
    for i = 0, L.GAME_STATS.count - 1 do
      sb1:w32(L.GAME_STATS.off + i * 4, bxor((t.gameStats or {})[i] or 0, key))
    end
    for i = 0, L.EASY_CHAT_PROFILE.count - 1 do
      sb1:w16(L.EASY_CHAT_PROFILE.off + i * 2, (t.easyChatProfile or {})[i + 1] or 0)
    end
    local EB = L.EASY_CHAT_BATTLE
    if t.easyChatBattle then
      for _, k in ipairs({ "start", "won", "lost" }) do
        local list = t.easyChatBattle[k] or {}
        for i = 0, EB.count - 1 do sb1:w16(EB[k] + i * 2, list[i + 1] or L.EC_WORD_UNDEFINED) end
      end
    end
    local M = L.MAIL
    if t.mail then
      for i = 0, M.count - 1 do writeMail(sb1, M.off + i * M.size, t.mail[i + 1]) end
    end
    local FC = L.FAME_CHECKER
    if FC and t.fameChecker then
      for i = 0, FC.count - 1 do
        local r = t.fameChecker[i + 1] or {}
        sb1:w16(FC.off + i * FC.stride, ((r.pickState or 0) % 2 ^ FC.pickBits) + ((r.flavorTextFlags or 0) % 2 ^ FC.flavorBits) * 2 ^ FC.flavorShift
          + ((r.unk or 0) % 4) * 2 ^ FC.unkShift)
      end
    end
    local RT = L.REGISTERED_TEXTS
    if RT and t.registeredTexts then
      for i = 0, RT.count - 1 do
        sb1:fill(RT.off + i * RT.size, RT.size, 0)
        sb1:bytes(RT.off + i * RT.size, Gen3Save.encodeString(t.registeredTexts[i + 1] or "", RT.size - 1))
      end
    end
    local TT = L.TRAINER_TOWER
    if TT and t.trainerTowerBest then
      for i = 0, TT.count - 1 do
        -- src/trainer_tower.c:1082
        sb1:w32(TT.off + i * TT.size + TT.bestTime, bxor(t.trainerTowerBest[i + 1] or L.TRAINER_TOWER_MAX_TIME, key))
      end
    end
    local D = L.DAYCARE
    local dc = t.daycare or { mons = {}, steps = {} }
    for i = 0, 1 do
      local off = D.off + i * D.monSize
      local mon = dc.mons and dc.mons[i + 1]
      if mon then sb1:bytes(off, Gen3Save.encodeBoxMon(mon)) else sb1:fill(off, L.BOX_MON_SIZE, 0) end
      local mailOff = D.mailOffset and (D.off + D.mailOffset + i * D.mailSize) or off
      local mail = (dc.mail or {})[i + 1]
      writeDaycareMail(sb1, mailOff, (L.FAMILY == "rs" or mon or (L.FAMILY == "emerald" and type(mail) == "table" and mail._recordMixNativeBytes)) and mail or nil)
      local stepsOff = D.stepsOffset and (D.off + D.stepsOffset + i * 4) or (off + D.stepsOff)
      sb1:w32(stepsOff, (dc.steps or {})[i + 1] or 0)
    end
    if D.offspringKind == "u32" then
      sb1:w32(D.off + D.offspringPersonality, dc.offspringPersonality or 0)
    else
      sb1:w16(D.off + D.offspringPersonality, dc.offspringPersonality or 0)
    end
    sb1:w8(D.off + D.stepCounter, dc.stepCounter or 0)
    if L.ROUTE5_DAYCARE then
      local r5 = t.route5Daycare or {}
      if r5.mon then
        sb1:bytes(L.ROUTE5_DAYCARE, Gen3Save.encodeBoxMon(r5.mon))
      else
        sb1:fill(L.ROUTE5_DAYCARE, L.BOX_MON_SIZE, 0)
      end
      writeDaycareMail(sb1, L.ROUTE5_DAYCARE, r5.mon and r5.mail or nil)
      sb1:w32(L.ROUTE5_DAYCARE + D.stepsOff, r5.steps or 0)
    end
    if t.roamer then
      for _, f in ipairs(L.ROAMER) do writeValue(sb1, L.ROAMER_OFFSET + f[2], f[3], nil, t.roamer[f[1]] or 0) end
    end

    local S = L.STORAGE
    local st = newBuf(L.BLOCKS[3].size, template.storage)
    local stg = t.storage or { currentBox = 0, boxes = {} }
    st:w8(S.currentBox, stg.currentBox or 0)
    st:fill(S.boxes, S.totalBoxes * S.inBox * L.BOX_MON_SIZE, 0)
    for bx = 1, S.totalBoxes do
      local box = (stg.boxes or {})[bx] or {}
      st:bytes(S.boxNames + (bx - 1) * S.boxNameLength,
        Gen3Save.encodeString(box.name or L.DEFAULT_BOX_NAME:format(bx), S.boxNameLength))
      st:w8(S.wallpapers + bx - 1, box.wallpaper or ((bx - 1) % L.DEFAULT_WALLPAPER_MOD))
      for sl, mon in pairs(box.mons or {}) do
        st:bytes(S.boxes + ((bx - 1) * S.inBox + sl - 1) * L.BOX_MON_SIZE, Gen3Save.encodeBoxMon(mon))
      end
    end
    return { sb2 = sb2:str(), sb1 = sb1:str(), storage = st:str() }
  end

  local function footer(id, checksum, counter)
    local f = newBuf(12)
    f:w16(0, id)
    f:w16(2, checksum)
    f:w32(4, L.SIGNATURE)
    f:w32(8, counter)
    return f:str()
  end

  -- src/save.c:174
  function Gen3Save.buildFlash(blocks, opts)
    opts = opts or {}
    local chunks = {}
    for _, blk in ipairs(L.BLOCKS) do
      local off = 0
      for id = blk.first, blk.last do
        chunks[id] = blocks[blk.key]:sub(off + 1, off + L.CHUNK_SIZES[id])
        off = off + L.CHUNK_SIZES[id]
      end
    end
    local counter = opts.counter or 1
    local slot = counter % L.NUM_SLOTS
    local rot = opts.rotation or (counter % L.SECTORS_PER_SLOT)
    local flash = {}
    local base = opts.image
    for i = 0, L.NUM_SECTORS - 1 do
      flash[i] = base and base:sub(i * L.SECTOR_SIZE + 1, (i + 1) * L.SECTOR_SIZE) or string.rep("\255", L.SECTOR_SIZE)
      if #flash[i] < L.SECTOR_SIZE then flash[i] = flash[i] .. string.rep("\255", L.SECTOR_SIZE - #flash[i]) end
    end
    for id = 0, L.SECTORS_PER_SLOT - 1 do
      local data = chunks[id]
      local padded = data .. string.rep("\0", L.SECTOR_DATA_SIZE - #data)
      local ck = Gen3Save.checksum(padded, 0, L.CHUNK_SIZES[id])
      local phys = slot * L.SECTORS_PER_SLOT + (rot + id) % L.SECTORS_PER_SLOT
      flash[phys] = padded .. string.rep("\0", L.FOOTER.id - L.SECTOR_DATA_SIZE) .. footer(id, ck, counter)
    end
    if opts.hof then
      for i = 0, L.HOF_SECTORS - 1 do
        local data = opts.hof:sub(i * L.SECTOR_DATA_SIZE + 1, (i + 1) * L.SECTOR_DATA_SIZE)
        -- src/save.c:210
        flash[L.SECTOR_ID_HOF_1 + i] = data .. string.rep("\0", L.FOOTER.id - L.SECTOR_DATA_SIZE)
          .. footer(Gen3Save.checksum(data, 0, L.SECTOR_DATA_SIZE), 0, 0)
      end
    end
    local out = {}
    for i = 0, L.NUM_SECTORS - 1 do out[#out + 1] = flash[i] end
    return table.concat(out)
  end

  function Gen3Save.encode(t, opts)
    opts = opts or {}
    return Gen3Save.buildFlash(Gen3Save.encodeBlocks(t, opts.template), opts)
  end

  function Gen3Save.message(why, n)
    if why == "size" then return Gen3Save.MSG.size:format(n or 0) end
    return Gen3Save.MSG[why] or Gen3Save.MSG.corrupt
  end

  local function consts()
    return L.GAME and require("src.core.game3.constants").of(L.GAME) or nil
  end

  local RESOLVED
  local function resolved()
    if RESOLVED then return RESOLVED end
    local C = consts()
    local function id(kind, v)
      if type(v) == "string" then return C:require(kind, v) end
      return v
    end
    local N = L.NATIONAL_DEX
    RESOLVED = {
      national = { magic = N.magic, var = id("vars", N.var), varValue = N.varValue, flag = id("flags", N.flag) },
      gameClear = id("flags", L.FLAG_SYS_GAME_CLEAR),
    }
    return RESOLVED
  end
  Gen3Save.resolved = resolved

  local MAPS
  local function gameMaps()
    if MAPS ~= nil then return MAPS end
    local C = consts()
    if not C then
      MAPS = false
      return MAPS
    end
    local prefix = require("src.core.game3.profile").of(L.GAME).map.enginePrefix
    MAPS = { byKey = {}, bySlot = {} }
    for const, row in pairs(C.map_groups.byName) do
      if type(row) == "table" and row.group and row.num then
        local id = prefix .. const:gsub("^MAP_", "")
        MAPS.byKey[row.group .. ":" .. row.num] = id
        MAPS.bySlot[id] = row.group .. "_" .. row.num
      end
    end
    return MAPS
  end

  local function mapFor(group, num)
    local maps = gameMaps()
    if maps then return maps.byKey[(tonumber(group) or 0) .. ":" .. (tonumber(num) or 0)] end
    return require("src.import.gba.map_catalog").mapIdFor(group, num)
  end
  Gen3Save.mapFor = mapFor

  local function slotKeyFor(mapId)
    local maps = gameMaps()
    if maps then return type(mapId) == "string" and maps.bySlot[mapId] or nil end
    return require("src.import.gba.map_catalog").slotKeyFor(mapId)
  end

  local function portWarp(w)
    if type(w) ~= "table" or w.group < 0 or w.num < 0 then return nil end
    local map = mapFor(w.group, w.num)
    if not map then return nil end
    return { map = map, warpId = w.warpId, x = w.x, y = w.y }
  end

  local function portStatus(raw)
    raw = raw or 0
    local sleep = band(raw, L.STATUS.sleepMask)
    if sleep ~= 0 then return "SLP", sleep end
    for _, k in ipairs(L.STATUS_ORDER) do
      if band(raw, L.STATUS[k]) ~= 0 then return k, 0 end
    end
    return nil, 0
  end

  local STAT_ALIASES = { linkBattleWins = 23, linkBattleLosses = 24, linkBattleDraws = 25 }
  Gen3Save.STAT_ALIASES = STAT_ALIASES

  local function portGameStats(stats)
    local out = {}
    for k, v in pairs(stats) do out[k] = v end
    for name, id in pairs(STAT_ALIASES) do
      if stats[id] then out[name] = stats[id] end
    end
    return out
  end

  function Gen3Save.toPortMon(c, party)
    local moves, pp = {}, {}
    for i = 1, 4 do
      if (c.moves[i] or 0) ~= 0 then
        moves[#moves + 1] = c.moves[i]
        pp[#pp + 1] = c.pp[i]
      end
    end
    local mon = {
      species = c.species,
      speciesId = c.species,
      speciesNumbering = "internal",
      personality = c.personality,
      nature = c.personality % 25,
      otId = c.otId,
      otSecretId = c.otSecretId,
      ot = c.otName,
      otName = c.otName,
      otGender = c.otGender,
      nickname = c.nickname,
      language = c.language,
      isEgg = c.isEgg or nil,
      isBadEgg = c.isBadEgg or nil,
      markings = c.markings,
      item = c.heldItem ~= 0 and c.heldItem or nil,
      heldItem = c.heldItem,
      exp = c.exp,
      friendship = c.friendship,
      happiness = c.friendship,
      ppBonusesPacked = c.ppBonuses,
      moves = moves,
      pp = pp,
      evs = c.evs,
      ivs = c.ivs,
      contest = c.contest,
      ribbons = c.ribbons - (c.championRibbon and 2 ^ L.RIBBON_CHAMPION_BIT or 0) - (c.modernFatefulEncounter and 2 ^ L.RIBBON_FATEFUL_BIT or 0),
      championRibbon = c.championRibbon or false,
      modernFatefulEncounter = c.modernFatefulEncounter or false,
      pokerus = c.pokerus,
      metLocation = c.metLocation,
      metLevel = c.metLevel,
      metGame = c.metGame,
      pokeball = c.pokeball,
      abilityNum = c.abilityNum,
      cartExtra = {
        flagsRaw = c.flagsRaw,
        unknown = c.unknown,
        growthFiller = c.growthFiller,
      },
      cartImport = true,
    }
    local gap, seenEmpty = false, false
    for i = 1, 4 do
      if (c.moves[i] or 0) == 0 then
        seenEmpty = true
        if (c.pp[i] or 0) ~= 0 then gap = true end
      elseif seenEmpty then
        gap = true
      end
    end
    if gap then
      mon.cartExtra.moveSlots = { moves = { c.moves[1], c.moves[2], c.moves[3], c.moves[4] },
        pp = { c.pp[1], c.pp[2], c.pp[3], c.pp[4] } }
    end
    if c.isEgg then
      mon.nickname, mon.name = "EGG", "EGG"
      -- pokeruby/src/pokemon_2.c:342
      if c.isBadEgg then mon.nickname, mon.name = "Bad EGG", "Bad EGG" end
      mon.eggCycles = c.friendship
    end
    if c.nicknameBytes then
      mon.cartExtra.nicknameBytes = { c.nicknameBytes:byte(1, -1) }
      mon.cartExtra.nicknameLanguage = c.language
    end
    if c.nicknameRaw then
      mon.cartExtra.nicknameRaw = { c.nicknameRaw:byte(1, -1) }
      mon.cartExtra.otNameRaw = { c.otNameRaw:byte(1, -1) }
    end
    if c.raw then
      mon.cartRaw = (c.raw:gsub(".", function(ch) return string.format("%02X", ch:byte()) end))
    end
    if party then
      mon.level = c.level
      mon.hp = c.hp
      mon.status, mon.sleep = portStatus(c.status)
      if c.status ~= 0 then mon.cartExtra.statusRaw = c.status end
      mon.maxHp, mon.attack, mon.defense = c.maxHp, c.attack, c.defense
      mon.speed, mon.spAtk, mon.spDef = c.speed, c.spAtk, c.spDef
      if c.mail < L.MAIL.count then mon.mail = c.mail end
    end
    return mon
  end

  local function portBoxName(name, b)
    if name == L.DEFAULT_BOX_NAME:format(b) then return string.format("BOX %d", b) end
    return name
  end

  local function portWallpaper(w)
    return w + 1
  end

  local function has(list, v)
    for _, x in ipairs(list) do if x == v then return true end end
    return false
  end

  local function nationalList(bitsList)
    local out = {}
    for _, i in ipairs(bitsList) do out[#out + 1] = i + 1 end
    return out
  end

  function Gen3Save.toPortSave(c, version)
    local flags = {}
    for _, id in ipairs(c.flags) do
      if id > L.TEMP_FLAGS_END then
        flags[id] = true
        flags[tostring(id)] = true
      end
    end
    local vars = {}
    for id, v in pairs(c.vars) do vars[id] = v end
    local pockets = {}
    for _, p in ipairs(L.POCKETS) do pockets[p.key] = c.pockets[p.key] end
    local boxes = {}
    for b, box in ipairs(c.storage.boxes) do
      local mons = {}
      for sl, mon in pairs(box.mons) do mons[sl] = Gen3Save.toPortMon(mon, false) end
      boxes[b] = { name = portBoxName(box.name, b), wallpaper = portWallpaper(box.wallpaper, b), mons = mons }
    end
    local party = {}
    for i, mon in ipairs(c.party) do party[i] = Gen3Save.toPortMon(mon, true) end
    local seenCount = {}
    for _, list in ipairs({ c.dexSeen, c.dexSeen1, c.dexSeen2 }) do
      for _, i in ipairs(list) do seenCount[i] = (seenCount[i] or 0) + 1 end
    end
    local seenList, ownedList = {}, {}
    -- src/pokedex_screen.c:2243
    for i, n in pairs(seenCount) do if n == 3 then seenList[#seenList + 1] = i end end
    table.sort(seenList)
    -- src/pokedex_screen.c:2252
    for _, i in ipairs(c.dexOwned) do if seenCount[i] == 3 then ownedList[#ownedList + 1] = i end end
    local N = resolved().national
    local national = c.dexNationalMagic == N.magic and c.vars[N.var] == N.varValue and has(c.flags, N.flag)
    local mail
    for i, rec in ipairs(c.mail or {}) do
      if rec.itemId ~= 0 or L.FAMILY == "rs" then
        mail = mail or {}
        local own = rec.trainerIdRaw == c.trainerId + c.secretId * 65536
        mail[i] = { words = rec.words, playerName = rec.playerName, trainerId = L.FAMILY == "rs" and rec.trainerIdRaw or ((own or rec.trainerIdRaw < 65536) and rec.trainerId or rec.trainerIdRaw), species = rec.species,
          itemId = rec.itemId, design = isMailItem(rec.itemId) and rec.itemId - L.MAIL_ITEM_FIRST or nil,
          _rsNativeBytes = rec._rsNativeBytes,
          _recordMixNativeBytes = L.FAMILY == "emerald" and rec._recordMixNativeBytes or nil }
      end
    end
    if mail then
      for i = 1, L.MAIL.count do
        mail[i] = mail[i] or { words = {}, playerName = "", trainerId = 0, species = L.MAIL_CLEAR_SPECIES, itemId = 0 }
      end
    end
    local function portDaycareMail(m)
      if not m then return nil end
      local r = m.message
      return { otName = m.otName, monName = m.monName, _rsNativeBytes = L.FAMILY == "rs" and m._rsNativeBytes or nil,
        _recordMixNativeBytes = L.FAMILY == "emerald" and m._recordMixNativeBytes or nil, message = { words = r.words, playerName = r.playerName,
        trainerId = L.FAMILY == "rs" and r.trainerIdRaw or r.trainerId, species = r.species, itemId = r.itemId,
        _rsNativeBytes = r._rsNativeBytes, design = isMailItem(r.itemId) and r.itemId - L.MAIL_ITEM_FIRST or nil } }
    end
    local recordMixTvBytes256
    if type(c.tvShowsRawPrefix) == "string" and #c.tvShowsRawPrefix >= 256 then
      recordMixTvBytes256 = {}
      for i = 1, 256 do recordMixTvBytes256[i] = c.tvShowsRawPrefix:byte(i) end
    end
    for _, mon in ipairs(party) do
      if mon.mail and not (mail and mail[mon.mail + 1] and mail[mon.mail + 1].itemId ~= 0) then mon.mail = nil end
    end
    local fame = {}
    for i, r in ipairs(c.fameChecker or {}) do fame[i] = { pickState = r.pickState, flavorTextFlags = r.flavorTextFlags } end
    local tower
    if c.trainerTowerBest then
      tower = { challengeId = 0, records = {} }
      for i, t in ipairs(c.trainerTowerBest) do
        tower.records[i] = { bestTime = math.min(t, L.TRAINER_TOWER_MAX_TIME) }
      end
    end
    local map = mapFor(c.location.group, c.location.num)
    local facing = c.player and L.FACING[c.player.facing] or "down"
    local hofTime = c.gameStats[L.GAME_STAT_FIRST_HOF_PLAY_TIME]
    local hofTeams = {}
    for _, team in ipairs(c.hallOfFame or {}) do
      local rec = {}
      for _, m in ipairs(team) do
        rec[#rec + 1] = {
          species = m.species, level = m.level, nickname = m.nickname,
          trainerId = m.tid % 65536, otSecretId = math.floor(m.tid / 65536), personality = m.personality,
        }
      end
      hofTeams[#hofTeams + 1] = rec
    end
    local daycare = { steps = { c.daycare.steps[1], c.daycare.steps[2] },
      offspringPersonality = c.daycare.offspringPersonality, stepCounter = c.daycare.stepCounter }
    for i = 1, 2 do
      if c.daycare.mons[i] then daycare[i] = Gen3Save.toPortMon(c.daycare.mons[i], false) end
      local dm = portDaycareMail((c.daycare.mail or {})[i])
      if dm then
        daycare.mail = daycare.mail or {}
        daycare.mail[i] = dm
      end
    end
    local route5
    if c.route5Daycare then
      route5 = { steps = c.route5Daycare.steps, mail = portDaycareMail(c.route5Daycare.mail) }
      if c.route5Daycare.mon then route5.mon = Gen3Save.toPortMon(c.route5Daycare.mon, false) end
    end
    local profile = {}
    for i = 1, 4 do profile[i] = c.easyChatProfile[i] end
    local save = {
      schemaVersion = 1,
      engine = "game3",
      version = version,
      generation = 3,
      name = c.name,
      rivalName = c.rivalName,
      gender = c.gender,
      money = c.money,
      coins = c.coins,
      berryPowder = c.berryPowder,
      party = party,
      bag = { pockets = pockets },
      dex = { seen = {}, owned = {}, caught = {}, national = national, nationalUnlocked = national or nil,
        unownPersonality = c.unownPersonality, spindaPersonality = c.spindaPersonality },
      pokedex = ((c.dexMode or 0) ~= 0 or (c.dexOrder or 0) ~= 0) and { mode = c.dexMode or 0, order = c.dexOrder or 0 } or nil,
      map = map,
      x = c.posX,
      y = c.posY,
      facing = facing,
      flags = flags,
      vars = vars,
      playTime = { hours = c.playHours, minutes = c.playMinutes, seconds = c.playSeconds, vblanks = c.playVBlanks },
      easyChatProfile = profile,
      options = {
        textSpeed = c.options.textSpeed, frameType = c.options.frameType, sound = c.options.sound,
        battleStyle = c.options.battleStyle, battleScene = c.options.battleScene, buttonMode = c.options.buttonMode,
      },
      storage = { currentBox = math.min(c.storage.currentBox, L.STORAGE.totalBoxes - 1) + 1, boxes = boxes, items = c.pcItems },
      mail = mail,
      registeredTexts = c.registeredTexts,
      registeredItem = c.registeredItem ~= 0 and c.registeredItem or nil,
      dynamicWarp = portWarp(c.dynamicWarp),
      escapeWarp = portWarp(c.escapeWarp),
      continueGameWarp = portWarp(c.continueGameWarp),
      specialSaveWarpFlags = c.specialSaveWarpFlags,
      gcnLinkFlags = c.gcnLinkFlags,
      flashLevel = c.flashLevel,
      trainerId = c.trainerId,
      secretId = c.secretId,
      gameStats = portGameStats(c.gameStats),
      game_cleared = has(c.flags, resolved().gameClear),
      hallOfFameTeams = hofTeams,
      hasHallOfFameRecords = #hofTeams > 0,
      modData = {
        [(L.FAMILY == "rs" and tostring(version or L.GAME) .. "_daycare" or L.DAYCARE_SAVE_KEY)] = { daycare = daycare, route5Daycare = route5 },
        fameChecker = #fame > 0 and fame or nil,
        trainerTower = tower,
        cartImport = {
          boxFlags = c.boxFlags,
          dexSeen = nationalList(seenList),
          dexOwned = nationalList(ownedList),
          lastHealLocation = portWarp(c.lastHealLocation),
          recordMixTvBytes256 = recordMixTvBytes256,
        },
      },
      meta = { mods = {} },
    }
    if L.DEFAULT_EASY_CHAT and type(c.easyChatBattle) == "table" then
      -- pokeemerald/include/global.h:1050
      for k, f in pairs({ start = "easyChatBattleStart", won = "easyChatBattleWon", lost = "easyChatBattleLost" }) do
        local list = {}
        for i = 1, L.EASY_CHAT_BATTLE.count do list[i] = (c.easyChatBattle[k] or {})[i] or L.EC_WORD_UNDEFINED end
        save[f] = list
      end
    end
    if hofTime and hofTime ~= 0 then
      save.hofDebutHours = math.floor(hofTime / 65536)
      save.hofDebutMinutes = math.floor(hofTime / 256) % 256
      save.hofDebutSeconds = hofTime % 256
      save.hofDebutTime = string.format("%d:%02d:%02d", save.hofDebutHours, save.hofDebutMinutes, save.hofDebutSeconds)
    end
    return save
  end

  function Gen3Save.importPort(bytes, version)
    if type(bytes) ~= "string" then return nil, Gen3Save.message("size", 0) end
    local cart, why = Gen3Save.decode(bytes)
    if not cart then return nil, Gen3Save.message(why, #bytes) end
    if not mapFor(cart.location.group, cart.location.num) then
      return nil, Gen3Save.MSG.corrupt
    end
    local save, note = Gen3Save.stampImport(Gen3Save.toPortSave(cart, version), bytes, cart, version)
    return save, nil, note
  end

  local function num(v, d)
    return tonumber(v) or d
  end

  local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
  end

  local function trunc(s, n)
    s = type(s) == "string" and s or ""
    local out, i, count = {}, 1, 0
    while i <= #s and count < n do
      local hex = s:match("^{%x%x}", i)
      local len
      if hex then
        len = 4
      else
        local c = s:byte(i)
        len = c < 0x80 and 1 or c < 0xE0 and 2 or c < 0xF0 and 3 or 4
      end
      out[#out + 1] = s:sub(i, i + len - 1)
      i, count = i + len, count + 1
    end
    return table.concat(out)
  end

  function Gen3Save.cartWarp(w)
    if type(w) ~= "table" or type(w.map) ~= "string" then return nil end
    local key = slotKeyFor(w.map)
    local g, n = (key or ""):match("^(%d+)_(%d+)$")
    if not g then return nil end
    return { group = tonumber(g), num = tonumber(n), warpId = num(w.warpId, -1), x = num(w.x, -1), y = num(w.y, -1) }
  end

  local function cartStatus(mon)
    local s = mon.status
    if type(s) == "number" then return s % U32 end
    if s == "SLP" then return clamp(num(mon.sleep, 1), 1, L.STATUS.sleepMask) end
    for _, k in ipairs(L.STATUS_ORDER) do
      if s == k then return L.STATUS[k] end
    end
    return 0
  end

  local function statTable(v, keys, width)
    local out = {}
    if type(v) == "number" then
      for i, k in ipairs(keys) do out[k] = bits(v, (i - 1) * 5, 5) end
      return out
    end
    v = type(v) == "table" and v or {}
    for _, k in ipairs(keys) do out[k] = clamp(num(v[k], 0), 0, width) end
    return out
  end

  local FLAG_NAMES
  local function flagTables()
    if FLAG_NAMES == nil and L.GAME then
      local C = consts()
      FLAG_NAMES = { FLAGS = C.flags.byName, VARS = C.vars.byName }
    elseif FLAG_NAMES == nil then
      local ok, T = pcall(require, "src.core.game3.scripting.flags_table")
      FLAG_NAMES = ok and T or false
    end
    return FLAG_NAMES or {}
  end

  local function resolveId(k, names, prefix)
    if type(k) == "number" then return k end
    if type(k) ~= "string" then return nil end
    local n = tonumber(k)
    if n then return n end
    names = names or {}
    return names[k] or names[prefix .. k]
  end

  local function secondAbility(species, ctx)
    local abilities
    if ctx.abilities then
      abilities = ctx.abilities()
      if abilities == nil then ctx.abilitiesMissing = true end
    else
      local ok, Pokemon = pcall(require, "src.core.game3.pokemon")
      if not (ok and type(Pokemon) == "table") then return nil end
      if Pokemon._abilities == nil and Pokemon.install then pcall(Pokemon.install, Pokemon._cache) end
      abilities = Pokemon._abilities
    end
    local row = type(abilities) == "table" and abilities[species]
    if type(row) ~= "table" then return nil end
    return (tonumber(row[2]) or 0) ~= 0
  end

  local RIBBON_CHAMPION_MASK = 2 ^ 15
  local RIBBON_FATEFUL_MASK = 2 ^ 31

  local function ribbonWord(mon, x)
    local word = tonumber(mon.ribbons)
    if word == nil then
      if type(mon.ribbons) == "table" then
        local ok, Ribbons = pcall(require, "src.core.game3.rse.ribbons")
        if ok and Ribbons and Ribbons.word then
          local okw, w = pcall(Ribbons.word, mon)
          if okw then word = tonumber(w) end
        end
      end
    end
    word = word or num(x.ribbons, 0)
    word = word % U32
    local function setBit(w, mask, on)
      local has = math.floor(w / mask) % 2 == 1
      if on and not has then return w + mask end
      if not on and has then return w - mask end
      return w
    end
    if mon.championRibbon ~= nil then word = setBit(word, RIBBON_CHAMPION_MASK, mon.championRibbon == true) end
    if mon.modernFatefulEncounter ~= nil then word = setBit(word, RIBBON_FATEFUL_MASK, mon.modernFatefulEncounter == true) end
    return word
  end

  function Gen3Save.fromPortMon(mon, ctx, party)
    ctx = ctx or {}
    local x = type(mon.cartExtra) == "table" and mon.cartExtra or {}
    local species = num(mon.species or mon.speciesId, 0)
    local nationalMiss
    if mon.speciesNumbering == "national" then
      local nat = species
      species = (ctx.speciesFromNational and ctx.speciesFromNational(species)) or 0
      if species == 0 then nationalMiss = nat end
    end
    local moves, pp, portPp = {}, {}, type(mon.pp) == "table" and mon.pp or {}
    for i = 1, 4 do
      local m = type(mon.moves) == "table" and mon.moves[i] or nil
      if type(m) == "table" then
        moves[i] = num(m.moveId or m.id or m.move, 0)
        pp[i] = num(m.pp or portPp[i], 0)
      else
        moves[i] = num(m, 0)
        pp[i] = num(portPp[i], 0)
      end
      if moves[i] == 0 then pp[i] = 0 end
    end
    local slots = x.moveSlots
    if type(slots) == "table" and type(slots.moves) == "table" and type(slots.pp) == "table" then
      local cm, cp = {}, {}
      for i = 1, 4 do
        local mv = num(slots.moves[i], 0)
        if mv ~= 0 then
          cm[#cm + 1] = mv
          cp[#cp + 1] = num(slots.pp[i], 0)
        end
      end
      local same = true
      for i = 1, 4 do
        if (cm[i] or 0) ~= moves[i] or (cp[i] or 0) ~= pp[i] then same = false end
      end
      if same then
        for i = 1, 4 do
          moves[i], pp[i] = num(slots.moves[i], 0), num(slots.pp[i], 0)
        end
      end
    end
    local tid = num(ctx.trainerId, 0)
    local otId = num(mon.otId, tid) % 65536
    local sid = num(mon.otSecretId, nil)
    if sid == nil then sid = otId == tid and num(ctx.secretId, 0) or 0 end
    local isEgg = mon.isEgg == true
    -- src/daycare.c:1098
    local language = num(mon.language, isEgg and L.LANGUAGE_JAPANESE or L.LANGUAGE_ENGLISH)
    local nickname = mon.nickname
    if type(nickname) ~= "string" or nickname == "" then
      nickname = mon.name or (ctx.speciesName and ctx.speciesName(species)) or ""
    end
    local nicknameBytes
    if isEgg and nickname == "EGG" then
      if type(x.nicknameBytes) == "table" and num(x.nicknameLanguage, language) == language then
        nicknameBytes = string.char(unpack(x.nicknameBytes))
      elseif language == L.LANGUAGE_JAPANESE then
        nicknameBytes = L.EGG_NICKNAME
      end
    end
    local personality = num(mon.personality, 0) % U32
    local item = mon.item or mon.heldItem
    local c = {
      nicknameRaw = type(x.nicknameRaw) == "table" and string.char(unpack(x.nicknameRaw)) or nil,
      otNameRaw = type(x.otNameRaw) == "table" and string.char(unpack(x.otNameRaw)) or nil,
      personality = personality,
      otIdRaw = otId + (sid % 65536) * 65536,
      nickname = trunc(nickname, L.POKEMON_NAME_LENGTH),
      nicknameBytes = nicknameBytes,
      language = language,
      flagsRaw = num(x.flagsRaw, 0),
      isBadEgg = mon.isBadEgg == true,
      isEgg = isEgg,
      isEggFlag = isEgg,
      otName = trunc(mon.otName or mon.ot or ctx.playerName, L.PLAYER_NAME_LENGTH),
      markings = num(mon.markings, 0),
      unknown = num(x.unknown, 0),
      species = species,
      heldItem = (ctx.itemId and item ~= nil and ctx.itemId(item)) or num(item, 0),
      exp = num(mon.exp, 0),
      ppBonuses = num(mon.ppBonusesPacked, 0),
      friendship = isEgg and num(mon.eggCycles, num(mon.friendship, 0)) or num(mon.friendship or mon.happiness, 0),
      growthFiller = num(x.growthFiller, 0),
      moves = moves,
      pp = pp,
      evs = statTable(mon.evs, L.EV_KEYS, 255),
      contest = statTable(type(mon.contest) == "table" and mon.contest or x.contest, L.CONTEST_KEYS, 255),
      pokerus = num(mon.pokerus, 0),
      metLocation = num(mon.metLocation, 0),
      metLevel = num(mon.metLevel, isEgg and 0 or num(mon.level, 0)),
      metGame = num(mon.metGame, ctx.metGame or 0),
      pokeball = num(mon.pokeball, 4),
      otGender = num(mon.otGender, ctx.gender or 0),
      ivs = statTable(mon.ivs, L.IV_KEYS, 31),
      -- src/pokemon.c:1857
      abilityNum = mon.abilityNum ~= nil and num(mon.abilityNum) or (secondAbility(species, ctx) == false and 0 or personality % 2),
      ribbons = ribbonWord(mon, x),
    }
    if mon.ribbons == nil and x.ribbons == nil then
      if x.championRibbon then c.ribbons = c.ribbons + 2 ^ L.RIBBON_CHAMPION_BIT end
      if x.modernFatefulEncounter then c.ribbons = c.ribbons + 2 ^ L.RIBBON_FATEFUL_BIT end
    end
    if type(mon.cartRaw) == "string" and #mon.cartRaw % 2 == 0 and not mon.cartRaw:find("[^%x]") then
      c.raw = mon.cartRaw:gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end)
    elseif species == 0 then
      c.missingSpecies = nationalMiss or 0
    end
    if party then
      local maxHp = num(mon.maxHp or (type(mon.stats) == "table" and mon.stats.hp), 0)
      c.status = cartStatus(mon)
      local sr = tonumber(x.statusRaw)
      if sr then
        local k, sleep = portStatus(sr)
        if c.status == cartStatus({ status = k, sleep = sleep }) then c.status = sr % U32 end
      end
      c.level = clamp(num(mon.level, 1), 1, 100)
      c.mail = ctx.mailIndex and ctx.mailIndex(mon, c) or L.MAIL_NONE
      c.maxHp = maxHp
      c.hp = clamp(num(mon.hp, maxHp), 0, maxHp)
      c.attack, c.defense = num(mon.attack, 0), num(mon.defense, 0)
      c.speed, c.spAtk, c.spDef = num(mon.speed, 0), num(mon.spAtk, 0), num(mon.spDef, 0)
    end
    return c
  end

  local function freshCart()
    return {
      options = {},
      party = {},
      pcItems = {},
      pockets = {},
      flags = {},
      vars = {},
      gameStats = {},
      easyChatProfile = {},
      daycare = { mons = {}, steps = { 0, 0 }, offspringPersonality = 0, stepCounter = 0 },
      route5Daycare = { steps = 0 },
      storage = { currentBox = 0, boxes = {} },
      hallOfFame = {},
    }
  end

  local function itemList(list, count, ctx, notes, label)
    local out, dropped = {}, 0
    for _, it in ipairs(type(list) == "table" and list or {}) do
      local id = type(it) == "table" and it.id
      local qty = type(it) == "table" and num(it.qty, 0) or 0
      id = id ~= nil and ((ctx.itemId and ctx.itemId(id)) or num(id, 0)) or 0
      if id ~= 0 and qty > 0 then
        if #out >= count then
          dropped = dropped + 1
        else
          out[#out + 1] = { id = id, qty = clamp(qty, 0, 65535) }
        end
      end
    end
    if dropped > 0 and notes then
      notes[#notes + 1] = ("%d item slot(s) did not fit in the cartridge's %s (%d slots) and were left out."):format(dropped, label, count)
    end
    return out
  end

  local function cartBoxName(name, b)
    if name == nil or name == string.format("BOX %d", b) then return L.DEFAULT_BOX_NAME:format(b) end
    return trunc(name, L.BOX_NAME_LENGTH)
  end

  local function cartWallpaper(w, b)
    w = num(w, nil)
    if w == nil then return clamp((b - 1) % L.DEFAULT_WALLPAPER_MOD, 0, L.WALLPAPER_MAX) end
    return clamp(w - 1, 0, L.WALLPAPER_MAX)
  end

  local function portOptions(save, version)
    local o = type(save.options) == "table" and save.options or {}
    local ok, Profile = pcall(require, "src.core.game3.profile")
    local block = ok and version and Profile.of(version).optionsBlock
    if block and type(o[block]) == "table" then return o[block] end
    return o
  end

  local function bitList(set)
    local out = {}
    for i in pairs(set) do out[#out + 1] = i end
    table.sort(out)
    return out
  end

  Gen3Save.MSG.noMap = "That save is on a map the cartridge does not have."
  Gen3Save.MSG.noData = "Import this game's ROM again before exporting a cartridge save."
  Gen3Save.MSG.hofSpecies = "Hall of Fame entries for species 512 and above are left out, because the cartridge format only has 9 bits for the species."
  Gen3Save.MSG.badSpecies = "Pokemon #%d (%s) has no cartridge species number, so the save can't be exported."

  function Gen3Save.ownerOf(bytes)
    local blocks = Gen3Save.readBlocks(bytes)
    if not blocks then return nil end
    return Gen3Save.readFields(blocks.sb2, { L.SB2[1], L.SB2[4], L.SB2[5] }, {})
  end

  function Gen3Save.templateBelongs(c, save)
    if type(c) ~= "table" or type(save) ~= "table" then return false end
    return c.trainerId == num(save.trainerId, -1) % 65536
      and c.secretId == num(save.secretId, -1) % 65536
      and c.name == trunc(save.name, L.PLAYER_NAME_LENGTH)
  end

  local function mailSpecies(mon)
    local ok, Mail = pcall(require, "src.core.game3.mail")
    local species = num(mon.species or mon.speciesId, 0)
    if ok and Mail.speciesToMailSpecies then return Mail.speciesToMailSpecies(species, mon.personality) end
    return species
  end

  function Gen3Save.fromPortSave(save, opts)
    opts = opts or {}
    local c, blocks, orig
    local md = type(save.modData) == "table" and save.modData or {}
    local candidates = { opts.template, md.cartImage }
    local damaged
    for i = 1, 2 do
      local source = candidates[i]
      if not c and source ~= nil and source ~= false then
        local tpl = ImagePack.unpack(source)
        if type(tpl) ~= "string" then
          damaged = true
        else
          c, blocks = Gen3Save.decode(tpl)
          if not c then
            damaged = true
          elseif not Gen3Save.templateBelongs(c, save) then
            c, blocks = nil, nil
          else
            orig = Gen3Save.decode(tpl)
          end
        end
      end
    end
    if not c and damaged then return nil, Gen3Save.MSG.damagedTemplate end
    if not c then c, blocks = freshCart(), nil end
    if not opts.toNational then return nil, Gen3Save.MSG.noData end
    local tplTower = c.trainerTowerBest
    local tid, sid = num(save.trainerId, 0) % 65536, num(save.secretId, 0) % 65536
    local function cartMail(r)
      if type(r) ~= "table" or (num(r.itemId, 0) == 0 and L.FAMILY ~= "rs"
          and not (L.FAMILY == "emerald" and r._recordMixNativeBytes)) then return nil end
      local full = num(r.trainerId, 0) % U32
      local rt = full % 65536
      return { words = type(r.words) == "table" and r.words or {}, playerName = r.playerName, species = num(r.species, 0),
        itemId = num(r.itemId, 0), trainerId = rt, _rsNativeBytes = r._rsNativeBytes, _rsNewMail = r._rsNewMail,
        _recordMixNativeBytes = L.FAMILY == "emerald" and r._recordMixNativeBytes or nil,
        trainerIdRaw = ((L.FAMILY == "rs" or (L.FAMILY == "emerald" and r._recordMixNativeBytes)) and full)
          or (full >= 65536 and full or (rt == tid and rt + sid * 65536 or rt)) }
    end
    local pool = {}
    for i = 1, L.MAIL.count do pool[i] = cartMail(type(save.mail) == "table" and save.mail[i] or nil) end
    local function mailIndex(mon, cm)
      if not isMailItem(cm.heldItem) then return L.MAIL_NONE end
      local idx = tonumber(mon.mail)
      if idx and idx % 1 == 0 and idx >= 0 and idx < L.MAIL.count and pool[idx + 1] and pool[idx + 1].itemId ~= 0 then return idx end
      -- src/mail_data.c:41
      for id = 0, L.MAIL_PARTY_SLOTS - 1 do
        if not pool[id + 1] or pool[id + 1].itemId == 0 then
          pool[id + 1] = { words = {}, playerName = save.name, trainerId = tid, trainerIdRaw = tid + sid * 65536,
            species = mailSpecies(mon), itemId = cm.heldItem }
          return id
        end
      end
      return L.MAIL_NONE
    end
    local ctx = {
      mailIndex = mailIndex,
      trainerId = num(save.trainerId, 0) % 65536,
      secretId = num(save.secretId, 0) % 65536,
      gender = num(save.gender, 0) == 1 and 1 or 0,
      playerName = save.name,
      metGame = opts.metGame,
      itemId = opts.itemId,
      speciesName = opts.speciesName,
      speciesFromNational = opts.speciesFromNational,
    }
    if type(opts.abilities) == "table" then
      ctx.abilities = function() return opts.abilities end
    elseif opts.version then
      local abilityTable
      ctx.abilities = function()
        if abilityTable == nil then
          local okS, SaveConvert = pcall(require, "src.save_convert.SaveConvert")
          abilityTable = okS and SaveConvert.gen3CacheTable and SaveConvert.gen3CacheTable(opts.version, "pokemon/abilities.lua") or false
        end
        return abilityTable or nil
      end
    end

    c.name = trunc(save.name, L.PLAYER_NAME_LENGTH)
    c.rivalName = trunc(save.rivalName, L.PLAYER_NAME_LENGTH)
    c.gender = ctx.gender
    c.trainerId, c.secretId = ctx.trainerId, ctx.secretId
    local pt = type(save.playTime) == "table" and save.playTime or (type(save.playtime) == "table" and save.playtime) or {}
    c.playHours = clamp(num(pt.hours, 0), 0, 999)
    c.playMinutes = clamp(num(pt.minutes, 0), 0, 59)
    c.playSeconds = clamp(num(pt.seconds, 0), 0, 59)
    c.playVBlanks = clamp(num(pt.vblanks, 0), 0, 59)
    local po = portOptions(save, opts.version)
    c.options = c.options or {}
    for _, f in ipairs(L.OPTIONS_BITS) do
      if f[1] ~= "regionMapZoom" then c.options[f[1]] = num(po[f[1]], c.options[f[1]] or 0) end
    end
    c.options.buttonMode = num(po.buttonMode, c.options.buttonMode or 0)
    c.buttonMode = c.options.buttonMode
    c.money = clamp(num(save.money, 0), 0, 999999)
    c.coins = clamp(num(save.coins, 0), 0, 9999)
    c.berryPowder = num(save.berryPowder, 0)
    c.registeredItem = save.registeredItem ~= nil and ((opts.itemId and opts.itemId(save.registeredItem)) or num(save.registeredItem, 0)) or 0
    c.gcnLinkFlags = num(save.gcnLinkFlags, 0)
    c.flashLevel = num(save.flashLevel, 0)

    local x, y = num(save.x, 0), num(save.y, 0)
    local here = Gen3Save.cartWarp({ map = save.map, warpId = -1, x = x, y = y })
    if not here then return nil, Gen3Save.MSG.noMap end
    local layout = opts.mapLayoutId and opts.mapLayoutId(here.group, here.num)
    local sameMap = orig and orig.location.group == here.group and orig.location.num == here.num
    if not layout and sameMap then layout = orig.mapLayoutId end
    if not layout then return nil, Gen3Save.MSG.noData end
    c.location, c.posX, c.posY, c.mapLayoutId = here, x, y, layout
    local warpFlags = num(save.specialSaveWarpFlags, 0)
    local cont = band(warpFlags, L.CONTINUE_GAME_WARP) ~= 0 and Gen3Save.cartWarp(save.continueGameWarp) or nil
    -- src/overworld.c:1706
    c.continueGameWarp = cont or here
    c.specialSaveWarpFlags = bor(warpFlags, L.CONTINUE_GAME_WARP) % 256
    if sameMap and x == orig.posX and y == orig.posY and warpFlags == orig.specialSaveWarpFlags then
      c.location, c.continueGameWarp, c.specialSaveWarpFlags = orig.location, orig.continueGameWarp, orig.specialSaveWarpFlags
    end
    if orig and not sameMap then c.resetMapState = true end
    c.playerFacing = nil
    if orig and orig.player and (L.FACING[orig.player.facing] or "down") ~= save.facing then
      for code, name in pairs(L.FACING) do if name == save.facing then c.playerFacing = code end end
    end
    c.dynamicWarp = Gen3Save.cartWarp(save.dynamicWarp) or L.EMPTY_WARP
    c.escapeWarp = Gen3Save.cartWarp(save.escapeWarp) or L.EMPTY_WARP
    local ci = type(save.modData) == "table" and type(save.modData.cartImport) == "table" and save.modData.cartImport or {}
    local heal = Gen3Save.cartWarp(ci.lastHealLocation) or (opts.healWarp and opts.healWarp(save.healMap, tonumber(save.healX), tonumber(save.healY)))
    if heal then
      c.lastHealLocation = heal
    elseif not blocks then
      return nil, Gen3Save.MSG.noData
    end

    c.party = {}
    for i, m in ipairs(type(save.party) == "table" and save.party or {}) do
      if i > L.PARTY_SIZE then break end
      c.party[i] = Gen3Save.fromPortMon(m, ctx, true)
    end

    local st = type(save.storage) == "table" and save.storage or {}
    local S = L.STORAGE
    c.storage = { currentBox = clamp(num(st.currentBox, 1) - 1, 0, S.totalBoxes - 1), boxes = {} }
    for b = 1, S.totalBoxes do
      local pb = type(st.boxes) == "table" and type(st.boxes[b]) == "table" and st.boxes[b] or {}
      local box = { name = cartBoxName(pb.name, b), wallpaper = cartWallpaper(pb.wallpaper, b), mons = {} }
      for key, m in pairs(type(pb.mons) == "table" and pb.mons or {}) do
        local sl = tonumber(key)
        if sl and sl >= 1 and sl <= S.inBox and type(m) == "table" then box.mons[sl] = Gen3Save.fromPortMon(m, ctx, false) end
      end
      c.storage.boxes[b] = box
    end
    for i, m in ipairs(c.party) do
      if m.missingSpecies then return nil, Gen3Save.MSG.badSpecies:format(m.missingSpecies, "party slot " .. i) end
    end
    for b, box in ipairs(c.storage.boxes) do
      for sl, m in pairs(box.mons) do
        if m.missingSpecies then
          return nil, Gen3Save.MSG.badSpecies:format(m.missingSpecies, ("box %d slot %d"):format(b, sl))
        end
      end
    end
    c.notes = c.notes or {}
    c.pcItems = itemList(st.items, L.PC_ITEMS.count, ctx, c.notes, "PC item storage")
    local pockets = type(save.bag) == "table" and type(save.bag.pockets) == "table" and save.bag.pockets or {}
    c.pockets = {}
    for _, p in ipairs(L.POCKETS) do c.pockets[p.key] = itemList(pockets[p.key], p.count, ctx) end

    local T = flagTables()
    local flags = {}
    for _, id in ipairs(c.flags or {}) do
      if id <= L.TEMP_FLAGS_END then flags[id] = true end
    end
    for k, v in pairs(type(save.flags) == "table" and save.flags or {}) do
      local id = v == true and resolveId(k, T.FLAGS, "FLAG_")
      if id and id > L.TEMP_FLAGS_END and id < L.FLAGS_COUNT then flags[id] = true end
    end
    local vars = {}
    for k, v in pairs(type(save.vars) == "table" and save.vars or {}) do
      local id = resolveId(k, T.VARS, "VAR_")
      local value = num(v, 0) % 65536
      if id and id >= L.VARS.first and id < L.VARS.first + L.VARS.count and value ~= 0 then vars[id] = value end
    end
    local dex = type(save.dex) == "table" and save.dex or {}
    local N = resolved().national
    local pdx = type(save.pokedex) == "table" and save.pokedex or nil
    if pdx and tonumber(pdx.mode) then
      c.dexMode, c.dexOrder = math.floor(tonumber(pdx.mode)), math.floor(tonumber(pdx.order) or 0)
    end
    if not blocks and L.RSE_NATIONAL_VAR and vars[L.RSE_NATIONAL_VAR] == nil then
      -- src/event_data.c:71
      vars[L.RSE_NATIONAL_VAR] = L.RSE_NATIONAL_VALUE
      flags[L.RSE_NATIONAL_FLAG] = true
    end
    -- src/event_data.c:99
    if dex.national == true or dex.nationalUnlocked == true or dex.isNationalUnlocked == true
        or save.national_dex_unlocked == true or flags[N.flag] or vars[N.var] == N.varValue then
      if L.DEX_MODE_NATIONAL and not (orig and orig.dexNationalMagic == N.magic) then
        -- pokeemerald/src/event_data.c:69
        c.dexMode, c.dexOrder = L.DEX_MODE_NATIONAL, 0
      end
      c.dexNationalMagic = N.magic
      vars[N.var] = N.varValue
      flags[N.flag] = true
    else
      c.dexNationalMagic = 0
    end
    c.flags = bitList(flags)
    c.vars = vars

    local seen, owned = {}, {}
    local function mark(set, species)
      local nat = opts.toNational(num(species, 0))
      if nat and nat >= 1 and nat <= 52 * 8 then set[nat - 1] = true end
    end
    for sp, v in pairs(type(dex.seen) == "table" and dex.seen or {}) do if v then mark(seen, sp) end end
    for _, key in ipairs({ "owned", "caught" }) do
      for sp, v in pairs(type(dex[key]) == "table" and dex[key] or {}) do if v then mark(owned, sp) end end
    end
    for _, nat in ipairs(type(ci.dexSeen) == "table" and ci.dexSeen or {}) do seen[nat - 1] = true end
    for _, nat in ipairs(type(ci.dexOwned) == "table" and ci.dexOwned or {}) do owned[nat - 1] = true end
    -- src/pokedex_screen.c:2252
    for i in pairs(owned) do seen[i] = true end
    local function withHigh(set, origList)
      local out = {}
      for i in pairs(set) do out[i] = true end
      for _, i in ipairs(origList or {}) do
        if i >= L.NATIONAL_DEX_SPECIES then out[i] = true end
      end
      return bitList(out)
    end
    c.dexSeen = withHigh(seen, orig and orig.dexSeen)
    c.dexSeen1 = withHigh(seen, orig and orig.dexSeen1)
    c.dexSeen2 = withHigh(seen, orig and orig.dexSeen2)
    c.dexOwned = withHigh(owned, orig and orig.dexOwned)
    c.unownPersonality = num(dex.unownPersonality, c.unownPersonality or 0)
    c.spindaPersonality = num(dex.spindaPersonality, c.spindaPersonality or 0)

    c.gameStats = {}
    for k, v in pairs(type(save.gameStats) == "table" and save.gameStats or {}) do
      local id = tonumber(k) or STAT_ALIASES[k]
      local value = num(v, 0) % U32
      if id and id >= 0 and id < L.GAME_STATS.count and value ~= 0 and value > (c.gameStats[id] or 0) then
        c.gameStats[id] = value
      end
    end
    c.easyChatProfile = c.easyChatProfile or {}
    for i = 1, L.PORT_PROFILE_WORDS do
      local w = type(save.easyChatProfile) == "table" and save.easyChatProfile[i]
      c.easyChatProfile[i] = num(w, c.easyChatProfile[i] or L.EC_WORD_UNDEFINED)
    end

    local md = type(save.modData) == "table" and save.modData or {}
    local daycareKey = L.FAMILY == "rs" and tostring(save.version or opts.version or L.GAME) .. "_daycare" or L.DAYCARE_SAVE_KEY
    local dcRoot = type(md[daycareKey]) == "table" and md[daycareKey] or {}
    local dc = type(dcRoot.daycare) == "table" and dcRoot.daycare or {}
    local dsteps = type(dc.steps) == "table" and dc.steps or {}
    c.daycare = { mons = {}, steps = {}, mail = {}, offspringPersonality = num(dc.offspringPersonality, 0) % (L.DAYCARE.offspringKind == "u32" and U32 or 65536),
      stepCounter = num(dc.stepCounter, 0) % 256 }
    local function daycareMail(m)
      if L.FAMILY == "emerald" and type(m) == "table" and m._recordMixNativeBytes then
        local cross = require("src.core.game3.link.rs_record_cross_bytes")
        return cross.readMail(Gen3Save, cross.renderMail(Gen3Save, m, nil, true), true)
      end
      local message = type(m) == "table" and cartMail(m.message)
      if not message then return nil end
      return { message = message, otName = L.FAMILY == "rs" and tostring(m.otName or "") or trunc(m.otName, L.PLAYER_NAME_LENGTH),
        monName = L.FAMILY == "rs" and tostring(m.monName or "") or trunc(m.monName, L.POKEMON_NAME_LENGTH),
        _rsNativeBytes = L.FAMILY == "rs" and m._rsNativeBytes or nil,
        _recordMixNativeBytes = L.FAMILY == "emerald" and m._recordMixNativeBytes or nil }
    end
    for i = 1, 2 do
      c.daycare.mons[i] = type(dc[i]) == "table" and Gen3Save.fromPortMon(dc[i], ctx, false) or nil
      c.daycare.steps[i] = num(dsteps[i], 0)
      c.daycare.mail[i] = daycareMail(type(dc.mail) == "table" and dc.mail[i] or nil)
    end
    if L.ROUTE5_DAYCARE then
      local r5 = type(dcRoot.route5Daycare) == "table" and dcRoot.route5Daycare or {}
      c.route5Daycare = { mon = type(r5.mon) == "table" and Gen3Save.fromPortMon(r5.mon, ctx, false) or nil,
        steps = num(r5.steps, 0), mail = daycareMail(r5.mail) }
    end

    c.mail = {}
    for i = 1, L.MAIL.count do c.mail[i] = pool[i] or false end
    local fameSrc = type(md.fameChecker) == "table" and md.fameChecker
      or (type(save.fameChecker) == "table" and save.fameChecker) or nil
    local oldFame = c.fameChecker or {}
    if not L.FAME_CHECKER then
      c.fameChecker = nil
    elseif fameSrc then
      c.fameChecker = {}
      for i = 1, L.FAME_CHECKER.count do
        local rec = type(fameSrc[i]) == "table" and fameSrc[i] or {}
        c.fameChecker[i] = { pickState = num(rec.pickState, 0), flavorTextFlags = num(rec.flavorTextFlags, 0),
          unk = (oldFame[i] or {}).unk }
      end
    elseif not blocks then
      -- src/fame_checker.c:1140
      c.fameChecker = {}
      for i = 1, L.FAME_CHECKER.count do c.fameChecker[i] = { pickState = 0, flavorTextFlags = 0 } end
      c.fameChecker[L.FAMECHECKER_OAK + 1].pickState = L.FCPICKSTATE_COLORED
    else
      c.fameChecker = nil
    end
    if L.REGISTERED_TEXTS and type(save.registeredTexts) == "table" then
      c.registeredTexts = {}
      for i = 1, L.REGISTERED_TEXTS.count do c.registeredTexts[i] = tostring(save.registeredTexts[i] or "") end
    elseif not blocks then
      -- src/union_room_chat.c:1430
      c.registeredTexts = opts.registeredTextDefaults and opts.registeredTextDefaults() or nil
    else
      c.registeredTexts = nil
    end
    local tower = type(md.trainerTower) == "table" and type(md.trainerTower.records) == "table" and md.trainerTower.records
    if not L.TRAINER_TOWER then
      c.trainerTowerBest = nil
    elseif tower then
      c.trainerTowerBest = {}
      for i = 1, L.TRAINER_TOWER.count do
        local rec = type(tower[i]) == "table" and tower[i] or {}
        c.trainerTowerBest[i] = clamp(num(rec.bestTime, L.TRAINER_TOWER_MAX_TIME), 0, L.TRAINER_TOWER_MAX_TIME)
      end
    elseif not blocks then
      -- src/new_game.c:151
      c.trainerTowerBest = {}
    else
      c.trainerTowerBest = nil
    end
    if not blocks then
      -- src/easy_chat.c:440
      c.easyChatBattle = { start = L.DEFAULT_BATTLE_START_WORDS, won = {}, lost = {} }
      if L.DEFAULT_EASY_CHAT then
        local C = consts()
        local function words(list)
          local out = {}
          for i, w in ipairs(list) do out[i] = C:require("easy_chat", w[1]) * 2 ^ L.EC_MASK_BITS + w[2] end
          return out
        end
        local D = L.DEFAULT_EASY_CHAT
        c.easyChatBattle = { start = words(D.start), won = words(D.won), lost = words(D.lost) }
      end
      -- src/new_game.c:130
      c.clearLinkRecords = true
    else
      c.easyChatBattle, c.clearLinkRecords = nil, nil
    end
    if L.DEFAULT_EASY_CHAT and type(save.easyChatBattleStart) == "table" then
      local base = c.easyChatBattle or {}
      local out = {}
      for k, f in pairs({ start = "easyChatBattleStart", won = "easyChatBattleWon", lost = "easyChatBattleLost" }) do
        out[k] = {}
        for i = 1, L.EASY_CHAT_BATTLE.count do
          local w = type(save[f]) == "table" and save[f][i]
          out[k][i] = num(w, (base[k] or {})[i] or L.EC_WORD_UNDEFINED)
        end
      end
      c.easyChatBattle = out
    end

    local r = save.roamer
    if type(r) == "table" then
      local src = type(r.ivs) == "table" and r.ivs or {}
      local alias = { atk = "attack", def = "defense", spe = "speed", spa = "spAtk", spd = "spDef" }
      local named = {}
      for _, k in ipairs(L.IV_KEYS) do named[k] = src[k] or src[alias[k]] end
      local ivs, ivw = statTable(type(r.ivs) == "number" and r.ivs or named, L.IV_KEYS, 31), 0
      for i, k in ipairs(L.IV_KEYS) do ivw = ivw + ivs[k] * 2 ^ ((i - 1) * 5) end
      if tonumber(r.ivWord) then ivw = ivw + math.floor(tonumber(r.ivWord) / 2 ^ 30) % 4 * 2 ^ 30 end
      c.roamer = {
        ivs = ivw,
        personality = num(r.pid or r.personality, 0) % U32,
        species = num(r.species, 0),
        hp = num(r.hp, 0),
        level = num(r.level, 0),
        status = num(r.statusNum, type(r.status) == "number" and r.status or 0) % 256,
        active = r.active and 1 or 0,
      }
    end

    local teams, hofSkipped = {}, false
    for _, team in ipairs(type(save.hallOfFameTeams) == "table" and save.hallOfFameTeams or {}) do
      local rec = {}
      for _, m in ipairs(type(team) == "table" and team or {}) do
        if num(m.species, 0) >= 512 then
          if not hofSkipped then
            c.notes = c.notes or {}
            c.notes[#c.notes + 1] = Gen3Save.MSG.hofSpecies
            hofSkipped = true
          end
        else
          rec[#rec + 1] = {
            tid = num(m.trainerId, 0) % 65536 + (num(m.otSecretId, 0) % 65536) * 65536,
            personality = num(m.personality, 0) % U32,
            species = num(m.species, 0),
            level = num(m.level, 0),
            nickname = trunc(m.nickname, L.HOF.nickLength),
          }
        end
      end
      if #rec > 0 then teams[#teams + 1] = rec end
    end
    c.hallOfFame = teams
    local key = Gen3Save.resolveKey(c, save, blocks)
    if blocks and key ~= c.encryptionKey and L.TRAINER_TOWER and c.trainerTowerBest == nil then
      c.trainerTowerBest = tplTower
    end
    c.encryptionKey = key
    local boxFlags = Gen3Save.boxFlagsOf(save)
    if boxFlags ~= nil then c.boxFlags = boxFlags end
    if ctx.abilitiesMissing then return nil, Gen3Save.MSG.noData end
    return c, blocks
  end

  function Gen3Save.keyValid(k, powder)
    k = tonumber(k)
    if not k or k % 1 ~= 0 or k <= 0 or k >= U32 then return false end
    if L.FAMILY == "emerald" then return k ~= 1 end
    return k ~= (tonumber(powder) or 0) % U32
  end

  local function fnv(h, s)
    for i = 1, #s do
      h = bxor(h, s:byte(i)) % U32
      h = (h * 0x193 + (h % 256) * 16777216) % U32
    end
    return h
  end

  function Gen3Save.deriveKey(tid, sid, playthroughId, powder)
    local seed = ("%d:%d:%s"):format(num(tid, 0) % 65536, num(sid, 0) % 65536, tostring(playthroughId or ""))
    local h = fnv(2166136261, seed)
    for salt = 0, 255 do
      local k = fnv(h, string.char(salt))
      if k ~= 1 and k ~= (tonumber(powder) or 0) % U32 and Gen3Save.keyValid(k, powder) then return k end
    end
    return 0x9E3779B9
  end

  function Gen3Save.storedKey(save)
    if type(save) ~= "table" then return nil end
    if L.FAMILY == "emerald" then return tonumber(save.encryptionKey) end
    local md = type(save.modData) == "table" and save.modData or {}
    return tonumber(md.cartKey)
  end

  function Gen3Save.resolveKey(c, save, blocks)
    if L.UNENCRYPTED then return 0 end
    if blocks and Gen3Save.keyValid(c.encryptionKey, c.berryPowder) then return c.encryptionKey end
    local stored = Gen3Save.storedKey(save)
    if Gen3Save.keyValid(stored, c.berryPowder) then return stored end
    local meta = type(save.meta) == "table" and save.meta or {}
    return Gen3Save.deriveKey(c.trainerId, c.secretId, meta.playthroughId, c.berryPowder)
  end

  function Gen3Save.slotTemplate(save)
    local md = type(save) == "table" and type(save.modData) == "table" and save.modData or nil
    return md and type(md.cartImage) == "string" and ImagePack.unpack(md.cartImage) or nil
  end

  function Gen3Save.recordMixTvPrefix(save, shows)
    if L.FAMILY ~= "emerald" and L.FAMILY ~= "rs" then return nil end
    local template = Gen3Save.slotTemplate(save)
    local blocks
    if template then local _, b = Gen3Save.decode(template); if type(b) == "table" then blocks = b end end
    local buf = newBuf(L.BLOCKS[2].size, blocks and blocks.sb1)
    local off = L.RSE.sb1.tvShows
    if not blocks then
      local md = type(save.modData) == "table" and save.modData or {}
      local imported = type(md.cartImport) == "table" and md.cartImport or {}
      local raw = imported.recordMixTvBytes256
      if type(raw) == "table" then
        for i = 1, 256 do buf:w8(off + i - 1, num(raw[i], 0) % 256) end
      end
    end
    local port = require(L.FAMILY == "rs" and "src.save_convert.gen3_port.rs" or "src.save_convert.gen3_port.rse")
    port.SECTIONS.tvShows.write({ L = L, codec = Gen3Save, sb1 = buf:str(), w1 = buf }, { tvShows = shows })
    return buf:str():sub(off + 1, off + 256)
  end

  function Gen3Save.exportPort(save, opts)
    local c, blocks = Gen3Save.fromPortSave(save, opts)
    if not c then return nil, blocks end
    return Gen3Save.finishFlash(c, blocks, Gen3Save.encodeBlocks(c, blocks)), #(c.notes or {}) > 0 and table.concat(c.notes, " ") or nil
  end

  function Gen3Save.finishFlash(c, blocks, encoded)
    local hof = #c.hallOfFame > 0 and Gen3Save.encodeHof(c.hallOfFame) or nil
    if blocks and hof then
      local orig = Gen3Save.decode(blocks.image)
      local function same(a, b)
        if type(a) ~= type(b) then return false end
        if type(a) ~= "table" then return a == b end
        for k, v in pairs(a) do if not same(v, b[k]) then return false end end
        for k in pairs(b) do if a[k] == nil then return false end end
        return true
      end
      if orig and same(orig.hallOfFame, c.hallOfFame) then hof = nil end
    end
    local counter = blocks and (blocks.counter + 1) % U32 or 1
    local flash = Gen3Save.buildFlash(encoded, { counter = counter, image = blocks and blocks.image, hof = hof })
    return flash .. (blocks and #blocks.image == L.FLASH_SIZE and blocks.trailer or "")
  end

  function Gen3Save.gameOf(c)
    local codes = L.GAME_CODES or {}
    local tally = {}
    local function count(m)
      if m and not m.isEgg and m.otId == c.trainerId and m.otSecretId == c.secretId and codes[m.metGame] then
        tally[m.metGame] = (tally[m.metGame] or 0) + 1
      end
    end
    for _, m in ipairs(c.party or {}) do count(m) end
    for _, box in ipairs(c.storage and c.storage.boxes or {}) do
      for _, m in pairs(box.mons) do count(m) end
    end
    local best, n = nil, 0
    for code, k in pairs(tally) do
      if k > n or (k == n and best and code < best) then best, n = code, k end
    end
    return best and codes[best] or nil
  end

  function Gen3Save.stampImport(save, bytes, cart, version)
    save.modData = type(save.modData) == "table" and save.modData or {}
    save.modData.cartImage = ImagePack.pack(bytes) or bytes
    save.modData.cartGame = Gen3Save.gameOf(cart) or version
    if not L.UNENCRYPTED and L.FAMILY ~= "emerald" then save.modData.cartKey = cart.encryptionKey end
    return save, cart.olderSlot and Gen3Save.MSG.olderSlot or nil
  end

  if L.PORT then require(L.PORT).install(Gen3Save) end
  return Gen3Save
end
local FRLG = require("src.save_convert.Gen3Layout")
local M = build(FRLG)
local CODECS = { [FRLG] = M }
local SHARED = { "codec", "forVersion", "layoutFor", "sniff", "sniffMessage" }

local function word(s, o)
  local a, b, c, d = s:byte(o + 1, o + 4)
  return a + b * 256 + c * 65536 + d * 16777216
end

local function zero(s, from, to)
  for i = from + 1, math.min(to, #s) do
    if s:byte(i) ~= 0 then return false end
  end
  return true
end

function M.codec(L)
  local c = CODECS[L]
  if c then return c end
  c = build(L)
  for _, k in ipairs(SHARED) do c[k] = M[k] end
  CODECS[L] = c
  return c
end

function M.layoutFor(version)
  return FRLG.forVersion(version)
end

function M.forVersion(version)
  return M.codec(FRLG.forVersion(version))
end

-- pokeemerald/src/save.c:57
function M.sniff(bytes)
  if type(bytes) ~= "string" then return nil end
  local fr = M.readBlocks(bytes)
  -- pokefirered/src/new_game.c:121
  if fr and word(fr.sb2, FRLG.MARKER.off) == FRLG.MARKER.value then return "frlg" end
  local em = M.codec(FRLG.family("emerald")).readBlocks(bytes)
  if not em then return nil end
  -- pokeruby/src/save.c:110
  if zero(em.sb2, 0x890, #em.sb2) and zero(em.sb1, 0x3AC0, #em.sb1) then return "rs" end
  return "emerald"
end

function M.repairJapaneseNames(root)
  local codec, seen, changed = M.forVersion("emerald"), {}, false
  local function walk(t)
    if seen[t] then return end
    seen[t] = true
    if type(t.personality) == "number" and codec.repairJapaneseNames(t) then changed = true end
    for _, v in pairs(t) do
      if type(v) == "table" then walk(v) end
    end
  end
  if type(root) == "table" then walk(root) end
  return changed
end

M.FAMILY_NAMES = { frlg = "FireRed/LeafGreen", emerald = "Emerald", rs = "Ruby/Sapphire" }

function M.sniffMessage(bytes)
  local fam = M.sniff(bytes)
  return fam, fam and M.FAMILY_NAMES[fam] or nil
end

return M
