local LT = {}

-- pokefirered/include/link.h:54
LT.LINKCMD = {
  READY_TO_TRADE = 0xAABB,
  READY_FINISH_TRADE = 0xABCD,
  INIT_BLOCK = 0xBBBB,
  READY_CANCEL_TRADE = 0xBBCC,
  START_TRADE = 0xCCDD,
  CONFIRM_FINISH_TRADE = 0xDCBA,
  SET_MONS_TO_TRADE = 0xDDDD,
  PLAYER_CANCEL_TRADE = 0xDDEE,
  REQUEST_CANCEL = 0xEEAA,
  BOTH_CANCEL_TRADE = 0xEEBB,
  PARTNER_CANCEL_TRADE = 0xEECC,
}

-- pokefirered/include/link.h:88
LT.LINKTYPE = {
  TRADE = 0x1111,
  TRADE_CONNECTING = 0x1122,
  TRADE_SETUP = 0x1133,
  TRADE_DISCONNECTED = 0x1144,
}

-- pokefirered/src/trade.c:133
LT.STATUS = { NONE = 0, READY = 1, CANCEL = 2 }

-- pokefirered/include/constants/trade.h:32
LT.PLAYER_MON_INVALID = 0
LT.BOTH_MONS_VALID = 1
LT.PARTNER_MON_INVALID = 2

-- pokefirered/src/cable_club.c:525 TryTradeLinkup
LT.LINKUP = { min = 2, max = 2, linkType = LT.LINKTYPE.TRADE_SETUP }

LT.MSG = {
  CMD = "game3_trade_cmd",
  PARTY = "game3_trade_party",
  MON = "game3_trade_mon",
}

-- pokefirered/include/constants/global.h:78
LT.PARTY_SIZE = 6
-- pokefirered/include/constants/game_stat.h:54
LT.GAME_STAT_NUM_UNION_ROOM_BATTLES = 50
LT.VAR_0x8005 = 0x8005

LT.state = "off"
LT.cursor = nil
LT.partnerCursor = nil
LT.peer = nil
LT.peerParty = {}
LT.unionRoom = false
LT.lastRefusal = nil
LT.lastResult = nil
LT.playerSelectStatus = LT.STATUS.NONE
LT.partnerSelectStatus = LT.STATUS.NONE
LT.playerConfirmStatus = LT.STATUS.NONE
LT.partnerConfirmStatus = LT.STATUS.NONE
LT._sent = nil
LT._received = nil
LT._peerBlock = nil
LT._monSent = false
LT._swapped = false
LT._partySent = false
LT._onDone = nil
LT._confirmSent = false
LT._saveAsked = false

local function link()
  return require("src.core.game3.link")
end

local function battle()
  return require("src.core.game3.link.battle")
end

local function union()
  return require("src.core.game3.link.union_room")
end

local function trade()
  return require("src.core.game3.scripting.natives_trade")
end

local function scene()
  return require("src.core.game3.trade_scene")
end

local function mail()
  return require("src.core.game3.mail")
end

local function session()
  return link().session()
end

local function copyTable(value, depth)
  if type(value) ~= "table" or (depth or 0) > 8 then return value end
  local out = {}
  for k, v in pairs(value) do out[k] = copyTable(v, (depth or 0) + 1) end
  return out
end

LT.copy = copyTable

local function partyOf(s)
  return (s and s.party) or {}
end

local function lk()
  local live = link().link
  if live and live.isOpen and live:isOpen() then return live end
  return nil
end

-- pokefirered/src/link.c:965 GetMultiplayerId
function LT.isLeader()
  local live = link().link
  return not (live and live.role == "guest")
end

function LT.isActive()
  return LT.state ~= "off" and LT.state ~= "done"
end

local function send(message)
  local live = lk()
  if not live then return false end
  live:send(message)
  return true
end

local function sendCmd(cmd, cursor)
  return send({ type = LT.MSG.CMD, cmd = cmd, cursor = cursor })
