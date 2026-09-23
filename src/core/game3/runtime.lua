-- Game3 primary runtime on Sevii (P0).
-- Pauses host field locomotion (_game3FieldPause); pumps RTC / playtime (H1).
-- Game3 Player owns walk/run; dialogs + START go through game3 HUD.

local MapIds = require("src.core.game3.map_ids")
local Runtime = {}

Runtime.active = false
Runtime.session = nil
Runtime._mod = nil
Runtime._game = nil
Runtime._fieldLocked = false
Runtime._playTimeAcc = 0
Runtime._deferred = nil
Runtime._menuFocus = false

local function log(msg)
  print("[game3] " .. tostring(msg))
  local mod = Runtime._mod
  if mod and mod.log and mod.log.info then
    mod.log:info("[game3] " .. tostring(msg))
  end
end
Runtime.log = log

function Runtime.isActive()
  return Runtime.active == true
end

function Runtime.getSession()
  return Runtime.session
end

function Runtime.defer(fn)
  if type(fn) ~= "function" or not Runtime.active then return false end
  local q = Runtime._deferred
  if not q then
    q = {}
    Runtime._deferred = q
  end
  q[#q + 1] = fn
  return true
end

function Runtime.drainDeferred()
  local q = Runtime._deferred
  if not q then return 0 end
  Runtime._deferred = nil
  for i = 1, #q do
    local ok, err = pcall(q[i])
    if not ok then log("deferred call failed: " .. tostring(err)) end
  end
  return #q
end

-- pokefirered/src/start_menu.c:1003
function Runtime.fieldScreenOpen(menuOpen)
  if menuOpen == nil then
    local Hud = require("src.ui.game3.hud")
    menuOpen = Hud.isMenuOpen and Hud.isMenuOpen() or false
  end
  if not menuOpen then return false end
  local Stack = package.loaded["src.ui.game3.stack"]
  if Stack and Stack.depth and Stack.has and Stack.has("start") then
    local depth = Stack.depth()
    -- pokefirered/src/start_menu.c:577
    if depth == 1 or (depth == 2 and Stack.has("save")) then
      return false
    end
  end
  return true
end

-- pokefirered/src/overworld.c:1936
function Runtime.noteFieldFocus(screenOpen)
  local was = Runtime._menuFocus == true
  Runtime._menuFocus = screenOpen and true or false
  if screenOpen and not was then
    -- pokefirered/src/start_menu.c:453
    local Lighting = package.loaded["src.core.game3.league_lighting"]
    if Lighting then Lighting.stop() end
  end
  if screenOpen or not was then return false end
  local Battle = package.loaded["src.core.game3.battle"]
  if Battle and Battle.isActive and Battle.isActive() then return false end
  local Space = package.loaded["src.core.game3.scripting.space"]
  if not (Space and Space.active and Space.vm) then return false end
  if Space.vm.isRunning and Space.vm:isRunning() then return false end
  local iv = Space._immediateVm
  if iv and iv.isRunning and iv:isRunning() then return false end
  local ok, ran = pcall(Space.returnToField)
  return ok and ran == true
end

function Runtime.pumpRtc(game, dt)
  local session = Runtime.session or (game and game.session)
  local save = game and game.save
  if not session and not save then return end
  dt = tonumber(dt) or (1 / 60)

  -- Standalone FRLG playtime accumulator (no hardware RTC, no Gen2 Clock).
  local pt = (session and (session.playtime or session.playTime))
    or (save and (save.playTime or save.playtime))
  if type(pt) ~= "table" then
    pt = { hours = 0, minutes = 0, seconds = 0, vblanks = 0 }
  end
  pt.hours = tonumber(pt.hours) or 0
  pt.minutes = tonumber(pt.minutes) or 0
  pt.seconds = tonumber(pt.seconds) or 0
  pt.vblanks = tonumber(pt.vblanks) or 0

  Runtime._playTimeAcc = (Runtime._playTimeAcc or 0) + dt
  while Runtime._playTimeAcc >= 1 do
    Runtime._playTimeAcc = Runtime._playTimeAcc - 1
    pt.seconds = pt.seconds + 1
    if pt.seconds >= 60 then
      pt.seconds = 0
      pt.minutes = pt.minutes + 1
      if pt.minutes >= 60 then
        pt.minutes = 0
        pt.hours = math.min(999, pt.hours + 1)
      end
    end
  end

  if session then
    session.playtime = pt
    session.playTime = pt
    session.playTimeHours = pt.hours
    session.playTimeMinutes = pt.minutes
    session.playTimeSeconds = pt.seconds
    session.hours = pt.hours
    session.minutes = pt.minutes
    session.seconds = pt.seconds
  end
  if save then
    save.playTime = pt
    save.playtime = pt
    save.playTimeHours = pt.hours
    save.playTimeMinutes = pt.minutes
    save.playTimeSeconds = pt.seconds
  end
end

local function mark_host_game3(game, on)
  local world = game and (game.overworld or game.world)
  if world then
    world._game3FieldPause = on and true or false
  end
  if game then
    game._game3Active = on and true or false
  end
end

--- Start Game3 session. opts.alreadyOnMap skips Map.load warp (save load / adopt).
function Runtime.start(mod, game, session, opts)
  opts = opts or {}
  Runtime._mod = mod
  Runtime._game = game
  Runtime.session = session
  Runtime.active = true
  Runtime._deferred = nil
  Runtime._menuFocus = false
  local CameraObject = require("src.core.game3.camera_object")
  CameraObject.reset()
  mark_host_game3(game, true)

  log(string.format(
    "ACTIVE engine=game3 map=%s pos=%s,%s reason=%s",
    tostring(session and session.map),
    tostring(session and session.x),
    tostring(session and session.y),
    tostring(opts.reason or (opts.alreadyOnMap and "adopt" or "enter"))))

  local Field = require("src.core.game3.field")
  Field.start(mod, game, session)

  local Dataset = require("src.core.game3.dataset")
  local cache = (mod and mod.cache) or (Dataset.cache and Dataset.cache())
  local okPk, Pokemon = pcall(require, "src.core.game3.pokemon")
  if okPk and Pokemon and Pokemon.install then
    Pokemon.install(cache)
  end
  local okPc, PartyChrome = pcall(require, "src.ui.game3.party_chrome")
  if okPc and PartyChrome and PartyChrome.install then
    PartyChrome.install(cache)
  end
  local okBc, BattleChrome = pcall(require, "src.ui.game3.battle_chrome")
  if okBc and BattleChrome and BattleChrome.install then
    BattleChrome.install(cache)
  end

  if opts.alreadyOnMap then
    -- Stay on current host map; only ensure Space VM + depth-1 neighbors.
    local Map = require("src.core.game3.map")
    local def = game and game.data and game.data.maps and game.data.maps[session.map]
    Map.current = session.map
    Map.loadNeighborsDepth1(game, def)
    -- Space.onMapEnter already ran (or will run) from afterMap — don't double.
    log("adopted existing game3 map (no re-warp)")
  else
    local Map = require("src.core.game3.map")
    Map.load(mod, game, session.map, {
      x = session.x,
      y = session.y,
      facing = session.facing,
      depth1Connections = true,
    })
    log("warped via game3 map loader → " .. tostring(session.map))
  end
end

function Runtime.stop(mod, game)
  log("INACTIVE leaving game3 field")
  local Field = require("src.core.game3.field")
  Field.stop()
  mark_host_game3(game or Runtime._game, false)
  Runtime.active = false
  Runtime.session = nil
  Runtime._deferred = nil
  Runtime._menuFocus = false
  local okCam, CameraObject = pcall(require, "src.core.game3.camera_object")
  if okCam and CameraObject then CameraObject.reset() end
  local Space = package.loaded["src.core.game3.scripting.space"]
  if Space and Space.deactivate then
    Space.deactivate(mod or Runtime._mod)
  end
  Runtime._mod = nil
  Runtime._game = nil
end

function Runtime.update(dt)
  if not Runtime.active then return end
  local game = Runtime._game
  local Hud = require("src.ui.game3.hud")
  local inputTop = require("src.ui.game3.stack").top() or false
  local inMenu = Hud.isMenuOpen and Hud.isMenuOpen() or false
  Runtime.drainDeferred()
  Runtime.noteFieldFocus(Runtime.fieldScreenOpen(inMenu))

  -- pokefirered/src/field_control_avatar.c:94 FieldGetPlayerInput
  if inMenu then
    Hud.clearFieldInput()
  else
    Hud.sampleFieldInput(game)
  end

  if not inMenu then
    Runtime.pumpRtc(game, dt)
  end

  local okF, Fade = pcall(require, "src.ui.game3.fade")
  if okF and Fade.tick then Fade.tick(dt) end
  local okTr, BattleTransition = pcall(require, "src.core.game3.battle_transition")
  if okTr and BattleTransition.isActive and BattleTransition.isActive() then
    BattleTransition.tick(dt)
  end
  local okT, Task = pcall(require, "src.core.game3.task")
  if okT and Task.update then Task.update(dt) end
  local okA, Audio = pcall(require, "src.core.game3.audio")
  if okA and Audio.update then
    -- Cry tick is folded into Audio.update (called from Game3:fixedUpdate).
  elseif okA and Audio.tickCry then
    Audio.tickCry(dt)
  end

  local Battle = require("src.core.game3.battle")
  if Battle.isActive() then
    Battle.update(dt, game)
    -- Keep script VM + message typewriter alive while battle runs.
    local Space = package.loaded["src.core.game3.scripting.space"]
    if Space and Space.vm then
      local ad = Space.vm.adapters
      if ad and ad.pollMovement then ad.pollMovement(0) end
      Space.vm:tick()
    end
    local Message = package.loaded["src.ui.game3.message"]
    if Message and Message.tick then Message.tick() end
    Hud.update(game, dt, inputTop)
    return
  end

  if not inMenu then
    local Field = require("src.core.game3.field")
    Field.update(dt)
  end
  Hud.update(game, dt, inputTop)
end

function Runtime.uiBusy()
  local Hud = require("src.ui.game3.hud")
  return Hud.busy()
end

function Runtime.setUi(stackTop)
  Runtime._ui = stackTop
end

local function current_map_id(game)
  local world = game and (game.overworld or game.world)
  if world and world.map and world.map.id then return world.map.id end
  local pos = game and game.save and game.save.position
  return pos and pos.map
end

local function player_xy(game)
  -- Prefer game3 avatar when active.
  local okP, Player = pcall(require, "src.core.game3.player")
  if okP and Player and Runtime.active then
    return Player.cellX, Player.cellY, Player.facing or "down"
  end
  local world = game and (game.overworld or game.world)
  local p = world and world.player
  if p then
    return p.cellX or p.x, p.cellY or p.y, p.facing or "down"
  end
  local pos = game and game.save and game.save.position
  if pos then return pos.x, pos.y, pos.facing or "down" end
  return 0, 0, "down"
end

--- If save/load or warp lands on SEVII_* without ferry, adopt Game3 session.
function Runtime.ensureActiveForMap(mod, game, mapId)
  if not MapIds.isGame3Map(mapId) then
    if Runtime.active then
      log("left game3 map=" .. tostring(mapId) .. " — tearing down")
      local Bridge = require("src.core.game3.bridge")
      Bridge.persistSessionOnly(mod, game)
      Runtime.stop(mod, game)
    else
      log("map=" .. tostring(mapId) .. " (not a game3 map)")
    end
    return false
  end
  if Runtime.active then
    local session = Runtime.session
    local world = game and (game.overworld or game.world)
    local p = world and world.player
    local pos = game and game.save and game.save.position
    -- Prefer host-placed coords when adopting.
    -- stale game3 Player (Map.load no longer soft-syncs setMap).
    local x, y, facing
    if p and ((pos and pos.map == mapId) or (pos == nil)) then
      x = tonumber(p.cellX or p.x) or 0
      y = tonumber(p.cellY or p.y) or 0
      facing = p.facing or "down"
    elseif pos and pos.map == mapId then
      x = tonumber(pos.x) or 0
      y = tonumber(pos.y) or 0
      facing = pos.facing or "down"
    else
      x, y, facing = player_xy(game)
    end
    if session then
      session.map = mapId
      session.x, session.y, session.facing = x, y, facing
    end
    -- Rebind EventObjects + collision for the new map. localIds are per-map.
    local data = game and game.data and game.data.maps
    local def = data and data[mapId]
    local Map = package.loaded["src.core.game3.map"]
      or require("src.core.game3.map")
    Map.current = mapId
    if def then
      local Space = package.loaded["src.core.game3.scripting.space"]
        or require("src.core.game3.scripting.space")
      if Space.ensureBundle then Space.ensureBundle(mod) end
      if Space.attachEventsToMaps then
        Space.attachEventsToMaps({ [mapId] = def }, Space.bundle)
      end
      local okC, Collision = pcall(require, "src.core.game3.collision")
      if okC and Collision and Collision.bindMap then
        Collision.bindMap(game, mapId, def)
      end
      local okO, Objects = pcall(require, "src.core.game3.objects")
      if okO and Objects and Objects.loadMap then
        Objects.loadMap(game, mapId, def)
      end
      Map.loadNeighborsDepth1(game, def)
    end
    local okP, Player = pcall(require, "src.core.game3.player")
    if okP and Player then
      Player.reset(x, y, facing)
      Player.syncSavePosition(game)
    end
    log("already ACTIVE on " .. tostring(mapId) .. " (rebound objects)")
    return true
  end
  log("bootstrapping game3 on Sevii map load: " .. tostring(mapId))
  local Bridge = require("src.core.game3.bridge")
  local x, y, facing = player_xy(game)
  Bridge.enterFromHost(mod, game, {
    map = mapId,
    x = x,
    y = y,
    facing = facing,
    alreadyOnMap = true,
    reason = "map_enter_or_load",
  })
  return true
end

function Runtime.install(mod)
  if Runtime._installed then return end
  Runtime._installed = true
  Runtime._mod = mod
  log("Runtime.install — display ownership + START intercept + game.ready")

  local ok, World = pcall(require, "src.world.gen2.World")
  if ok and World and World.step and not World._game3RuntimeStep then
    local prev = World.step
    World.step = function(self, ...)
      if Runtime.active then
        Runtime._game = self.game or Runtime._game
        -- Honor field pause: do not run Gen2 locomotion / NPC AI / pollInput step.
        -- Keep map fade + heal/fly anims so warps and nurse SFX still complete.
        if self.mapSetup and self.updateMapSetup then
          self:updateMapSetup()
        end
        if self.healAnim and self.stepHealAnim then self:stepHealAnim() end
        if self.flyAnim and self.stepFlyAnim then self:stepFlyAnim() end
        Runtime.update(1 / 60)
        return
      end
      return prev(self, ...)
    end
    World._game3RuntimeStep = true
    log("World:step hooked — host locomotion paused on Sevii")
  end
  if ok and World and World.pollInput and not World._game3PollInput then
    local prevPoll = World.pollInput
    World.pollInput = function(self, ...)
      -- Game3 Player reads input from Field.update; never feed Gen2 heldDir.
      if Runtime.active then return end
      return prevPoll(self, ...)
    end
    World._game3PollInput = true
  end
  if ok and World and World.interact and not World._game3InteractGate then
    local prevIx = World.interact
    World.interact = function(self, ...)
      -- Field.interact owns A-button talk on Sevii; never double-fire host path.
      if Runtime.active then return end
      return prevIx(self, ...)
    end
    World._game3InteractGate = true
  end

  -- Own the frame: replace Gen2 drawScene presentation while active.
  local ok2, Game2 = pcall(require, "src.core.Game2")
  if ok2 and Game2 and Game2.drawScene and not Game2._game3Display then
    local prevDraw = Game2.drawScene
    Game2.drawScene = function(self, w, h)
      if Runtime.isActive() then
        Runtime._game = self
        local Display = require("src.core.game3.display")
        if Display.present(self, w, h) then
          return
        end
      end
      return prevDraw(self, w, h)
    end
    Game2._game3Display = true
    log("Game2:drawScene hooked — game3 owns FRLG 240x160 present")
  end

  if ok2 and Game2 and Game2.openStartMenu and not Game2._game3StartMenu then
    local prevOpen = Game2.openStartMenu
    Game2.openStartMenu = function(self, ...)
      if Runtime.isActive() then
        local Hud = require("src.ui.game3.hud")
        log("START → game3 Start Menu (own display)")
        Hud.openStartMenu(self, Runtime.getSession())
        return
      end
      local mapId = current_map_id(self)
      if MapIds.isGame3Map(mapId) then
        Runtime.ensureActiveForMap(mod, self, mapId)
        local Hud = require("src.ui.game3.hud")
        Hud.openStartMenu(self, Runtime.getSession())
        return
      end
      return prevOpen(self, ...)
    end
    Game2._game3StartMenu = true
  end

  -- Block Gen2 menu pushes on Sevii entirely.
  local ok3, Screens = pcall(require, "src.ui.Screens")
  if ok3 and Screens and Screens.push and not Screens._game3StartHook then
    local prevPush = Screens.push
    Screens.push = function(game, id, ...)
      if id == "StartMenu" or id == "Gen2StartMenu" or id == "Gen2PackMenu"
          or id == "PackMenu" or id == "Gen2Pokegear" then
        local mapId = current_map_id(game)
        if Runtime.isActive() or MapIds.isGame3Map(mapId) then
          if not Runtime.isActive() and MapIds.isGame3Map(mapId) then
            Runtime.ensureActiveForMap(mod, game, mapId)
          end
          if Runtime.isActive() then
            local Hud = require("src.ui.game3.hud")
            log("blocked Screens.push(" .. tostring(id) .. ") — game3 owns UI")
            if id == "StartMenu" or id == "Gen2StartMenu" then
              Hud.openStartMenu(game, Runtime.getSession())
            elseif id == "Gen2Pokegear" or id == "PackMenu" or id == "Gen2PackMenu" then
              local RegionMap = require("src.ui.game3.region_map")
              RegionMap.show({ session = Runtime.getSession() })
            end
            return
          end
        end
      end
      return prevPush(game, id, ...)
    end
    Screens._game3StartHook = true
  end

  -- Also pump UI when Game2 logic would open start but world step is gated.
  if ok2 and Game2 and Game2.update and not Game2._game3Logic then
    -- openStartMenu already hooked; ensure START during uiBusy still works
    -- via Game2's acceptsMenuInput path — openStartMenu intercept handles it.
    Game2._game3Logic = true
  end

  if mod.events then
    mod.events:on("game.ready", function(game)
      Runtime._game = game
      local mapId = current_map_id(game)
      log("game.ready map=" .. tostring(mapId)
        .. (MapIds.isGame3Map(mapId) and " → ensure game3" or " → host"))
      if MapIds.isGame3Map(mapId) then
        Runtime.ensureActiveForMap(mod, game, mapId)
      end
    end)
  end
end

return Runtime
