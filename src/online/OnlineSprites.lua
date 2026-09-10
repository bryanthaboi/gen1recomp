-- engine/gfx/mon_icons.asm WriteSymmetricMonPartySpriteOAM
-- engine/gfx/load_pics.asm

local CacheFs = require("src.import.CacheFs")
local GameVersion = require("src.core.GameVersion")
local Sprites = require("src.pokemon.Sprites")

local OnlineSprites = {}

local catalogs = {}
local cache = {}

-- engine/gfx/mon_icons.asm:246
local function mirrors(name)
  return name ~= nil and name ~= "HELIX"
end

local SHADES = { { 255, 255, 255 }, { 170, 170, 170 },
                 { 85, 85, 85 }, { 0, 0, 0 } }

function OnlineSprites.key(version, species, shiny)
  return ("%s|%s|%s"):format(tostring(version), tostring(species),
    shiny and "shiny" or "normal")
end

function OnlineSprites.reset()
  catalogs, cache = {}, {}
end

function OnlineSprites.keepOnly(versions)
  local keep = {}
  for _, version in ipairs(versions or {}) do keep[tostring(version)] = true end
  for version in pairs(catalogs) do
    if not keep[version] then catalogs[version] = nil end
  end
  for key in pairs(cache) do
    local version = key:match("^([^|]*)|")
    if version and not keep[version] then cache[key] = nil end
  end
end

function OnlineSprites.readBytes(version, path)
  local prefix = GameVersion.cachePrefix(version) or ""
  local bytes = CacheFs.readAt(prefix .. path)
  if type(bytes) == "string" and bytes ~= "" then return bytes end
  return nil
end

local function loadTable(version, path)
  local bytes = OnlineSprites.readBytes(version, path)
  if not bytes then return nil end
  local loader = loadstring or load
  local chunk = loader(bytes, "@" .. path)
  if not chunk then return nil end
  local ok, value = pcall(chunk)
  if not ok or type(value) ~= "table" then return nil end
  return value
end

local function catalog(version)
  local hit = catalogs[version]
  if hit then return hit end
  hit = {
    pokemon = loadTable(version, "data/generated/pokemon.lua") or {},
    icons = loadTable(version, "data/generated/icons.lua") or {},
    palettes = loadTable(version, "data/generated/palettes.lua") or {},
    generation = GameVersion.generation(version),
  }
  catalogs[version] = hit
  return hit
end

local function paletteFor(cat, species, shiny)
  local entry = cat.palettes and cat.palettes.pokemon
    and cat.palettes.pokemon[species]
  if type(entry) == "string" then
    local ramp = cat.palettes.palettes and cat.palettes.palettes[entry]
    if type(ramp) == "table" and #ramp == 4 then return ramp end
    return nil
  end
  if type(entry) ~= "table" then return nil end
  local pair = entry[shiny and "shiny" or "normal"] or entry.normal
  if type(pair) ~= "table" or #pair < 2 then return nil end
  return { { 255, 255, 255 }, pair[1], pair[2], { 0, 0, 0 } }
end

local function shadeIndex(r)
  if r > 0.75 then return 1 end
  if r > 0.5 then return 2 end
  if r > 0.25 then return 3 end
  return 4
end

function OnlineSprites.makeImage(bytes, path, palette)
  if not (love and love.graphics and love.graphics.newImage) then return nil end
  local ok, image = pcall(function()
    local data = love.filesystem.newFileData(bytes, path)
    if not (palette and love.image and love.image.newImageData) then
      return love.graphics.newImage(data)
    end
    local pixels = love.image.newImageData(data)
    if type(pixels.mapPixel) ~= "function" then
      return love.graphics.newImage(data)
    end
    pixels:mapPixel(function(_, _, r, _, _, a)
      local col = palette[shadeIndex(r)] or SHADES[shadeIndex(r)]
      return (col[1] or 0) / 255, (col[2] or 0) / 255, (col[3] or 0) / 255, a
    end)
    return love.graphics.newImage(pixels)
  end)
  if not ok then return nil end
  return image
end

local function image(version, path, palette)
  local bytes = OnlineSprites.readBytes(version, path)
  if not bytes then return false end
  return OnlineSprites.makeImage(bytes, path, palette) or false
end

