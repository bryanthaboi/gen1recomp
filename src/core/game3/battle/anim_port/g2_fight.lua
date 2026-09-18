local P = require("src.core.game3.battle.anim_port.g2_pret")

local CB = {}
local TASKS = {}

-- pokefirered/src/battle_anim_fight.c:416
function CB.SlideHandOrFootToTarget(s)
  if P.arg(7) == 1 and P.atk() ~= "player" then
    P.setArg(1, -P.arg(1))
    P.setArg(3, -P.arg(3))
  end
  P.startAnim(s, P.arg(6))
  P.setArg(6, 0)
  P.AnimTravelDiagonally(s)
end

-- pokefirered/src/battle_anim_fight.c:428
function CB.JumpKick(s)
  CB.SlideHandOrFootToTarget(s)
end

-- pokefirered/src/battle_anim_fight.c:445
function CB.BasicFistOrFoot(s)
  P.startAnim(s, P.arg(4))
  if P.arg(3) == 0 then
    P.InitSpritePosToAnimAttacker(s, true)
  else
    P.InitSpritePosToAnimTarget(s, true)
  end
  s.data[0] = P.arg(2)
  s.pcb = P.WaitAnimForDuration
  P.storeCallback(s, P.DestroyAnimSprite)
end

local function fist_random_step(s)
  if s.data[0] == 0 then
    local child = s.g2.child
    if child then P.destroy(child) end
    P.destroy(s)
  else
    s.data[0] = s.data[0] - 1
  end
end

-- pokefirered/src/battle_anim_fight.c:457
function CB.FistOrFootRandomPos(s)
  local b
  if P.arg(0) == 0 then b = P.atk() else b = P.tgt() end
  if P.arg(2) < 0 then P.setArg(2, P.Random() % 5) end
  P.startAnim(s, P.arg(2))
  s.x = P.coord(b, 2)
  s.y = P.coord(b, 3)
  local xMod = P.div(P.coordAttr(b, P.ATTR_WIDTH), 2)
  local yMod = P.div(P.coordAttr(b, P.ATTR_HEIGHT), 4)
  local x = (xMod ~= 0) and (P.Random() % xMod) or 0
  local y = (yMod ~= 0) and (P.Random() % yMod) or 0
  if P.Random() % 2 == 1 then x = -x end
  if P.Random() % 2 == 1 then y = -y end
  if b == "player" then y = P.s16(y + 0xFFF0) end
  s.x = s.x + x
  s.y = s.y + y
  s.data[0] = P.arg(1)
  local child = P.createSprite("gBasicHitSplatSpriteTemplate", s.x, s.y, s.subpriority + 1, false, false, false)
  if child then
    P.startAffineAnim(child, 0)
    s.g2.child = child
  end
  s.pcb = fist_random_step
end

local function cross_chop_step(s)
  s.data[5] = s.data[5] + 1
  if s.data[5] == 11 then
    s.data[2] = s.x - s.x2
    s.data[4] = s.y - s.y2
    s.data[0] = 8
    s.x = s.x + s.x2
    s.y = s.y + s.y2
    s.y2 = 0
    s.x2 = 0
    s.pcb = P.StartAnimLinearTranslation
    P.storeCallback(s, P.DestroyAnimSprite)
  end
end

-- pokefirered/src/battle_anim_fight.c:512
function CB.CrossChopHand(s)
  P.InitSpritePosToAnimTarget(s, true)
  s.data[0] = 30
  if P.arg(2) == 0 then
    s.data[2] = s.x - 20
  else
    s.data[2] = s.x + 20
    s.pHFlip = true
  end
  s.data[4] = s.y - 20
  s.pcb = P.StartAnimLinearTranslation
  P.storeCallback(s, cross_chop_step)
end

local function sliding_kick_step(s)
  if not P.AnimTranslateLinear(s) then
    s.y2 = s.y2 + P.Sin(P.asr(s.data[7], 8), s.data[5])
    s.data[7] = P.s16(s.data[7] + s.data[6])
  else
    P.destroy(s)
  end
end

