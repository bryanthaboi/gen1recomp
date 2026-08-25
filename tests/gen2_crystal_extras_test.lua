-- ../pokecrystal/engine/events/move_tutor.asm:1, engine/events/buena.asm:1
-- and :64, engine/events/poke_seer.asm:18, mobile/mobile_12_2.asm:191.
-- ROM-free:
--   luajit tests/gen2_crystal_extras_test.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

-- The same love stub tests/gen2_menus_test.lua installs; nothing here draws.
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
love.math = love.math or { random = function(a, b) return b and a or 1 end }
love.image = love.image or {}
love.filesystem = love.filesystem or {
  load = function() return nil end,
  getInfo = function() return nil end,
  read = function() return nil end,
}
love.timer = love.timer or { getTime = function() return 0 end }

local S = require("tests.harness").suite("gen2 crystal extras")
local check, eq = S.check, S.eq

require("src.core.Logger").warn = function() end

local Events = require("src.world.gen2.Events")
local Mon = require("src.battle.gen2.Mon")
local MoveTutorScreen = require("src.ui.gen2.MoveTutor")
local Save = require("src.core.gen2.Save")
local Specials = require("src.script.gen2.Specials")
local Vm = require("src.script.gen2.Vm")

local H = Specials.HANDLERS

-- --------------------------------------------------------------- fixtures

-- The cache tables the handlers read, plus the landmark registry
-- GetLandmarkName walks (../pokecrystal/engine/overworld/landmarks.asm:16).
local DATA = {
  pokemon = {
    tutorMoves = { "FLAMETHROWER", "THUNDERBOLT", "ICE_BEAM" },
    TYPHLOSION = { index = 157, name = "TYPHLOSION",
      tmhm = { "CUT", "STRENGTH" }, tutorMoves = { "FLAMETHROWER" } },
    GEODUDE = { index = 74, name = "GEODUDE",
      tmhm = { "STRENGTH" }, tutorMoves = { "FLAMETHROWER" } },
    LAPRAS = { index = 131, name = "LAPRAS", tmhm = { "SURF" } },
    CYNDAQUIL = { index = 155, name = "CYNDAQUIL" },
    TOTODILE = { index = 158, name = "TOTODILE" },
    CHIKORITA = { index = 152, name = "CHIKORITA" },
    PIKACHU = { index = 25, name = "PIKACHU" },
    RATTATA = { index = 19, name = "RATTATA" },
    HOOTHOOT = { index = 163, name = "HOOTHOOT" },
    SPINARAK = { index = 165, name = "SPINARAK" },
    DROWZEE = { index = 96, name = "DROWZEE" },
  },
  items = {
    ULTRA_BALL = { index = 2, name = "ULTRA BALL" },
    FULL_RESTORE = { index = 16, name = "FULL RESTORE" },
    NUGGET = { index = 92, name = "NUGGET" },
    RARE_CANDY = { index = 50, name = "RARE CANDY" },
    PROTEIN = { index = 33, name = "PROTEIN" },
    IRON = { index = 34, name = "IRON" },
    CARBOS = { index = 35, name = "CARBOS" },
    CALCIUM = { index = 37, name = "CALCIUM" },
    HP_UP = { index = 32, name = "HP UP" },
    POTION = { index = 17, name = "POTION" },
    ANTIDOTE = { index = 18, name = "ANTIDOTE" },
    PARLYZ_HEAL = { index = 21, name = "PARLYZ HEAL" },
    FRESH_WATER = { index = 39, name = "FRESH WATER" },
    SODA_POP = { index = 40, name = "SODA POP" },
    LEMONADE = { index = 41, name = "LEMONADE" },
    POKE_BALL = { index = 5, name = "POKé BALL" },
    GREAT_BALL = { index = 1, name = "GREAT BALL" },
    X_ATTACK = { index = 68, name = "X ATTACK" },
    X_DEFEND = { index = 69, name = "X DEFEND" },
    X_SPEED = { index = 67, name = "X SPEED" },
  },
  moves = {
    FLAMETHROWER = { name = "FLAMETHROWER" },
    THUNDERBOLT = { name = "THUNDERBOLT" },
    ICE_BEAM = { name = "ICE BEAM" },
    TACKLE = { name = "TACKLE" },
    GROWL = { name = "GROWL" },
    MUD_SLAP = { name = "MUD-SLAP" },
  },
  gen2Landmarks = {
    order = {},
    landmarks = {
      NEW_BARK_TOWN = { index = 1, name = "NEW BARK\nTOWN" },
      ROUTE_29 = { index = 2, name = "ROUTE 29" },
    },
  },
}

