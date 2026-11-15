-- The POKeGEAR's phone (engine/phone/phone.asm, data/phone/*.asm and the
-- receive-call timer in engine/overworld/time.asm).
--
-- love-free on purpose: everything here is model.  The Pokegear card
-- (src/ui/gen2/Pokegear.lua) drives the outgoing half, the script VM
-- (src/script/gen2/Vm.lua) drives the incoming half and the four phone
-- opcodes, and both talk to this module rather than to each other.
--
-- The cart's phone is three separate machines that share one contact table:
--
--   OUTGOING  MakePhoneCallFromPokegear.  You pick a name off wPhoneList; the
--             contact's SCRIPT1 ("callee": you called them) runs, unless there
--             is no signal, unless they cannot take a call at this time of
--             day, or unless you are standing on their own map -- in which
--             case the game tells you to go talk to them instead.
--
--   INCOMING  CheckPhoneCall, run once per step out of PlayerEvents.  A gate
--             of five tests decides whether anyone rings; if one does, that
--             contact's SCRIPT2 ("caller": they called you) runs.  This is the
--             half that hands out the trainer rematch flags.
--
--   SPECIAL   CheckSpecialPhoneCall, run BEFORE the step is counted.  A script
--             somewhere in the world has done `specialphonecall N`, which
--             parks N in wSpecialPhoneCallID; the next time its condition
--             holds, that scripted call jumps the queue.  This is main quest,
--             not flavour: Elm's "your POKeMON was stolen" and "the egg
--             hatched" beats, Mom's lecture and the bike shop's call are all
--             special calls.
--
-- Notes that cost real time to work out, kept here so the next reader does not
-- have to:
--
--   * PhoneContacts rows carry TWO time-of-day masks.  SCRIPT1_TIME gates YOU
--     calling THEM, SCRIPT2_TIME gates THEM calling YOU.  Mom, Elm, Bill and
--     the bike shop all have SCRIPT2_TIME 0, so none of them can ever be
--     picked as a random caller -- every unprompted call from Elm arrives
--     through the special-call queue.
--
--   * The delay timer is restarted by StartMap (engine/overworld/events.asm
--     `farcall InitCallReceiveDelay`), so it starts over at twenty in-game
--     minutes on EVERY map load.  A player who keeps warping is never called.
--
--   * The queue is cleared by the called script itself (`specialphonecall
--     SPECIALCALL_NONE` is the first or second line of every special caller
--     script), not by the engine.
--
-- The call scripts live in ROM bank $41, which the extractor reaches by
-- seeding its queue from PhoneContacts and SpecialPhoneCallList (no map
-- points into that bank, so those two tables are the only way in), and
-- Phone.useExtracted builds every contact row from the cache.  A call's presentation
-- (the ring, the Click!, the countdown restart) is src/core/gen2/PhoneRing.lua.

local Runtime = require("src.mods.Runtime")
local Merge = require("src.mods.Merge")

local Phone = {}

-- ------------------------------------------------------- constants

-- constants/phone_constants.asm
Phone.CONTACT_LIST_SIZE = 10
Phone.SPECIALCALL_NONE = 0
Phone.NUM_SPECIALCALLS = 8

-- constants/ram_constants.asm wTimeOfDay.  DARKNESS has no bit of its own in
-- CheckTime's table, and IsInArray stops at the first match, so a dark map
-- resolves to c = 0: nobody is available and no contact can be called.
Phone.MORN, Phone.DAY, Phone.NITE = 1, 2, 4
Phone.ANYTIME = 7 -- MORN | DAY | NITE

-- constants/misc_constants.asm time of day boundaries.
local MORN_HOUR, DAY_HOUR, NITE_HOUR = 4, 10, 18
local MAX_HOUR = 24
-- _CalcDaysSince wraps with `add 20 * 7`; wCurDay counts inside that window.
local MAX_DAY = 140

-- constants/script_constants.asm, askforphonenumber return values.
Phone.CONTACT_GOT = 0
Phone.CONTACTS_FULL = 1
Phone.CONTACT_REFUSED = 2

-- constants/script_constants.asm readvar id, for the VM's readVar hook:
-- `dwb wSpecialPhoneCallID, RETVAR_STRBUF2` (engine/overworld/variables.asm).
Phone.VAR_SPECIALPHONECALL = 0x14

-- constants/map_data_constants.asm environments.  SpecialCallOnlyWhenOutside
-- takes TOWN and ROUTE and nothing else.
local OUTSIDE_ENVIRONMENTS = { TOWN = true, ROUTE = true }

