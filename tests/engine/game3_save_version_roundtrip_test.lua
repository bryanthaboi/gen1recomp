package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Schema = require("src.core.game3.save_schema_firered")
local Profile = require("src.core.game3.profile")
local SaveData = require("src.core.SaveData")

local session = Schema.newGame({ gender = 0 })
eq(session.version, Profile.active().id, "newGame stamps the active profile id")
eq(session.version, "firered", "headless fails closed to the FireRed profile")

local save = Schema.toSaveTable(session)
eq(save.version, "firered", "toSaveTable writes the session version, not a literal")

local back = Schema.fromSaveTable(save)
eq(back.version, "firered", "fromSaveTable round-trips version")

local bare = Schema.toSaveTable(session)
bare.version = nil
eq(Schema.fromSaveTable(bare).version, Profile.active().id,
  "a version-less save falls back to the active profile")

local unknown = Schema.toSaveTable(session)
unknown.version = "not-a-real-game"
eq(Schema.fromSaveTable(unknown).version, "not-a-real-game",
  "fromSaveTable keeps the stored id; Profile.of is the fail-closed reader")
eq(Profile.of("not-a-real-game").id, Profile.active().id,
  "Profile.of fails closed for an unknown id")

local name, info = SaveData.slotSummary({
  engine = "game3",
  name = "RED",
  dex = { owned = { [1] = true, [2] = true, [3] = true } },
})
eq(name, "RED", "slot summary reads the player name")
check(info and info.dexCount == 3, "an engine-tagged save without a version counts dex.owned as Gen 3")

T.finish("game3_save_version_roundtrip_test")
