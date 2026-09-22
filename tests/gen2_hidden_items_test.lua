-- Hidden items: engine/events/checkforhiddenitems.asm, the BGEVENT_ITEM arm of
-- the bg event dispatch (engine/overworld/events.asm `.itemifset`) and
-- HiddenItemScript (engine/events/hidden_item.asm), plus the extractor half
-- that stopped walking a `hiddenitem` struct as bytecode.
--
-- ROM-free: `luajit tests/gen2_hidden_items_test.lua`.  The cache section at
-- the bottom SKIPs when no Gold cache is present.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 hidden items")
local check, eq = S.check, S.eq

local HiddenItems = require("src.world.gen2.HiddenItems")
local Events = require("src.world.gen2.Events")
local Vm = require("src.script.gen2.Vm")

-- maps/Route42.asm:
--   bg_event 16, 11, BGEVENT_ITEM, Route42HiddenMaxPotion
--   Route42HiddenMaxPotion: hiddenitem MAX_POTION, EVENT_ROUTE_42_HIDDEN_MAX_POTION
-- MAX_POTION is item 15 (constants/item_constants.asm) and the flag is 173
-- (constants/event_flags.asm).
local MAX_POTION, ROUTE_42_FLAG = 15, 173

local function itemRow(x, y, item, event)
  return { x = x, y = y, kind = HiddenItems.BGEVENT_ITEM,
    hiddenItem = { item = item, event = event } }
end

-- ---- the bg event row -----------------------------------------------------
do
  local row = itemRow(16, 11, MAX_POTION, ROUTE_42_FLAG)
  eq(HiddenItems.dataOf(row).item, MAX_POTION, "kind 7 carries hiddenitem data")
  eq(HiddenItems.dataOf(row).event, ROUTE_42_FLAG, "and its event flag")
  check(HiddenItems.dataOf({ x = 1, y = 1, kind = 0, scriptKey = "1:4000" }) == nil,
    "BGEVENT_READ is a sign, not an item")
  check(HiddenItems.dataOf({ x = 1, y = 1, kind = 7 }) == nil,
    "a kind 7 row from a cache that predates the decode answers nil")
  check(HiddenItems.dataOf(nil) == nil, "and nil is not a row")
end

-- ---- CheckForHiddenItems' box ---------------------------------------------
-- The corner is player + SCREEN_WIDTH / 4, SCREEN_HEIGHT / 4 = +5, +4, and the
-- differences that survive are 0..9 on x and 0..8 on y.  So the box is ten
-- cells wide with the player LEFT of centre and nine tall with the player
-- centred, and it is not a radius.
do
  local px, py = 20, 20
  check(HiddenItems.onScreen(px, py, px, py), "the player's own cell is on screen")
  check(HiddenItems.onScreen(px, py, px + 5, py), "five cells right is the last x")
  check(not HiddenItems.onScreen(px, py, px + 6, py), "six is past the corner")
  check(HiddenItems.onScreen(px, py, px - 4, py), "four cells left is the first x")
  check(not HiddenItems.onScreen(px, py, px - 5, py), "five left is a screen away")
  check(HiddenItems.onScreen(px, py, px, py + 4), "four cells down is the last y")
  check(not HiddenItems.onScreen(px, py, px, py + 5), "five down is past the corner")
  check(HiddenItems.onScreen(px, py, px, py - 4), "four cells up is the first y")
  check(not HiddenItems.onScreen(px, py, px, py - 5), "five up is a screen away")
  check(not HiddenItems.onScreen(px, py, px + 6, py + 4),
    "either axis out of range is out")
end

