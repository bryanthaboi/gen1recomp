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
FieldEffects._surfClock = 0
FieldEffects._logged = false

local CELL = 16
local FEET_H = 8
local RUSTLE = { 1, 2, 3, 4, 0 }
local FRAME_DUR = 10

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
  if not rgba or #rgba < w * h * 4 then return nil end
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
  if FieldEffects._sheets[name] then return FieldEffects._sheets[name] end
  local totalH = fh * frames
  local root = cache_root() .. "/field_effects/"
  local img = try_load_rgba(FieldEffects._cache, root .. name .. ".rgba", fw, totalH)
    or try_load_rgba(FieldEffects._cache, "field_effects/" .. name .. ".rgba", fw, totalH)
    or try_load_png(root .. name .. ".png")
  if not img then return nil end

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
  FieldEffects._surfClock = 0
  FieldEffects._logged = false
  local ok, Heal = pcall(require, "src.core.game3.pokecenter_heal")
  if ok and Heal and Heal.install then Heal.install(cache) end
end

function FieldEffects.invalidate()
  FieldEffects._sheets = {}
  FieldEffects._fx = nil
  FieldEffects._anims = {}
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

--- Screen flash animation (Flash HM)
function FieldEffects.startFlash(onDone)
  local anim = {
    kind = "flash",
    alpha = 1.0,
    timer = 0,
    maxDur = 30,
    onDone = onDone,
  }
  table.insert(FieldEffects._anims, anim)
end

--- Fly Bird takeoff and landing animations
function FieldEffects.startFlyTakeoff(onMidWarp, onDone)
  load_sheet("fly_bird", 32, 32, 4)
  local P = package.loaded["src.core.game3.player"]
  local px = P and P.px or 0
  local py = P and P.py or 0
  local anim = {
    kind = "fly_takeoff",
    px = px - 8,
    py = py - 40,
    targetPy = py - 8,
    state = "descend",
    timer = 0,
    frame = 0,
    onMidWarp = onMidWarp,
    onDone = onDone,
  }
  table.insert(FieldEffects._anims, anim)
end

function FieldEffects.startFlyLanding(onDone)
  load_sheet("fly_bird", 32, 32, 4)
  local P = package.loaded["src.core.game3.player"]
  local px = P and P.px or 0
  local py = P and P.py or 0
  local anim = {
    kind = "fly_landing",
    px = px - 8,
    py = py - 60,
    targetPy = py - 8,
    state = "descend",
    timer = 0,
    frame = 0,
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

-- ---------------------------------------------------------------- Step & Update
function FieldEffects.step()
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
    elseif anim.kind == "fly_takeoff" then
      anim.frame = math.floor(anim.timer / 4) % 4
      if anim.state == "descend" then
        anim.py = anim.py + 2
        if anim.py >= anim.targetPy then
          anim.py = anim.targetPy
          anim.state = "ascend"
        end
      elseif anim.state == "ascend" then
        anim.py = anim.py - 3
        if anim.py <= -50 then
          finished = true
          if anim.onMidWarp then anim.onMidWarp() end
        end
      end
    elseif anim.kind == "fly_landing" then
      anim.frame = math.floor(anim.timer / 4) % 4
      if anim.state == "descend" then
        anim.py = anim.py + 2
        if anim.py >= anim.targetPy then
          anim.py = anim.targetPy
          anim.state = "leave"
        end
      elseif anim.state == "leave" then
        anim.py = anim.py - 3
        if anim.py <= -50 then
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
    end

    if finished then
      if anim.onDone then anim.onDone() end
    else
      table.insert(active, anim)
    end
  end
  FieldEffects._anims = active

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
    elseif anim.kind == "fly_takeoff" or anim.kind == "fly_landing" then
      local sheet = load_sheet("fly_bird", 32, 32, 4)
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
      love.graphics.setColor(1, 1, 1, anim.alpha)
      love.graphics.rectangle("fill", 0, 0, 240, 160)
      love.graphics.setColor(1, 1, 1, 1)
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
  local ok, Heal = pcall(require, "src.core.game3.pokecenter_heal")
  if ok and Heal and id == Heal.FLDEFF then
    return Heal.start()
  end
  return false
end

function FieldEffects.waitFieldEffect(id, done)
  id = tonumber(id) or 0
  local ok, Heal = pcall(require, "src.core.game3.pokecenter_heal")
  if ok and Heal and id == Heal.FLDEFF then
    Heal.wait(done)
    return
  end
  if done then done() end
end

function FieldEffects.isFieldEffectActive(id)
  id = tonumber(id) or 0
  local ok, Heal = pcall(require, "src.core.game3.pokecenter_heal")
  if ok and Heal and id == Heal.FLDEFF then
    return Heal.isActive()
  end
  return false
end

return FieldEffects
