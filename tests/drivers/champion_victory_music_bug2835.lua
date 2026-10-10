-- engine/battle/core.asm:928
-- scripts/ChampionsRoom.asm:112
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local Pokemon = require("src.pokemon.Pokemon")
  local Music = require("src.core.Music")
  local BattleState = require("src.battle.BattleState")
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')

  local failed = false
  local function check(label, ok)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failed = true end
    return ok
  end

  U.newGame(game)
  local mon = Pokemon.new(game.data, "MEWTWO", 100)
  mon.moves = { { id = "SWIFT", pp = 20, maxPp = 20, ppUps = 0 } }
  game.save.party = { mon }
  game.save.player.name = "RED"

  local realNewTrainer = BattleState.newTrainer
  local battle
  BattleState.newTrainer = function(...)
    local b = realNewTrainer(...)
    for _, m in ipairs(b.enemyParty or {}) do m.hp = 1 end
    battle = b
    return b
  end

  U.teleport(game, "CHAMPIONS_ROOM", 4, 3, "up")
  U.wait(20)
  local ow = game.overworld
  check("overworld up in CHAMPIONS_ROOM", ow ~= nil and ow.map.id == "CHAMPIONS_ROOM")
  if not ow then love.event.quit(1) return end
  local rival
  for _, npc in ipairs(ow.npcs or {}) do
    if npc.def and npc.def.name == "CHAMPIONSROOM_RIVAL" then rival = npc end
  end
  local rows = require("data.scripts.init").get("CHAMPIONS_ROOM").talk.TEXT_CHAMPIONSROOM_RIVAL
  ow:queueScript(rows, { npc = rival })

  for _ = 1, 3000 do
    if battle and game.stack:top() == battle then break end
    U.tap(game, "a")
    U.wait(4)
  end
  check("rival battle on screen", battle ~= nil and game.stack:top() == battle)
  check("rival battle is the final battle", battle and battle.musicKind == "final")

  local b = game.data.audio and game.data.audio.battle or {}
  local gymWin = b.gymWin
  for _ = 1, 4000 do
    if battle and game.stack:top() ~= battle and battle.result then break end
    U.tap(game, "a")
    U.wait(6)
  end
  BattleState.newTrainer = realNewTrainer
  check("rival defeated", battle and battle.result == "win")

  local cues = {}
  local realPlay = Music.play
  Music.play = function(data, song, loop, ctx)
    cues[#cues + 1] = song
    return realPlay(data, song, loop, ctx)
  end

  U.wait(10)
  check("battle screen closed", game.stack:top() ~= battle)
  check("MUSIC_DEFEATED_GYM_LEADER still playing after the battle screen closes",
        gymWin ~= nil and Music.current() == gymWin)
  U.still(game, DIR .. "/2835_01_after_battle_victory_theme.png")

  local sawCities, between = false, {}
  for _ = 1, 3000 do
    if Music.current() == "Music_Cities1" then sawCities = true break end
    U.tap(game, "a")
    U.wait(4)
  end
  Music.play = realPlay
  for _, s in ipairs(cues) do
    if s == "Music_Cities1" then break end
    between[#between + 1] = s
  end
  check("Oak's arrival switches to Cities1", sawCities)
  check("no map theme cue between the battle and Oak's arrival (got "
        .. table.concat(between, ",") .. ")", #between == 0)
  U.still(game, DIR .. "/2835_02_oak_arrives_cities1.png")

  love.event.quit(failed and 1 or 0)
end
