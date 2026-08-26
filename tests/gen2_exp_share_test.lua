-- GiveExperiencePoints' three boosts and the EXP.SHARE double pass
-- (engine/battle/core.asm:6747, dispatch at :2099-2130).
--
--   luajit tests/gen2_exp_share_test.lua
--
-- ROM-free.  Traded mons (OT id differs from the player's) earn x1.5 with
-- BoostedExpPointsText; a held LUCKY_EGG is another x1.5, checked by item
-- id; any live EXP.SHARE holder halves the pool up front, participants
-- split the first pass and every holder is paid a second pass -- stat exp
-- included, from the same halved base stats.

package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 exp share")
local check, eq = S.check, S.eq

local Battle = require("src.battle.gen2.Battle")
local Mon = require("src.battle.gen2.Mon")

-- ---------------------------------------------------------------- fixtures

local TYPES = {
  NORMAL = { id = "NORMAL", index = 0, category = "physical" },
}

local MOVES = {
  TACKLE = { id = "TACKLE", name = "TACKLE", power = 35, type = "NORMAL",
    accuracy = 95, pp = 35, effect = "EFFECT_NORMAL_HIT" },
}

local GROWTH = {
  GROWTH_SLOW = { numerator = 5, denominator = 4, squared = 0, linear = 0,
    constant = 0 },
}

local POKEMON = {
  growthRates = GROWTH,
  MACHOP = {
    id = "MACHOP", index = 66, name = "MACHOP",
    baseStats = { hp = 70, attack = 80, defense = 50, speed = 35,
      specialAttack = 35, specialDefense = 35 },
    types = { "NORMAL", "NORMAL" }, catchRate = 180, baseExp = 75,
    growthRate = "GROWTH_SLOW", genderRatio = 63,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
  PIDGEY = {
    id = "PIDGEY", index = 16, name = "PIDGEY",
    baseStats = { hp = 40, attack = 45, defense = 40, speed = 56,
      specialAttack = 35, specialDefense = 35 },
    types = { "NORMAL", "NORMAL" }, catchRate = 255, baseExp = 55,
    growthRate = "GROWTH_SLOW", genderRatio = 127,
    levelMoves = { { level = 1, move = "TACKLE" } }, evolutions = {},
  },
}

local ITEMS = {
  LUCKY_EGG = { id = "LUCKY_EGG", name = "LUCKY EGG",
    heldEffect = "HELD_NONE", heldParameter = 0 },
  EXP_SHARE = { id = "EXP_SHARE", name = "EXP.SHARE",
    heldEffect = "HELD_NONE", heldParameter = 0 },
}

local DATA = {
  pokemon = POKEMON,
  moves = MOVES,
  type_chart = { types = TYPES, matchups = {} },
  items = ITEMS,
}

local perfect = { attack = 15, defense = 15, speed = 15, special = 15 }
perfect.hp = Mon.hpDV(perfect)

local PLAYER_ID = 31337

-- One KO's worth of exp, replayed against a fresh battle each time.
-- `partySpec` rows: { otId =, item =, participant =, hp = }.
local function award(partySpec)
  local party, participants = {}, {}
  for index, spec in ipairs(partySpec) do
    local mon = Mon.new(DATA, "MACHOP", 20, { dvs = perfect })
    mon.otId = spec.otId
    mon.item = spec.item
    if spec.hp then mon.hp = spec.hp end
    party[index] = mon
    if spec.participant then participants[index] = true end
  end
  local wild = Mon.new(DATA, "PIDGEY", 14, { dvs = perfect })
  local battle = Battle.new({ data = DATA, party = party, wild = wild,
    save = { player = { id = PLAYER_ID, badges = {} } },
    random = function(n) return (n or 1) > 1 and 1 or 0 end })
  battle.participants = participants
  local before = {}
  for index, mon in ipairs(party) do before[index] = mon.experience end
  battle:awardExperience(wild)
  local gained = {}
  for index, mon in ipairs(party) do
    gained[index] = mon.experience - before[index]
  end
  return gained, battle:takeEvents(), party
end

-- The wild PIDGEY: baseExp 55, level 14 -> floor(55 * 14 / 7) = 110.
local BASE = 110

-- ---- the native baseline --------------------------------------------------
do
  local gained, events = award({ { otId = PLAYER_ID, participant = true } })
  eq(gained[1], BASE, "a native solo participant earns baseExp * level / 7")
  local boosted = false
  for _, event in ipairs(events) do
    if event.kind == "experience"
        and event.text:find("boosted", 1, true) then
      boosted = true
    end
  end
  eq(boosted, false, "and its line is the plain ExpPointsText")
end

-- ---- the traded 1.5x ------------------------------------------------------
do
  local gained, events = award({ { otId = 48926, participant = true } })
  eq(gained[1], math.floor(BASE * 3 / 2),
    "an outsider mon (ROCKY the Onix's OT, say) earns x1.5")
  local line
  for _, event in ipairs(events) do
    if event.kind == "experience" then line = event.text end
  end
  eq(line, "MACHOP gained a boosted 165 EXP. Points!",
    "with BoostedExpPointsText's own wording")
end

-- ---- the Lucky Egg 1.5x and the stack -------------------------------------
do
  local gained = award({
    { otId = PLAYER_ID, item = "LUCKY_EGG", participant = true } })
  eq(gained[1], math.floor(BASE * 3 / 2), "a held LUCKY EGG is x1.5")

  gained = award({ { otId = 48926, item = "LUCKY_EGG", participant = true } })
  eq(gained[1], math.floor(math.floor(BASE * 3 / 2) * 3 / 2),
    "traded and egg stack to x2.25, floored in the cart's order")
end

-- ---- EXP.SHARE ------------------------------------------------------------
do
  -- Holder on the bench: the pool halves (baseExp 55 -> 27), the fighter
  -- takes the first pass, the holder the second.
  local halved = math.floor(math.floor(55 / 2) * 14 / 7) -- 54
  local gained = award({
    { otId = PLAYER_ID, participant = true },
    { otId = PLAYER_ID, item = "EXP_SHARE" },
  })
  eq(gained[1], halved, "the participant's share is halved")
  eq(gained[2], halved, "the benched holder is paid the second pass")

  -- A holder that fought collects BOTH passes.
  gained = award({
    { otId = PLAYER_ID, item = "EXP_SHARE", participant = true } })
  eq(gained[1], halved * 2, "a fighting holder is paid twice")

  -- Two participants split pass one; the one holder still takes a full
  -- second-pass share.
  gained = award({
    { otId = PLAYER_ID, participant = true },
    { otId = PLAYER_ID, participant = true },
    { otId = PLAYER_ID, item = "EXP_SHARE" },
  })
  local split = math.floor(halved / 2)
  eq(gained[1], split, "two participants split the halved pool")
  eq(gained[2], split, "both of them")
  eq(gained[3], halved, "the lone holder's pass divides by one")

  -- A fainted holder is skipped by the pass loop, and with no live holder
  -- the pool is never halved.
  gained = award({
    { otId = PLAYER_ID, participant = true },
    { otId = PLAYER_ID, item = "EXP_SHARE", hp = 0 },
  })
  eq(gained[1], BASE, "a fainted holder does not tax the pool")
  eq(gained[2], 0, "and earns nothing")
end

-- ---- stat exp rides the same halving --------------------------------------
do
  local _, _, party = award({
    { otId = PLAYER_ID, participant = true },
    { otId = PLAYER_ID, item = "EXP_SHARE" },
  })
  -- PIDGEY base attack 45: halved to 22 for each pass.
  eq(party[1].statExp.attack, 22, "the participant's stat exp is halved")
  eq(party[2].statExp.attack, 22, "the holder earns stat exp too")
  -- And the special word takes the loser's Special ATTACK, halved.
  eq(party[2].statExp.special, math.floor(35 / 2),
    "the special stat exp word follows")

  _, _, party = award({ { otId = PLAYER_ID, participant = true } })
  eq(party[1].statExp.attack, 45, "no holder, no halving")
end

-- ---- Mon.experienceGain's arms stay honest --------------------------------
do
  local def = POKEMON.PIDGEY
  eq(Mon.experienceGain(def, 14, 1, false), BASE, "bare")
  eq(Mon.experienceGain(def, 14, 1, true), math.floor(BASE * 3 / 2),
    "trainer battles boost x1.5, unchanged")
  eq(Mon.experienceGain(def, 14, 1, false, { traded = true, luckyEgg = true }),
    math.floor(math.floor(BASE * 3 / 2) * 3 / 2), "traded + egg")
  eq(Mon.experienceGain(def, 14, 1, false, { halved = true }),
    math.floor(math.floor(55 / 2) * 14 / 7), "the share tax halves baseExp")
  eq(Mon.experienceGain(def, 14, 1, true,
    { halved = true, traded = true, luckyEgg = true }),
    math.floor(math.floor(math.floor(
      math.floor(math.floor(55 / 2) * 14 / 7) * 3 / 2) * 3 / 2) * 3 / 2),
    "all four arms compose in the cart's order")
end

-- ---- battle.exp_award: applyShare's third argument ------------------------
--
-- Gen 1's applyShare(mon, split, announce) pays the mon and prints its
-- GainedText only when `announce` is truthy (src/battle/BattleState.lua).
-- Gold accepted the argument and ignored it, so a mod that pays the whole
-- party -- the Exp Share mod's own documented behaviour -- could not print one
-- summary line here; it got a box per recipient.
--
-- Two tests, per Route B in CONTRIBUTING-mods.md: vanilla is unchanged with no
-- subscriber, and the seam is driven through the public hook API.

local Events = require("src.mods.Events")
local Hooks = require("src.mods.Hooks")
local Runtime = require("src.mods.Runtime")

-- Counts the GainedText boxes an award produced.
local function expLines(events)
  local out = {}
  for _, event in ipairs(events) do
    if event.kind == "experience" then out[#out + 1] = event.text end
  end
  return out
end

local function kindsOf(events)
  local out = {}
  for _, event in ipairs(events) do out[#out + 1] = event.kind end
  return table.concat(out, ",")
end

-- ---- the no-mod test: nothing subscribed, nothing changes -----------------
do
  local _, events = award({ { otId = PLAYER_ID, participant = true } })
  eq(#expLines(events), 1, "no subscriber: a solo participant still prints one line")

  local _, twoPass = award({
    { otId = PLAYER_ID, participant = true },
    { otId = PLAYER_ID, item = "EXP_SHARE" },
  })
  eq(#expLines(twoPass), 2,
    "no subscriber: the EXP.SHARE double pass still prints both lines")
end

-- ---- the mod-API test: driven through hooks:wrap, not internals -----------
do
  local savedEvents, savedHooks = Runtime.events, Runtime.hooks
  local hooks = Hooks.new()
  Runtime.install(Events.new(), hooks)

  -- Each case pays a two-mon party through ctx.applyShare and reports the
  -- GainedText boxes that survived.  The party mon in slot 2 never fights, so
  -- it stands in for the bench a party-wide mod pays.
  local function awardVia(payer)
    local unsub = hooks:wrap("battle.exp_award", function(_nextFn, ctx)
      payer(ctx)
    end)
    local gained, events, party = award({
      { otId = PLAYER_ID, participant = true },
      { otId = PLAYER_ID },
    })
    unsub()
    return gained, events, party
  end

  -- omitted: the Gen 2-era call, which has always announced
  local gained, events = awardVia(function(ctx)
    ctx.applyShare(ctx.battle.party[1], 1)
    ctx.applyShare(ctx.battle.party[2], 1)
  end)
  eq(#expLines(events), 2,
    "applyShare(mon, split) still announces -- no existing mod changes")
  check(gained[1] > 0 and gained[2] > 0, "and both mons were paid")

  -- passed nil: "pay this one quietly", Gen 1's reading
  local quietGained, quietEvents = awardVia(function(ctx)
    ctx.applyShare(ctx.battle.party[1], 1, true)
    ctx.applyShare(ctx.battle.party[2], 1, nil)
  end)
  eq(#expLines(quietEvents), 1,
    "an explicit nil third argument pays the mon silently")
  eq(expLines(quietEvents)[1], "MACHOP gained 110 EXP. Points!",
    "and the announced participant keeps its own line")
  check(quietGained[2] > 0, "the silent mon is still paid the same exp")
  eq(quietGained[1], gained[1], "and the announced mon's exp is untouched")
  eq(quietGained[2], gained[2], "as is the silent one's")

  -- false reads the same as nil; a truthy string is Gen 1's EXP.ALL variant
  local _, falseEvents = awardVia(function(ctx)
    ctx.applyShare(ctx.battle.party[1], 1, false)
  end)
  eq(#expLines(falseEvents), 0, "false is silent too")

  local _, expAllEvents = awardVia(function(ctx)
    ctx.applyShare(ctx.battle.party[1], 1, "expAll")
  end)
  eq(#expLines(expAllEvents), 1,
    "any truthy value announces, so Gen 1's \"expAll\" carries over")

  -- a silent award is still a whole award: only the line goes
  local _, levelEvents, levelParty = awardVia(function(ctx)
    ctx.applyShare(ctx.battle.party[2], 1, nil)
  end)
  eq(#expLines(levelEvents), 0, "the silent pass prints no GainedText")
  check(levelParty[2].statExp.attack > 0,
    "but stat exp is still awarded on a silent pass")
  check(not kindsOf(levelEvents):find("experience", 1, true),
    "and no experience event leaks into the queue")

  Runtime.install(savedEvents, savedHooks)
end

S.finish()
