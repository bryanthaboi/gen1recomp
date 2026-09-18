-- Gen 3 (FireRed) battle transition orchestrator & visual effects.
-- Replicates pret battle_transition.c and battle_setup.c.

local Audio = require("src.core.game3.audio")
local Trig = require("src.core.game3.trig")
local Pal = require("src.core.game3.pal_fade")
local bit = require("bit")

local band, bor, bxor = bit.band, bit.bor, bit.bxor
local lshift, rshift, arshift = bit.lshift, bit.rshift, bit.arshift
local floor = math.floor
local SINE = Trig.SINE

local BattleTransition = {}

local ID = {
  BLUR = 0,
  SWIRL = 1,
  SHUFFLE = 2,
  BIG_POKEBALL = 3,
  POKEBALLS_TRAIL = 4,
  CLOCKWISE_WIPE = 5,
  RIPPLE = 6,
  WAVE = 7,
  SLICE = 8,
  WHITE_BARS_FADE = 9,
  GRID_SQUARES = 10,
  ANGLED_WIPES = 11,
  LORELEI = 12,
  BRUNO = 13,
  AGATHA = 14,
  LANCE = 15,
  BLUE = 16,
  SPIRAL = 17,
}
BattleTransition.ID = ID

local TERRAIN = {
  NORMAL = 0,
  CAVE = 1,
  FLASH = 2,
  WATER = 3,
}
BattleTransition.TERRAIN = TERRAIN

-- src/battle_setup.c:87
local TABLE_WILD = {
  [TERRAIN.NORMAL] = { ID.SLICE, ID.WHITE_BARS_FADE },
  [TERRAIN.CAVE]   = { ID.CLOCKWISE_WIPE, ID.GRID_SQUARES },
  [TERRAIN.FLASH]  = { ID.BLUR, ID.GRID_SQUARES },
  [TERRAIN.WATER]  = { ID.WAVE, ID.RIPPLE },
}

-- src/battle_setup.c:95
local TABLE_TRAINER = {
  [TERRAIN.NORMAL] = { ID.POKEBALLS_TRAIL, ID.ANGLED_WIPES },
  [TERRAIN.CAVE]   = { ID.SHUFFLE, ID.BIG_POKEBALL },
  [TERRAIN.FLASH]  = { ID.BLUR, ID.GRID_SQUARES },
  [TERRAIN.WATER]  = { ID.SWIRL, ID.RIPPLE },
}

local MUGSHOT_BY_ID = {
  [ID.LORELEI] = "lorelei",
  [ID.BRUNO]   = "bruno",
  [ID.AGATHA]  = "agatha",
  [ID.LANCE]   = "lance",
  [ID.BLUE]    = "blue",
}

BattleTransition._active = false
BattleTransition._phase = "idle"
BattleTransition._transitionId = ID.SLICE
BattleTransition._opts = {}
BattleTransition._doneCb = nil
BattleTransition._frame = 0
BattleTransition._fx = nil
BattleTransition._pal = nil
BattleTransition._intro = nil
BattleTransition._worldDrawn = false

local function getChrome()
  local ok, Chrome = pcall(require, "src.ui.game3.battle_transition_chrome")
  if ok and Chrome then return Chrome end
  return nil
end

local function getTrainerPic()
  local ok, TP = pcall(require, "src.core.game3.trainer_pic")
  if ok and TP then return TP end
  return nil
end

--------------------------------------------------------------------------------
-- Transition Selection (battle_setup.c parity)
--------------------------------------------------------------------------------

function BattleTransition.getTerrainByMap(opts)
  opts = opts or {}
  if opts.flash or opts.flashLevel and opts.flashLevel > 0 then
    return TERRAIN.FLASH
  end
  if opts.surfing or opts.isWater or opts.mapKind == "water" or opts.mapType == 4 or opts.mapType == 5 then
    return TERRAIN.WATER
  end
  if opts.isCave or opts.mapKind == "cave" or opts.mapKind == "dungeon" or opts.mapType == 3 then
    return TERRAIN.CAVE
  end
  return TERRAIN.NORMAL
end

function BattleTransition.pickWild(opts)
  opts = opts or {}
  local terrain = opts.terrain or BattleTransition.getTerrainByMap(opts)
  local tableEntry = TABLE_WILD[terrain] or TABLE_WILD[TERRAIN.NORMAL]
  local playerLv = tonumber(opts.playerLevel) or 5
  local enemyLv = tonumber(opts.enemyLevel) or 3
  if enemyLv < playerLv then
    return tableEntry[1]
  else
    return tableEntry[2]
  end
end

function BattleTransition.pickTrainer(opts)
  opts = opts or {}
  local tid = tonumber(opts.trainerId) or 0
  local tClass = opts.trainerClass

  if tClass == "ELITE_FOUR" or tClass == 57 then
    if tid == 412 or tid == 413 or opts.isLorelei then return ID.LORELEI end
    if tid == 414 or tid == 415 or opts.isBruno then return ID.BRUNO end
    if tid == 416 or tid == 417 or opts.isAgatha then return ID.AGATHA end
    if tid == 418 or tid == 419 or opts.isLance then return ID.LANCE end
    return ID.BLUE
  end
  if tClass == "CHAMPION" or tClass == "RIVAL" or tClass == 58 or opts.isRival or opts.isChampion then
    return ID.BLUE
  end
  if opts.isLorelei then return ID.LORELEI end
  if opts.isBruno then return ID.BRUNO end
  if opts.isAgatha then return ID.AGATHA end
  if opts.isLance then return ID.LANCE end
  if opts.isBlue then return ID.BLUE end

  local terrain = opts.terrain or BattleTransition.getTerrainByMap(opts)
  local tableEntry = TABLE_TRAINER[terrain] or TABLE_TRAINER[TERRAIN.NORMAL]
  local playerLv = tonumber(opts.playerLevel) or 5
  local enemyLv = tonumber(opts.enemyLevel) or 3
  if enemyLv < playerLv then
    return tableEntry[1]
  else
    return tableEntry[2]
  end
end

function BattleTransition.pick(opts)
  opts = opts or {}
  if opts.transitionId then return opts.transitionId end
  if opts.wild then
    return BattleTransition.pickWild(opts)
  else
    return BattleTransition.pickTrainer(opts)
  end
end

local DW, DH = 240, 160
local GRAY = { 11, 11, 11 }

local function s16(v)
  v = band(v, 0xFFFF)
  if v >= 0x8000 then v = v - 0x10000 end
  return v
end
local function u16(v) return band(v, 0xFFFF) end
local function u8(v) return band(v, 0xFF) end

-- src/trig.c:514
local function Sin(i, a) return s16(arshift(a * SINE[band(i, 0xFF) + 1], 8)) end
local function Cos(i, a) return s16(arshift(a * SINE[band(i + 64, 0xFF) + 1], 8)) end

local function WIN_RANGE(a, b) return u16(bor(lshift(a, 8), b)) end

local function winH(v)
  v = u16(v or 0)
  local l, r = rshift(v, 8), band(v, 0xFF)
  if r > DW or l > r then r = DW end
  if l >= r then return nil end
  return l, r
end

local function winV(v)
  v = u16(v or 0)
  local t, b = rshift(v, 8), band(v, 0xFF)
  if b > DH or t > b then b = DH end
  return t, b
end

-- src/battle_transition.c:2952
local function initBlackWipe(d, sx, sy, ex, ey, stx, sty)
  d.startX, d.startY = sx, sy
  d.currX, d.currY = sx, sy
  d.endX, d.endY = ex, ey
  d.xMove, d.yMove = stx, sty
  d.xDist = ex - sx
  if d.xDist < 0 then
    d.xDist = -d.xDist
    d.xMove = -stx
  end
  d.yDist = ey - sy
  if d.yDist < 0 then
    d.yDist = -d.yDist
    d.yMove = -sty
  end
  d.temp = 0
end

-- src/battle_transition.c:2979
local function updateBlackWipe(d, xExact, yExact)
  if d.xDist > d.yDist then
    d.currX = d.currX + d.xMove
    d.temp = d.temp + d.yDist
    if d.temp > d.xDist then
      d.currY = d.currY + d.yMove
      d.temp = d.temp - d.xDist
    end
  else
    d.currY = d.currY + d.yMove
    d.temp = d.temp + d.xDist
    if d.temp > d.yDist then
      d.currX = d.currX + d.xMove
      d.temp = d.temp - d.yDist
    end
  end
  local n = 0
  if (d.xMove > 0 and d.currX >= d.endX) or (d.xMove < 0 and d.currX <= d.endX) then
    n = n + 1
    if xExact then d.currX = d.endX end
  end
  if (d.yMove > 0 and d.currY >= d.endY) or (d.yMove < 0 and d.currY <= d.endY) then
    n = n + 1
    if yExact then d.currY = d.endY end
  end
  return n == 2
