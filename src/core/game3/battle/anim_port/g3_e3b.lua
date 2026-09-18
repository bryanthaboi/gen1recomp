local P = require("src.core.game3.battle.anim_port.g3_pret")

local C, T = {}, {}
local band, bor = P.band, P.bor
local floor = math.floor

local H = {}

function H.prepareAffine(t, side, name)
  local d = t.data
  d[7] = 0
  d[8] = 0
  d[9] = 0
  d[10] = 0x100
  d[11] = 0x100
  d[12] = 0
  t._affSide = side
  t._affCmds = P.data().affine[name] or { { e = 1 } }
end

function H.runAffine(t, vm)
  local d = t.data
  local cmds = t._affCmds
  local side = t._affSide
  local c = cmds[d[7] + 1] or { e = 1 }
  if c.x ~= nil then
    if (c.d or 0) == 0 then
      d[10] = c.x
      d[11] = c.y
      d[12] = c.r or 0
      d[7] = d[7] + 1
      c = cmds[d[7] + 1] or {}
    end
    d[10] = P.s16(d[10] + (c.x or 0))
    d[11] = P.s16(d[11] + (c.y or 0))
    d[12] = P.s16(d[12] + (c.r or 0))
    local p = side and P.monPresent(side)
    P.monRotScale(p, d[10], d[11], d[12])
    if p then P.monYOffsetFromYScale(vm, side) end
    d[8] = d[8] + 1
    if d[8] >= (c.d or 0) then
      d[8] = 0
      d[7] = d[7] + 1
    end
  elseif c.j ~= nil then
    d[7] = c.j
  elseif c.l ~= nil then
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
        local pc = cmds[d[7] + 1]
        if pc and pc.l ~= nil then
          d[7] = d[7] + 1
          return true
        end
        if d[7] == 0 then return true end
      end
    end
    d[7] = d[7] + 1
  else
    local p = side and P.monPresent(side)
    if p then p.oy = 0 end
    P.monResetRotScale(p)
    return false
  end
  return true
end

function H.rgb(r, g, b) return r + g * 32 + b * 1024 end

function H.greenStarChild(s)
  local d = s.data
  if not s.invisible then
    local delta = P.s16(d[3] + d[2])
    s.oy = s.oy - P.shr(delta, 8)
    d[3] = band(P.s16(d[3] + d[2]), 0xFF)
    d[1] = d[1] - 1
    if d[1] == -1 then
      s.invisible = true
      s._dummy = true
      s.callbackFn = nil
    end
  end
end

function H.greenStarStep2(s)
  local a, b = s._c1, s._c2
  local da = (not a) or (not a.active) or a._dummy
  local db = (not b) or (not b.active) or b._dummy
  if da and db then
    if a and a.active then P.DestroyAnimSprite(a) end
    if b and b.active then P.DestroyAnimSprite(b) end
    P.DestroyAnimSprite(s)
  end
end

function H.greenStarStep1(s)
  local d = s.data
  local delta = P.s16(d[3] + d[2])
  s.oy = s.oy - P.shr(delta, 8)
  d[3] = band(P.s16(d[3] + d[2]), 0xFF)
  if d[4] == 0 and s.oy < -8 then
    if s._c1 then s._c1.invisible = false end
    d[4] = d[4] + 1
  end
  if d[4] == 1 and s.oy < -16 then
    if s._c2 then s._c2.invisible = false end
    d[4] = d[4] + 1
  end
  d[1] = d[1] - 1
  if d[1] == -1 then
    s.invisible = true
    s.callbackFn = H.greenStarStep2
  end
end

-- pokefirered/src/battle_anim_effects_3.c:2405
C.GreenStar = P.cb(function(s, vm)
  local d = s.data
  local xOffset = band(P.Random(), 0x3F)
  if xOffset > 31 then xOffset = 32 - xOffset end
  s.x = P.coordAtk(vm, P.COORD_X) + xOffset
  s.y = P.coordAtk(vm, P.COORD_Y) + 32
  d[1] = s.ga[0]
  d[2] = s.ga[1]
  local c1 = P.CreateSprite(vm, "gGreenStarSpriteTemplate", s.x, s.y, s.sub + 1, H.greenStarChild)
  local c2 = P.CreateSprite(vm, "gGreenStarSpriteTemplate", s.x, s.y, s.sub + 1, H.greenStarChild)
  for i, c in ipairs({ c1 or false, c2 or false }) do
    if c then
      P.StartSpriteAnim(c, i)
      c.data[1] = s.ga[0]
      c.data[2] = s.ga[1]
      c.data[7] = -1
      c.invisible = true
      P.sync(c, vm)
    end
  end
  s._c1 = c1
  s._c2 = c2
  s.callbackFn = H.greenStarStep1
end)

H.DOOM_COORDS = { [0] = 0x78, 0x50, 0x28, 0x00, 0 }
H.DOOM_DELAYS = { [0] = 0, 0, 0, 0, 50 }

