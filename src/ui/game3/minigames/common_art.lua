local Art = {}

Art.ROOT = "data/generated/gba/"

function Art.cache()
  return require("src.core.game3.dataset").cache()
end

local function readLua(cache, rel)
  local src = cache:read(Art.ROOT .. rel)
  if type(src) ~= "string" then return nil, rel .. " is missing from the cache" end
  local fn, err = loadstring(src, "@" .. rel)
  if not fn then return nil, rel .. ": " .. tostring(err) end
  setfenv(fn, {})
  local ok, value = pcall(fn)
  if not ok or type(value) ~= "table" then return nil, rel .. " did not return a table" end
  return value
end

function Art.readLua(dir, file, cache)
  return readLua(cache or Art.cache(), dir .. "/" .. file)
end

function Art.manifest(dir, cache)
  return readLua(cache or Art.cache(), dir .. "/manifest.lua")
end

function Art.tables(dir, cache)
  cache = cache or Art.cache()
  local manifest, err = Art.manifest(dir, cache)
  if not manifest then return nil, err end
  local file = manifest._tables
  if type(file) ~= "string" then return nil, dir .. "/manifest.lua has no _tables" end
  return readLua(cache, dir .. "/" .. file)
end

local function hasGraphics()
  return love ~= nil and love.graphics ~= nil and love.image ~= nil
    and love.graphics.newImage ~= nil
end

function Art.sheet(dir, key, cache, manifest)
  cache = cache or Art.cache()
  if not manifest then
    local err
    manifest, err = Art.manifest(dir, cache)
    if not manifest then return nil, err end
  end
  local entry = manifest[key]
  if type(entry) ~= "table" then return nil, dir .. "/manifest.lua has no " .. tostring(key) end
  local w, h = tonumber(entry.width), tonumber(entry.height)
  if not (w and h) then return nil, dir .. "/" .. key .. " has no size" end
  local rel = dir .. "/" .. (entry.file or (key .. ".rgba"))
  local rgba = cache:read(Art.ROOT .. rel)
  if type(rgba) ~= "string" or #rgba ~= w * h * 4 then
    return nil, rel .. " is missing from the cache or has the wrong size"
  end
  local fw = tonumber(entry.frame_w) or w
  local fh = tonumber(entry.frame_h) or h
  local frames = tonumber(entry.frames) or math.max(1, math.floor(h / fh))
  local sheet = {
    key = key, entry = entry, width = w, height = h,
    frame_w = fw, frame_h = fh, frames = frames, quads = {},
  }
  if hasGraphics() then
    local data = love.image.newImageData(w, h, "rgba8", rgba)
    local image = love.graphics.newImage(data)
    image:setFilter("nearest", "nearest")
    sheet.image = image
    for i = 0, frames - 1 do
      sheet.quads[i] = love.graphics.newQuad(0, i * fh, fw, fh, w, h)
    end
  end
  return sheet
end

function Art.load(dir, keys, cache)
  cache = cache or Art.cache()
  local manifest, err = Art.manifest(dir, cache)
  if not manifest then return nil, err end
  local out = { manifest = manifest }
  for _, key in ipairs(keys) do
    local sheet, e = Art.sheet(dir, key, cache, manifest)
    if not sheet then return nil, e end
    out[key] = sheet
  end
  return out
end

function Art.drawFrame(sheet, frame, x, y, sx, sy, ox, oy)
  if not (sheet and sheet.image) then return false end
  local quad = sheet.quads[frame or 0]
  if not quad then return false end
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(sheet.image, quad, x, y, 0, sx or 1, sy or 1, ox or 0, oy or 0)
  return true
end

return Art
