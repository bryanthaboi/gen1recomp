local P = require("src.core.game3.battle.anim_port.g3_pret")
local AnimPal = require("src.core.game3.battle.anim_pal")

local T = {}
local band = P.band or bit.band

local function monBase(vm, side)
  local p = P.monPresent(side)
  local cx, cy = P.monCenter(vm, side)
  return cx - ((p and p.ox) or 0), cy - ((p and p.oy) or 0)
end

local function sx16(v) return P.s16(v) end

local function statMask(side, mask)
  local p = P.monPresent(side)
  if p then p.statMask = mask end
  return p
end

local function clearStatMask(side, mask)
  local p = P.monPresent(side)
  if p and p.statMask == mask then p.statMask = nil end
end

local function sandstormStep(t, vm)
  local d = t.data
  if d[0] == 0 then
    t._bg1x = sx16((t._bg1x or 0) - 6)
  else
    t._bg1x = sx16((t._bg1x or 0) + 6)
  end
  t._bg1y = sx16((t._bg1y or 0) - 1)
  local k = d[12]
  if k == 0 then
    d[10] = d[10] + 1
    if d[10] == 4 then
      d[10] = 0
      d[11] = d[11] + 1
      P.setBld(vm, d[11], 16 - d[11])
      if d[11] == 7 then
        d[12] = d[12] + 1
        d[11] = 0
      end
    end
  elseif k == 1 then
    d[11] = d[11] + 1
    if d[11] == 101 then
      d[11] = 7
      d[12] = d[12] + 1
    end
  elseif k == 2 then
    d[10] = d[10] + 1
    if d[10] == 4 then
      d[10] = 0
      d[11] = d[11] - 1
      P.setBld(vm, d[11], 16 - d[11])
      if d[11] == 0 then
        d[12] = d[12] + 1
        d[11] = 0
      end
    end
  elseif k == 3 then
    P.bg1Clear(t)
    d[12] = d[12] + 1
  elseif k == 4 then
    t._bg1x, t._bg1y = 0, 0
    P.setBld(vm, nil)
    P.DestroyAnimVisualTask(t)
  end
end

-- pokefirered/src/battle_anim_rock.c:388
T.LoadSandstormBackground = P.task(function(t, vm)
  P.setBld(vm, 0, 16)
  t._bg1x, t._bg1y = 0, 0
  P.bg1Layer(t, vm, "SANDSTORM", 1)
  local var0 = 0
  if t.ga[0] ~= 0 and not P.atkIsPlayer(vm) then var0 = 1 end
  t.data[0] = var0
  t.fn = sandstormStep
end)

local function surfBands(t)
  local sc = t._scan
  if not sc then return nil end
  return sc
end

local function surfDraw(t, vm)
  local sc = surfBands(t)
  if not sc then return end
  local x, y = t._bg1x or 0, t._bg1y or 0
  local function band_(y0, y1, v)
    if y1 <= y0 then return end
    local eva, evb = band(v, 0x1F), band(P.shr(v, 8), 0x1F)
    if eva <= 0 then return end
    AnimPal.drawBg("SURF_" .. t._surfSide, "bg1", x, y + y0, { y = y0, h = y1 - y0, eva = eva, evb = evb })
  end
  band_(0, sc[4], sc[2])
  band_(sc[4], sc[5], sc[1])
  band_(sc[5], 160, sc[2])
end

local function surfScanStep(t)
  local sc = t._scan
  if not sc then return end
  if sc[0] == 0 then
    sc[0] = 1
  elseif sc[0] == 1 then
    if sc[3] == 0 then
      sc[4] = sc[4] - 1
      if sc[4] <= 0 then
        sc[4] = 0
        sc[0] = 2
      end
    else
      sc[5] = sc[5] + 1
      if sc[5] > 111 then sc[0] = 2 end
    end
  end
end

local function surfStep2(t, vm)
  local d = t.data
  surfScanStep(t)
  if d[0] == 0 then
    t.draw = nil
    d[0] = d[0] + 1
  else
    t._bg1x, t._bg1y = 0, 0
    P.setBld(vm, nil)
    t._scan = nil
    P.DestroyAnimVisualTask(t)
  end
