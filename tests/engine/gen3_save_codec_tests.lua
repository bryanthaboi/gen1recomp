package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Gen3Save = require("src.save_convert.Gen3Save")
local L = require("src.save_convert.Gen3Layout")
local SaveConvert = require("src.save_convert.SaveConvert")
local F = require("tests.fixture_data.gen3_saves")

local function unrle(s)
  local out = {}
  for tok in s:gmatch("%S+") do
    local k, n = tok:match("^([ZF])(%x+)$")
    if k then
      out[#out + 1] = string.rep(k == "Z" and "\0" or "\255", tonumber(n, 16))
    else
      out[#out + 1] = (tok:gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end))
    end
  end
  return table.concat(out)
end

local IMAGES = {}
for name, r in pairs(F.images) do IMAGES[name] = unrle(r) end

local function same(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local function show(v)
  if type(v) ~= "table" then return tostring(v) end
  local parts = {}
  for k, x in pairs(v) do parts[#parts + 1] = tostring(k) .. "=" .. show(x) end
  table.sort(parts)
  return "{" .. table.concat(parts, ",") .. "}"
end

local function same_eq(a, b, label)
  check(same(a, b), label .. " (" .. show(a) .. " vs " .. show(b) .. ")")
end

local function items(list)
  local out = {}
  for _, it in ipairs(list) do out[#out + 1] = { it.id, it.qty } end
  return out
end

local function plusOne(list)
  local out = {}
  for _, i in ipairs(list) do out[#out + 1] = i + 1 end
  return out
end

local function checkMon(label, m, o, party)
  eq(m.species, o.speciesInternal, label .. " species")
  eq(m.personality, o.pid, label .. " personality")
  eq(m.otId, o.tid, label .. " TID")
  eq(m.otSecretId, o.sid, label .. " SID")
  if o.nickname then eq(m.nickname, o.nickname, label .. " nickname") end
  if o.ot then eq(m.otName, o.ot, label .. " OT name") end
  eq(m.otGender, o.otGender, label .. " OT gender")
  eq(m.language, o.lang, label .. " language")
  eq(m.isEgg, o.isEgg, label .. " egg")
  eq(m.isBadEgg, o.badEgg, label .. " bad egg")
  eq(m.markings, o.markingsRaw, label .. " markings")
  eq(m.heldItem, o.heldItem, label .. " held item")
  eq(m.exp, o.exp, label .. " exp")
  eq(m.friendship, o.friendship, label .. " friendship")
  eq(m.ppBonuses, o.ppUps, label .. " PP ups")
  same_eq(m.moves, o.moves, label .. " moves")
  same_eq(m.pp, o.pp, label .. " PP")
  same_eq({ m.evs.hp, m.evs.atk, m.evs.def, m.evs.spe, m.evs.spa, m.evs.spd }, o.evs, label .. " EVs")
  local c = m.contest
  same_eq({ c.cool, c.beauty, c.cute, c.smart, c.tough, c.sheen }, o.contest, label .. " contest")
  eq(m.pokerus, o.pokerus, label .. " pokerus")
  eq(m.metLocation, o.metLocation, label .. " met location")
  eq(m.metLevel, o.metLevel, label .. " met level")
  eq(m.metGame, o.version, label .. " met game")
  eq(m.pokeball, o.ball, label .. " ball")
  local iv = m.ivs
  same_eq({ iv.hp, iv.atk, iv.def, iv.spe, iv.spa, iv.spd }, o.ivs, label .. " IVs")
  eq(m.abilityNum == 1, o.abilityBit, label .. " ability bit")
  eq(m.ribbons, o.ribbons, label .. " ribbons")
  eq(m.modernFatefulEncounter, o.fateful, label .. " fateful")
  eq(m.checksumOk, o.checksumValid, label .. " checksum")
  if party then
    same_eq({ m.status, m.level, m.hp, m.maxHp, m.attack, m.defense, m.speed, m.spAtk, m.spDef },
      { o.status, o.statLevel, o.hp, o.maxHp, o.stats[1], o.stats[2], o.stats[3], o.stats[4], o.stats[5] },
      label .. " party stats")
  end
end

local function checkOracle(name, c, o)
  eq(c.name, o.ot, name .. " player name")
  eq(c.gender, o.gender, name .. " gender")
  eq(c.trainerId, o.tid, name .. " TID")
  eq(c.secretId, o.sid, name .. " SID")
  same_eq({ c.playHours, c.playMinutes, c.playSeconds }, o.playTime, name .. " play time")
  eq(c.money, o.money, name .. " money")
  eq(c.coins, o.coins, name .. " coins")
  eq(c.encryptionKey, o.securityKey, name .. " encryption key")
  eq(c.rivalName, o.rival, name .. " rival")
  same_eq({ c.posX, c.posY }, o.pos, name .. " position")
  local w = c.location
  same_eq({ w.group, w.num, w.warpId, w.x, w.y }, o.location, name .. " location")
  w = c.lastHealLocation
  same_eq({ w.group, w.num, w.warpId, w.x, w.y }, o.heal, name .. " last heal location")
  same_eq(items(c.pockets.ITEMS), o.pouches.Items, name .. " items pocket")
  same_eq(items(c.pockets.KEY_ITEMS), o.pouches.KeyItems, name .. " key items")
  same_eq(items(c.pockets.POKE_BALLS), o.pouches.Balls, name .. " balls")
  same_eq(items(c.pockets.TM_CASE), o.pouches.TMHMs, name .. " TM case")
  same_eq(items(c.pockets.BERRY_POUCH), o.pouches.Berries, name .. " berry pouch")
  same_eq(items(c.pcItems), o.pouches.PCItems, name .. " PC items")
  same_eq(plusOne(c.dexSeen), o.seen, name .. " dex seen")
  same_eq(plusOne(c.dexOwned), o.caught, name .. " dex caught")
  same_eq(c.flags, o.flags, name .. " flags")
  local vars = {}
  for id, v in pairs(c.vars) do vars[tostring(id)] = v end
  local ovars = {}
  for id, v in pairs(o.vars) do ovars[tostring(id)] = v end
  same_eq(vars, ovars, name .. " vars")
  local stats = {}
  for id, v in pairs(c.gameStats) do stats[tostring(id)] = v end
  local ostats = {}
  for id, v in pairs(o.gameStats) do ostats[tostring(id)] = v end
  same_eq(stats, ostats, name .. " game stats")
  eq(c.storage.currentBox, o.currentBox, name .. " current box")
  local names, walls = {}, {}
  for b, box in ipairs(c.storage.boxes) do names[b], walls[b] = box.name, box.wallpaper end
  same_eq(names, o.boxNames, name .. " box names")
  same_eq(walls, o.walls, name .. " wallpapers")
  eq(#c.party, #o.party, name .. " party size")
  for i, om in ipairs(o.party) do checkMon(name .. " party " .. i, c.party[i], om, true) end
  local n = 0
  for bx, box in ipairs(c.storage.boxes) do
    for sl, mon in pairs(box.mons) do
      n = n + 1
      local found
      for _, ob in ipairs(o.boxes) do
        if ob.box == bx - 1 and ob.slot == sl - 1 then found = ob end
      end
      check(found ~= nil, name .. " box " .. bx .. " slot " .. sl .. " is in the oracle")
      if found then checkMon(name .. " box " .. bx .. "/" .. sl, mon, found.mon, false) end
    end
  end
  eq(n, #o.boxes, name .. " box mon count")
end

for _, name in ipairs({ "fr_rich_game", "lg_rich_game", "fr_bedroom" }) do
  local c, why = Gen3Save.decode(IMAGES[name])
  check(c ~= nil, name .. " decodes (" .. tostring(why) .. ")")
  if c then
    checkOracle(name, c, F.oracle[name])
    eq(c.olderSlot, false, name .. " reads the newest slot")
  end
end

local rich = IMAGES.fr_rich_game

do
  local c = assert(Gen3Save.decode(rich .. string.rep("\0", 16)))
  checkOracle("128K+16 trailer", c, F.oracle.fr_rich_game)
  local c64 = assert(Gen3Save.decode(rich:sub(1, 0x10000)))
  checkOracle("64K flash", c64, F.oracle.fr_rich_game)
  local c63 = Gen3Save.decode(rich .. string.rep("\0", 0x40))
  eq(c63, nil, "a 128K image with 64 extra bytes is refused")
end

local function poke(bytes, off, v)
  return bytes:sub(1, off) .. string.char(v) .. bytes:sub(off + 2)
end

do
  local corrupt = poke(rich, 24677, (rich:byte(24678) + 1) % 256)
  local c = assert(Gen3Save.decode(corrupt))
  eq(c.olderSlot, true, "a damaged newest slot falls back to the older one")
  checkOracle("older slot", c, F.oracle.fr_rich_pkhex)
  local save, err, note = SaveConvert.importSav(corrupt, "firered", "firered")
  check(save ~= nil, "the older slot imports (" .. tostring(err) .. ")")
  eq(note, Gen3Save.MSG.olderSlot, "the import says the previous save was used")
  local both = poke(corrupt, 14 * 0x1000 + 100, (corrupt:byte(14 * 0x1000 + 101) + 1) % 256)
  local _, bad = SaveConvert.importSav(both, "firered", "firered")
  eq(bad, Gen3Save.MSG.corrupt, "two damaged slots are refused")
  local _, empty = SaveConvert.importSav(string.rep("\255", 0x20000), "firered", "firered")
  eq(empty, Gen3Save.MSG.empty, "an erased flash is refused as empty")
  local _, small = SaveConvert.importSav(string.rep("\0", 32768), "firered", "firered")
  eq(small, Gen3Save.MSG.size:format(32768), "a 32 KB file gets the size sentence")
end

local function rebuild(bytes, patch)
  local blocks = assert(Gen3Save.readBlocks(bytes))
  patch(blocks)
  return Gen3Save.buildFlash(blocks, { counter = blocks.counter + 1 })
end

local function setByte(block, off, v) return block:sub(1, off) .. string.char(v) .. block:sub(off + 2) end

do
  local rs = rebuild(rich, function(b) b.sb2 = setByte(b.sb2, 0xAC, 0) end)
  local _, err = SaveConvert.importSav(rs, "firered", "firered")
  eq(err, Gen3Save.MSG.notFrlg, "a Ruby/Sapphire marker is refused")
  local jp = rebuild(rich, function(b) b.sb2 = setByte(setByte(b.sb2, 6, 0), 7, 0) end)
  local _, jerr = SaveConvert.importSav(jp, "firered", "firered")
  eq(jerr, Gen3Save.MSG.japanese, "a Japanese save is refused")
  local ok = assert(Gen3Save.decode(rebuild(rich, function() end)))
  checkOracle("rebuilt flash", ok, F.oracle.fr_rich_game)
end

math.randomseed(2444)
local function rnd(n) return math.random(0, n - 1) end
for order = 0, 23 do
  for trial = 1, 3 do
    local personality = (rnd(65536) * 65536 + rnd(65536)) - ((rnd(65536) * 65536 + rnd(65536)) % 24) + order
    personality = personality % 4294967296
    if personality % 24 ~= order then personality = personality - personality % 24 + order end
    local mon = {
      personality = personality,
      otIdRaw = rnd(65536) * 65536 + rnd(65536),
      nickname = "MON" .. order, language = 2, otName = "OT", markings = rnd(16),
      species = 1 + rnd(411), heldItem = rnd(376), exp = rnd(1000000), ppBonuses = rnd(256), friendship = rnd(256),
      growthFiller = 0,
      moves = { 1 + rnd(354), rnd(355), rnd(355), rnd(355) }, pp = { rnd(64), rnd(64), rnd(64), rnd(64) },
      evs = { hp = rnd(256), atk = rnd(256), def = rnd(256), spe = rnd(256), spa = rnd(256), spd = rnd(256) },
      contest = { cool = rnd(256), beauty = rnd(256), cute = rnd(256), smart = rnd(256), tough = rnd(256), sheen = rnd(256) },
      pokerus = rnd(256), metLocation = rnd(256), metLevel = rnd(101), metGame = rnd(16), pokeball = rnd(16), otGender = rnd(2),
      ivs = { hp = rnd(32), atk = rnd(32), def = rnd(32), spe = rnd(32), spa = rnd(32), spd = rnd(32) },
      isEgg = trial == 2, abilityNum = rnd(2), ribbons = rnd(65536) * 65536 + rnd(65536),
      isBadEgg = trial == 3, unknown = 0,
    }
    local raw = Gen3Save.encodeBoxMon(mon)
    eq(#raw, L.BOX_MON_SIZE, "order " .. order .. " encodes 80 bytes")
    local back = Gen3Save.decodeBoxMon(raw)
    eq(back.checksumOk, true, "order " .. order .. " trial " .. trial .. " checksum")
    for _, k in ipairs({ "personality", "otIdRaw", "nickname", "otName", "species", "heldItem", "exp", "ppBonuses",
        "friendship", "pokerus", "metLocation", "metLevel", "metGame", "pokeball", "otGender", "isEgg",
        "abilityNum", "ribbons", "markings", "isBadEgg" }) do
      eq(back[k], mon[k], "order " .. order .. " trial " .. trial .. " " .. k)
    end
    same_eq(back.moves, mon.moves, "order " .. order .. " moves")
    same_eq(back.ivs, mon.ivs, "order " .. order .. " IVs")
    same_eq(back.evs, mon.evs, "order " .. order .. " EVs")
    same_eq(back.contest, mon.contest, "order " .. order .. " contest")
    eq(back.isEggFlag, mon.isEgg, "order " .. order .. " egg flag byte")
    local tampered = poke(raw, 0x20 + rnd(48), (raw:byte(0x21) + 1) % 256)
    local bad = Gen3Save.decodeBoxMon(tampered)
    if not bad.checksumOk then
      eq(bad.isBadEgg, true, "order " .. order .. " a bad checksum reads as a bad egg")
    end
  end
end

local function strip(c)
  c.counter, c.slot, c.olderSlot = nil, nil, nil
  return c
end

for _, name in ipairs({ "fr_rich_game", "lg_rich_game", "fr_bedroom" }) do
  local c, blocks = Gen3Save.decode(IMAGES[name])
  local again = assert(Gen3Save.decode(Gen3Save.encode(c, { template = blocks, counter = c.counter + 1 })))
  same_eq(strip(again), strip(Gen3Save.decode(IMAGES[name])), name .. " encode(decode) with its template decodes identically")
  local c2 = Gen3Save.decode(IMAGES[name])
  local bare = assert(Gen3Save.decode(Gen3Save.encode(c2, { counter = 1 })))
  bare.player, c2.player = nil, nil
  same_eq(strip(bare), strip(c2), name .. " encode(decode) without a template decodes identically")
end

do
  local save, err, note = SaveConvert.importSav(rich, "firered", "firered")
  check(save ~= nil, "fr_rich_game converts to a port save (" .. tostring(err) .. ")")
  eq(note, nil, "a clean import has no fallback note")
  eq(save.engine, "game3", "port save engine")
  eq(save.version, "firered", "port save version")
  eq(save.name, "AAA", "port player name")
  eq(save.rivalName, "GREEN", "port rival name")
  eq(save.trainerId, 56718, "port TID")
  eq(save.secretId, 43871, "port SID")
  eq(save.money, 123456, "port money")
  eq(save.coins, 777, "port coins")
  eq(save.map, "FR_PLAYERS_HOUSE_2F", "port map")
  eq(save.x, 6, "port x")
  eq(save.y, 6, "port y")
  same_eq(save.playTime, { hours = 12, minutes = 35, seconds = 24, vblanks = 12 }, "port play time")
  eq(save.modData.cartImport.lastHealLocation.map, "FR_PALLET_TOWN", "the heal spot waits for the first load")
  local p = save.party
  eq(#p, 4, "port party size")
  eq(p[1].species, 6, "party 1 species")
  eq(p[1].nickname, "BLAZE", "party 1 nickname")
  eq(p[1].level, 36, "party 1 level")
  eq(p[1].hp, 50, "party 1 hp")
  eq(p[1].status, "PSN", "party 1 poisoned")
  eq(p[1].ppBonusesPacked, 3, "party 1 PP ups")
  eq(p[1].item, 200, "party 1 held item")
  eq(p[1].cartExtra.championRibbon, true, "party 1 champion ribbon kept")
  eq(p[1].cartImport, true, "party mons are finished on first load")
  eq(p[2].species, 277, "Treecko keeps its internal species")
  eq(p[2].otName, "PKHEX", "Treecko keeps its foreign OT")
  eq(p[3].isEgg, true, "the Pichu egg is an egg")
  eq(p[3].nickname, "EGG", "the egg is named EGG")
  eq(p[3].eggCycles, 10, "the egg keeps its cycles")
  eq(p[4].species, 201, "Unown")
  eq(p[4].cartExtra.modernFatefulEncounter, true, "Unown fateful bit kept")
  eq(save.storage.currentBox, 2, "current box is 1-based")
  eq(save.storage.boxes[2].mons[20].species, 150, "box 2 slot 20 straddles storage chunks")
  eq(save.storage.boxes[2].mons[20].level, nil, "box levels wait for the first load")
  eq(save.storage.boxes[14].mons[30].nickname, "SPARKY", "box 14 slot 30")
  eq(save.storage.boxes[8].mons[15].species, 410, "Deoxys in box 8")
  eq(save.storage.boxes[3].name, "CUSTOM", "a renamed box keeps its name")
  eq(save.storage.boxes[3].wallpaper, 6, "a changed wallpaper is 1-based")
  eq(save.storage.boxes[1].name, "BOX 1", "a default box name takes the port default")
  eq(save.storage.boxes[5].wallpaper, 5, "a default wallpaper takes the port default")
  same_eq(save.storage.items, { { id = 13, qty = 1 }, { id = 20, qty = 3 } }, "PC items")
  same_eq(save.bag.pockets.ITEMS, { { id = 13, qty = 10 }, { id = 68, qty = 5 }, { id = 23, qty = 99 } }, "bag items")
  same_eq(save.bag.pockets.KEY_ITEMS, { { id = 360, qty = 1 }, { id = 364, qty = 1 } }, "key items")
  for _, f in ipairs({ 0x820, 0x821, 0x828, 0x829 }) do
    eq(save.flags[f], true, ("flag 0x%X set"):format(f))
    eq(save.flags[tostring(f)], true, ("flag 0x%X set by string key"):format(f))
  end
  eq(save.flags[0x822], nil, "flag 0x822 clear")
  eq(save.vars[0x4050], 7, "var 0x4050")
  local nat = {}
  for _, n in ipairs(save.modData.cartImport.dexOwned) do nat[n] = true end
  eq(nat[252], true, "Treecko is caught under national 252")
  eq(nat[386], true, "Deoxys is caught under national 386")
  eq(save.dex.national, false, "national dex stays off")
  eq(save.game_cleared, false, "game not cleared")
  eq(save.options.textSpeed, 1, "text speed")
end

do
  local lg, err = SaveConvert.importSav(IMAGES.lg_rich_game, "firered", "firered")
  check(lg ~= nil, "a LeafGreen cart imports into FireRed (" .. tostring(err) .. ")")
  local fr, err2 = SaveConvert.importSav(rich, "leafgreen", "leafgreen")
  check(fr ~= nil, "a FireRed cart imports into LeafGreen (" .. tostring(err2) .. ")")
  eq(fr and fr.version, "leafgreen", "the import is stamped with the target game")
end

local STUB_NATIONAL = { [277] = 252, [410] = 386 }
local STUB_LAYOUT = { ["4:1"] = 2, ["3:0"] = 1, ["3:1"] = 79 }
local function stubOpts(extra)
  local o = {
    version = "firered",
    metGame = L.VERSION_FIRE_RED,
    toNational = function(sp) return STUB_NATIONAL[sp] or (sp >= 1 and sp <= 251 and sp or nil) end,
    speciesFromNational = function(n) for sp, nat in pairs(STUB_NATIONAL) do if nat == n then return sp end end return n end,
    speciesName = function(sp) return ({ [4] = "CHARMANDER", [16] = "PIDGEY", [172] = "PICHU" })[sp] end,
    mapLayoutId = function(g, n) return STUB_LAYOUT[g .. ":" .. n] end,
    healWarp = function() return { group = 3, num = 0, warpId = -1, x = 6, y = 8 } end,
  }
  for k, v in pairs(extra or {}) do o[k] = v end
  return o
end

local SaveSerializer = require("src.core.SaveSerializer")
local function reload(t) return SaveSerializer.decode(SaveSerializer.encode(t)) end

local function byteRuns(a, b)
  local runs, start = {}, nil
  for i = 1, #a + 1 do
    local d = i <= #a and a:byte(i) ~= b:byte(i)
    if d and not start then start = i - 1 end
    if not d and start then runs[#runs + 1] = { start, i - 2 }; start = nil end
  end
  return runs
end

local function onlyIn(runs, allowed)
  for _, r in ipairs(runs) do
    local ok = false
    for _, w in ipairs(allowed) do
      if r[1] >= w[1] and r[2] <= w[2] then ok = true end
    end
    if not ok then return false, string.format("0x%X-0x%X", r[1], r[2]) end
  end
  return true
end

do
  eq(SaveConvert.exportSupported("firered"), true, "FireRed cart export is supported")
  eq(SaveConvert.exportSupported("leafgreen"), true, "LeafGreen cart export is supported")

  local save = reload(assert(SaveConvert.importSav(rich, "firered", "firered")))
  local out = assert(Gen3Save.exportPort(save, stubOpts({ template = rich })))
  eq(#out, L.FLASH_SIZE, "a template export is a 128K flash image")
  local a, b = assert(Gen3Save.readBlocks(rich)), assert(Gen3Save.readBlocks(out))
  eq(b.counter, a.counter + 1, "the export is the next save after the cart's")
  local ok, where = onlyIn(byteRuns(a.sb2, b.sb2), { { 0x09, 0x09 } })
  check(ok, "SaveBlock2 only changes the continue flag (" .. tostring(where) .. ")")
  ok, where = onlyIn(byteRuns(a.sb1, b.sb1), { { 0x0C, 0x13 } })
  check(ok, "SaveBlock1 only changes the continue warp (" .. tostring(where) .. ")")
  eq(#byteRuns(a.storage, b.storage), 0, "PC storage is byte-identical")
  for s = 28, 31 do
    eq(out:sub(s * 0x1000 + 1, (s + 1) * 0x1000), rich:sub(s * 0x1000 + 1, (s + 1) * 0x1000),
      "sector " .. s .. " (Hall of Fame / Trainer Tower) is kept from the cart")
  end
  local c = assert(Gen3Save.decode(out))
  eq(c.specialSaveWarpFlags, L.CONTINUE_GAME_WARP, "the export continues through the continue-game warp")
  same_eq(c.continueGameWarp, { group = 4, num = 1, warpId = -1, x = 6, y = 6 }, "continue warp is the bedroom")
  eq(c.encryptionKey, a.sb2:byte(0xF21) + a.sb2:byte(0xF22) * 256 + a.sb2:byte(0xF23) * 65536 + a.sb2:byte(0xF24) * 16777216,
    "the cart's encryption key is kept for the unmodeled key-XORed fields")

  local again = reload(assert(SaveConvert.importSav(out, "firered", "firered")))
  local cw = again.continueGameWarp
  again.continueGameWarp, again.specialSaveWarpFlags = nil, nil
  local base = reload(save)
  base.continueGameWarp, base.specialSaveWarpFlags = nil, nil
  same_eq(again, base, "import(export(cart slot)) equals the slot")
  same_eq(cw, { map = "FR_PLAYERS_HOUSE_2F", warpId = -1, x = 6, y = 6 }, "the re-import sees the continue warp")

  local moved = reload(save)
  moved.map, moved.x, moved.y = "FR_VIRIDIAN_CITY", 26, 28
  moved.money = 777
  table.remove(moved.party, 4)
  moved.storage.boxes[2].mons[20] = nil
  moved.flags["FLAG_BADGE01_GET"] = nil
  moved.flags[0x820], moved.flags["2080"] = nil, nil
  moved.flags["FLAG_SYS_POKEDEX_GET"] = true
  moved.vars.VAR_STARTER_MON = 2
  local mb = assert(Gen3Save.exportPort(moved, stubOpts({ template = rich })))
  local m = assert(Gen3Save.decode(mb))
  same_eq(m.location, { group = 3, num = 1, warpId = -1, x = 26, y = 28 }, "a moved slot saves its new map")
  eq(m.mapLayoutId, 79, "the new map's layout id rides with it")
  eq(m.money, 777, "money change")
  eq(#m.party, 3, "a released party mon is gone")
  eq(m.storage.boxes[2].mons[20], nil, "a released box mon is gone")
  local fl = {}
  for _, id in ipairs(m.flags) do fl[id] = true end
  eq(fl[0x820], nil, "a cleared flag is cleared")
  eq(fl[0x829], true, "a flag set by name is set")
  eq(m.vars[0x4031], 2, "a var set by name is set")
  local mblk = assert(Gen3Save.readBlocks(mb))
  -- include/global.h:793
  eq(mblk.sb1:sub(0x1301, 0x2CA0), a.sb1:sub(0x1301, 0x2CA0), "the quest log is kept from the cart")
  -- include/global.h:352
  eq(mblk.sb2:sub(0x899, 0xAF0), a.sb2:sub(0x899, 0xAF0), "map view and link battle records are kept")
  -- include/global.h:807
  eq(mblk.sb1:sub(0x3121, 0x3A18), a.sb1:sub(0x3121, 0x3A18), "mystery gift data is kept")
end

local function portMon(o)
  local m = {
    species = 4, speciesNumbering = "internal", name = "CHARMANDER", nickname = "", level = 5, exp = 135,
    moves = { 10, 45 }, pp = { 35, 40 }, personality = 0x11223344,
    ivs = { hp = 1, atk = 2, def = 3, spe = 4, spa = 5, spd = 6 },
    evs = { hp = 7, atk = 8, def = 9, spe = 10, spa = 11, spd = 12 },
    friendship = 70, metLocation = 88, metLevel = 5, metGame = 4, pokeball = 4,
    otName = "PORT", otId = 12345, otSecretId = 54321, otGender = 1,
    hp = 20, maxHp = 20, attack = 11, defense = 10, speed = 12, spAtk = 11, spDef = 10,
  }
  for k, v in pairs(o or {}) do m[k] = v end
  return m
end

do
  local save = {
    engine = "game3", version = "firered", generation = 3,
    name = "PORT", rivalName = "RIVAL", gender = 1, trainerId = 12345, secretId = 54321,
    money = 4321, coins = 12, map = "FR_PALLET_TOWN", x = 12, y = 16, facing = "down",
    healMap = "FR_PLAYERS_HOUSE_1F", healX = 8, healY = 5,
    party = {
      portMon({ hp = 7, status = "PAR" }),
      portMon({ species = 16, name = "PIDGEY", nickname = "BIRDY", personality = 0x55667788, item = 13, heldItem = 13 }),
      portMon({ species = 172, name = "EGG", nickname = "EGG", isEgg = true, eggCycles = 10, personality = 0x0BADF00D }),
    },
    storage = {
      currentBox = 2,
      boxes = {
        [1] = { name = "BOX 1", wallpaper = 1, mons = { [5] = portMon({ species = 277, name = nil, nickname = "", personality = 0x99 }) } },
        [3] = { name = "MINE", wallpaper = 7, mons = {} },
      },
      items = { { id = 13, qty = 1 } },
    },
    bag = { pockets = { ITEMS = { { id = 13, qty = 3 } }, KEY_ITEMS = { { id = 360, qty = 1 } },
      POKE_BALLS = { { id = 4, qty = 5 } }, TM_CASE = {}, BERRY_POUCH = {} } },
    flags = { ["2088"] = true, [0x820] = true, FLAG_SYS_POKEDEX_GET = true, ["5"] = true },
    vars = { [0x4050] = 3, VAR_STARTER_MON = 1 },
    dex = { seen = { [4] = true, [16] = true, [277] = true }, owned = { [4] = true }, caught = { [4] = true }, national = false },
    playTime = { hours = 1, minutes = 2, seconds = 3, vblanks = 4 },
    options = { firered = { textSpeed = 2, battleScene = 1, battleStyle = 1, sound = 1, buttonMode = 1, frameType = 3 } },
    gameStats = { [2] = 5 },
    easyChatProfile = { 1, 2, 3, 4 },
    specialSaveWarpFlags = 0,
    hallOfFameTeams = { { { species = 6, level = 50, nickname = "CHAR", trainerId = 12345, otSecretId = 54321, personality = 99 } } },
    roamer = { active = true, species = 243, level = 50, hp = 100, statusNum = 0, pid = 7,
      ivs = { hp = 31, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 } },
    modData = { firered_daycare = { daycare = { [1] = portMon({ personality = 0x1234 }), steps = { 300, 0 } },
      route5Daycare = { steps = 0 } } },
  }
  local bytes, err = Gen3Save.exportPort(reload(save), stubOpts())
  check(bytes ~= nil, "a port-born slot exports without a template (" .. tostring(err) .. ")")
  eq(#bytes, L.FLASH_SIZE, "a fresh export is a 128K flash image")
  local c = assert(Gen3Save.decode(bytes))
  eq(c.counter, 1, "a fresh export is a first save")
  eq(c.encryptionKey, 0, "a fresh export starts with key 0")
  eq(c.specialSaveWarpFlags, L.CONTINUE_GAME_WARP, "continue-game warp flag set")
  same_eq(c.continueGameWarp, { group = 3, num = 0, warpId = -1, x = 12, y = 16 }, "continue warp is Pallet 12,16")
  same_eq(c.location, { group = 3, num = 0, warpId = -1, x = 12, y = 16 }, "location")
  eq(c.mapLayoutId, 1, "map layout id comes from the map header")
  eq(c.posX == 12 and c.posY == 16, true, "position")
  same_eq(c.lastHealLocation, { group = 3, num = 0, warpId = -1, x = 6, y = 8 }, "heal location")
  eq(c.name, "PORT", "player name")
  eq(c.rivalName, "RIVAL", "rival name")
  eq(c.gender, 1, "gender")
  eq(c.trainerId == 12345 and c.secretId == 54321, true, "TID/SID")
  eq(c.money, 4321, "money")
  eq(c.coins, 12, "coins")
  eq(c.playHours == 1 and c.playMinutes == 2 and c.playSeconds == 3, true, "play time")
  eq(c.options.textSpeed == 2 and c.options.battleScene == 1 and c.options.battleStyle == 1
    and c.options.sound == 1 and c.options.frameType == 3 and c.buttonMode == 1, true, "options from the game's options block")
  eq(#c.party, 3, "party size")
  local p1 = c.party[1]
  eq(p1.checksumOk, true, "party 1 checksum")
  eq(p1.species, 4, "party 1 species")
  eq(p1.nickname, "CHARMANDER", "an unnamed mon carries its species name like the cart")
  eq(p1.level, 5, "party 1 level")
  eq(p1.hp, 7, "party 1 hp")
  eq(p1.maxHp, 20, "party 1 max hp")
  eq(p1.status, L.STATUS.PAR, "party 1 paralysis")
  eq(p1.mail, 0xFF, "no mail")
  same_eq(p1.moves, { 10, 45, 0, 0 }, "party 1 moves")
  same_eq(p1.pp, { 35, 40, 0, 0 }, "party 1 pp")
  same_eq(p1.ivs, { hp = 1, atk = 2, def = 3, spe = 4, spa = 5, spd = 6 }, "party 1 IVs")
  eq(p1.otId == 12345 and p1.otSecretId == 54321 and p1.otName == "PORT", true, "party 1 OT")
  eq(p1.abilityNum, 0x11223344 % 2, "ability bit from personality")
  eq(p1.language, L.LANGUAGE_ENGLISH, "English")
  eq(c.party[2].nickname, "BIRDY", "nickname")
  eq(c.party[2].heldItem, 13, "held item")
  local egg = c.party[3]
  eq(egg.isEgg, true, "egg bit")
  eq(egg.language, L.LANGUAGE_JAPANESE, "a port egg is Japanese like CreateEgg")
  eq(egg.nicknameBytes:sub(1, 3), L.EGG_NICKNAME, "a port egg carries the egg nickname")
  eq(egg.friendship, 10, "egg cycles")
  eq(c.storage.currentBox, 1, "current box is 0-based")
  eq(c.storage.boxes[1].name, "BOX1", "default box name is the cart's")
  eq(c.storage.boxes[1].wallpaper, 0, "default wallpaper is the cart's")
  eq(c.storage.boxes[3].name, "MINE", "renamed box")
  eq(c.storage.boxes[3].wallpaper, 6, "wallpaper is 0-based")
  eq(c.storage.boxes[1].mons[5].species, 277, "box mon position")
  eq(c.storage.boxes[1].mons[5].exp, 135, "box mon exp")
  same_eq(c.pcItems, { { id = 13, qty = 1 } }, "PC items")
  same_eq(c.pockets.ITEMS, { { id = 13, qty = 3 } }, "bag items")
  same_eq(c.pockets.KEY_ITEMS, { { id = 360, qty = 1 } }, "key items")
  same_eq(c.pockets.POKE_BALLS, { { id = 4, qty = 5 } }, "balls")
  local fl = {}
  for _, id in ipairs(c.flags) do fl[id] = true end
  eq(fl[0x828] and fl[0x820] and fl[0x829], true, "flags by number, string and name")
  eq(fl[5], nil, "temp flags are not saved")
  eq(c.vars[0x4050], 3, "var by number")
  eq(c.vars[0x4031], 1, "var by name")
  same_eq(c.dexOwned, { 3 }, "owned bit is national order")
  same_eq(c.dexSeen, { 3, 15, 251 }, "seen bits use the national number (Treecko 252)")
  same_eq(c.dexSeen1, c.dexSeen, "seen1 matches")
  same_eq(c.dexSeen2, c.dexSeen, "seen2 matches")
  eq(c.dexNationalMagic, 0, "national dex off")
  eq(c.gameStats[2], 5, "game stat")
  same_eq({ c.easyChatProfile[1], c.easyChatProfile[2], c.easyChatProfile[3], c.easyChatProfile[4] }, { 1, 2, 3, 4 }, "profile words")
  eq(#c.hallOfFame, 1, "Hall of Fame team")
  eq(c.hallOfFame[1][1].species == 6 and c.hallOfFame[1][1].level == 50 and c.hallOfFame[1][1].nickname == "CHAR", true, "Hall of Fame mon")
  eq(c.roamer.species == 243 and c.roamer.active == 1 and c.roamer.ivs == 31 and c.roamer.personality == 7, true, "roamer")
  eq(c.daycare.mons[1] and c.daycare.mons[1].species, 4, "daycare mon")
  eq(c.daycare.steps[1], 300, "daycare steps")
  eq(c.daycare.mons[2], nil, "empty daycare slot")

  local back = assert(SaveConvert.importSav(bytes, "firered", "firered"))
  eq(back.name == "PORT" and back.rivalName == "RIVAL" and back.money == 4321 and back.coins == 12, true, "re-import: trainer")
  eq(back.map == "FR_PALLET_TOWN" and back.x == 12 and back.y == 16, true, "re-import: map")
  for i, m in ipairs(save.party) do
    local r = back.party[i]
    for _, k in ipairs({ "species", "level", "hp", "personality", "exp", "otId", "otSecretId", "metLevel", "pokeball", "otGender" }) do
      eq(r[k], m[k], ("re-import: party %d %s"):format(i, k))
    end
    same_eq(r.moves, m.moves, ("re-import: party %d moves"):format(i))
    same_eq(r.ivs, m.ivs, ("re-import: party %d IVs"):format(i))
    same_eq(r.evs, m.evs, ("re-import: party %d EVs"):format(i))
  end
  eq(back.party[1].status, "PAR", "re-import: status")
  eq(back.party[3].isEgg, true, "re-import: egg")
  eq(back.party[3].eggCycles, 10, "re-import: egg cycles")
  eq(back.storage.currentBox, 2, "re-import: current box")
  eq(back.storage.boxes[1].name, "BOX 1", "re-import: default box name")
  eq(back.storage.boxes[1].wallpaper, 1, "re-import: default wallpaper")
  eq(back.storage.boxes[3].name == "MINE" and back.storage.boxes[3].wallpaper == 7, true, "re-import: custom box")
  eq(back.storage.boxes[1].mons[5].species, 277, "re-import: box mon")
  same_eq(back.bag.pockets.ITEMS, save.bag.pockets.ITEMS, "re-import: bag")
  same_eq(back.storage.items, save.storage.items, "re-import: PC items")
  eq(back.flags[0x828] and back.flags[0x820] and back.flags[0x829], true, "re-import: flags")
  eq(back.vars[0x4050] == 3 and back.vars[0x4031] == 1, true, "re-import: vars")
  same_eq(back.modData.cartImport.dexOwned, { 4 }, "re-import: owned (national)")
  same_eq(back.modData.cartImport.dexSeen, { 4, 16, 252 }, "re-import: seen (national)")
  same_eq(back.playTime, save.playTime, "re-import: play time")
  eq(back.options.textSpeed == 2 and back.options.buttonMode == 1 and back.options.frameType == 3, true, "re-import: options")
  eq(back.gameStats[2], 5, "re-import: game stat")
  eq(back.hallOfFameTeams[1][1].species == 6 and back.hallOfFameTeams[1][1].trainerId == 12345
    and back.hallOfFameTeams[1][1].otSecretId == 54321, true, "re-import: Hall of Fame")
  eq(back.modData.firered_daycare.daycare[1].species, 4, "re-import: daycare")

  local _, noData = Gen3Save.exportPort(reload(save), stubOpts({ toNational = false }))
  eq(noData, Gen3Save.MSG.noData, "no species table refuses with the re-import sentence")
  local _, noLayout = Gen3Save.exportPort(reload(save), stubOpts({ mapLayoutId = function() return nil end }))
  eq(noLayout, Gen3Save.MSG.noData, "no map header refuses a fresh export")
  local lost = reload(save)
  lost.map = "FR_NOWHERE"
  local _, noMap = Gen3Save.exportPort(lost, stubOpts())
  eq(noMap, Gen3Save.MSG.noMap, "an unknown map is refused")
end

local function portSave(extra)
  local s = {
    engine = "game3", version = "firered", generation = 3,
    name = "PORT", rivalName = "RIVAL", gender = 0, trainerId = 12345, secretId = 54321,
    money = 3000, coins = 0, map = "FR_PALLET_TOWN", x = 12, y = 16, facing = "down",
    healMap = "FR_PLAYERS_HOUSE_1F", healX = 8, healY = 5,
    party = { portMon() },
    storage = { currentBox = 1, boxes = {}, items = {} },
    bag = { pockets = {} }, flags = {}, vars = {},
    dex = { seen = { [4] = true }, owned = { [4] = true }, caught = { [4] = true }, national = false },
    playTime = { hours = 1, minutes = 0, seconds = 0, vblanks = 0 }, options = {}, specialSaveWarpFlags = 0,
  }
  for k, v in pairs(extra or {}) do s[k] = v end
  return s
end

local function flagSet(c)
  local fl = {}
  for _, id in ipairs(c.flags) do fl[id] = true end
  return fl
end

do
  local N = L.NATIONAL_DEX
  local cases = {
    { "dex.nationalUnlocked", { dex = { seen = {}, owned = {}, caught = {}, national = false, nationalUnlocked = true } } },
    { "FLAG_SYS_NATIONAL_DEX alone", { flags = { ["2112"] = true } } },
    { "VAR_NATIONAL_DEX alone", { vars = { [0x404E] = 0x6258 } } },
  }
  for _, case in ipairs(cases) do
    local bytes = assert(Gen3Save.exportPort(reload(portSave(case[2])), stubOpts()))
    local c = assert(Gen3Save.decode(bytes))
    eq(c.dexNationalMagic, N.magic, case[1] .. ": the export carries the National Dex magic")
    eq(c.vars[N.var], N.varValue, case[1] .. ": VAR_NATIONAL_DEX")
    eq(flagSet(c)[N.flag], true, case[1] .. ": FLAG_SYS_NATIONAL_DEX")
    local back = assert(SaveConvert.importSav(bytes, "firered", "firered"))
    eq(back.dex.national == true and back.dex.nationalUnlocked == true, true, case[1] .. ": the re-import unlocks the port's National Dex")
  end
  local off = assert(Gen3Save.decode(assert(Gen3Save.exportPort(reload(portSave()), stubOpts()))))
  eq(off.dexNationalMagic, 0, "no unlock, no magic")
  eq(off.vars[N.var], nil, "no unlock, no var")
  local back = assert(SaveConvert.importSav(Gen3Save.exportPort(reload(portSave()), stubOpts()), "firered", "firered"))
  eq(back.dex.nationalUnlocked, nil, "no unlock stays locked on import")
end

do
  local ORANGE, HARBOR = 121, 122
  local words = { 1, 2, 3, 4, 5, 6, 7, 8, 9 }
  local save = portSave({
    party = {
      portMon({ item = ORANGE, heldItem = ORANGE, mail = 0 }),
      portMon({ species = 16, item = HARBOR, heldItem = HARBOR }),
      portMon({ species = 16, item = 13, heldItem = 13, mail = 3 }),
      portMon({ species = 16, item = HARBOR, heldItem = HARBOR, mail = 20 }),
    },
    mail = { { words = words, playerName = "PORT", trainerId = 12345, species = 4, itemId = ORANGE } },
    modData = { firered_daycare = {
      daycare = { [1] = portMon({ personality = 0x1234 }), steps = { 5, 0 },
        mail = { [1] = { otName = "PORT", monName = "CHARMANDER",
          message = { words = { 9, 8, 7, 6, 5, 4, 3, 2, 1 }, playerName = "PORT", trainerId = 12345, species = 4, itemId = HARBOR } } } },
      route5Daycare = { steps = 0 } } },
  })
  local bytes = assert(Gen3Save.exportPort(reload(save), stubOpts()))
  local c = assert(Gen3Save.decode(bytes))
  eq(c.party[1].mail, 0, "a port mon's mail index is exported")
  same_eq(c.mail[1].words, words, "the letter's words are in SaveBlock1.mail")
  eq(c.mail[1].itemId, ORANGE, "the letter's mail item")
  eq(c.mail[1].species, 4, "the letter's species")
  eq(c.mail[1].playerName, "PORT", "the letter's author")
  eq(c.mail[1].trainerIdRaw, 12345 + 54321 * 65536, "the player's own letter carries TID and SID")
  local blk = assert(Gen3Save.readBlocks(bytes))
  -- src/mail_data.c:58
  eq(blk.sb1:sub(L.MAIL.off + L.MAIL.playerName + 1, L.MAIL.off + L.MAIL.playerName + 8), "\xCA\xC9\xCC\xCE\x00\x00\xFF\xFF",
    "the author is space padded to 6 like GiveMailToMon")
  eq(c.party[2].mail, 1, "mail held without a letter gets a fresh letter slot")
  eq(c.mail[2].itemId, HARBOR, "the fresh letter is that mail")
  eq(c.party[3].mail, L.MAIL_NONE, "a non-mail item has no mail index")
  eq(c.party[4].mail, 2, "an index past the mail table is never exported")
  for i = 1, #c.party do check(c.party[i].mail == L.MAIL_NONE or c.party[i].mail < L.MAIL.count, "party " .. i .. " mail index in range") end
  eq(c.mail[4].itemId, 0, "unused letters are cleared")
  same_eq(c.mail[4].words, { 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF }, "cleared letters use EC_WORD_UNDEFINED")
  eq(c.mail[4].species, L.MAIL_CLEAR_SPECIES, "cleared letters use ClearMailStruct's species")
  eq(c.daycare.mail[1] and c.daycare.mail[1].message.itemId, HARBOR, "daycare mail is exported")
  eq(c.daycare.mail[1] and c.daycare.mail[1].monName, "CHARMANDER", "daycare mail mon name")

  local back = assert(SaveConvert.importSav(bytes, "firered", "firered"))
  eq(back.party[1].mail, 0, "import: mon.mail is the cart's index")
  same_eq(back.mail[1].words, words, "import: the letter lands in save.mail")
  eq(back.mail[1].itemId == ORANGE and back.mail[1].playerName == "PORT" and back.mail[1].trainerId == 12345, true, "import: letter header")
  eq(back.mail[1].design, 0, "import: letter design from the mail item")
  eq(back.party[3].mail, nil, "import: no mail index without a letter")
  eq(#back.mail, 16, "import: the whole mail table")
  eq(back.modData.firered_daycare.daycare.mail[1].message.itemId, HARBOR, "import: daycare mail")
  eq(back.party[1].cartExtra.mail, nil, "import: the index is not parked in cartExtra")
  local Mail = require("src.core.game3.mail")
  local restored = Mail.restore(back.mail)
  eq(Mail.monHasMail(back.party[1]) and not Mail.isEmpty(restored[back.party[1].mail + 1]), true, "import: the port sees the mon's letter")
end

do
  local bytes = assert(Gen3Save.exportPort(reload(portSave()), stubOpts({
    registeredTextDefaults = function() return { "HELLO", "POKéMON", "TRADE", "BATTLE", "LET'S", "OK!", "SORRY", "YAY{EMOJI_BIGSMILE}", "THANK YOU", "BYE-BYE!" } end,
  })))
  local c = assert(Gen3Save.decode(bytes))
  local blk = assert(Gen3Save.readBlocks(bytes))
  -- src/new_game.c:151
  same_eq(c.trainerTowerBest, { L.TRAINER_TOWER_MAX_TIME, L.TRAINER_TOWER_MAX_TIME, L.TRAINER_TOWER_MAX_TIME, L.TRAINER_TOWER_MAX_TIME },
    "a fresh export has no Trainer Tower times")
  -- src/easy_chat.c:440
  same_eq(c.easyChatBattle.start, { 4111, 2562, 3621, 3075, 2051, 3072 }, "default battle start words")
  same_eq(c.easyChatBattle.won, { 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF }, "battle won words undefined")
  same_eq(c.easyChatBattle.lost, { 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF }, "battle lost words undefined")
  -- src/fame_checker.c:1140
  eq(c.fameChecker[1].pickState, L.FCPICKSTATE_COLORED, "Fame Checker shows Oak")
  local others = 0
  for i = 2, 16 do others = others + c.fameChecker[i].pickState + c.fameChecker[i].flavorTextFlags end
  eq(others, 0, "Fame Checker has nobody else")
  eq(c.registeredTexts[1], "HELLO", "registered text defaults")
  eq(c.registeredTexts[8], "YAY{EMOJI_BIGSMILE}", "registered texts keep the emoji")
  eq(blk.sb1:sub(L.REGISTERED_TEXTS.off + 7 * 21 + 1, L.REGISTERED_TEXTS.off + 7 * 21 + 6), "\xD3\xBB\xD3\xF9\xF9\xFF",
    "the emoji is the cart's F9 F9 symbol")
  -- src/battle_records.c:274
  eq(blk.sb2:byte(L.LINK_BATTLE_RECORDS.off + 1), 0xFF, "link battle record names start empty")
  -- src/event_data.c:71
  eq(c.vars[L.RSE_NATIONAL_VAR], L.RSE_NATIONAL_VALUE, "EnableNationalPokedex_RSE var")
  eq(flagSet(c)[L.RSE_NATIONAL_FLAG], true, "EnableNationalPokedex_RSE flag")

  local fame = {}
  for i = 1, 16 do fame[i] = { pickState = 0, flavorTextFlags = 0 } end
  fame[1].pickState, fame[4] = 2, { pickState = 1, flavorTextFlags = 0x15 }
  local save = portSave({
    registeredTexts = { "HI", "", "", "", "", "", "", "YAY{EMOJI_BIGSMILE}", "", "" },
    modData = { fameChecker = fame, trainerTower = { challengeId = 0, records = { { bestTime = 3600 }, {}, {}, {} } } },
  })
  local b2 = assert(Gen3Save.exportPort(reload(save), stubOpts()))
  local c2 = assert(Gen3Save.decode(b2))
  eq(c2.fameChecker[4].pickState == 1 and c2.fameChecker[4].flavorTextFlags == 0x15, true, "port Fame Checker progress is exported")
  eq(c2.registeredTexts[1], "HI", "port registered texts are exported")
  eq(c2.trainerTowerBest[1], 3600, "port Trainer Tower best time is exported")
  eq(c2.trainerTowerBest[2], L.TRAINER_TOWER_MAX_TIME, "an unplayed Trainer Tower mode has no time")
  local back = assert(SaveConvert.importSav(b2, "firered", "firered"))
  eq(back.modData.fameChecker[4].pickState == 1 and back.modData.fameChecker[4].flavorTextFlags == 0x15, true, "import: Fame Checker progress")
  eq(back.modData.fameChecker[1].pickState, 2, "import: Oak")
  eq(back.registeredTexts[8], "YAY{EMOJI_BIGSMILE}", "import: registered texts")
  eq(back.modData.trainerTower.records[1].bestTime, 3600, "import: Trainer Tower best time")
end

do
  local stranger = reload(assert(SaveConvert.importSav(rich, "firered", "firered")))
  stranger.trainerId, stranger.secretId, stranger.name = 1111, 2222, "NEWBIE"
  stranger.hallOfFameTeams = {}
  local out = assert(Gen3Save.exportPort(stranger, stubOpts({ template = rich })))
  local c = assert(Gen3Save.decode(out))
  eq(c.counter, 1, "another player's cart is not used as the template (first save)")
  eq(c.encryptionKey, 0, "another player's key is not reused")
  eq(c.name, "NEWBIE", "the export is the slot's player")
  local other = out:sub(14 * 0x1000 * (1 - c.slot) + 1, 14 * 0x1000 * (2 - c.slot))
  eq(other, string.rep("\255", 14 * 0x1000), "no copy of the other player's save rides in the older slot")
  eq(out:sub(28 * 0x1000 + 1, 32 * 0x1000), string.rep("\255", 4 * 0x1000), "no Hall of Fame or Trainer Tower sectors from the other player")
  local cart = assert(Gen3Save.decode(rich))
  eq(Gen3Save.templateBelongs(Gen3Save.ownerOf(rich), stranger), false, "ownerOf tells the carts apart")
  eq(Gen3Save.templateBelongs(Gen3Save.ownerOf(rich), { trainerId = cart.trainerId, secretId = cart.secretId, name = cart.name }), true,
    "ownerOf matches the cart's own player")
end

do
  local c = assert(Gen3Save.decode(rich))
  local nat = c.dexOwned[1]
  local patched = rebuild(rich, function(b)
    local o = 0x5F8 + math.floor(nat / 8)
    b.sb1 = setByte(b.sb1, o, b.sb1:byte(o + 1) - (math.floor(b.sb1:byte(o + 1) / 2 ^ (nat % 8)) % 2) * 2 ^ (nat % 8))
    b.storage = setByte(b.storage, 0, 200)
  end)
  local save = assert(SaveConvert.importSav(patched, "firered", "firered"))
  local seen, owned = {}, {}
  for _, n in ipairs(save.modData.cartImport.dexSeen) do seen[n] = true end
  for _, n in ipairs(save.modData.cartImport.dexOwned) do owned[n] = true end
  -- src/pokedex_screen.c:2243
  eq(seen[nat + 1], nil, "a species missing from one seen copy is not seen")
  eq(owned[nat + 1], nil, "and not owned either")
  eq(save.storage.currentBox, L.STORAGE.totalBoxes, "an out-of-range current box is clamped")

  local bytes = assert(Gen3Save.exportPort(reload(portSave({ dex = { seen = {}, owned = { [4] = true }, caught = {} } })), stubOpts()))
  local e = assert(Gen3Save.decode(bytes))
  same_eq(e.dexSeen, { 3 }, "an owned species is written as seen")
  same_eq(e.dexSeen1, { 3 }, "seen1 too")
  same_eq(e.dexSeen2, { 3 }, "seen2 too")
end

do
  local function withCounter(img, slot, counter)
    local parts = {}
    for i = 0, 31 do
      local sec = img:sub(i * 0x1000 + 1, (i + 1) * 0x1000)
      if math.floor(i / 14) == slot and i < 28 then
        local v = counter
        sec = sec:sub(1, 0xFFC) .. string.char(v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
      end
      parts[#parts + 1] = sec
    end
    return table.concat(parts)
  end
  local c, blocks = Gen3Save.decode(rich)
  c.money = 111
  local a = Gen3Save.buildFlash(Gen3Save.encodeBlocks(c, blocks), { counter = 4 })
  c.money = 222
  local ab = Gen3Save.buildFlash(Gen3Save.encodeBlocks(c, blocks), { counter = 5, image = a })
  local odd = withCounter(ab, 0, 5)
  -- src/save.c:444
  eq(assert(Gen3Save.decode(odd)).money, 222, "equal odd counters load slot B like the cart")
  local even = withCounter(withCounter(ab, 1, 6), 0, 6)
  eq(assert(Gen3Save.decode(even)).money, 111, "equal even counters load slot A like the cart")
  eq(assert(Gen3Save.decode(ab)).money, 222, "the newer slot wins")
end

T.finish("gen3_save_codec")
