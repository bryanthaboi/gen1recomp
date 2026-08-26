-- Prize money for beating a trainer.
--
-- Two routines, in two files, and both halves matter:
--
--   ComputeTrainerReward (engine/battle/read_trainer_party.asm) runs when the
--     party is READ, not when it is beaten: wBattleReward = the class's
--     TRNATTR_BASE_REWARD times wCurPartyLevel, and wCurPartyLevel at that
--     point is whatever the LAST row of data/trainers/parties.asm left there.
--     So Falkner pays for his level 9 Pidgeotto and not for the level 7 Pidgey
--     that came out first, whichever of them faints last.
--   WinTrainerBattle (engine/battle/core.asm) is the trainer-defeated arm, and
--     it hands out wBattleReward FOUR TIMES -- `ld c, 4`, one add per pass --
--     before doubling the figure twice for the text.  That factor of four is
--     the difference between Falkner's ¥900 and a ¥225 that would look
--     plausible and be wrong.
--
-- The split is the other half of Bank of Mom: those four quarters are dealt
-- between wMoney and wMomsMoney by wMomSavingMoney, so "save some money for
-- me" is a standing 25% deduction on every trainer you beat, not a thing that
-- only happens when you walk into the house.
--
-- love-free and save-shaped: takes the Gold save table
-- (src/core/gen2/Save.lua) and writes the two accounts on it, so the battle
-- engine, the world and the tests all reach the same routine.

local Strings = require("src.core.Strings")

local Prize = {}

-- constants/misc_constants.asm.  The same cap Save.MAX_MONEY carries; spelled
-- out here so this module stays usable against a bare save-shaped table.
Prize.MAX_MONEY = 999999

-- .DoubleReward saturates: `sla [hl] / rl [hl] / rl [hl] / ret nc` and then
-- $ff into all three bytes, so the shift tops out at 24 bits rather than
-- wrapping.  wBattleReward is three bytes, which is where the number comes
-- from -- it is NOT the money cap.
local REWARD_CAP = 0xffffff

-- constants/ram_constants.asm, wMomSavingMoney's low bits.  MOM_ACTIVE_F (bit
-- 7) is deliberately outside MOM_SAVING_MONEY_MASK: it says the bank
-- conversation has happened, not that anything is being skimmed.
--
-- "All" is bits 0 AND 1 together, not MOM_SAVING_ALL_MONEY_F -- that third
-- bit is inside the mask and is never written by anything, which is why
-- WinTrainerBattle compares against `(1 << SOME) | (1 << HALF)` rather than
-- against it.
local MOM_SAVING_MONEY_MASK = 7
local MOM_SAVING_SOME, MOM_SAVING_HALF = 1, 2
local MOM_SAVING_ALL = MOM_SAVING_SOME + MOM_SAVING_HALF

-- data/items/attributes.asm: HELD_AMULET_COIN is the only held effect that
-- reaches this file.  CheckAmuletCoin (engine/battle/core.asm) latches
-- wAmuletCoin when a mon holding one is SENT OUT, and nothing clears it for
-- the rest of the battle, so the coin still pays after its holder has fainted.
Prize.AMULET_COIN = "AMULET_COIN"

-- data/text/battle.asm.  Declared here and formatted at the call site so
-- Strings.source is what registers them, the same way Decorations declares
-- its own five.  No line markers: every battle message in this port is one
-- flowing string that Chrome.wrap breaks to the box, except SentSomeToMomText,
-- which keeps the cart's own `line`/`cont` breaks because it does not fit two
-- rows.
local GOT_MONEY = Strings.source("%s got %s%d for winning!")
-- data/text/battle.asm:179-185
local SENT_SOME = Strings.source("%s got %s%d\nfor winning!\vSent some to MOM!")
-- The half and all texts really are this short on the cart: they replace the
-- money line rather than following it, which is a quirk no Gold player can
-- see because BankOfMom only ever writes MOM_SAVING_SOME_MONEY_F.
local SENT_HALF = Strings.source("Sent half to MOM!")
local SENT_ALL = Strings.source("Sent all to MOM!")
-- BattleText_PlayerPickedUpPayDayMoney (data/text/battle.asm:3-8).
local PICKED_UP = Strings.source("%s picked up %s%d!")

-- charmap.asm: the currency glyph, the same one Chrome.money floats in front
-- of a six-digit field.
local YEN = "\xc2\xa5"

--------------------------------------------------------------------------
-- ComputeTrainerReward
--------------------------------------------------------------------------

-- hProduct is four bytes and wBattleReward takes the low two of them with a
-- zero on top, so the product is kept modulo 65536.  No vanilla class can
-- reach that (255 * 100 = 25500), but a mod that raises a base reward should
-- truncate the way the cart does rather than quietly pay more.
function Prize.reward(baseMoney, level)
  local base = math.floor(tonumber(baseMoney) or 0)
  local lvl = math.floor(tonumber(level) or 0)
  if base < 0 then base = 0 end
  if lvl < 0 then lvl = 0 end
  return (base * lvl) % 0x10000
end

