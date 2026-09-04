-- (EnemySendOutFirstMon, engine/battle/core.asm:1432-1435)
-- WaitForSoundToFinish, home/pokemon.asm:145-149
--   POKEPORT_DRIVER=tests/drivers/battle_hud_after_cry_bug2118_test.lua POKEPORT_IDENTITY=bug2118 SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local Font = require("src.render.Font")

  local LOG = DIR .. "/bug2118.log"
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
  local function note(...)
    U.log(...)
    local f = io.open(LOG, "a")
    if not f then return end
    f:write(table.concat({ ... }, " "), "\n")
    f:close()
  end

  local function check(label, ok)
    note(ok and "PASS" or "FAIL", label)
    return ok
  end

  local function hudStrings(battle)
    local strings = {}
    local realFont, realDraw = Font.draw, love.graphics.draw
    Font.draw = function(text) strings[#strings + 1] = tostring(text) end
    love.graphics.draw = function() end
    pcall(battle.drawHUDs, battle, 0)
    Font.draw, love.graphics.draw = realFont, realDraw
    return strings
  end

  local function drew(strings, want)
    for _, s in ipairs(strings) do
      if s:find(want, 1, true) then return true end
    end
    return false
  end

  game.save.party = {
    Pokemon.new(game.data, "BULBASAUR", 12),
    Pokemon.new(game.data, "PIDGEY", 9),
  }
  U.teleport(game, "ROUTE_3", 13, 6, "left")
  U.wait(10)
  local ow = game.overworld
  check("the overworld is up", ow ~= nil)

  local battle = BattleState.newTrainer(game, "OPP_BUG_CATCHER", 4)
  battle.onFinish = function() end
  if ow then ow:pushBattle(battle) end
  for _ = 1, 600 do
    if game.stack:top() == battle and (battle.introSlide or 0) == 0 then break end
    U.wait(1)
  end
  check("the trainer battle reached the screen", game.stack:top() == battle)

  local grew = false
  for _ = 1, 900 do
    if battle.growIn then grew = true break end
    U.tap(game, "a")
    U.wait(4)
  end
  check("AnimateSendingOutMon started", grew)

  for _ = 1, 240 do
    if not battle.growIn then break end
    U.wait(1)
  end
  check("the grow-in finished", battle.growIn == nil)
  check("the cry is still outstanding (enemyHudPending)",
        battle.enemyHudPending == true)
  check("the enemy name is NOT on screen yet",
        not drew(hudStrings(battle), battle.enemy.name))
  U.shot(game, DIR .. "/bug2118_1_sprite_no_hud.png")

  for _ = 1, 900 do
    if not battle.enemyHudPending then break end
    U.wait(1)
  end
  check("the cry finished and the HUD was released",
        battle.enemyHudPending == nil)
  U.wait(2)
  check("the enemy name and HP bar are on screen now",
        drew(hudStrings(battle), battle.enemy.name))
  U.shot(game, DIR .. "/bug2118_2_hud_after_cry.png")

  U.log("Correct: the foe's pic grows out of its ball with the top-left of the")
  U.log("screen still blank, the cry plays in full, and only then do the name,")
  U.log("<LV> and HP bar appear together (#2118).")
  U.log("Screenshots: " .. DIR .. "/bug2118_*.png")

  while true do
    coroutine.yield()
  end
end