function H.doomDesireStep(t, vm)
  local d = t.data
  local st = d[0]
  if st == 0 then
    P.setBld(vm, 3, 13)
    P.bg1Layer(t, vm, "MORNING_SUN", 1)
    local x = P.tgtIsPlayer(vm) and -10 or -135
    t._bg1x = x
    t._bg1y = 0
    d[10] = x
    d[11] = 0
    d[0] = d[0] + 1
  elseif st == 1 then
    d[3] = 0
    if not P.tgtIsPlayer(vm) then
      t._bg1x = d[10] + H.DOOM_COORDS[d[2]]
    else
      t._bg1x = d[10] - H.DOOM_COORDS[d[2]]
    end
    d[2] = d[2] + 1
    if d[2] == 5 then d[0] = 5 else d[0] = d[0] + 1 end
  elseif st == 2 then
    d[1] = d[1] - 1
    if d[1] <= 4 then d[1] = 5 end
    P.setBld(vm, 3, d[1])
    if d[1] == 5 then d[0] = d[0] + 1 end
  elseif st == 3 then
    d[3] = d[3] + 1
    if d[3] > H.DOOM_DELAYS[d[2]] then d[0] = d[0] + 1 end
  elseif st == 4 then
    d[1] = d[1] + 1
    if d[1] > 13 then d[1] = 13 end
    P.setBld(vm, 3, d[1])
    if d[1] == 13 then d[0] = 1 end
  elseif st == 5 then
    P.bg1Clear(t)
    t._bg1x = 0
    t._bg1y = 0
    P.setBld(vm, nil)
    P.DestroyAnimVisualTask(t)
  end
end

-- pokefirered/src/battle_anim_effects_3.c:2495
T.DoomDesireLightBeam = P.task(function(t, vm)
  t.fn = H.doomDesireStep
  H.doomDesireStep(t, vm)
end)

function H.strongFrustrationStep(t, vm)
  if not H.runAffine(t, vm) then P.DestroyAnimVisualTask(t) end
end

-- pokefirered/src/battle_anim_effects_3.c:2599
T.StrongFrustrationGrowAndShrink = P.task(function(t, vm)
  H.prepareAffine(t, P.atk(vm), "sStrongFrustrationAffineAnimCmds")
  t.data[0] = t.data[0] + 1
  t.fn = H.strongFrustrationStep
end)

-- pokefirered/src/battle_anim_effects_3.c:2616
C.WeakFrustrationAngerMark = P.cb(function(s, vm)
  local d = s.data
  if d[0] == 0 then
    P.InitSpritePosToAnimAttacker(s, vm, false)
    d[0] = d[0] + 1
  else
    local old = d[0]
    d[0] = d[0] + 1
    if old > 20 then
      d[1] = P.s16(d[1] + 160)
      d[2] = P.s16(d[2] + 128)
      if not P.atkIsPlayer(vm) then
        s.ox = -P.shr(d[1], 8)
      else
        s.ox = P.shr(d[1], 8)
      end
      s.oy = s.oy + P.shr(d[2], 8)
      if s.oy > 64 then P.DestroyAnimSprite(s) end
    end
  end
end)

function H.rockMonApply(t, vm)
  local d = t.data
  local p = t._p
  P.monRotScale(p, 0x100, 0x100, d[2])
  if p then P.monYOffsetFromRotation(t._side) end
end

function H.rockMonStep(t, vm)
  local d = t.data
  local p = t._p
  local st = d[0]
  if st == 0 then
    if p then p.ox = p.ox + d[5] end
    d[2] = P.s16(d[2] - d[4])
    H.rockMonApply(t, vm)
    d[1] = d[1] + 1
    if d[1] >= d[3] then
      d[1] = 0
      d[0] = d[0] + 1
    end
  elseif st == 1 then
    if p then p.ox = p.ox - d[5] end
    d[2] = P.s16(d[2] + d[4])
    H.rockMonApply(t, vm)
    d[1] = d[1] + 1
    if d[1] >= d[3] * 2 then
      d[1] = 0
      d[0] = d[0] + 1
    end
  elseif st == 2 then
    if p then p.ox = p.ox + d[5] end
    d[2] = P.s16(d[2] - d[4])
    H.rockMonApply(t, vm)
    d[1] = d[1] + 1
    if d[1] >= d[3] then
      if d[6] ~= 0 then
        d[6] = d[6] - 1
        d[1] = 0
        d[0] = 0
      else
        d[0] = d[0] + 1
      end
    end
  elseif st == 3 then
    P.monResetRotScale(p)
    P.DestroyAnimVisualTask(t)
  end
end

