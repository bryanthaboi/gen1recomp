-- Gold's frame and input seams: proof that all six shared hooks fire on a Gold
-- boot, with the Gen 1 payloads, and that subscribing to them does not change
-- the picture.
--
--   POKEPORT_GAME=gold POKEPORT_DRIVER=tests/drivers/gold_frame_seams.lua \
--     POKEPORT_SHOT_DIR=/tmp/gold-seams love .
--
-- Two halves, and the second is the one that matters.  A hook that fires is
-- easy; a hook that fires and MOVES A PIXEL is worse than no hook at all,
-- because it silently changes what every existing Gold screenshot means.  So
-- this shoots the overworld, CLASSIC, and a menu over the overworld with
-- nothing subscribed, wraps all six hooks with pass-throughs that draw
-- nothing, shoots the same three frames again, and compares the PNG bytes.
-- Identical files are the claim; the shots are left on disk either way so a
-- human can look at the picture the port is actually producing.
--
-- The three frames are chosen to cover every branch of Game2:draw: no canvas
-- at all, the zone pass alone, and (once the wraps are on) the render.compose
-- path that forces a canvas even when no display mode wanted one.
--
-- The zone-pass-into-a-texture-then-reread branch (`reread` in
-- Game2:drawViewportFrame, formerly exercised by CLASSIC + GBC FX before
-- GBCFX.lua's removal) is not covered here any more:
-- ShaderFX is the only thing left that triggers it, and activating it needs
-- a converted on-disk preset this headless driver does not set up. Flagged,
-- not silently dropped.
local U = require("tests.drivers.util")

local Runtime = require("src.mods.Runtime")
local Hooks = require("src.mods.Hooks")
local GbcPalette = require("src.render.GbcPalette")

local OWNER = "driver_frame_seams"

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  return body
end

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-seams"
  local failures = 0
  local function check(ok, what)
    if ok then
      print("[driver] ok   " .. what)
    else
      failures = failures + 1
      print("[driver] FAIL " .. what)
    end
  end

  U.wait(45)
  assert(game.world and game.world.map, "gold world did not boot")

  -- The three frames, each named for the display state it exercises.
  local frames = {
    { name = "world", color = "gbc" },
    { name = "classic", color = "classic" },
    { name = "menu", color = "gbc", menu = true },
  }

  local function shoot(tag)
    local menuOpen = false
    for _, frame in ipairs(frames) do
      GbcPalette.setMode(frame.color)
      if frame.menu and not menuOpen then
        game:openStartMenu()
        menuOpen = true
        U.wait(6)
      end
      U.wait(2)
      U.shot(game, ("%s/%s-%s.png"):format(out, frame.name, tag))
    end
    if menuOpen then
      -- B closes the START menu; leave the stack the way it was found so the
      -- second pass shoots the same scene the first one did
      U.tap(game, "b")
      U.wait(8)
    end
    GbcPalette.setMode("gbc")
  end

  -- POKEPORT_SEAM_BASELINE=<tag> shoots the four frames under that tag and
  -- stops, with nothing ever subscribed.  That is how the composite was A/B'd
  -- against the revision of Game2:draw that predates these seams: run it once
  -- with the old draw in place, once with the new one, and diff the PNGs.
  local baseline = os.getenv("POKEPORT_SEAM_BASELINE")
  if baseline and baseline ~= "" then
    shoot(baseline)
    print(("[driver] baseline shots (%s) in %s"):format(baseline, out))
    return
  end

  shoot("before")

  -- A live bus, in case this checkout booted with no mods (Runtime's null
  -- object has no chains table and wantsHook is false for everything).
  if not (Runtime.hooks and Runtime.hooks.wrap) then
    Runtime.hooks = Hooks.new()
  end
  local hooks = Runtime.hooks

  local seen = {}
  local payload = {}
  local function record(name, ctx)
    seen[name] = (seen[name] or 0) + 1
    payload[name] = payload[name] or ctx
  end

  -- input.step: (game, dt), before the pad is read
  hooks:wrap("input.step", function(nextFn, g, dt)
    record("input.step", { game = g, dt = dt })
    return nextFn(g, dt)
  end, 0, OWNER)

  -- input.pointer: (game, event); returning false is "not consumed"
  hooks:wrap("input.pointer", function(nextFn, g, ev)
    record("input.pointer", { game = g, ev = ev })
    return nextFn(g, ev)
  end, 0, OWNER)

  -- render.zones: (game, zones) -> zones.  Pass the list straight through; a
  -- wrap that returned a new list would be testing itself, not the seam.
  hooks:wrap("render.zones", function(nextFn, g, zones)
    record("render.zones", { game = g, zones = zones })
    return nextFn(g, zones)
  end, 0, OWNER)

  -- render.compose: (renderer, ctx) -> true to take the window.  Declines, so
  -- the engine composite still runs -- which is the case the byte comparison
  -- below is about.
  hooks:wrap("render.compose", function(nextFn, r, ctx)
    record("render.compose", { renderer = r, ctx = ctx })
    return nextFn(r, ctx)
  end, 0, OWNER)

  -- render.letterbox: (ctx), draws nothing
  hooks:wrap("render.letterbox", function(nextFn, ctx)
    record("render.letterbox", { ctx = ctx })
    return nextFn(ctx)
  end, 0, OWNER)

  -- render.hud: (game, viewport), draws nothing
  hooks:wrap("render.hud", function(nextFn, g, viewport)
    record("render.hud", { game = g, viewport = viewport })
    return nextFn(g, viewport)
  end, 0, OWNER)

  U.wait(4)
  -- a pointer the engine itself never generates headlessly
  game:mousepressed(40, 30, 1, false)
  game:mousemoved(48, 36, 8, 6, false)
  game:mousereleased(48, 36, 1, false)
  U.wait(2)

  shoot("after")

  -- ---- the seams fired, with the Gen 1 payloads -----------------------------

  for _, name in ipairs({ "input.step", "input.pointer", "render.zones",
                          "render.compose", "render.letterbox",
                          "render.hud" }) do
    check((seen[name] or 0) > 0, name .. " fires on Gold (" ..
      tostring(seen[name] or 0) .. " calls)")
  end

  local step = payload["input.step"]
  check(step and step.game == game, "input.step receives the live Game object")
  check(step and math.abs((step.dt or 0) - 1 / 60) < 1e-9,
    "input.step receives the fixed-step dt")

  local ptr = payload["input.pointer"]
  check(ptr and ptr.game == game, "input.pointer receives the live Game object")
  check(ptr and ptr.ev and ptr.ev.phase == "pressed"
    and ptr.ev.source == "mouse" and ptr.ev.id == "mouse"
    and ptr.ev.x == 40 and ptr.ev.y == 30 and ptr.ev.button == 1
    and ptr.ev.dx == 0 and ptr.ev.dy == 0,
    "input.pointer carries phase/source/id/x/y/dx/dy/button")

  local zones = payload["render.zones"]
  check(zones and zones.game == game, "render.zones receives the live Game")

  local hud = payload["render.hud"]
  local vp = hud and hud.viewport
  local ww, wh = love.graphics.getDimensions()
  check(vp and vp.width == ww and vp.height == wh,
    "render.hud viewport carries the window size")
  check(vp and vp.gameWidth == 160 * vp.scale
    and vp.gameHeight == 144 * vp.scale,
    "render.hud viewport playfield is 160x144 at the fit scale")
  check(vp and vp.gameX == math.floor((ww - vp.gameWidth) / 2)
    and vp.gameY == math.floor((wh - vp.gameHeight) / 2),
    "render.hud viewport playfield is centred")
  check(vp and vp.dpiX ~= nil and vp.dpiY ~= nil,
    "render.hud viewport carries the dpi scales")

  local lb = payload["render.letterbox"] and payload["render.letterbox"].ctx
  check(lb and lb.ww == ww and lb.wh == wh,
    "render.letterbox carries ww/wh")
  check(lb and lb.pw ~= nil and lb.ph ~= nil and lb.ox ~= nil and lb.oy ~= nil
    and lb.vpw ~= nil and lb.vph ~= nil and lb.scale ~= nil
    and lb.dpiX ~= nil and lb.dpiY ~= nil,
    "render.letterbox carries pw/ph/ox/oy/vpw/vph/scale/dpi")
  check(lb and type(lb.worldActive) == "boolean",
    "render.letterbox carries worldActive")

  local ctx = payload["render.compose"] and payload["render.compose"].ctx
  check(payload["render.compose"]
    and payload["render.compose"].renderer == game,
    "render.compose receives the compositor in the renderer position")
  check(ctx and ctx.uiCanvas ~= nil and ctx.worldCanvas == ctx.uiCanvas,
    "render.compose hands over Gold's one scene canvas under both keys")
  check(ctx and ctx.ww == ww and ctx.wh == wh and ctx.uiw == 160
    and ctx.uih == 144 and ctx.scale ~= nil and ctx.ox ~= nil
    and ctx.oy ~= nil and ctx.vpw ~= nil and ctx.vph ~= nil
    and ctx.dpiX ~= nil and ctx.secondScreen ~= nil,
    "render.compose carries the Gen 1 frame metrics")

  -- ---- and moved nothing ----------------------------------------------------

  for _, frame in ipairs(frames) do
    local a = readFile(("%s/%s-before.png"):format(out, frame.name))
    local b = readFile(("%s/%s-after.png"):format(out, frame.name))
    check(a ~= nil and b ~= nil and a == b,
      ("subscribing does not change the %s frame"):format(frame.name))
  end

  hooks:removeOwner(OWNER)
  print(("[driver] shots in %s"):format(out))
  if failures > 0 then
    print(("[driver] FAILED (%d)"):format(failures))
  else
    print("[driver] PASS")
  end
end
