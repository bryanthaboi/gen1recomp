local Common = require("src.ui.game3.minigames.common_art")

local Art = {}

Art.DIR = "dodrio_berry_picking"
Art.KEYS = { "bg", "tree_border_left", "tree_border_right", "dodrio", "dodrio_shiny", "status", "berries", "cloud" }

local function hasGraphics()
  return love ~= nil and love.graphics ~= nil and love.image ~= nil and love.graphics.newImage ~= nil
end

local function read(cache, file)
  local data = cache:read(Common.ROOT .. Art.DIR .. "/" .. file)
  if type(data) ~= "string" or #data == 0 then
    return nil, Art.DIR .. "/" .. file .. " is missing from the cache"
  end
  return data
end

local function palColor(pal, bank, index)
  local o = (bank * 16 + index) * 3
  local r, g, b = pal:byte(o + 1, o + 3)
  return r or 0, g or 0, b or 0
end

-- pokefirered/src/dodrio_berry_picking.c:4327
function Art.bakeLayer(tiles, map, pal, cols, rows)
  local img = love.image.newImageData(cols * 8, rows * 8)
  local entries = math.floor(#map / 2)
  for i = 0, math.min(entries, cols * rows) - 1 do
    local lo, hi = map:byte(i * 2 + 1, i * 2 + 2)
    local v = lo + hi * 256
    local tile = v % 1024
    local hflip = math.floor(v / 1024) % 2 == 1
    local vflip = math.floor(v / 2048) % 2 == 1
    local bank = math.floor(v / 4096)
    local tx, ty = (i % cols) * 8, math.floor(i / cols) * 8
    local base = tile * 32
    for y = 0, 7 do
      for x = 0, 7 do
        local byte = tiles:byte(base + y * 4 + math.floor(x / 2) + 1) or 0
        local c = (x % 2 == 0) and (byte % 16) or math.floor(byte / 16)
        if c ~= 0 then
          local r, g, b = palColor(pal, bank, c)
          local dx = hflip and (7 - x) or x
          local dy = vflip and (7 - y) or y
          img:setPixel(tx + dx, ty + dy, r / 255, g / 255, b / 255, 1)
        end
      end
    end
  end
  return img
end

function Art.load(cache)
  cache = cache or Common.cache()
  local art, err = Common.load(Art.DIR, Art.KEYS, cache)
  if not art then return nil, err end
  local T, terr = Common.tables(Art.DIR, cache)
  if not T then return nil, terr end
  art.tables = T
  local bg = art.manifest.bg
  if not (bg.palette and bg.tilemap and bg.tiles) then
    return nil, Art.DIR .. "/manifest.lua bg has no palette, tilemap or tiles"
  end
  local pal, perr = read(cache, bg.palette)
  if not pal then return nil, perr end
  local map, merr = read(cache, bg.tilemap)
  if not map then return nil, merr end
  local tiles, tierr = read(cache, bg.tiles)
  if not tiles then return nil, tierr end
  local r, g, b = palColor(pal, 0, 0)
  art.backdrop = { r / 255, g / 255, b / 255, 1 }
  if hasGraphics() then
    local data = Art.bakeLayer(tiles, map, pal, tonumber(bg.map_w) or 32, math.floor((tonumber(bg.height) or 160) / 8))
    art.scenery = love.graphics.newImage(data)
    art.scenery:setFilter("nearest", "nearest")
  end
  return art
end

return Art
