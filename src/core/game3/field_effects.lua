-- FRLG field effects engine (pret fldeff_*.c).
-- Handles pure ROM-extracted field effect sprites and animations:
-- Tall grass, Cut grass leaves, Rock smash rubble, Surf blob, Fly bird, Ripples,
-- Flash screen flash, Dig / Teleport warp spin, Sweet scent aroma.

local Extract = require("src.import.gba.extract_island1")

local FieldEffects = {}

FieldEffects._cache = nil
FieldEffects._sheets = {} -- [name] = { image = ..., quads = ..., fw = ..., fh = ..., frames = ... }
FieldEffects._fx = nil    -- tall grass
FieldEffects._anims = {}  -- transient active field animations
FieldEffects._ground = nil -- pokefirered/src/event_object_movement.c:8721
FieldEffects._surfClock = 0
FieldEffects._logged = false
-- pokefirered/src/scrcmd.c:2051 — gFieldEffectArguments, written by
-- setfieldeffectargument and read by the effect that dofieldeffect starts.
FieldEffects._fieldEffectArguments = {}
-- waitfieldeffect callers parked until isFieldEffectActive(id) goes false.
FieldEffects._waiters = {}

-- pokefirered/include/constants/field_effects.h:71-72
FieldEffects.FLDEFF_MOVE_DEOXYS_ROCK = 67
FieldEffects.FLDEFF_DESTROY_DEOXYS_ROCK = 68

-- pokefirered/include/constants/songs.h:81,80
local SE_THUNDER2 = 81
local SE_THUNDER = 80

-- How far a Deoxys rock shard travels before it counts as off-screen and is
-- dropped.  pret destroys each fragment once it leaves the 240x160 viewport
-- (field_effect.c:4015); the engine draws in world space, so this is a
-- viewport-sized bound around the shard's spawn point instead.
local FRAG_TRAVEL_X = 260
local FRAG_TRAVEL_Y = 200

local CELL = 16
local FEET_H = 8
local RUSTLE = { 1, 2, 3, 4, 0 }
local FRAME_DUR = 10
-- pokefirered/src/data/field_effects/field_effect_objects.h:1099
local FLY_BIRD_W, FLY_BIRD_H, FLY_BIRD_FRAMES = 64, 64, 5

-- Forward-declared so field-effect starters defined above the body can call it.
local play_se

local function log(msg)
  if FieldEffects._logged then return end
  FieldEffects._logged = true
  print("[game3/field_effects] " .. tostring(msg))
end

local function cache_root()
  return Extract.CACHE_ROOT or "data/generated/gba"
end

local function try_load_rgba(cache, rel, w, h)
  if not cache or not cache.read then return nil end
  local rgba = cache:read(rel)
  if not rgba or #rgba ~= w * h * 4 then return nil end
  if not (love and love.image and love.graphics) then return nil end
  local ok, id = pcall(love.image.newImageData, w, h, "rgba8", rgba)
  if not ok or not id then return nil end
  local img = love.graphics.newImage(id)
  if img.setFilter then img:setFilter("nearest", "nearest") end
  return img
end

local function try_load_png(path)
  if not (love and love.graphics and love.graphics.newImage) then return nil end
  local ok, img = pcall(love.graphics.newImage, path)
  if ok and img then
    if img.setFilter then img:setFilter("nearest", "nearest") end
    return img
  end
  return nil
end

local function load_sheet(name, fw, fh, frames)
  local memo = FieldEffects._sheets[name]
  if memo ~= nil then return memo or nil end
  local totalH = fh * frames
  local root = cache_root() .. "/field_effects/"
  local img = try_load_rgba(FieldEffects._cache, root .. name .. ".rgba", fw, totalH)
    or try_load_rgba(FieldEffects._cache, "field_effects/" .. name .. ".rgba", fw, totalH)
    or try_load_png(root .. name .. ".png")
  if not img then
    FieldEffects._sheets[name] = false
    return nil
  end

  local quads = {}
  local quadsFront = {}
  local iw, ih = img:getDimensions()
  for i = 0, frames - 1 do
    local y = i * fh
    if y + fh <= ih then
      quads[i] = love.graphics.newQuad(0, y, fw, fh, iw, ih)
      if fh >= FEET_H then
        quadsFront[i] = love.graphics.newQuad(0, y + (fh - FEET_H), fw, FEET_H, iw, ih)
      end
    end
  end

  local sheet = {
    image = img,
    quads = quads,
    quadsFront = quadsFront,
    fw = fw,
    fh = fh,
    frames = frames,
  }
  FieldEffects._sheets[name] = sheet
  return sheet
end

function FieldEffects.install(cache)
  FieldEffects._cache = cache
  FieldEffects._sheets = {}
  FieldEffects._fx = nil
  FieldEffects._anims = {}
  FieldEffects._ground = nil
  FieldEffects._surfClock = 0
  FieldEffects._logged = false
  local okV, FieldView = pcall(require, "src.core.game3.field_view")
  if okV and FieldView and FieldView.setCameraPanning then
    FieldView.setCameraPanning(0, 0)
    FieldView.setFlashRadius(nil)
  end
  local ok, Heal = pcall(require, "src.core.game3.pokecenter_heal")
  if ok and Heal and Heal.install then Heal.install(cache) end
end

function FieldEffects.invalidate()
  FieldEffects._sheets = {}
  FieldEffects._fx = nil
  FieldEffects._anims = {}
  FieldEffects._ground = nil
  local okV, FieldView = pcall(require, "src.core.game3.field_view")
  if okV and FieldView and FieldView.setCameraPanning then
    FieldView.setCameraPanning(0, 0)
    FieldView.setFlashRadius(nil)
  end
  local ok, Heal = pcall(require, "src.core.game3.pokecenter_heal")
  if ok and Heal and Heal.invalidate then Heal.invalidate() end
end

