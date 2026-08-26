-- The Cianwood photo studio's portrait card (engine/printer/print_party.asm
-- PrintPartyMonPage1), reached through `special PhotoStudio` (src/script/
-- gen2/Specials.lua H.PhotoStudio) once the fishing guru's own yes/no gate
-- (CianwoodPhotoStudioFishingGuruScript, maps/CianwoodPhotoStudio.asm) has
-- been answered yes and a party mon picked.
--
-- On the cart, farcall PrintPartymon draws PrintPartyMonPage1 to the
-- background so SendScreenToPrinter has pixels to walk out the serial port,
-- then a second card (PrintPartyMonPage2, the mon's other three moves and
-- its non-HP stats) goes out behind it.  There is no Game Boy Printer here
-- -- same reason src/ui/gen2/UnownPrinter.lua takes its A press nowhere and
-- PrintDiploma's own print goes nowhere
-- -- so only page 1 is worth transcribing: it is the portrait itself, the
-- part a player actually watches happen, while page 2 only ever existed as
-- ink on a strip of thermal paper nobody in this port owns. H.PhotoStudio
-- pushes this screen for the "hold still" beat and then always lands on
-- the cancel branch afterward, exactly as a cartridge with nothing plugged
-- into its link port would.
--
-- Coordinates below are the literal hlcoord operands
-- PrintPartyMonPage1 writes at, not a layout guessed from a screenshot:
--
--   hlcoord 0, 0    PrepMonFrontpic, a 7x7 block
--   hlcoord 8, 0    "№." then the dex number, 3 digits, leading zeros
--   hlcoord 8, 2    the level (PrintLevel_Force3Digits)
--   hlcoord 12, 2   the HP icon then the max HP, 3 digits -- one field, no
--                   separate current-HP column
--   hlcoord 8, 4    the nickname
--   hlcoord 9, 6    a bare '/' then the species name at hlcoord 10, 6
--   hlcoord 0, 7    Textbox, 9 rows by 18 columns -- the border the fields
--                   below sit inside
--   hlcoord 1, 9    "OT/" then the OT name at hlcoord 4, 9
--   hlcoord 1, 11   "<ID>№" then the id number at hlcoord 4, 11, 5 digits
--   hlcoord 1, 14   "MOVE" then the first move's name at hlcoord 7, 14
--   PlaceGenderAndShininess: gender at hlcoord 17, 2, the shiny ⁂ at 18, 2
--
-- The pic-drawing and palette plumbing (picFor/drawPic, PIC_PAD) is the same
-- shape src/ui/gen2/SummaryMenu.lua uses for its own PrepMonFrontpic block;
-- kept as its own small copy here rather than reached through SummaryMenu so
-- this screen has no dependency on the stats screen's paging state.

local Assets = require("src.render.Assets")
local Chrome = require("src.ui.gen2.Chrome")
local Font = require("src.render.Font")
local GbcPalette = require("src.render.GbcPalette")
local Palettes = require("src.world.gen2.Palettes")
local Strings = require("src.core.Strings")

local PhotoStudio = {}
PhotoStudio.__index = PhotoStudio
PhotoStudio.isOpaque = true

function PhotoStudio:wantsFillScale() return true end

local PIC_PAD = { [7] = { 0, 0 }, [6] = { 1, 1 }, [5] = { 1, 2 } }

local function num(value, width, leadingZeros)
  return Chrome.number(value, width, leadingZeros)
end

-- opts: mon, playerName, pokemon, moves, palettes, onClose()
function PhotoStudio.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, PhotoStudio)
  self.game = game
  local data = (game and game.data) or {}
  local save = game and game.save
  self.mon = opts.mon
  self.playerName = opts.playerName
    or (save and save.player and save.player.name) or "?"
  self.pokemon = opts.pokemon or data.pokemon
  self.moves = opts.moves or data.moves
  self.palettes = opts.palettes or data.gen2Palettes
  self.onClose = opts.onClose
  self.done = false
  self.picCache = {}
  return self
end

function PhotoStudio:speciesDef()
  local mon = self.mon
  return mon and self.pokemon and self.pokemon[mon.species]
end

function PhotoStudio:finish()
  if self.done then return end
  self.done = true
  if self.onClose then self.onClose() end
end

