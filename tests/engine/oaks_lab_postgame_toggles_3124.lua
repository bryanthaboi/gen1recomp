-- scripts/OaksLab.asm:66-76, :320, :480, :635, :766-783, :918
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local Commands = require("src.script.Commands")

local Red = assert(loadfile("data/scripts/oaks_lab.lua"))()
local Yellow = assert(loadfile("data/scripts/oaks_lab_yellow.lua"))()

local writes = 0
local realShow, realHide = Commands.show_object, Commands.hide_object
Commands.show_object = function(...) writes = writes + 1 return realShow(...) end
Commands.hide_object = function(...) writes = writes + 1 return realHide(...) end

local function snapshot(save)
  local out = {}
  for k, v in pairs(save.objectToggles.OAKS_LAB or {}) do out[#out + 1] = k .. "=" .. tostring(v) end
  table.sort(out)
  return table.concat(out, " ")
end

local function newGame(flags, toggles)
  return {
    save = {
      flags = flags or {},
      objectToggles = { OAKS_LAB = toggles or {} },
      bag = {},
      ownedCount = 1,
    },
  }
end

local function stubOw(game, opts)
  opts = opts or {}
  local ow = {
    map = {
      id = opts.mapId or "NOT_THE_LAB",
      def = { objects = {} },
      inBounds = function() return true end,
      isWalkableCell = function() return true end,
    },
    npcs = opts.npcs or {},
    entities = {},
    player = { cellX = 5, cellY = 3 },
    captured = nil,
  }
  ow.runner = {
    running = opts.running or false,
    isRunning = function(self) return self.running end,
    run = function(_, rows) ow.captured = rows end,
  }
  function ow.npcByIndex(_, i)
    return { cellX = 4, cellY = 3, px = 64, py = 48, index = i }
  end
  return ow
end

local function exec(game, rows, ow)
  local save = game.save
  local labels = {}
  for i, row in ipairs(rows) do
    if row[1] == "label" then labels[row[2]] = i end
  end
  local ctx = { save = save, game = game, overworld = ow }
  local pc, last, guard, out = 1, nil, 0, {}
  while pc <= #rows and guard < 1000 do
    guard = guard + 1
    local row = rows[pc]
    local verb, jump = row[1], nil
    if verb == "check_flag" then last = save.flags[row[2]] == true
    elseif verb == "set_flag" then save.flags[row[2]] = true
    elseif verb == "clear_flag" then save.flags[row[2]] = nil
    elseif verb == "check_item" then last = (save.bag[row[2]] or 0) > 0
    elseif verb == "take_item" then save.bag[row[2]] = nil
    elseif verb == "check_dex_owned" then last = save.ownedCount >= row[2]
    elseif verb == "ask" or verb == "check_battle_result" then last = true
    elseif verb == "hide_object" then Commands.hide_object(ctx, row[2], row[3])
    elseif verb == "show_object" then Commands.show_object(ctx, row[2], row[3])
    elseif verb == "show_text" then out[#out + 1] = row[2]
    elseif verb == "dex_rating" then out[#out + 1] = "<dex_rating>"
    elseif verb == "jump" then jump = row[2]
    elseif verb == "jump_if_true" then if last then jump = row[2] end
    elseif verb == "jump_if_false" then if not last then jump = row[2] end
    end
    if jump == "end" then break
    elseif type(jump) == "string" then pc = labels[jump]
    elseif type(jump) == "number" then pc = jump
    else pc = pc + 1 end
  end
  return table.concat(out, "|")
end

local function assertNoop(M, game, stage)
  local before = snapshot(game.save)
  writes = 0
  M.onEnter(game, stubOw(game))
  T.eq(writes, 0, stage .. ": onEnter writes no toggle")
  T.eq(snapshot(game.save), before, stage .. ": OAKS_LAB toggles unchanged")
end

local function escort(game)
  local ctx = { save = game.save, game = game }
  Commands.show_object(ctx, "OAKS_LAB", "OAKSLAB_OAK2")
  Commands.hide_object(ctx, "OAKS_LAB", "OAKSLAB_OAK2")
  Commands.show_object(ctx, "OAKS_LAB", "OAKSLAB_OAK1")
  game.save.flags.EVENT_FOLLOWED_OAK_INTO_LAB = true
  game.save.flags.EVENT_FOLLOWED_OAK_INTO_LAB_2 = true
end

local function postgame(game)
  for _, f in ipairs({ "EVENT_BEAT_ROUTE22_RIVAL_1ST_BATTLE", "EVENT_BEAT_BROCK",
                       "EVENT_BEAT_LANCE", "EVENT_BEAT_CHAMPION_RIVAL" }) do
    game.save.flags[f] = true
  end
  game.save.ownedCount = 151
end

for _, sp in ipairs({ "CHARMANDER", "SQUIRTLE", "BULBASAUR" }) do
  local game = newGame()
  local tag = "red " .. sp
  assertNoop(Red, game, tag .. " before escort")
  escort(game)
  assertNoop(Red, game, tag .. " after escort")
  exec(game, Red.talk["TEXT_OAKSLAB_" .. sp .. "_POKE_BALL"], stubOw(game))
  T.eq(game.save.flags["EVENT_CHOSE_" .. sp], true, tag .. ": starter chosen through the ball rows")
  assertNoop(Red, game, tag .. " after the pick")
  local ow = stubOw(game)
  T.check(Red.onStep(game, ow, 5, 6) == true and ow.captured ~= nil, tag .. ": lab battle rows queued")
  exec(game, ow.captured, ow)
  T.eq(game.save.flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB, true, tag .. ": lab battle flag set")
  assertNoop(Red, game, tag .. " after the lab battle")
  game.save.bag.OAKS_PARCEL = 1
  exec(game, Red.talk.TEXT_OAKSLAB_OAK1, stubOw(game))
  T.eq(game.save.flags.EVENT_GOT_POKEDEX, true, tag .. ": parcel scene gave the Pokedex")
  assertNoop(Red, game, tag .. " after the Pokedex")
  postgame(game)
  assertNoop(Red, game, tag .. " after the Champion")
end

do
  local game = newGame({
    EVENT_FOLLOWED_OAK_INTO_LAB = true, EVENT_FOLLOWED_OAK_INTO_LAB_2 = true,
    EVENT_GOT_STARTER = true, EVENT_CHOSE_SQUIRTLE = true,
    EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true, EVENT_GOT_POKEDEX = true,
    EVENT_BEAT_CHAMPION_RIVAL = true,
  }, {
    OAKSLAB_RIVAL = true, OAKSLAB_OAK1 = false, OAKSLAB_OAK2 = true,
    OAKSLAB_CHARMANDER_POKE_BALL = false, OAKSLAB_SQUIRTLE_POKE_BALL = false,
    OAKSLAB_BULBASAUR_POKE_BALL = false,
  })
  game.save.ownedCount = 151
  local rival = { def = { name = "OAKSLAB_RIVAL" }, id = "OAKS_LAB_obj_1" }
  local ow = stubOw(game, { mapId = "OAKS_LAB", npcs = { rival } })
  ow.entities = { rival }
  ow.npcPool = { [rival.id] = rival }
  Red.onEnter(game, ow)
  local t = game.save.objectToggles.OAKS_LAB
  T.eq(t.OAKSLAB_OAK1, true, "red broken table: Oak1 shown")
  T.eq(t.OAKSLAB_OAK2, false, "red broken table: Oak2 hidden")
  T.eq(t.OAKSLAB_RIVAL, false, "red broken table: rival hidden")
  T.eq(#ow.npcs, 0, "red broken table: rival sprite removed on entry")
  T.eq(t.OAKSLAB_SQUIRTLE_POKE_BALL, false, "red broken table: player's ball hidden")
  T.eq(t.OAKSLAB_BULBASAUR_POKE_BALL, false, "red broken table: rival's ball hidden")
  T.eq(t.OAKSLAB_CHARMANDER_POKE_BALL, true, "red broken table: third ball back on the table")
  T.eq(exec(game, Red.talk.TEXT_OAKSLAB_OAK1, ow),
    "_OaksLabOak1HowIsYourPokedexComingText|<dex_rating>",
    "red broken table: Oak rates the Pokedex")

  local g2 = newGame(game.save.flags, { OAKSLAB_OAK1 = false, OAKSLAB_OAK2 = false })
  Red.onEnter(g2, stubOw(g2))
  T.eq(g2.save.objectToggles.OAKS_LAB.OAKSLAB_OAK1, true, "red Oak2 already hidden: Oak1 shown")
  T.eq(g2.save.objectToggles.OAKS_LAB.OAKSLAB_RIVAL, false, "red Oak2 already hidden: rival hidden")
end

do
  local game = newGame({ EVENT_FOLLOWED_OAK_INTO_LAB = true, EVENT_GOT_STARTER = true,
                         EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true }, { OAKSLAB_RIVAL = true })
  Red.onEnter(game, stubOw(game, { running = true }))
  T.eq(game.save.objectToggles.OAKS_LAB.OAKSLAB_RIVAL, true,
    "red: rival left alone while a script is running")
end

do
  local function rival(flags)
    return exec(newGame(flags), Red.talk.TEXT_OAKSLAB_RIVAL, nil)
  end
  T.eq(rival({}), "_OaksLabRivalGrampsIsntAroundText", "red rival: before the escort")
  T.eq(rival({ EVENT_FOLLOWED_OAK_INTO_LAB_2 = true }),
    "_OaksLabRivalGoAheadAndChooseText", "red rival: escorted, no starter")
  T.eq(rival({ EVENT_FOLLOWED_OAK_INTO_LAB_2 = true, EVENT_GOT_STARTER = true }),
    "_OaksLabRivalMyPokemonLooksStrongerText", "red rival: with starter")
  T.eq(rival({ EVENT_FOLLOWED_OAK_INTO_LAB_2 = true, EVENT_GOT_STARTER = true,
               EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true, EVENT_BEAT_CHAMPION_RIVAL = true }),
    "_OaksLabRivalMyPokemonLooksStrongerText", "red rival: after the lab battle")
  for _, row in ipairs(Red.talk.TEXT_OAKSLAB_RIVAL) do
    T.check(row[2] ~= "_OaksLabRivalFedUpWithWaitingText", "red rival: no fed-up-with-waiting row")
  end
end

do
  local game = newGame()
  assertNoop(Yellow, game, "yellow before escort")
  escort(game)
  assertNoop(Yellow, game, "yellow after escort")
  game.save.flags.EVENT_OAK_ASKED_TO_CHOOSE_MON = true
  local ow = stubOw(game)
  Yellow.talk.TEXT_OAKSLAB_EEVEE_POKE_BALL(game, ow, {}, function() end)
  T.check(ow.captured ~= nil, "yellow: eevee snatch rows queued")
  exec(game, ow.captured or {}, ow)
  T.eq(game.save.flags.EVENT_GOT_STARTER, true, "yellow: starter given through the snatch rows")
  T.eq(game.save.objectToggles.OAKS_LAB.OAKSLAB_EEVEE_POKE_BALL, false, "yellow: eevee ball hidden")
  assertNoop(Yellow, game, "yellow after the pick")
  ow = stubOw(game)
  T.check(Yellow.onStep(game, ow, 5, 6) == true and ow.captured ~= nil, "yellow: lab battle rows queued")
  exec(game, ow.captured, ow)
  assertNoop(Yellow, game, "yellow after the lab battle")
  game.save.bag.OAKS_PARCEL = 1
  exec(game, Yellow.talk.TEXT_OAKSLAB_OAK1, stubOw(game))
  T.eq(game.save.flags.EVENT_GOT_POKEDEX, true, "yellow: parcel scene gave the Pokedex")
  assertNoop(Yellow, game, "yellow after the Pokedex")
  postgame(game)
  assertNoop(Yellow, game, "yellow after the Champion")
end

do
  local game = newGame({
    EVENT_FOLLOWED_OAK_INTO_LAB = true, EVENT_FOLLOWED_OAK_INTO_LAB_2 = true,
    EVENT_GOT_STARTER = true, EVENT_BATTLED_RIVAL_IN_OAKS_LAB = true,
    EVENT_GOT_POKEDEX = true, EVENT_BEAT_CHAMPION_RIVAL = true,
  }, { OAKSLAB_RIVAL = true, OAKSLAB_OAK1 = false, OAKSLAB_OAK2 = true,
       OAKSLAB_EEVEE_POKE_BALL = true })
  game.save.ownedCount = 151
  Yellow.onEnter(game, stubOw(game))
  local t = game.save.objectToggles.OAKS_LAB
  T.eq(t.OAKSLAB_OAK1, true, "yellow broken table: Oak1 shown")
  T.eq(t.OAKSLAB_OAK2, false, "yellow broken table: Oak2 hidden")
  T.eq(t.OAKSLAB_RIVAL, false, "yellow broken table: rival hidden")
  T.eq(t.OAKSLAB_EEVEE_POKE_BALL, false, "yellow broken table: eevee ball hidden")
  T.eq(exec(game, Yellow.talk.TEXT_OAKSLAB_OAK1, nil),
    "_OaksLabOak1HowIsYourPokedexComingText|<dex_rating>",
    "yellow broken table: Oak rates the Pokedex")
  T.eq(exec(newGame({ EVENT_GOT_STARTER = true }), Yellow.talk.TEXT_OAKSLAB_RIVAL, nil),
    "_OaksLabRivalGrampsIsntAroundText", "yellow rival: FOLLOWED_OAK_INTO_LAB_2 checked first")
end

T.finish("oaks_lab_postgame_toggles_3124")
