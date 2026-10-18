package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
Profile.reset()
GameVersion.set("emerald")

local Dataset = require("src.core.game3.dataset")
local cache = Dataset.cache()
local src = cache and cache.read and cache:read("data/generated/gba/pokemon/battle/manifest.lua")
local manifest = type(src) == "string" and load(src, "@manifest", "t", {})()
if not (manifest and manifest.layout == "rse") then
  print("game3_battle_replay_test: skipped (no Emerald cache; set POKEPORT_IDENTITY)")
  os.exit(0)
end

require("src.import.gba.versions").select("emerald")
local C = require("src.core.game3.constants").of("emerald")
local BattleProfile = require("src.core.game3.battle.profile")
BattleProfile.reset()
local Pokemon = require("src.core.game3.pokemon")
Pokemon.install(nil)
local Battle = require("src.core.game3.battle")
local Ui = require("src.core.game3.battle.ui")
local RB = require("src.core.game3.rse.recorded_battle")
local Runtime = require("src.core.game3.runtime")
local Trainers = require("src.core.game3.scripting.trainers")
local BattleBridge = require("src.core.game3.battle_bridge")
local Rng = require("src.core.game3.rng")

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

local sess = { version = "emerald", name = "BRENDAN", money = 0, party = {} }
local prevGet = Runtime.getSession
Runtime.getSession = function() return sess end

-- each battle gets fresh objects, since a battle mutates the mons it is given
local function singleStart(extra)
  local o = {
    session = sess,
    playerParty = { mon("SPECIES_MARSHTOMP", 6, { "MOVE_TACKLE", "MOVE_WATER_GUN" }) },
    foe = mon("SPECIES_POOCHYENA", 9, { "MOVE_TACKLE", "MOVE_BITE" }),
    onDone = function() end,
  }
  for k, v in pairs(extra or {}) do o[k] = v end
  return o
end

local function doubleStart(extra)
  local tidA, tidB = C.trainers.byName.TRAINER_CALVIN_1, C.trainers.byName.TRAINER_RICK
  local foe, foeHalf = BattleBridge.twoOpponentFoe(Trainers.foeFromId(tidA), tidB)
  local o = {
    session = sess,
    playerParty = { mon("SPECIES_SWAMPERT", 70, { "MOVE_SURF", "MOVE_EARTHQUAKE" }),
      mon("SPECIES_BLAZIKEN", 70, { "MOVE_SKY_UPPERCUT", "MOVE_FLAMETHROWER" }) },
    foe = foe, trainerId = tidA, trainerIdB = tidB, twoOpponents = true,
    double = true, foeHalf = foeHalf,
    defeatText = "LOSE-A", defeatTextB = "LOSE-B", onDone = function() end,
  }
  for k, v in pairs(extra or {}) do o[k] = v end
  return o
end

-- replays drive the battle to its end with no player input: autoFight stays off
local function drive(limit)
  local guard = 0
  while Battle.isActive() and guard < limit do
    guard = guard + 1
    Battle.update(1 / 60, nil)
  end
  return not Battle.isActive()
end

local function outcome()
  local st = Battle.getState()
  return {
    result = st and st.result,
    turn = st and st.turn,
    playerHp = st and st.player and st.player.mon and st.player.mon.hp,
    foeHp = st and st.enemy and st.enemy.mon and st.enemy.mon.hp,
  }
end

local function countKeys(t)
  local n = 0
  for _ in pairs(t or {}) do n = n + 1 end
  return n
end

-- record a headless auto-fight battle with a battle-local stream, then return the record
local function record(build)
  local rec = RB.beginRecording(sess, { kind = "test" })
  local o = build({ headless = true, autoFight = true, rng = rec.rng.fn, recorder = rec })
  local ok, err = Battle.start(o)
  if not ok then return nil, err end
  local live = outcome()
  rec:finish(sess, live.result)
  return rec, live
end

