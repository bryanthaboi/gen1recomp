return function(game)
  local U = dofile("tests/drivers/util.lua")
  local PaletteFX = require("src.render.PaletteFX")
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp"
  pcall(function() io.stdout:setvbuf("no") end)
  local ok = true

  local function report(label, pass, detail)
    print((pass and "PASS " or "FAIL ") .. label .. (detail and (" " .. detail) or ""))
    ok = ok and pass
  end

  local function fmt(m)
    return m and (m[0] .. m[1] .. m[2] .. m[3]) or "nil"
  end

  local function finish()
    print(ok and "PASS yellow_smog_advanced_3073" or "FAIL yellow_smog_advanced_3073")
    love.event.quit(ok and 0 or 1)
    while true do coroutine.yield() end
  end

  U.newGame(game)
  U.wait(30)
  PaletteFX.setMode("redpp")
  report("mode is ADVANCED", PaletteFX.mode == "redpp", tostring(PaletteFX.mode))
  report("wOnSGB is set on Yellow ADVANCED", not PaletteFX.runsNotSGB())

  local koffing = Pokemon.new(game.data, "KOFFING", 30)
  koffing.moves = { { id = "SMOG", pp = game.data.moves.SMOG.pp } }
  game.save.party = { koffing }

  U.teleport(game, "ROUTE_1", 5, 5, "down")
  U.wait(10)
  local ow = game.overworld
  local battle = BattleState.newWild(game, "PIDGEY", 20)
  battle.onFinish = function() end
  ow:pushBattle(battle)
  for _ = 1, 600 do
    if game.stack:top() == battle and (battle.introSlide or 0) == 0
        and battle.phase == "menu" then break end
    if battle.phase == "messages" then U.tap(game, "a") end
    U.wait(2)
  end
  report("battle reached the FIGHT menu", battle.phase == "menu", tostring(battle.phase))
  if battle.phase ~= "menu" then finish() end

  battle.enemy.mon.stats.hp = 400
  battle.enemy.mon.hp = 400
  battle.enemy.shownHP = 400
  for i = #battle.enemy.mon.moves, 1, -1 do
    local id = battle.enemy.mon.moves[i].id
    if id == "WHIRLWIND" or id == "SAND_ATTACK" then
      table.remove(battle.enemy.mon.moves, i)
    end
  end

  local darken
  local realFx = battle.applyAnimEffect
  battle.applyAnimEffect = function(self, ev)
    realFx(self, ev)
    if ev and ev.effect == "SE_DARKEN_MON_PALETTE" and not darken then
      darken = fmt(self.fx and self.fx.bgp)
    end
  end

  local shot, applied
  for _ = 1, 6 do
    battle.player.stages.accuracy = 0
    for _ = 1, 120 do
      if battle.phase == "moveSelect" then break end
      U.tap(game, "a")
      U.wait(4)
    end
    for _ = 1, 20 do
      if battle.phase ~= "moveSelect" then break end
      U.tap(game, "a")
      U.wait(3)
    end
    for i = 1, 2400 do
      if darken and not shot then
        applied = fmt(battle:activeBgp())
        U.wait(6)
        applied = fmt(battle:activeBgp())
        shot = U.still(game, DIR .. "/3073_01_smog_darken_advanced_yellow.png")
      end
      if battle.phase == "menu" and #battle.queue == 0 and i > 30 then break end
      if battle.phase == "messages" and i % 8 == 0 then
        table.insert(game.input.pressQueue, "a")
      end
      U.wait(1)
      game.input.state.a = false
    end
    if darken then break end
    print("SMOG did not connect that turn; using it again")
  end

  report("SE_DARKEN_MON_PALETTE fired", darken ~= nil)
  report("darken BGP is $f4", darken == "0133", tostring(darken))
  report("BG shade map on screen mid-darken is $f4", applied == "0133", tostring(applied))
  report("mid-darken screenshot written", shot == true)
  if shot then
    local f = io.open(DIR .. "/3073_01_smog_darken_advanced_yellow.png", "rb")
    local bytes = f and f:read("*a")
    if f then f:close() end
    local img = bytes and love.image.newImageData(love.filesystem.newFileData(bytes, "shot.png"))
    if img then
      local w, h = img:getDimensions()
      local s = math.floor(math.min(w / 160, h / 144))
      local ox, oy = math.floor((w - 160 * s) / 2), math.floor((h - 144 * s) / 2)
      local r, g, b = img:getPixel(ox + 90 * s + 2, oy + 44 * s + 2)
      local px = string.format("(%d,%d,%d)", r * 255 + 0.5, g * 255 + 0.5, b * 255 + 0.5)
      report("paper beside the enemy pic stays white mid-darken", r > 0.95 and g > 0.95 and b > 0.95, px)
    else
      report("screenshot decoded", false)
    end
  end
  finish()
end
