package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
T.verbose = true
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
Profile.reset()
GameVersion.set("emerald")

require("tests.game3_cache").mount("emerald")
local Dataset = require("src.core.game3.dataset")
local emCache = Dataset.cache()
local meta = emCache and emCache.read and emCache:read("data/generated/gba/meta.json")
if not (type(meta) == "string" and meta:find('"version":"emerald"', 1, true)) then
  print("emerald_link_loopback_test: skipped (no Emerald cache; set POKEPORT_IDENTITY)")
  os.exit(0)
end
require("src.import.gba.versions").select("emerald")
require("src.core.game3.song_ids").select("emerald")
local Pokemon = require("src.core.game3.pokemon")
Pokemon.install(nil)

local VersionsGame = require("src.import.gba.versions_game")
local Fingerprint = require("src.link.Fingerprint")
local Game3Link = require("src.link.Game3Link")
local Handshake = require("src.link.Handshake")
local Net = require("src.link.Net")
local Json = require("src.link.Json")
local Wire = require("src.link.Wire")
local Family = require("src.core.game3.link.family")
local C = require("src.core.game3.constants")
local EM, FR = C.of("emerald"), C.of("firered")

local HOME = os.getenv("HOME") or ""
local LOVE_ROOTS = { HOME .. "/Library/Application Support/LOVE", HOME .. "/.local/share/love" }

local function emRoot()
  local id = os.getenv("POKEPORT_IDENTITY") or ""
  for _, r in ipairs(LOVE_ROOTS) do
    local root = r .. "/" .. id .. "/emerald"
    local f = io.open(root .. "/data/generated/gba/meta.json", "rb")
    if f then f:close() return root end
  end
  return require("tests.game3_cache").gameDir("emerald")
end

