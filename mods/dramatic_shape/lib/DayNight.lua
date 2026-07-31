-- Voxel world mode: the day/night cycle -- one clock, and everything the
-- frame asks it.
--
-- THE CLOCK is twenty minutes around: ten of day, ten of night. The DAYTIME
-- row either PINS it -- DAY, NIGHT, DUSK and DAWN are fixed times on that
-- dial, not separate looks -- or lets it run (CYCLE), in which case the pin
-- the player left is where the cycle picks up. Everything below is a pure
-- function of the clock, so the pinned settings and the running cycle can
-- never drift apart: DUSK is simply the cycle stopped at sunset.
--
-- THE SUN's noon is this mod's existing sun, exactly: shear (-0.85, -0.55),
-- hanging in the southeast about 45 degrees up. That is the DAY setting and
-- the default, so a player who never touches the row sees the mod they
-- already had. From there the arc swings NORTH at both ends -- rising 70
-- degrees north of east, setting the mirror of that -- because the camera
-- looks north and the northern sky is the only sky it ever frames: a sun
-- that rose due east would light the world for ten minutes without once
-- being seen. Swung north, the disc stands in frame through dawn and dusk
-- (the hours worth looking at) and passes overhead-behind-the-camera
-- through midday, which is where a noon sun belongs.
--
-- THE MOON arcs entirely through the northern sky -- rising northeast, due
-- north at mid-night, setting northwest -- so it hangs over the diorama all
-- night and the pinned NIGHT setting puts it dead centre. Its shadows fall
-- softly south, away from it, at about two-thirds the sun's weight.
--
-- SHADOWS are the shear the light throws: direction opposite the body's
-- bearing, length its elevation's cotangent (clamped -- a rising sun throws
-- a long shadow, not an infinite one), strength fading to nothing over the
-- last twelve degrees before the horizon so the handoff between sun and
-- moon is a soft gap rather than a snap. Face shading (Voxel3D.FACE_SHADE)
-- deliberately stays the noon bake: it is a subtle angle term baked into
-- every mesh, and rebaking the world's geometry per phase buys less than
-- the cast shadows, the sky and the tint already say.
--
-- OUTDOOR ONLY. Indoors keeps the noon rig, the untinted world and no sky:
-- a cave at midnight is exactly as dark as a cave at noon, which is what a
-- room with no windows looks like. Map.isOutdoor is the same test the sky
-- already rests on; the caller passes its answer in (applyRig/tint).
--
-- Persistence: the running cycle's clock is written into the mod's own
-- save-file bucket (save.modData.DRAMATIC_SHAPE, via mod.save) on the
-- engine's save.writing event, and read back on save.loaded/created. A save
-- with no clock in it starts at noon.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local ModSetting = V.require("ModSetting")
local PaletteFX = require("src.render.PaletteFX")

local DayNight = {}

-- ------- the dial

DayNight.CYCLE = 1200         -- seconds around the whole dial
DayNight.DAY_LEN = 600        -- the sun's half; the moon has the rest
DayNight.BLEND = 75           -- seconds of palette blend either side of a twilight

-- where the pinned settings stop the clock
DayNight.T = { dawn = 0, day = 300, dusk = 600, night = 900 }

DayNight.KEY = "daytime"
DayNight.LABEL = "DAYTIME"

-- "sync" first: an unset or unreadable value follows the machine's own
-- clock, per the row's contract (ModSetting values[1] is the default) --
-- and forceSync below reaches for it by the same position.
DayNight.setting = ModSetting.new(DayNight.KEY, DayNight.LABEL,
                                  { "sync", "day", "night", "dusk",
                                    "dawn", "cycle" },
                                  { "SYNC", "DAY", "NIGHT", "DUSK",
                                    "DAWN", "CYCLE" })

