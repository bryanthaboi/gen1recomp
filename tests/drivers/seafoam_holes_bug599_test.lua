-- Eye/ear check that the Seafoam Islands floor holes drop the PLAYER, not just
-- the boulders (#599).  Each floor's script sets wDungeonWarpDestinationMap and
-- calls IsPlayerOnDungeonWarp over its SeafoamNHolesCoords list (pokered
-- scripts/SeafoamIslands1F.asm, B2F.asm); the landing cells come from
-- data/maps/special_warps.asm DungeonWarpData.  The data half is asserted in
-- tests/parity_seafoam_holes.lua.
--   POKEPORT_DRIVER=tests/drivers/seafoam_holes_bug599_test.lua POKEPORT_IDENTITY=bug599 POKEPORT_TOUCH=0 SHOT_DIR=/tmp/shots love .
-- No POKEPORT_SPEED: it scales the logic clock only while audio runs on its own
-- real-time accumulator in Game:update, so it desyncs the ordering being judged.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Sound = require("src.core.Sound")
  local Pokemon = require("src.pokemon.Pokemon")
  local mapScripts = require("data.scripts.init")

  -- Hole cells from pokered scripts/SeafoamIslands1F.asm Seafoam1HolesCoords
  -- (17,6)/(24,6) and scripts/SeafoamIslandsB2F.asm Seafoam3HolesCoords
  -- (19,6)/(22,6); the landings are the DungeonWarpData rows those floors
  -- index.  data/generated/maps.lua agrees: those four cells carry CAVERN $22
  -- and are walkable, which is why the fall is an onStep and not a collision.
  -- The B2F pair is here because its landing on B3F is water: the arrival has
  -- to come up already surfing, not standing on the sea.
  local FALLS = {
    { from = "SEAFOAM_ISLANDS_1F",  hx = 17, hy = 6,
      to = "SEAFOAM_ISLANDS_B1F",   lx = 18, ly = 7, water = false,
      shot = DIR .. "/bug599_1f_to_b1f.png" },
    { from = "SEAFOAM_ISLANDS_B2F", hx = 19, hy = 6,
      to = "SEAFOAM_ISLANDS_B3F",   lx = 18, ly = 7, water = true,
      shot = DIR .. "/bug599_b2f_to_b3f.png" },
  }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- ---- what the eye and the ear cannot check ------------------------------
  -- Silence is half the claim (a hole is not a door), and at SFX 0 a dead
  -- audio path and a fixed bug sound exactly alike.
  local opts = game.save.options or {}
  local sfxVol = opts.sfxVol or 7
  if sfxVol == 0 then
    U.log("FAIL SFX volume is 0, so the door chime this fall must NOT play")
    U.log("     could not play anyway. Set SFX to 7 in OPTION and rerun.")
  end
  check(("SFX volume %d"):format(sfxVol), sfxVol > 0)

  for _, f in ipairs(FALLS) do
    local hooks = mapScripts.get(f.from)
    check(f.from .. " has a hole onStep hook", hooks ~= nil and hooks.onStep ~= nil)
  end

  -- a party so a wild encounter on the B3F water is a battle to back out of
  -- rather than a blackout that throws the hand-off away
  if not game.save.party or #game.save.party == 0 then
    game.save.party = { Pokemon.new(game.data, "LAPRAS", 40),
                        Pokemon.new(game.data, "SNORLAX", 45) }
  end
  game.save.moveFlags = game.save.moveFlags or {}

  -- Every SFX cue raised during a fall.  Go_Inside / Go_Outside is the door
  -- chime WarpFound2 .indoorMaps skips for a warp pad or hole, and an ear can
  -- miss it under a fade if the fade happens to be busy.
  local cues, watching = {}, false
  local realPlay = Sound.play
  Sound.play = function(data, key, ...)
    if watching then cues[#cues + 1] = tostring(key) end
    return realPlay(data, key, ...)
  end

  -- Stand one cell south of the hole and walk north into it.  If a map edit
  -- moved the floor out from under that cell, fall back to any walkable
  -- neighbour that is not itself a hole, and walk from there instead.
  local SIDES = { { 0, 1, "up" }, { 0, -1, "down" },
                  { 1, 0, "left" }, { -1, 0, "right" } }

  local function standFor(f)
    local map = game.overworld and game.overworld.map
    local sameMap = map and map.id == f.from
    for _, s in ipairs(SIDES) do
      local cx, cy = f.hx + s[1], f.hy + s[2]
      local free = not sameMap
      if sameMap then
        free = map:isWalkableCell(cx, cy)
                 and (not map.warpPadOrHoleAt or map:warpPadOrHoleAt(cx, cy) ~= "hole")
      end
      if free then return cx, cy, s[3] end
    end
    return f.hx, f.hy + 1, "up"
  end

  local function runFall(f)
    -- teleport onto the floor first so the map is loaded and standFor can read
    -- its collision, then park on the approach cell that map actually offers
    U.teleport(game, f.from, f.hx, f.hy + 1, "up")
    U.wait(10)
    local sx, sy, dir = standFor(f)
    if sx ~= f.hx or sy ~= f.hy + 1 then
      U.log(("approach cell (%d, %d) is blocked, walking in from")
              :format(f.hx, f.hy + 1), sx, sy, "facing", dir)
      U.teleport(game, f.from, sx, sy, dir)
      U.wait(10)
    end
    local ow = game.overworld
    check(("standing on %s (%d, %d) facing %s"):format(f.from, sx, sy, dir),
          ow ~= nil and ow.map.id == f.from
            and ow.player.cellX == sx and ow.player.cellY == sy)
    check(("the hole at (%d, %d) is a walkable CAVERN tile, not a warp event")
            :format(f.hx, f.hy),
          ow ~= nil and ow.map:isWalkableCell(f.hx, f.hy)
            and ow.map:warpPadOrHoleAt(f.hx, f.hy) == "hole")

    cues, watching = {}, true
    U.hold(game, dir, 18)

    -- snapshot the very first frame the destination map is live: on B3F the
    -- current starts dragging the player the moment the step completes, so a
    -- later read would report where the water took them, not where they landed
    local landed
    for _ = 1, 300 do
      local o = game.overworld
      if o and o.map.id == f.to and not landed then
        landed = { x = o.player.cellX, y = o.player.cellY,
                   facing = o.player.facing, surfing = o.player.surfing }
      end
      if landed and not o.transitioning then break end
      U.wait(1)
    end
    -- spins the player down -- player_animations.asm:41-45
    local hidden = false
    for _ = 1, 200 do
      local o = game.overworld
      if o.holeArrive then hidden = hidden or o.playerHidden end
      if not (o.holeArrive or o.player.spinning) then break end
      U.wait(1)
    end
    U.wait(20)
    watching = false

    check("walking into the hole left " .. f.from, landed ~= nil)
    if not landed then
      U.log("     the player is still on", game.overworld and game.overworld.map.id)
      return
    end
    check(("landed on %s at (%d, %d), wanted (%d, %d)")
            :format(f.to, landed.x, landed.y, f.lx, f.ly),
          landed.x == f.lx and landed.y == f.ly)
    check("facing carried through the fall (" .. tostring(landed.facing) .. ")",
          landed.facing == dir)
    if f.water then
      -- the landing is sea, so setMap's CheckForceBikeOrSurf pass
      -- (OverworldState:checkForcedMovement) has to mount SURF on arrival
      check("arrived already surfing on the B3F water", landed.surfing == true)
    end
    local doors = {}
    for _, c in ipairs(cues) do
      if c == "Go_Inside" or c == "Go_Outside" then doors[#doors + 1] = c end
    end
    check("no door chime over the fall (heard: " ..
            (#cues > 0 and table.concat(cues, ", ") or "nothing") .. ")",
          #doors == 0)
    -- player_animations.asm:12
    local faint, enter = false, false
    for _, c in ipairs(cues) do
      if c == "Faint_Fall" then faint = true end
      if c == "Teleport_Enter1" then enter = true end
    end
    check("the departure is silent (no invented Faint_Fall)", not faint)
    check("the arrival rings Teleport_Enter1", enter)
    check("the player is parked offscreen through the 50-frame hold", hidden)
    U.shot(game, f.shot)
    U.log("captured", f.shot)
  end

  for _, f in ipairs(FALLS) do runFall(f) end

  Sound.play = realPlay

  -- hand back to real input on the 1F approach cell, one step short of the hole
  U.teleport(game, FALLS[1].from, FALLS[1].hx, FALLS[1].hy + 1, "up")
  U.wait(10)

  U.log("Both falls have already run; press up from where you are standing to")
  U.log("do the 1F one again. It should sink the sprite, fade to WHITE, hold")
  U.log("about a second on an empty B1F (18,7) with the player offscreen, ring")
  U.log("Teleport_Enter1 and spin him down into the cell still facing up -- no")
  U.log("faint sound, no door chime, and no")
  U.log("step out of a doorway on the far side. The near miss to watch for is")
  U.log("landing one cell off, on the boulder's own spot from field.seafoam")
  U.log("landsAt, which strands you inside the rock; and dropping onto the B3F")
  U.log("sea standing up instead of surfing, which shows as the player on top")
  U.log("of the water until the next step. The other three holes are 1F (24,6),")
  U.log("B1F (18,6)/(23,6) and B2F (22,6) if you want to walk the cascade down.")

  while true do
    coroutine.yield()
  end
end
