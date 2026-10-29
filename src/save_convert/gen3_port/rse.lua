local bit = require("bit")

local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift

local Rse = {}

local U32 = 4294967296

local function u8(s, o) return s:byte(o + 1) end
local function u16(s, o) local a, b = s:byte(o + 1, o + 2); return a + b * 256 end
local function u32(s, o) local a, b, c, d = s:byte(o + 1, o + 4); return a + b * 256 + c * 65536 + d * 16777216 end
local function s8(s, o) local v = u8(s, o); return v >= 128 and v - 256 or v end
local function s16(s, o) local v = u16(s, o); return v >= 32768 and v - 65536 or v end
local function field(v, shift, width) return band(rshift(v, shift), lshift(1, width) - 1) end
local function num(v, d) return tonumber(v) or d or 0 end
local function flag(v) return v == true or (type(v) == "number" and v ~= 0) end

local function copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = copy(x) end
  return out
end

local function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end
Rse.same = same

local function bytesAt(s, off, n)
  local out = {}
  for i = 1, n do out[i] = u8(s, off + i - 1) end
  return out
end

local function putBytes(w, off, list, n, fill)
  for i = 1, n do w:w8(off + i - 1, num(list and list[i], fill or 0)) end
end

local function readTime(s, o)
  return { days = s16(s, o), hours = s8(s, o + 2), minutes = s8(s, o + 3), seconds = s8(s, o + 4) }
end

local function writeTime(w, o, t)
  t = type(t) == "table" and t or {}
  w:w16(o, num(t.days) % 65536)
  w:w8(o + 2, num(t.hours) % 256)
  w:w8(o + 3, num(t.minutes) % 256)
  w:w8(o + 4, num(t.seconds) % 256)
end

