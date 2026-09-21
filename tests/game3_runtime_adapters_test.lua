#!/usr/bin/env luajit
-- pokefirered/src/party_menu_specials.c:14

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function done()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local Adapters = require("src.core.game3.scripting.adapters")
local Ctx = require("src.core.game3.scripting.ctx")
local Flags = require("src.core.game3.scripting.flags")
local Std = require("src.core.game3.scripting.stdscripts")
local Natives = require("src.core.game3.scripting.natives")
local Runtime = require("src.core.game3.runtime")

local SLOT_CANCEL = 7

local function newCtx()
  local ctx = Ctx.new({})
  ctx.mode = "bytecode"
  ctx.status = "running"
  return ctx
end

local function slotVar(ctx)
  return Flags.getVar(nil, ctx, 0x8004)
end

print("[test] 1. the stub adapter carries the three new seams")
local stub = Adapters.stub({ verbose = false })
check(type(stub.chooseParty) == "function", "Adapters.stub defines chooseParty")
check(type(stub.elevatorWindow) == "function", "Adapters.stub defines elevatorWindow")
check(type(stub.elevatorWindowClose) == "function", "Adapters.stub defines elevatorWindowClose")

local gotSlot, gotCalled = "unset", false
stub.chooseParty({ menuType = "choose_single" }, function(s)
  gotCalled = true
  gotSlot = s
end)
check(gotCalled and gotSlot == nil, "the default chooseParty answers done(nil)")

local ctx1 = newCtx()
local yielded = Natives.special(ctx1, Std.SPECIAL.ChoosePartyMon, stub)
check(yielded == false, "the default seam resolves without parking the script")
check(slotVar(ctx1) == SLOT_CANCEL,
  "ChoosePartyMon through the default seam writes SLOT_CANCEL, got " .. tostring(slotVar(ctx1)))

stub.elevatorWindow("1F")
check(stub.elevatorFloorLabel == "1F", "the stub elevator window records the floor label")
stub.elevatorWindowClose()
check(stub.elevatorFloorLabel == nil, "the stub elevator window closes")

local injected = Adapters.stub({ chooseParty = function(_, cb) cb(2) end })
local ctx2 = newCtx()
Natives.special(ctx2, Std.SPECIAL.ChoosePartyMon, injected)
check(slotVar(ctx2) == 2, "an injected chooseParty still overrides the default, got "
  .. tostring(slotVar(ctx2)))

print("[test] 2. the field adapter binds ChoosePartyMon to the party menu")
local PartyMenu = require("src.ui.game3.party_menu")
local game = { data = {} }
local host = Adapters.host(nil, game, nil)
check(type(host.chooseParty) == "function", "Adapters.host defines chooseParty")

local session = {
  map = "FR_LAVENDER_TOWN_HOUSE2",
  party = {
    { species = 1, level = 12, hp = 20, maxHp = 20, nickname = "", otId = 1 },
    { species = 4, level = 12, hp = 20, maxHp = 20, nickname = "SPIKE", otId = 2 },
  },
}
Runtime.session = session
Runtime.active = true

local function press(btn)
  PartyMenu.handleInput({
    wasPressed = function(_, k) return k == btn end,
    isDown = function() return false end,
  })
end

local ctx3 = newCtx()
local parked = Natives.special(ctx3, Std.SPECIAL.ChoosePartyMon, host)
check(parked == true, "the script parks while the picker is up")
check(PartyMenu.isOpen() == true, "the party menu opened")
check(PartyMenu.mode == "choose", "it opened in choose mode, got " .. tostring(PartyMenu.mode))
check(PartyMenu._party == session.party, "it shows the live session party")
check(require("src.ui.game3.naming").isOpen() == false,
  "ChoosePartyMon did not open the naming keyboard")

press("down")
check(PartyMenu.cursor == 2, "the cursor moved to slot 2")
press("a")
check(PartyMenu.isOpen() == false, "A closed the picker")
check(ctx3.nativePoll() == false, "the pick is still pending before the field frame")
check(Runtime.drainDeferred() == 1, "one deferred resume was queued")
check(ctx3.nativePoll() == true, "the native finished on the next field frame")
check(slotVar(ctx3) == 1, "VAR_0x8004 = 1 for slot 2, got " .. tostring(slotVar(ctx3)))

local ctx4 = newCtx()
Natives.special(ctx4, Std.SPECIAL.ChoosePartyMon, host)
check(PartyMenu.isOpen() == true, "the picker reopens for a second script")
press("b")
Runtime.drainDeferred()
check(slotVar(ctx4) == SLOT_CANCEL, "B writes SLOT_CANCEL, got " .. tostring(slotVar(ctx4)))

local ctx5 = newCtx()
local emptySession = { party = {} }
Runtime.session = emptySession
Natives.special(ctx5, Std.SPECIAL.ChoosePartyMon, host)
check(PartyMenu.isOpen() == false, "an empty party never opens the picker")
check(slotVar(ctx5) == SLOT_CANCEL, "and it answers SLOT_CANCEL, got " .. tostring(slotVar(ctx5)))
Runtime.session = session

print("[test] 3. the elevator window seams are safe with no screen behind them")
check(package.loaded["src.ui.game3.elevator_window"] == nil,
  "no elevator window screen is loaded in this tier")
