-- ../pokecrystal/engine/events/unown_walls.asm:102 DisplayUnownWords, and the
-- Unown alphabet it writes out of ../pokecrystal/constants/charmap.asm:424;
-- :1 HoOhChamber, :13 OmanyteChamber, :54 SpecialAerodactylChamber and :81
-- SpecialKabutoChamber, the four routines that open the chambers' walls.

local Assets = require("src.render.Assets")
local Font = require("src.render.Font")
local GbcPalette = require("src.render.GbcPalette")
local Palettes = require("src.world.gen2.Palettes")
local Sound = require("src.core.Sound")

local UnownWords = {}
UnownWords.__index = UnownWords
UnownWords.isOpaque = false

-- engine/tilesets/map_palettes.asm:40, ../pokecrystal/constants/tileset_constants.asm:55
UnownWords.BANK1 = 0x80
UnownWords.BROWN = 6

-- ../pokecrystal/engine/events/unown_walls.asm:225 .YChar, :237 .ZChar, :249 .DashChar
local FIXED = {
  [0x60] = { 0x5b, 0x5c, 0x4d, 0x5d },
  [0x62] = { 0x4e, 0x4f, 0x5e, 0x5f },
  [0x64] = { 0x02, 0x03, 0x03, 0x02 },
}

function UnownWords.square(char)
  local fixed = FIXED[char]
  if fixed then return fixed[1], fixed[2], fixed[3], fixed[4] end
  local base = UnownWords.BANK1 + char
  return base, base + 1, base + 0x10, base + 0x11
end

-- ../pokecrystal/engine/events/unown_walls.asm:122-127
function UnownWords.origin(wall)
  return (wall.x1 or 0) + 1, (wall.y1 or 0) + 2
end

-- ../pokecrystal/engine/events/unown_walls.asm:119 MenuBox, home/menu.asm:131 GetMenuBoxDims
function UnownWords.boxRect(wall)
  local x1, y1 = wall.x1 or 0, wall.y1 or 0
  return x1, y1, (wall.x2 or x1) - x1 + 1, (wall.y2 or y1) - y1 + 1
end

-- ../pokecrystal/engine/events/unown_walls.asm:182 _DisplayUnownWords_CopyWord
function UnownWords.layout(wall)
  local tx, ty = UnownWords.origin(wall)
  local out = {}
  for index, char in ipairs(wall.chars or {}) do
    local tl, tr, bl, br = UnownWords.square(char)
    out[index] = {
      tx = tx + (index - 1) * 2, ty = ty,
      tl = tl, tr = tr, bl = bl, br = br,
    }
  end
  return out
end

-- ../pokecrystal/constants/event_flags.asm:486-489, the four Crystal-only
-- EVENT_WALL_OPENED_IN_*_CHAMBER bits.
UnownWords.WALL_OPENED = {
  HO_OH = 806,
  KABUTO = 807,
  OMANYTE = 808,
  AERODACTYL = 809,
}

-- ../pokecrystal/engine/events/unown_walls.asm:60, :87 -- the
-- GetMapAttributesPointer compare the two non-special routines are gated on.
UnownWords.CHAMBER_MAPS = {
  HO_OH = "RUINS_OF_ALPH_HO_OH_CHAMBER",
  KABUTO = "RUINS_OF_ALPH_KABUTO_CHAMBER",
  OMANYTE = "RUINS_OF_ALPH_OMANYTE_CHAMBER",
  AERODACTYL = "RUINS_OF_ALPH_AERODACTYL_CHAMBER",
}

-- ../pokecrystal/engine/events/unown_walls.asm:4, :22
UnownWords.HO_OH = "HO_OH"
UnownWords.WATER_STONE = "WATER_STONE"

-- ../pokecrystal/engine/events/unown_walls.asm:16 EventFlagAction CHECK_FLAG
function UnownWords.wallOpened(events, chamber)
  local flag = UnownWords.WALL_OPENED[chamber]
  if not (events and flag) then return false end
  return events:get(flag) and true or false
end

-- ../pokecrystal/engine/events/unown_walls.asm:8 EventFlagAction SET_FLAG
function UnownWords.openWall(events, chamber)
  local flag = UnownWords.WALL_OPENED[chamber]
  if not (events and flag) then return false end
  if events:get(flag) then return false end
  events:set(flag, true)
  return true
end

-- ../pokecrystal/engine/events/unown_walls.asm:2-5: wPartySpecies[0], which
-- holds EGG rather than the hatchling's species while a slot is an egg.
function UnownWords.leadIsHoOh(party)
  local lead = party and party[1]
  if not lead or lead.isEgg then return false end
  return lead.species == UnownWords.HO_OH
