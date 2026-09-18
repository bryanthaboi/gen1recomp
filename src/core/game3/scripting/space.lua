-- Sevii space swap: activate game3 on SEVII_* maps; wipe on leave/halt.

local MapIds = require("src.core.game3.map_ids")
local Ctx = require("src.core.game3.scripting.ctx")
local Flags = require("src.core.game3.scripting.flags")
local Vm = require("src.core.game3.scripting.vm")
local Adapters = require("src.core.game3.scripting.adapters")
local ExtractScripts = require("src.import.gba.extract_scripts")
local GfxIds = require("src.core.game3.scripting.gfx_ids")

local Space = {}

Space.active = false
Space.vm = nil
Space.store = nil
Space.bundle = nil
Space.mapId = nil
Space._saveKey = "firered_game3"

function Space.isActive()
  return Space.active == true
end

function Space.getVm()
  return Space.vm
end

function Space.getStore()
  return Space.store
end

local function resolve_game(mod, game)
  if game then return game end
  if mod and mod.game then return mod.game end
  local Runtime = package.loaded["src.core.game3.runtime"]
  return Runtime and Runtime._game
end

local function resolve_session(mod, game)
  local Runtime = package.loaded["src.core.game3.runtime"]
  if Runtime and Runtime.getSession then
    local s = Runtime.getSession()
    if s then return s end
  end
  game = resolve_game(mod, game)
  return game and game.session
end