end

-- src/battle_transition.c:2903
local function setCircularMask(buf, x, y, radius)
  for i = 0, DH - 1 do buf[i] = 0x0A0A end
  for i = 0, 63 do
    local sinR = Sin(i, radius)
    local cosR = Cos(i, radius)
    local leftX = x - sinR
    local winVal = x + sinR
    local topY = y - cosR
    local bottomY = y + cosR
    if leftX < 0 then leftX = 0 end
    if winVal > DW then winVal = DW end
    if topY < 0 then topY = 0 end
    if bottomY > DH - 1 then bottomY = DH - 1 end
    winVal = bor(winVal, lshift(leftX, 8))
    buf[topY] = winVal
    buf[bottomY] = winVal
    cosR = Cos(i + 1, radius)
    local nextTop = y - cosR
    local nextBottom = y + cosR
    if nextTop < 0 then nextTop = 0 end
    if nextBottom > DH - 1 then nextBottom = DH - 1 end
    while topY > nextTop do topY = topY - 1; buf[topY] = winVal end
    while topY < nextTop do topY = topY + 1; buf[topY] = winVal end
    while bottomY > nextBottom do bottomY = bottomY - 1; buf[bottomY] = winVal end
    while bottomY < nextBottom do bottomY = bottomY + 1; buf[bottomY] = winVal end
  end
end

local function fadeScreenBlack(fx)
  fx.pal:blend(Pal.ALL, 16, Pal.BLACK)
end

local function copyBuf(dst, src, n, off)
  off = off or 0
  for i = off, off + n - 1 do dst[i] = src[i] end
end

local DEF = {}

-- src/battle_transition.c:723
DEF[ID.BLUR] = {
  funcs = {
    function(fx)
      fx.mosaic = 0
      fx.state = 1
      return true
    end,
    function(fx)
      local t = fx.t
      if t.delay ~= 0 then
        t.delay = t.delay - 1
      else
        t.delay = 2
        t.counter = t.counter + 1
        if t.counter == 10 then
          fx.pal:beginFade(Pal.ALL, -1, 0, 16, Pal.BLACK)
        end
        fx.mosaic = band(t.counter, 0xF)
        if t.counter > 14 then fx.state = 2 end
      end
      return false
    end,
    function(fx)
      if not fx.pal:fadeActive() then fx.done = true end
      return false
    end,
  },
  init = function(fx) fx.t.delay, fx.t.counter = 0, 0 end,
  redraw = true,
}

-- src/battle_transition.c:773
DEF[ID.SWIRL] = {
  funcs = {
    function(fx)
      fx.pal:beginFade(Pal.ALL, 4, 0, 16, Pal.BLACK)
      fx.wave1 = { idx = 0, amp = 0 }
      fx.state = 1
      return false
    end,
    function(fx)
      local t = fx.t
      fx.T.vblankDma = false
      t.sinIndex = s16(t.sinIndex + 4)
      t.amp = s16(t.amp + 8)
      fx.wave0 = { idx = t.sinIndex, amp = t.amp }
      if not fx.pal:fadeActive() then fx.done = true end
      fx.T.vblankDma = true
      return false
    end,
  },
  init = function(fx) fx.t.sinIndex, fx.t.amp = 0, 0 end,
  vblank = function(fx)
    if fx.T.vblankDma and fx.wave0 then fx.wave1 = fx.wave0 end
  end,
  shift = function(fx, y)
    local w = fx.wave1
    if not w then return 0, 0 end
    return Sin(w.idx + 2 * y, w.amp), 0
  end,
  redraw = true,
}

-- src/battle_transition.c:829
DEF[ID.SHUFFLE] = {
  funcs = {
    function(fx)
      fx.pal:beginFade(Pal.ALL, 4, 0, 16, Pal.BLACK)
      fx.sh1 = { sinVal = 0, amp = 0 }
      fx.state = 1
      return false
    end,
    function(fx)
      local t = fx.t
      fx.T.vblankDma = false
      local sinVal = u16(t.sinVal)
      local amp = u16(arshift(t.amp, 8))
      t.sinVal = s16(t.sinVal + 4224)
      t.amp = s16(t.amp + 384)
      fx.sh0 = { sinVal = sinVal, amp = s16(amp) }
      if not fx.pal:fadeActive() then fx.done = true end
      fx.T.vblankDma = true
      return false
    end,
  },
  init = function(fx) fx.t.sinVal, fx.t.amp = 0, 0 end,
  vblank = function(fx)
    if fx.T.vblankDma and fx.sh0 then fx.sh1 = fx.sh0 end
  end,
  shift = function(fx, y)
    local s = fx.sh1
    if not s then return 0, 0 end
    return 0, Sin(rshift(u16(s.sinVal + 4224 * y), 8), s.amp)
  end,
  redraw = true,
}

-- src/battle_transition.c:906
local function bigBlend(t, dec)
  local fire
  if t.blendDelay == 0 then
    fire = true
  else
    t.blendDelay = t.blendDelay - 1
    fire = t.blendDelay == 0
  end
  if fire then
    if dec then
      t.evb = t.evb - 1
      t.blendDelay = 2
    else
      t.eva = t.eva + 1
      t.blendDelay = 1
    end
  end
end

local function bigAmp(t)
  if t.amp > 0 then
    t.sinIndex = s16(t.sinIndex + 12)
    t.amp = s16(t.amp - 384)
  else
    t.amp = 0
  end
end

DEF[ID.BIG_POKEBALL] = {
  funcs = {
    function(fx)
      local t = fx.t
      t.evb, t.eva, t.sinIndex, t.amp, t.blendDelay = 16, 0, 0, 0x4000, 0
      fx.T.bldAlpha = { 0, 16 }
      fx.hofs1 = { const = 240 }
      fx.state = 1
      return false
    end,
    function(fx)
      fx.pattern = true
      fx.state = 2
      return true
    end,
    function(fx)
      local t = fx.t
      fx.T.vblankDma = false
      bigBlend(t, false)
      fx.T.bldAlpha = { t.eva, t.evb }
      if t.eva > 15 then fx.state = 3 end
      t.sinIndex = s16(t.sinIndex + 12)
      t.amp = s16(t.amp - 384)
      fx.hofs0 = { idx = t.sinIndex, amp = arshift(t.amp, 8) }
      fx.T.vblankDma = true
      return false
    end,
    function(fx)
      local t = fx.t
      fx.T.vblankDma = false
      bigBlend(t, true)
      fx.T.bldAlpha = { t.eva, t.evb }
      if t.evb == 0 then fx.state = 4 end
      bigAmp(t)
      fx.hofs0 = { idx = t.sinIndex, amp = arshift(t.amp, 8) }
      fx.T.vblankDma = true
      return false
    end,
    function(fx)
      local t = fx.t
      fx.T.vblankDma = false
      bigAmp(t)
      fx.hofs0 = { idx = t.sinIndex, amp = arshift(t.amp, 8) }
      if t.amp <= 0 then
        fx.state = 5
        t.radius = DH
        t.radiusDelta = 256
        t.vblankSet = false
      end
      fx.T.vblankDma = true
      return false
    end,
    function(fx)
      local t = fx.t
      fx.T.vblankDma = false
      if t.radiusDelta < 2048 then t.radiusDelta = t.radiusDelta + 256 end
      if t.radius ~= 0 then
        t.radius = t.radius - arshift(t.radiusDelta, 8)
        if t.radius < 0 then t.radius = 0 end
      end
      setCircularMask(fx.buf0, DW / 2, DH / 2, t.radius)
      if t.radius == 0 then
        fadeScreenBlack(fx)
        fx.done = true
      end
      if not t.vblankSet then
        t.vblankSet = true
        fx.maskMode = true
      end
      fx.T.vblankDma = true
      return false
    end,
  },
  vblank = function(fx)
    local T = fx.T
    fx.bldAlpha1 = T.bldAlpha
    if fx.maskMode then
      if not fx.mask1 then
        fx.mask1 = {}
        fx.hofs1 = { const = 0 }
      end
      if T.vblankDma then copyBuf(fx.mask1, fx.buf0, DH) end
    elseif T.vblankDma and fx.hofs0 then
      fx.hofs1 = fx.hofs0
    end
  end,
  winSpans = function(fx, y, out)
    if not fx.mask1 then return 0 end
    local l, r = winH(fx.mask1[y])
    if not l then
      out[1], out[2] = 0, DW
      return 1
    end
    local n = 0
    if l > 0 then n = n + 1; out[2 * n - 1], out[2 * n] = 0, l end
    if r < DW then n = n + 1; out[2 * n - 1], out[2 * n] = r, DW end
    return n
  end,
}

