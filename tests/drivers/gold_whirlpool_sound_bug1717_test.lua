-- #1717: the surf wash PlayWhirlpoolSound rings as a whirlpool drains.
--
--   POKEPORT_IDENTITY=gold-dev POKEPORT_GAME=gold POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/gold_whirlpool_sound_bug1717_test.lua \
--     POKEPORT_SHOT_DIR=/tmp/gold-whirlpool-sfx \
--     perl -e 'alarm 240; exec @ARGV' \
--     python3 -c "import pty; pty.spawn(['love','.'])"
--
-- PlayWhirlpoolSound is WaitSFX / PlaySFX SFX_SURF / WaitSFX
-- (engine/events/field_moves.asm:5-10), never a bare PlaySFX.  The LEADING wait
-- is what makes it audible: SFX_SURF is $53 and PlaySFX drops any id above the
-- sound still on ch5-ch8 (home/audio.asm), so the beep that dismissed the text
-- box swallowed it.  The TRAILING wait is why the water is still washing when
-- DisappearWhirlpool hands back, above `closetext`.
--
-- No POKEPORT_SPEED here on purpose: audio runs on its own real-time
-- accumulator, so fast-forward slides the sound off the moment it belongs to,
-- and the ordering is the whole thing being judged.
local U = require("tests.drivers.util")

local FieldMoves = require("src.world.gen2.FieldMoves")
local Mon = require("src.battle.gen2.Mon")
local Permissions = require("src.world.gen2.Permissions")
local Sound = require("src.core.Sound")

