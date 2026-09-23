local U = require("tests.drivers.util")

local failed = false
local function check(label, cond, detail)
  print((cond and "PASS " or "FAIL ") .. label .. (detail and (" " .. detail) or ""))
  if not cond then failed = true end
end

local STRIDE = {
  down = { [10] = true, [11] = true },
  up = { [13] = true, [14] = true },
  left = { [16] = true, [17] = true },
  right = { [16] = true, [17] = true },
}

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)
  local ok, err = pcall(function()
    local Map = require("src.core.game3.map")
    local Player = require("src.core.game3.player")
    local Space = require("src.core.game3.scripting.space")
    local Flags = require("src.core.game3.scripting.flags")
    local OwSprites = require("src.core.game3.ow_sprites")
    Map.load(nil, game, "FR_ROUTE_1", { x = 11, y = 20, facing = "down" })
    U.wait(60)
    Flags.setFlag(Space.getStore(), nil, Flags.IDS.SYS_B_DASH, true)

    local drawn = {}
    local origPose = OwSprites.pose
    OwSprites.pose = function(spr, facing, walkPhase, stepFlip, opts)
      local f, flip = origPose(spr, facing, walkPhase, stepFlip, opts)
      if opts and opts.running ~= nil then drawn[#drawn + 1] = { f = f, facing = facing } end
      return f, flip
    end

    local dirs = { "down", "up", "left", "right" }
    for _, dir in ipairs(dirs) do
      Map.load(nil, game, "FR_ROUTE_1", { x = 11, y = dir == "right" and 21 or 20, facing = "down" })
      U.wait(30)
      game.input.state.b = true
      local ready = false
      for _ = 1, 240 do
        game.input.state[dir] = true
        table.insert(game.input.pressQueue, dir)
        coroutine.yield()
        if Player.moving and Player.running and Player.facing == dir
            and Player.animClock == 5 and Player.runPose() == 0 then
          ready = true
          break
        end
      end
      check("run_step_started_" .. dir, ready)
      for _ = 1, 3 do
        if Player.runPose() == 1 then break end
        coroutine.yield()
      end
      local strideClock = Player.animClock
      local origTick = Player.tick
      Player.tick = function() return false end
      for k in pairs(drawn) do drawn[k] = nil end
      local dirShot = os.getenv("POKEPORT_SHOT_DIR")
      if dirShot and dirShot ~= "" then
        U.shot(game, dirShot .. "/run_stride_" .. dir .. ".png")
      end
      for _ = 1, 60 do
        if #drawn > 0 then break end
        coroutine.yield()
      end
      Player.tick = origTick
      local hit, miss
      for _, d in ipairs(drawn) do
        if STRIDE[dir][d.f] then hit = d.f else miss = d.f end
      end
      check("run_stride_frame_" .. dir, hit ~= nil and miss == nil,
        "frame=" .. tostring(miss or hit) .. " clock=" .. tostring(strideClock))
      game.input.state[dir] = false
      game.input.state.b = false
      U.wait(20)
    end

    for k in pairs(drawn) do drawn[k] = nil end
    game.input.state.b = false
    for _ = 1, 20 do
      game.input.state.down = true
      table.insert(game.input.pressQueue, "down")
      coroutine.yield()
    end
    game.input.state.down = false
    check("walk_not_run_pose", #drawn == 0, "runDraws=" .. #drawn)
    OwSprites.pose = origPose
  end)
  if not ok then check("driver_error", false, tostring(err)) end
  love.event.quit(failed and 1 or 0)
end
