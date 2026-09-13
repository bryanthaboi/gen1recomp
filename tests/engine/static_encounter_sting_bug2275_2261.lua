-- pokered/home/trainers.asm:123
-- pokered/home/text_script.asm:96

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local check, eq = T.check, T.eq
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
Data.text = {}

local Sound = require("src.core.Sound")
local Music = require("src.core.Music")
local Commands = require("src.script.Commands")
local ScriptRunner = require("src.script.ScriptRunner")

local frame = 0
local CRY_FRAMES = 30
local cryEndedAt
local cries = {}
Sound.playCry = function(_, species)
  local endAt = frame + CRY_FRAMES
  cries[#cries + 1] = species
  return {
    getDuration = function() return CRY_FRAMES / 60 end,
    getPitch = function() return 1 end,
    stop = function() end,
    isPlaying = function()
      local playing = frame < endAt
      if not playing and not cryEndedAt then cryEndedAt = frame end
      return playing
    end,
  }
end
Sound.play = function() return nil end
Sound.playPress = function() return nil end

local songs = {}
Music.play = function(_, song)
  songs[#songs + 1] = { song = song, frame = frame, cryEndedAt = cryEndedAt }
end

local battles = {}
Commands.start_battle = function(ctx, kind, species, level)
  battles[#battles + 1] = { kind = kind, species = species, level = level,
                            songs = #songs }
  ctx.lastBattleResult = "win"
end

local stack = { states = {} }
function stack:push(s) self.states[#self.states + 1] = s end
function stack:pop() return table.remove(self.states) end
function stack:top() return self.states[#self.states] end

local pressed = {}
local game = {
  data = Data,
  save = { flags = {}, player = { name = "RED" }, options = { textSpeed = 1 } },
  stack = stack,
  input = {
    wasPressed = function(_, key) return pressed[key] or false end,
    isDown = function() return false end,
  },
}

local runner
local function step(btn)
  frame = frame + 1
  pressed = btn and { [btn] = true } or {}
  local top = stack:top()
  if top then top:update(1 / 60) end
  pressed = {}
  runner:update()
end

local function load(path, mapId, textId)
  local mod = assert(loadfile(path))()
  return mod[mapId].talk[textId]
end

local function start(script)
  stack.states, songs, battles, cries, cryEndedAt = {}, {}, {}, {}, nil
  runner = ScriptRunner.new(game, nil)
  runner:run(script, { npc = { def = {} } })
end

local CASES = {
  { "data/scripts/flavor/seafoam_islands_b4f.lua", "SEAFOAM_ISLANDS_B4F",
    "TEXT_SEAFOAMISLANDSB4F_ARTICUNO", "ARTICUNO", "EVENT_BEAT_ARTICUNO" },
  { "data/scripts/flavor/power_plant.lua", "POWER_PLANT",
    "TEXT_POWERPLANT_ZAPDOS", "ZAPDOS", "EVENT_BEAT_ZAPDOS" },
  { "data/scripts/flavor/victory_road_2f.lua", "VICTORY_ROAD_2F",
    "TEXT_VICTORYROAD2F_MOLTRES", "MOLTRES", "EVENT_BEAT_MOLTRES" },
  { "data/scripts/flavor/cerulean_cave_b1f.lua", "CERULEAN_CAVE_B1F",
    "TEXT_CERULEANCAVEB1F_MEWTWO", "MEWTWO", "EVENT_BEAT_MEWTWO" },
  { "data/scripts/flavor/power_plant.lua", "POWER_PLANT",
    "TEXT_POWERPLANT_VOLTORB1", nil, "EVENT_BEAT_POWER_PLANT_VOLTORB_0",
    "VOLTORB" },
}

for _, c in ipairs(CASES) do
  local path, mapId, textId, crySpecies, flag = c[1], c[2], c[3], c[4], c[5]
  local species = c[6] or crySpecies
  local script = load(path, mapId, textId)
  check(type(script) == "table", textId .. " resolves")

  game.save.flags = {}
  start(script)
  for _ = 1, 400 do step() end
  eq(#battles, 0, textId .. ": no battle before A/B")
  check(stack:top() ~= nil, textId .. ": box still up without a press")
  eq(#songs, 1, textId .. ": one engage sting while the box waits")
  eq(songs[1] and songs[1].song, "Music_MeetMaleTrainer",
     textId .. ": sting is Music_MeetMaleTrainer")
  if crySpecies then
    eq(cries[1], crySpecies, textId .. ": cry plays")
    check(songs[1] and songs[1].cryEndedAt ~= nil
          and songs[1].frame >= songs[1].cryEndedAt,
          textId .. ": sting starts after the cry finishes")
  else
    eq(#cries, 0, textId .. ": no cry")
  end
  step("a")
  for _ = 1, 10 do step() end
  check(not runner:isRunning(), textId .. ": script finishes after A")
  eq(#battles, 1, textId .. ": one battle after A")
  eq(battles[1] and battles[1].species, species, textId .. ": battle species")
  eq(battles[1] and battles[1].songs, 1, textId .. ": sting precedes battle")
  check(game.save.flags[flag] == true, textId .. ": beat flag set")

  start(script)
  for _ = 1, 400 do step() end
  check(stack:top() ~= nil, textId .. " beaten: box waits for A/B")
  if crySpecies then
    eq(cries[1], crySpecies, textId .. " beaten: cry still plays")
  end
  step("a")
  for _ = 1, 10 do step() end
  check(not runner:isRunning(), textId .. " beaten: script finishes after A")
  eq(#songs, 0, textId .. " beaten: no sting")
  eq(#battles, 0, textId .. " beaten: no battle")
end

T.finish("static_encounter_sting_bug2275_2261")
