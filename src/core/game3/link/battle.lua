local Rng = require("src.core.game3.rng")

local LB = {}

-- pokefirered/include/constants/battle.h:47
LB.BATTLE_TYPE = {
  DOUBLE = 0x1,
  LINK = 0x2,
  IS_MASTER = 0x4,
  TRAINER = 0x8,
  MULTI = 0x40,
}

-- pokefirered/include/constants/battle.h:83
LB.B_OUTCOME = {
  WON = 1,
  LOST = 2,
  DREW = 3,
  LINK_BATTLE_RAN = 128,
}

-- pokefirered/include/global.h:238
LB.RECORDS_COUNT = 5
LB.RECORD_MAX = 9999

-- pokefirered/include/link.h:88
LB.LINKTYPE = {
  BATTLE = 0x2211,
  SINGLE_BATTLE = 0x2233,
  DOUBLE_BATTLE = 0x2244,
  MULTI_BATTLE = 0x2255,
  RECORD_MIX_BEFORE = 0x3311,
}

LB.MSG = {
  LINKUP = "game3_battle_linkup",
  SETUP = "game3_battle_setup",
  ACTION = "game3_battle_action",
  SWITCH = "game3_battle_switch",
  SEAT = "game3_battle_seat",
  OUTCOME = "game3_battle_outcome",
}

-- pokefirered/src/cable_club.c:493 TryBattleLinkup
LB.PLAYERS = {
  [1] = { min = 2, max = 2, linkType = LB.LINKTYPE.SINGLE_BATTLE },
  [2] = { min = 2, max = 2, linkType = LB.LINKTYPE.DOUBLE_BATTLE },
  [5] = { min = 4, max = 4, linkType = LB.LINKTYPE.MULTI_BATTLE },
}

-- pokefirered/src/cable_club.c:532 TryRecordMixLinkup
LB.RECORD_MIX = { min = 2, max = 4, linkType = LB.LINKTYPE.RECORD_MIX_BEFORE }

-- pokefirered/src/cable_club.c:482 TryLinkTimeout
LB.LINKUP_TICKS = 600
LB.VAR_0x8005 = 0x8005

LB.state = "off"
LB.mode = nil
LB.seed = nil
LB.seat = nil
LB.linkup = nil
LB.peer = nil
LB.unionRoom = false
LB.outcome = nil
LB.headless = nil
LB.fade = nil
LB._actions = {}
LB._switches = {}
LB._sent = {}
LB._started = false

local function link()
  return require("src.core.game3.link")
end

local function union()
  return package.loaded["src.core.game3.link.union_room"]
end

local function natives()
  return require("src.core.game3.scripting.natives")
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

LB.copy = copyTable

-- pokefirered/src/random.c:15 ISO_RANDOMIZE1
function LB.makeRng(seed)
  local value = math.floor(tonumber(seed) or 0) % 4294967296
  local function word()
    value = (Rng.mulU32(value, 1103515245) + 24691) % 4294967296
    return math.floor(value / 65536) % 65536
  end
  return function(lo, hi)
    if lo == nil and hi == nil then return word() / 65536 end
    if hi == nil then
      lo = math.floor(tonumber(lo) or 1)
      if lo <= 0 then return 0 end
      return 1 + (word() % lo)
    end
    lo = math.floor(tonumber(lo) or 0)
    hi = math.floor(tonumber(hi) or lo)
    if hi < lo then lo, hi = hi, lo end
    local span = hi - lo + 1
    if span <= 0 then return lo end
    return lo + (word() % span)
  end
end

function LB.dealSeed()
  return Rng.Random32() % 4294967296
end

local function partyOf(s)
  return (s and s.party) or {}
end

local function speciesOf(mon)
  return tonumber(mon and (mon.species or mon.speciesId)) or 0
end

-- pokefirered/src/party_menu.c:5674 GetMonForBattleEntry
function LB.eligible(mon)
  if type(mon) ~= "table" then return false end
  local sp = speciesOf(mon)
  if sp == 0 or sp == 412 then return false end
  if mon.isEgg or mon.egg then return false end
  return true
end

-- pokefirered/data/scripts/cable_club.inc:847
local function hasBadEgg(s)
  for _, mon in ipairs(partyOf(s)) do
    if mon.isBadEgg == true then return true end
  end
  return false
