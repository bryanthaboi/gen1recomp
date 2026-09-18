-- Game3 field loop coordinator (scripts, player input, heal/respawn).

local Player = require("src.core.game3.player")
local ModRuntime = require("src.mods.Runtime")

local Field = {}

Field.running = false
Field._mod = nil
Field._game = nil
Field._session = nil
Field.locked = false
Field.weather = 0
Field.metatileOverrides = {}

function Field.start(mod, game, session)
  Field._mod = mod
  Field._game = game
  Field._session = session
  Field.running = true
  Field.locked = false
  Field.weather = 0
  Field.metatileOverrides = {}
  local PcAnim = package.loaded["src.core.game3.pc_anim"]
  if PcAnim then PcAnim.reset() end
  if session then
    Player.syncFromSession(session)
  else
    Player.syncFromHost(game)
  end
  Player.syncSavePosition(game)

  -- Bind collision grid + EventObjects for current Sevii map.
  local mapId = session and session.map
  local data = game and game.data and game.data.maps
  local def = mapId and data and data[mapId]
  local Collision = require("src.core.game3.collision")
  local Objects = require("src.core.game3.objects")
  if def then
    Collision.bindMap(game, mapId, def)
    Objects.loadMap(game, mapId, def)
  end
end

function Field.stop()
  Field.running = false
  Field._session = nil
  Field.locked = false
end

function Field.getSession()
  return Field._session
end

function Field.update(_dt)
  if not Field.running then return end
  local game = Field._game

  local Compat = package.loaded["src.mods.Gen3Compat"]
  if Compat and Compat.worldTick then Compat.worldTick(_dt) end

  local Space = package.loaded["src.core.game3.scripting.space"]
  if Space and Space.vm then
    local ad = Space.vm.adapters
    if ad and ad.pollMovement then ad.pollMovement(0) end
    Space.vm:tick()
    if Space._pendingOnFrame and not Space.vm:isRunning() then
      local world = game and (game.overworld or game.world)
      if not (Space._deferOnFrameForFade and world and world.mapSetup) then
        Space._pendingOnFrame = false
        Space._deferOnFrameForFade = false
        Space.runOnFrame()
        -- Map.load locks until ON_FRAME can claim (lockall). If nothing
        -- started, free the D-pad again (pret: no script → no lock).
        if not Space.vm:isRunning() then
          Field.unlock()
        end
      end
    end
  end

  local PcAnim = package.loaded["src.core.game3.pc_anim"]
  if PcAnim then PcAnim.update() end

  -- Game3 owns locomotion + EventObjects (host World:step is paused).
  local Objects = require("src.core.game3.objects")
  Objects.update(game)
  local Ghosts = require("src.core.game3.ghosts")
  Ghosts.sync()
  Ghosts.update(game)

  local input = game and game.input
  Player.update(game, input)

  local Hud = require("src.ui.game3.hud")
  local Runtime = package.loaded["src.core.game3.runtime"]
    or require("src.core.game3.runtime")
  local Message = package.loaded["src.ui.game3.message"]

  -- A-button talk / signs / PC — owned here (host pollInput is no-op on Sevii).
  -- START / pause menu is owned by Hud.update (avoids same-frame open+close).
  if input and input.wasPressed and input:wasPressed("a") then
    if not Hud.busy() then
      Field.interact(game)
    end
  end

  -- Pret General tileset anims (water / flower / sand edge).
  local okA, TilesetAnim = pcall(require, "src.core.game3.tileset_anim")
  if okA and TilesetAnim and TilesetAnim.step then
    TilesetAnim.step()
  end

  local okFx, FieldEffects = pcall(require, "src.core.game3.field_effects")
  if okFx and FieldEffects and FieldEffects.step then
    FieldEffects.step()
  end

  local okD, Doors = pcall(require, "src.core.game3.doors")
  if okD and Doors and Doors.update then
    Doors.update()
  end

  local okS, SpecialAnim = pcall(require, "src.core.game3.special_field_anim")
  if okS and SpecialAnim and SpecialAnim.update then
    SpecialAnim.update()
  end

  local okStep, StepEvents = pcall(require, "src.core.game3.step_events")
  if okStep and StepEvents and StepEvents.update then
    StepEvents.update(_dt, game)
  end

  if Message and Message.tick then Message.tick() end
end

function Field.lock()
  Field.locked = true
end

function Field.unlock()
  Field.locked = false
end

local DELTA = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }

local function facing_cell(px, py, facing)
  local d = DELTA[facing or "down"] or DELTA.down
  return px + d[1], py + d[2]
end

