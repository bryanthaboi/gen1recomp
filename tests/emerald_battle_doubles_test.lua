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
local src = cache and cache.read and cache:read("data/generated/gba/pokemon/battle/manifest.lua")
local manifest = type(src) == "string" and load(src, "@manifest", "t", {})()
if not (manifest and manifest.layout == "rse") then
  print("emerald_battle_doubles_test: skipped (no Emerald cache; set POKEPORT_IDENTITY)")
  os.exit(0)
end

require("src.import.gba.versions").select("emerald")
local C = require("src.core.game3.constants").of("emerald")
local BattleProfile = require("src.core.game3.battle.profile")
BattleProfile.reset()
local Pokemon = require("src.core.game3.pokemon")
Pokemon.install(nil)
local State = require("src.core.game3.battle.state")
local Engine = require("src.core.game3.battle.engine")
local Ai = require("src.core.game3.battle.ai")
local BattleText = require("src.core.game3.battle.battle_text")
local Adapter = require("src.core.game3.battle.adapter")
local Trainers = require("src.core.game3.scripting.trainers")
local BattleBridge = require("src.core.game3.battle_bridge")
local Prize = require("src.core.game3.battle.prize")
local RomText = require("src.core.game3.rom_text")

local session = { version = "emerald" }
local bp = BattleProfile.get(session)
eq(bp.kinds.twoOpponents, true, "Emerald profile enables two-opponent battles")
eq(bp.rules.aiDoubles, "per_target", "Emerald AI scores every target in doubles")
eq(bp.rules.aiMoveHistory, "battler", "Emerald AI move history is per battler")
local fr = BattleProfile.get({ version = "firered" })
eq(fr.kinds.twoOpponents, nil, "FireRed profile has no two-opponent kind")
eq(fr.rules.aiDoubles, nil, "FireRed doubles AI unchanged")

local function mon(name, level, moves)
  local m = { species = C.species.byName[name], level = level, moves = {}, pp = {} }
  for i, mv in ipairs(moves) do
    m.moves[i] = C.moves.byName[mv]
    m.pp[i] = 20
  end
  m.iv, m.ivs = 10, { hp = 10, atk = 10, def = 10, spa = 10, spd = 10, spe = 10 }
  m.evs = { hp = 0, atk = 0, def = 0, spa = 0, spd = 0, spe = 0 }
  m = require("src.core.game3.battle.damage").ensureStats(m, level)
  m.hp = m.hp or m.maxHp
  return m
end

