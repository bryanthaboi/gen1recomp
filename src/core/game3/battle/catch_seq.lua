-- pokefirered/src/pokeball.c:441

local Anim = require("src.core.game3.battle.anim")
local State = require("src.core.game3.battle.state")
local Audio = require("src.core.game3.audio")
local SE = require("src.core.game3.se_ids")
local ItemsData = require("src.core.game3.items_data")
local Pokemon = require("src.core.game3.pokemon")
local Catching = require("src.core.game3.battle.catching")
local BallOpen = require("src.core.game3.battle.ball_open")

local MUS_CAUGHT_INTRO = 319
local MUS_CAUGHT = 322

local CatchSeq = {}

CatchSeq._steps = nil
CatchSeq._i = 1
CatchSeq._waiting = false
CatchSeq._waitingMsg = false
CatchSeq._pushMsg = nil
CatchSeq._headless = false
CatchSeq._result = nil -- "catch" | "fail_catch"
CatchSeq._st = nil
CatchSeq._session = nil
CatchSeq._ballId = nil
CatchSeq._caught = false
CatchSeq._shakes = 0

function CatchSeq.reset()
  CatchSeq._steps = nil
  CatchSeq._i = 1
  CatchSeq._waiting = false
  CatchSeq._waitingMsg = false
  CatchSeq._pushMsg = nil
  CatchSeq._headless = false
  CatchSeq._result = nil
  CatchSeq._st = nil
  CatchSeq._session = nil
  CatchSeq._ballId = nil
  CatchSeq._caught = false
  CatchSeq._shakes = 0
  CatchSeq._catchResult = nil
  CatchSeq._ball = nil
  CatchSeq._waitingBall = false
  CatchSeq._target = 1
end

function CatchSeq.busy()
  return CatchSeq._steps ~= nil
end

function CatchSeq.result()
  return CatchSeq._result
end

function CatchSeq.catchResult()
  return CatchSeq._catchResult
end

local function finish()
  CatchSeq._steps = nil
  CatchSeq._i = 1
  CatchSeq._waiting = false
  CatchSeq._waitingMsg = false
end

local function advance()
  CatchSeq._waiting = false
  CatchSeq._i = CatchSeq._i + 1
end

local function wait_busy()
  CatchSeq._waiting = true
end

