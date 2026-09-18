local P = require("src.core.game3.battle.anim_port.g3_pret")

local C, T = {}, {}
local band, rshift = P.band, P.rshift

local function attackerFadeToInvisibleStep(t, vm)
  local d = t.data
  local blendA = P.u8(rshift(P.u16(d[1]), 8))
  local blendB = P.u8(d[1])
  if d[2] == P.u8(d[0]) then
    blendA = P.u8(blendA + 1)
    blendB = P.u8(blendB - 1)
    d[1] = P.s16(blendB + blendA * 256)
    P.setBld(vm, blendB, blendA)
    local p = t._p
    if p and P.isMonBg(t._side) then p.alpha = P.bldAlphaValue(vm) end
    d[2] = 0
    if blendA == 16 then
      if p then
        p.visible = false
        p.alpha = 1
      end
      P.DestroyAnimVisualTask(t)
    end
  else
    d[2] = d[2] + 1
  end
end

-- pokefirered/src/battle_anim_dark.c:187
T.AttackerFadeToInvisible = P.task(function(t, vm)
  local d = t.data
  d[0] = t.ga[0]
  t._side = P.atk(vm)
  t._p = P.monPresent(t._side)
  d[1] = 16
  P.setBld(vm, 16, 0)
  if t._p and P.isMonBg(t._side) then t._p.alpha = P.bldAlphaValue(vm) end
  t.fn = attackerFadeToInvisibleStep
end)

local function attackerFadeFromInvisibleStep(t, vm)
  local d = t.data
  local blendA = P.u8(rshift(P.u16(d[1]), 8))
  local blendB = P.u8(d[1])
  if d[2] == P.u8(d[0]) then
    blendA = P.u8(blendA - 1)
    blendB = P.u8(blendB + 1)
    d[1] = P.s16(blendA * 256 + blendB)
    P.setBld(vm, blendB, blendA)
    local p = t._p
    if p then p.alpha = P.bldAlphaValue(vm) end
    d[2] = 0
    if blendA == 0 then
      P.setBld(vm, nil)
      if p then
        p.visible = true
        p.alpha = 1
      end
      P.DestroyAnimVisualTask(t)
    end
  else
    d[2] = d[2] + 1
  end
end

-- pokefirered/src/battle_anim_dark.c:226
T.AttackerFadeFromInvisible = P.task(function(t, vm)
  local d = t.data
  d[0] = t.ga[0]
  d[1] = 0x1000
  t._side = P.atk(vm)
  t._p = P.monPresent(t._side)
  t.fn = attackerFadeFromInvisibleStep
  P.setBld(vm, 0, 16)
  if t._p then
    t._p.visible = true
    t._p.alpha = P.bldAlphaValue(vm)
  end
end)

-- pokefirered/src/battle_anim_dark.c:259
T.InitAttackerFadeFromInvisible = P.task(function(t, vm)
  P.setBld(vm, 0, 16)
  local p = P.monPresent(P.atk(vm))
  if p then
    p.visible = true
    p.alpha = P.bldAlphaValue(vm)
  end
  P.DestroyAnimVisualTask(t)
end)

local function biteStep2(s)
  local d = s.data
  d[4] = P.s16(d[4] - d[0])
  d[5] = P.s16(d[5] - d[1])
  s.ox = P.shr(d[4], 8)
  s.oy = P.shr(d[5], 8)
  d[3] = d[3] - 1
  if d[3] == 0 then P.DestroySpriteAndMatrix(s) end
end

local function biteStep1(s)
  local d = s.data
  d[4] = P.s16(d[4] + d[0])
  d[5] = P.s16(d[5] + d[1])
  s.ox = P.shr(d[4], 8)
  s.oy = P.shr(d[5], 8)
  d[3] = d[3] + 1
  if d[3] == d[2] then s.callbackFn = biteStep2 end
end

