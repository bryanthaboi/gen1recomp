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

local Vm = require("src.core.game3.scripting.vm")
local Flags = require("src.core.game3.scripting.flags")
local Std = require("src.core.game3.scripting.stdscripts")
local Natives = require("src.core.game3.scripting.natives")
local okSeag, Seagallop = pcall(require, "src.core.game3.scripting.natives_seagallop")
if not okSeag then Seagallop = { WARPS = {} } end
local Fade = require("src.ui.game3.fade")

local SEAGALLOP_VERMILION_CITY = 0
local SEAGALLOP_ONE_ISLAND = 1
local SEAGALLOP_TWO_ISLAND = 2
local SEAGALLOP_THREE_ISLAND = 3
local SEAGALLOP_FOUR_ISLAND = 4
local SEAGALLOP_FIVE_ISLAND = 5
local SEAGALLOP_SIX_ISLAND = 6
local SEAGALLOP_SEVEN_ISLAND = 7
local SEAGALLOP_CINNABAR_ISLAND = 8
local SEAGALLOP_NAVEL_ROCK = 9
local SEAGALLOP_BIRTH_ISLAND = 10
local SEAGALLOP_MORE = 254
local SCR_MENU_CANCEL = 127

-- pokefirered/data/scripts/seagallop.inc:102 EventScript_SetSail
local function setSailScript(origin, dest)
  return {
    { op = "setvar", var = 0x8004, value = origin },
    { op = "setvar", var = 0x8006, value = dest },
    { op = "specialvar", [1] = 0x800D, [2] = Std.SPECIAL.GetSeagallopNumber },
    { op = "fadescreen", [1] = 1 },
    { op = "special", id = Std.SPECIAL.DoSeagallopFerryScene },
    { op = "waitstate" },
    { op = "copyvar", [1] = 0x4000, [2] = 0x8006 },
    { op = "end" },
  }
end

local function newVm(scripts, adapters)
  return Vm.new({
    store = Flags.newStore(),
    scripts = scripts,
    adapters = adapters,
  })
end

local function logAdapters(extra)
  local a = {
    log = function(m) print("[log] " .. tostring(m)) end,
    fadeScreen = function(mode, speed, done)
      Fade.begin(mode, speed, function() if done then done() end end)
      Fade.t = (mode == 1 or mode == 3) and 16 or 0
      Fade.active = false
      local cb = Fade.doneCb
      Fade.doneCb = nil
      if cb then cb() end
    end,
  }
  for k, v in pairs(extra or {}) do a[k] = v end
  return a
end

