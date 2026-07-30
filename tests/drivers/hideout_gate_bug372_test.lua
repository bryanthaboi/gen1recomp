-- Driver: the Rocket Hideout B4F lift gate stays barred until both guards fall,
-- then opens on the spot (#372).  scripts/RocketHideoutB4F.asm ...DoorCallback-
-- Script stamps $2d at lb bc, 5, 12 until CheckBothEventsSet trainer_0/_1, then
-- SFX_GO_INSIDE and $e, and re-runs after a battle (home/trainers.asm
-- EndTrainerBattle).  Data half: tests/parity_hideout_gate.lua.  Never under
-- POKEPORT_SPEED: fast-forward desynchronizes the door sound from the stamp.
--   POKEPORT_DRIVER=tests/drivers/hideout_gate_bug372_test.lua POKEPORT_IDENTITY=bug372 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local FieldDefaults = require("src.world.FieldDefaults")

  local MAP = "ROCKET_HIDEOUT_B4F"
  local MAP_LABEL = "RocketHideoutB4F"
  local GUARD_0 = "EVENT_BEAT_ROCKET_HIDEOUT_4_TRAINER_0"
  local GUARD_1 = "EVENT_BEAT_ROCKET_HIDEOUT_4_TRAINER_1"
  -- data/generated/maps.lua ROCKET_HIDEOUT_B4F: the gate is block (12,5),
  -- i.e. cells (24-25, 10-11), the only gap in that wall row; the guards
  -- (data/maps/objects/RocketHideoutB4F.asm) sit at (23,12) and (26,12) and
  -- Giovanni at (25,3) with the SILPH SCOPE ball at (25,2) behind the gate.
  local DOOR = { bx = 12, by = 5 }
  local GATE_CELLS = { { 24, 11 }, { 25, 11 } }
  local STAND = { x = 24, y = 13, facing = "up" }

  local pass, fail = 0, 0
  local function check(label, ok)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  game.save.party = {
    Pokemon.new(game.data, "CHARIZARD", 40),
    Pokemon.new(game.data, "NIDOKING", 38),
  }
  game.save.player.name = "RED"
  -- a save that has been here before would already carry the guard events
  game.save.flags[GUARD_0] = nil
  game.save.flags[GUARD_1] = nil
  game.save.defeatedTrainers = {}

  local doors = FieldDefaults.fieldValue(game.data, "cardKeyDoors", "closedDoors")
  local row = doors and doors[MAP] and doors[MAP][1]
  check("the B4F gate has a closedDoors row (stale caches had none)", row ~= nil)
  if row then
    check("it stamps $2d over block (12,5)",
          row.block == 0x2d and row.bx == DOOR.bx and row.by == DOOR.by)
    check("it opens to $e on both guard events",
          row.open == 0x0e and row.events ~= nil and #row.events == 2)
  end
  check("B1F carries its own row ($54 at (12,8))",
        doors and doors.ROCKET_HIDEOUT_B1F ~= nil
        and doors.ROCKET_HIDEOUT_B1F[1].block == 0x54)
  check("the guards set the events the gate watches",
        game.data:trainerHeader(MAP_LABEL, 2).event == GUARD_0
        and game.data:trainerHeader(MAP_LABEL, 3).event == GUARD_1)
  check("Go_Inside is in the generated audio",
        game.data.audio and game.data.audio.sfx
        and game.data.audio.sfx.Go_Inside ~= nil)

  local vol = game.save.options and game.save.options.sfxVol
  if vol == 0 then
    U.log("sfxVol is 0: the door sound will be SILENT, raise it in OPTION first")
  else
    U.log("sfxVol", tostring(vol), "-- expect one door sound as the gate opens")
  end

  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(10)
  local ow = game.overworld

  -- a map edit or a mod moved the doorway: stand on any walkable cell
  -- touching the gate instead of the cell below it
  if not ow.map:isWalkableCell(STAND.x, STAND.y) then
    for _, cell in ipairs(GATE_CELLS) do
      for _, off in ipairs({ { 0, 1, "up" }, { 0, -1, "down" },
                            { 1, 0, "left" }, { -1, 0, "right" } }) do
        local cx, cy = cell[1] + off[1], cell[2] + off[2]
        if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
          U.log(("(%d,%d) is not walkable, standing on"):format(STAND.x, STAND.y),
                cx, cy, "facing", off[3])
          U.teleport(game, MAP, cx, cy, off[3])
          U.wait(10)
          ow = game.overworld
          break
        end
      end
    end
  end

  check("the doorway is stamped shut on arrival",
        ow.map:blockAt(DOOR.bx, DOOR.by) == 0x2d)
  local blocked = true
  for _, cell in ipairs(GATE_CELLS) do
    if ow.map:isWalkableCell(cell[1], cell[2]) then blocked = false end
  end
  check("neither doorway cell can be stepped into", blocked)

  local guards = 0
  for _, n in ipairs(ow.npcs or {}) do
    local name = n.def and n.def.name
    if name == "ROCKETHIDEOUTB4F_ROCKET1" or name == "ROCKETHIDEOUTB4F_ROCKET2" then
      guards = guards + 1
    end
  end
  check("both guards are on the floor", guards == 2)
  U.log(("machine checks: %d pass, %d fail"):format(pass, fail))

  U.shot(game, (os.getenv("SHOT_DIR") or "/tmp/shots") .. "/bug372_gate_shut.png")

  U.log("You are one cell south of the lift gate: barred, and walking up bumps.")
  U.log("Beat one grunt and it is still barred; beat the second and the bars turn")
  U.log("to floor as the fade ends, one door sound, then north to Giovanni.")

  while true do
    coroutine.yield()
  end
end