local function frRoot()
  local frlg = VersionsGame.game("firered")
  local want = ('"cache_version":%d'):format(frlg.CACHE_VERSION)
  local candidates = {}
  local fromEnv = os.getenv("POKEPORT_FR_IDENTITY")
  for _, r in ipairs(LOVE_ROOTS) do
    if fromEnv and fromEnv ~= "" then candidates[#candidates + 1] = r .. "/" .. fromEnv .. "/firered" end
    local pipe = io.popen('ls -1t "' .. r .. '" 2>/dev/null')
    if pipe then
      for name in pipe:lines() do
        candidates[#candidates + 1] = r .. "/" .. name .. "/firered"
      end
      pipe:close()
    end
  end
  for _, root in ipairs(candidates) do
    local f = io.open(root .. "/data/generated/gba/meta.json", "rb")
    if f then
      local src = f:read("*a") or ""
      f:close()
      if src:gsub("%s", ""):find(want, 1, true) then return root end
    end
  end
  return nil
end

local function reader(root)
  return function(rel)
    if not root then return nil end
    local f = io.open(root .. "/" .. rel, "rb")
    if not f then return nil end
    local s = f:read("*a")
    f:close()
    return s
  end
end

print("[test] 1. link family tables follow pret")
eq(Family.cartVersion("emerald"), 3, "Emerald links as VERSION_EMERALD (global.h:10)")
eq(Family.cartVersion("firered"), 4, "FireRed links as VERSION_FIRE_RED")
eq(Family.cartVersion("leafgreen"), 5, "LeafGreen links as VERSION_LEAF_GREEN")
eq(Family.localLinkPlayer({ version = "emerald" }).version, 0x4003, "link player version = gGameVersion + 0x4000 (link.c:330)")
eq(Family.cableClubVar("emerald"), 0x4087, "Emerald VAR_CABLE_CLUB_STATE")
eq(Family.cableClubVar("firered"), 0x406F, "FireRed VAR_CABLE_CLUB_STATE unchanged")
eq(Family.mapId("emerald", "unionRoom"), "EM_UNION_ROOM", "Emerald union room map id")
eq(Family.mapId("emerald", "tradeCenter"), "EM_TRADE_CENTER", "Emerald trade center map id")
eq(Family.mapId("firered", "colosseum2P"), "FR_BATTLE_COLOSSEUM_2P", "FireRed colosseum map id unchanged")
eq(Family.activity("emerald").BATTLE_TOWER_OPEN, 14, "activity 14 is BATTLE_TOWER_OPEN on Emerald")
eq(Family.activity("emerald").ITEM_TRADE, nil, "Emerald has no ITEM_TRADE activity")
eq(Family.activity("firered").ITEM_TRADE, 14, "activity 14 is ITEM_TRADE on FireRed")
eq(Family.activity("emerald").CONTEST_TOUGH, 27, "Emerald contest activities 23..27")
eq(Family.groupActivity("emerald", 12).name, "RECORD_CORNER", "LINK_GROUP_RECORD_CORNER -> ACTIVITY_RECORD_CORNER")
eq(Family.groupActivity("emerald", 21).activity, 14, "LINK_GROUP_BATTLE_TOWER_OPEN -> 14")
eq(Family.groupActivity("firered", 12), nil, "FireRed has no group 12")
eq(Family.flag("emerald", Family.PROGRESS_FLAG.rse), 0x87F, "Emerald progress flag is FLAG_IS_CHAMPION (link.c:333)")
eq(Family.flag("firered", Family.PROGRESS_FLAG.frlg), 0x844, "FireRed progress flag is FLAG_SYS_CAN_LINK_WITH_RS")
local songs = Family.linkBattleSongs("emerald")
eq(songs.trainer, "MUS_VS_TRAINER", "Emerald cable club battle plays MUS_VS_TRAINER (cable_club.c:866)")
eq(Family.linkBattleSongs("firered").trainer, "MUS_RS_VS_TRAINER", "FireRed keeps MUS_RS_VS_TRAINER")

print("[test] 2. cross-version trade gates (trade.c:2453 / union_room.c:1266)")
local TR = Family.TRADE
local function lp(version, flags) return { version = version + 0x4000, progressFlags = flags } end
eq(Family.gameProgressForLinkTrade("rse", lp(3, 0), lp(3, 0)), TR.BOTH_PLAYERS_READY, "EM<->EM always trades")
eq(Family.gameProgressForLinkTrade("rse", lp(3, 0), lp(4, 0x10)), TR.PLAYER_NOT_READY, "EM not champion -> player not ready")
eq(Family.gameProgressForLinkTrade("rse", lp(3, 0x10), lp(4, 0)), TR.PARTNER_NOT_READY, "FR partner without Sevii -> partner not ready")
eq(Family.gameProgressForLinkTrade("rse", lp(3, 0x11), lp(5, 0x10)), TR.BOTH_PLAYERS_READY, "both progressed -> ready")
eq(Family.gameProgressForLinkTrade("frlg", lp(4, 0), lp(3, 0x10)), TR.PLAYER_NOT_READY, "FR side needs its own flag first")
eq(Family.gameProgressForLinkTrade("frlg", lp(4, 0x10), lp(3, 0)), TR.PARTNER_NOT_READY, "FR side needs the EM champion")
eq(Family.gameProgressForLinkTrade("frlg", lp(4, 0x10), lp(2, 0)), TR.BOTH_PLAYERS_READY, "FR vs RS only checks the player (trade.c:2842)")
eq(Family.gameProgressForLinkTrade("frlg", lp(4, 0), lp(5, 0)), TR.BOTH_PLAYERS_READY, "FR<->LG always trades")
local UR = Family.UR_TRADE
eq(Family.tradeAcrossVersionTooSoon("rse", { trading = true, partnerVersion = 4, specialSaveWarpFlags = 0 }),
  UR.PLAYER_NOT_READY, "Emerald union room trade with FR before the HoF warp")
eq(Family.tradeAcrossVersionTooSoon("rse", { trading = true, partnerVersion = 4, specialSaveWarpFlags = 0x80 }),
  UR.PARTNER_NOT_READY, "partner that cannot link nationally")
eq(Family.tradeAcrossVersionTooSoon("rse", { trading = true, partnerVersion = 4, specialSaveWarpFlags = 0x80,
  partnerCanLinkNationally = true }), UR.READY, "both ready")
eq(Family.tradeAcrossVersionTooSoon("rse", { trading = true, partnerVersion = 3 }), UR.READY, "Emerald partner is home")

print("[test] 3. CanTradeSelectedMon on Emerald (trade.c:2389)")
local EGG = EM:require("species", "SPECIES_EGG")
local party = { { species = 277 }, { species = 1 }, { species = 280, isEgg = true } }
eq(Family.canTradeSelectedMon("emerald", party, 0, { nationalDex = false }), Family.CAN_TRADE_MON, "Treecko (Hoenn) trades without the National Dex")
eq(Family.canTradeSelectedMon("emerald", party, 1, { nationalDex = false }), Family.CANT_TRADE_NATIONAL, "Bulbasaur needs the National Dex")
eq(Family.canTradeSelectedMon("emerald", party, 2, { nationalDex = false }), Family.CANT_TRADE_EGG_YET, "an egg needs the National Dex")
eq(Family.canTradeSelectedMon("emerald", party, 1, { nationalDex = true, partner = { version = 4, progressFlags = 0 } }),
  Family.CANT_TRADE_INVALID_MON, "partner without the National Dex cannot take Bulbasaur")
eq(Family.canTradeSelectedMon("emerald", party, 1, { nationalDex = true, partner = { version = 2, progressFlags = 0 } }),
  Family.CAN_TRADE_MON, "Ruby partners skip the partner check")
eq(Family.canTradeSelectedMon("emerald", { { species = 277 }, { species = 280, isEgg = true } }, 0, { nationalDex = true }),
  Family.CANT_TRADE_LAST_MON, "eggs do not count as a mon left for battle")
eq(EGG, 412, "SPECIES_EGG by name")

print("[test] 3b. Direct Corner trade gate reads the partner avatar (union_room.c:1051)")
do
  local Link = require("src.core.game3.link")
  local Union = require("src.core.game3.link.union_room")
  local saved = { session = Link.session, clientCall = Link.clientCall }
  local sess = { version = "emerald", specialSaveWarpFlags = 0x80 }
  local entries, room = {}, nil
  Link.session = function() return sess end
  Link.clientCall = function(name)
    if name == "directEntries" then return entries end
    if name == "you" then return { id = "me" } end
    if name == "room" then return room end
    return nil
  end
  local ok, err = pcall(function()
    entries = {
      { kind = "player", id = "p1", avatar = { name = "RED", version = "firered", canLinkNationally = false } },
      { kind = "player", id = "p2", avatar = { name = "LEAF", version = "leafgreen", canLinkNationally = true } },
      { kind = "player", id = "p3", avatar = { name = "OLD", version = "firered" } },
      { kind = "room", room = "r1", host = "h1", avatar = { name = "HOST", version = "firered", canLinkNationally = false } },
      { kind = "player", id = "p4", avatar = { name = "MAY", version = "emerald", canLinkNationally = false } },
    }
    local rows = Union.directRows("trade")
    eq(Union.tradeReadyWith(rows[1]), UR.PARTNER_NOT_READY, "FR partner that cannot link nationally is refused")
    eq(Union.tradeReadyWith(rows[2]), UR.READY, "LG partner that can link nationally trades")
    eq(Union.tradeReadyWith(rows[3]), UR.PARTNER_NOT_READY, "an avatar without the capability is never assumed ready")
    eq(rows[4].version, "firered", "a hosted room row carries the host version")
    eq(Union.tradeReadyWith(rows[4]), UR.PARTNER_NOT_READY, "a hosted FR room is gated too")
    eq(Union.tradeReadyWith(rows[5]), UR.READY, "an Emerald partner is home")
    sess.specialSaveWarpFlags = 0
    eq(Union.tradeReadyWith(rows[2]), UR.PLAYER_NOT_READY, "before the HoF warp the player is not ready")
    sess.specialSaveWarpFlags = 0x80
    room = { players = { { id = "me", avatar = { version = "emerald" } },
      { id = "x", avatar = { name = "RED", version = "firered", canLinkNationally = false } } } }
    eq(Union.tradeReadyWith(Union.roomPartnerAvatar(room)), UR.PARTNER_NOT_READY,
      "the matched room partner is checked on this side too")
    sess.flags = {}
    local av = Link.avatar()
    eq(av.canLinkNationally, false, "the avatar carries FLAG_IS_CHAMPION as canLinkNationally")
  end)
  Link.session, Link.clientCall = saved.session, saved.clientCall
  check(ok, "direct corner gate checks ran: " .. tostring(err))
end

print("[test] 4. the [rules] row and the Emerald hello")
local emRules, frRules = Fingerprint.rulesGen3("emerald"), Fingerprint.rulesGen3("firered")
check(type(emRules) == "string" and #emRules == 16, "Emerald rules digest")
check(emRules ~= frRules, "Emerald and FireRed battle rules differ")
eq(Fingerprint.rulesGen3("leafgreen"), frRules, "LeafGreen shares FireRed's rules")
eq(Fingerprint.rulesGen3("emerald"), emRules, "the digest is stable")
local emPath = emRoot()
local emInputs = emPath and Fingerprint.gen3Inputs(reader(emPath)) or nil
local function gameFor(version, inputs, session)
  return { version = version, data = { generation = 3, gen3Inputs = inputs }, session = session,
    save = { player = { name = session.name } } }
end
local maySession, emGame, emHello
if not emInputs then
  print("[skip] section 4 hello checks: no current Emerald cache found (set POKEPORT_IDENTITY)")
else
  maySession = { version = "emerald", name = "MAY", trainerId = 0x1111, gender = 1, dex = {},
    store = { flags = { [0x87F] = true }, vars = {} } }
  emGame = gameFor("emerald", emInputs, maySession)
  emHello = Game3Link.hello(emGame, Game3Link.LINKTYPE.TRADE, { session = maySession })
  eq(emHello.game3.version, "emerald", "hello names the version")
  eq(emHello.game3.family, "rse", "hello names the family")
  eq(emHello.game3.gameVersion, 0x4003, "hello carries the link player version")
  eq(emHello.game3.progressFlags, 0x10, "hello carries FLAG_IS_CHAMPION as progress bit 0x10")
  eq(emHello.game3.cacheVersion, VersionsGame.game("emerald").CACHE_VERSION, "hello stamps the Emerald importer")
  eq(emHello.game3.rules, emRules, "hello carries the rules digest")
end

print("[test] 5. FireRed <-> Emerald over a loopback link")
local frPath = frRoot()
local frInputs = frPath and Fingerprint.gen3Inputs(reader(frPath)) or nil
if not (frInputs and emHello) then
  print("[skip] section 5: need both Emerald and FireRed cache (set POKEPORT_IDENTITY, POKEPORT_FR_IDENTITY)")
else
  print("[info] FireRed cache at " .. frPath)
  local redSession = { version = "firered", name = "RED", trainerId = 0x2222, gender = 0, dex = {},
    store = { flags = { [0x844] = true }, vars = {} } }
  local frGame = gameFor("firered", frInputs, redSession)
  local frHello = Game3Link.hello(frGame, Game3Link.LINKTYPE.TRADE, { session = redSession })
  check(frHello.fingerprint ~= emHello.fingerprint, "FireRed and Emerald data surfaces differ (3 moves: battle_moves.h)")
  eq(Handshake.checkCompat(emHello, frHello), "subset", "the plain handshake calls it a subset")
  local verdict, why, cross = Game3Link.decideOne(emHello, frHello, Game3Link.LINKTYPE.TRADE)
  eq(verdict, "full", "a cross-version TRADE pairs: " .. tostring(why))
  eq(cross, true, "and is marked cross-version")
  local hosted
  verdict, why, cross, hosted = Game3Link.decideOne(emHello, frHello, Game3Link.LINKTYPE.BATTLE)
  eq(verdict, "full", "a cross-version BATTLE pairs: " .. tostring(why))
  eq(hosted, true, "on the host's battle rules")
  local moddedFr = {}
  for k, v in pairs(frHello) do moddedFr[k] = v end
  moddedFr.linkModified = true
  verdict, why = Game3Link.decideOne(emHello, moddedFr, Game3Link.LINKTYPE.BATTLE)
  eq(verdict, "refused", "a link-modified cross-version BATTLE is refused")
  eq(why, "fingerprint_mismatch", "because the lockstep surfaces differ")
  local lines = Handshake.describe(emHello, frHello, "subset", "battle")
  eq(lines[2], "FIRERED.", "the notice names the other game")
  eq(lines[3], "Link battles need", "and says why a battle can't start")
  local stripped = Wire.sanitize(Json.decode(Json.encode(frHello)))
  stripped.game3.version, stripped.game3.family, stripped.game3.rules = nil, nil, nil
  verdict, why = Game3Link.decideOne(emHello, stripped, Game3Link.LINKTYPE.TRADE)
  eq(verdict, "full", "a legacy FireRed hello still pairs for trade: " .. tostring(why))
  local emStripped = Wire.sanitize(Json.decode(Json.encode(emHello)))
  emStripped.game3.version, emStripped.game3.family, emStripped.game3.rules = nil, nil, nil
  verdict, why = Game3Link.decideOne(frHello, emStripped, Game3Link.LINKTYPE.TRADE)
  eq(verdict, "full", "a relay-stripped Emerald hello is recognised by its importer stamps: " .. tostring(why))

  local function pair(linkType, gameA, gameB, sessA, sessB)
    local a, b = Net.loopbackPair()
    local readyA, readyB = false, false
    local la = Game3Link.attach(a, { seat = 0, seats = 2, linkType = linkType,
      hello = Game3Link.hello(gameA, linkType, { session = sessA }), game = gameA,
      onReady = function() readyA = true end })
    local lb = Game3Link.attach(b, { seat = 1, seats = 2, linkType = linkType,
      hello = Game3Link.hello(gameB, linkType, { session = sessB }), game = gameB,
      onReady = function() readyB = true end })
    for _ = 1, 4 do la:update(1 / 60) lb:update(1 / 60) end
    return la, lb, readyA, readyB
  end
  local la, lb, ra, rb = pair(Game3Link.LINKTYPE.TRADE, emGame, frGame, maySession, redSession)
  check(ra and rb and la:isReady() and lb:isReady(), "EM host + FR guest reach ready for a trade")
  check(la.crossVersion and lb.crossVersion, "both ends know the partner is the other family")
  eq(la:peerGame() and la:peerGame().version, "firered", "Emerald sees a FireRed partner")
  eq(lb:peerGame() and lb:peerGame().family, "rse", "FireRed sees an Emerald partner")
  la:close("done") lb:update(0)
  la, lb, ra, rb = pair(Game3Link.LINKTYPE.BATTLE, emGame, frGame, maySession, redSession)
  check(ra and rb and la:isReady() and lb:isReady(), "a FR<->EM link battle reaches ready")
  check(la.hostRules and lb.hostRules, "both ends run it on the host's rules")
  la:close("done") lb:update(0)
  la, lb, ra, rb = pair(Game3Link.LINKTYPE.BATTLE, emGame, gameFor("emerald", emInputs,
    { version = "emerald", name = "WALLY", trainerId = 0x3333, gender = 0, dex = {}, store = { flags = {}, vars = {} } }),
    maySession, nil)
  check(ra and rb and la:isReady() and lb:isReady(), "EM<->EM reaches ready for a battle")
  la:close("done")
end

print("[test] 6. FireRed <-> Emerald trade between two saves")
do
  local Schema = require("src.core.game3.save_schema_firered")
  local Party = require("src.core.game3.party")
  local SaveData = require("src.core.SaveData")
  local Trade = require("src.online.Trade")
  local files = {}
  SaveData.portableFs = function()
    return {
      getInfo = function(n) return files[n] and { type = "file" } or nil end,
      read = function(n) return files[n] end,
      write = function(n, b) files[n] = b return true end,
      remove = function(n) files[n] = nil return true end,
      createDirectory = function() return true end,
    }
  end
  local function makeSave(version, name, tid, mons)
    local s = Schema.newGame({ version = version, name = name, rngSeed = tid })
    s.trainerId = tid
    s.party = {}
    for _, row in ipairs(mons) do assert(Party.giveMon(s, row[1], row[2])) end
    return SaveData.decode(SaveData.encode(Schema.toSaveTable(s)))
  end
  local DATA = { generation = 3, Pokemon = Pokemon }
  local function handle(version, slot, save)
    return { version = version, generation = 3, slotId = slot, save = save,
      path = Trade.slotPath(version, slot), party = save.party, data = DATA }
  end
  local fr = makeSave("firered", "RED", 11111, { { 25, 12 }, { 16, 5 } })
  local em = makeSave("emerald", "MAY", 22222, { { 277, 10 }, { 280, 7 }, { 1, 5 } })
  eq(Trade.partnerInfo3(handle("emerald", "s", em)).version, 3, "an Emerald save announces VERSION_EMERALD")
  local plan, why = Trade.plan({ from = handle("firered", "s1", fr), to = handle("emerald", "s1", em),
    fromIndex = 1, toIndex = 1 })
  eq(plan, nil, "no cross-version trade before either side has progressed")
  eq(why, "you can't trade with that game yet", "and it says why")
  em.flags = em.flags or {}
  em.flags[EM:flag("FLAG_IS_CHAMPION")] = true
  fr.flags = fr.flags or {}
  fr.flags[FR:flag("FLAG_SYS_CAN_LINK_WITH_RS")] = true
  eq(Trade.partnerInfo3(handle("emerald", "s", em)).progressFlags, 0x10, "the champion flag sets progress bit 0x10")
  _, why = Trade.plan({ from = handle("firered", "s1", fr), to = handle("emerald", "s1", em),
    fromIndex = 1, toIndex = 3 })
  eq(why, "that POKéMON can't be traded now", "Emerald can't send Bulbasaur without the National Dex")
  plan, why = Trade.plan({ from = handle("firered", "s1", fr), to = handle("emerald", "s1", em),
    fromIndex = 1, toIndex = 1 })
  check(plan ~= nil, "FireRed's Pikachu for Emerald's Treecko plans: " .. tostring(why))
  eq(plan and plan.get.species, 277, "FireRed receives Treecko")
  eq(plan and plan.give.species, 25, "Emerald receives Pikachu")
  eq(plan and plan.give.otName, "RED", "Pikachu keeps its FireRed OT")
  eq(plan and plan.get.otName, "MAY", "Treecko keeps its Emerald OT")
  local ok, err = Trade.commit(plan)
  check(ok, "the trade commits: " .. tostring(err))
  local frNow = SaveData.decode(files["saves/firered/s1.lua"] or "")
  local emNow = SaveData.decode(files["saves/emerald/s1.lua"] or "")
  eq(frNow and frNow.party[1].species, 277, "the FireRed file holds Treecko")
  eq(emNow and emNow.party[1].species, 25, "the Emerald file holds Pikachu")
  eq(emNow and emNow.version, "emerald", "the Emerald file is still an Emerald save")
  check(emNow and pcall(Schema.fromSaveTable, emNow), "the Emerald file loads back")
  check(frNow and pcall(Schema.fromSaveTable, frNow), "the FireRed file loads back")
end

print("[test] 7. record mixing packets cross the wire and merge")
do
  local Schema = require("src.core.game3.save_schema_firered")
  local RecordMix = require("src.core.game3.link.record_mix")
  local Dew = require("src.core.game3.rse.dewford_trend")
  local a = Schema.newGame({ version = "emerald", name = "MAY", rngSeed = 1 })
  a.trainerId = 1111
  local b = Schema.newGame({ version = "emerald", name = "BRENDAN", rngSeed = 2 })
  b.trainerId = 2222
  local pa, pb = RecordMix.packet(a), RecordMix.packet(b)
  check(type(pa.tvShows) == "table" and type(pa.dewfordTrends) == "table", "the packet carries TV shows and trends")
  local sent = Wire.sanitize(Json.decode(Json.encode({ type = RecordMix.MSG.PACKET, spot = 1, packet = RecordMix.toWire(pb) })))
  check(sent ~= nil, "the packet survives Wire.sanitize")
  local got = sent and RecordMix.fromWire(sent.packet) or {}
  eq(got.trainerId, 2222, "the partner's trainer id arrives")
  check(type(got.tvShows) == "table" and got.tvShows[0] ~= nil, "0-based TV show slots survive JSON")
  local before = {}
  for i, t in ipairs(Dew.trends(b)) do before[i] = Dew.phraseString(i - 1, b) end
  local applied = RecordMix.receive(a, { pa, got }, 1)
  check(applied.tvShows and applied.pokeNews, "ReceiveTvShowsData / ReceivePokeNewsData ran")
  check(applied.dewfordTrends, "ReceiveDewfordTrendData ran")
  check(applied.secretBases, "ReceiveSecretBasesData hook ran")
  local seen = {}
  for i = 0, #Dew.trends(a) - 1 do seen[Dew.phraseString(i, a)] = true end
  local merged = 0
  for _, phrase in ipairs(before) do if seen[phrase] then merged = merged + 1 end end
  check(merged > 0, "MAY's Dewford trends now include BRENDAN's (" .. merged .. ")")
end

print("[test] 8. Emerald <-> Emerald link battle over the relay")
do
  local H = require("tests.link3_harness")
  local Cache = require("tests.game3_cache")
  local ExtractScripts = require("src.import.gba.extract_scripts")
  local emPath = emRoot()
  if not emPath then
    print("[skip] section 8: no current Emerald cache found (set POKEPORT_IDENTITY)")
  else
    H.bundle = ExtractScripts.loadBundle(Cache.cache(), emPath .. "/data/generated/gba", { allowIncomplete = true })
    local function mon(species, level)
      return H.legal({ species = species, level = level, moves = Pokemon.movesAtLevel(species, level), personality = 0,
        ivs = { hp = 20, atk = 20, def = 20, spe = 20, spa = 20, spd = 20 },
        evs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 }, item = 0 })
    end
    local function session(name, tid, g)
      return { name = name, trainerId = tid, gender = g, party = {}, bag = {}, version = "emerald" }
    end
    local function policy(w, st)
      local m = st.player and st.player.mon or {}
      local usable = {}
      for i = 1, 4 do
        if m.moves and m.moves[i] and (tonumber(m.pp and m.pp[i]) or 0) > 0 then usable[#usable + 1] = i end
      end
      w.Ui._pendingCommand = w.Commands.playerAction(st, 1, usable[((st.turn or 0) % math.max(1, #usable)) + 1] or 1)
    end
    local relay = H.relay({ seed = 0x4242, seats = 2, roomSeed = 0x4242 })
    local w0 = H.newWorld("may", session("MAY", 0x1234, 1))
    H.run(w0, function()
      require("src.core.GameVersion").set("emerald")
      require("src.core.game3.song_ids").select("emerald")
    end)
    local w1 = H.newWorld("brendan", session("BRENDAN", 0x5678, 0))
    H.run(w1, function()
      require("src.core.GameVersion").set("emerald")
      require("src.core.game3.song_ids").select("emerald")
    end)
    H.attachSeat(w0, relay, 0, { mode = "single", myParty = H.pack({ mon(277, 50), mon(280, 50) }), profile = { rule = {} } })
    H.attachSeat(w1, relay, 1, { mode = "single", myParty = H.pack({ mon(283, 50), mon(286, 50) }), profile = { rule = {} } })
    local frames = 0
    while frames < 20000 do
      frames = frames + 1
      H.step(w0, policy)
      H.step(w1, policy)
      relay:tick()
      if w0.result and w1.result then break end
    end
    local MIRROR = { win = "lose", lose = "win", draw = "draw" }
    check(w0.result ~= nil and w1.result ~= nil, "both Emerald seats finished (" .. frames .. " frames)")
    eq(MIRROR[w0.result], w1.result, "the results mirror (" .. tostring(w0.result) .. "/" .. tostring(w1.result) .. ")")
    eq(H.run(w0, function() return w0.LB.endReason end), nil, "seat 0 saw no desync")
    eq(H.run(w1, function() return w1.LB.endReason end), nil, "seat 1 saw no desync")
    local h0 = H.run(w0, function() return w0.LB._myHashes end) or {}
    local h1 = H.run(w1, function() return w1.LB._myHashes end) or {}
    local n, same = 0, true
    for turn, v in pairs(h0) do
      if h1[turn] ~= nil then
        n = n + 1
        if h1[turn] ~= v then same = false end
      end
    end
    check(same and n >= 2, "every turn's digest matched across seats (" .. n .. " turns)")
    eq(H.run(w0, function() return require("src.core.game3.battle.profile").get(w0.session).family end), "rse",
      "the battle ran on the Emerald battle profile")
    eq(H.run(w0, function() return w0.LB.battleSong({ trainerId = 0 }, { trainerId = 0 }) end), EM:song("MUS_VS_TRAINER"),
      "the Emerald cable club song is MUS_VS_TRAINER")
  end
end

T.finish("emerald_link_loopback")
