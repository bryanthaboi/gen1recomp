#!/usr/bin/env luajit
-- The summary's move and ability descriptions are keyed by the English name.
-- A translation mod renames moves and abilities in place, so the lookup has
-- to go through the ROM's own name for the number, not the name on screen.

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").mountOrSkip("summary_description")
love = require("tests.love_stub")

local failed = 0
local function check(cond, msg)
  if not cond then
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local Strings = require("src.core.Strings")
local Pokemon = require("src.core.game3.pokemon")
local SummaryData = require("src.core.game3.summary_data")

-- An installed pack a mod has renamed entries of, as Gen3Compat leaves it.
Pokemon._cache = {}
Pokemon._moveNames = { [71] = "VOL-VIE" }
Pokemon._abilityNames = { [9] = "STATIK" }
Pokemon._romMoveNames = { [71] = "ABSORB" }
Pokemon._romAbilityNames = { [9] = "STATIC" }

check(SummaryData.moveDescription(71, "VOL-VIE"):find("absorbs half", 1, true) ~= nil,
  "a renamed move still finds its description")
check(SummaryData.abilityDescription(9, "STATIK") == "Paralyzes on contact.",
  "a renamed ability still finds its description")

Strings.load({ strings = { ["Paralyzes on contact."] = "Paralyse au contact." } })
check(SummaryData.abilityDescription(9, "STATIK") == "Paralyse au contact.",
  "the description goes through Strings()")
Strings.load({})

Pokemon._romMoveNames = nil
check(SummaryData.moveDescription(71, "ABSORB"):find("absorbs half", 1, true) ~= nil,
  "without the ROM names, the name passed in is used")

print(("game3_summary_description_test: %s (%d failed)"):format(failed == 0 and "PASS" or "FAIL", failed))
if failed > 0 then os.exit(1) end
