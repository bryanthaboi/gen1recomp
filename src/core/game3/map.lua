-- Game3 map loader. Owns Sevii enter: player, collision, EventObjects, Space scripts.
-- Talk/interact is Field.interact. Do not call host setMap/warpToMapId here —
-- MAPSETUP.WARP races ON_FRAME and wipes applymovement tracks (Bill intro).

local MapIds = require("src.core.game3.map_ids")
local ModRuntime = require("src.mods.Runtime")
local Map = {}

Map.current = nil
Map._announced = nil
Map.neighbors = {}
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
  if not primaryDef or type(primaryDef.connections) ~= "table" then
    return Map.neighbors
  end
  local data = game and game.data and game.data.maps
  if not data then return Map.neighbors end
  for dir, conn in pairs(primaryDef.connections) do
    local mid = type(conn) == "table" and conn.map or conn
    if type(mid) == "string" and data[mid] then
      local def = data[mid]
      Map.ensureMidLayout(game, mid, def)
      Map.neighbors[dir] = {
        map = mid,
        mapId = mid,
        def = def,
        offset = type(conn) == "table" and (conn.offset or 0) or 0,
      }
      Map._loadedLayouts[mid] = true
    end
  end
  return Map.neighbors
end

local function cell_size(def)
  local L = def and def.midLayout
  if L and L.width and L.height then return L.width or 0, L.height or 0 end
  return (tonumber(def and def.width) or 0) * 2, (tonumber(def and def.height) or 0) * 2
end

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
    for dir, conn in pairs(cur.def.connections or {}) do
      local destId = type(conn) == "table" and conn.map or conn
      local destDef = type(destId) == "string" and maps[destId] or nil
      if destDef and destDef ~= rootDef and not placed[destId] then
        local offset = (type(conn) == "table" and tonumber(conn.offset) or 0) or 0
        ensure(destId, destDef)
        local destW, destH = cell_size(destDef)
        local ox, oy
        if dir == "north" or dir == "up" then
          ox, oy = offset, -destH
        elseif dir == "south" or dir == "down" then
          ox, oy = offset, curH
        elseif dir == "west" or dir == "left" then
          ox, oy = -destW, offset
        elseif dir == "east" or dir == "right" then
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
  Map._worldRoot = rootId
  Map._worldReachW = reachW
  Map._worldReachH = reachH
  local FieldView = package.loaded["src.core.game3.field_view"]
  if FieldView then FieldView._nativeDirty = true end
  return Map.world
end