-- constants/trainer_constants.asm.  That block opens `const_def 1`, so the
-- non-trainer contacts are ONE based and PHONECONTACT_MOM is 1, not 0.  They
-- double as PhoneContacts row indexes, which is why SpecialPhoneCallList can
-- hand PHONECONTACT_ELM straight to LoadCallerScript.
Phone.PHONECONTACT_MOM = 1
Phone.PHONECONTACT_BIKESHOP = 2
Phone.PHONECONTACT_BILL = 3
Phone.PHONECONTACT_ELM = 4

-- data/phone/non_trainer_names.asm:1
Phone.NON_TRAINER_NAMES = {}
Phone.NON_TRAINER_TITLES = {}

-- data/phone/permanent_numbers.asm:1
Phone.PERMANENT_NUMBERS = {}

-- ------------------------------------------------------- the contact table

-- data/phone/phone_contacts.asm:1
Phone.CONTACTS = {}

local registryRows, registryOrder, registryConstants
local nativeContacts = {}

local function required(events)
  if type(events) ~= "table" then error("events.lua is missing", 3) end
  for _, key in ipairs({ "phone", "phoneScripts", "phoneNames", "specialCalls",
      "permanentNumbers" }) do
    if type(events[key]) ~= "table" then error("events.lua has no " .. key, 3) end
  end
end

local function scriptLabels(events)
  local byKey = {}
  for label, row in pairs(events.phoneScripts) do
    local key = row.script
    if key and (byKey[key] == nil or label < byKey[key]) then byKey[key] = label end
  end
  return byKey
end

-- data/phone/non_trainer_names.asm:1
local function splitName(raw)
  local head, tail = raw:match("^(.-)<LF>%s*(.*)$")
  head = (head or raw):gsub(":$", "")
  if tail == "" then tail = nil end
  return head, tail
end

local function readNames(events)
  for key in pairs(Phone.NON_TRAINER_NAMES) do Phone.NON_TRAINER_NAMES[key] = nil end
  for key in pairs(Phone.NON_TRAINER_TITLES) do Phone.NON_TRAINER_TITLES[key] = nil end
  for number, raw in pairs(events.phoneNames) do
    Phone.NON_TRAINER_NAMES[number], Phone.NON_TRAINER_TITLES[number] = splitName(raw)
  end
end

local function rematchFlags(constants)
  local out = {}
  if type(constants) ~= "table" then return out end
  if type(constants.rematchFlags) ~= "table" then
    error("constants.lua has no rematchFlags", 4)
  end
  for _, row in ipairs(constants.rematchFlags) do
    out[row[1]] = { kind = row[2], flag = row[3] }
  end
  return out
end

local function bookFrom(events, constants)
  required(events)
  readNames(events)
  for i = #Phone.PERMANENT_NUMBERS, 1, -1 do Phone.PERMANENT_NUMBERS[i] = nil end
  for i, id in ipairs(events.permanentNumbers) do Phone.PERMANENT_NUMBERS[i] = id end
  local labels = scriptLabels(events)
  local rematch = rematchFlags(constants)
  local book = {}
  for index, row in pairs(events.phone) do
    local dest = {
      index = index, map = row.map,
      calleeTime = row.calleeTime, callerTime = row.callerTime,
      calleeKey = row.callee, callerKey = row.caller,
      callee = labels[row.callee], caller = labels[row.caller],
    }
    local flag = rematch[index]
    if flag and flag.kind == "event" then
      dest.rematchEvent = flag.flag
    elseif flag then
      dest.rematchEngineFlag = flag.flag
    end
    if row.trainerClass ~= 0 then
      local order = constants and constants.trainerClassOrder
      if type(order) ~= "table" then
        error("PhoneContacts row " .. index .. " needs constants.trainerClassOrder", 3)
      end
      dest.class = order[row.trainerClass + 1]
      dest.member = ((constants.trainerClassMembers or {})[dest.class] or {})[row.number]
    else
      dest.number = row.number
      dest.name = Phone.NON_TRAINER_NAMES[row.number]
    end
    book[index] = dest
  end
  return book
end

local function applyRegistryRows()
  Phone.CONTACTS = Merge.deepCopy(nativeContacts)
  if not registryRows then return 0 end
  for index, id in ipairs(registryOrder or {}) do
    if id ~= "PHONE_UNUSED" and registryRows[id] == nil then Phone.CONTACTS[index - 1] = nil end
  end
  local applied = 0
  for _, record in pairs(registryRows) do
    local index = type(record) == "table" and record.index
    if type(index) == "number" then
      Phone.CONTACTS[index] = Merge.deepCopy(record)
      applied = applied + 1
    end
  end
  return applied
end

-- vanilla registrations, engine-owned; `data` carries the constant order the
-- ids come from, so a dataset without it registers nothing rather than
-- inventing names
function Phone.registerInto(registry, data, owner)
  local order = data and data.gen2Constants and data.gen2Constants.phoneContactOrder
  if type(order) ~= "table" then return 0 end
  local book = bookFrom(data.gen2EventTables, data.gen2Constants)
  local count = 0
  for index = 0, #order - 1 do
    local id = order[index + 1]
    local row = book[index]
    if type(id) == "string" and id ~= "PHONE_UNUSED" and row then
      registry:register(id, row, owner)
      count = count + 1
    end
  end
  return count
