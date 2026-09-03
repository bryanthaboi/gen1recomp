-- scripts/ViridianCity.asm:245; scripts/ViridianMart.asm:64
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local ScriptRunner = require("src.script.ScriptRunner")

local Yellow = assert(loadfile("data/scripts/yellow_viridian_old_man.lua"))()

local CITY = "VIRIDIAN_CITY"
local SLEEPY = "VIRIDIANCITY_OLD_MAN_SLEEPY"
local OLD_MAN = "VIRIDIANCITY_OLD_MAN"
local OLD_MAN2 = "VIRIDIANCITY_OLD_MAN2"

local function toggles(game)
  return (game.save.objectToggles or {})[CITY] or {}
end

local function fakeGame(flags, cityToggles)
  return {
    save = {
      flags = flags,
      objectToggles = cityToggles and { [CITY] = cityToggles } or {},
      inventory = {},
    },
  }
end

T.check(type(Yellow.VIRIDIAN_CITY.onEnter) == "function",
  "VIRIDIAN_CITY.onEnter exists")

-- scripts/OaksLab.asm:591
do
  local game = fakeGame({ EVENT_GOT_POKEDEX = true })
  Yellow.VIRIDIAN_CITY.onEnter(game, nil)
  T.eq(toggles(game)[SLEEPY], false, "pokedex only: sleeper hidden")
  T.eq(toggles(game)[OLD_MAN2], true, "pokedex only: OLD_MAN2 shown")
  T.eq(toggles(game)[OLD_MAN], false, "pokedex only: OLD_MAN hidden")
end

-- scripts/ViridianCity.asm:249
do
  local game = fakeGame(
    { EVENT_GOT_POKEDEX = true, EVENT_COMPLETED_CATCH_TRAINING = true },
    { [SLEEPY] = false, [OLD_MAN2] = false })
  Yellow.VIRIDIAN_CITY.onEnter(game, { map = { id = CITY, def = { objects = {} } }, npcs = {}, entities = {} })
  T.eq(toggles(game)[OLD_MAN2], false,
    "training done: re-entry keeps OLD_MAN2 hidden")
  T.eq(toggles(game)[OLD_MAN], false,
    "training done, mart not visited: OLD_MAN still hidden")
  T.eq(toggles(game)[SLEEPY], false, "training done: sleeper hidden")
end

-- scripts/ViridianMart.asm:69
do
  local game = fakeGame({
    EVENT_GOT_POKEDEX = true,
    EVENT_COMPLETED_CATCH_TRAINING = true,
    EVENT_SPAWNED_OLD_MAN_1 = true,
  })
  Yellow.VIRIDIAN_CITY.onEnter(game, nil)
  T.eq(toggles(game)[OLD_MAN2], false, "old man 1 spawned: OLD_MAN2 hidden")
  T.eq(toggles(game)[OLD_MAN], true, "old man 1 spawned: OLD_MAN shown")
  T.eq(toggles(game)[SLEEPY], false, "old man 1 spawned: sleeper hidden")
end

do
  local game = fakeGame({})
  Yellow.VIRIDIAN_CITY.onEnter(game, nil)
  T.check(next(toggles(game)) == nil, "no pokedex: onEnter writes nothing")
end

T.check(type(Yellow.VIRIDIAN_MART) == "table"
  and type(Yellow.VIRIDIAN_MART.onEnter) == "function",
  "VIRIDIAN_MART.onEnter exists")

