-- Owned effect registry. Dispatch is driven by ROM gBattleMoves.effect
-- via EffectIds.STATUS_SETUP (see effect_ids.lua). Name fallbacks are last resort.

local Hazards = require("src.core.game3.battle.effects.hazards")
local Screens = require("src.core.game3.battle.effects.screens")
local Stats = require("src.core.game3.battle.effects.stats")
local Status = require("src.core.game3.battle.effects.status")
local Healing = require("src.core.game3.battle.effects.healing")
local Setup = require("src.core.game3.battle.effects.setup")
local Volatiles = require("src.core.game3.battle.effects.volatiles")
local Weather = require("src.core.game3.battle.effects.weather")
local Special = require("src.core.game3.battle.effects.special")
local EffectCtx = require("src.core.game3.battle.effect_ctx")
local Moves = require("src.core.game3.battle.moves")
local EffectIds = require("src.core.game3.battle.effect_ids")

local Effects = {}

local registry = {}

local function reg(id, fn)
  registry[id] = fn
end

-- FRLG-legal handlers only (no Stealth Rock / Trick Room / Aqua Ring / …).
reg("EXP_SPIKES_EFFECT", Hazards.spikes)
reg("EXP_SAFEGUARD_EFFECT", Screens.safeguard)
reg("EXP_REFLECT_EFFECT", Screens.reflect)
reg("EXP_LIGHT_SCREEN_EFFECT", Screens.lightScreen)
reg("EXP_BURN_EFFECT", Status.burn)
reg("EXP_POISON_EFFECT", Status.poison)
reg("EXP_TOXIC_EFFECT", Status.toxic)
reg("EXP_SLEEP_EFFECT", Status.sleep)
reg("EXP_PARALYZE_EFFECT", Status.paralyze)
reg("EXP_TAUNT_EFFECT", Status.taunt)
reg("EXP_YAWN_EFFECT", Status.yawn)
reg("EXP_REFRESH_EFFECT", Healing.refresh)
reg("EXP_INGRAIN_EFFECT", Healing.ingrain)
reg("EXP_RECOVER_EFFECT", Healing.recover)
reg("EXP_SOFTBOILED_EFFECT", Healing.softboiled)
reg("EXP_BELLY_DRUM_EFFECT", Healing.bellyDrum)
reg("EXP_WISH_EFFECT", Healing.wish)
reg("EXP_HEAL_BELL_EFFECT", Healing.healBell)
reg("EXP_PAIN_SPLIT_EFFECT", Healing.painSplit)
reg("EXP_SWALLOW_EFFECT", Healing.swallow)
reg("EXP_MEAN_LOOK_EFFECT", Setup.meanLook)
reg("EXP_LEECH_SEED_EFFECT", Setup.leechSeed)
reg("EXP_DESTINY_BOND_EFFECT", Setup.destinyBond)
reg("EXP_NIGHTMARE_EFFECT", Setup.nightmare)
reg("EXP_FOCUS_ENERGY_EFFECT", Setup.focusEnergy)
reg("EXP_FORESIGHT_EFFECT", Setup.foresight)
reg("EXP_LOCK_ON_EFFECT", Setup.lockOn)
reg("EXP_MAGIC_COAT_EFFECT", Setup.magicCoat)
reg("EXP_GRUDGE_EFFECT", Setup.grudge)
reg("EXP_IMPRISON_EFFECT", Setup.imprison)
reg("EXP_SNATCH_EFFECT", Setup.snatch)
reg("EXP_MUD_SPORT_EFFECT", Setup.mudSport)
reg("EXP_WATER_SPORT_EFFECT", Setup.waterSport)
reg("EXP_CAMOUFLAGE_EFFECT", Setup.camouflage)
reg("EXP_ROLE_PLAY_EFFECT", Setup.rolePlay)
reg("EXP_SKILL_SWAP_EFFECT", Setup.skillSwap)
reg("EXP_FUTURE_SIGHT_EFFECT", Setup.futureSight)
reg("EXP_CURSE_EFFECT", Setup.curse)
reg("EXP_HELPING_HAND_EFFECT", Setup.helpingHand)
reg("EXP_CONFUSE_EFFECT", Setup.confuse)
reg("EXP_HAZE_EFFECT", Setup.haze)
reg("EXP_SUBSTITUTE_EFFECT", Setup.substitute)
reg("EXP_TEETER_DANCE", Setup.teeterDance)
reg("EXP_MIST_EFFECT", Screens.mist)
reg("EXP_REST_EFFECT", Healing.rest)
reg("EXP_SPLASH_EFFECT", Setup.splash)
reg("EXP_BATON_PASS_EFFECT", Special.batonPass)
reg("EXP_ROAR_EFFECT", Special.roar)
reg("EXP_CONVERSION_EFFECT", Special.conversion)
reg("EXP_CONVERSION_2_EFFECT", Special.conversion2)
reg("EXP_TRANSFORM_EFFECT", Special.transform)
reg("EXP_MIMIC_EFFECT", Special.mimic)
reg("EXP_DISABLE_EFFECT", Special.disable)
reg("EXP_SKETCH_EFFECT", Special.sketch)
reg("EXP_TELEPORT_EFFECT", Special.teleport)
reg("EXP_FOLLOW_ME_EFFECT", Special.followMe)
reg("EXP_TRICK_EFFECT", Special.trick)
reg("EXP_RECYCLE_EFFECT", Special.recycle)
reg("EXP_MORNING_SUN_EFFECT", Healing.morningSun)
reg("EXP_MINIMIZE_EFFECT", Stats.minimize)
reg("EXP_DEFENSE_CURL_EFFECT", Stats.defenseCurl)
reg("EXP_PROTECT_EFFECT", Volatiles.protect)
reg("EXP_ENDURE_EFFECT", Volatiles.endure)
reg("EXP_ENCORE_EFFECT", Volatiles.encore)
reg("EXP_PERISH_SONG_EFFECT", Volatiles.perishSong)
reg("EXP_ATTRACT_EFFECT", Volatiles.attract)
reg("EXP_SPITE_EFFECT", Volatiles.spite)
reg("EXP_TORMENT_EFFECT", Volatiles.torment)
reg("EXP_WEATHER_SUNNY", Weather.sunny)
reg("EXP_WEATHER_RAINY", Weather.rainy)
reg("EXP_WEATHER_SANDSTORM", Weather.sandstorm)
reg("EXP_WEATHER_HAIL", Weather.hail)
reg("EXP_STAT_FROM_EFFECT", Stats.fromRomEffect)
reg("EXP_SWAGGER_EFFECT", Stats.swagger)
reg("EXP_FLATTER_EFFECT", Stats.flatter)
reg("EXP_PSYCH_UP_EFFECT", Stats.psychUp)
reg("EXP_STOCKPILE_EFFECT", Stats.stockpile)
reg("EXP_CHARGE_EFFECT", Stats.charge)
reg("EXP_MEMENTO_EFFECT", Stats.memento)
reg("EXP_TICKLE_EFFECT", Stats.tickle)
reg("EXP_COSMIC_POWER_EFFECT", Stats.cosmicPower)
reg("EXP_CALM_MIND", Stats.calmMind)
reg("EXP_BULK_UP", Stats.bulkUp)
reg("EXP_DRAGON_DANCE", Stats.dragonDance)

function Effects.get(id)
  return registry[id]
end

function Effects.run(id, adapter, user, target, move, moveId, moveCtx)
  local fn = registry[id]
  if not fn then return false end
  local ctx = EffectCtx.push(adapter, user, target, move, moveId or id, adapter:rng(), moveCtx)
  local ok, err = pcall(fn, ctx)
  EffectCtx.pop()
  if not ok then error(err, 0) end
  return true
end

--- Prefer ROM effect byte → STATUS_SETUP.
function Effects.runForMove(adapter, user, target, moveId, moveCtx)
  local move = (moveCtx and moveCtx.move) or Moves.get(moveId)
  local effectByte = tonumber(move and move.effect)
  local effectId = effectByte and EffectIds.STATUS_SETUP[effectByte]
  if not effectId then return false end
  return Effects.run(effectId, adapter, user, target, move, moveId, moveCtx)
end

function Effects.ids()
  local out = {}
  for id in pairs(registry) do out[#out + 1] = id end
  table.sort(out)
  return out
end

return Effects
