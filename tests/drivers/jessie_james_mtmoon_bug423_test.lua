-- Eye check on the Mt Moon B2F Jessie & James ambush (#423): the duo walk up
-- to the player and leave behind a fade.  pokeyellow scripts/MtMoonB2F.asm
-- MtMoonB2FScript_49e15 simulates PAD_UP, Script6/Script9 walk Jessie six and
-- James five LEFT steps, Script8/Script11 face them; Script14 hides them between
-- GBFadeOutToBlack / GBFadeInFromBlack.  No POKEPORT_SPEED (the fade and the
-- theme sting ride the audio clock), and no POKEPORT_IDENTITY (it re-imports):
--   POKEPORT_VERSION=yellow SHOT_DIR=/tmp/shots POKEPORT_TOUCH=0 POKEPORT_DRIVER=tests/drivers/jessie_james_mtmoon_bug423_test.lua love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local BattleState = require("src.battle.BattleState")
  local GameVersion = require("src.core.GameVersion")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  pcall(function() io.stdout:setvbuf("no") end) -- LOVE block-buffers stdout

  -- pokeyellow data/maps/objects/MtMoonB2F.asm: object 2 JESSIE at (9,3),
  -- object 6 JAMES at (9,4).  MtMoonB2FScript_49e15's trigger is (3,5), so the
  -- PAD_UP step puts the player on (3,4) and the walks land (3,3) and (4,4).
  local MAP = "MT_MOON_B2F"
  local TRIGGER = { x = 3, y = 5 }
  local JESSIE, JAMES = "MTMOONB2F_JESSIE", "MTMOONB2F_JAMES"
  local BEAT = "EVENT_BEAT_MT_MOON_3_JESSIE_JAMES"
  local WANT = {
    player = { x = TRIGGER.x, y = TRIGGER.y - 1 },
    jessie = { x = TRIGGER.x, y = TRIGGER.y - 2, facing = "down" },
    james = { x = TRIGGER.x + 1, y = TRIGGER.y - 1, facing = "left" },
  }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local function npcNamed(ow, name)
    for _, n in ipairs(ow.npcs or {}) do
      if n.def and n.def.name == name then return n end
    end
    return nil
  end

  -- ---- what the eye cannot check -----------------------------------------
  local opts = game.save.options or {}
  local sfxVol = opts.sfxVol or 7
  if sfxVol == 0 then
    U.log("FAIL sfx volume is 0: the theme sting that opens the ambush and the")
    U.log("     bubble blip over the player are both silent, so the audio half")
    U.log("     cannot be judged. Set SFX to 7 in OPTION first.")
  end
  check(("sfx volume %d"):format(sfxVol), sfxVol > 0)
  check("running Yellow", GameVersion.isYellow())

  -- one strong mon with one damaging move: a stat move stalls the A-mash
  local mon = Pokemon.new(game.data, "MEWTWO", 100)
  mon.moves = { { id = "TACKLE", pp = 35 } }
  game.save.party = { mon }
  game.save.flags[BEAT] = nil
  game.save.flags.EVENT_GOT_HELIX_FOSSIL = true

  -- ---- reach the trigger ---------------------------------------------------
  U.teleport(game, MAP, TRIGGER.x, TRIGGER.y + 1, "up")
  local ow = game.overworld
  U.hold(game, "up", 20)
  U.wait(10)
  if not ow.runner:isRunning() then
    -- a map or mod edit blocked the approach from below: step in from whatever
    -- free walkable neighbour is left
    local sides = { { 1, 0, "left" }, { -1, 0, "right" }, { 0, -1, "down" } }
    for _, s in ipairs(sides) do
      local cx, cy = TRIGGER.x + s[1], TRIGGER.y + s[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log("approach from below failed, stepping in from", cx, cy)
        U.teleport(game, MAP, cx, cy, s[3])
        ow = game.overworld
        U.hold(game, s[3], 20)
        U.wait(10)
        if ow.runner:isRunning() then break end
      end
    end
  end
  check("the ambush script is running", ow.runner:isRunning())
  U.shot(game, DIR .. "/jj423_0_trigger.png")

  -- ---- the duo close in ----------------------------------------------------
  -- Sample every mash: the closed-in positions only hold between the motto and
  -- the challenge line, and the battle push ends the window.
  local closed = nil
  local battle = nil
  for _ = 1, 1500 do
    local top = game.stack:top()
    if getmetatable(top) == BattleState then
      battle = top
      break
    end
    local jessie, james = npcNamed(ow, JESSIE), npcNamed(ow, JAMES)
    if not closed and jessie and james and not jessie.moving and not james.moving
       and jessie.cellX == WANT.jessie.x and james.cellX == WANT.james.x then
      closed = {
        px = ow.player.cellX, py = ow.player.cellY,
        jx = jessie.cellX, jy = jessie.cellY, jf = jessie.facing,
        mx = james.cellX, my = james.cellY, mf = james.facing,
      }
      U.shot(game, DIR .. "/jj423_1_scene.png")
    end
    U.tap(game, "a")
    U.wait(3)
  end

  check("the duo walked in instead of staying at (9,3) and (9,4)", closed ~= nil)
  closed = closed or {}
  U.log("player", tostring(closed.px), tostring(closed.py),
        "jessie", tostring(closed.jx), tostring(closed.jy), tostring(closed.jf),
        "james", tostring(closed.mx), tostring(closed.my), tostring(closed.mf))
  check("the player took the simulated PAD_UP step onto (3,4)",
        closed.px == WANT.player.x and closed.py == WANT.player.y)
  check("Jessie is standing directly above the player",
        closed.jx == WANT.jessie.x and closed.jy == WANT.jessie.y)
  check("Jessie is facing down at him", closed.jf == WANT.jessie.facing)
  check("James is standing beside the player",
        closed.mx == WANT.james.x and closed.my == WANT.james.y)
  check("James is facing left at him", closed.mf == WANT.james.facing)
  check("the challenge line opened the battle", battle ~= nil)
  if battle then
    for _ = 1, 240 do
      if battle.showEnemyTrainer and (battle.introSlide or 0) <= 0 then break end
      U.wait(1)
    end
    U.shot(game, DIR .. "/jj423_1b_battle.png")
  end

  -- ---- and leave behind a fade --------------------------------------------
  local peakFade, fadeShot = 0, false
  local settled = false
  for i = 1, 6000 do
    local overlay = ow.fadeOverlay
    local alpha = overlay and overlay.alpha or 0
    if alpha > peakFade then peakFade = alpha end
    if game.stack:top() == ow and not ow.runner:isRunning()
       and #ow.scriptMoves == 0 and game.save.flags[BEAT] then
      settled = true
      break
    end
    if alpha > 0.35 and not fadeShot then
      fadeShot = true
      U.shot(game, DIR .. "/jj423_2_fade.png")
    end
    U.tap(game, "a")
    -- step frame by frame while the overlay lives: a 12-frame ramp sampled
    -- every third frame reads as no fade at all
    U.wait((alpha > 0 or i > 1200) and 1 or 3)
  end
  U.shot(game, DIR .. "/jj423_3_done.png")

  check("the scene ran to its end", settled)
  check("the beat flag is set", game.save.flags[BEAT] == true)
  check("Jessie is gone", npcNamed(ow, JESSIE) == nil)
  check("James is gone", npcNamed(ow, JAMES) == nil)
  U.log(("peak fade alpha %.2f"):format(peakFade))
  check("the exit dipped the screen toward black", peakFade > 0.3)

  U.log("jj423_1_scene.png must show Jessie one cell ABOVE the player looking")
  U.log("down at him and James on his right looking left, not the pair parked")
  U.log("across the corridor; the exclamation bubble pops over the player just")
  U.log("before they start walking, so watch the window live for that beat.")
  U.log("jj423_2_fade.png is the room dimming with the duo still standing in")
  U.log("it, and jj423_3_done.png is the same room lit and empty; the second")
  U.log("Music_MeetJessieJames sting covers the fade, then the cave theme.")

  while true do
    coroutine.yield()
  end
end
