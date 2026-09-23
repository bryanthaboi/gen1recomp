#!/usr/bin/env luajit
-- pokefirered/src/trainer_tower.c:438 CallTrainerTowerFunc

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local Ctx = require("src.core.game3.scripting.ctx")
local Flags = require("src.core.game3.scripting.flags")
local Std = require("src.core.game3.scripting.stdscripts")
local Natives = require("src.core.game3.scripting.natives")
local Ops = require("src.core.game3.scripting.ops_a")
local Bag = require("src.core.game3.bag")
local Task = require("src.core.game3.task")
local Tower = require("src.core.game3.trainer_tower")
local TowerNatives = require("src.core.game3.scripting.natives_tower")
local Cache = require("tests.game3_cache")

-- pokefirered/src/trainer_tower_sets.c:8956 gTrainerTowerFloors is cache data
Cache.mount("meta.json")
local romBundle = Cache.bundle()
if not romBundle then
  package.loaded["src.core.game3.rom_text"] = {
    plain = function(key) return key end, box = function(key) return key end,
    ascii = function(key) return key end, has = function() return true end,
    ir = function(key) return { { t = "text", s = key } } end,
    key = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
    at = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
    count = function() return 0 end, list = function() return {} end,
    lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
  }
end
Tower.resetPack()
local havePack = Tower.floors(Tower.CHALLENGE_TYPE.SINGLE) ~= nil
if not havePack then
  print("[skip] the floor-set checks: " .. tostring(Cache.reason or "no trainer_tower.lua in cache"))
end

local store = Flags.newStore()
package.loaded["src.core.game3.scripting.space"] = { store = store, ensureBundle = function() return romBundle end }

local adapters = { log = function() end }

local function newCtx()
  local ctx = Ctx.new({})
  ctx.mode = "bytecode"
  ctx.status = "running"
  return ctx
end

local function useSession(tbl)
  package.loaded["src.core.game3.runtime"] = {
    getSession = function() return tbl end,
    isActive = function() return true end,
  }
  return tbl
end

local function newSession(map)
  return useSession({
    name = "RED",
    gender = 0,
    money = 3000,
    trainerId = 4242,
    party = {},
    bag = Bag.new(),
    map = map or "FR_TRAINER_TOWER_LOBBY",
    x = 9,
    y = 7,
    modData = {},
  })
end

local function getVar(ctx, id) return Flags.getVar(store, ctx, id) end
local function setVar(ctx, id, v) Flags.setVar(store, ctx, id, v) end

-- pokefirered/asm/macros/trainer_tower.inc:2
local function towerFunc(ctx, index, arg5, arg6)
  setVar(ctx, 0x8004, index)
  if arg5 ~= nil then setVar(ctx, 0x8005, arg5) end
  if arg6 ~= nil then setVar(ctx, 0x8006, arg6) end
  Ops.dispatch({ ctx = ctx, store = store, adapters = adapters, setPc = function() end },
    { op = "special", id = Std.SPECIAL.CallTrainerTowerFunc })
  return getVar(ctx, 0x800D)
end

print("[test] 1. special 0x194 is bound and every gTrainerTowerFuncs index is reachable")
eq(Std.SPECIAL.CallTrainerTowerFunc, 0x194, "CallTrainerTowerFunc special id")
check(Natives.ALLOW["special:" .. Std.SPECIAL.CallTrainerTowerFunc] ~= nil,
  "natives.lua discovered natives_tower and bound special 404")
local session = newSession("FR_TRAINER_TOWER_1F")
local ctx = newCtx()
TowerNatives._logged = {}
for index = 0, Tower.FUNC_COUNT - 1 do
  local ok, err = pcall(towerFunc, ctx, index)
  check(ok, "gTrainerTowerFuncs[" .. index .. "] ran (" .. tostring(err) .. ")")
