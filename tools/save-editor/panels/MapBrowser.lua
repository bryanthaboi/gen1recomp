-- Map browser: view any map, follow its warps, and set the save's spawn point
-- / remembered outdoor or heal spot by clicking cells on the rendered map.
-- Reuses the game's own MapLoader/TileRenderer/Warp so the editor's view
-- matches what the player would actually see.
--
-- Three columns: a searchable map list, the viewport, and the spawn
-- inspector.  Overlays are drawn in this order so the selection always wins:
--   cyan hollow  warp cell (clicking follows the warp)
--   red filled   the save's player position
--   green / amber  lastHeal / lastOutdoor
--   yellow hollow  the current click selection

local MapLoader = require("src.world.MapLoader")
local Warp = require("src.world.Warp")
local Theme = require("Theme")
local Ops = require("Ops")
local Gen = require("Gen")
local PAL = Theme.PAL

local MapBrowser = {}

local CELL = 16   -- the walk grid; a cell is 16px of map art

local function playerPos(S)
  local map, x, y = Gen.playerMap(S.save)
  return map, x or 0, y or 0
end

local function clampZoom(z)
  if z < 1 then return 1 end
  if z > 4 then return 4 end
  return z
end

-- Point the camera so (cx,cy) lands in the middle of the viewport.  The
-- viewport size is only known while drawing, so it is stashed on S.
local function centerOn(S, cx, cy)
  local vw = S._mapViewW or 480
  local vh = S._mapViewH or 432
  S.mapCamX = cx * CELL - vw / (2 * S.mapZoom)
  S.mapCamY = cy * CELL - vh / (2 * S.mapZoom)
end
MapBrowser.centerOn = centerOn

local function sortedMapIds(data)
  local ids = {}
  for id in pairs(Gen.maps(data)) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids
end

-- LAST_MAP warps resolve against the remembered outdoor spot; skip with a
-- status message if the save has none (fresh games, or old saves).  Mirrors
-- the game: leaving an OVERWORLD/PLATEAU map via a warp updates lastOutdoor
-- so building exits (Indigo lobby, Route 22 Gate, ...) return to the map you
-- entered from.
local OUTSIDE_TILESETS = { OVERWORLD = true, PLATEAU = true }

local function goToWarp(S, warp)
  local def = warp.def
  if Gen.of(S.save) == 3 or Gen.of(S.save) == 2 then
    local dest = def.destMap or def.map
    if dest then
      S.mapId = dest
      S.mapClickCell = nil
      S._mapCenteredFor = dest
      S.status = "Followed warp to " .. tostring(dest)
    else
      S.status = "Warp has no destination map"
    end
    return
  end
  local fromMap = Gen.maps(S.data)[S.mapId]
  if fromMap and OUTSIDE_TILESETS[fromMap.tileset]
     and def.destMap ~= "LAST_MAP" and def.destMap ~= S.mapId then
    S.save.lastOutdoor = { id = S.mapId, x = def.x, y = def.y }
  end
  if def.destMap == "LAST_MAP" and not S.save.lastOutdoor then
    S.status = "Can't follow warp: no remembered outdoor map (lastOutdoor unset)"
    return
  end
  local ok, destMap, dx, dy = pcall(Warp.destination, S.data, def, S.save.lastOutdoor)
  if not ok then
    S.status = "Warp failed: " .. tostring(destMap)
    return
  end
  S.mapId = destMap
  S.mapClickCell = nil
  centerOn(S, dx, dy)
  -- claim the lazy first-draw centering below, so it does not immediately
  -- re-centre the destination map and lose the warp's landing cell
  S._mapCenteredFor = destMap
  S.status = "Followed warp to " .. destMap
end