-- pokefirered/src/battle_anim_fight.c:547
function CB.SlidingKick(s)
  P.InitSpritePosToAnimTarget(s, true)
  if P.atk() ~= "player" then P.setArg(2, -P.arg(2)) end
  s.data[0] = P.arg(3)
  s.data[1] = s.x
  s.data[2] = s.x + P.arg(2)
  s.data[3] = s.y
  s.data[4] = s.y
  P.InitAnimLinearTranslation(s)
  s.data[5] = P.arg(5)
  s.data[6] = P.arg(4)
  s.data[7] = 0
  s.pcb = sliding_kick_step
end

local function spinning_finish(s)
  P.startAffineAnim(s, 0)
  s.affineAnimPaused = true
  s.data[0] = 20
  s.pcb = P.WaitAnimForDuration
  P.storeCallback(s, P.DestroyAnimSprite)
end

-- pokefirered/src/battle_anim_fight.c:585
function CB.SpinningKickOrPunch(s)
  P.InitSpritePosToAnimTarget(s, true)
  P.startAnim(s, P.arg(2))
  s.data[0] = P.arg(3)
  s.pcb = P.WaitAnimForDuration
  P.storeCallback(s, spinning_finish)
end

local function stomp_end(s)
  s.data[0] = 15
  s.pcb = P.WaitAnimForDuration
  P.storeCallback(s, P.DestroyAnimSprite)
end

local function stomp_step(s)
  s.data[0] = s.data[0] - 1
  if s.data[0] == -1 then
    s.data[0] = 6
    s.data[2] = P.coord(P.tgt(), 2)
    s.data[4] = P.coord(P.tgt(), 3)
    s.pcb = P.StartAnimLinearTranslation
    P.storeCallback(s, stomp_end)
  end
end

-- pokefirered/src/battle_anim_fight.c:607
function CB.StompFoot(s)
  P.InitSpritePosToAnimTarget(s, true)
  s.data[0] = P.arg(2)
  s.pcb = stomp_step
end

local function dizzy_duck(s)
  if s.data[0] == 0 then
    P.InitSpritePosToAnimTarget(s, true)
    s.data[1] = P.arg(2)
    s.data[2] = P.arg(3)
    s.data[0] = s.data[0] + 1
  else
    s.data[4] = P.s16(s.data[4] + s.data[1])
    s.x2 = P.asr(s.data[4], 8)
    s.y2 = P.Sin(s.data[3], s.data[2])
    s.data[3] = (s.data[3] + 3) % 256
    if s.data[3] > 100 then s.invisible = (s.data[3] % 2) == 1 end
    if s.data[3] > 120 then P.destroy(s) end
  end
end

-- pokefirered/src/battle_anim_fight.c:633
function CB.DizzyPunchDuck(s)
  dizzy_duck(s)
  s.pcb = dizzy_duck
end

local function brick_wall_step(s)
  local d = s.data
  if d[0] == 0 then
    d[1] = d[1] - 1
    if d[1] == 0 then
      if d[2] == 0 then
        P.destroy(s)
      else
        d[0] = d[0] + 1
      end
    end
  elseif d[0] == 1 then
    d[1] = d[1] + 1
    if d[1] > 1 then
      d[1] = 0
      d[3] = d[3] + 1
      if d[3] % 2 == 1 then s.x2 = 2 else s.x2 = -2 end
    end
    d[2] = d[2] - 1
    if d[2] == 0 then P.destroy(s) end
  end
end

-- pokefirered/src/battle_anim_fight.c:656
function CB.BrickBreakWall(s)
  local b = (P.arg(0) == 0) and P.atk() or P.tgt()
  s.x = P.coord(b, 0)
  s.y = P.coord(b, 1)
  s.x = s.x + P.arg(1)
  s.y = s.y + P.arg(2)
  s.data[0] = 0
  s.data[1] = P.arg(3)
  s.data[2] = P.arg(4)
  s.data[3] = 0
  s.pcb = brick_wall_step
end

local function brick_shard_step(s)
  s.x = s.x + s.data[6]
  s.y = s.y + s.data[7]
  s.data[0] = s.data[0] + 1
  if s.data[0] > 40 then P.destroy(s) end
