-- pret pokefirered/src/field_specials.c:2319-2456 — Birth Island Deoxys triangle.
--
-- The "triangle" is a single 32x32 inanimate rock object that the puzzle slides
-- between eleven fixed positions. Every successful interaction advances the rock
-- one position and shifts its palette one step towards the bright red "awakened"
-- colours; walking more than the per-position step cap resets the puzzle.
-- Reaching position 10 makes Deoxys appear.

local Deoxys = {}

-- pokefirered/include/constants/field_effects.h:71-72
Deoxys.FLDEFF_MOVE_ROCK = 67
Deoxys.FLDEFF_DESTROY_ROCK = 68

-- pokefirered/include/constants/vars.h
Deoxys.VAR_DEOXYS_INTERACTION_NUM = 0x403E
Deoxys.VAR_DEOXYS_INTERACTION_STEP_COUNTER = 0x4026
-- pokefirered/include/constants/flags.h
Deoxys.FLAG_SYS_DEOXYS_AWAKENED = 0x848

-- pokefirered/include/constants/event_objects.h
Deoxys.OBJ_EVENT_GFX_METEORITE = 106

-- pokefirered/include/constants/map_groups.h — gMapGroup_SpecialArea:56
Deoxys.MAP_GROUP = 2
Deoxys.MAP_NUM = 56
Deoxys.MAP_ID = "FR_BIRTH_ISLAND_EXTERIOR"

-- tools/mapjson/mapjson.cpp:415 numbers local_id 1-based in object_events order.
Deoxys.LOCALID_ROCK = 1
Deoxys.LOCALID_DEOXYS = 2

-- pokefirered/include/constants/songs.h
Deoxys.SE_M_CONFUSE_RAY = 189
Deoxys.SE_DEOXYS_MOVE = 253
-- The event battle: EventScript_Deoxys plays MUS_ENCOUNTER_DEOXYS on the field,
-- then StartLegendaryBattle switches to the unique MUS_VS_DEOXYS.
Deoxys.MUS_ENCOUNTER_DEOXYS = 343
Deoxys.MUS_VS_DEOXYS = 339

-- pokefirered/include/constants/species.h:419 — FRLG internal id, not the
-- National Dex number (386 is SPECIES_VOLBEAT).
Deoxys.SPECIES_DEOXYS = 410

-- pokefirered/src/field_specials.c:2334 — index 0..10 == interaction num.
Deoxys.COORDS = {
  { 15, 12 }, { 11, 14 }, { 15, 8 }, { 19, 14 }, { 12, 11 }, { 18, 11 },
  { 15, 14 }, { 11, 14 }, { 19, 14 }, { 15, 15 }, { 15, 10 },
}

-- pokefirered/src/field_specials.c:2346 — indexed by num-1, num in 1..10.
Deoxys.STEP_CAPS = { 4, 8, 8, 8, 4, 4, 4, 6, 3, 3 }

-- pret sDeoxysObjectPals (pokefirered/src/field_specials.c:2321, INCBIN of
-- graphics/field_specials/deoxys_rock_N.gbapal), ROM 0x3F6206: eleven 16-colour
-- BGR555 palettes. Entry 0 is the transparent OBJ index and is never drawn, so
-- only entries 1..3 are listed.
--
-- These are the 8-bit values the GBA 5-bit channels expand to (floor(x*255/31
-- + 0.5)), which is exactly what the extracted overworld sprites are baked
-- with.  They are NOT the raw ASCII numbers in the .pal files: those differ by
-- a unit or two and an exact-match recolour LUT would silently miss them.
Deoxys.ROCK_PALS = {
  { { 33, 33, 33 }, { 82, 82, 82 }, { 140, 140, 140 } },
  { { 41, 33, 33 }, { 82, 82, 82 }, { 140, 140, 140 } },
  { { 49, 33, 33 }, { 90, 82, 82 }, { 148, 148, 140 } },
  { { 66, 33, 33 }, { 115, 82, 82 }, { 156, 148, 140 } },
  { { 74, 33, 33 }, { 123, 82, 82 }, { 165, 156, 140 } },
  { { 99, 33, 33 }, { 140, 82, 82 }, { 173, 156, 140 } },
  { { 99, 33, 33 }, { 148, 82, 82 }, { 181, 165, 140 } },
  { { 107, 33, 33 }, { 156, 82, 82 }, { 189, 165, 140 } },
  { { 123, 33, 33 }, { 173, 82, 82 }, { 197, 173, 148 } },
  { { 132, 33, 33 }, { 181, 82, 82 }, { 206, 173, 148 } },
  { { 206, 33, 33 }, { 255, 82, 82 }, { 255, 206, 156 } },
}
Deoxys.PALETTE_COUNT = #Deoxys.ROCK_PALS

