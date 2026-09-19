-- #2328: the save screen's location header printed the engine's internal map
-- id ("FR_ROUTE_22") instead of the place name ("ROUTE 22").
--
-- The header drew `session.mapName or session.map`, and nothing in src/ ever
-- assigns session.mapName (only tests did), so the `or` chain always fell
-- through to the raw map id.  pret prints the sMapNames place name, resolved
-- from the map header's region map section:
--   pokefirered/src/start_menu.c    PrintSaveStats -> SAVE_STAT_LOCATION
--   pokefirered/src/save_menu_util.c GetMapNameGeneric(dest, gMapHeader.regionMapSectionId)
--   pokefirered/src/region_map.c    GetMapName(dst, mapsec, 0)   -- fill = 0
-- and centres it in the 14-tile stats window:
--   x = (112 - GetStringWidth(FONT_NORMAL, gStringVar4, -1)) / 2
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

-- The header is the only thing under test, so stand the frame/menu plumbing
-- down: nothing here needs a real window stack or a chrome image.
package.loaded["src.ui.game3.stack"] = {
  push = function() end, pop = function() end,
  busy = function() return false end, drawOrder = function() return {} end,
}
package.loaded["src.ui.game3.window"] = {
  template = function(l, t, w, h)
    return { left = l, top = t, width = w, height = h }
  end,
  stdFrame = function() end,
  cursorPx = function() end,
}
package.loaded["src.ui.game3.chrome"] = { dialogueFrame = function() end }

local SaveMenu = require("src.ui.game3.save_menu")
local FrlgFont = require("src.ui.game3.frlg_font")

eq(type(SaveMenu.locationName), "function", "SaveMenu.locationName exists")

-- --- the reported map resolves to its place name ----------------------------
-- regionMapSectionId values come from the game's own map headers.
local function gameWith(maps) return { data = { maps = maps } } end

SaveMenu._game = gameWith({
  FR_ROUTE_22 = { regionMapSectionId = 122 },
  FR_PALLET_TOWN = { regionMapSectionId = 88 },
  FR_CELADON_CITY_DEPARTMENT_STORE_1F = { regionMapSectionId = 94 },
  FR_POKEMON_MANSION = { regionMapSectionId = 135 },
})

eq(SaveMenu.locationName({ map = "FR_ROUTE_22" }), "ROUTE 22",
  "the reported map shows its place name, not the engine id")
check(SaveMenu.locationName({ map = "FR_ROUTE_22" }) ~= "FR_ROUTE_22",
  "the internal id is not shown verbatim (the reported bug)")
eq(SaveMenu.locationName({ map = "FR_PALLET_TOWN" }), "PALLET TOWN", "Pallet Town")
eq(SaveMenu.locationName({ map = "FR_POKEMON_MANSION" }), "POKéMON MANSION",
  "the mapsec name, accents and all, is what pret prints")
eq(SaveMenu.locationName({ map = "FR_CELADON_CITY_DEPARTMENT_STORE_1F" }), "CELADON DEPT.",
  "region_map.c's Celadon Dept. Store override still applies")
eq(SaveMenu.locationName({ mapName = "CUSTOM PLACE" }), "CUSTOM PLACE",
  "an explicit session.mapName still wins")
eq(SaveMenu.locationName({}), "PALLET TOWN", "a session with no map keeps the default")
eq(SaveMenu.locationName(nil), "PALLET TOWN", "a missing session keeps the default")

-- --- with no dataset loaded the map id is still resolved by name ------------
-- getInfo() fuzzy-matches the id against sMapNames; the match must be
-- deterministic, or "ROUTE_22" can land on "ROUTE 2" depending on pairs() order.
SaveMenu._game = nil
eq(SaveMenu.locationName({ map = "FR_ROUTE_22" }), "ROUTE 22",
  "the map id alone resolves, with no dataset and no arbitrary-match drift")
eq(SaveMenu.locationName({ map = "FR_PALLET_TOWN" }), "PALLET TOWN",
  "the map id alone resolves to Pallet Town")
local unknown = SaveMenu.locationName({ map = "FR_MOD_CUSTOM_CAVE" })
check(not unknown:find("FR_", 1, true), "an unknown map id never shows the engine prefix")
eq(unknown, "MOD CUSTOM CAVE", "an unknown map id falls back to a readable id")

-- --- the header is the resolved name, centred in the 14-tile window ---------
SaveMenu._game = gameWith({ FR_ROUTE_22 = { regionMapSectionId = 122 } })
local realDraw = FrlgFont.draw
local seen = {}
FrlgFont.draw = function(text, x, y, opts)
  seen[#seen + 1] = { text = text, x = x, y = y, maxWidth = opts and opts.maxWidth }
  return 0
end

SaveMenu.open = true
SaveMenu._session = { map = "FR_ROUTE_22", name = "RED" }
local ok, err = pcall(SaveMenu.draw)
SaveMenu.open = false
FrlgFont.draw = realDraw
check(ok, "the save screen draws headless: " .. tostring(err))

local header
for _, s in ipairs(seen) do
  if s.text == "ROUTE 22" then header = s end
end
check(header ~= nil, "the header is drawn as the resolved place name")

local BOX_X, BOX_W = 1 * 8, 14 * 8 -- sSaveStatsWindowTemplate (1, 1, 14, 9)
eq(header and header.y, 1 * 8 + 2, "header keeps its row")
eq(header and header.maxWidth, BOX_W, "header is clamped to the window, not 240px")
check(header and header.x >= BOX_X and header.x + FrlgFont.measure("ROUTE 22") <= BOX_X + BOX_W,
  "the centred header stays inside the window")

-- pret: x = (112 - GetStringWidth(FONT_NORMAL, text)) / 2, from the window's left edge
local nameW = FrlgFont.measure("ROUTE 22")
eq(header and header.x, BOX_X + math.floor((BOX_W - nameW) / 2),
  "header is centred like start_menu.c PrintSaveStats")

-- no place name pret can print may overflow the 112px box
for _, n in ipairs({
  "POKéMON MANSION", "VIRIDIAN FOREST", "UNDERGROUND PATH", "POKéMON LEAGUE",
  "DIGLETT'S CAVE", "MT. MOON", "SAFFRON CITY", "CELADON DEPT.",
}) do
  local w = FrlgFont.measure(n)
  check(w <= BOX_W, ("%q fits the 14-tile window (%dpx of %d)"):format(n, w, BOX_W))
end

T.finish("save_menu_location_bug2328")
