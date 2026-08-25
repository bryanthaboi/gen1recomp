-- The player-name menu (pokegold engine/menus/intro_menu.asm NamePlayer,
-- data/player_names.asm NameMenuHeader).
--
-- Transcribed from the header rather than laid out by eye, because almost
-- every coordinate here comes out of one:
--
--   menu_coords 0, 0, 10, TEXTBOX_Y - 1     the box: (0,0) to (10,11)
--   STATICMENU_CURSOR | STATICMENU_PLACE_TITLE | STATICMENU_DISABLE_B
--   5 items, default option 1, title indent 2, title "NAME"
--
-- GetMenuTextStartCoord turns those flags into the label origin: the border
-- costs a row and a column, STATICMENU_CURSOR costs another column, and the
-- absence of STATICMENU_NO_TOP_SPACING costs another row -- so the labels
-- start at (2,2) and step TWO rows each (PlaceVerticalMenuItems adds
-- 2 * SCREEN_WIDTH per item).  The cursor sits one column left of the labels,
-- at column 1.  The title is placed from MenuBoxCoord2Tile plus the indent,
-- which lands it ON the box's top border at (2,0).
--
-- The other half of the screen is the pic.  NamePlayer opens by calling
-- MovePlayerPicRight, which walks the 7x7 CAL frontpic OakSpeech left at
-- hlcoord 6,4 one tile per frame until it sits at hlcoord 13,4 -- so the menu
-- is not on its own, it slides in beside the player.  Picking a preset runs
-- MovePlayerPicLeft to walk it back before returning to the speech.
--
-- STATICMENU_DISABLE_B is why B does nothing here: there is no way out of
-- this menu except choosing a name.

local Chrome = require("src.ui.gen2.Chrome")
local Font = require("src.render.Font")
local GbcPalette = require("src.render.GbcPalette")
local Screens = require("src.ui.Screens")

local NamePick = {}
NamePick.__index = NamePick
NamePick.isOpaque = true

-- data/player_names.asm PlayerNameArray, one half of the IF per edition, and
-- Crystal's two arrays at ../pokecrystal/data/player_names.asm:12-16, :31-35.
local PRESETS = {
  gold = { "GOLD", "HIRO", "TAYLOR", "KARL" },
  silver = { "SILVER", "KAMON", "OSCAR", "MAX" },
  crystal = { "CHRIS", "MAT", "ALLAN", "JON" },
}
local PRESETS_FEMALE = {
  crystal = { "KRIS", "AMANDA", "JUANA", "JODI" },
}

-- ShowPlayerNamingChoices picks the header off wPlayerGender
-- (../pokecrystal/engine/gfx/player_gfx.asm:57-62).
local function presetsFor(gender)
  local version = require("src.core.GameVersion").get()
  if gender == "female" and PRESETS_FEMALE[version] then
    return PRESETS_FEMALE[version]
  end
  return PRESETS[version] or PRESETS.gold
end

-- menu_coords 0, 0, 10, TEXTBOX_Y - 1 (TEXTBOX_Y = 12).
local BOX_X1, BOX_Y1, BOX_X2, BOX_Y2 = 0, 0, 10, 11
-- GetMenuTextStartCoord's answer for this header's flags.
local TEXT_X, TEXT_Y = 2, 2
local CURSOR_X = TEXT_X - 1
local TITLE, TITLE_X, TITLE_Y = "NAME", 2, 0

-- Intro_PrepTrainerPic puts the 7x7 pic at hlcoord 6,4; MovePlayerPic walks
-- it to 13,4 one tile per frame.
local PIC_X_LEFT, PIC_X_RIGHT, PIC_Y = 6, 13, 4
local PIC_TILES = 7

function NamePick:wantsFillScale() return true end
function NamePick:drawsWidescreen() return true end

