-- Battle animation host: present state, HP tween, busy gate, VM launch facade.
-- Engine stays pure; this layer owns display offsets and pacing.

local Task = require("src.core.game3.task")
local AnimVm = require("src.core.game3.battle.anim_vm")
local AnimSprites = require("src.core.game3.battle.anim_sprites")
local BallOpen = require("src.core.game3.battle.ball_open")
local AnimPal = require("src.core.game3.battle.anim_pal")
local AnimCoords = require("src.core.game3.battle.anim_coords")

local Anim = {}

Anim.Z = AnimVm.Z
Anim.Coords = AnimCoords

-- pret sBattlerCoords (singles) — CreateSprite CENTER
Anim.ENEMY_MON = { x = 176, y = 40 }
Anim.PLAYER_MON = { x = 72, y = 80 }

Anim._vm = nil
Anim._headless = false
Anim._pack = nil
Anim._packLoaded = false
Anim._hpTweening = false
Anim._expTweening = false
Anim._introTweening = 0
Anim._stageTasks = {}
Anim._seqBusy = false
Anim._statusQueue = {}
Anim._present = AnimCoords.idTable()
Anim._stage = nil
Anim._screenEffect = {
  type = "none",
  coeff = 0,
  targetColor = { 1, 1, 1 },
}
Anim._screenShader = nil

local SCREEN_SHADER_SRC = [[
extern int effectType;
extern float coeff;
extern vec3 targetColor;

vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
  vec4 c = Texel(tex, tc) * color;
  if (effectType == 1) {
    return vec4(vec3(1.0) - c.rgb, c.a);
  } else if (effectType == 2) {
    return vec4(mix(c.rgb, vec3(1.0), coeff), c.a);
  } else if (effectType == 3) {
    return vec4(mix(c.rgb, vec3(0.0), coeff), c.a);
  } else if (effectType == 4) {
    float luma = dot(c.rgb, vec3(0.299, 0.587, 0.114));
    return vec4(mix(c.rgb, vec3(luma), coeff), c.a);
  } else if (effectType == 5) {
    return vec4(mix(c.rgb, targetColor, coeff), c.a);
  }
  return c;
}
]]

function Anim.setScreenEffect(opts)
  if not opts or opts.type == "none" or opts.type == false then
    Anim._screenEffect = { type = "none", coeff = 0, targetColor = { 1, 1, 1 } }
    return
  end
  Anim._screenEffect = {
    type = opts.type or "invert",
    coeff = opts.coeff or 1,
    targetColor = opts.targetColor or { 1, 1, 1 },
  }
end

function Anim.screenEffect()
  return Anim._screenEffect
end

function Anim.beginScreenEffect()
  local fx = Anim._screenEffect
  if not fx or fx.type == "none" then return false end
  if not (love and love.graphics and love.graphics.newShader) then return false end

  if Anim._screenShader == nil then
    local ok, sh = pcall(love.graphics.newShader, SCREEN_SHADER_SRC)
    Anim._screenShader = ok and sh or false
  end
  local sh = Anim._screenShader
  if not sh then return false end

  local typeCode = 0
  if fx.type == "invert" then typeCode = 1
  elseif fx.type == "fade_white" then typeCode = 2
  elseif fx.type == "fade_black" or fx.type == "darken" then typeCode = 3
  elseif fx.type == "grayscale" then typeCode = 4
  elseif fx.type == "custom_blend" then typeCode = 5
  end

  if typeCode == 0 then return false end

  pcall(function()
    sh:send("effectType", typeCode)
    sh:send("coeff", fx.coeff or 1.0)
    sh:send("targetColor", fx.targetColor or { 1, 1, 1 })
    love.graphics.setShader(sh)
  end)
  return true
end

function Anim.endScreenEffect()
  if love and love.graphics and love.graphics.setShader then
    love.graphics.setShader()
  end
end

local function default_present(id)
  local side = AnimCoords.sideOf(id)
  local z = (side == "player") and Anim.Z.PLAYER or Anim.Z.ENEMY
  return {
    id = id,
    side = side,
    ox = 0,
    oy = 0,
    alpha = 1,
    visible = true,
    z = z,
    hFlip = false,
    darken = 0,
    scale = 1,
    sx = 1,
    sy = 1,
    rotation = 0,
    displayHp = nil,
    displayMaxHp = nil,
    displayExp = nil,
    displayLevel = nil,
    flash = 0,
  }
