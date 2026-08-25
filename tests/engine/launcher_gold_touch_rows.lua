-- #1100 / #1135: the launcher gear offered TOUCH PAD, VIBRATION and the
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

-- The rows are mobile-gated the same way OptionsMenu's are, so the suite has
-- to look like a phone; POKEPORT_TOUCH=1 is the other way in.
local realGetOS = love.system.getOS
love.system.getOS = function() return "Android" end

local LauncherSettings = require("src.import.LauncherSettings")
local TouchControls = require("src.core.TouchControls")

local function labels(model)
local out = {}
for _, section in ipairs(model.sections) do
  for _, row in ipairs(section.rows) do out[#out + 1] = row.label end
end
return out
end

local function findRow(model, label)
for _, section in ipairs(model.sections) do
  for _, row in ipairs(section.rows) do
    if row.label == label then return row end
  end
end
end

local function has(model, label)
for _, l in ipairs(labels(model)) do
  if l == label then return true end
end
return false
end

local edited = 0
local hooks = { editTouchControls = function() edited = edited + 1 end }

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local model = LauncherSettings.open(hooks, version)
  check(has(model, "TOUCH PAD"), version .. " gear offers TOUCH PAD")
  check(has(model, "VIBRATION"), version .. " and VIBRATION")
  check(has(model, "TOUCH CONTROLS"), version .. " and the layout editor")
  check(has(model, "VOID FILL"), version .. " and VOID FILL")
  check(has(model, "ZOOM"), version .. " and ZOOM")

  local zoom = findRow(model, "ZOOM")
  eq(zoom.value(), "FIT", version .. " ZOOM defaults to FIT")
  zoom.step(-1)
  eq(model.opts.gold.zoom, -1, version .. " left stores OUT1 in the gold block")
  eq(zoom.value(), "OUT1", version .. " and the row reads OUT1")
  zoom.step(1)
  eq(model.opts.gold.zoom, 0, version .. " right restores FIT")

  local voidFill = findRow(model, "VOID FILL")
  eq(voidFill.value(), "FADE ", version .. " VOID FILL defaults to FADE")
  voidFill.step(1)
  eq(model.opts.gold.voidFill, "water",
    version .. " right stores water in the gold block")
  eq(voidFill.value(), "WATER", version .. " and the row reads WATER")
  voidFill.step(-1)
  eq(model.opts.gold.voidFill, "fade", version .. " left restores fade")

  -- The pad and the buzz are one device-wide setting: Gen 2 reads them from
  -- the flat keys, not its block (src/core/gen2/Save.lua SHARED_KEYS), so the
  -- rows write the flat keys and must never grow a copy inside `gold`.
  local pad = findRow(model, "TOUCH PAD")
  local before = pad.value()
  pad.step(1)
  check(pad.value() ~= before, version .. " stepping TOUCH PAD flips it")
  eq(model.opts.touchControls.enabled, false,
    version .. " on the flat shared key")
  eq(model.opts.gold.touchControls, nil,
    version .. " without a copy in the gold block")
  eq(model.opts.silver, nil,
    version .. " and inventing no second Gen 2 block beside it")
  eq(model.opts.crystal, nil, version .. " nor a third")

  local buzz = findRow(model, "VIBRATION")
  local buzzBefore = buzz.value()
  buzz.step(1)
  check(buzz.value() ~= buzzBefore, version .. " stepping VIBRATION moves the level")
  eq(model.opts.haptics,
    TouchControls.normalizeHaptics(model.opts.haptics),
    version .. " VIBRATION stores a level the shared module knows")
  eq(model.opts.gold.haptics, nil, version .. " on the flat key only")

  edited = 0
  findRow(model, "TOUCH CONTROLS").action()
  eq(edited, 1, version .. " the editor row reaches the host hook")
end

-- The Gen 1 gear is untouched by the extraction: same three rows, still on
-- the flat table.
local red = LauncherSettings.open(hooks, "red")
check(has(red, "TOUCH PAD"), "Red still offers TOUCH PAD")
check(has(red, "VIBRATION"), "and VIBRATION")
check(has(red, "TOUCH CONTROLS"), "and the layout editor")
findRow(red, "TOUCH PAD").step(1)
eq(red.opts.touchControls.enabled, false, "writing to the flat key")
eq(red.opts.gold, nil, "with no gold block invented")
eq(findRow(red, "TOUCH PAD").value() ~= nil, true, "and reading it back")

-- With no hook (the standalone save editor's shape) the editor row is gone
-- rather than dead, on both sides.
eq(has(LauncherSettings.open(nil, "gold"), "TOUCH CONTROLS"), false,
  "no hook, no editor row on Gold")
eq(has(LauncherSettings.open(nil, "silver"), "TOUCH CONTROLS"), false,
  "nor on Silver")
eq(has(LauncherSettings.open(nil, "crystal"), "TOUCH CONTROLS"), false,
  "nor on Crystal")
eq(has(LauncherSettings.open(nil, "red"), "TOUCH CONTROLS"), false,
  "nor on Red")
-- The Edit row hands the screen to the host, and the host has to know WHICH
-- game's block to write the dragged layout into: TouchControlsEditor persists
-- to opts.gold only when it was loaded with version = "gold".  Source-shape
-- checks, the same way tests/engine/touch_controls_pad_cursor_test.lua pins
-- the handoff either side of this one.
local function read(path)
  local f = assert(io.open(path, "r"))
  local src = f:read("*a")
  f:close()
  return src
end

local importerSrc = read("src/import/RomImporter.lua")
check(importerSrc:find("self.onEditTouchControls(version)", 1, true) ~= nil,
  "the gear hands the launcher tab to the host")

local mainSrc = read("main.lua")
local body = mainSrc:match("local function openTouchControlsEditor%((.-)%)")
eq(body, "version", "main.lua's opener takes that tab")
check(mainSrc:match("TouchEditor%.load%({%s*version = version") ~= nil,
  "and loads the editor with it, so Gold's layout lands in the gold block")

love.system.getOS = realGetOS

T.finish("launcher gold touch rows")
