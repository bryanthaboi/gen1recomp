-- RedrawPartyMenu_ (engine/menus/start_sub_menus.asm:660-693).
--   POKEPORT_DRIVER=tests/drivers/party_swap_anim_bug2059_test.lua POKEPORT_IDENTITY=bug2059 POKEPORT_TOUCH=0 POKEPORT_VERSION=red SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Screens = require("src.ui.Screens")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  game.save.party = {
    Pokemon.new(game.data, "RATTATA", 12),
    Pokemon.new(game.data, "PIDGEY", 14),
    Pokemon.new(game.data, "MAGIKARP", 16),
  }
  game.save.player.name = "bryan"

  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(10)

  Screens.push(game, "PartyMenu")
  U.wait(5)
  local pm = game.stack:top()

  U.tap(game, "a")
  U.wait(2)
  for _ = 1, 6 do
    local entry = (pm.subItems or {})[pm.subIndex]
    if entry and entry.action == "switch" then break end
    U.tap(game, "down")
    U.wait(2)
  end
  U.tap(game, "a")
  U.wait(2)
  check("slot 1 is picked up (Move POKeMON where?)", pm.swapFrom == 1)
  U.shot(game, DIR .. "/bug2059_picked.png")

  U.tap(game, "down")
  U.wait(2)
  U.tap(game, "down")
  U.wait(2)
  check("cursor on slot 3", pm.index == 3)

  U.tap(game, "a")
  check("party swapped on the confirming frame",
        game.save.party[1].species == "MAGIKARP"
        and game.save.party[3].species == "RATTATA")
  check("the swapped-from row is blanked",
        pm.swapAnim ~= nil and pm.swapAnim.blank[1] == true)
  U.shot(game, DIR .. "/bug2059_blank.png")

  -- the second SwitchPartyMon_ClearGfx (start_sub_menus.asm:664-666)
  U.wait(1)
  check("the destination row blanks too (#2126)",
        pm.swapAnim ~= nil and pm.swapAnim.blank[3] == true)
  U.shot(game, DIR .. "/bug2126_both_blank.png")

  U.wait(40)
  check("the row is back after the second SFX_SWAP", pm.swapAnim == nil)
  U.shot(game, DIR .. "/bug2059_redrawn.png")

  U.log("bug2059_blank.png should show row 1 EMPTY (no icon, no name, no HP")
  U.log("bar, no cursor) while the swap sound plays; bug2126_both_blank.png")
  U.log("should show rows 1 AND 3 empty at the same time; bug2059_redrawn.png")
  U.log("should show the full list with MAGIKARP first and RATTATA third.")
  U.log("Listen for TWO swap beeps, not one.  Input is yours now: press A")
  U.log("twice on the same slot -- the row should still blank and beep.")

  while true do
    coroutine.yield()
  end
end