-- pokefirered/src/battle_anim_dark.c:311
C.Bite = P.cb(function(s, vm)
  s.x = s.x + s.ga[0]
  s.y = s.y + s.ga[1]
  P.StartSpriteAffineAnim(s, s.ga[2])
  s.data[0] = s.ga[3]
  s.data[1] = s.ga[4]
  s.data[2] = s.ga[5]
  s.callbackFn = biteStep1
end)

local function tearDropStep(s)
  if P.TranslateAnimHorizontalArc(s) then P.DestroySpriteAndMatrix(s) end
end

-- pokefirered/src/battle_anim_dark.c:343
C.TearDrop = P.cb(function(s, vm)
  local side = (s.ga[0] == P.ANIM_ATTACKER) and P.atk(vm) or P.tgt(vm)
  local xOffset = 20
  s.imageValue = s.imageValue + 4
  local a = s.ga[1]
  if a == 0 then
    s.x = P.coordAttr(vm, side, P.ATTR_RIGHT) - 8
    s.y = P.coordAttr(vm, side, P.ATTR_TOP) + 8
  elseif a == 1 then
    s.x = P.coordAttr(vm, side, P.ATTR_RIGHT) - 14
    s.y = P.coordAttr(vm, side, P.ATTR_TOP) + 16
  elseif a == 2 then
    s.x = P.coordAttr(vm, side, P.ATTR_LEFT) + 8
    s.y = P.coordAttr(vm, side, P.ATTR_TOP) + 8
    P.StartSpriteAffineAnim(s, 1)
    xOffset = -20
  elseif a == 3 then
    s.x = P.coordAttr(vm, side, P.ATTR_LEFT) + 14
    s.y = P.coordAttr(vm, side, P.ATTR_TOP) + 16
    P.StartSpriteAffineAnim(s, 1)
    xOffset = -20
  end
  s.data[0] = 32
  s.data[2] = s.x + xOffset
  s.data[4] = s.y + 12
  s.data[5] = -12
  P.InitAnimArcTranslation(s)
  s.callbackFn = tearDropStep
end)

local rowQuad

local function mementoDraw(t)
  if not (love and love.graphics) then return end
  local d = t.data
  local img = t._img
  if not img or not t._map then return end
  local wl, wr = d[14], d[15]
  if wr <= wl then return end
  local b = t._vm and t._vm.bldAlpha
  local evb = b and (b.evb or b[2]) or 0
  if evb > 16 then evb = 16 end
  local a = 1 - evb / 16
  if a <= 0 then return end
  local iw, ih = img:getDimensions()
  local left = t._picLeft
  local xa = math.max(left, wl, 0)
  local xb = math.min(left + iw, wr, 240)
  if xb <= xa then return end
  if not rowQuad then rowQuad = love.graphics.newQuad(0, 0, 1, 1, iw, ih) end
  local flip = t._flip
  love.graphics.setColor(0, 0, 0, a)
  for i = 0, 111 do
    local src = t._map[i]
    if src then
      local r = src - t._picTop
      if r >= 0 and r < ih then
        if flip then
          rowQuad:setViewport(iw - (xb - left), r, xb - xa, 1, iw, ih)
          love.graphics.draw(img, rowQuad, xb, i, 0, -1, 1)
        else
          rowQuad:setViewport(xa - left, r, xb - xa, 1, iw, ih)
          love.graphics.draw(img, rowQuad, xa, i)
        end
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

local function doMementoShadowEffect(t)
  local d = t.data
  local map = t._map
  local var2 = P.s16(d[5] - d[4])
  if var2 ~= 0 then
    local var0 = P.div(d[13], var2)
    local var1 = d[6] * 256
    local i = 0
    while i < d[4] do
      if map then map[i] = false end
      i = i + 1
    end
    i = d[4]
    while i <= d[5] do
      if i >= 0 and map then map[i] = P.s16(P.shr(var1, 8)) end
      var1 = var1 + var0
      i = i + 1
    end
    while i < d[7] do
      if i >= 0 and map then map[i] = false end
      i = i + 1
    end
  elseif map then
    for i = 0, 111 do map[i] = false end
  end