end

-- pokefirered/src/script_pokemon_util.c:119 DoesPartyHaveEnigmaBerry
local ITEM_ENIGMA_BERRY = 175
local function hasEnigmaBerry(s)
  for _, mon in ipairs(partyOf(s)) do
    if tonumber(mon.heldItem or mon.item) == ITEM_ENIGMA_BERRY then return true end
  end
  return false
end

-- pokefirered/src/union_room.c:4565 HasAtLeastTwoMonsOfLevel30OrLower
local function twoUnderCap(s, cap)
  local n = 0
  for _, mon in ipairs(partyOf(s)) do
    if LB.eligible(mon) and (tonumber(mon.level) or 0) <= cap then n = n + 1 end
  end
  return n >= 2
end

function LB.validateParty(s, mode, opts)
  opts = opts or {}
  s = s or session()
  if hasBadEgg(s) then return false, "bad_egg" end
  local usable = 0
  for _, mon in ipairs(partyOf(s)) do
    if LB.eligible(mon) then usable = usable + 1 end
  end
  if usable < 1 then return false, "no_mons" end
  if opts.unionRoom then
    -- pokefirered/data/scripts/cable_club.inc:806
    if hasEnigmaBerry(s) then return false, "enigma_berry" end
    if not twoUnderCap(s, (union() and union().MAX_LEVEL) or 30) then
      return false, "level_cap"
    end
    return true, nil
  end
  local L = link()
  -- pokefirered/data/scripts/cable_club.inc:252 HasEnoughMonsForDoubleBattle
  if mode == L.USING.DOUBLE_BATTLE or mode == L.USING.MULTI_BATTLE then
    local Party = require("src.core.game3.party")
    if Party.monsStateToDoubles(partyOf(s)) ~= Party.PLAYER_HAS_TWO_USABLE_MONS then
      return false, "need_two_mons"
    end
  end
  return true, nil
end

function LB.isActive()
  return LB.state == "battle" or LB.state == "setup"
end

function LB.localPlayer()
  local s = session()
  return {
    name = (s and s.name) or "PLAYER",
    trainerId = tonumber(s and (s.trainerId or s.id)) or 0,
    gender = (s and (s.gender == "female" or s.gender == 1)) and 1 or 0,
  }
end

