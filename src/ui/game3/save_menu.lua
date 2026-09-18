-- FRLG Save confirm dialog (start_menu save path matching pret start_menu.c).
-- Features:
-- 1. Top-left Save Stats Window (1, 1, 14, 9): Location header, Player, Badges, Pokédex, Time.
-- 2. Bottom Dialogue Window (2, 15, 26, 4): "Would you like to SAVE...", "SAVING...", "[Player] saved the game."
-- 3. Right YES/NO Window (21, 9, 6, 4).

local Stack = require("src.ui.game3.stack")
local Window = require("src.ui.game3.window")
local Chrome = require("src.ui.game3.chrome")
local FrlgFont = require("src.ui.game3.frlg_font")

local SaveMenu = {}

SaveMenu.open = false
SaveMenu.cursor = 1 -- 1=YES 2=NO
SaveMenu._phase = "confirm" -- confirm | overwrite | saving | saved
SaveMenu._session = nil
SaveMenu._onClose = nil

local function se(id)
  pcall(function() require("src.core.game3.audio").playSe(id) end)
end

local function count_badges(session)
  if not session then return 0 end
  local count = 0
  if session.badges then
    if type(session.badges) == "table" then
      for i = 1, 8 do
        if session.badges[i] == true or (tonumber(session.badges[i]) or 0) > 0 then
          count = count + 1
        end
      end
    elseif type(session.badges) == "number" then
      for i = 1, 8 do
        local mask = bit and bit.lshift(1, i - 1) or math.pow(2, i - 1)
        if bit and bit.band(session.badges, mask) ~= 0 then
          count = count + 1
        end
      end
    end
  else
    for i = 1, 8 do
      if session["badge" .. i] == true then count = count + 1 end
    end
  end
  return count
end

local function count_caught(dex)
  if not dex then return 0 end
  local n = 0
  for sp, on in pairs(dex.caught or {}) do
    if on then n = n + 1 end
  end
  return n
end

function SaveMenu.show(opts)
  opts = opts or {}
  SaveMenu.open = true
  SaveMenu.cursor = 1
  SaveMenu._phase = "confirm"
  SaveMenu._session = opts.session
  SaveMenu._onClose = opts.onClose
  Stack.push("save", SaveMenu, { hideBelow = true })
  se(6) -- SE_WIN_OPEN
end

function SaveMenu.close()
  SaveMenu.open = false
  Stack.pop("save")
  local cb = SaveMenu._onClose
  SaveMenu._onClose = nil
  se(9) -- SE_EXIT
  if cb then cb() end
end

function SaveMenu.isOpen()
  return SaveMenu.open
end

function SaveMenu.move(delta)
  if SaveMenu._phase ~= "confirm" and SaveMenu._phase ~= "overwrite" then return end
  SaveMenu.cursor = SaveMenu.cursor == 1 and 2 or 1
  se(5) -- SE_SELECT
end

local function do_save()
  SaveMenu._phase = "saving"
  local Runtime = require("src.core.game3.runtime")
  local Bridge = require("src.core.game3.bridge")
  local game = Runtime._game
  local mod = Runtime._mod
  if game and mod then
    pcall(function() Bridge.persistSessionOnly(mod, game) end)
  end
  if game and game.saveGame then
    pcall(function() game:saveGame() end)
  end
  se(48) -- SE_SAVE
  SaveMenu._phase = "saved"
end

function SaveMenu.confirm()
  if SaveMenu._phase == "saved" then
    SaveMenu.close()
    local StartMenu = require("src.ui.game3.start_menu")
    if StartMenu.isOpen() then StartMenu.close() end
    return
  end
  if SaveMenu._phase == "saving" then
    return
  end

  if SaveMenu.cursor == 1 then -- YES
    if SaveMenu._phase == "confirm" then
      -- If there is an active save file, ask overwrite confirm
      SaveMenu._phase = "overwrite"
      SaveMenu.cursor = 1
      se(5) -- SE_SELECT
    elseif SaveMenu._phase == "overwrite" then
      do_save()
    end
  else -- NO
    SaveMenu.close()
  end
end

