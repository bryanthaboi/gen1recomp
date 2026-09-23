#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").mountOrSkip("game3_battle_catch_ball_open_test")
require("tests.fixture_data.game3_items").install()

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local BallOpen = require("src.core.game3.battle.ball_open")
local sine = {}
for i = 0, 319 do sine[i + 1] = math.floor(math.sin(i * math.pi / 128) * 256 + 0.5) end
local colors = {
  { 31, 22, 30 }, { 16, 23, 30 }, { 23, 30, 20 }, { 31, 31, 15 }, { 23, 20, 28 }, { 21, 31, 25 },
  { 12, 25, 30 }, { 30, 27, 10 }, { 31, 24, 16 }, { 29, 30, 30 }, { 31, 17, 10 }, { 31, 9, 10 },
}
BallOpen.setData({ fadeColors = colors, sine = sine, sheetW = 64, sheetH = 8 }, false)

local Audio = require("src.core.game3.audio")
local SE = require("src.core.game3.se_ids")
local Catching = require("src.core.game3.battle.catching")
local Anim = require("src.core.game3.battle.anim")
local CatchSeq = require("src.core.game3.battle.catch_seq")
local Ui = require("src.core.game3.battle.ui")

local frame = 0
local sounds = {}
Audio.playSe = function(id) sounds[#sounds + 1] = { id = id, f = frame } return true end
Audio.stopAll = function() sounds[#sounds + 1] = { stop = true, f = frame } end
Audio.waitSe = function(id, cb) sounds[#sounds + 1] = { waitSe = id, f = frame, cb = cb } end
Audio.playSong = function(id) sounds[#sounds + 1] = { song = id, f = frame } return true end
Catching.storeCaught = function() return { firstTimeCaught = false } end
Ui.battlerSpriteCenter = function(_, _, base) return base.x, base.y end

local function se_frames(id)
  local out = {}
  for _, s in ipairs(sounds) do
    if s.id == id then out[#out + 1] = s.f end
  end
  return table.concat(out, ",")
end

local function run(caught, shakes)
  Anim.reset({ headless = false })
  Anim.present("enemy").visible = true
  sounds = {}
  local msgs = {}
  frame = 0
  local st = { enemy = { species = 16, mon = { species = 16, name = "PIDGEY" } } }
  CatchSeq.begin(st, 4, caught, shakes, {
    pushMsg = function(t) msgs[#msgs + 1] = { t = t, f = frame } end,
    headless = false,
    session = { name = "RED" },
  })
  CatchSeq.update()
  CatchSeq._waitingMsg = false
  CatchSeq.update()
  local log = {}
  for f = 1, 1200 do
    frame = f
    Anim.update(1 / 60)
    local b = CatchSeq._ball
    local s = Anim.stage().ball
    local p = Anim.present("enemy")
    log[f] = {
      sx = s.x, sy = s.y, visible = s.visible, ballFrame = s.frame, x2 = b.x2,
      rotation = b.aff.rotation, blend = b.blend.coeff, alpha = b.alpha,
      scale = p.scale, oy = p.oy, monVisible = p.visible,
      mon = (BallOpen.monBlend("enemy")), particles = BallOpen.particleCount(),
      finished = b.finished, invisibleStars = 0,
    }
    for _, q in ipairs(BallOpen.particles()) do
      if q.invisible then log[f].invisibleStars = log[f].invisibleStars + 1 end
    end
    CatchSeq.update()
    if not CatchSeq.busy() then break end
  end
  return log, msgs
end

print("[test] throw arc and ball open (pokefirered/src/battle_anim_special.c:810-863)")
local log, msgs = run(true, 4)
check(sounds[1] and sounds[1].id == SE.SE_BALL_THROW and sounds[1].f == 0, "SE_BALL_THROW when the ball sprite is created")
check(log[1].sx == 32 and log[1].sy == 80, "ball starts at (32,80)")
check(log[35].ballFrame == 0 and log[36].ballFrame == 1 and log[36].sx == 175 and log[36].sy == 24,
  "34-step arc ends at (175,24) and the ball opens on frame 36")
check(se_frames(SE.SE_BALL_OPEN) == "36", "SE_BALL_OPEN on the open frame only")
check(log[36].particles == 1 and log[51].particles == 16, "poke ball particles spawn one per frame from the open frame")
check(log[36].mon == 0 and log[44].mon == 8 and log[52].mon == 16 and log[90].mon == 16,
  "mon fades to ball color 0..16 over 17 frames and holds (LaunchBallFadeMonTask unfadeLater=FALSE)")

print("[test] shrink into ball (pokefirered/src/battle_anim_special.c:865-919)")
check(log[47].scale == 1 and math.abs(log[48].scale - 256 / 288) < 1e-9, "shrink starts 11 frames after the open")
check(se_frames(SE.SE_BALL_TRADE) == "57", "SE_BALL_TRADE on the 11th shrink tick")
check(log[75].monVisible and log[75].oy == -16 and log[76].monVisible == false, "28 rot-scale steps rise 16px, mon hidden on frame 76")
check(log[77].ballFrame == 1 and log[82].ballFrame == 0, "ball anim 2 closes after 5 frames")

print("[test] bounce and shakes (pokefirered/src/battle_anim_special.c:921-1160)")
check(se_frames(SE.SE_BALL_BOUNCE_1) == "104" and se_frames(SE.SE_BALL_BOUNCE_2) == "130"
  and se_frames(SE.SE_BALL_BOUNCE_3) == "152" and se_frames(SE.SE_BALL_BOUNCE_4) == "172", "four bounces at 104/130/152/172")
check(log[100].sy < 64 and log[172].sy == 64 and log[173].sy == 64, "ball settles at y=64")
check(se_frames(SE.SE_BALL) == "203,262,321", "three shakes 59 frames apart")
check(log[203].rotation == 64768 and log[204].rotation == 64000, "shake rotates -3 per frame (BALL_ROTATE_RIGHT)")
check(log[205].x2 == 0 and log[206].x2 == 1, "shake x2 steps by the 0xB0 subpixel counter")

print("[test] capture click and stars (pokefirered/src/battle_anim_special.c:1171-1303)")
check(se_frames(SE.SE_BALL_CLICK) == "390", "SE_BALL_CLICK 40 frames after the third shake ends")
check(log[390].particles == 3 and log[390].invisibleStars == 3 and log[391].invisibleStars == 0
  and log[413].particles == 3 and log[414].particles == 0, "3 capture stars flicker for 24 arc steps")
check(log[389].blend == 0 and log[413].blend == 6 and log[414].blend == 4 and log[418].blend == 2 and log[422].blend == 0,
  "ball blended 6 to black, then faded back with delay 2")
check(se_frames(319) == "445", "MUS_CAUGHT_INTRO 95 frames into the click")
check(log[667].alpha == 1 and log[668].alpha == 15 / 16 and log[698].alpha == 0 and log[698].visible and log[699].visible == false,
  "ball alpha blends out over 32 frames then hides")
check(log[700].finished ~= true and log[701].finished == true, "anim signals end on frame 701")
check(msgs[2] and msgs[2].f == 701 and msgs[2].t:match("^Gotcha!"), "Gotcha printed after the anim ends")
local waited = false
for _, s in ipairs(sounds) do if s.waitSe == 319 and s.f == 701 then waited = s.cb end end
check(waited ~= false, "MUS_CAUGHT waits for MUS_CAUGHT_INTRO")
if waited then waited() end
check(sounds[#sounds].song == 322, "MUS_CAUGHT after the intro SE")

print("[test] breakout after 1 shake (pokefirered/src/battle_anim_special.c:1305-1354)")
log, msgs = run(false, 1)
check(se_frames(SE.SE_BALL) == "203" and se_frames(SE.SE_BALL_OPEN) == "36,263", "ball reopens 31 frames after the only shake")
check(log[262].monVisible == false and log[263].monVisible and log[263].mon == 16, "mon reappears fully tinted on the breakout frame")
check(math.abs(log[263].scale - 0x28 / 256) < 1e-9 and math.abs(log[264].scale - 0x3A / 256) < 1e-9 and log[275].scale == 1,
  "BATTLER_AFFINE_EMERGE 0x28 + 12 x 0x12")
check(log[264].oy == 14 and log[275].oy == 2 and log[276].oy == 0, "mon y2 falls 288/256 per frame")
check(log[263].particles == 1 and log[264].particles == 2, "breakout burst spawns particles again")
check(log[273].visible and log[274].visible == false, "ball hides once open anim ends")
check(log[276].finished ~= true and log[277].finished == true and msgs[2] and msgs[2].f == 277
  and msgs[2].t == "Aww!\nIt appeared to be caught!", "breakout text after the anim ends")
for _ = 1, 60 do BallOpen.tick() end
check((BallOpen.monBlend("enemy")) == 0 and BallOpen._mon.enemy == nil and not BallOpen.active(), "mon unfades after the breakout")

print("[test] breakout with no shakes and after 3 shakes")
log, msgs = run(false, 0)
check(se_frames(SE.SE_BALL) == "" and se_frames(SE.SE_BALL_OPEN) == "36,204" and msgs[2] and msgs[2].f == 218,
  "BALL_NO_SHAKES breaks out 31 frames after the last bounce")
log, msgs = run(false, 3)
check(se_frames(SE.SE_BALL) == "203,262,321" and se_frames(SE.SE_BALL_OPEN) == "36,381" and msgs[2] and msgs[2].f == 395
  and msgs[2].t == "Shoot!\nIt was so close, too!", "BALL_3_SHAKES_FAIL breaks out after the third shake")

print(failed == 0 and "[ok] all" or ("[FAIL] " .. failed .. " failed"))
os.exit(failed == 0 and 0 or 1)
