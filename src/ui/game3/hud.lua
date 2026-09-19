-- Game3 UI controller: input + open helpers.
-- Drawing is owned by display.lua / gfx.lua (FRLG 240×160).

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
local SummaryMenu = require("src.ui.game3.summary_menu")
local ShopMenu = require("src.ui.game3.shop_menu")
local Stack = require("src.ui.game3.stack")

local Hud = {}

local function log(msg)
  print("[game3] " .. tostring(msg))
end

function Hud.isMenuOpen()
  local Naming = package.loaded["src.ui.game3.naming"]
  local EasyChat = package.loaded["src.ui.game3.easy_chat"]
  return Stack.busy()
    or StartMenu.isOpen() or BagMenu.isOpen() or RegionMap.isOpen()
    or PartyMenu.isOpen() or SummaryMenu.isOpen() or Pokedex.isOpen()
    or OptionMenu.isOpen() or SaveMenu.isOpen()
    or TrainerCard.isOpen() or PcMenu.isOpen()
    or ShopMenu.isOpen()
    or (Naming and Naming.isOpen and Naming.isOpen())
    or (EasyChat and EasyChat.isOpen and EasyChat.isOpen())
end

function Hud.busy()
  local Battle = package.loaded["src.core.game3.battle"]
  if Battle and Battle.isActive and Battle.isActive() then return true end
  local Fade = package.loaded["src.ui.game3.fade"]
  return Message.isOpen() or Choice.active or Hud.isMenuOpen()
    or (Fade and Fade.isActive and Fade.isActive())
    or Hud._waitButton ~= nil
end

function Hud.armWaitButton(cb)
  Hud._waitButton = cb
end

function Hud.clearWaitButton()
  Hud._waitButton = nil
end

local function update_top_menu(input)
  local top = Stack.top()
  if top and top.mod then
    if top.mod.handleInput then
      top.mod.handleInput(input)
      return true
    end
  end
  if SaveMenu.isOpen() then
    if input:wasPressed("left") or input:wasPressed("right")
        or input:wasPressed("up") or input:wasPressed("down") then
      SaveMenu.move(1)
    elseif input:wasPressed("a") then SaveMenu.confirm()
    elseif input:wasPressed("b") then SaveMenu.cancel()
    end
    return true
  end
  if OptionMenu.isOpen() then
    OptionMenu.handleInput(input)
    return true
  end
  if TrainerCard.isOpen() then
    if input:wasPressed("b") or input:wasPressed("start") or input:wasPressed("a") then
      TrainerCard.close()
    end
    return true
  end
  if PcMenu.isOpen() then
    if PcMenu.handleInput then
      PcMenu.handleInput(input)
    end
    return true
  end
  if ShopMenu.isOpen() then
    if ShopMenu.handleInput then
      ShopMenu.handleInput(input)
    end
    return true
  end
  if BagMenu.isOpen() then
    if BagMenu.handleInput then
      BagMenu.handleInput(input)
    else
      if input:wasPressed("b") or input:wasPressed("start") then BagMenu.close() end
    end
    return true
  end
  if RegionMap.isOpen() then
    if RegionMap.handleInput then
      RegionMap.handleInput(input)
    else
      if input:wasPressed("b") or input:wasPressed("start") then RegionMap.close() end
    end
    return true
  end
  if SummaryMenu.isOpen() then
    if SummaryMenu.handleInput then
      SummaryMenu.handleInput(input)
    else
      if input:wasPressed("b") or input:wasPressed("start") then SummaryMenu.close() end
    end
    return true
  end
  if PartyMenu.isOpen() then
    if PartyMenu.handleInput then
      PartyMenu.handleInput(input)
    else
      if input:wasPressed("b") or input:wasPressed("start") then PartyMenu.close() end
    end
    return true
  end
  if Pokedex.isOpen() then
    if Pokedex.handleInput then
      Pokedex.handleInput(input)
    else
      if input:wasPressed("b") or input:wasPressed("start") then Pokedex.close() end
    end
    return true
  end
  if StartMenu.isOpen() then
    if input:wasPressed("up") then StartMenu.move(-1)
    elseif input:wasPressed("down") then StartMenu.move(1)
    elseif input:wasPressed("a") then StartMenu.confirm()
    elseif input:wasPressed("b") or input:wasPressed("start") then
      if StartMenu.cancel then StartMenu.cancel() else StartMenu.close() end
    end
    return true
  end
  return false
end

