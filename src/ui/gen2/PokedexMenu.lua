-- Gen 2 #DEX, transcribed from engine/pokedex/pokedex.asm.
--
-- The main screen is two layers, which is the thing to understand before any
-- coordinate in here makes sense:
--
--   * The **background** holds the frontpic box, the SEEN/OWN box, the
--     vertical rule at column 8 and the bottom caption, and it is scrolled
--     left by POKEDEX_SCX (5 pixels).  So background tile column 0 lands at
--     screen x -5.
--   * The **window** holds the listing.  Pokedex_InitMainScreen sets hWX to
--     $47 (or $4a in OLD mode) and hWY to 0, so the window's own column 0 is
--     at screen x 64 (67 in OLD mode) and it covers the full height.  Twelve
--     of its columns fit on screen, which is exactly the 11-wide list plus
--     its scroll bar.
--
-- Both layers are written through the same wTilemap buffer and copied to
-- vBGMap0 / vBGMap1 at different times, which is why every hlcoord in the ASM
-- reads as if it were the only screen.
--
-- Everything the screens draw comes out of one 64-tile sheet decompressed
-- over vTiles2 tile $31, plus an *inverted* font: Pokedex_LoadInvertedFont
-- flips both bitplanes of the standard font, so under PREDEFPAL_POKEDEX
-- (white, orange, dark red, black) the dex prints white on black.  Here that
-- is Chrome.printInverted, which draws the ordinary font page through the
-- reversed palette; the inverted ' ' cell is a solid black tile no sheet
-- carries, so PokedexMenu:blank paints it.
--
-- Gold's dex sorts three ways -- NEW (Johto order), OLD (national, and the
-- only mode that prints numbers) and A-Z.  SELECT opens the option screen on
-- the cart; here it cycles the mode directly.

local Assets = require("src.render.Assets")
local Chrome = require("src.ui.gen2.Chrome")
local GbcPalette = require("src.render.GbcPalette")
local Palettes = require("src.world.gen2.Palettes")
local TileSheet = require("src.ui.gen2.TileSheet")
local Nests = require("src.core.gen2.Nests")
local Sound = require("src.core.Sound")
local Unown = require("src.core.gen2.Unown")

local PokedexMenu = {}
PokedexMenu.__index = PokedexMenu
PokedexMenu.isOpaque = true

-- wDexListingHeight is set to 7 by Pokedex_InitMainScreen.
local VISIBLE_ROWS = 7
local MODES = { "NEW", "OLD", "A-Z" }

-- DexEntryScreen_ArrowCursorData, in its own order. PRNT is listed because the
-- cursor stops on it; the port has no Game Boy Printer to send anything to.
local ENTRY_ACTIONS = { "PAGE", "AREA", "CRY", "PRNT" }
-- The four dwcoord columns the arrow parks in, row 17.
local ENTRY_ACTION_X = { 1, 6, 11, 15 }

-- engine/pokedex/pokedex.asm POKEDEX_SCX.
local SCX = 5
-- hWX values, less the hardware's 7-pixel bias.
local WINDOW_X = { NEW = 0x47 - 7, OLD = 0x4a - 7, ["A-Z"] = 0x47 - 7 }

-- Tile ids out of the dex sheet, named after what the routines use them for.
local TILE_BG = 0x32
local TILE_BORDER = { -- Pokedex_PlaceBorder
  topLeft = 0x33, top = 0x34, topRight = 0x35,
  left = 0x36, right = 0x37,
  bottomLeft = 0x38, bottom = 0x39, bottomRight = 0x3a,
}
local TILE_CAUGHT = 0x4f
local TILE_FOOT = 0x5e
local TILE_INCH = 0x5f
local TILE_NO = { 0x5c, 0x5d }
local TILE_DIVIDER = 0x61
local TILE_PAGE_TOP = 0x55
local TILE_PAGE_P = 0x56
local TILE_PAGE_DIGIT = { 0x57, 0x58 }

-- String_SELECT_OPTION falls through into String_START_SEARCH with no
-- terminator between them, so placing it at (1,17) writes all 18 tiles.
local BOTTOM_CAPTION = {
  0x3b, 0x48, 0x49, 0x4a, 0x44, 0x45, 0x46, 0x47,
  0x3c, 0x3b, 0x41, 0x42, 0x43, 0x4b, 0x4c, 0x4d, 0x4e, 0x3c,
}
-- ...and the window gets its own copy of just the START > SEARCH half.
local WINDOW_CAPTION = { 0x3c, 0x3b, 0x41, 0x42, 0x43, 0x4b, 0x4c, 0x4d, 0x4e, 0x3c }

-- Pokedex_PutNewModeABCModeCursorOAM / Pokedex_PutOldModeCursorOAM, as
-- { screen x, screen y, tile, xflip, yflip }.  dbsprite emits y first and the
-- values are OAM coordinates, so screen space is (x - 8, y - 16); the cursor
-- row adds 16 pixels per step, which Pokedex_LoadCursorOAM does with a
-- `swap a` on the low three bits.
local function sprite(xTile, yTile, xPixel, yPixel, tile, xflip, yflip)
  return {
    x = xTile * 8 + xPixel - 8,
    y = yTile * 8 + yPixel - 16,
    tile = tile, xflip = xflip, yflip = yflip,
  }
end

local CURSOR_OAM = {
  sprite(9, 3, -1, 3, 0x30), sprite(9, 2, -1, 3, 0x31),
  sprite(10, 2, -1, 3, 0x32), sprite(11, 2, -1, 3, 0x32),
  sprite(12, 2, -1, 3, 0x33),
  sprite(16, 2, 0, 3, 0x33, true), sprite(17, 2, 0, 3, 0x32, true),
  sprite(18, 2, 0, 3, 0x32, true), sprite(19, 2, 0, 3, 0x31, true),
  sprite(19, 3, 0, 3, 0x30, true),
  sprite(9, 4, -1, 3, 0x30, false, true), sprite(9, 5, -1, 3, 0x31, false, true),
  sprite(10, 5, -1, 3, 0x32, false, true), sprite(11, 5, -1, 3, 0x32, false, true),
  sprite(12, 5, -1, 3, 0x33, false, true),
  sprite(16, 5, 0, 3, 0x33, true, true), sprite(17, 5, 0, 3, 0x32, true, true),
  sprite(18, 5, 0, 3, 0x32, true, true), sprite(19, 5, 0, 3, 0x31, true, true),
  sprite(19, 4, 0, 3, 0x30, true, true),
}

local CURSOR_OAM_OLD = {
  sprite(9, 3, -1, 0, 0x30), sprite(9, 2, -1, 0, 0x31),
  sprite(10, 2, -1, 0, 0x32), sprite(11, 2, -1, 0, 0x32),
  sprite(12, 2, -1, 0, 0x32), sprite(13, 2, -1, 0, 0x33),
  sprite(16, 2, -2, 0, 0x33, true), sprite(17, 2, -2, 0, 0x32, true),
  sprite(18, 2, -2, 0, 0x32, true), sprite(19, 2, -2, 0, 0x32, true),
  sprite(20, 2, -2, 0, 0x31, true), sprite(20, 3, -2, 0, 0x30, true),
  sprite(9, 4, -1, 0, 0x30, false, true), sprite(9, 5, -1, 0, 0x31, false, true),
  sprite(10, 5, -1, 0, 0x32, false, true), sprite(11, 5, -1, 0, 0x32, false, true),
  sprite(12, 5, -1, 0, 0x32, false, true), sprite(13, 5, -1, 0, 0x33, false, true),
  sprite(16, 5, -2, 0, 0x33, true, true), sprite(17, 5, -2, 0, 0x32, true, true),
  sprite(18, 5, -2, 0, 0x32, true, true), sprite(19, 5, -2, 0, 0x32, true, true),
  sprite(20, 5, -2, 0, 0x31, true, true), sprite(20, 4, -2, 0, 0x30, true, true),
}

