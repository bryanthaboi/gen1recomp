local bit = require("bit")

local band, arshift = bit.band, bit.arshift
local floor = math.floor

local M = {}

local function quadFor(G, img, key, cache)
  local q = cache[key]
  if not q then
    local w, h = img:getDimensions()
    q = G.newQuad(0, 0, 1, 1, w, h)
    cache[key] = q
  end
  return q
end

local QUADS = {}

local function drawRows(G, img, rowHofs, rowVofs, DW, DH)
  local q = quadFor(G, img, tostring(img), QUADS)
  local w, h = img:getDimensions()
  for y = 0, DH - 1 do
    local sx = band(rowHofs(y), w - 1)
    local sy = band(y + rowVofs(y), h - 1)
    q:setViewport(sx, sy, DW, 1, w, h)
    G.draw(img, q, 0, y)
  end
end

local function palBlendMul(slot)
  local y = slot and slot.y or 0
  if y > 16 then y = 16 end
  return 1 - y / 16
end

function M.register(DEF, ID, H)
  local DW, DH, Pal = H.DW, H.DH, H.Pal
  local s16, Sin = H.s16, H.Sin
  local winInside, winOutside, rowSrc = H.winInside, H.winOutside, H.rowSrc
  local copyBuf, setCircularMask, fadeScreenBlack = H.copyBuf, H.setCircularMask, H.fadeScreenBlack

  local function chrome() return H.getChrome() end

  local HOFS_OFF = { const = DW }

  -- pokeemerald/src/battle_transition.c:1375
  local function patternDef(opts)
    local funcs = {
      function(fx)
        local t = fx.t
        t.evb, t.eva, t.sinIndex, t.amp, t.blendDelay = 16, 0, 0, 0x4000, 0
        t.endDelay = 60
        fx.T.bldAlpha = { 0, 16 }
        fx.hofs1 = { const = DW }
        fx.patternImage = opts.image
        fx.state = fx.state + 1
        return false
      end,
      function(fx)
        fx.pattern = true
        fx.state = fx.state + 1
        return opts.setGfxContinues == true
      end,
      -- pokeemerald/src/battle_transition.c:1612
      function(fx)
        local t = fx.t
        fx.T.vblankDma = false
        if t.blendDelay == 0 or (function() t.blendDelay = t.blendDelay - 1 return t.blendDelay == 0 end)() then
          t.eva = t.eva + 1
          t.blendDelay = 2
        end
        fx.T.bldAlpha = { t.eva, t.evb }
        if t.eva > 15 then fx.state = fx.state + 1 end
        t.sinIndex = s16(t.sinIndex + 8)
        t.amp = s16(t.amp - 256)
        fx.hofs0 = { idx = t.sinIndex, amp = arshift(t.amp, 8) }
        fx.T.vblankDma = true
        return false
      end,
      -- pokeemerald/src/battle_transition.c:1632
      function(fx)
        local t = fx.t
        fx.T.vblankDma = false
        if t.blendDelay == 0 or (function() t.blendDelay = t.blendDelay - 1 return t.blendDelay == 0 end)() then
          t.evb = t.evb - 1
          t.blendDelay = 2
        end
        fx.T.bldAlpha = { t.eva, t.evb }
        if t.evb == 0 then fx.state = fx.state + 1 end
        t.sinIndex = s16(t.sinIndex + 8)
        t.amp = s16(t.amp - 256)
        fx.hofs0 = { idx = t.sinIndex, amp = arshift(t.amp, 8) }
        fx.T.vblankDma = true
        return false
      end,
      -- pokeemerald/src/battle_transition.c:1652
      function(fx)
        local t = fx.t
        fx.T.vblankDma = false
        t.sinIndex = s16(t.sinIndex + 8)
        t.amp = s16(t.amp - 256)
        fx.hofs0 = { idx = t.sinIndex, amp = arshift(t.amp, 8) }
        if t.amp <= 0 then
          fx.state = fx.state + 1
          t.radius = DH
          t.radiusDelta = 256
          t.vblankSet = false
        end
        fx.T.vblankDma = true
        return false
      end,
    }
    if opts.countdown then
      -- pokeemerald/src/battle_transition.c:1672
      funcs[#funcs + 1] = function(fx)
        local t = fx.t
        t.endDelay = t.endDelay - 1
        if t.endDelay == 0 then fx.state = fx.state + 1 end
        return false
      end
    end
    -- pokeemerald/src/battle_transition.c:1694
    funcs[#funcs + 1] = function(fx)
      local t = fx.t
      fx.T.vblankDma = false
      if t.radiusDelta < 4 * 256 then t.radiusDelta = t.radiusDelta + 128 end
      if t.radius ~= 0 then
        t.radius = t.radius - arshift(t.radiusDelta, 8)
        if t.radius < 0 then t.radius = 0 end
      end
      setCircularMask(fx.buf0, DW / 2, DH / 2, t.radius)
      if t.radius == 0 then
        fadeScreenBlack(fx)
        fx.done = true
      else
        if not t.vblankSet then
          t.vblankSet = true
          fx.maskMode = true
        end
        fx.T.vblankDma = true
      end
      return false
    end
    return {
      funcs = funcs,
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
        return winOutside(fx.mask1[y], out)
      end,
      row0 = "prev",
      front = { "mask1", "hofs1" },
      draw = function(fx, R, G)
        if not fx.pattern or not fx.patternImage then return end
        local img = fx.patternImage(fx)
        if not img then return end
        local ba = fx.bldAlpha1 or { 0, 16 }
        local eva, evb = math.min(16, ba[1]), math.min(16, ba[2])
        local function rowHofs(y)
          local f, sy = rowSrc(fx, y)
          local h = f.hofs1 or HOFS_OFF
          if h.const then return h.const end
          return Sin(h.idx + 132 * sy, h.amp)
        end
        local function zero() return 0 end
        if evb < 16 then
          G.setColor(0, 0, 0, 1 - evb / 16)
          drawRows(G, img, rowHofs, zero, DW, DH)
        end
        if eva > 0 then
          G.setBlendMode("add")
          G.setColor(eva / 16, eva / 16, eva / 16, 1)
          drawRows(G, img, rowHofs, zero, DW, DH)
          G.setBlendMode("alpha")
        end
        G.setColor(1, 1, 1, 1)
      end,
    }
  end

  M.patternDef = patternDef
  M.drawRows = drawRows

  local function assetImage(key, which, bank)
    return function()
      local C = chrome()
      if not C then return nil end
      return C.assetImage(key, C.assetPalette(key, which or 1, bank or 0))
    end
  end

  -- pokeemerald/src/battle_transition.c:1443
  DEF[ID.BIG_POKEBALL] = patternDef({
    image = function()
      local C = chrome()
      return C and C.bigPokeball and C.bigPokeball() or nil
    end,
    setGfxContinues = true,
  })
  -- pokeemerald/src/battle_transition.c:1399
  DEF[ID.AQUA] = patternDef({ image = assetImage("aqua"), countdown = true })
  -- pokeemerald/src/battle_transition.c:1414
  DEF[ID.MAGMA] = patternDef({ image = assetImage("magma"), countdown = true })
  -- pokeemerald/src/battle_transition.c:1501
  DEF[ID.REGICE] = patternDef({ image = assetImage("regice") })
  -- pokeemerald/src/battle_transition.c:1514
  DEF[ID.REGISTEEL] = patternDef({ image = assetImage("registeel") })
  -- pokeemerald/src/battle_transition.c:1527
  DEF[ID.REGIROCK] = patternDef({ image = assetImage("regirock") })

  local BG15 = 15

  -- pokeemerald/src/battle_transition.c:1679
  local function bgFadeBlack(fx)
    fx.pal:beginFade(Pal.ALL, 1, 0, 16, Pal.BLACK)
    fx.state = fx.state + 1
    return false
  end

  local function waitFade(fx)
    if not fx.pal:fadeActive() then fx.state = fx.state + 1 end
    return false
  end

  local function bg0Post(fx, R, G)
    if not fx.bg0Key or not fx.bg0Pal then return end
    local C = chrome()
    if not C then return end
    local img = C.assetImage(fx.bg0Key, fx.bg0Pal)
    if not img then return end
    local mul = palBlendMul(fx.pal2 and fx.pal2.slots[BG15])
    if mul <= 0 then return end
    local vofs = fx.bg0Vofs or 0
    G.setColor(mul, mul, mul, 1)
    drawRows(G, img, function() return 0 end, function() return vofs end, DW, DH)
    G.setColor(1, 1, 1, 1)
  end

  -- pokeemerald/src/battle_transition.c:1542
  local function weatherDuo(key)
    return {
      funcs = {
        bgFadeBlack,
        waitFade,
        function(fx)
          fx.bg0Key = key
          fx.pal2 = Pal.new()
          fx.t.timer = 0
          fx.state = fx.state + 1
          return false
        end,
        function(fx)
          local t = fx.t
          if t.timer % 3 == 0 then
            fx.bg0Pal = chrome().assetPalette(key, 1, floor((t.timer % 30) / 3))
          end
          t.timer = t.timer + 1
          if t.timer > 58 then
            fx.state = fx.state + 1
            t.timer = 0
          end
          return false
        end,
        function(fx)
          local t = fx.t
          if t.timer % 5 == 0 then
            fx.bg0Pal = chrome().assetPalette(key, 2, floor(t.timer / 5)) or fx.bg0Pal
          end
          t.timer = t.timer + 1
          if t.timer > 68 then
            fx.state = fx.state + 1
            t.timer = 0
            t.endDelay = 30
          end
          return false
        end,
        function(fx)
          local t = fx.t
          t.endDelay = t.endDelay - 1
          if t.endDelay == 0 then fx.state = fx.state + 1 end
          return false
        end,
        -- pokeemerald/src/battle_transition.c:1589
        function(fx)
          fx.pal2:beginFade(Pal.ALL, 1, 0, 16, Pal.BLACK)
          fx.state = fx.state + 1
          return false
        end,
        function(fx)
          if not fx.pal2:fadeActive() then
            fadeScreenBlack(fx)
            fx.done = true
          end
          return false
        end,
      },
      vblank = function(fx) if fx.pal2 then fx.pal2:updateFade() end end,
      post = bg0Post,
    }
  end

  DEF[ID.KYOGRE] = weatherDuo("kyogre")
  -- pokeemerald/src/battle_transition.c:3374
  DEF[ID.GROUDON] = weatherDuo("groudon")

  -- pokeemerald/src/battle_transition.c:618
  local VIBRATIONS = { -6, 4 }

  -- pokeemerald/src/battle_transition.c:3437
  DEF[ID.RAYQUAZA] = {
    funcs = {
      bgFadeBlack,
      waitFade,
      function(fx)
        fx.pal2 = Pal.new()
        fx.bg0Vofs = 0
        fx.t.timer = 0
        fx.state = fx.state + 1
        return false
      end,
      function(fx)
        fx.bg0Key = "rayquaza"
        fx.bg0Pal = chrome().assetPalette("rayquaza", 1, 5)
        fx.state = fx.state + 1
        return false
      end,
      function(fx)
        local t = fx.t
        if t.timer % 4 == 0 then
          fx.bg0Pal = chrome().assetPalette("rayquaza", 1, floor(t.timer / 4) + 5) or fx.bg0Pal
        end
        t.timer = t.timer + 1
        if t.timer > 40 then
          fx.state = fx.state + 1
          t.timer = 0
        end
        return false
      end,
      function(fx)
        local t = fx.t
        t.timer = t.timer + 1
        if t.timer > 20 then
          fx.state = fx.state + 1
          t.timer = 0
          fx.pal2:beginFade(Pal.ALL, 2, 0, 16, Pal.BLACK)
        end
        return false
      end,
      function(fx)
        if not fx.pal2:fadeActive() then
          fx.bg0Vofs = 256
          fx.state = fx.state + 1
        end
        return false
      end,
      function(fx)
        fx.pal:resetFade()
        fx.pal:blend(Pal.ALL, 8, Pal.BLACK)
        fx.pal2 = Pal.new()
        fx.state = fx.state + 1
        return false
      end,
      function(fx)
        local t = fx.t
        if t.timer % 3 == 0 then
          fx.bg0Pal = chrome().assetPalette("rayquaza", 1, floor(t.timer / 3)) or fx.bg0Pal
        end
        t.timer = t.timer + 1
        if t.timer >= 40 then
          fx.bg0Key = nil
          fx.state = fx.state + 1
          t.growSpeed = 256
          t.flag = false
        end
        return false
      end,
      -- pokeemerald/src/battle_transition.c:3101
      function(fx)
        local t = fx.t
        fx.T.vblankDma = false
        if not t.flag then
          t.flag = true
          t.radius = 48
          t.vibrateId = 0
        end
        t.radius = t.radius + VIBRATIONS[t.vibrateId + 1]
        t.vibrateId = (t.vibrateId + 1) % #VIBRATIONS
        setCircularMask(fx.buf0, DW / 2, DH / 2, t.radius)
        fx.holeMode = true
        if t.radius < 9 then
          fx.state = fx.state + 1
          t.flag = false
        end
        fx.T.vblankDma = true
        return false
      end,
      -- pokeemerald/src/battle_transition.c:3069
      function(fx)
        local t = fx.t
        if t.flag then
          fx.done = true
          return false
        end
        fx.T.vblankDma = false
        if t.growSpeed < 1024 then t.growSpeed = t.growSpeed + 128 end
        if t.radius < DH then t.radius = t.radius + arshift(t.growSpeed, 8) end
        if t.radius > DH then t.radius = DH end
        setCircularMask(fx.buf0, DW / 2, DH / 2, t.radius)
        if t.radius == DH then
          t.flag = true
          fadeScreenBlack(fx)
        else
          fx.T.vblankDma = true
        end
        return false
      end,
    },
    vblank = function(fx)
      if fx.pal2 then fx.pal2:updateFade() end
      if fx.holeMode then
        fx.hole1 = fx.hole1 or {}
        if fx.T.vblankDma then copyBuf(fx.hole1, fx.buf0, DH) end
      end
    end,
    winSpans = function(fx, y, out)
      if not fx.hole1 then return 0 end
      return winInside(fx.hole1[y], out)
    end,
    row0 = "prev",
    front = { "hole1" },
    post = bg0Post,
  }

  M.registerWhiteBars(DEF, ID, H)
end

-- pokeruby/src/battle_transition.c:2039
function M.registerWhiteBars(DEF, ID, H, emptyWin0)
  local DW, DH, Pal = H.DW, H.DH, H.Pal
  local rowSrc, copyBuf, fadeScreenBlack = H.rowSrc, H.copyBuf, H.fadeScreenBlack

  -- pokeemerald/src/battle_transition.c:739
  local NUM_WHITE_BARS = 8
  local BAR_H = DH / NUM_WHITE_BARS
  local DELAYS = { 0, 20, 15, 40, 10, 25, 35, 5 }
  local FADE_TARGET = 16 * 256

  -- pokeemerald/src/battle_transition.c:3590
  DEF[ID.WHITE_BARS_FADE] = {
    funcs = {
      function(fx)
        for i = 0, DH - 1 do
          fx.buf1[i] = 0
          fx.buf0[i] = 0
          fx.buf1[i + DH] = DW
          fx.buf0[i + DH] = 0
        end
        fx.T.counter = 0
        fx.state = 1
        return false
      end,
      function(fx)
        local last
        for i = 0, NUM_WHITE_BARS - 1 do
          last = { x = DW, y = i * BAR_H, fade = 0, finished = false, delay = DELAYS[i + 1], main = false,
            attempts = 0 }
          fx.sprites[#fx.sprites + 1] = last
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
        fx.state = 4
        return false
      end,
      function(fx)
        local T = fx.T
        T.bldY = T.bldY + 1
        if T.bldY > 16 then
          fadeScreenBlack(fx)
          fx.done = true
        end
        return false
      end,
    },
    -- pokeemerald/src/battle_transition.c:3709
    sprite = function(fx, s)
      local T = fx.T
      if s.delay ~= 0 then
        s.delay = s.delay - 1
        if s.main then T.vblankDma = true end
        return
      end
      local lvl = floor(s.fade / 256)
      for i = 0, BAR_H - 1 do
        fx.buf0[s.y + i] = lvl
        fx.buf0[s.y + i + DH] = band(s.x, 0xFF)
      end
      if s.x == 0 and s.fade == FADE_TARGET then s.finished = true end
      s.x = s.x - 16
      s.fade = s.fade + FADE_TARGET / 32
      if s.x < 0 then s.x = 0 end
      if s.fade > FADE_TARGET then s.fade = FADE_TARGET end
      if s.main then T.vblankDma = true end
      if s.finished then
        if not s.main then
          T.counter = T.counter + 1
          s.dead = true
        elseif T.counter >= NUM_WHITE_BARS - 1 then
          local a = s.attempts
          s.attempts = a + 1
          if a > 7 then
            T.counter = T.counter + 1
            s.dead = true
          end
        end
      end
    end,
    vblank = function(fx)
      if fx.T.vblankDma and not fx.darkenPhase then copyBuf(fx.buf1, fx.buf0, DH * 2) end
    end,
    post = function(fx, R, G)
      if fx.darkenPhase then
        local y = math.min(16, fx.T.bldY or 0)
        if y > 0 then
          G.setColor(0, 0, 0, y / 16)
          G.rectangle("fill", R.X0, R.Y0, R.X1 - R.X0, R.Y1 - R.Y0)
        end
        return
      end
      for y = 0, DH - 1 do
        local f, sy = rowSrc(fx, y)
        local v
        if y > 0 then
          v = math.min(16, fx.buf1[y - 1] or 0)
        else
          -- pokeemerald/src/battle_transition.c:3706
          v = math.min(16, band(fx.buf1[DH + 67] or 0, 0x1F))
        end
        local x = f.buf1[sy + DH] or DW
        if emptyWin0 then
          if v > 0 then
            G.setColor(1, 1, 1, v / 16)
            G.rectangle("fill", R.X0, y, R.X1 - R.X0, 1)
          end
        elseif v > 0 and x < DW then
          G.setColor(1, 1, 1, v / 16)
          G.rectangle("fill", R.hmap(x), y, R.hmapR(DW) - R.hmap(x), 1)
        end
      end
      G.setColor(1, 1, 1, 1)
    end,
    row0 = "prev",
    front = { "buf1" },
  }
end

return M
