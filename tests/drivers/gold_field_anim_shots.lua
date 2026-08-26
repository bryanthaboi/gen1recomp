-- The field presentations a test cannot see, through the real world:
-- teleport_from's spin-and-rise, the fishing rod bob, the headbutt tree shake,
-- FLY's take-off lift, and FLY's own destination picker.
--
--   POKEPORT_IDENTITY=gold-dev POKEPORT_GAME=gold \
--     POKEPORT_DRIVER=tests/drivers/gold_field_anim_shots.lua love .
--   POKEPORT_SHOT_DIR=/tmp/gold-field   (default)
--
-- Every beat is asserted as well as shot, so a run that only prints PASS is
-- still worth something on a machine nobody is looking at.
local U = require("tests.drivers.util")

local FieldMoves = require("src.world.gen2.FieldMoves")
local Movement = require("src.script.gen2.Movement")
local Pokegear = require("src.ui.gen2.Pokegear")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-field"
  local failures = 0

  local function ok(label, condition, detail)
    if condition then
      print("[field] ok   " .. label)
    else
      failures = failures + 1
      print("[field] FAIL " .. label .. " " .. tostring(detail))
    end
  end

  U.wait(45)
  local world = game.world
  assert(world and world.map, "gold world did not boot")

  world:setMap("ROUTE_30", 10, 10, "down")
  U.wait(10)

  -- ------------------------------------------------------------- teleport
  --
  -- LakeOfRageLanceTeleportIntoSkyMovement is `teleport_from / step_end`:
  -- StepFunction_TeleportFrom spins the object for sixteen frames and then
  -- lifts it off the tile over sixteen more.  The byte used to decode as a nop,
  -- so Lance simply blinked out.
  local npc = world.npcs and world.npcs[1]
  -- applymovement's operand is the object_const_def index, which starts at 2
  -- (World:objectEntity takes it back off), not the pooled NPC's own id.
  local objectId = npc and npc.def and npc.def.index and (npc.def.index + 1)
  if npc and objectId then
    local finished = false
    world:beginMovement(objectId,
      { Movement.TELEPORT_FROM, Movement.STEP_END },
      function() finished = true end)
    local facings, deepest = {}, 0
    for frame = 1, 34 do
      U.wait(1)
      facings[npc.facing] = true
      deepest = math.min(deepest, npc.spriteYOffset or 0)
      if frame == 20 then U.shot(game, out .. "/01-teleport-spin.png") end
      if frame == 30 then U.shot(game, out .. "/02-teleport-rise.png") end
    end
    ok("teleport_from spins the object",
      facings.up and facings.down and facings.left and facings.right)
    ok("and lifts it off its tile", deepest <= -0x50, deepest)
    ok("and the movement stream waits it out", finished)
    ok("and the object never left its cell", npc.spriteYOffset == 0)
  else
    print("[field] SKIP teleport: no object on this map")
  end

  -- ------------------------------------------------------------- fishing
  --
  -- Script_GotABite's four fish_got_bite bobs: StepFunction_GotBite flips
  -- OBJECT_SPRITE_Y_OFFSET between 0 and 1 once a frame.
  local Mon = require("src.battle.gen2.Mon")
  local wild = Mon.new(game.data, "MAGIKARP", 10)
  world:beginFishing("battle", wild)
  local offsets = {}
  for frame = 1, 90 do
    U.wait(1)
    offsets[world.player.spriteYOffset or 0] = true
    if frame == 40 then U.shot(game, out .. "/03-fishing.png") end
    if world.textbox then break end
  end
  ok("the rod bobs the player one pixel", offsets[1] == true)
  world.fishing = nil
  world.player.spriteYOffset = 0
  U.wait(5)
  while game.stack:top() do game.stack:pop() end
  U.wait(5)

  -- ------------------------------------------------------------- headbutt
  --
  -- ShakeHeadbuttTree runs a 32-frame wobble under SFX_SANDSTORM.
  world:runHeadbutt(10, 9, { species = "SPEAROW", nickname = "SPEAROW" })
  U.wait(2)
  -- The line is a text box; A takes it down and the shake starts on its close.
  for _ = 1, 20 do
    if world.headbutt then break end
    U.tap(game, "a")
    U.wait(2)
  end
  ok("the headbutt shake is armed", world.headbutt ~= nil)
  ok("and the frame shakes with it", world.shake ~= nil)
  U.wait(4)
  U.shot(game, out .. "/04-headbutt.png")
  for _ = 1, 120 do
    if not world.headbutt then break end
    U.tap(game, "a")
    U.wait(2)
  end
  while game.stack:top() do game.stack:pop() end
  U.wait(5)

  -- ------------------------------------------------------------- fly
  --
  -- Every flypoint visited, so the picker has a full map to walk.
  local save = game.save
  save.engineFlags = save.engineFlags or {}
  for _, row in ipairs(FieldMoves.FLYPOINTS) do
    save.engineFlags[row.flag] = true
  end
  -- The mon that used the move: FlyFunction_InitGFX and TownMapMon both draw
  -- wCurPartyMon's icon (engine/events/field_moves.asm:390).
  local flyMon = (save.party and save.party[1]) or { species = "PIDGEY" }
  ok("openFlyMap opens a screen", world:openFlyMap(flyMon) == true)
  U.wait(4)
  local picker = game.stack:top()
  ok("and it is the town-map picker, not a yes/no box",
    getmetatable(picker) == Pokegear and picker.fly ~= nil)
  ok("with the cursor on a flypoint",
    picker and picker.flyRow and picker:flyRow() ~= nil)
  U.shot(game, out .. "/05-flymap.png")
  U.tap(game, "up")
  U.wait(4)
  U.shot(game, out .. "/06-flymap-moved.png")

  -- A takes the destination: FlyFromAnim hovers over the tile for 64 frames,
  -- climbs off the top of the screen, and FlyToAnim drops back in after the warp.
  U.tap(game, "a")
  U.wait(4)
  ok("FLY starts the take-off animation", world.flyAnim ~= nil)
  U.shot(game, out .. "/07-fly-takeoff.png")
  local risen, landing = 0, false
  for _ = 1, 300 do
    U.wait(1)
    local fa = world.flyAnim
    if fa then
      risen = math.min(risen, fa.y or 0)
      if fa.phase == "to" then landing = true end
    elseif landing then
      break
    end
  end
  ok("the mon climbs off the map", risen < 0, risen)
  ok("and FlyToAnim brings it back down", landing)
  ok("with the player standing again", world.flyAnim == nil)
  U.shot(game, out .. "/08-fly-landed.png")

  -- --------------------------------------------------- tilt and the void
  --
  -- Zoomed out with TILT on is where both nitpicks live: the billboard clip
  -- (no NPCs standing past where the ground is drawn) and the border-block
  -- dissolve across a map boundary.
  local Tilt = require("src.render.Tilt")
  local Zoom = require("src.render.Zoom")
  Zoom.offset = -3
  world:rebuildNeighbors()
  world:rebuildPeople({ seamless = true })
  Tilt.setLevel(3)
  for _ = 1, 40 do
    Tilt.update(1 / 60)
    U.wait(1)
  end
  U.shot(game, out .. "/09-tilt-survey.png")
  -- Cross into the next map: the void fill dissolves from one border block to
  -- the other rather than cutting.
  world:setMap("ROUTE_31", 10, 10, "down")
  U.wait(2)
  U.shot(game, out .. "/10-void-crossfade.png")
  U.wait(10)
  U.shot(game, out .. "/11-void-settled.png")
  ok("the border fill is mid-dissolve on arrival",
    world.borderFade == nil or world.borderFade >= 1)
  Tilt.setLevel(0)
  Zoom.offset = 0

  if failures > 0 then
    print(("[driver] FAIL gold field anims: %d check(s)"):format(failures))
    return
  end
  print("[driver] PASS gold field anims in " .. out)
end