--- The colours the pristine meteorite sprite is drawn with (palette 0), i.e. the
--- source side of every recolour.  pret gets this for free because it loads the
--- whole 4-colour palette; the engine bakes the sprite once, so it has to be
--- told which colours to swap out.
function Deoxys.sourcePalette()
  return Deoxys.ROCK_PALS[1]
end

--- Clamp an interaction num to the 0..10 range the coordinate/palette tables use.
function Deoxys.clamp(num)
  num = math.floor(tonumber(num) or 0)
  if num < 0 then return 0 end
  if num > Deoxys.PALETTE_COUNT - 1 then return Deoxys.PALETTE_COUNT - 1 end
  return num
end

--- pret sDeoxysObjectPals[num] — the three opaque colours of that step.
function Deoxys.palette(num)
  return Deoxys.ROCK_PALS[Deoxys.clamp(num) + 1]
end

function Deoxys.paletteKey(num)
  return string.format("deoxys_rock_%d", Deoxys.clamp(num))
end

--- pret sDeoxysCoords[num].
function Deoxys.coords(num)
  local c = Deoxys.COORDS[Deoxys.clamp(num) + 1] or Deoxys.COORDS[1]
  return c[1], c[2]
end

--- pret gFieldEffectArguments[5]: 60 frames to snap home, 5 to nudge.
function Deoxys.moveFrames(num)
  return (Deoxys.clamp(num) == 0) and 60 or 5
end

--- pret sDeoxysStepCaps[num - 1]; nil outside 1..10.
function Deoxys.stepCap(num)
  num = math.floor(tonumber(num) or 0)
  return Deoxys.STEP_CAPS[num]
end

function Deoxys.isBirthIsland(mapId)
  if mapId == nil then return false end
  if mapId == Deoxys.MAP_ID then return true end
  local ok, MapCatalog = pcall(require, "src.import.gba.map_catalog")
  if ok and MapCatalog and MapCatalog.mapIdFor then
    local okId, id = pcall(MapCatalog.mapIdFor, Deoxys.MAP_GROUP, Deoxys.MAP_NUM)
    if okId and id then return id == mapId end
  end
  return false
end

-- ------------------------------------------------------------------ var access
local function flagsMod()
  return require("src.core.game3.scripting.flags")
end

--- The store the running script reads: the live Sevii store first (that is what
--- every other field special uses), then the session's own, then a view built
--- over the session tables so writes still land somewhere durable.
function Deoxys.storeOf(session)
  local Space = package.loaded["src.core.game3.scripting.space"]
  if Space and Space.store and Space.store.vars then return Space.store, false end
  if type(session) == "table" and type(session.store) == "table"
    and session.store.vars then
    return session.store, false
  end
  if type(session) == "table" then
    session.flags = type(session.flags) == "table" and session.flags or {}
    session.vars = type(session.vars) == "table" and session.vars or {}
    return { flags = session.flags, vars = session.vars }, true
  end
  return nil, false
end

function Deoxys.getVar(session, id)
  local store = Deoxys.storeOf(session)
  return tonumber(flagsMod().getVar(store, nil, id)) or 0
end

function Deoxys.setVar(session, id, value)
  local store, synthesized = Deoxys.storeOf(session)
  flagsMod().setVar(store, nil, id, value)
  -- Only mirror when the store is a view over the session tables; with a live
  -- store Space.persistSession owns that write-back.
  if synthesized and store then
    store.vars[id] = (tonumber(value) or 0) % 65536
  end
end

function Deoxys.getFlag(session, id)
  return flagsMod().getFlag(Deoxys.storeOf(session), nil, id) == true
end

function Deoxys.setFlag(session, id, on)
  flagsMod().setFlag(Deoxys.storeOf(session), nil, id, on ~= false)
end

-- ------------------------------------------------------------------- the rock
local function objectsMod()
  local Objects = package.loaded["src.core.game3.objects"]
  if type(Objects) == "table" then return Objects end
  local ok, mod = pcall(require, "src.core.game3.objects")
  if ok and type(mod) == "table" then return mod end
  return nil
end

--- The Birth Island meteorite object event, or nil when it is not on the map.
--- Falls back to whichever object uses the meteorite graphics so a different
--- local_id numbering cannot silently break the puzzle.
function Deoxys.resolveRockObject()
  local Objects = objectsMod()
  if not (Objects and Objects.find) then return nil, nil end
  local eo = Objects.find(Deoxys.LOCALID_ROCK)
  if eo and tonumber(eo.graphicsId) == Deoxys.OBJ_EVENT_GFX_METEORITE then
    return eo, Deoxys.LOCALID_ROCK
  end
  for id, cand in pairs(Objects._byId or {}) do
    if cand and tonumber(cand.graphicsId) == Deoxys.OBJ_EVENT_GFX_METEORITE then
      return cand, tonumber(id)
    end
  end
  return nil, nil
