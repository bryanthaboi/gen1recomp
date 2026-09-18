-- Field script mon pic (pret ScriptMenu_ShowPokemonPic / showmonpic).
-- 8×8 tile window + 64×64 front (or scaled icon fallback).

local Window = require("src.ui.game3.window")
local Display = require("src.core.game3.display")

local MonPic = {}

MonPic.active = false
MonPic.species = 0
MonPic.left = 10
MonPic.top = 3
MonPic._img = nil
MonPic._w = 64
MonPic._h = 64

function MonPic.show(species, x, y)
  species = tonumber(species) or 0
  MonPic.active = true
  MonPic.species = species
  MonPic.left = tonumber(x) or 10
  MonPic.top = tonumber(y) or 3
  MonPic._img = nil
  MonPic._w = 64
  MonPic._h = 64
  local ok, Pokemon = pcall(require, "src.core.game3.pokemon")
  if ok and Pokemon then
    local entry = Pokemon.frontPic and Pokemon.frontPic(species)
    if not entry then
      entry = Pokemon.icon and Pokemon.icon(species)
    end
    if entry and entry.image then
      MonPic._img = entry.image
      MonPic._w = entry.w or 64
      MonPic._h = entry.h or 64
    end
  end
  local okA, Audio = pcall(require, "src.core.game3.audio")
  if okA and Audio and Audio.playCry then
    Audio.playCry(species)
  end
end

function MonPic.hide()
  MonPic.active = false
  MonPic.species = 0
  MonPic._img = nil
end

function MonPic.isActive()
  return MonPic.active
end

function MonPic.draw()
  if not MonPic.active then return end
  local tx = MonPic.left or 10
  local ty = MonPic.top or 3
  -- pokefirered/src/script_menu.c:1193
  Window.stdFrame(Window.template(tx + 1, ty + 1, 8, 8))
  local cx = tx * Display.TILE + 40
  local cy = ty * Display.TILE + 40
  if MonPic._img then
    local iw = MonPic._w or 64
    local ih = MonPic._h or 64
    local scale = math.min(64 / iw, 64 / ih)
    local dw, dh = iw * scale, ih * scale
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(MonPic._img, cx - dw / 2, cy - dh / 2, 0, scale, scale)
  else
    love.graphics.setColor(0.2, 0.25, 0.35, 1)
    love.graphics.rectangle("fill", cx - 28, cy - 28, 56, 56)
    love.graphics.setColor(1, 1, 1, 1)
  end
end

return MonPic
