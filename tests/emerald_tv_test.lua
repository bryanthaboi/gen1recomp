package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ROM_PATH = os.getenv("POKEPORT_EMERALD_ROM") or "../pokeemerald/pokeemerald.gba"
local PRET = os.getenv("POKEPORT_PRET_EMERALD") or "../pokeemerald"

local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
Profile.reset()
GameVersion.set("emerald")

local session
package.loaded["src.core.game3.runtime"] = { getSession = function() return session end }

require("tests.game3_cache").mount("emerald")
local Dataset = require("src.core.game3.dataset")
local overlay = {}
local realCache = Dataset.cache
Dataset.cache = function()
  local c = realCache()
  local realRead = c.read
  c.read = function(self, rel)
    if overlay[rel] then return overlay[rel] end
    return realRead(self, rel)
  end
  return c
end
local TV_REL = "data/generated/gba/tv/manifest.lua"

local romData
do
  local f = io.open(ROM_PATH, "rb")
  if f then
    romData = f:read("*a")
    f:close()
    if romData:sub(0xAD, 0xB0) ~= "BPEE" then romData = nil end
  end
end

local function readPret(rel)
  local h = io.open(PRET .. "/" .. rel, "rb")
  if not h then return nil end
  local s = h:read("*a")
  h:close()
  return s
end

local C = require("src.core.game3.constants").of("emerald")
local function sp(name) return C:require("species", name) end

