return function(game)
  local U = dofile("tests/drivers/util.lua")
  local OW = require("src.world.OverworldController")
  local Assets = require("src.render.Assets")
  local MapLoader = require("src.world.MapLoader")
  local SpriteRenderer = require("src.render.SpriteRenderer")
  local Pokemon = require("src.pokemon.Pokemon")

  local failed = false
  local function pending()
    return SpriteRenderer.warmPending and SpriteRenderer.warmPending() or 0
  end
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failed = true end
  end

  local inDraw, counting, drawReads, crossingReads = false, false, 0, {}
  local realDraw = OW.draw
  OW.draw = function(...)
    inDraw = true
    local ok, err = pcall(realDraw, ...)
    inDraw = false
    if not ok then error(err, 0) end
  end
  local realImageData = Assets.imageData
  Assets.imageData = function(path, ...)
    if inDraw and counting then
      drawReads = drawReads + 1
      crossingReads[#crossingReads + 1] = tostring(path)
    end
    return realImageData(path, ...)
  end

  game.driverSpeed = 1
  U.wait(30)
  game.save.flags.EVENT_GOT_STARTER = true
  if #game.save.party == 0 then
    table.insert(game.save.party, Pokemon.new(game.data, "PIKACHU", 5))
  end
  game.save.repelSteps = 9999

  local SEAMS = {
    { "ROUTE_1", "up" },
    { "VIRIDIAN_CITY", "up" },
    { "VIRIDIAN_CITY", "left" },
    { "ROUTE_2", "up" },
  }

  local function clearStart(mapId, dir)
    local def = game.data.maps[mapId]
    local w, h = def.width * 2, def.height * 2
    local m = MapLoader.load(game.data, mapId)
    local span = (dir == "up" or dir == "down") and w or h
    for c = 0, span - 1 do
      local sx, sy
      if dir == "up" then sx, sy = c, 3
      elseif dir == "down" then sx, sy = c, h - 4
      elseif dir == "left" then sx, sy = 3, c
      else sx, sy = w - 4, c end
      local clear = true
      for k = 0, 3 do
        local cx = sx + (dir == "left" and -k or dir == "right" and k or 0)
        local cy = sy + (dir == "up" and -k or dir == "down" and k or 0)
        if not m:isWalkableCell(cx, cy) or m:isGrassCell(cx, cy) then
          clear = false
        end
      end
      if clear then return sx, sy end
    end
  end

  local crossings = 0
  for _, seam in ipairs(SEAMS) do
    local mapId, dir = seam[1], seam[2]
    local sx, sy = clearStart(mapId, dir)
    if not sx then
      result(false, "a clear lane to the " .. dir .. " seam of " .. mapId)
    else
      U.teleport(game, mapId, sx, sy, dir)
      local ow = game.overworld
      ow.rollEncounter = function() return nil end
      local settle = 0
      while settle < 240 and pending() > 0 do
        U.wait(1)
        settle = settle + 1
      end
      U.wait(60)
      local from = ow.map.id
      local before = drawReads
      counting = true
      local crossed = false
      for _ = 1, 120 do
        U.hold(game, dir, 1)
        if ow.map.id ~= from then crossed = true break end
      end
      if crossed then U.hold(game, dir, 40) end
      counting = false
      if crossed then crossings = crossings + 1 end
      U.log(("%s %s -> %s: %d sheet reads in draw while crossing, warm settled in %d frames")
        :format(mapId, dir, ow.map.id, drawReads - before, settle))
    end
  end

  OW.draw = realDraw
  Assets.imageData = realImageData
  result(crossings == #SEAMS, ("crossed every seam (%d/%d)"):format(crossings, #SEAMS))
  result(drawReads == 0,
    ("no sprite sheet is read for a palette bake inside the overworld draw while crossing (%d: %s)")
      :format(drawReads, table.concat(crossingReads, ", ")))
  result(SpriteRenderer.warmPending ~= nil and pending() == 0,
    "the sprite warm queue drains")
  love.event.quit(failed and 1 or 0)
end
