-- The POKeGEAR's phone: the contact list, the receive-call timer, the random
-- caller gate, the special-call queue, the trainer rematch flags, and the
-- phone card that places an outgoing call.
--
-- ROM-free and draw-free.  src/core/gen2/Phone.lua is love-free by design, so
-- every model assertion here runs against the module directly; the Pokegear
-- section stubs the same love pieces tests/gen2_menus_test.lua does and drives
-- the card with a fake input.
--
-- Everything asserted is transcribed behaviour, so each block names the
-- pokegold routine it is pinning down.

package.path = "./?.lua;" .. package.path
require("tests.fixture_data.gen2_engine_flags").bind("gold")

local drawn = {}
love = love or {}
love.graphics = love.graphics or {
  getColor = function() return 1, 1, 1, 1 end,
  setColor = function() end,
  rectangle = function() end,
  print = function() end,
  printf = function() end,
  draw = function() end,
  newQuad = function() return {} end,
  newImage = function() return nil end,
  getShader = function() return nil end,
  setShader = function() end,
  newShader = function() error("no shaders in this harness") end,
  getDimensions = function() return 160, 144 end,
  push = function() end, pop = function() end,
  translate = function() end, scale = function() end,
  circle = function() end, clear = function() end,
}
love.math = love.math or {
  random = function(a, b)
    if b then return a end
    return a and 1 or 0.5
  end,
}
love.image = love.image or {}
love.filesystem = love.filesystem or {
  load = function() return nil end,
  getInfo = function() return nil end,
  read = function() return nil end,
  write = function() return true end,
  remove = function() return true end,
}
love.timer = love.timer or { getTime = function() return 0 end }

require("src.core.Logger").warn = function() end

local Events = require("src.world.gen2.Events")
local Phone = require("src.core.gen2.Phone")
local Pokegear = require("src.ui.gen2.Pokegear")
local Save = require("src.core.gen2.Save")

local failures, checks = 0, 0
local function check(name, got, want)
  checks = checks + 1
  if got ~= want then
    failures = failures + 1
    print(("FAIL %s: got %s, want %s"):format(
      name, tostring(got), tostring(want)))
  end
end

local function newSave()
  return Save.normalize({})
end

-- A deterministic Random: one byte per cart `call Random`, in the order the
-- gate consumes them.  Runs off the end of the list rather than wrapping, so a
-- test that draws more rolls than it queued fails loudly instead of quietly
-- re-using one.
local function rolls(...)
  local queue = { ... }
  local index = 0
  return function()
    index = index + 1
    return queue[index] or error("ran out of seeded rolls at draw " .. index, 0)
  end
end

-- ------------------------------------------------------ the contact table

check("no hand-typed contact rows before events.lua is read",
  next(Phone.CONTACTS), nil)
check("no hand-typed non-trainer names either",
  next(Phone.NON_TRAINER_NAMES), nil)
check("no hand-typed special calls either", next(Phone.SPECIAL_CALLS), nil)
check("no hand-typed script keys before events.lua is read",
  Phone.scriptKey("JoeyPhoneCallerScript"), nil)
check("events.lua with no phoneScripts is an error",
  pcall(Phone.useExtracted, { phone = {}, phoneNames = {}, specialCalls = {} }),
  false)
check("events.lua with no phoneNames is an error",
  pcall(Phone.useExtracted, { phone = {}, phoneScripts = {}, specialCalls = {} }),
  false)
check("events.lua with no specialCalls is an error",
  pcall(Phone.useExtracted, { phone = {}, phoneScripts = {}, phoneNames = {} }),
  false)
check("a trainer row with no trainer constants is an error",
  pcall(Phone.useExtracted, { phone = { [15] = { trainerClass = 22, number = 1 } },
    phoneScripts = {}, phoneNames = {}, specialCalls = {} }), false)

local PHONE = require("tests.fixtures.gen2_phone_events")
Phone.useRegistry({ gen2EventTables = PHONE.events, gen2Constants = PHONE.constants })
check("useExtracted takes the fixture's rows", Phone.useExtracted(PHONE.events), true)

