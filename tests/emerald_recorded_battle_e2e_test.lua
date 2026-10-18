package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
Profile.reset()
GameVersion.set("emerald")

local Dataset = require("src.core.game3.dataset")
local cache = Dataset.cache()
local function has(rel)
  local src = cache and cache.read and cache:read(rel)
  return type(src) == "string"
end
if not (has("data/generated/gba/frontier/trainers.lua") and has("data/generated/gba/rse/frontier/manifest.lua")) then
  print("emerald_recorded_battle_e2e_test: skipped (no Emerald cache with rse/frontier; set POKEPORT_IDENTITY)")
  os.exit(0)
end

require("src.import.gba.versions").select("emerald")
local C = require("src.core.game3.constants").of("emerald")
local BattleProfile = require("src.core.game3.battle.profile")
BattleProfile.reset()
local Pokemon = require("src.core.game3.pokemon")
Pokemon.install(nil)
local Runtime = require("src.core.game3.runtime")
local Rng = require("src.core.game3.rng")
local Battle = require("src.core.game3.battle")
local Ui = require("src.core.game3.battle.ui")
local Serializer = require("src.core.SaveSerializer")

local store = { flags = {}, vars = {} }
local Space = require("src.core.game3.scripting.space")
Space.store = store

local sess = { version = "emerald", name = "BRENDAN", trainerId = 12345, secretId = 4321, money = 1000, party = {},
  gender = 0, bag = {}, flags = store.flags, vars = store.vars }
local prevGet = Runtime.getSession
Runtime.getSession = function() return sess end

local D = require("src.core.game3.rse.frontier.trainers")
local Util = require("src.core.game3.rse.frontier.util")
local Tower = require("src.core.game3.rse.frontier.tower")
local Rse = require("src.core.game3.rse.init")
local NF = require("src.core.game3.scripting.natives_frontier")
local RB = require("src.core.game3.rse.recorded_battle")

Ui.reset({ headless = true })

local function mon(name, level, item)
  local m = D.createMon(C.species.byName[name], level, 20, 7, 99)
  D.setHeldItem(m, item and C.items.byName[item] or 0)
  return m
end

-- a frontier singles battle, built the way the facility does it
Rse.setVar("VAR_FRONTIER_FACILITY", D.FACILITY.TOWER, sess)
Rse.setVar("VAR_FRONTIER_BATTLE_MODE", D.MODE.SINGLES, sess)
Util.newGame(sess)
local f = Util.frontier(sess)
f.lvlMode = 0
sess.party = { mon("SPECIES_SWAMPERT", 50, "ITEM_LEFTOVERS"), mon("SPECIES_BLAZIKEN", 50),
  mon("SPECIES_SCEPTILE", 50) }
sess.frontierOpponentA = 0

Rng.SeedRng(0x1234)
local foeParty = {}
D.fillTrainerParty(sess, 0, 0, D.PARTY_SIZE, foeParty)
check(#foeParty > 0, "the frontier trainer has a party")

local function drive(ctx, limit)
  local guard = 0
  while not ctx.nativePoll() and guard < limit do
    guard = guard + 1
    Battle.update(1 / 60, nil)
    Battle.update(0, nil)
  end
  return ctx.nativePoll()
end

-- pokeemerald/src/battle_tower.c:2007 Tower.startBattle, headless with auto-fight
local ctx = { specialVars = {}, stringVars = { "", "", "" } }
local adapters = { log = function() end }
local started = Tower.startBattle(ctx, adapters, sess, "tower", {
  party = foeParty,
  double = false,
  extra = { headless = true, autoFight = true },
})
-- the headless battle finishes inside the start call, so no yield is needed
check(started == false, "the headless frontier battle finishes inside Tower.startBattle")
local ended = drive(ctx, 20000)
check(ended, "the frontier battle runs to its end headlessly")

-- the finished battle leaves a pending record, and SAVE_BATTLE copies it to the save
check(sess.pendingRecordedBattle ~= nil, "the finished battle leaves a pending recorded battle")
local recorded = sess.pendingRecordedBattle
local recordedTurns = 0
for _ in pairs(recorded and recorded.turns or {}) do recordedTurns = recordedTurns + 1 end
check(recordedTurns >= 1, "the recording stores at least one turn checkpoint")
local recordedState = Battle.getState()
local recordedTurn = recordedState and recordedState.turn

local saveCtx = { specialVars = {} }
NF.FUNCS[Util.FUNC.SAVE_BATTLE](saveCtx, adapters, sess)
eq(Rse.specialVar(saveCtx, Util.VAR_RESULT), 1, "SAVE_BATTLE sets VAR_RESULT 1 with a pending record")
check(RB.canCopy(sess), "the saved recorded battle can be copied")

-- snapshot what a replay must not change
local function snapshot()
  return Serializer.encode({ party = sess.party, money = sess.money, frontier = sess.frontier })
end
local before = snapshot()

-- replay the saved record headlessly through RB.play
local calls, replayResult, replayTurn = 0, nil, nil
RB.play(sess, function(result)
  calls = calls + 1
  replayResult = result
  local st = Battle.getState and Battle.getState()
  replayTurn = st and st.turn
end)
local replayGuard = 0
while calls == 0 and replayGuard < 20000 do
  replayGuard = replayGuard + 1
  Battle.update(1 / 60, nil)
  Battle.update(0, nil)
end
eq(calls, 1, "RB.play calls onDone exactly once")
eq(replayResult, recorded.result, "the replayed result matches the recording")
eq(replayTurn, recordedTurn, "the replay ends on the same turn as the recording")
eq(snapshot(), before, "a replay leaves the party, money and frontier state unchanged")

Runtime.getSession = prevGet
T.finish("emerald_recorded_battle_e2e_test")
