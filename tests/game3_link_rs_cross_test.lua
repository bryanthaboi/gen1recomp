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
local session = {
  version = "ruby", store = store, map = "RS_TEST_POKEMON_CENTER_2F", x = 5, y = 3,
  name = "BRENDAN", gender = 0, trainerId = 0x2222,
  party = { { species = 280, level = 12 }, { species = 283, level = 9 } },
  bag = { pockets = { items = {} } },
}
local game = { data = { maps = {} }, session = session, input = { wasPressed = function() return false end },
  save = { player = { name = "BRENDAN" } } }
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  isActive = function() return true end,
  _game = game,
}
package.loaded["src.core.game3.player"] = { cellX = 5, cellY = 3, facing = "up" }
package.loaded["src.core.game3.map"] = { load = function() end }
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
local ctx = { specialVars = {}, stringVars = {} }
local adapters = { log = function() end, playSe = function() end }
package.loaded["src.core.game3.scripting.space"] = {
  store = store, mapId = session.map, vm = { ctx = ctx, adapters = adapters },
  ensureBundle = function() return nil end,
}
package.loaded["src.online.ArenaData"] = {
  liveProfile3 = function(_, rulesetId)
    return { engine = 3, engineVersion = "1.0.0", fingerprint = "f00dcafe", kind = "vanilla",
      version = session.version, rulesetId = rulesetId }
  end,
}
local Client = FakeRelay.client({ state = "online", id = "0000beef" })
package.loaded["src.online.Client"] = Client

local Link = require("src.core.game3.link")
local LB = require("src.core.game3.link.battle")
local Flags = require("src.core.game3.scripting.flags")
local Lobby = require("src.ui.game3.rs.cable_lobby")
local Game3Link = require("src.link.Game3Link")
local RsNatives = require("src.core.game3.scripting.natives_link_rs").BY_NAME
local RseNatives = require("src.core.game3.scripting.natives_link_rse").BY_NAME
local ContestNatives = require("src.core.game3.scripting.natives_contest").BY_NAME
local CL = require("src.core.game3.link.contest_link")

local function setVar(id, v) Flags.setVar(store, ctx, id, v) end
local function getVar(id) return tonumber(Flags.getVar(store, ctx, id)) or 0 end
local function pick(id)
  for _, row in ipairs(Lobby.rows()) do
    if row.id == id and not row.disabled then return Lobby.opts.select(row) end
  end
  error("no enabled row " .. tostring(id))
end
local function pump(peers)
  for _ = 1, 4 do
    for _, p in ipairs(peers) do p:update(0) end
    Link.update(0)
  end
end

