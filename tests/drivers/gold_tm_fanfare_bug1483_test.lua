-- #1483: the TM/HM jingle under `verbosegiveitem`, and the item jingle beside it.
--
--   POKEPORT_IDENTITY=gold-dev POKEPORT_GAME=gold POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/gold_tm_fanfare_bug1483_test.lua \
--     POKEPORT_SHOT_DIR=/tmp/gold-tm-fanfare \
--     perl -e 'alarm 300; exec @ARGV' \
--     python3 -c "import pty; pty.spawn(['love','.'])"
--
-- GiveItemScript is `waitsfx / specialsound / waitbutton`, the drain sitting
-- ABOVE the sound (engine/overworld/scripting.asm:441-449).  Without it PlaySFX
-- drops SFX_GET_TM ($9b) under the beep the box rang on its own press,
-- SFX_READ_TEXT_2 ($08) -- while SFX_ITEM ($01) outranks that beep and survives.
--
-- No POKEPORT_SPEED here on purpose: audio runs on its own real-time
-- accumulator, so fast-forward slides the jingle off the press it belongs to,
-- and the ordering is the whole thing being judged.
local U = require("tests.drivers.util")

local FieldMoves = require("src.world.gen2.FieldMoves")
local Sound = require("src.core.Sound")

-- ../pokegold/maps/Route32.asm:866 -- Route32RoarTMGuyScript, `verbosegiveitem
-- TM_ROAR`, gated on nothing but its own EVENT_GOT_TM05_ROAR latch.
local TM_GIVER = { map = "ROUTE_32", x = 15, y = 13, item = "TM_ROAR" }
-- ../pokegold/maps/Route32Pokecenter1F.asm:109 -- the fishing guru,
-- `verbosegiveitem OLD_ROD`, one warp away and the control for the same gate.
local ITEM_GIVER =
  { map = "ROUTE_32_POKECENTER_1F", x = 1, y = 4, item = "OLD_ROD" }

