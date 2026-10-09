-- pokeemerald/src/field_control_avatar.c:940

local function lazyReq(name)
  local m = package.loaded[name]
  if type(m) == "table" then return m end
  return require(name)
end

local Dive = {}

-- pokeemerald/include/constants/map_types.h:9
Dive.MAP_TYPE_UNDERWATER = 5

Dive._task = nil

local function MB() return require("src.core.game3.mb") end

local function mbIs(beh, ...)
  if beh == nil then return false end
  for i = 1, select("#", ...) do
    local id = MB().id((select(i, ...)))
    if id ~= nil and beh == id then return true end
  end
  return false
end

-- pokeemerald/src/metatile_behavior.c:853
function Dive.isDiveable(beh)
  return mbIs(beh, "INTERIOR_DEEP_WATER", "DEEP_WATER", "SOOTOPOLIS_DEEP_WATER")
end

-- pokeemerald/src/metatile_behavior.c:863
function Dive.isUnableToEmerge(beh)
  return mbIs(beh, "NO_SURFACING", "SEAWEED_NO_SURFACING")
end

local function session()
  local Runtime = package.loaded["src.core.game3.runtime"]
  return Runtime and Runtime.getSession and Runtime.getSession() or nil
end

local function currentDef()
  local Map = package.loaded["src.core.game3.map"]
  return Map and Map.currentDef and Map.currentDef() or nil, Map and Map.current or nil
end

function Dive.enabled(sess)
  local ok, Capabilities = pcall(lazyReq, "src.core.game3.capabilities")
  if not ok then return false end
  local okH, has = pcall(Capabilities.has, sess or session(), "dive")
  return okH and has == true
end

function Dive.isUnderwaterMap(def)
  return type(def) == "table" and tonumber(def.mapType) == Dive.MAP_TYPE_UNDERWATER
end

-- pokeemerald/src/overworld.c:756 SetDiveWarp
local function setDiveWarp(dir, def, mapId, x, y, sess)
  local c = def and def[dir]
  if type(c) == "table" and type(c.map) == "string" then
    return { map = c.map, x = x, y = y }
  end
  local Space = package.loaded["src.core.game3.scripting.space"]
  if Space and Space.runOnDiveWarp then Space.runOnDiveWarp(mapId) end
  local w = sess and sess.diveWarp
  -- pokeemerald/src/overworld.c:563 IsDummyWarp
  if type(w) ~= "table" or type(w.map) ~= "string" or (tonumber(w.x) or -1) < 0 then return nil end
  return { map = w.map, x = tonumber(w.x), y = tonumber(w.y), warpId = w.warpId }
end

-- pokeemerald/src/field_control_avatar.c:965 TrySetDiveWarp
function Dive.trySetDiveWarp(sess)
  sess = sess or session()
  local P = lazyReq("src.core.game3.player")
  local Collision = lazyReq("src.core.game3.collision")
  local def, mapId = currentDef()
  local x, y = P.cellX, P.cellY
  local beh = Collision.behavior(x, y)
  if Dive.isUnderwaterMap(def) and not Dive.isUnableToEmerge(beh) then
    local dest = setDiveWarp("emerge", def, mapId, x, y, sess)
    if dest then return 1, dest end
  elseif Dive.isDiveable(beh) then
    local dest = setDiveWarp("dive", def, mapId, x, y, sess)
    if dest then return 2, dest end
  end
  return 0, nil
end

local function badge(sess)
  local FieldMoves = lazyReq("src.core.game3.field_moves")
  local Space = package.loaded["src.core.game3.scripting.space"]
  return FieldMoves.hasBadge({ store = Space and Space.store, session = sess }, "DIVE")
end

local function fieldFree()
  local Field = package.loaded["src.core.game3.field"]
  if not (Field and Field.running) or Field.locked then return false end
  local Space = package.loaded["src.core.game3.scripting.space"]
  if not (Space and Space.active and Space.startScript) then return false end
  if Space.vm and Space.vm.isRunning and Space.vm:isRunning() then return false end
  local P = lazyReq("src.core.game3.player")
  if P.moving or P.jumping then return false end
  local Warp = package.loaded["src.core.game3.warp"]
  if Warp and Warp.isBusy and Warp.isBusy() then return false end
  return Dive._task == nil
end

