-- The START menu (engine/menus/start_menu.asm): entries appear as they
-- become usable -- POKéDEX once Oak gives it, POKéMON once you have any,
-- SAVE with a confirmation, plus ITEM / OPTION / LINK / QUIT.  The built
-- item list runs through the ui.start_menu.items hook before the menu
-- opens, so mods insert or remove rows without patching this file.

local Font = require("src.render.Font")
local Logger = require("src.core.Logger")
local Menu = require("src.ui.Menu")
local Renderer = require("src.render.Renderer")
local Runtime = require("src.mods.Runtime")
local Screens = require("src.ui.Screens")
local SecondScreen = require("src.render.SecondScreen")
local Strings = require("src.core.Strings")

local StartMenu = {}

local function sameItems(_, items) return items end

function StartMenu.new(game)
  local flags = game.save.flags or {}
  local items = {}

  -- vanilla start submenus return here on B (RedisplayStartMenu): the
  -- generic Menu pops the start menu when a row is selected, so each
  -- submenu gets an onCancel that re-opens it
  local function reopen() Screens.push(game, "StartMenu") end

  -- POKéDEX: only after Oak hands it over
  if flags.EVENT_GOT_POKEDEX then
    table.insert(items, { label = Strings("POKéDEX"), onSelect = function()
      Screens.push(game, "PokedexMenu", { onCancel = reopen })
    end })
  end

  -- POKéMON is always listed (draw_start_menu.asm prints it even with
  -- an empty party; selecting it then just no-ops)
  table.insert(items, { label = Strings("POKéMON"), onSelect = function()
    if #game.save.party == 0 then return end
    Screens.push(game, "PartyMenu", { onCancel = reopen })
  end })

  table.insert(items, { label = Strings("ITEM"), onSelect = function()
    Screens.push(game, "BagMenu", { onCancel = reopen })
  end })

  -- the player's name opens the trainer card (StartMenu_TrainerInfo)
  table.insert(items, { label = game.save.player.name or "RED",
    onSelect = function()
      Screens.push(game, "TrainerCard", { onCancel = reopen })
    end })

  -- SAVE shows the player/badges/dex/time panel then asks to confirm
  -- (PrintSaveScreenText)
  table.insert(items, { label = Strings("SAVE"), onSelect = function()
    local TextBox = require("src.render.TextBox")
    local ChoiceBox = require("src.ui.ChoiceBox")
    local badges = require("src.inventory.Badges").count(game.data, game.save)
    local owned = 0
    for _ in pairs(game.save.pokedex and game.save.pokedex.owned or {}) do
      owned = owned + 1
    end
    local t = math.floor(game.save.playTime or 0)
    local panel = Strings("PLAYER %s\nBADGES    %d\nPOKéDEX %3d\nTIME %6d:%02d",
                          game.save.player.name or "RED", badges, owned,
                          math.floor(t / 3600), math.floor(t / 60) % 60)
    game.stack:push(TextBox.new(game,
      panel .. Strings("\fWould you like to\nSAVE the game?"), function()
      game.stack:push(ChoiceBox.new(game, function(yes)
        if not yes then return end
        -- "Now saving..." beat before the write (save.asm
        -- NowSavingString), then GameSavedText + SFX_SAVE
        game.stack:push(TextBox.new(game, Strings("Now saving..."), function()
          game:writeSave()
          require("src.core.Sound").play(game.data, "Save")
          game.stack:push(TextBox.new(game,
            Strings("%s saved\nthe game!", game.save.player.name or "RED")))
        end))
      end))
    end))
  end })

  table.insert(items, { label = Strings("OPTION"), onSelect = function()
    Screens.push(game, "OptionsMenu", { onCancel = reopen })
  end })

  -- LINK needs a party
  if #game.save.party > 0 then
    table.insert(items, { label = Strings("LINK"), onSelect = function()
      local LinkState = require("src.link.LinkState")
      game.stack:push(LinkState.new(game))
    end })
  end

  -- the manager's pause-menu entry (18-mod-manager-ux): gated on at least
  -- one discovered mod so a vanilla install's menu is unchanged
  local status = game.modStatus
  if status and #(status.available or {}) > 0 then
    table.insert(items, { label = Strings("MODS"), onSelect = function()
      Screens.push(game, "ManagerState")
    end })
  end

  -- the original's EXIT just closed the menu (CloseStartMenu); with a
  -- window close button covering that, QUIT instead power-cycles back
  -- to the title after a confirm (defaultNo guards accidental quits)
  table.insert(items, { label = Strings("QUIT"), onSelect = function()
    local TextBox = require("src.render.TextBox")
    local ChoiceBox = require("src.ui.ChoiceBox")
    game.stack:push(TextBox.new(game, Strings("RETURN TO MAIN\nMENU?"), function()
      game.stack:push(ChoiceBox.new(game, function(yes)
        if yes then game:returnToTitle() end
      end, { defaultNo = true }))
    end))
  end })

  local hooked = Runtime.call("ui.start_menu.items", sameItems, game, items)
  if type(hooked) == "table" then
    items = hooked
  else
    Logger.error("ui.start_menu.items returned %s; keeping the vanilla items",
                 type(hooked))
  end

  -- the start menu's mask is PAD_DOWN | PAD_UP | PAD_START | PAD_B | PAD_A
  -- (engine/menus/draw_start_menu.asm), so START closes it back to the
  -- overworld -- unlike most menus, whose masks omit PAD_START.
  --
  -- item count isn't fixed: POKéDEX/LINK/MODS come and go with save state,
  -- and mods can append their own rows through the hook above, so the
  -- double-spaced box (the original's style) can grow past the 18-tile
  -- canvas. Cap it at however many rows actually fit and scroll the rest,
  -- with Menu's moreArrow showing while there's more below.
  local rowStep = 2
  local maxVisible = math.floor((Renderer.HEIGHT / 8 - 2) / rowStep)
  local menu = Menu.new(game, items,
    { tx = 9, ty = 0, tw = 11, maxVisible = maxVisible, startCloses = true })
  -- the cursor position survives closing the menu
  -- (wBattleAndStartSavedMenuItem, home/start_menu.asm)
  menu.index = math.min(game.save.startMenuIndex or 1, #items)
  menu:clampScroll()
  local baseUpdate = menu.update
  menu.update = function(self, dt)
    baseUpdate(self, dt)
    game.save.startMenuIndex = self.index
  end

  -- inside the Safari Zone the start menu also shows remaining steps and
  -- SAFARI BALLs (PrintSafariZoneSteps): a 9x5 border at the top-left with
  -- "steps/500" and "BALL xx"
  if game.save.safari then
    local baseDraw = menu.draw
    menu.draw = function(self)
      baseDraw(self)
      local safari = game.save.safari
      Font.drawBox(0, 0, 9, 5)
      love.graphics.setColor(0, 0, 0, 1)
      Font.draw(("%3d"):format(math.floor(safari.steps or 0)), 8, 8)
      Font.draw("/500", 32, 8)
      Font.draw(Strings("BALL"), 8, 24)
      Font.draw(("%2d"):format(math.floor(safari.balls or 0)), 48, 24)
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  -- AYN Thor second screen: this is the pause menu, so once a second
  -- screen exists its content lives there instead -- a persistent left
  -- column (src/render/OverworldSecondScreen.lua), which frees the main
  -- screen to keep showing the map uninterrupted while paused, the same
  -- move BattleState's menus already made for battle. drawColumn keeps
  -- the real draw logic (box/items/cursor, including the safari overlay
  -- above) available for the coordinator to call against the
  -- second-screen canvas; draw() itself becomes a no-op on the main
  -- screen once a second screen is present, and falls back to the
  -- classic on-screen menu exactly as before everywhere else.
  menu.drawColumn = menu.draw
  menu.draw = function(self)
    if SecondScreen.available() then return end
    self:drawColumn()
  end
  return menu
end

return StartMenu