end

-- the merged table, held by reference and folded onto the contact rows.  Pass
-- nil to forget it (a second dataset in one process).
function Phone.useRegistry(data)
  registryRows = data and data.gen2PhoneContacts or nil
  registryConstants = data and data.gen2Constants
  registryOrder = registryConstants and registryConstants.phoneContactOrder
  nativeContacts = data and bookFrom(data.gen2EventTables, registryConstants) or {}
  return applyRegistryRows()
end

-- ------------------------------------------------------- script keys

Phone.SCRIPT_KEYS = {}

function Phone.scriptKey(label)
  return label and Phone.SCRIPT_KEYS[label] or nil
end

-- ------------------------------------------------------- special calls

-- data/phone/special_calls.asm:1
Phone.SPECIAL_CALLS = {}
Phone.SPECIALCALL = { SPECIALCALL_NONE = 0 }

-- pokegold/data/phone/phone_contacts.asm:12
function Phone.useExtracted(events)
  required(events)
  nativeContacts = bookFrom(events, registryConstants)
  local labels = scriptLabels(events)
  for key in pairs(Phone.SPECIAL_CALLS) do Phone.SPECIAL_CALLS[key] = nil end
  for key in pairs(Phone.SPECIALCALL) do Phone.SPECIALCALL[key] = nil end
  Phone.SPECIALCALL.SPECIALCALL_NONE = Phone.SPECIALCALL_NONE
  for _, row in ipairs(events.specialCalls) do
    Phone.SPECIAL_CALLS[row.id] = {
      name = row.call, condition = row.when, contact = row.contact,
      script = labels[row.script], scriptKey = row.script,
    }
    Phone.SPECIALCALL[row.call] = row.id
  end
  for label in pairs(Phone.SCRIPT_KEYS) do Phone.SCRIPT_KEYS[label] = nil end
  for label, row in pairs(events.phoneScripts) do
    Phone.SCRIPT_KEYS[label] = row.script
  end
  applyRegistryRows()
  return true
end

-- ------------------------------------------------------- save state
--
-- src/core/gen2/Save.lua owns the file; this is the block the phone keeps in
-- it.  `list` is wPhoneList (ten ordered slots, 0 = empty), which is the shape
-- the Pokegear reads and the shape AddPhoneNumber's reserved-slot arithmetic
-- needs -- a set of ids cannot answer "which slot".
--
-- save.phoneContacts (the id -> true set the VM's addcellnum/checkcellnum
-- hooks already write in src/world/gen2/World.lua) is kept mirrored in both
-- directions so neither half has to change before the other does.
local function newState()
  return {
    list = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
    specialCall = 0,           -- wSpecialPhoneCallID
    timeCycles = 0,            -- wTimeCyclesSinceLastCall
    delayMins = 20,            -- wReceiveCallDelay_MinsRemaining
    delayStart = nil,          -- wReceiveCallDelay_StartTime {day,hour,minute}
  }
end

local function inList(state, id)
  for slot = 1, Phone.CONTACT_LIST_SIZE do
    if state.list[slot] == id then return slot end
  end
  return nil
end

function Phone.state(save)
  if type(save) ~= "table" then return newState() end
  local state = save.phone
  if type(state) ~= "table" then
    state = newState()
    save.phone = state
  end
  state.list = type(state.list) == "table" and state.list or {}
  for slot = 1, Phone.CONTACT_LIST_SIZE do
    state.list[slot] = tonumber(state.list[slot]) or 0
  end
  state.specialCall = tonumber(state.specialCall) or 0
  state.timeCycles = tonumber(state.timeCycles) or 0
  state.delayMins = tonumber(state.delayMins) or 20
  -- Adopt anything the VM's addcellnum hook put in the legacy set, then mirror
  -- the list back over it.  An id in the set but not the list takes the first
  -- free slot; the mirror is rebuilt from scratch so a delete propagates.
  local legacy = save.phoneContacts
  if type(legacy) == "table" then
    for key in pairs(legacy) do
      local id = tonumber(key)
      if id and id > 0 and not inList(state, id) then
        for slot = 1, Phone.CONTACT_LIST_SIZE do
          if state.list[slot] == 0 then
            state.list[slot] = id
            break
          end
        end
      end
    end
  end
  Phone.mirror(save, state)
  return state
end