-- ---------------------------------------------------------------- Tall Grass
function FieldEffects.tallGrassAt(cx, cy, seekEnd)
  local sheet = load_sheet("tall_grass", 16, 16, 5)
  if not sheet then return end
  cx, cy = tonumber(cx) or 0, tonumber(cy) or 0
  local fx = FieldEffects._fx
  if fx and fx.cx == cx and fx.cy == cy and not fx.leaving then return end
  FieldEffects._fx = {
    cx = cx,
    cy = cy,
    timer = 0,
    step = seekEnd and (#RUSTLE - 1) or 0,
    leaving = false,
    done = false,
  }
end

function FieldEffects.clearTallGrass()
  FieldEffects._fx = nil
end

function FieldEffects.leaveTallGrass()
  local fx = FieldEffects._fx
  if not fx then return end
  fx.leaving = true
end

-- ---------------------------------------------------------------- Transient Animations

--- Cut tree animation: tree slices and collapses (pret EventScript_CutTreeDown / Movement_CutTreeDown)
function FieldEffects.startCutTree(targetObj, cx, cy, onDone)
  cx, cy = tonumber(cx) or 0, tonumber(cy) or 0
  local anim = {
    kind = "cut_tree",
    targetObj = targetObj,
    cx = cx,
    cy = cy,
    timer = 0,
    maxDur = 24, -- 4 frames (0, 1, 2, 3) at 6 ticks per frame
    onDone = onDone,
  }
  table.insert(FieldEffects._anims, anim)
end

--- Cut grass leaves scattering animation across 3x3 tiles (pret FldEff_CutGrass)
function FieldEffects.startCutGrass(cx, cy, onDone)
  load_sheet("cut_grass", 8, 8, 1)
  cx, cy = tonumber(cx) or 0, tonumber(cy) or 0
  local px = cx * CELL
  local py = cy * CELL

  local particles = {}
  for i = 1, 8 do
    local angle = (i - 1) * (math.pi / 4)
    local spd = 1.2 + math.random() * 1.0
    particles[#particles + 1] = {
      x = px + 4,
      y = py + 4,
      vx = math.cos(angle) * spd,
      vy = math.sin(angle) * spd - 1.0,
      frame = 0,
    }
  end

  local anim = {
    kind = "cut_grass_scatter",
    cx = cx,
    cy = cy,
    timer = 0,
    maxDur = 24,
    particles = particles,
    onDone = onDone,
  }
  table.insert(FieldEffects._anims, anim)
end

--- Rock smash rubble exploding animation
function FieldEffects.startRockSmash(targetObj, cx, cy, onDone)
  load_sheet("rock_smash", 16, 16, 4)
  cx, cy = tonumber(cx) or 0, tonumber(cy) or 0
  local px = cx * CELL
  local py = cy * CELL

  local particles = {}
  for i = 1, 8 do
    local angle = (i - 1) * (math.pi / 4) + (math.random() * 0.3 - 0.15)
    local spd = 1.2 + math.random() * 1.6
    particles[#particles + 1] = {
      x = px + 4,
      y = py + 4,
      vx = math.cos(angle) * spd,
      vy = math.sin(angle) * spd - 1.5,
      frame = math.random(0, 3),
    }
  end

  local anim = {
    kind = "rock_smash",
    targetObj = targetObj,
    cx = cx,
    cy = cy,
    timer = 0,
    maxDur = 24,
    particles = particles,
    onDone = onDone,
  }
  table.insert(FieldEffects._anims, anim)
end

local function fieldView()
  local ok, FieldView = pcall(require, "src.core.game3.field_view")
  if ok and type(FieldView) == "table" then return FieldView end
  return nil
end

--- pokefirered/src/field_screen_effect.c:194
function FieldEffects.animateFlashLevel(fromLevel, toLevel)
  local FieldView = fieldView()
  if not FieldView then return nil end
  local from = FieldView.radiusForLevel(fromLevel)
  local to = FieldView.radiusForLevel(toLevel)
  if from == to then
    FieldView.setFlashLevel(toLevel)
    return nil
  end
  FieldView.setFlashRadius(from)
  local anim = {
    kind = "flash_level",
    radius = from,
    dest = to,
    delta = (from < to) and 2 or -2,
    level = tonumber(toLevel) or 0,
    clear = (tonumber(toLevel) or 0) == 0,
    state = 0,
    timer = 0,
  }
  table.insert(FieldEffects._anims, anim)
  return anim
end

--- Screen flash animation (Flash HM)
function FieldEffects.startFlash(onDone)
  local anim = {
    kind = "flash",
    alpha = 1.0,
    timer = 0,
    maxDur = 30,
  }
  table.insert(FieldEffects._anims, anim)
  -- pokefirered/data/scripts/flash.inc:2
  local FieldView = fieldView()
  local levelAnim
  if FieldView and FieldView.getFlashLevel and FieldView.getFlashLevel() ~= 0 then
    levelAnim = FieldEffects.animateFlashLevel(FieldView.getFlashLevel(), 0)
  end
  -- pokefirered/src/field_screen_effect.c:202
  if levelAnim then
    levelAnim.onDone = onDone
  else
    anim.onDone = onDone
  end
  return levelAnim or anim
end

--- pokefirered/src/field_effect.c:1258
function FieldEffects.startLandingShake(onDone)
  local anim = {
    kind = "camera_shake",
    amp = 4,
    ticks = 0,
    timer = 0,
    onDone = onDone,
  }
  table.insert(FieldEffects._anims, anim)
  return anim
end

local function player_gender()
  local R = package.loaded["src.core.game3.runtime"]
  local s = R and R.getSession and R.getSession()
  return (s and tonumber(s.gender)) or 0
end

--- Fly Bird takeoff and landing animations
function FieldEffects.startFlyTakeoff(onMidWarp, onDone)
  load_sheet("fly_bird", FLY_BIRD_W, FLY_BIRD_H, FLY_BIRD_FRAMES)
  local P = package.loaded["src.core.game3.player"]
  local px = P and P.px or 0
  local py = P and P.py or 0
  local anim = {
    kind = "fly_takeoff",
    px = px - 24,
    py = py - 72,
    targetPy = py - 40,
    state = "descend",
    timer = 0,
    frame = 0,
    -- pokefirered/src/field_effect.c:3312
    ridingFrame = player_gender() * 2 + 1,
    onMidWarp = onMidWarp,
    onDone = onDone,
  }
  table.insert(FieldEffects._anims, anim)
end

function FieldEffects.startFlyLanding(onDone)
  load_sheet("fly_bird", FLY_BIRD_W, FLY_BIRD_H, FLY_BIRD_FRAMES)
  local P = package.loaded["src.core.game3.player"]
  local px = P and P.px or 0
  local py = P and P.py or 0
  local anim = {
    kind = "fly_landing",
    px = px - 24,
    py = py - 92,
    targetPy = py - 40,
    state = "descend",
    timer = 0,
    -- pokefirered/src/field_effect.c:3550
    frame = player_gender() * 2 + 2,
    onDone = onDone,
  }
  table.insert(FieldEffects._anims, anim)
end

--- Dig / Teleport warp spin
function FieldEffects.startWarpSpin(kind, onDone)
  local anim = {
    kind = "warp_spin",
    warpKind = kind or "teleport",
    timer = 0,
    maxDur = 40,
    onDone = onDone,
  }
  table.insert(FieldEffects._anims, anim)
end

--- Sweet scent aroma waves
function FieldEffects.startSweetScent(onDone)
  local anim = {
    kind = "sweet_scent",
    timer = 0,
    maxDur = 50,
    radius = 0,
    onDone = onDone,
  }
  table.insert(FieldEffects._anims, anim)
end

--- pokefirered/src/field_effect.c:3878 — BlendPalettes(PALETTES_BG, 0x10, RGB_WHITE).
function FieldEffects.startWhiteFlash(duration)
  local anim = {
    kind = "flash",
    alpha = 1.0,
    timer = 0,
    maxDur = math.max(1, math.floor(tonumber(duration) or 16)),
  }
  table.insert(FieldEffects._anims, anim)
  return anim
end

-- ------------------------------------------------- Birth Island Deoxys effects

--- pokefirered/src/field_effect.c:3722 — slide the meteorite object to (x, y).
--- pret works in object-event coords offset by +7 so the sprite visibly travels
--- a long way; here the sprite simply lerps from its current pixel position to
--- the target cell, which reads the same on screen.
function FieldEffects.startMoveDeoxysRock(localId, x, y, frames)
  local Objects = package.loaded["src.core.game3.objects"]
  if not (Objects and Objects.find) then return nil end
  local eo = Objects.find(localId)
  if not eo then return nil end
  local fromX, fromY = eo.px or 0, eo.py or 0
  local toX, toY = (tonumber(x) or 0) * CELL, (tonumber(y) or 0) * CELL
  -- Snap the home/template coords immediately, exactly like
  -- SetObjEventTemplateCoords: the script-visible position must already be final
  -- when the next interaction runs.
  Objects.setObjectXY(localId, x, y)
  -- setObjectXY snaps px/py to the destination; keep the sprite drawn where it
  -- was so the lerp below actually slides it instead of teleporting.
  eo.px, eo.py = fromX, fromY
  frames = math.max(1, math.floor(tonumber(frames) or 5))
  local anim = {
    kind = "deoxys_rock_move",
    localId = localId,
    fromX = fromX,
    fromY = fromY,
    toX = toX,
    toY = toY,
    timer = 0,
    maxDur = frames,
    effectId = FieldEffects.FLDEFF_MOVE_DEOXYS_ROCK,
  }
  table.insert(FieldEffects._anims, anim)
  return anim
end

--- pokefirered/src/field_effect.c:3840 — camera shake, thunder, then the rock
--- shatters into four fragments and is removed from the map.
function FieldEffects.startDestroyDeoxysRock(localId, graphicsId)
  local Objects = package.loaded["src.core.game3.objects"]
  local eo = Objects and Objects.find and Objects.find(localId)
  if not eo then return nil end
  local x, y = eo.px or 0, eo.py or 0
  graphicsId = graphicsId or eo.graphicsId

  -- pokefirered/src/field_effect.c:3975 CreateDeoxysRockFragments: all four
  -- shards start at the rock's own top-left corner (4px higher) and fly apart.
  -- eo.px/py is the cell's foot point, so undo the offset OwSprites.draw adds.
  local originX, originY = x - 8, y - 20
  local okO, OwSprites = pcall(require, "src.core.game3.ow_sprites")
  if okO and OwSprites and OwSprites.getDraw then
    local spr = OwSprites.getDraw(graphicsId)
    if spr and spr.width and spr.height then
      originX = x + (16 - spr.width) / 2
      originY = y + 16 - spr.height - 4
    end
  end

  -- pokefirered/src/field_effect.c:3993 SpriteCB_DeoxysRockFragment: fixed
  -- ±16 x / ±12 y per frame, no gravity, one shard per diagonal.
  local frags = {}
  local dirs = { { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }
  for i = 1, 4 do
    frags[i] = {
      frame = i - 1,
      x = originX,
      y = originY,
      ox = originX,
      oy = originY,
      dx = dirs[i][1] * 16,
      dy = dirs[i][2] * 12,
      off = false,
    }
  end
  local anim = {
    kind = "deoxys_rock_destroy",
    localId = localId,
    graphicsId = graphicsId,
    x = x,
    y = y,
    px = x,
    py = y,
    timer = 0,
    state = "shake",
    frags = frags,
    effectId = FieldEffects.FLDEFF_DESTROY_DEOXYS_ROCK,
  }
  table.insert(FieldEffects._anims, anim)
  play_se(SE_THUNDER2)
  return anim
end

local EMOTE_BASES = {
  [0] = 0,
  [1] = 6,
  [2] = 3,
  [3] = 9,
  [4] = 12,
  exclamation = 0,
  double_exclamation = 6,
  x = 3,
  smile = 9,
  question = 12,
  question_mark = 12,
  [0x62] = 0,
  [0x63] = 12,
  [0x64] = 3,
  [0x65] = 6,
  [0x66] = 9,
}

--- Start emote bubble animation over target object (pret FLDEFF_*_ICON / sSpriteAnimTable_Emoticons)
function FieldEffects.startEmote(targetObj, emoteType, onDone)
  load_sheet("emoticons", 16, 16, 15)
  local baseFrame = EMOTE_BASES[emoteType] or 0
  local anim = {
    kind = "emote",
    targetObj = targetObj,
    timer = 0,
    maxDur = 60, -- 4 + 4 + 52 frames matching pokefirered
    baseFrame = baseFrame,
    frame = baseFrame,
    onDone = onDone,
  }
  table.insert(FieldEffects._anims, anim)
  if emoteType == "exclamation" or emoteType == 0 or emoteType == 0x62 or
     emoteType == "double_exclamation" or emoteType == 1 or emoteType == 0x65 then
    local okA, Audio = pcall(require, "src.core.game3.audio")
    if okA and Audio and Audio.playSe then
      Audio.playSe(21) -- SE_PIN
    end
  end
  return anim
end

--- Exclamation mark '!' emote animation over target object (pret FLDEFF_EXCLAMATION_MARK_ICON / sAnim_ExclamationMark)
function FieldEffects.startExclamation(targetObj, onDone)
  return FieldEffects.startEmote(targetObj, "exclamation", onDone)
end

--- Alias for vs_seeker and other callers
function FieldEffects.spawnEmoticon(targetObj, emoteType, onDone)
  return FieldEffects.startEmote(targetObj, emoteType, onDone)
end

-- pokefirered/include/constants/metatile_behaviors.h:14
local MB_POND_WATER = 0x10
-- pokefirered/include/constants/metatile_behaviors.h:20
local MB_PUDDLE = 0x16
local MB_SHALLOW_WATER = 0x17

-- pokefirered/src/data/field_effects/field_effect_objects.h:571 sAnim_Splash_0
local ANIM_SPLASH = { { 0, 4 }, { 1, 4 } }
-- pokefirered/src/data/field_effects/field_effect_objects.h:578 sAnim_Splash_1
local ANIM_FEET_IN_FLOWING_WATER = {
  { 0, 4 }, { 1, 4 }, { 0, 6 }, { 1, 6 }, { 0, 8 }, { 1, 8 }, { 0, 6 }, { 1, 6 },
}
-- pokefirered/src/data/field_effects/field_effect_objects.h:108 sAnim_Ripple
local ANIM_RIPPLE = {
  { 0, 12 }, { 1, 9 }, { 2, 9 }, { 3, 9 }, { 0, 9 }, { 1, 9 }, { 2, 11 }, { 4, 11 },
}

local SE_PUDDLE = 63

local function anim_frame(seq, t, loop)
  local total = 0
  for i = 1, #seq do total = total + seq[i][2] end
  if total <= 0 then return nil end
  if loop then
    t = t % total
  elseif t >= total then
    return nil
  end
  local acc = 0
  for i = 1, #seq do
    acc = acc + seq[i][2]
    if t < acc then return seq[i][1] end
  end
  return seq[#seq][1]
end

function play_se(id)
  local okA, Audio = pcall(require, "src.core.game3.audio")
  if okA and Audio and Audio.playSe then Audio.playSe(id) end
end

-- ------------------------------------------------- setfieldeffectargument plumbing
-- pokefirered/src/scrcmd.c:2051 writes gFieldEffectArguments[argNum]; the value
-- operand is VarGet'd, which passes raw constants (< 0x4000) straight through.
function FieldEffects.setFieldEffectArgument(argNum, value)
  argNum = math.floor(tonumber(argNum) or -1)
  if argNum < 0 or argNum > 15 then return false end
  FieldEffects._fieldEffectArguments[argNum] = math.floor(tonumber(value) or 0)
  return true
end

function FieldEffects.fieldEffectArgument(argNum, default)
  local v = FieldEffects._fieldEffectArguments[argNum]
  if v == nil then return default end
  return v
end

function FieldEffects.clearFieldEffectArguments()
  FieldEffects._fieldEffectArguments = {}
end

local function resolve_waiters()
  local pending = FieldEffects._waiters
  if #pending == 0 then return end
  local keep = {}
  for i = 1, #pending do
    local w = pending[i]
    if FieldEffects.isFieldEffectActive(w.id) then
      keep[#keep + 1] = w
    elseif w.done then
      w.done()
    end
  end
  FieldEffects._waiters = keep
end

local function ground_state()
  local g = FieldEffects._ground
  if not g then
    g = { inShallowFlowingWater = false, inHotSprings = false, moving = false }
    FieldEffects._ground = g
  end
  return g
end

local function behavior_at(cx, cy)
  local Collision = package.loaded["src.core.game3.collision"]
  if not (Collision and Collision.behavior) then return nil end
  return Collision.behavior(cx, cy)
end

local function is_hot_springs(beh)
  local Collision = package.loaded["src.core.game3.collision"]
  if Collision and Collision.isHotSprings then return Collision.isHotSprings(beh) end
  return false
end

-- pokefirered/src/event_object_movement.c:8143
local function flag_shallow_flowing_water(g, cur, prev)
  if cur == MB_SHALLOW_WATER and prev == MB_SHALLOW_WATER then
    if not g.inShallowFlowingWater then
      g.inShallowFlowingWater = true
      return true
    end
  else
    g.inShallowFlowingWater = false
  end
  return false
end

-- pokefirered/src/event_object_movement.c:8163
local function flag_puddle(cur, prev)
  return cur == MB_PUDDLE and prev == MB_PUDDLE
end

-- pokefirered/src/event_object_movement.c:8172
local function flag_ripple(cur)
  return cur == MB_POND_WATER or cur == MB_PUDDLE
end

-- pokefirered/src/event_object_movement.c:8196
local function flag_hot_springs(g, cur, prev)
  if is_hot_springs(cur) and is_hot_springs(prev) then
    if not g.inHotSprings then
      g.inHotSprings = true
      return true
    end
  else
    g.inHotSprings = false
  end
  return false
end

local function has_anim(kind)
  for _, anim in ipairs(FieldEffects._anims) do
    if anim.kind == kind then return true end
  end
  return false
end

local GROUND_KINDS = { splash = true, feet_water = true, hot_springs = true, ripple = true }

local function clear_ground_anims()
  local keep = {}
  for _, anim in ipairs(FieldEffects._anims) do
    if not GROUND_KINDS[anim.kind] then keep[#keep + 1] = anim end
  end
  FieldEffects._anims = keep
end

-- pokefirered/src/event_object_movement.c:8580 GroundEffect_StepOnPuddle
local function start_splash()
  load_sheet("splash", 16, 8, 2)
  table.insert(FieldEffects._anims, { kind = "splash", timer = 0, frame = 0 })
  play_se(SE_PUDDLE)
end

-- pokefirered/src/event_object_movement.c:8505 GroundEffect_FlowingWater
local function start_feet_in_flowing_water()
  if has_anim("feet_water") then return end
  load_sheet("splash", 16, 8, 2)
  table.insert(FieldEffects._anims, { kind = "feet_water", timer = 0, frame = 0 })
end

-- pokefirered/src/event_object_movement.c:8575 GroundEffect_Ripple
local function start_ripple(cx, cy)
  load_sheet("ripple", 16, 16, 5)
  table.insert(FieldEffects._anims,
    { kind = "ripple", timer = 0, frame = 0, cx = cx, cy = cy })
end

-- pokefirered/src/event_object_movement.c:8652 GroundEffect_HotSprings
local function start_hot_springs()
  if has_anim("hot_springs") then return end
  load_sheet("hot_springs_water", 16, 16, 1)
  table.insert(FieldEffects._anims, { kind = "hot_springs", timer = 0, frame = 0 })
end

-- pokefirered/src/event_object_movement.c:8023 GetAllGroundEffectFlags_OnSpawn
local function ground_effects_on_spawn(g, cur, prev)
  if flag_shallow_flowing_water(g, cur, prev) then start_feet_in_flowing_water() end
  if flag_hot_springs(g, cur, prev) then start_hot_springs() end
end

-- pokefirered/src/event_object_movement.c:8035 GetAllGroundEffectFlags_OnBeginStep
local function ground_effects_on_begin_step(g, cur, prev)
  if flag_shallow_flowing_water(g, cur, prev) then start_feet_in_flowing_water() end
  if flag_puddle(cur, prev) then start_splash() end
  if flag_hot_springs(g, cur, prev) then start_hot_springs() end
end

-- pokefirered/src/event_object_movement.c:8049 GetAllGroundEffectFlags_OnFinishStep
local function ground_effects_on_finish_step(g, cur, jumped)
  -- pokefirered/src/event_object_movement.c:5343 ShiftStillObjectEventCoords (previous := current)
  local prev = cur
  if flag_shallow_flowing_water(g, cur, prev) then start_feet_in_flowing_water() end
  -- pokefirered/src/event_object_movement.c:8715 FilterOutStepOnPuddleGroundEffectIfJumping
  if flag_puddle(cur, prev) and not jumped then start_splash() end
  if flag_ripple(cur) then start_ripple(g.cx, g.cy) end
  if flag_hot_springs(g, cur, prev) then start_hot_springs() end
end

--- pokefirered/src/event_object_movement.c:8721 DoGroundEffects_OnSpawn / OnBeginStep / OnFinishStep
function FieldEffects.groundEffects()
  local P = package.loaded["src.core.game3.player"]
  if not P then return end
  local moving = P.moving and true or false
  local cx, cy
  if moving then
    cx, cy = P.targetX or P.cellX, P.targetY or P.cellY
  else
    cx, cy = P.cellX, P.cellY
  end
  if cx == nil or cy == nil then return end
  local g = ground_state()
  local Map = package.loaded["src.core.game3.map"]
  local mapId = Map and Map.current
  if mapId ~= g.mapId then
    -- pokefirered/src/event_object_movement.c:1934 ResetObjectEventFldEffData
    g.mapId = mapId
    g.inShallowFlowingWater = false
    g.inHotSprings = false
    g.cx, g.cy, g.px, g.py = nil, nil, nil, nil
    g.moving = false
    clear_ground_anims()
  end
  if moving == g.moving and cx == g.cx and cy == g.cy then return end

  local px, py = cx, cy
  if moving or g.moving then px, py = P.prevCellX or cx, P.prevCellY or cy end
  local wasMoving = g.moving
  local wasPx = g.px
  local wasJump = g.jumped
  g.moving = moving
  g.cx, g.cy = cx, cy
  g.px, g.py = px, py
  g.jumped = moving and (P.jumping and true or false) or false

  if wasMoving and moving and wasPx ~= nil then
    g.cx, g.cy = px, py
    ground_effects_on_finish_step(g, behavior_at(px, py), wasJump)
    g.cx, g.cy = cx, cy
  end

  -- pokefirered/src/event_object_movement.c:8062 ObjectEventUpdateMetatileBehaviors
  local cur = behavior_at(cx, cy)
  local prev = behavior_at(px, py)

  if moving and not wasMoving then
    ground_effects_on_begin_step(g, cur, prev)
  elseif wasMoving and not moving then
    ground_effects_on_finish_step(g, cur, wasJump)
  elseif wasMoving and moving then
    ground_effects_on_begin_step(g, cur, prev)
  else
    -- pokefirered/src/event_object_movement.c:1934 ResetObjectEventFldEffData
    g.inShallowFlowingWater = false
    g.inHotSprings = false
    clear_ground_anims()
    ground_effects_on_spawn(g, cur, prev)
  end
end

-- ---------------------------------------------------------------- Step & Update
function FieldEffects.step()
  FieldEffects.groundEffects()
  -- Tall grass update
  local fx = FieldEffects._fx
  if fx and not fx.done then
    fx.timer = fx.timer + 1
    if fx.timer >= FRAME_DUR then
      fx.timer = 0
      fx.step = fx.step + 1
      if fx.step >= #RUSTLE then
        if fx.leaving then
          fx.done = true
          FieldEffects._fx = nil
        else
          fx.step = #RUSTLE - 1
        end
      end
    end
  end

  -- Surfing blob clock (48 ticks per frame * 2 frames = 96 ticks per loop)
  FieldEffects._surfClock = (FieldEffects._surfClock + 1) % 96

  -- Update active transient animations
  local active = {}
  for _, anim in ipairs(FieldEffects._anims) do
    anim.timer = anim.timer + 1
    local finished = false

    if anim.kind == "cut_tree" then
      -- Animate tree object through frames 0..3 (6 ticks per frame)
      local frame = math.min(3, math.floor(anim.timer / 6))
      if anim.targetObj then
        anim.targetObj.customFrame = frame
      end
      -- Update scattering leaf particles with gravity
      for _, p in ipairs(anim.particles or {}) do
        p.x = p.x + p.vx
        p.y = p.y + p.vy
        p.vy = p.vy + 0.12 -- gravity
        p.frame = math.floor(anim.timer / 4) % 4
      end
      if anim.timer >= anim.maxDur then
        finished = true
      end
    elseif anim.kind == "cut_grass_scatter" then
      for _, p in ipairs(anim.particles or {}) do
        p.x = p.x + p.vx
        p.y = p.y + p.vy
        p.vy = p.vy + 0.12
        p.frame = math.floor(anim.timer / 4) % 4
      end
      if anim.timer >= anim.maxDur then
        finished = true
      end
    elseif anim.kind == "rock_smash" then
      local frame = math.min(3, math.floor(anim.timer / 6))
      if anim.targetObj then
        anim.targetObj.customFrame = frame
      end
      for _, p in ipairs(anim.particles or {}) do
        p.x = p.x + p.vx
        p.y = p.y + p.vy
        p.vy = p.vy + 0.15 -- gravity
        p.frame = math.floor(anim.timer / 4) % 4
      end
      if anim.timer >= anim.maxDur then
        finished = true
      end
    elseif anim.kind == "flash" then
      anim.alpha = math.max(0, 1.0 - (anim.timer / anim.maxDur))
      if anim.timer >= anim.maxDur then
        finished = true
      end
    elseif anim.kind == "flash_level" then
      -- pokefirered/src/field_screen_effect.c:119
      local FieldView = fieldView()
      if not FieldView then
        finished = true
      elseif anim.state == 2 then
        FieldView.setFlashLevel(anim.level)
        finished = true
      else
        FieldView.setFlashRadius(anim.radius)
        if anim.state == 0 then
          anim.state = 1
        else
          anim.state = 0
          anim.radius = anim.radius + anim.delta
          if anim.radius > anim.dest then
            if anim.clear then
              anim.state = 2
            else
              FieldView.setFlashLevel(anim.level)
              finished = true
            end
          end
        end
      end
    elseif anim.kind == "camera_shake" then
      local FieldView = fieldView()
      if not FieldView then
        finished = true
      elseif anim.amp == 0 then
        -- pokefirered/src/field_camera.c:513
        FieldView.setCameraPanning(0, 0)
        finished = true
      else
        FieldView.setCameraPanning(0, anim.amp)
        anim.amp = -anim.amp
        anim.ticks = anim.ticks + 1
        if anim.ticks % 4 == 0 then
          anim.amp = math.floor(anim.amp / 2)
        end
      end
    elseif anim.kind == "fly_takeoff" then
      -- pokefirered/src/field_effect.c:3342
      anim.frame = (anim.state == "descend") and 0 or (anim.ridingFrame or 1)
      if anim.state == "descend" then
        anim.py = anim.py + 2
        if anim.py >= anim.targetPy then
          anim.py = anim.targetPy
          anim.state = "ascend"
        end
      elseif anim.state == "ascend" then
        anim.py = anim.py - 3
        if anim.py <= -82 then
          finished = true
          if anim.onMidWarp then anim.onMidWarp() end
        end
      end
    elseif anim.kind == "fly_landing" then
      if anim.state == "descend" then
        anim.py = anim.py + 2
        if anim.py >= anim.targetPy then
          anim.py = anim.targetPy
          anim.state = "leave"
        end
      elseif anim.state == "leave" then
        anim.py = anim.py - 3
        if anim.py <= -82 then
          finished = true
        end
      end
    elseif anim.kind == "warp_spin" then
      local P = package.loaded["src.core.game3.player"]
      local facings = { "down", "left", "up", "right" }
      if P then
        P.facing = facings[(math.floor(anim.timer / 3) % 4) + 1]
      end
      if anim.timer >= anim.maxDur then
        finished = true
      end
    elseif anim.kind == "sweet_scent" then
      anim.radius = (anim.timer / anim.maxDur) * 120
      if anim.timer >= anim.maxDur then
        finished = true
      end
    elseif anim.kind == "emote" or anim.kind == "exclamation" then
      local base = anim.baseFrame or 0
      if anim.timer < 4 then
        anim.frame = base
      elseif anim.timer < 8 then
        anim.frame = base + 1
      else
        anim.frame = base + 2
      end
      if anim.timer >= anim.maxDur then
        finished = true
      end
    elseif anim.kind == "splash" then
      -- pokefirered/src/field_effect_helpers.c:626 UpdateSplashFieldEffect
      local frame = anim_frame(ANIM_SPLASH, anim.timer - 1, false)
      if frame then anim.frame = frame else finished = true end
    elseif anim.kind == "feet_water" then
      -- pokefirered/src/field_effect_helpers.c:707 UpdateFeetInFlowingWaterFieldEffect
      local g = FieldEffects._ground
      if not (g and g.inShallowFlowingWater) then
        finished = true
      else
        anim.frame = anim_frame(ANIM_FEET_IN_FLOWING_WATER, anim.timer - 1, true) or 0
        if g.cx and (g.cx ~= anim.cx or g.cy ~= anim.cy) then
          anim.cx, anim.cy = g.cx, g.cy
          play_se(SE_PUDDLE)
        end
      end
    elseif anim.kind == "hot_springs" then
      -- pokefirered/src/field_effect_helpers.c:777 UpdateHotSpringsWaterFieldEffect
      local g = FieldEffects._ground
      if not (g and g.inHotSprings) then finished = true end
    elseif anim.kind == "deoxys_rock_move" then
      -- pokefirered/src/field_effect.c:3745 — linear sprite lerp over maxDur frames.
      local t = math.min(1, anim.timer / anim.maxDur)
      local Objects = package.loaded["src.core.game3.objects"]
      local eo = Objects and Objects.find and Objects.find(anim.localId)
      if eo then
        eo.px = anim.fromX + (anim.toX - anim.fromX) * t
        eo.py = anim.fromY + (anim.toY - anim.fromY) * t
      end
      if anim.timer >= anim.maxDur then
        if eo then
          eo.px, eo.py = anim.toX, anim.toY
          -- pret ShiftStillObjectEventCoords + triggerGroundEffectsOnStop.
          if Objects.copyObjectXYToPerm then Objects.copyObjectXYToPerm(anim.localId) end
        end
        finished = true
      end
    elseif anim.kind == "deoxys_rock_destroy" then
      -- pokefirered/src/field_effect.c:3860 DestroyDeoxysRockEffect_*
      local FieldView = fieldView()
      if anim.state == "shake" then
        -- Task_DeoxysRockCameraShake (data[7]==0): full amplitude, sign flips
        -- every other frame.
        if FieldView and FieldView.setCameraPanning then
          FieldView.setCameraPanning(0, (anim.timer % 2 == 0) and 4 or -4)
        end
        if anim.timer >= 120 then
          local Objects = package.loaded["src.core.game3.objects"]
          local eo = Objects and Objects.find and Objects.find(anim.localId)
          if eo then
            eo.px, eo.py = anim.x, anim.y
            eo.invisible = true
            eo.hidden = true
            eo.visible = false
          end
          FieldEffects.startWhiteFlash()
          play_se(SE_THUNDER)
          anim.state = "shatter"
          anim.timer = 0
          anim.amp = 4
        end
      elseif anim.state == "shatter" then
        -- The shards fly out while the shake decays (StartEndingDeoxysRock
        -- CameraShake + the data[7]!=0 half of Task_DeoxysRockCameraShake).
        for _, f in ipairs(anim.frags) do
          if not f.off then
            f.x = f.x + f.dx
            f.y = f.y + f.dy
            if math.abs(f.x - f.ox) > FRAG_TRAVEL_X
              or math.abs(f.y - f.oy) > FRAG_TRAVEL_Y then
              f.off = true
            end
          end
        end
        if anim.timer > 0 and anim.timer % 21 == 0 and anim.amp > 0 then
          anim.amp = anim.amp - 1
        end
        if FieldView and FieldView.setCameraPanning then
          FieldView.setCameraPanning(0,
            (anim.timer % 2 == 0) and anim.amp or -anim.amp)
        end
        if anim.amp <= 0 then
          if FieldView and FieldView.setCameraPanning then
            FieldView.setCameraPanning(0, 0)
          end
          local Objects = package.loaded["src.core.game3.objects"]
          if Objects and Objects.removeObject then Objects.removeObject(anim.localId) end
          finished = true
        end
      end
    elseif anim.kind == "ripple" then
      -- pokefirered/src/field_effect_helpers.c:737 FldEff_Ripple
      local frame = anim_frame(ANIM_RIPPLE, anim.timer - 1, false)
      if frame then anim.frame = frame else finished = true end
    end

    if finished then
      if anim.onDone then anim.onDone() end
    else
      table.insert(active, anim)
    end
  end
  FieldEffects._anims = active

  resolve_waiters()

  local ok, Heal = pcall(require, "src.core.game3.pokecenter_heal")
  if ok and Heal and Heal.step then Heal.step() end
end

-- ---------------------------------------------------------------- Drawing

--- Draw behind player (Surf blob, tall grass bottom, etc.)
function FieldEffects.drawBehind(camX, camY)
  camX, camY = camX or 0, camY or 0

  -- 1) Surfing water mount (pret FLDEFF_SURF_BLOB)
  local P = package.loaded["src.core.game3.player"]
  if P and (P.surfing or P.surfHopping or P.dismounting) then
    local surfSheet = load_sheet("surf_blob", 32, 32, 6)
    if surfSheet then
      local facing = P.facing or "down"
      local step = math.floor(FieldEffects._surfClock / 48) % 2
      local frameIdx = 0
      local flip = false

      if facing == "down" then
        frameIdx = 0 + step
      elseif facing == "up" then
        frameIdx = 2 + step
      elseif facing == "left" then
        frameIdx = 4 + step
      elseif facing == "right" then
        frameIdx = 4 + step
        flip = true
      end

      local q = surfSheet.quads[frameIdx]
      if q then
        local sx, sy
        if P.surfHopping then
          -- Player is hopping onto water: blob is in position on the destination tile
          sx = (P.targetX or P.cellX) * CELL - camX - 8
          sy = (P.targetY or P.cellY) * CELL - camY - 8
        elseif P.dismounting then
          -- Player is hopping off water to land: blob remains at origin tile
          sx = P.cellX * CELL - camX - 8
          sy = P.cellY * CELL - camY - 8
        else
          local bob = (not P.moving and not P.jumping) and ((step == 1) and -1 or 0) or 0
          sx = P.px - camX - 8
          sy = P.py - camY - 8 + bob
        end

        love.graphics.setColor(1, 1, 1, 1)
        if flip then
          love.graphics.draw(surfSheet.image, q, sx + 32, sy, 0, -1, 1)
        else
          love.graphics.draw(surfSheet.image, q, sx, sy)
        end
      end
    end
  end

  -- 2) Tall grass base pad
  local fx = FieldEffects._fx
  if fx then
    local sheet = load_sheet("tall_grass", 16, 16, 5)
    if sheet then
      local frameIdx = RUSTLE[fx.step + 1] or 0
      local q = sheet.quads[frameIdx]
      if q then
        local sx = fx.cx * CELL - camX
        local sy = fx.cy * CELL - camY
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(sheet.image, q, sx, sy)
      end
    end
  end

  -- pokefirered/src/event_object_movement.c:9404 DoRippleFieldEffect
  for _, anim in ipairs(FieldEffects._anims) do
    if anim.kind == "ripple" then
      local sheet = load_sheet("ripple", 16, 16, 5)
      local q = sheet and sheet.quads[anim.frame or 0]
      if q then
        local sx = anim.cx * CELL - camX
        local sy = anim.cy * CELL + 6 - camY
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(sheet.image, q, sx, sy)
      end
    end
  end
end

--- Draw in front of player (feet cover, cut grass particles, rock smash rubble, bird, ripples)
function FieldEffects.drawFront(camX, camY, playerPy)
  camX, camY = camX or 0, camY or 0

  -- 1) Tall grass feet cover
  local fx = FieldEffects._fx
  if fx then
    local sheet = load_sheet("tall_grass", 16, 16, 5)
    if sheet and sheet.quadsFront then
      local drawCover = true
      if playerPy ~= nil then
        local feetY = playerPy + CELL
        local grassTop = fx.cy * CELL
        local grassBot = grassTop + CELL
        if feetY < grassTop + FEET_H or feetY > grassBot + 2 then
          drawCover = false
        end
      end
      if drawCover then
        local frameIdx = RUSTLE[fx.step + 1] or 0
        local q = sheet.quadsFront[frameIdx]
        if q then
          local sx = fx.cx * CELL - camX
          local sy = fx.cy * CELL - camY + (16 - FEET_H)
          love.graphics.setColor(1, 1, 1, 1)
          love.graphics.draw(sheet.image, q, sx, sy)
        end
      end
    end
  end

  -- 2) Transient particle animations
  for _, anim in ipairs(FieldEffects._anims) do
    if anim.kind == "cut_grass_scatter" then
      local sheet = load_sheet("cut_grass", 8, 8, 1)
      if sheet then
        for _, p in ipairs(anim.particles or {}) do
          local q = sheet.quads[0]
          if q then
            local sx = p.x - camX
            local sy = p.y - camY
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(sheet.image, q, sx, sy)
          end
        end
      end
    elseif anim.kind == "rock_smash" then
      local sheet = load_sheet("rock_smash", 16, 16, 4)
      if sheet then
        for _, p in ipairs(anim.particles or {}) do
          local q = sheet.quads[p.frame % 4]
          if q then
            local sx = p.x - camX
            local sy = p.y - camY
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(sheet.image, q, sx, sy)
          end
        end
      end
    elseif anim.kind == "deoxys_rock_destroy" and anim.state == "shatter" then
      -- pokefirered/src/field_effect.c:3975 CreateDeoxysRockFragments (4x 8x8 sprites)
      local sheet = load_sheet("deoxys_rock_fragments", 8, 8, 4)
      if sheet then
        for _, f in ipairs(anim.frags or {}) do
          if not f.off then
            local q = sheet.quads[f.frame]
            if q then
              love.graphics.setColor(1, 1, 1, 1)
              love.graphics.draw(sheet.image, q, f.x - camX, f.y - camY)
            end
          end
        end
      end
    elseif anim.kind == "fly_takeoff" or anim.kind == "fly_landing" then
      local sheet = load_sheet("fly_bird", FLY_BIRD_W, FLY_BIRD_H, FLY_BIRD_FRAMES)
      if sheet and sheet.quads[anim.frame] then
        local sx = anim.px - camX
        local sy = anim.py - camY
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(sheet.image, sheet.quads[anim.frame], sx, sy)
      end
    elseif anim.kind == "emote" or anim.kind == "exclamation" then
      local sheet = load_sheet("emoticons", 16, 16, 15)
      if sheet and sheet.quads[anim.frame] then
        local t = anim.targetObj
        local ox = t and (t.px or (t.cellX and t.cellX * CELL) or (t.x and t.x * CELL)) or 0
        local oy = t and (t.py or (t.cellY and t.cellY * CELL) or (t.y and t.y * CELL)) or 0
        local sx = ox - camX
        local sy = oy - 16 - camY
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(sheet.image, sheet.quads[anim.frame], sx, sy)
      end
    elseif anim.kind == "splash" or anim.kind == "feet_water" then
      -- pokefirered/src/field_effect_helpers.c:598 FldEff_Splash
      local sheet = load_sheet("splash", 16, 8, 2)
      local P = package.loaded["src.core.game3.player"]
      local q = sheet and P and sheet.quads[anim.frame or 0]
      if q then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(sheet.image, q, P.px - camX, P.py + FEET_H - camY)
      end
    elseif anim.kind == "hot_springs" then
      -- pokefirered/src/field_effect_helpers.c:777 UpdateHotSpringsWaterFieldEffect
      local sheet = load_sheet("hot_springs_water", 16, 16, 1)
      local P = package.loaded["src.core.game3.player"]
      local q = sheet and P and sheet.quads[0]
      if q then
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(sheet.image, q, P.px - camX, P.py - camY)
      end
    end
  end
end

function FieldEffects.draw(camX, camY, playerPy)
  FieldEffects.drawFront(camX, camY, playerPy)
end

--- Screen-space overlay (Flash screen glow, Sweet scent aroma, Pokemon Center heal)
function FieldEffects.drawOverlay(camX, camY)
  -- 1) Flash screen illumination
  for _, anim in ipairs(FieldEffects._anims) do
    if anim.kind == "flash" and anim.alpha > 0 then
      local okR, Renderer = pcall(require, "src.render.Renderer")
      if okR and Renderer and Renderer.canvas then
        Renderer.screenVeil = { 1, 1, 1, anim.alpha }
      else
        love.graphics.setColor(1, 1, 1, anim.alpha)
        local w, h = 240, 160
        local curCanvas = love.graphics.getCanvas()
        if curCanvas then
          local okW, cw, ch = pcall(function() return curCanvas:getWidth(), curCanvas:getHeight() end)
          if okW and cw and ch then w, h = cw, ch end
        elseif love and love.graphics and love.graphics.getDimensions then
          local gw, gh = love.graphics.getDimensions()
          if gw and gh and gw > 0 and gh > 0 then w, h = gw, gh end
        end
        love.graphics.rectangle("fill", 0, 0, w, h)
        love.graphics.setColor(1, 1, 1, 1)
      end
    elseif anim.kind == "sweet_scent" then
      love.graphics.setColor(1, 0.7, 0.9, 0.6 * (1.0 - (anim.timer / anim.maxDur)))
      love.graphics.circle("line", 120, 80, anim.radius)
      love.graphics.circle("line", 120, 80, math.max(0, anim.radius - 20))
      love.graphics.setColor(1, 1, 1, 1)
    end
  end

  local ok, Heal = pcall(require, "src.core.game3.pokecenter_heal")
  if ok and Heal and Heal.draw then Heal.draw(camX, camY) end
