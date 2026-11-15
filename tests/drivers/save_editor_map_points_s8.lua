local U = require("tests.drivers.util")
return function(game)
  U.wait(20)
  package.path = package.path .. ";./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua"
  local App, path, tmp
  local dim, safe, osName, getTime = love.graphics.getDimensions, love.window.getSafeArea, love.system.getOS,
    love.timer.getTime
  local failures = 0
  local function pass(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failures = failures + 1 end
  end
  local clock = 1000
  love.timer.getTime = function() return clock end
  local ok, err = xpcall(function()
    App = require("tools.save-editor.App")
    local Gen, Kit = require("Gen"), require("Kit")
    local MapBrowser = require("MapBrowser")
    local Serializer = require("src.core.SaveSerializer")
    local version = require("src.core.GameVersion").get()
    local dir = assert(os.getenv("POKEPORT_SHOT_DIR"))
    tmp = os.tmpname()
    path = tmp .. "-map-s8.lua"
    local file = assert(io.open(path, "wb"))
    file:write(Serializer.encode(Gen.newGame(version, game.data))); file:close()
    App.load(path, { version = version, embedded = true })
    local S = App.getState()
    assert(S.save and not S.loadError and not S.missingCache, S.status)
    local generation = Gen.ofState(S)
    if generation == 2 then
      pass(type(S.save.player.name) == "string" and S.save.player.name ~= "",
        "the Gen 2 stub carries the cart's default name (" .. tostring(S.save.player.name) .. ")")
    end
    local maps = Gen.maps(S.data)
    local mapId
    for _, id in ipairs({ "PALLET_TOWN", "NEW_BARK_TOWN", "FR_PALLET_TOWN", "LITTLEROOT_TOWN" }) do
      if maps[id] then mapId = id; break end
    end
    if not mapId then
      local ids = {}
      for id in pairs(maps) do if id:find("TOWN", 1, true) then ids[#ids + 1] = id end end
      table.sort(ids)
      mapId = assert(ids[1], "no town map")
    end

    local W, H, platform = 390, 844, "Android"
    local audit
    local function render(name)
      love.graphics.getDimensions = function() return W, H end
      love.window.getSafeArea = function() return 0, 0, W, H end
      love.system.getOS = function() return platform end
      local canvas = love.graphics.newCanvas(W, H, { msaa = 0 })
      love.graphics.push("all")
      love.graphics.setCanvas(canvas)
      love.graphics.origin()
      love.graphics.setScissor()
      love.graphics.setShader()
      require("src.render.GameViewport").reset()
      love.graphics.clear(0, 0, 0, 1)
      Kit.audit = {}
      App.draw()
      audit = Kit.audit
      Kit.audit = nil
      love.graphics.setCanvas()
      love.graphics.pop()
      if name then
        local pixels = canvas:newImageData()
        local bytes = pixels:encode("png"):getString()
        pixels:release()
        local out = assert(io.open(dir .. "/" .. version .. "-" .. name .. ".png", "wb"))
        out:write(bytes); out:close()
      end
      canvas:release()
      love.graphics.getDimensions, love.window.getSafeArea, love.system.getOS = dim, safe, osName
    end
    local function control(label)
      for _, c in ipairs(audit or {}) do
        if c.class == "control" and c.label == label then return c end
      end
    end
    local function tap(x, y)
      App.mousepressed(x, y, 1)
      render()
    end
    local labels = { "Player", generation == 2 and "Spawn" or "Heal" }
    if generation == 1 then labels[3] = "Outdoor" end

    local function pickCell(map)
      local r = S._mapViewRect
      local hc = map.heightCells or map.height * 2
      local wc = map.widthCells or map.width * 2
      for cy = math.floor(hc * 0.75), 1, -1 do
        for cx = 2, wc - 2 do
          local sx = r.x + ((cx + 0.5) * 16 - S.mapCamX) * S.mapZoom
          local sy = r.y + ((cy + 0.5) * 16 - S.mapCamY) * S.mapZoom
          if not map:warpAtCell(cx, cy) and sx > r.x + 4 and sx < r.x + r.w - 4 and sy > r.y + 4
            and sy < r.y + r.h - 4 and not MapBrowser.insideOverlay(S, sx, sy) then
            return { cx = cx, cy = cy, x = sx, y = sy }
          end
        end
      end
    end

    local startMap, startX, startY = Gen.playerMap(S.save)
    local function view(tag, shotPrefix)
      Gen.setPlayerHere(S.save, startMap, startX, startY)
      S.save.lastHeal, S.save.lastOutdoor, S.save.spawn = nil, nil, nil
      S.save.healMap, S.save.healX, S.save.healY = nil, nil, nil
      S.tab, S.navPopup, S.editPopup = "map", nil, nil
      MapBrowser.select(S, mapId)
      render(); render()
      for _, label in ipairs(labels) do
        local c = control(label)
        local r = S._mapViewRect
        pass(c ~= nil and r ~= nil and c.x >= r.x and c.y >= r.y and c.x + c.w <= r.x + r.w and c.y + c.h <= r.y + r.h
          and c.h >= Kit.tapMin(), version .. " " .. tag .. " " .. label .. " button sits on the map at tap size")
      end
      pass(control("Set here") == nil, version .. " " .. tag .. " has no separate Set here card")
      clock = clock + 10
      local first = control(labels[2])
      tap(first.x + first.w / 2, first.y + first.h / 2)
      clock = clock + 1
      render(shotPrefix .. "_01_no_cell_reason")
      pass(S.toast and S.toast.kind == "info" and S.toast.text:find("Tap a cell first", 1, true) ~= nil
        and S.mapClickCell == nil, version .. " " .. tag .. " disabled button explains itself and selects nothing")

      local _, map = MapBrowser.preview(S)
      local pick = assert(pickCell(map), "no free cell")
      tap(pick.x, pick.y)
      pass(S.mapClickCell and S.mapClickCell.cx == pick.cx and S.mapClickCell.cy == pick.cy,
        version .. " " .. tag .. " tap selects a map cell")
      for i, label in ipairs(labels) do
        render()
        local c = control(label)
        clock = clock + 10
        tap(c.x + c.w / 2, c.y + c.h / 2)
        clock = clock + 1
        render(("%s_%02d_%s_toast"):format(shotPrefix, i + 1, label:lower()))
        pass(S.toast and S.toast.kind == "ok", version .. " " .. tag .. " " .. label .. " shows a green toast: "
          .. tostring(S.toast and S.toast.text))
        pass(S.mapClickCell and S.mapClickCell.cx == pick.cx and S.mapClickCell.cy == pick.cy,
          version .. " " .. tag .. " " .. label .. " tap does not fall through to the map")
      end
      return pick
    end

    local function verify(tag, pick)
      assert(App.save(), "save failed")
      local f = assert(io.open(path, "rb"))
      local saved = assert(Serializer.decode(f:read("*a")))
      f:close()
      local pm, px, py = Gen.playerMap(saved)
      pass(pm == mapId and px == pick.cx and py == pick.cy,
        ("%s %s exported player at %s (%d,%d)"):format(version, tag, tostring(pm), px or -1, py or -1))
      if generation == 3 then
        pass(saved.healMap == mapId and saved.healX == pick.cx and saved.healY == pick.cy,
          ("%s %s exported heal location %s (%s,%s)"):format(version, tag, tostring(saved.healMap),
            tostring(saved.healX), tostring(saved.healY)))
      elseif generation == 2 then
        pass(saved.spawn == mapId, ("%s %s exported spawn %s"):format(version, tag, tostring(saved.spawn)))
      else
        local heal, out = saved.lastHeal, saved.lastOutdoor
        pass(heal and heal.map == mapId and heal.x == pick.cx and heal.y == pick.cy,
          ("%s %s exported lastHeal %s"):format(version, tag, heal and heal.map or "nil"))
        pass(out and out.id == mapId and out.x == pick.cx and out.y == pick.cy,
          ("%s %s exported lastOutdoor %s"):format(version, tag, out and out.id or "nil"))
      end
    end

    S.mapSection, S.mapFocused = "view", false
    verify("phone", view("phone", "s8_phone"))
    S.mapFocused = true
    view("phone focused", "s8_phone_focused")
    S.mapFocused = false
    W, H, platform = 1360, 860, "OS X"
    verify("desktop", view("desktop", "s8_desktop"))
  end, debug.traceback)
  if App then App.unload() end
  love.graphics.getDimensions, love.window.getSafeArea, love.system.getOS = dim, safe, osName
  love.timer.getTime = getTime
  if path then
    os.remove(path)
    for _, backup in ipairs(require("tests.fs_io").globPrefix(path .. ".bak-")) do os.remove(backup) end
  end
  if tmp then os.remove(tmp) end
  if not ok then print("FAIL save_editor_map_points_s8: " .. tostring(err)) end
  love.event.quit((ok and failures == 0) and 0 or 1)
end
