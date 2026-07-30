-- Parity test: the Celadon Mansion roof house blackboard and pamphlet (#391).
--
-- pokered data/events/hidden_events.asm, hidden_events_for
-- CELADON_MANSION_ROOF_HOUSE:
--   hidden_text_predef 3, 0 / 4, 0  PrintBlackboardLinkCableText, LinkCableHelp
--   hidden_text_predef 3, 4         PrintNotebookText, TMNotebook
-- tools/extract/field.py only parses `hidden_event` rows, so neither tile
-- reaches data/generated/field.lua and data/scripts/celadon_eevee.lua carries
-- them as an onInteract hook instead.  LinkCableHelp
-- (engine/events/hidden_events/school_blackboard.asm) prints
-- _LinkCableHelpText1, then loops prompt + 15x10 heading box until B or the
-- fourth row; TMNotebook (school_notebooks.asm) is one plain text.
--
-- Self-contained; run via `luajit tests/parity_celadon_roof_readables.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.CELADON_MANSION_ROOF_HOUSE) then Data:load() end
local Font = require("src.render.Font")
if not pcall(Font.encode, "A") then Font.load(Data) end
require("data.scripts.init")
local MapScripts = require("src.script.MapScripts")
local TextBox = require("src.render.TextBox")
local Menu = require("src.ui.Menu")
local S = require("tests.harness").suite("parity celadon roof readables")
local check, eq = S.check, S.eq

local MAP = "CELADON_MANSION_ROOF_HOUSE"

for _, key in ipairs({ "_LinkCableHelpText1", "_LinkCableHelpText2",
    "_LinkCableInfoText1", "_LinkCableInfoText2", "_LinkCableInfoText3" }) do
  check(type(Data.text[key]) == "string" and Data.text[key] ~= "",
        key .. " is extracted")
end

local hooks = MapScripts.get(MAP)
check(hooks and type(hooks.onInteract) == "function",
      MAP .. " registers onInteract for the two readables")
check(hooks and hooks.talk
        and hooks.talk.TEXT_CELADONMANSION_ROOF_HOUSE_EEVEE_POKEBALL ~= nil,
      "the Eevee ball talk entry survives alongside the hook")

-- stack stub: the blackboard loop pushes and pops, so keep the whole stack
local stack = {}
local game = {
  data = Data,
  save = { player = { name = "RED", rival = "BLUE" } },
  stack = {
    push = function(_, state) stack[#stack + 1] = state end,
    pop = function() return table.remove(stack) end,
    top = function() return stack[#stack] end,
  },
}
local ow = { player = { facing = "up" } }

local function pages(box)
  local out = {}
  for _, page in ipairs(box.pages or {}) do
    for _, line in ipairs(page) do out[#out + 1] = line end
  end
  return table.concat(out, "\n")
end

-- the pamphlet: (3,4) only, the table's other three cells stay silent
stack = {}
eq(hooks.onInteract(game, ow, 3, 4), true, "the pamphlet at (3,4) is claimed")
local box = stack[#stack]
check(getmetatable(box) == TextBox, "the pamphlet pushes a TextBox")
local pamphlet = pages(box)
for _, want in ipairs({ "pamphlet", "50 TMs", "HMs", "SILPH CO." }) do
  check(pamphlet:find(want, 1, true) ~= nil,
        "the pamphlet text has " .. want)
end

for _, cell in ipairs({ { 4, 4 }, { 3, 3 }, { 4, 3 }, { 3, 5 } }) do
  eq(hooks.onInteract(game, ow, cell[1], cell[2]), false,
     ("(%d,%d) is not one of the readables"):format(cell[1], cell[2]))
end

-- the blackboard: both top-row cells, and facing is irrelevant because
-- hidden_text_predef spends the facing byte on the predef id
for _, fx in ipairs({ 3, 4 }) do
  stack = {}
  ow.player.facing = fx == 3 and "up" or "left"
  eq(hooks.onInteract(game, ow, fx, 0), true,
     ("the blackboard at (%d,0) is claimed"):format(fx))
  check(pages(stack[#stack]):find("TRAINER TIPS", 1, true) ~= nil,
        ("(%d,0) opens with _LinkCableHelpText1"):format(fx))
end
eq(hooks.onInteract(game, ow, 2, 0), false,
   "the wall left of the blackboard stays silent")

-- walk the loop: intro -> prompt -> heading box -> blurb -> prompt again
stack = {}
hooks.onInteract(game, ow, 3, 0)
local intro = stack[#stack]
check(type(intro.onDone) == "function", "the intro text has a continuation")
intro.onDone()
local prompt = stack[#stack]
check(getmetatable(prompt) == TextBox
        and pages(prompt):find("heading", 1, true) ~= nil,
      "the intro leads into the which-heading prompt")
prompt.onDone()
local menu = stack[#stack]
check(getmetatable(menu) == Menu, "the prompt opens the heading menu")
eq(#menu.items, 4, "four headings, as in HowToLinkText")
local labels = {}
for i, item in ipairs(menu.items) do labels[i] = item.label end
eq(table.concat(labels, "/"),
   "HOW TO LINK/COLOSSEUM/TRADE CENTER/STOP READING",
   "the headings read in HowToLinkText order")
eq(menu.items[4].onSelect, nil, "STOP READING just closes the menu")
check(menu.tw == 15 and menu.th == 10 and menu.tx == 0 and menu.ty == 0,
      "the box is the asm's 15x10 at the top left")

for i = 1, 3 do
  stack = {}
  menu.items[i].onSelect()
  local blurb = stack[#stack]
  check(getmetatable(blurb) == TextBox,
        labels[i] .. " prints a text box")
  local want = Data.text["_LinkCableInfoText" .. i]:match("^[^\n\011\012]+")
  check(pages(blurb):find(want, 1, true) ~= nil,
        labels[i] .. " prints _LinkCableInfoText" .. i)
  check(type(blurb.onDone) == "function",
        labels[i] .. " returns to the prompt instead of dropping out")
  blurb.onDone()
  check(getmetatable(stack[#stack]) == TextBox,
        "the prompt comes back after " .. labels[i])
  stack[#stack].onDone()
  check(getmetatable(stack[#stack]) == Menu,
        "the menu comes back after " .. labels[i])
end

S.finish()