print("[test] 1. special 0x17B is bound and is not logged as unknown")
Natives.resetLog()
local unknown = {}
do
  local warps = {}
  local a = logAdapters({
    log = function(m)
      if tostring(m):match("skip unknown") then unknown[#unknown + 1] = m end
    end,
    warp = function(g, n, w, x, y, done)
      warps[#warps + 1] = { g, n, w, x, y }
      if done then done() end
    end,
  })
  local vm = newVm({ sail = setSailScript(SEAGALLOP_CINNABAR_ISLAND, SEAGALLOP_ONE_ISLAND) }, a)
  vm:start("sail")
  check(#unknown == 0, "nothing logged as an unknown special (got " .. #unknown .. ")")
  check(Flags.getVar(vm.store, vm.ctx, 0x800D) == 1,
    "GetSeagallopNumber = 1 for the Cinnabar run (got " ..
    tostring(Flags.getVar(vm.store, vm.ctx, 0x800D)) .. ")")

  print("[test] 2. waitstate holds the script while the ferry crosses")
  check(vm:isRunning(), "the script is still alive after `special` + `waitstate`")
  check(#warps == 0, "no warp on the frame the ferry leaves")
  local ranFor = 0
  for _ = 1, 400 do
    if #warps > 0 then break end
    ranFor = ranFor + 1
    vm:tick()
  end
  check(#warps == 1, "the ferry warped exactly once (got " .. #warps .. ")")
  check(ranFor >= 100, "waitstate suspended the script for the crossing, ticks=" .. ranFor)
  local w = warps[1]
  check(w and w[1] == 32 and w[2] == 4,
    "warped to MAP_ONE_ISLAND_HARBOR group 32 num 4 (got " ..
    tostring(w and w[1]) .. "/" .. tostring(w and w[2]) .. ")")
  check(w and w[4] == 8 and w[5] == 5,
    "landed on sSeag coords (8,5), got (" .. tostring(w and w[4]) .. "," .. tostring(w and w[5]) .. ")")

  print("[test] 3. the FADE_TO_BLACK is undone on arrival")
  check(Fade.mode == Fade.MODE.FROM_BLACK, "a FADE_FROM_BLACK was started on arrival")
  check(Fade.active == true, "the arrival fade is running, not left black")
  for _ = 1, 40 do
    if not Fade.active then break end
    Fade.tick(1 / 60)
  end
  check(Fade.active == false and Fade.t == 0, "the veil cleared (t=" .. tostring(Fade.t) .. ")")

  print("[test] 4. the script finishes after the warp")
  for _ = 1, 10 do vm:tick() end
  check(not vm:isRunning(), "the VM reached `end` instead of hanging on waitstate")
end

print("[test] 5. every seagallop id has the pret warp row")
local WANT = {
  [SEAGALLOP_VERMILION_CITY] = { 3, 5, 0x17, 0x20 },
  [SEAGALLOP_ONE_ISLAND] = { 32, 4, 8, 5 },
  [SEAGALLOP_TWO_ISLAND] = { 33, 4, 8, 5 },
  [SEAGALLOP_THREE_ISLAND] = { 38, 0, 8, 5 },
  [SEAGALLOP_FOUR_ISLAND] = { 35, 5, 8, 5 },
  [SEAGALLOP_FIVE_ISLAND] = { 36, 2, 8, 5 },
  [SEAGALLOP_SIX_ISLAND] = { 37, 2, 8, 5 },
  [SEAGALLOP_SEVEN_ISLAND] = { 31, 6, 8, 5 },
  [SEAGALLOP_CINNABAR_ISLAND] = { 3, 8, 0x15, 0x07 },
  [SEAGALLOP_NAVEL_ROCK] = { 2, 59, 8, 5 },
  [SEAGALLOP_BIRTH_ISLAND] = { 2, 58, 8, 5 },
}
for id, want in pairs(WANT) do
  local got = Seagallop.WARPS[id]
  check(got and got[1] == want[1] and got[2] == want[2] and got[3] == want[3] and got[4] == want[4],
    string.format("seagallop %d -> %d.%d (%d,%d)", id, want[1], want[2], want[3], want[4]))
end

print("[test] 6. an out-of-range destination falls back to Vermilion")
do
  local warps = {}
  local a = logAdapters({
    warp = function(g, n, w, x, y, done)
      warps[#warps + 1] = { g, n, w, x, y }
      if done then done() end
    end,
  })
  local vm = newVm({ sail = setSailScript(SEAGALLOP_ONE_ISLAND, 40) }, a)
  vm:start("sail")
  for _ = 1, 400 do
    if #warps > 0 then break end
    vm:tick()
  end
  check(#warps == 1 and warps[1][1] == 3 and warps[1][2] == 5,
    "dest 40 warped to Vermilion City 3.5")
  for _ = 1, 5 do vm:tick() end
  check(Flags.getVar(vm.store, vm.ctx, 0x4000) == SEAGALLOP_VERMILION_CITY,
    "VAR_0x8006 was clamped to 0 (got " ..
    tostring(Flags.getVar(vm.store, vm.ctx, 0x4000)) .. ")")
end

print("[test] 7. GetSeagallopNumber matches the pret cascade")
check(type(Seagallop.seagallopNumber) == "function", "the seagallop module is present")
if type(Seagallop.seagallopNumber) ~= "function" then
  print("[test] " .. (failed + 1) .. " failed")
  os.exit(1)
end
local NUM = {
  { SEAGALLOP_VERMILION_CITY, SEAGALLOP_ONE_ISLAND, 7 },
  { SEAGALLOP_CINNABAR_ISLAND, SEAGALLOP_ONE_ISLAND, 1 },
  { SEAGALLOP_ONE_ISLAND, SEAGALLOP_CINNABAR_ISLAND, 1 },
  { SEAGALLOP_VERMILION_CITY, SEAGALLOP_NAVEL_ROCK, 7 },
  { SEAGALLOP_ONE_ISLAND, SEAGALLOP_NAVEL_ROCK, 10 },
  { SEAGALLOP_ONE_ISLAND, SEAGALLOP_BIRTH_ISLAND, 12 },
  { SEAGALLOP_ONE_ISLAND, SEAGALLOP_THREE_ISLAND, 2 },
  { SEAGALLOP_FOUR_ISLAND, SEAGALLOP_FIVE_ISLAND, 3 },
  { SEAGALLOP_SIX_ISLAND, SEAGALLOP_SEVEN_ISLAND, 5 },
  { SEAGALLOP_THREE_ISLAND, SEAGALLOP_FOUR_ISLAND, 6 },
}
for _, row in ipairs(NUM) do
  local got = Seagallop.seagallopNumber(row[1], row[2])
  check(got == row[3], string.format("seagallop number %d -> %d is %d (got %s)",
    row[1], row[2], row[3], tostring(got)))
end

print("[test] 8. the destination menu drops the port you are standing in")
if not require("tests.game3_cache").mount() then
  print("[skip] sSeagallopDestStrings come from the ROM: " .. tostring(require("tests.game3_cache").reason))
else
  local labels = Seagallop.destinationMenu(SEAGALLOP_ONE_ISLAND, 0)
  check(#labels == 6, "page 0 has six rows (got " .. #labels .. ")")
  check(labels[1] == "VERMILION" and labels[2] == "TWO ISLAND"
    and labels[3] == "THREE ISLAND" and labels[4] == "FOUR ISLAND",
    "ONE ISLAND is skipped: " .. table.concat(labels, "/"))
  check(labels[5] == "OTHER" and labels[6] == "EXIT", "OTHER and EXIT close the page")
  local p1 = Seagallop.destinationMenu(SEAGALLOP_ONE_ISLAND, 1)
  check(#p1 == 5 and p1[1] == "FIVE ISLAND" and p1[2] == "SIX ISLAND"
    and p1[3] == "SEVEN ISLAND", "page 1 from One Island: " .. table.concat(p1, "/"))
  local p1b = Seagallop.destinationMenu(SEAGALLOP_SIX_ISLAND, 1)
  check(p1b[1] == "FOUR ISLAND" and p1b[2] == "FIVE ISLAND" and p1b[3] == "SEVEN ISLAND",
    "page 1 from Six Island: " .. table.concat(p1b, "/"))
end

print("[test] 9. GetSelectedSeagallopDestination maps the row back to a port")
do
  local sel = Seagallop.selectedDestination
  check(sel(SEAGALLOP_ONE_ISLAND, 0, 0) == SEAGALLOP_VERMILION_CITY, "page 0 row 0 = Vermilion")
  check(sel(SEAGALLOP_ONE_ISLAND, 0, 1) == SEAGALLOP_TWO_ISLAND, "page 0 row 1 = Two Island")
  check(sel(SEAGALLOP_ONE_ISLAND, 0, 4) == SEAGALLOP_MORE, "page 0 row 4 = OTHER")
  check(sel(SEAGALLOP_ONE_ISLAND, 0, 5) == SCR_MENU_CANCEL, "page 0 row 5 = EXIT")
  check(sel(SEAGALLOP_ONE_ISLAND, 0, SCR_MENU_CANCEL) == SCR_MENU_CANCEL, "B press cancels")
  check(sel(SEAGALLOP_ONE_ISLAND, 1, 0) == SEAGALLOP_FIVE_ISLAND, "page 1 row 0 from One Island")
  check(sel(SEAGALLOP_SIX_ISLAND, 1, 0) == SEAGALLOP_FOUR_ISLAND, "page 1 row 0 from Six Island")
  check(sel(SEAGALLOP_SIX_ISLAND, 1, 2) == SEAGALLOP_SEVEN_ISLAND, "page 1 row 2 from Six Island")
  check(sel(SEAGALLOP_ONE_ISLAND, 1, 3) == SEAGALLOP_MORE, "page 1 row 3 = OTHER")
  check(sel(SEAGALLOP_ONE_ISLAND, 1, 4) == SCR_MENU_CANCEL, "page 1 row 4 = EXIT")
end

print("[test] 10. the menu special drives the shared multichoice and sets VAR_0x8006")
if not require("tests.game3_cache").mount() then
  print("[skip] the ferry menu labels come from the ROM: " .. tostring(require("tests.game3_cache").reason))
else
  local shown
  local a = logAdapters({
    multichoice = function(row, cb)
      local Multi = require("src.core.game3.scripting.multichoice")
      local entry = Multi.LISTS[row[3]]
      shown = entry and entry.labels
      cb(1)
    end,
  })
  local vm = newVm({
    page1 = {
      { op = "setvar", var = 0x8004, value = SEAGALLOP_ONE_ISLAND },
      { op = "setvar", var = 0x8005, value = 0 },
      { op = "special", id = Std.SPECIAL.DrawSeagallopDestinationMenu },
      { op = "waitstate" },
      { op = "specialvar", [1] = 0x8006, [2] = Std.SPECIAL.GetSelectedSeagallopDestination },
      { op = "copyvar", [1] = 0x4000, [2] = 0x8006 },
      { op = "end" },
    },
  }, a)
  vm:start("page1")
  for _ = 1, 10 do vm:tick() end
  check(shown ~= nil and #shown == 6, "the ferry menu reached the multichoice adapter")
  check(Flags.getVar(vm.store, vm.ctx, 0x4000) == SEAGALLOP_TWO_ISLAND,
    "picking row 1 from One Island sails to Two Island (got " ..
    tostring(Flags.getVar(vm.store, vm.ctx, 0x4000)) .. ")")
  check(not vm:isRunning(), "the menu script finished")
end

print("[test] 11. waitstate with nothing pending is still a no-op")
do
  local a = logAdapters({})
  local vm = newVm({
    plain = {
      { op = "waitstate" },
      { op = "setflag", [1] = 0x300 },
      { op = "end" },
    },
  }, a)
  vm:start("plain")
  check(Flags.getFlag(vm.store, nil, 0x300) == true, "a bare waitstate fell straight through")
  check(not vm:isRunning(), "and the script ended in the same frame")
end

if failed == 0 then
  print("[test] all passed")
  os.exit(0)
end
print("[test] " .. failed .. " failed")
os.exit(1)