-- ---- the sweep ------------------------------------------------------------
do
  local def = { bgEvents = {
    { x = 3, y = 3, kind = 0, scriptKey = "1:4000" },
    itemRow(16, 11, MAX_POTION, ROUTE_42_FLAG),
    itemRow(40, 40, 32, 182),
  } }
  local events = Events.new()
  eq(#HiddenItems.unfound(def, events), 2, "two hidden items, one sign")
  local found = HiddenItems.nearby(def, 14, 10, events)
  check(found ~= nil, "the ITEMFINDER answers for the one in range")
  eq(found.item, MAX_POTION, "and hands back the item")
  eq(found.event, ROUTE_42_FLAG, "and its flag")
  check(HiddenItems.nearby(def, 30, 30, events) == nil,
    "and nothing when both are off screen")

  events:set(ROUTE_42_FLAG, true)
  check(HiddenItems.nearby(def, 14, 10, events) == nil,
    "an item already found never sets the ITEMFINDER off again")
  eq(#HiddenItems.unfound(def, events), 1, "and drops out of the unfound list")
  check(HiddenItems.nearby(def, 14, 10, nil) ~= nil,
    "with no flag store at all nothing has been found yet")
end

-- ---- the facing cell ------------------------------------------------------
do
  local def = { bgEvents = {
    { x = 3, y = 3, kind = 0, scriptKey = "1:4000" },
    itemRow(16, 11, MAX_POTION, ROUTE_42_FLAG),
  } }
  local events = Events.new()
  eq(HiddenItems.at(def, 16, 11, events).item, MAX_POTION,
    "the facing cell finds the hidden item")
  check(HiddenItems.at(def, 3, 3, events) == nil, "a sign is not one")
  check(HiddenItems.at(def, 9, 9, events) == nil, "and an empty cell is not one")
  events:set(ROUTE_42_FLAG, true)
  check(HiddenItems.at(def, 16, 11, events) == nil,
    "`.itemifset` jumps to .dontread once the flag is set")
end

-- ---- HiddenItemScript -----------------------------------------------------
do
  local script = HiddenItems.pickupScript(MAX_POTION, ROUTE_42_FLAG)
  local ops = {}
  for _, cmd in ipairs(script) do ops[#ops + 1] = cmd.op end
  eq(table.concat(ops, ","),
    "opentext,getitemname,rawtext,giveitem,iffalse,setevent,specialsound," ..
    "itemnotify,closetext,end",
    "the order is HiddenItemScript's, with readmem folded into the item")
  eq(script[4].item, MAX_POTION, "giveitem ITEM_FROM_MEM gives the found item")
  eq(script[4].quantity, 1, "one of it")
  eq(script[6].event, ROUTE_42_FLAG,
    "callasm SetMemEvent sets the flag by NUMBER")
  local fullOps = {}
  for _, cmd in ipairs(script[5].script) do fullOps[#fullOps + 1] = cmd.op end
  eq(table.concat(fullOps, ","),
    "promptbutton,rawtext,waitbutton,closetext,end",
    ".bag_full prints and stops; it sets no flag")
end

-- The same list through the real VM, which is where the ordering matters: the
-- flag must be set only on the arm that really took the item.
local function runPickup(bagFull)
  local events = Events.new()
  local log, given = {}, nil
  local vm = Vm.new({}, {}, events, {
    showText = function(body, onDone)
      log[#log + 1] = body
      if onDone then onDone() end
    end,
    getItemName = function(index)
      eq(index, MAX_POTION, "getitemname is asked for the found item")
      return "MAX POTION"
    end,
    giveItem = function(index, qty)
      if bagFull then return false end
      given = { index = index, qty = qty }
      return true
    end,
    specialSound = function() end,
    waitSfx = function() return true end,
  })
  vm:start(HiddenItems.pickupScript(MAX_POTION, ROUTE_42_FLAG))
  for _ = 1, 8 do vm:update() end
  return events, log, given
end

do
  local events, log, given = runPickup(false)
  eq(log[1], "{PLAYER} found\nMAX POTION.",
    "_PlayerFoundItemText names the item; {PLAYER} is TextBox's to fill")
  eq(given.index, MAX_POTION, "and the item lands in the pack")
  eq(given.qty, 1, "one of it")
  check(events:get(ROUTE_42_FLAG), "SetMemEvent ticks the flag off")
  eq(log[2], "{PLAYER} put the\nMAX POTION in\nthe ITEM POCKET.",
    "itemnotify is the second line")

  local fullEvents, fullLog = runPickup(true)
  check(not fullEvents:get(ROUTE_42_FLAG),
    "a full pack leaves the flag CLEAR, so the item is still there")
  eq(fullLog[2], "But {PLAYER} has\nno space left…", "_ButNoSpaceText instead")
end

-- ---- FindItemInBallScript, the OBJECTTYPE_ITEMBALL press -------------------
-- engine/events/misc_scripts.asm:9.  The object's pointer is two raw bytes, so
-- nothing exists for the VM to start: World:interact feeds it this built list.
-- Two load-bearing orderings.  `callasm .TryReceiveItem` names the item AND
-- takes it before any box is drawn, so the full-pocket branch is chosen with
-- nothing on screen and its arm prints two boxes of its own; and `disappear`
-- (which is what sets the ball's own event flag through World:disappearObject)
-- sits on the success side of the iffalse only, or a full pack would still eat
-- the ball.  This is NOT the hidden item's script with a disappear swapped in,
-- which is what it used to assert.
local function runBallPickup(bagFull)
  local events = Events.new()
  local log, given, gone, sfx = {}, nil, nil, nil
  local vm = Vm.new({}, {}, events, {
    showText = function(body, onDone)
      log[#log + 1] = body
      if onDone then onDone() end
    end,
    getItemName = function() return "HM07" end,
    giveItem = function(index, qty)
      if bagFull then return false end
      given = { index = index, qty = qty }
      return true
    end,
    disappear = function(objectId) gone = objectId end,
    playSound = function(id) sfx = id end,
    specialSound = function() end,
    waitSfx = function() return true end,
  })
  vm:start(HiddenItems.ballPickupScript(MAX_POTION, 1, 2))
  -- The cart's `pause 60` now rides the found line's own row as `hold` (see
  -- the order assertion below), and a `hold` is counted by the TEXT BOX, not
  -- by the VM -- this stub showText answers straight away, so nothing parks
  -- here.  The loop is left long so a future park would still be outlasted
  -- rather than read as a hang.
  for _ = 1, 160 do vm:update() end
  return log, given, gone, sfx, vm
end

do
  local script = HiddenItems.ballPickupScript(MAX_POTION, 3, 5)
  local ops = {}
  for _, cmd in ipairs(script) do ops[#ops + 1] = cmd.op end
  -- FindItemInBallScript is `writetext .FoundItemText / playsound SFX_ITEM /
  -- pause 60 / itemnotify` (engine/events/misc_scripts.asm:13-17), all of it
  -- inside ONE MapTextbox: nothing between the found line and the itemnotify
  -- line takes a box down.  The port's box does take itself down -- it waits
  -- for its own button and pops on it -- so written in that order the pause
  -- ran with an EMPTY state stack: 120 frames of bare overworld inside one
  -- cart textbox, with Game2's play clock counting for all of them
  -- (tests/drivers/gold_item_pickup_box.lua measures exactly that).
  --
  -- So the pause rides the found line's own row as `hold`, which World:showText
  -- counts on the standing box, and the sound leads the text instead of
  -- trailing it -- it has to be rung before the row that does not come back
  -- until the hold has drained.
  eq(table.concat(ops, ","),
    "getitemname,giveitem,iffalse,disappear,opentext,playsound,rawtext," ..
    "itemnotify,closetext,end",
    "FindItemInBallScript's order: the callasm pair first, then the freeze")
  eq(script[2].quantity, 3, "the itemball row's own quantity is given")
  eq(script[4].object, 5, "disappear names the object const the caller built")
  eq(script[6].id, 1, "playsound SFX_ITEM, not specialsound's TM-aware pick")
  eq(script[7].stay, true, "the found line holds the ONE MapTextbox open")
  eq(script[7].hold, 60, "and `pause 60` holds the world under that box")

  local log, given, gone, sfx, vm = runBallPickup(false)
  eq(log[1], "{PLAYER} found\nHM07!",
    "_FoundItemText ends on '!' -- the '.' one is the hidden item's")
  eq(given.index, MAX_POTION, "and the item lands in the pack")
  eq(gone, 2, "the ball object disappears -- its event flag rides on that")
  eq(sfx, 1, "SFX_ITEM rang")
  check(not vm:running(), "and the script ran off the end of the pause")

  local fullLog, fullGiven, fullGone = runBallPickup(true)
  check(fullGiven == nil, "a full pack takes nothing")
  check(fullGone == nil, "and the ball stays where it is")
  eq(fullLog[1], "{PLAYER} found\nHM07!", "the .no_room arm shows the find too")
  eq(fullLog[2], "But {PLAYER} can't\ncarry any more\vitems!",
    "_CantCarryItemText is the second box, not _ButNoSpaceText")
end

-- ---- ItemFinder's two queued scripts --------------------------------------
do
  local asked = {}
  local function sfxId(want, fallback)
    asked[#asked + 1] = want
    return fallback + 100
  end
  local found = HiddenItems.itemfinderScript(
    { x = 1, y = 1, item = MAX_POTION, event = ROUTE_42_FLAG }, sfxId)
  local ops = {}
  for _, cmd in ipairs(found) do ops[#ops + 1] = cmd.op end
  eq(#asked, 8, ".ItemfinderSound is four rounds of two sounds")
  eq(asked[1], "Sfx_SecondPartOfItemfinder", "the beep comes first")
  eq(asked[2], "Sfx_Transaction", "then the answering blip")
  eq(ops[1], "waitsfx", "WaitPlaySFX waits BEFORE it plays")
  eq(ops[2], "playsound", "and the play follows the wait")
  eq(found[2].id, 118, "the id is resolved through this cache's sfx table")
  eq(#found, 21, "sixteen sound rows and the five the text box needs")
  eq(table.concat({ ops[16], ops[17], ops[18], ops[19], ops[20], ops[21] }, ","),
    "playsound,opentext,rawtext,waitbutton,closetext,end",
    "and the text lands after the last sound, unwaited")

  local nothing = HiddenItems.itemfinderScript(nil, sfxId)
  local nothingOps = {}
  for _, cmd in ipairs(nothing) do nothingOps[#nothingOps + 1] = cmd.op end
  eq(table.concat(nothingOps, ","),
    "opentext,rawtext,waitbutton,closetext,end",
    ".Script_FoundNothing makes no sound at all")
  eq(#asked, 8, "and asks the sfx table for nothing")
end

-- ---- the world wiring -----------------------------------------------------
local World = require("src.world.gen2.World")

local COLL_FLOOR = 0x00

local function fakeWorld(bgEvents, px, py, facing)
  local game = {
    data = { items = {
      MAX_POTION = { id = "MAX_POTION", name = "MAX POTION",
        pocket = "ITEM", index = MAX_POTION },
      ITEMFINDER = { id = "ITEMFINDER", name = "ITEMFINDER",
        pocket = "KEY_ITEM", index = 0x3c },
    } },
    save = { player = { name = "GOLD" }, party = {},
      inventory = { ITEMFINDER = 1 } },
  }
  local world = World.new(game)
  game.world = world
  world.map = {
    id = "TEST_MAP",
    def = { bgEvents = bgEvents, objects = {}, width = 10, height = 10 },
    cellCollision = function() return COLL_FLOOR end,
    inBounds = function() return true end,
    warpAt = function() return nil end,
  }
  world.maps = { TEST_MAP = world.map.def }
  world.player = {
    cellX = px, cellY = py, px = px * 16, py = py * 16,
    facing = facing or "down", moving = false,
    update = function() return false end,
  }
  world.pollTimeOfDay = function() end
  world.playSfx = function(self, id) self.sfxLog = self.sfxLog or {}
    self.sfxLog[#self.sfxLog + 1] = id end
  local started = {}
  world.startedScripts = started
  world.vm = {
    running = function() return false end,
    update = function() end,
    start = function(_, script) started[#started + 1] = script return true end,
  }
  return world, game
end

do
  -- Facing the hidden item's cell: the A press runs HiddenItemScript.
  local world = fakeWorld({ itemRow(5, 6, MAX_POTION, ROUTE_42_FLAG) },
    5, 5, "down")
  check(world:interact(), "an A press into a hidden item is taken")
  eq(#world.startedScripts, 1, "and starts one script")
  eq(world.startedScripts[1][4].item, MAX_POTION,
    "the script the world built is the pickup for that item")
  eq(world.sfxLog[1], 8, "PlayTalkObject's SFX_READ_TEXT_2 opens it")

  -- Already found: `.dontread`, so the press is NOT taken and falls through to
  -- the tile events (none here, so interact answers false).
  world.events:set(ROUTE_42_FLAG, true)
  check(not world:interact(), "a hidden item already taken does not eat the press")
  eq(#world.startedScripts, 1, "and starts nothing")
end

do
  -- OBJECTTYPE_ITEMBALL: World:interact has to route the A press to the built
  -- ball pickup, because the object's pointer is raw (item, quantity) bytes
  -- and there is no scriptKey.  Without this arm no floor item in the game
  -- could be taken -- HM07 WATERFALL among them.
  local world = fakeWorld({}, 5, 5, "up")
  world.map.def.objects = {
    { index = 0, x = 5, y = 4, type = 1,   -- OBJECTTYPE_ITEMBALL, faced cell
      itemball = { item = MAX_POTION, quantity = 1 } },
  }
  world.npcs = {
    { cellX = 5, cellY = 4, def = world.map.def.objects[1] },
  }
  check(world:interact(), "an A press into an item ball is taken")
  eq(#world.startedScripts, 1, "and starts the pickup script")
  eq(world.startedScripts[1][2].item, MAX_POTION, "for the ball's item")
  -- And hLastTalked is set to the object, so the script's disappear names the
  -- ball and not whatever an earlier conversation left behind.
  eq(world.vm.lastTalked, 1, "hLastTalked points at the ball object (index+1)")
end

do
  -- ItemFinder from the PACK: QueueScript, so nothing runs until the menus are
  -- gone and the world owns the frame again.
  local world = fakeWorld({ itemRow(5, 6, MAX_POTION, ROUTE_42_FLAG) },
    5, 5, "down")
  eq(world:useFieldItem("ITEMFINDER"), "itemfinder",
    "the ITEMFINDER always quits the PACK; there is no refusal arm")
  check(world.queuedScript ~= nil, "the script is QUEUED, not run")
  eq(#world.startedScripts, 0, "so nothing has started yet")
  eq(world.queuedScript[1].op, "waitsfx", "and it is the found-something one")
  world:step()
  eq(#world.startedScripts, 1, "the drain starts it the next frame")
  check(world.queuedScript == nil, "and the queue is empty again")

  local empty = fakeWorld({}, 5, 5, "down")
  eq(empty:useFieldItem("ITEMFINDER"), "itemfinder", "a bare map still quits")
  eq(empty.queuedScript[1].op, "opentext",
    "and queues .Script_FoundNothing, which is silent")
  check(empty:useFieldItem("MAX_POTION") == nil,
    "any other item still falls through to the PACK's own onChoose")
end

-- ---- against the cache ----------------------------------------------------
-- Every row here is transcribed from pokegold: `bg_event x, y, BGEVENT_ITEM`
-- out of maps/<Map>.asm and the `hiddenitem item, flag` it points at, with the
-- item id from constants/item_constants.asm and the flag from
-- constants/event_flags.asm.
local PINNED = {
  { "AZALEA_TOWN", 31, 6, 38, 177 },        -- FULL_HEAL
  { "ROUTE_42", 16, 11, 15, 173 },          -- MAX_POTION
  { "TIN_TOWER_4F", 11, 6, 15, 125 },       -- MAX_POTION, the lowest flag
  { "DRAGONS_DEN_B1F", 31, 15, 21, 162 },   -- MAX_ELIXER
  { "CERULEAN_CITY", 2, 12, 152, 250 },     -- BERSERK_GENE
  { "MOUNT_MOON_SQUARE", 7, 7, 8, 236 },    -- MOON_STONE
  { "ROUTE_17", 8, 77, 21, 247 },           -- MAX_ELIXER, the highest flag
  { "GOLDENROD_UNDERGROUND_SWITCH_ROOM_ENTRANCES", 1, 8, 39, 143 }, -- REVIVE
}

-- NATIONAL_PARK and NATIONAL_PARK_BUG_CONTEST are the same map twice and share
-- one flag: finding the FULL_HEAL during the contest finds it outside too.
local SHARED_FLAG = { "NATIONAL_PARK", "NATIONAL_PARK_BUG_CONTEST", 6, 47, 38, 132 }

local HIDDEN_ITEM_COUNT = 87

local cacheDir = os.getenv("GOLD_CACHE")
if not cacheDir then
  cacheDir = (os.getenv("HOME") or "") ..
    "/Library/Application Support/LOVE/gold-dev/gold"
end
local mapsFile = loadfile(cacheDir .. "/data/generated/maps.lua")
if not mapsFile then
  check(true, "no Gold cache (SKIP)")
  S.finish()
  return
end
local maps = mapsFile()

local rows, decoded, withKey = {}, 0, 0
for mapId, def in pairs(maps) do
  if type(def) == "table" then
    for _, ev in ipairs(def.bgEvents or {}) do
      if ev.kind == HiddenItems.BGEVENT_ITEM then
        rows[#rows + 1] = true
        if ev.hiddenItem then decoded = decoded + 1 end
        if ev.scriptKey then withKey = withKey + 1 end
        local key = ("%s:%d:%d"):format(mapId, ev.x, ev.y)
        rows[key] = ev
      end
    end
  end
end

if decoded == 0 then
  eq(#rows, HIDDEN_ITEM_COUNT, "the cache has every BGEVENT_ITEM row")
  check(true, "cache predates the hiddenitem decode; re-import (SKIP)")
  S.finish()
  return
end

eq(#rows, HIDDEN_ITEM_COUNT, "eighty-seven hidden items in Gold")
eq(decoded, HIDDEN_ITEM_COUNT, "every one of them decoded its `hiddenitem`")
eq(withKey, 0,
  "and none of them is queued as a script: a scriptKey here is the pointer " ..
  "walk disassembling the flag word as opcodes")

for _, want in ipairs(PINNED) do
  local mapId, x, y, item, event = want[1], want[2], want[3], want[4], want[5]
  local ev = rows[("%s:%d:%d"):format(mapId, x, y)]
  check(ev ~= nil, mapId .. " has a hidden item at " .. x .. "," .. y)
  if ev then
    eq(ev.hiddenItem.item, item, mapId .. " hidden item id")
    eq(ev.hiddenItem.event, event, mapId .. " hidden item flag")
  end
end

do
  local a = rows[("%s:%d:%d"):format(SHARED_FLAG[1], SHARED_FLAG[3], SHARED_FLAG[4])]
  local b = rows[("%s:%d:%d"):format(SHARED_FLAG[2], SHARED_FLAG[3], SHARED_FLAG[4])]
  check(a ~= nil and b ~= nil, "NATIONAL PARK carries its FULL_HEAL on both maps")
  if a and b then
    eq(a.hiddenItem.event, SHARED_FLAG[6], "at the same flag")
    eq(b.hiddenItem.event, SHARED_FLAG[6], "on the contest copy too")
    eq(a.hiddenItem.item, SHARED_FLAG[5], "and the same item")
  end
end

-- Every flag has to land inside wEventFlags and every item inside ItemNames:
-- a mis-read `dwb` would put the item byte in the low half of the flag word.
do
  local items = assert(loadfile(cacheDir .. "/data/generated/items.lua"))()
  local byIndex = {}
  for id, def in pairs(items) do
    if type(def) == "table" and def.index then byIndex[def.index] = id end
  end
  local bad = 0
  for key, ev in pairs(rows) do
    if type(key) == "string" then
      if not byIndex[ev.hiddenItem.item] then bad = bad + 1 end
      if ev.hiddenItem.event >= 2048 then bad = bad + 1 end
    end
  end
  eq(bad, 0, "every decoded item is a real item and every flag is in range")
end

-- The point of the extractor half: those 87 pointers were being disassembled,
-- and the noise is where the port's unknown-opcode rows came from.
do
  local scripts = assert(loadfile(cacheDir .. "/data/generated/scripts.lua"))()
  local unknown = 0
  for key, list in pairs(scripts) do
    if key ~= "movements" and type(list) == "table" then
      for _, cmd in ipairs(list) do
        if cmd.op == "unknown" then unknown = unknown + 1 end
      end
    end
  end
  check(unknown <= 4,
    ("unknown opcode rows are down to %d (64 of the old 68 were hidden items)")
      :format(unknown))
end

S.finish()
