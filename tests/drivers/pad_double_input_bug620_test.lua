-- Hands-on check that a mapped controller sends one press per button (#620).
-- SDL raises love.gamepadpressed AND love.joystickpressed for the same
-- physical button on any pad it has a database entry for; the raw fallback in
-- src/core/Input.lua now stands down for those pads.  No pokered behavior is
-- involved, this is platform input plumbing only.  Do not set POKEPORT_SPEED:
-- fast-forward reorders the logic clock against real input and audio.
--   POKEPORT_DRIVER=tests/drivers/pad_double_input_bug620_test.lua POKEPORT_IDENTITY=bug620 POKEPORT_TOUCH=0 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Screens = require("src.ui.Screens")
  local Bag = require("src.inventory.Bag")

  -- pokered data/maps/objects/PalletTown.asm: warp_event 5, 5 is the player's
  -- house door, so the cell below it is open ground with no object on it.
  -- Any walkable cell would do, the bag is what is being looked at.
  local MAP = "PALLET_TOWN"
  local STAND = { x = 5, y = 6, facing = "down" }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- A pad nobody plugged in fails exactly like a pad whose events are being
  -- dropped, so name the stick before anything else.
  local pads, mapped = {}, 0
  if love.joystick then
    for _, j in ipairs(love.joystick.getJoysticks()) do
      local isPad = j.isGamepad and j:isGamepad()
      if isPad then mapped = mapped + 1 end
      pads[#pads + 1] = j:getName() .. (isPad and " (SDL-mapped)" or " (raw stick)")
    end
  end
  check("a controller is connected", #pads > 0)
  check("SDL maps at least one of them, which is the pad #620 is about",
        mapped > 0)
  if #pads > 0 then U.log("pads:", table.concat(pads, ", ")) end

  -- The gate itself, driven with a stub that answers isGamepad like a mapped
  -- pad does.  Cross-file contract with main.lua's love.joystick* forwarders:
  -- these three entry points must all ignore a mapped pad, because its press
  -- already arrived through gamepadpressed this frame.  Raw index 9 is SELECT
  -- in RAW_BUTTON_BINDINGS, which is the button iOS's MFi packing slid the
  -- D-pad onto.
  local stub = { isGamepad = function() return true end }
  local input = game.input
  input:joystickpressed(stub, 9)
  input:joystickhat(stub, 1, "l")
  input:joystickaxis(stub, 1, -0.9)
  local rawSelect = input.sources.select and input.sources.select["joy:9"]
  local rawHat = (input.hatDirs[1] or {})[1] ~= nil
  local rawStick = input.stickDir ~= nil
  check("a mapped pad's raw button index is ignored", not rawSelect)
  check("a mapped pad's raw hat is ignored", not rawHat)
  check("a mapped pad's raw axis is ignored", not rawStick)
  -- leave nothing held behind if one of those did land (nil = raw stick)
  if rawSelect then input:joystickreleased(nil, 9) end
  if rawHat then input:joystickhat(nil, 1, "c") end
  if rawStick then input:joystickaxis(nil, 1, 0) end

  -- The launcher half runs before Game exists, so this driver can never reach
  -- it; confirm its copy of the gate is still in the file at least.
  local src = love.filesystem.read("src/import/RomImporter.lua") or ""
  check("the launcher keeps its own copy of the gate",
        src:find("isMappedPad", 1, true) ~= nil)

  -- The swap beep is the audible half of a wrong press.
  local opts = game.save.options or {}
  check("sfxVol is not zero (" .. tostring(opts.sfxVol or 7) .. ")",
        (opts.sfxVol or 7) ~= 0)
  check("renderer is up", game.renderer ~= nil)

  game.save.party = { Pokemon.new(game.data, "CHARIZARD", 50) }
  game.save.player.name = "bryan"
  game.save.inventory = game.save.inventory or {}
  game.save.inventory.POTION = 3
  game.save.inventory.ANTIDOTE = 2
  -- one item can be marked for a swap but never traded with anything, which
  -- hides half the near-miss
  check("the bag holds at least two swappable items",
        #Bag.order(game.save) >= 2)

  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(10)
  local ow = game.overworld
  if ow and ow.map and not ow.map:isWalkableCell(STAND.x, STAND.y) then
    -- a map edit moved the door: any free walkable neighbour is as good
    local sides = { { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }
    for _, s in ipairs(sides) do
      local cx, cy = STAND.x + s[1], STAND.y + s[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log(("(%d, %d) is blocked, standing on"):format(STAND.x, STAND.y),
              cx, cy)
        U.teleport(game, MAP, cx, cy, STAND.facing)
        U.wait(10)
        break
      end
    end
  end

  local list = Screens.push(game, "BagMenu")
  U.wait(20)
  -- ListMenu:update checks up/down before SELECT in one elseif chain and the
  -- bag sets no pageJump, so left is inert there and a stray SELECT in the
  -- same step is what actually fires (src/ui/ListMenu.lua, swap_items.asm).
  check("the bag list answers SELECT with a swap",
        list ~= nil and list.onSelectKey ~= nil)
  check("left and right do nothing in this list", list ~= nil and not list.pageJump)

  U.tap(game, "down") -- park on the second item so a swap has somewhere to go
  U.wait(20)
  U.shot(game, "bug620_bag.png")

  U.log("The bag is open with the cursor on the second item. Press D-pad left")
  U.log("once on the pad: the cursor should stay put and the list should not")
  U.log("change at all. If the press also counts as SELECT the item under the")
  U.log("cursor gets picked up for a swap and draws differently, and a second")
  U.log("left press trades it with its neighbour with a beep. Up and down move")
  U.log("normally, B closes the bag. The launcher half of #620 needs a boot")
  U.log("with data/generated missing, which no driver can reach.")

  while true do
    coroutine.yield()
  end
end
