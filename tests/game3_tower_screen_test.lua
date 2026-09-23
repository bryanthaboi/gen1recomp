#!/usr/bin/env luajit
-- pokefirered/src/battle_records.c:83, src/trainer_tower.c:899, :1054

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
local Natives = require("src.core.game3.scripting.natives")
local Ops = require("src.core.game3.scripting.ops_a")
local Bag = require("src.core.game3.bag")
local Task = require("src.core.game3.task")
local Stack = require("src.ui.game3.stack")
local Fade = require("src.ui.game3.fade")
local Tower = require("src.core.game3.trainer_tower")
local Screen = require("src.ui.game3.trainer_tower_records")

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

local function newSession()
  return useSession({
    name = "RED",
    gender = 0,
    trainerId = 4242,
    party = {},
    bag = Bag.new(),
    map = "FR_TRAINER_TOWER_LOBBY",
    modData = {},
  })
end

local function setVar(ctx, id, v) Flags.setVar(store, ctx, id, v) end

local function dispatch(ctx, row)
  return Ops.dispatch({ ctx = ctx, store = store, adapters = adapters, setPc = function() end }, row)
end

-- pokefirered/asm/macros/trainer_tower.inc:46 ttower_startchallenge
local function startChallenge(ctx, mode)
  setVar(ctx, 0x8004, Tower.FUNC.START_CHALLENGE)
  setVar(ctx, 0x8005, mode)
  dispatch(ctx, { op = "special", id = Std.SPECIAL.CallTrainerTowerFunc })
end

local function tick(n, input)
  for _ = 1, (n or 1) do
    Fade.tick(1 / 60)
    Task.update(1 / 60)
    if Screen.isOpen() then
      Screen.update(1 / 60)
      if input then Screen.handleInput(input) end
    end
  end
end

local function press(key)
  return {
    wasPressed = function(_, k) return k == key end,
    isDown = function() return false end,
  }
end

-- pokefirered/data/maps/TrainerTower_Lobby/scripts.inc:209 fadescreen FADE_TO_BLACK
local function coverScreen()
  Fade.begin(Fade.MODE.TO_BLACK, 1, function() end)
  for _ = 1, 40 do Fade.tick(1 / 60) end
  return (not Fade.isActive()) and Fade.t == 16
end

print("[test] 1. ShowBattleRecords is bound with pret's special id")
eq(Std.SPECIAL.ShowBattleRecords, 0xC4, "ShowBattleRecords is special 196")
check(Natives.ALLOW["special:" .. Std.SPECIAL.ShowBattleRecords] ~= nil,
  "special 0xC4 reaches a handler instead of the unknown-special log")

print("[test] 2. the lobby board takes the script's black screen back")
local session = newSession()
local ctx = newCtx()
Stack.clear()
Task.clear()
Fade.clear()
check(coverScreen(), "the script's fadescreen FADE_TO_BLACK covered the screen")
eq(Fade.mode, Fade.MODE.TO_BLACK, "and it is a black cover, not a white one")
-- pokefirered/data/maps/TrainerTower_Lobby/scripts.inc:210
setVar(ctx, 0x8004, 1)
local yielded = dispatch(ctx, { op = "special", id = Std.SPECIAL.ShowBattleRecords })
check(yielded, "the special yielded the script the way waitstate expects")
dispatch(ctx, { op = "waitstate" })
check(Screen.isOpen(), "the records screen is up")
eq(Screen.kind(), "tower", "VAR_0x8004 = 1 selects the trainer tower records")
-- pokefirered/src/battle_records.c:130 BeginNormalPaletteFade(PALETTES_ALL, 0, 16, 0)
eq(Fade.mode, Fade.MODE.FROM_BLACK, "the screen is fading back in, not sitting black")
tick(40)
eq(Fade.t, 0, "the black is gone once the fade in finishes")
check(not ctx.nativePoll(), "the script is still blocked on waitstate")

