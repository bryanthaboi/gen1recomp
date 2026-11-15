-- BattleState:drawTextArea drew the FIGHT/ITEM/RUN command box with a flat
-- setColor, the same gap TextBox.lua had. Gen 1 gets colour from
-- PaletteFX's whole-frame remap, but Gen 2 has no such pass outside
-- CLASSIC mode, so the command box needed its own fix.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")

love = require("tests.love_stub")

require("src.core.Logger").warn = function() end

local GbcPalette = require("src.render.GbcPalette")
local BattleState = require("src.battle.BattleState")

GbcPalette.available = function() return true end
GbcPalette.setCustomRamp({ { 255, 0, 255 }, { 200, 0, 200 }, { 100, 0, 100 },
                            { 0, 0, 0 } })

local calls
local function spy(name)
  local original = GbcPalette[name]
  GbcPalette[name] = function(...)
    calls[name] = (calls[name] or 0) + 1
    return original(...)
  end
end

local function fakeState()
  return setmetatable({
    phase = "menu", menuIndex = 1, safari = nil, demo = false,
    bottomUIVisible = function() return true end,
    game = { save = { generation = 2, version = "gold" } },
    data = { text = dofile("tests/fixture_data/text.lua") },
  }, { __index = BattleState })
end

do
  calls = {}
  spy("resolve"); spy("use"); spy("with")
  BattleState.drawTextArea(fakeState())
  T.check((calls.resolve or 0) > 0 or (calls.use or 0) > 0 or (calls.with or 0) > 0,
    "Gen 2 battle command box reaches the GbcPalette seam")
end

-- Gen 1 recolours through PaletteFX's whole-frame zone remap, not per draw
-- call, so this must stay untouched. Same guard gen2_textbox_palette_test
-- checks for TextBox.
do
  calls = {}
  spy("resolve"); spy("use"); spy("with")
  local state = fakeState()
  state.game = { save = { generation = 1, version = "red" } }
  BattleState.drawTextArea(state)
  T.eq((calls.resolve or 0) + (calls.use or 0) + (calls.with or 0), 0,
    "Gen 1 battle command box is untouched, it never calls GbcPalette")
end

T.finish()
