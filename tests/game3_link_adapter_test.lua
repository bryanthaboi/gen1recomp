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

local FakeRelay = require("tests.g3link_fake_relay")

local store = { flags = {}, vars = {} }
local session = { store = store, name = "RED", trainerId = 0x12345, gender = 1, party = {},
  map = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F" }
local input = { pressed = {} }
function input:wasPressed(k) return self.pressed[k] == true end
local game = { data = {}, save = { player = { name = "RED" }, options = {} }, input = input,
  session = session }

package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  isActive = function() return true end,
  _game = game,
}

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

local ctx = { specialVars = {}, stringVars = {} }
local adapters = { log = function() end }
package.loaded["src.core.game3.scripting.space"] = {
  store = store,
  mapId = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F",
  vm = { ctx = ctx, adapters = adapters },
  ensureBundle = function() return romBundle end,
}

local arena = { why = nil, calls = 0 }
local LIVE = { engine = 3, engineVersion = "1.0.0", fingerprint = "f00dcafe", kind = "vanilla",
  version = "firered" }
package.loaded["src.online.ArenaData"] = {
  liveProfile3 = function(g, rulesetId)
    arena.calls = arena.calls + 1
    arena.game = g
    if arena.why then return nil, arena.why end
    local p = {}
    for k, v in pairs(LIVE) do p[k] = v end
    p.rulesetId = rulesetId
    return p
  end,
}

local Client = FakeRelay.client({ state = "offline" })
package.loaded["src.online.Client"] = Client

