-- Parity test, gift atomicity: a mon handed over by give_pokemon and the
-- event that closes its offer must land in the same script step, so a
-- script torn down between the two cannot hand the gift out twice (#426).
--
-- asm sources:
--   pokeyellow scripts/Route24.asm (Route24CooltrainerM4Text: CheckEvent
--     EVENT_54F -> YesNoChoice -> GivePokemon -> `jp nc, TextScriptEnd`
--     (party + box full leaves the event clear so the offer repeats) ->
--     PrintText Route24Text_515e3 -> SetEvent EVENT_54F)
--   pokeyellow scripts/CeruleanMelaniesHouse.asm (same shape plus predef
--     HideObject TOGGLE_CERULEAN_BULBASAUR, then SetEvent
--     EVENT_GOT_BULBASAUR_IN_CERULEAN)
--   pokeyellow scripts/VermilionCity_2.asm (CheckEvent / SetEvent
--     EVENT_GOT_SQUIRTLE_FROM_OFFICER_JENNY)
--   scripts/CeladonMansionRoofHouse.asm (Eevee ball: GivePokemon with no
--     confirm, HideObject on success)
-- On hardware the event write trails the received text because no step in
-- between can abort.  The port yields there (AskName, NamingScreen, the
-- text box) and wraps every row in the script.command mod hook, so the
-- write is hoisted ahead of the text: the event is only read at script
-- entry, and the failed-give path still leaves it clear.
--
-- Self-contained: run via `luajit tests/parity_gift_atomicity.lua`; also
-- dofile'd by tests/run_tests.lua's aggregator.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end

local S = require("tests.harness").suite("parity gift atomicity")
local check, eq = S.check, S.eq

local Commands = require("src.script.Commands")
local Events = require("src.mods.Events")
local Flags = require("src.script.Flags")
local Game = require("src.core.Game")
local Hooks = require("src.mods.Hooks")
local Input = require("src.core.Input")
local Logger = require("src.core.Logger")
local Runtime = require("src.mods.Runtime")
local SaveData = require("src.core.SaveData")
local ScriptRunner = require("src.script.ScriptRunner")
local StateStack = require("src.core.StateStack")

Game.data = Data
Game.input = Input; Input:init()
Game.stack = StateStack; StateStack:init()
Game.save = SaveData.newGame()
require("src.render.Font").load(Data)

local gifts = require("data.scripts.yellow_gifts")
local eevee = require("data.scripts.celadon_eevee")

-- === 1) row-order audit: on every gift site the carry guard follows
--        give_pokemon immediately and the bookkeeping (event, and the
--        HideObject that clears a ball or a pen mon) comes before any
--        received text ===
local function audit(label, rows)
  local give
  for i, row in ipairs(rows) do
    if row[1] == "give_pokemon" then give = i break end
  end
  if not give then
    check(false, label .. ": has a give_pokemon row")
    return
  end
  eq(rows[give + 1] and rows[give + 1][1], "jump_if_false",
     label .. ": carry guard sits right after give_pokemon")
  local flag, text, hide
  for i = give + 2, #rows do
    local name = rows[i][1]
    if name == "set_flag" and not flag then flag = i end
    if name == "hide_object" and not hide then hide = i end
    if (name == "show_text" or name == "ask") and not text then text = i end
    if name == "jump" and rows[i][2] ~= nil and text then break end
  end
  eq(flag, give + 2, label .. ": event write is the first row past the guard")
  check(text and flag < text,
        label .. ": event write precedes the received text")
  if hide then
    check(hide < text, label .. ": HideObject precedes the received text")
  end
end

-- the two function-form scripts build their rows per talk; run them with
-- the gift branch's preconditions and keep what they hand the runner
local function capture(fn, save)
  local rows
  local ow = { runner = { run = function(_, r) rows = r end } }
  fn({ save = save }, ow, { def = {}, facePlayer = function() end },
     function() end)
  return rows or {}
end

audit("Route 24 Damian",
      gifts.ROUTE_24.talk.TEXT_ROUTE24_COOLTRAINER_M4)
