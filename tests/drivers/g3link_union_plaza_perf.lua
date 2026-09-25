local U = require("tests.drivers.util")

local CENTER_2F = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F"
local Plaza = require("src.core.game3.link.union_plaza_map")
-- pokefirered/include/constants/flags.h:1375
local FLAG_SYS_POKEDEX_GET = 0x829
local SECONDS = tonumber(os.getenv("PERF_SECONDS")) or 20
local LABEL = os.getenv("POKEPORT_TOUCH") == "1" and "touch" or "desktop"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  local Link = package.loaded["src.core.game3.link"]
  if Link then pcall(Link.reset) end
  local Client = package.loaded["src.online.Client"]
  if Client then pcall(Client.disconnect) end
  if failures == 0 then
    print("PASS g3link_union_plaza_perf")
    love.event.quit(0)
  else
    print("FAIL g3link_union_plaza_perf failures=" .. failures)
    love.event.quit(1)
  end
end

local function now() return love.timer.getTime() end

return function(game)
  print("PASS driver_started")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Player = require("src.core.game3.player")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Link = require("src.core.game3.link")
  local Union = require("src.core.game3.link.union_room")
  local Client = require("src.online.Client")
  local Relay = require("tests.support.fake_relay")
  local Natives = require("src.core.game3.scripting.natives")
  local MapCatalog = require("src.import.gba.map_catalog")

  local relay = Relay.new({ clock = function() return now() end })
  local me = relay:seat("a0000001", "RED")
  Client.configure({ relayAddress = "fake:1", connect = function() return me.transport end })

  local function ctx() return Space.vm and Space.vm.ctx end
  local function wait(n)
    for _ = 1, n do
      relay:pump()
      U.wait(1)
    end
  end
  local function waitFor(cond, seconds)
    local t0 = now()
    while not cond() do
      relay:pump()
      U.wait(1)
      if now() - t0 > (seconds or 5) then return false end
    end
    return true
  end
  local function drive(cond, seconds)
    local t0 = now()
    while not cond() and now() - t0 < (seconds or 10) do
      if Choice.active or Message.isOpen() then U.tap(game, "a") end
      wait(6)
    end
    return cond()
  end

  local live = Link.liveProfile()
  if not result(live ~= nil, "the live g3 profile computes (vanilla game)") then return finish() end
  Link.connect()
  result(waitFor(function() return Client.state() == "online" end, 5), "online on the relay")
  Map.load(nil, game, CENTER_2F, { x = 5, y = 1, facing = "up" })
  wait(30)
  Flags.setFlag(Space.store, ctx(), FLAG_SYS_POKEDEX_GET, true)
  Player.cellX, Player.cellY, Player.targetX, Player.targetY = 5, 1, 5, 1
  Player.px, Player.py, Player.facing = 5 * 16, 1 * 16, "up"
  wait(5)
  -- pokefirered/data/specials.inc:12
  Natives.special(ctx(), 0x01, Space.vm.adapters)
  local slot = MapCatalog.slotKeyFor("FR_UNION_ROOM") or ""
  local group, num = slot:match("(%d+)%D+(%d+)")
  -- pokefirered/data/scripts/cable_club.inc:797
  Space.vm.adapters.warp(tonumber(group), tonumber(num), 0xFF, 7, 11, function() end, "warpspinenter")
  if not result(drive(function() return Space.mapId == Plaza.MAP_ID and Union.state == "main" end, 60),
      "entered the plaza") then
    return finish()
  end

  local peers = {}
  local function addPeers(n)
    while #peers < n do
      local i = #peers + 1
      local id = string.format("d%07x", i)
      local s = relay:seat(id, "P" .. i)
      relay:handle(s, { type = "lobby_hello", protocol = 3, name = "P" .. i, profiles = { live },
        presence = { where = "launcher", status = "idle", version = "firered" } })
      s.avatar = { name = "P" .. i, trainerId = i * 37, gender = i % 2, version = "firered" }
      relay:handle(s, { type = "plaza_join", kind = "union", cap = 40, profile = live, avatar = s.avatar })
      peers[i] = s
    end
  end

  local ownUpdate, ownDraw = rawget(game, "update"), rawget(game, "draw")
  local rawUpdate, rawDraw = game.update, game.draw
  local upd, drw = { sum = 0, max = 0, n = 0 }, { sum = 0, max = 0, n = 0 }
  local function timed(fn, acc)
    return function(self, ...)
      local t = love.timer.getTime()
      local a, b = fn(self, ...)
      local d = (love.timer.getTime() - t) * 1000
      acc.sum, acc.n = acc.sum + d, acc.n + 1
      if d > acc.max then acc.max = d end
      return a, b
    end
  end
  game.update = timed(rawUpdate, upd)
  game.draw = timed(rawDraw, drw)

  local STATUSES = { "chatting", "battling", "idle" }
  local function measure(n)
    addPeers(n)
    result(waitFor(function() return Union.playerCount() == n end, 10), n .. " avatars in the room")
    Player.cellX, Player.cellY, Player.targetX, Player.targetY = 12, 12, 12, 12
    Player.px, Player.py = 12 * 16, 12 * 16
    wait(90)
    upd.sum, upd.max, upd.n = 0, 0, 0
    drw.sum, drw.max, drw.n = 0, 0, 0
    collectgarbage("collect")
    local kb0 = collectgarbage("count")
    local last = kb0
    local allocated = 0
    local frame = { sum = 0, max = 0, n = 0 }
    local builds0 = Union.plazaBuilds or 0
    local t0, tPrev, nextChange, k = now(), now(), now() + 1, 0
    while now() - t0 < SECONDS do
      relay:pump()
      for i = 1, #peers do
        local box = peers[i].transport.inbox
        for j = #box, 1, -1 do box[j] = nil end
      end
      if now() >= nextChange then
        k = k + 1
        local s = peers[(k - 1) % n + 1]
        s.status = STATUSES[(k - 1) % #STATUSES + 1]
        relay:plazaChanged(s)
        nextChange = nextChange + 1
      end
      U.wait(1)
      local t = now()
      local d = (t - tPrev) * 1000
      tPrev = t
      frame.sum, frame.n = frame.sum + d, frame.n + 1
      if d > frame.max then frame.max = d end
      local kb = collectgarbage("count")
      if kb > last then allocated = allocated + (kb - last) end
      last = kb
    end
    local elapsed = now() - t0
    collectgarbage("collect")
    local growth = collectgarbage("count") - kb0
    local line = string.format(
      "PERF %s members=%d seconds=%.1f frames=%d frame_ms mean=%.2f max=%.2f update_ms mean=%.3f max=%.3f"
        .. " draw_ms mean=%.3f max=%.3f alloc_kb_per_s=%.1f gc_growth_kb=%.1f status_changes=%d rebuilds=%d",
      LABEL, n, elapsed, frame.n, frame.sum / math.max(1, frame.n), frame.max,
      upd.sum / math.max(1, upd.n), upd.max, drw.sum / math.max(1, drw.n), drw.max,
      allocated / elapsed, growth, k, (Union.plazaBuilds or 0) - builds0)
    print(line)
    local f = io.open(os.getenv("PERF_OUT") or "/tmp/g3link_union_plaza_perf.log", "a")
    if f then
      f:write(line, "\n")
      f:close()
    end
    result((Union.plazaBuilds or 0) - builds0 <= k + 1, "one rebuild per status change at " .. n)
  end

  measure(8)
  measure(Plaza.CAP - 1)
  game.update, game.draw = ownUpdate, ownDraw
  finish()
end