-- Rebuild save.phoneContacts from wPhoneList.  Separate from Phone.state
-- because state ADOPTS the mirror first: anything that has just taken an id
-- out of the list has to mirror without adopting, or the id it removed walks
-- straight back into the first free slot.
function Phone.mirror(save, state)
  state = state or (save and save.phone) or {}
  local legacy = {}
  for slot = 1, Phone.CONTACT_LIST_SIZE do
    local id = state.list and state.list[slot]
    if id and id ~= 0 then legacy[id] = true end
  end
  save.phoneContacts = legacy
  return legacy
end

-- ------------------------------------------------------- the contact list
--
-- engine/phone/phone.asm _CheckCellNum.  Transcribed literally, including its
-- one oddity: it compares against ten slots with no "is this a real contact"
-- test, so `Phone.hasContact(save, 0)` reports true whenever a slot is empty.
-- AddPhoneNumber leans on exactly that to refuse adding contact 0.
function Phone.hasContact(save, id)
  local state = Phone.state(save)
  return inList(state, id) ~= nil
end

-- GetRemainingSpaceInPhoneList.  wRegisteredPhoneNumbers is named backwards:
-- it counts the permanent numbers you have NOT registered yet, and each one
-- costs a slot that stays reserved for it.  `id` is the number being added,
-- which is skipped (`cp c / jr z, .continue`) so a permanent number never
-- reserves a slot against itself.
function Phone.remainingSlots(save, id)
  local state = Phone.state(save)
  local reserved = 0
  for _, permanent in ipairs(Phone.PERMANENT_NUMBERS) do
    if permanent ~= id and not inList(state, permanent) then
      reserved = reserved + 1
    end
  end
  return Phone.CONTACT_LIST_SIZE - reserved
end

-- Phone_FindOpenSlot: the first empty slot inside the unreserved run.
function Phone.openSlot(save, id)
  local state = Phone.state(save)
  local usable = Phone.remainingSlots(save, id)
  for slot = 1, usable do
    if state.list[slot] == 0 then return slot end
  end
  return nil
end

-- AddPhoneNumber.  Returns true, or false plus "already" / "full" -- the cart
-- sets carry for both and Script_askforphonenumber reports either as
-- PHONE_CONTACTS_FULL, so the reason is for the port's own callers.
function Phone.addContact(save, id)
  id = tonumber(id)
  if not id or not Phone.CONTACTS[id] then return false, "unknown" end
  local state = Phone.state(save)
  if inList(state, id) then return false, "already" end
  local slot = Phone.openSlot(save, id)
  if not slot then return false, "full" end
  state.list[slot] = id
  save.phoneContacts = save.phoneContacts or {}
  save.phoneContacts[id] = true
  return true
end

-- DelCellNum: blank the slot in place, leaving the hole where it was.
function Phone.removeContact(save, id)
  local state = Phone.state(save)
  local slot = inList(state, id)
  if not slot then return false end
  state.list[slot] = 0
  Phone.mirror(save, state)
  return true
end

-- PokegearPhone_DeletePhoneNumber: the Pokegear's own delete, which blanks the
-- slot and THEN compacts the list so the display has no gap in it.  Every pass
-- of its loop pulls the next entry back one slot, which is why it runs
-- CONTACT_LIST_SIZE times rather than once.
function Phone.deleteContactAt(save, slot)
  local state = Phone.state(save)
  if not (slot and state.list[slot]) then return false end
  state.list[slot] = 0
  for _ = 1, Phone.CONTACT_LIST_SIZE do
    for index = 1, Phone.CONTACT_LIST_SIZE - 1 do
      if state.list[index] == 0 then
        state.list[index] = state.list[index + 1]
        state.list[index + 1] = 0
      end
    end
  end
  Phone.mirror(save, state)
  return true
end

-- CheckCanDeletePhoneNumber: MOM and PROF.ELM cannot be deleted, and neither
-- can an empty slot; every trainer can.  (`ld a, c / and a / ret nz` -- a row
-- with a trainer class is deletable outright.)
function Phone.canDelete(id)
  local contact = Phone.CONTACTS[id or -1]
  if not contact then return false end
  if contact.class then return true end
  if contact.number == Phone.PHONECONTACT_MOM then return false end
  if contact.number == Phone.PHONECONTACT_ELM then return false end
  return contact.number ~= 0
end

-- wPhoneList as an array of slot values, 0 for empty.  The Pokegear draws all
-- ten slots including the empty ones (they render as "----------"), so this
-- keeps them rather than compacting.
local function sameList(_, list) return list end