-- replay a stored record through the replay hook
local function replay(build, stored)
  local rep = RB.beginReplay(stored)
  local ok, err = Battle.start(build({ headless = true, autoFight = false, rng = rep.rng.fn, replay = rep }))
  if not ok then return nil, err end
  drive(20000)
  return outcome(), rep
end

local function logHas(needle)
  for _, t in ipairs(Ui.log() or {}) do
    if type(t) == "string" and t:find(needle, 1, true) then return true end
  end
  return false
end

---- singles: record, save round trip, replay

local rec, live = record(singleStart)
check(rec ~= nil, "singles recorded battle starts")
check(not Battle.isActive(), "singles recording runs to the end")
check(countKeys(rec.record.turns) >= 2, "recording stores a checkpoint per planned turn")

local save = { pendingRecordedBattle = rec.record }
check(RB.moveToSaveData(save), "recorded battle moves into save data")
check(RB.canCopy(save), "saved recorded battle is valid")

local sReplayed = replay(singleStart, save.recordedBattle)
eq(sReplayed.result, live.result, "singles replay ends with the recorded result")
eq(sReplayed.turn, live.turn, "singles replay plays the recorded number of turns")
eq(sReplayed.playerHp, live.playerHp, "singles replay leaves the player with the recorded HP")
eq(sReplayed.foeHp, live.foeHp, "singles replay leaves the foe with the recorded HP")

---- negative control: a record missing a turn must end the replay, not follow live input

local truncated = { seed = save.recordedBattle.seed, battleFlags = 1, turns = {}, replaces = {} }
for n, t in pairs(save.recordedBattle.turns) do truncated.turns[n] = t end
truncated.turns[live.turn] = nil
local cut = replay(singleStart, truncated)
eq(cut.result, "draw", "a replay that runs out of stored turns ends as a draw")
check(logHas("no more stored turns"), "the replay miss is written to the battle log")
check(not Battle.isActive(), "the replay miss ends the battle")

---- doubles: same record and replay path through the doubles turn and faint hooks

local drec, dlive = record(doubleStart)
check(drec ~= nil, "doubles recorded battle starts")
check(not Battle.isActive(), "doubles recording runs to the end")
local dsave = { pendingRecordedBattle = drec.record }
check(RB.moveToSaveData(dsave), "doubles record moves into save data")
local moneyBefore, domeBefore = sess.money, sess.frontierDomeLastMoves
local dReplayed = replay(doubleStart, dsave.recordedBattle)
eq(sess.money, moneyBefore, "playback leaves the live session money alone")
eq(sess.frontierDomeLastMoves, domeBefore, "playback leaves the live Dome record alone")
eq(dReplayed.result, dlive.result, "doubles replay ends with the recorded result")
eq(dReplayed.turn, dlive.turn, "doubles replay plays the recorded number of turns")
eq(dReplayed.playerHp, dlive.playerHp, "doubles replay leaves the lead player with the recorded HP")
eq(dReplayed.foeHp, dlive.foeHp, "doubles replay leaves the lead foe with the recorded HP")

---- tampered record: one stored action changed must not replay to the same battle

local function copyRecord(src)
  local out = { seed = src.seed, battleFlags = src.battleFlags, turns = {}, replaces = {} }
  for n, t in pairs(src.turns) do
    local acts = {}
    for side, a in pairs(t.acts) do
      local c = {}
      for k, v in pairs(a) do c[k] = v end
      acts[side] = c
    end
    out.turns[n] = { rng = t.rng, acts = acts }
  end
  return out
end

local tampered = copyRecord(save.recordedBattle)
local firstPlayer = tampered.turns[1].acts.player
firstPlayer.move, firstPlayer.slot = C.moves.byName.MOVE_WATER_GUN, 2
local tamperedOut, _ = replay(singleStart, tampered)
local miss = logHas("no more stored turns")
check(miss or tamperedOut.result ~= live.result or tamperedOut.turn ~= live.turn
  or tamperedOut.playerHp ~= live.playerHp or tamperedOut.foeHp ~= live.foeHp,
  "a tampered stored action changes the replay or fires the replay miss")

---- the global stream may move between record and replay; the battle-local stream decides

