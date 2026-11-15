-- Prize money for beating a trainer, plus what Mom does with her cut.
-- ROM-free:
--   luajit tests/gen2_prize_test.lua
--
-- The numbers below are traceable to pokegold: Falkner's ¥900 is
-- TrainerClassAttributes' 25 times his level 9 Pidgeotto times the four adds
-- in WinTrainerBattle, and the Mom item table is data/items/mom_phone.asm
-- verbatim.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 prize money")
local check, eq = S.check, S.eq

local Prize = require("src.battle.gen2.Prize")
local Battle = require("src.battle.gen2.Battle")
local MomShopping = require("src.core.gen2.MomShopping")
local Decorations = require("src.core.gen2.Decorations")
local Events = require("src.world.gen2.Events")
local Save = require("src.core.gen2.Save")
local Trainers = require("src.world.gen2.Trainers")

-- --------------------------------------------------------------- fixtures

-- A save with nothing on it but the two money accounts the payout writes.
local function record(money, saved, active, savingMoney)
  return {
    player = { name = "GOLD", money = money or 0 },
    mom = { savedMoney = saved or 0, active = active or false,
      savingMoney = savingMoney or false },
  }
end

-- ------------------------------------------------- ComputeTrainerReward

-- engine/battle/read_trainer_party.asm: base reward times wCurPartyLevel, and
-- wCurPartyLevel is whatever the LAST party row left behind.
eq(Prize.reward(25, 9), 225, "Falkner's quarter is 25 x 9")
eq(Prize.reward(4, 4), 16, "a YOUNGSTER's is 4 x 4")
eq(Prize.reward(nil, 9), 0, "a class with no base reward pays nothing")
eq(Prize.reward(25, nil), 0, "and neither does a party with no level")
-- hProduct + 2 / + 3 with a zero on top: the product is kept modulo 65536.
eq(Prize.reward(255, 300), (255 * 300) % 0x10000,
  "the product is truncated to wBattleReward's low two bytes")

eq(Prize.rewardLevel({ { level = 7 }, { level = 9 } }), 9,
  "the level is the LAST roster row, not the highest")
eq(Prize.rewardLevel({ { level = 40 }, { level = 3 } }), 3,
  "even when the last row is the weakest")
eq(Prize.rewardLevel({}), 0, "and an empty party has none")

-- ---------------------------------------------------- the four quarters

-- WinTrainerBattle's `ld c, 4`: wBattleReward is added FOUR times, and only
-- then doubled twice for the text.  Falkner really does pay ¥900.
local falkner = record(0)
local award = Prize.award(falkner, { baseMoney = 25, level = 9 })
eq(award.quarter, 225, "one quarter of Falkner's prize")
eq(award.total, 900, "and the figure the text prints")
eq(falkner.player.money, 900, "all four quarters land in the wallet")
eq(award.toMom, 0, "with Mom taking none of them")

-- Mom is not saving yet: `active` alone is the bank conversation having
-- happened, and MOM_SAVING_SOME_MONEY_F is a separate bit.
local idle = record(0, 0, true, false)
Prize.award(idle, { baseMoney = 25, level = 9 })
eq(idle.player.money, 900, "an active-but-not-saving Mom takes nothing")
eq(idle.mom.savedMoney, 0, "and her account does not move")

-- The standing 25%: one of the four adds goes to wMomsMoney.
local saving = record(0, 0, true, true)
local skimmed = Prize.award(saving, { baseMoney = 25, level = 9 })
eq(skimmed.toMom, 1, "MOM_SAVING_SOME_MONEY_F takes one quarter")
eq(saving.mom.savedMoney, 225, "which is a quarter of the prize")
eq(saving.player.money, 675, "and the wallet keeps the other three")
eq(skimmed.total, 900, "while the text still names the whole figure")

