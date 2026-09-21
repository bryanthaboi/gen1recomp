-- Visual reproduction harness for the Birth Island Deoxys triangle.
--
-- Boots a fresh FireRed game, warps to Birth Island, walks the meteorite through
-- all eleven puzzle positions and then shatters it.  A PNG is captured at every
-- stage and the rock's *drawn* colours are sampled straight out of the sprite
-- the renderer would use, so the palette ramp can be checked as data rather
-- than by eye alone.
local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/deoxys_visual"

local MAP = "FR_BIRTH_ISLAND_EXTERIOR"
local METEORITE = 106

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS deoxys_visual")
    love.event.quit(0)
  else
    print("FAIL deoxys_visual failures=" .. failures)
    love.event.quit(1)
  end
end

--- Count pixels in a saved shot that match one of the rock fragment's palette
--- colours.  The fragment sheet is imported with sDeoxysObjectPals[10] (the
--- awakened red ramp) and the map never contains those exact reds, so any hit
--- is a flying shard actually reaching the screen.  This is what catches the
--- shards being buried under the shatter's white flash: with a whole-screen
--- veil the count is exactly 0.
local FRAG_RGB = { { 206, 33, 33 }, { 255, 82, 82 }, { 255, 206, 156 } }

--- love.graphics.captureScreenshot writes the PNG with a plain io.open, which
--- can reach any absolute path -- but love.image.newImageData only reads paths
--- inside LOVE's sandboxed source/save filesystems, so it cannot open SHOT_DIR.
--- Read the bytes ourselves and hand LOVE a FileData instead.  U.shot has
--- already confirmed the file is on disk, so this never needs to yield frames
--- (yielding here would let the shards fly off screen before they are measured).
local function fragPixels(path)
  local f = io.open(path, "rb")
  if not f then return -1 end
  local bytes = f:read("*a")
  f:close()
  local ok, data = pcall(function()
    return love.image.newImageData(love.filesystem.newFileData(bytes, "shot.png"))
  end)
  if not ok or not data then return -1 end
  local w, h = data:getWidth(), data:getHeight()
  local hits = 0
  for y = 0, h - 1, 2 do
    for x = 0, w - 1, 2 do
      local r, g, b = data:getPixel(x, y)
      r, g, b = r * 255, g * 255, b * 255
      for _, c in ipairs(FRAG_RGB) do
        if math.abs(r - c[1]) < 6 and math.abs(g - c[2]) < 6
          and math.abs(b - c[3]) < 6 then
          hits = hits + 1
          break
        end
      end
    end
  end
  return hits
end

