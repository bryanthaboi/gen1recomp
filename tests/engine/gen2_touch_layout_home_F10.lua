package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local SaveData = require("src.core.SaveData")
local Save = require("src.core.gen2.Save")
local TouchControls = require("src.core.TouchControls")
local Editor = require("src.ui.TouchControlsEditor")
local LauncherSettings = require("src.import.LauncherSettings")

local GEN1_DPAD = { x = 0.2, y = 0.7 }

local function seed(mut)
  local opts = SaveData.defaultOptions()
  opts.touchControls = {
    enabled = true,
    layouts = {
      portrait = { positions = { dpad = GEN1_DPAD }, scale = 1 },
      landscape = { positions = { dpad = GEN1_DPAD }, scale = 1 },
    },
  }
  if mut then mut(opts) end
  SaveData.saveOptions(opts)
end

local function editDpad(version, dx, dy, enabled)
  Editor.load({ version = version })
  TouchControls:currentBucket()
  local bucket = TouchControls.orientation
  local d = TouchControls:layout().dpad
  TouchControls:setControlCenter("dpad", d.cx + dx, d.cy + dy)
  if enabled ~= nil then TouchControls.enabled = enabled end
  local saved = TouchControls:config().layouts[bucket].positions.dpad
  Editor.keypressed("escape")
  return bucket, { x = saved.x, y = saved.y }
end

local function dpadOf(tc, bucket)
  local cfg = TouchControls.normalizeConfig(tc)
  local p = cfg.layouts[bucket].positions
  return p and p.dpad
end

local function near(a, b)
  return a ~= nil and b ~= nil
    and math.abs(a.x - b.x) < 1e-6 and math.abs(a.y - b.y) < 1e-6
end

seed()
local bucket, goldDpad = editDpad("gold", -40, -30)
check(not near(goldDpad, GEN1_DPAD), "gold edit moved the pad off the Gen 1 spot")
local boot = Save.loadOptions()
check(near(dpadOf(boot.touchControls, bucket), goldDpad),
  "gold layout edited with a flat layout present shows on the next Gen 2 boot")
local file = SaveData.loadOptions()
check(near(dpadOf(file.touchControls, bucket), GEN1_DPAD),
  "the Gen 1 layout is left where Red had it")
eq(file.gold.touchControls.enabled, nil, "the gold block holds no second TOUCH PAD switch")
eq(file.touchControls.enabled, true, "the switch stays on the flat key")

for _, version in ipairs({ "silver", "crystal" }) do
  seed()
  local b, moved = editDpad(version, 30, -20)
  check(near(dpadOf(Save.loadOptions().touchControls, b), moved),
    version .. " layout edit shows on the next Gen 2 boot")
end

seed()
local b1, gen1Moved = editDpad("red", 25, 0)
seed(function(o)
  o.gold = { touchControls = { layouts = {
    portrait = { positions = { dpad = { x = 0.6, y = 0.5 } }, scale = 1 },
    landscape = { positions = { dpad = { x = 0.6, y = 0.5 } }, scale = 1 },
  } } }
end)
editDpad("red", 25, 0)
check(near(dpadOf(Save.loadOptions().touchControls, b1), { x = 0.6, y = 0.5 }),
  "a Red layout edit does not move Gold's own layout")
check(near(dpadOf(SaveData.loadOptions().touchControls, b1), gen1Moved),
  "while Red still gets its edit")

seed(function(o) o.gold = { textSpeed = "FAST" } end)
check(near(dpadOf(Save.loadOptions().touchControls, bucket), GEN1_DPAD),
  "a save with no gold layout migrates the flat one")

seed(function(o)
  o.gold = { touchControls = { enabled = false } }
end)
local stale = Save.loadOptions()
eq(stale.touchControls.enabled, true, "a stale gold switch never beats the flat TOUCH PAD")
check(near(dpadOf(stale.touchControls, bucket), GEN1_DPAD),
  "and a gold block with no layout still migrates the flat one")