function Hud.update(game, _dt)
  local dt = tonumber(_dt) or (1 / 60)

  -- Active stack modal menu tick
  local top = Stack.top()
  if top and top.mod and top.mod.update then
    pcall(top.mod.update, dt)
  end

  -- Tick location map name popup banner
  local okPop, MapNamePopup = pcall(require, "src.ui.game3.map_name_popup")
  if okPop and MapNamePopup and MapNamePopup.update then
    MapNamePopup.update(dt)
  end

  -- Tick location preview screen (map_preview_screen.c Task_RunMapPreviewScreenForest)
  local okPrev, MapPreviewScreen = pcall(require, "src.ui.game3.map_preview_screen")
  if okPrev and MapPreviewScreen and MapPreviewScreen.update then
    MapPreviewScreen.update(dt)
  end

  local input = game and game.input
  if not input then return end

  local inBattle = false
  local Battle = package.loaded["src.core.game3.battle"]
  if Battle and Battle.isActive and Battle.isActive() then
    inBattle = true
  end

  if inBattle or Message.isOpen() or Stack.busy() then
    if okPop and MapNamePopup and MapNamePopup.dismiss then
      MapNamePopup.dismiss()
    end
    if okPrev and MapPreviewScreen and MapPreviewScreen.dismiss then
      MapPreviewScreen.dismiss()
    end
  end

  -- Active stack modal menu input takes top precedence.
  -- When battle is active, overlays like EvolutionScene or modal stack menus still receive input.
  if Stack.busy() then
    local top = Stack.top()
    if (not inBattle) or (top and (top.id == "evolution_scene" or top.id == "naming" or top.id == "summary_menu")) then
      if update_top_menu(input) then
        return
      end
    end
  end

  -- Choice in field/scripting (in battle, Choice is driven by Battle.update).
  if not inBattle and Choice.active then
    if input:wasPressed("up") then Choice.move(-1, 0)
    elseif input:wasPressed("down") then Choice.move(1, 0)
    elseif input:wasPressed("left") then Choice.move(0, -1)
    elseif input:wasPressed("right") then Choice.move(0, 1)
    elseif input:wasPressed("a") then Choice.confirm()
    elseif input:wasPressed("b") then Choice.cancel()
    end
    return
  end

  if Message.isOpen() then
    local held = input:isDown("a") or input:isDown("b")
    if Message.setSpeedUp then Message.setSpeedUp(held) end
    local aPress = input:wasPressed("a") or input:wasPressed("b")
    if aPress then
      local onLast = Message.isWaiting()
        and Message._page >= #(Message._pages or {})
      if Message._stay and onLast then
        -- Stay on last page: waitbuttonpress / yesnobox own the A press.
        if Hud._waitButton then
          local cb = Hud._waitButton
          Hud._waitButton = nil
          cb()
        end
      else
        Message.advance()
      end
    end
    return
  end

  if Hud._waitButton then
    if input:wasPressed("a") or input:wasPressed("b") then
      local cb = Hud._waitButton
      Hud._waitButton = nil
      cb()
    end
    return
  end

  if inBattle then
    return
  end

  if not Hud.busy() then
    -- START opens pause menu when field is idle (Escape / gamepad Start).
    -- Owned here (not Field) so the open press cannot also close same frame.
    if input:wasPressed("start") then
      local Field = package.loaded["src.core.game3.field"]
      local Space = package.loaded["src.core.game3.scripting.space"]
      local Runtime = package.loaded["src.core.game3.runtime"]
        or require("src.core.game3.runtime")
      local scriptBusy = Space and Space.vm and Space.vm.isRunning and Space.vm:isRunning()
      local locked = Field and Field.locked
      if not locked and not scriptBusy then
        Hud.openStartMenu(game, (Field and Field._session)
          or (Runtime.getSession and Runtime.getSession()))
      end
    end
    return
  end

  if SummaryMenu.isOpen() and SummaryMenu.update then
    SummaryMenu.update(_dt or (1 / 60))
  end
  if PartyMenu.isOpen() and PartyMenu.update then
    PartyMenu.update(_dt or (1 / 60))
  end

  update_top_menu(input)
end

function Hud.openStartMenu(game, session)
  if StartMenu.isOpen() then
    log("Start Menu close (toggle)")
    StartMenu.close()
    return
  end
  -- Close other field menus first.
  if BagMenu.isOpen() then BagMenu.close() end
  if SummaryMenu.isOpen() then SummaryMenu.close() end
  if PartyMenu.isOpen() then PartyMenu.close() end
  if Pokedex.isOpen() then Pokedex.close() end
  if RegionMap.isOpen() then RegionMap.close() end
  if OptionMenu.isOpen() then OptionMenu.close() end
  if SaveMenu.isOpen() then SaveMenu.close() end
  if TrainerCard.isOpen() then TrainerCard.close() end
  if PcMenu.isOpen() then PcMenu.close() end
  -- pret FlagSet(FLAG_OPENED_START_MENU) on first open (Pallet sign lady).
  do
    local Space = package.loaded["src.core.game3.scripting.space"]
    local Flags = package.loaded["src.core.game3.scripting.flags"]
      or require("src.core.game3.scripting.flags")
    local store = Space and Space.store
    if store and Flags.IDS and Flags.IDS.OPENED_START_MENU then
      local scene = Flags.getVar(store, nil, 0x4070)
      if scene >= 1 then
        Flags.setFlag(store, nil, Flags.IDS.OPENED_START_MENU, true)
        if Space.persistSession then
          pcall(Space.persistSession)
        end
      end
    end
  end
  log("Start Menu on game3 display (FRLG 240x160)")
  StartMenu.show({ session = session, game = game })
end

function Hud.openMessage(game, text, opts)
  log("dialog on game3 display")
  Message.show(text, opts)
end

function Hud.openMessageStay(game, text, opts)
  opts = opts or {}
  opts.stay = true
  log("stay-dialog on game3 display")
  Message.showStay(text, opts)
end

function Hud.openPc(game, session)
  PcMenu.show({ session = session or (require("src.core.game3.runtime").getSession()) })
end

function Hud.ensure(_game, _mode)
  return Hud
end

function Hud.new()
  return Hud
end

return Hud
