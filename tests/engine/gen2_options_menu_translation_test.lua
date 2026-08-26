-- Gold's OPTION screen (src/ui/gen2/OptionsMenu.lua) used to draw every row
-- label -- and the cart-original value strings (FAST/MID/SLOW, ON/OFF,
-- SHIFT/SET, ...) -- as bare literals baked into the module-level ROWS
-- table, invisible to a translation mod's `strings` registry (reported
-- against a real Gold build, gen1recomp#1642). This drives
-- OptionsMenu:drawPanel() with a mod-loaded Strings catalog and checks the
-- translated text reaches Font.draw, for both a cart-original row (label +
-- display value) and a port-added row (label only -- its value already
-- comes pre-translated from the shared module it calls, same as the Gen 1
-- OPTION screen's equivalent rows), plus a vanilla no-mod case proving the
-- fallback is unchanged.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")

love = require("tests.love_stub")

require("src.core.Logger").warn = function() end

-- Chrome.print (the only draw call this screen makes) goes straight to
-- Font.draw, so recording that call is enough to see exactly what text
-- reached the screen -- same technique as
-- tests/engine/status_abbreviation_translation_test.lua.  Stubbed before
-- OptionsMenu (and the Chrome module it requires) ever loads, so Chrome's
-- own `local Font = require(...)` captures this stub instead of the real
-- module.
local drawn
package.loaded["src.render.Font"] = {
  draw = function(text, x, y)
    drawn[#drawn + 1] = { text = text, x = x, y = y }
  end,
  drawCode = function() end,
  drawBox = function() end,
}

local OptionsMenu = require("src.ui.gen2.OptionsMenu")
local Strings = require("src.core.Strings")

local function drawnAt(x, y)
  for _, d in ipairs(drawn) do
    if d.x == x and d.y == y then return d.text end
  end
  return nil
end

-- Chrome.print multiplies tile coordinates by 8 (src/ui/gen2/Chrome.lua);
-- drawPanel puts labels at tile x=2 and values at tile x=11.
local LABEL_X = 2 * 8
local VALUE_X = 11 * 8

local function rowIndex(rows, id)
  for i, row in ipairs(rows) do
    if row.id == id then return i end
  end
end

-- ---------------------------------------------- vanilla: no mod catalog
do
  local menu = OptionsMenu.new({})
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(LABEL_X, 2 * 8), "TEXT SPEED",
    "row 1's label draws in English with no mod loaded")
  -- Save.DEFAULT_OPTIONS.textSpeed is "MID", the cart's own default.
  T.eq(drawnAt(VALUE_X, 3 * 8), "MID ",
    "and its cart-original display value too")
end

-- ------------------------------------------------- a translation mod's turn
do
  Strings.load({
    strings = {
      ["TEXT SPEED"] = "VITESSE TEXTE",
      ["MID "] = "MOY ",
      ["CONTROLS"] = "COMMANDES",
      ["CANCEL"] = "ANNULER",
    },
  })

  local menu = OptionsMenu.new({})
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(LABEL_X, 2 * 8), "VITESSE TEXTE",
    "a mod catalog reaches a cart-original row's label")
  T.eq(drawnAt(VALUE_X, 3 * 8), "MOY ",
    "and its cart-original display value")

  -- CONTROLS is the first port-added row; scroll to it so it lands in the
  -- VISIBLE_ROWS=7 window drawPanel actually draws.
  local index = rowIndex(menu.rows, "controls")
  T.check(index ~= nil, "CONTROLS is one of the rows")
  menu.index = index
  menu:ensureVisible()
  drawn = {}
  menu:drawPanel()
  local slot = index - menu.scroll
  T.eq(drawnAt(LABEL_X, (2 + (slot - 1) * 2) * 8), "COMMANDES",
    "and a port-added row's label is translated too")

  -- CANCEL is the last row, built into ROWS like any other -- there is no
  -- separate hook to fall through if this one row is missed.
  local cancelMenu = OptionsMenu.new({})
  local cancelIndex = #cancelMenu.rows
  T.check(cancelMenu.rows[cancelIndex].cancel, "the last row is CANCEL")
  cancelMenu.index = cancelIndex
  cancelMenu:ensureVisible()
  drawn = {}
  cancelMenu:drawPanel()
  local cancelSlot = cancelIndex - cancelMenu.scroll
  T.eq(drawnAt(LABEL_X, (2 + (cancelSlot - 1) * 2) * 8), "ANNULER",
    "CANCEL, the way out of the menu, is translated too")

  -- Module state is process-global (see tests/gen2_clock_test.lua's own
  -- note); this suite gets its own process from tests/tier_runner.lua, but
  -- leaving the catalog loaded past this point would still mistranslate
  -- every check below it in this file.
  Strings.load({})
  T.check(not Strings.active(), "the catalog is unloaded for the checks after this one")
end

T.finish("gen2_options_menu_translation_test")