Rse.SECTIONS = {}
local function section(def)
  Rse.SECTIONS[#Rse.SECTIONS + 1] = def
  Rse.SECTIONS[def.name] = def
  return def
end
Rse.FRLG_SECTIONS = {}
function Rse.defineSection(def, families)
  families = families or { emerald = true }
  if families.emerald then section(def) end
  if families.frlg then
    Rse.FRLG_SECTIONS[#Rse.FRLG_SECTIONS + 1] = def
    Rse.FRLG_SECTIONS[def.name] = def
  end
  return def
end

-- pokeemerald/include/global.h:529
section({
  name = "rtc",
  fields = { "localTimeOffset", "lastBerryTreeUpdate" },
  read = function(x)
    local o = x.L.RSE.sb2
    return { localTimeOffset = readTime(x.sb2, o.localTimeOffset), lastBerryTreeUpdate = readTime(x.sb2, o.lastBerryTreeUpdate) }
  end,
  write = function(x, v)
    local o = x.L.RSE.sb2
    writeTime(x.w2, o.localTimeOffset, v.localTimeOffset)
    writeTime(x.w2, o.lastBerryTreeUpdate, v.lastBerryTreeUpdate)
  end,
})

-- pokeemerald/include/global.h:532
section({
  name = "encryptionKey",
  fields = { "encryptionKey" },
  read = function(x) return { encryptionKey = u32(x.sb2, x.L.KEY_OFF) } end,
})

-- pokeemerald/include/global.berry.h:63
section({
  name = "berryTrees",
  fields = { "berryTrees" },
  read = function(x)
    local o, trees = x.L.RSE.sb1, {}
    for id = 0, o.berryTreeCount - 1 do
      local b = o.berryTrees + id * 8
      local any = false
      for i = 0, 7 do if u8(x.sb1, b + i) ~= 0 then any = true end end
      if any then
        local st, rw = u8(x.sb1, b + 1), u8(x.sb1, b + 5)
        trees[id] = {
          berry = u8(x.sb1, b), stage = field(st, 0, 7), stopGrowth = field(st, 7, 1) == 1,
          minutesUntilNextStage = u16(x.sb1, b + 2), berryYield = u8(x.sb1, b + 4),
          regrowthCount = field(rw, 0, 4), watered1 = field(rw, 4, 1) == 1, watered2 = field(rw, 5, 1) == 1,
          watered3 = field(rw, 6, 1) == 1, watered4 = field(rw, 7, 1) == 1,
        }
      end
    end
    return { berryTrees = trees }
  end,
  write = function(x, v)
    local o, trees = x.L.RSE.sb1, type(v.berryTrees) == "table" and v.berryTrees or {}
    for id = 0, o.berryTreeCount - 1 do
      local b, t = o.berryTrees + id * 8, trees[id]
      if type(t) ~= "table" then
        x.w1:fill(b, 8, 0)
      else
        x.w1:w8(b, num(t.berry))
        x.w1:w8(b + 1, num(t.stage) % 128 + (flag(t.stopGrowth) and 128 or 0))
        x.w1:w16(b + 2, num(t.minutesUntilNextStage))
        x.w1:w8(b + 4, num(t.berryYield))
        x.w1:w8(b + 5, num(t.regrowthCount) % 16 + (flag(t.watered1) and 16 or 0) + (flag(t.watered2) and 32 or 0)
          + (flag(t.watered3) and 64 or 0) + (flag(t.watered4) and 128 or 0))
        x.w1:w16(b + 6, 0)
      end
    end
  end,
})

-- pokeemerald/include/global.h:1025
section({
  name = "decorations",
  fields = { "playerRoomDecorations", "decorationInventory" },
  read = function(x)
    local o, L = x.L.RSE.sb1, x.L
    local inv, off = {}, o.decorationInventory
    for cat = 0, 7 do
      inv[cat] = bytesAt(x.sb1, off, L.DECOR_CATEGORY_SIZES[cat])
      off = off + L.DECOR_CATEGORY_SIZES[cat]
    end
    return { playerRoomDecorations = bytesAt(x.sb1, o.playerRoomDecorations, L.DECOR_MAX_PLAYERS_HOUSE), decorationInventory = inv }
  end,
  write = function(x, v)
    local o, L = x.L.RSE.sb1, x.L
    putBytes(x.w1, o.playerRoomDecorations, v.playerRoomDecorations, L.DECOR_MAX_PLAYERS_HOUSE)
    local inv, off = type(v.decorationInventory) == "table" and v.decorationInventory or {}, o.decorationInventory
    for cat = 0, 7 do
      putBytes(x.w1, off, inv[cat], L.DECOR_CATEGORY_SIZES[cat])
      off = off + L.DECOR_CATEGORY_SIZES[cat]
    end
  end,
})

local SB_PARTY = { personality = 0, moves = 24, species = 72, heldItems = 84, levels = 96, EVs = 102 }

-- pokeemerald/include/global.h:556
section({
  name = "secretBases",
  fields = { "secretBases", "playerRoomDecorationPositions" },
  read = function(x)
    local o, L, dec = x.L.RSE.sb1, x.L, x.codec.decodeString
    local bases = {}
    for i = 0, o.secretBaseCount - 1 do
      local b = o.secretBases + i * o.secretBaseSize
      local f1 = u8(x.sb1, b + 1)
      local p = b + 52
      local party = { personality = {}, moves = {}, species = {}, heldItems = {}, levels = {}, EVs = {} }
      for k = 1, 6 do
        party.personality[k] = u32(x.sb1, p + SB_PARTY.personality + (k - 1) * 4)
        party.species[k] = u16(x.sb1, p + SB_PARTY.species + (k - 1) * 2)
        party.heldItems[k] = u16(x.sb1, p + SB_PARTY.heldItems + (k - 1) * 2)
        party.levels[k] = u8(x.sb1, p + SB_PARTY.levels + k - 1)
        party.EVs[k] = u8(x.sb1, p + SB_PARTY.EVs + k - 1)
      end
      for k = 1, 24 do party.moves[k] = u16(x.sb1, p + SB_PARTY.moves + (k - 1) * 2) end
      bases[i + 1] = {
        secretBaseId = u8(x.sb1, b), toRegister = field(f1, 0, 4), gender = field(f1, 4, 1),
        battledOwnerToday = field(f1, 5, 1), registryStatus = field(f1, 6, 2),
        trainerName = dec(x.sb1, b + 2, L.PLAYER_NAME_LENGTH), trainerId = bytesAt(x.sb1, b + 9, 4),
        language = u8(x.sb1, b + 13), numSecretBasesReceived = u16(x.sb1, b + 14), numTimesEntered = u8(x.sb1, b + 16),
        decorations = bytesAt(x.sb1, b + 18, 16), decorationPositions = bytesAt(x.sb1, b + 34, 16), party = party,
      }
    end
    return { secretBases = bases,
      playerRoomDecorationPositions = bytesAt(x.sb1, o.playerRoomDecorationPositions, L.DECOR_MAX_PLAYERS_HOUSE) }
  end,
  write = function(x, v)
    local o, L, enc = x.L.RSE.sb1, x.L, x.codec.encodeString
    putBytes(x.w1, o.playerRoomDecorationPositions, v.playerRoomDecorationPositions, L.DECOR_MAX_PLAYERS_HOUSE)
    local bases = type(v.secretBases) == "table" and v.secretBases or {}
    for i = 0, o.secretBaseCount - 1 do
      local b, s = o.secretBases + i * o.secretBaseSize, bases[i + 1]
      x.w1:fill(b, o.secretBaseSize, 0)
      if type(s) == "table" then
        x.w1:w8(b, num(s.secretBaseId))
        x.w1:w8(b + 1, num(s.toRegister) % 16 + (num(s.gender) % 2) * 16 + (num(s.battledOwnerToday) % 2) * 32
          + (num(s.registryStatus) % 4) * 64)
        x.w1:bytes(b + 2, enc(s.trainerName, L.PLAYER_NAME_LENGTH, 0xFF))
        putBytes(x.w1, b + 9, s.trainerId, 4)
        x.w1:w8(b + 13, num(s.language))
        x.w1:w16(b + 14, num(s.numSecretBasesReceived))
        x.w1:w8(b + 16, num(s.numTimesEntered))
        putBytes(x.w1, b + 18, s.decorations, 16)
        putBytes(x.w1, b + 34, s.decorationPositions, 16)
        local p, party = b + 52, type(s.party) == "table" and s.party or {}
        for k = 1, 6 do
          x.w1:w32(p + SB_PARTY.personality + (k - 1) * 4, num((party.personality or {})[k]))
          x.w1:w16(p + SB_PARTY.species + (k - 1) * 2, num((party.species or {})[k]))
          x.w1:w16(p + SB_PARTY.heldItems + (k - 1) * 2, num((party.heldItems or {})[k]))
          x.w1:w8(p + SB_PARTY.levels + k - 1, num((party.levels or {})[k]))
          x.w1:w8(p + SB_PARTY.EVs + k - 1, num((party.EVs or {})[k]))
        end
        for k = 1, 24 do x.w1:w16(p + SB_PARTY.moves + (k - 1) * 2, num((party.moves or {})[k])) end
      end
    end
  end,
})

-- pokeemerald/include/global.h:596
local BLOCK_FIELDS = { "color", "spicy", "dry", "sweet", "bitter", "sour", "feel" }
section({
  name = "pokeblocks",
  fields = { "pokeblocks" },
  read = function(x)
    local o, list = x.L.RSE.sb1, {}
    for i = 0, o.pokeblockCount - 1 do
      local b, blk = o.pokeblocks + i * 8, {}
      for k, f in ipairs(BLOCK_FIELDS) do blk[f] = u8(x.sb1, b + k - 1) end
      list[i + 1] = blk
    end
    return { pokeblocks = list }
  end,
  write = function(x, v)
    local o, list = x.L.RSE.sb1, type(v.pokeblocks) == "table" and v.pokeblocks or {}
    for i = 0, o.pokeblockCount - 1 do
      local b, blk = o.pokeblocks + i * 8, list[i + 1]
      x.w1:fill(b, 8, 0)
      if type(blk) == "table" then
        for k, f in ipairs(BLOCK_FIELDS) do x.w1:w8(b + k - 1, num(blk[f])) end
      end
    end
  end,
})

-- pokeemerald/include/global.h:993
section({
  name = "weather",
  fields = { "savedWeather", "weatherCycleStage" },
  read = function(x) return { savedWeather = u8(x.sb1, 0x2E), weatherCycleStage = u8(x.sb1, 0x2F) } end,
  write = function(x, v)
    x.w1:w8(0x2E, num(v.savedWeather))
    x.w1:w8(0x2F, num(v.weatherCycleStage))
  end,
})

-- pokeemerald/include/global.h:1015
section({
  name = "matchCall",
  fields = { "trainerRematchStepCounter", "trainerRematches", "regionMapZoom" },
  read = function(x)
    local o, rem = x.L.RSE.sb1, {}
    for i = 0, o.trainerRematchCount - 1 do
      local r = u8(x.sb1, o.trainerRematches + i)
      if r ~= 0 then rem[i] = r end
    end
    -- pokeemerald/include/global.h:524
    return { trainerRematchStepCounter = u16(x.sb1, o.trainerRematchStepCounter), trainerRematches = rem,
      regionMapZoom = field(u16(x.sb2, 0x14), 11, 1) == 1 }
  end,
  write = function(x, v)
    local o, rem = x.L.RSE.sb1, type(v.trainerRematches) == "table" and v.trainerRematches or {}
    x.w1:w16(o.trainerRematchStepCounter, num(v.trainerRematchStepCounter))
    for i = 0, o.trainerRematchCount - 1 do x.w1:w8(o.trainerRematches + i, num(rem[i])) end
    local word = u16(x.w2:str(), 0x14)
    word = band(word, bit.bnot(lshift(1, 11))) + (flag(v.regionMapZoom) and 2048 or 0)
    x.w2:w16(0x14, word)
  end,
})

-- pokeemerald/include/global.h:1036
local OUTBREAK = {
  { "outbreakPokemonSpecies", 0, "u16" }, { "outbreakLocationMapNum", 2, "u8" }, { "outbreakLocationMapGroup", 3, "u8" },
  { "outbreakPokemonLevel", 4, "u8" }, { "outbreakUnused1", 5, "u8" }, { "outbreakUnused2", 6, "u16" },
  { "outbreakUnused3", 16, "u8" }, { "outbreakPokemonProbability", 17, "u8" }, { "outbreakDaysLeft", 18, "u16" },
}
-- pokeemerald/include/global.tv.h:502
local GABBY_BITS = {
  { 10, 0, 1, "battleTookMoreThanOneTurn" }, { 10, 1, 1, "playerLostAMon" }, { 10, 2, 1, "playerUsedHealingItem" },
  { 10, 3, 1, "playerThrewABall" }, { 10, 4, 1, "onAir" }, { 10, 5, 3, "valA_5", true },
  { 11, 0, 1, "battleTookMoreThanOneTurn2" }, { 11, 1, 1, "playerLostAMon2" }, { 11, 2, 1, "playerUsedHealingItem2" },
  { 11, 3, 1, "playerThrewABall2" }, { 11, 4, 4, "valB_4", true },
}
section({
  name = "tv",
  fields = { "pokeNews", "gabbyAndTyData", "outbreakPokemonSpecies", "outbreakLocationMapNum", "outbreakLocationMapGroup",
    "outbreakPokemonLevel", "outbreakUnused1", "outbreakUnused2", "outbreakPokemonMoves", "outbreakUnused3",
    "outbreakPokemonProbability", "outbreakDaysLeft" },
  read = function(x)
    local o, out = x.L.RSE.sb1, { pokeNews = {} }
    for i = 0, o.pokeNewsCount - 1 do
      local b = o.pokeNews + i * 4
      -- pokeemerald/include/global.tv.h:495
      out.pokeNews[i] = { kind = u8(x.sb1, b), state = u8(x.sb1, b + 1), dayCountdown = u16(x.sb1, b + 2) }
    end
    for _, f in ipairs(OUTBREAK) do
      out[f[1]] = (f[3] == "u16" and u16 or u8)(x.sb1, o.outbreak + f[2])
    end
    out.outbreakPokemonMoves = {}
    for i = 1, 4 do out.outbreakPokemonMoves[i] = u16(x.sb1, o.outbreak + 8 + (i - 1) * 2) end
    local g = o.gabbyAndTy
    local gb = { mon1 = u16(x.sb1, g), mon2 = u16(x.sb1, g + 2), lastMove = u16(x.sb1, g + 4),
      quote = { [0] = u16(x.sb1, g + 6) }, mapnum = u8(x.sb1, g + 8), battleNum = u8(x.sb1, g + 9) }
    for _, f in ipairs(GABBY_BITS) do
      local v = field(u8(x.sb1, g + f[1]), f[2], f[3])
      if f[5] then gb[f[4]] = v else gb[f[4]] = v == 1 end
    end
    out.gabbyAndTyData = gb
    return out
  end,
  write = function(x, v)
    local o = x.L.RSE.sb1
    local news = type(v.pokeNews) == "table" and v.pokeNews or {}
    for i = 0, o.pokeNewsCount - 1 do
      local b, n = o.pokeNews + i * 4, type(news[i]) == "table" and news[i] or {}
      x.w1:w8(b, num(n.kind))
      x.w1:w8(b + 1, num(n.state))
      x.w1:w16(b + 2, num(n.dayCountdown))
    end
    for _, f in ipairs(OUTBREAK) do
      if f[3] == "u16" then x.w1:w16(o.outbreak + f[2], num(v[f[1]])) else x.w1:w8(o.outbreak + f[2], num(v[f[1]])) end
    end
    local moves = type(v.outbreakPokemonMoves) == "table" and v.outbreakPokemonMoves or {}
    for i = 1, 4 do x.w1:w16(o.outbreak + 8 + (i - 1) * 2, num(moves[i])) end
    local g, gb = o.gabbyAndTy, type(v.gabbyAndTyData) == "table" and v.gabbyAndTyData or {}
    x.w1:w16(g, num(gb.mon1))
    x.w1:w16(g + 2, num(gb.mon2))
    x.w1:w16(g + 4, num(gb.lastMove))
    x.w1:w16(g + 6, num(type(gb.quote) == "table" and gb.quote[0], 0xFFFF))
    x.w1:w8(g + 8, num(gb.mapnum))
    x.w1:w8(g + 9, num(gb.battleNum))
    local b10, b11 = 0, 0
    for _, f in ipairs(GABBY_BITS) do
      local raw = gb[f[4]]
      local val = f[5] and num(raw) % lshift(1, f[3]) or (flag(raw) and 1 or 0)
      if f[1] == 10 then b10 = bor(b10, lshift(val, f[2])) else b11 = bor(b11, lshift(val, f[2])) end
    end
    x.w1:w8(g + 10, b10)
    x.w1:w8(g + 11, b11)
  end,
})

-- pokeemerald/include/global.h:1061
section({
  name = "giftRibbons",
  fields = { "giftRibbons" },
  read = function(x) local o = x.L.RSE.sb1; return { giftRibbons = bytesAt(x.sb1, o.giftRibbons, o.giftRibbonCount) } end,
  write = function(x, v) local o = x.L.RSE.sb1; putBytes(x.w1, o.giftRibbons, v.giftRibbons, o.giftRibbonCount) end,
})

-- pokeemerald/include/global.h:641
section({
  name = "dewfordTrends",
  fields = { "dewfordTrends", "unlockedTrendySayings" },
  read = function(x)
    local o, list = x.L.RSE.sb1, {}
    for i = 0, o.dewfordTrendCount - 1 do
      local b = o.dewfordTrends + i * 8
      local w = u16(x.sb1, b)
      list[i + 1] = { trendiness = field(w, 0, 7), maxTrendiness = field(w, 7, 7), gainingTrendiness = field(w, 14, 1) == 1,
        rand = u16(x.sb1, b + 2), words = { u16(x.sb1, b + 4), u16(x.sb1, b + 6) } }
    end
    return { dewfordTrends = list, unlockedTrendySayings = bytesAt(x.sb1, o.unlockedTrendySayings, 5) }
  end,
  write = function(x, v)
    local o, list = x.L.RSE.sb1, type(v.dewfordTrends) == "table" and v.dewfordTrends or {}
    for i = 0, o.dewfordTrendCount - 1 do
      local b, t = o.dewfordTrends + i * 8, type(list[i + 1]) == "table" and list[i + 1] or {}
      local word = u16(x.w1:str(), b)
      x.w1:w16(b, num(t.trendiness) % 128 + (num(t.maxTrendiness) % 128) * 128 + (flag(t.gainingTrendiness) and 16384 or 0)
        + band(word, 0x8000))
      x.w1:w16(b + 2, num(t.rand))
      local words = type(t.words) == "table" and t.words or {}
      x.w1:w16(b + 4, num(words[1]))
      x.w1:w16(b + 6, num(words[2]))
    end
    putBytes(x.w1, o.unlockedTrendySayings, v.unlockedTrendySayings, 5)
  end,
})

-- pokeemerald/include/global.h:752
section({
  name = "contests",
  fields = { "contestWinners", "contestLinkResults" },
  read = function(x)
    local o, list = x.L.RSE.sb1, {}
    for i = 0, o.contestWinnerCount - 1 do
      local b = o.contestWinners + i * 32
      list[i + 1] = { personality = u32(x.sb1, b), trainerId = u32(x.sb1, b + 4), species = u16(x.sb1, b + 8),
        contestCategory = u8(x.sb1, b + 10), contestRank = u8(x.sb1, b + 30) }
    end
    local res, r = {}, x.L.RSE.sb2.contestLinkResults
    for cat = 0, 4 do
      res[cat + 1] = {}
      for rank = 0, 3 do res[cat + 1][rank + 1] = u16(x.sb2, r + (cat * 4 + rank) * 2) end
    end
    return { contestWinners = list, contestLinkResults = res }
  end,
  write = function(x, v)
    local o, list = x.L.RSE.sb1, type(v.contestWinners) == "table" and v.contestWinners or {}
    for i = 0, o.contestWinnerCount - 1 do
      local b, w = o.contestWinners + i * 32, type(list[i + 1]) == "table" and list[i + 1] or {}
      x.w1:w32(b, num(w.personality))
      x.w1:w32(b + 4, num(w.trainerId))
      x.w1:w16(b + 8, num(w.species))
      x.w1:w8(b + 10, num(w.contestCategory))
      x.w1:w8(b + 30, num(w.contestRank))
    end
    local res, r = type(v.contestLinkResults) == "table" and v.contestLinkResults or {}, x.L.RSE.sb2.contestLinkResults
    for cat = 0, 4 do
      for rank = 0, 3 do x.w2:w16(r + (cat * 4 + rank) * 2, num((res[cat + 1] or {})[rank + 1])) end
    end
  end,
})

-- pokeemerald/include/global.h:731
section({
  name = "linkBattleRecords",
  fields = { "linkBattleRecords" },
  read = function(x)
    local LR, list = x.L.LINK_BATTLE_RECORDS, {}
    local s = LR.block == "sb2" and x.sb2 or x.sb1
    for i = 0, LR.count - 1 do
      local b = LR.off + i * LR.size
      if u8(s, b) ~= 0xFF and u8(s, b) ~= 0 then
        list[#list + 1] = { name = x.codec.decodeString(s, b, 8), trainerId = u16(s, b + 8),
          wins = u16(s, b + 10), losses = u16(s, b + 12), draws = u16(s, b + 14) }
      end
    end
    return { linkBattleRecords = list }
  end,
  write = function(x, v)
    local LR, list = x.L.LINK_BATTLE_RECORDS, type(v.linkBattleRecords) == "table" and v.linkBattleRecords or {}
    local w = LR.block == "sb2" and x.w2 or x.w1
    for i = 0, LR.count - 1 do
      local b, e = LR.off + i * LR.size, list[i + 1]
      w:fill(b, LR.size, 0)
      if type(e) == "table" and tostring(e.name or "") ~= "" then
        w:bytes(b, x.codec.encodeString(e.name, 8))
        w:w16(b + 8, num(e.trainerId))
        w:w16(b + 10, num(e.wins))
        w:w16(b + 12, num(e.losses))
        w:w16(b + 14, num(e.draws))
      else
        -- pokeemerald/src/battle_records.c:94
        w:w8(b, 0xFF)
      end
    end
  end,
})

-- pokeemerald/include/global.h:849
section({
  name = "waldaPhrase",
  fields = { "waldaPhrase" },
  read = function(x)
    local o = x.L.RSE.sb1.waldaPhrase
    return { waldaPhrase = {
      colors = { u16(x.sb1, o), u16(x.sb1, o + 2) },
      phrase = x.codec.decodeString(x.sb1, o + 4, 16),
      iconId = u8(x.sb1, o + 20),
      patternId = u8(x.sb1, o + 21),
      unlocked = u8(x.sb1, o + 22) ~= 0,
    } }
  end,
  write = function(x, v)
    local o = x.L.RSE.sb1.waldaPhrase
    local w = type(v.waldaPhrase) == "table" and v.waldaPhrase or {}
    local colors = type(w.colors) == "table" and w.colors or { 0x7B35, 0x6186 }
    x.w1:w16(o, num(colors[1], 0x7B35))
    x.w1:w16(o + 2, num(colors[2], 0x6186))
    x.w1:bytes(o + 4, x.codec.encodeString(tostring(w.phrase or ""), 16))
    x.w1:w8(o + 20, num(w.iconId) % 256)
    x.w1:w8(o + 21, num(w.patternId) % 256)
    x.w1:w8(o + 22, flag(w.unlocked) and 1 or 0)
  end,
})

-- pokeemerald/include/global.h:859
section({
  name = "trainerNameRecords",
  fields = { "trainerNameRecords" },
  read = function(x)
    local o, list = x.L.TRAINER_NAME_RECORDS, {}
    for i = 0, o.count - 1 do
      local b = o.off + i * 12
      local id = u32(x.sb1, b)
      if id ~= 0 or u8(x.sb1, b + 4) ~= 0xFF and u8(x.sb1, b + 4) ~= 0 then
        list[#list + 1] = { trainerId = id % 65536, name = x.codec.decodeString(x.sb1, b + 4, 8) }
      end
    end
    return { trainerNameRecords = list }
  end,
  write = function(x, v)
    local o, list = x.L.TRAINER_NAME_RECORDS, type(v.trainerNameRecords) == "table" and v.trainerNameRecords or {}
    for i = 0, o.count - 1 do
      local b, e = o.off + i * 12, list[i + 1]
      x.w1:fill(b, 12, 0)
      if type(e) == "table" then
        x.w1:w32(b, num(e.trainerId))
        x.w1:bytes(b + 4, x.codec.encodeString(e.name, 8, 0xFF))
      end
    end
  end,
})

-- pokeemerald/include/global.h:1013
section({
  name = "berryBlender",
  fields = { "berryBlenderRecords" },
  read = function(x)
    local o = x.L.RSE.sb1.berryBlenderRecords
    return { berryBlenderRecords = { u16(x.sb1, o), u16(x.sb1, o + 2), u16(x.sb1, o + 4) } }
  end,
  write = function(x, v)
    local o, r = x.L.RSE.sb1.berryBlenderRecords, type(v.berryBlenderRecords) == "table" and v.berryBlenderRecords or {}
    for i = 0, 2 do x.w1:w16(o + i * 2, num(r[i + 1])) end
  end,
})

-- pokeemerald/include/global.h:378
section({
  name = "frontier",
  fields = { "frontier" },
  read = function(x)
    local Util = require("src.core.game3.rse.frontier.util")
    local base = Util.CART_BASE
    local f = Util.fromCart(function(off, size)
      if size == 1 then return u8(x.sb2, base + off) end
      if size == 2 then return u16(x.sb2, base + off) end
      return u32(x.sb2, base + off)
    end)
    local out = {}
    for _, row in ipairs(Util.CART_LAYOUT) do out[row[1]] = f[row[1]] end
    return { frontier = out }
  end,
  write = function(x, v)
    if type(v.frontier) ~= "table" then return end
    local Util = require("src.core.game3.rse.frontier.util")
    local base = Util.CART_BASE
    local keep = {}
    for _, row in ipairs(Util.CART_LAYOUT) do
      if row[3] == "bits" then keep[row[2]] = (keep[row[2]] or 255) - (2 ^ row[5] - 1) * 2 ^ row[4] end
    end
    Util.toCart(function(off, size, value)
      value = num(value)
      if keep[off] then value = band(x.w2.b[base + off] or 0, keep[off]) + value % 256 end
      if size == 1 then x.w2:w8(base + off, value % 256)
      elseif size == 2 then x.w2:w16(base + off, value)
      else x.w2:w32(base + off, value) end
    end, { frontier = v.frontier })
  end,
})

section({ name = "apprentice", fields = {}, template = { "playerApprentice", "apprentices" } })

-- pokeemerald/include/global.h:746
section({
  name = "recordMixingGift",
  fields = { "recordMixingGift" },
  read = function(x)
    local b = x.L.RSE.sb1.recordMixingGift
    return { recordMixingGift = { checksum = u32(x.sb1, b), unk0 = u8(x.sb1, b + 4), quantity = u8(x.sb1, b + 5),
      itemId = u16(x.sb1, b + 6) } }
  end,
  write = function(x, v)
    local b = x.L.RSE.sb1.recordMixingGift
    local g = type(v.recordMixingGift) == "table" and v.recordMixingGift or {}
    x.w1:fill(b, 16, 0)
    x.w1:w32(b, num(g.checksum) % U32)
    x.w1:w8(b + 4, num(g.unk0) % 256)
    x.w1:w8(b + 5, num(g.quantity) % 256)
    x.w1:w16(b + 6, num(g.itemId) % 65536)
  end,
})
section({ name = "lottery", fields = {}, vars = true })
section({ name = "easyChat", fields = {} })

local function context(codec, blocks, w1, w2, notes)
  return { L = codec.L, codec = codec, sb1 = blocks.sb1, sb2 = blocks.sb2, w1 = w1, w2 = w2, notes = notes }
end

local function merge(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" and type(dst[k]) == "table" then merge(dst[k], v) else dst[k] = v end
  end
end

function Rse.readSections(codec, blocks, out, sections)
  local x = context(codec, blocks)
  for _, s in ipairs(sections or Rse.SECTIONS) do
    if s.read then merge(out, s.read(x)) end
  end
  return out
end

local function pick(save, fields)
  local out = {}
  for _, f in ipairs(fields) do out[f] = copy(save[f]) end
  return out
end

local function hasNativeMixBytes(value)
  if type(value) ~= "table" then return false end
  if type(value._recordMixNativeBytes) == "table" then return true end
  for _, child in pairs(value) do
    if type(child) == "table" and hasNativeMixBytes(child) then return true end
  end
  return false
end
local NATIVE_MIX_SECTIONS = { secretBases = true, tvShows = true, oldMan = true, frontierRecords = true }

function Rse.writeSections(codec, encoded, template, save, sections)
  local newBuf = codec.newBuf
  local w1, w2 = newBuf(#encoded.sb1, encoded.sb1), newBuf(#encoded.sb2, encoded.sb2)
  local base = template and context(codec, template) or nil
  local notes = {}
  for _, s in ipairs(sections or Rse.SECTIONS) do
    if s.write then
      local want = pick(save, s.fields)
      local present = false
      for _, f in ipairs(s.fields) do if save[f] ~= nil then present = true end end
      if present then
        local t1, t2 = newBuf(#encoded.sb1, w1:str()), newBuf(#encoded.sb2, w2:str())
        local tx = context(codec, encoded, t1, t2, notes)
        local nativeCross = (codec.L.FAMILY == "emerald" or codec.L.FAMILY == "rs")
          and NATIVE_MIX_SECTIONS[s.name] and hasNativeMixBytes(want)
        local cross = nativeCross and require("src.core.game3.link.rs_record_cross_bytes")
        if nativeCross then cross.beforeSection(tx, s.name, want) end
        s.write(tx, want)
        if nativeCross then cross.afterSection(tx, s.name, want) end
        local changed = true
        if base then
          local back = s.read(context(codec, { sb1 = t1:str(), sb2 = t2:str() }))
          changed = nativeCross or not same(back, s.read(base))
        end
        if changed then w1, w2 = t1, t2 end
      end
    end
  end
  local boxFlags = codec.boxFlagsOf and codec.boxFlagsOf(save)
  if boxFlags ~= nil and codec.BOX_FLAGS_OFFSET then w1:w8(codec.BOX_FLAGS_OFFSET, boxFlags) end
  return { sb2 = w2:str(), sb1 = w1:str(), storage = encoded.storage, notes = notes,
    nativeRecordMixMail = codec.L.FAMILY == "emerald" and hasNativeMixBytes(save.mail) }
end

local function splice(s, off, part)
  return s:sub(1, off) .. part .. s:sub(off + #part + 1)
end

local function mailKey(m)
  if type(m) ~= "table" or num(m.itemId) == 0 then return "-" end
  local w = {}
  for i = 1, 9 do w[i] = tostring(num((m.words or {})[i], 0xFFFF)) end
  return table.concat({ num(m.itemId), num(m.species), num(m.trainerId) % 65536, tostring(m.playerName or ""),
    table.concat(w, ",") }, "|")
end

function Rse.keepUnchanged(codec, encoded, template)
  local L = codec.L
  local a, b = template.sb1, encoded.sb1
  local P = L.PARTY_OFFSET
  local len = L.PARTY_SIZE * L.PARTY_MON_SIZE
  if b:sub(P + 1, P + len) ~= a:sub(P + 1, P + len) and u8(a, 0x234) == u8(b, 0x234) then
    local same_ = true
    for i = 0, u8(b, 0x234) - 1 do
      local o = P + i * L.PARTY_MON_SIZE
      if b:sub(o + 1, o + L.PARTY_MON_SIZE) ~= a:sub(o + 1, o + L.PARTY_MON_SIZE) then same_ = false end
    end
    if same_ then b = splice(b, P, a:sub(P + 1, P + len)) end
  end
  local M = L.MAIL
  local mlen = M.count * M.size
  if L.FAMILY ~= "rs" and not encoded.nativeRecordMixMail
      and b:sub(M.off + 1, M.off + mlen) ~= a:sub(M.off + 1, M.off + mlen) then
    local same_ = true
    for i = 0, M.count - 1 do
      local o = M.off + i * M.size
      local ra = { itemId = u16(a, o + M.itemId), species = u16(a, o + M.species), trainerId = u32(a, o + M.trainerId),
        playerName = codec.decodeString(a, o + M.playerName, M.playerNameLength):gsub(" +$", ""), words = {} }
      local rb = { itemId = u16(b, o + M.itemId), species = u16(b, o + M.species), trainerId = u32(b, o + M.trainerId),
        playerName = codec.decodeString(b, o + M.playerName, M.playerNameLength):gsub(" +$", ""), words = {} }
      for k = 1, M.wordCount do
        ra.words[k] = u16(a, o + (k - 1) * 2)
        rb.words[k] = u16(b, o + (k - 1) * 2)
      end
      if mailKey(ra) ~= mailKey(rb) then same_ = false end
    end
    if same_ then b = splice(b, M.off, a:sub(M.off + 1, M.off + mlen)) end
  end
  encoded.sb1 = b
  return encoded
end

function Rse.portRoamer(r)
  if type(r) ~= "table" or (r.species or 0) == 0 then return nil end
  local ivs = {}
  local keys = { "hp", "atk", "def", "spe", "spa", "spd" }
  for i, k in ipairs(keys) do ivs[k] = field(r.ivs, (i - 1) * 5, 5) end
  return { active = r.active ~= 0, species = r.species, level = r.level, status = r.status, hp = r.hp,
    ivs = ivs, ivWord = r.ivs, personality = r.personality, cool = r.cool, beauty = r.beauty, cute = r.cute,
    smart = r.smart, tough = r.tough, history = { false, false, false } }
end

function Rse.cartRoamer(r, old)
  if type(r) ~= "table" then return old end
  local ivw = tonumber(r.ivWord)
  if type(r.ivs) == "table" then
    ivw = 0
    local keys = { "hp", "atk", "def", "spe", "spa", "spd" }
    for i, k in ipairs(keys) do ivw = ivw + (num(r.ivs[k]) % 32) * 2 ^ ((i - 1) * 5) end
    if tonumber(r.ivWord) then ivw = ivw + math.floor(tonumber(r.ivWord) / 2 ^ 30) * 2 ^ 30 end
  elseif type(r.ivs) == "number" then
    ivw = r.ivs
  end
  local status = type(r.status) == "number" and r.status or num(r.statusNum)
  return { ivs = (ivw or 0) % U32, personality = num(r.personality or r.pid) % U32, species = num(r.species),
    hp = num(r.hp), level = num(r.level), status = status % 256, cool = num(r.cool), beauty = num(r.beauty),
    cute = num(r.cute), smart = num(r.smart), tough = num(r.tough), active = r.active and 1 or 0 }
end

function Rse.augment(codec, save, c, blocks, sections)
  save.rivalName = nil
  -- pokeemerald/src/random.c:8
  save.rng = { value = 0, value2 = 0, wild = 0 }
  save.roamer = Rse.portRoamer(c.roamer)
  Rse.readSections(codec, blocks, save, sections)
  if type(save.modData) == "table" then
    save.modData.fameChecker, save.modData.trainerTower = nil, nil
    if type(save.modData.cartImport) == "table" then
      save.modData.cartImport.mapLayoutId = c.mapLayoutId
    end
  end
  local okR, Rtc = pcall(require, "src.core.game3.rtc")
  if okR and Rtc.anchorToLastUpdate then Rtc.anchorToLastUpdate(save) end
  return save
end

-- pokeemerald/src/pokedex.c:4263
function Rse.finishImport(save, data)
  local national = type(data) == "table" and type(data.national) == "table" and data.national.toSpecies
  local ci = type(save.modData) == "table" and save.modData.cartImport
  if type(national) ~= "table" or type(ci) ~= "table" then return save end
  save.dex = save.dex or {}
  local dex = save.dex
  dex.seen, dex.owned, dex.caught = dex.seen or {}, dex.owned or {}, dex.caught or {}
  for _, nat in ipairs(ci.dexSeen or {}) do
    local sp = national[nat]
    if sp then dex.seen[sp] = true end
  end
  for _, nat in ipairs(ci.dexOwned or {}) do
    local sp = national[nat]
    if sp then dex.owned[sp], dex.caught[sp] = true, true end
  end
  ci.dexSeen, ci.dexOwned = nil, nil
  return save
end

for _, name in ipairs({ "tv_shows", "records", "town", "frlg_extra" }) do
  require("src.save_convert.gen3_port.sections." .. name)(Rse)
end

function Rse.install(codec, sections)
  local toPortSave, fromPortSave = codec.toPortSave, codec.fromPortSave

  function codec.importPort(bytes, version)
    if type(bytes) ~= "string" then return nil, codec.message("size", 0) end
    local cart, blocks = codec.decode(bytes)
    if not cart then return nil, codec.message(blocks, #bytes) end
    if not codec.mapFor(cart.location.group, cart.location.num) then return nil, codec.MSG.corrupt end
    local save, note = codec.stampImport(Rse.augment(codec, toPortSave(cart, version), cart, blocks, sections), bytes, cart, version)
    return save, nil, note
  end

  function codec.fromPortSave(save, opts)
    local c, blocks = fromPortSave(save, opts)
    if not c then return nil, blocks end
    local orig = blocks and codec.decode(blocks.image)
    if orig and opts.healWarp and not same(c.lastHealLocation, orig.lastHealLocation) then
      local o = orig.lastHealLocation
      local was = codec.mapFor(o.group, o.num)
      local a = was and opts.healWarp(was, o.x, o.y)
      local b = type(save.healMap) == "string" and opts.healWarp(save.healMap, tonumber(save.healX), tonumber(save.healY))
      -- src/overworld.c:670
      if a and b and same(a, o) and same(a, b) then c.lastHealLocation = o end
    end
    c.roamer = Rse.cartRoamer(save.roamer, c.roamer)
    if save.savedWeather ~= nil then c.weather = num(save.savedWeather) % 256 end
    if save.weatherCycleStage ~= nil then c.weatherCycleStage = num(save.weatherCycleStage) % 256 end
    return c, blocks
  end

  function codec.exportPort(save, opts)
    local c, blocks = codec.fromPortSave(save, opts)
    if not c then return nil, blocks end
    local encoded = Rse.writeSections(codec, codec.encodeBlocks(c, blocks), blocks, save, sections)
    if blocks then encoded = Rse.keepUnchanged(codec, encoded, blocks) end
    for _, n in ipairs(c.notes or {}) do encoded.notes[#encoded.notes + 1] = n end
    return codec.finishFlash(c, blocks, encoded), #encoded.notes > 0 and table.concat(encoded.notes, " ") or nil
  end

  codec.port = Rse
  return codec
end

return Rse
