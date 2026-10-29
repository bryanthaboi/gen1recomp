-- Gen 3's world-pipeline seam (src/core/game3/display.lua presentPlanes), the
-- peer of tests/drivers/gold_pipeline_shots.lua for Gen 1 / Gen 2.
--
--   POKEPORT_IDENTITY=<id with a FireRed import> POKEPORT_VERSION=firered \
--     POKEPORT_DRIVER=tests/drivers/game3_pipeline_shots.lua love .
--   POKEPORT_SHOT_DIR=/tmp/game3-pipeline   (default; must exist)
--
-- Registers a pipeline whose drawWorld draws the vanilla field through
-- ctx.drawField and scales it to the window, switches it on, and asserts
-- what the seam is supposed to guarantee:
--   * parity: that pipeline's frame is the vanilla frame, pixel for pixel
--   * drawWorld owns the world and worldPresent folds over it
--   * ctx carries generation 3, the camera, the view and the window size
--   * sprite animation ticks once per frame however often drawField runs
--   * a pipeline that declines (nil) or throws leaves the vanilla plane
local U = require("tests.drivers.util")
local Pipelines = require("src.render.Pipelines")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3-pipeline"
  local failures = 0
  local function ok(label, cond, detail)
    if cond then
      print("[pipeline3] ok   " .. label)
    else
      failures = failures + 1
      print("[pipeline3] FAIL " .. label .. " " .. tostring(detail))
    end
  end
  local function finish()
    print(failures == 0 and "[pipeline3] PASS" or ("[pipeline3] FAILURES " .. failures))
    love.event.quit(failures == 0 and 0 or 1)
  end

  -- capture through main.lua's capturePath, decoded back for comparison
  local function shot(name)
    local path = out .. "/" .. name
    os.remove(path)
    game.capturePath = path
    for _ = 1, 4000 do
      if not game.capturePath then break end
      U.wait(1)
    end
    U.wait(2)
    local f = io.open(path, "rb")
    if not f then ok("screenshot " .. name, false, "not written (does the dir exist?)") return nil end
    local bytes = f:read("*a")
    f:close()
    return love.image.newImageData(love.filesystem.newFileData(bytes, name))
  end
  local function diff(a, b)
    if not (a and b) then return math.huge end
    local w, h = a:getDimensions()
    if b:getWidth() ~= w or b:getHeight() ~= h then return math.huge end
    local n = 0
    for y = 0, h - 1, 2 do
      for x = 0, w - 1, 2 do
        local r1, g1, b1 = a:getPixel(x, y)
        local r2, g2, b2 = b:getPixel(x, y)
        if math.abs(r1 - r2) + math.abs(g1 - g2) + math.abs(b1 - b2) > 0.02 then n = n + 1 end
      end
    end
    return n
  end

  -- boot a new game into the field
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not game.boot then ok("boot reached", false) return finish() end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  ok("new game reached the field", Runtime.getSession() ~= nil, "no session")
  pcall(Map.load, Runtime._mod, game, "FR_PALLET_TOWN", { x = 12, y = 8, facing = "down" })
  local s = Runtime.getSession()
  s.x, s.y, s.facing = 12, 8, "down"
  Player.reset(12, 8, "down")
  U.wait(40)
  local Space = require("src.core.game3.scripting.space")
  if Space.vm and Space.vm:isRunning() then Space.vm:halt(true) end
  require("src.core.game3.field").unlock()
  -- let the map-name popup slide away so it cannot differ between shots
  U.wait(300)

  -- ---------------------------------------------------------------- record
  local seen = { draws = 0, fields = 0, presents = 0 }
  local mode = "parity"
  local canvas, small
  local G = love.graphics
  local pipeline = {
    label = "PIPE3",
    levels = { "OFF", "ON" },
    drawWorld = function(ctx)
      seen.draws = seen.draws + 1
      seen.ctx = ctx
      if mode == "decline" then return nil end
      if mode == "throw" then error("pipeline3 exploded") end
      local w = math.floor(ctx.width * G.getDPIScale() + 0.5)
      local h = math.floor(ctx.height * G.getDPIScale() + 0.5)
      if not canvas or canvas:getWidth() ~= w or canvas:getHeight() ~= h then
        canvas = G.newCanvas(w, h, { dpiscale = 1 })
      end
      if not small or small:getWidth() ~= ctx.vw or small:getHeight() ~= ctx.vh then
        small = G.newCanvas(ctx.vw, ctx.vh, { dpiscale = 1 })
        small:setFilter("nearest", "nearest")
      end
      G.setCanvas(small)
      G.clear(0, 0, 0, 1)
      if mode == "twice" then
        ctx.drawField({ skipActors = true })
        ctx.drawField({ actorsOnly = true })
        seen.fields = seen.fields + 2
      else
        ctx.drawField()
        seen.fields = seen.fields + 1
      end
      G.setCanvas(canvas)
      G.clear(0, 0, 0, 1)
      local scale = math.min(w / ctx.vw, h / ctx.vh)
      G.draw(small, math.floor((w - ctx.vw * scale) / 2), math.floor((h - ctx.vh * scale) / 2), 0, scale, scale)
      G.setCanvas()
      return canvas
    end,
    worldPresent = function(image)
      seen.presents = seen.presents + 1
      return image
    end,
  }
  -- a fresh table so Pipelines.list() re-sorts; the mod merge does the same
  local reg = { pipe3 = pipeline, _owners = {} }
  for k, v in pairs(game.data.render_pipelines or {}) do
    if k ~= "_owners" and k ~= "pipe3" then reg[k] = v end
  end
  game.data.render_pipelines = reg
  Pipelines.install(game.data)

  -- An off/on pair with the game logic frozen in between, so the two frames
  -- differ only by what the pipeline did -- no popup, NPC step or tile
  -- animation can creep in between them.
  local function pair(name, setup)
    Pipelines.setLevel("pipe3", 0)
    U.wait(4)
    local update = rawget(game, "update")
    game.update = function() end
    local before = shot(name .. "-off.png")
    setup()
    Pipelines.setLevel("pipe3", 1)
    U.wait(2)
    local after = shot(name .. "-on.png")
    game.update = update
    return before, after
  end

  -- ---------------------------------------------------------------- parity
  Pipelines.setLevel("pipe3", 0)
  U.wait(10)
  ok("off: the pipeline is not consulted", seen.draws == 0, seen.draws)
  local vanilla, piped = pair("01-parity", function() mode = "parity" end)
  ok("on: the pipeline owns the Gen 3 world", Pipelines.worldPipeline() == "pipe3",
    tostring(Pipelines.worldPipeline()))
  ok("drawWorld ran", seen.draws > 0, seen.draws)
  ok("worldPresent folded over it", seen.presents > 0, seen.presents)
  local d = diff(vanilla, piped)
  ok("parity: drawField through the pipeline matches the vanilla frame", d == 0, d .. " pixels differ")

  local ctx = seen.ctx or {}
  ok("ctx.generation is 3", ctx.generation == 3, ctx.generation)
  ok("ctx.cam is a world-pixel point", type(ctx.cam) == "table" and type(ctx.cam.x) == "number", ctx.cam)
  ok("ctx.vw/vh is the world view", (ctx.vw or 0) > 0 and (ctx.vh or 0) > 0, tostring(ctx.vw) .. "x" .. tostring(ctx.vh))
  ok("ctx.width/height is the playfield", (ctx.width or 0) > 0 and (ctx.height or 0) > 0, ctx.width)
  ok("ctx.map names the current map", ctx.map == "FR_PALLET_TOWN", ctx.map)

  -- ---------------------------------------------------------------- split draw
  local v2, split = pair("02-ground-then-actors", function() mode = "twice" end)
  local ds = diff(v2, split)
  ok("ground then actors draws the same scene", ds == 0, ds .. " pixels differ")

  mode = "twice"
  -- animation ticks once a frame: watch the frame counter of a sprite sheet
  -- advance at the same rate with one and two drawField calls
  local Oam = require("src.core.game3.oam")
  local ticks = 0
  local orig = Oam.animateSprites
  Oam.animateSprites = function(...) ticks = ticks + 1 return orig(...) end
  ticks = 0
  U.wait(30)
  local twice = ticks
  mode = "parity"
  ticks = 0
  U.wait(30)
  local once = ticks
  Oam.animateSprites = orig
  ok("sprite animation ticks once per frame however often drawField runs",
    twice == once, ("%d vs %d"):format(twice, once))

  -- ---------------------------------------------------------------- fallback
  local v3, declined = pair("03-declines", function() mode = "decline" end)
  ok("a declining pipeline leaves the vanilla frame", diff(v3, declined) == 0,
    diff(v3, declined) .. " pixels differ")

  local v4, thrown = pair("04-throws", function() mode = "throw" end)
  ok("a throwing pipeline is retired and the vanilla frame stays", diff(v4, thrown) == 0,
    diff(v4, thrown) .. " pixels differ")
  ok("after the throw the world is vanilla again", Pipelines.worldPipeline() == nil,
    tostring(Pipelines.worldPipeline()))

  Pipelines.setLevel("pipe3", 0)
  finish()
end
