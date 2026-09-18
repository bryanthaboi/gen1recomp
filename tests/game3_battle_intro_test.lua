#!/usr/bin/env luajit
-- Battle intro sequencer + trainer string / offset smoke tests.

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

print("[test] 1. Versions trainer offsets")
local Versions = require("src.import.gba.versions")
check(Versions.TRAINER_FRONT_PIC_TABLE == 0x23957C, "FRONT_PIC_TABLE")
check(Versions.TRAINER_FRONT_PIC_PAL_TABLE == 0x239A1C, "FRONT_PIC_PAL_TABLE")
check(Versions.TRAINER_BACK_PIC_TABLE == 0x239FA4, "BACK_PIC_TABLE")
check(Versions.TRAINERS_TABLE == 0x23EAC8, "TRAINERS_TABLE")
check(Versions.TRAINER_CLASS_NAMES == 0x23E558, "CLASS_NAMES")
check(Versions.BATTLE_UI and Versions.BATTLE_UI.party_summary_bar == 0xE7BB04, "party_summary_bar")

print("[test] 2. Trainer intro strings")
local Trainers = require("src.core.game3.scripting.trainers")
local s = Trainers.introStrings(326, "SQUIRTLE")
check(s.wants == "RIVAL TERRY\nwould like to battle!", "wants string")
check(s.sentOut == "RIVAL TERRY sent\nout SQUIRTLE!", "sentOut string")
local s2 = Trainers.introStrings(326, "SQUIRTLE", { rivalName = "BLUE" })
check(s2.wants:find("BLUE", 1, true) ~= nil, "rivalName override")

print("[test] 3. IntroSeq step shapes")
-- Stub love-less anim/task path via headless begin false; build via private tables
-- by starting a minimal state through Battle.start headless.
local State = require("src.core.game3.battle.state")
local IntroSeq = require("src.core.game3.battle.intro_seq")
local Anim = require("src.core.game3.battle.anim")
Anim.reset({ headless = false })

