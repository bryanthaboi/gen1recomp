-- (engine/battle/core.asm:3718) for these
-- straight to JumpMoveEffect (core.asm:3125, :3213) and a 0-BP move bails
-- out of damage at core.asm:3146 before MoveHitTest
-- prints its own: PrintDidntAffectText for SleepEffect (effects.asm:57,67),
-- PoisonEffect (:113,159) and ParalyzeEffect_ (move_effects/paralyze.asm:33,40);
-- ConditionalPrintButItFailed for ConfusionEffect (effects.asm:1158),
-- for LeechSeedEffect_ (move_effects/leech_seed.asm:28-32)
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not (Data.moves and Data.moves.HYPNOSIS) then Data:load() end
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)

local Font = require("src.render.Font")
if not pcall(Font.encode, "A") then Font.load(Data) end

local Game = require("src.core.Game")
Game.data = Data
Game.save = require("src.core.SaveData").newGame()

local Pokemon = require("src.pokemon.Pokemon")
local BattleState = require("src.battle.BattleState")
local strip = require("src.render.TextBox").strip
local S = require("tests.harness").suite("parity status move failure")
local check, eq = S.check, S.eq

local function freshBattle(species, rng)
  Game.save.options.animations = true
  Game.save.party = { Pokemon.new(Data, "SQUIRTLE", 30) }
  local tb = BattleState.newWild(Game, species or "PIDGEY", 10)
  tb.queue, tb.nextInsert = {}, 0
  tb.rng = rng or function(a, b) return b end
  return tb
end

local function texts(tb)
  local out = {}
  for _, row in ipairs(tb.queue) do
    if row.text then out[#out + 1] = strip(row.text):gsub("%s+$", "") end
  end
  return out
end

local function say(moveId, opts)
  opts = opts or {}
  local tb = freshBattle(opts.species, opts.rng)
  local user = opts.enemy and tb.enemy or tb.player
  local target = opts.enemy and tb.player or tb.enemy
  if opts.before then opts.before(tb, user, target) end
  tb:performMove(user, target, { id = moveId, pp = 10 }, false)
  local lines = texts(tb)
  return lines[#lines] or "", tb
end

local function has(line, needle)
  return line:find(needle, 1, true) ~= nil
end

do
  for _, id in ipairs({ "HYPNOSIS", "POISONPOWDER", "THUNDER_WAVE" }) do
    local line = say(id)
    check(has(line, "didn't affect"),
          id .. " miss prints DidntAffectText, got: " .. line)
    check(not has(line, "attack missed"),
          id .. " miss must not print AttackMissedText (#2282), got: " .. line)
  end
  eq(Data.moves.HYPNOSIS.effect, "SLEEP_EFFECT", "HYPNOSIS is SLEEP_EFFECT")
  eq(Data.moves.POISONPOWDER.effect, "POISON_EFFECT", "POISONPOWDER is POISON_EFFECT")
  eq(Data.moves.THUNDER_WAVE.effect, "PARALYZE_EFFECT", "THUNDER WAVE is PARALYZE_EFFECT")
end

do
  for _, id in ipairs({ "CONFUSE_RAY", "DISABLE", "GROWL", "SAND_ATTACK" }) do
    local line = say(id)
    check(has(line, "But, it failed!"),
          id .. " miss prints ButItFailedText, got: " .. line)
    check(not has(line, "attack missed"),
          id .. " miss must not print AttackMissedText, got: " .. line)
  end
end

-- the enemy-only 25% stat-down whiff -- engine/battle/effects.asm:552-555
do
  local line = say("GROWL", { enemy = true, rng = function() return 0 end })
  check(has(line, "But, it failed!"),
        "the foe's 25% stat-down whiff prints ButItFailedText, got: " .. line)
end

do
  local line = say("LEECH_SEED")
  check(has(line, "evaded attack"),
        "a missed LEECH SEED prints EvadedAttackText, got: " .. line)

  -- leech_seed.asm:14-20
  local grass = say("LEECH_SEED", { species = "BULBASAUR",
                                    rng = function(a) return a end })
  check(has(grass, "evaded attack"),
        "LEECH SEED on a Grass-type prints EvadedAttackText, got: " .. grass)

  -- leech_seed.asm:21-24
  local again = say("LEECH_SEED", { rng = function(a) return a end,
                                    before = function(_, _, target)
                                      target.leechSeeded = true
                                    end })
  check(has(again, "evaded attack"),
        "re-seeding prints EvadedAttackText, got: " .. again)
end

do
  local line = say("TACKLE")
  check(has(line, "attack missed"),
        "a real accuracy miss on a damaging move still prints AttackMissedText, got: " .. line)
end

do
  local prev = Data.move_effects
  local records = {}
  for id, record in pairs(require("src.battle.MoveEffects").RECORDS) do
    records[id] = record
  end
  records.MODKIT_TEST_EFFECT = { kind = "primary", accuracyChecked = true,
                                 run = function() return {} end }
  Data.move_effects = records
  Data.moves.MODKIT_TEST_MOVE = { id = "MODKIT_TEST_MOVE", name = "MODTEST",
                                  type = "NORMAL_TYPE", power = 0, pp = 10,
                                  accuracy = 60, effect = "MODKIT_TEST_EFFECT" }
  local ok, line = pcall(say, "MODKIT_TEST_MOVE")
  Data.move_effects = prev
  Data.moves.MODKIT_TEST_MOVE = nil
  check(ok, "a mod-registered status effect resolves: " .. tostring(line))
  check(has(line, "attack missed"),
        "an unmapped record keeps AttackMissedText, got: " .. tostring(line))
end
