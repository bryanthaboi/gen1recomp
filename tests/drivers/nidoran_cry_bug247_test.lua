-- Driver: manual audio check for the silent Pewter NIDORAN (#247).
--
-- pokered scripts/PewterNidoranHouse.asm, PewterNidoranHouseNidoranText:
--     text_far _PewterNidoranHouseNidoranText
--     text_asm
--     ld a, NIDORAN_M
--     call PlayCry
--     call WaitForSoundToFinish
--     jp TextScriptEnd
-- so the box types "NIDORAN: Bowbow!" first and the male NIDORAN cry sounds
-- second, once the typewriter is done.  The box then still waits for a
-- button: PewterNidoranHouse_Script is `jp EnableAutoTextBoxDrawing`, and
-- AutoTextBoxDrawingCommon (pokered home/window.asm) zeroes
-- wDoNotWaitForButtonPressAfterDisplayingText, so DisplayTextID falls through
-- to WaitForTextScrollButtonPress like any other NPC line.
-- data/scripts/flavor/pewter_nidoran_house.lua ported the dialogue row but
-- never the cry row, so the NIDORAN was silent.
--
-- This is an audio fix, so nothing here can assert it.  What this driver does
-- is check the halves an ear cannot check (the cry row is wired into the talk
-- script in the adjacency Commands.play_cry/show_text require, and the
-- NIDORAN_M cry sample resolves the way Sound.playCry looks it up), park the
-- player one cell below the NIDORAN already facing it, and then hand input
-- straight back so a human hears the cry live.
--
-- Do NOT add POKEPORT_SPEED to this run: fast-forward scales only the logic
-- clock while audio runs on its own real-time 60 Hz accumulator
-- (src/core/Game.lua), so the cry would stop lining up with the box it
-- belongs to.
--
--   POKEPORT_DRIVER=tests/drivers/nidoran_cry_bug247_test.lua \
--     POKEPORT_IDENTITY=bug247 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local mapScripts = require("data.scripts.init")

  local MAP = "PEWTER_NIDORAN_HOUSE"
  local NPC = "PEWTERNIDORANHOUSE_NIDORAN"
  local TEXT = "TEXT_PEWTERNIDORANHOUSE_NIDORAN"
  local SPECIES = "NIDORAN_M"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- ---- preconditions the ear cannot check --------------------------------
  -- Commands.play_cry only stashes ctx.pendingCry; Commands.show_text is what
  -- turns it into the box's opts.auto.  The two rows therefore have to be
  -- adjacent and in that order, or the cry is handed to the wrong box or
  -- never consumed at all -- and either way the NIDORAN stays quiet.
  local rows = mapScripts.talkScript(MAP, TEXT)
  local cryAt, textAt
  for i, row in ipairs(rows or {}) do
    if row[1] == "play_cry" and not cryAt then cryAt = i end
    if row[1] == "show_text" and not textAt then textAt = i end
  end
  local cry = cryAt and rows[cryAt]
  check("talk script carries a play_cry row", cry ~= nil)
  check("cry species is " .. SPECIES, cry ~= nil and cry[2] == SPECIES)
  -- the third arg is play_cry's waitForButton form, which keeps
  -- DisplayTextID's trailing WaitForTextScrollButtonPress instead of letting
  -- the box pop itself the instant the cry goes quiet
  check("cry row keeps the button wait", cry ~= nil and cry[3] == true)
  check("play_cry sits immediately before show_text",
        cryAt ~= nil and textAt == cryAt + 1)

  -- Sound.playCry reads data.audio.cries[species]; a missing or misspelled
  -- key is a silent no-op with no error, which is indistinguishable by ear
  -- from the bug itself
  local cries = game.data.audio and game.data.audio.cries
  check("data.audio.cries." .. SPECIES .. " resolves",
        cries ~= nil and cries[SPECIES] ~= nil)

  local vol = game.save.options and game.save.options.sfxVol
  U.log("audio device present:", love.audio ~= nil,
        "  SFX VOL (0-7):", tostring(vol))
  if not love.audio or vol == 0 then
    U.log("WARNING: sound output is off, so nothing below will be audible;",
          "raise SFX VOL in OPTION first")
  end

  -- ---- park the player in front of the NIDORAN ---------------------------
  -- pokered data/maps/objects/PewterNidoranHouse.asm puts the NIDORAN on
  -- (4, 5) facing LEFT at the little boy on (3, 5), so the free approach cell
  -- is the floor directly below it.
  U.teleport(game, MAP, 4, 6, "up")
  U.wait(10)

  local function nidoranIn(ow)
    for _, n in ipairs(ow.npcs or {}) do
      if n.def and n.def.name == NPC then return n end
    end
    return nil
  end

  -- re-reads game.overworld every call: the fallback below teleports again,
  -- which rebuilds the whole state and its npc list
  local function facingTheMon()
    local ow = game.overworld
    local mon = ow and nidoranIn(ow)
    if not mon then return false end
    local fx, fy = ow.player:facingCell()
    return ow:npcAtCell(fx, fy) == mon
  end

  local ow = game.overworld
  local mon = ow and nidoranIn(ow)
  check("NIDORAN object loaded on " .. MAP, mon ~= nil)

  if mon and not facingTheMon() then
    -- the hard-coded approach cell stopped working (map edit, or a mod moved
    -- the object): take any free walkable neighbour and turn toward the mon.
    -- {dx, dy, facing} is the offset from the mon to the stand cell plus the
    -- direction that looks back at it, so +1 on x means facing left.
    local sides = {
      { 0, 1, "up" }, { 1, 0, "left" }, { -1, 0, "right" }, { 0, -1, "down" },
    }
    for _, s in ipairs(sides) do
      local cx, cy = mon.cellX + s[1], mon.cellY + s[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log("approach cell (4, 6) is blocked, standing on",
              cx, cy, "facing", s[3])
        U.teleport(game, MAP, cx, cy, s[3])
        U.wait(10)
        break
      end
    end
  end
  check("player is standing in front of the NIDORAN", facingTheMon())

  -- ---- hand off, then stay out of the way --------------------------------
  U.log("........................................................")
  U.log("LISTEN NOW: press A to talk to the NIDORAN in front of you.")
  U.log("  RIGHT: the box types out \"NIDORAN: Bowbow!\", the male NIDORAN")
  U.log("         cry sounds ONCE after the last character lands, then the")
  U.log("         arrow blinks and the box waits for your A or B.")
  U.log("  BUG #247 sounds like: the line types out and then nothing, dead")
  U.log("         silence under the house music, arrow blinking.")
  U.log("  ALSO WRONG: the cry fires while the text is still typing (row")
  U.log("         order broken), or the box closes itself the moment the cry")
  U.log("         ends with no button press (waitForButton lost).")
  U.log("Input is yours from here on -- talk again as often as you like, and")
  U.log("the little boy on the left is the silent control to compare against.")
  U.log("........................................................")

  while true do
    coroutine.yield()
  end
end
