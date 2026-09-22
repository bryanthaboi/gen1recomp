-- Mid-battle switch, withdraw, and send-out presentation sequencer.
-- Handles dynamic withdraw strings, sprite tweens, cry audio, shiny checks, and hazard/ability triggers.

local Anim = require("src.core.game3.battle.anim")
local State = require("src.core.game3.battle.state")
local Audio = require("src.core.game3.audio")
local SE = require("src.core.game3.se_ids")
local SummaryData = require("src.core.game3.summary_data")
local Strings = require("src.core.Strings")

local SwitchSeq = {}

SwitchSeq._steps = nil
SwitchSeq._i = 1
SwitchSeq._waiting = false
SwitchSeq._waitingMsg = false
SwitchSeq._waitingCry = false
SwitchSeq._pushMsg = nil
SwitchSeq._onDone = nil
SwitchSeq._headless = false
SwitchSeq._st = nil

function SwitchSeq.reset()
  SwitchSeq._steps = nil
  SwitchSeq._i = 1
  SwitchSeq._waiting = false
  SwitchSeq._waitingMsg = false
  SwitchSeq._waitingCry = false
  SwitchSeq._pushMsg = nil
  SwitchSeq._onDone = nil
  SwitchSeq._st = nil
  SwitchSeq._waitAnimSeq = false
end

function SwitchSeq.busy()
  return SwitchSeq._steps ~= nil
end

local function finish()
  local cb = SwitchSeq._onDone
  SwitchSeq._steps = nil
  SwitchSeq._i = 1
  SwitchSeq._waiting = false
  SwitchSeq._waitingMsg = false
  SwitchSeq._waitingCry = false
  SwitchSeq._onDone = nil
  if cb then cb() end
end

local function advance()
  SwitchSeq._waiting = false
  SwitchSeq._waitingMsg = false
  SwitchSeq._waitingCry = false
  SwitchSeq._i = SwitchSeq._i + 1
end

local function stage()
  return Anim.stage()
end

local function step_battler(st, d)
  if d.id ~= nil then return st and State.battler(st, d.id) end
  return st and st[d.side or "player"]
end

local function step_side(d)
  if d.id ~= nil then return State.sideOf(d.id) end
  return d.side or "player"
end

local function step_present(d)
  if d.id == nil then return Anim.present(d.side or "player") end
  return Anim.present(d.id) or (d.id < 2 and Anim.present(State.sideOf(d.id))) or nil
end

local function step_healthbox(s, d)
  local hb = s and s.healthbox
  if not hb then return nil end
  if d.id == nil then return hb[d.side or "player"] end
  return hb[d.id] or (d.id < 2 and hb[State.sideOf(d.id)]) or nil
end

local function step_center(st, d)
  if d.id ~= nil and Anim.coords then
    local a, b = Anim.coords(st, d.id)
    if type(a) == "table" then return a.x or a[1], a.y or a[2] end
    if a then return a, b end
  end
  local base = (step_side(d) == "player") and Anim.PLAYER_MON or Anim.ENEMY_MON
  return base.x, base.y
end

local function trainer_label(st)
  return (st and st.trainerClassName and st.trainerClassName ~= "")
    and (st.trainerClassName .. " " .. (st.trainerName or ""))
    or (st and st.trainerName or "TRAINER")
end

local function withdraw_text(battler)
  local name = battler and State.displayName(battler) or "POKéMON"
  local hp = tonumber(battler and battler.mon and battler.mon.hp) or 0
  local maxHp = tonumber(battler and battler.mon and (battler.mon.maxHp or battler.mon.maxhp)) or 1
  if maxHp < 1 then maxHp = 1 end
  local ratio = hp / maxHp
  if ratio > 0.5 then
    return Strings("%s, that's enough!\nCome back!", name)
  elseif ratio > 0.2 then
    return Strings("%s, good job!\nCome back!", name)
  else
    return Strings("%s, you did it!\nCome back!", name)
  end
end

