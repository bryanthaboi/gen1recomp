#!/usr/bin/env luajit
-- pokefirered/src/trainer_tower.c:838, :1044

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

local romBundle = require("tests.game3_cache").bundle()
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
local function teq(a, b, msg)
  if romBundle then eq(a, b, msg) else print("[skip] ROM text: " .. msg) end
end

local Ctx = require("src.core.game3.scripting.ctx")
local Flags = require("src.core.game3.scripting.flags")
local Std = require("src.core.game3.scripting.stdscripts")
local Ops = require("src.core.game3.scripting.ops_a")
local Bag = require("src.core.game3.bag")
local Task = require("src.core.game3.task")
local Stack = require("src.ui.game3.stack")
local Tower = require("src.core.game3.trainer_tower")

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
    trainerId = 4242,
    party = {},
    bag = Bag.new(),
    map = map or "FR_TRAINER_TOWER_LOBBY",
    modData = {},
  })
end

local function getVar(ctx, id) return Flags.getVar(store, ctx, id) end
local function setVar(ctx, id, v) Flags.setVar(store, ctx, id, v) end

-- pokefirered/asm/macros/trainer_tower.inc:2
local function towerFunc(ctx, index, arg5)
  setVar(ctx, 0x8004, index)
  if arg5 ~= nil then setVar(ctx, 0x8005, arg5) end
  Ops.dispatch({ ctx = ctx, store = store, adapters = adapters, setPc = function() end },
    { op = "special", id = Std.SPECIAL.CallTrainerTowerFunc })
  return getVar(ctx, 0x800D)
end

local function frames(n)
  for _ = 1, n do Task.update(1 / 60) end
end

print("[test] 1. the clock runs only between StartTrainerTowerChallenge and the owner")
local session = newSession("FR_TRAINER_TOWER_LOBBY")
local ctx = newCtx()
Task.clear()
Stack.clear()
eq(Tower.record(session).timer, 0, "a fresh save has no elapsed time")
frames(60)
eq(Tower.record(session).timer, 0, "the clock does not run before the challenge starts")
towerFunc(ctx, Tower.FUNC.START_CHALLENGE, Tower.CHALLENGE_TYPE.SINGLE)
frames(90)
eq(Tower.record(session).timer, 90, "90 field frames are 90 tower frames")
-- pokefirered/src/trainer_tower.c:788 DisableVBlankCounter1
towerFunc(ctx, Tower.FUNC.GET_OWNER_STATE)
frames(60)
eq(Tower.record(session).timer, 90, "speaking to the owner stops the clock for good")
towerFunc(ctx, Tower.FUNC.RESUME_TIMER)
frames(60)
eq(Tower.record(session).timer, 90, "ResumeTimer will not restart it after the owner")

print("[test] 2. the clock keeps running while a menu owns the screen")
-- pokefirered/src/main.c:390 gMain.vblankCounter1
session = newSession("FR_TRAINER_TOWER_3F")
ctx = newCtx()
Task.clear()
Stack.clear()
towerFunc(ctx, Tower.FUNC.START_CHALLENGE, Tower.CHALLENGE_TYPE.MIXED)
frames(30)
local Screen = require("src.ui.game3.trainer_tower_records")
Screen.show({ session = session, kind = "tower" })
check(Stack.busy(), "a full screen menu layer is up")
frames(45)
eq(Tower.record(session).timer, 75, "the clock advanced behind the open menu")
Screen.close()
frames(15)
eq(Tower.record(session).timer, 90, "and keeps advancing after it closes")
Stack.clear()

print("[test] 3. the clock stops itself at TRAINER_TOWER_MAX_TIME")
session = newSession("FR_TRAINER_TOWER_8F")
ctx = newCtx()
Task.clear()
towerFunc(ctx, Tower.FUNC.START_CHALLENGE, Tower.CHALLENGE_TYPE.SINGLE)
Tower.record(session).timer = Tower.MAX_TIME - 2
frames(10)
-- pokefirered/src/trainer_tower.c:892
towerFunc(ctx, Tower.FUNC.GET_TIME)
eq(Tower.record(session).timer, Tower.MAX_TIME, "GetCurrentTime clamps at the ceiling")
check(not Tower.isTimerRunning(session), "and disables the counter")
frames(30)
eq(Tower.record(session).timer, Tower.MAX_TIME, "a clamped clock does not creep past the ceiling")