-- src/battle_transition.c:1099
local TRAIL_START_X = { [0] = -16, [1] = DW + 16 }
local TRAIL_DELAYS = { 0, 16, 32, 8, 24 }
local TRAIL_SPEEDS = { [0] = 8, [1] = -8 }
local TRAIL_LANE_MIN, TRAIL_LANE_MAX = -16, 20

local function trailRandom()
  local ok, Rng = pcall(require, "src.core.game3.rng")
  if ok and Rng and Rng.Random then return Rng.Random() end
  return math.random(0, 0xFFFF)
end

DEF[ID.POKEBALLS_TRAIL] = {
  funcs = {
    function(fx)
      fx.trail = {}
      fx.state = 1
      return false
    end,
    function(fx)
      local side0 = band(trailRandom(), 1)
      for lane = TRAIL_LANE_MIN, TRAIL_LANE_MAX do
        local side = bxor(side0, band(lane, 1))
        fx.sprites[#fx.sprites + 1] = {
          x = TRAIL_START_X[side],
          y = lane * 32 + 16,
          lane = lane,
          side = side,
          delay = TRAIL_DELAYS[(lane % 5) + 1],
          prevX = -1,
          rot = 0,
          real = lane >= 0 and lane < 5,
        }
      end
      fx.state = 2
      return false
    end,
    function(fx)
      for _, s in ipairs(fx.sprites) do
        if s.real and not s.dead then return false end
      end
      fadeScreenBlack(fx)
      fx.done = true
      return false
    end,
  },
  sprite = function(fx, s)
    s.rot = s.rot + (s.side == 0 and -4 or 4)
    if s.delay ~= 0 then
      s.delay = s.delay - 1
      return
    end
    if s.x >= 0 and s.x <= DW then
      local posX = arshift(s.x, 3)
      if posX ~= s.prevX then
        s.prevX = posX
        local cols = fx.trail[s.lane]
        if not cols then
          cols = {}
          fx.trail[s.lane] = cols
        end
        cols[posX] = true
      end
    end
    s.x = s.x + TRAIL_SPEEDS[s.side]
    if s.x < -15 or s.x > DW + 15 then s.dead = true end
  end,
}

-- src/battle_transition.c:1207
DEF[ID.CLOCKWISE_WIPE] = {
  funcs = {
    function(fx)
      for i = 0, DH - 1 do fx.buf1[i] = WIN_RANGE(DW + 3, DW + 4) end
      fx.T.endX = DW / 2
      fx.state = 1
      return true
    end,
    function(fx)
      local T, b = fx.T, fx.buf0
      T.vblankDma = false
      initBlackWipe(T, DW / 2, DH / 2, T.endX, -1, 1, 1)
      repeat
        b[T.currY] = WIN_RANGE(DW / 2, T.currX + 1)
      until updateBlackWipe(T, true, true)
      T.endX = T.endX + 32
      if T.endX >= DW then
        T.endY = 0
        fx.state = 2
      end
      T.vblankDma = true
      return false
    end,
    function(fx)
      local T, b = fx.T, fx.buf0
      local start, stop
      local finished = false
      T.vblankDma = false
      initBlackWipe(T, DW / 2, DH / 2, DW, T.endY, 1, 1)
      while true do
        start = DW / 2
        stop = T.currX + 1
        if T.endY >= DH / 2 then
          start = T.currX
          stop = DW
        end
        b[T.currY] = WIN_RANGE(start, stop)
        if finished then break end
        finished = updateBlackWipe(T, true, true)
      end
      T.endY = T.endY + 16
      if T.endY >= DH then
        T.endX = DW
        fx.state = 3
      else
        while T.currY < T.endY do
          T.currY = T.currY + 1
          b[T.currY] = WIN_RANGE(start, stop)
        end
      end
      T.vblankDma = true
      return false
    end,
    function(fx)
      local T, b = fx.T, fx.buf0
      T.vblankDma = false
      initBlackWipe(T, DW / 2, DH / 2, T.endX, DH, 1, 1)
      repeat
        b[T.currY] = u16(bor(lshift(T.currX, 8), DW))
      until updateBlackWipe(T, true, true)
      T.endX = T.endX - 32
      if T.endX <= 0 then
        T.endY = DH
        fx.state = 4
      end
      T.vblankDma = true
      return false
    end,
    function(fx)
      local T, b = fx.T, fx.buf0
      local start, stop
      local finished = false
      T.vblankDma = false
      initBlackWipe(T, DW / 2, DH / 2, 0, T.endY, 1, 1)
      while true do
        stop = band(b[T.currY] or 0, 0xFF)
        start = T.currX
        if T.endY <= DH / 2 then
          start = DW / 2
          stop = T.currX
        end
        b[T.currY] = WIN_RANGE(start, stop)
        if finished then break end
        finished = updateBlackWipe(T, true, true)
      end
      T.endY = T.endY - 16
      if T.endY <= 0 then
        T.endX = 0
        fx.state = 5
      else
        while T.currY > T.endY do
          T.currY = T.currY - 1
          b[T.currY] = WIN_RANGE(start, stop)
        end
      end
      T.vblankDma = true
      return false
    end,
    function(fx)
      local T, b = fx.T, fx.buf0
      T.vblankDma = false
      initBlackWipe(T, 120, 80, T.endX, 0, 1, 1)
      repeat
        local start, stop = DW / 2, T.currX
        if T.currX >= 120 then
          start, stop = 0, DW
        end
        b[T.currY] = WIN_RANGE(start, stop)
      until updateBlackWipe(T, true, true)
      T.endX = T.endX + 32
      if T.currX > DW / 2 then fx.state = 6 end
      T.vblankDma = true
      return false
    end,
    function(fx)
      fadeScreenBlack(fx)
      fx.done = true
      return false
    end,
  },
  vblank = function(fx)
    if fx.T.vblankDma then copyBuf(fx.buf1, fx.buf0, DH) end
  end,
  winSpans = function(fx, y, out)
    local l, r = winH(fx.buf1[y])
    if not l then return 0 end
    out[1], out[2] = l, r
    return 1
  end,
}

-- src/battle_transition.c:1412
DEF[ID.RIPPLE] = {
  funcs = {
    function(fx)
      fx.rp1 = { sinVal = 0, amp = 0 }
      fx.state = 1
      return true
    end,
    function(fx)
      local t = fx.t
      fx.T.vblankDma = false
      local amp = arshift(t.amp, 8)
      local sinVal = u16(t.sinVal)
      t.sinVal = s16(t.sinVal + 0x400)
      if t.amp <= 0x1FFF then t.amp = t.amp + 384 end
      fx.rp0 = { sinVal = sinVal, amp = amp }
      t.timer = t.timer + 1
      if t.timer == 41 then
        t.fadeStarted = true
        fx.pal:beginFade(Pal.ALL, -8, 0, 16, Pal.BLACK)
      end
      if t.fadeStarted and not fx.pal:fadeActive() then fx.done = true end
      fx.T.vblankDma = true
      return false
    end,
  },
  init = function(fx) fx.t.sinVal, fx.t.amp, fx.t.timer = 0, 0, 0 end,
  vblank = function(fx)
    if fx.T.vblankDma and fx.rp0 then fx.rp1 = fx.rp0 end
  end,
  shift = function(fx, y)
    local s = fx.rp1
    if not s then return 0, 0 end
    return 0, Sin(rshift(u16(s.sinVal + 384 * y), 8), s.amp)
  end,
  redraw = true,
}

-- src/battle_transition.c:1489
local function waveX(w, y)
  local x = w.x + Sin(u8(w.idx + 4 * y), 40)
  if x < 0 then x = 0 end
  if x > DW then x = DW end
  return x
end

DEF[ID.WAVE] = {
  funcs = {
    function(fx)
      fx.state = 1
      return true
    end,
    function(fx)
      local t = fx.t
      fx.T.vblankDma = false
      local sinIndex = u8(t.sinIndex)
      t.sinIndex = s16(t.sinIndex + 16)
      t.x = t.x + 8
      local w = { x = t.x, idx = sinIndex }
      local finished = true
      for i = 0, DH - 1 do
        if waveX(w, i) < DW then
          finished = false
          break
        end
      end
      fx.wv0 = w
      if finished then fx.state = 2 end
      fx.T.vblankDma = true
      return false
    end,
    function(fx)
      fadeScreenBlack(fx)
      fx.done = true
      return false
    end,
  },
  init = function(fx) fx.t.sinIndex, fx.t.x = 0, 0 end,
  vblank = function(fx)
    if fx.T.vblankDma and fx.wv0 then fx.wv1 = fx.wv0 end
  end,
  rowSpans = function(fx, y, R, out)
    local w = fx.wv1
    if not w then return 0 end
    local x = waveX(w, y)
    if x <= 0 then return 0 end
    out[1], out[2] = R.X0, R.hmapR(x)
    return 1
  end,
}