-- side the player stands on, and the way they have to look from there
local SIDES = {
  { dx = -1, dy = 0, face = "right" },
  { dx = 1, dy = 0, face = "left" },
  { dx = 0, dy = -1, face = "down" },
  { dx = 0, dy = 1, face = "up" },
}

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-tm-fanfare"
  local fails, lines = 0, {}

  local function claim(ok, text)
    if not ok then fails = fails + 1 end
    lines[#lines + 1] = (ok and "PASS " or "FAIL ") .. text
    return ok
  end

  local function stop()
    for _, line in ipairs(lines) do U.log(line) end
    while true do coroutine.yield() end
  end

  U.wait(45)
  local world = game.world
  if not (world and world.map) then
    U.log("FAIL the gold world never booted, nothing to listen to")
    while true do coroutine.yield() end
  end
  local data = game.data

  -- ---- everything that fails as silence --------------------------------------
  local audio = data.audio or {}
  local ids = {}
  for i, name in ipairs(audio.sfxOrder or {}) do ids[name] = i - 1 end
  for _, name in ipairs({ "Sfx_GetTm", "Sfx_Item", "Sfx_ReadText2" }) do
    claim(ids[name] ~= nil and audio.sfx and audio.sfx[name] ~= nil,
      ("the cache can play %s (id %s)"):format(name, tostring(ids[name])))
  end
  -- The gate is a numeric comparison, so the whole bug only exists while these
  -- three ids sit in this order (constants/sfx_constants.asm:4, :11).
  claim((ids.Sfx_Item or 0) < (ids.Sfx_ReadText2 or 0)
    and (ids.Sfx_ReadText2 or 0) < (ids.Sfx_GetTm or 0),
    "and SFX_ITEM outranks the box beep, which outranks SFX_GET_TM")
  claim(type(Sound.waitSfxDone) == "function",
    "Sound.waitSfxDone exists for specialsound's `waitsfx` to call")

  local vol = game.save.options and game.save.options.sfxVol
  claim(vol ~= 0, ("SFX VOL is %s"):format(tostring(vol)))
  if vol == 0 then
    U.log("SFX VOL is ZERO -- a muted run sounds exactly like the bug.")
    U.log("turn it up in OPTION before trusting anything you hear here.")
  end

  for _, spot in ipairs({ TM_GIVER, ITEM_GIVER }) do
    local def = data.items and data.items[spot.item]
    claim(def ~= nil, ("the cache names the item %s"):format(spot.item))
    spot.pocket = def and def.pocket
    spot.index = def and def.index
    spot.want = (spot.pocket == "TM_HM") and "Sfx_GetTm" or "Sfx_Item"
  end
  claim(TM_GIVER.pocket == "TM_HM",
    ("TM_ROAR sits in the TM_HM pocket (got %s)"):format(
      tostring(TM_GIVER.pocket)))
  claim(ITEM_GIVER.pocket ~= "TM_HM",
    ("OLD_ROD does not (got %s)"):format(tostring(ITEM_GIVER.pocket)))

  -- ---- the recorder ----------------------------------------------------------
  --
  -- Sound.play returns nil when the priority gate DROPS the request, which is
  -- the bug itself: the sound neither rings nor ducks the music.
  local calls, frame, inSpecial = {}, 0, false
  local realPlay = Sound.play
  Sound.play = function(d, name)
    local src = realPlay(d, name)
    calls[#calls + 1] = {
      name = Sound.resolve(d, name), frame = frame,
      started = src ~= nil, special = inSpecial,
    }
    return src
  end
  local drains = 0
  local realDrain = Sound.waitSfxDone
  Sound.waitSfxDone = function()
    if inSpecial then drains = drains + 1 end
    return realDrain()
  end
  local realSpecial = world.specialSound
  world.specialSound = function(self, itemIndex)
    inSpecial = true
    local ok, err = pcall(realSpecial, self, itemIndex)
    inSpecial = false
    if not ok then error(err) end
  end

  local function tap(button, gap)
    table.insert(game.input.pressQueue, button)
    game.input.state[button] = true
    frame = frame + 1
    coroutine.yield()
    game.input.state[button] = false
    for _ = 1, (gap or 12) do frame = frame + 1 coroutine.yield() end
  end

  local function walk(button, n)
    for _ = 1, n do
      table.insert(game.input.pressQueue, button)
      game.input.state[button] = true
      frame = frame + 1
      coroutine.yield()
    end
    game.input.state[button] = false
    U.wait(6)
  end

  -- The VM finishes its last `showRaw` and stops while the boxes it queued are
  -- still on the stack, so "the script ended" is not "the conversation ended":
  -- the stack has to be back where it was before A was ever pressed.
  local baseDepth = #game.stack.states
  local function idle()
    return #game.stack.states <= baseDepth
      and not world.vm:running() and not world:busy()
  end

  -- Press first, then look: at rest the Gold overworld holds nothing on the
  -- stack at all, so a leading idle() check would return before the A that
  -- starts the conversation was ever sent.
  local function mash(limit, gap)
    for _ = 1, (limit or 40) do
      tap("a", gap)
      if idle() then return true end
    end
    return idle()
  end

  local function clear(limit)
    for _ = 1, (limit or 12) do
      if idle() then return end
      tap("b", 8)
    end
  end

  -- ---- walk up to one giver and take what they hand over ---------------------
  local function visit(spot, shots)
    clear() -- nothing from the last giver may still be on the stack
    world:applyPlayerState(FieldMoves.PLAYER_NORMAL)
    -- Land on the map first so the collision under the giver is this map's.
    world:setMap(spot.map, spot.x, spot.y + 1, "up")
    U.wait(20)
    world.noWildEncounters = true

    -- A later map edit must degrade to a different side rather than park the
    -- player in a wall, so the standing tile is picked from the live map.
    local side
    for _, s in ipairs(SIDES) do
      local sx, sy = spot.x + s.dx, spot.y + s.dy
      if not side and world.map:isWalkable(sx, sy)
         and not world:npcAt(sx, sy) then
        side = s
      end
    end
    if not claim(side ~= nil,
      ("a free tile beside the giver at (%d,%d) on %s"):format(
        spot.x, spot.y, spot.map)) then
      return nil
    end

    -- Start two cells back and walk in, so the approach is the player's own.
    local steps, sx, sy = 0, spot.x + side.dx, spot.y + side.dy
    for n = 2, 3 do
      local tx, ty = spot.x + side.dx * n, spot.y + side.dy * n
      if steps == n - 2 and world.map:isWalkable(tx, ty)
         and not world:npcAt(tx, ty) then
        steps, sx, sy = n - 1, tx, ty
      end
    end
    spot.side, spot.steps, spot.sx, spot.sy = side, steps, sx, sy
    world:setMap(spot.map, sx, sy, side.face)
    U.wait(20)
    world.noWildEncounters = true
    if steps > 0 then walk(side.face, 20 * steps) end
    U.wait(10)

    local npc = world:facingObject()
    local key = npc and npc.def and npc.def.scriptKey
    local script = key and world.vm.scripts and world.vm.scripts[key]
    if not claim(type(script) == "table",
      ("%s has a script to run at (%d,%d)"):format(spot.map, spot.x, spot.y)) then
      return nil
    end

    -- The give is behind a `checkevent` latch (EVENT_GOT_TM05_ROAR,
    -- EVENT_GOT_OLD_ROD); those are the only flags either script reads.
    local gives = nil
    spot.events = {}
    for _, row in ipairs(script) do
      if type(row) == "table" then
        if row.event then
          world.events:set(row.event, false)
          spot.events[#spot.events + 1] = row.event
        end
        if row.op == "verbosegiveitem" then gives = row.item end
      end
    end
    claim(gives == spot.index,
      ("its `verbosegiveitem` hands over item %s, wanted %s (%s)"):format(
        tostring(gives), tostring(spot.index), spot.item))
    if gives ~= spot.index then return nil end

    game.save.inventory = game.save.inventory or {}
    game.save.inventory[spot.item] = nil
    local first = #calls + 1
    U.shot(game, shots[1])

    -- Mash A the way a player does: through the intro line, the yes/no the
    -- guru asks (YES is the resting cursor), the received line and the pocket
    -- line.  Nothing here waits for the jingle; that is the point.
    local function rang()
      for i = first, #calls do
        if calls[i].name == spot.want and calls[i].special then return true end
      end
      return false
    end
    for _ = 1, 40 do
      tap("a")
      if rang() or idle() then break end
    end
    U.shot(game, shots[2]) -- the box the jingle is meant to be ringing under
    local finished = mash(40)
    claim(finished, ("the %s conversation ran to the end"):format(spot.item))
    U.wait(30)

    local got = (game.save.inventory[spot.item] or 0) > 0
    claim(got, ("the %s reached the pack"):format(spot.item))

    local heard, want, blipBefore = {}, nil, false
    for i = first, #calls do
      local c = calls[i]
      heard[#heard + 1] = ("%s@%d%s"):format(c.name, c.frame,
        c.started and "" or "(dropped)")
      if c.name == spot.want and c.special then want = want or c end
      if c.name == "Sfx_ReadText2" and c.started and not want then
        blipBefore = true
      end
    end
    U.log(("sfx across the %s hand-over: %s"):format(
      spot.item, table.concat(heard, " ")))
    return { want = want, blipBefore = blipBefore, heard = heard }
  end

  local tm = visit(TM_GIVER,
    { out .. "/01-tm-giver.png", out .. "/02-tm-jingle.png" })
  if not tm then
    U.log("could not reach the TM giver; stopping rather than faking it")
    Sound.play = realPlay
    Sound.waitSfxDone = realDrain
    stop()
  end
  claim(tm.blipBefore,
    "the box rang its own beep before the TM jingle was asked for")
  claim(drains > 0, "specialsound drained the channels first, as `waitsfx` does")
  claim(tm.want ~= nil, "Sfx_GetTm was asked for from specialsound at all")
  claim(tm.want and tm.want.started,
    "and the priority gate let it start instead of dropping it")

  local item = visit(ITEM_GIVER,
    { out .. "/03-item-giver.png", out .. "/04-item-jingle.png" })
  if item then
    claim(item.want ~= nil, "Sfx_Item was asked for from specialsound too")
    claim(item.want and item.want.started, "and it started, as it always did")
  end

  Sound.play = realPlay
  Sound.waitSfxDone = realDrain

  for _, line in ipairs(lines) do U.log(line) end
  U.log(("%d checks, %d failed"):format(#lines, fails))
  if fails > 0 then
    U.log("something above is FAIL, so do not spend time listening")
  end

  -- ---- the replay, live ------------------------------------------------------
  --
  -- EVENT_GOT_TM05_ROAR is the only latch the Roar guy reads, so clearing what
  -- his own script checked puts the whole hand-over back.
  clear()
  for _, ev in ipairs(TM_GIVER.events or {}) do world.events:set(ev, false) end
  game.save.inventory[TM_GIVER.item] = nil
  world:setMap(TM_GIVER.map, TM_GIVER.sx, TM_GIVER.sy, TM_GIVER.side.face)
  world.noWildEncounters = true
  U.wait(30)
  U.log("the Roar guy is a couple of steps away; the replay starts in three")
  U.log("seconds and mashes A the whole way through.")
  U.wait(180)
  if TM_GIVER.steps > 0 then walk(TM_GIVER.side.face, 20 * TM_GIVER.steps) end
  U.wait(10)
  mash(40, 16)
  U.wait(60)

  U.log("what right sounds like: the route music cuts out on the received line")
  U.log("and the TM jingle rings under it, then the music comes back.")
  U.log("dead silence with the music still playing is the drop this fixes.")
  U.log("expect the jingle to be cut short by the beep on the next box -- that")
  U.log("is the missing trailing WaitSFX, not this fix failing.")
  U.log("the guru in the Route 32 centre is the control: same beep, but his")
  U.log("OLD ROD jingle rang before the fix as well.")
  U.log("the controls are yours.")
  while true do coroutine.yield() end
end