end

local function default_stage(headless)
  return {
    slide = headless and 1 or 0,
    slideDone = headless and true or false,
    trainer = {
      player = { visible = false, ox = 0, oy = 0, frame = 0, gender = 0 },
      enemy = { visible = false, ox = 0, oy = 0, picId = nil },
    },
    ball = { visible = false, x = 0, y = 0, frame = 0, side = nil },
    balls = {},
    healthbox = AnimCoords.idTable({
      [0] = { visible = headless and true or false, ox = 0 },
      [1] = { visible = headless and true or false, ox = 0 },
      [2] = { visible = headless and true or false, ox = 0 },
      [3] = { visible = headless and true or false, ox = 0 },
    }),
    partyBar = {
      player = { visible = false, ox = 0, balls = {} },
      enemy = { visible = false, ox = 0, balls = {} },
    },
    bgSlide = {
      enemyOx = 0,
      playerOx = 0,
    },
  }
end

function Anim.x(v)
  local vm = Anim._vm
  if vm and vm.isReversed then return -(tonumber(v) or 0) end
  return tonumber(v) or 0
end

function Anim.idOf(key)
  if key == "attacker_side" then
    local vm = Anim._vm
    return vm and vm.attackerId and vm:attackerId() or 0
  end
  return AnimCoords.idOf(key)
end

function Anim.sideOf(id)
  return AnimCoords.sideOf(id)
end

function Anim.isDouble(st)
  return AnimCoords.isDouble(st)
end

function Anim.setDouble(v)
  AnimCoords.setDouble(v)
end

function Anim.present(key)
  local id = Anim.idOf(key)
  if id == nil then return nil end
  local p = rawget(Anim._present, id)
  if not p then
    if id >= 2 and not AnimCoords.isDouble() then return nil end
    p = default_present(id)
    if id >= 2 and not Anim._headless then p.visible = false end
    rawset(Anim._present, id, p)
  end
  return p
end

-- pokefirered/src/battle_anim_mons.c:105
function Anim.coords(st, key)
  return AnimCoords.coords(st, key)
end

-- pokefirered/src/battle_anim_mons.c:1908
function Anim.subpriority(key)
  return AnimCoords.subpriority(key)
end

-- pokefirered/src/battle_anim_mons.c:1934
function Anim.bgPriorityRank(key)
  return AnimCoords.bgPriorityRank(key)
end

function Anim.monDrawOrder(st)
  return AnimCoords.monDrawOrder(st)
end

function Anim.particleBand(k, st)
  return AnimCoords.particleBand(k, st)
end

function Anim.battlerIds(st)
  return AnimCoords.ids(st)
end

function Anim.battlerCenter(key)
  local base = Anim.coords(nil, key) or Anim.ENEMY_MON
  local p = Anim.present(key)
  local cx = base.x + (p and p.ox or 0)
  local cy = base.y + (p and p.oy or 0)
  return cx, cy
end

function Anim.reset(opts)
  opts = opts or {}
  for id in pairs(Anim._stageTasks) do Task.cancel(id) end
  Anim._stageTasks = {}
  Anim._headless = opts.headless and true or false
  Anim._hpTweening = false
  Anim._hpTweenTask = nil
  Anim._expTweening = false
  Anim._expTweenTask = nil
  Anim._introTweening = 0
  Anim._seqBusy = false
  Anim._statusQueue = {}
  AnimCoords.setDouble(opts.double)
  AnimCoords.bind(nil)
  for id = 0, 3 do rawset(Anim._present, id, nil) end
  for id = 0, AnimCoords.isDouble() and 3 or 1 do
    local p = default_present(id)
    if not Anim._headless then p.visible = false end
    rawset(Anim._present, id, p)
  end
  Anim._stage = default_stage(Anim._headless)
  if not Anim._vm then
    Anim._vm = AnimVm.new()
  end
  Anim._vm.headless = Anim._headless
  Anim._vm:reset()
  if Anim._pack then
    Anim._vm:setPack(Anim._pack)
  end
  Anim._screenEffect = { type = "none", coeff = 0, targetColor = { 1, 1, 1 } }
  Anim._bgPalAffine = nil
  Anim._bgBlend = nil
  Anim._g1BgBlend = nil
  Anim._bg3Scroll = nil
  if love and love.graphics and love.graphics.setDefaultFilter then
    pcall(love.graphics.setDefaultFilter, "nearest", "nearest")
  end
  AnimSprites.reset()
  BallOpen.reset()
