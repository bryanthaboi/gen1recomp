local P = require("src.core.game3.battle.anim_port.g3_pret")

local C, T = {}, {}
local H = {}
local band = P.band

local DISPLAY_WIDTH = 240

function H.sine(i)
  return P.SINE[(math.floor(i) % 256) + 1]
end

function H.bgPriority(vm, side)
  local bp = vm and vm._bgPrio
  return (bp and bp[require("src.core.game3.battle.anim_coords").bgPriorityRank(side)]) or 2
end

function H.monX(vm, side)
  return P.coord(vm, side, P.COORD_X)
end

function H.monY(vm, side)
  return P.coord(vm, side, P.COORD_Y_PIC_DEF)
end

function H.battleSt()
  local B = package.loaded["src.core.game3.battle"] or package.loaded["src.core.game3.battle.init"]
  return B and B._st
end

function H.prepAffine(t, side, cmds)
  local d = t.data
  d[7], d[8], d[9] = 0, 0, 0
  d[10], d[11], d[12] = 0x100, 0x100, 0
  t._aSide = side
  t._aP = side and P.monPresent(side) or nil
  t._aCmds = cmds or {}
end

function H.runAffine(t, vm)
  local d = t.data
  local cmds = t._aCmds
  local p = t._aP
  local c = cmds[d[7] + 1]
  if c == nil or c.e then
    if p then
      p.oy = 0
      P.monResetRotScale(p)
    end
    return false
  elseif c.j then
    d[7] = c.j
  elseif c.l then
    if c.l ~= 0 then
      if d[9] ~= 0 then
        d[9] = d[9] - 1
        if d[9] == 0 then
          d[7] = d[7] + 1
          return true
        end
      else
        d[9] = c.l
      end
      if d[7] == 0 then return true end
      while true do
        d[7] = d[7] - 1
        local prev = cmds[d[7] + 1]
        if prev and prev.l then
          d[7] = d[7] + 1
          return true
        end
        if d[7] == 0 then return true end
      end
    end
    d[7] = d[7] + 1
  else
    if (c.d or 0) == 0 then
      d[10] = c.x or 0
      d[11] = c.y or 0
      d[12] = c.r or 0
      d[7] = d[7] + 1
      c = cmds[d[7] + 1] or {}
    end
    d[10] = P.s16(d[10] + (c.x or 0))
    d[11] = P.s16(d[11] + (c.y or 0))
    d[12] = P.s16(d[12] + (c.r or 0))
    if p then
      P.monRotScale(p, d[10], d[11], P.u16(d[12]))
      P.monYOffsetFromYScale(vm, t._aSide)
    end
    d[8] = d[8] + 1
    if d[8] >= (c.d or 0) then
      d[8] = 0
      d[7] = d[7] + 1
    end
  end
  return true
end

function H.roarStep(s)
  local d = s.data
  d[6] = P.s16(d[6] + d[0])
  d[7] = P.s16(d[7] + d[1])
  s.ox = P.shr(d[6], 8)
  s.oy = P.shr(d[7], 8)
  d[5] = d[5] + 1
  if d[5] == 14 then P.DestroyAnimSprite(s) end
end

-- pokefirered/src/battle_anim_effects_3.c:3839
C.RoarNoiseLine = P.cb(function(s, vm)
  local d = s.data
  if not P.atkIsPlayer(vm) then s.ga[0] = -s.ga[0] end
  s.x = P.coordAtk(vm, P.COORD_X) + s.ga[0]
  s.y = P.coordAtk(vm, P.COORD_Y) + s.ga[1]
  if s.ga[2] == 0 then
    d[0] = 0x280
    d[1] = -0x280
  elseif s.ga[2] == 1 then
    s._vFlipBase = true
    d[0] = 0x280
    d[1] = 0x280
  else
    P.StartSpriteAnim(s, 1)
    d[0] = 0x280
  end
  if not P.atkIsPlayer(vm) then
    d[0] = -d[0]
    s._hFlipBase = true
  end
  s.callbackFn = H.roarStep
end)

function H.glareDotCoords(startX, startY, endX, endY, pairMax, pairNum)
  if pairNum == 0 then return startX, startY end
  if pairNum >= pairMax then return endX, endY end
  pairMax = pairMax - 1
  local x2 = startX * 256 + pairNum * P.div((endX - startX) * 256, pairMax)
  local y2 = startY * 256 + pairNum * P.div((endY - startY) * 256, pairMax)
  return P.s16(P.shr(x2, 8)), P.s16(P.shr(y2, 8))
end

function H.glareDotStep(s)
  s.data[0] = s.data[0] + 1
  if s.data[0] > 36 then
    if s.task then
      local idx = s._activeIdx or 10
      s.task.data[idx] = s.task.data[idx] - 1
    end
    P.DestroyAnimSprite(s)
  end
end

-- pokefirered/src/battle_anim_effects_3.c:4020
C.GlareEyeDot = P.cb(H.glareDotStep)

