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
  require("src.core.game3.scripting.flags").setFlag(require("src.core.game3.scripting.space").store, nil, 0x828, true) -- data/maps/PalletTown_ProfessorOaksLab/scripts.inc:1120
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
  U.still(game, DIR .. "/party_dig_01_pallet_fly_row.png")
  U.tap(game, "a")
  U.wait(30)
  result(PartyMenu._messageText == nil, "FLY outdoors is accepted (no refusal text)")
  -- pokefirered/src/party_menu.c:3953
  result(RegionMap.isOpen() and RegionMap.isFlyMode(), "FLY opened the fly map")
  for _ = 1, 300 do
    if RegionMap.inputReady() then break end
    U.wait(1)
  end
  U.tap(game, "b")
  for _ = 1, 200 do
    if not RegionMap.isOpen() then break end
    U.wait(1)
  end
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
  U.still(game, DIR .. "/party_dig_02_pallet_dig_refused.png")
  closeParty()

  -- pokefirered/src/fldeff_dig.c:12
  goTo(MT_MOON, 14, 22, "down")
  session.escapeWarp = { map = "FR_ROUTE_4", warpId = 255, x = 19, y = 6 }
  local CaveTransition = require("src.ui.game3.cave_transition")
  local realCaveStart = CaveTransition.start
  local caveKinds = {}
  CaveTransition.start = function(kind, ...)
    caveKinds[#caveKinds + 1] = kind
    return realCaveStart(kind, ...)
  end
  if not result(openParty(), "party menu opens in Mt Moon 1F") then return finish() end
  result(chooseAction("DIG"), "DIG is on the action list in Mt Moon")
  U.still(game, DIR .. "/party_dig_03_mtmoon_dig_row.png")
  U.tap(game, "a")
  U.wait(30)
  local digCtx = seenCtx
  result(digCtx ~= nil and tonumber(digCtx.mapType) == 4,
    "the Mt Moon context carries MAP_TYPE_UNDERGROUND (mapType=" .. tostring(digCtx and digCtx.mapType) .. ")")
  result(digCtx ~= nil and digCtx.canEscapeRope == true,
    "the Mt Moon context carries allowEscaping out of header.json")
  result(PartyMenu._messageText == nil,
    "DIG in Mt Moon is accepted (refusal: " .. tostring(PartyMenu._messageText) .. ")")
  -- pokefirered/src/party_menu.c:3946
  local digPrompt = tostring(PartyMenu._yesNoPrompt)
  result(PartyMenu.mode == "yesno" and digPrompt:find("escape from here", 1, true) ~= nil
    and digPrompt:find("ROUTE 4", 1, true) ~= nil,
    "DIG asks gText_EscapeFromHereAndReturnTo with the escape warp's place (" .. digPrompt .. ")")
  U.still(game, DIR .. "/party_dig_04_mtmoon_dig_yesno.png")
  U.tap(game, "down")
  U.wait(6)
  U.tap(game, "a")
  U.wait(12)
  -- pokefirered/src/party_menu.c:4014 Task_ReturnToChooseMonAfterText
  result(PartyMenu.isOpen() and PartyMenu.mode == "list" and session.map == MT_MOON,
    "NO goes back to choosing a mon and stays in Mt Moon (mode=" .. tostring(PartyMenu.mode) .. ")")
  result(chooseAction("DIG"), "DIG is still on the action list")
  U.tap(game, "a")
  U.wait(30)
  result(PartyMenu.mode == "yesno", "DIG asks again")
  U.tap(game, "a")
  U.wait(6)
  result(not (PartyMenu.isOpen and PartyMenu.isOpen()), "YES closes the party menu and DIG runs")
  local ShowMon = require("src.core.game3.field_move_show_mon")
  local Player = require("src.core.game3.player")
  for _ = 1, 120 do
    if ShowMon.isActive() then break end
    U.wait(1)
  end
  for _ = 1, 200 do
    local fx = ShowMon._fx
    if fx and fx.sprite and fx.sprite.state == "wait" then break end
    U.wait(1)
  end
  result(ShowMon._fx and ShowMon._fx.sprite and ShowMon._fx.sprite.state == "wait", "DIG shows the mon cut-in")
  U.still(game, DIR .. "/party_dig_04a_mtmoon_dig_show_mon.png")
  local rose = false
  for _ = 1, 400 do
    if (Player.spriteYOffset or 0) <= -40 then rose = true break end
    U.wait(1)
  end
  result(rose, "DIG spins the player and lifts them off (offY=" .. tostring(Player.spriteYOffset) .. ")")
  U.still(game, DIR .. "/party_dig_04_mtmoon_dig_used.png")
  U.wait(150)
  dismiss(30)
  U.wait(90)
  local FieldMod = require("src.core.game3.field")
  result(FieldMod.locked ~= true, "the dig warp finishes and unlocks the field")
  result(session.map == "FR_ROUTE_4", "DIG landed on the escape warp (map=" .. tostring(session.map) .. ")")
  CaveTransition.start = realCaveStart
  -- pokefirered/src/fldeff_flash.c:236 TryDoMapTransition
  result(caveKinds[1] == "exit", "DIG out of Mt Moon played FlashTransition_Exit ("
    .. table.concat(caveKinds, ",") .. ")")
  U.still(game, DIR .. "/party_dig_05_dig_landed.png")
  closeParty()

  -- pokefirered/src/party_menu.c:4099
  goTo(PALLET, 10, 6, "down")
  if not result(openParty(), "party menu opens back in Pallet Town") then return finish() end
  result(chooseAction("TELEPORT"), "TELEPORT is on the action list")
  U.tap(game, "a")
  U.wait(20)
  result(PartyMenu._messageText == nil, "TELEPORT outdoors is accepted")
  -- pokefirered/src/party_menu.c:3939
  local tpPrompt = tostring(PartyMenu._yesNoPrompt)
  result(PartyMenu.mode == "yesno" and tpPrompt:find("healing spot", 1, true) ~= nil
    and tpPrompt:find("PALLET TOWN", 1, true) ~= nil,
    "TELEPORT asks gText_ReturnToHealingSpot with the heal map's place (" .. tpPrompt .. ")")
  U.still(game, DIR .. "/party_dig_06_teleport_yesno.png")
  U.tap(game, "a")
  U.wait(6)
  result(not (PartyMenu.isOpen and PartyMenu.isOpen()), "YES closes the party menu and TELEPORT runs")
  result(not (StartMenu.isOpen and StartMenu.isOpen()), "the start menu closes with it")
  local FieldEffects = require("src.core.game3.field_effects")
  local function fxAnim(kind)
    for _, a in ipairs(FieldEffects._anims or {}) do
      if a.kind == kind then return a end
    end
  end
  local function waitFor(pred, frames)
    for _ = 1, frames do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end
  waitFor(function() return fxAnim("teleport_out") ~= nil end, 400)
  local tpOut = fxAnim("teleport_out")
  if not result(tpOut ~= nil, "TELEPORT starts the teleport field effect task") then return finish() end
  -- pokefirered/src/field_effect.c:2371 TeleportFieldEffectTask2
  waitFor(function() return tpOut.d2 >= 2 end, 40)
  local f0 = Player.facing
  waitFor(function() return Player.facing ~= f0 end, 20)
  local f1, gap = Player.facing, 0
  for _ = 1, 20 do
    if Player.facing ~= f1 then break end
    U.wait(1)
    gap = gap + 1
  end
  result(gap == 8 and Player.spriteYOffset == 0,
    "TELEPORT first turns in place every 8 frames (gap=" .. gap .. ")")
  U.still(game, DIR .. "/party_dig_07_teleport_spin.png")
  -- pokefirered/src/field_effect.c:2397 TeleportFieldEffectTask3
  waitFor(function() return tpOut.state == 3 and tpOut.d4 >= 64 end, 200)
  result(tpOut.state == 3 and tpOut.d3 == 8 and Player.spriteYOffset == -tpOut.d4
    and Player.oamPriority == 1,
    "after 8+ turns back to the start facing it spins faster and rises (y=" .. tostring(Player.spriteYOffset) .. ")")
  U.still(game, DIR .. "/party_dig_07b_teleport_rise.png")
  waitFor(function() return fxAnim("teleport_out") == nil end, 120)
  result(tpOut.d4 >= 0xa8 and not Player.isVisible(),
    "it rises 0xa8 px before the fade (d4=" .. tostring(tpOut.d4) .. ")")
  -- pokefirered/src/field_effect.c:2483 TeleportInFieldEffectTask2
  waitFor(function() return fxAnim("teleport_in") ~= nil end, 600)
  local tpIn = fxAnim("teleport_in")
  if not result(tpIn ~= nil, "the heal map runs the teleport-in effect") then return finish() end
  waitFor(function() return tpIn.y2 >= -40 end, 60)
  result(Player.isVisible() and Player.spriteYOffset == tpIn.y2 and tpIn.y2 < 0,
    "the player spins down from above the screen (y=" .. tostring(tpIn.y2) .. ")")
  -- pokefirered/src/field_effect.c:2451
  result(require("src.core.game3.field").locked == true,
    "the field stays locked while the teleport-in spin runs")
  U.still(game, DIR .. "/party_dig_07c_teleport_arrive.png")
  waitFor(function() return fxAnim("teleport_in") == nil end, 200)
  -- pokefirered/src/field_effect.c:2530
  result(Player.facing == "down" and Player.spriteYOffset == 0 and Player.oamPriority == nil,
    "the teleport-in spin stops facing south on the ground")
  dismiss(40)
  U.wait(90)
  local Field = require("src.core.game3.field")
  result(Field.locked ~= true, "the teleport warp finishes and unlocks the field")
  result(session.map ~= PALLET, "TELEPORT landed on the heal map (" .. tostring(session.map) .. ")")
  U.still(game, DIR .. "/party_dig_08_teleport_landed.png")

  finish()
end

return run
