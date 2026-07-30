-- Walking into grass with no useable POKeMON must black the player out, not
-- cancel the battle and hand the map back (#425).  pokered core.asm:158-162
-- runs .checkAnyPartyAlive after the intro and jumps to HandlePlayerBlackOut
-- (core.asm:1145-1166, PlayerBlackedOutText2).  Machine half also in
-- tests/parity_blackout_no_party.lua.  Never under POKEPORT_SPEED: the wipe,
-- the theme change and the two text boxes come apart from each other.
--   POKEPORT_DRIVER=tests/drivers/blackout_no_party_bug425_test.lua POKEPORT_IDENTITY=bug425 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Music = require("src.core.Music")
  local BattleState = require("src.battle.BattleState")
  local Pokemon = require("src.pokemon.Pokemon")
  local TextBox = require("src.render.TextBox")
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local MAP = "ROUTE_1"
  local pass, fail = 0, 0
  local function check(label, ok)
    if ok then pass = pass + 1 else fail = fail + 1 end
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local function waitFor(fn, limit)
    for _ = 1, limit do
      if fn() then return true end
      U.wait(1)
    end
    return false
  end

  -- every song request in order, so "the battle theme was never restored"
  -- and "the map theme was never playing" read differently in the log
  local songs = {}
  local realPlay = Music.play
  Music.play = function(data, song, loop, ctx)
    songs[#songs + 1] = { song = song, frame = U.frame() }
    U.log(("frame %d play %s"):format(U.frame(), tostring(song)))
    return realPlay(data, song, loop, ctx)
  end
  local function playedAfter(song, frame)
    for _, s in ipairs(songs) do
      if s.song == song and s.frame >= frame then return s end
    end
    return nil
  end

  local opts = game.save.options
  if (opts and opts.musicVol or 0) == 0 then
    U.log("MUSIC VOLUME IS 0: the theme swap this bug is about is silent.")
    U.log("Raise it in OPTION, quit and rerun; the log half still holds.")
  end
  if (opts and opts.sfxVol or 0) == 0 then
    U.log("WARNING sfx volume is 0: the wipe and the text beeps will be")
    U.log("silent too.")
  end

  -- MAGIKARP with SPLASH only would still be a battle; 0 HP is the state
  -- under test, and money is the blackout's other visible half
  game.save.party = { Pokemon.new(game.data, "MAGIKARP", 10) }
  local mon = game.save.party[1]
  local full = mon.stats.hp
  mon.hp = 0
  game.save.money = 3000

  -- Route 1's first grass row.  data/generated/maps.lua holds the tiles
  -- (pokered data/maps/objects/Route1.asm has no grass in it), so the cell is
  -- checked against the loaded map and rescanned if a map edit moved it.
  local GRASS = { x = 10, y = 6 }
  U.teleport(game, MAP, GRASS.x, GRASS.y, "down")
  local ow = game.overworld
  local function grassAt(cx, cy)
    return ow.map:isGrassCell(cx, cy) and ow.map:isWalkableCell(cx, cy)
  end
  if not grassAt(GRASS.x, GRASS.y) then
    local found
    for y = 0, ow.map.heightCells - 1 do
      for x = 0, ow.map.widthCells - 1 do
        -- a neighbouring grass cell too, so the hand-off half below has
        -- somewhere to step without leaving the patch
        if grassAt(x, y) and grassAt(x + 1, y) then found = { x = x, y = y } break end
      end
      if found then break end
    end
    if found then
      U.log(("(%d, %d) is not grass any more, standing on")
              :format(GRASS.x, GRASS.y), found.x, found.y)
      GRASS = found
      U.teleport(game, MAP, found.x, found.y, "down")
      ow = game.overworld
    end
  end
  check("the player is standing in " .. MAP .. " grass",
        grassAt(GRASS.x, GRASS.y))

  local heal = ow:healPoint()
  U.log("heal point:", heal.map, heal.x, heal.y)
  local MAP_SONG = game.data.audio.mapSongs[MAP]
  local HEAL_SONG = game.data.audio.mapSongs[heal.map]
  local WILD_SONG = game.data.audio.battle.wild
  U.log("songs:", tostring(MAP_SONG), tostring(WILD_SONG), tostring(HEAL_SONG))

  -- the encounter OverworldState:checkEncounter would build for this cell
  local encDef = game.data.encounters[MAP]
  local slots = encDef and encDef.grass and encDef.grass.slots
  check(MAP .. " has a grass encounter table", slots ~= nil and #slots > 0)
  if not slots then
    U.log("Nothing can be encountered here; rerun after a ROM re-import.")
    while true do coroutine.yield() end
  end

  local start = U.frame()
  local battle = BattleState.newWild(game, slots[1].species, slots[1].level)
  check("the encounter starts out flagged dead (no healthy party)",
        battle.dead == true)
  local got
  battle.onFinish = function(result)
    got = result
    ow:afterBattle(result, battle)
  end
  ow:pushBattle(battle)
  check("the wipe started the battle theme",
        waitFor(function() return playedAfter(WILD_SONG, start) ~= nil end, 120))

  local function box()
    local top = game.stack:top()
    return getmetatable(top) == TextBox and top or nil
  end
  local shown = waitFor(function() return box() ~= nil end, 600)
  check("the blackout text came up over the map", shown)
  if shown then
    local lines = {}
    for _, page in ipairs(box().pages or {}) do
      for _, line in ipairs(page) do lines[#lines + 1] = line end
    end
    local text = table.concat(lines, " / ")
    U.log("box reads:", text)
    check("it is PlayerBlackedOutText2, both paragraphs",
          text:find("out of", 1, true) ~= nil
          and text:find("blacked", 1, true) ~= nil)
    U.wait(60)
    U.shot(game, SHOT_DIR .. "/bug425_blackout.png")
    U.log("captured", SHOT_DIR .. "/bug425_blackout.png")
  end

  -- page both paragraphs, then let the warp run
  for _ = 1, 12 do
    if not box() then break end
    U.tap(game, "a")
    U.wait(20)
  end
  local warped = waitFor(function()
    return game.overworld and game.overworld.map
       and game.overworld.map.id == heal.map
       and not game.overworld.transitioning
  end, 900)
  check("the player was warped to the heal point map " .. heal.map, warped)
  check("onFinish reported a loss, not a cancelled battle", got == "lose")
  check("the party was revived", mon.hp == full)
  check("half the money is gone (3000 -> 1500)", game.save.money == 1500)
  if HEAL_SONG then
    check("the heal point's own theme replaced the battle theme",
          playedAfter(HEAL_SONG, start) ~= nil)
  end
  local stillBattle = songs[#songs] and songs[#songs].song == WILD_SONG
  check("the battle theme is not what is still playing", not stillBattle)
  U.log(("%d passed, %d failed"):format(pass, fail))

  -- re-arm for the hand-off: same 0 HP party, back in the grass
  mon.hp = 0
  game.save.money = 3000
  U.teleport(game, MAP, GRASS.x, GRASS.y, "down")
  U.log("MAGIKARP is at 0 HP again and you are back in the Route 1 grass.")
  U.log("Step around until an encounter rolls: the wipe and the battle theme,")
  U.log("then the two boxes over the map with the route theme back under them,")
  U.log("then the warp to Pallet Town. Landing back in the grass with the")
  U.log("battle music looping, over and over, is the bug.")

  while true do
    coroutine.yield()
  end
end
