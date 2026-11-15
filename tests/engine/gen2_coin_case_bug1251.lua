-- #1251: the Game Corner's `CheckCoinsAndCoinCase` transcription must ask
-- the bag about the real COIN_CASE item id, not SILVER_WING.
-- constants/item_constants.asm:62 (COIN_CASE = $36); SILVER_WING is $47.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")

local Vm = require("src.script.gen2.Vm")
local Specials = require("src.script.gen2.Specials")
local Events = require("src.world.gen2.Events")

local COIN_CASE = 0x36
local SILVER_WING = 0x47

-- 1) the id the handler actually queries the bag with
local seenId
local vm = Vm.new({ generation = 2 }, {}, Events.new(), {
  specials = {
    coins = function() return 100 end,
    hasItem = function(id) seenId = id return true end,
    gameCornerGame = function(_, done) done() end,
  },
})
vm.showTextFn = function() end
vm.co = coroutine.create(function() Specials.HANDLERS.SlotMachine(vm) end)
coroutine.resume(vm.co)
T.eq(seenId, COIN_CASE,
  "SlotMachine's CheckItem call carries the real COIN_CASE id ($36)")
T.check(seenId ~= SILVER_WING,
  "and specifically not SILVER_WING ($47), the pre-fix value")

-- 2) a bag holding ONLY the real coin case (not the silver wing) must be
-- enough to open both machines: this is what would still fail if the id
-- above were merely logged and not actually used to gate the machine.
local bag = { [COIN_CASE] = true }
local slotsOpened, flipOpened
local vm2 = Vm.new({ generation = 2 }, {}, Events.new(), {
  specials = {
    coins = function() return 50 end,
    hasItem = function(id) return bag[id] == true end,
    gameCornerGame = function(kind, done) slotsOpened = kind done() end,
  },
})
vm2.showTextFn = function() end
vm2.co = coroutine.create(function() Specials.HANDLERS.SlotMachine(vm2) end)
coroutine.resume(vm2.co)
T.eq(slotsOpened, "slots",
  "a bag with the real COIN CASE and coins opens the slot machine")

local vm3 = Vm.new({ generation = 2 }, {}, Events.new(), {
  specials = {
    coins = function() return 50 end,
    hasItem = function(id) return bag[id] == true end,
    gameCornerGame = function(kind, done) flipOpened = kind done() end,
  },
})
vm3.showTextFn = function() end
vm3.co = coroutine.create(function() Specials.HANDLERS.CardFlip(vm3) end)
coroutine.resume(vm3.co)
T.eq(flipOpened, "cardflip",
  "and the same bag opens card flip too")

-- 3) the mirror case: SILVER_WING in the bag, no coin case, must still
-- refuse with _NoCoinCaseText (this is the exact symptom in #1251, and it
-- is the yield the coroutine parks on, not a call, so opening never runs
-- behind it).
local wrongBag = { [SILVER_WING] = true }
local opened = false
local vm4 = Vm.new({ generation = 2 }, {}, Events.new(), {
  specials = {
    coins = function() return 50 end,
    hasItem = function(id) return wrongBag[id] == true end,
    gameCornerGame = function() opened = true end,
    data = function() return { text = require("tests.fixtures.gen2_rom_text").text() } end,
  },
})
vm4.showTextFn = function() end
vm4.co = coroutine.create(function() Specials.HANDLERS.SlotMachine(vm4) end)
local _, refusal = coroutine.resume(vm4.co)
T.eq(refusal and refusal.text, "You don't have a\nCOIN CASE.{PROMPT}",
  "holding only SILVER_WING gets the real _NoCoinCaseText refusal")
T.check(not opened, "and the machine never opens behind it")

T.finish("gen2_coin_case_bug1251")
