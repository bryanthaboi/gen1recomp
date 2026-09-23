local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_stitchsave_summary"

local ROUTE_1 = "FR_ROUTE_1"

local failures = 0

local function say(line)
  print(line)
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
  local fh = io.open(DIR .. "/stitchsave_summary.log", "a")
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
    say("PASS stitchsave_summary")
    love.event.quit(0)
  else
    say("FAIL stitchsave_summary failures=" .. failures)
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
  local Pokemon = require("src.core.game3.pokemon")
  local Party = require("src.core.game3.party")
  local SummaryData = require("src.core.game3.summary_data")
  local PartyMenu = require("src.ui.game3.party_menu")
  local StartMenu = require("src.ui.game3.start_menu")
  local SummaryMenu = require("src.ui.game3.summary_menu")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  Map.load(nil, game, ROUTE_1, { x = 9, y = 9, facing = "down" })
  if game.session then
    game.session.x, game.session.y, game.session.facing = 9, 9, "down"
  end
  Player.cellX, Player.cellY = 9, 9
  Player.px, Player.py = 9 * 16, 9 * 16
  Player.targetX, Player.targetY = 9, 9
  U.wait(60)

  U.hold(game, "down", 16)
  U.wait(20)
  U.hold(game, "up", 16)
  U.wait(30)

  session = Runtime.getSession() or session
  result(session.map == ROUTE_1, "standing on Route 1, map=" .. tostring(session.map))

  local sec = Pokemon.currentMapSec(session)
  result(tonumber(sec) ~= nil, "Route 1 resolves to a region map section (" .. tostring(sec) .. ")")

  session.party = {}
  require("src.core.game3.scripting.flags").setFlag(require("src.core.game3.scripting.space").store, nil, 0x828, true) -- data/maps/PalletTown_ProfessorOaksLab/scripts.inc:1120
  -- pokefirered/src/script_pokemon_util.c:48 ScriptGiveMon
  local code, gift = Party.giveMonToPlayer(session, 106, 25, "")
  if not result(code == Party.MON_GIVEN_TO_PARTY and gift ~= nil, "the script gift reached the party") then
    return finish()
  end
  result(tonumber(gift.metLocation) == tonumber(sec),
    "the gift was stamped with the Route 1 section (" .. tostring(gift.metLocation) .. ")")
  result(gift.metLocationName == nil, "and with no stamped place name")

  -- pokefirered/src/script_pokemon_util.c:48 ScriptGiveMon
  Party.giveMonToPlayer(session, 25, 20, "")
  Party.giveMonToPlayer(session, 1, 20, "")
  -- pokefirered/src/pokemon.c:5618 CheckPartyPokerus
  session.party[2].pokerus = 0x10
  session.party[3].pokerus = 0x41

  local memo = SummaryData.formatTrainerMemo(gift, session)
  local memoText = table.concat(memo, " "):gsub("\n", " ")
  say("[driver] trainer memo: " .. memoText)
  result(memoText:find("ROUTE 1", 1, true) ~= nil, "the trainer memo names ROUTE 1")
  result(memoText:find("PALLET TOWN", 1, true) == nil, "and never claims PALLET TOWN")

  result(SummaryData.statusAilment(session.party[2]) == 0,
    "a cured mon has no status ailment")
  result(SummaryMenu.showsPokerusIcon(session.party[2]) == true,
    "a cured mon shows the pokerus dot")
  result(SummaryData.statusAilment(session.party[3]) == 6,
    "an infected mon still reports PKRS")
  result(SummaryMenu.showsPokerusIcon(session.party[3]) == false,
    "and an infected mon has no cured dot")

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

  local function closeSummary()
    for _ = 1, 40 do
      if not SummaryMenu.isOpen() then break end
      U.tap(game, "b")
      U.wait(6)
    end
    U.wait(20)
  end

  if not result(openParty(), "party menu opens") then return finish() end
  if not result(openSummary(), "summary opens on the gift mon") then return finish() end
  U.wait(40)
  U.shot(game, DIR .. "/stitchsave_summary_01_route1_memo.png")
  closeSummary()

  U.tap(game, "down")
  U.wait(20)
  if not result(openSummary(), "summary opens on the cured mon") then return finish() end
  U.wait(40)
  U.shot(game, DIR .. "/stitchsave_summary_02_cured_no_pkrs.png")
  closeSummary()

  U.tap(game, "down")
  U.wait(20)
  if not result(openSummary(), "summary opens on the infected mon") then return finish() end
  U.wait(40)
  U.shot(game, DIR .. "/stitchsave_summary_03_infected_pkrs.png")
  closeSummary()

  finish()
end

return run