end

-- pokefirered/src/battle_anim_fight.c:708
function CB.BrickBreakWallShard(s)
  local b = (P.arg(0) == P.ANIM_ATTACKER) and P.atk() or P.tgt()
  s.x = P.coord(b, 0) + P.arg(2)
  s.y = P.coord(b, 1) + P.arg(3)
  s.tileBase = s.tileBase + P.arg(1) * 16
  s.data[0] = 0
  local a1 = P.arg(1)
  if a1 == 0 then
    s.data[6], s.data[7] = -3, -3
  elseif a1 == 1 then
    s.data[6], s.data[7] = 3, -3
  elseif a1 == 2 then
    s.data[6], s.data[7] = -3, 3
  elseif a1 == 3 then
    s.data[6], s.data[7] = 3, 3
  else
    P.destroy(s)
    return
  end
  s.pcb = brick_shard_step
end

local function superpower_orb_step(s)
  s.data[0] = s.data[0] + 1
  if s.data[0] == 180 then
    s.objBlend = false
    s.data[0] = 16
    s.data[1] = s.x
    s.data[2] = P.coord(s.g2.dest, 2)
    s.data[3] = s.y
    s.data[4] = P.coord(s.g2.dest, 3)
    P.InitAnimLinearTranslation(s)
    P.storeCallback(s, P.DestroySpriteAndMatrix)
    s.pcb = P.AnimTranslateLinear_WithFollowup
  end
end

-- pokefirered/src/battle_anim_fight.c:755
function CB.SuperpowerOrb(s)
  if P.arg(0) == 0 then
    s.x = P.coord(P.atk(), 2)
    s.y = P.coord(P.atk(), 3)
    s.oamPriority = P.bgPriority(P.atk())
    s.g2.dest = P.tgt()
  else
    s.oamPriority = P.bgPriority(P.tgt())
    s.g2.dest = P.atk()
  end
  s.data[0] = 0
  s.data[1] = 12
  s.data[2] = 8
  s.pcb = superpower_orb_step
end

local function superpower_rock_step2(s)
  s.data[2] = P.s16(s.data[2] + s.data[0])
  s.data[3] = P.s16(s.data[3] + s.data[1])
  s.x = P.asr(s.data[2], 4)
  s.y = P.asr(s.data[3], 4)
  local edgeX = P.u16(s.x + 8)
  if edgeX > 256 or s.y < -8 or s.y > 120 then P.destroy(s) end
end

local function superpower_rock_step1(s)
  if s.data[0] ~= 0 then
    s.g2.fy = s.g2.fy - s.data[6]
    s.y = P.asr(s.g2.fy, 8)
    if s.y < -8 then
      P.destroy(s)
    else
      s.data[0] = s.data[0] - 1
    end
  else
    local pos0 = P.coord(P.atk(), 2)
    local pos1 = P.coord(P.atk(), 3)
    local pos2 = P.coord(P.tgt(), 2)
    local pos3 = P.coord(P.tgt(), 3)
    s.data[0] = pos2 - pos0
    s.data[1] = pos3 - pos1
    s.data[2] = P.s16(s.x * 16)
    s.data[3] = P.s16(s.y * 16)
    s.pcb = superpower_rock_step2
  end
end

-- pokefirered/src/battle_anim_fight.c:792
function CB.SuperpowerRock(s)
  s.x = P.arg(0)
  s.y = 120
  s.data[0] = P.arg(3)
  s.g2.fy = s.y * 256
  s.data[6] = P.arg(1)
  s.tileBase = s.tileBase + P.arg(2) * 4
  s.pcb = superpower_rock_step1
end