-- The level ComputeTrainerReward would have seen: wCurPartyLevel after
-- ReadTrainerParty's loop, which is the last row it built.
function Prize.rewardLevel(party)
  local last = party and party[#party]
  return (last and last.level) or 0
end

local function doubleReward(value)
  local doubled = (value or 0) * 2
  if doubled > REWARD_CAP then return REWARD_CAP end
  return doubled
end

--------------------------------------------------------------------------
-- The accounts
--------------------------------------------------------------------------

local function playerMoney(save)
  local player = save and save.player
  return (player and player.money) or 0
end

local function momMoney(save)
  local mom = save and save.mom
  return (mom and mom.savedMoney) or 0
end

-- AddBattleMoneyToAccount: a 24-bit add followed by a compare against
-- MAX_MONEY, and the overflow arm WRITES the cap rather than refusing the
-- add.  The cart clamps; it does not wrap and it does not reject.
local function addToAccount(have, amount)
  local total = have + amount
  if total > Prize.MAX_MONEY then return Prize.MAX_MONEY end
  return total
end

local function setPlayerMoney(save, value)
  local player = save and save.player
  if player then player.money = value end
end

local function setMomMoney(save, value)
  local mom = save and save.mom
  if mom then mom.savedMoney = value end
end

-- wMomSavingMoney & MOM_SAVING_MONEY_MASK.  BankOfMom (engine/events/mom.asm)
-- only ever stores (1 << MOM_ACTIVE_F) or that plus (1 <<
-- MOM_SAVING_SOME_MONEY_F), so in Gold the masked byte is 0 or 1 and nothing
-- else -- which is why `savingMoney` is a boolean on this save rather than a
-- number.  MOM_SAVING_HALF / _ALL are kept below anyway because the split
-- loop reads them and a Crystal-shaped save would set them.
function Prize.savingMode(save)
  local mom = save and save.mom
  if not (mom and mom.active and mom.savingMoney) then return 0 end
  if type(mom.savingMoney) == "number" then
    return mom.savingMoney % (MOM_SAVING_MONEY_MASK + 1)
  end
  return MOM_SAVING_SOME
end

-- `ld b, a` then the two loops: b quarters to Mom, 4 - b to the wallet.  The
-- `cp (1 << SOME) | (1 << HALF) / inc a` is what turns the setting into a
-- count -- 3 means ALL, which is four quarters, not three.  A masked byte of
-- 4 or more is not a value anything writes, and the cart's own text lookup
-- would run off the end of .SentToMomTexts for one, so it is read as nothing
-- rather than guessed at.
local function quartersToMom(mode)
  if mode == MOM_SAVING_ALL then return 4 end
  if mode == MOM_SAVING_HALF then return 2 end
  if mode == MOM_SAVING_SOME then return 1 end
  return 0
end

Prize.QUARTERS = 4

--------------------------------------------------------------------------
-- WinTrainerBattle
--------------------------------------------------------------------------

-- opts:
--   baseMoney   the class's TRNATTR_BASE_REWARD (Trainers.lookup's baseMoney)
--   level       wCurPartyLevel, i.e. Prize.rewardLevel(the trainer's party)
--   amuletCoin  wAmuletCoin, latched by CheckAmuletCoin
--
-- Returns a record of what happened, which is what the caller turns into the
-- message: `total` is the figure the text prints (the quarter doubled twice),
-- `toMom` is how many of the four quarters Mom took, and `mode` is the
-- wMomSavingMoney setting the text is chosen by.
function Prize.award(save, opts)
  opts = opts or {}
  local quarter = Prize.reward(opts.baseMoney, opts.level)
  -- `ld a, [wAmuletCoin] / and a / call nz, .DoubleReward` -- before the
  -- split, so Mom's cut doubles with everything else.
  if opts.amuletCoin then quarter = doubleReward(quarter) end

  -- .CheckMaxedOutMomMoney: carry means wMomsMoney is BELOW the cap.  With no
  -- carry the whole reward goes to the wallet and the text is .KeepItAll,
  -- however the savings setting is left -- Mom stops skimming once she is
  -- full rather than throwing the quarter away.
  local mode = 0
  if momMoney(save) < Prize.MAX_MONEY then mode = Prize.savingMode(save) end
  local toMom = quartersToMom(mode)

  local wallet, saved = playerMoney(save), momMoney(save)
  for _ = 1, toMom do saved = addToAccount(saved, quarter) end
  for _ = 1, Prize.QUARTERS - toMom do wallet = addToAccount(wallet, quarter) end
  setPlayerMoney(save, wallet)
  setMomMoney(save, saved)

  return {
    quarter = quarter,
    total = doubleReward(doubleReward(quarter)),
    toMom = toMom,
    mode = mode,
    wallet = wallet,
    saved = saved,
  }
end

-- The line StdBattleTextbox prints, chosen by .SentToMomTexts / .KeepItAll.
function Prize.message(award, playerName)
  local name = playerName or "PLAYER"
  local total = (award and award.total) or 0
  local mode = (award and award.mode) or 0
  if mode == MOM_SAVING_ALL then return Strings(SENT_ALL) end
  if mode == MOM_SAVING_HALF then return Strings(SENT_HALF) end
  if mode == MOM_SAVING_SOME then
    return Strings(SENT_SOME, name, YEN, total)
  end
  return Strings(GOT_MONEY, name, YEN, total)
end

-- CheckPayDay (engine/battle/core.asm:8014-8042): the Amulet Coin doubles the
-- accumulated total once, and the wallet is written directly, no Mom split.
function Prize.payDay(save, amount, amuletCoin)
  if not (save and save.player) or (amount or 0) <= 0 then return nil end
  if amuletCoin then amount = amount * 2 end
  setPlayerMoney(save, addToAccount(playerMoney(save), amount))
  return amount
end

function Prize.payDayMessage(amount, playerName)
  return Strings(PICKED_UP, playerName or "PLAYER", YEN, amount or 0)
end

return Prize