--- Object cell for talk (pret CheckFacingObject): double past COLL_COUNTER desks.
local function facing_object_cell(fx, fy, facing)
  local Collision = require("src.core.game3.collision")
  local CollisionStd = require("src.core.game3.scripting.collision_std")
  local coll = Collision.cell and Collision.cell(fx, fy)
  if CollisionStd.isCounter(coll) then
    local d = DELTA[facing or "down"] or DELTA.down
    return fx + d[1], fy + d[2]
  end
  return fx, fy
end

local function bg_event_at(game, fx, fy, elevation, facingDir)
  local session = Field._session
  local mapId = session and session.map
  local data = game and game.data and game.data.maps
  local def = mapId and data and data[mapId]
  local events = def and def.bgEvents
  if not events then
    local Space = package.loaded["src.core.game3.scripting.space"]
    local ev = Space and Space.bundle and Space.bundle.events and Space.bundle.events[mapId]
    events = ev and ev.bgEvents
  end
  if not events then return nil end
  for _, ev in ipairs(events) do
    if ev.scriptKey and require("src.core.game3.scripting.interaction_scripts").backgroundMatches(ev,fx,fy,elevation,facingDir) then
      return ev
    end
  end
  return nil
end

--- Step-onto coord events (Pallet Oak gate, etc.). Returns true if a script started.
function Field.tryCoordEvents(game, cx, cy)
  game = game or Field._game
  if not Field.running then return false end
  if Field.locked then return false end

  local Space = package.loaded["src.core.game3.scripting.space"]
    or require("src.core.game3.scripting.space")
  if not Space.active or not Space.startScript then return false end
  if Space.vm and Space.vm.isRunning and Space.vm:isRunning() then
    return false
  end

  local session = Field._session
  local mapId = session and session.map
  local data = game and game.data and game.data.maps
  local def = mapId and data and data[mapId]
  local events = def and def.coordEvents
  if not events then
    local ev = Space.bundle and Space.bundle.events and Space.bundle.events[mapId]
    events = ev and ev.coordEvents
  end
  if type(events) ~= "table" then return false end

  local Flags = require("src.core.game3.scripting.flags")
  local Ctx = require("src.core.game3.scripting.ctx")
  local store = Space.store
  local ctx = (Space.vm and Space.vm.ctx) or Ctx.new()

  local P = require("src.core.game3.player")
  local DIR_BY_FACING = { down = 1, up = 2, left = 3, right = 4 }
  local facingDir = DIR_BY_FACING[P.facing] or 1

  for _, ev in ipairs(events) do
    if ev.x == cx and ev.y == cy and ev.scriptKey then
      local var = tonumber(ev.var)
      if var then
        local cur = Flags.getVar(store, ctx, var)
        local want = tonumber(ev.value) or 0
        if cur ~= want then
          -- not this trigger
        else
          Space.startScript(ev.scriptKey, nil, facingDir)
          return true
        end
      else
        Space.startScript(ev.scriptKey, nil, facingDir)
        return true
      end
    end
  end
  return false
end

--- A-button field interact: NPC talk → bgEvent → metatile interaction → Surf.
-- Returns true if a script (or handled action) started.
local function interacted(fx, fy, kind, target)
  if not ModRuntime.wants("world.interacted") then return end
  local Map = package.loaded["src.core.game3.map"]
  local session = Field._session
  ModRuntime.emit("world.interacted", {
    mapId = (session and session.map) or (Map and Map.current),
    x = fx, y = fy, kind = kind, target = target,
  })
end

local inInteract = false

