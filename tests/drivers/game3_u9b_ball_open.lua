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
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local Ui = require("src.core.game3.battle.ui")
  local BallOpen = require("src.core.game3.battle.ball_open")
  local session = Runtime.getSession()
  session.party = {}
  Party.giveMon(session, 4, 5)

  local d = BallOpen.data()
  result(d ~= nil and d.fadeColors and #d.fadeColors == 12 and d.sine and #d.sine == 320,
    "u9b ball_open manifest loaded from cache")

  local function waitOpen(side, maxFrames)
    for _ = 1, maxFrames do
      if BallOpen._mon[side] and BallOpen.particleCount() > 0 then return true end
      if Ui.dialogPending and Ui.dialogPending() then
        U.tap(game, "a")
      else
        U.wait(1)
      end
    end
    return false
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

  local function waitFor(pred, maxFrames)
    for _ = 1, maxFrames do
      if pred() then return true end
      U.wait(1)
    end
    return pred()
  end

  local function runSide(side, prefix, shotBase)
    local c = BallOpen.monBlend(side)
    result(c == 16, prefix .. " mon blended to ball color on open tick coeff=" .. tostring(c))
    U.wait(3)
    local n = sheetDraws()
    result(n >= 3, prefix .. " ball-open particles drawn n=" .. n)
    U.shot(game, DIR .. "/" .. shotBase[1])
    result(waitFor(function() return BallOpen.bgCoeff() == 16 end, 30), prefix .. " terrain faded to white")
    U.shot(game, DIR .. "/" .. shotBase[2])
    local mid = waitFor(function()
      local m = BallOpen.monBlend(side)
      return m > 0 and m <= 10
    end, 60)
    result(mid, prefix .. " mon unblending back to normal")
    U.shot(game, DIR .. "/" .. shotBase[3])
    result(waitFor(function()
      return not BallOpen.active() and BallOpen.monBlend(side) == 0 and BallOpen.bgCoeff() == 0
    end, 120), prefix .. " palettes restored and particles gone")
    U.shot(game, DIR .. "/" .. shotBase[4])
  end

  local ok, err = BattleBridge.startWild(Runtime._mod, game, { species = 16, level = 3 }, { fade = false })
  result(ok == true, "u9b wild battle started " .. tostring(err or ""))
  if not ok then love.event.quit(1) return end
  local opened = waitOpen("player", 1500)
  result(opened, "u9b player ball opened")
  if opened then
    runSide("player", "u9b player", {
      "u9b_01_player_ball_open_burst.png",
      "u9b_02_player_mon_pink_terrain_white.png",
      "u9b_03_player_mon_unblending.png",
      "u9b_04_player_restored.png",
    })
  end

  Battle.abort("win")
  U.wait(120)
  for _ = 1, 30 do U.tap(game, "a") U.wait(4) end

  local ok2, err2 = BattleBridge.start(Runtime._mod, game,
    { trainerId = 326, party = { { species = 7, level = 5 } } },
    { wild = false, trainerId = 326, fade = false })
  result(ok2 == true, "u9b trainer battle started " .. tostring(err2 or ""))
  if ok2 then
    local opened2 = waitOpen("enemy", 2000)
    result(opened2, "u9b enemy ball opened")
    if opened2 then
      runSide("enemy", "u9b enemy", {
        "u9b_05_enemy_ball_open_burst.png",
        "u9b_06_enemy_mon_pink_terrain_white.png",
        "u9b_07_enemy_mon_unblending.png",
        "u9b_08_enemy_restored.png",
      })
    end
  end

  love.event.quit(fails == 0 and 0 or 1)
end
