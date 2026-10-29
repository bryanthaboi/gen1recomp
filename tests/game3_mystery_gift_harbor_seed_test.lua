#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Flags = require("src.core.game3.scripting.flags")
local MysteryGift = require("src.core.game3.mystery_gift")

local HARBOR = 0x4075

print("[test] 1. a fresh store carries no story vars")
local fresh = Flags.newStore()
eq(fresh.vars[HARBOR], nil, "newStore vars[0x4075] is nil")
eq(next(fresh.vars), nil, "newStore vars is empty")
eq(next(fresh.flags), nil, "newStore flags is empty")

print("[test] 2. Mystery Gift round-trip leaves a save without 0x4075 untouched")
local save = { version = "leafgreen", flags = {}, vars = { ["16497"] = 4 } }
local session = MysteryGift.sessionFromSave(save)
eq(session.store.vars[HARBOR], nil, "sessionFromSave store has no harbor var")
check(MysteryGift.applyToSave(session, save), "applyToSave succeeds")
eq(save.vars["16501"], nil, "applyToSave does not write vars[\"16501\"]")
eq(tonumber(save.vars["16497"]), 4, "Cinnabar scene var survives the round-trip")

print("[test] 3. a saved harbor value is kept as-is")
local saved = { version = "leafgreen", flags = {}, vars = { ["16501"] = 3 } }
local s2 = MysteryGift.sessionFromSave(saved)
MysteryGift.applyToSave(s2, saved)
eq(tonumber(saved.vars["16501"]), 3, "harbor var 3 round-trips")

T.finish()
