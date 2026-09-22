local Stack = require("src.ui.game3.stack")

local UiPass = {}

local function setRgb(r, g, b, a)
  love.graphics.setColor(r, g, b, a or 1)
end

local gfxDrawWarned = {}
local function tryDraw(mod)
  if mod and mod.draw then
    local ok, err = pcall(mod.draw)
    if not ok and not gfxDrawWarned[tostring(mod)] then
      gfxDrawWarned[tostring(mod)] = true
      print("[game3/gfx] mod draw failed: " .. tostring(err))
    end
  end
end

function UiPass.drawUi()
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
  local CoinsBox = require("src.ui.game3.coins_box")
  local ElevatorWindow = require("src.ui.game3.elevator_window")

  local order = Stack.drawOrder()
  if #order > 0 then
    for _, layer in ipairs(order) do
      tryDraw(layer.mod)
    end
  else
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

  if MoneyBox.isVisible and MoneyBox.isVisible() then
    local ShopMenu = package.loaded["src.ui.game3.shop_menu"]
    if not (ShopMenu and ShopMenu.isOpen and ShopMenu.isOpen()) then
      tryDraw(MoneyBox)
    end
  end

  -- pokefirered/src/coins.c:79
  if CoinsBox.isVisible and CoinsBox.isVisible() then
    tryDraw(CoinsBox)
  end

  -- pokefirered/src/field_specials.c:1094
  if ElevatorWindow.isVisible and ElevatorWindow.isVisible() then
    tryDraw(ElevatorWindow)
  end

  -- pokefirered/src/map_name_popup.c
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

  local okPic, MonPic = pcall(require, "src.ui.game3.mon_pic")
  if okPic and MonPic and MonPic.active then
    tryDraw(MonPic)
  end

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
  local okEC, EasyChat = pcall(require, "src.ui.game3.easy_chat")
  local isEasyChatOpen = okEC and EasyChat.isOpen and EasyChat.isOpen()
  if okF and Fade.draw and not isNamingOpen and not isRegionMapOpen and not isEasyChatOpen then
    Fade.draw()
  end

  setRgb(1, 1, 1, 1)
end


return UiPass
