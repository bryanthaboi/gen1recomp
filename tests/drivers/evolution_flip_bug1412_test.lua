return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/bug1412"
  local Pokemon = require("src.pokemon.Pokemon")
  local Evolution = require("src.pokemon.Evolution")
  local Screens = require("src.ui.Screens")
  local TradeAnim = require("src.ui.TradeAnim")
  local TextBox = require("src.render.TextBox")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  U.log("Issue #1412: mon pics must be mirrored on the evolution and trade")
  U.log("screens, and only there; battle keeps the raw orientation.")

  U.teleport(game, "ROUTE_1", 5, 5, "down")
  U.wait(10)
  check("the overworld fixture is ready", game.overworld ~= nil)

  local mon = Pokemon.new(game.data, "PIKACHU", 20)
  game.save.party = { mon }
  -- engine/movie/evolution.asm:103
  Evolution.evolve(game, mon, "RAICHU", nil, "ITEM")
  U.wait(12)
  local top = game.stack:top()
  check("the evolution screen opened",
        top and top.screenId == "EvolutionState")
  U.shot(game, DIR .. "/bug1412_evo_old_pikachu.png")

  for _ = 1, 600 do
    if top.done then break end
    U.wait(1)
  end
  check("the evolution finished", top.done and not top.canceled)
  U.wait(2)
  U.shot(game, DIR .. "/bug1412_evo_new_raichu.png")
  for _ = 1, 60 do
    if game.stack:top() == game.overworld then break end
    U.tap(game, "a")
    U.wait(4)
  end

  -- engine/movie/trade.asm:751
  local sent = Pokemon.new(game.data, "SPEAROW", 10)
  local recv = Pokemon.new(game.data, "FARFETCHD", 10)
  recv.nickname = "DUX"
  recv.traded = true
  recv.ot = "TRAINER"
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  local anim = Screens.push(game, "TradeAnim", {
    sent = sent, received = recv, enemyName = "TRAINER",
  })
  check("the trade cinematic opened", getmetatable(anim) == TradeAnim)
  for _ = 1, 200 do
    if anim.sub == "hold" then break end
    U.wait(1)
  end
  check("the sent SPEAROW pic is on screen",
        anim.phase == "show_player" and anim.sub == "hold" and anim.monVisible)
  U.shot(game, DIR .. "/bug1412_trade_sent_spearow.png")

  local function topIsText()
    return getmetatable(game.stack:top()) == TextBox
  end
  for _ = 1, 8000 do
    if anim.phase == "show_enemy" and anim.monVisible then break end
    if anim.phase == "done" then break end
    if anim.waitingText or topIsText() then
      U.wait(1)
    else
      anim:update(1 / 60)
    end
  end
  U.wait(2)
  check("the received FARFETCH'D pic is on screen",
        anim.phase == "show_enemy" and anim.monVisible)
  U.shot(game, DIR .. "/bug1412_trade_recv_farfetchd.png")

  U.log("shots in", DIR)
  U.log("Right: all four pics are mirrored left-right compared to the same")
  U.log("mon's battle front sprite (compare the hardware capture on #1412:")
  U.log("PIKACHU's face points the other way than it does in battle).")
  U.log("Wrong: any of the four matches the battle orientation.")
  U.log("Battle, pokedex, title, Hall of Fame, League PC, credits, and the")
  U.log("museum fossils are untouched and must still match the cart.")

  while true do
    coroutine.yield()
  end
end
