
local Chrome = require("src.ui.gen2.Chrome")
local Strings = require("src.core.Strings")

local WideBattle = {
  WIDTH = 304,
  HEIGHT = 144,
  TILES_W = 38,
  TILES_H = 18,
  FIELD_X = 72,
  EXTRA_TILES = 18,
}

function WideBattle.fillScale(winW, winH)
  local w, h = winW or 0, winH or 0
  local ok, Playfield = pcall(require, "src.render.Playfield")
  if ok and Playfield.rect then
    local okv, _, _, pw, ph = pcall(Playfield.rect, winW, winH)
    if okv and pw and pw >= 1 and ph and ph >= 1 then
      w, h = pw, ph
    end
  end
  return math.max(1, math.min(w / WideBattle.WIDTH, h / WideBattle.HEIGHT))
end

function WideBattle.drawSurface(battle)
  local G = love.graphics
  Chrome.paletteFill(0, 0, WideBattle.WIDTH, WideBattle.HEIGHT)
  if not battle:hasBattleSides() then
    Chrome.printThrough(Strings("NO BATTLE"), 1, 1, Chrome.DEFAULT_BOX_PALETTE)
    return
  end
  G.push()
  G.translate(WideBattle.FIELD_X, 0)
  battle:drawSceneBody(function()
    Chrome.clear()
    battle:drawPics()
  end)
  G.pop()
  -- engine/battle/core.asm:4730
  battle:drawEnemyHud()
  -- engine/battle/core.asm:4592
  G.push()
  G.translate(WideBattle.EXTRA_TILES * 8, 0)
  battle:drawPlayerHud()
  G.pop()
  battle:drawBottom(WideBattle.EXTRA_TILES)
end

function WideBattle.draw(battle, winW, winH)
  local G = love.graphics
  Chrome.letterbox(winW, winH, 1, 1, 1)
  local scale = battle:battlePanelScale(winW, winH)
  local ox, oy = Chrome.fitOriginFor(winW, winH, scale, WideBattle.TILES_W,
    WideBattle.TILES_H)
  G.push("all")
  Chrome.clipTo(ox, oy, WideBattle.WIDTH * scale, WideBattle.HEIGHT * scale)
  G.translate(ox, oy)
  G.scale(scale, scale)
  battle:drawScene(function() WideBattle.drawSurface(battle) end)
  G.pop()
end

return WideBattle
