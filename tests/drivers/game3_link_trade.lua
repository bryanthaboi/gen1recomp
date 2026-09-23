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
    item = 13, heldItem = 13,
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
        party = { LT.copy(peerMon) },
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
  -- pokefirered/include/constants/items.h:17, :125
  session.party[1].item, session.party[1].heldItem = 13, 13
  session.party[2].item, session.party[2].heldItem = 121, 121
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

  local Menu = require("src.ui.game3.link_trade_menu")
  local SummaryMenu = require("src.ui.game3.summary_menu")
  local function waitFor(pred, limit)
    local n = 0
    while n < (limit or 300) and not pred() do
      waitP(1)
      n = n + 1
    end
    return pred()
  end
  local function tap(btn)
    U.tap(game, btn)
    waitP(2)
  end

  -- pokefirered/src/trade.c:1065
  result(waitFor(function() return Menu.cb == "main" and Menu.fade == 0 end),
    "the trade screen faded in over the standby message")
  local okArt, art = pcall(Menu.loadArt)
  result(okArt and art ~= nil and art.menu_bg1 ~= nil, "the trade menu sheets came out of the cache")
  waitP(20)
  U.shot(game, DIR .. "/link_trade_02_seated.png")

  -- pokefirered/src/party_menu.c:2785 DrawHeldItemIconsForTrade
  local okHold, holdSheet = pcall(PartyMenu.heldItemSheet)
  result(okHold and holdSheet ~= nil, "the held-item sheet came out of the party chrome cache")
  result(Menu.heldItemFrame(session.party[1]) == 0 and Menu.heldItemFrame(session.party[2]) == 1
    and Menu.heldItemFrame(LT.peerParty[1]) == 0,
    "the trade grid puts the item icon on POTION holders and the mail icon on MAIL")
  U.shot(game, DIR .. "/link_trade_02a_held_item_icons.png")

  -- pokefirered/src/main.c:309 JOY_REPT
  table.insert(game.input.pressQueue, "right")
  for _ = 1, 43 do
    game.input.state.right = true
    waitP(1)
  end
  game.input.state.right = false
  waitP(2)
  result(Menu.pos == 6, "holding RIGHT repeats after 40 frames onto the other player's lead")
  tap("left")
  tap("left")
  result(Menu.pos == 0, "LEFT twice walks back to the lead")

  -- pokefirered/src/trade.c:349 sCursorMoveDestinations
  tap("right")
  tap("right")
  result(Menu.pos == 6, "RIGHT twice crosses to the other player's party")
  U.shot(game, DIR .. "/link_trade_02b_cursor_partner.png")
  tap("down")
  result(Menu.pos == 12, "DOWN from a lone partner mon lands on CANCEL")
  U.shot(game, DIR .. "/link_trade_02c_cursor_cancel.png")
  -- pokefirered/src/trade.c:1867
  tap("a")
  result(Menu.cb == "cancel_prompt", "A on CANCEL asks YES / NO")
  U.shot(game, DIR .. "/link_trade_02d_cancel_prompt.png")
  tap("b")
  result(Menu.cb == "main" and LT.state == "menu", "B answers NO and nothing was canceled")

  -- pokefirered/src/trade.c:1939
  tap("up")
  result(Menu.pos == 6, "UP from CANCEL returns to the partner mon")
  tap("a")
  result(waitFor(function() return SummaryMenu.isOpen() end), "A on a partner mon opens its summary")
  waitP(20)
  result(SummaryMenu._enemyParty == true and SummaryMenu._owner and SummaryMenu._owner.playerName == "BLUE",
    "the partner's summary reads as the enemy party with BLUE as the owner")
  do
    local SummaryData = require("src.core.game3.summary_data")
    local mon = SummaryMenu._party and SummaryMenu._party[SummaryMenu._cursor]
    local want = require("src.core.game3.pokemon").gender(mon and mon.species, mon and mon.personality)
    -- pokefirered/src/pokemon_summary_screen.c:2114
    result(SummaryData.gender(mon) == want and (want == "M" or want == "F"),
      "the partner summary prints the gender symbol, " .. tostring(SummaryData.gender(mon)))
  end
  U.shot(game, DIR .. "/link_trade_02e_partner_summary.png")
  tap("b")
  result(waitFor(function() return Menu.cb == "main" and Menu.fade == 0 end),
    "B on the summary comes back to the trade screen")
  result(Menu.pos == 6, "with the cursor on the mon that was viewed")

  tap("left")
  tap("left")
  result(Menu.pos == 0, "LEFT twice walks back to the lead")
  -- pokefirered/src/trade.c:1847
  tap("a")
  result(Menu.cb == "selected" and Menu.submenuVisible, "A on an own mon opens SUMMARY / TRADE")
  U.shot(game, DIR .. "/link_trade_02f_summary_trade_menu.png")
  tap("down")
  -- pokefirered/src/trade.c:1811 SetReadyToTrade
  tap("a")
  result(LT.state == "ready_wait", "TRADE offers the mon in the first slot")
  result(not Menu.cursorVisible, "and hides the cursor behind the standby message")
  U.shot(game, DIR .. "/link_trade_02g_standby.png")
  peer:send({ type = LT.MSG.CMD, cmd = LT.LINKCMD.READY_TO_TRADE, cursor = 0 })
  result(waitFor(function() return Menu.cb == "okay_wait" end),
    "both machines named a mon, so both slide to the middle")
  waitP(10)
  U.still(game, DIR .. "/link_trade_02h_selected_mons.png")
  result(Menu.cb == "okay_wait" and not Menu.confirming,
    "the selected-mon screen holds before the YES / NO")
  -- pokefirered/src/trade.c:2086
  result(waitFor(function() return Menu.confirming end), "the YES / NO comes up after the pause")
  U.shot(game, DIR .. "/link_trade_02i_is_this_okay.png")

  local tradesBefore = tonumber(type(session.gameStats) == "table" and session.gameStats[21]) or 0
  local sentName = require("src.core.game3.pokemon").name(offeredSpecies)
  -- pokefirered/src/trade.c:2008 CB_ProcessConfirmTradeInput
  tap("a")
  result(LT.state ~= "confirm", "the player answers YES")
  guard = 0
  local sawExit, shotFade = false, false
  while guard < 600 and LT.state ~= "scene" do
    waitP(1)
    guard = guard + 1
    if Menu.cb == "exiting" then sawExit = true end
    if not shotFade and Menu.isOpen() and Menu.fade >= 6 and Menu.fade <= 10 then
      shotFade = true
      U.still(game, DIR .. "/link_trade_02j_fade_to_trade.png")
    end
  end
  -- pokefirered/src/trade.c:1293 CB_FadeToStartTrade
  print("[driver] fade before scene: menu reached exiting=" .. tostring(sawExit)
    .. " fade shot=" .. tostring(shotFade))
  result(sawExit and shotFade, "the trade menu fades to black before the trade scene")
  print("[driver] exchange: lt=" .. tostring(LT.state) .. " peerGot="
    .. tostring(peerGot ~= nil and peerGot.mon and peerGot.mon.species))
  result(peerGot ~= nil, "this player's mon went over the cable")
  result(LT.state == "scene", "and the trade cinema started")
  result(#session.party == 2, "with both mons still accounted for")

  guard = 0
  while guard < 1200 and TradeScene.phase() ~= "pokeball_depart" do
    waitP(1)
    guard = guard + 1
  end
  local sendSt = TradeScene.state() or {}
  print("[driver] send scene: phase=" .. tostring(TradeScene.phase()) .. " text=" .. tostring(sendSt.text)
    .. " shadow=" .. tostring(sendSt.monShadowBg) .. " hofs=" .. tostring(sendSt.bg2hofs))
  -- pokefirered/src/trade_scene.c:1381 gText_ByeByeVar1
  result(TradeScene.phase() == "pokeball_depart" and tostring(sendSt.text):find("Bye") ~= nil,
    "the send scene is on Bye-bye")
  -- pokefirered/src/trade_scene.c:1121
  result(sendSt.monShadowBg == true and sendSt.bg2hofs == 0, "the BG2 mon shadow sits under the sent mon")
  U.still(game, DIR .. "/link_trade_03_cinema_send.png")
  guard = 0
  local shotReceive = false
  while guard < 6000 and LT.state ~= "done" do
    waitP(1)
    guard = guard + 1
    if not shotReceive and TradeScene.phase() == "after_new_mon_delay" then
      shotReceive = true
      local st = TradeScene.state() or {}
      print("[driver] arrive text: " .. tostring(st.text))
      -- pokefirered/src/trade_scene.c:1756 gText_TakeGoodCareOfX
      result(tostring(st.text):find("Take good care of PIKACHU") ~= nil,
        "the arrival shot is on Take good care of PIKACHU!")
      result(st.monShadowBg == true, "the BG2 mon shadow sits under the received mon")
      U.still(game, DIR .. "/link_trade_04_cinema_arrive.png")
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
  -- pokefirered/src/trade_scene.c:2606
  result((tonumber(session.gameStats and session.gameStats[21]) or 0) == tradesBefore + 1,
    "GAME_STAT_POKEMON_TRADES went up by one")
  -- pokefirered/src/trade_scene.c:2605
  local qlScenes = session.questLog and session.questLog.scenes or {}
  local qlEvents = qlScenes[#qlScenes] and qlScenes[#qlScenes].events or {}
  local ql = qlEvents[#qlEvents]
  print("[driver] quest log: " .. tostring(ql and ql.key) .. " S1=" .. tostring(ql and ql.args.S1)
    .. " S2=" .. tostring(ql and ql.args.S2) .. " S3=" .. tostring(ql and ql.args.S3))
  result(ql and ql.key == "TradedMon1ForPersonsMon2" and ql.args.S1 == "BLUE"
    and ql.args.S2 == "PIKACHU" and ql.args.S3 == sentName,
    "the quest log records the link trade")

  waitP(60)
  U.shot(game, DIR .. "/link_trade_05_back_in_the_room.png")

  PartyMenu.show(session.party, nil, { session = session })
  waitP(60)
  local oam = PartyMenu._oam or {}
  result(oam[1] and oam[1].item ~= nil and oam[2] and oam[2].item ~= nil,
    "the party menu shows the received POTION and the kept MAIL")
  U.shot(game, DIR .. "/link_trade_06_party_after.png")
  PartyMenu.close()
  waitP(30)

  local StartMenu = require("src.ui.game3.start_menu")
  local TrainerCard = require("src.ui.game3.trainer_card")
  StartMenu.show({ session = session })
  waitP(10)
  local cardEntry
  for _ = 1, 10 do
    local e = StartMenu.ENTRIES and StartMenu.ENTRIES[StartMenu.cursor or 1]
    if e and (e.id == "trainer" or e.id == "trainer_link") then cardEntry = e.id break end
    tap("down")
    waitP(4)
  end
  tap("a")
  waitP(30)
  result(TrainerCard.isOpen(), "the START menu opened the trainer card (" .. tostring(cardEntry) .. ")")
  tap("a")
  result(waitFor(function() return TrainerCard.side == "back" and not TrainerCard._flip end, 60),
    "A flipped the card to the back")
  local trades
  for _, t in ipairs(TrainerCard.backTexts(TrainerCard._card)) do
    if t.id == "trades" then trades = t.text end
  end
  print("[driver] card trades=" .. tostring(trades) .. " stat=" .. tostring(session.gameStats[21]))
  -- pokefirered/src/trainer_card.c:824
  result(trades ~= nil and tonumber(trades) == session.gameStats[21] and session.gameStats[21] > 0,
    "the card back shows the link trade count")
  U.still(game, DIR .. "/2436_card_back_trades.png")
  for _ = 1, 20 do
    if not TrainerCard.isOpen() then break end
    tap("b")
    waitP(8)
  end

  Link.reset()
  finish()
end