-- data/phone/phone_contacts.asm, `assert_table_length NUM_PHONE_CONTACTS + 1`.
check("the contact table is zero based", Phone.CONTACTS[0] ~= nil, true)
check("and runs to the last PhoneContacts row",
  Phone.CONTACTS[#PHONE.constants.phoneContactOrder - 1] ~= nil, true)
check("with nothing past it",
  Phone.CONTACTS[#PHONE.constants.phoneContactOrder], nil)
check("a trainer row carries its class from the cache",
  Phone.CONTACTS[15].class, "YOUNGSTER")
check("and its member", Phone.CONTACTS[15].member, "JOEY1")
check("special calls come from SpecialPhoneCallList",
  Phone.SPECIAL_CALLS[Phone.SPECIALCALL.SPECIALCALL_BIKESHOP].condition,
  "anywhere")
check("with SpecialCallOnlyWhenOutside read as outside",
  Phone.SPECIAL_CALLS[Phone.SPECIALCALL.SPECIALCALL_ROBBED].condition,
  "outside")
check("and no row past SPECIALCALL_MASTERBALL",
  Phone.SPECIAL_CALLS[#PHONE.constants.specialCallOrder], nil)

-- constants/trainer_constants.asm opens the non-trainer block with
-- `const_def 1`.  A zero-based reading here would shift every name by one and
-- leave PROF.ELM off the end.
check("PHONECONTACT_MOM is 1", Phone.PHONECONTACT_MOM, 1)
check("PHONECONTACT_ELM is 4", Phone.PHONECONTACT_ELM, 4)
check("and MOM's name comes off that index",
  Phone.contactName(1), "MOM")
check("as does PROF.ELM's", Phone.contactName(4), "PROF.ELM")
check("contact 0 is the wrong-number filler",
  Phone.contactName(0), "----------")

-- The three const_skip holes between HUEY and GAVEN, and the one before DANA,
-- are real rows in the ROM table: they must resolve, not index nil.
check("a const_skip hole is a live row", Phone.CONTACTS[9] ~= nil, true)
check("and it can never be called", Phone.CONTACTS[9].callerTime, 0)
check("nor called out to", Phone.CONTACTS[25].calleeTime, 0)

-- SCRIPT2_TIME is the mask for THEM calling YOU, and Mom, Elm, Bill and the
-- bike shop all have it at 0.  This is why an unprompted Elm call can only
-- ever arrive through the special-call queue.
check("Mom never rings you at random", Phone.CONTACTS[1].callerTime, 0)
check("nor does Elm", Phone.CONTACTS[4].callerTime, 0)
check("but Joey does", Phone.CONTACTS[15].callerTime, Phone.ANYTIME)
check("and Elm can still be called", Phone.CONTACTS[4].calleeTime,
  Phone.ANYTIME)

check("a contact names its caller script",
  Phone.CONTACTS[15].caller, "JoeyPhoneCallerScript")
check("and resolves it to a scripts.lua key",
  Phone.scriptKey("JoeyPhoneCallerScript"),
  PHONE.events.phoneScripts.JoeyPhoneCallerScript.script)

-- ------------------------------------------------------ the contact list

-- engine/phone/phone.asm AddPhoneNumber / _CheckCellNum / DelCellNum.
do
  local save = newSave()
  check("a new phone book is empty", Phone.hasContact(save, 15), false)
  check("adding Joey works", Phone.addContact(save, 15), true)
  check("and he is in the book", Phone.hasContact(save, 15), true)
  check("in the first slot", Phone.contacts(save)[1], 15)
  local ok, why = Phone.addContact(save, 15)
  check("adding him twice is refused", ok, false)
  check("because he is already there", why, "already")
  check("removing him works", Phone.removeContact(save, 15), true)
  check("and he is gone", Phone.hasContact(save, 15), false)
  check("removing him again does nothing", Phone.removeContact(save, 15), false)
end

-- GetRemainingSpaceInPhoneList reserves a slot for every PERMANENT number you
-- have not registered yet, so a player who has met neither MOM nor ELM can
-- only fill eight of the ten slots.
do
  local save = newSave()
  check("two permanent numbers are outstanding",
    Phone.remainingSlots(save, 15), 8)
  Phone.addContact(save, Phone.PHONECONTACT_MOM)
  check("registering MOM frees her slot", Phone.remainingSlots(save, 15), 9)
  Phone.addContact(save, Phone.PHONECONTACT_ELM)
  check("and registering ELM frees his", Phone.remainingSlots(save, 15), 10)
end

-- `cp c / jr z, .continue`: a permanent number never reserves a slot against
-- itself, which is what lets MOM in when the book is otherwise full.
do
  local save = newSave()
  local trainers = { 15, 16, 17, 18, 19, 20, 21, 22 }
  for _, id in ipairs(trainers) do
    check("trainer " .. id .. " fits", Phone.addContact(save, id), true)
  end
  local ok, why = Phone.addContact(save, 23)
  check("the ninth trainer does not", ok, false)
  check("because the book is full", why, "full")
  check("but MOM still fits",
    Phone.addContact(save, Phone.PHONECONTACT_MOM), true)
  check("and so does ELM",
    Phone.addContact(save, Phone.PHONECONTACT_ELM), true)
  check("filling all ten slots", Phone.contacts(save)[10],
    Phone.PHONECONTACT_ELM)
end

-- Script_askforphonenumber's three PHONE_CONTACT_* return values.  A refusal
-- never touches the book, and a full book reports FULL rather than GOT.
do
  local save = newSave()
  check("refusing returns PHONE_CONTACT_REFUSED",
    Phone.askForNumber(save, 15, false), Phone.CONTACT_REFUSED)
  check("and stores nothing", Phone.hasContact(save, 15), false)
  check("accepting returns PHONE_CONTACT_GOT",
    Phone.askForNumber(save, 15, true), Phone.CONTACT_GOT)
  check("a second ask reports PHONE_CONTACTS_FULL",
    Phone.askForNumber(save, 15, true), Phone.CONTACTS_FULL)
end

-- PokegearPhone_DeletePhoneNumber blanks the slot and then compacts, so the
-- display never shows a gap; CheckCanDeletePhoneNumber withholds DELETE from
-- MOM and ELM.
do
  local save = newSave()
  Phone.addContact(save, 15)
  Phone.addContact(save, 16)
  Phone.addContact(save, 17)
  Phone.deleteContactAt(save, 2)
  local list = Phone.contacts(save)
  check("delete compacts the list", list[1], 15)
  check("pulling the tail forward", list[2], 17)
  check("and leaving the end empty", list[3], 0)
  check("MOM cannot be deleted", Phone.canDelete(Phone.PHONECONTACT_MOM), false)
  check("nor can ELM", Phone.canDelete(Phone.PHONECONTACT_ELM), false)
  check("but BILL can", Phone.canDelete(Phone.PHONECONTACT_BILL), true)
  check("and so can a trainer", Phone.canDelete(15), true)
  check("an empty slot cannot", Phone.canDelete(0), false)
end

-- The VM's addcellnum hook writes save.phoneContacts directly
-- (src/world/gen2/World.lua); the model adopts that set into wPhoneList and
-- mirrors the list back over it, so neither half has to move first.
do
  local save = newSave()
  save.phoneContacts = { [15] = true, [16] = true }
  check("a legacy set is adopted into the list",
    Phone.hasContact(save, 16), true)
  Phone.removeContact(save, 15)
  Phone.state(save)
  check("and a delete propagates back out", save.phoneContacts[15], nil)
  check("leaving the rest alone", save.phoneContacts[16], true)
end

-- ------------------------------------------------------ the receive timer

-- engine/overworld/time.asm InitCallReceiveDelay / NextCallReceiveDelay /
-- CheckReceiveCallTimer.  The ladder is 20, 10, 5, 3 minutes, indexed by
-- wTimeCyclesSinceLastCall and capped at three.
local function at(hour, minute, day)
  return { clock = { day = day or 0, hour = hour, minute = minute } }
end

do
  local save = newSave()
  Phone.initReceiveDelay(save, at(9, 0))
  check("the first delay is twenty minutes", save.phone.delayMins, 20)
  check("nineteen minutes is not enough",
    Phone.checkReceiveCallTimer(save, at(9, 19)), false)
  check("with a minute left on the clock", save.phone.delayMins, 1)
  check("the twentieth minute expires it",
    Phone.checkReceiveCallTimer(save, at(9, 20)), true)
  check("and the counter winds on", save.phone.timeCycles, 1)
  check("shortening the next delay to ten", save.phone.delayMins, 10)
  check("which expires ten minutes later",
    Phone.checkReceiveCallTimer(save, at(9, 30)), true)
  check("then five", save.phone.delayMins, 5)
  Phone.checkReceiveCallTimer(save, at(9, 35))
  check("then three", save.phone.delayMins, 3)
  Phone.checkReceiveCallTimer(save, at(9, 38))
  check("and three stays three", save.phone.delayMins, 3)
  check("with the counter capped", save.phone.timeCycles, 3)
end

-- GetMinutesSinceIfLessThan60 gives up past an hour and hands
-- UpdateTimeRemaining -1, which it treats as expired outright.
do
  local save = newSave()
  Phone.initReceiveDelay(save, at(9, 0))
  check("an hour away expires the timer at once",
    Phone.checkReceiveCallTimer(save, at(11, 5)), true)
end

-- StartMap runs InitCallReceiveDelay on EVERY map load, which is why warping
-- around never gets you a call.
do
  local save = newSave()
  Phone.initReceiveDelay(save, at(9, 0))
  Phone.checkReceiveCallTimer(save, at(9, 19))
  Phone.onMapLoad(save, at(9, 19))
  check("a map load resets the countdown", save.phone.delayMins, 20)
  check("and the cycle counter with it", save.phone.timeCycles, 0)
end

-- ------------------------------------------------------ who can call

-- GetAvailableCallers: the SCRIPT2_TIME mask has to cover the current time of
-- day, and a contact standing on your own map is skipped.
local ROUTE_30 = { id = "ROUTE_30", environment = "ROUTE", phoneService = true }
local ROUTE_31 = { id = "ROUTE_31", environment = "ROUTE", phoneService = true }
local NO_SERVICE = { id = "SPROUT_TOWER_1F", environment = "INDOOR",
  phoneService = false }

do
  local save = newSave()
  Phone.addContact(save, 15) -- Joey, ROUTE_30
  Phone.addContact(save, 16) -- Wade, ROUTE_31
  local here = { map = ROUTE_30, timeOfDay = "DAY" }
  local callers = Phone.availableCallers(save, here)
  check("one caller is available on Route 30", #callers, 1)
  check("and it is not the trainer standing there", callers[1], 16)
  local elsewhere = Phone.availableCallers(save,
    { map = { id = "ROUTE_32", phoneService = true }, timeOfDay = "DAY" })
  check("off both their maps, both are available", #elsewhere, 2)
end

-- CheckTime's table has no live DARKNESS row, so a dark map resolves to c = 0
-- and nobody's ANYTIME mask can match it.
do
  local save = newSave()
  Phone.addContact(save, 15)
  check("darkness leaves nobody available",
    #Phone.availableCallers(save, { map = ROUTE_31, timeOfDay = "DARK" }), 0)
end

-- Mom's SCRIPT2_TIME is 0, so she is never sampled however full the book is.
do
  local save = newSave()
  Phone.addContact(save, Phone.PHONECONTACT_MOM)
  check("Mom is never an available caller",
    #Phone.availableCallers(save, { map = ROUTE_31, timeOfDay = "DAY" }), 0)
end

-- ChooseRandomCaller: swap the nibbles of one random byte, mask to 0..31, then
-- take it modulo the number of callers (SimpleDivide returns the remainder).
do
  local callers = { 15, 16, 17 }
  -- $10 swaps to $01, & $1f = 1, 1 % 3 = 1 -> the second caller.
  check("a seeded roll picks the second caller",
    Phone.chooseRandomCaller(callers, rolls(0x10)), 16)
  -- $20 swaps to $02, & $1f = 2, 2 % 3 = 2 -> the third.
  check("and another picks the third",
    Phone.chooseRandomCaller(callers, rolls(0x20)), 17)
  -- $30 swaps to $03, & $1f = 3, 3 % 3 = 0 -> back to the first.
  check("the modulo wraps", Phone.chooseRandomCaller(callers, rolls(0x30)), 15)
  check("an empty list samples nothing",
    Phone.chooseRandomCaller({}, rolls(0x10)), nil)
end

-- CheckTime derives wTimeOfDay from the hour, on
-- constants/misc_constants.asm's boundaries: MORN at 4, DAY at 10, NITE at 18.
check("3am is night", Phone.timeOfDay(at(3, 0)), Phone.NITE)
check("4am is morning", Phone.timeOfDay(at(4, 0)), Phone.MORN)
check("10am is day", Phone.timeOfDay(at(10, 0)), Phone.DAY)
check("6pm is night again", Phone.timeOfDay(at(18, 0)), Phone.NITE)

-- GetMapPhoneService returns the header nybble and every caller tests it
-- against zero, so ZERO means the map HAS service; maps.lua already decodes
-- that into a boolean.
check("a serviced map has a signal", Phone.mapHasService({ map = ROUTE_30 }),
  true)
check("a dead zone does not", Phone.mapHasService({ map = NO_SERVICE }), false)

-- ------------------------------------------------------ the random-call gate

-- CheckPhoneCall, in order: not on an entrance tile, the timer has expired, a
-- 50% coin flip, the map has a signal, and someone is available.
local function armedSave()
  local save = newSave()
  Phone.addContact(save, 15) -- Joey, ROUTE_30
  Phone.initReceiveDelay(save, at(9, 0))
  return save
end

do
  local save = armedSave()
  local call = Phone.tryRandomCall(save, {
    map = ROUTE_31, timeOfDay = "DAY", clock = { hour = 9, minute = 20 },
    rng = rolls(0x00, 0x00),
  })
  check("a call lands once every gate passes", call ~= nil, true)
  check("from the contact in the book", call and call.contact, 15)
  check("running their caller script", call and call.script,
    "JoeyPhoneCallerScript")
  check("keyed for scripts.lua", call and call.scriptKey, "41:4368")
  check("and it is an incoming call", call and call.direction, "incoming")
end

do
  local save = armedSave()
  check("standing on a door refuses the call", Phone.tryRandomCall(save, {
    map = ROUTE_31, timeOfDay = "DAY", clock = { hour = 9, minute = 20 },
    standingOnEntrance = true, rng = rolls(0x00, 0x00),
  }), nil)
  check("and the timer is untouched by the refusal",
    save.phone.delayMins, 20)
end

do
  local save = armedSave()
  check("too soon is no call", Phone.tryRandomCall(save, {
    map = ROUTE_31, timeOfDay = "DAY", clock = { hour = 9, minute = 5 },
    rng = rolls(0x00, 0x00),
  }), nil)
  check("but the countdown still ran down", save.phone.delayMins, 15)
end

do
  local save = armedSave()
  -- `and %01111111 / cp b`: a byte with its top bit set fails the flip.
  check("the coin flip refuses half the time", Phone.tryRandomCall(save, {
    map = ROUTE_31, timeOfDay = "DAY", clock = { hour = 9, minute = 20 },
    rng = rolls(0x80),
  }), nil)
end

do
  local save = armedSave()
  check("no signal is no call", Phone.tryRandomCall(save, {
    map = NO_SERVICE, timeOfDay = "DAY", clock = { hour = 9, minute = 20 },
    rng = rolls(0x00, 0x00),
  }), nil)
end

do
  local save = armedSave()
  check("nobody available is no call", Phone.tryRandomCall(save, {
    map = ROUTE_30, timeOfDay = "DAY", clock = { hour = 9, minute = 20 },
    rng = rolls(0x00, 0x00),
  }), nil)
end

-- ------------------------------------------------------ special calls

-- Script_specialphonecall parks the id in wSpecialPhoneCallID;
-- Script_checkphonecall reports whether one is waiting; CheckSpecialPhoneCall
-- fires it the next time its condition holds.
do
  local save = newSave()
  check("nothing is queued to start with", Phone.hasSpecialCall(save), false)
  Phone.queueSpecialCall(save, Phone.SPECIALCALL.SPECIALCALL_ROBBED)
  check("queueing one shows up", Phone.hasSpecialCall(save), true)
  check("and readvar VAR_SPECIALPHONECALL sees the id",
    Phone.specialCallVar(save), 2)
  -- SpecialCallOnlyWhenOutside takes TOWN and ROUTE and nothing else.
  check("indoors it holds off",
    Phone.checkSpecialCall(save, { map = NO_SERVICE }), nil)
  local call = Phone.checkSpecialCall(save, { map = ROUTE_30 })
  check("outdoors it fires", call ~= nil, true)
  check("as Elm", call and call.contact, Phone.PHONECONTACT_ELM)
  check("with the special call's script, not Elm's own",
    call and call.script, "ElmPhoneCallerScript")
  check("naming which special call it is", call and call.special, 2)
  check("and pausing thirty frames first", call and call.delay, 30)
end

-- SPECIALCALL_WORRIED is Mom's lecture, and its condition is
-- SpecialCallWhereverYouAre -- it reaches you indoors too.
do
  local save = newSave()
  Phone.queueSpecialCall(save, Phone.SPECIALCALL.SPECIALCALL_WORRIED)
  local call = Phone.checkSpecialCall(save, { map = NO_SERVICE })
  check("Mom's lecture reaches you anywhere", call ~= nil, true)
  check("from Mom", call and call.contact, Phone.PHONECONTACT_MOM)
  check("running her lecture script", call and call.script,
    "MomPhoneLectureScript")
end

-- engine/phone/phone.asm:431
do
  local save = newSave()
  Phone.queueSpecialCall(save, Phone.SPECIALCALL.SPECIALCALL_ASSISTANT)
  local call = Phone.checkSpecialCall(save, { map = ROUTE_30 })
  check("the queued call fires", call ~= nil, true)
  Phone.endCall(save, call, at(9, 0))
  check("hanging up leaves the queue to the script",
    Phone.hasSpecialCall(save), true)
  check("and the receive timer restarts", save.phone.delayMins, 20)
end

-- ------------------------------------------------------ rematches

-- engine/phone/scripts/trainers.asm: the .WantsBattle branch of a caller
-- script sets EVENT_<NAME>_READY_FOR_REMATCH.  The numbers are wEventFlags bit
-- indexes counted through constants/event_flags.asm.
do
  local events = Events.new()
  check("Joey has a rematch flag", Phone.rematchEvent(15), 628)
  check("and Erin the last one", Phone.rematchEvent(36), 670)
  check("Mom has none", Phone.rematchEvent(Phone.PHONECONTACT_MOM), nil)
  check("nobody is waiting yet", Phone.isReadyForRematch(events, 15), false)
  check("setting the flag works", Phone.setRematchReady(events, 15), true)
  check("and Joey is waiting", Phone.isReadyForRematch(events, 15), true)
  check("without dragging anyone else in",
    Phone.isReadyForRematch(events, 16), false)
  check("a contact with no flag cannot be set",
    Phone.setRematchReady(events, Phone.PHONECONTACT_MOM), false)
end

-- ------------------------------------------------------ outgoing calls

-- MakePhoneCallFromPokegear.  Three outcomes: the call, "just go talk to that
-- person" when they are on this map, and out of area.
do
  local save = newSave()
  Phone.addContact(save, 15)
  local call = Phone.call(save, 15, { map = ROUTE_31 })
  check("calling Joey runs his callee script", call.script,
    "JoeyPhoneCalleeScript")
  check("as an outgoing call", call.direction, "outgoing")
  check("standing on his map says go talk to him",
    Phone.call(save, 15, { map = ROUTE_30 }).kind, "justtalk")
  check("no signal is out of area",
    Phone.call(save, 15, { map = NO_SERVICE }).kind, "outofarea")
  check("and so is a link session",
    Phone.call(save, 15, { map = ROUTE_31, linkMode = true }).kind, "outofarea")
end

-- The bike shop's SCRIPT1_TIME is 0: there is no hour at which you can call
-- them, only one at which they call you.
do
  local save = newSave()
  check("the bike shop cannot be called",
    Phone.call(save, Phone.PHONECONTACT_BIKESHOP,
      { map = ROUTE_31, timeOfDay = "DAY" }).kind, "outofarea")
end

-- ------------------------------------------------------ the phone card

local function newInput()
  local input = { pressed = {} }
  function input:press(...)
    for _, button in ipairs({ ... }) do self.pressed[button] = true end
  end
  function input:wasPressed(button)
    if self.pressed[button] then
      self.pressed[button] = nil
      return true
    end
    return false
  end
  function input:isDown() return false end
  return input
end

-- Just enough of data/generated/trainers.lua for GetCallerClassAndName: the
-- contact table stores class and member ids, and the names come off that
-- table.  Stubbed rather than loaded so this suite stays ROM-free.
local TRAINERS = { classes = {
  YOUNGSTER = { id = "YOUNGSTER", name = "YOUNGSTER", index = 24,
    trainers = { { id = "JOEY1", name = "JOEY" } } },
  BUG_CATCHER = { id = "BUG_CATCHER", name = "BUG CATCHER", index = 2,
    trainers = { { id = "WADE1", name = "WADE" } } },
} }

-- A Pokegear parked on the PHONE card, inside it rather than on the strip.
local function newGear(save, opts)
  opts = opts or {}
  local input = newInput()
  local game = {
    input = input,
    save = save,
    data = { audio = {}, pokemon = {}, items = {},
      text = require("tests.fixture_data.gen2_rom_text_s7_d").text() },
    stack = { push = function() end, pop = function() end },
  }
  -- Pokegear:visibleCards keys off wPokegearFlags; without the PHONE bit the
  -- card is not on the strip at all.
  save.pokegearFlags = save.pokegearFlags or {}
  save.pokegearFlags.phone = true
  local gear = Pokegear.new(game, {
    save = save,
    mapDef = opts.mapDef or ROUTE_31,
    clock = { hour = 9, minute = 0, weekday = 1 },
    trainers = TRAINERS,
    onCall = opts.onCall,
  })
  gear.mode = "card"
  for index, card in ipairs(gear.cards) do
    if card.id == "phone" then gear.cardIndex = index end
  end
  return gear, input
end

do
  local save = newSave()
  for _, id in ipairs({ 15, 16, 17, 18, 19, 20 }) do
    Phone.addContact(save, id)
  end
  local gear, input = newGear(save)
  check("the card opens on the phone", gear:card().id, "phone")
  check("with the cursor at the top", gear.phoneCursor, 0)
  -- PokegearPhone_GetDPad: the cursor walks the four visible rows first.
  for _ = 1, 3 do
    input:press("down")
    gear:update(0)
  end
  check("down walks the cursor to the last visible row", gear.phoneCursor, 3)
  check("without scrolling yet", gear.phoneScroll, 0)
  input:press("down")
  gear:update(0)
  check("the next press scrolls instead", gear.phoneScroll, 1)
  check("leaving the cursor where it is", gear.phoneCursor, 3)
  check("on the fifth contact", gear:phoneSelection(), 19)
  -- .scroll_page_down stops dead at CONTACT_LIST_SIZE - PHONE_DISPLAY_HEIGHT.
  for _ = 1, 20 do
    input:press("down")
    gear:update(0)
  end
  check("the scroll stops at the end of the list", gear.phoneScroll, 6)
  for _ = 1, 20 do
    input:press("up")
    gear:update(0)
  end
  check("and up unwinds it to the top", gear.phoneScroll, 0)
  check("with the cursor back at row 0", gear.phoneCursor, 0)
end

-- `.a` returns straight back out on an empty slot: no submenu, no call.
do
  local save = newSave()
  local gear, input = newGear(save)
  input:press("a")
  gear:update(0)
  check("an empty slot opens nothing", gear.phoneSubmenu, nil)
end

-- CheckCanDeletePhoneNumber picks which submenu opens.
do
  local save = newSave()
  Phone.addContact(save, Phone.PHONECONTACT_MOM)
  Phone.addContact(save, 15)
  local gear, input = newGear(save)
  input:press("a")
  gear:update(0)
  check("MOM gets the CALL/CANCEL menu", gear.phoneSubmenu, "callCancel")
  input:press("b")
  gear:update(0)
  check("B closes it", gear.phoneSubmenu, nil)
  check("without leaving the card", gear.mode, "card")
  input:press("down")
  gear:update(0)
  input:press("a")
  gear:update(0)
  check("a trainer gets CALL/DELETE/CANCEL", gear.phoneSubmenu,
    "callDeleteCancel")
end

-- The submenu's CALL entry runs MakePhoneCallFromPokegear and hands the
-- descriptor out to whoever can run its script.
do
  local save = newSave()
  Phone.addContact(save, 15)
  local seen
  local gear, input = newGear(save, { onCall = function(c) seen = c end })
  input:press("a")
  gear:update(0)
  input:press("a")
  gear:update(0)
  check("CALL places the call", gear.call ~= nil, true)
  check("to Joey", gear.call and gear.call.contact, 15)
  check("and hands the descriptor out", seen == gear.call, true)
  check("naming his callee script", seen and seen.script,
    "JoeyPhoneCalleeScript")
  check("with his name for the textbox", seen and seen.name, "JOEY")
  check("and his class under it", seen and seen.className, "YOUNGSTER")
  -- Bank $41 is not extracted, so there is no line to run: the card shows what
  -- the cart shows while a call connects.
  check("the box shows the caller and the ellipsis",
    gear.call and gear.call.text, "JOEY: ……")
  input:press("b")
  gear:update(0)
  check("any button hangs up", gear.call, nil)
  check("still inside the card", gear.mode, "card")
end

-- .no_service never reaches MakePhoneCallFromPokegear at all: it plays
-- SFX_NO_SIGNAL and prints its own out-of-service line.
do
  local save = newSave()
  Phone.addContact(save, 15)
  local gear, input = newGear(save, { mapDef = NO_SERVICE })
  input:press("a")
  gear:update(0)
  input:press("a")
  gear:update(0)
  check("a dead zone refuses the call", gear.call and gear.call.kind,
    "nosignal")
end

-- DELETE goes through the compacting delete, so the row below moves up.
do
  local save = newSave()
  Phone.addContact(save, 15)
  Phone.addContact(save, 16)
  local gear, input = newGear(save)
  input:press("a")
  gear:update(0)
  input:press("down")
  gear:update(0)
  check("the cursor is on DELETE", gear.phoneSubmenuCursor, 1)
  input:press("a")
  gear:update(0)
  check("the submenu closes", gear.phoneSubmenu, nil)
  check("Joey is gone", Phone.hasContact(save, 15), false)
  check("and Wade has moved up", Phone.contacts(save)[1], 16)
end

-- The list draws every visible slot, empty ones included: GetCallerName maps
-- contact 0 to NonTrainerCallerNames' dashes.
do
  local save = newSave()
  Phone.addContact(save, 15)
  local gear = newGear(save)
  local label, className = gear:contactRow(0)
  check("an empty row still has a label", label, "----------:")
  check("with no class under it", className, nil)
  local name = gear:contactRow(Phone.PHONECONTACT_MOM)
  check("MOM's row is her name and a colon", name, "MOM:")
end

-- data/text/common_3.asm:43
do
  local save = newSave()
  local gear = newGear(save)
  check("the prompt is the cache's _PokegearAskWhoCallText",
    gear:phoneText("AskWhoCall"), "Whom do you want\nto call?")
  gear.textData = { _PokegearAskWhoCallText = "EXTRACTED{DONE}" }
  check("read from rom_text by label",
    gear:phoneText("AskWhoCall"), "EXTRACTED")
  gear.textData = {}
  check("and a cache without the label is an error",
    pcall(gear.phoneText, gear, "AskWhoCall"), false)
end

-- ------------------------------------------------------ the save

-- Everything the phone persists rides one block on the Gold save, and
-- Save.normalize has to leave it alone.
do
  local save = newSave()
  Phone.addContact(save, 15)
  Phone.queueSpecialCall(save, Phone.SPECIALCALL.SPECIALCALL_ROBBED)
  Phone.initReceiveDelay(save, at(9, 0))
  Save.normalize(save)
  check("the phone block survives normalize", type(save.phone), "table")
  check("with the contact list", save.phone.list[1], 15)
  check("the queued special call", save.phone.specialCall, 2)
  check("the cycle counter", save.phone.timeCycles, 0)
  check("the countdown", save.phone.delayMins, 20)
  check("and its start stamp", save.phone.delayStart.hour, 9)
  check("and the legacy set is still mirrored", save.phoneContacts[15], true)
end

-- ------------------------------------------------------ against the cache
--
-- The tables in Phone.lua were transcribed from data/phone/*.asm and the
-- symbol file at a time when nothing pointed into ROM bank $41.  The extractor
-- follows PhoneContacts and SpecialPhoneCallList now, so the two must agree --
-- and every script key they name has to be a real entry in scripts.lua, or a
-- call arrives with a body that cannot run and the step counter stalls.
do
  local cacheDir = os.getenv("GOLD_CACHE")
  if not cacheDir then
    local home = os.getenv("HOME") or ""
    cacheDir = home .. "/Library/Application Support/LOVE/gold-dev/gold"
  end
  local eventsFile = loadfile(cacheDir .. "/data/generated/events.lua")
  if not eventsFile then
    check("cache absent or predates events.lua (SKIP)", true, true)
  else
    local events = eventsFile()
    local scripts = assert(loadfile(
      cacheDir .. "/data/generated/scripts.lua"))()
    check("useExtracted takes the cache's rows", Phone.useExtracted(events), true)
    for index = 0, #PHONE.constants.phoneContactOrder - 1 do
      local row = Phone.CONTACTS[index]
      local was = Phone.SCRIPT_KEYS[row.callee]
      check(("contact %d callee key matches the transcription"):format(index),
        row.calleeKey, was)
      check(("contact %d caller key matches"):format(index),
        row.callerKey, Phone.SCRIPT_KEYS[row.caller])
      check(("contact %d callee script is in scripts.lua"):format(index),
        scripts[row.calleeKey] ~= nil, true)
      check(("contact %d caller script is in scripts.lua"):format(index),
        scripts[row.callerKey] ~= nil, true)
    end
    -- The five Elm special calls all point at ElmPhoneCallerScript, which is
    -- what lets one contact serve five different scripted beats; the bike shop
    -- and Mom have their own.
    for id, entry in pairs(Phone.SPECIAL_CALLS) do
      check(("special call %d key matches the transcription"):format(id),
        entry.scriptKey, Phone.SCRIPT_KEYS[entry.script])
      check(("special call %d script is in scripts.lua"):format(id),
        scripts[entry.scriptKey] ~= nil, true)
    end
    -- SPECIALCALL_ROBBED is Elm's "your POKeMON was stolen" beat, and its
    -- script really is the shared caller script that branches on
    -- VAR_SPECIALPHONECALL rather than a script of its own.
    local robbed = Phone.SPECIAL_CALLS[Phone.SPECIALCALL.SPECIALCALL_ROBBED]
    check("SPECIALCALL_ROBBED rings PROF.ELM",
      robbed.contact, Phone.PHONECONTACT_ELM)
    check("and its script reads VAR_SPECIALPHONECALL first",
      scripts[robbed.scriptKey][1].op, "readvar")
    -- The engine's own two scripts live in bank $24 and are reached without a
    -- contact row; they are seeded by nothing but a map pointer, so this is
    -- the check that says whether they came along.
    check("PhoneOutOfAreaScript is reachable",
      scripts[Phone.SCRIPT_KEYS.PhoneOutOfAreaScript] ~= nil, true)
    -- The wiring around a landed call: the gate's descriptor drops straight
    -- into Script_ReceivePhoneCall's rows (src/core/gen2/PhoneRing.lua,
    -- driven end to end by tests/gen2_phone_call_test.lua) and the caller
    -- script it wraps, resolved through the cache overlay just applied, is
    -- live in this cache.
    local PhoneRing = require("src.core.gen2.PhoneRing")
    local armed = armedSave()
    local landed = Phone.tryRandomCall(armed, {
      map = ROUTE_31, timeOfDay = "DAY", clock = { hour = 9, minute = 20 },
      rng = rolls(0x00, 0x00),
    })
    check("the gate lands a call with the cache rows applied",
      landed ~= nil, true)
    local rows = PhoneRing.script(landed, "JOEY")
    -- Two waitsfx/callasm ring passes now, RingTwice_StartCall's `call .Ring`
    -- plus its fallthrough (engine/phone/phone.asm:458-469), so the caller
    -- script sits four rows further down than it used to.
    check("the wrapper rings before the caller script",
      rows[3].label, "RingTwice_StartCall")
    check("restarts the countdown after it",
      rows[12].label, "InitCallReceiveDelay")
    check("and the script it wraps is live in this cache",
      scripts[rows[8].script] ~= nil, true)
  end
end

print(("gen2 phone: %d checks, %d failures"):format(checks, failures))
-- Raise rather than os.exit: tests/run_tests.lua dofiles this file, so an exit
-- here takes the whole tier down with it.
if failures > 0 then
  error(("%d assertion(s) failed"):format(failures), 0)
end
