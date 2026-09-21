#!/usr/bin/env luajit

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

local function eq(a, b, msg)
  check(a == b, string.format("%s (%s == %s)", msg, tostring(a), tostring(b)))
end

local Schema = require("src.core.game3.save_schema_firered")

local session = Schema.newGame({ rngSeed = 0x1234 })
session.store = { flags = {}, vars = {} }
package.loaded["src.core.game3.runtime"] = {
  getSession = function() return session end,
  isActive = function() return true end,
}

local MysteryGift = require("src.core.game3.mystery_gift")
local Natives = require("src.core.game3.scripting.natives")
local Gift = require("src.core.game3.scripting.natives_gift")
local Bag = require("src.core.game3.bag")

-- pokefirered/data/specials.inc:395 ValidateSavedWonderCard
local SPECIAL_VALIDATE = Gift.SPECIAL_IDS.ValidateSavedWonderCard
-- pokefirered/include/constants/flags.h:704
local FLAG_RECEIVED_MYSTIC_TICKET = 0x2A8
-- pokefirered/include/constants/flags.h:1408
local FLAG_ENABLE_SHIP_NAVEL_ROCK = 0x84A

local function builtin(key)
  for _, entry in ipairs(MysteryGift.builtins()) do
    if entry.key == key then return entry end
  end
  return nil
end

local function newCtx()
  return { specialVars = {} }
end

local quiet = { log = function() end }

print("[test] 1. The deliveryman shows only for a valid saved card")
do
  MysteryGift.clear(session)
  local yield, value, known = Natives.special(newCtx(), SPECIAL_VALIDATE, quiet)
  check(known, "ValidateSavedWonderCard is bound")
  check(not yield, "it does not yield")
  eq(value, 0, "no saved card hides the deliveryman")

  local mystic = builtin("mystic_ticket")
  check(mystic ~= nil, "the built-in set carries the MYSTIC TICKET card")
  check(MysteryGift.receiveCard(session, mystic.card), "the card saves")
  local _, value2 = Natives.special(newCtx(), SPECIAL_VALIDATE, quiet)
  eq(value2, 1, "a saved card clears FLAG_HIDE_MG_DELIVERYMEN")
end

print("[test] 2. The once-only flag per card")
do
  session.bag = Bag.new()
  MysteryGift.clear(session)
  session.store.flags = {}
  local mystic = builtin("mystic_ticket")
  MysteryGift.receiveCard(session, mystic.card)
  check(MysteryGift.isGiftNotReceived(session), "the gift starts uncollected")

  local first = MysteryGift.deliverGift(session)
  eq(first, MysteryGift.DELIVER_GIVEN, "the first visit hands the ticket over")
  eq(Bag.get(session.bag, MysteryGift.ITEM_MYSTIC_TICKET), 1, "one ticket in the bag")
  check(MysteryGift.getFlag(session, FLAG_ENABLE_SHIP_NAVEL_ROCK),
    "FLAG_ENABLE_SHIP_NAVEL_ROCK is set")
  check(MysteryGift.getFlag(session, FLAG_RECEIVED_MYSTIC_TICKET),
    "FLAG_RECEIVED_MYSTIC_TICKET is set")
  check(not MysteryGift.isGiftNotReceived(session), "the card reads as collected")

  local second = MysteryGift.deliverGift(session)
  eq(second, MysteryGift.DELIVER_ALREADY, "the second visit hands over nothing")
  eq(Bag.get(session.bag, MysteryGift.ITEM_MYSTIC_TICKET), 1, "still one ticket in the bag")
end

print("[test] 3. The received-gift flag alone closes a card")
do
  session.bag = Bag.new()
  MysteryGift.clear(session)
  session.store.flags = {}
  local cave = builtin("altering_cave")
  MysteryGift.receiveCard(session, cave.card)
  local flagId = MysteryGift.getCardFlagId(session)
  local giftFlag = MysteryGift.receivedGiftFlag(flagId)
  check(giftFlag ~= nil, "the card maps into sReceivedGiftFlags")
  eq(MysteryGift.deliverGift(session), MysteryGift.DELIVER_GIVEN, "the first visit runs it")
  check(MysteryGift.getFlag(session, giftFlag), "and sets its sReceivedGiftFlags entry")
  eq(MysteryGift.deliverGift(session), MysteryGift.DELIVER_ALREADY, "a second visit does not")
end