end

LT.sendCmd = sendCmd

-- pokefirered/src/trade.c:1435 Trade_Memcpy
local function partyDigest(s)
  local out = {}
  for i = 1, LT.PARTY_SIZE do
    local mon = partyOf(s)[i]
    if mon then
      out[i] = {
        species = tonumber(mon.species) or 0,
        level = tonumber(mon.level) or 0,
        hp = tonumber(mon.hp) or 0,
        isEgg = mon.isEgg and true or false,
        isBadEgg = mon.isBadEgg and true or false,
        fatefulEncounter = mon.fatefulEncounter,
        personality = tonumber(mon.personality) or 0,
        nickname = mon.nickname or mon.name,
      }
    end
  end
  return out
end

LT.partyDigest = partyDigest

-- pokefirered/src/trade.c:778 InitTradeMenu
function LT.sendParty()
  local s = session()
  local Party = require("src.core.game3.party")
  local version = (Party.metGame and Party.metGame()) or 0
  local flags = 0
  local okD, PokedexData = pcall(require, "src.core.game3.pokedex_data")
  if okD and PokedexData and PokedexData.isNationalUnlocked then
    local okU, unlocked = pcall(PokedexData.isNationalUnlocked, s, s and s.dex)
    if okU and unlocked then flags = 1 end
  end
  local ok = send({
    type = LT.MSG.PARTY,
    party = partyDigest(s),
    name = (s and s.name) or "PLAYER",
    trainerId = tonumber(s and (s.trainerId or s.id)) or 0,
    gender = (s and (s.gender == "female" or s.gender == 1)) and 1 or 0,
    version = version,
    progressFlags = flags,
  })
  LT._partySent = ok
  return ok
end

function LT.peerInfo()
  return LT.peer
end

-- pokefirered/src/trade.c:2745 CanTradeSelectedMon
function LT.canTradeSelectedMon(slot)
  local s = session()
  local Trade = trade()
  local partner = LT.peer and { version = LT.peer.version, progressFlags = LT.peer.progressFlags }
  return Trade.canTradeSelectedMon(partyOf(s), (tonumber(slot) or 1) - 1, {
    session = s,
    partner = partner,
  })
end

-- pokefirered/src/trade.c:1951 CheckValidityOfTradeMons
function LT.checkValidityOfTradeMons(slot, partnerSlot)
  local s = session()
  local party = partyOf(s)
  slot = tonumber(slot) or 1
  local alive = 0
  for i = 1, LT.PARTY_SIZE do
    local mon = party[i]
    if i ~= slot and mon and (tonumber(mon.species) or 0) ~= 0
        and (tonumber(mon.hp) or 0) > 0 and not mon.isEgg then
      alive = alive + 1
    end
  end
  local peerMon = LT.peerParty[(tonumber(partnerSlot) or 1)]
  local species = tonumber(peerMon and peerMon.species) or 0
  -- pokefirered/include/constants/species.h:155
  if (species == 151 or species == 410) and peerMon and peerMon.fatefulEncounter == false then
    return LT.PARTNER_MON_INVALID
  end
  if alive == 0 then return LT.PLAYER_MON_INVALID end
  return LT.BOTH_MONS_VALID
end

local function clearStatuses()
  LT.playerSelectStatus = LT.STATUS.NONE
  LT.partnerSelectStatus = LT.STATUS.NONE
  LT.playerConfirmStatus = LT.STATUS.NONE
  LT.partnerConfirmStatus = LT.STATUS.NONE
end

