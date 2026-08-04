-- The title screen and the intro fill the window (aspect preserved, bars on
-- the long axis) instead of sitting at the fixed integer scale, and the
-- overworld's survey zoom does not shrink them.
--
-- Both halves shipped broken together.  Renderer:uiScale steps the UI down one
-- whole integer per zoom-out step, which is right for the overworld -- a
-- full-size dialogue box over a shrunken map looks wrong -- but it was applied
-- unconditionally, so a saved zoom of -2 also drew the TITLE SCREEN at a
-- reduced scale, in a window showing no map at all.  The fix gates the
-- step-down on a world actually being on screen, and opts these two states
-- into the fill scale the battle "fill" size already uses.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Game = require("src.core.Game")
local TitleState = require("src.ui.TitleState")
local IntroMovie = require("src.ui.IntroMovie")

-- --------------------------------------------------------------- the opt-in

local title = setmetatable({}, { __index = TitleState })
local intro = setmetatable({}, { __index = IntroMovie })

T.eq(title:wantsFillScale(), true, "the title screen asks for the fill scale")
T.eq(intro:wantsFillScale(), true, "and so does the intro")

-- neither reads options, so this must hold with no game attached at all --
-- the title screen is up before a save is loaded
T.eq(TitleState.wantsFillScale(nil), true,
  "the title screen fills with no game or save behind it")
T.eq(IntroMovie.wantsFillScale(nil), true, "and so does the intro")

-- ------------------------------------------------------------- the stack scan

local function stack(...) return { states = { ... } } end
local overworld = {} -- no wantsFillScale at all, like every other state

T.eq(Game.fillScaleInStack(stack(title)), true,
  "the shared scan picks the title screen up")
T.eq(Game.fillScaleInStack(stack(intro)), true, "and the intro")
T.eq(Game.fillScaleInStack(stack(overworld)), false,
  "and the overworld still draws at the fixed scale")

-- the title screen opens the CONTINUE/NEW GAME menu and the options menu on
-- top of itself; those must not snap the surface back for a frame, the same
-- whole-stack rule a battle relies on
T.eq(Game.fillScaleInStack(stack(title, {})), true,
  "a menu opened over the title screen keeps it filling")

T.finish("title fill scale")