-- pokefirered/src/battle_anim_effects_3.c:2643
T.RockMonBackAndForth = P.task(function(t, vm)
  local d = t.data
  local ga = t.ga
  if ga[1] == 0 then
    P.DestroyAnimVisualTask(t)
    return
  end
  if ga[2] < 0 then ga[2] = 0 end
  if ga[2] > 2 then ga[2] = 2 end
  d[0] = 0
  d[1] = 0
  d[2] = 0
  d[3] = 8 - 2 * ga[2]
  d[4] = 0x100 + ga[2] * 128
  d[5] = ga[2] + 2
  d[6] = ga[1] - 1
  t._p, t._side = P.monSprite(vm, ga[0])
  local side = (ga[0] == P.ANIM_ATTACKER) and P.atk(vm) or P.tgt(vm)
  if side ~= "player" then
    d[4] = -d[4]
    d[5] = -d[5]
  end
  t.fn = H.rockMonStep
end)

function H.sweetScentStep(s, vm)
  local d = s.data
  d[0] = P.s16(d[0] + 3)
  if P.atkIsPlayer(vm) then
    s.x = s.x + 5
    s.y = s.y - 1
    if s.x > 240 then
      P.DestroyAnimSprite(s)
      return
    end
    s.oy = P.Sin(band(d[0], 0xFF), 16)
  else
    s.x = s.x - 5
    s.y = s.y + 1
    if s.x < 0 then
      P.DestroyAnimSprite(s)
      return
    end
    s.oy = P.Cos(band(d[0], 0xFF), 16)
  end
end

-- pokefirered/src/battle_anim_effects_3.c:2741
C.SweetScentPetal = P.cb(function(s, vm)
  if P.atkIsPlayer(vm) then
    s.x = 0
    s.y = s.ga[0]
  else
    s.x = 240
    s.y = s.ga[0] - 30
  end
  s.data[2] = s.ga[2]
  P.StartSpriteAnim(s, s.ga[1])
  s.callbackFn = H.sweetScentStep
end)

function H.flailStep(t, vm)
  local d = t.data
  local p = t._p
  local st = d[0]
  if st == 0 then
    d[2] = P.s16(d[2] + 0x200)
    if d[2] >= d[14] then
      local diff = P.s16(d[14] - d[2])
      local dv = P.s16(P.div(diff, d[14] * 2))
      local md = P.s16(P.mod(diff, d[14] * 2))
      if band(dv, 1) == 0 then
        d[2] = P.s16(d[14] - md)
        d[0] = 1
      else
        d[2] = P.s16(md - d[14])
      end
    end
  elseif st == 1 then
    d[2] = P.s16(d[2] - 0x200)
    if d[2] <= -d[14] then
      local diff = P.s16(d[14] - d[2])
      local dv = P.s16(P.div(diff, d[14] * 2))
      local md = P.s16(P.mod(diff, d[14] * 2))
      if band(dv, 1) == 0 then
        d[2] = P.s16(md - d[14])
        d[0] = 0
      else
        d[2] = P.s16(d[14] - md)
      end
    end
  elseif st == 2 then
    P.monResetRotScale(p)
    P.DestroyAnimVisualTask(t)
    return
  end
  P.monRotScale(p, 0x100, 0x100, d[2])
  if p then
    P.monYOffsetFromRotation(t._side)
    local v = d[2]
    if v < 0 then v = v + 63 end
    p.ox = -P.shr(v, 6)
  end
  d[1] = d[1] + 1
  if d[1] > 8 then
    if d[12] ~= 0 then
      d[12] = d[12] - 1
      d[14] = d[14] - d[13]
      if d[14] < 16 then d[14] = 16 end
    else
      d[0] = 2
    end
  end
end

-- pokefirered/src/battle_anim_effects_3.c:2786
T.FlailMovement = P.task(function(t, vm)
  local d = t.data
  d[0] = 0
  d[1] = 0
  d[2] = 0
  d[3] = 0
  d[12] = 0x20
  d[13] = 0x40
  d[14] = 0x800
  t._p, t._side = P.monSprite(vm, t.ga[0])
  t.fn = H.flailStep
end)

-- pokefirered/src/battle_anim_effects_3.c:2877
C.PainSplitProjectile = P.cb(function(s, vm)
  local d = s.data
  if d[0] == 0 then
    if s.ga[2] == P.ANIM_ATTACKER then
      s.x = P.coordAtk(vm, P.COORD_X_2)
      s.y = P.coordAtk(vm, P.COORD_Y_PIC)
    end
    s.x = s.x + s.ga[0]
    s.y = s.y + s.ga[1]
    d[1] = 0x80
    d[2] = 0x300
    d[3] = s.ga[1]
    d[0] = d[0] + 1
  else
    s.ox = P.shr(d[1], 8)
    s.oy = s.oy + P.shr(d[2], 8)
    if d[4] == 0 and s.oy > -d[3] then
      d[4] = 1
      d[2] = P.s16(P.div(-d[2], 3) * 2)
    end
    d[1] = P.s16(d[1] + 192)
    d[2] = P.s16(d[2] + 128)
    if s.animEnded then P.DestroyAnimSprite(s) end
  end
end)

