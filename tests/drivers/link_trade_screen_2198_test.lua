-- TradeCenter_DrawPartyLists (engine/link/cable_club.asm:635) draws two
--   SHOT_DIR=/tmp/2198 POKEPORT_IDENTITY=red-sep04 \
--   POKEPORT_DRIVER=tests/drivers/link_trade_screen_2198_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/2198"
  local Pokemon = require("src.pokemon.Pokemon")
  local Protocol = require("src.link.Protocol")
  local LinkState = require("src.link.LinkState")
  local Net = require("src.link.Net")
  local Session = require("src.link.Session")

  local function fail(msg)
    U.log("FAIL link_trade_screen_2198:", msg)
    love.event.quit(1)
  end

  U.teleport(game, "PALLET_TOWN", 5, 6, "down")
  U.wait(5)

  local nicked = Pokemon.new(game.data, "CHARMANDER", 12)
  nicked.nickname = "FLUFFY"
  game.save.party = {
    Pokemon.new(game.data, "SANDSHREW", 9),
    nicked,
    Pokemon.new(game.data, "PIDGEY", 7),
  }
  local peerParty = {
    Pokemon.new(game.data, "MACHOKE", 30),
    Pokemon.new(game.data, "RATTATA", 8),
  }

  local trade = Protocol.TradeSession.new(game.data, game.save.party)
  trade:handle({ type = "party", mons = Protocol.packParty(peerParty) })
  if trade.stage ~= "picking" then
    return fail("trade session never reached picking: " .. tostring(trade.stage))
  end

  local ls = LinkState.new(game)
  local mine, theirs = Net.loopbackPair()
  ls.peerTransport = theirs
  ls.net = Session.new(mine, { role = "host", kind = "link" })
  ls.peerName = "MG"
  ls.verdict = "full"
  ls.stage = "trade"
  ls.trade = trade
  ls.index = 1
  ls.theirIndex = 1
  ls.side = "mine"
  game.stack:push(ls)
  U.wait(2)
  if game.stack:top() ~= ls then
    return fail("LinkState left the trade stage on its own")
  end

  U.shot(game, DIR .. "/2198_01_trade_party_lists.png")
  U.log("party lists: side=", ls.side, "index=", ls.index)

  -- engine/link/cable_club.asm:468
  U.tap(game, "a")
  U.wait(2)
  U.shot(game, DIR .. "/2198_02_stats_trade_row.png")
  U.log("pickChoice=", ls.pickChoice)
  U.tap(game, "b")
  U.wait(2)

  -- engine/link/cable_club.asm:537
  for _ = 1, 6 do
    if ls.side == "cancel" then break end
    U.tap(game, "down")
    U.wait(2)
  end
  U.shot(game, DIR .. "/2198_03_cancel_cursor.png")
  U.log("after DOWN past the last mon: side=", ls.side)

  local ok = ls.side == "cancel" and ls:listLabel(game.save.party[1]) == "SANDSHREW"
             and ls:listLabel(nicked) == "CHARMANDER"
  U.log(ok and "PASS link_trade_screen_2198" or "FAIL link_trade_screen_2198")
  love.event.quit(ok and 0 or 1)
end
