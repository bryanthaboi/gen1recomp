#!/usr/bin/env luajit
-- Comprehensive unit and integration test for:
-- 1. StepEvents Engine (lockstep queue, lethal poison, whiteout flush, repel, happiness, egg cycles, vs seeker charge)
-- 2. VS Seeker Engine (battery charge only with the item in the bag, map gate, uncharged use)
-- 3. TM Case & Berry Pouch Sub-Containers & Bag state persistence

package.path = "./?.lua;./?/init.lua;" .. package.path
local Game3Cache = require("tests.game3_cache")
if not Game3Cache.bundle() then print("[skip] step_events_queue: " .. tostring(Game3Cache.reason)) return end

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

-- Mock Love2D globals if not present
if not _G.love then
  _G.love = {
    graphics = {
      setColor = function() end,
      rectangle = function() end,
      circle = function() end,
      arc = function() end,
      draw = function() end,
      newImage = function() return { setFilter = function() end } end,
      newQuad = function() return {} end,
    },
    timer = { getTime = function() return 0 end },
    filesystem = { read = function() return nil end },
  }
end

local StepEvents = require("src.core.game3.step_events")
local VsSeeker = require("src.core.game3.vs_seeker")
local ItemsData = require("src.core.game3.items_data")
local Bag = require("src.core.game3.bag")
local ItemUse = require("src.core.game3.item_use")
local TmCase = require("src.ui.game3.tm_case")
local BerryPouch = require("src.ui.game3.berry_pouch")
local BagMenu = require("src.ui.game3.bag_menu")
local Pokemon = require("src.core.game3.pokemon")

print("=== 1. StepEvents Engine & Lockstep Queue Tests ===")

StepEvents.flush()
check(not StepEvents.busy(), "Initial StepEvents is not busy")

local eventOrder = {}
StepEvents.queueEvent(function() table.insert(eventOrder, "first") end)
StepEvents.queueEvent(function() table.insert(eventOrder, "second") end)
check(StepEvents.busy(), "StepEvents is busy with 2 queued events")

