package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
Profile.reset()
GameVersion.set("emerald")

require("tests.game3_cache").mount("emerald")
local Dataset = require("src.core.game3.dataset")
local cache = Dataset.cache()
local function has(rel)
  local src = cache and cache.read and cache:read(rel)
  return type(src) == "string"
end
if not (has("data/generated/gba/frontier/trainers.lua") and has("data/generated/gba/rse/frontier_f2/manifest.lua")) then
  print("emerald_frontier_f2_test: skipped (no Emerald cache with rse/frontier_f2; set POKEPORT_IDENTITY)")
  os.exit(0)
end

require("src.import.gba.versions").select("emerald")
local C = require("src.core.game3.constants").of("emerald")
local Pokemon = require("src.core.game3.pokemon")
Pokemon.install(nil)
local BattleProfile = require("src.core.game3.battle.profile")
BattleProfile.reset()
local Runtime = require("src.core.game3.runtime")
local Rng = require("src.core.game3.rng")
local State = require("src.core.game3.battle.state")

local store = { flags = {}, vars = {} }
local Space = require("src.core.game3.scripting.space")
Space.store = store

local sess = { version = "emerald", name = "BRENDAN", trainerId = 12345, secretId = 4321, money = 1000, party = {},
  gender = 0, bag = {}, flags = store.flags, vars = store.vars }
local prevGet = Runtime.getSession
Runtime.getSession = function() return sess end

local Data = require("src.core.game3.rse.frontier.f2_data")
local D = require("src.core.game3.rse.frontier.trainers")
local Util = require("src.core.game3.rse.frontier.util")
local Rse = require("src.core.game3.rse.init")
local Palace = require("src.core.game3.rse.frontier.palace")
local Arena = require("src.core.game3.rse.frontier.arena")
local Dome = require("src.core.game3.rse.frontier.dome")
local FacPalace = require("src.core.game3.battle.facility_palace")
local FacArena = require("src.core.game3.battle.facility_arena")
local FacDome = require("src.core.game3.battle.facility_dome")

local function mv(name) return C:require("moves", name) end
local function sp(name) return C:require("species", name) end

