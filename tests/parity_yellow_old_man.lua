-- Parity (#617): Yellow's Viridian old man is the OLD_MAN2 at (18,9),
-- not the Red/Blue OLD_MAN at (17,5), and his dialog has no yes/no
-- choice -- the apology speech runs the RATTATA demo battle straight
-- away, the post-battle line is the losing-my-touch text, and he walks
-- off and hides.
--
-- Oracle: pokeyellow scripts/OaksLab.asm (OaksLabOakGivesPokedexScript:
-- HideObject TOGGLE_LYING_OLD_MAN / ShowObject TOGGLE_OLD_MAN_2),
-- scripts/ViridianCity.asm (ViridianCityCheckWaitingOldMan,
-- ViridianCityOldMan2Text, ...InitialCatchTrainingScript,
-- ...PostInitialCatchTraining) and scripts/ViridianCity_2.asm
-- (ViridianCityPrintOldManText).  The Red/Blue "Are you in a hurry?"
-- script was running against Yellow's text: YES printed the TimeIsMoney
-- alias (_ViridianCityOldManLosingMyTouchText) and NO ran the demo --
-- every talk, forever.
--
-- Self-contained: `luajit tests/parity_yellow_old_man.lua`; also globbed
-- by tests/run_tests.lua.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end
local GameVersion = require("src.core.GameVersion")
local SaveData = require("src.core.SaveData")
local ScriptRunner = require("src.script.ScriptRunner")
local TextBox = require("src.render.TextBox")
local BattleState = require("src.battle.BattleState")
local Pokemon = require("src.pokemon.Pokemon")

local S = require("tests.harness").suite("parity Yellow old man (#617)")
local check, eq = S.check, S.eq

local oldVersion = GameVersion.get()

local MAP = "VIRIDIAN_CITY"
local SLEEPER = "VIRIDIANCITY_OLD_MAN_SLEEPY"
local WALKER = "VIRIDIANCITY_OLD_MAN"
local OLD_MAN2 = "VIRIDIANCITY_OLD_MAN2"
local DONE_FLAG = "EVENT_COMPLETED_CATCH_TRAINING"

-- The Yellow wiring must be attached before anything else caches the
-- map-script registry: data.scripts.init branches on GameVersion at
-- load, so flip it first (this file owns its own process when run
-- standalone).  Under tests/run_tests.lua the registry is already
-- cached with the Red wiring, so attach the Yellow modules directly
-- afterwards -- attachBase merges per TEXT constant and replaces hooks,
-- which is a no-op on a fresh process and the fix on a shared one.
GameVersion.set("yellow")
local mapScripts = require("data.scripts.init")
local MapScripts = require("src.script.MapScripts")
MapScripts.attachBase(MAP,
  require("data.scripts.yellow_viridian_old_man").VIRIDIAN_CITY)
MapScripts.attachBase("OAKS_LAB",
  require("data.scripts.oaks_lab_yellow"))
local oldManMod = require("data.scripts.yellow_viridian_old_man")

-- ------------------------------------------------------- the demo species
-- The catch demo is a RATTATA in Yellow (SetupBattle sets wCurOpponent
-- = RATTATA) but the Yellow manifest inherited Red's WEEDLE; the runtime
-- override in Data:applyVersionedFieldData repairs old caches.  Kept
-- active until the end of this file so the demo-battle assertions below
-- run against the Yellow value; restored before S.finish() like
-- parity_yellow_trades does for its trades table.
local originalOldManBattle = Data.field.oldManBattle
  or { species = "WEEDLE", level = 5 } -- the fixture carries no oldManBattle
local originalTrades = Data.field.trades
eq(originalOldManBattle.species, "WEEDLE",
   "Red/Blue's old man still demos a Weedle")
GameVersion.set("yellow")
Data:applyVersionedFieldData()
eq(Data.field.oldManBattle.species, "RATTATA",
   "Yellow's old man demos a Rattata (#617)")

local manifestFile = assert(io.open("tools/rom_manifest_yellow.json", "r"))
local yellowManifest = manifestFile:read("*a")
manifestFile:close()
check(yellowManifest:find('"species": "RATTATA"', 1, true) ~= nil,
      "the Yellow manifest stamps RATTATA for fresh imports")
local redManifestFile = assert(io.open("tools/rom_manifest.json", "r"))
local redManifest = redManifestFile:read("*a")
redManifestFile:close()
check(redManifest:find('"species": "WEEDLE"', 1, true) ~= nil,
      "and the Red/Blue manifest keeps WEEDLE")

-- ------------------------------------------------------- the Pokedex swap
-- OaksLabOakGivesPokedexScript shows TOGGLE_OLD_MAN_2 (the tutorial old
-- man standing on the sleeper's cell), never the Red/Blue walker
local oaksRows = mapScripts.talkScript("OAKS_LAB", "TEXT_OAKSLAB_OAK1")
check(type(oaksRows) == "table",
      "the Yellow OaksLab Oak talk resolves to rows")
local sawSleepHide, sawOldMan2Show, sawOldManShow = false, false, false
for _, row in ipairs(oaksRows or {}) do
  if row[1] == "hide_object" and row[3] == SLEEPER then sawSleepHide = true end
  if row[1] == "show_object" and row[3] == OLD_MAN2 then sawOldMan2Show = true end
  if row[1] == "show_object" and row[3] == WALKER then sawOldManShow = true end
end
check(sawSleepHide, "the Pokédex hand-over hides the lying old man")
check(sawOldMan2Show, "it shows OLD_MAN2 on the sleeper's cell")
check(not sawOldManShow, "it never shows the Red/Blue OLD_MAN (#617)")

-- both Yellow gamblers default hidden (toggle OFF), like pokeyellow
-- data/maps/toggleable_objects.asm.  OLD_MAN2 only exists in a Yellow
-- import -- a Red-imported checkout carries just OLD_MAN -- so the
-- dataset checks tolerate its absence and the Yellow manifest carries
-- the OLD_MAN2 default instead.
local walkerDef, oldMan2Def
if Data.maps[MAP] then
  for _, o in ipairs(Data.maps[MAP].objects or {}) do
    if o.name == WALKER then walkerDef = o end
    if o.name == OLD_MAN2 then oldMan2Def = o end
  end
end
check(walkerDef == nil or walkerDef.hidden == true,
      "VIRIDIANCITY_OLD_MAN defaults hidden in Yellow")
check(oldMan2Def == nil or oldMan2Def.hidden == true,
      "VIRIDIANCITY_OLD_MAN2 defaults hidden in Yellow")
local om2Name = yellowManifest:find('"name": "VIRIDIANCITY_OLD_MAN2"', 1, true)
local om2Hidden = om2Name and yellowManifest:sub(
  math.max(1, om2Name - 40), om2Name):find('"hidden": true', 1, true)
check(om2Hidden ~= nil,
      "the Yellow manifest ships OLD_MAN2 with the toggle OFF")

-- ------------------------------------------------------- script registry
local talk = mapScripts.talkScript(MAP, "TEXT_VIRIDIANCITY_OLD_MAN2")
check(type(talk) == "function",
      "TEXT_VIRIDIANCITY_OLD_MAN2 resolves to the Yellow handler")
check(type(mapScripts.talkScript(MAP, "TEXT_VIRIDIANCITY_OLD_MAN")) == "table",
      "the Red/Blue OLD_MAN talk is still registered (unreachable in Yellow)")
local hooks = mapScripts.get(MAP)
check(hooks and type(hooks.onEnter) == "function",
      "VIRIDIAN_CITY.onEnter is the Yellow swap")
check(hooks and type(hooks.onStep) == "function",
      "VIRIDIAN_CITY.onStep chains the gym lock and sleeper gate")
check(oldManMod.VIRIDIAN_CITY and oldManMod.VIRIDIAN_CITY.talk
      and oldManMod.VIRIDIAN_CITY.talk.TEXT_VIRIDIANCITY_OLD_MAN2 == talk,
      "the handler is the module's own, not a leftover merge")

-- ------------------------------------------------------- completed branch
do
  local pushed = {}
  local game = {
    data = Data,
    save = SaveData.newGame(),
    stack = { push = function(_, s) pushed[#pushed + 1] = s end },
  }
  game.save.flags.EVENT_COMPLETED_CATCH_TRAINING = true
  local done = false
  talk(game, nil, {}, function() done = true end)
  eq(#pushed, 1, "a second talk only prints one box")
  eq(getmetatable(pushed[1]), TextBox, "the losing-my-touch line, in a box")
  pushed[1].onDone()
  check(done, "closing it hands input back")
end

-- ------------------------------- the initial tutorial, end to end
-- Needs real species in the dataset (the fixture carries only FIX_*);
-- the engine's old-man demo machinery itself is parity_J's territory.
if Data.pokemon.RATTATA and Data.pokemon.PIKACHU then
do
  require("src.render.Font").load(Data)
  local pushed = {}
  local save = SaveData.newGame()
  save.party = { Pokemon.new(Data, "PIKACHU", 12) }
  local moves = {}
  local man = { def = { index = 8, name = OLD_MAN2 } }
  local ow = {
    map = { id = MAP, def = { label = "ViridianCity" } },
    npcs = { man }, entities = { man },
    player = { cellX = 19, cellY = 9, facing = "left" },
    scriptMove = function(_, _, dir, _, cb) moves[#moves + 1] = dir; cb() end,
    npcByIndex = function(_, i) if i == 8 then return man end end,
  }
  local game = {
    data = Data,
    save = save,
    stack = { push = function(_, s) pushed[#pushed + 1] = s end },
  }
  local runner = ScriptRunner.new(game, ow)
  ow.runner = runner
  local done = false
  talk(game, ow, man, function() done = true end)

  eq(#pushed, 1, "the initial talk opens the apology speech")
  eq(getmetatable(pushed[1]), TextBox, "in a text box")
  pushed[1].onDone() -- A: the apology closes, the demo battle starts

  eq(#pushed, 2, "the demo battle starts with no choice in between")
  local battle = pushed[2]
  check(battle and battle.demo, "it is the old-man demo battle")
  eq(battle and battle.enemy and battle.enemy.mon.species, "RATTATA",
     "the demo is a RATTATA in Yellow (#617)")
  check(battle and battle.demoFails,
        "the initial training throw breaks out, never catches (#636)")
  eq(save.flags[DONE_FLAG], nil, "the flag is still clear mid-demo")
  battle.onFinish() -- the battle ends, the post-battle text prints

  eq(save.flags[DONE_FLAG], true, "EVENT_COMPLETED_CATCH_TRAINING is set")
  eq(#pushed, 3, "the losing-my-touch line follows the demo")
  pushed[3].onDone() -- A: the old man walks off

  eq(#moves, 6, "with the player on (19,9) he walks down 6 tiles")
  check(moves[1] == "down" and moves[6] == "down",
        "all six steps are the ViridianCityOldManMovementData2 walk")
  eq(save.objectToggles[MAP] and save.objectToggles[MAP][OLD_MAN2], false,
     "TOGGLE_OLD_MAN_2 hides once the walk finishes")
  check(done, "and the talk hands input back")
end

-- ---------------------------------- side talk: player not on (19,9) cell
do
  local pushed = {}
  local save = SaveData.newGame()
  save.party = { Pokemon.new(Data, "PIKACHU", 12) }
  local moves = {}
  local man = { def = { index = 8, name = OLD_MAN2 } }
  local pika = { def = { index = 99, name = "PIKACHU_FOLLOWER" },
                 pikachuFollower = true }
  local ow = {
    map = { id = MAP, def = { label = "ViridianCity" } },
    npcs = { man, pika }, entities = { man, pika },
    player = { cellX = 18, cellY = 8, facing = "down" },
    scriptMove = function(_, _, dir, _, cb) moves[#moves + 1] = dir; cb() end,
    npcByIndex = function(_, i) if i == 8 then return man elseif i == 99 then return pika end end,
  }
  local game = {
    data = Data,
    save = save,
    stack = { push = function(_, s) pushed[#pushed + 1] = s end },
  }
  local runner = ScriptRunner.new(game, ow)
  ow.runner = runner
  talk(game, ow, man, function() end)
  pushed[1].onDone()
  pushed[2].onFinish()
  pushed[3].onDone()
  eq(moves[1], "right", "Pikachu steps aside first (ViridianCityMovePikachu)")
  eq(moves[2], "right", "then the old man turns right one tile")
  eq(#moves, 2, "and no more")
end
else
  check(true, "fixture dataset: demo-battle flow skipped (no RATTATA)")
end

-- --------------------------------------------------------- the (19,9) step
do
  local pushed = {}
  local save = SaveData.newGame()
  local man = { def = { index = 8, name = OLD_MAN2 } }
  local ow = {
    map = { id = MAP, def = { label = "ViridianCity" } },
    npcs = { man }, entities = { man },
    player = { cellX = 19, cellY = 9, facing = "down" },
    scriptMove = function(_, _, _, _, cb) cb() end,
    npcByIndex = function() end,
  }
  local game = {
    data = Data,
    save = save,
    stack = { push = function(_, s) pushed[#pushed + 1] = s end },
  }
  local runner = ScriptRunner.new(game, ow)
  ow.runner = runner

  check(not hooks.onStep(game, ow, 5, 5),
        "off the trigger cell the step passes through")
  check(hooks.onStep(game, ow, 19, 9),
        "pre-Pokedex the sleeper gate owns (19,9)")
  eq(#pushed, 1, "with the sleepy text box")
  check(save.flags[DONE_FLAG] ~= true, "the tutorial is not running")

  save.flags.EVENT_GOT_POKEDEX = true
  check(hooks.onStep(game, ow, 19, 9),
        "with the Pokedex, (19,9) starts the tutorial")
  eq(man.facing, "right", "the old man faces the player")
  eq(ow.player.facing, "left", "and the player turns to face him")
  eq(#pushed, 2, "the apology box is up")
  check(save.flags[DONE_FLAG] ~= true,
        "no flag until the demo battle actually runs")

  save.flags.EVENT_COMPLETED_CATCH_TRAINING = true
  check(not hooks.onStep(game, ow, 19, 9),
        "once the tutorial is done the cell is quiet again")
end

Data.field.trades = originalTrades
Data.field.oldManBattle = originalOldManBattle
GameVersion.set(oldVersion)

S.finish()