-- pokefirered/src/trade.c:821 CB2_StartCreateTradeMenu
function LT.startMenu(opts)
  opts = opts or {}
  LT.state = "menu"
  LT.unionRoom = false
  LT.cursor = nil
  LT.partnerCursor = nil
  LT.peerParty = {}
  LT.lastRefusal = nil
  LT.lastResult = nil
  LT._sent = nil
  LT._received = nil
  LT._peerBlock = nil
  LT._monSent = false
  LT._swapped = false
  LT._confirmSent = false
  LT._saveAsked = false
  LT._released = false
  LT._onDone = opts.onDone
  clearStatuses()
  local live = lk()
  if live then live.linkType = LT.LINKTYPE.TRADE end
  LT.sendParty()
  link().startPump()
  -- pokefirered/src/trade.c:821 CB2_StartCreateTradeMenu
  if opts.screen ~= false and type(love) == "table" and love.graphics then
    local okM, Menu = pcall(require, "src.ui.game3.link_trade_menu")
    if okM and type(Menu) == "table" and Menu.show then Menu.show() end
  end
  return true
end

-- pokefirered/src/trade.c:1811 SetReadyToTrade
function LT.offer(slot)
  if LT.state ~= "menu" then return false, "not_in_menu" end
  local Trade = trade()
  local code = LT.canTradeSelectedMon(slot)
  if code ~= Trade.CAN_TRADE_MON then
    LT.lastRefusal = code
    return false, code
  end
  LT.lastRefusal = nil
  LT.cursor = math.floor(tonumber(slot) or 1) - 1
  LT.state = "ready_wait"
  if LT.isLeader() then
    LT.playerSelectStatus = LT.STATUS.READY
    LT.leaderHandleCommunication()
  else
    sendCmd(LT.LINKCMD.READY_TO_TRADE, LT.cursor)
  end
  return true
end

-- pokefirered/src/trade.c:2043 CB_ProcessCancelTradeInput
function LT.cancelSelect()
  if LT.state ~= "menu" and LT.state ~= "ready_wait" then return false end
  LT.state = "ready_wait"
  if LT.isLeader() then
    LT.playerSelectStatus = LT.STATUS.CANCEL
    LT.leaderHandleCommunication()
  else
    sendCmd(LT.LINKCMD.REQUEST_CANCEL, 0)
  end
  return true
end

-- pokefirered/src/trade.c:1976 CommunicateWhetherMonCanBeTraded
function LT.confirm(yes)
  if LT.state ~= "confirm" then return false end
  local status = LT.STATUS.CANCEL
  if yes then
    local validity = LT.checkValidityOfTradeMons(
      (LT.cursor or 0) + 1, (LT.partnerCursor or 0) + 1)
    LT.lastResult = validity
    if validity == LT.BOTH_MONS_VALID then status = LT.STATUS.READY end
  else
    LT.lastResult = nil
  end
  LT.state = "confirm_wait"
  LT._confirmSent = true
  local cmd = (status == LT.STATUS.READY) and LT.LINKCMD.INIT_BLOCK
    or LT.LINKCMD.READY_CANCEL_TRADE
  if LT.isLeader() then
    LT.playerConfirmStatus = status
    LT.leaderHandleCommunication()
  else
    sendCmd(cmd, 0)
  end
  return true
end

local function cancelTo(state, result)
  LT.state = state
  LT.lastResult = result
  clearStatuses()
end