-- src/battle_transition.c:2293
DEF[ID.SLICE] = {
  funcs = {
    function(fx)
      fx.t.speed = 256
      fx.t.accel = 1
      fx.sl1 = 0
      fx.state = 1
      return true
    end,
    function(fx)
      local t = fx.t
      fx.T.vblankDma = false
      t.effectX = t.effectX + arshift(t.speed, 8)
      if t.effectX > DW then t.effectX = DW end
      if t.speed <= 0xFFF then t.speed = t.speed + t.accel end
      if t.accel < 128 then t.accel = t.accel * 2 end
      fx.sl0 = t.effectX
      if t.effectX >= DW then fx.state = 2 end
      fx.T.vblankDma = true
      return false
    end,
    function(fx)
      fadeScreenBlack(fx)
      fx.done = true
      return false
    end,
  },
  init = function(fx) fx.t.effectX = 0 end,
  vblank = function(fx)
    if fx.T.vblankDma and fx.sl0 then fx.sl1 = fx.sl0 end
  end,
  rowSpans = function(fx, y, R, out)
    local e = R.hdist(fx.sl1 or 0)
    if e <= 0 then return 0 end
    if band(y, 1) == 1 then
      out[1], out[2] = R.X1 - e, R.X1
    else
      out[1], out[2] = R.X0, R.X0 + e
    end
    return 1
  end,
  shift = function(fx, y, R)
    local e = R.hdist(fx.sl1 or 0)
    if band(y, 1) == 1 then return e, 0 end
    return -e, 0
  end,
  redraw = true,
}

-- src/battle_transition.c:2402
local NUM_WHITE_BARS = 6
local WHITE_BAR_HEIGHT = 1 + floor(DH / NUM_WHITE_BARS)
local WHITE_BAR_DELAYS = { 0, 9, 15, 6, 12, 3 }
local FADE_TARGET = 16 * 256