seed()
editDpad("gold", -40, -30)
local gearOpts = SaveData.loadOptions()
gearOpts.touchControls.enabled = false
SaveData.saveOptions(gearOpts)
local off = Save.loadOptions()
eq(off.touchControls.enabled, false, "gear TOUCH PAD OFF reaches Gen 2 with a gold layout saved")
check(near(dpadOf(off.touchControls, bucket), goldDpad), "without losing the gold layout")

off.touchControls.enabled = true
check(Save.saveOptions(off), "Gen 2 in-game TOUCH PAD write lands")
file = SaveData.loadOptions()
eq(file.touchControls.enabled, true, "in-game TOUCH PAD ON lands on the flat switch")
eq(file.gold.touchControls.enabled, nil, "not in the gold block")
check(near(dpadOf(file.gold.touchControls, bucket), goldDpad), "gold layout survives an options write")
check(near(dpadOf(file.touchControls, bucket), GEN1_DPAD), "flat layout survives an options write")
eq(Save.loadOptions().touchControls.enabled, true, "and Gen 2 boots with the pad on")

seed()
editDpad("gold", 10, 10, false)
file = SaveData.loadOptions()
eq(file.touchControls.enabled, false, "editor TOUCH PAD OFF from a Gen 2 tab is the flat switch")
eq(Save.loadOptions().touchControls.enabled, false, "and Gen 2 boots with the pad off")
check(near(dpadOf(file.touchControls, bucket), GEN1_DPAD), "the Gen 1 layout is not overwritten")

local realSelectSkin = TouchControls.selectSkin
TouchControls.selectSkin = function(self, id) self.skinId = id end
seed(function(o)
  o.touchControls.skin = "gb_anim"
  o.gold = { touchControls = { skin = "tv_crt" } }
end)
editDpad("gold", 10, 10)
eq(SaveData.loadOptions().touchControls.skin, "gb_anim", "a Gen 2 editor save keeps the flat skin pick")
eq(Save.loadOptions().touchControls.skin, "gb_anim", "and Gen 2 boots with it")
TouchControls.selectSkin = realSelectSkin

seed()
editDpad("gold", -40, -30)
local hooks = { editTouchControls = function() end }
local model = LauncherSettings.open(hooks, "gold")
for _, section in ipairs(model.sections) do
  for _, row in ipairs(section.rows) do
    if row.label == "RESET REBINDS" then row.action() end
  end
end
model.save()
local reset = Save.loadOptions()
eq(dpadOf(reset.touchControls, bucket), nil, "gold RESET REBINDS brings Gen 2 back to the stock layout")

seed()
local b3, g3Moved = editDpad("emerald", 15, -15, false)
file = SaveData.loadOptions()
check(near(dpadOf(file.game3.touchControls, b3), g3Moved), "a Gen 3 edit still lands in the game3 block")
check(near(dpadOf(file.touchControls, b3), GEN1_DPAD), "and leaves the flat layout alone")
eq(file.touchControls.enabled, false, "the Gen 3 editor's TOUCH PAD is the flat switch too")

seed(function(o)
  o.touchControls.enabled = false
  o.game3 = { touchControls = { enabled = true, layouts = {} } }
end)
Editor.load({ version = "emerald" })
eq(TouchControls.enabled, false, "the Gen 3 editor opens on the flat TOUCH PAD switch")
Editor.keypressed("escape")
eq(SaveData.loadOptions().touchControls.enabled, false,
  "and closing it does not flip the switch back on")

local Game3 = require("src.core.Game3")
local function gen3Boot()
  local got
  local game = setmetatable({
    touchControls = { applyOptions = function(_, o) got = o end },
  }, { __index = Game3 })
  local opts = SaveData.loadOptions()
  pcall(Game3.applyOptions, game, opts)
  return got and got.touchControls, got or {}, opts
end