end

-- ../pokecrystal/engine/events/unown_walls.asm:28-43: wPartyCount down to 1,
-- MON_ITEM on each, so the LAST slot holding one is the one it stops at.
function UnownWords.waterStoneSlot(party)
  party = party or {}
  for slot = #party, 1, -1 do
    local mon = party[slot]
    if mon and mon.item == UnownWords.WATER_STONE then return slot end
  end
  return nil
end

-- ../pokecrystal/engine/events/unown_walls.asm:54, whose carry FlashFunction
-- jumps on at ../pokecrystal/engine/events/overworld.asm:285.
function UnownWords.aerodactylChamber(events, mapId)
  if mapId ~= UnownWords.CHAMBER_MAPS.AERODACTYL then return false end
  UnownWords.openWall(events, "AERODACTYL")
  return true
end

-- ../pokecrystal/engine/events/unown_walls.asm:81, off the escape rope arm of
-- EscapeRopeOrDig (../pokecrystal/engine/events/overworld.asm:809).
function UnownWords.kabutoChamber(events, mapId)
  if mapId ~= UnownWords.CHAMBER_MAPS.KABUTO then return false end
  UnownWords.openWall(events, "KABUTO")
  return true
end

-- ../pokecrystal/constants/script_constants.asm:319 UNOWNWORDS_*
function UnownWords.wallFor(data, scriptVar)
  local walls = data and data.gen2EventTables and data.gen2EventTables.unownWalls
  if not walls then return nil end
  return walls[(scriptVar or 0) + 1]
end

-- opts: wall (an events.unownWalls row), world, onClose()
function UnownWords.new(game, opts)
  opts = opts or {}
  local self = setmetatable({}, UnownWords)
  self.game = game
  self.wall = opts.wall
  self.world = opts.world
  self.onClose = opts.onClose
  self.done = false
  self.squares = self.wall and UnownWords.layout(self.wall) or {}
  return self
end

-- ../pokecrystal/engine/events/unown_walls.asm:155 _DisplayUnownWords_FillAttr
function UnownWords:tileset()
  local world = self.world
  local map = world and world.map
  local def = map and map.def
  local tileset = def and world.tilesets and world.tilesets[def.tileset]
  if not tileset or not tileset.image then return nil end
  if self.atlas == nil then
    local ok, image = pcall(Assets.image, tileset.image)
    self.atlas = ok and image or false
    if self.atlas then self.atlas:setFilter("nearest", "nearest") end
    local set = world.palettes
      and Palettes.bgSet(world.palettes, def, world.daytime or "DAY")
    self.colors = set and set[UnownWords.BROWN] or nil
  end
  if not self.atlas then return nil end
  return tileset, self.atlas
end

-- ../pokecrystal/engine/events/unown_walls.asm:147 PlayClickSFX, :148 CloseWindow
function UnownWords:finish()
  if self.done then return end
  self.done = true
  local game = self.game
  if game and game.data then Sound.play(game.data, "SFX_READ_TEXT_2") end
  if game and game.stack then game.stack:pop() end
  if self.onClose then self.onClose() end
end

function UnownWords:update(_dt)
  if self.done then return end
  local input = self.game and self.game.input
  if not input then return end
  if input:wasPressed("a") or input:wasPressed("b") then self:finish() end
end

function UnownWords:draw()
  local wall = self.wall
  if not wall then return end
  local bx, by, bw, bh = UnownWords.boxRect(wall)
  Font.drawBox(bx, by, bw, bh)
  local tileset, atlas = self:tileset()
  if not tileset then return end
  local perRow = tileset.tilesPerRow or 16
  local aw, ah = atlas:getDimensions()
  local quads = {}
  local function quadFor(tile)
    local q = quads[tile]
    if not q then
      q = love.graphics.newQuad((tile % perRow) * 8,
        math.floor(tile / perRow) * 8, 8, 8, aw, ah)
      quads[tile] = q
    end
    return q
  end
  local function body()
    love.graphics.setColor(1, 1, 1, 1)
    for _, square in ipairs(self.squares) do
      local x, y = square.tx * 8, square.ty * 8
      love.graphics.draw(atlas, quadFor(square.tl), x, y)
      love.graphics.draw(atlas, quadFor(square.tr), x + 8, y)
      love.graphics.draw(atlas, quadFor(square.bl), x, y + 8)
      love.graphics.draw(atlas, quadFor(square.br), x + 8, y + 8)
    end
  end
  if self.colors and GbcPalette.available() then
    GbcPalette.with(self.colors, body)
  else
    body()
  end
  love.graphics.setColor(0, 0, 0, 1)
end

return UnownWords
