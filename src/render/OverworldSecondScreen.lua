-- Composes the AYN Thor's second screen for the overworld: the pause menu
-- (src/ui/StartMenu.lua) as a persistent left column, full height, plus a
-- toggleable main panel to its right -- party status
-- (src/render/PartyStatusHUD.lua) or the region map
-- (src/render/TownMapPanel.lua), switched by tapping the tab strip above
-- it. The menu column shows an inert preview while walking around and
-- swaps to the live, input-driven instance the moment the player pauses
-- -- "focus" is exactly which instance this draws each tick, not a
-- separate flag to track and keep in sync.
local SecondScreen = require("src.render.SecondScreen")
local SecondScreenInput = require("src.render.SecondScreenInput")
local PartyStatusHUD = require("src.render.PartyStatusHUD")
local TownMapPanel = require("src.render.TownMapPanel")
local StartMenu = require("src.ui.StartMenu")
local Font = require("src.render.Font")
local Theme = require("src.ui.Theme")

local OverworldSecondScreen = {}

local PUSH_EVERY_N_FRAMES = 4 -- snappier than PartyStatusHUD alone: the
                               -- menu column wants to feel responsive
                               -- once focused
local TAB_TILES_H = 3 -- Font.drawBox needs >= 3 rows for one usable
                       -- content row between its top/bottom border --
                       -- the same height TownMap's own name banner uses
local TAB_H = TAB_TILES_H * 8

-- Both panels share one footprint (TownMapPanel.WIDTH/HEIGHT mirror
-- PartyStatusHUD's) so switching tabs never resizes the canvas.
local PANEL_W, PANEL_H = PartyStatusHUD.WIDTH, PartyStatusHUD.HEIGHT

local PANELS = { pokemon = PartyStatusHUD, map = TownMapPanel }

local frame = 0
local mode = "pokemon" -- "pokemon" | "map" -- in-memory only, resets on relaunch

local function findFocusedMenu(stack)
  for i = 1, #(stack and stack.states or {}) do
    local state = stack.states[i]
    if state and state.screenId == "StartMenu" then return state end
  end
  return nil
end

-- Same ownership check PartyStatusHUD used when it owned its own
-- begin/finish -- kept here now that this coordinator does instead.
local function secondScreenClaimedByStack(stack)
  for i = 1, #(stack and stack.states or {}) do
    local state = stack.states[i]
    if state and state.usesSecondScreenText and state:usesSecondScreenText() then
      return true
    end
  end
  return false
end

local function drawTabs()
  Font.drawBox(0, 0, PANEL_W / 8, TAB_TILES_H)
  love.graphics.setColor(0, 0, 0, 1)
  local halfW = PANEL_W / 2
  local pkmnLabel, mapLabel = "PKMN", "MAP"
  local pkmnX = halfW / 2 - (#pkmnLabel * 8) / 2
  local mapX = halfW + halfW / 2 - (#mapLabel * 8) / 2
  Font.draw(pkmnLabel, pkmnX, 8)
  Font.draw(mapLabel, mapX, 8)
  Font.drawCode(Theme.cursor, (mode == "pokemon" and pkmnX or mapX) - 8, 8)
  love.graphics.setColor(1, 1, 1, 1)
end

-- A completed tap landing on the tab strip (colW..colW+PANEL_W,
-- 0..TAB_H) switches mode; anything else -- including a tap on the
-- panel content below -- is ignored here, since neither panel currently
-- reads touch input of its own.
local function pollTabTap(colW)
  local tapX, tapY = SecondScreenInput.poll()
  if not tapX then return end
  local localX, localY = tapX - colW, tapY
  if localY < 0 or localY >= TAB_H or localX < 0 or localX >= PANEL_W then
    return
  end
  mode = (localX < PANEL_W / 2) and "pokemon" or "map"
end

function OverworldSecondScreen.draw(game)
  if not SecondScreen.available() then return end
  if secondScreenClaimedByStack(game.stack) then return end

  frame = frame + 1
  if frame % PUSH_EVERY_N_FRAMES ~= 0 then return end

  local focused = findFocusedMenu(game.stack)
  local menu = focused
  if not menu then
    -- Rebuilt every throttled tick rather than cached: cheap table
    -- construction, and it keeps the preview honest about newly
    -- unlocked entries (POKéDEX, LINK) without needing to invalidate a
    -- stale cached copy itself.
    local ok, fresh = pcall(StartMenu.new, game)
    if not ok or not fresh then return end
    menu = fresh
  end
  if not menu.drawColumn then return end

  local colW = (menu.tw + 2) * 8 -- box width plus a small margin
  pollTabTap(colW)

  SecondScreen.begin(colW + PANEL_W, TAB_H + PANEL_H)

  local savedTx, savedTy = menu.tx, menu.ty
  menu.tx, menu.ty = 0, 0
  menu:drawColumn()
  menu.tx, menu.ty = savedTx, savedTy

  love.graphics.translate(colW, 0)
  drawTabs()
  love.graphics.translate(0, TAB_H)
  ;(PANELS[mode] or PartyStatusHUD).drawRows(game)

  SecondScreen.finish()
end

return OverworldSecondScreen
