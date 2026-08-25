-- Badges are one store, not two.
--
--   luajit tests/gen2_badges_test.lua
--
-- On the cart ENGINE_ZEPHYRBADGE is bit 0 of wJohtoBadges
-- (constants/engine_flags.asm), so `setflag ENGINE_ZEPHYRBADGE` and "the player
-- owns the Zephyr Badge" are the same write.  The port had two stores: gym
-- scripts wrote save.engineFlags, while FieldMoves.hasBadge, VAR_BADGES, the
-- trainer card and the save summary all read save.player.badges -- which
-- nothing ever assigned.
--
-- The visible bug, found by the Gold route bot after it beat Falkner and Bugsy:
-- CUT refused with "Sorry! A new BADGE is required" while holding the badge
-- that grants it, so Ilex Forest could never be left and no HM was usable for
-- the rest of the game.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 badges")
local check, eq = S.check, S.eq

local FieldMoves = require("src.world.gen2.FieldMoves")
local World = require("src.world.gen2.World")

-- The bit order is wJohtoBadges', not the order a player earns them: Jasmine's
-- MINERALBADGE sits at bit 4 and Chuck's STORMBADGE at bit 5, even though Chuck
-- is fought first.  Getting this backwards maps SURF's and FLY's gates onto
-- each other's bits.
eq(FieldMoves.JOHTO_BADGES[5], "MINERAL", "bit 4 is MINERAL")
eq(FieldMoves.JOHTO_BADGES[6], "STORM", "bit 5 is STORM")

-- The ids come from constants/engine_flags.asm's const_def run.
eq(FieldMoves.BADGE_FLAG[26].name, "ZEPHYR", "ENGINE_ZEPHYRBADGE is 26")
eq(FieldMoves.BADGE_FLAG[27].name, "HIVE", "ENGINE_HIVEBADGE is 27")
eq(FieldMoves.BADGE_FLAG[30].name, "MINERAL", "ENGINE_MINERALBADGE is 30")
eq(FieldMoves.BADGE_FLAG[31].name, "STORM", "ENGINE_STORMBADGE is 31")
eq(FieldMoves.BADGE_FLAG[26].store, "badges", "Johto badges go to player.badges")
eq(FieldMoves.BADGE_FLAG[34].store, "kantoBadges",
   "ENGINE_BOULDERBADGE goes to player.kantoBadges")

-- pokecrystal/constants/engine_flags.asm:39 declares 162 flags to pokegold's
-- 93, moving the whole badge block up one.
do
  local order = {}
  for i = 1, 43 do order[i] = "ENGINE_UNRELATED" .. i end
  order[10] = nil -- a const_skip hole must not truncate the map
  for index, name in ipairs(FieldMoves.JOHTO_BADGES) do
    order[27 + index] = "ENGINE_" .. name .. "BADGE"
  end
  for index, name in ipairs(FieldMoves.KANTO_BADGES) do
    order[35 + index] = "ENGINE_" .. name .. "BADGE"
  end
  FieldMoves.bindEngineFlags(order)
  eq(FieldMoves.BADGE_FLAG[27].name, "ZEPHYR", "crystal ZEPHYRBADGE is 27")
  eq(FieldMoves.BADGE_FLAG[28].name, "HIVE", "crystal HIVEBADGE is 28")
  eq(FieldMoves.BADGE_FLAG[34].name, "RISING", "crystal RISINGBADGE is 34")
  eq(FieldMoves.BADGE_FLAG[35].name, "BOULDER", "crystal BOULDERBADGE is 35")
  eq(FieldMoves.BADGE_FLAG[35].store, "kantoBadges",
     "a renumbered Kanto badge still lands in kantoBadges")
  eq(FieldMoves.BADGE_FLAG[26], nil, "Gold's ZEPHYR slot is vacated")

  FieldMoves.bindEngineFlags(nil)
  eq(FieldMoves.BADGE_FLAG[26].name, "ZEPHYR", "no map falls back to Gold")
end

-- ---------------------------------------------------------------------------
-- The round trip: what a gym script writes is what a field move reads.
-- ---------------------------------------------------------------------------

local save = { player = { badges = {}, kantoBadges = {} }, engineFlags = {} }
local world = setmetatable({ game = { save = save } }, { __index = World })

eq(world:engineFlag(27), false, "no HIVEBADGE to begin with")
eq(FieldMoves.hasBadge(save, FieldMoves.BADGE.CUT), false, "so CUT is gated")

-- What BugsyScript does: `setflag ENGINE_HIVEBADGE`.
world:setEngineFlag(27, true)

eq(world:engineFlag(27), true, "the flag reads back as set")
eq(save.player.badges.HIVE, true, "and it landed in the badge store")
check(FieldMoves.hasBadge(save, FieldMoves.BADGE.CUT),
      "CUT is now allowed -- the bug was that this stayed false forever")

-- VAR_BADGES counts the same store, so a script branching on badge count
-- (section 09's "if VAR_BADGES == 6, the Rockets appear in Goldenrod") sees it.
local counted = 0
for _, has in pairs(save.player.badges) do
  if has then counted = counted + 1 end
end
eq(counted, 1, "the badge count sees it too")

-- Clearing works, and does not leave a stale copy in the flag table.
world:setEngineFlag(27, false)
eq(world:engineFlag(27), false, "cleared")
eq(save.player.badges.HIVE, nil, "cleared in the badge store")
eq(save.engineFlags[27], nil, "and never shadowed by a second copy")

-- Non-badge engine flags still use the ordinary table.
world:setEngineFlag(1, true)   -- ENGINE_MAP_CARD
eq(world:engineFlag(1), true, "a non-badge flag still round-trips")
eq(save.engineFlags[1], true, "...through save.engineFlags")

-- Every gate FieldMoves.BADGE names must be a real Johto badge.
for move, badge in pairs(FieldMoves.BADGE) do
  local found = false
  for _, name in ipairs(FieldMoves.JOHTO_BADGES) do
    if name == badge then found = true break end
  end
  check(found, ("%s is gated on a real badge (%s)"):format(move, badge))
end

S.finish()
