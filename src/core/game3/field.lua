-- Game3 field loop coordinator (scripts, player input, heal/respawn).

local Player = require("src.core.game3.player")
local ModRuntime = require("src.mods.Runtime")
local Strings = require("src.core.Strings")

local Field = {}

Field.running = false
Field._mod = nil
Field._game = nil
Field._session = nil
Field.locked = false
Field.weather = 0
Field.metatileOverrides = {}
Field._overrideLayouts = {}
Field._waterfall = nil
Field._tempFlagMap = nil

-- pokefirered/src/event_object_movement.c:8959
local WALK_SLOWER_FRAMES = 32

-- pokefirered/src/fieldmap.c:103
function Field.clearMetatiles(layout)
  for _, written in pairs(Field._overrideLayouts) do
    if written.clearOverrides then written:clearOverrides() end
  end
  if layout and layout.clearOverrides then layout:clearOverrides() end
  Field.metatileOverrides = {}
  Field._overrideLayouts = {}
end

function Field.metatileOverrideAt(mapId, x, y)
  local bucket = mapId and Field.metatileOverrides[mapId]
  return bucket and bucket[y * 1024 + x] or nil
end

function Field.start(mod, game, session)
  Field._mod = mod
  Field._game = game
  Field._session = session
  Field.running = true
  Field.locked = false
  Field.weather = 0
  Field._waterfall = nil
  -- pokefirered/src/overworld.c:345
  Field._tempFlagMap = session and session.map
  Field.clearMetatiles()
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
  Field._waterfall = nil
  Field._tempFlagMap = nil
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
    -- pokefirered/src/field_control_avatar.c:212
    if not Space.vm:isRunning() then
      local world = game and (game.overworld or game.world)
      if not (Space._deferOnFrameForFade and world and world.mapSetup) then
        local claiming = Space._pendingOnFrame
        Space._pendingOnFrame = false
        Space._deferOnFrameForFade = false
        if claiming or not Field.locked then
          Space.runOnFrame()
          -- pokefirered/src/script.c:463 TryRunOnFrameMapScript
          if claiming and not Space.vm:isRunning() then
            Field.unlock()
          end
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

  Field.pollMapChange(game)
  -- pokefirered/src/safari_zone.c:60 CB2_EndSafariBattle
  Field.pollSafariBalls(game)

  local input = game and game.input
  -- pokefirered/src/field_control_avatar.c:98
  local walkInput = input
  if Field.forcedMovementPending() then walkInput = nil end
  Player.update(game, walkInput)
  Field.updateWaterfall(game)
  -- pokefirered/src/field_player_avatar.c:1691
  Field.updateFishing()

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

-- pokefirered/src/field_effect.c:1104 FieldCallback_FlyIntoMap
Field._flyLanding = false

-- pokefirered/src/field_effect.c:1155 FieldCB_FallWarpExit
Field._fallWarp = false

function Field.unlock()
  if Field._flyLanding then return end
  -- pokefirered/src/field_effect.c:1274 FallWarpEffect_7
  if Field._fallWarp then return end
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

local function get_map_bg_events(game, mapId)
  local session = Field._session
  mapId = mapId or (session and session.map)
  local data = game and game.data and game.data.maps
  local def = mapId and data and data[mapId]
  local events = def and def.bgEvents
  if not events then
    local Space = package.loaded["src.core.game3.scripting.space"]
    local ev = Space and Space.bundle and Space.bundle.events and Space.bundle.events[mapId]
    events = ev and ev.bgEvents
  end
  return events or {}
end

local function bg_event_at(game, fx, fy, elevation, facingDir)
  local events = get_map_bg_events(game)
  for _, ev in ipairs(events) do
    if ev.scriptKey and require("src.core.game3.scripting.interaction_scripts").backgroundMatches(ev,fx,fy,elevation,facingDir) then
      return ev
    end
  end
  return nil
end

local function hidden_item_store(session)
  local Runtime = package.loaded["src.core.game3.runtime"]
  local Space = package.loaded["src.core.game3.scripting.space"]
  if session and Runtime and Runtime.getSession and Runtime.getSession() == session
      and Space and Space.store then
    return Space.store, Space
  end
  return session and (session.store or session)
end

local function hidden_item_at(game, x, y, elevation)
  local session = Field._session
  local events = get_map_bg_events(game)
  local Flags = require("src.core.game3.scripting.flags")
  local store = hidden_item_store(session)
  for _, ev in ipairs(events) do
    if (ev.type == "hidden_item" or ev.kind == 7) and ev.x == x and ev.y == y then
      local flag = ev.flag or (ev.hiddenItemId and (0x3E8 + ev.hiddenItemId))
      if flag and not Flags.getFlag(store, nil, flag) then
        return ev
      end
    end
  end
  return nil
end

function Field.hiddenItemAt(game, x, y, elevation)
  return hidden_item_at(game or Field._game, x, y, elevation)
