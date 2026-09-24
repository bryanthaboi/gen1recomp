local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_link_battle"

local CENTER_2F = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F"
local COLOSSEUM = "FR_BATTLE_COLOSSEUM_2P"
-- pokefirered/data/specials.inc:5 SetCableClubWarp
local SET_CABLE_CLUB_WARP = 0x01
-- pokefirered/include/constants/vars.h:163
local VAR_CABLE_CLUB_STATE = 0x406F
local VAR_0x8004 = 0x8004
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
    print("PASS link_battle")
    love.event.quit(0)
  else
    print("FAIL link_battle failures=" .. failures)
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
  local Link = require("src.core.game3.link")
  local LB = require("src.core.game3.link.battle")
  local Game3Link = require("src.link.Game3Link")
  local Protocol = require("src.link.Protocol")
  local Battle = require("src.core.game3.battle")
  local BattleUi = require("src.core.game3.battle.ui")

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

  -- pokefirered/src/pokemon.c:1796 the other GBA's party
  local peerHolder = { name = "BLUE", trainerId = 0x2222, party = {} }
  Party.giveMon(peerHolder, 129, 5)
  Party.giveMon(peerHolder, 23, 5)
  local karp, ekans = peerHolder.party[1], peerHolder.party[2]
  karp.moves, karp.pp, karp.maxPp = { 150 }, { 40 }, { 40 }
  ekans.moves, ekans.pp, ekans.maxPp = { 40 }, { 35 }, { 35 }
  local peerParty = Protocol.packParty3(peerHolder.party)

  local peer, turnsAnswered, peerSeat, peerSetup = nil, 0, false, false
  local peerSwitches, peerSentSwitch = 0, false
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
    local setup = peer:take(LB.MSG.SETUP)
    if setup then
      peerSetup = true
      peer:send({
        type = LB.MSG.SETUP, seed = setup.seed, mode = setup.mode,
        name = "BLUE", trainerId = 0x2222, gender = 0, party = peerParty,
      })
    end
    local act = peer:take(LB.MSG.ACTION)
    if act then
      turnsAnswered = turnsAnswered + 1
      peer:send({ type = LB.MSG.ACTION, turn = act.turn, kind = "move", slot = 1 })
    end
    if peer:take(LB.MSG.SWITCH) then peerSwitches = peerSwitches + 1 end
    -- pokefirered/data/battle_scripts_1.s:2837 the other machine picks its own replacement
    if Battle._phase == "linkswitch" and not peerSentSwitch then
      peerSentSwitch = true
      peer:send({ type = LB.MSG.SWITCH, slot = 2 })
    end
    peer:take(LB.MSG.OUTCOME)
  end

  local function waitP(frames)
    for _ = 1, frames do
      U.wait(1)
      pumpPeer()
    end
  end

  local function printedStill(path)
    local Message = require("src.ui.game3.message")
    local n = 0
    while n < 600 and not (Message.isOpen() and Message.isWaiting()) do
      waitP(1)
      n = n + 1
    end
    U.still(game, path)
  end

  local function mashP(frames)
    local left = frames
    while left > 0 do
      U.tap(game, "a")
      waitP(12)
      left = left - 12
    end
  end

  Flags.setFlag(Space.store, ctx(), FLAG_SYS_POKEDEX_GET, true)
  session.party = {}
  Party.giveMon(session, 6, 50)
  local lead = session.party[1]
  lead.moves, lead.pp, lead.maxPp = { 53 }, { 15 }, { 15 }
  Party.giveMon(session, 1, 48)
  result(#session.party == 2, "the player has a party to battle with")

  -- pokefirered/data/scripts/cable_club.inc:284 CableClub_EventScript_EnterColosseum
  Map.load(nil, game, CENTER_2F, { x = 9, y = 2, facing = "up" })
  place(9, 2, "up")
  U.wait(60)
  Flags.setFlag(Space.store, ctx(), FLAG_SYS_POKEDEX_GET, true)
  place(9, 1, "up")
  U.wait(10)
  Natives.special(ctx(), SET_CABLE_CLUB_WARP, adapters())
  result(session.dynamicWarp ~= nil and session.dynamicWarp.map == CENTER_2F,
    "SetCableClubWarp recorded the way back to the cable club counter")

  local host
  host, peer = Game3Link.loopback({ game = game })
  host:update(0)
  peer:update(0)
  Link.attach(host)
  result(host:isReady(), "the other GBA is on the cable")

  -- pokefirered/data/scripts/cable_club.inc:262 CableClub_EventScript_SingleBattleMode
  setVar(VAR_0x8004, Link.USING.SINGLE_BATTLE)
  local NativesLink = require("src.core.game3.scripting.natives_link")
  local VAR_RESULT = 0x800D
  local yielded = Natives.special(ctx(), NativesLink.SPECIAL.TryBattleLinkup, adapters())
  result(yielded, "TryBattleLinkup parked the script while the two machines agreed")
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
  print("[driver] linkup=" .. tostring(linkup) .. " lb=" .. tostring(LB.state))
  result(linkup == Link.LINKUP.SUCCESS,
    "both machines picked SINGLE BATTLE, so the linkup reports LINKUP_SUCCESS")
  result(LB.state == "seat", "and the session is waiting for a colosseum seat")

  -- pokefirered/data/scripts/cable_club.inc:284 special SavePlayerParty
  Natives.special(ctx(), 0x27, adapters())
  Natives.special(ctx(), 0x14B, adapters())
  setVar(VAR_CABLE_CLUB_STATE, Link.USING.SINGLE_BATTLE)
  Map.load(nil, game, COLOSSEUM, { x = 6, y = 8, facing = "up" })
  place(6, 8, "up")
  waitP(120)
  result(Space.mapId == COLOSSEUM, "the player is inside the 2P colosseum")
  U.shot(game, DIR .. "/link_battle_01_colosseum.png")

  -- pokefirered/data/scripts/cable_club.inc:575 BattleColosseum_2P_EventScript_PlayerSpot0
  place(3, 6, "up")
  waitP(20)
  U.hold(game, "up", 24)
  waitP(60)
  guard = 0
  while guard < 600 and not Battle.isActive() do
    pumpPeer()
    if Player.cellY > 5 and not Player.moving then U.hold(game, "up", 12) end
    waitP(15)
    guard = guard + 15
  end
  print("[driver] seat=" .. tostring(LB.seat) .. " lb=" .. tostring(LB.state)
    .. " cell=" .. tostring(Player.cellX) .. "," .. tostring(Player.cellY))
  result(peerSeat, "the other machine saw this player take a colosseum seat")
  result(peerSetup, "and received this player's party over the cable")
  if not result(Battle.isActive(), "the link battle started") then
    U.shot(game, DIR .. "/link_battle_99_no_battle.png")
    Link.reset()
    return finish()
  end

  local st = Battle.getState()
  result(st.link == true, "BATTLE_TYPE_LINK is set on the battle state")
  result(st.peerName == "BLUE", "the opponent is the peer, not an NPC trainer")
  waitP(180)
  printedStill(DIR .. "/link_battle_02_battle_start.png")

  guard = 0
  while guard < 1800 and Battle._phase ~= "command" and Battle._phase ~= "linkwait" do
    U.tap(game, "a")
    waitP(12)
    guard = guard + 12
  end
  print("[driver] first menu: phase=" .. tostring(Battle._phase))
  result(Battle._phase == "command" or Battle._phase == "linkwait",
    "the battle reached the first command menu")
  U.shot(game, DIR .. "/link_battle_03_command_menu.png")

  guard = 0
  while guard < 1800 and turnsAnswered < 1 and Battle.isActive() do
    U.tap(game, "a")
    waitP(12)
    guard = guard + 12
  end
  print("[driver] turn exchange: answered=" .. tostring(turnsAnswered)
    .. " phase=" .. tostring(Battle._phase))
  result(turnsAnswered >= 1, "this player's chosen action went out over the cable")
  guard = 0
  while guard < 600 and Battle._phase == "linkwait" do
    waitP(10)
    guard = guard + 10
  end
  result(Battle._phase ~= "linkwait",
    "and the turn only resolved once the other machine answered")
  result((Battle.getState() or st).turn >= 1, "turn 1 is resolved on both machines")
  waitP(60)
  U.shot(game, DIR .. "/link_battle_04_turn_one.png")

  -- pokefirered/data/battle_scripts_1.s:2837 switchhandleorder BS_FAINTED
  local function enemySlot()
    local s2 = Battle.getState()
    return s2 and s2.enemy and s2.enemy.partyIndex
  end
  guard = 0
  while guard < 1800 and Battle.isActive() and enemySlot() ~= 2 do
    U.tap(game, "a")
    waitP(12)
    guard = guard + 12
  end
  print("[driver] peer replacement: sent=" .. tostring(peerSentSwitch)
    .. " slot=" .. tostring(enemySlot()) .. " phase=" .. tostring(Battle._phase))
  result(peerSentSwitch, "the other machine had to name its own replacement over the cable")
  result(enemySlot() == 2, "and the mon it named is the one that came out")
  local SwitchSeq = require("src.core.game3.battle.switch_seq")
  local function switchStep()
    local steps = SwitchSeq._steps
    local step = steps and steps[SwitchSeq._i]
    return step and step.kind
  end
  guard = 0
  while guard < 600 and switchStep() ~= "healthbox" do
    waitP(1)
    guard = guard + 1
  end
  waitP(19)
  local foeMon = require("src.core.game3.battle.anim").present("enemy")
  local M5 = require("src.ui.game3.message")
  local page5 = (M5.isOpen() and tostring(M5.currentPage() or "")) or ""
  result(foeMon ~= nil and foeMon.visible and page5:find("sent out", 1, true) ~= nil,
    "EKANS is on the field under the send-out line with no A press (" .. page5:gsub("\n", " ") .. ")")
  U.still(game, DIR .. "/link_battle_05_peer_replacement.png")

  local PartyMenu = require("src.ui.game3.party_menu")
  local SummaryMenu = require("src.ui.game3.summary_menu")
  guard = 0
  local lastReport = 0
  local sentOutNext, endShot = false, false
  while guard < 6000 and Battle.isActive() do
    -- pokefirered/data/battle_scripts_1.s:2984 BattleScript_LinkBattleWonOrLost
    if not endShot and Battle._phase == "ending" then
      local M = require("src.ui.game3.message")
      local page = (M.isOpen() and M.isWaiting() and tostring(M.currentPage() or "")) or ""
      if page:find("defeated", 1, true) or page:find("lost", 1, true) or page:find("draw", 1, true) then
        endShot = true
        U.still(game, DIR .. "/link_battle_06_link_battle_end.png")
      end
    end
    -- pokefirered/src/battle_controller_player.c:1486 ChooseNextMon
    if PartyMenu.isOpen and PartyMenu.isOpen() then
      if SummaryMenu.isOpen and SummaryMenu.isOpen() then
        U.tap(game, "b")
      elseif PartyMenu.mode == "message" then
        U.tap(game, "a")
      elseif PartyMenu.mode == "action" then
        -- pokefirered/src/party_menu.c:3760 SEND OUT is the first row
        U.tap(game, "a")
        sentOutNext = true
      elseif PartyMenu.cursor ~= 2 then
        U.tap(game, "down")
      else
        U.tap(game, "a")
      end
      waitP(10)
      guard = guard + 10
    else
      U.tap(game, "a")
      waitP(12)
      guard = guard + 12
    end
    if guard - lastReport >= 900 then
      lastReport = guard
      local s2 = Battle.getState()
      print("[driver] still battling: phase=" .. tostring(Battle._phase)
        .. " turn=" .. tostring(s2 and s2.turn) .. " answered=" .. tostring(turnsAnswered)
        .. " party=" .. tostring(PartyMenu.isOpen and PartyMenu.isOpen())
        .. " mode=" .. tostring(PartyMenu.mode) .. " cursor=" .. tostring(PartyMenu.cursor)
        .. " mon=" .. tostring(s2 and s2.player and s2.player.mon and s2.player.mon.species)
        .. " hp=" .. tostring(s2 and s2.player and s2.player.mon and s2.player.mon.hp)
        .. "/" .. tostring(s2 and s2.enemy and s2.enemy.mon and s2.enemy.mon.hp))
    end
  end
  print("[driver] battle over: sentOutNext=" .. tostring(sentOutNext)
    .. " peerSwitches=" .. tostring(peerSwitches) .. " turns=" .. tostring(turnsAnswered)
    .. " lead=" .. tostring(session.party[1] and session.party[1].species)
    .. " hp=" .. tostring(session.party[1] and session.party[1].hp)
    .. "/" .. tostring(session.party[1] and session.party[1].maxHp))
  result(not Battle.isActive(), "the link battle ran to its end")
  local log = BattleUi.log() or {}
  local sawExp, sawEnd = false, false
  for i, line in ipairs(log) do
    if line:find("EXP. Points", 1, true) then sawExp = true end
    if line:find("BLUE!", 1, true) then sawEnd = true end
    if i > #log - 6 then print("[driver] log: " .. (line:gsub("\n", " "))) end
  end
  result(not sawExp, "no EXP was handed out, as in every link battle")
  result(sawEnd, "the battle ended on the link battle string naming BLUE")
  waitP(120)

  -- pokefirered/src/cable_club.c:776 CB2_ReturnFromCableClubBattle
  result(#(session.party or {}) == 2, "LoadPlayerParty handed the pre-link party back")
  local records = session.linkBattleRecords or {}
  result(records[1] ~= nil and records[1].name == "BLUE",
    "the battle record screen now has a row for BLUE")
  local stats = session.gameStats or {}
  local total = (tonumber(stats.linkBattleWins) or 0) + (tonumber(stats.linkBattleLosses) or 0)
    + (tonumber(stats.linkBattleDraws) or 0)
  result(total == 1, "and one GAME_STAT_LINK_BATTLE_* was counted")

  waitP(60)
  U.shot(game, DIR .. "/link_battle_07_back_at_the_seat.png")

  Link.reset()
  finish()
end
