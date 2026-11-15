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
  print("emerald_record_mix_test: skipped (no Emerald cache; set POKEPORT_IDENTITY)")
  os.exit(0)
end
require("src.import.gba.versions").select("emerald")
local Pokemon = require("src.core.game3.pokemon")
Pokemon.install(nil)

local Json = require("src.link.Json")
local Wire = require("src.link.Wire")
local SaveData = require("src.core.SaveData")
local Schema = require("src.core.game3.save_schema_firered")
local Flags = require("src.core.game3.scripting.flags")
local Space = require("src.core.game3.scripting.space")
local Rse = require("src.core.game3.rse.init")
local RecordMix = require("src.core.game3.link.record_mix")
local MixUtil = require("src.core.game3.rse.record_mix_util")
local OldMan = require("src.core.game3.rse.old_man")
local Lady = require("src.core.game3.rse.lilycove_lady")
local SB = require("src.core.game3.rse.secret_base")
local Tv = require("src.core.game3.rse.tv")
local Dex = require("src.core.game3.dex")
local Daycare = require("src.core.game3.daycare")
local DaycareMail = require("src.core.game3.rse.daycare_mail_mix")
local Gift = require("src.core.game3.rse.record_mixing_gift")
local FUtil = require("src.core.game3.rse.frontier.util")
local Apprentice = require("src.core.game3.rse.frontier.apprentice")
local Bag = require("src.core.game3.bag")
local EM = require("src.core.game3.constants").of("emerald")

local ORANGE_MAIL = EM:require("items", "ITEM_ORANGE_MAIL")
local EON_TICKET = EM:require("items", "ITEM_EON_TICKET")
local SEEDOT = EM:require("species", "SPECIES_SEEDOT")
local MUDKIP = EM:require("species", "SPECIES_MUDKIP")

local stores = {}
local function use(s)
  Space.store = stores[s]
end

local function makePlayer(idx, name, tid, gender)
  local s = Schema.newGame({ version = "emerald", name = name, rngSeed = tid })
  s.trainerId, s.secretId, s.gender = tid, 0, gender
  s.modData = s.modData or {}
  s.modData.cartImport = s.modData.cartImport or {}
  s.modData.cartImport.recordMixTvBytes256 = {}
  for i = 1, 256 do s.modData.cartImport.recordMixTvBytes256[i] = 0 end
  s.modData.cartImport.recordMixTvBytes256[1] = Tv.TVSHOW_POKEMON_TODAY_CAUGHT
  s.modData.cartImport.recordMixTvBytes256[2] = 1
  s.party = { { species = MUDKIP, level = 20, nickname = "", heldItem = 0 } }
  s.dex = s.dex or Dex.new()
  Dex.setSeen(s.dex, SEEDOT)
  Dex.setSeen(s.dex, MUDKIP)
  stores[s] = Flags.newStore()
  use(s)
  Rse.setFlag("FLAG_RECEIVED_SECRET_POWER", true, s)

  local b = SB.base(s, 0)
  b.secretBaseId, b.trainerName, b.gender, b.language = 10 * idx + 1, name, gender, 2
  b.trainerId = MixUtil.trainerIdBytes(s)

  local m = OldMan.set(s)
  if m.id == OldMan.STORYTELLER then
    m.gameStatIDs[1], m.trainerNames[1], m.statValues[1] = 1, name, 100 * idx
  elseif m.id == OldMan.GIDDY then
    m.randomWords[1] = 100 + idx
  elseif m.id == OldMan.BARD then
    m.playerName = name
  end

  local l = Lady.init(s)
  local which = l.quiz or l.favor or l.contest
  which.playerName = name

  local dc = Daycare.stateOf(s)
  Daycare.setMon(dc, 1, { species = SEEDOT, level = 5, heldItem = 0 })
  dc.mail = {}

  local f = FUtil.frontier(s)
  f.towerPlayer = { trainerId = MixUtil.trainerIdBytes(s), name = name, winStreak = 20 * idx, lvlMode = 0,
    facilityClass = 1, party = { { species = MUDKIP, level = 50 } }, language = 2 }
  FUtil.set2(f.towerRecordWinStreaks, 0, 0, 20 * idx)
  FUtil.set2(f.towerRecordWinStreaks, 3, 0, 5 * idx)

  local a = Apprentice.saved(s)[1]
  a.playerName, a.playerId, a.number, a.id, a.lvlMode = name, MixUtil.trainerIdBytes(s), idx, idx, 1
  return s
