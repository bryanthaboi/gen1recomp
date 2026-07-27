-- Parity test,  Workstream F.
-- Self-contained: run via `luajit tests/parity_F.lua`; also dofile'd by
-- tests/run_tests.lua's aggregator.
--
-- Covers: Oak no longer hands over 5 POKé BALLs the instant a starter is
-- picked (scripts/OaksLab.asm has no such grant); the balls are handed
-- over later, at TEXT_OAKSLAB_OAK1's .give_poke_balls beat, gated on
-- EVENT_BEAT_ROUTE22_RIVAL_1ST_BATTLE and the one-shot
-- EVENT_GOT_POKEBALLS_FROM_OAK flag (data/scripts/oaks_lab.lua).
-- Also #137: starter give_pokemon runs AskName (nickname yes/no).
-- Also #235: the Viridian Mart parcel walk replays its simulated joypad
-- states in the order the original consumes them.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end

local S = require("tests.harness").suite("parity F")
local check, eq = S.check, S.eq

local Game = require("src.core.Game")
local Input = require("src.core.Input")
local StateStack = require("src.core.StateStack")
local SaveData = require("src.core.SaveData")
local ScriptRunner = require("src.script.ScriptRunner")
local Flags = require("src.script.Flags")
local ChoiceBox = require("src.ui.ChoiceBox")
local NamingScreen = require("src.ui.NamingScreen")
local mapScripts = require("data.scripts.init")

Game.data = Data
Game.input = Input; Input:init()
Game.stack = StateStack; StateStack:init()
Game.save = SaveData.newGame()
require("src.render.Font").load(Data)

-- pumps a script coroutine to completion; pressFn returns the Input.pressed
-- table for this frame (default: mash A through text/ask/naming)
local function runScript(script, pressFn)
  local r = ScriptRunner.new(Game, nil)
  r:run(script, {})
  local guard = 0
  while r:isRunning() and guard < 4000 do
    guard = guard + 1
    Input.pressed = pressFn and pressFn() or { a = true }
    StateStack:update(1 / 60)
    r:update()
  end
  Input.pressed = {}
  return not r:isRunning()
end

-- === 1) picking a starter no longer grants POKé BALLs ===
-- (like the parcel-chain runScript below, this runner has no live
-- overworld; the starterBall() script's give_pokemon/set_flag rows run
-- fine, but its later rival-counterpick NPC choreography needs
-- ctx.overworld and errors out headless -- the ScriptRunner logs and
-- kills the coroutine, so isRunning() still goes false, which is all we
-- need to check the pre-crash flag/inventory state below)
Flags.set(Game.save, "EVENT_FOLLOWED_OAK_INTO_LAB")
check(runScript(mapScripts.talkScript("OAKS_LAB", "TEXT_OAKSLAB_BULBASAUR_POKE_BALL")),
      "starter pick script completes")
check(Flags.get(Game.save, "EVENT_GOT_STARTER"), "starter flag set")
eq(Game.save.inventory.POKE_BALL, nil, "no POKe BALLs yet right after picking a starter")
check(Game.save.party[1] and Game.save.party[1].species == "BULBASAUR",
      "starter joined the party")
-- A-mash accepts the nickname prompt and fills NamingScreen with A's
check(Game.save.party[1].nickname == "AAAAAAAAAA",
      "starter nickname prompt accepted (AskName / #137)")

-- === 2) the parcel/pokedex beat still doesn't grant POKé BALLs ===
-- OaksLabOak1Text.got_parcel requires EVENT_BATTLED_RIVAL_IN_OAKS_LAB
Flags.set(Game.save, "EVENT_BATTLED_RIVAL_IN_OAKS_LAB")
check(runScript(mapScripts.talkScript("VIRIDIAN_MART", "TEXT_VIRIDIANMART_CLERK")),
      "mart clerk script completes")
eq(Game.save.inventory.OAKS_PARCEL, 1, "clerk hands over Oak's Parcel")

check(runScript(mapScripts.talkScript("OAKS_LAB", "TEXT_OAKSLAB_OAK1")),
      "Oak delivery script completes")
eq(Game.save.inventory.OAKS_PARCEL, nil, "parcel delivered")
check(Flags.get(Game.save, "EVENT_OAK_GOT_PARCEL"), "delivery flag set")
check(Flags.get(Game.save, "EVENT_GOT_POKEDEX"), "Pokedex flag set")
-- OaksLab.asm OakGivesPokedex: HideObject TOGGLE_POKEDEX_1/2 (#106)
local labToggles = Game.save.objectToggles and Game.save.objectToggles.OAKS_LAB
check(labToggles and labToggles.OAKSLAB_POKEDEX1 == false,
      "POKEDEX1 hidden after receiving Pokédex")
check(labToggles and labToggles.OAKSLAB_POKEDEX2 == false,
      "POKEDEX2 hidden after receiving Pokédex")
eq(Game.save.inventory.POKE_BALL, nil, "still no POKe BALLs at the pokedex beat")

-- talking to Oak again before beating the Route 22 rival is the
-- .mon_around_the_world branch (not the poke-ball grant)
check(runScript(mapScripts.talkScript("OAKS_LAB", "TEXT_OAKSLAB_OAK1")),
      "Oak talk (pre-Route22-win) script completes")
eq(Game.save.inventory.POKE_BALL, nil, "still no POKe BALLs before the Route 22 rival is beaten")

-- === 3) beating the Route 22 rival unlocks the real grant ===
Flags.set(Game.save, "EVENT_BEAT_ROUTE22_RIVAL_1ST_BATTLE")
check(runScript(mapScripts.talkScript("OAKS_LAB", "TEXT_OAKSLAB_OAK1")),
      "Oak give-balls script completes")
