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

local Ui = require("src.core.game3.battle.ui")
local Anim = require("src.core.game3.battle.anim")
local BattleBg = require("src.core.game3.battle.bg")
local Healthbox = require("src.core.game3.battle.healthbox")
local BattleChrome = require("src.ui.game3.battle_chrome")
local TrainerPic = require("src.core.game3.trainer_pic")
local Pokemon = require("src.core.game3.pokemon")

local IMG = { enemyMon = { tag = "enemyMon" }, playerMon = { tag = "playerMon" } }

local calls = {}
local gfx = setmetatable({}, { __index = function() return function() end end })
gfx.draw = function(img, x, y, r, sx, sy)
  if img and img.tag then calls[img.tag] = { sx = sx, sy = sy } end
end
gfx.newQuad = function() return {} end
_G.love = { graphics = gfx }

BattleBg.draw = function() return true end
Healthbox.draw = function() end
BattleChrome.drawPanel = function() end
BattleChrome.drawPartyBar = function() end
BattleChrome.manifest = function() return {} end
Anim.drawParticles = function() end
TrainerPic.front = function() return nil end
TrainerPic.back = function() return nil end
Pokemon.frontPic = function() return { image = IMG.enemyMon } end
Pokemon.backPic = function() return { image = IMG.playerMon } end

local function near(a, b) return a and math.abs(a - b) < 1e-6 end

local function drawWith(setup)
  Ui.reset({ headless = false })
  Anim.reset({ headless = false })
  Ui._st = { enemy = { species = 16 }, player = { species = 4 } }
  Anim.present("player").visible = true
  Anim.present("enemy").visible = true
  setup(Anim.present("player"), Anim.present("enemy"))
  calls = {}
  Ui.draw(240, 160)
  return calls.playerMon, calls.enemyMon
end

print("[test] emerge scale reaches the drawn pic")
local p, e = drawWith(function(pp, pe)
  pp.scale = 0.23
  pe.scale = 0.16
end)
check(p and near(p.sx, 0.23) and near(p.sy, 0.23), "player pic drawn at pres.scale 0.23")
check(e and near(e.sx, 0.16) and near(e.sy, 0.16), "enemy pic drawn at pres.scale 0.16")

print("[test] default present draws at 1.0")
p, e = drawWith(function() end)
check(p and near(p.sx, 1) and near(p.sy, 1), "player pic drawn at 1.0")
check(e and near(e.sx, 1) and near(e.sy, 1), "enemy pic drawn at 1.0")

print("[test] deform sx/sy composes with scale")
p = drawWith(function(pp)
  pp.scale = 0.5
  pp.sx = 0.8
  pp.sy = 1.2
end)
check(p and near(p.sx, 0.4) and near(p.sy, 0.6), "sx/sy deform multiplies scale")

p = drawWith(function(pp)
  pp.sx = 0.8
  pp.sy = 1.2
end)
check(p and near(p.sx, 0.8) and near(p.sy, 1.2), "sx/sy deform unchanged at scale 1")

print("[test] hFlip keeps scale magnitude")
p = drawWith(function(pp)
  pp.scale = 0.5
  pp.hFlip = true
end)
check(p and near(p.sx, -0.5) and near(p.sy, 0.5), "hFlip gives -scale on x")

print(failed == 0 and "[ok] all" or ("[FAIL] " .. failed .. " failed"))
os.exit(failed == 0 and 0 or 1)
