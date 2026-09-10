
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

-- engine/battle/core.asm:4490
WideBattle.TOP_HUD = { x = 0, y = 0, w = 96, h = 32 }
-- engine/battle/core.asm:4352
WideBattle.BOTTOM = { x = 0, y = 56, w = 304, h = 88 }
function WideBattle.drawField(battle)
  local G = love.graphics
  Chrome.paletteFill(0, 0, WideBattle.WIDTH, WideBattle.HEIGHT)
  if not battle:hasBattleSides() then
    Chrome.printThrough(Strings("NO BATTLE"), 1, 1, Chrome.DEFAULT_BOX_PALETTE)
    return false
  end
  G.push()
  G.translate(WideBattle.FIELD_X, 0)
  battle:drawSceneBody(function()
    Chrome.clear()
    battle:drawPics()
  end)
  G.pop()
  return true
end

function WideBattle.drawTopHud(battle)
  -- engine/battle/core.asm:4730
  battle:drawEnemyHud()
end

function WideBattle.drawBottomHud(battle)
  local G = love.graphics
  -- engine/battle/core.asm:4592
  G.push()
  G.translate(WideBattle.EXTRA_TILES * 8, 0)
  battle:drawPlayerHud()
  G.pop()
  battle:drawBottom(WideBattle.EXTRA_TILES)
end

function WideBattle.drawSurface(battle)
  if not WideBattle.drawField(battle) then return end
  WideBattle.drawTopHud(battle)
  WideBattle.drawBottomHud(battle)
end

local function battleIsTopState(battle)
  local stack = battle.game and battle.game.stack
  return not (stack and stack.top) or stack:top() == battle
end

WideBattle.battleIsTopState = battleIsTopState

-- engine/battle/core.asm:7060
function WideBattle.docked(battle)
  return battle.extendedHUD ~= nil and battle:extendedHUD() == true
    and battleIsTopState(battle) and battle.phase ~= "stats-box"
end

local function group(dx, dy, rect, fn)
  local G = love.graphics
  G.push("all")
  G.translate(dx, dy)
  Chrome.clipTo(rect.x, rect.y, rect.w, rect.h)
  fn()
  G.pop()
end

function WideBattle.dockOffsets(scale, oy, py, ph)
  return math.ceil((py - oy) / scale),
    math.floor((py + ph - WideBattle.HEIGHT * scale - oy) / scale)
end

function WideBattle.drawDocked(battle, scale, oy, py, ph)
  local topY, bottomY = WideBattle.dockOffsets(scale, oy, py, ph)
  local surface = { x = 0, y = 0, w = WideBattle.WIDTH, h = WideBattle.HEIGHT }
  local sides = false
  group(0, 0, surface, function() sides = WideBattle.drawField(battle) end)
  if not sides then return end
  group(0, topY, WideBattle.TOP_HUD, function()
    WideBattle.drawTopHud(battle)
  end)
  group(0, bottomY, WideBattle.BOTTOM, function()
    WideBattle.drawBottomHud(battle)
  end)
end

function WideBattle.draw(battle, winW, winH)
  local G = love.graphics
  Chrome.letterbox(winW, winH, 1, 1, 1)
  local scale = battle:battlePanelScale(winW, winH)
  local ox, oy = Chrome.fitOriginFor(winW, winH, scale, WideBattle.TILES_W,
    WideBattle.TILES_H)
  if not WideBattle.docked(battle) then
    G.push("all")
    Chrome.clipTo(ox, oy, WideBattle.WIDTH * scale, WideBattle.HEIGHT * scale)
    G.translate(ox, oy)
    G.scale(scale, scale)
    battle:drawScene(function() WideBattle.drawSurface(battle) end)
    G.pop()
    return
  end
  local _, py, _, ph = Chrome.playfieldRect(winW, winH)
  Chrome.paletteFill(ox, py, WideBattle.WIDTH * scale, ph)
  G.push("all")
  G.translate(ox, oy)
  G.scale(scale, scale)
  battle:drawScene(function()
    WideBattle.drawDocked(battle, scale, oy, py, ph)
  end)
  G.pop()
end

return WideBattle