function H.glareStep(t, vm)
  local d = t.data
  if d[0] == 0 then
    d[1] = d[1] + 1
    if d[1] > 3 then
      d[1] = 0
      local x, y = H.glareDotCoords(d[11], d[12], d[13], d[14], P.u8(d[5]), P.u8(d[2]))
      for i = 0, 1 do
        local s = P.CreateSprite(vm, "gGlareEyeDotSpriteTemplate", x, y, 35, H.glareDotStep)
        if s then
          if d[7] == 0 then
            if i == 0 then
              s.ox, s.oy = -d[6], -d[6]
            else
              s.ox, s.oy = d[6], d[6]
            end
          else
            if i == 0 then
              s.ox, s.oy = -d[6], d[6]
            else
              s.ox, s.oy = d[6], -d[6]
            end
          end
          s.data[0] = 0
          s.task = t
          s._activeIdx = 10
          d[10] = d[10] + 1
        end
      end
      if d[2] == d[5] then d[0] = d[0] + 1 end
      d[2] = d[2] + 1
    end
  elseif d[0] == 1 then
    if d[10] == 0 then P.DestroyAnimVisualTask(t) end
  end
end

-- pokefirered/src/battle_anim_effects_3.c:3904
T.GlareEyeDots = P.task(function(t, vm)
  local d = t.data
  local atk, tgt = P.atk(vm), P.tgt(vm)
  d[5] = 12
  d[6] = 3
  d[7] = 0
  local q = P.div(P.coordAttr(vm, atk, P.ATTR_HEIGHT), 4)
  if P.atkIsPlayer(vm) then
    d[11] = P.coord(vm, atk, P.COORD_X_2) + q
  else
    d[11] = P.coord(vm, atk, P.COORD_X_2) - q
  end
  d[12] = P.coord(vm, atk, P.COORD_Y_PIC) - q
  d[13] = P.coord(vm, tgt, P.COORD_X_2)
  d[14] = P.coord(vm, tgt, P.COORD_Y_PIC)
  t.fn = H.glareStep
end)

-- pokefirered/src/battle_anim_effects_3.c:4051
C.AssistPawprint = P.cb(function(s, vm)
  s.x = s.ga[0]
  s.y = s.ga[1]
  s.data[2] = s.ga[2]
  s.data[4] = s.ga[3]
  s.data[0] = s.ga[4]
  P.StoreSpriteCallbackInData6(s, P.DestroyAnimSprite)
  s.callbackFn = P.InitAndRunAnimFastLinearTranslation
end)

function H.barrageStep(t, vm)
  local d = t.data
  local s = t._ball
  if d[0] == 0 then
    d[1] = d[1] + 1
    if d[1] > 1 then
      d[1] = 0
      if s and s.active then P.TranslateAnimHorizontalArc(s) end
      d[2] = d[2] + 1
      if d[2] > 7 then d[0] = d[0] + 1 end
    end
  elseif d[0] == 1 then
    if not (s and s.active) or P.TranslateAnimHorizontalArc(s) then
      d[1] = 0
      d[2] = 0
      d[0] = d[0] + 1
    end
  elseif d[0] == 2 then
    d[1] = d[1] + 1
    if d[1] > 1 then
      d[1] = 0
      d[2] = d[2] + 1
      if s and s.active then s.invisible = band(d[2], 1) ~= 0 end
      if d[2] == 16 then
        if s and s.active then P.DestroyAnimSprite(s) end
        t._ball = nil
        d[0] = d[0] + 1
      end
    end
  elseif d[0] == 3 then
    P.DestroyAnimVisualTask(t)
  end
end

-- pokefirered/src/battle_anim_effects_3.c:4064
T.BarrageBall = P.task(function(t, vm)
  local d = t.data
  local atk, tgt = P.atk(vm), P.tgt(vm)
  d[11] = P.coord(vm, atk, P.COORD_X_2)
  d[12] = P.coord(vm, atk, P.COORD_Y_PIC)
  d[13] = P.coord(vm, tgt, P.COORD_X_2)
  d[14] = P.coord(vm, tgt, P.COORD_Y_PIC) + P.div(P.coordAttr(vm, tgt, P.ATTR_HEIGHT), 4)
  local s = P.CreateSprite(vm, "gBarrageBallSpriteTemplate", d[11], d[12], P.subpriorityOf(tgt) - 5, function() end)
  if s then
    t._ball = s
    s.data[0] = 16
    s.data[2] = d[13]
    s.data[4] = d[14]
    s.data[5] = -32
    P.InitAnimArcTranslation(s)
    if not P.atkIsPlayer(vm) then P.StartSpriteAffineAnim(s, 1) end
    t.fn = H.barrageStep
  else
    P.DestroyAnimVisualTask(t)
  end
end)

function H.saltsHandStep(s)
  local d = s.data
  if d[0] == 0 then
    d[1] = d[1] + 1
    if d[1] > 1 then
      d[1] = 0
      s.ox = s.ox + d[7]
      d[2] = d[2] + 1
      if d[2] == 12 then d[0] = d[0] + 1 end
    end
  elseif d[0] == 1 then
    d[1] = d[1] + 1
    if d[1] == 8 then
      d[1] = 0
      d[0] = d[0] + 1
    end
  elseif d[0] == 2 then
    s.ox = s.ox - d[7] * 4
    d[1] = d[1] + 1
    if d[1] == 6 then
      d[1] = 0
      d[0] = d[0] + 1
    end
  elseif d[0] == 3 then
    s.ox = s.ox + d[7] * 3
    d[1] = d[1] + 1
    if d[1] == 8 then
      d[6] = d[6] - 1
      if d[6] ~= 0 then
        d[1] = 0
        d[0] = d[0] - 1
      else
        P.DestroyAnimSprite(s)
      end
    end
  end
end