function Map.overscanSlices()
  local slices = {}
  for dir, n in pairs(Map.neighbors) do
    slices[#slices + 1] = { dir = dir, mapId = n.map or n.mapId, offset = n.offset }
  end
  return slices
end

local function neighborFor(cardinal)
  local n = Map.neighbors
  if not n then return nil end
  -- Dataset keys are north/south/west/east; some callers use up/down/left/right.
  if cardinal == "north" or cardinal == "up" then
    return n.north or n.up
  elseif cardinal == "south" or cardinal == "down" then
    return n.south or n.down
  elseif cardinal == "west" or cardinal == "left" then
    return n.west or n.left
  elseif cardinal == "east" or cardinal == "right" then
    return n.east or n.right
  end
  return n[cardinal]
end

--- Resolve a cell in current-map space, sampling connected neighbors when OOB
-- (pret VMap connection fill). Returns mid, sourcePair. OOB with no neighbor
-- falls through to primary border tiling.
-- Module level, not a closure per call: worldMidAt runs for every visible
-- cell of every frame, and a per-call closure was steady garbage.
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

function Map.worldMidAt(cx, cy, primaryDef)
  local layout = primaryDef and primaryDef.midLayout
  if not layout then return 0, nil end
  local w, h = layout.width or 0, layout.height or 0
  local primaryPair = layout.pair or primaryDef.pair

  if cx >= 0 and cy >= 0 and cx < w and cy < h then
    return layout:midAt(cx, cy), primaryPair
  end

  if cy < 0 then
    local n = neighborFor("north")
    if n then
      local offset = tonumber(n.offset) or 0
      local L = n.def and n.def.midLayout
      local nh = L and L.height or 0
      local mid, pair = fromNeighbor(n, cx - offset, nh + cy, primaryPair)
      if mid ~= nil then return mid, pair end
    end
  elseif cy >= h then
    local n = neighborFor("south")
    if n then
      local offset = tonumber(n.offset) or 0
      local mid, pair = fromNeighbor(n, cx - offset, cy - h, primaryPair)
      if mid ~= nil then return mid, pair end
    end
  end

  if cx < 0 then
    local n = neighborFor("west")
    if n then
      local offset = tonumber(n.offset) or 0
      local L = n.def and n.def.midLayout
      local nw = L and L.width or 0
      local mid, pair = fromNeighbor(n, nw + cx, cy - offset, primaryPair)
      if mid ~= nil then return mid, pair end
    end
  elseif cx >= w then
    local n = neighborFor("east")
    if n then
      local offset = tonumber(n.offset) or 0
      local mid, pair = fromNeighbor(n, cx - w, cy - offset, primaryPair)
      if mid ~= nil then return mid, pair end
    end
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

--- Load a Sevii map under game3 ownership (pret enter order).
-- 1) Bind game3 player + collision + EventObjects
-- 2) Objects.loadMap then Space.runEnterScripts (ON_TRANSITION → ON_FRAME)
function Map.load(mod, game, mapId, opts)
  opts = opts or {}
  if not MapIds.isGame3Map(mapId) then
    return nil, "not a game3 map"
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
        if fromMapId ~= nil and fromMapId ~= mapId then
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
  Map._def = def
  Map._currentDef = def
  -- pokefirered/src/overworld.c:878 GetAdjustedInitialTransitionFlags
  local keepBike = false
  do
    local Player = require("src.core.game3.player")
    if Player.biking then
      local allowed = def and def.bikingAllowed
      if allowed ~= nil then
        -- pokefirered/src/overworld.c:948 Overworld_IsBikingAllowed
        keepBike = (tonumber(allowed) or 0) ~= 0
      else
        local pair = def and (def.pair or (def.midLayout and def.midLayout.pair))
        keepBike = type(pair) == "string" and pair:find("outdoor", 1, true) ~= nil
      end
      Player.biking = keepBike
    end
  end
  if opts.depth1Connections ~= false then
    Map.loadNeighborsDepth1(game, def)
  else
    Map.neighbors = {}
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

  local session = Runtime.getSession and Runtime.getSession()
  if session then
    session.map = mapId
    session.x = x
    session.y = y
    session.facing = facing
  end

  -- Keep save.position current for ferry exit / host save without setMap.
  local save = game and game.save
  if save then
    save.position = save.position or {}
    save.position.map = mapId
    save.position.x = x
    save.position.y = y
    save.position.facing = facing
  end

  local Player = require("src.core.game3.player")
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
  Player.syncSavePosition(game)

  local okFv, FieldView = pcall(require, "src.core.game3.field_view")
  if okFv and FieldView then FieldView._nativeDirty = true end

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
  end

  local Objects = require("src.core.game3.objects")
  -- pokefirered/src/overworld.c:800
  if fromMapId and (fromMapId ~= mapId or opts.heal) then
    require("src.core.game3.vs_seeker").mapReset(session)
  end
  if Space and Space.activate then
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
    Objects.loadMap(game, mapId, def)
    Ghosts.adopt(mapId)
  end
  -- pokefirered/src/overworld.c:771 / :808 TryRegenerateRenewableHiddenItems
  local okRen, Renewable = pcall(require, "src.core.game3.renewable_hidden_items")
  if okRen and Renewable and Renewable.tryRegenerate then
    Renewable.tryRegenerate(session, def and (def.group or (def.pair and def.pair[1])), def and (def.num or (def.pair and def.pair[2])), mapId)
  end
  -- pokefirered/src/overworld.c:809 SetCurrentAndNextWeather
  if def and def.weather ~= nil then
    local Weather = require("src.core.game3.weather")
    Weather.apply(def.weather)
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
    Space.runEnterScripts(mod or Runtime._mod, mapId, game, world,
      { seamless = opts.seamless, enterVia = enterVia })
  elseif Space and Space.onMapEnter then
    Space.onMapEnter(mod or Runtime._mod, mapId, game, world)
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
    if music and music ~= 0xFFFF then
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

    if currSec and not opts.seamless and lastSec ~= currSec then
      local okPreview, MapPreviewScreen = pcall(require, "src.ui.game3.map_preview_screen")
      if okPreview and MapPreviewScreen then
        MapPreviewScreen.dismiss()
        previewed = MapPreviewScreen.show(currSec) == true
      end
    end

    local okPop, MapNamePopup = pcall(require, "src.ui.game3.map_name_popup")
    if okPop and MapNamePopup then
      if previewed then
        MapNamePopup.dismiss()
      elseif showFlag == 0 or showFlag == false then
        MapNamePopup.dismiss()
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
