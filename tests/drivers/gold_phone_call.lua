-- Assertion driver: the phone in the RUNNING game.  It PASSes or it fails
-- loudly; there is nothing to eyeball.
--
--   POKEPORT_IDENTITY=gold-dev POKEPORT_GAME=gold \
--     POKEPORT_DRIVER=tests/drivers/gold_phone_call.lua \
--     perl -e 'alarm 300; exec @ARGV' \
--     python3 -c "import pty; pty.spawn(['love','.'])"
--
-- Three things the ROM-free suites cannot see from outside a booted world:
--   * StartMap's `farcall InitCallReceiveDelay`: a genuine World:setMap has
--     to arm the receive countdown off the game clock.
--   * CheckTimeEvents' CheckPhoneCall arm: with a contact in the book and
--     the countdown run down, a random call has to RING in the overworld --
--     the caller-ID page, the extracted bank $41 chat, the Click! -- and a
--     caller script's .WantsBattle has to arm its _READY_FOR_REMATCH event.
--   * The Pokegear's CALL entry: the callee's SCRIPT1 runs through the same
--     VM while the card keeps the screen.
local U = require("tests.drivers.util")

return function(game)
  local fails = 0
  local function ok(cond, msg)
    if cond then print("[phone] ok   " .. msg)
    else fails = fails + 1 print("[phone] FAIL " .. msg) end
    return cond
  end

  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    U.wait(2)
    game.input.state[button] = false
    U.wait(frames or 4)
  end

  -- TextBox.paginate emits a page as a LIST of wrapped lines; flatten the
  -- whole open box to one searchable string.
  local function boxText(top)
    if not (top and top.pages) then return nil end
    local out = {}
    for _, page in ipairs(top.pages) do
      if type(page) == "table" then
        out[#out + 1] = table.concat(page, "\n")
      else
        out[#out + 1] = tostring(page)
      end
    end
    return table.concat(out, "|")
  end

  U.wait(45)
  local w = game.world
  assert(w and w.map, "gold world did not boot")
  local save = game.save
  local Phone = require("src.core.gen2.Phone")

  -- The phone reads its clock through World:stepContext's game.clock seam, so
  -- the driver owns the minutes the countdown walks.
  game.clock = { day = 0, hour = 9, minute = 0 }

  -- ------------------------------------------- StartMap arms the countdown
  save.phone = nil
  assert(w:setMap("ROUTE_31", 8, 6, "down"), "setMap failed for ROUTE_31")
  U.wait(3)
  ok(save.phone and save.phone.delayMins == 20,
    "a map load arms the receive countdown at twenty minutes")
  ok(save.phone and save.phone.timeCycles == 0, "with the cycle counter zeroed")
  ok(save.phone and save.phone.delayStart
    and save.phone.delayStart.minute == 0, "stamped off the game clock")

  -- CheckStandingOnEntrance must not refuse, so stand on a plain floor cell.
  local cx, cy = w.player.cellX, w.player.cellY
  for y = 2, 16 do
    for x = 2, 16 do
      if w.map:cellCollision(x, y) == 0x00 then cx, cy = x, y end
    end
  end
  assert(w:setMap("ROUTE_31", cx, cy, "down"), "no floor cell on ROUTE_31")
  U.wait(3)

  -- ------------------------------------------- a random call rings
  -- Joey (contact 15) lives on ROUTE_30, so he is available from ROUTE_31,
  -- and his caller script's rematch gate is ENGINE_FLYPOINT_GOLDENROD
  -- (checkflag 69 in the extracted body).
  Phone.addContact(save, 15)
  w:setEngineFlag(69, true)

  local calls, sawRing, sawClick, sawReset = 0, false, false, false
  for _ = 1, 40 do
    if w.events:get(628) then break end
    game.clock.minute = game.clock.minute + 20
    for _ = 1, 20 do
      U.wait(1)
      if w:busy() then break end
    end
    if w:busy() then
      calls = calls + 1
      for _ = 1, 300 do
        local textAll = boxText(game.stack and game.stack:top())
        if textAll then
          if textAll:find("RING!", 1, true) then sawRing = true end
          if textAll:find("Click!", 1, true) then sawClick = true end
        end
        if not w:busy() then break end
        tap("a", 2)
      end
      if save.phone.timeCycles == 0 and save.phone.delayMins == 20 then
        sawReset = true
      end
    end
  end
  ok(calls > 0, ("a random incoming call rang in the overworld (%d calls)")
    :format(calls))
  ok(sawRing, "opening on the RING! caller-ID page")
  ok(sawClick, "and hanging up on the Click!")
  ok(w.events:get(628),
    "a caller script armed EVENT_JOEY_READY_FOR_REMATCH (628)")
  ok(sawReset, "and the hang-up restarted the receive countdown")

  -- ------------------------------------------- the Pokegear calls out
  w:setEngineFlag(2, true) -- ENGINE_PHONE_CARD
  w:setEngineFlag(4, true) -- ENGINE_POKEGEAR
  game:openStartMenuItem("pokegear")
  for _ = 1, 600 do
    local top = game.stack:top()
    if top and top.cards then break end
    U.wait(1)
  end
  local gear = game.stack:top()
  assert(gear and gear.cards, "the Pokegear did not open")
  gear.mode = "card"
  for index, card in ipairs(gear.cards) do
    if card.id == "phone" then gear.cardIndex = index end
  end
  U.wait(2)
  tap("a", 3) -- CALL/DELETE/CANCEL submenu on Joey's slot
  tap("a", 3) -- CALL
  local spoke = false
  for _ = 1, 200 do
    local top = game.stack and game.stack:top()
    local textAll = boxText(top)
    if textAll and textAll:find("JOEY", 1, true) then spoke = true end
    if not (w.vm and w.vm:running()) and not (top and top.pages) then break end
    tap("a", 2)
  end
  ok(gear.call ~= nil, "the card holds the placed call")
  ok(gear.call and gear.call.script == "JoeyPhoneCalleeScript",
    "to Joey's own SCRIPT1")
  ok(gear.call and gear.call.ranScript == true,
    "which ran through the overworld VM")
  ok(spoke, "and he actually talked")
  tap("a", 3) -- hang up
  ok(gear.call == nil, "A hangs the call up")

  print(fails == 0 and "PASS gold_phone_call"
    or ("FAIL gold_phone_call (%d)"):format(fails))
  love.event.quit(fails == 0 and 0 or 1)
end