-- opts: onDone(name), font, pic (the CAL frontpic already loaded by the Oak
-- speech), picColors, presets, gender
function NamePick.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, NamePick)
  self.game = game
  self.onDone = opts.onDone
  self.gender = opts.gender
    or (game and game.save and game.save.player and game.save.player.gender)
  self.items = { "NEW NAME" }
  for _, name in ipairs(opts.presets or presetsFor(self.gender)) do
    self.items[#self.items + 1] = name
  end
  -- `db 1 ; default option`: the cursor starts on NEW NAME, not on a preset.
  self.cursor = 1
  self.pic = opts.pic
  self.picColors = opts.picColors
  self.fontOk = false
  local font = opts.font
  if font then
    self.fontOk = pcall(Font.load, { font = font })
  end
  -- The approach walk, and then the walk back once a preset is taken.  picX
  -- is the pic's live tile column rather than a step count: MovePlayerPic
  -- walks it one tile per frame and both directions end where they end, so
  -- the column IS the state.
  self.picX = PIC_X_LEFT
  self.slide = "in"
  return self
end

function NamePick:choose(name)
  if self.onDone then self.onDone(name) end
end

-- NEW NAME opens Gold's own keyboard (src/ui/gen2/NamingScreen.lua), not
-- Gen 1's: the two differ in grid size, the case switch, and where DEL/END sit.
function NamePick:openNaming()
  local data = self.game and self.game.data or {}
  local sprites = data.gen2Sprites
  local NamingScreen = require("src.ui.gen2.NamingScreen")
  local def = sprites and sprites[NamingScreen.playerSprite(self.gender)]
  local Palettes = require("src.world.gen2.Palettes")
  Screens.push(self.game, "Gen2NamingScreen", {
    type = "player",
    gender = self.gender,
    menuGfx = data.gen2MenuGfx,
    iconPath = def and def.image or nil,
    -- Chris is PAL_OW_RED and Kris PAL_OW_BLUE
    -- (../pokecrystal/engine/overworld/player_object.asm:32-39); the naming
    -- screen is lit like day.
    iconColors = data.gen2Palettes
      and Palettes.spritePalette(data.gen2Palettes, "DAY", def) or nil,
    onDone = function(name)
      -- An empty name keeps the default, the way ending entry with nothing
      -- typed leaves wPlayerName at its preset.
      self.game.stack:pop() -- the naming screen
      if name and #name > 0 then
        self:choose(name)
      else
        self:choose(self.items[2] or presetsFor(self.gender)[1])
      end
    end,
  })
end

function NamePick:update(_dt)
  -- MovePlayerPic is a blocking DelayFrame loop on the cart: nothing reads
  -- the joypad until the pic has finished walking.
  if self.slide == "in" then
    if self.picX < PIC_X_RIGHT then
      self.picX = self.picX + 1
      return
    end
    self.slide = nil
    return
  elseif self.slide == "out" then
    if self.picX > PIC_X_LEFT then
      self.picX = self.picX - 1
      return
    end
    self.slide = nil
    self:choose(self.pendingName)
    return
  end

  local input = self.game.input
  if not input then return end
  if input:wasPressed("up") then
    self.cursor = self.cursor > 1 and self.cursor - 1 or #self.items
  elseif input:wasPressed("down") then
    self.cursor = self.cursor < #self.items and self.cursor + 1 or 1
  elseif input:wasPressed("a") or input:wasPressed("start") then
    -- `ld a, [wMenuCursorY]; dec a; jr z, .NewName`: item 1 is NEW NAME and
    -- everything else is a preset.  B is deliberately not handled --
    -- STATICMENU_DISABLE_B.
    if self.cursor == 1 then
      if self.fontOk then
        self:openNaming()
      else
        self:choose(self.items[2] or presetsFor(self.gender)[1])
      end
    else
      -- A preset returns through MovePlayerPicLeft, so the pic walks back
      -- before the speech resumes.
      self.pendingName = self.items[self.cursor]
      self.slide = "out"
    end
  end
end

function NamePick:drawPic()
  if not self.pic then return end
  local G = love.graphics
  local w, h = self.pic:getDimensions()
  -- PlaceGraphic lays a 7x7 block from the coordinate; a pic smaller than
  -- that sits in the block's bottom-left, as PadFrontpic leaves it.
  local x = self.picX * 8
  local y = PIC_Y * 8 + (PIC_TILES - h / 8) * 8
  local function body()
    G.setColor(1, 1, 1, 1)
    G.draw(self.pic, x, y)
  end
  if self.picColors and GbcPalette.available() then
    GbcPalette.with(self.picColors, body)
  else
    body()
  end
  G.setColor(1, 1, 1, 1)
end

function NamePick:drawPanel()
  local G = love.graphics
  Chrome.clear()
  self:drawPic()
  -- The menu is only up once the pic has finished walking over: MenuBox is
  -- drawn by ShowPlayerNamingChoices, which NamePlayer calls after the walk.
  if self.slide == "in" then return end
  if not self.fontOk then
    G.setColor(0, 0, 0, 1)
    for index, label in ipairs(self.items) do
      local prefix = (index == self.cursor) and "> " or "  "
      G.print(prefix .. label, TEXT_X * 8, (TEXT_Y + (index - 1) * 2) * 8)
    end
    G.setColor(1, 1, 1, 1)
    return
  end
  -- MenuBox: GetMenuBoxDims then `dec b / dec c`, so the interior is one less
  -- than the span in each direction.
  Chrome.textbox(BOX_X1, BOX_Y1, BOX_X2 - BOX_X1 - 1, BOX_Y2 - BOX_Y1 - 1)
  -- PlaceString REPLACES the tilemap cells it lands on, and the title lands
  -- on the box's top border -- so the border tiles under it have to go, or
  -- the letters sit on a line the cart does not draw there.
  G.setColor(1, 1, 1, 1)
  G.rectangle("fill", TITLE_X * 8, TITLE_Y * 8, #TITLE * 8, 8)
  Chrome.print(TITLE, TITLE_X, TITLE_Y)
  for index, label in ipairs(self.items) do
    Chrome.print(label, TEXT_X, TEXT_Y + (index - 1) * 2)
  end
  Chrome.cursor(CURSOR_X, TEXT_Y + (self.cursor - 1) * 2)
  G.setColor(1, 1, 1, 1)
end

function NamePick:draw()
  self:drawPanel()
end

function NamePick:drawWidescreen(winW, winH)
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

NamePick.PRESETS = PRESETS
NamePick.PRESETS_FEMALE = PRESETS_FEMALE
NamePick.presetsFor = presetsFor

return NamePick