local rec2, live2 = record(singleStart)
for _ = 1, 7 do Rng.Random() end
local save2 = { pendingRecordedBattle = rec2.record }
RB.moveToSaveData(save2)
for _ = 1, 13 do Rng.Random() end
local perturbed = replay(singleStart, save2.recordedBattle)
eq(perturbed.result, live2.result, "replay after global rng moves ends with the recorded result")
eq(perturbed.turn, live2.turn, "replay after global rng moves plays the recorded turns")
eq(perturbed.playerHp, live2.playerHp, "replay after global rng moves leaves the recorded player HP")
eq(perturbed.foeHp, live2.foeHp, "replay after global rng moves leaves the recorded foe HP")

---- forfeit: the recorder keeps the flag, and a replayed forfeit ends the battle without input

local fr = RB.beginRecording(sess, { kind = "test" })
fr:onTurn(1, { player = { kind = "run", forfeit = true, battler = 0, user = "player" } })
eq(fr:finish(nil, "lose").turns[1].acts.player.forfeit, true, "the recorder keeps a forfeit flag on the stored action")

local forfeitRecord = copyRecord(save.recordedBattle)
forfeitRecord.turns = { [1] = { rng = save.recordedBattle.turns[1].rng, acts = {
  player = { kind = "run", forfeit = true, battler = 0, user = "player" },
  enemy = save.recordedBattle.turns[1].acts.enemy,
} } }
local forfeited = replay(singleStart, forfeitRecord)
eq(forfeited.result, "forfeited", "a replayed forfeit ends the battle as forfeited")
check(not Battle.isActive(), "a replayed forfeit leaves no battle running")

---- no replay and no auto-fight: the battle waits for the player instead of acting

local waiting = singleStart({ headless = true, autoFight = false, session = sess })
check(Battle.start(waiting), "a battle without replay starts")
for _ = 1, 200 do Battle.update(1 / 60, nil) end
check(Battle.isActive(), "a battle without replay or auto-fight stays active while waiting for input")
eq(Battle._phase, "command", "a battle without replay or auto-fight waits at the command phase")
Battle.abort("run")

---- Baton Pass: the player's switch pick is recorded and replayed through the same FIFO

local function batonStart(extra)
  local o = singleStart(extra)
  o.playerParty = {
    mon("SPECIES_MARSHTOMP", 30, { "MOVE_BATON_PASS", "MOVE_WATER_GUN" }),
    mon("SPECIES_ZIGZAGOON", 20, { "MOVE_TACKLE" }),
  }
  return o
end
local brec, blive = record(batonStart)
check(brec ~= nil and blive.result ~= nil, "a baton pass battle records")
local bsave = { pendingRecordedBattle = brec.record }
RB.moveToSaveData(bsave)
local bpicks = 0
for _, r in ipairs(bsave.recordedBattle.replaces) do
  if r.battler == 0 then bpicks = bpicks + 1 end
end
check(bpicks >= 1, "the baton pass pick is stored in the replace FIFO")
local bReplayed, bRep = replay(batonStart, bsave.recordedBattle)
eq(bReplayed.result, blive.result, "baton pass replay ends with the recorded result")
eq(bReplayed.turn, blive.turn, "baton pass replay plays the recorded turns")
eq(bReplayed.playerHp, blive.playerHp, "baton pass replay leaves the recorded player HP")
eq(bRep:nextReplace(0), nil, "baton pass replay consumes every stored pick")

---- headless trainer battle with auto-fight off and no replay: the player is asked for input

local dwait = doubleStart({ headless = true, autoFight = false, session = sess })
check(Battle.start(dwait), "a headless doubles trainer battle without replay starts")
for _ = 1, 200 do Battle.update(1 / 60, nil) end
check(Battle.isActive(), "a headless doubles trainer battle without replay waits for the player")
eq(Battle._phase, "command", "a headless doubles trainer battle without replay waits at the command phase")
Battle.abort("run")

Runtime.getSession = prevGet
T.finish("game3_battle_replay_test")