-- Screen-space point inside the viewport -> map cell, or nil if the point is
-- outside the viewport or off the edge of the map.
local function cellAtScreen(S, map, Kit, vx, vy, vw, vh)
  if Kit.mouseX < vx or Kit.mouseX >= vx + vw
     or Kit.mouseY < vy or Kit.mouseY >= vy + vh then
    return nil
  end
  local wx = (Kit.mouseX - vx) / S.mapZoom + S.mapCamX
  local wy = (Kit.mouseY - vy) / S.mapZoom + S.mapCamY
  local cx, cy = math.floor(wx / CELL), math.floor(wy / CELL)
  if not map:inBounds(cx, cy) then return nil end
  return cx, cy
end

-- Wired from App.wheelmoved while the Map tab is active.
function MapBrowser.wheelmoved(S, dy)
  S.mapZoom = clampZoom((S.mapZoom or 2) + (dy > 0 and 0.25 or -0.25))
end

local PAN_KEYS = {
  up = { 0, -CELL }, w = { 0, -CELL },
  down = { 0, CELL }, s = { 0, CELL },
  left = { -CELL, 0 }, a = { -CELL, 0 },
  right = { CELL, 0 }, d = { CELL, 0 },
}

-- Wired from App.keypressed while the Map tab is active.
function MapBrowser.keypressed(S, key)
  local d = PAN_KEYS[key]
  if not d then return end
  S.mapCamX = (S.mapCamX or 0) + d[1]
  S.mapCamY = (S.mapCamY or 0) + d[2]
end

-- Select a map by id.  The camera is left to the first-draw centering in
-- draw(), which knows the viewport size and so can actually centre.
function MapBrowser.select(S, id)
  S.mapId = id
  S.mapClickCell = nil
  S._mapCenteredFor = nil
  S.status = "Viewing " .. id
end

