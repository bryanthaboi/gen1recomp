-- Battle intro presentation (pret BeginBattleIntro + DoPokeballSendOutAnimation).
-- Separate from AnimSeq (hit loop); same contract as ExpSeq.

local Anim = require("src.core.game3.battle.anim")
local BallOpen = require("src.core.game3.battle.ball_open")
local State = require("src.core.game3.battle.state")
local Audio = require("src.core.game3.audio")
local SE = require("src.core.game3.se_ids")
local RomText = require("src.core.game3.rom_text")
local BattleText = require("src.core.game3.battle.battle_text")
local Adapter = require("src.core.game3.battle.adapter")
local ShinySeq = require("src.core.game3.battle.shiny_seq")
local MonAnimBattle = require("src.core.game3.battle.mon_anim_battle")
local TrainerPic = require("src.core.game3.trainer_pic")

local IntroSeq = {}

IntroSeq._steps = nil
IntroSeq._i = 1
IntroSeq._waiting = false
IntroSeq._pushMsg = nil
IntroSeq._headless = false
IntroSeq._opts = nil
IntroSeq._st = nil

function IntroSeq.reset()
  IntroSeq._steps = nil
  IntroSeq._i = 1
  IntroSeq._waiting = false
  IntroSeq._waitingMsg = false
  IntroSeq._waitingFade = false
  IntroSeq._waitingCry = false
  IntroSeq._waitingGen = false
  IntroSeq._pendingSlideIn = nil
  IntroSeq._pushMsg = nil
  IntroSeq._opts = nil
  IntroSeq._st = nil
  IntroSeq._cryQueue = nil
  IntroSeq._waitingMonAnim = nil
end

function IntroSeq.busy()
  return IntroSeq._steps ~= nil
end

local function finish()
  IntroSeq._steps = nil
  IntroSeq._i = 1
  IntroSeq._waiting = false
  IntroSeq._waitingMsg = false
  IntroSeq._waitingFade = false
  IntroSeq._waitingCry = false
  IntroSeq._pendingSlideIn = nil
end

local function advance()
  IntroSeq._waiting = false
  IntroSeq._i = IntroSeq._i + 1
end

local function stage()
  return Anim.stage()
end

local TRAINER_STEVEN_PARTNER = 3075

-- pokeemerald/src/battle_intro.c:113
function IntroSeq.win0Rows(f)
  if f < 1 then return 80, 80 end
  local top = math.max(48, 81 - f)
  if f > 33 then top = math.max(0, 48 - 4 * (f - 33)) end
  return top, 161 - top
end

local SLIDE_KIND = { [0] = 1, [1] = 1, [2] = 2, [3] = 2, [4] = 2, [5] = 1, [6] = 1, [7] = 1, [8] = 3, [9] = 3 }
local ENV_LONG_GRASS, ENV_SAND, ENV_UNDERWATER, ENV_WATER = 1, 2, 3, 4

-- pokeemerald/src/battle_intro.c:37
function IntroSeq.entrySlide(st, key)
  if not st or st.link then return nil end
  if st.partner and st.partner.trainerId ~= TRAINER_STEVEN_PARTNER then return nil end
  local env = tonumber(st.terrain) or 9
  if key == "frontier" then return 3, env end
  if key == "groudon" or key == "kyogre" then
    local game = require("src.core.game3.profile").forSession().id
    if game ~= "ruby" then return 2, ENV_UNDERWATER end
  end
  return SLIDE_KIND[env] or 3, env
end

local function water_y(n)
  local P = require("src.core.game3.battle.anim_port.g3_pret")
  local d6 = 0
  local y = 0
  for _ = 1, n do
    y = P.div(P.Sin2(d6 + 90), 512) - 8
    if d6 < 180 then d6 = d6 + 4 else d6 = d6 + 6 end
    if d6 == 360 then d6 = 0 end
  end
  return y
end

-- pokeemerald/src/battle_intro.c:86
function IntroSeq.entryFrame(kind, env, n)
  if n >= 154 then return nil end
  local k = n - 66
  if kind == 1 then
    local y = 0
    -- pokeemerald/src/battle_intro.c:129
    if k > 0 then y = (env == ENV_LONG_GRASS) and -math.min(2 * k, 80) or -math.min(k, 56) end
    return 6 * n, y, 1
  elseif kind == 2 then
    -- pokeemerald/src/battle_intro.c:171
    local x = ((env == ENV_UNDERWATER) and 6 or 8) * n
    local y = (env == ENV_WATER) and water_y(n) or 0
    local eva = 16
    if k > 0 then eva = math.max(0, 16 - (math.floor((k - 1) / 4) + 1)) end
    return x, y, eva / 16
  end
  -- pokeemerald/src/battle_intro.c:283
  local eva = 8
  if k > 0 then eva = math.max(0, 8 - (math.floor((k - 1) / 6) + 1)) end
  return 8 * n, 0, eva / 16
end

local function tray_se(name, pan)
  pcall(function() Audio.playSe(SE[name], { pan = pan }) end)
end

local function tray_spawn(bar, fn)
  local Task = require("src.core.game3.task")
  if bar.task then Task.cancel(bar.task); Anim._stageTasks[bar.task] = nil end
  local t = Task.spawn(function() return fn() end, { onDone = function(task) Anim._stageTasks[task.id] = nil end })
  bar.task = t.id
  Anim._stageTasks[t.id] = true
  return t
end

local function accel_step(b)
  local v = b.d3 + 56
  b.d3 = v - v % 16
  return math.floor(v / 16)
end

-- pokeemerald/src/battle_interface.c:1817
function IntroSeq.trayEnterTick(bar, isOpponent)
  if bar.ox ~= 0 then bar.ox = bar.ox + bar.d0 end
  local busy = bar.ox ~= 0
  for i = 1, 6 do
    local b = bar.ballState[i]
    if not b.done then
      busy = true
      if b.delay > 0 then
        b.delay = b.delay - 1
      else
        -- pokeemerald/src/battle_interface.c:1833
        local move = accel_step(b)
        if isOpponent then
          b.x2 = math.min(0, b.x2 + move)
        else
          b.x2 = math.max(0, b.x2 - move)
        end
        if b.x2 == 0 then
          b.done = true
          local pan = isOpponent and -64 or 63
          tray_se((bar.balls[i] or "empty") == "empty" and "SE_BALL_TRAY_EXIT" or "SE_BALL_TRAY_BALL", pan)
        end
      end
      bar.ballOx[i] = b.x2
    end
  end
  return not busy
