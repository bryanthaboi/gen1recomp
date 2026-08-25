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
local Strings = require("src.core.Strings")
local Theme = require("src.ui.Theme")

local StartMenu = {}

local function sameItems(_, items) return items end

function StartMenu.new(game)
  local flags = game.save.flags or {}
  local items = {}
  local menu

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
  table.insert(items, { label = Strings("POKéMON"),
    keepOpen = #game.save.party == 0, onSelect = function()
    if #game.save.party == 0 then return end
    Screens.push(game, "PartyMenu", { onCancel = reopen })
  end })

  -- StartMenu_Item draws LIST_MENU_BOX over the still-drawn START menu and
  -- only redisplays it on the way out (start_sub_menus.asm:302-329) #1745
  table.insert(items, { label = Strings("ITEM"), keepOpen = true,
    onSelect = function()
      Screens.push(game, "BagMenu", { onClose = function()
        if menu and game.stack:top() == menu then game.stack:pop() end
      end })
    end })

  -- the player's name opens the trainer card (StartMenu_TrainerInfo)
  table.insert(items, { label = game.save.player.name or "RED",
    onSelect = function()
      Screens.push(game, "TrainerCard", { onCancel = reopen })
    end })

  -- SAVE shows the player/badges/dex/time panel then asks to confirm
  -- (PrintSaveScreenText); StartMenu_SaveReset never clears the START menu
  -- box, so it stays on screen beside the panel (start_sub_menus.asm:641-647)
  table.insert(items, { label = Strings("SAVE"), keepOpen = true,
    onSelect = function()
    local TextBox = require("src.render.TextBox")
    local badges = require("src.inventory.Badges").count(game.data, game.save)
    local owned = 0
    for _ in pairs(game.save.pokedex and game.save.pokedex.owned or {}) do
      owned = owned + 1
    end
    -- the panel is a static snapshot; the cart prints it once
    -- (main_menu.asm:390-401)
    local t = math.floor(game.save.playTime or 0)
    -- PrintSaveScreenText draws its own border at hlcoord 4,0 (b=8, c=$e) and
    -- leaves it up under the prompt -- engine/menus/main_menu.asm:381-405
    local panel
    panel = {
      -- the panel overlaps the kept-open START menu box (start_sub_menus.asm:
      -- 641-647), so neither can be docked to a screen edge on its own
      holdsUIAnchors = true,
      delay = 0,
      update = function()
        -- ld c, 30 / jp DelayFrames: the bare panel holds before the
        -- prompt (main_menu.asm:404-405)
        panel.delay = panel.delay + 1
        if panel.delay == 30 then panel.openPrompt() end
      end,
      draw = function()
        Font.drawBox(4, 0, 16, 10)
        love.graphics.setColor(0, 0, 0, 1)
        Font.draw(Strings("PLAYER"), 5 * 8, 2 * 8)
        Font.draw(game.save.player.name or "RED", 12 * 8, 2 * 8)
        Font.draw(Strings("BADGES"), 5 * 8, 4 * 8)
        Font.draw(("%2d"):format(badges), 17 * 8, 4 * 8)
        Font.draw(Strings("POKéDEX"), 5 * 8, 6 * 8)
        Font.draw(("%3d"):format(owned), 16 * 8, 6 * 8)
        Font.draw(Strings("TIME"), 5 * 8, 8 * 8)
        Font.draw(("%3d:%02d"):format(math.floor(t / 3600),
                                      math.floor(t / 60) % 60), 13 * 8, 8 * 8)
        love.graphics.setColor(1, 1, 1, 1)
      end,
    }
    local function closePanel()
      if game.stack:top() == panel then game.stack:pop() end
      -- SaveMenu returns into HoldTextDisplayOpen, not RedisplayStartMenu
      -- (start_sub_menus.asm:645-647): the kept-open START menu goes too
      if menu and game.stack:top() == menu then game.stack:pop() end
    end
    panel.openPrompt = function()
      game.stack:push(TextBox.new(game,
        Strings("Would you like to\nSAVE the game?"), nil, {
        -- SaveTheGame_YesOrNo pins its TWO_OPTION_MENU at hlcoord 0, 7 rather
        -- than the shared right-hand one -- engine/menus/save.asm:186-192
        choiceBox = Theme.saveBox,
        choice = function(yes)
          if not yes then closePanel() return end
          -- SaveMenu .save (engine/menus/save.asm:164-181): "Now saving..."
          -- is a bare PlaceString held by DelayFrames 120, then GameSavedText,
          -- which ends in `done` and so never reaches TX_PROMPT_BUTTON.
          -- Neither page takes a button press (#765); the second waits on
          -- SFX_SAVE (PlaySoundWaitForCurrent + WaitForSoundToFinish) and then
          -- DelayFrames 30.  The write itself is invisible either side of the
          -- "Now saving..." hold, so it stays on that box's onDone.
          game.stack:push(TextBox.new(game, Strings("Now saving..."), function()
            game:writeSave()
            game.stack:push(TextBox.new(game,
              Strings("%s saved\nthe game!", game.save.player.name or "RED"),
              closePanel, { auto = {
                sound = function()
                  return require("src.core.Sound").play(game.data, "Save")
                end,
                delay = 30,
              } }))
          end, { auto = { delay = 120 } }))
        end,
      }))
    end
    game.stack:push(panel)
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
    game.stack:push(TextBox.new(game, Strings("RETURN TO MAIN\nMENU?"), nil, {
      defaultNo = true,
      choice = function(yes)
        if yes then game:returnToTitle() end
      end,
    }))
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
  menu = Menu.new(game, items,
    -- the START menu hugs the top-right corner of the SCREEN, not of a
    -- centred letterbox: at 9,0 x 11 it is already flush with the top and
    -- right of the 20x18 grid, so the anchor keeps it flush when the view
    -- is zoomed out and the letterbox no longer fills the window
    { tx = 9, ty = 0, tw = 11, maxVisible = maxVisible, startCloses = true,
      anchor = "topright" })
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
  -- SAFARI BALLs (PrintSafariZoneSteps, engine/overworld/player_state.asm:
  -- 219-224): a 9x5 border at the top-left with "steps/500" and "BALL xx".
  -- It opens with `cp SAFARI_ZONE_EAST / ret c`, so only the nine interior
  -- maps ($D9..$E1) get it -- SAFARI_ZONE_GATE is $9C and falls under that
  -- early out, and used to show "502/500" while the player was still
  -- standing at the counter (#540).  Same map set as the step counter's
  -- (FieldDefaults safari.stepMaps via OverworldState:inSafariStepZone).
  local ow = game.overworld
  if game.save.safari and ow and ow.map and ow.inSafariStepZone
     and ow:inSafariStepZone() then
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
  return menu
end

return StartMenu
