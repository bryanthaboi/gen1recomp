-- Per-category GAME SPEED (RFC 0007): Game.speedCategoryInStack's stack
-- walk, Game:logicSpeed()'s precedence (link lock / run-argument override /
-- the core.logic_speed hook), Game:_cycleSpeed's per-category cycling, and
-- the core.logic_speed hook itself exercised through the public mod API
-- (Hooks.new() + bus:wrap, the same idiom other hooks' tests use -- not a
-- private require).
--   luajit tests/engine/game_speed_categories_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local check, eq = T.check, T.eq

local Game = require("src.core.Game")
local GameSpeed = require("src.core.GameSpeed")
local Hooks = require("src.mods.Hooks")
local Runtime = require("src.mods.Runtime")

-- ------- Game.speedCategoryInStack: the whole-stack walk

local function stack(...) return { states = { ... } } end

local battle = { isBattle = true }
local overworld = { isOverworld = true }
local overlay = {} -- a party menu/choice box/naming screen/text box: no marker

eq(Game.speedCategoryInStack(nil), "menu", "a nil stack falls to menu")
eq(Game.speedCategoryInStack(stack()), "menu", "an empty stack falls to menu")
eq(Game.speedCategoryInStack(stack(overlay)), "menu",
  "an unmarked state alone (title screen, credits, a standalone cutscene) is menu")

eq(Game.speedCategoryInStack(stack(overworld)), "overworld",
  "the overworld alone resolves to overworld")
eq(Game.speedCategoryInStack(stack(battle)), "battle",
  "a battle alone resolves to battle")

eq(Game.speedCategoryInStack(stack(overworld, overlay)), "overworld",
  "a menu opened while walking inherits overworld")
eq(Game.speedCategoryInStack(stack(battle, overlay)), "battle",
  "a menu opened mid-battle inherits battle, not menu")
eq(Game.speedCategoryInStack(stack(overworld, overlay, overlay)), "overworld",
  "the inheritance walk sees through more than one stacked overlay")

eq(Game.speedCategoryInStack(stack(overworld, battle)), "battle",
  "a battle opened over the overworld reads as battle, not the overworld underneath it")
eq(Game.speedCategoryInStack(stack(overworld, battle, overlay)), "battle",
  "and a menu on top of THAT still reads as battle")

-- ------- Game:_resolveLogicSpeed: category -> save.options key -> clamp

local unpack = table.unpack or unpack

local function gameWith(states, options)
  return setmetatable({
    save = { options = options },
    stack = stack(unpack(states or {})),
  }, { __index = Game })
end

do
  local g = gameWith({ overworld },
    { speedOverworld = 4, speedBattle = 10, speedMenu = 2 })
  eq(g:_resolveLogicSpeed(), 4, "overworld reads speedOverworld")
end
do
  local g = gameWith({ battle },
    { speedOverworld = 4, speedBattle = 10, speedMenu = 2 })
  eq(g:_resolveLogicSpeed(), 10, "battle reads speedBattle")
end
do
  local g = gameWith({ overlay },
    { speedOverworld = 4, speedBattle = 10, speedMenu = 2 })
  eq(g:_resolveLogicSpeed(), 2, "menu reads speedMenu")
end
do
  local g = gameWith({ overworld }, { speedOverworld = 7 })
  eq(g:_resolveLogicSpeed(), GameSpeed.clamp(7),
    "an odd value clamps to the nearest LEVELS entry, like the old single field")
end
do
  local g = gameWith({ overworld }, nil)
  eq(g:_resolveLogicSpeed(), GameSpeed.DEFAULT,
    "no save.options at all defaults rather than erroring")
end

-- ------- Game:logicSpeed(): link and speedOverride win over every category
-- and over a hook override; the hook only ever sees the ordinary case

do
  local g = gameWith({ battle }, { speedBattle = 50 })
  g.linkSession = true
  eq(g:logicSpeed(), 1, "an active link session forces 1X even at 50X battle")
end
do
  local g = gameWith({ battle }, { speedBattle = 50 })
  g.linkNet = { closed = false }
  eq(g:logicSpeed(), 1, "an open linkNet forces 1X the same way")
end
do
  local g = gameWith({ battle }, { speedBattle = 50 })
  g.linkNet = { closed = true }
  eq(g:logicSpeed(), 50, "a CLOSED linkNet does not force 1X")
end
do
  local g = gameWith({ overworld }, { speedOverworld = 4 })
  g.speedOverride = 20
  eq(g:logicSpeed(), 20,
    "speedOverride (--speed/POKEPORT_SPEED) wins over the category option")
