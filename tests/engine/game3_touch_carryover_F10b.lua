package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local SaveData = require("src.core.SaveData")
local TouchControls = require("src.core.TouchControls")
local Game3 = require("src.core.Game3")

local RED = { x = 0.15, y = 0.75 }
local function redLayout()
  return {
    portrait = { positions = { dpad = { x = RED.x, y = RED.y } }, scale = 1 },
    landscape = { positions = { dpad = { x = RED.x, y = RED.y } }, scale = 1 },
  }
end

local function isRed(tc)
  local p = TouchControls.normalizeConfig(tc).layouts.landscape.positions
  local d = p and p.dpad
  return d ~= nil and math.abs(d.x - RED.x) < 1e-6 and math.abs(d.y - RED.y) < 1e-6
end

local function seed(flat, game3)
  local o = SaveData.defaultOptions()
  o.touchControls = flat
  o.game3 = game3
  SaveData.saveOptions(o)
end

local function boot()
  local got
  local game = setmetatable({
    touchControls = { applyOptions = function(_, o) got = o end },
  }, { __index = Game3 })
  game.options = SaveData.loadOptions()
  pcall(Game3.applyOptions, game, game.options)
  return got and got.touchControls or {}
end

seed({ enabled = true }, { touchControls = { enabled = false, skin = "tv_crt", layouts = redLayout() } })
local a = boot()
eq(a.enabled, false, "an old Gen 3 editor TOUCH PAD OFF survives the upgrade")
eq(a.skin, "tv_crt", "an old Gen 3 editor skin pick survives the upgrade")
check(isRed(a), "the Gen 3 layout is unchanged")
local file = SaveData.loadOptions()
eq(file.touchControls.enabled, false, "the old switch is carried into the flat key")
eq(file.touchControls.skin, "tv_crt", "the old skin is carried into the flat key")
eq(file.game3.touchControls.enabled, nil, "the game3 block drops its switch")
eq(file.game3.touchControls.skin, nil, "the game3 block drops its skin")
check(isRed(file.game3.touchControls), "the game3 block keeps its layout")
local again = boot()
eq(again.enabled, false, "the next boot still has the pad off")
eq(again.skin, "tv_crt", "the next boot still has the skin")

seed({ enabled = false, skin = "gb_anim" }, { touchControls = { enabled = true, skin = "tv_crt", layouts = redLayout() } })
local b = boot()
eq(b.enabled, false, "a flat TOUCH PAD OFF beats an old game3 ON")
eq(b.skin, "gb_anim", "a flat skin pick beats an old game3 skin")
file = SaveData.loadOptions()
eq(file.game3.touchControls.skin, nil, "the stale game3 skin is dropped")
eq(file.game3.touchControls.enabled, nil, "the stale game3 switch is dropped")

seed({ enabled = true, skin = "gb_anim" }, { touchControls = { enabled = false, skin = "tv_crt", layouts = redLayout() } })
local c = boot()
eq(c.enabled, false, "an old game3 OFF carries over when flat is still ON by default")
eq(c.skin, "gb_anim", "while a flat skin pick is kept")

seed({ enabled = false }, { touchControls = { enabled = true, layouts = { portrait = { scale = 1 }, landscape = { scale = 1 } } } })
local d = boot()
eq(d.enabled, false, "an old editor peek block never turns the pad back on")
eq(SaveData.loadOptions().game3.touchControls.enabled, nil, "and its switch is dropped")

T.finish("game3_touch_carryover_F10b")
