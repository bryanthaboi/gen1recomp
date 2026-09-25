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
local function teq(a, b, msg)
  if romBundle then eq(a, b, msg) else print("[skip] ROM text: " .. msg) end
end

package.loaded["src.core.game3.scripting.space"] = {
  store = store,
  mapId = UNION_MAP,
  vm = { ctx = ctx, adapters = adapters },
  ensureBundle = function() return romBundle end,
}
local Space = package.loaded["src.core.game3.scripting.space"]

local Natives = require("src.core.game3.scripting.natives")
local NativesLink = require("src.core.game3.scripting.natives_link")
local Link = require("src.core.game3.link")
local Union = require("src.core.game3.link.union_room")
local Screen = require("src.ui.game3.union_room")
local FakeRelay = require("tests.g3link_fake_relay")
Union._avatars = FakeRelay.avatars()
local Flags = require("src.core.game3.scripting.flags")
local Std = require("src.core.game3.scripting.stdscripts")

local function getVar(id)
  return tonumber(Flags.getVar(store, ctx, id)) or 0
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

print("[test] 3. RunUnionRoom always opens the relay plaza, never a cable room")
local host, guest = FakeRelay.pair({ game = game })
host:update(0)
guest:update(0)
Link.attach(host)
Space.mapId = UNION_MAP
session.map = UNION_MAP
Flags.setVar(store, ctx, Link.VAR_RESULT, 5)
Natives.special(ctx, NativesLink.SPECIAL.RunUnionRoom, adapters)
eq(Union.state, "init", "RunUnionRoom armed the union room task")
eq(getVar(Link.VAR_RESULT), 0, "VAR_RESULT is cleared on entry")
eq(Union.relay, true, "with a cable link up and no relay the room is still the plaza")
eq(Union.capacity(), 40, "holding 40 players")
Union.update(0)
eq(Union.state, "main", "the session reached the main loop")
guest:update(0)
eq(guest:take("game3_union_hello"), nil, "nothing is announced over the cable")
guest:send({ type = "game3_union_hello", name = "BLUE", trainerId = 0x2222, gender = 0, activity = 0x4C })
host:update(0)
Union.update(0)
eq(Union.playerCount(), 0, "and a cable hello adds nobody")
eq(#objectCalls.added, 0, "no cart player object is spawned")

print("[test] 10. stepping on the union room pad returns the dynamic warp, not a header map")
local pad = MAPS[UNION_MAP].warps[1]
eq(tonumber(pad.mapNum), 0x7F, "the pad at (7,11) is MAP_DYNAMIC in the map header")
session.dynamicWarp = { map = CENTER_MAP, warpId = 0, x = 5, y = 3 }
local destMap, destX, destY = Link.resolveDest(session.dynamicWarp)
eq(destMap, CENTER_MAP, "it resolves to the Pokemon Center the player came from")
eq(destX, 5, "at the counter door x")
eq(destY, 3, "at the counter door y")

print("[test] 11. leaving the union room map ends the session")
Space.mapId = CENTER_MAP
session.map = CENTER_MAP
local alive = Union.update(0)
eq(alive, false, "the union room task stopped")
eq(Union.state, "off", "the session is closed")

print("[test] 12. InitUnionRoom has no cable to scan")
Natives.special(ctx, NativesLink.SPECIAL.InitUnionRoom, adapters)
eq(Union.state, "off", "the Pokemon Center ON_RESUME call starts nothing")

print("[test] 13. the link group flows answer LINKUP through VAR_RESULT")
Link.reset()
Space.mapId = UNION_MAP
session.map = UNION_MAP
local host2, guest2 = FakeRelay.pair({ game = game })
host2:update(0)
guest2:update(0)
Link.attach(host2)

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

print("[test] the link group at the counter lists the machine on the cable")
Link.reset()
Union.reset()
local grpHost, grpGuest = FakeRelay.pair({ game = game })
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
