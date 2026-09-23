-- FRLG-style start menu on Sevii (pret start_menu.c SetUpStartMenu_NormalField).
-- Window at tilemapLeft=22 (right column), double-spaced entries.

local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local Chrome = require("src.ui.game3.chrome")
local FrlgFont = require("src.ui.game3.frlg_font")
local Strings = require("src.core.Strings")
local ModRuntime = require("src.mods.Runtime")

local StartMenu = {}

local function se(id)
  pcall(function() require("src.core.game3.audio").playSe(id) end)
end

StartMenu.open = false
StartMenu.cursor = 1
StartMenu.ENTRIES = {}
StartMenu._confirmExit = false
StartMenu._confirmCursor = 2 -- 1=YES, 2=NO (default NO)

local function player_label(session)
  local name = (session and (session.name or session.playerName)) or "PLAYER"
  name = tostring(name)
  if #name > 7 then name = name:sub(1, 7) end
  return string.upper(name)
end

-- pokefirered/src/overworld.c:1386 IsUpdateLinkStateCBActive
local function link_state_active()
  local Link = package.loaded["src.core.game3.link"]
  if not (type(Link) == "table" and Link.link and Link.inLinkRoom) then return false end
  local ok, inRoom = pcall(Link.inLinkRoom)
  return ok and inRoom == true
end

-- pokefirered/src/union_room.c:4558 InUnionRoom
local function in_union_room(session)
  local Map = package.loaded["src.core.game3.map"]
  local cur = (Map and type(Map.current) == "string" and Map.current) or (session and session.map)
  return cur == "FR_UNION_ROOM"
end

local function safari_active(session)
  return require("src.core.game3.safari").isActive(session) == true
end

