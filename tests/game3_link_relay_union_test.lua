#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.fixture_data.game3_items").install()

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

local FakeRelay = require("tests.g3link_fake_relay")

local Plaza = require("src.core.game3.link.union_plaza_map")
local UNION_MAP = Plaza.MAP_ID
local CENTER_MAP = "FR_TEST_POKEMON_CENTER_2F"
local MAPS = {
  [UNION_MAP] = { warps = { { x = 12, y = 24, mapGroup = 0x7F, mapNum = 0x7F, destWarp = 128 } } },
  [CENTER_MAP] = { warps = { { x = 9, y = 1, destMap = "FR_TRADE_CENTER", destWarp = 1 } } },
  FR_TRADE_CENTER = { warps = { { x = 5, y = 8, mapGroup = 0x7F, mapNum = 0x7F, destWarp = 128 } } },
}

local store = { flags = {}, vars = {} }
local session = {
  store = store, map = UNION_MAP, x = 12, y = 24, name = "RED", gender = 0, trainerId = 0x1234,
  party = { { species = 1, level = 12 }, { species = 4, level = 9 } },
  bag = { pockets = { items = {} } },
}
local input = { pressed = {} }
function input:wasPressed(k) return self.pressed[k] == true end
local game = { data = { maps = MAPS }, session = session, input = input,
  save = { player = { name = "RED" }, options = {} } }