-- pokefirered/src/battle_anim_fight.c:847
function CB.SuperpowerFireball(s)
  local b
  if P.arg(0) == P.ANIM_ATTACKER then
    s.x = P.coord(P.atk(), 2)
    s.y = P.coord(P.atk(), 3)
    b = P.tgt()
    s.oamPriority = P.bgPriority(P.atk())
  else
    b = P.atk()
    s.oamPriority = P.bgPriority(P.tgt())
  end
  if b == "player" then
    s.pHFlip = true
    s.pVFlip = true
  end
  s.data[0] = 16
  s.data[1] = s.x
  s.data[2] = P.coord(b, 2)
  s.data[3] = s.y
  s.data[4] = P.coord(b, 3)
  P.InitAnimLinearTranslation(s)
  P.storeCallback(s, P.DestroyAnimSprite)
  s.pcb = P.AnimTranslateLinear_WithFollowup
end

local function arm_thrust_step(s)
  if s.data[0] == s.data[4] then
    P.destroy(s)
    return
  end
  s.data[0] = s.data[0] + 1
end

-- pokefirered/src/battle_anim_fight.c:884
function CB.ArmThrustHit(s)
  s.x = P.coord(P.tgt(), 2)
  s.y = P.coord(P.tgt(), 3)
  s.data[1] = P.arg(3)
  s.data[2] = P.arg(0)
  s.data[3] = P.arg(1)
  s.data[4] = P.arg(2)
  local turn = P.turn() % 256
  if P.tgt() == "player" then turn = turn + 1 end
  if turn % 2 == 1 then
    s.data[2] = -s.data[2]
    s.data[1] = s.data[1] + 1
  end
  P.startAnim(s, s.data[1])
  s.x2 = s.data[2]
  s.y2 = s.data[3]
  s.pcb = arm_thrust_step
end

-- pokefirered/src/battle_anim_fight.c:908
function CB.RevengeScratch(s)
  if P.arg(2) == P.ANIM_ATTACKER then
    P.InitSpritePosToAnimAttacker(s, false)
  else
    P.InitSpritePosToAnimTarget(s, false)
  end
  if P.atk() ~= "player" then P.startAnim(s, 1) end
  s.pcb = P.RunStoredCallbackWhenAnimEnds
  P.storeCallback(s, P.DestroyAnimSprite)
end

-- pokefirered/src/battle_anim_fight.c:923
function CB.FocusPunchFist(s)
  if s.affineAnimEnded then
    s.data[1] = (s.data[1] + 40) % 256
    s.x2 = P.Sin(s.data[1], 2)
    s.data[0] = s.data[0] + 1
    if s.data[0] > 40 then P.destroy(s) end
  end
  s.pcb = CB.FocusPunchFist
end

local function sky_uppercut_tail(t)
  local d = t.data
  d[10] = P.s16(d[10] + 2816)
  local sc = t.g2.scroll
  if P.tgt() == "player" then
    sc.x = P.u16(sc.x + P.asr(d[9], 8))
  else
    sc.x = P.u16(sc.x - P.asr(d[9], 8))
  end
  sc.y = P.u16(sc.y + P.asr(d[10], 8))
  d[9] = d[9] % 256
  d[10] = d[10] % 256
  if P.arg(7) == -1 then
    sc.x = 0
    sc.y = 0
    local Anim = P.anim()
    if Anim and Anim._bg3Scroll == sc then Anim._bg3Scroll = nil end
    P.destroyTask(t)
  end
end

local function sky_uppercut_step(t)
  local d = t.data
  if d[0] == 1 then
    d[8] = d[8] - 1
    if d[8] == -1 then d[0] = d[0] + 1 end
  elseif d[0] >= 2 then
    d[9] = P.s16(d[9] + 1280)
  end
  sky_uppercut_tail(t)
end

-- pokefirered/src/battle_anim_fight.c:934
TASKS.MoveSkyUppercutBg = P.task(function(t)
  local vm = P.vm
  if vm and not vm.bg3 then vm.bg3 = { x = 0, y = 0 } end
  local sc = vm and vm.bg3 or { x = 0, y = 0 }
  t.g2.scroll = sc
  local Anim = P.anim()
  if Anim then Anim._bg3Scroll = sc end
  t.data[8] = P.arg(0)
  t.data[0] = 1
  t.func = sky_uppercut_step
  sky_uppercut_tail(t)
end)

return { cb = CB, tasks = TASKS }
