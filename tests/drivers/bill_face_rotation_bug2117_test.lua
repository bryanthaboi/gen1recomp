-- (engine/overworld/movement.asm:151)
--   SHOT_DIR=/tmp/shots POKEPORT_VERSION=red \
--     POKEPORT_DRIVER=tests/drivers/bill_face_rotation_bug2117_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")

  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local function idle()
    while true do coroutine.yield() end
  end

  local MAP, STAND = "BILLS_HOUSE", { x = 1, y = 5, facing = "up" }

  game.save.party = { Pokemon.new(game.data, "PIKACHU", 12) }
  game.save.player.name = "bryan"
  game.save.options = game.save.options or {}
  game.save.options.textSpeed = 1
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true
  game.save.flags.EVENT_BILL_SAID_USE_CELL_SEPARATOR = nil
  game.save.flags.EVENT_MET_BILL = nil
  game.save.flags.EVENT_MET_BILL_2 = nil

  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(20)

  local ow = game.overworld
  if not check("Bill's House loaded", ow ~= nil and ow.map
               and ow.map.id == MAP) then
    idle()
  end

  local monster
  for _, npc in ipairs(ow.npcs or {}) do
    if npc.def and npc.def.sprite == "SPRITE_MONSTER" then monster = npc end
  end
  if not check("the monster form is on the map", monster ~= nil) then idle() end
  check("it is a STAY, NONE object",
        monster.def.movement == "STAY" and monster.def.range == "NONE")
  check("it rolls a facing but never steps",
        monster.wanders == true and monster.steps == false)

  local seen, order = {}, {}
  local startX, startY = monster.cellX, monster.cellY
  local moved = false
  for frame = 0, 600 do
    if not seen[monster.facing] then
      seen[monster.facing] = true
      order[#order + 1] = monster.facing
    end
    if monster.cellX ~= startX or monster.cellY ~= startY then moved = true end
    if frame % 60 == 0 then
      U.shot(game, SHOT_DIR .. "/bill_face_" .. frame .. ".png")
    end
    U.wait(1)
  end

  check("Bill takes more than one facing over 600 frames: "
        .. table.concat(order, ","), #order >= 2)
  check("and never leaves his cell", not moved)
  U.log("shots in", SHOT_DIR)

  idle()
end
