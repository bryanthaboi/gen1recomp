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
local src = cache and cache.read and cache:read("data/generated/gba/rse/frontier/manifest.lua")
if type(src) ~= "string" then
  print("[skip] emerald_recorded_battle_test: no Emerald cache with rse/frontier")
  os.exit(0)
end

require("src.import.gba.versions").select("emerald")
local Runtime = require("src.core.game3.runtime")
local store = { flags = {}, vars = {} }
require("src.core.game3.scripting.space").store = store

local sess = { version = "emerald", name = "MAY", trainerId = 0x1234, secretId = 0xBEEF, gender = "female",
  party = {}, bag = {}, flags = store.flags, vars = store.vars }
local prevGet = Runtime.getSession
Runtime.getSession = function() return sess end

local Rse = require("src.core.game3.rse.init")
local Util = require("src.core.game3.rse.frontier.util")
local D = require("src.core.game3.rse.frontier.trainers")
local NF = require("src.core.game3.scripting.natives_frontier")

Util.newGame(sess)
Rse.setVar("VAR_FRONTIER_FACILITY", D.FACILITY.PALACE, sess)
local f = Util.frontier(sess)
f.disableRecordBattle = 0

local ctx = { specialVars = {}, stringVars = { "", "", "" } }
ctx.specialVars[Util.VAR_0x8004] = Util.FUNC.SAVE_BATTLE
ctx.specialVars[Util.VAR_RESULT] = 0
NF.callUtil(ctx, nil)
eq(Rse.specialVar(ctx, Util.VAR_RESULT), 1, "frontier_savebattle returns TRUE (frontier_util.c:2175)")
eq(f.disableRecordBattle, 1, "frontier_savebattle disables a second record (frontier_util.c:2176)")
check(type(sess.recordedBattle) == "table", "the recorded battle block lands in the save")

local RB = Rse.system("recordedBattle")
check(RB ~= nil, "recordedBattle system is registered")
check(not RB.isValid(sess.recordedBattle), "a block with no battle flags is not a valid record (recorded_battle.c:296)")

local function hasField(list, name)
  for _, v in ipairs(list) do if v == name then return true end end
  return false
end
check(hasField(Util.SAVE_FIELDS, "recordedBattle"), "recordedBattle persists with the frontier save fields")

local BATTLE_TYPE_TRAINER, BATTLE_TYPE_PALACE = 0x8, 0x20000
local player = { { species = 260, level = 50 }, { species = 257, level = 50 }, { species = 254, level = 50 } }
local foe = { { species = 65, level = 50 } }
sess.frontierOpponentA = 12
RB.begin(sess, { battleFlags = BATTLE_TYPE_TRAINER + BATTLE_TYPE_PALACE, aiFlags = 7, rngSeed = 0xCAFE,
  playerParty = player, opponentParty = foe, opponentA = 12 })
player[1].species = 1
f.lvlMode = 1
f.disableRecordBattle = 0
ctx.specialVars[Util.VAR_RESULT] = 0
NF.callUtil(ctx, nil)
eq(Rse.specialVar(ctx, Util.VAR_RESULT), 1, "saving after a palace battle succeeds")
local rec = sess.recordedBattle
check(RB.isValid(rec), "a palace trainer battle is a valid record")
eq(rec.battleFlags, BATTLE_TYPE_TRAINER + BATTLE_TYPE_PALACE, "local battle flags are stored as-is (recorded_battle.c:378)")
eq(rec.playerParty[1].species, 260, "the player party is the battle-start snapshot (recorded_battle.c:625)")
eq(rec.opponentParty[1].species, 65, "the opponent party is stored")
eq(rec.rngSeed, 0xCAFE, "the battle rng seed is stored")
eq(rec.opponentA, 12, "gTrainerBattleOpponent_A is stored")
eq(rec.frontierFacility, D.FACILITY.PALACE, "the facility comes from VAR_FRONTIER_FACILITY")
eq(rec.lvlMode, 1, "lvlMode is stored")
eq(rec.aiScripts, 7, "AI flags are stored")
eq(rec.players[1].name, "MAY", "the player name is recorded for a local battle")
eq(rec.players[1].gender, 1, "the player gender is recorded")
eq(rec.players[1].trainerId, 0x1234 + 0xBEEF * 65536, "the full 32-bit OT id is recorded")
eq(#rec.battleRecord, 4, "one action stream per battler")

RB.begin(sess, { battleFlags = 0x2 + 0x4 + 0x8 })
RB.moveToSaveData(sess)
eq(sess.recordedBattle.battleFlags, 0x8 + 0x4 + 0x2000000 + 0x80000000,
  "a link master battle becomes RECORDED_LINK | RECORDED_IS_MASTER (recorded_battle.c:350)")
check(RB.isValid(sess.recordedBattle), "a recorded link battle is valid")

RB.begin(sess, { battleFlags = 0x8 + 0x80 })
RB.moveToSaveData(sess)
check(not RB.isValid(sess.recordedBattle), "a safari battle record is invalid (battle.h:93)")

Runtime.getSession = prevGet
GameVersion.set("firered")
T.finish("emerald_recorded_battle_test")