-- pokefirered/src/trade.c:1681 Leader_HandleCommunication
function LT.leaderHandleCommunication()
  if not LT.isLeader() then return false end
  if LT.playerSelectStatus ~= LT.STATUS.NONE and LT.partnerSelectStatus ~= LT.STATUS.NONE then
    local player, partner = LT.playerSelectStatus, LT.partnerSelectStatus
    if player == LT.STATUS.READY and partner == LT.STATUS.READY then
      sendCmd(LT.LINKCMD.SET_MONS_TO_TRADE, LT.cursor)
      LT.playerSelectStatus = LT.STATUS.NONE
      LT.partnerSelectStatus = LT.STATUS.NONE
      LT.state = "confirm"
    elseif player == LT.STATUS.READY and partner == LT.STATUS.CANCEL then
      sendCmd(LT.LINKCMD.PARTNER_CANCEL_TRADE, 0)
      cancelTo("canceled", "partner_canceled")
    elseif player == LT.STATUS.CANCEL and partner == LT.STATUS.READY then
      sendCmd(LT.LINKCMD.PLAYER_CANCEL_TRADE, 0)
      cancelTo("canceled", "player_canceled")
    elseif player == LT.STATUS.CANCEL and partner == LT.STATUS.CANCEL then
      sendCmd(LT.LINKCMD.BOTH_CANCEL_TRADE, 0)
      cancelTo("exit", "both_canceled")
    end
  end
  if LT.playerConfirmStatus ~= LT.STATUS.NONE and LT.partnerConfirmStatus ~= LT.STATUS.NONE then
    if LT.playerConfirmStatus == LT.STATUS.READY
        and LT.partnerConfirmStatus == LT.STATUS.READY then
      sendCmd(LT.LINKCMD.START_TRADE, 0)
      LT.playerConfirmStatus = LT.STATUS.NONE
      LT.partnerConfirmStatus = LT.STATUS.NONE
      LT.beginTrade()
    elseif LT.playerConfirmStatus == LT.STATUS.CANCEL
        or LT.partnerConfirmStatus == LT.STATUS.CANCEL then
      sendCmd(LT.LINKCMD.PLAYER_CANCEL_TRADE, 0)
      cancelTo("canceled", "trade_canceled")
    end
  end
  return true
end

-- pokefirered/src/trade.c:1593 Leader_ReadLinkBuffer
function LT.leaderRead(msg)
  local cmd = tonumber(msg and msg.cmd)
  if cmd == LT.LINKCMD.REQUEST_CANCEL then
    LT.partnerSelectStatus = LT.STATUS.CANCEL
  elseif cmd == LT.LINKCMD.READY_TO_TRADE then
    LT.partnerCursor = math.floor(tonumber(msg.cursor) or 0)
    LT.partnerSelectStatus = LT.STATUS.READY
  elseif cmd == LT.LINKCMD.INIT_BLOCK then
    LT.partnerConfirmStatus = LT.STATUS.READY
  elseif cmd == LT.LINKCMD.READY_CANCEL_TRADE then
    LT.partnerConfirmStatus = LT.STATUS.CANCEL
  elseif cmd == LT.LINKCMD.CONFIRM_FINISH_TRADE then
    scene().peerConfirmed()
  end
  LT.leaderHandleCommunication()
  return true
end

-- pokefirered/src/trade.c:1637 Follower_ReadLinkBuffer
function LT.followerRead(msg)
  local cmd = tonumber(msg and msg.cmd)
  if cmd == LT.LINKCMD.BOTH_CANCEL_TRADE then
    cancelTo("exit", "both_canceled")
  elseif cmd == LT.LINKCMD.PARTNER_CANCEL_TRADE then
    cancelTo("canceled", "partner_canceled")
  elseif cmd == LT.LINKCMD.SET_MONS_TO_TRADE then
    LT.partnerCursor = math.floor(tonumber(msg.cursor) or 0)
    LT.state = "confirm"
  elseif cmd == LT.LINKCMD.START_TRADE then
    LT.beginTrade()
  elseif cmd == LT.LINKCMD.PLAYER_CANCEL_TRADE then
    cancelTo("canceled", "trade_canceled")
  elseif cmd == LT.LINKCMD.CONFIRM_FINISH_TRADE then
    scene().peerConfirmed()
  end
  return true
end

local function mailRecordFor(s, mon)
  local Mail = mail()
  local id = tonumber(mon and mon.mail)
  if not id or id == Mail.MAIL_NONE then return nil end
  local record = Mail.slot(s, id)
  if not record or Mail.isEmpty(record) then return nil end
  return copyTable(record)
end

