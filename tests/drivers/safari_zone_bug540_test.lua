-- Driver: the Safari Zone entrance walk and the safari battle HUD (#540).
-- Paying runs SafariZoneEntranceAutoWalk (pokered scripts/SafariZoneGate.asm),
-- so the two gate steps are charged and the counter reads 500/500; leaving
-- early is a queued script, not a box drawn over a black transition; and the
-- ball count belongs in the battle menu (engine/battle/core.asm:2074-2079).
-- No POKEPORT_SPEED: fast-forward desyncs the audio clock from the walk.
--   POKEPORT_DRIVER=tests/drivers/safari_zone_bug540_test.lua POKEPORT_IDENTITY=bug540 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Commands = require("src.script.Commands")
  local BattleState = require("src.battle.BattleState")

  -- pokered data/maps/objects/SafariZoneGate.asm: warps 3,0 / 4,0 lead to
  -- SAFARI_ZONE_CENTER 1 / 2, and scripts/SafariZoneGate.asm's
  -- .PlayerNextToSafariZoneWorker1CoordsArray is (3,2)/(4,2), so walking up
  -- the right-hand column from the south warp crosses the join trigger and
  -- lands on the warp the auto-walk takes.
  local GATE = "SAFARI_ZONE_GATE"
  local CENTER = "SAFARI_ZONE_CENTER"
  local START = { x = 4, y = 4, facing = "up" }
  local TRIGGER = { x = 4, y = 2 }
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- ---- machine-checkable preconditions ------------------------------------
  -- a renamed text key, a moved warp or a missing encounter table all end as
  -- "nothing happened", which is indistinguishable from the bug on screen
  local t = game.data.text
  local KEYS = {
    "_SafariZoneGateSafariZoneWorker1WouldYouLikeToJoinText",
    "_SafariZoneGateSafariZoneWorker1ThatllBe500PleaseText",
    "_SafariZoneGateSafariZoneWorker1GoodLuckText",
    "_SafariZoneGateSafariZoneWorker1LeavingEarlyText",
    "_SafariZoneGateSafariZoneWorker1ReturnSafariBallsText",
    "_SafariZoneGateSafariZoneWorker1GoodHaulComeAgainText",
  }
  local missingText = {}
  for _, k in ipairs(KEYS) do
    if type(t[k]) ~= "string" or t[k] == "" then missingText[#missingText + 1] = k end
  end
  check("every gate text key resolves to a string", #missingText == 0)
  if #missingText > 0 then U.log("  missing:", table.concat(missingText, ", ")) end

  -- the leaving-early script is queued rather than pushed, so every opcode it
  -- uses has to exist or the queue runs off the end in silence
  local OPS = { "ask", "jump_if_false", "show_text", "set_field",
                "move_player", "jump", "label", "warp" }
  local missingOps = {}
  for _, op in ipairs(OPS) do
    if type(Commands[op]) ~= "function" then missingOps[#missingOps + 1] = op end
  end
  check("the queued leaving-early script's commands all exist", #missingOps == 0)
  if #missingOps > 0 then U.log("  missing:", table.concat(missingOps, ", ")) end

  local gateDef = game.data.maps[GATE]
  local centerDef = game.data.maps[CENTER]
  local northWarp
  for _, w in ipairs(gateDef and gateDef.warps or {}) do
    if w.x == TRIGGER.x and w.y == 0 then northWarp = w end
  end
  check(GATE .. " has the north warp at (4, 0) into " .. CENTER,
        northWarp ~= nil and northWarp.destMap == CENTER)
  local dest = centerDef and centerDef.warps and centerDef.warps[2]
  check(CENTER .. " warp 2 is the arrival cell",
        dest ~= nil and dest.x == 15 and dest.y == 25)
  if dest then U.log("  arrival cell:", dest.x, dest.y) end

  local enc = game.data.encounters and game.data.encounters[CENTER]
  local slots = enc and enc.grass and enc.grass.slots
  check(CENTER .. " has a grass encounter table", slots ~= nil and #slots > 0)

  -- the auto-walk out of the gate ends on a warp, so the door sfx is part of
  -- what the moment is judged on
  local sfx = game.data.audio and game.data.audio.sfx
  local vol = game.save.options and game.save.options.sfxVol
  check("Go_Outside sfx is loaded", sfx ~= nil and sfx.Go_Outside ~= nil)
  check(("sfx volume is %s, the door sound is audible"):format(tostring(vol)),
        love.audio ~= nil and (vol or 0) > 0)
  if (vol or 0) == 0 then
    U.log("  raise SFX VOL in OPTION or the walk out will be silent")
  end
  U.log("BATTLE LAYOUT is currently",
        (game.save.options and game.save.options.battleLayout) == "wide"
        and "WIDE" or "OG")

  -- ---- entry: pay, then watch him walk himself in --------------------------
  -- FAST text: the join spiel plus the payment text run five pages, and at
  -- the MEDIUM default (TextBox drawChars reads save.options.textSpeed) the
  -- mash loop below runs out of taps before the auto-walk is ever queued
  game.save.options = game.save.options or {}
  game.save.options.textSpeed = 1
  game.save.money = 3000 -- the ¥500 fee, plus change for a few more runs
  if #game.save.party == 0 then
    game.save.party = {
      Pokemon.new(game.data, "NIDORINO", 25),
      Pokemon.new(game.data, "PIDGEY", 14),
      Pokemon.new(game.data, "SANDSHREW", 18),
    }
    U.log("party was empty; added three mons so the pokeball row has content")
  end
  game.save.safari = nil

  U.teleport(game, GATE, START.x, START.y, START.facing)
  U.wait(15)
  local ow = game.overworld
  check("the start menu box is gated off in the gate itself",
        ow ~= nil and ow.inSafariStepZone ~= nil and not ow:inSafariStepZone())

  -- a map edit that blocks the right-hand column would stop the trigger ever
  -- firing; fall back to the other trigger cell's column
  if ow and ow.map and not ow.map:isWalkableCell(TRIGGER.x, TRIGGER.y) then
    U.log(("(%d, %d) is not walkable; using the left trigger column instead")
            :format(TRIGGER.x, TRIGGER.y))
    U.teleport(game, GATE, 3, START.y, START.facing)
    U.wait(10)
    ow = game.overworld
  end

  U.log("He is about to pay and walk in on his own; the screen is yours after.")
  for _ = 1, 12 do
    U.hold(game, "up", 8)
    if game.stack:top() ~= game.overworld then break end
  end
  check("stepping up in front of the worker opened the join prompt",
        game.stack:top() ~= game.overworld)

  -- mash A through the join text, the YES/NO box (YES is the default index)
  -- and the payment text; the auto-walk starts on its own once that closes
  for _ = 1, 150 do
    U.tap(game, "a")
    U.wait(5)
    local cur = game.overworld
    if cur and cur.map and cur.map.id == CENTER then break end
  end
  U.wait(45)

  ow = game.overworld
  local st = game.save.safari
  check("the safari game started", st ~= nil)
  check("he warped through on his own and is in " .. CENTER,
        ow ~= nil and ow.map and ow.map.id == CENTER)
  if ow and ow.map and ow.map.id == CENTER then
    check(("he arrived at the warp cell (%d, %d)")
            :format(ow.player.cellX, ow.player.cellY),
          ow.player.cellX == 15 and ow.player.cellY == 25)
  end
  if st then
    check(("the counter reads %d/500 with %d balls")
            :format(st.steps or -1, st.balls or -1),
          st.steps == 500 and st.balls == 30)
  end
  check("the start menu box is live now that he is inside",
        ow ~= nil and ow.inSafariStepZone and ow:inSafariStepZone())

  U.tap(game, "start")
  U.wait(20)
  if U.shot(game, SHOT_DIR .. "/bug540_start_menu.png") then
    U.log("captured", SHOT_DIR .. "/bug540_start_menu.png")
  end
  U.tap(game, "b")
  U.wait(15)

  -- ---- the safari battle HUD ----------------------------------------------
  local function firstGrassCell(map)
    for y = 0, (map.heightCells or 0) - 1 do
      for x = 0, (map.widthCells or 0) - 1 do
        if map:isGrassCell(x, y) and map:isWalkableCell(x, y) then return x, y end
      end
    end
  end

  ow = game.overworld
  if ow and ow.map and not ow.map:isGrassCell(ow.player.cellX, ow.player.cellY) then
    local gx, gy = firstGrassCell(ow.map)
    if gx then
      U.log("stepping over to the grass at", gx, gy)
      U.teleport(game, CENTER, gx, gy, "up")
      U.wait(10)
    else
      U.log("FAIL no walkable grass cell found on " .. CENTER)
    end
  end

  local function liveBattle()
    for _, s in ipairs(game.stack.states or {}) do
      if getmetatable(s) == BattleState then return s end
    end
    return nil
  end

  local DIRS = { "up", "down", "left", "right" }
  local battle
  for i = 1, 400 do
    U.hold(game, DIRS[(i - 1) % #DIRS + 1], 10)
    battle = liveBattle()
    if battle then break end
  end
  check("a safari battle started", battle ~= nil and battle.safari ~= nil)
  if battle and battle.enemy and battle.enemy.mon then
    U.log("  encounter:", battle.enemy.mon.species, "at level",
          battle.enemy.mon.level)
  end
  if not battle then
    U.log("no encounter after 400 steps -- walk into the grass yourself")
  end

  -- catch the "Wild X appeared!" beat first, then clear it: the count is
  -- judged in both, absent over the field and present in the menu
  U.wait(60)
  if U.shot(game, SHOT_DIR .. "/bug540_battle_intro.png") then
    U.log("captured", SHOT_DIR .. "/bug540_battle_intro.png")
  end
  -- the cry and the slide run on their own clocks, so press until the phase
  -- flips rather than guessing a frame count
  for _ = 1, 60 do
    if battle and battle.phase == "menu" then break end
    U.tap(game, "a")
    U.wait(10)
  end
  check("the BALL/BAIT/THROW ROCK/RUN menu is up",
        battle ~= nil and battle.phase == "menu")
  U.wait(15)
  if U.shot(game, SHOT_DIR .. "/bug540_battle_menu.png") then
    U.log("captured", SHOT_DIR .. "/bug540_battle_menu.png")
  end

  -- ---- hand off ------------------------------------------------------------
  U.log("Controls are yours.  The count belongs inside the menu, reading")
  U.log("\"BALLx 30\" on one line with the cursor to its left, and nothing")
  U.log("floating over the field above the party pokeball row.  Watch for the")
  U.log("30 landing a cell left and colliding with the x, or a cell right and")
  U.log("leaving a gap before BAIT; toggle BATTLE LAYOUT in OPTION and check")
  U.log("WIDE too, where the old 15x4 panel used to sit at tile (23,7).")
  U.log("Then RUN, walk back down onto the south warp: \"Leaving early?\"")
  U.log("should sit over the drawn gate interior, worker and counter and")
  U.log("shelves visible, not a black screen.  Answer NO to bounce back in and")
  U.log("do it again, or YES for the return-balls text and a walk down to")
  U.log("(4,3) below the worker, rather than being left on the warp at (4,0).")

  while true do
    coroutine.yield()
  end
end
