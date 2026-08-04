-- The Pokédex seen/own footer survives three-digit counts (#639).
-- engine/menus/pokedex.asm HandlePokedexListMenu prints both counts into a
-- fixed three-digit field (`lb bc, 1, 3` at hlcoord 16,3 and 16,6) under
-- PokedexSeenText / PokedexOwnText, so the line never changes width as the
-- dex fills.  The port built "SEEN %d  OWNED %d", which is 19 glyphs once
-- either count reaches 100: one column over the text box, so ListMenu's
-- bare footer paginated it into two lines and drew the first at y=120,
-- on top of the list's last row.
-- ROM-free: the real PokedexMenu over a synthetic 151-entry dex.
--   luajit tests/engine/pokedex_counts_bug639.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local check, eq = T.check, T.eq
local Data = T.fixtures.load()

local PokedexMenu = require("src.ui.PokedexMenu")
local SaveData = require("src.core.SaveData")
local StateStack = require("src.core.StateStack")
local TextBox = require("src.render.TextBox")

-- A full Kanto numbering, which the fixture dataset deliberately does not
-- carry (tests/fixture_data/constants.lua caps dexSize at 3).  Everything
-- the menu reads off a species is here: id, name, dex number.
local DEX_SIZE = 151
local dexData = setmetatable({
  pokemon = {},
  constants = { dexSize = DEX_SIZE, dexDigits = 3 },
}, { __index = Data })
for n = 1, DEX_SIZE do
  local id = ("DEXMON_%03d"):format(n)
  dexData.pokemon[id] = { id = id, name = ("MON%03d"):format(n), dex = n }
end

-- builds the dex list the way Screens does, with the first `ownedCount`
-- species owned and the next `seenOnly` species seen but not caught
local function footerFor(ownedCount, seenOnly)
  local stack = setmetatable({}, { __index = StateStack })
  stack:init()
  local save = SaveData.newGame()
  save.pokedex = { seen = {}, owned = {} }
  for n = 1, ownedCount do
    local id = ("DEXMON_%03d"):format(n)
    save.pokedex.seen[id] = true
    save.pokedex.owned[id] = true
  end
  for n = ownedCount + 1, ownedCount + seenOnly do
    save.pokedex.seen[("DEXMON_%03d"):format(n)] = true
  end
  local game = { data = dexData, save = save, stack = stack }
  return PokedexMenu.new(game, {}).footer
end

-- how many lines ListMenu's bare-footer branch would end up drawing: it
-- flattens every paginated line and, at two or more, starts them at y=120
-- instead of y=136, which is the row the last list entry sits on
local function lines(text)
  local flat = {}
  for _, page in ipairs(TextBox.paginate(text)) do
    for _, line in ipairs(page) do flat[#flat + 1] = line end
  end
  return flat
end

-- --------------------------------------------------------- 100 or more
local hundred = footerFor(100, 5)
eq(hundred, "SEEN 105  OWN 100", "105 seen / 100 owned prints both counts")
eq(#lines(hundred), 1, "the three-digit footer still fits on one line")

local full = footerFor(DEX_SIZE, 0)
eq(full, "SEEN 151  OWN 151", "a completed dex prints 151 twice")
eq(#lines(full), 1, "the widest possible footer still fits on one line")

-- The witness for the bug: the string this replaced is one column over the
-- 18-column box, so it wrapped and the wrap is what collided with the list.
eq(#lines("SEEN 105  OWNED 100"), 2,
   "the old OWNED wording is what pushed the footer onto a second line")

-- --------------------------------------------------------- under 100
-- The field is fixed width, so a small dex right-aligns into the same
-- columns rather than sliding left as it grows.
local small = footerFor(3, 6)
eq(small, "SEEN   9  OWN   3", "single digits keep the three-wide field")
eq(#lines(small), 1, "a small dex is one line too")
eq(#small, #hundred, "the footer is the same width empty or full")
check(small:find("OWN ") == hundred:find("OWN "),
      "OWN starts in the same column at 3 caught and at 100")

T.finish("pokedex_counts_bug639")
