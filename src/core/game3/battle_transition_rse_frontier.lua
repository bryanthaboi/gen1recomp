local bit = require("bit")

local band = bit.band
local floor = math.floor

local M = {}

function M.register(DEF, ID, H)
  local DW, DH, Pal = H.DW, H.DH, H.Pal
  local Sin, s16 = H.Sin, H.s16
  local fadeScreenBlack = H.fadeScreenBlack
  local A = require("src.core.game3.battle_transition_rse_a")

  local function logoImage()
    local C = H.getChrome()
    if not C then return nil end
    return C.assetImage("frontier_logo", C.assetPalette("frontier_logo", 1, 0))
  end

  -- pokeemerald/src/battle_transition.c:4238
  DEF[ID.FRONTIER_LOGO_WIGGLE] = A.patternDef({ image = logoImage, setGfxContinues = true })

  -- pokeemerald/src/battle_transition.c:4289
  DEF[ID.FRONTIER_LOGO_WAVE] = {
    funcs = {
      function(fx)
        local t = fx.t
        t.amp = 32 * 256
        t.sinVal = 0x7FFF
        t.eva, t.evb = 0, 16
        t.sinDec = 2560
        t.timer = 0
        t.startedFade = false
        fx.bld = { 0, 16 }
        fx.state = 1
        return false
      end,
      function(fx)
        fx.logo = true
        fx.state = 2
        return true
      end,
      function(fx)
        fx.vofs1 = {}
        for i = 0, DH - 1 do fx.vofs1[i] = 0 end
        fx.state = 3
        return true
      end,
      -- pokeemerald/src/battle_transition.c:4341
      function(fx)
        local t = fx.t
        fx.T.vblankDma = false
        local amplitude = floor(t.amp / 256)
        local sinVal = band(t.sinVal, 0xFFFF)
        t.sinVal = s16(t.sinVal - t.sinDec)
        if t.timer >= 70 then
          if t.amp - 384 >= 0 then t.amp = t.amp - 384 else t.amp = 0 end
        end
        if t.timer >= 0 and t.timer % 3 == 0 then
          if t.eva < 16 then
            t.eva = t.eva + 1
          elseif t.evb > 0 then
            t.evb = t.evb - 1
          end
          fx.bld = { t.eva, t.evb }
        end
        local rows = {}
        for i = 0, DH - 1 do
          rows[i] = Sin(band(floor(sinVal / 256), 0xFF), amplitude)
          sinVal = band(sinVal + 384, 0xFFFF)
        end
        fx.vofs0 = rows
        t.timer = t.timer + 1
        if t.timer == 101 then
          t.startedFade = true
          fx.pal:beginFade(Pal.ALL, 0, 0, 16, Pal.BLACK)
        end
        if t.startedFade and not fx.pal:fadeActive() then fx.done = true end
        t.sinDec = t.sinDec - 17
        fx.T.vblankDma = true
        return false
      end,
    },
    vblank = function(fx)
      fx.bld1 = fx.bld
      if fx.T.vblankDma and fx.vofs0 then fx.vofs1 = fx.vofs0 end
    end,
    draw = function(fx, R, G)
      if not fx.logo then return end
      local img = logoImage()
      if not img then return end
      local ba = fx.bld1 or { 0, 16 }
      local eva, evb = math.min(16, ba[1]), math.min(16, ba[2])
      local function hofs() return 0 end
      local function vofs(y)
        local f, sy = H.rowSrc(fx, y)
        local v = f.vofs1
        return v and v[sy] or 0
      end
      if evb < 16 then
        G.setColor(0, 0, 0, 1 - evb / 16)
        A.drawRows(G, img, hofs, vofs, DW, DH)
      end
      if eva > 0 then
        G.setBlendMode("add")
        G.setColor(eva / 16, eva / 16, eva / 16, 1)
        A.drawRows(G, img, hofs, vofs, DW, DH)
        G.setBlendMode("alpha")
      end
      G.setColor(1, 1, 1, 1)
    end,
    row0 = "first",
  }

  local SQUARE_SIZE, MARGIN_SIZE = 4, 1
  local PER_ROW = (DW - MARGIN_SIZE * 8 * 2) / (SQUARE_SIZE * 8)
  local PER_COL = DH / (SQUARE_SIZE * 8)
  local NUM_SQUARES = PER_ROW * PER_COL

  -- pokeemerald/src/battle_transition.c:972
  local SPIRAL_POS = {
    28, 29, 30, 31, 32, 33, 34,
    27, 20, 13, 6, 5, 4, 3,
    2, 1, 0, 7, 14, 21, 22,
    23, 24, 25, 26, 19, 12, 11,
    10, 9, 8, 15, 16, 17, 18,
  }
  -- pokeemerald/src/battle_transition.c:982
  local SCROLL_POS = {
    0, 16, 41, 22, 44, 2, 43, 21,
    46, 27, 9, 48, 38, 5, 57, 59,
    12, 63, 35, 28, 10, 53, 7, 49,
    39, 23, 55, 1, 62, 17, 61, 30,
    6, 34, 15, 51, 32, 58, 13, 45,
    37, 52, 11, 24, 60, 19, 56, 33,
    29, 50, 40, 54, 14, 3, 47, 20,
    18, 25, 4, 36, 26, 42, 31, 8,
  }

  local function palColor(bytes, i)
    local lo, hi = bytes:byte(i * 2 + 1, i * 2 + 2)
    return (lo or 0) + (hi or 0) * 256
  end

  local function palBytes(list)
    local out = {}
    for i = 0, 15 do
      local c = list[i] or 0
      out[#out + 1] = string.char(c % 256, floor(c / 256) % 256)
    end
    return table.concat(out)
  end

  -- pokeemerald/src/util.c:264
  local function blendPal(bytes, coeff, target)
    local tr, tg, tb = target[1], target[2], target[3]
    local out = {}
    for i = 0, 15 do
      local c = palColor(bytes, i)
      local r, g, b = c % 32, floor(c / 32) % 32, floor(c / 1024) % 32
      r = r + bit.arshift((tr - r) * coeff, 4)
      g = g + bit.arshift((tg - g) * coeff, 4)
      b = b + bit.arshift((tb - b) * coeff, 4)
      out[i] = r + g * 32 + b * 1024
    end
    return palBytes(out)
  end

  local function blackRange(bytes, lo, hi)
    local out = {}
    for i = 0, 15 do out[i] = (i >= lo and i <= hi) and 0 or palColor(bytes, i) end
    return palBytes(out)
  end

  local function squaresInit(fx, margins)
    local C = H.getChrome()
    fx.sqPal15 = C.assetPalette("frontier_squares_filled", 1, 0)
    fx.sqPal14 = fx.sqPal15
    fx.sqKey = "filled"
    fx.sqMap = {}
    fx.sqHofs, fx.sqVofs = 0, 0
    if margins then
      for y = 0, 31 do
        fx.sqMap[y * 32] = { blank = true, pal = 15 }
        fx.sqMap[y * 32 + 30 - MARGIN_SIZE] = { blank = true, pal = 15 }
      end
    end
  end

  local function putSquare(fx, tx, ty, pal)
    for sy = 0, SQUARE_SIZE - 1 do
      for sx = 0, SQUARE_SIZE - 1 do
        fx.sqMap[band(ty + sy, 31) * 32 + band(tx + sx, 31)] = { sx = sx, sy = sy, pal = pal }
      end
    end
  end

  local function eraseSquare(fx, tx, ty)
    for sy = 0, SQUARE_SIZE - 1 do
      for sx = 0, SQUARE_SIZE - 1 do
        fx.sqMap[band(ty + sy, 31) * 32 + band(tx + sx, 31)] = { blank = true, pal = 15 }
      end
    end
  end

  local SQ_QUAD = {}

  local function drawSquares(fx, R, G)
    if not fx.sqMap then return end
    local slot = fx.pal.slots[15]
    local mul = 1 - math.min(16, slot and slot.y or 0) / 16
    if mul <= 0 then return end
    local C = H.getChrome()
    local blankIdx = C.rseManifest().squaresBlankTile[fx.sqKey]
    local imgs = {}
    local function images(pal)
      local hit = imgs[pal]
      if hit then return hit end
      local bytes = pal == 14 and fx.sqPal14 or fx.sqPal15
      hit = {
        sq = C.assetImage("frontier_squares_" .. fx.sqKey, bytes),
        blank = C.indexedImage("frontier_squares_blank_" .. fx.sqKey, blankIdx, 8, 8, bytes),
      }
      imgs[pal] = hit
      return hit
    end
    local q = SQ_QUAD[1]
    if not q then
      q = G.newQuad(0, 0, 8, 8, 32, 32)
      SQ_QUAD[1] = q
    end
    G.setColor(mul, mul, mul, 1)
    for idx, e in pairs(fx.sqMap) do
      local tx, ty = idx % 32, floor(idx / 32)
      local bx = band(tx * 8 - fx.sqHofs, 255)
      local y = band(ty * 8 - fx.sqVofs, 255)
      if y > 248 then y = y - 256 end
      if y < DH and y > -8 then
        local set = images(e.pal)
        for _, x in ipairs({ bx - 256, bx, bx + 256 }) do
          if x + 8 > R.X0 and x < R.X1 then
            if e.blank then
              if set.blank then
                local x0 = (x == 0) and R.X0 or x
                local x1 = (x + 8 == DW) and R.X1 or x + 8
                G.draw(set.blank, x0, y, 0, (x1 - x0) / 8, 1)
              end
            elseif set.sq then
              q:setViewport(e.sx * 8, e.sy * 8, 8, 8, 32, 32)
              G.draw(set.sq, q, x, y)
            end
          end
        end
      end
    end
    G.setColor(1, 1, 1, 1)
  end

  -- pokeemerald/src/battle_transition.c:4630
  local function squaresEnd(fx)
    fadeScreenBlack(fx)
    fx.done = true
    return false
  end

  -- pokeemerald/src/battle_transition.c:4432
  DEF[ID.FRONTIER_SQUARES] = {
    funcs = {
      -- pokeemerald/src/battle_transition.c:4447
      function(fx)
        squaresInit(fx, true)
        fx.t.posX, fx.t.posY, fx.t.rowPos = MARGIN_SIZE, 0, 0
        fx.t.shrinkState, fx.t.shrinkTimer, fx.t.shrinkDelay = 0, 0, 10
        fx.state = 1
        return false
      end,
      -- pokeemerald/src/battle_transition.c:4469
      function(fx)
        local t = fx.t
        putSquare(fx, t.posX, t.posY, 15)
        t.posX = t.posX + SQUARE_SIZE
        t.rowPos = t.rowPos + 1
        if t.rowPos == PER_ROW then
          t.posX = MARGIN_SIZE
          t.posY = t.posY + SQUARE_SIZE
          t.rowPos = 0
          if t.posY >= PER_COL * SQUARE_SIZE then fx.state = 2 end
        end
        return false
      end,
      -- pokeemerald/src/battle_transition.c:4491
      function(fx)
        local t = fx.t
        local fire = t.shrinkTimer >= t.shrinkDelay
        t.shrinkTimer = t.shrinkTimer + 1
        if fire then
          local s = t.shrinkState
          if s == 0 then
            fx.sqPal15 = blackRange(fx.sqPal15, 10, 14)
          elseif s == 1 then
            fx.pal:blend(Pal.ALL - 2 ^ 15, 16, Pal.BLACK)
            fx.sqKey = "empty"
          elseif s == 2 then
            fx.sqKey = "shrink1"
          elseif s == 3 then
            fx.sqKey = "shrink2"
          else
            fx.sqMap = {}
            fx.state = 3
            return false
          end
          t.shrinkTimer = 0
          t.shrinkState = s + 1
        end
        return false
      end,
      squaresEnd,
    },
    post = drawSquares,
  }

  -- pokeemerald/src/battle_transition.c:4437
  DEF[ID.FRONTIER_SQUARES_SPIRAL] = {
    funcs = {
      function(fx)
        squaresInit(fx, true)
        fx.sqPal14 = blendPal(fx.sqPal15, 8, Pal.BLACK)
        fx.t.squareNum = NUM_SQUARES - 1
        fx.t.fadeFlag = 0
        fx.state = 1
        return false
      end,
      -- pokeemerald/src/battle_transition.c:4564
      function(fx)
        local t = fx.t
        local pos = SPIRAL_POS[t.squareNum + 1]
        putSquare(fx, SQUARE_SIZE * (pos % PER_ROW) + MARGIN_SIZE, SQUARE_SIZE * floor(pos / PER_ROW), 15)
        t.squareNum = t.squareNum - 1
        if t.squareNum < 0 then fx.state = 2 end
        return false
      end,
      -- pokeemerald/src/battle_transition.c:4583
      function(fx)
        fx.sqPal14 = blendPal(fx.sqPal15, 3, Pal.BLACK)
        fx.pal:blend(Pal.ALL - 2 ^ 15 - 2 ^ 14, 16, Pal.BLACK)
        fx.t.squareNum = 0
        fx.t.fadeFlag = 0
        fx.state = 3
        return false
      end,
      -- pokeemerald/src/battle_transition.c:4596
      function(fx)
        local t = fx.t
        t.fadeFlag = bit.bxor(t.fadeFlag, 1)
        if t.fadeFlag ~= 0 then
          local pos = SPIRAL_POS[t.squareNum + 1]
          putSquare(fx, SQUARE_SIZE * (pos % PER_ROW) + MARGIN_SIZE, SQUARE_SIZE * floor(pos / PER_ROW), 14)
        else
          if t.squareNum > 0 then
            local pos = SPIRAL_POS[t.squareNum]
            eraseSquare(fx, SQUARE_SIZE * (pos % PER_ROW) + MARGIN_SIZE, SQUARE_SIZE * floor(pos / PER_ROW))
          end
          t.squareNum = t.squareNum + 1
        end
        if t.squareNum >= NUM_SQUARES then fx.state = 4 end
        return false
      end,
      squaresEnd,
    },
    post = drawSquares,
  }

  local function scrollXY(pos)
    return SQUARE_SIZE * floor(pos / (PER_ROW + 1)) + MARGIN_SIZE, SQUARE_SIZE * (pos % (PER_ROW + 1))
  end

  -- pokeemerald/src/battle_transition.c:4442
  DEF[ID.FRONTIER_SQUARES_SCROLL] = {
    funcs = {
      -- pokeemerald/src/battle_transition.c:4659
      function(fx)
        squaresInit(fx, false)
        fx.t.squareNum = 0
        local r = (fx.opts and fx.opts.random or math.random)(0, 65535) % 4
        local dirs = { { 1, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 } }
        fx.scroll = { dx = dirs[r + 1][1], dy = dirs[r + 1][2], flag = 0, x = 0, y = 0 }
        fx.state = 1
        return false
      end,
      -- pokeemerald/src/battle_transition.c:4703
      function(fx)
        local t = fx.t
        local x, y = scrollXY(SCROLL_POS[t.squareNum + 1])
        putSquare(fx, x, y, 15)
        t.squareNum = t.squareNum + 1
        if t.squareNum >= #SCROLL_POS then fx.state = 2 end
        return false
      end,
      -- pokeemerald/src/battle_transition.c:4723
      function(fx)
        fx.pal:blend(Pal.ALL - 2 ^ 15, 16, Pal.BLACK)
        fx.t.squareNum = 0
        fx.state = 3
        return false
      end,
      -- pokeemerald/src/battle_transition.c:4733
      function(fx)
        local t = fx.t
        local x, y = scrollXY(SCROLL_POS[t.squareNum + 1])
        eraseSquare(fx, x, y)
        t.squareNum = t.squareNum + 1
        if t.squareNum >= #SCROLL_POS then
          fx.scroll = nil
          fx.state = 4
        end
        return false
      end,
      -- pokeemerald/src/battle_transition.c:4754
      function(fx)
        fx.sqHofs, fx.sqVofs = 0, 0
        return squaresEnd(fx)
      end,
    },
    -- pokeemerald/src/battle_transition.c:4648
    vblank = function(fx)
      local s = fx.scroll
      if not s then return end
      s.flag = bit.bxor(s.flag, 1)
      if s.flag == 0 then
        fx.sqVofs = band(s.x, 0xFFFF)
        fx.sqHofs = band(s.y, 0xFFFF)
        s.x = s.x + s.dx
        s.y = s.y + s.dy
      end
    end,
    post = drawSquares,
  }

  local function sin2(angle)
    angle = band(angle, 0xFFFF)
    local P = require("src.core.game3.battle.anim_port.g3_pret")
    return P.Sin2(angle)
  end

  -- pokeemerald/src/battle_transition_frontier.c:234
  local TARGETS = { [0] = { 120, 45 }, { 89, 97 }, { 151, 97 } }

  local function slideCircle(x, y, delayX, delayY, speedX, speedY, anim)
    return { kind = "slide", x = x, y = y, x2 = 0, y2 = 0, tx = TARGETS[anim][1], ty = TARGETS[anim][2],
      speedX = speedX, speedY = speedY, delayX = delayX, delayY = delayY, timerX = 0, timerY = 0, anim = anim }
  end

  local function spiralCircle(x, y, angle, rotateSpeed, radiusStart, radiusEnd, radiusDelta, anim)
    return { kind = "spiral", x = x, y = y, x2 = 0, y2 = 0, angle = angle, rotateSpeed = rotateSpeed,
      radius = radiusStart, targetRadius = radiusEnd, radiusDelta = radiusDelta, anim = anim }
  end

  -- pokeemerald/src/battle_transition_frontier.c:365
  local function circlesInit(fx)
    local t = fx.t
    if (t.timer or 0) == 0 then
      t.timer = 1
      fx.logoOn = false
      return false
    end
    fx.circlesLoaded = true
    t.blend, t.fadeTimer = 0, 0
    fx.bld = { 0, 16 }
    t.timer = 0
    fx.state = fx.state + 1
    return true
  end

  -- pokeemerald/src/battle_transition_frontier.c:420
  local function waitCircles(fx)
    for _, s in ipairs(fx.sprites) do
      if not s.stopped then return false end
    end
    fx.state = fx.state + 1
    return false
  end

  -- pokeemerald/src/battle_transition_frontier.c:391
  local function fadeInCenter(fx)
    local t = fx.t
    if t.blend == 0 then fx.logoOn = true end
    if t.blend == 16 then
      if t.fadeTimer == 31 then
        fx.pal:beginFade(Pal.ALL, -1, 0, 16, Pal.BLACK)
        fx.state = fx.state + 1
      else
        t.fadeTimer = t.fadeTimer + 1
      end
    else
      t.blend = t.blend + 1
      fx.bld = { t.blend, 16 - t.blend }
    end
    return false
  end

  local function circlesEnd(fx)
    if not fx.pal:fadeActive() then
      fx.sprites = {}
      fx.done = true
    end
    return false
  end

  local CIRCLE_QUAD = {}

  local function drawCircles(fx, R, G)
    if not fx.circlesLoaded then return end
    local C = H.getChrome()
    local info = C.rseManifest().logoCircles
    local img = C.assetImage("frontier_logo_circles")
    local objSlot = fx.pal.slots[16]
    local objMul = 1 - math.min(16, objSlot and objSlot.y or 0) / 16
    if img and objMul > 0 then
      local q = CIRCLE_QUAD[1]
      if not q then
        local iw, ih = img:getDimensions()
        q = G.newQuad(0, 0, info.w, info.h, iw, ih)
        CIRCLE_QUAD[1] = q
      end
      local iw, ih = img:getDimensions()
      G.setColor(objMul, objMul, objMul, 1)
      for i = #fx.sprites, 1, -1 do
        local s = fx.sprites[i]
        local frame = info.frames[s.anim + 1] or s.anim
        q:setViewport(0, frame * info.h, info.w, info.h, iw, ih)
        G.draw(img, q, s.x + s.x2 - info.w / 2, s.y + s.y2 - info.h / 2)
      end
    end
    if fx.logoOn then
      local logo = C.assetImage("frontier_logo_center", C.assetPalette("frontier_logo_center", 1, 0))
      local bgSlot = fx.pal.slots[15]
      local bgMul = 1 - math.min(16, bgSlot and bgSlot.y or 0) / 16
      local ba = fx.bld or { 0, 16 }
      local eva, evb = math.min(16, ba[1]), math.min(16, ba[2])
      local function hofs() return 0 end
      local function vofs() return -5 end
      if logo then
        if evb < 16 then
          G.setColor(0, 0, 0, 1 - evb / 16)
          A.drawRows(G, logo, hofs, vofs, DW, DH)
        end
        if eva > 0 and bgMul > 0 then
          G.setBlendMode("add")
          local k = eva / 16 * bgMul
          G.setColor(k, k, k, 1)
          A.drawRows(G, logo, hofs, vofs, DW, DH)
          G.setBlendMode("alpha")
        end
      end
    end
    G.setColor(1, 1, 1, 1)
  end

  -- pokeemerald/src/battle_transition_frontier.c:267
  local function circleSprite(fx, s)
    if s.stopped then return end
    if s.kind == "slide" then
      if s.x == s.tx and s.y == s.ty then
        s.stopped = true
        return
      end
      if s.timerX == s.delayX then
        s.x = s.x + s.speedX
        s.timerX = 0
      else
        s.timerX = s.timerX + 1
      end
      if s.timerY == s.delayY then
        s.y = s.y + s.speedY
        s.timerY = 0
      else
        s.timerY = s.timerY + 1
      end
    else
      -- pokeemerald/src/battle_transition_frontier.c:332
      s.x2 = bit.arshift(sin2(s.angle) * s.radius, 12)
      s.y2 = bit.arshift(sin2(s.angle + 90) * s.radius, 12)
      s.angle = (s.angle + s.rotateSpeed) % 360
      if s.radius ~= s.targetRadius then
        s.radius = s.radius + s.radiusDelta
      else
        s.stopped = true
      end
    end
  end

  local function circlesDef(create)
    return {
      funcs = { circlesInit, create, waitCircles, fadeInCenter, circlesEnd },
      sprite = circleSprite,
      post = drawCircles,
    }
  end

  local function allAtOnce(list)
    return function(fx)
      for _, args in ipairs(list) do
        local f = args.spiral and spiralCircle or slideCircle
        fx.sprites[#fx.sprites + 1] = f(unpack(args))
      end
      fx.state = fx.state + 1
      return false
    end
  end

  local function inSequence(list)
    return function(fx)
      local t = fx.t
      local i = floor(t.timer / 16)
      if t.timer % 16 == 0 and list[i + 1] then
        local args = list[i + 1]
        local f = args.spiral and spiralCircle or slideCircle
        fx.sprites[#fx.sprites + 1] = f(unpack(args))
        if i + 1 == #list then fx.state = fx.state + 1 end
      end
      t.timer = t.timer + 1
      return false
    end
  end

  -- pokeemerald/src/battle_transition_frontier.c:433
  local MEET = { { 120, -51, 0, 0, 0, 2, 0 }, { -7, 193, 0, 0, 2, -2, 1 }, { 247, 193, 0, 0, -2, -2, 2 } }
  -- pokeemerald/src/battle_transition_frontier.c:459
  local CROSS = { { 120, 197, 0, 0, 0, -4, 0 }, { 241, 59, 0, 1, -4, 2, 1 }, { -1, 59, 0, 1, 4, 2, 2 } }
  -- pokeemerald/src/battle_transition_frontier.c:485
  local ASYM = { { 120, 45, 12, 4, 128, 0, -4, 0, spiral = true }, { 89, 97, 252, 4, 128, 0, -4, 1, spiral = true },
    { 151, 97, 132, 4, 128, 0, -4, 2, spiral = true } }
  -- pokeemerald/src/battle_transition_frontier.c:511
  local SYM = { { 120, 80, 284, 8, 131, 35, -3, 0, spiral = true }, { 120, 80, 44, 8, 131, 35, -3, 1, spiral = true },
    { 121, 80, 164, 8, 131, 35, -3, 2, spiral = true } }
  -- pokeemerald/src/battle_transition_frontier.c:537
  local MEET_SEQ = { { 120, -51, 0, 0, 0, 4, 0 }, { -7, 193, 0, 0, 4, -4, 1 }, { 247, 193, 0, 0, -4, -4, 2 } }
  -- pokeemerald/src/battle_transition_frontier.c:573
  local CROSS_SEQ = { { 120, 197, 0, 0, 0, -8, 0 }, { 241, 78, 0, 0, -8, 1, 1 }, { -1, 78, 0, 0, 8, 1, 2 } }

  DEF[ID.FRONTIER_CIRCLES_MEET] = circlesDef(allAtOnce(MEET))
  DEF[ID.FRONTIER_CIRCLES_CROSS] = circlesDef(allAtOnce(CROSS))
  DEF[ID.FRONTIER_CIRCLES_ASYMMETRIC_SPIRAL] = circlesDef(allAtOnce(ASYM))
  DEF[ID.FRONTIER_CIRCLES_SYMMETRIC_SPIRAL] = circlesDef(allAtOnce(SYM))
  DEF[ID.FRONTIER_CIRCLES_MEET_IN_SEQ] = circlesDef(inSequence(MEET_SEQ))
  DEF[ID.FRONTIER_CIRCLES_CROSS_IN_SEQ] = circlesDef(inSequence(CROSS_SEQ))
  DEF[ID.FRONTIER_CIRCLES_ASYMMETRIC_SPIRAL_IN_SEQ] = circlesDef(inSequence(ASYM))
  DEF[ID.FRONTIER_CIRCLES_SYMMETRIC_SPIRAL_IN_SEQ] = circlesDef(inSequence(SYM))
end

return M