end

local function surfStep1(t, vm)
  local d = t.data
  t._bg1x = sx16((t._bg1x or 0) + d[0])
  t._bg1y = sx16((t._bg1y or 0) + d[1])
  d[2] = d[2] + d[1]
  d[5] = d[5] + 1
  if d[5] == 4 then
    local f = AnimPal.bgWriteFaded("bg1")
    if f then
      local buf = f[7]
      for i = 6, 1, -1 do f[1 + i] = f[i] end
      f[1] = buf
    end
    d[5] = 0
  end
  d[6] = d[6] + 1
  if d[6] > 1 then
    d[6] = 0
    d[3] = d[3] + 1
    if d[3] < 14 then
      t._scan[1] = P.s16(d[3] + P.lshift(16 - d[3], 8))
      d[4] = d[4] + 1
    end
    if d[3] > 54 then
      d[4] = d[4] - 1
      t._scan[1] = P.s16(d[4] + P.lshift(16 - d[4], 8))
    end
  end
  if band(t._scan[1], 0x1F) == 0 then
    d[0] = band(t._scan[1], 0x1F)
    t.fn = surfStep2
  end
  surfScanStep(t)
end

-- pokefirered/src/battle_anim_water.c:799
T.CreateSurfWave = P.task(function(t, vm)
  local d = t.data
  local opp = not P.atkIsPlayer(vm)
  t._surfSide = opp and "OPPONENT" or "PLAYER"
  AnimPal.bgLoad("bg1", "SURF_" .. t._surfSide, t.ga[0] ~= 0 and AnimPal._pack and AnimPal._pack.bgPals and AnimPal._pack.bgPals.MUDDY_WATER or nil)
  t._scan = { [0] = 0, [1] = 0x1000, [2] = 0x1000 }
  if opp then
    t._bg1x, t._bg1y = -224, 256
    d[0], d[1] = 2, -1
    t._scan[3] = 1
  else
    t._bg1x, t._bg1y = 0, -48
    d[0], d[1] = -2, 1
    t._scan[3] = 0
  end
  if t._scan[3] == 0 then
    t._scan[4], t._scan[5] = 48, 112
  else
    t._scan[4], t._scan[5] = 0, 0
  end
  d[6] = 1
  t.z = P.bgZ(1)
  t.draw = surfDraw
  t.fn = surfStep1
end)

local function curseStep(t, vm)
  local d = t.data
  local m = t._mask
  d[10] = d[10] + 4
  m.y = m.y - 4
  if d[10] == 64 then
    d[10] = 0
    m.y = m.y + 64
    d[11] = d[11] + 1
    if d[11] == 4 then
      clearStatMask(t._side, m)
      P.DestroyAnimVisualTask(t)
    end
  end
end

-- pokefirered/src/battle_anim_utility_funcs.c:288
T.DrawFallingWhiteLinesOnAttacker = P.task(function(t, vm)
  local side = P.atk(vm)
  local x, y = monBase(vm, side)
  t._side = side
  t._mask = { tilemap = "CURSE", x = -x + 32, y = -y + 32, eva = 8, evb = 12 }
  statMask(side, t._mask)
  t.fn = curseStep
end)

local function scrollingMaskStep(t, vm)
  local d = t.data
  local m = t._mask
  local sp = d[1]
  d[13] = d[13] + (sp < 0 and -sp or sp)
  if sp < 0 then
    m.y = m.y - P.shr(d[13], 8)
  else
    m.y = m.y + P.shr(d[13], 8)
  end
  d[13] = band(d[13], 0xFF)
  local k = d[15]
  if k == 0 then
    local old = d[11]
    d[11] = d[11] + 1
    if old >= d[6] then
      d[11] = 0
      d[12] = d[12] + 1
      m.eva, m.evb = d[12], 16 - d[12]
      if d[12] == d[4] then d[15] = d[15] + 1 end
    end
  elseif k == 1 then
    d[10] = d[10] + 1
    if d[10] == d[5] then d[15] = d[15] + 1 end
  elseif k == 2 then
    local old = d[11]
    d[11] = d[11] + 1
    if old >= d[6] then
      d[11] = 0
      d[12] = d[12] - 1
      m.eva, m.evb = d[12], 16 - d[12]
      if d[12] == 0 then
        clearStatMask(t._side, m)
        P.DestroyAnimVisualTask(t)
      end
    end
  end
