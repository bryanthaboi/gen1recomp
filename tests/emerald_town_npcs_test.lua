package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local home = os.getenv("HOME") or ""
local roots = {}
local identity = os.getenv("POKEPORT_IDENTITY")
if identity and identity ~= "" then
  roots[#roots + 1] = home .. "/Library/Application Support/LOVE/" .. identity .. "/emerald/"
  roots[#roots + 1] = home .. "/.local/share/love/" .. identity .. "/emerald/"
end
local ROOT
for _, r in ipairs(roots) do
  local f = io.open(r .. "data/generated/gba/rse/misc/manifest.lua", "rb")
  if f then
    f:close()
    ROOT = r
    break
  end
end
if not ROOT then
  local dir = require("tests.game3_cache").gameDir("emerald", "rse/misc/manifest.lua")
  ROOT = dir and dir .. "/"
end
if not ROOT then
  print("SKIP emerald_town_npcs_test: no Emerald cache with rse/misc (set POKEPORT_IDENTITY to a current import)")
  os.exit(0)
end

local fs = {}
function fs:read(rel)
  local f = io.open(ROOT .. rel, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end
function fs:exists(rel) return self:read(rel) ~= nil end
package.loaded["src.core.game3.dataset"] = {
  cache = function() return fs end,
  mountExtractRoots = function() end,
}

local GameVersion = require("src.core.GameVersion")
local before = GameVersion.get()
GameVersion.set("emerald")

local store = { flags = {}, vars = {} }
local session = { version = "emerald", gender = 0, name = "BRENDAN", trainerId = 12345, party = {}, flags = {},
  vars = {}, store = store, dex = { seen = {}, caught = {}, owned = {} }, gameStats = {} }
package.loaded["src.core.game3.runtime"] = { getSession = function() return session end }
local bundle
package.loaded["src.core.game3.scripting.space"] = { store = store, ensureBundle = function()
  bundle = bundle or require("src.import.gba.extract_scripts").loadBundle(fs, "data/generated/gba", { allowIncomplete = true })
  return bundle
end }

local Rng = require("src.core.game3.rng")
local C = require("src.core.game3.constants").of("emerald")
local Rse = require("src.core.game3.rse.init")
local Town = require("src.core.game3.rse.town_common")

local specials = {}
local ctx = {
  stringVars = {},
  getVar = function(_, id) return specials[id] or 0 end,
  setVar = function(_, id, v) specials[id] = v end,
}

local function word(name)
  local text = name:gsub("^EC_WORD_", "")
  local groups = require("src.core.game3.easy_chat_text").groups()
  for gid = 1, 20 do
    local g = groups[gid]
    for _, w in ipairs(g and g.words or {}) do
      if w.text == text and gid ~= 18 and gid ~= 19 then return w.id end
    end
  end
  error("no easy chat word " .. name)
end

print("[test] Dewford trend (pokeemerald/src/dewford_trend.c)")
local Dewford = require("src.core.game3.rse.dewford_trend")
Rng.SeedRng(0x1234)
local trends = Dewford.init(session)
eq(#trends, 5, "five saved trends")
for i = 2, 5 do
  check(not Dewford.compare(trends[i], trends[i - 1], Dewford.SORT_MODE_NORMAL) or trends[i].trendiness == trends[i - 1].trendiness,
    "trends sorted by trendiness " .. i)
end
for _, t in ipairs(trends) do
  check(t.maxTrendiness >= 30 and t.maxTrendiness <= 127, "maxTrendiness in 30..127")
  check(t.trendiness >= 30 and t.trendiness <= t.maxTrendiness, "trendiness in 30..max")
  eq(math.floor(t.words[1] / 512), Town.EC_GROUP.CONDITIONS, "first word from CONDITIONS")
  local g2 = math.floor(t.words[2] / 512)
  check(g2 == Town.EC_GROUP.LIFESTYLE or g2 == Town.EC_GROUP.HOBBIES, "second word from LIFESTYLE/HOBBIES")
end
local t = { { trendiness = 40, maxTrendiness = 50, gainingTrendiness = true, rand = 1, words = { 1, 2 } },
  { trendiness = 10, maxTrendiness = 60, gainingTrendiness = false, rand = 2, words = { 3, 4 } },
  { trendiness = 3, maxTrendiness = 40, gainingTrendiness = false, rand = 3, words = { 5, 6 } },
  { trendiness = 45, maxTrendiness = 45, gainingTrendiness = true, rand = 4, words = { 7, 8 } },
  { trendiness = 30, maxTrendiness = 31, gainingTrendiness = true, rand = 5, words = { 9, 10 } } }
session.dewfordTrends = t
Dewford.updatePerDay(2, session)
local byWords = {}
for _, x in ipairs(session.dewfordTrends) do byWords[x.words[1]] = x end
eq(byWords[1].trendiness, 50, "gaining 40 + 10 hits max 50")
eq(byWords[1].gainingTrendiness, false, "reaching max turns boring")
eq(byWords[3].trendiness, 0, "boring 10 - 10 reaches 0")
eq(byWords[3].gainingTrendiness, true, "reaching 0 starts gaining")
eq(byWords[5].trendiness, 7, "boring 3 drops to 0 then gains the remaining 7")
eq(byWords[7].trendiness, 35, "45 + 10 over max 45: 55 % 45 = 10, odd quotient -> 45 - 10")
eq(byWords[7].gainingTrendiness, false, "odd quotient turns boring")
eq(byWords[9].trendiness, 22, "30 + 10 over 31: 40 % 31 = 9, odd quotient -> 31 - 9")
Rse.setFlag("FLAG_SYS_CHANGED_DEWFORD_TREND", false)
Rse.setFlag("FLAG_SYS_MIX_RECORD", false)
Dewford.init(session)
local phrase = { word("EC_WORD_COOL"), word("EC_WORD_CAMERA") }
check(Dewford.trySetTrendyPhrase(phrase, session), "first submission always becomes the trend")
eq(session.dewfordTrends[1].words[1], phrase[1], "trend word 1 replaced in place")
check(Rse.flag("FLAG_SYS_CHANGED_DEWFORD_TREND"), "FLAG_SYS_CHANGED_DEWFORD_TREND set")
check(not Dewford.trySetTrendyPhrase(phrase, session), "an already-saved phrase is rejected")
local second = { word("EC_WORD_CAMERA"), word("EC_WORD_COOL") }
Dewford.trySetTrendyPhrase(second, session)
check(Dewford.isPhraseSaved(second, session), "a later submission is always saved in the list")
eq(#session.dewfordTrends, 5, "still five saved trends")
local NativesDewford = require("src.core.game3.scripting.natives_dewford")
specials[0x8004] = 0
NativesDewford.BY_NAME.BufferTrendyPhraseString(ctx)
eq(ctx.stringVars[1], Town.word(phrase[1]) .. " " .. Town.word(phrase[2]), "BufferTrendyPhraseString")
local _, idx = NativesDewford.BY_NAME.GetDewfordHallPaintingNameIndex(ctx)
eq(idx, (phrase[1] + phrase[2]) % 8, "painting index = (w0 + w1) & 7")

print("[test] Lottery corner (pokeemerald/src/lottery_corner.c)")
local Lottery = require("src.core.game3.rse.lottery")
eq(Lottery.matchingDigits(12345, 12345), 5, "5 digits")
eq(Lottery.matchingDigits(12345, 62345), 4, "last 4 digits")
eq(Lottery.matchingDigits(12345, 12346), 0, "first digit differs")
Lottery.setNumber(0x0001D431, session)
eq(Rse.var("VAR_POKELOT_RND1"), 0xD431, "RND1 = low 16")
eq(Rse.var("VAR_POKELOT_RND2"), 0x0001, "RND2 = high 16")
eq(Lottery.getNumber(session), 0x0001D431, "GetLotteryNumber recombines")
session.party = { { species = 280, otId = 54321 }, { species = 281, otId = 11345, nickname = "RALTS" } }
local r = Lottery.pickTicket(12345, session)
eq(r.tier, 2, "3 matching digits -> prize tier 2")
eq(r.prize, C:require("items", "ITEM_EXP_SHARE"), "tier 2 prize is EXP. SHARE")
eq(r.where, "party", "match found in the party")
eq(Town.data().lotteryPrizes[4], C:require("items", "ITEM_MASTER_BALL"), "sLotteryPrizes[3] = MASTER BALL")
eq(Lottery.ticketString(345), "00345", "ticket zero padded")
Rng.SeedRng(7)
local v = Rng.Random()
Rng.SeedRng(7)
Lottery.setRandomNumber(2, session)
eq(Lottery.getNumber(session), Lottery.isoRandomize2(Lottery.isoRandomize2(v)), "two days = two ISO_RANDOMIZE2 steps")

print("[test] Mauville old man (pokeemerald/src/mauville_old_man.c)")
local OldMan = require("src.core.game3.rse.old_man")
local expect = { [0] = OldMan.BARD, OldMan.BARD, OldMan.HIPSTER, OldMan.HIPSTER, OldMan.TRADER, OldMan.TRADER,
  OldMan.STORYTELLER, OldMan.STORYTELLER, OldMan.GIDDY, OldMan.GIDDY }
for digit = 0, 9 do
  session.trainerId = 40 + digit
  OldMan.set(session)
  eq(session.oldMan.id, expect[digit], "trainer id last digit " .. digit)
end
session.trainerId = 10
OldMan.set(session)
eq(#session.oldMan.songLyrics, 6, "bard has 6 lyrics")
eq(session.oldMan.songLyrics[1], word("EC_WORD_SHAKE"), "default song starts SHAKE")
local Bard = require("src.core.game3.rse.bard_music")
local sim = Bard.simulate(session.oldMan.songLyrics)
check(sim.count > 200, "song lasts more than 200 frames (" .. sim.count .. ")")
eq(sim.frames[sim.count - 1], "THE DIET\nDANCE", "second paragraph reads THE DIET / DANCE")
local sang = 0
for f = 1, sim.count do
  for _, e in ipairs(sim.events[f]) do if e.op == "start" then sang = sang + 1 end end
end
check(sang >= 6, "at least one phoneme per word (" .. sang .. ")")
local tpl = Bard.templatesFor(word("EC_WORD_SHAKE"))
check(tpl[1].songId < C:require("songs", "NUM_PHONEME_SONGS"), "SHAKE has a phoneme")
eq(Bard.pitchTableIndex(word("EC_WORD_SHAKE")), (word("EC_WORD_SHAKE") % 4) + math.floor(word("EC_WORD_SHAKE") / 8) % 2,
  "WORD_TO_PITCH_TABLE_INDEX")
local okBake, pcm = pcall(Bard.bake, sim)
check(okBake, "bard song bakes: " .. tostring(not okBake and pcm or ""))
if okBake then
  check(pcm.samples > 44100 * 3, "rendered more than 3 s of audio (" .. pcm.samples .. ")")
  check(pcm.peak > 0.01, "rendered audio is not silent (peak " .. string.format("%.4f", pcm.peak) .. ")")
end

session.trainerId = 18
OldMan.set(session)
Rng.SeedRng(99)
local lines, n = {}, 0
while OldMan.giddyShouldTellAnotherTale(session) and n < 20 do
  n = n + 1
  lines[n] = OldMan.generateGiddyLine(session)
end
check(n >= 1 and n <= 10, "giddy tells 1..10 tales (" .. n .. ")")
check(lines[1] ~= nil and lines[1] ~= "", "giddy line text")

session.trainerId = 16
OldMan.set(session)
eq(OldMan.freeStorySlot(session), 0, "storyteller starts empty")
session.gameStats = { [9] = 42 }
local ok, value = OldMan.initializeRandomStat(session)
check(ok, "a stat >= minVal is recorded")
eq(value, 42, "recorded trainer battles value")
eq(OldMan.freeStorySlot(session), 1, "one tale known")
session.gameStats[9] = 43
OldMan.selectedStory = 0
check((OldMan.updateStat(session)), "stat increase re-records the tale")

session.trainerId = 12
OldMan.set(session)
local w = OldMan.unlockRandomTrendySaying(session)
eq(math.floor(w / 512), Town.EC_GROUP.TRENDY_SAYING, "hipster teaches a trendy saying")
check(OldMan.isTrendySayingUnlocked(w % 512, session), "saying unlocked")

print("[test] Lilycove lady (pokeemerald/src/lilycove_lady.c)")
local Lady = require("src.core.game3.rse.lilycove_lady")
for tid = 0, 5 do
  session.trainerId = tid
  Lady.init(session)
  eq(session.lilycoveLady.id, math.floor(tid / 2), "lady from trainer id " .. tid)
end
session.trainerId = 0
Lady.init(session)
local q = Lady.quiz(session)
eq(#q.question, 9, "quiz has 9 question words")
eq(q.correctAnswer, Town.data().lady.quizAnswers[q.questionId + 1], "answer from sQuizLadyQuizAnswers")
q.playerAnswer = q.correctAnswer
check(Lady.isAnswerCorrect(session), "correct answer accepted")
q.playerAnswer = word("EC_WORD_COOL")
check(not Lady.isAnswerCorrect(session), "wrong answer rejected")
session.trainerId = 2
Lady.init(session)
local f = Lady.favor(session)
local liked = Town.data().lady.favorAccepted[f.favorId + 1][1]
check(Lady.doesFavorLadyLikeItem(liked, session), "accepted item liked")
eq(Lady.favorState(session), Lady.STATE_COMPLETED, "favor state completed")
Lady.doesFavorLadyLikeItem(f.bestItem, session)
check(Lady.favorThresholdMet(session), "best item jumps to the gift threshold")
session.trainerId = 4
Lady.init(session)
local c = Lady.contest(session)
c.category = 0
check(Lady.givePokeblock({ spicy = 20 }, session), "cool lady likes spicy")
check(not Lady.givePokeblock({ dry = 20 }, session), "cool lady dislikes dry")
eq(c.maxSheen, 20, "max sheen recorded")
local tvData = Lady.contestLadyTvData(session)
eq(tvData.contestCategory, 0, "TV data carries the category")
eq(tvData.pokeblockState, Lady.CONTEST_LADY_NORMAL, "one good pokeblock -> CONTEST_LADY_NORMAL")
check(tvData.nickname ~= "", "TV data carries the contest mon name")
local gfx, mon = Lady.gfx(session)
eq(gfx, C:require("event_objects", "OBJ_EVENT_GFX_GIRL_2"), "contest lady gfx")
eq(mon, C:require("event_objects", "OBJ_EVENT_GFX_ZIGZAGOON_1"), "cool contest mon gfx")

print("[test] Daily events (pokeemerald/src/clock.c:36)")
require("src.core.game3.rse.daily_events")
local TimeEvents = require("src.core.game3.time_events")
local perDay = TimeEvents.handlers()
for _, name in ipairs({ "UpdateDewfordTrendPerDay", "UpdateFrontierManiac", "UpdateFrontierGambler", "SetRandomLotteryNumber" }) do
  check(type(perDay[name]) == "function", name .. " registered")
end
Rse.setVar("VAR_FRONTIER_MANIAC_FACILITY", 8)
require("src.core.game3.rse.daily_events").updateFrontierManiac(5, session)
eq(Rse.var("VAR_FRONTIER_MANIAC_FACILITY"), 3, "maniac facility wraps at 10")

GameVersion.set(before)
T.finish()
