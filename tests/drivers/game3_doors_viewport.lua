local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_doors_viewport"
local TARGETS = {
  { label = "gym", x = 36, y = 10, tile = "SlidingDouble" },
  { label = "wooden", x = 25, y = 11, tile = "Viridian" },
}
local VIEWS = {
  { label = "portrait", w = 390, h = 844, zoom = 0 },
  { label = "landscape_survey", w = 844, h = 390, zoom = -1 },
}

return function(game)
  local failures = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failures = failures + 1 end
    return ok
  end
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Doors = require("src.core.game3.doors")
  local Dataset = require("src.core.game3.dataset")
  local Extract = require("src.import.gba.extract_island1")
  local Renderer = require("src.render.Renderer")
  local FaithfulRes = require("src.core.FaithfulRes")
  local Zoom = require("src.render.Zoom")
  FaithfulRes.apply(0)
  require("src.render.Tilt").reset()
  require("src.render.ShaderFX").applyOptions({})
  require("src.core.ScreenPosition").setMode("center")
  Zoom.allowSurvey = true

  local realDoorDraw, realDraw = Doors.draw, love.graphics.draw
  local insideDoor, observed = false, nil
  love.graphics.draw = function(...)
    local image, quad, x, y = ...
    if insideDoor then
      observed = { image = image, quad = quad, x = x, y = y, canvas = love.graphics.getCanvas() }
    end
    return realDraw(...)
  end
  Doors.draw = function(...)
    insideDoor = true
    realDoorDraw(...)
    insideDoor = false
  end

  for _, view in ipairs(VIEWS) do
    Doors.reset()
    local _, _, flags = love.window.getMode()
    flags.fullscreen, flags.resizable = false, true
    flags.minwidth, flags.minheight = 1, 1
    assert(love.window.setMode(view.w, view.h, flags))
    Zoom.offset = view.zoom
    U.wait(15)
    local vw, vh = Renderer:worldViewSize()
    local ww, wh = love.graphics.getDimensions()
    print(string.format("[driver] %s window=%dx%d worldViewSize=%dx%d zoom=%d faithful=%s",
      view.label, ww, wh, vw, vh, Zoom.offset, tostring(FaithfulRes.scaleCap())))
    result(ww == view.w and wh == view.h, view.label .. "_window")
    result(view.label == "portrait" and vh > 400 or view.label == "landscape_survey" and vw > 600,
      view.label .. "_expanded_viewport")

    for _, target in ipairs(TARGETS) do
      Doors.reset()
      Map.load(nil, game, "FR_VIRIDIAN_CITY", { x = target.x, y = target.y + 2, facing = "up" })
      Player.reset(target.x, target.y + 2, "up")
      if game.session then
        game.session.x, game.session.y, game.session.facing = target.x, target.y + 2, "up"
      end
      U.wait(60)
      local anim = Doors.open("FR_VIRIDIAN_CITY", target.x, target.y, { playSound = false })
      local label = view.label .. "_" .. target.label
      result(anim.tile == target.tile, label .. "_sheet")
      for _ = 1, 30 do
        if anim.frame == 1 then break end
        U.wait(1)
      end
      result(anim.frame == 1, label .. "_half_open")
      anim.mode = "hold"
      observed = nil
      local path = DIR .. "/" .. label .. "_half_open.png"
      local captured = U.shot(game, path)
      local sheet = Doors._sheets[target.tile]
      local drawn = observed and sheet and observed.image == sheet.image
        and observed.quad == sheet.quads[1] and observed.canvas == Renderer.worldCanvas
      result(drawn, label .. "_image_drawn")
      if drawn then
        result(observed.x > 256 or observed.y > 176, label .. "_past_old_cutoff")
        local info = Doors._manifest.doors[target.tile]
        local cache = Dataset.cache()
        local bytes = assert(cache:read(Extract.CACHE_ROOT .. "/doors/" .. info.file)
          or cache:read("doors/" .. info.file))
        local source = love.image.newImageData(info.width, info.height, "rgba8", bytes)
        local pixels = observed.canvas:newImageData()
        local matched, opaque, changed = 0, 0, 0
        for y = 0, info.frame_height - 1 do
          for x = 0, info.frame_width - 1 do
            local r, g, b, a = source:getPixel(x, y + info.frame_height)
            if a > 0.99 then
              opaque = opaque + 1
              local pr, pg, pb = pixels:getPixel(observed.x + x, observed.y + y)
              if math.abs(pr - r) < 0.01 and math.abs(pg - g) < 0.01 and math.abs(pb - b) < 0.01 then
                matched = matched + 1
                local cr, cg, cb, ca = source:getPixel(x, y)
                if ca < 0.99 or math.abs(cr-r) + math.abs(cg-g) + math.abs(cb-b) > 0.05 then
                  changed = changed + 1
                end
              end
            end
          end
        end
        print(string.format("[driver] %s opaque=%d matched=%d changed_from_closed=%d", label, opaque, matched, changed))
        result(opaque > 0 and matched == opaque and changed > 0, label .. "_half_open_pixels")
        source:release()
        pixels:release()
      end
      result(captured, label .. "_screenshot")
    end
  end
  Doors.draw, love.graphics.draw = realDoorDraw, realDraw
  Doors.reset()
  result(failures == 0, "doors_viewport_driver")
  love.event.quit(failures == 0 and 0 or 1)
end
