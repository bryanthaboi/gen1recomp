-- pokeyellow scripts/OaksLab.asm:340-364, engine/battle/core.asm:947-958.
--
--   POKEPORT_DRIVER=tests/drivers/oak_rival_loss_line_2121_test.lua POKEPORT_VERSION=yellow love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local GameVersion = require("src.core.GameVersion")
  local Commands = require("src.script.Commands")
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")

  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local LAB = "OAKS_LAB"
  local GIFT = { x = 5, y = 3 }
  local LOSS_ID = "_OaksLabRivalIPickedTheWrongPokemonText"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end
  local function idle()
    while true do coroutine.yield() end
  end
  local function ow() return game.overworld end
  local function ctx()
    return { game = game, save = game.save, overworld = game.overworld }
  end
  local function oneline(s)
    return (tostring(s):gsub("[\n\v]", " / "))
  end

  local function stepOnce(dir)
    local p = ow().player
    local x0, y0 = p.cellX, p.cellY
    for _ = 1, 60 do
      table.insert(game.input.pressQueue, dir)
      game.input.state[dir] = true
      coroutine.yield()
      p = ow().player
      if p.cellX ~= x0 or p.cellY ~= y0 then break end
    end
    game.input.state[dir] = false
    for _ = 1, 40 do
      if not ow().player.moving then break end
      U.wait(1)
    end
    U.wait(3)
    p = ow().player
    return p.cellX ~= x0 or p.cellY ~= y0
  end

  if not check("running the Yellow cache (POKEPORT_VERSION=yellow)",
               GameVersion.isYellow()) then
    idle()
  end

  local expected = game.data.text and game.data.text[LOSS_ID]
  check("the Yellow cache carries " .. LOSS_ID, type(expected) == "string")
  if expected then U.log("cache text:", oneline(expected)) end

  game.save.flags = game.save.flags or {}
  local flags = game.save.flags
  flags.EVENT_GOT_STARTER = true
  flags.EVENT_CHOSE_PIKACHU = true
  flags.EVENT_FOLLOWED_OAK_INTO_LAB = true
  flags.EVENT_FOLLOWED_OAK_INTO_LAB_2 = true
  flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = nil
  flags.EVENT_OAK_ASKED_TO_CHOOSE_MON = true
  flags.EVENT_GOT_POKEDEX = nil
  flags.EVENT_OAK_GOT_PARCEL = nil
  game.save.party = { Pokemon.new(game.data, "PIKACHU", 30) }
  game.save.player.name = "bryan"
  game.save.onBike = false
  game.save.pikachuInBall = true

  U.teleport(game, LAB, GIFT.x, GIFT.y, "up")
  U.wait(10)
  Commands.show_object(ctx(), LAB, "OAKSLAB_OAK1")
  Commands.show_object(ctx(), LAB, "OAKSLAB_RIVAL")
  U.wait(5)

  for _ = 1, 10 do
    if ow().player.cellY >= 6 then break end
    if not stepOnce("down") then
      if not stepOnce("left") then break end
    end
  end
  check("reached the row the rival challenges from", ow().player.cellY >= 6)

  local sawBattle, armed = false, nil
  local sawDefeated, sawLoss, sawMoney = nil, nil, nil
  local lossText, lossShot = nil, false
  local lastText = nil
  for _ = 1, 4000 do
    local o = game.overworld
    local top = game.stack:top()
    if top ~= o then
      if getmetatable(top) == BattleState then
        if not sawBattle then
          sawBattle = true
          armed = top.endBattleText
          U.log("battle pushed; endBattleText:", oneline(armed))
        end
        local cur = top.current
        local text = cur and cur.text
        if text and text ~= lastText then
          lastText = text
          if text:find("defeated", 1, true) then sawDefeated = U.frame() end
          if text:find("WHAT?", 1, true) and text:find("Unbelievable", 1, true) then
            sawLoss = U.frame()
            lossText = text
          end
          if text:find("for winning", 1, true) then sawMoney = U.frame() end
        end
        if text == lossText and lossText and not lossShot
           and top.charIndex and top.total and top.charIndex >= top.total then
          lossShot = true
          U.wait(2)
          U.shot(game, SHOT_DIR .. "/bug2121_loss_line.png")
          U.log("captured", SHOT_DIR .. "/bug2121_loss_line.png")
          U.wait(6)
        end
      end
      U.tap(game, "a")
      U.wait(3)
    else
      if sawBattle and not o.runner:isRunning() and #o.scriptMoves == 0 then
        break
      end
      U.wait(2)
    end
  end

  check("the rival battle actually ran", sawBattle)
  check("the battle was armed with the loss line",
        type(armed) == "string" and armed ~= ""
        and armed:find("Unbelievable", 1, true) ~= nil)
  check("the battle result is a win", flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB == true
        and game.save.rivalStarter == 2)
  check("\"<PLAYER> defeated <RIVAL>!\" printed", sawDefeated ~= nil)
  check("the rival's loss line printed on the battle screen", sawLoss ~= nil)
  if lossText then
    U.log("loss line:", oneline(lossText))
    local rival = game.save.player.rival
    check("it opens with the rival's name tag",
          type(rival) == "string" and lossText:sub(1, #rival + 2) == rival .. ": ")
    check("its body is the cache text",
          expected ~= nil and lossText:find(expected, 1, true) ~= nil)
  end
  check("\"got ¥ for winning!\" printed", sawMoney ~= nil)
  check("the loss line sits between defeated and the money line",
        sawDefeated and sawLoss and sawMoney
        and sawDefeated < sawLoss and sawLoss < sawMoney)
  check("the loss line was screenshotted", lossShot)

  U.log("bug2121_loss_line.png: the rival pic scrolled back in, the box")
  U.log("reads \"<RIVAL>: WHAT? / Unbelievable!\" and the money line has")
  U.log("not printed yet.  Red/Blue show the same box in the same spot.")
  idle()
end