end

-- pokefirered/src/battle_anim_utility_funcs.c:729
local function startMonScrollingBgMask(t, vm, scrollSpeed, side, numFadeSteps, fadeStepDelay, duration, key)
  local d = t.data
  t._side = side
  t._mask = { tilemap = key, x = 0, y = 0, eva = 0, evb = 16 }
  statMask(side, t._mask)
  d[1] = P.s16(scrollSpeed)
  d[4] = numFadeSteps
  d[5] = duration
  d[6] = fadeStepDelay
  t.fn = scrollingMaskStep
end

-- pokefirered/src/battle_anim_effects_3.c:3830
T.StatusClearedEffect = P.task(function(t, vm)
  startMonScrollingBgMask(t, vm, 0x1A0, P.atk(vm), 10, 2, 30, "CURE_BUBBLES")
end)

local function setGrey(p, restore)
  if not p then return end
  if restore then
    p.grayscale = false
    P.monBlend(p, 0, 0)
  else
    p.grayscale = true
  end
end

local function metallicShineStep(t, vm)
  local d = t.data
  local m = t._mask
  d[10] = d[10] + 4
  m.x = m.x - 4
  if d[10] == 128 then
    d[10] = 0
    m.x = m.x + 128
    d[11] = d[11] + 1
    if d[11] == 2 then
      if d[1] == 0 then setGrey(t._p, true) end
      clearStatMask(t._side, m)
    elseif d[11] == 3 then
      P.setBld(vm, nil)
      P.DestroyAnimVisualTask(t)
    end
  end
end

-- pokefirered/src/battle_anim_dark.c:769
T.MetallicShine = P.task(function(t, vm)
  local d = t.data
  local side = P.atk(vm)
  local x, y = monBase(vm, side)
  t._side = side
  t._p = P.monPresent(side)
  t._mask = { tilemap = "METAL_SHINE", x = -x + 96, y = -y + 32, eva = 8, evb = 12 }
  statMask(side, t._mask)
  if t.ga[1] == 0 then
    setGrey(t._p, false)
  else
    P.monBlend(t._p, 11, P.u16(t.ga[2]))
  end
  d[1] = t.ga[0]
  d[2] = t.ga[1]
  d[3] = t.ga[2]
  t.fn = metallicShineStep
end)

local function rotateBgPal(t, vm, both)
  local d = t.data
  d[5] = d[5] + 1
  if d[5] == 4 then
    local f = AnimPal.bgWriteFaded("bg")
    if f then
      local last = f[11]
      for i = 10, 1, -1 do f[i + 1] = f[i] end
      f[1] = last
    end
    if both then
      local u = AnimPal.bgUnfaded.bg
      if u then
        local last = u[11]
        for i = 10, 1, -1 do u[i + 1] = u[i] end
        u[1] = last
      end
    end
    d[5] = 0
  end
  if P.u16(tonumber(vm.args and vm.args[7]) or 0) == 0xFFFF then
    P.DestroyAnimVisualTask(t)
  end
end

-- pokefirered/src/battle_anim_effects_3.c:1356
T.SetPsychicBackground = P.task(function(t, vm)
  t._g4kind = "aux"
  t.fn = function(tt, v) rotateBgPal(tt, v, false) end
end)

-- pokefirered/src/battle_anim_effects_3.c:1382
T.FadeScreenToWhite = P.task(function(t, vm)
  t._g4kind = "aux"
  t.fn = function(tt, v) rotateBgPal(tt, v, true) end
end)

local function digClip(p, y0, y1, hideBelow)
  local rows = {}
  for r = 0, 159 do
    if r < y0 or r >= y1 then rows[r] = hideBelow and -240 or nil end
  end
  p.hShift = rows
  return rows
end

