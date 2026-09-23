-- data/moves/animations.asm:659
-- engine/battle/animations.asm:2326-2469
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"

  local fails = 0
  local function check(label, ok)
    if ok then
      print("PASS " .. label)
    else
      print("FAIL " .. label)
      fails = fails + 1
    end
    return ok
  end

  game.save.options = game.save.options or {}
  game.save.options.animations = true

  local anims = game.data.battle_anims or {}
  local deltas = anims.fallingDeltaXs
  check("cache carries the falling-object delta-X bytes",
        deltas ~= nil and deltas[63] ~= nil)
  local expect10 = deltas and (0x4A - deltas[10]) % 256

  U.teleport(game, "ROUTE_1", 5, 5, "down")
  U.wait(15)
  local ow = game.overworld
  check("standing on ROUTE_1", ow and ow.map and ow.map.id == "ROUTE_1")

  local function petalStep(battle)
    local ap = battle.animPlayer
    local st = ap and ap.steps[ap.stepIndex]
    if battle.animPlaying and st and #st.sprites == 20 then return st end
  end

  local function waitPhase(battle, phase, tries)
    for _ = 1, tries do
      if battle.phase == phase then return true end
      U.tap(game, "a")
      U.wait(6)
    end
    if battle.phase ~= phase then
      U.log("stuck in phase", tostring(battle.phase), "waiting on", phase)
    end
    return battle.phase == phase
  end

  local function leaveBattle()
    for _ = 1, 10 do
      if game.stack:top() == ow then break end
      game.stack:pop()
    end
  end

  local function watchPetals(battle, side, targets)
    local startAt, first
    for _ = 1, 3000 do
      local st = petalStep(battle)
      if st and battle.animName == "PETAL_DANCE"
         and battle.animAttackerIsPlayer == (side == "player") then
        startAt = battle.animPlayer.elapsed
        first = st
        break
      end
      if game.stack:top() ~= battle then break end
      if U.frame() % 6 == 0 then U.tap(game, "a") else U.wait(1) end
    end
    if not check(side .. " PETAL_DANCE reached the falling petals", startAt ~= nil) then
      return
    end
    check(("%s petal 10 jumps to x=%s on tick 1 (got %s)"):format(
            side, tostring(expect10), tostring(first.sprites[10].x)),
          first.sprites[10].x == expect10)
    check(side .. " petals fall under the light palette",
          battle.fx and battle.fx.bgp ~= nil)

    local seen = 0
    local lastElapsed = startAt
    for _, target in ipairs(targets) do
      for _ = 1, 400 do
        if battle.animPlayer.elapsed - startAt >= target then break end
        if petalStep(battle) then seen = seen + 1 end
        U.wait(1)
      end
      lastElapsed = battle.animPlayer.elapsed
      if petalStep(battle) then
        U.still(game, ("%s/2428_%s_petals_f%03d.png"):format(DIR, side, target))
      end
    end
    for _ = 1, 400 do
      if not petalStep(battle) then break end
      seen = seen + 1
      U.wait(1)
    end
    local total = battle.animPlayer.elapsed - startAt
    check(("%s petals stay up about 156 frames (got %d)"):format(side, total),
          total >= 150 and total <= 160 and lastElapsed > startAt)
    check(side .. " no battle animation failed to start",
          battle.animStartWarned == nil)
  end

  local lead = Pokemon.new(game.data, "VILEPLUME", 40)
  lead.moves = { { id = "PETAL_DANCE", pp = 20 } }
  game.save.party = { lead }
  local battle = BattleState.newWild(game, "SLOWPOKE", 40)
  battle.onFinish = function() end
  battle.enemy.mon.moves = { { id = "GROWL", pp = 40 } }
  battle.enemy.curMoves = battle.enemy.mon.moves
  ow:pushBattle(battle)
  check("player battle reached the menu", waitPhase(battle, "menu", 600))
  U.tap(game, "a")
  check("PETAL_DANCE is on the move list", waitPhase(battle, "moveSelect", 20))
  U.tap(game, "a")
  watchPetals(battle, "player", { 5, 40, 90, 150 })
  leaveBattle()

  local guard = Pokemon.new(game.data, "CHARIZARD", 70)
  guard.moves = { { id = "GROWL", pp = 40 } }
  game.save.party = { guard }
  local foeBattle = BattleState.newWild(game, "VILEPLUME", 30)
  foeBattle.onFinish = function() end
  foeBattle.enemy.mon.moves = { { id = "PETAL_DANCE", pp = 20 } }
  foeBattle.enemy.curMoves = foeBattle.enemy.mon.moves
  ow:pushBattle(foeBattle)
  check("foe battle reached the menu", waitPhase(foeBattle, "menu", 600))
  U.tap(game, "a")
  check("GROWL is on the move list", waitPhase(foeBattle, "moveSelect", 20))
  U.tap(game, "a")
  watchPetals(foeBattle, "enemy", { 40, 90 })
  leaveBattle()

  print(fails == 0 and "PASS petal_dance_anim_bug2428" or "FAIL petal_dance_anim_bug2428")
  love.event.quit(fails == 0 and 0 or 1)
end
