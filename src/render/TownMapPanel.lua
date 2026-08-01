-- Region-map alternative to src/render/PartyStatusHUD.lua's party panel,
-- selected by OverworldSecondScreen.lua's tab strip. Same bordered-panel
-- footprint (WIDTH/HEIGHT match PartyStatusHUD's exactly) so switching
-- tabs never resizes the second-screen canvas.
local Font = require("src.render.Font")
local PartyStatusHUD = require("src.render.PartyStatusHUD")
local TownMap = require("src.ui.TownMap")

local TownMapPanel = {}

TownMapPanel.WIDTH = PartyStatusHUD.WIDTH
TownMapPanel.HEIGHT = PartyStatusHUD.HEIGHT

local BORDER = 8

function TownMapPanel.drawRows(game)
  Font.drawBox(0, 0, TownMapPanel.WIDTH / 8, TownMapPanel.HEIGHT / 8)
  love.graphics.push()
  love.graphics.translate(BORDER, BORDER)

  -- Fresh instance every call (the caller already throttles how often
  -- this runs): keeps the "you are here" marker honest about the
  -- player's current map without needing to invalidate a stale cached
  -- one. TownMap.new has no side effects until :update()/:draw() runs --
  -- safe to build without pushing it onto game.stack, same as the
  -- pause-menu idle preview in OverworldSecondScreen.lua. self.sel
  -- already defaults to the player's own location (TownMap.new), and a
  -- freshly-built self.blink is 0, so the marker/cursor this draws
  -- default to visible with no blink-off flicker on a panel nobody is
  -- reading frame-by-frame.
  local ok, map = pcall(TownMap.new, game, {})
  if ok and map then
    pcall(map.draw, map)
  end

  love.graphics.pop()
end

return TownMapPanel