end

local function mementoSetup(t, vm, side)
  t._vm = vm
  t._img = P.monImage(vm, side)
  local p = P.monPresent(side)
  local cx, cy = P.monCenter(vm, side)
  t._picLeft = math.floor(cx + 0.5) - 32
  t._picTop = math.floor(cy + 0.5) - 32
  t._flip = p and p.hFlip and true or false
end

local function moveAttackerMementoShadowStep(t, vm)
  local d = t.data
  local k = d[0]
  if k == 0 then
    d[1] = d[1] + 1
    if d[1] > 1 then
      d[1] = 0
      d[2] = d[2] + 1
      if band(d[2], 1) ~= 0 then
        if d[11] ~= 12 then d[11] = d[11] + 1 end
      elseif d[12] ~= 8 then
        d[12] = d[12] - 1
      end
      P.setBld(vm, d[11], d[12])
      if d[11] == 12 and d[12] == 8 then d[0] = d[0] + 1 end
    end
  elseif k == 1 then
    d[4] = d[4] - 8
    doMementoShadowEffect(t)
    if d[4] < d[8] then d[0] = d[0] + 1 end
  elseif k == 2 then
    d[4] = d[4] - 8
    doMementoShadowEffect(t)
    d[14] = d[14] + 4
    d[15] = d[15] - 4
    if d[14] >= d[15] then d[14] = d[15] end
    if d[14] == d[15] then d[0] = d[0] + 1 end
  elseif k == 3 then
    t._map = nil
    d[0] = d[0] + 1
  elseif k == 4 then
    t.draw = nil
    P.DestroyAnimVisualTask(t)
  end
end

-- pokefirered/src/battle_anim_dark.c:391
T.MoveAttackerMementoShadow = P.task(function(t, vm)
  local d = t.data
  local side = P.atk(vm)
  d[7] = P.coord(vm, side, P.COORD_Y) + 31
  d[6] = P.coordAttr(vm, side, P.ATTR_TOP) - 7
  d[5] = d[7]
  d[4] = d[6]
  d[13] = P.s16((d[7] - d[6]) * 256)
  local pos = P.u8(P.coord(vm, side, P.COORD_X))
  d[14] = pos - 32
  d[15] = pos + 32
  if P.isPlayer(side) then d[8] = -12 else d[8] = -64 end
  d[3] = P.isPlayer(side) and 2 or 1
  d[10] = 0
  d[11] = 0
  d[12] = 16
  d[0] = 0
  d[1] = 0
  d[2] = 0
  mementoSetup(t, vm, side)
  t._map = {}
  for i = 0, 111 do t._map[i] = i end
  t.z = 205
  t.draw = mementoDraw
  t.fn = moveAttackerMementoShadowStep
end)

local function moveTargetMementoShadowStep(t, vm)
  local d = t.data
  local k = d[0]
  if k == 0 then
    d[5] = d[5] + 8
    if d[5] >= d[7] then d[5] = d[7] end
    doMementoShadowEffect(t)
    if d[5] == d[7] then d[0] = d[0] + 1 end
  elseif k == 1 then
    if d[15] - d[14] < 0x40 then
      d[14] = d[14] - 4
      d[15] = d[15] + 4
    else
      d[1] = 1
    end
    d[4] = d[4] + 8
    if d[4] >= d[6] then d[4] = d[6] end
    doMementoShadowEffect(t)
    if d[4] == d[6] and d[1] ~= 0 then
      d[1] = 0
      d[0] = d[0] + 1
    end
  elseif k == 2 then
    d[1] = d[1] + 1
    if d[1] > 1 then
      d[1] = 0
      d[2] = d[2] + 1
      if band(d[2], 1) ~= 0 then
        if d[11] ~= 0 then d[11] = d[11] - 1 end
      elseif d[12] < 16 then
        d[12] = d[12] + 1
      end
      P.setBld(vm, d[11], d[12])
      if d[11] == 0 and d[12] == 16 then d[0] = d[0] + 1 end
    end
  elseif k == 3 then
    t._map = nil
    d[0] = d[0] + 1
  elseif k == 4 then
    t.draw = nil
    P.DestroyAnimVisualTask(t)
  end
