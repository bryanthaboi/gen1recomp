-- The trade animation's screen (engine/movie/trade_animation.asm).
--
-- The script and every frame count is src/core/gen2/TradeAnim.lua's; this file
-- is the half that draws, so the sequence can be walked in a test with no
-- window.  NPCTrade runs it between DoNPCTrade and TradedForText and nothing
-- about the trade depends on it, so B skips straight to the end -- the cart
-- has no skip, but it also has no player who has seen this thirty seconds of
-- cable six times in one save.
--
-- gfx/trade/ comes out of the cache as data.gen2Trade
-- (RomExtractorGen2:extractTrade): one 49-tile sheet the two tilemaps index,
-- plus the ball, the poof, the tube bulge and the bubble as OAM sheets.  A
-- cache built before that stage leaves every one of them nil, and then
-- everything below the frontpics falls back to the shapes those tiles are,
-- drawn at the coordinates the tilemap puts them, the same way
-- src/ui/gen2/EvolutionAnim.lua draws its balls of light.  Art and shapes
-- alike go through GbcPalette so the COLOR option still reaches them.
--
-- THE OBJECTS ARE QUADRANTS.  data/sprite_anims/oam.asm builds the poof and
-- the bubble out of a 2x2 block drawn four times (X-flipped, Y-flipped, both)
-- into a 32x32 sprite, and the bulge out of a single tile the same way; the
-- ball's first wobble frame is its left half with the right half X-flipped.
-- So a sheet of 4 tiles really is a 32x32 puff, and :drawQuadrant is that
-- mirroring rather than a shortcut.
--
-- A sprite anim's x, y is its ORIGIN, which for these centred objects is the
-- middle of the sprite: an OAM entry at dbsprite -1, -1 lands 8 pixels up and
-- left of it.  The positions below are origins for that reason.
--
-- Coordinates worth keeping, all from the ASM:
--
--   * the frontpic is PlaceGraphic's 7x7 box at hlcoord 7, 2, i.e. (56, 16).
--   * the stats panel is a `Textbox` at hlcoord 3, 0 with `lb bc, 6, 13` --
--     15x8 tiles -- drawn into vBGMap1, which is the WINDOW map, and the
--     window sits at hWY $50.  So it lands at (24, 80), under the pic.
--   * the link tube is a 12x3 tilemap at hlcoord 8, 2: (64, 16), 96x24.
--   * TradeAnim_RockingBall's `depixel 10, 11, 4, 0` is y first, and an OAM
--     object draws at (x - 8, y - 16), so the ball is at (80, 68).
--   * the tube bulge's `depixel 5, 11` is (80, 24), inside the tube.
--
-- SCX scrolls the BACKGROUND, so a positive hSCX moves the picture LEFT: the
-- give-mon pic arrives from the left while its window arrives from the right,
-- and the link tube slides in from the left and back out the same way.

local Anim = require("src.core.gen2.TradeAnim")
local Assets = require("src.render.Assets")
local Chrome = require("src.ui.gen2.Chrome")
local Font = require("src.render.Font")
local GbcPalette = require("src.render.GbcPalette")
local Music = require("src.core.Music")
local Palettes = require("src.world.gen2.Palettes")
local Sound = require("src.core.Sound")
local Strings = require("src.core.Strings")
local TradeMenu = require("src.ui.gen2.TradeMenu")
local Unown = require("src.core.gen2.Unown")

local TradeAnimView = {}
TradeAnimView.__index = TradeAnimView
TradeAnimView.isOpaque = true

-- PlaceGraphic's box and the stats panel's Textbox, in tiles.
local PIC_TILE_X, PIC_TILE_Y, PIC_TILES = 7, 2, 7
local PANEL_X, PANEL_Y = 3, 0
local PANEL_INNER_W, PANEL_INNER_H = 13, 6
local WINDOW_Y = 0x50

-- TradeLinkTubeTilemap at hlcoord 8, 2.
local TUBE_X, TUBE_Y, TUBE_W, TUBE_H = 64, 16, 96, 24

-- The ball, the poof and the bulge, from their depixel rows.
local BALL_X, BALL_Y = 80, 68
local BULGE_Y = 24
-- TradeAnim_DropBall's SPRITEANIMSTRUCT_YOFFSET is $dc, i.e. -36: the ball
-- starts that far above its resting place and falls into it.
local DROP_OFFSET = -36

-- TradeAnim_Poof's wFrameCounter.
local POOF_FRAMES = 16

