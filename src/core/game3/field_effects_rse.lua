local function lazyReq(name)
  local m = package.loaded[name]
  if type(m) == "table" then return m end
  return require(name)
end

local FxRse = {}

local CELL = 16

FxRse._list = {}
FxRse._fc = nil
FxRse._images = {}
FxRse._state = {}

local function FE()
  return package.loaded["src.core.game3.field_effects"] or lazyReq("src.core.game3.field_effects")
end

local function Player()
  return package.loaded["src.core.game3.player"]
end

local function Objects()
  return package.loaded["src.core.game3.objects"]
end

local function Collision()
  return package.loaded["src.core.game3.collision"]
end

local function root()
  local ok, Extract = pcall(lazyReq, "src.import.gba.extract_island1")
  return (ok and Extract and Extract.CACHE_ROOT) or "data/generated/gba"
end

local function cache()
  local fe = FE()
  if fe._cache then return fe._cache end
  local ok, Dataset = pcall(lazyReq, "src.core.game3.dataset")
  return ok and Dataset and Dataset.cache and Dataset.cache() or nil
end

function FxRse.active()
  local m = FE().manifest()
  return m ~= nil and m.family == "rse"
end

function FxRse.fc()
  local m = FxRse._fc
  if m ~= nil then return m or nil end
  local c = cache()
  local src = c and c.read and c:read(root() .. "/field_fc/manifest.lua")
  local chunk = src and load(src, "@field_fc/manifest.lua", "t", {})
  local ok, t = false, nil
  if chunk then ok, t = pcall(chunk) end
  FxRse._fc = ok and type(t) == "table" and t or false
  return FxRse._fc or nil
end

function FxRse.invalidate()
  local orb = package.loaded["src.core.game3.rse.orb_effect_rs"]
  if orb then orb.reset() end
  FxRse._list = {}
  FxRse._fc = nil
  FxRse._images = {}
  FxRse._state = {}
  FxRse._berry = nil
end


local sets = {}
local function set(key, names)
  local s = sets[key]
  if s then return s end
  local MB = lazyReq("src.core.game3.mb")
  s = {}
  for _, n in ipairs(names) do
    local id = MB.id(n)
    if id then s[id] = true end
  end
  sets[key] = s
  return s
end

local NAMES = {
  refl = { "POND_WATER", "PUDDLE", "UNUSED_SOOTOPOLIS_DEEP_WATER_2", "ICE", "SOOTOPOLIS_DEEP_WATER", "REFLECTION_UNDER_BRIDGE" },
  ice = { "ICE" },
  short = { "SHORT_GRASS" },
  deep = { "DEEP_SAND" },
  sand = { "SAND", "DEEP_SAND" },
  foot = { "FOOTPRINTS" },
  weed = { "SEAWEED", "SEAWEED_NO_SURFACING" },
  tall = { "TALL_GRASS" },
  long = { "LONG_GRASS" },
  puddle = { "PUDDLE" },
  flow = { "SHALLOW_WATER", "STAIRS_OUTSIDE_ABANDONED_SHIP", "SHOAL_CAVE_ENTRANCE" },
  ripple = { "POND_WATER", "PUDDLE", "SOOTOPOLIS_DEEP_WATER" },
  fr_ripple = { "POND_WATER", "PUDDLE" },
}

local B = {}
-- pokeemerald/src/metatile_behavior.c:199
function B.reflective(b)
  return set("refl", NAMES.refl)[b] == true
end
-- pokeemerald/src/metatile_behavior.c:212
function B.ice(b) return set("ice", NAMES.ice)[b] == true end
-- pokeemerald/src/metatile_behavior.c:979
function B.shortGrass(b) return set("short", NAMES.short)[b] == true end
-- pokeemerald/src/metatile_behavior.c:191
function B.deepSand(b) return set("deep", NAMES.deep)[b] == true end
-- pokeemerald/src/metatile_behavior.c:183
function B.sandOrDeepSand(b) return set("sand", NAMES.sand)[b] == true end
-- pokeemerald/src/metatile_behavior.c:761
function B.footprints(b) return set("foot", NAMES.foot)[b] == true end
-- pokeemerald/src/metatile_behavior.c:1250
function B.seaweed(b) return set("weed", NAMES.weed)[b] == true end
-- pokeemerald/src/metatile_behavior.c:729
function B.tallGrass(b) return set("tall", NAMES.tall)[b] == true end
-- pokeemerald/src/metatile_behavior.c:737
function B.longGrass(b) return set("long", NAMES.long)[b] == true end
-- pokeemerald/src/metatile_behavior.c:721
function B.puddle(b) return set("puddle", NAMES.puddle)[b] == true end
-- pokeemerald/src/metatile_behavior.c:879
function B.shallowFlowing(b)
  return set("flow", NAMES.flow)[b] == true
end
-- pokeemerald/src/metatile_behavior.c:711
function B.ripples(b) return set("ripple", NAMES.ripple)[b] == true end
-- pokeemerald/src/metatile_behavior.c:280
function B.surfable(b)
  local C = Collision()
  return b ~= nil and C and C.isSurfable and C.isSurfable(b) == true or false
end
-- pokeemerald/src/metatile_behavior.c:788
local BRIDGE = {
  BRIDGE_OVER_OCEAN = 0, BRIDGE_OVER_POND_LOW = 1, BRIDGE_OVER_POND_MED = 2, BRIDGE_OVER_POND_HIGH = 3,
  BRIDGE_OVER_POND_MED_EDGE_1 = 2, BRIDGE_OVER_POND_MED_EDGE_2 = 2,
  BRIDGE_OVER_POND_HIGH_EDGE_1 = 3, BRIDGE_OVER_POND_HIGH_EDGE_2 = 3,
}
function B.bridgeType(b)
  local MB = lazyReq("src.core.game3.mb")
  local n = b and MB.nameOf(b)
  return n and BRIDGE[n] or 0
