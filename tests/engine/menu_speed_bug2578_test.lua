package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local T = require("tests.harness")
local Game = require("src.core.Game")
local Game2 = require("src.core.Game2")
local Game3 = require("src.core.Game3")
local StateStack = require("src.core.StateStack")
local FixedStep = require("src.core.FixedStep")
local Stack3 = require("src.ui.game3.stack")
local battleActive = false
package.loaded["src.core.game3.battle"] = { isActive = function() return battleActive end }

local g = setmetatable({
  save = { party = {}, player = { name = "RED" }, inventory = {},
    flags = {}, pcItems = {}, pokedex = { seen = {}, owned = {} },
    options = { speedOverworld = 4, speedBattle = 10, speedMenu = 2 } },
  data = { pokemon = {}, items = {}, maps = {}, text = dofile("tests/fixture_data/text.lua"), field = {} },
  input = { wasPressed = function() return false end },
}, { __index = Game })
g.stack = setmetatable({}, { __index = StateStack })
g.stack:init()
local overworld, battle = { isOverworld = true }, { isBattle = true }
g.stack:push(overworld)

g.data.pokemon.PIKACHU = { id = "PIKACHU", dex = 25 }
local constructors = {
  StartMenu = {}, PartyMenu = {}, BagMenu = {}, OptionsMenu = {},
  PokedexMenu = {}, TrainerCard = {}, BoxMenu = {}, PlayerPC = {},
  LeaguePC = {}, NamingScreen = {}, FlyMenu = {}, TownMap = {},
  DexEntryMenu = { "PIKACHU" }, SummaryMenu = { { species = "PIKACHU", moves = {} } },
  PrizeCounter = { {} },
}
for name, args in pairs(constructors) do
  local screen = require("src.ui." .. name).new(g, unpack(args))
  T.eq(screen.isMenu, true, name .. " returned instance is a menu owner")
  g.stack:push(screen)
  T.eq(g:logicSpeed(), 2, name .. " uses MENU SPEED over the overworld")
  g.stack:push({})
  T.eq(g:logicSpeed(), 2, name .. " nested dialogue inherits MENU SPEED")
  g.stack:pop()
  g.stack:pop()
  T.eq(g:logicSpeed(), 4, name .. " pop restores OVERWORLD SPEED")
end

local shop = require("src.ui.ShopMenu").new(g, {})
T.eq(shop.isMenu, true, "ShopMenu actual returned generic instance owns MENU SPEED")
T.eq(Game.speedCategoryInStack({ states = { overworld, shop, {} } }), "menu",
  "shop greetings and nested item lists inherit the concrete menu owner")

local Menu = require("src.ui.Menu")
local OW = require("src.world.OverworldController")
local owGameIndex, owGame
for i = 1, 100 do
  local name, value = debug.getupvalue(OW.openPC, i)
  if not name then break end
  if name == "Game" then owGameIndex, owGame = i, value; break end
end
assert(owGameIndex, "openPC Game binding absent")
debug.setupvalue(OW.openPC, owGameIndex, g)
local baseInput, pressed = g.input, nil
g.input = { wasPressed = function(_, key) return pressed == key end,
  isDown = function() return false end }
local function tap(screen, key)
  pressed = key
  screen:update(1 / 60)
  pressed = nil
end
local function advanceToMenu()
  for _ = 1, 600 do
    local top = g.stack:top()
    if getmetatable(top) == Menu then return top end
    tap(top, "a")
  end
  error("actual interactive PC menu was not reached")
end

