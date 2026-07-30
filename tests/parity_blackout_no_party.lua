-- Parity: starting a battle with no useable POKeMON blacks the player out,
-- it does not cancel the battle (#425).  pokered's .checkAnyPartyAlive
-- (engine/battle/core.asm:158-162) runs after EnemySendOutFirstMon and the
-- 40-frame delay -- the battle has already begun -- and jumps to
-- HandlePlayerBlackOut (core.asm:1145-1166), which prints
-- PlayerBlackedOutText2 (data/text/text_2.asm:896) and drops through to the
-- overworld blackout warp (home/overworld.asm:335-360).  Cancelling instead
-- left the battle theme looping, the party at 0 HP and no warp, so every
-- later encounter took the same exit.
-- Self-contained; run via `luajit tests/parity_blackout_no_party.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end
local S = require("tests.harness").suite("parity blackout no party")
local check, eq = S.check, S.eq

require("src.render.Font").load(Data)
local Game        = require("src.core.Game")
local Input       = require("src.core.Input")
local StateStack  = require("src.core.StateStack")
local Renderer    = require("src.render.Renderer")
local SaveData    = require("src.core.SaveData")
local Pokemon     = require("src.pokemon.Pokemon")
local Music       = require("src.core.Music")
local Runtime     = require("src.mods.Runtime")
local TextBox     = require("src.render.TextBox")
local BattleState = require("src.battle.BattleState")
local OW          = require("src.world.OverworldController")

local MAP = "ROUTE_1"
local MAP_SONG = Data.audio.mapSongs[MAP]
local WILD_SONG = Data.audio.battle.wild

-- every song request in order: "the theme was never restored" and "the theme
-- was never started" have to read differently.  Music.playMap still sets the
-- state Music.restoreMap reads, so the real restore path is under test.
local songs = {}
Music.play = function(_, song) songs[#songs + 1] = song end
local function lastSong() return songs[#songs] end
-- run_tests.lua dofiles the parity files into one process and other suites
-- leave Music.playBattle a no-op, so stand in for its body here: one
-- Music.play of audio.battle[kind] (src/core/Music.lua:350-357)
Music.playBattle = function(data, kind)
  local b = data.audio.battle
  Music.play(data, b[kind] or b.wild)
end

local events = { listeners = {} }
function events:emit(name, payload)
  self.listeners[name] = payload
end
function events:removeOwner() end
Runtime.install(events, Runtime.hooks)

Game.data = Data
Game.input = Input; Input:init()
Game.renderer = Renderer; Renderer:init()
Game.stack = StateStack; StateStack:init()

local warp
local function newWorld(mapId)
  while Game.stack:top() do Game.stack:pop() end
  Game.stack:push(OW, mapId, 5, 5, "down")
  local ow = Game.stack:top()
  Game.overworld = ow
  -- the real one runs a Transition; only the destination matters here
  ow.startWarpTo = function(self, map, x, y, facing)
    warp = { map = map, x = x, y = y, facing = facing }
    self.transitioning = false
  end
  Music.playMap(Data, mapId)
  return ow
end

-- a wild encounter as OverworldState:checkEncounter builds it (:3182-3194)
local function encounter(ow)
  local battle = BattleState.newWild(Game, "PIDGEY", 3)
  local got
  battle.onFinish = function(result)
    got = result
    ow:afterBattle(result, battle)
  end
  return battle, function() return got end
end

Game.save = SaveData.newGame()
Game.save.player.name = "RED"
Game.save.money = 3000
Game.save.party = { Pokemon.new(Data, "MAGIKARP", 10) }
Game.save.party[1].hp = 0
local full = Game.save.party[1].stats.hp
Game.save.lastHeal = { map = "VIRIDIAN_POKECENTER", x = 3, y = 3,
                       outdoor = { id = "VIRIDIAN_CITY", x = 17, y = 8 } }

local ow = newWorld(MAP)
eq(lastSong(), MAP_SONG, MAP .. " is playing its own theme before the step")

local battle, result = encounter(ow)
eq(battle.dead, true, "the constructor still flags a partyless wild battle")
eq(battle.player, nil, "and installs no player battler (Party.firstHealthy)")

-- pushBattle starts the theme with the wipe, before enter() ever runs
-- (:660-679, audio/play_battle_music.asm), which is why a cancelled battle
-- left the battle music looping over the map
ow:pushBattle(battle)
eq(lastSong(), WILD_SONG, "the wipe has already started the battle theme")
Game.stack:pop() -- the transition; its callback pushes the battle below

Game.stack:push(battle)
eq(Game.stack:top() ~= battle, true, "enter() takes the battle back off the stack")
eq(lastSong(), MAP_SONG, "and restores the map theme instead of looping the battle one")
eq(battle.result, "lose", "the battle resolves as a loss, not a skip")
local ended = events.listeners["battle.ended"]
check(ended ~= nil and ended.result == "lose",
      "battle.ended reports a loss for mods too")

local box = Game.stack:top()
check(getmetatable(box) == TextBox, "the blackout text is on screen over the map")
local lines = {}
for _, page in ipairs(box and box.pages or {}) do
  for _, line in ipairs(page) do lines[#lines + 1] = line end
end
local text = table.concat(lines, " / ")
check(text:find("RED", 1, true) ~= nil, "the text names the player")
check(text:find("out of", 1, true) ~= nil and text:find("POK", 1, true) ~= nil,
      "PlayerBlackedOutText2 line 1: <PLAYER> is out of useable POKeMON!")
check(text:find("blacked", 1, true) ~= nil,
      "PlayerBlackedOutText2 line 2: <PLAYER> blacked out!")

-- the cancel path called onFinish itself, with no box to dismiss
if box and box.onDone then box.onDone() end
eq(result(), "lose", "onFinish gets \"lose\", so afterBattle blacks out")
eq(Game.save.party[1].hp, full, "the party is revived at the heal point")
eq(Game.save.money, 1500, "half the money is lost, as on any blackout")
check(warp ~= nil and warp.map == "VIRIDIAN_POKECENTER",
      "and the player is warped to the last heal point")
-- the brick: before #425 the party was still at 0 HP here, so this second
-- encounter took the same exit, and so did every one after it
local ow2 = newWorld(MAP)
local live = BattleState.newWild(Game, "PIDGEY", 3)
eq(live.dead, nil, "the next encounter is a real battle again")
check(live.player ~= nil, "with the revived MAGIKARP leading it")

-- Oak's Lab starter rival: HandlePlayerBlackOut rets above
-- PlayerBlackedOutText2 (core.asm:1147-1149) and the lab script heals, so
-- there is no text, no money loss and no warp.
Game.save.money = 3000
Game.save.party[1].hp = 0
local lab = newWorld("OAKS_LAB")
warp = nil
local labResult
local rival = BattleState.newTrainer(Game, "OPP_RIVAL1", 1)
rival.onFinish = function(r) labResult = r lab:afterBattle(r, rival) end
eq(rival.dead, true, "a partyless lab rival battle is flagged the same way")
Game.stack:push(rival)
check(getmetatable(Game.stack:top()) ~= TextBox,
      "the lab rival prints no blackout text (core.asm:1147-1149)")
eq(labResult, "lose", "it still finishes as a loss")
eq(Game.save.money, 3000, "no money is lost in the lab")
eq(warp, nil, "and the player stays in the lab for OaksLabRivalEndBattleScript")

S.finish()
