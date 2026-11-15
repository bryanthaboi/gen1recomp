package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 engine flags ensure")
local check, eq = S.check, S.eq

local savedEF = package.loaded["src.core.gen2.EngineFlags"]
local savedFM = package.loaded["src.world.gen2.FieldMoves"]
package.loaded["src.core.gen2.EngineFlags"] = nil
package.loaded["src.world.gen2.FieldMoves"] = nil
local EngineFlags = require("src.core.gen2.EngineFlags")
local FieldMoves = require("src.world.gen2.FieldMoves")
local Fixture = require("tests.fixture_data.gen2_engine_flags")

local function dataset(version)
  return { gen2Constants = { engineFlagOrder = Fixture.order(version) } }
end

check(not pcall(EngineFlags.ensure, nil), "ensure with no data and nothing bound is an error")
check(not pcall(EngineFlags.ensure, {}, { gen2Constants = {} }),
  "and so is ensure over datasets that carry no engineFlagOrder")
check(not pcall(EngineFlags.id, "ENGINE_BUG_CONTEST_TIMER"), "id before any bind is an error")
check(not pcall(function() return FieldMoves.BIKE_SHOP_CALL_FLAG end),
  "FieldMoves' derived ids refuse to answer while unbound")

EngineFlags.bind(Fixture.order("crystal"))
eq(EngineFlags.id("ENGINE_REACHED_GOLDENROD"), 22, "bind: Crystal's REACHED_GOLDENROD is 22")
eq(FieldMoves.BIKE_SHOP_CALL_FLAG, 20, "Crystal's BIKE_SHOP_CALL_ENABLED is 20")
eq(FieldMoves.BUG_CONTEST_FLAG, 17, "Crystal's BUG_CONTEST_TIMER is 17")
eq(FieldMoves.BADGE_FLAG[27].name, "ZEPHYR", "Crystal's ZEPHYRBADGE is 27")
check(FieldMoves.FEMALE_FLAG ~= nil, "Crystal has ENGINE_PLAYER_IS_FEMALE")

EngineFlags.ensure(dataset("gold"))
eq(EngineFlags.id("ENGINE_REACHED_GOLDENROD"), 21, "ensure rebinds Crystal -> Gold: REACHED_GOLDENROD is 21")
eq(FieldMoves.BIKE_SHOP_CALL_FLAG, 19, "and FieldMoves' bike shop id follows it to 19")
eq(FieldMoves.BUG_CONTEST_FLAG, 16, "and the contest timer to 16")
eq(FieldMoves.BADGE_FLAG[26].name, "ZEPHYR", "and Gold's ZEPHYRBADGE is 26")
eq(FieldMoves.FEMALE_FLAG, nil, "Gold has no ENGINE_PLAYER_IS_FEMALE")

EngineFlags.ensure({ text = {} }, dataset("crystal"))
eq(EngineFlags.id("ENGINE_REACHED_GOLDENROD"), 22,
  "a game dataset without constants falls through to the battle dataset")
eq(FieldMoves.BIKE_SHOP_CALL_FLAG, 20, "and FieldMoves follows that rebind too")

EngineFlags.ensure({ text = {} })
eq(EngineFlags.id("ENGINE_REACHED_GOLDENROD"), 22, "no order anywhere keeps the current binding")

local gold = dataset("gold")
EngineFlags.ensure(gold, dataset("crystal"))
eq(EngineFlags.id("ENGINE_REACHED_GOLDENROD"), 21, "the first dataset with an order wins")

package.loaded["src.core.gen2.EngineFlags"] = savedEF
package.loaded["src.world.gen2.FieldMoves"] = savedFM
S.finish()
