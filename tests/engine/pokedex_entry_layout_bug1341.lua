-- The Pokedex entry page laid out its fields at the port's own invented
-- coordinates instead of the cart's, ran the whole description together on
-- one page with no trailing full stop, and never let A/B advance past page
-- one (#1341).
-- engine/menus/pokedex.asm:399, home/text.asm:245 (<PAGE>), :204 (<DEXEND>)
--   luajit tests/engine/pokedex_entry_layout_bug1341.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

-- stub Font: DexEntryMenu draws through Font.draw/Font.drawCode only, and
-- the real Font needs loaded page images this suite has no reason to touch.
local calls = {}
package.loaded["src.render.Font"] = {
  draw = function(text, x, y) calls[#calls + 1] = { text = text, x = x, y = y } end,
  drawCode = function(code, x, y) calls[#calls + 1] = { code = code, x = x, y = y } end,
}

local DexEntryMenu = require("src.ui.DexEntryMenu")

local function hasText(text, x, y)
  for _, c in ipairs(calls) do
    if c.text == text and c.x == x and c.y == y then return true end
  end
  return false
end
local function hasCode(code, x, y)
  for _, c in ipairs(calls) do
    if c.code == code and c.x == x and c.y == y then return true end
  end
  return false
end

local game = {
  data = {
    pokemon = {
      BULBASAUR = {
        id = "BULBASAUR",
        name = "BULBASAUR",
        dex = 1,
        dexEntry = {
          kind = "SEED POKEMON",
          heightFt = 2, heightIn = 4, weight = 69,
          text = "_BulbasaurDexEntry",
        },
      },
    },
    text = {
      -- \f is the extractor's <PAGE> break; two pages, three lines each
      _BulbasaurDexEntry = "A strange seed was\nplanted on its\nback at birth\f"
        .. "The plant sprouts\nand grows with\nthis POKEMON",
    },
    constants = { dexDigits = 3 },
  },
  save = { pokedex = { owned = { BULBASAUR = true } } },
}

local ns = DexEntryMenu.new(game, "BULBASAUR")
eq(ns.pageCount, 2, "the entry has two <PAGE>-separated pages")
eq(ns.page, 1, "starts on page 1")

ns:draw()
check(hasText("BULBASAUR", 72, 16), "name at (72,16), not the port's old (72,8)")
check(hasText("SEED POKEMON", 72, 32), "kind at (72,32)")
check(hasText("No.001", 16, 64), "dex number under the pic, at (16,64)")
check(hasText("HT", 72, 48), "HT label at (72,48)")
check(hasText(" 2", 96, 48), "feet in cols 12-13")
check(hasText("04", 120, 48), "inches in cols 15-16")
check(hasText("WT", 72, 64), "WT label at (72,64)")
check(hasText("   6.9", 88, 64), "weight right-aligned into cols 11-16")
check(hasText("A strange seed was", 8, 88), "page 1 line 1 at y=88 (row 11)")
check(hasText("planted on its", 8, 104), "page 1 line 2 at y=104")
check(hasText("back at birth", 8, 120), "page 1 line 3, unmodified: not the last page")
check(hasCode(0xEE, 144, 128), "the more-below arrow shows on a non-final page")

-- A on a non-final page turns it, it does not close the screen
local popped, doneCalled = false, false
game.stack = { pop = function() popped = true end }
game.input = { wasPressed = function(_, b) return b == "a" end }
ns.onDone = function() doneCalled = true end
ns:update(0)
eq(ns.page, 2, "A advances to page 2 instead of closing")
check(not popped, "the screen did not pop on a non-final page")

calls = {}
ns:draw()
check(hasText("this POKEMON.", 8, 120), "the final page's last line gets the trailing full stop")
check(not hasCode(0xEE, 144, 128), "no more-below arrow on the last page")

-- A on the final page closes the screen
ns:update(0)
check(popped, "A on the final page pops the screen")
check(doneCalled, "onDone fires once the last page closes")

T.finish("pokedex entry layout bug 1341")