local function apply_entry_triggers(st, side, pushMsg)
  if not st then return end
  local b = st[side]
  if not b or not b.mon or (tonumber(b.mon.hp) or 0) <= 0 then return end

  -- Hazards: Spikes
  local sideState = (side == "player") and st.playerSide or st.enemySide
  local hazards = sideState and sideState.hazards or {}
  local spikesLayers = tonumber(hazards.spikes or hazards.SPIKES) or 0
  if spikesLayers > 0 and b and b.mon then
    local isFlying = (b.type1 == 2 or b.type2 == 2 or b.type1 == "FLYING" or b.type2 == "FLYING")
    local hasLevitate = (b.ability == "LEVITATE" or b.ability == 26)
    if not isFlying and not hasLevitate then
      local maxHp = tonumber(b.mon.maxHp) or 1
      local fraction = (spikesLayers == 1) and 8 or (spikesLayers == 2 and 6 or 4)
      local dmg = math.max(1, math.floor(maxHp / fraction))
      State.applyHpLoss(b, dmg)
      local msg = Strings("%s is hurt\nby the SPIKES!", State.displayName(b))
      if pushMsg then pushMsg(msg) end
      local p = Anim.present(side)
      if p then
        Anim.tweenHp(side, p.displayHp or maxHp, b.mon.hp, maxHp)
      end
    end
  end

  -- Ability: Intimidate (ability 22 or "INTIMIDATE")
  if (b.ability == 22 or b.ability == "INTIMIDATE") and (tonumber(b.mon.hp) or 0) > 0 then
    local oppSide = (side == "player") and "enemy" or "player"
    local opp = st[oppSide]
    if opp and opp.mon and (tonumber(opp.mon.hp) or 0) > 0 then
      local oppName = State.displayName(opp)
      local myName = State.displayName(b)
      if opp.ability == "CLEAR_BODY" or opp.ability == 29 or opp.ability == "WHITE_SMOKE" or opp.ability == 73 or opp.substitute then
        -- Immune to Intimidate
      else
        local cur = opp.stages and opp.stages.attack or 0
        if cur > -6 then
          opp.stages.attack = math.max(-6, cur - 1)
          local msg = Strings("%s's INTIMIDATE\ncuts %s's ATTACK!", myName, oppName)
          if pushMsg then pushMsg(msg) end
        end
      end
    end
  end
end

local function battle_adapter()
  local Battle = package.loaded["src.core.game3.battle"]
  return Battle and Battle._adapter
end

local function capture_events(fn)
  local ad = battle_adapter()
  if not ad then return nil end
  local mark = ad:eventMark()
  local prev = ad._say
  ad._say = function() end
  local ok = pcall(fn, ad)
  ad._say = prev
  if not ok then return {} end
  return ad:eventsSince(mark)
end

-- pokefirered/src/battle_script_commands.c:9197
local function switch_out_effects(st, battler)
  local Engine = package.loaded["src.core.game3.battle.engine"]
  if not (Engine and Engine.switchOutEffects and battler) then return end
  capture_events(function(ad) Engine.switchOutEffects(st, ad, battler) end)
end

-- pokefirered/src/battle_script_commands.c:4960
local function engine_entry_events(st, sides)
  local Engine = package.loaded["src.core.game3.battle.engine"]
  if not (Engine and Engine.switchInEffects and battle_adapter()) then return nil end
  return capture_events(function(ad)
    for _, side in ipairs(sides) do
      local b = st and ((type(side) == "number") and State.battler(st, side) or st[side])
      if b and b.mon and (tonumber(b.mon.hp) or 0) > 0 then
        Engine.switchInEffects(st, ad, b, { spikes = true })
      end
    end
  end)
end

local function headless_entry(st, sides)
  local evs = engine_entry_events(st, sides)
  if evs == nil then
    for _, side in ipairs(sides) do apply_entry_triggers(st, side, SwitchSeq._pushMsg) end
    return
  end
  for _, e in ipairs(evs) do
    if e.kind == "msg" and SwitchSeq._pushMsg then SwitchSeq._pushMsg(e.text) end
  end
  Anim.syncDisplayFromState(st)