local function iconPath(cat, mon)
  local icons = cat.icons or {}
  if cat.generation == 2 then
    local id = mon.isEgg and "ICON_EGG"
      or (icons.species and icons.species[mon.species])
    local entry = id and icons.icons and icons.icons[id]
    if type(entry) == "table" then return entry.image, id end
    return nil, id
  end
  local def = cat.pokemon and cat.pokemon[mon.species]
  local entry = (icons.bySpecies and icons.bySpecies[mon.species])
    or (def and def.icon)
  local name, path
  if type(entry) == "string" then
    name = entry
    path = icons.icons and icons.icons[entry]
  elseif type(entry) == "table" then
    path = entry.image
  end
  if not path then
    name = def and def.dex and icons.byDex and icons.byDex[def.dex]
    local hit = name and icons.icons and icons.icons[name]
    path = (type(hit) == "table") and hit.image or hit
  end
  return path, name
end

function OnlineSprites.get(version, mon)
  if type(mon) ~= "table" then return nil end
  return cache[OnlineSprites.key(version, mon.species, mon.shiny == true)]
end

function OnlineSprites.ensure(version, mon)
  if type(mon) ~= "table" or not version then return nil end
  local key = OnlineSprites.key(version, mon.species, mon.shiny == true)
  local hit = cache[key]
  if hit then return hit end
  local cat = catalog(version)
  local def = cat.pokemon and cat.pokemon[mon.species]
  local palette = paletteFor(cat, mon.species, mon.shiny == true)
  local path, name = iconPath(cat, mon)
  local entry = { key = key, mirror = false }
  if path then
    entry.icon = image(version, path, nil)
    entry.mirror = (cat.generation ~= 2) and mirrors(name) or false
  else
    entry.icon = false
  end
  local front, trueColor = Sprites.pic(def and def.spriteFront, {
    species = mon.species,
    side = "front",
    kind = "online",
    mon = mon,
    data = cat,
    shiny = mon.shiny == true,
  })
  if trueColor then palette = nil end
  entry.front = front and image(version, front, palette) or false
  if entry.front == false and front and front ~= (def and def.spriteFront)
     and love and love.filesystem and love.filesystem.read then
    local bytes = love.filesystem.read(front)
    entry.front = bytes and OnlineSprites.makeImage(bytes, front, palette)
      or false
  end
  cache[key] = entry
  return entry
end

function OnlineSprites.prime(version, party)
  if not version or type(party) ~= "table" then return 0 end
  local n = 0
  for _, mon in ipairs(party) do
    if OnlineSprites.ensure(version, mon) then n = n + 1 end
  end
  return n
end

local function paintWhite()
  if not (love.graphics and love.graphics.getColor) then return nil end
  local r, g, b, a = love.graphics.getColor()
  love.graphics.setColor(1, 1, 1, 1)
  return { r, g, b, a }
end

local function restore(saved)
  if saved and love.graphics and love.graphics.setColor then
    love.graphics.setColor(saved[1], saved[2], saved[3], saved[4])
  end
end

function OnlineSprites.drawIcon(entry, x, y, size)
  if type(entry) ~= "table" or not entry.icon then return false end
  local img = entry.icon
  if type(img.getDimensions) ~= "function" then return false end
  local iw, ih = img:getDimensions()
  if not iw or iw <= 0 or ih <= 0 then return false end
  local scale = (size or 16) / 16
  local saved = paintWhite()
  if ih > 16 and entry.mirror then
    local half = love.graphics.newQuad(0, 0, 8, 16, iw, ih)
    love.graphics.draw(img, half, x, y, 0, scale, scale)
    love.graphics.draw(img, half, x + 16 * scale, y, 0, -scale, scale)
  elseif ih > 16 then
    local frame = love.graphics.newQuad(0, 0, 16, 16, iw, ih)
    love.graphics.draw(img, frame, x, y, 0, scale, scale)
  else
    love.graphics.draw(img, x, y, 0, scale, scale)
  end
  restore(saved)
  return true
end

function OnlineSprites.drawFront(entry, x, y, box)
  if type(entry) ~= "table" or not entry.front then return false end
  local img = entry.front
  if type(img.getDimensions) ~= "function" then return false end
  local iw, ih = img:getDimensions()
  if not iw or iw <= 0 or ih <= 0 then return false end
  box = box or 56
  local scale = box / math.max(iw, ih)
  if scale >= 1 then scale = math.floor(scale) end
  local saved = paintWhite()
  love.graphics.draw(img, math.floor(x + (box - iw * scale) / 2),
    math.floor(y + (box - ih * scale) / 2), 0, scale, scale)
  restore(saved)
  return true
end

return OnlineSprites