print("[test] 4. trywondercardscript is the deliveryman's whole script")
do
  session.bag = Bag.new()
  MysteryGift.clear(session)
  session.store.flags = {}

  local shown = nil
  local adapters = {
    log = function() end,
    playerName = "RED",
    openMessageAsync = function(text, done)
      shown = text
      done()
    end,
  }

  local ctx = newCtx()
  check(Gift.runWonderCardScript(ctx, adapters) == false,
    "with no saved card the script falls straight through")
  check(shown == nil, "and opens no message box")

  local mystic = builtin("mystic_ticket")
  MysteryGift.receiveCard(session, mystic.card)
  ctx = newCtx()
  Gift.runWonderCardScript(ctx, adapters)
  eq(Gift.lastDelivery, MysteryGift.DELIVER_GIVEN, "the deliveryman hands the gift over")
  check(Bag.has(session.bag, MysteryGift.ITEM_MYSTIC_TICKET, 1), "the ticket is in the bag")
  check(type(shown) == "table" or type(shown) == "string", "a message box was opened")

  shown = nil
  ctx = newCtx()
  Gift.runWonderCardScript(ctx, adapters)
  eq(Gift.lastDelivery, MysteryGift.DELIVER_ALREADY, "a second talk gives nothing")
  eq(Bag.get(session.bag, MysteryGift.ITEM_MYSTIC_TICKET), 1, "and no second ticket")
end

print("[test] 5. The deliveryman's four outcomes")
do
  local already = Gift.deliveryText(session, MysteryGift.DELIVER_ALREADY)
  check(tostring(already):find("MYSTERY"), "the already-collected line thanks the player")
  local noRoom = Gift.deliveryText(session, MysteryGift.DELIVER_NO_ROOM)
  check(tostring(noRoom):find("BAG"), "the no-room line names the BAG")
  local full = Gift.deliveryText(session, MysteryGift.DELIVER_PARTY_FULL)
  check(tostring(full):find("party"), "the party-full line names the party")
  local given = Gift.deliveryText(session, MysteryGift.DELIVER_GIVEN)
  check(tostring(given):find("ticket"), "the handover line reads the card's own body text")
  -- pokefirered/data/mystery_event_msg.s:303 sText_MysticTicket2
  local pages = {}
  for page in (tostring(given) .. "\\p"):gmatch("(.-)\\p") do pages[#pages + 1] = page end
  eq(#pages, 2, "four body lines become two message pages")
  for i, page in ipairs(pages) do
    local lines = 1
    for _ in page:gmatch("\n") do lines = lines + 1 end
    eq(lines, 2, "page " .. i .. " is two lines high")
  end
end

print("[test] 6. The 0xCF opcode runs the card script through the VM")
do
  local Vm = require("src.core.game3.scripting.vm")
  local Flags = require("src.core.game3.scripting.flags")
  local FALL_THROUGH = 0x300

  local function runMan()
    session.bag = Bag.new()
    session.store = Flags.newStore()
    local shown = 0
    local vm = Vm.new({
      store = session.store,
      scripts = {
        -- pokefirered/data/scripts/cable_club.inc:15 CableClub_EventScript_MysteryGiftMan
        man = {
          { op = "trywondercardscript", opcode = 207 },
          { op = "setflag", [1] = FALL_THROUGH, flag = FALL_THROUGH, opcode = 41 },
          { op = "end", opcode = 3 },
        },
      },
      adapters = {
        log = function() end,
        playerName = "RED",
        openMessageAsync = function(_, done) shown = shown + 1 done() end,
      },
    })
    vm:start("man")
    for _ = 1, 60 do
      if not vm:isRunning() then break end
      vm:tick()
    end
    return vm, shown
  end

  MysteryGift.clear(session)
  local vm1, shown1 = runMan()
  eq(shown1, 0, "no saved card opens no delivery message")
  check(Flags.getFlag(session.store, vm1.ctx, FALL_THROUGH),
    "and the script falls through to the rest of the deliveryman script")

  MysteryGift.clear(session)
  local mystic = builtin("mystic_ticket")
  MysteryGift.receiveCard(session, mystic.card)
  local vm2, shown2 = runMan()
  eq(shown2, 1, "a saved card opens the delivery message")
  eq(Bag.get(session.bag, MysteryGift.ITEM_MYSTIC_TICKET), 1, "the opcode put the ticket in the bag")
  check(MysteryGift.getFlag(session, FLAG_ENABLE_SHIP_NAVEL_ROCK),
    "and set FLAG_ENABLE_SHIP_NAVEL_ROCK")
  -- pokefirered/src/scrcmd.c:280 ScriptJump
  check(not Flags.getFlag(session.store, vm2.ctx, FALL_THROUGH),
    "the card script jumped away instead of falling through")
  check(not vm2:isRunning(), "and the deliveryman script finished")
end

if failed == 0 then
  print("PASS game3_gift_delivery")
else
  print("FAIL game3_gift_delivery failures=" .. failed)
  os.exit(1)
end
