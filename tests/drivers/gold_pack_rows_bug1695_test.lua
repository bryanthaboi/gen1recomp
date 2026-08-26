-- The PACK's TM/HM rows (#1695), the list cursor's colour (#1694) and the rows
-- a message prints on in the description box (#1725).
-- engine/items/tmhm.asm:355-403 and engine/gfx/cgb_layouts.asm:723-726 (pokegold).
--
--   POKEPORT_IDENTITY=gold-dev POKEPORT_GAME=gold POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/gold_pack_rows_bug1695_test.lua \
--     POKEPORT_SHOT_DIR=/tmp/gold-pack-rows love .
--
-- No POKEPORT_SPEED: it scales the logic clock only, so every shot here would
-- race the keypress that redrew the list.
local U = require("tests.drivers.util")

local Bag = require("src.inventory.Bag")
local GbcPalette = require("src.render.GbcPalette")
local PackMenu = require("src.ui.gen2.PackMenu")

-- ../pokecrystal/maps/NewBarkTown.asm:287 -- the tile in front of the player's
-- own front door.  An outdoor map is what makes the ESCAPE ROPE below print
-- OakThisIsntTheTimeText instead of warping the PACK shut.
local HOME = { map = "NEW_BARK_TOWN", x = 13, y = 6 }

-- One-digit and two-digit counts side by side, both HM ends of the pocket, and
-- the two key items whose submenus reach a SEL and a USE.
local SEED = {
  { "POTION", 5 },
  { "SUPER_POTION", 50 },
  { "ESCAPE_ROPE", 3 },
  { "POKE_BALL", 7 },
  { "GREAT_BALL", 12 },
  { "ITEMFINDER", 1 },
  { "BICYCLE", 1 },
  { "TM_DYNAMICPUNCH", 1 },
  { "TM_HEADBUTT", 3 },
  { "TM_THUNDER", 24 },
  { "HM_CUT", 1 },
  { "HM_SURF", 1 },
  { "HM_WATERFALL", 1 },
}

-- TM/HM pocket order is wTMsHMs order (engine/items/tmhm.asm:341), and each row
-- carries the number the cart prints at column 5 and the move name at column 8.
local TMHM = {
  { "TM_DYNAMICPUNCH", "01", "DYNAMICPUNCH" },
  { "TM_HEADBUTT", "02", "HEADBUTT" },
  { "TM_THUNDER", "25", "THUNDER" },
  { "HM_CUT", "H1", "CUT" },
  { "HM_SURF", "H3", "SURF" },
  { "HM_WATERFALL", "H7", "WATERFALL" },
}

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-pack-rows"
  local failed = 0

  local function pass(ok, line)
    if not ok then failed = failed + 1 end
    U.log((ok and "PASS " or "FAIL ") .. line)
  end

  local function shot(name)
    U.wait(4)
    U.shot(game, ("%s/%s.png"):format(out, name))
  end

  local function tap(button, frames)
    U.tap(game, button)
    U.wait(frames or 5)
  end

  U.wait(45)
  assert(game.world and game.world.map, "gold world did not boot")

  local world, save = game.world, game.save

  -- A later map edit must not park the player against a wall: try the door
  -- tile, then any free neighbour of it.
  local placed = world:setMap(HOME.map, HOME.x, HOME.y, "down")
  if not placed then
    for _, step in ipairs({ { 0, -1 }, { 1, 0 }, { -1, 0 }, { 0, 1 } }) do
      placed = world:setMap(HOME.map, HOME.x + step[1], HOME.y + step[2], "down")
      if placed then break end
    end
  end
  U.wait(12)

  local mapId = world.map and world.map.id
  local env = world.map and world.map.def and world.map.def.environment
  pass(placed and env ~= "CAVE" and env ~= "DUNGEON",
    ("standing in %s (environment %s), where an ESCAPE ROPE has nowhere to " ..
     "pay out to"):format(tostring(mapId), tostring(env)))

  save.inventory = {}
  save.bagOrder = {}
  for _, entry in ipairs(SEED) do
    local id, count = entry[1], entry[2]
    if game.data.items and game.data.items[id] then
      save.inventory[id] = count
      table.insert(save.bagOrder, id)
    else
      pass(false, id .. " is not in this cache, so its row will be missing")
    end
  end
  Bag.order(save, { items = game.data.items })

  -- A probe pack for the checks, so the one on screen opens on a clean cursor.
  local probe = PackMenu.new(game, { save = save, world = world,
    pocket = "TM_HM" })

  for i, want in ipairs(TMHM) do
    local row = probe.rows[i]
    pass(row and row.id == want[1] and row.tmhmLabel == want[2],
      ("row %d is %s and its number reads %q (got %s / %s)"):format(
        i, want[1], want[2], tostring(row and row.id),
        tostring(row and row.tmhmLabel)))
    pass(row and row.teaches == want[3],
      ("row %d prints the move name %q rather than the item name %s"):format(
        i, want[3], tostring(row and row.name)))
  end

  pass(probe.gfx and probe.gfx:available(),
    "this cache has the PACK's own tiles, so the screen is the cart's chrome " ..
    "and not the fallback boxes")
  pass(GbcPalette.available(),
    "the palette shader is loaded, so a coloured cursor is drawable at all")
  pass(GbcPalette.mode == "gbc",
    ("colour mode is %q; anything else draws the cursor in DMG greys and " ..
     "looks exactly like the bug"):format(tostring(GbcPalette.mode)))

  local cursorPal = probe.gfx and probe.gfx:available()
    and probe.gfx:colorsAt(7, 2)
  local ink = cursorPal and cursorPal[4]
  pass(ink and ink[1] == 255 and ink[2] == 0 and ink[3] == 0,
    ("the cursor column (7,2) resolves to a palette whose colour 3 is " ..
     "255,0,0 (got %s)"):format(ink and table.concat(ink, ",") or "nil"))
  local lastPal = probe.gfx and probe.gfx:available()
    and probe.gfx:colorsAt(7, 10)
  pass(lastPal == cursorPal,
    "and the fifth list row's cursor cell (7,10) is in the same 1x9 zone")

  local finder = game.data.items and game.data.items.ITEMFINDER
  pass(finder and finder.canSelect == true and world.registerItem ~= nil,
    "the ITEMFINDER is registerable, so SEL prints \"Registered the\" and " ..
    "not the refusal")
  local rope = game.data.items and game.data.items.ESCAPE_ROPE
  pass(rope and rope.fieldMenu ~= "ITEMMENU_NOUSE",
    "the ESCAPE ROPE's submenu carries a USE row to reach the three-line " ..
    "OAK message with")

  if failed > 0 then
    U.log(("%d check(s) failed above, so the shots below cannot be read as " ..
      "a pass."):format(failed))
  end

  game.packCursor = nil
  local pack = PackMenu.new(game, { save = save, world = world,
    onClose = function() game.stack:pop() end })
  game.stack:push(pack)

  U.log("00-items: the arrow beside POTION should be the same red as the")
  U.log("pocket plaque on the left, not black. black in every pocket means")
  U.log("the palette never reached it (#1694).")
  shot("00-items")

  tap("select")
  tap("down")
  U.log("01-items-select: row 1 now carries the hollow arrow and row 2 the")
  U.log("solid one, both red. \"Where should this\" / \"be moved to?\" sit on")
  U.log("rows 14 and 16 with a blank row between them (#1725).")
  U.log("switching row is " .. tostring(pack.switching) ..
    ", cursor on " .. tostring(pack.index))
  shot("01-items-select")
  tap("b")
  tap("up")

  tap("right")
  shot("02-balls")
  tap("right")
  shot("03-key-items")
  U.log("02 and 03: same red arrow in POKe BALLS and KEY ITEMS.")

  tap("right")
  U.log("04-tmhm-top: the rows read \"01 DYNAMICPUNCH\", \"02 HEADBUTT\",")
  U.log("\"25 THUNDER\", \"H1 CUT\", \"H3 SURF\". the number is hard against the")
  U.log("left edge of the item area where the blue pattern column ends, the")
  U.log("arrow one tile later, the move name from column 8. the word TM or HM")
  U.log("printed anywhere, or a right-aligned number, is the bug (#1695).")
  U.log("pocket is " .. tostring(pack:pocket().id) ..
    " with " .. tostring(#pack.rows) .. " rows")
  shot("04-tmhm-top")

  for _ = 1, 5 do tap("down") end
  U.log("05-tmhm-hms: scrolled to the last HM. \"H7 WATERFALL\" reads with a")
  U.log("single digit and no count; \"H07\" would mean the TM branch took it.")
  U.log("the three TM rows above it still carry their xNN on the line below.")
  shot("05-tmhm-hms")

  tap("left")
  tap("left")
  tap("left")
  tap("a")
  tap("down")
  tap("down")
  tap("a")
  U.log("06-toss-how-many: \"Throw away how\" on row 14 and \"many?\" on row 16,")
  U.log("with a full blank row between them and the first line clear of the")
  U.log("box's top border. adjacent lines mean the message path is still")
  U.log("single-spaced (#1725).")
  U.log("message is " ..
    (pack.message and table.concat(pack.message, " / ") or "nil"))
  shot("06-toss-how-many")

  tap("b")
  tap("down")
  tap("down")
  tap("a")
  tap("a")
  U.log("07-oak-three-lines: a message too tall for two rows still packs one")
  U.log("row apart, so \"OAK: GOLD!\" / \"This isn't the\" / \"time to use that!\"")
  U.log("fill rows 13, 14 and 15. a gap here would clip the third line.")
  U.log("message is " ..
    (pack.message and table.concat(pack.message, " / ") or "nil"))
  shot("07-oak-three-lines")

  tap("b")
  tap("right")
  tap("right")
  tap("a")
  tap("down")
  tap("a")
  U.log("08-registered: the case the report filed. \"Registered the\" on row 14")
  U.log("and \"ITEMFINDER.\" on row 16, lining up with the item description")
  U.log("that shares this box. row 13 plus row 14 is the old behaviour; row 15")
  U.log("plus a clipped row 17 means the offset went the other way.")
  U.log("message is " ..
    (pack.message and table.concat(pack.message, " / ") or "nil"))
  shot("08-registered")

  U.log("shots in " .. out .. "; the PACK is open on KEY ITEMS, controls yours")

  while true do
    coroutine.yield()
  end
end
