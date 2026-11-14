local bit = require("bit")

local band, bor, lshift, rshift, arshift = bit.band, bit.bor, bit.lshift, bit.rshift, bit.arshift
local floor = math.floor

local M = {}

function M.register(DEF, ID, H)
  local DW, DH = H.DW, H.DH
  local Sin, s16, u16 = H.Sin, H.s16, H.u16
  local winH, copyBuf, setCircularMask, fadeScreenBlack = H.winH, H.copyBuf, H.setCircularMask, H.fadeScreenBlack
  local winHSpans = H.winHSpans
  local WSPANS = {}

  -- pokeemerald/src/battle_transition.c:3044
  local function blackholeInit(fx)
    fx.hole1 = {}
    for i = 0, DH - 1 do fx.hole1[i] = 0 end
    fx.t.radius = 1
    fx.t.growSpeed = 256
    fx.t.flag = false
    fx.state = fx.state + 1
    return false
  end

  local function holeVblank(fx)
    if fx.T.vblankDma and fx.hole1 then copyBuf(fx.hole1, fx.buf0, DH) end
  end

  local function holeSpans(fx, y, out)
    if not fx.hole1 then return 0 end
    local l, r = winH(fx.hole1[y])
    if not l then return 0 end
    out[1], out[2] = l, r
    return 1
  end

  -- pokeemerald/src/battle_transition.c:618
  local VIBRATIONS = { -6, 4 }

  -- pokeemerald/src/battle_transition.c:3033
  DEF[ID.BLACKHOLE] = {
    funcs = {
      blackholeInit,
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
          fx.T.vblankDma = false
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
    vblank = holeVblank,
    winSpans = holeSpans,
  }

  -- pokeemerald/src/battle_transition.c:3123
  DEF[ID.BLACKHOLE_PULSATE] = {
    funcs = {
      blackholeInit,
      function(fx)
        local t = fx.t
        fx.T.vblankDma = false
        if not t.flag then
          t.flag = true
          t.sinIndex = 2
          t.amplitude = 2
        end
        if t.radius > DH then t.radius = DH end
        setCircularMask(fx.buf0, DW / 2, DH / 2, t.radius)
        if t.radius == DH then
          fadeScreenBlack(fx)
          fx.done = true
        end
        local index = u16(t.sinIndex)
        local amplitude
        if band(t.sinIndex, 0xFF) <= 128 then
          amplitude = t.amplitude
          t.sinIndex = s16(t.sinIndex + 8)
        else
          amplitude = t.amplitude - 1
          t.sinIndex = s16(t.sinIndex + 16)
        end
        t.radius = s16(t.radius + Sin(band(index, 0xFF), amplitude))
        if t.radius <= 0 then t.radius = 1 end
        if t.sinIndex >= 0xFF then
          t.sinIndex = arshift(t.sinIndex, 8)
          t.amplitude = t.amplitude + 1
        end
        fx.T.vblankDma = true
        return false
      end,
    },
    vblank = holeVblank,
    winSpans = holeSpans,
  }

  -- pokeemerald/src/battle_transition.c:600
  local SECTION_Y = { 39, DH - 41 }
  local MOVE_DIRS = { 1, -1 }

  local function shredCell(fx, y, left, cameraX)
    local b = fx.shred0
    local p4, p3, p1 = y + DH * 2, y + DH * 3, y + DH * 4
    local finished = 0
    if b[p4] >= DW then
      b[p4] = DW
      finished = 1
    else
      b[p4] = u16(b[p4] + rshift(b[p3], 8))
      if b[p1] <= 0x7F then b[p1] = u16(b[p1] * 2) end
      if b[p3] <= 0xFFF then b[p3] = u16(b[p3] + b[p1]) end
    end
    if left then
      b[y] = u16(cameraX - b[p4])
      b[y + DH] = u16(bor(lshift(b[p4], 8), DW + 1))
    else
      b[y] = u16(cameraX + b[p4])
      b[y + DH] = u16(DW - b[p4])
    end
    return finished
  end

  -- pokeemerald/src/battle_transition.c:2840
  DEF[ID.SHRED_SPLIT] = {
    funcs = {
      -- pokeemerald/src/battle_transition.c:2845
      function(fx)
        local Player = package.loaded["src.core.game3.player"]
        local cameraX = tonumber(fx.opts and fx.opts.cameraX)
          or band(((Player and Player.cellX) or 0) * 16, 0xFF)
        fx.t.cameraX = cameraX
        fx.shred0, fx.shred1 = {}, {}
        for i = 0, DH * 6 - 1 do fx.shred0[i] = 0 end
        for i = 0, DH - 1 do
          fx.shred1[i] = u16(cameraX)
          fx.shred1[DH + i] = DW
          fx.shred0[i] = u16(cameraX)
          fx.shred0[DH + i] = DW
          fx.shred0[DH * 2 + i] = 0
          fx.shred0[DH * 3 + i] = 256
          fx.shred0[DH * 4 + i] = 1
        end
        fx.t.delayTimer = 0
        fx.t.extent = 0
        fx.t.delay = 7
        fx.state = 1
        return true
      end,
      -- pokeemerald/src/battle_transition.c:2880
      function(fx)
        local t = fx.t
        local cameraX = t.cameraX or 0
        fx.T.vblankDma = false
        local finished = 0
        for i = 0, t.extent do
          for j = 1, 2 do
            for k = 1, 2 do
              local y = s16(SECTION_Y[j] + MOVE_DIRS[k] * -i * 2)
              if y >= 0 and (y ~= DH / 2 - 1 or j ~= 2) then
                finished = finished + shredCell(fx, y, false, cameraX)
                if i == 0 then break end
              end
            end
          end
          for j = 1, 2 do
            for k = 1, 2 do
              local y = s16(SECTION_Y[j] + 1 + MOVE_DIRS[k] * -i * 2)
              if y <= DH and (y ~= DH / 2 or j ~= 2) then
                finished = finished + shredCell(fx, y, true, cameraX)
                if i == 0 then break end
              end
            end
          end
        end
        t.delayTimer = t.delayTimer - 1
        if t.delayTimer < 0 then t.delayTimer = 0 end
        if t.delayTimer <= 0 and t.extent + 1 <= DH / 8 then
          t.delayTimer = t.delay
          t.extent = t.extent + 1
        end
        if band(finished, 0xFF) >= DH then fx.state = 2 end
        fx.T.vblankDma = true
        return false
      end,
      -- pokeemerald/src/battle_transition.c:2992
      function(fx)
        local done = true
        for i = 0, DH - 1 do
          local v = fx.shred1[i]
          if v ~= DW and v ~= 0xFF10 then done = false end
        end
        if done then fx.state = 3 end
        return false
      end,
      function(fx)
        fadeScreenBlack(fx)
        fx.done = true
        return false
      end,
    },
    vblank = function(fx)
      if fx.T.vblankDma and fx.shred0 then copyBuf(fx.shred1, fx.shred0, DH * 2) end
    end,
    rowSpans = function(fx, y, R, out)
      if not fx.shred1 then return 0 end
      local win
      if y < 0 or y > DH - 1 then
        local e = y < 0 and 0 or DH - 1
        local cameraX = fx.t.cameraX or 0
        if band(e, 1) == 0 then
          -- pokeemerald/src/battle_transition.c:2959
          win = bor(lshift(u16(cameraX - fx.shred1[e]), 8), DW + 1)
        else
          -- pokeemerald/src/battle_transition.c:2924
          win = DW - u16(fx.shred1[e] - cameraX)
        end
      else
        win = fx.shred1[DH + y]
      end
      local k = winHSpans(win, WSPANS)
      local n, x = 0, 0
      for i = 1, k do
        local a, b = WSPANS[2 * i - 1], WSPANS[2 * i]
        if a > x then
          n = n + 1
          out[2 * n - 1], out[2 * n] = x == 0 and R.X0 or R.hmap(x), R.hmap(a)
        end
        x = b
      end
      if x < DW then
        n = n + 1
        out[2 * n - 1], out[2 * n] = x == 0 and R.X0 or R.hmap(x), R.X1
      end
      return n
    end,
    shift = function(fx, y, R)
      if not fx.shred1 then return 0, 0 end
      local yy = y
      if yy < 0 then yy = 0 end
      if yy > DH - 1 then yy = DH - 1 end
      return R.hdist(s16(fx.shred1[yy]) - (fx.t.cameraX or 0)), 0
    end,
    redraw = true,
  }

  local SPIRAL_END, SPIRAL_REBOUND = -1, -2
  local MOVE_RIGHT, MOVE_LEFT, MOVE_UP, MOVE_DOWN = 1, 2, 3, 4
  -- pokeemerald/src/battle_transition.c:645
  local MAJOR = {
    { MOVE_RIGHT, 27, 275, SPIRAL_END },
    { MOVE_DOWN, 507, SPIRAL_REBOUND },
    { MOVE_LEFT, 486, SPIRAL_END },
    { MOVE_UP, 262, SPIRAL_END },
    { MOVE_UP, 244, 28, SPIRAL_END },
    { MOVE_LEFT, 229, SPIRAL_END },
    { MOVE_DOWN, 517, SPIRAL_END },
    { MOVE_RIGHT, 540, SPIRAL_END },
  }
  local MINOR = {
    { MOVE_DOWN, 573, 309, SPIRAL_END },
    { MOVE_LEFT, 548, SPIRAL_REBOUND },
    { MOVE_UP, 196, SPIRAL_END },
    { MOVE_RIGHT, 213, SPIRAL_END },
    { MOVE_LEFT, 295, 32, SPIRAL_END },
    { MOVE_DOWN, 455, SPIRAL_END },
    { MOVE_RIGHT, 474, SPIRAL_END },
    { MOVE_UP, 58, SPIRAL_END },
  }
  local TABLES = { MAJOR, MINOR }

  -- pokeemerald/src/battle_transition.c:3282
  local function updateLine(tbl, line)
    local md = tbl[line.state + 1]
    if md[line.moveIndex + 1] == SPIRAL_END then return false end
    local dir = md[1]
    if dir == MOVE_RIGHT then
      line.position = line.position + 1
    elseif dir == MOVE_LEFT then
      line.position = line.position - 1
    elseif dir == MOVE_UP then
      line.position = line.position - 32
    elseif dir == MOVE_DOWN then
      line.position = line.position + 32
    end
    if line.position >= 640 or md[line.moveIndex + 1] == SPIRAL_END then return false end
    if not line.outward and md[line.moveIndex + 1] == SPIRAL_REBOUND then
      line.outward = true
      line.moveIndex = 1
      line.position = line.reboundPosition
      line.state = 4
    end
    if line.position == md[line.moveIndex + 1] then
      line.state = line.state + 1
      if line.outward then
        if line.state > 7 then
          line.moveIndex = line.moveIndex + 1
          line.state = 4
        end
      elseif line.state > 3 then
        line.moveIndex = line.moveIndex + 1
        line.state = 0
      end
    end
    return true
  end

  -- pokeemerald/src/battle_transition.c:3184
  DEF[ID.RECTANGULAR_SPIRAL] = {
    funcs = {
      -- pokeemerald/src/battle_transition.c:3189
      function(fx)
        fx.spiralTiles = {}
        fx.lines = {
          { state = 0, position = -1, moveIndex = 1, reboundPosition = 308, outward = false },
          { state = 0, position = -1, moveIndex = 1, reboundPosition = 308, outward = false },
          { state = 0, position = -3, moveIndex = 1, reboundPosition = 307, outward = false },
          { state = 0, position = -3, moveIndex = 1, reboundPosition = 307, outward = false },
        }
        fx.state = 1
        return false
      end,
      -- pokeemerald/src/battle_transition.c:3233
      function(fx)
        local done = true
        for _ = 1, 2 do
          for j = 0, 3 do
            local line = fx.lines[j + 1]
            if updateLine(TABLES[floor(j / 2) + 1], line) then
              done = false
              local position = line.position
              if j % 2 == 1 then position = 637 - position end
              local idx = band(position, 0x3FF)
              fx.spiralTiles[idx] = true
            end
          end
        end
        if done then fx.state = 2 end
        return false
      end,
      function(fx)
        fadeScreenBlack(fx)
        fx.done = true
        return false
      end,
    },
    draw = function(fx, R, G)
      if not fx.spiralTiles then return end
      local C = H.getChrome()
      local img = C and C.gridFrame and C.gridFrame(14)
      if not img then return end
      G.setColor(1, 1, 1, 1)
      for idx in pairs(fx.spiralTiles) do
        local tx, y = idx % 32, floor(idx / 32) * 8
        if y < DH then
          for _, x in ipairs({ tx * 8 - 256, tx * 8 }) do
            if x + 8 > R.X0 and x < R.X1 then G.draw(img, x, y) end
          end
        end
      end
    end,
  }
end

return M