-- .CheckMaxedOutMomMoney: with her account at the cap the carry is clear, b
-- is 0 and the KeepItAll text is chosen -- she stops skimming rather than
-- throwing the quarter away.
local maxed = record(0, Prize.MAX_MONEY, true, true)
local kept = Prize.award(maxed, { baseMoney = 25, level = 9 })
eq(kept.toMom, 0, "a maxed-out Mom takes nothing")
eq(kept.mode, 0, "and the text falls back to KeepItAll")
eq(maxed.player.money, 900, "so the whole prize reaches the wallet")
eq(maxed.mom.savedMoney, Prize.MAX_MONEY, "and her account is untouched")

-- AddBattleMoneyToAccount clamps at MAX_MONEY rather than wrapping.
local rich = record(Prize.MAX_MONEY - 100)
Prize.award(rich, { baseMoney = 25, level = 9 })
eq(rich.player.money, Prize.MAX_MONEY, "the wallet clamps at the cap")
local richMom = record(0, Prize.MAX_MONEY - 100, true, true)
Prize.award(richMom, { baseMoney = 100, level = 100 })
eq(richMom.mom.savedMoney, Prize.MAX_MONEY, "and so does Mom's account")

-- The Amulet Coin doubles wBattleReward BEFORE the split, so Mom's cut
-- doubles with everything else.
local coin = record(0, 0, true, true)
local doubled = Prize.award(coin, { baseMoney = 25, level = 9,
  amuletCoin = true })
eq(doubled.total, 1800, "an AMULET COIN doubles the prize")
eq(coin.mom.savedMoney, 450, "including the quarter Mom takes")
eq(coin.player.money, 1350, "and the three the wallet keeps")

-- The half and all settings are Crystal's -- BankOfMom never writes them in
-- Gold -- but WinTrainerBattle's loop reads them, and 3 means FOUR quarters
-- (the `inc a`), not three.
local half = record(0, 0, true, 2)
eq(Prize.award(half, { baseMoney = 25, level = 9 }).toMom, 2,
  "MOM_SAVING_HALF_MONEY_F takes two quarters")
eq(half.mom.savedMoney, 450, "which really is half")
local all = record(0, 0, true, 3)
eq(Prize.award(all, { baseMoney = 25, level = 9 }).toMom, 4,
  "both bits together take all four")
eq(all.player.money, 0, "so the wallet gets nothing")
eq(all.mom.savedMoney, 900, "and Mom banks the lot")

-- data/text/battle.asm.  The half and all lines really do replace the money
-- line rather than following it.
local TEXT = { text = require("tests.fixture_data.gen2_rom_text_s7_b").text() }
local plain = Prize.message(TEXT, { total = 900, mode = 0 }, "GOLD")
eq(plain, "GOLD got \xc2\xa5900\nfor winning!", "GotMoneyForWinningText from the cache")
check(plain:find("MOM", 1, true) == nil, "and does not mention MOM")
local some = Prize.message(TEXT, { total = 900, mode = 1 }, "GOLD")
eq(some, "GOLD got \xc2\xa5900\nfor winning!\vSent some to MOM!",
  "SentSomeToMomText keeps the figure and adds the line")
eq(Prize.message(TEXT, { total = 900, mode = 2 }, "GOLD"), "Sent half to MOM!",
  "SentHalfToMomText is the whole text")
eq(Prize.message(TEXT, { total = 900, mode = 3 }, "GOLD"), "Sent all to MOM!",
  "and so is SentAllToMomText")
eq(Prize.payDayMessage(TEXT, 240, "GOLD"), "GOLD picked up\n\xc2\xa5240!",
  "BattleText_PlayerPickedUpPayDayMoney from the cache")
check(not pcall(Prize.message, { text = {} }, { total = 900, mode = 0 }, "GOLD"),
  "a cache without GotMoneyForWinningText is an error")

-- ------------------------------------------------- reached from a battle