print("[test] 4. the best time is only written when the run beat it")
session = newSession("FR_TRAINER_TOWER_ROOF")
ctx = newCtx()
Task.clear()
towerFunc(ctx, Tower.FUNC.START_CHALLENGE, Tower.CHALLENGE_TYPE.DOUBLE)
eq(Tower.bestTime(session), Tower.MAX_TIME, "an unplayed mode holds TRAINER_TOWER_MAX_TIME")
frames(1200)
-- pokefirered/src/trainer_tower.c:825
eq(towerFunc(ctx, Tower.FUNC.CHECK_FINAL_TIME), 0, "the first clear is a new record")
eq(Tower.bestTime(session), 1200, "and the record time was stored")
eq(towerFunc(ctx, Tower.FUNC.CHECK_FINAL_TIME), 2, "the same visit checks the time once")
towerFunc(ctx, Tower.FUNC.START_CHALLENGE, Tower.CHALLENGE_TYPE.DOUBLE)
eq(Tower.bestTime(session), 1200, "a new run keeps the old record")
frames(2000)
eq(towerFunc(ctx, Tower.FUNC.CHECK_FINAL_TIME), 1, "a slower run is not a record")
eq(Tower.bestTime(session), 1200, "and leaves the record alone")
towerFunc(ctx, Tower.FUNC.START_CHALLENGE, Tower.CHALLENGE_TYPE.DOUBLE)
frames(600)
eq(towerFunc(ctx, Tower.FUNC.CHECK_FINAL_TIME), 0, "a faster run is a new record")
eq(Tower.bestTime(session), 600, "and overwrites it")

print("[test] 5. each challenge type keeps its own record")
session = newSession("FR_TRAINER_TOWER_ROOF")
ctx = newCtx()
Task.clear()
local times = { [0] = 900, [1] = 1500, [2] = 2400, [3] = 3300 }
for mode = 0, Tower.NUM_CHALLENGE_TYPES - 1 do
  towerFunc(ctx, Tower.FUNC.START_CHALLENGE, mode)
  frames(times[mode])
  eq(towerFunc(ctx, Tower.FUNC.CHECK_FINAL_TIME), 0, "mode " .. mode .. " set a record")
end
for mode = 0, Tower.NUM_CHALLENGE_TYPES - 1 do
  eq(Tower.bestTime(session, mode), times[mode], "mode " .. mode .. " kept its own best time")
end

print("[test] 6. all four records round trip through a save and a reload")
local Schema = require("src.core.game3.save_schema_firered")
local saved = Schema.toSaveTable(session)
local reloaded = useSession(Schema.fromSaveTable(saved))
for mode = 0, Tower.NUM_CHALLENGE_TYPES - 1 do
  eq(Tower.bestTime(reloaded, mode), times[mode],
    "mode " .. mode .. " survived the save")
end
eq(Tower.getChallengeId(reloaded), Tower.CHALLENGE_TYPE.MIXED, "the last mode survived too")

print("[test] 7. a different floor set resets the record it no longer describes")
-- pokefirered/src/trainer_tower.c:1044 ValidateOrResetCurTrainerTowerRecord
session = newSession("FR_TRAINER_TOWER_LOBBY")
ctx = newCtx()
Task.clear()
towerFunc(ctx, Tower.FUNC.START_CHALLENGE, Tower.CHALLENGE_TYPE.KNOCKOUT)
Tower.setBestTime(session, 4242)
local rec = Tower.record(session)
rec.receivedPrize = true
eq(Tower.bestTime(session), 4242, "the record belongs to the built in set")
rec.setId = Tower.header().id + 1
Tower.validateRecord(session)
eq(Tower.bestTime(session), Tower.MAX_TIME, "a swapped floor set clears the record")
eq(Tower.record(session).receivedPrize, false, "and the prize can be won again")

print("[test] 8. the lobby prints the clock as minutes, seconds and hundredths")
session = newSession("FR_TRAINER_TOWER_1F")
ctx = newCtx()
Task.clear()
towerFunc(ctx, Tower.FUNC.START_CHALLENGE, Tower.CHALLENGE_TYPE.SINGLE)
frames(3661)
-- pokefirered/data/scripts/trainer_tower.inc:320 ttower_gettime
towerFunc(ctx, Tower.FUNC.GET_TIME)
eq(ctx.stringVars[1], " 1", "gStringVar1 is the minutes, right aligned in two")
eq(ctx.stringVars[2], " 1", "gStringVar2 is the seconds, right aligned in two")
eq(ctx.stringVars[3], "01", "gStringVar3 is frames * 168 / 100 with a leading zero")
teq(Screen.timeText(3661), " 1MIN.  1.01SEC.",
  "the board prints gText_XMinYZSec (pokefirered/src/battle_message.c:1354)")
teq(Screen.timeText(Tower.MAX_TIME), "59MIN. 59.99SEC.",
  "an unbeaten mode shows the ceiling time")

print("[test] 9. ResetTrainerTowerResults clears every mode")
-- pokefirered/src/trainer_tower.c:1087
session = newSession("FR_TRAINER_TOWER_LOBBY")
Task.clear()
for mode = 0, Tower.NUM_CHALLENGE_TYPES - 1 do
  Tower.setBestTime(session, 1000 + mode, mode)
end
Tower.resetResults(session)
for mode = 0, Tower.NUM_CHALLENGE_TYPES - 1 do
  eq(Tower.bestTime(session, mode), Tower.MAX_TIME, "mode " .. mode .. " was reset")
end
Task.clear()

if failed > 0 then
  print(string.format("[FAIL] %d check(s) failed", failed))
  os.exit(1)
end
print("[pass] trainer tower records")
