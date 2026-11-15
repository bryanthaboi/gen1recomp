package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Profile = require("src.core.game3.profile")
Profile.reset()
GameVersion.set("emerald")

require("tests.game3_cache").mount("emerald")
local Dataset = require("src.core.game3.dataset")
local cache = Dataset.cache()
local function loadRel(rel)
  local src = cache and cache.read and cache:read("data/generated/gba/" .. rel)
  if type(src) ~= "string" then return nil end
  local chunk = load(src, "@" .. rel, "t", {})
  return chunk and chunk() or nil
end

local manifest = loadRel("pokemon/battle/manifest.lua")
if not (manifest and manifest.layout == "rse") then
  print("emerald_battle_rules_test: skipped (no Emerald cache; set POKEPORT_IDENTITY)")
  os.exit(0)
end

local Versions = require("src.import.gba.versions")
Versions.select("emerald")
local C = require("src.core.game3.constants").of("emerald")
local BattleProfile = require("src.core.game3.battle.profile")
local bp = BattleProfile.get({ version = "emerald" })
local BattleEngine = require("src.core.game3.battle.engine")
local frontierRun = { wild = false, player = {}, kinds = { frontier = true } }
local hillRun = { wild = false, player = {}, kinds = { trainerHill = true } }
local ordinaryTrainerRun = { wild = false, player = {}, kinds = {} }
eq(BattleEngine.canRun(frontierRun, {}), true, "Frontier trainer can select RUN to forfeit")
eq(BattleEngine.canRun(hillRun, {}), true, "Trainer Hill trainer can select RUN to forfeit")
local ordinaryRun, ordinaryWhy = BattleEngine.canRun(ordinaryTrainerRun, {})
eq(ordinaryRun, false, "ordinary trainer still cannot run")
check(ordinaryWhy ~= nil, "ordinary trainer refusal retains its message")

