package.path = "./?.lua;./?/init.lua;" .. package.path

love = love or require("tests.love_stub")

local S = require("tests.harness").suite("gen3 cracked floor and PC metatile ids")
local check, eq = S.check, S.eq

local Constants = require("src.core.game3.constants")
local Steps = require("src.core.game3.step_callbacks_rse")

local rs = Steps.crackedIds(Constants.of("ruby"))
eq(rs.floor, 0x22F, "ruby cracked floor")
eq(rs.hole, 0x206, "ruby cracked floor hole")
eq(rs.pillarHole, 0x237, "ruby sky pillar hole")
eq(Steps.crackedIds(Constants.of("sapphire")), rs, "sapphire shares ruby's ids")

local em = Steps.crackedIds(Constants.of("emerald"))
eq(em.floor, 0x22F, "emerald cracked floor from its label")
eq(em.hole, 0x206, "emerald cracked floor hole from its label")
eq(em.pillarHole, 0x237, "emerald sky pillar hole from its label")

local labels = Constants.of("emerald").metatile_labels.byName
local saved = labels.METATILE_Cave_CrackedFloor_Hole
labels.METATILE_Cave_CrackedFloor_Hole = nil
local ok, err = pcall(Steps.crackedIds, Constants.of("emerald"))
labels.METATILE_Cave_CrackedFloor_Hole = saved
check(not ok and tostring(err):find("METATILE_Cave_CrackedFloor_Hole", 1, true) ~= nil,
  "emerald with a missing label raises instead of using a number: " .. tostring(err))

local GameVersion = require("src.core.GameVersion")
local before = GameVersion.get()
GameVersion.set("firered")
local PcAnim = require("src.core.game3.pc_anim")
eq(PcAnim.metatile(0, false), 0x062, "building PC off")
eq(PcAnim.metatile(0, true), 0x063, "building PC on")
eq(PcAnim.metatile(1, false), 0x28F, "player's PC off")
eq(PcAnim.metatile(1, true), 0x28A, "player's PC on")
eq(PcAnim.metatile(2, true), 0x28A, "var 2 is the player's PC too")
eq(PcAnim.metatile(3, true), nil, "no PC for var 3")
GameVersion.set("emerald")
eq(pcall(PcAnim.metatile, 0, true), false, "a FireRed PC label on Emerald raises")
GameVersion.set(before)

S.finish()
