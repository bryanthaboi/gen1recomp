local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_ui_party_dig"

local PALLET = "FR_PALLET_TOWN"
local MT_MOON = "FR_MT_MOON_1F"
-- pokefirered/include/constants/flags.h:1090
local FLAG_BADGE03_GET = 0x822

local failures = 0
local seenCtx = nil

local function say(line)
  print(line)
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
  local fh = io.open(DIR .. "/ui_party_dig.log", "a")
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
    say("PASS ui_party_dig")
    love.event.quit(0)
  else
    say("FAIL ui_party_dig failures=" .. failures)
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
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Player = require("src.core.game3.player")
  local Party = require("src.core.game3.party")
  local PartyMenu = require("src.ui.game3.party_menu")
  local StartMenu = require("src.ui.game3.start_menu")
  local RegionMap = require("src.ui.game3.region_map")
  local Message = require("src.ui.game3.message")
  local FieldMoves = require("src.core.game3.field_moves")

  local realFromMenu = FieldMoves.fromMenu
  FieldMoves.fromMenu = function(moveId, moveCtx)
    seenCtx = moveCtx
    return realFromMenu(moveId, moveCtx)
  end

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end
  Flags.setFlag(Space.store, ctx(), FLAG_BADGE03_GET, true)

  session.party = {}
  Party.giveMon(session, 6, 40)
  local mon = session.party[1]
  mon.moves = { "FLY", "DIG", "TELEPORT", "EMBER" }
  mon.pp = { 15, 10, 20, 25 }
  result(#session.party == 1, "party has one mon that knows FLY, DIG and TELEPORT")

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "down" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "down"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "down"
    U.wait(90)
  end

  local function dismiss(frames)
    for _ = 1, frames or 20 do
      if Message.isWaiting and Message.isWaiting() then U.tap(game, "a") end
      U.wait(4)
    end
  end

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

  local function chooseAction(label)
    U.tap(game, "a")
    U.wait(12)
    local target = nil
    for i, name in ipairs(PartyMenu.ACTIONS or {}) do
      if name == label then target = i end
    end
    if not target then return false end
    for _ = 1, 12 do
      if PartyMenu.actionCursor == target then break end
      U.tap(game, "down")
      U.wait(6)
    end
    return PartyMenu.actionCursor == target
  end

  local function closeParty()
    -- pokefirered/src/region_map.c:4019
    for _ = 1, 30 do
      if not (RegionMap.isOpen and RegionMap.isOpen()) then break end
      U.tap(game, "b")
      U.wait(6)
    end
    for _ = 1, 30 do
      if not (PartyMenu.isOpen and PartyMenu.isOpen()) then break end
      if PartyMenu._messageText then U.tap(game, "a") else U.tap(game, "b") end
      U.wait(6)
    end
    for _ = 1, 20 do
      if not (StartMenu.isOpen and StartMenu.isOpen()) then break end
      U.tap(game, "b")
      U.wait(6)
    end
    U.wait(20)
  end

  -- pokefirered/src/party_menu.c:4099
  goTo(PALLET, 10, 6, "down")
  if not result(openParty(), "party menu opens in Pallet Town") then return finish() end
  result(chooseAction("FLY"), "FLY is on the action list")
  U.shot(game, DIR .. "/party_dig_01_pallet_fly_row.png")
  U.tap(game, "a")
  U.wait(30)
  result(PartyMenu._messageText == nil, "FLY outdoors is accepted (no refusal text)")
  -- pokefirered/src/party_menu.c:3953
  result(RegionMap.isOpen() and RegionMap.isFlyMode(), "FLY opened the fly map")
  U.tap(game, "b")
  U.wait(30)
  result(not RegionMap.isOpen(), "B closed the fly map")
  -- pokefirered/src/region_map.c:4019
  result(PartyMenu.isOpen and PartyMenu.isOpen(), "a cancelled fly map came back to the party menu")
  closeParty()

  -- pokefirered/src/item_use.c:614
  if not result(openParty(), "party menu reopens in Pallet Town") then return finish() end
  result(chooseAction("DIG"), "DIG is on the action list")
  U.tap(game, "a")
  U.wait(30)
  local palletRefusal = PartyMenu._messageText
  result(palletRefusal ~= nil, "DIG in Pallet Town is refused: " .. tostring(palletRefusal))
  U.shot(game, DIR .. "/party_dig_02_pallet_dig_refused.png")
  closeParty()

  -- pokefirered/src/fldeff_dig.c:12
  goTo(MT_MOON, 14, 22, "down")
  if not result(openParty(), "party menu opens in Mt Moon 1F") then return finish() end
  result(chooseAction("DIG"), "DIG is on the action list in Mt Moon")
  U.shot(game, DIR .. "/party_dig_03_mtmoon_dig_row.png")
  U.tap(game, "a")
  U.wait(30)
  local digCtx = seenCtx
  result(digCtx ~= nil and tonumber(digCtx.mapType) == 4,
    "the Mt Moon context carries MAP_TYPE_UNDERGROUND (mapType=" .. tostring(digCtx and digCtx.mapType) .. ")")
  result(digCtx ~= nil and digCtx.canEscapeRope == true,
    "the Mt Moon context carries allowEscaping out of header.json")
  result(PartyMenu._messageText == nil,
    "DIG in Mt Moon is accepted (refusal: " .. tostring(PartyMenu._messageText) .. ")")
  result(not (PartyMenu.isOpen and PartyMenu.isOpen()), "the party menu closes and DIG runs")
  U.wait(25)
  U.shot(game, DIR .. "/party_dig_04_mtmoon_dig_used.png")
  U.wait(150)
  dismiss(30)
  U.wait(90)
  local FieldMod = require("src.core.game3.field")
  result(FieldMod.locked ~= true, "the dig warp finishes and unlocks the field")
  result(session.map ~= MT_MOON, "DIG left Mt Moon (map=" .. tostring(session.map) .. ")")
  U.shot(game, DIR .. "/party_dig_05_dig_landed.png")
  closeParty()

  -- pokefirered/src/party_menu.c:4099
  goTo(PALLET, 10, 6, "down")
  if not result(openParty(), "party menu opens back in Pallet Town") then return finish() end
  result(chooseAction("TELEPORT"), "TELEPORT is on the action list")
  U.tap(game, "a")
  U.wait(20)
  result(PartyMenu._messageText == nil, "TELEPORT outdoors is accepted")
  result(not (PartyMenu.isOpen and PartyMenu.isOpen()), "the party menu closes and TELEPORT runs")
  result(not (StartMenu.isOpen and StartMenu.isOpen()), "the start menu closes with it")
  U.wait(20)
  U.shot(game, DIR .. "/party_dig_04_teleport_return.png")
  U.wait(150)
  dismiss(40)
  U.wait(90)
  local Field = require("src.core.game3.field")
  result(Field.locked ~= true, "the teleport warp finishes and unlocks the field")
  result(session.map ~= PALLET, "TELEPORT landed on the heal map (" .. tostring(session.map) .. ")")
  U.shot(game, DIR .. "/party_dig_05_teleport_landed.png")

  finish()
end

return run
