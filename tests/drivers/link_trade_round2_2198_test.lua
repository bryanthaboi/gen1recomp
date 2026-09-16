-- TradeCenter_Trade .tradeCompleted (engine/link/cable_club.asm:870) saves,
--   SHOT_DIR=/tmp/2198 POKEPORT_IDENTITY=red-sep04 \
--   POKEPORT_DRIVER=tests/drivers/link_trade_round2_2198_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/2198"
  local Pokemon = require("src.pokemon.Pokemon")
  local Protocol = require("src.link.Protocol")
  local LinkState = require("src.link.LinkState")
  local Net = require("src.link.Net")
  local Session = require("src.link.Session")
  local TextBox = require("src.render.TextBox")
  local TradeAnim = require("src.ui.TradeAnim")

  local function fail(msg)
    U.log("FAIL link_trade_round2_2198:", msg)
    love.event.quit(1)
  end

  U.teleport(game, "PALLET_TOWN", 5, 6, "down")
  U.wait(5)

  game.save.party = {
    Pokemon.new(game.data, "SANDSHREW", 9),
    Pokemon.new(game.data, "PIDGEY", 7),
  }
  local peerParty = {
    Pokemon.new(game.data, "RATTATA", 8),
    Pokemon.new(game.data, "EKANS", 9),
  }

  local mine, theirs = Net.loopbackPair()
  local ls = LinkState.new(game)
  ls.net = Session.new(mine, { role = "host", kind = "link" })
  ls.peerName = "MG"
  ls.verdict = "full"
  ls.stage = "trade"
  ls.index, ls.theirIndex, ls.side = 1, 1, "mine"
  ls.trade = Protocol.TradeSession.new(game.data, game.save.party,
                                       { peerName = "MG" })
  ls.net:send(ls.trade:opening())
  game.stack:push(ls)

  local peerTrade = Protocol.TradeSession.new(game.data, peerParty,
                                              { peerName = "RED" })
  theirs:send(peerTrade:opening())
  local peerPicked, peerConfirmed = false, false
  local peerRounds = 1

  local function pumpPeer()
    theirs:update()
    for _, msg in ipairs(theirs:poll()) do
      local reply = peerTrade:handle(msg)
      if reply then theirs:send(reply) end
    end
    if peerTrade.stage == "picking" and not peerPicked then
      peerPicked = true
      theirs:send(peerTrade:pick(1))
    elseif peerTrade.stage == "confirming" and not peerConfirmed then
      peerConfirmed = true
      theirs:send(peerTrade:confirm(true))
    elseif peerTrade.stage == "done" then
      peerTrade:apply(nil)
      peerRounds = peerRounds + 1
      peerPicked, peerConfirmed = false, false
      peerTrade = Protocol.TradeSession.new(game.data, peerParty,
                                            { peerName = "RED" })
      theirs:send(peerTrade:opening())
    end
  end

  local firstTrade = ls.trade
  local ourPicked, ourConfirmed = false, false
  local function ourStep()
    if game.stack:top() ~= ls or ls.stage ~= "trade" then return end
    local t = ls.trade
    if t.stage == "picking" and not ourPicked then
      ourPicked = true
      ls.net:send(t:pick(1))
    elseif t.stage == "confirming" and not ourConfirmed then
      ourConfirmed = true
      ls.confirmed = true
      ls.net:send(t:confirm(true))
    end
  end

  local sawAnim = false
  local reached = false
  for _ = 1, 6000 do
    pumpPeer()
    local top = game.stack:top()
    if getmetatable(top) == TradeAnim then
      sawAnim = true
      U.tap(game, "start") -- engine/movie/trade.asm:20 skip
    elseif getmetatable(top) == TextBox then
      U.tap(game, "a")
    elseif top == ls then
      ourStep()
      if ls.trade ~= firstTrade and ls.trade.stage == "picking" then
        reached = true
        break
      end
    elseif top == game.overworld then
      return fail("LinkState was torn down after the first trade")
    end
    U.wait(1)
  end

  if not sawAnim then return fail("the trade cinematic never ran") end
  if not reached then
    return fail("round 2 never reached picking (trade stage "
                .. tostring(ls.trade and ls.trade.stage) .. ")")
  end

  U.shot(game, DIR .. "/2198_04_round2_select.png")
  U.log("round 2: stage=", ls.trade.stage,
        "party=", game.save.party[1] and game.save.party[1].species,
        "theirs=", (ls.trade.theirParty or {})[1] and ls.trade.theirParty[1].species,
        "session=", ls.net:getStatus(), "peerRounds=", peerRounds)

  local ok = game.stack:top() == ls
         and game.save.party[1] and game.save.party[1].species == "RATTATA"
         and ls.net:getStatus() ~= "closed"
         and (ls.trade.theirParty or {})[1] ~= nil
         and ls.trade.theirParty[1].species == "SANDSHREW"
         and peerRounds == 2
  U.log(ok and "PASS link_trade_round2_2198" or "FAIL link_trade_round2_2198")
  ls.net:close()
  love.event.quit(ok and 0 or 1)
end
