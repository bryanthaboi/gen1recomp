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
  HASH = "game3_battle_hash",
  FORFEIT = "forfeit",
}

LB.HASH_PARTS = { "actives", "volatile", "bench", "field", "rng" }

LB.MODE_OF = { single = 1, double = 2, multi = 5 }

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
LB._draws = { n = 0 }
LB._myHashes = {}
LB._peerHashes = {}
LB._myParts = {}
LB._peerOutcomes = {}
LB._reported = false
LB.endReason = nil
LB.log = {}

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
function LB.makeRng(seed, counter)
  local value = math.floor(tonumber(seed) or 0) % 4294967296
  local function word()
    if counter then counter.n = counter.n + 1 end
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

local function note(fmt, ...)
  local line = string.format(fmt, ...)
  LB.log[#LB.log + 1] = line
  if #LB.log > 64 then table.remove(LB.log, 1) end
  print("[link3] " .. line)
end

LB.note = note

function LB.transport()
  if LB._spec then return LB._spec.t end
  local lk = link().link
  return lk and lk._transport or nil
end

function LB.onRelay()
  local t = LB.transport()
  return (t and t.relay == true) and true or false
end

function LB.seedFromRelay()
  local t = LB.transport()
  if t and t.relay == true and type(t.seed) == "function" then
    local ok, seed = pcall(t.seed, t)
    seed = ok and tonumber(seed) or nil
    if seed then return math.floor(seed) % 4294967296 end
  end
  local spec = LB._arena or (LB._spec and LB._spec.spec)
  local seed = spec and tonumber(spec.seed)
  if seed then return math.floor(seed) % 4294967296 end
  return nil
end

function LB.relaySeat()
  local t = LB.transport()
  if t and type(t.seat) == "function" then
    local ok, seat = pcall(t.seat, t)
    if ok and tonumber(seat) then return math.floor(tonumber(seat)) end
  end
  local spec = LB._arena
  if spec and tonumber(spec.seat) then return math.floor(tonumber(spec.seat)) end
  return nil
end

local function protocol()
  return require("src.link.Protocol")
end

function LB.unpackOpts()
  local spec = LB._arena or (LB._spec and LB._spec.spec)
  local rule = spec and spec.profile and spec.profile.rule
  return { strict = true, forceLevel = rule and tonumber(rule.forceLevel) or nil }
end

function LB.packParty(party)
  local P = protocol()
  assert(type(P.packParty3) == "function", "Protocol.packParty3 is required for a Gen 3 link battle")
  return P.packParty3(party)
end

-- pokefirered/include/constants/species.h:419
LB.SPECIES_DEOXYS = 410

-- pokefirered/src/pokemon.c:6163
function LB.applyLinkStats(mon)
  if tonumber(mon and (mon.species or mon.speciesId)) ~= LB.SPECIES_DEOXYS then return mon end
  local Pokemon = require("src.core.game3.pokemon")
  local meta = Pokemon.speciesMeta(LB.SPECIES_DEOXYS)
  local row = meta and meta.linkStats
  if type(row) ~= "table" or #row < 6 or not Pokemon.stats(LB.SPECIES_DEOXYS) then
    return nil, "no_link_stats"
  end
  local saved = Pokemon._stats[LB.SPECIES_DEOXYS]
  Pokemon._stats[LB.SPECIES_DEOXYS] = {
    hp = row[1], atk = row[2], def = row[3], spe = row[4], spa = row[5], spd = row[6],
  }
  local ok, st = pcall(Pokemon.calcStats, LB.SPECIES_DEOXYS, mon.level, mon.ivs, mon.evs, mon.personality)
  Pokemon._stats[LB.SPECIES_DEOXYS] = saved
  if not ok or type(st) ~= "table" then return nil, "no_link_stats" end
  mon.attack, mon.atk = st.attack, st.attack
  mon.defense, mon.def = st.defense, st.defense
  mon.speed, mon.spe = st.speed, st.speed
  mon.spAtk, mon.spa = st.spAtk, st.spAtk
  mon.spDef, mon.spd = st.spDef, st.spDef
  return mon
end

function LB.unpackParty(packed, opts)
  if type(packed) ~= "table" or #packed == 0 or #packed > 6 then return nil, "bad party" end
  local P = protocol()
  assert(type(P.unpackMon3) == "function", "Protocol.unpackMon3 is required for a Gen 3 link battle")
  opts = opts or LB.unpackOpts()
  local out = {}
  for i = 1, #packed do
    local mon, why = P.unpackMon3(nil, packed[i], { strict = true, forceLevel = opts.forceLevel })
    if not mon then return nil, why or "bad mon" end
    local item = tonumber(mon.item or mon.heldItem) or 0
    mon.item, mon.heldItem = item, item
    local linked, linkWhy = LB.applyLinkStats(mon)
    if not linked then return nil, linkWhy end
    out[i] = linked
  end
  return out
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

function LB.isMulti()
  return LB.mode == LB.MODE_OF.multi
end

-- pokefirered/src/script_pokemon_util.c:197
LB.MULTI_PARTY_SIZE = 3

local function firstThree(list)
  if type(list) ~= "table" or #list <= LB.MULTI_PARTY_SIZE then return list end
  local out = {}
  for i = 1, LB.MULTI_PARTY_SIZE do out[i] = list[i] end
  return out
end

function LB.myPacked()
  if LB._myPacked then
    if LB.isMulti() then LB._myPacked = firstThree(LB._myPacked) end
    return LB._myPacked
  end
  local party = LB.battleParty()
  if LB.isMulti() then party = firstThree(party) end
  LB._myPacked = LB.packParty(party)
  return LB._myPacked
end

function LB.myParty()
  if LB._myParty then return LB._myParty end
  local party, why = LB.unpackParty(LB.myPacked())
  if not party then return nil, why end
  LB._myParty = party
  return party
end

local function sendSetup()
  local lk = link().link
  if not (lk and lk:isOpen()) then return false end
  local me = LB.localPlayer()
  lk:send({
    type = LB.MSG.SETUP,
    seed = (not LB.onRelay()) and LB.seed or nil,
    mode = LB.mode,
    unionRoom = LB.unionRoom and true or false,
    name = me.name,
    trainerId = me.trainerId,
    gender = me.gender,
    seat = LB.relaySeat() or LB.seat,
    party = LB.myPacked(),
  })
  return true
end

LB.sendSetup = sendSetup

function LB.foeFrom(setup)
  local party = {}
  for _, mon in ipairs((setup and setup.party) or {}) do
    local copy = copyTable(mon)
    copy.item = tonumber(copy.item or copy.heldItem) or 0
    copy.heldItem = copy.item
    party[#party + 1] = copy
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

-- pokefirered/include/constants/union_room.h:19
LB.NUM_UNION_ROOM_CLASSES = 8

function LB.unionRoomClasses()
  if not LB._unionRoomClasses then
    local rel = "data/generated/gba/trainers/union_room_classes.lua"
    local src = assert(require("src.core.game3.dataset").cache():read(rel), "no " .. rel .. " in the cache")
    LB._unionRoomClasses = assert(load(src, "@" .. rel, "t", {}))()
  end
  return LB._unionRoomClasses
end

-- pokefirered/src/pokemon.c:6197
local function unionRoomIndex(peer)
  local i = (tonumber(peer and peer.trainerId) or 0) % LB.NUM_UNION_ROOM_CLASSES
  if tonumber(peer and peer.gender) == 1 then i = i + LB.NUM_UNION_ROOM_CLASSES end
  return i
end

-- pokefirered/src/pokemon.c:6206 GetUnionRoomTrainerClass
function LB.unionRoomTrainerClass(peer)
  return LB.unionRoomClasses().trainerClass[unionRoomIndex(peer or LB.peer)]
end

-- pokefirered/src/pokemon.c:6197 GetUnionRoomTrainerPic
function LB.unionRoomTrainerPic(peer)
  return LB.unionRoomClasses().trainerPic[unionRoomIndex(peer or LB.peer)]
end

-- pokefirered/src/battle_controller_link_opponent.c:1172
function LB.peerPicId(setup)
  if LB.unionRoom then return LB.unionRoomTrainerPic(setup) end
  if tonumber(setup and setup.gender) == 1 then return LB.TRAINER_PIC_LEAF end
  return LB.TRAINER_PIC_RED
end

-- pokefirered/src/link.c:965 GetMultiplayerId
function LB.multiplayerId()
  if LB._spec then return 0 end
  local seat = LB.onRelay() and LB.relaySeat() or nil
  if seat then return seat end
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
function LB.battleSong(setup, mine)
  local leader
  if LB.isMaster() then
    leader = tonumber(mine and mine.trainerId) or LB.localPlayer().trainerId
  else
    leader = tonumber(setup and setup.trainerId) or 0
  end
  if leader % 2 == 1 then return LB.MUS_RS_VS_GYM_LEADER end
  return LB.MUS_RS_VS_TRAINER
end

local function resetTurnState()
  LB._actions = {}
  LB._switches = {}
  LB._seatActions = {}
  LB._seatSwitches = {}
  LB._sent = {}
  LB._draws = { n = 0 }
  LB._myHashes = {}
  LB._peerHashes = {}
  LB._myParts = {}
  LB._peerOutcomes = {}
  LB._checked = {}
  LB._raw = nil
end

function LB.refuse(why, onDone)
  why = tostring(why or "refused")
  note("battle refused: %s", why)
  LB.endReason = why
  local lk = link().link
  if lk and lk:isOpen() then lk:send({ type = LB.MSG.FORFEIT, reason = why }) end
  LB.state = "off"
  LB._started = false
  LB.report("error")
  if onDone then onDone("error") end
  return false, why
end

function LB.beginBattle(setup, onDone)
  local L = link()
  local peerParty, why = LB.unpackParty(setup and setup.party)
  if not peerParty then return LB.refuse(why, onDone) end
  local mine, mineWhy = LB.myParty()
  if not mine then return LB.refuse(mineWhy, onDone) end
  local foe = LB.foeFrom({ name = setup.name, party = peerParty })
  if not foe then return LB.refuse("peer_has_no_party", onDone) end
  LB.peer = {
    name = setup.name,
    trainerId = tonumber(setup.trainerId) or 0,
    gender = tonumber(setup.gender) or 0,
  }
  LB.state = "battle"
  resetTurnState()
  LB._relay = LB.onRelay()
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
  local ok, started, err = pcall(BattleBridge.start, rt and rt._mod, L.game(), foe, {
    link = true,
    linkParty = mine,
    linkFlags = flags,
    -- pokefirered/src/battle_controllers.c:148 the master's own mon is battler 0 on both machines
    linkMaster = LB.isMaster(),
    double = double,
    unionRoom = LB.unionRoom,
    trainerId = nil,
    rng = LB.makeRng(LB.seed, LB._draws),
    peerName = setup.name,
    trainerName = setup.name,
    trainerPicId = LB.peerPicId(setup),
    song = LB.battleSong(setup),
    headless = LB.headless,
    autoFight = LB.autoFight,
    fade = LB.fade,
    done = function(result)
      LB.finish(result)
      if onDone then onDone(LB.resultWord(result)) end
    end,
  })
  if not ok or not started then
    LB._started = false
    return LB.refuse(ok and (err or "battle_start_failed") or started, onDone)
  end
  return started
end

local function hasLiving(party)
  for _, mon in ipairs(party or {}) do
    if LB.eligible(mon) and (tonumber(mon.hp) or 0) > 0 then return true end
  end
  return false
end

function LB.unpackMultiParty(packed)
  if type(packed) == "table" and #packed > LB.MULTI_PARTY_SIZE then return nil, "bad party" end
  local party, why = LB.unpackParty(packed)
  if not party then return nil, why end
  if not hasLiving(party) then return nil, "no_mons" end
  return party
end

-- pokefirered/src/battle_controllers.c:229
local MULTI_POSITION = {
  [0] = { [0] = 0, [1] = 3, [2] = 2, [3] = 1 },
  [1] = { [0] = 1, [1] = 2, [2] = 3, [3] = 0 },
}

function LB.localBattler(mySeat, seat)
  return MULTI_POSITION[(tonumber(mySeat) or 0) % 2][seat]
end

-- pokefirered/src/battle_message.c:2092
function LB.oppositeSeat(seat)
  return (seat % 2 == 0) and (seat + 1) or (seat - 1)
end

-- pokefirered/src/battle_main.c:1295
local SIDE_SEATS = { [0] = { 0, 2 }, [1] = { 3, 1 } }

function LB.multiLayout(mySeat, parties, names, genders)
  local mySide = (mySeat ~= nil and mySeat % 2 == 1) and 1 or 0
  local function side(n)
    local party, owners = {}, {}
    for _, seat in ipairs(SIDE_SEATS[n]) do
      for _, mon in ipairs(parties[seat] or {}) do
        party[#party + 1] = mon
        owners[#party] = LB.localBattler(mySeat, seat)
      end
    end
    return party, owners
  end
  local playerParty, playerOwners = side(mySide)
  local foeParty, foeOwners = side(1 - mySide)
  local byLocal, seatOf, localOf, genderOf, order = {}, {}, {}, {}, {}
  for seat = 0, 3 do
    local id = LB.localBattler(mySeat, seat)
    byLocal[id] = names and names[seat] or nil
    genderOf[id] = (genders and tonumber(genders[seat]) == 1) and 1 or 0
    seatOf[id] = seat
    localOf[seat] = id
    order[seat + 1] = id
  end
  return {
    own = mySeat ~= nil and LB.localBattler(mySeat, mySeat) or nil,
    names = byLocal,
    genders = genderOf,
    seatOf = seatOf,
    localOf = localOf,
    order = order,
    owners = { player = playerOwners, enemy = foeOwners },
  }, playerParty, foeParty
end

local function setupInfo(setup)
  return {
    name = setup and setup.name or nil,
    trainerId = tonumber(setup and setup.trainerId) or 0,
    gender = (tonumber(setup and setup.gender) == 1) and 1 or 0,
  }
end

-- pokefirered/src/battle_main.c:1196
function LB.beginMulti(setups, onDone)
  local L = link()
  local mySeat = LB.relaySeat() or tonumber(LB.seat) or 0
  local mine, mineWhy = LB.myParty()
  if not mine then return LB.refuse(mineWhy, onDone) end
  if #mine > LB.MULTI_PARTY_SIZE or not hasLiving(mine) then return LB.refuse("no_mons", onDone) end
  local me = LB.localPlayer()
  local parties, names, info = { [mySeat] = mine }, { [mySeat] = me.name }, { [mySeat] = me }
  for seat = 0, 3 do
    if seat ~= mySeat then
      local setup = setups and setups[seat]
      if not setup then return LB.refuse("missing_seat", onDone) end
      local party, why = LB.unpackMultiParty(setup.party)
      if not party then return LB.refuse(why, onDone) end
      parties[seat] = party
      info[seat] = setupInfo(setup)
      names[seat] = info[seat].name
    end
  end
  local genders = {}
  for seat = 0, 3 do genders[seat] = info[seat].gender end
  local layout, playerParty, foeParty = LB.multiLayout(mySeat, parties, names, genders)
  local oppSeat = LB.oppositeSeat(mySeat)
  local foe = LB.foeFrom({ name = names[oppSeat], party = foeParty })
  if not foe then return LB.refuse("peer_has_no_party", onDone) end
  LB.peer = info[oppSeat]
  LB.multiNames = names
  LB.state = "battle"
  resetTurnState()
  LB._relay = LB.onRelay()
  LB._started = true
  if not LB._arena then
    -- pokefirered/src/cable_club.c:669
    local okT, Tower = pcall(require, "src.core.game3.trainer_tower")
    if okT and Tower and Tower.reducePartyToThree then Tower.reducePartyToThree(session()) end
  end
  local BattleBridge = require("src.core.game3.battle_bridge")
  local rt = package.loaded["src.core.game3.runtime"]
  local ok, started, err = pcall(BattleBridge.start, rt and rt._mod, L.game(), foe, {
    link = true,
    linkParty = playerParty,
    linkFlags = LB.battleFlags(L.USING.MULTI_BATTLE),
    -- pokefirered/src/battle_controllers.c:248
    linkMaster = mySeat % 2 == 0,
    double = true,
    multi = layout,
    unionRoom = false,
    trainerId = nil,
    rng = LB.makeRng(LB.seed, LB._draws),
    peerName = names[oppSeat],
    trainerName = names[oppSeat],
    trainerPicId = LB.peerPicId(info[oppSeat]),
    song = LB.battleSong(info[0], info[mySeat]),
    headless = LB.headless,
    autoFight = LB.autoFight,
    fade = LB.fade,
    done = function(result)
      LB.finish(result)
      if onDone then onDone(LB.resultWord(result)) end
    end,
  })
  if not ok or not started then
    LB._started = false
    return LB.refuse(ok and (err or "battle_start_failed") or started, onDone)
  end
  return started
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

local function battleState()
  local Battle = package.loaded["src.core.game3.battle"]
  return Battle and Battle.getState and Battle.getState() or nil, Battle
end

local bit = require("bit")

local function fnv(text)
  local h = 0x811C9DC5
  for i = 1, #text do
    h = bit.bxor(h, text:byte(i)) % 4294967296
    h = ((bit.lshift(h, 24) % 4294967296) + h * 403) % 4294967296
  end
  return string.format("%08x", h)
end

LB.fnv = fnv

local function scalar(v)
  local t = type(v)
  if t == "number" then
    if v == math.floor(v) then return string.format("%d", v) end
    return string.format("%.6f", v)
  end
  if t == "boolean" then return v and "T" or "F" end
  if t == "string" then return v end
  if v == nil then return "-" end
  return "t"
end

local STAGES = { "attack", "defense", "speed", "spAtk", "spDef", "accuracy", "evasion" }

local VOLATILE_KEYS = {
  "confusion", "substitute", "toxicCounter", "focusEnergy", "perishSong", "seeded", "trapped",
  "attracted", "disabled", "encore", "taunt", "bide", "rage", "endure", "protect", "destinyBond",
  "transformed", "isFirstTurn",
  "expCharged", "expCursed", "expDisableTurns", "expDisabledMove", "expEncoreMove", "expEncoreSlot",
  "expEncoreTurns", "expFocusEnergy", "expFuryCutter", "expInfatuated", "expIngrain", "expLockedMove",
  "expLockedSlot", "expMustRecharge", "expNightmare", "expPerishTurns", "expRampageTurns",
  "expRechargeTurns", "expRolloutTimer", "expSeeded", "expTauntedTurns", "expTormented",
  "expTransform", "expTrapTurns", "expTrapped", "expTruantCounter", "expUproarTurns", "expYawnTurns",
  "expCastformForm",
}

local function perspective(st)
  if st.linkMaster == false then
    return { 1, 0, 3, 2 }, { "enemy", "player" }
  end
  return { 0, 1, 2, 3 }, { "player", "enemy" }
end

local function battlerOf(st, id)
  local State = require("src.core.game3.battle.state")
  if State.isAbsent(st, id) then return nil end
  return State.battler(st, id)
end

local function sortedScalars(t, skip, st)
  if type(t) ~= "table" then return scalar(t) end
  local flip = st and st.linkMaster == false
  local keys = {}
  for k, v in pairs(t) do
    if (type(k) == "string" or type(k) == "number") and not (skip and skip[k])
        and type(v) ~= "table" and type(v) ~= "function" then
      keys[#keys + 1] = tostring(k)
    end
  end
  table.sort(keys)
  local out = {}
  for _, k in ipairs(keys) do
    local v = t[k]
    if v == nil then v = t[tonumber(k)] end
    if flip and type(v) == "number" and k:sub(-2) == "Id" and v >= 0 and v <= 3 then
      v = (v % 2 == 0) and (v + 1) or (v - 1)
    end
    out[#out + 1] = k .. "=" .. scalar(v)
  end
  return table.concat(out, ",")
end

local function monPp(mon)
  local pp = {}
  for i = 1, 4 do pp[i] = scalar(mon and mon.pp and mon.pp[i]) end
  return table.concat(pp, "/")
end

local SIDE_SKIP = { id = true }

function LB.hashParts(st)
  local order, sides = perspective(st)
  local actives, volatile = {}, {}
  for _, id in ipairs(order) do
    local b = battlerOf(st, id)
    if not b then
      actives[#actives + 1] = "-"
      volatile[#volatile + 1] = "-"
    else
      local mon = b.mon or {}
      local stages = {}
      for i, key in ipairs(STAGES) do stages[i] = scalar(b.stages and b.stages[key] or 0) end
      actives[#actives + 1] = table.concat({
        scalar(tonumber(b.species or mon.species)), scalar(tonumber(mon.hp)), scalar(tonumber(mon.maxHp)),
        scalar(b.status or mon.status), scalar(mon.sleep or b.sleepTurns), table.concat(stages, "/"),
        scalar(b.ability), scalar(tonumber(b.item) or 0), monPp(mon),
      }, ":")
      local vol = {}
      for _, key in ipairs(VOLATILE_KEYS) do vol[#vol + 1] = scalar(b[key]) end
      vol[#vol + 1] = sortedScalars(b.volatiles)
      volatile[#volatile + 1] = table.concat(vol, ":")
    end
  end
  local bench, field = {}, {}
  for _, side in ipairs(sides) do
    local party = (side == "player") and st.playerParty or st.foeParty
    local active = {}
    for _, id in ipairs((side == "player") and { 0, 2 } or { 1, 3 }) do
      local b = battlerOf(st, id)
      if b and b.partyIndex then active[b.partyIndex] = true end
    end
    local rows = {}
    for i, mon in ipairs(party or {}) do
      if active[i] then
        rows[#rows + 1] = "*"
      else
        rows[#rows + 1] = table.concat({
          scalar(tonumber(mon.species or mon.speciesId)), scalar(tonumber(mon.hp)), scalar(mon.status),
          scalar(tonumber(mon.item or mon.heldItem) or 0), monPp(mon),
        }, ":")
      end
    end
    bench[#bench + 1] = table.concat(rows, ";")
    local sideState = (side == "player") and st.playerSide or st.enemySide
    field[#field + 1] = sortedScalars(sideState, SIDE_SKIP, st) .. "|" .. sortedScalars(sideState and sideState.hazards, nil, st)
  end
  table.insert(field, 1, scalar(st.weather) .. ":" .. scalar(st.weatherTurns))
  local raw = {
    actives = table.concat(actives, "#"),
    volatile = table.concat(volatile, "#"),
    bench = table.concat(bench, "#"),
    field = table.concat(field, "#"),
  }
  return {
    actives = fnv(raw.actives),
    volatile = fnv(raw.volatile),
    bench = fnv(raw.bench),
    field = fnv(raw.field),
    rng = string.format("%d", LB._draws and LB._draws.n or 0),
  }, raw
end

function LB.hashValue(parts)
  local list = {}
  for i, key in ipairs(LB.HASH_PARTS) do list[i] = tostring(parts[key] or "") end
  return fnv(table.concat(list, "|"))
end

local function firstDiff(mine, theirs)
  if type(mine) ~= "table" or type(theirs) ~= "table" then return "state" end
  for _, key in ipairs(LB.HASH_PARTS) do
    if tostring(mine[key]) ~= tostring(theirs[key]) then return key end
  end
  return "state"
end

function LB.checkHashes()
  if LB.state ~= "battle" or not LB._started then return end
  for turn, mine in pairs(LB._myHashes) do
    for seat, rows in pairs(LB._peerHashes) do
      local theirs = rows[turn]
      local key = tostring(seat) .. ":" .. tostring(turn)
      if theirs and not LB._checked[key] then
        LB._checked[key] = true
        if theirs.value ~= mine then
          local component = firstDiff(LB._myParts[turn], theirs.parts)
          return LB.desync(turn, component, seat)
        end
      end
    end
  end
end

function LB.checkpoint(turn)
  turn = math.floor(tonumber(turn) or 0)
  if turn < 1 or LB._myHashes[turn] then return nil end
  local st = battleState()
  if not st then return nil end
  local parts, raw = LB.hashParts(st)
  local value = LB.hashValue(parts)
  LB._myHashes[turn] = value
  LB._myParts[turn] = parts
  if LB.keepRaw then
    LB._raw = LB._raw or {}
    LB._raw[turn] = raw
  end
  local lk = link().link
  if lk and lk:isOpen() then
    lk:send({ type = LB.MSG.HASH, turn = turn, value = value, parts = parts })
  end
  LB.checkHashes()
  return value
end

function LB.desync(turn, component, seat)
  if LB.endReason == "desync" then return false end
  LB.endReason = "desync"
  note("desync turn %s component=%s seat=%s", tostring(turn), tostring(component), tostring(seat))
  local _, Battle = battleState()
  local Strings = require("src.core.Strings")
  local text = Strings("Link desync! %s differs. Are both games the same version and mods?", tostring(component))
  if Battle and Battle.isActive and Battle.isActive() and Battle.linkEnd then
    Battle.linkEnd("draw", text, "desync")
  elseif LB._started then
    LB.finish("draw")
  end
  return true
end

function LB.protocolError(component)
  return LB.desync(LB._turn or 0, component or "protocol", nil)
end

-- pokefirered/src/battle_main.c:3226
function LB.sendAction(turn, action)
  local lk = link().link
  turn = math.floor(tonumber(turn) or 0)
  if LB._sent[turn] then return true end
  if not (lk and lk:isOpen()) then return false end
  LB.checkpoint(turn - 1)
  LB._turn = turn
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
  LB.checkpoint(turn - 1)
  LB._turn = turn
  LB._sent[turn] = true
  local actions = {}
  for i = 1, 2 do actions[i] = wireAction(list and list[i]) end
  lk:send({ type = LB.MSG.ACTION, turn = turn, kind = "list", actions = actions })
  return true
end

-- pokefirered/src/battle_main.c:3097
function LB.sendMultiAction(turn, action, target)
  local lk = link().link
  turn = math.floor(tonumber(turn) or 0)
  if LB._sent[turn] then return true end
  if not (lk and lk:isOpen()) then return false end
  LB.checkpoint(turn - 1)
  LB._turn = turn
  LB._sent[turn] = true
  if action == nil then return true end
  local msg = wireAction(action)
  msg.target = tonumber(target)
  msg.type = LB.MSG.ACTION
  msg.turn = turn
  lk:send(msg)
  return true
end

function LB.seatAction(seat, turn)
  LB.pumpActions()
  turn = math.floor(tonumber(turn) or 0)
  local rows = LB._spec and LB._spec.actions[seat] or LB._seatActions[seat]
  return rows and rows[turn] or nil
end

function LB.forgetSeatAction(seat, turn)
  local rows = LB._spec and LB._spec.actions[seat] or LB._seatActions[seat]
  if rows then rows[math.floor(tonumber(turn) or 0)] = nil end
end

function LB.seatSwitch(seat)
  LB.pumpActions()
  local q = LB._spec and LB._spec.switches[seat] or LB._seatSwitches[seat]
  if not q or #q == 0 then return nil end
  return table.remove(q, 1)
end

function LB.peerAhead(seat, turn)
  LB.pumpActions()
  turn = math.floor(tonumber(turn) or 0)
  local outcomes = LB._spec and LB._spec.outcomes or LB._peerOutcomes
  local function past(s)
    local rows = LB._peerHashes[s]
    return (rows and rows[turn] ~= nil) or outcomes[s] ~= nil
  end
  if seat ~= nil then return past(seat) end
  for s in pairs(LB._peerHashes) do if past(s) then return true end end
  for _ in pairs(outcomes) do return true end
  return false
end

function LB.beginSpectatedTurn(turn)
  turn = math.floor(tonumber(turn) or 0)
  LB.checkpoint(turn - 1)
  LB._turn = turn
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
  if LB._spec then
    local q = LB._spec.switches[1]
    if #q == 0 then return nil end
    return table.remove(q, 1)
  end
  if #LB._switches == 0 then return nil end
  return table.remove(LB._switches, 1)
end

function LB.ownSwitch()
  if not LB._spec then return nil end
  LB.pumpActions()
  local q = LB._spec.switches[0]
  if #q == 0 then return nil end
  return table.remove(q, 1)
end

function LB.linkOpen()
  if LB._spec then
    local t = LB._spec.t
    return not (LB._spec.gone or (t and (t.closed or t.error))) and true or false
  end
  local lk = link().link
  return (lk and lk:isOpen()) and true or false
end

local function isOwn(msg)
  if type(msg) ~= "table" then return false end
  local seat = tonumber(msg.seat)
  if seat == nil or not LB.onRelay() then return false end
  local mine = LB.relaySeat()
  return mine ~= nil and seat == mine
end

local function noteOutcome(msg, seat)
  LB._peerOutcomes[seat or 1] = { outcome = tonumber(msg.outcome), turn = tonumber(msg.turn) }
  LB.compareOutcome()
end

local function noteHash(msg, seat)
  local turn = math.floor(tonumber(msg.turn) or 0)
  if turn < 1 then return end
  seat = seat or 1
  LB._peerHashes[seat] = LB._peerHashes[seat] or {}
  LB._peerHashes[seat][turn] = { value = tostring(msg.value or ""), parts = msg.parts }
end

function LB.pumpActions()
  if LB._spec then return LB.pumpSpectator() end
  local lk = link().link
  if lk then LB._lk = lk else lk = LB._lk end
  if not lk then return end
  if lk:isOpen() then lk:update(0) end
  local multi = LB.isMulti()
  local msg = lk:take(LB.MSG.ACTION)
  while msg do
    if not isOwn(msg) then
      local turn = math.floor(tonumber(msg.turn) or 0)
      local seat = tonumber(msg.seat)
      if multi then
        if seat then
          LB._seatActions[seat] = LB._seatActions[seat] or {}
          LB._seatActions[seat][turn] = msg
        end
      else
        LB._actions[turn] = msg
      end
    end
    msg = lk:take(LB.MSG.ACTION)
  end
  local sw = lk:take(LB.MSG.SWITCH)
  while sw do
    if not isOwn(sw) then
      local slot = math.floor(tonumber(sw.slot) or 1)
      local seat = tonumber(sw.seat)
      if multi then
        if seat then
          local q = LB._seatSwitches[seat] or {}
          LB._seatSwitches[seat] = q
          q[#q + 1] = slot
        end
      else
        LB._switches[#LB._switches + 1] = slot
      end
    end
    sw = lk:take(LB.MSG.SWITCH)
  end
  local h = lk:take(LB.MSG.HASH)
  while h do
    if not isOwn(h) then noteHash(h, tonumber(h.seat) or 1) end
    h = lk:take(LB.MSG.HASH)
  end
  local o = lk:take(LB.MSG.OUTCOME)
  while o do
    if not isOwn(o) then noteOutcome(o, tonumber(o.seat) or 1) end
    o = lk:take(LB.MSG.OUTCOME)
  end
  local f = lk:take(LB.MSG.FORFEIT)
  if f and not isOwn(f) then
    note("peer forfeited: %s", tostring(f.reason))
    local seat, mine = tonumber(f.seat), LB.relaySeat()
    LB.peerForfeit = (multi and seat and mine and seat % 2 == mine % 2) and "lose" or "win"
  end
  LB.checkHashes()
end

function LB.peerAction(turn)
  LB.pumpActions()
  if LB._spec then return LB._spec.actions[1][math.floor(tonumber(turn) or 0)] end
  return LB._actions[math.floor(tonumber(turn) or 0)]
end

function LB.ownAction(turn)
  if not LB._spec then return nil end
  LB.pumpActions()
  turn = math.floor(tonumber(turn) or 0)
  local msg = LB._spec.actions[0][turn]
  if msg then
    LB._spec.actions[0][turn] = nil
    LB.checkpoint(turn - 1)
    LB._turn = turn
  end
  return msg
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

-- pokefirered/src/battle_main.c:4303
function LB.outcomeCode(result)
  if result == "win" then return LB.B_OUTCOME.WON end
  if result == "lose" or result == "whiteout" or result == "blackout" then
    return LB.B_OUTCOME.LOST
  end
  if result == "draw" then return LB.B_OUTCOME.DREW end
  if result == "run" then return LB.B_OUTCOME.LINK_BATTLE_RAN end
  return LB.B_OUTCOME.DREW
end

-- pokefirered/src/battle_main.c:3777
function LB.recordOutcome(outcome)
  if outcome == LB.B_OUTCOME.LINK_BATTLE_RAN then return LB.B_OUTCOME.LOST end
  return outcome
end

local REPORT_WORD = { [1] = "win", [2] = "lose", [3] = "draw", [128] = "lose" }

function LB.resultWord(result)
  return REPORT_WORD[LB.outcomeCode(result)] or "draw"
end

function LB.report(word)
  if LB._reported or LB._spec then return false end
  if not (LB._relay or LB.onRelay() or LB._arena) then return false end
  LB._reported = true
  local okC, Client = pcall(require, "src.online.Client")
  if okC and type(Client) == "table" and type(Client.report) == "function" then
    local ok, err = pcall(Client.report, word)
    if not ok then note("report failed: %s", tostring(err)) end
  end
  note("report %s", tostring(word))
  return true
end

local MIRROR = { [1] = { [2] = true, [128] = true }, [2] = { [1] = true }, [3] = { [3] = true },
  [128] = { [1] = true } }

function LB.compareOutcome()
  local mine = LB.outcome
  if not mine then return end
  for seat, row in pairs(LB._peerOutcomes) do
    if not row.compared then
      row.compared = true
      local ok = MIRROR[mine] and MIRROR[mine][row.outcome]
      local me = LB.relaySeat()
      if LB.isMulti() and me and tonumber(seat) and tonumber(seat) % 2 == me % 2 then
        ok = LB.recordOutcome(row.outcome) == LB.recordOutcome(mine)
      end
      if not ok then
        note("outcome mismatch seat=%s mine=%s theirs=%s", tostring(seat), tostring(mine), tostring(row.outcome))
      end
    end
  end
end

-- pokefirered/src/cable_club.c:776 CB2_ReturnFromCableClubBattle
function LB.finish(result)
  if not LB._started then return false end
  LB._started = false
  local L = link()
  local s = session()
  local outcome = LB.outcomeCode(result)
  local recorded = LB.recordOutcome(outcome)
  LB.outcome = outcome
  local offField = LB._arena ~= nil or LB._spec ~= nil
  if not offField then
    local ctx, adapters = L.vmCtx()
    -- pokefirered/src/load_save.c:170
    L.callSpecial(ctx, adapters, 0x28)
    -- pokefirered/src/load_save.c:239
    L.savePlayerBag()
    if s then s.battleOutcome = recorded end
    -- pokefirered/src/battle_records.c:443
    if LB.mode ~= L.USING.MULTI_BATTLE and not LB.unionRoom then
      bumpTrainerCard(s, recorded)
      LB.addOpponentRecord(s, LB.peer and LB.peer.name, LB.peer and LB.peer.trainerId, recorded)
      -- pokefirered/src/cable_club.c:782
      local okF, TFC = pcall(require, "src.core.game3.trainer_fan_club")
      if okF and TFC and TFC.updateTrainerFansAfterLinkBattle then
        TFC.updateTrainerFansAfterLinkBattle(s, ctx, recorded)
      end
    end
  end
  local lk = L.link
  local live = lk and lk:isOpen() and not LB._spec
  if live then
    lk:send({ type = LB.MSG.OUTCOME, outcome = outcome, turn = LB._turn or 0 })
  end
  if (live or (LB._drained and LB.endReason == nil)) and not offField then
    -- pokefirered/src/cable_club.c:806
    local game = L.game()
    if game and type(game.saveGame) == "function" then
      local okSave, written = pcall(game.saveGame, game)
      if not okSave or written == false then
        print("[link] post-battle save failed: " .. tostring(written))
      end
    end
  end
  LB.report(REPORT_WORD[outcome] or "draw")
  LB.pumpActions()
  LB.compareOutcome()
  LB.state = "done"
  if LB.unionRoom then
    -- pokefirered/src/cable_club.c:761 CB2_ReturnFromUnionRoomBattle
    local U = union()
    if U then U.state = "main" end
  end
  return true
end

function LB.peerDone()
  if LB._peerOutcomes and next(LB._peerOutcomes) ~= nil then return true end
  local st = battleState()
  return (st and st.over) and true or false
end

function LB.streamComplete()
  local sp = LB._spec
  if not sp then return false end
  for seat = 0, LB.isMulti() and 3 or 1 do
    if sp.outcomes[seat] == nil then return false end
  end
  return true
end

-- pokefirered/src/cable_club.c:1002 Task_WaitForLinkPlayerConnection
function LB.peerDropped()
  if not LB._started then return false end
  if LB.streamComplete() then return LB.protocolError("stream") end
  LB.endReason = LB.endReason or "peer_dropped"
  local Battle = package.loaded["src.core.game3.battle"]
  if Battle and Battle.isActive and Battle.isActive() then
    Battle.abort("draw")
  else
    LB.finish("draw")
  end
  if not LB._spec then link().closeLink("peer_dropped") end
  return true
end

function LB.update(dt)
  if LB.state == "off" then return false end
  local Guard = package.loaded["src.core.game3.battle.link_guard"]
  if LB.state == "battle" and Guard and Guard.tripped then
    local where = Guard.tripped
    Guard.tripped = nil
    LB.desync(LB._turn or 0, "rng:" .. tostring(where))
  end
  if LB.state == "arena_setup" then
    LB.arenaStep()
    return true
  end
  if LB.state == "spectate_setup" then
    LB.spectatorStep()
    return true
  end
  if LB._spec then
    if LB.state == "battle" then LB.pumpActions() end
    return LB.state ~= "off" and LB.state ~= "done"
  end
  local L = link()
  local lk = L.link
  if LB.state == "battle" then
    LB.pumpActions()
    if LB.peerForfeit then
      local word = (LB.peerForfeit == "lose") and "lose" or "win"
      LB.peerForfeit = nil
      local Battle = package.loaded["src.core.game3.battle"]
      if Battle and Battle.isActive and Battle.isActive() and Battle.linkEnd then
        LB.endReason = "peer_forfeit"
        Battle.linkEnd(word, nil, "peer_forfeit")
      end
    end
    if not (lk and lk:isOpen()) then
      if not LB.peerDone() then
        LB.peerDropped()
        return LB.state ~= "off"
      end
      LB._drained = true
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
  if not (lk and lk:isOpen()) then return 1 end
  if type(lk.players) == "function" then
    local ok, list = pcall(lk.players, lk)
    if ok and type(list) == "table" and #list > 0 then return #list end
  end
  return 2
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
  LB.freshBattle()
  if LB.onRelay() then
    LB.seed = LB.seedFromRelay()
  else
    LB.seed = (lk.role == "host") and LB.dealSeed() or nil
  end
  local mySetupSent = false
  local peerSetup = nil
  local seated = false
  local multiSeats, multiSetups = {}, {}
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
    if LB.isMulti() then
      local sm = live:take(LB.MSG.SEAT)
      while sm do
        multiSeats[tonumber(sm.seat) or 1] = true
        sm = live:take(LB.MSG.SEAT)
      end
      local su = live:take(LB.MSG.SETUP)
      while su do
        local from = tonumber(su.seat) or 1
        multiSetups[from] = multiSetups[from] or su
        su = live:take(LB.MSG.SETUP)
      end
      if LB.seed and not mySetupSent then mySetupSent = sendSetup() end
      local nSeats, nSetups = 0, 0
      for _ in pairs(multiSeats) do nSeats = nSeats + 1 end
      for _ in pairs(multiSetups) do nSetups = nSetups + 1 end
      -- pokefirered/src/battle_main.c:1240
      if not (mySetupSent and nSeats >= 3 and nSetups >= 3) then return false end
      LB.beginMulti(multiSetups)
      return true
    end
    if not seated and live:take(LB.MSG.SEAT) then seated = true end
    peerSetup = peerSetup or live:take(LB.MSG.SETUP)
    if peerSetup and LB.seed == nil and not LB.onRelay() then LB.seed = tonumber(peerSetup.seed) end
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
  LB.freshBattle()
  if LB.onRelay() then
    LB.seed = LB.seedFromRelay()
  elseif lk.role == "host" then
    LB.seed = LB.dealSeed()
  end
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
  if LB.seed == nil and not LB.onRelay() then LB.seed = tonumber(setup.seed) end
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

local STALE = { LB.MSG.ACTION, LB.MSG.SWITCH, LB.MSG.HASH, LB.MSG.OUTCOME, LB.MSG.FORFEIT }

function LB.freshBattle()
  resetTurnState()
  local lk = link().link
  if lk and type(lk.take) == "function" then
    for _, kind in ipairs(STALE) do
      while lk:take(kind) do end
    end
  end
  LB._lk = nil
  LB._drained = nil
  LB._myPacked = nil
  LB._myParty = nil
  LB._reported = false
  LB._relay = nil
  LB._turn = nil
  LB.endReason = nil
  LB.outcome = nil
  LB.peerForfeit = nil
  LB.multiNames = nil
end

local function arenaLinkType(mode)
  if mode == LB.MODE_OF.double then return LB.LINKTYPE.DOUBLE_BATTLE end
  if mode == LB.MODE_OF.multi then return LB.LINKTYPE.MULTI_BATTLE end
  return LB.LINKTYPE.SINGLE_BATTLE
end

LB.arenaLinkType = arenaLinkType

-- pokefirered/src/cable_club.c:964
function LB.startArena(spec, onDone)
  LB.reset()
  LB.freshBattle()
  LB._arena = spec
  LB._arenaDone = onDone
  LB.mode = LB.MODE_OF[spec and spec.mode or "single"] or LB.MODE_OF.single
  LB.unionRoom = false
  LB.seat = tonumber(spec and spec.seat) or 0
  LB.seed = LB.seedFromRelay()
  LB.headless = spec and spec.headless or nil
  LB.autoFight = spec and spec.autoFight
  LB.fade = false
  if spec and spec.myParty then LB._myPacked = spec.myParty end
  LB._arenaSetup = { sent = false, seats = {}, setups = {}, linkup = nil }
  if LB.seed == nil then
    LB._arena = nil
    return LB.refuse("no_seed", onDone)
  end
  LB.state = "arena_setup"
  LB.arenaStep()
  return true
end

local function arenaFail(why)
  local done = LB._arenaDone
  LB._arenaDone = nil
  LB.refuse(why, done)
end

function LB.arenaStep()
  if LB.state ~= "arena_setup" then return false end
  local s = LB._arenaSetup
  local lk = link().link
  if not (lk and lk:isOpen()) then
    arenaFail((lk and lk.reason) or "link_closed")
    return false
  end
  lk:update(0)
  if not lk:isOpen() then
    arenaFail(lk.reason or "link_closed")
    return false
  end
  if not lk:isReady() then return false end
  if not s.sent then
    s.sent = true
    local linkType = arenaLinkType(LB.mode)
    lk.linkType = linkType
    local seats = tonumber(LB._arena.seats) or 2
    -- pokefirered/src/cable_club.c:318
    lk:send({ type = LB.MSG.LINKUP, linkType = linkType, players = seats })
    -- pokefirered/src/cable_club.c:838
    lk:send({ type = LB.MSG.SEAT, seat = LB.seat })
    local ok, sent = pcall(sendSetup)
    if not ok or not sent then
      arenaFail(ok and "setup_not_sent" or tostring(sent))
      return false
    end
  end
  local up = lk:take(LB.MSG.LINKUP)
  while up do
    if tonumber(up.linkType) ~= lk.linkType then
      -- pokefirered/src/cable_club.c:122
      arenaFail("diff_selections")
      return false
    end
    s.linkup = true
    up = lk:take(LB.MSG.LINKUP)
  end
  local seat = lk:take(LB.MSG.SEAT)
  while seat do
    s.seats[tonumber(seat.seat) or 1] = true
    s.seated = true
    seat = lk:take(LB.MSG.SEAT)
  end
  local setup = lk:take(LB.MSG.SETUP)
  while setup do
    s.peerSetup = s.peerSetup or setup
    local from = tonumber(setup.seat) or 1
    s.setups[from] = s.setups[from] or setup
    setup = lk:take(LB.MSG.SETUP)
  end
  if LB.isMulti() then
    local need = (tonumber(LB._arena.seats) or 4) - 1
    local nSeats, nSetups = 0, 0
    for _ in pairs(s.seats) do nSeats = nSeats + 1 end
    for _ in pairs(s.setups) do nSetups = nSetups + 1 end
    if nSeats < need or nSetups < need then return false end
    local done = LB._arenaDone
    LB._arenaDone = nil
    LB.state = "setup"
    LB.beginMulti(s.setups, function(result)
      if done then done(result) end
    end)
    return true
  end
  if not (s.seated and s.peerSetup) then return false end
  local done = LB._arenaDone
  LB._arenaDone = nil
  LB.state = "setup"
  LB.beginBattle(s.peerSetup, function(result)
    if done then done(result) end
  end)
  return true
end

function LB.startSpectator(spec, onDone)
  LB.reset()
  LB.freshBattle()
  local okT, t = pcall(function()
    if spec.transport then return spec.transport end
    return require("src.core.game3.link.relay_transport").new(spec.session, { client = spec.client })
  end)
  if not okT or not t then
    if onDone then onDone("error") end
    return false, tostring(t)
  end
  LB._spec = {
    spec = spec, t = t, done = onDone,
    setups = {}, actions = { [0] = {}, [1] = {}, [2] = {}, [3] = {} },
    switches = { [0] = {}, [1] = {}, [2] = {}, [3] = {} },
    outcomes = {}, gone = false,
  }
  LB.mode = LB.MODE_OF[spec.mode or "single"] or LB.MODE_OF.single
  LB.unionRoom = false
  LB.seat = nil
  LB.seed = LB.seedFromRelay()
  LB.headless = spec.headless or nil
  LB.fade = false
  LB.state = "spectate_setup"
  LB.spectatorStep()
  return true
end

local function spectatorFinish(word)
  local sp = LB._spec
  if not sp or sp.finished then return end
  sp.finished = true
  local done = sp.done
  sp.done = nil
  if done then done(word) end
end

LB.spectatorFinish = spectatorFinish

function LB.pumpSpectator()
  local sp = LB._spec
  if not sp then return end
  local t = sp.t
  if t.update then pcall(t.update, t) end
  local ok, msgs = pcall(t.poll, t)
  if not ok or type(msgs) ~= "table" then
    sp.gone = true
    return
  end
  for _, msg in ipairs(msgs) do
    local seat = tonumber(msg.seat)
    local kind = msg.type
    if seat and seat >= 0 and seat <= ((LB.isMulti() and 3) or 1) then
      if kind == LB.MSG.SETUP then
        sp.setups[seat] = sp.setups[seat] or msg
      elseif kind == LB.MSG.ACTION then
        local turn = math.floor(tonumber(msg.turn) or 0)
        if turn > 0 then
          sp.actions[seat][turn] = msg
          sp.lastTurn = math.max(sp.lastTurn or 0, turn)
        end
      elseif kind == LB.MSG.SWITCH then
        local q = sp.switches[seat]
        q[#q + 1] = math.floor(tonumber(msg.slot) or 1)
      elseif kind == LB.MSG.HASH then
        noteHash(msg, seat)
      elseif kind == LB.MSG.OUTCOME then
        sp.outcomes[seat] = tonumber(msg.outcome)
      elseif kind == "game3_bye" or kind == "bye" or kind == LB.MSG.FORFEIT then
        sp.left = sp.left or {}
        sp.left[seat] = true
      end
    end
  end
  if t.closed or t.error then sp.gone = true end
  LB.checkHashes()
end

function LB.spectatorBehind()
  local sp = LB._spec
  if not sp or LB.state ~= "battle" then return false end
  local st = battleState()
  local turn = st and st.turn or 0
  return (sp.lastTurn or 0) > turn + 1
end

function LB.spectatorStep()
  if LB.state ~= "spectate_setup" then return false end
  local sp = LB._spec
  LB.pumpSpectator()
  if LB.isMulti() then return LB.spectatorStepMulti() end
  if sp.gone and not (sp.setups[0] and sp.setups[1]) then
    LB.state = "off"
    spectatorFinish("error")
    return false
  end
  if not (sp.setups[0] and sp.setups[1]) then return false end
  if LB.seed == nil then
    LB.state = "off"
    spectatorFinish("error")
    return false
  end
  local mine, whyA = LB.unpackParty(sp.setups[0].party)
  local theirs, whyB = LB.unpackParty(sp.setups[1].party)
  if not (mine and theirs) then
    note("spectator refused a party: %s", tostring(whyA or whyB))
    LB.state = "off"
    spectatorFinish("error")
    return false
  end
  local host, guest = sp.setups[0], sp.setups[1]
  local foe = LB.foeFrom({ name = guest.name, party = theirs })
  LB.peer = { name = guest.name, trainerId = tonumber(guest.trainerId) or 0, gender = tonumber(guest.gender) or 0 }
  sp.watched = {
    name = host.name, trainerId = tonumber(host.trainerId) or 0,
    gender = (tonumber(host.gender) == 1) and 1 or 0, party = mine,
    bag = {}, store = { flags = {}, vars = {} },
  }
  LB.state = "battle"
  LB._started = true
  local flags = LB.BATTLE_TYPE.TRAINER + LB.BATTLE_TYPE.LINK + LB.BATTLE_TYPE.IS_MASTER
  if LB.mode == LB.MODE_OF.double then flags = flags + LB.BATTLE_TYPE.DOUBLE end
  local BattleBridge = require("src.core.game3.battle_bridge")
  local rt = package.loaded["src.core.game3.runtime"]
  local ok, started, err = pcall(BattleBridge.start, rt and rt._mod, link().game(), foe, {
    link = true,
    spectate = true,
    autoFight = false,
    session = sp.watched,
    linkParty = mine,
    linkFlags = flags,
    linkMaster = true,
    double = LB.mode == LB.MODE_OF.double,
    unionRoom = false,
    rng = LB.makeRng(LB.seed, LB._draws),
    peerName = guest.name,
    trainerName = guest.name,
    trainerPicId = LB.peerPicId(guest),
    song = LB.battleSong(guest, host),
    playerGender = sp.watched.gender,
    headless = LB.headless,
    fade = false,
    done = function(result)
      LB._started = false
      LB.outcome = LB.outcomeCode(result)
      LB.state = "done"
      spectatorFinish(LB.endReason == "desync" and "error" or "ended")
    end,
  })
  if not ok or not started then
    note("spectator battle did not start: %s", tostring(ok and err or started))
    LB.state = "off"
    LB._started = false
    spectatorFinish("error")
    return false
  end
  return true
end

function LB.spectatorStepMulti()
  local sp = LB._spec
  local all = sp.setups[0] and sp.setups[1] and sp.setups[2] and sp.setups[3]
  if sp.gone and not all then
    LB.state = "off"
    spectatorFinish("error")
    return false
  end
  if not all then return false end
  if LB.seed == nil then
    LB.state = "off"
    spectatorFinish("error")
    return false
  end
  local parties, names, info = {}, {}, {}
  for seat = 0, 3 do
    local party, why = LB.unpackMultiParty(sp.setups[seat].party)
    if not party then
      note("spectator refused a party: %s", tostring(why))
      LB.state = "off"
      spectatorFinish("error")
      return false
    end
    parties[seat] = party
    info[seat] = setupInfo(sp.setups[seat])
    names[seat] = info[seat].name
  end
  local genders = {}
  for seat = 0, 3 do genders[seat] = info[seat].gender end
  local layout, playerParty, foeParty = LB.multiLayout(nil, parties, names, genders)
  local foe = LB.foeFrom({ name = names[1], party = foeParty })
  LB.peer = info[1]
  LB.multiNames = names
  sp.watched = {
    name = names[0], trainerId = info[0].trainerId, gender = info[0].gender, party = playerParty,
    bag = {}, store = { flags = {}, vars = {} },
  }
  LB.state = "battle"
  LB._started = true
  local flags = LB.BATTLE_TYPE.TRAINER + LB.BATTLE_TYPE.LINK + LB.BATTLE_TYPE.IS_MASTER
    + LB.BATTLE_TYPE.DOUBLE + LB.BATTLE_TYPE.MULTI
  local BattleBridge = require("src.core.game3.battle_bridge")
  local rt = package.loaded["src.core.game3.runtime"]
  local ok, started, err = pcall(BattleBridge.start, rt and rt._mod, link().game(), foe, {
    link = true,
    spectate = true,
    autoFight = false,
    session = sp.watched,
    linkParty = playerParty,
    linkFlags = flags,
    linkMaster = true,
    double = true,
    multi = layout,
    unionRoom = false,
    rng = LB.makeRng(LB.seed, LB._draws),
    peerName = names[1],
    trainerName = names[1],
    trainerPicId = LB.peerPicId(info[1]),
    song = LB.battleSong(info[0], info[0]),
    playerGender = sp.watched.gender,
    headless = LB.headless,
    fade = false,
    done = function(result)
      LB._started = false
      LB.outcome = LB.outcomeCode(result)
      LB.state = "done"
      spectatorFinish(LB.endReason == "desync" and "error" or "ended")
    end,
  })
  if not ok or not started then
    note("spectator battle did not start: %s", tostring(ok and err or started))
    LB.state = "off"
    LB._started = false
    spectatorFinish("error")
    return false
  end
  return true
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
  LB.autoFight = nil
  LB.fade = nil
  LB._started = false
  LB._onSetup = nil
  LB._arena = nil
  LB._arenaDone = nil
  LB._arenaSetup = nil
  LB._spec = nil
  LB.freshBattle()
end

return LB
