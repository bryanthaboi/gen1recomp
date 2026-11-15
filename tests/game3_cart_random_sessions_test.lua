#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local bit = require("bit")
local GameVersion = require("src.core.GameVersion")

local LABEL = "game3_cart_random_sessions_test"
local GAME
if os.getenv("POKEPORT_RANDOM_GAME") == "emerald" then
  GameVersion.set("emerald")
  require("src.import.gba.versions").select("emerald")
  require("tests.game3_cache").mount("emerald")
  local Dataset = require("src.core.game3.dataset")
  local cache = Dataset.cache()
  if not cache:read("data/generated/gba/native/manifest.lua") or not cache:read("data/generated/gba/pokemon/national.lua") then
    print("[skip] " .. LABEL .. ": no Emerald cache for identity "
      .. tostring(os.getenv("POKEPORT_IDENTITY") or "pokemon-love2d"))
    os.exit(0)
  end
  Dataset.mountExtractRoots()
  Dataset.hydrate({ data = {} })
  GAME = "emerald"
else
  GAME = require("tests.game3_cart_cache").mountOrSkip(LABEL)
  GameVersion.set(GAME)
  require("src.import.gba.versions").select(GAME)
end

local N = tonumber(os.getenv("POKEPORT_RANDOM_SESSIONS")) or 200
local SEED = tonumber(os.getenv("POKEPORT_RANDOM_SEED")) or 1
local ONLY = tonumber(os.getenv("POKEPORT_RANDOM_ONLY"))
local DUMP = os.getenv("POKEPORT_RANDOM_DUMP_DIR")
local VERBOSE = os.getenv("POKEPORT_RANDOM_VERBOSE") == "1"

local SaveConvert = require("src.save_convert.SaveConvert")
local Compat = require("src.save_convert.Compat")
local Gen3Save = require("src.save_convert.Gen3Save")
local Rse = require("src.save_convert.gen3_port.rse")
local Frlg = require("src.save_convert.gen3_port.frlg")
local Schema = require("src.core.game3.save_schema_firered")
local Party = require("src.core.game3.party")
local Bag = require("src.core.game3.bag")
local Storage = require("src.core.game3.storage")
local Mail = require("src.core.game3.mail")
local Dex = require("src.core.game3.dex")
local Flags = require("src.core.game3.scripting.flags")
local Pokemon = require("src.core.game3.pokemon")
local Daycare = require("src.core.game3.daycare")
local Roamer = require("src.core.game3.roamer")
local Options = require("src.core.game3.options")
local ItemsData = require("src.core.game3.items_data")
local SummaryData = require("src.core.game3.summary_data")
local Profile = require("src.core.game3.profile")
local Ribbons = require("src.core.game3.rse.ribbons")
local D = require("tests.save_compat._gen3_decode")
local Dataset = require("src.core.game3.dataset")

local CODEC = Gen3Save.forVersion(GAME)
local L = CODEC.L
local FAMILY = GAME == "emerald" and "emerald" or "frlg"
local SECTIONS = GAME == "emerald" and Rse.SECTIONS or Frlg.SECTIONS
local EMERALD = GAME == "emerald"
local U32 = 4294967296

local NATIONAL = assert(SaveConvert.gen3CacheTable(GAME, "pokemon/national.lua"), "pokemon/national.lua")
local SPECIES_NAMES = SaveConvert.gen3CacheTable(GAME, "pokemon/names.lua") or {}
local ITEM_PACK = assert(SaveConvert.gen3CacheTable(GAME, "items/pack.lua"), "items/pack.lua")
local MOVES = assert((SaveConvert.gen3CacheTable(GAME, "pokemon/battle_moves.lua") or {}).moves, "pokemon/battle_moves.lua")
local ABILITIES = SaveConvert.gen3CacheTable(GAME, "pokemon/abilities.lua")

local cache = Dataset.cache()

local function H_rng(seed)
  local state = seed % 2147483647
  if state <= 0 then state = state + 2147483646 end
  return function(n)
    state = (state * 48271) % 2147483647
    if n then return state % n end
    return state
  end
end

local function deepcopy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = deepcopy(x) end
  return out
end

