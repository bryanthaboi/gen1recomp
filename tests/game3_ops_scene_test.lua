#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local Flags = require("src.core.game3.scripting.flags")
local Ctx = require("src.core.game3.scripting.ctx")
local Vm = require("src.core.game3.scripting.vm")
local Ops = require("src.core.game3.scripting.ops_a")
local Adapters = require("src.core.game3.scripting.adapters")
local Audio = require("src.core.game3.audio")
local Runtime = require("src.core.game3.runtime")
local Player = require("src.core.game3.player")
local Task = require("src.core.game3.task")
local Warp = require("src.core.game3.warp")
local LayoutNative = require("src.core.game3.layout_native")
local NativePack = require("src.import.gba.native_pack")
local Extract = require("src.import.gba.extract_island1")

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

local VAR_TEMP_1 = 0x4001
local VAR_0x8004 = 0x8004
-- pokefirered/include/constants/field_tasks.h:4
local STEP_CB_ICE = (Ctx.STEP_CB and Ctx.STEP_CB.ICE) or 4
local STEP_CB_ASH = (Ctx.STEP_CB and Ctx.STEP_CB.ASH) or 1

local function resetStepCb()
  if Ctx.resetStepCallback then Ctx.resetStepCallback() end
end

local function stepCb(mapId)
  if not Ctx.stepCallback then return nil end
  return Ctx.stepCallback(mapId)
end

local function ops(name, ...)
  if type(Ops[name]) ~= "function" then return nil end
  return Ops[name](...)
end

local function newVm(scripts, store)
  store = store or Flags.newStore()
  local vm = Vm.new({ store = store, scripts = scripts, adapters = Adapters.host(nil, nil, nil) })
  return vm, store
end

local function run(scripts, key, store)
  local vm, st = newVm(scripts, store)
  vm:start(key)
  return vm, st
end

print("[test] 1. playmoncry dispatches species and mode to the cry mixer")
-- pokefirered/src/scrcmd.c:2088
Audio.stopCry()
Audio._cryParams = nil
run({
  t = { { op = "playmoncry", [1] = 143, [2] = 2 }, { op = "end" } },
}, "t")
eq(Audio._cryParams and Audio._cryParams.mode, 2, "playmoncry SNORLAX, CRY_MODE_ENCOUNTER reaches the mixer as mode 2")

Audio.stopCry()
Audio._cryParams = nil
run({
  t = { { op = "playmoncry", [1] = 33, [2] = 0 }, { op = "end" } },
}, "t")
eq(Audio._cryParams and Audio._cryParams.mode, 0, "playmoncry NIDORAN_M, CRY_MODE_NORMAL reaches the mixer as mode 0")

-- pokefirered/src/scrcmd.c:2090
Audio.stopCry()
Audio._cryParams = nil
local vm, store = newVm({
  t = {
    { op = "setvar", [1] = VAR_TEMP_1, [2] = 25 },
    { op = "playmoncry", [1] = VAR_TEMP_1, [2] = 0 },
    { op = "end" },
  },
})
vm:start("t")
check(Audio._cryParams ~= nil, "playmoncry VarGets a variable species operand without erroring")

print("[test] 2. waitmoncry blocks the script until the cry finishes")
-- pokefirered/src/scrcmd.c:2097
Audio.stopCry()
vm, store = newVm({
  t = {
    { op = "playmoncry", [1] = 143, [2] = 2 },
    { op = "waitmoncry" },
    { op = "setvar", [1] = VAR_TEMP_1, [2] = 7 },
    { op = "end" },
  },
})
vm:start("t")
check(vm:isRunning(), "the vm is still running at waitmoncry")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 0, "the op after waitmoncry has not run yet")
local heldFrames = 0
for _ = 1, 600 do
  if not vm:isRunning() then break end
  heldFrames = heldFrames + 1
  Audio.tickCry(1 / 60)
  vm:tick()
