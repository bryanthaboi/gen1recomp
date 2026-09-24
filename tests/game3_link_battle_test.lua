#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local COUNTER_MAP = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F"
local COLOSSEUM_MAP = "FR_BATTLE_COLOSSEUM_2P"
local UNION_MAP = "FR_UNION_ROOM"

local MAPS = {
  [COUNTER_MAP] = {
    warps = { { x = 9, y = 1, destMap = COLOSSEUM_MAP, destWarp = 1 } },
  },
  [COLOSSEUM_MAP] = {
    warps = { { x = 6, y = 8, mapGroup = 0x7F, mapNum = 0x7F, destWarp = 128 } },
  },
  [UNION_MAP] = {
    warps = { { x = 7, y = 11, mapGroup = 0x7F, mapNum = 0x7F, destWarp = 128 } },
  },
}

local function legal(mon)
  local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
  local okS, SummaryData = pcall(require, "src.core.game3.summary_data")
  if mon.exp == nil and okP and okS then
    local okE, exp = pcall(function()
      return SummaryData.expForLevel(Pokemon.growthRate(mon.species), mon.level)
    end)
    if okE then mon.exp = exp end
  end
  mon.otName = mon.otName or "RED"
  mon.otId = mon.otId or 0x1234
  mon.personality = mon.personality or 0
  return mon
end

local function charizard()
  return legal({ species = 6, level = 60, hp = 200, maxHp = 200,
    moves = { 53 }, pp = { 15 }, maxPp = { 15 } })
end

local function blastoise()
  return legal({ species = 9, level = 60, hp = 190, maxHp = 190,
    moves = { 57 }, pp = { 15 }, maxPp = { 15 } })
end

local function packed(list)
  local Protocol = require("src.link.Protocol")
  local out = {}
  for i, mon in ipairs(list) do out[i] = Protocol.packMon3(legal(mon)) end
  return out
end

local store = { flags = {}, vars = {} }
local session = {
  store = store,
  map = COLOSSEUM_MAP,
  x = 6,
  y = 8,
  name = "RED",
  gender = 0,
  trainerId = 0x1234,
  party = { charizard() },
  bag = { pockets = { items = { [4] = 3 } } },
}
local game = { data = { maps = MAPS }, session = session }

package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  isActive = function() return true end,
  _game = game,
  _mod = nil,
}

package.loaded["src.core.game3.player"] = { cellX = 6, cellY = 8, facing = "up" }
package.loaded["src.core.game3.map"] = { load = function() end, current = COLOSSEUM_MAP }
package.loaded["src.core.game3.objects"] = {
  addObject = function() return true end,
  removeObject = function() return true end,
  refreshGraphics = function() return 0 end,
}

local ctx = { specialVars = {}, stringVars = {} }
local adapters = { log = function() end, playSe = function() end }
local romBundle = require("tests.game3_cache").bundle()
if not romBundle then
  package.loaded["src.core.game3.rom_text"] = {
    plain = function(key) return key end, box = function(key) return key end,
    ascii = function(key) return key end, has = function() return true end,
    ir = function(key) return { { t = "text", s = key } } end,
    translate = function(ir) return ir end,
    key = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
    at = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
    count = function() return 0 end, list = function() return {} end,
    lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
  }
end

package.loaded["src.core.game3.scripting.space"] = {
  store = store,
  mapId = COLOSSEUM_MAP,
  vm = { ctx = ctx, adapters = adapters },
  ensureBundle = function() return romBundle end,
}
local Space = package.loaded["src.core.game3.scripting.space"]

local Natives = require("src.core.game3.scripting.natives")
local NativesLink = require("src.core.game3.scripting.natives_link")
local Link = require("src.core.game3.link")
local LB = require("src.core.game3.link.battle")
local Union = require("src.core.game3.link.union_room")
local FakeRelay = require("tests.g3link_fake_relay")
local Battle = require("src.core.game3.battle")
local Engine = require("src.core.game3.battle.engine")
local Flags = require("src.core.game3.scripting.flags")
local Std = require("src.core.game3.scripting.stdscripts")
local Ui = require("src.core.game3.battle.ui")

local function getVar(id)
  return tonumber(Flags.getVar(store, ctx, id)) or 0
end

local function setVar(id, value)
  Flags.setVar(store, ctx, id, value)
end

local function freshCtx()
  ctx.specialVars = {}
  ctx.nativePoll = nil
  ctx.mode = nil
  ctx.status = nil
end

local function pumpLink(host, guest)
  host:update(0)
  guest:update(0)
end

print("[test] 1. the colosseum specials answer to their pret def_special index")
local EXPECTED = {
  TryBattleLinkup = 0x1C,
  TryRecordMixLinkup = 0x1E,
  EnterColosseumPlayerSpot = 0x20,
}
for name, id in pairs(EXPECTED) do
  eq(NativesLink.SPECIAL[name], id, "NativesLink.SPECIAL." .. name)
  check(Natives.ALLOW["special:" .. id] ~= nil, name .. " is bound in Natives.ALLOW")
  eq(Std.SPECIAL_NAME_BY_ID[id], name, string.format("special 0x%X is declared by its pret name", id))