end
do
  local g = gameWith({ battle }, { speedBattle = 50 })
  g.linkSession = true
  local bus = Hooks.new()
  local savedHooks = Runtime.hooks
  Runtime.hooks = bus
  local hookRan = false
  local unsub = bus:wrap("core.logic_speed", function(next, game)
    hookRan = true
    return 999
  end)
  eq(g:logicSpeed(), 1,
    "the link lock wins even over a mod's core.logic_speed override")
  check(not hookRan, "...because the hook is never called during link play")
  unsub()
  Runtime.hooks = savedHooks
end

-- ------- core.logic_speed: the mod-API seam, driven through Runtime.call/
-- Hooks.new + bus:wrap like every other hook's public-API test

local function callLogicSpeed(g)
  return Runtime.call("core.logic_speed",
    function(gg) return gg:_resolveLogicSpeed() end, g)
end

do
  local g = gameWith({ battle }, { speedBattle = 4 })
  eq(callLogicSpeed(g), 4,
    "with no subscriber, the hook returns the vanilla category resolution")
end

do
  local g = gameWith({ overworld }, { speedOverworld = 4 })
  local bus = Hooks.new()
  local savedHooks = Runtime.hooks
  Runtime.hooks = bus

  local nextArg = nil
  local unsub = bus:wrap("core.logic_speed", function(next, game)
    nextArg = next(game)
    return nextArg
  end)
  eq(callLogicSpeed(g), 4,
    "a subscriber calling next(game) passes the vanilla value through")
  eq(nextArg, 4, "...and next(game) itself returned the vanilla resolution")
  unsub()

  -- a bot mod forcing 1X for one route segment regardless of the category
  unsub = bus:wrap("core.logic_speed", function(next, game) return 1 end)
  eq(callLogicSpeed(g), 1,
    "a subscriber may override the resolved multiplier outright")
  unsub()

  Runtime.hooks = savedHooks
end

-- ------- Game:_cycleSpeed: cycles whichever category is active, and only it

do
  local writeOptions = { calls = 0 }
  local g = gameWith({ battle },
    { speedOverworld = 1, speedBattle = 1, speedMenu = 1 })
  function g:writeOptions() writeOptions.calls = writeOptions.calls + 1 end
  g:_cycleSpeed(1)
  eq(g.save.options.speedBattle, 2, "cycling during battle bumps speedBattle")
  eq(g.save.options.speedOverworld, 1, "...and leaves speedOverworld alone")
  eq(g.save.options.speedMenu, 1, "...and leaves speedMenu alone")
  eq(writeOptions.calls, 1, "a successful cycle persists the option")
end
do
  local g = gameWith({ overworld },
    { speedOverworld = 1, speedBattle = 1, speedMenu = 1 })
  function g:writeOptions() end
  g:_cycleSpeed(1)
  eq(g.save.options.speedOverworld, 2, "cycling on the overworld bumps speedOverworld")
  eq(g.save.options.speedBattle, 1, "...and leaves speedBattle alone")
end
do
  local g = gameWith({ overlay },
    { speedOverworld = 1, speedBattle = 1, speedMenu = 1 })
  function g:writeOptions() end
  g:_cycleSpeed(1)
  eq(g.save.options.speedMenu, 2, "cycling in a menu bumps speedMenu")
end

-- A cart may narrow the ladder (CartManifest's `speeds`), and returning to
-- the launcher must put it back.
do
  local GameSpeed = require("src.core.GameSpeed")
  eq(#GameSpeed.allowed(), #GameSpeed.LEVELS, "no cart means the full ladder")
  check(not GameSpeed.isLocked(), "and nothing is pinned")

  GameSpeed.setAllowed({ 1, 2 })
  eq(#GameSpeed.allowed(), 2, "a cart narrows the ladder")
  eq(GameSpeed.cycle(1, 1), 2, "cycling stays inside the cart's levels")
  eq(GameSpeed.cycle(2, 1), 1, "and wraps within them")
  eq(GameSpeed.clamp(100), 2, "a value past the cart's top clamps into it")
  check(not GameSpeed.isLocked(), "two levels is narrowed, not pinned")

  GameSpeed.setAllowed({ 1 })
  check(GameSpeed.isLocked(), "one level reads as pinned")
  eq(GameSpeed.cycle(1, 1), 1, "and cycling cannot leave it")

  GameSpeed.setAllowed({ 1, 7 })
  eq(#GameSpeed.allowed(), 1, "a level that is not on the ladder is dropped")

  GameSpeed.setAllowed(nil)
  eq(#GameSpeed.allowed(), #GameSpeed.LEVELS,
    "leaving the cart restores the full ladder")
  eq(GameSpeed.cycle(4, 1), 10, "and cycling reaches the levels again")
end

T.finish("game_speed_categories")
