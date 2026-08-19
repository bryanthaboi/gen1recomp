return function(game)
  local U = dofile("tests/drivers/util.lua")
  local TouchControls = require("src.core.TouchControls")
  local TouchSkin = require("src.core.TouchSkin")
  local Playfield = require("src.render.Playfield")

  local dir = os.getenv("SHOT_DIR") or "/tmp/skin-cutout"
  local gen2 = game.overworld == nil
  local failures, checks = 0, 0

  local SKIN = [[
return {
  name = "containment_probe",
  pages = {
    {
      name = "probe",
      fullScreen = true,
      viewport = { x = 0.25, y = 0.1, w = 0.5, h = 0.6 },
      controls = { { bind = "nul", x = 0.5, y = 0.92, w = 0.04, h = 0.04 } },
    },
  },
}
]]
  love.filesystem.createDirectory("skins/containment_probe")
  assert(love.filesystem.write("skins/containment_probe/skin.lua", SKIN))

  love.window.setMode(1280, 720, { resizable = true, highdpi = true })
  love.graphics.setBackgroundColor(0, 0, 0, 1)
  U.wait(2)

  local options = gen2 and game.options or game.save.options
  options.touchControls = { enabled = true, skin = "containment_probe" }
  options.tilt = 0
  options.zoom = 0
  options.pipelines = {}
  options.videoMode = "windowed"
  options.faithfulRes = 0
  game:applyOptions()
  love.window.setMode(1280, 720, { resizable = true, highdpi = true })
  U.wait(4)

  U.log("gen:", gen2 and 2 or 1, "skin:", tostring(TouchControls.skinId),
        "err:", tostring(TouchControls.skinError))
  U.log("drawable:", TouchSkin.drawable(), "hasViewport:", TouchSkin.hasViewport())

  local function cutoutPx()
    local pw, ph = love.graphics.getPixelDimensions()
    local x, y, w, h = Playfield.cutout(pw, ph)
    return x, y, w, h, pw, ph
  end

  local cx, cy, cw, ch, pw, ph = cutoutPx()
  if not cx then
    U.log("FAIL no cutout is active; nothing to prove")
    love.event.quit()
    while true do coroutine.yield() end
  end
  U.log(("cutout px: %d,%d %dx%d in %dx%d"):format(cx, cy, cw, ch, pw, ph))

  local INSET = 4
  local function scan(label, data)
    local w, h = data:getWidth(), data:getHeight()
    local sx, sy = w / pw, h / ph
    local x1, y1 = math.floor(cx * sx) - INSET, math.floor(cy * sy) - INSET
    local x2 = math.ceil((cx + cw) * sx) + INSET
    local y2 = math.ceil((cy + ch) * sy) + INSET
    local bad, firstX, firstY, worst = 0, nil, nil, 0
    local inked = 0
    local step = math.max(2, math.floor(math.min(w, h) / 360))
    for y = 0, h - 1, step do
      for x = 0, w - 1, step do
        local r, g, b = data:getPixel(x, y)
        local lit = math.max(r, g, b)
        local outside = x < x1 or x >= x2 or y < y1 or y >= y2
        if outside then
          if lit > 0.02 then
            bad = bad + 1
            if not firstX then firstX, firstY = x, y end
            if lit > worst then worst = lit end
          end
        elseif lit > 0.02 then
          inked = inked + 1
        end
      end
    end
    checks = checks + 1
    if bad > 0 then
      failures = failures + 1
      U.log(("FAIL %s: %d lit samples outside the cutout (first %d,%d, max %.2f)")
        :format(label, bad, firstX, firstY, worst))
    elseif inked == 0 then
      failures = failures + 1
      U.log("FAIL " .. label .. ": nothing drew inside the cutout either")
    else
      U.log(("ok   %s: contained (%d lit samples inside)"):format(label, inked))
    end
  end

  local pending = nil
  local function probe(label)
    U.wait(2)
    pending = label
    love.graphics.captureScreenshot(function(data)
      scan(pending, data)
      pending = nil
    end)
    for _ = 1, 180 do
      if not pending then break end
      coroutine.yield()
    end
    if pending then
      failures = failures + 1
      U.log("FAIL " .. tostring(pending) .. ": screenshot never arrived")
      pending = nil
    end
    if os.getenv("SHOT_PNG") == "1" then
      U.shot(game, ("%s/%s.png"):format(dir, label:gsub("[^%w]+", "_")))
    end
  end

  if gen2 then
    for i = 1, 2 do
      probe("gold_boot_" .. i)
      U.wait(60)
    end
    for _ = 1, 240 do
      if game.world and game.world.map then break end
      game.input.pressQueue[#game.input.pressQueue + 1] = "start"
      U.wait(4)
    end
    if game.world and game.world.map then
      probe("gold_overworld")
      local Zoom = require("src.render.Zoom")
      Zoom.allowSurvey = true
      for _, off in ipairs({ -2, -1, 1, 2 }) do
        Zoom.offset = off
        probe("gold_zoom_" .. (off < 0 and "out" or "in") .. math.abs(off))
      end
      Zoom.offset = 0
      local function tap(button, frames)
        game.input.pressQueue[#game.input.pressQueue + 1] = button
        game.input.state[button] = true
        U.wait(2)
        game.input.state[button] = false
        U.wait(frames or 12)
      end
      tap("start", 24)
      probe("gold_start_menu")
      tap("b", 12)
      probe("gold_after_menu")
    else
      U.log("FAIL gold world never booted")
      failures = failures + 1
    end
  else
    local Pokemon = require("src.pokemon.Pokemon")
    game.save.party = { Pokemon.new(game.data, "CHARIZARD", 50) }
    game.save.player.name = "bryan"
    U.teleport(game, "PALLET_TOWN", 10, 8, "down")
    U.wait(12)
    probe("red_overworld")

    local Zoom = require("src.render.Zoom")
    local Renderer = require("src.render.Renderer")
    Zoom.allowSurvey = true
    local lo, hi = Zoom.offsetRange(Renderer:fitScale())
    for off = lo, hi do
      Zoom.offset = off
      probe("red_zoom_" .. Zoom.offsetLabel(off))
    end
    Zoom.offset = 0

    U.tap(game, "start")
    U.wait(20)
    probe("red_start_menu")

    local function stress(label, mutate)
      local state = game.stack:top()
      local original = state.draw
      state.draw = function(...)
        original(...)
        mutate()
      end
      probe(label)
      state.draw = original
    end
    stress("red_screen_veil", function()
      Renderer.screenVeil = { 1, 0.85 }
    end)
    stress("red_battle_wipe", function()
      Renderer.battleWipe = { style = "spiralin", prog = 0.45 }
    end)
    stress("red_letterbox_paper", function()
      Renderer.extendedWorldBand = true
    end)
    stress("red_ui_anchor", function()
      Renderer.uiCentered = false
      Renderer:setUIAnchor(0, 96, 160, 48, "bottom")
    end)
    U.tap(game, "b")
    U.wait(10)

    game.save.options.uiLayout = "dynamic"
    game:applyOptions()
    U.tap(game, "start")
    U.wait(20)
    probe("red_dynamic_start_menu")
    U.tap(game, "b")
    U.wait(10)
    game.save.options.uiLayout = "centered"
    game:applyOptions()

    local Tilt = require("src.render.Tilt")
    game.save.options.tilt = 1
    Tilt.applyOptions(game.save.options)
    U.wait(30)
    probe("red_tilt")
    game.save.options.tilt = 0
    Tilt.applyOptions(game.save.options)
    U.wait(20)
  end

  U.log(("done: %d/%d frames contained, %d failures")
    :format(checks - failures, checks, failures))
  love.event.quit()
  while true do coroutine.yield() end
end
