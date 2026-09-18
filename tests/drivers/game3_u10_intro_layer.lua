local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp"

return function(game)
  local fails = 0
  local function result(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then fails = fails + 1 end
  end

  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local session = Runtime.getSession()
  session.party = {}
  Party.giveMon(session, 4, 5)
  local BattleBridge = require("src.core.game3.battle_bridge")
  local species = tonumber(os.getenv("U10_SPECIES") or "") or 95
  local ok, err = BattleBridge.startWild(Runtime._mod, game, { species = species, level = 3 }, { fade = false })
  result(ok == true, "u10 wild battle started " .. tostring(err or ""))
  if not ok then love.event.quit(1) return end

  local Anim = require("src.core.game3.battle.anim")
  local TrainerPic = require("src.core.game3.trainer_pic")
  local Pokemon = require("src.core.game3.pokemon")

  local function waitEnemyOx(target)
    for _ = 1, 900 do
      local p = Anim.present("enemy")
      if p and p.visible ~= false and (p.ox or 0) >= target then return true end
      U.wait(1)
    end
    return false
  end

  local function recordOrder()
    local monEntry = Pokemon.frontPic(species)
    local backEntry = TrainerPic.back(Anim.stage().trainer.player.gender or 0)
    local monImg = monEntry and monEntry.image
    local backImg = backEntry and backEntry.image
    local order = {}
    local realDraw = love.graphics.draw
    love.graphics.draw = function(img, ...)
      if img == monImg then order[#order + 1] = "mon" end
      if img == backImg then order[#order + 1] = "back" end
      return realDraw(img, ...)
    end
    U.wait(2)
    love.graphics.draw = realDraw
    local iMon, iBack
    for i, t in ipairs(order) do
      if t == "mon" and not iMon then iMon = i end
      if t == "back" and not iBack then iBack = i end
    end
    return iMon, iBack
  end

  local reached = waitEnemyOx(-48)
  result(reached, "u10 enemy mon reached crossing ox -48")
  if reached then
    local tp = Anim.stage().trainer.player
    result(tp.visible == true, "u10 player trainer back pic visible at crossing")
    local iMon, iBack = recordOrder()
    result(iMon ~= nil and iBack ~= nil and iMon < iBack, "u10 enemy mon drawn under trainer back pic")
    U.shot(game, DIR .. "/u10_01_cap_over_mon_crossing.png")
  end

  reached = waitEnemyOx(-32)
  if reached then
    U.shot(game, DIR .. "/u10_02_cap_brim_over_mon_tail.png")
  end

  reached = waitEnemyOx(0)
  result(reached, "u10 intro slide finished")
  if reached then
    U.shot(game, DIR .. "/u10_03_slide_settled.png")
  end

  love.event.quit(fails == 0 and 0 or 1)
end