end
local outOfRange = "CallTrainerTowerFunc index out of range: "
local logged = 0
for msg in pairs(TowerNatives._logged) do
  if msg:sub(1, #outOfRange) == outOfRange then logged = logged + 1 end
end
eq(logged, 0, "no index in 0..20 fell through the dispatcher")
towerFunc(ctx, Tower.FUNC_COUNT)
check(TowerNatives._logged[outOfRange .. Tower.FUNC_COUNT] == true,
  "index 21 is out of range and is logged, so the sweep above proves reachability")

print("[test] 2. StartTrainerTowerChallenge picks the mode and clamps it")
session = newSession("FR_TRAINER_TOWER_LOBBY")
ctx = newCtx()
-- pokefirered/data/maps/TrainerTower_Lobby/scripts.inc:187
towerFunc(ctx, Tower.FUNC.START_CHALLENGE, Tower.CHALLENGE_TYPE.KNOCKOUT)
eq(Tower.getChallengeId(session), Tower.CHALLENGE_TYPE.KNOCKOUT, "mode is KNOCKOUT")
towerFunc(ctx, Tower.FUNC.START_CHALLENGE, Tower.NUM_CHALLENGE_TYPES)
eq(Tower.getChallengeId(session), Tower.CHALLENGE_TYPE.SINGLE,
  "an out of range mode clamps to SINGLE (pokefirered/src/trainer_tower.c:772)")

print("[test] 3. the timer starts, runs on the engine task and stops")
session = newSession("FR_TRAINER_TOWER_LOBBY")
ctx = newCtx()
Task.clear()
towerFunc(ctx, Tower.FUNC.START_CHALLENGE, Tower.CHALLENGE_TYPE.SINGLE)
check(Tower.isTimerRunning(session), "START_CHALLENGE started the clock")
eq(Tower.record(session).timer, 0, "START_CHALLENGE zeroed the clock")
for _ = 1, 45 do Task.update(1 / 60) end
eq(Tower.record(session).timer, 45, "45 engine frames = 45 tower frames")
-- pokefirered/src/trainer_tower.c:788
towerFunc(ctx, Tower.FUNC.GET_OWNER_STATE)
check(not Tower.isTimerRunning(session), "GetOwnerState disabled the counter")
for _ = 1, 30 do Task.update(1 / 60) end
eq(Tower.record(session).timer, 45, "a stopped clock does not advance")
-- pokefirered/src/trainer_tower.c:840
towerFunc(ctx, Tower.FUNC.RESUME_TIMER)
check(not Tower.isTimerRunning(session),
  "ResumeTimer stays stopped once the owner has been spoken to")

print("[test] 4. the timer clamps at TRAINER_TOWER_MAX_TIME and formats like pret")
session = newSession("FR_TRAINER_TOWER_ROOF")
ctx = newCtx()
Task.clear()
towerFunc(ctx, Tower.FUNC.START_CHALLENGE, Tower.CHALLENGE_TYPE.SINGLE)
Tower.record(session).timer = Tower.MAX_TIME + 500
towerFunc(ctx, Tower.FUNC.GET_TIME)
eq(Tower.record(session).timer, Tower.MAX_TIME, "GetCurrentTime clamped the clock")
check(not Tower.isTimerRunning(session), "GetCurrentTime stopped the counter at the ceiling")
eq(ctx.stringVars[1], "59", "gStringVar1 minutes at the ceiling")
eq(ctx.stringVars[2], "59", "gStringVar2 seconds at the ceiling")
eq(ctx.stringVars[3], "99", "gStringVar3 hundredths at the ceiling")
local m, s, c = Tower.formatTime(3661)
eq(m, " 1", "1 minute right aligned")
eq(s, " 1", "1 second right aligned")
eq(c, "01", "1 frame is 01 hundredths (1 * 168 / 100)")

print("[test] 5. the floor counter advances and the floor index clamps to the roof")
session = newSession("FR_TRAINER_TOWER_1F")
ctx = newCtx()
Task.clear()
towerFunc(ctx, Tower.FUNC.START_CHALLENGE, Tower.CHALLENGE_TYPE.SINGLE)
eq(Tower.record(session).floorsCleared, 0, "a fresh run has cleared no floors")
-- pokefirered/data/scripts/trainer_tower.inc:80
eq(towerFunc(ctx, Tower.FUNC.GET_FLOOR_CLEARED), 0, "1F is not cleared yet")
towerFunc(ctx, Tower.FUNC.CLEARED_FLOOR)
eq(Tower.record(session).floorsCleared, 1, "clearing 1F advanced the counter")
eq(towerFunc(ctx, Tower.FUNC.GET_FLOOR_CLEARED), 1, "1F now reports cleared")
session.map = "FR_TRAINER_TOWER_2F"
eq(towerFunc(ctx, Tower.FUNC.GET_FLOOR_CLEARED), 0, "2F is the next uncleared floor")
for i = 0, Tower.MAX_FLOORS - 1 do
  eq(Tower.floorIndexForMap("FR_TRAINER_TOWER_" .. (i + 1) .. "F"), i,
    "floor index of " .. (i + 1) .. "F")
end
check(Tower.floor(Tower.CHALLENGE_TYPE.SINGLE, Tower.MAX_FLOORS) == nil,
  "there is no floor past 8F")
check(not Tower.isPastFinalFloor("FR_TRAINER_TOWER_8F"), "8F is inside the tower")
check(Tower.isPastFinalFloor("FR_TRAINER_TOWER_ROOF"),
  "the roof is past the last floor (pokefirered/src/trainer_tower.c:546)")
session.map = "FR_TRAINER_TOWER_ROOF"
eq(towerFunc(ctx, Tower.FUNC.INIT_FLOOR), 3,
  "InitTrainerTowerFloor on the roof returns 3 and skips the challenge types")

print("[test] 6. the lobby queries")
session = newSession("FR_TRAINER_TOWER_LOBBY")
ctx = newCtx()
Task.clear()
-- pokefirered/data/maps/TrainerTower_Lobby/scripts.inc:148
eq(towerFunc(ctx, Tower.FUNC.GET_NUM_FLOORS), 0,
  "GetNumFloors is FALSE for the built in floor set")
-- pokefirered/data/scripts/trainer_tower.inc:90
eq(towerFunc(ctx, Tower.FUNC.SHOULD_WARP_TO_COUNTER), 0, "ShouldWarpToCounter is dummied to FALSE")
-- pokefirered/data/maps/TrainerTower_Lobby/scripts.inc:106
eq(towerFunc(ctx, Tower.FUNC.GET_BEAT_CHALLENGE), 0, "the owner has not been spoken to")
towerFunc(ctx, Tower.FUNC.START_CHALLENGE, Tower.CHALLENGE_TYPE.SINGLE)
-- pokefirered/src/trainer_tower.c:856
eq(towerFunc(ctx, Tower.FUNC.GET_CHALLENGE_STATUS), Tower.CHALLENGE_STATUS.NORMAL,
  "an ongoing run reports CHALLENGE_STATUS_NORMAL")
towerFunc(ctx, Tower.FUNC.SET_LOST)
eq(towerFunc(ctx, Tower.FUNC.GET_CHALLENGE_STATUS), Tower.CHALLENGE_STATUS.LOST,
  "after SetPlayerLost the lobby reports CHALLENGE_STATUS_LOST")
eq(towerFunc(ctx, Tower.FUNC.GET_CHALLENGE_STATUS), Tower.CHALLENGE_STATUS.NORMAL,
  "the lost flag is consumed once")
local Party = require("src.core.game3.party")
-- pokefirered/include/constants/pokemon.h:197
eq(towerFunc(ctx, Tower.FUNC.CHECK_DOUBLES), Party.PLAYER_HAS_ONE_MON,
  "an empty party is not eligible for a double battle")
session.party = {
  { species = 1, hp = 20, level = 10 },
  { species = 4, hp = 18, level = 10 },
}
eq(towerFunc(ctx, Tower.FUNC.CHECK_DOUBLES), Party.PLAYER_HAS_TWO_USABLE_MONS,
  "two healthy mons clear the double battle trigger")
session.party = {}

print("[test] 7. the owner ladder, the prize and the record time")
session = newSession("FR_TRAINER_TOWER_ROOF")
ctx = newCtx()
Task.clear()
towerFunc(ctx, Tower.FUNC.START_CHALLENGE, Tower.CHALLENGE_TYPE.SINGLE)
for _ = 1, 120 do Task.update(1 / 60) end
-- pokefirered/data/scripts/trainer_tower.inc:268
eq(towerFunc(ctx, Tower.FUNC.GET_OWNER_STATE), 0, "the owner has not been met")
eq(towerFunc(ctx, Tower.FUNC.GET_OWNER_STATE), 1, "the second visit offers the prize")
-- pokefirered/src/trainer_tower.c:801
if havePack then
  local prize = Tower.prizeItem(session, Tower.CHALLENGE_TYPE.SINGLE)
  eq(towerFunc(ctx, Tower.FUNC.GIVE_PRIZE), 0, "the prize is handed over")
  eq(Bag.has(session.bag, prize, 1), true, "the SINGLE prize item reached the bag")
  eq(towerFunc(ctx, Tower.FUNC.GIVE_PRIZE), 2, "the prize is only given once")
else
  -- pokefirered/src/trainer_tower.c:805 AddBagItem of a prize the cache does not name
  eq(towerFunc(ctx, Tower.FUNC.GIVE_PRIZE), 1, "with no floor set the prize is refused")
end
-- pokefirered/src/trainer_tower.c:825
eq(towerFunc(ctx, Tower.FUNC.CHECK_FINAL_TIME), 0, "120 frames beats the empty record")
eq(Tower.record(session).bestTime, 120, "the record time was written")
eq(towerFunc(ctx, Tower.FUNC.CHECK_FINAL_TIME), 2, "the final time is only checked once")
if havePack then
  eq(towerFunc(ctx, Tower.FUNC.GET_OWNER_STATE), 2, "the owner is done with the player")
end

print("[test] 8. the prize differs per mode, as floors[0].prize does")
if havePack then
  local seen, distinct = {}, 0
  for mode = 0, Tower.NUM_CHALLENGE_TYPES - 1 do
    -- pokefirered/src/trainer_tower.c:801 sPrizeList[floors[0].prize]
    local item = Tower.prizeItem(session, mode)
    eq(item, Tower.PRIZE_ITEMS[Tower.floors(mode)[1].prize], "mode " .. mode .. " prize item")
    if item and not seen[item] then
      seen[item] = true
      distinct = distinct + 1
    end
  end
  check(distinct > 1, "the prize is per mode, not one item for the whole tower")
  eq(Tower.prizeItem(session, Tower.CHALLENGE_TYPE.SINGLE),
    Tower.prizeItem(session, Tower.CHALLENGE_TYPE.SINGLE + Tower.NUM_CHALLENGE_TYPES),
    "an out of range mode clamps to SINGLE's prize")
end

print("[test] 9. the mixed challenge mixes challenge types per floor")
if havePack then
  local kinds = {}
  -- pokefirered/include/constants/trainer_tower.h:8 mixed uses one of the other 3 per floor
  for _, row in ipairs(Tower.floors(Tower.CHALLENGE_TYPE.MIXED)) do
    kinds[row.challengeType] = true
  end
  local n = 0
  for _ in pairs(kinds) do n = n + 1 end
  check(n > 1, "MIXED carries more than one challenge type across its floors")
  check(kinds[Tower.CHALLENGE_TYPE.MIXED] == nil, "and never MIXED itself")
  for mode = 0, Tower.NUM_CHALLENGE_TYPES - 2 do
    for _, row in ipairs(Tower.floors(mode)) do
      eq(row.challengeType, mode, "mode " .. mode .. " is that type on every floor")
    end
  end
  for mode = 0, Tower.NUM_CHALLENGE_TYPES - 1 do
    local floors = Tower.floors(mode)
    eq(#floors, Tower.MAX_FLOORS, "mode " .. mode .. " has 8 floors")
    for i = 1, Tower.MAX_FLOORS do
      eq(floors[i].floorIdx, Tower.MAX_FLOORS, "mode " .. mode .. " floor " .. i .. " floorIdx")
    end
  end
end

print("[test] 10. sFloorLayouts maps floor and challenge type to a layout id")
-- pokefirered/src/trainer_tower.c:353
eq(Tower.floorLayoutFor(0, Tower.CHALLENGE_TYPE.SINGLE), 298, "1F singles layout")
eq(Tower.floorLayoutFor(0, Tower.CHALLENGE_TYPE.DOUBLE), 366, "1F doubles layout")
eq(Tower.floorLayoutFor(7, Tower.CHALLENGE_TYPE.KNOCKOUT), 381, "8F knockout layout")

print("[test] 11. the tower state survives a save and reload")
session = newSession("FR_TRAINER_TOWER_5F")
ctx = newCtx()
Task.clear()
towerFunc(ctx, Tower.FUNC.START_CHALLENGE, Tower.CHALLENGE_TYPE.DOUBLE)
for _ = 1, 600 do Task.update(1 / 60) end
towerFunc(ctx, Tower.FUNC.CLEARED_FLOOR)
towerFunc(ctx, Tower.FUNC.CLEARED_FLOOR)
local Schema = require("src.core.game3.save_schema_firered")
local saved = Schema.toSaveTable(session)
local reloaded = useSession(Schema.fromSaveTable(saved))
eq(Tower.getChallengeId(reloaded), Tower.CHALLENGE_TYPE.DOUBLE, "the mode survived the save")
eq(Tower.record(reloaded).timer, 600, "the clock survived the save")
eq(Tower.record(reloaded).floorsCleared, 2, "the floors cleared survived the save")
ctx = newCtx()
towerFunc(ctx, Tower.FUNC.RESUME_TIMER)
check(Tower.isTimerRunning(reloaded), "OnResume restarts the clock after a reload")
for _ = 1, 60 do Task.update(1 / 60) end
eq(Tower.record(reloaded).timer, 660, "the reloaded clock keeps counting")
Task.clear()

print("[test] 12. the battle runs through the host and the unused results board opens")
session = newSession("FR_TRAINER_TOWER_1F")
ctx = newCtx()
Task.clear()
Tower.setPack(nil)
TowerNatives._logged = {}
session.party = { { species = 1, hp = 20, level = 20 } }
towerFunc(ctx, Tower.FUNC.START_CHALLENGE, Tower.CHALLENGE_TYPE.SINGLE)
-- pokefirered/include/constants/battle.h:76
eq(towerFunc(ctx, Tower.FUNC.DO_BATTLE), 2,
  "with no floor trainers in the cache DoTrainerTowerBattle reports B_OUTCOME_LOST")
eq(Tower.record(session).floorsCleared, 0, "a lost battle cleared no floor")
eq(Tower.record(session).bestTime, Tower.MAX_TIME, "a lost battle wrote no record")
check(TowerNatives._logged["DoTrainerTowerBattle has no floor trainers in this cache"] == true,
  "the missing gTrainerTowerFloors table is what stopped the battle")
session.party = {}
local Screen = require("src.ui.game3.trainer_tower_records")
-- pokefirered/asm/macros/trainer_tower.inc:96 ttower_showresults
towerFunc(ctx, Tower.FUNC.SHOW_RESULTS)
check(Screen.isOpen(), "ShowResultsBoard opened the results board")
eq(getVar(ctx, 0x4001), Screen.BOARD_WINDOW_ID,
  "the board window id is in VAR_TEMP_1 (pokefirered/src/trainer_tower.c:921)")
eq(Screen.kind(), "board", "the unused board is not the full screen records scene")
towerFunc(ctx, Tower.FUNC.CLOSE_RESULTS)
check(not Screen.isOpen(),
  "CloseResultsBoard read VAR_TEMP_1 back and closed it (pokefirered/src/trainer_tower.c:926)")
Task.clear()

print("[test] 13. pokefirered/src/trainer_tower.c:960 the encounter song leaves the floor song alone")
do
  local realAudio = package.loaded["src.core.game3.audio"]
  local calls = {}
  local stubAudio = {
    _mapSong = 300,
    playSong = function(id) calls[#calls + 1] = { "playSong", id } end,
  }
  stubAudio.playMapSong = function(id)
    calls[#calls + 1] = { "playMapSong", id }
    stubAudio._mapSong = id
  end
  package.loaded["src.core.game3.audio"] = stubAudio
  towerFunc(ctx, Tower.FUNC.ENCOUNTER_MUSIC)
  package.loaded["src.core.game3.audio"] = realAudio
  eq(calls[1] and calls[1][1], "playSong", "PlayNewMapMusic goes through Audio.playSong")
  eq(calls[1] and calls[1][2], Tower.MUS_ENCOUNTER_BOY, "with no floor trainers it plays MUS_ENCOUNTER_BOY")
  eq(stubAudio._mapSong, 300, "the location song BattleBridge restores after the battle is untouched")
end

if failed > 0 then
  print(string.format("[FAIL] %d check(s) failed", failed))
  os.exit(1)
end
print("[pass] trainer tower state")