end

-- pokefirered/src/pokeball.c:769
function Anim.ballOpen(key, x, y)
  if Anim._headless then return nil end
  local id = Anim.idOf(key) or 1
  local b = AnimCoords.battler(nil, id)
  return BallOpen.start(id, x, y, b and b.mon and b.mon.pokeball)
end

local function play_se(name, pan)
  pcall(function()
    local SE = require("src.core.game3.se_ids")
    require("src.core.game3.audio").playSe(SE[name], { pan = pan })
  end)
end

-- pokefirered/src/pokeball.c:349
function Anim.sendOutMon(key, opts)
  opts = opts or {}
  local id = Anim.idOf(key) or 1
  local side = AnimCoords.sideOf(id)
  local p = Anim.present(id)
  local done = opts.onComplete
  if Anim._headless or not p then
    if p then
      p.visible = true
      p.ox, p.oy, p.scale = 0, 0, 1
    end
    if done then done() end
    return nil
  end
  local base = Anim.coords(nil, id) or Anim.ENEMY_MON
  local stage = Anim.stage()
  stage.balls = stage.balls or {}
  local ball = { visible = true, frame = 0, rot = 0, side = side, battler = id, x = 0, y = 0 }
  stage.balls[id] = ball
  local pan = (side == "player") and -64 or 63
  local function reveal()
    ball.frame = 1
    ball.rot = 0
    play_se("SE_BALL_OPEN", pan)
    Anim.ballOpen(id, ball.x, ball.y)
    p.visible = true
    p.ox = 0
    p.oy = 16
    p.scale = 0.16
    p.darken = 0
    Anim.tweenStage(12, function(u)
      p.oy = 16 * (1 - u)
      p.scale = 0.16 + 0.84 * u
      ball.frame = (u < 0.5) and 1 or 2
    end, function()
      p.oy = 0
      p.scale = 1
      ball.visible = false
      if stage.balls[id] == ball then stage.balls[id] = nil end
      if done then done() end
    end)
  end
  if side == "player" then
    -- pokefirered/src/pokeball.c:912
    local sx, sy = 48, 70
    local tx, ty = base.x, base.y + 24
    ball.x, ball.y = sx, sy
    play_se("SE_BALL_THROW", pan)
    Anim.tweenStage(25, function(u, t)
      local f = t and t.frames or (u * 25)
      ball.x = sx + (tx - sx) * u
      ball.y = sy + (ty - sy) * u + (-30 * 4 * u * (1 - u))
      ball.rot = f * ((25 / 256) * math.pi * 2)
    end, reveal)
  else
    -- pokefirered/src/pokeball.c:406
    ball.x, ball.y = base.x, base.y + 24
    Anim.tweenStage(16, function() end, reveal)
  end
  return ball
end

function Anim.setSeqBusy(v)
  Anim._seqBusy = v and true or false
end

function Anim.hpTweening()
  return Anim._hpTweening == true
end

--- True while a clip or HP bar is mid-flight (NOT while the host sequencer merely has steps left).
-- Including seqBusy here soft-locks Battle.update: animating waits on busy() before AnimSeq.update().
function Anim.busy()
  if Anim._headless then return false end
  if Anim._hpTweening then return true end
  if Anim._expTweening then return true end
  if (Anim._introTweening or 0) > 0 then return true end
  if Anim._vm and Anim._vm:busy() then return true end
  return false
end

function Anim.stage()
  if not Anim._stage then
    Anim._stage = default_stage(Anim._headless)
  end
  return Anim._stage
end

function Anim.introSlideDone()
  local s = Anim.stage()
  return s and s.slideDone == true
end

