local U = require("tests.drivers.util")
local FixedStep = require("src.core.FixedStep")

local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/pokeport-shots"

return function(game)
  local failed = false
  local function expect(cond, label)
    print((cond and "PASS " or "FAIL ") .. label)
    if not cond then failed = true end
  end

  local pos
  local gen = "gen" .. tostring(require("src.core.GameVersion").generation())

  if gen == "gen1" then
    U.newGame(game)
    U.teleport(game, "PALLET_TOWN", 8, 6, "down")
    pos = function()
      local p = game.overworld and game.overworld.player
      return p and p.cellX, p and p.cellY
    end
  elseif gen == "gen2" then
    U.wait(60)
    if game.world and game.world.map then
      game.world:warpToMapId("NEW_BARK_TOWN", 5, 6, "down")
      U.wait(120)
    end
    pos = function()
      local p = game.world and game.world.player
      return p and p.cellX, p and p.cellY
    end
  else
    for _ = 1, 900 do
      if game.phase == "boot" and game.boot then break end
      U.wait(1)
    end
    game:_handleBootAction({ action = "new_game", name = "RED" })
    U.wait(240)
    pos = function()
      local s = game.session
      return s and s.x, s and s.y
    end
  end
  local x0, y0 = pos()
  expect(x0 ~= nil, gen .. "_2471_overworld_reached")
  if x0 == nil then love.event.quit(1) return end

  local counted = 0
  local orig = FixedStep.callback
  FixedStep.callback = function(dt)
    counted = counted + 1
    return orig(dt)
  end

  local function stepsPerUpdate(speed, updates)
    game.speedOverride = speed
    counted = 0
    for _ = 1, updates do game:update(1 / 60) end
    game.speedOverride = 1
    return counted / updates
  end

  local function walk(speed, dir, updates)
    local ax, ay = pos()
    game.speedOverride = speed
    for _ = 1, updates do
      table.insert(game.input.pressQueue, dir)
      game.input.state[dir] = true
      game:update(1 / 60)
    end
    game.input.state[dir] = false
    game.speedOverride = 1
    for _ = 1, 60 do game:update(1 / 60) end
    local bx, by = pos()
    return math.abs((bx or ax) - ax) + math.abs((by or ay) - ay)
  end

  local s10 = stepsPerUpdate(10, 30)
  local s200 = stepsPerUpdate(200, 30)
  print(("[2471] %s logic steps per rendered frame: 10X=%.1f 200X=%.1f"):format(gen, s10, s200))
  expect(math.abs(s10 - 10) < 0.5, gen .. "_2471_10x_runs_10_steps_a_frame")
  expect(s200 > 60, gen .. "_2471_200x_not_capped_at_15")

  local best, bestDir = -1, nil
  for _, dir in ipairs({ "left", "right", "down", "up" }) do
    local sx, sy = pos()
    local cells10 = walk(10, dir, 1)
    local back = ({ left = "right", right = "left", up = "down", down = "up" })[dir]
    for _ = 1, 120 do
      local cx, cy = pos()
      if cx == sx and cy == sy then break end
      walk(1, back, 1)
    end
    local cells200 = walk(200, dir, 1)
    print(("[2471] %s %s: 10X moved %d cells, 200X moved %d cells in one frame")
      :format(gen, dir, cells10, cells200))
    if cells200 - cells10 > best then best, bestDir = cells200 - cells10, dir end
    if cells200 >= 3 and cells200 > cells10 * 2 then break end
    for _ = 1, 200 do
      local cx, cy = pos()
      if cx == sx and cy == sy then break end
      walk(4, back, 1)
    end
  end
  expect(best >= 2, gen .. "_2471_200x_moves_more_cells_than_10x_" .. tostring(bestDir))
  FixedStep.callback = orig

  U.still(game, SHOT_DIR .. "/2471_" .. gen .. "_after_200x_frame.png")
  love.event.quit(failed and 1 or 0)
end
