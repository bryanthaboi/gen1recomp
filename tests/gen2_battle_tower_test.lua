-- The Battle Tower: engine/events/battle_tower/battle_tower.asm,
-- engine/events/battle_tower/rules.asm and the room menu at
-- mobile/mobile_46.asm:137.
--
--   luajit tests/gen2_battle_tower_test.lua
--
-- ROM-free.  The lobby rules, the challenge-state machine, the level/uber
-- room gates, the reward roll and the wInBattleTowerBattle badge guard, all
-- against fixtures.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 battle tower")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local Battle = require("src.battle.gen2.Battle")
local BattleTower = require("src.core.gen2.BattleTower")
local BattleTowerMenu = require("src.ui.gen2.BattleTowerMenu")
local Mon = require("src.battle.gen2.Mon")
local Save = require("src.core.gen2.Save")
local Screens = require("src.ui.Screens")
local Specials = require("src.script.gen2.Specials")

local A = BattleTower.ACTIONS

-- ---------------------------------------------------------------- fixtures

local ITEM_ORDER = {}
do
  -- ../pokecrystal/constants/item_constants.asm: only the span the reward roll
  -- walks has to be at its real index, so the filler carries the rest.
  for i = 1, 250 do ITEM_ORDER[i] = "FILLER_" .. i end
  ITEM_ORDER[18] = "POTION"
  ITEM_ORDER[26] = "HP_UP"
  ITEM_ORDER[27] = "PROTEIN"
  ITEM_ORDER[28] = "IRON"
  ITEM_ORDER[29] = "CARBOS"
  ITEM_ORDER[30] = "LUCKY_PUNCH"
  ITEM_ORDER[31] = "CALCIUM"
end

local DATA = {
  gen2Constants = { itemOrder = ITEM_ORDER },
  items = {
    POTION = { index = 18, pocket = "ITEM" },
    HP_UP = { index = 26, pocket = "ITEM" },
    CALCIUM = { index = 31, pocket = "ITEM" },
  },
}

local function mon(species, level, item, isEgg)
  return { species = species, level = level, item = item, isEgg = isEgg }
end

local function crystalSave()
  local save = { version = "crystal", player = { id = 7, badges = {} },
    party = {}, inventory = {} }
  return save
end