-- pokefirered/src/battle_anim_effects_3.c:2914
T.PainSplitMovement = P.task(function(t, vm)
  local d = t.data
  if d[0] == 0 then
    local p, side = P.monSprite(vm, t.ga[0])
    t._p, t._side = p, side
    if p then
      local mode = t.ga[1]
      if mode == 0 then
        P.monRotScale(p, 0xE0, 0x140, 0)
        P.monYOffsetFromYScale(vm, side)
      elseif mode == 1 then
        P.monRotScale(p, 0xD0, 0x130, 0xF00)
        P.monYOffsetFromYScale(vm, side)
        if side == "player" then p.oy = p.oy + 16 end
      elseif mode == 2 then
        P.monRotScale(p, 0xD0, 0x130, 0xF100)
        P.monYOffsetFromYScale(vm, side)
        if side == "player" then p.oy = p.oy + 16 end
      end
      p.ox = 2
    end
    d[0] = d[0] + 1
  else
    local p = t._p
    d[2] = d[2] + 1
    if d[2] == 3 then
      d[2] = 0
      if p then p.ox = -p.ox end
    end
    d[1] = d[1] + 1
    if d[1] == 13 then
      P.monResetRotScale(p)
      if p then
        p.ox = 0
        p.oy = 0
      end
      P.DestroyAnimVisualTask(t)
    end
  end
end)

function H.flatterConfettiStep(s)
  local d = s.data
  if d[2] == 0 then
    s.ox = s.ox + P.shr(d[0], 8)
    s.oy = s.oy - P.shr(d[1], 8)
  else
    s.ox = s.ox - P.shr(d[0], 8)
    s.oy = s.oy - P.shr(d[1], 8)
  end
  d[0] = P.s16(d[0] - 22)
  d[1] = P.s16(d[1] - 48)
  if d[0] < 0 then d[0] = 0 end
  d[3] = d[3] + 1
  if d[3] == 31 then P.DestroyAnimSprite(s) end
end

-- pokefirered/src/battle_anim_effects_3.c:2973
C.FlatterConfetti = P.cb(function(s, vm)
  local d = s.data
  local tileOffset = P.Random() % 12
  s.imageValue = s.imageValue + tileOffset
  local rand1 = band(P.Random(), 0x1FF)
  local rand2 = band(P.Random(), 0xFF)
  if band(rand1, 1) ~= 0 then d[0] = 0x5E0 + rand1 else d[0] = 0x5E0 - rand1 end
  if band(rand2, 1) ~= 0 then d[1] = 0x480 + rand2 else d[1] = 0x480 - rand2 end
  d[2] = s.ga[0]
  if d[2] == P.ANIM_ATTACKER then s.x = -8 else s.x = 248 end
  s.y = 104
  s.callbackFn = H.flatterConfettiStep
end)

function H.flatterSpotlightStep(s, vm)
  local d = s.data
  local st = d[1]
  if st == 0 then
    s.invisible = false
    if s.affineAnimEnded then d[1] = d[1] + 1 end
  elseif st == 1 then
    d[0] = d[0] - 1
    if d[0] == 0 then
      P.ChangeSpriteAffineAnim(s, 1)
      d[1] = d[1] + 1
    end
  elseif st == 2 then
    if s.affineAnimEnded then
      s.invisible = true
      d[1] = d[1] + 1
    end
  elseif st == 3 then
    local w = P.win(vm)
    w.winout = 0x3F3F
    w.objwin = not w.objwin
    P.DestroyAnimSprite(s)
  end
end

-- pokefirered/src/battle_anim_effects_3.c:3030
C.FlatterSpotlight = P.cb(function(s, vm)
  local w = P.win(vm)
  w.winout = 0x1F3F
  w.objwin = true
  w.win0 = nil
  s.data[0] = s.ga[2]
  P.InitSpritePosToAnimTarget(s, vm, false)
  P.registerObjWindow(vm, s)
  P.ensureColorOverlay(vm)
  s.invisible = true
  s.callbackFn = H.flatterSpotlightStep
end)

function H.reversalOrbStep(s, vm)
  local d = s.data
  s.ox = P.Sin(d[1], P.shr(d[2], 8))
  s.oy = P.Cos(d[1], P.shr(d[3], 8))
  d[1] = band(d[1] + 9, 0xFF)
  local base = P.subpriorityOf(P.atk(vm))
  if P.u16(d[1]) < 64 or d[1] > 195 then
    s.sub = base - 1
  else
    s.sub = base + 1
  end
  if d[5] == 0 then
    d[2] = P.s16(d[2] + 0x400)
    d[3] = P.s16(d[3] + 0x100)
    d[4] = d[4] + 1
    if d[4] == d[0] then
      d[4] = 0
      d[5] = 1
    end
  elseif d[5] == 1 then
    d[2] = P.s16(d[2] - 0x400)
    d[3] = P.s16(d[3] - 0x100)
    d[4] = d[4] + 1
    if d[4] == d[0] then P.DestroyAnimSprite(s) end
  end
