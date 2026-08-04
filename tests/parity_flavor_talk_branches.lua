-- Parity: a branched flavor talk script shows exactly ONE text per branch
-- (#719).  The buggy layout was
--
--   check_flag X / jump_if_true <jumpRow> / show before / jump <afterRow> /
--   show after
--
-- where the fall-through "jump" landed ON the after-text row instead of
-- ending the script, so talking to the Silph Co. workers (and the other
-- NPCs below) before Giovanni showed the worried line and then the
-- relieved line right after it.  ScriptRunner executes the row a numeric
-- jump targets, so the fixed scripts point jump_if_true at the after-text
-- row directly and end the before-branch with jump "end".
--
-- The walker below is a minimal read of ScriptRunner's jump semantics:
-- checks are forced to one outcome, every non-control command is a no-op,
-- and show_text/ask rows are recorded in order.
package.path = "./?.lua;./?/init.lua;" .. package.path
local S = require("tests.harness").suite("parity flavor talk branches")
local check, eq = S.check, S.eq

local scripts = require("data.scripts.init")

local function textsShown(script, checkResult)
  local texts, pc, steps = {}, 1, 0
  local last = nil
  while pc <= #script do
    steps = steps + 1
    if steps > 200 then error("script did not terminate", 0) end
    local row = script[pc]
    local cmd = row[1]
    if cmd == "show_text" or cmd == "ask" then
      texts[#texts + 1] = row[2]
      pc = pc + 1
    elseif cmd == "check_flag" or cmd == "check_item" then
      last = checkResult
      pc = pc + 1
    elseif cmd == "jump" then
      if row[2] == "end" then break end
      pc = row[2]
    elseif cmd == "jump_if_true" or cmd == "jump_if_false" then
      local take = (cmd == "jump_if_true") == (last == true)
      if take then
        if row[2] == "end" then break end
        pc = row[2]
      else
        pc = pc + 1
      end
    else
      pc = pc + 1
    end
  end
  return texts
end

-- { mapId, textConst, before-text, after-text }
local cases = {
  { "SILPH_CO_3F", "TEXT_SILPHCO3F_SILPH_WORKER_M",
    "_SilphCo3FSilphWorkerMWhatShouldIDoText",
    "_SilphCo3FSilphWorkerMYouSavedUsText" },
  { "SILPH_CO_4F", "TEXT_SILPHCO4F_SILPH_WORKER_M",
    "_SilphCo4FSilphWorkerMImHidingText",
    "_SilphCo4FSilphWorkerMTeamRocketIsGoneText" },
  { "SILPH_CO_5F", "TEXT_SILPHCO5F_SILPH_WORKER_M",
    "_SilphCo5FSilphWorkerMThatsYouRightText",
    "_SilphCo5FSilphWorkerMYoureOurHeroText" },
  { "SILPH_CO_6F", "TEXT_SILPHCO6F_SILPH_WORKER_M1",
    "_SilphCo6FSilphWorkerM1TookOverTheBuildingText",
    "_SilphCo6FSilphWorkerM1BackToWorkText" },
  { "SILPH_CO_6F", "TEXT_SILPHCO6F_SILPH_WORKER_M2",
    "_SilphCo6FSilphWorkerMHelpMePleaseText",
    "_SilphCo6FSilphWorkerMWeGotEngagedText" },
  { "SILPH_CO_6F", "TEXT_SILPHCO6F_SILPH_WORKER_F1",
    "_SilphCo6FSilphWorkerF1SuchACowardText",
    "_SilphCo6FSilphWorkerF1HaveToMarryHimText" },
  { "SILPH_CO_6F", "TEXT_SILPHCO6F_SILPH_WORKER_F2",
    "_SilphCo6FSilphWorkerF2TeamRocketConquerWorldText",
    "_SilphCo6FSilphWorkerF2TeamRocketRanText" },
  { "SILPH_CO_6F", "TEXT_SILPHCO6F_SILPH_WORKER_M3",
    "_SilphCo6FSilphWorkerM3TargetedSilphText",
    "_SilphCo6FSilphWorkerM3WorkForSilphText" },
  { "SILPH_CO_7F", "TEXT_SILPHCO7F_SILPH_WORKER_M2",
    "_SilphCo7FSilphWorkerM2AfterTheMasterBallText",
    "_SilphCo7FSilphWorkerM2CancelledMasterBallText" },
  { "SILPH_CO_7F", "TEXT_SILPHCO7F_SILPH_WORKER_M3",
    "_SilphCo7FSilphWorkerM3ItWouldBeBadText",
    "_SilphCo7FSilphWorkerM3YouChasedOffTeamRocketText" },
  { "SILPH_CO_7F", "TEXT_SILPHCO7F_SILPH_WORKER_M4",
    "_SilphCo7FSilphWorkerM4ItsReallyDangerousHereText",
    "_SilphCo7FSilphWorkerM4SafeAtLastText" },
  { "SILPH_CO_8F", "TEXT_SILPHCO8F_SILPH_WORKER_M",
    "_SilphCo8FSilphWorkerMSilphIsFinishedText",
    "_SilphCo8FSilphWorkerMThanksForSavingUsText" },
  { "SILPH_CO_10F", "TEXT_SILPHCO10F_SILPH_WORKER_F",
    "_SilphCo10FSilphWorkerFImScaredText",
    "_SilphCo10FSilphWorkerFQuietAboutMyCryingText" },
  { "CERULEAN_TRASHED_HOUSE", "TEXT_CERULEANTRASHEDHOUSE_FISHING_GURU",
    "_CeruleanTrashedHouseFishingGuruTheyStoleATMText",
    "_CeruleanTrashedHouseFishingGuruWhatsLostIsLostText" },
  { "LAVENDER_MART", "TEXT_LAVENDERMART_COOLTRAINER_M",
    "_LavenderMartCooltrainerMReviveText",
    "_LavenderMartCooltrainerMNuggetText" },
  { "ROUTE_16_GATE_1F", "TEXT_ROUTE16GATE1F_GUARD",
    "_Route16Gate1FGuardNoPedestriansAllowedText",
    "_Route16Gate1FGuardCyclingRoadExplanationText" },
  { "ROUTE_18_GATE_1F", "TEXT_ROUTE18GATE1F_GUARD",
    "_Route18Gate1FGuardYouNeedABicycleText",
    "_Route18Gate1FGuardCyclingRoadUphillText" },
  { "MR_FUJIS_HOUSE", "TEXT_MRFUJISHOUSE_SUPER_NERD",
    "_MrFujisHouseSuperNerdMrFujiIsntHereText",
    "_MrFujisHouseSuperNerdMrFujiHadBeenPrayingText" },
  { "MR_FUJIS_HOUSE", "TEXT_MRFUJISHOUSE_LITTLE_GIRL",
    "_MrFujisHouseLittleGirlThisIsMrFujisHouseText",
    "_MrFujisHouseLittleGirlPokemonAreNiceToHugText" },
}

for _, case in ipairs(cases) do
  local mapId, textConst, beforeText, afterText = case[1], case[2], case[3], case[4]
  local script = scripts.talkScript(mapId, textConst)
  check(script ~= nil, mapId .. "/" .. textConst .. " has a talk script")
  if script then
    local before = textsShown(script, false)
    eq(#before, 1, textConst .. " shows exactly one text before the event")
    eq(before[1], beforeText, textConst .. " shows the before-text")
    local after = textsShown(script, true)
    eq(#after, 1, textConst .. " shows exactly one text after the event")
    eq(after[1], afterText, textConst .. " shows the after-text")
  end
end

S.finish()