-- pokefirered/src/battle_anim_effects_3.c:4138
C.SmellingSaltsHand = P.cb(function(s, vm)
  local side = (s.ga[0] == P.ANIM_ATTACKER) and P.atk(vm) or P.tgt(vm)
  s.imageValue = s.imageValue + 16
  s.data[6] = s.ga[2]
  s.data[7] = (s.ga[1] == 0) and -1 or 1
  s.y = P.coord(vm, side, P.COORD_Y_PIC)
  if s.ga[1] == 0 then
    s._hFlipBase = true
    s.x = P.coordAttr(vm, side, P.ATTR_LEFT) - 8
  else
    s.x = P.coordAttr(vm, side, P.ATTR_RIGHT) + 8
  end
  s.callbackFn = H.saltsHandStep
end)

function H.saltsSquishStep(t, vm)
  local d = t.data
  local p = t._aP
  d[1] = d[1] + 1
  if d[1] > 1 then
    d[1] = 0
    if p then
      if band(d[2], 1) == 0 then p.ox = 2 else p.ox = -2 end
    end
  end
  if not H.runAffine(t, vm) then
    if p then p.ox = 0 end
    d[0] = d[0] - 1
    if d[0] ~= 0 then
      H.prepAffine(t, t._aSide, P.data().affine.sSmellingSaltsSquishAffineAnimCmds)
      d[1] = 0
      d[2] = 0
    else
      P.DestroyAnimVisualTask(t)
    end
  end
end

-- pokefirered/src/battle_anim_effects_3.c:4213
T.SmellingSaltsSquish = P.task(function(t, vm)
  if t.ga[0] == P.ANIM_ATTACKER then
    P.DestroyAnimVisualTask(t)
    return
  end
  t.data[0] = t.ga[1]
  H.prepAffine(t, P.side(vm, t.ga[0]), P.data().affine.sSmellingSaltsSquishAffineAnimCmds)
  t.fn = H.saltsSquishStep
end)

function H.exclamationStep(s)
  local d = s.data
  d[0] = d[0] + 1
  if d[0] >= d[1] then
    d[0] = 0
    d[2] = band(d[2] + 1, 1)
    s.invisible = d[2] ~= 0
    if d[2] ~= 0 then
      d[3] = d[3] - 1
      if d[3] == 0 then P.DestroyAnimSprite(s) end
    end
  end
end

-- pokefirered/src/battle_anim_effects_3.c:4261
C.SmellingSaltExclamation = P.cb(function(s, vm)
  local side = (s.ga[0] == P.ANIM_ATTACKER) and P.atk(vm) or P.tgt(vm)
  s.x = P.coord(vm, side, P.COORD_X_2)
  s.y = P.coordAttr(vm, side, P.ATTR_TOP)
  if s.y < 8 then s.y = 8 end
  s.data[0] = 0
  s.data[1] = s.ga[1]
  s.data[2] = 0
  s.data[3] = s.ga[2]
  s.callbackFn = H.exclamationStep
end)

function H.clapStep(s)
  local d = s.data
  local k = d[0]
  if k == 0 then
    s.y = s.y - d[7] * 2
    if band(d[1], 1) ~= 0 then s.x = s.x - d[7] * 2 end
    d[1] = d[1] + 1
    if d[1] == 9 then
      d[1] = 0
      d[0] = d[0] + 1
    end
  elseif k == 1 then
    d[1] = d[1] + 1
    if d[1] == 4 then
      d[1] = 0
      d[0] = d[0] + 1
    end
  elseif k == 2 then
    d[1] = d[1] + 1
    s.y = s.y + d[7] * 3
    s.ox = d[7] * P.shr(H.sine(d[1] * 10), 3)
    if d[1] == 12 then
      d[1] = 0
      d[0] = d[0] + 1
    end
  elseif k == 3 then
    d[1] = d[1] + 1
    if d[1] == 2 then
      d[1] = 0
      d[0] = d[0] + 1
    end
  elseif k == 4 then
    d[1] = d[1] + 1
    s.y = s.y - d[7] * 3
    s.ox = d[7] * P.shr(H.sine(d[1] * 10), 3)
    if d[1] == 12 then d[0] = d[0] + 1 end
  elseif k == 5 then
    d[1] = d[1] + 1
    s.y = s.y + d[7] * 3
    s.ox = d[7] * P.shr(H.sine(d[1] * 10), 3)
    if d[1] == 15 then s.imageValue = s.imageValue + 16 end
    if d[1] == 18 then
      d[1] = 0
      d[0] = d[0] + 1
    end
  elseif k == 6 then
    s.x = s.x + d[7] * 6
    d[1] = d[1] + 1
    if d[1] == 9 then
      d[1] = 0
      d[0] = d[0] + 1
    end
  elseif k == 7 then
    s.x = s.x + d[7] * 2
    d[1] = d[1] + 1
    if d[1] == 1 then
      d[1] = 0
      d[0] = d[0] + 1
    end
  elseif k == 8 then
    s.x = s.x - d[7] * 3
    d[1] = d[1] + 1
    if d[1] == 5 then P.DestroyAnimSprite(s) end
  end
end

-- pokefirered/src/battle_anim_effects_3.c:4299
C.HelpingHandClap = P.cb(function(s)
  if s.ga[0] == 0 then
    s._hFlipBase = true
    s.x = 100
    s.data[7] = 1
  else
    s.x = 140
    s.data[7] = -1
  end
  s.y = 56
  s.callbackFn = H.clapStep
end)