end
FxRse.B = B

local function behaviorAt(x, y)
  local C = Collision()
  if not (C and C.behavior) or x == nil or y == nil then return nil end
  return C.behavior(x, y)
end

local function worldBehaviorAt(x, y)
  local C = Collision()
  if not (C and C.worldBehavior) or x == nil or y == nil then return nil end
  return C.worldBehavior(x, y)
end


function FxRse.animCmds(name, idx)
  local o = FE().manifestObject(name)
  return o and o.anims and o.anims[idx or 1] or nil
end

local function animEnter(a)
  for _ = 1, 64 do
    local c = a.cmds[a.i]
    if not c or c[1] == "end" then
      a.ended = true
      return
    end
    local op = c[1]
    if op == "frame" then
      a.frame = tonumber(c[2]) or 0
      a.left = math.max(1, tonumber(c[3]) or 1)
      a.hflip, a.vflip = c[4] == true, c[5] == true
      return
    elseif op == "jump" then
      a.i = (tonumber(c[2]) or 0) + 1
    elseif op == "loop" then
      local n = tonumber(c[2]) or 0
      if n == 0 then
        a.loopStart = a.i + 1
        a.i = a.i + 1
      else
        if a.loopLeft == nil then a.loopLeft = n end
        if a.loopLeft > 0 then
          a.loopLeft = a.loopLeft - 1
          a.i = a.loopStart or 1
        else
          a.loopLeft = nil
          a.i = a.i + 1
        end
      end
    else
      a.i = a.i + 1
    end
  end
  a.ended = true
end

-- pokeemerald/src/sprite.c:909
function FxRse.anim(cmds, seek)
  local a = { cmds = cmds or {}, i = 1, frame = 0, left = 1, ended = false, index = 0 }
  if seek and seek > 0 then a.i = seek + 1 end
  animEnter(a)
  a.index = a.i - 1
  return a
end

function FxRse.animTick(a)
  if not a or a.ended or a.paused then return end
  a.left = a.left - 1
  if a.left <= 0 then
    a.i = a.i + 1
    animEnter(a)
    a.index = a.i - 1
  end
end


local function sprH(obj)
  local Ow = package.loaded["src.core.game3.ow_sprites"]
  local gid = obj and (obj.graphicsId or (obj.def and obj.def.graphicsId))
  if obj == Player() and Ow and Ow.playerGraphicsId then
    local rt = package.loaded["src.core.game3.runtime"]
    local ok, g = pcall(Ow.playerGraphicsId, rt and rt._game)
    if ok then gid = g end
  end
  local spr = Ow and gid and Ow.get and Ow.get(gid)
  return spr and spr.height or 32, spr and spr.width or 16, gid
end
FxRse.spriteSize = sprH

local function objCenter(obj)
  local h = sprH(obj)
  local x = (obj.px or (obj.cellX or 0) * CELL) + 8
  local y = (obj.py or (obj.cellY or 0) * CELL) + CELL - math.floor(h / 2)
  return x, y, h
end
FxRse.objCenter = objCenter

-- pokeemerald/src/event_object_movement.c:4821
local function cellPos(cx, cy, ox, oy)
  return cx * CELL + (ox or 8), cy * CELL + (oy or 8)
end

