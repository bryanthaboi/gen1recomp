-- engine/items/item_effects.asm:558-566
-- engine/items/item_effects.asm:2737-2740
-- data/text/text_6.asm:37-42

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local dir = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gen1_transferred_nickname"
  local BattleState = require("src.battle.BattleState")
  local NamingScreen = require("src.ui.NamingScreen")
  local Pokemon = require("src.pokemon.Pokemon")
  local failures = 0
  local function check(ok, label, detail)
    print((ok and "PASS " or "FAIL ") .. label .. (detail and (" " .. tostring(detail)) or ""))
    if not ok then failures = failures + 1 end
  end
  local function finish()
    print((failures == 0 and "PASS" or "FAIL") .. " gen1_transferred_nickname failures=" .. failures)
    love.event.quit(failures == 0 and 0 or 1)
    while true do U.wait(10) end
  end

  U.wait(30)
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  local ow = game.overworld
  game.save.party = {}
  for _ = 1, 6 do table.insert(game.save.party, Pokemon.new(game.data, "RATTATA", 5)) end
  game.save.pokedex = game.save.pokedex or { owned = {}, seen = {} }
  game.save.pokedex.owned.PIDGEY = true
  game.save.pokedex.seen.PIDGEY = true
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_MET_BILL = true

  local battle = BattleState.newWild(game, "PIDGEY", 8)
  battle.onFinish = function() end
  battle.rng = function(a) return a end
  ow:pushBattle(battle)
  for _ = 1, 14 do U.tap(game, "a"); U.wait(6) end
  battle.phase = "messages"
  battle.afterQueue = "menu"
  battle:throwBall("POKE_BALL")

  local named, pcText = false, nil
  for _ = 1, 1500 do
    local top = game.stack:top()
    if top == ow then break end
    if getmetatable(top) == NamingScreen and not named then
      named = true
      U.wait(20)
      top.glyphs = { "S", "P", "A", "R", "K", "Y" }
      U.wait(5)
      U.still(game, dir .. "/p5g1_01_naming_sparky.png")
      top:confirm()
    end
    local cur = battle.current
    local text = cur and cur.text
    if not pcText and type(text) == "string" and text:find("transferred", 1, true) then
      pcText = text:gsub("[\n\v]", " ")
      U.wait(90)
      U.still(game, dir .. "/p5g1_02_transferred_sparky.png")
    end
    U.tap(game, "a")
    U.wait(3)
  end
  check(named, "naming screen opened and SPARKY typed")
  local nick
  for _, box in pairs(game.save.boxes or {}) do
    for _, mon in ipairs(box) do if mon.species == "PIDGEY" then nick = mon.nickname end end
  end
  check(nick == "SPARKY", "boxed PIDGEY nickname is SPARKY", nick)
  check(pcText ~= nil and pcText:find("SPARKY was", 1, true) == 1,
    "_ItemUseBallText07 names wBoxMonNicks", pcText)
  finish()
end