end

--- pret dofieldeffect / waitfieldeffect for FLDEFF_POKECENTER_HEAL (25).
function FieldEffects.doFieldEffect(id)
  id = tonumber(id) or 0
  if id == FieldEffects.FLDEFF_MOVE_DEOXYS_ROCK then
    -- pokefirered/src/field_effect.c:3722 FldEff_MoveDeoxysRock reads
    -- gFieldEffectArguments[0..5] written by setfieldeffectargument.
    local localId = FieldEffects.fieldEffectArgument(0, 1)
    local x = FieldEffects.fieldEffectArgument(3, 15)
    local y = FieldEffects.fieldEffectArgument(4, 12)
    local frames = FieldEffects.fieldEffectArgument(5, 5)
    return FieldEffects.startMoveDeoxysRock(localId, x, y, frames) ~= nil
  end
  if id == FieldEffects.FLDEFF_DESTROY_DEOXYS_ROCK then
    -- pokefirered/src/field_effect.c:3860 FldEff_DestroyDeoxysRock
    local localId = FieldEffects.fieldEffectArgument(0, 1)
    return FieldEffects.startDestroyDeoxysRock(localId) ~= nil
  end
  local ok, Heal = pcall(require, "src.core.game3.pokecenter_heal")
  if ok and Heal and id == Heal.FLDEFF then
    return Heal.start()
  end
  return false
