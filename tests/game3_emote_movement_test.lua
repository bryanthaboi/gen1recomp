-- Test suite for Game 3 Fanfare cues (Oak's Parcel / std:9) and Emote visual movement animations.

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local Movement = require("src.core.game3.scripting.movement")
local Objects = require("src.core.game3.objects")
local FieldEffects = require("src.core.game3.field_effects")
local Flags = require("src.core.game3.scripting.flags")
local Ctx = require("src.core.game3.scripting.ctx")
local Vm = require("src.core.game3.scripting.vm")
local Std = require("src.core.game3.scripting.stdscripts")
local Adapters = require("src.core.game3.scripting.adapters")
local Audio = require("src.core.game3.audio")

print("=== Game 3 Fanfare & Emote Parity Tests ===")

-- -----------------------------------------------------------------------------
-- 1. Movement bytecode decoding for Emotes (0x62 - 0x66)
-- -----------------------------------------------------------------------------
print("[test] 1. Movement.decodeAction for emote actions")
local a62 = Movement.decodeAction(0x62)
assert(a62.kind == "emote" and a62.emoteType == "exclamation" and a62.frames == 60, "0x62 decodes to exclamation emote with 60 frames")

local a63 = Movement.decodeAction(0x63)
assert(a63.kind == "emote" and a63.emoteType == "question" and a63.frames == 60, "0x63 decodes to question emote with 60 frames")

local a64 = Movement.decodeAction(0x64)
assert(a64.kind == "emote" and a64.emoteType == "x" and a64.frames == 60, "0x64 decodes to x emote with 60 frames")

local a65 = Movement.decodeAction(0x65)
assert(a65.kind == "emote" and a65.emoteType == "double_exclamation" and a65.frames == 60, "0x65 decodes to double exclamation emote with 60 frames")

local a66 = Movement.decodeAction(0x66)
assert(a66.kind == "emote" and a66.emoteType == "smile" and a66.frames == 60, "0x66 decodes to smile emote with 60 frames")

local actions = Movement.actionsFromBytes({ 0x62, 0xFE })
assert(#actions == 1 and actions[1].kind == "emote", "Common_Movement_ExclamationMark contains 1 emote action")
print("[ok] Movement decoding for emotes passed")

-- -----------------------------------------------------------------------------
-- 2. Objects.applyMovement with Emotes & 60-frame blocking (waitmovement)
-- -----------------------------------------------------------------------------
print("[test] 2. Objects.applyMovement with Emote action blocks for 60 frames")
local oakDef = {
  localId = 3,
  index = 3,
  x = 10,
  y = 12,
  graphicsId = 10,
  sprite = "SPRITE_PROF_OAK",
}
Objects.loadMap(nil, "PALLET_LAB", { objects = { oakDef } })
local oak = Objects.find(3)
assert(oak ~= nil, "Oak spawned")

FieldEffects._anims = {}
local doneCalled = false
Objects.applyMovement(3, { 0x62, 0xFE }, function()
  doneCalled = true
end)

assert(#FieldEffects._anims == 1, "FieldEffects animation spawned on emote movement")
local anim = FieldEffects._anims[1]
assert(anim.kind == "emote" and anim.targetObj == oak, "Emote targetObj is Oak")
assert(anim.baseFrame == 0, "Exclamation base frame is 0")
assert(Objects.pollMovement(3) == false, "Objects.pollMovement(3) is false while emote is playing")
assert(doneCalled == false, "onDone not called immediately")

-- Step 59 frames -> should still be active
for f = 1, 59 do
  Objects.update(nil)
  FieldEffects.step()
  assert(Objects.pollMovement(3) == false, "Movement still pending at frame " .. f)
  assert(doneCalled == false, "onDone not called at frame " .. f)
end

-- Step 60th frame -> movement finishes
Objects.update(nil)
FieldEffects.step()
assert(Objects.pollMovement(3) == true, "Movement reports finished after 60 frames")
assert(doneCalled == true, "onDone invoked after 60 frames")
print("[ok] Emote movement blocks for 60 frames exactly")

-- -----------------------------------------------------------------------------
-- 3. FieldEffects animation progression across emote types
-- -----------------------------------------------------------------------------
print("[test] 3. FieldEffects animation frames and baseFrame offsets")
local testCases = {
  { type = "exclamation", base = 0 },
  { type = "double_exclamation", base = 6 },
  { type = "x", base = 3 },
  { type = "smile", base = 9 },
  { type = "question", base = 12 },
}

for _, tc in ipairs(testCases) do
  FieldEffects._anims = {}
  local a = FieldEffects.startEmote(oak, tc.type)
  assert(a.baseFrame == tc.base, "Base frame matches for " .. tc.type)
  assert(a.frame == tc.base, "Initial frame is base frame")
  
  -- Frame 0..3: base
  FieldEffects.step() -- timer = 1
  assert(a.frame == tc.base, "Frame at t=1 is base")
  
  for _ = 2, 4 do FieldEffects.step() end -- timer = 4
  assert(a.frame == tc.base + 1, "Frame at t=4 is base+1")
  
  for _ = 5, 8 do FieldEffects.step() end -- timer = 8
  assert(a.frame == tc.base + 2, "Frame at t=8 is base+2")
  
  for _ = 9, 60 do FieldEffects.step() end -- timer = 60
  assert(#FieldEffects._anims == 0, "Emote cleaned up after 60 frames for " .. tc.type)
end
print("[ok] All emote types animate through frames and clean up")

-- -----------------------------------------------------------------------------
-- 4. std:9 (STD_RECEIVED_ITEM) fanfare playback and audio cues
-- -----------------------------------------------------------------------------
print("[test] 4. STD_RECEIVED_ITEM (std:9) plays correct fanfare and displays put-away message")

local lastFanfarePlayed = nil
local fanfarePlaying = false

local mockAudio = {
  playFanfare = function(id)
    lastFanfarePlayed = id
    fanfarePlaying = true
    return true
  end,
  isFanfareFinished = function()
    return not fanfarePlaying
  end,
  waitFanfare = function(cb)
    if not fanfarePlaying and cb then cb() end
  end,
}

local store = Flags.newStore()
local adapters = Adapters.host(nil, nil, nil)
adapters.playSe = function(id, isFanfare)
  if isFanfare then
    mockAudio.playFanfare(id)
  end
end
adapters.isFanfareFinished = function()
  return mockAudio.isFanfareFinished()
end
adapters.waitFanfare = function(cb)
  mockAudio.waitFanfare(cb)
end

local scripts = {}
for k, v in pairs(Std.SCRIPTS) do
  scripts[k] = v
end

-- Test 4A: Oak's Parcel (MUS_OBTAIN_KEY_ITEM = 318)
scripts.test_parcel = {
  { op = "setorcopyvar", [1] = 0x8000, [2] = 360 }, -- ITEM_OAKS_PARCEL
  { op = "setorcopyvar", [1] = 0x8001, [2] = 1 },
  { op = "setorcopyvar", [1] = 0x8002, [2] = 318 }, -- MUS_OBTAIN_KEY_ITEM
  { op = "loadword", dest = 0, value = "Test_Parcel_Text" },
  { op = "callstd", std = 9 },
  { op = "end" },
}

local vm = Vm.new({
  store = store,
  scripts = scripts,
  adapters = adapters,
})

lastFanfarePlayed = nil
fanfarePlaying = false
vm:start("test_parcel", 1)

assert(lastFanfarePlayed == 318, "Oak's Parcel triggered MUS_OBTAIN_KEY_ITEM (318) fanfare")
print("[ok] Oak's Parcel played key item fanfare (318)")

-- Test 4B: Standard Item (MUS_OBTAIN_ITEM = 258)
scripts.test_potion = {
  { op = "setorcopyvar", [1] = 0x8000, [2] = 13 }, -- ITEM_POTION
  { op = "setorcopyvar", [1] = 0x8001, [2] = 1 },
  { op = "setorcopyvar", [1] = 0x8002, [2] = 258 }, -- MUS_OBTAIN_ITEM
  { op = "loadword", dest = 0, value = "Test_Potion_Text" },
  { op = "callstd", std = 9 },
  { op = "end" },
}

lastFanfarePlayed = nil
fanfarePlaying = false
vm:start("test_potion", 1)
assert(lastFanfarePlayed == 258, "Potion triggered MUS_OBTAIN_ITEM (258) fanfare")
print("[ok] Standard item played obtain item fanfare (258)")

-- Test 4C: Level Up Fanfare (MUS_LEVEL_UP = 257)
scripts.test_levelup = {
  { op = "setorcopyvar", [1] = 0x8000, [2] = 1 },
  { op = "setorcopyvar", [1] = 0x8001, [2] = 1 },
  { op = "setorcopyvar", [1] = 0x8002, [2] = 257 }, -- MUS_LEVEL_UP
  { op = "loadword", dest = 0, value = "Test_LevelUp_Text" },
  { op = "callstd", std = 9 },
  { op = "end" },
}

lastFanfarePlayed = nil
fanfarePlaying = false
vm:start("test_levelup", 1)
assert(lastFanfarePlayed == 257, "Level up triggered MUS_LEVEL_UP (257) fanfare")
print("[ok] Level up fanfare (257) handled")

-- Test 4D: Dynamic/Variable Fanfare Fallback in playfanfare
scripts.test_var_fanfare = {
  { op = "setorcopyvar", [1] = 0x8000, [2] = 1 },
  { op = "setorcopyvar", [1] = 0x8001, [2] = 1 },
  { op = "setorcopyvar", [1] = 0x8002, [2] = 317 }, -- MUS_DEX_RATING
  { op = "loadword", dest = 0, value = "Test_Rating_Text" },
  { op = "callstd", std = 9 },
  { op = "end" },
}

lastFanfarePlayed = nil
fanfarePlaying = false
vm:start("test_var_fanfare", 1)
assert(lastFanfarePlayed == 317, "Dynamic fanfare variable resolved to 317")
print("[ok] Dynamic fanfare fallback resolved variable")

print("All Game 3 Fanfare & Emote Parity Tests passed successfully!")
