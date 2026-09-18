#!/usr/bin/env luajit
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

local BallOpen = require("src.core.game3.battle.ball_open")

local sine = {}
for i = 0, 319 do sine[i + 1] = math.floor(math.sin(i * math.pi / 128) * 256 + 0.5) end
local colors = {
  { 31, 22, 30 }, { 16, 23, 30 }, { 23, 30, 20 }, { 31, 31, 15 }, { 23, 20, 28 }, { 21, 31, 25 },
  { 12, 25, 30 }, { 30, 27, 10 }, { 31, 24, 16 }, { 29, 30, 30 }, { 31, 17, 10 }, { 31, 9, 10 },
}
local DATA = { fadeColors = colors, sine = sine, sheetW = 64, sheetH = 8 }
BallOpen.setData(DATA, false)

print("[test] ItemIdToBallId")
check(BallOpen.ballIdForItem(4) == 0, "poke ball item 4 -> BALL_POKE")
check(BallOpen.ballIdForItem(1) == 4, "master ball item 1 -> BALL_MASTER")
check(BallOpen.ballIdForItem(3) == 1, "great ball item 3 -> BALL_GREAT")
check(BallOpen.ballIdForItem(12) == 11, "premier ball item 12 -> BALL_PREMIER")
check(BallOpen.ballIdForItem(nil) == 0 and BallOpen.ballIdForItem(13) == 0, "unknown item -> BALL_POKE")

print("[test] BlendPalette 5-bit math")
check(BallOpen.blend5(0, 31, 16) == 31, "coeff 16 reaches target")
check(BallOpen.blend5(31, 0, 8) == 15, "negative delta floors like >> 4")
check(BallOpen.blend5(10, 31, 0) == 10, "coeff 0 keeps color")

print("[test] poke ball open: mon tint + BG white fade timeline")
BallOpen.reset()
BallOpen.start("player", 71, 98, 4)
local c0, r, g, b = BallOpen.monBlend("player")
check(c0 == 16 and r == 31 and g == 22 and b == 30, "mon fully blended to RGB(31,22,30) on open")
check(BallOpen.bgCoeff() == 0 and BallOpen.fadeActive(), "BG fade begins at y=0")
local bg, mon, count, first = {}, {}, {}, {}
for k = 0, 45 do
  BallOpen.tick()
  bg[k] = BallOpen.bgCoeff()
  mon[k] = (BallOpen.monBlend("player"))
  count[k] = BallOpen.particleCount()
  local p = BallOpen.particles()[1]
  first[k] = p and { x = p.x, y = p.y, x2 = p.x2, y2 = p.y2, frame = p.frame, hFlip = p.hFlip, beg = p.animBeginning }
end
check(bg[0] == 0 and bg[1] == 2 and bg[3] == 4 and bg[15] == 16, "BG y steps 2 every other frame up to 16")
check(bg[21] == 16 and bg[22] == 16 and bg[23] == 14 and bg[37] == 0, "BG fades back once the first fade finishes")
check(mon[0] == 16 and mon[22] == 16 and mon[23] == 15 and mon[30] == 8, "mon holds 16 then unblends one step per frame")
check(mon[38] == 0 and BallOpen._mon.player == nil, "mon palette restored after 17 steps")
check(not BallOpen.fadeActive() and not BallOpen.active(), "fade and tasks finished")

print("[test] poke ball particles")
check(count[0] == 1 and count[14] == 15 and count[15] == 16, "one particle per frame for 16 frames")
check(first[0].x == 71 and first[0].y == 93 and first[0].beg, "spawned at ball x, y-5 and hidden until animated")
check(first[10].x2 == 0 and first[10].y2 == 16, "particle 0 radius grows 2 per frame along angle 0")
check(first[1].frame == 0 and first[2].frame == 1 and first[3].frame == 2
  and first[4].frame == 0 and first[4].hFlip and first[5].frame == 2
  and first[6].frame == 1 and first[7].frame == 0 and not first[7].hFlip, "sAnim_RegularBall frame loop")
check(count[25] == 16 and count[26] == 15 and count[40] == 1 and count[41] == 0, "particle dies when radius reaches 50")

