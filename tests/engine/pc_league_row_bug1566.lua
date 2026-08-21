-- The PC gains a PKMN LEAGUE row after the Hall of Fame (#1566):
-- DisplayPCMainMenu (engine/pokemon/bills_pc.asm:5), PKMNLeague (pc.asm:67)
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local OW = require("src.world.OverworldController")

local function setUpvalue(fn, name, val)
  local i = 1
  while true do
    local n = debug.getupvalue(fn, i)
    if not n then return false end
    if n == name then debug.setupvalue(fn, i, val); return true end
    i = i + 1
  end
end

local pushed = {}
local fakeGame = {
  data = { text = {
    _TurnedOnPC1Text = "RED turned on\nthe PC.",
    _AccessedHoFPCText = "Accessed POKéMON\nLEAGUE's site.",
  } },
  save = {
    flags = { EVENT_GOT_POKEDEX = true },
    player = { name = "RED" },
  },
  stack = { push = function(_, item) pushed[#pushed + 1] = item end },
}

local sounds = {}
package.loaded["src.core.Sound"] = {
  play = function(_, name) sounds[#sounds + 1] = name end,
}
local menuItems
package.loaded["src.ui.Menu"] = {
  new = function(_, items) menuItems = items; return { menu = true } end,
}
local opened = {}
T.check(setUpvalue(OW.openPC, "Game", fakeGame), "Game upvalue on openPC")
T.check(setUpvalue(OW.openPC, "Screens", {
  push = function(_, id) opened[#opened + 1] = id end,
}), "Screens upvalue on openPC")
T.check(setUpvalue(OW.openPC, "TextBox", {
  new = function(_, text, onDone) return { text = text, onDone = onDone } end,
}), "TextBox upvalue on openPC")

local fakeSelf = setmetatable({}, { __index = OW })

local function labels()
  pushed, menuItems, sounds, opened = {}, nil, {}, {}
  fakeSelf:openPC(function() end)
  pushed[1].onDone() -- close TurnedOnPC1Text; the menu goes up behind it
  local names = {}
  for i, item in ipairs(menuItems or {}) do names[i] = item.label end
  return names
end

local function indexOf(list, label)
  for i, name in ipairs(list) do
    if name == label then return i end
  end
end

-- wNumHoFTeams == 0: three rows plus LOG OFF (bills_pc.asm .noLeaguePC)
local before = labels()
T.eq(indexOf(before, "<PK><MN>LEAGUE"), nil,
  "no PKMN LEAGUE row before the Hall of Fame")
T.eq(#before, 4, "BILL's PC, the player's PC, PROF.OAK's PC and LOG OFF")

-- one recorded team is enough, and it stays for good
fakeGame.save.hallOfFame = { { { species = "PIKACHU", level = 80 } } }
local after = labels()
local iLeague = indexOf(after, "<PK><MN>LEAGUE")
T.check(iLeague, "PKMN LEAGUE appears once a team is in the Hall of Fame")
T.eq(after[iLeague - 1], "PROF.OAK's PC", "it follows PROF.OAK's PC")
T.eq(after[iLeague + 1], "LOG OFF", "and LOG OFF still closes the menu")
T.check(menuItems[iLeague].keepOpen,
  "B returns to the PC menu (ReloadMainMenu), it does not log off")

-- selecting it: SFX_ENTER_PC, AccessedHoFPCText, then the roster screen
menuItems[iLeague].onSelect()
T.eq(sounds[#sounds], "Enter_PC", "PKMNLeague plays SFX_ENTER_PC")
local box = pushed[#pushed]
T.eq(box.text, fakeGame.data.text._AccessedHoFPCText,
  "PKMNLeaguePC prints AccessedHoFPCText first")
box.onDone()
T.same(opened, { "LeaguePC" }, "the Hall of Fame roster screen opens")

-- without the Pokedex, .noOaksPC2 skips Oak's PC and the league row alike
-- (bills_pc.asm:48-49, :68-72); only the box height ignores it (:5-7)
fakeGame.save.flags.EVENT_GOT_POKEDEX = nil
local noDex = labels()
T.eq(indexOf(noDex, "<PK><MN>LEAGUE"), nil,
  "no dex, no PKMN LEAGUE row, HoF teams or not")
T.eq(indexOf(noDex, "PROF.OAK's PC"), nil, "and no PROF.OAK's PC either")

T.finish("pc league row (#1566)")