-- Pokedex_PutScrollbarOAM: one OBJ, tile $0f, x 161, y from 20 to 141.
local SCROLLBAR_TILE = 0x0f
local SCROLLBAR_X = 161 - 8
local SCROLLBAR_TOP = 20 - 16
local SCROLLBAR_TRAVEL = 121

function PokedexMenu:wantsFillScale() return true end
function PokedexMenu:drawsWidescreen() return true end

-- opts: save, pokedex (pokedex.lua), pokemon (pokemon.lua), palettes,
-- menuGfx (menu_gfx.lua), onClose(), entrySpecies (open straight on that
-- species' ENTRY screen, the way `predef NewPokedexEntry` does), newEntry (the
-- two-page NewPokedexEntry viewing, no action bar)
function PokedexMenu.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, PokedexMenu)
  self.game = game
  self.save = opts.save or (game and game.save)
  local data = game and game.data or {}
  -- engine/pokedex/pokedex.asm:447
  self.data = data
  self.dex = opts.pokedex or data.gen2Pokedex
  self.pokemon = opts.pokemon or data.pokemon
  self.palettes = opts.palettes or data.gen2Palettes
  self.onClose = opts.onClose
  -- InitPokedex: wLastDexMode -> wCurDexMode (engine/pokedex/pokedex.asm:97).
  self.modeIndex = 1
  for i, name in ipairs(MODES) do
    if self.save and name == self.save.lastDexMode then self.modeIndex = i end
  end
  self.index = 1
  self.scroll = 0
  self.view = "list" -- list | entry | area | option | search | results | unown
  self.page = 1
  self.entryAction = 1
  self.picCache = {}
  -- The OPTION and SEARCH screens' own cursors, and wDexCurUnownIndex -- the
  -- slot UNOWN MODE's cursor sits on, 0-based like the cart's.
  self.optionIndex = 1
  self.searchIndex = 1
  self.unownIndex = 0
  -- wDexSearchMonType1 starts at NORMAL + 1 and TYPE2 at 0 ("-----").
  self.searchType = { 1, 0 }
  self.searchResults = nil

  local gfx = (opts.menuGfx or data.gen2MenuGfx or {}).pokedex
  self.gfx = gfx
  if gfx then
    self.sheet = TileSheet.new({
      path = gfx.tiles, wide = gfx.tilesWide or 16,
      firstTile = gfx.firstTile or 0x31, palette = gfx.palette,
    })
    self.objs = TileSheet.new({
      path = gfx.objs, wide = gfx.objsWide or 16,
      firstTile = 0, palette = gfx.cursorPalette,
    })
    -- Kept as the raw palette, not two colours: the COLOR option substitutes
    -- palettes at draw time, so picking colours out of one here would freeze
    -- the dex's ink and paper at whatever mode was live when it opened.
    self.dexPalette = gfx.palette
  end

  -- pokegold engine/pokegear/pokegear.asm Pokedex_GetArea: the AREA page
  -- draws through the Pokegear's own town-map tiles and TownMapPals, not the
  -- dex's PokedexLZ sheet.
  local mapGfx = (opts.menuGfx or data.gen2MenuGfx or {}).pokegear
  self.mapGfx = mapGfx
  if mapGfx then
    self.mapSheet = TileSheet.new({
      path = mapGfx.tiles, wide = mapGfx.tilesWide or 16, firstTile = 0,
      paletteFor = function(tile)
        if not mapGfx.palettes then return nil end
        if tile >= 0x60 then return mapGfx.palettes[1] end
        return mapGfx.palettes[(mapGfx.palMap and mapGfx.palMap[tile + 1]) or 1]
      end,
    })
  end

  -- Pokedex_LoadUnownFont: 27 tiles at vTiles2 tile FIRST_UNOWN_CHAR, live
  -- only while UNOWN MODE is on screen.  It is a sheet rather than a font
  -- page (see PokedexMenu:unownGlyph), and it draws through the dex palette
  -- REVERSED, because the routine inverts the tiles on their way into VRAM
  -- the same way Pokedex_LoadInvertedFont inverts the ordinary font.
  local font = opts.font or data.font
  if font and font.imageUnown and gfx then
    self.unownFontBase = font.unownBase or 0x40
    self.unownFont = TileSheet.new({
      path = font.imageUnown, wide = font.unownWide or 3,
      firstTile = font.unownBase or 0x40,
      paletteFor = function()
        local pal = self.dexPalette
        if not pal then return nil end
        return { pal[4], pal[3], pal[2], pal[1] }
      end,
    })
  end
  self:rebuild()
  -- NewPokedexEntry (engine/items/item_effects.asm:534-542): catching a mon the
  -- player did not already own runs the dex straight into that species' ENTRY
  -- screen rather than the listing.  Set after rebuild because the row index is
  -- only meaningful once the rows exist.
  if opts.entrySpecies then
    for index, row in ipairs(self.rows) do
      if row.species == opts.entrySpecies then
        self.index = index
        self.view = "entry"
        self.page = 1
        self:ensureVisible()
        break
      end
    end
    -- _NewPokedexEntry's own tail: `ld a, [wCurPartySpecies] / call PlayMonCry`
    -- (engine/pokedex/pokedex.asm:2554-2555).
    if opts.newEntry and self.view == "entry" then
      self.newEntry = true
      self:playCry(opts.entrySpecies)
    end
  end
  return self
end

function PokedexMenu:mode()
  return MODES[self.modeIndex]
end

function PokedexMenu:styled()
  return self.sheet ~= nil and self.sheet:available()
end

