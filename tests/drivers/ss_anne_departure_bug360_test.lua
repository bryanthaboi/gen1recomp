-- Eye/ear check on the S.S. Anne leaving Vermilion Dock and the rival's
-- goodbye on 2F (#360): she used to blink to water in one frame, the surf
-- music rode into the city, and the rival walked back to his spawn without
-- the CUT-master line.  scripts/VermilionDock.asm and scripts/SSAnne2F.asm.
-- Do not set POKEPORT_SPEED: fast-forward scales the logic clock only, so
-- the horns and the music switch desynchronize from what you see.
--   POKEPORT_DRIVER=tests/drivers/ss_anne_departure_bug360_test.lua POKEPORT_IDENTITY=bug360 POKEPORT_DEV=1 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Music = require("src.core.Music")
  local story3 = require("data.scripts.story3")
  local story5 = require("data.scripts.story5")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  -- pokered data/maps/objects/VermilionDock.asm: warp_event 14, 2 is the
  -- gangway off the ship, which is block (7,1); SSAnne2F.asm's
  -- .PlayerCoordinatesArray is 36,8 / 37,8 with the rival spawned on (36,4).
  local DOCK, DOCK_CELL = "VERMILION_DOCK", { x = 14, y = 2 }
  local ANNE2F, TRIGGER = "SS_ANNE_2F", { x = 37, y = 8 }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local function rowsOfKind(rows, kind)
    local out = {}
    for _, r in ipairs(rows or {}) do
      if r[1] == kind then out[#out + 1] = r end
    end
    return out
  end

  -- capture what a scene queues without letting it touch the live save or
  -- start the encounter sting
  local function capture(run)
    local realPlay = Music.play
    Music.play = function() end
    local rows
    local ow = {
      runner = {
        isRunning = function() return false end,
        run = function(_, r) rows = r end,
      },
      player = { facing = "down", cellX = DOCK_CELL.x, cellY = DOCK_CELL.y },
      startDustAnim = function(_, _, _, done) if done then done() end end,
      queueScript = function(_, r) rows = r end,
    }
    run(ow)
    Music.play = realPlay
    return rows, ow
  end

  -- ---------------------------------------------------------- rival exit
  local CUT = "_SSAnne2FRivalCutMasterText"
  local cut = game.data.text[CUT]
  check(CUT .. " resolves", type(cut) == "string" and cut ~= "")
  if type(cut) == "string" then
    check("it is the CUT-master line", cut:find("CUT", 1, true) ~= nil)
    U.log("rival goodbye reads:", (cut:gsub("\n", " / ")))
  end

  for _, side in ipairs({ { 37, 4 }, { 36, 6 } }) do
    local x, steps = side[1], side[2]
    local rows, capturedOw = capture(function(ow)
      story5[ANNE2F].onStep({ save = { flags = {} }, data = game.data }, ow, x, 8)
    end)
    -- SSAnne2FSetFacingDirectionScript (scripts/SSAnne2F.asm:73)
    check(("x=%d the player keeps his walking facing at trigger time"):format(x),
          capturedOw.player.facing == "down")
    local turnIndex, moveIndex, textIndex
    for i, r in ipairs(rows) do
      if r[1] == "face_player_dir" and not turnIndex then turnIndex = i end
      if r[1] == "move_npc_to" and not moveIndex then moveIndex = i end
      if r[1] == "show_text" and not textIndex then textIndex = i end
    end
    if x == 37 then
      check("x=37 turns the player LEFT as a scripted row",
            turnIndex ~= nil and rows[turnIndex][2] == "left")
      check("x=37 turns him after the walk and before the dialogue",
            turnIndex ~= nil and moveIndex ~= nil and textIndex ~= nil
            and turnIndex > moveIndex and turnIndex < textIndex)
    else
      check("x=36 never writes the player's direction", turnIndex == nil)
    end
    local said = rowsOfKind(rows, "show_text")
    check(("x=%d the goodbye is the last thing he says"):format(x),
          said[#said] ~= nil and said[#said][2] == CUT)
    local walk = rowsOfKind(rows, "walk_npc")[1]
    check(("x=%d exit walk is %d steps, ending downward"):format(x, steps),
          walk ~= nil and #walk[3] == steps and walk[3][#walk[3]] == "down")
    check(("x=%d he does not retreat to the spawn (36,4)"):format(x), (function()
      for _, r in ipairs(rowsOfKind(rows, "move_npc_to")) do
        if r[3] == 36 and r[4] == 4 then return false end
      end
      return true
    end)())
  end

  -- ------------------------------------------------------------ the ship
  local dockRows = capture(function(ow)
    story3[DOCK].onEnter({ save = { flags = { EVENT_GOT_HM01 = true } },
                           data = game.data }, ow)
  end)
  local horns = 0
  for _, r in ipairs(rowsOfKind(dockRows, "play_sound")) do
    if r[2] == "SS_Anne_Horn" then horns = horns + 1 end
  end
  check("the departure blows the horn twice", horns == 2)
  check("she sails as one blocking slide, not a block shuffle",
        #rowsOfKind(dockRows, "ss_anne_departs") == 1
        and #rowsOfKind(dockRows, "replace_block") == 0)
  check("he keeps facing down until he walks out",
        (rowsOfKind(dockRows, "face_player_dir")[1] or {})[2] == "down")
  check("no keepMusic override into the city", (function()
    for _, r in ipairs(rowsOfKind(dockRows, "play_music")) do
      if r[3] and r[3].keep then return false end
    end
    return true
  end)())
  local sfx = game.data.audio and game.data.audio.sfx
  check("SS_Anne_Horn is in the sfx table", sfx ~= nil and sfx.SS_Anne_Horn ~= nil)
  local mapSongs = game.data.audio and game.data.audio.mapSongs
  check("VERMILION_CITY still owns Music_Vermilion",
        mapSongs ~= nil and mapSongs.VERMILION_CITY == "Music_Vermilion")

  local opts = game.save.options or {}
  if opts.sfxVol == 0 or opts.musicVol == 0 then
    U.log("SFX OR MUSIC VOLUME IS 0. The horns and the music switch are the")
    U.log("whole check. Raise them in OPTION and rerun.")
  else
    check("sfx and music are audible (" .. tostring(opts.sfxVol) .. "/"
          .. tostring(opts.musicVol) .. ")", true)
  end

  game.save.party = {
    Pokemon.new(game.data, "CHARIZARD", 50),
    Pokemon.new(game.data, "PIKACHU", 30),
    Pokemon.new(game.data, "SNORLAX", 77),
  }
  game.save.flags.EVENT_GOT_POKEDEX = true
  game.save.flags.EVENT_GOT_HM01 = true
  game.save.flags.EVENT_SS_ANNE_LEFT = nil
  game.save.flags.EVENT_BEAT_SS_ANNE_RIVAL = nil
  check("HM01 in hand, ship still docked, rival unbeaten",
        game.save.flags.EVENT_GOT_HM01 == true
        and game.save.flags.EVENT_SS_ANNE_LEFT == nil
        and game.save.flags.EVENT_BEAT_SS_ANNE_RIVAL == nil)

  U.log("Watch for: he turns to face DOWN and stays that way, she idles two")
  U.log("seconds, one horn, then she slides WEST smoothly for about seventeen")
  U.log("seconds with white smoke puffing off the front funnel and drifting")
  U.log("east, the dock row he stands on never moving; a second horn once she")
  U.log("is gone, the gangway stub still under his feet, then he walks up and")
  U.log("the surf loop gives way to the Vermilion theme as you cross in.")

  U.teleport(game, DOCK, DOCK_CELL.x, DOCK_CELL.y, "up")
  local ow = game.overworld
  if ow and ow.map.id ~= DOCK then
    check("standing on " .. DOCK, false)
  elseif ow and not ow.map:isWalkableCell(DOCK_CELL.x, DOCK_CELL.y) then
    -- a map edit moved the gangway: any walkable neighbour of it still sits
    -- on the deck row the departure is keyed on
    for _, s in ipairs({ { 0, 1 }, { -1, 0 }, { 0, -1 }, { 1, 0 } }) do
      local cx, cy = DOCK_CELL.x + s[1], DOCK_CELL.y + s[2]
      if ow.map:isWalkableCell(cx, cy) then
        U.log(("gangway cell (%d,%d) is blocked, standing on")
                :format(DOCK_CELL.x, DOCK_CELL.y), cx, cy)
        U.teleport(game, DOCK, cx, cy, "up")
        break
      end
    end
  end

  -- filmstrip across the slide: 120 frames of idling, then a shot every 40
  U.wait(110)
  U.shot(game, DIR .. "/360_dock_0.png")
  for i = 1, 5 do
    U.wait(40)
    U.shot(game, DIR .. "/360_dock_" .. i .. ".png")
  end
  U.log("captured", DIR .. "/360_dock_0.png", "through 5")
  U.wait(240)
  U.shot(game, DIR .. "/360_dock_gone.png")

  -- park him one step short of the 2F trigger so the pad picks it up
  U.wait(120)
  U.teleport(game, ANNE2F, TRIGGER.x, TRIGGER.y + 1, "up")

  U.log("The pad is yours. One tap UP walks onto (37,8) and the rival comes")
  U.log("down from the captain's door: beat him, and after the goodbye he must")
  U.log("walk four cells DOWN out of the room, never back up to (36,4).  For")
  U.log("the other branch, console: game.save.flags.EVENT_BEAT_SS_ANNE_RIVAL")
  U.log("= nil, then step onto (36,8) -- there he goes RIGHT around you first.")

  while true do
    coroutine.yield()
  end
end