seed()
local b3g, g3Dpad = editDpad("emerald", 15, -15)
eq(SaveData.loadOptions().game3.touchControls.enabled, nil,
  "the game3 block holds no second TOUCH PAD switch")
local gear3 = SaveData.loadOptions()
gear3.touchControls.enabled = false
gear3.touchControls.skin = "gb_anim"
SaveData.saveOptions(gear3)
local g3boot = gen3Boot() or {}
eq(g3boot.enabled, false, "gear TOUCH PAD OFF reaches Gen 3 after a Gen 3 editor save")
eq(g3boot.skin, "gb_anim", "a skin pick reaches Gen 3 after a Gen 3 editor save")
check(near(dpadOf(g3boot, b3g), g3Dpad), "Gen 3 still boots on its own layout")

seed(function(o) o.game3 = { textSpeed = 2 } end)
check(near(dpadOf(gen3Boot() or {}, b3g), GEN1_DPAD),
  "a save with no game3 layout boots Gen 3 on the flat one")

local realGetenv = os.getenv
os.getenv = function(k)
  if k == "POKEPORT_TOUCH" then return "1" end
  return realGetenv(k)
end

local function launcherRow(model, label)
  for _, section in ipairs(model.sections) do
    for _, row in ipairs(section.rows) do
      if row.label == label then return row end
    end
  end
end

seed(function(o)
  o.haptics, o.hotbar = "light", true
  o.game3 = { haptics = "strong", hotbar = true }
end)
local gear = LauncherSettings.open({ editTouchControls = function() end }, "emerald")
local vib, bar = launcherRow(gear, "VIBRATION"), launcherRow(gear, "KEY BAR")
check(vib ~= nil and bar ~= nil, "Gen 3 gear lists VIBRATION and KEY BAR")
if vib and bar then
  vib.step(1)
  bar.step(1)
  gear.save()
  local _, g3applied, g3opts = gen3Boot()
  eq(g3applied.haptics, "normal", "gear VIBRATION reaches Gen 3 over a stale game3 copy")
  eq(g3applied.hotbar, false, "gear KEY BAR OFF reaches Gen 3 over a stale game3 copy")
  eq(g3opts.game3.haptics, nil, "the stale game3 VIBRATION copy is dropped")
  eq(g3opts.game3.hotbar, nil, "the stale game3 KEY BAR copy is dropped")
end

local RomText = require("src.core.game3.rom_text")
local realAt, realCount = RomText.at, RomText.count
RomText.at = function(n, i) return n .. "[" .. tostring(i) .. "]" end
RomText.count = function() return 0 end
local Rows = require("src.ui.game3.option_rows")
seed()
local b3r, g3RowDpad = editDpad("emerald", -20, 10)
local g3game = setmetatable({ options = SaveData.loadOptions(), touchControls = TouchControls },
  { __index = Game3 })
pcall(Game3.applyOptions, g3game, g3game.options)
local ctx = { options = g3game.options, game = g3game, session = {} }
local padRow, vibRow, barRow
for _, r in ipairs(Rows.build(ctx)) do
  if r.id == "touchControls" then padRow = r end
  if r.id == "haptics" then vibRow = r end
  if r.id == "hotbar" then barRow = r end
end
os.getenv = realGetenv
RomText.at, RomText.count = realAt, realCount
check(padRow ~= nil, "Gen 3 options list a TOUCH PAD row")
if padRow then
  padRow.step(ctx, 1)
  eq(TouchControls.enabled, false, "Gen 3 in-game TOUCH PAD turns the pad off")
  check(near(TouchControls:config().layouts[b3r].positions.dpad, g3RowDpad),
    "Gen 3 in-game TOUCH PAD keeps the game3 layout")
  padRow.step(ctx, 1)
  eq(TouchControls.enabled, true, "and back on")
  check(near(TouchControls:config().layouts[b3r].positions.dpad, g3RowDpad),
    "still on the game3 layout")