-- The one writer for the FULL pin. While VOXEL sits on FULL the DAYTIME
-- row is off the menu with the rest of the rows the preset owns, and the
-- value is held HERE at SYNC -- the diorama preset's sky follows the clock
-- on the wall, whatever was chosen before. Called from every path that can
-- arrive at or act under FULL (main.lua: the preset itself, the rows hook,
-- the manager's options_changed), mirroring OverworldBattle.forceOG.
function DayNight.forceSync(game)
  if DayNight.setting:get() ~= "sync" then
    DayNight.setting:setIndex(1, game)
  end
end

DayNight.clock = DayNight.T.day     -- the running cycle's own position

-- ------- the two arcs
--
-- Bearings in DEGREES from east toward south (the world's +X is east, +Z
-- south), elevations in degrees up from the ground plane.

-- noon IS the existing sun: shear (-0.85, -0.55) hangs it at
-- atan2(0.55, 0.85) south of east, atan(1/hypot) = 44.65 degrees up
local NOON_KX, NOON_KZ = -0.85, -0.55
local TH_NOON = math.deg(math.atan2(-NOON_KZ, -NOON_KX))
local EL_NOON = math.deg(math.atan(1 / math.sqrt(NOON_KX * NOON_KX
                                                 + NOON_KZ * NOON_KZ)))

local TH_RISE, TH_SET = -70, 250            -- north of east / north of west
local TH_MRISE, TH_MMID, TH_MSET = -20, -90, -160
local EL_MOON = 40

DayNight.K_MAX = 2.0          -- shear clamp: a shadow at most twice its height
DayNight.ALPHA_SUN = 0.40     -- the existing midday shadow weight
DayNight.ALPHA_MOON = 0.26    -- moonlight is a softer press
DayNight.FADE_DEG = 12        -- shadows fade out over the last degrees of a rise/set

-- disc PLACEMENT only: the true elevation would put the noon sun far above
-- any frame, so the arc the discs ride is squashed toward the horizon. The
-- shadows always use the true elevation.
DayNight.ELEV_SQUASH = 0.14

-- three-point arc: a at s=0, b at s=0.5, c at s=1
local function arc(a, b, c, s)
  if s < 0.5 then return a + (b - a) * 2 * s end
  return b + (c - b) * (2 * s - 1)
end

-- The body lighting the world at clock `t`: bearing and elevation in
-- degrees, and whether it is the moon. The t == DAY_LEN boundary belongs to
-- the SUN, so the pinned DUSK setting is the sun half-set in the northwest,
-- not the moon rising.
function DayNight.bodyAt(t)
  t = t % DayNight.CYCLE
  if t <= DayNight.DAY_LEN then
    local s = t / DayNight.DAY_LEN
    return arc(TH_RISE, TH_NOON, TH_SET, s),
           EL_NOON * math.sin(math.pi * s), false
  end
  local s = (t - DayNight.DAY_LEN) / (DayNight.CYCLE - DayNight.DAY_LEN)
  return arc(TH_MRISE, TH_MMID, TH_MSET, s),
         EL_MOON * math.sin(math.pi * s), true
end

-- The shadow shear that body throws: drift per pixel of height, opposite
-- the bearing, cot(elevation) long, clamped.
function DayNight.shearAt(t)
  local th, el, moon = DayNight.bodyAt(t)
  if el < 0.5 then el = 0.5 end
  local k = math.min(DayNight.K_MAX, 1 / math.tan(math.rad(el)))
  return -math.cos(math.rad(th)) * k, -math.sin(math.rad(th)) * k, moon
end

-- How much shadow the light can press right now, 0..1 of the body's own
-- weight: full up high, gone at the horizon, so sunset hands off to
-- moonrise through a soft shadowless gap instead of snapping.
function DayNight.strengthAt(t)
  local _, el = DayNight.bodyAt(t)
  local s = el / DayNight.FADE_DEG
  if s < 0 then return 0 end
  return s < 1 and s or 1
end

-- ------- the palettes
--
-- Sky bands, lightest FIRST (the horizon end), exactly the shape Sky.bands
-- reads. Six bands, not four: twilight is the whole show here, and six rungs
-- of it is what keeps a sunset reading as a gradient rather than as stripes.
-- Every channel is a multiple of 8 -- the 5-bit GBC lattice -- including
-- after blending, which re-quantises onto it.
-- `golden` and `violet` are not pins -- they are WAYPOINTS the blends pass
-- through. Day's blue horizon and dusk's gold one are near-complements, and
-- a straight lerp between complements bottoms out in grey: mid-transition
-- the whole sky went the colour of dishwater, and gold-to-navy did the same
-- on the far side of sunset. So the evening bends through a golden hour
-- (horizon warming, zenith still blue -- late afternoon), and both edges of
-- the night bend through a violet civil twilight (rose horizon under a
-- violet sky -- the real colour of that half hour).
DayNight.PALETTES = {
  day = { { 184, 216, 248 }, { 144, 192, 248 }, { 104, 160, 240 },
          { 72, 128, 224 }, { 48, 96, 200 }, { 40, 72, 168 } },
  golden = { { 248, 216, 144 }, { 232, 184, 136 }, { 176, 152, 168 },
             { 120, 128, 192 }, { 80, 104, 184 }, { 56, 80, 152 } },
  dawn = { { 248, 216, 152 }, { 248, 176, 136 }, { 232, 136, 144 },
           { 176, 104, 168 }, { 112, 80, 168 }, { 64, 64, 136 } },
  dusk = { { 248, 200, 112 }, { 248, 152, 96 }, { 232, 104, 96 },
           { 184, 80, 136 }, { 120, 64, 152 }, { 56, 48, 120 } },
  violet = { { 200, 136, 160 }, { 152, 104, 160 }, { 112, 80, 152 },
             { 72, 56, 128 }, { 40, 40, 96 }, { 16, 24, 64 } },
  night = { { 88, 104, 160 }, { 64, 80, 136 }, { 48, 56, 112 },
            { 32, 40, 88 }, { 16, 24, 64 }, { 8, 8, 40 } },
}

-- what the world's own colours are multiplied by, per phase (0..255)
DayNight.TINTS = {
  day = { 255, 255, 255 },
  golden = { 255, 232, 208 },
  dawn = { 255, 216, 192 },
  dusk = { 255, 192, 168 },
  violet = { 184, 160, 200 },
  night = { 120, 136, 192 },
}

-- the twilight glow around the low sun, and the discs' own four-shade
-- palettes (lightest first, so a display mode transforms them like any
-- other palette)
DayNight.GLOWS = { dawn = { 248, 232, 176 }, dusk = { 248, 224, 168 } }
DayNight.SUN_COLORS = { { 248, 240, 200 }, { 248, 208, 96 },
                        { 248, 144, 80 }, { 216, 96, 64 } }
DayNight.MOON_COLORS = { { 240, 244, 248 }, { 224, 232, 240 },
                         { 168, 184, 208 }, { 120, 136, 168 } }

-- The dial as keyframes: a repeated name is a plateau, a change is a
-- BLEND-wide ramp. Laid out so DUSK and DAWN proper land exactly on their
-- pinned times, and so the evening approaches dusk THROUGH the golden-hour
-- waypoint rather than straight across the grey between blue and gold. The
-- morning side needs no waypoint of its own: dawn's pinks into day's blues
-- share a family and blend clean.
local DIAL
local function dial()
  if DIAL then return DIAL end
  local B, D, C = DayNight.BLEND, DayNight.DAY_LEN, DayNight.CYCLE
  DIAL = {
    { 0, "dawn" }, { B, "day" },
    { D - 2 * B, "day" }, { D - B, "golden" }, { D, "dusk" },
    { D + B / 2, "violet" }, { D + B, "night" },
    { C - B, "night" }, { C - B / 2, "violet" }, { C, "dawn" },
  }
  return DIAL
end

-- Phase weights at clock `t`, off the dial above.
function DayNight.mix(t)
  t = t % DayNight.CYCLE
  local d = dial()
  for i = 1, #d - 1 do
    local a, b = d[i], d[i + 1]
    if t >= a[1] and t < b[1] then
      if a[2] == b[2] then return { [a[2]] = 1 } end
      local u = (t - a[1]) / (b[1] - a[1])
      return { [a[2]] = 1 - u, [b[2]] = u }
    end
  end
  return { dawn = 1 }
end

-- back onto the 5-bit lattice after any blend
local function q8(v)
  v = math.floor(v / 8 + 0.5) * 8
  if v < 0 then return 0 end
  return v > 248 and 248 or v
end

local function blend3(key, mix, fallback)
  local r, g, b = 0, 0, 0
  for name, w in pairs(mix) do
    local c = key[name] or fallback
    r = r + c[1] * w
    g = g + c[2] * w
    b = b + c[3] * w
  end
  return { q8(r), q8(g), q8(b) }
end

-- The sky palette for clock `t`, blended between the phase palettes and
-- re-quantised to the lattice. Memoised per whole second: the answer only
-- moves as the cycle runs, and the cycle moves it slowly.
local palCache = { key = nil, pal = nil }

function DayNight.palette(t)
  t = t or DayNight.time()
  local key = math.floor(t % DayNight.CYCLE)
  if palCache.key == key then return palCache.pal end
  local mix = DayNight.mix(t)
  local pal = {}
  for i = 1, #DayNight.PALETTES.day do
    local r, g, b = 0, 0, 0
    for name, w in pairs(mix) do
      local c = DayNight.PALETTES[name][i]
      r = r + c[1] * w
      g = g + c[2] * w
      b = b + c[3] * w
    end
    pal[i] = { q8(r), q8(g), q8(b) }
  end
  palCache.key, palCache.pal = key, pal
  return pal
end

-- The world tint for clock `t`, {r, g, b} in 0..1. Neutral indoors -- the
-- caller answers for where it is standing (see the header).
local tintCache = { key = nil, tint = nil }
local NEUTRAL = { 1, 1, 1 }

function DayNight.tint(outdoor, t)
  if not outdoor then return NEUTRAL end
  t = t or DayNight.time()
  local key = math.floor(t % DayNight.CYCLE)
  if tintCache.key ~= key then
    -- NOT re-quantised: this is a light level the shader multiplies by, not
    -- a palette colour, and the lattice's 248 ceiling would make even noon
    -- fractionally dim
    local mix = DayNight.mix(t)
    local r, g, b = 0, 0, 0
    for name, w in pairs(mix) do
      local c = DayNight.TINTS[name] or DayNight.TINTS.day
      r = r + c[1] * w
      g = g + c[2] * w
      b = b + c[3] * w
    end
    tintCache.key = key
    tintCache.tint = { r / 255, g / 255, b / 255 }
  end
  return tintCache.tint
end

-- The twilight glow: how strongly (0..1) and in what colour the sky warms
-- around the low sun. Only the SUN glows -- a moonrise is silver, not gold.
function DayNight.glow(t)
  t = t or DayNight.time()
  local _, _, moon = DayNight.bodyAt(t)
  if moon then return 0, nil end
  local mix = DayNight.mix(t)
  local amt = (mix.dawn or 0) + (mix.dusk or 0)
  if amt <= 0 then return 0, nil end
  return amt, blend3(DayNight.GLOWS, mix, DayNight.GLOWS.dusk)
end

-- ------- the clock itself

local lastMode = nil

local function mode()
  return DayNight.setting:get() or "day"
end

-- Where SYNC reads the real clock: local hours, 0..24 with the minutes as
-- fraction. A named seam rather than a bare os.date call, so the suite can
-- hand it a fixed hour.
function DayNight.hours()
  local d = os.date("*t")
  return d.hour + d.min / 60 + d.sec / 3600
end

-- SYNC: the machine's own time of day laid onto the dial. Local noon is
-- the DAY pin, midnight the NIGHT pin, six and eighteen the twilights --
-- an hour of the real day is fifty seconds of dial, and Kanto's evening
-- falls when the player's does.
function DayNight.syncTime()
  return ((DayNight.hours() - 6) * (DayNight.CYCLE / 24)) % DayNight.CYCLE
end

-- The effective time: the pin, the running clock under CYCLE, or the wall
-- clock under SYNC.
function DayNight.time()
  local m = mode()
  if m == "cycle" then return DayNight.clock end
  if m == "sync" then return DayNight.syncTime() end
  return DayNight.T[m] or DayNight.T.day
end

-- Advance the cycle. Runs every frame from the voxel pipeline's update hook
-- (which ticks through battles and menus too, so night falls during a long
-- fight exactly as it does on a walk). Stepping ONTO cycle picks up from
-- the pin the player was just looking at: DUSK then CYCLE rolls on into
-- night rather than teleporting the sky.
function DayNight.update(dt)
  local m = mode()
  if m ~= lastMode then
    if m == "cycle" then
      -- from a pin, its time; from SYNC, wherever the real sky already was
      DayNight.clock = DayNight.T[lastMode]
                       or (lastMode == "sync" and DayNight.syncTime())
                       or DayNight.clock
    end
    lastMode = m
  end
  if m == "cycle" and dt and dt > 0 then
    DayNight.clock = (DayNight.clock + dt) % DayNight.CYCLE
  end
end

-- The clock the RIG runs on: quantised, so the shadow map redraws a few
-- times a minute as the sun crawls rather than every frame.
DayNight.STEP = 2

function DayNight.rigTime()
  local t = DayNight.time()
  return math.floor(t / DayNight.STEP) * DayNight.STEP
end

-- ------- what the frame reads

-- Point the shared light rig at the clock -- or at noon, indoors. This
-- writes the same fields everything already reads (ShadowMap.KX/KZ for the
-- sun pass and its frustum, Voxel3D.SHADOW_* for the decal fallback and the
-- sunDark uniform), so no draw path changes to follow the sun; they follow
-- the rig, and the rig follows the clock.
function DayNight.applyRig(outdoor)
  local ShadowMap = V.require("ShadowMap")
  local Voxel3D = V.require("Voxel3D")
  local t = outdoor and DayNight.rigTime() or DayNight.T.day
  local kx, kz, moon = DayNight.shearAt(t)
  ShadowMap.KX, ShadowMap.KZ = kx, kz
  Voxel3D.SHADOW_KX, Voxel3D.SHADOW_KZ = kx, kz
  local base = moon and DayNight.ALPHA_MOON or DayNight.ALPHA_SUN
  Voxel3D.SHADOW_ALPHA = base * DayNight.strengthAt(t)
  return t
end

-- How much of a pass's OWN shadow weight the hour leaves it, 0..1 -- for a
-- caller that sets its own alpha (the battle arena) and should still lose
-- its shadows to a sunset.
function DayNight.shadowScale(outdoor, t)
  if not outdoor then return 1 end
  t = t or DayNight.rigTime()
  local _, _, moon = DayNight.bodyAt(t)
  local s = DayNight.strengthAt(t)
  return moon and s * (DayNight.ALPHA_MOON / DayNight.ALPHA_SUN) or s
end

-- The disc to hang in the sky, or nil when the body is set or behind the
-- camera's half of the sky. Returns a direction for the PLACEMENT arc --
-- true bearing, squashed elevation (see ELEV_SQUASH) -- plus which body it
-- is; the caller projects it through its own camera.
function DayNight.body(t)
  t = t or DayNight.time()
  local th, el, moon = DayNight.bodyAt(t)
  if el < -2 then return nil end
  local e = math.rad(el * DayNight.ELEV_SQUASH)
  local b = math.rad(th)
  return {
    dx = math.cos(b) * math.cos(e),
    dy = math.sin(e),
    dz = math.sin(b) * math.cos(e),
    moon = moon,
  }
end

-- Maps under a CANOPY: not outdoor -- there is no sky to paint and no sun
-- or moon to see, so the shadow rig stays the mod's fixed noon light,
-- which is all that ever filtered through the leaves -- but not a sealed
-- room either: night still FALLS in them. Of everything the clock does,
-- exactly one thing reaches a canopy map: the hour's tint.
DayNight.CANOPY = { VIRIDIAN_FOREST = true }

function DayNight.isCanopy(map)
  return (map and map.id and DayNight.CANOPY[map.id]) and true or false
end

-- How lit the WINDOWS are, 0..1 -- the lamps behind the glass, not the sky.
-- They come on through dusk (a lit window against a sunset is half the point
-- of having either), burn all night, and are mostly out again by dawn:
-- people wake before it is bright, they do not read at sunrise.
local LAMPS = { night = 1, violet = 1, dusk = 0.7, dawn = 0.25 }

function DayNight.windowLight(t)
  local mix = DayNight.mix(t or DayNight.time())
  local lit = 0
  for name, w in pairs(mix) do
    lit = lit + (LAMPS[name] or 0) * w
  end
  return lit
end

-- The period name for the engine's world.tod hook (map.palette ctx.tod,
-- music.select): the dominant phase, in the vocabulary day/night mods use.
local TOD = { day = "DAY", golden = "DAY", night = "NIGHT",
              violet = "NIGHT", dawn = "MORNING", dusk = "EVENING" }

function DayNight.tod(t)
  local mix = DayNight.mix(t or DayNight.time())
  local best, bestW = "day", -1
  for name, w in pairs(mix) do
    if w > bestW then best, bestW = name, w end
  end
  return TOD[best] or "DAY"
end

-- ------- persistence
--
-- The clock rides the SAVE SLOT, not the options file: what time it is in
-- Kanto is a fact about that journey, like where the player is standing.
-- mod.save is the loader's per-mod bucket in save.modData, which persists
-- with the slot on its own -- writing the value is all there is to do.

DayNight.SAVE_KEY = "clock"

function DayNight.store()
  local saveApi = V.mod and V.mod.save
  if not (saveApi and saveApi.set) then return end
  pcall(saveApi.set, saveApi, DayNight.SAVE_KEY, DayNight.clock)
end

function DayNight.restore()
  local saveApi = V.mod and V.mod.save
  local stored = nil
  if saveApi and saveApi.get then
    local ok, got = pcall(saveApi.get, saveApi, DayNight.SAVE_KEY)
    if ok then stored = got end
  end
  -- no time set: it is day (the requirement, verbatim)
  DayNight.clock = type(stored) == "number"
                   and stored % DayNight.CYCLE or DayNight.T.day
end

return DayNight