-- Called inside the viewport's translate+scale transform, so every rect is
-- in map space: a cell is CELL units wide whatever the zoom is.
local function drawOverlays(S, map)
  local function cellRect(cx, cy)
    return cx * CELL - S.mapCamX, cy * CELL - S.mapCamY, CELL, CELL
  end
  love.graphics.setColor(0.27, 0.59, 1, 0.55)
  for _, wdef in ipairs(map.def.warps or {}) do
    love.graphics.rectangle("line", cellRect(wdef.x, wdef.y))
  end
  local playerMap, px, py = playerPos(S)
  if playerMap == S.mapId then
    love.graphics.setColor(1, 0.36, 0.4, 0.9)
    love.graphics.rectangle("fill", cellRect(px, py))
  end
  if Gen.of(S.save) == 3 then
    local healMap = S.save.healMap
    if healMap == S.mapId and S.save.healX and S.save.healY then
      love.graphics.setColor(0.24, 0.88, 0.54, 0.9)
      love.graphics.rectangle("line", cellRect(S.save.healX, S.save.healY))
    end
  elseif Gen.of(S.save) ~= 2 then
    local heal = S.save.lastHeal
    if heal and heal.map == S.mapId then
      love.graphics.setColor(0.24, 0.88, 0.54, 0.9)
      love.graphics.rectangle("line", cellRect(heal.x, heal.y))
    end
    local out = S.save.lastOutdoor
    if out and out.id == S.mapId then
      love.graphics.setColor(1, 0.8, 0.02, 0.9)
      love.graphics.rectangle("line", cellRect(out.x, out.y))
    end
  end
  if S.mapClickCell then
    love.graphics.setColor(1, 1, 0.35, 0.95)
    love.graphics.rectangle("line", cellRect(S.mapClickCell.cx, S.mapClickCell.cy))
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function MapBrowser.draw(S, Kit, x, y, w, h)
  local s = Kit.scale
  local gap = 20 * s
  local pad = 16 * s
  S.mapQuery = S.mapQuery or ""
  S.mapZoom = clampZoom(S.mapZoom or 2)

  -- Column plan (#715).  Side by side, the list and spawn cards claim ~470
  -- logical px before the viewport gets anything, and a portrait phone does
  -- not have it: the old layout answered by laying the viewport out at a
  -- negative width, which the scissor below rejected ("Can't set scissor
  -- with negative width and/or height") and took the whole editor down.
  -- Portrait now stacks the three cards vertically -- list, viewport, spawn
  -- inspector, each full width -- and every viewport dimension is clamped at
  -- zero so no window shape can reach the scissor with a negative rect.
  local listW = math.max(200 * s, math.min(260 * s, w * 0.2))
  local sideW = math.max(230 * s, math.min(300 * s, w * 0.22))
  local viewW = w - listW - sideW - 2 * gap
  local stacked = h > w or viewW < 260 * s
  local lr, vr, sr  -- list / viewport / spawn card rects
  if stacked then
    local capH = Kit.textHeight("caption")
    -- list: caption, search field, three rows, pager, the goto button
    local listH = math.min(math.max(0, h * 0.32),
      2 * pad + capH + 8 * s + 32 * s + 10 * s + 3 * 30 * s + 10 * s
      + 30 * s + 10 * s + 34 * s)
    -- spawns: caption, three 62px rows, the hint line
    local sideH = math.min(math.max(0, h * 0.34),
      2 * pad + capH + 12 * s + 3 * (62 * s + 8 * s) - 8 * s + 6 * s + 30 * s)
    lr = { x = x, y = y, w = w, h = listH }
    vr = { x = x, y = y + listH + gap, w = w,
           h = math.max(0, h - listH - sideH - 2 * gap) }
    sr = { x = x, y = y + h - sideH, w = w, h = sideH }
  else
    lr = { x = x, y = y, w = listW, h = h }
    vr = { x = x + listW + gap, y = y, w = math.max(0, viewW), h = h }
    sr = { x = x + w - sideW, y = y, w = sideW, h = h }
  end

  -- --------------------------------------------------------- the map list
  local listInner = lr.w - 2 * pad
  Kit.card(lr.x, lr.y, lr.w, lr.h)
  Kit.caption(lr.x + pad, lr.y + pad, "MAPS")
  local qy = lr.y + pad + Kit.textHeight("caption") + 8 * s
  S.mapQuery = Kit.textfield("map-query", lr.x + pad, qy, listInner, 32 * s,
    S.mapQuery, "search maps...")

  local ids = {}
  for _, id in ipairs(sortedMapIds(S.data)) do
    if S.mapQuery == "" or id:lower():find(S.mapQuery:lower(), 1, true) then
      ids[#ids + 1] = id
    end
  end

  local gotoH = 34 * s
  local gotoY = lr.y + lr.h - pad - gotoH
  local pagerH = 30 * s
  local pagerY = gotoY - 10 * s - pagerH
  local listTop = qy + 32 * s + 10 * s
  local mRowH = 26 * s
  local mGap = 4 * s
  local listBodyH = pagerY - 10 * s - listTop
  local perPage = math.max(1, math.floor(listBodyH / (mRowH + mGap)))
  S.mapListOffset = Ops.clamp(S.mapListOffset or 0, 0, math.max(0, #ids - perPage))
  -- wheel and touch drag reach the list too (#715): App routes the wheel to
  -- zoom on this tab, so the list rides Kit's drag path and the pager alone
  -- on desktop -- on a phone the drag is the difference between "stuck" and
  -- scrollable.
  S.mapListOffset = Kit.scroll(lr.x + pad, listTop, listInner, listBodyH,
    S.mapListOffset, #ids, perPage)

  for i = 1, math.min(perPage, #ids - S.mapListOffset) do
    local id = ids[S.mapListOffset + i]
    local ry = listTop + (i - 1) * (mRowH + mGap)
    if Kit.row(lr.x + pad, ry, listInner, mRowH, id == S.mapId, PAL.blue, 7 * s) then
      MapBrowser.select(S, id)
    end
    Kit.text("tiny", Kit.ellipsize("tiny", id, listInner - 18 * s),
      lr.x + pad + 9 * s, ry + (mRowH - Kit.textHeight("tiny")) / 2,
      id == S.mapId and PAL.heading or PAL.muted)
  end
  if #ids == 0 then
    Kit.text("mono", "no map matches", lr.x + pad + 9 * s, listTop + 8 * s, PAL.faint)
  end
  Kit.scrollbar(lr.x + pad, listTop, listInner, listBodyH,
    S.mapListOffset, #ids, perPage)
  S.mapListOffset = Kit.pager(lr.x + pad, pagerY, listInner, S.mapListOffset,
    #ids, perPage)
  if Kit.button(lr.x + pad, gotoY, listInner, gotoH, "Go to save location",
      { font = "small", radius = 9 * s }) then
    local pmap, px, py = playerPos(S)
    if pmap then
      MapBrowser.select(S, pmap)
      Ops.say(S, ("Jumped to %s (%d,%d)"):format(pmap, px, py))
    else
      Ops.say(S, "No player location on this save")
    end
  end

  -- ---------------------------------------------------------- the viewport
  Kit.card(vr.x, vr.y, vr.w, vr.h)
  local vpad = 18 * s
  local vx0 = vr.x + vpad
  local vinner = math.max(0, vr.w - 2 * vpad)
  local headH = 28 * s
  Kit.text("monoBig", tostring(S.mapId), vx0,
    vr.y + vpad + (headH - Kit.textHeight("monoBig")) / 2, PAL.heading)

  local ok, map
  if Gen.of(S.save) == 3 then
    local def = Gen.maps(S.data)[S.mapId]
    if def then
      local mw = def.width or 20
      local mh = def.height or 18
      local midLayout = def.midLayout
      local pair = def.pair or (midLayout and midLayout.pair)
      map = {
        id = S.mapId,
        def = def,
        width = mw,
        height = mh,
        widthCells = mw,
        heightCells = mh,
        warps = def.warps or {},
        inBounds = function(self, cx, cy)
          return cx >= 0 and cx < self.width and cy >= 0 and cy < self.height
        end,
        warpAtCell = function(self, cx, cy)
          for _, w in ipairs(self.warps or {}) do
            if w.x == cx and w.y == cy then
              return { def = w }
            end
          end
          return nil
        end,
        tileAtCell = function(self, cx, cy)
          if midLayout and midLayout.midAt then
            return midLayout:midAt(cx, cy) or 0
          end
          return 0
        end,
      }

      local okN, NativeTileset = pcall(require, "src.core.game3.tileset_native")
      if okN and NativeTileset and pair and midLayout and midLayout.midAt then
        local ts = NativeTileset.get(pair)
        if ts and ts.image then
          map.renderer = {
            draw = function(self, camX, camY)
              local viewW = S._mapViewW or 480
              local viewH = S._mapViewH or 432
              local zoom = S.mapZoom or 1
              local startCx = math.max(0, math.floor(camX / CELL) - 1)
              local endCx = math.min(mw - 1, math.ceil((camX + viewW / zoom) / CELL) + 1)
              local startCy = math.max(0, math.floor(camY / CELL) - 1)
              local endCy = math.min(mh - 1, math.ceil((camY + viewH / zoom) / CELL) + 1)

              love.graphics.setColor(1, 1, 1, 1)
              for cy = startCy, endCy do
                for cx = startCx, endCx do
                  local mid = midLayout:midAt(cx, cy)
                  if mid and mid >= 0 then
                    local slot = NativeTileset.slotFor(ts, mid)
                    local q = NativeTileset.quad(ts, slot)
                    if q then
                      love.graphics.draw(ts.image, q, cx * CELL - camX, cy * CELL - camY)
                    end
                    if ts.layered and ts.overImage then
                      local oq = NativeTileset.overQuad(ts, slot)
                      if oq then
                        love.graphics.draw(ts.overImage, oq, cx * CELL - camX, cy * CELL - camY)
                      end
                    end
                  end
                end
              end
            end
          }
        end
      end
      ok = true
    else
      ok, map = false, "unknown map"
    end
  elseif Gen.of(S.save) == 2 then
    local def = Gen.maps(S.data)[S.mapId]
    if def then
      local Map2 = require("src.world.gen2.Map")
      if type(def.width) ~= "number" or type(def.height) ~= "number" then
        ok, map = false, "incomplete map record (missing width/height)"
      else
        local tileset = Gen.tilesets(S.data)[def.tileset]
        ok, map = pcall(Map2.new, def, tileset or {})
        if ok and map and not map.renderer then
          local MapPreview = require("src.world.gen2.MapPreview")
          S._g2MapBaker = S._g2MapBaker or MapPreview.baker({
            tilesets = Gen.tilesets(S.data),
            gen2Roofs = S.data.gen2Roofs, roofs = S.data.roofs,
            gen2Palettes = S.data.gen2Palettes, palettes = S.data.palettes,
          })
          map.renderer = MapPreview.renderer(S._g2MapBaker, map)
        end
      end
    else
      ok, map = false, "unknown map"
    end
  else
    ok, map = pcall(MapLoader.load, S.data, S.mapId)
  end
  if not ok then
    Kit.text("mono", "Failed to load map: " .. tostring(map), vx0,
      vr.y + vpad + headH + 20 * s, PAL.red)
    return
  end

  local outdoor = Ops.isOutdoor(S, map)
  local oLabel = outdoor and "OUTDOOR" or "INDOOR"
  local oW = Kit.textWidth("tiny", oLabel) + 16 * s
  local oX = vx0 + Kit.textWidth("monoBig", tostring(S.mapId)) + 14 * s
  Theme.stroke(oX, vr.y + vpad + (headH - 20 * s) / 2, oW, 20 * s, 6 * s,
    PAL.cardBorder, 0.3, 1)
  Kit.textCenter("tiny", oLabel, oX,
    vr.y + vpad + (headH - 20 * s) / 2 + (20 * s - Kit.textHeight("tiny")) / 2, oW,
    outdoor and PAL.green or PAL.muted)

  -- zoom cluster, right-aligned in the viewport header.  The centre button
  -- is the one part with a long label; on a header too narrow to hold it
  -- beside the title it is dropped (its job is covered by the list's "Go to
  -- save location" plus the first-draw centering) rather than painted over
  -- the map name (#715).
  local centerW = 130 * s
  local zBtn = 32 * s
  local rightEdge = vx0 + vinner
  local zoomW = 2 * zBtn + 56 * s + 12 * s
  local pmap, px, py = playerPos(S)
  local showCenter = vinner >= zoomW + 10 * s + centerW + 160 * s
  if showCenter then
    if Kit.button(rightEdge - centerW, vr.y + vpad, centerW, headH, "Center on player",
        { kind = "accent", font = "small", radius = 7 * s }) then
      if pmap == S.mapId then
        centerOn(S, px, py)
        Ops.say(S, "Centred on the player")
      else
        Ops.say(S, "Player isn't on this map")
      end
    end
  end
  local zx = rightEdge - (showCenter and (centerW + 10 * s) or 0) - zoomW
  if Kit.stepper(zx, vr.y + vpad, zBtn, headH, "-", { radius = 7 * s }) then
    S.mapZoom = clampZoom(S.mapZoom - 0.5)
  end
  Kit.textCenter("mono", ("%.2fx"):format(S.mapZoom), zx + zBtn + 6 * s,
    vr.y + vpad + (headH - Kit.textHeight("mono")) / 2, 56 * s, PAL.muted)
  if Kit.stepper(zx + zBtn + 62 * s, vr.y + vpad, zBtn, headH, "+", { radius = 7 * s }) then
    S.mapZoom = clampZoom(S.mapZoom + 0.5)
  end

  local legendH = 22 * s
  local vy0 = vr.y + vpad + headH + 12 * s
  local vh0 = math.max(0, (vr.y + vr.h - vpad - legendH - 10 * s) - vy0)
  S._mapViewW, S._mapViewH = vinner, vh0

  -- First draw of a map: park the camera somewhere meaningful rather than at
  -- (0,0), which leaves a small map wedged in the top-left corner.  Deferred
  -- to here because centerOn needs the viewport size, which only exists once
  -- the panel has laid itself out.
  if S._mapCenteredFor ~= S.mapId then
    S._mapCenteredFor = S.mapId
    if pmap == S.mapId then
      centerOn(S, px, py)
    else
      centerOn(S, (map.widthCells or map.width or 10) / 2,
        (map.heightCells or map.height or 10) / 2)
    end
  end

  Theme.col(PAL.bgBot, 1)
  love.graphics.rectangle("fill", vx0, vy0, vinner, vh0, 12 * s, 12 * s)
  Theme.stroke(vx0, vy0, vinner, vh0, 12 * s, PAL.cardBorder, 0.28, 1)

  -- love_stub (headless tests) lacks push/pop/scale/scissor; skip the actual
  -- render there but keep all click/button logic below running.  The size
  -- guard is the #715 crash fix proper: an exhausted viewport (a window
  -- shorter or narrower than the chrome) renders nothing instead of handing
  -- LOVE a negative scissor rect.
  if love.graphics.push and vinner > 0 and vh0 > 0 then
    love.graphics.setScissor(math.floor(vx0), math.floor(vy0),
      math.ceil(vinner), math.ceil(vh0))
    love.graphics.push()
    love.graphics.translate(vx0, vy0)
    love.graphics.scale(S.mapZoom, S.mapZoom)
    if map.renderer and map.renderer.draw then
      map.renderer:draw(S.mapCamX, S.mapCamY)
    else
      local wc = map.widthCells or ((map.width or 8) * 2)
      local hc = map.heightCells or ((map.height or 8) * 2)
      for cy = 0, hc - 1 do
        for cx = 0, wc - 1 do
          if (cx + cy) % 2 == 0 then
            love.graphics.setColor(0.18, 0.22, 0.32, 1)
          else
            love.graphics.setColor(0.14, 0.17, 0.26, 1)
          end
          love.graphics.rectangle("fill",
            cx * CELL - S.mapCamX, cy * CELL - S.mapCamY, CELL, CELL)
        end
      end
      love.graphics.setColor(1, 1, 1, 1)
    end
    drawOverlays(S, map)
    love.graphics.pop()
    love.graphics.setScissor()
  end

  -- Touch pan (#715): arrows/WASD and the wheel are desktop-only inputs, so
  -- a held pointer drags the camera directly.  A plain tap still selects a
  -- cell via the click handling below; only movement while held pans.
  if Kit.mouseDown and not Kit.blockClicks
     and (S._mapDrag or Kit.hit(vx0, vy0, vinner, vh0)) then
    local d = S._mapDrag
    if not d then
      S._mapDrag = { mx = Kit.mouseX, my = Kit.mouseY,
                     camX = S.mapCamX, camY = S.mapCamY }
    else
      S.mapCamX = d.camX - (Kit.mouseX - d.mx) / S.mapZoom
      S.mapCamY = d.camY - (Kit.mouseY - d.my) / S.mapZoom
    end
  elseif not Kit.mouseDown then
    S._mapDrag = nil
  end

  -- click handling: warp cells jump the view, everything else selects
  if Kit.mouseClicked then
    local cx, cy = cellAtScreen(S, map, Kit, vx0, vy0, vinner, vh0)
    if cx then
      local warp = map:warpAtCell(cx, cy)
      if warp then
        goToWarp(S, warp)
      else
        S.mapClickCell = { cx = cx, cy = cy }
        S.status = string.format("Selected cell (%d,%d) on %s", cx, cy, S.mapId)
      end
    end
  end

  -- legend + the current selection readout
  local ly = vr.y + vr.h - vpad - legendH + 4 * s
  local lx = vx0
  local legend = {
    { PAL.blue, "warp", false },
    { PAL.red, "player", true },
    { PAL.green, "lastHeal", false },
    { PAL.yellow, "lastOutdoor", false },
  }
  for _, item in ipairs(legend) do
    local box = 10 * s
    if item[3] then
      Theme.col(item[1], 1)
      love.graphics.rectangle("fill", lx, ly + 2 * s, box, box)
    else
      Theme.stroke(lx, ly + 2 * s, box, box, 0, item[1], 1, 1.5 * s)
    end
    Kit.text("tiny", item[2], lx + box + 6 * s, ly, PAL.muted)
    lx = lx + box + 6 * s + Kit.textWidth("tiny", item[2]) + 16 * s
  end
  Kit.textRight("mono", S.mapClickCell
      and ("selected (%d,%d)"):format(S.mapClickCell.cx, S.mapClickCell.cy)
      or "click a cell to select it",
    vx0 + vinner, ly, PAL.caption)

  -- ------------------------------------------------------ spawn inspector
  local sx0 = sr.x
  Kit.card(sx0, sr.y, sr.w, sr.h)
  Kit.caption(sx0 + pad, sr.y + pad, "SPAWN POINTS")
  local sTop = sr.y + pad + Kit.textHeight("caption") + 12 * s
  local sInner = sr.w - 2 * pad
  local pmap2, px2, py2 = playerPos(S)
  local playerValue = pmap2 and ("%s (%d,%d)"):format(pmap2, px2, py2) or "unset"
  local spawns
  if Gen.of(S.save) == 3 then
    local healMap = S.save.healMap
    local healX = S.save.healX or 0
    local healY = S.save.healY or 0
    spawns = {
      { key = "PLAYER", color = PAL.red, value = playerValue,
        set = function() Ops.setPlayerHere(S) end },
      { key = "LAST HEAL", color = PAL.green,
        value = healMap and ("%s (%d,%d)"):format(healMap, healX, healY) or "unset",
        set = function() Ops.setLastHeal(S) end },
    }
  elseif Gen.of(S.save) == 2 then
    spawns = {
      { key = "PLAYER", color = PAL.red, value = playerValue,
        set = function() Ops.setPlayerHere(S) end },
      { key = "SPAWN", color = PAL.green,
        value = tostring(S.save.spawn or "SPAWN_HOME"),
        set = function() Ops.setLastHeal(S) end },
    }
  else
    local out = S.save.lastOutdoor
    local heal = S.save.lastHeal
    spawns = {
      { key = "PLAYER", color = PAL.red, value = playerValue,
        set = function() Ops.setPlayerHere(S) end },
      { key = "LAST HEAL", color = PAL.green,
        value = heal and ("%s (%d,%d)"):format(heal.map, heal.x, heal.y) or "unset",
        set = function() Ops.setLastHeal(S) end },
      { key = "LAST OUTDOOR", color = PAL.yellow,
        value = out and ("%s (%d,%d)"):format(out.id, out.x, out.y) or "unset",
        set = function() Ops.setLastOutdoor(S, map) end },
    }
  end
  local spawnH = 62 * s
  for i, sp in ipairs(spawns) do
    local ry = sTop + (i - 1) * (spawnH + 8 * s)
    Theme.row(sx0 + pad, ry, sInner, spawnH, 10 * s, 0.6)
    Kit.text("tiny", sp.key, sx0 + pad + 12 * s, ry + 11 * s, sp.color)
    local setW = 70 * s
    if Kit.button(sx0 + pad + sInner - 12 * s - setW, ry + 8 * s, setW, 26 * s,
        "Set here", { kind = "accent", font = "tiny", radius = 7 * s,
        enabled = S.mapClickCell ~= nil }) then
      sp.set()
    end
    Kit.text("mono", Kit.ellipsize("mono", sp.value, sInner - 24 * s),
      sx0 + pad + 12 * s, ry + spawnH - 10 * s - Kit.textHeight("mono"), PAL.muted)
  end

  local noteY = sTop + #spawns * (spawnH + 8 * s) + 6 * s
  Kit.textCenter("tiny",
    "Click a cell first. Warp cells follow the warp instead of selecting. " ..
    "Arrow keys / WASD pan, the wheel zooms.",
    sx0 + pad, noteY, sInner, PAL.caption)
end

return MapBrowser