local function digBounce(t, vm)
  local d = t.data
  local p = t._p
  local k = d[0]
  if k == 0 then
    local y = P.yWithElevation(vm, P.atk(vm))
    d[14] = y - 32
    d[15] = y + 32
    if d[14] < 0 then d[14] = 0 end
    d[13] = 0
    d[0] = d[0] + 1
  elseif k == 1 then
    if p then t._rows = digClip(p, d[14], d[15], true) end
    d[0] = d[0] + 1
  elseif k == 2 then
    d[2] = band(d[2] + 6, 0x7F)
    d[4] = d[4] + 1
    if d[4] > 2 then
      d[4] = 0
      d[3] = d[3] + 1
    end
    d[5] = d[3] + P.shr(P.SINE[d[2] + 1], 4)
    if p then p.oy = d[5] end
    if d[5] > 63 then
      d[5] = 120 - d[14]
      if p then p.oy = d[5] end
      d[0] = d[0] + 1
    end
  elseif k == 3 then
    if p and p.hShift == t._rows then p.hShift = nil end
    d[0] = d[0] + 1
  elseif k == 4 then
    if p then
      p.invisible = true
      p.oy = 0
      p.ox = 272 - P.coord(vm, P.atk(vm), P.COORD_X)
    end
    P.DestroyAnimVisualTask(t)
  end
end

local function digDisappear(t, vm)
  local p = t._p
  if p then
    p.invisible = true
    p.ox, p.oy = 0, 0
    p.hShift = nil
  end
  P.DestroyAnimVisualTask(t)
end

-- pokefirered/src/battle_anim_ground.c:282
T.DigDownMovement = P.task(function(t, vm)
  t._p = P.monPresent(P.atk(vm))
  if t.ga[0] == 0 then
    t.fn = digBounce
  else
    t.fn = digDisappear
  end
  t.fn(t, vm)
end)

local function digSetVisibleUnderground(t, vm)
  local d = t.data
  local p = t._p
  if d[0] == 0 then
    if p then
      local _, cy = monBase(vm, P.atk(vm))
      p.invisible = false
      p.ox = 0
      p.oy = 160 - cy
    end
    d[0] = d[0] + 1
  else
    P.DestroyAnimVisualTask(t)
  end
end

local function digRiseUp(t, vm)
  local d = t.data
  local p = t._p
  local k = d[0]
  if k == 0 then
    local y = P.yWithElevation(vm, P.atk(vm))
    d[14] = y - 32
    d[15] = y + 32
    d[0] = d[0] + 1
  elseif k == 1 then
    if p then t._rows = digClip(p, 0, d[15], true) end
    d[0] = d[0] + 1
  elseif k == 2 then
    if p then p.oy = 96 end
    d[0] = d[0] + 1
  elseif k == 3 then
    if p then
      p.oy = p.oy - 8
      if p.oy == 0 then
        if p.hShift == t._rows then p.hShift = nil end
        d[0] = d[0] + 1
      end
    else
      d[0] = d[0] + 1
    end
  elseif k == 4 then
    P.DestroyAnimVisualTask(t)
  end
end

-- pokefirered/src/battle_anim_ground.c:375
T.DigUpMovement = P.task(function(t, vm)
  t._p = P.monPresent(P.atk(vm))
  if t.ga[0] == 0 then
    t.fn = digSetVisibleUnderground
  else
    t.fn = digRiseUp
  end
  t.fn(t, vm)
end)

local GHOST_BLUE = 23 * 32 + 25 * 1024
local GHOST_WHITE = 31 + 31 * 32 + 29 * 1024

local function ghostFaceDraw(t, vm)
  local g = t._ghost
  if not (g and g.face) then return end
  local eva, evb = 16, 0
  if g.bldTarget == 2 then eva, evb = g.eva, g.evb end
  if eva <= 0 then return end
  AnimPal.drawBg("SCARY_FACE_PLAYER", "bg2", 0, 0, { eva = eva, evb = evb })
end