end

-- pokeemerald/src/battle_interface.c:1450
function IntroSeq.trayEnterState(bar, balls, isOpponent)
  bar.visible = true
  bar.balls = balls or { "ok" }
  bar.alpha = 1
  bar.extended = false
  bar.exiting = false
  bar.ox = isOpponent and -100 or 100
  bar.d0 = isOpponent and 5 or -5
  bar.ballOx, bar.ballHidden, bar.ballState = {}, {}, {}
  for i = 1, 6 do
    local delay = isOpponent and ((7 - i) * 7 + 10) or ((i - 1) * 7 + 10)
    local x2 = isOpponent and -120 or 120
    bar.ballState[i] = { delay = delay, x2 = x2, d3 = 0, done = false }
    bar.ballOx[i] = x2
  end
  return bar
end

function IntroSeq.showTray(s, side, balls, delay)
  local bar = s.partyBar[side]
  local isOpponent = side == "enemy"
  IntroSeq.trayEnterState(bar, balls, isOpponent)
  if Anim._headless then
    bar.ox = 0
    for i = 1, 6 do bar.ballState[i].done, bar.ballState[i].x2, bar.ballOx[i] = true, 0, 0 end
    return
  end
  local wait = delay or 0
  bar.visible = wait == 0
  if wait == 0 then tray_se("SE_BALL_TRAY_ENTER", 0) end
  tray_spawn(bar, function()
    if wait > 0 then
      wait = wait - 1
      if wait == 0 then
        bar.visible = true
        -- pokeemerald/src/battle_interface.c:1666
        tray_se("SE_BALL_TRAY_ENTER", 0)
      end
      return false
    end
    return IntroSeq.trayEnterTick(bar, isOpponent)
  end)
end

-- pokeemerald/src/battle_interface.c:1671
function IntroSeq.trayExitState(bar, isOpponent)
  bar.exiting = true
  bar.extended = true
  bar.blend = 16
  bar.blendTick = 0
  bar.alpha = 1
  bar.d0 = (bar.d0 or (isOpponent and 5 or -5))
  bar.d0 = bar.d0 >= 0 and math.floor(bar.d0 / 2) or -math.floor(-bar.d0 / 2)
  bar.d1 = 0
  bar.ballState = bar.ballState or {}
  bar.ballOx = bar.ballOx or {}
  bar.ballHidden = bar.ballHidden or {}
  for i = 1, 6 do
    local b = bar.ballState[i] or { x2 = 0 }
    bar.ballState[i] = b
    b.delay = isOpponent and 7 * (6 - i) or 7 * (i - 1)
    b.d3 = 0
    b.x2 = b.x2 or 0
    b.done = false
  end
  return bar
end

local function tray_center_x(i, isOpponent)
  local m = require("src.ui.game3.battle_chrome").manifest() or {}
  if isOpponent then
    local x = (m.partyBarOpponent and m.partyBarOpponent.x) or 104
    return x - 24 - 10 * (6 - i) + 4
  end
  local x = (m.partyBarPlayer and m.partyBarPlayer.x) or 136
  return x + 24 + 10 * (i - 1) + 4
end

function IntroSeq.trayExitTick(bar, isOpponent)
  -- pokeemerald/src/battle_interface.c:1823
  bar.d1 = bar.d1 + 32
  local step = math.floor(bar.d1 / 16)
  if bar.d0 > 0 then bar.ox = bar.ox + step else bar.ox = bar.ox - step end
  bar.d1 = bar.d1 % 16
  for i = 1, 6 do
    local b = bar.ballState[i]
    if not b.done then
      if b.delay > 0 then
        b.delay = b.delay - 1
      else
        -- pokeemerald/src/battle_interface.c:1878
        local move = accel_step(b)
        if isOpponent then b.x2 = b.x2 + move else b.x2 = b.x2 - move end
        local cx = tray_center_x(i, isOpponent) + b.x2
        if cx > 248 or cx < -8 then
          b.done = true
          bar.ballHidden[i] = true
        end
      end
      bar.ballOx[i] = b.x2
    end
  end
  -- pokeemerald/src/battle_interface.c:1727
  if bar.blend > 0 then
    if bar.blendTick % 2 == 0 then bar.blend = bar.blend - 1 end
    bar.blendTick = bar.blendTick + 1
    bar.alpha = math.max(0, bar.blend) / 16
    return false
  end
  -- pokeemerald/src/battle_interface.c:1740
  bar.blend = bar.blend - 1
  if bar.blend == -1 then
    bar.visible = false
    bar.alpha = 0
  end
  return bar.blend <= -3
end

function IntroSeq.hideTray(s, side)
  local bar = s.partyBar[side]
  if not bar.visible and not bar.task then return end
  local isOpponent = side == "enemy"
  if Anim._headless or not bar.ballState then
    bar.visible = false
    return
  end
  IntroSeq.trayExitState(bar, isOpponent)
  tray_spawn(bar, function() return IntroSeq.trayExitTick(bar, isOpponent) end)
end

local function present_of(key)
  if type(key) ~= "number" then return Anim.present(key) end
  return Anim.present(key) or (key < 2 and Anim.present(State.sideOf(key))) or nil
end

local function healthbox_of(s, key)
  local hb = s and s.healthbox
  if not hb then return nil end
  if type(key) ~= "number" then return hb[key] end
  return hb[key] or (key < 2 and hb[State.sideOf(key)]) or nil
end

local function center_of(st, key)
  if type(key) == "number" and Anim.coords then
    local a, b = Anim.coords(st, key)
    if type(a) == "table" then return a.x or a[1], a.y or a[2] end
    if a then return a, b end
  end
  local side = (type(key) == "number") and State.sideOf(key) or key
  local base = (side == "player") and Anim.PLAYER_MON or Anim.ENEMY_MON
  return base.x, base.y
end

local function battler_of(st, key)
  if not st then return nil end
  if type(key) == "number" then return State.battler(st, key) end
  return st[key]
end

local function ball_for(s, key, st)
  local b
  if type(key) ~= "number" then
    b = s.ball
  else
    s.balls = s.balls or {}
    b = s.balls[key]
    if not b then
      b = { visible = false, x = 0, y = 0, frame = 0, rot = 0, battler = key, side = State.sideOf(key) }
      s.balls[key] = b
    end
  end
  local mon = battler_of(st, key)
  mon = mon and mon.mon
  -- pokefirered/src/pokeball.c:373
  b.ballId = BallOpen.ballIdForItem(mon and mon.pokeball)
  return b