function PhotoStudio:update(_dt)
  if self.done then return end
  local input = self.game and self.game.input
  if not input then return end
  if input:wasPressed("a") or input:wasPressed("b") then
    self:finish()
  end
end

function PhotoStudio:picFor(species)
  local def = species and self.pokemon and self.pokemon[species]
  local path = def and def.spriteFront
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

-- PrepMonFrontpic at hlcoord 0, 0: a 7x7 block with the pic centred in it.
function PhotoStudio:drawPic()
  local mon = self.mon
  local image = mon and self:picFor(mon.species)
  if not image then return end
  local G = love.graphics
  local colors = self.palettes and mon.species
    and Palettes.monColors(self.palettes, mon.species, mon.shiny) or nil
  local blank = colors and GbcPalette.color(colors, 1) or { 255, 255, 255 }
  G.setColor(blank[1] / 255, blank[2] / 255, blank[3] / 255, 1)
  G.rectangle("fill", 0, 0, 7 * 8, 7 * 8)

  local wide = math.floor(image:getWidth() / 8)
  local pad = PIC_PAD[wide] or PIC_PAD[7]
  G.setColor(1, 1, 1, 1)
  local function body() G.draw(image, pad[1] * 8, pad[2] * 8) end
  if colors and GbcPalette.available() then
    GbcPalette.with(colors, body)
  else
    body()
  end
  G.setColor(1, 1, 1, 1)
end

function PhotoStudio:moveName()
  local mon = self.mon
  local entry = mon and mon.moves and mon.moves[1]
  if not entry then return "-" end
  local def = self.moves and self.moves[entry.id]
  return (def and def.name) or entry.id
end

function PhotoStudio:drawPanel()
  -- PrintPartyMonPage1 opens with LoadFontsBattleExtra, and the card is
  -- written in that sheet's glyphs: '№' ($74), '<ID>' ($73) and '<LV>' ($6e)
  -- are a middle dot, a closing quote and a kana on the normal extra sheet.
  local wasBattle = Font.useBattleExtra(true)
  Chrome.clear()
  local mon = self.mon or {}
  local def = self:speciesDef()

  self:drawPic()

  Chrome.print(Strings("№."), 8, 0)
  Chrome.print(num((def and def.dex) or 0, 3, true), 10, 0)

  Chrome.print(Strings("<LV>") .. num(mon.level or 1, 2), 8, 2)
  -- `ld de, wTempMonMaxHP / lb bc, 2, 3 / call PrintNum`: one field, the
  -- mon's max HP -- the card has no separate current-HP column, unlike the
  -- stats screen's pink page.
  Chrome.print(Strings("HP"), 12, 2)
  Chrome.print(num(mon.maxHp or mon.hp or 0, 3), 14, 2)

  -- PlaceGenderAndShininess: gender at hlcoord 17, 2, the shiny ⁂ at 18, 2.
  if mon.gender == "male" then
    Chrome.print(Strings("♂"), 17, 2)
  elseif mon.gender == "female" then
    Chrome.print(Strings("♀"), 17, 2)
  end
  if mon.shiny then Chrome.print(Strings("⁂"), 18, 2) end

  Chrome.print(mon.nickname or mon.name or mon.species or "?", 8, 4)

  Chrome.print(Strings("/"), 9, 6)
  Chrome.print((def and def.name) or mon.species or "?", 10, 6)

  Chrome.textbox(0, 7, 18, 9)

  Chrome.print(Strings("OT/"), 1, 9)
  Chrome.print(mon.ot or self.playerName, 4, 9)

  Chrome.print(Strings("<ID>№"), 1, 11)
  Chrome.print(num(mon.otId or 0, 5, true), 4, 11)

  Chrome.print(Strings("MOVE"), 1, 14)
  Chrome.print(self:moveName(), 7, 14)
  Font.useBattleExtra(wasBattle)
end

function PhotoStudio:draw()
  self:drawPanel()
end

-- PrintPartyMonPage1 opens on ClearBGPalettes / ClearTilemap
-- (engine/printer/print_party.asm:134-135), so the card owns the screen
-- outright.  The panel itself starts from Chrome.clear(), so white IS the
-- surround here and the fill just carries it to the window edge.
function PhotoStudio:drawsWidescreen() return true end

function PhotoStudio:drawWidescreen(winW, winH)
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

return PhotoStudio