end

function SwitchSeq.beginPlayerSwitch(st, newSlot, opts)
  opts = opts or {}
  SwitchSeq.reset()
  SwitchSeq._st = st
  SwitchSeq._headless = opts.headless and true or false
  SwitchSeq._pushMsg = opts.pushMsg
  SwitchSeq._onDone = opts.onDone

  local oldBattler = st.player
  local withdrawMsg = withdraw_text(oldBattler)

  if SwitchSeq._headless then
    if SwitchSeq._pushMsg then SwitchSeq._pushMsg(withdrawMsg) end
    switch_out_effects(st, oldBattler)
    State.trackParticipant(st, st.enemy, oldBattler and oldBattler.partyIndex or 1)
    State.syncBattlerToParty(st.player, st.playerParty)
    State.wipeVolatilesAndStages(st.player, { batonPass = opts.batonPass })
    st.player = State.makeBattler(st.playerParty[newSlot], "player", { state = st, partyIndex = newSlot })
    State.trackParticipant(st, st.enemy, newSlot)
    Anim.syncDisplayFromState(st)
    local newName = State.displayName(st.player)
    if SwitchSeq._pushMsg then SwitchSeq._pushMsg(Strings("Go! %s!", newName)) end
    headless_entry(st, { "player" })
    finish()
    return false
  end

  local steps = {
    { kind = "msg", data = { text = withdrawMsg } },
    { kind = "withdraw", data = { side = "player" } },
    { kind = "swap_data", data = { side = "player", newSlot = newSlot, batonPass = opts.batonPass } },
    { kind = "msg_sendout", data = { side = "player" } },
    { kind = "sendout_player", data = { slot = newSlot } },
    { kind = "shiny_check", data = { side = "player" } },
    { kind = "cry", data = { side = "player" } },
    { kind = "healthbox", data = { side = "player" } },
    { kind = "entry_triggers", data = { side = "player" } },
  }

  SwitchSeq._steps = steps
  SwitchSeq._i = 1
  return true
end

function SwitchSeq.beginSendOut(st, side, newSlot, opts)
  opts = opts or {}
  side = side or "player"
  SwitchSeq.reset()
  SwitchSeq._st = st
  SwitchSeq._headless = opts.headless and true or false
  SwitchSeq._pushMsg = opts.pushMsg
  SwitchSeq._onDone = opts.onDone

  if SwitchSeq._headless then
    if side == "player" then
      st.player = State.makeBattler(st.playerParty[newSlot], "player", { state = st, partyIndex = newSlot })
      State.trackParticipant(st, st.enemy, newSlot)
      Anim.syncDisplayFromState(st)
      if SwitchSeq._pushMsg then
        SwitchSeq._pushMsg(Strings("Go! %s!", State.displayName(st.player)))
      end
    else
      st.enemy = State.makeBattler(st.foeParty[newSlot], "enemy", { state = st, partyIndex = newSlot })
      Anim.syncDisplayFromState(st)
      if SwitchSeq._pushMsg then
        local tname = (st.trainerClassName and st.trainerClassName ~= "")
          and (st.trainerClassName .. " " .. (st.trainerName or ""))
          or (st.trainerName or "TRAINER")
        SwitchSeq._pushMsg(Strings("%s sent\nout %s!", tname, State.displayName(st.enemy)))
      end
    end
    headless_entry(st, { side })
    finish()
    return false
  end

  local steps = {}
  if side == "player" then
    steps = {
      { kind = "swap_data", data = { side = "player", newSlot = newSlot } },
      { kind = "msg_sendout", data = { side = "player" } },
      { kind = "sendout_player", data = { slot = newSlot } },
      { kind = "shiny_check", data = { side = "player" } },
      { kind = "cry", data = { side = "player" } },
      { kind = "healthbox", data = { side = "player" } },
      { kind = "entry_triggers", data = { side = "player" } },
    }
  else
    steps = {
      { kind = "swap_data", data = { side = "enemy", newSlot = newSlot } },
      { kind = "msg_sendout", data = { side = "enemy" } },
      { kind = "sendout_enemy", data = { slot = newSlot } },
      { kind = "shiny_check", data = { side = "enemy" } },
      { kind = "cry", data = { side = "enemy" } },
      { kind = "healthbox", data = { side = "enemy" } },
      { kind = "entry_triggers", data = { side = "enemy" } },
    }
  end

  SwitchSeq._steps = steps
  SwitchSeq._i = 1
  return true
