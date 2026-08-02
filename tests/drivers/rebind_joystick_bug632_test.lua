-- Manual check that a rebind on a real controller actually takes (#632).
-- LOVE raises love.joystickpressed for EVERY stick, gamepads included, so
-- Input's fixed raw table used to re-assert the factory A/B/START/SELECT map
-- underneath a CONTROLS rebind: only a plugged-in pad makes that duplicate
-- event happen at all, which is why no test can stand in for a hand here.
-- Rebinding is port-only (gap C2), so there is no pokered file to cite; the
-- map position below comes from pokered data/maps/objects/PalletTown.asm.
--   POKEPORT_DRIVER=tests/drivers/rebind_joystick_bug632_test.lua POKEPORT_IDENTITY=bug632 POKEPORT_TOUCH=0 love .
-- Do not set POKEPORT_SPEED: fast-forward scales the logic clock only, and a
-- press that lands between two stepped frames is the very thing being judged.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Screens = require("src.ui.Screens")
  local BindingsMenu = require("src.ui.BindingsMenu")
  local Input = require("src.core.Input")

  -- pokered data/maps/objects/PalletTown.asm: warp_event 5, 5 is the player's
  -- own front door, so the path cell below it is open ground with nothing to
  -- walk into by accident while the pad is being mashed.
  local MAP = "PALLET_TOWN"
  local STAND = { x = 5, y = 6, facing = "down" }
  local ROW_A = 5 -- BindingsMenu's BUTTONS order: up, down, left, right, A

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- A pad that SDL has no database entry for and a pad it recognizes behave
  -- differently on purpose, and only the second one is plugged in here.
  local sticks = (love.joystick and love.joystick.getJoysticks
                  and love.joystick.getJoysticks()) or {}
  local recognized = nil
  for _, js in ipairs(sticks) do
    if js.isGamepad and js:isGamepad() then recognized = recognized or js end
    U.log("stick:", js:getName(),
          (js.isGamepad and js:isGamepad()) and "(SDL gamepad)" or "(raw)")
  end
  check("a controller is plugged in", #sticks > 0)
  check("at least one of them is an SDL-recognized gamepad", recognized ~= nil)

  -- The three halves of the fix that can be read off in-process: the raw
  -- lookup table applyBindings now builds, the guard that keeps a recognized
  -- pad off the raw path, and BindingsMenu's raw capture hooks.
  check("Input:applyBindings built the raw joyBindings table",
        type(Input.joyBindings) == "table" and Input.joyBindings[1] == "a")
  check("BindingsMenu has the raw-stick capture hooks",
        type(BindingsMenu.captureJoy) == "function"
        and type(BindingsMenu.captureJoyRelease) == "function")
  check("Game routes joystick presses", type(game.joystickpressed) == "function")

  -- Probe the guard with a stand-in gamepad rather than the live pad, so the
  -- log says which of the two paths answered without asking for a press yet.
  local fakePad = { isGamepad = function() return true end }
  Input:reset()
  Input:joystickpressed(fakePad, 1)
  check("a recognized pad's duplicate joystick press is ignored",
        not Input:isDown("a"))
  Input:joystickhat(fakePad, 1, "u")
  check("and its duplicate hat event is ignored too", not Input:isDown("up"))
  -- a nil joystick is how the raw path is reachable without a raw stick on
  -- the desk; tests/input_hold_test.lua drives it the same way
  Input:joystickpressed(nil, 1)
  check("a stick SDL does not recognize still presses A", Input:isDown("a"))
  Input:joystickreleased(nil, 1)
  Input:reset()

  -- Guide and the stick clicks are in no binding table, which is what makes
  -- them dead buttons rather than something that quietly fires START.
  check("Guide is unbound", Input.padBindings.guide == nil)
  check("the left stick click is unbound", Input.padBindings.leftstick == nil)

  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(10)

  -- a map edit or a mod could put something on the door path; any free
  -- neighbour is just as good, the position only has to be somewhere quiet
  local ow = game.overworld
  if ow and ow.map and not ow.map:isWalkableCell(STAND.x, STAND.y) then
    for _, d in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
      local cx, cy = STAND.x + d[1], STAND.y + d[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log(("cell (%d, %d) is blocked, standing on"):format(STAND.x, STAND.y),
              cx, cy)
        U.teleport(game, MAP, cx, cy, STAND.facing)
        U.wait(10)
        break
      end
    end
  end

  -- Open the screen the same way the START menu does, one push per level, so
  -- backing out with B lands on OPTION and then on the overworld exactly as
  -- it would have if the human had walked the menus.
  Screens.push(game, "OptionsMenu")
  U.wait(10)
  Screens.push(game, "BindingsMenu")
  U.wait(10)

  local menu = game.stack:top()
  local isBindings = getmetatable(menu) == BindingsMenu
  check("the CONTROLS screen is open", isBindings)

  if isBindings then
    for _ = 1, ROW_A - 1 do
      U.tap(game, "down")
      U.wait(6)
    end
    check("the cursor is parked on the A row",
          menu.index == ROW_A and menu.items[ROW_A].button.id == "a")
    U.log("the A row currently reads", menu.items[ROW_A].right)
    check("the B row reads its defaults too",
          menu.items[ROW_A + 1] ~= nil
          and menu.items[ROW_A + 1].right:find("/", 1, true) ~= nil)
  end

  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  if U.shot(game, SHOT_DIR .. "/bug632_controls.png") then
    check("the window rendered", true)
    U.log("captured", SHOT_DIR .. "/bug632_controls.png")
  else
    check("the window rendered", false)
  end

  U.log("CONTROLS is open with the cursor on the A row. Press A to arm it,")
  U.log("then press and release the pad's B button: the rows should end up")
  U.log("reading Z/B and X/A. Back out with B twice and open START with the")
  U.log("pad. The physical B should confirm and the physical A should cancel,")
  U.log("one action per press. If A both confirms and cancels in the same")
  U.log("frame (a menu that opens and shuts, or text jumping two pages), the")
  U.log("raw table is still answering alongside the gamepad map. Guide and a")
  U.log("left-stick click should do nothing at all out in the overworld.")

  while true do
    coroutine.yield()
  end
end