function Field.interact(game)
  game = game or Field._game
  if not Field.running then return false end
  local Compat = package.loaded["src.mods.Gen3Compat"]
  local replaced = not inInteract and Compat and Compat.interactWrapper and Compat.interactWrapper()
  if replaced then
    inInteract = true
    local ok, res = pcall(replaced, Compat.resolve("src.world.OverworldController"))
    inInteract = false
    if not ok then error(res, 0) end
    return res
  end

  local Runtime = package.loaded["src.core.game3.runtime"]
  if Runtime and Runtime.uiBusy and Runtime.uiBusy() then return false end
  if Field.locked then return false end

  local Space = package.loaded["src.core.game3.scripting.space"]
    or require("src.core.game3.scripting.space")
  if Space.vm and Space.vm.isRunning and Space.vm:isRunning() then
    return false
  end
  if not Space.active or not Space.startScript then return false end

  local P = require("src.core.game3.player")
  if P.moving then return false end

  local Objects = require("src.core.game3.objects")
  local Collision = require("src.core.game3.collision")
  local CollisionStd = require("src.core.game3.scripting.collision_std")

  local fx, fy = facing_cell(P.cellX, P.cellY, P.facing)
  local DIR_BY_FACING = { down = 1, up = 2, left = 3, right = 4 }
  local facingDir = DIR_BY_FACING[P.facing] or 1

  local FieldMoves = require("src.core.game3.field_moves")
  local party = Field._session and Field._session.party

  -- 1) EventObject (nurse behind counter uses doubled cell; Cut tree / Rock / Boulder)
  local ox, oy = facing_object_cell(fx, fy, P.facing)
  local eo = Objects.at(ox, oy)
  if eo and eo.def then
    local gfx = eo.def.graphicsId or eo.def.gfx
    if gfx == FieldMoves.GFX_IDS.CUT_TREE then
      local ctx = { party = party, store = Space.store, session = Field._session, facingObject = eo }
      local res = FieldMoves.tryCutOW(ctx)
      if res.ask then
        local Message = require("src.ui.game3.message")
        local Choice = require("src.ui.game3.choice")
        Message.show(res.ask, function()
          Choice.yesNo(function(yes)
            if yes then Field.executeFieldMove(res) else Message.close() end
          end)
        end)
        return true
      elseif res.text then
        local Message = require("src.ui.game3.message")
        Message.show(res.text)
        return true
      end
    elseif gfx == FieldMoves.GFX_IDS.ROCK_SMASH_ROCK then
      local ctx = { party = party, store = Space.store, session = Field._session, facingObject = eo }
      local res = FieldMoves.tryRockSmashOW(ctx)
      if res.ask then
        local Message = require("src.ui.game3.message")
        local Choice = require("src.ui.game3.choice")
        Message.show(res.ask, function()
          Choice.yesNo(function(yes)
            if yes then Field.executeFieldMove(res) else Message.close() end
          end)
        end)
        return true
      elseif res.text then
        local Message = require("src.ui.game3.message")
        Message.show(res.text)
        return true
      end
    elseif gfx == FieldMoves.GFX_IDS.PUSHABLE_BOULDER then
      local ctx = { party = party, store = Space.store, session = Field._session, facingObject = eo }
      local res = FieldMoves.tryStrengthOW(ctx)
      if res.ask then
        local Message = require("src.ui.game3.message")
        local Choice = require("src.ui.game3.choice")
        Message.show(res.ask, function()
          Choice.yesNo(function(yes)
            if yes then Field.executeFieldMove(res) else Message.close() end
          end)
        end)
        return true
      elseif res.text then
        local Message = require("src.ui.game3.message")
        Message.show(res.text)
        return true
      end
    elseif eo.def.scriptKey then
      local lid = eo.localId or eo.def.localId or eo.def.index or 0
      local talkTo = Compat and Compat.talkToWrapper and Compat.talkToWrapper()
      if talkTo and talkTo(Compat.resolve("src.world.OverworldController"), eo) then
        interacted(ox, oy, "npc", eo)
        return true
      end
      local function talk()
        Objects.freeze(lid)
        Objects.facePlayer(lid, game)
        Space.startScript(eo.def.scriptKey, lid, facingDir)
      end
      if ModRuntime.wantsHook("world.talk") then
        ModRuntime.call("world.talk", talk, game, eo)
      else
        talk()
      end
      interacted(ox, oy, "npc", eo)
      return true
    end
  end

  -- 2) Extracted bgEvents (signs) — face cell only, not doubled
  local layout=Collision._mapDef and Collision._mapDef.midLayout
  local elevation=layout and layout:elevAt(P.cellX,P.cellY) or 0
  if elevation==0 then elevation=P.elevation or 0 end
  local sign = bg_event_at(game, fx, fy, elevation, facingDir)
  if sign and sign.scriptKey then
    if Space.startScript(sign.scriptKey, nil, facingDir) then
      interacted(fx, fy, "sign", sign)
      return true
    end
  end

  -- 3) Original metatile interactions follow objects and map-specific scripts.
  local behavior=Collision.behavior(fx,fy)
  local key=require("src.core.game3.scripting.interaction_scripts").scriptFor(behavior,P.facing)
  if behavior==nil then key=CollisionStd.scriptFor(Collision.cell(fx,fy)) end
  if key and Space.startScript(key,nil,facingDir) then
    interacted(fx, fy, "script", key)
    return true
  end

  -- 4) Water / Surf interact on facing water tile
  if not P.surfing and Collision.isWater and Collision.isWater(fx, fy) then
    local ctx = { party = party, store = Space.store, session = Field._session, isFacingWater = true }
    local res = FieldMoves.trySurfOW(ctx)
    if res.ask then
      local Message = require("src.ui.game3.message")
      local Choice = require("src.ui.game3.choice")
      Message.show(res.ask, function()
        Choice.yesNo(function(yes)
          if yes then Field.executeFieldMove(res) else Message.close() end
        end)
      end)
      return true
    end
  end


  return false
