local Ax = require("src.import.pmd.AxSprites")
local Catalog = require("src.import.pmd.Catalog")
local Importers = require("src.import.Importers")
local StreamMD5 = require("src.mods.StreamMD5")
local LuaWriter = require("src.import.LuaWriter")

local Pmd = { IMPORTER = "pmd_red", EXPORT_VERSION = "1.0.0", COUNT = #Catalog }
Pmd.FILES = 0x510018
Pmd.MONSTER_DATA = 0x357B98
Pmd.MD5 = "2100cf6f17e12cd34f1513647dfa506b"
Pmd.SIZE = 33554432

function Pmd.identify(rom)
  if type(rom) ~= "string" or #rom ~= Pmd.SIZE then
    return nil, "Expected a 32 MiB Mystery Dungeon Red Rescue Team USA/Australia GBA dump."
  end
  local digest = StreamMD5.new():update(rom):final()
  if digest ~= Pmd.MD5 then
    return nil, "Unsupported Mystery Dungeon dump (" .. digest .. "). Use Red Rescue Team USA/Australia."
  end
  return { md5 = digest, name = "Pokémon Mystery Dungeon: Red Rescue Team (USA/Australia)", size = #rom }
end

function Pmd.readPokemon(rom, index)
  local spec = assert(Catalog[index], "unknown PMD monster index")
  local u8, u16, _, _, ptr = Ax.reader(rom)
  local archive = ptr(Pmd.FILES + (index - 1) * 8 + 4)
  local palette = ptr(Pmd.FILES + 496 * 8 + 4)
  local paletteId = u8(Pmd.MONSTER_DATA + index * 0x48 + 8)
  local sprite = Ax.read(rom, archive, spec.poses, palette, paletteId)
  sprite.id, sprite.monsterId = spec.id, index
  sprite.paletteId = paletteId
  sprite.dexNumber = u16(Pmd.MONSTER_DATA + index * 0x48 + 0x3C)
  return sprite
end

function Pmd.image(sprite, onPose)
  local columns = math.min(8, #sprite.poses)
  local width = columns * sprite.frameWidth
  local height = math.ceil(#sprite.poses / columns) * sprite.frameHeight
  local image = love.image.newImageData(width, height)
  for i, pose in ipairs(sprite.poses) do
    local dx = (i - 1) % columns * sprite.frameWidth - sprite.minX
    local dy = math.floor((i - 1) / columns) * sprite.frameHeight - sprite.minY
    Ax.drawPose(pose, function(x, y, color, palette)
      local rgb = sprite.palettes[palette][color]
      image:setPixel(dx + x, dy + y, rgb[1] / 255, rgb[2] / 255, rgb[3] / 255, 1)
    end)
    if onPose then onPose(i) end
  end
  return image, {
    monsterId = sprite.monsterId, paletteId = sprite.paletteId, dexNumber = sprite.dexNumber,
    frameWidth = sprite.frameWidth, frameHeight = sprite.frameHeight,
    frameColumns = columns, anchorX = -sprite.minX, anchorY = -sprite.minY,
    directions = { "south", "southeast", "east", "northeast", "north", "northwest", "west", "southwest" },
    animations = sprite.animations, sequences = sprite.sequences,
  }
end

function Pmd.job(rom, fs)
  return coroutine.create(function()
    local source, err = Pmd.identify(rom)
    assert(source, err)
    local entries = {}
    for index = 1, Pmd.COUNT do
      local sprite = Pmd.readPokemon(rom, index)
      local function progress(pose)
        if pose % 16 == 0 then
          coroutine.yield({ done = index - 1 + pose / #sprite.poses,
            total = Pmd.COUNT, status = "Assembling " .. sprite.id })
        end
      end
      local image, metadata = Pmd.image(sprite, progress)
      local width, height = image:getDimensions()
      local ok, encoded = pcall(image.encode, image, "png")
      image:release()
      assert(ok, encoded)
      local bytes = encoded:getString()
      if encoded.release then encoded:release() end
      local file = sprite.id .. ".png"
      local size, writeErr = Importers.writeAsset(Pmd.IMPORTER, "sprites", file, bytes, fs)
      assert(size, writeErr)
      local animationFile = sprite.id .. ".lua"
      local animationBytes = LuaWriter.encode({ animations = metadata.animations, sequences = metadata.sequences })
      local animationSize, animationErr = Importers.writeAsset(Pmd.IMPORTER, "sprites", animationFile, animationBytes, fs)
      assert(animationSize, animationErr)
      metadata.animations, metadata.sequences = nil, nil
      entries[sprite.id] = { file = file, size = size, width = width, height = height,
        frames = #sprite.poses, sprite = metadata,
        metadata = { file = animationFile, size = animationSize },
        note = "Assembled poses; transparent color 0; animation timing in 60 Hz ticks." }
      coroutine.yield({ done = index, total = Pmd.COUNT, status = "Imported " .. sprite.id })
    end
    local ok, writeErr = Importers.writePack(Pmd.IMPORTER, "sprites", {
      format = Importers.PACK_FORMAT, importer = Pmd.IMPORTER, pack = "sprites",
      kind = "sprite", version = Pmd.EXPORT_VERSION, source = source, entries = entries,
    }, fs)
    assert(ok, writeErr)
    return { source = source, packs = { sprites = Pmd.COUNT }, skipped = {} }
  end)
end

return Pmd
