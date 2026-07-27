-- Driver: party menu cursor alignment (#278).  A manual eye check, not a
-- pass/fail run -- no assertion in this repo can judge where a triangle
-- sits against a reference screenshot.
--
-- pokered evidence.  home/pokemon.asm PartyMenuInit seeds the shared menu
-- cursor coordinates:
--
--   ld hl, wTopMenuItemY
--   inc a          ; a = 1
--   ld [hli], a    ; top menu item Y
--   xor a
--   ld [hli], a    ; top menu item X
--
-- and home/window.asm PlaceMenuCursor walks that many rows down from
-- hlcoord 0, 0.  Meanwhile party_menu.asm RedrawPartyMenu_ starts the name
-- column at hlcoord 3, 0.  So a party entry's name is on tile row 0 while
-- its cursor belongs on tile row 1: the level/HP line, level with the
-- middle of the two-row icon.
--
-- The bug: PartyMenu drew the cursor at entryY(i), the name row, putting it
-- a full tile (8px) too high on every slot.  The fix draws it at y + 8.
--
-- Do NOT run this under POKEPORT_SPEED.  Fast-forward scales only the logic
-- clock while rendering and audio run on their own real-time accumulators
-- (src/core/Game.lua), so a sped-up run can capture a half-drawn frame.
--
--   POKEPORT_DRIVER=tests/drivers/party_cursor_bug278_test.lua POKEPORT_IDENTITY=bug278 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Screens = require("src.ui.Screens")
  local PartyMenu = require("src.ui.PartyMenu")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- ---- preconditions a human's eye cannot separate from the bug ----------
  -- A cursor drawn off-screen, or a party too short to show the stride,
  -- both look exactly like "the offset is wrong".  Check them first.

  -- the geometry contract the fix depends on: 16px stride, name row at the
  -- top of each entry.  If entryY ever changes, the +8 has to be revisited.
  check("entryY stride is 16px", PartyMenu.entryY(2) - PartyMenu.entryY(1) == 16)
  check("slot 1 name row is y=0", PartyMenu.entryY(1) == 0)

  game.save.party = {
    Pokemon.new(game.data, "CHARIZARD", 50),
    Pokemon.new(game.data, "PIKACHU", 30),
    Pokemon.new(game.data, "SNORLAX", 77),
    Pokemon.new(game.data, "BULBASAUR", 12),
  }
  game.save.player.name = "bryan"
  check("party has enough slots to judge the stride", #game.save.party >= 3)

  -- the window actually rendered: a black frame is not an offset bug
  check("renderer is up", game.renderer ~= nil)

  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(20)

  Screens.push(game, "PartyMenu")
  U.wait(30)
  check("party menu is on top", game.stack:top() ~= nil)

  U.shot(game, "bug278_party_cursor_slot1.png")

  -- move the cursor down so the stride is visible too: a fix that is right
  -- on slot 1 and wrong further down would otherwise read as a pass
  U.tap(game, "down")
  U.wait(15)
  U.shot(game, "bug278_party_cursor_slot2.png")
  U.tap(game, "down")
  U.wait(15)
  U.shot(game, "bug278_party_cursor_slot3.png")

  U.log("........................................................")
  U.log("LOOK NOW: the party menu is open. Screenshots were written to the")
  U.log("  LOVE save dir as bug278_party_cursor_slot1/2/3.png.")
  U.log("  RIGHT: the black triangle sits on the LOWER of each entry's two")
  U.log("         rows, level with the LEVEL/HP line and with the middle of")
  U.log("         the two-row party icon.")
  U.log("  BUG #278 looks like: the triangle riding up on the NAME row, its")
  U.log("         tip level with the first letter of the nickname.")
  U.log("  ALSO WRONG: correct on slot 1 but drifting on slots 2-4 (that is")
  U.log("         a stride bug, not an offset bug), or the triangle sliding")
  U.log("         a half tile so it straddles both rows.")
  U.log("Compare against the reference shot in issue #278. Input is yours")
  U.log("from here: up/down re-checks every slot, B closes the menu.")
  U.log("........................................................")

  while true do
    coroutine.yield()
  end
end