--- The distinct opaque colours actually present in the sprite the renderer
--- would draw for `graphicsId`, most common first.  This reads the sprite the
--- renderer uses (so it reflects the palette override, not the module's own
--- tables), and the override keeps its ImageData in step with its texture.
local function drawnColours(OwSprites, graphicsId)
  local spr = OwSprites.getDraw and OwSprites.getDraw(graphicsId)
  if not spr then return nil end
  local data
  if spr.imageData then
    local ok, copy = pcall(function() return spr.imageData:clone() end)
    if ok then data = copy end
  end
  if not data then return nil end
  local counts = {}
  local okMap = pcall(function()
    data:mapPixel(function(_, _, r, g, b, a)
      if a > 0 then
        local key = string.format("%d,%d,%d",
          math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5),
          math.floor(b * 255 + 0.5))
        counts[key] = (counts[key] or 0) + 1
      end
      return r, g, b, a
    end)
  end)
  if not okMap then return nil end
  local list = {}
  for key, n in pairs(counts) do list[#list + 1] = { key = key, n = n } end
  table.sort(list, function(x, y)
    if x.n == y.n then return x.key < y.key end
    return x.n > y.n
  end)
  return list
end

--- Comma-joined colour set, for set comparisons.
local function colourSet(list)
  if not list then return nil end
  local keys = {}
  for _, e in ipairs(list) do keys[#keys + 1] = e.key end
  table.sort(keys)
  return table.concat(keys, " ")
end

local function rampSet(pal)
  if not pal then return nil end
  local keys = {}
  for _, c in ipairs(pal) do
    keys[#keys + 1] = string.format("%d,%d,%d", c[1], c[2], c[3])
  end
  table.sort(keys)
  return table.concat(keys, " ")
end

local function dominantRed(list)
  if not (list and list[1]) then return nil end
  return tonumber(list[1].key:match("^(%d+),"))
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Objects = require("src.core.game3.objects")
  local Player = require("src.core.game3.player")
  local Deoxys = require("src.core.game3.deoxys")
  local FieldEffects = require("src.core.game3.field_effects")
  local OwSprites = require("src.core.game3.ow_sprites")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then
    return finish()
  end

  local function goTo(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "up" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "up"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "up"
    U.wait(30)
    local Preview = package.loaded["src.ui.game3.map_preview_screen"]
    for _ = 1, 240 do
      if not (Preview and Preview.isActive and Preview.isActive()) then break end
      U.wait(5)
    end
    U.wait(60)
  end

  -- Stand one tile south of the rock's starting position (field_specials.c
  -- COORDS[1] == {15,12}) so it is on camera.
  goTo(MAP, 15, 13, "up")

  local rock, rockId = Deoxys.resolveRockObject()
  result(rock ~= nil, "the Birth Island meteorite object is on the map")
  if not rock then
    U.shot(game, DIR .. "/00_no_rock.png")
    return finish()
  end
  U.log("rock localId=" .. tostring(rockId) ..
    " graphicsId=" .. tostring(rock.graphicsId) ..
    " cell=(" .. tostring(rock.cellX or rock.x) .. "," ..
    tostring(rock.cellY or rock.y) .. ")")
  result(tonumber(rock.graphicsId) == METEORITE,
    "the rock uses OBJ_EVENT_GFX_METEORITE (106), got " ..
    tostring(rock.graphicsId))

  U.shot(game, DIR .. "/01_position_0.png")

  local gid = tonumber(rock.graphicsId)
  local base = OwSprites.get(gid)
  result(base ~= nil and base.imageData ~= nil,
    "the meteorite sprite keeps its decoded pixels for palette swaps")

  local before = drawnColours(OwSprites, gid)
  U.log("position 0 drawn colours: " .. tostring(colourSet(before)))
  result(colourSet(before) == rampSet(Deoxys.sourcePalette()),
    "position 0 draws the source grey ramp " ..
    tostring(rampSet(Deoxys.sourcePalette())) ..
    ", got " .. tostring(colourSet(before)))

  -- ---------------------------------------------------------------- the ramp
  -- Ten successful interactions walk the rock to position 10; the eleventh
  -- awakens Deoxys (handled by the script, not here).
  local seen, reds = {}, {}
  for step = 1, 10 do
    Deoxys.interact(session)
    U.wait(45) -- let the move field effect finish
    local colours = drawnColours(OwSprites, gid)
    seen[step] = colourSet(colours)
    reds[step] = dominantRed(colours)
    U.log(string.format("position %d: key=%s colours=%s", step,
      tostring(OwSprites.objectPaletteKey(gid)), tostring(seen[step])))
    U.shot(game, string.format("%s/02_position_%02d.png", DIR, step))
  end

  result(seen[1] ~= seen[10],
    "the rock's drawn colours change across the puzzle")

  local monotonic = true
  for step = 2, 10 do
    if not (reds[step] and reds[step - 1] and reds[step] >= reds[step - 1]) then
      monotonic = false
      U.log(string.format("red went backwards at step %d: %s -> %s",
        step, tostring(reds[step - 1]), tostring(reds[step])))
    end
  end
  result(monotonic, "the rock reddens monotonically across the ten steps")

  result(seen[10] == rampSet(Deoxys.palette(10)),
    "position 10 draws the awakened red ramp " ..
    tostring(rampSet(Deoxys.palette(10))) ..
    ", got " .. tostring(seen[10]))

  -- ------------------------------------------------------------- the shatter
  local anim = FieldEffects.startDestroyDeoxysRock(rockId)
  result(anim ~= nil, "startDestroyDeoxysRock created the shatter animation")
  if anim then
    U.wait(30)
    result(anim.state == "shake",
      "the rock shakes before breaking, got " .. tostring(anim.state))
    U.shot(game, DIR .. "/03_shatter_shake.png")

    -- Task_DeoxysRockCameraShake runs for 120 frames, then the shards fly for
    -- only ~16 frames, so poll instead of guessing at a delay.
    for _ = 1, 200 do
      if anim.state ~= "shake" then break end
      U.wait(1)
    end
    result(anim.state == "shatter",
      "the animation reached the shatter state, got " .. tostring(anim.state))

    local sheet = FieldEffects._sheets["deoxys_rock_fragments"]
    result(sheet ~= nil and sheet ~= false,
      "the rock fragment sheet loaded (4 x 8x8)")
    U.shot(game, DIR .. "/04_shatter_fragments.png")

    -- The white flash must be a *background* veil (pret blends PALETTES_BG
    -- only), so the shards stay visible on top of it.
    local frag04 = fragPixels(DIR .. "/04_shatter_fragments.png")
    U.log("  fragment pixels on screen at the shatter frame: " .. frag04)
    result(frag04 > 0,
      "the shards are visible through the shatter flash, got " ..
      frag04 .. " px (0 means the flash covered them)")

    local alive = 0
    for _, f in ipairs(anim.frags or {}) do
      if not f.off then alive = alive + 1 end
      U.log(string.format("  frag frame=%s at (%d,%d) off=%s",
        tostring(f.frame), math.floor(f.x), math.floor(f.y), tostring(f.off)))
    end
    result(#(anim.frags or {}) == 4 and alive > 0,
      "four shards are flying, " .. alive .. " still on screen")

    -- Only a frame or two later: pret destroys a fragment once it leaves the
    -- 244x168 display, and at 16px/frame a shard crosses the whole screen in
    -- ~8 frames, so a longer wait would correctly find an empty screen.
    U.wait(1)
    U.shot(game, DIR .. "/05_shatter_spread.png")
    local frag05 = fragPixels(DIR .. "/05_shatter_spread.png")
    U.log("  fragment pixels on screen once they have spread: " .. frag05)
    result(frag05 > 0,
      "the shards are still flying a few frames later, got " .. frag05 .. " px")
  end

  finish()
end