package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  isActive = function() return true end,
  _game = game,
}
local Player = { cellX = 12, cellY = 23, facing = "down" }
package.loaded["src.core.game3.player"] = Player
local mapLoads = {}
package.loaded["src.core.game3.map"] = {
  load = function(_mod, _game, mapId, opts)
    mapLoads[#mapLoads + 1] = { map = mapId, x = opts and opts.x, y = opts and opts.y }
  end,
}
local objectCalls = { added = {}, removed = {} }
local liveObjects = {}
package.loaded["src.core.game3.objects"] = {
  addObject = function(id)
    objectCalls.added[#objectCalls.added + 1] = id
    liveObjects[id] = { localId = id, visible = true, raiseY = 0 }
    return true
  end,
  removeObject = function(id)
    objectCalls.removed[#objectCalls.removed + 1] = id
    liveObjects[id] = nil
    return true
  end,
  find = function(id) return liveObjects[id] end,
  refreshGraphics = function() return 0 end,
}
local VirtualObjects = require("src.core.game3.virtual_objects")

local romBundle = require("tests.game3_cache").bundle()
if not romBundle then
  package.loaded["src.core.game3.rom_text"] = {
    plain = function(key) return key end, box = function(key) return key end,
    ascii = function(key) return key end, has = function() return true end,
    ir = function(key) return { { t = "text", s = key } } end,
    key = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
    at = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
    count = function() return 0 end, list = function() return {} end,
    lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
  }
end
local RomText = require("src.core.game3.rom_text")

local ctx = { specialVars = {}, stringVars = {} }
local adapters = { log = function() end, playSe = function() end }
package.loaded["src.core.game3.scripting.space"] = {
  store = store, mapId = UNION_MAP, vm = { ctx = ctx, adapters = adapters },
  ensureBundle = function() return romBundle end,
}
local Space = package.loaded["src.core.game3.scripting.space"]

local LIVE = { engine = 3, engineVersion = "1.0.0", fingerprint = "f00dcafe", kind = "vanilla",
  version = "firered" }
package.loaded["src.online.ArenaData"] = {
  liveProfile3 = function(_, rulesetId)
    local p = {}
    for k, v in pairs(LIVE) do p[k] = v end
    p.rulesetId = rulesetId
    return p
  end,
}
local Client = FakeRelay.client({ state = "online", id = "0000beef" })
Client._profiles = { LIVE }
package.loaded["src.online.Client"] = Client

local mgCalls = {}
package.loaded["src.core.game3.minigames.common"] = {
  GROUP_GAME = { [4] = "jump", [5] = "crush", [6] = "pick" },
  partySlot = 1,
  arm = function(c, spec)
    mgCalls[#mgCalls + 1] = { ctx = c, spec = spec }
    return true
  end,
}

local Natives = require("src.core.game3.scripting.natives")
local NativesLink = require("src.core.game3.scripting.natives_link")
local Link = require("src.core.game3.link")
local Union = require("src.core.game3.link.union_room")
local Screen = require("src.ui.game3.union_room")
local Game3Link = require("src.link.Game3Link")
local Flags = require("src.core.game3.scripting.flags")
local Message = require("src.ui.game3.message")
local Chat = require("src.core.game3.link.chat")

Union._avatars = FakeRelay.avatars()
local Choice = require("src.ui.game3.choice")

local function getVar(id) return tonumber(Flags.getVar(store, ctx, id)) or 0 end
local function tickMsg() for _ = 1, 400 do Message.tick() end end
local function run(n)
  for _ = 1, n or 1 do
    Message.tick()
    Link.update(1 / 60)
  end
end
local function settle(n)
  for _ = 1, n or 2000 do
    if Message.isOpen() and not Message.isWaiting() then Message.skipReveal() end
    Message.tick()
    Union.update(1 / 60)
    if Choice.isOpen() or Screen.isOpen() then return true end
    if Message.isOpen() and Message.isWaiting()
        and (not Message._stay or (Message._page or 1) < #(Message._pages or {})) then
      Message.advance()
    end
  end
  return false
end
local function answer(yes)
  Choice.cursor = yes and 1 or 2
  Choice.confirm()
end
local function drain()
  for _ = 1, 400 do
    if Message.isOpen() and not Message.isWaiting() then Message.skipReveal() end
    if Message.isOpen() and Message.isWaiting() and not Choice.isOpen() then Message.advance() end
    run(1)
    if not Message.isOpen() and not Union.flow then run(1) end
  end
end
local function page() return Message.isOpen() and Message.currentPage() or nil end
local function shows(text)
  local p = page()
  return p ~= nil and p ~= "" and text:find(p, 1, true) == 1
end
local function ascii(key) return RomText.ascii(key) end
local function member(id, slot, name, trainerId, gender)
  return { id = id, name = name, slot = slot, online = true, status = "idle",
    avatar = { name = name, trainerId = trainerId, gender = gender, version = "firered" } }
end

print("[test] 1. RunUnionRoom joins the union plaza when the adapter is connected")
Link.reset()
Space.mapId = UNION_MAP
session.map = UNION_MAP
Natives.special(ctx, NativesLink.SPECIAL.RunUnionRoom, adapters)
eq(Union.relay, true, "the union room runs over the relay")
local join = Client.last("joinPlaza")
eq(join and join[1], "union", "joinPlaza union")
eq(join and join[2] and join[2].rulesetId, "g3_link", "with the live g3_link profile")
eq(join and join[3] and join[3].name, "RED", "and the avatar")
eq(join and join[4], 40, "announcing the 40-player plaza cap")
eq(Union.capacity(), Plaza.CAP, "the relay room holds 40 players")
eq(Client.status, "idle", "presence status goes idle in the Union Room")
check(Union.isUnionMap(UNION_MAP) and Union.isUnionMap("FR_UNION_ROOM"), "both rooms are Union Room maps")
check(not Union.isUnionMap(CENTER_MAP), "the Pokemon Center is not")

print("[test] 2. every other trainer stands on the cell of their relay slot, self excluded")
Client._plaza = { kind = "union", instance = 1, cap = 40, rev = 1, you = 2, members = {
  member("aaaa0002", 1, "GREEN", 3, 1),
  member("0000beef", 2, "RED", 0x1234, 0),
  member("aaaa0001", 5, "BLUE", 0x2222, 0),
} }
run(1)
eq(Union.playerCount(), 2, "two other trainers")
eq(Union.players[1] and Union.players[1].name, "GREEN", "relay slot 1 is GREEN")
eq(Union.players[5] and Union.players[5].name, "BLUE", "relay slot 5 keeps its number (slot = cell)")
eq(Union.players[2], nil, "our own slot is never drawn")
eq(Union.vobj(2), nil, "and has no avatar")
eq(Union.players[1] and Union.players[1].id, "aaaa0002", "the slot remembers the relay id")
eq(#objectCalls.added, 0, "no cart map object is used")
local g1 = Union.vobj(1)
local cx1, cy1, cf1 = Plaza.cellFor(1)
check(g1 and g1.visible, "GREEN is a virtual object")
eq(g1 and g1.x, cx1, "on slot 1's cell x")
eq(g1 and g1.y, cy1, "on slot 1's cell y")
eq(g1 and g1.dir, Union.FACE_DIR[cf1], "facing the cell's default")
eq(Union.vobjId(5), Union.VOBJ_BASE + 5, "virtual object ids are VOBJ_BASE + slot")
local b5 = Union.vobj(5)
local cx5, cy5 = Plaza.cellFor(5)
eq(b5 and b5.x, cx5, "BLUE on slot 5's cell x")
eq(b5 and b5.y, cy5, "BLUE on slot 5's cell y")
local rec1 = VirtualObjects.get(Union.vobjId(1))
eq(rec1 and rec1.graphicsId, Union.graphicsIdFor(1, 3), "with the class graphics id")
check(rec1 and rec1.y2 < 0, "flying in")
run(20)
eq(VirtualObjects.get(Union.vobjId(1)).y2, 0, "and landed")
eq(VirtualObjects.count(), 2, "two avatars in the virtual object pool")

print("[test] 3. the plaza rebuilds only on a new (instance, rev)")
local builds = Union.plazaBuilds
run(30)
eq(Union.plazaBuilds, builds, "no rebuild while the rev stands still")
Client._plaza.members[3].status = "battling"
run(1)
eq(Union.players[5].activity, Union.ACTIVITY.NONE + Union.IN_UNION_ROOM, "an unannounced change is not applied")
Client._plaza.rev = 2
run(1)
eq(Union.plazaBuilds, builds + 1, "a new rev rebuilds once")
eq(Union.players[5].activity, Union.ACTIVITY.BATTLE_SINGLE + Union.IN_UNION_ROOM, "BLUE is battling")
eq(b5.x, cx5, "a busy player stays on its cell")
eq(b5.dir, Union.DIR.EAST, "facing its activity")
Client._plaza.members[3].status = "idle"
Client._plaza.instance, Client._plaza.rev = 2, 2
run(1)
eq(Union.plazaBuilds, builds + 2, "a new instance with the same rev rebuilds too")
eq(b5.dir, Union.FACE_DIR[select(3, Plaza.cellFor(5))], "BLUE is idle again")
local blueRow = table.remove(Client._plaza.members, 3)
Client._plaza.rev = 3
run(1)
eq(Union.players[5], nil, "a leaver is gone on the delta that drops it")
eq(b5.anim, "out", "and flies out")
run(Union.FLY_HEIGHT / Union.FLY_STEP)
eq(VirtualObjects.get(Union.vobjId(5)), nil, "then leaves the pool")
eq(VirtualObjects.count(), 1, "GREEN stays")
table.insert(Client._plaza.members, blueRow)
Client._plaza.rev = 4
run(1)
check(Union.vobjVisible(5), "a rejoin on the same slot comes back to the same cell")
run(20)

print("[test] 3a. a short relay blip keeps the room, a long drop empties it")
local realClock = Union.clock
local fakeNow = 1000
Union.clock = function() return fakeNow end
Client._state = "reconnecting"
run(1)
fakeNow = fakeNow + Union.GONE_GRACE_SECONDS / 2
run(1)
eq(Union.playerCount(), 2, "a blip keeps everyone")
Client._state = "online"
run(1)
eq(Union.playerCount(), 2, "and the resumed plaza (same rev) is applied again")
Client._state = "reconnecting"
run(1)
fakeNow = fakeNow + Union.GONE_GRACE_SECONDS + 1
run(1)
eq(Union.playerCount(), 0, "a drop past the grace empties the room")
Client._state = "online"
run(1)
eq(Union.playerCount(), 2, "the same rev after the drop still rebuilds")
Union.clock = realClock
run(20)

print("[test] 3b. a full 40-player plaza: 39 avatars, no per-frame allocation")
local full = {}
for slot = 1, Plaza.CAP do
  if slot == 2 then
    full[#full + 1] = member("0000beef", 2, "RED", 0x1234, 0)
  else
    full[#full + 1] = member(string.format("bbbb%04x", slot), slot, "P" .. slot, slot * 7, slot % 2)
  end
end
full[1] = member("aaaa0002", 1, "GREEN", 3, 1)
Client._plaza = { kind = "union", instance = 3, cap = 40, rev = 10, you = 2, members = full }
run(1)
eq(Union.playerCount(), Plaza.CAP - 1, "39 other trainers")
run(25)
eq(VirtualObjects.count(), Plaza.CAP - 1, "39 avatars in the pool")
local cellsOk, seen = true, {}
for slot = 1, Plaza.CAP do
  if slot ~= 2 then
    local v = Union.vobj(slot)
    local x, y = Plaza.cellFor(slot)
    if not (v and v.visible and v.x == x and v.y == y) or seen[y * 64 + x] then cellsOk = false end
    seen[y * 64 + x] = true
  end
end
check(cellsOk, "every avatar on its own slot cell")
builds = Union.plazaBuilds
local okJit, jit = pcall(require, "jit")
if okJit and jit and jit.off then jit.off() jit.flush() end
for _ = 1, 10 do Union.relayTick(1 / 60) end
collectgarbage("collect")
collectgarbage("stop")
local kb = collectgarbage("count")
for _ = 1, 600 do Union.relayTick(1 / 60) end
local grown = (collectgarbage("count") - kb) * 1024
collectgarbage("restart")
if okJit and jit and jit.on then jit.on() end
eq(Union.plazaBuilds, builds, "600 frames on one rev never rebuild")
check(grown == 0, string.format("and allocate nothing (%d bytes)", grown))
Client._plaza.members[40].status = "chatting"
Client._plaza.rev = 11
run(1)
eq(Union.plazaBuilds, builds + 1, "one status change is one rebuild")
eq(Union.vobj(40).dir, Union.DIR.SOUTH, "a chatter faces south on its cell")
local x40, y40 = Plaza.cellFor(40)
Player.cellX, Player.cellY, Player.facing = x40 - 1, y40, "right"
input.pressed = { a = true }
run(1)
input.pressed = {}
eq(Union.state, "recv_join_chat_request", "slot 40's chatter is talkable from the west")
check(settle(), "the join prompt asks YES/NO")
answer(false)
drain()
eq(Union.state, "main", "back to the main loop")
Client._plaza = { kind = "union", instance = 1, cap = 40, rev = 20, you = 2, members = {
  member("aaaa0002", 1, "GREEN", 3, 1),
  member("0000beef", 2, "RED", 0x1234, 0),
} }
run(25)
eq(Union.playerCount(), 1, "back to GREEN alone")

print("[test] 3c. anyone chatting can be joined, from any side; idle trainers from any side")
local pink = member("aaaa0003", 3, "PINK", 5, 1)
pink.status = "chatting"
pink.group = { leader = "aaaa0003", members = { "aaaa0003", "aaaa0004" }, activity = "chat" }
local yellow = member("aaaa0004", 4, "YELLOW", 6, 0)
yellow.status = "chatting"
yellow.group = pink.group
table.insert(Client._plaza.members, pink)
table.insert(Client._plaza.members, yellow)
Client._plaza.rev = 21
run(21)
eq(Union.playerCount(), 3, "no grouping: the chat member has its own slot")
eq(Union.players[4] and Union.players[4].name, "YELLOW", "YELLOW on slot 4")
eq(Union.players[3].partners, nil, "no partner lists")
local vy = Union.vobj(4)
local x4, y4 = Plaza.cellFor(4)
eq(vy and vy.x, x4, "YELLOW stands on slot 4's cell")
eq(vy and vy.dir, Union.DIR.SOUTH, "facing its chat")
Union.toMain()
Message.reset()
Player.cellX, Player.cellY, Player.facing = x4, y4 + 1, "up"
input.pressed = { a = true }
run(1)
input.pressed = {}
eq(Union.state, "recv_join_chat_request", "A in front of a chat member who is not the host")
eq(vy.dir, Union.DIR.SOUTH, "YELLOW turns to face the player")
check(settle(), "the join prompt asks YES/NO")
if romBundle then
  check(shows(RomText.ascii("sText_JoinChatMale")), "gTexts_UR_JoinChat for a male chatter")
end
answer(true)
local jinv = Client.last("invite")
eq(jinv and jinv[1], "aaaa0004", "joining asks YELLOW directly")
eq(jinv and jinv[2], "chat", "for the chat")
eq(jinv and jinv[3] and jinv[3].join, true, "as a join")
eq(Union.state, "send_activity_request", "waiting for the relay")
local jh = Client.handles[#Client.handles]
jh.state, jh.why = "closed", "busy"
run(1)
eq(Union.state, "print_and_exit", "a refused join")
if romBundle then
  check(shows(RomText.ascii(RomText.key("gTexts_UR_ChatDeclined", 0))), "reads gTexts_UR_ChatDeclined")
end
drain()
eq(Union.state, "main", "back to the main loop")
eq(vy.dir, Union.DIR.SOUTH, "YELLOW faces its chat again")
local x3, y3 = Plaza.cellFor(3)
pink.group.members = { "aaaa0003", "aaaa0004", "c1", "c2", "c3" }
Client._plaza.rev = 22
run(1)
Player.cellX, Player.cellY, Player.facing = x3 + 1, y3, "left"
input.pressed = { a = true }
run(1)
input.pressed = {}
eq(Union.state, "print_and_exit", "a full chat (5 seats) only gets a reaction")
eq(Union.vobj(3).dir, Union.DIR.EAST, "PINK turns east to the player")
drain()
local xg, yg = Plaza.cellFor(1)
for _, side in ipairs({ { 0, 1, "up" }, { 0, -1, "down" }, { -1, 0, "right" }, { 1, 0, "left" } }) do
  Union.toMain()
  Message.reset()
  Player.cellX, Player.cellY, Player.facing = xg + side[1], yg + side[2], side[3]
  input.pressed = { a = true }
  run(1)
  input.pressed = {}
  eq(Union.state, "do_something_prompt", "idle GREEN is talkable facing " .. side[3])
  Union.toMain()
  Union.flow = nil
  Message.reset()
end
eq(Union.vobj(1).dir, Union.FACE_DIR[cf1], "and turns back to its cell facing")
Player.cellX, Player.cellY, Player.facing = 12, 23, "down"

print("[test] 3d. a relay that refuses this build shows the update prompt once")
Union.toMain()
Message.reset()
Client._state = "error"
Client.upgradeRequired = function() return { type = "upgrade_required", text = "This build is too old for online play. Please update." } end
run(1)
eq(Union.state, "print_and_exit", "upgrade_required prints")
tickMsg()
check(Message.isOpen() and tostring(Message.currentPage()):find("too old", 1, true) ~= nil, "the relay's update text")
drain()
eq(Union.state, "main", "back to the main loop")
run(5)
eq(Union.state, "main", "and it is shown only once")
Client.upgradeRequired = nil
Client._state = "online"
run(25)
eq(Union.playerCount(), 3, "the room comes back when the relay does")
Union.toMain()
Message.reset()

print("[test] 4. talking to a trainer: HiDoSomething, the invite menu, the cart's reject")
run(1)
local held = ctx.stateWait
eq(held, Union.scriptWaitTask, "the Union Room holds the next waitstate")
ctx.stateWait = nil
Flags.setVar(store, ctx, 0x800D, 1)
eq(held(), false, "setvar VAR_RESULT, 1 then waitstate: the script waits")
Flags.setVar(store, ctx, 0x800D, 0)
run(1)
eq(Union.state, "main", "a VAR_RESULT that is not the attendant talks to no slot")
eq(Union.flow, nil, "and opens no flow")
eq(held(), true, "the waitstate is released")
Player.cellX, Player.cellY, Player.facing = xg, yg + 1, "up"
input.pressed = { a = true }
run(1)
input.pressed = {}
eq(Union.state, "do_something_prompt", "talking to GREEN")
Player.cellX, Player.cellY, Player.facing = 12, 23, "down"
check(settle(), "the activity menu opens")
eq(Screen.mode, "activity", "GREETINGS / BATTLE / CHAT / EXIT")
if romBundle then
  check(shows(RomText.ascii("sText_HiDoSomethingFemale")), "gTexts_UR_HiDoSomething for a stranger")
end
Screen.cursor = 2
Screen.confirm()
local inv = Client.last("invite")
eq(inv and inv[1], "aaaa0002", "invites the member by relay id")
eq(inv and inv[2], "battle_single", "BATTLE is battle_single")
eq(inv and inv[3] and inv[3].ruleset, "g3_single", "with the g3_single ruleset")
eq(inv and inv[4] and inv[4].rulesetId, "g3_single", "and a g3_single profile")
eq(Union.state, "send_activity_request", "waiting for the answer")
if romBundle then
  check(shows(RomText.ascii(RomText.key("gTexts_UR_WaitOrShowCard", 1, 0))), "the partner's wait line")
end
local h = Client.handles[#Client.handles]
Union.update(5)
eq(Union.state, "send_activity_request", "no local timeout: the relay decides")
h.state, h.why = "closed", "declined"
run(1)
eq(Union.lastResult, "declined", "declined")
check(shows(RomText.ascii(RomText.key("gTexts_UR_BattleDeclined", 1))),
  "the partner's gendered battle refusal (GetURoomActivityRejectMsg)")
drain()
eq(Union.state, "main", "back to the main loop")

Union.partnerId = 1
Union.chooseActivity(3)
h = Client.handles[#Client.handles]
h.state, h.why = "closed", "busy"
run(1)
check(shows(ascii("gText_UR_TrainerAppearsBusy")), "busy reads The TRAINER appears to be busy")
drain()

Union.partnerId = 1
Union.chooseActivity(3)
h = Client.handles[#Client.handles]
check(h ~= nil and h.state ~= "closed", "an open invite")
Client._state = "reconnecting"
run(30)
eq(Union.state, "send_activity_request", "a reconnecting relay keeps the invite wait")
Client._state = "error"
run(1)
eq(Union.lastResult, "busy", "the relay dropping for good ends the invite")
check(shows(ascii("gText_UR_TrainerBattleBusy")), "with gText_UR_TrainerBattleBusy (!gReceivedRemoteLinkPlayers)")
check(not Message._stay, "the stay-open wait line is gone")
drain()
eq(Union.state, "main", "back to the main loop")
eq(Union.invite, nil, "the dead handle is dropped")
Client._state = "online"
run(1)

Union.partnerId = 1
Union._partner = Union.players[1]
Union.chooseActivity(4)
eq(Union.state, "print_and_exit", "EXIT")
run(1)
if romBundle then
  check(shows(RomText.ascii(RomText.key("gTexts_UR_IfYouWantToDoSomething", 1))),
    "EXIT reads gTexts_UR_IfYouWantToDoSomething")
end
drain()
eq(Union.state, "main", "back to main")

print("[test] 5. an accepted CHAT starts the chat on the room session")
Union.partnerId = 1
Union.chooseActivity(3)
eq(Client.last("invite")[2], "chat", "CHAT is chat")
h = Client.handles[#Client.handles]
local room = FakeRelay.room({ seats = 2, intent = "chat", names = { "RED", "GREEN" } })
local rs0 = room:session(0)
h.state, h.why, h.room = "accepted", "accepted", room.id
run(1)
eq(Union.state, "await_room", "accepted: waiting for the room")
run(1)
eq(Union.state, "await_room", "still no room")
Client.bindRoom(room, 0)
run(3)
eq(Union.state, "in_activity", "room_state + match_start: the chat started")
eq(Link.link, nil, "no Game3Link handshake for a chat")
check(Chat.isActive(), "chat is live")
local joinMsg = room.inbox[1][1]
eq(joinMsg and joinMsg.type, "game3_union_hello", "RED announced itself to the room")
room:push(1, { type = "game3_union_hello", name = "GREEN", gender = 1, trainerId = 3, activity = 0x45 })
room:push(1, { type = "game3_chat_line", name = "GREEN", text = "HI RED" })
run(1)
eq(#Chat.lines, 2, "GREEN joined and spoke")
eq(Chat.lines[2] and Chat.lines[2].seat, 1, "GREEN's lines use seat 1's colour")
Chat.stop("left")
run(2)
eq(Union.state, "main", "chat over, back in the room")
eq(rs0.closeCalls, 1, "and the private room was left")
eq(Client.status, "idle", "presence back to idle")

print("[test] 6. an incoming invite rings, asks, and answers the relay")
Client.bindRoom(nil, nil)
Client._invites = { { id = "i0000000000000001", from = { id = "aaaa0002", name = "GREEN" },
  activity = "card", detail = {}, expiresAt = 0 } }
Union.state = "main"
Union.pollIncoming()
eq(Union.state, "player_contacted_you", "the request lands")
eq(Union.activity, Union.ACTIVITY.CARD, "as GREETINGS")
eq(Union._requestName, "GREEN", "from GREEN")
eq(Union.partnerId, 1, "who is in slot 1")
Union.answerRequest(false)
eq(Client.last("replyInvite")[1], "i0000000000000001", "the reply names the invite")
eq(Client.last("replyInvite")[2], false, "and declines it")
eq(Union.state, "main", "back to main")

Client._invites = { { id = "i0000000000000002", from = { id = "aaaa0002", name = "GREEN" },
  activity = "chat", detail = {} } }
Union.state = "do_something_prompt"
Union.pollIncoming()
eq(Client.last("replyInvite")[1], "i0000000000000002", "an invite outside the main loop")
eq(Client.last("replyInvite")[2], false, "is refused at once")

Client._invites = { { id = "i0000000000000003", from = { id = "aaaa0002", name = "GREEN" },
  activity = "card", detail = {} } }
Union.state = "main"
Union.pollIncoming()
Union.answerRequest(true)
eq(Client.last("replyInvite")[2], true, "YES accepts")
eq(Union.state, "await_room", "and waits for the room")
local room2 = FakeRelay.room({ seats = 2, intent = "card" })
Client.bindRoom(room2, 1)
Union.update(1 / 60)
local host2 = Game3Link.attach(FakeRelay.transport(room2, 0), { game = game, seat = 0, seats = 2 })
Link.update(1 / 60)
host2:update(0)
Link.update(1 / 60)
eq(Union.state, "await_link", "GREETINGS waits for the partner's card")
host2:send({ type = Link.MSG.CARD, card = { name = "GREEN", trainerId = 3 } })
Link.update(1 / 60)
Link.update(1 / 60)
eq(Link.peerCard and Link.peerCard.name, "GREEN", "the card arrived")
eq(Union.lastResult, "card_shown", "and the card was shown")
Link.reset()
Client.bindRoom(nil, nil)
Union.state = "main"
Union.relay = true

print("[test] 6b. the TRAINER CARD we send")
local lc = Link.localTrainerCard()
eq(type(lc.stars), "number", "the card we send carries the star count")
eq(type(lc.caughtMonsCount), "number", "and the POKeDEX count")

print("[test] 7. the trading board: register at the attendant, browse at (2,1), offer a mon")
local pickSlot = 1
package.loaded["src.ui.game3.party_menu"] = {
  show = function(_, _, opts) opts.onSelect(pickSlot) end,
  close = function() end,
}
Client.calls = {}
Flags.setVar(store, ctx, 0x800D, Union.INTERACT_ATTENDANT)
run(1)
eq(Union.state, "register_prompt", "the attendant offers the board")
check(settle(), "REGISTER / INFO / EXIT")
eq(Screen.mode, "register", "the register menu")
eq(#Screen.list.items, 3, "three rows")
if romBundle then
  local p = page()
  check(p ~= nil and RomText.ascii("gText_UR_RegisterMonAtTradingBoard", { playerName = "RED" }):find(p, 1, true) ~= nil,
    "gText_UR_RegisterMonAtTradingBoard")
end
Screen.cursor = 1
Screen.confirm()
drain()
check(settle(), "the type list opens after choosing a POKeMON")
eq(Screen.mode, "types", "the requested type list")
eq(#Screen.list.items, 18, "17 types and EXIT")
eq(Screen.list.items[2].id, 10, "row 2 is FIRE (TYPE_FIRE)")
Screen.cursor = 2
Screen.confirm()
local pres = Client.last("setPresence")
local board = pres and pres[1] and pres[1].board
eq(board and board.species, 1, "the board shows the registered species")
eq(board and board.level, 12, "and its level")
eq(board and board.wantType, 10, "wanting a FIRE type")
drain()
eq(Union.state, "main", "registration complete")

local greenMember = Client._plaza.members[1]
eq(greenMember.name, "GREEN", "GREEN's plaza row")
greenMember.board = { species = 4, level = 9, wantType = 12 }
Client._plaza.rev = Client._plaza.rev + 1
run(1)
eq(Union.players[1].board and Union.players[1].board.species, 4, "GREEN's board offer is on the member row")
local offers = Union.boardOffers()
eq(#offers, 1, "one offer on the board")
Player.cellX, Player.cellY, Player.facing = 2, 2, "up"
input.pressed = { a = true }
run(1)
input.pressed = {}
eq(Union.state, "check_trading_board", "A at the board")
check(settle(), "the board list opens")
eq(Screen.mode, "board", "the trading board")
eq(#Screen.list.items, 10, "header, eight offers, EXIT")
check(Screen.list.items[1].disabled, "the header row cannot be picked")
eq(Screen.list.items[1].entry and Screen.list.items[1].entry.species, 1, "and shows our own registration")
eq(Screen.cursor, 2, "the cursor starts on the first offer")
if romBundle then
  Screen.confirm()
  check(settle(), "asked whether to ask GREEN")
  check(shows(RomText.ascii("gText_UR_AskTrainerToMakeTrade", { stringVars = { "GREEN" } })),
    "gText_UR_AskTrainerToMakeTrade")
  pickSlot = 1
  answer(true)
  drain()
  local tinv = Client.last("invite")
  eq(tinv and tinv[1], "aaaa0002", "the offer goes to GREEN")
  eq(tinv and tinv[2], "trade", "as a trade")
  eq(tinv and tinv[3] and tinv[3].board and tinv[3].board.species, 1, "carrying the offered mon")
  eq(Union.state, "send_activity_request", "waiting for GREEN")
  local th = Client.handles[#Client.handles]
  th.state, th.why = "closed", "declined"
  run(1)
  check(shows(RomText.ascii("gText_UR_TradeOfferRejected")), "a declined offer reads gText_UR_TradeOfferRejected")
  drain()
else
  Screen.cancel()
  run(1)
end
eq(Union.state, "main", "back from the board")
Player.cellX, Player.cellY, Player.facing = 7, 11, "down"

print("[test] 7b. the board lists every offer in the room and scrolls; EXIT never collides")
for slot = 5, 16 do
  local m = member(string.format("cccc%04x", slot), slot, "T" .. slot, slot, 0)
  m.board = { species = slot, level = slot, wantType = 12 }
  table.insert(Client._plaza.members, m)
end
Client._plaza.rev = Client._plaza.rev + 1
run(1)
eq(#Union.boardOffers(), 13, "13 offers from 40 possible slots")
Union.openTradingBoard()
eq(Screen.mode, "board", "the trading board")
local items = Screen.list.items
eq(#items, 15, "header, 13 offers, EXIT")
eq(items[#items].id, Screen.BOARD_EXIT, "EXIT has its own id")
eq(items[10].id, 8, "the ninth offer keeps id 8")
check(items[10].entry ~= nil and not items[10].disabled, "and is a real, pickable offer")
eq(Screen.list.maxShowed, 5, "five rows at a time")
Screen.select(10)
check(Screen.list.scroll > 0, "the list scrolls to reach it")
Screen.confirm()
check(Union.state ~= "main", "picking offer id 8 opens that offer, not EXIT (" .. tostring(Union.state) .. ")")
Union.toMain()
Message.reset()
Union.openTradingBoard()
Screen.select(#Screen.list.items)
Screen.confirm()
eq(Union.state, "main", "EXIT closes the board")
for i = #Client._plaza.members, 1, -1 do
  if tostring(Client._plaza.members[i].id):sub(1, 4) == "cccc" then table.remove(Client._plaza.members, i) end
end
Client._plaza.rev = Client._plaza.rev + 1
run(25)

Union.trade().playerSpecies, Union.trade().playerLevel = 1, 12
Flags.setVar(store, ctx, 0x800D, Union.INTERACT_ATTENDANT)
run(1)
eq(Union.state, "cancel_registration_prompt", "a registered player is asked to cancel")
check(settle(), "YES/NO")
answer(true)
pres = Client.last("setPresence")
eq(pres and pres[1] and pres[1].board, false, "cancelling clears the board")
eq(Union.trade().playerSpecies, 0, "and the registration")
drain()
eq(Union.state, "main", "back to main")

print("[test] 7. leaving the Union Room leaves the plaza and goes busy")
Space.mapId = CENTER_MAP
session.map = CENTER_MAP
Union.update(1 / 60)
eq(Union.state, "off", "the union room stopped")
eq(Client.last("leavePlaza")[1], "union", "leavePlaza union")
eq(Client.status, "busy", "presence busy outside the plazas")
Link.reset()
Client.bindRoom(nil, nil)

print("[test] 8. Direct Corner JOIN queues AUTO, B cancels")
Message.reset()
ctx.nativePoll = nil
Flags.setVar(store, ctx, Link.VAR_0x8004, Union.LINK_GROUP.SINGLE_BATTLE)
local y = Natives.special(ctx, NativesLink.SPECIAL.TryJoinLinkGroup, adapters)
eq(y, true, "the script waits")
local q = Client.last("queueDirect")[1]
eq(q and q.activity, "battle_single", "queues battle_single")
eq(q and q.ruleset, "g3_single", "ruleset g3_single")
eq(q and q.auto, true, "AUTO")
eq(q and q.pin, nil, "no PIN")
eq(q and q.profile and q.profile.rulesetId, "g3_single", "profile matches the ruleset")
eq(q and q.avatar and q.avatar.name, "RED", "with the avatar")
eq(q and q.preview and q.preview[1], 1, "and a party preview")
check(shows(ascii("CableClub_Text_PleaseWaitBCancel")), "Please wait. B Button: Cancel")
eq(Client.status, "idle", "queued players are invitable")
eq(ctx.nativePoll(), false, "still waiting")
local Direct = require("src.ui.game3.link_menu").Direct
check(Direct.isOpen() and Direct.view == "wait", "the Direct Corner wait layer owns the input")
input.pressed = { b = true }
Direct.handleInput(input)
eq(ctx.nativePoll(), true, "B resumes the script")
input.pressed = {}
check(not Direct.isOpen(), "the wait layer closed")
eq(Client.count("leaveDirect"), 1, "and leaves the queue")
eq(getVar(Link.VAR_RESULT), Link.LINKUP.FAILED, "LINKUP_FAILED goes back to the menu")
check(not Message.isOpen(), "the wait box closed")

print("[test] 9. Direct Corner LEAD hosts, pairs, and walks into the Trade Center")
Space.mapId = CENTER_MAP
session.map = CENTER_MAP
Player.cellX, Player.cellY = 9, 1
Flags.setVar(store, ctx, Link.VAR_0x8004, Union.LINK_GROUP.TRADE)
ctx.nativePoll, ctx.stateWait = nil, nil
Natives.special(ctx, NativesLink.SPECIAL.TryBecomeLinkLeader, adapters)
q = Client.last("queueDirect")[1]
eq(q and q.activity, "trade", "queues trade")
eq(q and q.auto, false, "LEAD hosts an open room")
local room3 = FakeRelay.room({ seats = 2, intent = "trade" })
local rs3 = room3:session(0)
Client.bindRoom(room3, 0)
eq(ctx.nativePoll(), true, "match_start resumes the script")
eq(getVar(Link.VAR_RESULT), Link.LINKUP.SUCCESS, "LINKUP_SUCCESS")
check(Link.link ~= nil and Link.link.seat == 0, "the link is attached at seat 0")
eq(Link.link and Link.link.linkType, Game3Link.LINKTYPE.TRADE_SETUP, "as a trade link")
check(type(ctx.stateWait) == "function", "the activity is armed for the script's waitstate")
local first = ctx.stateWait
ctx.stateWait = nil
eq(first(), true, "the waitstate right after the special passes")
check(type(ctx.stateWait) == "function", "and re-arms for EnterWirelessLinkRoom's waitstate")
mapLoads = {}
eq(ctx.stateWait(), true, "the final waitstate warps and finishes")
eq(mapLoads[1] and mapLoads[1].map, "FR_TRADE_CENTER", "into the Trade Center")
eq(mapLoads[1] and mapLoads[1].x, 5, "at x 5")
eq(mapLoads[1] and mapLoads[1].y, 8, "at y 8")
eq(getVar(Link.VAR_0x8004), Link.USING.TRADE_CENTER, "VAR_0x8004 = USING_TRADE_CENTER")
eq(getVar(Link.VAR_CABLE_CLUB_STATE), Link.USING.TRADE_CENTER, "VAR_CABLE_CLUB_STATE too")
eq(session.warpDestination and session.warpDestination.map, "FR_TRADE_CENTER",
  "SetCableClubWarp ran at the door")
Link.closeLink("done")
eq(rs3.closeCalls, 1, "closing the link leaves the room")
Link.reset()
Client.bindRoom(nil, nil)

print("[test] 10. SET PIN hosts a locked room")
Union.direct = { mode = "pin", pin = "0420", auto = true }
Flags.setVar(store, ctx, Link.VAR_0x8004, Union.LINK_GROUP.DOUBLE_BATTLE)
ctx.nativePoll, ctx.stateWait = nil, nil
Natives.special(ctx, NativesLink.SPECIAL.TryBecomeLinkLeader, adapters)
q = Client.last("queueDirect")[1]
eq(q and q.activity, "battle_double", "battle_double")
eq(q and q.pin, "0420", "with the PIN")
eq(q and q.auto, true, "letting AUTO players in")
eq(q and q.ruleset, "g3_double", "ruleset g3_double")
eq(Union.direct.mode, nil, "the mode is consumed")
input.pressed = { b = true }
Direct.handleInput(input)
ctx.nativePoll()
input.pressed = {}
Message.reset()

print("[test] 11. a minigame leader accepts joiners and starts the group")
local Lobby = require("src.ui.game3.minigames.common_lobby")
Screen = Lobby
Screen.reset()
Flags.setVar(store, ctx, Link.VAR_0x8004, Union.LINK_GROUP.BERRY_CRUSH)
ctx.nativePoll, ctx.stateWait = nil, nil
Natives.special(ctx, NativesLink.SPECIAL.TryBecomeLinkLeader, adapters)
local og = Client.last("openGroup")
eq(og and og[1], "minigame_crush", "openGroup minigame_crush")
eq(og and og[2] and og[2].rulesetId, "g3_link", "with the g3_link profile")
check(Screen.isOpen() and Screen.mode == "leader", "the leader list is up")
eq(Lobby.group and Lobby.group.min, 2, "the lobby knows Berry Crush needs 2")
eq(Lobby.group and Lobby.group.max, 5, "and takes up to 5")
check(Lobby._onTick ~= nil, "the lobby ticks the flow while the VM is paused")
Client._group = { leader = "0000beef", activity = "minigame_crush", min = 2, max = 5,
  members = { { id = "0000beef", name = "RED", seat = 0, avatar = { name = "RED", trainerId = 0x1234, gender = 0 } },
              { id = "aaaa0001", name = "BLUE", seat = 1, avatar = { name = "BLUE", trainerId = 0x2222, gender = 0 } } },
  pending = { { id = "aaaa0003", name = "GOLD", avatar = { name = "GOLD" } } } }
eq(ctx.nativePoll(), false, "waiting")
check(not Screen.isOpen(), "the list steps aside for the request")
check(Message.isOpen(), "a request prompt is up")
tickMsg()
ctx.nativePoll()
local Choice = require("src.ui.game3.choice")
check(Choice.isOpen(), "YES/NO")
Choice.cursor = 1
Choice.confirm()
eq(Client.last("acceptGroup")[1], "aaaa0003", "the joiner is accepted")
eq(Client.last("acceptGroup")[2], true, "YES")
check(Screen.isOpen() and Screen.mode == "leader", "back on the list")
Client._group.pending = {}
Screen.update(1 / 60)
eq(#Screen.players, 1, "the list shows the accepted member")
check(Screen.confirm(), "START with enough members")
eq(Client.count("startGroup"), 1, "startGroup sent")
local room4 = FakeRelay.room({ seats = 2, intent = "minigame", names = { "RED", "BLUE" } })
room4.players[1].id = "0000beef"
room4.players[2].id = "aaaa0001"
Client.bindRoom(room4, 0)
eq(ctx.nativePoll(), true, "match_start resumes the script")
eq(getVar(Link.VAR_RESULT), Link.LINKUP.SUCCESS, "LINKUP_SUCCESS")
eq(Link.link, nil, "minigames do not attach a Game3Link")
local arm = ctx.stateWait
ctx.stateWait = nil
check(type(arm) == "function", "MG.arm waits for the script's waitstate")
eq(#mgCalls, 0, "not armed yet")
eq(arm(), true, "the waitstate after the special arms it")
eq(#mgCalls, 1, "MG.arm ran once")
local spec = mgCalls[1] and mgCalls[1].spec or {}
eq(spec.game, "crush", "Berry Crush")
eq(spec.seat, 0, "seat 0")
eq(spec.seats, 2, "two seats")
eq(spec.seed, room4.seed, "the relay seed")
eq(spec.partySlot, 1, "the chosen party slot")
eq(spec.players and spec.players[2] and spec.players[2].trainerId, 0x2222,
  "players carry trainer ids from the group avatars")
eq(spec.session, room4:session(0), "and the room session")
Client.bindRoom(nil, nil)
Client._group = nil

print("[test] 12. a minigame joiner picks a group, can back out, and cancel")
Screen.reset()
Flags.setVar(store, ctx, Link.VAR_0x8004, Union.LINK_GROUP.POKEMON_JUMP)
ctx.nativePoll = nil
Client._groups = { { leader = "aaaa0001", name = "BLUE", avatar = { name = "BLUE" }, joined = 1, min = 2, max = 5 } }
Natives.special(ctx, NativesLink.SPECIAL.TryJoinLinkGroup, adapters)
local gl = Client.last("groupList")
eq(gl and gl[1], "minigame_jump", "subscribes to minigame_jump groups")
check(Screen.isOpen() and Screen.mode == "group", "the group list is up")
eq(#Screen.players, 1, "listing BLUE's group")
Screen.confirm()
eq(Client.last("joinGroup")[1], "aaaa0001", "asks to join BLUE")
check(shows(ascii("CableClub_Text_PleaseWaitBCancel")), "waits")
input.pressed = { b = true }
ctx.nativePoll()
input.pressed = {}
eq(Client.count("leaveGroup"), 1, "B withdraws the request")
check(Screen.isOpen(), "back on the list")
Screen.cancel()
eq(ctx.nativePoll(), true, "cancel resumes the script")
eq(getVar(Link.VAR_RESULT), Link.LINKUP.FAILED, "LINKUP_FAILED")
eq(Client.last("groupList")[1], nil, "and unsubscribes")

Link.reset()
if failed == 0 then
  print("[pass] relay union room")
  os.exit(0)
end
print("[fail] relay union room: " .. failed)
os.exit(1)
