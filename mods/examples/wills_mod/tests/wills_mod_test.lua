-- Encounters Guide gallery suite: loads the bundled entry through the real loader
-- and asserts the stated effects: two read-only overlay hooks, a PKMN MAP
-- START-menu row, and the screen family resolving through the registry.
--
-- Standalone: luajit mods/examples/wills_mod/tests/wills_mod_test.lua
-- (or: POKEPORT_DATA_DIR=... /tmp/love-luajit mods/examples/wills_mod/tests/wills_mod_test.lua)
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Runtime = require("src.mods.Runtime")
local Data = require("src.core.Data")

-- Assemble a ROM-free dataset the same way the fixture base does (methods
-- only, fresh tables, defaults seeded) so this suite runs with no ROM and
-- no data/generated/ directory.
local function fixtureData()
  local methods = {}
  for key, value in pairs(Data) do
    if type(value) == "function" then methods[key] = value end
  end
  local set = setmetatable({}, { __index = methods })
  local fixture = require("tests.fixture_data").load()
  for name, mod in pairs(fixture) do set[name] = mod end
  Data.seedDefaults(set)
  return set
end
local data = fixtureData()

local run = T.sdk.loadMod("mods/examples/wills_mod", { data = data })
T.eq(#run.errors, 0, "loads clean (" .. tostring(run.errors[1]) .. ")")

-- ------- the two read-only overlays and the options rows are wrapped

T.check(Runtime.wantsHook("battle.overlay"), "battle.overlay is wrapped")
T.check(Runtime.wantsHook("render.hud"), "render.hud is wrapped")
T.check(Runtime.wantsHook("ui.options.rows"), "the options rows are wrapped")

-- ------- the START menu gains exactly one row, anchored before SAVE

local vanilla = { { label = "POKéDEX" }, { label = "SAVE" }, { label = "QUIT" } }
local hooked = Runtime.call("ui.start_menu.items",
  function(_, items) return items end, { data = data, save = {} }, vanilla)
T.eq(#hooked, 4, "the wrap added exactly one row")
T.eq(hooked[2].label, "PKMN MAP", "the row is anchored before SAVE")
T.eq(hooked[3].label, "SAVE", "the vanilla rows are still in order")

-- ------- the PKMN MAP screen resolves through the registry

local Screens = require("src.ui.Screens")
Screens.invalidate()
local factory = Screens.get({ data = data, save = {} }, "EncounterGuideMap")
T.check(factory and factory.new,
  "the PKMN MAP screen resolves through the registry")

run.release()
Screens.invalidate()
T.finish("wills_mod")