-- pokefirered/src/trade.c:1302 CB_WaitToStartTrade
function LT.beginTrade()
  if LT.state == "exchange" or LT.state == "scene" then return false end
  local s = session()
  local slot = (LT.cursor or 0) + 1
  local mon = partyOf(s)[slot]
  if not mon then
    cancelTo("canceled", "no_mon")
    return false
  end
  LT.state = "exchange"
  LT._sent = mon
  LT._swapped = false
  -- pokefirered/src/union_room.c:1718 SendBlock(0, &gPlayerParty[monId], sizeof(struct Pokemon))
  LT._monSent = send({
    type = LT.MSG.MON,
    mon = copyTable(mon),
    -- pokefirered/src/union_room.c:1733 gLinkPartnerMail
    mail = mailRecordFor(s, mon),
    name = (s and s.name) or "PLAYER",
    trainerId = tonumber(s and (s.trainerId or s.id)) or 0,
  })
  LT.tryPlayScene()
  return true
end

local function saveAfterTrade()
  if LT._saveAsked then return end
  LT._saveAsked = true
  local Runtime = package.loaded["src.core.game3.runtime"]
  local game = Runtime and Runtime._game
  local mod = Runtime and Runtime._mod
  local okPersist = true
  if game and mod then
    local okB, Bridge = pcall(require, "src.core.game3.bridge")
    if okB and Bridge and Bridge.persistSessionOnly then
      okPersist = select(1, pcall(Bridge.persistSessionOnly, mod, game))
    end
  end
  local okSave = true
  if game and game.saveGame then
    okSave = select(1, pcall(function() game:saveGame() end))
  end
  if not (okPersist and okSave) then
    LT._saveFailed = true
    print("[link] post-trade save failed (persist=" .. tostring(okPersist)
      .. ", save=" .. tostring(okSave) .. ")")
  else
    LT._saveFailed = false
  end
  scene().saveDone()
  return okPersist and okSave
end

-- pokefirered/src/trade_scene.c:779 CB2_LinkTrade
function LT.tryPlayScene()
  if LT.state ~= "exchange" then return false end
  local block = LT._peerBlock
  if not (block and LT._monSent and LT._sent) then return false end
  local s = session()
  local Trade = trade()
  local Mail = mail()
  local received = copyTable(block.mon)
  Trade.clearPartnerMail()
  if block.mail then
    local id = tonumber(received.mail)
    if not id or id == Mail.MAIL_NONE then id = 0 end
    received.mail = id
    -- pokefirered/src/trade_scene.c:2488 gLinkPartnerMail[0] = mail
    Trade.setPartnerMail(id, block.mail)
  else
    received.mail = nil
  end
  LT._received = received
  LT.state = "scene"
  LT._peerBlock = nil
  local peerName = block.name or (LT.peer and LT.peer.name)
  local Scene = scene()
  local slot = LT.cursor or 0
  Scene.play(LT._sent, received, function()
    LT.finishTrade()
  end, {
    -- pokefirered/src/trade_scene.c:1230 TradeBufferOTnameAndNicknames
    peer = { name = peerName, id = block.trainerId or (LT.peer and LT.peer.trainerId) },
    linkHost = LT.isLeader(),
    awaitPeer = true,
    awaitSave = true,
    uiDriven = (type(love) == "table" and love.graphics) and true or false,
    -- pokefirered/src/trade_scene.c:2533 TradeMons
    onSwap = function()
      if Trade.tradeMons(s, slot, received) then LT._swapped = true end
      -- pokefirered/src/trade_scene.c:2344 LINKCMD_CONFIRM_FINISH_TRADE
      sendCmd(LT.LINKCMD.CONFIRM_FINISH_TRADE, 0)
      Scene.linkTaskDone()
      saveAfterTrade()
    end,
    -- pokefirered/src/trade_scene.c:2311 CB2_TryLinkTradeEvolution
    onEvolve = function()
      if not LT._swapped then return end
      Trade.tryTradeEvolution(received, s)
    end,
  })
  return true
end

