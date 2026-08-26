-- The ALPH RUINS STAMP viewer (engine/events/print_unown.asm _UnownPrinter),
-- reached through `special UnownPrinter` (src/script/gen2/Specials.lua
-- H.UnownPrinter) from the Ruins of Alph research centre's printer once every
-- Unown form has been caught (RuinsOfAlphResearchCenterPrinter's `readvar
-- VAR_UNOWNCOUNT / ifequal NUM_UNOWN`).
--
-- _UnownPrinter is two halves and only one of them needs a peripheral: the
-- VIEWER -- the stamp sheet the player scrolls through with LEFT and RIGHT --
-- is drawn and driven entirely on the cartridge, and only the A press
-- (`farcall PrintUnownStamp`, engine/printer/printer.asm) walks the screen
-- out the serial port to a Game Boy Printer.  There is no printer here, the
-- same reason PrintDiploma's own print goes nowhere, so A lands on the
-- same arm a cartridge with nothing plugged into its link port takes: the
-- stamp does not print and the screen stays up.  Everything else is the
-- cart's.
--
-- RotateUnownFrontpic (engine/events/print_unown_2.asm) belongs to that
-- stubbed half and is deliberately not ported: it writes a 90-degree rotated
-- copy of the pic to vTiles2 tile $31, which nothing but
-- PlaceUnownPrinterFrontpic -- the PRINTED page -- ever reads.  The pic on
-- screen is the upright one at tiles $00-$30.
--
-- Coordinates below are the literal hlcoord operands _UnownPrinter writes at:
--
--   hlcoord 0, 0    Textbox, 3 rows by 18 columns
--   hlcoord 0, 5    Textbox, 7 by 7 -- the frame round the stamp
--   hlcoord 0, 14   Textbox, 2 by 18
--   hlcoord 1, 2    " ALPH RUINS STAMP"
--   hlcoord 1, 16   "Do what?"
--   hlcoord 10, 6   the four-row menu, one row per `next`
--   hlcoord 1, 6    the 7x7 frontpic, or ClearBox + "VACANT" at hlcoord 1, 9
--
-- The menu's first two rows start with the bold A and B tiles
-- (gfx/printer/bold_a.1bpp / bold_b.1bpp, requested into vTiles0 at the ♂/♀
-- character cells).  Those two tiles are not extracted -- they exist only for
-- this screen -- so the ordinary font's A and B stand in for them, which is
-- the same pair of letters in a lighter weight.
--
-- THE SHEET IS ALL 26 FORMS, not the caught ones: .UpdateUnownFrontpic loads
-- `wJumptableIndex + 1` as the letter whatever the #DEX holds, and the 27th
-- slot is the blank stamp the cart labels VACANT.  The gate is on the way in
-- instead (H.UnownPrinter's `ld a, [wUnownDex] / and a / ret z`).

local Assets = require("src.render.Assets")
local Chrome = require("src.ui.gen2.Chrome")
local GbcPalette = require("src.render.GbcPalette")
local Palettes = require("src.world.gen2.Palettes")
local Strings = require("src.core.Strings")
local Unown = require("src.core.gen2.Unown")

local UnownPrinter = {}
UnownPrinter.__index = UnownPrinter
UnownPrinter.isOpaque = true

function UnownPrinter:wantsFillScale() return true end

-- AlphRuinsStampString keeps its leading space: the string starts at column 1
-- and the space is what puts the S of STAMP under the box's own edge.
local TEXT = {
  title = Strings.source(" ALPH RUINS STAMP"),
  doWhat = Strings.source("Do what?"),
  vacant = Strings.source("VACANT"),
  menu = {
    Strings.source("A▶PRINT"),
    Strings.source("B▶CANCEL"),
    Strings.source("L▶BEFORE"),
    Strings.source("R▶NEXT"),
  },
}

-- opts: pokemon, palettes, onClose()
function UnownPrinter.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, UnownPrinter)
  self.game = game
  local data = (game and game.data) or {}
  self.pokemon = opts.pokemon or data.pokemon
  self.palettes = opts.palettes or data.gen2Palettes
  self.onClose = opts.onClose
  -- wJumptableIndex: 0..NUM_UNOWN - 1 are the letters and NUM_UNOWN is the
  -- vacant slot, so the wheel is 27 long.
  self.index = 0
  self.done = false
  self.picCache = {}
  return self
end

function UnownPrinter:slots()
  return Unown.NUM_UNOWN + 1
end

-- The letter this slot shows, or nil for the vacant one.
function UnownPrinter:letter()
  if self.index >= Unown.NUM_UNOWN then return nil end
  return self.index + 1
end

function UnownPrinter:finish()
  if self.done then return end
  self.done = true
  if self.onClose then self.onClose() end
end

-- .LeftRight, and the two wraps below it: RIGHT past the vacant slot comes
-- back to A, LEFT off A goes to the vacant slot.  The cart reads hJoyLast
-- rather than hJoyPressed for these two, so holding the pad scrolls; edge
-- detection is close enough here and is what every other Gold menu in the
-- port uses.
function UnownPrinter:update(_dt)
  if self.done then return end
  local input = self.game and self.game.input
  if not input then return end
  if input:wasPressed("b") then
    -- .pressed_b: restore hInMenu/wOptions and ReturnToMapFromSubmenu.
    self:finish()
    return
  end
  if input:wasPressed("a") then
    -- .pressed_a is `farcall PrintUnownStamp / call RestartMapMusic` and then
    -- straight back into the joypad loop.  With no printer there is nothing
    -- to send and nothing to restart, so this is deliberately a no-op rather
    -- than a screen the player has to back out of twice.
    return
  end
  if input:wasPressed("right") then
    self.index = (self.index + 1) % self:slots()
  elseif input:wasPressed("left") then
    self.index = (self.index - 1) % self:slots()
  end
end

function UnownPrinter:picFor(letter)
  local path = Unown.formSprite(self.pokemon, letter, false)
  if not path then return nil end
  local cached = self.picCache[path]
  if cached == nil then
    -- `and` truncates a multi-return, so the pcall has to stand alone.
    local ok, image = pcall(Assets.image, path)
    cached = (ok and image) or false
    self.picCache[path] = cached
  end
  return cached or nil
end

-- .UpdateUnownFrontpic: PlaceGraphic of the form's 7x7 pic at hlcoord 1, 6.
function UnownPrinter:drawPic(letter)
  local image = self:picFor(letter)
  if not image then return end
  local colors = self.palettes
    and Palettes.monColors(self.palettes, Unown.SPECIES)
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  local function body() G.draw(image, 1 * 8, 6 * 8) end
  if colors and GbcPalette.available() then
    GbcPalette.with(colors, body)
  else
    body()
  end
  G.setColor(1, 1, 1, 1)
end

function UnownPrinter:drawPanel()
  Chrome.clear()
  Chrome.textbox(0, 0, 18, 3)
  Chrome.textbox(0, 5, 7, 7)
  Chrome.textbox(0, 14, 18, 2)

  Chrome.print(Strings(TEXT.title), 1, 2)
  Chrome.print(Strings(TEXT.doWhat), 1, 16)
  for i, row in ipairs(TEXT.menu) do
    Chrome.print(Strings(row), 10, 5 + i)
  end

  local letter = self:letter()
  if letter then
    self:drawPic(letter)
  else
    -- .vacant: ClearBox over the 7x7 block, then VACANT across its middle.
    Chrome.print(Strings(TEXT.vacant), 1, 9)
  end
end

function UnownPrinter:draw()
  self:drawPanel()
end

-- _PrintUnown opens on ClearBGPalettes / ClearTilemap
-- (engine/events/print_unown.asm:17-18), so the #DEX screen underneath is
-- gone.  The panel starts from Chrome.clear(), so white IS the surround.
function UnownPrinter:drawsWidescreen() return true end

function UnownPrinter:drawWidescreen(winW, winH)
  local G = love.graphics
  G.setColor(1, 1, 1, 1)
  G.rectangle("fill", 0, 0, winW, winH)
  local scale = Chrome.fitScale(winW, winH)
  local ox, oy = Chrome.fitOrigin(winW, winH, scale)
  G.push()
  G.translate(ox, oy)
  G.scale(scale, scale)
  self:drawPanel()
  G.pop()
end

return UnownPrinter
