-- Manual check that a warp arrival hides Pikachu under the player (#863):
-- pokeyellow spawns on the player's own coords and the follow buffer walks
-- it out, but before the fix it popped in already beside him.
-- Warp cells: pokered data/maps/objects/RedsHouse1F.asm / RedsHouse2F.asm.
--   POKEPORT_DRIVER=tests/drivers/pikachu_warp_spawn_bug863_test.lua POKEPORT_IDENTITY=bug863 POKEPORT_TOUCH=0 POKEPORT_VERSION=yellow love .
-- Never add POKEPORT_SPEED; the identity needs an imported Yellow cache.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local GameVersion = require("src.core.GameVersion")
  local PF = require("src.world.PikachuFollower")
  local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local failures = 0

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    if not ok then failures = failures + 1 end
    return ok
  end

  check("running as Yellow (needs POKEPORT_VERSION=yellow)",
        GameVersion.isYellow())

  -- the follower only spawns behind EVENT_GOT_STARTER with a healthy
  -- PIKACHU in the party (PikachuFollower shouldSpawn)
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true
  game.save.flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true
  game.save.pikachuInBall = false
  game.save.party = { Pokemon.new(game.data, "PIKACHU", 20) }
  game.save.onBike = false
  game.save.player.name = "bryan"

  -- pokered RedsHouse1F.asm: warp_event 7, 1 -> REDS_HOUSE_2F, and
  -- RedsHouse2F.asm: warp_event 7, 1 back down.  Read the live map data
  -- so a hack or mod that moved the stairs still points us at them.
  local function warpTo(fromMap, destMap)
    local def = game.data.maps[fromMap]
    for _, w in ipairs(def and def.warps or {}) do
      if w.destMap == destMap then return w.x, w.y end
    end
    return nil
  end
  local wx, wy = warpTo("REDS_HOUSE_1F", "REDS_HOUSE_2F")
  check("REDS_HOUSE_1F has a warp to REDS_HOUSE_2F", wx ~= nil)
  wx, wy = wx or 7, wy or 1

  local follower = function() return PF.current(game.overworld) end

  local function overlapsPlayer()
    local npc = follower()
    local p = game.overworld and game.overworld.player
    return npc and p and npc.cellX == p.cellX and npc.cellY == p.cellY
  end

  -- press-and-hold dir until the map flips, releasing the instant it
  -- does so no queued step drags the player off the arrival warp cell
  local function walkUntilMap(dir, targetMap, maxFrames)
    for _ = 1, maxFrames do
      local ow = game.overworld
      if ow and ow.map and ow.map.id == targetMap then break end
      table.insert(game.input.pressQueue, dir)
      game.input.state[dir] = true
      coroutine.yield()
    end
    game.input.state[dir] = false
    U.wait(45) -- warp fade + arrival settle
    local ow = game.overworld
    return ow and ow.map and ow.map.id == targetMap
  end

  -- stand two below the stairs facing up; fall back to any walkable cell
  -- below the warp if a mod reshaped the room
  local sx, sy = wx, wy + 2
  U.teleport(game, "REDS_HOUSE_1F", sx, sy, "up")
  U.wait(10)
  local ow = game.overworld
  if not ow.map:isWalkableCell(sx, sy) then
    for dy = 1, 3 do
      if ow.map:isWalkableCell(wx, wy + dy) then
        sx, sy = wx, wy + dy
        U.teleport(game, "REDS_HOUSE_1F", sx, sy, "up")
        U.wait(10)
        break
      end
    end
  end
  -- U.teleport is itself a fresh map load, so the fixed spawn already
  -- parks Pikachu on the player's cell here
  check("follower spawned on map load", follower() ~= nil)
  check("map-load spawn is on the player's own cell", overlapsPlayer())

  -- climb the stairs
  check("walked up into REDS_HOUSE_2F",
        walkUntilMap("up", "REDS_HOUSE_2F", 240))
  check("warp arrival upstairs: Pikachu hidden under the player",
        overlapsPlayer())
  U.shot(game, SHOT_DIR .. "/bug863_2f_arrival.png")

  -- the draw sort tie-break (#863): sharing the player's py must list the
  -- follower first so he draws over it.  The sort runs in draw, and the
  -- shot above rendered a frame, so entities order is post-sort here.
  do
    local npc = follower()
    local p = game.overworld.player
    if npc and p and npc.py == p.py then
      local ni, pi
      for i, e in ipairs(game.overworld.entities) do
        if e == npc then ni = i elseif e == p then pi = i end
      end
      check("draw sort puts the hidden follower under the player",
            ni ~= nil and pi ~= nil and ni < pi)
    end
  end

  -- walk off the stairs: the trail should pull Pikachu out one behind
  U.hold(game, "down", 20)
  U.wait(20)
  U.hold(game, "down", 20)
  U.wait(30)
  do
    local npc = follower()
    local p = game.overworld.player
    check("two steps later Pikachu trails one cell behind",
          npc and p and npc.cellX == p.cellX and npc.cellY == p.cellY - 1)
    check("and it faces down, walking out of the stairwell",
          npc and npc.facing == "down")
  end
  U.shot(game, SHOT_DIR .. "/bug863_2f_trailing.png")

  -- back down the same stairs: descent must hide it the same way
  check("walked back down into REDS_HOUSE_1F",
        walkUntilMap("up", "REDS_HOUSE_1F", 240))
  check("warp arrival downstairs: Pikachu hidden under the player",
        overlapsPlayer())
  U.shot(game, SHOT_DIR .. "/bug863_1f_return.png")

  -- regression: a connection seam is the keepPikachu path (#427), not a
  -- respawn, so the follower must ride across it, not vanish or repark
  U.teleport(game, "PALLET_TOWN", 10, 2, "up")
  U.wait(10)
  check("crossed the Pallet Town north seam into ROUTE_1",
        walkUntilMap("up", "ROUTE_1", 300))
  do
    local npc = follower()
    local p = game.overworld.player
    check("follower survived the connection crossing", npc ~= nil)
    check("and stayed within trailing range of the player",
          npc and p and math.abs(npc.cellX - p.cellX)
                      + math.abs(npc.cellY - p.cellY) <= 2)
  end
  U.shot(game, SHOT_DIR .. "/bug863_route1_seam.png")

  local sfx = game.save.options and game.save.options.sfxVol
  if sfx == 0 then
    U.log("note: sfxVol is 0, Pikachu's steps and voice will be silent")
  end

  U.log(failures == 0 and "ALL PASS" or ("DONE " .. failures .. " check(s) failed"))
  love.event.quit(failures == 0 and 0 or 1)
  while true do coroutine.yield() end
end