if romData then
  print("[test] 1. tv_extract reads the ROM tables by symbol (pokeemerald/src/tv.c:192)")
  local rom = { id = "emerald", size = #romData }
  function rom.get(_, o) return romData:byte(o + 1) end
  function rom.u16(_, o) local a, b = romData:byte(o + 1, o + 2); return a + b * 256 end
  function rom.u32(_, o)
    local a, b, c, d = romData:byte(o + 1, o + 4)
    return a + b * 256 + c * 65536 + d * 16777216
  end
  function rom.readString(_, o, n) return romData:sub(o + 1, o + n) end
  local files = {}
  local fake = {
    write = function(_, rel, bytes) files[rel] = bytes; return true end,
    read = function(_, rel) return files[rel] end,
  }
  local X = require("src.import.gba.rse.tv_extract")
  check(not X.ready(fake, "data/generated/gba"), "tv not ready before run")
  eq(X.run(rom, fake, { cacheRoot = "data/generated/gba" }), true, "tv extractor ran")
  check(X.ready(fake, "data/generated/gba"), "tv ready after run")
  for _, rel in ipairs(X.REQUIRED) do check(files["data/generated/gba/" .. rel] ~= nil, rel .. " written") end
  overlay[TV_REL] = files[TV_REL]
  local m = assert(load(files[TV_REL], "@tv", "t", {}))()
  eq(#m.outbreakSpecies, 5, "sPokeOutbreakSpeciesList has 5 rows")
  local src = readPret("src/tv.c")
  if src then
    local body = src:match("sPokeOutbreakSpeciesList%[%]%s*=%s*(%b{})")
    local i = 0
    for species, moves, level, map in (body or ""):gmatch("%.species%s*=%s*(SPECIES_[%w_]+),%s*%.moves%s*=%s*(%b{}),%s*%.level%s*=%s*(%d+),%s*%.location%s*=%s*MAP_NUM%((MAP_[%w_]+)%)") do
      i = i + 1
      local row = m.outbreakSpecies[i]
      eq(row.species, sp(species), "outbreak " .. i .. " species " .. species)
      eq(row.level, tonumber(level), "outbreak " .. i .. " level")
      eq(row.location, C.map_groups.byName[map].num, "outbreak " .. i .. " location " .. map)
      local k = 0
      for mv in moves:gmatch("MOVE_[%w_]+") do
        k = k + 1
        eq(row.moves[k], C:require("moves", mv), "outbreak " .. i .. " move " .. mv)
      end
    end
    eq(i, 5, "pret list parsed")
    local nb = src:match("sNumberOneVarsAndThresholds%[%]%[2%]%s*=%s*(%b{})")
    local j = 0
    for v, th in (nb or ""):gmatch("{(VAR_[%w_]+),%s*(%d+)}") do
      j = j + 1
      eq(m.numberOne[j].var, v, "number one var " .. v)
      eq(m.numberOne[j].threshold, tonumber(th), "number one threshold " .. v)
    end
    eq(j, 7, "seven number one rows")
  end
  eq(#m.secretBaseSecretsActions, 32, "sTVSecretBaseSecretsActions has 32 rows")
  eq(m.secretBaseSecretsActions[1], 10, "first secret base action is SBSECRETS_STATE_USED_CHAIR")
  eq(m.secretBaseSecretsActions[32], 43, "last row is SBSECRETS_NUM_STATES")
  eq(m.goldSymbolFlags[1], "FLAG_SYS_TOWER_GOLD", "gold symbol flags by name")
  eq(m.silverSymbolFlags[7], "FLAG_SYS_PYRAMID_SILVER", "silver symbol flags by name")
else
  print("emerald_tv_test: ROM section skipped (no ROM at " .. ROM_PATH .. ")")
end

local Space = require("src.core.game3.scripting.space")
Space.store = { flags = {}, vars = {} }
local Flags = require("src.core.game3.scripting.flags")
local EM = Flags.forVersion("emerald")
local function setFlag(name, on) Flags.setFlag(Space.store, nil, assert(EM.IDS[name], name), on ~= false) end
local function getVar(name) return tonumber(Flags.getVar(Space.store, nil, assert(EM.VAR_IDS[name], name))) or 0 end
local function setVar(name, v) Flags.setVar(Space.store, nil, assert(EM.VAR_IDS[name], name), v) end

local Tv = require("src.core.game3.rse.tv")
local Dex = require("src.core.game3.dex")
local haveData = Tv.data() ~= nil

local queue = {}
Tv.random = function()
  local v = table.remove(queue, 1)
  return v or 0
end
local function rolls(...) queue = { ... } end

Tv.names = {
  species = function(id) return "SP" .. tostring(id) end,
  move = function(id) return "MV" .. tostring(id) end,
  item = function(id) return "IT" .. tostring(id) end,
  itemPrice = function() return 200 end,
  decoration = function(id) return "DC" .. tostring(id) end,
  mapName = function(sec) return "MAP" .. tostring(sec) end,
  word = function(id) if id == nil or id == 0xFFFF then return "" end return "W" .. tostring(id) end,
  phrase = function(words) return "PHRASE:" .. table.concat(words, ",", 1, 4) end,
  text = function(key) return "<" .. key .. ">" end,
}

local function newSession(extra)
  local s = { version = "emerald", name = "QUINCY", trainerId = 47118, secretId = 27998, gender = 0,
    party = {}, dex = Dex.new(), gameStats = {}, map = "EM_SLATEPORT_CITY", regionMapSectionId = 8 }
  for k, v in pairs(extra or {}) do s[k] = v end
  Tv.newGame(s)
  return s
end

local function runShow(s, idx, sv, limit)
  local seq, texts = {}, {}
  sv = sv or {}
  for _ = 1, limit or 60 do
    local res, done = Tv.doTVShow(s, idx, sv)
    if not res then break end
    seq[#seq + 1] = res.group and res.index or "text"
    texts[#texts + 1] = res
    if done then return seq, true, texts, sv end
  end
  return seq, false, texts, sv
end

print("[test] 2. new game clears TV state (pokeemerald/src/new_game.c:168)")
session = newSession()
eq(#session.tvShows, Tv.TV_SHOWS_COUNT - 1, "25 show slots (0..24)")
eq(session.tvShows[0].kind, 0, "slot 0 off the air")
eq(session.pokeNews[15].kind, 0, "16 PokeNews slots")
eq(session.gabbyAndTyData.quote[0], 0xFFFF, "Gabby quote is EC_EMPTY_WORD")
eq(session.outbreakPokemonSpecies, 0, "no outbreak species")
eq(session.outbreak, nil, "no outbreak for the encounter rule")
eq(Tv.groupOf(12), Tv.TVGROUP.NORMAL, "kind 12 is a normal show")
eq(Tv.groupOf(21), Tv.TVGROUP.RECORD_MIX, "kind 21 is a record-mix show")
eq(Tv.groupOf(41), Tv.TVGROUP.OUTBREAK, "kind 41 is the outbreak group")

print("[test] 3. interviews (pokeemerald/src/tv.c:2894, 1077)")
session.party = { { species = sp("SPECIES_MUDKIP"), nickname = "", name = "MUDKIP", level = 20, friendship = 200 } }
check(not Tv.interviewBefore(session, Tv.TVSHOW_FAN_CLUB_LETTER), "fan club letter interview is available")
eq(Tv._curSlot, 0, "first normal slot reserved")
eq(Tv._var8006, 0, "VAR_0x8006 is the slot")
eq(Tv._stringVar1, "SP283", "gStringVar1 = lead species name")
eq(#session.tvShows[0].words, 6, "six EC_EMPTY words initialised")
local words, first, count = Tv.easyChatWords(session, Tv.EASY_CHAT_TYPE.INTERVIEW, 0, 0)
check(words == session.tvShows[0].words and first == 1 and count == 4, "easy chat INTERVIEW edits the show's first 4 words (2x2)")
words[1], words[2], words[3], words[4] = 101, 102, 103, 104
Tv.interviewAfter(session, Tv.TVSHOW_FAN_CLUB_LETTER, {})
eq(session.tvShows[0].kind, Tv.TVSHOW_FAN_CLUB_LETTER, "fan club letter goes on air")
check(session.tvShows[0].active == true, "normal shows are active immediately")
eq(session.tvShows[0].species, sp("SPECIES_MUDKIP"), "letter stores the lead species")
eq(session.tvShows[0].trainerIdLo, 47118 % 256, "StorePlayerIdInNormalShow low byte")
check(Tv.interviewBefore(session, Tv.TVSHOW_FAN_CLUB_LETTER), "a second letter waits while the first is on air")
rolls(0, 1, 0, 0, 5)
local seq, done = runShow(session, 0)
check(done, "fan club letter finishes")
eq(table.concat(seq, ","), "0,text,1,2,text,3,5,7", "letter pages: intro, phrase, roll 0 -> 2, phrase again, roll -> 5, sign-off")
check(session.tvShows[0].active == false, "TVShowDone takes the show off the air")
check(not Tv.interviewBefore(session, Tv.TVSHOW_FAN_CLUB_LETTER), "an aired letter can be replaced")
eq(session.tvShows[0].kind, 0, "the old inactive letter was deleted")

print("[test] 4. Name Rater show (pokeemerald/src/tv.c:3280, 4570)")
session = newSession()
session.party = { { species = sp("SPECIES_MUDKIP"), nickname = "ZAPPY", name = "MUDKIP", level = 20 } }
Dex.setSeen(session.dex, sp("SPECIES_ZIGZAGOON"))
check(not Tv.tryPutNameRaterShowOnTheAir(session, 0, "ZAPPY"), "unchanged nickname puts nothing on air")
rolls(0, 1, 5)
check(Tv.tryPutNameRaterShowOnTheAir(session, 0, "MUDKIP"), "renamed mon puts the Name Rater on air")
local nr = session.tvShows[0]
eq(nr.kind, Tv.TVSHOW_NAME_RATER_SHOW, "kind NAME_RATER_SHOW")
eq(nr.pokemonName, "ZAPPY", "stores the new nickname")
eq(nr.trainerName, "QUINCY", "stores the player")
eq(nr.random, 0, "random = Random() % 3")
eq(nr.random2, 1, "random2 = Random() % 2")
eq(nr.randomSpecies, sp("SPECIES_ZIGZAGOON"), "randomSpecies walks down to a seen species")
local sv
seq, done, _, sv = runShow(session, 0)
check(done, "Name Rater show finishes")
eq(table.concat(seq, ","), "0,7,9,18", "ZAPPY sums to state 7 (tv.c:3171), random 0 -> 9 -> 18")
eq(sv[1], "ZAPPY", "last page names the mon")
eq(sv[2], "Z", "first letter substring")
eq(sv[3], "A", "second letter substring")
check(nr.active == false, "aired Name Rater show goes inactive")

if haveData then
  print("[test] 5. mass outbreak countdown (pokeemerald/src/tv.c:1646, 1707, 4898)")
  session = newSession()
  setFlag("FLAG_SYS_GAME_CLEAR", true)
  rolls(400)
  eq(Tv.tryStartRandomMassOutbreak(session), nil, "Random() > 327 fails the 1/200 roll")
  rolls(327, 0)
  eq(Tv.tryStartRandomMassOutbreak(session), 0, "Random() <= 327 starts an outbreak show in slot 0")
  local ob = session.tvShows[0]
  eq(ob.kind, Tv.TVSHOW_MASS_OUTBREAK, "kind MASS_OUTBREAK")
  eq(ob.species, sp("SPECIES_SEEDOT"), "Seedot outbreak")
  eq(ob.locationMapNum, C.map_groups.byName.MAP_ROUTE102.num, "on Route 102")
  eq(ob.level, 3, "level 3")
  eq(ob.probability, 50, "50% of encounters")
  eq(ob.daysBeforeOutbreak, 1, "airs after one day")
  eq(Tv.getRandomActiveShowIdx(session, function() return 0 end), 0xFF, "not on the air on day 0")
  Tv.updatePerDay(session, 1)
  eq(ob.daysBeforeOutbreak, 0, "countdown reaches 0")
  eq(Tv.getRandomActiveShowIdx(session, function() return 0 end), 0, "on the air the next day")
  sv = {}
  local res, fin = Tv.doTVShow(session, 0, sv)
  check(fin and res.group == "sTVMassOutbreakTextGroup" and res.index == 0, "outbreak news is one page")
  eq(sv[1], "MAP17", "gStringVar1 = Route 102 map name")
  eq(sv[2], "SP298", "gStringVar2 = Seedot")
  eq(session.outbreakPokemonSpecies, sp("SPECIES_SEEDOT"), "StartMassOutbreak copies the species")
  eq(session.outbreakDaysLeft, 2, "outbreak lasts two days")
  check(session.outbreak and session.outbreak.map == "EM_ROUTE102", "encounter hook sees EM_ROUTE102")
  eq(session.outbreak.probability, 50, "encounter hook probability")
  eq(table.concat(session.outbreak.moves, ","), "117,106,73,0", "encounter hook moves (Bide/Harden/Leech Seed)")
  eq(Tv.nextActiveIfMassOutbreak(session, 0), 0xFF, "no other show to fall back to")
  Tv.updatePerDay(session, 1)
  eq(session.outbreakDaysLeft, 1, "one day left")
  check(session.outbreak ~= nil, "still running")
  Tv.updatePerDay(session, 1)
  eq(session.outbreakPokemonSpecies, 0, "EndMassOutbreak after two days")
  eq(session.outbreak, nil, "encounter hook cleared")
  setFlag("FLAG_SYS_GAME_CLEAR", false)
else
  print("emerald_tv_test: outbreak section skipped (no tv manifest; needs ROM or POKEPORT_IDENTITY)")
end

print("[test] 6. PokeNews (pokeemerald/src/tv.c:2540, 2621, 2712)")
session = newSession()
setFlag("FLAG_SYS_GAME_CLEAR", true)
rolls(1000)
Tv.tryPutRandomPokeNewsOnAir(session)
eq(session.pokeNews[0].kind, 0, "Random() > 655 skips PokeNews")
rolls(655, 0)
Tv.tryPutRandomPokeNewsOnAir(session)
eq(session.pokeNews[0].kind, Tv.POKENEWS_SLATEPORT, "Slateport sale news")
eq(session.pokeNews[0].dayCountdown, 4, "four days out")
eq(Tv.findPokeNewsOnAir(session), 0xFF, "not announced on day 4")
Tv.updatePerDay(session, 2)
eq(Tv.findPokeNewsOnAir(session), 0, "announced once the countdown is below 3")
sv = {}
local news, shown = Tv.doPokeNews(session, 10, sv)
check(shown and news.group == "sPokeNewsTextGroup_Upcoming" and news.index == 1, "upcoming Slateport text")
eq(sv[1], "2", "gStringVar1 = days left")
eq(session.pokeNews[0].state, Tv.POKENEWS_STATE_INACTIVE, "countdown airing does not repeat")
eq(Tv.findPokeNewsOnAir(session), 0xFF, "not on the air again the same day")
Tv.updatePerDay(session, 2)
eq(session.pokeNews[0].state, Tv.POKENEWS_STATE_UPCOMING, "UpdatePokeNewsCountdown re-arms it")
news = Tv.doPokeNews(session, 21, sv)
check(news.group == "sPokeNewsTextGroup_Ending", "after 20:00 the ending text")
eq(session.pokeNews[0].state, Tv.POKENEWS_STATE_ACTIVE, "event is active")
check(Tv.isPokeNewsActive(session, Tv.POKENEWS_SLATEPORT, function() return true end), "IsPokeNewsActive")
session.map = "EM_SLATEPORT_CITY"
check(Tv.shouldApplyPokeNews(Tv.POKENEWS_SLATEPORT, session, Tv.LOCALID_SLATEPORT_ENERGY_GURU), "discount at the Energy Guru")
check(not Tv.shouldApplyPokeNews(Tv.POKENEWS_SLATEPORT, session, 3), "not for another NPC")
Tv.updatePerDay(session, 1)
eq(session.pokeNews[0].kind, 0, "elapsed news is cleared")
setFlag("FLAG_SYS_GAME_CLEAR", false)

print("[test] 7. battle results -> Pokemon Today / World of Masters (pokeemerald/src/battle_main.c:5126)")
session = newSession()
session.party = { { species = sp("SPECIES_MUDKIP"), nickname = "", name = "MUDKIP", level = 20 } }
local results = { playerMon1Species = sp("SPECIES_MUDKIP"), caughtMonSpecies = sp("SPECIES_SEEDOT"), caughtMonNick = "ACORN",
  catchAttempts = { [3] = 2 }, lastUsedItem = C:require("items", "ITEM_POKE_BALL"), lastOpponentSpecies = sp("SPECIES_SEEDOT") }
Tv.onBattleEnd(session, results, Tv.B_OUTCOME_CAUGHT, { frontier = true })
eq(session.tvShows[5].kind, 0, "frontier battles never make a show")
rolls(0)
Tv.onBattleEnd(session, results, Tv.B_OUTCOME_CAUGHT, {})
local today = session.tvShows[5]
eq(today.kind, Tv.TVSHOW_POKEMON_TODAY_CAUGHT, "Pokemon Today in the first record-mix slot")
check(today.active == false, "record-mix show waits for a partner (tv.c:1139)")
eq(today.nickname, "ACORN", "stores the nickname")
eq(today.nBallsUsed, 2, "counts the balls")
eq(today.ball, C:require("items", "ITEM_POKE_BALL"), "last ball used")
eq(session.tvShows[24].kind, Tv.TVSHOW_WORLD_OF_MASTERS, "World of Masters tracker in the last slot")
eq(session.tvShows[24].numPokeCaught, 1, "one catch counted")
eq(Tv.getRandomActiveShowIdx(session, function() return 0 end), 0xFF, "nothing on this player's TV")
Tv.updatePerDay(session, 1)
eq(session.tvShows[24].kind, 0, "World of Masters tracker resolves at the day change")

print("[test] 8. record mixing airs a partner's show (pokeemerald/src/tv.c:3449)")
local partner = newSession({ name = "WALLY", trainerId = 1234, secretId = 1 })
Dex.setSeen(partner.dex, sp("SPECIES_SEEDOT"))
Dex.setSeen(partner.dex, sp("SPECIES_ZIGZAGOON"))
local export = Tv.mixExport(session)
session, partner = partner, session
Tv.receiveShows(session, { export, {} }, 2)
local mixed = session.tvShows[5]
eq(mixed.kind, Tv.TVSHOW_POKEMON_TODAY_CAUGHT, "partner receives Pokemon Today")
check(mixed.active == true, "and it is on the air there")
eq(mixed.playerName, "QUINCY", "still credits the catcher")
eq(export.tvShows[5].kind, 0, "the sender's copy is removed")
rolls(0, 0)
seq, done, _, sv = runShow(session, 5)
check(done, "Pokemon Today airs to the end")
eq(seq[1], 0, "intro page")
eq(sv[3], "SP288", "a random seen species is compared (tv.c:3079)")
session = partner

print("[test] 9. Gabby and Ty (pokeemerald/src/tv.c:935, 979, 5427)")
session = newSession()
Tv.gabbyAndTyBeforeInterview(session, { playerMon1Species = 1, playerMon2Species = 2, lastUsedMovePlayer = 33,
  playerMonWasDamaged = true, catchAttempts = {} })
local g = session.gabbyAndTyData
eq(g.battleNum, 1, "first Gabby battle")
check(g.onAir == false, "interview takes the old show off the air")
g.quote[0] = 555
Tv.gabbyAndTyAfterInterview(session)
check(Tv.isGabbyAndTyOnAir(session), "In Search of Trainers is on the air")
eq(session.gameStats[Tv.GAME_STAT_GOT_INTERVIEWED], 1, "GAME_STAT_GOT_INTERVIEWED")
sv = {}
local steps = {}
for _ = 1, 10 do
  local res, fin = Tv.doInSearchOfTrainers(session, sv)
  steps[#steps + 1] = res.index
  if fin then break end
end
eq(table.concat(steps, ","), "0,2,3,8", "damaged, no ball/item/faint -> the move trivia page")
eq(sv[1], "W555", "last page quotes the interview word")
check(not Tv.isGabbyAndTyOnAir(session), "show ends")
words = Tv.easyChatWords(session, Tv.EASY_CHAT_TYPE.GABBY_AND_TY, 0, 0)
check(words == g.quote and words[0] == 0xFFFF, "GABBY_AND_TY easy chat writes quote[0]")

print("[test] 10. smart shopper and daily Number One (pokeemerald/src/tv.c:1503, 2467)")
session = newSession()
rolls(30000)
Tv.tryPutSmartShopperOnAir(session, { { itemId = 13, quantity = 25 }, { itemId = 4, quantity = 30 }, { itemId = 0, quantity = 0 } })
eq(session.tvShows[5].kind, 0, "rbernoulli(1, 3) blocks the show")
rolls(100)
Tv.tryPutSmartShopperOnAir(session, { { itemId = 13, quantity = 25 }, { itemId = 4, quantity = 30 }, { itemId = 0, quantity = 0 } })
eq(session.tvShows[5].kind, Tv.TVSHOW_SMART_SHOPPER, "20+ of one item makes the show")
eq(session.tvShows[5].itemIds[1], 4, "purchases sorted by quantity")
if haveData then
  setVar("VAR_DAILY_WILDS", 120)
  setVar("VAR_DAILY_SLOTS", 5)
  Tv.updatePerDay(session, 1)
  local found
  for i = 5, 23 do if session.tvShows[i].kind == Tv.TVSHOW_NUMBER_ONE then found = session.tvShows[i] end end
  check(found and found.actionIdx == 2 and found.count == 120, "100+ wild battles -> What's No. 1 action 2")
  eq(getVar("VAR_DAILY_WILDS"), 0, "daily vars reset")
end

print("[test] 11. every show airs to the end within its text table")
local SAMPLES = {
  [Tv.TVSHOW_RECENT_HAPPENINGS] = { words = { 1, 2, 3, 4, 5, 6 } },
  [Tv.TVSHOW_PKMN_FAN_CLUB_OPINIONS] = { species = 1, questionAsked = 2, words = { 7, 8 } },
  [Tv.TVSHOW_BRAVO_TRAINER_POKEMON_PROFILE] = { species = 1, pokemonNickname = "BUDDY", contestCategory = 2, contestRank = 1,
    contestResult = 0, move = 33, words = { 5, 6 } },
  [Tv.TVSHOW_BRAVO_TRAINER_BATTLE_TOWER_PROFILE] = { species = 1, numFights = 7, wonTheChallenge = true, btLevel = 50,
    interviewResponse = 1, words = { 9 } },
  [Tv.TVSHOW_CONTEST_LIVE_UPDATES] = { round1Placing = 0, round2Placing = 0, winnerAppealFlag = 128, loserAppealFlag = 4,
    category = 3, winningSpecies = 1, losingSpecies = 2, move = 33, winningTrainerName = "Q", losingTrainerName = "L" },
  [Tv.TVSHOW_3_CHEERS_FOR_POKEBLOCKS] = { sheen = 23, flavor = 2 },
  [Tv.TVSHOW_BATTLE_UPDATE] = { battleType = 2, speciesPlayer = 1, speciesOpponent = 2, move = 33 },
  [Tv.TVSHOW_FAN_CLUB_SPECIAL] = { score = 80, words = { 3 } },
  [Tv.TVSHOW_LILYCOVE_CONTEST_LADY] = { contestCategory = 1, pokeblockState = 0 },
  [Tv.TVSHOW_POKEMON_TODAY_FAILED] = { species = 1, species2 = 2, nBallsUsed = 3, outcome = 1 },
  [Tv.TVSHOW_SMART_SHOPPER] = { itemIds = { 13, 4, 1 }, itemAmounts = { 30, 20, 1 }, priceReduced = 1 },
  [Tv.TVSHOW_FISHING_ADVICE] = { nBites = 5, nFails = 1, species = 129 },
  [Tv.TVSHOW_WORLD_OF_MASTERS] = { steps = 400, numPokeCaught = 21, species = 1, caughtPoke = 2, location = 3 },
  [Tv.TVSHOW_TODAYS_RIVAL_TRAINER] = { location = 3, badgeCount = 8, dexCount = 100, battlePoints = 0 },
  [Tv.TVSHOW_TREND_WATCHER] = { gender = 1, words = { 1, 2 } },
  [Tv.TVSHOW_TREASURE_INVESTIGATORS] = { item = 13, location = 4 },
  [Tv.TVSHOW_FIND_THAT_GAMER] = { won = false, whichGame = 1, nCoins = 120 },
  [Tv.TVSHOW_BREAKING_NEWS] = { outcome = 1, lastUsedMove = 33, lastOpponentSpecies = 2, poke1Species = 1, location = 3 },
  [Tv.TVSHOW_SECRET_BASE_VISIT] = { numDecorations = 4, decorations = { 1, 2, 3, 4 }, avgLevel = 55, species = 1, move = 33 },
  [Tv.TVSHOW_LOTTO_WINNER] = { whichPrize = 1, item = 13 },
  [Tv.TVSHOW_BATTLE_SEMINAR] = { species = 1, foeSpecies = 2, move = 33, otherMoves = { 34, 35 }, nOtherMoves = 2, betterMove = 36 },
  [Tv.TVSHOW_TRAINER_FAN_CLUB] = { words = { 1, 2 }, trainerIdLo = 7, trainerIdHi = 0 },
  [Tv.TVSHOW_CUTIES] = { nRibbons = 12, selectedRibbon = 24 },
  [Tv.TVSHOW_FRONTIER] = { winStreak = 50, facilityAndMode = 2, species1 = 1, species2 = 2, species3 = 3, species4 = 4 },
  [Tv.TVSHOW_NUMBER_ONE] = { actionIdx = 3, count = 25 },
  [Tv.TVSHOW_SECRET_BASE_SECRETS] = { flags = 0x401 + 0x800, stepsInBase = 60, item = 13, baseOwnersName = "MAY" },
  [Tv.TVSHOW_SAFARI_FAN_CLUB] = { monsCaught = 5, pokeblocksUsed = 2 },
  [Tv.TVSHOW_POKEMON_TODAY_CAUGHT] = { species = 1, nickname = "NICK", ball = 4, nBallsUsed = 5 },
}
local emitted = {}
if not haveData then SAMPLES[Tv.TVSHOW_SECRET_BASE_SECRETS] = nil end
for kind, fields in pairs(SAMPLES) do
  session = newSession()
  local show = session.tvShows[0]
  for k, v in pairs(fields) do show[k] = v end
  show.kind, show.active, show.playerName = kind, true, show.playerName or "QUINCY"
  Tv.resetShowState()
  rolls(1, 2, 0, 1, 2, 0, 1, 2)
  local s2, fin, texts = runShow(session, 0)
  check(fin, "show kind " .. kind .. " reaches TVShowDone (" .. table.concat(s2, ",") .. ")")
  eq(Tv.showState(), 0, "show kind " .. kind .. " resets sTVShowState")
  for _, r in ipairs(texts) do
    if r.group then emitted[#emitted + 1] = { kind = kind, group = r.group, index = r.index } end
  end
end
check(#emitted > 60, "sample shows emitted " .. #emitted .. " text pages")
for state, want in pairs({ [0] = "0,2", [1] = "0,1", [2] = "0,3" }) do
  session = newSession()
  local lady = session.tvShows[0]
  lady.kind, lady.active, lady.pokeblockState, lady.contestCategory = Tv.TVSHOW_LILYCOVE_CONTEST_LADY, true, state, 0
  eq(table.concat(runShow(session, 0), ","), want, "contest lady pokeblock state " .. state
    .. " (pokeemerald/include/constants/lilycove_lady.h:26)")
end
eq(Tv.ribbonOf(71), Tv.RIBBON.effort, "MON_DATA_EFFORT_RIBBON (71) -> EFFORT_RIBBON")
eq(Tv.ribbonOf(67), Tv.RIBBON.champion, "MON_DATA_CHAMPION_RIBBON (67) -> CHAMPION_RIBBON")
eq(Tv.ribbonOf(52), Tv.RIBBON.cute, "MON_DATA_CUTE_RIBBON (52) -> CUTE_RIBBON_NORMAL")
eq(Tv.ribbonCount({ ribbons = 7 + 2 ^ 15 + 2 ^ 19 }), 9, "packed ribbon word: cool 7 + champion + effort")

print("[test] 12. time hook and FireRed gating")
local NativesTv = require("src.core.game3.scripting.natives_tv")
local TimeEvents = require("src.core.game3.time_events")
check(TimeEvents.handlers().UpdateTVShowsPerDay ~= nil, "UpdateTVShowsPerDay is registered (pokeemerald/src/clock.c:46)")
local Capabilities = require("src.core.game3.capabilities")
check(not Capabilities.nativeAllowed({ version = "firered" }, "natives_tv"), "FireRed never binds natives_tv")
check(NativesTv.BY_NAME.DoTVShow and NativesTv.BY_NAME.InterviewBefore and NativesTv.BY_NAME.InterviewAfter
  and NativesTv.BY_NAME.TryPutNameRaterShowOnTheAir and NativesTv.BY_NAME.GabbyAndTyBeforeInterview, "tv.c specials bound")
local Rse = require("src.core.game3.rse.init")
check(Rse.system("tv") == Tv.api, "rse system tv is registered")
local okTypes, Types = pcall(require, "src.core.game3.rse.easy_chat_types")
if okTypes then
  local def = Types.get(Tv.EASY_CHAT_TYPE.FAN_CLUB)
  check(def ~= nil and Types.get(Tv.EASY_CHAT_TYPE.GABBY_AND_TY) ~= nil and Types.get(Tv.EASY_CHAT_TYPE.INTERVIEW) ~= nil,
    "TV easy chat types registered")
  session = newSession()
  session.party = { { species = sp("SPECIES_MUDKIP"), nickname = "", name = "MUDKIP", level = 20, friendship = 200 } }
  Tv.interviewBefore(session, Tv.TVSHOW_PKMN_FAN_CLUB_OPINIONS)
  local ctx = { specialVars = { [0x8005] = Tv._curSlot, [0x8006] = 1 } }
  local w = def.words(ctx, session)
  eq(#w, 1, "FAN_CLUB edits one word")
  def.commit(ctx, session, { 777 })
  eq(session.tvShows[Tv._curSlot].words[2], 777, "FAN_CLUB answer 2 lands in fanclubOpinions.words[1]")
end
session = newSession()
session.party = { { species = sp("SPECIES_MUDKIP"), nickname = "", name = "MUDKIP", level = 20, ribbons = { effort = true, cool = 4,
  beauty = 2 } } }
local _, handled = Rse.call("tv", "tryPutSpotTheCutiesOnAir", "test", nil, session.party[1], "effort")
check(handled, "Rse.call reaches Tv.api")
eq(session.tvShows[5].kind, Tv.TVSHOW_CUTIES, "Spot the Cuties recorded")
eq(session.tvShows[5].nRibbons, 7, "ribbon count sums contest ranks (tv.c:2277)")
eq(session.tvShows[5].selectedRibbon, 24, "EFFORT_RIBBON")
local SaveSections = require("src.core.game3.save_sections")
local out = {}
session.outbreakPokemonSpecies, session.outbreakLocationMapNum, session.outbreakLocationMapGroup = 298, 17, 0
SaveSections.export(session, out, "emerald")
eq(out.outbreakLocationMapNum, 17, "save section keeps the cart outbreak fields")
local restored = { version = "emerald" }
SaveSections.restore(out, restored, "emerald")
check(restored.outbreak and restored.outbreak.map == "EM_ROUTE102", "restore rebuilds session.outbreak")

local identityText = (function()
  local RomText = require("src.core.game3.rom_text")
  local ok, has = pcall(RomText.has, "sTVNameRaterTextGroup[0]")
  return ok and has
end)()
if identityText then
  print("[test] 13. every emitted page exists in the Emerald text cache and renders")
  Tv.names = {}
  local RomText = require("src.core.game3.rom_text")
  local TextIR = require("src.core.game3.scripting.text_ir")
  local missing = 0
  for _, e in ipairs(emitted) do
    local key = RomText.key(e.group, e.index)
    if not RomText.has(key) then
      missing = missing + 1
      print("  missing " .. key .. " for kind " .. e.kind)
    end
  end
  eq(missing, 0, "all emitted TV pages are ROM text")
  local count = RomText.count("sTVNameRaterTextGroup")
  eq(count, 19, "sTVNameRaterTextGroup has 19 pages")
  session = newSession()
  session.party = { { species = sp("SPECIES_MUDKIP"), nickname = "ZAPPY", name = "MUDKIP", level = 20 } }
  rolls(0, 1, 5)
  Tv.tryPutNameRaterShowOnTheAir(session, 0, "MUDKIP")
  sv = { "", "", "" }
  local res = Tv.doTVShow(session, 0, sv)
  local page = TextIR.toPlain(RomText.ir(RomText.key(res.group, res.index)), { stringVars = sv, playerName = "QUINCY" })
  check(page:find("ZAPPY", 1, true) ~= nil, "first Name Rater page names ZAPPY: " .. page:gsub("\n", " "))
  check(page:find("QUINCY", 1, true) ~= nil, "and the trainer")
else
  print("emerald_tv_test: text section skipped (no Emerald script cache; set POKEPORT_IDENTITY)")
end

T.finish()
