-- The battle main menu's 2x2 cursor clamps at every edge instead of wrapping
-- to the opposite command (#1706).  BattleMenuHeader's .MenuData flag byte is
-- `db STATICMENU_CURSOR | STATICMENU_DISABLE_B` (engine/battle/menu.asm:31-33)
-- with no STATICMENU_WRAP, so Init2DMenuCursorPosition leaves both wrap bits
-- clear (engine/menus/menu.asm:156-166) and _2DMenuInterpretJoypad's
-- .check_wrap_around_* arms answer `xor a / ret`: the cursor does not move.
-- ContestBattleMenuHeader (menu.asm:70-77) is the same grid, same flag byte.
--
--   luajit tests/gen2_battle_cursor_test.lua
--
-- ROM-free: the fixtures below are the extractor's shapes, and every press
-- goes through the real Input edge detector and the real screen.

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 battle cursor")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local Battle = require("src.battle.gen2.Battle")
local BattleState = require("src.ui.gen2.BattleState")
local Input = require("src.core.Input")
local Mon = require("src.battle.gen2.Mon")

-- ---------------------------------------------------------------- fixtures

local TYPES = { NORMAL = { id = "NORMAL", index = 0, category = "physical" } }

local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 95, pp = 35, effect = "EFFECT_NORMAL_HIT" },
}

local GROWTH = {
  GROWTH_MEDIUM_FAST = { numerator = 1, denominator = 1, squared = 0,
    linear = 0, constant = 0 },
}

