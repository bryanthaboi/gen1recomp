local bit = require("bit")
local ImageWriter = require("src.import.ImageWriter")
local LuaWriter = require("src.import.LuaWriter")
local Rom = require("src.import.Rom")

local RomExtractor = {}
RomExtractor.__index = RomExtractor

local STAGE_COUNT = 17

local function copy(value, seen)
  if type(value) ~= "table" then return value end
  seen = seen or {}
  if seen[value] then return seen[value] end
  local result = {}
  seen[value] = result
  for key, item in pairs(value) do result[copy(key, seen)] = copy(item, seen) end
  return result
end

local function append(target, source)
  for _, value in ipairs(source) do target[#target + 1] = value end
end

local function unique(values)
  local result, seen = {}, {}
  for _, value in ipairs(values) do
    if not seen[value] then
      seen[value] = true
      result[#result + 1] = value
    end
  end
  return result
end

local function sorted(values)
  table.sort(values)
  return values
end

local function startsWith(value, prefix)
  return value:sub(1, #prefix) == prefix
end

local function round(value)
  return math.floor(value + 0.5)
end

local function hex(prefix, value)
  return ("%s_%02X"):format(prefix, value)
end

function RomExtractor.new(romData, manifest, progress)
  return setmetatable({
    rom = Rom.new(romData),
    manifest = manifest,
    symbols = manifest.symbols,
    progress = progress,
    stage = 0,
  }, RomExtractor)
end

function RomExtractor:symbol(name)
  local location = self.symbols[name]
  if not location then error("required symbol is missing: " .. tostring(name)) end
  return { bank = location[1], address = location[2], name = name }
end

function RomExtractor:beginStage(name)
  self.stage = self.stage + 1
  if self.progress then self.progress(self.stage - 1, STAGE_COUNT, name, 0, 1) end
end

function RomExtractor:tick(name, current, total)
  if self.progress then
    self.progress(self.stage - 1 + current / total, STAGE_COUNT,
      name, current, total)
  end
end

function RomExtractor:write(name, value)
  LuaWriter.write("data/generated/" .. name .. ".lua", value)
end

function RomExtractor:save(image, relative)
  ImageWriter.save(image, "assets/generated/" .. relative)
end

function RomExtractor:readTerminated(bank, address, terminator, limit)
  local out = {}
  for offset = 0, (limit or 256) - 1 do
    local value = self.rom:byte(bank, address + offset)
    if value == terminator then return out end
    out[#out + 1] = value
  end
  error(("unterminated byte list at %02X:%04X"):format(bank, address))
end

function RomExtractor:write2bpp(raw, width, height, relative, transparent)
  local image = ImageWriter.decode2bpp(raw, width, height, transparent)
  self:save(image, relative)
end

function RomExtractor:writeCompressedPic(label, relative)
  local symbol = self:symbol(label)
  local compressed = self.rom:bytes(
    symbol.bank, symbol.address, 0x8000 - symbol.address)
  local raw, width = Rom.decompressPic(compressed)
  local image = ImageWriter.matteColor0(
    ImageWriter.decode2bpp(raw, width * 8, width * 8))
  self:save(image, relative)
  return width
end

function RomExtractor:extractConstants()
  self:beginStage("Game constants")
  local data = self.manifest.constants
  self:write("constants", data)
  self:tick("Game constants", 1, 1)
  return data
end

function RomExtractor:extractTilesets()
  self:beginStage("World tiles")
  local manifest = self.manifest
  local order = manifest.constants.tilesetOrder
  local metadata = manifest.tilesets
  local animations = manifest.tileAnimations
  assert(#metadata == #order, "tileset metadata count does not match constants")

  local headers = self:symbol("Tilesets")
  local warpPointers = self:symbol("WarpTileIDPointers")
  local doorPointers = self:symbol("DoorTileIDPointers")
  local doors, address = {}, doorPointers.address
  while true do
    local tilesetId = self.rom:byte(doorPointers.bank, address)
    if tilesetId == 0xFF then break end
    local pointer = self.rom:word(doorPointers.bank, address + 1)
    doors[tilesetId] = self:readTerminated(
      doorPointers.bank, pointer, 0)
    address = address + 3
  end

  local out, written = {}, {}
  for index, constName in ipairs(order) do
    local spec = metadata[index]
    assert(spec.id == constName, "tileset metadata is out of order")
    local rowAddress = headers.address + (index - 1) * 12
    local gfxBank = self.rom:byte(headers.bank, rowAddress)
    local blockPointer = self.rom:word(headers.bank, rowAddress + 1)
    local gfxPointer = self.rom:word(headers.bank, rowAddress + 3)
    local collisionPointer = self.rom:word(headers.bank, rowAddress + 5)
    local counters = self.rom:bytes(headers.bank, rowAddress + 7, 3)
    local grass = self.rom:byte(headers.bank, rowAddress + 10)
    local animationId = self.rom:byte(headers.bank, rowAddress + 11)
    assert(animationId < #animations, constName .. ": unknown tile animation")

    local blocksRaw = self.rom:bytes(
      gfxBank, blockPointer, spec.blockCount * 16)
    local blocks = {}
    for offset = 1, #blocksRaw, 16 do
      local block = {}
      for pos = offset, offset + 15 do block[#block + 1] = blocksRaw[pos] end
      blocks[#blocks + 1] = block
    end
    -- Red/Blue keep collision lists in ROM0; Yellow moved them to bank 1
    -- (pokeyellow Overworld_Coll at 01:4ac2). Pointers in $4000-$7FFF are
    -- banked; treat ROM0-range pointers as bank 0.
    local collBank = collisionPointer < 0x4000 and 0 or 1
    local walkable = sorted(self:readTerminated(
      collBank, collisionPointer, 0xFF))
    local warpPointer = self.rom:word(
      warpPointers.bank, warpPointers.address + (index - 1) * 2)
    local warpTiles = unique(self:readTerminated(
      warpPointers.bank, warpPointer, 0xFF))
    sorted(warpTiles)

    local base = spec.imageBase
    if not written[base] then
      local byteLength = spec.imageWidth * spec.imageHeight / 4
      local storedLength = blockPointer - gfxPointer
      assert(storedLength >= 0 and storedLength <= byteLength
        and storedLength % 16 == 0,
        constName .. ": invalid stored tileset graphics length")
      local pixels = self.rom:bytes(gfxBank, gfxPointer, storedLength)
      while #pixels < byteLength do pixels[#pixels + 1] = 0 end
      self:write2bpp(pixels, spec.imageWidth, spec.imageHeight,
        "tilesets/" .. base .. ".png")
      written[base] = true
    end

    local counterTiles = {}
    for _, value in ipairs(counters) do
      if value ~= 0xFF then counterTiles[#counterTiles + 1] = value end
    end
    local grassTile
    if grass ~= 0xFF then grassTile = grass end
    out[constName] = {
      id = constName,
      source = ("ROM:Tilesets[%d]"):format(index - 1),
      -- The raw Tilesets row, verbatim.  A .sav export has to reproduce what
      -- LoadTilesetHeader (engine/overworld/tilesets.asm) would have left in
      -- wTilesetBank..wGrassTile, because a Continue never re-runs it -- see
      -- src/save_convert/MapContext.lua (#889).  Byte 12 is the tile
      -- animation id, which rides in sTileAnimations.
      header = self.rom:bytes(headers.bank, rowAddress, 12),
      image = "assets/generated/tilesets/" .. base .. ".png",
      imageWidth = spec.imageWidth,
      imageHeight = spec.imageHeight,
      tilesPerRow = spec.imageWidth / 8,
      blocks = blocks,
      walkable = walkable,
      counterTiles = counterTiles,
      grassTile = grassTile,
      doorTiles = sorted(copy(doors[index - 1] or {})),
      warpTiles = warpTiles,
      animation = animations[animationId + 1],
    }
    self:tick("World tiles", index, #order + 4)
  end
  for number = 1, 3 do
    local symbol = self:symbol("FlowerTile" .. number)
    self:write2bpp(self.rom:bytes(symbol.bank, symbol.address, 16),
      8, 8, "tilesets/flower" .. number .. ".png")
    self:tick("World tiles", #order + number, #order + 4)
  end
  local spinner = self:symbol("SpinnerArrowAnimTiles")
  self:write2bpp(self.rom:bytes(spinner.bank, spinner.address, 64),
    32, 8, "tilesets/spinners.png")
  self:write("tilesets", out)
  self:tick("World tiles", #order + 4, #order + 4)
  return out
end

function RomExtractor:extractMaps()
  self:beginStage("Maps")
  local manifest = self.manifest
  local mapOrder = manifest.constants.mapOrder
  local dimensions = manifest.constants.maps
  local metadata = manifest.maps
  local tilesets = manifest.constants.tilesetOrder
  local sprites = manifest.constants.spriteOrder
  local movementNames = { [0xFE] = "WALK", [0xFF] = "STAY" }
  local rangeNames = {
    [0x00] = "ANY_DIR", [0x01] = "UP_DOWN", [0x02] = "LEFT_RIGHT",
    [0x10] = "BOULDER_MOVEMENT_BYTE_2", [0xD0] = "DOWN",
    [0xD1] = "UP", [0xD2] = "LEFT", [0xD3] = "RIGHT", [0xFF] = "NONE",
  }
  local directions = {
    { "north", 0x08 }, { "south", 0x04 },
    { "west", 0x02 }, { "east", 0x01 },
  }
  local function signed(value) return value >= 0x80 and value - 0x100 or value end
  local function mapId(value)
    if value == 0xFF then return "LAST_MAP" end
    assert(value < #mapOrder, ("unknown map id $%02X"):format(value))
    return mapOrder[value + 1]
  end

  local keys = {}
  for key in pairs(metadata) do keys[#keys + 1] = key end
  table.sort(keys)
  local out = {}
  for mapIndex, constName in ipairs(keys) do
    local spec, dims = metadata[constName], dimensions[constName]
    local label = spec.label
    local header = self:symbol(label .. "_h")
    local address = header.address
    local tilesetId = self.rom:byte(header.bank, address)
    local height = self.rom:byte(header.bank, address + 1)
    local width = self.rom:byte(header.bank, address + 2)
    assert(width == dims.width and height == dims.height,
      constName .. ": ROM dimensions do not match metadata")
    assert(tilesetId < #tilesets, constName .. ": unknown tileset id")
    local blockPointer = self.rom:word(header.bank, address + 3)
    local connectionFlags = self.rom:byte(header.bank, address + 9)
    -- wCurMapHeader verbatim (tileset, height, width, data/text/script
    -- pointers, connection flags).  A save restores this window instead of
    -- rebuilding it, so an export has to carry the real bytes (#889).
    local headerBytes = self.rom:bytes(header.bank, address, 10)
    local connectionStart = address + 10
    address = address + 10

    local connections = {}
    for _, directionSpec in ipairs(directions) do
      local direction, flag = directionSpec[1], directionSpec[2]
      if bit.band(connectionFlags, flag) ~= 0 then
        local targetId = self.rom:byte(header.bank, address)
        local yOffset = signed(self.rom:byte(header.bank, address + 7))
        local xOffset = signed(self.rom:byte(header.bank, address + 8))
        local encoded = (direction == "north" or direction == "south")
          and xOffset or yOffset
        assert(encoded % 2 == 0, constName .. ": odd connection offset")
        connections[direction] = {
          map = mapId(targetId),
          offset = -encoded / 2,
        }
        address = address + 11
      end
    end
    assert(bit.band(connectionFlags, 0xF0) == 0,
      constName .. ": unknown connection flags")
    local connectionBytes = self.rom:bytes(
      header.bank, connectionStart, address - connectionStart)
    local objectPointer = self.rom:word(header.bank, address)
    local objectAddress = objectPointer
    local borderBlock = self.rom:byte(header.bank, objectAddress)
    objectAddress = objectAddress + 1

    local warpCount = self.rom:byte(header.bank, objectAddress)
    objectAddress = objectAddress + 1
    local warps = {}
    for _ = 1, warpCount do
      local row = self.rom:bytes(header.bank, objectAddress, 4)
      warps[#warps + 1] = {
        x = row[2], y = row[1],
        destMap = mapId(row[4]), destWarp = row[3] + 1,
      }
      objectAddress = objectAddress + 4
    end

    local signCount = self.rom:byte(header.bank, objectAddress)
    objectAddress = objectAddress + 1
    assert(signCount == #spec.signTexts, constName .. ": sign count mismatch")
    local signs = {}
    for _, signText in ipairs(spec.signTexts) do
      local row = self.rom:bytes(header.bank, objectAddress, 3)
      signs[#signs + 1] = { x = row[2], y = row[1], text = signText }
      objectAddress = objectAddress + 3
    end

    local objectCount = self.rom:byte(header.bank, objectAddress)
    objectAddress = objectAddress + 1
    assert(objectCount == #spec.objects, constName .. ": object count mismatch")
    local objects = {}
    for index, objectSpec in ipairs(spec.objects) do
      local row = self.rom:bytes(header.bank, objectAddress, 6)
      local spriteId, y, x = row[1], row[2], row[3]
      local movementId, rangeId, textId = row[4], row[5], row[6]
      assert(spriteId >= 1 and spriteId <= #sprites,
        constName .. ": unknown object sprite")
      assert(movementNames[movementId] and rangeNames[rangeId],
        constName .. ": unknown movement encoding")
      local object = {
        index = index, x = x - 4, y = y - 4,
        sprite = sprites[spriteId],
        movement = movementNames[movementId],
        range = rangeNames[rangeId],
        text = objectSpec.text,
      }
      objectAddress = objectAddress + 6
      if bit.band(textId, 0x80) ~= 0 then
        assert(objectSpec.item, constName .. ": unexpected item payload")
        object.item = objectSpec.item
        objectAddress = objectAddress + 1
      elseif bit.band(textId, 0x40) ~= 0 then
        local extra = self.rom:bytes(header.bank, objectAddress, 2)
        objectAddress = objectAddress + 2
        if objectSpec.trainerClass then
          object.trainerClass = objectSpec.trainerClass
          object.trainerParty = type(objectSpec.trainerParty) == "string"
            and objectSpec.trainerParty or extra[2]
        elseif objectSpec.pokemon then
          object.pokemon = objectSpec.pokemon
          object.level = extra[2]
        else
          error(constName .. ": unexpected trainer or Pokemon payload")
        end
      else
        assert(not objectSpec.item and not objectSpec.trainerClass
          and not objectSpec.pokemon, constName .. ": missing extra payload")
      end
      if objectSpec.name then object.name = objectSpec.name end
      if objectSpec.hidden ~= nil then object.hidden = objectSpec.hidden end
      objects[#objects + 1] = object
    end

    local expectedBlocks = width * height
    assert(spec.blockLength <= expectedBlocks,
      constName .. ": block payload exceeds map dimensions")
    local blocks = self.rom:bytes(
      header.bank, blockPointer, spec.blockLength)
    while #blocks < expectedBlocks do blocks[#blocks + 1] = borderBlock end

    out[constName] = {
      id = constName, label = label, index = dims.index,
      source = ("ROM:%02X:%04X"):format(header.bank, header.address),
      tileset = tilesets[tilesetId + 1],
      width = width, height = height, blocks = blocks,
      borderBlock = borderBlock, connections = connections,
      warps = warps, signs = signs, objects = objects,
      -- Raw ROM bytes a .sav export replays through LoadMapHeader's WRAM
      -- writes (src/save_convert/MapContext.lua, #889).  Kept as the original
      -- bytes rather than re-encoded from the decoded tables above: the
      -- pointers in them (wCurMapDataPtr, the connection strip src/dest
      -- addresses, sign text ids) have no equivalent in the port's own model.
      sram = {
        header = headerBytes,
        connections = connectionBytes,
        objects = self.rom:bytes(
          header.bank, objectPointer, objectAddress - objectPointer),
      },
    }
    self:tick("Maps", mapIndex, #keys)
  end
  -- keep the extract ROM-faithful; Data:seedDefaults applies the #189
  -- S.S. Anne 1F cabin reorder at load time
  self:write("maps", out)
  return out
end

function RomExtractor:extractFont()
  self:beginStage("Fonts")
  local mainSymbol = self:symbol("FontGraphics")
  local raw = self.rom:bytes(mainSymbol.bank, mainSymbol.address, 128 * 8)
  local image = ImageWriter.blank(128, 64, 0, 0, 0, 0)
  for tile = 0, 127 do
    local tileX, tileY = tile % 16 * 8, math.floor(tile / 16) * 8
    for y = 0, 7 do
      local row = raw[tile * 8 + y + 1]
      for x = 0, 7 do
        if bit.band(row, 2 ^ (7 - x)) ~= 0 then
          image:setPixel(tileX + x, tileY + y, 0, 0, 0, 1)
        end
      end
    end
  end
  self:save(image, "fonts/font.png")
  self:tick("Fonts", 1, 2)

  local extraSymbol = self:symbol("TextBoxGraphics")
  local shaded = ImageWriter.decode2bpp(
    self.rom:bytes(extraSymbol.bank, extraSymbol.address, 32 * 16),
    128, 16)
  local extra = ImageWriter.blank(128, 16, 0, 0, 0, 0)
  for y = 0, 15 do
    for x = 0, 127 do
      local r = shaded:getPixel(x, y)
      if r < 0.5 then extra:setPixel(x, y, 0, 0, 0, 1) end
    end
  end
  local pokedex = self:symbol("PokedexTileGraphics")
  local dex = ImageWriter.decode2bpp(
    self.rom:bytes(pokedex.bank, pokedex.address, 32), 16, 8)
  for y = 0, 7 do
    for x = 0, 15 do
      local r = dex:getPixel(x, y)
      extra:setPixel(x, y, 0, 0, 0, r < 0.5 and 1 or 0)
    end
  end
  self:save(extra, "fonts/font_extra.png")
  local data = {
    source = "ROM:FontGraphics, TextBoxGraphics, PokedexTileGraphics",
    image = "assets/generated/fonts/font.png",
    imageExtra = "assets/generated/fonts/font_extra.png",
    mainBase = 0x80, extraBase = 0x60, glyphsPerRow = 16,
    charmap = self.manifest.fontCharmap,
  }
  -- engine/menus/naming_screen.asm:326
  local edSymbol = self.symbols["ED_Tile"]
  if edSymbol then
    local edRaw = self.rom:bytes(edSymbol[1], edSymbol[2], 8)
    local ed = ImageWriter.blank(8, 8, 0, 0, 0, 0)
    for y = 0, 7 do
      local row = edRaw[y + 1]
      for x = 0, 7 do
        if bit.band(row, 2 ^ (7 - x)) ~= 0 then
          ed:setPixel(x, y, 0, 0, 0, 1)
        end
      end
    end
    self:save(ed, "fonts/ed.png")
    data.imageEd = "assets/generated/fonts/ed.png"
  end
  self:write("font", data)
  self:tick("Fonts", 2, 2)
  return data
end

-- engine/overworld/map_sprites.asm:181
function RomExtractor.spriteSheetLength(constName, width, height, firstHalf)
  local byteLength = width * height / 4
  local frames = height / 16
  local expected = firstHalf * (frames >= 6 and 2 or 1)
  if byteLength < expected then
    byteLength = expected
    assert(byteLength * 4 % width == 0,
      constName .. ": ROM sprite length not tile-aligned")
    height = byteLength * 4 / width
    frames = height / 16
    expected = firstHalf * (frames >= 6 and 2 or 1)
    assert(byteLength == expected, constName .. ": sprite length mismatch")
  end
  return byteLength, height, frames
end

function RomExtractor:extractSprites()
  self:beginStage("Overworld sprites")
  local order = self.manifest.constants.spriteOrder
  local metadata = self.manifest.sprites.order
  local pointerTable = self:symbol("SpriteSheetPointerTable")
  assert(#metadata == #order, "sprite metadata count does not match constants")
  local out, written = {}, {}
  for index, constName in ipairs(order) do
    local spec = metadata[index]
    assert(spec.id == constName, "sprite metadata is out of order")
    local address = pointerTable.address + (index - 1) * 4
    local pointer = self.rom:word(pointerTable.bank, address)
    local firstHalf = self.rom:byte(pointerTable.bank, address + 2)
    local bank = self.rom:byte(pointerTable.bank, address + 3)
    local width = spec.imageWidth
    local byteLength, height, frames = RomExtractor.spriteSheetLength(
      constName, width, spec.imageHeight, firstHalf)
    local base = spec.imageBase
    if not written[base] then
      self:write2bpp(self.rom:bytes(bank, pointer, byteLength),
        width, height,
        "sprites/" .. base .. ".png", true)
      written[base] = true
    end
    out[constName] = {
      id = constName,
      source = ("ROM:SpriteSheetPointerTable[%d]"):format(index - 1),
      image = "assets/generated/sprites/" .. base .. ".png",
      frames = frames, walker = frames >= 6,
    }
    self:tick("Overworld sprites", index, #order + 1)
  end
  local bike = self.manifest.sprites.bike
  local bikeSymbol = self:symbol(bike.label)
  self:write2bpp(
    self.rom:bytes(bikeSymbol.bank, bikeSymbol.address,
      bike.imageWidth * bike.imageHeight / 4),
    bike.imageWidth, bike.imageHeight,
    "sprites/" .. bike.imageBase .. ".png", true)
  local bikeFrames = bike.imageHeight / 16
  out.SPRITE_RED_BIKE = {
    id = "SPRITE_RED_BIKE", source = "ROM:RedBikeSprite",
    image = "assets/generated/sprites/red_bike.png",
    frames = bikeFrames, walker = bikeFrames >= 6,
  }
  -- Yellow-only: the surfing-Pikachu overworld sheet, loaded outside
  -- SpriteSheetPointerTable (LoadSurfingPlayerSpriteGraphics2) -- same
  -- extra-extract shape as RedBikeSprite. (RFC 0001)
  local surfPika = self.manifest.sprites.surfPikachu
  if surfPika and self.symbols[surfPika.label] then
    local spSymbol = self:symbol(surfPika.label)
    self:write2bpp(
      self.rom:bytes(spSymbol.bank, spSymbol.address,
        surfPika.imageWidth * surfPika.imageHeight / 4),
      surfPika.imageWidth, surfPika.imageHeight,
      "sprites/" .. surfPika.imageBase .. ".png", true)
    local spFrames = surfPika.imageHeight / 16
    out.SPRITE_SURFING_PIKACHU = {
      id = "SPRITE_SURFING_PIKACHU",
      source = ("ROM:%s"):format(surfPika.label),
      image = "assets/generated/sprites/" .. surfPika.imageBase .. ".png",
      frames = spFrames, walker = spFrames >= 6,
    }
  end
  self:write("sprites", out)
  self:tick("Overworld sprites", #order + 1, #order + 1)
  return out
end

function RomExtractor:animationFlags(count)
  local pointerTable = self:symbol("AttackAnimationPointers")
  local flags = {}
  for index = 0, count - 1 do
    local address = self.rom:word(
      pointerTable.bank, pointerTable.address + index * 2)
    local shake, flash, ended = false, false, false
    for _ = 1, 256 do
      local first = self.rom:byte(pointerTable.bank, address)
      if first == 0xFF then ended = true; break end
      if first >= 0xD8 then
        shake = shake or first == 0xFB
        flash = flash or first == 0xF8 or first == 0xFE
        address = address + 2
      else
        address = address + 3
      end
    end
    assert(ended, "unterminated move animation " .. (index + 1))
    flags[#flags + 1] = { shake, flash }
  end
  return flags
end

function RomExtractor:extractMoves()
  self:beginStage("Moves")
  local order = self.manifest.constants.moveOrder
  local types = {}
  for name, value in pairs(self.manifest.constants.types) do types[value] = name end
  local effects = self.manifest.moveEffects
  local charmap = self.manifest.charmap
  local moves = self:symbol("Moves")
  local names = self:symbol("MoveNames")
  local sounds = self:symbol("MoveSoundTable")
  local flags = self:animationFlags(#order)
  local decodedNames, address = {}, names.address
  for _ = 1, #order do
    local value, consumed = self.rom:readString(
      names.bank, address, charmap, 0x50, 32)
    decodedNames[#decodedNames + 1] = value
    address = address + consumed
  end
  local out = {}
  for index, moveId in ipairs(order) do
    local row = self.rom:bytes(moves.bank, moves.address + (index - 1) * 6, 6)
    assert(row[1] == index, "Moves row stores wrong animation id")
    local effect = effects[row[2] + 1] or hex("EFFECT", row[2])
    local typeName = types[row[4]] or hex("TYPE", row[4])
    local soundId, pitch, tempo = unpack(self.rom:bytes(
      sounds.bank, sounds.address + (index - 1) * 3, 3))
    local animation = {
      sound = self.manifest.sfxKeys[tostring(soundId)] or hex("SFX", soundId),
      pitch = pitch, tempo = tempo,
    }
    if flags[index][1] then animation.shake = true end
    if flags[index][2] then animation.flash = true end
    out[moveId] = {
      id = moveId, index = index, name = decodedNames[index],
      source = ("ROM:Moves[%d]"):format(index),
      effect = effect, power = row[3], type = typeName,
      accuracy = round(row[5] * 100 / 255), pp = row[6],
      anim = animation,
    }
    self:tick("Moves", index, #order)
  end
  self:write("moves", out)
  return out
end

function RomExtractor:extractBattleAnimations()
  self:beginStage("Battle animations")
  local metadata = self.manifest.battleAnimations
  local moveOrder = self.manifest.constants.moveOrder
  assert(#moveOrder == metadata.moveCount,
    "battle animation move count does not match constants")
  local total = metadata.baseCoordCount + metadata.frameBlockCount
    + metadata.subanimCount + metadata.moveCount
    + #metadata.miscAnimations + 3
  local completed = 0
  local function tick()
    completed = completed + 1
    self:tick("Battle animations", completed, total)
  end

  local coordsSymbol = self:symbol("FrameBlockBaseCoords")
  local baseCoords = {}
  for index = 0, metadata.baseCoordCount - 1 do
    local row = self.rom:bytes(
      coordsSymbol.bank, coordsSymbol.address + index * 2, 2)
    baseCoords[index] = { y = row[1], x = row[2] }
    tick()
  end

  local blocksSymbol = self:symbol("FrameBlockPointers")
  local frameBlocks = {}
  for index = 0, metadata.frameBlockCount - 1 do
    local address = self.rom:word(
      blocksSymbol.bank, blocksSymbol.address + index * 2)
    local count = self.rom:byte(blocksSymbol.bank, address)
    address = address + 1
    local entries = {}
    for _ = 1, count do
      local row = self.rom:bytes(blocksSymbol.bank, address, 4)
      local attrs = row[4]
      local entry = {
        y = row[1], x = row[2], tile = row[3],
        xflip = bit.band(attrs, 0x20) ~= 0,
        yflip = bit.band(attrs, 0x40) ~= 0,
      }
      if bit.band(attrs, 0x80) ~= 0 then entry.prio = true end
      if bit.band(attrs, 0x10) ~= 0 then entry.pal1 = true end
      entries[#entries + 1] = entry
      address = address + 4
    end
    frameBlocks[index] = entries
    tick()
  end

  local subanimSymbol = self:symbol("SubanimationPointers")
  local subanims = {}
  for index = 0, metadata.subanimCount - 1 do
    local address = self.rom:word(
      subanimSymbol.bank, subanimSymbol.address + index * 2)
    local packed = self.rom:byte(subanimSymbol.bank, address)
    local typeId = math.floor(packed / 0x20)
    local count = packed % 0x20
    local typeName = metadata.subanimTypes[typeId + 1]
    assert(typeName, "subanimation " .. index .. " has unknown type")
    address = address + 1
    local entries = {}
    for _ = 1, count do
      local row = self.rom:bytes(subanimSymbol.bank, address, 3)
      assert(row[1] < metadata.frameBlockCount,
        "subanimation " .. index .. " has invalid frame block")
      assert(row[2] < metadata.baseCoordCount,
        "subanimation " .. index .. " has invalid base coord")
      entries[#entries + 1] = {
        block = row[1], coord = row[2], mode = row[3],
      }
      address = address + 3
    end
    subanims[index] = { type = typeName, blocks = entries }
    tick()
  end

  local tilesTable = self:symbol("MoveAnimationTilesPointers")
  assert(#metadata.tilesheets == 3,
    "expected three battle animation tilesheets")
  local tileRows = {}
  for index = 0, 2 do
    local row = self.rom:bytes(
      tilesTable.bank, tilesTable.address + index * 4, 4)
    assert(row[4] == 0xFF,
      "battle animation tilesheet " .. index .. " has invalid padding")
    local pointer = row[2] + row[3] * 0x100
    local expected = self:symbol("MoveAnimationTiles" .. index)
    assert(expected.bank == tilesTable.bank and expected.address == pointer,
      "battle animation tilesheet " .. index .. " pointer differs")
    tileRows[index] = {
      count = row[1], pointer = pointer,
      spec = metadata.tilesheets[index + 1],
    }
  end

  local imagePayloads = {}
  for index = 0, 2 do
    local row = tileRows[index]
    local path = row.spec.path
    local payload = imagePayloads[path]
    if payload then
      assert(payload.pointer == row.pointer,
        "shared battle animation atlas has two pointers")
    else
      payload = { pointer = row.pointer, tiles = 0, spec = row.spec }
      imagePayloads[path] = payload
    end
    payload.tiles = math.max(payload.tiles, row.count)
  end
  local prefix = "assets/generated/"
  for path, payload in pairs(imagePayloads) do
    local spec = payload.spec
    local byteLength = spec.width * spec.height / 4
    local storedLength = payload.tiles * 16
    assert(storedLength <= byteLength,
      path .. ": battle animation atlas is too large")
    local raw = self.rom:bytes(
      tilesTable.bank, payload.pointer, storedLength)
    while #raw < byteLength do raw[#raw + 1] = 0 end
    assert(startsWith(path, prefix), "invalid generated asset path")
    self:write2bpp(raw, spec.width, spec.height,
      path:sub(#prefix + 1), true)
  end

  local tilesheets = {}
  for index = 0, 2 do
    local row, spec = tileRows[index], tileRows[index].spec
    tilesheets[index] = {
      path = spec.path, width = spec.width, height = spec.height,
      tiles = row.count, source = spec.source,
    }
    tick()
  end

  local moveNames = copy(moveOrder)
  append(moveNames, metadata.miscAnimations)
  local pointerTable = self:symbol("AttackAnimationPointers")
  local moveAnims = {}
  for index, name in ipairs(moveNames) do
    local address = self.rom:word(
      pointerTable.bank, pointerTable.address + (index - 1) * 2)
    local sequence, ended = {}, false
    for _ = 1, 256 do
      local first = self.rom:byte(pointerTable.bank, address)
      if first == 0xFF then ended = true; break end
      local sound = self.rom:byte(pointerTable.bank, address + 1)
      local row
      if first >= metadata.firstSpecialEffect then
        local effect = metadata.specialEffects[tostring(first)]
        assert(effect, name .. ": unknown special effect")
        row = { effect = effect }
        address = address + 2
      else
        local subanim = self.rom:byte(pointerTable.bank, address + 2)
        local delay = first % 0x40
        local tileset = math.floor(first / 0x40)
        assert(delay > 0, name .. ": zero animation delay")
        assert(subanim < metadata.subanimCount,
          name .. ": unknown subanimation")
        assert(tilesheets[tileset],
          name .. ": unknown animation tileset")
        row = { subanim = subanim, tileset = tileset, delay = delay }
        address = address + 3
      end
      if sound ~= 0xFF then
        assert(sound < #moveOrder, name .. ": unknown animation sound")
        row.sound = moveOrder[sound + 1]
      end
      sequence[#sequence + 1] = row
    end
    assert(ended, name .. ": unterminated battle animation")
    moveAnims[name] = {
      source = ("ROM:AttackAnimationPointers[%d]"):format(index - 1),
      seq = sequence,
    }
    tick()
  end

  for name, anim in pairs(moveAnims) do
    for _, row in ipairs(anim.seq) do
      if row.subanim then
        local sheet = tilesheets[row.tileset]
        for _, blockRef in ipairs(subanims[row.subanim].blocks) do
          for _, tile in ipairs(frameBlocks[blockRef.block]) do
            assert(tile.tile < sheet.tiles,
              name .. ": animation tile is out of range")
          end
        end
      end
    end
  end

  local out = {
    tilesheets = tilesheets,
    baseCoords = baseCoords,
    frameBlocks = frameBlocks,
    subanims = subanims,
    moveAnims = moveAnims,
  }
  self:write("battle_anims", out)
  return out
end

function RomExtractor:nybbles(raw, count)
  local out = {}
  for _, value in ipairs(raw) do
    out[#out + 1], out[#out + 2] = math.floor(value / 16), value % 16
  end
  while #out > count do table.remove(out) end
  return out
end

function RomExtractor:extractItems()
  self:beginStage("Items")
  local order = self.manifest.items
  local charmap = self.manifest.charmap
  local names = self:symbol("ItemNames")
  local prices = self:symbol("ItemPrices")
  local keyFlags = self:symbol("KeyItemFlags")
  local tmPrices = self:symbol("TechnicalMachinePrices")
  local decodedNames, address = {}, names.address
  for _ = 1, #order do
    local value, consumed = self.rom:readString(
      names.bank, address, charmap, 0x50, 32)
    decodedNames[#decodedNames + 1] = value
    address = address + consumed
  end
  local numItems = self.manifest.numItems
  local flags = self.rom:bytes(
    keyFlags.bank, keyFlags.address, math.floor((numItems + 7) / 8))
  local out = {}
  for index, itemId in ipairs(order) do
    local entry = {
      id = itemId, index = index, name = decodedNames[index],
      price = Rom.bcd(self.rom:bytes(
        prices.bank, prices.address + (index - 1) * 3, 3)),
      source = ("ROM:ItemNames[%d]"):format(index),
    }
    if index <= numItems
        and bit.band(flags[math.floor((index - 1) / 8) + 1],
          2 ^ ((index - 1) % 8)) ~= 0 then
      entry.keyItem = true
    end
    out[itemId] = entry
  end
  for number, move in ipairs(self.manifest.hms) do
    local itemId = "HM_" .. move
    out[itemId] = {
      id = itemId, name = ("HM%02d"):format(number), price = 0,
      machine = { kind = "HM", number = number, move = move },
      source = "ROM metadata manifest (HM mapping)",
    }
  end
  local packed = self.rom:bytes(tmPrices.bank, tmPrices.address,
    math.floor((#self.manifest.tms + 1) / 2))
  local pricesByTm = self:nybbles(packed, #self.manifest.tms)
  for number, move in ipairs(self.manifest.tms) do
    local itemId = "TM_" .. move
    out[itemId] = {
      id = itemId, name = ("TM%02d"):format(number),
      price = pricesByTm[number] * 1000,
      machine = { kind = "TM", number = number, move = move },
      source = ("ROM:TechnicalMachinePrices[%d]"):format(number),
    }
  end
  self:write("items", out)
  self:tick("Items", 1, 1)
  return out
end

function RomExtractor:extractTypeChart()
  self:beginStage("Types")
  local types = {}
  for name, value in pairs(self.manifest.constants.types) do types[value] = name end
  local effects = self:symbol("TypeEffects")
  local address, matchups = effects.address, {}
  while self.rom:byte(effects.bank, address) ~= 0xFF do
    local row = self.rom:bytes(effects.bank, address, 3)
    matchups[#matchups + 1] = {
      attacker = types[row[1]] or hex("TYPE", row[1]),
      defender = types[row[2]] or hex("TYPE", row[2]),
      multiplier = row[3],
    }
    address = address + 3
  end
  local names, seen = {}, {}
  for _, label in ipairs(self.manifest.typeNameLabels) do
    local symbol = self:symbol(label)
    local location = symbol.bank .. ":" .. symbol.address
    if not seen[location] then
      seen[location] = true
      names[#names + 1] = self.rom:readString(
        symbol.bank, symbol.address, self.manifest.charmap, 0x50, 16)
    end
  end
  local data = {
    source = "ROM:TypeEffects + TypeNames",
    matchups = matchups, names = names,
  }
  self:write("type_chart", data)
  self:tick("Types", 1, 1)
  return data
end

function RomExtractor:extractPalettes()
  self:beginStage("Color palettes")
  local order = self.manifest.paletteOrder
  local paletteTable = self:symbol("SuperPalettes")
  local function scale5(value) return round(value * 255 / 31) end
  local function readTable(symbol, names)
    local out = {}
    for index, name in ipairs(names) do
      local colors = {}
      for color = 0, 3 do
        local value = self.rom:word(symbol.bank,
          symbol.address + (index - 1) * 8 + color * 2)
        colors[#colors + 1] = {
          scale5(bit.band(value, 0x1F)),
          scale5(bit.band(bit.rshift(value, 5), 0x1F)),
          scale5(bit.band(bit.rshift(value, 10), 0x1F)),
        }
      end
      out[name] = colors
    end
    return out
  end
  local palettes = readTable(paletteTable, order)
  local monsterTable = self:symbol("MonsterPalettes")
  local monsterPalettes = {}
  for index, species in ipairs(self.manifest.dexOrder) do
    local paletteId = self.rom:byte(
      monsterTable.bank, monsterTable.address + index)
    monsterPalettes[species] = order[paletteId + 1]
  end
  local data = {
    source = "ROM:SuperPalettes + MonsterPalettes",
    palettes = palettes, order = order, pokemon = monsterPalettes,
  }
  -- Yellow (and GBC carts) also carry CGBBasePalettes beside SuperPalettes.
  if self.symbols["CGBBasePalettes"] then
    data.cgbBase = readTable(self:symbol("CGBBasePalettes"), order)
    data.source = data.source .. " + CGBBasePalettes"
  end
  self:write("palettes", data)
  self:tick("Color palettes", 1, 1)
  return data
end

function RomExtractor:extractIcons()
  self:beginStage("Party icons")
  local iconTable = self:symbol("MonPartyData")
  local count = #self.manifest.dexOrder
  local packed = self.rom:bytes(iconTable.bank, iconTable.address,
    math.floor((count + 1) / 2))
  local values = self:nybbles(packed, count)
  local byDex = {}
  for _, value in ipairs(values) do
    byDex[#byDex + 1] = self.manifest.iconOrder[value + 1]
      or ("ICON_%X"):format(value)
  end
  local icons = {
    MON = "assets/generated/sprites/monster.png",
    BALL = "assets/generated/sprites/poke_ball.png",
    HELIX = "assets/generated/sprites/fossil.png",
    FAIRY = "assets/generated/sprites/fairy.png",
    BIRD = "assets/generated/sprites/bird.png",
    WATER = "assets/generated/sprites/seel.png",
    BUG = "assets/generated/icons/bug.png",
    GRASS = "assets/generated/icons/plant.png",
    SNAKE = "assets/generated/icons/snake.png",
    QUADRUPED = "assets/generated/icons/quadruped.png",
    -- Yellow's ICON_PIKACHU draws from the overworld PikachuSprite sheet
    -- (data/icon_pointers.asm mon_icon_header PikachuSprite, 0/12);
    -- only referenced when the manifest's iconOrder includes it
    PIKACHU = "assets/generated/sprites/pikachu.png",
  }
  local frames = {
    { "bug", "BugIconFrame1", "BugIconFrame2" },
    { "plant", "PlantIconFrame1", "PlantIconFrame2" },
    { "snake", "SnakeIconFrame1", "SnakeIconFrame2" },
    { "quadruped", "QuadrupedIconFrame1", "QuadrupedIconFrame2" },
  }
  for index, spec in ipairs(frames) do
    local raw = {}
    for labelIndex = 2, 3 do
      local symbol = self:symbol(spec[labelIndex])
      append(raw, self.rom:bytes(symbol.bank, symbol.address, 32))
    end
    local half = ImageWriter.decode2bpp(raw, 8, 32, true)
    local image = ImageWriter.blank(16, 32, 1, 1, 1, 0)
    for frame = 0, 1 do
      ImageWriter.blit(image, half, 0, frame * 16, 0, frame * 16, 8, 16)
      ImageWriter.blit(image, half, 8, frame * 16, 0, frame * 16, 8, 16, true)
    end
    self:save(image, "icons/" .. spec[1] .. ".png")
    self:tick("Party icons", index, #frames)
  end
  local data = { source = "ROM:MonPartyData", byDex = byDex, icons = icons }
  self:write("icons", data)
  return data
end

function RomExtractor:species(value)
  local order = self.manifest.constants.speciesOrder
  if value < 1 or value > #order then return hex("SPECIES", value) end
  return order[value]
end

function RomExtractor:item(value)
  local order = self.manifest.items
  if value < 1 or value > #order then return hex("ITEM", value) end
  return order[value]
end

function RomExtractor:move(value)
  if value == 0 then return nil end
  local order = self.manifest.constants.moveOrder
  if value < 1 or value > #order then return hex("MOVE", value) end
  return order[value]
end

function RomExtractor:typesById()
  local result = {}
  for name, value in pairs(self.manifest.constants.types) do
    result[value] = name
  end
  return result
end

function RomExtractor:decodeEvolutionsAndMoves(index)
  local pointerTable = self:symbol("EvosMovesPointerTable")
  local address = self.rom:word(
    pointerTable.bank, pointerTable.address + (index - 1) * 2)
  local evolutions = {}
  while true do
    local method = self.rom:byte(pointerTable.bank, address)
    address = address + 1
    if method == 0 then break end
    if method == 1 then
      local row = self.rom:bytes(pointerTable.bank, address, 2)
      address = address + 2
      evolutions[#evolutions + 1] = {
        method = "LEVEL", level = row[1], species = self:species(row[2]),
      }
    elseif method == 2 then
      local row = self.rom:bytes(pointerTable.bank, address, 3)
      address = address + 3
      evolutions[#evolutions + 1] = {
        method = "ITEM", item = self:item(row[1]), level = row[2],
        species = self:species(row[3]),
      }
    elseif method == 3 then
      local row = self.rom:bytes(pointerTable.bank, address, 2)
      address = address + 2
      evolutions[#evolutions + 1] = {
        method = "TRADE", level = row[1], species = self:species(row[2]),
      }
    else
      error(("unknown evolution method %d for species index %d")
        :format(method, index))
    end
  end

  local learnset = {}
  while true do
    local level = self.rom:byte(pointerTable.bank, address)
    address = address + 1
    if level == 0 then break end
    local move = self.rom:byte(pointerTable.bank, address)
    address = address + 1
    learnset[#learnset + 1] = { level = level, move = self:move(move) }
  end
  return evolutions, learnset
end

function RomExtractor:dexEntry(index, species)
  local pointerTable = self:symbol("PokedexEntryPointers")
  local address = self.rom:word(
    pointerTable.bank, pointerTable.address + (index - 1) * 2)
  local kind, consumed = self.rom:readString(
    pointerTable.bank, address, self.manifest.charmap, 0x50, 32)
  address = address + consumed
  local heightFt = self.rom:byte(pointerTable.bank, address)
  local heightIn = self.rom:byte(pointerTable.bank, address + 1)
  local weight = self.rom:word(pointerTable.bank, address + 2)
  address = address + 4
  assert(self.rom:byte(pointerTable.bank, address) == 0x17,
    "dex entry " .. index .. " has no TX_FAR command")
  local textAddress = self.rom:word(pointerTable.bank, address + 1)
  local textBank = self.rom:byte(pointerTable.bank, address + 3)
  local textLabel = self.manifest.dexEntryLabels[species]
    or ("_DexEntry_%02X_%04X"):format(textBank, textAddress)
  return {
    kind = kind, heightFt = heightFt, heightIn = heightIn,
    weight = weight, text = textLabel,
  }
end

function RomExtractor:extractPokemon()
  self:beginStage("Pokemon")
  local speciesOrder = self.manifest.constants.speciesOrder
  local dexBySpecies = {}
  for index, species in ipairs(self.manifest.dexOrder) do
    dexBySpecies[species] = index
  end
  local typeById = self:typesById()
  local names = self:symbol("MonsterNames")
  local baseStats = self:symbol("BaseStats")
  -- Red/Blue keep Mew outside BaseStats (pret pokered MewBaseStats).
  -- Yellow stores Mew as dex 151 inside BaseStats (pret/pokeyellow).
  local mewStats = self.symbols["MewBaseStats"] and self:symbol("MewBaseStats")
  local decodedNames = {}
  for index = 1, #speciesOrder do
    decodedNames[index] = self.rom:decodeText(
      self.rom:bytes(names.bank, names.address + (index - 1) * 10, 10),
      self.manifest.charmap)
  end

  local out, writtenFront, writtenBack = {}, {}, {}
  local completed = 0
  for index, species in ipairs(speciesOrder) do
    local skip = startsWith(species, "MISSINGNO")
      or startsWith(species, "UNUSED")
      or startsWith(species, "FOSSIL_")
      or startsWith(species, "MON_GHOST")
    if not skip then
      local dex = assert(dexBySpecies[species],
        "missing dex number for " .. species)
      local row
      if species == "MEW" and mewStats then
        row = self.rom:bytes(mewStats.bank, mewStats.address, 28)
      else
        row = self.rom:bytes(
          baseStats.bank, baseStats.address + (dex - 1) * 28, 28)
      end
      assert(row[1] == dex, species .. ": base stats dex mismatch")

      local level1Moves = {}
      for position = 16, 19 do
        if row[position] ~= 0 then
          level1Moves[#level1Moves + 1] = self:move(row[position])
        end
      end
      local tmhm = {}
      for moveIndex, move in ipairs(self.manifest.tmhmMoves) do
        local byte = row[21 + math.floor((moveIndex - 1) / 8)]
        if bit.band(byte, 2 ^ ((moveIndex - 1) % 8)) ~= 0 then
          tmhm[#tmhm + 1] = move
        end
      end
      local evolutions, learnset = self:decodeEvolutionsAndMoves(index)
      local asset = self.manifest.pokemonAssets[species]
      local front, back = asset.front, asset.back
      if front and not writtenFront[front] then
        local size = self:writeCompressedPic(
          asset.frontLabel, "battle/front/" .. front .. ".png")
        assert(size == math.floor(row[11] / 16),
          species .. ": front picture size mismatch")
        writtenFront[front] = true
      end
      if back and not writtenBack[back] then
        self:writeCompressedPic(
          asset.backLabel, "battle/back/" .. back .. ".png")
        writtenBack[back] = true
      end
      local speciesTypes = unique({
        typeById[row[7]] or hex("TYPE", row[7]),
        typeById[row[8]] or hex("TYPE", row[8]),
      })
      out[species] = {
        id = species, index = index, dex = dex,
        name = decodedNames[index],
        source = ("ROM:BaseStats[%d]"):format(dex),
        types = speciesTypes,
        baseStats = {
          hp = row[2], attack = row[3], defense = row[4],
          speed = row[5], special = row[6],
        },
        catchRate = row[9], baseExp = row[10],
        level1Moves = level1Moves,
        growthRate = self.manifest.growthRates[row[20] + 1],
        tmhm = tmhm, learnset = learnset, evolutions = evolutions,
        spriteFront = front
          and "assets/generated/battle/front/" .. front .. ".png" or nil,
        spriteBack = back
          and "assets/generated/battle/back/" .. back .. ".png" or nil,
        frontSize = math.floor(row[11] / 16),
        dexEntry = self:dexEntry(index, species),
      }
      completed = completed + 1
      self:tick("Pokemon", completed, #self.manifest.dexOrder + 10)
    end
  end

  for _, spec in ipairs({
    { "FossilAerodactylPic", "fossilaerodactyl" },
    { "FossilKabutopsPic", "fossilkabutops" },
    { "GhostPic", "ghost" },
  }) do
    self:writeCompressedPic(spec[1], "battle/front/" .. spec[2] .. ".png")
    completed = completed + 1
    self:tick("Pokemon", completed, #self.manifest.dexOrder + 10)
  end
  for _, spec in ipairs({
    { "RedPicBack", "redb" }, { "OldManPicBack", "oldmanb" },
  }) do
    self:writeCompressedPic(spec[1], "battle/" .. spec[2] .. ".png")
    completed = completed + 1
    self:tick("Pokemon", completed, #self.manifest.dexOrder + 10)
  end
  -- Yellow-only third back pic: LoadPlayerBackPic (engine/battle/core.asm)
  -- picks OldManPicBack for BATTLE_TYPE_OLD_MAN but ProfOakPicBack for
  -- BATTLE_TYPE_PIKACHU, the Pallet Town catch scene (#557).  Outside the
  -- ticked loop so the progress denominator stays as it was.
  if self.symbols["ProfOakPicBack"] then
    self:writeCompressedPic("ProfOakPicBack", "battle/profoakb.png")
  end
  local balls = self:symbol("PokeballTileGraphics")
  self:write2bpp(self.rom:bytes(balls.bank, balls.address, 64),
    32, 8, "battle/balls.png", true)
  completed = completed + 1
  self:tick("Pokemon", completed, #self.manifest.dexOrder + 10)

  for _, spec in ipairs({
    { "TrainerInfoTextBoxTileGraphics", "trainer_info.png", 24, 24, false },
    { "GymLeaderFaceAndBadgeTileGraphics", "badges.png", 16, 256, true },
    { "BadgeNumbersTileGraphics", "badge_numbers.png", 16, 32, true },
    { "CircleTile", "circle_tile.png", 8, 8, true },
  }) do
    local symbol = self:symbol(spec[1])
    self:write2bpp(
      self.rom:bytes(symbol.bank, symbol.address, spec[3] * spec[4] / 4),
      spec[3], spec[4], "trainer_card/" .. spec[2], spec[5])
    completed = completed + 1
    self:tick("Pokemon", completed, #self.manifest.dexOrder + 10)
  end
  self:writeCompressedPic("RedPicFront", "trainer_card/red.png")
  self:write("pokemon", out)
  self:tick("Pokemon", #self.manifest.dexOrder + 10,
    #self.manifest.dexOrder + 10)
  return out
end

function RomExtractor:trainerParties(bank, startAddress, endAddress)
  local parties, address = {}, startAddress
  while address < endAddress do
    local first = self.rom:byte(bank, address)
    address = address + 1
    local party = {}
    if first == 0xFF then
      while true do
        local level = self.rom:byte(bank, address)
        address = address + 1
        if level == 0 then break end
        local species = self.rom:byte(bank, address)
        address = address + 1
        party[#party + 1] = {
          level = level, species = self:species(species),
        }
      end
    else
      while true do
        local species = self.rom:byte(bank, address)
        address = address + 1
        if species == 0 then break end
        party[#party + 1] = {
          level = first, species = self:species(species),
        }
      end
    end
    parties[#parties + 1] = party
  end
  assert(address == endAddress,
    ("trainer party data overran %02X:%04X"):format(bank, endAddress))
  return parties
end

function RomExtractor:extractTrainers()
  self:beginStage("Trainers")
  local order = self.manifest.trainers
  local names = self:symbol("TrainerNames")
  local pointers = self:symbol("TrainerDataPointers")
  local money = self:symbol("TrainerPicAndMoneyPointers")
  local choices = self:symbol("TrainerClassMoveChoiceModifications")
  local decodedNames, address = {}, names.address
  for _ = 1, #order do
    local name, consumed = self.rom:readString(
      names.bank, address, self.manifest.charmap, 0x50, 32)
    decodedNames[#decodedNames + 1] = name
    address = address + consumed
  end

  local aiMods = {}
  address = choices.address
  for _ = 1, #order do
    local mods = {}
    while true do
      local value = self.rom:byte(choices.bank, address)
      address = address + 1
      if value == 0 then break end
      mods[#mods + 1] = value
    end
    aiMods[#aiMods + 1] = mods
  end
  local partyStarts = {}
  for index = 0, #order - 1 do
    partyStarts[#partyStarts + 1] = self.rom:word(
      pointers.bank, pointers.address + index * 2)
  end
  local partyEnds = {}
  for index = 2, #partyStarts do partyEnds[#partyEnds + 1] = partyStarts[index] end
  partyEnds[#partyEnds + 1] = self:symbol("TrainerAI").address

  local out, written = {}, {}
  for index, label in ipairs(order) do
    local trainerId = "OPP_" .. label
    local rawMoney = self.rom:bytes(
      money.bank, money.address + (index - 1) * 5 + 2, 3)
    local picture = self.manifest.trainerPics[index]
    if picture and not written[picture.imageBase] then
      self:writeCompressedPic(picture.label,
        "battle/trainers/" .. picture.imageBase .. ".png")
      written[picture.imageBase] = true
    end
    local parties = self:trainerParties(
      pointers.bank, partyStarts[index], partyEnds[index])
    -- ChiefData is empty in the ROM (the Celadon Chief battle is unused/
    -- cut content); tools/rom_manifest.json carries a hand-authored party
    -- for the trainers this project reimplements, since no ROM data exists
    -- to extract for them.
    if #parties == 0 then
      local override = self.manifest.trainerPartyOverrides
        and self.manifest.trainerPartyOverrides[trainerId]
      if override then parties = { copy(override) } end
    end
    out[trainerId] = {
      id = trainerId, index = index, name = decodedNames[index],
      source = "ROM:TrainerDataPointers",
      pic = picture and picture.path or nil,
      baseMoney = math.floor(Rom.bcd(rawMoney) / 100),
      aiMods = aiMods[index],
      parties = parties,
    }
    self:tick("Trainers", index, #order)
  end
  -- Yellow's Jessie & James fight as OPP_ROCKET but carry their own pic
  -- (home/trainers2.asm IsFightingJessieJames); only Yellow's manifest has
  -- the symbol, so Red and Blue skip this (#439).
  if self.symbols.JessieJamesPic then
    local relative = "battle/trainers/jessie_james.png"
    self:writeCompressedPic("JessieJamesPic", relative)
    if out.OPP_ROCKET then
      out.OPP_ROCKET.picJessieJames = "assets/generated/" .. relative
    end
  end
  self:write("trainers", out)
  return out
end

function RomExtractor:wildTable(bank, address)
  local grassRate = self.rom:byte(bank, address)
  address = address + 1
  local grass = { rate = grassRate, slots = {} }
  if grassRate ~= 0 then
    for _ = 1, 10 do
      local row = self.rom:bytes(bank, address, 2)
      address = address + 2
      grass.slots[#grass.slots + 1] = {
        level = row[1], species = self:species(row[2]),
      }
    end
  end
  local waterRate = self.rom:byte(bank, address)
  address = address + 1
  local water = { rate = waterRate, slots = {} }
  if waterRate ~= 0 then
    for _ = 1, 10 do
      local row = self.rom:bytes(bank, address, 2)
      address = address + 2
      water.slots[#water.slots + 1] = {
        level = row[1], species = self:species(row[2]),
      }
    end
  end
  return grass, water
end

function RomExtractor:extractEncounters()
  self:beginStage("Wild Pokemon")
  local maps = self.manifest.constants.mapOrder
  local pointers = self:symbol("WildDataPointers")
  local nothing = self:symbol("NothingWildMons")
  local out = {}
  for index, mapId in ipairs(maps) do
    local address = self.rom:word(
      pointers.bank, pointers.address + (index - 1) * 2)
    if address ~= nothing.address then
      local grass, water = self:wildTable(pointers.bank, address)
      local entry = {
        source = ("ROM:%02X:%04X"):format(pointers.bank, address),
      }
      if grass.rate ~= 0 or #grass.slots > 0 then entry.grass = grass end
      if water.rate ~= 0 or #water.slots > 0 then entry.water = water end
      out[mapId] = entry
    end
    self:tick("Wild Pokemon", index, #maps)
  end
  self:write("encounters", out)
  return out
end

local TEXT_GLYPH_OVERRIDES = {
  [0x4B] = "{_CONT}", [0x4C] = "{SCROLL}",
  [0x6D] = "{COLON}", [0xF0] = "¥",
}

function RomExtractor:textGlyph(value)
  if TEXT_GLYPH_OVERRIDES[value] then return TEXT_GLYPH_OVERRIDES[value] end
  local glyph = self.manifest.charmap[tostring(value)]
    or ("{BYTE:%02X}"):format(value)
  if glyph:sub(1, 1) == "<" and glyph:sub(-1) == ">" then
    return "{" .. glyph:sub(2, -2) .. "}"
  end
  return glyph
end

function RomExtractor:decodeTextCommands(symbol, substitutions)
  local address = symbol.address
  local pending = 1
  local out = {}
  for _ = 1, 4096 do
    local command = self.rom:byte(symbol.bank, address)
    address = address + 1
    if command == 0x50 then
      assert(pending > #substitutions,
        symbol.name .. ": unused dynamic text substitutions")
      return table.concat(out)
    elseif command == 0 then
      while true do
        local value = self.rom:byte(symbol.bank, address)
        address = address + 1
        if value == 0x50 then break end
        if value == 0x57 or value == 0x58 or value == 0x5F then
          assert(pending > #substitutions,
            symbol.name .. ": unused dynamic text substitutions")
          return table.concat(out)
        end
        out[#out + 1] = self:textGlyph(value)
      end
    elseif command == 1 or command == 2 or command == 9 then
      local expected = substitutions[pending]
      assert(expected, symbol.name .. ": missing dynamic text substitution")
      assert(command == expected[1],
        symbol.name .. ": dynamic text command mismatch")
      out[#out + 1] = expected[2]
      pending = pending + 1
      address = address + (command == 1 and 2 or 3)
    else
      error(("%s: unsupported text command $%02X")
        :format(symbol.name, command))
    end
  end
  error(symbol.name .. ": text command stream is too long")
end

function RomExtractor:extractText()
  self:beginStage("Dialogue")
  local metadata = self.manifest.text
  local texts = {}
  for index, label in ipairs(metadata.labels) do
    texts[label] = self:decodeTextCommands(
      self:symbol(label), metadata.dynamic[label] or {})
    self:tick("Dialogue", index, #metadata.labels)
  end
  local trainerHeaders = {}
  for mapLabel, headers in pairs(metadata.trainerHeaders) do
    local converted = {}
    for index, header in pairs(headers) do converted[tonumber(index)] = header end
    trainerHeaders[mapLabel] = converted
  end
  self:write("text", texts)
  self:write("text_pointers", metadata.pointers)
  self:write("trainer_headers", trainerHeaders)
  return {
    texts = texts, pointers = metadata.pointers,
    trainerHeaders = trainerHeaders,
  }
end

function RomExtractor:extractYellowTitleArt()
  -- pret/pokeyellow engine/movie/title_yellow.asm: the Yellow title is a
  -- tilemap composition over BOTH tile banks.  LoadYellowTitleScreenGFX
  -- loads PokemonLogoGraphics into vChars2 (BG ids $00-$7F),
  -- TitlePikachuBGGraphics into vChars1 (ids $80-$EF),
  -- TitlePikachuOBGraphics at vChars1 tile $70 (ids $F0-$FC, also the eye
  -- OAM tiles), and PokemonLogoCornerGraphics at vChars1 tile $7D (ids
  -- $FD-$FF).  Every tilemap mixes ids from several of those sheets, so a
  -- single-sheet lookup shows checkerboard garbage where a foreign-bank id
  -- lands (e.g. blank id $00 = logo tile 0, not Pikachu BG tile 0).
  if not self.symbols["TitlePikachuBGGraphics"] then return end
  -- raw sheets, kept for debugging / mod reference
  self:raw2bpp("TitlePikachuBGGraphics", 128, 32,
    "title/pikachu_bg.png", { transparent = true })
  self:raw2bpp("TitlePikachuOBGraphics", 96, 8,
    "title/pikachu_ob.png", { transparent = true })

  -- Tile counts are the Graphics..GraphicsEnd symbol gaps in pokeyellow.sym.
  local function sheetTiles(label, count, transparent)
    local symbol = self:symbol(label)
    local raw = self.rom:bytes(symbol.bank, symbol.address, count * 16)
    local tiles = {}
    for offset = 1, #raw, 16 do
      local one = {}
      for i = offset, offset + 15 do one[#one + 1] = raw[i] end
      tiles[#tiles + 1] = ImageWriter.decode2bpp(one, 8, 8, transparent)
    end
    return tiles
  end
  local logo = sheetTiles("PokemonLogoGraphics", 115)
  local corner = sheetTiles("PokemonLogoCornerGraphics", 3)
  local bg = sheetTiles("TitlePikachuBGGraphics", 64)
  local ob = sheetTiles("TitlePikachuOBGraphics", 12)
  local obClear = sheetTiles("TitlePikachuOBGraphics", 12, true)
  -- Title rOBP0=$E0: remap eye OAM shades 1/2 → white before baking into the
  -- MEWMON BG composition (otherwise glints read as body yellow).
  local eyeOb = {}
  for i, tile in ipairs(obClear) do
    local copy = ImageWriter.blank(8, 8, 0, 0, 0, 0)
    ImageWriter.blit(copy, tile, 0, 0)
    eyeOb[i] = ImageWriter.applyTitleObp0(copy)
  end
  local function tileFor(id)
    if id < 0x80 then return logo[id + 1] end
    if id < 0xF0 then return bg[id - 0x80 + 1] end
    if id < 0xFD then return ob[id - 0xF0 + 1] end
    return corner[id - 0xFD + 1]
  end
  -- OAM-style blit: color-0 pixels stay whatever the target already holds
  -- (ImageWriter.blit copies alpha-0 pixels wholesale, which would punch
  -- holes into the face under the eye sprites).
  local function blitSprite(target, tile, tx, ty, flipX)
    for y = 0, 7 do
      for x = 0, 7 do
        local sx = flipX and 7 - x or x
        local r, g, b, a = tile:getPixel(sx, y)
        if a ~= 0 then target:setPixel(tx + x, ty + y, r, g, b, a) end
      end
    end
  end
  -- cells = { {id, col, row}, ... }; untouched cells stay transparent
  local function compose(cols, rows, cells)
    local pose = ImageWriter.blank(cols * 8, rows * 8, 1, 1, 1, 0)
    for _, cell in ipairs(cells) do
      local tile = tileFor(cell[1])
      if tile then ImageWriter.blit(pose, tile, cell[2] * 8, cell[3] * 8) end
    end
    return pose
  end
  local function mapCells(map, cols, rows)
    local ids = self.rom:bytes(map.bank, map.address, cols * rows)
    local cells = {}
    for index, id in ipairs(ids) do
      cells[#cells + 1] =
        { id, (index - 1) % cols, math.floor((index - 1) / cols) }
    end
    return cells
  end

  -- TitleScreen_PlacePokemonLogo: 16x7 box at (2,1).  Yellow's logo sheet
  -- is deduplicated (unlike Red's sequential rip), so the raw2bpp
  -- pokemon_logo.png from extractField is scrambled; overwrite it with the
  -- tilemap composition.  Kept opaque: TitleState clears to white behind it.
  self:save(compose(16, 7,
    mapCells(self:symbol("TitleScreenPokemonLogoTilemap"), 16, 7)),
    "title/pokemon_logo.png")

  -- TitleScreen_PlacePikaSpeechBubble: 7x4 box at (6,4) plus the two tail
  -- tiles $64/$65 the routine pokes at (9,8) -- one row below the box, over
  -- blank cells of the Pikachu row.  Composed 7x5 with the tail at (3,4);
  -- matteColor0 clears the outside-the-balloon whites, the outline protects
  -- the interior.
  local bubbleCells = mapCells(
    self:symbol("TitleScreenPikaBubbleTilemap"), 7, 4)
  bubbleCells[#bubbleCells + 1] = { 0x64, 3, 4 }
  bubbleCells[#bubbleCells + 1] = { 0x65, 4, 4 }
  self:save(ImageWriter.matteColor0(compose(7, 5, bubbleCells)),
    "title/pika_bubble.png")

  -- TitleScreen_PlacePikachu: 12x9 box at (4,8) plus the right-ear edge
  -- tiles it pokes down column 16 (rows 10-13) -- composed 13x9 with those
  -- at relative column 12, rows 2-5.  The open eyes are OAM
  -- (TitleScreenPikachuEyesOAMData, copied at place time): OB tiles 0-3 at
  -- screen (56,80)/(88,80) blocks, the left eye x-flipped (attr $22); baked
  -- into the composition relative to the box origin px(32,64).
  local pikaCells = mapCells(self:symbol("TitleScreenPikachuTilemap"), 12, 9)
  pikaCells[#pikaCells + 1] = { 0x96, 12, 2 }
  pikaCells[#pikaCells + 1] = { 0x9d, 12, 3 }
  pikaCells[#pikaCells + 1] = { 0xa7, 12, 4 }
  pikaCells[#pikaCells + 1] = { 0xb1, 12, 5 }
  local pikachu = ImageWriter.matteColor0(compose(13, 9, pikaCells))
  -- DoTitleScreenFunction's blink rewrites the eye OAM tile ids with
  -- `and $f3 / or e` (e = 0 open / 4 half / 8 closed), so the OB sheet
  -- holds three 4-tile eye sets.  Bake the open set into pikachu.png and
  -- save half/closed as standalone overlays for TitleState's blink.
  local EYE_LAYOUT = {
    { 2, 24, 16, true }, { 1, 32, 16, true },
    { 4, 24, 24, true }, { 3, 32, 24, true },
    { 1, 56, 16 }, { 2, 64, 16 },
    { 3, 56, 24 }, { 4, 64, 24 },
  }
  -- Blink overlays for the (24,16)-(71,31) eye band: the BG face is
  -- eyeless (the eyes are OAM), so each overlay = the blank-face crop
  -- with the half (+4) / closed (+8) tile set composited color-0
  -- transparent -- exactly what the hardware shows mid-blink.
  local overlays = {}
  for suffix, base in pairs({ eyes_half = 4, eyes_closed = 8 }) do
    local overlay = ImageWriter.blank(48, 16, 1, 1, 1, 0)
    ImageWriter.blit(overlay, pikachu, 0, 0, 24, 16, 48, 16)
    for _, e in ipairs(EYE_LAYOUT) do
      blitSprite(overlay, eyeOb[base + e[1]], e[2] - 24, e[3] - 16, e[4])
    end
    overlays[suffix] = overlay
  end
  -- open eyes bake into pikachu.png AFTER the blank-face crops
  for _, e in ipairs(EYE_LAYOUT) do
    blitSprite(pikachu, eyeOb[e[1]], e[2], e[3], e[4])
  end
  self:save(pikachu, "title/pikachu.png")
  for suffix, overlay in pairs(overlays) do
    self:save(overlay, "title/" .. suffix .. ".png")
  end
end

function RomExtractor:extractSurfingPikachuTitleArt()
  -- engine/minigame/surfing_pikachu.asm
  -- DrawSurfingPikachuMinigameIntroBackground: compose the 160x144
  -- "Pikachu's Beach" title from SurfingMinigame_* tilemaps over
  -- SurfingPikachu1Graphics3 tiles (mirrors tools/build_rom_data.py).
  if not self.symbols["SurfingPikachu1Graphics3"] then return end
  if not self.symbols["SurfingMinigame_BeachIntroTilemap"] then return end

  local beachIntro = self:symbol("SurfingMinigame_BeachIntroTilemap")
  local useCtrlPad = self:symbol("SurfingMinigame_UseControlPadTilemap")
  local toSurfRad = self:symbol("SurfingMinigame_ToSurfRadTilemap")
  local titleMap = self:symbol("SurfingMinigame_TitleTilemap")

  local beachBytes = self.rom:bytes(
    beachIntro.bank, beachIntro.address, 12 * 20)
  local useCtrlBytes = self.rom:bytes(
    useCtrlPad.bank, useCtrlPad.address, 15)
  local toSurfRadBytes = self.rom:bytes(
    toSurfRad.bank, toSurfRad.address, 13)
  local titleMapBytes = self.rom:bytes(
    titleMap.bank, titleMap.address, 6 * 12)

  local screen = {}
  for _ = 1, 20 * 18 do screen[#screen + 1] = 0xff end

  for i = 1, #beachBytes do
    screen[6 * 20 + i] = beachBytes[i]
  end
  for r = 0, 5 do
    for c = 0, 11 do
      screen[r * 20 + (4 + c) + 1] = titleMapBytes[r * 12 + c + 1]
    end
  end
  for r = 0, 2 do
    for c = 0, 14 do
      screen[(7 + r) * 20 + (3 + c) + 1] = 0xff
    end
  end
  for i = 1, #useCtrlBytes do
    screen[7 * 20 + 3 + i] = useCtrlBytes[i]
  end
  for i = 1, #toSurfRadBytes do
    screen[9 * 20 + 4 + i] = toSurfRadBytes[i]
  end

  local gfx3 = self:symbol("SurfingPikachu1Graphics3")
  local rawGfx3 = self.rom:bytes(gfx3.bank, gfx3.address, 144 * 16)
  local tiles = {}
  for tile = 0, 143 do
    local one = {}
    for j = 1, 16 do one[j] = rawGfx3[tile * 16 + j] end
    tiles[tile + 1] = ImageWriter.decode2bpp(one, 8, 8, false)
  end
  local blank = ImageWriter.blank(8, 8, 1, 1, 1, 1)

  local titleBg = ImageWriter.blank(160, 144, 1, 1, 1, 1)
  for r = 0, 17 do
    for c = 0, 19 do
      local tileId = screen[r * 20 + c + 1]
      local tileImg = blank
      if tileId ~= 0xff then
        local idx = tileId >= 0x80 and (tileId - 0x80 + 1) or (128 + tileId + 1)
        if idx >= 1 and idx <= 144 then tileImg = tiles[idx] end
      end
      ImageWriter.blit(titleBg, tileImg, c * 8, r * 8)
    end
  end
  self:save(titleBg, "minigame/title_bg.png")

  -- Intro paddling Pikachu frames (surfing_pikachu_oam.asm .IntroPikachu).
  local INTRO_PIKA_FRAME_BASE = { 0x80, 0x84, 0x88, 0x8c }
  local INTRO_PIKA_OAM = {
    { -12, -16, 0x03, true }, { -12, -8, 0x02, true },
    { -12, 0, 0x01, true }, { -12, 8, 0x00, true },
    { -4, -16, 0x13, true }, { -4, -8, 0x12, true },
    { -4, 0, 0x11, true }, { -4, 8, 0x10, true },
    { 4, -16, 0x23, true }, { 4, -8, 0x22, true },
    { 4, 0, 0x21, true }, { 4, 8, 0x20, true },
  }
  local function blitIntroTile(target, tile, tx, ty, flipX)
    for y = 0, 7 do
      for x = 0, 7 do
        local sx = flipX and (7 - x) or x
        local r, g, b, a = tile:getPixel(sx, y)
        local px, py = tx + x, ty + y
        if a ~= 0 and px >= 0 and py >= 0
            and px < target:getWidth() and py < target:getHeight() then
          target:setPixel(px, py, r, g, b, a)
        end
      end
    end
  end
  for frame, vramBase in ipairs(INTRO_PIKA_FRAME_BASE) do
    local pose = ImageWriter.blank(32, 24, 1, 1, 1, 0)
    local sheetBase = vramBase - 0x80
    for _, sp in ipairs(INTRO_PIKA_OAM) do
      local dy, dx, rel, flipX = sp[1], sp[2], sp[3], sp[4]
      local tileImg = tiles[sheetBase + rel + 1]
      if tileImg then
        blitIntroTile(pose, tileImg,
          16 + dx + (flipX and 8 or 0), 12 + dy, flipX)
      end
    end
    self:save(pose, ("minigame/intro_pika_%d.png"):format(frame - 1))
  end
end

function RomExtractor:raw2bpp(label, width, height, relative, options)
  options = options or {}
  local expected = width * height / 4
  local length = options.storedLength or expected
  local symbol = self:symbol(label)
  local raw = self.rom:bytes(symbol.bank, symbol.address, length)
  while #raw < expected do raw[#raw + 1] = 0 end
  if options.columns then
    raw = ImageWriter.columnsToRows(raw, width / 8, height / 8)
  end
  local image = ImageWriter.decode2bpp(
    raw, width, height, options.transparent)
  if options.matte then image = ImageWriter.matteColor0(image) end
  self:save(image, relative)
  return image
end

function RomExtractor:raw1bpp(label, width, height, relative, transparent)
  local symbol = self:symbol(label)
  local raw = self.rom:bytes(
    symbol.bank, symbol.address, width * height / 8)
  local image = ImageWriter.decode1bpp(raw, width, height, transparent)
  self:save(image, relative)
  return image
end

-- Trading animation art: gfx/trade.asm TradingAnimationGraphics is one
-- 49-tile atlas (game_boy.2bpp, built with --remove-duplicates, then
-- link_cable.2bpp), and the Game Boy and open-cable plates are painted out
-- of it through the tilemaps in data/tilemaps.asm (GameBoyTiles 6x8,
-- LinkCableTiles 12x3), whose ids are absolute vChars2 ids starting at $31
-- because trade.asm reaches them through
-- CopyTileIDsFromList_ZeroBaseTileID.  Only the developer-only Python path
-- ever wrote these files, so an imported cache had none of them and
-- TradeAnim drew the whole cinematic as plain rectangles (#750).
function RomExtractor:extractTradeArt()
  local BASE, COUNT = 0x31, 49
  local gfx = self:symbol("TradingAnimationGraphics")
  local atlas = ImageWriter.decode2bpp(
    self.rom:bytes(gfx.bank, gfx.address, COUNT * 16), COUNT * 8, 8)
  local function tileX(id)
    local index = id - BASE
    assert(index >= 0 and index < COUNT,
      ("trade tile $%02X is outside the animation atlas"):format(id))
    return index * 8
  end
  local function plate(label, tilesWide, tilesHigh, relative, matte)
    local map = self:symbol(label)
    local ids = self.rom:bytes(map.bank, map.address, tilesWide * tilesHigh)
    local image = ImageWriter.blank(tilesWide * 8, tilesHigh * 8, 1, 1, 1, 1)
    for index, id in ipairs(ids) do
      ImageWriter.blit(image, atlas,
        (index - 1) % tilesWide * 8,
        math.floor((index - 1) / tilesWide) * 8, tileX(id), 0, 8, 8)
    end
    if matte then image = ImageWriter.matteColor0(image) end
    self:save(image, relative)
  end
  plate("GameBoyTiles", 6, 8, "trade/game_boy.png", true)
  plate("LinkCableTiles", 12, 3, "trade/open_cable.png", false)
  for _, spec in ipairs({
    { 0x5D, "cable_conn" }, { 0x5E, "cable_seg" }, { 0x5F, "cable_corner" },
    { 0x60, "cable_end" }, { 0x61, "cable_vert" },
  }) do
    local tile = ImageWriter.blank(8, 8, 1, 1, 1, 1)
    ImageWriter.blit(tile, atlas, 0, 0, tileX(spec[1]), 0, 8, 8)
    self:save(tile, "trade/" .. spec[2] .. ".png")
  end
  -- Trade_DrawCableAcrossScreen fills a whole 20-tile row with tile $5e.
  local horizontal = ImageWriter.blank(160, 8, 1, 1, 1, 1)
  for column = 0, 19 do
    ImageWriter.blit(horizontal, atlas, column * 8, 0, tileX(0x5E), 0, 8, 8)
  end
  self:save(horizontal, "trade/cable_horiz.png")

  -- Trade_BallInsideLinkCableOAMBlock draws one tile four times with the
  -- X/Y flips, so each of the two frames -- $7e travelling, $7f bulging,
  -- the bottom row of TradingAnimationGraphics2 -- makes a 16x16 ball.
  local ball = self:symbol("TradingAnimationGraphics2")
  local frames = ImageWriter.decode2bpp(
    self.rom:bytes(ball.bank, ball.address, 64), 16, 16, true)
  for index, name in ipairs({ "cable_ball", "cable_ball_alt" }) do
    local image = ImageWriter.blank(16, 16, 1, 1, 1, 0)
    for y = 0, 7 do
      for x = 0, 7 do
        local r, g, b, a = frames:getPixel((index - 1) * 8 + x, 8 + y)
        image:setPixel(x, y, r, g, b, a)
        image:setPixel(15 - x, y, r, g, b, a)
        image:setPixel(x, 15 - y, r, g, b, a)
        image:setPixel(15 - x, 15 - y, r, g, b, a)
      end
    end
    self:save(image, "trade/" .. name .. ".png")
  end
  -- The ring around the travelling mon: one 16x16 quadrant per animation
  -- frame (engine/gfx/mon_icons.asm TradeBubbleIconGFX), mirrored into a
  -- 32x32 circle by the OAM attributes in Trade_CircleOAMBlocks.
  local bubble = self:symbol("TradeBubbleIconGFX")
  self:write2bpp(self.rom:bytes(bubble.bank, bubble.address, 128),
    16, 32, "trade/bubble.png", true)

  return {
    gameBoy = "assets/generated/trade/game_boy.png",
    openCable = "assets/generated/trade/open_cable.png",
    cableHoriz = "assets/generated/trade/cable_horiz.png",
    cableConn = "assets/generated/trade/cable_conn.png",
    cableVert = "assets/generated/trade/cable_vert.png",
    cableCorner = "assets/generated/trade/cable_corner.png",
    cableEnd = "assets/generated/trade/cable_end.png",
    cableBall = "assets/generated/trade/cable_ball.png",
    cableBallAlt = "assets/generated/trade/cable_ball_alt.png",
    bubble = "assets/generated/trade/bubble.png",
    source = "ROM:TradingAnimationGraphics + ROM:TradeBubbleIconGFX"
      .. " (engine/movie/trade.asm InternalClockTradeAnim)",
  }
end

function RomExtractor:extractField()
  self:beginStage("Interface artwork")
  local done, total = 0, 53
  local function tick()
    done = done + 1
    self:tick("Interface artwork", math.min(done, total), total)
  end

  self:raw2bpp("PokemonLogoGraphics", 128, 56,
    "title/pokemon_logo.png"); tick()
  self:raw1bpp("Version_GFX", 80, 8,
    "title/red_version.png"); tick()
  self:raw2bpp("PlayerCharacterTitleGraphics", 40, 56,
    "title/player.png", { matte = true }); tick()
  self:raw2bpp("NintendoCopyrightLogoGraphics", 152, 8,
    "title/copyright.png"); tick()
  self:raw2bpp("GameFreakLogoGraphics", 72, 8,
    "title/gamefreak_inc.png"); tick()

  do
    local gf = self.symbols["GameFreakLogoGraphics"]
    local tb = self.symbols["TextBoxGraphics"]
    if gf and tb and tb[2] == gf[2] + 9 * 16 + 16 then
      local raw = self.rom:bytes(gf[1], gf[2] + 9 * 16, 16)
      self:save(ImageWriter.decode2bpp(raw, 8, 8, false), "title/nine.png")
    end
  end
  tick()
  -- Yellow fixed Pikachu title art (no-op on Red/Blue manifests).
  self:extractYellowTitleArt(); tick()

  local fallingStar = self:raw2bpp(
    "FallingStar", 8, 8, "intro/falling_star.png",
    { transparent = true })
  tick()
  local blink = ImageWriter.blank(8, 8, 1, 1, 1, 0)
  for y = 0, 7 do
    for x = 0, 7 do
      local r, g, b, a = fallingStar:getPixel(x, y)
      if a ~= 0 and math.abs(r - 2 / 3) < 0.001 then
        blink:setPixel(x, y, r, g, b, a)
      end
    end
  end
  self:save(blink, "intro/falling_star_blink.png"); tick()

  local gameFreak = self:symbol("GameFreakIntro")
  local presentsLength = 104 * 8 / 4
  local presents = ImageWriter.decode2bpp(
    self.rom:bytes(gameFreak.bank, gameFreak.address, presentsLength),
    104, 8, true)
  self:save(presents, "intro/gamefreak_presents.png"); tick()
  self:save(ImageWriter.decode2bpp(
    self.rom:bytes(gameFreak.bank,
      gameFreak.address + presentsLength, 16 * 24 / 4),
    16, 24, true), "intro/gamefreak_logo.png"); tick()

  local textImage = ImageWriter.blank(80, 8, 1, 1, 1, 0)
  local textTiles = { 0, 1, 2, 3, false, 4, 5, 3, 1, 6 }
  for index, tile in ipairs(textTiles) do
    if tile then
      ImageWriter.blit(textImage, presents, (index - 1) * 8, 0,
        tile * 8, 0, 8, 8)
    end
  end
  self:save(textImage, "intro/gamefreak_text.png"); tick()

  local moveTiles = self:symbol("MoveAnimationTiles1")
  local star = ImageWriter.blank(16, 16, 1, 1, 1, 0)
  for _, spec in ipairs({ { 0, 3 }, { 1, 19 } }) do
    local tile = ImageWriter.decode2bpp(self.rom:bytes(
      moveTiles.bank, moveTiles.address + spec[2] * 16, 16),
      8, 8, true)
    ImageWriter.blit(star, tile, 0, spec[1] * 8)
    ImageWriter.blit(star, tile, 8, spec[1] * 8, 0, 0, 8, 8, true)
  end
  self:save(star, "intro/big_star.png"); tick()

  -- Yellow has no FightIntro Gengar/Nidorino fight (pret/pokeyellow
  -- engine/movie/intro_yellow.asm); write blank placeholders so Title/
  -- Intro still find the expected paths. Red/Blue keep the tilemap rip.
  if self.symbols["FightIntroBackMon"] then
    local gengar = self:symbol("FightIntroBackMon")
    local gengarRaw = self.rom:bytes(
      gengar.bank, gengar.address, 96 * 16)
    local gengarTiles = {}
    for offset = 1, #gengarRaw, 16 do
      local raw = {}
      for index = offset, offset + 15 do raw[#raw + 1] = gengarRaw[index] end
      gengarTiles[#gengarTiles + 1] = ImageWriter.decode2bpp(raw, 8, 8)
    end
    for number = 1, 3 do
      local tilemap = self:symbol("GengarIntroTiles" .. number)
      local tileIds = self.rom:bytes(tilemap.bank, tilemap.address, 49)
      local pose = ImageWriter.blank(56, 56, 0, 0, 0, 0)
      for index, tileId in ipairs(tileIds) do
        ImageWriter.blit(pose, gengarTiles[tileId + 1],
          (index - 1) % 7 * 8, math.floor((index - 1) / 7) * 8)
      end
      pose = ImageWriter.matteColor0(pose)
      self:save(pose, "intro/gengar_" .. number .. ".png"); tick()
    end
  else
    for number = 1, 3 do
      self:save(ImageWriter.blank(56, 56, 0, 0, 0, 0),
        "intro/gengar_" .. number .. ".png"); tick()
    end
  end

  if self.symbols["FightIntroFrontMon"] then
    for number, label in ipairs({
      "FightIntroFrontMon", "FightIntroFrontMon2", "FightIntroFrontMon3",
    }) do
      self:raw2bpp(label, 48, 48,
        "intro/red_nidorino_" .. number .. ".png",
        { transparent = true, columns = true })
      tick()
    end
  else
    for number = 1, 3 do
      self:save(ImageWriter.blank(48, 48, 1, 1, 1, 0),
        "intro/red_nidorino_" .. number .. ".png"); tick()
    end
  end

  -- Optional Yellow-only intro atlas (pret/pokeyellow gfx/yellow_intro.asm).
  if self.symbols["YellowIntroGraphics1"] then
    self:raw2bpp("YellowIntroGraphics1", 128, 64,
      "intro/yellow_intro_1.png")
  end
  if self.symbols["YellowIntroGraphics2"] then
    -- atlas2 doubles as the intro's OBJ tile bank (vChars0); OBJ color 0
    -- is hardware-transparent, and the BG draws it over a white clear so
    -- BG cells lose nothing
    self:raw2bpp("YellowIntroGraphics2", 128, 128,
      "intro/yellow_intro_2.png", { transparent = true })
  end
  -- Yellow intro clouds (intro_yellow.asm YellowIntroCloudGFX): 8 tiles,
  -- two 4-tile animation frames -- saved 32x16, one frame per row.
  if self.symbols["YellowIntroCloudGFX"] then
    self:raw2bpp("YellowIntroCloudGFX", 32, 16, "intro/clouds.png")
  end

  for number = 1, 2 do
    self:writeCompressedPic(
      "ShrinkPic" .. number, "intro/shrink" .. number .. ".png")
    tick()
  end

  self:raw2bpp("SlotMachineTiles1", 128, 24,
    "slots/red_slots_1.png", { storedLength = 0x250 }); tick()
  local slotSheet = self:raw2bpp(
    "SlotMachineTiles2", 32, 48, "slots/red_slots_2.png")
  tick()
  local transparentSlots = ImageWriter.blank(32, 48, 1, 1, 1, 0)
  for y = 0, 47 do
    for x = 0, 31 do
      local r, g, b, a = slotSheet:getPixel(x, y)
      transparentSlots:setPixel(x, y, r, g, b,
        r == 1 and g == 1 and b == 1 and a == 1 and 0 or a)
    end
  end
  local slotOrder = self.manifest.field.slotSymbols.order
  local symbolSheet = ImageWriter.blank(#slotOrder * 16, 16, 1, 1, 1, 0)
  for index, name in ipairs(slotOrder) do
    local value = self.manifest.field.slotSymbols.symbols[name].tiles
    local high, low = math.floor(value / 0x100), value % 0x100
    for _, row in ipairs({ { 0, high }, { 1, low } }) do
      local x, y = row[2] % 4 * 8, math.floor(row[2] / 4) * 8
      ImageWriter.blit(symbolSheet, transparentSlots,
        (index - 1) * 16, row[1] * 8, x, y, 16, 8)
    end
  end
  self:save(symbolSheet, "slots/symbols.png"); tick()

  -- Emote sheet layout comes from manifest.field.emotionBubbles so the
  -- versions can differ: Red ships the three shared bubbles, Yellow adds
  -- the five Pikachu-only ones (emotion_bubbles.asm Skull/Heart/Bolt/
  -- Zzz/FishEmote, used by the PikachuEmotionTable reactions).
  local EMOTE_SYMBOLS = {
    EXCLAMATION_BUBBLE = "ShockEmote", QUESTION_BUBBLE = "QuestionEmote",
    SMILE_BUBBLE = "HappyEmote", SKULL_BUBBLE = "SkullEmote",
    HEART_BUBBLE = "HeartEmote", BOLT_BUBBLE = "BoltEmote",
    ZZZ_BUBBLE = "ZzzEmote", FISH_BUBBLE = "FishEmote",
  }
  local bubbleDefs = self.manifest.field.emotionBubbles
    and self.manifest.field.emotionBubbles.bubbles
  local emoteLabels = {}
  for _, b in ipairs(bubbleDefs or {}) do
    emoteLabels[#emoteLabels + 1] = EMOTE_SYMBOLS[b.name]
  end
  if #emoteLabels == 0 then
    emoteLabels = { "ShockEmote", "QuestionEmote", "HappyEmote" }
  end
  local emotes = ImageWriter.blank(#emoteLabels * 16, 16, 1, 1, 1, 0)
  for index, label in ipairs(emoteLabels) do
    local symbol = self:symbol(label)
    local image = ImageWriter.decode2bpp(
      self.rom:bytes(symbol.bank, symbol.address, 64), 16, 16, true)
    ImageWriter.blit(emotes, image, (index - 1) * 16, 0)
  end
  self:save(emotes, "emotes.png"); tick()

  local tradeArt = self:extractTradeArt(); tick()

  -- Yellow-only: the Surfing Pikachu minigame sheets
  -- (gfx/surfing_pikachu.asm) at pret's canvas widths, so
  -- src/ui/SurfingMinigame.lua's quads can be read off the source pngs.
  -- 1a is the BG set (water/beach/score tiles, opaque); 1b the OAM pose
  -- sheet and 1c the intro set (both color-0 transparent).
  for _, spec in ipairs({
    { "SurfingPikachu1Graphics1", 65, 40, false, "minigame/surf_1a.png" },
    { "SurfingPikachu1Graphics2", 256, 128, true, "minigame/surf_1b.png" },
    { "SurfingPikachu1Graphics3", 144, 96, true, "minigame/surf_1c.png" },
  }) do
    if self.symbols[spec[1]] then
      local symbol = self:symbol(spec[1])
      local tilesPerRow = spec[3] / 8
      local image = ImageWriter.decode2bpp(
        self.rom:bytes(symbol.bank, symbol.address, spec[2] * 16),
        spec[3], spec[2] / tilesPerRow * 8, spec[4])
      self:save(image, spec[5])
    end
  end
  self:extractSurfingPikachuTitleArt()

  -- Yellow-only: TalkToPikachu's framed portrait, one 5x5 base frame per
  -- PikaPicAnimScript -- each script's FIRST pikapic_loadgfx in
  -- data/pikachu/pikachu_pic_animation.asm, the pic PikaPicAnimBGFrames_4
  -- (PikaAnimTilemap_1, column order) paints.  Scripts 18/22/23/24 have no
  -- compressed base and take PikaPicAnimBGFrames_5 -> PikaAnimTilemap_9,
  -- which is ROW order over a raw 25-tile sheet, hence no columns flag.
  -- Script 26 shares script 11's base.  The pikaframe overlays each script
  -- draws ON TOP of the base are a second full pose out of the same blob and
  -- stay unripped: PikachuFollower.picLift stands in for their motion
  -- (#561, still on #407's stand-in).
  local PIKAPIC_BASE = {
    "Pic_e4000", "Pic_e411c", "Pic_e4272", "Pic_e4383", "Pic_e458b",
    "Pic_e467b", "Pic_e476e", "Pic_e49d1", "Pic_e4b39", "Pic_e4c3e",
    "Pic_e5000", "Pic_e523f", "Pic_e548e", "Pic_e56d1", "Pic_e5924",
    "Pic_e5b7d", "Pic_e5ddd", "GFX_e6020", "Pic_e6340", "Pic_e6587",
    "Pic_e67d6", "GFX_e6e6f", "GFX_e718f", "GFX_e74af", "Pic_e77cf",
    "Pic_e5000", "Pic_f0abf", "Pic_f0cf4",
  }
  if self.symbols[PIKAPIC_BASE[1]] then
    for script, label in ipairs(PIKAPIC_BASE) do
      local path = "pikachu/pikapic_" .. script .. ".png"
      if label:sub(1, 4) == "GFX_" then
        self:raw2bpp(label, 40, 40, path, { matte = true })
      else
        self:writeCompressedPic(label, path)
      end
    end
  end

  self:raw1bpp("LedgeHoppingShadow", 8, 8,
    "fx/shadow.png", true); tick()
  for _, spec in ipairs({
    { "RedFishingRodTiles", 8, 24, "fishing_rod.png" },
    { "RedFishingTilesSide", 16, 8, "red_fish_side.png" },
    { "RedFishingTilesFront", 16, 8, "red_fish_front.png" },
    { "RedFishingTilesBack", 16, 8, "red_fish_back.png" },
    { "PokeCenterFlashingMonitorAndHealBall", 8, 16, "heal_machine.png" },
    { "SSAnneSmokePuffTile", 8, 8, "smoke.png" },
  }) do
    self:raw2bpp(spec[1], spec[2], spec[3],
      "fx/" .. spec[4], { transparent = true })
    tick()
  end

  -- The cuttable tree's own sprite: InitCutAnimOAM (engine/overworld/cut.asm)
  -- copies Overworld_GFX tiles $2d-$2e (top half) and $3d-$3e (bottom half)
  -- into the OAM tiles the Cut animation slides apart, so this comes out of
  -- the OVERWORLD tileset's own graphics blob rather than a named symbol.
  do
    local overworldIndex
    for i, name in ipairs(self.manifest.constants.tilesetOrder) do
      if name == "OVERWORLD" then overworldIndex = i break end
    end
    assert(overworldIndex, "OVERWORLD tileset not found in tilesetOrder")
    local tilesetHeaders = self:symbol("Tilesets")
    local rowAddress = tilesetHeaders.address + (overworldIndex - 1) * 12
    local gfxBank = self.rom:byte(tilesetHeaders.bank, rowAddress)
    local gfxPointer = self.rom:word(tilesetHeaders.bank, rowAddress + 3)
    local cutTree = ImageWriter.blank(16, 16, 1, 1, 1, 0)
    for _, spec in ipairs({
      { 0x2d, 0, 0 }, { 0x2e, 8, 0 }, { 0x3d, 0, 8 }, { 0x3e, 8, 8 },
    }) do
      local tileIndex, dx, dy = spec[1], spec[2], spec[3]
      local tile = ImageWriter.decode2bpp(
        self.rom:bytes(gfxBank, gfxPointer + tileIndex * 16, 16),
        8, 8, true)
      ImageWriter.blit(cutTree, tile, dx, dy)
    end
    self:save(cutTree, "fx/cut_tree.png"); tick()
  end

  self:raw2bpp("BattleTransitionTile", 8, 8,
    "fx/battle_transition.png"); tick()
  self:raw2bpp("PokedexTileGraphics", 24, 48,
    "fx/pokedex.png"); tick()

  self:raw2bpp("HpBarAndStatusGraphics", 120, 16,
    "battle/font_battle_extra.png", { transparent = true }); tick()
  for number, label in ipairs({
    "BattleHudTiles1", "BattleHudTiles2", "BattleHudTiles3",
  }) do
    self:raw1bpp(label, 24, 8,
      "battle/battle_hud_" .. number .. ".png", true)
    tick()
  end

  local theEnd = self:symbol("TheEndGfx")
  local interleaved = self.rom:bytes(
    theEnd.bank, theEnd.address, 160)
  local reordered = {}
  for column = 0, 4 do
    for offset = 1, 16 do
      reordered[column * 16 + offset] =
        interleaved[column * 32 + offset]
      reordered[(column + 5) * 16 + offset] =
        interleaved[column * 32 + 16 + offset]
    end
  end
  self:save(ImageWriter.decode2bpp(reordered, 40, 16),
    "credits/the_end.png"); tick()
  self:raw2bpp("WorldMapTileGraphics", 32, 32,
    "townmap/tiles.png"); tick()
  self:raw1bpp("TownMapCursor", 16, 16,
    "townmap/cursor.png", true); tick()
  -- engine/items/town_map.asm:296, 150
  local nestArt, upArrowArt
  if self.symbols["MonNestIcon"] then
    self:raw1bpp("MonNestIcon", 8, 8, "townmap/nest.png", true); tick()
    nestArt = {
      path = "assets/generated/townmap/nest.png", width = 8, height = 8,
    }
  end
  if self.symbols["TownMapUpArrow"] then
    self:raw1bpp("TownMapUpArrow", 8, 8, "townmap/up_arrow.png", true); tick()
    upArrowArt = {
      path = "assets/generated/townmap/up_arrow.png", width = 8, height = 8,
    }
  end

  local data = copy(self.manifest.field)
  if type(data.townMap) == "table" then
    data.townMap.nest = nestArt
    data.townMap.upArrow = upArrowArt
  end
  local adjacency = data.hiddenExtras.trashCans.adjacent
  local converted = {}
  for index, values in pairs(adjacency) do converted[tonumber(index)] = values end
  data.hiddenExtras.trashCans.adjacent = converted
  data.tradeArt = tradeArt
  data.source = "canonical Pokemon Red ROM + bundled port metadata"
  self:write("field", data)
  self:tick("Interface artwork", total, total)
  return data
end

function RomExtractor:extractAudio()
  self:beginStage("Sound programs")
  local metadata = copy(self.manifest.audio)
  -- Yellow adds a fourth music bank ($20: Jessie & James, Surfing
  -- Pikachu, GB Printer); the manifest names the pack when it needs it.
  local bankOrder = metadata.programBanks or { 2, 8, 31 }
  local chunks = {}
  for index, bank in ipairs(bankOrder) do
    local first = Rom.offset(bank, 0x4000) + 1
    chunks[index] = self.rom.data:sub(first, first + 0x3FFF)
    self:tick("Sound programs", index, #bankOrder + 2)
  end
  -- CacheFs (not love.filesystem directly) so a portable install lands this
  -- in the game folder with the rest of the cache; it creates the parent
  -- directory too.
  local CacheFs = require("src.import.CacheFs")
  local ok, writeError = CacheFs.write(
    "assets/generated/audio/programs.bin", table.concat(chunks))
  if not ok then error("could not write audio programs: " .. tostring(writeError)) end

  local songs = {}
  for name, header in pairs(metadata.musicHeaders) do
    songs[name] = header
  end
  metadata.pikaCries = self:extractPikachuCries()
  local cries = {}
  local cryData = metadata.cryData
  for index, species in ipairs(self.manifest.constants.speciesOrder) do
    local row = self.rom:bytes(
      cryData.bank, cryData.address + (index - 1) * 3, 3)
    if not startsWith(species, "MISSINGNO")
        and not startsWith(species, "UNUSED") then
      cries[species] = {
        header = metadata.cryHeaders[tostring(row[1])],
        pitch = row[2],
        length = row[3],
      }
    end
  end
  metadata.runtime = true
  metadata.programFile = "assets/generated/audio/programs.bin"
  metadata.bankOrder = bankOrder
  metadata.songs = songs
  metadata.sfx = metadata.sfxHeaders
  metadata.cries = cries
  metadata.source = "canonical Pokemon Red ROM sound programs"
  self:write("audio", metadata)
  self:tick("Sound programs", #bankOrder + 2, #bankOrder + 2)
  return metadata
end

-- Yellow's voiced Pikachu clips (audio/pikachu_cries_pointers.asm
-- PikachuCriesPointerTable, 42 `dba` rows; each clip is `dw length` then
-- 1-bit PCM, MSB first -- home/pikachu_cries.asm PlayPikachuPCM toggles
-- rAUD3LEVEL per bit at roughly 190 CPU cycles a sample).  Decoded to
-- 16-bit stereo WAVs (identical L/R) so OpenAL never spatializes them as
-- ambient surround (#626); returns the clip count for data.audio.pikaCries,
-- or nil when the manifest has no pointer table (Red/Blue).
function RomExtractor:extractPikachuCries()
  if not self.symbols["PikachuCriesPointerTable"] then return nil end
  local NUM = 42   -- NUM_PIKA_CRIES
  local RATE = 22050 -- ~4.19 MHz / ~190 cycles per sample
  -- byte -> 8 mono sample levels, MSB first (LoadNextSoundClipSample: `and $80`)
  -- levels match the old unsigned-8 WAV (on=0xE0, off=0x20) as floats in [-1,1]
  local lut = {}
  for byte = 0, 255 do
    local out = {}
    for bit = 7, 0, -1 do
      local on = math.floor(byte / 2 ^ bit) % 2 == 1
      out[#out + 1] = on and ((0xE0 - 128) / 128) or ((0x20 - 128) / 128)
    end
    lut[byte] = out
  end
  local function u16(v)
    return string.char(v % 256, math.floor(v / 256) % 256)
  end
  local function u32(v)
    return string.char(v % 256, math.floor(v / 256) % 256,
      math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
  end
  local function i16le(f)
    local v = math.floor(f * 32767 + (f >= 0 and 0.5 or -0.5))
    if v > 32767 then v = 32767 elseif v < -32768 then v = -32768 end
    if v < 0 then v = v + 65536 end
    return string.char(v % 256, math.floor(v / 256) % 256)
  end
  local CacheFs = require("src.import.CacheFs")
  local pointers = self:symbol("PikachuCriesPointerTable")
  for index = 0, NUM - 1 do
    local row = self.rom:bytes(pointers.bank, pointers.address + index * 3, 3)
    local bank, address = row[1], row[2] + row[3] * 256
    local header = self.rom:bytes(bank, address, 2)
    local length = header[1] + header[2] * 256
    local raw = self.rom:bytes(bank, address + 2, length)
    local parts = {}
    for _, byte in ipairs(raw) do
      for _, level in ipairs(lut[byte]) do
        local s = i16le(level)
        parts[#parts + 1] = s .. s -- identical L/R (#626)
      end
    end
    local pcm = table.concat(parts)
    local wav = "RIFF" .. u32(36 + #pcm) .. "WAVEfmt " .. u32(16)
      .. u16(1) .. u16(2) .. u32(RATE) .. u32(RATE * 4) .. u16(4) .. u16(16)
      .. "data" .. u32(#pcm) .. pcm
    local ok, err = CacheFs.write(
      ("assets/generated/audio/pika_cries/cry_%02d.wav"):format(index + 1),
      wav)
    if not ok then
      error("could not write pika cry " .. (index + 1) .. ": " .. tostring(err))
    end
  end
  return NUM
end

function RomExtractor:run()
  local results = {}
  results.constants = self:extractConstants()
  results.tilesets = self:extractTilesets()
  results.maps = self:extractMaps()
  results.font = self:extractFont()
  results.sprites = self:extractSprites()
  results.moves = self:extractMoves()
  results.battle_anims = self:extractBattleAnimations()
  results.items = self:extractItems()
  results.type_chart = self:extractTypeChart()
  results.palettes = self:extractPalettes()
  results.icons = self:extractIcons()
  results.pokemon = self:extractPokemon()
  results.trainers = self:extractTrainers()
  results.encounters = self:extractEncounters()
  results.text = self:extractText()
  results.field = self:extractField()
  results.audio = self:extractAudio()
  if self.progress then
    self.progress(STAGE_COUNT, STAGE_COUNT, "Ready", 1, 1)
  end
  return results
end

return RomExtractor