StepEvents.update(0.1)
check(#eventOrder == 1 and eventOrder[1] == "first", "First event executed")
check(StepEvents.busy(), "StepEvents still busy with remaining event")

StepEvents.update(0.1)
check(#eventOrder == 2 and eventOrder[2] == "second", "Second event executed")
check(not StepEvents.busy(), "Queue drained, StepEvents is no longer busy")

print("=== 2. VS Seeker Battery Management across Locomotion Modes ===")

local session = {
  repelSteps = 10,
  bag = Bag.new(),
  party = {
    { species = 25, nickname = "PIKACHU", hp = 20, maxHp = 20, friendship = 70 },
  },
}

for i = 1, 5 do
  StepEvents.onStep(session, {})
end
check(VsSeeker.getBattery(session) == 0, "VS Seeker does not charge while it is not in the bag")
session.repelSteps = 10
Bag.add(session.bag, ItemsData.ITEM_VS_SEEKER, 1)

-- Step counting across locomotion modes
for i = 1, 50 do
  StepEvents.onStep(session, { running = false, biking = false, surfing = false })
end
check(VsSeeker.getBattery(session) == 50, "VS Seeker charged 50 steps via walking")

for i = 1, 30 do
  StepEvents.onStep(session, { running = true, biking = false, surfing = false })
end
check(VsSeeker.getBattery(session) == 80, "VS Seeker charged +30 steps via running (total 80)")

for i = 1, 20 do
  StepEvents.onStep(session, { running = false, biking = true, surfing = false })
end
check(VsSeeker.getBattery(session) == 100, "VS Seeker reached 100 charge via biking")

-- Charging capped at 100
StepEvents.onStep(session, { running = false, biking = false, surfing = true })
check(VsSeeker.getBattery(session) == 100, "VS Seeker charge capped at 100")

print("=== 3. Repel Countdown & Single Wear-off Mechanics ===")

check(session.repelSteps == 0, "Repel wore off after 10 steps (started at 10)")
-- Verify repel queued wear off event
check(StepEvents.busy(), "Repel wear-off event queued")
local handledRepel = false
local mockHud = {
  openMessage = function(_game, msg, opts)
    if msg == require("src.core.game3.rom_text").box("Text_RepelWoreOff") then
      handledRepel = true
    end
    if opts and opts.done then opts.done() end
  end
}
package.loaded["src.ui.game3.hud"] = mockHud
StepEvents.update(0.1)
check(handledRepel, "Repel displayed ROM Text_RepelWoreOff")

print("=== 4. Happiness & Egg Cycles Mechanics ===")

local eggMon = { species = 175, nickname = "EGG", isEgg = true, eggCycles = 2 }
local partyMon = { species = 25, nickname = "PIKA", hp = 30, maxHp = 30, friendship = 100 }
session.party = { partyMon, eggMon }
StepEvents.flush()

-- Step 128 times for friendship
for i = 1, 128 do
  StepEvents.onStep(session, {})
end
check(partyMon.friendship == 101, "Party mon gained +1 friendship after 128 steps")

-- Step another 128 times (total 256 steps) for egg cycle decrement
for i = 1, 128 do
  StepEvents.onStep(session, {})
end
check(eggMon.eggCycles == 1, "Egg decremented 1 egg cycle after 256 steps")

print("=== 5. Gen 3 Lethal Poison & Whiteout Queue Flush ===")

StepEvents.flush()
local poisonedMon1 = { species = 1, nickname = "BULBA", hp = 2, maxHp = 20, status = "PSN" }
local poisonedMon2 = { species = 4, nickname = "CHAR", hp = 1, maxHp = 20, status = "PSN" }
session.party = { poisonedMon1, poisonedMon2 }

-- 4 steps trigger 1 HP poison damage
for i = 1, 4 do
  StepEvents.onStep(session, {})
end
check(poisonedMon1.hp == 1, "Poisoned mon 1 took 1 HP damage (now 1 HP)")
check(poisonedMon2.hp == 0, "Poisoned mon 2 dropped to 0 HP and fainted")

-- Process queued poison faint dialogue
local faintedMsg = false
mockHud.openMessage = function(_game, msg, opts)
  if msg:find("CHAR fainted") or msg:find("fainted") then
    faintedMsg = true
  end
  if opts and opts.done then opts.done() end
end
StepEvents.update(0.1)
check(faintedMsg, "Lethal poison faint event processed")
StepEvents.update(0.1)
check(not StepEvents.busy(), "Party still standing: the whiteout check releases the queue")

-- Next 4 steps drop last Pokémon to 0 HP -> Whiteout
for i = 1, 4 do
  StepEvents.onStep(session, {})
end
check(poisonedMon1.hp == 0, "Poisoned mon 1 dropped to 0 HP (entire party fainted)")

session.money = 1000
local messages = {}
mockHud.openMessage = function(_game, msg, opts)
  messages[#messages + 1] = msg
  if opts and opts.done then opts.done() end
end
local respawned, locked = false, false
package.loaded["src.core.game3.audio"] = { fadeOutBgm = function() end, playCry = function() end }
package.loaded["src.ui.game3.fade"] = { MODE = { TO_BLACK = 1 }, begin = function(_, _, cb) if cb then cb() end end }
package.loaded["src.core.game3.field"] = {
  lock = function() locked = true end,
  respawnAtHeal = function() respawned = true end,
}
for _ = 1, 4 do StepEvents.update(0.1) end
check(messages[1] and messages[1]:find("BULBA fainted…", 1, true) ~= nil, "Last faint message shown before the wipe check")
check(messages[2] and messages[2]:find("panicked and lost ¥8…", 1, true) ~= nil, "Whiteout text carries the money loss")
check(session.money == 992, "Money loss applied on field whiteout (" .. tostring(session.money) .. ")")
check(locked and respawned, "Field whiteout locks the player and respawns at the heal point")
check(not StepEvents.busy(), "StepEvents queue completely empty after whiteout")
package.loaded["src.core.game3.audio"] = nil
package.loaded["src.ui.game3.fade"] = nil
package.loaded["src.core.game3.field"] = nil

print("=== 6. VS Seeker Map Gate & Uncharged Use ===")

local mapType = 8
package.loaded["src.core.game3.map"] = {
  current = "FR_ROUTE_8",
  currentDef = function() return { mapType = mapType } end,
}
session.map = "FR_ROUTE_8"
session.name = "RED"
session.bag = Bag.new()
Bag.add(session.bag, ItemsData.ITEM_VS_SEEKER, 1)
VsSeeker.setBattery(session, 100)

local okIndoor, kindIndoor, textIndoor = ItemUse.useField(session, session.bag, ItemsData.ITEM_VS_SEEKER)
check(not okIndoor and kindIndoor == "vs_seeker", "VS Seeker refused on an indoor map type")
check(textIndoor == "OAK: RED!\nThis isn't the time to use that!", "refusal uses the OAK forbids text")
check(VsSeeker.getBattery(session) == 100, "Battery preserved at 100 on refusal")

mapType = 3
local okRoute, kindRoute = ItemUse.useField(session, session.bag, ItemsData.ITEM_VS_SEEKER)
check(okRoute and kindRoute == "vs_seeker", "VS Seeker accepted on a ROUTE map type")
check(VsSeeker.mapAllowed("FR_ROUTE_8", 1) and VsSeeker.mapAllowed("FR_ROUTE_8", 2), "TOWN and CITY map types allowed")
check(not VsSeeker.mapAllowed("FR_ROUTE_8", 4), "UNDERGROUND map type refused")
check(not VsSeeker.mapAllowed("ViridianForest", 3), "Viridian Forest excluded by name")

VsSeeker.setBattery(session, 40)
local notChargedMsg
mockHud.openMessage = function(_game, msg, opts)
  notChargedMsg = msg
  if opts and opts.done then opts.done() end
end
local okUse, code = VsSeeker.use(session, nil)
check(not okUse and code == VsSeeker.NOT_CHARGED, "uncharged VS Seeker reports NOT_CHARGED")
check(notChargedMsg and notChargedMsg:find("charge the battery: 60", 1, true) ~= nil, "uncharged text prints 100 - charge")
check(VsSeeker.getBattery(session) == 40, "uncharged use does not drain the battery")
package.loaded["src.core.game3.map"] = nil

print("=== 7. TM Case & Berry Pouch Sub-Containers & Bag State Persistence ===")

local bag = Bag.new()
Bag.add(bag, 289, 1) -- TM01
Bag.add(bag, 290, 2) -- TM02
Bag.add(bag, 139, 5) -- ORAN BERRY
Bag.add(bag, 142, 3) -- SITRUS BERRY

session.bag = bag
session.party = {
  { species = 1, nickname = "BULBASAUR", hp = 20, maxHp = 20, moves = { 33, 45 } },
}

-- TM Case listing
TmCase.show(session, bag)
check(TmCase.isOpen(), "TmCase opened")
local tmList = TmCase.list()
check(#tmList == 2, "TmCase has 2 TMs listed")
TmCase.close()
check(not TmCase.isOpen(), "TmCase closed cleanly")

-- Berry Pouch listing
BerryPouch.show(session, bag)
check(BerryPouch.isOpen(), "BerryPouch opened")
local berryList = BerryPouch.list()
check(#berryList == 2, "BerryPouch has 2 Berries listed")
BerryPouch.close()
check(not BerryPouch.isOpen(), "BerryPouch closed cleanly")

-- BagMenu sub-container transition & state preservation
BagMenu.show(session, { bag = bag })
BagMenu.settle()
BagMenu.pocketIdx = 2 -- KEY_ITEMS
BagMenu.cursor = 1
BagMenu.scroll = 0

-- Simulate selecting TM Case from Key Items
BagMenu.mode = "action"
BagMenu.actionCursor = 1 -- USE
local mockRow = { id = ItemsData.ITEM_TM_CASE, name = "TM CASE" }
-- Mock rows in BagMenu
BagMenu.list = function() return { mockRow } end

local mockInput = {
  wasPressed = function(self, key)
    return key == "a"
  end
}
BagMenu.handleInput(mockInput)
BagMenu.settle()
check(TmCase.isOpen(), "Using TM CASE from BagMenu opens TmCase UI")

-- Close TM Case and verify BagMenu state restored
TmCase.close()
check(BagMenu.pocketIdx == 2, "BagMenu pocketIdx preserved (2 = KEY_ITEMS)")
check(BagMenu.cursor == 1, "BagMenu cursor preserved")
check(BagMenu.mode == "list", "BagMenu mode returned to list")
BagMenu.close()

print(string.format("\n=========================================="))
if failed == 0 then
  print("ALL TESTS PASSED SUCCESSFULLY!")
else
  print(string.format("TESTS FAILED WITH %d ERRORS", failed))
  os.exit(1)
end