end
check(heldFrames > 1, "waitmoncry held the script for " .. heldFrames .. " frames")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 7, "the script resumed once the cry finished")

Audio.stopCry()
vm, store = run({
  t = {
    { op = "waitmoncry" },
    { op = "setvar", [1] = VAR_TEMP_1, [2] = 7 },
    { op = "end" },
  },
}, "t")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 7, "waitmoncry with no cry playing does not block")

-- pokefirered/src/sound.c:502
Audio.stopCry()
vm, store = newVm({
  t = {
    { op = "playmoncry", [1] = 143, [2] = 2 },
    { op = "waitmoncry" },
    { op = "setvar", [1] = VAR_TEMP_1, [2] = 9 },
    { op = "end" },
  },
})
vm:start("t")
for _ = 1, 600 do
  if not vm:isRunning() then break end
  vm:tick()
end
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 9,
  "waitmoncry still completes when the caller never ticks the audio clock")

print("[test] 3. setstepcallback registry")
-- pokefirered/src/field_tasks.c:96
resetStepCb()
local prevSession = Runtime.session
Runtime.session = { map = "FR_FOUR_ISLAND_ICEFALL_CAVE_1F" }
run({ t = { { op = "setstepcallback", [1] = STEP_CB_ICE }, { op = "end" } } }, "t")
eq(stepCb("FR_FOUR_ISLAND_ICEFALL_CAVE_1F"), "ice", "STEP_CB_ICE registers the ice callback on Icefall Cave 1F")
eq(stepCb("FR_PALLET_TOWN"), nil, "the callback does not leak to another map")

-- pokefirered/src/overworld.c:2105
resetStepCb()
eq(stepCb("FR_FOUR_ISLAND_ICEFALL_CAVE_1F"), nil, "a map load resets the callback to STEP_CB_DUMMY")

resetStepCb()
run({ t = { { op = "setstepcallback", [1] = STEP_CB_ASH }, { op = "end" } } }, "t")
eq(stepCb(), nil, "an unregistered callback id falls back to STEP_CB_DUMMY")
resetStepCb()

print("[test] 4. setmaplayoutindex swaps the live layout")
-- pokefirered/src/overworld.c:978
local W, H = 6, 4
local baseCells, altCells = {}, {}
for i = 1, W * H do
  baseCells[i] = { mid = 0x10, coll = 0x00, elev = 3 }
  altCells[i] = { mid = 0x10, coll = 0x00, elev = 3 }
end
altCells[1] = { mid = 0x2A, coll = 0x01, elev = 4 }
altCells[W * H] = { mid = 0x2B, coll = 0x01, elev = 4 }

local layout = LayoutNative.fromDecoded({
  width = W, height = H, borderWidth = 1, borderHeight = 1,
  borderMids = { 0 }, cells = baseCells,
}, "FR_SEAFOAM_ISLANDS_B4F", "cave")

local scratch = os.getenv("TMPDIR") or "/tmp"
scratch = scratch:gsub("/$", "") .. "/game3_ops_scene_" .. tostring(os.time())
os.execute("mkdir -p '" .. scratch .. "/layouts'")
local blob = NativePack.encodeMidLayout({
  width = W, height = H, borderWidth = 1, borderHeight = 1,
  borderMids = { 0 }, cells = altCells,
})
local fh = io.open(scratch .. "/layouts/alt_279.mid", "wb")
fh:write(blob)
fh:close()

local prevRoot = Extract.NATIVE_ROOT
Extract.NATIVE_ROOT = scratch
local prevGame = Runtime._game
Runtime._game = { data = { maps = { FR_SEAFOAM_ISLANDS_B4F = {
  midLayout = layout, pair = "cave", width = W, height = H,
} } } }
Runtime.session = { map = "FR_SEAFOAM_ISLANDS_B4F" }