end

function FieldEffects.waitFieldEffect(id, done)
  id = tonumber(id) or 0
  if id == FieldEffects.FLDEFF_MOVE_DEOXYS_ROCK
    or id == FieldEffects.FLDEFF_DESTROY_DEOXYS_ROCK then
    if not FieldEffects.isFieldEffectActive(id) then
      if done then done() end
      return
    end
    FieldEffects._waiters[#FieldEffects._waiters + 1] = { id = id, done = done }
    return
  end
  local ok, Heal = pcall(require, "src.core.game3.pokecenter_heal")
  if ok and Heal and id == Heal.FLDEFF then
    Heal.wait(done)
    return
  end
  if done then done() end
end

function FieldEffects.isFieldEffectActive(id)
  id = tonumber(id) or 0
  if id == FieldEffects.FLDEFF_MOVE_DEOXYS_ROCK
    or id == FieldEffects.FLDEFF_DESTROY_DEOXYS_ROCK then
    for _, anim in ipairs(FieldEffects._anims) do
      if anim.effectId == id then return true end
    end
    return false
  end
  local ok, Heal = pcall(require, "src.core.game3.pokecenter_heal")
  if ok and Heal and id == Heal.FLDEFF then
    return Heal.isActive()
  end
  return false
end

return FieldEffects