end

function Field.pickUpHiddenItem(game, hidden)
  if not hidden then return false end
  local session = Field._session
  local Bag = require("src.core.game3.bag")
  local Flags = require("src.core.game3.scripting.flags")
  local Items = require("src.core.game3.items")
  local ItemsData = require("src.core.game3.items_data")
  local Message = require("src.ui.game3.message")
  local Audio = require("src.core.game3.audio")
  local store, Space = hidden_item_store(session)

  local flag = hidden.flag or (hidden.hiddenItemId and (0x3E8 + hidden.hiddenItemId))
  if flag and Flags.getFlag(store, nil, flag) then
    return false
  end

  local itemId = hidden.item
  local qty = hidden.quantity or 1
  local bag = session and session.bag

  if not bag or not Bag.add(bag, itemId, qty) then
    Message.show("Too bad!\nThe BAG is full…", {
      done = function()
        Message.close()
      end,
    })
    return true
  end

  if flag and store then
    Flags.setFlag(store, nil, flag, true)
    if Space then Space.persistSession(nil, game or Field._game) end
  end

  Audio.playFanfare(257)

  local playerName = (session and (session.playerName or session.name)) or "RED"
  local itemName = Items.displayName(itemId)
  local pocket = ItemsData.pocketOf(itemId)
  local pocketLabel = ItemsData.POCKET_LABEL[pocket] or "ITEMS POCKET"
  local text = string.format("%s found one\n%s!\f%s put away the\n%s in the %s.", playerName, itemName, playerName, itemName, pocketLabel)

  Message.show(text, {
    done = function()
      Message.close()
    end,
  })

  if session then
    local okQ, Q = pcall(require, "src.core.game3.quest_log_recorder")
    if okQ and Q and Q.event then
      Q.event(session, "UsedTheItem", { itemName, "" })
    end
  end

  return true
end

function Field.useItemfinder(session, showOWMessage)
  session = session or Field._session
  local P = package.loaded["src.core.game3.player"]
  local px = (session and (session.playerX or session.x)) or (P and (P.cellX or P.x)) or 0
  local py = (session and (session.playerY or session.y)) or (P and (P.cellY or P.y)) or 0
  local events = get_map_bg_events(Field._game, session and session.map)
  local Flags = require("src.core.game3.scripting.flags")
  local Audio = require("src.core.game3.audio")
  local Message = require("src.ui.game3.message")
  local store = hidden_item_store(session)

  local found = nil
  local underfoot = false
  local minDistance = 999999

  for _, ev in ipairs(events) do
    if (ev.type == "hidden_item" or ev.kind == 7) then
      local flag = ev.flag or (ev.hiddenItemId and (0x3E8 + ev.hiddenItemId))
      if flag and not Flags.getFlag(store, nil, flag) then
        local dx = ev.x - px
        local dy = ev.y - py
        local dist = math.abs(dx) + math.abs(dy)
        if math.abs(dx) <= 7 and math.abs(dy) <= 7 then
          if dx == 0 and dy == 0 then
            found = ev
            underfoot = true
            minDistance = 0
            break
          elseif dist < minDistance then
            found = ev
            underfoot = false
            minDistance = dist
          end
        end
      end
    end
  end

  if found then
    Audio.playSe(65) -- SE_ITEMFINDER
    local text
    if underfoot then
      text = "Oh! The ITEMFINDER's responding!\nThere's an item buried right beneath your feet!"
    else
      text = "Huh? The ITEMFINDER's responding!\nThere's an item buried around here!"
    end
    if showOWMessage then
      Message.show(text, { done = function() Message.close() end })
    end
    return true, "itemfinder", text, { x = found.x, y = found.y, underfoot = underfoot }
  else
    local text = "… … … …Nope!\nThere's no response."
    if showOWMessage then
      Message.show(text, { done = function() Message.close() end })
    end
    return false, "itemfinder", text, nil
  end
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

-- pokefirered/include/constants/metatile_behaviors.h:27
local MB_STRENGTH_BUTTON = 0x20
-- pokefirered/include/constants/metatile_behaviors.h:78
local MB_FALL_WARP = 0x66

local function boulderCell(game, cx, cy)
  local Collision = package.loaded["src.core.game3.collision"]
    or require("src.core.game3.collision")
  local beh = Collision.behavior and Collision.behavior(cx, cy)
  return beh, Collision
end