end

-- pokefirered/src/battle_anim_effects_3.c:3079
C.ReversalOrb = P.cb(function(s, vm)
  s.x = P.coordAtk(vm, P.COORD_X_2)
  s.y = P.coordAtk(vm, P.COORD_Y_PIC)
  s.data[0] = s.ga[0]
  s.data[1] = s.ga[1]
  s.callbackFn = H.reversalOrbStep
  H.reversalOrbStep(s, vm)
end)

function H.picImage(species, back)
  local ok, Pokemon = pcall(require, "src.core.game3.pokemon")
  if not ok or not species then return nil end
  local e
  if back and Pokemon.backPic then e = Pokemon.backPic(species) end
  if not e and Pokemon.frontPic then e = Pokemon.frontPic(species) end
  return e and e.image
end

function H.picYOffset(species, back)
  local ok, pc = pcall(require, "src.core.game3.battle.pic_coords")
  if not ok or type(pc) ~= "table" or not species then return 0 end
  local tbl = back and pc.back or pc.front
  return (tbl and tbl[species]) or 0
end

function H.rolePlayStep2(t, vm)
  local d = t.data
  local c = t._clone
  d[10] = P.s16(d[10] - 16)
  d[11] = P.s16(d[11] + 128)
  if c and c.active then
    P.TrySetSpriteRotScale(c, true, d[10], d[11], 0)
    P.sync(c, vm)
  end
  d[12] = d[12] + 1
  if d[12] == 9 then
    if c and c.active then
      P.TryResetSpriteAffineState(c)
      P.DestroyAnimSprite(c)
    end
    t._clone = nil
    t.fn = P.DestroyAnimVisualTaskAndDisableBlend
  end
end

function H.rolePlayStep1(t, vm)
  local d = t.data
  local old = d[10]
  d[10] = d[10] + 1
  if old > 1 then
    d[10] = 0
    d[1] = d[1] + 1
    P.setBld(vm, d[1], 16 - d[1])
    if d[1] == 10 then
      d[10] = 256
      d[11] = 256
      t.fn = H.rolePlayStep2
    end
  end
end

-- pokefirered/src/battle_anim_effects_3.c:3122
T.RolePlaySilhouette = P.task(function(t, vm)
  local d = t.data
  local atk = P.atk(vm)
  local isBackPic = atk == "player"
  local xOffset = isBackPic and -20 or 20
  local species = P.species(vm, P.tgt(vm))
  local x = P.coordAtk(vm, P.COORD_X) + xOffset
  local y = P.coordAtk(vm, P.COORD_Y) + H.picYOffset(species, isBackPic)
  local c = P.CloneMon(vm, atk)
  if c then
    local img = H.picImage(species, isBackPic)
    if img then c.image = img end
    c.x, c.y = x, y
    c.ox, c.oy = 0, 0
    c._mat = nil
    c.sub = 5
    c.pri = 2
    c.zOverride = isBackPic and 205 or 105
    c._objBlend = true
    c.palBlend = { coeff = 16, color = 0x7FFF }
    P.sync(c, vm)
  end
  t._clone = c
  P.setBld(vm, d[1], 16 - d[1])
  d[0] = 0
  t.fn = H.rolePlayStep1
end)

H.rowQuads = setmetatable({}, { __mode = "k" })

function H.rowQuad(img, r)
  local per = H.rowQuads[img]
  if not per then
    per = {}
    H.rowQuads[img] = per
  end
  local q = per[r]
  if not q then
    local iw, ih = img:getDimensions()
    q = love.graphics.newQuad(0, r, iw, 1, iw, ih)
    per[r] = q
  end
  return q
end

function H.acidArmorDraw(t, vm)
  if not (love and love.graphics) then return end
  if not t._drawOn then return end
  local img = P.monImage(vm, t._side)
  if not img then return end
  local cx, cy = P.monCenter(vm, t._side)
  local iw, ih = img:getDimensions()
  local top = floor(cy - ih / 2 + 0.5)
  local left = floor(cx - iw / 2 + 0.5)
  local flip = t._p and t._p.hFlip
  local buf = t._shown
  love.graphics.setColor(1, 1, 1, P.bldAlphaValue(vm))
  for y = 0, 159 do
    local h = buf and buf.h[y] or 0
    local v = buf and buf.v[y] or 0
    if h < 240 then
      local r = y + v - top
      if r >= 0 and r < ih then
        if flip then
          love.graphics.draw(img, H.rowQuad(img, r), left - h + iw, y, 0, -1, 1)
        else
          love.graphics.draw(img, H.rowQuad(img, r), left - h, y)
        end
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
end

function H.acidArmorVblank(t)
  if t._scan == 1 then
    t._shown = t._bufs[t._src]
    t._src = 1 - t._src
  elseif t._scan == 3 then
    t._scan = 0
    t._shown = nil
    if t._drawOn then
      t._drawOn = false
      t.draw = nil
      if t._p then t._p.visible = true end
    end
  end