local okOpen = pcall(host.elevatorWindow, "5F")
local okClose = pcall(host.elevatorWindowClose)
check(okOpen, "elevatorWindow degrades to a no-op")
check(okClose, "elevatorWindowClose degrades to a no-op")

print("[test] 4. the field-focus notification is edge triggered")
Runtime.active = false
check(Runtime.defer(function() end) == false, "defer refuses while the field is down")
Runtime.active = true
local ran = 0
Runtime.defer(function() ran = ran + 1 end)
Runtime.defer(function() ran = ran + 1 end)
check(Runtime.drainDeferred() == 2, "both deferred calls drain together")
check(ran == 2, "and both ran")
check(Runtime.drainDeferred() == 0, "the queue is empty afterwards")

local Stack = require("src.ui.game3.stack")
Stack.clear()
check(Runtime.fieldScreenOpen(false) == false, "an open field is not a screen")
Stack.push("start", {}, { hideBelow = true })
check(Runtime.fieldScreenOpen(true) == false,
  "the START menu alone is an overlay, not a CB2 screen")
Stack.push("bag", {}, { hideBelow = true })
check(Runtime.fieldScreenOpen(true) == true, "the bag over it is a CB2 screen")
Stack.pop("bag")
check(Runtime.fieldScreenOpen(true) == false,
  "closing the bag back to the START menu ends the screen")
Stack.push("save", {}, { hideBelow = true })
check(Runtime.fieldScreenOpen(true) == false,
  "the save dialog over START stays in-field, not a CB2 screen")
Stack.push("bag", {}, { hideBelow = true })
check(Runtime.fieldScreenOpen(true) == true,
  "a third layer over the save dialog is a CB2 screen again")
Stack.clear()
check(Runtime.fieldScreenOpen(true) == true,
  "any other screen counts even with no stack layer")

check(Runtime.noteFieldFocus(true) == false, "opening a menu never notifies")
check(Runtime.noteFieldFocus(true) == false, "a second frame with the menu open is quiet")
check(Runtime.noteFieldFocus(false) == false,
  "closing it with no live Space VM is a safe no-op")
check(Runtime.noteFieldFocus(false) == false, "and the level state stays quiet")

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] game3_runtime_adapters_test cache tier: " .. tostring(Cache.reason))
  done()
end
print("[info] FireRed cache at " .. cacheRoot)

print("[test] 5. a menu close re-runs ON_RESUME + ON_RETURN_TO_FIELD, once")
local Space = require("src.core.game3.scripting.space")
local ExtractScripts = require("src.import.gba.extract_scripts")
Space.bundle = ExtractScripts.loadBundle(Cache.cache(), cacheRoot, { allowIncomplete = true })
check(Space.bundle ~= nil, "script bundle loads")

local Dataset = require("src.core.game3.dataset")
local Map = require("src.core.game3.map")
local Objects = require("src.core.game3.objects")

Dataset.hydrate(game)
local live = { map = "FR_PALLET_TOWN", x = 12, y = 20, facing = "down", flags = {}, vars = {} }
game.session = live
Runtime.start(nil, game, live, { reason = "new_game" })

local LOBBY = "FR_TRAINER_TOWER_LOBBY"
local function warpTo(mapId, x, y, facing)
  Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "down" })
  for _ = 1, 256 do
    if not Space.vm:isRunning() then break end
    Space.vm:tick()
  end
end

if not (Space.bundle.events[LOBBY] and game.data.maps[LOBBY]) then
  check(false, "FR_TRAINER_TOWER_LOBBY is in the bundle and the map set")
  done()
end

warpTo(LOBBY, 9, 10, "down")
local staff = Objects.find(3)
check(staff ~= nil and staff.visible == true, "the lobby receptionist is on the map")

local function openBag()
  Stack.clear()
  Stack.push("start", {}, { hideBelow = true })
  Stack.push("bag", {}, { hideBelow = true })
  Runtime.update(1 / 60)
end

local function closeBag()
  Stack.clear()
  Runtime.update(1 / 60)
end

local function quietFrame()
  Stack.clear()
  Runtime.update(1 / 60)
end

Objects.removeObject(3)
openBag()
local hidden = Objects.find(3)
check(hidden == nil or hidden.visible == false,
  "a field frame with the bag up does not run the map scripts")

closeBag()
local back = Objects.find(3)
check(back ~= nil and back.visible == true,
  "the field frame after the bag closes put the receptionist back")

Objects.removeObject(3)
quietFrame()
local stillGone = Objects.find(3)
check(stillGone == nil or stillGone.visible == false,
  "a second quiet frame does not re-run them")

Space.vm.scripts["g3:test_parked"] = {
  { op = "lockall" },
  { op = "delay", 1, delay = 240 },
  { op = "end" },
}
Space.vm:start("g3:test_parked")
check(Space.vm:isRunning() == true, "a field script is parked on delay")
openBag()
closeBag()
local parkedGone = Objects.find(3)
check(parkedGone == nil or parkedGone.visible == false,
  "a menu closing over a running script does not re-enter it")
Space.vm:halt(true)

openBag()
closeBag()
local back2 = Objects.find(3)
check(back2 ~= nil and back2.visible == true,
  "once the script ends the next close runs them")

done()