local function disk_fallback(rel)
  local f0 = io.open(rel, "rb") or io.open("data/generated/gba/" .. rel, "rb")
  if f0 then
    local data = f0:read("*a")
    f0:close()
    if type(data) == "string" and #data > 0 then return data end
  end

  local okG, GameVersion = pcall(require, "src.core.GameVersion")
  local prefix = (okG and GameVersion.cachePrefix and GameVersion.cachePrefix()) or "firered/"
  local roots = {}
  local home = os.getenv("HOME")
  if home then roots[#roots + 1] = home .. "/.local/share/love/pokemon-love2d" end
  if love and love.filesystem and love.filesystem.getSaveDirectory then
    local sd = love.filesystem.getSaveDirectory()
    if type(sd) == "string" and sd ~= "" then
      roots[#roots + 1] = sd
      local parent = sd:match("^(.*)/[^/]+$")
      if parent then roots[#roots + 1] = parent .. "/pokemon-love2d" end
    end
  end
  for _, root in ipairs(roots) do
    for _, path in ipairs({ root .. "/" .. prefix .. rel, root .. "/" .. rel }) do
      local f = io.open(path, "rb")
      if f then
        local data = f:read("*a")
        f:close()
        if type(data) == "string" and #data > 0 then return data end
      end
    end
  end
  return nil
end

local function love_cache()
  return {
    read = function(_, rel)
      local ok, CacheFs = pcall(require, "src.import.CacheFs")
      if ok and CacheFs and CacheFs.readActive then
        local bytes = CacheFs.readActive(rel)
        if type(bytes) == "string" then return bytes end
      end
      if love and love.filesystem then
        local bytes = love.filesystem.read(rel)
        if type(bytes) == "string" then return bytes end
      end
      return disk_fallback(rel)
    end,
    exists = function(_, rel)
      return love_cache():read(rel) ~= nil
    end,
  }
end

local function load_sidecar(mod, game)
  Space.store = Flags.newStore()
  -- Standalone FR: do not keep the Sevii harbor seed unless a save restores it.
  local harborVar = (Flags.VAR_IDS and (Flags.VAR_IDS.MAP_SCENE_ONE_ISLAND_HARBOR or Flags.VAR_IDS.VAR_MAP_SCENE_ONE_ISLAND_HARBOR))
    or (Flags.IDS and (Flags.IDS.MAP_SCENE_ONE_ISLAND_HARBOR or Flags.IDS.VAR_MAP_SCENE_ONE_ISLAND_HARBOR))
    or 0x4075
  if harborVar then
    Space.store.vars[harborVar] = nil
  end
  local session = resolve_session(mod, game)
  if session then
    Flags.loadInto(Space.store, {
      flags = session.flags,
      vars = session.vars,
    })
    Flags.ensurePalletOakHidden(Space.store)
    return
  end
  game = resolve_game(mod, game)
  local save = game and game.save
  if save and save.modData and save.modData[Space._saveKey] then
    Flags.loadInto(Space.store, save.modData[Space._saveKey])
  end
  Flags.ensurePalletOakHidden(Space.store)
end

local function persist_sidecar(mod, game)
  if not Space.store then return end
  local snap = Flags.serialize(Space.store)
  local session = resolve_session(mod, game)
  if session then
    session.flags = snap.flags
    session.vars = snap.vars
    return
  end
  game = resolve_game(mod, game)
  if not (game and game.save) then return end
  game.save.modData = game.save.modData or {}
  game.save.modData[Space._saveKey] = snap
  if game.save.flags == nil and session then
    game.save.flags = session.flags
    game.save.vars = session.vars
  end
end

--- Persist flag/var store into the active session (and save sidecar if any).
function Space.persistSession(mod, game)
  persist_sidecar(mod or Space._mod, game)
end

function Space.ensureBundle(mod)
  if Space.bundle then return Space.bundle end
  local Dataset = require("src.core.game3.dataset")
  local Extract = require("src.import.gba.extract_island1")
  Dataset.mountExtractRoots()
  local root = Extract.CACHE_ROOT or "data/generated/gba"
  local cache = (mod and mod.cache) or love_cache()
  local bundle = ExtractScripts.loadBundle(cache, root, { allowIncomplete = true })
  Space.bundle = bundle
  local nEv = 0
  if bundle and bundle.events then
    for _ in pairs(bundle.events) do nEv = nEv + 1 end
  end
  print(string.format("[game3/space] script bundle events=%d fromCache=%s",
    nEv, tostring(bundle and bundle.fromCache)))
  return Space.bundle
end

--- Copy extracted objects / signs / coords onto map defs (Objects + Field read these).
function Space.attachEventsToMaps(maps, bundle)
  bundle = bundle or Space.bundle or Space.ensureBundle(nil)
  if not (maps and bundle and bundle.events) then return 0 end
  local n = 0
  for mapId, ev in pairs(bundle.events) do
    local def = maps[mapId]
    if def and type(ev) == "table" then
      -- Deep-ish copy object rows so setobjectxy/removeobject cannot mutate the
      -- shared script bundle for the rest of the session.
      if type(ev.objects) == "table" then
        local objs = {}
        for i, row in ipairs(ev.objects) do
          local copy = {}
          for k, v in pairs(row) do copy[k] = v end
          objs[i] = copy
        end
        def.objects = objs
      elseif type(ev.objectEvents) == "table" and not def.objects then
        local objs = {}
        for i, row in ipairs(ev.objectEvents) do
          local copy = {}
          for k, v in pairs(row) do copy[k] = v end
          objs[i] = copy
        end
        def.objects = objs
      end
      if type(ev.bgEvents) == "table" then def.bgEvents = ev.bgEvents end
      if type(ev.coordEvents) == "table" then def.coordEvents = ev.coordEvents end
      if type(ev.mapScripts) == "table" then def.mapScripts = ev.mapScripts end
      if ev.music ~= nil then def.music = ev.music end
      n = n + 1
    end
  end
  return n
end

function Space.activate(mod, mapId, game, world)
  if Space.active and Space.mapId == mapId then
    return Space.vm
  end
  if Space.active then
    Space.deactivate(mod)
  end
  load_sidecar(mod, game)
  Flags.onMapLoad(Space.store)
  local bundle = Space.ensureBundle(mod)
  local adapters = Adapters.host(mod, game, world)
  adapters.lookupMovement = function(key)
    if type(key) == "string" then return bundle.movements[key] end
    return bundle.movements[tostring(key)]
  end
  adapters.lookupText = function(key) return bundle.text[key] end
  Space.vm = Vm.new({
    store = Space.store,
    scripts = bundle.scripts,
    text = bundle.text,
    movements = bundle.movements,
    adapters = adapters,
  })
  Space.vm._mod = mod
  Space.active = true
  Space.mapId = mapId
  Space._mod = mod
  if adapters.clearMovements then adapters.clearMovements() end
  return Space.vm
end

function Space.deactivate(mod)
  if Space.vm then
    Space.vm:halt(Space.vm:isRunning())
  end
  persist_sidecar(mod or Space._mod)
  if Space.store then
    -- specialVars live on ctx; already wiped by halt
  end
  Space.vm = nil
  Space.active = false
  Space.mapId = nil
end

function Space.onMapEnter(mod, mapId, game, world)
  if not MapIds.isGame3Map(mapId) then
    if Space.active then Space.deactivate(mod) end
    return
  end
  local vm = Space.activate(mod, mapId, game, world)
  Space.runEnterScripts(mod, mapId, game, world)
  return vm
end

--- ON_TRANSITION + schedule ON_FRAME. Call only after Objects.loadMap for mapId
-- so setobjectxyperm / removeobject hit the destination map's localIds (pret order).
function Space.runEnterScripts(mod, mapId, game, world)
  if not Space.vm then return end
  mapId = mapId or Space.mapId
  local ev = Space.bundle and Space.bundle.events and Space.bundle.events[mapId]
  if not ev then return Space.vm end
  local vm = Space.vm
  local ms = ev.mapScripts or {}
  if ms.onTransition and type(ms.onTransition) == "string" then
    vm:start(ms.onTransition)
    -- Drain short transition scripts so ON_FRAME can run this enter.
    for _ = 1, 64 do
      if not vm:isRunning() then break end
      vm:tick()
    end
    -- VAR_OBJ_GFX_ID_* / setobjectxyperm applied — refresh NPC sprites.
    Space.refreshObjectGraphics()
  end
  -- ON_FRAME (Bill intro etc.) — defer while Gen2 MAPSETUP is still white.
  if not vm:isRunning() then
    Space.scheduleOnFrame(world)
  else
    Space._pendingOnFrame = true
    if world and world.mapSetup then
      Space._deferOnFrameForFade = true
    end
  end
  return vm
end

function Space.scheduleOnFrame(world)
  -- Always defer ON_FRAME to the field loop. Running it synchronously from
  -- Map.load/warp nests under the previous script; warp.finish then cleared
  -- Objects tracks and soft-locked MeetCelio on waitmovement.
  Space._pendingOnFrame = true
  Space._deferOnFrameForFade = (world and world.mapSetup) and true or false
end

function Space.onResume(mod)
  if not Space.active or not Space.vm then return end
  local ev = Space.bundle and Space.bundle.events and Space.bundle.events[Space.mapId]
  local ms = ev and ev.mapScripts
  if ms and type(ms.onResume) == "string" then
    Space.vm:start(ms.onResume)
  end
  -- ON_FRAME after resume (stub wiring)
  Space.runOnFrame()
end

function Space.runOnFrame()
  if not Space.active or not Space.vm then return end
  local ev = Space.bundle and Space.bundle.events and Space.bundle.events[Space.mapId]
  local frames = ev and ev.mapScripts and ev.mapScripts.onFrame
  if type(frames) ~= "table" then return end
  for _, row in ipairs(frames) do
    if row.script then
      local v = Flags.getVar(Space.store, Space.vm.ctx, row.var)
      if v == (row.value or 0) then
        Space.vm:start(row.script)
        break
      end
    end
  end
end

--- Resolve graphics / graphicsVar → sprite for object defs at spawn.
function Space.resolveObjectSprite(obj)
  if type(obj.sprite) == "string" and obj.sprite ~= "" then
    return obj.sprite
  end
  return GfxIds.spriteFor(Space.resolveObjectGraphicsId(obj))
end

--- Resolve FRLG OBJ_EVENT_GFX id (honours graphicsVar + OBJ_EVENT_GFX_VAR_*).
-- pret: graphicsId >= 240 → VarGetObjectEventGraphicsId(id - 240).
function Space.resolveObjectGraphicsId(obj)
  if not obj then return nil end
  local graphics = tonumber(obj.graphics or obj.graphicsId)
  local store = Space.store or Flags.newStore()
  local ctx = (Space.vm and Space.vm.ctx) or Ctx.new()
  if obj.graphicsVar then
    local v = Flags.getVar(store, ctx, obj.graphicsVar)
    if type(v) == "number" and v ~= 0 then graphics = v end
  end
  if graphics and graphics >= 240 and graphics <= 255 then
    local varId = Ctx.GFX_VAR_LO + (graphics - 240)
    local v = Flags.getVar(store, ctx, varId)
    if type(v) == "number" and v > 0 and v < 240 then
      graphics = v
    end
  end
  return graphics
end

--- After ON_TRANSITION sets VAR_OBJ_GFX_ID_*, refresh spawned sprites.
function Space.refreshObjectGraphics()
  local okO, Objects = pcall(require, "src.core.game3.objects")
  if not (okO and Objects and Objects.refreshGraphics) then return end
  Objects.refreshGraphics()
end

function Space.objectVisible(obj)
  local flag = tonumber(obj and (obj.flag or obj.flagId))
  -- pret: flag 0 / 0xFFFF = no hide flag (always visible).
  if not flag or flag == 0 or flag == 0xFFFF or flag == 65535 then
    return true
  end
  local store = Space.store or Flags.newStore()
  return not Flags.getFlag(store, Space.vm and Space.vm.ctx or Ctx.new(), flag)
end

function Space.startScript(scriptKey, localId, facing)
  if not Space.vm then return false end
  if not facing then
    local P = package.loaded["src.core.game3.player"]
    if P and P.facing then
      local dirs = { down = 1, up = 2, left = 3, right = 4 }
      facing = dirs[P.facing] or 1
    end
  end
  if facing and Space.store and Space.vm.ctx then
    Flags.setVar(Space.store, Space.vm.ctx, Ctx.VAR_FACING, facing)
  end
  if localId then
    return Space.vm:startTalk(scriptKey, localId, facing)
  end
  -- src/field_control_avatar.c:200
  return Space.vm:startTalk(scriptKey, 0, facing)
end

function Space.install(mod)
  if Space._installed then return end
  Space._installed = true
  Space._mod = mod
  Space.ensureBundle(mod)

  local OC = require("src.world.OverworldController")

  -- Map enter / leave: Gen1 loadMap; Gen2 facade/World setMap.
  if not OC._game3LoadMap then
    local function afterMap(world, mapId)
      local game = (world and world.game) or (mod.game)
      if MapIds.isGame3Map(mapId) then
        local Runtime = package.loaded["src.core.game3.runtime"]
          or require("src.core.game3.runtime")
        if Runtime.ensureActiveForMap then
          Runtime.ensureActiveForMap(mod, game, mapId)
        end
        -- Map.load calls Space.onMapEnter directly (no host setMap). External
        -- ferry/host setMap still lands here.
        print("[game3] Space.afterMap SEVII map=" .. tostring(mapId)
          .. " → Space.onMapEnter")
        Space.onMapEnter(mod, mapId, game, world)
      else
        if Space.active then
          print("[game3] Space.afterMap left Sevii → deactivate Space")
        end
        local Runtime = package.loaded["src.core.game3.runtime"]
        if Runtime and Runtime.isActive and Runtime.isActive() then
          local Bridge = require("src.core.game3.bridge")
          Bridge.persistSessionOnly(mod, game)
          Runtime.stop(mod, game)
        end
        Space.deactivate(mod)
      end
    end
    if type(OC.loadMap) == "function" then
      local prev = OC.loadMap
      OC.loadMap = function(self, mapId, ...)
        local r = prev(self, mapId, ...)
        afterMap(self, mapId)
        return r
      end
    end
    if type(OC.setMap) == "function" then
      local prev = OC.setMap
      OC.setMap = function(a, b, ...)
        local mapId = type(a) == "string" and a or b
        local r = prev(a, b, ...)
        local world = type(a) == "table" and a or nil
        afterMap(world, mapId)
        return r
      end
    end
    -- Direct Gen2 World:setMap (ferry/warps often skip the facade).
    local ok, World = pcall(require, "src.world.gen2.World")
    if ok and World and World.setMap and not World._game3SetMap then
      local prevW = World.setMap
      World.setMap = function(self, mapId, ...)
        local r = prevW(self, mapId, ...)
        afterMap(self, mapId)
        return r
      end
      World._game3SetMap = true
    end
    OC._game3LoadMap = true
  end

  if not OC._game3Talk then
    local prevTalk = OC.talkTo
    OC.talkTo = function(world, npc)
      local mapId = world and world.map and world.map.id
      -- Only claim Sevii object talk; leave Gen2 host sailors (Vermilion Port
      -- Fast Ship, etc.) to earlier OC.talkTo wrappers such as the ferry.
      if Space.active and MapIds.isGame3Map(mapId)
          and npc and npc.def and npc.def.scriptKey then
        if world then
          world.talkNpc = npc
          if world.freezeNpc then
            world:freezeNpc(npc)
          else
            npc.frozen = true
            world.frozeNpcs = true
          end
          if npc.facePlayer and world.player then
            npc:facePlayer(world.player)
          end
        end
        local lid = npc.def.localId or npc.def.index or 0
        local facingDir = nil
        if world and world.player and world.player.facing then
          local dirs = { down = 1, up = 2, left = 3, right = 4 }
          facingDir = dirs[world.player.facing]
        end
        Space.startScript(npc.def.scriptKey, lid, facingDir)
        return true
      end
      if type(prevTalk) == "function" then
        return prevTalk(world, npc)
      end
      return false
    end
    OC._game3Talk = true
  end

  -- Gen2 World:busy must see game3 scripts or frozeNpcs clears mid-dialog.
  do
    local ok, World = pcall(require, "src.world.gen2.World")
    if ok and World and World.busy and not World._game3Busy then
      local prevBusy = World.busy
      World.busy = function(self)
        if prevBusy(self) then return true end
        if Space.active and Space.vm and Space.vm:isRunning() then
          return true
        end
        return false
      end
      World._game3Busy = true
    end
    if ok and World and World.step and not World._game3Step then
      local prevStep = World.step
      World.step = function(self, ...)
        local r = prevStep(self, ...)
        -- When Game3 Runtime owns the field loop it drives Vm:tick via Field.update.
        local Runtime = package.loaded["src.core.game3.runtime"]
        if Runtime and Runtime.isActive and Runtime.isActive() then
          return r
        end
        if Space.active and Space.vm then
          -- Advance FRLG cutscene walks even between script yields.
          local ad = Space.vm.adapters
          if ad and ad.pollMovement then
            ad.pollMovement(0)
          end
          Space.vm:tick()
          if Space._pendingOnFrame and not Space.vm:isRunning() then
            if Space._deferOnFrameForFade and self.mapSetup then
              -- Still fading in from MAPSETUP.WARP; keep holding onFrame.
            else
              Space._pendingOnFrame = false
              Space._deferOnFrameForFade = false
              Space.runOnFrame()
              if not Space.vm:isRunning() then
                local okF, Field = pcall(require, "src.core.game3.field")
                if okF and Field and Field.unlock then Field.unlock() end
              end
            end
          end
        end
        return r
      end
      World._game3Step = true
    end
  end

  -- Signs / bgEvents from extracted event tables; then collision-std (MB_PC etc.).
  -- When game3 Runtime is active, Field.interact owns A-button; skip host path.
  if not OC._game3Interact then
    local CollisionStd = require("src.core.game3.scripting.collision_std")
    local prevInteract = OC.interact
    OC.interact = function(world)
      local Runtime = package.loaded["src.core.game3.runtime"]
      if Runtime and Runtime.isActive and Runtime.isActive() then
        return false
      end
      if Space.active and world and world.player then
        local p = world.player
        local Map = world.map
        local delta = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
        local d = delta[p.facing] or delta.down
        local fx, fy = p.cellX + d[1], p.cellY + d[2]
        local dirs = { down = 1, up = 2, left = 3, right = 4 }
        local facingDir = dirs[p.facing] or 1

        -- 1) Extracted bgEvents (signs / network machines from map event tables)
        if world.bgEventAt then
          local sign = world:bgEventAt(fx, fy)
          if sign and sign.scriptKey then
            Space.startScript(sign.scriptKey, nil, facingDir)
            return true
          end
        elseif Map and Map.def and Map.def.bgEvents then
          for _, ev in ipairs(Map.def.bgEvents) do
            if ev.x == fx and ev.y == fy and ev.scriptKey then
              Space.startScript(ev.scriptKey, nil, facingDir)
              return true
            end
          end
        end

        -- 2) Metatile-behavior std scripts (PC, …) — same idea as Gen2
        --    TILE_COLLISION_STD_SCRIPTS: applies wherever extract tagged MB_PC.
        local coll = nil
        if Map and Map.cellCollision then
          coll = Map:cellCollision(fx, fy)
        elseif world.map and world.map.cellCollision then
          coll = world.map:cellCollision(fx, fy)
        end
        local stdKey = CollisionStd.scriptFor(coll)
        if stdKey then
          Space.startScript(stdKey, nil, facingDir)
          return true
        end
      end
      if type(prevInteract) == "function" then
        return prevInteract(world)
      end
      if world and world.interactBody then
        return world:interactBody()
      end
      return false
    end
    OC._game3Interact = true
  end

  if mod.events then
    mod.events:on("game.save", function()
      persist_sidecar(mod)
    end)
  end
end

return Space
