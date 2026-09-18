local SnesGfx = require("src.import.lttp.SnesGfx")

local Overworld = {}

local function word(rom, offset)
  local lo, hi = rom:byte(offset + 1, offset + 2)
  assert(hi, "overworld data is truncated")
  return lo + hi * 256
end

-- Bank00.asm InitTilesets, LoadBgGfx; Bank02.asm Overworld_LoadMapProperties.
function Overworld.sheets(rom, area)
  local main = area < 0x40 and 0x20 or 0x21
  local aux = assert(rom:byte(0x7C9C + area + 1))
  local sheets = {}
  for slot = 0, 7 do
    local id = rom:byte(0x6073 + main * 8 + slot + 1)
    if slot >= 3 and slot <= 6 then
      local replacement = rom:byte(0x5D97 + aux * 4 + slot - 3 + 1)
      if replacement ~= 0 then id = replacement end
    end
    sheets[slot + 1] = id
  end
  return sheets
end

-- palettes.asm Palette_OverworldBgMain/Aux1/Aux2/Aux3; Bank0E.asm Overworld_LoadPalettes.
function Overworld.palettes(rom, area)
  local group = assert(rom:byte(0x7D1C + area + 1))
  local aux1, aux2, aux3 = rom:byte(0x75504 + group * 4 + 1,
    0x75504 + group * 4 + 3)
  local main = area < 0x40 and 0 or 1
  local rows = {}
  local function row(palette, first, offset)
    rows[palette] = rows[palette] or {}
    local colors = assert(SnesGfx.readPalette(rom, offset, 7))
    for i, color in ipairs(colors) do rows[palette][first + i - 1] = color end
  end
  for p = 2, 6 do
    row(p, 1, 0xDE6C8 + word(rom, 0xDEC3B + main * 2) + (p - 2) * 14)
  end
  for p = 2, 4 do
    row(p, 9, 0xDE86C + word(rom, 0xDEC13 + aux1 * 2) + (p - 2) * 14)
  end
  for p = 5, 7 do
    row(p, 9, 0xDE86C + word(rom, 0xDEC13 + aux2 * 2) + (p - 5) * 14)
  end
  row(7, 1, 0xDE604 + rom:byte(0xDEBC6 + aux3 + 1))
  return rows
end

-- Bank02.asm Map16ChunkToMap8; Bank0F.asm $0F8000 Map16 to Map8 descriptors.
function Overworld.image(rom, readSheet)
  local sheets, pixels = Overworld.sheets(rom, 0x18), {}
  for slot, id in ipairs(sheets) do pixels[slot] = assert(readSheet(rom, id)) end
  local palettes = Overworld.palettes(rom, 0x18)
  local r, g, b = SnesGfx.color(0x2669)
  local background = { r, g, b }
  local image = love.image.newImageData(1024, 1024)
  local high = { [0] = true, [3] = true, [4] = true, [5] = true }
  for tile = 0, 4095 do
    for cell = 0, 3 do
      local descriptor = word(rom, 0x78000 + tile * 8 + cell * 2)
      local index = descriptor % 1024
      local slot = math.floor(index / 64)
      local source = pixels[slot + 1] and pixels[slot + 1][index % 64 + 1]
      local palette = palettes[math.floor(descriptor / 1024) % 8]
      local flipX = math.floor(descriptor / 0x4000) % 2 == 1
      local flipY = descriptor >= 0x8000
      local ox = tile % 64 * 16 + cell % 2 * 8
      local oy = math.floor(tile / 64) * 16 + math.floor(cell / 2) * 8
      for y = 0, 7 do
        for x = 0, 7 do
          local sx, sy = flipX and 7 - x or x, flipY and 7 - y or y
          local value = source and source[sy * 8 + sx + 1] or 0
          local color = value ~= 0 and palette
            and palette[value + (high[slot] and 8 or 0)] or background
          color = color or background
          image:setPixel(ox + x, oy + y, color[1] / 255,
            color[2] / 255, color[3] / 255, 1)
        end
      end
    end
  end
  return image
end

return Overworld