-- pret MENU_POKEDEX..MENU_EXIT order for normal field.
local function build_entries(session)
  if link_state_active() then
    -- pokefirered/src/start_menu.c:236 SetUpStartMenu_Link
    return {
      { id = "pokemon", label = "POKéMON" },
      { id = "bag", label = "BAG" },
      { id = "trainer_link", label = player_label(session) },
      { id = "option", label = "OPTION" },
      { id = "exit", label = "EXIT" },
    }
  end
  if in_union_room(session) then
    -- pokefirered/src/start_menu.c:245 SetUpStartMenu_UnionRoom
    return {
      { id = "pokemon", label = "POKéMON" },
      { id = "bag", label = "BAG" },
      { id = "trainer", label = player_label(session) },
      { id = "option", label = "OPTION" },
      { id = "exit", label = "EXIT" },
    }
  end
  if safari_active(session) then
    -- pokefirered/src/start_menu.c:226 SetUpStartMenu_SafariZone
    return {
      { id = "retire", label = "RETIRE" },
      { id = "pokedex", label = "POKéDEX" },
      { id = "pokemon", label = "POKéMON" },
      { id = "bag", label = "BAG" },
      { id = "trainer", label = player_label(session) },
      { id = "option", label = "OPTION" },
      { id = "exit", label = "EXIT" },
    }
  end
  local entries = {}
  local Flags = package.loaded["src.core.game3.scripting.flags"]
  local Space = package.loaded["src.core.game3.scripting.space"]
  local store = Space and Space.store
  local hasDex = true
  -- Retail gates Pokédex on FLAG_SYS_POKEDEX_GET (SYS_FLAGS+0x29 = 0x829).
  if store and Flags and Flags.getFlag then
    hasDex = Flags.getFlag(store, nil, Flags.IDS and Flags.IDS.SYS_POKEDEX_GET or 0x829) == true
  end
  if hasDex then
    entries[#entries + 1] = { id = "pokedex", label = "POKéDEX" }
  end
  -- start_menu.c:217-218
  local hasMon = true
  if store and Flags and Flags.getFlag then
    hasMon = Flags.getFlag(store, nil, Flags.IDS and Flags.IDS.SYS_POKEMON_GET or 0x828) == true
  end
  if hasMon then
    entries[#entries + 1] = { id = "pokemon", label = "POKéMON" }
  end
  entries[#entries + 1] = { id = "bag", label = "BAG" }
  entries[#entries + 1] = { id = "trainer", label = player_label(session) }
  entries[#entries + 1] = { id = "save", label = "SAVE" }
  entries[#entries + 1] = { id = "option", label = "OPTION" }
  entries[#entries + 1] = { id = "exit", label = "EXIT" }
  return entries
end

function StartMenu.resetCursor()
  StartMenu.cursor = 1
end

function StartMenu.saveOffered(session)
  for _, entry in ipairs(build_entries(session)) do
    if entry.id == "save" then return true end
  end
  return false
end

function StartMenu.show(opts)
  opts = opts or {}
  StartMenu.open = true
  StartMenu._confirmExit = false
  StartMenu._confirmCursor = 2
  StartMenu._session = opts.session
  StartMenu._game = opts.game
  StartMenu._onClose = opts.onClose
  StartMenu.ENTRIES = build_entries(opts.session)
  StartMenu._safariStats = not link_state_active() and not in_union_room(opts.session)
    and safari_active(opts.session)
  if ModRuntime.wantsHook("ui.start_menu.items") then
    local hooked = ModRuntime.call("ui.start_menu.items", function(_, items) return items end,
      opts.game, StartMenu.ENTRIES)
    if type(hooked) == "table" then StartMenu.ENTRIES = hooked end
  end
  local pos = tonumber(StartMenu.cursor) or 1
  if pos < 1 or pos > #StartMenu.ENTRIES then pos = 1 end -- pokefirered/src/menu.c:276
  StartMenu.cursor = pos -- pokefirered/src/start_menu.c:329
  Stack.push("start", StartMenu, { hideBelow = true })
  se(6) -- SE_WIN_OPEN
end

function StartMenu.close(silent)
  StartMenu.open = false
  StartMenu._confirmExit = false
  Stack.pop("start")
  local cb = StartMenu._onClose
  StartMenu._onClose = nil
  if not silent then se(5) end -- pokefirered/src/start_menu.c:1005
  if cb then cb() end
end

function StartMenu.cancel()
  if StartMenu._confirmExit then
    StartMenu._confirmExit = false
    -- pokefirered/src/menu.c:381
    return
  end
  StartMenu.close()
end

function StartMenu.move(delta)
  if StartMenu._confirmExit then
    StartMenu._confirmCursor = (StartMenu._confirmCursor == 1) and 2 or 1
    se(5) -- SE_SELECT
    return
  end
  local n = #StartMenu.ENTRIES
  if n < 1 then return end
  StartMenu.cursor = ((StartMenu.cursor - 1 + delta) % n) + 1
  se(5) -- SE_SELECT
end

function StartMenu.confirm()
  se(5)
  if StartMenu._confirmExit then
    if StartMenu._confirmCursor == 1 then -- YES
      StartMenu.open = false
      StartMenu._confirmExit = false
      Stack.pop("start")
      local Runtime = package.loaded["src.core.game3.runtime"]
      local game = (StartMenu._session and StartMenu._session.game)
        or (Runtime and Runtime._game)
        or StartMenu._game
      if game and game.returnToTitle then
        game:returnToTitle()
      end
    else -- NO
      StartMenu._confirmExit = false
    end
    return
  end

  local e = StartMenu.ENTRIES[StartMenu.cursor]
  if not e then return end
  local session = StartMenu._session
  if type(e.onSelect) == "function" then
    local ok, err = pcall(e.onSelect, StartMenu._game, session)
    if not ok then print("[game3/start_menu] onSelect failed: " .. tostring(err)) end
  elseif e.id == "exit" then
    StartMenu._confirmExit = true
    StartMenu._confirmCursor = 2 -- Default to NO
  elseif e.id == "bag" then
    local BagMenu = require("src.ui.game3.bag_menu")
    BagMenu.show(session and session.bag, {
      session = session,
      onClose = function() end,
    })
  elseif e.id == "pokedex" then
    local Pokedex = require("src.ui.game3.pokedex")
    Pokedex.show(session and session.dex, { session = session })
  elseif e.id == "pokemon" then
    local PartyMenu = require("src.ui.game3.party_menu")
    PartyMenu.show(session and session.party, session and session.move_overlay, {
      session = session,
    })
  elseif e.id == "retire" then
    -- pokefirered/src/start_menu.c:546 StartMenuSafariZoneRetireCallback
    local game = StartMenu._game
    StartMenu.close(true)
    require("src.core.game3.safari").retirePrompt(session, game)
  elseif e.id == "trainer_link" then
    -- pokefirered/src/start_menu.c:556 StartMenuLinkPlayerCallback
    local TrainerCard = require("src.ui.game3.trainer_card")
    TrainerCard.show({ session = require("src.core.game3.link").localTrainerCard() })
  elseif e.id == "trainer" then
    local TrainerCard = require("src.ui.game3.trainer_card")
    TrainerCard.show({ session = session })
  elseif e.id == "save" then
    local SaveMenu = require("src.ui.game3.save_menu")
    SaveMenu.show({ session = session, game = StartMenu._game })
  elseif e.id == "option" then
    local OptionMenu = require("src.ui.game3.option_menu")
    OptionMenu.show({ session = session })
  end
end

function StartMenu.isOpen()
  return StartMenu.open
end

--- pret: content at (22,1), width 7; labels at +8px, rows every 15px.
function StartMenu.contentTemplate()
  local n = math.max(1, #StartMenu.ENTRIES)
  -- Window height in tiles: pret (numActions*2)+2 includes frame padding;
  -- content height for n×15px rows ≈ ceil(n*15/8) tiles.
  local contentH = math.max(2, math.ceil((n * Window.OPTION_HEIGHT) / 8))
  return Window.template(22, 1, 7, contentH)
end

function StartMenu.draw()
  if not StartMenu.open then return end
  if StartMenu._safariStats then
    -- pokefirered/src/start_menu.c:255 DrawSafariZoneStatsWindow
    local Safari = require("src.core.game3.safari")
    local stats = Window.template(1, 1, 10, 4)
    Window.stdFrame(stats)
    -- pokefirered/src/strings.c:167 gText_MenuSafariStats
    local text = string.format("%3d/%3d\nBALLS  %2d",
      Safari.steps(StartMenu._session), Safari.STEPS, Safari.balls(StartMenu._session))
    Window.printPx(text, stats.left * 8 + 4, stats.top * 8 + 3)
  end
  local tpl = StartMenu.contentTemplate()
  Window.stdFrame(tpl)
  local leftPx = tpl.left * 8
  local topPx = tpl.top * 8
  for i, e in ipairs(StartMenu.ENTRIES) do
    -- pret: cursor (0, i*15), text (8, i*15) inside the window.
    local yPx = Window.menuRowPx(topPx, i)
    if not StartMenu._confirmExit and i == StartMenu.cursor then
      Window.cursorPx(leftPx, yPx)
    end
    Window.printPx(e.label, leftPx + Window.CURSOR_WIDTH, yPx)
  end

  if StartMenu._confirmExit then
    -- Bottom Dialogue Window
    Chrome.dialogueFrame()
    local prompt = Strings("RETURN TO MAIN\nMENU?")
    FrlgFont.draw(prompt, 2 * 8 + 4, 15 * 8 + 2, { linePitch = 15, colors = FrlgFont.COLOR.NORMAL })

    -- Right YES/NO Window
    local popX = 21
    local popY = 9
    local popW = 6
    local popH = 4
    Window.stdFrame(Window.template(popX, popY, popW, popH))
    local rowY1 = popY * 8 + 2
    local rowY2 = popY * 8 + 18
    local curY = (StartMenu._confirmCursor == 1) and rowY1 or rowY2
    Window.cursorPx(popX * 8 + 1, curY)
    FrlgFont.draw(Strings("YES"), popX * 8 + 9, rowY1, { colors = FrlgFont.COLOR.NORMAL })
    FrlgFont.draw(Strings("NO"), popX * 8 + 9, rowY2, { colors = FrlgFont.COLOR.NORMAL })
  end
end

return StartMenu
