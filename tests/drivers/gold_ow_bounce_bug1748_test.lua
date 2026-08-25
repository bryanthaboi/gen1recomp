-- #1748: overworld Pokemon objects (SPRITEMOVEDATA_POKEMON, $16) never bounce.
--
--   POKEPORT_IDENTITY=gold-dev POKEPORT_GAME=gold POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/gold_ow_bounce_bug1748_test.lua \
--     POKEPORT_SHOT_DIR=/tmp/gold-bounce \
--     perl -e 'alarm 240; exec @ARGV' \
--     python3 -c "import pty; pty.spawn(['love','.'])"
--
-- The $16 row is SPRITEMOVEFN_BOUNCE + OBJECT_ACTION_BOUNCE
-- (data/sprites/map_objects.asm:181-187).  SetFacingBounce steps
-- OBJECT_STEP_FRAME once a frame and reads bit 3, swapping FACING_STEP_DOWN_0
-- for FACING_STEP_UP_0 -- eight frames on each (map_object_action.asm:184-202).
-- Its frozen column, SetFacingFreezeBounce, pins FACING_STEP_DOWN_0.
--
-- No POKEPORT_SPEED here on purpose: an eight-frame dwell is the whole thing
-- being watched, and fast-forward scales only the logic clock.
local U = require("tests.drivers.util")

local NPC = require("src.world.gen2.Npc")

-- ../pokegold/maps/PokemonFanClub.asm:311-316 -- the bouncing SPRITE_ODDISH at
-- (7,3) shares the room with a SPRITE_FAIRY doll at (2,4) on
-- SPRITEMOVEDATA_STANDING_DOWN, which is the negative control standing next to
-- it.  ../pokegold/maps/PewterPokecenter1F.asm is the reporter's own room.
local ROOM = { map = "POKEMON_FAN_CLUB", x = 7, y = 3 }
local PEWTER = { map = "PEWTER_POKECENTER_1F", x = 1, y = 3 }

