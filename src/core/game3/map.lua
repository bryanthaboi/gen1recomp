-- Game3 map loader. Owns Sevii enter: player, collision, EventObjects, Space scripts.
-- Talk/interact is Field.interact. Do not call host setMap/warpToMapId here:
-- MAPSETUP.WARP races ON_FRAME and wipes applymovement tracks (Bill intro).

local MapIds = require("src.core.game3.map_ids")
local ModRuntime = require("src.mods.Runtime")
local Connections = require("src.core.game3.connections")
local FieldModules = require("src.core.game3.field_modules")
local Map = {}

Map.current = nil
Map._announced = nil
Map.neighbors = {}
Map.neighborList = {}
Map._loadedLayouts = {}
Map._def = nil
Map._currentDef = nil
-- pokefirered/include/overworld.h:46
Map.MUSIC_DISABLE_OFF, Map.MUSIC_DISABLE_STOP, Map.MUSIC_DISABLE_KEEP = 0, 1, 2
-- pokefirered/src/overworld.c:103
Map.disableMusicChange = 0

function Map.currentDef()
  return Map._def or Map._currentDef
end

local function host_map_def(game, mapId)
  local data = game and game.data
  return data and data.maps and data.maps[mapId]
end

local function host_world(game)
  return game and (game.overworld or game.world)
end

