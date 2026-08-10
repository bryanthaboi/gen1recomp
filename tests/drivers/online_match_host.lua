-- Driver: play a real online match, hosting side.
--
-- Pair with tests/drivers/online_match_join.lua in a second instance:
--
--   POKEPORT_IDENTITY=pokehost ONLINE_CODE_FILE=/tmp/poke_code.txt \
--     POKEPORT_DRIVER=tests/drivers/online_match_host.lua love .
--   POKEPORT_IDENTITY=pokeguest ONLINE_CODE_FILE=/tmp/poke_code.txt \
--     POKEPORT_DRIVER=tests/drivers/online_match_join.lua love .
--
-- Two real windows, the real relay (POKEPORT_RELAY_ADDR to point elsewhere),
-- the real LinkState menus and the real lockstep battle -- the loopback
-- suites can't see anything the transport, the two separate processes or
-- the two save identities contribute.  The host writes its room code to
-- ONLINE_CODE_FILE for the joiner to pick up, since on a real screen that
-- code is read aloud to a friend.
--
-- Prints ONLINE_MATCH_HOST: lines; the wrapper script greps them.

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local LinkState = require("src.link.LinkState")
  local Runtime = require("src.mods.Runtime")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local CODE_FILE = os.getenv("ONLINE_CODE_FILE") or "/tmp/poke_code.txt"
  local TAG = "ONLINE_MATCH_HOST:"

  local function log(...) U.log(TAG, ...) end

  -- a desync is the whole point of the exercise, so make it loud
  local desyncs = {}
  -- wrap emit rather than subscribing: with no mods loaded Runtime.events is
  -- the null sink, and a vanilla online run is exactly the case under test
  local realEmit = Runtime.emit
  Runtime.emit = function(name, p)
    if name == "link.desync" and p then
      desyncs[#desyncs + 1] = p
      log(("DESYNC turn=%s component=%s fatal=%s"):format(
        tostring(p.turn), tostring(p.component), tostring(p.fatal)))
    end
    return realEmit(name, p)
  end

  game.save.player.name = "HOST"
  game.save.party = {
    Pokemon.new(game.data, "CHARIZARD", 50),
    Pokemon.new(game.data, "SNORLAX", 50),
    Pokemon.new(game.data, "ALAKAZAM", 50),
  }
  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(30)

  local link = LinkState.new(game)
  game.stack:push(link)
  U.wait(10)

  -- the GAME SPEED forcing under test: a link session pins the logic clock
  -- to 1X no matter what the option or POKEPORT_SPEED says. RFC 0007: set
  -- all three per-category speeds high, since the link lock has to win over
  -- every one of them, not just whichever category happens to be active.
  game.save.options.speedOverworld = 10
  game.save.options.speedBattle = 10
  game.save.options.speedMenu = 10
  U.wait(2)
  log("logicSpeed with GAME SPEED=10 during link:", game:logicSpeed())

  -- top menu: LAN / ONLINE MATCH / TOURNAMENT
  U.tap(game, "down"); U.wait(3)
  U.tap(game, "a"); U.wait(5)        -- ONLINE MATCH
  if link.stage ~= "onlineMenu" then
    log("FAIL expected onlineMenu, at", tostring(link.stage))
    -- a mods-enabled build lands on the vanilla-restart prompt instead
    U.wait(60)
    U.shot(game, DIR .. "/online_host_blocked.png")
    return
  end
  U.tap(game, "a"); U.wait(10)       -- HOST ONLINE

  -- wait for the relay to hand back a room code
  local code
  for _ = 1, 900 do
    if link.net and link.net.code then code = link.net.code break end
    U.wait(1)
  end
  if not code then
    log("FAIL no room code from the relay:", tostring(link.net and link.net.error))
    U.shot(game, DIR .. "/online_host_nocode.png")
    return
  end
  log("hosting code", code)
  U.shot(game, DIR .. "/online_host_1_code.png")
  local f = io.open(CODE_FILE, "w")
  if f then f:write(code) f:close() end

  -- wait for the joiner
  for _ = 1, 1800 do
    if link.stage == "modeSelect" then break end
    U.wait(1)
  end
  if link.stage ~= "modeSelect" then
    log("FAIL nobody joined (stage " .. tostring(link.stage) .. ")")
    return
  end
  log("paired with", tostring(link.peerName))
  U.shot(game, DIR .. "/online_host_2_paired.png")

  U.tap(game, "down"); U.wait(3)     -- TRADE / BATTLE -> BATTLE
  U.tap(game, "a"); U.wait(10)
  -- host owns the level rule; ANY is the default row
  for _ = 1, 600 do
    if link.stage == "battleOptions" then break end
    U.wait(1)
  end
  if link.stage == "battleOptions" then
    U.shot(game, DIR .. "/online_host_3_options.png")
    U.tap(game, "a"); U.wait(5)
  end

  -- the battle: mash A, exactly like a player who just wants it over with
  local battle
  for _ = 1, 1800 do
    local top = game.stack:top()
    if top and top.kind == "link" then battle = top break end
    U.wait(1)
  end
  if not battle then
    log("FAIL battle never started (stage " .. tostring(link.stage) .. ")")
    U.shot(game, DIR .. "/online_host_nobattle.png")
    return
  end
  log("battle started vs", tostring(battle.opponentName))
  U.shot(game, DIR .. "/online_host_4_battle.png")

  local shots = 0
  for i = 1, 200000 do
    if battle.result then break end
    U.tap(game, "a")
    if i % 900 == 0 and shots < 3 then
      shots = shots + 1
      U.shot(game, DIR .. ("/online_host_5_turn%d.png"):format(shots))
    end
  end
  U.wait(60)
  U.shot(game, DIR .. "/online_host_6_result.png")
  log("result", tostring(battle.result), "turns", tostring(battle.turnCount))
  log("desyncs", #desyncs)
  log("DONE")
end