end

function Field.executeFieldMove(payload)
  if not payload then return end
  local Message = require("src.ui.game3.message")
  local Audio = require("src.core.game3.audio")
  local FieldEffects = require("src.core.game3.field_effects")
  local P = require("src.core.game3.player")
  local Objects = require("src.core.game3.objects")

  local act = payload.action
  local questKeys={cut_tree="UsedCut",cut_grass="UsedCut",surf="UsedSurf",strength="UsedStrength",
    flash="UsedFlash",rock_smash="UsedRockSmash",dig="UsedDigInLocation",
    teleport="UsedTeleportToLocation",fly="UsedFly",sweet_scent="UsedSweetScent"}
  local key=questKeys[act]
  if key and Field._session then
    local Q=require("src.core.game3.quest_log_recorder")
    Q.event(Field._session,key,{require("src.core.game3.pokemon").displayMonName(payload.mon),
      Q.location(Field._game,Field._session)})
  end
  if act == "cut_tree" then
    Field.locked = true
    P.startFieldMove(28)
    if payload.se then Audio.playSe(payload.se) end
    local target = payload.target
    local tx = target and (target.cellX or target.x or (target.def and target.def.x)) or P.cellX
    local ty = target and (target.cellY or target.y or (target.def and target.def.y)) or P.cellY

    FieldEffects.startCutTree(target, tx, ty, function()
      if target then
        local lid = target.localId or (target.def and (target.def.localId or target.def.index))
        if lid then Objects.removeObject(lid) end
      end
      Field.locked = false
      if payload.text then
        Message.show(payload.text, function() Message.close() end)
      end
    end)
  elseif act == "cut_grass" then
    Field.locked = true
    P.startFieldMove(24)
    if payload.se then Audio.playSe(payload.se) end
    local Map = require("src.core.game3.map")
    local def = Map.currentDef()
    local layout = def and def.midLayout
    if layout and layout.midAt and layout.setMidAt then
      local Collision = require("src.core.game3.collision")
      local FieldMoves = require("src.core.game3.field_moves")
      FieldMoves.mowGrass3x3(P.cellX, P.cellY, function(x, y) return layout:midAt(x, y) end,
        function(x, y, mid) layout:setMidAt(x, y, mid) end,
        function(x, y) return Collision.isGrass(x, y) end)
      local okFv, FieldView = pcall(require, "src.core.game3.field_view")
      if okFv and FieldView then FieldView._nativeDirty = true end
    end
    FieldEffects.startCutGrass(P.cellX, P.cellY, function()
      Field.locked = false
      if payload.text then
        Message.show(payload.text, function() Message.close() end)
      end
    end)
  elseif act == "rock_smash" then
    Field.locked = true
    P.startFieldMove(28)
    if payload.se then Audio.playSe(payload.se) end
    local target = payload.target
    local tx = target and (target.cellX or target.x or (target.def and target.def.x)) or P.cellX
    local ty = target and (target.cellY or target.y or (target.def and target.def.y)) or P.cellY

    FieldEffects.startRockSmash(target, tx, ty, function()
      if target then
        local lid = target.localId or (target.def and (target.def.localId or target.def.index))
        if lid then Objects.removeObject(lid) end
      end
      Field.locked = false
      if payload.text then
        Message.show(payload.text, function() Message.close() end)
      end
    end)
  elseif act == "strength" then
    Field.locked = true
    P.startFieldMove(24)
    if payload.flag then
      local Space = package.loaded["src.core.game3.scripting.space"]
      local Flags = require("src.core.game3.scripting.flags")
      if Space and Space.store then
        Flags.setFlag(Space.store, nil, payload.flag, true)
      end
      if Field._session and Field._session.flags then
        Field._session.flags[payload.flag] = true
      end
    end
    if payload.text then
      Message.show(payload.text, function()
        Message.close()
        Field.locked = false
      end)
    else
      Field.locked = false
    end
  elseif act == "surf" then
    Field.locked = true
    P.startSurfing(Field._game, function()
      Field.locked = false
      if payload.text then
        Message.show(payload.text, function() Message.close() end)
      end
    end)
  elseif act == "flash" then
    Field.locked = true
    P.startFieldMove(24)
    if payload.se then Audio.playSe(payload.se) end
    if payload.flag then
      local Space = package.loaded["src.core.game3.scripting.space"]
      local Flags = require("src.core.game3.scripting.flags")
      if Space and Space.store then
        Flags.setFlag(Space.store, nil, payload.flag, true)
      end
    end
    FieldEffects.startFlash(function()
      Field.locked = false
      if payload.text then
        Message.show(payload.text, function() Message.close() end)
      end
    end)
  elseif act == "teleport" or act == "dig" then
    Field.locked = true
    if payload.se then Audio.playSe(payload.se) end
    FieldEffects.startWarpSpin(act, function()
      Field.locked = false
      Field.respawnAtHeal({ fieldMove = true })
    end)
    if payload.text then
      Message.show(payload.text, function() Message.close() end)
    end
  elseif act == "sweet_scent" then
    Field.locked = true
    P.startFieldMove(24)
    if payload.se then Audio.playSe(payload.se) end
    FieldEffects.startSweetScent(function()
      Field.locked = false
      local okE, Encounters = pcall(require, "src.core.game3.encounters")
      if okE and Encounters and Encounters.tryBattle then
        Encounters.tryBattle(Field._game, true)
      end
    end)
    if payload.text then
      Message.show(payload.text, function() Message.close() end)
    end
  end
