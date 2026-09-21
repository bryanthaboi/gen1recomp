local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_special_trade"

-- pokefirered/data/maps/Route2_House/scripts.inc:8 Route2_House_EventScript_Reyley
local HOUSE = "FR_ROUTE_2_HOUSE"
local REYLEY_X, REYLEY_Y = 7, 2

-- pokefirered/include/constants/species.h:67
local SPECIES_ABRA = 63
-- pokefirered/include/constants/species.h:126
local SPECIES_MR_MIME = 122
-- pokefirered/include/constants/flags.h:609
local FLAG_DID_MIMIEN_TRADE = 0x248

local failures = 0

local function say(line)
  print(line)
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
  local fh = io.open(DIR .. "/special_trade.log", "a")
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
    say("PASS special_trade")
    love.event.quit(0)
  else
    say("FAIL special_trade failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Player = require("src.core.game3.player")
  local Party = require("src.core.game3.party")
  local Pokemon = require("src.core.game3.pokemon")
  local PartyMenu = require("src.ui.game3.party_menu")
  local StartMenu = require("src.ui.game3.start_menu")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  session.party = {}
  Party.giveMon(session, SPECIES_ABRA, 18)
  Party.giveMon(session, 4, 14)
  result(#session.party == 2 and session.party[1].species == SPECIES_ABRA,
    "the party leads with the ABRA Reyley asks for")

  local function ctx() return Space.vm and Space.vm.ctx end
  local function getVar(id) return tonumber(Flags.getVar(Space.store, ctx(), id)) or 0 end

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "up" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "up"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "up"
    U.wait(30)
    local Preview = package.loaded["src.ui.game3.map_preview_screen"]
    for _ = 1, 240 do
      if not (Preview and Preview.isActive and Preview.isActive()) then break end
      U.wait(5)
    end
    U.wait(60)
  end

  result(Flags.getFlag(Space.store, ctx(), FLAG_DID_MIMIEN_TRADE) ~= true,
    "FLAG_DID_MIMIEN_TRADE starts clear")

  goTo(HOUSE, REYLEY_X, REYLEY_Y + 1, "up")
  U.shot(game, DIR .. "/special_trade_01_reyley.png")

  local function scriptRunning()
    return Space.vm and Space.vm.isRunning and Space.vm:isRunning() or false
  end

  say("[driver] talking to Reyley")
  local asked = false
  for _ = 1, 40 do
    if Choice.active then
      asked = true
      break
    end
    if Message.isWaiting and Message.isWaiting() then
      U.tap(game, "a")
    elseif not scriptRunning() then
      U.tap(game, "a")
    end
    U.wait(8)
  end
  result(asked, "Reyley asked to trade his MR. MIME for an ABRA")
  U.shot(game, DIR .. "/special_trade_02_offer.png")

  -- pokefirered/data/maps/Route2_House/scripts.inc:14
  for _ = 1, 10 do
    if Choice.cursor == 1 then break end
    U.tap(game, "up")
    U.wait(6)
  end
  U.tap(game, "a")
  U.wait(20)

  local picker = false
  for _ = 1, 90 do
    if PartyMenu.isOpen and PartyMenu.isOpen() then
      picker = true
      break
    end
    if Choice.active or (Message.isWaiting and Message.isWaiting()) then U.tap(game, "a") end
    U.wait(6)
  end
  result(picker, "ChoosePartyMon opened the party picker")
  if not picker then
    U.shot(game, DIR .. "/special_trade_03_no_picker.png")
    return finish()
  end

  say("[driver] handing over the ABRA in slot 1")
  U.tap(game, "a")
  U.wait(30)
  result(getVar(0x8004) == 0, "VAR_0x8004 = 0 for slot 1, got " .. tostring(getVar(0x8004)))

  local swapped = false
  for _ = 1, 400 do
    local lead = session.party and session.party[1]
    if lead and (tonumber(lead.species) or 0) == SPECIES_MR_MIME then
      swapped = true
      break
    end
    U.wait(4)
  end
  result(swapped, "DoInGameTradeScene put MR. MIME in the party")

  local lead = session.party and session.party[1] or {}
  result(tostring(lead.nickname) == "MIMIEN",
    "the received mon is nicknamed MIMIEN, got " .. tostring(lead.nickname))
  result(tonumber(lead.otId) == 1985,
    "its OT id is the cart's 1985, got " .. tostring(lead.otId))
  result(tostring(lead.otName) == "REYLEY",
    "its OT name is REYLEY, got " .. tostring(lead.otName))
  result(tonumber(lead.level) == 18,
    "it arrived at the ABRA's level 18, got " .. tostring(lead.level))
  result(tonumber(lead.friendship) == 70,
    "a traded mon starts at 70 friendship, got " .. tostring(lead.friendship))
  result(session.dex and session.dex.owned and session.dex.owned[SPECIES_MR_MIME] == true,
    "MR. MIME is registered as owned")

  for _ = 1, 200 do
    if not scriptRunning() and not (Message.isOpen and Message.isOpen()) then break end
    if Message.isWaiting and Message.isWaiting() then U.tap(game, "a") end
    U.wait(6)
  end
  result(Flags.getFlag(Space.store, ctx(), FLAG_DID_MIMIEN_TRADE) == true,
    "FLAG_DID_MIMIEN_TRADE is set once the trade finished")

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
    for _ = 1, 80 do
      if PartyMenu.isOpen and PartyMenu.isOpen() then return true end
      U.wait(4)
    end
    return false
  end

  result(openParty(), "the party screen opened")
  U.wait(20)
  U.shot(game, DIR .. "/special_trade_03_mimien_in_party.png")
  U.log("lead mon: " .. tostring(Pokemon.name(lead.species)) .. " / " ..
    tostring(lead.nickname) .. " Lv" .. tostring(lead.level))

  finish()
end
