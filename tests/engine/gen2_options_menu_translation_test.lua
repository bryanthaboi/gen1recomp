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
_G.POKEPORT_LOOP_PANEL_SYNC = true

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

-- TEXT SPEED and the other cart rows live on a group page now, so the
-- screen a row draws on is the page its group opens, not the top level.
local function pageFor(menu, id)
  for _, row in ipairs(menu.view) do
    if row.group then
      row.activate(menu.game)
      local page = menu.game.stack:top()
      if rowIndex(page.view, id) then return page end
      menu.game.stack:pop()
    end
  end
end

local function fakeGame()
  local stack = { items = {} }
  function stack:push(s) self.items[#self.items + 1] = s; return s end
  function stack:pop() self.items[#self.items] = nil end
  function stack:top() return self.items[#self.items] end
  return { stack = stack }
end

-- ---------------------------------------------- vanilla: no mod catalog
do
  local menu = OptionsMenu.new(fakeGame())
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(LABEL_X, 2 * 8), "SPEED",
    "row 1 is the SPEED group with no mod loaded")

  local page = pageFor(menu, "textSpeed")
  T.check(page ~= nil, "TEXT SPEED is on a group page")
  drawn = {}
  page:drawPanel()
  T.eq(drawnAt(LABEL_X, 2 * 8), "TEXT SPEED",
    "the page's first label draws in English")
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
      ["SPEED"] = "VITESSE",
      ["BACK"] = "RETOUR",
      ["AUTO"] = "AUTO-FR",
      ["GEN 2"] = "GEN2-FR",
      ["OFF"] = "SANS",
      ["GREEN"] = "VERT",
      ["DISPLAY (%dHZ)"] = "ECRAN %dHZ",
    },
  })

  local menu = OptionsMenu.new(fakeGame())
  drawn = {}
  menu:drawPanel()
  T.eq(drawnAt(LABEL_X, 2 * 8), "VITESSE",
    "a mod catalog reaches a group opener's label too")

  local page = pageFor(menu, "textSpeed")
  drawn = {}
  page:drawPanel()
  T.eq(drawnAt(LABEL_X, 2 * 8), "VITESSE TEXTE",
    "a mod catalog reaches a cart-original row's label")
  T.eq(drawnAt(VALUE_X, 3 * 8), "MOY ",
    "and its cart-original display value")

  local index = rowIndex(menu.view, "controls")
  T.check(index ~= nil, "CONTROLS is one of the rows")
  menu.index = index
  menu:ensureVisible()
  drawn = {}
  menu:drawPanel()
  local slot = index - menu.scroll
  T.eq(drawnAt(LABEL_X, (2 + (slot - 1) * 2) * 8), "COMMANDES",
    "and a port-added row's label is translated too")

  -- BACK is the last row, built into ROWS like any other -- there is no
  -- separate hook to fall through if this one row is missed.
  local cancelMenu = OptionsMenu.new(fakeGame())
  local cancelIndex = #cancelMenu.view
  T.check(cancelMenu.view[cancelIndex].cancel, "the last row is BACK")
  cancelMenu.index = cancelIndex
  cancelMenu:ensureVisible()
  drawn = {}
  cancelMenu:drawPanel()
  local cancelY = -1
  for _, entry in ipairs(cancelMenu:layout()) do
    if entry.index == cancelIndex then cancelY = entry.labelY end
  end
  T.eq(drawnAt(LABEL_X, cancelY * 8), "RETOUR",
    "CANCEL, the way out of the menu, is translated too")

  -- Port-added finite values used to be returned by helper modules after the
  -- only Strings lookup in drawPanel had already happened.  They must pass
  -- through the catalog at draw time as well.
  local performance = menu:focusRow("performance")
  drawn = {}
  performance:drawPanel()
  local performanceSlot = performance.index - performance.scroll
  T.eq(drawnAt(VALUE_X, (3 + (performanceSlot - 1) * 2) * 8),
    "AUTO-FR", "a helper-produced PERFORMANCE value is translated")

  local color = menu:focusRow("color")
  color.options.palette = ""
  color.options.color = "gbc"
  drawn = {}
  color:drawPanel()
  local colorSlot = color.index - color.scroll
  T.eq(drawnAt(VALUE_X, (3 + (colorSlot - 1) * 2) * 8), "GEN2-FR",
    "a finite built-in COLOR mode is translated")

  color.options.palette = "m:9bbc0f"
  T.eq(color:row().text(color.options), "VERT",
    "an engine-provided monochrome palette label is translated")

  local filter = menu:focusRow("musicFilter")
  filter.options.musicFilter = 0
  T.eq(filter:row().text(filter.options), "SANS",
    "MUSIC FILTER resolves its finite value through Strings at runtime")

  local fps = menu:focusRow("fpsCap")
  local RefreshRate = require("src.core.RefreshRate")
  local priorMismatch = RefreshRate.mismatch
  RefreshRate.mismatch = function() return 59 end
  fps.options.fpsCap = 0
  T.eq(fps:row().text(fps.options), "ECRAN 59HZ",
    "DISPLAY retains its refresh-rate suffix through a localizable template")
  RefreshRate.mismatch = priorMismatch

  -- A user palette name is content, not a finite engine enum.  It must stay
  -- verbatim even if a catalog happens to contain an identically named key.
  Strings.load({ strings = {
    ["My Palette"] = "NE PAS TRADUIRE",
  } })
  color.options.palette = "p:custom/My Palette"
  drawn = {}
  color:drawPanel()
  T.eq(drawnAt(VALUE_X, (3 + (colorSlot - 1) * 2) * 8), "My Palet",
    "a user palette name stays raw (and is only clipped to the value width)")

  -- Module state is process-global (see tests/gen2_clock_test.lua's own
  -- note); this suite gets its own process from tests/tier_runner.lua, but
  -- leaving the catalog loaded past this point would still mistranslate
  -- every check below it in this file.
  Strings.load({})
  T.check(not Strings.active(), "the catalog is unloaded for the checks after this one")
end

T.finish("gen2_options_menu_translation_test")