local function ghostApply(t)
  local g = t._ghost
  local p = g.p
  if not p then return end
  P.monBlend(p, g.monCoeff or 0, g.monColor or GHOST_BLUE)
  if g.bldTarget == 1 then
    p.alpha = math.max(0, math.min(16, g.eva)) / 16
  else
    p.alpha = 1
  end
  p.hShift = g.wave and g.waveRows or nil
end

local function ghostSetBld(t, target, eva, evb)
  local g = t._ghost
  g.bldTarget, g.eva, g.evb = target, eva, evb
end

local function ghostStep3(t, vm)
  local d = t.data
  local g = t._ghost
  local k = d[15]
  if k == 0 then
    g.wave = nil
    g.monCoeff, g.monColor = 12, GHOST_BLUE
  elseif k == 1 then
    ghostSetBld(t, 2, 16, 0)
    d[2] = 16
    d[3] = 0
  elseif k == 2 then
    d[2] = d[2] - 1
    d[3] = d[3] + 1
    ghostSetBld(t, 2, d[2], d[3])
    if d[3] <= 15 then
      ghostApply(t)
      return
    end
    t.z = P.bgZ(2)
  elseif k == 3 then
    g.face = false
    d[1] = 12
  elseif k == 4 then
    g.monCoeff, g.monColor = d[1], GHOST_BLUE
    if d[1] ~= 0 then
      d[1] = d[1] - 1
      ghostApply(t)
      return
    end
    d[1] = 0
    ghostSetBld(t, 2, 0, 16)
  elseif k == 5 then
    g.monCoeff = 0
    ghostSetBld(t, 0, 16, 0)
    ghostApply(t)
    if g.p then
      g.p.alpha = 1
      g.p.hShift = nil
      P.monBlend(g.p, 0, 0)
    end
    t.draw = nil
    P.DestroyAnimVisualTask(t)
    return
  end
  ghostApply(t)
  d[15] = d[15] + 1
end

local function ghostStep2(t, vm)
  local d = t.data
  local g = t._ghost
  d[1] = d[1] + 1
  d[8] = band(d[1], 1)
  if d[8] == 0 then d[2] = P.div(P.SINE[d[1] + 1], 18) end
  if d[8] == 1 then d[3] = 16 - P.div(P.SINE[d[1] + 1], 18) end
  ghostSetBld(t, 1, d[2], d[3])
  if g.wave then g.waveRows = P.hShiftFromHofs(g.wave:step(0)) end
  ghostApply(t)
  if d[1] == 128 then
    d[15] = 0
    t.fn = ghostStep3
    ghostStep3(t, vm)
  end
end

local function ghostStep1(t, vm)
  local d = t.data
  local g = t._ghost
  local k = d[15]
  if k == 0 then
    t.z = P.bgZ(1)
    d[1] = 0
    d[2] = 0
    d[3] = 16
  elseif k == 1 then
    d[1] = d[1] + 1
    if band(d[1], 1) ~= 0 then return end
    g.monCoeff, g.monColor = d[2], GHOST_BLUE
    ghostApply(t)
    if d[2] <= 11 then
      d[2] = d[2] + 1
      return
    end
    d[1] = 0
    d[2] = 0
    ghostSetBld(t, 2, 0, 16)
  elseif k == 2 then
    AnimPal.bgLoad("bg2", "SCARY_FACE_PLAYER")
  elseif k == 3 then
    g.face = true
    t.draw = ghostFaceDraw
  elseif k == 4 then
    d[1] = d[1] + 1
    if band(d[1], 1) ~= 0 then return end
    d[2] = d[2] + 1
    d[3] = d[3] - 1
    ghostSetBld(t, 2, d[2], d[3])
    if d[3] ~= 0 then return end
    d[1] = 0
    d[2] = 0
    d[3] = 16
    ghostSetBld(t, 1, 0, 16)
    t.z = P.bgZ(2)
  elseif k == 5 then
    g.hidden = true
  elseif k == 6 then
    local _, cy = P.monCenter(vm, P.atk(vm))
    local y = math.floor(cy) - 32
    if y < 0 then y = 0 end
    g.wave = P.Wave(y, y + 64, 4, 8, 0)
  elseif k == 7 then
    g.monCoeff, g.monColor = 12, GHOST_WHITE
    g.hidden = false
    ghostApply(t)
    t.fn = ghostStep2
    d[15] = 0
    return
  end
  ghostApply(t)
  d[15] = d[15] + 1
