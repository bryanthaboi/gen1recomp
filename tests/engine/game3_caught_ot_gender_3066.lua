package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local eq = T.eq

local GameVersion = require("src.core.GameVersion")
GameVersion.set("sapphire")

local Catching = require("src.core.game3.battle.catching")
local Schema = require("src.core.game3.save_schema_firered")

local function catchAs(gender)
  local s = { version = "sapphire", name = "MAY", gender = gender, trainerId = 4321, secretId = 8765, party = {} }
  local foe = { species = 263, mon = { species = 263, name = "ZIGZAGOON", level = 3, hp = 12, maxHp = 12 } }
  local res = Catching.storeCaught(s, foe, 4)
  return res and res.mon or {}
end

-- pokeruby/src/pokemon_2.c:969
eq(catchAs(1).otGender, 1, "female player's caught mon has OT gender 1")
eq(catchAs("female").otGender, 1, "female string gender maps to OT gender 1")
eq(catchAs(0).otGender, 0, "male player's caught mon has OT gender 0")

local session = { version = "sapphire", name = "MAY", gender = 1, trainerId = 4321, secretId = 8765 }
session.party = {
  { species = 263, level = 3, hp = 12, maxHp = 12, otName = "MAY", ot = "MAY", otId = 4321, otSecretId = 8765 },
  { species = 263, level = 3, hp = 12, maxHp = 12, otName = "WALLY", ot = "WALLY", otId = 1, otSecretId = 2 },
}
Schema.repairOwnMons(session)
eq(session.party[1].otGender, 1, "own mon missing OT gender is repaired on load")
eq(session.party[2].otGender, nil, "foreign mon OT gender is left alone")

T.finish("game3_caught_ot_gender_3066")