-- The whole point of the file: a real Battle, beaten, pays the save.  These
-- fixtures are the shapes Trainers.party and Mon.new produce, cut down to
-- what the faint path reads.
local DATA = {
  pokemon = {
    RATTATA = { id = "RATTATA", name = "RATTATA", index = 19, baseExp = 57,
      growthRate = "MEDIUM_FAST", stats = { hp = 30, attack = 56,
        defense = 35, speed = 72, specialAttack = 25, specialDefense = 35 },
      types = { "NORMAL" } },
    PIDGEY = { id = "PIDGEY", name = "PIDGEY", index = 15, baseExp = 55,
      growthRate = "MEDIUM_SLOW", stats = { hp = 40, attack = 45,
        defense = 40, speed = 56, specialAttack = 35, specialDefense = 35 },
      types = { "NORMAL", "FLYING" } },
  },
  moves = {},
  text = require("tests.fixture_data.gen2_rom_text_s7_a").text(TEXT.text),
}

local function mon(species, level, hp, item)
  return { species = species, name = species, nickname = species,
    level = level, hp = hp, maxHp = 30, item = item,
    stats = { hp = 30, attack = 10, defense = 10, speed = 10,
      specialAttack = 10, specialDefense = 10 },
    moves = {}, experience = 0, statExp = {}, dvs = {} }
end

local function beat(save, opts)
  opts = opts or {}
  local enemy = mon("PIDGEY", 7, 1)
  local last = mon("PIDGEY", 9, 0)
  local battle = Battle.new({
    data = DATA,
    party = { mon("RATTATA", 10, 20, opts.playerItem) },
    save = save,
    trainer = { name = "FALKNER", className = "LEADER",
      baseMoney = 25, party = { enemy, last } },
  })
  -- The last mon standing faints, which is the arm WinTrainerBattle sits in.
  battle.enemy = last
  battle.enemyIndex = 2
  battle.enemyParty[1].hp = 0
  last.hp = 0
  battle:resolveFaints()
  return battle
end

local paid = record(0)
local won = beat(paid)
eq(won.outcome, "win", "the battle ends on a win")
eq(paid.player.money, 900, "and the save is paid the cart's figure")
check(won.prize ~= nil, "the battle keeps the award it made")

-- The money line is an EVENT, so the battle screen shows it the same way it
-- shows every other line: no new seam, no new phase.
local sawMoney = nil
for _, event in ipairs(won.events) do
  if event.kind == "money" then sawMoney = event end
end
check(sawMoney ~= nil, "a `money` event is emitted")
check(sawMoney and sawMoney.text and sawMoney.text:find("900", 1, true) ~= nil,
  "carrying the line StdBattleTextbox would print")

-- CheckAmuletCoin latches on the SEND-OUT, so the lead's held item counts.
local coined = record(0)
beat(coined, { playerItem = Prize.AMULET_COIN })
eq(coined.player.money, 1800, "a lead holding the AMULET COIN doubles it")

-- A battle with no save (a headless turn-order test, or a link battle) pays
-- nobody rather than throwing.
local noSave = beat(nil)
eq(noSave.outcome, "win", "a battle with no save still ends")

-- A WILD battle pays nothing: WinTrainerBattle is the trainer arm and nothing
-- else reaches it.
local wildSave = record(0)
local wild = Battle.new({ data = DATA, save = wildSave,
  party = { mon("RATTATA", 10, 20) }, wild = mon("PIDGEY", 3, 0) })
wild:resolveFaints()
eq(wildSave.player.money, 0, "beating a wild mon pays nothing")

-- --------------------------------------------- the class attribute row

-- TrainerClassAttributes is SEVEN bytes and the base reward is the THIRD, so
-- Trainers.lookup has to carry it through to the battle or the payout is
-- always zero.
local TRAINER_DATA = { classes = { FALKNER = { id = "FALKNER", index = 1,
  name = "FALKNER", baseMoney = 25, items = {},
  trainers = { [1] = { id = "FALKNER1", name = "FALKNER",
    party = { { species = "PIDGEY", level = 7 } } } } } } }
local looked = Trainers.lookup(TRAINER_DATA, 1, 1)
eq(looked and looked.baseMoney, 25, "the class's base reward survives lookup")

-- ------------------------------------------------------- Mom goes shopping

local function momSave(saved)
  local save = Save.normalize({ mom = { savedMoney = saved, active = true,
    savingMoney = true }, party = {} })
  return save
end