function Phone.contacts(save)
  local state = Phone.state(save)
  local out = {}
  for slot = 1, Phone.CONTACT_LIST_SIZE do out[slot] = state.list[slot] end
  if not Runtime.wantsHook("phone.contact_list") then return out end
  -- phone.contact_list, a Gen 2 invention: Red has no phone, so there is no
  -- Gen 1 name to share.  Shaped like the other list hooks (ui.pc.items,
  -- ui.start_menu.items) -- (save, list), returning the list to draw -- rather
  -- than a ctx table, because that is what a mod that reorders or hides rows
  -- already knows how to write.
  --
  -- The list is wPhoneList itself: exactly CONTACT_LIST_SIZE slots, each a
  -- PHONE_* contact id or 0 for an empty one, and the empty slots are part of
  -- the display.  A chain that returns something that is not a table, or one
  -- of the wrong length, is ignored: the Pokegear indexes this by slot and a
  -- short list would put the cursor on nil.  Ids the CONTACTS table does not
  -- know are blanked rather than dropped, so the slot count survives.
  local hooked = Runtime.call("phone.contact_list", sameList, save, out)
  if type(hooked) ~= "table" or #hooked ~= Phone.CONTACT_LIST_SIZE then
    return out
  end
  for slot = 1, Phone.CONTACT_LIST_SIZE do
    local id = tonumber(hooked[slot]) or 0
    hooked[slot] = Phone.CONTACTS[id] and id or 0
  end
  return hooked
end

-- Script_askforphonenumber (engine/overworld/scripting.asm).  `accepted` is
-- the YesNoBox result; the script writes one of the three PHONE_CONTACT_*
-- values into wScriptVar and its ifequal chain branches on it.
function Phone.askForNumber(save, id, accepted)
  if not accepted then return Phone.CONTACT_REFUSED end
  if Phone.addContact(save, id) then return Phone.CONTACT_GOT end
  return Phone.CONTACTS_FULL
end

-- ------------------------------------------------------- names

-- GetCallerName.  A trainer contact prints "<name>:" over its class name; a
-- non-trainer prints its NonTrainerCallerNames string and nothing under it.
-- `trainerData` is data/generated/trainers.lua; without it a trainer contact
-- still returns its member id, which is better than a bare number.
function Phone.contactName(id, trainerData)
  local contact = Phone.CONTACTS[id or -1]
  if not contact then return Phone.NON_TRAINER_NAMES[0], nil end
  -- `name` is presentation only.  Keeping class/member untouched preserves
  -- trainer lookup, rematches and script identity while allowing both the
  -- non-trainer names and an individual trainer contact to be localized by
  -- the phone_contacts registry.
  if contact.name then
    local className
    if contact.class then
      local class = trainerData and trainerData.classes
        and trainerData.classes[contact.class]
      className = (class and class.name) or contact.class
    else
      className = Phone.NON_TRAINER_TITLES[contact.number or 0]
    end
    return contact.name, className
  end
  if not contact.class then
    return Phone.NON_TRAINER_NAMES[contact.number or 0]
      or Phone.NON_TRAINER_NAMES[0], Phone.NON_TRAINER_TITLES[contact.number or 0]
  end
  local class = trainerData and trainerData.classes
    and trainerData.classes[contact.class]
  if class and class.trainers then
    for _, row in ipairs(class.trainers) do
      if row.id == contact.member then
        return row.name, class.name or contact.class
      end
    end
  end
  return contact.member, contact.class
end

-- ------------------------------------------------------- context helpers

local function rngOf(ctx)
  local rng = ctx and ctx.rng
  if rng then return rng end
  return function() return math.random(0, 255) end
end

local function clockOf(ctx)
  local clock = ctx and ctx.clock
  if type(clock) == "table" then
    return {
      day = tonumber(clock.day) or 0,
      hour = tonumber(clock.hour) or 0,
      minute = tonumber(clock.minute or clock.min) or 0,
    }
  end
  return {
    day = (tonumber(os.date("%j")) or 1) % MAX_DAY,
    hour = tonumber(os.date("%H")) or 0,
    minute = tonumber(os.date("%M")) or 0,
  }
end

-- CheckTime: wTimeOfDay -> the MORN / DAY / NITE bit.  DARKNESS is absent from
-- .TimeOfDayTable's live rows, so it comes back as 0.
local TIME_BITS = {
  MORN = Phone.MORN, DAY = Phone.DAY, NITE = Phone.NITE,
  MORN_F = Phone.MORN, DAY_F = Phone.DAY, NITE_F = Phone.NITE,
  DARK = 0, DARKNESS = 0,
}

function Phone.timeOfDay(ctx)
  local given = ctx and (ctx.timeOfDay or ctx.daytime)
  if type(given) == "number" then return given end
  if type(given) == "string" then return TIME_BITS[given] or 0 end
  local hour = clockOf(ctx).hour
  if hour < MORN_HOUR then return Phone.NITE end
  if hour < DAY_HOUR then return Phone.MORN end
  if hour < NITE_HOUR then return Phone.DAY end
  return Phone.NITE
end

