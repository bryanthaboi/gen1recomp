-- Driver: the bag's USE/TOSS submenu box (#284).  A manual eye check, not a
-- pass/fail run.
--
-- pokered evidence.  data/text_boxes.asm pins the whole thing as one entry:
--
--   text_box_text USE_TOSS_MENU_TEMPLATE, 13, 10, 19, 14, UseTossText, 15, 11
--   ; text box ID, upper-left X, upper-left Y, lower-right X, lower-right Y,
--   ; text pointer, text X, text Y
--
-- so the box covers tiles (13,10)-(19,14) and "USE" starts at tile (15,11).
-- engine/menus/start_sub_menus.asm then sets wTopMenuItemY/X to 11/14 for
-- the cursor, and UseTossText is "USE" + next "TOSS", i.e. two rows.
--
-- The bug: the port opened the submenu with a (12,10) 8x6 box, one column
-- too wide on the left and one row too tall at the bottom.  The labels
-- themselves were already on the right pixel rows, but the extra bottom row
-- left them stranded near the top edge, which is what reads as "too high".
-- The fix passes the real geometry (13,10,7,5); src/ui/Menu.lua derives the
-- label and cursor columns from the box, so it needed no change and its
-- eight other callers are untouched.
--
-- Do NOT run this under POKEPORT_SPEED: fast-forward scales only the logic
-- clock, so a sped-up run can capture a half-drawn frame.
--
--   POKEPORT_DRIVER=tests/drivers/bag_usetoss_bug284_test.lua POKEPORT_IDENTITY=bug284 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Screens = require("src.ui.Screens")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- ---- preconditions the eye cannot separate from the bug ----------------
  -- An empty bag, or an item whose branch skips the submenu, both end with
  -- "no USE/TOSS box on screen", which looks identical to a broken box.

  game.save.party = { Pokemon.new(game.data, "CHARIZARD", 50) }
  game.save.player.name = "bryan"
  game.save.inventory = game.save.inventory or {}
  game.save.inventory.POTION = 3
  check("a usable, tossable item is in the bag",
        (game.save.inventory.POTION or 0) > 0)

  -- BICYCLE short-circuits straight past the submenu in the original
  -- (start_sub_menus.asm `cp BICYCLE / jp z, .useOrTossItem`), and the port
  -- mirrors that, so the first item must not be the bike.
  check("POTION is not a submenu-skipping item",
        game.data.items.POTION ~= nil and not game.data.items.POTION.keyItem)

  check("renderer is up", game.renderer ~= nil)

  U.teleport(game, "PALLET_TOWN", 10, 8, "down")
  U.wait(20)

  Screens.push(game, "BagMenu")
  U.wait(30)
  U.shot(game, "bug284_bag_list.png")

  -- A on the first item opens USE/TOSS
  U.tap(game, "a")
  U.wait(30)
  U.shot(game, "bug284_usetoss.png")

  U.log("........................................................")
  U.log("LOOK NOW: the USE/TOSS box should be open over the bag list.")
  U.log("  Screenshot: bug284_usetoss.png in the LOVE save dir.")
  U.log("  RIGHT: a box hugging the bottom-right corner, its border running")
  U.log("         tiles (13,10) to (19,14). USE and TOSS sit on alternating")
  U.log("         rows with the cursor one column to their left, and there")
  U.log("         is exactly one border row below TOSS -- no empty gap.")
  U.log("  BUG #284 looks like: a roomier box whose labels crowd the top,")
  U.log("         with a blank row of dead space under TOSS, and the whole")
  U.log("         box starting one column further left than the original.")
  U.log("  ALSO WRONG: labels pushed down but the box left oversized (that")
  U.log("         moves the text off pokered's row 11), or the cursor column")
  U.log("         no longer lining up one tile left of the labels.")
  U.log("Compare against the original screenshot in issue #284.")
  U.log("Input is yours from here: up/down moves between USE and TOSS.")
  U.log("........................................................")

  while true do
    coroutine.yield()
  end
end