end

-- pokefirered/src/battle_anim_dark.c:508
T.MoveTargetMementoShadow = P.task(function(t, vm)
  local d = t.data
  local side = P.tgt(vm)
  local k = d[0]
  if k == 0 then
    d[3] = P.isPlayer(side) and 2 or 1
    d[0] = d[0] + 1
  elseif k == 1 then
    d[10] = 0
    d[0] = d[0] + 1
  elseif k == 2 then
    d[7] = P.coord(vm, side, P.COORD_Y) + 31
    d[6] = P.coordAttr(vm, side, P.ATTR_TOP) - 7
    d[13] = P.s16((d[7] - d[6]) * 256)
    local x = P.u8(P.coord(vm, side, P.COORD_X))
    d[14] = x - 4
    d[15] = x + 4
    if P.isPlayer(side) then d[8] = -12 else d[8] = -64 end
    d[4] = d[8]
    d[5] = d[8]
    d[11] = 12
    d[12] = 8
    d[0] = d[0] + 1
  elseif k == 3 then
    d[0] = d[0] + 1
  elseif k == 4 then
    d[0] = 0
    d[1] = 0
    d[2] = 0
    P.setBld(vm, 12, 8)
    t.fn = moveTargetMementoShadowStep
  end
end)

-- pokefirered/src/battle_anim_dark.c:729
T.InitMementoShadow = P.task(function(t, vm)
  local p = P.monPresent(P.atk(vm))
  if p then p.visible = true end
  P.DestroyAnimVisualTask(t)
end)

-- pokefirered/src/battle_anim_dark.c:743
T.MementoHandleBg = P.task(function(t, vm)
  P.DestroyAnimVisualTask(t)
end)

-- pokefirered/src/battle_anim_dark.c:754
C.ClawSlash = P.cb(function(s, vm)
  s.x = s.x + s.ga[0]
  s.y = s.y + s.ga[1]
  P.StartSpriteAnim(s, s.ga[2])
  s.callbackFn = P.RunStoredCallbackWhenAnimEnds
  P.StoreSpriteCallbackInData6(s, P.DestroyAnimSprite)
end)

local function setGreyscaleOrOriginal(p, restore)
  if not p then return end
  if restore then
    p.grayscale = false
    P.monBlend(p, 0, 0)
  else
    p.grayscale = true
  end
end

local POSITION_ID = { [4] = 0, [5] = 2, [6] = 1, [7] = 3 }

-- pokefirered/src/battle_anim_dark.c:869
T.SetGrayscaleOrOriginalPal = P.task(function(t, vm)
  local a = t.ga[0]
  local p
  if a >= 0 and a <= 3 then
    p = P.monSprite(vm, a)
  elseif a >= 4 and a <= 7 then
    local id = POSITION_ID[a]
    local ok = id ~= nil and (id < 2 or require("src.core.game3.battle.anim_coords").spritePresent(nil, id))
    if ok and not P.monHidden(vm, id) then p = P.monPresent(id) end
  end
  if p then setGreyscaleOrOriginal(p, t.ga[1] ~= 0) end
  P.DestroyAnimVisualTask(t)
end)

-- pokefirered/src/battle_anim_dark.c:916
T.GetIsDoomDesireHitTurn = P.task(function(t, vm)
  local turn = tonumber(vm and vm._turn) or 0
  if turn < 2 then P.setRet(vm, 0) end
  if turn == 2 then P.setRet(vm, 1) end
  P.DestroyAnimVisualTask(t)
end)

return { callbacks = C, tasks = T }
