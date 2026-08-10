-- Driver: play a real online match, joining side.
-- See tests/drivers/online_match_host.lua for how to run the pair.

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local LinkState = require("src.link.LinkState")
  local CodeEntry = require("src.link.CodeEntry")
  local Runtime = require("src.mods.Runtime")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local CODE_FILE = os.getenv("ONLINE_CODE_FILE") or "/tmp/poke_code.txt"
  local TAG = "ONLINE_MATCH_JOIN:"

  local function log(...) U.log(TAG, ...) end

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

  game.save.player.name = "GUEST"
  game.save.party = {
    Pokemon.new(game.data, "BLASTOISE", 50),
    Pokemon.new(game.data, "GENGAR", 50),
    Pokemon.new(game.data, "DRAGONITE", 50),
  }
  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(30)

  -- the host writes its room code out once the relay assigns one
  local code
  for _ = 1, 3600 do
    local f = io.open(CODE_FILE, "r")
    if f then
      local text = (f:read("*a") or ""):gsub("%s+", "")
      f:close()
      if #text == CodeEntry.LENGTH then code = text break end
    end
    U.wait(1)
  end
  if not code then
    log("FAIL host never published a code")
    return
  end
  log("joining code", code)

  local link = LinkState.new(game)
  game.stack:push(link)
  U.wait(10)
  -- RFC 0007: set all three per-category speeds high, since the link lock
  -- has to win over every one of them, not just whichever is active.
  game.save.options.speedOverworld = 20
  game.save.options.speedBattle = 20
  game.save.options.speedMenu = 20
  U.wait(2)
  log("logicSpeed with GAME SPEED=20 during link:", game:logicSpeed())

  log("before nav: stage", tostring(link.stage), "index", tostring(link.index),
      "top", tostring(game.stack:top() == link), "mods", #require("src.link.Handshake").mods(game))
  U.tap(game, "down"); U.wait(3)
  log("after down: stage", tostring(link.stage), "index", tostring(link.index))
  U.tap(game, "a"); U.wait(5)        -- ONLINE MATCH
  log("after a: stage", tostring(link.stage), "index", tostring(link.index))
  if link.stage ~= "onlineMenu" then
    log("FAIL expected onlineMenu, at", tostring(link.stage))
    U.wait(60)
    U.shot(game, DIR .. "/online_join_blocked.png")
    return
  end
  U.tap(game, "down"); U.wait(3)
  U.tap(game, "a"); U.wait(5)        -- JOIN ONLINE -> code entry
  if link.stage ~= "codeEntry" then
    log("FAIL expected codeEntry, at", tostring(link.stage))
    return
  end
  -- set the six slots straight rather than scrubbing each one with UP
  -- presses; the scrub interaction has its own coverage (online_play_test)
  for i = 1, CodeEntry.LENGTH do
    local idx = CodeEntry.CHARSET:find(code:sub(i, i), 1, true)
    link.codeEntry.chars[i] = idx or 1
  end
  U.wait(2)
  U.shot(game, DIR .. "/online_join_1_code.png")
  U.tap(game, "a"); U.wait(10)

  for _ = 1, 1800 do
    if link.stage == "waitMode" or link.stage == "battleWait" then break end
    if link.net and link.net.error then
      log("FAIL join error:", tostring(link.net.error))
      return
    end
    U.wait(1)
  end
  log("connected, stage", tostring(link.stage))
  U.shot(game, DIR .. "/online_join_2_connected.png")

  local battle
  for _ = 1, 1800 do
    local top = game.stack:top()
    if top and top.kind == "link" then battle = top break end
    U.wait(1)
  end
  if not battle then
    log("FAIL battle never started (stage " .. tostring(link.stage) .. ")")
    U.shot(game, DIR .. "/online_join_nobattle.png")
    return
  end
  log("battle started vs", tostring(battle.opponentName))
  U.shot(game, DIR .. "/online_join_3_battle.png")

  local shots = 0
  for i = 1, 200000 do
    if battle.result then break end
    U.tap(game, "a")
    if i % 900 == 0 and shots < 3 then
      shots = shots + 1
      U.shot(game, DIR .. ("/online_join_4_turn%d.png"):format(shots))
    end
  end
  U.wait(60)
  U.shot(game, DIR .. "/online_join_5_result.png")
  log("result", tostring(battle.result), "turns", tostring(battle.turnCount))
  log("desyncs", #desyncs)
  log("DONE")
end
