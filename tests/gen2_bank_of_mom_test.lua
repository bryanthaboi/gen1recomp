-- Mom's savings, special BankOfMom (engine/events/mom.asm).  ROM-free:
--   luajit tests/gen2_bank_of_mom_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 bank of mom")
local check, eq = S.check, S.eq

local Vm = require("src.script.gen2.Vm")
local Events = require("src.world.gen2.Events")
local Specials = require("src.script.gen2.Specials")
local Save = require("src.core.gen2.Save")

check(Specials.STUBS.BankOfMom == nil,
  "BankOfMom is a HANDLER: the six-digit keypad it needed now exists")
check(Specials.HANDLERS.BankOfMom ~= nil,
  "and special dispatch resolves to it")

-- A minimal Gold save: just the two accounts BankOfMom reads and writes.
local function record(money, saved, active, savingMoney)
  return {
    player = { money = money or 0 },
    mom = { savedMoney = saved or 0, active = active or false,
      savingMoney = savingMoney or false },
  }
end

-- Wires H.BankOfMom's whole `hooks(vm)` surface: `money`/`setMoney` over the
-- two accounts (YOUR_MONEY 0, MOMS_MONEY 1), `bankOfMomAmount` answering off
-- a fixed queue the way a real keypad answers one amount per open, and
-- `playSfxNamed` recorded so the transaction jingle can be checked for.
local function bankVm(rec, amounts)
  local sfx = {}
  local amountIndex = 0
  local vm = Vm.new({}, {}, Events.new(), {
    specials = {
      save = function() return rec end,
      money = function(account)
        return account == 1 and rec.mom.savedMoney or rec.player.money
      end,
      setMoney = function(account, value)
        if account == 1 then rec.mom.savedMoney = value
        else rec.player.money = value end
      end,
      bankOfMomAmount = function(_kind, _saved, _held, done)
        amountIndex = amountIndex + 1
        done(amounts and amounts[amountIndex])
      end,
      playSfxNamed = function(name, fallback)
        sfx[#sfx + 1] = { name = name, fallback = fallback }
      end,
    },
  })
  vm.showTextFn = function() end
  vm.sfx = sfx
  return vm
end

-- Drives the coroutine to completion, feeding a `yesorno` off `yesAnswers` and
-- a `menu` off `menuAnswers` (both 1-based queues, consumed in the order the
-- handler asks), and collects every `text` yield along the way -- the same
-- shape tests/gen2_vm_test.lua's driveMoveDeletion/driveNameRater use, with
-- a `menu` arm added for BankOfMom's GET/SAVE/CHANGE/CANCEL screen.
local function drive(vm, yesAnswers, menuAnswers)
  local texts, menus = {}, {}
  local yi, mi = 0, 0
  local resumeArg = nil
  local ok, req = coroutine.resume(vm.co, resumeArg)
  while true do
    if not ok then error(req) end
    if req and req.kind == "text" then texts[#texts + 1] = req.text end
    if req and req.kind == "menu" then menus[#menus + 1] = req.header end
    if coroutine.status(vm.co) == "dead" then break end
    resumeArg = nil
    if req and req.kind == "yesorno" then
      yi = yi + 1
      resumeArg = yesAnswers[yi]
    elseif req and req.kind == "menu" then
      mi = mi + 1
      resumeArg = menuAnswers[mi]
    end
    ok, req = coroutine.resume(vm.co, resumeArg)
  end
  return texts, menus
end

local function run(vm, yesAnswers, menuAnswers)
  vm.co = coroutine.create(function() Specials.HANDLERS.BankOfMom(vm) end)
  return drive(vm, yesAnswers or {}, menuAnswers or {})
end

-- ---- .CheckIfBankInitialized / .InitializeBank -----------------------------
-- The very first visit skips IsThisAboutYourMoney and jumps straight to
-- "shall I save your money?"
do
  local rec = record(3000, 0, false, false)
  local vm = bankVm(rec)
  local texts = run(vm, { true })
  eq(#texts, 3, "leaving1, leaving2 (accepted), leaving3")
  check(texts[1]:find("cute", 1, true) ~= nil, "MomLeavingText1")
  check(texts[2]:find("take care", 1, true) ~= nil, "MomLeavingText2")
  check(texts[3]:find("careful", 1, true) ~= nil, "MomLeavingText3")
  check(rec.mom.active, "MOM_ACTIVE_F is set either way")
  check(rec.mom.savingMoney, "and MOM_SAVING_SOME_MONEY_F, since the answer was yes")
end

do
  local rec = record(3000, 0, false, false)
  local vm = bankVm(rec)
  local texts = run(vm, { false })
  eq(#texts, 2, "leaving1 and leaving3 only -- MomLeavingText2 is skipped")
  check(texts[2]:find("careful", 1, true) ~= nil, "still MomLeavingText3")
  check(rec.mom.active, "the bank is still marked initialized")
  check(not rec.mom.savingMoney, "but nothing is being saved")
end

-- ---- .IsThisAboutYourMoney --------------------------------------------------
do
  local rec = record(1000, 500, true, true)
  local texts = run(bankVm(rec), { false })
  eq(#texts, 2, "the room-tidy line, then the fallback close")
  check(texts[2]:find("Just do what", 1, true) ~= nil,
    "declining reads as MomJustDoWhatYouCanText -- DSTChecks does not apply "
    .. "in this port (no wStartHour offset to nudge)")
  eq(rec.player.money, 1000, "and nothing about either account moved")
  eq(rec.mom.savedMoney, 500, "")
end

-- ---- .AccessBankOfMom: CANCEL and B both fall through to the same close ----
do
  local rec = record(1000, 500, true, true)
  local texts, menus = run(bankVm(rec), { true }, { 4 })
  check(#menus == 1, "the GET/SAVE/CHANGE/CANCEL menu opened once")
  eq(menus[1].items[1], "GET", "GET is withdraw")
  eq(menus[1].items[2], "SAVE", "SAVE is deposit")
  eq(menus[1].items[3], "CHANGE", "CHANGE is the savings toggle")
  eq(menus[1].items[4], "CANCEL", "")
  check(texts[#texts]:find("Just do what", 1, true) ~= nil,
    "CANCEL falls to MomJustDoWhatYouCanText")
end

do
  local rec = record(1000, 500, true, true)
  local texts = run(bankVm(rec), { true }, { 0 })
  check(texts[#texts]:find("Just do what", 1, true) ~= nil,
    "so does B (menu answers 0, the way Script_verticalmenu's carry does)")
end

-- ---- .StoreMoney (SAVE / deposit) ------------------------------------------
do
  -- First offer is more than the wallet holds: retried in place, no state
  -- change, then a good amount goes through.
  local rec = record(1000, 500, true, true)
  local vm = bankVm(rec, { 2000, 300 })
  local texts = run(vm, { true }, { 2 })
  check(texts[4]:find("don't have", 1, true) ~= nil,
    "MomInsufficientFundsInWalletText for the first, too-big offer")
  check(texts[#texts]:find("safe", 1, true) ~= nil, "MomStoredMoneyText closes it")
  eq(rec.player.money, 700, "the wallet paid out the SECOND, valid amount")
  eq(rec.mom.savedMoney, 800, "and the savings account received it")
  eq(#vm.sfx, 1, "the transaction jingle played once")
  eq(vm.sfx[1].name, "Sfx_Transaction", "by its pokegold label")
end

-- Depositing enough to overflow Mom's account clamps it to the cap and
-- reports "no room" -- but the clamp already landed, exactly the way
-- GiveMoney commits before it reports carry (engine/events/money.asm).  The
-- wallet is never charged for a deposit that could not fully land.
do
  local rec = record(999999, 999990, true, true)
  local vm = bankVm(rec, { 20, 0 })
  local texts = run(vm, { true }, { 2 })
  check(texts[4]:find("can't save", 1, true) ~= nil, "MomNotEnoughRoomInBankText")
  eq(rec.mom.savedMoney, 999999, "clamped to MAX_MONEY regardless")
  eq(rec.player.money, 999999, "the wallet was never touched by the failed leg")
  check(texts[#texts]:find("Just do what", 1, true) ~= nil,
    "entering 0 on the retry cancels out to the same close as B")
end

-- A zero entry or a flat B (bankOfMomAmount answering nil) both read as
-- CancelDeposit -- no retry, straight to the close.
do
  local rec = record(1000, 500, true, true)
  local texts = run(bankVm(rec, { 0 }), { true }, { 2 })
  check(texts[#texts]:find("Just do what", 1, true) ~= nil, "amount 0 cancels")
  eq(rec.player.money, 1000, "untouched")
end

do
  local rec = record(1000, 500, true, true)
  local texts = run(bankVm(rec, { nil }), { true }, { 2 })
  check(texts[#texts]:find("Just do what", 1, true) ~= nil, "B (nil) cancels too")
end

-- ---- .TakeMoney (GET / withdraw) -------------------------------------------
do
  local rec = record(200, 900, true, true)
  local vm = bankVm(rec, { 1000, 400 })
  local texts = run(vm, { true }, { 1 })
  check(texts[4]:find("haven't saved", 1, true) ~= nil,
    "MomHaventSavedThatMuchText for the first offer, more than is saved")
  check(texts[#texts]:find("don't", 1, true) ~= nil
    or texts[#texts]:find("give up", 1, true) ~= nil,
    "MomTakenMoneyText closes it")
  eq(rec.player.money, 600, "the wallet received the withdrawal")
  eq(rec.mom.savedMoney, 500, "and the savings account paid it out")
  eq(vm.sfx[1].name, "Sfx_Transaction", "the same jingle as a deposit")
end

-- The mirror of the deposit overflow: too much withdrawn to fit the wallet
-- clamps the WALLET to the cap and leaves the savings account untouched.
do
  local rec = record(999990, 999999, true, true)
  local vm = bankVm(rec, { 20 })
  local texts = run(vm, { true }, { 1 })
  check(texts[4]:find("can't take", 1, true) ~= nil, "MomNotEnoughRoomInWalletText")
  eq(rec.player.money, 999999, "the wallet was clamped to MAX_MONEY")
  eq(rec.mom.savedMoney, 999999, "and Mom's account never paid out the failed leg")
end

-- ---- .StopOrStartSavingMoney (CHANGE) --------------------------------------
do
  local rec = record(1000, 500, true, false)
  local texts = run(bankVm(rec), { true, true }, { 3 })
  check(texts[#texts]:find("Trust me", 1, true) ~= nil, "MomStartSavingMoneyText")
  check(rec.mom.savingMoney, "and MOM_SAVING_SOME_MONEY_F is set")
end

do
  local rec = record(1000, 500, true, true)
  local texts = run(bankVm(rec), { true, false }, { 3 })
  check(texts[#texts]:find("Just do what", 1, true) ~= nil,
    "declining still closes on MomJustDoWhatYouCanText, with no line of its own")
  check(not rec.mom.savingMoney, "but the flag comes off")
  check(rec.mom.active, "MOM_ACTIVE_F stays set -- the bank itself is not undone")
end

-- ---- Save.lua: the fields BankOfMom reads and writes -----------------------
do
  local fresh = Save.newGame({})
  eq(fresh.mom.active, false, "a new save has never talked to the bank")
  eq(fresh.mom.savingMoney, false, "and nothing is being saved yet")
  eq(fresh.mom.savedMoney, 0, "wMomsMoney starts empty")

  -- An older save's `mom` table predates `active`/`savingMoney` entirely.
  local old = { mom = { name = "MOM" } }
  Save.normalize(old)
  eq(old.mom.active, false, "normalize fills in the unset bank state")
  eq(old.mom.savingMoney, false, "")
  eq(old.mom.savedMoney, 0, "and the balance, clamped the way player.money is")

  local over = { mom = { savedMoney = 5000000 } }
  Save.normalize(over)
  eq(over.mom.savedMoney, Save.MAX_MONEY, "an out-of-range balance is clamped, not trusted")
end

-- ---- World:whiteOut -- HalveMoney (engine/events/whiteout.asm) ------------
do
  local World = require("src.world.gen2.World")
  local healed, warped = false, false
  local fakeSelf = setmetatable({
    game = { save = { player = { money = 5001 } } },
    showText = function(_self, _text, onDone) onDone() end,
    healParty = function() healed = true end,
    warpToSpawn = function(self)
      warped = true
      self.fade, self.fadeHold = nil, nil
    end,
  }, { __index = World })
  World.whiteOut(fakeSelf)
  eq(fakeSelf.game.save.player.money, 2500, "halved and floored")
  check(healed, "HealParty still runs")
  check(warped, "and WarpToSpawnPoint still runs")
  -- back in is a fade -- engine/events/whiteout.asm:19-20
  eq(fakeSelf.fade, "white", "and the warp brings a FadeInFromWhite with it")
  eq(fakeSelf.mapSetup and fakeSelf.mapSetup.phase, "in",
    "armed AFTER the load, so the load cannot clear it")
  eq(fakeSelf.fadeHold, World.WARP_LOAD_WHITE_FRAMES,
    "holding the LCD-off window first")
end

S.finish()