function H.helpingHandStep(t, vm)
  local d = t.data
  local p = t._p
  local k = d[0]
  local function addX(v) if p then p.ox = p.ox + v end end
  if k == 0 then
    d[1] = d[1] + 1
    if d[1] == 13 then
      d[1] = 0
      d[0] = d[0] + 1
    end
  elseif k == 1 then
    addX(-d[14] * 3)
    d[1] = d[1] + 1
    if d[1] == 6 then
      d[1] = 0
      d[0] = d[0] + 1
    end
  elseif k == 2 then
    addX(d[14] * 3)
    d[1] = d[1] + 1
    if d[1] == 6 then
      d[1] = 0
      d[0] = d[0] + 1
    end
  elseif k == 3 then
    d[1] = d[1] + 1
    if d[1] == 2 then
      d[1] = 0
      if d[2] == 0 then
        d[2] = d[2] + 1
        d[0] = 1
      else
        d[0] = d[0] + 1
      end
    end
  elseif k == 4 then
    addX(d[14])
    d[1] = d[1] + 1
    if d[1] == 3 then
      d[1] = 0
      d[0] = d[0] + 1
    end
  elseif k == 5 then
    d[1] = d[1] + 1
    if d[1] == 6 then
      d[1] = 0
      d[0] = d[0] + 1
    end
  elseif k == 6 then
    addX(-d[14] * 4)
    d[1] = d[1] + 1
    if d[1] == 5 then
      d[1] = 0
      d[0] = d[0] + 1
    end
  elseif k == 7 then
    addX(d[14] * 4)
    d[1] = d[1] + 1
    if d[1] == 5 then
      d[1] = 0
      d[0] = d[0] + 1
    end
  elseif k == 8 then
    if p then p.ox = 0 end
    P.DestroyAnimVisualTask(t)
  end
end

-- pokefirered/src/battle_anim_effects_3.c:4402
T.HelpingHandAttackerMovement = P.task(function(t, vm)
  t._p = P.monPresent(P.atk(vm))
  if P.atkIsPlayer(vm) then t.data[14] = -1 else t.data[14] = 1 end
  t.fn = H.helpingHandStep
end)

function H.foresightStep(s, vm)
  local d = s.data
  local side = s._battler
  if d[5] == 0 then
    local x, y
    local k = d[6]
    if k < 0 or k > 5 then
      d[6] = 0
      k = 0
    end
    if k == 0 or k == 4 then
      x = P.coordAttr(vm, side, P.ATTR_RIGHT) - 4
      y = P.coordAttr(vm, side, P.ATTR_BOTTOM) - 4
    elseif k == 1 then
      x = P.coordAttr(vm, side, P.ATTR_RIGHT) - 4
      y = P.coordAttr(vm, side, P.ATTR_TOP) + 4
    elseif k == 2 then
      x = P.coordAttr(vm, side, P.ATTR_LEFT) + 4
      y = P.coordAttr(vm, side, P.ATTR_BOTTOM) - 4
    elseif k == 3 then
      x = P.coordAttr(vm, side, P.ATTR_LEFT) + 4
      y = P.coordAttr(vm, side, P.ATTR_TOP) - 4
    else
      x = P.coord(vm, side, P.COORD_X_2)
      y = P.coord(vm, side, P.COORD_Y_PIC)
    end
    x = P.s16(P.u16(x))
    y = P.s16(P.u16(y))
    if d[6] == 4 then
      d[0] = 24
    elseif d[6] == 5 then
      d[0] = 6
    else
      d[0] = 12
    end
    d[1] = s.x
    d[2] = x
    d[3] = s.y
    d[4] = y
    P.InitAnimLinearTranslation(s)
    d[5] = d[5] + 1
  elseif d[5] == 1 then
    if P.AnimTranslateLinear(s) then
      if d[6] == 4 then
        s.x = s.x + s.ox
        s.y = s.y + s.oy
        s.oy = 0
        s.ox = 0
        d[5] = 0
        d[6] = d[6] + 1
      elseif d[6] == 5 then
        d[0] = 0
        d[1] = 16
        d[2] = 0
        d[5] = 3
      else
        s.x = s.x + s.ox
        s.y = s.y + s.oy
        s.oy = 0
        s.ox = 0
        d[0] = 0
        d[5] = d[5] + 1
        d[6] = d[6] + 1
      end
    end
  elseif d[5] == 2 then
    d[0] = d[0] + 1
    if d[0] == 4 then d[5] = 0 end
  elseif d[5] == 3 then
    if band(d[0], 1) == 0 then
      d[1] = d[1] - 1
    else
      d[2] = d[2] + 1
    end
    P.setBld(vm, d[1], d[2])
    d[0] = d[0] + 1
    if d[0] == 32 then
      s.invisible = true
      d[5] = d[5] + 1
    end
  elseif d[5] == 4 then
    P.DestroyAnimSprite(s)
  end
end

-- pokefirered/src/battle_anim_effects_3.c:4511
C.ForesightMagnifyingGlass = P.cb(function(s, vm)
  if s.ga[0] == P.ANIM_ATTACKER then
    P.InitSpritePosToAnimAttacker(s, vm, true)
    s._battler = P.atk(vm)
  else
    s._battler = P.tgt(vm)
  end
  if s._battler ~= "player" then s._hFlipBase = true end
  s.pri = H.bgPriority(vm, s._battler)
  s._objBlend = true
  s.callbackFn = H.foresightStep
end)

