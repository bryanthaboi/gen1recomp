-- #1718 / #1749: START while the Cycling Road rolls the bike downhill, and SURF
-- refused there.  Assertion driver -- every line it prints is PASS or FAIL.
-- Covers the halves tests/gen2_cycling_road_test.lua cannot: Game2's joypad
-- latch, which needs a real Input, and the A press at the water.
-- ../pokegold/maps/Route17.asm:11-16, engine/overworld/events.asm:193-231.
-- Never add POKEPORT_SPEED: which fixed step a press lands on IS the subject.
--
--   POKEPORT_IDENTITY=gold-dev POKEPORT_GAME=gold POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/gold_cycling_road_bug1718_1749_test.lua \
--     POKEPORT_SHOT_DIR=/tmp/gold-cycling-road \
--     perl -e 'alarm 240; exec @ARGV' \
--     python3 -c "import pty; pty.spawn(['love','.'])"
local U = require("tests.drivers.util")

local FieldMoves = require("src.world.gen2.FieldMoves")
local Mon = require("src.battle.gen2.Mon")
local Permissions = require("src.world.gen2.Permissions")
local Screens = require("src.ui.Screens")

-- The lane: x=9 is road, x=10 the water beside it, and Route 17's four bikers
-- stand at (4,17) (16,32) (3,53) (6,80) (../pokegold/maps/Route17.asm:147-150).
local ROAD = { map = "ROUTE_17", x = 9, y = 36 }
-- The control, a route with no ALWAYS_ON_BIKE on it: the shore south of the
-- Union Cave mouth (../pokegold/maps/Route32.asm:861 is the nearest object).
local SEA = { map = "ROUTE_32", x = 11, y = 41 }

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-cycling-road"
  local fails = 0

  local function report(ok, line)
    if not ok then fails = fails + 1 end
    U.log((ok and "PASS " or "FAIL ") .. line)
    return ok
  end

  U.wait(45)
  local world = game.world
  if not (world and world.map) then
    U.log("FAIL gold world did not boot; nothing below ran")
    while true do coroutine.yield() end
  end
  local save = game.save

  -- --------------------------------------------------------------- helpers

  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    U.wait(2)
    game.input.state[button] = false
    U.wait(frames or 6)
  end

  -- One edge then a sustained hold: re-queueing every frame would hand the
  -- gate a fresh edge on the landing tick and prove nothing.
  local function holdUntilMenu(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    local opened = false
    for _ = 1, frames do
      coroutine.yield()
      if game.stack:top() then opened = true break end
    end
    game.input.state[button] = false
    U.wait(2)
    return opened
  end

  local function tapAndRelease(button)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    coroutine.yield()
    game.input.state[button] = false
  end

  local function closeMenus()
    for _ = 1, 40 do
      if not game.stack:top() then return true end
      tap("b", 4)
    end
    return game.stack:top() == nil
  end

  local function dismiss()
    for _ = 1, 80 do
      if not (world.textbox or world.choicebox or world:busy()) then return true end
      if world.choicebox then tap("b", 4) else tap("a", 4) end
    end
    return not (world.textbox or world.choicebox)
  end

  -- Put the roll back at the top of the lane, standing, so every trial starts
  -- from the same step phase and none of them drifts into a biker.
  local function park(x, y, facing)
    local p = world.player
    p.moving = false
    p.progress = 0
    p.targetX, p.targetY = nil, nil
    p.turnTimer = 0
    p.cellX, p.cellY = x, y
    p.px, p.py = x * 16, y * 16
    p.facing = facing or "down"
    world.stepFinished = false
    world.heldDir = nil
  end

  -- ---- preflight: everything here fails the same silent way the bugs do ----

  local okScreen = pcall(Screens.get, game, "Gen2StartMenu")
  report(okScreen, "the Gen2StartMenu screen id resolves")

  local badges = save.player.badges or {}
  save.player.badges = badges
  badges[FieldMoves.BADGE.SURF] = true
  report(FieldMoves.hasBadge(save, FieldMoves.BADGE.SURF), "the FOGBADGE is on")

  local swimmer = Mon.new(game.data, "LAPRAS", 30, { moves = { { id = "SURF" } } })
  report(swimmer ~= nil, "the cache builds a LAPRAS")
  save.party = { swimmer }
  report(FieldMoves.partyMoveUser(save.party, "SURF") ~= nil,
    "and it knows SURF, so CheckPartyMove has a mon to find")

  report(world:setMap(ROAD.map, ROAD.x, ROAD.y, "down") ~= false,
    "ROUTE_17 loads")
  U.wait(10)
  report(world.map.id == ROAD.map, "and the world is on it")
  report(world:alwaysOnBike() == true,
    "MAPCALLBACK_NEWMAP set ALWAYS_ON_BIKE")
  report(world:downhill() == true, "and DOWNHILL")
  report(FieldMoves.isBiking(world.playerState),
    "CheckUpdatePlayerSprite put the player on the bike")

  for cy = ROAD.y, ROAD.y + 12 do
    local road = Permissions.isLand(world.map:cellCollision(ROAD.x, cy))
    local sea = Permissions.isWater(world.map:cellCollision(ROAD.x + 1, cy))
    if not (road and sea) then
      report(false, ("ROUTE_17 (%d,%d) is no longer road-beside-water")
        :format(ROAD.x, cy))
      break
    end
  end
  report(true, "the lane is road all the way down with water on its right")

  local clear = true
  for _, npc in ipairs(world.npcs or {}) do
    if npc.cellX == ROAD.x and npc.cellY >= ROAD.y - 2
        and npc.cellY <= ROAD.y + 14 then
      clear = false
    end
  end
  report(clear, "and no biker is parked in it")

  if fails > 0 then
    U.log("preflight failed -- the trials below would be measuring the setup,")
    U.log("not the fix. fix the lines above first.")
    while true do coroutine.yield() end
  end

  -- ---- #1718: the nine offsets in an 8-frame STEP_BIKE cell ---------------
  -- Offset 0 is the one tick the gate opens; 1..8 only the latch can carry.

  local opened = 0
  for offset = 0, 8 do
    park(ROAD.x, ROAD.y, "down")
    U.wait(offset)
    local moving = world.player.moving and "mid-step" or "standing"
    local ok = holdUntilMenu("start", 24)
    if ok then opened = opened + 1 end
    report(ok, ("START at offset %d (%s) opened the menu"):format(offset, moving))
    if offset == 4 then U.shot(game, out .. "/01-start-mid-roll.png") end
    closeMenus()
  end
  report(opened == 9, ("all nine offsets opened the menu (%d/9)"):format(opened))

  -- A press RELEASED inside the step is one the frozen mirror never sees again.
  park(ROAD.x, ROAD.y, "down")
  U.wait(3)
  report(world.player.moving == true, "three ticks in, the roll is mid-step")
  tapAndRelease("start")
  U.wait(24)
  report(game.stack:top() == nil,
    "a START tapped and released inside the step opens nothing")
  closeMenus()

  -- And the dropped press must not poison the latch for the next one.
  park(ROAD.x, ROAD.y, "down")
  U.wait(3)
  report(holdUntilMenu("start", 24),
    "the next held START still opens the menu")
  closeMenus()

  -- ---- #1749: SURF refused on the road ------------------------------------

  park(ROAD.x, ROAD.y, "down")
  -- Held RIGHT into the water the step is refused every tick, so the player
  -- stands facing the sea instead of rolling and an A press can land at all.
  game.input.pressQueue[#game.input.pressQueue + 1] = "right"
  game.input.state.right = true
  U.wait(20)
  report(world.player.facing == "right", "facing the water off the Cycling Road")
  report(world.player.moving == false, "and held there by the water it bumps")
  local ctx = world:fieldContext()
  report(Permissions.isWater(ctx.facingColl), "the faced cell really is water")
  report(ctx.alwaysOnBike == true,
    "and the field-move context carries ALWAYS_ON_BIKE (#1749)")
  U.shot(game, out .. "/02-road-facing-water.png")

  -- TrySurfOW's arm is `.quit`: xor a, no script, no text
  -- (engine/events/overworld.asm:513-515).  Pressed through the real Input.
  game.input.pressQueue[#game.input.pressQueue + 1] = "a"
  game.input.state.a = true
  U.wait(2)
  game.input.state.a = false
  U.wait(12)
  game.input.state.right = false
  report(world.textbox == nil, "A at the water put up no text box")
  report(world.queuedFieldMove == nil, "and queued no field move")
  report(FieldMoves.isBiking(world.playerState), "the player is still on the bike")

  -- SurfFunction.TrySurf's arm is .FailSurf, which TALKS
  -- (engine/events/overworld.asm:350-352, :387-390).  The world has to be idle
  -- first or useFieldMove answers CANT_USE_HERE off its own busy gate, which
  -- is a refusal for the wrong reason and would read as a pass.
  dismiss()
  report(not world:busy(), "the world is idle before the PACK's SURF is asked")
  local menu = world:useFieldMove("SURF", swimmer)
  report(menu and menu.ok == false, "the PACK's SURF refuses on the road")
  report(menu and menu.text == FieldMoves.TEXT.CANT_SURF,
    "with CantSurfText, not the badge line and not silence")
  U.wait(6)
  report(world.textbox ~= nil, "and the refusal is on screen")
  U.wait(70) -- let the line finish typing so the shot is readable
  U.shot(game, out .. "/03-road-cant-surf.png")
  dismiss()

  -- ---- the control: plain water, ALWAYS_ON_BIKE clear ---------------------

  report(world:setMap(SEA.map, SEA.x, SEA.y, "right") ~= false, "ROUTE_32 loads")
  U.wait(10)
  world:applyPlayerState(FieldMoves.PLAYER_NORMAL)
  report(world:alwaysOnBike() == false, "ROUTE_32 has no ALWAYS_ON_BIKE")
  local sea = world:fieldContext()
  report(sea.alwaysOnBike == false, "so the context reports it clear")
  report(Permissions.isWater(sea.facingColl), "and the player faces its water")

  local allowed = world:useFieldMove("SURF", swimmer)
  report(allowed and allowed.ok == true, "the PACK's SURF still works there")
  world.queuedFieldMove = nil

  tap("a", 10)
  report(world.textbox ~= nil or world.choicebox ~= nil,
    "and A at the water still offers to SURF")
  U.wait(70)
  U.shot(game, out .. "/04-route32-offer.png")
  dismiss()

  if fails == 0 then
    U.log("all trials passed. shots are in " .. out)
  else
    U.log(fails .. " trial(s) failed -- see the FAIL lines above")
  end
  U.log("what a wrong fix looks like: START opening the menu on roughly one")
  U.log("press in eight is the World half applied without the Game2 latch, and")
  U.log("a menu from the tapped-and-released press is the latch re-pressing a")
  U.log("button the player already let go of.")

  world:setMap(ROAD.map, ROAD.x, ROAD.y, "down")
  U.wait(10)
  U.log("parked back on the Cycling Road; the controls are yours from here")
  while true do
    coroutine.yield()
  end
end