end

--- White-out / heal respawn via game3 map loader (H7).
function Field.respawnAtHeal(opts)
  local session = Field._session
  if not session then return end
  local HealLocations = require("src.core.game3.heal_locations")
  HealLocations.normalizeSession(session)
  if not (opts and opts.fieldMove) and ModRuntime.wants("world.blacked_out") then
    ModRuntime.emit("world.blacked_out", {
      save = session,
      healTarget = { map = session.healMap, x = session.healX, y = session.healY },
    })
  end
  local Party = require("src.core.game3.party")
  Party.healAll(session.party)
  local Map = require("src.core.game3.map")
  local mapId = session.healMap or "FR_PLAYERS_HOUSE_1F"
  local hx = session.healX or 8
  local hy = session.healY or 5
  Map.load(Field._mod, Field._game, mapId, {
    x = hx,
    y = hy,
    facing = "down",
    depth1Connections = true,
    heal = true,
  })
  Player.reset(hx, hy, "down")
  Player.syncToHost(Field._game)
  -- Map.load already locked; ON_FRAME / releaseall own unlock.
end

function Field.setHealPoint(mapId, x, y)
  local session = Field._session
  if not session then return end
  session.healMap = mapId
  session.healX = x
  session.healY = y
end

--- pret ScrCmd_setrespawn → SetLastHealLocationWarp (we store whiteout tile).
function Field.setRespawn(healLocationId)
  local session = Field._session
  if not session then return false end
  local HealLocations = require("src.core.game3.heal_locations")
  return HealLocations.applyToSession(session, healLocationId)
end

function Field.setWeather(id)
  Field.weather = tonumber(id) or 0
  local Weather = require("src.core.game3.weather")
  Weather.apply(Field.weather)
end

function Field.setMetatile(x, y, metatile, isImpassable)
  Field.metatileOverrides[#Field.metatileOverrides + 1] = {
    x = x, y = y, metatile = metatile, impassable = isImpassable,
  }
  local session = Field._session
  local mapId = session and session.map
  if ModRuntime.wants("world.block_replaced") then
    ModRuntime.emit("world.block_replaced", { mapId = mapId, bx = x, by = y, block = metatile })
  end
  local game = Field._game
  local data = game and game.data and game.data.maps
  local mapDef = mapId and data and data[mapId]
  local mid = tonumber(metatile) or 0
  local coll = isImpassable and 0x07 or 0x00
  if mapDef and mapDef.midLayout then
    local pair = mapDef.pair or mapDef.midLayout.pair
    local okR, Register = pcall(require, "src.import.gba.register")
    local midIndex = okR and Register and Register._midIndex
    if midIndex and pair and midIndex[pair] and midIndex[pair][mid] then
      coll = midIndex[pair][mid].coll or coll
      if isImpassable then coll = 0x07 end
    end
    mapDef.midLayout:applyOverride(x, y, mid, coll, 0)
    local Collision = require("src.core.game3.collision")
    Collision.bindMap(game, mapId, mapDef)
    local FieldView = package.loaded["src.core.game3.field_view"]
    if FieldView then FieldView._nativeDirty = true end
  end
  local world = game and (game.overworld or game.world)
  if world and world.map and world.map.setBlock then
    pcall(function()
      world.map:setBlock(x, y, metatile)
    end)
  end
end

return Field
