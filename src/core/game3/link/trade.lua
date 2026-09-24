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
  CONFIRM = "game3_trade_confirm",
  COMMIT = "trade_commit",
  ABORT = "trade_abort",
}

LT.loopbackCommit = false
LT.completed = 0

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
LT._sentPacked = nil
LT._digest = nil
LT._peerDigest = nil
LT._committed = false
LT._lastCommitN = 0
LT._lastRound = 0
LT._staleRound = nil
LT._peerPacked = nil
LT._peerLost = false
LT._journal = nil
LT._resolver = nil
LT._applied = {}
LT.journalIo = nil
LT.outcomeClient = nil
LT.OUTCOME_PATH = "/trade/outcome"
LT.OUTCOME_SECONDS = 10
LT.OUTCOME_RETRY_SECONDS = 5
LT.JOURNAL_TTL = 24 * 60 * 60

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

local function protocol()
  return require("src.link.Protocol")
end

function LT.unpackMon(packed)
  return protocol().unpackMon3(nil, packed, { strict = true })
end

-- pokefirered/src/trade.c:1435 Trade_Memcpy
function LT.packParty(s)
  local party, list = partyOf(s), {}
  for i = 1, math.min(LT.PARTY_SIZE, #party) do list[#list + 1] = i end
  return protocol().packParty3(party, list)
end

function LT.unpackParty(list)
  local out = {}
  if type(list) ~= "table" then return out end
  for i = 1, math.min(LT.PARTY_SIZE, #list) do
    local mon, why = LT.unpackMon(list[i])
    if not mon then return nil, why end
    out[i] = mon
  end
  return out
end

local function sanitizedMon(block)
  return require("src.link.Wire").sanitize(block).mon
end

local function journalIo()
  if LT.journalIo then return LT.journalIo end
  local SaveData = require("src.core.SaveData")
  local fs = SaveData.persistenceFs()
  if not fs then return nil end
  local path = SaveData.saveFilename():gsub("%.lua$", "") .. "_trade.lua"
  return {
    read = function()
      if not fs.getInfo(path) then return nil end
      return (fs.read(path))
    end,
    write = function(text) return fs.write(path, text) end,
    remove = function()
      if not fs.getInfo(path) then return true end
      return fs.remove(path)
    end,
  }
end

local function readJournal()
  local store = journalIo()
  if not store then return {} end
  local ok, text = pcall(store.read)
  if not ok or type(text) ~= "string" or text == "" then return {} end
  local okD, data = pcall(require("src.core.SaveData").decode, text)
  if not okD or type(data) ~= "table" or type(data.entries) ~= "table" then return {} end
  return data.entries
end

local function writeJournal(entries)
  local store = journalIo()
  if not store then return nil end
  if #entries == 0 then
    local ok, removed = pcall(store.remove)
    return ok and removed ~= false
  end
  local okE, text = pcall(require("src.core.SaveData").encode, { v = 1, entries = entries })
  if not okE then return false end
  local ok, wrote = pcall(store.write, text)
  return ok and wrote ~= false and wrote ~= nil
end

local function journalAdd(entry)
  local list, kept = readJournal(), {}
  for _, e in ipairs(list) do
    if not (e.room == entry.room and e.digest == entry.digest) then kept[#kept + 1] = e end
  end
  kept[#kept + 1] = entry
  return writeJournal(kept)
end

local function journalDrop(room, digest)
  local list, kept = readJournal(), {}
  for _, e in ipairs(list) do
    if not (e.room == room and e.digest == digest) then kept[#kept + 1] = e end
  end
  if #kept == #list then return true end
  return writeJournal(kept)
end

local function dropOwnJournal()
  local j = LT._journal
  LT._journal = nil
  if j then journalDrop(j.room, j.digest) end
end

function LT.pendingTrades()
  return readJournal()
end

local function relayRoom(live)
  local t = live and live._transport
  if not (t and t.relay) then return nil end
  if type(t.target) == "string" and t.target ~= "" then return t.target end
  local room = type(t.room) == "function" and t:room() or nil
  local id = type(room) == "table" and (room.room or room.code) or nil
  return type(id) == "string" and id or nil
end

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
    party = LT.packParty(s),
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

local function resetExchange()
  LT._sent = nil
  LT._received = nil
  LT._peerBlock = nil
  LT._monSent = false
  LT._swapped = false
  LT._sentPacked = nil
  LT._digest = nil
  LT._peerDigest = nil
  LT._committed = false
  LT._saveAsked = false
  LT._released = false
  LT._peerLost = false
end

-- pokefirered/src/trade.c:821 CB2_StartCreateTradeMenu
function LT.startMenu(opts)
  opts = opts or {}
  LT.state = "menu"
  LT.unionRoom = false
  LT.cursor = nil
  LT.partnerCursor = nil
  LT.peer = nil
  LT.peerParty = {}
  LT._peerPacked = nil
  LT.lastRefusal = nil
  LT.lastResult = nil
  resetExchange()
  LT._confirmSent = false
  if LT._barrierLink ~= link().link then
    LT._barrierLink = link().link
    LT._lastCommitN = 0
    LT._lastRound = 0
    LT._staleRound = nil
  end
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

-- pokefirered/src/trade.c:2094 CB_HandleTradeCanceled
function LT.resumeMenu()
  if LT.state ~= "canceled" then return false end
  local live = lk()
  if live then
    live:update(0)
    while live:take(LT.MSG.MON) do end
    while live:take(LT.MSG.CONFIRM) do end
  end
  LT.state = "menu"
  LT.cursor = nil
  LT.partnerCursor = nil
  LT.lastRefusal = nil
  clearStatuses()
  resetExchange()
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

local EXCHANGING = { exchange = true, commit_wait = true }

local function cancelTo(state, result)
  if LT._committed then return false end
  if EXCHANGING[LT.state] and not LT.loopbackCommit then
    LT._staleRound = (LT._lastRound or 0) + 1
  end
  dropOwnJournal()
  if LT.unionRoom then
    trade().clearPartnerMail()
    resetExchange()
    clearStatuses()
    LT.state = "off"
    LT.lastResult = result
    local cb = LT._onDone
    LT._onDone = nil
    if cb then cb(nil, result) end
    return true
  end
  LT.state = state
  LT.lastResult = result
  clearStatuses()
  if LT._sent or LT._peerBlock then trade().clearPartnerMail() end
  resetExchange()
  return true
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
  elseif cmd == LT.LINKCMD.PLAYER_CANCEL_TRADE and EXCHANGING[LT.state] then
    cancelTo("canceled", "trade_canceled")
  elseif cmd == LT.LINKCMD.BOTH_CANCEL_TRADE and not LT._committed then
    cancelTo("exit", "both_canceled")
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
  if EXCHANGING[LT.state] or LT._committed then return false end
  local s = session()
  local slot = (LT.cursor or 0) + 1
  local mon = partyOf(s)[slot]
  if not mon then
    cancelTo("canceled", "no_mon")
    return false
  end
  resetExchange()
  LT.state = "exchange"
  LT._sent = mon
  -- pokefirered/src/union_room.c:1718 SendBlock(0, &gPlayerParty[monId], sizeof(struct Pokemon))
  local block = {
    type = LT.MSG.MON,
    mon = protocol().packMon3(mon),
    -- pokefirered/src/union_room.c:1733 gLinkPartnerMail
    mail = mailRecordFor(s, mon),
    name = (s and s.name) or "PLAYER",
    trainerId = tonumber(s and (s.trainerId or s.id)) or 0,
  }
  LT._sentPacked = sanitizedMon(block)
  LT._monSent = send(block)
  LT.tryConfirm()
  return true
end

local function shownMon(mon)
  local P = protocol()
  local list = LT._peerPacked
  local shown = type(list) == "table" and list[(tonumber(LT.partnerCursor) or 0) + 1] or nil
  local a = type(shown) == "table" and P.wireMon3(shown) or nil
  local b = type(mon) == "table" and P.wireMon3(mon) or nil
  return a ~= nil and b ~= nil and P.canonical(a) == P.canonical(b)
end

local function noteRound(msg)
  local n = math.floor(tonumber(type(msg) == "table" and msg.n or nil) or 0)
  if n > (LT._lastRound or 0) then LT._lastRound = n end
end

function LT.tryConfirm()
  if LT.state ~= "exchange" then return false end
  local block = LT._peerBlock
  if not (block and LT._monSent and LT._sentPacked) then return false end
  -- pokefirered/src/trade.c:1951
  if not LT.unionRoom and not shownMon(block.mon) then
    LT.lastRefusal = "not the POKéMON that was shown"
    sendCmd(LT.LINKCMD.PLAYER_CANCEL_TRADE, 0)
    cancelTo("canceled", "bad_mon")
    return false
  end
  local received, why = LT.unpackMon(block.mon)
  if not received then
    LT.lastRefusal = why
    sendCmd(LT.LINKCMD.PLAYER_CANCEL_TRADE, 0)
    cancelTo("canceled", "bad_mon")
    return false
  end
  local mine, theirs = LT._sentPacked, block.mon
  local digest
  if LT.isLeader() then
    digest = protocol().tradeDigest(mine, theirs)
  else
    digest = protocol().tradeDigest(theirs, mine)
  end
  LT._received = received
  LT._digest = digest
  local live = lk()
  if live then
    local drained = live:take(LT.MSG.COMMIT) or live:take(LT.MSG.ABORT)
    while drained do
      noteRound(drained)
      drained = live:take(LT.MSG.COMMIT) or live:take(LT.MSG.ABORT)
    end
  end
  local room = relayRoom(live)
  if room then
    local wrote = journalAdd({
      room = room, digest = digest, at = os.time(),
      sent = mine, mon = theirs, mail = block.mail,
      name = block.name or (LT.peer and LT.peer.name),
      unionRoom = LT.unionRoom and true or false,
    })
    if wrote == false then
      LT.lastRefusal = "journal"
      sendCmd(LT.LINKCMD.PLAYER_CANCEL_TRADE, 0)
      cancelTo("canceled", "journal")
      return false
    end
    if wrote then LT._journal = { room = room, digest = digest } end
  end
  LT.state = "commit_wait"
  send({ type = LT.MSG.CONFIRM, digest = digest })
  LT.tryLoopbackCommit()
  return true
end

function LT.tryLoopbackCommit()
  if not (LT.loopbackCommit and LT.state == "commit_wait" and LT._peerDigest) then return false end
  local n = LT._lastCommitN + 1
  if LT._peerDigest == LT._digest then
    return LT.onCommit({ n = n, digests = { LT._digest, LT._peerDigest } })
  end
  return LT.onAbort({ n = n, why = "digest" })
end

function LT.onCommit(msg)
  if LT.state ~= "commit_wait" or LT._committed then return false end
  local d = type(msg) == "table" and msg.digests or nil
  if type(d) ~= "table" or d[1] ~= LT._digest or d[2] ~= LT._digest then return false end
  local n = tonumber(msg.n)
  if n and math.floor(n) <= LT._lastCommitN then return false end
  LT._committed = true
  LT._lastCommitN = math.max(LT._lastCommitN, math.floor(tonumber(msg.n) or 0))
  LT._staleRound = nil
  LT.state = "committed"
  LT.tryPlayScene()
  return true
end

function LT.onAbort(msg)
  if LT.state ~= "commit_wait" or LT._committed then return false end
  local n = tonumber(type(msg) == "table" and msg.n or nil)
  if n and n <= LT._lastCommitN then return false end
  if LT._staleRound and n and n <= LT._staleRound then
    LT._staleRound = nil
    send({ type = LT.MSG.CONFIRM, digest = LT._digest })
    return false
  end
  local why = type(msg) == "table" and msg.why or nil
  local ok = cancelTo("canceled", type(why) == "string" and why or "aborted")
  LT._staleRound = nil
  return ok
end

local function writeSave()
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
    local ok, wrote = pcall(function() return game:saveGame() end)
    okSave = ok and wrote ~= false
  end
  if not (okPersist and okSave) then
    print("[link] post-trade save failed (persist=" .. tostring(okPersist)
      .. ", save=" .. tostring(okSave) .. ")")
  end
  return okPersist and okSave
end

local function saveAfterTrade()
  if LT._saveAsked then return end
  LT._saveAsked = true
  local ok = writeSave()
  LT._saveFailed = not ok
  if ok then dropOwnJournal() end
  scene().saveDone()
  return ok
end

-- pokefirered/src/trade_scene.c:779 CB2_LinkTrade
function LT.tryPlayScene()
  if LT.state ~= "committed" then return false end
  -- pokefirered/src/trade.c:1302
  local Menu = package.loaded["src.ui.game3.link_trade_menu"]
  if Menu and Menu.isOpen and Menu.isOpen() then return false end
  local block = LT._peerBlock
  if not (block and LT._sent and LT._received) then return false end
  local s = session()
  local Trade = trade()
  local Mail = mail()
  local received = LT._received
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
      local sent = LT._sent
      if Trade.tradeMons(s, slot, received) then
        LT._swapped = true
        local key, args = Trade.noteLinkTrade(s, sent, received, peerName, LT.unionRoom)
        -- pokefirered/src/trade_scene.c:2599
        if key then require("src.core.game3.quest_log_recorder").event(s, key, args) end
      end
      -- pokefirered/src/trade_scene.c:2344 LINKCMD_CONFIRM_FINISH_TRADE
      sendCmd(LT.LINKCMD.CONFIRM_FINISH_TRADE, 0)
      if LT._peerLost then Scene.peerConfirmed() end
    end,
    -- pokefirered/src/trade_scene.c:2311 CB2_TryLinkTradeEvolution
    onEvolve = function()
      if not LT._swapped then return end
      Trade.tryTradeEvolution(received, s)
    end,
  })
  return true
end

-- pokefirered/src/trade_scene.c:2572
function LT.trySave()
  if LT.state ~= "scene" or LT._saveAsked then return false end
  local Scene = scene()
  if Scene.phase() ~= "link_standby" then return false end
  Scene.linkTaskDone()
  saveAfterTrade()
  return true
end

-- pokefirered/src/trade_scene.c:2566 CB2_SaveAndEndTrade
function LT.finishTrade()
  LT.state = "done"
  LT.completed = LT.completed + 1
  local cb = LT._onDone
  LT._onDone = nil
  local received = LT._received
  LT._committed = false
  LT._journal = nil
  if LT.unionRoom then
    union().resetTrade()
    local U = package.loaded["src.core.game3.link.union_room"]
    if U and U.state ~= "off" then U.state = "main" end
  end
  if cb then
    cb(received)
  elseif not LT.unionRoom and lk() then
    -- pokefirered/src/trade.c:1322
    LT.startMenu()
  end
  return true
end

-- pokefirered/src/cable_club.c:1002 Task_WaitForLinkPlayerConnection
function LT.abort(reason)
  if LT.state == "off" then return false end
  local Scene = scene()
  if LT._committed then
    LT._peerLost = true
    if LT._released then return false end
    LT._released = true
    Scene.peerConfirmed()
    return false
  end
  if Scene.isOpen() then Scene.cancel() end
  trade().clearPartnerMail()
  local pending = LT._journal ~= nil
  LT._journal = nil
  LT.state = "off"
  LT.lastResult = reason or "peer_dropped"
  resetExchange()
  clearStatuses()
  local cb = LT._onDone
  LT._onDone = nil
  if cb then cb(nil, reason) end
  if pending then LT.resumePending() end
  return true
end

local TAKES_PARTY = { menu = true, ready_wait = true, confirm = true, confirm_wait = true, canceled = true }

local function takeParty(party)
  local list, why = LT.unpackParty(party.party)
  if not list then
    LT.lastRefusal = why
    sendCmd(LT.LINKCMD.BOTH_CANCEL_TRADE, 0)
    cancelTo("exit", "bad_party")
    return false
  end
  LT.peer = {
    name = party.name,
    trainerId = tonumber(party.trainerId) or 0,
    gender = tonumber(party.gender) or 0,
    version = tonumber(party.version) or 0,
    progressFlags = tonumber(party.progressFlags) or 0,
  }
  LT.peerParty = list
  LT._peerPacked = party.party
  return true
end

function LT.pump()
  local live = lk()
  if not live then return false end
  live:update(0)
  if not live.isOpen or not live:isOpen() then return false end
  local party = TAKES_PARTY[LT.state] and live:take(LT.MSG.PARTY) or nil
  while party do
    takeParty(party)
    party = TAKES_PARTY[LT.state] and live:take(LT.MSG.PARTY) or nil
  end
  if EXCHANGING[LT.state] then
    local block = live:take(LT.MSG.MON)
    while block do
      LT._peerBlock = block
      block = live:take(LT.MSG.MON)
    end
    local confirm = live:take(LT.MSG.CONFIRM)
    while confirm do
      if type(confirm.digest) == "string" then LT._peerDigest = confirm.digest end
      confirm = live:take(LT.MSG.CONFIRM)
    end
  end
  if LT.state == "exchange" then LT.tryConfirm() end
  if LT.state == "commit_wait" then
    local commit = live:take(LT.MSG.COMMIT)
    while commit and LT.state == "commit_wait" do
      LT.onCommit(commit)
      noteRound(commit)
      commit = LT.state == "commit_wait" and live:take(LT.MSG.COMMIT) or nil
    end
    local abort = LT.state == "commit_wait" and live:take(LT.MSG.ABORT) or nil
    while abort and LT.state == "commit_wait" do
      LT.onAbort(abort)
      noteRound(abort)
      abort = LT.state == "commit_wait" and live:take(LT.MSG.ABORT) or nil
    end
    LT.tryLoopbackCommit()
  end
  local cmd = live:take(LT.MSG.CMD)
  while cmd do
    if LT.isLeader() then LT.leaderRead(cmd) else LT.followerRead(cmd) end
    cmd = live:take(LT.MSG.CMD)
  end
  return true
end

local function peerOffline(live)
  local t = live and live._transport
  if not (t and t.relay and type(t.peerOnline) == "function") then return false end
  local mine = tonumber(live.seat) or (live.role == "guest" and 1 or 0)
  local ok, online = pcall(t.peerOnline, t, 1 - mine)
  return ok and online == false
end

function LT.update(dt)
  if LT.state == "off" then return false end
  LT.pump()
  if LT.state == "committed" then LT.tryPlayScene() end
  if LT.state == "scene" then
    local Scene = scene()
    if peerOffline(lk()) then Scene.peerConfirmed() end
    if Scene.isOpen() and not (type(love) == "table" and love.graphics) then
      Scene.step()
    end
    LT.trySave()
  end
  if not lk() and LT.state ~= "done" then
    LT.abort("peer_dropped")
    if not LT._committed then return false end
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
  LT.startMenu({ onDone = onDone, screen = false })
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

local function outcomeClient()
  if LT.outcomeClient then return LT.outcomeClient end
  if not LT._syncClient then
    LT._syncClient = require("src.sync.SyncClient").new()
  end
  return LT._syncClient
end

function LT.fetchOutcome(entry)
  local okC, client = pcall(outcomeClient)
  if not okC or not client then return { status = "error", entry = entry } end
  local okR, handle = pcall(client.send, client, "GET", LT.OUTCOME_PATH, nil, {
    noAuth = true, maxSeconds = LT.OUTCOME_SECONDS,
    params = { room = entry.room, digest = entry.digest },
  })
  if not okR or handle == nil then return { status = "error", entry = entry } end
  return { status = "pending", client = client, handle = handle, entry = entry }
end

function LT.pollOutcome(job)
  if job.status ~= "pending" then return job.status, job.outcome end
  local ok, res = pcall(job.client.poll, job.client, job.handle)
  if not ok or type(res) ~= "table" then res = { status = "error" } end
  if res.status == "pending" then return "pending" end
  pcall(job.client.release, job.client, job.handle)
  job.handle = nil
  local outcome = res.status == "ok" and type(res.data) == "table" and res.data.outcome or nil
  if outcome ~= "commit" and outcome ~= "abort" and outcome ~= "open" then
    job.status = "error"
    return "error"
  end
  job.status, job.outcome = "ok", outcome
  return "ok", outcome
end

local function sameMon(mon, packed)
  return type(mon) == "table" and type(packed) == "table"
    and (tonumber(mon.personality) or 0) == tonumber(packed.personality)
    and (tonumber(mon.otId) or 0) % 65536 == tonumber(packed.otId)
end

-- pokefirered/src/trade_scene.c:2533
function LT.applyPending(s, entry)
  local party = partyOf(s)
  local slot
  for i = 1, LT.PARTY_SIZE do
    if sameMon(party[i], entry.sent) then
      slot = i
      break
    end
  end
  if not slot then return false, "missing" end
  local received, why = LT.unpackMon(entry.mon)
  if not received then return false, why end
  local Trade, Mail = trade(), mail()
  local sent = party[slot]
  Trade.clearPartnerMail()
  if type(entry.mail) == "table" then
    local id = tonumber(received.mail)
    if not id or id == Mail.MAIL_NONE then id = 0 end
    received.mail = id
    Trade.setPartnerMail(id, entry.mail)
  else
    received.mail = nil
  end
  local swapped = Trade.tradeMons(s, slot - 1, received)
  Trade.clearPartnerMail()
  if not swapped then return false, "swap" end
  local key, args = Trade.noteLinkTrade(s, sent, received, entry.name, entry.unionRoom)
  if key then require("src.core.game3.quest_log_recorder").event(s, key, args) end
  -- pokefirered/src/trade_scene.c:2311
  local Evolution = require("src.core.game3.evolution")
  local target = Evolution.tradeTarget(received, s)
  if target then Evolution.apply(received, target, s, s.bag, "trade") end
  return true
end

local function entryKey(e)
  return tostring(e.room) .. ":" .. tostring(e.digest)
end

function LT.settlePending(s, entry, outcome)
  if outcome == "abort" then
    journalDrop(entry.room, entry.digest)
    return "abort"
  end
  if outcome ~= "commit" or LT._applied[entryKey(entry)] then return nil end
  local ok, why = LT.applyPending(s, entry)
  if not ok then
    print("[link] pending trade " .. entryKey(entry) .. " not applied: " .. tostring(why))
    journalDrop(entry.room, entry.digest)
    return "dropped"
  end
  LT._applied[entryKey(entry)] = true
  if writeSave() then journalDrop(entry.room, entry.digest) end
  return "commit"
end

function LT.stepResolver(st, dt)
  local Runtime = package.loaded["src.core.game3.runtime"]
  local game = Runtime and Runtime._game
  local s = Runtime and Runtime.getSession and Runtime.getSession()
  if not (game and s and game.phase == "field") or LT.isActive() then return false end
  if st.job then
    local status, outcome = LT.pollOutcome(st.job)
    if status == "pending" then return false end
    local entry = st.job.entry
    st.job = nil
    st.fails = status == "ok" and 0 or math.min((st.fails or 0) + 1, 6)
    st.wait = LT.OUTCOME_RETRY_SECONDS * 2 ^ st.fails
    if status == "ok" then LT.settlePending(s, entry, outcome) end
  end
  if (st.wait or 0) > 0 then
    st.wait = st.wait - (tonumber(dt) or 0)
    return false
  end
  local now, open = os.time(), {}
  for _, e in ipairs(readJournal()) do
    if now - (tonumber(e.at) or 0) > LT.JOURNAL_TTL then
      journalDrop(e.room, e.digest)
    elseif not LT._applied[entryKey(e)] then
      open[#open + 1] = e
    end
  end
  if #open == 0 then
    LT._resolver = nil
    return true
  end
  st.index = ((st.index or 0) % #open) + 1
  st.job = LT.fetchOutcome(open[st.index])
  return false
end

function LT.resumePending()
  if LT._resolver then return LT._resolver end
  if #readJournal() == 0 then return nil end
  local st = {}
  LT._resolver = require("src.core.game3.task").spawn(function(_, dt)
    local ok, done = pcall(LT.stepResolver, st, dt)
    if not ok then
      print("[link] pending trade resolver failed: " .. tostring(done))
      LT._resolver = nil
      return true
    end
    return done
  end)
  return LT._resolver
end

function LT.reset()
  if LT._journal then
    LT._journal = nil
    if not LT._committed then LT.resumePending() end
  end
  LT.state = "off"
  LT.cursor = nil
  LT.partnerCursor = nil
  LT.peer = nil
  LT.peerParty = {}
  LT._peerPacked = nil
  LT.unionRoom = false
  LT.lastRefusal = nil
  LT.lastResult = nil
  LT.seat = nil
  resetExchange()
  LT._partySent = false
  LT._onDone = nil
  LT._confirmSent = false
  LT._lastCommitN = 0
  LT._lastRound = 0
  LT._staleRound = nil
  LT._barrierLink = nil
  clearStatuses()
end

return LT