-- The hooks World:specialHooks hands a handler, stubbed.
local function fakeVm(opts)
  opts = opts or {}
  local vm = {
    scriptVar = opts.scriptVar or 0,
    specials = opts.hooks or {},
    pages = {},
    stringBuffer = "",
  }
  function vm:setStringBuffer(value) self.stringBuffer = value or "" end
  function vm:showRaw(body)
    body = tostring(body)
    if self.stringBuffer ~= "" then
      body = body:gsub("{STRBUF}", self.stringBuffer)
    end
    self.pages[#self.pages + 1] = body
  end
  return vm
end

local function towerVm(save, extra)
  local hooks = {
    save = function() return save end,
    data = function() return DATA end,
    party = function() return save.party end,
    itemIndex = function(id)
      for index, name in ipairs(ITEM_ORDER) do
        if name == id then return index end
      end
      return 0
    end,
  }
  for key, value in pairs(extra or {}) do hooks[key] = value end
  return fakeVm({ hooks = hooks })
end

local function action(vm, id)
  vm.scriptVar = id
  Specials.ALL.BattleTowerAction(vm)
  return vm.scriptVar
end

-- ============================================== the seam and the ownership
do
  -- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:181-259 and
  -- :1534-1576 joined the list once the roster reached trainers.lua; their own
  -- behaviour is tests/gen2_battle_tower_battle_test.lua.
  for _, name in ipairs({ "BattleTowerAction", "CheckForBattleTowerRules",
      "Menu_ChallengeExplanationCancel", "BattleTowerRoomMenu",
      "BattleTowerBattle", "LoadOpponentTrainerAndPokemonWithOTSprite" }) do
    eq(Specials.HANDLER_SOURCE[name], "specials/battle_tower.lua",
      name .. " is owned by specials/battle_tower.lua")
    check(type(Specials.ALL[name]) == "function",
      name .. " resolves to a function")
    eq(Specials.STUBS[name], nil, name .. " is no longer a stub")
  end

  for _, name in ipairs({ "BattleTowerMobileError" }) do
    check(type(Specials.STUB_REASONS[name]) == "string",
      name .. " is still a deliberate stub, with its reason")
  end

  local found = false
  for _, id in ipairs(Screens.GEN2_IDS) do
    if id == "Gen2BattleTowerMenu" then found = true end
  end
  check(found, "Gen2BattleTowerMenu joined Screens.GEN2_IDS")
end

-- ================================================= _CheckForBattleTowerRules
do
  local legal = { mon("PIKACHU", 40, "BERRY"), mon("GEODUDE", 40, "GOLD_BERRY"),
    mon("HORSEA", 40) }
  local lines, failed = BattleTower.checkRules(legal)
  eq(#lines, 0, "a legal three-mon party prints nothing")
  eq(failed, false, "and _CheckForBattleTowerRules returns no carry")

  -- Two itemless mons do not collide: `ld a, [hl] / and a / jr z, .next`
  -- drops a zero value before the inner scan ever runs.
  local bare = { mon("PIKACHU", 40), mon("GEODUDE", 40), mon("HORSEA", 40) }
  eq(#(BattleTower.checkRules(bare)), 0,
    "three mons holding nothing is legal")

  lines = BattleTower.checkRules({ mon("PIKACHU", 40), mon("GEODUDE", 40) })
  eq(table.concat(lines, "|"),
    "_ExcuseMeYoureNotReadyText|_OnlyThreeMonMayBeEnteredText|"
    .. "_BattleTowerReturnWhenReadyText",
    "two mons: the header, the count line and the tail")

  lines = BattleTower.checkRules({ mon("PIKACHU", 40), mon("PIKACHU", 40),
    mon("HORSEA", 40) })
  eq(lines[2], "_TheMonMustAllBeDifferentKindsText",
    "a duplicate species is the second check")

  lines = BattleTower.checkRules({ mon("PIKACHU", 40, "BERRY"),
    mon("GEODUDE", 40, "BERRY"), mon("HORSEA", 40) })
  eq(lines[2], "_TheMonMustNotHoldTheSameItemsText",
    "a duplicate held item is the third")

  lines = BattleTower.checkRules({ mon("PIKACHU", 40), mon("GEODUDE", 40),
    mon("ODD_EGG", 5, nil, true) })
  eq(lines[2], "_YouCantTakeAnEggText", "an egg is the fourth")

  -- An egg is skipped by BOTH uniqueness walks (CheckPartyValueIsUnique's
  -- `.isegg` guards each side), so it only trips its own check.
  lines = BattleTower.checkRules({ mon("PIKACHU", 40, "BERRY"),
    mon("PIKACHU", 40, "BERRY", true), mon("HORSEA", 40) })
  eq(table.concat(lines, "|"),
    "_ExcuseMeYoureNotReadyText|_YouCantTakeAnEggText|"
    .. "_BattleTowerReturnWhenReadyText",
    "an egg duplicating a species and an item still only fails the egg rule")

  -- Every check runs; BattleTower_ExecuteJumptable does not stop at the first.
  lines = BattleTower.checkRules({ mon("PIKACHU", 40, "BERRY"),
    mon("PIKACHU", 40, "BERRY"), mon("HORSEA", 40, "BERRY"),
    mon("ODD_EGG", 5, nil, true) })
  eq(table.concat(lines, "|"),
    "_ExcuseMeYoureNotReadyText|_OnlyThreeMonMayBeEnteredText|"
    .. "_TheMonMustAllBeDifferentKindsText|"
    .. "_TheMonMustNotHoldTheSameItemsText|_YouCantTakeAnEggText|"
    .. "_BattleTowerReturnWhenReadyText",
    "four failures print the header, all four lines and the tail, in order")
end

-- ---- the special itself
do
  local save = crystalSave()
  save.party = { mon("PIKACHU", 40), mon("GEODUDE", 40), mon("HORSEA", 40) }
  local vm = towerVm(save)
  Specials.ALL.CheckForBattleTowerRules(vm)
  eq(vm.scriptVar, 0, "a legal party answers FALSE, the `ifnotequal FALSE` arm")
  eq(#vm.pages, 0, "and prints nothing")

  save.party = { mon("PIKACHU", 40) }
  vm = towerVm(save)
  Specials.ALL.CheckForBattleTowerRules(vm)
  eq(vm.scriptVar, 1, "a broken party answers TRUE")
  eq(#vm.pages, 3, "and prints header, refusal and tail")
  eq(vm.stringBuffer, "3", "wStringBuffer2 holds the '3' the lines splice in")
end

-- ============================================== the rooms and their gates
do
  local save = crystalSave()
  eq(#BattleTower.levelGroupRows(save), 4,
    "before the Hall of Fame only L10-L40 are offered")
  save.hallOfFame = { count = 1, teams = {} }
  eq(#BattleTower.levelGroupRows(save), 10,
    "and all ten once STATUSFLAGS_HALL_OF_FAME_F is set")

  -- maps/BattleTowerHallway.asm:40-47, the room the receptionist walks to.
  eq(BattleTower.roomOf(1), 0, "L10 is the 10/20 room")
  eq(BattleTower.roomOf(2), 0, "L20 shares it")
  eq(BattleTower.roomOf(3), 1, "L30 is the 30/40 room")
  eq(BattleTower.roomOf(4), 1, "L40 shares it")
  eq(BattleTower.roomOf(9), 4, "L90 is the 90/100 room")
  eq(BattleTower.roomOf(10), 4, "L100 shares it")

  local party = { mon("PIKACHU", 30), mon("GEODUDE", 30), mon("HORSEA", 30) }
  eq(BattleTower.levelCheck(party, 3), false, "L30 mons fit the L30 room")
  eq(BattleTower.levelCheck(party, 2), true, "and top the L20 room")
  party[1].level = 31
  eq(BattleTower.levelCheck(party, 3), true, "one mon over is enough")

  local ubers = { mon("LUGIA", 40), mon("GEODUDE", 40), mon("HORSEA", 40) }
  eq(BattleTower.ubersCheck(ubers, 4), "LUGIA",
    "an uber is refused below the L70 rooms")
  eq(BattleTower.ubersCheck(ubers, 7), nil,
    "and allowed from the L70 room up")
  ubers[1] = mon("MEWTWO", 70)
  eq(BattleTower.ubersCheck(ubers, 6), nil,
    "an uber already at L70 is past the `cp 70 / jr c` gate")
  eq(BattleTower.ubersCheck({ mon("DRAGONITE", 40) }, 4), nil,
    "and DRAGONITE is not on the list")
end

-- ==================================================== the reward (:906-976)
do
  -- The `maskbits` roll is over eight values folded into six, so HP_UP and
  -- PROTEIN come up twice as often; LUCKY_PUNCH is rerolled.
  local seen = {}
  for roll = 1, 8 do
    local n = 0
    local item = BattleTower.rollReward(ITEM_ORDER, function(mask)
      n = n + 1
      -- Specials.random answers 1..mask, and the handler folds it with % mask.
      return (n == 1) and roll or 1
    end)
    seen[roll % 8] = item
  end
  eq(seen[1], "PROTEIN", "roll 1 is PROTEIN")
  eq(seen[2], "IRON", "roll 2 is IRON")
  eq(seen[3], "CARBOS", "roll 3 is CARBOS")
  eq(seen[5], "CALCIUM", "roll 5 is CALCIUM")
  eq(seen[0], "HP_UP", "roll 0 is HP_UP")
  eq(seen[6], "HP_UP", "roll 6 folds back onto HP_UP")
  eq(seen[7], "PROTEIN", "roll 7 folds back onto PROTEIN")
  check(seen[4] ~= "LUCKY_PUNCH", "roll 4 lands on LUCKY_PUNCH and rerolls")

  eq(BattleTower.rewardFits(19, 20, nil), true,
    "a pocket with a free slot takes the five")
  eq(BattleTower.rewardFits(20, 20, nil), false,
    "a full pocket holding none of the reward cannot")
  eq(BattleTower.rewardFits(20, 20, 94), true,
    "a full pocket already holding 94 can stack five more")
  eq(BattleTower.rewardFits(20, 20, 95), false,
    "95 is where MAX_ITEM_STACK - 5 + 1 stops it")
end

-- ================================== BattleTowerAction, every jumptable row
do
  local save = crystalSave()
  local vm = towerVm(save)
  -- ../pokecrystal/engine/events/battle_tower/battle_tower.asm:855-887
  local unhandled = {}
  for id = 0, BattleTower.NUM_ACTIONS - 1 do
    vm.scriptVar = id
    local before = vm.scriptVar
    local ok = pcall(Specials.ALL.BattleTowerAction, vm)
    if not ok then unhandled[#unhandled + 1] = id end
    if ok and vm.scriptVar == before and before ~= 0 then
      -- a row that answers nothing must be one of the documented no-writes
      local writesNothing = (id == A.SET_EXPLANATION_READ)
        or (id == A.SAVE_AND_QUIT) or (id == A.CHALLENGECANCELED)
        or (id == A.ACTION_06) or (id == A.SAVELEVELGROUP)
        or (id == A.LOADLEVELGROUP) or (id == A.ACTION_0A)
        or (id == A.ACTION_0C) or (id == A.ACTION_11) or (id == A.ACTION_12)
        or (id == A.ACTION_15) or (id == A.ACTION_16) or (id == A.RESETDATA)
        or (id == A.ACTION_1C) or (id == A.ACTION_1D)
        or (id == A.CHOOSEREWARD) or (id == A.SAVEOPTIONS)
      if not writesNothing then unhandled[#unhandled + 1] = id end
    end
  end
  eq(table.concat(unhandled, ","), "",
    "all 32 BattleTowerAction rows run, and only the cart's silent ones "
    .. "leave wScriptVar alone")
end

-- ---- the challenge state machine (:992-1022, :935-949)
do
  local save = crystalSave()
  local vm = towerVm(save)
  eq(action(vm, A.GET_CHALLENGE_STATE), BattleTower.NO_CHALLENGE,
    "a fresh save is BATTLETOWER_NO_CHALLENGE")
  action(vm, A.SAVE_AND_QUIT)
  eq(action(vm, A.GET_CHALLENGE_STATE), BattleTower.SAVED_AND_LEFT,
    "the quicksave arm parks on BATTLETOWER_SAVED_AND_LEFT")
  action(vm, A.ACTION_1C)
  eq(action(vm, A.GET_CHALLENGE_STATE), BattleTower.WON_CHALLENGE,
    "beating the seventh trainer is BATTLETOWER_WON_CHALLENGE")
  action(vm, A.ACTION_1D)
  eq(action(vm, A.GET_CHALLENGE_STATE), BattleTower.RECEIVED_REWARD,
    "and taking the prize is BATTLETOWER_RECEIVED_REWARD")
  action(vm, A.CHALLENGECANCELED)
  eq(action(vm, A.GET_CHALLENGE_STATE), BattleTower.NO_CHALLENGE,
    "cancelling clears it")
end

-- ---- sBattleTowerSaveFileFlags (:978-1008, :1471-1492)
do
  local save = crystalSave()
  local tower = BattleTower.state(save)
  eq(tower.saveFileFlags, 0, "a fresh save has no tower flags")
  BattleTower.setSaveFileFlag(save, BattleTower.SAVEFILE_EXPLANATION)
  eq(BattleTower.saveFileFlag(save, BattleTower.SAVEFILE_EXPLANATION), 2,
    "`and 2` answers the masked byte, not a boolean")
  eq(BattleTower.saveFileFlag(save, BattleTower.SAVEFILE_REGISTERED), 0,
    "and bit 0 is untouched")
  BattleTower.setSaveFileFlag(save, BattleTower.SAVEFILE_EXPLANATION)
  eq(tower.saveFileFlags, 2, "`or 2` twice is still 2")
  BattleTower.setSaveFileFlag(save, BattleTower.SAVEFILE_REGISTERED)
  eq(tower.saveFileFlags, 3, "both bits live in the one byte")

  -- :979-982 -- with no save file on disk the routine returns FALSE without
  -- ever reading the flags.
  local vm = towerVm(save)
  eq(action(vm, A.CHECK_EXPLANATION_READ), 0,
    "no save file means the explanation check answers FALSE")
  eq(action(vm, A.CHECKSAVEFILEISYOURS), 0,
    "and so does the save-file check itself")
end

-- ---- the level group (:1129-1155) and the GS Ball (:1179-1185)
do
  local save = crystalSave()
  local vm = towerVm(save)
  vm.btLevelGroup = 7
  action(vm, A.SAVELEVELGROUP)
  eq(BattleTower.state(save).levelGroup, 7,
    "SAVELEVELGROUP banks wBTChoiceOfLvlGroup in SRAM")
  vm.btLevelGroup = nil
  action(vm, A.LOADLEVELGROUP)
  eq(vm.btLevelGroup, 7, "and LOADLEVELGROUP brings it back for the hallway")

  eq(action(vm, A.GSBALL), 0, "no GS Ball, no scene")
  Save.crystalState(save).gsBall = "have"
  eq(action(vm, A.GSBALL), BattleTower.GS_BALL_AVAILABLE,
    "sGSBallFlag reads back as GS_BALL_AVAILABLE ($b)")
  Save.crystalState(save).gsBall = "given"
  eq(action(vm, A.GSBALL), BattleTower.GS_BALL_AVAILABLE,
    "and stays set once the ball has been handed over")
end

-- ---- RESETDATA and the prize (:890-933, :955-976)
do
  local save = crystalSave()
  local tower = BattleTower.state(save)
  tower.streak = 5
  tower.trainers = { 3, 9 }
  local vm = towerVm(save)
  action(vm, A.RESETDATA)
  eq(tower.streak, 0, "RESETDATA clears sNrOfBeatenBattleTowerTrainers")
  eq(next(tower.trainers), nil, "and the seven sBTTrainers slots")

  local rewards = {}
  for _ = 1, 200 do
    action(vm, A.CHOOSEREWARD)
    rewards[tower.reward] = true
  end
  eq(rewards.POTION, nil,
    "CHOOSEREWARD never falls back on POTION: it reads gen2Constants.itemOrder")
  eq(rewards[BattleTower.SKIPPED_REWARD], nil, "and never rolls LUCKY_PUNCH")
  for name in pairs(rewards) do
    check(name == "HP_UP" or name == "PROTEIN" or name == "IRON"
      or name == "CARBOS" or name == "CALCIUM",
      name .. " is inside BATTLETOWER_MIN_REWARD..MAX_REWARD")
  end
  eq(rewards.HP_UP, true, "and the whole span comes up (HP_UP)")
  eq(rewards.CALCIUM, true, "through CALCIUM")

  tower.reward = "CALCIUM"
  eq(action(vm, A.GIVEREWARD), 31, "GIVEREWARD answers the item id")
  -- A full ITEM pocket that does not already hold the reward: the desk hands
  -- over a POTION, which is the script's `ifequal POTION` arm.
  for i = 1, 20 do save.inventory["FILLER_" .. i] = 1 end
  eq(action(vm, A.GIVEREWARD), 18,
    "a stuffed pack turns the prize into POTION")
end

-- ---- Menu_ChallengeExplanationCancel (mobile/mobile_5f.asm:425-468)
do
  local save = crystalSave()
  for row = 1, 3 do
    local vm = towerVm(save, {
      scriptMenu = function(_header, done) done(row) end,
    })
    vm.scriptVar = 1
    Specials.ALL.Menu_ChallengeExplanationCancel(vm)
    eq(vm.scriptVar, row, "row " .. row .. " comes back as wScriptVar")
  end
  local vm = towerVm(save, {
    scriptMenu = function(_header, done) done(0) end,
  })
  vm.scriptVar = 1
  Specials.ALL.Menu_ChallengeExplanationCancel(vm)
  eq(vm.scriptVar, 4, "a B press is the `.Exit` arm's 4")

  vm = towerVm(save)
  vm.scriptVar = 1
  Specials.ALL.Menu_ChallengeExplanationCancel(vm)
  eq(vm.scriptVar, 4, "and so is a run with no menu to open")
end

-- ---- BattleTowerRoomMenu (battle_tower.asm:1-5)
do
  local save = crystalSave()
  save.hallOfFame = { count = 1, teams = {} }
  local pushed
  local vm = towerVm(save, {
    pushScreen = function(id, opts)
      pushed = id
      opts.onDone(6)
      return true
    end,
  })
  Specials.ALL.BattleTowerRoomMenu(vm)
  eq(pushed, "Gen2BattleTowerMenu", "the desk opens the room menu screen")
  eq(vm.scriptVar, 0, "a chosen room answers 0, the script's `ifnotequal $0`")
  eq(vm.btLevelGroup, 6, "and wBTChoiceOfLvlGroup holds the L60 room")

  vm = towerVm(save, {
    pushScreen = function(_id, opts)
      opts.onDone(nil)
      return true
    end,
  })
  Specials.ALL.BattleTowerRoomMenu(vm)
  eq(vm.scriptVar, 0x0a, "cancelling answers $a, the desk's loop-back arm")

  vm = towerVm(save)
  Specials.ALL.BattleTowerRoomMenu(vm)
  eq(vm.scriptVar, 0x0a, "and so does a run with no screen to push")
end

-- ============================================ the room menu screen itself
do
  eq(BattleTowerMenu.levelLabel(1), " L:10 ", "Strings_L10ToL100 row 1")
  eq(BattleTowerMenu.levelLabel(10), " L:100", "and row 10, six tiles wide")

  local pressed = {}
  local game = { input = { wasPressed = function(_, name)
    return pressed[name] == true
  end } }
  local function press(name) pressed = { [name] = true } end

  local save = crystalSave()
  save.hallOfFame = { count = 1, teams = {} }
  local result, calls = nil, 0
  local screen = BattleTowerMenu.new(game, {
    save = save,
    party = { mon("PIKACHU", 20), mon("GEODUDE", 20), mon("HORSEA", 20) },
    onDone = function(value) result = value; calls = calls + 1 end,
  })
  eq(screen.cursor, 1, "the spinner opens on L:10")
  eq(screen:rowCount(), 11, "ten rooms plus CANCEL")

  press("up"); screen:update()
  eq(screen.cursor, 2, "UP walks the level up")
  press("down"); screen:update()
  press("down"); screen:update()
  eq(screen.cursor, 11, "DOWN off the top rolls over to CANCEL")
  press("up"); screen:update()
  eq(screen.cursor, 1, "and UP off CANCEL rolls back to L:10")

  -- A party at L20 tops the L10 room (mobile/mobile_46.asm:3915-3917).
  press("a"); screen:update()
  eq(screen.phase, "message", "picking L:10 with L20 mons prints a refusal")
  eq(calls, 0, "and does not answer the script")
  for _ = 1, 0x80 do pressed = {}; screen:update() end
  eq(screen.phase, "pick", "the $80-frame hold puts the menu back")
  eq(screen.cursor, 1, "at jumptable index 0, cursor reset")

  press("up"); screen:update()
  press("a"); screen:update()
  eq(result, 2, "L:20 is accepted and hands back the level group")
  eq(calls, 1, "exactly once")
end

do
  -- The uber gate, and the CANCEL path's yes/no.
  local pressed = {}
  local game = { input = { wasPressed = function(_, name)
    return pressed[name] == true
  end } }
  local function press(name) pressed = { [name] = true } end

  local save = crystalSave()
  local result, answered = nil, false
  local screen = BattleTowerMenu.new(game, {
    save = save,
    party = { mon("LUGIA", 40), mon("GEODUDE", 40), mon("HORSEA", 40) },
    monName = function(id) return id end,
    onDone = function(value) result = value; answered = true end,
  })
  eq(screen:rowCount(), 5, "no Hall of Fame, so four rooms plus CANCEL")
  for _ = 1, 3 do press("up"); screen:update() end
  eq(screen.cursor, 4, "on L:40")
  press("a"); screen:update()
  eq(screen.phase, "message", "an uber under L70 is refused below the L70 room")
  check(screen.message:find("LUGIA", 1, true) ~= nil,
    "and the refusal names it, the way text_ram wcd49 does")

  for _ = 1, 0x80 do pressed = {}; screen:update() end
  eq(screen.cursor, 1, "the refusal restarts the menu at L:10")
  for _ = 1, 4 do press("up"); screen:update() end
  eq(screen.cursor, 5, "CANCEL is the last row")
  press("a"); screen:update()
  eq(screen.phase, "quit", "CANCEL opens the yes/no")
  eq(screen.yes, true, "on YES")
  press("down"); screen:update()
  press("a"); screen:update()
  eq(screen.phase, "pick", "NO puts the level spinner back")
  eq(answered, false, "and answers nothing yet")
  press("b"); screen:update()
  eq(screen.phase, "quit", "B on the spinner is the same cancel prompt")
  press("a"); screen:update()
  eq(answered, true, "YES ends the menu")
  eq(result, nil, "with no level group, which the handler turns into $a")
end

-- ================================ wInBattleTowerBattle and the badge boosts
do
  local GROWTH = { GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1,
    squared = 0, linear = 0, constant = 0 } }
  local BATTLE_DATA = {
    pokemon = {
      growthRates = GROWTH,
      MACHOP = { id = "MACHOP", index = 66, name = "MACHOP",
        baseStats = { hp = 70, attack = 80, defense = 50, speed = 35,
          specialAttack = 35, specialDefense = 35 },
        types = { "NORMAL", "NORMAL" }, catchRate = 180, baseExp = 75,
        growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 63,
        levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {} },
      PIDGEY = { id = "PIDGEY", index = 16, name = "PIDGEY",
        baseStats = { hp = 40, attack = 45, defense = 40, speed = 56,
          specialAttack = 35, specialDefense = 35 },
        types = { "NORMAL", "FLYING" }, catchRate = 255, baseExp = 55,
        growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
        levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {} },
    },
    moves = {}, type_chart = { types = {}, matchups = {} }, items = {},
  }
  local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
  perfect.hp = Mon.hpDV(perfect)

  local BADGES = { ZEPHYR = true, HIVE = true, PLAIN = true, FOG = true,
    MINERAL = true, STORM = true, GLACIER = true, RISING = true }

  local function newBattle(tower)
    local player = Mon.new(BATTLE_DATA, "MACHOP", 40, { dvs = perfect })
    local wild = Mon.new(BATTLE_DATA, "PIDGEY", 40, { dvs = perfect })
    return Battle.new({ data = BATTLE_DATA, party = { player }, wild = wild,
      save = { player = { id = 7, badges = BADGES, kantoBadges = {} } },
      battleTower = tower,
      random = function(n) return (n or 1) > 1 and 1 or 0 end }), player
  end

  local outside, player = newBattle(false)
  eq(outside.inBattleTowerBattle, false, "an ordinary battle is not a Tower one")
  eq(outside:battleStat(player, "attack"),
    Battle.boostStat(player.stats.attack),
    "outside the Tower ZEPHYRBADGE still boosts Attack")
  eq(outside:battleStat(player, "speed"),
    Battle.boostStat(player.stats.speed), "and PLAINBADGE Speed")
  eq(outside:badgeTypeBoost(player, "FLYING"), true,
    "and DoBadgeTypeBoosts still fires")

  local inside, towerPlayer = newBattle(true)
  eq(inside.inBattleTowerBattle, true, "the Tower battle sets it")
  eq(inside:battleStat(towerPlayer, "attack"), towerPlayer.stats.attack,
    "BadgeStatBoosts' second early return drops the Attack boost")
  eq(inside:battleStat(towerPlayer, "defense"), towerPlayer.stats.defense,
    "and Defense")
  eq(inside:battleStat(towerPlayer, "speed"), towerPlayer.stats.speed,
    "and Speed")
  eq(inside:battleStat(towerPlayer, "specialAttack"),
    towerPlayer.stats.specialAttack, "and Special Attack")
  eq(inside:battleStat(towerPlayer, "specialDefense"),
    towerPlayer.stats.specialDefense,
    "and GLACIERBADGE's buggy Special Defense re-check with it")
  eq(inside:badgeTypeBoost(towerPlayer, "FLYING"), false,
    "DoBadgeTypeBoosts takes the same guard (engine/battle/misc.asm:152)")

  -- The obedience ladder shares Battle:hasBadge and the cart does NOT guard
  -- it (engine/battle/effect_commands.asm:671-696 reads wJohtoBadges raw).
  eq(inside:obedienceLevel(), outside:obedienceLevel(),
    "obedience reads the badges either way")
  eq(inside:hasBadge("badges", "ZEPHYR"), true,
    "and Battle:hasBadge itself is untouched")
end

-- ================================================ Gold and Silver are clean
do
  for _, version in ipairs({ "gold", "silver" }) do
    local save = Save.normalize({ version = version, generation = 2 })
    eq(save.version, version, version .. " keeps its own version")
    eq(save.battleTower, nil, version .. " grows no battleTower block")
    eq(save.crystal, nil, "nor a crystal one")
  end
  local crystal = Save.normalize({ version = "crystal", generation = 2 })
  eq(crystal.version, "crystal", "and the Crystal file stays Crystal")
  check(type(crystal.battleTower) == "table",
    "which does carry sBattleTowerChallengeState")
  eq(crystal.battleTower.challenge, BattleTower.NO_CHALLENGE,
    "starting at BATTLETOWER_NO_CHALLENGE")
end

S.finish()