local man = Data.manifest()
local P, A, M = man.palace, man.arena, man.dome
-- pokeemerald/src/battle_script_commands.c:859
eq(table.concat(P.moveGroupLikelihood[1], ","), "61,68,61,68", "Hardy palace likelihoods (battle_script_commands.c:859)")
eq(table.concat(P.moveGroupLikelihood[4], ","), "38,69,70,85", "Adamant likelihoods")
eq(#P.moveTarget, 25, "one palace target preference per nature")
eq(#P.flavorTextId, 25, "one palace flavor text per nature")
eq(#P.earlyPrizes, 6, "six early palace prizes (battle_palace.c:43)")
eq(P.latePrizes[#P.latePrizes], C:require("items", "ITEM_CHOICE_BAND"), "last late palace prize is the Choice Band")
eq(P.inobedientStringIds[5], C:require("battle_string_ids", "STRINGID_PKMNINCAPABLEOFPOWER"),
  "gInobedientStringIds[B_MSG_INCAPABLE_OF_POWER]")
eq(A.mindRatings[mv("MOVE_POUND") + 1], 1, "Pound gives 1 mind point (battle_arena.c:59)")
eq(A.mindRatings[mv("MOVE_PROTECT") + 1], -1, "Protect subtracts a mind point")
eq(A.mindRatings[mv("MOVE_FAKE_OUT") + 1], -1, "Fake Out subtracts a mind point")
eq(A.mindRatings[mv("MOVE_COUNTER") + 1], 0, "Counter gives no mind points")
eq(A.mindRatings[mv("MOVE_GROWL") + 1], 0, "status moves give no mind points")
eq(#A.refereeStrings, 9, "nine referee strings (battle_message.c:1409)")
eq(A.windows[23].left, 2, "ARENA_WIN_JUDGMENT_TEXT sits at column 2 (battle_bg.c:584)")
eq(A.textInfo[23].fg, 2, "judgment text uses dark gray")
eq(table.concat(M.treeTrainerIds, ","), "0,8,12,4,7,15,11,3,2,10,14,6,5,13,9,1", "sTourneyTreeTrainerIds")
eq(table.concat(M.idToOpponentId[1], ","), "8,0,4,8", "sIdToOpponentId[0]")
eq(#M.styleMovePoints, 355, "a battle-style row per move")
eq(#M.styleThresholds, 31, "31 battle-style thresholds")
eq(#M.text.stats, 43, "43 opponent stat texts")
eq(#M.text.potential, 17, "potential texts for 16 seeds and Tucker")
eq(#M.lineSections[1][1], 4, "trainer 1 round 1 advancement line has four tiles (battle_dome.c:1686)")
eq(M.lineSections[1][1][1].tile, 0x6021, "the first line tile is LINE_H in palette 6")
eq(#M.typeEffectiveness, 111, "gTypeEffectiveness rows incl. the Foresight separator")

-- pokeemerald/src/battle_gfx_sfx_util.c:296
eq(FacPalace.moveGroup(mv("MOVE_TACKLE")), FacPalace.GROUP.ATTACK, "Tackle is an attack move")
eq(FacPalace.moveGroup(mv("MOVE_GROWL")), FacPalace.GROUP.SUPPORT, "Growl is a support move")
eq(FacPalace.moveGroup(mv("MOVE_SWORDS_DANCE")), FacPalace.GROUP.DEFENSE, "Swords Dance is a defense move")
eq(FacPalace.moveGroup(mv("MOVE_SPIKES")), FacPalace.GROUP.SUPPORT, "Spikes is a support move")
eq(FacPalace.moveGroup(mv("MOVE_EARTHQUAKE")), FacPalace.GROUP.ATTACK, "Earthquake is an attack move")

local function mon(name, level, moves, personality)
  local m = D.createMon(sp(name), level, 20, personality or 0, 99)
  local list = {}
  for i, n in ipairs(moves) do list[i] = mv(n) end
  D.setMoves(m, list)
  return m
end

local draws, seq = 0, {}
local function rng(lo, hi)
  draws = draws + 1
  local v = seq[draws] or 0
  if hi == nil then return v end
  return lo + (v % (hi - lo + 1))
end

local ADAMANT = 3
local function palaceState(moves, foeMoves)
  local st = State.new({
    playerParty = { mon("SPECIES_SWAMPERT", 50, moves, ADAMANT) },
    foeParty = { mon("SPECIES_METAGROSS", 50, foeMoves or { "MOVE_TACKLE" }, ADAMANT) },
  })
  st.session = sess
  st.aiFlags = 7
  st.trainerItems = { 0, 0, 0, 0 }
  st.rng = rng
  return st
end

local fac = FacPalace.new()
local st = palaceState({ "MOVE_TACKLE", "MOVE_SWORDS_DANCE", "MOVE_GROWL", "MOVE_PROTECT" })
fac:start(st)
draws, seq = 0, { 10 }
local slot = fac:choose(st, 0, nil)
eq(slot, 1, "Adamant with percent 10 < 38 picks the attack group, only Tackle qualifies")
check(not fac.unable[0], "a mon with a move in the chosen group is able to act")
draws, seq = 0, { 50 }
slot = fac:choose(st, 0, nil)
check(slot == 2 or slot == 4, "percent 50 lands in Adamant's defense range 38..68 (slot " .. tostring(slot) .. ")")
draws, seq = 0, { 80 }
slot = fac:choose(st, 0, nil)
eq(slot, 3, "percent 80 >= 69 picks support, only Growl qualifies")
fac.flags[0] = true
draws, seq = 0, { 60 }
slot = fac:choose(st, 0, nil)
eq(slot, 1, "at half HP Adamant uses the second likelihood pair: 60 < 70 is attack")
fac.flags[0] = nil

local st2 = palaceState({ "MOVE_TACKLE", "MOVE_EARTHQUAKE" })
fac:start(st2)
draws, seq = 0, { 90, 5, 99 }
slot = fac:choose(st2, 0, nil)
check(fac.unable[0] == true, "no move in the chosen group and a failed 50% roll leaves the mon incapable")
fac.unable = {}
draws, seq = 0, { 90, 5, 10 }
slot = fac:choose(st2, 0, nil)
check(not fac.unable[0] and (slot == 1 or slot == 2), "the 50% roll can still let the mon use a random move")

-- pokeemerald/src/battle_script_commands.c:6389
local Ui = require("src.core.game3.battle.ui")
Ui.reset({ headless = true })
Ui.bindState(st, sess)
fac:start(st)
st.turn = 0
fac:turnStart(st, nil, true)
st.player.mon.hp = math.floor(st.player.mon.maxHp / 2)
st.turn = 1
fac:turnStart(st, nil, true)
check(fac.flags[0] == true, "a mon at half HP is flagged at the turn boundary")
local log = Ui.log()
local last = log[#log]
check(type(last) == "string" and last ~= "", "the palace flavor text is printed (" .. tostring(last) .. ")")
local before = #Ui.log()
st.turn = 2
fac:turnStart(st, nil, true)
eq(#Ui.log(), before, "the flavor text prints once per mon")

-- pokeemerald/src/battle_gfx_sfx_util.c:325
local std = State.new({ double = true,
  playerParty = { mon("SPECIES_SWAMPERT", 50, { "MOVE_TACKLE" }, 0), mon("SPECIES_MANECTRIC", 50, { "MOVE_TACKLE" }, 0) },
  foeParty = { mon("SPECIES_METAGROSS", 50, { "MOVE_TACKLE" }), mon("SPECIES_SALAMENCE", 50, { "MOVE_TACKLE" }) } })
std.session = sess
std.rng = rng
std.battlers[1].mon.hp = 10
local pref = P.moveTarget[1]
local want = (pref == FacPalace.TARGET.STRONGER) and 3 or ((pref == FacPalace.TARGET.WEAKER) and 1 or nil)
if want then
  eq(fac:target(std, 0), want, "Hardy's doubles target preference follows gBattlePalaceNatureToMoveTarget")
else
  local t = fac:target(std, 0)
  check(t == 1 or t == 3, "random preference targets a foe")
end

-- pokeemerald/src/battle_palace.c:168
Util.newGame(sess)
local f = Util.frontier(sess)
Rse.setVar("VAR_FRONTIER_BATTLE_MODE", D.MODE.SINGLES, sess)
Rse.setVar("VAR_FRONTIER_FACILITY", D.FACILITY.PALACE, sess)
f.lvlMode = D.LVL.OPEN
Palace.incrementStreak(sess)
eq(Util.get2(f.palaceWinStreaks, 0, 1), 1, "palace streak increments")
eq(Util.get2(f.palaceRecordWinStreaks, 0, 1), 1, "open level records the streak")
f.lvlMode = D.LVL.L50
Util.set2(f.palaceRecordWinStreaks, 0, 0, 10)
Palace.incrementStreak(sess)
eq(Util.get2(f.palaceRecordWinStreaks, 0, 0), 1,
  "IncrementPalaceStreak overwrites a higher record with the current streak (battle_palace.c:177)")
local ctx = { specialVars = {} }
Palace.commentId(ctx, sess)
check((Rse.specialVar(ctx, Util.VAR_RESULT)) < 3, "short palace streak comments are random 0..2")
Util.set2(f.palaceWinStreaks, 0, 0, 60)
Palace.commentId(ctx, sess)
eq(Rse.specialVar(ctx, Util.VAR_RESULT), 3, "50..98 palace streak comment is 3")
Palace.setPrize(sess)
local late = false
for _, it in ipairs(P.latePrizes) do if it == f.palacePrize then late = true end end
check(late, "a 60 streak palace prize comes from the late list")

-- pokeemerald/src/battle_arena.c:470
local afac = FacArena.new()
local ast = State.new({ playerParty = { mon("SPECIES_SWAMPERT", 50, { "MOVE_TACKLE" }) },
  foeParty = { mon("SPECIES_METAGROSS", 50, { "MOVE_TACKLE" }) } })
ast.session = sess
afac:start(ast)
ast.turn = 0
afac:turnStart(ast, nil, true)
eq(afac.counter, 0, "the arena counter starts at 0 for the first turn")
for t = 1, 2 do
  ast.turn = t
  afac:turnStart(ast, nil, true)
end
eq(afac.counter, 2, "after two turn boundaries the arena counter is 2 (battle_main.c:3998)")
afac:initPoints(ast)
afac:addMind(0, mv("MOVE_TACKLE"))
afac:addMind(1, mv("MOVE_PROTECT"))
eq(afac.mind[0], 1, "Tackle adds a mind point")
eq(afac.mind[1], -1, "Protect removes a mind point")
afac:addSkill(0, { obeys = true, super = true })
afac:addSkill(1, { obeys = true, noEffect = true })
eq(afac.skill[0], 2, "a super effective hit adds 2 skill points")
eq(afac.skill[1], -2, "a move with no effect costs 2 skill points")
afac:addSkill(1, { obeys = true, noEffect = true, protectedMiss = true })
eq(afac.skill[1], -2, "a miss into Protect costs nothing")
afac:deductSkill(1, "STRINGID_PKMNSXMADEYUSELESS")
eq(afac.skill[1], -5, "an ability blocking the move costs 3 skill points")
ast.enemy.mon.hp = math.floor(ast.enemy.mon.hp / 2)
local result, rows, total = afac:judge(ast)
eq(result, FacArena.RESULT.PLAYER_WON, "the player wins mind, skill and body")
eq(total[0], 6, "three circles are six points")
eq(rows[0].icons[0], FacArena.ANIM.CIRCLE, "mind circle for the player")
eq(rows[0].icons[1], FacArena.ANIM.X, "mind cross for the opponent")
local flags = FacArena.moveFlags({ { kind = "move", attackerId = 0 }, { kind = "msg", id = "STRINGID_NOTVERYEFFECTIVE" } }, 0)
check(flags.obeys and flags.notVery, "move events are read into skill flags")
Ui.reset({ headless = true })
Ui.bindState(ast, sess)
afac:endTurn(ast, nil, true)
eq(ast.enemy.mon.hp, 0, "the judged loser's mon is knocked out (battle_script_commands.c:6410)")
eq(ast.player.mon.hp > 0, true, "the judged winner keeps its HP")

-- pokeemerald/src/battle_arena.c:731
Rse.setVar("VAR_FRONTIER_FACILITY", D.FACILITY.ARENA, sess)
f.lvlMode = D.LVL.L50
Util.set1(f.arenaWinStreaks, 0, 7)
f.winStreakActiveFlags = 0
Arena.init(sess)
eq(Util.get1(f.arenaWinStreaks, 0), 0, "InitArenaChallenge clears an inactive streak")
Arena.setPrize(sess)
local short = false
for _, it in ipairs(A.shortPrizes) do if it == f.arenaPrize then short = true end end
check(short, "a fresh arena challenge sets a short-streak prize")

-- pokeemerald/src/battle_dome.c:2801
local E = Dome.EFFECTIVENESS
eq(Dome.typeEffectivenessPoints(mv("MOVE_WATER_GUN"), sp("SPECIES_CHARMANDER"), E.GOOD, sess), 4, "x2 is 4 good points")
eq(Dome.typeEffectivenessPoints(mv("MOVE_WATER_GUN"), sp("SPECIES_CHARMANDER"), E.BAD, sess), -2, "x2 is -2 bad points")
eq(Dome.typeEffectivenessPoints(mv("MOVE_WATER_GUN"), sp("SPECIES_CHARMANDER"), E.AI_VS_AI, sess), 12, "x2 is 12 AI points")
eq(Dome.typeEffectivenessPoints(mv("MOVE_EARTHQUAKE"), sp("SPECIES_GASTLY"), E.BAD, sess), 0,
  "Levitate ground in bad mode falls through to 0 (battle_dome.c:2821)")
eq(Dome.typeEffectivenessPoints(mv("MOVE_EARTHQUAKE"), sp("SPECIES_GASTLY"), E.GOOD, sess), 2,
  "Levitate ground in good mode counts as neutral")
eq(Dome.typeEffectivenessPoints(mv("MOVE_GROWL"), sp("SPECIES_GASTLY"), E.GOOD, sess), 0, "status moves score 0")
eq(Dome.typeEffectivenessPoints(mv("MOVE_THUNDERBOLT"), sp("SPECIES_SHEDINJA"), E.GOOD, sess), 2,
  "Wonder Guard never multiplies (battle_dome.c:2839)")
local stats = Dome.calcMonStats(sp("SPECIES_METAGROSS"), 50, 31, 0x3F, 0)
local base = Pokemon.stats(sp("SPECIES_METAGROSS"))
eq(stats[0], math.floor((2 * base.hp + 31) * 50 / 100) + 60, "CalcDomeMonStats HP ignores EVs (battle_dome.c:2531)")
eq(stats[1], (math.floor((2 * base.atk + 31) * 50 / 100) + 5) % 256, "CalcDomeMonStats Attack")
local flags2 = Dome.aiTypeCalc(mv("MOVE_THUNDERBOLT"), sp("SPECIES_GYARADOS"), 0, sess)
eq(flags2, 2, "Thunderbolt on Gyarados is super effective x4")

Rse.setVar("VAR_FRONTIER_FACILITY", D.FACILITY.DOME, sess)
Rse.setVar("VAR_FRONTIER_BATTLE_MODE", D.MODE.SINGLES, sess)
f.lvlMode = D.LVL.L50
sess.party = {
  mon("SPECIES_SWAMPERT", 50, { "MOVE_SURF", "MOVE_EARTHQUAKE", "MOVE_ICE_BEAM", "MOVE_PROTECT" }),
  mon("SPECIES_METAGROSS", 50, { "MOVE_METEOR_MASH", "MOVE_EARTHQUAKE", "MOVE_PSYCHIC", "MOVE_EXPLOSION" }),
  mon("SPECIES_SALAMENCE", 50, { "MOVE_DRAGON_CLAW", "MOVE_FLAMETHROWER", "MOVE_AERIAL_ACE", "MOVE_ROCK_SLIDE" }),
}
f.selectedPartyMons = { 1, 2, 3, 0 }
Rng.SeedRng(0xBEEF)
Dome.init(sess)
local scores = Dome.initTrainers(sess)
local fd = Dome.frontier(sess)
local ids, dup = {}, false
for i = 1, 16 do
  local tid = fd.domeTrainers[i].trainerId
  if ids[tid] then dup = true end
  ids[tid] = true
end
check(not dup, "sixteen distinct tourney trainers")
check(ids[D.TRAINER_PLAYER] == true, "the player is seeded into the tourney")
local sorted = true
for i = 0, 14 do if scores[i] < scores[i + 1] then sorted = false end end
check(sorted, "tourney seeds are sorted by ranking score (battle_dome.c:2466)")
local ptid = Dome.tournamentId(sess, D.TRAINER_PLAYER)
local opp = Dome.opponentTournamentId(sess, 0, D.TRAINER_PLAYER)
eq(opp, M.idToOpponentId[ptid + 1][1], "round 1 opponent comes from sIdToOpponentId")
sess.frontierOpponentA = Dome.playerOpponentTrainerId(sess)
eq(Dome.tournamentId(sess, sess.frontierOpponentA), opp, "dome_setopponent picks the round 1 opponent")
local party = Dome.initOpponentParty(sess)
eq(#party, 2, "the dome opponent brings two of three mons (battle_dome.c:2615)")
eq(party[1].level, 50, "dome opponents are level 50 in the lv50 tourney")
local ivs = party[1].ivs.atk
eq(ivs, 3, "CreateDomeOpponentMon passes the tourney id to GetDomeTrainerMonIvs (battle_dome.c:2590)")
sess.frontierDomeLastMoves = { player = mv("MOVE_SURF"), opponent = 0 }
Dome.resolveWinners({ specialVars = {} }, sess, Dome.PLAYER_WON_MATCH)
local out = 0
for i = 1, 16 do if fd.domeTrainers[i].isEliminated then out = out + 1 end end
eq(out, 8, "after round 1 eight trainers are out (battle_dome.c:5191)")
eq(fd.domeWinningMoves[opp + 1], mv("MOVE_SURF"), "the player's last move is the winning move")
check(not fd.domeTrainers[ptid + 1].isEliminated, "the player advances")
local match = M.idToMatchNumber[M.pairedTrainerIds[ptid + 1] + 1][1]
local ws = Dome.winString(sess, match)
eq(ws.id, Dome.TEXT.WON_USING_MOVE, "a decided round-1 match reports the winning move")
eq(ws.var1, sess.name, "the player is named as the winner")
fd.curChallengeBattleNum = 1
local nxt = Dome.playerOpponentTrainerId(sess)
check(nxt ~= 0 and nxt ~= D.TRAINER_PLAYER, "round 2 has an opponent for the player")
for tid = 0, 15 do
  local card = Dome.trainerCard(sess, tid)
  check(card.style >= 0 and card.style <= 31 and card.statText ~= nil, "info card style/stat for tourney id " .. tid)
end
fd.domePlayerPartyData = {}
for i = 1, 3 do fd.domePlayerPartyData[i] = { moves = { 0, 0, 0, 0 }, evs = { 6, 252, 0, 252, 0, 0 }, nature = 0 } end
eq(Dome.statTextId(sess, ptid), 6, "Atk+Speed EVs pick the atk-and-speed text (battle_dome.c:4686)")
local ctx2 = { specialVars = {} }
Dome.compareSeeds(ctx2, sess)
check(Rse.specialVar(ctx2, Util.VAR_RESULT) == 1 or Rse.specialVar(ctx2, Util.VAR_RESULT) == 2, "dome_compareseeds returns 1 or 2")

-- pokeemerald/data/battle_scripts_1.s:2958
local dfac = FacDome.new()
local dst = State.new({ playerParty = { mon("SPECIES_SWAMPERT", 50, { "MOVE_TACKLE" }) },
  foeParty = { mon("SPECIES_METAGROSS", 50, { "MOVE_TACKLE" }) } })
dst.session = sess
dst.playerParty[1].hp, dst.foeParty[1].hp = 0, 0
eq(dfac:finalResult(dst, "lose"), "draw", "both sides wiped in the dome is a draw")
dst.foeParty[1].hp = 5
eq(dfac:finalResult(dst, "lose"), "lose", "a normal loss stays a loss")

local Natives = require("src.core.game3.scripting.natives")
Natives.bind("emerald")
for _, name in ipairs({ "CallBattleDomeFunction", "CallBattlePalaceFunction", "CallBattleArenaFunction", "DoDomeConfetti" }) do
  local id = C.specials.byName[name]
  check(id ~= nil and Natives.ALLOW["special:" .. id] ~= nil, name .. " is bound on Emerald")
end
check(Rse.system("palace") == Palace and Rse.system("arena") == Arena and Rse.system("dome") == Dome,
  "the facilities register their doSpecialBattle handlers")
Natives.bind("firered")
check(Natives.handlerFor("CallBattleDomeFunction") == nil, "FireRed never binds the dome")

Runtime.getSession = prevGet
GameVersion.set("firered")
T.finish("emerald_frontier_f2_test")
