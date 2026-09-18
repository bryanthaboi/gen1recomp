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
  local Bag = require("src.core.game3.bag")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local Ui = require("src.core.game3.battle.ui")
  local BallOpen = require("src.core.game3.battle.ball_open")
  local CatchSeq = require("src.core.game3.battle.catch_seq")
  local Catching = require("src.core.game3.battle.catching")
  local Audio = require("src.core.game3.audio")
  local SE = require("src.core.game3.se_ids")
  local session = Runtime.getSession()
  session.party = {}
  Party.giveMon(session, 4, 5)
  Bag.add(session.bag, 4, 10)

  local seLog = {}
  local realPlaySe = Audio.playSe
  Audio.playSe = function(id, opts)
    seLog[#seLog + 1] = { id = id, f = U.frame() }
    return realPlaySe(id, opts)
  end
  local function seFrames(id, after)
    local out = {}
    for _, e in ipairs(seLog) do
      if e.id == id and e.f >= (after or 0) then out[#out + 1] = e.f end
    end
    return out
  end

  local outcomes = { { false, 1 }, { true, 4 } }
  local realTry = Catching.tryCatch
  Catching.tryCatch = function(...)
    local o = table.remove(outcomes, 1)
    if o then return o[1], o[2] end
    return realTry(...)
  end

  local function waitFor(pred, maxFrames)
    for _ = 1, maxFrames do
      if pred() then return true end
      U.wait(1)
    end
    return pred()
  end

  local function sheetDraws()
    local img = BallOpen._image
    local n = 0
    local realDraw = love.graphics.draw
    love.graphics.draw = function(i, ...)
      if img and i == img then n = n + 1 end
      return realDraw(i, ...)
    end
    U.wait(1)
    love.graphics.draw = realDraw
    return n
  end

  local function toCommand(maxFrames)
    for _ = 1, maxFrames do
      if Battle._phase == "command" and not Ui.dialogPending() then return true end
      if Ui.dialogPending() then
        U.tap(game, "a")
        U.wait(3)
      else
        U.wait(1)
      end
    end
    return false
  end

  local function throw()
    local prev = CatchSeq._ball
    Ui._pendingCommand = { kind = "bag", user = "player", itemId = 4 }
    Ui._mode = "none"
    for _ = 1, 400 do
      if CatchSeq._ball and CatchSeq._ball ~= prev then return CatchSeq._ball end
      if Ui.dialogPending() then
        U.tap(game, "a")
        U.wait(2)
      else
        U.wait(1)
      end
    end
    return nil
  end

  local function logHas(text, from)
    for i = from or 1, #Ui._log do
      if Ui._log[i] == text or tostring(Ui._log[i]):find(text, 1, true) then return true end
    end
    return false
  end

  local ok, err = BattleBridge.startWild(Runtime._mod, game, { species = 16, level = 3 }, { fade = false })
  result(ok == true, "u9c wild battle started " .. tostring(err or ""))
  if not ok then love.event.quit(1) return end
  result(toCommand(2000), "u9c reached the command menu")

  local b = throw()
  result(b ~= nil, "u9c first ball thrown")
  if not b then love.event.quit(1) return end
  local throwF = seFrames(SE.SE_BALL_THROW)
  throwF = throwF[#throwF]

  local opened = waitFor(function() return BallOpen._mon.enemy ~= nil and BallOpen.particleCount() > 0 end, 80)
  local openF = seFrames(SE.SE_BALL_OPEN, throwF)[1]
  result(opened and openF and throwF and openF - throwF == 36,
    "u9c ball opens 36 frames after SE_BALL_THROW d=" .. tostring(openF and throwF and openF - throwF))
  local c0 = BallOpen.monBlend("enemy")
  result(c0 <= 2, "u9c mon starts its fade to ball color at the open coeff=" .. tostring(c0))
  U.wait(3)
  local n = sheetDraws()
  result(n >= 2, "u9c catch ball-open particles drawn n=" .. n)
  U.shot(game, DIR .. "/u9c_01_catch_open_burst.png")
  result(waitFor(function()
    return BallOpen.monBlend("enemy") == 16 and Anim.present("enemy").scale < 1 and Anim.present("enemy").visible
  end, 30), "u9c mon fully tinted while shrinking into the ball")
  result(waitFor(function() return BallOpen.bgCoeff() == 16 end, 30), "u9c terrain faded to white on the catch open")
  U.shot(game, DIR .. "/u9c_02_mon_tinted_shrinking.png")
  result(waitFor(function() return Anim.present("enemy").visible == false end, 60), "u9c mon absorbed into the ball")

  result(waitFor(function() return #seFrames(SE.SE_BALL, openF) >= 1 end, 300), "u9c ball shakes once")
  local shakeF = seFrames(SE.SE_BALL, openF)[1]
  result(shakeF - openF == 167, "u9c shake SE 167 frames after the open d=" .. tostring(shakeF - openF))
  U.wait(10)
  local rot = Anim.stage().ball.rot or 0
  result(math.abs(math.sin(rot)) > 0.01, "u9c ball rotated mid-shake rot=" .. string.format("%.3f", rot))
  U.shot(game, DIR .. "/u9c_03_ball_shake.png")

  result(waitFor(function() return #seFrames(SE.SE_BALL_OPEN, shakeF) >= 1 end, 120), "u9c ball breaks open")
  local breakF = seFrames(SE.SE_BALL_OPEN, shakeF)[1]
  result(breakF and breakF - shakeF == 60, "u9c breakout 60 frames after the shake d=" .. tostring(breakF and breakF - shakeF))
  local p = Anim.present("enemy")
  result(p.visible and BallOpen.monBlend("enemy") == 16 and p.scale < 0.5 and BallOpen.particleCount() > 0,
    "u9c breakout burst with the mon emerging at ball color")
  U.wait(2)
  U.shot(game, DIR .. "/u9c_04_breakout_burst.png")
  local logStart = #Ui._log + 1
  result(waitFor(function() return b.finished end, 60), "u9c breakout anim signalled end")
  result(waitFor(function() return logHas("Aww! It appeared to be caught!", logStart) end, 30),
    "u9c breakout text printed after the anim")
  result(waitFor(function()
    return BallOpen.monBlend("enemy") == 0 and Anim.present("enemy").scale == 1
  end, 90), "u9c mon back to normal colors and size")
  U.shot(game, DIR .. "/u9c_05_breakout_text.png")

  result(toCommand(3000), "u9c back at the command menu")
  local b2 = throw()
  result(b2 ~= nil, "u9c second ball thrown")
  if not b2 then love.event.quit(1) return end
  local throw2 = seFrames(SE.SE_BALL_THROW)
  throw2 = throw2[#throw2]
  result(waitFor(function() return #seFrames(SE.SE_BALL_CLICK, throw2) >= 1 end, 900), "u9c ball clicks")
  local clickF = seFrames(SE.SE_BALL_CLICK, throw2)[1]
  local shakes = seFrames(SE.SE_BALL, throw2)
  result(#shakes == 3 and clickF - shakes[3] == 69, "u9c three shakes then click 69 frames later d=" .. tostring(shakes[3] and clickF - shakes[3]))
  U.wait(4)
  local stars = 0
  for _, q in ipairs(BallOpen.particles()) do if q.animNum == 1 then stars = stars + 1 end end
  local blend = Anim.stage().ball.blend
  result(stars == 3 and blend and blend.coeff == 6 and blend.r == 0, "u9c 3 capture stars and ball darkened to coeff 6")
  U.shot(game, DIR .. "/u9c_06_capture_stars.png")
  result(waitFor(function() return #seFrames(319, clickF) >= 1 end, 80), "u9c MUS_CAUGHT_INTRO starts")
  local introF = seFrames(319, clickF)[1]
  result(introF - clickF == 55, "u9c MUS_CAUGHT_INTRO 55 frames after the click d=" .. tostring(introF - clickF))
  result(waitFor(function()
    local a = Anim.stage().ball.alpha
    return a and a < 0.6 and a > 0
  end, 320), "u9c ball blending out")
  U.shot(game, DIR .. "/u9c_07_ball_blending_out.png")
  local log2 = #Ui._log + 1
  result(waitFor(function() return b2.finished end, 80), "u9c capture anim signalled end")
  result(waitFor(function() return logHas("Gotcha!", log2) end, 30), "u9c Gotcha printed after the anim")
  U.wait(10)
  U.shot(game, DIR .. "/u9c_08_gotcha.png")

  love.event.quit(fails == 0 and 0 or 1)
end