-- data/generated/maps.lua, ROUTE_41: whirlpools at (22,12), (42,24), (6,30) and
-- (28,48).  Stand one cell north of the first and face it.
local MAP = "ROUTE_41"
local WHIRL = { x = 22, y = 12 }

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-whirlpool-sfx"
  local fails, lines = 0, {}

  local function claim(ok, text)
    if not ok then fails = fails + 1 end
    lines[#lines + 1] = (ok and "PASS " or "FAIL ") .. text
    return ok
  end

  U.wait(45)
  local world = game.world
  if not (world and world.map) then
    U.log("FAIL the gold world never booted, nothing to listen to")
    while true do coroutine.yield() end
  end

  -- ---- everything that fails as silence ------------------------------------
  local audio = game.data.audio or {}
  local hasLabel = false
  for _, name in ipairs(audio.sfxOrder or {}) do
    if name == "Sfx_Surf" then hasLabel = true end
  end
  claim(hasLabel, "the cache knows the sfx label Sfx_Surf")
  claim(audio.sfx and audio.sfx.Sfx_Surf ~= nil,
    "and it has a loadable definition for it")
  claim(type(world.playWhirlpoolSound) == "function",
    "World:playWhirlpoolSound exists for DisappearWhirlpool to call")
  local vol = game.save.options and game.save.options.sfxVol
  claim(vol ~= 0, ("SFX VOL is %s"):format(tostring(vol)))
  if vol == 0 then
    U.log("SFX VOL is ZERO -- a muted run sounds exactly like the bug.")
    U.log("turn it up in OPTION before trusting anything you hear here.")
  end

  -- SURF to get there and WHIRLPOOL to use, with the badges TryWhirlpoolOW
  -- gates on: the gate has its own checks in tests/gen2_world_test.lua, and
  -- what is under test here is the sound, not the refusal.
  local badges = game.save.player.badges or {}
  game.save.player.badges = badges
  for _, badge in pairs(FieldMoves.BADGE) do badges[badge] = true end
  local swimmer = Mon.new(game.data, "LAPRAS", 30,
    { moves = { { id = "SURF" }, { id = "WHIRLPOOL" } } })
  claim(swimmer ~= nil, "a LAPRAS that knows SURF and WHIRLPOOL")
  game.save.party = { swimmer }

  -- ---- stand on the water facing the whirlpool -----------------------------
  world:applyPlayerState(FieldMoves.PLAYER_SURF)
  world:setMap(MAP, WHIRL.x, WHIRL.y - 1, "down")
  U.wait(15)
  world.noWildEncounters = true

  local ctx = world:fieldContext()
  local facingWhirl = Permissions.isWhirlpool(ctx.facingColl)
  if not facingWhirl then
    -- A re-import moved it: take any whirlpool with open water above it rather
    -- than ringing a sound at a patch of empty sea.
    local def = world.maps[MAP]
    for y = 1, (def.height or 0) * 2 - 1 do
      for x = 0, (def.width or 0) * 2 - 1 do
        if not facingWhirl
           and Permissions.isWhirlpool(world.map:cellCollision(x, y))
           and Permissions.isWater(world.map:cellCollision(x, y - 1)) then
          WHIRL.x, WHIRL.y = x, y
          world:setMap(MAP, x, y - 1, "down")
          world:applyPlayerState(FieldMoves.PLAYER_SURF)
          U.wait(10)
          ctx = world:fieldContext()
          facingWhirl = Permissions.isWhirlpool(ctx.facingColl)
          U.log(("note: using the whirlpool at (%d,%d)"):format(x, y))
        end
      end
    end
  end
  claim(facingWhirl,
    ("facing the whirlpool at (%d,%d) on %s"):format(WHIRL.x, WHIRL.y, MAP))
  local blocks = world.maps[MAP] and world.maps[MAP].blocks
  local index = ctx.facingBlockIndex
  local before = blocks and index and blocks[index]
  claim(before ~= nil, "and the block behind it is readable")
  if not (facingWhirl and before) then
    for _, line in ipairs(lines) do U.log(line) end
    U.log("nothing to drive; stopping here rather than faking the moment")
    while true do coroutine.yield() end
  end
  U.shot(game, out .. "/01-facing.png")

  -- ---- record every sfx the drain rings ------------------------------------
  --
  -- Sound.play returns nil when the priority gate DROPS the request, which is
  -- the bug itself: the sound neither sounds nor ducks the music.
  local calls, frame = {}, 0
  local realPlay = Sound.play
  Sound.play = function(data, name)
    local src = realPlay(data, name)
    calls[#calls + 1] = {
      name = name, frame = frame, started = src ~= nil,
      phase = world.fieldMove and world.fieldMove.phase,
    }
    return src
  end

  local function tap(button, gap)
    table.insert(game.input.pressQueue, button)
    game.input.state[button] = true
    frame = frame + 1
    coroutine.yield()
    game.input.state[button] = false
    for _ = 1, (gap or 8) do frame = frame + 1 coroutine.yield() end
  end

  -- Press A into the whirlpool, then answer the ask box.  YES is the default
  -- cursor, so A all the way down is what a player does.
  local drainedAt, closedAt = nil, nil
  for _ = 1, 24 do
    if world.fieldMove and world.fieldMove.phase == "whirlpoolsfx" then break end
    if blocks[index] ~= before and not closedAt then closedAt = frame end
    tap("a")
  end
  if blocks[index] ~= before and not closedAt then closedAt = frame end
  drainedAt = frame

  -- From here on nothing is pressed: the trailing WaitSFX is supposed to hold
  -- the world by itself.
  local busyAfter, phaseFrames = 0, 0
  for _ = 1, 300 do
    if world.fieldMove and world.fieldMove.phase == "whirlpoolsfx" then
      phaseFrames = phaseFrames + 1
    end
    if world:busy() then busyAfter = busyAfter + 1 else break end
    frame = frame + 1
    coroutine.yield()
  end
  Sound.play = realPlay
  U.shot(game, out .. "/02-cleared.png")

  -- ---- what was rung -------------------------------------------------------
  local surf, surfStarted, surfInPhase = nil, false, false
  local heard = {}
  for _, c in ipairs(calls) do
    heard[#heard + 1] = ("%s@%d%s"):format(c.name, c.frame,
      c.started and "" or "(dropped)")
    if c.name == "Sfx_Surf" then
      surf = c
      surfStarted = surfStarted or c.started
      surfInPhase = surfInPhase or c.phase == "whirlpoolsfx"
    end
  end

  claim(blocks[index] ~= before,
    "the whirlpool block was replaced, so the drain really ran")
  claim(surf ~= nil, "Sfx_Surf was asked for at all")
  claim(surfStarted,
    "and the priority gate let it start instead of dropping it")
  claim(surfInPhase,
    "it was rung from PlayWhirlpoolSound, not from somewhere else")
  claim(closedAt == nil or (surf and surf.frame >= closedAt),
    "it came after the text box took its button, not before")
  claim(busyAfter >= 1,
    ("the world stayed shut for %d frames after the box closed"):format(
      busyAfter))
  -- The phase counts down from 180 whatever happens, so 180 flat is the cap
  -- firing rather than the sound ending.
  claim(phaseFrames > 0 and phaseFrames < 180,
    ("the wash ended on its own after %d frames, inside the 180-frame cap")
      :format(phaseFrames))
  if phaseFrames >= 180 then
    U.log("the 180-frame cap is doing the work: Sound.sfxBusy never cleared,")
    U.log("so check curSfx bookkeeping rather than raising the cap.")
  elseif phaseFrames > 165 then
    U.log(("note: only %d frames of margin under the cap"):format(
      180 - phaseFrames))
  end

  for _, line in ipairs(lines) do U.log(line) end
  U.log("sfx rung across the drain: " .. table.concat(heard, " "))
  U.log(("%d checks, %d failed"):format(#lines, fails))
  if fails > 0 then
    U.log("something above is FAIL, so do not spend time listening")
  end

  -- ---- the replay, live ----------------------------------------------------
  --
  -- LoadMapAttributes refills the block buffer from ROM, so the whirlpool is
  -- back on the next map load and the whole thing can be run again by ear.
  world:setMap("NEW_BARK_TOWN", 13, 6, "down")
  U.wait(10)
  world:applyPlayerState(FieldMoves.PLAYER_SURF)
  world:setMap(MAP, WHIRL.x, WHIRL.y - 1, "down")
  world.noWildEncounters = true
  U.wait(30)
  U.log("the whirlpool is back; the replay starts in three seconds.")
  U.wait(180)
  for _ = 1, 24 do
    if world.fieldMove and world.fieldMove.phase == "whirlpoolsfx" then break end
    tap("a", 14)
  end
  for _ = 1, 240 do
    if not world:busy() then break end
    coroutine.yield()
  end

  U.log("what right sounds like: the box takes its A-press beep, then the same")
  U.log("wave wash SURF plays when you get on the water, and control only comes")
  U.log("back once the wash has finished.")
  U.log("silence with the block gone is the drop; a wash that starts under the")
  U.log("beep, or control back in the same frame, is the wrong half fixed.")
  U.log("the controls are yours -- the other whirlpools are further south.")
  while true do coroutine.yield() end
end
