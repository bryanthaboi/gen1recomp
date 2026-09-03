--   POKEPORT_IDENTITY=crystal-2134 POKEPORT_VERSION=crystal \
--     POKEPORT_DRIVER=tests/drivers/crystal_sendout_name_bug2134.lua \
--     POKEPORT_SHOT_DIR=/tmp/c2134 love .
-- ../pokecrystal/data/text/battle.asm:240-246
-- ../pokecrystal/engine/battle/core.asm:3146-3147
-- ../pokecrystal/home/text.asm:502-526
local U = require("tests.drivers.util")

local Mon = require("src.battle.gen2.Mon")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/c2134"
  local fails = 0
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    print("[sendout-2134] " .. (cond and "PASS " or "FAIL ") .. line)
  end
  local function lines(screen)
    return table.concat(screen:messageLines(), "|")
  end
  local function sendStarted(screen)
    return screen.afterSendOut ~= nil or screen.showEnemyHud == true
  end

  U.wait(45)
  local world = game.world
  assert(world and world.map, "the crystal world did not boot")

  local lead = Mon.new(game.data, "DRAGONITE", 47)
  assert(lead and #lead.moves > 0, "could not build a DRAGONITE")
  for i, move in ipairs(lead.moves) do
    local def = game.data.moves[move.id]
    if def and (def.power or 0) > 0 then
      table.remove(lead.moves, i)
      table.insert(lead.moves, 1, move)
      break
    end
  end
  game.save.party = { lead }
  game.save.inventory = { POKE_BALL = 5 }
  local trainer = {
    class = 16, classId = "CHAMPION", memberId = "LANCE",
    name = "CHAMPION LANCE", trainerName = "LANCE", className = "CHAMPION",
    party = { Mon.new(game.data, "GYARADOS", 44),
      Mon.new(game.data, "DRAGONITE", 61) },
    baseMoney = 25,
  }
  assert(world:startBattle({ trainer = trainer }), "startBattle failed")
  local screen
  for _ = 1, 600 do
    local top = game.stack:top()
    if top and top.battle then screen = top break end
    U.wait(1)
  end
  assert(screen and screen.battle, "battle screen never came up")

  local function settle()
    for _ = 1, 600 do
      if screen.typer and screen.typer:done() then return true end
      U.wait(1)
    end
    return false
  end

  local function awaitSendOut(name, tag)
    for _ = 1, 2400 do
      local m = screen.message
      if m and m:find("sent out", 1, true) and screen.messagePages then
        settle()
        local first = lines(screen)
        ok(first == "CHAMPION LANCE|sent out",
          tag .. " page 1 reads CHAMPION LANCE / sent out: " .. first)
        ok(not sendStarted(screen) and screen.pendingSendOut ~= nil,
          tag .. " the ball is still shut on page 1")
        U.shot(game, out .. "/" .. tag .. "-page1.png")
        U.tap(game, "a")
        U.wait(2)
        local early = screen:messageLines()
        ok(early[1] == "sent out",
          tag .. " 'sent out' is already on row 1 of page 2")
        settle()
        local second = lines(screen)
        ok(second == "sent out|" .. name .. "!",
          tag .. " page 2 reads sent out / " .. name .. "!: " .. second)
        ok(sendStarted(screen), tag .. " ANIM_SEND_OUT_MON runs with page 2")
        U.shot(game, out .. "/" .. tag .. "-page2.png")
        return true
      end
      if screen.phase == "menu" then
        if screen.battle.enemyIndex == 1
            and (screen.battle.enemy.hp or 0) > 1 then
          screen.battle.enemy.hp = 1
          screen.battle.enemy.moves = {}
          screen.battle.enemy.status = false
        end
        U.tap(game, "a")
        U.wait(2)
        U.tap(game, "a")
        U.wait(2)
      elseif (screen.messageTimer or 0) > 0 and screen.typer
          and screen.typer:done() then
        U.tap(game, "a")
      end
      U.wait(1)
    end
    ok(false, tag .. " send-out line never came up")
    return false
  end

  awaitSendOut("GYARADOS", "intro")
  awaitSendOut("DRAGONITE", "replacement")

  print("[sendout-2134] " .. (fails == 0 and "PASS all claims" or
    (fails .. " claims failed")) .. " -- shots in " .. out)
  love.event.quit(fails == 0 and 0 or 1)
end