eq(layout:midAt(0, 0), 0x10, "the current layout starts on the flowing-current metatile")
run({ t = { { op = "setmaplayoutindex", [1] = 279 }, { op = "end" } } }, "t")
eq(layout:midAt(0, 0), 0x2A, "setmaplayoutindex swapped the first cell's metatile")
eq(layout:collAt(0, 0), 0x01, "the swapped cell carries the alternate layout's collision")
eq(layout:elevAt(0, 0), 4, "the swapped cell carries the alternate layout's elevation")
eq(layout:midAt(W - 1, H - 1), 0x2B, "setmaplayoutindex swapped the last cell too")
eq(layout:midAt(1, 0), 0x10, "cells the alternate layout leaves alone are untouched")

local ok, swapped = ops("setMapLayout", 279)
check(ok and swapped == 0, "re-applying the same layout swaps nothing")
check(ops("setMapLayout", 9999) == false, "an unbaked layout id is a no-op, not an error")

layout:clearOverrides()
eq(layout:midAt(0, 0), 0x10, "clearing the overrides restores the original layout")
os.execute("rm -rf '" .. scratch .. "'")
Extract.NATIVE_ROOT = prevRoot

print("[test] 5. warphole destination resolution")
-- pokefirered/src/scrcmd.c:761
eq(ops("warpHoleDest", 1, 112), "FR_FOUR_ISLAND_ICEFALL_CAVE_B1F",
  "warphole MAP_FOUR_ISLAND_ICEFALL_CAVE_B1F resolves to the port map id")
-- pokefirered/include/constants/maps.h:11
eq(ops("warpHoleDest", 0xFF, 0xFF), nil, "MAP_UNDEFINED has no fixed hole warp on this cart")

Runtime.session = { map = "FR_FOUR_ISLAND_ICEFALL_CAVE_1F" }
Runtime._game = prevGame
Warp._busy = false
Task.clear()
Player.reset(8, 14, "down")
vm, store = newVm({
  t = {
    { op = "warphole", [1] = 0xFF, [2] = 0xFF },
    { op = "waitstate" },
    { op = "setvar", [1] = VAR_TEMP_1, [2] = 5 },
    { op = "end" },
  },
})
vm:start("t")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 5, "an unresolvable warphole falls through instead of hanging")
check(vm.ctx.warpPending ~= true, "no warp is marked pending when the destination is unknown")

Task.clear()
Warp._busy = false
Player.reset(8, 14, "down")
vm, store = newVm({
  t = {
    { op = "warphole", [1] = 1, [2] = 112 },
    { op = "waitstate" },
    { op = "setvar", [1] = VAR_TEMP_1, [2] = 5 },
    { op = "end" },
  },
})
vm:start("t")
check(Warp.isBusy() == true, "warphole started the fall sequence")
check(vm.ctx.warpPending == true, "warphole marked the warp pending")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 0, "waitstate is blocking on the fall")
for _ = 1, 30 do
  Task.update(1 / 60)
  vm:tick()
end
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 0, "waitstate keeps blocking while the fall runs")
check(vm.ctx.warpPending == true, "the pending flag is still set while Warp is busy")
check(vm:isRunning(), "the script is still parked on waitstate after 30 frames of falling")
vm:halt()
Task.clear()
Warp._busy = false

print("[test] 5b. the pending flag clears and waitstate releases when the fall ends")
-- pokefirered/data/scripts/hole.inc:19
local realWarp = package.loaded["src.core.game3.warp"]
local fallFrames = 0
package.loaded["src.core.game3.warp"] = {
  startFall = function() fallFrames = 12 return true end,
  isBusy = function() return fallFrames > 0 end,
}
Task.clear()
Player.reset(8, 14, "down")
vm, store = newVm({
  t = {
    { op = "warphole", [1] = 1, [2] = 112 },
    { op = "waitstate" },
    { op = "setvar", [1] = VAR_TEMP_1, [2] = 5 },
    { op = "end" },
  },
})
vm:start("t")
check(vm.ctx.warpPending == true, "warphole marked the warp pending")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 0, "waitstate is parked while the fall runs")
for _ = 1, 40 do
  if fallFrames > 0 then fallFrames = fallFrames - 1 end
  Task.update(1 / 60)
  vm:tick()
