-- engine/pikachu/pikachu_follow.asm:1030
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local GameVersion = require("src.core.GameVersion")
  local NPC = require("src.world.NPC")
  local PF = require("src.world.PikachuFollower")
  local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local failures = 0

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    if not ok then failures = failures + 1 end
    return ok
  end

  check("running as Yellow", GameVersion.isYellow())

  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true
  game.save.flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true
  game.save.pikachuInBall = false
  game.save.party = { Pokemon.new(game.data, "PIKACHU", 20) }
  game.save.onBike = false

  local pikaDraws = 0
  local realDraw = NPC.draw
  NPC.draw = function(self, ...)
    if self.pikachuFollower then pikaDraws = pikaDraws + 1 end
    return realDraw(self, ...)
  end

  local function plain(map, x, y)
    return map:inBounds(x, y) and map:isWalkableCell(x, y)
       and not map:isGrassCell(x, y)
  end

  U.teleport(game, "ROUTE_1", 10, 20, "down")
  U.wait(5)
  local ow = game.overworld
  local sx, sy
  for y = 4, 30 do
    for x = 2, 16 do
      if not sx and plain(ow.map, x, y) and plain(ow.map, x, y + 1)
         and plain(ow.map, x, y + 2) and plain(ow.map, x - 1, y)
         and plain(ow.map, x + 1, y) then
        sx, sy = x, y
      end
    end
  end
  check("found an open Route 1 cell", sx ~= nil)
  sx, sy = sx or 10, sy or 20
  U.teleport(game, "ROUTE_1", sx, sy, "down")
  U.wait(30)
  ow = game.overworld

  local npc = PF.current(ow)
  local p = ow.player
  check("follower spawned on the Route 1 map load", npc ~= nil)
  check("spawn state 0 parks Pikachu on the player's cell",
        npc and npc.cellX == p.cellX and npc.cellY == p.cellY)

  pikaDraws = 0
  local shotOk = U.still(game, SHOT_DIR .. "/2846_01_route1_before_step.png")
  check("Pikachu is not drawn before the first step (draws=" .. pikaDraws .. ")",
        shotOk and pikaDraws == 0)

  U.hold(game, "down", 20)
  U.wait(20)
  npc = PF.current(ow)
  p = ow.player
  check("after one step Pikachu trails one cell behind",
        npc and p and npc.cellX == p.cellX and npc.cellY == p.cellY - 1)
  pikaDraws = 0
  shotOk = U.still(game, SHOT_DIR .. "/2846_02_route1_after_step.png")
  check("Pikachu is drawn after the first step (draws=" .. pikaDraws .. ")",
        shotOk and pikaDraws > 0)

  NPC.draw = realDraw
  U.log(failures == 0 and "PASS all" or ("FAIL " .. failures .. " check(s)"))
  love.event.quit(failures == 0 and 0 or 1)
end