function H.miniStarStep(s)
  local d = s.data
  d[0] = d[0] + 1
  if d[0] < 30 then
    d[1] = d[1] + 1
    if d[1] == 2 then
      s.invisible = not s.invisible
      d[1] = 0
    end
  else
    if d[1] == 2 then s.invisible = false end
    if d[1] == 3 then
      s.invisible = true
      d[1] = -1
    end
    d[1] = d[1] + 1
  end
  if d[0] > 60 then P.DestroyAnimSprite(s) end
end

function H.miniStar(s)
  local rand = band(P.Random(), 3)
  if rand == 0 then
    s.imageValue = s.imageValue + 4
  else
    s.imageValue = s.imageValue + 5
  end
  local y = band(P.Random(), 7)
  if y > 3 then y = -y end
  s.oy = y
  s.callbackFn = H.miniStarStep
end

function H.meteorStep(s, vm)
  local d = s.data
  s.ox = P.div((d[2] - d[0]) * d[5], d[4])
  s.oy = P.div((d[3] - d[1]) * d[5], d[4])
  if band(d[5], 1) == 0 then
    P.CreateSprite(vm, "gMiniTwinklingStarSpriteTemplate", s.x + s.ox, s.y + s.oy, 5, H.miniStar)
  end
  if d[5] == d[4] then
    P.DestroyAnimSprite(s)
    return
  end
  d[5] = d[5] + 1
end

-- pokefirered/src/battle_anim_effects_3.c:4657
C.MeteorMashStar = P.cb(function(s, vm)
  local d = s.data
  if P.tgtIsPlayer(vm) then
    d[0] = s.x - s.ga[0]
    d[2] = s.x - s.ga[2]
  else
    d[0] = s.x + s.ga[0]
    d[2] = s.x + s.ga[2]
  end
  d[1] = s.y + s.ga[1]
  d[3] = s.y + s.ga[3]
  d[4] = s.ga[4]
  s.x = d[0]
  s.y = d[1]
  s.callbackFn = H.meteorStep
end)

function H.subDollStep(t, vm)
  local d = t.data
  local p = t._p
  if not p then
    P.DestroyAnimVisualTask(t)
    return
  end
  local k = d[0]
  if k == 0 then
    p.oy = -200
    p.ox = 200
    p.visible = true
    d[10] = 0
    d[0] = d[0] + 1
  elseif k == 1 then
    d[10] = P.s16(d[10] + 112)
    p.oy = P.s16(p.oy + P.shr(d[10], 8))
    if t._y + p.oy >= -32 then p.ox = 0 end
    if p.oy > 0 then p.oy = 0 end
    if p.oy == 0 then
      P.playSEPan(vm, "SE_M_BUBBLE2", -64)
      d[10] = P.s16(d[10] - 0x800)
      d[0] = d[0] + 1
    end
  elseif k == 2 then
    d[10] = P.s16(d[10] - 112)
    if d[10] < 0 then d[10] = 0 end
    p.oy = P.s16(p.oy - P.shr(d[10], 8))
    if d[10] == 0 then d[0] = d[0] + 1 end
  elseif k == 3 then
    d[10] = P.s16(d[10] + 112)
    p.oy = P.s16(p.oy + P.shr(d[10], 8))
    if p.oy > 0 then p.oy = 0 end
    if p.oy == 0 then
      P.playSEPan(vm, "SE_M_BUBBLE2", -64)
      P.DestroyAnimVisualTask(t)
    end
  end
end

-- pokefirered/src/battle_anim_effects_3.c:4681
T.MonToSubstitute = P.task(function(t, vm)
  local d = t.data
  local side = P.atk(vm)
  local p = P.monPresent(side)
  t._p = p
  if d[0] == 0 then
    d[1] = 0x100
    d[2] = 0x100
    d[0] = d[0] + 1
  elseif d[0] == 1 then
    d[1] = P.s16(d[1] + 0x60)
    d[2] = P.s16(d[2] - 0xD)
    P.monRotScale(p, d[1], d[2], 0)
    d[3] = d[3] + 1
    if d[3] == 9 then
      d[3] = 0
      P.monResetRotScale(p)
      if p then p.visible = false end
      d[0] = d[0] + 1
    end
  else
    local A = P.Anim()
    if A.setSubstitute then A.setSubstitute(side, true) end
    for i = 0, 15 do d[i] = 0 end
    t._y = (A.substituteY and A.substituteY(side)) or H.monY(vm, side)
    t.fn = H.subDollStep
  end
end)

function H.blockXStep(s, vm)
  local d = s.data
  local k = d[0]
  if k == 0 then
    s.oy = s.oy + 10
    if s.oy >= 0 then
      P.playSEPan(vm, "SE_M_SKETCH", 63)
      s.oy = 0
      d[0] = d[0] + 1
    end
  elseif k == 1 then
    d[1] = d[1] + 4
    s.oy = -P.shr(H.sine(d[1]), 3)
    if d[1] > 0x7F then
      P.playSEPan(vm, "SE_M_SKETCH", 63)
      d[1] = 0
      s.oy = 0
      d[0] = d[0] + 1
    end
  elseif k == 2 then
    d[1] = d[1] + 6
    s.oy = -P.shr(H.sine(d[1]), 4)
    if d[1] > 0x7F then
      d[1] = 0
      s.oy = 0
      d[0] = d[0] + 1
    end
  elseif k == 3 then
    d[1] = d[1] + 1
    if d[1] > 8 then
      P.playSEPan(vm, "SE_M_LEER", 63)
      d[1] = 0
      d[0] = d[0] + 1
    end
  elseif k == 4 then
    d[1] = d[1] + 1
    if d[1] > 8 then
      d[1] = 0
      d[2] = d[2] + 1
      s.invisible = band(d[2], 1) ~= 0
      if d[2] == 7 then P.DestroyAnimSprite(s) end
    end
  end