--- Pret faint presentation: SE_FAINT + sink/slide off, then hide mon + healthbox.
-- Opponent: SpriteCB_AnimFaintOpponent — +8px every 2 frames, ~8 steps.
-- Player: SpriteCB_FaintSlideAnim — +5px/frame until below screen.
function Anim.faintMon(key, opts)
  opts = opts or {}
  local id = Anim.idOf(key or "enemy") or 1
  local side = AnimCoords.sideOf(id)
  local p = Anim.present(id)
  local stage = Anim.stage()
  local hb = stage and stage.healthbox and stage.healthbox[id]
  local AnimSprites = require("src.core.game3.battle.anim_sprites")
  AnimSprites.clearHost(id)

  local function hide_all()
    if p then
      p.visible = false
      p.oy = 0
    end
    if hb then hb.visible = false end
  end

  if Anim._headless or not p then
    hide_all()
    if opts.onComplete then opts.onComplete() end
    return
  end

  if opts.playSe ~= false then
    local okA, Audio = pcall(require, "src.core.game3.audio")
    local okS, SE = pcall(require, "src.core.game3.se_ids")
    if okA and okS and Audio.playSe and SE and SE.SE_FAINT then
      Audio.playSe(SE.SE_FAINT)
    end
  end

  local fromOy = p.oy or 0
  if side == "enemy" then
    -- data[3] ≈ 8 − yOffset/8 → ~8 steps; 2 frames each → 16 frames, +64px.
    local steps = 8
    local frames = steps * 2
    Anim.tweenStage(frames, function(u)
      local step = math.min(steps, math.floor(u * steps + 1e-9))
      p.oy = fromOy + step * 8
    end, function()
      hide_all()
      if opts.onComplete then opts.onComplete() end
    end)
  else
    -- Player back sprite center y=80; +5/frame until below 160.
    local screenH = 160
    do
      local ok, Display = pcall(require, "src.core.game3.display")
      if ok and Display and Display.H then screenH = Display.H end
    end
    local base = Anim.coords(nil, id) or Anim.PLAYER_MON
    local need = math.max(1, math.ceil((screenH - (base.y or 80) + 32) / 5))
    local frames = math.max(16, need + 2)
    Anim.tweenStage(frames, function(_, t)
      p.oy = fromOy + 5 * (t.frames or 1)
    end, function()
      hide_all()
      if opts.onComplete then opts.onComplete() end
    end)
  end
end

--- Tween helper that raises Anim.busy via _introTweening (in-flight only).
function Anim.tweenStage(frames, onStep, onComplete)
  if Anim._headless then
    if onStep then onStep(1) end
    if onComplete then onComplete() end
    return nil
  end
  Anim._introTweening = (Anim._introTweening or 0) + 1
  local t
  t = Task.tween(frames, onStep, function()
    Anim._stageTasks[t.id] = nil
    Anim._introTweening = math.max(0, (Anim._introTweening or 1) - 1)
    if onComplete then onComplete() end
  end)
  Anim._stageTasks[t.id] = true
  return t
end

function Anim.seqBusy()
  return Anim._seqBusy == true
end

function Anim.vm()
  return Anim._vm
end

--- Sync display HP from logical battler (instant).
function Anim.syncDisplayFromState(st)
  if not st then return end
  local Experience = require("src.core.game3.battle.experience")
  for _, id in ipairs(AnimCoords.ids(st)) do
    local b = AnimCoords.battler(st, id)
    local p = Anim.present(id)
    if b and b.mon and p then
      p.displayHp = tonumber(b.mon.hp) or 0
      p.displayMaxHp = tonumber(b.mon.maxHp) or 1
      p.displayLevel = tonumber(b.mon.level) or 1
      local prog = Experience.progress(b.mon)
      p.displayExp = prog.progressPercent or 0
    end
  end
end

--- Lerp display HP; onComplete when done. frames ≈ pret healthbar speed.
function Anim.tweenHp(side, fromHp, toHp, maxHp, opts)
  opts = opts or {}
  local p = Anim.present(side)
  if not p then
    if opts.onComplete then opts.onComplete() end
    return
  end
  maxHp = math.max(1, tonumber(maxHp) or p.displayMaxHp or 1)
  fromHp = tonumber(fromHp)
  toHp = tonumber(toHp)
  if fromHp == nil then fromHp = p.displayHp or toHp or 0 end
  if toHp == nil then toHp = fromHp end
  p.displayMaxHp = maxHp
  if Anim._headless or opts.instant then
    p.displayHp = toHp
    if opts.onComplete then opts.onComplete() end
    return
  end
  local delta = math.abs(toHp - fromHp)
  -- pret-ish: ~1 HP per frame-ish for small, cap duration
  local frames = math.max(4, math.min(40, math.floor(delta / math.max(1, maxHp / 48)) + 4))
  if opts.frames then frames = opts.frames end
  Anim._hpTweening = true
  p.displayHp = fromHp
  local t
  t = Task.tween(frames, function(u)
    p.displayHp = fromHp + (toHp - fromHp) * u
  end, function()
    Anim._stageTasks[t.id] = nil
    p.displayHp = toHp
    if Anim._hpTweenTask == t.id then
      Anim._hpTweening = false
      Anim._hpTweenTask = nil
    end
    if opts.onComplete then opts.onComplete() end
  end)
  Anim._hpTweenTask = t.id
  Anim._stageTasks[t.id] = true