end

local function giveShow(s)
  local saved = Tv.random
  Tv.random = function() return 0 end
  Tv.onBattleEnd(s, { playerMon1Species = MUDKIP, caughtMonSpecies = SEEDOT, caughtMonNick = "ACORN",
    catchAttempts = { [3] = 2 }, lastUsedItem = EM:require("items", "ITEM_POKE_BALL"), lastOpponentSpecies = SEEDOT },
    Tv.B_OUTCOME_CAUGHT, {})
  Tv.random = saved
end

local function wire(packet, spot)
  local msg = Wire.sanitize(Json.decode(Json.encode({ type = RecordMix.MSG.PACKET, spot = spot,
    packet = RecordMix.toWire(packet) })))
  return msg and RecordMix.fromWire(msg.packet) or nil
end

local function mix(players)
  local packets, wired = {}, {}
  for i, s in ipairs(players) do
    use(s)
    packets[i] = RecordMix.packet(s, i - 1)
    wired[i] = wire(packets[i], i - 1)
  end
  local applied = {}
  for i, s in ipairs(players) do
    local list = {}
    for j = 1, #players do list[j] = j == i and packets[i] or wired[j] end
    use(s)
    applied[i] = RecordMix.receive(s, list, i)
  end
  return applied, packets, wired
end

local function hasBase(s, id)
  for i = 2, SB.COUNT do
    if SB.base(s, i - 1).secretBaseId == id then return SB.base(s, i - 1) end
  end
  return nil
end

local function towerRecordNamed(s, name)
  for _, r in ipairs(FUtil.frontier(s).towerRecords) do
    if r.name == name then return r end
  end
  return nil
end

local function apprenticeNamed(s, name)
  for i, a in ipairs(s.apprentices or {}) do
    if i > 1 and a.playerName == name then return a end
  end
  return nil
end

local function tvHasCaught(s)
  for i = 0, Tv.TV_SHOWS_COUNT - 1 do
    local show = s.tvShows[i]
    if show and show.kind == Tv.TVSHOW_POKEMON_TODAY_CAUGHT and show.active == true then return true end
  end
  return false
end

local function reload(s)
  local save = SaveData.decode(SaveData.encode(Schema.toSaveTable(s)))
  return Schema.fromSaveTable(save)
end

local function giftVar(s)
  use(s)
  return Rse.var("VAR_TEMP_RECORD_MIX_GIFT_ITEM", s)
end

print("[test] 1. ShufflePlayerIndices (pokeemerald/src/record_mixing.c:604)")
do
  local two = MixUtil.shuffle({ { trainerId = 5 }, {} })
  eq(two[1] .. two[2], "21", "2 players swap")
  local three0 = MixUtil.shuffle({ { linkTrainerId = 4 }, {}, {} })
  eq(three0[1] .. three0[2] .. three0[3], "231", "3 players, even leader id: 0<-1, 1<-2, 2<-0")
  local three1 = MixUtil.shuffle({ { linkTrainerId = 7 }, {}, {} })
  eq(three1[1] .. three1[2] .. three1[3], "312", "3 players, odd leader id: 0<-2, 1<-0, 2<-1")
  local four = MixUtil.shuffle({ { linkTrainerId = 9 * 3 + 4 }, {}, {}, {} })
  eq(four[1] .. four[2] .. four[3] .. four[4], "3412", "4 players use sPlayerIdxOrders_4Player[id % 9]")
end

