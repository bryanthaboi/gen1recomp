local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_ui_summary_pokerus"

local PALLET = "FR_PALLET_TOWN"

local failures = 0

local function say(line)
  print(line)
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
  local fh = io.open(DIR .. "/ui_summary_pokerus.log", "a")
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
    say("PASS ui_summary_pokerus")
    love.event.quit(0)
  else
    say("FAIL ui_summary_pokerus failures=" .. failures)
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
  local PartyMenu = require("src.ui.game3.party_menu")
  local StartMenu = require("src.ui.game3.start_menu")
  local SummaryMenu = require("src.ui.game3.summary_menu")
  local SummaryChrome = require("src.ui.game3.summary_chrome")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  session.party = {}
  require("src.core.game3.scripting.flags").setFlag(require("src.core.game3.scripting.space").store, nil, 0x828, true) -- data/maps/PalletTown_ProfessorOaksLab/scripts.inc:1120
  Party.giveMon(session, 25, 20)
  Party.giveMon(session, 1, 20)
  -- pokefirered/src/pokemon.c:5618
  session.party[1].pokerus = 0x10
  session.party[2].pokerus = 0x00

  result(SummaryMenu.showsPokerusIcon(session.party[1]) == true, "slot 1 is cured and shows the dot")
  result(SummaryMenu.showsPokerusIcon(session.party[2]) == false, "slot 2 never had it")
  result(SummaryChrome.pokerusImage() ~= nil, "the cache carries pokerus.rgba")

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

  if not result(openParty(), "party menu opens") then return finish() end
  if not result(openSummary(), "summary opens on the cured mon") then return finish() end
  U.wait(40)
  U.shot(game, DIR .. "/summary_pokerus_01_cured_info.png")

  for _ = 1, 40 do
    if not SummaryMenu.isOpen() then break end
    U.tap(game, "b")
    U.wait(6)
  end
  U.wait(30)
  U.tap(game, "right")
  U.wait(20)
  if not result(openSummary(), "summary opens on the clean mon") then return finish() end
  U.wait(40)
  U.shot(game, DIR .. "/summary_pokerus_02_clean_info.png")

  finish()
end

return run
