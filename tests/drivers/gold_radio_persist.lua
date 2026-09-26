-- Assertion driver: the Pokegear radio's song outlives the gear, and the
-- Vermilion Snorlax hears it.
--
--   POKEPORT_GAME=gold POKEPORT_IDENTITY=gold-dev \
--     POKEPORT_DRIVER=tests/drivers/gold_radio_persist.lua love .
--
-- The chain under test, all through the real screens: engine flags written by
-- World:setEngineFlag (the store every granting script's `setflag` lands in)
-- unlock the START menu's POKeGEAR row and the gear's cards; the radio card
-- tunes 20.0 to the POKe FLUTE channel (Kanto + ENGINE_EXPN_CARD); closing
-- the gear leaves the song playing as the map music
-- (ExitPokegearRadio_HandleMusic / RadioMusicRestartDE); and `special
-- SnorlaxAwake` then reads that very song and starts the BATTLETYPE_FORCEITEM
-- Snorlax fight.
local U = require("tests.drivers.util")

local function run(game)
  U.wait(45)
  local world = game.world
  assert(world and world.map, "gold world did not boot")
  local Music = require("src.core.Music")

  -- A party to fight with; the unlock flags go through the same store every
  -- granting script's `setflag` writes.
  local save = game.save
  save.party = { {
    species = "TYPHLOSION", name = "TYPHLOSION", nickname = "TYPHLOSION",
    level = 60, hp = 180, maxHp = 180,
    moves = { { id = "FLAMETHROWER", pp = 15, maxPp = 15 } },
  } }
  for _, flag in ipairs({ 0, 1, 2, 3, 4, 11 }) do
    world:setEngineFlag(flag, true)
  end

  -- Beside the sleeping Snorlax: (33,8) is one of SnorlaxAwake's own
  -- .ProximityCoords, and facing right reaches the doll's object cell (34,8).
  world:warpToMapId("VERMILION_CITY", 33, 8, "right")
  local ready
  for _ = 1, 600 do
    ready = not game.stack:top() and world.map.id == "VERMILION_CITY"
      and world:acceptsMenuInput()
    if ready then break end
    U.wait(1)
  end
  assert(ready, "Vermilion warp did not become ready for menu input")

  local function top() return game.stack:top() end
  local function topIs(id)
    local t = top()
    return t and t.screenId == id and t or nil
  end

  -- START -> the menu, with the POKeGEAR row unlocked by the flags alone.
  U.tap(game, "start")
  local menu
  for _ = 1, 60 do
    menu = topIs("Gen2StartMenu")
    if menu then break end
    U.wait(1)
  end
  assert(menu, "START did not open the start menu")
  local ids = {}
  for _, item in ipairs(menu.items) do ids[item.value] = true end
  assert(ids.pokegear, "the POKeGEAR row is missing from the START menu")
  assert(ids.pokedex, "the POKeDEX row is missing from the START menu")
  U.log("START menu shows POKeDEX and POKeGEAR from the engine flags")

  -- Down to the POKeGEAR row (POKeDEX, POKeMON, PACK, POKeGEAR) and in.
  for _ = 1, 3 do U.tap(game, "down") U.wait(2) end
  U.tap(game, "a")
  local gear
  for _ = 1, 60 do
    gear = topIs("Gen2Pokegear")
    if gear then break end
    U.wait(1)
  end
  assert(gear, "the POKeGEAR row did not open the gear")
  assert(#gear.cards == 4, "expected all four cards, got " .. #gear.cards)

  for _ = 1, 8 do
    if gear:card().id == "radio" then break end
    U.tap(game, "right") U.wait(3)
  end
  if gear.mode == "strip" then U.tap(game, "a") U.wait(3) end
  assert(gear.mode == "card" and gear:card().id == "radio",
    "did not land on the radio card")

  for _ = 1, 39 do U.tap(game, "up") U.wait(2) end
  assert(gear.radioShow == "POKE_FLUTE_RADIO",
    "20.0 did not resolve the POKe FLUTE channel (got "
    .. tostring(gear.radioShow) .. ")")
  for _ = 1, 60 do
    if Music.current() == "Music_PokeFluteChannel" then break end
    U.wait(1)
  end
  assert(Music.current() == "Music_PokeFluteChannel",
    "the POKe FLUTE channel is not playing")
  U.log("tuned 20.0: the POKe FLUTE channel is playing")

  -- B off the card, B out of the gear, B out of the menu: the song must
  -- survive all three (ExitPokegearRadio_HandleMusic keeps a tuned song).
  U.tap(game, "b") U.wait(3)
  U.tap(game, "b") U.wait(3)
  ready = false
  for _ = 1, 600 do
    ready = top() == nil and world:acceptsMenuInput()
    if ready then break end
    if topIs("Gen2StartMenu") then U.tap(game, "b") end
    U.wait(1)
  end
  assert(ready, "closing the gear did not return to an interactive overworld")
  assert(Music.current() == "Music_PokeFluteChannel",
    "the song did not survive closing the gear (playing "
    .. tostring(Music.current()) .. ")")
  assert(Music.mapSong() == "Music_PokeFluteChannel",
    "the song did not become the map music")
  U.log("gear closed: the POKe FLUTE channel persists as the map music")

  -- A on the Snorlax.  SnorlaxAwake hears the flute channel, and the script
  -- runs on into `loadwildmon SNORLAX, 50` and `startbattle`.
  U.tap(game, "a")
  local battle
  for _ = 1, 300 do
    battle = topIs("Gen2BattleTransition") or topIs("Gen2BattleState")
    if battle then break end
    U.tap(game, "a")
    U.wait(3)
  end
  assert(battle, "the Snorlax did not wake: no battle started")
  -- Ride the wipe into the battle screen and read the enemy off it.
  local state
  for _ = 1, 600 do
    state = topIs("Gen2BattleState")
    if state then break end
    U.wait(1)
  end
  assert(state, "the transition never handed over to the battle screen")
  local enemy = state.battle and state.battle.enemy
  assert(enemy and enemy.species == "SNORLAX",
    "expected SNORLAX, got " .. tostring(enemy and enemy.species))
  assert(enemy.level == 50, "expected L50, got " .. tostring(enemy.level))
  -- BATTLETYPE_FORCEITEM: InitEnemyMon hands Item1 over unconditionally.
  assert(enemy.item ~= nil, "the forced held item is missing")
  U.log(("SNORLAX woke up: L%d battle fired, holding %s")
    :format(enemy.level, tostring(enemy.item)))

  print("[driver] PASS gold radio persistence + Snorlax wake")
end

return function(game)
  local ok, err = xpcall(function() run(game) end, debug.traceback)
  if not ok then print("[driver] FAIL gold radio persistence " .. tostring(err)) end
  love.event.quit(ok and 0 or 1)
end
