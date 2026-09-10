-- Parity: the Silph Co. 7F worker's LAPRAS gift offers the nickname prompt (#1049).
-- pokered scripts/SilphCo7F.asm SilphCo7FSilphWorkerM1Text.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end

local S = require("tests.harness").suite("parity Silph LAPRAS")
local check, eq = S.check, S.eq

local Game = require("src.core.Game")
local Input = require("src.core.Input")
local StateStack = require("src.core.StateStack")
local SaveData = require("src.core.SaveData")
local ScriptRunner = require("src.script.ScriptRunner")
local Commands = require("src.script.Commands")
local Flags = require("src.script.Flags")
local Pokemon = require("src.pokemon.Pokemon")
local Boxes = require("src.pokemon.Boxes")
local mapScripts = require("data.scripts.init")

Game.data = Data
Game.input = Input; Input:init()
Game.stack = StateStack; StateStack:init()
Game.save = SaveData.newGame()
require("src.render.Font").load(Data)

local MAP, TEXT = "SILPH_CO_7F", "TEXT_SILPHCO7F_SILPH_WORKER_M1"

-- === 1) the worker is command rows, so the run carries a ScriptRunner ===
local script = mapScripts.talkScript(MAP, TEXT)
check(type(script) == "table",
      "the LAPRAS worker is a row list, not a bare callback (#1049)")
eq(#ScriptRunner.validate(script), 0, "the rows validate cleanly")
local gives = 0
for _, row in ipairs(type(script) == "table" and script or {}) do
  if row[1] == "give_pokemon" then
    gives = gives + 1
    eq(row[2], "LAPRAS", "the gift species is LAPRAS")
    eq(row[3], 15, "the gift is level 15 (lb bc, LAPRAS, 15)")
    check(row[4] ~= true, "no skipNickname: AskName is left to run")
    eq(row[5], true, "GotMonText + jingle come from GivePokemon (give_pokemon.asm:45-46)")
  end
end
eq(gives, 1, "exactly one give_pokemon row")

-- === harness: run the talk script headless, A every frame, recording show_text ids
local shown = {}
local origShow = Commands.show_text
-- forward extraOpts: Commands.ask rides show_text's 4th argument
Commands.show_text = function(ctx, textId, subs, ...)
  table.insert(shown, textId)
  return origShow(ctx, textId, subs, ...)
end

local function runScript()
  shown = {}
  local ow = { map = { id = MAP, def = { label = MAP } },
               npcs = {}, entities = {} }
  local r = ScriptRunner.new(Game, ow)
  r:run(script, { npc = { def = {}, facePlayer = function() end },
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

local function shownIs(want, msg)
  eq(table.concat(shown, ","), table.concat(want, ","), msg)
end

-- === 2) the gift itself: thanks, GotMonText, nickname prompt, blurb ===
-- engine/events/give_pokemon.asm:45-46 then add_mon.asm:52 (#2243)
Game.save = SaveData.newGame()
check(runScript(), "LAPRAS gift script completes")
shownIs({ "_SilphCo7FSilphWorkerM1HaveThisPokemonText",
          "_GotMonText", "_DoYouWantToNicknameText",
          "_SilphCo7FSilphWorkerM1LaprasDescriptionText" },
        "thanks, got-mon line, nickname prompt, then the LAPRAS blurb")
eq(#Game.save.party, 1, "LAPRAS joins the party")
local lapras = Game.save.party[1] or {}
eq(lapras.species, "LAPRAS", "gift species is LAPRAS")
eq(lapras.level, 15, "LAPRAS is level 15")
eq(lapras.nickname, "AAAAAAAAAA",
   "the nickname prompt reaches the NamingScreen (A-mash)")
check(Flags.get(Game.save, "EVENT_GOT_LAPRAS"), "BIT_GOT_LAPRAS is set")
check(Game.save.pokedex.owned.LAPRAS, "LAPRAS is registered owned")

-- === 3) after the gift he worries about the PRESIDENT, and only after
check(runScript(), "post-gift script completes")
shownIs({ "_SilphCo7FSilphWorkerM1IsOurPresidentOkText" },
        "before Giovanni: the worried line, and no second LAPRAS")
eq(#Game.save.party, 1, "no second LAPRAS")

Flags.set(Game.save, "EVENT_BEAT_SILPH_CO_GIOVANNI")
check(runScript(), "post-Giovanni script completes")
shownIs({ "_SilphCo7FSilphWorkerM1SavedText" },
        "after Giovanni: saved at last")

-- === 4) party full, box has room: SendNewMonToBox still asks the name ===
Game.save = SaveData.newGame()
for i = 1, 6 do Game.save.party[i] = Pokemon.new(Data, "PIDGEY", 5) end
check(runScript(), "full-party gift script completes")
shownIs({ "_SilphCo7FSilphWorkerM1HaveThisPokemonText",
          "_GotMonText", "_DoYouWantToNicknameText", "_SentToBoxText",
          "_SilphCo7FSilphWorkerM1LaprasDescriptionText" },
        "full party: got-mon line, nickname, sent-to-box, blurb")
local boxed = false
for _, box in ipairs(Boxes.ensure(Game.save)) do
  for _, m in ipairs(box) do
    if m.species == "LAPRAS" then boxed = true end
  end
end
check(boxed, "full-party LAPRAS lands in a box")
check(Flags.get(Game.save, "EVENT_GOT_LAPRAS"), "full-party gift sets the flag")

-- === 5) party AND every box full: BoxIsFullText, no got-mon line, flag
Game.save = SaveData.newGame()
for i = 1, 6 do Game.save.party[i] = Pokemon.new(Data, "PIDGEY", 5) end
Boxes.ensure(Game.save)
for b = 1, Boxes.COUNT do
  for s = 1, Boxes.CAPACITY do Game.save.boxes[b][s] = { species = "PIDGEY" } end
end
check(runScript(), "full-everything script completes")
shownIs({ "_SilphCo7FSilphWorkerM1HaveThisPokemonText", "_BoxIsFullText" },
        "no room: the box-full line, never a got-mon line for a mon you lack")
check(not Flags.get(Game.save, "EVENT_GOT_LAPRAS"),
      "a failed give leaves BIT_GOT_LAPRAS clear, so the gift stays claimable")

Commands.show_text = origShow
S.finish()