local POKEMON = {
  growthRates = GROWTH,
  CYNDAQUIL = {
    id = "CYNDAQUIL", index = 155, name = "CYNDAQUIL",
    baseStats = { hp = 39, attack = 52, defense = 43, speed = 65,
      specialAttack = 60, specialDefense = 50 },
    types = { "NORMAL", "NORMAL" }, catchRate = 45, baseExp = 65,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 31,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
  PIDGEY = {
    id = "PIDGEY", index = 16, name = "PIDGEY",
    baseStats = { hp = 40, attack = 45, defense = 40, speed = 56,
      specialAttack = 35, specialDefense = 35 },
    types = { "NORMAL", "NORMAL" }, catchRate = 255, baseExp = 55,
    growthRate = "GROWTH_MEDIUM_FAST", genderRatio = 127,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
}

local DATA = {
  pokemon = POKEMON,
  moves = MOVES,
  type_chart = { types = TYPES, matchups = {} },
  items = {},
}

local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
perfect.hp = Mon.hpDV(perfect)

-- The smallest roll that neither crits nor misses.
local function detRandom(n)
  if (n or 1) <= 1 then return 0 end
  return 1
end

local function newScreen(opts)
  opts = opts or {}
  Input:init()
  local player = Mon.new(DATA, "CYNDAQUIL", 10, { dvs = perfect })
  player.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local wild = Mon.new(DATA, "PIDGEY", 5, { dvs = perfect })
  wild.moves = { { id = "TACKLE", pp = 35, maxPp = 35 } }
  local save = { party = { player }, inventory = {}, player = { name = "GOLD" } }
  local pushed = {}
  local game = {
    data = DATA, save = save, input = Input, options = {},
    stack = {
      push = function(_, screen) pushed[#pushed + 1] = screen end,
      pop = function() table.remove(pushed) end,
      top = function() return pushed[#pushed] end,
      clear = function(self) while #pushed > 0 do self:pop() end end,
    },
  }
  local battle = Battle.new({ data = DATA, party = { player }, wild = wild,
    save = save, random = detRandom })
  local screen = BattleState.new(game, { battle = battle, save = save,
    contest = opts.contest })
  game.stack:push(screen)
  return screen, pushed
end

-- Battle lines end in `prompt`, and PromptButton waits on A or B with no frame
-- countdown (home/joypad.asm:383-412), so the drain presses like a player.
local function runToMenu(screen, cap)
  for _ = 1, (cap or 3000) do
    local waiting = (screen.messageTimer or 0) > 0
    if waiting then Input:overlayPressed("a") end
    Input:step()
    screen:update(1 / 60)
    if waiting then Input:overlayReleased("a") end
    if screen.phase == "menu" then return true end
  end
  return false
end

local function press(screen, button)
  Input:overlayPressed(button)
  Input:step()
  screen:update(1 / 60)
  Input:overlayReleased(button)
  Input:step()
end

-- One press from a known cursor position, answering where it landed.
local function pressAt(screen, index, button)
  screen.menuIndex = index
  press(screen, button)
  return screen.menuIndex
end

-- ---- the whole 2x2 transition table ---------------------------------------
--
-- Row-major, FIGHT / PkMn over PACK / RUN (BattleMenuHeader's menu_coords).
-- The eight edge rows are the bug; the eight interior rows are the guard
-- against a fix that clamps the raw index instead of the column and the row,
-- which would hold every edge and still break FIGHT-down and RUN-left.
local GRID = {
  { 1, "left", 1 }, { 2, "left", 1 }, { 3, "left", 3 }, { 4, "left", 3 },
  { 1, "right", 2 }, { 2, "right", 2 }, { 3, "right", 4 }, { 4, "right", 4 },
  { 1, "up", 1 }, { 2, "up", 2 }, { 3, "up", 1 }, { 4, "up", 2 },
  { 1, "down", 3 }, { 2, "down", 4 }, { 3, "down", 3 }, { 4, "down", 4 },
}

local LABEL = { "FIGHT", "PkMn", "PACK", "RUN" }

do
  local screen = newScreen()
  check(runToMenu(screen), "the intro drains to the battle menu")
  eq(screen.menuIndex, 1, "which opens on FIGHT")

  for _, row in ipairs(GRID) do
    local from, button, want = row[1], row[2], row[3]
    local note = from == want
      and ("%s holds against %s"):format(LABEL[from], button)
      or ("%s goes %s to %s"):format(LABEL[from], button, LABEL[want])
    eq(pressAt(screen, from, button), want, note)
  end

  -- Whatever the cursor lands on has to stay a command the menu can run;
  -- an off-by-one clamp would index MENU past its end and choose nothing.
  for _, row in ipairs(GRID) do
    local landed = pressAt(screen, row[1], row[2])
    check(BattleState.MENU[landed] ~= nil,
      ("%s %s leaves the cursor on a real command"):format(
        LABEL[row[1]], row[2]))
  end
end

-- ---- the same grid inside the bug-catching contest -------------------------
--
-- ContestBattleMenuHeader only moves the box out to menu_coords 2, 12
-- (engine/battle/menu.asm:70-77); flag byte and cells are BattleMenuHeader's.
do
  local screen = newScreen({ contest = true })
  check(runToMenu(screen), "a contest battle drains to its menu")
  eq(screen.contest, true, "with the contest menu's coordinates")
  eq(pressAt(screen, 2, "right"), 2, "PkMn holds against right in the contest")
  eq(pressAt(screen, 3, "down"), 3, "PARKBALL holds against down")
  eq(pressAt(screen, 1, "down"), 3, "and FIGHT still drops onto it")
end

-- ---- the D-pad is silent ---------------------------------------------------
--
-- MenuClickSound / PlayClickSFX play SFX_READ_TEXT_2 for A and B only
-- (home/menu.asm:746-762), so a rebuilt branch must not click on a move.
do
  local screen = newScreen()
  check(runToMenu(screen), "reached the menu again")
  local played = {}
  screen.playSfx = function(_, name) played[#played + 1] = name end
  for _, button in ipairs({ "left", "right", "up", "down" }) do
    press(screen, button)
  end
  eq(#played, 0, "no click sound on any of the four directions")
  screen.menuIndex = 1
  press(screen, "a")
  eq(played[1], "Sfx_ReadText2", "A on FIGHT is what clicks")
end

S.finish()