end
check(vm.ctx.warpPending == false, "the pending flag cleared when Warp stopped being busy")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 5, "waitstate released and the script ran on")
check(not vm:isRunning(), "the script finished instead of hanging on waitstate")
package.loaded["src.core.game3.warp"] = realWarp
Task.clear()

print("[test] 6. braille width is pret's fixed 16px advance")
-- pokefirered/src/braille_text.c:209
local everything = { { t = "text", s = "EVERYTHING" }, { t = "eos" } }
eq(ops("brailleWidth", everything), 160, "a ten glyph braille line measures 160")
eq(ops("brailleWidth", { { t = "text", s = "ABC" }, { t = "eos" } }), 48, "ABC measures 48")
-- pokefirered/src/text.c:1051
eq(ops("brailleWidth", {
  { t = "text", s = "ABC" }, { t = "nl" }, { t = "text", s = "WXYZ" }, { t = "eos" },
}), 64, "a two line braille string measures its widest line")
eq(ops("brailleWidth", { { t = "text", s = "É?é=" }, { t = "eos" } }), 64,
  "multi byte glyphs count once each")
eq(ops("brailleWidth", nil), 0, "a missing braille string measures 0")

print("[test] 7. braillemessage and getbraillestringwidth fall back with no renderer")
-- pokefirered/src/scrcmd.c:1570
local prevBraille = package.loaded["src.ui.game3.braille"]
package.loaded["src.ui.game3.braille"] = {}
local opened = {}
local adapters = Adapters.host(nil, nil, nil)
adapters.openMessageStay = function(body) opened[#opened + 1] = body end
adapters.openMessageAsync = nil
adapters.openMessage = nil
store = Flags.newStore()
vm = Vm.new({
  store = store,
  scripts = {
    t = {
      { op = "braillemessage", [1] = "braille1", ptr = "braille1" },
      { op = "getbraillestringwidth", [1] = "braille1" },
      { op = "copyvar", [1] = VAR_TEMP_1, [2] = VAR_0x8004 },
      { op = "end" },
    },
  },
  text = { braille1 = { { t = "text", s = "EVERYTHING" }, { t = "eos" } } },
  adapters = adapters,
})
vm:start("t")
eq(#opened, 1, "braillemessage fell back to the ordinary message box")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 160,
  "getbraillestringwidth wrote the width into VAR_0x8004")
package.loaded["src.ui.game3.braille"] = prevBraille

print("[test] 8. braillemessage hands the string to the renderer when it exists")
local shown = {}
package.loaded["src.ui.game3.braille"] = {
  show = function(text, opts) shown[#shown + 1] = { text = text, opts = opts } end,
  width = function(text) return #text * 16 end,
}
opened = {}
store = Flags.newStore()
vm = Vm.new({
  store = store,
  scripts = {
    t = {
      { op = "braillemessage", [1] = "braille1", ptr = "braille1" },
      { op = "getbraillestringwidth", [1] = "braille1" },
      { op = "copyvar", [1] = VAR_TEMP_1, [2] = VAR_0x8004 },
      { op = "end" },
    },
  },
  text = { braille1 = { { t = "text", s = "CUT" }, { t = "eos" } } },
  adapters = adapters,
})
vm:start("t")
eq(#opened, 0, "the ordinary message box is not used when the renderer is present")
eq(shown[1] and shown[1].text, "CUT", "Braille.show received the braille string")
eq(shown[1] and shown[1].opts and shown[1].opts.width, 48, "Braille.show received the pret width")
eq(Flags.getVar(store, vm.ctx, VAR_TEMP_1), 48, "Braille.width fed VAR_0x8004")
package.loaded["src.ui.game3.braille"] = prevBraille

Runtime.session = prevSession
Runtime._game = prevGame

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
