#!/usr/bin/env luajit
-- The summary's MOVES page gives each move name the room pret does: up to the
-- right edge of POKESUM_WIN_MOVES_3 (pokemon_summary_screen.c:857, :2543).
-- A fixed 64 px cut the cart's own longest names, and most translations.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check

require("src.core.GameVersion").set("firered")

package.loaded["src.core.game3.audio"] = {
  playSe = function() end, playCry = function() end,
  playSong = function() end, stopAll = function() end,
}

local gfx = setmetatable({}, { __index = function() return function() end end })
gfx.newQuad = function() return {} end
gfx.newImage = function() return nil end
gfx.getWidth = function() return 240 end
gfx.getHeight = function() return 160 end
_G.love = { graphics = gfx, timer = { getTime = function() return 0 end } }

local FrlgFont = require("src.ui.game3.frlg_font")
local SummaryMenu = require("src.ui.game3.summary_menu")
local SummaryChrome = require("src.ui.game3.summary_chrome")
for _, name in ipairs({ "drawPageBg", "drawShinyStar", "drawStatusIcon", "drawTypeBadge",
                        "drawHpBar", "drawExpBar", "drawPokerus", "drawMoveSelectionCursor" }) do
  SummaryChrome[name] = function() end
end

local drawn = {}
local realDraw = FrlgFont.draw
FrlgFont.draw = function(text, x, y, opts)
  drawn[#drawn + 1] = { text = text, x = x, y = y, maxWidth = opts and opts.maxWidth }
end

SummaryMenu.openMenu({ {
  species = 25, level = 30, hp = 50, maxHp = 50,
  stats = { hp = 50, attack = 30, defense = 30, spAttack = 30, spDefense = 30, speed = 30 },
  moves = { "SKY UPPERCUT", "GROWL" }, pp = { 15, 40 },
  otName = "RED", otId = 1, personality = 1,
} }, 1, { page = 2 })
SummaryMenu.draw()
SummaryMenu.close()
FrlgFont.draw = realDraw

local name
for _, call in ipairs(drawn) do
  if call.text == "SKY UPPERCUT" then name = call end
end
check(name ~= nil, "the MOVES page draws the move name")
if name then
  check(name.x + name.maxWidth == 240,
    ("a move name has up to the window's right edge (x %d + %d)"):format(name.x, name.maxWidth))
  check(name.maxWidth >= 72, "which fits the cart's own longest name, 72 px")
end

T.finish("game3_summary_move_name_width_test")
