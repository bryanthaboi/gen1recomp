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

local IMG = {
  enemyMon = { tag = "enemyMon" },
  playerMon = { tag = "playerMon" },
  trainerBack = { tag = "trainerBack" },
  trainerFront = { tag = "trainerFront" },
}

local drawn = {}
local gfx = setmetatable({}, { __index = function() return function() end end })
gfx.draw = function(img) drawn[#drawn + 1] = img and img.tag end
gfx.newQuad = function() return {} end
_G.love = { graphics = gfx }

BattleBg.draw = function() return true end
Healthbox.draw = function() end
BattleChrome.drawPanel = function() end
BattleChrome.drawPartyBar = function() end
BattleChrome.manifest = function() return {} end
Anim.drawParticles = function() end
TrainerPic.front = function() return { image = IMG.trainerFront } end
TrainerPic.back = function() return { image = IMG.trainerBack } end
Pokemon.frontPic = function() return { image = IMG.enemyMon } end
Pokemon.backPic = function() return { image = IMG.playerMon } end

local function indexOf(tag)
  for i, t in ipairs(drawn) do
    if t == tag then return i end
  end
  return nil
end

print("[test] wild intro: enemy mon passes under player trainer back pic")
Ui.reset({ headless = false })
Anim.reset({ headless = false })
Ui._st = { enemy = { species = 95 }, player = { species = 4 } }
Anim.present("enemy").visible = true
Anim.present("enemy").ox = -48
local stage = Anim.stage()
stage.trainer.player.visible = true
stage.trainer.player.ox = 48
drawn = {}
Ui.draw(240, 160)
local iMon, iBack = indexOf("enemyMon"), indexOf("trainerBack")
check(iMon ~= nil and iBack ~= nil, "both enemy mon and trainer back drawn")
check(iMon and iBack and iMon < iBack, "enemy mon drawn before player trainer back")

print("[test] trainer intro: enemy trainer front under player trainer back")
Ui.reset({ headless = false })
Anim.reset({ headless = false })
Ui._st = { enemy = { species = 7 }, player = { species = 4 } }
stage = Anim.stage()
stage.trainer.enemy.visible = true
stage.trainer.enemy.picId = 106
stage.trainer.player.visible = true
drawn = {}
Ui.draw(240, 160)
local iFront = indexOf("trainerFront")
iBack = indexOf("trainerBack")
check(iFront and iBack and iFront < iBack, "enemy trainer front drawn before player trainer back")

print("[test] send-out: player mon still above enemy mon")
Ui.reset({ headless = false })
Anim.reset({ headless = false })
Ui._st = { enemy = { species = 95 }, player = { species = 4 } }
Anim.present("enemy").visible = true
Anim.present("player").visible = true
drawn = {}
Ui.draw(240, 160)
iMon = indexOf("enemyMon")
local iPlayer = indexOf("playerMon")
check(iMon and iPlayer and iMon < iPlayer, "enemy mon drawn before player mon")

if failed > 0 then
  print("[test] FAILED " .. failed)
  os.exit(1)
end
print("[test] all passed")