end

--- Lerp player EXP bar ratio 0..1 within current level band.
function Anim.tweenExp(side, fromRatio, toRatio, opts)
  opts = opts or {}
  side = side or "player"
  local p = Anim.present(side)
  if not p then
    if opts.onComplete then opts.onComplete() end
    return
  end
  fromRatio = math.max(0, math.min(1, tonumber(fromRatio) or p.displayExp or 0))
  toRatio = math.max(0, math.min(1, tonumber(toRatio) or fromRatio))
  if opts.level then p.displayLevel = opts.level end
  if Anim._headless or opts.instant then
    p.displayExp = toRatio
    if opts.onComplete then opts.onComplete() end
    return
  end
  local delta = math.abs(toRatio - fromRatio)
  local fillFrames = math.max(1, math.floor(delta * 64 + 0.5))
  local leadIn = 13 -- pokefirered Task_GiveExpWithExpBar 13-frame sound pre-roll
  local totalFrames = leadIn + fillFrames
  if opts.frames then
    totalFrames = opts.frames
    leadIn = math.min(13, math.floor(totalFrames * 0.2))
    fillFrames = math.max(1, totalFrames - leadIn)
  end
  Anim._expTweening = true
  p.displayExp = fromRatio
  local task
  task = Task.tween(totalFrames, function(_, t)
    local curFrame = t.frames or 0
    if curFrame <= leadIn then
      p.displayExp = fromRatio
    else
      local u = math.min(1, (curFrame - leadIn) / fillFrames)
      p.displayExp = fromRatio + (toRatio - fromRatio) * u
    end
  end, function()
    Anim._stageTasks[task.id] = nil
    p.displayExp = toRatio
    if Anim._expTweenTask == task.id then
      Anim._expTweening = false
      Anim._expTweenTask = nil
    end
    if opts.onComplete then opts.onComplete() end
  end)
  Anim._expTweenTask = task.id
  Anim._stageTasks[task.id] = true
end

function Anim.displayExpRatio(side, battler)
  local p = Anim.present(side or "player")
  if p and p.displayExp ~= nil then
    return math.max(0, math.min(1, p.displayExp)), p.displayLevel
  end
  if battler and battler.mon then
    local Experience = require("src.core.game3.battle.experience")
    local prog = Experience.progress(battler.mon)
    return prog.progressPercent or 0, tonumber(battler.mon.level) or 1
  end
  return 0, 1
end

function Anim.displayHpRatio(side, battler)
  local p = Anim.present(side)
  local hp, maxHp
  if p and p.displayHp ~= nil then
    hp = p.displayHp
    maxHp = p.displayMaxHp or (battler and battler.mon and battler.mon.maxHp) or 1
  elseif battler and battler.mon then
    hp = tonumber(battler.mon.hp) or 0
    maxHp = tonumber(battler.mon.maxHp) or 1
  else
    return 0, 0, 1
  end
  maxHp = math.max(1, tonumber(maxHp) or 1)
  hp = math.max(0, tonumber(hp) or 0)
  return math.max(0, math.min(1, hp / maxHp)), hp, maxHp
end