local function merge(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" and type(dst[k]) == "table" then merge(dst[k], v) else dst[k] = deepcopy(v) end
  end
end

local VALID_SPECIES = {}
for sp = 1, 411 do
  if (sp <= 251 or sp >= 277) and NATIONAL.toNational[sp] then VALID_SPECIES[#VALID_SPECIES + 1] = sp end
end

local VALID_MOVES = {}
for id, row in pairs(MOVES) do
  if type(id) == "number" and id >= 1 and id <= 354 and type(row) == "table" then VALID_MOVES[#VALID_MOVES + 1] = id end
end
table.sort(VALID_MOVES)

local ITEMS_BY_POCKET, ALL_ITEMS, MAIL_ITEMS, KEY_ITEMS = {}, {}, {}, {}
for id, e in pairs(ITEM_PACK.items or {}) do
  if type(id) == "number" and id > 0 and type(e) == "table" and e.name and e.name ~= "????????" then
    local pocket = ItemsData.pocketOf(id)
    ITEMS_BY_POCKET[pocket] = ITEMS_BY_POCKET[pocket] or {}
    table.insert(ITEMS_BY_POCKET[pocket], id)
    ALL_ITEMS[#ALL_ITEMS + 1] = id
    if Mail.isMailItem(id) then MAIL_ITEMS[#MAIL_ITEMS + 1] = id end
    if pocket == "KEY_ITEMS" then KEY_ITEMS[#KEY_ITEMS + 1] = id end
  end
end
table.sort(ALL_ITEMS)
for _, list in pairs(ITEMS_BY_POCKET) do table.sort(list) end
table.sort(MAIL_ITEMS)
table.sort(KEY_ITEMS)
local HOLDABLE = {}
for _, id in ipairs(ALL_ITEMS) do
  if not Mail.isMailItem(id) and ItemsData.pocketOf(id) ~= "KEY_ITEMS" then HOLDABLE[#HOLDABLE + 1] = id end
end

local PREFIX = Profile.of(GAME).map.enginePrefix
local function engineMapId(pretName)
  local s = pretName:gsub("(%l)(%u)", "%1_%2"):gsub("(%u)(%u%l)", "%1_%2")
  return PREFIX .. s:upper()
end

local MAPS = {}
for g = 0, 60 do
  for n = 0, 200 do
    local raw = cache:read(("data/generated/gba/map_tree/maps/%d_%d/header.json"):format(g, n))
    if raw then
      local id = raw:match('"id"%s*:%s*"([^"]+)"')
      local width, height = tonumber(raw:match('"width"%s*:%s*(%d+)')), tonumber(raw:match('"height"%s*:%s*(%d+)'))
      local layout = tonumber(raw:match('"layoutId"%s*:%s*(%d+)'))
      if id and width and height and layout and width > 0 and height > 0 then
        local eid, named = engineMapId(id), true
        if not CODEC.cartWarp({ map = eid, x = 0, y = 0 }) then eid, named = CODEC.mapFor(g, n), false end
        if eid then
          MAPS[#MAPS + 1] = { id = eid, group = g, num = n, width = width, height = height, layout = layout }
          if named then MAPS.byName = (MAPS.byName or 0) + 1 else MAPS.byCodec = (MAPS.byCodec or 0) + 1 end
        end
      end
    end
  end
end
table.sort(MAPS, function(a, b) return a.group * 1000 + a.num < b.group * 1000 + b.num end)
assert(#MAPS > 50, "map list from the cache headers: " .. #MAPS)
print(("[info] %d cached map headers: %d engine ids derived from the pret name, %d from the codec table")
  :format(#MAPS, MAPS.byName or 0, MAPS.byCodec or 0))

local FLAG_MAX = L.FLAGS_COUNT - 1
local NAT = Gen3Save.forVersion(GAME).resolved().national
local CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 "

local stats = {
  sessions = 0, exported = 0, compatErrors = 0, decodeFail = 0, fixedPoint = 0, r2 = 0, edit = 0,
  eggsParty = 0, eggsBox = 0, mailMons = 0, pcMail = 0, fullBoxes = 0, emptyParty = 0, fullParty = 0,
  boxMons = 0, partyMons = 0, shiny = 0, traded = 0, statusMons = 0, daycareMons = 0, daycareMail = 0,
  route5 = 0, roamer = 0, hofTeams = 0, nationalDex = 0, pcItems = 0, flagsSet = 0, varsSet = 0,
  bagItems = 0, sectionsMerged = 0, contest = 0, ribbons = 0, champion = 0, fateful = 0, trailingSpaceNick = 0,
  dynamicWarp = 0, escapeWarp = 0, registeredTexts = 0, fameTower = 0, sectionReads = 0, registeredItem = 0, gameStats = 0, linkRoomMaps = 0,
}
local failures, failureKinds, kindOrder = 0, {}, {}
local KNOWN = {
  { "contest", "B1 engine mon.contest is not exported or imported (Gen3Save reads cartExtra.contest only)" },
  { "ribbons", "B2 engine mon.ribbons/championRibbon/modernFatefulEncounter are not exported or imported" },
  { "championRibbon", "B2" },
  { "modernFatefulEncounter", "B2" },
  { "abilit", "B3 abilityNum = personality & 1 for single-ability species (pokefirered/src/pokemon.c:1855)" },
  { "SetContinueGameWarpToDynamicWarp", "E1 engine saveWarpFields drops dynamicWarp.warpId" },
  { "fixture withTemplate", "B4 dex bits above the last species are dropped even with an untouched template" },
}
local function knownBug(kind)
  for _, k in ipairs(KNOWN) do if kind:find(k[1], 1, true) then return k[2] end end
  return nil
end
local sessionFails, sessionUnknown = {}, {}

local CURRENT = { idx = 0 }

local function kindOf(path)
  return (path:gsub("%[%d+%]", "[]"):gsub("%.%d+", ".#"))
end

local function fail(stage, path, engine, cart)
  if CURRENT.dry then CURRENT.dry = CURRENT.dry + 1 return end
  failures = failures + 1
  local kind = stage .. " " .. kindOf(path)
  sessionFails[CURRENT.idx] = true
  if not knownBug(kind) then sessionUnknown[CURRENT.idx] = true end
  local rec = failureKinds[kind]
  if not rec then
    rec = { count = 0, sessions = {}, first = ("seed=%d session=%d %s %s engine=%s cart=%s"):format(SEED, CURRENT.idx,
      stage, path, tostring(engine), tostring(cart)) }
    failureKinds[kind] = rec
    kindOrder[#kindOrder + 1] = kind
  end
  rec.count = rec.count + 1
  if not rec.sessions[CURRENT.idx] then
    rec.sessions[CURRENT.idx] = true
    rec.sessionCount = (rec.sessionCount or 0) + 1
  end
  if VERBOSE then
    print(("[FAIL] seed=%d session=%d %s %s engine=%s cart=%s"):format(SEED, CURRENT.idx, stage, path,
      tostring(engine), tostring(cart)))
  end
end

local function same(stage, path, engine, cart)
  if engine ~= cart then fail(stage, path, engine, cart) return false end
  return true
end

local function randName(r, maxLen, allowEmpty, allowTrailing)
  local len = r(maxLen + (allowEmpty and 1 or 0)) + (allowEmpty and 0 or 1)
  local out = {}
  for i = 1, len do
    local c = r(#CHARS) + 1
    if (i == 1 or (i == len and not allowTrailing)) and CHARS:sub(c, c) == " " then c = 1 + r(26) end
    out[i] = CHARS:sub(c, c)
  end
  local s = table.concat(out)
  if s:match("^BOX%d+$") then s = "X" .. s:sub(2) end
  return s
end

local function pick(r, list) return list[r(#list) + 1] end

local function expForLevel(mon, level)
  local growth = tonumber(mon.growthRate) or Pokemon.growthRate(mon.species) or 0
  return SummaryData.expForLevel(growth, level)
end

local function speciesName(sp)
  return Pokemon.name(sp)
end

local function maxPpOf(move, bonus)
  local base = tonumber(MOVES[move] and MOVES[move].pp) or 5
  return math.floor(base * (5 + bonus) / 5)
end

local STATUSES = { "PSN", "BRN", "FRZ", "PAR", "TOX", "SLP" }

local function randomizeMon(s, mon, r, opts)
  opts = opts or {}
  local own = r(5) ~= 0
  if not own then
    mon.otId = r(65536)
    mon.otSecretId = r(65536)
    mon.otName = randName(r, 7)
    mon.ot = mon.otName
    mon.otGender = r(2)
    stats.traded = stats.traded + 1
  else
    mon.otId = s.trainerId
    mon.otSecretId = s.secretId
    mon.otName, mon.ot = s.name, s.name
    mon.otGender = Party.otGender(s)
  end
  local tid, sid = mon.otId % 65536, mon.otSecretId % 65536
  local pid
  if r(10) == 0 then
    local hi = r(65536)
    local lo = bit.bxor(bit.bxor(tid, sid), bit.bxor(hi, r(8))) % 65536
    pid = hi * 65536 + lo
    stats.shiny = stats.shiny + 1
  else
    pid = r(65536) * 65536 + r(65536)
  end
  mon.personality = pid
  mon.nature = Pokemon.natureId(pid)
  mon.ability = Pokemon.abilityId(mon.species, pid)
  mon.abilityId = mon.ability
  mon.gender = Pokemon.gender(mon.species, pid)
  local ivs = {}
  for _, k in ipairs({ "hp", "atk", "def", "spe", "spa", "spd" }) do ivs[k] = r(32) end
  mon.ivs = ivs
  local evs, left = {}, 510
  for _, k in ipairs({ "hp", "atk", "def", "spe", "spa", "spd" }) do
    local v = math.min(r(256), left)
    evs[k] = v
    left = left - v
  end
  mon.evs = evs
  if not mon.isEgg then
    local lvl = 1 + r(100)
    mon.level = lvl
    local lo = expForLevel(mon, lvl)
    local hi = lvl < 100 and expForLevel(mon, lvl + 1) - 1 or lo
    mon.exp = lo + (hi > lo and r(hi - lo + 1) or 0)
    mon.friendship = r(256)
    mon.happiness = mon.friendship
  else
    mon.eggCycles = r(256)
  end
  local moves, pp, maxPp = {}, {}, {}
  local bonuses = r(256)
  local count = 1 + r(4)
  local used = {}
  while #moves < count do
    local m = pick(r, VALID_MOVES)
    if not used[m] then
      used[m] = true
      moves[#moves + 1] = m
      local mx = maxPpOf(m, math.floor(bonuses / 4 ^ (#moves - 1)) % 4)
      maxPp[#moves] = mx
      pp[#moves] = r(mx + 1)
    end
  end
  mon.moves, mon.pp, mon.maxPp, mon.ppBonusesPacked = moves, pp, maxPp, bonuses
  if r(4) == 0 then
    local strain = 1 + r(15)
    mon.pokerus = strain * 16 + r(strain % 4 + 2)
  else
    mon.pokerus = 0
  end
  mon.metLocation = r(0xD5)
  mon.metLevel = mon.isEgg and 0 or r(101)
  mon.metGame = 1 + r(5)
  mon.pokeball = 1 + r(12)
  mon.markings = r(16)
  if not mon.isEgg then mon.language = pick(r, { 1, 2, 3, 4, 5, 7 }) end
  if not mon.isEgg and r(3) == 0 then
    mon.nickname = randName(r, 10, false, r(6) == 0)
    if mon.nickname:sub(-1) == " " then stats.trailingSpaceNick = stats.trailingSpaceNick + 1 end
  elseif not mon.isEgg then
    mon.nickname = ""
  end
  if r(2) == 0 then
    local it = pick(r, HOLDABLE)
    mon.item, mon.heldItem = it, it
  else
    mon.item, mon.heldItem = nil, nil
  end
  if EMERALD and r(3) == 0 then
    local c = require("src.core.game3.rse.pokeblock").contest(mon)
    for _, k in ipairs({ "cool", "beauty", "cute", "smart", "tough", "sheen" }) do c[k] = r(256) end
    stats.contest = stats.contest + 1
  end
  if EMERALD and r(3) == 0 then
    for _, f in ipairs(Ribbons.FIELDS) do
      if f.name ~= "unused" and f.name ~= "fateful" and r(3) == 0 then Ribbons.set(mon, f.name, r(2 ^ f.bits)) end
    end
    stats.ribbons = stats.ribbons + 1
  end
  if not mon.isEgg and r(8) == 0 then
    if EMERALD then Ribbons.set(mon, "champion", 1) else mon.championRibbon = true end
    stats.champion = stats.champion + 1
  end
  if r(12) == 0 then
    mon.modernFatefulEncounter = true
    stats.fateful = stats.fateful + 1
  end
  Pokemon.applyStats(mon)
  if opts.party then
    mon.hp = r(mon.maxHp + 1)
    if r(3) == 0 then
      local st = pick(r, STATUSES)
      mon.status = st
      if st == "SLP" then mon.sleep = 1 + r(7) end
      stats.statusMons = stats.statusMons + 1
    else
      mon.status, mon.sleep = nil, nil
    end
  else
    Storage.fullHealMon(mon)
  end
  return mon
end

local function scratchFor(s)
  return { party = {}, name = s.name, trainerId = s.trainerId, secretId = s.secretId, gender = s.gender,
    version = s.version, dex = { seen = {}, owned = {}, caught = {} } }
end

local function newMon(s, r, opts)
  local tmp = scratchFor(s)
  local sp = pick(r, VALID_SPECIES)
  local ok, code, mon
  if r(10) == 0 then
    ok, code, mon = Party.giveEgg(tmp, sp)
  else
    ok, code, mon = Party.giveMon(tmp, sp, 5, nil)
  end
  assert(ok and mon, "Party.giveMon")
  return randomizeMon(s, mon, r, opts)
end

local function randWarp(r)
  local m = pick(r, MAPS)
  return { map = m.id, warpId = r(10) == 0 and -1 or r(8), x = r(m.width), y = r(m.height) }
end

local LINK_ROOMS = {
  [PREFIX .. "BATTLE_COLOSSEUM_2P"] = true, [PREFIX .. "TRADE_CENTER"] = true, [PREFIX .. "RECORD_CORNER"] = true,
  [PREFIX .. "BATTLE_COLOSSEUM_4P"] = true, [PREFIX .. "UNION_ROOM"] = true, [PREFIX .. "UNION_ROOM_PLAZA"] = true,
}

local function sectionState(r)
  local sb1, sb2 = {}, {}
  for i = 1, L.BLOCKS[2].size do sb1[i] = string.char(r(256)) end
  for i = 1, L.BLOCKS[1].size do sb2[i] = string.char(r(256)) end
  local blocks = { sb1 = table.concat(sb1), sb2 = table.concat(sb2) }
  local vals = {}
  Rse.readSections(CODEC, blocks, vals, SECTIONS)
  return vals, blocks
end

local function buildSession(idx)
  local r = H_rng(SEED * 1000003 + idx * 7919)
  local gender = r(2)
  local s = Schema.newGame({ version = GAME, name = randName(r, 7), gender = gender,
    rivalName = not EMERALD and randName(r, 7) or nil, rngSeed = SEED * 100000 + idx })
  s.trainerId = r(65536)
  s.secretId = r(65536)
  s.id, s.playerId = s.trainerId, s.trainerId
  local m = pick(r, MAPS)
  s.map, s.x, s.y = m.id, r(m.width), r(m.height)
  s.facing = pick(r, { "down", "up", "left", "right" })
  s.money = r(10) == 0 and 999999 or r(1000000)
  s.coins = r(10) == 0 and 9999 or r(10000)
  s.berryPowder = r(10) == 0 and 99999 or r(100000)
  s.playtime = { hours = r(10) == 0 and 999 or r(1000), minutes = r(60), seconds = r(60) }
  local o = Options.ensure(s)
  o.textSpeed, o.frameType, o.sound = r(3), r(10), r(2)
  o.battleStyle, o.battleScene, o.buttonMode = r(2), r(2), r(3)
  o.text_speed, o.l_equals_a = o.textSpeed, o.buttonMode == 2
  s.flashLevel = r(8)
  s.gcnLinkFlags = r(4) == 0 and r(65536) or 0

  local partySize = r(7)
  if partySize == 0 then stats.emptyParty = stats.emptyParty + 1 end
  if partySize == 6 then stats.fullParty = stats.fullParty + 1 end
  for _ = 1, partySize do
    local sp = pick(r, VALID_SPECIES)
    local ok, code, mon
    if r(8) == 0 then
      ok, code, mon = Party.giveEgg(s, sp)
      stats.eggsParty = stats.eggsParty + 1
    else
      ok, code, mon = Party.giveMon(s, sp, 5, nil)
    end
    assert(ok, "Party.giveMon party")
    randomizeMon(s, mon, r, { party = true })
    stats.partyMons = stats.partyMons + 1
  end
  for _, mon in ipairs(s.party) do
    if not mon.isEgg and r(4) == 0 then
      local id = Mail.giveMailToMon(s, mon, pick(r, MAIL_ITEMS))
      if id ~= Mail.MAIL_NONE then
        local rec = Mail.slot(s, id)
        for i = 1, 9 do rec.words[i] = r(5) == 0 and 0xFFFF or (r(22) * 512 + r(40)) end
        stats.mailMons = stats.mailMons + 1
      end
    end
  end
  if r(3) == 0 then
    local pool = Mail.pool(s)
    for i = 7, 16 do
      if r(3) == 0 then
        local rec = pool[i]
        Mail.clear(rec)
        rec.playerName = randName(r, 7)
        rec.trainerId = r(65536)
        rec.species = pick(r, VALID_SPECIES)
        rec.itemId = pick(r, MAIL_ITEMS)
        rec.design = Mail.designOf(rec.itemId)
        for k = 1, 9 do rec.words[k] = r(22) * 512 + r(40) end
        stats.pcMail = stats.pcMail + 1
      end
    end
  end

  local Sto = s.storage
  for b = 1, 14 do
    local box = Sto.boxes[b]
    if r(4) == 0 then box.name = randName(r, 8, true) end
    if r(4) == 0 then box.wallpaper = 1 + r(L.WALLPAPER_MAX + 1) end
    local count = r(12) == 0 and 30 or (r(3) == 0 and r(31) or 0)
    if count == 30 then stats.fullBoxes = stats.fullBoxes + 1 end
    local slots = {}
    for sl = 1, 30 do slots[sl] = sl end
    for i = 30, 2, -1 do local j = r(i) + 1; slots[i], slots[j] = slots[j], slots[i] end
    for i = 1, count do
      local mon = newMon(s, r, { party = false })
      if mon.isEgg then stats.eggsBox = stats.eggsBox + 1 end
      box.mons[slots[i]] = mon
      stats.boxMons = stats.boxMons + 1
    end
  end
  Sto.currentBox = 1 + r(14)
  Sto.items = {}
  for _ = 1, r(4) == 0 and 60 or r(12) do
    local id = pick(r, ALL_ITEMS)
    local stacked = false
    for _, it in ipairs(Sto.items) do if it.id == id then stacked = true end end
    if (stacked or #Sto.items < L.PC_ITEMS.count) and Storage.addPcItem(s, id, 1 + r(999)) then
      stats.pcItems = stats.pcItems + 1
    end
  end

  for _ = 1, r(5) == 0 and 120 or r(25) do
    if Bag.add(s.bag, pick(r, ALL_ITEMS), 1 + r(r(3) == 0 and 999 or 20)) then stats.bagItems = stats.bagItems + 1 end
  end
  local keys = s.bag.pockets.KEY_ITEMS or {}
  if #keys > 0 and r(2) == 0 then
    s.registeredItem = keys[r(#keys) + 1].id
    stats.registeredItem = stats.registeredItem + 1
  end

  for _ = 1, r(60) do
    local sp = pick(r, VALID_SPECIES)
    local roll = r(3)
    if roll == 0 then Dex.setSeen(s.dex, sp)
    elseif roll == 1 then Dex.setCaught(s.dex, sp)
    else Dex.handleSetPokedexFlag(s.dex, sp, r(2) == 0, r(65536) * 65536 + r(65536)) end
  end
  if r(3) == 0 then
    Dex.handleSetPokedexFlag(s.dex, 201, true, r(65536) * 65536 + r(65536))
    Dex.handleSetPokedexFlag(s.dex, 308, false, r(65536) * 65536 + r(65536))
  end

  for _ = 1, r(200) do
    local id = 0x20 + r(FLAG_MAX - 0x1F)
    if id ~= NAT.flag then Flags.setFlag(s, nil, id, true) stats.flagsSet = stats.flagsSet + 1 end
  end
  for _ = 1, r(60) do
    local id = 0x4000 + r(256)
    if id ~= NAT.var and id ~= L.RSE_NATIONAL_VAR then
      Flags.setVar(s, nil, id, r(65536))
      stats.varsSet = stats.varsSet + 1
    end
  end
  if r(3) == 0 then
    stats.nationalDex = stats.nationalDex + 1
    if EMERALD then
      Dex.enableNational(s)
    else
      s.dex.nationalUnlocked = true
      s.national_dex_unlocked = true
    end
    Flags.setVar(s, nil, NAT.var, NAT.varValue)
    Flags.setFlag(s, nil, NAT.flag, true)
  end

  s.gameStats = {}
  for _ = 1, r(20) do
    local id = r(64)
    if id == 1 then
      s.gameStats[1] = r(1000) * 65536 + r(60) * 256 + r(60)
    else
      s.gameStats[id] = r(4) == 0 and r(U32) or r(100000)
    end
    stats.gameStats = stats.gameStats + 1
  end
  if r(2) == 0 then
    s.registeredTexts = {}
    for i = 1, 10 do s.registeredTexts[i] = randName(r, 10, true, true) end
    stats.registeredTexts = stats.registeredTexts + 1
  end
  s.easyChatProfile = {}
  for i = 1, 4 do s.easyChatProfile[i] = r(22) * 512 + r(40) end

  if r(4) == 0 then
    s.dynamicWarp = randWarp(r)
    stats.dynamicWarp = stats.dynamicWarp + 1
  end
  if r(15) == 0 then
    local rooms = {}
    for _, mm in ipairs(MAPS) do if LINK_ROOMS[mm.id] then rooms[#rooms + 1] = mm end end
    if #rooms > 0 then
      local lr = pick(r, rooms)
      s.map, s.x, s.y = lr.id, r(lr.width), r(lr.height)
      s.dynamicWarp = randWarp(r)
      stats.linkRoomMaps = stats.linkRoomMaps + 1
    end
  end
  if EMERALD then
    local Player = require("src.core.game3.rse.easy_chat_player")
    for _, f in ipairs(Player.BATTLE_FIELDS) do
      local words = Player.battleWords(s, f)
      for i = 1, #words do if r(2) == 0 then words[i] = r(5) == 0 and 0xFFFF or r(22) * 512 + r(40) end end
    end
  end
  local clear = Gen3Save.forVersion(GAME).resolved().gameClear
  if Flags.getFlag(s, nil, clear) then s.game_cleared = true end
  if r(4) == 0 then
    s.escapeWarp = randWarp(r)
    stats.escapeWarp = stats.escapeWarp + 1
  end

  if r(3) == 0 then
    local ok
    if EMERALD then ok = Roamer.initRse(s, r(2) == 0) else ok = Roamer.init(s, pick(r, { 1, 4, 7 })) end
    if ok and s.roamer then
      local ro = s.roamer
      ro.active = r(4) ~= 0
      ro.level = 1 + r(100)
      ro.hp = r(400)
      local st = r(8)
      if EMERALD then ro.status = st else ro.status, ro.statusNum = st, st end
      stats.roamer = stats.roamer + 1
    end
  end

  local nDay = #s.party > 1 and r(3) or 0
  for _ = 1, nDay do
    if #s.party > 1 then
      local slot = 1 + r(#s.party)
      local mon = s.party[slot]
      if mon and not mon.isEgg then
        local hadMail = Mail.monHasMail(mon)
        if Daycare.deposit(s, slot) then
          stats.daycareMons = stats.daycareMons + 1
          if hadMail then stats.daycareMail = stats.daycareMail + 1 end
        end
      end
    end
  end
  if nDay > 0 then
    local dc = Daycare.stateOf(s)
    for i = 1, 2 do if Daycare.mon(dc, i) then dc.steps[i] = r(100000) end end
    dc.offspringPersonality = r(4) == 0 and (EMERALD and r(65536) * 65536 + r(65536) or r(65536)) or 0
    dc.stepCounter = r(256)
  end
  if not EMERALD and #s.party > 1 and r(4) == 0 then
    local slot = 1 + r(#s.party)
    local mon = s.party[slot]
    if mon and not mon.isEgg and Daycare.depositRoute5(s, slot) then
      Daycare.route5Of(s).steps = r(100000)
      stats.route5 = stats.route5 + 1
    end
  end

  if r(4) == 0 then
    s.hallOfFameTeams = {}
    for _ = 1, 1 + r(r(4) == 0 and 50 or 5) do
      local team = {}
      for _ = 1, 1 + r(6) do
        local sp = pick(r, VALID_SPECIES)
        team[#team + 1] = { species = sp, level = 1 + r(100), nickname = randName(r, 10),
          trainerId = r(65536), otSecretId = r(65536), personality = r(65536) * 65536 + r(65536) }
      end
      s.hallOfFameTeams[#s.hallOfFameTeams + 1] = team
      stats.hofTeams = stats.hofTeams + 1
    end
    s.hasHallOfFameRecords = true
  end

  if not EMERALD then
    local FameChecker = require("src.core.game3.fame_checker")
    FameChecker.records(s)
    for p = 0, FameChecker.NUM_PERSONS - 1 do
      for slot = 0, FameChecker.NUM_FLAVOR_TEXTS - 1 do
        if r(4) == 0 then FameChecker.setFlavorText(p, slot, s) end
      end
      if r(3) == 0 then FameChecker.updatePickState(p, 1 + r(2), s) end
    end
    local Tower = require("src.core.game3.trainer_tower")
    local state = Tower.state(s)
    for _, rec in ipairs(state.records) do rec.bestTime = r(4) == 0 and Tower.MAX_TIME or r(Tower.MAX_TIME + 1) end
    stats.fameTower = stats.fameTower + 1
  end

  local save = Schema.toSaveTable(s)
  local vals, blocks = sectionState(r)
  for k, v in pairs(vals) do
    if k == "modData" then merge(save.modData, v) else save[k] = deepcopy(v) end
  end
  stats.sectionsMerged = stats.sectionsMerged + 1
  save.modData.cartImage = nil
  return s, save, r, vals, blocks
end

local function bitSet(list)
  local out = {}
  for _, v in ipairs(list) do out[v] = true end
  return out
end

local function cmpSet(stage, path, want, got, limit)
  for k in pairs(want) do if not got[k] then fail(stage, path .. "[" .. k .. "]", "set", "unset") end end
  for k in pairs(got) do
    if not want[k] and (not limit or k >= limit) then fail(stage, path .. "[" .. k .. "]", "unset", "set") end
  end
end

-- pokeemerald/charmap.txt:80
local ESCAPES = { ["."] = "{AD}", ["-"] = "{AE}", ["'"] = "{B4}", ["\226\153\130"] = "{B5}", ["\226\153\128"] = "{B6}" }

local function textOf(s, n)
  s = tostring(s or "")
  local out, count, i = {}, 0, 1
  while i <= #s and count < n do
    local c = s:byte(i)
    local len = c < 0x80 and 1 or c < 0xE0 and 2 or c < 0xF0 and 3 or 4
    local ch = s:sub(i, i + len - 1)
    out[#out + 1] = ESCAPES[ch] or ch
    count, i = count + 1, i + len
  end
  return table.concat(out)
end

-- pokeemerald/src/mail_data.c:65
local function mailName(s)
  s = tostring(s or "")
  while #s < 6 do s = s .. " " end
  return textOf(s, 7)
end

local function cartStatusOf(mon)
  local st = mon.status
  if st == "SLP" then return math.max(1, math.min(7, tonumber(mon.sleep) or 1)) end
  local map = { PSN = 0x8, BRN = 0x10, FRZ = 0x20, PAR = 0x40, TOX = 0x80 }
  return map[st] or 0
end

local function abilityOf(species, bitv)
  local a = ABILITIES and ABILITIES[species]
  if type(a) ~= "table" then return nil end
  return bitv == 1 and (a[2] or 0) or (a[1] or 0)
end

local function compareMon(path, m, c, party, s)
  local stage = "cart"
  if not c then fail(stage, path, "mon", "empty") return end
  same(stage, path .. ".checksum", true, c.checksumOk)
  same(stage, path .. ".species", m.species, c.species)
  same(stage, path .. ".personality", m.personality % U32, c.pid)
  local sid = m.otSecretId
  same(stage, path .. ".otId", (m.otId % 65536) + (sid % 65536) * 65536, c.otid)
  same(stage, path .. ".heldItem", tonumber(m.item or m.heldItem) or 0, c.item)
  same(stage, path .. ".isEgg", m.isEgg == true, c.isEgg)
  local eggBit = math.floor(c.flags / 4) % 2 == 1
  same(stage, path .. ".flags.isEggBit", m.isEgg == true, eggBit)
  same(stage, path .. ".exp", m.exp, c.exp)
  for i = 1, 4 do
    same(stage, path .. ".moves[" .. i .. "]", m.moves[i] or 0, c.moves[i])
    same(stage, path .. ".pp[" .. i .. "]", m.moves[i] and (m.pp[i] or 0) or 0, c.pp[i])
  end
  same(stage, path .. ".ppBonuses", m.ppBonusesPacked or 0, c.ppBonuses)
  for i, k in ipairs({ "hp", "atk", "def", "spe", "spa", "spd" }) do
    same(stage, path .. ".evs." .. k, m.evs[k] or 0, c.evs[i])
    same(stage, path .. ".ivs." .. k, m.ivs[k] or 0, c.ivs[i])
  end
  local contest = type(m.contest) == "table" and m.contest or {}
  for i, k in ipairs({ "cool", "beauty", "cute", "smart", "tough", "sheen" }) do
    same(stage, path .. ".contest." .. k, tonumber(contest[k]) or 0, c.contest[i])
  end
  same(stage, path .. ".friendship", m.isEgg and (m.eggCycles or m.friendship) or m.friendship, c.friendship)
  same(stage, path .. ".pokerus", m.pokerus or 0, c.pokerus)
  same(stage, path .. ".metLocation", m.metLocation or 0, c.metLocation)
  same(stage, path .. ".metLevel", m.metLevel or 0, c.metLevel)
  same(stage, path .. ".metGame", m.metGame, c.metGame)
  same(stage, path .. ".ball", m.pokeball or 4, c.ball)
  same(stage, path .. ".otGender", m.otGender or 0, c.otGender)
  local engineAbility = tonumber(m.ability or m.abilityId)
  local cartAbility = abilityOf(m.species, c.ability)
  if engineAbility and cartAbility then
    same(stage, path .. ".abilityBit(GetAbilityBySpecies)", engineAbility, cartAbility)
  end
  local ribbons = EMERALD and Ribbons.word(m) or ((m.championRibbon and 2 ^ 15) or 0)
  if m.modernFatefulEncounter then ribbons = ribbons + 2 ^ 31 end
  same(stage, path .. ".ribbons", ribbons, c.ribbons)
  same(stage, path .. ".markings", m.markings or 0, c.markings)
  if m.isEgg then
    same(stage, path .. ".nickname(egg)", "{60}{6F}{8B}", c.nickText)
    same(stage, path .. ".language(egg)", m.language or 1, c.language)
  else
    local nick = (m.nickname and m.nickname ~= "") and m.nickname or speciesName(m.species)
    same(stage, path .. ".nickname", textOf(nick, 10), c.nickText)
    same(stage, path .. ".language", m.language or 2, c.language)
  end
  same(stage, path .. ".otName", textOf(m.otName or m.ot, 7), c.otText)
  if party then
    same(stage, path .. ".status", cartStatusOf(m), c.status)
    same(stage, path .. ".level", m.level, c.level)
    same(stage, path .. ".hp", m.hp, c.hp)
    same(stage, path .. ".maxHp", m.maxHp, c.maxHp)
    local st = { m.attack, m.defense, m.speed, m.spAtk, m.spDef }
    local names = { "attack", "defense", "speed", "spAtk", "spDef" }
    for i = 1, 5 do same(stage, path .. "." .. names[i], st[i], c.stats[i]) end
    local wantMail = (Mail.monHasMail(m) and tonumber(m.mail)) or 0xFF
    same(stage, path .. ".mail", wantMail, c.mail)
  end
end

local function sortedPocket(list)
  local out = {}
  for _, it in ipairs(list or {}) do out[#out + 1] = { tonumber(it.id) or ItemsData.toNumericId(it.id), it.qty } end
  return out
end

local function compareCart(s, save, bytes)
  local c = D.deep(bytes, FAMILY)
  local x = D.extra(bytes, FAMILY)
  if not c or not x then fail("cart", "decode", "decodable", "nil") stats.decodeFail = stats.decodeFail + 1 return end
  local st = "cart"
  same(st, "name", textOf(s.name, 7), c.name)
  same(st, "gender", s.gender, c.gender)
  same(st, "trainerId", s.trainerId % 65536, c.tid)
  same(st, "secretId", s.secretId % 65536, c.sid)
  same(st, "playTime.hours", s.playtime.hours, c.playHours)
  same(st, "playTime.minutes", s.playtime.minutes, c.playMinutes)
  same(st, "playTime.seconds", s.playtime.seconds, c.playSeconds)
  same(st, "playTime.vblanks", 0, c.playVBlanks)
  local o = s.options
  local ow = c.optionsWord
  same(st, "options.textSpeed", o.textSpeed, ow % 8)
  same(st, "options.frameType", o.frameType, math.floor(ow / 8) % 32)
  same(st, "options.sound", o.sound, math.floor(ow / 256) % 2)
  same(st, "options.battleStyle", o.battleStyle, math.floor(ow / 512) % 2)
  same(st, "options.battleScene", o.battleScene, math.floor(ow / 1024) % 2)
  if save.regionMapZoom ~= nil then
    same(st, "regionMapZoom", save.regionMapZoom == true and 1 or 0, math.floor(ow / 2048) % 2)
  end
  same(st, "options.buttonMode", o.buttonMode, c.buttonMode)

  local wantOwned, wantSeen = {}, {}
  for sp, v in pairs(s.dex.owned or {}) do if v then wantOwned[NATIONAL.toNational[sp] - 1] = true end end
  for sp, v in pairs(s.dex.caught or {}) do if v then wantOwned[NATIONAL.toNational[sp] - 1] = true end end
  for sp, v in pairs(s.dex.seen or {}) do if v then wantSeen[NATIONAL.toNational[sp] - 1] = true end end
  for k in pairs(wantOwned) do wantSeen[k] = true end
  cmpSet(st, "dex.owned", wantOwned, bitSet(c.dexOwned))
  cmpSet(st, "dex.seen(sb2)", wantSeen, bitSet(c.dexSeen))
  cmpSet(st, "dex.seen(sb1 seen1)", wantSeen, bitSet(c.dexSeen1))
  cmpSet(st, "dex.seen(sb1 seen2)", wantSeen, bitSet(c.dexSeen2))
  same(st, "dex.unownPersonality", tonumber(s.dex.unownPersonality) or 0, x.unownPersonality)
  same(st, "dex.spindaPersonality", tonumber(s.dex.spindaPersonality) or 0, x.spindaPersonality)
  local national = s.dex.nationalUnlocked == true or s.dex.national == true
  same(st, "dex.nationalMagic", national and NAT.magic or 0, c.dexMagic)
  if national and EMERALD then
    same(st, "dex.mode(national)", 1, c.dexMode)
    same(st, "dex.order", 0, c.dexOrder)
  end

  same(st, "money", s.money, c.money)
  same(st, "coins", s.coins, c.coins)
  same(st, "berryPowder", s.berryPowder, c.powder)
  if EMERALD then
    local k = tonumber(save.encryptionKey)
    if k and k ~= 0 and k ~= 1 then same(st, "encryptionKey", k, c.key) end
  end
  same(st, "gcnLinkFlags", s.gcnLinkFlags or 0, x.gcnLinkFlags)
  same(st, "flashLevel", s.flashLevel or 0, x.flashLevel)

  local here
  for _, m in ipairs(MAPS) do if m.id == s.map then here = m break end end
  same(st, "location.group", here.group, c.location.group)
  same(st, "location.num", here.num, c.location.num)
  same(st, "location.warpId", -1, c.location.warpId)
  same(st, "location.x", s.x, c.location.x)
  same(st, "location.y", s.y, c.location.y)
  same(st, "pos.x", s.x, c.posX)
  same(st, "pos.y", s.y, c.posY)
  same(st, "mapLayoutId", here.layout, c.mapLayoutId)
  same(st, "specialSaveWarpFlags.continue", 1, c.specialSaveWarpFlags % 2)
  local cont = here
  local cx, cy = s.x, s.y
  if save.continueGameWarp and type(save.continueGameWarp.map) == "string" and bit.band(save.specialSaveWarpFlags or 0, 1) ~= 0 then
    for _, m in ipairs(MAPS) do if m.id == save.continueGameWarp.map then cont = m end end
    cx, cy = save.continueGameWarp.x, save.continueGameWarp.y
  end
  same(st, "continueGameWarp.group", cont.group, c.continueGameWarp.group)
  same(st, "continueGameWarp.num", cont.num, c.continueGameWarp.num)
  same(st, "continueGameWarp.x", cx, c.continueGameWarp.x)
  same(st, "continueGameWarp.y", cy, c.continueGameWarp.y)
  if LINK_ROOMS[s.map] and s.dynamicWarp then
    same(st, "continueGameWarp.warpId(link room: SetContinueGameWarpToDynamicWarp copies dynamicWarp)",
      s.dynamicWarp.warpId, c.continueGameWarp.warpId)
  end
  if EMERALD then
    for k, f in ipairs({ "easyChatBattleStart", "easyChatBattleWon", "easyChatBattleLost" }) do
      for i = 1, 6 do
        same(st, ("%s[%d]"):format(f, i), (save[f] or {})[i], x.battleWords[(k - 1) * 6 + i])
      end
    end
  end
  for _, key in ipairs({ "dynamicWarp", "escapeWarp" }) do
    local w = s[key]
    if w then
      local m
      for _, mm in ipairs(MAPS) do if mm.id == w.map then m = mm end end
      same(st, key .. ".group", m.group, c[key].group)
      same(st, key .. ".num", m.num, c[key].num)
      same(st, key .. ".warpId", w.warpId, c[key].warpId)
      same(st, key .. ".x", w.x, c[key].x)
      same(st, key .. ".y", w.y, c[key].y)
    else
      same(st, key .. ".group", -1, c[key].group >= 128 and c[key].group - 256 or c[key].group)
    end
  end
  local lh = c.lastHealLocation
  local healOk = false
  for _, m in ipairs(MAPS) do if m.group == lh.group and m.num == lh.num then healOk = true end end
  same(st, "lastHealLocation.isCachedMap", true, healOk)

  local wantFlags = {}
  for k, v in pairs(s.flags or {}) do
    local id = tonumber(k)
    if v and id and id > 0x1F and id <= FLAG_MAX then wantFlags[id] = true end
  end
  if not EMERALD and save.vars[L.RSE_NATIONAL_VAR] == nil then wantFlags[L.RSE_NATIONAL_FLAG] = true end
  cmpSet(st, "flags", wantFlags, bitSet(c.flagsSet), 0)
  for id = 0x4000, 0x40FF do
    local want = (tonumber(s.vars[id]) or 0) % 65536
    if not EMERALD and id == L.RSE_NATIONAL_VAR and s.vars[id] == nil then want = L.RSE_NATIONAL_VALUE end
    same(st, ("vars[0x%X]"):format(id), want, c.vars[id])
  end
  for i = 0, 63 do same(st, "gameStats[" .. i .. "]", (tonumber(s.gameStats[i]) or 0) % U32, c.stats[i]) end
  for i = 1, 4 do same(st, "easyChatProfile[" .. i .. "]", s.easyChatProfile[i], c.profile[i]) end

  same(st, "partyCount", #s.party, #c.party)
  for i, m in ipairs(s.party) do compareMon("party[" .. i .. "]", m, c.party[i], true, s) end
  for b = 1, 14 do
    local box = s.storage.boxes[b]
    for sl = 1, 30 do
      local m = box.mons[sl]
      if m then compareMon(("box[%d][%d]"):format(b, sl), m, c.boxes[b][sl], false, s)
      elseif c.boxes[b][sl] then fail(st, ("box[%d][%d]"):format(b, sl), "empty", "mon") end
    end
    local wantName = box.name == ("BOX %d"):format(b) and ("BOX%d"):format(b) or textOf(box.name, 8)
    same(st, ("boxName[%d]"):format(b), wantName, c.boxNames[b])
    same(st, ("wallpaper[%d]"):format(b), box.wallpaper - 1, c.wallpapers[b])
  end
  same(st, "currentBox", s.storage.currentBox - 1, c.currentBox)

  for p, pk in ipairs(L.POCKETS) do
    local want = sortedPocket(s.bag.pockets[pk.key])
    local got = c.pockets[p]
    same(st, "bag." .. pk.key .. ".count", #want, #got)
    for i = 1, math.max(#want, #got) do
      local a, b2 = want[i] or {}, got[i] or {}
      same(st, ("bag.%s[%d].id"):format(pk.key, i), a[1], b2[1])
      same(st, ("bag.%s[%d].qty"):format(pk.key, i), a[2], b2[2])
    end
  end
  local wantPc = sortedPocket(s.storage.items)
  same(st, "pcItems.count", #wantPc, #c.pcItems)
  for i = 1, math.max(#wantPc, #c.pcItems) do
    local a, b2 = wantPc[i] or {}, c.pcItems[i] or {}
    same(st, ("pcItems[%d].id"):format(i), a[1], b2[1])
    same(st, ("pcItems[%d].qty"):format(i), a[2], b2[2])
  end
  same(st, "registeredItem", tonumber(s.registeredItem) or 0, c.registeredItem)

  local pool = s.mail or {}
  for i = 1, 16 do
    local want = pool[i]
    local got = c.mail[i]
    if want and (tonumber(want.itemId) or 0) ~= 0 then
      same(st, ("mail[%d].itemId"):format(i), want.itemId, got.itemId)
      same(st, ("mail[%d].species"):format(i), want.species, got.species)
      same(st, ("mail[%d].trainerId16"):format(i), want.trainerId % 65536, got.trainerId % 65536)
      same(st, ("mail[%d].name"):format(i), mailName(want.playerName), got.name)
      for k = 1, 9 do same(st, ("mail[%d].words[%d]"):format(i, k), want.words[k], got.words[k]) end
    else
      same(st, ("mail[%d].itemId"):format(i), 0, got.itemId)
    end
  end

  if s.roamer then
    local ro = s.roamer
    local raw = x.roamerRaw
    local function u16(o) return raw[o + 1] + raw[o + 2] * 256 end
    local function u32(o) return u16(o) + u16(o + 2) * 65536 end
    local ivs = ro.ivs
    local ivw = 0
    for i, k in ipairs({ "hp", "atk", "def", "spe", "spa", "spd" }) do ivw = ivw + (ivs[k] or 0) * 2 ^ ((i - 1) * 5) end
    same(st, "roamer.ivs", ivw, u32(0) % 2 ^ 30)
    same(st, "roamer.personality", (ro.personality or ro.pid) % U32, u32(4))
    same(st, "roamer.species", ro.species, u16(8))
    same(st, "roamer.hp", ro.hp, u16(10))
    same(st, "roamer.level", ro.level, raw[13])
    same(st, "roamer.status", (EMERALD and ro.status or ro.statusNum) % 256, raw[14])
    same(st, "roamer.active", ro.active and 1 or 0, raw[20])
  end

  local root = save.modData and save.modData[L.DAYCARE_SAVE_KEY] or {}
  local dc = root.daycare or {}
  for i = 1, 2 do
    local m = dc[i]
    local got = x.daycare[i]
    if m then
      compareMon("daycare[" .. i .. "]", m, got.mon, false, s)
      same(st, "daycare[" .. i .. "].steps", (dc.steps or {})[i] or 0, got.steps)
      local ml = (dc.mail or {})[i]
      if ml and ml.message and (ml.message.itemId or 0) ~= 0 then
        same(st, "daycare[" .. i .. "].mail.itemId", ml.message.itemId, got.mail.itemId)
        same(st, "daycare[" .. i .. "].mail.otName", textOf(ml.otName, 7), got.otName)
        same(st, "daycare[" .. i .. "].mail.monName", textOf(ml.monName, 10), got.monName)
        for k = 1, 9 do same(st, ("daycare[%d].mail.words[%d]"):format(i, k), ml.message.words[k], got.mail.words[k]) end
      else
        same(st, "daycare[" .. i .. "].mail.itemId", 0, got.mail.itemId)
      end
    else
      same(st, "daycare[" .. i .. "]", nil, got.mon and got.mon.species)
    end
  end
  same(st, "daycare.offspringPersonality", tonumber(dc.offspringPersonality) or 0, x.offspringPersonality)
  same(st, "daycare.stepCounter", tonumber(dc.stepCounter) or 0, x.daycareStepCounter)
  if not EMERALD then
    local r5 = root.route5Daycare or {}
    if r5.mon then
      compareMon("route5", r5.mon, x.route5.mon, false, s)
      same(st, "route5.steps", r5.steps or 0, x.route5.steps)
      if r5.mail and r5.mail.message and (r5.mail.message.itemId or 0) ~= 0 then
        same(st, "route5.mail.itemId", r5.mail.message.itemId, x.route5.mail.itemId)
      end
    else
      same(st, "route5", nil, x.route5.mon and x.route5.mon.species)
    end
    same(st, "rivalName", textOf(s.rivalName, 7), x.rivalName)
  end

  if s.registeredTexts then
    for i = 1, 10 do same(st, ("registeredTexts[%d]"):format(i), textOf(s.registeredTexts[i], 20), x.registeredTexts[i]) end
  end
  local teams = s.hallOfFameTeams or {}
  same(st, "hof.teamCount", #teams, #x.hof)
  if #teams > 0 then same(st, "hof.sectorChecksums", true, x.hofChecksumOk) end
  for t, team in ipairs(teams) do
    local got = x.hof[t] or {}
    same(st, ("hof[%d].size"):format(t), #team, #got)
    for i, m in ipairs(team) do
      local g = got[i] or {}
      same(st, ("hof[%d][%d].species"):format(t, i), m.species, g.species)
      same(st, ("hof[%d][%d].level"):format(t, i), m.level, g.level)
      same(st, ("hof[%d][%d].tid"):format(t, i), m.trainerId + m.otSecretId * 65536, g.tid)
      same(st, ("hof[%d][%d].personality"):format(t, i), m.personality, g.personality)
      same(st, ("hof[%d][%d].nick"):format(t, i), textOf(m.nickname, 10), g.nick)
    end
  end
  return c, x
end

local EXCLUDED_ROOTS = {
  rng = "engine RNG state; pret gRngValue is not in the save blocks (src/random.c)",
  specialVars = "VAR_0x8000+ special vars are EWRAM (src/event_data.c gSpecialVar_*), never saved",
  stringVars = "gStringVar1-3 are EWRAM text buffers (src/string_util.c), never saved",
  move_overlay = "engine-only Gen 1 host move quarantine",
  meta = "engine slot metadata (playthrough id, mods)",
  biking = "engine runtime flag; the cart keeps bike state in flags/avatar",
  bikeType = "engine runtime field",
  healMap = "engine respawn map; cart lastHealLocation is a heal-location warp (Gen3Save fromPortSave healWarp)",
  healX = "see healMap",
  healY = "see healMap",
  rtcSkew = "engine wall-clock skew anchored at import (src/core/game3/rtc.lua anchorToLastUpdate)",
  questLog = "engine quest log runtime; FRLG cart quest log is template-carried (gen3_layouts/frlg.lua QUEST_LOG)",
  trainerCard = "engine trainer card UI cache",
  inventory = "SaveData alias of bag",
  schemaVersion = "engine schema version",
  engine = "engine id",
  generation = "engine id",
  facing = "templateless export writes no player object event (Gen3Save.encodeBlocks only rewrites facing over a template)",
  monBoxId = "engine PC cursor (VAR_PC_BOX_TO_SEND_MON is the cart copy)",
  monBoxPos = "engine PC cursor",
}
local EXCLUDED_MODDATA = {
  cartImage = "the import template itself",
  cartGame = "import provenance stamp",
  cartKey = "import key stamp (FRLG key lives in modData so the next export reuses it)",
  cartImport = "import-only scratch (dex lists consumed by finishImport, lastHealLocation, mapLayoutId)",
}

local function effMon(m, party)
  if type(m) ~= "table" then return m end
  local isEgg = m.isEgg == true
  local nick = m.nickname
  if isEgg then nick = "EGG" elseif type(nick) ~= "string" or nick == "" then nick = speciesName(tonumber(m.species)) end
  local contest = type(m.contest) == "table" and m.contest or {}
  local out = {
    species = tonumber(m.species), personality = tonumber(m.personality),
    otId = (tonumber(m.otId) or 0) % 65536, otSecretId = tonumber(m.otSecretId), otName = m.otName or m.ot,
    otGender = tonumber(m.otGender) or 0, nickname = nick, language = tonumber(m.language) or (isEgg and 1 or 2),
    isEgg = isEgg, markings = tonumber(m.markings) or 0, item = tonumber(m.item or m.heldItem) or 0,
    exp = tonumber(m.exp), friendship = isEgg and tonumber(m.eggCycles or m.friendship) or tonumber(m.friendship),
    ppBonusesPacked = tonumber(m.ppBonusesPacked) or 0, moves = deepcopy(m.moves), pp = deepcopy(m.pp),
    evs = deepcopy(m.evs), ivs = deepcopy(m.ivs), pokerus = tonumber(m.pokerus) or 0,
    metLocation = tonumber(m.metLocation) or 0, metLevel = tonumber(m.metLevel), metGame = tonumber(m.metGame),
    pokeball = tonumber(m.pokeball) or 4,
    ability = Pokemon.abilityId(tonumber(m.species), tonumber(m.personality)),
    contest = { tonumber(contest.cool) or 0, tonumber(contest.beauty) or 0, tonumber(contest.cute) or 0,
      tonumber(contest.smart) or 0, tonumber(contest.tough) or 0, tonumber(contest.sheen) or 0 },
    ribbons = EMERALD and Ribbons.word(m) or (m.championRibbon == true and 2 ^ 15 or 0),
    championRibbon = m.championRibbon == true, modernFatefulEncounter = m.modernFatefulEncounter == true,
  }
  if tonumber(m.abilityNum) then
    out.ability = abilityOf(out.species, tonumber(m.abilityNum)) or out.ability
  end
  if party then
    out.level, out.hp, out.maxHp = tonumber(m.level), tonumber(m.hp), tonumber(m.maxHp)
    out.attack, out.defense, out.speed = tonumber(m.attack), tonumber(m.defense), tonumber(m.speed)
    out.spAtk, out.spDef = tonumber(m.spAtk), tonumber(m.spDef)
    out.status = m.status
    out.sleep = m.status == "SLP" and tonumber(m.sleep) or nil
    out.mail = Mail.monHasMail(m) and tonumber(m.mail) or nil
  end
  return out
end

local function effStorage(stg)
  local out = { currentBox = tonumber(stg and stg.currentBox) or 1, items = {}, boxes = {} }
  for _, it in ipairs(stg and stg.items or {}) do
    out.items[#out.items + 1] = { id = tonumber(it.id) or ItemsData.toNumericId(it.id), qty = tonumber(it.qty) }
  end
  for b = 1, 14 do
    local box = stg and stg.boxes and stg.boxes[b] or {}
    local eb = { name = box.name or ("BOX %d"):format(b), wallpaper = tonumber(box.wallpaper) or Storage.defaultWallpaper(b), mons = {} }
    for sl, m in pairs(box.mons or {}) do eb.mons[tonumber(sl)] = effMon(m, false) end
    out.boxes[b] = eb
  end
  return out
end

local function effBag(bag)
  local out = {}
  for _, pk in ipairs(L.POCKETS) do
    local list = {}
    for _, it in ipairs(bag and bag.pockets and bag.pockets[pk.key] or {}) do
      list[#list + 1] = { id = tonumber(it.id) or ItemsData.toNumericId(it.id), qty = tonumber(it.qty) }
    end
    out[pk.key] = list
  end
  return out
end

local function effFlags(flags)
  local out = {}
  for k, v in pairs(flags or {}) do
    local id = tonumber(k)
    if v and id and id > 0x1F and id <= FLAG_MAX then out[id] = true end
  end
  return out
end

local function effVars(vars)
  local out = {}
  for k, v in pairs(vars or {}) do
    local id = tonumber(k)
    local n = (tonumber(v) or 0) % 65536
    if id and id >= 0x4000 and id <= 0x40FF and n ~= 0 then out[id] = n end
  end
  return out
end

local function effDex(dex)
  dex = dex or {}
  local out = { seen = {}, owned = {}, national = dex.national == true or dex.nationalUnlocked == true,
    unownPersonality = tonumber(dex.unownPersonality) or 0, spindaPersonality = tonumber(dex.spindaPersonality) or 0 }
  for sp, v in pairs(dex.seen or {}) do if v then out.seen[tonumber(sp)] = true end end
  for _, key in ipairs({ "owned", "caught" }) do
    for sp, v in pairs(dex[key] or {}) do if v then out.owned[tonumber(sp)] = true; out.seen[tonumber(sp)] = true end end
  end
  return out
end

local function effMail(pool)
  local out = {}
  for i = 1, 16 do
    local r = pool and pool[i]
    if r and (tonumber(r.itemId) or 0) ~= 0 then
      local words = {}
      for k = 1, 9 do words[k] = tonumber(r.words and r.words[k]) or 0xFFFF end
      out[i] = { itemId = tonumber(r.itemId), species = tonumber(r.species), trainerId = (tonumber(r.trainerId) or 0) % 65536,
        playerName = r.playerName, words = words }
    end
  end
  return out
end

local function effDaycare(md)
  local root = type(md) == "table" and md[L.DAYCARE_SAVE_KEY] or {}
  local dc = type(root.daycare) == "table" and root.daycare or {}
  local out = { offspringPersonality = tonumber(dc.offspringPersonality) or 0, stepCounter = tonumber(dc.stepCounter) or 0,
    mons = {}, steps = {}, mail = {} }
  for i = 1, 2 do
    out.mons[i] = effMon(dc[i] or (dc.mons and dc.mons[i]), false)
    out.steps[i] = out.mons[i] and (tonumber((dc.steps or {})[i]) or 0) or 0
    local ml = (dc.mail or {})[i]
    if out.mons[i] and type(ml) == "table" and ml.message and (tonumber(ml.message.itemId) or 0) ~= 0 then
      out.mail[i] = { otName = ml.otName, monName = ml.monName, message = effMail({ ml.message })[1] }
    end
  end
  if not EMERALD then
    local r5 = type(root.route5Daycare) == "table" and root.route5Daycare or {}
    out.route5 = { mon = effMon(r5.mon, false), steps = r5.mon and (tonumber(r5.steps) or 0) or 0 }
    if r5.mon and type(r5.mail) == "table" and r5.mail.message and (tonumber(r5.mail.message.itemId) or 0) ~= 0 then
      out.route5.mail = { otName = r5.mail.otName, monName = r5.mail.monName, message = effMail({ r5.mail.message })[1] }
    end
  end
  return out
end

local function effRoamer(ro)
  if type(ro) ~= "table" or (tonumber(ro.species) or 0) == 0 then return nil end
  local ivs = type(ro.ivs) == "table" and ro.ivs or {}
  local keys = EMERALD and { "hp", "atk", "def", "spe", "spa", "spd" } or { "hp", "attack", "defense", "speed", "spAtk", "spDef" }
  local iv = {}
  for i, k in ipairs(keys) do iv[i] = tonumber(ivs[k]) or 0 end
  return { active = ro.active == true, species = tonumber(ro.species), level = tonumber(ro.level), hp = tonumber(ro.hp),
    status = tonumber(EMERALD and ro.status or (ro.statusNum or ro.status)) or 0,
    personality = tonumber(ro.personality or ro.pid), ivs = iv }
end

local function effHof(teams)
  local out = {}
  for t, team in ipairs(teams or {}) do
    out[t] = {}
    for i, m in ipairs(team) do
      out[t][i] = { species = m.species, level = m.level, nickname = m.nickname, trainerId = m.trainerId,
        otSecretId = m.otSecretId, personality = m.personality }
    end
  end
  return out
end

local function effOptions(o)
  o = type(o) == "table" and o or {}
  local blk = Profile.of(GAME).optionsBlock
  if blk and type(o[blk]) == "table" then o = o[blk] end
  return { textSpeed = o.textSpeed, frameType = o.frameType, sound = o.sound, battleStyle = o.battleStyle,
    battleScene = o.battleScene, buttonMode = o.buttonMode }
end

local function effWarp(w)
  if type(w) ~= "table" or type(w.map) ~= "string" then return nil end
  return { map = w.map, warpId = tonumber(w.warpId) or -1, x = tonumber(w.x), y = tonumber(w.y) }
end

local MODELED = {
  party = function(v) local out = {} for i, m in ipairs(v or {}) do out[i] = effMon(m, true) end return out end,
  storage = effStorage, bag = effBag, flags = effFlags, vars = effVars, dex = effDex, mail = effMail,
  options = effOptions, roamer = effRoamer, hallOfFameTeams = effHof, dynamicWarp = effWarp, escapeWarp = effWarp,
  continueGameWarp = effWarp,
  playTime = function(p) p = p or {} return { hours = p.hours, minutes = p.minutes, seconds = p.seconds, vblanks = tonumber(p.vblanks) or 0 } end,
  gameStats = function(g)
    local out = {}
    for k, v in pairs(g or {}) do
      local id = tonumber(k) or (Gen3Save.STAT_ALIASES or {})[k]
      if (tonumber(v) or 0) ~= 0 then out[id or k] = math.max(out[id or k] or 0, tonumber(v) % U32) end
    end
    return out
  end,
  registeredItem = function(v) return tonumber(v) or 0 end,
  hasHallOfFameRecords = function(v) return v == true end,
  game_cleared = function(v) return v == true end,
  gcnLinkFlags = function(v) return tonumber(v) or 0 end,
  flashLevel = function(v) return tonumber(v) or 0 end,
}

local NORMALISED = {
  continueGameWarp = "every export sets CONTINUE_GAME_WARP to the player position so the cart warps in on continue (pokefirered/src/overworld.c:1706); orig without the flag compares as that stamp",
  specialSaveWarpFlags = "see continueGameWarp",
  hofDebutHours = "derived on import from GAME_STAT_FIRST_HOF_PLAY_TIME (include/constants/game_stat.h:5); compared against gameStats[1]",
  hofDebutMinutes = "see hofDebutHours",
  hofDebutSeconds = "see hofDebutHours",
  hofDebutTime = "see hofDebutHours",
  registeredTexts = "nil in the engine means the new-game defaults (src/union_room_chat.c InitUnionChatRegisteredTexts)",
  ["vars[0x403C]/flags[0x838]"] = "FRLG templateless export runs EnableNationalPokedex_RSE like NewGameInitData (pokefirered/src/new_game.c:133)",
  ["modData.*"] = "compared on the paths the reimport holds; engine-only sub-keys are listed as [engine-only]",
}
local engineOnly = {}

local function backDiff(a, b2, path, out)
  if type(b2) ~= "table" then
    if a ~= b2 then out[#out + 1] = { path, a, b2 } end
    return out
  end
  if type(a) ~= "table" then out[#out + 1] = { path, a, b2 } return out end
  for k, v in pairs(b2) do backDiff(a[k], v, path .. "." .. tostring(k), out) end
  for k in pairs(a) do
    if b2[k] == nil then
      local key = kindOf(path .. "." .. tostring(k))
      engineOnly[key] = (engineOnly[key] or 0) + 1
    end
  end
  return out
end
local excludedDiffs = {}

local function normaliseOrig(orig, back)
  local o = {}
  for k, v in pairs(orig) do o[k] = v end
  if bit.band(tonumber(o.specialSaveWarpFlags) or 0, 1) == 0 or type(o.continueGameWarp) ~= "table" then
    o.specialSaveWarpFlags = bit.bor(tonumber(o.specialSaveWarpFlags) or 0, 1)
    o.continueGameWarp = { map = o.map, warpId = -1, x = o.x, y = o.y }
  end
  local t = tonumber((o.gameStats or {})[1]) or 0
  if t ~= 0 and o.hofDebutHours == nil then
    o.hofDebutHours, o.hofDebutMinutes, o.hofDebutSeconds = math.floor(t / 65536), math.floor(t / 256) % 256, t % 256
    o.hofDebutTime = ("%d:%02d:%02d"):format(o.hofDebutHours, o.hofDebutMinutes, o.hofDebutSeconds)
  end
  if o.registeredTexts == nil then o.registeredTexts = back.registeredTexts end
  if L.RSE_NATIONAL_VAR and type(o.vars) == "table" and o.vars[L.RSE_NATIONAL_VAR] == nil then
    o.vars = deepcopy(o.vars)
    o.vars[L.RSE_NATIONAL_VAR] = L.RSE_NATIONAL_VALUE
    o.flags = deepcopy(o.flags or {})
    o.flags[L.RSE_NATIONAL_FLAG] = true
  end
  return o
end

local function r2(orig, back)
  orig = normaliseOrig(orig, back)
  for k in pairs(EXCLUDED_ROOTS) do
    if #D.diff(orig[k], back[k]) > 0 then excludedDiffs[k] = (excludedDiffs[k] or 0) + 1 end
  end
  local roots = {}
  for k in pairs(orig) do roots[k] = true end
  for k in pairs(back) do roots[k] = true end
  for k in pairs(roots) do
    if not EXCLUDED_ROOTS[k] then
      if k == "modData" then
        local a, b2 = orig.modData or {}, back.modData or {}
        local keys = {}
        for kk in pairs(a) do keys[kk] = true end
        for kk in pairs(b2) do keys[kk] = true end
        for kk in pairs(keys) do
          if not EXCLUDED_MODDATA[kk] then
            if kk == L.DAYCARE_SAVE_KEY then
              for _, d in ipairs(D.diff(effDaycare(a), effDaycare(b2))) do fail("r2", "modData." .. kk .. d, "orig", "reimport") end
            else
              for _, d in ipairs(backDiff(a[kk], b2[kk], "." .. kk, {})) do
                fail("r2", "modData" .. d[1], tostring(d[2]), tostring(d[3]))
              end
            end
          end
        end
      else
        local f = MODELED[k] or function(v) return v end
        local ea, eb = f(orig[k]), f(back[k])
        if type(ea) == "table" or type(eb) == "table" then
          for _, d in ipairs(D.diff(ea, eb)) do
            local function at(t)
              for seg in d:gmatch("[^.]+") do
                if type(t) ~= "table" then return t end
                local nk = tonumber(seg)
                if t[seg] ~= nil then t = t[seg] elseif nk and t[nk] ~= nil then t = t[nk] else return nil end
              end
              return t
            end
            fail("r2", k .. d, tostring(at(ea)), tostring(at(eb)))
          end
        elseif ea ~= eb then
          fail("r2", k, ea, eb)
        end
      end
    end
  end
end

local function editCheck(s, back, bytes, r)
  local save = deepcopy(back)
  local edits = {}
  save.money = (tonumber(save.money) or 0) == 777777 and 777776 or 777777
  edits.money = true
  local slot
  for i, m in ipairs(save.party or {}) do
    if not Mail.monHasMail(m) and not m.isEgg then slot = i end
  end
  local moved
  if slot and #save.party > 1 then
    local before = #save.party
    local ok, b, sl = Storage.deposit(save, slot, nil, nil)
    if ok then
      moved = { box = b, slot = sl, from = slot }
      same("edit", "deposit.partyCount", before - 1, #save.party)
    end
  end
  local before = deepcopy(save.bag)
  local added
  for _ = 1, 40 do
    local id = pick(r, ALL_ITEMS)
    if Bag.add(save.bag, id, 1) then added = id break end
  end
  local out, err = SaveConvert.exportSav(save, GAME, bytes)
  if not out then fail("edit", "export", "bytes", tostring(err)) return end
  local a, b2 = D.deep(bytes, FAMILY), D.deep(out, FAMILY)
  local xa, xb = D.extra(bytes, FAMILY), D.extra(out, FAMILY)
  same("edit", "money", save.money, b2.money)
  local allowed = { "%.counter$", "%.slot$", "^%.money$" }
  if moved then
    allowed[#allowed + 1] = "^%.party"
    allowed[#allowed + 1] = ("^%%.boxes%%.%d%%.%d"):format(moved.box, moved.slot)
    same("edit", "deposit.cartPartyCount", #save.party, #b2.party)
    local m = b2.boxes[moved.box][moved.slot]
    same("edit", "deposit.boxSpecies", back.party[moved.from].species, m and m.species)
  end
  if added then
    local pk = ItemsData.pocketOf(added)
    for p, pocket in ipairs(L.POCKETS) do
      if pocket.key == pk then allowed[#allowed + 1] = "^%.pockets%." .. p end
    end
    if pk == "TM_CASE" or pk == "BERRY_POUCH" then allowed[#allowed + 1] = "^%.pockets%.2" end
  end
  for _, d in ipairs(D.diff(a, b2)) do
    local ok = false
    for _, pat in ipairs(allowed) do if d:match(pat) then ok = true end end
    if not ok then fail("edit", "unintended" .. d, "unchanged", "changed") end
  end
  for _, d in ipairs(D.diff(xa, xb)) do fail("edit", "unintended.extra" .. d, "unchanged", "changed") end
  local ba, bb = D.blocks(bytes, FAMILY), D.blocks(out, FAMILY)
  if ba.sb2 ~= bb.sb2 then
    local diffs = 0
    for i = 1, #ba.sb2 do if ba.sb2:byte(i) ~= bb.sb2:byte(i) then diffs = diffs + 1 if diffs < 4 then fail("edit", ("sb2byte[0x%X]"):format(i - 1), ba.sb2:byte(i), bb.sb2:byte(i)) end end end
  end
  stats.edit = stats.edit + 1
end

local function writeDump(idx, bytes)
  if not DUMP or not bytes then return end
  local f = io.open(("%s/%s_%d_%d.sav"):format(DUMP, GAME, SEED, idx), "wb")
  if f then f:write(bytes) f:close() end
end

local t0 = os.clock()
for idx = 1, N do
  if not ONLY or ONLY == idx then
    CURRENT.idx = idx
    local ok, e = xpcall(function()
      local s, save, r, vals, blocks = buildSession(idx)
      stats.sessions = stats.sessions + 1
      local bytes, err = SaveConvert.exportSav(save, GAME, nil)
      if not bytes then fail("export", "exportSav", "bytes", tostring(err)) return end
      stats.exported = stats.exported + 1
      writeDump(idx, bytes)
      local report = Compat.check(bytes, GAME)
      if #report.errors > 0 then
        stats.compatErrors = stats.compatErrors + 1
        for _, ce in ipairs(report.errors) do fail("compat", ce.rule, "no error", ce.msg) end
      end
      if idx == (ONLY or 1) then
        CURRENT.dry = 0
        compareCart(s, save, bytes)
        local baseline = CURRENT.dry
        local keep = { s.money, s.party[1] and s.party[1].exp, s.storage.currentBox }
        s.money = (s.money + 1) % 1000000
        if s.party[1] then s.party[1].exp = s.party[1].exp + 1 end
        s.storage.currentBox = s.storage.currentBox % 14 + 1
        CURRENT.dry = 0
        compareCart(s, save, bytes)
        local caught = CURRENT.dry - baseline
        CURRENT.dry = nil
        s.money, s.storage.currentBox = keep[1], keep[3]
        if s.party[1] then s.party[1].exp = keep[2] end
        same("selftest", "decoder catches 2-3 planted engine edits", s.party[1] and 3 or 2, caught)
      end
      compareCart(s, save, bytes)
      local back, ierr = SaveConvert.importSav(bytes, GAME, GAME)
      if not back then fail("import", "importSav", "save", tostring(ierr)) return end
      local again = deepcopy(back)
      again.modData.cartImage = nil
      local bytes2, err2 = SaveConvert.exportSav(again, GAME, nil)
      if bytes2 ~= bytes then
        local first
        if bytes2 then for i = 1, #bytes do if bytes:byte(i) ~= bytes2:byte(i) then first = i - 1 break end end end
        fail("fixedpoint", "export(import(bytes))", "identical",
          bytes2 and ("first diff at flash 0x%X"):format(first or -1) or tostring(err2))
      else
        stats.fixedPoint = stats.fixedPoint + 1
      end
      local sb = D.blocks(bytes, FAMILY)
      local outCtx = { L = L, codec = CODEC, sb1 = sb.sb1, sb2 = sb.sb2 }
      local srcCtx = { L = L, codec = CODEC, sb1 = blocks.sb1, sb2 = blocks.sb2 }
      for _, sec in ipairs(SECTIONS) do
        if sec.read then
          stats.sectionReads = stats.sectionReads + 1
          for _, d in ipairs(D.diff(sec.read(srcCtx), sec.read(outCtx))) do
            fail("section", sec.name .. d, "random-cart read", "exported read")
          end
        end
      end
      r2(save, back)
      stats.r2 = stats.r2 + 1
      editCheck(s, back, bytes, r)
    end, debug.traceback)
    if not ok then fail("crash", "lua error", "no error", tostring(e):gsub("\n", " | ")) end
  end
end

local FIXTURE = os.getenv(EMERALD and "POKEPORT_EMERALD_SAV_FIXTURE" or "POKEPORT_FIRERED_SAV_FIXTURE")
if FIXTURE and FIXTURE ~= "" then
  CURRENT.idx = 0
  local f = io.open(FIXTURE, "rb")
  local src = f and f:read("*a")
  if f then f:close() end
  if not src then
    fail("fixture", "read " .. FIXTURE, "bytes", "missing")
  else
    local save, err = SaveConvert.importSav(src, GAME, GAME)
    if not save then
      fail("fixture", "importSav", "save", tostring(err))
    else
      local function decodeAll(bytes)
        local blk = D.blocks(bytes, FAMILY)
        local out = { deep = D.deep(bytes, FAMILY), extra = D.extra(bytes, FAMILY), sections = {} }
        out.deep.counter, out.deep.slot = nil, nil
        local ctx = { L = L, codec = CODEC, sb1 = blk.sb1, sb2 = blk.sb2 }
        for _, sec in ipairs(SECTIONS) do
          if sec.read then out.sections[sec.name] = sec.read(ctx) end
        end
        return out, blk
      end
      local orig, oblk = decodeAll(src)
      local withTpl, werr = SaveConvert.exportSav(deepcopy(save), GAME, src)
      if not withTpl then
        fail("fixture", "export with template", "bytes", tostring(werr))
      else
        local got, gblk = decodeAll(withTpl)
        for _, d in ipairs(D.diff(orig, got)) do fail("fixture", "withTemplate" .. d, "original", "changed") end
        for _, key in ipairs({ "sb1", "sb2", "storage" }) do
          if oblk[key] ~= gblk[key] then
            local first
            for i = 1, #oblk[key] do if oblk[key]:byte(i) ~= gblk[key]:byte(i) then first = i - 1 break end end
            fail("fixture", "withTemplate.bytes." .. key, "identical", ("first diff at 0x%X"):format(first or -1))
          end
        end
        stats.fixtureWithTemplate = 1
      end
      local bare = deepcopy(save)
      bare.modData.cartImage = nil
      local noTpl, nerr = SaveConvert.exportSav(bare, GAME, nil)
      if not noTpl then
        fail("fixture", "export without template", "bytes", tostring(nerr))
      else
        local got = decodeAll(noTpl)
        local gaps = {}
        for _, d in ipairs(D.diff(orig, got)) do
          local k = kindOf(d)
          gaps[k] = (gaps[k] or 0) + 1
        end
        local list = {}
        for k, n in pairs(gaps) do list[#list + 1] = ("%s x%d"):format(k, n) end
        table.sort(list)
        for _, line in ipairs(list) do print("[fixture-templateless-diff] " .. line) end
        stats.fixtureTemplatelessDiffKinds = #list
      end
    end
  end
end

print(("[info] %s seed=%d sessions=%d (%.1fs)"):format(GAME, SEED, stats.sessions, os.clock() - t0))
local keys = {}
for k in pairs(stats) do keys[#keys + 1] = k end
table.sort(keys)
local parts = {}
for _, k in ipairs(keys) do parts[#parts + 1] = k .. "=" .. stats[k] end
print("[coverage] " .. table.concat(parts, " "))
for k, n in pairs(excludedDiffs) do
  print(("[excluded] %s differed in %d sessions: %s"):format(k, n, EXCLUDED_ROOTS[k]))
end
for k, why in pairs(NORMALISED) do print(("[normalised] %s: %s"):format(k, why)) end
for k, n in pairs(engineOnly) do print(("[engine-only] modData%s in %d records"):format(k, n)) end
for _, kind in ipairs(kindOrder) do
  local rec = failureKinds[kind]
  local bug = knownBug(kind)
  print(("[FAIL] %s x%d in %d sessions%s; first: %s"):format(kind, rec.count, rec.sessionCount or 0,
    bug and (" [" .. bug:match("^%S+") .. "]") or " [UNCLASSIFIED]", rec.first))
end
local clean, cleanButKnown = 0, 0
for idx = 1, N do
  if not ONLY or ONLY == idx then
    if not sessionFails[idx] then clean = clean + 1 end
    if not sessionUnknown[idx] then cleanButKnown = cleanButKnown + 1 end
  end
end
print(("[summary] %s: %d/%d sessions fully clean, %d/%d clean apart from known bugs; %d unclassified failure kinds")
  :format(GAME, clean, stats.sessions, cleanButKnown, stats.sessions, (function()
    local n = 0
    for _, kind in ipairs(kindOrder) do if not knownBug(kind) then n = n + 1 end end
    return n
  end)()))
local bad = 0
for _ in pairs(failureKinds) do bad = bad + 1 end
print(failures == 0 and (LABEL .. ": all passed (" .. GAME .. ")")
  or (("%s: %d failed checks in %d kinds (%s)"):format(LABEL, failures, bad, GAME)))
os.exit(failures == 0 and 0 or 1)