audit("Melanie's BULBASAUR",
      capture(gifts.CERULEAN_MELANIES_HOUSE.talk
                .TEXT_CERULEANMELANIESHOUSE_MELANIE,
              { flags = {}, pikachuHappiness = 200 }))
audit("Officer Jenny's SQUIRTLE",
      capture(gifts.VERMILION_CITY.talk.TEXT_VERMILIONCITY_OFFICER_JENNY,
              { flags = {}, inventory = { THUNDERBADGE = 1 } }))
audit("Celadon EEVEE ball",
      eevee.talk.TEXT_CELADONMANSION_ROOF_HOUSE_EEVEE_POKEBALL)

-- === harness: run a row list headless, A-mashing through the yes/no,
--        the nickname prompt and every text box, recording show_text ids
--        (Yellow's gift text is not in a Red cache, so show_text takes
--        its literal-id fallback: the ids are still what we assert on) ===
local shown = {}
local origShow = Commands.show_text
Commands.show_text = function(ctx, textId, subs)
  shown[#shown + 1] = textId
  return origShow(ctx, textId, subs)
end

local function runRows(rows)
  shown = {}
  StateStack:init()
  local ow = { map = { id = "ROUTE_24", def = { label = "ROUTE_24" } },
               npcs = {}, entities = {} }
  local r = ScriptRunner.new(Game, ow)
  r:run(rows, { npc = { def = {}, facePlayer = function() end },
                overworld = ow })
  local guard = 0
  while r:isRunning() and guard < 3000 do
    guard = guard + 1
    Input.pressed = { a = true }
    StateStack:update(1 / 60)
    r:update()
  end
  Input.pressed = {}
  return not r:isRunning()
end

local DAMIAN = gifts.ROUTE_24.talk.TEXT_ROUTE24_COOLTRAINER_M4

-- === 2) plain accept: one CHARMANDER, EVENT_54F set, and the next talk
--        is Damian's after-text only ===
Game.save = SaveData.newGame()
check(runRows(DAMIAN), "Damian gift script completes")
eq(#Game.save.party, 1, "CHARMANDER joins the party")
eq(Game.save.party[1].species, "CHARMANDER", "gift species is CHARMANDER")
check(Flags.get(Game.save, "EVENT_54F"), "accepting sets EVENT_54F")
check(runRows(DAMIAN), "post-gift talk completes")
eq(table.concat(shown, ","), "_Route24DamianText4",
   "a closed offer shows only the after-text")
eq(#Game.save.party, 1, "no second CHARMANDER")

-- === 3) the regression itself: every row runs inside the script.command
--        hook, and a mod that mishandles the row after the give (the
--        reporter was running a third-party UI mod) tears the coroutine
--        down mid-gift -- here by sending the pc at a label that is not
--        there.  The mon is already in the party, so EVENT_54F has to be
--        set by then or the next talk re-runs the whole offer ===
local savedEvents, savedHooks, savedErrors =
  Runtime.events, Runtime.hooks, Runtime.errors
local hooks = Hooks.new()
Runtime.install(Events.new(), hooks, {})
local remove = hooks:wrap("script.command", function(nextFn, _, name, args)
  if name == "show_text" and args[1] == "_Route24DamianText2" then
    return "no_such_label"
  end
  return nextFn()
end, 0, "t")

Game.save = SaveData.newGame()
local origError = Logger.error -- the tear-down logs; the test expects it
Logger.error = function() end
runRows(DAMIAN)
Logger.error = origError
eq(#Game.save.party, 1, "the killed script still handed the CHARMANDER over")
check(Flags.get(Game.save, "EVENT_54F"),
      "EVENT_54F survives a tear-down after the give")

remove()
Runtime.install(savedEvents, savedHooks, savedErrors)

check(runRows(DAMIAN), "talk after the tear-down completes")
eq(table.concat(shown, ","), "_Route24DamianText4",
   "the interrupted gift is not offered again")
eq(#Game.save.party, 1, "still exactly one CHARMANDER")

S.finish()