--- Begin a catch animation sequence.
-- opts: { pushMsg, headless, session }
function CatchSeq.begin(st, itemId, caught, shakes, opts)
  opts = opts or {}
  CatchSeq.reset()
  CatchSeq._st = st
  CatchSeq._ballId = itemId
  CatchSeq._caught = caught and true or false
  CatchSeq._shakes = math.max(0, math.min(4, tonumber(shakes) or 0))
  CatchSeq._pushMsg = opts.pushMsg
  CatchSeq._headless = opts.headless and true or false
  CatchSeq._session = opts.session
  CatchSeq._result = caught and "catch" or "fail_catch"
  CatchSeq._target = tonumber(opts.target) or 1

  local session = opts.session
  if not session then
    local okR, Runtime = pcall(require, "src.core.game3.runtime")
    if okR and Runtime and Runtime.getSession then
      session = Runtime.getSession()
      CatchSeq._session = session
    end
  end

  local playerName = (session and (session.name or session.playerName)) or "RED"
  local ballName = ItemsData.displayName(itemId) or "POKé BALL"
  local ename = (st and st.enemy and st.enemy.mon and (st.enemy.mon.nickname or st.enemy.mon.name))
    or Pokemon.name(st and st.enemy and st.enemy.species) or "POKéMON"

  -- pokefirered/data/battle_scripts_2.s:124
  local DODGE = "It dodged the thrown BALL!\nThis POKéMON can't be caught!"
  if opts.ghostDodge then CatchSeq._result = "fail_catch" end
  if CatchSeq._headless then
    if CatchSeq._pushMsg then
      CatchSeq._pushMsg(playerName .. " used\nthe " .. ballName .. "!")
    end
    if opts.ghostDodge then
      if CatchSeq._pushMsg then CatchSeq._pushMsg(DODGE) end
    elseif caught then
      local res = Catching.storeCaught(session, st and st.enemy, itemId)
      if CatchSeq._pushMsg then
        CatchSeq._pushMsg("Gotcha!\n" .. ename .. " was caught!")
        if res and res.firstTimeCaught then
          CatchSeq._pushMsg(ename .. "'s data was\nadded to the POKéDEX.")
        end
        if res and res.location == "pc" then
          CatchSeq._pushMsg(ename .. " was transferred\nto the PC.")
        end
      end
    else
      if CatchSeq._pushMsg then
        if CatchSeq._shakes == 0 then
          CatchSeq._pushMsg("Oh no! The POKéMON broke free!")
        elseif CatchSeq._shakes == 1 then
          CatchSeq._pushMsg("Aww! It appeared to be caught!")
        elseif CatchSeq._shakes == 2 then
          CatchSeq._pushMsg("Aargh! Almost had it!")
        else
          CatchSeq._pushMsg("Shoot! It was so close too!")
        end
      end
    end
    finish()
    return true
  end

  local steps = {}
  local function add(kind, data)
    steps[#steps + 1] = { kind = kind, data = data or {} }
  end

  add("msg", { text = playerName .. " used\nthe " .. ballName .. "!", wait = opts.ghostDodge and 0 or nil })

  -- pokefirered/src/battle_script_commands.c:9590
  add("throw", {
    caseId = opts.ghostDodge and "ghost" or (caught and 4 or math.min(3, CatchSeq._shakes)),
    itemId = itemId,
  })

  if opts.ghostDodge then
    add("msg", { text = DODGE, wait = 64 })
  elseif caught then
    add("capture_success", {
      ballId = itemId,
      ename = ename,
    })
  else
    add("breakout", {
      shakes = math.min(3, CatchSeq._shakes),
      ename = ename,
    })
  end

  CatchSeq._steps = steps
  CatchSeq._i = 1
  CatchSeq._waiting = false
  return true
end

local function play_se(id)
  pcall(function() Audio.playSe(id) end)
end

-- pokefirered/src/pokeball.c:132
local BALL_ANIMS = {
  [0] = { { 0, 1 } },
  [1] = { { 1, 5 }, { 2, 5 } },
  [2] = { { 1, 5 }, { 0, 5 } },
}

-- pokefirered/src/pokeball.c:163
local BALL_AFFINE = {
  [0] = { { 0, 0, 0, 1 }, jump = 1 },
  [1] = { { 0, 0, -3, 1 }, jump = 1 },
  [2] = { { 0, 0, 3, 1 }, jump = 1 },
  [3] = { { 256, 256, 0, 0 } },
}

-- pokefirered/src/data.c:112
local MON_AFFINE = {
  [0] = { { 0x100, 0x100, 0, 0 } },
  [1] = { { 0x28, 0x28, 0, 0 }, { 0x12, 0x12, 0, 12 } },
}

-- pokefirered/src/battle_anim_special.c:98
local CAPTURE_STARS = { { 10, 2, -3 }, { 15, 0, -4 }, { -10, 2, -4 } }

-- pokefirered/src/sprite.c:1320
local function affine_apply(a, cmd)
  if cmd[4] > 0 then
    a.scale = a.scale + cmd[1]
    a.rotation = (a.rotation + cmd[3] * 256) % 65536
    return cmd[4] - 1
  end
  a.scale = cmd[1]
  a.rotation = (cmd[3] * 256) % 65536
  return 0
end

-- pokefirered/src/sprite.c:1363
local function affine_start(a, num)
  a.num = num
  a.idx = 1
  a.delay = 0
  a.scale = 0x100
  a.rotation = 0
  a.beginning = true
  a.ended = false
end

-- pokefirered/src/sprite.c:1378
local function affine_change(a, num)
  a.num = num
  a.beginning = true
  a.ended = false
end

-- pokefirered/src/sprite.c:1063
local function affine_step(a, anims)
  local cmds = anims[a.num]
  if a.beginning then
    a.idx = 1
    a.beginning = false
    a.ended = false
    a.delay = affine_apply(a, cmds[1])
    return
  end
  -- pokefirered/src/sprite.c:1080
  if a.delay > 0 then
    if not a.paused then
      a.delay = a.delay - 1
      local c = cmds[a.idx]
      a.scale = a.scale + c[1]
      a.rotation = (a.rotation + c[3] * 256) % 65536
    end
    return
  end
  if a.paused then return end
  if cmds[a.idx + 1] then
    a.idx = a.idx + 1
  elseif cmds.jump then
    a.idx = cmds.jump
  else
    a.ended = true
    return
  end
  a.delay = affine_apply(a, cmds[a.idx])
end

-- pokefirered/src/battle_anim_mons.c:988
local function arc_init(s, speed, destX, destY, ampl)
  local d = s.data
  local dx, dy = destX - s.x, destY - s.y
  local xd = math.floor((math.abs(dx) * 256) % 65536 / speed)
  local yd = math.floor((math.abs(dy) * 256) % 65536 / speed)
  xd = xd - xd % 2 + ((dx < 0) and 1 or 0)
  yd = yd - yd % 2 + ((dy < 0) and 1 or 0)
  d[0], d[1], d[2], d[3], d[4] = speed, xd, yd, 0, 0
  d[5] = ampl
  -- pokefirered/src/battle_anim_mons.c:757
  d[6] = math.floor(0x8000 / speed)
  d[7] = 0
end

-- pokefirered/src/battle_anim_mons.c:1034
local function translate_linear(s)
  local d = s.data
  if d[0] == 0 then return true end
  local x = (d[3] + d[1]) % 65536
  local y = (d[4] + d[2]) % 65536
  s.x2 = (d[1] % 2 == 1) and -math.floor(x / 256) or math.floor(x / 256)
  s.y2 = (d[2] % 2 == 1) and -math.floor(y / 256) or math.floor(y / 256)
  d[3], d[4] = x, y
  d[0] = d[0] - 1
  return false
end

-- pokefirered/src/battle_anim_mons.c:766
local function translate_arc(s)
  if translate_linear(s) then return true end
  local d = s.data
  d[7] = d[7] + d[6]
  s.y2 = s.y2 + BallOpen.sin(math.floor(d[7] / 256) % 256, d[5])
  return false
end

-- pokefirered/src/battle_anim_mons.c:775
local function translate_vertical_arc(s)
  if translate_linear(s) then return true end
  local d = s.data
  d[7] = d[7] + d[6]
  s.x2 = s.x2 + BallOpen.sin(math.floor(d[7] / 256) % 256, d[5])
  return false
end

local CB = {}

local function start_anim(b, num)
  b.animNum, b.animBeginning, b.animEnded = num, true, false
end

-- pokefirered/src/battle_anim_special.c:810
function CB.init(b)
  arc_init(b, b.data[0], b.data[1], b.data[2], -40)
  b.cb = CB.arcFlight
end

-- pokefirered/src/battle_anim_special.c:824
-- pokefirered/src/battle_anim_special.c:1404
function CB.ghostDodge2(b)
  if not translate_vertical_arc(b) and (b.y + b.y2) < 65 then return end
  b.data[0] = 0
  b.cb = CB.signalEnd
end

-- pokefirered/src/battle_anim_special.c:1388
function CB.ghostDodge(b)
  b.x, b.y = b.x + b.x2, b.y + b.y2
  b.x2, b.y2 = 0, 0
  arc_init(b, 0x22, b.x - 8, 0x90, 0x20)
  translate_vertical_arc(b)
  b.cb = CB.ghostDodge2
end

function CB.arcFlight(b)
  if not translate_arc(b) then return end
  if b.caseId == "ghost" then
    b.cb = CB.ghostDodge
    return
  end
  start_anim(b, 1)
  b.x, b.y = b.x + b.x2, b.y + b.y2
  b.x2, b.y2 = 0, 0
  for i = 0, 7 do b.data[i] = 0 end
  b.cb = CB.tenFrameDelay
  -- pokefirered/src/battle_anim_special.c:857
  BallOpen.start(b.target or 1, b.x, b.y, b.itemId, false)
  play_se(SE.SE_BALL_OPEN)
end

-- pokefirered/src/battle_anim_special.c:865
function CB.tenFrameDelay(b)
  b.data[5] = b.data[5] + 1
  if b.data[5] == 10 then
    b.task = { state = 0, count = 0, delta = 0, acc = 0, scale = 256 }
    b.cb = CB.shrinkMon
  end
end

-- pokefirered/src/battle_anim_special.c:875
function CB.shrinkMon(b)
  local t, p = b.task, b.mon
  t.count = t.count + 1
  if t.count == 11 then play_se(SE.SE_BALL_TRADE) end
  if t.state == 0 then
    t.scale = 256
    local dist = (b.monY + (p.oy or 0)) - (b.y + b.y2)
    local delta = dist * 256 / 28
    t.delta = (delta < 0) and math.ceil(delta) or math.floor(delta)
    t.state = 1
  elseif t.state == 1 then
    t.scale = t.scale + 0x20
    p.scale = 256 / t.scale
    t.acc = t.acc + t.delta
    p.oy = math.floor(-t.acc / 256)
    if t.scale >= 0x480 then t.state = 2 end
  elseif t.state == 2 then
    p.scale = 1
    p.visible = false
    t.state = 3
  elseif t.count > 10 then
    b.task = nil
    start_anim(b, 2)
    b.data[5] = 0
    b.cb = CB.initialFall
  end
end

-- pokefirered/src/battle_anim_special.c:921
function CB.initialFall(b)
  if not b.animEnded then return end
  local d = b.data
  d[3], d[4], d[5] = 0, 40, 0
  b.y = b.y + BallOpen.cos(0, 40)
  b.y2 = -BallOpen.cos(0, d[4])
  b.cb = CB.bounce
end

local BOUNCE_SE = { SE.SE_BALL_BOUNCE_1, SE.SE_BALL_BOUNCE_2, SE.SE_BALL_BOUNCE_3 }

-- pokefirered/src/battle_anim_special.c:937
function CB.bounce(b)
  local d = b.data
  local lastBounce = false
  local low, hi = d[3] % 256, math.floor(d[3] / 256)
  if low == 0 then
    b.y2 = -BallOpen.cos(d[5], d[4])
    d[5] = d[5] + hi + 4
    if d[5] >= 64 then
      d[4] = d[4] - 10
      d[3] = d[3] + 257
      local count = math.floor(d[3] / 256)
      if count == 4 then lastBounce = true end
      play_se(BOUNCE_SE[count] or SE.SE_BALL_BOUNCE_4)
    end
  elseif low == 1 then
    b.y2 = -BallOpen.cos(d[5], d[4])
    d[5] = d[5] - (hi + 4)
    if d[5] <= 0 then
      d[5] = 0
      d[3] = d[3] - low
    end
  end
  if lastBounce then
    d[3] = 0
    b.y = b.y + BallOpen.cos(64, 40)
    b.y2 = 0
    d[5] = 0
    if b.caseId == 0 then
      b.cb = CB.delayThenBreakOut
    else
      d[4] = 1
      b.cb = CB.initShake
    end
  end
end

-- pokefirered/src/battle_anim_special.c:1005
function CB.initShake(b)
  local d = b.data
  d[3] = d[3] + 1
  if d[3] == 31 then
    d[3] = 0
    b.aff.paused = true
    affine_start(b.aff, 1)
    b.subpx = 0
    b.cb = CB.doShake
    play_se(SE.SE_BALL)
  end
end

local function shake_move(b)
  if b.subpx > 0xFF then
    b.x2 = b.x2 + b.data[4]
    b.subpx = b.subpx % 256
  else
    b.subpx = b.subpx + 0xB0
  end
  b.data[5] = b.data[5] + 1
  b.aff.paused = false
end

local function shake_turn(b)
  local d = b.data
  d[5] = 0
  d[4] = -d[4]
  d[3] = d[3] + 1
  b.aff.paused = false
  affine_change(b.aff, (d[4] < 0) and 2 or 1)
end

-- pokefirered/src/battle_anim_special.c:1018
function CB.doShake(b)
  local d = b.data
  local low = d[3] % 256
  if low == 0 then
    shake_move(b)
    if d[5] + 7 > 14 then
      b.subpx = 0
      d[3] = d[3] + 1
      d[5] = 0
    end
  elseif low == 1 then
    d[5] = d[5] + 1
    if d[5] == 1 then
      shake_turn(b)
    else
      b.aff.paused = true
    end
  elseif low == 2 then
    shake_move(b)
    if d[5] + 12 > 24 then
      b.subpx = 0
      d[3] = d[3] + 1
      d[5] = 0
    end
  elseif low == 3 or low == 4 then
    if low == 3 then
      local v = d[5]
      d[5] = v + 1
      if v < 0 then
        b.aff.paused = true
        return
      end
      shake_turn(b)
    end
    shake_move(b)
    if d[5] + 4 > 8 then
      b.subpx = 0
      d[3] = d[3] + 1
      d[5] = 0
      d[4] = -d[4]
    end
  elseif low == 5 then
    d[3] = d[3] + 0x100
    local state = math.floor(d[3] / 256)
    b.aff.paused = true
    if state == b.caseId then
      b.cb = CB.delayThenBreakOut
    elseif b.caseId == 4 and state == 3 then
      b.cb = CB.initClick
    else
      d[3] = d[3] + 1
    end
  else
    d[5] = d[5] + 1
    if d[5] == 31 then
      d[5] = 0
      d[3] = d[3] - low
      affine_start(b.aff, 3)
      affine_start(b.aff, (d[4] < 0) and 2 or 1)
      play_se(SE.SE_BALL)
    end
  end
end

-- pokefirered/src/battle_anim_special.c:1162
function CB.delayThenBreakOut(b)
  b.data[5] = b.data[5] + 1
  if b.data[5] == 31 then
    b.data[5] = 0
    b.cb = CB.beginBreakOut
  end
end

-- pokefirered/src/battle_anim_special.c:1305
function CB.beginBreakOut(b)
  start_anim(b, 1)
  affine_start(b.aff, 0)
  b.cb = CB.runBreakOut
  BallOpen.start(b.target or 1, b.x, b.y, b.itemId, true)
  play_se(SE.SE_BALL_OPEN)
  b.mon.visible = true
  b.monAff = { paused = false }
  affine_start(b.monAff, 1)
  affine_step(b.monAff, MON_AFFINE)
  b.mon.scale = b.monAff.scale / 256
  b.monData1 = 0x1000
end

-- pokefirered/src/battle_anim_special.c:1327
function CB.runBreakOut(b)
  local p = b.mon
  local nextStep = false
  if b.animEnded then b.invisible = true end
  if b.monAff.ended then
    affine_start(b.monAff, 0)
    nextStep = true
  else
    b.monData1 = b.monData1 - 288
    p.oy = math.floor(b.monData1 / 256)
  end
  if b.animEnded and nextStep then
    p.oy = 0
    p.visible = true
    b.data[0] = 0
    b.cb = CB.signalEnd
  end
end

-- pokefirered/src/battle_anim_special.c:1171
function CB.initClick(b)
  b.animPaused = true
  b.cb = CB.doClick
  b.data[3], b.data[4], b.data[5] = 0, 0, 0
end

-- pokefirered/src/battle_anim_special.c:1298
local function star_cb(p)
  p.invisible = not p.invisible
  if translate_arc(p) then p.dead = true end
end

-- pokefirered/src/battle_anim_special.c:1180
function CB.doClick(b)
  local d = b.data
  d[4] = d[4] + 1
  if d[4] == 40 then
    play_se(SE.SE_BALL_CLICK)
    b.blend.coeff, b.blend.r, b.blend.g, b.blend.b = 6, 0, 0, 0
    -- pokefirered/src/battle_anim_special.c:1266
    for _, c in ipairs(CAPTURE_STARS) do
      local p = BallOpen.spawnSprite(b.x, b.y, 1, star_cb)
      p.invisible = false
      arc_init(p, 24, b.x + c[1], b.y + c[2], c[3])
    end
  elseif d[4] == 60 then
    BallOpen.beginFade(6, 0, { obj = b.blend, delay = 2, color = { 0, 0, 0 } })
  elseif d[4] == 95 then
    pcall(function()
      Audio.stopAll()
      Audio.playSe(MUS_CAUGHT_INTRO)
    end)
  elseif d[4] == 315 then
    b.mon.visible = false
    d[0] = 0
    b.cb = CB.finishClick
  end
end

-- pokefirered/src/battle_anim_special.c:1211
function CB.finishClick(b)
  local d = b.data
  if d[0] == 0 then
    d[1], d[2] = 0, 0
    b.alpha = 1
    BallOpen.beginFade(0, 16, { obj = b.blend, color = { 31, 31, 31 } })
    d[0] = 1
  elseif d[0] == 1 then
    local v = d[1]
    d[1] = v + 1
    if v > 0 then
      d[1] = 0
      d[2] = d[2] + 1
      b.alpha = (16 - d[2]) / 16
      if d[2] == 16 then d[0] = 2 end
    end
  elseif d[0] == 2 then
    b.invisible = true
    d[0] = 3
  elseif not BallOpen.fadeActive() then
    d[0] = 0
    b.cb = CB.signalEnd
  end
end

-- pokefirered/src/battle_anim_special.c:1253
function CB.signalEnd(b)
  if b.data[0] == 0 then
    b.data[0] = -1
    b.finished = true
  else
    b.dead = true
  end
end

-- pokefirered/src/sprite.c:304
local function ball_update(b)
  if b.monAff then
    affine_step(b.monAff, MON_AFFINE)
    b.mon.scale = b.monAff.scale / 256
  end
  b.cb(b)
  local s = b.stage
  if b.dead then
    s.visible, s.blend, s.alpha, s.rot = false, nil, nil, 0
    return
  end
  BallOpen.animate(b)
  affine_step(b.aff, BALL_AFFINE)
  s.visible = not b.invisible
  s.x, s.y = b.x + b.x2, b.y + b.y2
  s.ox, s.oy = 0, 0
  s.frame = b.frame
  s.rot = -b.aff.rotation * math.pi / 32768
  s.blend = (b.blend.coeff > 0) and b.blend or nil
  s.alpha = b.alpha
end

-- pokefirered/src/battle_anim_special.c:734
local function start_ball(d)
  local st = CatchSeq._st
  local target = tonumber(d.target) or CatchSeq._target or 1
  local enemy = Anim.Coords.battler(st, target)
  local sp = enemy and enemy.species
  if not sp and enemy and enemy.mon then
    sp = Pokemon.speciesOf and Pokemon.speciesOf(enemy.mon) or enemy.mon.species or enemy.mon.speciesId
  end
  local base = Anim.coords(st, target) or Anim.ENEMY_MON
  local Ui = require("src.core.game3.battle.ui")
  local monY = base.y
  if Ui.battlerSpriteCenter then
    local _, cy = Ui.battlerSpriteCenter("enemy", sp, { x = base.x, y = base.y })
    monY = cy
  end
  local stage = Anim.stage().ball
  stage.visible, stage.darken, stage.flash, stage.side = false, 0, 0, "enemy"
  local b = {
    x = 32, y = 80, x2 = 0, y2 = 0,
    data = { [0] = 34, base.x, base.y - 16, 0, 0, 0, 0, 0 },
    anims = BALL_ANIMS, animNum = 0, animBeginning = true, animEnded = false, animPaused = false,
    frame = 0, hFlip = false, delay = 0, cmd = 1,
    aff = { paused = false },
    blend = { coeff = 0, r = 0, g = 0, b = 0 },
    alpha = 1,
    subpx = 0,
    caseId = d.caseId or 0,
    itemId = d.itemId,
    mon = Anim.present(target),
    target = target,
    monY = monY,
    stage = stage,
    cb = CB.init,
    update = ball_update,
  }
  affine_start(b.aff, 0)
  return BallOpen.addSprite(b)
end
CatchSeq.startBall = start_ball

local function run_step(step)
  if not step then
    finish()
    return
  end

  local kind = step.kind
  local d = step.data or {}

  if kind == "msg" then
    if CatchSeq._pushMsg and d.text then
      CatchSeq._pushMsg(d.text, d.wait)
    end
    CatchSeq._waiting = true
    CatchSeq._waitingMsg = true
    return
  end

  if kind == "throw" then
    if Anim._headless then
      advance()
      return
    end
    pcall(function() Audio.playSe(SE.SE_BALL_THROW, { pan = 0 }) end)
    CatchSeq._ball = start_ball(d)
    CatchSeq._waitingBall = true
    return
  end

  if kind == "capture_success" then
    local res = Catching.storeCaught(CatchSeq._session, CatchSeq._st and CatchSeq._st.enemy, d.ballId)
    CatchSeq._catchResult = res
    local ename = d.ename or "POKéMON"
    -- pokefirered/src/battle_message.c:475
    if CatchSeq._pushMsg then
      CatchSeq._pushMsg("Gotcha!\n" .. ename .. " was caught!")
    end
    pcall(function()
      Audio.waitSe(MUS_CAUGHT_INTRO, function() Audio.playSong(MUS_CAUGHT) end)
    end)
    if CatchSeq._pushMsg then
      if res and res.firstTimeCaught then
        CatchSeq._pushMsg(ename .. "'s data was\nadded to the POKéDEX.")
      end
      if res and res.location == "pc" then
        CatchSeq._pushMsg(ename .. " was transferred\nto the PC.")
      end
    end
    advance()
    return
  end

  if kind == "breakout" then
    if CatchSeq._pushMsg then
      if d.shakes == 0 then
        CatchSeq._pushMsg("Oh no! The POKéMON broke free!")
      elseif d.shakes == 1 then
        CatchSeq._pushMsg("Aww! It appeared to be caught!")
      elseif d.shakes == 2 then
        CatchSeq._pushMsg("Aargh! Almost had it!")
      else
        CatchSeq._pushMsg("Shoot! It was so close too!")
      end
    end
    advance()
    return
  end

  advance()
end

function CatchSeq.update()
  if not CatchSeq._steps then return true end

  if CatchSeq._waitingBall then
    local b = CatchSeq._ball
    local alive = false
    for _, s in ipairs(BallOpen._sprites) do
      if s == b then alive = true end
    end
    if alive and not b.finished then return false end
    CatchSeq._waitingBall = false
    advance()
  end

  if CatchSeq._waitingMsg then
    local Ui = require("src.core.game3.battle.ui")
    local pending = false
    if Ui.dialogPending then
      pending = Ui.dialogPending()
    elseif not Ui._headless then
      pending = (Ui._showing == true) or (Ui._queue and #Ui._queue > 0)
    end
    if pending then
      return false
    end
    CatchSeq._waitingMsg = false
    CatchSeq._waiting = false
    advance()
  end

  if CatchSeq._waiting then
    if not Anim.busy() then
      advance()
    else
      return false
    end
  end

  local step = CatchSeq._steps[CatchSeq._i]
  if not step then
    finish()
    return true
  end
  run_step(step)
  return false
end

return CatchSeq