-- The species list in the current sort order.  OLD is the national (index)
-- order, which for Gen 2 is just speciesOrder.
function PokedexMenu:order()
  local dex = self.dex
  if not dex then return {} end
  local mode = self:mode()
  if mode == "NEW" and dex.newOrder then return dex.newOrder end
  if mode == "A-Z" and dex.alphabeticalOrder then return dex.alphabeticalOrder end
  local out = {}
  for species, entry in pairs(dex.entries or {}) do
    out[entry.dex or #out + 1] = species
  end
  return out
end

function PokedexMenu:rebuild()
  local seen = (self.save and self.save.pokedex and self.save.pokedex.seen) or {}
  local caught = (self.save and self.save.pokedex and self.save.pokedex.caught)
    or {}
  local rows = {}
  for _, species in ipairs(self:order()) do
    local entry = self.dex and self.dex.entries and self.dex.entries[species]
    if entry then
      rows[#rows + 1] = {
        species = species,
        dex = entry.dex,
        seen = seen[species] == true,
        caught = caught[species] == true,
      }
    end
  end
  self.rows = rows
  self.index = math.max(1, math.min(self.index, math.max(1, #rows)))
  self:ensureVisible()
end

function PokedexMenu:ensureVisible()
  if self.index <= self.scroll then
    self.scroll = self.index - 1
  elseif self.index > self.scroll + VISIBLE_ROWS then
    self.scroll = self.index - VISIBLE_ROWS
  end
  self.scroll = math.max(0, math.min(self.scroll,
    math.max(0, #self.rows - VISIBLE_ROWS)))
end

function PokedexMenu:current()
  return self.rows[self.index]
end

function PokedexMenu:totals()
  local seen, caught = 0, 0
  for _, entry in ipairs(self.rows) do
    if entry.seen then seen = seen + 1 end
    if entry.caught then caught = caught + 1 end
  end
  return seen, caught
end

-- The entry bar's arrow flashes.  Counted here rather than in the entry
-- branch so it keeps ticking on a frame with no input, and on the same 32-step
-- period the AREA map's own blink uses (PokedexMenu:updateArea) so the two
-- cannot drift out of step on screens that show both.
function PokedexMenu:cursorVisible()
  return ((self.entryBlink or 0) % 32) < 20
end

-- Pokedex: wCurDexMode -> wLastDexMode on the way out
-- (engine/pokedex/pokedex.asm:60), which lives in the saved game data.
function PokedexMenu:close()
  if self.save then self.save.lastDexMode = MODES[self.modeIndex] end
  if self.onClose then self.onClose() end
end

function PokedexMenu:update(_dt)
  self.entryBlink = (self.entryBlink or 0) + 1
  local input = self.game and self.game.input
  if not input then return end
  if self.view == "entry" then
    -- NewPokedexEntry is two WaitPressAorB_BlinkCursor pages and then out
    -- (engine/pokedex/new_pokedex_entry.asm:19-23).
    if self.newEntry then
      if input:wasPressed("a") or input:wasPressed("b") then
        if self.page == 1 then
          self.page = 2
        else
          self:close()
        end
      end
      return
    end
    -- DexEntryScreen_MenuActionJumptable's PAGE flips between the entry's two
    -- pages; B and A back out to the listing.
    -- DexEntryScreen_ArrowCursorData: LEFT/RIGHT walk an arrow across four
    -- actions at (1,17) (6,17) (11,17) (15,17), and A runs the one under it.
    -- This used to flip the page on LEFT/RIGHT directly, which is a shortcut
    -- that reads fine and quietly makes three of the four actions unreachable
    -- -- AREA among them, so the nest map could never be opened at all.
    if input:wasPressed("right") then
      self.entryAction = (self.entryAction % #ENTRY_ACTIONS) + 1
    elseif input:wasPressed("left") then
      self.entryAction = (self.entryAction - 2) % #ENTRY_ACTIONS + 1
    elseif input:wasPressed("a") then
      local action = ENTRY_ACTIONS[self.entryAction]
      if action == "PAGE" then
        self.page = self.page == 1 and 2 or 1
      elseif action == "AREA" then
        self.view = "area"
        self.areaRegion = nil
      elseif action == "CRY" then
        self:playCry(self:current() and self:current().species)
      elseif action == "PRNT" then
        self:printEntry()
      end
    elseif input:wasPressed("b") then
      self.view = "list"
    end
    return
  end
  if self.view == "area" then return self:updateArea(input) end
  if self.view == "option" then return self:updateOption(input) end
  if self.view == "search" then return self:updateSearch(input) end
  if self.view == "unown" then return self:updateUnown(input) end
  if input:wasPressed("b") then
    self:close()
    return
  elseif input:wasPressed("select") then
    -- Pokedex_UpdateMainScreen: SELECT opens the OPTION screen and START the
    -- SEARCH screen; neither cycles anything in place.
    self.view = "option"
    self.optionIndex = self.modeIndex
    return
  elseif input:wasPressed("start") then
    self.view = "search"
    self.searchIndex = 1
    self.searchType = self.searchType or { 1, 0 }
    self.searchResults = nil
    return
  elseif input:wasPressed("up") then
    self.index = self.index > 1 and self.index - 1 or #self.rows
    self:ensureVisible()
    return
  elseif input:wasPressed("down") then
    self.index = self.index < #self.rows and self.index + 1 or 1
    self:ensureVisible()
    return
  elseif input:wasPressed("a") then
    local row = self:current()
    -- Pokedex_UpdateMainScreen's .a returns unless the mon has been seen.
    if row and row.seen then
      self.view = "entry"
      self.page = 1
      -- Pokedex_InitDexEntryScreen's tail cries the selected mon
      -- (pokedex.asm:345-347); PAGE itself does not (:386-394).
      self:playCry(row.species)
    end
    return
  end
end

function PokedexMenu:monName(species)
  local def = self.pokemon and self.pokemon[species]
  return (def and def.name) or species
end

function PokedexMenu:picFor(species)
  local def = self.pokemon and self.pokemon[species]
  local path = def and def.spriteFront
  -- Pokedex_LoadSelectedMonTiles (engine/pokedex/pokedex.asm:2364) copies
  -- wFirstUnownSeen into wUnownLetter before GetMonFrontpic, so the #DEX shows
  -- the form the player FIRST met.  The species' own row is letter A's pic
  -- (src/import/RomExtractorGen2.lua fills it that way), which is exactly what
  -- the cart draws while the byte is still 0.
  if species == Unown.SPECIES then
    local first = self.save and tonumber(self.save.firstUnownSeen) or 0
    if first ~= 0 then
      path = Unown.formSprite(self.pokemon, first, false) or path
    end
  end
  if not path then return nil end
  local cached = self.picCache[path]
  if cached == nil then
    local ok, image = pcall(Assets.image, path)
    cached = ok and image or false
    self.picCache[path] = cached
  end
  return cached or nil
end

function PokedexMenu:questionMark()
  local path = self.gfx and self.gfx.questionMark
  if not path then return nil end
  local cached = self.picCache[path]
  if cached == nil then
    local ok, image = pcall(Assets.image, path)
    cached = ok and image or false
    self.picCache[path] = cached
  end
  return cached or nil
end

-- Pokedex_PlaceFrontpicTopLeftCorner lays a 7x7 block of tiles at (1,1) on
-- every dex screen, and Pokedex_LoadSelectedMonTiles fills those 49 tiles --
-- with the mon's frontpic if it has been seen, with LoadQuestionMarkPic's if
-- not.
--
-- Gen 2 pics are 5x5, 6x6 or 7x7, and PadFrontpic centres the small ones in
-- that block: a 6x6 goes one tile in from the top left, a 5x5 one across and
-- two down.  Everything else in the block stays blank, which under the
-- palette in force is its colour 0 -- so the pic sits on a solid square of
-- that colour rather than on the panel.
--
-- `ownColors` picks which palette that is.  _CGB_Pokedex_Init branches on
-- wCurPartySpecies: Pokedex_InitMainScreen sets it to -1, so the listing
-- draws every mon through PokedexQuestionMarkPalette (which is why the cart's
-- main screen shows a green mon on green), while Pokedex_InitDexEntryScreen
-- sets the real species and gets its own two colours.
local PIC_PAD = { [7] = { 0, 0 }, [6] = { 1, 1 }, [5] = { 1, 2 } }

function PokedexMenu:drawPic(row, tx, ty, ownColors)
  local G = love.graphics
  local image, colors
  if row and row.seen then
    image = self:picFor(row.species)
    if ownColors then
      colors = self.palettes and Palettes.monColors(self.palettes, row.species)
    else
      colors = self.gfx and self.gfx.questionMarkPalette
    end
  else
    image = self:questionMark()
    colors = self.gfx and self.gfx.questionMarkPalette
  end
  if not image then return end

  local blank = colors and GbcPalette.color(colors, 1) or { 255, 255, 255 }
  G.setColor(blank[1] / 255, blank[2] / 255, blank[3] / 255, 1)
  G.rectangle("fill", tx * 8, ty * 8, 7 * 8, 7 * 8)

  local tiles = math.floor(image:getWidth() / 8)
  local pad = PIC_PAD[tiles] or PIC_PAD[7]
  G.setColor(1, 1, 1, 1)
  local function body()
    G.draw(image, (tx + pad[1]) * 8, (ty + pad[2]) * 8)
  end
  if colors and GbcPalette.available() then
    GbcPalette.with(colors, body)
  else
    body()
  end
end

-- Pokedex_DrawFootprint: $62..$65 at (18,1), a 2x2 out of the strip
-- Pokedex_LoadAnyFootprint would have requested into those tiles.
function PokedexMenu:drawFootprint(species, tx, ty)
  local path = self.gfx and self.gfx.footprints
  local order = self.gfx and self.gfx.footprintOrder
  if not (path and order) then return end
  local index
  for i, id in ipairs(order) do
    if id == species then index = i break end
  end
  if not index then return end
  local cached = self.picCache[path]
  if cached == nil then
    local ok, image = pcall(Assets.image, path)
    cached = ok and image or false
    self.picCache[path] = cached
  end
  if not cached then return end
  local quad = self.footprintQuad
  if not quad then
    quad = love.graphics.newQuad(0, 0, 16, 16, cached:getDimensions())
    self.footprintQuad = quad
  end
  quad:setViewport(0, (index - 1) * 16, 16, 16, cached:getDimensions())
  love.graphics.setColor(1, 1, 1, 1)
  local function body() love.graphics.draw(cached, quad, tx * 8, ty * 8) end
  if self.gfx.palette and GbcPalette.available() then
    GbcPalette.with(self.gfx.palette, body)
  else
    body()
  end
end

function PokedexMenu:tile(id, tx, ty)
  if self.sheet then self.sheet:draw(id, tx, ty) end
end

function PokedexMenu:fill(id, tx, ty, wide, high)
  for y = ty, ty + high - 1 do
    for x = tx, tx + wide - 1 do
      self:tile(id, x, y)
    end
  end
end

function PokedexMenu:text(str, tx, ty)
  Chrome.printInverted(str, tx, ty, self.gfx and self.gfx.palette)
end

-- The inverted font's ' ' cell.  Uninverted it is shade 0 throughout, so
-- inverted it is a solid shade 3 -- black under PREDEFPAL_POKEDEX -- and
-- every ClearBox and box interior on these screens is made of it.
function PokedexMenu:blank(tx, ty, wide, high)
  -- Colour 3, which is what an inverted shade-0 cell resolves to and the same
  -- colour Chrome.printThrough paints behind an inverted string.
  local paper = self.dexPalette and GbcPalette.color(self.dexPalette, 4)
    or { 0, 0, 0 }
  local G = love.graphics
  G.setColor(paper[1] / 255, paper[2] / 255, paper[3] / 255, 1)
  G.rectangle("fill", tx * 8, ty * 8, wide * 8, high * 8)
  G.setColor(1, 1, 1, 1)
end

-- Pokedex_PlaceBorder: b interior rows by c interior columns, so the box on
-- screen is (c + 2) wide and (b + 2) tall.  The interior is ' ' ($7f), which
-- in the inverted font page is a solid black cell.
function PokedexMenu:border(tx, ty, interiorRows, interiorCols)
  local B = TILE_BORDER
  self:tile(B.topLeft, tx, ty)
  for i = 1, interiorCols do self:tile(B.top, tx + i, ty) end
  self:tile(B.topRight, tx + interiorCols + 1, ty)
  self:blank(tx + 1, ty + 1, interiorCols, interiorRows)
  for row = 1, interiorRows do
    self:tile(B.left, tx, ty + row)
    self:tile(B.right, tx + interiorCols + 1, ty + row)
  end
  local bottom = ty + interiorRows + 1
  self:tile(B.bottomLeft, tx, bottom)
  for i = 1, interiorCols do self:tile(B.bottom, tx + i, bottom) end
  self:tile(B.bottomRight, tx + interiorCols + 1, bottom)
end

-- PrintNum: a right-aligned field of `digits` characters, space-padded unless
-- PRINTNUM_LEADINGZEROS was set.  `before` splits the field into an integer
-- part and a fraction with a '.' between them.
local function printNumString(value, digits, leadingZeros, before)
  local text = ("%0" .. digits .. "d"):format(math.max(0, math.floor(value or 0)))
  if not leadingZeros then
    local kept = false
    local out = {}
    for i = 1, #text do
      local ch = text:sub(i, i)
      -- .PrintDigit stops suppressing once e runs out, which is the digit
      -- immediately before the decimal point (and the units digit when there
      -- is none), so those always print even as a zero.
      local forced = i == #text or (before and i >= before)
      if ch ~= "0" or kept or forced then
        kept = true
        out[#out + 1] = ch
      else
        out[#out + 1] = " "
      end
    end
    text = table.concat(out)
  end
  if before then
    return text:sub(1, before) .. "." .. text:sub(before + 1)
  end
  return text
end

-- ---------------------------------------------------------------- main screen

-- Pokedex_DrawMainScreenBG, drawn behind the window and scrolled by SCX.
function PokedexMenu:drawMainBackground()
  local G = love.graphics
  G.push()
  G.translate(-SCX, 0)

  -- One column past the screen: SCX uncovers five pixels of column 20, which
  -- the BG map holds the same background fill in.
  self:fill(TILE_BG, 0, 0, Chrome.SCREEN_W + 1, Chrome.SCREEN_H)
  self:border(0, 0, 7, 7)
  self:border(0, 9, 6, 7)

  local seen, caught = self:totals()
  self:text("SEEN", 1, 11)
  self:text(printNumString(seen, 3), 5, 12)
  self:text("OWN", 1, 14)
  self:text(printNumString(caught, 3), 5, 15)

  for i, id in ipairs(BOTTOM_CAPTION) do self:tile(id, i, 17) end

  -- The rule between the two halves of the background and the window.
  self:tile(0x59, 8, 0)
  for y = 1, 7 do self:tile(0x5a, 8, y) end
  self:tile(0x53, 8, 8)
  self:tile(0x54, 8, 9)
  for y = 10, 15 do self:tile(0x5a, 8, y) end
  self:tile(0x5b, 8, 16)

  self:drawPic(self:current(), 1, 1)
  G.pop()
end

-- DrawPokedexListWindow + Pokedex_PrintListing, on the window layer.  hWX
-- puts the window's column 0 at screen x 64 (67 in OLD mode) and only twelve
-- of its columns fit, so everything past column 11 is off screen anyway.
function PokedexMenu:drawMainWindow()
  local G = love.graphics
  local old = self:mode() == "OLD"
  G.push()
  G.translate(WINDOW_X[self:mode()] or 64, 0)

  -- ClearBox(0, 1) 15 rows by 11 columns, then the top and bottom edges.
  self:blank(0, 1, 11, 15)
  for x = 0, 10 do
    self:tile(TILE_BORDER.top, x, 0)
    self:tile(TILE_BORDER.bottom, x, 16)
  end
  self:tile(0x3f, 5, 0)
  self:tile(0x40, 5, 16)

  -- The scroll bar column, or its flat OLD-mode replacement.
  local top, mid, bottom = 0x50, 0x51, 0x52
  if old then top, mid, bottom = 0x66, 0x67, 0x68 end
  self:tile(top, 11, 0)
  for y = 1, 15 do self:tile(mid, 11, y) end
  self:tile(bottom, 11, 16)

  self:fill(TILE_BG, 0, 17, 12, 1)
  for i, id in ipairs(WINDOW_CAPTION) do self:tile(id, i - 1, 17) end

  for row = 1, VISIBLE_ROWS do
    local entry = self.rows[row + self.scroll]
    if entry then
      local ty = row * 2
      if old then
        self:text(printNumString(entry.dex or 0, 3, true), 0, ty - 1)
      end
      if entry.seen then
        if entry.caught then self:tile(TILE_CAUGHT, 0, ty) end
        self:text(self:monName(entry.species), 1, ty)
      else
        self:text("-----", 1, ty)
      end
    end
  end
  G.pop()
end

function PokedexMenu:drawCursorObjs()
  if not (self.objs and self.objs:available()) then
    -- Without the OBJ sheet, mark the row the way every other Gen 2 list does.
    local row = self.index - self.scroll
    Chrome.cursor(math.floor((WINDOW_X[self:mode()] or 64) / 8) - 1, row * 2)
    return
  end
  local G = love.graphics
  local table_ = self:mode() == "OLD" and CURSOR_OAM_OLD or CURSOR_OAM
  -- Pokedex_LoadCursorOAM adds (cursor & 7) * 16 to every y.
  local offset = ((self.index - self.scroll - 1) % 8) * 16
  for _, obj in ipairs(table_) do
    local quad = self.objs:quad(obj.tile)
    local image = self.objs:image()
    if quad and image then
      G.setColor(1, 1, 1, 1)
      local sx = obj.xflip and -1 or 1
      local sy = obj.yflip and -1 or 1
      local ox = obj.xflip and 8 or 0
      local oy = obj.yflip and 8 or 0
      local function body()
        G.draw(image, quad, obj.x + ox, obj.y + offset + oy, 0, sx, sy)
      end
      if self.gfx.cursorPalette and GbcPalette.available() then
        GbcPalette.with(self.gfx.cursorPalette, body)
      else
        body()
      end
    end
  end

  -- The scroll bar thumb rides the whole list, not the page.  Its OAM
  -- attribute byte is 0, so unlike the cursor it wears OBJ palette 0, which
  -- _CGB_Pokedex_Resume left as InitPartyMenuOBPals' first entry.
  local total = math.max(1, #self.rows - 1)
  local travel = math.floor((self.index - 1) * SCROLLBAR_TRAVEL / total)
  local quad = self.objs:quad(SCROLLBAR_TILE)
  if quad and self:mode() ~= "OLD" then
    G.setColor(1, 1, 1, 1)
    local pals = self.palettes and self.palettes.partyMenu
    local colors = pals and pals[1]
    local function body()
      G.draw(self.objs:image(), quad, SCROLLBAR_X, SCROLLBAR_TOP + travel)
    end
    if colors and GbcPalette.available() then
      GbcPalette.with(colors, body)
    else
      body()
    end
  end
end

function PokedexMenu:drawList()
  self:drawMainBackground()
  self:drawMainWindow()
  self:drawCursorObjs()
end

-- --------------------------------------------------------------- entry screen

-- Pokedex_DrawDexEntryScreenBG + DisplayDexEntry.
--
-- Pokedex_InitDexEntryScreen only pushes the window off screen (hWX $a7); it
-- never resets hSCX, so this screen inherits the main screen's 5-pixel scroll
-- and the rightmost five pixels are whatever the BG map holds past column 19.
-- PlayMonCry, silent for a species with no extracted cry rather than raising.
-- PRNT.  Pokedex_Print (engine/pokedex/pokedex.asm) hands the entry to the
-- Game Boy Printer over the link port, which is a device this port cannot
-- have; Gen 1's Yellow dex answers the same problem the same way
-- (src/ui/PokedexMenu.lua's PRNT arm), so Gold does too rather than leaving
-- the fourth action inert: the page the printer would have printed is written
-- out as a PNG under prints/ in the save folder, at the printer's own 160x144.
--
-- The shot is THIS screen's own entry draw, so what lands in the file is what
-- was on the dex when PRNT was pressed, page and all.
function PokedexMenu:printEntry()
  local row = self:current()
  if not row then return end
  local Printer = require("src.core.Printer")
  local Strings = require("src.core.Strings")
  local TextBox = require("src.render.TextBox")
  local name = (self.pokemon and self.pokemon[row.species]
    and self.pokemon[row.species].name) or tostring(row.species)
  local saved, err = Printer.save("dex_" .. tostring(row.species), 160, 144,
    function() self:drawEntry() end)
  -- Word for word what Yellow's PRNT says (src/ui/PokedexMenu.lua), so the two
  -- generations share one catalog entry and a translation covers both.
  local text = saved
    and Strings("Printed %s's\ndata!\fSaved as\n%s\vin the save\nfolder.",
                name, tostring(saved))
    or Strings("Printer error!\n%s", tostring(err))
  if self.game and self.game.stack then
    self.game.stack:push(TextBox.new(self.game, text))
  end
end

function PokedexMenu:playCry(species)
  if not species then return end
  local cries = self.data and self.data.audio and self.data.audio.cries
  if cries and cries[species] then Sound.playCry(self.data, species) end
end

-- ------------------------------------------------------------------- AREA
--
-- Pokedex_GetArea (engine/pokegear/pokegear.asm) borrows the Pokegear's town
-- map and overlays FindNest's landmarks. The region shown starts as the one the
-- player is standing in; LEFT/RIGHT swap it, which is how you see a Kanto mon's
-- nests from Johto. B goes back to the entry.
function PokedexMenu:areaRegionName()
  if self.areaRegion then return self.areaRegion end
  local landmark = self:playerLandmark()
  return Nests.regionOf(landmark) or "johto"
end

-- The player's landmark index, which is what decides the starting region.
function PokedexMenu:playerLandmark()
  local save = self.game and self.game.save
  local mapId = save and save.position and save.position.map
  local def = mapId and self.data and self.data.gen2Maps and self.data.gen2Maps[mapId]
  return def and def.landmark
end

-- The Pokegear's own tilemap blit: a flat list of tile ids, row-major over the
-- 20x18 screen. Reimplemented here rather than reached for across modules
-- because the dex draws through its own sheet and palette (the COLOR option
-- substitutes them), and borrowing Pokegear's would freeze the map's ink.
function PokedexMenu:drawTilemap(cells)
  if type(cells) ~= "table" then return end
  local sheet = self.mapSheet
  if not sheet then return end
  local i = 1
  for ty = 0, Chrome.SCREEN_H - 1 do
    for tx = 0, Chrome.SCREEN_W - 1 do
      local id = cells[i]
      if id then sheet:draw(id, tx, ty) end
      i = i + 1
    end
  end
end

function PokedexMenu:updateArea(input)
  self.areaBlink = (self.areaBlink or 0) + 1
  if input:wasPressed("b") or input:wasPressed("a") then
    self.view = "entry"
    return
  end
  if input:wasPressed("left") or input:wasPressed("right") then
    self.areaRegion = (self:areaRegionName() == "johto") and "kanto" or "johto"
  end
end

function PokedexMenu:drawArea()
  local row = self:current()
  if not row then return end
  local region = self:areaRegionName()
  local save = self.game and self.game.save
  local nests = Nests.find(self.data, row.species, region, save)

  self:fill(TILE_BG, 0, 0, Chrome.SCREEN_W + 1, Chrome.SCREEN_H)

  -- The map itself is the Pokegear's, drawn through the same gfx the MAP card
  -- uses. Without it (a cache imported before the town map was extracted) the
  -- page still lists the landmark NAMES, which is the information the screen
  -- exists to convey.
  local maps = self.mapGfx and self.mapGfx.maps
  local cells = maps and maps[region]
  if cells then
    self:drawTilemap(cells)
  end

  self:blank(0, 0, Chrome.SCREEN_W, 2)
  self:text(self:monName(row.species) .. "'S NEST", 1, 0)
  self:text(region == "kanto" and "KANTO" or "JOHTO", 1, 1)

  local G = love.graphics

  if #nests == 0 then
    -- A species with no grass, water or roamer entry in this region. The cart
    -- simply shows the map with nothing blinking on it.
    self:text("AREA UNKNOWN", 4, 16)
    return
  end

  -- engine/pokegear/pokegear.asm:2427
  local on = ((self.areaBlink or 0) % 32) < 20
  if cells and on then
    for _, index in ipairs(nests) do
      local mark = Nests.landmark(self.data, index)
      if mark and mark.x and mark.y then
        G.setColor(0, 0, 0, 1)
        G.rectangle("fill", mark.x - 2, mark.y - 2, 5, 5)
        G.setColor(1, 1, 1, 1)
        G.rectangle("fill", mark.x - 1, mark.y - 1, 3, 3)
      end
    end
  end

  -- Name the first one in words as well as on the map: the flashing dot is
  -- unreadable at this size on a modern display, and the landmark name is what
  -- a player actually wants off this screen.
  local first = Nests.landmark(self.data, nests[1])
  if first and first.name then
    local name = tostring(first.name):gsub("\n", " ")
    self:text(name, 1, 16)
    if #nests > 1 then
      self:text(("+%d"):format(#nests - 1), 17, 16)
    end
  end
end

function PokedexMenu:drawEntry()
  local row = self:current()
  if not row then return end
  local entry = self.dex and self.dex.entries and self.dex.entries[row.species]
  if not entry then return end

  local G = love.graphics
  G.push()
  G.translate(-SCX, 0)
  local ok, err = pcall(function() self:drawEntryBody(row, entry) end)
  G.pop()
  if not ok then error(err, 0) end
end

function PokedexMenu:drawEntryBody(row, entry)
  -- One column past the screen, because the scroll exposes it: the BG map is
  -- 32 tiles wide and the fill runs on past the 20 the screen shows, so the
  -- five pixels SCX uncovers on the right are the same background colour.
  self:fill(TILE_BG, 0, 0, Chrome.SCREEN_W + 1, Chrome.SCREEN_H)
  self:border(0, 0, 15, 18)
  -- The right border column is then erased: (19,0) becomes the top edge,
  -- rows 1-15 blank, and (19,16) the bottom edge.
  self:tile(TILE_BORDER.top, 19, 0)
  self:blank(19, 1, 1, 15)
  self:tile(TILE_BORDER.bottom, 19, 16)

  for x = 1, 19 do self:tile(TILE_DIVIDER, x, 10) end
  -- Pokedex_DrawDexEntryScreenBG blanks 18 columns, _NewPokedexEntry's own
  -- ByteFill 19 (pokedex.asm:1155-1157, :2540-2545).
  self:blank(1, 17, self.newEntry and 19 or 18, 1)
  self:tile(0x3b, 0, 17)
  -- _NewPokedexEntry ByteFills the action row away (pokedex.asm:2540-2545).
  if not self.newEntry then
    self:text(" PAGE AREA CRY PRNT", 1, 17)
    -- Pokedex_InitArrowCursor parks an arrow on the selected action; without it
    -- the four words are decoration and there is no way to tell what A will do.
    --
    -- ENTRY_ACTION_X holds the ARROW's own dwcoord columns, so they are used as
    -- they are.  Subtracting one put the arrow a column early every time: on
    -- PAGE it landed at column 0, outside the bar against the border, and on
    -- CRY it landed on the last "A" of AREA and ate it.  The words sit one
    -- column right of each arrow slot -- the leading space in the string below
    -- is what makes that true -- so the raw value is already the gap in front of
    -- each word.
    --
    -- Drawn through the dex's inverted palette and blinking, because this arrow
    -- is white on the dark bar rather than the black one every other Gold menu
    -- uses, and it flashes.  The half-second period is chosen to read like the
    -- cart; the exact frame count is not cited here.
    if self:cursorVisible() then
      Chrome.cursorThrough(ENTRY_ACTION_X[self.entryAction or 1] or 1, 17,
        self.gfx and self.gfx.palette, true)
    end
  end

  self:drawPic(row, 1, 1, true)
  self:drawFootprint(row.species, 18, 1)

  self:text(self:monName(row.species), 9, 3)
  self:text(entry.kind or "", 9, 5)
  self:tile(TILE_NO[1], 2, 8)
  self:tile(TILE_NO[2], 3, 8)
  self:text(printNumString(entry.dex or 0, 3, true), 4, 8)

  -- .Height / .Weight are placeholder strings until the mon is caught:
  -- "HT  ?'??"" at (9,7) and "WT   ???lb" at (9,9).
  self:text("HT", 9, 7)
  self:text("WT", 9, 9)
  self:tile(TILE_FOOT, 14, 7)
  self:text("lb", 17, 9)

  if not row.caught then
    self:text("  ?", 11, 7)
    self:text("??", 15, 7)
    self:tile(TILE_INCH, 17, 7)
    self:text("  ???", 11, 9)
    return
  end

  -- The height word is four digits with two in front of the point and the
  -- point replaced by the foot mark; the weight word is five with four in
  -- front.  Both are already the digits the cart prints.
  local height = printNumString(entry.height or 0, 4, false, 2)
  self:text(height:sub(1, 2), 12, 7)
  self:text(height:sub(4), 15, 7)
  self:tile(TILE_INCH, 17, 7)
  self:text(printNumString(entry.weight or 0, 5, false, 4), 11, 9)

  -- Page marker, then the description.  ClearBox(2,11) is 5 rows by 18
  -- columns and <NEXT> steps two rows, so the three lines land on 11/13/15.
  self:tile(TILE_PAGE_TOP, 1, 9)
  self:tile(TILE_PAGE_TOP, 2, 9)
  self:tile(TILE_PAGE_P, 1, 10)
  self:tile(TILE_PAGE_DIGIT[self.page] or TILE_PAGE_DIGIT[1], 2, 10)

  local text = self.page == 2 and entry.text2 or entry.text
  local ty = 11
  for part in (tostring(text or "") .. "<NEXT>"):gmatch("(.-)<NEXT>") do
    if ty > 15 then break end
    self:text(part, 2, ty)
    ty = ty + 2
  end
end

-- ------------------------------------------------------------------ fallbacks

-- A cache from before the dex sheet was extracted has no `pokedex` table.
-- Rather than draw nothing, fall back to the plain boxes this screen used
-- before the sweep.
function PokedexMenu:drawPlain()
  Chrome.clear()
  if self.view == "unown" then
    -- Without the dex sheet there are no border tiles, so the ring of letters
    -- is printed straight onto a plain box; the slot coordinates are the same
    -- ones the styled screen uses.
    Chrome.box(2, 1, 15, 13)
    local list = self:unownDex()
    local slot = math.min(self.unownIndex or 0, math.max(0, #list - 1))
    for index, value in ipairs(list) do
      local coords = PokedexMenu.UNOWN_COORDS[index]
      if coords then
        Chrome.print(Unown.name(value) or "?", coords[1], coords[2])
        if index == slot + 1 then Chrome.cursor(coords[3], coords[4]) end
      end
    end
    local letter = list[slot + 1]
    if letter then
      self:drawUnownPic(letter, 6, 5)
      Chrome.print(Unown.word(letter) or "", 4, 15)
    end
    return
  end
  if self.view == "entry" then
    local row = self:current()
    local entry = row and self.dex and self.dex.entries
      and self.dex.entries[row.species]
    Chrome.box(0, 0, 20, 10)
    if entry then
      Chrome.print(("%s  %s"):format(
        Chrome.number(entry.dex or 0, 3, true), self:monName(row.species)), 1, 1)
      Chrome.print(entry.kind or "", 1, 3)
      Chrome.print("HT " .. printNumString(entry.height or 0, 4, false, 2), 1, 5)
      Chrome.print("WT " .. printNumString(entry.weight or 0, 5, false, 4), 1, 7)
      self:drawPic(row, 12, 1, true)
      Chrome.box(0, 10, 20, 8)
      local ty = 11
      for part in ((entry.text or "") .. "<NEXT>"):gmatch("(.-)<NEXT>") do
        if ty > 16 then break end
        Chrome.print(part, 1, ty)
        ty = ty + 1
      end
    end
    return
  end
  Chrome.box(0, 0, 13, 18)
  for row = 1, VISIBLE_ROWS do
    local i = row + self.scroll
    local entry = self.rows[i]
    if entry then
      local ty = 1 + (row - 1) * 2
      if i == self.index then Chrome.cursor(0, ty) end
      Chrome.print(Chrome.number(entry.dex or 0, 3, true), 1, ty)
      Chrome.print(entry.seen and self:monName(entry.species) or "-----", 5, ty)
    end
  end
  Chrome.box(13, 0, 7, 11)
  self:drawPic(self:current(), 13, 1)
  Chrome.box(13, 11, 7, 7)
  local seen, caught = self:totals()
  Chrome.print(self:mode(), 14, 12)
  Chrome.print("SEEN", 14, 14)
  Chrome.printRight(tostring(seen), 19, 15)
  Chrome.print("OWN", 14, 16)
  Chrome.printRight(tostring(caught), 19, 17)
end

-- ---------------------------------------------------------- OPTION / SEARCH
--
-- Pokedex_DrawOptionScreenBG and Pokedex_DrawSearchScreenBG, transcribed at
-- their own hlcoords.  Both draw over the dex's own background fill rather
-- than into a text box, which is why they use `border` and `text` here.

-- The SEARCH screen's type wheel: "-----" is index 0 and the eighteen real
-- types follow, in the order data/types/names.asm lists them.
PokedexMenu.SEARCH_TYPES = {
  "NORMAL", "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK", "BUG", "GHOST",
  "STEEL", "FIRE", "WATER", "GRASS", "ELECTRIC", "PSYCHIC", "ICE", "DRAGON",
  "DARK",
}

-- .Modes, and the two-line description Pokedex_DisplayModeDescription prints
-- under each one.
-- `#` is the compression byte for POKé, four tiles either way, so the label
-- is spelled out here the way every other Gen 2 screen in the port spells it.
PokedexMenu.OPTION_MODES = {
  { label = "NEW POKéDEX MODE", mode = "NEW",
    lines = { "<PK><MN> are listed by", "evolution type." } },
  { label = "OLD POKéDEX MODE", mode = "OLD",
    lines = { "<PK><MN> are listed by", "official type." } },
  { label = "A to Z MODE", mode = "A-Z",
    lines = { "<PK><MN> are listed", "alphabetically." } },
  { label = "UNOWN MODE", mode = "UNOWN", unown = true,
    lines = { "UNOWN are listed", "in catching order." } },
}

-- Pokedex_CheckUnlockedUnownMode: `ld a, [wStatusFlags] / bit
-- STATUSFLAGS_UNOWN_DEX_F`, which is ENGINE_UNOWN_DEX -- the flag the Ruins of
-- Alph researcher sets when he upgrades the #DEX, NOT "an Unown has been
-- caught".  The two come apart in play: the researcher only turns up once a
-- puzzle has been solved, so a player who catches an Unown before talking to
-- him has the mode hidden until he has upgraded the machine.
function PokedexMenu:unownUnlocked()
  local flags = (self.save and self.save.engineFlags) or {}
  return flags[Unown.ENGINE_UNOWN_DEX] == true
end

function PokedexMenu:optionRows()
  local rows = {}
  for _, entry in ipairs(PokedexMenu.OPTION_MODES) do
    if not entry.unown or self:unownUnlocked() then rows[#rows + 1] = entry end
  end
  return rows
end

function PokedexMenu:updateOption(input)
  local rows = self:optionRows()
  if input:wasPressed("up") then
    self.optionIndex = self.optionIndex > 1 and self.optionIndex - 1 or #rows
  elseif input:wasPressed("down") then
    self.optionIndex = self.optionIndex < #rows and self.optionIndex + 1 or 1
  elseif input:wasPressed("b") or input:wasPressed("select") then
    -- .return_to_main_screen: SELECT and B both back out without changing
    -- anything.
    self.view = "list"
  elseif input:wasPressed("a") then
    local row = rows[self.optionIndex]
    if row and row.unown then
      -- .MenuAction_UnownMode is the one option row that does NOT go back to
      -- the listing: it sets DEXSTATE_UNOWN_MODE, its own screen.
      self.view = "unown"
      self.unownIndex = 0
      return
    end
    self.view = "list"
    if row then
      for index, name in ipairs(MODES) do
        if name == row.mode then
          -- .ChangeMode resets the listing to the top when the mode actually
          -- changes, and does nothing at all when it does not.
          if index ~= self.modeIndex then
            self.modeIndex = index
            self.index, self.scroll = 1, 0
            self:rebuild()
          end
        end
      end
    end
  end
end

-- ------------------------------------------------------------- UNOWN MODE
--
-- Pokedex_InitUnownMode / Pokedex_UpdateUnownMode (engine/pokedex/pokedex.asm)
-- plus PrintUnownWord (engine/pokedex/unown_dex.asm).
--
-- The screen is the FORM list, not the species list: wUnownDex holds the
-- letters in the order they were first caught, wDexUnownCount is how many of
-- them there are, and wDexCurUnownIndex walks that list with LEFT and RIGHT
-- only.  A or B leaves, back to the OPTION screen.
--
-- The letters are laid out in a ring around the picture and the ring is
-- addressed by SLOT, not by letter: UnownModeLetterAndCursorCoords row 0 is
-- (4,11) whatever letter was caught first.
function PokedexMenu:unownDex()
  return Unown.dex(self.save)
end

function PokedexMenu:updateUnown(input)
  local list = self:unownDex()
  if input:wasPressed("a") or input:wasPressed("b") then
    -- .a_b returns to DEXSTATE_OPTION_SCR, not to the listing.
    self.view = "option"
    return
  end
  if input:wasPressed("right") then
    -- `.right`: `inc a / cp e / ret nc` -- the last slot cannot advance, and
    -- there is no wrap.
    if self.unownIndex + 1 < #list then
      self.unownIndex = self.unownIndex + 1
    end
  elseif input:wasPressed("left") then
    if self.unownIndex > 0 then self.unownIndex = self.unownIndex - 1 end
  end
end

-- UnownModeLetterAndCursorCoords, transcribed: the letter cell and the cursor
-- cell for each of the 26 SLOTS, running up the left column, along the top and
-- back down the right.
PokedexMenu.UNOWN_COORDS = {
  { 4, 11, 3, 11 }, { 4, 10, 3, 10 }, { 4, 9, 3, 9 }, { 4, 8, 3, 8 },
  { 4, 7, 3, 7 }, { 4, 6, 3, 6 }, { 4, 5, 3, 5 }, { 4, 4, 3, 4 },
  { 4, 3, 3, 2 }, { 5, 3, 5, 2 }, { 6, 3, 6, 2 }, { 7, 3, 7, 2 },
  { 8, 3, 8, 2 }, { 9, 3, 9, 2 }, { 10, 3, 10, 2 }, { 11, 3, 11, 2 },
  { 12, 3, 12, 2 }, { 13, 3, 13, 2 }, { 14, 3, 15, 2 }, { 14, 4, 15, 4 },
  { 14, 5, 15, 5 }, { 14, 6, 15, 6 }, { 14, 7, 15, 7 }, { 14, 8, 15, 8 },
  { 14, 9, 15, 9 }, { 14, 10, 15, 10 },
}

-- Pokedex_DrawUnownModeBG: FillBackgroundColor2, a 10x13 box at (2,1), a 1x13
-- box at (2,14), the two arrow tiles at (2,15) and (16,15), and the frontpic
-- at (6,5).  The word goes at hlcoord 4, 15, twelve cells wide.
function PokedexMenu:drawUnown()
  local list = self:unownDex()
  self:fill(TILE_BG, 0, 0, Chrome.SCREEN_W, Chrome.SCREEN_H)
  self:border(2, 1, 10, 13)
  self:border(2, 14, 1, 13)
  self:tile(0x3d, 2, 15)
  self:tile(0x3e, 16, 15)

  local slot = math.min(self.unownIndex or 0, math.max(0, #list - 1))
  local letter = list[slot + 1]
  if letter then
    -- Pokedex_LoadUnownFrontpicTiles: the pic is the FORM's, which is why
    -- pokemon.lua's UNOWN entry carries letters.A..Z.
    self:drawUnownPic(letter, 6, 5)
    self:unownText(Unown.word(letter) or "", 4, 15)
  end
  for index, value in ipairs(list) do
    local coords = PokedexMenu.UNOWN_COORDS[index]
    if coords then
      self:unownText(Unown.name(value) or "?", coords[1], coords[2])
      if index == slot + 1 then
        self:unownCursor(coords[3], coords[4])
      end
    end
  end
end

-- ------------------------------------------------------------- Unown font
--
-- Everything UNOWN MODE prints -- the ring of letters AND the word under the
-- picture -- is written in the Unown font, not in the ordinary one.  The
-- ring is `ld a, [hl] / add FIRST_UNOWN_CHAR - 1` (Pokedex_UpdateUnownMode),
-- and data/pokemon/unown_words.asm's own `unownword` macro spells each word
-- as `CHARVAL(...) - 'A' + FIRST_UNOWN_CHAR`, so a word is 26 letter tiles
-- too.  A cache built before UnownFont was extracted has no sheet, and both
-- fall back to the inverted ordinary font, which is what this screen printed
-- before.

-- One letter of the Unown font: 'A' is tile FIRST_UNOWN_CHAR.  Anything that
-- is not a letter (the '?' a corrupt slot would print) has no tile at all and
-- goes through the ordinary font instead.
function PokedexMenu:unownGlyph(char, tx, ty)
  local sheet = self.unownFont
  if not (sheet and sheet:available()) then return false end
  local index = Unown.index(char)
  if not index then return false end
  return sheet:draw((self.unownFontBase or 0x40) + index - 1, tx, ty)
end

function PokedexMenu:unownText(str, tx, ty)
  local text = tostring(str or "")
  for i = 1, #text do
    local char = text:sub(i, i)
    if not self:unownGlyph(char, tx + i - 1, ty) then
      self:text(char, tx + i - 1, ty)
    end
  end
end

-- FIRST_UNOWN_CHAR + NUM_UNOWN, the diamond the ring is pointed at with: the
-- 27th tile of the sheet, which is why the font is one tile longer than the
-- alphabet.  Without the sheet the shared cursor glyph stands in.
function PokedexMenu:unownCursor(tx, ty)
  local sheet = self.unownFont
  if sheet and sheet:available()
    and sheet:draw((self.unownFontBase or 0x40) + Unown.NUM_UNOWN, tx, ty) then
    return
  end
  self:text("\xe2\x96\xb6", tx, ty)
end

function PokedexMenu:drawUnownPic(letter, tx, ty)
  local path = Unown.formSprite(self.pokemon, letter, false)
  if not path then return end
  local cached = self.picCache[path]
  if cached == nil then
    local ok, image = pcall(Assets.image, path)
    cached = ok and image or false
    self.picCache[path] = cached
  end
  if not cached then return end
  local colors = self.palettes
    and Palettes.monColors(self.palettes, Unown.SPECIES)
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  local function body() G.draw(cached, tx * 8, ty * 8) end
  if colors and GbcPalette.available() then
    GbcPalette.with(colors, body)
  else
    body()
  end
end

-- Pokedex_UpdateSearchScreen: four rows, and left/right walk the type wheel
-- on the two that carry one.
function PokedexMenu:updateSearch(input)
  local row = self.searchIndex
  if input:wasPressed("up") then
    self.searchIndex = row > 1 and row - 1 or 4
  elseif input:wasPressed("down") then
    self.searchIndex = row < 4 and row + 1 or 1
  elseif row <= 2 and (input:wasPressed("left") or input:wasPressed("right")) then
    local delta = input:wasPressed("right") and 1 or -1
    local count = #PokedexMenu.SEARCH_TYPES
    self.searchType[row] = (self.searchType[row] + delta) % (count + 1)
  elseif input:wasPressed("b") or input:wasPressed("start") then
    self.view = "list"
  elseif input:wasPressed("a") then
    if row <= 2 then
      -- .MenuAction_MonSearchType: A steps the wheel too.
      local count = #PokedexMenu.SEARCH_TYPES
      self.searchType[row] = (self.searchType[row] + 1) % (count + 1)
    elseif row == 3 then
      self:beginSearch()
    else
      self.view = "list"
    end
  end
end

function PokedexMenu:searchTypeName(slot)
  local index = self.searchType[slot] or 0
  if index == 0 then return "-----" end
  return PokedexMenu.SEARCH_TYPES[index] or "-----"
end

-- Pokedex_SearchForMons: a mon matches when its two types cover both of the
-- wanted ones, in either order; "-----" matches anything.  Only SEEN mon are
-- searched, which is what makes the count meaningful.
function PokedexMenu:beginSearch()
  local want1 = self.searchType[1] ~= 0 and self:searchTypeName(1) or nil
  local want2 = self.searchType[2] ~= 0 and self:searchTypeName(2) or nil
  local results = {}
  for _, entry in ipairs(self.rows) do
    if entry.seen then
      local def = self.pokemon and self.pokemon[entry.species]
      local types = (def and def.types) or {}
      local a, b = types[1], types[2] or types[1]
      local ok = true
      if want1 then ok = ok and (a == want1 or b == want1) end
      if want2 then ok = ok and (a == want2 or b == want2) end
      if ok then results[#results + 1] = entry end
    end
  end
  self.searchResults = results
  if #results == 0 then
    -- .MenuAction_BeginSearch redraws the search screen and stays put when
    -- nothing matched.
    self.searchMessage = "No <PK><MN> found!"
    return
  end
  self.searchMessage = nil
  self.rows = results
  self.index, self.scroll = 1, 0
  self:ensureVisible()
  self.view = "list"
end

-- Pokedex_DrawOptionScreenBG: two bordered boxes, the title on the top rule,
-- the mode list from (3,4) two rows apart and the description at (1,14).
function PokedexMenu:drawOption()
  self:fill(TILE_BG, 0, 0, Chrome.SCREEN_W, Chrome.SCREEN_H)
  self:border(0, 2, 8, 18)
  self:border(0, 12, 4, 18)
  -- `db $3b, " OPTION ", $3c`: the two end-cap tiles are the dex sheet's, not
  -- font glyphs.
  self:tile(0x3b, 0, 1)
  self:text(" OPTION ", 1, 1)
  self:tile(0x3c, 9, 1)
  local rows = self:optionRows()
  for i, row in ipairs(rows) do
    self:text(row.label, 3, 2 + i * 2)
    if i == self.optionIndex then self:text("\xe2\x96\xb6", 2, 2 + i * 2) end
  end
  local current = rows[self.optionIndex]
  if current then
    self:text(current.lines[1], 1, 14)
    self:text(current.lines[2], 1, 15)
  end
end

-- Pokedex_DrawSearchScreenBG: one tall box, TYPE1/TYPE2 at (3,4) and (3,6)
-- with their left/right arrows at column 8, and the two-row menu at (3,13).
function PokedexMenu:drawSearch()
  self:fill(TILE_BG, 0, 0, Chrome.SCREEN_W, Chrome.SCREEN_H)
  self:border(0, 2, 14, 18)
  self:tile(0x3b, 0, 1)
  self:text(" SEARCH ", 1, 1)
  self:tile(0x3c, 9, 1)
  self:text("TYPE1", 3, 4)
  self:text("TYPE2", 3, 6)
  self:text(self:searchTypeName(1), 10, 4)
  self:text(self:searchTypeName(2), 10, 6)
  -- `.TypeLeftRightArrows: db $3d, "        ", $3e` -- two of the dex sheet's
  -- own tiles at columns 8 and 17, not font glyphs.
  for _, y in ipairs({ 4, 6 }) do
    self:tile(0x3d, 8, y)
    self:tile(0x3e, 17, y)
  end
  self:text("BEGIN SEARCH!!", 3, 13)
  self:text("CANCEL", 3, 15)
  if self.searchMessage then self:text(self.searchMessage, 3, 10) end
  local rows = { 4, 6, 13, 15 }
  local y = rows[self.searchIndex] or 4
  self:text("\xe2\x96\xb6", 2, y)
end

function PokedexMenu:drawPanel()
  if not self:styled() then
    self:drawPlain()
    love.graphics.setColor(1, 1, 1, 1)
    return
  end
  local G = love.graphics
  -- Every dex screen starts from a full-screen fill, so the frame under it
  -- is the sheet's own background rather than the white a text box wants.
  G.setColor(0, 0, 0, 1)
  G.rectangle("fill", 0, 0, Chrome.SCREEN_W * 8, Chrome.SCREEN_H * 8)
  if self.view == "entry" then
    self:drawEntry()
  elseif self.view == "area" then
    self:drawArea()
  elseif self.view == "option" then
    self:drawOption()
  elseif self.view == "search" then
    self:drawSearch()
  elseif self.view == "unown" then
    self:drawUnown()
  else
    self:drawList()
  end
  G.setColor(1, 1, 1, 1)
end

function PokedexMenu:draw()
  self:drawPanel()
end

function PokedexMenu:drawWidescreen(winW, winH)
  local G = love.graphics
  G.setColor(0, 0, 0, 1)
  G.rectangle("fill", 0, 0, winW, winH)
  local scale = Chrome.fitScale(winW, winH)
  G.push()
  G.translate(Chrome.fitOrigin(winW, winH, scale))
  G.scale(scale, scale)
  self:drawPanel()
  G.pop()
end

PokedexMenu.MODES = MODES
PokedexMenu.printNumString = printNumString

return PokedexMenu