-- Lua 5.1 has no bit ops in the base library and this module stays
-- dependency-free, so AND the three time bits by hand.
local function timeMatches(mask, checked)
  mask = mask or 0
  checked = checked or 0
  for _, bit in ipairs({ Phone.MORN, Phone.DAY, Phone.NITE }) do
    if math.floor(mask / bit) % 2 == 1 and math.floor(checked / bit) % 2 == 1 then
      return true
    end
  end
  return false
end

Phone.timeMatches = timeMatches

-- GetMapPhoneService returns the map header's phone-service nybble and every
-- caller tests `and a` -- ZERO means the map HAS service.  maps.lua already
-- decodes that nybble into a boolean, so a map record can be handed in whole.
local function mapRecord(ctx)
  local map = ctx and ctx.map
  if type(map) == "table" then return map end
  return nil
end

function Phone.mapHasService(ctx)
  local record = mapRecord(ctx)
  if record ~= nil and record.phoneService ~= nil then
    return record.phoneService and true or false
  end
  if ctx and ctx.phoneService ~= nil then
    return ctx.phoneService and true or false
  end
  -- No header to read: assume service, the way most of Johto has it.
  return true
end

local function currentMapId(ctx)
  local record = mapRecord(ctx)
  if record then return record.id end
  local map = ctx and ctx.map
  if type(map) == "string" then return map end
  return ctx and ctx.mapId or nil
end

-- The wMapGroup / wMapNumber compare from GetAvailableCallers and
-- MakePhoneCallFromPokegear: a contact standing on your own map is skipped.
function Phone.onSameMap(contact, ctx)
  if not (contact and contact.map) then return false end
  local here = currentMapId(ctx)
  if here then return here == contact.map end
  local record = mapRecord(ctx)
  local maps = ctx and ctx.maps
  local theirs = maps and maps[contact.map]
  if record and theirs then
    return record.group == theirs.group and record.map == theirs.map
  end
  return false
end

-- SpecialCallOnlyWhenOutside: TOWN and ROUTE, nothing else.
function Phone.isOutside(ctx)
  local record = mapRecord(ctx)
  local environment = (record and record.environment)
    or (ctx and ctx.environment)
  return OUTSIDE_ENVIRONMENTS[environment] == true
end

-- ------------------------------------------------------- the receive timer
--
-- engine/overworld/time.asm.  The delay is a countdown in in-game minutes with
-- a rebasing start stamp: every check works out how many minutes have passed
-- since the stamp, writes the current time back over the stamp, and subtracts
-- the difference from what is left.

-- .ReceiveCallDelays, indexed by wTimeCyclesSinceLastCall (0..3, capped).  The
-- gap between calls shrinks the longer you go without one: twenty minutes for
-- the first, then ten, five and three.
Phone.RECEIVE_CALL_DELAYS = { 20, 10, 5, 3 }

-- CalcMinsHoursDaysSince, borrow chain and all.  Returns minutes, hours, days.
local function since(now, start)
  local borrow = 0
  local minutes = now.minute - start.minute - borrow
  if minutes < 0 then minutes = minutes + 60 borrow = 1 else borrow = 0 end
  local hours = now.hour - start.hour - borrow
  if hours < 0 then hours = hours + MAX_HOUR borrow = 1 else borrow = 0 end
  local days = now.day - start.day - borrow
  if days < 0 then days = days + MAX_DAY end
  return minutes, hours, days
end

-- RestartReceiveCallDelay: park the countdown and stamp "now".
function Phone.restartReceiveDelay(save, minutes, ctx)
  local state = Phone.state(save)
  state.delayMins = minutes
  state.delayStart = clockOf(ctx)
  return state
end

-- NextCallReceiveDelay.
function Phone.nextReceiveDelay(save, ctx)
  local state = Phone.state(save)
  local cycles = state.timeCycles or 0
  if cycles > 3 then cycles = 3 end
  return Phone.restartReceiveDelay(save,
    Phone.RECEIVE_CALL_DELAYS[cycles + 1], ctx)
end

-- InitCallReceiveDelay.  StartMap runs this on every map load, and so does the
-- tail of Script_ReceivePhoneCall after a call is hung up.
function Phone.initReceiveDelay(save, ctx)
  local state = Phone.state(save)
  state.timeCycles = 0
  return Phone.nextReceiveDelay(save, ctx)
end

-- StartMap's `farcall InitCallReceiveDelay`, under the name the World will
-- want to call it by.
function Phone.onMapLoad(save, ctx)
  return Phone.initReceiveDelay(save, ctx)
end