local Connect = { starts = {}, _state = "offline", _error = nil }
function Connect.start(opts)
  Connect.starts[#Connect.starts + 1] = opts
  if Connect.failStart then return false, Connect.failStart end
  if Client._state == "online" then
    Client.setProfiles(opts.profiles)
    return true
  end
  Connect._state = "connecting"
  return true
end
function Connect.state() return Connect._state end
function Connect.error() return Connect._error end
function Connect.disconnect() Connect._state = "offline" Connect.disconnected = true end
package.loaded["src.online.Connect"] = Connect

local Natives = require("src.core.game3.scripting.natives")
local NativesLink = require("src.core.game3.scripting.natives_link")
local Link = require("src.core.game3.link")
local Flags = require("src.core.game3.scripting.flags")

local function result()
  return tonumber(Flags.getVar(store, ctx, Link.VAR_RESULT)) or 0
end

local function adapter()
  Flags.setVar(store, ctx, Link.VAR_RESULT, 7)
  return Natives.special(ctx, NativesLink.SPECIAL.IsWirelessAdapterConnected, adapters)
end

local function reset()
  Link.reset()
  Client._state = "offline"
  Client._profiles = {}
  Client.clear()
  Connect.starts = {}
  Connect._state = "offline"
  Connect._error = nil
  Connect.failStart = nil
  Connect.disconnected = nil
  arena.why = nil
  ctx.nativePoll = nil
  input.pressed = {}
end

print("[test] 1. headless and offline the adapter reads not connected")
reset()
local yielded, value = adapter()
eq(yielded, false, "no prompt without a screen")
eq(value, 0, "IsWirelessAdapterConnected is FALSE")
eq(result(), 0, "VAR_RESULT is FALSE")
eq(#Connect.starts, 0, "nothing tried to connect")

print("[test] 2. online with the live Gen 3 profile the adapter is connected")
reset()
Client._state = "online"
Client._profiles = { { engine = 1, fingerprint = "gen1" }, LIVE }
yielded, value = adapter()
eq(value, 1, "TRUE")
eq(result(), 1, "VAR_RESULT is TRUE")
eq(arena.game, game, "the profile is computed from the live game")
Client._profiles = { { engine = 3, fingerprint = "someone-else", engineVersion = "1.0.0" } }
Link._live = nil
eq(Link.adapterConnected(), false, "a Gen 3 profile with another fingerprint is not accepted")

print("[test] 3. online without the profile, the live profile is added and the adapter connects")
reset()
Client._state = "online"
yielded, value = adapter()
eq(value, 1, "TRUE after Connect.start adds the profile")
eq(#Connect.starts, 1, "Connect.start ran once (already-online path)")
local opts = Connect.starts[1] or {}
eq(opts.source, "game", "source is game")
eq(opts.version, "firered", "version is the running cart")
eq(opts.trainerName, "RED", "trainer name from the save")
eq(opts.profiles and opts.profiles[1] and opts.profiles[1].fingerprint, LIVE.fingerprint,
  "the one profile is the live g3 profile")
eq(opts.profiles and opts.profiles[1] and opts.profiles[1].rulesetId, "g3_link", "for g3_link")
eq(opts.presence and opts.presence.where, "game", "presence where is game")
eq(opts.presence and opts.presence.status, "busy", "presence status is busy")

print("[test] 4. offline with a screen: prompt, YES, Connecting..., online")
reset()
love = { graphics = {} }
local Message = require("src.ui.game3.message")
local Choice = require("src.ui.game3.choice")
local Strings = require("src.core.Strings")
yielded = adapter()
eq(yielded, true, "the script parks on the prompt")
check(Message.isOpen(), "a message is up")
eq(Message.currentPage(), Strings("Connect to the Wireless Club?"), "asking to connect")
for _ = 1, 300 do Message.tick() end
eq(ctx.nativePoll(), false, "still waiting")
check(Choice.isOpen(), "YES/NO is offered once the text printed")
Choice.cursor = 1
Choice.confirm()
eq(#Connect.starts, 1, "YES starts the connection")
eq(Message.currentPage(), Strings("Connecting..."), "Connecting... is shown")
eq(Message._stay, true, "without a prompt arrow")
eq(ctx.nativePoll(), false, "waits while connecting")
Connect._state = "online"
Client._state = "online"
Client._profiles = { LIVE }
eq(ctx.nativePoll(), true, "resumes once online with the profile")
eq(result(), 1, "VAR_RESULT is TRUE")
check(not Message.isOpen(), "the message closed")

print("[test] 5. NO leaves the adapter unconnected")
reset()
Message.reset()
adapter()
for _ = 1, 300 do Message.tick() end
ctx.nativePoll()
Choice.cursor = 2
Choice.confirm()
eq(ctx.nativePoll(), true, "the script resumes")
eq(result(), 0, "VAR_RESULT is FALSE")
eq(#Connect.starts, 0, "nothing connected")

print("[test] 6. a modded game names the reason and stays unconnected")
reset()
Message.reset()
arena.why = "mods"
adapter()
for _ = 1, 300 do Message.tick() end
ctx.nativePoll()
Choice.cursor = 1
Choice.confirm()
eq(#Connect.starts, 0, "no connection is attempted")
eq(Message.currentPage() ~= nil and Message.currentPage():find("Mods", 1, true) ~= nil, true,
  "the reason line names the mods")
eq(ctx.nativePoll(), false, "waits for the player to read it")
for _ = 1, 300 do Message.tick() end
Message.advance()
eq(ctx.nativePoll(), true, "then resumes")
eq(result(), 0, "VAR_RESULT is FALSE")

print("[test] 7. a failed connection names the error")
reset()
Message.reset()
adapter()
for _ = 1, 300 do Message.tick() end
ctx.nativePoll()
Choice.cursor = 1
Choice.confirm()
Connect._state = "error"
Connect._error = "This build is too old for online play. Please update."
ctx.nativePoll()
check(Message.currentPage():find("too old", 1, true) ~= nil, "the relay's text is shown")
for _ = 1, 4 do
  for _ = 1, 300 do Message.tick() end
  Message.advance()
end
eq(ctx.nativePoll(), true, "then the script resumes")
eq(result(), 0, "VAR_RESULT is FALSE")

print("[test] 8. B while connecting cancels")
reset()
Message.reset()
adapter()
for _ = 1, 300 do Message.tick() end
ctx.nativePoll()
Choice.cursor = 1
Choice.confirm()
input.pressed = { b = true }
eq(ctx.nativePoll(), true, "B resumes the script")
eq(Connect.disconnected, true, "and drops the connection attempt")
eq(result(), 0, "VAR_RESULT is FALSE")
input.pressed = {}

print("[test] 9. the wireless monitor subscribes to plaza counts while it is open")
reset()
Message.reset()
Client._state = "online"
Client._profiles = { LIVE }
Client._counts = { union = 3, trade = 2, battle = 4, chat = 1, minigame = 0, total = 9 }
local LinkMenu = require("src.ui.game3.link_menu")
local Status = require("src.core.game3.link.status")
love = nil
LinkMenu.show({})
local join = Client.last("joinPlaza")
eq(join and join[1], "wireless", "the monitor joins the wireless plaza")
eq(join and join[3] and join[3].name, "RED", "with the cart OT name")
eq(join and join[3] and join[3].trainerId, 0x12345 % 65536, "a 16-bit trainer id")
eq(join and join[3] and join[3].gender, 1, "the gender")
eq(join and join[3] and join[3].version, "firered", "and the version")
local rows = LinkMenu.rows
eq(rows[Status.GROUPTYPE.TRADE].count, 2, "TRADE row = plaza_counts.trade")
eq(rows[Status.GROUPTYPE.BATTLE].count, 4, "BATTLE row = plaza_counts.battle")
eq(rows[Status.GROUPTYPE.UNION].count, 3, "UNION row = plaza_counts.union")
eq(rows[Status.GROUPTYPE.TOTAL].count, 9, "TOTAL row = plaza_counts.total")
Client._counts = { union = 5, trade = 0, battle = 0, total = 5 }
for _ = 1, LinkMenu.ROWS_FRAMES + 1 do LinkMenu.update(1 / 60) end
eq(LinkMenu.rows[Status.GROUPTYPE.UNION].count, 5, "rows refresh from new counts")
LinkMenu.close()
eq(Client.last("leavePlaza") and Client.last("leavePlaza")[1], "wireless", "closing leaves the plaza")

reset()
LinkMenu.show({})
eq(Client.count("joinPlaza"), 0, "offline the monitor joins nothing")
eq(LinkMenu.rows[Status.GROUPTYPE.TOTAL].count, 0, "and counts nothing")
LinkMenu.close()
eq(Client.count("leavePlaza"), 0, "nor leaves anything")

print("[test] 10. the wireless icon follows the connection state")
local WirelessIcon = require("src.ui.game3.wireless_icon")
WirelessIcon.reset()
Connect._state = "offline"
Client._state = "offline"
eq(WirelessIcon.anim(), nil, "offline: hidden")
Connect._state = "connecting"
eq(WirelessIcon.anim(), "searching", "connecting: searching")
Connect._state = "reconnecting"
eq(WirelessIcon.anim(), "searching", "reconnecting: searching")
Connect._state = "online"
eq(WirelessIcon.anim(), "3bars", "online: three bars")
Connect._state = "error"
eq(WirelessIcon.anim(), "error", "error: error")
-- pokefirered/src/link_rfu_3.c:448
local bars = { [0] = 1, [4] = 1, [5] = 2, [10] = 3, [15] = 4, [24] = 4, [25] = 3, [30] = 2, [35] = 1 }
for f, frame in pairs(bars) do
  eq(WirelessIcon.frameFor("3bars", f), frame, "3 bars at frame " .. f)
end
eq(WirelessIcon.frameFor("searching", 0), 1, "searching starts on frame 1")
eq(WirelessIcon.frameFor("searching", 10), 5, "then frame 5")
eq(WirelessIcon.frameFor("error", 0), 6, "error starts on frame 6")
eq(WirelessIcon.frameFor("error", 10), 1, "then frame 1")
Connect._state = "online"
WirelessIcon.frame()
WirelessIcon.update(10 / 60)
eq(WirelessIcon.frame(), 3, "update(dt) advances the 60 Hz counter")
check(WirelessIcon.onLinkMap("FR_VIRIDIAN_CITY_POKEMON_CENTER_2F"), "shown on a Pokemon Center 2F")
check(WirelessIcon.onLinkMap("FR_UNION_ROOM"), "and in the Union Room")
check(not WirelessIcon.onLinkMap("FR_PALLET_TOWN"), "not out in the field")
eq(WirelessIcon.X, 231, "sprite centre x 231")
eq(WirelessIcon.Y, 8, "sprite centre y 8")

reset()
if failed == 0 then
  print("[pass] link adapter")
  os.exit(0)
end
print("[fail] link adapter: " .. failed)
os.exit(1)