local stWild = State.new({
  wild = true,
  playerParty = { { species = 1, level = 5, hp = 20, maxHp = 20, moves = { 33 }, pp = { 35 } } },
  foeMon = { species = 16, level = 3, hp = 15, maxHp = 15, moves = { 33 }, pp = { 35 } },
})
local msgs = {}
local okWild = IntroSeq.begin(stWild, {
  pushMsg = function(t) msgs[#msgs + 1] = t end,
  headless = false,
})
check(okWild == true, "wild begin")
local kinds = {}
for _, step in ipairs(IntroSeq._steps or {}) do
  kinds[#kinds + 1] = step.kind
end
local function has(kind)
  for _, k in ipairs(kinds) do if k == kind then return true end end
  return false
end
check(has("bgslide") and has("player_throw"), "wild has bgslide+throw")
check(not has("partybar") and not has("trainerexit"), "wild has no partybar/exit")
local bg = IntroSeq._steps and IntroSeq._steps[2]
check(bg and bg.kind == "bgslide" and bg.data.slidePlayer and bg.data.slideEnemyMon,
  "wild bgslide slides player + enemy mon")
check(msgs[1] == nil, "msgs deferred to update steps")

IntroSeq.reset()
msgs = {}
local stTr = State.new({
  wild = false,
  playerParty = { { species = 1, level = 5, hp = 20, maxHp = 20, moves = { 33 }, pp = { 35 } } },
  foeMon = { species = 7, level = 5, hp = 20, maxHp = 20, moves = { 33 }, pp = { 35 } },
})
stTr.trainerId = 326
local okTr = IntroSeq.begin(stTr, {
  pushMsg = function(t) msgs[#msgs + 1] = t end,
  headless = false,
  trainerId = 326,
  trainerPicId = 106,
  playerGender = 0,
})
check(okTr == true, "trainer begin")
kinds = {}
local partyStep
for _, step in ipairs(IntroSeq._steps or {}) do
  kinds[#kinds + 1] = step.kind
  if step.kind == "partybar" then partyStep = step end
end
check(has("partybar") and has("opponent_sendout"), "trainer party+sendout")
check(partyStep and #partyStep.data.playerBalls == 6, "player has 6 ball slots")
check(partyStep and partyStep.data.playerBalls[1] == "ok" and partyStep.data.playerBalls[2] == "empty", "player 1 mon has 1 ok on left and 5 empty")
check(partyStep and #partyStep.data.enemyBalls == 6, "opponent has 6 ball slots")
check(partyStep and partyStep.data.enemyBalls[1] == "empty" and partyStep.data.enemyBalls[6] == "ok", "opponent 1 mon has 5 empty on left and 1 ok on right")

-- Test opponent with 3 mons
local stTr3 = State.new({
  wild = false,
  playerParty = { { species = 1, hp = 20, maxHp = 20 } },
  foeParty = { { species = 10, hp = 10 }, { species = 11, hp = 10 }, { species = 12, hp = 10 } },
})
IntroSeq.reset()
IntroSeq.begin(stTr3, { headless = false })
local partyStep3
for _, step in ipairs(IntroSeq._steps or {}) do
  if step.kind == "partybar" then partyStep3 = step break end
end
check(partyStep3 and partyStep3.data.enemyBalls[1] == "empty" and partyStep3.data.enemyBalls[3] == "empty"
  and partyStep3.data.enemyBalls[4] == "ok" and partyStep3.data.enemyBalls[5] == "ok" and partyStep3.data.enemyBalls[6] == "ok",
  "opponent 3 mons has 3 empty on left and 3 ok on right")

-- pret: wants → sentOut → (then) IntroTrainerBallThrow (opponent_sendout)
local wi, si, xi
for i, k in ipairs(kinds) do
  if k == "msg" and not wi then wi = i
  elseif k == "msg" and wi and not si then si = i
  elseif k == "opponent_sendout" then xi = i end
end
check(wi and si and xi and wi < si and si < xi, "msgs before opponent_sendout (wants/sentOut then sendout)")
local bgTr
for _, step in ipairs(IntroSeq._steps or {}) do
  if step.kind == "bgslide" then bgTr = step break end
end
check(bgTr and bgTr.data.slidePlayer and bgTr.data.slideEnemy,
  "trainer bgslide slides both trainers")

print("[test] 3b. Trainer stays until dialog drained")
local Ui = require("src.core.game3.battle.ui")
local Task = require("src.core.game3.task")
local Fade = require("src.ui.game3.fade")
local _fadeBegin = Fade.begin
Fade.begin = function(_, _, cb) if cb then cb() end end
Ui.reset({ headless = false })
Anim.reset({ headless = false })
IntroSeq.reset()
local held = {}
local stHold = State.new({
  wild = false,
  playerParty = { { species = 1, level = 5, hp = 20, maxHp = 20, moves = { 33 }, pp = { 35 } } },
  foeMon = { species = 7, level = 5, hp = 20, maxHp = 20, moves = { 33 }, pp = { 35 } },
})
IntroSeq.begin(stHold, {
  pushMsg = function(t)
    held[#held + 1] = t
    Ui.push(t)
  end,
  headless = false,
  trainerId = 326,
  trainerPicId = 106,
  playerGender = 0,
})
local sawMsgWait = false
local exitedEarly = false
local playerMissing = false
for _ = 1, 400 do
  Task.update(1 / 60)
  Fade.tick(1 / 60)
  Anim.update(1 / 60)
  if IntroSeq._waitingMsg then
    sawMsgWait = true
    local te = Anim.stage().trainer.enemy
    local tp = Anim.stage().trainer.player
    if not te.visible then exitedEarly = true end
    if not (tp.visible and math.abs(tp.ox or 999) < 1) then playerMissing = true end
    break
  end
  if IntroSeq.update() then break end
end
Fade.begin = _fadeBegin
check(sawMsgWait == true, "intro waits on msg before trainerexit")
check(exitedEarly == false, "trainer still visible when dialog wait starts")
check(playerMissing == false, "player back sprite on-screen before wants dialog")
check(held[1] ~= nil and held[1]:find("battle", 1, true) ~= nil, "wants dialog queued first")
-- Drain first line; ensure trainerexit still not done until second line drained
Ui._queue = {}
Ui._showing = false
local Message = package.loaded["src.ui.game3.message"]
if Message and Message.close then Message.close() end
IntroSeq.update() -- should advance past first msg, push sentOut, wait again
check(IntroSeq._waitingMsg == true, "waits on sentOut msg")
check(Anim.stage().trainer.enemy.visible == true, "trainer still visible during sentOut")

print("[test] 4. Headless Battle.start strings")
local Battle = require("src.core.game3.battle")
-- Ensure not already active
if Battle.isActive and Battle.isActive() then
  Battle.abort("win")
end
local okB, err = Battle.start({
  wild = false,
  headless = true,
  trainerId = 326,
  playerParty = {
    { species = 4, level = 5, hp = 20, maxHp = 20, moves = { 10, 45 }, pp = { 35, 40 }, maxPp = { 35, 40 } },
  },
  foe = { species = 7, level = 5, trainerId = 326 },
})
check(okB == true, "headless start " .. tostring(err))
local log = Ui.log and Ui.log() or {}
local joined = table.concat(log, " || ")
check(joined:find("would like to battle", 1, true) ~= nil, "log has FRLG wants")
check(joined:find("wants\nto battle", 1, true) == nil, "log lacks Gen1 wants")
check(IntroSeq.busy() == false, "intro not busy headless")

print("[test] 5. Visibility + IntroSeq completes under Task/Fade")
if Battle.isActive and Battle.isActive() then Battle.abort("win") end
Anim.reset({ headless = false })
IntroSeq.reset()
Ui.reset({ headless = false })
okB = Battle.start({
  wild = true,
  headless = false,
  playerParty = {
    { species = 4, level = 5, hp = 20, maxHp = 20, moves = { 10 }, pp = { 35 }, maxPp = { 35 } },
  },
  foe = { species = 16, level = 3 },
  onDone = function() end,
})
check(okB == true, "non-headless wild start")
local p = Anim.present("player")
local stage = Anim.stage()
check(p.visible == false, "player mon hidden at intro start")
check(stage.healthbox.player.visible == false, "player healthbox hidden")

-- Drive sequencer without Message UI (no love input): auto-dismiss text.
local MessageMod = package.loaded["src.ui.game3.message"]
local guard = 0
local done = false
while not done and guard < 2000 do
  guard = guard + 1
  Task.update(1 / 60)
  Fade.tick(1 / 60)
  Anim.update(1 / 60)
  local okA, Audio = pcall(require, "src.core.game3.audio")
  if okA and Audio and Audio.tickCry then Audio.tickCry(1 / 60) end
  -- Instant-dismiss battle dialog so msg waits don't soft-lock the smoke test.
  Ui._queue = {}
  Ui._showing = false
  if MessageMod and MessageMod.close then MessageMod.close() end
  done = IntroSeq.update()
end
check(done == true, "IntroSeq completed in " .. guard .. " frames")
check(Anim.present("player").visible == true, "player visible after intro")
check(Anim.stage().healthbox.player.visible == true, "player healthbox visible after intro")
if Battle.isActive and Battle.isActive() then Battle.abort("win") end

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