-- CheckReceiveCallDelay -> UpdateTimeRemaining.  True means the countdown has
-- reached zero.  Anything longer than an hour (or a rolled-over day) comes
-- back from GetMinutesSinceIfLessThan60 as -1, which UpdateTimeRemaining
-- treats as "expired" outright rather than trying to subtract it.
function Phone.checkReceiveCallDelay(save, ctx)
  local state = Phone.state(save)
  local now = clockOf(ctx)
  if not state.delayStart then
    state.delayStart = now
    return false
  end
  local minutes, hours, days = since(now, state.delayStart)
  -- The routine writes the current value back into each byte as it walks the
  -- stamp, so the next check measures from here.
  state.delayStart = now
  local elapsed = minutes
  if days ~= 0 or hours ~= 0 then elapsed = -1 end
  if elapsed == -1 then
    state.delayMins = 0
    return true
  end
  local left = (state.delayMins or 0) - elapsed
  if left < 0 then left = 0 end
  state.delayMins = left
  return left == 0
end

-- CheckReceiveCallTimer: consume the expiry, wind the cycle counter on (capped
-- at 3) and restart the countdown at the next, shorter delay.
function Phone.checkReceiveCallTimer(save, ctx)
  if not Phone.checkReceiveCallDelay(save, ctx) then return false end
  local state = Phone.state(save)
  if (state.timeCycles or 0) < 3 then
    state.timeCycles = (state.timeCycles or 0) + 1
  end
  Phone.nextReceiveDelay(save, ctx)
  return true
end

-- ------------------------------------------------------- call descriptors

-- LoadCallerScript.  Contact 0 is not a contact: the routine swaps in the
-- WrongNumber record, whose script is one writetext and an end.
local function descriptor(id, direction, scriptField)
  id = tonumber(id) or 0
  local contact = Phone.CONTACTS[id]
  if id == 0 or not contact then
    return {
      kind = "call", contact = 0, direction = direction,
      script = "WrongNumberScript",
      scriptKey = Phone.SCRIPT_KEYS.WrongNumberScript,
      wrongNumber = true,
    }
  end
  local label = contact[scriptField]
  return {
    kind = "call",
    contact = id,
    direction = direction,
    class = contact.class,
    member = contact.member,
    number = contact.number,
    map = contact.map,
    script = label,
    scriptKey = contact[scriptField .. "Key"] or Phone.scriptKey(label),
  }
end

Phone.loadCallerScript = descriptor

-- ------------------------------------------------------- outgoing
--
-- MakePhoneCallFromPokegear.  `kind` says which of the three things the cart
-- does happened:
--   "call"      ring the contact and run their callee script
--   "justtalk"  PhoneScript_JustTalkToThem -- they are on this very map
--   "outofarea" PhoneOutOfAreaScript -- link mode, no signal, or wrong hour
--
-- Note what is NOT checked: whether the contact is in your phone book at all.
-- The Pokegear only ever offers listed contacts, so the cart never asks.
function Phone.call(save, id, ctx)
  ctx = ctx or {}
  local outOfArea = {
    kind = "outofarea",
    contact = tonumber(id) or 0,
    direction = "outgoing",
    script = "PhoneOutOfAreaScript",
    scriptKey = Phone.SCRIPT_KEYS.PhoneOutOfAreaScript,
  }
  if ctx.linkMode then return outOfArea end
  if not Phone.mapHasService(ctx) then return outOfArea end
  local contact = Phone.CONTACTS[tonumber(id) or -1]
  if not contact then return outOfArea end
  -- CheckPhoneContactTimeOfDay masks the row's SCRIPT1_TIME with ANYTIME and
  -- then with the current time bit.
  if not timeMatches(contact.calleeTime, Phone.timeOfDay(ctx)) then
    return outOfArea
  end
  if Phone.onSameMap(contact, ctx) then
    return {
      kind = "justtalk",
      contact = tonumber(id),
      direction = "outgoing",
      script = "PhoneScript_JustTalkToThem",
      scriptKey = Phone.SCRIPT_KEYS.PhoneScript_JustTalkToThem,
    }
  end
  return descriptor(id, "outgoing", "callee")
end

-- ------------------------------------------------------- incoming