local foeParty = {
  mon("SPECIES_POOCHYENA", 10, { "MOVE_TACKLE" }),
  mon("SPECIES_ZIGZAGOON", 10, { "MOVE_TACKLE" }),
  mon("SPECIES_WURMPLE", 10, { "MOVE_TACKLE" }),
  mon("SPECIES_TAILLOW", 10, { "MOVE_PECK" }),
  mon("SPECIES_WINGULL", 10, { "MOVE_WATER_GUN" }),
}
local playerParty = {
  mon("SPECIES_MARSHTOMP", 20, { "MOVE_TACKLE", "MOVE_WATER_GUN" }),
  mon("SPECIES_COMBUSKEN", 20, { "MOVE_EMBER", "MOVE_PECK" }),
}
local st = State.new({ double = true, playerParty = playerParty, foeParty = foeParty, foeHalf = 2 })
st.session = session
eq(st.foeHalf, 2, "state keeps trainer A's half size")
eq(st.enemy.partyIndex, 1, "left opponent leads with A's first mon (battle_controllers.c:650)")
eq(st.battlers[3].partyIndex, 3, "right opponent leads with B's first mon")
check(State.ownsSlot(st, 1, 2) and not State.ownsSlot(st, 1, 3), "battler 1 owns only A's half")
check(State.ownsSlot(st, 3, 5) and not State.ownsSlot(st, 3, 1), "battler 3 owns only B's half")
check(State.ownsSlot(st, 0, 2) and State.ownsSlot(st, 2, 1), "player side keeps the whole party")
st.enemy.mon.hp = 0
st.enemy.fainted = true
local c1 = Engine.replacementCandidates(st, 1)
eq(#c1, 1, "left opponent can only send A's other mon")
eq(c1[1], 2, "replacement for battler 1 is slot 2")
local c3 = Engine.switchCandidates(st, 3)
check(#c3 == 2 and c3[1] == 4 and c3[2] == 5, "switch candidates for battler 3 are B's slots 4-5")
foeParty[2].hp = 0
eq(#Engine.replacementCandidates(st, 1), 0, "A out of mons: battler 1 has no replacement even though B has mons")
check(Engine.hasLivingMons(st.foeParty), "the enemy side still has B's mons")

local nohalf = State.new({ double = true, playerParty = playerParty, foeParty = {
  mon("SPECIES_POOCHYENA", 10, { "MOVE_TACKLE" }), mon("SPECIES_ZIGZAGOON", 10, { "MOVE_TACKLE" }) } })
eq(nohalf.foeHalf, nil, "plain double battle has no party halves")
eq(nohalf.battlers[3].partyIndex, 2, "plain double: right opponent is the second mon")

local draws = 0
local seq = { 7, 3, 9, 1, 2, 5, 4, 8, 6, 0, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47, 53, 59, 61, 67, 71 }
local function rng(lo, hi)
  draws = draws + 1
  local v = seq[((draws - 1) % #seq) + 1]
  if hi == nil then return v end
  return lo + (v % (hi - lo + 1))
end
local pack = {
  table = { "T" },
  scripts = {
    T = { { op = "if_target_is_ally", target = "ALLY" }, { op = "end" } },
    ALLY = { { op = "score", delta = -20 }, { op = "end" } },
  },
}
local st2 = State.new({ double = true, playerParty = {
  mon("SPECIES_MARSHTOMP", 20, { "MOVE_TACKLE" }), mon("SPECIES_COMBUSKEN", 20, { "MOVE_EMBER" }) },
  foeParty = { mon("SPECIES_POOCHYENA", 10, { "MOVE_TACKLE" }),
    mon("SPECIES_ZIGZAGOON", 10, { "MOVE_TACKLE" }) } })
st2.session = session
st2.trainerItems = { 0, 0, 0, 0 }
local act = Ai.chooseMove(st2, { battler = 1, rng = rng, pack = pack, aiFlags = 1 })
check(act and act.kind == "move", "doubles AI returns a move")
check(act.target == 0 or act.target == 2, "doubles AI never targets its ally when the ally scores < 100 (target "
  .. tostring(act.target) .. ")")
-- pokeemerald/src/battle_ai_script_commands.c:312
eq(draws, 5 + 3 * 6 + 1, "RNG draws: outer SetupAIData 5, three targets x (SetupAIData 5 + pick 1), target pick 1")
local want = { 0, 2 }
local finalDraw = seq[draws]
eq(act.target, want[(finalDraw % 2) + 1], "target = mostViableTargets[Random() % 2] over the two foes")

draws = 0
local pack2 = {
  table = { "U" },
  scripts = {
    U = { { op = "if_target_is_ally", target = "BOOST" }, { op = "end" } },
    BOOST = { { op = "score", delta = 5 }, { op = "end" } },
  },
}
local act2 = Ai.chooseMove(st2, { battler = 1, rng = rng, pack = pack2, aiFlags = 1 })
eq(act2.target, 3, "an ally scoring >= 100 and above both foes becomes the target (score 105)")

local frSt = State.new({ double = true, playerParty = st2.playerParty, foeParty = st2.foeParty })
frSt.session = { version = "firered" }
draws = 0
Ai.chooseMove(frSt, { battler = 1, rng = rng, pack = pack, aiFlags = 1 })
eq(draws, 5 + 1, "FireRed doubles keep one scoring pass (4 sim + target + pick)")

st2.battlers[0].lastMoveId = C.moves.byName.MOVE_TACKLE
Ai.recordLastUsedMove(st2, 0)
st2.battlers[0].lastMoveId = C.moves.byName.MOVE_TACKLE
Ai.recordLastUsedMove(st2, 0)
local h = Ai.usedMoves(st2, 0)
eq(h[1], C.moves.byName.MOVE_TACKLE, "history records the target's last move")
eq(h[2], 0, "history does not duplicate a move (battle_ai_script_commands.c:618)")
eq(Ai.usedMoves(st2, 2)[1], 0, "history is per battler, not per side")
st2.battlers[0] = State.makeBattler(st2.playerParty[2], "player", { partyIndex = 2, id = 0 })
eq(Ai.usedMoves(st2, 0)[1], 0, "switching in clears the battler's move history (battle_main.c:3260)")

local AiCmds = require("src.core.game3.battle.ai_cmds")
st2.battlers[0].lastMoveId = C.moves.byName.MOVE_EMBER
Ai.recordLastUsedMove(st2, 0)
local vm = { st = st2, user = st2.battlers[1], target = st2.battlers[0], ip = 1 }
local jumped
vm.jump = function(_, name) jumped = name end
AiCmds.CMD.if_has_move(vm, { battler = 0, move = C.moves.byName.MOVE_EMBER, target = "YES" })
eq(jumped, "YES", "if_has_move AI_TARGET reads the recorded history")
jumped = nil
AiCmds.CMD.if_has_move(vm, { battler = 0, move = C.moves.byName.MOVE_PECK, target = "YES" })
eq(jumped, nil, "if_has_move AI_TARGET ignores a known but unused move")

local function textOf(key, fill)
  return BattleText.get(key, fill)
end
local fillTwo = { trainer = true, twoOpponents = true, double = true, trainer1Class = "TWINS", trainer1Name = "AMY",
  trainer2Class = "LASS", trainer2Name = "HALEY", side = "enemy",
  opponentMon1 = { mon = { species = C.species.byName.SPECIES_POOCHYENA } },
  opponentMon2 = { mon = { species = C.species.byName.SPECIES_TAILLOW } } }
eq(BattleText.key(BattleText.INTROMSG, fillTwo), "sText_TwoTrainersWantToBattle", "intro key for two opponents")
eq(BattleText.key(BattleText.INTROSENDOUT, fillTwo), "sText_TwoTrainersSentPkmn", "send-out key for two opponents")
local two = textOf(BattleText.INTROMSG, fillTwo)
check(two:find("AMY") and two:find("HALEY"), "two-trainer intro names both trainers: " .. two:gsub("\n", " "))
local f3 = { trainer = true, twoOpponents = true, side = "enemy", switchBattler = 3, buff1 = "TAILLOW", hpScale = 0,
  trainer1Class = "TWINS", trainer1Name = "AMY", trainer2Class = "LASS", trainer2Name = "HALEY" }
eq(BattleText.key(BattleText.SWITCHINMON, f3), "sText_Trainer2SentOutPkmn", "B's replacement uses Trainer2SentOutPkmn")
check(textOf(BattleText.SWITCHINMON, f3):find("HALEY"), "B's replacement names trainer B")
f3.switchBattler = 1
eq(BattleText.key(BattleText.SWITCHINMON, f3), "sText_Trainer1SentOutPkmn2", "A's replacement uses Trainer1SentOutPkmn2")
check(RomText.has("STRINGID_TWOENEMIESDEFEATED"), "Emerald text has STRINGID_TWOENEMIESDEFEATED")
eq(BattleText.key(0, { wally = true }), "sText_WildPkmnAppearedPause", "Wally tutorial intro pauses (battle_message.c:2029)")

local rowA = Trainers.foeFromId(C.trainers.byName.TRAINER_CALVIN_1)
local combined, half = BattleBridge.twoOpponentFoe(rowA, C.trainers.byName.TRAINER_RICK)
eq(half, math.min(3, #rowA.party), "A contributes at most three mons")
eq(#combined.party, half + math.min(3, #Trainers.foeFromId(C.trainers.byName.TRAINER_RICK).party), "B fills the second half")
local a = Prize.calcRse(C.trainers.byName.TRAINER_CALVIN_1, { double = true, twoOpponents = true })
local b = Prize.calcRse(C.trainers.byName.TRAINER_RICK, { double = true, twoOpponents = true })
eq(Prize.rewardRse(C.trainers.byName.TRAINER_CALVIN_1, { double = true, twoOpponents = true,
  trainerIdB = C.trainers.byName.TRAINER_RICK }), a + b, "two-opponent money is A + B with no double x2")

local Battle = require("src.core.game3.battle")
local Ui = require("src.core.game3.battle.ui")
local tidA, tidB = C.trainers.byName.TRAINER_CALVIN_1, C.trainers.byName.TRAINER_RICK
local foe = BattleBridge.twoOpponentFoe(Trainers.foeFromId(tidA), tidB)
local sess = { version = "emerald", name = "BRENDAN", money = 0, party = {} }
local strong = mon("SPECIES_SWAMPERT", 70, { "MOVE_SURF", "MOVE_EARTHQUAKE" })
local strong2 = mon("SPECIES_BLAZIKEN", 70, { "MOVE_SKY_UPPERCUT", "MOVE_FLAMETHROWER" })
local Runtime = require("src.core.game3.runtime")
local prevGet = Runtime.getSession
Runtime.getSession = function() return sess end
local seed = 0x1234
local function lcg(lo, hi)
  seed = (seed * 1103515245 + 24691) % 2147483648
  local v = math.floor(seed / 65536)
  if lo == nil then return v / 32768 end
  if hi == nil then return 1 + v % lo end
  return lo + v % (hi - lo + 1)
end
local okStart, err = Battle.start({
  headless = true, autoFight = true, session = sess, rng = lcg,
  playerParty = { strong, strong2 }, foe = foe, trainerId = tidA, trainerIdB = tidB, twoOpponents = true,
  double = true, foeHalf = select(2, BattleBridge.twoOpponentFoe(Trainers.foeFromId(tidA), tidB)),
  defeatText = "LOSE-A", defeatTextB = "LOSE-B", onDone = function() end,
})
check(okStart, "headless two-opponent battle starts " .. tostring(err or ""))
local log = Ui.log and Ui.log() or {}
local function idx(needle)
  for i, t in ipairs(log) do
    if type(t) == "string" and t:find(needle, 1, true) then return i end
  end
  return nil
end
local st3 = Battle.getState()
eq(st3 and st3.result, "win", "the strong pair wins")
local iDef, iA, iB, iMoney = idx("defeated"), idx("LOSE-A"), idx("LOSE-B"), idx("BRENDAN got")
print(string.format("[info] text order defeated=%s A=%s B=%s money=%s", tostring(iDef), tostring(iA), tostring(iB),
  tostring(iMoney)))
check(iDef and iA and iB and iMoney and iDef < iA and iA < iB and iB < iMoney,
  "LocalTwoTrainersDefeated order: TWOENEMIESDEFEATED, A lose, B lose, money (battle_scripts_1.s:2924)")
eq(sess.money, Prize.rewardRse(tidA, { double = true, twoOpponents = true, trainerIdB = tidB }), "money = A + B")
check(idx(Trainers.info(tidB).name) ~= nil, "trainer B is named in the battle text")
Runtime.getSession = prevGet

T.finish("emerald_battle_doubles_test")
