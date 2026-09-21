local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchuid_summary_dexno"

local PALLET = "FR_PALLET_TOWN"
local WURMPLE = 290

local failures = 0

local function say(line)
  print(line)
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
  local fh = io.open(DIR .. "/stitchuid_summary_dexno.log", "a")
  if fh then
    fh:write(line, "\n")
    fh:close()
  end
end

local function result(ok, label)
  say((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    say("PASS stitchuid_summary_dexno")
    love.event.quit(0)
  else
    say("FAIL stitchuid_summary_dexno failures=" .. failures)
    love.event.quit(1)
  end
end

local function run(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Party = require("src.core.game3.party")
  local Pokemon = require("src.core.game3.pokemon")
  local PokedexData = require("src.core.game3.pokedex_data")
  local PartyMenu = require("src.ui.game3.party_menu")
  local StartMenu = require("src.ui.game3.start_menu")
  local SummaryMenu = require("src.ui.game3.summary_menu")
  local Natives = require("src.core.game3.scripting.natives")
  local Space = require("src.core.game3.scripting.space")
  local Std = require("src.core.game3.scripting.stdscripts")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  -- pokefirered/src/pokemon_summary_screen.c:2088-2092
  local FrlgFont = require("src.ui.game3.frlg_font")
  local SummaryChrome = require("src.ui.game3.summary_chrome")
  local realDraw = FrlgFont.draw
  local lastNo = nil
  FrlgFont.draw = function(str, x, y, ...)
    local c = ((SummaryChrome.manifest() or {}).coords or {}).dexNo or { x = 167, y = 21 }
    if SummaryMenu.isOpen() and x == c.x and y == c.y then lastNo = tostring(str) end
    return realDraw(str, x, y, ...)
  end

  session.party = {}
  Party.giveMon(session, WURMPLE, 20)
  result(Pokemon.national(WURMPLE) == 265, "the cache maps species 290 to national 265")

  Map.load(nil, game, PALLET, { x = 10, y = 6, facing = "down" })
  if game.session then
    game.session.x, game.session.y, game.session.facing = 10, 6, "down"
  end
  Player.cellX, Player.cellY = 10, 6
  Player.px, Player.py = 160, 96
  Player.targetX, Player.targetY = 10, 6
  U.wait(90)

  local function openParty()
    for _ = 1, 40 do
      if PartyMenu.isOpen and PartyMenu.isOpen() then return true end
      if StartMenu.isOpen and StartMenu.isOpen() then break end
      U.tap(game, "start")
      U.wait(8)
    end
    for _ = 1, 20 do
      local e = StartMenu.ENTRIES and StartMenu.ENTRIES[StartMenu.cursor]
      if e and e.id == "pokemon" then break end
      U.tap(game, "down")
      U.wait(6)
    end
    U.tap(game, "a")
    for _ = 1, 60 do
      if PartyMenu.isOpen and PartyMenu.isOpen() then return true end
      U.wait(4)
    end
    return false
  end

  local function openSummary()
    U.tap(game, "a")
    U.wait(12)
    for _ = 1, 12 do
      if PartyMenu.ACTIONS[PartyMenu.actionCursor] == "SUMMARY" then break end
      U.tap(game, "down")
      U.wait(6)
    end
    U.tap(game, "a")
    for _ = 1, 60 do
      if SummaryMenu.isOpen() then return true end
      U.wait(4)
    end
    return false
  end

  local function closeAll()
    for _ = 1, 60 do
      if not SummaryMenu.isOpen() and not (PartyMenu.isOpen and PartyMenu.isOpen()) then break end
      U.tap(game, "b")
      U.wait(8)
    end
    U.wait(30)
  end

  if not result(openParty(), "party menu opens") then return finish() end
  if not result(openSummary(), "summary opens on the WURMPLE") then return finish() end
  U.wait(40)
  result(PokedexData.isNationalUnlocked(session) == false, "the national dex starts locked")
  result(lastNo == "???", "the screen drew ??? before the national dex (" .. tostring(lastNo) .. ")")
  U.shot(game, DIR .. "/stitchuid_summary_dexno_01_national_off.png")

  closeAll()

  -- pokefirered/src/event_data.c:99
  local handler = Natives.ALLOW["special:" .. Std.SPECIAL.EnableNationalPokedex]
  if not result(handler ~= nil, "EnableNationalPokedex is bound") then return finish() end
  handler(Space.vm and Space.vm.ctx, nil)
  U.wait(20)
  result(PokedexData.isNationalUnlocked(session) == true, "the special unlocked the national dex")

  if not result(openParty(), "party menu reopens") then return finish() end
  if not result(openSummary(), "summary reopens on the WURMPLE") then return finish() end
  U.wait(40)
  result(lastNo == "265", "the screen drew 265 with the national dex (" .. tostring(lastNo) .. ")")
  U.shot(game, DIR .. "/stitchuid_summary_dexno_02_national_on.png")

  FrlgFont.draw = realDraw
  finish()
end

return run
