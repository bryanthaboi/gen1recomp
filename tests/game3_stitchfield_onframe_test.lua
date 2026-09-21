#!/usr/bin/env luajit

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

local function done()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local Space = require("src.core.game3.scripting.space")

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] game3_stitchfield_onframe_test: " .. tostring(Cache.reason))
  done()
end
print("[info] FireRed cache at " .. cacheRoot)

local ExtractScripts = require("src.import.gba.extract_scripts")
Space.bundle = ExtractScripts.loadBundle(Cache.cache(), cacheRoot, { allowIncomplete = true })
check(Space.bundle ~= nil, "script bundle loads")

local ModRuntime = require("src.mods.Runtime")
local startedLog = {}
local bus = { listeners = { ["script.started"] = true } }
function bus:emit(name, payload)
  if name == "script.started" and payload and payload.key then
    startedLog[#startedLog + 1] = payload.key
  end
end
function bus:removeOwner() end
ModRuntime.install(bus, {
  call = function(_, _, vanilla, ...) return vanilla(...) end,
  removeOwner = function() end,
})

local Dataset = require("src.core.game3.dataset")
local Runtime = require("src.core.game3.runtime")
local Map = require("src.core.game3.map")
local Field = require("src.core.game3.field")
local Flags = require("src.core.game3.scripting.flags")

local game = { data = {} }
Dataset.hydrate(game)
local session = { map = "FR_PALLET_TOWN", x = 12, y = 20, facing = "down", flags = {}, vars = {} }
game.session = session
Runtime.start(nil, game, session, { reason = "new_game" })

local ICEFALL = "FR_FOUR_ISLAND_ICEFALL_CAVE_1F"
local SEAFOAM_B3F = "FR_SEAFOAM_ISLANDS_B3F"
local NEUTRAL = "FR_PALLET_TOWN"
local VAR_TEMP_1 = 0x4001

local mark = 0
local function since()
  local out = {}
  for i = mark + 1, #startedLog do out[#out + 1] = startedLog[i] end
  mark = #startedLog
  return out
end

local function frames(n)
  for _ = 1, n do Field.update(1 / 60) end
end

local function warpTo(mapId, x, y)
  Map.load(nil, game, mapId, { x = x, y = y, facing = "down" })
  frames(4)
end

local function var(id) return Flags.getVar(Space.store, Space.vm and Space.vm.ctx, id) end
local function setVar(id, v) Flags.setVar(Space.store, Space.vm and Space.vm.ctx, id, v) end

print("[test] 1. the two fall maps carry an ON_FRAME row keyed on VAR_TEMP_1")
local iceRows = Space.bundle.events[ICEFALL].mapScripts.onFrame
local seaRows = Space.bundle.events[SEAFOAM_B3F].mapScripts.onFrame
check(type(iceRows) == "table" and iceRows[1] and iceRows[1].var == VAR_TEMP_1
  and iceRows[1].value == 1,
  "Icefall Cave 1F ON_FRAME is VAR_TEMP_1 == 1, script="
  .. tostring(iceRows[1] and iceRows[1].script))
check(type(seaRows) == "table" and seaRows[1] and seaRows[1].var == VAR_TEMP_1
  and seaRows[1].value == 1,
  "Seafoam B3F ON_FRAME is VAR_TEMP_1 == 1, script="
  .. tostring(seaRows[1] and seaRows[1].script))
local ICE_SCRIPT = iceRows[1].script
local SEA_SCRIPT = seaRows[1].script

print("[test] 2. entering Icefall Cave 1F with VAR_TEMP_1 clear starts nothing")
warpTo(NEUTRAL, 12, 20)
warpTo(ICEFALL, 9, 21)
since()
check(var(VAR_TEMP_1) == 0, "VAR_TEMP_1 is 0 on entry, got " .. var(VAR_TEMP_1))
check(Space.vm:isRunning() == false, "no map script is running after the entry drain")
check(Field.locked == false, "the entry lock was released because no ON_FRAME claimed it")

print("[test] 3. standing still for a second does not spuriously fire it")
frames(60)
check(#since() == 0, "60 field frames, no script started")
check(Space._pendingOnFrame == false, "and the claim flag stayed cleared")

print("[test] 4. the ice per-step callback's VarSet is noticed on the very next frame")
-- pokefirered/src/field_tasks.c:243
setVar(VAR_TEMP_1, 1)
check(Space._pendingOnFrame == false, "nothing re-armed the claim flag")
frames(1)
local ran = since()
check(#ran == 1 and ran[1] == ICE_SCRIPT,
  "one frame later FallDownHole " .. tostring(ICE_SCRIPT) .. " started, got "
  .. tostring(ran[1]) .. " x" .. #ran)
check(Space.vm:isRunning() == true, "it is parked on its delay")
check(Field.locked == true, "its lockall took the field")

print("[test] 5. a locked field is not polled (pret ArePlayerFieldControlsLocked)")
Space.vm:halt(true)
warpTo(NEUTRAL, 12, 20)
warpTo(ICEFALL, 9, 21)
since()
check(var(VAR_TEMP_1) == 0, "temp vars cleared by the map load, got " .. var(VAR_TEMP_1))
Field.lock()
setVar(VAR_TEMP_1, 1)
frames(30)
check(#since() == 0, "30 frames under a field lock start nothing")
Field.unlock()
frames(1)
local ran5 = since()
check(#ran5 == 1 and ran5[1] == ICE_SCRIPT,
  "and the first unlocked frame starts it, got " .. tostring(ran5[1]))

print("[test] 6. Seafoam B3F catches the surf-arrival VarSet the same way")
-- pokefirered/src/field_effect.c:1285
Space.vm:halt(true)
Field.unlock()
warpTo(NEUTRAL, 12, 20)
warpTo(SEAFOAM_B3F, 20, 8)
since()
check(var(VAR_TEMP_1) == 0, "B3F entered with VAR_TEMP_1 clear, got " .. var(VAR_TEMP_1))
frames(120)
check(#since() == 0,
  "two seconds of frames, the length of the fall animation, start nothing")
setVar(VAR_TEMP_1, 1)
frames(1)
local ran6 = since()
check(ran6[1] == SEA_SCRIPT,
  "EnterByFalling " .. tostring(SEA_SCRIPT) .. " started, got " .. tostring(ran6[1]))

print("[test] 7. the row stops matching once the var moves, so the poll stays quiet")
if Space.vm:isRunning() then Space.vm:halt(true) end
Field.unlock()
setVar(VAR_TEMP_1, 0)
since()
frames(60)
check(#since() == 0, "VAR_TEMP_1 back to 0, 60 more frames start nothing")

print("[test] 8. the no-match poll allocates nothing")
warpTo(NEUTRAL, 12, 20)
warpTo(ICEFALL, 9, 21)
since()
check(var(VAR_TEMP_1) == 0, "back in the cave with the row unmatched")
for _ = 1, 20000 do Space.runOnFrame() end
collectgarbage("collect")
local before = collectgarbage("count")
for _ = 1, 20000 do Space.runOnFrame() end
local perPoll = (collectgarbage("count") - before) * 1024 / 20000
check(#since() == 0, "40000 polls started nothing")
check(perPoll < 1,
  "the unmatched poll allocates " .. string.format("%.4f", perPoll) .. " bytes per frame")

ModRuntime.reset()
done()