-- pokefirered/src/trade_scene.c:2566 CB2_SaveAndEndTrade
function LT.finishTrade()
  LT.state = "done"
  local cb = LT._onDone
  LT._onDone = nil
  if LT.unionRoom then
    union().resetTrade()
    local U = package.loaded["src.core.game3.link.union_room"]
    if U and U.state ~= "off" then U.state = "main" end
  end
  if cb then cb(LT._received) end
  return true
end

-- pokefirered/src/cable_club.c:1002 Task_WaitForLinkPlayerConnection
function LT.abort(reason)
  if LT.state == "off" then return false end
  local Scene = scene()
  if LT.state == "scene" and LT._swapped then
    if LT._released then return false end
    LT._released = true
    Scene.peerConfirmed()
    Scene.linkTaskDone()
    saveAfterTrade()
    return false
  end
  if Scene.isOpen() then Scene.cancel() end
  trade().clearPartnerMail()
  LT.state = "off"
  LT.lastResult = reason or "peer_dropped"
  LT._sent = nil
  LT._received = nil
  LT._peerBlock = nil
  LT._monSent = false
  LT._swapped = false
  LT._released = false
  clearStatuses()
  local cb = LT._onDone
  LT._onDone = nil
  if cb then cb(nil, reason) end
  return true
end

function LT.pump()
  local live = lk()
  if not live then return false end
  live:update(0)
  if not live.isOpen or not live:isOpen() then return false end
  local party = live:take(LT.MSG.PARTY)
  while party do
    LT.peer = {
      name = party.name,
      trainerId = tonumber(party.trainerId) or 0,
      gender = tonumber(party.gender) or 0,
      version = tonumber(party.version) or 0,
      progressFlags = tonumber(party.progressFlags) or 0,
    }
    LT.peerParty = party.party or {}
    party = live:take(LT.MSG.PARTY)
  end
  local block = live:take(LT.MSG.MON)
  while block do
    LT._peerBlock = block
    block = live:take(LT.MSG.MON)
  end
  local cmd = live:take(LT.MSG.CMD)
  while cmd do
    if LT.isLeader() then LT.leaderRead(cmd) else LT.followerRead(cmd) end
    cmd = live:take(LT.MSG.CMD)
  end
  return true
end

function LT.update(dt)
  if LT.state == "off" then return false end
  LT.pump()
  if LT.state == "exchange" then
    if LT._peerBlock then LT.tryPlayScene() end
  end
  if LT.state == "scene" then
    local Scene = scene()
    if Scene.isOpen() and not (type(love) == "table" and love.graphics) then
      Scene.step()
    end
  end
  if not lk() and LT.state ~= "done" then
    LT.abort("peer_dropped")
    return false
  end
  return LT.state ~= "off" and LT.state ~= "done"
end

-- pokefirered/src/cable_club.c:525 TryTradeLinkup
function LT.tryTradeLinkup(ctx, adapters)
  local L = link()
  local LB = battle()
  LB.mode = L.USING.TRADE_CENTER
  LB.unionRoom = false
  LT.state = "off"
  return LB.createLinkupTask(ctx, adapters, LT.LINKUP)
end

-- pokefirered/src/cable_club.c:945 EnterTradeSeat
function LT.enterTradeSeat(ctx, adapters)
  local L = link()
  local LB = battle()
  LT.seat = L.getVar(ctx, LT.VAR_0x8005)
  local live = lk()
  if not live then
    LT.state = "off"
    return false
  end
  live.linkType = LT.LINKTYPE.TRADE
  -- pokefirered/src/cable_club.c:839 SetInCableClubSeat
  live:send({ type = LB.MSG.SEAT, seat = LT.seat })
  LT.state = "seat"
  local seated = false
  local Natives = require("src.core.game3.scripting.natives")
  local yielded = Natives.yieldHost(ctx, adapters, function() end)
  if not yielded then
    LT.state = "off"
    return false
  end
  ctx.nativePoll = function()
    local now = lk()
    if not now then
      -- pokefirered/src/cable_club.c:856 CABLE_SEAT_FAILED
      LT.state = "off"
      return true
    end
    now:update(0)
    if not seated and now:take(LB.MSG.SEAT) then seated = true end
    if not seated then return false end
    LT.startMenu()
    return true
  end
  return true
