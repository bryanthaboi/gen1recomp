local Catalog = require("src.box.Catalog")
local Sprites = require("src.online.OnlineSprites")
local MonAnim = require("src.core.game3.mon_anim")
local Animation = {}
local data
local live = setmetatable({}, { __mode = "k" })

local function animationData()
  if data ~= nil then return data or nil end
  data = false
  local body = Sprites.readBytes("emerald", "data/generated/gba/pokemon/front_anims.lua")
  if not body then return nil end
  local chunk = (loadstring or load)(body, "@box-emerald-animation")
  if not chunk then return nil end
  if setfenv then setfenv(chunk, {}) end
  local ok, front = pcall(chunk)
  if not ok or type(front) ~= "table" or not (front.species and front.lists
      and front.functions and front.animIds and front.animDelays) then return nil end
  local pack = { version = "emerald" }
  function pack.functionName(id) return front.functions[id] end
  function pack.frontAnimId(species) return front.animIds[species] end
  function pack.delay(species) return front.animDelays[species] or 0 end
  function pack.anims(species)
    local row = front.species[species]
    if not row then return nil end
    local result = {}
    for i, id in ipairs(row) do
      local list = front.lists[id]
      result[i - 1] = list and list.cmds or nil
    end
    return result
  end
  data = pack
  return pack
end

function Animation.release(animation)
  if not animation or animation.released then return end
  for _, image in pairs(animation.frames) do
    if image.release then pcall(image.release, image) end
  end
  animation.frames, animation.released = {}, true
  live[animation] = nil
end

function Animation.reset()
  for animation in pairs(live) do Animation.release(animation) end
  data = nil
end

function Animation.new(entry)
  if not entry or entry.mon.isEgg or entry.display.egg then return nil end
  local art, version, mon = Catalog.art(entry)
  if version ~= "emerald" or not art.front or not mon then return nil end
  local pack = animationData()
  local species = tonumber(mon.species)
  if not pack or not species or pack.frontAnimId(species) == nil then return nil end
  local ok, sprite = pcall(function()
    local s = MonAnim.newSprite(species, { animationData = pack, affineMode = "off", data = { [0] = species, [1] = 1 } })
    MonAnim.summary(s, species, false)
    return s
  end)
  if not ok then return nil end
  local animation = { entry = entry, art = art, sprite = sprite, elapsed = 0, frames = {} }
  live[animation] = true
  if MonAnim.hasTwoFramesAnimation(species, "emerald") and love and love.image and love.graphics then
    local Pokemon = require("src.core.game3.pokemon")
    local pic = Pokemon.picSpecies(species, mon.personality)
    local path = (entry.display.shiny and MonAnim.Data.SHEET_SHINY or MonAnim.Data.SHEET):format(pic)
    local read, rgba = pcall(Sprites.readBytes, "emerald", path)
    local size = 64 * 64 * 4
    if read and rgba then
      for frame = 1, math.min(15, math.floor(#rgba / size) - 1) do
        local made, image = pcall(function()
          local pixels = love.image.newImageData(64, 64, "rgba8", rgba:sub(size * frame + 1, size * (frame + 1)))
          local img = love.graphics.newImage(pixels)
          if pixels.release then pixels:release() end
          img:setFilter("nearest", "nearest")
          return img
        end)
        if made then animation.frames[frame] = image end
      end
    end
  end
  return animation
end

function Animation.update(animation, dt)
  if not animation or animation.released or MonAnim.done(animation.sprite) then return end
  animation.elapsed = animation.elapsed + math.max(0, math.min(dt or 0, 0.25))
  while animation.elapsed >= 1 / 60 and not MonAnim.done(animation.sprite) do
    MonAnim.step(animation.sprite, true)
    animation.elapsed = animation.elapsed - 1 / 60
  end
end

function Animation.draw(animation, x, y, size)
  if not animation or animation.released then return false end
  local image = animation.frames[animation.sprite.frame] or animation.art.front
  if not image then return false end
  local scale = size / 64
  if scale >= 1 then scale = math.floor(scale) end
  local r, g, b, a = love.graphics.getColor()
  love.graphics.setColor(1, 1, 1, 1)
  MonAnim.draw(animation.sprite, image, math.floor(x + size / 2), math.floor(y + size / 2), { scale = scale })
  love.graphics.setColor(r, g, b, a)
  return true
end

require("src.render.Assets").register({ invalidate = Animation.reset, release = Animation.reset })
return Animation