-- NewGame's seed, which is also what MomShopping.state fills in for a file
-- that predates it.
local seeded = MomShopping.state(momSave(0))
eq(seeded.whichItem, 0, "the ladder starts on its first rung")
eq(seeded.triggerBalance, MomShopping.MOM_MONEY,
  "and the consolation threshold at MOM_MONEY")

-- data/items/mom_phone.asm: the four dolls and their thresholds.  These are
-- the only way a Gold player gets any of them.
local DOLLS = {
  { trigger = 10000, deco = 35, label = "CHARMANDER" },
  { trigger = 30000, deco = 32, label = "CLEFAIRY" },
  { trigger = 50000, deco = 30, label = "PIKACHU" },
  { trigger = 100000, deco = 26, label = "BIG SNORLAX" },
}
local dollRows = 0
for _, row in ipairs(MomShopping.ITEMS_2) do
  if row.kind == 2 then dollRows = dollRows + 1 end
end
eq(dollRows, 4, "MomItems_2 carries four dolls")
for _, doll in ipairs(DOLLS) do
  local found = nil
  for _, row in ipairs(MomShopping.ITEMS_2) do
    if row.item == doll.deco then found = row end
  end
  check(found ~= nil, doll.label .. "'s doll is on the list")
  eq(found and found.trigger, doll.trigger,
    "and unlocks at its own savings threshold")
  eq(Decorations.attributes(doll.deco) ~= nil, true,
    "and its DECO id names a real decoration row")
end

-- Under the first rung and off a MOM_MONEY multiple: nothing happens.
local quiet = momSave(500)
check(MomShopping.tryBuy(quiet, { events = Events.new() }) == nil,
  "with too little saved Mom buys nothing")

-- The ladder, one rung per won trainer battle.  10000 banked is past the
-- first three triggers, and each buy comes out of the savings -- which is why
-- the doll at 10000 does NOT follow them: three purchases have dropped the
-- balance under its own trigger and it has to be earned back.
local ladder = momSave(10000)
local events = Events.new()
local bought = {}
for _ = 1, 4 do
  bought[#bought + 1] = MomShopping.tryBuy(ladder, { events = events,
    random = function() return 0 end })
end
eq(bought[1] and bought[1].item, "SUPER_POTION", "rung one is a SUPER POTION")
eq(bought[2] and bought[2].item, "REPEL", "rung two a REPEL")
eq(bought[3] and bought[3].item, "SUPER_POTION", "rung three another")
check(bought[4] == nil, "and the doll waits: the buying spent its trigger")
eq(ladder.mom.whichItem, 3, "the ladder has moved on three rungs")
eq(ladder.mom.savedMoney, 10000 - 600 - 270 - 600,
  "and every cost came out of her savings")
eq(ladder.pcItems.SUPER_POTION, 2, "the two potions are in the PC")
eq(ladder.pcItems.REPEL, 1, "and so is the REPEL")

-- Saved back up to the trigger, the doll arrives -- and it is a decoration
-- flag, not a PC item, because Mom_GiveItemOrDoll's doll arm goes through
-- DecorationFlagAction_c.
ladder.mom.savedMoney = 10000
local doll = MomShopping.tryBuy(ladder, { events = events })
eq(doll and doll.kind, "doll", "rung four is the doll")
eq(doll and doll.item, 35, "the CHARMANDER doll")
check(Decorations.owns(events, 35), "which the player now owns")
eq(ladder.mom.savedMoney, 10000 - 1800, "and she paid 1800 for it")
eq(ladder.pcItems[35], nil, "a doll does not go in the PC")

