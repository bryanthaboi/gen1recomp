-- Ear check: a song cued while a jingle sounds must wait for it (#398).
-- A fanfare's sfx header claims the music channels and .playMusic rewrites
-- only the music-channel state, so a mid-jingle song stays muted (pokered
-- audio/engine_1.asm:39-56, :1343-1357).
--   POKEPORT_DRIVER=tests/drivers/fanfare_hold_bug398_test.lua POKEPORT_IDENTITY=bug398 POKEPORT_TOUCH=0 love .
-- No POKEPORT_SPEED: fast-forward scales the logic clock only and desyncs audio.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local ChipAudio = require("src.core.ChipAudio")
  local Music = require("src.core.Music")
  local Sound = require("src.core.Sound")

  -- data/generated/maps.lua ROUTE_1: the northern grass patch spans cells
  -- (10-17, 6-8), and pokered data/maps/objects/Route1.asm keeps its
  -- youngsters at (5, 24) and (15, 13), well south of it.
  local MAP = "ROUTE_1"
  local STAND = { x = 12, y = 7, facing = "down" }
  local FANFARES = {
    "Level_Up", "Caught_Mon", "Get_Item1", "Get_Item2",
    "Get_Key_Item", "Pokedex_Rating", "Dex_Page_Added", "Pokeflute",
  }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- ---- what the ear cannot check -----------------------------------------
  local opts = game.save.options or {}
  local sfxVol = opts.sfxVol or 7
  local musicVol = opts.musicVol or 7
  if sfxVol == 0 then
    U.log("FAIL sfx volume is 0: no jingle will sound at all, so nothing")
    U.log("     below can be judged. Set SFX to 7 in OPTION first.")
  end
  if musicVol == 0 then
    U.log("FAIL music volume is 0: the song that must stay held is muted")
    U.log("     anyway. Set MUSIC to 7 in OPTION first.")
  end
  check(("sfx volume %d, music volume %d"):format(sfxVol, musicVol),
        sfxVol > 0 and musicVol > 0)

  for _, name in ipairs(FANFARES) do
    local def = (game.data.audio.sfx or {})[name]
    local src = def and ChipAudio.newSfx(game.data, name) or nil
    local secs = src and src:getDuration() or 0
    check(("%s synthesizes (%.2fs)"):format(name, secs), secs > 0.3)
  end
  local fanfares = game.data.audio.fanfares
  check("Caught_Mon counts as a fanfare",
        fanfares == nil or fanfares.Caught_Mon == true)
  -- Music.lua:100 reaches into ChipAudio for the hold: a chip song is started
  -- by ChipAudio, not by Music, so pausing Music's own source cannot cover it
  check("ChipAudio.holdMusic exists for Music to call",
        type(ChipAudio.holdMusic) == "function")
  local routeSong = (game.data.audio.mapSongs or {})[MAP]
  check(MAP .. " has a map theme to hold (" .. tostring(routeSong) .. ")",
        routeSong ~= nil)

  -- ---- park in the grass -------------------------------------------------
  game.save.party = {
    Pokemon.new(game.data, "PIDGEY", 4),
    Pokemon.new(game.data, "CHARIZARD", 50),
  }
  game.save.inventory = { POKE_BALL = 20, POTION = 5 }
  game.save.bagOrder = { "POKE_BALL", "POTION" }

  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(20)
  local ow = game.overworld
  if not ow.map:isWalkableCell(STAND.x, STAND.y) then
    -- a map edit or a mod blocked the cell: take any free neighbour
    for _, d in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
      local cx, cy = STAND.x + d[1], STAND.y + d[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log(("(%d, %d) is blocked, standing on"):format(STAND.x, STAND.y), cx, cy)
        U.teleport(game, MAP, cx, cy, STAND.facing)
        U.wait(20)
        ow = game.overworld
        break
      end
    end
  end
  check("standing on " .. MAP, ow.map.id == MAP)

  -- ---- the hold, measured ------------------------------------------------
  -- Music hands its chip sources to ChipAudio, so the source the restore
  -- built is only reachable through playMusic's return value.
  local song
  local realPlayMusic = ChipAudio.playMusic
  ChipAudio.playMusic = function(...)
    local src, err = realPlayMusic(...)
    song = src or song
    return src, err
  end

  local jingle = Sound.play(game.data, "Caught_Mon")
  song = nil
  -- BattleState:finish restores the map theme this way, and restoreMap clears
  -- the current label so even the same theme is rebuilt and restarted
  Music.restoreMap(game.data)
  U.wait(45) -- past the threaded first-buffer window, still inside the jingle
  local stillSounding = jingle ~= nil and jingle:isPlaying()
  local songUp = song ~= nil and song:isPlaying()
  if not stillSounding then
    U.log("FAIL the jingle ended before the restore could be judged; rerun")
  else
    check("the map theme stays silent under the jingle", not songUp)
  end

  for _ = 1, 400 do
    if not (jingle and jingle:isPlaying()) then break end
    U.wait(1)
  end
  local back = false
  for _ = 1, 120 do
    if song and song:isPlaying() then back = true break end
    U.wait(1)
  end
  check("the held theme comes back when the jingle ends", back)
  ChipAudio.playMusic = realPlayMusic

  -- ---- the real path, so the same beat can be heard in a battle ----------
  local battle = BattleState.newWild(game, "PIDGEY", 3)
  battle.rng = function(a, b) return a end -- clean capture, no wobbles
  ow:pushBattle(battle)
  for _ = 1, 14 do U.tap(game, "a") U.wait(6) end
  battle.phase = "messages"
  battle.afterQueue = "menu"
  battle:throwBall("POKE_BALL")
  local ChoiceBox = require("src.ui.ChoiceBox")
  for _ = 1, 120 do
    if game.stack:top() == ow then break end
    if getmetatable(game.stack:top()) == ChoiceBox then
      U.tap(game, "down") -- decline the nickname, or naming eats the mash
      U.wait(2)
    end
    U.tap(game, "a")
    U.wait(4)
  end
  if not check("the catch ran through to the overworld", game.stack:top() == ow) then
    -- hand the pad over in the grass whatever the mash got stuck on
    U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  end
  U.wait(60)

  U.log("That was a capture mashed straight out of the battle, which is the")
  U.log("tightest case: the caught jingle should sound alone start to finish")
  U.log("and the route theme should only come in after its last note.")
  U.log("You have 20 balls and a level 4 PIDGEY, so walk the grass and catch")
  U.log("something, or let it level up, and listen for the same thing.")

  while true do
    coroutine.yield()
  end
end