end
check(vibRow ~= nil and barRow ~= nil, "Gen 3 options list VIBRATION and KEY BAR rows")
if vibRow and barRow then
  ctx.options.haptics = "light"
  vibRow.step(ctx, 1)
  eq(TouchControls.haptics, "normal", "Gen 3 in-game VIBRATION applies live")
  check(near(TouchControls:config().layouts[b3r].positions.dpad, g3RowDpad),
    "Gen 3 in-game VIBRATION keeps the game3 layout")
  ctx.options.hotbar = true
  barRow.step(ctx, 1)
  eq(TouchControls.hotbarEnabled, false, "Gen 3 in-game KEY BAR OFF applies live")
  check(near(TouchControls:config().layouts[b3r].positions.dpad, g3RowDpad),
    "Gen 3 in-game KEY BAR keeps the game3 layout")
end

local GOLD_DPAD = { x = 0.6, y = 0.5 }

seed(function(o)
  o.gold = { textSpeed = "FAST", touchControls = {
    enabled = true,
    layouts = { portrait = { scale = 1 }, landscape = { scale = 1 } },
  } }
end)
check(near(dpadOf(Save.loadOptions().touchControls, bucket), GEN1_DPAD),
  "an old-editor gold block with no drag keeps the Red layout Gold showed")

seed(function(o)
  o.gold = { touchControls = {
    enabled = true,
    layouts = {
      portrait = { positions = { dpad = GOLD_DPAD }, scale = 1 },
      landscape = { positions = { dpad = GOLD_DPAD }, scale = 1 },
    },
  } }
end)
check(near(dpadOf(Save.loadOptions().touchControls, bucket), GOLD_DPAD),
  "an old-editor gold block with a real drag is Gold's layout")

seed(function(o) o.gold = { touchControls = { layouts = {} } } end)
eq(dpadOf(Save.loadOptions().touchControls, bucket), nil,
  "a reset gold block still means the stock layout")

seed(function(o)
  o.hotbar = true
  o.gold = { textSpeed = "FAST", hotbar = false }
end)
eq(Save.loadOptions().hotbar, false, "an old gold KEY BAR OFF carries over on the Gen 2 boot")
file = SaveData.loadOptions()
eq(file.hotbar, false, "into the flat KEY BAR")
eq(file.gold.hotbar, nil, "and leaves no gold copy behind")
eq(file.gold.textSpeed, "FAST", "without touching the rest of the gold block")

local realGetenvBar = os.getenv
os.getenv = function(k)
  if k == "POKEPORT_TOUCH" then return "1" end
  return realGetenvBar(k)
end
local function gearKeyBar()
  local model = LauncherSettings.open({}, "gold")
  for _, section in ipairs(model.sections) do
    for _, r in ipairs(section.rows) do
      if r.label == "KEY BAR" then r.step(1) end
    end
  end
  model.save()
end
gearKeyBar()
os.getenv = realGetenvBar
eq(Save.loadOptions().hotbar, true, "the carry-over happens once, a later gear KEY BAR ON sticks")

seed(function(o)
  o.hotbar = true
  o.gold = { textSpeed = "FAST", hotbar = true }
end)
os.getenv = function(k)
  if k == "POKEPORT_TOUCH" then return "1" end
  return realGetenvBar(k)
end
gearKeyBar()
os.getenv = realGetenvBar
eq(Save.loadOptions().hotbar, false, "gold gear KEY BAR OFF reaches the Gen 2 boot")

local barOpts = Save.loadOptions()
barOpts.hotbar = true
check(Save.saveOptions(barOpts), "Gen 2 in-game KEY BAR write lands")
file = SaveData.loadOptions()
eq(file.hotbar, true, "Gen 2 in-game KEY BAR lands on the flat key")
eq(file.gold.hotbar, nil, "not in the gold block")

T.finish("gen2_touch_layout_home_F10")