-- pokefirered/src/field_control_avatar.c:1066
local function boulderFallThroughHole(game, obj, cx, cy)
  local beh, Collision = boulderCell(game, cx, cy)
  if beh == nil then return false end
  local hole
  if Collision.isFallWarp then
    hole = Collision.isFallWarp(beh) and true or false
  else
    hole = (beh == MB_FALL_WARP)
  end
  if not hole then return false end

  pcall(function()
    local Audio = require("src.core.game3.audio")
    local SE = require("src.core.game3.se_ids")
    if Audio.playSe and SE.SE_FALL then Audio.playSe(SE.SE_FALL) end
  end)

  -- pokefirered/src/event_object_movement.c:1520 RemoveObjectEventByLocalIdAndMap
  require("src.core.game3.objects").removeObject(
    obj.localId or (obj.def and (obj.def.localId or obj.def.index)))
  obj.moving = false

  -- pokefirered/src/event_object_movement.c:2546
  local reveal = tonumber(obj.trainerType)
    or tonumber(obj.def and obj.def.trainerType) or 0
  if reveal > 0 and reveal ~= 0xFFFF then
    local Space = package.loaded["src.core.game3.scripting.space"]
    if Space and Space.store then
      local Flags = require("src.core.game3.scripting.flags")
      Flags.setFlag(Space.store, Space.vm and Space.vm.ctx or nil, reveal, false)
    end
    local Objects = package.loaded["src.core.game3.objects"]
    if Objects and Objects.syncFlagVisibility then
      Objects.syncFlagVisibility(reveal, false)
    end
  end
  return true
end

-- pokefirered/src/field_control_avatar.c:1076
local function boulderActivateVictoryRoadSwitch(game, cx, cy)
  local beh, Collision = boulderCell(game, cx, cy)
  if beh == nil then return false end
  local button
  if Collision.isStrengthButton then
    button = Collision.isStrengthButton(beh) and true or false
  else
    button = (beh == MB_STRENGTH_BUTTON)
  end
  if not button then return false end

  local Space = package.loaded["src.core.game3.scripting.space"]
    or require("src.core.game3.scripting.space")
  if not Space.active or not Space.startScript then return false end
  if Space.vm and Space.vm.isRunning and Space.vm:isRunning() then return false end

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

  local P = require("src.core.game3.player")
  local DIR_BY_FACING = { down = 1, up = 2, left = 3, right = 4 }
  local facingDir = DIR_BY_FACING[P.facing] or 1

  for _, ev in ipairs(events) do
    if ev.x == cx and ev.y == cy and ev.scriptKey then
      Space.startScript(ev.scriptKey, nil, facingDir)
      return true
    end
  end
  return false
end