end

function H.acidArmorStep(t, vm)
  local d = t.data
  H.acidArmorVblank(t)
  local p = t._p
  local st = d[0]
  if st == 0 then
    local buf = t._bufs[t._src]
    d[1] = band(d[1] + 2, 0xFF)
    local sineIndex = d[1]
    d[9] = P.div(0x7E0, d[6])
    d[10] = P.s16(-P.div(d[7] * 2, d[9]))
    d[11] = d[7]
    local var3 = P.shr(d[11], 5)
    d[12] = var3
    local var0 = d[14]
    local i, var1, var2 = 0, 0, 0
    while var0 > d[13] do
      buf.v[var0] = i - var2
      buf.h[var0] = var3 + P.shr(P.SINE[sineIndex + 1], 5)
      sineIndex = band(sineIndex + 10, 0xFF)
      d[11] = P.s16(d[11] + d[10])
      var3 = P.shr(d[11], 5)
      d[12] = var3
      i = i + 1
      var1 = P.s16(var1 + d[6])
      var2 = P.shr(var1, 5)
      var0 = var0 - 1
    end
    while var0 >= 0 do
      t._bufs[0].h[var0] = 240
      t._bufs[1].h[var0] = 240
      var0 = var0 - 1
    end
    d[6] = d[6] + 1
    if d[6] > 63 then
      d[6] = 64
      d[2] = d[2] + 1
      if band(d[2], 1) ~= 0 then d[3] = d[3] - 1 else d[4] = d[4] + 1 end
      P.setBld(vm, d[3], d[4])
      if d[3] == 0 and d[4] == 16 then
        d[2] = 0
        d[3] = 0
        d[0] = d[0] + 1
      end
    else
      d[7] = P.s16(d[7] + d[8])
    end
  elseif st == 1 then
    d[2] = d[2] + 1
    if d[2] > 12 then
      t._scan = 3
      d[2] = 0
      d[0] = d[0] + 1
    end
  elseif st == 2 then
    d[2] = d[2] + 1
    if band(d[2], 1) ~= 0 then d[3] = d[3] + 1 else d[4] = d[4] - 1 end
    P.setBld(vm, d[3], d[4])
    if d[3] == 16 and d[4] == 0 then
      d[2] = 0
      d[3] = 0
      d[0] = d[0] + 1
    end
  elseif st == 3 then
    if p then
      if t._drawOn then p.visible = true end
      p.alpha = 1
    end
    P.DestroyAnimVisualTask(t)
    return
  end
  if p and t._bg then p.alpha = P.bldAlphaValue(vm) end
end

-- pokefirered/src/battle_anim_effects_3.c:3222
T.AcidArmor = P.task(function(t, vm)
  local d = t.data
  local side = (t.ga[0] == P.ANIM_ATTACKER) and P.atk(vm) or P.tgt(vm)
  d[0] = 0
  d[1] = 0
  d[2] = 0
  d[3] = 16
  d[4] = 0
  d[6] = 32
  d[7] = 0
  d[8] = 24
  if side ~= "player" then d[8] = -24 end
  d[13] = P.yWithElevation(vm, side) - 34
  if d[13] < 0 then d[13] = 0 end
  d[14] = d[13] + 66
  t._side = side
  t._p = P.monSprite(vm, t.ga[0])
  t._bufs = { [0] = { h = {}, v = {} }, [1] = { h = {}, v = {} } }
  t._src = 0
  t._scan = 1
  t._bg = P.isMonBg(side)
  if t._bg and t._p and t._p.visible ~= false then
    t._drawOn = true
    t._p.visible = false
    t.z = (side == "player") and 199 or 99
    t.draw = H.acidArmorDraw
  end
  t.fn = H.acidArmorStep
end)

function H.deepInhaleStep(t, vm)
  local d = t.data
  local p = t._affSide and P.monPresent(t._affSide)
  local var0 = d[0]
  d[0] = d[0] + 1
  var0 = P.u16(var0 - 20)
  if var0 < 23 then
    d[1] = d[1] + 1
    if d[1] > 1 then
      d[1] = 0
      d[2] = d[2] + 1
      if p then
        if band(d[2], 1) ~= 0 then p.ox = 1 else p.ox = -1 end
      end
    end
  elseif p then
    p.ox = 0
  end
  if not H.runAffine(t, vm) then P.DestroyAnimVisualTask(t) end
end

-- pokefirered/src/battle_anim_effects_3.c:3400
T.DeepInhale = P.task(function(t, vm)
  t.data[0] = 0
  local _, side = P.monSprite(vm, t.ga[0])
  H.prepareAffine(t, side, "sDeepInhaleAffineAnimCmds")
  t.fn = H.deepInhaleStep
end)