local function newSave()
  local save = {
    version = "crystal",
    player = { name = "KRIS", id = 0x1234, money = 0 },
    party = {},
    inventory = {},
    bagOrder = {},
  }
  Save.crystalState(save)
  return save
end

-- World:specialHooks, stubbed; every screen answers through its own onDone.
local function newHooks(save, opts)
  opts = opts or {}
  local vars = opts.vars or {}
  local log = { pushed = {}, sfx = {} }
  local hooks = {
    log = log,
    vars = vars,
    save = function() return save end,
    data = function() return DATA end,
    party = function() return save.party end,
    itemIndex = function(id)
      local def = DATA.items[id]
      return def and def.index
    end,
    hasItem = function(index) return opts.held and opts.held[index] == true end,
    playSfxNamed = function(name) log.sfx[#log.sfx + 1] = name end,
    selectPartyMon = function(prompt, done)
      log.selectPrompt = prompt
      done(opts.pickIndex, opts.pickIndex and save.party[opts.pickIndex])
    end,
    pushScreen = function(id, screenOpts)
      log.pushed[#log.pushed + 1] = { id = id, opts = screenOpts }
      if opts.noScreens then return false end
      local answer = opts.answers and opts.answers[#log.pushed]
      if screenOpts.onDone then screenOpts.onDone(answer) end
      return true
    end,
  }
  return hooks
end

-- The var pair is Vm.readVarFn / Vm.writeVarFn, not a `specials` hook:
-- engine/overworld/variables.asm's rows belong to `readvar` / `writevar`.
local function newVm(hooks, scriptVar)
  local vars = hooks.vars
  local vm = Vm.new({}, {}, Events.new(), {
    specials = hooks,
    readVar = function(id) return vars[id] or 0 end,
    writeVar = function(id, value) vars[id] = value end,
  })
  vm.showTextFn = function() end
  vm.scriptVar = scriptVar or 0
  return vm
end

-- Run one handler out, collecting its pages and feeding its YES/NO answers.
local function run(vm, handler, answers)
  answers = answers or {}
  local pages, asked = {}, 0
  local co = coroutine.create(function() handler(vm) end)
  vm.co = co
  local send
  while true do
    local ok, req = coroutine.resume(co, send)
    if not ok then error(req, 0) end
    if coroutine.status(co) == "dead" then break end
    send = nil
    if type(req) == "table" and req.kind == "text" then
      pages[#pages + 1] = req.text
    elseif type(req) == "table" and req.kind == "yesorno" then
      asked = asked + 1
      send = answers[asked]
    else
      pages.parked = req
      break
    end
  end
  return pages
end

-- ============================================================ the move tutor

-- .GetMoveTutorMove (engine/events/move_tutor.asm:36-52); anything that is
-- not MOVETUTOR_FLAMETHROWER or _THUNDERBOLT falls through to MT03.
do
  local function tutorMoveFor(value, answer)
    local save = newSave()
    local hooks = newHooks(save, { answers = { answer } })
    local vm = newVm(hooks, value)
    run(vm, H.MoveTutor)
    local pushed = hooks.log.pushed[1]
    return pushed and pushed.opts.move, vm.scriptVar
  end
  eq(select(1, tutorMoveFor(1, true)), "FLAMETHROWER", "MOVETUTOR_FLAMETHROWER is MT01")
  eq(select(1, tutorMoveFor(2, true)), "THUNDERBOLT", "MOVETUTOR_THUNDERBOLT is MT02")
  eq(select(1, tutorMoveFor(3, true)), "ICE_BEAM", "MOVETUTOR_ICE_BEAM is MT03")
  eq(select(1, tutorMoveFor(0, true)), "ICE_BEAM",
    "and anything else falls through to MT03, as the `cp` ladder does")

  local _, learned = tutorMoveFor(1, true)
  eq(learned, 0, "a taught move leaves wScriptVar FALSE, which is .TeachMove")
  local _, cancelled = tutorMoveFor(1, false)
  eq(cancelled, 255, "and a cancel leaves -1, which is .Incompatible")
end

-- engine/events/move_tutor.asm:29 .cancel, ahead of the script's
-- takecoins 4000 (maps/GoldenrodCity.asm:124).
do
  local save = newSave()
  local hooks = newHooks(save, { noScreens = true })
  local vm = newVm(hooks, 2)
  run(vm, H.MoveTutor)
  eq(vm.scriptVar, 255, "no screen is the -1 cancel, not a free lesson")
end

-- `add_mt` gives the three tutor moves TMHM flags 58-60
-- (constants/item_constants.asm:295-307), so CanLearnTMHMMove sees them.
do
  local view = MoveTutorScreen.speciesView(DATA.pokemon)
  check(MoveTutorScreen.canLearn(view.TYPHLOSION, "FLAMETHROWER"),
    "TYPHLOSION can be taught FLAMETHROWER")
  check(MoveTutorScreen.canLearn(view.TYPHLOSION, "CUT"),
    "and its ordinary TM list still answers")
  check(not MoveTutorScreen.canLearn(view.LAPRAS, "FLAMETHROWER"),
    "LAPRAS cannot")
  local merged = view.TYPHLOSION.tmhm
  eq(#merged, 3, "the view's tmhm list carries the tutor row too")
  eq(merged[3], "FLAMETHROWER", "appended after the TM/HM rows")
  check(view.TYPHLOSION == view.TYPHLOSION, "and the view is memoised")
  eq(view.MISSINGNO, nil, "a species the cache does not carry stays nil")
  eq(#DATA.pokemon.TYPHLOSION.tmhm, 2, "the cache's own record is not touched")
end

-- ================================================================== Buena

-- engine/events/buena_menu.asm:1-9: carry (NO or B) is 0, YES is 1.
do
  local save = newSave()
  local vm = newVm(newHooks(save))
  run(vm, H.AskRememberPassword, { true })
  eq(vm.scriptVar, 1, "YES is 1, which the script reads as `iffalse` not taken")
  local vm2 = newVm(newHooks(save))
  run(vm2, H.AskRememberPassword, { false })
  eq(vm2.scriptVar, 0, "and NO is 0, .ForgotPassword")
end

-- engine/events/buena.asm:19-23: only wBuenasPassword's low nybble is right.
do
  local save = newSave()
  -- BuenasPassword4's two rejection rolls, pinned
  -- (engine/pokegear/radio.asm:1470-1487).
  local rolls = { 1, 2 }
  local taken = 0
  local realRandom = Specials.random
  Specials.random = function() taken = taken + 1 return rolls[taken] end

  local hooks = newHooks(save, { answers = { 1 } })
  local vm = newVm(hooks)
  run(vm, H.BuenasPassword)
  Specials.random = realRandom

  local pushed = hooks.log.pushed[1]
  eq(pushed.id, "Gen2BuenaPassword", "the show opens its own menu")
  eq(pushed.opts.mode, "password", "in password mode")
  eq(pushed.opts.width, 10, "the box is as wide as the category's points byte")
  eq(table.concat(pushed.opts.words, ","), "CYNDAQUIL,TOTODILE,CHIKORITA",
    ".PlacePasswordChoices resolves BUENA_MON rows through GetPokemonName")
  eq(vm.scriptVar, 1, "picking the low nybble's row is the right answer")
  eq(save.crystal.buenaPassword.word, 0x01,
    "and the roll is packed group-high, word-low into wBuenasPassword")
  eq(hooks.vars[0x19], 0x01, "VAR_BUENASPASSWORD sees the same byte")

  -- DAILYFLAGS2_BUENAS_PASSWORD_F holds the roll for the day
  -- (engine/pokegear/radio.asm:1467).
  local hooks2 = newHooks(save, { answers = { 0 } })
  local vm2 = newVm(hooks2)
  run(vm2, H.BuenasPassword)
  eq(vm2.scriptVar, 0, "row 0 is a wrong guess")
  eq(save.crystal.buenaPassword.word, 0x01, "and the day's password is unchanged")
  eq(table.concat(hooks2.log.pushed[1].opts.words, ","),
    "CYNDAQUIL,TOTODILE,CHIKORITA", "so the menu offers the same three words")
end

-- GetBuenasPassword's four BUENA_* arms (engine/pokegear/radio.asm:1534),
-- and the points byte as the menu width (engine/events/buena.asm:9-12).
do
  local save = newSave()
  local realRandom = Specials.random
  local function pin(group, word)
    local rolls, taken = { group + 1, word + 1 }, 0
    Specials.random = function() taken = taken + 1 return rolls[taken] end
    save.crystal.buenaPassword.word = nil
    save.crystal.buenaPassword.day = nil
    local hooks = newHooks(save, { answers = { word } })
    local vm = newVm(hooks)
    run(vm, H.BuenasPassword)
    return hooks.log.pushed[1].opts, vm.scriptVar
  end
  local balls = pin(3, 2)
  eq(table.concat(balls.words, ","), "POKé BALL,GREAT BALL,ULTRA BALL",
    "BUENA_ITEM rows resolve through GetItemName")
  eq(balls.width, 12, "and .Balls is worth 12 points")
  local towns = pin(6, 0)
  eq(table.concat(towns.words, ","), "NEW BARK TOWN,CHERRYGROVE CITY,AZALEA TOWN",
    "BUENA_STRING rows are the literals themselves")
  eq(towns.width, 16, "the widest category is 16 wide")
  local moves = pin(8, 1)
  eq(table.concat(moves.words, ","), "TACKLE,GROWL,MUD-SLAP",
    "BUENA_MOVE rows resolve through GetMoveName")
  local types = pin(7, 0)
  eq(types.width, 6, ".Types is the narrowest box at 6")
  local _, right = pin(10, 2)
  eq(right, 1, "the eleventh category exists and its third row can be picked")
  Specials.random = realRandom
end

-- engine/events/buena.asm:25 .wrong is what a menu-less run has to take.
do
  local save = newSave()
  local vm = newVm(newHooks(save, { noScreens = true }))
  run(vm, H.BuenasPassword)
  eq(vm.scriptVar, 0, "no menu means no correct answer")
end

-- ------------------------------------------------------------ the prizes

-- data/items/buena_prizes.asm, and the cost / ReceiveItem / subtract order
-- (engine/events/buena.asm:95-119).
do
  local save = newSave()
  local hooks = newHooks(save, { vars = { [0x18] = 5 }, answers = { 1 } })
  local vm = newVm(hooks)
  local pages = run(vm, H.BuenaPrize, { true })

  local pushed = hooks.log.pushed[1]
  eq(pushed.opts.mode, "prize", "the counter opens the prize list")
  eq(#pushed.opts.prizes, 9, "NUM_BUENA_PRIZES rows")
  eq(pushed.opts.prizes[1].name, "ULTRA BALL", "the first prize")
  eq(pushed.opts.prizes[1].cost, 2, "costs 2 points")
  eq(pushed.opts.prizes[9].name, "HP UP", "the last prize")
  eq(pushed.opts.prizes[9].cost, 5, "costs 5")
  eq(pushed.opts.balance, 5, "and the Points box shows wBlueCardBalance")

  eq(save.inventory.ULTRA_BALL, 1, "one ULTRA BALL leaves the counter")
  eq(hooks.vars[0x18], 3, "and the two points come off the card")
  eq(hooks.log.sfx[1], "Sfx_Transaction", "SFX_TRANSACTION rings the sale")
  eq(pages[#pages], "Oh. Please come\nback again!",
    ".done prints _BuenaComeAgainText after the loop")
end

-- engine/events/buena.asm:93 `jr c, .loop`: nothing is spent.
do
  local save = newSave()
  local hooks = newHooks(save, { vars = { [0x18] = 9 }, answers = { 1, 0 } })
  local vm = newVm(hooks)
  run(vm, H.BuenaPrize, { false })
  eq(save.inventory.ULTRA_BALL, nil, "a refused confirmation buys nothing")
  eq(hooks.vars[0x18], 9, "and spends no points")
  eq(#hooks.log.pushed, 2, "the list reopens once before the B press ends it")
end

-- .InsufficientBalance and .BagFull (engine/events/buena.asm:121-127).
do
  local save = newSave()
  local hooks = newHooks(save, { vars = { [0x18] = 1 }, answers = { 1, 0 } })
  local vm = newVm(hooks)
  local pages = run(vm, H.BuenaPrize, { true })
  eq(save.inventory.ULTRA_BALL, nil, "one point cannot buy a two point ball")
  eq(hooks.vars[0x18], 1, "the balance is untouched")
  check(pages[3] == "You don't have\nenough points.",
    "_BuenaNotEnoughPointsText is the refusal")

  -- ReceiveItem's own refusal: a stack already at 99.
  local full = newSave()
  full.inventory.ULTRA_BALL = 99
  local fullHooks = newHooks(full, { vars = { [0x18] = 9 }, answers = { 1, 0 } })
  local fullVm = newVm(fullHooks)
  local fullPages = run(fullVm, H.BuenaPrize, { true })
  eq(full.inventory.ULTRA_BALL, 99, "a full stack takes no more")
  eq(fullHooks.vars[0x18], 9, "a full bag spends nothing either")
  check(fullPages[3] == "You have no room\nfor it.",
    "_BuenaNoRoomText is that refusal")
end

-- ================================================================ the Seer

local function seerMon(fields)
  local mon = {
    species = "GEODUDE", nickname = "ROCKY", level = 30,
    otId = 0x1234, otName = "KRIS", moves = {},
  }
  for key, value in pairs(fields or {}) do mon[key] = value end
  return mon
end

local function runSeer(mon, cancel)
  local save = newSave()
  save.party = { mon }
  local hooks = newHooks(save, { pickIndex = (not cancel) and 1 or nil })
  local vm = newVm(hooks)
  return run(vm, H.PokeSeer), hooks
end

-- engine/events/poke_seer.asm:38 .cancel, SeerDoNothingText.
do
  local pages = runSeer(seerMon(), true)
  eq(#pages, 2, "the intro and then the refusal")
  eq(pages[2], "Fufufu! I saw that\nyou'd do nothing!", "_SeerDoNothingText")
end

-- engine/events/poke_seer.asm:28-29 `cp EGG / jr z, .egg`.
do
  local pages = runSeer(seerMon({ isEgg = true }))
  eq(pages[2], "Hey!\fThat's an EGG!\fYou can't say that\nyou've met it yet…",
    "_SeerEggText")
end

-- ReadCaughtData's `.error` (engine/events/poke_seer.asm:104-105, :133).
do
  local pages = runSeer(seerMon())
  check(pages[2]:find("Whaaaat", 1, true) ~= nil,
    "a mon with no caught data at all gets _SeerCantTellAThingText")
end

-- SeerAction0 (engine/events/poke_seer.asm:64-70), then SeerAdvice.
do
  local mon = seerMon({ caughtTime = 1, caughtLevel = 10,
    caughtLocation = 1, caughtByGender = "boy" })
  local pages = runSeer(mon)
  eq(pages[2], "Hm… I see you met\nROCKY here:\vNEW BARK TOWN!",
    "_SeerNameLocationText, with the town map's line break spent as a space")
  eq(pages[3], "The time was\nMorning!\fIts level was 10!\fAm I good or what?",
    "_SeerTimeLevelText")
  check(pages[4]:find("more confident", 1, true) ~= nil,
    "a 20 level gain is SeerMoreConfidentText, the 29 row")
end

-- SeerAction1, and engine/events/poke_seer.asm:110-119 where the OT id's
-- second `cp` is commented out, so only the HIGH byte decides.
do
  local traded = seerMon({ otId = 0x9999, otName = "SILVER",
    caughtTime = 3, caughtLevel = 5, caughtLocation = 2 })
  local pages = runSeer(traded)
  eq(pages[2], "Hm… ROCKY\ncame from SILVER\vin a trade?\fROUTE 29\n"
    .. "was where SILVER\vmet ROCKY!", "_SeerTradeText")
  eq(pages[3], "The time was\nNight!\fIts level was 5!\fAm I good or what?",
    "the same time/level page follows")

  local sameHigh = seerMon({ otId = 0x12ff, caughtTime = 2, caughtLevel = 5,
    caughtLocation = 2 })
  local samePages = runSeer(sameHigh)
  check(samePages[2]:find("I see you met", 1, true) ~= nil,
    "an OT id that differs only in its LOW byte reads as met, bug and all")
end

-- GetCaughtLocation's two sentinels (engine/events/poke_seer.asm:239-249).
do
  local event = seerMon({ caughtLevel = 20, caughtLocation = Mon.LANDMARK_EVENT })
  local pages = runSeer(event)
  check(pages[2]:find("What!? Incredible!", 1, true) ~= nil,
    "LANDMARK_EVENT is SEERACTION_LEVEL_ONLY, _SeerNoLocationText")
  check(pages[2]:find("was at level 20", 1, true) ~= nil,
    "which still prints the level")
  check(pages[3] ~= nil, "and still gives the advice page")

  local gift = seerMon({ caughtLevel = 5, caughtLocation = Mon.LANDMARK_GIFT })
  local giftPages = runSeer(gift)
  check(giftPages[2]:find("Whaaaat", 1, true) ~= nil,
    "LANDMARK_GIFT is SEERACTION_CANT_TELL_2, the same refusal")
  eq(#giftPages, 2, "and there is no advice behind it")
end

-- GetCaughtLevel (engine/events/poke_seer.asm:148-179) and GetCaughtTime's
-- .none arm (:198-201).
do
  local unknown = seerMon({ caughtLevel = 0, caughtLocation = 1, caughtTime = 0 })
  -- byte1 is set, so ReadCaughtData's `or [hl]` misses its `.error` arm
  -- (engine/events/poke_seer.asm:105).
  local pages = runSeer(unknown)
  eq(pages[3], "The time was\nUnknown!\fIts level was ???!\fAm I good or what?",
    "no time and no level print Unknown and ???")

  local hatched = seerMon({ caughtLevel = 1, caughtLocation = 1, caughtTime = 2,
    level = 6 })
  local hatchedPages = runSeer(hatched)
  check(hatchedPages[3]:find("level was 5", 1, true) ~= nil,
    "CAUGHT_EGG_LEVEL prints EGG_LEVEL, not 1")
end

-- SeerAdviceTexts (engine/events/poke_seer.asm:357-364), walked in order;
-- `sub c` is one byte, so the 255 row catches an underflow.
do
  local function adviceFor(level, caught)
    local mon = seerMon({ level = level, caughtLevel = caught,
      caughtLocation = 1, caughtTime = 2 })
    return runSeer(mon)[4]
  end
  check(adviceFor(12, 10):find("little more care", 1, true) ~= nil,
    "a 2 level gain is the 9 row")
  check(adviceFor(35, 10):find("more confident", 1, true) ~= nil,
    "25 is the 29 row")
  check(adviceFor(50, 10):find("much strength", 1, true) ~= nil,
    "40 is the 59 row")
  check(adviceFor(70, 10):find("grown mighty", 1, true) ~= nil,
    "60 is the 89 row")
  check(adviceFor(95, 5):find("I'm impressed", 1, true) ~= nil,
    "90 is the 100 row")
  check(adviceFor(5, 10):find("little more care", 1, true) ~= nil,
    "and `sub c` underflowing lands on the 255 row, which repeats the first")
end

-- ================================================ UnusedFindItemInPCOrBag

-- mobile/mobile_12_2.asm:194 wNumPCItems, then :201 wNumItems.
do
  local save = newSave()
  save.pcItems = { RARE_CANDY = 1 }
  local vm = newVm(newHooks(save), 50)
  run(vm, H.UnusedFindItemInPCOrBag)
  eq(vm.scriptVar, 1, "an item in the PC answers TRUE")

  local vm2 = newVm(newHooks(save, { held = { [92] = true } }), 92)
  run(vm2, H.UnusedFindItemInPCOrBag)
  eq(vm2.scriptVar, 1, "an item in the pack answers TRUE too")

  local vm3 = newVm(newHooks(save), 92)
  run(vm3, H.UnusedFindItemInPCOrBag)
  eq(vm3.scriptVar, 0, "and neither is FALSE")
end

-- ==================================================== the seam these ride

do
  for _, name in ipairs({ "MoveTutor", "BuenasPassword", "BuenaPrize",
      "AskRememberPassword", "PokeSeer", "UnusedFindItemInPCOrBag" }) do
    eq(Specials.HANDLER_SOURCE[name], "specials/crystal_extras.lua",
      name .. " is owned by this module")
    eq(Specials.STUBS[name], nil, name .. " is no longer a stub")
    check(Specials.SUPERSEDED_STUBS[name] ~= nil,
      "and its old stub reason was retired")
  end
  local ids = {}
  for _, id in ipairs(require("src.ui.Screens").GEN2_IDS) do ids[id] = true end
  check(ids.Gen2MoveTutor, "Gen2MoveTutor is a registered screen id")
  check(ids.Gen2BuenaPassword, "Gen2BuenaPassword is one too")
end

S.finish()
