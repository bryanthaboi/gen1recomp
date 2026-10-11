-- home/overworld.asm:180-200
-- home/overworld.asm:1234-1258
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local GameVersion = require("src.core.GameVersion")
  local Pokemon = require("src.pokemon.Pokemon")
  local Sound = require("src.core.Sound")

  local failures = 0
  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    if not ok then failures = failures + 1 end
    return ok
  end
  local function finish()
    U.log(failures == 0 and "DONE all checks passed"
                        or ("DONE " .. failures .. " check(s) failed"))
    love.event.quit(failures == 0 and 0 or 1)
    while true do coroutine.yield() end
  end

  if not check("running Yellow", GameVersion.isYellow()) then finish() end

  local bumps = {}
  local realPlay = Sound.play
  Sound.play = function(data, name, ...)
    if name == "Collision" then bumps[#bumps + 1] = U.frame() end
    return realPlay(data, name, ...)
  end

  game.save.party = { Pokemon.new(game.data, "PIKACHU", 12) }
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true
  game.save.flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true
  game.save.repelSteps = 9999

  U.teleport(game, "ROUTE_1", 8, 20, "down")
  U.wait(30)
  local ow = game.overworld
  if not check("Route 1 loaded", ow and ow.map and ow.map.id == "ROUTE_1") then finish() end
  ow.rollEncounter = function() return nil end

  local function follower()
    for _, n in ipairs(ow.npcs or {}) do
      if n.pikachuFollower then return n end
    end
  end

  local function step(dir)
    local p = ow.player
    local sx, sy = p.cellX, p.cellY
    for _ = 1, 60 do
      game.input.state[dir] = true
      table.insert(game.input.pressQueue, dir)
      U.wait(1)
      if p.cellX ~= sx or p.cellY ~= sy then break end
    end
    game.input.state[dir] = false
    for _ = 1, 40 do
      if not p.moving then break end
      U.wait(1)
    end
    U.wait(20)
  end

  local function behind()
    local p, npc = ow.player, follower()
    if not npc then return nil end
    if npc.cellX == p.cellX and npc.cellY == p.cellY + 1 then return "down" end
    if npc.cellX == p.cellX and npc.cellY == p.cellY - 1 then return "up" end
    if npc.cellY == p.cellY and npc.cellX == p.cellX + 1 then return "right" end
    if npc.cellY == p.cellY and npc.cellX == p.cellX - 1 then return "left" end
  end

  local function turnInto(label, holdFrames)
    local dir = behind()
    if not check(label .. ": companion trails directly behind", dir ~= nil) then return end
    local p = ow.player
    U.log(label, "player", p.cellX, p.cellY, p.facing, "push", dir)
    bumps = {}
    local t0 = U.frame()
    for _ = 1, holdFrames do
      game.input.state[dir] = true
      table.insert(game.input.pressQueue, dir)
      U.wait(1)
    end
    game.input.state[dir] = false
    U.wait(30)
    U.log(label, "bumps", #bumps, bumps[1] and (bumps[1] - t0) or "-")
    check(label .. ": turning into the companion plays SFX_COLLISION", #bumps >= 1)
  end

  step("down")
  step("down")
  turnInto("standing after walking down, held turn", 20)

  step("down")
  step("down")
  turnInto("standing after walking down, tap turn", 6)

  step("left")
  step("left")
  turnInto("standing after walking left", 20)

  step("right")
  step("right")
  turnInto("standing after walking right", 20)

  step("up")
  step("up")
  turnInto("standing after walking up", 20)

  step("up")
  step("up")
  local back = behind()
  turnInto("first tap turn into the companion", 6)
  local away = ({ up = "down", down = "up", left = "right", right = "left" })[back]
  U.hold(game, away, 6)
  U.wait(60)
  check("turned away again with the companion still behind", behind() == back)
  turnInto("second tap turn after facing away", 6)

  finish()
end