eq(Game.save.inventory.POKE_BALL, 5, "Oak gives 5 POKe Balls after the Route 22 win")
check(Flags.get(Game.save, "EVENT_GOT_POKEBALLS_FROM_OAK"), "one-shot flag set")

-- === 4) talking to Oak again does not re-grant (one-shot gate) ===
check(runScript(mapScripts.talkScript("OAKS_LAB", "TEXT_OAKSLAB_OAK1")),
      "Oak talk (post-grant) script completes")
eq(Game.save.inventory.POKE_BALL, 5, "POKe Ball count unchanged on a second talk")

-- === 5) onEnter re-hides table Pokédex for pre-#106 saves ===
Game.save.objectToggles = { OAKS_LAB = {
  OAKSLAB_POKEDEX1 = true, OAKSLAB_POKEDEX2 = true,
} }
local oaksLab = mapScripts.get("OAKS_LAB")
check(oaksLab and type(oaksLab.onEnter) == "function", "OAKS_LAB onEnter present")
oaksLab.onEnter(Game, nil)
local repaired = Game.save.objectToggles.OAKS_LAB
check(repaired.OAKSLAB_POKEDEX1 == false
      and repaired.OAKSLAB_POKEDEX2 == false,
      "onEnter hides both Pokédex table sprites when EVENT_GOT_POKEDEX is set")

-- === 6) #137: declining the starter nickname leaves no nickname ===
-- Choice boxes in order: (1) "you want X?" YES, (2) nickname YES/NO -> NO
Game.save = SaveData.newGame()
Flags.set(Game.save, "EVENT_FOLLOWED_OAK_INTO_LAB")
local choicesSeen, lastChoice = 0, nil
local function declineNickname()
  local top = StateStack:top()
  local mt = getmetatable(top)
  if mt == ChoiceBox and top ~= lastChoice then
    choicesSeen = choicesSeen + 1
    lastChoice = top
  elseif mt ~= ChoiceBox then
    lastChoice = nil
  end
  if mt == ChoiceBox and choicesSeen >= 2 then
    return { b = true }
  end
  if mt == NamingScreen then
    return { start = true }
  end
  return { a = true }
end
check(runScript(mapScripts.talkScript("OAKS_LAB", "TEXT_OAKSLAB_CHARMANDER_POKE_BALL"),
                declineNickname),
      "starter pick with declined nickname completes")
check(Flags.get(Game.save, "EVENT_GOT_STARTER"), "declined-nickname path still sets starter flag")
eq(Game.save.party[1] and Game.save.party[1].species, "CHARMANDER",
   "declined-nickname path still gives Charmander")
eq(Game.save.party[1] and Game.save.party[1].nickname, nil,
   "declining nickname leaves the species name")

-- === #235: the parcel walk goes up first, then left ===
-- ViridianMartDefaultScript feeds .PlayerMovement (PAD_LEFT 1, PAD_UP 2)
-- through DecodeRLEList into wSimulatedJoypadStatesEnd and then walks the
-- index *down*, so the list plays back to front: up, up, left.  Ending on
-- the left step is what leaves the player facing the clerk; replaying it
-- front to back parked them at the counter facing up.
do
  local parcelSave = SaveData.newGame()
  Flags.set(parcelSave, "EVENT_GOT_STARTER")
  local realSave = Game.save
  Game.save = parcelSave

  local queued
  local fakeOw = { queueScript = function(_, rows) queued = rows end }
  local mart = mapScripts.get("VIRIDIAN_MART")
  check(mart and type(mart.onEnter) == "function",
        "VIRIDIAN_MART has an onEnter parcel script")
  mart.onEnter(Game, fakeOw)
  check(type(queued) == "table", "entering the mart queues the parcel script")

  local moves = {}
  for _, row in ipairs(queued or {}) do
    if row[1] == "move_player" then moves[#moves + 1] = { row[2], row[3] } end
  end
  eq(#moves, 2, "the walk is two move_player runs")
  eq(moves[1] and moves[1][1], "up", "first leg is up (#235)")
  eq(moves[1] and moves[1][2], 2, "first leg is two cells")
  eq(moves[2] and moves[2][1], "left", "second leg is left, facing the clerk")
  eq(moves[2] and moves[2][2], 1, "second leg is one cell")

  Game.save = realSave
end

S.finish()