-- The unrolled Game Boy scene, in the pixels the three tilemap states put it
-- at once the 256-wide wrap is laid out flat.  State 0 has the Game Boy at
-- hlcoord 3, 2 with the cable starting at hlcoord 9, 3; state 2 has the second
-- one at hlcoord 10, 6 with the cable turning down at column 17 -- and state 2
-- is only ever seen after the window has wrapped, so its columns sit a full
-- $100 further along.
local GB_W, GB_H = 48, 64
local GB_A_X, GB_A_Y = 24, 16
local GB_B_X, GB_B_Y = 0x100 + 80, 48
local CABLE_Y = 3 * 8 + 4
local CABLE_FROM = 72
local CABLE_TURN = 0x100 + 17 * 8
local CABLE_DOWN_TO = 7 * 8
local CABLE_IN = 0x100 + 16 * 8

-- The same scene as tiles.  TradeAnim_TubeAnimJumptable ByteFills the cable
-- around the two TradeGameBoyTilemap stamps rather than drawing it from a
-- tilemap of its own: $5b is the plug that meets a Game Boy, $60 the
-- horizontal run, $5d the corner turning down, $61 the vertical run and $5f
-- the corner turning back left.  Unrolled, columns 0-31 are state 0's map and
-- 32-51 are state 2's, which is the same 256-pixel wrap the pixel constants
-- above lay out flat; state 1 is only ever the middle of that run.
--
-- Columns 20-31 of row 3 are TradeAnim_InitTubeAnim's own
-- `hlbgcoord 20, 3 / ld bc, 12 / ld a, $60`, off the right of the 20-wide
-- tilemap, which is what keeps the cable unbroken across the seam.
local CABLE_PLUG, CABLE_RUN = 0x5b, 0x60
local CABLE_CORNER_DOWN, CABLE_DROP, CABLE_CORNER_IN = 0x5d, 0x61, 0x5f
local CABLE_CELLS = {}
do
  local function cell(column, row, id)
    CABLE_CELLS[#CABLE_CELLS + 1] = { column, row, id }
  end
  cell(9, 3, CABLE_PLUG)
  for column = 10, 48 do cell(column, 3, CABLE_RUN) end
  cell(49, 3, CABLE_CORNER_DOWN)
  for row = 4, 6 do cell(49, row, CABLE_DROP) end
  cell(49, 7, CABLE_CORNER_IN)
  cell(48, 7, CABLE_PLUG)
end

-- The strip TradeAnim_PlaceTrademonStatsOnTubeAnim leaves under the two pans.
-- It is written into vBGMap1, which is the WINDOW map, and
-- TradeAnim_InitTubeAnim then parks the window at hWX $7 / hWY $70: window
-- column 0 lands at screen x 0 and window row 0 at y 112, so four rows show.
--
--   row 0  SCREEN_WIDTH of '─'
--   row 1  wLinkPlayer1Name at hlcoord 0, 1 -- TradeAnimation loads that from
--          wPlayerTrademonSenderName, so it is the player
--   row 2  six arrow tiles ByteFilled at hlcoord 7, 2, pointing the way the
--          trade is going: TradeAnim_TubeToOT1 passes the right arrow,
--          TradeAnim_TubeToPlayer1 the left one
--   row 3  wLinkPlayer2Name, right-aligned.  `hlcoord 0, 4 / add hl, de` with
--          de = -(name length) is one linear subtraction across the row
--          boundary, which lands it at column 20 - length of row 3.
local STRIP_Y = 0x70
local STRIP_RULE_ROW, STRIP_NAME_ROW = 0, 1
local STRIP_ARROW_ROW, STRIP_OT_ROW = 2, 3
local STRIP_ARROW_X, STRIP_ARROWS = 7, 6

-- The speech box every text beat prints into, and its two lines.
local BOX_X, BOX_Y, BOX_W, BOX_H = 0, 12, 20, 6
local TEXT_X, TEXT_Y, TEXT_LINE = 1, 14, 2

-- Which beats hold the speech box open.  The cart reaches
-- TradeAnim_SentToOTText with a cleared tilemap and prints into it from there;
-- TradeAnim_ScrollOutRight clears it again before each pan, and
-- TradeAnim_TakeCareOfText opens a last one over the received mon.
local BOX_BEATS = {
  sent_blank = true, sent_text = true, ot_sends_a = true, ot_sends_b = true,
  farewell_a = true, farewell_b = true, take_care = true,
}

-- The beats that show the give-mon panel, the ones that show the tube, and the
-- ones that show the received mon.
local GIVE_BEATS = { givemon_scroll = true, givemon_hold = true }
local TUBE_BEATS = {
  tube_in = true, tube_hold = true, ball_rock = true, bulge = true,
  tube_in2 = true, tube_hold2 = true, tube_out = true, ball_wait = true,
}
local GET_BEATS = {
  getmon_poof = true, getmon_hold = true, take_care = true,
}

-- Fallbacks for a cache built before the extractor reached the animation's own
-- lines (data/text/common_1.asm).  Each is transcribed with the buffer list
-- its text_ram rows name, so the two mons and the two trainers cannot swap.
local FALLBACK = {
  _MonWasSentToText = {
    text = Strings.source("{STRBUF} was\nsent to {STRBUF}."),
    buffers = { "wPlayerTrademonSpeciesName", "wOTTrademonSenderName" },
  },
  _ForYourMonSendsText = {
    text = Strings.source("For {STRBUF}'s\n{STRBUF},"),
    buffers = { "wPlayerTrademonSenderName", "wPlayerTrademonSpeciesName" },
  },
  _OTSendsText = {
    text = Strings.source("{STRBUF} sends\n{STRBUF}."),
    buffers = { "wOTTrademonSenderName", "wOTTrademonSpeciesName" },
  },
  _BidsFarewellToMonText = {
    text = Strings.source("{STRBUF} bids\nfarewell to"),
    buffers = { "wOTTrademonSenderName" },
  },
  _MonNameBidsFarewellText = {
    text = Strings.source("{STRBUF}."),
    buffers = { "wOTTrademonSpeciesName" },
  },
  _TakeGoodCareOfMonText = {
    text = Strings.source("Take good care of\n{STRBUF}."),
    buffers = { "wOTTrademonSpeciesName" },
  },
}

-- TrademonStats_MonTemplate's own string, placed at hlcoord 4, 0.  `next` in a
-- text box steps TWO rows, which is why the template's four lines land on the
-- rows PrintSpeciesName / PrintOTName / PrintTrademonID write into (0, 2, 4
-- and 6).
local TEMPLATE_ROWS = {
  { row = 0, text = "─── №." },
  { row = 4, text = "OT/" },
  { row = 6, text = "<ID>№." },
}

-- gfx/sgb/predef.pal:29
local function scale5(value) return math.floor(value * 255 / 31 + 0.5) end
local TRADE_TUBE_PAL = {
  { scale5(31), scale5(31), scale5(31) },
  { scale5(18), scale5(20), scale5(27) },
  { scale5(11), scale5(15), scale5(23) },
  { 0, 0, 0 },
}

--------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------

function TradeAnimView:wantsFillScale() return true end
function TradeAnimView:drawsWidescreen() return true end

-- opts:
--   row       the npc_trades.asm row, for the OT name and id
--   given     the party record that just left (NpcTrade.perform's first answer)
--   received  the one that arrived (its second)
--   save      for the player's own name and id
--   eventTables  data/generated/events.lua, for the animation's lines
--   onDone()  fired once, on the last frame or on a skip
function TradeAnimView.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, TradeAnimView)
  self.game = game
  self.data = (game and game.data) or {}
  self.palettes = self.data.gen2Palettes
  self.save = opts.save or (game and game.save)
  self.row = opts.row
  self.eventTables = opts.eventTables or {}
  self.onDone = opts.onDone
  self.give, self.get = Anim.records(self.data, self.save, self.row,
    opts.given, opts.received)
  self.frame = -1
  self.beatIndex = nil
  self.picCache = {}
  self.iconCache = {}
  self.gfx = opts.gfx or self.data.gen2Trade
  self.imageCache = {}
  self.quadCache = {}
  -- RunTradeAnimScript's `ld de, MUSIC_EVOLUTION / call PlayMusic2`.  The map
  -- theme comes back on the way out, which is NPCTrade's own RestartMapMusic.
  local songs = self.data.audio and self.data.audio.songs
  if songs and songs.Music_Evolution then
    Music.play(self.data, "Music_Evolution", true, { reason = "trade" })
  end
  self:step()
  return self
end

function TradeAnimView:playSfx(name)
  local sfx = self.data.audio and self.data.audio.sfx
  if sfx and sfx[Sound.resolve(self.data, name)] then
    Sound.play(self.data, name)
  end
end

function TradeAnimView:playCry(species)
  local cries = self.data.audio and self.data.audio.cries
  if species and cries and cries[species] then
    Sound.playCry(self.data, species)
  end
end

--------------------------------------------------------------------------
-- Clock
--------------------------------------------------------------------------

-- One frame of DoTradeAnimation: pick the beat this frame lands in and, when
-- that is a new one, fire the setup the commands before it did.
function TradeAnimView:step()
  self.frame = self.frame + 1
  local beat, offset, index = Anim.beatAt(self.frame)
  self.beat, self.offset = beat, offset
  if index ~= self.beatIndex then
    self.beatIndex = index
    self:cue(beat.cue)
  end
end

function TradeAnimView:cue(cue)
  if cue == "show_give" then
    -- TradeAnim_ShowGivemonData: the stats, the frontpic, then the cry.
    self:playCry(self.give.species)
  elseif cue == "poof" then
    -- TradeAnim_Poof's SFX_BALL_POOF, then EnterLinkTube1's SFX_POTION.
    self:playSfx("Sfx_BallPoof")
    self:playSfx("Sfx_Potion")
  elseif cue == "tube" then
    self:playSfx("Sfx_Potion")
  elseif cue == "give_sfx" then
    self:playSfx("Sfx_GiveTrademon")
  elseif cue == "get_sfx" then
    self:playSfx("Sfx_GetTrademon")
  elseif cue == "drop" then
    self:playSfx("Sfx_BallPoof")
  elseif cue == "show_get" then
    self:playSfx("Sfx_BallPoof")
    self:playCry(self.get.species)
  end
end

function TradeAnimView:finish()
  if self.done then return end
  self.done = true
  -- NPCTrade's RestartMapMusic, which runs before TradedForText.
  Music.restoreMap(self.data)
  if self.onDone then self.onDone() end
end

function TradeAnimView:update(_dt)
  if self.done then return end
  local input = self.game and self.game.input
  if input and (input:wasPressed("b") or input:wasPressed("start")) then
    return self:finish()
  end
  if self.frame + 1 >= Anim.TOTAL then return self:finish() end
  self:step()
end

--------------------------------------------------------------------------
-- Text
--------------------------------------------------------------------------

-- The four buffers the animation's lines name.  The port decodes every
-- text_ram to the same {STRBUF}, so which mon or trainer a marker meant comes
-- out of the buffer list the extractor recorded beside the text.
function TradeAnimView:buffers()
  return {
    wPlayerTrademonSpeciesName = self.give.name,
    wPlayerTrademonSenderName = self.give.senderName,
    wOTTrademonSpeciesName = self.get.name,
    wOTTrademonSenderName = self.get.senderName,
  }
end

function TradeAnimView.fill(body, names, buffers)
  local index = 0
  return (tostring(body or ""):gsub("{STRBUF}", function()
    index = index + 1
    local slot = (buffers or {})[index]
    return (slot and names[slot]) or names.wOTTrademonSpeciesName or ""
  end))
end

-- The line a beat prints, as up to two rows.  The cache wins; the fallback is
-- the same string with the same buffer order.
function TradeAnimView:lines(id)
  local label = Anim.TEXT[id]
  if not label then return nil end
  local texts = self.eventTables.tradeTexts or {}
  local body = texts[label]
  local buffers = (self.eventTables.tradeBuffers or {})[label]
  if type(body) ~= "string" then
    local fallback = FALLBACK[label]
    if not fallback then return nil end
    body, buffers = fallback.text, fallback.buffers
  end
  local pages = TradeMenu.paginate(
    TradeAnimView.fill(body, self:buffers(), buffers))
  return pages[1]
end

--------------------------------------------------------------------------
-- Draw helpers
--------------------------------------------------------------------------

-- Every shape on this screen is one of the four colours of the text palette,
-- which is what SCGB_TRADE_TUBE and TradeAnim_NormalPals leave the background
-- reading through.
-- `index` is a GB shade, 0 (white) to 3 (black); GbcPalette.color counts from
-- 1, as the palettes themselves do.
function TradeAnimView:bgColors()
  local id = (self.beat or {}).id or ""
  local pan = id:find("_pan_", 1, true)
  if not pan then
    return Palettes.textColors(self.palettes)
  end
  local colors = TRADE_TUBE_PAL
  -- engine/movie/trade_animation.asm:1271
  if math.floor((self.frame or 0) / 8) % 2 == 1 then
    colors = { colors[1], colors[3], colors[2], colors[4] }
  end
  return colors
end

function TradeAnimView:shade(index)
  local colors = self:bgColors()
  local rgb = GbcPalette.color(colors, index + 1)
    or ({ { 255, 255, 255 }, { 168, 168, 168 }, { 96, 96, 96 },
          { 0, 0, 0 } })[index + 1]
  return rgb[1] / 255, rgb[2] / 255, rgb[3] / 255
end

function TradeAnimView:setShade(index)
  love.graphics.setColor(self:shade(index))
end

-- Art and shapes read through the same four colours, so a sheet is blitted
-- inside the palette the way a mon pic is: the PNG's own greys are shades 0-3
-- and GbcPalette maps them.  A driver with no shader draws the greys, which
-- is the DMG ramp and not a black frame.
function TradeAnimView:through(body)
  local colors = self:bgColors()
  love.graphics.setColor(1, 1, 1, 1)
  if colors and GbcPalette.available() then
    GbcPalette.with(colors, body)
  else
    body()
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function TradeAnimView:image(path)
  if not path then return nil end
  local cached = self.imageCache[path]
  if cached == nil then
    local ok, image = pcall(Assets.image, path)
    cached = ok and image or false
    if cached then cached:setFilter("nearest", "nearest") end
    self.imageCache[path] = cached
  end
  return cached or nil
end

-- One of the object sheets (ball, poof, bulge, bubble, arrows), as its image
-- and how many tiles across it is.  nil for a cache that predates
-- RomExtractorGen2:extractTrade, which is what puts every caller on its
-- fallback shape.
function TradeAnimView:art(key)
  local entry = self.gfx and self.gfx[key]
  if type(entry) ~= "table" then return nil end
  local image = self:image(entry.image)
  if not image then return nil end
  return image, entry.sheetTiles or 1
end

-- TradeGameBoyLZ's 49 tiles, plus the base tile id every tilemap byte counts
-- from ($31, because the BG runs in $8800 mode and the sheet went to vTiles2).
function TradeAnimView:sheet()
  local gfx = self.gfx
  if not (gfx and gfx.image) then return nil end
  local image = self:image(gfx.image)
  if not image then return nil end
  return image, gfx.sheetTiles or 7, gfx.baseTile or 0x31
end

function TradeAnimView:quad(image, across, index)
  local perImage = self.quadCache[image]
  if not perImage then
    perImage = {}
    self.quadCache[image] = perImage
  end
  local quad = perImage[index]
  if not quad then
    quad = love.graphics.newQuad(index % across * 8,
      math.floor(index / across) * 8, 8, 8, image:getDimensions())
    perImage[index] = quad
  end
  return quad
end

-- One 8x8 tile, optionally mirrored the way an OAM attribute mirrors it.  A
-- flipped draw scales by -1, so the anchor moves a tile along that axis.
function TradeAnimView:blit(image, across, index, x, y, flipX, flipY)
  love.graphics.draw(image, self:quad(image, across, index),
    x + (flipX and 8 or 0), y + (flipY and 8 or 0), 0,
    flipX and -1 or 1, flipY and -1 or 1)
end

-- A tilemap stamp (TradeAnim_CopyBoxFromDEtoHL), at the pixel its hlcoord
-- lands on.  false when there is no cache art, so the caller can fall back.
function TradeAnimView:drawTilemap(map, x, y)
  if type(map) ~= "table" or type(map.tiles) ~= "table" then return false end
  local image, across, base = self:sheet()
  if not image then return false end
  self:through(function()
    for index = 0, map.width * map.height - 1 do
      local id = map.tiles[index + 1]
      if id and id >= base then
        self:blit(image, across, id - base,
          x + index % map.width * 8, y + math.floor(index / map.width) * 8)
      end
    end
  end)
  return true
end

-- An object built out of one mirrored quadrant: `side` tiles square, drawn
-- four times into a sprite twice that size, centred on the origin x, y.  The
-- flipped halves count their tiles back the other way, which is exactly what
-- AddOrSubtractX's `-8 - a` does to each OAM entry.
function TradeAnimView:drawQuadrant(image, across, first, side, x, y)
  for quadY = 0, 1 do
    for quadX = 0, 1 do
      for tileY = 0, side - 1 do
        for tileX = 0, side - 1 do
          local dx = (quadX == 0) and (tileX - side) or (side - 1 - tileX)
          local dy = (quadY == 0) and (tileY - side) or (side - 1 - tileY)
          self:blit(image, across, first + tileY * side + tileX,
            x + dx * 8, y + dy * 8, quadX == 1, quadY == 1)
        end
      end
    end
  end
end

function TradeAnimView:pic(record)
  local species = record and record.species
  local def = species and self.data.pokemon and self.data.pokemon[species]
  local path = def and def.spriteFront
  -- TradeAnim_GetFrontpic (engine/movie/trade_animation.asm:795-804) runs
  -- `predef GetUnownLetter` before GetBaseData and GetMonFrontpic, so the mon
  -- in the tube is the form that was actually traded.  TradeAnim.records
  -- carries the DVs across for exactly this.
  if species == Unown.SPECIES then
    path = Unown.formSprite(self.data.pokemon, Unown.monLetter(record)) or path
  end
  if not path then return nil end
  local cached = self.picCache[path]
  if cached == nil then
    -- "and" would truncate the pcall's second return, so the call stands on
    -- its own line.
    local ok, image = pcall(Assets.image, path)
    cached = ok and image or false
    self.picCache[path] = cached
  end
  return cached or nil
end

-- TradeAnim_ShowFrontpic's PlaceGraphic: the pic is padded into the 7x7 box
-- bottom-first, so a short mon still stands on the box's floor.
function TradeAnimView:drawPic(record, offset)
  local image = self:pic(record)
  if not image then return end
  local G = love.graphics
  local w, h = image:getDimensions()
  local box = PIC_TILES * 8
  local px = PIC_TILE_X * 8 + math.floor((box - w) / 2) - offset
  local py = PIC_TILE_Y * 8 + (box - h)
  G.setColor(1, 1, 1, 1)
  local colors = Palettes.monColors(self.palettes, record.species,
    record.shiny)
  local function body() G.draw(image, px, py) end
  if colors and GbcPalette.available() then
    GbcPalette.with(colors, body)
  else
    body()
  end
end

-- ShowPlayerTrademonStats / ShowOTTrademonStats, in the window.
function TradeAnimView:drawStats(record, offset)
  local G = love.graphics
  G.push()
  G.translate(offset, WINDOW_Y)
  Chrome.textbox(PANEL_X, PANEL_Y, PANEL_INNER_W, PANEL_INNER_H)
  -- pokegold engine/movie/trade_animation.asm:883-897,925-929: PlaceString
  -- and PrintNum overwrite the border's own tile at cols 4-12, row 0.
  G.setColor(1, 1, 1, 1)
  G.rectangle("fill", (PANEL_X + 1) * 8, PANEL_Y * 8, 9 * 8, 8)
  for _, row in ipairs(TEMPLATE_ROWS) do
    Chrome.print(Strings(row.text), PANEL_X + 1, row.row)
  end
  Chrome.print(Chrome.number(record.dex or 0, 3, true), PANEL_X + 7, 0)
  Chrome.print(record.name, PANEL_X + 1, 2)
  Chrome.print(record.otName, PANEL_X + 4, 4)
  Chrome.print(Chrome.number(record.id or 0, 5, true), PANEL_X + 4, 6)
  G.pop()
end

-- TradeLinkTubeTilemap: a flat tube with a rounded cap at each end.  The
-- middle rows are hollow, which is what lets the bulge read as something
-- moving INSIDE it.
function TradeAnimView:drawTube(offset)
  local G = love.graphics
  local x = TUBE_X - offset
  if self:drawTilemap(self.gfx and self.gfx.tube, x, TUBE_Y) then return end
  self:setShade(3)
  G.rectangle("line", x + 0.5, TUBE_Y + 0.5, TUBE_W - 1, TUBE_H - 1, 6, 6)
  self:setShade(2)
  G.rectangle("fill", x + 4, TUBE_Y + 4, TUBE_W - 8, 2)
  G.rectangle("fill", x + 4, TUBE_Y + TUBE_H - 6, TUBE_W - 8, 2)
  G.setColor(1, 1, 1, 1)
end

-- TradeBallGFX, on .Frameset_TradePokeBallWobble: four frames of 3 ticks
-- each, frame 1 / frame 2 / frame 1 / frame 2 X-flipped, which is the wobble.
-- Frame 1 is tiles 0 and 1 as the ball's left half with the right half
-- mirrored; frame 2 is tiles 2-5 in a plain 2x2.  x, y is the origin, so the
-- object hangs 8 pixels up and left of it.
function TradeAnimView:drawBall(x, y, rocking)
  local G = love.graphics
  local image, across = self:art("ball")
  if image then
    local step = rocking and math.floor((self.offset or 0) / 3) % 4 or 0
    self:through(function()
      if step % 2 == 0 then
        self:blit(image, across, 0, x - 8, y - 8)
        self:blit(image, across, 0, x, y - 8, true)
        self:blit(image, across, 1, x - 8, y)
        self:blit(image, across, 1, x, y, true)
      else
        -- The fourth frame's B_OAM_XFLIP mirrors the whole object, so the
        -- two columns swap places as well as flipping.
        local flip = (step == 3)
        for index = 0, 3 do
          local column = index % 2
          if flip then column = 1 - column end
          self:blit(image, across, 2 + index,
            x - 8 + column * 8, y - 8 + math.floor(index / 2) * 8, flip)
        end
      end
    end)
    return
  end
  local lean = 0
  if rocking then lean = (math.floor(self.offset / 8) % 2 == 0) and -1 or 1 end
  local cx, cy = x + 4 + lean, y + 4
  self:setShade(3)
  G.circle("fill", cx, cy, 5)
  self:setShade(0)
  G.circle("fill", cx, cy, 4)
  self:setShade(3)
  G.rectangle("fill", cx - 4, cy - 1, 9, 2)
  G.circle("fill", cx, cy, 1.5)
  G.setColor(1, 1, 1, 1)
end

-- TradePoofGFX on .Frameset_TradePoof: three 4-tile frames at 4 ticks each,
-- then oamdelete.  Each frame is a 2x2 quadrant mirrored into a 32x32 puff.
function TradeAnimView:drawPoof(x, y, t)
  local G = love.graphics
  local image, across = self:art("poof")
  if image then
    local frame = math.min(2, math.floor(t / 4))
    self:through(function()
      self:drawQuadrant(image, across, frame * 4, 2, x, y)
    end)
    return
  end
  local step = math.floor(t / 4)
  local radius = 4 + step * 3
  self:setShade(3 - math.min(2, step))
  G.setLineWidth(2)
  G.circle("line", x + 4, y + 4, radius)
  G.setLineWidth(1)
  G.setColor(1, 1, 1, 1)
end

-- The unrolled Game Boy scene the two pans travel: the player's Game Boy, the
-- cable, the turn down and the other Game Boy.
function TradeAnimView:drawScene(pan)
  local G = love.graphics
  G.push()
  G.translate(-pan, 0)
  local image, across, base = self:sheet()
  if image and self.gfx.gameBoy then
    self:through(function()
      for _, cell in ipairs(CABLE_CELLS) do
        self:blit(image, across, cell[3] - base, cell[1] * 8, cell[2] * 8)
      end
    end)
    self:drawGameBoy(GB_A_X, GB_A_Y)
    self:drawGameBoy(GB_B_X, GB_B_Y)
    G.pop()
    G.setColor(1, 1, 1, 1)
    return
  end
  self:setShade(3)
  G.rectangle("fill", CABLE_FROM, CABLE_Y, CABLE_TURN - CABLE_FROM, 2)
  G.rectangle("fill", CABLE_TURN, CABLE_Y, 2, CABLE_DOWN_TO - CABLE_Y)
  G.rectangle("fill", CABLE_IN, CABLE_DOWN_TO, CABLE_TURN - CABLE_IN + 2, 2)
  self:drawGameBoy(GB_A_X, GB_A_Y)
  self:drawGameBoy(GB_B_X, GB_B_Y)
  G.pop()
  G.setColor(1, 1, 1, 1)
end

-- TradeGameBoyTilemap, 6x8 tiles: a body with a screen in its top half.
function TradeAnimView:drawGameBoy(x, y)
  local G = love.graphics
  if self:drawTilemap(self.gfx and self.gfx.gameBoy, x, y) then return end
  self:setShade(3)
  G.rectangle("fill", x, y, GB_W, GB_H, 5, 5)
  self:setShade(1)
  G.rectangle("fill", x + 4, y + 4, GB_W - 8, GB_H - 26, 2, 2)
  self:setShade(0)
  G.rectangle("fill", x + 8, y + 8, GB_W - 16, GB_H - 34)
  self:setShade(1)
  G.circle("fill", x + GB_W - 12, y + GB_H - 16, 3)
  G.circle("fill", x + GB_W - 22, y + GB_H - 12, 3)
  G.rectangle("fill", x + 8, y + GB_H - 17, 8, 3)
  G.rectangle("fill", x + 10, y + GB_H - 19, 3, 8)
  G.setColor(1, 1, 1, 1)
end

-- TradeCableGFX on .Frameset_TradeTubeBulge: two one-tile frames at 3 ticks
-- apiece, each mirrored into the 16x16 bulge that travels inside the tube.
-- It is called "cable" in gfx/trade/ but loaded at the tile the bulge's
-- $12/$13 dictionary offsets point at, which is the only thing that reads it.
function TradeAnimView:drawBulge(x, y, t)
  local image, across = self:art("bulge")
  if not image then return self:drawBall(x, y, false) end
  local frame = math.floor((t or 0) / 3) % 2
  self:through(function()
    self:drawQuadrant(image, across, frame, 1, x, y)
  end)
end

-- The bubble the mon icon rides in (TradeBubbleGFX plus MONICON_TRADE).  The
-- bubble is a 2x2 quadrant mirrored into 32x32 and the icon is a plain 2x2
-- (.OAMData_RedWalk), both centred on the same origin; the icon is the party
-- icon sheet's first frame, which is what LoadMenuMonIcon hands the sprite.
function TradeAnimView:drawBubble(record, x, y)
  local G = love.graphics
  local image, across = self:art("bubble")
  if image then
    self:through(function()
      self:drawQuadrant(image, across, 0, 2, x, y)
    end)
  else
    self:setShade(0)
    G.circle("fill", x, y, 11)
    self:setShade(3)
    G.circle("line", x + 0.5, y + 0.5, 11)
    G.setColor(1, 1, 1, 1)
  end
  self:drawIcon(record, x - 8, y - 8)
end

-- The window strip the two pans run over: the rule, the two trainers and the
-- six arrows between them.  The arrows are the only part that is art, so a
-- cache with no gfx/trade still gets the names.
function TradeAnimView:drawTubeStrip(sending)
  local G = love.graphics
  G.push()
  G.translate(0, STRIP_Y)
  Chrome.print(string.rep("─", Chrome.SCREEN_W), 0, STRIP_RULE_ROW)
  Chrome.print(self.give.senderName, 0, STRIP_NAME_ROW)
  Chrome.printRight(self.get.senderName, Chrome.SCREEN_W, STRIP_OT_ROW)
  local image, across = self:art("arrows")
  if image then
    self:through(function()
      for column = 0, STRIP_ARROWS - 1 do
        self:blit(image, across, sending and 0 or 1,
          (STRIP_ARROW_X + column) * 8, STRIP_ARROW_ROW * 8)
      end
    end)
  end
  G.pop()
  G.setColor(1, 1, 1, 1)
end

function TradeAnimView:drawIcon(record, x, y)
  local icons = self.data.gen2Icons
  local iconId = icons and icons.species and record.species
    and icons.species[record.species]
  local entry = iconId and icons.icons and icons.icons[iconId]
  if not (entry and entry.image) then return end
  local cached = self.iconCache[entry.image]
  if cached == nil then
    local ok, img = pcall(Assets.image, entry.image)
    cached = ok and img or false
    self.iconCache[entry.image] = cached
  end
  if not cached then return end
  local G = love.graphics
  local quad = love.graphics.newQuad(0, 0, 16, 16, cached:getDimensions())
  G.setColor(1, 1, 1, 1)
  local colors = Palettes.monColors(self.palettes, record.species,
    record.shiny)
  if colors and GbcPalette.available() then
    GbcPalette.with(colors, function() G.draw(cached, quad, x, y) end)
  else
    G.draw(cached, quad, x, y)
  end
end

--------------------------------------------------------------------------
-- Draw
--------------------------------------------------------------------------

function TradeAnimView:drawPanel()
  local id = (self.beat or {}).id
  local t = self.offset or 0
  -- engine/movie/trade_animation.asm:151
  local wasBattle = Font.useBattleExtra(true)
  Chrome.clear()

  if GIVE_BEATS[id] then
    local offset = (id == "givemon_scroll") and Anim.givemonOffset(t) or 0
    self:drawPic(self.give, offset)
    -- The window comes in from the other side: hWX is $88 out when hSCX is.
    self:drawStats(self.give, offset)
  elseif TUBE_BEATS[id] then
    self:drawTubeBeat(id, t)
  elseif GET_BEATS[id] then
    self:drawPic(self.get, 0)
    if id == "getmon_poof" then self:drawPoof(BALL_X, BALL_Y, t) end
    -- FrontpicScrollStart puts the window back up for Wait80, and
    -- TextboxScrollStart takes it away again for the last line.
    if id == "getmon_hold" then self:drawStats(self.get, 0) end
  else
    local pan = Anim.pan(id, t)
    if pan then self:drawPanBeat(id, t, pan) end
  end

  if BOX_BEATS[id] then
    Chrome.box(BOX_X, BOX_Y, BOX_W, BOX_H)
    for index, line in ipairs(self:lines(id) or {}) do
      Chrome.print(line, TEXT_X, TEXT_Y + (index - 1) * TEXT_LINE)
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
  Font.useBattleExtra(wasBattle)
end

function TradeAnimView:drawTubeBeat(id, t)
  local offset = 0
  if id == "tube_in" or id == "tube_in2" or id == "tube_out" then
    offset = Anim.tubeOffset(id, t)
  end
  self:drawTube(offset)
  if id == "tube_in" then
    -- The poof is still running while the cable slides over it, and the ball
    -- RockingBall spawned is already underneath.
    if t < POOF_FRAMES then
      self:drawPoof(BALL_X, BALL_Y, t)
    else
      self:drawBall(BALL_X, BALL_Y, true)
    end
  elseif id == "tube_hold" or id == "ball_rock" then
    self:drawBall(BALL_X, BALL_Y, true)
  elseif id == "bulge" then
    -- TradeAnim_AnimateTrademonInTube walks the bulge from one cap to the
    -- other over its 128 frames.
    local span = TUBE_W - 16
    local x = TUBE_X + 8 + math.floor(span * t / 128)
    self:drawBulge(x, BULGE_Y, t)
  elseif id == "tube_out" then
    -- DropBall starts the ball $dc (-36) above its rest and lets it fall.
    local drop = math.min(0, DROP_OFFSET + t)
    self:drawBall(BALL_X, BALL_Y + drop, false)
  elseif id == "ball_wait" then
    self:drawBall(BALL_X, BALL_Y, true)
  end
end

function TradeAnimView:drawPanBeat(id, t, pan)
  self:drawScene(pan)
  local sending = id:sub(1, 4) == "send"
  -- TradeAnim_AnimateTrademonInTube walks the object along the cable and then
  -- despawns it; it is only parked while the pan itself runs.
  local x, y = Anim.tubeIcon(id, t)
  if x then
    self:drawBubble(sending and self.give or self.get, x, y)
  end
  self:drawTubeStrip(sending)
end

function TradeAnimView:draw()
  self:drawPanel()
end

function TradeAnimView:drawWidescreen(winW, winH)
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  G.rectangle("fill", 0, 0, winW, winH)
  local scale = Chrome.fitScale(winW, winH)
  G.push()
  G.translate(Chrome.fitOrigin(winW, winH, scale))
  G.scale(scale, scale)
  self:drawPanel()
  G.pop()
end

return TradeAnimView
