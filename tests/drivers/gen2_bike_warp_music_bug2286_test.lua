-- engine/overworld/events.asm:993, data/maps/setup_scripts.asm:117
local U = require("tests.drivers.util")

local FieldMoves = require("src.world.gen2.FieldMoves")
local Music = require("src.core.Music")
local Permissions = require("src.world.gen2.Permissions")

local RIDEABLE = { TOWN = true, ROUTE = true, CAVE = true, GATE = true }
local STEP = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

return function(game)
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR")
    or "/tmp/bike-warp-2286"
  local fails = 0
  local function say(line) print("[2286] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
  end
  local function bail(line)
    say("FAIL " .. line)
    love.event.quit(1)
  end

  U.wait(60)
  local world = game.world
  if not (world and world.map) then return bail("the gen2 world did not boot") end

  local SOURCE = "ROUTE_31"
  local def = world.maps and world.maps[SOURCE]
  if not (def and def.warps) then return bail(SOURCE .. " has no warps") end

  local mapSongs = game.data.audio and game.data.audio.mapSongs or {}
  local function songOf(mapId)
    return world:mapMusicSong(mapId) or mapSongs[mapId]
  end
  local source = songOf(SOURCE)
  local candidates = {}
  for _, w in ipairs(def.warps) do
    local d = w.destMap and world.maps[w.destMap]
    if d and RIDEABLE[d.environment] and songOf(w.destMap) then
      local rank = (songOf(w.destMap) ~= source) and 1 or 2
      candidates[#candidates + 1] = { warp = w, rank = rank }
    end
  end
  table.sort(candidates, function(a, b) return a.rank < b.rank end)
  for _, c in ipairs(candidates) do
    say(("candidate %d,%d -> %s (%s)"):format(c.warp.x, c.warp.y,
      tostring(c.warp.destMap), tostring(songOf(c.warp.destMap))))
  end
  if #candidates == 0 then return bail("no rideable-to-rideable warp on " .. SOURCE) end

  world:warpToMapId(SOURCE, 0, 0, "down")
  U.wait(90)
  if world.map.id ~= SOURCE then
    return bail("could not reach " .. SOURCE .. " (on " .. tostring(world.map.id) .. ")")
  end

  local shot, crossed, walkDir, warp = false, false, nil, nil
  for _, c in ipairs(candidates) do
    local w = c.warp
    local coll = world.map:cellCollision(w.x, w.y)
    local need = Permissions.carpetDirection(coll)
    local tries = {}
    for dir, d in pairs(STEP) do
      if (not need) or dir == need then
        local x, y = w.x - d[1], w.y - d[2]
        if Permissions.isWalkable(world.map:cellCollision(x, y)) then
          tries[#tries + 1] = { x, y, dir }
        end
      end
    end
    for _, t in ipairs(tries) do
      world:warpToMapId(SOURCE, t[1], t[2], t[3])
      U.wait(90)
      world:applyPlayerState(FieldMoves.PLAYER_BIKE)
      world:playBikeMusic()
      U.wait(10)
      if not shot then
        shot = true
        ok(Music.current() == "Music_Bicycle",
          "riding the bike theme on " .. SOURCE .. " (got "
          .. tostring(Music.current()) .. ")")
        U.shot(game, DIR .. "/2286_01_gold_bike_route31.png")
      end
      say(("try %d,%d walking %s onto %d,%d (at %s,%s)"):format(t[1], t[2],
        t[3], w.x, w.y, tostring(world.player.cellX),
        tostring(world.player.cellY)))
      for _ = 1, 8 do
        U.hold(game, t[3], 16)
        if world.map.id ~= SOURCE then
          crossed, walkDir, warp = true, t[3], w
          break
        end
      end
      say(("  ended at %s,%s on %s"):format(tostring(world.player.cellX),
        tostring(world.player.cellY), tostring(world.map.id)))
      if crossed then break end
    end
    if crossed then break end
  end
  ok(crossed, "walked " .. tostring(walkDir) .. " into the warp at "
    .. (warp and (warp.x .. "," .. warp.y) or "?")
    .. " (now on " .. tostring(world.map.id) .. ")")
  ok(FieldMoves.isBiking(world.playerState),
    "still mounted on the far side (state " .. tostring(world.playerState) .. ")")

  U.wait(8 * Music.MAP_FADE)
  local want = songOf(world.map.id)
  say("destination song is " .. tostring(want)
    .. ", playing " .. tostring(Music.current()))
  ok(Music.current() ~= "Music_Bicycle",
    "the bike theme did not restart across a walked warp")
  ok(Music.current() == want, "the destination map's own theme is playing")
  ok(Music.mapSong() == Music.current(),
    "FadeToMapMusic left wMapMusic on the new song")
  U.shot(game, DIR .. "/2286_02_gold_bike_dest.png")

  say(fails == 0 and "ALL PASS" or (fails .. " FAILURES"))
  love.event.quit(fails == 0 and 0 or 1)
end