-- pokefirered/src/script_pokemon_util.c:197 ReducePlayerPartyToThree
function LB.battleParty(s)
  s = s or session()
  local party = partyOf(s)
  local okT, Tower = pcall(require, "src.core.game3.trainer_tower")
  local order = okT and Tower and Tower.selectedOrder and Tower.selectedOrder(s) or nil
  if type(order) == "table" and (tonumber(order[1]) or 0) ~= 0 then
    local out = {}
    for i = 1, #order do
      local slot = tonumber(order[i]) or 0
      if slot > 0 and party[slot] then out[#out + 1] = copyTable(party[slot]) end
    end
    if #out > 0 then return out end
  end
  local out = {}
  for i = 1, 6 do
    if party[i] then out[#out + 1] = copyTable(party[i]) end
  end
  return out
end

local function sendSetup()
  local lk = link().link
  if not (lk and lk:isOpen()) then return false end
  local me = LB.localPlayer()
  lk:send({
    type = LB.MSG.SETUP,
    seed = LB.seed,
    mode = LB.mode,
    unionRoom = LB.unionRoom and true or false,
    name = me.name,
    trainerId = me.trainerId,
    gender = me.gender,
    party = LB.battleParty(),
  })
  return true
end

LB.sendSetup = sendSetup

function LB.foeFrom(setup)
  local party = {}
  for _, mon in ipairs((setup and setup.party) or {}) do
    party[#party + 1] = copyTable(mon)
  end
  if #party == 0 then return nil end
  local foe = copyTable(party[1])
  foe.party = party
  -- pokefirered/src/cable_club.c:672 TRAINER_LINK_OPPONENT is no gTrainers row
  foe.trainerId = nil
  foe.trainerClass = nil
  foe.link = true
  foe.name = setup and setup.name or nil
  return foe
end

-- pokefirered/include/constants/trainers.h:156 TRAINER_PIC_RED / TRAINER_PIC_LEAF
LB.TRAINER_PIC_RED = 135
LB.TRAINER_PIC_LEAF = 136

-- pokefirered/src/battle_controller_link_opponent.c:1172
function LB.peerPicId(setup)
  if tonumber(setup and setup.gender) == 1 then return LB.TRAINER_PIC_LEAF end
  return LB.TRAINER_PIC_RED
end

-- pokefirered/src/link.c:965 GetMultiplayerId
function LB.multiplayerId()
  local lk = link().link
  return (lk and lk.role == "guest") and 1 or 0
end

-- pokefirered/src/battle_main.c:909 BATTLE_TYPE_IS_MASTER
function LB.isMaster()
  return LB.multiplayerId() == 0
end

-- pokefirered/src/cable_club.c:628 Task_StartWiredCableClubBattle
function LB.battleFlags(mode)
  local L = link()
  local flags = LB.BATTLE_TYPE.TRAINER + LB.BATTLE_TYPE.LINK
  if LB.isMaster() then flags = flags + LB.BATTLE_TYPE.IS_MASTER end
  if mode == L.USING.DOUBLE_BATTLE then
    flags = flags + LB.BATTLE_TYPE.DOUBLE
  elseif mode == L.USING.MULTI_BATTLE then
    flags = flags + LB.BATTLE_TYPE.DOUBLE + LB.BATTLE_TYPE.MULTI
  end
  return flags
end

-- pokefirered/include/constants/songs.h:272
LB.MUS_RS_VS_GYM_LEADER = 265
LB.MUS_RS_VS_TRAINER = 266

-- pokefirered/src/cable_club.c:656 Task_StartWiredCableClubBattle
function LB.battleSong(setup)
  local lk = link().link
  local leader = (lk and lk.role == "host") and LB.localPlayer().trainerId
    or (tonumber(setup and setup.trainerId) or 0)
  if leader % 2 == 1 then return LB.MUS_RS_VS_GYM_LEADER end
  return LB.MUS_RS_VS_TRAINER
end

function LB.beginBattle(setup, onDone)
  local L = link()
  local foe = LB.foeFrom(setup)
  if not foe then return false, "peer_has_no_party" end
  LB.peer = {
    name = setup.name,
    trainerId = tonumber(setup.trainerId) or 0,
    gender = tonumber(setup.gender) or 0,
  }
  LB.state = "battle"
  LB._actions = {}
  LB._switches = {}
  LB._sent = {}
  LB._started = true
  local flags = LB.battleFlags(LB.mode)
  local double = (flags % (LB.BATTLE_TYPE.DOUBLE * 2)) >= LB.BATTLE_TYPE.DOUBLE
  -- pokefirered/src/cable_club.c:669 ReducePlayerPartyToThree
  if LB.mode == L.USING.MULTI_BATTLE then
    local okT, Tower = pcall(require, "src.core.game3.trainer_tower")
    if okT and Tower and Tower.reducePartyToThree then Tower.reducePartyToThree(session()) end
  end
  local BattleBridge = require("src.core.game3.battle_bridge")
  local rt = package.loaded["src.core.game3.runtime"]
  return BattleBridge.start(rt and rt._mod, L.game(), foe, {
    link = true,
    linkFlags = flags,
    -- pokefirered/src/battle_controllers.c:148 the master's own mon is battler 0 on both machines
    linkMaster = LB.isMaster(),
    double = double,
    unionRoom = LB.unionRoom,
    trainerId = nil,
    rng = LB.makeRng(LB.seed),
    peerName = setup.name,
    trainerName = setup.name,
    trainerPicId = LB.peerPicId(setup),
    song = LB.battleSong(setup),
    headless = LB.headless,
    fade = LB.fade,
    done = function(result)
      LB.finish(result)
      if onDone then onDone(result) end
    end,
  })
end

-- pokefirered/src/battle_main.c:3226 the action block the other machine reads
local function wireAction(action)
  return {
    kind = action and action.kind or "move",
    slot = action and tonumber(action.slot) or nil,
    move = action and action.move or nil,
    target = action and tonumber(action.target) or nil,
    itemId = action and tonumber(action.itemId) or nil,
    partySlot = action and tonumber(action.partySlot) or nil,
  }
end

-- pokefirered/src/battle_main.c:3226
function LB.sendAction(turn, action)
  local lk = link().link
  turn = math.floor(tonumber(turn) or 0)
  if LB._sent[turn] then return true end
  if not (lk and lk:isOpen()) then return false end
  LB._sent[turn] = true
  local msg = wireAction(action)
  msg.type = LB.MSG.ACTION
  msg.turn = turn
  lk:send(msg)
  return true
end

-- pokefirered/src/battle_main.c:3226 HandleTurnActionSelectionState
function LB.sendActionList(turn, list)
  local lk = link().link
  turn = math.floor(tonumber(turn) or 0)
  if LB._sent[turn] then return true end
  if not (lk and lk:isOpen()) then return false end
  LB._sent[turn] = true
  local actions = {}
  for i = 1, 2 do actions[i] = wireAction(list and list[i]) end
  lk:send({ type = LB.MSG.ACTION, turn = turn, kind = "list", actions = actions })
  return true
end

-- pokefirered/data/battle_scripts_1.s:2837
function LB.sendSwitch(slot)
  local lk = link().link
  if not (lk and lk:isOpen()) then return false end
  lk:send({ type = LB.MSG.SWITCH, slot = math.floor(tonumber(slot) or 1) })
  return true
end

function LB.peerSwitch()
  LB.pumpActions()
  if #LB._switches == 0 then return nil end
  return table.remove(LB._switches, 1)
end

function LB.linkOpen()
  local lk = link().link
  return (lk and lk:isOpen()) and true or false
end

function LB.pumpActions()
  local lk = link().link
  if not (lk and lk:isOpen()) then return end
  lk:update(0)
  if not lk:isOpen() then return end
  local msg = lk:take(LB.MSG.ACTION)
  while msg do
    local turn = math.floor(tonumber(msg.turn) or 0)
    LB._actions[turn] = msg
    msg = lk:take(LB.MSG.ACTION)
  end
  local sw = lk:take(LB.MSG.SWITCH)
  while sw do
    LB._switches[#LB._switches + 1] = math.floor(tonumber(sw.slot) or 1)
    sw = lk:take(LB.MSG.SWITCH)
  end
end

function LB.peerAction(turn)
  LB.pumpActions()
  return LB._actions[math.floor(tonumber(turn) or 0)]
end

function LB.forgetAction(turn)
  LB._actions[math.floor(tonumber(turn) or 0)] = nil
end

-- pokefirered/src/battle_records.c:295 GetLinkBattleRecordTotalBattles
local function totalBattles(entry)
  return (tonumber(entry.wins) or 0) + (tonumber(entry.losses) or 0)
    + (tonumber(entry.draws) or 0)
end

local function clamp(n)
  n = math.floor(tonumber(n) or 0)
  if n < 0 then return 0 end
  if n > LB.RECORD_MAX then return LB.RECORD_MAX end
  return n
end

function LB.records(s)
  s = s or session()
  if type(s) ~= "table" then return {} end
  if type(s.linkBattleRecords) ~= "table" then s.linkBattleRecords = {} end
  return s.linkBattleRecords
end

-- pokefirered/src/battle_records.c:313 SortLinkBattleRecords
local function sortRecords(records)
  table.sort(records, function(a, b)
    return totalBattles(a) > totalBattles(b)
  end)
end

-- pokefirered/src/battle_records.c:333 UpdateLinkBattleRecord
local function bumpRecord(entry, outcome)
  if outcome == LB.B_OUTCOME.WON then
    entry.wins = clamp((tonumber(entry.wins) or 0) + 1)
  elseif outcome == LB.B_OUTCOME.LOST then
    entry.losses = clamp((tonumber(entry.losses) or 0) + 1)
  elseif outcome == LB.B_OUTCOME.DREW then
    entry.draws = clamp((tonumber(entry.draws) or 0) + 1)
  end
end

-- pokefirered/src/battle_records.c:355 UpdateLinkBattleGameStats
local GAME_STAT = { [1] = "linkBattleWins", [2] = "linkBattleLosses", [3] = "linkBattleDraws" }
local function bumpGameStat(s, outcome)
  local key = GAME_STAT[outcome]
  if not (key and type(s) == "table") then return end
  if type(s.gameStats) ~= "table" then s.gameStats = {} end
  local n = tonumber(s.gameStats[key]) or 0
  if n < LB.RECORD_MAX then s.gameStats[key] = n + 1 end
end

-- pokefirered/src/battle_records.c:376 AddOpponentLinkBattleRecord
function LB.addOpponentRecord(s, name, trainerId, outcome)
  s = s or session()
  local records = LB.records(s)
  bumpGameStat(s, outcome)
  sortRecords(records)
  name = tostring(name or "")
  trainerId = math.floor(tonumber(trainerId) or 0)
  local found
  for _, entry in ipairs(records) do
    if entry.name == name and (tonumber(entry.trainerId) or 0) == trainerId then
      found = entry
      break
    end
  end
  if not found then
    if #records >= LB.RECORDS_COUNT then
      found = records[LB.RECORDS_COUNT]
    else
      found = {}
      records[#records + 1] = found
    end
    found.name = name
    found.trainerId = trainerId
    found.wins, found.losses, found.draws = 0, 0, 0
  end
  bumpRecord(found, outcome)
  sortRecords(records)
  return found
end

-- pokefirered/src/battle_records.c:411 IncTrainerCardWinCount
local function bumpTrainerCard(s, outcome)
  if type(s) ~= "table" then return end
  if type(s.trainerCard) ~= "table" then s.trainerCard = {} end
  local card = s.trainerCard
  if outcome == LB.B_OUTCOME.WON then
    card.linkBattleWins = clamp((tonumber(card.linkBattleWins) or 0) + 1)
  elseif outcome == LB.B_OUTCOME.LOST then
    card.linkBattleLosses = clamp((tonumber(card.linkBattleLosses) or 0) + 1)
  end
end

function LB.outcomeCode(result)
  if result == "win" then return LB.B_OUTCOME.WON end
  if result == "lose" or result == "whiteout" or result == "blackout" then
    return LB.B_OUTCOME.LOST
  end
  if result == "draw" then return LB.B_OUTCOME.DREW end
  if result == "run" then return LB.B_OUTCOME.DREW end
  return LB.B_OUTCOME.DREW
end

-- pokefirered/src/cable_club.c:776 CB2_ReturnFromCableClubBattle
function LB.finish(result)
  if not LB._started then return false end
  LB._started = false
  local L = link()
  local s = session()
  local outcome = LB.outcomeCode(result)
  LB.outcome = outcome
  local ctx, adapters = L.vmCtx()
  -- pokefirered/src/load_save.c:170 LoadPlayerParty
  L.callSpecial(ctx, adapters, 0x28)
  -- pokefirered/src/load_save.c:239 SavePlayerBag
  L.savePlayerBag()
  if s then s.battleOutcome = outcome end
  -- pokefirered/src/battle_records.c:443 UpdatePlayerLinkBattleRecords
  if LB.mode ~= L.USING.MULTI_BATTLE and not LB.unionRoom then
    bumpTrainerCard(s, outcome)
    LB.addOpponentRecord(s, LB.peer and LB.peer.name, LB.peer and LB.peer.trainerId, outcome)
    -- pokefirered/src/cable_club.c:782 CB2_ReturnFromDirectLinkBattle -> Special_UpdateTrainerFansAfterLinkBattle
    local okF, TFC = pcall(require, "src.core.game3.trainer_fan_club")
    if okF and TFC and TFC.updateTrainerFansAfterLinkBattle then
      TFC.updateTrainerFansAfterLinkBattle(s, ctx, outcome)
    end
  end
  local lk = L.link
  if lk and lk:isOpen() then
    lk:send({ type = LB.MSG.OUTCOME, outcome = outcome })
  end
  LB.state = "done"
  if LB.unionRoom then
    -- pokefirered/src/cable_club.c:761 CB2_ReturnFromUnionRoomBattle
    local U = union()
    if U then U.state = "main" end
  end
  return true
end

-- pokefirered/src/cable_club.c:1002 Task_WaitForLinkPlayerConnection
function LB.peerDropped()
  if not LB._started then return false end
  local Battle = package.loaded["src.core.game3.battle"]
  if Battle and Battle.isActive and Battle.isActive() then
    Battle.abort("draw")
  else
    LB.finish("draw")
  end
  link().closeLink("peer_dropped")
  return true
end

function LB.update(dt)
  if LB.state == "off" then return false end
  local L = link()
  local lk = L.link
  if LB.state == "battle" then
    LB.pumpActions()
    if not (lk and lk:isOpen()) then
      LB.peerDropped()
      return LB.state ~= "off"
    end
  end
  if LB.state == "linkup" and lk and lk:isReady() then
    LB.state = "seat"
  end
  return LB.state ~= "off" and LB.state ~= "done"
end

-- pokefirered/src/link.c:1069 GetLinkPlayerCount_2
function LB.playerCount()
  local lk = link().link
  return (lk and lk:isOpen()) and 2 or 1
end

-- pokefirered/src/cable_club.c:222 CreateLinkupTask
function LB.createLinkupTask(ctx, adapters, spec)
  local L = link()
  local function report(code)
    LB.linkup = code
    L.setResult(ctx, code)
    return code
  end
  report(L.LINKUP.ONGOING)
  LB.state = "linkup"
  LB.seed = nil
  local announced = false
  local lk = L.link
  if lk then
    lk.linkType = spec.linkType
    -- pokefirered/src/cable_club.c:318 Task_LinkupExchangeDataWithLeader
    lk:send({ type = LB.MSG.LINKUP, linkType = spec.linkType, players = spec.min })
    announced = true
  else
    -- pokefirered/src/cable_club.c:222 CreateLinkupTask waits for the other machine
    L.beginConnect({ linkType = spec.linkType })
  end
  local ticks = 0
  local Natives = natives()
  local yielded = Natives.yieldHost(ctx, adapters, function() end)
  if not yielded then
    LB.state = "off"
    report(L.LINKUP.FAILED)
    return false
  end
  ctx.nativePoll = function()
    ticks = ticks + 1
    local live = L.link
    if live and not announced then
      live.linkType = spec.linkType
      live:send({ type = LB.MSG.LINKUP, linkType = spec.linkType, players = spec.min })
      announced = true
    end
    if not announced then
      -- pokefirered/src/cable_club.c:482 TryLinkTimeout
      if ticks > LB.LINKUP_TICKS then
        report(L.LINKUP.CONNECTION_ERROR)
        LB.state = "off"
        return true
      end
      return false
    end
    local peer = live and live:isReady() and live:take(LB.MSG.LINKUP) or nil
    if peer then
      local players = LB.playerCount()
      if tonumber(peer.linkType) ~= spec.linkType then
        -- pokefirered/src/cable_club.c:122 EXCHANGE_DIFF_SELECTIONS
        report(L.LINKUP.DIFF_SELECTIONS)
        LB.state = "off"
      elseif players < spec.min or players > spec.max then
        -- pokefirered/src/cable_club.c:127 EXCHANGE_WRONG_NUM_PLAYERS
        report(L.LINKUP.WRONG_NUM_PLAYERS)
        LB.state = "off"
      else
        report(L.LINKUP.SUCCESS)
        LB.state = "seat"
      end
      return true
    end
    if not (live and live:isOpen()) then
      -- pokefirered/src/cable_club.c:473 Task_LinkupConnectionError
      report(L.LINKUP.CONNECTION_ERROR)
      LB.state = "off"
      return true
    end
    -- pokefirered/src/cable_club.c:482 TryLinkTimeout
    if ticks > LB.LINKUP_TICKS then
      report(L.LINKUP.CONNECTION_ERROR)
      LB.state = "off"
      return true
    end
    return false
  end
  return true
end

-- pokefirered/src/cable_club.c:493 TryBattleLinkup
function LB.tryBattleLinkup(ctx, adapters)
  local L = link()
  local mode = L.getVar(ctx, L.VAR_0x8004)
  LB.mode = mode
  LB.unionRoom = false
  return LB.createLinkupTask(ctx, adapters, LB.PLAYERS[mode] or LB.PLAYERS[1])
end

-- pokefirered/src/script_pokemon_util.c:90 HasEnoughMonsForDoubleBattle
function LB.hasEnoughMonsForDoubleBattle(ctx)
  local Party = require("src.core.game3.party")
  local state = Party.monsStateToDoubles(partyOf(session()))
  link().setResult(ctx, state)
  return false, state
end

-- pokefirered/src/cable_club.c:964 EnterColosseumPlayerSpot
function LB.enterColosseumPlayerSpot(ctx, adapters)
  local L = link()
  LB.seat = L.getVar(ctx, LB.VAR_0x8005)
  LB.mode = L.getVar(ctx, L.VAR_0x8004)
  LB.unionRoom = false
  local lk = L.link
  if not (lk and lk:isOpen()) then
    LB.state = "off"
    return false
  end
  lk.linkType = LB.LINKTYPE.BATTLE
  -- pokefirered/src/cable_club.c:838 SetInCableClubSeat
  lk:send({ type = LB.MSG.SEAT, seat = LB.seat })
  LB.state = "setup"
  LB.seed = (lk.role == "host") and LB.dealSeed() or nil
  local mySetupSent = false
  local peerSetup = nil
  local seated = false
  local Natives = natives()
  local yielded = Natives.yieldHost(ctx, adapters, function() end)
  if not yielded then
    LB.state = "off"
    return false
  end
  ctx.nativePoll = function()
    local live = L.link
    if not (live and live:isOpen()) then
      -- pokefirered/src/cable_club.c:859 CABLE_SEAT_FAILED
      LB.state = "off"
      return true
    end
    if not seated and live:take(LB.MSG.SEAT) then seated = true end
    peerSetup = peerSetup or live:take(LB.MSG.SETUP)
    if peerSetup and LB.seed == nil then LB.seed = tonumber(peerSetup.seed) end
    if LB.seed and not mySetupSent then mySetupSent = sendSetup() end
    if not (seated and peerSetup and mySetupSent) then return false end
    LB.beginBattle(peerSetup)
    return true
  end
  return true
end

-- pokefirered/src/union_room.c:1811 StartUnionRoomBattle
function LB.startUnionRoomBattle(onDone)
  local L = link()
  local lk = L.link
  if not (lk and lk:isOpen()) then return false, "no_link" end
  local ok, reason = LB.validateParty(nil, L.USING.SINGLE_BATTLE, { unionRoom = true })
  if not ok then return false, reason end
  LB.mode = L.USING.SINGLE_BATTLE
  LB.unionRoom = true
  LB.state = "setup"
  if lk.role == "host" then LB.seed = LB.dealSeed() end
  local ctx, adapters = L.vmCtx()
  -- pokefirered/src/union_room.c:1812 HealPlayerParty / SavePlayerParty / LoadPlayerBag
  L.callSpecial(ctx, adapters, 0x00)
  L.callSpecial(ctx, adapters, 0x27)
  L.loadPlayerBag()
  LB._onSetup = onDone or function() end
  sendSetup()
  return true
end

function LB.pumpUnionSetup()
  if LB.state ~= "setup" or not LB.unionRoom then return false end
  local lk = link().link
  if not (lk and lk:isOpen()) then
    LB.state = "off"
    return false
  end
  local setup = lk:take(LB.MSG.SETUP)
  if not setup then return false end
  if LB.seed == nil then LB.seed = tonumber(setup.seed) end
  if LB.seed == nil then return false end
  local cb = LB._onSetup
  LB._onSetup = nil
  LB.beginBattle(setup, cb)
  return true
end

-- pokefirered/src/cable_club.c:532 TryRecordMixLinkup
function LB.tryRecordMixLinkup(ctx, adapters)
  LB.mode = link().USING.RECORD_CORNER
  LB.unionRoom = false
  return LB.createLinkupTask(ctx, adapters, LB.RECORD_MIX)
end

function LB.reset()
  LB.state = "off"
  LB.mode = nil
  LB.seed = nil
  LB.seat = nil
  LB.linkup = nil
  LB.peer = nil
  LB.unionRoom = false
  LB.outcome = nil
  LB.headless = nil
  LB.fade = nil
  LB._actions = {}
  LB._switches = {}
  LB._sent = {}
  LB._started = false
  LB._onSetup = nil
end

return LB