end

-- pokefirered/src/battle_anim_effects_3.c:4771
C.BlockX = P.cb(function(s, vm)
  local tgt = P.tgt(vm)
  local y
  if P.tgtIsPlayer(vm) then
    s.sub = P.subpriorityOf(tgt) - 2
    y = -144
  else
    s.sub = P.subpriorityOf(tgt) + 2
    y = -96
  end
  s.y = P.coord(vm, tgt, P.COORD_Y_PIC)
  s.oy = y
  s.callbackFn = H.blockXStep
end)

function H.odorCloneStep(s, vm)
  local d = s.data
  local hidden = P.monHidden(vm, P.tgt(vm))
  d[1] = d[1] + 1
  if d[1] > 1 then
    d[1] = 0
    if not hidden then s.invisible = not s.invisible end
  end
  d[4] = band(d[4] + d[3], 0xFF)
  s.ox = P.Cos(d[4], d[5])
  if d[0] == 0 then
    d[2] = d[2] + 1
    if d[2] == 60 then
      d[2] = 0
      d[0] = d[0] + 1
    end
  elseif d[0] == 1 then
    d[2] = d[2] + 1
    if d[2] > 0 then
      d[2] = 0
      d[5] = d[5] - 2
      if d[5] < 0 then
        if s.task then s.task.data[d[7]] = s.task.data[d[7]] - 1 end
        P.DestroyAnimSprite(s)
      end
    end
  end
end

function H.odorWait(t)
  if t.data[0] == 0 then P.DestroyAnimVisualTask(t) end
end

-- pokefirered/src/battle_anim_effects_3.c:4848
T.OdorSleuthMovement = P.task(function(t, vm)
  local side = P.tgt(vm)
  local s1 = P.CloneMon(vm, side)
  if not s1 then
    P.DestroyAnimVisualTask(t)
    return
  end
  local s2 = P.CloneMon(vm, side)
  if not s2 then
    P.DestroyAnimSprite(s1)
    P.DestroyAnimVisualTask(t)
    return
  end
  s2.ox = s2.ox + 24
  s1.ox = s1.ox - 24
  for i = 0, 7 do
    s1.data[i] = 0
    s2.data[i] = 0
  end
  s2.data[3] = 16
  s1.data[3] = -16
  s2.data[4] = 0
  s1.data[4] = 128
  s2.data[5] = 24
  s1.data[5] = 24
  s1.task, s2.task = t, t
  t.data[0] = 2
  if not P.monHidden(vm, side) then
    s2.invisible = false
    s1.invisible = true
  else
    s2.invisible = true
    s1.invisible = true
  end
  s1._objBlend = false
  s2._objBlend = false
  s1.callbackFn = H.odorCloneStep
  s2.callbackFn = H.odorCloneStep
  t.fn = H.odorWait
end)

-- pokefirered/src/battle_anim_effects_3.c:4949
T.GetReturnPowerLevel = P.task(function(t, vm)
  local f = tonumber(vm and vm.ctx and (vm.ctx.friendship or vm.ctx.animFriendship))
  if not f then
    local st = H.battleSt()
    local b = st and st[P.atk(vm)]
    local mon = type(b) == "table" and b.mon or nil
    if mon then f = tonumber(mon.friendship or mon.happiness) end
  end
  f = P.u8(f or 0)
  P.setRet(vm, 0)
  if f < 60 then P.setRet(vm, 0) end
  if f > 60 and f < 92 then P.setRet(vm, 1) end
  if f > 91 and f < 201 then P.setRet(vm, 2) end
  if f > 200 then P.setRet(vm, 3) end
  P.DestroyAnimVisualTask(t)
end)

function H.monPicSprite(vm, species, isBack, x, y, z, side)
  local ok, Pokemon = pcall(require, "src.core.game3.pokemon")
  local img
  if ok and species then
    local picSp, shiny, personality = require("src.core.game3.battle.ui").sidePicArgs(side, species)
    local e
    if isBack and Pokemon.backPic then e = Pokemon.backPic(picSp, nil, shiny) end
    if not isBack and Pokemon.frontPic then e = Pokemon.frontPic(picSp, nil, shiny, personality) end
    img = e and e.image
  end
  local okc, pc = pcall(require, "src.core.game3.battle.pic_coords")
  local yOff = 0
  if okc and type(pc) == "table" and species then
    local tbl = isBack and pc.back or pc.front
    yOff = (tbl and tbl[species]) or 0
  end
  local s = P.CloneMon(vm, P.atk(vm))
  if not s then return nil end
  if img then s.image = img end
  s.x = x
  s.y = y + yOff
  s.ox, s.oy = 0, 0
  s._mat = nil
  s._objBlend = false
  s.invisible = false
  s.zOverride = z
  s.callbackFn = function() end
  P.sync(s, vm)
  return s
end

