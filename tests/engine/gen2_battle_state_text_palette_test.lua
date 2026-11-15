-- src/ui/gen2/BattleState.lua is the real Gen 2 battle screen (wired in
-- through Gen2Compat.lua's facade); it drew every label through flat
-- Chrome.print/cursor/printRight, never touching GbcPalette. Added
-- Chrome.printRightThrough alongside this fix since printRight had no
-- palette-aware counterpart.
--
-- No real shader runs headless, so this asserts on which seam gets called
-- rather than on rendered pixels. Exercises drawMoveInfoBox, drawStatsBox,
-- and drawPanel's no-battle fallback as representative cases.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")

love = require("tests.love_stub")

require("src.core.Logger").warn = function() end

local GbcPalette = require("src.render.GbcPalette")
local BattleState = require("src.ui.gen2.BattleState")

GbcPalette.available = function() return true end
GbcPalette.setCustomRamp({ { 255, 0, 255 }, { 200, 0, 200 }, { 100, 0, 100 },
                            { 0, 0, 0 } })

local function screen()
  return setmetatable({ game = { data = {
    text = require("tests.fixture_data.gen2_rom_text_s7_b").text() } } },
    { __index = BattleState })
end

local calls
local function spy(name)
  local original = GbcPalette[name]
  GbcPalette[name] = function(...)
    calls[name] = (calls[name] or 0) + 1
    return original(...)
  end
end

local function hits()
  return (calls.resolve or 0) + (calls.use or 0) + (calls.with or 0)
end

do
  calls = {}
  spy("resolve"); spy("use"); spy("with")
  BattleState.drawMoveInfoBox(screen(), { id = "TACKLE", pp = 10, maxPp = 35 })
  T.check(hits() > 0, "drawMoveInfoBox's TYPE/PP labels reach the GbcPalette seam")
end

do
  calls = {}
  spy("resolve"); spy("use"); spy("with")
  BattleState.drawMoveInfoBox(screen(), nil)
  T.eq(hits(), 0, "drawMoveInfoBox with no move draws nothing")
end

do
  local mon = { species = "RATTATA",
    stats = { attack = 10, defense = 9, specialAttack = 8, specialDefense = 8,
              speed = 12 } }
  calls = {}
  spy("resolve"); spy("use"); spy("with")
  BattleState.drawStatsBox(screen(), mon)
  T.check(hits() > 0, "drawStatsBox's stat names/numbers reach the GbcPalette seam")
end

do
  calls = {}
  spy("resolve"); spy("use"); spy("with")
  BattleState.drawPanel({ battle = nil, tutorial = false })
  T.check(hits() > 0, "drawPanel's NO BATTLE fallback reaches the GbcPalette seam")
end

T.finish()
