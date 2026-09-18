local Lz2 = require("src.import.lttp.Lz2")
local SnesGfx = require("src.import.lttp.SnesGfx")
local Importers = require("src.import.Importers")
local StreamMD5 = require("src.mods.StreamMD5")
local LuaWriter = require("src.import.LuaWriter")

local LttpImport = {}

LttpImport.IMPORTER = "lttp"
LttpImport.EXPORT_VERSION = "1.1.0"

LttpImport.SOURCES = {
  ["608c22b8ff930c62dc2de54bcd6eba72"] = {
    name = "The Legend of Zelda: A Link to the Past (USA)",
    size = 1048576,
  },
}

LttpImport.SHEET_COUNT = 0xDF
LttpImport.SPRITE_FIRST = 115
-- Bank00.asm Decomp .bg_variable / .spr_variable
LttpImport.POINTERS = { bank = 0x4F80, high = 0x505F, low = 0x513E }
LttpImport.RAW_FIRST, LttpImport.RAW_LAST = 115, 126
LttpImport.RAW_SIZE = 0x600
LttpImport.SHEET_TILES_WIDE = 16

-- palettes.asm; a 3bpp sheet uses the lower 8 colors, so a row's first 7
-- entries are the drawable ones and index 0 is transparent.
LttpImport.PALETTE_SETS = {
  { id = "sprites_light", offset = 0xDD218, rows = 4, perRow = 15 },
  { id = "sprites_dark", offset = 0xDD290, rows = 4, perRow = 15 },
  { id = "armor", offset = 0xDD308, rows = 5, perRow = 15 },
  { id = "sprites_aux3", offset = 0xDD39E, rows = 12, perRow = 7 },
  { id = "bg_dungeon", offset = 0xDD734, rows = 16, perRow = 15 },
  { id = "bg_overworld_aux3", offset = 0xDE604, rows = 12, perRow = 7 },
}

-- Bank00.asm: the core sprite DMA sets source bank $10 and writes straight to
-- $2118, so the player's frames are 4bpp in bank $10 and are NOT in the sheet
-- pointer table.  $80000 + 0x7000 lands exactly on $87000, where the table's
-- first sprite entry starts.
LttpImport.PLAYER = { offset = 0x80000, bytes = 0x7000, bits = 4, tiles = 896 }

LttpImport.COLORS_3BPP = 7
LttpImport.COLORS_4BPP = 15
LttpImport.DEFAULT_PALETTE = {
  sprites = { set = "sprites_light", row = 1 },
  tiles = { set = "bg_dungeon", row = 1 },
}