-- scripts/ViridianMart.asm:64
do
  local game = fakeGame({
    EVENT_GOT_STARTER = true,
    EVENT_GOT_OAKS_PARCEL = true,
    EVENT_OAK_GOT_PARCEL = true,
    EVENT_GOT_POKEDEX = true,
    EVENT_COMPLETED_CATCH_TRAINING = true,
  }, { [OLD_MAN2] = false })
  local ow = { map = { id = "VIRIDIAN_MART" }, npcs = {},
               queueScript = function() error("parcel walk-in re-ran") end }
  Yellow.VIRIDIAN_MART.onEnter(game, ow, CITY)
  T.eq(game.save.flags.EVENT_SPAWNED_OLD_MAN_1, true,
    "mart after training: EVENT_SPAWNED_OLD_MAN_1 set")
  T.eq(toggles(game)[OLD_MAN2], false, "mart after training: OLD_MAN2 hidden")
  T.eq(toggles(game)[OLD_MAN], true, "mart after training: OLD_MAN shown")

  game.save.objectToggles = {}
  Yellow.VIRIDIAN_MART.onEnter(game, ow, CITY)
  T.check(next(game.save.objectToggles) == nil,
    "second mart visit: no toggle writes")
end

do
  local game = fakeGame({
    EVENT_GOT_STARTER = true,
    EVENT_GOT_OAKS_PARCEL = true,
    EVENT_OAK_GOT_PARCEL = true,
    EVENT_GOT_POKEDEX = true,
  })
  local ow = { map = { id = "VIRIDIAN_MART" }, npcs = {},
               queueScript = function() error("parcel walk-in re-ran") end }
  Yellow.VIRIDIAN_MART.onEnter(game, ow, CITY)
  T.eq(game.save.flags.EVENT_SPAWNED_OLD_MAN_1, nil,
    "mart before training: flag untouched")
  T.check(next(game.save.objectToggles) == nil,
    "mart before training: no toggle writes")
end

-- scripts/ViridianMart.asm:30
do
  local game = fakeGame({ EVENT_GOT_STARTER = true })
  local queued
  local ow = { map = { id = "VIRIDIAN_MART" }, npcs = {},
               queueScript = function(_, rows) queued = rows end }
  Yellow.VIRIDIAN_MART.onEnter(game, ow, CITY)
  local setsParcel = false
  for _, row in ipairs(queued or {}) do
    if row[1] == "set_flag" and row[2] == "EVENT_GOT_OAKS_PARCEL" then
      setsParcel = true
    end
  end
  T.check(setsParcel, "no parcel yet: the base parcel walk-in still queues")
  T.eq(game.save.flags.EVENT_SPAWNED_OLD_MAN_1, nil,
    "no parcel yet: old man swap does not fire")
end

-- scripts/ViridianCity_2.asm:126
do
  local rows = Yellow.VIRIDIAN_CITY.talk.TEXT_VIRIDIANCITY_OLD_MAN
  T.check(type(rows) == "table", "Yellow TEXT_VIRIDIANCITY_OLD_MAN rows exist")
  local problems = ScriptRunner.validate(rows)
  T.eq(#problems, 0, "rows validate: " .. table.concat(problems, "; "))
  local labels = {}
  for _, row in ipairs(rows) do
    if row[1] == "ask" or row[1] == "show_text" then labels[row[2]] = true end
  end
  T.check(labels._ViridianCityOldManWantMeToShowYouAgainText,
    "asks WantMeToShowYouAgain")
  T.check(labels._ViridianCityOldManWatchCloselyText, "prints WatchClosely")
  T.check(labels._ViridianCityOldManYouNeedToWeakenTheTargetText,
    "prints YouNeedToWeakenTheTarget")
  T.check(labels._ViridianCityOldManNotGoodEnoughForYouText,
    "prints NotGoodEnoughForYou")
  T.check(not labels._ViridianCityOldManHadMyCoffeeNowText,
    "does not reuse the coffee apology")
  local demoFails, setsAgain = nil, false
  for _, row in ipairs(rows) do
    if row[1] == "old_man_demo" then demoFails = row[2] end
    if row[1] == "set_flag" and row[2] == "EVENT_COMPLETED_CATCH_TRAINING_AGAIN" then
      setsAgain = true
    end
  end
  T.eq(demoFails, nil, "the rerun demo catches")
  T.check(setsAgain, "the rerun sets EVENT_COMPLETED_CATCH_TRAINING_AGAIN")
end

T.finish("yellow_viridian_old_man_bug2122")
