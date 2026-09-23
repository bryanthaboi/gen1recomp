-- Battle intro presentation (pret BeginBattleIntro + DoPokeballSendOutAnimation).
-- Separate from AnimSeq (hit loop); same contract as ExpSeq.

local Anim = require("src.core.game3.battle.anim")
local State = require("src.core.game3.battle.state")
local Audio = require("src.core.game3.audio")
local SE = require("src.core.game3.se_ids")
local RomText = require("src.core.game3.rom_text")
local BattleText = require("src.core.game3.battle.battle_text")
local Adapter = require("src.core.game3.battle.adapter")

local IntroSeq = {}

IntroSeq._steps = nil
IntroSeq._i = 1
IntroSeq._waiting = false
IntroSeq._pushMsg = nil
IntroSeq._headless = false
IntroSeq._opts = nil

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
  IntroSeq._cryQueue = nil
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

local function ball_for(s, key)
  if type(key) ~= "number" then return s.ball end
  s.balls = s.balls or {}
  local b = s.balls[key]
  if not b then
    b = { visible = false, x = 0, y = 0, frame = 0, rot = 0, battler = key, side = State.sideOf(key) }
    s.balls[key] = b
  end
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
  local playerGender = (st.oldManTutorial and 5) or opts.playerGender or 0
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
    add("cry", { side = "enemy", release = true, ids = foeIds })
    add("healthbox", { side = "enemy", frames = 23, from = -115, ids = foeIds })
    add("msg", { text = goText, linger = true })
    add("player_throw", { ids = plIds })
    add("healthbox", { side = "player", frames = 23, from = 115, ids = plIds })
    add("wait", { frames = 3 })
    return steps
  end
  add("msg", { text = strings.wants })
  add("msg", { text = strings.sentOut })
  add("opponent_sendout", { toX = 280, frames = 35 })
  add("cry", { side = "enemy", release = true })
  add("healthbox", { side = "enemy", frames = 23, from = -115 })
  add("msg", { text = IntroSeq.sendOutText(st, "player"), linger = true })
  add("player_throw", {})
  add("healthbox", { side = "player", frames = 23, from = 115 })
  add("wait", { frames = 3 })
  return steps
end

--- Begin intro. Returns false when headless (caller pushes strings).
function IntroSeq.begin(st, opts)
  opts = opts or {}
  IntroSeq.reset()
  IntroSeq._opts = opts
  IntroSeq._pushMsg = opts.pushMsg
  IntroSeq._headless = opts.headless and true or false
  if IntroSeq._headless or not st then
    return false
  end

  local s = stage()
  s.slide = 0
  s.slideDone = false
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

  local playerGender = (st.oldManTutorial and 5) or opts.playerGender or 0
  s.bgSlide = { enemyOx = -240, playerOx = 240 }
  s.trainer.player.visible = true
  s.trainer.player.gender = playerGender
  s.trainer.player.ox = 240
  s.trainer.player.frame = 0

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
    IntroSeq._steps = build_trainer(st, opts)
  end
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
      s.trainer.player.frame = 0
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
    Anim.tweenStage(frames, function(u)
      s.slide = u
      if u * frames >= unlockAt then
        s.slideDone = true
        start_sprite_slide()
      end
    end, function()
      s.slide = 1
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
      s.trainer.player.frame = 0
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
    s.partyBar.enemy.visible = true
    s.partyBar.enemy.ox = -100
    s.partyBar.enemy.balls = d.enemyBalls or { "ok" }
    s.partyBar.player.visible = true
    s.partyBar.player.ox = 100
    s.partyBar.player.balls = d.playerBalls or { "ok" }
    wait_busy()
    Anim.tweenStage(d.frames or 20, function(u)
      s.partyBar.enemy.ox = -100 + 100 * u
      s.partyBar.player.ox = 100 - 100 * u
    end, function()
      s.partyBar.enemy.ox = 0
      s.partyBar.player.ox = 0
      advance()
    end)
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
    s.partyBar[side].visible = false
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
      local ball = ball_for(s, key)
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
    s.partyBar.enemy.visible = false
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
            pcall(function() Audio.playSe(SE.SE_BALL_OPEN, { pan = 63 }) end)
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
      tr.frame = 0
      tr.gender = (IntroSeq._opts and IntroSeq._opts.playerGender) or 0
    end
    s.partyBar.player.visible = false
    -- pret sAnimCmd_Red_1: 1(20) 2(6) 3(6) 4(24) 0(1) = 57f; exit linear ox 0→-120 over 50f.
    local pose = { { 1, 20 }, { 2, 6 }, { 3, 6 }, { 4, 24 }, { 0, 1 } }
    local poseFrame, poseLeft, poseI = 0, 0, 0
    local exitTo = -120
    local mons = {}
    for n, key in ipairs(keys) do
      local pcx, pcy = center_of(st, key)
      mons[n] = { key = key, ball = ball_for(s, key), tx = pcx, ty = pcy + 24 }
    end
    local threwSe, openedSe = false, false
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
          ball.x = 48
          ball.y = 70
          ball._sx, ball._sy = 48, 70
          ball._tx, ball._ty = m.tx, m.ty
          if not threwSe then
            threwSe = true
            pcall(function() Audio.playSe(SE.SE_BALL_THROW, { pan = -64 }) end)
          end
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
        pcall(function() Audio.playSe(SE.SE_BALL_OPEN, { pan = -64 }) end)
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
        or IntroSeq._waitingMsg or IntroSeq._pendingSlideIn or IntroSeq._cryQueue then
      return false
    end
  end

  finish()
  return true
end

return IntroSeq
