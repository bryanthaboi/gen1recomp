-- pokeyellow home/overworld.asm:476,503,507
-- engine/pikachu/pikachu_follow.asm:59
--   POKEPORT_IDENTITY=yellow-sep04 POKEPORT_VERSION=yellow POKEPORT_TOUCH=0 \
--   POKEPORT_DRIVER=tests/drivers/pikachu_door_spawn_2197.lua \
--   POKEPORT_SHOT_DIR=/tmp/shots2197 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local GameVersion = require("src.core.GameVersion")
  local PF = require("src.world.PikachuFollower")
  local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR")
                   or "/tmp/shots"

  local failures = 0
  local function check(label, ok, extra)
    if not ok then failures = failures + 1 end
    U.log(ok and "PASS" or "FAIL", label, extra or "")
    return ok
  end

  local function finish()
    U.log(failures == 0 and "ALL PASS" or (failures .. " FAILURES"))
    love.event.quit(failures == 0 and 0 or 1)
    while true do coroutine.yield() end
  end

  if not check("running as Yellow (needs POKEPORT_VERSION=yellow)",
               GameVersion.isYellow()) then
    finish()
  end

  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true
  game.save.flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true
  game.save.flags.EVENT_FOLLOWED_OAK_INTO_LAB = true
  game.save.flags.EVENT_FOLLOWED_OAK_INTO_LAB_2 = true
  game.save.flags.EVENT_OAK_ASKED_TO_CHOOSE_MON = true
  game.save.flags.EVENT_GOT_POKEDEX = true
  game.save.pikachuInBall = false
  game.save.party = { Pokemon.new(game.data, "PIKACHU", 20) }
  game.save.onBike = false
  game.save.player.name = "bryan"

  local function warpCell(fromMap, destMap, destWarp)
    local def = game.data.maps[fromMap]
    for _, w in ipairs(def and def.warps or {}) do
      if w.destMap == destMap and (not destWarp or w.destWarp == destWarp) then
        return w.x, w.y
      end
    end
    return nil
  end

  local STEP_BACK = { right = { -1, 0 }, left = { 1, 0 },
                      up = { 0, 1 }, down = { 0, -1 } }

  local function settled(targetMap)
    local ow = game.overworld
    return ow and ow.map and ow.map.id == targetMap and not ow.transitioning
  end

  local function walkUntilMap(dir, targetMap, maxFrames)
    for _ = 1, maxFrames do
      local ow = game.overworld
      if ow and ow.map and ow.map.id == targetMap then break end
      table.insert(game.input.pressQueue, dir)
      game.input.state[dir] = true
      coroutine.yield()
    end
    game.input.state[dir] = false
    for _ = 1, 240 do
      if settled(targetMap) then break end
      coroutine.yield()
    end
    U.wait(40)
    return settled(targetMap)
  end

  local function doorCase(c)
    local from = c.from or game.overworld.map.id
    local wx, wy = warpCell(from, c.dest, c.destWarp)
    if not check(c.name .. ": found the warp to " .. c.dest, wx ~= nil) then
      return
    end
    local back = STEP_BACK[c.dir]
    local sx, sy = wx + back[1], wy + back[2]
    if c.from then
      U.teleport(game, c.from, sx, sy, c.dir)
    else
      local p = game.overworld.player
      p.cellX, p.cellY = sx, sy
      p.px, p.py = sx * 16, sy * 16
      p.facing = c.dir
    end
    U.wait(20)
    if not check(c.name .. ": walked into " .. c.target,
                 walkUntilMap(c.dir, c.target, 300),
                 "on " .. tostring(game.overworld.map.id) .. " at ("
                 .. game.overworld.player.cellX .. ","
                 .. game.overworld.player.cellY .. ")") then
      return
    end
    local ow = game.overworld
    local npc = PF.current(ow)
    local p = ow.player
    if not check(c.name .. ": the companion is on the new map", npc ~= nil) then
      return
    end
    local gx, gy = npc.cellX - p.cellX, npc.cellY - p.cellY
    check(c.name .. ": spawn cell delta is (" .. c.dx .. "," .. c.dy .. ")",
          gx == c.dx and gy == c.dy, "got (" .. gx .. "," .. gy .. ")")
    check(c.name .. ": spawn facing is " .. c.face, npc.facing == c.face,
          "got " .. tostring(npc.facing))
    U.shot(game, SHOT_DIR .. "/" .. c.shot)
  end

  doorCase({ name = "A route16 gate", from = "ROUTE_16",
             dest = "ROUTE_16_GATE_1F", destWarp = 5,
             target = "ROUTE_16_GATE_1F", dir = "right",
             dx = 0, dy = 1, face = "right",
             shot = "2197_01_route16_gate_below.png" })

  doorCase({ name = "B reds house", from = "PALLET_TOWN",
             dest = "REDS_HOUSE_1F", target = "REDS_HOUSE_1F", dir = "up",
             dx = 1, dy = 0, face = "up",
             shot = "2197_02_reds_house_right.png" })

  doorCase({ name = "C reds house stairs", dest = "REDS_HOUSE_2F",
             target = "REDS_HOUSE_2F", dir = "up", dx = 0, dy = 0,
             face = "up", shot = "2197_03_stairs_under_player.png" })

  doorCase({ name = "D back downstairs", dest = "REDS_HOUSE_1F",
             target = "REDS_HOUSE_1F", dir = "up", dx = 0, dy = 0,
             face = "up", shot = "2197_04_back_downstairs.png" })

  doorCase({ name = "E house exit mat", dest = "LAST_MAP",
             target = "PALLET_TOWN", dir = "down", dx = 0, dy = -1,
             face = "down", shot = "2197_05_exit_mat_back_outside.png" })

  doorCase({ name = "F oaks lab", from = "PALLET_TOWN", dest = "OAKS_LAB",
             target = "OAKS_LAB", dir = "up", dx = -1, dy = 0, face = "up",
             shot = "2197_06_oaks_lab_left.png" })

  finish()
end
