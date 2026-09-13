--   POKEPORT_IDENTITY=red-sep04 POKEPORT_TOUCH=0 POKEPORT_SHOT_DIR=/tmp/2235 POKEPORT_DRIVER=tests/drivers/shaderfx_grid_2235.lua love .
local U = require("tests.drivers.util")
local ShaderFX = require("src.render.ShaderFX")
local Zoom = require("src.render.Zoom")
local GameVersion = require("src.core.GameVersion")

local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/2235"

local WANT = {
  { file = "retro-v3.slangp", tag = "retro" },
  { file = "sameboy-lcd.slangp", tag = "sameboy" },
}

local ZOOMS = {
  { offset = 0, tag = "fit" },
  { offset = -1, tag = "out1" },
  { offset = -2, tag = "out2" },
}

return function(game)
  local fails = 0
  local function ok(cond, label)
    if not cond then fails = fails + 1 end
    print((cond and "PASS " or "FAIL ") .. label)
  end

  love.window.setMode(1024, 768, { resizable = true })
  U.wait(30)

  local gen2 = GameVersion.generation() == 2
  if gen2 then
    game.world:warpToMapId("NEW_BARK_TOWN", 6, 6, "down")
  else
    U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  end
  U.wait(60)

  local byName = {}
  for _, e in ipairs(ShaderFX.list()) do byName[e.name] = e end
  local ready = {}
  for _, want in ipairs(WANT) do
    local entry = byName[want.file]
    if entry and not entry.converted then
      local converted = ShaderFX.convert(entry)
      if not converted then entry = nil end
    end
    if entry then
      ready[#ready + 1] = { entry = entry, tag = want.tag }
    else
      print("SKIP " .. want.file .. " is not in this identity's shaders/")
    end
  end
  ok(#ready > 0, "2235 a grid preset is installed")
  if #ready == 0 then love.event.quit(1) return end

  local captured = {}
  local realRunChain = ShaderFX.runChain
  ShaderFX.runChain = function(state, img, luts, viewport, original, layer)
    captured[layer or "main"] = { vw = viewport.w, vh = viewport.h, ow = original.w, oh = original.h }
    return realRunChain(state, img, luts, viewport, original, layer)
  end

  local function fitScale()
    if gen2 then return game.world:fitScale() end
    return game.renderer:fitScale()
  end

  local function scanlineBands(path, s)
    local f = io.open(path, "rb")
    if not f then return nil, "no shot" end
    local bytes = f:read("*a")
    f:close()
    local okImg, id = pcall(love.image.newImageData, love.filesystem.newFileData(bytes, "shot.png"))
    if not okImg then return nil, tostring(id) end
    local w, h = id:getWidth(), id:getHeight()
    local rows = {}
    for y = 0, h - 1 do
      local sum, n = 0, 0
      for x = 0, w - 1, 2 do
        local r, g, b = id:getPixel(x, y)
        sum, n = sum + (r + g + b) / 3, n + 1
      end
      rows[y] = sum / n * 255
    end
    local best
    for off = 0, s - 1 do
      local groups, total = {}, 0
      for y0 = off, h - s, s do
        local lo, hi = rows[y0], rows[y0]
        for y = y0 + 1, y0 + s - 1 do
          if rows[y] < lo then lo = rows[y] end
          if rows[y] > hi then hi = rows[y] end
        end
        local c = hi >= 40 and (hi - lo) / hi or nil
        groups[#groups + 1] = c
        total = total + (c or 0)
      end
      if not best or total < best.total then best = { off = off, groups = groups, total = total } end
    end
    local blocks = {}
    for b = 1, #best.groups, 16 do
      local sum, n = 0, 0
      for g = b, math.min(b + 15, #best.groups) do
        local c = best.groups[g]
        if c then sum, n = sum + c, n + 1 end
      end
      if n >= 4 then blocks[#blocks + 1] = sum / n end
    end
    local lo, hi = math.huge, 0
    for _, v in ipairs(blocks) do
      if v < lo then lo = v end
      if v > hi then hi = v end
    end
    return { off = best.off, blocks = blocks, lo = lo, hi = hi }
  end

  local gtag = tostring(GameVersion.get())
  for _, r in ipairs(ready) do
    ShaderFX.deactivate("secondary")
    local on, err = ShaderFX.activate("main", r.entry)
    ok(on, ("2235 %s activates %s"):format(r.tag, tostring(err or "")))
    if on then
      for _, z in ipairs(ZOOMS) do
        Zoom.offset = Zoom.clampOffset(z.offset, fitScale())
        captured = {}
        U.wait(6)
        local rect = ShaderFX._lastRect
        local m = captured.main
        ok(rect ~= nil and m ~= nil
          and m.vw == m.ow * rect.scale and m.vh == m.oh * rect.scale,
          ("2235 %s %s world viewport is an exact multiple of its source"):format(r.tag, z.tag))
        local shot = ("%s/2235_%s_%s_%s_map.png"):format(SHOT_DIR, gtag, r.tag, z.tag)
        U.shot(game, shot)
        if r.tag == "sameboy" and z.tag == "out2" and rect then
          local bands, err = scanlineBands(shot, rect.scale)
          local parts = {}
          for i, v in ipairs(bands and bands.blocks or {}) do parts[i] = ("%.3f"):format(v) end
          print(("info sameboy out2 scanline depth per 48px row band (phase %s): %s"):format(
            tostring(bands and bands.off), #parts > 0 and table.concat(parts, " ") or tostring(err)))
          ok(bands ~= nil and #bands.blocks >= 8 and bands.lo >= 0.015 and bands.lo >= 0.5 * bands.hi,
            "2235 sameboy out2 every 48px row band carries scanlines of similar depth")
        end
      end

      Zoom.offset = Zoom.clampOffset(-2, fitScale())
      U.tap(game, "start")
      U.wait(20)
      captured = {}
      U.wait(4)
      local ui = captured.ui or captured.main
      ok(ui ~= nil and ui.vw % ui.ow == 0 and ui.vh % ui.oh == 0
        and ui.vw / ui.ow == ui.vh / ui.oh,
        ("2235 %s out2 menu layer viewport is an exact multiple of its source"):format(r.tag))
      U.shot(game, ("%s/2235_%s_%s_out2_start_menu.png"):format(SHOT_DIR, gtag, r.tag))
      U.tap(game, "b")
      U.wait(20)
    end
  end

  ShaderFX.runChain = realRunChain
  ShaderFX.deactivate("main")
  Zoom.offset = 0
  print(fails == 0 and "PASS 2235 shaderfx grid alignment" or "FAIL 2235 shaderfx grid alignment")
  love.event.quit(fails == 0 and 0 or 1)
end