print("[test] fan-out balls")
BallOpen.reset()
BallOpen.start("enemy", 176, 64, 3)
BallOpen.tick()
local n0 = BallOpen.particleCount()
for _ = 1, 8 do BallOpen.tick() end
local n8 = BallOpen.particleCount()
BallOpen.tick()
check(n0 == 8 and n8 == 8 and BallOpen.particleCount() == 16, "great ball bursts 8, then 8 more 9 frames later")
local bc = { BallOpen.monBlend("enemy") }
check(bc[1] == 16 and bc[2] == 16 and bc[3] == 23 and bc[4] == 30, "great ball tint color")
for item, want in pairs({ [1] = 16, [2] = 10, [9] = 12, [12] = 8, [10] = 8, [7] = 8 }) do
  BallOpen.reset()
  BallOpen.start("enemy", 176, 64, item)
  BallOpen.tick()
  check(BallOpen.particleCount() == want, "item " .. item .. " spawns " .. want .. " particles")
end
BallOpen.reset()
BallOpen.start("enemy", 176, 64, 2)
for _ = 0, 50 do BallOpen.tick() end
local alive50 = BallOpen.particleCount()
BallOpen.tick()
check(alive50 == 10 and BallOpen.particleCount() == 0, "fan-out particles die on the 51st step")

print("[test] battle UI draws the blend and particles")
local Ui = require("src.core.game3.battle.ui")
local Anim = require("src.core.game3.battle.anim")
local BattleBg = require("src.core.game3.battle.bg")
local Healthbox = require("src.core.game3.battle.healthbox")
local BattleChrome = require("src.ui.game3.battle_chrome")
local TrainerPic = require("src.core.game3.trainer_pic")
local Pokemon = require("src.core.game3.pokemon")

local IMG = { enemyMon = { tag = "enemyMon" }, playerMon = { tag = "playerMon" } }
local SHEET = { tag = "sheet", getDimensions = function() return 64, 8 end }
local log, current = {}, nil
local gfx = setmetatable({}, { __index = function() return function() end end })
gfx.newShader = function() return { send = function(self, k, v) self[k] = v end } end
gfx.setShader = function(sh) current = sh end
gfx.newQuad = function() return {} end
gfx.draw = function(img)
  if type(img) == "table" and img.tag then
    log[#log + 1] = { tag = img.tag, coeff = current and current.coeff, target = current and current.target }
  end
end
_G.love = { graphics = gfx }

BattleBg.draw = function()
  log[#log + 1] = { tag = "bg", coeff = current and current.coeff, target = current and current.target }
  return true
end
Healthbox.draw = function() log[#log + 1] = { tag = "healthbox" } end
BattleChrome.drawPanel = function() end
BattleChrome.drawPartyBar = function() end
BattleChrome.manifest = function() return {} end
Anim.drawParticles = function() end
TrainerPic.front = function() return nil end
TrainerPic.back = function() return nil end
Pokemon.frontPic = function() return { image = IMG.enemyMon } end
Pokemon.backPic = function() return { image = IMG.playerMon } end

Ui.reset({ headless = false })
Anim.reset({ headless = false })
BallOpen.setData(DATA, SHEET)
Ui._st = { enemy = { species = 16 }, player = { species = 4, mon = { pokeball = 4 } } }
Anim.present("player").visible = true
Anim.present("enemy").visible = true
check(Anim.ballOpen("player", 71, 98) == 0, "Anim.ballOpen starts the burst")
for _ = 1, 16 do BallOpen.tick() end

local function find(tag)
  for i, e in ipairs(log) do if e.tag == tag then return i, e end end
end
log = {}
Ui.draw(240, 160)
local _, bgE = find("bg")
check(bgE and bgE.coeff == BallOpen.bgCoeff() and bgE.coeff == 16 and bgE.target[1] == 31, "terrain drawn through the white fade at y=16")
local _, pm = find("playerMon")
check(pm and pm.coeff == 16 and pm.target[1] == 31 and pm.target[2] == 22 and pm.target[3] == 30, "player pic drawn blended to ball color")
local _, em = find("enemyMon")
check(em and em.coeff == nil, "enemy pic not blended")
local sheets, lastSheet = 0, 0
for i, e in ipairs(log) do if e.tag == "sheet" then sheets = sheets + 1 lastSheet = i end end
local hb = find("healthbox")
check(BallOpen.particleCount() == 16 and sheets == 15 and hb and lastSheet < hb,
  "animated particles drawn under the healthboxes, newest still hidden")

Anim.reset({ headless = true })
check(Anim.ballOpen("player", 71, 98) == nil and BallOpen.particleCount() == 0, "headless battles skip the burst")

print(failed == 0 and "[ok] all" or ("[FAIL] " .. failed .. " failed"))
os.exit(failed == 0 and 0 or 1)
