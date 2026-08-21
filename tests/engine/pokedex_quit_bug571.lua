-- QUIT on a Pokédex entry closes the whole Pokédex (#571).
-- HandlePokedexSideMenu hands ShowPokedexMenu b=1 for QUIT and b=2 for B
-- (engine/menus/pokedex.asm); only b=2 loops back to .doPokemonListMenu,
-- b=1 falls through to .exitPokedex, which drops the dex and returns to
-- whoever opened it with wBattleAndStartSavedMenuItem intact.  The port
-- popped the side menu and left the list up, so QUIT looked like B.
-- ROM-free: real StateStack and real screens over tests/fixture_data.
--   luajit tests/engine/pokedex_quit_bug571.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local check, eq = T.check, T.eq
local Data = T.fixtures.load()

local SaveData = require("src.core.SaveData")
local Screens = require("src.ui.Screens")
local StateStack = require("src.core.StateStack")

local function newGame()
  local stack = setmetatable({}, { __index = StateStack })
  stack:init()
  local save = SaveData.newGame()
  save.flags = save.flags or {}
  save.flags.EVENT_GOT_POKEDEX = true
  save.pokedex = { seen = { FIXMON_A = true }, owned = { FIXMON_A = true } }
  return {
    data = Data, save = save, stack = stack,
    input = {
      queue = {},
      wasPressed = function(self, btn) return self.queue[btn] or false end,
      isDown = function() return false end,
    },
  }
end

local function press(game, btn)
  local top = game.stack:top()
  while top and (top.inputHold or 0) > 0 do
    game.input.queue = {}
    game.stack:update(1 / 60)
    top = game.stack:top()
  end
  game.input.queue = { [btn] = true }
  game.stack:update(1 / 60)
  game.input.queue = {}
end

-- what the stack is carrying, named the way Screens tags its screens
local function stackIds(game)
  local ids = {}
  for i, state in ipairs(game.stack.states) do
    ids[i] = tostring(state.screenId or "sideMenu")
  end
  return table.concat(ids, " > ")
end

local function openSideMenu(game)
  local start = Screens.push(game, "StartMenu")
  eq(start.items[start.index].label, "POKéDEX",
     "the start menu opens with the cursor on POKéDEX")
  press(game, "a")
  local list = game.stack:top()
  eq(list.screenId, "PokedexMenu", "POKéDEX opens the dex list")
  eq(list.items[list.index].value, "FIXMON_A",
     "the cursor is on a seen species, so A opens the side menu")
  press(game, "a")
  local side = game.stack:top()
  check(side ~= list, "A on the entry pushed the DATA/CRY/AREA/QUIT menu")
  return list, side
end

-- ---------------------------------------------------------------- QUIT
local game = newGame()
local list, side = openSideMenu(game)
-- the start menu popped itself when POKéDEX was chosen (Menu pops before
-- onSelect unless the row is keepOpen), so this is dex list + side menu
eq(#game.stack.states, 2, "dex list and side menu are what is on the stack")
eq(side.items[#side.items].label, "QUIT", "QUIT is the last side-menu row")
side.index = #side.items
press(game, "a")

eq(#game.stack.states, 1,
   "QUIT unwound the side menu and the dex list (" .. stackIds(game) .. ")")
local top = game.stack:top()
eq(top.screenId, "StartMenu", "QUIT lands back on the start menu")
check(top ~= list, "the dex list is not what is left on the stack")
eq(top.items[top.index].label, "POKéDEX",
   "the start menu cursor is still on POKéDEX (wBattleAndStartSavedMenuItem)")

-- ---------------------------------------------------------------- B
-- The control case: B is b=2, which re-shows the list rather than leaving.
-- If QUIT and B ever behave the same again, one of these two fails.
local bGame = newGame()
local bList = select(1, openSideMenu(bGame))
press(bGame, "b")
eq(#bGame.stack.states, 1, "B off the side menu keeps the dex list up")
eq(bGame.stack:top(), bList, "B returns to the dex list, not the start menu")

T.finish("pokedex_quit_bug571")
