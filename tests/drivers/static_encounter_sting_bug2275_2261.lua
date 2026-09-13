-- home/trainers.asm:123
--   POKEPORT_DRIVER=tests/drivers/static_encounter_sting_bug2275_2261.lua POKEPORT_IDENTITY=red-sep04 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local Music = require("src.core.Music")
  local Pokemon = require("src.pokemon.Pokemon")
  local TextBox = require("src.render.TextBox")

  local ok = true
  local function check(label, pass)
    U.log(pass and "PASS" or "FAIL", label)
    if not pass then ok = false end
    return pass
  end
  local function finish()
    U.log(ok and "PASS static_encounter_sting_2275_2261"
          or "FAIL static_encounter_sting_2275_2261")
    love.event.quit(ok and 0 or 1)
    while true do coroutine.yield() end
  end
  local function isBox(s) return getmetatable(s) == TextBox end
  local function waitTypedBox()
    for _ = 1, 300 do
      local top = game.stack:top()
      if isBox(top) and top.done then return top end
      U.wait(1)
    end
    return nil
  end

  local function encounter(tag, mapId, x, y)
    U.teleport(game, mapId, x, y, "up")
    U.wait(30)
    local ow = game.stack:top()
    local mapSong = Music.current()

    U.tap(game, "a")
    local box = waitTypedBox()
    if not check(tag .. " talking opens the battle text", box ~= nil) then
      return
    end

    local stingAt, battleEarly
    for f = 1, 240 do
      local top = game.stack:top()
      if top ~= box then battleEarly = true break end
      if not stingAt and Music.current() == "Music_MeetMaleTrainer" then
        stingAt = f
      end
      U.wait(1)
    end
    check(tag .. " box holds 240 frames with no button", not battleEarly)
    check(tag .. " sting replaced " .. tostring(mapSong) .. " while the box waits",
          stingAt ~= nil)
    if battleEarly then return end

    U.shot(game, ("%s/2275_%s_01_box_held_sting_playing.png"):format(DIR, tag))

    U.tap(game, "a")
    local battle
    for _ = 1, 300 do
      local top = game.stack:top()
      if top ~= box and top ~= ow and not isBox(top) then battle = top break end
      U.wait(1)
    end
    check(tag .. " battle starts after A", battle ~= nil)
    local settled = 0
    for _ = 1, 90 do
      settled = settled + 1
      U.wait(1)
    end
    if battle then
      U.shot(game, ("%s/2275_%s_02_battle_after_a_%df.png"):format(DIR, tag, settled))
    end
  end

  U.newGame(game)
  if not check("new game reached the overworld", game.overworld ~= nil) then finish() end
  game.save.party = { Pokemon.new(game.data, "CHARIZARD", 60) }

  encounter("voltorb", "POWER_PLANT", 9, 21)
  encounter("articuno", "SEAFOAM_ISLANDS_B4F", 6, 2)
  encounter("zapdos", "POWER_PLANT", 4, 10)
  finish()
end
