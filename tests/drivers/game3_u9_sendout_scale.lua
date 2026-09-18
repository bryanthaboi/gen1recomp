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
  local Pokemon = require("src.core.game3.pokemon")
  local session = Runtime.getSession()
  session.party = {}
  Party.giveMon(session, 4, 5)

  local function waitEmerge(side, maxFrames)
    for _ = 1, maxFrames do
      local p = Anim.present(side)
      local s = Anim.stage()
      if p and p.visible ~= false and (p.scale or 1) < 0.35 and s.ball and s.ball.visible
        and (s.ball.frame or 0) >= 1 then
        return true
      end
      if Ui.dialogPending and Ui.dialogPending() then
        U.tap(game, "a")
      else
        U.wait(1)
      end
    end
    return false
  end

  local function drawnScale(side)
    local b = Ui._st and Ui._st[side]
    local sp = b and (b.species or (b.mon and Pokemon.speciesOf(b.mon)))
    local entry = side == "player" and Pokemon.backPic(sp) or Pokemon.frontPic(sp)
    local img = entry and entry.image
    local got
    local realDraw = love.graphics.draw
    love.graphics.draw = function(i, x, y, r, sx, sy, ...)
      if i == img and not got then got = { sx = sx, sy = sy } end
      return realDraw(i, x, y, r, sx, sy, ...)
    end
    U.wait(1)
    love.graphics.draw = realDraw
    return got
  end

  local function waitScale(side, target, maxFrames)
    for _ = 1, maxFrames do
      local p = Anim.present(side)
      if p and p.visible ~= false and (p.scale or 1) >= target
        and (target < 1 or (p.oy or 0) == 0) then return true end
      U.wait(1)
    end
    return false
  end

  local function waitFull(side, maxFrames)
    return waitScale(side, 1, maxFrames)
  end

  local ok, err = BattleBridge.startWild(Runtime._mod, game, { species = 16, level = 3 }, { fade = false })
  result(ok == true, "u9 wild battle started " .. tostring(err or ""))
  if not ok then love.event.quit(1) return end

  local reached = waitEmerge("player", 1500)
  result(reached, "u9 player send-out emerge started")
  if reached then
    local want = Anim.present("player").scale
    local got = drawnScale("player")
    result(got ~= nil and math.abs(got.sy) < 0.5 and math.abs(got.sy) >= want - 1e-6,
      string.format("u9 player pic drawn scaled on open tick sy=%s pres=%.2f", tostring(got and got.sy), want))
    if waitScale("player", 0.55, 30) then
      U.shot(game, DIR .. "/u9_01_player_emerge_half_size.png")
    end
    result(waitFull("player", 60), "u9 player emerge grew to full size")
    U.shot(game, DIR .. "/u9_02_player_emerge_full.png")
  end

  Battle.abort("win")
  U.wait(120)
  for _ = 1, 30 do U.tap(game, "a") U.wait(4) end

  local ok2, err2 = BattleBridge.start(Runtime._mod, game,
    { trainerId = 326, party = { { species = 7, level = 5 } } },
    { wild = false, trainerId = 326, fade = false })
  result(ok2 == true, "u9 trainer battle started " .. tostring(err2 or ""))
  if ok2 then
    reached = waitEmerge("enemy", 2000)
    result(reached, "u9 enemy send-out emerge started")
    if reached then
      local want = Anim.present("enemy").scale
      local got = drawnScale("enemy")
      result(got ~= nil and math.abs(got.sy) < 0.5 and math.abs(got.sy) >= want - 1e-6,
        string.format("u9 enemy pic drawn scaled on open tick sy=%s pres=%.2f", tostring(got and got.sy), want))
      if waitScale("enemy", 0.55, 30) then
        U.shot(game, DIR .. "/u9_03_enemy_emerge_half_size.png")
      end
      result(waitFull("enemy", 60), "u9 enemy emerge grew to full size")
      U.shot(game, DIR .. "/u9_04_enemy_emerge_full.png")
    end
  end

  love.event.quit(fails == 0 and 0 or 1)
end