DEF[ID.WHITE_BARS_FADE] = {
  funcs = {
    function(fx)
      for i = 0, DH - 1 do
        fx.buf1[i] = 0
        fx.buf0[i] = 0
      end
      fx.barLevel = {}
      fx.barLevel1 = {}
      for i = 0, NUM_WHITE_BARS - 1 do
        fx.barLevel[i] = 0
        fx.barLevel1[i] = 0
      end
      fx.T.counter = 0
      fx.state = 1
      return false
    end,
    function(fx)
      local posY = 0
      local last
      for i = 0, NUM_WHITE_BARS - 1 do
        last = {
          x = DW, y = posY, bar = i, fade = 0, finished = false,
          delay = WHITE_BAR_DELAYS[i + 1], main = false,
        }
        fx.sprites[#fx.sprites + 1] = last
        posY = posY + WHITE_BAR_HEIGHT
      end
      last.main = true
      fx.state = 2
      return false
    end,
    function(fx)
      fx.T.vblankDma = false
      if fx.T.counter >= NUM_WHITE_BARS then
        fx.pal:blend(Pal.ALL, 16, Pal.WHITE)
        fx.state = 3
      end
      return false
    end,
    function(fx)
      fx.T.vblankDma = false
      fx.darkenPhase = true
      fx.T.bldY = 0
      fx.T.counter = 0
      fx.state = 4
      return false
    end,
    function(fx)
      local T = fx.T
      T.counter = T.counter + 480
      T.bldY = arshift(T.counter, 8)
      if T.bldY > 16 then
        fadeScreenBlack(fx)
        fx.done = true
      end
      return false
    end,
  },
  sprite = function(fx, s)
    local T = fx.T
    if s.delay ~= 0 then
      s.delay = s.delay - 1
      if s.main then T.vblankDma = true end
      return
    end
    local h = s.main and (WHITE_BAR_HEIGHT - 2) or WHITE_BAR_HEIGHT
    local lvl = rshift(s.fade, 8)
    for i = 0, h - 1 do fx.buf0[s.y + i] = lvl end
    fx.barLevel[s.bar] = lvl
    if s.x == 0 and s.fade == FADE_TARGET then s.finished = true end
    s.x = s.x - 24
    s.fade = s.fade + 192
    if s.x < 0 then s.x = 0 end
    if s.fade > FADE_TARGET then s.fade = FADE_TARGET end
    if s.main then T.vblankDma = true end
    if s.finished and (not s.main or T.counter > 4) then
      T.counter = T.counter + 1
      s.dead = true
    end
  end,
  vblank = function(fx)
    if fx.T.vblankDma and not fx.darkenPhase then
      copyBuf(fx.buf1, fx.buf0, DH)
      for i = 0, NUM_WHITE_BARS - 1 do fx.barLevel1[i] = fx.barLevel[i] end
    end
  end,
  post = function(fx, R, G)
    if fx.darkenPhase then
      local y = fx.T.bldY
      if y > 16 then y = 16 end
      if y > 0 then
        G.setColor(0, 0, 0, y / 16)
        G.rectangle("fill", R.X0, R.Y0, R.X1 - R.X0, R.Y1 - R.Y0)
      end
      return
    end
    if not fx.barLevel1 then return end
    R.rowBands(function(y)
      local v
      if y >= 0 and y < DH then
        v = fx.buf1[y] or 0
      else
        v = fx.barLevel1[floor(y / WHITE_BAR_HEIGHT) % NUM_WHITE_BARS] or 0
      end
      if v > 16 then v = 16 end
      return v
    end, function(v, y0, y1)
      if v > 0 then
        G.setColor(1, 1, 1, v / 16)
        G.rectangle("fill", R.X0, y0, R.X1 - R.X0, y1 - y0)
      end
    end)
  end,
}

-- src/battle_transition.c:2583
DEF[ID.GRID_SQUARES] = {
  funcs = {
    function(fx)
      fx.gridStage = 0
      fx.state = 1
      return false
    end,
    function(fx)
      local t = fx.t
      if t.delay == 0 then
        t.delay = 3
        t.stage = t.stage + 1
        fx.gridStage = t.stage
        if t.stage > 13 then
          fx.state = 2
          t.delay = 16
        end
      end
      t.delay = t.delay - 1
      return false
    end,
    function(fx)
      local t = fx.t
      t.delay = t.delay - 1
      if t.delay == 0 then
        fadeScreenBlack(fx)
        fx.done = true
      end
      return false
    end,
  },
  init = function(fx) fx.t.delay, fx.t.stage = 0, 0 end,
}

-- src/battle_transition.c:2641
local ANGLED_MOVE = {
  { 56, 0, 0, DH, 0 },
  { 104, DH, DW, 88, 1 },
  { DW, 72, 56, 0, 1 },
  { 0, 32, 144, DH, 0 },
  { 144, DH, 184, 0, 1 },
  { 56, 0, 168, DH, 0 },
  { 168, DH, 48, 0, 1 },
}
local ANGLED_END_DELAYS = { 1, 1, 1, 1, 1, 1, 0 }

DEF[ID.ANGLED_WIPES] = {
  funcs = {
    function(fx)
      for i = 0, DH - 1 do
        fx.buf0[i] = WIN_RANGE(0, DW)
        fx.buf1[i] = fx.buf0[i]
      end
      fx.state = 1
      return true
    end,
    function(fx)
      local md = ANGLED_MOVE[fx.t.wipeId + 1]
      initBlackWipe(fx.T, md[1], md[2], md[3], md[4], 1, 1)
      fx.t.dir = md[5]
      fx.state = 2
      return true
    end,
    function(fx)
      local T, b = fx.T, fx.buf0
      T.vblankDma = false
      local finished = false
      for _ = 0, 15 do
        local v = b[T.currY] or 0
        local left, right = rshift(v, 8), band(v, 0xFF)
        if fx.t.dir == 0 then
          if left < T.currX then left = T.currX end
          if left > right then left = right end
        else
          if right > T.currX then right = T.currX end
          if right <= left then right = left end
        end
        b[T.currY] = WIN_RANGE(left, right)
        if finished then
          fx.state = 3
          break
        end
        finished = updateBlackWipe(T, true, true)
      end
      T.vblankDma = true
      return false
    end,
    function(fx)
      local t = fx.t
      t.wipeId = t.wipeId + 1
      if t.wipeId < #ANGLED_MOVE then
        fx.state = 4
        t.delay = ANGLED_END_DELAYS[t.wipeId]
        return true
      end
      fadeScreenBlack(fx)
      fx.done = true
      return false
    end,
    function(fx)
      local t = fx.t
      t.delay = t.delay - 1
      if t.delay == 0 then
        fx.state = 1
        return true
      end
      return false
    end,
  },
  init = function(fx) fx.t.wipeId = 0 end,
  vblank = function(fx)
    if fx.T.vblankDma then copyBuf(fx.buf1, fx.buf0, DH) end
  end,
  winSpans = function(fx, y, out)
    local l, r = winH(fx.buf1[y])
    if not l then
      out[1], out[2] = 0, DW
      return 1
    end
    local n = 0
    if l > 0 then n = n + 1; out[2 * n - 1], out[2 * n] = 0, l end
    if r < DW then n = n + 1; out[2 * n - 1], out[2 * n] = r, DW end
    return n
  end,
}

-- src/battle_transition.c:1566
local SPIRAL_ANGLE = {
  0x0, 0x26E, 0x100, 0x69, 0x0, -0x69, -0x100, -0x266E,
  0x0, 0x26E, 0x100, 0x69, 0x0, -0x69, -0x100, -0x266E,
}

local function spiralUpdate(b, initRadius, dmax, off)
  local sinIndex = 0
  for i = DH * 2, DH * 6 - 1 do b[i] = DW / 2 end
  local x1, y1, x2, y2
  for _ = 0, dmax * 16 - 1 do
    local a1 = initRadius + rshift(sinIndex, 3)
    local a2 = a1
    if rshift(sinIndex, 3) ~= rshift(sinIndex + 1, 3) then a2 = a1 + 1 end
    y1 = DH / 2 - Sin(sinIndex, a1)
    x1 = Cos(sinIndex, a1) + DW / 2
    y2 = DH / 2 - Sin(sinIndex + 1, a2)
    x2 = Cos(sinIndex + 1, a2) + DW / 2
    if not ((y1 < 0 and y2 < 0) or (y1 > DH - 1 and y2 > DH - 1)) then
      if y1 < 0 then y1 = 0 end
      if y1 > DH - 1 then y1 = DH - 1 end
      if x1 < 0 then x1 = 0 end
      if x1 > 255 then x1 = 255 end
      if y2 < 0 then y2 = 0 end
      if y2 > DH - 1 then y2 = DH - 1 end
      if x2 < 0 then x2 = 0 end
      if x2 > 255 then x2 = 255 end
      y2 = y2 - y1
      local base = (sinIndex >= 64 and sinIndex < 192) and DH * 2 or DH * 3
      b[y1 + base] = x1
      if y2 ~= 0 then
        x2 = x2 - x1
        if x2 < -1 and x1 > 1 then
          x1 = x1 - 1
        elseif x2 > 1 and x1 < 255 then
          x1 = x1 + 1
        end
        if y2 < 0 then
          while y2 < 0 do b[y1 + y2 + base] = x1; y2 = y2 + 1 end
        else
          while y2 > 0 do b[y1 + y2 + base] = x1; y2 = y2 - 1 end
        end
      end
    end
    sinIndex = u8(sinIndex + 1)
  end

  if off ~= 0 and dmax % 4 ~= 0 then
    y1 = Sin(dmax * 16, initRadius + lshift(dmax, 1))
    local q = floor(dmax / 4)
    local ang = SPIRAL_ANGLE[dmax + 1]
    if q == 0 or q == 1 then
      if y1 > DH / 2 then y1 = DH / 2 end
      for i = y1, 1, -1 do
        x1 = arshift(i * ang, 8) + DW / 2
        if x1 >= 0 and x1 <= 255 then
          if q == 0 and b[560 - i] < x1 then
            b[560 - i] = DW / 2
          elseif b[400 - i] < x1 then
            b[400 - i] = x1
          end
        end
      end
    else
      if y1 < -(DH / 2 - 1) then y1 = -(DH / 2 - 1) end
      for i = y1, 0 do
        x1 = arshift(i * ang, 8) + DW / 2
        if x1 >= 0 and x1 <= 255 then
          if q == 2 and b[400 - i] >= x1 then
            b[400 - i] = DW / 2
          elseif b[560 - i] > x1 then
            b[560 - i] = x1
          end
        end
      end
    end
  end

  for i = 0, DH - 1 do
    b[i * 2 + off] = bor(lshift(b[i + DH * 2], 8), b[i + DH * 3])
  end
end

local function spiralWinV(d2)
  local top = 48 - d2
  if top < 0 then top = 0 end
  local bottom = d2 + 112
  if bottom > 255 then bottom = 255 end
  return u16(bor(top, bottom))
end

DEF[ID.SPIRAL] = {
  funcs = {
    function(fx)
      local T = fx.T
      T.win0V = WIN_RANGE(48, DH - 48)
      T.win1V = WIN_RANGE(16, DH - 16)
      T.counter = 0
      spiralUpdate(fx.buf1, 0, 0, 0)
      spiralUpdate(fx.buf1, 0, 0, 1)
      copyBuf(fx.buf0, fx.buf1, DH * 2)
      fx.t.d1, fx.t.d2 = 0, 0
      fx.state = 1
      return false
    end,
    function(fx)
      local T, t = fx.T, fx.t
      spiralUpdate(fx.buf1, t.d2, t.d1, 1)
      T.vblankDma = true
      t.d1 = t.d1 + 1
      if t.d1 == #SPIRAL_ANGLE + 1 then
        spiralUpdate(fx.buf1, t.d2, 16, 0)
        T.win0V = spiralWinV(t.d2)
        t.d2 = t.d2 + 32
        t.d1 = 0
        spiralUpdate(fx.buf1, t.d2, 0, 1)
        T.win1V = spiralWinV(t.d2)
        T.vblankDma = true
        if t.d2 >= DH then
          T.counter = 1
          fadeScreenBlack(fx)
        end
      end
      return false
    end,
  },
  vblank = function(fx)
    local T = fx.T
    if T.counter ~= 0 then
      fx.done = true
      return
    end
    if T.vblankDma then
      copyBuf(fx.buf0, fx.buf1, DH * 2)
      T.vblankDma = false
    end
    fx.win0V1, fx.win1V1 = T.win0V, T.win1V
  end,
  winSpans = function(fx, y, out)
    local n = 0
    local t0, b0 = winV(fx.win0V1 or 0)
    if y >= t0 and y < b0 then
      local l, r = winH(fx.buf0[y * 2])
      if l then n = n + 1; out[1], out[2] = l, r end
    end
    local t1, b1 = winV(fx.win1V1 or 0)
    if y >= t1 and y < b1 then
      local l, r = winH(fx.buf0[y * 2 + 1])
      if l then n = n + 1; out[2 * n - 1], out[2 * n] = l, r end
    end
    return n
  end,
}

-- src/battle_transition.c:1849
local MUGSHOT_PIC = { lorelei = 112, bruno = 113, agatha = 114, lance = 115, blue = 125 }
local MUGSHOT_COORDS = {
  lorelei = { -8, 0 }, bruno = { -10, 0 }, agatha = { 0, 0 }, lance = { -32, 0 }, blue = { 0, 0 },
}
local PIC_SLIDE_SPEEDS = { [0] = 12, [1] = -12 }
local PIC_SLIDE_ACCELS = { [0] = -1, [1] = 1 }

local PIC_FUNCS = {
  [0] = function() return false end,
  [1] = function(s)
    s.state = 2
    s.speed = PIC_SLIDE_SPEEDS[s.dir]
    s.accel = PIC_SLIDE_ACCELS[s.dir]
    return true
  end,
  [2] = function(s)
    s.x = s.x + s.speed
    if s.dir == 1 and s.x < DW - 107 then
      s.state = 3
    elseif s.dir == 0 and s.x > 103 then
      s.state = 3
    end
    return false
  end,
  [3] = function(s)
    s.speed = s.speed + s.accel
    s.x = s.x + s.speed
    if s.speed == 0 then
      s.state = 4
      s.accel = -s.accel
      s.done = true
    end
    return false
  end,
  [4] = function() return false end,
  [5] = function(s)
    s.speed = s.speed + s.accel
    s.x = s.x + s.speed
    if s.x < -31 or s.x > DW + 31 then s.state = 6 end
    return false
  end,
  [6] = function() return false end,
}

local function mugHofs(T)
  T.hofsOpp = s16(T.hofsOpp - 8)
  T.hofsPl = s16(T.hofsPl + 8)
end

local MUGSHOT_DEF = {
  funcs = {
    function(fx)
      local t, T = fx.t, fx.T
      local key = fx.mugKey
      local c = MUGSHOT_COORDS[key] or { 0, 0 }
      fx.opp = { x = c[1] - 32, y = c[2] + 42, state = 0, dir = 0, speed = 0, accel = 0,
        pic = MUGSHOT_PIC[key] or 125 }
      fx.player = { x = DW + 32, y = 106, state = 0, dir = 0, speed = 0, accel = 0,
        pic = fx.female and 136 or 135, flip = true }
      fx.sprites[1] = fx.opp
      fx.sprites[2] = fx.player
      t.sinIndex = 0
      t.top = 1
      t.bottom = DW - 1
      T.hofsOpp, T.hofsPl = 0, 0
      for i = 0, DH - 1 do fx.buf1[i] = WIN_RANGE(DW, DW + 1) end
      fx.state = 1
      return false
    end,
    function(fx)
      fx.banner = true
      fx.state = 2
      return false
    end,
    function(fx)
      local t, T, b = fx.t, fx.T, fx.buf0
      T.vblankDma = false
      local si = u8(t.sinIndex)
      t.sinIndex = s16(t.sinIndex + 16)
      for i = 0, DH / 2 - 1 do
        local x = t.top + Sin(si, 16)
        if x < 0 then x = 1 end
        if x > DW then x = DW end
        b[i] = x
        si = u8(si + 16)
      end
      for i = DH / 2, DH - 1 do
        local x = t.bottom - Sin(si, 16)
        if x < 0 then x = 0 end
        if x > DW - 1 then x = DW - 1 end
        b[i] = u16(bor(lshift(x, 8), DW))
        si = u8(si + 16)
      end
      t.top = t.top + 8
      t.bottom = t.bottom - 8
      if t.top > DW then t.top = DW end
      if t.bottom < 0 then t.bottom = 0 end
      if t.top == DW and t.bottom == 0 then fx.state = 3 end
      mugHofs(T)
      T.vblankDma = true
      return false
    end,
    function(fx)
      local t, T = fx.t, fx.T
      T.vblankDma = false
      for i = 0, DH - 1 do fx.buf0[i] = DW end
      fx.state = 4
      t.sinIndex, t.top, t.bottom = 0, 0, 0
      mugHofs(T)
      fx.opp.dir = 0
      fx.player.dir = 1
      fx.opp.state = fx.opp.state + 1
      pcall(function() Audio.playSe("SE_MUGSHOT") end)
      T.vblankDma = true
      return false
    end,
    function(fx)
      mugHofs(fx.T)
      if fx.opp.done then
        fx.state = 5
        fx.player.state = fx.player.state + 1
      end
      return false
    end,
    function(fx)
      local T = fx.T
      mugHofs(T)
      if fx.player.done then
        T.vblankDma = false
        for i = 0, DH - 1 do
          fx.buf0[i] = 0
          fx.buf1[i] = 0
        end
        fx.fadeMode = true
        fx.t.timer = 0
        fx.t.spread = 0
        fx.state = 6
      end
      return false
    end,
    function(fx)
      local t, T, b = fx.t, fx.T, fx.buf0
      T.vblankDma = false
      local active = true
      mugHofs(T)
      if t.spread < DH / 2 then t.spread = t.spread + 2 end
      if t.spread > DH / 2 then t.spread = DH / 2 end
      t.timer = t.timer + 1
      if band(t.timer, 1) == 1 then
        active = false
        for i = 0, t.spread do
          local y1, y2 = DH / 2 - i, DH / 2 + i
          if (b[y1] or 0) <= 15 then
            active = true
            b[y1] = (b[y1] or 0) + 1
          end
          if (b[y2] or 0) <= 15 then
            active = true
            b[y2] = (b[y2] or 0) + 1
          end
        end
      end
      if t.spread == DH / 2 and not active then fx.state = 7 end
      T.vblankDma = true
      return false
    end,
    function(fx)
      fx.T.vblankDma = false
      fx.pal:blend(Pal.ALL, 16, Pal.WHITE)
      fx.darken = true
      fx.t.timer = 0
      fx.state = 8
      return true
    end,
    function(fx)
      local t = fx.t
      fx.T.vblankDma = false
      t.timer = t.timer + 1
      for i = 0, DH - 1 do fx.buf0[i] = u16(t.timer * 257) end
      if t.timer > 15 then fx.state = 9 end
      fx.T.vblankDma = true
      return false
    end,
    function(fx)
      fadeScreenBlack(fx)
      fx.done = true
      return false
    end,
  },
  sprite = function(_, s)
    while PIC_FUNCS[s.state](s) do end
  end,
  vblank = function(fx)
    local T = fx.T
    if T.vblankDma then copyBuf(fx.buf1, fx.buf0, DH) end
    fx.hofsOpp1, fx.hofsPl1 = T.hofsOpp, T.hofsPl
    fx.darken1 = fx.darken
  end,
}

for mid in pairs(MUGSHOT_BY_ID) do DEF[mid] = MUGSHOT_DEF end

--------------------------------------------------------------------------------
-- Orchestrator Lifecycle
--------------------------------------------------------------------------------

local function newFx(tid, opts)
  local def = DEF[tid] or DEF[ID.SLICE]
  local fx = {
    id = tid, def = def, state = 0, t = {}, T = { vblankDma = false },
    buf0 = {}, buf1 = {}, sprites = {}, done = false,
    pal = BattleTransition._pal,
  }
  fx.mugKey = MUGSHOT_BY_ID[tid]
  local g = opts and opts.playerGender
  fx.female = (g == 1 or g == "female")
  if def.init then def.init(fx) end
  return fx
end

local function stepFx(fx)
  local def = fx.def
  local funcs = def.funcs
  while not fx.done do
    local f = funcs[fx.state + 1]
    if not f or not f(fx) then break end
  end
  if def.sprite then
    local alive = {}
    for _, s in ipairs(fx.sprites) do
      if not s.dead then def.sprite(fx, s) end
      if not s.dead or s.real then alive[#alive + 1] = s end
    end
    fx.sprites = alive
  end
  fx.pal:updateFade()
  if def.vblank then def.vblank(fx) end
end

-- src/battle_transition.c:2798
local function introStep(intro, pal)
  if intro.state == 0 then
    intro.blend = intro.blend + 2
    if intro.blend > 16 then intro.blend = 16 end
    pal:blend(Pal.ALL, intro.blend, GRAY)
    if intro.blend >= 16 then intro.state = 1 end
  else
    intro.blend = intro.blend - 2
    if intro.blend < 0 then intro.blend = 0 end
    pal:blend(Pal.ALL, intro.blend, GRAY)
    if intro.blend == 0 then
      intro.fades = intro.fades - 1
      if intro.fades == 0 then return true end
      intro.state = 0
    end
  end
  return false
end

function BattleTransition.start(transitionId, opts, doneCb)
  opts = opts or {}
  BattleTransition._active = true
  BattleTransition._transitionId = transitionId or ID.SLICE
  BattleTransition._opts = opts
  BattleTransition._doneCb = doneCb
  BattleTransition._frame = 0
  BattleTransition._pal = Pal.new()
  BattleTransition._fx = nil
  BattleTransition._intro = { state = 0, blend = 0, fades = 2, wait = 1, done = false }
  BattleTransition._worldDrawn = false

  if opts.skipIntro then
    BattleTransition._phase = "main"
  else
    BattleTransition._phase = "intro"
  end

  if opts.headless then
    BattleTransition.finish()
    return true
  end
  return true
end

function BattleTransition.isActive()
  return BattleTransition._active
end

function BattleTransition.finish()
  BattleTransition._active = false
  BattleTransition._phase = "done"
  BattleTransition._fx = nil
  local cb = BattleTransition._doneCb
  BattleTransition._doneCb = nil
  if cb then cb() end
end

function BattleTransition.abort()
  BattleTransition._active = false
  BattleTransition._phase = "idle"
  BattleTransition._fx = nil
  BattleTransition._doneCb = nil
end

function BattleTransition.tick()
  if not BattleTransition._active then return false end
  BattleTransition._frame = BattleTransition._frame + 1
  local phase = BattleTransition._phase

  if phase == "intro" then
    local intro = BattleTransition._intro
    if intro.wait > 0 then
      intro.wait = intro.wait - 1
    elseif not intro.done then
      if introStep(intro, BattleTransition._pal) then intro.done = true end
    else
      BattleTransition._phase = "main"
    end
    BattleTransition._pal:updateFade()
    return true
  end

  if phase == "main" then
    local fx = BattleTransition._fx
    if not fx then
      fx = newFx(BattleTransition._transitionId, BattleTransition._opts)
      BattleTransition._fx = fx
    end
    stepFx(fx)
    if fx.done then BattleTransition._phase = "ending" end
    return true
  end

  if phase == "ending" then
    BattleTransition.finish()
    return true
  end

  return false
end

local function makeView(X0, X1, Y0, Y1)
  local R = { X0 = X0, X1 = X1, Y0 = Y0, Y1 = Y1 }
  local span = X1 - X0
  R.hdist = function(v) return floor(v * span / DW + 0.5) end
  R.hmap = function(x) return X0 + floor(x * span / DW + 0.5) end
  R.hmapL = function(x) if x <= 0 then return X0 end return R.hmap(x) end
  R.hmapR = function(x) if x >= DW then return X1 end return R.hmap(x) end
  return R
end

local SCRATCH = {}

function BattleTransition.blackSpans(y, X0, X1)
  local fx = BattleTransition._fx
  if not fx then return {} end
  local out = {}
  local pal = fx.pal.slots[0]
  if pal.y >= 16 and pal.color == Pal.BLACK then
    return { X0 or 0, X1 or DW }
  end
  local def = fx.def
  local R = makeView(X0 or 0, X1 or DW, 0, DH)
  local n = 0
  if def.rowSpans then
    n = def.rowSpans(fx, y, R, SCRATCH)
  elseif def.winSpans then
    n = def.winSpans(fx, y, SCRATCH)
  end
  for i = 1, 2 * n do out[i] = SCRATCH[i] end
  return out
end

function BattleTransition.screenCoverage()
  local covered = 0
  for y = 0, DH - 1 do
    local s = BattleTransition.blackSpans(y)
    local row = {}
    for i = 1, #s, 2 do
      for x = math.max(0, s[i]), math.min(DW, s[i + 1]) - 1 do row[x] = true end
    end
    for _ in pairs(row) do covered = covered + 1 end
  end
  return covered / (DW * DH)
end

local function mergeRuns(R, valueFn, drawFn)
  local cur, start
  for y = R.Y0, R.Y1 - 1 do
    local v = valueFn(y)
    if v ~= cur then
      if start and cur then drawFn(cur, start, y) end
      cur, start = v, y
    end
  end
  if start and cur then drawFn(cur, start, R.Y1) end
end

local function drawFieldRows(R, G, fx)
  local tex = R.field
  if not tex then return end
  local def = fx and fx.def
  if fx and def.shift then
    local q = R.fieldQuad
    local runStart, rdx, rdy
    local function flush(yEnd)
      if not runStart then return end
      q:setViewport(rdx, runStart + rdy + R.gy, R.X1 - R.X0, yEnd - runStart)
      G.draw(tex, q, R.X0, runStart)
    end
    for y = R.Y0, R.Y1 - 1 do
      local dx, dy = def.shift(fx, y, R)
      if not (runStart and dx == rdx and dy == rdy) then
        flush(y)
        runStart, rdx, rdy = y, dx, dy
      end
    end
    flush(R.Y1)
    return
  end
  if fx and fx.mosaic and fx.mosaic > 0 and G.newCanvas then
    local m = fx.mosaic + 1
    local bx0, by0 = floor(R.X0 / m), floor(R.Y0 / m)
    local cw = floor((R.X1 - 1) / m) - bx0 + 1
    local ch = floor((R.Y1 - 1) / m) - by0 + 1
    local key = cw .. "x" .. ch
    local small = BattleTransition._mosaicCanvas
    if not small or BattleTransition._mosaicKey ~= key then
      if small and small.release then pcall(small.release, small) end
      small = G.newCanvas(cw, ch, { dpiscale = 1 })
      small:setFilter("nearest", "nearest")
      BattleTransition._mosaicCanvas = small
      BattleTransition._mosaicKey = key
    end
    G.push("all")
    G.origin()
    G.setCanvas(small)
    G.clear(0, 0, 0, 1)
    G.setColor(1, 1, 1, 1)
    G.draw(tex, -bx0 + 0.5 - (R.gx + 0.5) / m, -by0 + 0.5 - (R.gy + 0.5) / m, 0, 1 / m, 1 / m)
    G.pop()
    G.setColor(1, 1, 1, 1)
    G.draw(small, bx0 * m, by0 * m, 0, m, m)
    return
  end
  G.draw(tex, R.X0, R.Y0)
end

local function drawSpanRows(R, G, spanFn)
  local rows = {}
  local tmp = {}
  for y = R.Y0, R.Y1 - 1 do
    local k = spanFn(y, tmp)
    local key = ""
    for i = 1, 2 * k do key = key .. tmp[i] .. "," end
    rows[#rows + 1] = key
    rows[key] = rows[key] or { unpack(tmp, 1, 2 * k) }
  end
  G.setColor(0, 0, 0, 1)
  local cur, start = nil, R.Y0
  local function flush(yEnd)
    if cur == nil or cur == "" then return end
    local s = rows[cur]
    for i = 1, #s, 2 do
      if s[i + 1] > s[i] then G.rectangle("fill", s[i], start, s[i + 1] - s[i], yEnd - start) end
    end
  end
  for i = 1, #rows do
    local y = R.Y0 + i - 1
    if rows[i] ~= cur then
      flush(y)
      cur, start = rows[i], y
    end
  end
  flush(R.Y1)
end

local function drawWindowBlack(R, G, fx)
  local def = fx.def
  local screen = {}
  local tmp = {}
  for y = 0, DH - 1 do
    local n = def.winSpans(fx, y, tmp)
    local s = {}
    for i = 1, 2 * n do s[i] = tmp[i] end
    screen[y] = s
  end
  local sub = { X0 = math.max(R.X0, 0), X1 = math.min(R.X1, DW), Y0 = math.max(R.Y0, 0), Y1 = math.min(R.Y1, DH) }
  drawSpanRows(sub, G, function(y, out)
    local s = screen[y]
    local k = 0
    for i = 1, #s, 2 do
      local a, b = math.max(s[i], sub.X0), math.min(s[i + 1], sub.X1)
      if b > a then
        k = k + 1
        out[2 * k - 1], out[2 * k] = a, b
      end
    end
    return k
  end)
  if R.X0 >= 0 and R.Y0 >= 0 and R.X1 <= DW and R.Y1 <= DH then return end
  local function blackAt(x, y)
    local s = screen[y]
    for i = 1, #s, 2 do
      if x >= s[i] and x < s[i + 1] then return true end
    end
    return false
  end
  local cx, cy, K = DW / 2, DH / 2, 64
  local function wedge(ax, ay, bx, by)
    G.polygon("fill", ax, ay, bx, by,
      cx + (bx - cx) * K, cy + (by - cy) * K,
      cx + (ax - cx) * K, cy + (ay - cy) * K)
  end
  G.setColor(0, 0, 0, 1)
  local function edge(count, test, emit)
    local runStart
    for i = 0, count do
      local on = i < count and test(i)
      if on and not runStart then
        runStart = i
      elseif not on and runStart then
        emit(runStart, i)
        runStart = nil
      end
    end
  end
  edge(DW, function(x) return blackAt(x, 0) end, function(a, b) wedge(a, 0, b, 0) end)
  edge(DW, function(x) return blackAt(x, DH - 1) end, function(a, b) wedge(a, DH, b, DH) end)
  edge(DH, function(y) return blackAt(0, y) end, function(a, b) wedge(0, a, 0, b) end)
  edge(DH, function(y) return blackAt(DW - 1, y) end, function(a, b) wedge(DW, a, DW, b) end)
end

local function drawBigPokeball(R, G, fx)
  if not fx.pattern then return end
  local Chrome = getChrome()
  local img = Chrome and Chrome.bigPokeball and Chrome.bigPokeball()
  local ba = fx.bldAlpha1 or { 0, 16 }
  local eva, evb = math.min(16, ba[1]), math.min(16, ba[2])
  if not img then return end
  local q = BattleTransition._bigQuad
  if not q then
    q = G.newQuad(0, 0, 1, 1, DW, DH)
    BattleTransition._bigQuad = q
  end
  local h = fx.hofs1 or { const = 240 }
  local function rowHofs(y)
    if h.const then return h.const end
    return Sin(h.idx + 132 * y, h.amp)
  end
  local function pass()
    for y = 0, DH - 1 do
      local s = band(rowHofs(y), 0xFF)
      if s < DW then
        q:setViewport(s, y, DW - s, 1)
        G.draw(img, q, 0, y)
      end
      if s > 16 then
        q:setViewport(0, y, s - 16, 1)
        G.draw(img, q, 256 - s, y)
      end
    end
  end
  if evb < 16 then
    G.setColor(0, 0, 0, 1 - evb / 16)
    pass()
  end
  if eva > 0 then
    G.setBlendMode("add")
    G.setColor(eva / 16, eva / 16, eva / 16, 1)
    pass()
    G.setBlendMode("alpha")
  end
  G.setColor(1, 1, 1, 1)
end

local function drawTrail(R, G, fx)
  if not fx.trail then return end
  G.setColor(0, 0, 0, 1)
  for lane, cols in pairs(fx.trail) do
    local y0 = lane * 32
    if y0 + 32 > R.Y0 and y0 < R.Y1 then
      local runStart
      for c = 0, 32 do
        local on = cols[c]
        if on and not runStart then
          runStart = c
        elseif not on and runStart then
          local a, b = R.hmapL(runStart * 8), R.hmapR(c * 8)
          if b > a then G.rectangle("fill", a, y0, b - a, 32) end
          runStart = nil
        end
      end
    end
  end
  local Chrome = getChrome()
  local ball = Chrome and Chrome.slidingPokeball and Chrome.slidingPokeball()
  if not ball then return end
  G.setColor(1, 1, 1, 1)
  for _, s in ipairs(fx.sprites) do
    if not s.dead and s.y + 16 > R.Y0 and s.y - 16 < R.Y1 then
      G.draw(ball, R.hmap(s.x), s.y, -s.rot * math.pi * 2 / 256, 1, 1, 16, 16)
    end
  end
end

local function drawGrid(R, G, fx)
  local stage = fx.gridStage or 0
  if stage <= 0 then return end
  local Chrome = getChrome()
  local img = Chrome and Chrome.gridFrame and Chrome.gridFrame(stage)
  if not img then
    if stage >= 14 then
      G.setColor(0, 0, 0, 1)
      G.rectangle("fill", R.X0, R.Y0, R.X1 - R.X0, R.Y1 - R.Y0)
    end
    return
  end
  local q = BattleTransition._gridQuad
  if not q then
    q = G.newQuad(0, 0, 1, 1, 8, 8)
    BattleTransition._gridQuad = q
  end
  q:setViewport(R.X0, R.Y0, R.X1 - R.X0, R.Y1 - R.Y0, 8, 8)
  G.setColor(1, 1, 1, 1)
  G.draw(img, q, R.X0, R.Y0)
end

local function drawMugshot(R, G, fx)
  local Chrome = getChrome()
  local vsbar = fx.banner and Chrome and Chrome.vsbar and Chrome.vsbar(fx.mugKey, fx.female and "female" or "male")
  if vsbar then
    local q = BattleTransition._vsQuad
    if not q then
      q = G.newQuad(0, 0, 1, 1, 256, DH)
      BattleTransition._vsQuad = q
    end
    G.setColor(1, 1, 1, 1)
    local y0, y1 = math.max(R.Y0, 0), math.min(R.Y1, DH)
    for y = y0, y1 - 1 do
      local a, b
      if fx.fadeMode then
        a, b = R.X0, R.X1
      else
        local l, r = winH(fx.buf1[y])
        if l then a, b = R.hmapL(l), R.hmapR(r) end
      end
      if a and b > a then
        local hofs = (y < DH / 2) and (fx.hofsOpp1 or 0) or (fx.hofsPl1 or 0)
        q:setViewport(a + hofs, y, b - a, 1, 256, DH)
        G.draw(vsbar, q, a, y)
      end
    end
  end
  local TP = getTrainerPic()
  if not TP then return end
  local pq = BattleTransition._picQuad
  if not pq then
    pq = G.newQuad(0, 0, 64, 32, 64, 64)
    BattleTransition._picQuad = pq
  end
  G.setColor(1, 1, 1, 1)
  for _, s in ipairs({ fx.opp, fx.player }) do
    local entry = s and TP.front and TP.front(s.pic)
    local img = entry and (entry.image or entry)
    if img and type(img) ~= "table" then
      local sx = s.flip and -2 or 2
      G.draw(img, pq, R.hmap(s.x), s.y, 0, sx, 2, 32, 16)
    end
  end
end

local function drawMugshotPost(R, G, fx)
  if not fx.fadeMode then return end
  if fx.darken1 then
    local v = band(fx.buf1[0] or 0, 0x1F)
    if v > 16 then v = 16 end
    if v > 0 then
      G.setColor(0, 0, 0, v / 16)
      G.rectangle("fill", R.X0, R.Y0, R.X1 - R.X0, R.Y1 - R.Y0)
    end
    return
  end
  mergeRuns(R, function(y)
    local yy = y
    if yy < 0 then yy = 0 end
    if yy > DH - 1 then yy = DH - 1 end
    local v = band(fx.buf1[yy] or 0, 0x1F)
    if v > 16 then v = 16 end
    return v
  end, function(v, y0, y1)
    if v > 0 then
      G.setColor(1, 1, 1, v / 16)
      G.rectangle("fill", R.X0, y0, R.X1 - R.X0, y1 - y0)
    end
  end)
end

local function render(R, G)
  local fx = BattleTransition._fx
  R.rowBands = function(valueFn, drawFn) mergeRuns(R, valueFn, drawFn) end
  G.setColor(1, 1, 1, 1)
  G.setBlendMode("alpha")
  if fx and fx.def.redraw then drawFieldRows(R, G, fx) end
  if fx then
    local def, id = fx.def, fx.id
    if id == ID.BIG_POKEBALL then drawBigPokeball(R, G, fx) end
    if id == ID.GRID_SQUARES then drawGrid(R, G, fx) end
    if id == ID.POKEBALLS_TRAIL then drawTrail(R, G, fx) end
    if fx.mugKey then drawMugshot(R, G, fx) end
    if def.rowSpans then
      drawSpanRows(R, G, function(y, out) return def.rowSpans(fx, y, R, out) end)
    elseif def.winSpans then
      drawWindowBlack(R, G, fx)
    end
  end
  local pal = BattleTransition._pal and BattleTransition._pal.slots[0]
  if pal and pal.y > 0 then
    local c = pal.color or Pal.BLACK
    G.setColor(c[1] / 31, c[2] / 31, c[3] / 31, math.min(16, pal.y) / 16)
    G.rectangle("fill", R.X0, R.Y0, R.X1 - R.X0, R.Y1 - R.Y0)
  end
  if fx then
    if fx.def.post then fx.def.post(fx, R, G) end
    if fx.mugKey then drawMugshotPost(R, G, fx) end
  end
  G.setColor(1, 1, 1, 1)
end

local function viewFor(gx, gy, w, h)
  local R = makeView(-gx, w - gx, -gy, h - gy)
  R.gx, R.gy = gx, gy
  return R
end

function BattleTransition.drawWorld(canvas, vw, vh)
  if not BattleTransition._active then return false end
  if not (love and love.graphics and canvas) then return false end
  local G = love.graphics
  local gx, gy = floor((vw - DW) / 2), floor((vh - DH) / 2)
  local R = viewFor(gx, gy, vw, vh)
  local fx = BattleTransition._fx
  G.push("all")
  G.origin()
  if fx and fx.def.redraw then
    local scratch = BattleTransition._scratch
    if not scratch or scratch:getWidth() ~= vw or scratch:getHeight() ~= vh then
      if scratch and scratch.release then pcall(scratch.release, scratch) end
      scratch = G.newCanvas(vw, vh, { dpiscale = 1 })
      scratch:setFilter("nearest", "nearest")
      pcall(scratch.setWrap, scratch, "repeat", "repeat")
      BattleTransition._scratch = scratch
      BattleTransition._fieldQuad = G.newQuad(0, 0, 1, 1, vw, vh)
    end
    G.setCanvas(scratch)
    G.clear(0, 0, 0, 1)
    G.setColor(1, 1, 1, 1)
    G.draw(canvas, 0, 0)
    G.setCanvas(canvas)
    G.clear(0, 0, 0, 1)
    R.field = scratch
    R.fieldQuad = BattleTransition._fieldQuad
  end
  G.translate(gx, gy)
  local ok, err = pcall(render, R, G)
  G.pop()
  if not ok then print("[game3/battle_transition] " .. tostring(err)) end
  BattleTransition._worldDrawn = true
  return true
end

function BattleTransition.draw()
  if not BattleTransition._active then return end
  if not (love and love.graphics) then return end
  if BattleTransition._worldDrawn then
    BattleTransition._worldDrawn = false
    return
  end
  local G = love.graphics
  G.push("all")
  local ok, err = pcall(render, viewFor(0, 0, DW, DH), G)
  G.pop()
  if not ok then print("[game3/battle_transition] " .. tostring(err)) end
end

return BattleTransition