function H.yawnCloudStep(s)
  local d = s.data
  d[0] = d[0] + 1
  local index = band(d[0] * 8, 0xFF)
  d[4] = P.s16(d[4] + d[6])
  d[5] = P.s16(d[5] + d[7])
  s.x = P.shr(d[4], 4)
  s.y = P.shr(d[5], 4)
  s.oy = P.Sin(index, 8)
  if d[0] > 58 then
    d[1] = d[1] + 1
    if d[1] > 1 then
      d[1] = 0
      d[2] = d[2] + 1
      s.invisible = band(d[2], 1) ~= 0
      if d[2] > 3 then P.DestroySpriteAndMatrix(s) end
    end
  end
end

-- pokefirered/src/battle_anim_effects_3.c:3459
C.YawnCloud = P.cb(function(s, vm)
  local d = s.data
  local destX, destY = s.x, s.y
  P.SetSpriteCoordsToAnimAttackerCoords(s, vm)
  P.StartSpriteAffineAnim(s, s.ga[0])
  local startX, startY = s.x, s.y
  d[4] = P.s16(startX * 16)
  d[5] = P.s16(startY * 16)
  d[6] = P.s16(P.div((destX - startX) * 16, 64))
  d[7] = P.s16(P.div((destY - startY) * 16, 64))
  d[0] = 0
  s.callbackFn = H.yawnCloudStep
end)

function H.destroyAfterTimer(s)
  local old = s.data[0]
  s.data[0] = old - 1
  if old <= 0 then P.DestroyAnimSprite(s) end
end

-- pokefirered/src/battle_anim_effects_3.c:3497
C.SmokeBallEscapeCloud = P.cb(function(s, vm)
  s.data[0] = s.ga[3]
  P.StartSpriteAffineAnim(s, s.ga[0])
  if not P.tgtIsPlayer(vm) then s.ga[1] = -s.ga[1] end
  s.x = P.coordAtk(vm, P.COORD_X_2) + s.ga[1]
  s.y = P.coordAtk(vm, P.COORD_Y_PIC) + s.ga[2]
  s.callbackFn = H.destroyAfterTimer
end)

function H.focusBandToggle(t)
  local d = t.data
  if band(P.u16(d[6]), 0x8000) ~= 0 then
    d[1] = d[1] - 1
    if d[1] == -1 then
      if d[9] == 0 then
        d[9] = d[4]
        d[4] = P.s16(-d[4])
      else
        d[9] = 0
      end
      if d[10] == 0 then
        d[10] = d[5]
        d[5] = P.s16(-d[5])
      else
        d[10] = 0
      end
      d[1] = d[13]
    end
  end
end

function H.focusBandApply(t, var0, var1)
  local d = t.data
  local p = t._p
  if not p then return end
  if band(P.u16(d[2]), 0x8000) ~= 0 then
    p.ox = P.s16(d[9] - P.rshift(var0, 8))
  else
    p.ox = P.s16(d[9] + P.rshift(var0, 8))
  end
  if band(P.u16(d[3]), 0x8000) ~= 0 then
    p.oy = P.s16(d[10] - P.rshift(var1, 8))
  else
    p.oy = P.s16(d[10] + P.rshift(var1, 8))
  end
end

function H.focusBandStep2(t, vm)
  local d = t.data
  d[0] = d[0] - 1
  H.focusBandToggle(t)
  H.focusBandApply(t, P.u16(d[7]), P.u16(d[8]))
  if d[0] < 1 then P.DestroyAnimVisualTask(t) end
end

function H.focusBandStep1(t, vm)
  local d = t.data
  d[0] = d[0] - 1
  H.focusBandToggle(t)
  local var0 = P.u16(band(P.u16(d[2]), 0x7FFF) + d[7])
  local var1 = P.u16(band(P.u16(d[3]), 0x7FFF) + d[8])
  H.focusBandApply(t, var0, var1)
  d[7] = P.s16(var0)
  d[8] = P.s16(var1)
  if d[0] < 1 then
    d[0] = 30
    d[13] = 0
    t.fn = H.focusBandStep2
  end
end

-- pokefirered/src/battle_anim_effects_3.c:3612
T.SlideMonForFocusBand = P.task(function(t, vm)
  local d = t.data
  local ga = t.ga
  t._p = P.monPresent(P.atk(vm))
  d[14] = ga[0]
  d[0] = ga[0]
  d[13] = ga[6]
  if ga[3] ~= 0 then d[6] = P.s16(bor(P.u16(d[6]), 0x8000)) end
  if not P.atkIsPlayer(vm) then
    d[2] = ga[1]
    d[3] = ga[2]
  else
    if band(P.u16(ga[1]), 0x8000) ~= 0 then
      d[2] = band(P.u16(ga[1]), 0x7FFF)
    else
      d[2] = P.s16(bor(P.u16(ga[1]), 0x8000))
    end
    if band(P.u16(ga[2]), 0x8000) ~= 0 then
      d[3] = band(P.u16(ga[2]), 0x7FFF)
    else
      d[3] = P.s16(bor(P.u16(ga[2]), 0x8000))
    end
  end
  d[8] = 0
  d[7] = 0
  d[4] = ga[4]
  d[5] = ga[5]
  t.fn = H.focusBandStep1
end)