local Prize = require("src.core.game3.battle.prize")
local data = Prize.rseData()
eq(#data.pickupItems, 18, "sPickupItems has 18 rows (battle_script_commands.c:784)")
eq(#data.rarePickupItems, 11, "sRarePickupItems has 11 rows")
eq(#data.pickupProbabilities, 9, "sPickupProbabilities has 9 rows")
eq(Prize.pickupBanded(1, 0), C.items.byName.ITEM_POTION, "lv1 rand 0 -> Potion")
eq(Prize.pickupBanded(1, 30), C.items.byName.ITEM_ANTIDOTE, "lv1 rand 30 -> Antidote")
eq(Prize.pickupBanded(1, 99), C.items.byName.ITEM_HYPER_POTION, "lv1 rand 99 -> Hyper Potion")
eq(Prize.pickupBanded(1, 98), C.items.byName.ITEM_NUGGET, "lv1 rand 98 -> Nugget")
eq(Prize.pickupBanded(100, 97), C.items.byName.ITEM_MAX_ELIXIR, "lv100 rand 97 -> Max Elixir")
local pikeParty = { { species = C.species.byName.SPECIES_MEOWTH, level = 10, abilityId = Prize.ABILITY_PICKUP } }
local pickupRolls = 0
local suppressed = Prize.pickup(pikeParty, function() pickupRolls = pickupRolls + 1; return 0 end,
  { pickup = "level_bands", noPickup = true })
eq(#suppressed, 0, "Pike rule suppresses Pickup result")
eq(pickupRolls, 0, "Pike suppression consumes no random values")
eq(pikeParty[1].item, nil, "Pike suppression does not alter held item")
local Pyramid = require("src.core.game3.rse.frontier.pyramid")
local Rng = require("src.core.game3.rng")
local savedRandom = Rng.Random
Rng.Random = function() return 0 end
local pyramidSession = { version = "emerald", map = Pyramid.FLOOR_MAP, frontier = {} }
local pyramidItem = Pyramid.pickupItemId(pyramidSession)
local pyramidParty = { { species = C.species.byName.SPECIES_MEOWTH, level = 50,
  abilityId = Prize.ABILITY_PICKUP } }
local pyramidPicked = Prize.pickup(pyramidParty, function() return 0 end,
  { pickup = "level_bands", pyramidSession = pyramidSession })
Rng.Random = savedRandom
eq(#pyramidPicked, 1, "Pyramid Pickup grants one floor-table item")
eq(pyramidParty[1].item, pyramidItem, "Pyramid Pickup uses GetBattlePyramidPickupItemId's table")

local Pike = require("src.core.game3.rse.frontier.pike")
local Game3 = require("src.core.Game3")
local Bag = require("src.core.game3.bag")
local ItemUse = require("src.core.game3.item_use")
local registeredBag = Bag.new()
local registeredItem = C.items.byName.ITEM_MACH_BIKE
Bag.add(registeredBag, registeredItem, 1)
local registeredSession = { version = "emerald", map = Pike.WILD_ROOM, bag = registeredBag,
  registeredItem = registeredItem }
local oldUseField, registeredUses = ItemUse.useField, 0
ItemUse.useField = function() registeredUses = registeredUses + 1; return true, "bike" end
Game3._handleRegisteredItem({ session = registeredSession, input = {
  wasPressed = function(_, key) return key == "select" end,
} })
ItemUse.useField = oldUseField
eq(registeredUses, 0, "SELECT registered-item use is blocked in the Battle Pike")
eq(registeredSession.registeredItem, registeredItem, "blocked Pike use keeps its registration")
registeredSession.map = Pyramid.FLOOR_MAP
Game3._handleRegisteredItem({ session = registeredSession, input = {
  wasPressed = function(_, key) return key == "select" end,
} })
eq(registeredUses, 0, "SELECT registered-item use is blocked in the Battle Pyramid")

local PartyMenu = require("src.ui.game3.party_menu")
local function pressed(key)
  return { wasPressed = function(_, button) return button == key end }
end
local function twoMons()
  return { { species = C.species.byName.SPECIES_MEOWTH, level = 10, moves = {} },
    { species = C.species.byName.SPECIES_MEOWTH, level = 10, moves = {} } }
end
registeredSession.map = Pike.WILD_ROOM
PartyMenu.show(twoMons(), {
  session = registeredSession,
})
PartyMenu.handleInput(pressed("a"))
local pikeActions = table.concat(PartyMenu.ACTIONS, ",")
eq(pikeActions:find("SWITCH", 1, true), nil, "Battle Pike party menu omits SWITCH")
eq(pikeActions:find("ITEM", 1, true), nil, "Battle Pike party menu omits ITEM and MAIL")
PartyMenu.close()
registeredSession.map = "EM_ROUTE101"
PartyMenu.show(twoMons(), {
  session = registeredSession,
})
PartyMenu.handleInput(pressed("a"))
local fieldActions = table.concat(PartyMenu.ACTIONS, ",")
eq(fieldActions:find("SWITCH", 1, true) ~= nil, true, "ordinary field party menu keeps SWITCH")
eq(fieldActions:find("ITEM", 1, true) ~= nil, true, "ordinary field party menu keeps ITEM")
PartyMenu.close()
registeredSession.map = Pyramid.FLOOR_MAP

local BattleUi = require("src.core.game3.battle.ui")
local PyramidBag = require("src.ui.game3.rse.pyramid_bag")
local realPyramidBagShow, pyramidBagOpts = PyramidBag.show, nil
PyramidBag.show = function(opts) pyramidBagOpts = opts; return true end
BattleUi._session, BattleUi._st, BattleUi._mode = registeredSession, { link = false }, "command"
BattleUi.openBattleBag()
PyramidBag.show = realPyramidBagShow
eq(pyramidBagOpts and pyramidBagOpts.location, "battle", "Pyramid battle BAG opens its dedicated battle inventory")
eq(pyramidBagOpts and pyramidBagOpts.session, registeredSession, "Pyramid battle BAG uses the active challenge state")
BattleUi._session, BattleUi._st, BattleUi._mode = nil, nil, "none"

local Bag = require("src.core.game3.bag")
local BagMenu = require("src.ui.game3.bag_menu")
local Battle = require("src.core.game3.battle")
local State = require("src.core.game3.battle.state")
local Screens = require("src.ui.game3.screens")

local testBag = Bag.new()
Bag.add(testBag, C.items.byName.ITEM_POTION, 2)
local testParty = {
  { species = C.species.byName.SPECIES_TREECKO, hp = 10, maxHp = 20, moves = {} },
  { species = C.species.byName.SPECIES_TORCHIC, hp = 5, maxHp = 20, moves = {} },
}
local testSession = { bag = testBag, party = testParty }
local bst = {
  wild = true,
  turn = 1,
  player = State.makeBattler(testParty[1], "player", { partyIndex = 1 }),
  playerParty = testParty,
}
Battle._active = true
Battle._phase = "command"
Battle._st = bst
Battle._auto = false
BattleUi._session = testSession
BattleUi._st = bst
BattleUi._mode = "command"

BattleUi.openBattleBag()
eq(BagMenu.isOpen(), true, "Emerald battle BagMenu is open")
BagMenu.settle()
Screens.handleInput("bag", BagMenu, pressed("a"), testSession)
eq(BagMenu.mode, "action", "BagMenu mode is action")
Screens.handleInput("bag", BagMenu, pressed("a"), testSession)
eq(PartyMenu.isOpen(), true, "PartyMenu is open for in-battle item use")
eq(PartyMenu.mode, "use", "PartyMenu is in use mode")
eq(PartyMenu.cursor, 1, "PartyMenu initially selects slot 1")

Battle.update(0, { input = pressed("down") })
eq(PartyMenu.cursor, 2, "PartyMenu cursor moves to slot 2 in Emerald battle (not stuck on active mon)")

Battle.update(0, { input = pressed("a") })
-- Press A to fast-forward HP animation and advance message
PartyMenu.handleInput(pressed("a"))
eq(PartyMenu.mode, "message", "PartyMenu displays recovery message")
PartyMenu.handleInput(pressed("a"))
eq(PartyMenu.isOpen(), false, "PartyMenu closes after message dismissal")
BagMenu.settle()
eq(BagMenu.isOpen(), false, "BagMenu closes after committing battle item")
eq(BattleUi._pendingCommand and BattleUi._pendingCommand.partySlot, 2, "Pending battle command targets slot 2")

Battle._active = false
BattleUi._session, BattleUi._st, BattleUi._mode = nil, nil, "none"

-- Also test cancelling back from PartyMenu to BagMenu
Battle._active = true
Battle._phase = "command"
Battle._st = bst
BattleUi._session = testSession
BattleUi._st = bst
BattleUi._mode = "command"
BattleUi.openBattleBag()
BagMenu.settle()
Screens.handleInput("bag", BagMenu, pressed("a"), testSession)
Screens.handleInput("bag", BagMenu, pressed("a"), testSession)
eq(PartyMenu.isOpen(), true, "PartyMenu reopened for item use")
Battle.update(0, { input = pressed("b") })
eq(PartyMenu.isOpen(), false, "PartyMenu closed on B press")
eq(BagMenu.isOpen(), true, "BagMenu remains open after PartyMenu cancel")
eq(BagMenu.mode, "list", "BagMenu returned to list mode")
Screens.handleInput("bag", BagMenu, pressed("b"), testSession)
BagMenu.settle()
eq(BagMenu.isOpen(), false, "BagMenu closed on B press")
Battle._active = false
BattleUi._session, BattleUi._st, BattleUi._mode = nil, nil, "none"

local Trainers = require("src.core.game3.scripting.trainers")
local calvin = C.trainers.byName.TRAINER_CALVIN_1
local row = Trainers.get(calvin)
check(row ~= nil, "Calvin row exists")
local pack = Trainers.pack()
local value = pack.money[row.class] or pack.moneyDefault
local last = row.party[#row.party].level
eq(Prize.calcRse(calvin, {}), 4 * last * value, "Calvin prize money from gTrainerMoneyTable")
print(string.format("[info] Calvin class %d value %d last lv %d -> %d", row.class, value, last, Prize.calcRse(calvin, {})))

local RomText = require("src.core.game3.rom_text")
for _, key in ipairs({ bp.firstBattle.cantRun, "STRINGID_PLAYERWHITEOUT", "STRINGID_PLAYERWHITEOUT2",
    "STRINGID_PLAYERGOTMONEY", "STRINGID_WILDPKMNFLED", "STRINGID_PKMNGAINEDEXP", "gText_BattleWallyName" }) do
  check(RomText.has(key), "Emerald text has " .. key)
end
check(RomText.plain(bp.firstBattle.cantRun):find("Don't leave me") ~= nil, "DONTLEAVEBIRCH reads Birch's line")

local Ai = require("src.core.game3.battle.ai")
local aiPack = Ai.loadPack({ force = true, required = true })
eq(#aiPack.table, 32, "gBattleAI_ScriptsTable has 32 scripts")
local fb = aiPack.scripts[aiPack.table[32]]
check(fb ~= nil and fb[1].op == "if_hp_equal", "AI_FirstBattle is script 31 (battle_ai_scripts.s:3233)")
local AiCmds = require("src.core.game3.battle.ai_cmds")
local seen = {}
for _, body in pairs(aiPack.scripts) do
  for _, op in ipairs(body) do seen[op.op] = true end
end
for name in pairs(seen) do
  check(AiCmds.CMD[name] ~= nil or name == "end" or name == "goto" or name == "call_if_always_hit"
    or name:find("^nop") ~= nil, "AI op " .. name .. " has a handler")
end

local Anim = require("src.core.game3.battle.anim")
Anim._packLoaded, Anim._pack = false, nil
local reads = {}
local realRead = cache.read
cache.read = function(self, rel)
  reads[#reads + 1] = rel
  return realRead(self, rel)
end
local animPack = Anim.tableScript and select(2, pcall(function() return Anim.tableIndex("general", "POKEBLOCK_THROW") end))
cache.read = realRead
eq(animPack, 4, "general anim 4 is POKEBLOCK_THROW on Emerald")
local fromFr = false
for _, rel in ipairs(reads) do
  if rel:find("^firered/") then fromFr = true end
end
check(not fromFr, "Emerald anim pack load never reads firered/ paths")
eq(Anim.tableIndex("general", "BAIT_THROW"), nil, "Emerald has no BAIT_THROW general anim")
local AnimTasks = require("src.core.game3.battle.anim_tasks")
AnimTasks.init()
check(AnimTasks.REGISTRY.IsBallBlockedByTrainer ~= nil, "IsBallBlockedByTrainer is registered")

GameVersion.set("firered")
T.finish()
