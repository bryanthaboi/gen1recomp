local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_w0_online_assets"

local ROOT = "data/generated/gba/"
local MANIFESTS = {
  { "chrome/manifest.lua", "chrome/" },
  { "link/manifest.lua", "link/" },
  { "mystery_gift/manifest.lua", "mystery_gift/" },
  { "berry_crush/manifest.lua", "berry_crush/" },
  { "dodrio_berry_picking/manifest.lua", "dodrio_berry_picking/" },
  { "pokemon_jump/manifest.lua", "pokemon_jump/" },
}

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function read(rel)
  local Dataset = require("src.core.game3.dataset")
  local ok, d = pcall(function() return Dataset.cache():read(ROOT .. rel) end)
  if ok and type(d) == "string" and #d > 0 then return d end
  local CacheFs = require("src.import.CacheFs")
  local ok2, d2 = pcall(CacheFs.readActive, ROOT .. rel)
  if ok2 and type(d2) == "string" and #d2 > 0 then return d2 end
  return nil
end

local function manifest(rel)
  local body = read(rel)
  if not body then return nil end
  local chunk = loadstring(body)
  if not chunk then return nil end
  setfenv(chunk, {})
  local ok, man = pcall(chunk)
  return ok and man or nil
end

local function writeFile(path, data)
  os.execute("mkdir -p '" .. DIR .. "'")
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(data)
  f:close()
  return true
end

local function entries(man)
  local out, keys = {}, {}
  for k, v in pairs(man) do
    if type(v) == "table" and v.kind and v.file and v.width and v.height then keys[#keys + 1] = k end
  end
  table.sort(keys)
  for _, k in ipairs(keys) do out[#out + 1] = man[k] end
  return out
end

local function sheet(name, items)
  local W, H, x = 0, 0, 0
  for _, it in ipairs(items) do W = W + it.w + 4; H = math.max(H, it.h) end
  local canvas = love.graphics.newCanvas(math.max(W, 1), math.max(H, 1))
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  love.graphics.clear(1, 0, 1, 1)
  love.graphics.setColor(1, 1, 1, 1)
  for _, it in ipairs(items) do
    love.graphics.draw(it.image, x, 0)
    x = x + it.w + 4
  end
  love.graphics.setCanvas()
  love.graphics.pop()
  local png = canvas:newImageData():encode("png"):getString()
  return writeFile(DIR .. "/" .. name .. ".png", png)
end

return function(game)
  print("PASS driver_started")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  result(game.phase == "boot", "game3 booted on the v122 cache")

  for _, m in ipairs(MANIFESTS) do
    local man = manifest(m[1])
    if result(man ~= nil and (man.format_version or man.formatVersion) == 1, m[1] .. " loads through the active cache") then
      local items = {}
      for _, e in ipairs(entries(man)) do
        local bytes = read(m[2] .. e.file)
        local okImg, img = false, nil
        if bytes and #bytes == e.width * e.height * 4 then
          okImg, img = pcall(function()
            local data = love.image.newImageData(e.width, e.height, "rgba8", bytes)
            local image = love.graphics.newImage(data)
            image:setFilter("nearest", "nearest")
            return image
          end)
        end
        if result(okImg and img ~= nil, m[2] .. e.file .. " decodes to a " .. e.width .. "x" .. e.height .. " image") then
          items[#items + 1] = { image = img, w = e.width, h = e.height }
        end
      end
      local name = "g3w0_" .. m[2]:gsub("/$", ""):gsub("/", "_")
      result(sheet(name, items), name .. ".png written")
    end
  end

  local avatars = manifest("union_room/avatars.lua")
  local CacheFs = require("src.import.CacheFs")
  local allOw = avatars ~= nil
  for _, list in pairs((avatars or {}).gfx_ids or {}) do
    for _, gid in ipairs(list) do
      if not CacheFs.exists(ROOT .. "ow/" .. gid .. ".rgba") then allOw = false end
    end
  end
  result(allOw, "union room avatar gids all have ow/<gid>.rgba")

  for _, g in ipairs({ { "lock8.png", 8 } }) do
    local lock = love.graphics.newImage("assets/game3/" .. g[1])
    result(lock:getWidth() == g[2] and lock:getHeight() == g[2], "assets/game3/" .. g[1] .. " loads as " .. g[2] .. "x" .. g[2])
  end

  if failures == 0 then
    print("PASS w0_online_assets")
    love.event.quit(0)
  else
    print("FAIL w0_online_assets failures=" .. failures)
    love.event.quit(1)
  end
end