end

-- pokefirered/src/battle_message.c:1633
function SwitchSeq.returnText(st, id)
  local old = State.battler(st, id)
  if State.sideOf(id) == "player" then
    return Strings("%s, come back!", State.displayName(old))
  end
  return Strings("%s\nwithdrew %s!", trainer_label(st), State.displayName(old))
end

-- pokefirered/data/battle_scripts_1.s:3046
function SwitchSeq.beginDoubleSwitch(st, id, newSlot, opts)
  opts = opts or {}
  SwitchSeq.reset()
  SwitchSeq._st = st
  SwitchSeq._headless = opts.headless and true or false
  SwitchSeq._pushMsg = opts.pushMsg
  SwitchSeq._onDone = opts.onDone
  local side = State.sideOf(id)
  local withdrawMsg
  if opts.withdraw and not opts.noWithdrawMsg then
    withdrawMsg = SwitchSeq.returnText(st, id)
  end
  local reason = opts.reason or (opts.withdraw and "switch" or "replace")

  if SwitchSeq._headless then
    if withdrawMsg and SwitchSeq._pushMsg then SwitchSeq._pushMsg(withdrawMsg) end
    local Engine = package.loaded["src.core.game3.battle.engine"]
    local party = (side == "player") and st.playerParty or st.foeParty
    if Engine and Engine.performSwitch and battle_adapter() and party and party[newSlot] then
      capture_events(function(ad)
        Engine.performSwitch(st, ad, id, newSlot, { batonPass = opts.batonPass, reason = reason })
      end)
    end
    Anim.syncDisplayFromState(st)
    local nb = State.battler(st, id)
    if SwitchSeq._pushMsg then
      if side == "player" then
        SwitchSeq._pushMsg(Strings("Go! %s!", State.displayName(nb)))
      else
        SwitchSeq._pushMsg(Strings("%s sent\nout %s!", trainer_label(st), State.displayName(nb)))
      end
    end
    headless_entry(st, { id })
    finish()
    return false
  end

  local steps = {}
  if withdrawMsg then
    steps[#steps + 1] = { kind = "msg", data = { text = withdrawMsg } }
  end
  if opts.withdraw then
    steps[#steps + 1] = { kind = "withdraw", data = { id = id } }
  end
  steps[#steps + 1] = { kind = "swap_data", data = { id = id, newSlot = newSlot, batonPass = opts.batonPass, reason = reason } }
  steps[#steps + 1] = { kind = "msg_sendout", data = { id = id } }
  steps[#steps + 1] = { kind = (side == "player") and "sendout_player" or "sendout_enemy", data = { id = id, slot = newSlot } }
  steps[#steps + 1] = { kind = "shiny_check", data = { id = id } }
  steps[#steps + 1] = { kind = "cry", data = { id = id } }
  steps[#steps + 1] = { kind = "healthbox", data = { id = id } }
  steps[#steps + 1] = { kind = "entry_triggers", data = { id = id } }
  SwitchSeq._steps = steps
  SwitchSeq._i = 1
  return true
end

-- pokefirered/src/battle_controller_player.c:2105
function SwitchSeq.beginEventSwitchIn(st, side, opts)
  opts = opts or {}
  SwitchSeq.reset()
  SwitchSeq._st = st
  SwitchSeq._headless = opts.headless and true or false
  SwitchSeq._pushMsg = opts.pushMsg
  SwitchSeq._onDone = opts.onDone
  if SwitchSeq._headless then
    finish()
    return false
  end
  local id = tonumber(opts.battler) or ((type(side) == "number") and side or nil)
  if id ~= nil and not (st and st.double) and id < 2 then id = nil end
  if type(side) == "number" then side = State.sideOf(side) end
  local d = (id ~= nil) and { id = id } or { side = side }
  SwitchSeq._steps = {
    { kind = (side == "player") and "sendout_player" or "sendout_enemy", data = d },
    { kind = "shiny_check", data = d },
    { kind = "cry", data = d },
    { kind = "healthbox", data = d },
  }
  SwitchSeq._i = 1
  return true
end

--- Retail Shift sequence: Player recalls active mon -> Enemy sends out replacement FIRST -> Player sends out replacement SECOND.
function SwitchSeq.beginShiftSwitch(st, playerSlot, enemySlot, opts)
  opts = opts or {}
  SwitchSeq.reset()
  SwitchSeq._st = st
  SwitchSeq._headless = opts.headless and true or false
  SwitchSeq._pushMsg = opts.pushMsg
  SwitchSeq._onDone = opts.onDone

  local oldBattler = st.player
  local withdrawMsg = withdraw_text(oldBattler)

  if SwitchSeq._headless then
    if SwitchSeq._pushMsg then SwitchSeq._pushMsg(withdrawMsg) end
    switch_out_effects(st, oldBattler)
    State.trackParticipant(st, st.enemy, oldBattler and oldBattler.partyIndex or 1)
    State.syncBattlerToParty(st.player, st.playerParty)
    State.wipeVolatilesAndStages(st.player)
    st.enemy = State.makeBattler(st.foeParty[enemySlot], "enemy", { state = st, partyIndex = enemySlot })
    local tname = (st.trainerClassName and st.trainerClassName ~= "")
      and (st.trainerClassName .. " " .. (st.trainerName or ""))
      or (st.trainerName or "TRAINER")
    if SwitchSeq._pushMsg then SwitchSeq._pushMsg(Strings("%s sent\nout %s!", tname, State.displayName(st.enemy))) end
    st.player = State.makeBattler(st.playerParty[playerSlot], "player", { state = st, partyIndex = playerSlot })
    State.trackParticipant(st, st.enemy, playerSlot)
    Anim.syncDisplayFromState(st)
    if SwitchSeq._pushMsg then SwitchSeq._pushMsg(Strings("Go! %s!", State.displayName(st.player))) end
    headless_entry(st, { "enemy", "player" })
    finish()
    return false
  end

  local steps = {
    -- 1. Player recall
    { kind = "msg", data = { text = withdrawMsg } },
    { kind = "withdraw", data = { side = "player" } },
    -- 2. Enemy sendout first (retail FRLG order)
    { kind = "swap_data", data = { side = "enemy", newSlot = enemySlot } },
    { kind = "msg_sendout", data = { side = "enemy" } },
    { kind = "sendout_enemy", data = { slot = enemySlot } },
    { kind = "shiny_check", data = { side = "enemy" } },
    { kind = "cry", data = { side = "enemy" } },
    { kind = "healthbox", data = { side = "enemy" } },
    -- 3. Player sendout second
    { kind = "swap_data", data = { side = "player", newSlot = playerSlot } },
    { kind = "msg_sendout", data = { side = "player" } },
    { kind = "sendout_player", data = { slot = playerSlot } },
    { kind = "shiny_check", data = { side = "player" } },
    { kind = "cry", data = { side = "player" } },
    { kind = "healthbox", data = { side = "player" } },
    -- 4. Entry abilities and hazards in speed order
    { kind = "entry_triggers", data = { sides = { "enemy", "player" } } },
  }

  SwitchSeq._steps = steps
  SwitchSeq._i = 1
  return true
end

--- Retail defeat slide-in: Front sprite of defeated enemy trainer slides in from right before defeat speech.
function SwitchSeq.beginTrainerSlideIn(st, opts)
  opts = opts or {}
  SwitchSeq.reset()
  SwitchSeq._st = st
  SwitchSeq._headless = opts.headless and true or false
  SwitchSeq._pushMsg = opts.pushMsg
  SwitchSeq._onDone = opts.onDone

  if SwitchSeq._headless then
    finish()
    return false
  end

  local steps = {
    { kind = "trainer_slide_in", data = { side = "enemy" } },
  }
  SwitchSeq._steps = steps
  SwitchSeq._i = 1
  return true
end

local function wait_busy()
  SwitchSeq._waiting = true
end

local function run_step(step)
  if not step then return end
  local kind = step.kind
  local d = step.data or {}
  local s = stage()
  local st = SwitchSeq._st

  if kind == "msg" then
    if SwitchSeq._pushMsg and d.text then
      SwitchSeq._pushMsg(d.text)
    end
    SwitchSeq._waiting = true
    SwitchSeq._waitingMsg = true
    return
  end

  if kind == "msg_sendout" then
    local side = step_side(d)
    local text = ""
    if side == "player" then
      text = Strings("Go! %s!", State.displayName(step_battler(st, d)))
    else
      text = Strings("%s sent\nout %s!", trainer_label(st), State.displayName(step_battler(st, d)))
    end
    if side == "player" and not SwitchSeq._headless then
      -- pokefirered/src/battle_message.c:399
      require("src.core.game3.battle.ui").pushTimed(text, 0)
    elseif SwitchSeq._pushMsg then
      SwitchSeq._pushMsg(text)
    end
    SwitchSeq._waiting = true
    SwitchSeq._waitingMsg = true
    return
  end

  if kind == "withdraw" then
    local p = step_present(d)
    local hb = step_healthbox(s, d)
    if hb then hb.visible = false end
    pcall(function() Audio.playSe(SE.SE_BALL_OPEN) end)
    wait_busy()
    Anim.tweenStage(12, function(u)
      if p then
        p.scale = math.max(0.01, 1 - u)
      end
    end, function()
      if p then
        p.visible = false
        p.scale = 1
      end
      advance()
    end)
    return
  end

  if kind == "swap_data" then
    local side = step_side(d)
    local newSlot = d.newSlot or 1
    local Engine = package.loaded["src.core.game3.battle.engine"]
    local party = st and ((side == "player") and st.playerParty or st.foeParty)
    local pres = step_present(d)
    -- pokefirered/src/battle_gfx_sfx_util.c:997
    if pres then pres.castformForm, pres.castformMon = nil, nil end
    if Engine and Engine.performSwitch and battle_adapter() and step_battler(st, d) and party and party[newSlot] then
      capture_events(function(ad)
        Engine.performSwitch(st, ad, d.id ~= nil and d.id or side, newSlot,
          { batonPass = d.batonPass, reason = d.reason or "switch" })
      end)
      Anim.syncDisplayFromState(st)
      advance()
      return
    end
    switch_out_effects(st, st and st[side])
    if side == "player" then
      if st and st.player then
        State.trackParticipant(st, st.enemy, st.player.partyIndex or 1)
        State.syncBattlerToParty(st.player, st.playerParty)
        State.wipeVolatilesAndStages(st.player, { batonPass = d.batonPass })
      end
      st.player = State.makeBattler(st.playerParty[newSlot], "player", { state = st, partyIndex = newSlot })
      State.trackParticipant(st, st.enemy, newSlot)
    else
      if st and st.enemy then
        State.syncBattlerToParty(st.enemy, st.foeParty)
        State.wipeVolatilesAndStages(st.enemy)
      end
      st.enemy = State.makeBattler(st.foeParty[newSlot], "enemy", { state = st, partyIndex = newSlot })
    end
    Anim.syncDisplayFromState(st)
    advance()
    return
  end

  if kind == "sendout_player" then
    local pcx, pcy = step_center(st, d.id ~= nil and d or { side = "player" })
    s.ball.visible = true
    s.ball.frame = 0
    s.ball.rot = 0
    s.ball.side = "player"
    s.ball.x = 48
    s.ball.y = 70
    pcall(function() Audio.playSe(SE.SE_BALL_THROW, { pan = -64 }) end)
    wait_busy()
    Anim.tweenStage(25, function(u, t)
      local f = t.frames or (u * 25)
      local sx, sy = 48, 70
      local tx, ty = pcx, pcy + 24
      s.ball.x = sx + (tx - sx) * u
      s.ball.y = sy + (ty - sy) * u + (-30 * 4 * u * (1 - u))
      s.ball.rot = f * ((25 / 256) * math.pi * 2)
    end, function()
      s.ball.frame = 1
      s.ball.rot = 0
      pcall(function() Audio.playSe(SE.SE_BALL_OPEN, { pan = -64 }) end)
      Anim.ballOpen(d.id ~= nil and d.id or "player", s.ball.x, s.ball.y)
      local p = step_present(d.id ~= nil and d or { side = "player" }) or {}
      p.visible = true
      p.ox = 0
      p.oy = 16
      p.scale = 0.16
      p.darken = 0
      Anim.tweenStage(12, function(u)
        p.oy = 16 * (1 - u)
        p.scale = 0.16 + 0.84 * u
        s.ball.frame = (u < 0.5) and 1 or 2
      end, function()
        p.oy = 0
        p.scale = 1
        s.ball.visible = false
        s.ball.rot = 0
        advance()
      end)
    end)
    return
  end

  if kind == "sendout_enemy" then
    local cx, cy = step_center(st, d.id ~= nil and d or { side = "enemy" })
    s.ball.visible = true
    s.ball.frame = 0
    s.ball.side = "enemy"
    s.ball.x = cx
    s.ball.y = cy + 24
    wait_busy()
    Anim.tweenStage(16, function() end, function()
      s.ball.frame = 1
      pcall(function() Audio.playSe(SE.SE_BALL_OPEN, { pan = 63 }) end)
      Anim.ballOpen(d.id ~= nil and d.id or "enemy", s.ball.x, s.ball.y)
      local p = step_present(d.id ~= nil and d or { side = "enemy" }) or {}
      p.visible = true
      p.ox = 0
      p.oy = 16
      p.scale = 0.16
      p.darken = 0
      Anim.tweenStage(12, function(u)
        p.oy = 16 * (1 - u)
        p.scale = 0.16 + 0.84 * u
        s.ball.frame = (u < 0.5) and 1 or 2
      end, function()
        p.oy = 0
        p.scale = 1
        s.ball.visible = false
        advance()
      end)
    end)
    return
  end

  if kind == "shiny_check" then
    local b = step_battler(st, d)
    local mon = b and b.mon
    local isShiny = mon and SummaryData.isShiny(mon)
    if isShiny then
      pcall(function() Audio.playSe(SE.SE_SHINY) end)
      wait_busy()
      Anim.tweenStage(24, function() end, function()
        advance()
      end)
      return
    end
    advance()
    return
  end

  if kind == "cry" then
    local side = step_side(d)
    local b = step_battler(st, d)
    local sp = b and (b.species or (b.mon and (b.mon.species or b.mon.speciesId)))
    if sp then
      -- pokefirered/src/pokeball.c:782
      local IntroSeq = require("src.core.game3.battle.intro_seq")
      Audio.playCry(sp, IntroSeq.releaseCryMode(b.mon), (side == "player") and -25 or 25)
    end
    SwitchSeq._waiting = true
    SwitchSeq._waitingCry = true
    return
  end

  if kind == "healthbox" then
    local side = step_side(d)
    local hb = step_healthbox(s, d) or {}
    local from = (side == "player") and 115 or -115
    hb.visible = true
    hb.ox = from
    wait_busy()
    Anim.tweenStage(20, function(u)
      hb.ox = from * (1 - u)
    end, function()
      hb.ox = 0
      advance()
    end)
    return
  end

  if kind == "entry_triggers" then
    local sides = d.sides or { d.side or "player" }
    if d.id ~= nil then sides = { d.id } end
    if #sides > 1 then
      table.sort(sides, function(a, bSide)
        local spA = st and st[a] and (st[a].speed or (st[a].mon and st[a].mon.speed)) or 0
        local spB = st and st[bSide] and (st[bSide].speed or (st[bSide].mon and st[bSide].mon.speed)) or 0
        return spA > spB
      end)
    end
    local evs = engine_entry_events(st, sides)
    if evs == nil then
      for _, sSide in ipairs(sides) do
        apply_entry_triggers(st, sSide, SwitchSeq._pushMsg)
      end
    elseif #evs > 0 then
      local AnimSeq = require("src.core.game3.battle.anim_seq")
      local Ui = require("src.core.game3.battle.ui")
      if not AnimSeq.busy() then
        AnimSeq.beginEvents(evs, function(text, wait) Ui.pushTimed(text, tonumber(wait) or 64) end)
        SwitchSeq._waitAnimSeq = true
        advance()
        return
      end
      for _, e in ipairs(evs) do
        if e.kind == "msg" and SwitchSeq._pushMsg then SwitchSeq._pushMsg(e.text) end
      end
      Anim.syncDisplayFromState(st)
    end
    advance()
    return
  end

  if kind == "trainer_slide_in" then
    local p = Anim.present("enemy")
    if p then p.visible = false end
    local hb = s.healthbox and s.healthbox.enemy
    if hb then hb.visible = false end
    if st and st.double then
      for _, id in ipairs({ 1, 3 }) do
        local pp = step_present({ id = id })
        if pp then pp.visible = false end
        local hh = step_healthbox(s, { id = id })
        if hh then hh.visible = false end
      end
    end
    local Trainers = require("src.core.game3.scripting.trainers")
    local info = st and st.trainerId and Trainers.info(st.trainerId)
    local picId = (st and st.trainerPicId) or (info and info.pic) or 0
    s.trainer.enemy.visible = true
    s.trainer.enemy.picId = picId
    s.trainer.enemy.ox = 240
    wait_busy()
    Anim.tweenStage(35, function(u)
      s.trainer.enemy.ox = 240 * (1 - u)
    end, function()
      s.trainer.enemy.ox = 0
      advance()
    end)
    return
  end

  advance()
end

function SwitchSeq.update()
  if not SwitchSeq._steps then return true end

  if SwitchSeq._waitAnimSeq then
    local AnimSeq = require("src.core.game3.battle.anim_seq")
    if not AnimSeq.update() then return false end
    SwitchSeq._waitAnimSeq = false
  end

  if SwitchSeq._waitingCry then
    if Audio.isCryPlaying and Audio.isCryPlaying() then
      return false
    end
    SwitchSeq._waitingCry = false
    SwitchSeq._waiting = false
    advance()
  end

  if SwitchSeq._waitingMsg then
    local Ui = package.loaded["src.core.game3.battle.ui"]
    local pending = Ui and ((Ui.dialogPending and Ui.dialogPending()) or (Ui.busy and Ui.busy()))
    if pending then
      return false
    end
    SwitchSeq._waitingMsg = false
    SwitchSeq._waiting = false
    advance()
  end

  if SwitchSeq._waiting then
    if Anim.busy() then
      return false
    end
    SwitchSeq._waiting = false
  end

  while SwitchSeq._steps and SwitchSeq._i <= #SwitchSeq._steps do
    run_step(SwitchSeq._steps[SwitchSeq._i])
    if SwitchSeq._waiting or SwitchSeq._waitingCry or SwitchSeq._waitingMsg or SwitchSeq._waitAnimSeq then
      return false
    end
  end

  finish()
  return true
end

return SwitchSeq
