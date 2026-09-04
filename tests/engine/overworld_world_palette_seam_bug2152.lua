-- (engine/gfx/palettes.asm:178)
--   luajit tests/engine/overworld_world_palette_seam_bug2152.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("world palette seam #2152")
local check, eq = S.check, S.eq

local OW = require("src.world.OverworldController")
local Zoom = require("src.render.Zoom")

local saved = Zoom.offset

Zoom.offset = 0
eq(OW.perMapWorldPalettes(), false,
   "FIT publishes the whole-screen block the hardware does")

Zoom.offset = 1
eq(OW.perMapWorldPalettes(), false, "a close-up view is whole-screen too")

Zoom.offset = -1
eq(OW.perMapWorldPalettes(), true, "one step of survey zoom keeps per-area colour")

Zoom.offset = -3
eq(OW.perMapWorldPalettes(), true, "so does a far survey zoom")

Zoom.offset = nil
eq(OW.perMapWorldPalettes(), false, "an unset zoom reads as FIT")

Zoom.offset = saved

S.finish()