end

-- pokefirered/src/battle_anim_ghost.c:1267
T.GhostGetOut = P.task(function(t, vm)
  t._ghost = { p = P.monPresent(P.atk(vm)), bldTarget = 0, eva = 16, evb = 0, monCoeff = 0 }
  t.data[15] = 0
  t.fn = ghostStep1
  ghostStep1(t, vm)
end)

local ICE_CUBE_SUBSPRITES = {
  { -16, -16, 64, 64, 0 },
  { -16, 48, 64, 32, 64 },
  { 48, -16, 32, 64, 96 },
  { 48, 48, 32, 32, 128 },
}

local function iceCubeDraw(t, vm)
  local c = t._cube
  if not (c and c.visible and love and love.graphics) then return end
  local pack = vm and vm._pack
  local info = pack and pack.tags and pack.tags.ICE_CUBE
  local img = info and info.image
  if not img then return end
  local tw = math.max(1, math.floor(img:getWidth() / 8))
  local iw, ih = img:getDimensions()
  local draw = AnimPal.begin({ tag = "ICE_CUBE" }, img) or img
  love.graphics.setColor(1, 1, 1, math.max(0, math.min(16, c.eva)) / 16)
  c.quads = c.quads or {}
  for _, ss in ipairs(ICE_CUBE_SUBSPRITES) do
    local cols, rows = ss[3] / 8, ss[4] / 8
    for r = 0, rows - 1 do
      for col = 0, cols - 1 do
        local tile = ss[5] + r * cols + col
        local q = c.quads[tile]
        if not q then
          q = love.graphics.newQuad((tile % tw) * 8, math.floor(tile / tw) * 8, 8, 8, iw, ih)
          c.quads[tile] = q
        end
        love.graphics.draw(draw, q, c.x + ss[1] + col * 8, c.y + ss[2] + r * 8)
      end
    end
  end
  if draw ~= img then AnimPal.finish() end
  love.graphics.setColor(1, 1, 1, 1)
end

local function iceCubeStep4(t, vm)
  local d = t.data
  d[1] = d[1] + 1
  if d[1] == 37 then
    t._cube.visible = false
  elseif d[1] == 39 then
    t.draw = nil
    P.DestroyAnimVisualTask(t)
  end
end

local function iceCubeStep3(t, vm)
  local d = t.data
  d[1] = d[1] - 1
  if d[1] == -1 then
    t.fn = iceCubeStep4
    d[1] = 0
  else
    t._cube.eva = d[1]
  end
end

local function iceCubeStep2(t, vm)
  local d = t.data
  local old = d[1]
  d[1] = d[1] + 1
  if old > 13 then
    d[2] = d[2] + 1
    if d[2] == 3 then
      local f = AnimPal.writeFaded("ICE_CUBE")
      if f then
        local temp = f[13]
        f[13] = f[14]
        f[14] = f[15]
        f[15] = temp
      end
      d[2] = 0
      d[3] = d[3] + 1
      if d[3] == 3 then
        d[3] = 0
        d[1] = 0
        d[4] = d[4] + 1
        if d[4] == 2 then
          d[1] = 9
          t.fn = iceCubeStep3
        end
      end
    end
  end
end

local function iceCubeStep1(t, vm)
  local d = t.data
  d[1] = d[1] + 1
  if d[1] == 10 then
    t.fn = iceCubeStep2
    d[1] = 0
  else
    t._cube.eva = d[1]
  end
end

-- pokefirered/src/battle_anim_status_effects.c:350
T.FrozenIceCube = P.task(function(t, vm)
  local side = P.tgt(vm)
  local x = P.coord(vm, side, P.COORD_X_2) - 32
  local y = P.coord(vm, side, P.COORD_Y_PIC) - 36
  t._cube = { x = x, y = y, eva = 0, visible = true }
  t.z = 295
  t.draw = iceCubeDraw
  t.fn = iceCubeStep1
end)

return T