print("[test] 2. two players mix every record")
do
  local A = makePlayer(1, "MAY", 1116, 1)
  local B = makePlayer(2, "BRENDAN", 2228, 0)
  giveShow(B)
  local mail = { message = { itemId = ORANGE_MAIL, words = { 1, 2, 3, 4, 5, 6, 7, 8, 9 }, playerName = "MAY",
    trainerId = 1116, species = SEEDOT }, otName = "MAY", monName = "SEEDOT" }
  Daycare.stateOf(A).mail[1] = mail
  Gift.set(1, 1, EON_TICKET, A)
  eq(OldMan.current(A), OldMan.STORYTELLER, "MAY has the storyteller")
  eq(OldMan.current(B), OldMan.GIDDY, "BRENDAN has Giddy")
  eq(Lady.id(A), Lady.QUIZ, "MAY has the quiz lady")
  eq(Lady.id(B), Lady.FAVOR, "BRENDAN has the favor lady")

  local applied, packets, wired = mix({ A, B })
  eq(packets[1].giftItem, EON_TICKET, "multiplayer id 0 sends its record mixing gift")
  eq(packets[2].giftItem, 0, "other players send no gift")
  check(wired[2] and wired[2].daycareMail and wired[2].apprentices and wired[2].hallRecords
    and wired[2].battleTowerRecord and wired[2].lilycoveLady and wired[2].oldMan, "every record crosses the wire")
  for _, key in ipairs({ "secretBases", "tvShows", "pokeNews", "oldMan", "dewfordTrends", "daycareMail",
    "battleTower", "giftItem", "lilycoveLady", "apprentices", "hallRecords" }) do
    check(applied[1][key] and applied[2][key], "both sides ran the " .. key .. " receiver")
  end

  eq(OldMan.current(A), OldMan.GIDDY, "MAY now has BRENDAN's Giddy")
  eq(A.oldMan.randomWords[1], 102, "with BRENDAN's tale words")
  eq(OldMan.current(B), OldMan.STORYTELLER, "BRENDAN now has MAY's storyteller")
  eq(B.oldMan.trainerNames[1], "MAY", "with MAY's story")
  eq(B.oldMan.alreadyRecorded, false, "ResetMauvilleOldManFlag ran")

  eq(Lady.id(A), Lady.FAVOR, "MAY now has the favor lady")
  eq(A.lilycoveLady.favor.playerName, "BRENDAN", "carrying BRENDAN's data")
  eq(A.lilycoveLady.favor.state, Lady.STATE_READY, "ResetLilycoveLadyForRecordMix ran")
  eq(Lady.id(B), Lady.QUIZ, "BRENDAN now has the quiz lady")
  eq(B.lilycoveLady.quiz.playerName, "MAY", "carrying MAY's quiz")

  local bb = hasBase(A, 21)
  check(bb ~= nil, "MAY registered BRENDAN's secret base")
  eq(bb and bb.trainerName, "BRENDAN", "owned by BRENDAN")
  eq(bb and bb.registryStatus, SB.UNREGISTERED, "NEW is cleared back to UNREGISTERED")
  check(hasBase(B, 11) ~= nil, "BRENDAN registered MAY's secret base")
  eq(SB.base(A, 0).numSecretBasesReceived, 1, "numSecretBasesReceived counts the mix")

  check(tvHasCaught(A), "BRENDAN's Pokemon Today show airs on MAY's TV")

  eq(Daycare.stateOf(A).mail[1], nil, "MAY's daycare mail swapped away")
  local bm = Daycare.stateOf(B).mail[1]
  eq(bm and bm.message.itemId, ORANGE_MAIL, "BRENDAN's daycare SEEDOT now carries MAY's mail")
  eq(bm and bm.otName, "MAY", "with MAY as the writer")

  local tr = towerRecordNamed(A, "BRENDAN")
  eq(tr and tr.winStreak, 40, "BRENDAN's tower record joined MAY's towerRecords")
  eq(towerRecordNamed(B, "MAY") and towerRecordNamed(B, "MAY").winStreak, 20, "and MAY's joined BRENDAN's")

  check(Bag.has(B.bag, EON_TICKET, 1), "BRENDAN received MAY's EON TICKET")
  eq(giftVar(B), EON_TICKET, "VAR_TEMP_RECORD_MIX_GIFT_ITEM holds it")
  use(B)
  check(Rse.flag("FLAG_ENABLE_SHIP_SOUTHERN_ISLAND", B), "FLAG_ENABLE_SHIP_SOUTHERN_ISLAND is set")
  check(not Bag.has(A.bag, EON_TICKET, 1), "the sender keeps no copy")
  eq(Gift.state(A).quantity, 0, "the one-use gift is spent")

  local ap = apprenticeNamed(A, "BRENDAN")
  check(ap ~= nil, "MAY saved BRENDAN's apprentice")
  eq(A.playerApprentice.saveId, 1, "playerApprentice.saveId advanced")
  check(apprenticeNamed(B, "MAY") ~= nil, "BRENDAN saved MAY's apprentice")

  local h = A.hallRecords1P[1][1][1]
  eq(h.name, "BRENDAN", "MAY's Ranking Hall shows BRENDAN")
  eq(h.winStreak, 40, "with his tower singles streak")
  eq(B.hallRecords1P[1][1][1].name, "MAY", "BRENDAN's Ranking Hall shows MAY")
  eq(A.hallRecords2P[1][1].name1 .. "/" .. A.hallRecords2P[1][1].winStreak, "BRENDAN/10", "link multi hall row filled")

  print("[test] 3. the mixed records survive save and reload")
  local A2, B2 = reload(A), reload(B)
  eq(A2.oldMan and A2.oldMan.id, OldMan.GIDDY, "old man")
  eq(A2.lilycoveLady and A2.lilycoveLady.favor and A2.lilycoveLady.favor.playerName, "BRENDAN", "Lilycove lady")
  check(hasBase(A2, 21) ~= nil, "secret base registry")
  check(tvHasCaught(A2), "TV show")
  local bm2 = Daycare.stateOf(B2).mail[1]
  eq(bm2 and bm2.message.itemId, ORANGE_MAIL, "daycare mail")
  eq(towerRecordNamed(A2, "BRENDAN") and towerRecordNamed(A2, "BRENDAN").winStreak, 40, "tower record")
  check(Bag.has(B2.bag, EON_TICKET, 1), "gift item")
  check(apprenticeNamed(A2, "BRENDAN") ~= nil, "apprentice")
  eq(A2.playerApprentice and A2.playerApprentice.saveId, 1, "apprentice save id")
  eq(A2.hallRecords1P[1][1][1].name, "BRENDAN", "ranking hall")
  local g2 = reload(A)
  eq(g2.recordMixingGift and g2.recordMixingGift.itemId, 0, "record mixing gift block")