-- pokefirered/src/field_player_avatar.c:1452
function Field.onBoulderMoved(game, obj, cx, cy)
  game = game or Field._game
  if not obj then return false end
  if not Field.running then return false end
  if Field.locked then return false end
  cx = tonumber(cx) or obj.cellX
  cy = tonumber(cy) or obj.cellY
  if not cx or not cy then return false end
  local fell = boulderFallThroughHole(game, obj, cx, cy)
  local pressed = boulderActivateVictoryRoadSwitch(game, cx, cy)
  return fell or pressed
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

  -- Hidden items: check facing tile first, then underfoot tile
  local hidden = hidden_item_at(game, fx, fy, elevation)
  if not hidden then
    local pElev = layout and layout:elevAt(P.cellX, P.cellY) or P.elevation or 0
    hidden = hidden_item_at(game, P.cellX, P.cellY, pElev)
  end
  if hidden then
    if Field.pickUpHiddenItem(game, hidden) then
      interacted(hidden.x, hidden.y, "hidden_item", hidden)
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

  -- 5) pokefirered/src/field_control_avatar.c:608
  if FieldMoves.isWaterfallBehavior(behavior) then
    local ctx = {
      party = party, store = Space.store, session = Field._session,
      isSurfing = P.surfing == true, isFacingWaterfall = true, facing = P.facing,
    }
    local res = FieldMoves.tryWaterfallOW(ctx)
    local Message = require("src.ui.game3.message")
    if res.ask then
      local Choice = require("src.ui.game3.choice")
      Message.show(res.ask, function()
        Choice.yesNo(function(yes)
          if yes then Field.executeFieldMove(res) else Message.close() end
        end)
      end)
      return true
    elseif res.text then
      Message.show(res.text)
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
  elseif act == "dotted_hole" then
    -- pokefirered/src/fldeff_cut.c:194
    Field.locked = true
    P.startFieldMove(24)
    if payload.se then Audio.playSe(payload.se) end
    FieldEffects.startCutGrass(P.cellX, P.cellY, function()
      Field.openDottedHoleDoor()
      if payload.text then
        Message.show(payload.text, function() Message.close() end)
      end
    end)
  elseif act == "fly" then
    -- pokefirered/src/region_map.c:3873 CB2_OpenFlyMap
    Field.locked = true
    local okRm, RegionMap = pcall(require, "src.ui.game3.region_map")
    local shown = okRm and RegionMap and RegionMap.show and pcall(RegionMap.show, {
      session = Field._session,
      mode = "fly",
      onPick = function(section) Field.flyTo(section) end,
      onClose = function() Field.locked = false end,
    })
    if not shown then
      Field.locked = false
      local FieldMoves = require("src.core.game3.field_moves")
      Message.show(FieldMoves.TEXT.CANT_USE_HERE, function() Message.close() end)
    end
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
      -- pokefirered/data/scripts/field_moves.inc:88
      if payload.text then
        Message.show(payload.text, function()
          Message.close()
          Field.tryRockSmashEncounter()
        end)
      else
        Field.tryRockSmashEncounter()
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
  elseif act == "waterfall" then
    -- pokefirered/data/scripts/field_moves.inc:178
    Field.locked = true
    local function ride()
      P.startFieldMove(28)
      Field.rideWaterfall("up", 28)
    end
    if payload.text then
      Message.show(payload.text, function()
        Message.close()
        ride()
      end)
    else
      ride()
    end
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
    -- pokefirered/src/fldeff_flash.c:177
    if payload.text then
      Message.show(payload.text, function() Message.close() end)
    end
    FieldEffects.startFlash(function()
      Field.locked = false
    end)
  elseif act == "teleport" or act == "dig" then
    Field.locked = true
    if payload.se then Audio.playSe(payload.se) end
    FieldEffects.startWarpSpin(act, function()
      Field.locked = false
      -- pokefirered/src/field_effect.c:2126 SetWarpDestinationToEscapeWarp
      Field.respawnAtHeal({ fieldMove = true, warp = payload.warp })
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

-- pokefirered/src/wild_encounter.c:446
function Field.tryRockSmashEncounter()
  local Encounters = require("src.core.game3.encounters")
  local session = Field._session
  local mapId = session and session.map
  if not mapId then
    local Map = package.loaded["src.core.game3.map"]
    mapId = Map and Map.current
  end
  local enc = Encounters.rollRocks(mapId)
  if not enc then return false end
  local Runtime = package.loaded["src.core.game3.runtime"]
  local BattleBridge = require("src.core.game3.battle_bridge")
  local ok, err = BattleBridge.startWild(Runtime and Runtime._mod, Field._game, enc, {})
  if not ok then
    print("[game3/field] rock smash startWild failed: " .. tostring(err))
    return false
  end
  return true
end

-- pokefirered/src/field_player_avatar.c:1721 Fishing3
local FISHING_WAIT_FRAMES = 60
-- pokefirered/src/field_player_avatar.c:1755 Fishing5
local FISHING_DOT_FRAMES = 20
-- pokefirered/src/field_player_avatar.c:1741 Fishing4
local FISHING_DOT_MAX = 10
local FISHING_FIRST_ROUND_DOTS = 4

Field._fishing = nil

function Field.isFishing()
  return Field._fishing ~= nil
end

-- pokefirered/src/field_player_avatar.c:1679 StartFishing
function Field.startFishing(rod)
  if Field._fishing then return false end
  Field.locked = true
  Player.fishing = true
  Field._fishing = { rod = tonumber(rod) or 0, step = "wait", timer = 0, dots = 0, required = 0 }
  return true
end

-- pokefirered/src/field_player_avatar.c:1936 Fishing16
local function fishingStop()
  Field._fishing = nil
  Player.fishing = false
  Field.locked = false
end

-- pokefirered/src/wild_encounter.c:519 FishingWildEncounter
function Field.tryFishingEncounter(rod)
  local okE, Encounters = pcall(require, "src.core.game3.encounters")
  if not (okE and Encounters and Encounters.rollFishing) then return false end
  local session = Field._session
  local mapId = session and session.map
  if not mapId then
    local Map = package.loaded["src.core.game3.map"]
    mapId = Map and Map.current
  end
  local enc = Encounters.rollFishing(mapId, tonumber(rod) or 0)
  if not enc then return false end
  local Runtime = package.loaded["src.core.game3.runtime"]
  local BattleBridge = require("src.core.game3.battle_bridge")
  local ok, err = BattleBridge.startWild(Runtime and Runtime._mod, Field._game, enc, {})
  if not ok then
    print("[game3/field] fishing startWild failed: " .. tostring(err))
    return false
  end
  return true
end

local function fishingMapId()
  local session = Field._session
  local mapId = session and session.map
  if mapId then return mapId end
  local Map = package.loaded["src.core.game3.map"]
  return Map and Map.current
end

-- pokefirered/src/field_player_avatar.c:1691 Task_Fishing
function Field.updateFishing()
  local f = Field._fishing
  if not f then return false end
  local Message = require("src.ui.game3.message")
  local Rng = require("src.core.game3.rng")
  f.timer = f.timer + 1

  if f.step == "wait" then
    if f.timer >= FISHING_WAIT_FRAMES then
      -- pokefirered/src/field_player_avatar.c:1741 Fishing4
      f.required = math.min(FISHING_DOT_MAX, (Rng.Random() % 10) + FISHING_FIRST_ROUND_DOTS)
      f.dots = 0
      f.timer = 0
      f.step = "dots"
      Message.showStay("", { speed = 0 })
    end
  elseif f.step == "dots" then
    if f.timer >= FISHING_DOT_FRAMES then
      f.timer = 0
      if f.dots >= f.required then
        f.step = "bite"
      else
        f.dots = f.dots + 1
        Message.showStay(string.rep("·", f.dots), { speed = 0 })
      end
    end
  elseif f.step == "bite" then
    -- pokefirered/src/field_player_avatar.c:1777 Fishing6
    f.step = "result"
    local okE, Encounters = pcall(require, "src.core.game3.encounters")
    local hasMons = okE and Encounters and Encounters.hasFishingMons
      and Encounters.hasFishingMons(fishingMapId()) or false
    if (not hasMons) or (Rng.Random() % 2 == 1) then
      -- pokefirered/src/strings.c:1060 gText_NotEvenANibble
      Message.show(Strings("Not even a nibble…"), function() fishingStop() end)
    else
      -- pokefirered/src/strings.c:1059 gText_PokemonOnHook
      local rod = f.rod
      Message.show(Strings("A POKéMON's on the hook!"), function()
        fishingStop()
        Field.tryFishingEncounter(rod)
      end)
    end
  end
  return true
end

-- pokefirered/src/field_specials.c:2310 CutMoveOpenDottedHoleDoor
function Field.openDottedHoleDoor()
  local FieldMoves = require("src.core.game3.field_moves")
  local RV = FieldMoves.RUIN_VALLEY
  Field.setMetatile(RV.doorX, RV.doorY, RV.doorOpen, false)
  pcall(function()
    local Audio = require("src.core.game3.audio")
    local SE = require("src.core.game3.se_ids")
    Audio.playSe(SE.SE_BANG)
  end)
  local Flags = require("src.core.game3.scripting.flags")
  local Space = package.loaded["src.core.game3.scripting.space"]
  if Space and Space.store then
    Flags.setFlag(Space.store, Space.vm and Space.vm.ctx or nil, RV.flag, true)
  end
  local session = Field._session
  if session and session.flags then session.flags[RV.flag] = true end
  Field.locked = false
  return true
end

-- pokefirered/src/region_map.c:828 sMapFlyDestinations
local FLY_DESTINATIONS = {
  MAPSEC_PALLET_TOWN = { map = "FR_PALLET_TOWN", x = 6, y = 8 },
  MAPSEC_VIRIDIAN_CITY = { map = "FR_VIRIDIAN_CITY", x = 26, y = 27 },
  MAPSEC_PEWTER_CITY = { map = "FR_PEWTER_CITY", x = 17, y = 26 },
  MAPSEC_CERULEAN_CITY = { map = "FR_CERULEAN_CITY", x = 22, y = 20 },
  MAPSEC_LAVENDER_TOWN = { map = "FR_LAVENDER_TOWN", x = 6, y = 6 },
  MAPSEC_VERMILION_CITY = { map = "FR_VERMILION_CITY", x = 15, y = 7 },
  MAPSEC_CELADON_CITY = { map = "FR_CELADON_CITY", x = 48, y = 12 },
  MAPSEC_FUCHSIA_CITY = { map = "FR_FUCHSIA_CITY", x = 25, y = 32 },
  MAPSEC_CINNABAR_ISLAND = { map = "FR_CINNABAR_ISLAND", x = 14, y = 12 },
  MAPSEC_INDIGO_PLATEAU = { map = "FR_INDIGO_PLATEAU_EXTERIOR", x = 11, y = 7 },
  MAPSEC_SAFFRON_CITY = { map = "FR_SAFFRON_CITY", x = 24, y = 39 },
  MAPSEC_ROUTE_4_POKECENTER = { map = "FR_ROUTE_4", x = 12, y = 6 },
  MAPSEC_ROUTE_10_POKECENTER = { map = "FR_ROUTE_10", x = 13, y = 21 },
  MAPSEC_ONE_ISLAND = { map = "SEVII_ONE_ISLAND", x = 14, y = 6 },
  MAPSEC_TWO_ISLAND = { map = "FR_TWO_ISLAND", x = 21, y = 8 },
  MAPSEC_THREE_ISLAND = { map = "FR_THREE_ISLAND", x = 14, y = 28 },
  MAPSEC_FOUR_ISLAND = { map = "FR_FOUR_ISLAND", x = 18, y = 21 },
  MAPSEC_FIVE_ISLAND = { map = "FR_FIVE_ISLAND", x = 18, y = 7 },
  MAPSEC_SIX_ISLAND = { map = "FR_SIX_ISLAND", x = 11, y = 12 },
  MAPSEC_SEVEN_ISLAND = { map = "FR_SEVEN_ISLAND", x = 12, y = 4 },
}
Field.FLY_DESTINATIONS = FLY_DESTINATIONS

Field.FLY_BAKED_REL = "region_map/fly_destinations.lua"
Field._flyBaked = nil
Field._flyBakedRoot = nil

local function fly_default_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then return Extract.CACHE_ROOT end
  return "data/generated/gba"
end

local function fly_cache()
  local ok, Dataset = pcall(require, "src.core.game3.dataset")
  if ok and Dataset and Dataset.cache then return Dataset.cache() end
  return nil
end

local function fly_normalize(row)
  if type(row) ~= "table" then return nil end
  local map = row.map or row.mapId
  if type(map) ~= "string" or map == "" then return nil end
  return { map = map, x = tonumber(row.x) or 0, y = tonumber(row.y) or 0 }
end

function Field.installFlyDestinations(pack)
  Field._flyBaked = {}
  if type(pack) ~= "table" then return 0 end
  local rows = pack.fly_destinations or pack.destinations or pack
  if type(rows) ~= "table" then return 0 end
  local n = 0
  for key, row in pairs(rows) do
    local dest = fly_normalize(row)
    if dest then
      local name = (type(key) == "string" and key:match("^MAPSEC_") and key)
        or (type(row.mapsec) == "string" and row.mapsec)
        or (type(row.id) == "string" and row.id)
        or nil
      local num = tonumber(key) or tonumber(row.mapsec) or tonumber(row.section)
      if name then Field._flyBaked[name] = dest end
      if num then Field._flyBaked[num] = dest end
      if name or num then n = n + 1 end
    end
  end
  return n
end

function Field.loadFlyDestinations(cache, root)
  cache = cache or fly_cache()
  root = root or fly_default_root()
  Field._flyBaked = {}
  Field._flyBakedRoot = root
  if not (cache and cache.read) then return 0 end
  local rel = root .. "/" .. Field.FLY_BAKED_REL
  local src = cache:read(rel)
  if type(src) ~= "string" or src == "" then return 0 end
  local chunk = load(src, "@" .. rel, "t", {})
  if not chunk then return 0 end
  local ok, pack = pcall(chunk)
  if not ok then return 0 end
  return Field.installFlyDestinations(pack)
end

function Field.invalidateFlyDestinations()
  Field._flyBaked = nil
  Field._flyBakedRoot = nil
end

-- pokefirered/src/region_map.c:4022 SetFlyWarpDestination
function Field.flyDestination(section)
  if section == nil then return nil end
  if Field._flyBaked == nil or Field._flyBakedRoot ~= fly_default_root() then
    Field.loadFlyDestinations()
  end
  local baked = Field._flyBaked
  local num = tonumber(section)
  local hit = baked[section] or (num and baked[num])
  if hit then return hit end
  local byName = FLY_DESTINATIONS[section]
  if byName then return byName end
  if not num then return nil end
  local okS, MapSections = pcall(require, "src.import.gba.map_sections_extract")
  local info = okS and MapSections and MapSections.SECTIONS and MapSections.SECTIONS[num]
  local id = info and info.id
  if not id then return nil end
  return baked[id] or FLY_DESTINATIONS[id] or nil
end

-- pokefirered/src/field_effect.c:1065 ReturnToFieldFromFlyMapSelect
function Field.flyTo(section)
  local dest = Field.flyDestination(section)
  local Message = require("src.ui.game3.message")
  if not dest then
    Field.locked = false
    local FieldMoves = require("src.core.game3.field_moves")
    Message.show(FieldMoves.TEXT.CANT_USE_HERE, function() Message.close() end)
    return false
  end
  Field.locked = true
  local FieldEffects = require("src.core.game3.field_effects")
  local function land()
    local Map = require("src.core.game3.map")
    Map.load(Field._mod, Field._game, dest.map, {
      x = dest.x, y = dest.y, facing = "down", depth1Connections = true,
    })
    Player.reset(dest.x, dest.y, "down")
    Player.syncToHost(Field._game)
    Player.setVisible(true)
    -- pokefirered/src/field_effect.c:1104 FieldCallback_FlyIntoMap
    Field._flyLanding = true
    Field.locked = true
    FieldEffects.startFlyLanding(function()
      Field._flyLanding = false
      Field.locked = false
    end)
  end
  if love and love.graphics and FieldEffects.startFlyTakeoff then
    Player.setVisible(false)
    FieldEffects.startFlyTakeoff(land, nil)
  else
    land()
    Field._flyLanding = false
    Field.locked = false
  end
  return true
end

-- pokefirered/src/metatile_behavior.c:266
function Field.forcedMovementPending()
  if Field._waterfall then return false end
  if not Player.surfing then return false end
  local Collision = require("src.core.game3.collision")
  local FieldMoves = require("src.core.game3.field_moves")
  local x, y = Player.cellX, Player.cellY
  if Player.moving then x, y = Player.targetX, Player.targetY end
  if not FieldMoves.isWaterfallBehavior(Collision.behavior(x, y)) then return false end
  -- pokefirered/src/field_player_avatar.c:295
  return Collision.canEnter(Field._game, x, y + 1, {
    fromX = x, fromY = y, dir = "down", surfing = true,
  }) == true
end

-- pokefirered/src/safari_zone.c:60 CB2_EndSafariBattle
function Field.pollSafariBalls(game)
  if Field.locked then return false end
  local Battle = package.loaded["src.core.game3.battle"]
  if Battle and Battle.isActive and Battle.isActive() then return false end
  local Space = package.loaded["src.core.game3.scripting.space"]
  if Space and Space.vm and Space.vm.isRunning and Space.vm:isRunning() then return false end
  local Warp = package.loaded["src.core.game3.warp"]
  if Warp and Warp.isBusy and Warp.isBusy() then return false end
  local okS, Safari = pcall(require, "src.core.game3.safari")
  if not (okS and Safari and Safari.isActive) then return false end
  local session = Field._session
  if not Safari.isActive(session) then return false end
  if Safari.balls(session) > 0 then return false end
  -- pokefirered/data/scripts/safari_zone.inc:31 SafariZone_EventScript_OutOfBalls
  return Safari.outOfBalls(session, game or Field._game) and true or false
end

-- pokefirered/src/event_data.c:49
function Field.clearTempFieldEventData(game, mapId)
  local FieldMoves = require("src.core.game3.field_moves")
  local Flags = require("src.core.game3.scripting.flags")
  local Space = package.loaded["src.core.game3.scripting.space"]
  local session = Field._session
  local ids = {}
  for i = 1, #FieldMoves.TEMP_SYS_FLAGS do ids[i] = FieldMoves.TEMP_SYS_FLAGS[i] end
  local data = game and game.data and game.data.maps
  local def = mapId and data and data[mapId]
  -- pokefirered/src/overworld.c:803
  if FieldMoves.isOutdoors(def and def.mapType) then
    ids[#ids + 1] = FieldMoves.SYS_FLAGS.FLASH_ACTIVE
  end
  for i = 1, #ids do
    local id = ids[i]
    if Space and Space.store then Flags.setFlag(Space.store, nil, id, false) end
    if session and session.flags then session.flags[id] = nil end
  end
end

-- pokefirered/src/overworld.c:797
function Field.pollMapChange(game)
  local session = Field._session
  local mapId = session and session.map
  if mapId == Field._tempFlagMap then return false end
  Field._tempFlagMap = mapId
  Field.clearTempFieldEventData(game or Field._game, mapId)
  return true
end

-- pokefirered/src/field_effect.c:1605
function Field.rideWaterfall(dir, delay)
  Field.locked = true
  Field._waterfall = { dir = dir or "up", wait = tonumber(delay) or 0, started = false, steps = 0 }
end

-- pokefirered/src/field_effect.c:1613
-- pokefirered/src/field_player_avatar.c:246
function Field.updateWaterfall(game)
  local Collision = require("src.core.game3.collision")
  local FieldMoves = require("src.core.game3.field_moves")
  local onWaterfall = FieldMoves.isWaterfallBehavior(Collision.behavior(Player.cellX, Player.cellY))

  local st = Field._waterfall
  if st then
    if st.wait > 0 then
      st.wait = st.wait - 1
      return
    end
    if Player.moving then return end
    -- pokefirered/src/field_effect.c:1659
    if (st.started and not onWaterfall) or st.steps >= 64 then
      Field._waterfall = nil
      Field.locked = false
      return
    end
    st.started = true
    st.steps = st.steps + 1
    Player.forceStep(st.dir, function() end)
    -- pokefirered/src/field_effect.c:1650
    Player.stepFrames = WALK_SLOWER_FRAMES
    return
  end

  if not onWaterfall or Field.locked or not Player.surfing then return end
  local Space = package.loaded["src.core.game3.scripting.space"]
  if Space and Space.vm and Space.vm.isRunning and Space.vm:isRunning() then return end
  local Runtime = package.loaded["src.core.game3.runtime"]
  if Runtime and Runtime.uiBusy and Runtime.uiBusy() then return end
  local tx, ty = Player.cellX, Player.cellY + 1
  -- pokefirered/src/field_player_avatar.c:295
  if not Collision.canEnter(game or Field._game, tx, ty, {
    fromX = Player.cellX, fromY = Player.cellY, dir = "down", surfing = true,
  }) then return end
  if Player.moving then
    -- pokefirered/src/field_player_avatar.c:147
    if Player.targetX == tx and Player.targetY == ty then return end
    Player.moving = false
    Player.progress = 0
    Player.running = false
    Player.jumping = false
    Player.spriteYOffset = 0
    Player.targetX, Player.targetY = Player.cellX, Player.cellY
    Player.px, Player.py = Player.cellX * 16, Player.cellY * 16
    Player._onStepDone = nil
  end
  -- pokefirered/src/field_control_avatar.c:142
  if FieldMoves.isWaterfallBehavior(Collision.behavior(tx, ty)) then
    Player.forceStep("down", function() end)
  else
    Player.scriptStep("down")
  end
end

--- White-out / heal respawn via game3 map loader (H7).
function Field.respawnAtHeal(opts)
  local session = Field._session
  if not session then return end
  local HealLocations = require("src.core.game3.heal_locations")
  HealLocations.normalizeSession(session)
  if not (opts and opts.fieldMove) then
    -- pokefirered/src/overworld.c:1553 CB2_WhiteOut
    local okS, Safari = pcall(require, "src.core.game3.safari")
    if okS and Safari and Safari.reset then Safari.reset(session) end
  end
  if not (opts and opts.fieldMove) and ModRuntime.wants("world.blacked_out") then
    ModRuntime.emit("world.blacked_out", {
      save = session,
      healTarget = { map = session.healMap, x = session.healX, y = session.healY },
    })
  end
  if not (opts and opts.fieldMove) then
    -- pokefirered/src/overworld.c:1553 CB2_WhiteOut
    local Party = require("src.core.game3.party")
    Party.healAll(session.party)
  end
  local Map = require("src.core.game3.map")
  local mapId = session.healMap or "FR_PLAYERS_HOUSE_1F"
  local hx = session.healX or 8
  local hy = session.healY or 5
  local warp = opts and opts.warp
  if type(warp) == "string" then warp = { map = warp } end
  if type(warp) == "table" and type(warp.map) == "string" then
    -- pokefirered/src/overworld.c:656 SetWarpDestinationToEscapeWarp
    mapId = warp.map
    hx = tonumber(warp.x) or hx
    hy = tonumber(warp.y) or hy
  end
  Map.load(Field._mod, Field._game, mapId, {
    x = hx,
    y = hy,
    facing = "down",
    depth1Connections = true,
    heal = true,
  })
  Player.reset(hx, hy, "down")
  Player.syncToHost(Field._game)
  -- pokefirered/src/heal_location.c:119 SetWhiteoutRespawnHealerNpcAsLastTalked
  local healerId = tonumber(session.healHealerLocalId)
  if healerId and not (opts and opts.fieldMove) then
    local Space = package.loaded["src.core.game3.scripting.space"]
    if Space and Space.store then
      local Flags = require("src.core.game3.scripting.flags")
      local Ctx = require("src.core.game3.scripting.ctx")
      Flags.setVar(Space.store, Space.vm and Space.vm.ctx or nil, Ctx.VAR_LAST_TALKED, healerId)
    end
  end
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

local function passableColl(mapDef, pair, mid)
  local Interaction = require("src.core.game3.scripting.interaction_scripts")
  local behaviors = pair and Interaction.behaviors and Interaction.behaviors[pair]
  local beh = behaviors and behaviors[mid]
  if beh ~= nil then
    local ScriptColl = require("src.core.game3.scripting.collision")
    return (ScriptColl.fromCell(mid, 0, beh, mapDef.kind))
  end
  local okR, Register = pcall(require, "src.import.gba.register")
  local midIndex = okR and Register and Register._midIndex
  local row = midIndex and pair and midIndex[pair] and midIndex[pair][mid]
  return row and row.coll or 0x00
end

-- pokefirered/src/scrcmd.c:2103
function Field.setMetatile(x, y, metatile, isImpassable)
  x, y = tonumber(x) or 0, tonumber(y) or 0
  isImpassable = isImpassable == true or (tonumber(isImpassable) or 0) ~= 0
  local session = Field._session
  local mapId = session and session.map
  if mapId then
    local bucket = Field.metatileOverrides[mapId]
    if not bucket then
      bucket = {}
      Field.metatileOverrides[mapId] = bucket
    end
    bucket[y * 1024 + x] = {
      x = x, y = y, metatile = metatile, impassable = isImpassable,
    }
  end
  if ModRuntime.wants("world.block_replaced") then
    ModRuntime.emit("world.block_replaced", { mapId = mapId, bx = x, by = y, block = metatile })
  end
  local game = Field._game
  local data = game and game.data and game.data.maps
  local mapDef = mapId and data and data[mapId]
  local mid = tonumber(metatile) or 0
  if mapDef and mapDef.midLayout then
    local layout = mapDef.midLayout
    local pair = mapDef.pair or layout.pair
    local coll = isImpassable and 0x07 or passableColl(mapDef, pair, mid)
    -- pokefirered/src/fieldmap.c:407
    layout:applyOverride(x, y, mid, coll, layout:elevAt(x, y))
    Field._overrideLayouts[mapId] = layout
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
