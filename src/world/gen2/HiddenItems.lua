-- Hidden items: engine/events/checkforhiddenitems.asm (the ITEMFINDER sweep)
-- and the BGEVENT_ITEM arm of the bg event dispatch (`.itemifset` in
-- engine/overworld/events.asm, reached from home/map.asm
-- CheckIfFacingTileCoordIsBGEvent), whose body is HiddenItemScript
-- (engine/events/hidden_item.asm).
--
-- A `bg_event x, y, BGEVENT_ITEM, Label` does NOT name a script.  Its operand
-- points at `hiddenitem item, flag`, three bytes laid down by `dwb flag, item`
-- (macros/scripts/maps.asm), and the extractor now carries those two numbers on
-- the bg event row as `hiddenItem = { item, event }` instead of disassembling
-- them.  Eighty-seven of them exist; nothing in the port could reach one,
-- because World:bgEventAt only ever answered for BGEVENT_READ.
--
-- love-free: the caller supplies the map def, the player cell, the flag store
-- and a name-to-id sfx resolver, and gets back a command list for the VM.

local CommonText = require("src.core.gen2.CommonText")
local RomText = require("src.core.RomText")

local HiddenItems = {}

-- constants/script_constants.asm BGEVENT_*.
HiddenItems.BGEVENT_ITEM = 7

-- constants/hardware.inc: the screen is 20x18 TILES, and a walk cell is two
-- tiles on a side, so SCREEN_WIDTH / 4 and SCREEN_HEIGHT / 4 are half a screen
-- in the cell units bg_event coordinates and wXCoord/wYCoord both use.  RGBDS
-- divides integers, so 18 / 4 is 4 and 18 / 2 is 9: the sweep box is NOT
-- symmetric about the player and transcribing it as one loses a row.
local HALF_SCREEN_X, HALF_SCREEN_Y = 5, 4
local SCREEN_CELLS_X, SCREEN_CELLS_Y = 10, 9

-- constants/sfx_constants.asm, resolved by LABEL at call time; the ids here are
-- only the fallback for a cache whose sfx table sits somewhere else.
local SFX_SECOND_PART_OF_ITEMFINDER = { "Sfx_SecondPartOfItemfinder", 18 }
local SFX_TRANSACTION = { "Sfx_Transaction", 34 }
local SFX_ITEM = { "Sfx_Item", 1 }

-- data/text/common_1.asm:998, data/text/common_2.asm:220
local TEXT_PLAYER_FOUND = "_PlayerFoundItemText"
local TEXT_BUT_NO_SPACE = "_ButNoSpaceText"
local TEXT_ITEMFINDER_NEARBY = "_ItemfinderItemNearbyText"
local TEXT_ITEMFINDER_NOPE = "_ItemfinderNopeText"

-- engine/events/misc_scripts.asm:9
local TEXT_FOUND_ITEM = "_FoundItemText"
local TEXT_CANT_CARRY = "_CantCarryItemText"

local function romLine(data, label)
  return CommonText.plain(RomText(data, label, nil))
end

-- The `hiddenitem` pair on a bg event row, or nil when the row is not one.
function HiddenItems.dataOf(bgEvent)
  if type(bgEvent) ~= "table" then return nil end
  if bgEvent.kind ~= HiddenItems.BGEVENT_ITEM then return nil end
  local data = bgEvent.hiddenItem
  if type(data) ~= "table" or not data.item then return nil end
  return data
end