local function startScript(label, alt)
  local Space = package.loaded["src.core.game3.scripting.space"]
  local key = Space.scriptKey(label) or (alt and Space.scriptKey(alt))
  if not key then error("dive: script " .. label .. " is not in the script cache", 0) end
  return Space.startScript(key) and true or false
end

-- pokeemerald/src/field_control_avatar.c:463 TrySetupDiveDownScript
function Dive.tryDiveDown()
  local sess = session()
  if not Dive.enabled(sess) or not fieldFree() then return false end
  if not badge(sess) then return false end
  local code = Dive.trySetDiveWarp(sess)
  if code ~= 2 then return false end
  return startScript("EventScript_UseDive")
end

-- pokeemerald/src/field_control_avatar.c:473 TrySetupDiveEmergeScript
function Dive.tryEmerge()
  local sess = session()
  if not Dive.enabled(sess) or not fieldFree() then return false end
  if not badge(sess) then return false end
  if not Dive.isUnderwaterMap((currentDef())) then return false end
  local code = Dive.trySetDiveWarp(sess)
  if code ~= 1 then return false end
  -- pokeruby/src/field_control_avatar.c:533
  return startScript("EventScript_UseDiveUnderwater", "S_UseDiveUnderwater")
end

function Dive.isActive()
  return Dive._task ~= nil
end

-- pokeemerald/src/field_effect.c:1902 FldEff_UseDive
function Dive.useDive(slot, mon)
  local sess = session()
  if not mon and sess and sess.party and slot then mon = sess.party[slot + 1] end
  local Field = lazyReq("src.core.game3.field")
  local Task = lazyReq("src.core.game3.task")
  local t = { state = 0, mon = mon }
  Dive._task = t
  Field.lock()
  Field.holdInput(true)
  Task.spawn(function()
    local Space = package.loaded["src.core.game3.scripting.space"]
    if t.state == 0 then
      if Space and Space.vm and Space.vm:isRunning() then return false end
      Field.lock()
      t.state = 1
      -- pokeemerald/src/field_effect.c:1924
      lazyReq("src.core.game3.field_move_show_mon").start(t.mon, { pose = false }, function() t.state = 2 end)
      return false
    elseif t.state == 1 then
      Field.lock()
      return false
    end
    -- pokeemerald/src/field_effect.c:1933
    Dive._task = nil
    Field.holdInput(false)
    local code, dest = Dive.trySetDiveWarp(sess)
    if code ~= 0 and dest then
      lazyReq("src.core.game3.audio").playSe(lazyReq("src.core.game3.se_ids").SE_M_DIVE)
      local Runtime = package.loaded["src.core.game3.runtime"]
      lazyReq("src.core.game3.warp").startDive(Runtime and Runtime._mod, Runtime and Runtime._game, dest.map, dest.x, dest.y)
    else
      Field.unlock()
    end
    return true
  end)
  return true
end

-- pokeemerald/src/overworld.c:911 GetAdjustedInitialTransitionFlags
function Dive.syncAvatar()
  if not Dive.enabled() then return end
  local P = lazyReq("src.core.game3.player")
  local def = currentDef()
  if not def then return end
  local under = Dive.isUnderwaterMap(def)
  if under == (P.underwater == true) then return end
  if P.moving then return end
  if under then
    P.underwater = true
    P.surfing = false
    return
  end
  P.underwater = false
  local Collision = lazyReq("src.core.game3.collision")
  if Collision.isSurfable and Collision.isSurfable(Collision.behavior(P.cellX, P.cellY)) then
    P.surfing = true
    local Audio = lazyReq("src.core.game3.audio")
    if Audio.canOverrideMapMusic(Audio.MUS_SURF) then
      Audio.playMapSong(Audio.MUS_SURF, { mapSong = Audio._mapSong })
    end
  end
end

function Dive.reset()
  Dive._task = nil
end

function Dive.install()
  local FieldEffects = lazyReq("src.core.game3.field_effects")
  if FieldEffects.HANDLERS.FLDEFF_USE_DIVE then return end
  -- pokeemerald/src/field_effect.c:1902
  FieldEffects.HANDLERS.FLDEFF_USE_DIVE = function()
    return Dive.useDive(FieldEffects.fieldEffectArgument(0, 0))
  end
end

return Dive
