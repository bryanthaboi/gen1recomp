-- home/overworld.asm:675
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Zoom = require("src.render.Zoom")
  local PaletteFX = require("src.render.PaletteFX")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots2186"

  local failures = 0
  local function check(label, ok)
    if not ok then failures = failures + 1 end
    print((ok and "PASS " or "FAIL ") .. label)
    return ok
  end

  local function key(colors)
    if not colors then return "nil" end
    local out = {}
    for i, c in ipairs(colors) do out[i] = table.concat(c, ",") end
    return table.concat(out, "|")
  end

  local function baseKey(ow)
    local z = ow:sgbWorldZones()
    return key(z and z[1] and z[1].colors), z and #z or 0
  end

  local function crossNorth(ow)
    for _ = 1, 40 do
      table.insert(game.input.pressQueue, "up")
      game.input.state.up = true
      coroutine.yield()
      if ow.map.id == "ROUTE_1" then break end
    end
    game.input.state.up = false
    return ow.map.id == "ROUTE_1" and ow.player.moving
  end

  U.newGame(game)
  PaletteFX.setMode("gbc")
  Zoom.offset = 0
  local ow = game.overworld

  U.teleport(game, "PALLET_TOWN", 10, 1, "up")
  U.wait(20)
  ow = game.overworld
  check("standing at the Pallet Town / Route 1 seam", ow.map.id == "PALLET_TOWN")
  local pallet = key(PaletteFX.pal(game.data, ow:paletteNameFor(ow.map)))
  local r1 = { id = "ROUTE_1", def = game.data.maps.ROUTE_1 }
  local route = key(PaletteFX.pal(game.data, ow:paletteNameFor(r1)))
  check("Pallet and Route 1 wear different palettes", pallet ~= route)

  check("seam step starts onto Route 1", crossNorth(ow))
  local held, frames, zoneCount = true, 0, 0
  while ow.player.moving and frames < 40 do
    local k, n = baseKey(ow)
    zoneCount = math.max(zoneCount, n)
    if k ~= pallet then held = false end
    frames = frames + 1
    coroutine.yield()
  end
  U.log("seam step frames under Pallet's palette:", frames)
  check("whole screen keeps Pallet's palette for every seam-step frame", held and frames > 0)
  check("seam step is one whole-screen zone", zoneCount == 1)
  local landed, n = baseKey(ow)
  check("palette flips to Route 1 the frame the step lands", landed == route and n == 1)
  check("held palette cleared on landing", ow.seamPalette == nil)

  U.teleport(game, "PALLET_TOWN", 10, 1, "up")
  U.wait(20)
  ow = game.overworld
  check("second pass: seam step starts", crossNorth(ow))
  U.shot(game, DIR .. "/2186_01_seam_step_still_pallet.png")
  check("second pass: shot taken mid-step under Pallet's palette",
        ow.player.moving and (baseKey(ow)) == pallet)
  for _ = 1, 40 do
    if not ow.player.moving then break end
    coroutine.yield()
  end
  U.shot(game, DIR .. "/2186_02_landed_route1_palette.png")
  check("second pass: landed under Route 1's palette", (baseKey(ow)) == route)

  U.teleport(game, "PALLET_TOWN", 10, 1, "up")
  U.wait(20)
  ow = game.overworld
  Zoom.offset = -1
  U.wait(5)
  check("survey zoom: seam step starts", crossNorth(ow))
  local sk, sn = baseKey(ow)
  check("survey zoom keeps per-map zones mid-step", sk == route and sn > 1)
  U.shot(game, DIR .. "/2186_03_survey_per_map.png")
  Zoom.offset = 0

  print(failures == 0 and "PASS seam_palette_timing_2186" or "FAIL seam_palette_timing_2186")
  love.event.quit(failures == 0 and 0 or 1)
  while true do coroutine.yield() end
end