function H.snatchStep(t, vm)
  local d = t.data
  local atk, tgt = P.atk(vm), P.tgt(vm)
  local p = t._p
  local k = d[0]
  if k == 0 then
    d[1] = d[1] + 0x800
    if p then
      if P.atkIsPlayer(vm) then
        p.ox = p.ox + P.shr(d[1], 8)
      else
        p.ox = p.ox - P.shr(d[1], 8)
      end
    end
    d[1] = band(d[1], 0xFF)
    local x = t._x + (p and p.ox or 0)
    if x < -32 or x > DISPLAY_WIDTH + 32 then
      d[1] = 0
      d[0] = d[0] + 1
    end
  elseif k == 1 then
    local species = P.species(vm, atk)
    local isBack, x, z
    if P.atkIsPlayer(vm) then
      isBack = false
      x = DISPLAY_WIDTH + 32
      z = 95
    else
      isBack = true
      x = -32
      z = 205
    end
    t._s2 = H.monPicSprite(vm, species, isBack, x, P.coord(vm, tgt, P.COORD_Y), z, atk)
    d[0] = d[0] + 1
  elseif k == 2 then
    local s2 = t._s2
    d[1] = d[1] + 0x800
    if s2 then
      if P.atkIsPlayer(vm) then
        s2.ox = s2.ox - P.shr(d[1], 8)
      else
        s2.ox = s2.ox + P.shr(d[1], 8)
      end
    end
    d[1] = band(d[1], 0xFF)
    local x = s2 and (s2.x + s2.ox) or -1000
    if d[14] == 0 then
      if P.atkIsPlayer(vm) then
        if x < P.coord(vm, tgt, P.COORD_X) then
          d[14] = d[14] + 1
          P.setRet(vm, -1)
        end
      else
        if x > P.coord(vm, tgt, P.COORD_X) then
          d[14] = d[14] + 1
          P.setRet(vm, -1)
        end
      end
    end
    if x < -32 or x > DISPLAY_WIDTH + 32 then
      d[1] = 0
      d[0] = d[0] + 1
    end
  elseif k == 3 then
    if t._s2 and t._s2.active then P.DestroyAnimSprite(t._s2) end
    t._s2 = nil
    if p then
      if P.atkIsPlayer(vm) then
        p.ox = -t._x - 32
      else
        p.ox = DISPLAY_WIDTH + 32 - t._x
      end
    end
    d[0] = d[0] + 1
  elseif k == 4 then
    d[1] = d[1] + 0x800
    local ax = P.coord(vm, atk, P.COORD_X)
    if p then
      if P.atkIsPlayer(vm) then
        p.ox = p.ox + P.shr(d[1], 8)
        if p.ox + t._x >= ax then p.ox = 0 end
      else
        p.ox = p.ox - P.shr(d[1], 8)
        if p.ox + t._x <= ax then p.ox = 0 end
      end
    end
    d[1] = P.u8(d[1])
    if not p or p.ox == 0 then P.DestroyAnimVisualTask(t) end
  end
end

-- pokefirered/src/battle_anim_effects_3.c:4966
T.SnatchOpposingMonMove = P.task(function(t, vm)
  local atk = P.atk(vm)
  t._p = P.monPresent(atk)
  t._x = H.monX(vm, atk)
  t.fn = H.snatchStep
  H.snatchStep(t, vm)
end)

function H.snatchPartnerStep(t, vm)
  local d = t.data
  local p = t._p
  local k = d[15]
  if k == 0 then
    local attackerX = P.coord(vm, P.atk(vm), P.COORD_X)
    local targetX = P.coord(vm, P.tgt(vm), P.COORD_X)
    d[0] = 6
    if attackerX > targetX then d[0] = -d[0] end
    d[1] = attackerX
    d[2] = targetX
    d[15] = d[15] + 1
  elseif k == 1 then
    if p then p.ox = p.ox + d[0] end
    local x = t._x + (p and p.ox or 0)
    if d[0] > 0 then
      if x >= d[2] then d[15] = d[15] + 1 end
    else
      if x <= d[2] then d[15] = d[15] + 1 end
    end
  elseif k == 2 then
    d[0] = -d[0]
    d[15] = d[15] + 1
  elseif k == 3 then
    if p then p.ox = p.ox + d[0] end
    local x = t._x + (p and p.ox or 0)
    if d[0] < 0 then
      if x <= d[1] then d[15] = d[15] + 1 end
    else
      if x >= d[1] then d[15] = d[15] + 1 end
    end
  else
    if p then p.ox = 0 end
    P.DestroyAnimVisualTask(t)
  end
end

-- pokefirered/src/battle_anim_effects_3.c:5147
T.SnatchPartnerMove = P.task(function(t, vm)
  local atk = P.atk(vm)
  t._p = P.monPresent(atk)
  t._x = H.monX(vm, atk)
  t.fn = H.snatchPartnerStep
  H.snatchPartnerStep(t, vm)
end)

function H.teeterApply(t)
  local p = t._p
  if p then p.ox = t._xd + t._x2 end
end

function H.teeterStep(t, vm)
  local d = t.data
  if d[0] == 0 then
    d[11] = band(d[11] + 8, 0xFF)
    t._x2 = P.shr(H.sine(d[11]), 5)
    d[9] = band(d[9] + 2, 0xFF)
    t._xd = P.shr(H.sine(d[9]), 3) * d[4]
    if d[9] == 0 then
      t._xd = 0
      d[0] = d[0] + 1
    end
    H.teeterApply(t)
  elseif d[0] == 1 then
    d[11] = band(d[11] + 8, 0xFF)
    t._x2 = P.shr(H.sine(d[11]), 5)
    if d[11] == 0 then
      t._x2 = 0
      d[0] = d[0] + 1
    end
    H.teeterApply(t)
  elseif d[0] == 2 then
    P.DestroyAnimVisualTask(t)
  end