local function linkup(version, start, peerVersions, peerLinkType, max)
  session.version = version
  ctx.specialVars, ctx.nativePoll = {}, nil
  Client.clear()
  Client._group, Client._room, Client._seat = nil, nil, nil
  Lobby.reset()
  Link.reset()
  Link._live = nil
  local yielded = start()
  if not yielded then return nil, "did not yield" end
  pick("leader")
  local members = { { id = "0000beef", name = session.name } }
  for i = 1, #peerVersions do members[#members + 1] = { id = string.format("00e0000%d", i), name = "P" .. i } end
  Client._group = { leader = "0000beef", min = 2, max = max, members = members, pending = {} }
  ctx.nativePoll()
  if Client.count("startGroup") == 0 then pick("start") end
  local room = FakeRelay.room({ seats = #peerVersions + 1 })
  Client.bindRoom(room, 0)
  local peers = {}
  for i, v in ipairs(peerVersions) do
    local hello = Game3Link.hello(game, peerLinkType, { version = v, name = v:upper() .. i, trainerId = 0x3000 + i })
    peers[i] = Game3Link.attach(FakeRelay.transport(room, i), {
      game = game, linkType = peerLinkType, seat = i, seats = room.seats, hello = hello,
    })
  end
  ctx.nativePoll()
  pump(peers)
  for _ = 1, LB.LINKUP_TICKS + 5 do
    if ctx.nativePoll() then break end
  end
  return getVar(Link.VAR_RESULT), peers
end

local LT = Game3Link.LINKTYPE

print("[test] 1. trade: Ruby cable vs Emerald, both directions")
local code = linkup("ruby", function() return RsNatives.sub_80834E4(ctx, adapters) end,
  { "emerald" }, LT.TRADE_SETUP, 2)
eq(code, Link.LINKUP.SUCCESS, "Ruby's Trade Center links with an Emerald trader")
code = linkup("emerald", function() return RseNatives.TryTradeLinkup(ctx, adapters) end,
  { "sapphire" }, LT.TRADE_SETUP, 2)
eq(code, Link.LINKUP.SUCCESS, "Emerald's cable Trade Center links with a Sapphire trader")

print("[test] 2. battles: Ruby cable vs Emerald and FireRed wireless players")
code = linkup("ruby", function() setVar(0x8004, 1); return RsNatives.sub_808347C(ctx, adapters) end, { "emerald" }, LT.BATTLE, 2)
eq(code, Link.LINKUP.SUCCESS, "single battle with an Emerald Direct Corner player")
code = linkup("sapphire", function() setVar(0x8004, 2); return RsNatives.sub_808347C(ctx, adapters) end, { "firered" }, LT.BATTLE, 2)
eq(code, Link.LINKUP.SUCCESS, "double battle with a FireRed Direct Corner player")
code = linkup("ruby", function() setVar(0x8004, 5); return RsNatives.sub_808347C(ctx, adapters) end,
  { "emerald", "leafgreen", "sapphire" }, LT.BATTLE, 4)
eq(code, Link.LINKUP.SUCCESS, "multi battle with Emerald, LeafGreen and Sapphire")
code = linkup("emerald", function() setVar(0x8004, 1); return RseNatives.TryBattleLinkup(ctx, adapters) end, { "ruby" }, LT.SINGLE_BATTLE, 2)
eq(code, Link.LINKUP.SUCCESS, "Emerald's cable colosseum with a Ruby cable player")
code = linkup("emerald", function() setVar(0x8004, 1); return RseNatives.TryBattleLinkup(ctx, adapters) end, { "ruby" }, LT.DOUBLE_BATTLE, 2)
eq(code, Link.LINKUP.DIFF_SELECTIONS, "a single vs double cable pick is still LINKUP_DIFF_SELECTIONS")

print("[test] 3. record corner: Ruby with Emerald, three players")
code = linkup("ruby", function() return RsNatives.sub_808350C(ctx, adapters) end,
  { "emerald", "sapphire" }, LT.RECORD_MIX_BEFORE, 4)
eq(code, Link.LINKUP.SUCCESS, "Ruby's Record Corner links three players")
local players = Link.link and Link.link:players() or {}
eq(#players, 3, "all three seats are linked")
eq(players[2] and players[2].version, "emerald", "seat 1 is the Emerald player")
check(require("src.core.game3.link.rs_record_cross").anyRS(players), "Emerald sees an RS partner and uses the RS layout")

print("[test] 4. berry blender: Ruby and Emerald blend in step")
local blendPeers
code, blendPeers = linkup("ruby", function() return RsNatives.sub_8083614(ctx, adapters) end,
  { "emerald" }, LT.BERRY_BLENDER_SETUP, 4)
eq(code, Link.LINKUP.SUCCESS, "Ruby's blender links with an Emerald blender")
eq(Link.link and Link.link.linkType, LT.BERRY_BLENDER_SETUP, "the link runs as LINKTYPE_BERRY_BLENDER_SETUP")
local Blend = require("src.core.game3.rse.berry_blender_link")
local mine = Blend.new(Link.link, Link.link:players())
local theirs = Blend.new(blendPeers[1], blendPeers[1]:players())
eq(mine.rngState, theirs.rngState, "both machines seed the same blender RNG")
local a, b
for _ = 1, 8 do
  a = a or mine:submitBerry(133)
  b = b or theirs:submitBerry(140)
  pump(blendPeers)
end
eq(a and a[1], 140, "Ruby sees the Emerald berry")
eq(b and b[0], 133, "Emerald sees the Ruby berry")
local fa, fb
for _ = 1, 8 do
  fa = fa or mine:exchangeFrame(1, 2)
  fb = fb or theirs:exchangeFrame(1, 3)
  pump(blendPeers)
end
eq(fa and fa[1], 3, "the per-frame scores cross over")
eq(fb and fb[0], 2, "both ways")

print("[test] 5. contests: Ruby with three Emerald players")
code = linkup("ruby", function() setVar(0x8011, 0); return RsNatives.sub_808363C(ctx, adapters) end,
  { "emerald", "emerald", "emerald" }, 0x6602, 4)
eq(code, Link.LINKUP.SUCCESS, "Ruby's COOL contest links with three Emerald wireless contestants")
local flags = CL.flagsFor(Link.link, false)
eq(flags, CL.FLAG.IS_LINK + CL.FLAG.HAS_RS_PLAYER, "the contest is flagged HAS_RS_PLAYER")
code = linkup("emerald", function() setVar(0x8011, 0); return ContestNatives.TryContestEModeLinkup(ctx, adapters) end,
  { "ruby" }, 0x6601, 4)
eq(code, Link.LINKUP.SUCCESS, "Emerald's cable contest links with a Ruby contestant")
eq(CL.flagsFor(Link.link, true), CL.FLAG.IS_LINK + CL.FLAG.IS_WIRELESS + CL.FLAG.HAS_RS_PLAYER,
  "and a wireless Emerald contest with a Ruby player skips the standby too")
session.version = "ruby"
ctx.specialVars, ctx.nativePoll = {}, nil
Client.clear()
Client._group, Client._room, Client._seat = nil, nil, nil
Lobby.reset()
Link.reset()
setVar(0x8011, 0)
RsNatives.sub_808363C(ctx, adapters)
pick("join")
Client._groups = { { leader = "00e00009", name = "MAY", avatar = { name = "MAY" }, joined = 1, max = 4 } }
pick("00e00009")
eq(Client.last("joinGroup") and Client.last("joinGroup")[1], "00e00009", "Ruby joins an Emerald wireless contest group")
local room2 = FakeRelay.room({ seats = 2 })
Client.bindRoom(room2, 1)
local lead = Game3Link.attach(FakeRelay.transport(room2, 0), { game = game, linkType = 0x6602, seat = 0, seats = 2,
  hello = Game3Link.hello(game, 0x6602, { version = "emerald", name = "MAY", trainerId = 0x4444 }) })
ctx.nativePoll()
pump({ lead })
for _ = 1, LB.LINKUP_TICKS + 5 do
  if ctx.nativePoll() then break end
end
eq(getVar(Link.VAR_RESULT), Link.LINKUP.WRONG_NUM_PLAYERS,
  "a two player contest started by Emerald is LINKUP_WRONG_NUM_PLAYERS on Ruby")

Link.reset()
Lobby.reset()

print("[test] 6. record mixing data crosses Ruby and Emerald")
local function cacheRoot(version)
  local env = os.getenv("POKEPORT_" .. version:upper() .. "_CACHE")
  if env and env ~= "" then return env end
  local identity, home = os.getenv("POKEPORT_" .. version:upper() .. "_IDENTITY") or os.getenv("POKEPORT_IDENTITY"), os.getenv("HOME")
  if identity and identity ~= "" and home then
    for _, base in ipairs({ home .. "/Library/Application Support/LOVE/", home .. "/.local/share/love/" }) do
      local root = base .. identity .. "/" .. version .. "/data/generated/gba"
      local f = io.open(root .. "/meta.json", "rb")
      if f then f:close(); return root end
    end
  end
  return require("tests.game3_cache").root(version)
end
local rubyRoot, emeraldRoot = cacheRoot("ruby"), cacheRoot("emerald")
if not (rubyRoot and emeraldRoot) then
  print("[skip] 6. needs a Ruby and an Emerald cache (POKEPORT_RUBY_CACHE / POKEPORT_EMERALD_CACHE)")
else
  local tmp = os.tmpname()
  local function side(version, root, seat, out, inp)
    local cmd = string.format("POKEPORT_GBA_CACHE=%q luajit tests/g3link_rs_mix_side.lua %s %d %q %s 2>&1",
      root, version, seat, out, inp and string.format("%q", inp) or "")
    local p = io.popen(cmd)
    local text = p:read("*a")
    p:close()
    local out2 = {}
    for k, v in text:gmatch("\n?(%w+) ([^\n]*)") do out2[k] = v end
    return out2, text
  end
  local rubyOut, emOut = tmp .. ".ruby", tmp .. ".em"
  local r1 = side("ruby", rubyRoot, 1, rubyOut)
  local e = side("emerald", emeraldRoot, 0, emOut, rubyOut)
  local r = side("ruby", rubyRoot, 1, rubyOut, emOut)
  eq(e.layout, "rs", "Emerald sends the RS record layout to a Ruby partner")
  check((tonumber(e.bytes) or 1e9) < 65536, "and the packet fits the relay's rse_record_mix cap (" .. tostring(e.bytes) .. ")")
  check((tonumber(r1.bytes) or 1e9) < 65536, "Ruby's packet fits too (" .. tostring(r1.bytes) .. ")")
  eq(e.unsupported, "nil", "Emerald takes Ruby's records")
  eq(e.secretBases, "true", "Emerald mixes the secret bases")
  eq(e.tvShows, "true", "and the TV shows")
  eq(r.unsupported, "nil", "Ruby takes Emerald's records")
  eq(r.oldMan, "true", "Ruby swaps the old man")
  eq(r.daycareMail, "true", "and the daycare mail")
  os.remove(tmp)
  os.remove(rubyOut)
  os.remove(emOut)
end

print(string.format("%s game3_link_rs_cross_test", failed == 0 and "PASS" or ("FAIL " .. failed)))
os.exit(failed == 0 and 0 or 1)