end

--- pret MoveDeoxysObject's LoadPalette(..., OBJ_PLTT_ID(10)) + ApplyGlobalFieldPaletteTint.
function Deoxys.applyRockPalette(num, graphicsId)
  local ok, OwSprites = pcall(require, "src.core.game3.ow_sprites")
  if not (ok and OwSprites and OwSprites.setObjectPalette) then return false end
  if graphicsId == nil then
    local eo = Deoxys.resolveRockObject()
    graphicsId = eo and eo.graphicsId
  end
  graphicsId = tonumber(graphicsId)
  if graphicsId == nil then return false end
  return OwSprites.setObjectPalette(graphicsId, Deoxys.paletteKey(num),
    Deoxys.palette(num), Deoxys.sourcePalette())
end

--- pret MoveDeoxysObject (field_specials.c:2362).
function Deoxys.moveRock(num)
  num = Deoxys.clamp(num)
  Deoxys.applyRockPalette(num)
  local okA, Audio = pcall(require, "src.core.game3.audio")
  if okA and Audio and Audio.playSe then
    Audio.playSe(num == 0 and Deoxys.SE_M_CONFUSE_RAY or Deoxys.SE_DEOXYS_MOVE)
  end
  local eo, localId = Deoxys.resolveRockObject()
  if not eo then return false end
  local x, y = Deoxys.coords(num)
  local okF, FieldEffects = pcall(require, "src.core.game3.field_effects")
  if not (okF and FieldEffects and FieldEffects.startMoveDeoxysRock) then
    return false
  end
  return FieldEffects.startMoveDeoxysRock(localId, x, y, Deoxys.moveFrames(num)) ~= nil
end

--- pret FldEff_DestroyDeoxysRock, driven by the BirthIsland_Exterior_EventScript_Deoxys
--- dofieldeffect.
function Deoxys.destroyRock(localId, graphicsId)
  local eo, id = Deoxys.resolveRockObject()
  if localId == nil then localId = id end
  if graphicsId == nil then graphicsId = eo and eo.graphicsId end
  local okF, FieldEffects = pcall(require, "src.core.game3.field_effects")
  if not (okF and FieldEffects and FieldEffects.startDestroyDeoxysRock) then
    return false
  end
  return FieldEffects.startDestroyDeoxysRock(localId, graphicsId) ~= nil
end

--- pret IncrementBirthIslandRockStepCount (field_specials.c:2433).
function Deoxys.incrementStepCount(session)
  if type(session) ~= "table" then return false end
  if not Deoxys.isBirthIsland(session.map) then return false end
  local count = Deoxys.getVar(session, Deoxys.VAR_DEOXYS_INTERACTION_STEP_COUNTER) + 1
  if count > 99 then count = 0 end
  Deoxys.setVar(session, Deoxys.VAR_DEOXYS_INTERACTION_STEP_COUNTER, count)
  return true
end

--- pret Task_DoDeoxysTriangleInteraction (field_specials.c:2325).
--- Returns the gSpecialVar_Result value the script switches on.
function Deoxys.interact(session)
  if Deoxys.getFlag(session, Deoxys.FLAG_SYS_DEOXYS_AWAKENED) then
    return 3
  end

  local num = Deoxys.getVar(session, Deoxys.VAR_DEOXYS_INTERACTION_NUM)
  local steps = Deoxys.getVar(session, Deoxys.VAR_DEOXYS_INTERACTION_STEP_COUNTER)
  Deoxys.setVar(session, Deoxys.VAR_DEOXYS_INTERACTION_STEP_COUNTER, 0)

  local cap = Deoxys.stepCap(num)
  if num ~= 0 and cap ~= nil and cap < steps then
    -- Walked too far for this position: the rock snaps back to the start.
    Deoxys.moveRock(0)
    Deoxys.setVar(session, Deoxys.VAR_DEOXYS_INTERACTION_NUM, 0)
    return 0
  elseif num == 10 then
    Deoxys.setFlag(session, Deoxys.FLAG_SYS_DEOXYS_AWAKENED, true)
    return 2
  end

  num = num + 1
  Deoxys.moveRock(num)
  Deoxys.setVar(session, Deoxys.VAR_DEOXYS_INTERACTION_NUM, num)
  return 1
end

return Deoxys