end
do
  local logs = {}
  local quiet = { log = function(m) logs[#logs + 1] = m end }
  for _, id in ipairs({ 0x1C, 0x1E, 0x20 }) do
    local _, _, known = Natives.special({ specialVars = {} }, id, quiet)
    check(known, string.format("special 0x%X dispatches to a handler", id))
  end
  eq(#logs, 0, "nothing reached the unknown-special log")
end
Link.reset()

print("[test] 2. party validation refuses what the counter refuses")
session.party = { { species = 1, level = 5, hp = 20, maxHp = 20, isBadEgg = true } }
local ok, reason = LB.validateParty(session, Link.USING.SINGLE_BATTLE)
check(not ok, "a BAD EGG cannot enter the cable club")
eq(reason, "bad_egg", "and the reason is the bad egg")

session.party = { { species = 1, level = 5, hp = 20, maxHp = 20, isEgg = true } }
ok, reason = LB.validateParty(session, Link.USING.SINGLE_BATTLE)
check(not ok, "an egg-only party cannot battle")
eq(reason, "no_mons", "because no mon is battle eligible")

session.party = { charizard() }
ok, reason = LB.validateParty(session, Link.USING.DOUBLE_BATTLE)
check(not ok, "one mon is not enough for a double battle")
eq(reason, "need_two_mons", "HasEnoughMonsForDoubleBattle answers PLAYER_HAS_ONE_MON")

session.party = { charizard(), blastoise() }
ok = LB.validateParty(session, Link.USING.DOUBLE_BATTLE)
check(ok, "two usable mons pass the double battle check")

ok, reason = LB.validateParty(session, Link.USING.SINGLE_BATTLE, { unionRoom = true })
check(not ok, "two level 60 mons cannot enter a union room battle")
eq(reason, "level_cap", "UNION_ROOM_MAX_LEVEL refuses them")

session.party = {
  { species = 1, level = 12, hp = 30, maxHp = 30, moves = { 33 }, pp = { 35 }, maxPp = { 35 } },
  { species = 4, level = 9, hp = 25, maxHp = 25, moves = { 10 }, pp = { 35 }, maxPp = { 35 } },
}
ok = LB.validateParty(session, Link.USING.SINGLE_BATTLE, { unionRoom = true })
check(ok, "two mons at or below Lv. 30 may enter the union room")

session.party[1].heldItem = 175
ok, reason = LB.validateParty(session, Link.USING.SINGLE_BATTLE, { unionRoom = true })
check(not ok, "an ENIGMA BERRY keeps the party out of the union room")
eq(reason, "enigma_berry", "which is what CheckPartyUnionRoomRequirements checks")
session.party[1].heldItem = nil

print("[test] 3. the script's own double battle gate, and the pret LINKUP codes")
session.party = { charizard() }
freshCtx()
Natives.special(ctx, NativesLink.SPECIAL.HasEnoughMonsForDoubleBattle, adapters)
eq(getVar(Link.VAR_RESULT), 1,
  "one mon answers PLAYER_HAS_ONE_MON, which is the counter's own double battle gate")
session.party = { charizard(), blastoise() }
freshCtx()
Natives.special(ctx, NativesLink.SPECIAL.HasEnoughMonsForDoubleBattle, adapters)
eq(getVar(Link.VAR_RESULT), 0, "two usable mons answer PLAYER_HAS_TWO_USABLE_MONS")

session.party = { charizard() }
Link.reset()
freshCtx()
setVar(Link.VAR_0x8004, Link.USING.SINGLE_BATTLE)
local waited = Natives.special(ctx, NativesLink.SPECIAL.TryBattleLinkup, adapters)
-- pokefirered/src/cable_club.c:208-222
check(waited, "with no cable yet the counter parks the script instead of answering")
eq(getVar(Link.VAR_RESULT), Link.LINKUP.ONGOING, "and reports LINKUP_ONGOING while it waits")
local spun = 0
for _ = 1, LB.LINKUP_TICKS + 1 do
  if ctx.nativePoll() then break end
  spun = spun + 1
end
-- pokefirered/src/cable_club.c:482 TryLinkTimeout
eq(spun, LB.LINKUP_TICKS, "it waits the full TryLinkTimeout window before giving up")
eq(getVar(Link.VAR_RESULT), Link.LINKUP.CONNECTION_ERROR,
  "and a partner that never arrives is LINKUP_CONNECTION_ERROR")

local host, guest = FakeRelay.pair({ game = game })
pumpLink(host, guest)
Link.attach(host)
freshCtx()
setVar(Link.VAR_0x8004, Link.USING.SINGLE_BATTLE)
local yielded = Natives.special(ctx, NativesLink.SPECIAL.TryBattleLinkup, adapters)
check(yielded, "the script yields while the linkup runs")
eq(getVar(Link.VAR_RESULT), Link.LINKUP.ONGOING, "VAR_RESULT is LINKUP_ONGOING while it waits")
check(ctx.nativePoll() == false, "nothing is decided before the peer says what it picked")
guest:update(0)
local peerPick = guest:take(LB.MSG.LINKUP)
eq(peerPick and peerPick.linkType, LB.LINKTYPE.SINGLE_BATTLE,
  "the peer was told this machine picked LINKTYPE_SINGLE_BATTLE")
guest:send({ type = LB.MSG.LINKUP, linkType = LB.LINKTYPE.SINGLE_BATTLE, players = 2 })
host:update(0)
check(ctx.nativePoll() == true, "the poll settles once both picks are in")
eq(getVar(Link.VAR_RESULT), Link.LINKUP.SUCCESS, "matching picks report LINKUP_SUCCESS")
eq(LB.state, "seat", "and the session is waiting for a colosseum seat")

freshCtx()
setVar(Link.VAR_0x8004, Link.USING.SINGLE_BATTLE)
Natives.special(ctx, NativesLink.SPECIAL.TryBattleLinkup, adapters)
guest:update(0)
guest:take(LB.MSG.LINKUP)
guest:send({ type = LB.MSG.LINKUP, linkType = LB.LINKTYPE.MULTI_BATTLE, players = 4 })
host:update(0)
ctx.nativePoll()
eq(getVar(Link.VAR_RESULT), Link.LINKUP.DIFF_SELECTIONS,
  "a peer that picked another mode reports LINKUP_DIFF_SELECTIONS")

freshCtx()
setVar(Link.VAR_0x8004, Link.USING.MULTI_BATTLE)
Natives.special(ctx, NativesLink.SPECIAL.TryBattleLinkup, adapters)
guest:update(0)
local multiPick = guest:take(LB.MSG.LINKUP)
eq(multiPick and multiPick.linkType, LB.LINKTYPE.MULTI_BATTLE, "MULTI BATTLE picks LINKTYPE_MULTI_BATTLE")
guest:send({ type = LB.MSG.LINKUP, linkType = LB.LINKTYPE.MULTI_BATTLE, players = 4 })
host:update(0)
ctx.nativePoll()
eq(getVar(Link.VAR_RESULT), Link.LINKUP.WRONG_NUM_PLAYERS,
  "a four player mode on a two machine cable reports LINKUP_WRONG_NUM_PLAYERS")

Link.closeLink("test")
freshCtx()
setVar(Link.VAR_0x8004, Link.USING.SINGLE_BATTLE)
Natives.special(ctx, NativesLink.SPECIAL.TryBattleLinkup, adapters)
eq(getVar(Link.VAR_RESULT), Link.LINKUP.ONGOING,
  "a torn down link puts the counter back to waiting for a machine")
for _ = 1, LB.LINKUP_TICKS + 1 do
  if ctx.nativePoll() then break end
end
eq(getVar(Link.VAR_RESULT), Link.LINKUP.CONNECTION_ERROR,
  "and times out to LINKUP_CONNECTION_ERROR")
Link.reset()

print("[test] 4. the shared seed drives one RNG stream on both machines")
local mine = LB.makeRng(0xC0FFEE)
local theirs = LB.makeRng(0xC0FFEE)
local other = LB.makeRng(0xC0FFEF)
local same, drift = true, false
for _ = 1, 64 do
  local a, b, c = mine(0, 255), theirs(0, 255), other(0, 255)
  if a ~= b then same = false end
  if a ~= c then drift = true end
end
check(same, "the same seed gives both machines the same 64 rolls")
check(drift, "a different seed gives a different stream")

print("[test] 5. EnterColosseumPlayerSpot exchanges the seat and the parties")
Link.reset()
session.party = { charizard() }
host, guest = FakeRelay.pair({ game = game })
pumpLink(host, guest)
Link.attach(host)
LB.headless = true
LB.fade = false
freshCtx()
setVar(Link.VAR_0x8004, Link.USING.SINGLE_BATTLE)
setVar(LB.VAR_0x8005, 0)
yielded = Natives.special(ctx, NativesLink.SPECIAL.EnterColosseumPlayerSpot, adapters)
check(yielded, "the script yields while the seat is taken")
eq(LB.seat, 0, "the seat id came from VAR_0x8005")
if not romBundle then
  print("[skip] 5-32. the link battle runs on ROM species, move, trainer and battle text data: "
    .. tostring(require("tests.game3_cache").reason))
  os.exit(failed == 0 and 0 or 1)
end
check(ctx.nativePoll() == false, "nothing starts before the peer sits down")
guest:update(0)
local seat = guest:take(LB.MSG.SEAT)
check(seat ~= nil, "the peer saw this player take a colosseum seat")
local mySetup = guest:take(LB.MSG.SETUP)
check(mySetup ~= nil, "and received this player's party and seed")
eq(mySetup and mySetup.name, "RED", "with the player's name")
eq(#(mySetup and mySetup.party or {}), 1, "and one mon on the wire")
eq(type(mySetup and mySetup.party and mySetup.party[1] and mySetup.party[1].species), "number",
  "the party goes out as packMon3 rows")
guest:send({ type = LB.MSG.SEAT, seat = 1 })
guest:send({
  type = LB.MSG.SETUP, seed = mySetup and mySetup.seed, mode = Link.USING.SINGLE_BATTLE,
  name = "BLUE", trainerId = 0x2222, gender = 0, party = packed({ blastoise() }),
})
host:update(0)
check(ctx.nativePoll() == true, "both seats taken starts the battle")

print("[test] 6. BATTLE_TYPE_LINK reaches the engine state")
local st = Battle.getState()
check(Battle.isActive(), "the link battle is running")
eq(st and st.link, true, "st.link is set, so the engine's link branches are live")
eq(st and st.peerName, "BLUE", "the peer's name rides along for the end-of-battle text")
eq(st and st.trainerId, nil, "TRAINER_LINK_OPPONENT is no gTrainers row, so there is no trainer id")
eq(st and st.trainerPicId, LB.TRAINER_PIC_RED, "the opponent is drawn as the peer's own player sprite")
eq(LB.peerPicId({ gender = 1 }), LB.TRAINER_PIC_LEAF, "a female peer is drawn as LEAF")
-- pokefirered/src/battle_main.c:909 the cable master also gets BATTLE_TYPE_IS_MASTER
eq(st and st.linkFlags,
  LB.BATTLE_TYPE.TRAINER + LB.BATTLE_TYPE.LINK + LB.BATTLE_TYPE.IS_MASTER,
  "BATTLE_TYPE_TRAINER | BATTLE_TYPE_LINK | BATTLE_TYPE_IS_MASTER on the leader")
eq(st and st.linkMaster, true, "and the leader owns battler 0 on both machines")
eq(LB.battleFlags(Link.USING.DOUBLE_BATTLE),
  LB.BATTLE_TYPE.TRAINER + LB.BATTLE_TYPE.LINK + LB.BATTLE_TYPE.IS_MASTER
    + LB.BATTLE_TYPE.DOUBLE,
  "a double battle adds BATTLE_TYPE_DOUBLE")
eq(LB.battleFlags(Link.USING.MULTI_BATTLE),
  LB.BATTLE_TYPE.TRAINER + LB.BATTLE_TYPE.LINK + LB.BATTLE_TYPE.IS_MASTER
    + LB.BATTLE_TYPE.DOUBLE + LB.BATTLE_TYPE.MULTI,
  "a multi battle adds BATTLE_TYPE_MULTI too")

print("[test] 7. neither machine resolves a turn before both actions are on the wire")
eq(Battle._phase, "linkwait", "this side is parked waiting for the peer's action")
guest:update(0)
local act = guest:take(LB.MSG.ACTION)
check(act ~= nil, "the peer received this player's chosen action")
eq(act and act.turn, 1, "tagged with turn 1")
eq(act and act.kind, "move", "as a move")
Battle.update(0, nil)
eq(Battle._phase, "linkwait", "and an update with no answer still resolves nothing")
guest:send({ type = LB.MSG.ACTION, turn = act.turn, kind = "move", slot = 1 })
host:update(0)
Battle.update(0, nil)
check(Battle._phase ~= "linkwait", "the peer's answer releases the turn")
eq(Battle.getState().turn, 1, "which is turn 1")

print("[test] 8. running is allowed in a link battle and no EXP is handed out")
check(Engine.canRun(Battle.getState(), Battle._adapter, Battle.getState().player),
  "a link battle may be run from, unlike any other trainer battle")
local trainerSt = { wild = false, player = {}, enemy = {} }
check(not Engine.canRun(trainerSt, Battle._adapter, trainerSt.player),
  "an ordinary trainer battle still refuses")

local guard = 0
while Battle.isActive() and guard < 600 do
  guard = guard + 1
  Battle.update(0, nil)
  if Battle._phase == "linkwait" then
    guest:update(0)
    local a = guest:take(LB.MSG.ACTION)
    if a then
      guest:send({ type = LB.MSG.ACTION, turn = a.turn, kind = "move", slot = 1 })
      host:update(0)
    end
  end
end
check(not Battle.isActive(), "the link battle finished")
local log = Ui.log() or {}
local sawExp, sawEnd = false, nil
for _, line in ipairs(log) do
  if line:find("EXP. Points", 1, true) then sawExp = true end
  if line:find("BLUE!", 1, true) then sawEnd = line end
end
check(not sawExp, "no EXP line: a link battle gives none")
if romBundle then
  check(sawEnd ~= nil, "the battle ends on the link battle string, naming the peer")
else
  print("[skip] ROM text: the link battle outcome string")
end

print("[test] 9. the record the battle records screen reads")
eq(LB.outcome, LB.outcomeCode(Battle.getResult()), "the outcome was recorded")
local records = session.linkBattleRecords or {}
eq(#records, 1, "one opponent is on record")
eq(records[1] and records[1].name, "BLUE", "under the peer's name")
eq(records[1] and records[1].trainerId, 0x2222, "and the peer's trainer id")
eq((tonumber(records[1] and records[1].wins) or 0)
  + (tonumber(records[1] and records[1].losses) or 0)
  + (tonumber(records[1] and records[1].draws) or 0), 1, "with exactly one battle in it")
local stats = session.gameStats or {}
eq((tonumber(stats.linkBattleWins) or 0) + (tonumber(stats.linkBattleLosses) or 0)
  + (tonumber(stats.linkBattleDraws) or 0), 1, "and one GAME_STAT_LINK_BATTLE_* bump")
local card = session.trainerCard or {}
eq((tonumber(card.linkBattleWins) or 0) + (tonumber(card.linkBattleLosses) or 0), 1,
  "the trainer card counts it too")

do
  local Records = require("src.ui.game3.trainer_tower_records")
  Records.show({ session = session, kind = "link", onDone = function() end })
  local rows = Records.rows() or {}
  eq(rows[1] and rows[1].name, "BLUE", "ShowBattleRecords lists the peer in row 1")
  if Records.close then Records.close() end
end

print("[test] 10. AddOpponentLinkBattleRecord keeps five entries, sorted, capped at 9999")
session.linkBattleRecords = {}
session.gameStats = {}
for i = 1, 7 do
  LB.addOpponentRecord(session, "P" .. i, 0x1000 + i, LB.B_OUTCOME.WON)
end
eq(#session.linkBattleRecords, LB.RECORDS_COUNT, "LINK_B_RECORDS_COUNT entries at most")
for _ = 1, 3 do
  LB.addOpponentRecord(session, "P1", 0x1001, LB.B_OUTCOME.WON)
end
eq(session.linkBattleRecords[1].name, "P1", "the busiest opponent sorts to the top")
eq(session.linkBattleRecords[1].wins, 4, "and its wins accumulate")
session.linkBattleRecords[1].wins = LB.RECORD_MAX
LB.addOpponentRecord(session, "P1", 0x1001, LB.B_OUTCOME.WON)
eq(session.linkBattleRecords[1].wins, LB.RECORD_MAX, "a win count never passes 9999")
session.gameStats.linkBattleWins = LB.RECORD_MAX
LB.addOpponentRecord(session, "P1", 0x1001, LB.B_OUTCOME.WON)
eq(session.gameStats.linkBattleWins, LB.RECORD_MAX, "nor does the game stat")

print("[test] 11. SavePlayerParty and LoadPlayerParty bracket the exchange")
Link.reset()
session.linkBattleRecords = {}
session.gameStats = {}
session.party = { charizard(), blastoise() }
local Tower = require("src.core.game3.trainer_tower")
Tower.savePlayerParty(session)
session.party = { charizard() }
session.party[1].hp = 1
Link.loadPlayerBag()
session.bag = { pockets = { items = { [4] = 0 } } }
LB.mode = Link.USING.SINGLE_BATTLE
LB.unionRoom = false
LB.peer = { name = "BLUE", trainerId = 0x2222 }
LB._started = true
LB.finish("lose")
eq(#session.party, 2, "LoadPlayerParty gave the pre-link party back")
eq(session.party[1].hp, 200, "with the damage of the link battle discarded")
eq(session.bag.pockets.items[4], 3, "SavePlayerBag gave the pre-link bag back")

print("[test] 12. ChooseHalfPartyForBattle decides what goes on the wire")
session.party = { charizard(), blastoise(), charizard(), blastoise() }
Tower.setSelectedOrder(session, { 1, 3 })
local wire = LB.battleParty(session)
eq(#wire, 2, "only the chosen mons are sent")
eq(wire[1].species, 6, "in the order the player picked them")
eq(wire[2].species, 6, "second pick is party slot 3")
Tower.clearSelectedOrder(session)
eq(#LB.battleParty(session), 4, "with no selection the whole party goes")

print("[test] 13. a peer drop mid battle ends the match without a white-out")
Link.reset()
session.party = { charizard() }
session.money = 5000
host, guest = FakeRelay.pair({ game = game })
pumpLink(host, guest)
Link.attach(host)
LB.mode = Link.USING.SINGLE_BATTLE
LB.unionRoom = false
LB.seed = 999
LB.state = "setup"
LB.headless = true
LB.fade = false
LB.beginBattle({ seed = 999, name = "BLUE", trainerId = 0x2222, gender = 0,
  party = packed({ blastoise() }) })
check(Battle.isActive(), "the second link battle started")
guest:close("cable_pulled")
guest:update(0)
host:update(0)
Link.update(0)
check(not Battle.isActive(), "a yanked cable ends the battle")
eq(LB.outcome, LB.B_OUTCOME.DREW, "as a draw")
eq(session.money, 5000, "losing a link battle never costs money")
eq(Link.link, nil, "and the session is closed")

print("[test] 14. the union room routes ACTIVITY_BATTLE_SINGLE into a link battle")
Link.reset()
Union.reset()
Space.mapId = UNION_MAP
session.map = UNION_MAP
session.party = { charizard(), blastoise() }
host, guest = FakeRelay.pair({ game = game })
pumpLink(host, guest)
Link.attach(host)
LB.headless = true
LB.fade = false
Union.state = "start_activity"
Union.activity = Union.ACTIVITY.BATTLE_SINGLE + Union.IN_UNION_ROOM
Union.partnerId = 1
Union.update(0)
eq(Union.state, "print_and_exit", "an over-level party cannot start the union room battle")
Union.update(0)
eq(Union.state, "main", "and the room goes back to its main loop")
eq(Union.activity, nil, "with no pending activity")

session.party = {
  legal({ species = 1, level = 12, hp = 30, maxHp = 30, moves = { 33 }, pp = { 35 }, maxPp = { 35 } }),
  legal({ species = 4, level = 9, hp = 25, maxHp = 25, moves = { 10 }, pp = { 35 }, maxPp = { 35 } }),
}
Union.state = "start_activity"
Union.activity = Union.ACTIVITY.BATTLE_SINGLE + Union.IN_UNION_ROOM
Union.partnerId = 1
Union.update(0)
eq(Union.state, "in_activity", "a legal party starts the activity")
eq(LB.state, "setup", "and the link battle is waiting for the peer's party")
eq(LB.unionRoom, true, "flagged as a union room battle, which keeps it off the records")
guest:update(0)
local urSetup = guest:take(LB.MSG.SETUP)
check(urSetup ~= nil, "the peer was offered this player's party")
guest:send({ type = LB.MSG.SETUP, seed = urSetup and urSetup.seed,
  name = "BLUE", trainerId = 0x2222, gender = 0, party = packed({ blastoise() }) })
host:update(0)
Union.update(0)
check(Battle.isActive(), "the union room battle started")
eq(Battle.getState().link, true, "with BATTLE_TYPE_LINK")
local urClasses = LB.unionRoomClasses()
eq(Battle.getState().trainerPicId, urClasses.trainerPic[0x2222 % 8],
  "the peer is drawn with GetUnionRoomTrainerPic, not RED/LEAF")
local urFill = require("src.core.game3.battle.adapter").fill(Battle.getState())
eq(urFill.trainer1Class, urClasses.trainerClass[0x2222 % 8], "B_TRAINER1_CLASS is GetUnionRoomTrainerClass")
eq(urFill.trainer1Name, "BLUE", "B_TRAINER1_NAME is the peer's link name")
local urIntro = require("src.core.game3.battle.intro_seq").introText(Battle.getState())
local urRomText = require("src.core.game3.rom_text")
local urClassName = urRomText.plain(urRomText.key("gTrainerClassNames", urClasses.trainerClass[0x2222 % 8]))
check(urIntro:find(urClassName, 1, true) ~= nil and urIntro:find("BLUE", 1, true) ~= nil,
  "the intro is sText_Trainer1WantsToBattle with the union room class and the peer's name")
local urLog = Ui.log() or {}
local urPushed = false
for _, line in ipairs(urLog) do
  if line == urIntro then urPushed = true end
end
check(urPushed, "the battle printed that union room intro")
local urNone = require("src.core.game3.scripting.trainers").info(0)
local urNoneName = urNone and urNone.name
if urNoneName and urNoneName ~= "" and urNoneName ~= "BLUE" then
  check(table.concat(urLog, " | "):find(urNoneName, 1, true) == nil, "trainer 0 never reaches the union room intro")
end
Battle.abort("draw")
session.linkBattleRecords = {}
LB.finish("draw")
eq(#(session.linkBattleRecords or {}), 0,
  "a union room battle is not written to the battle records")

print("[test] 15. a double link battle takes both actions off the cable")
Link.reset()
local function linkMon(sp, lv, m1, m2)
  return legal({ species = sp, level = lv, hp = 100, maxHp = 100,
    moves = { m1, m2 }, pp = { 15, 15 }, maxPp = { 15, 15 } })
end
session.party = { linkMon(6, 30, 53), linkMon(9, 30, 57) }
host, guest = FakeRelay.pair({ game = game })
pumpLink(host, guest)
Link.attach(host)
LB.headless = true
LB.fade = false
LB.mode = Link.USING.DOUBLE_BATTLE
LB.seed = 4242
LB.state = "setup"
LB.beginBattle({ seed = 4242, name = "BLUE", trainerId = 0x2222, gender = 0,
  party = packed({ linkMon(129, 30, 33, 45), linkMon(1, 30, 33, 45) }) })
local dbl = Battle.getState()
eq(dbl and dbl.double, true, "the colosseum's DOUBLE BATTLE mode is a double battle")
eq(Battle._phase, "linkwait", "and it waits for the peer before resolving turn 1")
guest:update(0)
local dblAct = guest:take(LB.MSG.ACTION)
eq(dblAct and dblAct.kind, "list", "both of this machine's actions went out in one message")
eq(#((dblAct and dblAct.actions) or {}), 2, "one per battler")
guest:send({ type = LB.MSG.ACTION, turn = dblAct.turn, kind = "list",
  actions = { { kind = "move", slot = 2 }, { kind = "move", slot = 2 } } })
host:update(0)
Battle.update(0, nil)
check(Battle._phase ~= "linkwait", "the peer's pair of actions releases the turn")
local sawGrowl = false
for _ = 1, 40 do
  if Battle.isActive() then Battle.update(0, nil) end
  for _, line in ipairs(Ui.log() or {}) do
    if line:find("GROWL", 1, true) then sawGrowl = true end
  end
end
check(sawGrowl, "the enemy used the move the peer picked, not the one its AI would have")
Battle.abort("draw")
LB.reset()

print("[test] 16. the replacement after a faint crosses the cable")
Link.reset()
session.linkBattleRecords = {}
session.gameStats = {}
session.party = { charizard() }
host, guest = FakeRelay.pair({ game = game })
pumpLink(host, guest)
Link.attach(host)
LB.headless = true
LB.fade = false
LB.mode = Link.USING.SINGLE_BATTLE
LB.seed = 31337
LB.state = "setup"
LB.beginBattle({ seed = 31337, name = "BLUE", trainerId = 0x2222, gender = 0,
  party = packed({
    legal({ species = 129, level = 5, hp = 20, maxHp = 20, moves = { 150 }, pp = { 40 }, maxPp = { 40 } }),
    legal({ species = 10, level = 5, hp = 20, maxHp = 20, moves = { 33 }, pp = { 35 }, maxPp = { 35 } }),
    blastoise(),
  }) })
check(Battle.isActive(), "the link battle with a three mon peer started")
guard = 0
while guard < 300 and Battle._phase ~= "linkswitch" and Battle.isActive() do
  guard = guard + 1
  Battle.update(0, nil)
  if Battle._phase == "linkwait" then
    guest:update(0)
    local a = guest:take(LB.MSG.ACTION)
    if a then
      guest:send({ type = LB.MSG.ACTION, turn = a.turn, kind = "move", slot = 1 })
      host:update(0)
    end
  end
end
eq(Battle._phase, "linkswitch", "the fainted peer's replacement is a lockstep wait")
for _ = 1, 30 do Battle.update(0, nil) end
eq(Battle._phase, "linkswitch", "and nothing is sent out while the peer has not said which mon")
guest:send({ type = LB.MSG.SWITCH, slot = 3 })
host:update(0)
Battle.update(0, nil)
local afterSwitch = Battle.getState()
eq(afterSwitch and afterSwitch.enemy and afterSwitch.enemy.partyIndex, 3,
  "the mon the peer named is the one that came out")
local sawLinkSendOut = false
for _, line in ipairs(Ui.log() or {}) do
  if line:find("BLUE sent", 1, true) then sawLinkSendOut = true end
end
check(sawLinkSendOut, "and the send-out names the link trainer, with no trainer class")
Battle.abort("draw")
LB.reset()

print("[test] 17. this machine's own replacement goes out over the cable")
Link.reset()
session.linkBattleRecords = {}
session.gameStats = {}
session.party = {
  legal({ species = 129, level = 5, hp = 20, maxHp = 20, moves = { 150 }, pp = { 40 }, maxPp = { 40 } }),
  charizard(),
}
host, guest = FakeRelay.pair({ game = game })
pumpLink(host, guest)
Link.attach(host)
LB.headless = true
LB.fade = false
LB.mode = Link.USING.SINGLE_BATTLE
LB.seed = 5150
LB.state = "setup"
LB.beginBattle({ seed = 5150, name = "BLUE", trainerId = 0x2222, gender = 0,
  party = packed({ blastoise() }) })
guard = 0
local sentSwitch = nil
while guard < 300 and Battle.isActive() and not sentSwitch do
  guard = guard + 1
  Battle.update(0, nil)
  guest:update(0)
  local a = guest:take(LB.MSG.ACTION)
  if a then
    guest:send({ type = LB.MSG.ACTION, turn = a.turn, kind = "move", slot = 1 })
    host:update(0)
  end
  sentSwitch = guest:take(LB.MSG.SWITCH)
end
check(sentSwitch ~= nil, "the peer was told which mon this machine sent out after its faint")
eq(sentSwitch and sentSwitch.slot, 2, "the party slot it chose")
Battle.abort("draw")
LB.reset()

print("[test] 18. the link battle BGM is the leader's, on both machines")
Link.reset()
host, guest = FakeRelay.pair({ game = game })
pumpLink(host, guest)
Link.attach(host)
session.trainerId = 0x1234
eq(LB.battleSong({ trainerId = 0x2223 }), LB.MUS_RS_VS_TRAINER,
  "an even leader id plays MUS_RS_VS_TRAINER")
session.trainerId = 0x1235
eq(LB.battleSong({ trainerId = 0x2222 }), LB.MUS_RS_VS_GYM_LEADER,
  "an odd leader id plays MUS_RS_VS_GYM_LEADER")
session.trainerId = 0x1234
Link.reset()

print("[test] 19. the imported colosseum really is where the counter warps")
local Cache = require("tests.game3_cache")
local root = Cache.mount("meta.json")
if not root then
  print("[skip] colosseum map check: " .. tostring(Cache.reason))
else
  local Dataset = require("src.core.game3.dataset")
  local realMaps = Dataset.buildMaps()
  local control = realMaps[COUNTER_MAP]
  if not (control and control.warps and #control.warps > 0) then
    print("[skip] colosseum map check: the mounted cache at " .. tostring(root) ..
      " carries no map warps")
  else
    local def = realMaps[COLOSSEUM_MAP]
    check(def ~= nil, "FR_BATTLE_COLOSSEUM_2P is in the imported cache")
    if def then
      local dynamic = false
      for _, w in ipairs(def.warps or {}) do
        if tonumber(w.mapNum) == 0x7F then dynamic = true end
      end
      check(dynamic, "and its exit is the MAP_DYNAMIC warp CleanupLinkRoomState spends")
    end
  end
end

print("[test] 20. the same battle run from both ends of one cable stays in step")
-- pokefirered/src/battle_controllers.c:148 InitLinkBtlControllers: the cable master owns
local TIE_SEED = 0xC0FFEE
local function tieMon(move, pp)
  return legal { species = 6, level = 50, hp = 150, maxHp = 150, moves = { move }, pp = { pp },
    maxPp = { pp }, personality = 0, gender = "M", nickname = "", friendship = 70,
    otId = 1, otName = "X",
    ivs = { hp = 10, atk = 10, def = 10, spe = 10, spa = 10, spd = 10 },
    evs = { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 },
    attack = 100, defense = 95, spAtk = 120, spDef = 100, speed = 115,
    ability = 66, abilityId = 66 }
end
local function runSeat(seat)
  Link.reset()
  if Battle.isActive() then Battle.abort("draw") end
  local mine = seat == 0 and tieMon(52, 25) or tieMon(10, 35)
  local theirs = seat == 0 and tieMon(10, 35) or tieMon(52, 25)
  session.party = { mine }
  session.linkBattleRecords = nil
  local a, b = FakeRelay.pair({ game = game })
  a:update(0)
  b:update(0)
  local me, peer = a, b
  if seat == 1 then me, peer = b, a end
  Link.attach(me)
  LB.dealSeed = function() return TIE_SEED end
  LB.headless = true
  LB.fade = false
  freshCtx()
  setVar(Link.VAR_0x8004, Link.USING.SINGLE_BATTLE)
  setVar(LB.VAR_0x8005, seat)
  Natives.special(ctx, NativesLink.SPECIAL.EnterColosseumPlayerSpot, adapters)
  peer:update(0)
  peer:take(LB.MSG.SEAT)
  peer:take(LB.MSG.SETUP)
  peer:send({ type = LB.MSG.SEAT, seat = 1 - seat })
  peer:send({ type = LB.MSG.SETUP, seed = TIE_SEED, mode = Link.USING.SINGLE_BATTLE,
    name = "BLUE", trainerId = 0x2222, gender = 0, party = packed({ theirs }) })
  me:update(0)
  ctx.nativePoll()
  local trace, guard, lastTurn = {}, 0, 0
  while Battle.isActive() and guard < 2000 do
    guard = guard + 1
    Battle.update(0, nil)
    local st = Battle.getState()
    if st and st.turn ~= lastTurn and Battle._phase == "linkwait" then
      lastTurn = st.turn
      trace[#trace + 1] = { st.player.mon.hp, st.enemy.mon.hp }
    end
    if Battle._phase == "linkwait" then
      peer:update(0)
      local act = peer:take(LB.MSG.ACTION)
      if act then
        peer:send({ type = LB.MSG.ACTION, turn = act.turn, kind = "move", slot = 1 })
        me:update(0)
      end
    end
  end
  return trace, Battle.getResult()
end

local traceA, resultA = runSeat(0)
local traceB, resultB = runSeat(1)
eq(#traceA, #traceB, "both machines fought the same number of turns")
local agreed = #traceA > 0
for i = 1, math.max(#traceA, #traceB) do
  local left, right = traceA[i] or {}, traceB[i] or {}
  if left[1] ~= right[2] or left[2] ~= right[1] then agreed = false end
end
check(agreed, "every turn's HP on the leader mirrors the same turn on the follower")
local mirror = { win = "lose", lose = "win", draw = "draw" }
eq(mirror[resultA] or resultA, resultB, "one machine's win is the other machine's loss")
eq(Engine.linkSeatSwap({ link = true, linkMaster = false }), true,
  "the follower reads battler1/battler2 swapped")
eq(Engine.linkSeatSwap({ link = true, linkMaster = true }), false,
  "the leader reads them straight")
eq(Engine.linkSeatSwap({ link = false, linkMaster = false }), false,
  "and a local battle is untouched by the seat rule")

print("[test] 21. BAG is refused in a link battle and the intro names the peer")
Link.reset()
if Battle.isActive() then Battle.abort("draw") end
session.party = { charizard() }
local bagHost, bagGuest = FakeRelay.pair({ game = game })
pumpLink(bagHost, bagGuest)
Link.attach(bagHost)
LB.mode = Link.USING.SINGLE_BATTLE
LB.unionRoom = false
LB.seed = TIE_SEED
LB.headless = true
LB.fade = false
Ui.reset({ headless = true })
LB.beginBattle({ name = "BLUE", trainerId = 0x2222, gender = 0, party = packed({ blastoise() }) })
local linkSt = Battle.getState()
eq(linkSt and linkSt.link, true, "the link battle is up")
local introLog = table.concat(Ui.log() or {}, " | "):gsub("\n", " ")
-- pokefirered/src/battle_message.c:389 sText_LinkTrainerWantsToBattle
check(introLog:find("BLUE wants to battle!", 1, true) ~= nil,
  "the intro is sText_LinkTrainerWantsToBattle, not the generic trainer line")
check(introLog:find("would like to battle", 1, true) == nil,
  "sText_Trainer1WantsToBattle never reaches a link battle")
local before = #(Ui.log() or {})
Battle._phase = "command"
-- pokefirered/src/battle_main.c:3182 BattleScript_ActionSelectionItemsCantBeUsed
local fakeInput = { wasPressed = function(_, key) return key == "a" end }
Ui._mode = "menu"
Ui._menuIndex = 2
check(Battle._refuseLinkItem(fakeInput), "A on BAG in a link battle is refused at selection")
local after = Ui.log() or {}
check(#after > before and tostring(after[#after]):find("can't be used", 1, true) ~= nil,
  "and the refusal prints sText_ItemsCantBeUsedNow")
Ui._mode = "menu"
Ui._menuIndex = 1
eq(Battle._refuseLinkItem(fakeInput), false, "FIGHT is not touched by the rule")

local Net = require("src.link.Net")
local Guard = require("src.core.game3.battle.link_guard")
local reported = {}
package.loaded["src.online.Client"] = {
  report = function(result) reported[#reported + 1] = result end,
  state = function() return "online" end,
}

local lastRoom

local function relayPair(seed)
  local me, peer, room = FakeRelay.pair({ game = game, seed = seed })
  lastRoom = room
  me:update(0)
  peer:update(0)
  me:update(0)
  peer:update(0)
  return me, peer
end

local function relayBattle(seed, mine, theirs, mode)
  Link.reset()
  if Battle.isActive() then Battle.abort("draw") end
  reported = {}
  session.party = mine
  session.linkBattleRecords = {}
  local me, peer = relayPair(seed)
  Link.attach(me)
  LB.headless = true
  LB.fade = false
  freshCtx()
  setVar(Link.VAR_0x8004, mode or Link.USING.SINGLE_BATTLE)
  setVar(LB.VAR_0x8005, 0)
  Natives.special(ctx, NativesLink.SPECIAL.EnterColosseumPlayerSpot, adapters)
  ctx.nativePoll()
  peer:update(0)
  local mySetup = peer:take(LB.MSG.SETUP)
  peer:take(LB.MSG.SEAT)
  peer:send({ type = LB.MSG.SEAT, seat = 1 })
  peer:send({ type = LB.MSG.SETUP, seed = 12345, mode = mode or Link.USING.SINGLE_BATTLE,
    name = "BLUE", trainerId = 0x2222, gender = 0, party = packed(theirs) })
  me:update(0)
  ctx.nativePoll()
  return me, peer, mySetup
end

print("[test] 22. on the relay every seat takes the seed from match_start")
do
  local _, _, mySetup = relayBattle(777, { charizard() }, { blastoise() })
  eq(LB.seed, 777, "the room seed, not a dealt one, drives the battle")
  eq(mySetup and mySetup.seed, nil, "and no seed rides the setup on the relay")
  check(Battle.isActive() and Battle.getState().link, "the relay battle is running")
  eq(LB.seedFromRelay(), 777, "LB.seedFromRelay reads the transport")
  Battle.abort("draw")
end

print("[test] 23. every seat hashes each resolved turn and a mismatch ends the battle as a draw")
do
  local me, peer = relayBattle(4242, { charizard(), blastoise() }, { blastoise(), charizard() })
  local hashes, guard, broke = {}, 0, false
  while Battle.isActive() and guard < 600 do
    guard = guard + 1
    Battle.update(0, nil)
    peer:update(0)
    local h = peer:take(LB.MSG.HASH)
    while h do
      hashes[#hashes + 1] = h
      if h.turn == 2 then
        broke = true
        peer:send({ type = LB.MSG.HASH, turn = 2, value = "00000000",
          parts = { actives = "00000000", volatile = h.parts.volatile, bench = h.parts.bench,
            field = h.parts.field, rng = h.parts.rng } })
      else
        peer:send({ type = LB.MSG.HASH, turn = h.turn, value = h.value, parts = h.parts })
      end
      h = peer:take(LB.MSG.HASH)
    end
    local a = peer:take(LB.MSG.ACTION)
    if a then peer:send({ type = LB.MSG.ACTION, turn = a.turn, kind = "move", slot = 1 }) end
    me:update(0)
  end
  check(#hashes >= 2, "a game3_battle_hash went out for each resolved turn")
  local first = hashes[1] or {}
  eq(first.turn, 1, "the first hash covers turn 1")
  check(type(first.value) == "string" and #first.value == 8, "value is 8 hex digits")
  local partsOk = type(first.parts) == "table"
  for _, key in ipairs({ "actives", "volatile", "bench", "field" }) do
    partsOk = partsOk and type(first.parts[key]) == "string" and #first.parts[key] == 8
  end
  check(partsOk, "every part is an 8 hex FNV digest")
  check(tonumber(first.parts and first.parts.rng) ~= nil, "rng is the decimal draw count")
  check(broke, "the peer answered turn 2 with a different digest")
  check(not Battle.isActive(), "the battle ended")
  eq(LB.endReason, "desync", "because of the desync")
  eq(Battle.getResult(), "draw", "as a draw")
  peer:update(0)
  local out = peer:take(LB.MSG.OUTCOME)
  eq(out and out.outcome, LB.B_OUTCOME.DREW, "game3_battle_outcome DREW went to the peer")
  eq(reported[1], "draw", "and Client.report(\"draw\") was sent once")
  eq(#reported, 1, "exactly once")
end

print("[test] 24. the peer's game3_battle_outcome is read and checked against ours")
do
  LB.log = {}
  LB.outcome = LB.B_OUTCOME.WON
  LB._peerOutcomes = { [1] = { outcome = LB.B_OUTCOME.LOST } }
  LB.compareOutcome()
  local mismatch = false
  for _, line in ipairs(LB.log) do if line:find("outcome mismatch", 1, true) then mismatch = true end end
  check(not mismatch, "WON against LOST is a mirror")
  LB._peerOutcomes = { [1] = { outcome = LB.B_OUTCOME.WON } }
  LB.compareOutcome()
  for _, line in ipairs(LB.log) do if line:find("outcome mismatch", 1, true) then mismatch = true end end
  check(mismatch, "WON against WON is logged")
end

print("[test] 25. a failed RNG draw inside a link battle raises instead of using the local stream")
do
  relayBattle(99, { charizard() }, { blastoise() })
  check(Battle.isActive(), "a link battle is up")
  check(Guard.active, "the guard is armed while it runs")
  local Rng = require("src.core.game3.rng")
  local before = Rng.getState().value
  local broken = { rng = function() return function() error("broken rng") end end }
  local ok = pcall(Engine.roll, broken, 0, 255)
  check(not ok, "Engine.roll raises rather than falling back to Rng.compat")
  eq(Rng.getState().value, before, "and the machine's own stream was not stepped")
  eq(Guard.tripped, "engine.roll", "the trip names the site")
  LB.update(0)
  check(not Battle.isActive(), "the link battle ends on the next link pump")
  eq(LB.endReason, "desync", "as a desync")
  check(not Guard.active, "and the guard is disarmed once it is over")
  local okLocal = pcall(Engine.roll, broken, 0, 255)
  check(okLocal, "outside a link battle the old fallback still answers")
end

print("[test] 26. a link opponent's held item is never rolled on this machine")
do
  local mon = blastoise()
  mon.item = 0
  relayBattle(5, { charizard() }, { mon })
  local st = Battle.getState()
  eq(st and st.foeParty[1].item, 0, "an empty item slot stays empty")
  eq(st and st.enemy and st.enemy.mon, st and st.foeParty[1], "the foe's active mon is its party row, like ours")
  Battle.abort("draw")
  local okStart = pcall(Battle.start, {
    link = true, headless = true, autoFight = false, playerParty = { charizard() },
    foe = { link = true, party = { { species = 9, level = 5, moves = { 33 }, personality = 0, ivs = {} } } },
  })
  check(not okStart, "a link foe with no item field refuses to start instead of rolling one")
  Guard.disarm()
end

print("[test] 27. running from a link battle is LINK_BATTLE_RAN and a loss")
eq(LB.outcomeCode("run"), LB.B_OUTCOME.LINK_BATTLE_RAN, "outcomeCode(run) is 128")
eq(LB.resultWord("run"), "lose", "it reports as a loss")
eq(LB.recordOutcome(LB.B_OUTCOME.LINK_BATTLE_RAN), LB.B_OUTCOME.LOST, "and records as a loss")
do
  local me, peer = relayBattle(8, { charizard() }, { blastoise() })
  peer:update(0)
  local a = peer:take(LB.MSG.ACTION)
  peer:send({ type = LB.MSG.ACTION, turn = a and a.turn or 1, kind = "run" })
  me:update(0)
  for _ = 1, 20 do if Battle.isActive() then Battle.update(0, nil) end end
  check(not Battle.isActive(), "the peer running ends the battle")
  eq(Battle.getResult(), "win", "as this machine's win")
  eq(Battle.getState().linkRan, true, "with the link-ran flag")
  local log = table.concat(Ui.log() or {}, " | ")
  check(log:find("BLUE fled!", 1, true) ~= nil, "and sText_WildFled names the peer")
end

print("[test] 28. a peer item action reads itemId")
do
  local st = { enemy = { mon = { moves = { 33 } } } }
  local act = Battle._linkEnemyAction(st, { kind = "item", itemId = 17 })
  eq(act and act.item, 17, "the item comes from itemId")
end

print("[test] 29. a double battle refuses a peer action list that is not two long")
do
  local me, peer = relayBattle(31, { charizard(), blastoise() }, { blastoise(), charizard() },
    Link.USING.DOUBLE_BATTLE)
  check(Battle.isActive() and Battle.getState().double, "a double link battle is up")
  peer:update(0)
  local a = peer:take(LB.MSG.ACTION)
  eq(a and a.kind, "list", "this machine sent its pair")
  eq(#((a and a.actions) or {}), 2, "of two")
  peer:send({ type = LB.MSG.ACTION, turn = a and a.turn or 1, kind = "list",
    actions = { { kind = "move", slot = 1 } } })
  me:update(0)
  for _ = 1, 5 do if Battle.isActive() then Battle.update(0, nil) end end
  check(not Battle.isActive(), "a one-entry list ends the battle")
  eq(LB.endReason, "desync", "as a protocol desync")
end

print("[test] 30. hashes are perspective-free: both seats of one battle digest the same")
do
  local SEED = 0xBEEF
  local function side(seat)
    Link.reset()
    if Battle.isActive() then Battle.abort("draw") end
    local mine = seat == 0 and tieMon(52, 25) or tieMon(10, 35)
    local theirs = seat == 0 and tieMon(10, 35) or tieMon(52, 25)
    session.party = { mine }
    local l0, l1 = FakeRelay.pair({ game = game, seed = SEED })
    local me, peer = l0, l1
    if seat == 1 then me, peer = l1, l0 end
    me:update(0)
    peer:update(0)
    me:update(0)
    peer:update(0)
    Link.attach(me)
    LB.headless = true
    LB.fade = false
    freshCtx()
    setVar(Link.VAR_0x8004, Link.USING.SINGLE_BATTLE)
    setVar(LB.VAR_0x8005, seat)
    Natives.special(ctx, NativesLink.SPECIAL.EnterColosseumPlayerSpot, adapters)
    peer:update(0)
    peer:send({ type = LB.MSG.SEAT, seat = 1 - seat })
    peer:send({ type = LB.MSG.SETUP, mode = Link.USING.SINGLE_BATTLE,
      name = "BLUE", trainerId = 0x2222, gender = 0, party = packed({ theirs }) })
    me:update(0)
    ctx.nativePoll()
    local digests, guard = {}, 0
    while Battle.isActive() and guard < 2000 do
      guard = guard + 1
      Battle.update(0, nil)
      peer:update(0)
      local h = peer:take(LB.MSG.HASH)
      while h do
        digests[h.turn] = h.value
        h = peer:take(LB.MSG.HASH)
      end
      local act = peer:take(LB.MSG.ACTION)
      if act then
        peer:send({ type = LB.MSG.ACTION, turn = act.turn, kind = "move", slot = 1 })
        me:update(0)
      end
    end
    return digests
  end
  local d0 = side(0)
  local d1 = side(1)
  local n, same = 0, true
  for turn, value in pairs(d0) do
    n = n + 1
    if d1[turn] ~= value then same = false end
  end
  check(n >= 2, "both seats hashed several turns")
  check(same, "and every turn's digest is identical from either seat")
end

print("[test] 31. a seat that leaves the room mid battle ends it as a draw on the relay")
do
  local me, peer = relayBattle(77, { charizard() }, { blastoise() })
  check(Battle.isActive(), "the relay battle is up")
  lastRoom:drop(1)
  for _ = 1, 5 do
    Link.update(0)
    if Battle.isActive() then Battle.update(0, nil) end
  end
  check(not Battle.isActive(), "the dropped seat ends the battle")
  eq(Battle.getResult(), "draw", "as a draw")
  eq(LB.endReason, "peer_dropped", "because the peer left")
  eq(reported[1], "draw", "and the draw is reported once")
end

print("[test] 32. a fresh battle on the same link drops the last battle's late turn messages")
do
  local me, peer = relayBattle(91, { charizard() }, { blastoise() })
  Battle.abort("draw")
  peer:send({ type = LB.MSG.OUTCOME, outcome = 1, turn = 3 })
  peer:send({ type = LB.MSG.HASH, turn = 3, value = "x" })
  peer:send({ type = LB.MSG.ACTION, turn = 1, kind = "move", slot = 1 })
  me:update(0)
  check(me:isOpen(), "the link outlives the battle")
  LB.freshBattle()
  eq(me:take(LB.MSG.OUTCOME), nil, "the late outcome is gone")
  eq(me:take(LB.MSG.HASH), nil, "the late hash is gone")
  eq(me:take(LB.MSG.ACTION), nil, "the late action is gone")
  check(not LB.peerAhead(nil, 1), "turn 1 of the next battle does not see the peer as ahead")
end

Link.reset()
Union.reset()
LB.reset()
if failed == 0 then
  print("[pass] link battle")
  os.exit(0)
end
print("[fail] link battle: " .. failed)
os.exit(1)
