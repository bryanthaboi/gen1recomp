-- Menu button sounds (#570).  HandleMenuInput_ (home/window.asm) replays
-- SFX_PRESS_AB whenever the watched keys it just returned on include
-- PAD_A | PAD_B, unless BIT_NO_MENU_BUTTON_SOUND is set in wMiscFlags;
-- DisplayListMenuID watches PAD_A | PAD_B | PAD_SELECT (home/list_menu.asm),
-- so SELECT is answered but never beeps; DisplayOptionMenu plays it only at
-- .exitMenu (engine/menus/main_menu.asm), i.e. B, START and A on CANCEL.
-- Silence is half the contract: a click the original does not make is as
-- wrong as one it makes and the port swallows.
--   luajit tests/engine/menu_click_bug570.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

-- The UI modules reach for Sound lazily (require inside the press branch),
-- so seeding package.loaded before they load is enough to see every cue.
local played = {}
package.loaded["src.core.Sound"] = {
  play = function(_, key) played[#played + 1] = key end,
}

local ListMenu = require("src.ui.ListMenu")
local Menu = require("src.ui.Menu")
local OptionsMenu = require("src.ui.OptionsMenu")
local PartyMenu = require("src.ui.PartyMenu")

-- A stub game with the three things a menu touches: a stack it can pop
-- itself off, an input queue that is one fixed step of edges, and a
-- non-nil `data` (the beep helpers skip themselves when data is nil, which
-- is how the harness-driven screens stay silent).
local function newGame()
  local game = { data = {}, save = { options = {}, party = {},
                                     flags = {}, inventory = {} } }
  game.stack = {
    states = {},
    push = function(self, s) table.insert(self.states, s) end,
    pop = function(self) return table.remove(self.states) end,
    top = function(self) return self.states[#self.states] end,
  }
  game.input = {
    queue = {},
    wasPressed = function(self, btn) return self.queue[btn] or false end,
    isDown = function() return false end,
  }
  function game:writeOptions() end
  return game
end

-- one fixed step with `btn` on its edge; returns the cues it produced
local function press(state, btn)
  played = {}
  state.game.input.queue = btn and { [btn] = true } or {}
  state:update(1 / 60)
  state.game.input.queue = {}
  return played
end

local function beeps(state, btn)
  -- DisplayListMenuID's opening/redraw waits are tested in timing_parity;
  -- this suite isolates the sound made by the eventual accepted edge.
  while (state.inputHold or 0) > 0 do press(state, nil) end
  local cues = press(state, btn)
  for _, key in ipairs(cues) do
    if key ~= "Press_AB" then
      check(false, "unexpected cue " .. tostring(key) .. " on " .. btn)
    end
  end
  return #cues
end

-- ITEM and POKéDEX are both DisplayListMenuID lists, and cancelling either
-- was the silent half of the report.
local function newList(opts)
  local game = newGame()
  local list = ListMenu.new(game, "BAG",
    { { label = "POTION", value = "POTION" },
      { label = "ANTIDOTE", value = "ANTIDOTE" } }, opts)
  game.stack:push(list)
  return list, game
end

local list = newList({ onChoose = function() end })
eq(beeps(list, "a"), 1, "the first A on an item in ITEM clicks once (#570)")
eq(beeps(list, "b"), 1, "B out of a list clicks once (ITEM, POKéDEX cancel)")

local moves = newList({ onChoose = function() end,
                        onSelectKey = function() end })
eq(beeps(moves, "select"), 0,
   "SELECT is watched by DisplayListMenuID but outside its PAD_A | PAD_B "
   .. "sound test, so the swap key stays silent")
eq(beeps(moves, "up"), 0, "moving the cursor is silent")
eq(beeps(moves, "down"), 0, "moving the cursor is silent both ways")

-- Both PC sessions set BIT_NO_MENU_BUTTON_SOUND for their whole run
-- (engine/menus/pc.asm, engine/menus/players_pc.asm), so their lists are
-- the control case: the same code path, deliberately mute.
local pc = newList({ noSound = true, onChoose = function() end })
eq(beeps(pc, "a"), 0, "a PC list holds BIT_NO_MENU_BUTTON_SOUND: A is mute")
eq(beeps(pc, "b"), 0, "and so is backing out of it")

-- an emptied bag still answers A and B, and HandleMenuInput_ does not care
-- that the list has no rows
local emptyGame = newGame()
local empty = ListMenu.new(emptyGame, "BAG", {}, {})
emptyGame.stack:push(empty)
eq(beeps(empty, "a"), 1, "A out of an empty list still clicks")

-- OPTION: .exitMenu is the only PlaySound in DisplayOptionMenu
local function newOptions()
  local game = newGame()
  local om = OptionsMenu.new(game)
  game.stack:push(om)
  return om
end

local om = newOptions()
om.index = 1
eq(beeps(om, "a"), 0, "A on a setting row re-loops in the original: silent")
eq(beeps(om, "right"), 0, "and the Left/Right toggles are silent too")
eq(beeps(om, "left"), 0, "in both directions")
om.index = #om.rows + 1 -- CANCEL sits one past the hook-built rows
eq(beeps(om, "a"), 1, "A on CANCEL in OPTION clicks once (#570)")
eq(beeps(newOptions(), "b"), 1, "B out of OPTION clicks once (#570)")
eq(beeps(newOptions(), "start"), 1, "START leaves OPTION the same way")

-- POKéMON: HandlePartyMenuInput runs through HandleMenuInput_
local function newParty()
  local game = newGame()
  local pm = PartyMenu.new(game, {})
  game.stack:push(pm)
  return pm
end

eq(beeps(newParty(), "b"), 1, "B out of POKéMON clicks once (#570)")
eq(beeps(newParty(), "a"), 1, "and A in POKéMON clicks")
eq(beeps(newParty(), "down"), 0, "moving between slots is silent")

-- The start menu itself already beeped before the fix; pinned here because
-- an over-eager patch that beeps on every watched key would break it.
-- draw_start_menu.asm's mask includes PAD_START, and START is outside the
-- PAD_A | PAD_B sound test, so closing the menu with it is silent.
local function newStartMenu()
  local game = newGame()
  local m = Menu.new(game, { { label = "POKéDEX", onSelect = function() end },
                             { label = "ITEM", onSelect = function() end } },
                     { startCloses = true })
  game.stack:push(m)
  return m
end

eq(beeps(newStartMenu(), "a"), 1, "A on a start-menu row clicks")
eq(beeps(newStartMenu(), "b"), 1, "B closing the start menu clicks")
eq(beeps(newStartMenu(), "start"), 0,
   "START closes the start menu silently: it is watched but not in the "
   .. "PAD_A | PAD_B branch")

T.finish("menu_click_bug570")