end

-- pokefirered/src/cable_club.c:958 StartWiredCableClubTrade
function LT.startWiredCableClubTrade(ctx, adapters)
  if not lk() then
    LT.state = "off"
    return false
  end
  LT.startMenu()
  return false
end

-- pokefirered/src/union_room.c:4600 RegisterTradeMonAndGetIsEgg
function LT.registerTradeMonAndGetIsEgg(slot)
  local record = union().trade()
  local mon = partyOf(session())[(tonumber(slot) or 1)]
  if not mon then return false end
  record.playerSpecies = mon.isEgg and 412 or (tonumber(mon.species) or 0)
  record.playerLevel = tonumber(mon.level) or 0
  record.playerPersonality = tonumber(mon.personality) or 0
  return mon.isEgg and true or false
end

-- pokefirered/src/union_room.c:4611 RegisterTradeMon
function LT.registerTradeMon(slot)
  local record = union().trade()
  local mon = partyOf(session())[(tonumber(slot) or 1)]
  if not mon then return false end
  record.species = mon.isEgg and 412 or (tonumber(mon.species) or 0)
  record.level = tonumber(mon.level) or 0
  record.personality = tonumber(mon.personality) or 0
  return true
end

-- pokefirered/src/union_room.c:4618 GetPartyPositionOfRegisteredMon
function LT.partyPositionOfRegisteredMon(record, leader)
  record = record or union().trade()
  local species, personality
  if leader then
    species, personality = record.playerSpecies, record.playerPersonality
  else
    species, personality = record.species, record.personality
  end
  local party = partyOf(session())
  for i = 1, LT.PARTY_SIZE do
    local mon = party[i]
    if mon then
      local monSpecies = mon.isEgg and 412 or (tonumber(mon.species) or 0)
      if (tonumber(mon.personality) or 0) == (tonumber(personality) or 0)
          and monSpecies == (tonumber(species) or 0) then
        return i - 1
      end
    end
  end
  return 0
end

-- pokefirered/src/union_room.c:1713 Task_StartUnionRoomTrade
function LT.startUnionRoomTrade(onDone)
  local live = lk()
  if not live then return false, "no_link" end
  local record = union().trade()
  local slot = LT.partyPositionOfRegisteredMon(record, LT.isLeader())
  local s = session()
  if not partyOf(s)[slot + 1] then return false, "no_mon" end
  LT.startMenu({ onDone = onDone })
  LT.unionRoom = true
  LT.cursor = slot
  LT.partnerCursor = LT.PARTY_SIZE
  -- pokefirered/src/union_room.c:1725 IncrementGameStat(GAME_STAT_NUM_UNION_ROOM_BATTLES)
  if type(s) == "table" then
    if type(s.gameStats) ~= "table" then s.gameStats = {} end
    local id = LT.GAME_STAT_NUM_UNION_ROOM_BATTLES
    s.gameStats[id] = math.min(0xFFFFFF, (tonumber(s.gameStats[id]) or 0) + 1)
  end
  LT.beginTrade()
  return true
end

function LT.reset()
  LT.state = "off"
  LT.cursor = nil
  LT.partnerCursor = nil
  LT.peer = nil
  LT.peerParty = {}
  LT.unionRoom = false
  LT.lastRefusal = nil
  LT.lastResult = nil
  LT.seat = nil
  LT._sent = nil
  LT._received = nil
  LT._peerBlock = nil
  LT._monSent = false
  LT._swapped = false
  LT._partySent = false
  LT._onDone = nil
  LT._confirmSent = false
  LT._saveAsked = false
  LT._released = false
  clearStatuses()
end

return LT