end

local function present_ids(st, ids)
  local out = {}
  for _, id in ipairs(ids or {}) do
    if st and not State.isAbsent(st, id) and State.battler(st, id) then out[#out + 1] = id end
  end
  return out
end

local function ball_status(mon)
  if not mon then return "empty" end
  local hp = tonumber(mon.hp) or 0
  if hp <= 0 then return "faint" end
  local status = mon.status
  if status and status ~= 0 and status ~= "" then return "status" end
  return "ok"
end

local function player_party_balls(party)
  local balls = {}
  local count = #(party or {})
  for i = 1, 6 do
    if i <= count and party[i] then
      balls[i] = ball_status(party[i])
    else
      balls[i] = "empty"
    end
  end
  return balls
end

local function enemy_party_balls(foeParty, partySize)
  local balls = {}
  local count = math.max(1, math.min(6, tonumber(partySize) or (foeParty and #foeParty) or 1))
  local s = 6
  for i = 1, 6 do
    if i <= count then
      local mon = foeParty and foeParty[i]
      balls[s] = mon and ball_status(mon) or "ok"
    else
      balls[s] = "empty"
    end
    s = s - 1
  end
  return balls
end

-- pokefirered/src/battle_gfx_sfx_util.c:1045
local function release_cry_mode(mon)
  if not mon then return 0 end
  local status = mon.status
  if status and status ~= 0 and status ~= "" then return 11 end
  local ok, BattleChrome = pcall(require, "src.ui.game3.battle_chrome")
  if ok and BattleChrome and BattleChrome.hpBarLevel then
    local lvl = BattleChrome.hpBarLevel(mon.hp, mon.maxHp)
    if lvl ~= "green" and lvl ~= "full" then return 11 end
  end
  return 0
end
IntroSeq.releaseCryMode = release_cry_mode

function IntroSeq.introText(st)
  return BattleText.get(BattleText.INTROMSG, Adapter.fill(st, { opponentMon1 = st.enemy,
    opponentMon2 = st.double and State.battler(st, 3) or nil }))
end

local intro_msg = IntroSeq.introText

-- pokefirered/src/battle_setup.c:320
local function unveil_ghost(st)
  local p = Anim.present("enemy")
  if p then p.ghostUnveiled = true end
  if st and st.enemy and st.enemy.mon and st.enemy.mon.nickname == RomText.plain("gText_Ghost") then
    st.enemy.mon.nickname = nil
  end
end

-- pokefirered/src/battle_message.c:1574
function IntroSeq.headlessGhostIntro(st)
  if not (st and st.ghostBattle) then return {} end
  if not st.ghostUnveiled then return { intro_msg(st) } end
  unveil_ghost(st)
  return { intro_msg(st), BattleText.get("STRINGID_SILPHSCOPEUNVEILED"), BattleText.get("STRINGID_GHOSTWASMAROWAK") }
end

local function build_wild(st, opts)
  local steps = {}
  local function add(kind, data)
    steps[#steps + 1] = { kind = kind, data = data or {} }
  end
  local playerGender = (st.oldManTutorial and 5) or (st.backPicOverride) or opts.playerGender or 0
  add("fade", { mode = "FROM_BLACK", instant = true })
  -- pret: player back sprite slides in with the BG intro even in wild battles
  -- (BattleIntroDrawTrainersOrMonsSprites → EmitDrawTrainerPic for PLAYER_LEFT).
  -- pokefirered/src/battle_intro.c:145
  add("bgslide", {
    frames = 154,
    unlockAt = 35,
    slidePlayer = true,
    slideEnemyMon = true,
    playerFrom = 240,
    playerTo = 0,
    enemyMonFrom = -240,
    enemyMonTo = 0,
    slideFrames = 120,
    darken = 10 / 16,
    gender = playerGender,
  })
  add("shiny_check", { side = "enemy" })
  add("cry", { side = "enemy" })  add("undarken", { side = "enemy", frames = 10 })
  add("healthbox", { side = "enemy", frames = 23, from = -115 })
  -- pokefirered/src/battle_message.c:1551
  add("msg", { text = intro_msg(st) })
  if st.ghostBattle and st.ghostUnveiled then
    -- pokefirered/data/battle_scripts_1.s:3820
    add("wait", { frames = 32 })
    add("msg", { text = BattleText.get("STRINGID_SILPHSCOPEUNVEILED"), linger = true })
    add("general", { name = "SILPH_SCOPED", side = "enemy" })
    add("unveil", {})
    add("wait", { frames = 32 })
    add("msg", { text = BattleText.get("STRINGID_GHOSTWASMAROWAK") })
  end
  if st.safari then
    -- pokefirered/src/battle_controller_safari.c:608
    add("healthbox", { side = "player", frames = 23, from = 115 })
    add("wait", { frames = 3 })
    return steps
  end
  if st.oldManTutorial then
    -- pokefirered/src/battle_controller_oak_old_man.c
    -- In Oak/Old Man tutorial, the player's Pokémon is not sent out and there is no player healthbox.
    -- The Old Man backsprite stays at (0, 0) and the battle transitions straight to action selection.
    add("wait", { frames = 3 })
    return steps
  end
  -- pokefirered/src/battle_message.c:1592
  add("msg", { text = IntroSeq.sendOutText(st, "player"), linger = true })
  add("player_throw", {})
  add("shiny_check", { side = "player" })
  add("healthbox", { side = "player", frames = 23, from = 115 })
  add("wait", { frames = 3 })
  return steps
end

function IntroSeq.sendOutText(st, side)
  local double = st.double and true or false
  local fill = { side = side, double = double }
  if side == "player" then
    fill.playerMon1 = State.battler(st, 0)
    fill.playerMon2 = double and State.battler(st, 2) or nil
    if double and State.isAbsent(st, 2) then fill.double = false end
  else
    fill.opponentMon1 = State.battler(st, 1)
    fill.opponentMon2 = double and State.battler(st, 3) or nil
    if double and State.isAbsent(st, 3) then fill.double = false end
  end
  return BattleText.get(BattleText.INTROSENDOUT, Adapter.fill(st, fill))
end

local function build_trainer(st, opts)
  local steps = {}
  local function add(kind, data)
    steps[#steps + 1] = { kind = kind, data = data or {} }
  end
  local Trainers = require("src.core.game3.scripting.trainers")
  local strings = Trainers.introStrings(
    opts.trainerId or st.trainerId,
    State.displayName(st.enemy),
    { rivalName = opts.rivalName })
  local info = strings.info or {}
  local enemyBalls = enemy_party_balls(st.foeParty, info.partySize or (st.foeParty and #st.foeParty) or 1)
  if st.trainerB and st.foeHalf then
    -- pokeemerald/src/battle_interface.c:1597
    local slots = {}
    for i = 1, 3 do slots[i] = (i <= st.foeHalf) and st.foeParty[i] or false end
    for i = 1, 3 do slots[3 + i] = st.foeParty[st.foeHalf + i] or false end
    for i = 1, 6 do enemyBalls[7 - i] = slots[i] and ball_status(slots[i]) or "empty" end
    strings.wants = IntroSeq.introText(st)
  elseif st.frontierTrainer and not (opts.trainerId or st.trainerId) then
    strings.wants, strings.sentOut = IntroSeq.introText(st), IntroSeq.sendOutText(st, "enemy")
  end
  local playerBalls = player_party_balls(st.playerParty or (st.player and { st.player.mon }))

  add("fade", { mode = "FROM_BLACK", instant = true })
  -- pret: DrawTrainerPic for both sides during BG slide; sprites wait off-screen
  -- until gIntroSlideFlags clears, then SpriteCB_TrainerSlideIn (~120f at 2px/frame).
  -- pokefirered/src/battle_intro.c:145
  add("bgslide", {
    frames = 154,
    unlockAt = 35,
    slidePlayer = true,
    slideEnemy = true,
    playerFrom = 240,
    playerTo = 0,
    enemyFrom = -240,
    enemyTo = 0,
    slideFrames = 120,
    picId = opts.trainerPicId or info.pic,
    gender = opts.playerGender or 0,
  })
  add("partybar", {
    enemyBalls = enemyBalls,
    playerBalls = playerBalls,
    frames = 20,
  })
  if st.double then
    local foeIds = present_ids(st, { 1, 3 })
    local plIds = present_ids(st, { 0, 2 })
    local sentOut = strings.sentOut
    if #foeIds == 2 then
      -- pokefirered/src/battle_message.c:1611
      sentOut = IntroSeq.sendOutText(st, "enemy")
    end
    local goText = IntroSeq.sendOutText(st, "player")
    add("msg", { text = strings.wants })
    add("msg", { text = sentOut })
    add("opponent_sendout", { toX = 280, frames = 35, ids = foeIds })
    add("shiny_check", { ids = foeIds })
    add("cry", { side = "enemy", release = true, ids = foeIds })
    add("healthbox", { side = "enemy", frames = 23, from = -115, ids = foeIds })
    add("msg", { text = goText, linger = true })
    add("player_throw", { ids = plIds })
    add("shiny_check", { ids = plIds })
    add("healthbox", { side = "player", frames = 23, from = 115, ids = plIds })
    add("wait", { frames = 3 })
    return steps
  end
  add("msg", { text = strings.wants })
  add("msg", { text = strings.sentOut })
  add("opponent_sendout", { toX = 280, frames = 35 })
  add("shiny_check", { side = "enemy" })
  add("cry", { side = "enemy", release = true })
  add("healthbox", { side = "enemy", frames = 23, from = -115 })
  add("msg", { text = IntroSeq.sendOutText(st, "player"), linger = true })
  add("player_throw", {})
  add("shiny_check", { side = "player" })
  add("healthbox", { side = "player", frames = 23, from = 115 })
  add("wait", { frames = 3 })
  return steps
end

function IntroSeq.multiTrainerPics(st, playerGender)
  if not (st and st.multi and st.linkGenders) then return nil end
  local LB = require("src.core.game3.link.battle")
  local own = tonumber(st.linkOwn) or 0
  local g = st.linkGenders
  local function front(gender) return (gender == 1) and LB.TRAINER_PIC_LEAF or LB.TRAINER_PIC_RED end
  local towerA = st.towerLinkMulti and st.trainerPicId or nil
  local towerB = st.towerLinkMulti and st.trainerB and st.trainerB.pic or nil
  return {
    -- pokefirered/src/battle_controller_link_opponent.c:1133
    -- pokeemerald/src/battle_controller_link_opponent.c:1228
    enemyPic = towerA or front(g[1]), enemyX = 200,
    enemyPic2 = towerB or front(g[3]), enemyX2 = 152,
    -- pokefirered/src/battle_controller_player.c:2171
    gender = g[own] or playerGender or 0, x = (own == 2) and 90 or 32,
    -- pokefirered/src/battle_controller_link_partner.c:1106
    partnerGender = g[(own + 2) % 4] or 0, partnerX = (own == 2) and 32 or 90,
  }
end

--- Begin intro. Returns false when headless (caller pushes strings).
function IntroSeq.begin(st, opts)
  opts = opts or {}
  IntroSeq.reset()
  IntroSeq._opts = opts
  IntroSeq._st = st
  IntroSeq._pushMsg = opts.pushMsg
  IntroSeq._headless = opts.headless and true or false
  if IntroSeq._headless or not st then
    return false
  end

  local s = stage()
  s.slide = 0
  s.slideDone = false
  -- pokeemerald/src/battle_main.c:636
  s.win0 = nil
  if not (st.partner and st.partner.trainerId ~= TRAINER_STEVEN_PARTNER) then
    s.win0 = { 80, 80 }
  end
  s.trainer.player.visible = false
  s.trainer.enemy.visible = false
  s.ball.visible = false
  s.healthbox.player.visible = false
  s.healthbox.enemy.visible = false
  s.partyBar.player.visible = false
  s.partyBar.enemy.visible = false
  Anim.present("player").visible = false
  Anim.present("enemy").visible = false
  Anim.present("player").ox = 0
  Anim.present("enemy").ox = 0
  Anim.present("player").darken = 0
  Anim.present("enemy").darken = 0
  Anim.present("player").scale = 1
  Anim.present("enemy").scale = 1
  if st.double then
    s.balls = {}
    for id = 0, 3 do
      local p = present_of(id)
      if p then p.visible, p.ox, p.darken, p.scale = false, 0, 0, 1 end
      local hb = healthbox_of(s, id)
      if hb then hb.visible = false end
    end
  end

  local playerGender = (st.oldManTutorial and 5) or (st.backPicOverride) or opts.playerGender or 0
  s.bgSlide = { enemyOx = -240, playerOx = 240 }
  s.entry = nil
  local entryKey = require("src.core.game3.battle.bg").sheetKey()
  local kind, env = IntroSeq.entrySlide(st, entryKey)
  if kind then
    s.entry = { key = entryKey, kind = kind, env = env, x = 0, y = 0, alpha = (kind == 3) and 0.5 or 1 }
  end
  s.trainer.player.visible = true
  s.trainer.player.gender = playerGender
  s.trainer.player.ox = 240
  s.trainer.player.frame = TrainerPic.backIdleFrame(playerGender)

  if st.wild then
    local p = Anim.present("enemy")
    p.visible = true
    p.ox = -240
    p.darken = 10 / 16
    IntroSeq._steps = build_wild(st, opts)
  else
    s.trainer.enemy.visible = true
    s.trainer.enemy.picId = opts.trainerPicId or st.trainerPicId
    s.trainer.enemy.ox = -240
    s.trainer.enemy.x, s.trainer.enemy.pic2, s.trainer.enemy.x2 = nil, nil, nil
    s.trainer.player.x, s.trainer.player.gender2, s.trainer.player.x2 = nil, nil, nil
    local pics = IntroSeq.multiTrainerPics(st, playerGender)
    if st.trainerB then
      -- pokeemerald/src/battle_controller_opponent.c:1296
      s.trainer.enemy.x = 200
      s.trainer.enemy.pic2, s.trainer.enemy.x2 = st.trainerB.pic, 152
    end
    if pics then
      s.trainer.enemy.picId, s.trainer.enemy.x = pics.enemyPic, pics.enemyX
      s.trainer.enemy.pic2, s.trainer.enemy.x2 = pics.enemyPic2, pics.enemyX2
      s.trainer.player.gender, s.trainer.player.x = pics.gender, pics.x
      s.trainer.player.gender2, s.trainer.player.x2 = pics.partnerGender, pics.partnerX
    end
    if st.partner and st.partner.backPic then
      -- pokeemerald/src/battle_controller_player_partner.c:1304
      s.trainer.player.x = 32
      s.trainer.player.gender2, s.trainer.player.x2 = st.partner.backPic, 90
    end
    IntroSeq._steps = build_trainer(st, opts)
  end
  IntroSeq._steps = MonAnimBattle.introSteps(IntroSeq._steps, st.wild)
  IntroSeq._i = 1
  return true
end

local function wait_busy()
  IntroSeq._waiting = true
end

local function run_step(step)
  local kind = step.kind
  local d = step.data or {}
  local s = stage()

  if kind == "mon_anim" then
    for _, key in ipairs(d.ids or {}) do
      MonAnimBattle.start(key, d.kind, { st = IntroSeq._st, noCry = d.noCry })
    end
    advance()
    return
  end

  if kind == "mon_anim_wait" then
    IntroSeq._waitingMonAnim = d.ids
    return
  end

  if kind == "shiny_check" then
    local Battle = package.loaded["src.core.game3.battle"]
    local st = IntroSeq._st or (Battle and Battle._st)
    local keys = d.ids or { d.id ~= nil and d.id or d.side or "enemy" }
    local battlers = {}
    for _, key in ipairs(keys) do
      battlers[#battlers + 1] = battler_of(st, key)
    end
    if ShinySeq.startMany(battlers, keys) then
      -- FireRed starts shiny sparkle tasks before the healthbox animation and
      -- waits for both to drain. Advancing here lets the next healthbox step
      -- schedule its tween while the shared animation VM remains busy.
      advance()
      return
    end
    advance()
    return
  end

  if kind == "fade" then
    local okF, Fade = pcall(require, "src.ui.game3.fade")
    -- pokefirered/src/battle_main.c:648
    if d.instant then
      if okF and Fade and Fade.clear then Fade.clear() end
      advance()
      return
    end
    if okF and Fade and Fade.begin then
      local mode = Fade.MODE and Fade.MODE[d.mode or "FROM_BLACK"] or 0
      IntroSeq._waiting = true
      IntroSeq._waitingFade = true
      Fade.begin(mode, d.speed or 1, function()
        IntroSeq._waitingFade = false
        IntroSeq._waiting = false
        advance()
      end)
    else
      advance()
    end
    return
  end

  if kind == "bgslide" then
    local frames = d.frames or 154
    local unlockAt = d.unlockAt or 35
    local slideFrames = d.slideFrames or 120
    local needSpriteSlide = d.slidePlayer or d.slideEnemy or d.slideEnemyMon
    s.bgSlide = s.bgSlide or { enemyOx = 0, playerOx = 0 }
    -- pret DrawTrainersOrMonsSprites: park sprites off-screen immediately;
    -- SpriteCB_TrainerSlideIn starts once gIntroSlideFlags clears (unlockAt).
    if d.slidePlayer then
      s.trainer.player.visible = true
      s.trainer.player.gender = d.gender or 0
      s.trainer.player.ox = d.playerFrom or 240
      s.trainer.player.frame = TrainerPic.backIdleFrame(s.trainer.player.gender)
      s.bgSlide.playerOx = d.playerFrom or 240
    end
    if d.slideEnemy then
      s.trainer.enemy.visible = true
      s.trainer.enemy.picId = d.picId
      s.trainer.enemy.ox = d.enemyFrom or -240
      s.bgSlide.enemyOx = d.enemyFrom or -240
    end
    if d.slideEnemyMon then
      local p = Anim.present("enemy")
      p.visible = true
      p.ox = d.enemyMonFrom or d.from or -240
      p.darken = d.darken or (10 / 16)
      s.bgSlide.enemyOx = d.enemyMonFrom or d.from or -240
    end
    wait_busy()
    local spritesStarted = false
    local spritesDone = not needSpriteSlide
    local bgDone = false
    local function try_advance()
      if bgDone and spritesDone then
        s.bgSlide.enemyOx = 0
        s.bgSlide.playerOx = 0
        advance()
      end
    end
    local function start_sprite_slide()
      if spritesStarted or not needSpriteSlide then return end
      spritesStarted = true
      local pFrom = d.playerFrom or 240
      local pTo = d.playerTo or 0
      local eFrom = d.enemyFrom or -240
      local eTo = d.enemyTo or 0
      local mFrom = d.enemyMonFrom or d.from or -240
      local mTo = d.enemyMonTo or d.to or 0
      Anim.tweenStage(slideFrames, function(u)
        if d.slidePlayer then
          s.trainer.player.ox = pFrom + (pTo - pFrom) * u
          s.bgSlide.playerOx = pFrom + (pTo - pFrom) * u
        end
        if d.slideEnemy then
          s.trainer.enemy.ox = eFrom + (eTo - eFrom) * u
          s.bgSlide.enemyOx = eFrom + (eTo - eFrom) * u
        end
        if d.slideEnemyMon then
          local p = Anim.present("enemy")
          p.ox = mFrom + (mTo - mFrom) * u
          s.bgSlide.enemyOx = mFrom + (mTo - mFrom) * u
        end
      end, function()
        if d.slidePlayer then
          s.trainer.player.ox = pTo
          s.bgSlide.playerOx = pTo
        end
        if d.slideEnemy then
          s.trainer.enemy.ox = eTo
          s.bgSlide.enemyOx = eTo
        end
        if d.slideEnemyMon then
          Anim.present("enemy").ox = mTo
          s.bgSlide.enemyOx = mTo
        end
        spritesDone = true
        try_advance()
      end)
    end
    Anim.tweenStage(frames, function(u, t)
      s.slide = u
      local e = s.entry
      if e then
        local x, y, alpha = IntroSeq.entryFrame(e.kind, e.env, t and t.frames or math.floor(u * frames + 0.5))
        if x then e.x, e.y, e.alpha = x, y, alpha else s.entry = nil end
      end
      if s.win0 then
        local top, bottom = IntroSeq.win0Rows(math.floor(u * frames + 0.5))
        if top <= 0 then s.win0 = nil else s.win0[1], s.win0[2] = top, bottom end
      end
      if u * frames >= unlockAt then
        s.slideDone = true
        start_sprite_slide()
      end
    end, function()
      s.slide = 1
      s.win0 = nil
      s.entry = nil
      s.slideDone = true
      start_sprite_slide()
      bgDone = true
      try_advance()
    end)
    return
  end

  if kind == "slidein" then
    if d.who == "enemy_mon" then
      local p = Anim.present("enemy")
      p.visible = true
      p.ox = d.from or -240
      p.darken = d.darken or (10 / 16)
      wait_busy()
      local function start_move()
        Anim.tweenStage(d.frames or 120, function(u)
          p.ox = (d.from or -240) + ((d.to or 0) - (d.from or -240)) * u
        end, function()
          p.ox = d.to or 0
          advance()
        end)
      end
      if s.slideDone then
        start_move()
      else
        -- Wait until intro slide releases sprites.
        IntroSeq._pendingSlideIn = start_move
        wait_busy()
      end
      return
    end
    if d.who == "both_trainers" then
      s.trainer.enemy.visible = true
      s.trainer.enemy.picId = d.picId
      s.trainer.enemy.ox = d.enemyFrom or -240
      s.trainer.player.visible = true
      s.trainer.player.gender = d.gender or 0
      s.trainer.player.ox = d.playerFrom or 240
      s.trainer.player.frame = TrainerPic.backIdleFrame(s.trainer.player.gender)
      wait_busy()
      local function start_move()
        Anim.tweenStage(d.frames or 120, function(u)
          s.trainer.enemy.ox = (d.enemyFrom or -240)
            + ((d.enemyTo or 0) - (d.enemyFrom or -240)) * u
          s.trainer.player.ox = (d.playerFrom or 240)
            + ((d.playerTo or 0) - (d.playerFrom or 240)) * u
        end, function()
          s.trainer.enemy.ox = d.enemyTo or 0
          s.trainer.player.ox = d.playerTo or 0
          advance()
        end)
      end
      if s.slideDone then
        start_move()
      else
        IntroSeq._pendingSlideIn = start_move
        wait_busy()
      end
      return
    end
  end

  if kind == "undarken" then
    local p = Anim.present(d.side or "enemy")
    local from = p.darken or 0
    wait_busy()
    Anim.tweenStage(d.frames or 10, function(u)
      p.darken = from * (1 - u)
    end, function()
      p.darken = 0
      advance()
    end)
    return
  end

  if kind == "partybar" then
    -- pokeemerald/src/battle_controller_player.c:3022
    IntroSeq.showTray(s, "player", d.playerBalls, 0)
    -- pokeemerald/src/battle_controller_opponent.c:1938
    IntroSeq.showTray(s, "enemy", d.enemyBalls, 2)
    advance()
    return
  end

  if kind == "msg" then
    if d.linger and d.text then
      require("src.core.game3.battle.ui").pushTimed(d.text, 0)
    elseif IntroSeq._pushMsg and d.text then
      IntroSeq._pushMsg(d.text)
    end
    -- pret waits for PrintString / controller exec before send-out / slide-out.
    -- Do not advance past this step until Ui has shown + dismissed the line.
    IntroSeq._waiting = true
    IntroSeq._waitingMsg = true
    return
  end

  if kind == "trainerexit" then
    local side = d.side or "enemy"
    local tr = s.trainer[side]
    local from = tr.ox or 0
    local to = (side == "enemy") and (d.toX or 280) - 176 or (d.toX or -40) - 80
    -- Store as ox delta from resting center: resting ox=0 at center.
    -- Enemy exit: center 176 → 280 ⇒ ox 0 → 104
    if side == "enemy" then
      to = (d.toX or 280) - 176
    else
      to = (d.toX or -40) - 80
    end
    IntroSeq.hideTray(s, side)
    wait_busy()
    Anim.tweenStage(d.frames or 35, function(u)
      tr.ox = from + (to - from) * u
    end, function()
      tr.ox = to
      tr.visible = false
      advance()
    end)
    return
  end

  if kind == "opponent_sendout" then
    local Battle = package.loaded["src.core.game3.battle"]
    local st = Battle and Battle._st
    local keys = d.ids or { "enemy" }
    local mons = {}
    for n, key in ipairs(keys) do
      local cx, cy = center_of(st, key)
      local ball = ball_for(s, key, st)
      ball.visible = true
      ball.frame = 0
      ball.rot = 0
      ball.side = "enemy"
      ball.x = cx
      ball.y = cy + 24
      mons[n] = { key = key, ball = ball }
    end
    local tr = s.trainer.enemy
    local exitFrom = tr.ox or 0
    local exitTo = (d.toX or 280) - 176
    -- pokeemerald/src/battle_controller_opponent.c:1884
    IntroSeq.hideTray(s, "enemy")
    wait_busy()
    -- pret OpponentHandleIntroTrainerBallThrow: starts linear slide-out (35 frames)
    -- AND StartSendOutAnim (16f delay + 12f emergence).
    local totalFrames = d.frames or 35
    local openedSe = false
    Anim.tweenStage(totalFrames, function(u, t)
      local f = t.frames
      -- Opponent trainer slides offscreen (35 frames)
      tr.ox = exitFrom + (exitTo - exitFrom) * math.min(1, f / totalFrames)
      if f >= totalFrames then
        tr.visible = false
      end
      for _, m in ipairs(mons) do
        local ball = m.ball
        -- Ball opens after 16 frames delay (SpriteCB_OpponentMonSendOut)
        if f == 16 then
          ball.frame = 1
          if not openedSe then
            openedSe = true
            pcall(function() Audio.playSe(SE.SE_BALL_OPEN) end)
          end
          local p = present_of(m.key)
          if p then
            p.visible = true
            p.ox = 0
            p.oy = 16
            p.scale = 0.16
            p.darken = 0
          end
          Anim.ballOpen(m.key, ball.x, ball.y)
        end
        -- Emergence over 12 frames (frames 16..28) matching pret BATTLER_AFFINE_EMERGE
        if f > 16 and f <= 28 then
          local eu = (f - 16) / 12
          local p = present_of(m.key)
          if p then
            p.oy = 16 * (1 - eu)
            p.scale = 0.16 + 0.84 * eu
          end
          ball.frame = (eu < 0.5) and 1 or 2
        end
        if f > 28 then
          local p = present_of(m.key)
          if p then
            p.oy = 0
            p.scale = 1
          end
          ball.visible = false
        end
      end
    end, function()
      tr.visible = false
      tr.ox = exitTo
      for _, m in ipairs(mons) do
        m.ball.visible = false
        local p = present_of(m.key)
        if p then
          p.oy = 0
          p.scale = 1
        end
      end
      advance()
    end)
    return
  end

  if kind == "player_throw" then
    local Battle = package.loaded["src.core.game3.battle"]
    local st = Battle and Battle._st
    local keys = d.ids or { "player" }
    local tr = s.trainer.player
    if not tr.visible then
      tr.visible = true
      tr.ox = 0
      tr.gender = (IntroSeq._opts and IntroSeq._opts.playerGender) or 0
      tr.frame = TrainerPic.backIdleFrame(tr.gender)
    end
    -- pokeemerald/src/battle_controller_player.c:2955
    IntroSeq.hideTray(s, "player")
    -- pokeemerald/src/battle_controller_player.c:2931
    local pose = TrainerPic.backAnims(tr.gender).throw
    local poseFrame, poseLeft, poseI = 0, 0, 0
    local exitTo = -120
    local mons = {}
    for n, key in ipairs(keys) do
      local pcx, pcy = center_of(st, key)
      mons[n] = { key = key, ball = ball_for(s, key, st), tx = pcx, ty = pcy + 24 }
    end
    local openedSe = false
    wait_busy()
    Anim.tweenStage(57, function(u, t)
      local f = t.frames
      if poseLeft <= 0 then
        poseI = poseI + 1
        local entry = pose[poseI]
        if entry then
          poseFrame = entry[1]
          poseLeft = entry[2]
        end
      end
      poseLeft = poseLeft - 1
      tr.frame = poseFrame
      if f <= 50 then
        tr.ox = exitTo * (f / 50)
      else
        tr.visible = false
        tr.ox = exitTo
      end
      for _, m in ipairs(mons) do
        local ball = m.ball
        -- pret Task_StartSendOutAnim (31f delay) + Task_DoPokeballSendOutAnim (1f delay) -> spawn at frame 32
        if f == 32 then
          ball.visible = true
          ball.frame = 0
          ball.rot = 0
          ball.side = "player"
          local ox, oy = require("src.core.game3.battle.pokedude").sendOutOrigin(st)
          ball.x = ox
          ball.y = oy
          ball._sx, ball._sy = ox, oy
          ball._tx, ball._ty = m.tx, m.ty
        end
        -- pret SpriteCB_PlayerMonSendOut_1 / 2: 25 frames arc flight with affine rotation
        if f > 32 and f <= 57 and ball.visible then
          local bu = (f - 32) / 25
          local sx, sy = ball._sx, ball._sy
          local tx, ty = ball._tx, ball._ty
          ball.x = sx + (tx - sx) * bu
          ball.y = sy + (ty - sy) * bu + (-30 * 4 * bu * (1 - bu))
          -- pret sAffineAnim_BallRotate_4: 25 units per frame (approx 0.613 rad/frame)
          ball.rot = (f - 32) * ((25 / 256) * math.pi * 2)
        end
      end
    end, function()
      tr.visible = false
      tr.ox = exitTo
      if not openedSe then
        openedSe = true
        pcall(function() Audio.playSe(SE.SE_BALL_OPEN) end)
      end
      for _, m in ipairs(mons) do
        m.ball.frame = 1
        m.ball.rot = 0
        Anim.ballOpen(m.key, m.ball.x, m.ball.y)
        local p = present_of(m.key)
        if p then
          p.visible = true
          p.ox = 0
          p.oy = 16
          p.scale = 0.16
        end
      end
      if not d.ids then
        local b = st and st.player
        local species = b and (b.species or (b.mon and (b.mon.species or b.mon.speciesId)))
        if species then
          -- pokefirered/src/pokeball.c:782
          pcall(function() Audio.playCry(species, release_cry_mode(b.mon), -25) end)
        end
      end
      -- pret BATTLER_AFFINE_EMERGE: 12 frames scaling 40/256 to 256/256
      Anim.tweenStage(12, function(uu)
        for _, m in ipairs(mons) do
          local p = present_of(m.key)
          if p then
            p.oy = 16 * (1 - uu)
            p.scale = 0.16 + 0.84 * uu
          end
          m.ball.frame = (uu < 0.5) and 1 or 2
        end
      end, function()
        for _, m in ipairs(mons) do
          local p = present_of(m.key)
          if p then
            p.oy = 0
            p.scale = 1
          end
          m.ball.visible = false
          m.ball.rot = 0
        end
        if d.ids and #d.ids > 0 then
          IntroSeq._cryQueue = { side = "player", ids = d.ids }
        end
        advance()
      end)
    end)
    return
  end

  if kind == "general" then
    local side = d.side or "enemy"
    local Battle = package.loaded["src.core.game3.battle"]
    local st = Battle and Battle._st
    local b = st and st[side]
    local sp = b and (b.species or (b.mon and b.mon.species))
    local AnimCtx = require("src.core.game3.battle.anim_ctx")
    wait_busy()
    IntroSeq._waitingGen = true
    Anim.launchGeneral(d.name, {
      attackerSide = side,
      targetSide = side,
      isReversed = side == "enemy",
      attackerSpecies = sp,
      targetSpecies = sp,
      animArg = 0,
      ctx = AnimCtx.build(side, side, { animArg = 0 }),
      onEnd = function()
        if IntroSeq._waitingGen then
          IntroSeq._waitingGen = false
          advance()
        end
      end,
    })
    return
  end

  if kind == "unveil" then
    local Battle = package.loaded["src.core.game3.battle"]
    unveil_ghost(Battle and Battle._st)
    advance()
    return
  end

  if kind == "cry" and d.ids then
    IntroSeq._cryQueue = { side = d.side or "enemy", ids = d.ids }
    advance()
    return
  end

  if kind == "cry" then
    local side = d.side or "enemy"
    local Battle = package.loaded["src.core.game3.battle"]
    local st = Battle and Battle._st
    local battler = st and st[side]
    local species = battler and (battler.species
      or (battler.mon and (battler.mon.species or battler.mon.speciesId)))
    if species then
      -- pokefirered/src/battle_main.c:1899
      local mode = d.release and release_cry_mode(battler.mon) or 0
      Audio.playCry(species, mode, (side == "player") and -25 or 25)
    end
    IntroSeq._waiting = true
    IntroSeq._waitingCry = true
    return
  end

  if kind == "healthbox" and d.ids then
    local from = d.from or ((d.side == "player") and 115 or -115)
    local boxes = {}
    for _, id in ipairs(d.ids) do
      local hb = healthbox_of(s, id)
      if hb then
        hb.visible = true
        hb.ox = from
        boxes[#boxes + 1] = hb
      end
    end
    wait_busy()
    Anim.tweenStage(d.frames or 23, function(u)
      for _, hb in ipairs(boxes) do hb.ox = from * (1 - u) end
    end, function()
      for _, hb in ipairs(boxes) do hb.ox = 0 end
      advance()
    end)
    return
  end

  if kind == "healthbox" then
    local side = d.side or "enemy"
    local hb = s.healthbox[side]
    local from = d.from or ((side == "player") and 115 or -115)
    hb.visible = true
    hb.ox = from
    wait_busy()
    Anim.tweenStage(d.frames or 23, function(u)
      hb.ox = from * (1 - u)
    end, function()
      hb.ox = 0
      advance()
    end)
    return
  end

  if kind == "wait" then
    wait_busy()
    Anim.tweenStage(d.frames or 1, function() end, function()
      advance()
    end)
    return
  end

  advance()
end

-- pokefirered/src/pokeball.c:680
local function run_cry_queue()
  local q = IntroSeq._cryQueue
  if not q then return true end
  if q.waiting and Audio.isCryFinished and not Audio.isCryFinished() then return false end
  q.i = (q.i or 0) + 1
  local id = q.ids[q.i]
  if id == nil then
    IntroSeq._cryQueue = nil
    return true
  end
  local Battle = package.loaded["src.core.game3.battle"]
  local b = Battle and Battle._st and State.battler(Battle._st, id)
  local species = b and (b.species or (b.mon and (b.mon.species or b.mon.speciesId)))
  if species then
    local weak = release_cry_mode(b.mon) ~= 0
    local mode
    if #q.ids > 1 and q.i == 1 then mode = weak and 12 or 1 else mode = weak and 11 or 0 end
    pcall(function() Audio.playCry(species, mode, (State.sideOf(id) == "player") and -25 or 25) end)
  end
  q.waiting = true
  return false
end

function IntroSeq.update()
  if not IntroSeq._steps then return true end
  if IntroSeq._waitingGen then return false end
  if IntroSeq._cryQueue and not run_cry_queue() then return false end

  if IntroSeq._pendingSlideIn and Anim.introSlideDone() then
    local fn = IntroSeq._pendingSlideIn
    IntroSeq._pendingSlideIn = nil
    fn()
  end

  if IntroSeq._waitingCry then
    if (not Audio.isCryFinished) or Audio.isCryFinished() then
      IntroSeq._waitingCry = false
      IntroSeq._waiting = false
      advance()
    else
      return false
    end
  end

  if IntroSeq._waitingMonAnim then
    if MonAnimBattle.busy(IntroSeq._waitingMonAnim) then return false end
    IntroSeq._waitingMonAnim = nil
    advance()
  end

  -- Hold on intro dialog until the battle UI queue is drained (wants / sent out).
  if IntroSeq._waitingMsg then
    local Ui = require("src.core.game3.battle.ui")
    local pending = false
    if Ui.dialogPending then
      pending = Ui.dialogPending()
    elseif not Ui._headless then
      local Message = package.loaded["src.ui.game3.message"]
      pending = (Ui._showing == true)
        or (Ui._queue and #Ui._queue > 0)
        or (Message and Message.isOpen and Message.isOpen())
    end
    if pending then
      return false
    end
    IntroSeq._waitingMsg = false
    IntroSeq._waiting = false
    advance()
  end

  if IntroSeq._waiting then
    if Anim.busy() or IntroSeq._waitingFade or IntroSeq._pendingSlideIn then
      return false
    end
    IntroSeq._waiting = false
  end

  while IntroSeq._steps and IntroSeq._i <= #IntroSeq._steps do
    run_step(IntroSeq._steps[IntroSeq._i])
    if IntroSeq._waiting or IntroSeq._waitingFade or IntroSeq._waitingCry
        or IntroSeq._waitingMsg or IntroSeq._pendingSlideIn or IntroSeq._cryQueue
        or IntroSeq._waitingMonAnim then
      return false
    end
  end

  finish()
  return true
end

return IntroSeq
