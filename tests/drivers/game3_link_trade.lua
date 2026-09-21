local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_link_trade"

local CENTER_2F = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F"
local TRADE_CENTER = "FR_TRADE_CENTER"
-- pokefirered/data/specials.inc:5 SetCableClubWarp
local SET_CABLE_CLUB_WARP = 0x01
-- pokefirered/include/constants/vars.h:163
local VAR_CABLE_CLUB_STATE = 0x406F
local VAR_0x8004 = 0x8004
local VAR_RESULT = 0x800D
-- pokefirered/include/constants/flags.h:1375
local FLAG_SYS_POKEDEX_GET = 0x829

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS link_trade")
    love.event.quit(0)
  else
    print("FAIL link_trade failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  print("PASS driver_started")
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
  local Natives = require("src.core.game3.scripting.natives")
  local NativesLink = require("src.core.game3.scripting.natives_link")
  local Link = require("src.core.game3.link")
  local LB = require("src.core.game3.link.battle")
  local LT = require("src.core.game3.link.trade")
  local TradeScene = require("src.core.game3.trade_scene")
  local PartyMenu = require("src.ui.game3.party_menu")
  local Game3Link = require("src.link.Game3Link")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end

  local function ctx() return Space.vm and Space.vm.ctx end
  local function adapters() return Space.vm and Space.vm.adapters end
  local function getVar(id) return tonumber(Flags.getVar(Space.store, ctx(), id)) or 0 end
  local function setVar(id, v) Flags.setVar(Space.store, ctx(), id, v) end

  local function place(x, y, facing)
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing
    end
  end

  -- pokefirered/src/pokemon.c:1796 the mon on the other GBA
  local peerMon = {
    species = 25, level = 14, hp = 40, maxHp = 40,
    moves = { 84 }, pp = { 30 }, maxPp = { 30 },
    personality = 175, nickname = "", friendship = 70,
    otName = "BLUE", otId = 0x2222,
  }

  local peer, peerSeat, peerParty, peerGot, peerConfirmed = nil, false, false, nil, false
  local function pumpPeer()
    if not peer then return end
    peer:update(0)
    local lu = peer:take(LB.MSG.LINKUP)
    if lu then
      peer:send({ type = LB.MSG.LINKUP, linkType = lu.linkType, players = lu.players })
    end
    if peer:take(LB.MSG.SEAT) then
      peerSeat = true
      peer:send({ type = LB.MSG.SEAT, seat = 1 })
    end
    if peer:take(LT.MSG.PARTY) then
      peerParty = true
      -- pokefirered/src/trade.c:778 InitTradeMenu
      peer:send({
        type = LT.MSG.PARTY, name = "BLUE", trainerId = 0x2222, gender = 0,
        version = 4, progressFlags = 0,
        party = { { species = 25, level = 14, hp = 40, personality = 175 } },
      })
    end
    local block = peer:take(LT.MSG.MON)
    if block then
      peerGot = block
      peer:send({ type = LT.MSG.MON, name = "BLUE", trainerId = 0x2222, mon = peerMon })
    end
    local cmd = peer:take(LT.MSG.CMD)
    while cmd do
      -- pokefirered/src/trade.c:1637 Follower_ReadLinkBuffer
      if cmd.cmd == LT.LINKCMD.SET_MONS_TO_TRADE then
        peer:send({ type = LT.MSG.CMD, cmd = LT.LINKCMD.INIT_BLOCK })
      elseif cmd.cmd == LT.LINKCMD.CONFIRM_FINISH_TRADE then
        peerConfirmed = true
        peer:send({ type = LT.MSG.CMD, cmd = LT.LINKCMD.CONFIRM_FINISH_TRADE })
      end
      cmd = peer:take(LT.MSG.CMD)
    end
  end

  local function waitP(frames)
    for _ = 1, frames do
      U.wait(1)
      pumpPeer()
    end
  end

  Flags.setFlag(Space.store, ctx(), FLAG_SYS_POKEDEX_GET, true)
  session.party = {}
  Party.giveMon(session, 1, 16)
  Party.giveMon(session, 4, 15)
  result(#session.party == 2, "the player walks in with two POKeMON")
  local offeredSpecies = session.party[1] and session.party[1].species

  -- pokefirered/data/scripts/cable_club.inc:363 CableClub_EventScript_TradeCenter
  Map.load(nil, game, CENTER_2F, { x = 9, y = 2, facing = "up" })
  place(9, 2, "up")
  U.wait(60)
  place(9, 1, "up")
  U.wait(10)
  Natives.special(ctx(), SET_CABLE_CLUB_WARP, adapters())
  result(session.dynamicWarp ~= nil and session.dynamicWarp.map == CENTER_2F,
    "SetCableClubWarp recorded the walk back to the counter")

  local host
  host, peer = Game3Link.loopback({ game = game })
  host:update(0)
  peer:update(0)
  Link.attach(host)
  result(host:isReady(), "the other GBA is on the cable")

  -- pokefirered/data/scripts/cable_club.inc:373 special TryTradeLinkup
  local yielded = Natives.special(ctx(), NativesLink.SPECIAL.TryTradeLinkup, adapters())
  result(yielded, "TryTradeLinkup parked the script while the machines agreed")
  local linkup, guard = nil, 0
  while guard < 300 and linkup == nil do
    pumpPeer()
    local poll = ctx().nativePoll
    if poll and poll() then
      linkup = getVar(VAR_RESULT)
      ctx().nativePoll = nil
      ctx().mode = "bytecode"
    elseif LB.linkup ~= nil and LB.linkup ~= Link.LINKUP.ONGOING then
      linkup = LB.linkup
    end
    U.wait(1)
    guard = guard + 1
  end
  result(linkup == Link.LINKUP.SUCCESS, "both machines chose TRADE, so the linkup succeeded")

  -- pokefirered/data/scripts/cable_club.inc:386 CableClub_EventScript_EnterTradeCenter
  setVar(VAR_0x8004, Link.USING.TRADE_CENTER)
  setVar(VAR_CABLE_CLUB_STATE, Link.USING.TRADE_CENTER)
  Map.load(nil, game, TRADE_CENTER, { x = 5, y = 8, facing = "up" })
  place(5, 8, "up")
  waitP(90)
  result(Space.mapId == TRADE_CENTER, "the player is inside the TRADE CENTER")
  U.shot(game, DIR .. "/link_trade_01_trade_center.png")

  place(4, 7, "up")
  waitP(20)
  guard = 0
  while guard < 600 and LT.state ~= "menu" do
    if not Player.moving and Player.cellY > 5 then U.hold(game, "up", 12) end
    waitP(15)
    guard = guard + 15
  end
  print("[driver] seat: cell=" .. tostring(Player.cellX) .. "," .. tostring(Player.cellY)
    .. " lt=" .. tostring(LT.state) .. " seat=" .. tostring(peerSeat))
  result(peerSeat, "sitting down told the other machine this player took a trade seat")
  if not result(LT.state == "menu", "and the trade menu opened over the cable") then
    U.shot(game, DIR .. "/link_trade_99_no_menu.png")
    Link.reset()
    return finish()
  end
  result(peerParty, "both machines swapped their party lists")
  U.shot(game, DIR .. "/link_trade_02_seated.png")

  -- pokefirered/src/trade.c:1811 SetReadyToTrade
  local offered = LT.offer(1)
  result(offered, "the player offers the mon in the first slot")
  peer:send({ type = LT.MSG.CMD, cmd = LT.LINKCMD.READY_TO_TRADE, cursor = 0 })
  guard = 0
  while guard < 300 and LT.state ~= "confirm" do
    waitP(5)
    guard = guard + 5
  end
  result(LT.state == "confirm", "both machines named a mon, so the trade asks for a yes")

  -- pokefirered/src/trade.c:2008 CB_ProcessConfirmTradeInput
  result(LT.confirm(true), "the player answers YES")
  guard = 0
  while guard < 600 and LT.state ~= "scene" do
    waitP(5)
    guard = guard + 5
  end
  print("[driver] exchange: lt=" .. tostring(LT.state) .. " peerGot="
    .. tostring(peerGot ~= nil and peerGot.mon and peerGot.mon.species))
  result(peerGot ~= nil, "this player's mon went over the cable")
  result(LT.state == "scene", "and the trade cinema started")
  result(#session.party == 2, "with both mons still accounted for")

  waitP(90)
  U.shot(game, DIR .. "/link_trade_03_cinema_send.png")
  guard = 0
  local shotReceive = false
  while guard < 3000 and LT.state ~= "done" do
    waitP(10)
    guard = guard + 10
    if not shotReceive and LT._swapped then
      shotReceive = true
      waitP(20)
      U.shot(game, DIR .. "/link_trade_04_cinema_arrive.png")
    end
  end
  print("[driver] trade over: lt=" .. tostring(LT.state)
    .. " confirmed=" .. tostring(peerConfirmed)
    .. " party1=" .. tostring(session.party[1] and session.party[1].species)
    .. " party2=" .. tostring(session.party[2] and session.party[2].species))
  result(LT.state == "done", "the link trade ran to its end")
  result(peerConfirmed, "and both machines confirmed the finished trade")
  result(TradeScene.isOpen() == false, "the cinema closed")

  -- pokefirered/src/trade_scene.c:1054 TradeMons
  result(session.party[1] and session.party[1].species == 25,
    "the received PIKACHU is in the party")
  result(session.party[1] and session.party[1].otName == "BLUE",
    "with the other player as its original trainer")
  result(peerGot and peerGot.mon and peerGot.mon.species == offeredSpecies,
    "and the other machine is holding the mon this player sent")
  result(#session.party == 2, "the party is still two mons")

  waitP(60)
  U.shot(game, DIR .. "/link_trade_05_back_in_the_room.png")

  PartyMenu.show(session.party, nil, { session = session })
  waitP(60)
  U.shot(game, DIR .. "/link_trade_06_party_after.png")
  PartyMenu.close()
  waitP(30)

  Link.reset()
  finish()
end
