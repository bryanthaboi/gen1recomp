-- ../pokecrystal/data/moves/animations.asm:3245
-- ../pokecrystal/engine/battle_anims/bg_effects.asm:2480-2519
-- ../pokecrystal/engine/battle/effect_commands.asm:6650
local U = require("tests.drivers.util")

local Mon = require("src.battle.gen2.Mon")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/crystal-curse-anim-2140"
  os.execute('mkdir -p "' .. out .. '" 2>/dev/null')
  local fails = 0
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print("[curse-2140] " .. (cond and "PASS " or "FAIL ") .. line)
  end

  U.wait(45)
  local world = game.world
  assert(world and world.map, "the crystal world did not boot")

  local function movingUp(anim)
    local structs = anim and anim.objects and anim.objects.structs
    for _, obj in ipairs(structs or {}) do
      if obj.index ~= 0 and obj.func == "BATTLE_ANIM_FUNC_MOVE_UP" then
        return true
      end
    end
    return false
  end

  local function effectNames(anim)
    local names = {}
    for _, st in ipairs((anim and anim.bg and anim.bg.effects) or {}) do
      if st.func then names[#names + 1] = tostring(st.func) end
    end
    return table.concat(names, ",")
  end

  local function fight(leadSpecies, leadMove, wildSpecies, wildMove, tag)
    local lead = Mon.new(game.data, leadSpecies, 42)
    assert(lead, "could not build a " .. leadSpecies)
    lead.moves = { { id = leadMove, pp = 10, maxPp = 10 } }
    game.save.party = { lead }
    game.save.inventory = { POKE_BALL = 5 }

    local wild = Mon.new(game.data, wildSpecies, 40)
    assert(wild, "could not build a wild " .. wildSpecies)
    wild.moves = { { id = wildMove, pp = 10, maxPp = 10 } }

    assert(world:startBattle({ wild = wild }), "startBattle failed")
    local screen
    for _ = 1, 600 do
      local top = game.stack:top()
      if top and top.battle then screen = top break end
      U.wait(1)
    end
    assert(screen and screen.battle, "battle screen never came up")

    for _ = 1, 900 do
      if screen.phase == "menu" then break end
      U.tap(game, "a")
      U.wait(2)
    end
    ok(screen.phase == "menu", tag .. ": reached the battle menu")
    U.tap(game, "a")
    U.wait(4)
    U.tap(game, "a")

    local log = {
      streaksWithShade = 0, streaksWithoutShade = 0,
      playerShaded = 0, enemyShaded = 0,
      hideAfter = 0, shakeAfter = 0, wobbleAfter = 0, statDownAfter = 0,
    }
    local sawMoveAnim, moveAnimOver = false, false
    for tick = 1, 400 do
      local anim = screen.anim
      if anim and anim.bg then
        local shadeP = anim.bg.monShade and anim.bg.monShade.player
        local shadeE = anim.bg.monShade and anim.bg.monShade.enemy
        if anim.clearsHud then
          sawMoveAnim = true
          if shadeP and shadeP ~= 0xe4 then log.playerShaded = log.playerShaded + 1 end
          if shadeE and shadeE ~= 0xe4 then log.enemyShaded = log.enemyShaded + 1 end
          if movingUp(anim) then
            local userShade = (anim.env and anim.env.battleTurn == 0)
              and shadeP or shadeE
            if userShade ~= 0xe4 then
              log.streaksWithShade = log.streaksWithShade + 1
            elseif log.streaksWithShade > 0 then
              log.streaksWithoutShade = log.streaksWithoutShade + 1
            end
          end
        elseif sawMoveAnim then
          moveAnimOver = true
          local id = anim.animId or ""
          if id == "ANIM_ENEMY_DAMAGE" then log.hideAfter = log.hideAfter + 1 end
          if id == "ANIM_PLAYER_DAMAGE" then log.shakeAfter = log.shakeAfter + 1 end
          if id == "ANIM_WOBBLE" then log.wobbleAfter = log.wobbleAfter + 1 end
          if id == "ANIM_ENEMY_STAT_DOWN" then
            log.statDownAfter = log.statDownAfter + 1
          end
        end
      elseif sawMoveAnim then
        moveAnimOver = true
      end
      if tick % 10 == 0 then
        U.shot(game, ("%s/%s-t%03d.png"):format(out, tag, tick))
      end
      if moveAnimOver and screen.phase == "menu" then break end
      if (screen.messageTimer or 0) > 0 then U.tap(game, "a") end
      U.wait(1)
    end
    ok(sawMoveAnim, tag .. ": a move animation ran")
    return screen, log
  end

  local function endBattle(screen)
    for _ = 1, 900 do
      if game.stack:top() ~= screen then break end
      screen.battle.enemy.hp = 0
      U.tap(game, "a")
      U.wait(2)
    end
  end

  local screen, log = fight("SNORLAX", "CURSE", "HITMONLEE", "SPLASH", "snorlax")
  ok(log.streaksWithShade > 0 and log.streaksWithoutShade == 0,
    ("snorlax: user stays shaded once the ramp lands (%d shaded, %d flicker)")
      :format(log.streaksWithShade, log.streaksWithoutShade))
  ok(log.enemyShaded == 0, "snorlax: the enemy's mon is never shaded")
  ok(log.hideAfter == 0 and log.shakeAfter == 0,
    "snorlax: no damage blink / shake chained after Curse")
  endBattle(screen)

  local screen2, log2 = fight("HITMONLEE", "SPLASH", "SNORLAX", "CURSE", "enemy-curse")
  ok(log2.enemyShaded > 0, "enemy curse: the enemy's own mon is shaded")
  ok(log2.playerShaded == 0, "enemy curse: the player's mon is never shaded")
  ok(log2.hideAfter == 0 and log2.shakeAfter == 0,
    "enemy curse / player splash: no blink or shake chained")
  endBattle(screen2)

  local screen3, log3 = fight("SNORLAX", "GROWL", "HITMONLEE", "SPLASH", "growl")
  ok(log3.statDownAfter > 0, "growl: ANIM_ENEMY_STAT_DOWN follows the move")
  ok(log3.hideAfter == 0, "growl: not the damage blink")
  endBattle(screen3)

  local screen4, log4 = fight("SNORLAX", "TACKLE", "HITMONLEE", "SPLASH", "tackle")
  ok(log4.hideAfter > 0, "tackle: ANIM_ENEMY_DAMAGE still follows a hit")
  endBattle(screen4)

  print("[curse-2140] " .. (fails == 0 and "PASS all claims" or
    (fails .. " claims failed")) .. " -- shots in " .. out)
  love.event.quit(fails == 0 and 0 or 1)
end
