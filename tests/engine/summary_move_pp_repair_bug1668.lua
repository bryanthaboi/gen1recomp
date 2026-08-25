-- A Gen 1 move slot stores current PP in six bits of one byte and the PP Up
-- count in the other two (constants/pokemon_data_constants.asm:101-102), and
-- the status screen reads it back with `and PP_MASK` before PrintNumber
-- (engine/pokemon/status_screen.asm:357-365), so "not a number" is not a state
-- the hardware record can hold and the load-time repair must normalize it.
-- Max PP follows GetMaxPP/AddBonusPP (engine/items/item_effects.asm:2467,
-- 2418).  #1668

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local SaveData = require("src.core.SaveData")

local data = {
  pokemon = { FIXMON_A = { id = "FIXMON_A", name = "FIXMON A", types = { "GRASS" },
    baseStats = { hp = 45, attack = 49, defense = 49, speed = 45, special = 65 } } },
  moves = {
    FIX_TACKLE = { id = "FIX_TACKLE", name = "TACKLE", pp = 35 },
    FIX_GROWL = { id = "FIX_GROWL", name = "GROWL", pp = 40 },
  },
  items = {}, maps = { FIXMAP = { id = "FIXMAP" } },
  constants = { fallbackMove = "FIX_TACKLE" },
}

local function saveWith(moves)
  return {
    party = { { species = "FIXMON_A", level = 21, hp = 62, exp = 9000,
                dvs = { hp = 15, attack = 9, defense = 8, speed = 8, special = 8 },
                statExp = {}, moves = moves } },
    boxes = {}, inventory = {}, pcItems = {},
    player = { map = "FIXMAP", x = 1, y = 1, name = "RED", id = 1 },
  }
end

local function scrub(moves)
  local save = saveWith(moves)
  SaveData.validate(save, data)
  return save.party[1].moves
end

-- SummaryMenu page 2 and every battle reader index the save's own slot table
local function readers(mv)
  local mdef = data.moves[mv.id]
  local maxPP = mdef.pp + (mv.ppUps or 0) * math.floor(mdef.pp / 5)
  local okFmt = pcall(string.format, "%2d/%2d", mv.pp, maxPP)
  local okCmp = pcall(function() return mv.pp > 0 end)
  return okFmt, okCmp, maxPP
end

