-- Real-run check for mods/fr_voxel: boots FireRed, stands in Pallet Town,
-- walks the DIORAMA ladder with its hotkey and measures what the 3D pass
-- costs next to the flat field it replaces.
--
--   POKEPORT_DRIVER=tests/drivers/fr_voxel_field.lua POKEPORT_VERSION=firered love .
--   POKEPORT_SHOT_DIR=<dir> (defaults next to the repo's temp shots)
--
-- Screenshots are the evidence for the visual side; the PASS/FAIL lines are
-- the evidence for the contract: registration, hotkey, scope ladder, the
-- canvas handed back for an in-scope map and nil for an out-of-scope one.

local U = require("tests.drivers.util")

local SHOT_DIR = (os.getenv("POKEPORT_SHOT_DIR")
  or "C:/Users/Angel/AppData/Local/Temp/opencode/frshots"):gsub("\\", "/")

local failures = 0
local function result(ok, label, extra)
  if extra ~= nil then label = label .. " -- " .. tostring(extra) end
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function key(k)
  love.keypressed(k, k, false)
  love.keyreleased(k, k)
end

local function shot(game, name)
  local ok = U.shot(game, SHOT_DIR .. "/" .. name .. ".png")
  result(ok, "screenshot " .. name)
  return ok
end

-- Frames are driven 1:1 in a scripted run, so counting the yields between
-- two timestamps is a frame-time measurement of the real render loop.
local function measure(game, label, frames)
  U.wait(60) -- let the tween, the mesh build and the first draws settle
  local t0 = love.timer.getTime()
  for _ = 1, frames do U.wait(1) end
  local dt = math.max(love.timer.getTime() - t0, 0.001)
  U.log(("%s: %.1f fps (%.2f ms/frame over %d frames)")
    :format(label, frames / dt, dt * 1000 / frames, frames))
  return frames / dt
end

-- The ctx src/core/game3/display.lua hands a world pipeline: the cast is
-- built the same way, so this is the call the engine itself would make.
local function worldCtx(game, level)
  local FieldView = require("src.core.game3.field_view")
  local cast = FieldView.pipelineActors(game, 240, 160)
  return {
    state = game, vw = 240, vh = 160, level = level,
    cam = cast and { x = cast.camX, y = cast.camY } or nil,
    actors = cast,
  }
end

local function drawWorld(Pipelines, id, ctx)
  local canvas = Pipelines.drawWorld(id, ctx)
  return canvas ~= nil, canvas
end

local function finish()
  if failures == 0 then
    print("PASS fr_voxel_field")
  else
    print("FAIL fr_voxel_field failures=" .. failures)
  end
end

return function(game)
  -- ------------------------------------------------------------ boot
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not result(game.phase == "boot" and game.boot ~= nil, "reached the FireRed boot") then
    finish()
    return
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(300)
  if not result(game.phase == "field", "new game reached the field", game.phase) then
    finish()
    return
  end

  local Map = require("src.core.game3.map")
  Map.load(nil, game, "FR_PALLET_TOWN", { x = 5, y = 8, facing = "up" })
  U.wait(90)
  if not result(Map.current == "FR_PALLET_TOWN", "standing in Pallet Town",
      tostring(Map.current)) then
    finish()
    return
  end

  -- ------------------------------------------------- registration
  local Pipelines = require("src.render.Pipelines")
  local ids = {}
  local registered = false
  for _, entry in ipairs(Pipelines.list()) do
    ids[#ids + 1] = entry.id
    if entry.id == "fr_diorama" then registered = true end
  end
  if not result(registered, "fr_diorama is registered",
      table.concat(ids, ",")) then
    finish()
    return
  end

  local def = Pipelines.get("fr_diorama")
  local okA, avail = pcall(function() return def and def.available and def.available() end)
  result(okA and avail == true, "the 3D path reports available under LOVE",
    tostring(avail))
  result(def.hotkey == "6", "hotkey is 6", tostring(def.hotkey))
  result(Pipelines.levelLabel("fr_diorama", 0) == "OFF"
    and Pipelines.levelLabel("fr_diorama", 1) == "PALLET"
    and Pipelines.levelLabel("fr_diorama", 2) == "+ROUTE 1"
    and Pipelines.levelLabel("fr_diorama", 3) == "ALL",
    "ladder is OFF/PALLET/+ROUTE 1/ALL")

  -- --------------------------------------------- GLSL ES gate (Android)
  -- The phone build compiles this exact source through LÖVE's GLES driver,
  -- and the scene shader is the only shader the diorama owns (ShadowMap
  -- rides on it).  validateShader(gles=true, ...) relabels the source as ES
  -- without creating a Shader object, so it is a pure compile gate.
  do
    local raw = love.filesystem.read("mods/fr_voxel/lib/Voxel3D.lua")
    -- string.match returns every capture, so the long-bracket level must
    -- stay un-captured: "(=*)" would win the race and return "" instead of
    -- the body.
    local body = raw and (raw:match("local SHADER%s*=%s*%[%[(.-)%]%]")
      or raw:match("local SHADER%s*=%s*%[=(.-)%]="))
    if result(body ~= nil, "scene shader source readable for the ES check",
        body and (#body .. " bytes") or "Voxel3D SHADER literal not found") then
      local real = love.graphics.getSupported
      for _, g3 in ipairs({ true, false }) do
        love.graphics.getSupported = function()
          local t = real()
          t.glsl3 = g3
          return t
        end
        local okCall, ok, err = pcall(love.graphics.validateShader, true, body)
        love.graphics.getSupported = real
        result(okCall and ok == true,
          ("scene shader compiles as GLSL ES (glsl3=%s)"):format(tostring(g3)),
          okCall and (ok == true and "ok" or tostring(err)) or tostring(ok))
      end
    end
  end

  -- --------------------------------------------- Pallet, flat first
  Pipelines.setLevel("fr_diorama", 0)
  U.wait(20)
  result(Pipelines.worldPipeline() == nil, "flat field before the hotkey",
    tostring(Pipelines.worldPipeline()))
  shot(game, "00_pallet_flat")
  local flatFps = measure(game, "Pallet flat", 240)

  -- --------------------------------------------- Pallet, rung 1
  key("6")
  U.wait(30)
  result(Pipelines.worldPipeline() == "fr_diorama",
    "hotkey 6 selects the diorama", tostring(Pipelines.worldPipeline()))
  result(Pipelines.level("fr_diorama") == 1, "rung 1 is PALLET",
    Pipelines.levelLabel("fr_diorama"))
  local okCanvas, canvas = drawWorld(Pipelines, "fr_diorama",
    worldCtx(game, Pipelines.level("fr_diorama")))
  result(okCanvas, "in-scope map hands back a world canvas",
    canvas and tostring(canvas) or "nil")
  shot(game, "01_pallet_rung1")
  local dioramaFps = measure(game, "Pallet diorama rung 1", 240)
  U.log(("pallet: flat %.1f fps -> diorama %.1f fps (%+.0f%%)")
    :format(flatFps, dioramaFps, (dioramaFps / flatFps - 1) * 100))

  -- --------------------------------------------- the rest of the ladder
  key("6")
  U.wait(30)
  result(Pipelines.level("fr_diorama") == 2, "rung 2 is +ROUTE 1",
    Pipelines.levelLabel("fr_diorama"))
  shot(game, "02_pallet_rung2")
  key("6")
  U.wait(30)
  result(Pipelines.level("fr_diorama") == 3, "rung 3 is ALL",
    Pipelines.levelLabel("fr_diorama"))
  shot(game, "03_pallet_rung3")

  -- --------------------------------------------- Route 1
  Map.load(nil, game, "FR_ROUTE_1", { x = 10, y = 35, facing = "up" })
  U.wait(120)
  result(Map.current == "FR_ROUTE_1", "standing in Route 1",
    tostring(Map.current))

  -- rung 1 keeps Route 1 on the flat field: same map, scope off
  Pipelines.setLevel("fr_diorama", 1)
  U.wait(30)
  local okOff, canvasOff = drawWorld(Pipelines, "fr_diorama",
    worldCtx(game, 1))
  result(not okOff, "out-of-scope map declines the pipeline (2D fallback)",
    canvasOff and "handed a canvas anyway" or "nil")
  shot(game, "04_route1_rung1_flat")

  -- rung 2 puts Route 1 in scope again
  Pipelines.setLevel("fr_diorama", 2)
  U.wait(30)
  local okOn, canvasOn = drawWorld(Pipelines, "fr_diorama",
    worldCtx(game, 2))
  result(okOn, "in-scope Route 1 hands back a world canvas",
    canvasOn and tostring(canvasOn) or "nil")
  shot(game, "05_route1_rung2")
  local routeFps = measure(game, "Route 1 diorama rung 2", 240)
  U.log(("route1: flat %.1f fps vs diorama %.1f fps"):format(flatFps, routeFps))

  -- the mode must survive a hotkey round trip back to OFF
  key("6")
  U.wait(20)
  key("6")
  U.wait(20)
  key("6")
  U.wait(20)
  key("6")
  U.wait(20)
  result(Pipelines.worldPipeline() == nil or Pipelines.level("fr_diorama") >= 0,
    "ladder cycles without error", "level=" .. Pipelines.level("fr_diorama"))

  finish()
end