end

print("[test] 4. three players follow pret's partner table")
do
  local A = makePlayer(1, "MAY", 1116, 1)
  local B = makePlayer(2, "BRENDAN", 2228, 0)
  local C = makePlayer(3, "CHRIS", 3340, 0)
  giveShow(C)
  local mail = { message = { itemId = ORANGE_MAIL, words = { 9, 9, 9, 9, 9, 9, 9, 9, 9 }, playerName = "MAY",
    trainerId = 1116, species = SEEDOT }, otName = "MAY", monName = "SEEDOT" }
  Daycare.stateOf(A).mail[1] = mail
  Gift.set(1, 2, EON_TICKET, A)
  eq(OldMan.current(C), OldMan.BARD, "CHRIS has the bard")
  eq(Lady.id(C), Lady.CONTEST, "CHRIS has the contest lady")
  local order = MixUtil.shuffle({ { linkTrainerId = MixUtil.sessionLinkTrainerId(A) }, {}, {} })
  eq(order[1] .. order[2] .. order[3], "231", "MAY's even id picks {1, 2, 0}")
  local _, packets = mix({ A, B, C })
  local randSum = DaycareMail.randSum(packets[1])
  eq(randSum, 0, "sum uses the current blank TV slots after normal-show deactivation")

  eq(OldMan.current(A), OldMan.GIDDY, "MAY <- BRENDAN's Giddy")
  eq(OldMan.current(B), OldMan.BARD, "BRENDAN <- CHRIS's bard")
  eq(B.oldMan.playerName, "CHRIS", "the bard keeps CHRIS's song credit")
  eq(OldMan.current(C), OldMan.STORYTELLER, "CHRIS <- MAY's storyteller")
  eq(Lady.id(A), Lady.FAVOR, "MAY <- favor lady")
  eq(Lady.id(B), Lady.CONTEST, "BRENDAN <- contest lady")
  eq(B.lilycoveLady.contest.playerName, "CHRIS", "with CHRIS's contest data")
  eq(Lady.id(C), Lady.QUIZ, "CHRIS <- quiz lady")
  eq(C.lilycoveLady.quiz.playerName, "MAY", "with MAY's quiz")

  check(hasBase(A, 21) and hasBase(A, 31), "MAY registered both partners' bases")
  check(hasBase(B, 11) and hasBase(B, 31), "BRENDAN registered both partners' bases")
  check(hasBase(C, 11) and hasBase(C, 21), "CHRIS registered both partners' bases")

  check((tvHasCaught(A) and 1 or 0) + (tvHasCaught(B) and 1 or 0) == 1, "CHRIS's show airs on exactly one partner's TV (tv.c:3449)")

  local swap = ({ { 0, 1 }, { 1, 2 }, { 2, 0 } })[randSum % 3 + 1]
  local holder = (swap[1] == 0 and swap[2]) or (swap[2] == 0 and swap[1]) or 0
  local holders = {}
  for i, s in ipairs({ A, B, C }) do
    local m = Daycare.stateOf(s).mail[1]
    if m and m.message.itemId == ORANGE_MAIL then holders[#holders + 1] = i - 1 end
  end
  eq(#holders, 1, "MAY's mail exists exactly once after the swap")
  eq(holders[1], holder, "sDaycareMailSwapIds_3Player[" .. (randSum % 3) .. "] decides who holds it")

  eq(towerRecordNamed(A, "BRENDAN") and towerRecordNamed(A, "BRENDAN").winStreak, 40, "MAY <- BRENDAN's tower record")
  eq(towerRecordNamed(B, "CHRIS") and towerRecordNamed(B, "CHRIS").winStreak, 60, "BRENDAN <- CHRIS's tower record")
  eq(towerRecordNamed(C, "MAY") and towerRecordNamed(C, "MAY").winStreak, 20, "CHRIS <- MAY's tower record")
  check(towerRecordNamed(A, "CHRIS") == nil, "MAY does not take CHRIS's tower record")

  check(Bag.has(B.bag, EON_TICKET, 1) and Bag.has(C.bag, EON_TICKET, 1), "both partners get the leader's gift")

  check(apprenticeNamed(A, "BRENDAN") ~= nil, "MAY <- BRENDAN's apprentice")
  check(apprenticeNamed(B, "CHRIS") ~= nil, "BRENDAN <- CHRIS's apprentice")
  check(apprenticeNamed(C, "MAY") ~= nil, "CHRIS <- MAY's apprentice")

  local hall = A.hallRecords1P[1][1]
  eq(hall[1].name .. "/" .. hall[1].winStreak, "CHRIS/60", "MAY's hall ranks CHRIS first")
  eq(hall[2].name .. "/" .. hall[2].winStreak, "BRENDAN/40", "then BRENDAN")
  local hallC = C.hallRecords1P[1][1]
  eq(hallC[1].name .. "/" .. hallC[2].name, "BRENDAN/MAY", "CHRIS ranks BRENDAN over MAY")

  local C2 = reload(C)
  eq(C2.oldMan.id, OldMan.STORYTELLER, "CHRIS's old man survives reload")
  eq(C2.hallRecords1P[1][1][1].name, "BRENDAN", "and his hall records")
  check(hasBase(C2, 11) and hasBase(C2, 21), "and both bases")
end

print("[test] raw daycare-mail selector sum is limited to the cart's first 256 TV bytes")
do
  local bytes = {}
  for i = 1, 257 do bytes[i] = i == 257 and 99 or (i % 256) end
  eq(DaycareMail.randSum(bytes), 128, "sum includes only the first 256 bytes")
  eq(DaycareMail.randSum({ tvShowByteSum = 258 }), 2, "packet sum is reduced to a byte")
end

T.finish("emerald_record_mix")