do -- every non-numeric pp shape the tree can be handed
  local moves = scrub({
    { id = "FIX_TACKLE" },
    { id = "FIX_TACKLE", pp = {} },
    { id = "FIX_TACKLE", pp = "35" },
    { id = "FIX_TACKLE", pp = 0 / 0 },
  })
  eq(#moves, 4, "all four slots survive")
  for i = 1, 4 do
    local mv = moves[i]
    check(type(mv.pp) == "number", "slot " .. i .. " carries a numeric pp")
    local okFmt, okCmp, maxPP = readers(mv)
    check(okFmt, "slot " .. i .. ": SummaryMenu's ('%2d/%2d'):format no longer raises")
    check(okCmp, "slot " .. i .. ": playerHasPP's `mv.pp > 0` no longer raises")
    check(type(mv.pp) == "number" and mv.pp >= 0 and mv.pp <= maxPP,
          "slot " .. i .. " sits inside 0..maxPP")
  end
  eq(moves[1].pp, 35, "a missing pp heals to full, not to Struggle")
  eq(moves[2].pp, 35, "a table pp heals to full")
  eq(moves[3].pp, 35, "a numeric string becomes the number it spells")
  eq(moves[4].pp, 35, "a nan pp heals to full")
end

do -- numeric, but not a value the unsigned byte field can express
  local moves = scrub({
    { id = "FIX_TACKLE", pp = -4 },
    { id = "FIX_TACKLE", pp = 1.7 },
    { id = "FIX_TACKLE", pp = math.huge },
    { id = "FIX_TACKLE", pp = -math.huge },
  })
  eq(moves[1].pp, 0, "a negative pp clamps up to zero")
  eq(moves[2].pp, 1, "a fractional pp floors to an integer")
  eq(moves[3].pp, 35, "an infinite pp heals to full")
  eq(moves[4].pp, 35, "so does a negative infinity")
end

-- MimicEffect writes the copied move id into the slot and never touches the
-- PP byte (engine/battle/effects.asm:1261-1266), and this port's battler reads
-- mon.moves by identity, so a mid-battle save legitimately carries a PP count
-- above the slot's current move's max.  Clamping it down corrupts a battle
-- checkpoint, which is why the repair only replaces values that are not
-- numbers at all.
do
  local moves = scrub({
    { id = "FIX_TACKLE", pp = 40, mimic = true },
    { id = "FIX_TACKLE", pp = 999 },
    { id = "FIX_GROWL", pp = 40, ppUps = 0 },
  })
  eq(moves[1].pp, 40, "a Mimic'd slot keeps the 40 PP the GROWL it replaced had")
  check(moves[1].mimic == true, "and the battler's own restore marker survives")
  eq(moves[2].pp, 999, "an over-max pp is left alone, not clamped")
  eq(moves[3].pp, 40, "and a full slot is unchanged")
end

do -- the PP Up count is two bits, so 0..3
  local moves = scrub({
    { id = "FIX_TACKLE", pp = 5, ppUps = "x" },
    { id = "FIX_TACKLE", pp = 5, ppUps = 9 },
    { id = "FIX_TACKLE", pp = 49, ppUps = 2 },
    { id = "FIX_TACKLE", pp = 5 },
  })
  eq(moves[1].ppUps, 0, "a non-numeric ppUps becomes zero")
  eq(moves[2].ppUps, 3, "an over-max ppUps clamps to three")
  eq(moves[3].ppUps, 2, "a legal ppUps is kept")
  eq(moves[3].pp, 49, "and its PP-Upped count is untouched: 35 + 2 * 7")
  eq(moves[4].ppUps, nil, "a slot without a ppUps does not grow one")
  for i = 1, 4 do
    local okFmt = pcall(string.format, "%2d/%2d", moves[i].pp, 35)
    check(okFmt, "slot " .. i .. " formats after a ppUps repair")
    local mdef = data.moves[moves[i].id]
    local ok = pcall(function()
      return mdef.pp + (moves[i].ppUps or 0) * math.floor(mdef.pp / 5)
    end)
    check(ok, "slot " .. i .. ": SummaryMenu's maxPP arithmetic no longer raises")
  end
end

-- A scalar move slot is a shape the id filter has always tolerated, and
-- tests/modkit/cases/checkpoints.lua treats one as valid content that
-- SaveData.validate must not rewrite.  It stays out of the repair; the
-- SummaryMenu.lua:206 crash it causes is a separate defect.
do
  local moves = scrub({ "FIX_TACKLE", { id = "FIX_GROWL" } })
  eq(#moves, 2, "the scalar slot survives the id filter, as before")
  eq(moves[1], "FIX_TACKLE", "and is left exactly as the save stored it")
  eq(moves[2].pp, 40, "while its table-shaped neighbour is still repaired")
end

do -- the moveless-mon fallback slot goes through the same normalization
  local moves = scrub({ { id = "NOT_A_MOVE", pp = "junk" } })
  eq(#moves, 1, "the unknown move is replaced by the fallback")
  eq(moves[1].id, "FIX_TACKLE", "which is data.constants.fallbackMove")
  check(type(moves[1].pp) == "number", "and carries a numeric pp")
  eq(moves[1].pp, 35, "at full")
end

do -- a vanilla slot passes through byte-identical
  local moves = scrub({
    { id = "FIX_TACKLE", pp = 20 },
    { id = "FIX_GROWL", pp = 0 },
    { id = "FIX_GROWL", pp = 64, ppUps = 3 },
  })
  eq(moves[1].pp, 20, "a mid-fight pp is left alone")
  eq(moves[2].pp, 0, "an exhausted move is left on zero, not healed")
  eq(moves[3].pp, 64, "and a PP-Upped slot agrees with SummaryMenu's own maxPP")
  eq(moves[3].ppUps, 3, "with its PP Up count intact")
end

do -- box mons are reached by the same pass
  local save = saveWith({ { id = "FIX_TACKLE", pp = 20 } })
  save.boxes = { { { species = "FIXMON_A", level = 21, hp = 62,
                     dvs = {}, statExp = {},
                     moves = { { id = "FIX_TACKLE", pp = "nonsense" } } } } }
  SaveData.validate(save, data)
  local mv = save.boxes[1][1].moves[1]
  check(type(mv.pp) == "number", "a box mon's move slot is repaired too")
  eq(mv.pp, 35, "to full PP")
end

T.finish()