-- Every still-unfound hidden item on a map, in bg_event order.  `events` is the
-- wEventFlags store (src/world/gen2/Events.lua); a nil one means "nothing found
-- yet", which is what a test harness without a save wants.
function HiddenItems.unfound(mapDef, events)
  local out = {}
  for _, ev in ipairs((mapDef and mapDef.bgEvents) or {}) do
    local data = HiddenItems.dataOf(ev)
    if data and not (events and events:get(data.event)) then
      out[#out + 1] = { x = ev.x, y = ev.y, item = data.item, event = data.event }
    end
  end
  return out
end

-- CheckForHiddenItems, spelled out because the box is easy to get wrong.
--
-- The cart takes the BOTTOM RIGHT corner of the screen (player + half a screen
-- on each axis) and, for each bg event, computes corner minus event coordinate
-- as an unsigned byte.  Carry -- the event is past the corner -- skips it, and
-- so does a difference of a whole screen or more.  So the surviving box is
--
--   x in [player - 4 .. player + 5]   (10 cells, the player left of centre)
--   y in [player - 4 .. player + 4]   (9 cells, the player centred)
--
-- which is the visible screen, not a radius: this is the same "is it on
-- screen" test the object engine uses, and the ITEMFINDER really does answer
-- for an item the player can see but has walked past.
function HiddenItems.onScreen(px, py, ex, ey)
  local dx = (px + HALF_SCREEN_X) - ex
  local dy = (py + HALF_SCREEN_Y) - ey
  if dx < 0 or dx >= SCREEN_CELLS_X then return false end
  if dy < 0 or dy >= SCREEN_CELLS_Y then return false end
  return true
end

-- The whole of CheckForHiddenItems: the first unfound hidden item on screen, or
-- nil.  The cart returns a bare carry; the row itself is returned here because
-- nothing else needs the coordinates and a caller that wants the boolean can
-- test for nil.
function HiddenItems.nearby(mapDef, px, py, events)
  if not (mapDef and px and py) then return nil end
  for _, row in ipairs(HiddenItems.unfound(mapDef, events)) do
    if HiddenItems.onScreen(px, py, row.x, row.y) then return row end
  end
  return nil
end

-- The hidden item at a cell, if the player is facing one that is still unfound.
-- `.itemifset` checks the flag FIRST and jumps to `.dontread` when it is set,
-- which is why an already-taken hidden item does not eat the A press: the
-- press falls through to TryTileCollisionEvent exactly as if the bg event were
-- not there at all.
function HiddenItems.at(mapDef, cx, cy, events)
  for _, ev in ipairs((mapDef and mapDef.bgEvents) or {}) do
    if ev.x == cx and ev.y == cy then
      local data = HiddenItems.dataOf(ev)
      if data and not (events and events:get(data.event)) then
        return { x = ev.x, y = ev.y, item = data.item, event = data.event }
      end
      return nil
    end
  end
  return nil
end

-- HiddenItemScript (engine/events/hidden_item.asm), command for command:
--
--   opentext / readmem wHiddenItemID / getitemname STRING_BUFFER_3,
--   USE_SCRIPT_VAR / writetext .PlayerFoundItemText / giveitem ITEM_FROM_MEM /
--   iffalse .bag_full / callasm SetMemEvent / specialsound / itemnotify /
--   sjump .finish
--
-- The wHiddenItemData copy `.itemifset` makes before it calls the script is
-- what the readmem and the ITEM_FROM_MEM both read; here the item is baked into
-- the list instead, because the list is built per pickup.  `callasm
-- SetMemEvent` is the flag write, and it lands only on the arm where the item
-- was really taken -- a full pack leaves the item where it is, findable again.
--
function HiddenItems.pickupScript(item, event, data)
  local bagFull = {
    { op = "promptbutton" },
    { op = "rawtext", text = romLine(data, TEXT_BUT_NO_SPACE) },
    { op = "waitbutton" },
    { op = "closetext" },
    { op = "end" },
  }
  return {
    { op = "opentext" },
    { op = "getitemname", item = item },
    { op = "rawtext", text = romLine(data, TEXT_PLAYER_FOUND) },
    { op = "giveitem", item = item, quantity = 1 },
    { op = "iffalse", script = bagFull },
    { op = "setevent", event = event },
    { op = "specialsound" },
    { op = "itemnotify" },
    { op = "closetext" },
    { op = "end" },
  }
end

-- FindItemInBallScript (engine/events/misc_scripts.asm:9), command for command:
--
--   callasm .TryReceiveItem / iffalse .no_room / disappear LAST_TALKED /
--   opentext / writetext .FoundItemText / playsound SFX_ITEM / pause 60 /
--   itemnotify / closetext / end
--
--   .no_room: opentext / writetext .FoundItemText / waitbutton /
--   writetext .CantCarryItemText / waitbutton / closetext / end
--
-- The A-press arm for an OBJECTTYPE_ITEMBALL object.  The pointer under such an
-- object is two raw bytes -- item, quantity -- so there is no bytecode for the
-- VM to start; the extractor read the pair into `def.itemball` and this list is
-- the script the cart would have run.
--
-- It is NOT HiddenItemScript with a `disappear` swapped in for the flag write,
-- which is how it read before.  `.TryReceiveItem` (misc_scripts.asm:38) does
-- BOTH the GetItemName into wStringBuffer3 and the ReceiveItem, in one callasm,
-- before a single box is drawn -- so the getitemname and the give both come
-- first here, the full-pocket branch is taken with nothing yet on screen, and
-- its arm prints the found line, waits, and only then prints the "can't carry
-- any more" line.  Three further things the hidden-item shape got wrong: the
-- sound is an unconditional `playsound SFX_ITEM`, not `specialsound` (which
-- would ring SFX_GET_TM for a TM, scripting.asm:476); `disappear` lands BEFORE
-- the text, not after the give; and the success arm holds on `pause 60` under
-- the found line before itemnotify, which is the freeze a pickup is supposed to
-- have and which was missing entirely.
--
-- `disappear` is what stands in for the hidden item's flag write:
-- World:disappearObject sets the object's own event flag
-- (EVENT_GOT_HM07_WATERFALL on the Ice Path ball is the one a run cannot do
-- without), which is what keeps the ball gone across a reload and what a route
-- row's `expect` reads.  The `.no_room` arm never reaches it, so a full pocket
-- leaves the ball findable.
--
-- The pause operand is the cart's literal 60, the same reading every other
-- transcription in the port uses (CmdQueue's `pause 30`, the fishing `pause 40`
-- in World).  Script_pause loops `ld c, 2 / call DelayFrames` per unit, so the
-- hardware holds twice the operand; that factor lives on Vm:pauseFrames, where
-- it fixes every pause at once, rather than being pre-multiplied here.
function HiddenItems.ballPickupScript(item, quantity, objectId, sfxId, data)
  local noRoom = {
    { op = "opentext" },
    { op = "rawtext", text = romLine(data, TEXT_FOUND_ITEM) },
    { op = "waitbutton" },
    { op = "rawtext", text = romLine(data, TEXT_CANT_CARRY) },
    { op = "waitbutton" },
    { op = "closetext" },
    { op = "end" },
  }
  return {
    { op = "getitemname", item = item },
    { op = "giveitem", item = item, quantity = quantity or 1 },
    { op = "iffalse", script = noRoom },
    { op = "disappear", object = objectId },
    { op = "opentext" },
    -- `playsound` leads the text rather than trailing it, and the `pause 60`
    -- rides the text row as `hold`, because of the one thing this port's box
    -- does that a MapTextbox does not: it takes its own button and pops on it.
    -- The cart prints the found line and the itemnotify line into the SAME box
    -- with `playsound SFX_ITEM / pause 60` between them and nothing that takes
    -- a box down (misc_scripts.asm:13-17).  Written straight, the port popped
    -- the found box on the press, spent the pause with an EMPTY state stack --
    -- 120 frames of bare overworld inside a single cart textbox, with Game2's
    -- play clock (only paused while a state is on the stack) counting every one
    -- of them -- and then built a second box.  `stay` + `hold` keeps the one
    -- box up for the jingle and the pause; World:showText hands it straight
    -- over to the itemnotify page in the frame the hold drains.
    { op = "playsound",
      id = sfxId and sfxId(SFX_ITEM[1], SFX_ITEM[2]) or SFX_ITEM[2] },
    { op = "rawtext", text = romLine(data, TEXT_FOUND_ITEM), stay = true, hold = 60 },
    { op = "itemnotify" },
    { op = "closetext" },
    { op = "end" },
  }
end

-- ItemFinder's two queued scripts (engine/items/itemfinder.asm).
--
-- `sfxId(label, fallback)` resolves a pokegold sfx label against this cache's
-- own table.  .ItemfinderSound is `ld c, 4` around WaitPlaySFX
-- SFX_SECOND_PART_OF_ITEMFINDER then WaitPlaySFX SFX_TRANSACTION, and
-- WaitPlaySFX waits BEFORE it plays, so the wait leads each of the eight
-- sounds rather than trailing it -- the last one is deliberately left ringing
-- under the text box.
--
-- The cart's `refreshmap` and `special UpdateTimePals` are dropped: both repair
-- the tilemap and the palettes the PACK overwrote, and the port draws the PACK
-- as a state over an untouched world.  Running the port's `refreshmap` here
-- would be a real map reload, which is a much bigger thing than the cart is
-- doing.
function HiddenItems.itemfinderScript(found, sfxId, data)
  local script = {}
  if found then
    for _ = 1, 4 do
      for _, sfx in ipairs({ SFX_SECOND_PART_OF_ITEMFINDER, SFX_TRANSACTION }) do
        script[#script + 1] = { op = "waitsfx" }
        script[#script + 1] = {
          op = "playsound",
          id = sfxId and sfxId(sfx[1], sfx[2]) or sfx[2],
        }
      end
    end
  end
  script[#script + 1] = { op = "opentext" }
  script[#script + 1] = {
    op = "rawtext",
    text = romLine(data, found and TEXT_ITEMFINDER_NEARBY or TEXT_ITEMFINDER_NOPE),
  }
  script[#script + 1] = { op = "waitbutton" }
  script[#script + 1] = { op = "closetext" }
  script[#script + 1] = { op = "end" }
  return script
end

return HiddenItems
