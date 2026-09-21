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

local UNION_MAP = "FR_UNION_ROOM"
local CENTER_MAP = "FR_TEST_POKEMON_CENTER_1F"

local MAPS = {
  [UNION_MAP] = {
    warps = { { x = 7, y = 11, mapGroup = 0x7F, mapNum = 0x7F, destWarp = 128 } },
  },
  [CENTER_MAP] = {
    warps = { { x = 5, y = 3, destMap = UNION_MAP, destWarp = 1 } },
  },
}

local store = { flags = {}, vars = {} }
local session = {
  store = store,
  map = UNION_MAP,
  x = 7,
  y = 11,
  name = "RED",
  gender = 0,
  trainerId = 0x1234,
  party = {},
  bag = { pockets = { items = {} } },
}
local game = { data = { maps = MAPS }, session = session }

package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  isActive = function() return true end,
  _game = game,
  _mod = nil,
}

local Player = { cellX = 7, cellY = 11, facing = "down" }
package.loaded["src.core.game3.player"] = Player

local mapLoads = {}
package.loaded["src.core.game3.map"] = {
  load = function(_mod, _game, mapId, opts)
    mapLoads[#mapLoads + 1] = { map = mapId, x = opts and opts.x, y = opts and opts.y }
  end,
  current = nil,
}

local objectCalls = { added = {}, removed = {}, refreshed = 0 }
package.loaded["src.core.game3.objects"] = {
  addObject = function(localId) objectCalls.added[#objectCalls.added + 1] = localId return true end,
  removeObject = function(localId)
    objectCalls.removed[#objectCalls.removed + 1] = localId
    return true
  end,
  refreshGraphics = function() objectCalls.refreshed = objectCalls.refreshed + 1 return 0 end,
}

local ctx = { specialVars = {}, stringVars = {} }
local adapters = { log = function() end, playSe = function() end }

package.loaded["src.core.game3.scripting.space"] = {
  store = store,
  mapId = UNION_MAP,
  vm = { ctx = ctx, adapters = adapters },
}
local Space = package.loaded["src.core.game3.scripting.space"]

local Natives = require("src.core.game3.scripting.natives")
local NativesLink = require("src.core.game3.scripting.natives_link")
local Link = require("src.core.game3.link")
local Union = require("src.core.game3.link.union_room")
local Screen = require("src.ui.game3.union_room")
local Game3Link = require("src.link.Game3Link")
local Flags = require("src.core.game3.scripting.flags")
local Std = require("src.core.game3.scripting.stdscripts")

local function getVar(id)
  return tonumber(Flags.getVar(store, ctx, id)) or 0
end

local function peerHello(name, trainerId, gender)
  return {
    type = Union.MSG.HELLO,
    name = name,
    trainerId = trainerId,
    gender = gender or 0,
    activity = Union.ACTIVITY.SEARCH + Union.IN_UNION_ROOM,
  }
end

print("[test] 1. the union room specials answer to their pret index")
local EXPECTED = {
  TryBecomeLinkLeader = 0x16B,
  TryJoinLinkGroup = 0x16C,
  RunUnionRoom = 0x16D,
  InitUnionRoom = 0x182,
  BufferUnionRoomPlayerName = 0x183,
  Script_ResetUnionRoomTrade = 0x1B3,
}
for name, id in pairs(EXPECTED) do
  eq(NativesLink.SPECIAL[name], id, "NativesLink.SPECIAL." .. name)
  check(Natives.ALLOW["special:" .. id] ~= nil, name .. " is bound in Natives.ALLOW")
  eq(Std.SPECIAL_NAME_BY_ID[id], name, string.format("special 0x%X is declared by its pret name", id))
end
check(Natives.ALLOW["special:" .. 0x19B] ~= nil,
  "HasAtLeastOneBerry (0x19B) is bound (scripting/natives_queries.lua owns it)")
check(Natives.ALLOW["special:" .. 0x180] ~= nil,
  "ValidateSavedWonderCard (0x180) is bound (the mystery-gift chain owns it)")
print("[note] special 0x183 in Natives.ALLOW is whichever module loaded last; " ..
  "natives_queries sorts after natives_link")

print("[test] 2. every union room special dispatches instead of logging as unknown")
Natives.resetLog()
local logs = {}
local quiet = { log = function(m) logs[#logs + 1] = m end }
for _, id in ipairs({ 0x16D, 0x182, 0x183, 0x19B, 0x1B3 }) do
  local _, _, known = Natives.special({ specialVars = {} }, id, quiet)
  check(known, string.format("special 0x%X dispatches to a handler", id))
end
eq(#logs, 0, "nothing reached the unknown-special log")
Link.reset()

print("[test] 3. RunUnionRoom starts the session and announces to the peer")
local host, guest = Game3Link.loopback({ game = game })
host:update(0)
guest:update(0)
Link.attach(host)
Space.mapId = UNION_MAP
session.map = UNION_MAP
Flags.setVar(store, ctx, Link.VAR_RESULT, 5)
Natives.special(ctx, NativesLink.SPECIAL.RunUnionRoom, adapters)
eq(Union.state, "init", "RunUnionRoom armed the union room task")
eq(getVar(Link.VAR_RESULT), 0, "VAR_RESULT is cleared on entry")
Union.update(0)
eq(Union.state, "main", "the session reached the main loop")
guest:update(0)
local heard = guest:take(Union.MSG.HELLO)
check(heard ~= nil, "the peer heard this player enter the union room")
eq(heard and heard.name, "RED", "with the player's name")

print("[test] 4. the player list fills from the transport and spawns an avatar")
guest:send(peerHello("BLUE", 0x2222, 0))
host:update(0)
Union.update(0)
eq(Union.playerCount(), 1, "one other player is in the room")
local listed = Union.list()[1]
eq(listed and listed.name, "BLUE", "the list names the peer")
eq(listed and listed.slot, 1, "in the first leader slot")
eq(objectCalls.added[1], Union.LOCAL_IDS[1], "the slot 1 union room object was spawned")
eq(Flags.getFlag(store, ctx, Union.FLAG_HIDE_PLAYER_1), false,
  "FLAG_HIDE_UNION_ROOM_PLAYER_1 was cleared")
eq(getVar(Union.VAR_OBJ_GFX_ID_0), Union.graphicsIdFor(0, 0x2222),
  "VAR_OBJ_GFX_ID_0 holds the trainer-class graphics id")

print("[test] 5. BufferUnionRoomPlayerName hands the nurse the name once")
local _, first = NativesLink.HANDLERS[NativesLink.SPECIAL.BufferUnionRoomPlayerName](ctx, adapters)
eq(first, 1, "the first call reports TRUE")
eq(ctx.stringVars[1], "BLUE", "and buffers the name into STR_VAR_1")
local _, second = NativesLink.HANDLERS[NativesLink.SPECIAL.BufferUnionRoomPlayerName](ctx, adapters)
eq(second, 0, "the second call reports FALSE")

print("[test] 6. talking to a player opens the activity chooser")
Flags.setVar(store, ctx, Link.VAR_RESULT, 1)
Union.update(0)
eq(Union.partnerId, 1, "the interaction picked the player in slot 1")
Union.update(0)
check(Screen.isOpen(), "the union room screen opened")
eq(Screen.mode, "activity", "in activity-chooser mode")
eq(#Screen.items, 4, "with the four pret entries")
eq(Screen.labelFor(Screen.items[1]), "GREETINGS", "GREETINGS first")
eq(Screen.labelFor(Screen.items[4]), "EXIT", "EXIT last")

print("[test] 7. BATTLE needs two mons at or below level 30")
session.party = { { species = 1, level = 42 } }
Screen.cursor = 2
Screen.confirm()
check(not Screen.isOpen(), "the chooser closed")
eq(Union.activity, nil, "an over-level party cannot start a union room battle")

session.party = { { species = 1, level = 12 }, { species = 4, level = 9 } }
Union.state = "do_something_prompt"
Union.partnerId = 1
Union.update(0)
Screen.cursor = 2
Screen.confirm()
eq(Union.activity, Union.ACTIVITY.BATTLE_SINGLE + Union.IN_UNION_ROOM,
  "the battle request carries ACTIVITY_BATTLE_SINGLE | IN_UNION_ROOM")
eq(Union.state, "send_activity_request", "and the request went out")
guest:update(0)
local request = guest:take(Union.MSG.REQUEST)
check(request ~= nil, "the peer received the activity request")
eq(request and request.activity, Union.ACTIVITY.BATTLE_SINGLE + Union.IN_UNION_ROOM,
  "with the same activity id")

print("[test] 8. a partner that never answers frees the room again")
eq(Union.state, "send_activity_request", "the request is still outstanding")
Union.update(Union.RESPONSE_SECONDS + 0.1)
eq(Union.lastResult, "busy", "the partner is reported busy")
Union.update(0)
eq(Union.state, "main", "and the union room goes back to its main loop")
eq(Union.activity, nil, "with no pending activity")

print("[test] 9. EXIT leaves the chooser without contacting anybody")
Union.state = "do_something_prompt"
Union.partnerId = 1
Union.update(0)
Screen.cursor = 4
Screen.confirm()
eq(Union.activity, nil, "EXIT clears the pending activity")
eq(Union.state, "main", "and returns to the union room main loop")

print("[test] 10. stepping on the union room pad returns the dynamic warp, not a header map")
local pad = MAPS[UNION_MAP].warps[1]
eq(tonumber(pad.mapNum), 0x7F, "the pad at (7,11) is MAP_DYNAMIC in the map header")
session.dynamicWarp = { map = CENTER_MAP, warpId = 0, x = 5, y = 3 }
local destMap, destX, destY = Link.resolveDest(session.dynamicWarp)
eq(destMap, CENTER_MAP, "it resolves to the Pokemon Center the player came from")
eq(destX, 5, "at the counter door x")
eq(destY, 3, "at the counter door y")

print("[test] 11. leaving the union room map ends the session")
objectCalls.removed = {}
Space.mapId = CENTER_MAP
session.map = CENTER_MAP
local alive = Union.update(0)
eq(alive, false, "the union room task stopped")
eq(Union.state, "off", "the session is closed")
eq(Union.playerCount(), 0, "the player list is empty")
eq(objectCalls.removed[1], Union.LOCAL_IDS[1], "the spawned avatar was removed")
guest:update(0)
check(guest:take(Union.MSG.BYE) ~= nil, "the peer was told this player left")

print("[test] 12. InitUnionRoom scans from the Pokemon Center without spawning avatars")
objectCalls.added = {}
Natives.special(ctx, NativesLink.SPECIAL.InitUnionRoom, adapters)
eq(Union.state, "search", "the Pokemon Center ON_RESUME scan is running")
guest:send(peerHello("GREEN", 0x3333, 1))
host:update(0)
Union.update(0)
eq(Union.playerCount(), 1, "the scan found a union room player")
eq(#objectCalls.added, 0, "and spawned nothing on the Pokemon Center map")
local _, greeted = NativesLink.HANDLERS[NativesLink.SPECIAL.BufferUnionRoomPlayerName](ctx, adapters)
eq(greeted, 1, "the nurse can greet the player it found")
eq(ctx.stringVars[1], "GREEN", "by name")

print("[test] 13. the link group flows answer LINKUP through VAR_RESULT")
Link.reset()
Space.mapId = UNION_MAP
session.map = UNION_MAP
local host2, guest2 = Game3Link.loopback({ game = game })
host2:update(0)
guest2:update(0)
Link.attach(host2)
Natives.special(ctx, NativesLink.SPECIAL.RunUnionRoom, adapters)
Union.update(0)
guest2:send(peerHello("BLUE", 0x2222, 0))
host2:update(0)
Union.update(0)

Flags.setVar(store, ctx, Link.VAR_0x8004, Union.LINK_GROUP.SINGLE_BATTLE)
local yielded = Natives.special(ctx, NativesLink.SPECIAL.TryBecomeLinkLeader, adapters)
check(yielded, "the script yields while the group list is up")
eq(getVar(Link.VAR_RESULT), Link.LINKUP.ONGOING, "VAR_RESULT is LINKUP_ONGOING while it runs")
eq(Screen.mode, "leader", "the group list opened in leader mode")
Screen.confirm()
eq(getVar(Link.VAR_RESULT), Link.LINKUP.SUCCESS, "confirming reports LINKUP_SUCCESS")
check(ctx.nativePoll and ctx.nativePoll() == true, "and the script resumes")

Flags.setVar(store, ctx, Link.VAR_0x8004, Union.LINK_GROUP.TRADE)
Natives.special(ctx, NativesLink.SPECIAL.TryJoinLinkGroup, adapters)
eq(Screen.mode, "group", "joining opens the same list in group mode")
Screen.cancel()
eq(getVar(Link.VAR_RESULT), Link.LINKUP.FAILED, "backing out reports LINKUP_FAILED")

print("[test] 14. Script_ResetUnionRoomTrade clears the registered trade")
local trade = Union.trade()
trade.state = 1
trade.playerSpecies = 25
trade.playerLevel = 30
Natives.special(ctx, NativesLink.SPECIAL.Script_ResetUnionRoomTrade, adapters)
eq(Union.trade().state, 0, "the trade state is URTRADE_STATE_NONE")
eq(Union.trade().playerSpecies, 0, "the registered species is SPECIES_NONE")
eq(Union.trade().playerLevel, 0, "and the level is cleared")

print("[test] 15. the imported Union Room really is one dynamic warp at (7,11)")
local Cache = require("tests.game3_cache")
local root = Cache.mount("meta.json")
if not root then
  print("[skip] union room map check: " .. tostring(Cache.reason))
else
  local Dataset = require("src.core.game3.dataset")
  local realMaps = Dataset.buildMaps()
  local def = realMaps[UNION_MAP]
  local control = realMaps["FR_VIRIDIAN_CITY_POKEMON_CENTER_2F"]
  if not (control and control.warps and #control.warps > 0) then
    print("[skip] union room map check: the mounted cache at " .. tostring(root) ..
      " carries no map warps")
    def = nil
  end
  check(realMaps[UNION_MAP] ~= nil, "FR_UNION_ROOM is in the imported cache")
  if def then
    eq(#(def.warps or {}), 1, "it has exactly one warp")
    local w = (def.warps or {})[1]
    eq(tonumber(w and w.x), 7, "at x 7")
    eq(tonumber(w and w.y), 11, "at y 11")
    eq(tonumber(w and w.mapNum), 0x7F, "and it is MAP_DYNAMIC")
  end
end

print("[test] an incoming activity request is answered, never parked")
Link.reset()
Union.reset()
local reqHost, reqGuest = Game3Link.loopback({ game = game })
reqHost:update(0)
reqGuest:update(0)
Link.attach(reqHost)
Space.mapId = UNION_MAP
session.map = UNION_MAP
Natives.special(ctx, NativesLink.SPECIAL.RunUnionRoom, adapters)
Union.update(0)
reqGuest:update(0)
while reqGuest:take(Union.MSG.HELLO) do end
reqGuest:send({ type = Union.MSG.REQUEST, name = "BLUE",
  activity = Union.ACTIVITY.CHAT + Union.IN_UNION_ROOM })
reqHost:update(0)
Union.update(1 / 60)
eq(Union.activity, Union.ACTIVITY.CHAT + Union.IN_UNION_ROOM,
  "the request lands in UR_STATE_RECV_ACTIVITY_REQUEST with the activity asked for")
eq(Union._requestName, "BLUE", "and the name of the trainer who asked")
-- pokefirered/src/union_room_message.c:86 gText_UR_PlayerContactedYouForXAccept
local prompt = Union.requestPrompt()
check(prompt:find("BLUE", 1, true) ~= nil, "the prompt names the trainer who contacted you")
check(prompt:find("CHAT", 1, true) ~= nil, "and the activity they asked for")
Union.update(1 / 60)
reqHost:update(0)
reqGuest:update(0)
local answer = reqGuest:take(Union.MSG.RESPONSE)
check(answer ~= nil, "the peer gets a RESPONSE instead of timing out on a parked room")
check(Union.state ~= "player_contacted_you", "and the room leaves player_contacted_you")

print("[test] the chooser's CHAT and GREETINGS start real activities")
local Chat = require("src.core.game3.link.chat")
Union.state = "main"
Union.activity = nil
Union.chooseActivity(3)
eq(Union.state, "send_activity_request", "CHAT asks the partner first")
reqGuest:update(0)
reqGuest:take(Union.MSG.REQUEST)
reqGuest:send({ type = Union.MSG.RESPONSE, accept = true })
reqHost:update(0)
Union.update(1 / 60)
eq(Union.state, "in_activity", "an accepted CHAT enters the chat activity")
check(Chat.isActive(), "and the chat session is live")
Chat.say("HI")
reqGuest:update(0)
local said = reqGuest:take(Chat.MSG.LINE)
eq(said and said.text, "HI", "a line the player writes goes out on the wire")
reqGuest:send({ type = Chat.MSG.LINE, name = "BLUE", text = "HELLO" })
reqHost:update(0)
Chat.update(1 / 60)
eq(#Chat.lines, 2, "and the peer's line lands in the log")
eq(Chat.lines[2] and Chat.lines[2].text, "HELLO", "with the peer's words")
Chat.stop("left")
Union.update(1 / 60)
eq(Union.state, "main", "leaving the chat puts the room back in its main loop")

Union.state = "main"
Union.activity = nil
Union.chooseActivity(1)
eq(Union.state, "send_activity_request", "GREETINGS asks the partner first")
reqGuest:update(0)
reqGuest:take(Union.MSG.REQUEST)
reqGuest:send({ type = Union.MSG.RESPONSE, accept = true })
reqHost:update(0)
Union.update(1 / 60)
-- pokefirered/src/union_room.c:1954 CB2_ShowCard
eq(Union.state, "in_activity", "an accepted GREETINGS shows a trainer card")
eq(Union.lastResult, "card_shown", "built from CreateTrainerCardInBuffer")
local cardOut = nil
reqGuest:update(0)
local seen = reqGuest:take(Link.MSG.CARD)
while seen do
  cardOut = seen
  seen = reqGuest:take(Link.MSG.CARD)
end
check(cardOut ~= nil, "and this machine's own card went out to the peer")
eq(cardOut and cardOut.card and cardOut.card.name, session.name, "carrying the player's name")

print("[test] the link group at the counter lists the machine on the cable")
Link.reset()
Union.reset()
local grpHost, grpGuest = Game3Link.loopback({ game = game })
grpHost:update(0)
grpGuest:update(0)
Link.attach(grpHost)
-- pokefirered/src/union_room.c:403 LL_STATE_INIT
local listed = Union.groupList()
eq(#listed, 1, "the peer on the cable is a group member before any union room hello")
eq(listed[1] and listed[1].name, session.name, "named by the handshake hello")
Flags.setVar(store, ctx, Link.VAR_0x8004, Union.LINK_GROUP.TRADE)
ctx.nativePoll = nil
local upYield = Natives.special(ctx, NativesLink.SPECIAL.TryBecomeLinkLeader, adapters)
check(upYield, "TryBecomeLinkLeader parks the script on the group list")
grpGuest:update(0)
local advertised = grpGuest:take(Union.MSG.HELLO)
check(advertised ~= nil, "and the leader advertises itself to the other machine")
eq(#Screen.players, 1, "the list the player sees has the other machine in it")
check(Screen.confirm(), "so the leader can start the group")
eq(getVar(Link.VAR_RESULT), Link.LINKUP.SUCCESS, "and the linkup reports LINKUP_SUCCESS")

print("[test] the wireless adapter answer stays FALSE with a link up")
-- pokefirered/data/scripts/cable_club.inc:849 FALSE is what sends the direct corner
local _, adapterAnswer = Natives.special(ctx, NativesLink.SPECIAL.IsWirelessAdapterConnected,
  adapters)
eq(adapterAnswer, 0, "IsWirelessAdapterConnected is FALSE even with a live session")

Link.reset()
Union.reset()
if failed == 0 then
  print("[pass] link union room")
  os.exit(0)
end
print("[fail] link union room: " .. failed)
os.exit(1)