print("[test] 3. the board lists the four challenge types and their best times")
local rows = Screen.rows()
eq(#rows, Tower.NUM_CHALLENGE_TYPES, "one row per challenge type")
local labels = {}
for i, row in ipairs(rows) do labels[i] = row.label end
teq(table.concat(labels, "/"), "SINGLE/DOUBLE/KNOCKOUT/MIXED",
  "pokefirered/src/battle_message.c:1364 gTrainerTowerChallengeTypeTexts")
for i, row in ipairs(rows) do
  teq(row.time, "59MIN. 59.99SEC.", "row " .. i .. " of an untouched save is the ceiling time")
end

print("[test] 4. A closes the screen and hands the field back lit")
local input = press("a")
tick(1, input)
check(Screen.isOpen(), "the close fade is still running")
eq(Fade.mode, Fade.MODE.TO_BLACK, "pokefirered/src/battle_records.c:179 Task_FadeOut")
tick(60, input)
check(not Screen.isOpen(), "the screen closed")
check(not Stack.busy(), "and left no layer behind")
check(ctx.nativePoll(), "waitstate released the script")
tick(40)
eq(Fade.t, 0, "the field is lit again, not the black screen of the stitch round repro")
check(not Fade.isActive(), "and nothing is still fading")

print("[test] 5. B closes it the same way")
Fade.clear()
ctx = newCtx()
setVar(ctx, 0x8004, 1)
dispatch(ctx, { op = "special", id = Std.SPECIAL.ShowBattleRecords })
dispatch(ctx, { op = "waitstate" })
tick(40)
check(Screen.isOpen(), "the screen is up")
tick(80, press("b"))
check(not Screen.isOpen(), "B closed it (pokefirered/src/battle_records.c:174)")
check(ctx.nativePoll(), "and released the script")
tick(40)
eq(Fade.t, 0, "with the screen handed back lit")

print("[test] 6. a beaten mode shows its own record, the others the ceiling")
session = newSession()
Task.clear()
Tower.setBestTime(session, 3661, Tower.CHALLENGE_TYPE.KNOCKOUT)
ctx = newCtx()
Fade.clear()
setVar(ctx, 0x8004, 1)
dispatch(ctx, { op = "special", id = Std.SPECIAL.ShowBattleRecords })
dispatch(ctx, { op = "waitstate" })
rows = Screen.rows()
teq(rows[3].time, " 1MIN.  1.01SEC.", "the KNOCKOUT row shows the stored record")
teq(rows[1].time, "59MIN. 59.99SEC.", "the SINGLE row is still unbeaten")
tick(80, press("a"))
tick(40)
check(not Screen.isOpen(), "the screen closed again")

print("[test] 7. VAR_0x8004 = 0 is the cable club's link battle record screen")
-- pokefirered/data/scripts/cable_club.inc:569
session = newSession()
session.linkBattleWins = 12
session.linkBattleLosses = 3
session.linkBattleDraws = 1
session.linkBattleRecords = { { name = "BLUE", wins = 7, losses = 2, draws = 1 } }
ctx = newCtx()
Fade.clear()
check(coverScreen(), "the cable club script covered the screen too")
setVar(ctx, 0x8004, 0)
dispatch(ctx, { op = "special", id = Std.SPECIAL.ShowBattleRecords })
dispatch(ctx, { op = "waitstate" })
eq(Screen.kind(), "link", "VAR_0x8004 = 0 selects the link battle records")
rows = Screen.rows()
eq(#rows, Screen.LINK_ROWS, "five opponent rows (pokefirered/include/global.h:238)")
eq(rows[1].name, "BLUE", "the recorded opponent is listed")
eq(rows[1].wins, "   7", "with the wins right aligned in four")
teq(rows[2].name, "-------", "an empty slot is dashes (pokefirered/src/strings.c:599)")
teq(rows[2].draws, "----", "and so are its columns")
teq(Screen.totalText(session), "TOTAL RECORD W:12   L:3    D:1   ",
  "pokefirered/src/strings.c:597 left aligns each count in four")
tick(80, press("a"))
tick(40)
eq(Fade.t, 0, "the cable club tile no longer leaves a black screen")
check(not Screen.isOpen(), "and the screen closed")

print("[test] 8. the unused in-field board keeps its cart quirks")
session = newSession()
Task.clear()
Fade.clear()
Stack.clear()
ctx = newCtx()
startChallenge(ctx, Tower.CHALLENGE_TYPE.DOUBLE)
Tower.setBestTime(session, 600, Tower.CHALLENGE_TYPE.DOUBLE)
Tower.setBestTime(session, 60, Tower.CHALLENGE_TYPE.SINGLE)
Screen.show({ session = session, kind = "board" })
rows = Screen.rows()
-- pokefirered/src/trainer_tower.c:912 GetTrainerTowerRecordTime(&TRAINER_TOWER.bestTime)
for i, row in ipairs(rows) do
  teq(row.time, " 0MIN. 10.00SEC.", "board row " .. i .. " shows the current mode's record")
end
-- pokefirered/src/trainer_tower.c:915 indexes the label table at i - 1
eq(rows[1].label, "", "the first board row has no label on the cart")
teq(rows[2].label, "SINGLE", "and the rest are shifted by one")
teq(rows[4].label, "KNOCKOUT", "so MIXED is never shown")
eq(Fade.t, 0, "the board is a field window, so it never blacks the screen out")
Screen.close()
check(not Screen.isOpen(), "the board closed")
Stack.clear()
Task.clear()

if failed > 0 then
  print(string.format("[FAIL] %d check(s) failed", failed))
  os.exit(1)
end
print("[pass] trainer tower records screen")