function FxRse.spawn(name, opts)
  opts = opts or {}
  local sheet = FE().loadSheet(name)
  if not sheet then return nil end
  local e = {
    name = name,
    sheet = sheet,
    a = FxRse.anim(FxRse.animCmds(name, opts.anim or 1), opts.seek),
    x = opts.x or 0,
    y = opts.y or 0,
    follow = opts.follow,
    y2 = opts.y2 or 0,
    layer = opts.layer or "actor",
    effectName = opts.effectName,
    keep = opts.keep,
    restart = opts.restart,
    stopOnEnd = opts.stopOnEnd ~= false,
    hideOnEnd = opts.hideOnEnd,
    endWait = opts.endWait,
    vy = opts.vy,
    onDone = opts.onDone,
    onStep = opts.onStep,
    delay = opts.delay,
    elevation = opts.elevation,
    sortBias = opts.sortBias or 0.5,
    timer = 0,
  }
  if e.delay and e.delay > 0 then e.a.paused = true end
  FxRse._list[#FxRse._list + 1] = e
  return e
end

function FxRse.spawnAt(name, cx, cy, ox, oy, opts)
  opts = opts or {}
  local x, y = cellPos(cx, cy, ox, oy)
  opts.x, opts.y = x, y
  return FxRse.spawn(name, opts)
end

function FxRse.isActive(effectName)
  for _, e in ipairs(FxRse._list) do
    if e.effectName == effectName then return true end
  end
  return false
end

function FxRse.count(name)
  local n = 0
  for _, e in ipairs(FxRse._list) do
    if e.name == name then n = n + 1 end
  end
  return n
end

function FxRse.clear(pred)
  local keep = {}
  for _, e in ipairs(FxRse._list) do
    if pred and not pred(e) then keep[#keep + 1] = e end
  end
  FxRse._list = keep
end

local function stepEntry(e)
  e.timer = e.timer + 1
  if e.delay and e.delay > 0 then
    e.delay = e.delay - 1
    if e.delay > 0 then return false end
    e.a.paused = false
    if e.onShow then e.onShow(e) end
  end
  if e.onStep and e.onStep(e) == true then return true end
  if e.keep and not e.keep(e) then return true end
  if e.follow then
    local cx, cy, h = objCenter(e.follow)
    e.x, e.y = cx, cy + (type(e.y2) == "function" and e.y2(h) or e.y2)
    if e.restart then
      local mx, my = e.follow.px, e.follow.py
      if (mx ~= e.lastX or my ~= e.lastY) then
        e.lastX, e.lastY = mx, my
        if e.a.ended then e.a = FxRse.anim(e.a.cmds) end
      end
    end
  end
  if e.vy then
    e.sub = (e.sub or 0) + e.vy
    while e.sub >= 1 do
      e.sub = e.sub - 1
      e.y = e.y - 1
    end
  end
  FxRse.animTick(e.a)
  if e.a.ended then
    if e.endWait then
      e.hidden = true
      e.endWait = e.endWait - 1
      return e.endWait < 0
    end
    if e.stopOnEnd then return true end
  end
  return false
end

-- pokeemerald/src/data/field_effects/field_effect_objects.h:849
local DISTORT_SCALE = {}
do
  local d = 0
  for _, s in ipairs({ { 1, 4 }, { 0, 8 }, { -1, 4 }, { 0, 8 }, { -1, 4 }, { 0, 8 }, { 1, 4 }, { 0, 8 } }) do
    for _ = 1, s[2] do
      d = d + s[1]
      DISTORT_SCALE[#DISTORT_SCALE + 1] = math.floor(65536 / (256 - d))
    end
  end
end

function FxRse.reflectionScale()
  return DISTORT_SCALE[(FxRse._distortTick or 0) % #DISTORT_SCALE + 1]
end

function FxRse.step()
  FxRse._distortTick = ((FxRse._distortTick or 0) + 1) % #DISTORT_SCALE
  FxRse._hookTick = ((FxRse._hookTick or 0) + 1) % 256
  if FxRse._hookTick == 0 then lazyReq("src.core.game3.rse.berry_trees").installTimeHook() end
  local keep = {}
  for _, e in ipairs(FxRse._list) do
    if stepEntry(e) then
      if e.onDone then e.onDone(e) end
    else
      keep[#keep + 1] = e
    end
  end
  FxRse._list = keep
  FxRse.stepObjects()
  for _, name in ipairs(FxRse.SYSTEMS) do
    local mod = package.loaded[name]
    if mod and mod.step then mod.step() end
  end
end

local function drawEntry(e, camX, camY)
  if e.hidden or (e.delay and e.delay > 0) then return end
  local q = e.sheet.quads[e.a.frame or 0]
  if not q then return end
  local fw, fh = e.sheet.fw, e.sheet.fh
  local x = math.floor(e.x - fw / 2) - camX
  local y = math.floor(e.y - fh / 2) - camY
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(e.sheet.image, q, x + (e.a.hflip and fw or 0), y + (e.a.vflip and fh or 0), 0,
    e.a.hflip and -1 or 1, e.a.vflip and -1 or 1)
end


local function st()
  return FxRse._state
end

local function flagCovering(key, cur, prev, pred)
  local s = st()
  if pred(cur) and pred(prev) then
    if not s[key] then
      s[key] = true
      return true
    end
  else
    s[key] = false
  end
  return false
end

local function startShortGrass()
  local P = Player()
  -- pokeemerald/src/field_effect_helpers.c:492
  FxRse.spawn("short_grass", {
    follow = P, y2 = function(h) return math.floor(h / 2) - 8 end, restart = true, stopOnEnd = false,
    keep = function() return st().inShortGrass == true end, effectName = "FLDEFF_SHORT_GRASS",
  })
end

local function startSandPile()
  local P = Player()
  -- pokeemerald/src/field_effect_helpers.c:1204
  FxRse.spawn("sand_pile", {
    follow = P, y2 = function(h) return math.floor(h / 2) - 2 end, restart = true, stopOnEnd = false, seek = 2,
    keep = function() return st().inSandPile == true end, effectName = "FLDEFF_SAND_PILE",
  })
end

-- pokeemerald/src/event_object_movement.c:7905
local TIRE_TRANSITIONS = {
  { 1, 2, 7, 8 },
  { 1, 2, 6, 5 },
  { 5, 8, 3, 4 },
  { 6, 7, 3, 4 },
}
local DIR_NUM = { down = 1, up = 2, left = 3, right = 4 }
FxRse.TIRE_TRANSITIONS = TIRE_TRANSITIONS

function FxRse.tireTrackAnim(prevDir, facing)
  local row = TIRE_TRANSITIONS[DIR_NUM[prevDir] or 1]
  return row[DIR_NUM[facing] or 1]
end

-- pokeemerald/src/event_object_movement.c:7905
local function startTireTracks(px, py, prevDir, facing)
  local v = FxRse.tireTrackAnim(prevDir, facing)
  FxRse.spawnAt("bike_tire_tracks", px, py, 8, 8, {
    anim = v + 1, layer = "behind", stopOnEnd = false, effectName = "FLDEFF_BIKE_TIRE_TRACKS",
    onStep = function(e)
      -- pokeemerald/src/field_effect_helpers.c:624
      if e.timer > 41 then e.hidden = not e.hidden end
      return e.timer > 57
    end,
  })
end

function FxRse.onSpawn(g, cur, prev)
  if flagCovering("inShortGrass", cur, prev, B.shortGrass) then startShortGrass() end
  if flagCovering("inSandPile", cur, prev, B.deepSand) then startSandPile() end
end

function FxRse.onBeginStep(g, cur, prev)
  local P = Player()
  local s = st()
  if P and P.biking and prev ~= nil and g.px ~= nil
      and (B.sandOrDeepSand(prev) or B.footprints(prev)) and (g.px ~= g.cx or g.py ~= g.cy) then
    startTireTracks(g.px, g.py, s.lastMoveDir or P.facing, P.facing)
  end
  if P then s.lastMoveDir = P.facing end
  if flagCovering("inSandPile", cur, prev, B.deepSand) then startSandPile() end
  if flagCovering("inShortGrass", cur, prev, B.shortGrass) then startShortGrass() end
end

-- pokeemerald/src/event_object_movement.c:7582
function FxRse.jumpLanding(cx, cy, cur)
  if B.tallGrass(cur) then
    FxRse.spawnAt("jump_tall_grass", cx, cy, 8, 8, { effectName = "FLDEFF_JUMP_TALL_GRASS", layer = "actor" })
    local fe = FE()
    if fe.tallGrassAt then fe.tallGrassAt(cx, cy, true) end
  elseif B.longGrass(cur) then
    FxRse.spawnAt("jump_long_grass", cx, cy, 8, 8, { effectName = "FLDEFF_JUMP_LONG_GRASS" })
  elseif B.puddle(cur) or B.shallowFlowing(cur) then
    FxRse.spawnAt("jump_small_splash", cx, cy, 8, 12, { effectName = "FLDEFF_JUMP_SMALL_SPLASH" })
  elseif B.surfable(cur) then
    FxRse.spawnAt("jump_big_splash", cx, cy, 8, 8, { effectName = "FLDEFF_JUMP_BIG_SPLASH" })
  else
    FE().startDust(cx, cy)
  end
  return true
end

function FxRse.onFinishStep(g, cur, jumped, landingJump)
  if flagCovering("inSandPile", cur, cur, B.deepSand) then startSandPile() end
  if flagCovering("inShortGrass", cur, cur, B.shortGrass) then startShortGrass() end
  -- pokeemerald/src/event_object_movement.c:7534
  if cur ~= nil and B.ripples(cur) and not set("fr_ripple", NAMES.fr_ripple)[cur] then
    local fe = FE()
    if fe.startRipple then fe.startRipple(g.cx, g.cy) end
  end
  -- pokeemerald/src/event_object_movement.c:7576
  if B.seaweed(cur) then FxRse.startBubbles(g.cx, g.cy) end
  local s = st()
  if landingJump and not s.disableJumpLanding then
    FxRse.jumpLanding(g.cx, g.cy, cur)
    return true
  end
  return false
end

function FxRse.clearGround()
  local s = st()
  s.inShortGrass, s.inSandPile = false, false
  FxRse.clear(function(e) return e.follow ~= nil or e.name == "bike_tire_tracks" end)
end

function FxRse.setJumpLandingEffect(on)
  st().disableJumpLanding = not on
end


-- pokeemerald/src/field_effect_helpers.c:1258
function FxRse.startBubbles(cx, cy)
  return FxRse.spawnAt("bubbles", cx, cy, 8, 0, { layer = "front", vy = 0.5, effectName = "FLDEFF_BUBBLES" })
end

-- pokeemerald/src/field_effect_helpers.c:892
function FxRse.startWaterSurfacing(cx, cy)
  return FxRse.spawnAt("water_surfacing", cx, cy, 8, 8, { effectName = "FLDEFF_WATER_SURFACING", stopOnEnd = false })
end

function FxRse.stopEffect(effectName)
  FxRse.clear(function(e) return e.effectName == effectName end)
end

-- pokeemerald/src/field_effect_helpers.c:1417
function FxRse.startSparkle(cx, cy, onDone)
  return FxRse.spawnAt("small_sparkle", cx, cy, 8, 8, { layer = "front", endWait = 34, effectName = "FLDEFF_SPARKLE",
    onDone = onDone })
end

-- pokeemerald/src/field_effect_helpers.c:1288
function FxRse.startBerryTreeSparkle(cx, cy)
  return FxRse.spawnAt("sparkle", cx, cy, 8, 4, { layer = "front", effectName = "FLDEFF_BERRY_TREE_GROWTH_SPARKLE" })
end

-- pokeemerald/src/field_effect_helpers.c:926
function FxRse.startAsh(cx, cy, metatileId, delay)
  return FxRse.spawnAt("ash", cx, cy, 8, 8, {
    layer = "front", delay = math.max(1, tonumber(delay) or 1), effectName = "FLDEFF_ASH",
    onStep = function(e)
      if not e.shown and not (e.delay and e.delay > 0) then
        e.shown = true
        local Field = package.loaded["src.core.game3.field"]
        if Field and Field.setMetatile and metatileId then Field.setMetatile(cx, cy, metatileId, false) end
      end
    end,
  })
end

-- pokeemerald/src/trainer_see.c:584
function FxRse.startAshPuff(cx, cy, onDone)
  return FxRse.spawnAt("ash_puff", cx, cy, 8, 8, { layer = "front", effectName = "FLDEFF_ASH_PUFF", onDone = onDone })
end

-- pokeemerald/src/field_effect.c:2127
function FxRse.startAshLaunch(cx, cy, onDone)
  return FxRse.spawnAt("ash_launch", cx, cy, 8, 8, { layer = "front", effectName = "FLDEFF_ASH_LAUNCH", onDone = onDone })
end

-- pokeemerald/src/fldeff_misc.c:1033
function FxRse.startSandPillar(cx, cy, onDone)
  return FxRse.spawnAt("sand_pillar", cx, cy, 8, 0, { layer = "front", effectName = "FLDEFF_SAND_PILLAR", onDone = onDone })
end


local function fcGfx(gid)
  local m = FxRse.fc()
  return m and m.gfx and m.gfx[tonumber(gid) or -1] or nil
end

-- pokeemerald/src/field_effect_helpers.c:75
function FxRse.reflectionPaletteTag(gid, bridge)
  local m = FxRse.fc()
  local info = fcGfx(gid)
  if not (m and info) then return nil end
  local none = m.palTagNone or 0x11FF
  local slot = info.slot or 0
  local reflSlot = m.reflectionMap and m.reflectionMap[slot] or slot
  local default = m.slotTags and m.slotTags[reflSlot]
  if bridge ~= 0 and not info.noReflectionLoad and info.reflectionTag ~= none then
    return info.reflectionTag
  end
  if info.reflectionTag == none then return default end
  if slot == 0 then return (m.playerReflections or {})[info.paletteTag] or default end
  if slot == 10 then return (m.specialReflections or {})[info.paletteTag] or default end
  return default
end

-- pokeemerald/src/event_object_movement.c:7625
local function reflectionAt(x, y)
  local b = worldBehaviorAt(x, y)
  if b == nil then return 0 end
  if B.ice(b) then return 1 end
  if B.reflective(b) then return 2 end
  return 0
end

function FxRse.reflectionType(cx, cy, pcx, pcy, w, h)
  local width = math.floor(((w or 16) + 8) / 16)
  local height = math.floor(((h or 32) + 8) / 16)
  for i = 0, height - 1 do
    local r = reflectionAt(cx, cy + 1 + i)
    if r ~= 0 then return r end
    r = reflectionAt(pcx, pcy + 1 + i)
    if r ~= 0 then return r end
    for j = 1, width - 1 do
      r = reflectionAt(cx + j, cy + 1 + i)
      if r ~= 0 then return r end
      r = reflectionAt(cx - j, cy + 1 + i)
      if r ~= 0 then return r end
      r = reflectionAt(pcx + j, pcy + 1 + i)
      if r ~= 0 then return r end
      r = reflectionAt(pcx - j, pcy + 1 + i)
      if r ~= 0 then return r end
    end
  end
  return 0
end

local function to8(v)
  v = math.floor((tonumber(v) or 0) * 255 + 0.5)
  return v < 0 and 0 or v > 255 and 255 or v
end

local function recolored(gid, spr, tag)
  local key = tostring(gid) .. ":" .. tostring(tag)
  local hit = FxRse._images[key]
  if hit ~= nil then return hit or nil end
  local m = FxRse.fc()
  local info = fcGfx(gid)
  local from = m and info and m.palettes and m.palettes[info.paletteTag]
  local to = m and m.palettes and m.palettes[tag]
  if not (from and to and spr and spr.imageData and love and love.graphics) then
    FxRse._images[key] = false
    return nil
  end
  local lut = {}
  for i = 2, 16 do
    local a, b = from[i], to[i]
    if a and b then lut[a[1] * 65536 + a[2] * 256 + a[3]] = b end
  end
  local okC, data = pcall(function() return spr.imageData:clone() end)
  if not okC then
    FxRse._images[key] = false
    return nil
  end
  data:mapPixel(function(_, _, r, g, b, a)
    if a <= 0 then return r, g, b, a end
    local c = lut[to8(r) * 65536 + to8(g) * 256 + to8(b)]
    if c then return c[1] / 255, c[2] / 255, c[3] / 255, a end
    return r, g, b, a
  end)
  local img = love.graphics.newImage(data)
  if img.setFilter then img:setFilter("nearest", "nearest") end
  local out = { image = img, width = spr.width, height = spr.height }
  FxRse._images[key] = out
  return out
end

local reflQuad
local coverCells, coverN = {}, 0
local coverBuckets, coverPairs = {}, {}
local REFL_CULL = 64
local ghostPose = {}

local function drawReflection(obj, gid, frame, hflip, x2, y2, camX, camY, ox, oy)
  local Ow = package.loaded["src.core.game3.ow_sprites"]
  local spr = Ow and (Ow.peekDraw or Ow.getDraw)(gid)
  if not (spr and spr.quads and spr.quads[frame]) then return false end
  ox, oy = ox or 0, oy or 0
  local cx = (obj.moving and obj.targetX or obj.cellX) + ox
  local cy = (obj.moving and obj.targetY or obj.cellY) + oy
  local pcx, pcy = obj.cellX + ox, obj.cellY + oy
  if obj == Player() then pcx, pcy = (obj.prevCellX or cx - ox) + ox, (obj.prevCellY or cy - oy) + oy end
  local rtype = FxRse.reflectionType(cx, cy, pcx, pcy, spr.width, spr.height)
  if rtype == 0 then return false end
  local bridge = B.bridgeType(worldBehaviorAt(pcx, pcy))
  if bridge == 0 then bridge = B.bridgeType(worldBehaviorAt(cx, cy)) end
  local info = fcGfx(gid)
  local tag = FxRse.reflectionPaletteTag(gid, bridge)
  local src = (tag and recolored(gid, spr, tag)) or spr
  FxRse.lastReflections = (FxRse.lastReflections or 0) + 1
  FxRse.lastReflectionTag = tag
  -- pokeemerald/src/field_effect_helpers.c:75
  local offs = { [1] = 12, [2] = 28, [3] = 44 }
  local extra = (not (info and info.noReflectionLoad)) and offs[bridge] or 0
  local w, h = spr.width, spr.height
  local left = (obj.px or (cx - ox) * CELL) + ox * CELL + (16 - w) / 2 + (x2 or 0)
  local top = (obj.py or (cy - oy) * CELL) + oy * CELL + 16 - h + (h - 2) + extra - (y2 or 0)
  local iw, ih = src.image:getDimensions()
  reflQuad = reflQuad or love.graphics.newQuad(0, 0, 1, 1, iw, ih)
  local fy = frame * h
  local c0x, c1x = math.floor(left / CELL), math.floor((left + w - 1) / CELL)
  local c0y, c1y = math.floor(top / CELL), math.floor((top + h - 1) / CELL)
  love.graphics.setColor(1, 1, 1, 1)
  for ty = c0y, c1y do
    for tx = c0x, c1x do
      local b = worldBehaviorAt(tx, ty)
      if b and B.reflective(b) then
        local ix0, ix1 = math.max(left, tx * CELL), math.min(left + w, tx * CELL + CELL)
        local iy0, iy1 = math.max(top, ty * CELL), math.min(top + h, ty * CELL + CELL)
        local dw, dh = ix1 - ix0, iy1 - iy0
        if dw > 0 and dh > 0 and rtype == 2 then
          -- pokeemerald/src/field_effect_helpers.c:153
          local pa = hflip and -FxRse.reflectionScale() or FxRse.reflectionScale()
          local ry0 = math.max(iy0, top + 1)
          local rdh = iy1 - ry0
          if rdh > 0 then
            local tyMin = h - (iy1 - 1 - top)
            for c = ix0, ix1 - 1 do
              local tcol = math.floor(pa * (c - left - w / 2) / 256) + w / 2
              if tcol >= 0 and tcol < w then
                reflQuad:setViewport(tcol, fy + tyMin, 1, rdh, iw, ih)
                love.graphics.draw(src.image, reflQuad, c - camX, iy1 - camY, 0, 1, -1)
              end
            end
          end
          coverCells[coverN + 1], coverCells[coverN + 2] = tx, ty
          coverN = coverN + 2
        elseif dw > 0 and dh > 0 then
          local dx0, dy0 = ix0 - left, iy0 - top
          local sx = hflip and (w - (dx0 + dw)) or dx0
          local sy = h - (dy0 + dh)
          reflQuad:setViewport(sx, fy + sy, dw, dh, iw, ih)
          love.graphics.draw(src.image, reflQuad,
            ix0 + (hflip and dw or 0) - camX, iy0 + dh - camY, 0, hflip and -1 or 1, -1)
          coverCells[coverN + 1], coverCells[coverN + 2] = tx, ty
          coverN = coverN + 2
        end
      end
    end
  end
  return true
end
FxRse.drawReflection = drawReflection

local coverShader
local function getCoverShader()
  if coverShader == nil then
    local ok, sh = pcall(love.graphics.newShader, [[
      extern Image mask;
      vec4 effect(vec4 color, Image tex, vec2 uv, vec2 sc) {
        vec4 p = Texel(tex, uv);
        return vec4(p.rgb, p.a * Texel(mask, uv).a) * color;
      }
    ]])
    coverShader = ok and sh or false
  end
  return coverShader or nil
end

-- pokeemerald/src/field_effect_helpers.c:53
local function coverReflections(camX, camY)
  local n = coverN
  coverN = 0
  if n == 0 then return end
  local C = Collision()
  local mapDef = C and C._mapDef
  local layout = mapDef and mapDef.midLayout
  local NT = package.loaded["src.core.game3.tileset_native"]
  local Map = package.loaded["src.core.game3.map"]
  if not (layout and NT and Map) then return end
  local shader = getCoverShader()
  if not shader then return end
  love.graphics.setShader(shader)
  love.graphics.setColor(1, 1, 1, 1)
  local loaded = NT._pairs or {}
  local np = 0
  for i = 1, n, 2 do
    local tx, ty = coverCells[i], coverCells[i + 1]
    local mid, pair = Map.worldMidAt(tx, ty, mapDef)
    local ts = pair and loaded[pair]
    if ts and ts.midImage then
      local bucket = coverBuckets[pair]
      if not bucket then
        bucket = { n = 0 }
        coverBuckets[pair] = bucket
      end
      if bucket.n == 0 then
        np = np + 1
        coverPairs[np] = pair
      end
      local b = bucket.n
      bucket[b + 1], bucket[b + 2], bucket[b + 3] = tx, ty, mid
      bucket.n = b + 3
    end
  end
  for p = 1, np do
    local pair = coverPairs[p]
    local bucket = coverBuckets[pair]
    local ts = loaded[pair]
    shader:send("mask", ts.midImage)
    for i = 1, bucket.n, 3 do
      local tx, ty = bucket[i], bucket[i + 1]
      local q = NT.quad(ts, NT.slotFor(ts, bucket[i + 2]))
      if q then love.graphics.draw(ts.image, q, tx * CELL - camX, ty * CELL - camY) end
    end
    bucket.n = 0
    coverPairs[p] = nil
  end
  love.graphics.setShader()
end

function FxRse.coverWorldRect(left, top, w, h, camX, camY)
  coverN = 0
  for ty = math.floor(top / CELL), math.floor((top + h - 1) / CELL) do
    for tx = math.floor(left / CELL), math.floor((left + w - 1) / CELL) do
      coverCells[coverN + 1], coverCells[coverN + 2] = tx, ty
      coverN = coverN + 2
    end
  end
  coverReflections(camX, camY)
end

local function drawReflections(camX, camY)
  FxRse.lastReflections = 0
  coverN = 0
  local Ow = package.loaded["src.core.game3.ow_sprites"]
  if not (Ow and Ow.getDraw and Ow.pose) then return end
  local O = Objects()
  if O and O.forDraw then
    for _, eo in ipairs(O.forDraw()) do
      if not eo.hideReflection and eo.graphicsId and not eo.virtualId then
        local spr = Ow.getDraw(eo.graphicsId)
        if spr then
          local frame, flip = Ow.pose(spr, eo.facing, O.walkPhase(eo), eo.stepFlip, { frame = eo.customFrame })
          drawReflection(eo, eo.graphicsId, frame, flip, eo.raiseX, eo.raiseY, camX, camY)
        end
      end
    end
  end
  local Map = package.loaded["src.core.game3.map"]
  local Ghosts = package.loaded["src.core.game3.ghosts"]
  local world = Map and Map.world
  if O and Ghosts and Ghosts.forDraw and type(world) == "table" then
    local C = Collision()
    local host = C and C._mapDef
    local FV = package.loaded["src.core.game3.field_view"]
    local Display = lazyReq("src.core.game3.display")
    local vw = FV and FV._viewW or Display.W
    local vh = FV and FV._viewH or Display.H
    local x0, y0 = camX - REFL_CULL, camY - REFL_CULL
    local x1, y1 = camX + vw + REFL_CULL, camY + vh + REFL_CULL
    for i = 1, #world do
      local entry = world[i]
      local ox, oy = entry.ox or 0, entry.oy or 0
      local L = entry.def and entry.def.midLayout
      local ex, ey = ox * CELL, oy * CELL
      if entry.def ~= host and L
          and ex + (L.width or 0) * CELL > x0 and ex < x1
          and ey + (L.height or 0) * CELL > y0 and ey < y1 then
        local live = Ghosts.forDraw(entry.id)
        if live then
          for j = 1, #live do
            local eo = live[j]
            if not eo.hideReflection and eo.graphicsId and not eo.virtualId then
              local spr = (Ow.peekDraw or Ow.getDraw)(eo.graphicsId)
              if spr then
                ghostPose.frame = eo.customFrame
                local frame, flip = Ow.pose(spr, eo.facing, O.walkPhase(eo), eo.stepFlip, ghostPose)
                drawReflection(eo, eo.graphicsId, frame, flip, eo.raiseX, eo.raiseY, camX, camY, ox, oy)
              end
            end
          end
        end
      end
    end
  end
  local P = Player()
  if P and P.isVisible and P.isVisible() and not P.hideReflection then
    local rt = package.loaded["src.core.game3.runtime"]
    local ok, gid = pcall(Ow.playerGraphicsId, rt and rt._game)
    local spr = ok and gid and Ow.getDraw(gid)
    if spr then
      local frame, flip = Ow.pose(spr, P.facing, P.walkPhase and P.walkPhase() or 0,
        P.drawFlip and P.drawFlip() or false, { running = P.runPose and P.runPose() or nil })
      local y2 = P.jumpSpriteY and P.jumpSpriteY() or 0
      drawReflection(P, gid, frame, flip, 0, y2, camX, camY)
    end
  end
  coverReflections(camX, camY)
end


-- pokeemerald/src/field_effect_helpers.c:213
local SHADOW_SHEETS = { [0] = "shadow_small", "shadow_medium", "shadow_large", "shadow_extra_large" }
local SHADOW_OFFSETS = { [0] = 4, 4, 4, 16 }

function FxRse.shadowFor(gid)
  local info = fcGfx(gid)
  local size = info and info.shadow or 1
  return SHADOW_SHEETS[size] or "shadow_medium", SHADOW_OFFSETS[size] or 4
end

local berryMemo

function FxRse.berryManifest()
  if berryMemo ~= nil then return berryMemo or nil end
  local c = cache()
  local src = c and c.read and c:read(root() .. "/berry_trees/manifest.lua")
  local chunk = src and load(src, "@berry_trees/manifest.lua", "t", {})
  local ok, t = false, nil
  if chunk then ok, t = pcall(chunk) end
  berryMemo = ok and type(t) == "table" and t or false
  return berryMemo or nil
end

local berryImages = {}
local function berrySheet(tree)
  local img = berryImages[tree.file]
  if img ~= nil then return img or nil end
  local c = cache()
  local rgba = c and c.read and c:read(root() .. "/berry_trees/" .. tree.file)
  if not (rgba and love and love.image and #rgba == tree.width * tree.height * 4) then
    berryImages[tree.file] = false
    return nil
  end
  local data = love.image.newImageData(tree.width, tree.height, "rgba8", rgba)
  img = love.graphics.newImage(data)
  if img.setFilter then img:setFilter("nearest", "nearest") end
  berryImages[tree.file] = img
  return img
end

function FxRse.stepObjects()
  local O = Objects()
  if not (O and O._order) then return end
  for _, lid in ipairs(O._order) do
    local eo = O._byId[lid]
    local d = eo and eo.disguise
    if d then
      if not d.a then d.a = FxRse.anim(FxRse.animCmds(d.sheet, 1)) end
      FxRse.animTick(d.a)
      if d.revealing and d.a.ended then
        d.done = true
      end
    end
    local bt = eo and eo.berryTree
    if bt and bt.anim then FxRse.animTick(bt.anim) end
  end
end

local function pushActor(actors, sortY, elevation, x, y, fn)
  actors[#actors + 1] = {
    kind = "field_effect_rse", elevation = elevation or 3, sortY = sortY, x = x, y = y,
    i = 95000 + #actors, draw = fn,
  }
end

FxRse.SYSTEMS = {
  "src.core.game3.rotating_gate",
  "src.core.game3.rotating_tile_puzzle",
  "src.core.game3.mirage_tower",
  "src.core.game3.faraway_island",
  "src.core.game3.special_scene_rse",
  "src.core.game3.rse.orb_effect_rs",
}

function FxRse.collectActors(actors)
  for _, name in ipairs(FxRse.SYSTEMS) do
    local mod = package.loaded[name]
    if mod and mod.collectActors then mod.collectActors(actors) end
  end
  for _, e in ipairs(FxRse._list) do
    if e.layer == "actor" and not e.hidden then
      local sortY = e.follow and ((e.follow.py or 0) + e.sortBias) or (e.y - 8 + e.sortBias)
      pushActor(actors, sortY, e.elevation or (e.follow and e.follow.elevation) or 3, e.x, e.y, function(_, camX, camY)
        drawEntry(e, camX, camY)
      end)
    end
  end
  local O = Objects()
  if not (O and O._order) then return end
  for _, lid in ipairs(O._order) do
    local eo = O._byId[lid]
    if eo and eo.visible and not eo.hidden then
      local d = eo.disguise
      -- pokeemerald/src/field_effect_helpers.c:1362
      if d and not d.done and not eo.invisible then
        local sheet = FE().loadSheet(d.sheet)
        local q = sheet and d.a and sheet.quads[d.a.frame or 0]
        if q then
          local _, _, h = objCenter(eo)
          local x = (eo.px or 0) + 8 - sheet.fw / 2
          local y = (eo.py or 0) + CELL - math.floor(h / 2) + math.floor(h / 2) - 16 - sheet.fh / 2
          pushActor(actors, (eo.py or 0) + 0.6, eo.elevation, x, y, function(_, camX, camY)
            love.graphics.setColor(1, 1, 1, O.fadeAlpha(eo) or 1)
            love.graphics.draw(sheet.image, q, math.floor(x) - camX, math.floor(y) - camY)
            love.graphics.setColor(1, 1, 1, 1)
          end)
          -- pokeemerald/src/field_effect_helpers.c:1365
          actors[#actors].disguiseObject = eo
        end
      end
      local bt = eo.berryTree
      if bt and bt.tree and bt.visible then
        local img = berrySheet(bt.tree)
        local fr = img and bt.anim and bt.tree.frames[(bt.anim.frame or 0) + 1]
        if fr then
          local iw, ih = img:getDimensions()
          bt.quad = bt.quad or love.graphics.newQuad(0, 0, 1, 1, iw, ih)
          bt.quad:setViewport(0, fr.y, fr.w, fr.h, iw, ih)
          local x = (eo.px or 0) + (16 - fr.w) / 2
          local y = (eo.py or 0) + 16 - fr.h
          pushActor(actors, eo.py or 0, eo.elevation, x, y, function(_, camX, camY)
            love.graphics.setColor(1, 1, 1, O.fadeAlpha(eo) or 1)
            love.graphics.draw(img, bt.quad, math.floor(x) - camX, math.floor(y) - camY)
            love.graphics.setColor(1, 1, 1, 1)
          end)
        end
      end
      if eo.jumpArc and eo.jumpArc.shadow and not eo.invisible then
        local sheetName, off = FxRse.shadowFor(eo.graphicsId)
        local sheet = FE().loadSheet(sheetName)
        local q = sheet and sheet.quads[0]
        if q then
          local h = sprH(eo)
          local x = (eo.px or 0) + 8 - sheet.fw / 2
          local y = (eo.py or 0) + CELL - math.floor(h / 2) + math.floor(h / 2) - off - sheet.fh / 2
          pushActor(actors, (eo.py or 0) - 0.5, eo.elevation, x, y, function(_, camX, camY)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(sheet.image, q, math.floor(x) - camX, math.floor(y) - camY)
          end)
        end
      end
    end
  end
end

function FxRse.drawBehind(camX, camY)
  drawReflections(camX, camY)
  for _, e in ipairs(FxRse._list) do
    if e.layer == "behind" then drawEntry(e, camX, camY) end
  end
end

function FxRse.drawFront(camX, camY)
  for _, e in ipairs(FxRse._list) do
    if e.layer == "front" then drawEntry(e, camX, camY) end
  end
  for _, name in ipairs(FxRse.SYSTEMS) do
    local mod = package.loaded[name]
    if mod and mod.drawFront then mod.drawFront(camX, camY) end
  end
end

FxRse.HOOKED = {
  "src.core.game3.rotating_tile_puzzle",
}

function FxRse.installHooks()
  for _, name in ipairs(FxRse.HOOKED) do
    local ok, err = pcall(require, name)
    if not ok then print("[game3/field_effects_rse] " .. tostring(err)) end
  end
  lazyReq("src.core.game3.rse.berry_trees").installTimeHook()
end

function FxRse.drawOverlay(camX, camY)
  for _, name in ipairs(FxRse.SYSTEMS) do
    local mod = package.loaded[name]
    if mod and mod.drawOverlay then mod.drawOverlay(camX, camY) end
  end
end

FxRse.installHooks()

return FxRse