local SPRITEMOVEDATA_POKEMON = 0x16
local DELTA = {
  up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 },
}
local FACE_FROM = { up = "down", down = "up", left = "right", right = "left" }

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-bounce"
  local fails, lines = 0, {}

  local function claim(ok, text)
    if not ok then fails = fails + 1 end
    lines[#lines + 1] = (ok and "PASS " or "FAIL ") .. text
    return ok
  end

  local function stop(why)
    for _, line in ipairs(lines) do U.log(line) end
    U.log(why)
    while true do coroutine.yield() end
  end

  U.wait(45)
  local world = game.world
  if not (world and world.map) then
    U.log("FAIL the gold world never booted, nothing to look at")
    while true do coroutine.yield() end
  end

  -- ---- the things a human's eyes cannot check ------------------------------
  --
  -- Every one of these fails as silence: a missing movement byte, a sheet with
  -- no second frame and a doll that quietly took the animation all look exactly
  -- like "the object sits there", which is also what the bug looked like.
  claim(NPC.MOVE.POKEMON == SPRITEMOVEDATA_POKEMON,
    "SPRITEMOVEDATA_POKEMON is modelled as $16")
  claim(type(NPC.bounceFrame) == "function",
    "NPC:bounceFrame exists for the draw call to spend")

  local function findObject(mapId, x, y)
    local def = world.maps[mapId]
    if not def then return nil end
    local exact, any
    for _, obj in ipairs(def.objects or {}) do
      if obj.movement == SPRITEMOVEDATA_POKEMON then
        any = any or obj
        if obj.x == x and obj.y == y then exact = obj end
      end
    end
    return exact or any
  end

  local monDef = findObject(ROOM.map, ROOM.x, ROOM.y)
  claim(monDef ~= nil,
    ("%s still carries a $16 object"):format(ROOM.map))
  if not monDef then
    stop("no bouncing object on the map; stopping rather than faking the moment")
  end
  if monDef.x ~= ROOM.x or monDef.y ~= ROOM.y then
    U.log(("note: using the mon at (%d,%d), not the (%d,%d) in the header")
      :format(monDef.x, monDef.y, ROOM.x, ROOM.y))
  end

  local sheet = type(monDef.sprite) == "string"
    and world.sprites and world.sprites[monDef.sprite]
  claim(sheet ~= nil,
    ("its sprite %s resolves to a sheet"):format(tostring(monDef.sprite)))
  claim(sheet and (sheet.frames or 1) >= 2,
    ("and that sheet is two frames deep (frames = %s) -- one frame is the half"
      .. " of #1748 a re-import fixes"):format(sheet and tostring(sheet.frames)))
  claim(world.scripts and world.scripts[monDef.scriptKey] ~= nil,
    ("its script %s is in the cache, so the A press below opens a box")
      :format(tostring(monDef.scriptKey)))

  -- ---- walk in and stand in front of it ------------------------------------
  world:setMap(ROOM.map, monDef.x, monDef.y + 1, "up")
  U.wait(20)
  local map = world.map

  -- Stand on the mon's neighbour and face back at it; any free neighbour will
  -- do, so a re-import that shuffles the room degrades instead of parking the
  -- player at a wall.
  local spot
  for _, dir in ipairs({ "down", "left", "right", "up" }) do
    local d = DELTA[dir]
    local x, y = monDef.x + d[1], monDef.y + d[2]
    if not spot and map:isWalkable(x, y) then
      spot = { x = x, y = y, facing = FACE_FROM[dir] }
    end
  end
  claim(spot ~= nil, "there is a free cell beside it to stand on")
  if not spot then
    stop("nowhere to stand; stopping rather than parking the player at a wall")
  end
  world:setMap(ROOM.map, spot.x, spot.y, spot.facing)
  U.wait(20)

  local mon, dolls = nil, {}
  for _, npc in ipairs(world.npcs or {}) do
    if npc.def == monDef then mon = npc
    elseif npc.def and npc.def.movement ~= SPRITEMOVEDATA_POKEMON then
      dolls[#dolls + 1] = npc
    end
  end
  claim(mon ~= nil, "the object spawned as an NPC")
  if not mon then stop("the mon never spawned; nothing to watch") end
  claim(mon.bouncing == true, "and it spawned bouncing")

  local stillBouncers = 0
  for _, npc in ipairs(dolls) do
    if npc.bouncing then stillBouncers = stillBouncers + 1 end
  end
  claim(stillBouncers == 0,
    ("none of the %d other objects in the room bounce -- the Clefairy doll"
      .. " beside it must not move"):format(#dolls))

  -- ---- the cycle, measured on the logic clock ------------------------------
  -- One sample per frame, and the run lengths are what SetFacingBounce's bit 3
  -- decides.  Measured rather than eyeballed because four flips a second is
  -- exactly the rate a human reads as "about right" when it is wrong.
  local samples = {}
  for i = 1, 96 do
    samples[i] = mon:bounceFrame()
    coroutine.yield()
  end
  local runs, values = {}, {}
  for i = 1, #samples do
    if i > 1 and samples[i] == samples[i - 1] then
      runs[#runs] = runs[#runs] + 1
    else
      runs[#runs + 1] = 1
      values[#values + 1] = samples[i]
    end
  end
  claim(#runs >= 5, ("the pose changed %d times in 96 frames"):format(#runs - 1))
  local alternates, dwell, uneven = true, nil, nil
  for i = 2, #runs - 1 do
    dwell = dwell or runs[i]
    if runs[i] ~= dwell then uneven = uneven or runs[i] end
    if values[i] == values[i - 1] then alternates = false end
  end
  claim(alternates and values[1] ~= nil,
    "it alternates between two poses and only two")
  claim(uneven == nil, ("every whole dwell is the same length"
    .. (uneven and (" -- saw %d and %d"):format(dwell or 0, uneven) or "")))
  claim(dwell == 8, ("and it is the eight frames bit 3 buys (measured %s)")
    :format(tostring(dwell)))

  -- ---- what the renderer was actually handed -------------------------------
  -- A bounce the draw call drops looks exactly like no bounce, and a doll that
  -- picked the override up is the other way to pass this by accident.
  local seen, watched = {}, { { key = "mon", npc = mon } }
  for i, npc in ipairs(dolls) do
    watched[#watched + 1] = { key = "doll" .. i, npc = npc }
  end
  for _, row in ipairs(watched) do
    local sprite = row.npc.sprite
    row.sprite, row.real = sprite, sprite.draw
    seen[row.key] = {}
    sprite.draw = function(s, ...)
      local args = { ... }
      local log = seen[row.key]
      -- "none" rather than a hole, so a sprite that was never drawn at all is
      -- not mistaken for one that was drawn with no override.
      log[#log + 1] = args[10] == nil and "none" or args[10]
      return row.real(s, ...)
    end
  end
  U.wait(40)
  for _, row in ipairs(watched) do row.sprite.draw = row.real end

  local monPoses = {}
  for _, v in ipairs(seen.mon) do monPoses[v] = true end
  claim(#seen.mon > 0, "the mon was drawn")
  claim(monPoses[0] and monPoses[1],
    "and both icon frames reached SpriteRenderer over 40 frames")
  local dollDraws, dollOverrides = 0, 0
  for i = 1, #dolls do
    for _, v in ipairs(seen["doll" .. i] or {}) do
      dollDraws = dollDraws + 1
      if v ~= "none" then dollOverrides = dollOverrides + 1 end
    end
  end
  claim(dollDraws > 0, ("the other %d objects were drawn too"):format(#dolls))
  claim(dollOverrides == 0, "and not one of them was handed a frame override")

  -- ---- the pair of shots ---------------------------------------------------
  -- The counter is held while each capture lands so the file is definitely one
  -- pose rather than whichever the spin drifted onto; the cycle above is what
  -- proves it runs on its own.
  local function holdShot(path, step)
    os.execute('mkdir -p "' .. path:match("^(.*)/[^/]+$") .. '" 2>/dev/null')
    game.capturePath = path
    for _ = 1, 120 do
      mon.bounceStep = step
      if not game.capturePath then break end
      coroutine.yield()
    end
    mon.bounceStep = step
    coroutine.yield()
    local f = io.open(path, "rb")
    if not f then return nil end
    local bytes = f:read("*a")
    f:close()
    return bytes
  end

  local down = holdShot(out .. "/01-pose-down.png", 0)
  local up = holdShot(out .. "/02-pose-up.png", 8)
  claim(down ~= nil and up ~= nil, "both pose shots reached disk")
  claim(down and up and down ~= up,
    "and the two files differ, so the screen really changes between poses")

  -- ---- talking to it holds the first pose ----------------------------------
  -- OBJECT_ACTION_BOUNCE's frozen column is SetFacingFreezeBounce, which writes
  -- FACING_STEP_DOWN_0 and never touches the counter.
  mon.bounceStep = 12
  local phaseBefore = mon.bounceStep
  U.tap(game, "a")
  U.wait(30)
  claim(world.talkNpc == mon or mon.frozen,
    "the A press reached the mon and froze it")
  local heldWrong = nil
  for _ = 1, 60 do
    if mon:bounceFrame() ~= 0 then heldWrong = mon:bounceFrame() end
    coroutine.yield()
  end
  claim(heldWrong == nil,
    "and it holds its first pose for the whole conversation")
  claim(mon.bounceStep == phaseBefore,
    ("with the step counter left at %d, so the bounce resumes on the phase it"
      .. " froze at (it is %s)"):format(phaseBefore, tostring(mon.bounceStep)))
  U.shot(game, out .. "/03-frozen-talking.png")

  U.tap(game, "a")
  U.wait(40)
  U.tap(game, "a")
  U.wait(40)

  -- ---- the reporter's own room ---------------------------------------------
  local pewterDef = findObject(PEWTER.map, PEWTER.x, PEWTER.y)
  if not pewterDef then
    U.log("note: no $16 object on " .. PEWTER.map .. ", skipping its shots")
  else
    world:setMap(PEWTER.map, pewterDef.x, pewterDef.y + 2, "up")
    U.wait(30)
    local jiggly
    for _, npc in ipairs(world.npcs or {}) do
      if npc.def == pewterDef then jiggly = npc end
    end
    claim(jiggly ~= nil and jiggly.bouncing == true,
      ("the %s at (%d,%d) bounces too"):format(PEWTER.map,
        pewterDef.x, pewterDef.y))
    if jiggly then
      local a, b
      local function pin(path, step)
        os.execute('mkdir -p "' .. path:match("^(.*)/[^/]+$") .. '" 2>/dev/null')
        game.capturePath = path
        for _ = 1, 120 do
          jiggly.bounceStep = step
          if not game.capturePath then break end
          coroutine.yield()
        end
        coroutine.yield()
        local f = io.open(path, "rb")
        if not f then return nil end
        local bytes = f:read("*a")
        f:close()
        return bytes
      end
      a = pin(out .. "/04-pewter-down.png", 0)
      b = pin(out .. "/05-pewter-up.png", 8)
      claim(a ~= nil and b ~= nil and a ~= b,
        "and its two pose shots differ as well")
    end
  end

  for _, line in ipairs(lines) do U.log(line) end
  U.log(("%d checks, %d failed"):format(#lines, fails))
  if fails > 0 then
    U.log("something above says FAIL, so do not spend time watching the room.")
  end

  -- ---- what to look at -----------------------------------------------------
  U.log("shots are in " .. out .. ". 01 and 02 are the two poses of the same")
  U.log("mon; they should look like the two halves of its party menu icon,")
  U.log("the second one sitting a pixel or two differently. 03 is the same mon")
  U.log("mid-conversation, which must match 01.")
  U.log("")
  U.log("the run ends back in the Fan Club with the Oddish on screen at (7,3).")
  U.log("it should visibly flip between its two icon poses about four times a")
  U.log("second, without moving off its tile or turning to face anything.")
  U.log("the Clefairy doll at (2,4) and the people in the room must stay dead")
  U.log("still: a doll that bobs means the bounce got keyed off the sprite")
  U.log("instead of the movement byte. a mon that keeps bobbing while its text")
  U.log("box is open is the other near miss -- it must hold one pose there and")
  U.log("pick the cycle back up where it left off when the box closes.")

  world:setMap(ROOM.map, spot.x, spot.y, spot.facing)
  while true do coroutine.yield() end
end