function LttpImport.identify(rom)
  if type(rom) ~= "string" then return nil, "no rom bytes" end
  if #rom % 1024 == 512 then rom = rom:sub(513) end
  local digest = StreamMD5.new():update(rom):final()
  local source = LttpImport.SOURCES[digest]
  if not source then
    return nil, "this is not a Link to the Past dump this importer knows ("
      .. digest .. ")"
  end
  if #rom ~= source.size then
    return nil, ("expected %d bytes, got %d"):format(source.size, #rom)
  end
  return { md5 = digest, name = source.name, size = #rom }, rom
end

function LttpImport.sheetOffset(rom, index)
  local p = LttpImport.POINTERS
  local bank = rom:byte(p.bank + index + 1)
  local high = rom:byte(p.high + index + 1)
  local low = rom:byte(p.low + index + 1)
  if not (bank and high and low) then return nil end
  return SnesGfx.loRomOffset(bank, high, low)
end

function LttpImport.isRaw(index)
  return index >= LttpImport.RAW_FIRST and index <= LttpImport.RAW_LAST
end

function LttpImport.readSheet(rom, index)
  local offset = LttpImport.sheetOffset(rom, index)
  if not offset then return nil, "sheet pointer is out of range" end
  local raw, err
  if LttpImport.isRaw(index) then
    raw = rom:sub(offset + 1, offset + LttpImport.RAW_SIZE)
    if #raw ~= LttpImport.RAW_SIZE then return nil, "raw sheet is truncated" end
  else
    raw, err = Lz2.decompress(rom, offset)
    if not raw then return nil, err end
  end
  return SnesGfx.decodeSheet(raw)
end

function LttpImport.readPlayer(rom)
  local p = LttpImport.PLAYER
  local raw = rom:sub(p.offset + 1, p.offset + p.bytes)
  if #raw ~= p.bytes then return nil, "player graphics are truncated" end
  return SnesGfx.decodeTiles(raw, p.bits)
end

function LttpImport.readPalettes(rom)
  local out = {}
  for _, set in ipairs(LttpImport.PALETTE_SETS) do
    local colors, err = SnesGfx.readPalette(rom, set.offset,
      set.rows * set.perRow)
    if not colors then return nil, err end
    local rows = {}
    for row = 0, set.rows - 1 do
      local one = {}
      for i = 1, set.perRow do one[i] = colors[row * set.perRow + i] end
      rows[row + 1] = one
    end
    out[set.id] = rows
  end
  return out
end

local function sheetImage(tiles, palette)
  local wide = LttpImport.SHEET_TILES_WIDE
  local rows = math.ceil(#tiles / wide)
  local image = love.image.newImageData(wide * 8, rows * 8)
  for index, pixels in ipairs(tiles) do
    local tx = ((index - 1) % wide) * 8
    local ty = math.floor((index - 1) / wide) * 8
    for y = 0, 7 do
      for x = 0, 7 do
        local value = pixels[y * 8 + x + 1]
        if value == 0 then
          image:setPixel(tx + x, ty + y, 0, 0, 0, 0)
        else
          local color = palette and palette[value]
          if color then
            image:setPixel(tx + x, ty + y,
              color[1] / 255, color[2] / 255, color[3] / 255, 1)
          else
            local shade = value / LttpImport.COLORS_3BPP
            image:setPixel(tx + x, ty + y, shade, shade, shade, 1)
          end
        end
      end
    end
  end
  return image
end

local function encodePng(image)
  local ok, fileData = pcall(image.encode, image, "png")
  if not ok then return nil, tostring(fileData) end
  return fileData:getString()
end

-- Yields { done, total, status } as it walks the sheets, so the launcher can
-- draw progress instead of freezing for the length of a 223-sheet import.
function LttpImport.job(rom, fs)
  return coroutine.create(function()
    local source, normalized = LttpImport.identify(rom)
    if not source then error(normalized, 0) end
    rom = normalized

    local packs = {
      tiles = { kind = "tileset", entries = {}, first = 0,
        last = LttpImport.SPRITE_FIRST - 1 },
      sprites = { kind = "sprite", entries = {},
        first = LttpImport.SPRITE_FIRST, last = LttpImport.SHEET_COUNT - 1 },
    }
    local total = LttpImport.SHEET_COUNT + #LttpImport.PALETTE_SETS + 2
    local done = 0
    local skipped = {}

    local palettes, paletteErr = LttpImport.readPalettes(rom)
    if not palettes then error(paletteErr, 0) end

    local function paletteRow(set, row, count)
      local src = palettes[set] and palettes[set][row]
      if not src then return nil end
      local out = {}
      for i = 1, count do out[i] = src[i] end
      return out
    end

    local function defaultPalette(packId)
      local pick = LttpImport.DEFAULT_PALETTE[packId]
      local row = pick and palettes[pick.set] and palettes[pick.set][pick.row]
      if not row then return nil, nil end
      local out = {}
      for i = 1, LttpImport.COLORS_3BPP do out[i] = row[i] end
      return out, pick.set .. "/" .. pick.row
    end

    for _, packId in ipairs({ "tiles", "sprites" }) do
      local palette, paletteName = defaultPalette(packId)
      local pack = packs[packId]
      for index = pack.first, pack.last do
        local tiles, bits = LttpImport.readSheet(rom, index)
        if tiles then
          local file = ("sheet_%03d.png"):format(index)
          local bytes, encodeErr = encodePng(sheetImage(tiles, palette))
          if bytes then
            local size, writeErr = Importers.writeAsset(LttpImport.IMPORTER,
              packId, file, bytes, fs)
            if size then
              pack.entries[("sheet_%03d"):format(index)] = {
                file = file, size = size,
                width = LttpImport.SHEET_TILES_WIDE * 8,
                height = math.ceil(#tiles / LttpImport.SHEET_TILES_WIDE) * 8,
                frames = #tiles,
                colors = bits == 3 and 8 or 4,
                palette = paletteName,
                note = "colour 0 is transparent; recolour from the palettes pack",
              }
            else
              skipped[#skipped + 1] = index .. ": " .. tostring(writeErr)
            end
          else
            skipped[#skipped + 1] = index .. ": " .. tostring(encodeErr)
          end
        else
          skipped[#skipped + 1] = index .. ": " .. tostring(bits)
        end
        done = done + 1
        coroutine.yield({ done = done, total = total,
          status = "Reading sheet " .. index })
      end
    end

    do
      local tiles, playerErr = LttpImport.readPlayer(rom)
      if tiles then
        local palette = paletteRow("armor", 1, LttpImport.COLORS_4BPP)
        local bytes, encodeErr = encodePng(sheetImage(tiles, palette))
        if bytes then
          local size, writeErr = Importers.writeAsset(LttpImport.IMPORTER,
            "sprites", "player.png", bytes, fs)
          if size then
            packs.sprites.entries.player = {
              file = "player.png", size = size,
              width = LttpImport.SHEET_TILES_WIDE * 8,
              height = math.ceil(#tiles / LttpImport.SHEET_TILES_WIDE) * 8,
              frames = #tiles, colors = 16,
              palette = "armor/1",
              note = "bank $10 player frames, 4bpp; colour 0 is transparent",
            }
          else
            skipped[#skipped + 1] = "player: " .. tostring(writeErr)
          end
        else
          skipped[#skipped + 1] = "player: " .. tostring(encodeErr)
        end
      else
        skipped[#skipped + 1] = "player: " .. tostring(playerErr)
      end
    end

    done = done + 1
    coroutine.yield({ done = done, total = total, status = "Reading Link graphics" })

    local overworld = require("src.import.lttp.Overworld")
    local townImage = overworld.image(rom, LttpImport.readSheet)
    local townBytes = assert(encodePng(townImage))
    townImage:release()
    local townSize = assert(Importers.writeAsset(LttpImport.IMPORTER,
      "tiles", "kakariko.png", townBytes, fs))
    packs.tiles.entries.kakariko = {
      file = "kakariko.png", size = townSize, width = 1024, height = 1024,
      frames = 4096, colors = 128,
      note = "16x16 overworld metatiles with Kakariko graphics and palettes",
    }
    done = done + 1
    coroutine.yield({ done = done, total = total, status = "Assembling Kakariko tiles" })

    local paletteEntries = {}
    for _, set in ipairs(LttpImport.PALETTE_SETS) do
      local file = set.id .. ".lua"
      local bytes = LuaWriter.encode(palettes[set.id])
      local size, writeErr = Importers.writeAsset(LttpImport.IMPORTER,
        "palettes", file, bytes, fs)
      if size then
        paletteEntries[set.id] = { file = file, size = size,
          frames = set.rows, note = set.rows .. " rows of " .. set.perRow }
      else
        skipped[#skipped + 1] = set.id .. ": " .. tostring(writeErr)
      end
      done = done + 1
      coroutine.yield({ done = done, total = total,
        status = "Reading palette " .. set.id })
    end

    local written = {}
    local function finish(packId, kind, entries)
      local manifest = {
        format = Importers.PACK_FORMAT,
        importer = LttpImport.IMPORTER,
        pack = packId,
        kind = kind,
        version = LttpImport.EXPORT_VERSION,
        source = { name = source.name, md5 = source.md5, size = source.size },
        entries = entries,
      }
      local ok, err = Importers.writePack(LttpImport.IMPORTER, packId,
        manifest, fs)
      if not ok then error("could not write the " .. packId .. " pack: "
        .. tostring(err), 0) end
      local count = 0
      for _ in pairs(entries) do count = count + 1 end
      written[packId] = count
    end

    finish("tiles", "tileset", packs.tiles.entries)
    finish("sprites", "sprite", packs.sprites.entries)
    finish("palettes", "palette", paletteEntries)

    return { source = source, packs = written, skipped = skipped }
  end)
end

return LttpImport