-- MomItems_1: the consolation buy, which fires only when the LADDER has
-- nothing to offer (the next rung's trigger is out of reach) and the savings
-- land EXACTLY on a MOM_MONEY multiple the threshold has not passed.
local function stalledSave(saved)
  local save = momSave(saved)
  MomShopping.state(save)
  -- Rung two wants 4000; anything below that leaves the ladder stalled.
  save.mom.whichItem = 1
  return save
end
local exact = stalledSave(MomShopping.MOM_MONEY)
local consolation = MomShopping.tryBuy(exact, { events = Events.new(),
  random = function() return 1 end })
eq(consolation and consolation.set, 1, "an exact 2300 buys off MomItems_1")
eq(consolation and consolation.item, "ANTIDOTE", "the row the roll picked")
eq(exact.mom.whichItem, 1, "and the ladder has NOT moved")
eq(exact.mom.triggerBalance, MomShopping.MOM_MONEY * 2,
  "while the threshold has climbed a step")
exact.mom.savedMoney = MomShopping.MOM_MONEY
check(MomShopping.tryBuy(exact, { events = Events.new(),
  random = function() return 1 end }) == nil,
  "so the same 2300 cannot pay twice")

-- Overshooting the threshold is `.less_than`: the balance is left where the
-- walk pushed it and nothing is bought.
local between = stalledSave(MomShopping.MOM_MONEY + 1)
check(MomShopping.tryBuy(between, { events = Events.new() }) == nil,
  "a balance between two rungs buys nothing")
eq(between.mom.triggerBalance, MomShopping.MOM_MONEY * 2,
  "and the threshold has walked past it")

-- GetMapPhoneService: no reception, no call, and the balance is not even
-- looked at -- so Mom tries again after the next trainer.
local noService = stalledSave(MomShopping.MOM_MONEY)
check(MomShopping.tryBuy(noService, { events = Events.new(),
  phoneService = false }) == nil, "a map with no phone service buys nothing")
eq(noService.mom.triggerBalance, MomShopping.MOM_MONEY,
  "and leaves the threshold alone")

-- Mom_GetScriptPointer's two scripts.
local MOM_TEXT = require("tests.fixture_data.gen2_rom_text_s7_g").text()
local itemPages = MomShopping.pages({ kind = "item" }, { text = MOM_TEXT })
local dollPages = MomShopping.pages({ kind = "doll" }, { text = MOM_TEXT })
eq(#itemPages, 4, ".ItemScript is four writetexts")
eq(#dollPages, 4, "and so is .DollScript")
eq(itemPages[4], (MOM_TEXT._MomItsInPCText:gsub("{DONE}", "")),
  "the item ends up in the PC")
eq(dollPages[4], (MOM_TEXT._MomItsInYourRoomText:gsub("{DONE}", "")),
  "and the doll in your room")
check(not pcall(MomShopping.pages, { kind = "item" }, { text = {} }),
  "a dataset without Mom's lines is an error")
check(itemPages[1] == dollPages[1], "both open on the same greeting")

-- A doll cannot fail; an item into a full PC can, and then nothing is
-- deducted (Mom_GiveItemOrDoll's no-carry return).
local fullPc = momSave(10000)
fullPc.pcItems = {}
for i = 1, 50 do fullPc.pcItems["FILLER_" .. i] = 1 end
local refused = MomShopping.tryBuy(fullPc, { events = Events.new() })
check(refused == nil, "a full PC refuses the purchase")
eq(fullPc.mom.savedMoney, 10000, "and nothing is deducted")
eq(fullPc.mom.whichItem, 0, "and the ladder does not move")

-- ------------------------------------------------ the two World call sites
--
-- A model with a green suite and no door is the failure this file exists to
-- avoid, so both seams are driven through World:startBattle itself rather
-- than called by hand: the battle screen is replaced through the screens
-- REGISTRY (the same door a mod uses), which hands back the real `onDone`
-- closure Script_reloadmapafterbattle's two arms live in.

local World = require("src.world.gen2.World")
local Screens = require("src.ui.Screens")

local function battleWorld(save)
  local captured = {}
  -- Screens caches a factory by id alone, so a second world would otherwise
  -- be handed the first one's closure.
  Screens.invalidate()
  local game = {
    data = {
      pokemon = DATA.pokemon, moves = DATA.moves,
      text = require("tests.fixture_data.gen2_rom_text_s7_g").text(),
      screens = {
        Gen2BattleState = function(_, opts)
          captured.opts = opts
          return { screenId = "Gen2BattleState" }
        end,
      },
    },
    save = save,
    stack = { push = function() end, pop = function() end },
  }
  local world = World.new(game)
  game.world = world
  world.map = { def = { id = "TEST_MAP", phoneService = true } }
  world.maps = { TEST_MAP = world.map.def }
  world.events = Events.new()
  -- The render and audio halves, which have no place in a headless run.
  world.playBattleMusic = function() end
  world.battleMusicContext = function() return nil end
  world.pushBattleTransition = function() return nil end
  world.restoreMapMusic = function() end
  world.healParty = function() end
  world.warpToSpawn = function() end
  return world, captured
end

local lossSave = Save.normalize({ party = {},
  player = { name = "GOLD", money = 3001 },
  mom = { savedMoney = 4000, active = true, savingMoney = true } })
local lossWorld, lossCaptured = battleWorld(lossSave)
lossWorld:startBattle({ trainer = { name = "FALKNER", baseMoney = 25,
  party = { mon("PIDGEY", 9, 5) } } })
check(lossCaptured.opts ~= nil, "startBattle pushes the battle screen")
check(lossCaptured.opts and lossCaptured.opts.save == lossSave,
  "handing it the save the payout writes")
lossCaptured.opts.onDone("lose")
eq(lossSave.player.money, 1500, "a lost battle halves the wallet")
eq(lossSave.mom.savedMoney, 4000,
  "and leaves Mom's savings alone -- HalveMoney shifts wMoney only")

-- The Bug Contest arm: `checkflag ENGINE_BUG_CONTEST_TIMER / iftrue
-- .bug_contest` skips both callasms, so a wipe in the park is free.
local parkSave = Save.normalize({ party = {},
  player = { name = "GOLD", money = 3000 } })
parkSave.bugContest = { active = true, start = { day = 0, hour = 0,
  minute = 0, second = 0 } }
local parkWorld, parkCaptured = battleWorld(parkSave)
parkWorld:startBattle({ trainer = { name = "FALKNER", baseMoney = 25,
  party = { mon("PIDGEY", 9, 5) } } })
parkCaptured.opts.onDone("lose")
eq(parkSave.player.money, 3000, "a wipe during the Bug Contest costs nothing")

-- The win arm: MomTriesToBuySomething, queued the way LoadMemScript queues it
-- so the four lines land after the trainer's own after-battle script.
local shopSave = Save.normalize({ party = {},
  player = { name = "GOLD", money = 0 },
  mom = { savedMoney = 900, active = true, savingMoney = true } })
local shopWorld, shopCaptured = battleWorld(shopSave)
shopWorld:startBattle({ trainer = { name = "FALKNER", baseMoney = 25,
  party = { mon("PIDGEY", 9, 5) } } })
check(shopWorld.queuedScript == nil, "nothing is queued before the battle")
shopCaptured.opts.onDone("win")
check(shopWorld.queuedScript ~= nil, "a won trainer battle lets Mom shop")
eq(shopSave.mom.savedMoney, 900 - 600, "and she pays for what she bought")
eq(shopSave.pcItems.SUPER_POTION, 1, "which is waiting in the PC")
local sawRaw = false
for _, row in ipairs(shopWorld.queuedScript or {}) do
  if row.op == "rawtext" then sawRaw = true end
end
check(sawRaw, "the queued script speaks the call's four lines")

-- A won WILD battle does not: Script_reloadmapafterbattle's `.was_wild` arm
-- goes to the box-full check instead.
local wildWorld, wildCaptured = battleWorld(Save.normalize({ party = {},
  player = { name = "GOLD", money = 0 },
  mom = { savedMoney = 900, active = true, savingMoney = true } }))
wildWorld.roamMonsAfterBattle = function() end
wildWorld:startBattle({ wild = mon("PIDGEY", 3, 5) })
wildCaptured.opts.onDone("win")
check(wildWorld.queuedScript == nil, "a wild battle gives Mom no chance")

-- The registry cache is process-wide, so the fake screen must not outlive
-- this file: tests/run_tests.lua dofiles every suite into one process.
Screens.invalidate()

return S.finish()