function H.facadeSweatDrop(s)
  local d = s.data
  s.x = s.x + d[1]
  s.y = s.y + d[2]
  d[0] = d[0] + 1
  if d[0] > 6 then
    local task = s.task
    if task then task.data[d[4]] = task.data[d[4]] - 1 end
    P.DestroyAnimSprite(s)
  end
end

-- pokefirered/src/battle_anim_effects_3.c:3773
C.FacadeSweatDrop = P.cb(H.facadeSweatDrop)

function H.createSweatDroplets(t, vm, lower)
  local d = t.data
  local xOffset, yOffset
  if not lower then
    xOffset, yOffset = 18, -20
  else
    xOffset, yOffset = 30, 20
  end
  local xs = { [0] = d[4] - xOffset, d[4] - xOffset - 4, d[4] + xOffset, d[4] + xOffset + 4 }
  local ys = { [0] = d[5] + yOffset, d[5] + yOffset + 6 }
  for i = 0, 3 do
    local s = P.CreateSprite(vm, "gFacadeSweatDropSpriteTemplate", xs[i], ys[band(i, 1)], d[6] - 5, H.facadeSweatDrop)
    if s then
      s.data[0] = 0
      s.data[1] = (i < 2) and -2 or 2
      s.data[2] = -1
      s.task = t
      s.data[4] = 2
      d[2] = d[2] + 1
    end
  end
end

function H.squishStep(t, vm)
  local d = t.data
  if d[0] == 0 then
    d[1] = d[1] + 1
    if d[1] == 6 then H.createSweatDroplets(t, vm, true) end
    if d[1] == 18 then H.createSweatDroplets(t, vm, false) end
    if not H.runAffine(t, vm) then
      d[3] = d[3] - 1
      if d[3] == 0 then
        d[0] = d[0] + 1
      else
        d[1] = 0
        H.prepareAffine(t, t._affSide, "sFacadeSquishAffineAnimCmds")
      end
    end
  elseif d[0] == 1 then
    if d[2] == 0 then P.DestroyAnimVisualTask(t) end
  end
end

-- pokefirered/src/battle_anim_effects_3.c:3669
T.SquishAndSweatDroplets = P.task(function(t, vm)
  local d = t.data
  if t.ga[1] == 0 then
    P.DestroyAnimVisualTask(t)
    return
  end
  d[0] = 0
  d[1] = 0
  d[2] = 0
  d[3] = t.ga[1]
  local side = (t.ga[0] == P.ANIM_ATTACKER) and P.atk(vm) or P.tgt(vm)
  d[4] = P.coord(vm, side, P.COORD_X)
  d[5] = P.coord(vm, side, P.COORD_Y)
  d[6] = P.subpriorityOf(side)
  local _, mside = P.monSprite(vm, t.ga[0])
  H.prepareAffine(t, mside, "sFacadeSquishAffineAnimCmds")
  t.fn = H.squishStep
end)

H.FACADE_COLORS = {
  [0] = H.rgb(28, 25, 1), H.rgb(28, 21, 5), H.rgb(27, 18, 8), H.rgb(27, 14, 11),
  H.rgb(26, 10, 15), H.rgb(26, 7, 18), H.rgb(25, 3, 21), H.rgb(25, 0, 25),
  H.rgb(25, 0, 23), H.rgb(25, 0, 20), H.rgb(25, 0, 16), H.rgb(25, 0, 13),
  H.rgb(26, 0, 10), H.rgb(26, 0, 6), H.rgb(26, 0, 3), H.rgb(27, 0, 0),
  H.rgb(27, 1, 0), H.rgb(27, 5, 0), H.rgb(27, 9, 0), H.rgb(27, 12, 0),
  H.rgb(28, 16, 0), H.rgb(28, 19, 0), H.rgb(28, 23, 0), H.rgb(29, 27, 0),
}

function H.facadeBlendStep(t, vm)
  local d = t.data
  if d[1] ~= 0 then
    P.monBlend(t._p, 8, H.FACADE_COLORS[d[0]])
    d[0] = d[0] + 1
    if d[0] > 23 then d[0] = 0 end
    d[1] = d[1] - 1
  else
    P.monBlend(t._p, 0, 0)
    P.DestroyAnimVisualTask(t)
  end
end

-- pokefirered/src/battle_anim_effects_3.c:3802
T.FacadeColorBlend = P.task(function(t, vm)
  t.data[0] = 0
  t.data[1] = t.ga[1]
  t._p = P.monSprite(vm, t.ga[0])
  t.fn = H.facadeBlendStep
end)

return { callbacks = C, tasks = T }