--- GBA indexed sheets store transparent as palette index 0 (often magenta #6229FF).
-- Love2D expands that to opaque pixels — punch them to alpha 0.
local function punch_gba_transparent(imageData)
  if not imageData or not imageData.mapPixel then return imageData end
  -- Exact pret key color and near-matches (98/255, 41/255, 1)
  local kr, kg, kb = 98 / 255, 41 / 255, 1
  imageData:mapPixel(function(_x, _y, r, g, b, a)
    if a < 0.01 then return 0, 0, 0, 0 end
    -- Exact key
    if math.abs(r - kr) < 0.004 and math.abs(g - kg) < 0.004 and math.abs(b - kb) < 0.004 then
      return 0, 0, 0, 0
    end
    -- Generic bright magenta/blue key used across pret sheets (high B, mid R, low G)
    if b > 0.95 and r > 0.30 and r < 0.50 and g < 0.25 then
      return 0, 0, 0, 0
    end
    return r, g, b, a
  end)
  return imageData
end

local function hydrate_tag_images(pack)
  if not pack or not pack.tags then return end
  if not (love and love.image and love.graphics) then return end
  local ok, Dataset = pcall(require, "src.core.game3.dataset")
  local cache = ok and Dataset.cache and Dataset.cache() or nil
  local root = "data/generated/gba/pokemon/battle_anims/"
  for tag, info in pairs(pack.tags) do
    if type(info) == "table" and not info.image and info.file then
      local bytes = nil
      local rel = root .. info.file
      if cache and cache.read then
        bytes = cache:read(rel)
        if not bytes then bytes = cache:read("firered/" .. rel) end
      end
      if type(bytes) == "string" and #bytes > 0 then
        local okFd, fileData = pcall(love.filesystem.newFileData, bytes, info.file)
        if okFd and fileData then
          local okId, imageData = pcall(love.image.newImageData, fileData)
          if okId and imageData then
            punch_gba_transparent(imageData)
            local okImg, image = pcall(love.graphics.newImage, imageData)
            if okImg and image then
              image:setFilter("nearest", "nearest")
              info.image = image
              info.w = image:getWidth()
              info.h = image:getHeight()
              AnimPal.hydrateIndex(info, tag, image, function(f)
                return cache and cache.read and (cache:read(root .. f) or cache:read("firered/" .. root .. f))
              end)
            end
          end
        end
      end
    end
  end
end

local function load_pack()
  if Anim._packLoaded then return Anim._pack end
  Anim._packLoaded = true
  local chunk
  local ok, Dataset = pcall(require, "src.core.game3.dataset")
  local cache = ok and Dataset.cache and Dataset.cache() or nil
  local rels = {
    "data/generated/gba/pokemon/battle_anims/pack.lua",
    "firered/data/generated/gba/pokemon/battle_anims/pack.lua",
  }
  if cache and cache.read then
    for _, rel in ipairs(rels) do
      local src = cache:read(rel)
      if type(src) == "string" and #src > 0 then
        local loader = loadstring or load
        local fn, err = loader(src, "@" .. rel)
        if fn then
          local ok2, result = pcall(fn)
          if ok2 and type(result) == "table" then
            chunk = result
            break
          end
        else
          print("[battle.anim] pack load error: " .. tostring(err))
        end
      end
    end
  end
  if not chunk then
    local okR, mod = pcall(require, "src.core.game3.battle.anim_pack_fallback")
    if okR then chunk = mod end
  end
  if chunk then
    hydrate_tag_images(chunk)
  end
  Anim._pack = chunk
  if Anim._vm and chunk then Anim._vm:setPack(chunk) end
  return chunk
end

function Anim.loadPack(pack)
  Anim._pack = pack
  Anim._packLoaded = true
  AnimPal.setPack(pack)
  if Anim._vm then Anim._vm:setPack(pack) end
end

local GENERIC_HIT = {
  { op = "loadspritegfx", tag = "IMPACT" },
  { op = "monbg", battler = "target" },
  { op = "createsprite", template = "gHorizontalLungeSpriteTemplate", animBattler = "attacker", subpriority = 2, args = { 4, 4 } },
  { op = "delay", frames = 6 },
  { op = "createsprite", template = "gBasicHitSplatSpriteTemplate", animBattler = "attacker", subpriority = 2, tag = "IMPACT", args = { 0, 0, "target", 2 } },
  { op = "createvisualtask", task = "AnimTask_ShakeMon", priority = 2, args = { "target", 3, 0, 6, 1 } },
  { op = "waitforvisualfinish" },
  { op = "clearmonbg", battler = "target" },
  { op = "end" },
}

local GENERIC_STATUS = {
  { op = "createvisualtask", task = "AnimTask_ShakeMon", priority = 2, args = { "attacker", 1, 0, 8, 1 } },
  { op = "waitforvisualfinish" },
  { op = "end" },
}

local GENERIC_MISS = {
  { op = "delay", frames = 8 },
  { op = "end" },
}

function Anim.scriptForMove(moveId)
  local pack = load_pack()
  local numId = tonumber(moveId)
  if not numId then
    local okM, Moves = pcall(require, "src.core.game3.battle.moves")
    if okM and Moves and Moves.numForName then
      numId = Moves.numForName(moveId)
    end
  end
  numId = numId or tonumber(moveId) or moveId
  if pack and pack.moves then
    local s = pack.moves[numId] or pack.moves[tostring(numId)] or pack.moves[moveId]
    if s then return s end
  end
  return GENERIC_HIT
end

function Anim.scriptForStatus(statusId)
  local pack = load_pack()
  if pack and pack.status and pack.status[statusId] then
    return pack.status[statusId]
  end
  return GENERIC_STATUS
end

--- Launch move anim. opts: { attackerSide, targetSide, attackerSpecies, targetSpecies, isReversed, onEnd, miss }
function Anim.launchMove(moveId, opts)
  opts = opts or {}
  if not Anim._vm then Anim.reset({ headless = Anim._headless }) end
  if opts.miss then
    return Anim._vm:launch(GENERIC_MISS, opts)
  end
  local script = Anim.scriptForMove(moveId)
  return Anim._vm:launch(script, opts)
end

local STATUS_PACK_NAME = {
  POISON = "STATUS_PSN", BURN = "STATUS_BRN", SLEEP = "STATUS_SLP", PARALYSIS = "STATUS_PRZ",
  FREEZE = "STATUS_FRZ", CONFUSION = "STATUS_CONFUSION", INFATUATION = "STATUS_INFATUATION",
  CURSED = "STATUS_CURSED", NIGHTMARE = "STATUS_NIGHTMARE",
}

function Anim.tableIndex(kind, name)
  if type(name) == "number" then return name end
  local pack = load_pack()
  local names = pack and pack[kind .. "Names"]
  if not names then return nil end
  local want = tostring(name or "")
  if kind == "status" then want = STATUS_PACK_NAME[want] or want end
  for i = 0, 63 do
    local n = names[i]
    if n == nil and i > 0 and names[i + 1] == nil then break end
    if n == want or n == "B_ANIM_" .. want then return i end
  end
  return nil
end

function Anim.tableScript(kind, name)
  local pack = load_pack()
  local idx = Anim.tableIndex(kind, name)
  local tbl = pack and pack[kind]
  return idx and tbl and tbl[idx] or nil, idx
end

local function launch_table(kind, name, opts)
  opts = opts or {}
  if not Anim._vm then Anim.reset({ headless = Anim._headless }) end
  local script = Anim.tableScript(kind, name)
  if not script then
    if opts.onEnd then opts.onEnd() end
    return false
  end
  local o = {}
  for k, v in pairs(opts) do o[k] = v end
  if o.targetSide == nil then o.targetSide = o.attackerSide end
  if o.targetId == nil then o.targetId = o.attackerId end
  if kind == "status" and o.statusAnim == nil then o.statusAnim = true end
  if Anim._vm.launchScript then return Anim._vm:launchScript(script, o) end
  return Anim._vm:launch(script, o)
end

-- pokefirered/src/battle_gfx_sfx_util.c:208
function Anim.launchGeneral(name, opts)
  return launch_table("general", name, opts)
end

-- pokefirered/src/battle_gfx_sfx_util.c:266
function Anim.launchSpecial(name, opts)
  return launch_table("special", name, opts)
end

-- pokefirered/src/battle_gfx_sfx_util.c:171
function Anim.launchStatus(statusId, opts)
  opts = opts or {}
  if not Anim._vm then Anim.reset({ headless = Anim._headless }) end
  if Anim._vm:busy() and not opts.force then
    Anim._statusQueue[#Anim._statusQueue + 1] = { statusId = statusId, opts = opts }
    return false
  end
  return launch_table("status", statusId, opts)
end

-- pokefirered/src/battle_controller_player.c:1351
function Anim.blinkMon(side, opts)
  opts = opts or {}
  local p = Anim.present(side)
  if Anim._headless or not p or p.visible == false then
    if opts.onComplete then opts.onComplete() end
    return
  end
  Anim.tweenStage(32, function(_, t)
    local f = (t and t.frames or 1) - 1
    p.blinkHidden = (math.floor(f / 4) % 2) == 0
  end, function()
    p.blinkHidden = false
    if opts.onComplete then opts.onComplete() end
  end)
end

function Anim.setShown(side, battler)
  local p = Anim.present(side)
  if p then p.shown = battler end
end

function Anim.shownBattler(side, battler)
  local p = Anim._present[side]
  if p and p.shown then return p.shown end
  return battler
end

-- pokefirered/src/battle_anim_mons.c:286
function Anim.substituteY(key)
  local id = Anim.idOf(key) or 1
  local base = Anim.coords(nil, id) or Anim.ENEMY_MON
  if AnimCoords.sideOf(id) == "player" then return base.y + 17 end
  return base.y + 16
end

-- pokefirered/src/battle_gfx_sfx_util.c:762
function Anim.substituteImage(key)
  local pack = load_pack()
  local tags = pack and pack.tags
  local id = Anim.idOf(key) or 1
  local info = tags and tags[(AnimCoords.sideOf(id) == "player") and "SUBSTITUTE_DOLL_BACK" or "SUBSTITUTE_DOLL_FRONT"]
  return info and info.image or nil
end

function Anim.setSubstitute(side, on)
  local p = Anim.present(side)
  if not p then return end
  p.substitute = on and true or false
  p.substituteY = on and Anim.substituteY(side) or nil
end

Anim._statMaskImgs = {}

-- pokefirered/src/battle_anim_utility_funcs.c:464
function Anim.statMaskImage(tilemap, pal)
  if type(tilemap) == "string" and not tonumber(tilemap) then
    load_pack()
    local img = AnimPal.bgImages(tilemap)
    return img
  end
  local key = (tonumber(tilemap) or 1) * 16 + (tonumber(pal) or 5)
  local hit = Anim._statMaskImgs[key]
  if hit ~= nil then return hit or nil end
  Anim._statMaskImgs[key] = false
  if not (love and love.image and love.graphics) then return nil end
  local pack = load_pack()
  local sm = pack and pack.statMask
  local rel = sm and sm.files and sm.files[tonumber(tilemap) or 1]
  local row = sm and sm.pals and sm.pals[tonumber(pal) or 5]
  if not (rel and row) then return nil end
  local ok, Dataset = pcall(require, "src.core.game3.dataset")
  local cache = ok and Dataset.cache and Dataset.cache() or nil
  local path = "data/generated/gba/pokemon/battle_anims/" .. rel
  local bytes = cache and cache.read and (cache:read(path) or cache:read("firered/" .. path))
  if type(bytes) ~= "string" or #bytes == 0 then return nil end
  local okD, data = pcall(function()
    return love.image.newImageData(love.filesystem.newFileData(bytes, rel))
  end)
  if not okD or not data then return nil end
  data:mapPixel(function(_, _, r, _, _, a)
    if a < 0.5 then return 0, 0, 0, 0 end
    local c = row[math.floor(r * 255 / 16 + 0.5) + 1] or row[1]
    return c[1] / 255, c[2] / 255, c[3] / 255, 1
  end)
  local img = love.graphics.newImage(data)
  img:setFilter("nearest", "nearest")
  img:setWrap("repeat", "repeat")
  Anim._statMaskImgs[key] = img
  return img
end

local function pump_status_queue()
  if Anim._vm and Anim._vm:busy() then return end
  local next = table.remove(Anim._statusQueue, 1)
  if next then
    Anim.launchStatus(next.statusId, next.opts)
  end
end

function Anim.update(dt)
  if Anim._headless then return end
  -- HP tweens live on shared Task list
  if Anim._vm then
    Anim._vm:update(dt)
    if not Anim._vm.active then
      for _, p in pairs(Anim._present) do
        if p then p.statMask = nil end
      end
    end
  end
  BallOpen.tick()
  pump_status_queue()
end

function Anim.drawParticles(minZ, maxZ)
  if Anim._headless then return end
  if Anim._vm then Anim._vm:draw(minZ, maxZ) end
end

return Anim