end

-- pokefirered/src/battle_anim_effects_3.c:5208
T.TeeterDanceMovement = P.task(function(t, vm)
  local d = t.data
  local atk = P.atk(vm)
  t._p = P.monPresent(atk)
  d[4] = P.atkIsPlayer(vm) and 1 or -1
  d[6] = H.monY(vm, atk)
  d[5] = H.monX(vm, atk)
  d[9] = 0
  d[11] = 0
  d[10] = 1
  d[12] = 0
  t._xd = 0
  t._x2 = (t._p and t._p.ox) or 0
  t.fn = H.teeterStep
end)

function H.knockOffStep(s)
  local d = s.data
  d[1] = band(d[1] + d[0], 0xFF)
  s.ox = P.Cos(d[1], 20)
  s.oy = P.Sin(d[1], 20)
  if s.animEnded then
    P.DestroyAnimSprite(s)
    return
  end
  d[2] = d[2] + 1
end

-- pokefirered/src/battle_anim_effects_3.c:5283
C.KnockOffStrike = P.cb(function(s, vm)
  local d = s.data
  if P.tgtIsPlayer(vm) then
    s.x = s.x - s.ga[0]
    s.y = s.y + s.ga[1]
    d[0] = -11
    d[1] = 192
    P.StartSpriteAffineAnim(s, 1)
  else
    d[0] = 11
    d[1] = 192
    s.x = s.x + s.ga[0]
    s.y = s.y + s.ga[1]
  end
  s.callbackFn = H.knockOffStep
end)

function H.recycleStep(s, vm)
  local d = s.data
  local k = d[2]
  if k == 0 then
    d[0] = d[0] + 1
    if d[0] > 1 then
      d[0] = 0
      if band(d[1], 1) == 0 then
        if d[6] < 16 then d[6] = d[6] + 1 end
      else
        if d[7] ~= 0 then d[7] = d[7] - 1 end
      end
      d[1] = d[1] + 1
      P.setBld(vm, d[6], d[7])
      if d[7] == 0 then d[2] = d[2] + 1 end
    end
  elseif k == 1 then
    d[0] = d[0] + 1
    if d[0] == 10 then
      d[0] = 0
      d[1] = 0
      d[2] = d[2] + 1
    end
  elseif k == 2 then
    d[0] = d[0] + 1
    if d[0] > 1 then
      d[0] = 0
      if band(d[1], 1) == 0 then
        if d[6] ~= 0 then d[6] = d[6] - 1 end
      else
        if d[7] < 16 then d[7] = d[7] + 1 end
      end
      d[1] = d[1] + 1
      P.setBld(vm, d[6], d[7])
      if d[7] == 16 then d[2] = d[2] + 1 end
    end
  elseif k == 3 then
    P.DestroySpriteAndMatrix(s)
  end
end

-- pokefirered/src/battle_anim_effects_3.c:5306
C.Recycle = P.cb(function(s, vm)
  local atk = P.atk(vm)
  s.x = P.coord(vm, atk, P.COORD_X_2)
  s.y = P.coordAttr(vm, atk, P.ATTR_TOP)
  if s.y < 16 then s.y = 16 end
  s.data[6] = 0
  s.data[7] = 16
  s.callbackFn = H.recycleStep
  P.setBld(vm, s.data[6], s.data[7])
end)

function H.weatherCode(w)
  if w == nil then return 0 end
  if type(w) == "number" then
    if band(w, 0x60) ~= 0 then return 1 end
    if band(w, 0x07) ~= 0 then return 2 end
    if band(w, 0x18) ~= 0 then return 3 end
    if band(w, 0x80) ~= 0 then return 4 end
    return 0
  end
  local ok, Rules = pcall(require, "src.core.game3.battle.rules")
  local kind = ok and Rules.weather and Rules.weather.kind(w) or nil
  if kind == "SUN" then return 1 end
  if kind == "RAIN" then return 2 end
  if kind == "SAND" then return 3 end
  if kind == "HAIL" then return 4 end
  return 0
end

-- pokefirered/src/battle_anim_effects_3.c:5379
T.GetWeather = P.task(function(t, vm)
  local w = vm and vm.ctx and (vm.ctx.weatherMoveAnim or vm.ctx.weather)
  if w == nil then
    local st = H.battleSt()
    w = st and st.weather
  end
  P.setRet(vm, H.weatherCode(w))
  P.DestroyAnimVisualTask(t)
end)

function H.slackOffStep(t, vm)
  local d = t.data
  local p = t._aP
  d[0] = d[0] + 1
  if d[0] > 16 and d[0] < 40 then
    d[1] = d[1] + 1
    if d[1] > 2 then
      d[1] = 0
      d[2] = d[2] + 1
      if p then
        if band(d[2], 1) == 0 then p.ox = -1 else p.ox = 1 end
      end
    end
  else
    if p then p.ox = 0 end
  end
  if not H.runAffine(t, vm) then P.DestroyAnimVisualTask(t) end
end

-- pokefirered/src/battle_anim_effects_3.c:5396
T.SlackOffSquish = P.task(function(t, vm)
  t.data[0] = 0
  H.prepAffine(t, P.side(vm, t.ga[0]), P.data().affine.sSlackOffSquishAffineAnimCmds)
  t.fn = H.slackOffStep
end)

return { callbacks = C, tasks = T }
