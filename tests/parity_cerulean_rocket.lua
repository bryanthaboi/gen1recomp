-- Parity: Cerulean TM28 Rocket HideObject fade (#170).
--
-- pokered CeruleanCityRocketText .Success → PrintText (ReceivedTM28 +
-- IBetterGetMoving) → farcall CeruleanHideRocket:
--   GBFadeOutToBlack → Show GUARD1 / Hide GUARD2 / Hide ROCKET →
--   GBFadeInFromBlack.
--
-- Self-contained; run via `luajit tests/parity_cerulean_rocket.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local S = require("tests.harness").suite("parity cerulean rocket")
local check, eq = S.check, S.eq

local story5 = dofile("data/scripts/story5.lua")
local rows = story5.CERULEAN_CITY.talk.TEXT_CERULEANCITY_ROCKET
check(rows ~= nil, "Cerulean Rocket talk script exists")

local function find(verb, arg)
  for i, row in ipairs(rows) do
    if row[1] == verb and (arg == nil or row[2] == arg) then
      return i, row
    end
  end
end

local iMoving = find("show_text", "_CeruleanCityRocketIBetterGetMovingText")
local iFadeOut = find("fade", "out")
local iGuard1 = find("show_object", "CERULEAN_CITY")
local iGuard2 = find("hide_object", "CERULEAN_CITY")
local iRocket, rocketRow
for i, row in ipairs(rows) do
  if row[1] == "hide_object" and row[3] == "CERULEANCITY_ROCKET" then
    iRocket, rocketRow = i, row
    break
  end
end
local iFadeIn = find("fade", "in")

check(iMoving, "prints IBetterGetMovingText before hide")
check(iFadeOut and iFadeOut == iMoving + 1,
      "GBFadeOutToBlack follows IBetterGetMovingText")
check(iGuard1 and rows[iGuard1][3] == "CERULEANCITY_GUARD1"
      and iGuard1 > iFadeOut,
      "ShowObject GUARD1 runs under the black fade")
check(iGuard2 and rows[iGuard2][3] == "CERULEANCITY_GUARD2"
      and iGuard2 > iGuard1,
      "HideObject GUARD2 follows GUARD1 (pokered CeruleanHideRocket order)")
check(iRocket and iRocket > iGuard2 and iRocket < iFadeIn,
      "HideObject ROCKET runs while screen is black")
eq(rocketRow[2], "CERULEAN_CITY", "Rocket hide targets CERULEAN_CITY")
check(iFadeIn and iFadeIn == iRocket + 1,
      "GBFadeInFromBlack follows the three object toggles")

-- loss must not land on a hide/show row
local iBattleJump
for _, row in ipairs(rows) do
  if row[1] == "jump_if_false" then iBattleJump = row break end
end
check(iBattleJump and iBattleJump[2] == "end",
      "battle loss jumps to end (not into CeruleanHideRocket)")

-- GOT_TM28 re-entry jumps at the fade (idempotent HideRocket)
local iGotJump
for _, row in ipairs(rows) do
  if row[1] == "jump_if_true" then iGotJump = row break end
end
check(iGotJump and iGotJump[2] == iFadeOut,
      "EVENT_GOT_TM28 jumps to CeruleanHideRocket fade-out")

-- SaveEndBattleTextPointers before EngageMapTrainer
-- (scripts/CeruleanCity.asm:295) (#1579)
local iBattle = find("start_battle")
local iGiveUp = find("save_end_battle_text",
                     "_CeruleanCityRocketIGiveUpText")
check(iGiveUp, "the thief arms _CeruleanCityRocketIGiveUpText")
check(iBattle and iGiveUp == iBattle - 1,
      "SaveEndBattleTextPointers runs just before the battle")

local ScriptRunner = require("src.script.ScriptRunner")
local problems = ScriptRunner.validate(rows)
eq(#problems, 0, "Rocket script validates: " .. table.concat(problems, "; "))

S.finish()