function SaveMenu.cancel()
  if SaveMenu._phase == "saved" then
    SaveMenu.confirm()
    return
  end
  if SaveMenu._phase == "saving" then
    return
  end
  SaveMenu.close()
end

function SaveMenu.draw()
  if not SaveMenu.open then return end
  local session = SaveMenu._session or {}
  local name = tostring(session.name or session.playerName or "RED")
  local map = tostring(session.mapName or session.map or "PALLET TOWN"):upper()
  local badges = count_badges(session)
  local caught = count_caught(session.dex) or tonumber(session.caughtMonsCount) or 0
  local hours = tonumber(session.playTimeHours or session.hours) or 0
  local mins = tonumber(session.playTimeMinutes or session.minutes) or 0

  -- 1. Top-Left Save Stats Box (pret sSaveStatsWindowTemplate at (1, 1, 14, 9))
  Window.stdFrame(Window.template(1, 1, 14, 9))
  -- Location Header
  FrlgFont.draw(map, 1 * 8 + 4, 1 * 8 + 2, { maxWidth = 14 * 8, colors = FrlgFont.COLOR.NORMAL })
  -- PLAYER
  FrlgFont.draw("PLAYER", 1 * 8 + 4, 1 * 8 + 18, { colors = FrlgFont.COLOR.NORMAL })
  FrlgFont.draw(name, 1 * 8 + 56, 1 * 8 + 18, { colors = FrlgFont.COLOR.NORMAL })
  -- BADGES
  FrlgFont.draw("BADGES", 1 * 8 + 4, 1 * 8 + 32, { colors = FrlgFont.COLOR.NORMAL })
  FrlgFont.draw(tostring(badges), 1 * 8 + 56, 1 * 8 + 32, { colors = FrlgFont.COLOR.NORMAL })
  -- POKéDEX
  FrlgFont.draw("POKéDEX", 1 * 8 + 4, 1 * 8 + 46, { colors = FrlgFont.COLOR.NORMAL })
  FrlgFont.draw(tostring(caught), 1 * 8 + 56, 1 * 8 + 46, { colors = FrlgFont.COLOR.NORMAL })
  -- TIME
  FrlgFont.draw("TIME", 1 * 8 + 4, 1 * 8 + 60, { colors = FrlgFont.COLOR.NORMAL })
  FrlgFont.draw(string.format("%d:%02d", hours, mins), 1 * 8 + 56, 1 * 8 + 60, { colors = FrlgFont.COLOR.NORMAL })

  -- 2. Bottom Dialogue Window (pret WindowFunc_DrawDialogueFrame at (2, 15, 26, 4))
  Chrome.dialogueFrame()
  local msg = "Would you like to SAVE\nthe game?"
  if SaveMenu._phase == "overwrite" then
    msg = "There is already a saved file.\nIs it okay to overwrite it?"
  elseif SaveMenu._phase == "saving" then
    msg = "SAVING…\nDON'T TURN OFF THE POWER."
  elseif SaveMenu._phase == "saved" then
    msg = name .. " saved\nthe game."
  end
  FrlgFont.draw(msg, 2 * 8 + 4, 15 * 8 + 2, { linePitch = 15, colors = FrlgFont.COLOR.NORMAL })

  -- 3. Right YES/NO Window (pret sSaveStatsWindow / YesNo popup at (21, 9, 6, 4))
  if SaveMenu._phase == "confirm" or SaveMenu._phase == "overwrite" then
    local popX = 21
    local popY = 9
    local popW = 6
    local popH = 4
    Window.stdFrame(Window.template(popX, popY, popW, popH))
    local rowY1 = popY * 8 + 2
    local rowY2 = popY * 8 + 18
    local curY = (SaveMenu.cursor == 1) and rowY1 or rowY2
    Window.cursorPx(popX * 8 + 1, curY)
    FrlgFont.draw("YES", popX * 8 + 9, rowY1, { colors = FrlgFont.COLOR.NORMAL })
    FrlgFont.draw("NO", popX * 8 + 9, rowY2, { colors = FrlgFont.COLOR.NORMAL })
  end
end

return SaveMenu