function Map.loadNeighborsDepth1(game, primaryDef)
  Map.neighbors = {}
  Map.neighborList = {}
  if not primaryDef or type(primaryDef.connections) ~= "table" then
    return Map.neighbors
  end
  local data = game and game.data and game.data.maps
  if not data then return Map.neighbors end
  -- pokefirered/src/fieldmap.c:129
  for _, conn in ipairs(Connections.each(primaryDef)) do
    local mid = conn.map
    if data[mid] then
      local def = data[mid]
      Map.ensureMidLayout(game, mid, def)
      local n = {
        dir = conn.dir,
        map = mid,
        mapId = mid,
        def = def,
        offset = conn.offset,
      }
      Map.neighborList[#Map.neighborList + 1] = n
      Map.neighbors[conn.dir] = Map.neighbors[conn.dir] or n
      Map._loadedLayouts[mid] = true
    end
  end
  return Map.neighbors
end

local cell_size = Connections.sizeOf

Map.world = {}
Map._worldRoot = nil
Map._worldReachW = -1
Map._worldReachH = -1
Map.WORLD_HOPS = 2

function Map.computeWorld(maps, rootId, hops, reachW, reachH, ensure)
  local out = {}
  local rootDef = maps and maps[rootId]
  if not rootDef then return out end
  ensure = ensure or function() end
  ensure(rootId, rootDef)
  local rootW, rootH = cell_size(rootDef)
  local placed = { [rootId] = true }
  local queue = { { id = rootId, def = rootDef, ox = 0, oy = 0, hops = 0 } }
  local qi = 1
  local function inReach(def, ox, oy)
    if not (reachW and reachH) then return false end
    local w, h = cell_size(def)
    return ox + w > -reachW and ox < rootW + reachW
       and oy + h > -reachH and oy < rootH + reachH
  end
  while queue[qi] do
    local cur = queue[qi]
    qi = qi + 1
    local curW, curH = cell_size(cur.def)
    for _, conn in ipairs(Connections.each(cur.def)) do
      local dir = conn.dir
      local destId = conn.map
      local destDef = maps[destId]
      if destDef and destDef ~= rootDef and not placed[destId] then
        local offset = conn.offset
        ensure(destId, destDef)
        local destW, destH = cell_size(destDef)
        local ox, oy
        if dir == "north" then
          ox, oy = offset, -destH
        elseif dir == "south" then
          ox, oy = offset, curH
        elseif dir == "west" then
          ox, oy = -destW, offset
        elseif dir == "east" then
          ox, oy = curW, offset
        end
        if ox then
          ox, oy = cur.ox + ox, cur.oy + oy
          local reach = inReach(destDef, ox, oy)
          if cur.hops + 1 <= (hops or 0) or reach then
            placed[destId] = true
            out[#out + 1] = { id = destId, def = destDef, ox = ox, oy = oy }
            if cur.hops + 1 < (hops or 0) or reach then
              queue[#queue + 1] = {
                id = destId, def = destDef, ox = ox, oy = oy, hops = cur.hops + 1,
              }
            end
          end
        end
      end
    end
  end
  return out
end

function Map.refreshWorld(game, reachW, reachH, rootId)
  rootId = rootId or Map.current
  local maps = game and game.data and game.data.maps
  if not (rootId and maps) then
    Map.world = {}
    Map._worldRoot = nil
    return Map.world
  end
  reachW = math.floor(tonumber(reachW) or 0)
  reachH = math.floor(tonumber(reachH) or 0)
  if Map._worldRoot == rootId
      and Map._worldReachW == reachW and Map._worldReachH == reachH then
    return Map.world
  end
  Map.world = Map.computeWorld(maps, rootId, Map.WORLD_HOPS, reachW, reachH,
    function(id, def)
      Map.ensureMidLayout(game, id, def)
    end)
  for _, entry in ipairs(Map.world) do
    Map._loadedLayouts[entry.id] = true
  end
  local NativeTileset = package.loaded["src.core.game3.tileset_native"]
  if NativeTileset and NativeTileset.get then
    local sync = Map._warmPairs
    Map._warmPairs = nil
    local x0, y0, x1, y1 = Map.warmRect()
    local queue, seen, entries = {}, {}, {}
    for _, entry in ipairs(Map.world) do
      local pair = entry.def and (entry.def.pair or (entry.def.midLayout and entry.def.midLayout.pair))
      if sync and pair and not NativeTileset.prefetch and Map.warmNear(entry, x0, y0, x1, y1) then
        if NativeTileset.ready(pair) then pcall(NativeTileset.get, pair) end
      elseif type(pair) == "string" and not (NativeTileset._pairs and NativeTileset._pairs[pair]) then
        if not seen[pair] then
          seen[pair] = true
          queue[#queue + 1] = pair
          entries[pair] = {}
        end
        local list = entries[pair]
        list[#list + 1] = entry
      end
    end
    Map._warmQueue = queue[1] and queue or nil
    Map._warmEntries = queue[1] and entries or nil
    if NativeTileset._stream then
      local root = maps[rootId]
      local pair = root and (root.pair or (root.midLayout and root.midLayout.pair))
      if pair then seen[pair] = true end
      NativeTileset._stream:retain(seen)
    end
  end
  Map._worldRoot = rootId
  Map._worldReachW = reachW
  Map._worldReachH = reachH
  local FieldView = package.loaded["src.core.game3.field_view"]
  if FieldView then FieldView._nativeDirty = true end
  return Map.world
end

Map.WARM_MARGIN_SCREENS = 1
Map.WARM_BUDGET_SEC = 0.030
Map.WARM_MAX_DEFER = 3
Map._warmDefer = 0

function Map.warmNow(game, rootId)
  local FieldView = package.loaded["src.core.game3.field_view"]
  local Display = package.loaded["src.core.game3.display"]
  local vw = (FieldView and FieldView._viewW) or (Display and Display.W) or 240
  local vh = (FieldView and FieldView._viewH) or (Display and Display.H) or 160
  Map._warmPairs = nil
  local world = Map.refreshWorld(game, math.ceil(vw / 16), math.ceil(vh / 16), rootId)
  local Native = package.loaded["src.core.game3.tileset_native"]
  local def = host_map_def(game, rootId)
  local pair = def and (def.pair or (def.midLayout and def.midLayout.pair))
  if Native and pair and Native.ready(pair) then pcall(Native.get, pair) end
  local Ow = package.loaded["src.core.game3.ow_sprites"]
  if Ow and Ow.get and Ow.playerGraphicsId then
    local gid = Ow.playerGraphicsId(game)
    if gid then pcall(Ow.get, gid) end
    local Objects = package.loaded["src.core.game3.objects"]
    local x0, y0, x1, y1 = Map.warmRect()
    for _, eo in ipairs(Objects and Objects.forDraw and Objects.forDraw() or {}) do
      local x, y = eo.cellX or 0, eo.cellY or 0
      if eo.graphicsId and (not x0 or (x >= x0 and x <= x1 and y >= y0 and y <= y1)) then pcall(Ow.get, eo.graphicsId) end
    end
  end
  Map.stepWarm(game)
  return world
end

function Map.warmRect(margin)
  local P = package.loaded["src.core.game3.player"]
  local px, py = P and tonumber(P.cellX), P and tonumber(P.cellY)
  if not (px and py) then return nil end
  local FieldView = package.loaded["src.core.game3.field_view"]
  local Display = package.loaded["src.core.game3.display"]
  local vw = (FieldView and FieldView._viewW) or (Display and Display.W) or 240
  local vh = (FieldView and FieldView._viewH) or (Display and Display.H) or 160
  local cols, rows = math.ceil(vw / 16), math.ceil(vh / 16)
  margin = margin or Map.WARM_MARGIN_SCREENS
  local mx = math.ceil(cols / 2) + 1 + cols * margin
  local my = math.ceil(rows / 2) + 1 + rows * margin
  return px - mx, py - my, px + mx, py + my
end

function Map.warmNear(entry, x0, y0, x1, y1)
  if not x0 then return true end
  local layout = entry.def and entry.def.midLayout
  local w, h = layout and layout.width, layout and layout.height
  if not (w and h) then return true end
  local ox, oy = entry.ox or 0, entry.oy or 0
  return ox + w > x0 and ox <= x1 and oy + h > y0 and oy <= y1
end

function Map.stepWarm(game)
  local Stream = package.loaded["src.core.game3.asset_stream"]
  local Native = package.loaded["src.core.game3.tileset_native"]
  if Native and Native.prefetch then
    local x0, y0, x1, y1 = Map.warmRect()
    Map._warmScanTick = ((Map._warmScanTick or 0) + 1) % 4
    if Map._warmScanTick ~= 0 and Map._warmScanWorld == Map.world
        and Map._warmScanX == x0 and Map._warmScanY == y0
        and Map._warmScanX1 == x1 and Map._warmScanY1 == y1 then
      if Stream then Stream.update() end
      return true
    end
    Map._warmScanWorld = Map.world
    Map._warmScanX, Map._warmScanY, Map._warmScanX1, Map._warmScanY1 = x0, y0, x1, y1
    local vx0, vy0, vx1, vy1 = Map.warmRect(0)
    local wantedPairs = {}
    local priorities = {}
    local def = Map.currentDef()
    local currentPair = def and (def.pair or (def.midLayout and def.midLayout.pair))
    if currentPair then wantedPairs[currentPair], priorities[currentPair] = true, 0 end
    local queue = Map._warmQueue or {}
    for i = #queue, 1, -1 do
      local pair = queue[i]
      local near = not (Map._warmEntries and Map._warmEntries[pair])
      for _, entry in ipairs(Map._warmEntries and Map._warmEntries[pair] or {}) do
        if Map.warmNear(entry, x0, y0, x1, y1) then near = true end
        if Map.warmNear(entry, vx0, vy0, vx1, vy1) then priorities[pair] = 0 end
      end
      if Native._pairs[pair] then table.remove(queue, i)
      elseif near then wantedPairs[pair] = true end
    end
    if not queue[1] then Map._warmQueue = nil end
    if Native._stream then Native._stream:retain(wantedPairs) end
    for pair in pairs(wantedPairs) do Native.prefetch(pair, priorities[pair] or 1) end
    local Ow = package.loaded["src.core.game3.ow_sprites"]
    local Obj = package.loaded["src.core.game3.objects"]
    if Obj and Obj.prefetchMap then
      local wanted = {}
      for _, entry in ipairs(Map.world or {}) do
        if Map.warmNear(entry, x0, y0, x1, y1) then
          wanted[entry.id] = true
          Obj.prefetchMap(entry.id, entry.def, entry.id == Map.current and 0 or 1)
        end
      end
      Obj.retainPrepared(wanted)
    end
    if game and Ow and Ow.prefetch then
      local wanted = {}
      local function actor(eo, ox, oy)
        if not (eo.visible and not eo.hidden and not eo.invisible) then return end
        local x, y = (eo.cellX or 0) + (ox or 0), (eo.cellY or 0) + (oy or 0)
        if not x0 or (x >= x0 and x <= x1 and y >= y0 and y <= y1) then
          local gid = tonumber(eo.graphicsId)
          if gid then
            local visible = not vx0 or (x >= vx0 and x <= vx1 and y >= vy0 and y <= vy1)
            wanted[gid] = math.min(wanted[gid] or 1, visible and 0 or 1)
          end
        end
      end
      local Obj = package.loaded["src.core.game3.objects"]
      for _, eo in ipairs(Obj and Obj.forDraw and Obj.forDraw() or {}) do actor(eo) end
      local Ghosts = package.loaded["src.core.game3.ghosts"]
      for _, entry in ipairs(Map.world or {}) do
        if Map.warmNear(entry, x0, y0, x1, y1) then
          for _, eo in ipairs(Ghosts and Ghosts.forDraw(entry.id) or {}) do actor(eo, entry.ox, entry.oy) end
        end
      end
      local gid = Ow.playerGraphicsId(game)
      if gid then wanted[gid] = 0 end
      if Ow._stream then Ow._stream:retain(wanted) end
      for id, priority in pairs(wanted) do Ow.prefetch(id, priority) end
    end
    if game then require("src.core.game3.field_plan").prefetch(game) end
    if Stream then Stream.update() end
    return true
  end
  local queue = Map._warmQueue
  if not queue then return false end
  local NativeTileset = package.loaded["src.core.game3.tileset_native"]
  local timer = love and love.timer
  if timer and timer.getDelta and timer.getDelta() > Map.WARM_BUDGET_SEC
      and Map._warmDefer < Map.WARM_MAX_DEFER then
    Map._warmDefer = Map._warmDefer + 1
    return false
  end
  Map._warmDefer = 0
  local entries = Map._warmEntries or {}
  local x0, y0, x1, y1 = Map.warmRect()
  local i = 1
  while queue[i] do
    local pair = queue[i]
    if NativeTileset and (NativeTileset._pairs and NativeTileset._pairs[pair])
        or not (NativeTileset and NativeTileset.get) then
      table.remove(queue, i)
    else
      local near = not entries[pair]
      for _, entry in ipairs(entries[pair] or {}) do
        if Map.warmNear(entry, x0, y0, x1, y1) then near = true break end
      end
      if near then
        table.remove(queue, i)
        if NativeTileset.ready(pair) then
          pcall(NativeTileset.get, pair)
          if not queue[1] then Map._warmQueue = nil end
          return true
        end
      else
        i = i + 1
      end
    end
  end
  if not queue[1] then Map._warmQueue = nil end
  return false
end

function Map.overscanSlices()
  local slices = {}
  for _, n in ipairs(Map.neighborList or {}) do
    slices[#slices + 1] = { dir = n.dir, mapId = n.map or n.mapId, offset = n.offset }
  end
  return slices
end

local function fromNeighbor(n, nx, ny, primaryPair)
  if not n or not n.def then return nil end
  local L = n.def.midLayout
  if not L then return nil end
  if nx < 0 or ny < 0 or nx >= (L.width or 0) or ny >= (L.height or 0) then
    return nil
  end
  local pair = L.pair or n.def.pair
  return L:midAt(nx, ny), pair or primaryPair
end

local function fromDir(list, dir, cx, cy, w, h, primaryPair)
  for i = #list, 1, -1 do
    local n = list[i]
    if n.dir == dir and n.def and n.def.midLayout then
      local L = n.def.midLayout
      local offset = tonumber(n.offset) or 0
      local nx, ny
      if dir == "north" then
        nx, ny = cx - offset, (L.height or 0) + cy
      elseif dir == "south" then
        nx, ny = cx - offset, cy - h
      elseif dir == "west" then
        nx, ny = (L.width or 0) + cx, cy - offset
      else
        nx, ny = cx - w, cy - offset
      end
      local mid, pair = fromNeighbor(n, nx, ny, primaryPair)
      if mid ~= nil then return mid, pair end
    end
  end
end

--- Resolve a cell in current-map space, sampling connected neighbors when OOB
-- (pret VMap connection fill). Returns mid, sourcePair. OOB with no neighbor
-- falls through to primary border tiling.
function Map.worldMidAt(cx, cy, primaryDef)
  local layout = primaryDef and primaryDef.midLayout
  if not layout then return 0, nil end
  local w, h = layout.width or 0, layout.height or 0
  local primaryPair = layout.pair or primaryDef.pair

  if cx >= 0 and cy >= 0 and cx < w and cy < h then
    return layout:midAt(cx, cy), primaryPair
  end

  local list = Map.neighborList or {}

  -- pokefirered/src/fieldmap.c:129
  if cy < 0 then
    local mid, pair = fromDir(list, "north", cx, cy, w, h, primaryPair)
    if mid ~= nil then return mid, pair end
  elseif cy >= h then
    local mid, pair = fromDir(list, "south", cx, cy, w, h, primaryPair)
    if mid ~= nil then return mid, pair end
  end

  if cx < 0 then
    local mid, pair = fromDir(list, "west", cx, cy, w, h, primaryPair)
    if mid ~= nil then return mid, pair end
  elseif cx >= w then
    local mid, pair = fromDir(list, "east", cx, cy, w, h, primaryPair)
    if mid ~= nil then return mid, pair end
  end

  for _, entry in ipairs(Map.world) do
    local L = entry.def ~= primaryDef and entry.def and entry.def.midLayout
    if L then
      local nx, ny = cx - entry.ox, cy - entry.oy
      if nx >= 0 and ny >= 0 and nx < (L.width or 0) and ny < (L.height or 0) then
        return L:midAt(nx, ny), L.pair or entry.def.pair or primaryPair
      end
    end
  end

  return layout:midAt(cx, cy), primaryPair, true
end

--- Ensure mapDef.midLayout is bound (lazy; Dataset.hydrate usually did this).
function Map.ensureMidLayout(game, mapId, def)
  def = def or host_map_def(game, mapId)
  if not def then return nil end
  if def.midLayout then return def.midLayout end
  local Dataset = require("src.core.game3.dataset")
  if Dataset.attachMidLayouts and game and game.data and game.data.maps then
    Dataset.attachMidLayouts({ [mapId] = def })
  end
  return def.midLayout
end

-- pokeemerald/src/overworld.c:911
-- pokefirered/src/overworld.c:878
function Map.applyInitialAvatar(session, def, saved, previous)
  if not session then return end
  local Player = require("src.core.game3.player")
  if saved and (saved.surfing ~= nil or saved.underwater ~= nil) then
    Player.restoreAvatar(saved)
    return
  end
  local Flags = require("src.core.game3.scripting.flags")
  local version = session.version or require("src.core.game3.profile").active().id
  local cruiseId = Flags.forVersion(version).IDS.FLAG_SYS_CRUISE_MODE
  local cruise = cruiseId and Flags.getFlag(session, nil, cruiseId)
  local mapType = def and tonumber(def.mapType)
  local isRse = session and require("src.core.game3.profile").family(session) == "rse"
  local Collision = require("src.core.game3.collision")
  local surfable = Collision.isSurfable(Collision.behavior(Player.cellX, Player.cellY))
  local mapId = session and session.map or ""
  local seafoam = not isRse and (mapId == "FR_SEAFOAM_ISLANDS_B3F" or mapId == "FR_SEAFOAM_ISLANDS_B4F")
  Player.surfing, Player.underwater = false, false
  if cruise and mapType ~= 8 then
    Player.biking = false
    if mapType == 6 then Player.facing = "right" end
  elseif mapType == 5 then
    Player.underwater, Player.biking = true, false
  elseif surfable and not seafoam then
    Player.surfing, Player.biking = true, false
  end
  if previous and ((previous.underwater and Player.surfing)
      or (previous.surfing and Player.underwater)) then
    Player.facing = previous.facing
  end
end

function Map.load(mod, game, mapId, opts)
  opts = opts or {}
  if not MapIds.isGame3Map(mapId) then
    return nil, "not a game3 map"
  end
  if not opts.seamless then
    local StayMessage = package.loaded["src.ui.game3.message"]
    if StayMessage and StayMessage.closeStay then StayMessage.closeStay() end
    -- pokeemerald/src/overworld.c:2170
    local CamObj = package.loaded["src.core.game3.camera_object"]
    if CamObj and CamObj.reset then CamObj.reset() end
  end
  -- pret RestartWildEncounterImmunitySteps on LoadMap / LoadMapFromWarp: every
  -- map entry restarts the wild encounter grace period. Unconditional, so the
  -- seamless connection crossing between two routes resets it too.
  do
    local okE, Encounters = pcall(require, "src.core.game3.encounters")
    if okE and Encounters and Encounters.resetRateModifiers then
      Encounters.resetRateModifiers()
    end
    local okR, Roamer = pcall(require, "src.core.game3.roamer")
    if okR and Roamer and Roamer.move then
      local okRt, Runtime = pcall(require, "src.core.game3.runtime")
      local session = okRt and Runtime and Runtime.getSession and Runtime.getSession()
      if session and session.roamer and session.roamer.active then
        local fromMapId = Map._announced
        if require("src.core.game3.profile").family(session) == "rse" then
          if fromMapId ~= nil then
            -- pokeemerald/src/overworld.c:816
            Roamer.move(session, opts.seamless and "connection" or "warp", mapId)
          end
        elseif fromMapId ~= nil and fromMapId ~= mapId then
          local moveReason = (opts.teleport or opts.fly or opts.whiteout) and "warp_random" or "map_transition"
          Roamer.move(session, moveReason)
        elseif opts.teleport or opts.fly or opts.whiteout then
          Roamer.move(session, "warp_random")
        end
      end
    end
  end
  local Ghosts = require("src.core.game3.ghosts")
  local fromMapId = Map._announced
  if Map.current and Map.current ~= mapId then
    Ghosts.capture(Map.current)
  end
  if fromMapId and fromMapId ~= mapId and ModRuntime.wants("map.exited") then
    ModRuntime.emit("map.exited", { mapId = fromMapId, toMapId = mapId })
  end
  Map._announced = mapId
  Map.current = mapId
  Map._loadedLayouts = { [mapId] = true }
  -- overworld.c:792, overworld.c:759
  Map._worldRoot = nil

  local def = host_map_def(game, mapId)
  if not def then
    local okD, Dataset = pcall(require, "src.core.game3.dataset")
    if okD and Dataset and Dataset.map then
      def = Dataset.map(mapId)
    end
  end
  Map.ensureMidLayout(game, mapId, def)
  do
    local Rt = package.loaded["src.core.game3.runtime"]
    local sess = (Rt and Rt.getSession and Rt.getSession()) or (game and game.session)
    if def and sess and require("src.core.game3.profile").family(sess) == "rse" then
      local FV = package.loaded["src.core.game3.field_view"]
      if FV and FV._bgPalOverride then FV.setBgPaletteOverride(FV._bgPalOverride.slot, nil) end
      -- pokeemerald/src/field_effect.c:1546
      if FV and not opts.seamless then FV.setCameraPanning(0, 0) end
      local R = require("src.core.game3.rse.init")
      -- pokeemerald/src/fieldmap.c:82
      R.call("pyramid", "onMapLoad", nil, nil, nil, mapId, def, opts)
      -- pokeemerald/src/fieldmap.c:88
      R.call("trainerHill", "onMapLoad", nil, nil, nil, mapId, def, opts)
    end
  end
  Map._def = def
  Map._currentDef = def
  if opts.depth1Connections ~= false then
    Map.loadNeighborsDepth1(game, def)
  else
    Map.neighbors = {}
    Map.neighborList = {}
  end

  local world = host_world(game)
  local x = tonumber(opts.x) or 0
  local y = tonumber(opts.y) or 0
  local facing = opts.facing or "down"

  local Runtime = require("src.core.game3.runtime")
  if not Runtime.isActive or not Runtime.isActive() then
    if Runtime.ensureActiveForMap then
      Runtime.ensureActiveForMap(mod, game, mapId)
    end
  end

  local session = (Runtime.getSession and Runtime.getSession()) or (game and game.session)
  local save = game and game.save
  local Player = require("src.core.game3.player")
  local previousAvatar = { surfing = Player.surfing, underwater = Player.underwater, facing = Player.facing }
  local savedAvatar = session and session._savedAvatar
  if (opts.enterVia or Map._nextEnterVia) ~= "continue" or not savedAvatar
      or savedAvatar.map ~= mapId or savedAvatar.x ~= x or savedAvatar.y ~= y
      or (session and session._continueWarpDeferred) then
    savedAvatar = nil
  end
  local onCyclingRoad = Player.isOnCyclingRoad and Player.isOnCyclingRoad(session, x, y, def)
  local wasBiking = (Player.biking == true)
  if opts.initialLoad and not wasBiking then
    wasBiking = (session and session.biking == true) or (save and save.biking == true) or false
  end

  -- pokefirered/src/overworld.c:878 GetAdjustedInitialTransitionFlags
  local keepBike = false
  if wasBiking or onCyclingRoad then
    local allowed = def and def.bikingAllowed
    if allowed ~= nil then
      -- pokefirered/src/overworld.c:948 Overworld_IsBikingAllowed
      keepBike = (tonumber(allowed) or 0) ~= 0
    else
      local pair = def and (def.pair or (def.midLayout and def.midLayout.pair))
      keepBike = type(pair) == "string" and pair:find("outdoor", 1, true) ~= nil
    end
  end

  local isRse = session ~= nil and require("src.core.game3.profile").family(session) == "rse"
  if isRse and not opts.seamless and session.map then
    -- pokeemerald/src/overworld.c:542
    session.lastUsedWarp = { map = session.map, x = session.x, y = session.y }
  end
  if session then
    session.map = mapId
    session.x = x
    session.y = y
    session.facing = facing
    session.biking = keepBike
  end

  -- Keep save.position current for ferry exit / host save without setMap.
  if save then
    save.position = save.position or {}
    save.position.map = mapId
    save.position.x = x
    save.position.y = y
    save.position.facing = facing
    save.position.biking = keepBike
    save.biking = keepBike
  end

  if opts.seamless then
    -- Connection remap (pret LoadMapFromCameraTransition): keep mid-step motion.
    -- Caller parks one cell before landing and sets target toward landing.
    Player.cellX = x
    Player.cellY = y
    Player.px = x * 16
    Player.py = y * 16
    Player.facing = facing
  else
    Player.reset(x, y, facing)
  end
  -- pokefirered/src/overworld.c:2145 SetPlayerAvatarTransitionFlags
  Player.biking = keepBike

  local okFv, FieldView = pcall(require, "src.core.game3.field_view")
  if okFv and FieldView then FieldView._nativeDirty = true end
  -- pokeemerald/src/overworld.c:529, pokeemerald/src/overworld.c:815
  do
    local TilesetAnim = package.loaded["src.core.game3.tileset_anim"]
    local pair = def and (def.pair or (def.midLayout and def.midLayout.pair))
    if TilesetAnim and TilesetAnim._rse and TilesetAnim.enterMap and type(pair) == "string" then
      TilesetAnim.enterMap(pair, opts.seamless == true)
    end
  end

  -- Scripts/events before spawn so Objects.loadMap sees mapDef.objects.
  local Space = package.loaded["src.core.game3.scripting.space"]
    or require("src.core.game3.scripting.space")
  if Space.ensureBundle then Space.ensureBundle(mod or Runtime._mod) end
  if def and Space.attachEventsToMaps and game and game.data and game.data.maps then
    Space.attachEventsToMaps({ [mapId] = def }, Space.bundle)
  end

  -- pokefirered/src/fieldmap.c:93
  require("src.core.game3.field").clearMetatiles(def and def.midLayout)
  local Collision = require("src.core.game3.collision")
  if def then
    Collision.bindMap(game, mapId, def)
  else
    -- No def for this id.  Keeping the previous map's grid bound would validate
    -- movement against the map we just left; unbind so canEnter falls back to
    -- the host map (collision.lua: "Prefer owned grid; fall back to host map").
    Collision.clear()
  end

  Player.syncSavePosition(game)

  Map._warmPairs = not opts.seamless or nil
  -- pret GroundEffect_SpawnOnTallGrass when warping onto grass.
  if not opts.seamless then
    local onGrass = Collision.isGrass and Collision.isGrass(Player.cellX, Player.cellY)
    local okE, Encounters = pcall(require, "src.core.game3.encounters")
    if okE and Encounters and Encounters.noteGrass then
      Encounters.noteGrass(onGrass)
    end
    local okFx, FieldEffects = pcall(require, "src.core.game3.field_effects")
    if okFx and FieldEffects then
      if onGrass and FieldEffects.tallGrassAt then
        FieldEffects.tallGrassAt(Player.cellX, Player.cellY, true)
      elseif FieldEffects.clearTallGrass then
        FieldEffects.clearTallGrass()
      end
    end
  end

  -- Activate scripts (flag store) → spawn destination NPCs → ON_TRANSITION.
  -- pret order: never run setobjectxyperm against the previous map's localIds
  -- (Pallet sign-lady localId=1 was teleporting Mom on FR_PLAYERS_HOUSE_1F).
  local Field = require("src.core.game3.field")
  if not opts.seamless then
    Field.lock()
    -- pokeemerald/src/overworld.c:2134
    require("src.core.game3.virtual_objects").clear()
  end

  local Objects = require("src.core.game3.objects")
  -- pokefirered/src/overworld.c:800
  if fromMapId and (fromMapId ~= mapId or opts.heal) and FieldModules.enabled("vsSeeker", session) then
    require("src.core.game3.vs_seeker").mapReset(session)
  end
  local RsRematch = isRse and require("src.core.game3.rs.rematch")
  if RsRematch and RsRematch.enabled(session) then
    -- pokeruby/src/overworld.c:617
    RsRematch.tryUpdateRandomTrainerRematchesForMap(session, mapId)
  elseif isRse and require("src.core.game3.capabilities").gate(session, "match_call") then
    -- pokeemerald/src/overworld.c:801
    require("src.core.game3.rse.rematch").tryUpdateRandomTrainerRematchesForMap(session, mapId)
  end
  -- pokeemerald/src/overworld.c:802
  if session and require("src.core.game3.rtc").enabled(session) then
    require("src.core.game3.time_events").run(session)
  end
  if opts.keepScript and Space and Space.retarget then
    Space.retarget(mod or Runtime._mod, mapId, game, world)
  elseif Space and Space.activate then
    Space.activate(mod or Runtime._mod, mapId, game, world)
  end

  -- pokefirered/src/overworld.c:805
  local savedFlash = session and tonumber(session.flashLevel)
  if okFv and FieldView and FieldView.setDefaultFlashLevel then
    FieldView.setDefaultFlashLevel(game, mapId)
    -- pokefirered/src/overworld.c:1691 CB2_ContinueSavedGame
    if savedFlash and (opts.enterVia or Map._nextEnterVia) == "continue" then
      FieldView.setFlashLevel(savedFlash)
    end
  end

  if def then
    local seen = opts.seamless and Ghosts.visibleIds(mapId) or nil
    Objects.loadMap(game, mapId, def)
    if opts.carry then Objects.carryIn(opts.carry) end
    if opts.seamless then
      Objects.beginFadeIn(seen or {})
      Ghosts.openFadeWindow()
    end
    Ghosts.adopt(mapId)
  end
  -- pokefirered/src/overworld.c:771 / :808 TryRegenerateRenewableHiddenItems
  local okRen, Renewable = false, nil
  if FieldModules.enabled("renewableHiddenItems", session) then
    okRen, Renewable = pcall(require, "src.core.game3.renewable_hidden_items")
  end
  if okRen and Renewable and Renewable.tryRegenerate then
    Renewable.tryRegenerate(session, def and (def.group or (def.pair and def.pair[1])), def and (def.num or (def.pair and def.pair[2])), mapId)
  end
  -- pokefirered/src/overworld.c:809 SetCurrentAndNextWeather
  if def and def.weather ~= nil then
    local Weather = require("src.core.game3.weather")
    Weather.apply(def.weather, { seamless = opts.seamless,
      continue = isRse and (opts.enterVia or Map._nextEnterVia) == "continue" })
  end
  if isRse and not opts.seamless and def and require("src.core.game3.dataset").isOutdoorMapType(def.mapType) then
    -- pokeemerald/src/overworld.c:857
    local Flags = require("src.core.game3.scripting.flags")
    local flash = require("src.core.game3.field_semantics").flag(session, "flashActive")
    if flash and Space.store then Flags.setFlag(Space.store, nil, flash, false) end
  end
  -- pokefirered/src/overworld.c:769
  -- pokefirered/src/overworld.c:806
  require("src.core.game3.audio").setSavedSong(nil)
  if fromMapId == mapId then
    if opts.reason and ModRuntime.wants("map.reloaded") then
      ModRuntime.emit("map.reloaded", { mapId = mapId, reason = opts.reason or "reload" })
    end
  elseif ModRuntime.wants("map.entered") then
    ModRuntime.emit("map.entered", {
      mapId = mapId, map = def, fromMapId = fromMapId,
      via = opts.via or (opts.seamless and "connection")
        or (opts.heal and "respawn") or (fromMapId and "warp" or "boot"),
    })
  end
  -- pokefirered/src/overworld.c:1717
  local enterVia = opts.enterVia or Map._nextEnterVia
  Map._nextEnterVia = nil
  if Space and Space.runEnterScripts then
    local Weather = isRse and def and def.weather ~= nil and require("src.core.game3.weather")
    local savedBefore = Weather and Weather.getSaved()
    Space.runEnterScripts(mod or Runtime._mod, mapId, game, world,
      { seamless = opts.seamless, enterVia = enterVia, keepScript = opts.keepScript })
    if enterVia == "continue" and session and not opts.seamless then
      local snap = session.objectEvents
      session.objectEvents = nil
      if snap == nil or snap.mapId ~= mapId then
        -- pokeemerald/src/overworld.c:1739
        -- pokeemerald/src/overworld.c:2177
        Space.runOnWarpIntoMap(mapId)
      else
        -- pokeemerald/src/overworld.c:2182
        Objects.restoreSnapshot(snap)
      end
    end
    -- pokeruby/src/overworld.c:661
    if Weather and Weather.getSaved() ~= savedBefore then
      if opts.seamless then Weather.doCurrent() else Weather.resumePaused() end
    end
  elseif Space and Space.onMapEnter then
    Space.onMapEnter(mod or Runtime._mod, mapId, game, world)
  end
  -- pokeemerald/src/overworld.c:2172
  if not opts.seamless then
    Map.applyInitialAvatar(session, def, savedAvatar, previousAvatar)
    if session then
      session._savedAvatar = nil
      session.facing = Player.facing
    end
    Player.syncSavePosition(game)
  end
  -- pokeemerald/src/overworld.c:870
  if session and not opts.seamless and require("src.core.game3.capabilities").has(session, "tv")
      and def and require("src.core.game3.dataset").isIndoorMapType(def.mapType) then
    require("src.core.game3.scripting.natives_tv").updateScreensOnMap(session)
  end

  -- Map BGM from extract index / header music.
  do
    local Audio = require("src.core.game3.audio")
    local music = def and def.music
    if not music and Audio._pack and Audio._pack.index and Audio._pack.index.mapSongs then
      music = Audio._pack.index.mapSongs[mapId]
    end
    -- pokefirered/src/overworld.c:1063
    if Map.disableMusicChange == Map.MUSIC_DISABLE_STOP then
      Audio.playSong(0)
      music = nil
    elseif Map.disableMusicChange == Map.MUSIC_DISABLE_KEEP then
      music = nil
    end
    if music and music ~= 0xFFFF and Audio.mapMusicPolicy() == "rse" then
      -- pokeemerald/src/overworld.c:1170
      Audio.mapLoadMusic({ mapId = mapId, fromMapId = fromMapId, seamless = opts.seamless, music = music,
        x = Player.cellX, y = Player.cellY })
    elseif music and music ~= 0xFFFF then
      local id
      if opts.seamless then
        -- pokefirered/src/overworld.c:1075
        local fromDef = fromMapId and host_map_def(game, fromMapId)
        if Audio._currentSong and Audio._currentSong.id == Audio.MUS_SURF then
          Audio.setMapSong(music)
        elseif Audio.specialMapSong(fromDef and fromDef.regionMapSectionId) == Audio.MUS_SURF then
          id = Audio.MUS_SURF
        else
          id = music
        end
      else
        -- pokefirered/src/overworld.c:1039
        id = Audio._savedSong or (Audio.specialMapSong(def and def.regionMapSectionId) == Audio.MUS_SURF
          and Audio.MUS_SURF) or music
      end
      if id then Audio.playMapSong(id, { mapSong = music }) end
    end
  end

  -- Location change overlay (pokefirered/src/overworld.c:785, 1687, 1922)
  -- Strict arbiter: gMapHeader.showMapName == TRUE. If 0/false, strictly suppress popup.
  -- overworld.c:1913 gives a changed map section with a FOREST preview screen
  -- precedence over the popup; pret gates that on a real warp, not a connection.
  do
    local currSec = def and (def.regionMapSectionId or def.region_map_section_id)
    local lastSec = Map._lastSectionId
    local showFlag = def and (def.showMapName or def.show_map_name)
    local previewed = false

    if currSec and not opts.seamless and lastSec ~= currSec and FieldModules.enabled("mapPreview", session) then
      local okPreview, MapPreviewScreen = pcall(require, "src.ui.game3.map_preview_screen")
      if okPreview and MapPreviewScreen then
        MapPreviewScreen.dismiss()
        previewed = MapPreviewScreen.show(currSec) == true
      end
    end

    local okPop, MapNamePopup = false, nil
    if FieldModules.enabled("mapNamePopup", session) then
      okPop, MapNamePopup = pcall(require, "src.ui.game3.map_name_popup")
    end
    if okPop and MapNamePopup then
      if previewed then
        MapNamePopup.dismiss()
      elseif showFlag == 0 or showFlag == false then
        MapNamePopup.dismiss()
      elseif isRse and opts.seamless then
        -- pokeemerald/src/overworld.c:824
        MapNamePopup.show(def)
      elseif showFlag == 1 or showFlag == true then
        if lastSec == nil or lastSec ~= currSec or not opts.seamless then
          MapNamePopup.show(def)
        end
      end
    end
    if def and def.regionMapSectionId then
      Map._lastSectionId = def.regionMapSectionId
    end
  end

  if not opts.seamless then
    if not Space._pendingOnFrame
        and not (Space.vm and Space.vm.isRunning and Space.vm:isRunning()) then
      Field.unlock()
    end
  end

  if Map._warmPairs then Map.warmNow(game, mapId) end
  require("src.core.FixedStep"):discardCatchup()

  return {
    mapId = mapId,
    neighbors = Map.neighbors,
    overscan = Map.overscanSlices(),
  }
end

function Map.loadedLayoutCount()
  local n = 0
  for _ in pairs(Map._loadedLayouts) do n = n + 1 end
  return n
end

return Map