-- GetAvailableCallers.  Walks all ten slots of wPhoneList and keeps the
-- contacts whose SCRIPT2_TIME covers the current time of day and who are not
-- standing on the map you are standing on.
function Phone.availableCallers(save, ctx)
  local state = Phone.state(save)
  local checked = Phone.timeOfDay(ctx)
  local out = {}
  for slot = 1, Phone.CONTACT_LIST_SIZE do
    local id = state.list[slot]
    if id ~= 0 then
      local contact = Phone.CONTACTS[id]
      if contact and timeMatches(contact.callerTime, checked)
          and not Phone.onSameMap(contact, ctx) then
        out[#out + 1] = id
      end
    end
  end
  return out
end

-- ChooseRandomCaller.  One Random call, whose byte is nibble-swapped and
-- masked to 0..31, then reduced modulo the number of available callers by
-- SimpleDivide (which returns the remainder in a).  The swap-and-mask is why a
-- book with more than a few contacts still samples evenly enough.
function Phone.chooseRandomCaller(callers, rng)
  if not callers or #callers == 0 then return nil end
  rng = rng or rngOf(nil)
  local roll = rng() % 256
  local swapped = (roll % 16) * 16 + math.floor(roll / 16)
  local index = (swapped % 32) % #callers
  return callers[index + 1]
end

-- CheckPhoneCall, the whole gate, in the cart's order.  The order matters: the
-- timer check has side effects (it restarts the countdown and winds the cycle
-- counter), so it must run before the coin flip and not after it.
--
--   1. CheckStandingOnEntrance -- a door, staircase or cave tile never rings
--   2. CheckReceiveCallTimer   -- the countdown has to have run out
--   3. a 50% coin flip
--   4. GetMapPhoneService      -- the map has to have a signal
--   5. someone has to be available at this hour and off this map
function Phone.tryRandomCall(save, ctx)
  ctx = ctx or {}
  if ctx.standingOnEntrance then return nil end
  if not Phone.checkReceiveCallTimer(save, ctx) then return nil end
  local rng = rngOf(ctx)
  -- `call Random / ld b, a / and %01111111 / cp b / jr nz`: equal only when
  -- the top bit was already clear, so this passes half the time.
  if (rng() % 256) >= 0x80 then return nil end
  if not Phone.mapHasService(ctx) then return nil end
  local who = Phone.chooseRandomCaller(Phone.availableCallers(save, ctx), rng)
  if not who then return nil end
  return descriptor(who, "incoming", "caller")
end

-- The cart's own name for it, for a reader coming from phone.asm.
Phone.checkPhoneCall = Phone.tryRandomCall

-- ------------------------------------------------------- special calls

-- Script_specialphonecall: the id goes into wSpecialPhoneCallID and sits there
-- until a called script clears it.  `SPECIALCALL_NONE` (0) is the clear.
function Phone.queueSpecialCall(save, id)
  local state = Phone.state(save)
  state.specialCall = tonumber(id) or 0
  return state.specialCall
end

function Phone.clearSpecialCall(save)
  return Phone.queueSpecialCall(save, Phone.SPECIALCALL_NONE)
end

-- Script_checkphonecall: false when nothing is queued.
function Phone.hasSpecialCall(save)
  return Phone.state(save).specialCall ~= 0
end

-- readvar VAR_SPECIALPHONECALL, which is how every special caller script works
-- out which of its branches to take (ElmPhoneCallerScript's ifequal chain).
function Phone.specialCallVar(save)
  return Phone.state(save).specialCall or 0
end

-- CheckSpecialPhoneCall, run from CountStep before the step is counted.  The
-- queued row's script REPLACES the contact's own SCRIPT2 for this call, which
-- is how one Elm contact serves five different scripted calls.
--
-- `delay` is the `pause 30` its little wrapper script runs before
-- Script_ReceivePhoneCall; a random call has no such pause.
function Phone.checkSpecialCall(save, ctx)
  local state = Phone.state(save)
  local queued = state.specialCall or 0
  if queued == 0 then return nil end
  local entry = Phone.SPECIAL_CALLS[queued]
  if not entry then return nil end
  if entry.condition == "outside" and not Phone.isOutside(ctx) then
    return nil
  end
  local call = descriptor(entry.contact, "incoming", "caller")
  call.special = queued
  call.specialName = entry.name
  call.script = entry.script
  call.scriptKey = entry.scriptKey or Phone.scriptKey(entry.script)
  call.delay = 30
  return call
end

-- ------------------------------------------------------- rematches

-- ../pokegold/constants/event_flags.asm:268
function Phone.rematchEvent(id)
  local contact = Phone.CONTACTS[id or -1]
  return contact and contact.rematchEvent or nil
end

-- ../pokecrystal/constants/engine_flags.asm:125
function Phone.rematchEngineFlag(id)
  local contact = Phone.CONTACTS[id or -1]
  return contact and contact.rematchEngineFlag or nil
end

function Phone.setRematchReady(events, id, value, engineFlags)
  local flag = Phone.rematchEvent(id)
  if flag and events then
    events:set(flag, value ~= false)
    return true
  end
  local engine = Phone.rematchEngineFlag(id)
  if engine and engineFlags then
    engineFlags[engine] = (value ~= false) or nil
    return true
  end
  return false
end

function Phone.isReadyForRematch(events, id, engineFlags)
  local flag = Phone.rematchEvent(id)
  if flag and events then return events:get(flag) and true or false end
  local engine = Phone.rematchEngineFlag(id)
  if engine and engineFlags then return engineFlags[engine] and true or false end
  return false
end

-- ------------------------------------------------------- ending a call

-- engine/phone/phone.asm:431
function Phone.endCall(save, _, ctx)
  Phone.initReceiveDelay(save, ctx)
  return true
end

return Phone