OW:openPC()
T.eq(g:logicSpeed(), 4, "PC opening text retains OVERWORLD SPEED")
local pc = advanceToMenu()
T.eq(#pc.items >= 3 and pc.noSound, true, "actual main PC chooser is reached")
T.eq(pc.isMenu, true, "main PC chooser concrete instance owns MENU SPEED")
T.eq(Game.speedCategoryInStack(g.stack), "menu", "main PC chooser category is menu")
T.eq(g:logicSpeed(), 2, "actual main PC chooser uses MENU SPEED")
pc.index = 2
tap(pc, "a")
T.eq(g.stack:top().isTextBox, true, "main PC chooser opens actual player PC access text")
T.eq(g:logicSpeed(), 2, "player PC access text inherits MENU SPEED")
local playerPC = advanceToMenu()
T.eq(playerPC ~= pc and #playerPC.items == 4, true, "actual player PC submenu is reached")
T.eq(g:logicSpeed(), 2, "player PC submenu uses MENU SPEED")
tap(playerPC, "b")
T.eq(g.stack:top(), pc, "player PC back returns the same main chooser")
T.eq(g:logicSpeed(), 2, "returned main PC chooser retains MENU SPEED")
tap(pc, "b")
T.eq(g.stack:top(), overworld, "main PC cancel returns to field")
T.eq(g:logicSpeed(), 4, "main PC cancel restores OVERWORLD SPEED")

for i, id in ipairs({ "EEVEE", "FLAREON", "JOLTEON", "VAPOREON" }) do
  g.data.pokemon[id] = { id = id, name = id, dex = 132 + i }
end
g.data.text._BillsHousePokemonListText2 = "Which POKéMON do\nyou want to see?{DONE}"
OW:billsHousePokemonList()
T.eq(g:logicSpeed(), 4, "Bill viewer opening text retains OVERWORLD SPEED")
local bill = advanceToMenu()
T.eq(#bill.items == 5 and bill.items[1].keepOpen, true, "actual Bill PC viewer list is reached")
T.eq(bill.isMenu, true, "Bill PC viewer concrete instance owns MENU SPEED")
T.eq(Game.speedCategoryInStack(g.stack), "menu", "Bill PC viewer category is menu")
T.eq(g:logicSpeed(), 2, "actual Bill PC viewer uses MENU SPEED")
tap(bill, "a")
T.eq(getmetatable(g.stack:top()), require("src.ui.DexEntryMenu"),
  "Bill viewer selection opens the actual DexEntryMenu")
T.eq(g.save.pokedex.seen.EEVEE, true, "Bill viewer preserves the selected species seen flag")
T.eq(g:logicSpeed(), 2, "Bill viewer nested DexEntryMenu uses MENU SPEED")
for _ = 1, 600 do
  if g.stack:top() == bill then break end
  tap(g.stack:top(), "b")
end
T.eq(g.stack:top(), bill, "DexEntryMenu back returns the same Bill viewer")
T.eq(g:logicSpeed(), 2, "returned Bill PC viewer retains MENU SPEED")
tap(bill, "b")
T.eq(g.stack:top(), overworld, "Bill viewer cancel returns to field")
T.eq(g:logicSpeed(), 4, "Bill viewer cancel restores OVERWORLD SPEED")

g.input = baseInput
debug.setupvalue(OW.openPC, owGameIndex, owGame)
local generic = Menu.new(g, { { label = "CHOICE" } })
T.eq(generic.isMenu, nil, "generic Menu remains transparent")
g.stack:push(generic)
T.eq(g:logicSpeed(), 4, "unowned generic choice retains OVERWORLD SPEED")
g.stack:pop()

for _, name in ipairs({ "PartyMenu", "BagMenu" }) do
  g.stack:push(battle)
  local screen = require("src.ui." .. name).new(g, { battle = { playerParty = {} } })
  g.stack:push(screen)
  T.eq(g:logicSpeed(), 2, "battle " .. name .. " uses MENU SPEED")
  g.stack:pop()
  T.eq(g:logicSpeed(), 10, "battle " .. name .. " pop restores BATTLE SPEED")
  g.stack:push({})
  T.eq(g:logicSpeed(), 10, "battle dialogue stays at BATTLE SPEED")
  g.stack:pop()
  g.stack:pop()
end

local party = require("src.ui.PartyMenu").new(g)
g.stack:push(party)
local function ticks(speed)
  g.save.options.speedMenu = speed
  party.blink = 0
  FixedStep.clock = function() return 0 end
  FixedStep.refreshPeriod = nil
  FixedStep:init(function(dt) party:update(dt) end)
  local multiplier = g:logicSpeed()
  FixedStep.maxAccum = FixedStep.catchupLimit(multiplier, 1 / 60)
  for _ = 1, 60 do FixedStep:update(1 / 60, multiplier) end
  return party.blink
end
T.eq(ticks(1), 60, "real party advances 60 logic ticks per second at MENU SPEED 1")
T.eq(ticks(4), 240, "real party advances 240 logic ticks per second at MENU SPEED 4")
g.speedOverride = 20
T.eq(g:logicSpeed(), 20, "run override still wins over a menu")
g.linkSession = true
T.eq(g:logicSpeed(), 1, "link lock still wins over menu and override")
g.linkSession = nil
g.stack:push({ isFixedSpeed = true })
T.eq(g:logicSpeed(), 1, "minigame lock still wins over menu and override")
g.stack:pop()
g.stack:pop()

local g3 = setmetatable({ phase = "field",
  options = { speedOverworld = 4, speedBattle = 10, speedMenu = 2 } }, { __index = Game3 })
Stack3.clear()
for _, name in ipairs({ "start_menu", "party_menu", "bag_menu", "option_menu", "pokedex",
    "trainer_card", "summary_menu", "box_storage_ui", "pc_menu", "item_pc",
    "hall_of_fame_pc", "naming", "region_map", "tm_case", "berry_pouch", "save_menu",
    "fame_checker", "controls_menu", "mod_manager", "rse.option_menu", "rse.item_storage",
    "rse.mailbox", "shop_menu", "daycare_menu", "prize_corner", "move_relearner", "easy_chat",
    "rse.move_relearner", "rse.pokeblock_case", "rse.berry_tag", "rse.frontier_pass", "rse.pyramid_bag" }) do
  local mod = require("src.ui.game3." .. name)
  Stack3.push(name, mod, { fullscreen = false })
  T.eq(g3:speedCategory(), "menu", name .. " owns the actual non-fullscreen layer")
  T.eq(g3:logicSpeed(), 2, name .. " uses MENU SPEED")
  Stack3.push("dialogue", {}, { fullscreen = true })
  T.eq(g3:logicSpeed(), 2, name .. " nested text inherits menu speed")
  Stack3.pop("dialogue")
  Stack3.pop(name)
  T.eq(g3:logicSpeed(), 4, name .. " pop restores field speed")
end
for _, name in ipairs({ "pokedex", "region_map", "pokenav.init" }) do
  local mod = require("src.ui.game3.rse." .. name).Host
  Stack3.push(name, mod)
  T.eq(g3:logicSpeed(), 2, "RSE " .. name .. " actual delegated Host owns MENU SPEED")
  Stack3.pop(name)
end
for _, name in ipairs({ "party_menu", "bag_menu" }) do
  battleActive = true
  Stack3.push(name, require("src.ui.game3." .. name), { fullscreen = false })
  T.eq(g3:logicSpeed(), 2, "Gen3 battle " .. name .. " uses MENU SPEED")
  Stack3.pop(name)
  T.eq(g3:logicSpeed(), 10, "Gen3 battle " .. name .. " pop restores BATTLE SPEED")
end
Stack3.push("battle_message", {}, { fullscreen = true })
T.eq(g3:logicSpeed(), 10, "Gen3 unmarked fullscreen battle text stays at BATTLE SPEED")
Stack3.clear()
battleActive = false
Stack3.push("scene", {}, { fullscreen = true })
T.eq(g3:logicSpeed(), 4, "Gen3 unmarked field scene stays at OVERWORLD SPEED")
Stack3.clear()
Stack3.push("party", require("src.ui.game3.party_menu"))
g3.speedOverride = 20
T.eq(g3:logicSpeed(), 20, "Gen3 run override wins over menu")
package.loaded["src.core.game3.link"] = { link = {} }
T.eq(g3:logicSpeed(), 1, "Gen3 link lock wins over menu and override")
package.loaded["src.core.game3.link"] = nil
package.loaded["src.core.game3.minigames.common"] = { isActive = function() return true end }
T.eq(g3:logicSpeed(), 1, "Gen3 minigame lock wins over menu and override")
package.loaded["src.core.game3.minigames.common"] = nil
Stack3.clear()

local g2 = setmetatable({ options = { speed = 4, speedOverworld = 1, speedMenu = 10 } }, { __index = Game2 })
T.eq(g2:logicSpeed(), 4, "Gen2 retains legacy GAME SPEED")
T.finish("menu speed bug 2578")
