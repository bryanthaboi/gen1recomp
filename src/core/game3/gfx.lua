-- Game3 drawing primitives on the FRLG 240×160 canvas.
-- Tile grid: 30×20 cells of 8px. Dialog/menu chrome from pret text_window tiles.
-- All menu text uses FrlgFont (latin_normal) — never Gen2 Font.

local Display = require("src.core.game3.display")
local Chrome = require("src.ui.game3.chrome")
local Window = require("src.ui.game3.window")
local FrlgFont = require("src.ui.game3.frlg_font")
local Stack = require("src.ui.game3.stack")

local Gfx = {}

local function setRgb(r, g, b, a)
  love.graphics.setColor(r, g, b, a or 1)
end

function Gfx.fill(px, py, pw, ph, r, g, b, a)
  setRgb(r, g, b, a)
  love.graphics.rectangle("fill", px, py, pw, ph)
end

function Gfx.rect(px, py, pw, ph, r, g, b, a)
  setRgb(r, g, b, a)
  love.graphics.rectangle("line", px, py, pw, ph)
end

function Gfx.window(tx, ty, tw, th)
  Chrome.stdFrame(tx, ty, tw, th)
end

function Gfx.dialogueWindow()
  Chrome.dialogueFrame()
end

function Gfx.signWindow()
  Chrome.signFrame()
end

function Gfx.print(text, tx, ty, r, g, b)
  local colors = FrlgFont.COLOR.NORMAL
  if r then
    colors = { fg = { r, g or r, b or r, 1 }, shadow = FrlgFont.COLOR.NORMAL.shadow }
  end
  Window.print(text, tx, ty, { colors = colors })
end

function Gfx.printPx(text, px, py, r, g, b)
  local colors = FrlgFont.COLOR.NORMAL
  if r then
    colors = { fg = { r, g or r, b or r, 1 }, shadow = FrlgFont.COLOR.NORMAL.shadow }
  end
  Window.printPx(text, px, py, { colors = colors })
end

function Gfx.cursor(tx, ty)
  Window.cursor(tx, ty)
end

function Gfx.clearUiBand()
end

local function tryDraw(mod)
  if mod and mod.draw then
    pcall(mod.draw)
  end
end

--- Draw all active game3 UI widgets onto the current Display canvas.
function Gfx.drawUi()
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local StartMenu = require("src.ui.game3.start_menu")
  local BagMenu = require("src.ui.game3.bag_menu")
  local RegionMap = require("src.ui.game3.region_map")
  local PartyMenu = require("src.ui.game3.party_menu")
  local Pokedex = require("src.ui.game3.pokedex")
  local OptionMenu = require("src.ui.game3.option_menu")
  local SaveMenu = require("src.ui.game3.save_menu")
  local TrainerCard = require("src.ui.game3.trainer_card")
  local PcMenu = require("src.ui.game3.pc_menu")
  local MoneyBox = require("src.ui.game3.money_box")

  -- Stack-driven full-screen menus (bottom → top).
  local order = Stack.drawOrder()
  if #order > 0 then
    for _, layer in ipairs(order) do
      tryDraw(layer.mod)
    end
  else
    -- Legacy open flags if stack not used yet.
    if StartMenu.isOpen() then tryDraw(StartMenu) end
    if BagMenu.isOpen() then tryDraw(BagMenu) end
    if RegionMap.isOpen() then tryDraw(RegionMap) end
    if PartyMenu.isOpen() then tryDraw(PartyMenu) end
    if Pokedex.isOpen() then tryDraw(Pokedex) end
    if OptionMenu.isOpen() then tryDraw(OptionMenu) end
    if SaveMenu.isOpen() then tryDraw(SaveMenu) end
    if TrainerCard.isOpen() then tryDraw(TrainerCard) end
    if PcMenu.isOpen() then tryDraw(PcMenu) end
  end

  -- Field moneybox sits above the map but under dialogue when script-owned.
  if MoneyBox.isVisible and MoneyBox.isVisible() then
    local ShopMenu = package.loaded["src.ui.game3.shop_menu"]
    if not (ShopMenu and ShopMenu.isOpen and ShopMenu.isOpen()) then
      tryDraw(MoneyBox)
    end
  end

  -- Location change overlay / signpost popup banner (pokefirered/src/map_name_popup.c)
  -- A running FOREST preview screen owns BG0, so it replaces the popup entirely.
  local okPrev, MapPreviewScreen = pcall(require, "src.ui.game3.map_preview_screen")
  local previewActive = okPrev and MapPreviewScreen and MapPreviewScreen.isActive
    and MapPreviewScreen.isActive()
  if previewActive then
    local top = Stack.top()
    local suppress = top and top.hideBelow
    if not suppress and not Message.isOpen() then
      tryDraw(MapPreviewScreen)
    else
      previewActive = false
    end
  end

  local okPop, MapNamePopup = pcall(require, "src.ui.game3.map_name_popup")
  if okPop and MapNamePopup and MapNamePopup.isActive and MapNamePopup.isActive()
      and not previewActive then
    local top = Stack.top()
    local suppress = top and top.hideBelow
    if not suppress and not Message.isOpen() then
      tryDraw(MapNamePopup)
    end
  end

  -- Script mon pic (showmonpic) under dialogue / yes-no.
  local okPic, MonPic = pcall(require, "src.ui.game3.mon_pic")
  if okPic and MonPic and MonPic.active then
    tryDraw(MonPic)
  end

  -- Dialog then choice on top (yesnobox overlays stayed message).
  local top = Stack.top()
  local suppressOverworldDialog = top and top.hideBelow

  if Message.isOpen() and not suppressOverworldDialog and not Stack.has("box_storage") and not Stack.has("pc_menu") then
    Message.draw()
  end

  if Choice.active and Choice.options and not suppressOverworldDialog then
    tryDraw(Choice)
  end

  local okN, Naming = pcall(require, "src.ui.game3.naming")
  if okN and Naming.isOpen and Naming.isOpen() then
    tryDraw(Naming)
  end

  local okTr, BattleTransition = pcall(require, "src.core.game3.battle_transition")
  if okTr and BattleTransition and BattleTransition.draw then
    BattleTransition.draw()
  end

  local okF, Fade = pcall(require, "src.ui.game3.fade")
  local isNamingOpen = okN and Naming.isOpen and Naming.isOpen()
  local okR, RegionMap = pcall(require, "src.ui.game3.region_map")
  local isRegionMapOpen = okR and RegionMap.isOpen and RegionMap.isOpen()
  if okF and Fade.draw and not isNamingOpen and not isRegionMapOpen then
    Fade.draw()
  end

  setRgb(1, 1, 1, 1)
end

-- Export Window geometry helpers used by menus / tests.
Gfx.Window = Window
Gfx.START_LEFT = 22 -- pret AddWindowParameterized tilemapLeft
Gfx.START_TOP = 1
Gfx.START_WIDTH = 7

return Gfx
