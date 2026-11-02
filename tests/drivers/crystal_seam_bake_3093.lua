-- engine/overworld/load_map_part.asm:1
local U = require("tests.drivers.util")
local World = require("src.world.gen2.World")
local Map = require("src.world.gen2.Map")
local BorderFill = require("src.world.gen2.BorderFill")
local GbcPalette = require("src.render.GbcPalette")
local Palettes = require("src.world.gen2.Palettes")
local PixelCanvas = require("src.render.PixelCanvas")
local TileAttrs = require("src.world.gen2.TileAttrs")
local Assets = require("src.render.Assets")

local function referenceBake(self, map, daytime, flicker)
  local atlas, tileset = self:atlasFor(map.def)
  if not atlas or not tileset then return nil end
  local blocks = tileset.blocks
  local tilesPerRow = tileset.tilesPerRow or 16
  local canvas = PixelCanvas.new(map.width * 32, map.height * 32, "nearest")
  local quads = {}
  local crystal = self:isCrystal()
  local function quadFor(tile)
    if crystal then
      local attr = TileAttrs.forTile(tileset, tile)
      return TileAttrs.quadFor(atlas, tile, attr, tilesPerRow, quads)
    end
    local q = quads[tile]
    if q then return q end
    q = love.graphics.newQuad((tile % tilesPerRow) * 8,
      math.floor(tile / tilesPerRow) * 8, 8, 8, atlas:getDimensions())
    quads[tile] = q
    return q
  end
  local tilePalettes = tileset.tilePalettes
  local bgSet = self.palettes and daytime
    and Palettes.bgSet(self.palettes, map.def, daytime) or nil
  if bgSet and daytime == "DARK" then
    bgSet = Palettes.withCaveFlicker(bgSet, flicker or 1)
  end
  local colored = bgSet and tilePalettes and GbcPalette.available()
  local clearColor = { 0.15, 0.55, 0.25 }
  if bgSet and bgSet[1] and bgSet[1][1] then
    local c = GbcPalette.color(bgSet[1], 1)
    clearColor = { c[1] / 255, c[2] / 255, c[3] / 255 }
  end
  local function drawTiles(slot)
    for by = 0, map.height - 1 do
      for bx = 0, map.width - 1 do
        local blockId = BorderFill.blockFor(
          map.blocks[by * map.width + bx + 1], map.borderBlock)
        local block = blocks and blocks[(blockId or 0) + 1]
        if block then
          for i = 0, 15 do
            local tile = block[i + 1] or 0
            local tileSlot = crystal
              and TileAttrs.paletteSlot(tileset, tile)
              or (tilePalettes and tilePalettes[tile + 1] or 1)
            if not slot or tileSlot == slot then
              local tx = bx * 32 + (i % 4) * 8
              local ty = by * 32 + math.floor(i / 4) * 8
              if crystal then
                TileAttrs.drawFlippedTile(atlas, quadFor(tile), tx, ty,
                  TileAttrs.forTile(tileset, tile))
              else
                love.graphics.draw(atlas, quadFor(tile), tx, ty)
              end
            end
          end
        end
      end
    end
  end
  canvas:renderTo(function()
    love.graphics.clear(clearColor[1], clearColor[2], clearColor[3], 1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.push()
    love.graphics.origin()
    if colored then
      for slot = 1, 8 do
        GbcPalette.with(bgSet[slot], function() drawTiles(slot) end)
      end
    else
      drawTiles(nil)
    end
    love.graphics.pop()
  end)
  return canvas, bgSet
end

local PARITY = { "ROUTE_29", "CHERRYGROVE_CITY", "ROUTE_30", "ROUTE_31",
  "VIOLET_CITY", "NEW_BARK_TOWN", "GOLDENROD_CITY", "ROUTE_34", "ILEX_FOREST",
  "ECRUTEAK_CITY" }

local TOUR = { "NEW_BARK_TOWN", "ROUTE_29", "CHERRYGROVE_CITY", "ROUTE_30",
  "ROUTE_31", "VIOLET_CITY", "ROUTE_32", "ROUTE_33", "AZALEA_TOWN", "ROUTE_34",
  "GOLDENROD_CITY", "ROUTE_35", "ROUTE_36", "ROUTE_37", "ECRUTEAK_CITY",
  "ROUTE_38", "ROUTE_39", "OLIVINE_CITY", "ROUTE_42", "MAHOGANY_TOWN",
  "ROUTE_43", "LAKE_OF_RAGE", "ROUTE_44", "BLACKTHORN_CITY" }

return function(game)
  local deadline = love.timer.getTime() + 28
  local speed, volume = game.speedOverride, love.audio.getVolume()
  local writes = {}
  for _, key in ipairs({ "writeSave", "writeOptions", "persistOptions" }) do
    writes[key] = rawget(game, key)
    game[key] = function() end
  end
  local fails = 0
  local function label(ok, name, detail)
    if not ok then fails = fails + 1 end
    print((ok and "PASS " or "FAIL ") .. name
      .. (detail ~= nil and (" (" .. tostring(detail) .. ")") or ""))
    return ok
  end
  local function check()
    assert(love.timer.getTime() < deadline, "28 second driver deadline")
  end
  local function wait(n) for _ = 1, n do check(); U.wait(1) end end
  local function settle(predicate, what)
    for _ = 1, 3600 do
      check()
      if predicate() then return end
      wait(1)
    end
    error("bounded settle failed: " .. what)
  end
  local function top() return game.stack:top() end
  local bake = World.bakeMapImage
  local bakes = 0
  local stepWrapped
  local draw, imageData = World.draw, Assets.imageData
  local drawing, counting, recolors = false, false, {}

  local ok, err = xpcall(function()
    local out = assert(os.getenv("POKEPORT_SHOT_DIR"), "POKEPORT_SHOT_DIR required")
    love.audio.setVolume(0)
    game.speedOverride = 200
    local world = game.world
    settle(function()
      return world and world.map and not top() and not world:busy()
    end, "field ready")

    local function same(mapId, daytime, flicker)
      local def = world.maps[mapId]
      local tileset = def and world.tilesets[def.tileset]
      if not tileset then return false, "missing " .. mapId end
      local map = Map.new(def, tileset)
      local a = referenceBake(world, map, daytime, flicker)
      local b = world:bakeMapImage(map, daytime, flicker)
      if not (a and b) then return false, "no canvas " .. mapId end
      local equal = a:newImageData():getString() == b:newImageData():getString()
      a:release()
      b:release()
      return equal, mapId
    end
    local mismatched = {}
    for _, id in ipairs(PARITY) do
      for _, daytime in ipairs({ "MORN", "DAY", "NITE" }) do
        local equal, why = same(id, daytime, 1)
        if not equal then mismatched[#mismatched + 1] = why .. "/" .. daytime end
      end
    end
    for _, flicker in ipairs({ 1, 2 }) do
      local equal, why = same("DARK_CAVE_VIOLET_ENTRANCE", "DARK", flicker)
      if not equal then mismatched[#mismatched + 1] = why .. "/DARK" .. flicker end
    end
    local equal, why = same("ROUTE_29", nil, 1)
    if not equal then mismatched[#mismatched + 1] = why .. "/plain" end
    label(#mismatched == 0, "3093_bake_identical_to_8_pass",
      #mismatched > 0 and table.concat(mismatched, ",") or (#PARITY .. " maps x3 daytimes + cave + plain"))

    World.bakeMapImage = function(...)
      bakes = bakes + 1
      return bake(...)
    end
    local crossings = {}
    local origStep = world.step
    stepWrapped = true
    world.step = function(w)
      local before, from = bakes, w.map and w.map.id
      origStep(w)
      local to = w.map and w.map.id
      if from and to and from ~= to then
        crossings[#crossings + 1] = { from = from, to = to, bakes = bakes - before }
      end
    end

    World.draw = function(...)
      drawing = true
      local results = { pcall(draw, ...) }
      drawing = false
      if not results[1] then error(results[2], 0) end
      return unpack(results, 2)
    end
    Assets.imageData = function(path, ...)
      if drawing and counting then recolors[#recolors + 1] = tostring(path):match("[^/]+$") end
      return imageData(path, ...)
    end

    local function drained()
      return world.bakeQueue == nil or (#world.bakeQueue == 0 and not world.bakeHold)
    end

    local function cross(mapId, x, y, dir, target, shot)
      world:warpToMapId(mapId, x, y, dir)
      settle(function()
        return world.map.id == mapId and not world:busy() and not top()
      end, "warp " .. mapId)
      settle(drained, "bake queue drained on " .. mapId)
      label(true, "3093_queue_drained_" .. mapId)
      wait(120)
      local seen = #crossings
      game.input.state[dir] = true
      for _ = 1, 600 do
        check()
        table.insert(game.input.pressQueue, dir)
        U.wait(1)
        if world.map.id == target then break end
      end
      game.input.state[dir] = false
      local hit = crossings[seen + 1]
      label(hit ~= nil and hit.to == target and hit.bakes == 0,
        "3093_no_bake_on_crossing_" .. mapId .. "_to_" .. target,
        hit and (hit.from .. "->" .. hit.to .. " bakes=" .. hit.bakes) or "no crossing")
      settle(function() return not world:busy() end, "walk settled")
      game.speedOverride = speed
      label(U.still(game, out .. "/" .. shot), "3093_shot_" .. target)
      game.speedOverride = 200
    end

    local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
    local function route(map, sx, sy, goal, occupied)
      local start = sx .. "," .. sy
      local prev, queue, head = { [start] = false }, { { sx, sy } }, 1
      while head <= #queue do
        local c = queue[head]
        head = head + 1
        if goal(c[1], c[2]) then
          local path, k = {}, c[1] .. "," .. c[2]
          while prev[k] do
            table.insert(path, 1, prev[k].dir)
            k = prev[k].from
          end
          return path
        end
        for _, dir in ipairs({ "up", "left", "right", "down" }) do
          local d = DELTA[dir]
          local nx, ny = c[1] + d[1], c[2] + d[2]
          local k = nx .. "," .. ny
          if prev[k] == nil and map:isWalkable(nx, ny) and map:stepPermitted(c[1], c[2], dir)
              and not map:warpAtCell(nx, ny) and not (occupied and occupied[k]) then
            prev[k] = { from = c[1] .. "," .. c[2], dir = dir }
            queue[#queue + 1] = { nx, ny }
          end
        end
      end
    end
    local function stepOnce(dir)
      local p = world.player
      local x, y, id = p.cellX, p.cellY, world.map.id
      for _ = 1, 60 do
        check()
        world.wildCooldown = 1e9
        U.hold(game, dir, 1)
        if world.map.id ~= id or p.cellX ~= x or p.cellY ~= y then
          settle(function() return not p.moving and not world:busy() and not top() end, "step")
          return true
        end
      end
      return false
    end
    local function walkTo(goal, what)
      for _ = 1, 20 do
        local occupied = {}
        for _, npc in ipairs(world.npcs or {}) do
          if npc.cellX then occupied[npc.cellX .. "," .. npc.cellY] = true end
        end
        local p = world.player
        local path = route(world.map, p.cellX, p.cellY, goal, occupied)
        if not path then error("no path to " .. what) end
        local done = true
        for _, dir in ipairs(path) do
          if not stepOnce(dir) then done = false break end
        end
        if done then return end
      end
      error("walk stuck: " .. what)
    end

    local function walkInto(fromId, sx, sy, dir, toId)
      local def = world.maps[fromId]
      local fromMap = Map.new(def, world.tilesets[def.tileset])
      local toDef = world.maps[toId]
      local toMap = Map.new(toDef, world.tilesets[toDef.tileset])
      local conn = def.connections[dir == "up" and "north" or dir == "down" and "south"
        or dir == "left" and "west" or "east"]
      local d = DELTA[dir]
      local function edge(x, y)
        if fromMap:inBounds(x + d[1], y + d[2]) then return false end
        local lx, ly = Map.connectionLanding(toDef, conn, dir, x, y)
        return toMap:isWalkable(lx, ly)
      end
      local start
      for r = 0, 8 do
        for dx = -r, r do
          for dy = -r, r do
            local x, y = sx + dx, sy + dy
            if not start and math.max(math.abs(dx), math.abs(dy)) == r
                and fromMap:isWalkable(x, y) and not fromMap:warpAtCell(x, y)
                and route(fromMap, x, y, edge) then
              start = { x, y }
            end
          end
        end
      end
      assert(start, "no start cell on " .. fromId)
      world:warpToMapId(fromId, start[1], start[2], dir)
      settle(function()
        return world.map.id == fromId and not world:busy() and not top()
      end, "warp " .. fromId)
      world.checkTrainerBattle = function() return false end
      require("src.core.gen2.Phone").state(game.save).specialCall = 0
      wait(240)
      recolors = {}
      counting = true
      game.speedOverride = 4
      walkTo(edge, fromId .. " edge")
      for _ = 1, 4 do
        if world.map.id == toId then break end
        stepOnce(dir)
      end
      assert(world.map.id == toId, "did not reach " .. toId)
      local p = world.player
      local entry = d[1] * p.cellX + d[2] * p.cellY
      local far = entry
      route(toMap, p.cellX, p.cellY, function(x, y)
        far = math.max(far, d[1] * x + d[2] * y)
        return false
      end)
      far = math.min(far, entry + 12)
      walkTo(function(x, y) return d[1] * x + d[2] * y >= far end, toId .. " far side")
      wait(30)
      counting = false
      game.speedOverride = 200
      world.checkTrainerBattle = nil
      label(#recolors == 0, "3093_no_sprite_bake_in_draw_walking_into_" .. toId,
        #recolors .. (#recolors > 0 and (": " .. table.concat(recolors, ",")) or ""))
    end
    cross("ROUTE_29", 3, 6, "left", "CHERRYGROVE_CITY", "3093_01_cherrygrove_seam.png")
    cross("CHERRYGROVE_CITY", 16, 3, "up", "ROUTE_30", "3093_02_route30_seam.png")
    cross("ROUTE_30", 6, 3, "up", "ROUTE_31", "3093_03_route31_seam.png")
    walkInto("OLIVINE_CITY", 20, 6, "up", "ROUTE_39")

    for _, id in ipairs(TOUR) do
      world:warpToMapId(id, 4, 4, "down")
      settle(function()
        return world.map.id == id and not world:busy() and not top()
      end, "tour " .. id)
    end
    local count = 0
    for _ in pairs(world.mapImages) do count = count + 1 end
    label(count <= World.MAP_IMAGE_CAP, "3093_map_images_bounded",
      count .. " <= " .. World.MAP_IMAGE_CAP)
  end, debug.traceback)

  World.bakeMapImage = bake
  World.draw, Assets.imageData = draw, imageData
  if stepWrapped and game.world then game.world.step = nil end
  game.speedOverride = speed
  love.audio.setVolume(volume)
  for _, key in ipairs({ "writeSave", "writeOptions", "persistOptions" }) do
    game[key] = writes[key]
  end
  if not ok then
    fails = fails + 1
    print("FAIL driver_error " .. tostring(err))
  end
  print(fails == 0 and "PASS crystal_seam_bake_3093"
    or ("FAIL crystal_seam_bake_3093 " .. fails .. " failures"))
  love.event.quit(fails == 0 and 0 or 1)
  while true do coroutine.yield() end
end
