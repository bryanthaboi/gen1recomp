-- Parity test: Pokemon Center bench guys.
-- Self-contained: run via `luajit tests/parity_bench_guys.lua`; also
-- dofile'd by tests/run_tests.lua's aggregator.
--
-- data/events/bench_guys.asm maps (map id, player facing) to a predef text.
-- The catch is that every entry in that table names a *wrapper* label:
-- PewterCityPokecenterBenchGuyText:: is `text_far _PewterCityPokecenterGuyText`,
-- so the extractor records the wrapper while the string lands under the far
-- label.  Looking up "_" .. label therefore missed on 10 of the 12 benches
-- and those guys answered with nothing at all (#248).  Only Mt Moon and the
-- Celadon hotel worked, because there the two labels happen to coincide.
--
-- This asserts the invariant rather than the table: every bench guy the
-- generated data knows about has to resolve to real text.  A new center, or
-- an extractor that starts recording far labels directly, both stay green.

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end

local S = require("tests.harness").suite("parity bench guys")
local check, eq = S.check, S.eq

local OverworldState = require("src.world.OverworldController")
local resolve = OverworldState.benchGuyText

local benchGuys = Data.field and Data.field.hiddenExtras
  and Data.field.hiddenExtras.benchGuys
check(type(benchGuys) == "table", "generated data carries a benchGuys table")

local noFlags = { flags = {} }

-- BenchGuyTextPointers in pokered, minus the Safari rest houses the
-- extractor also files here without a text label (those NPCs are ordinary
-- map objects, not bench guys, and are out of scope for #248).
local expected = {
  "CELADON_HOTEL", "CELADON_POKECENTER", "CERULEAN_POKECENTER",
  "CINNABAR_POKECENTER", "FUCHSIA_POKECENTER", "LAVENDER_POKECENTER",
  "MT_MOON_POKECENTER", "PEWTER_POKECENTER", "ROCK_TUNNEL_POKECENTER",
  "SAFFRON_POKECENTER", "VERMILION_POKECENTER", "VIRIDIAN_POKECENTER",
}
for _, mapId in ipairs(expected) do
  check(benchGuys[mapId] ~= nil, "bench guy present for " .. mapId)
end

-- the invariant: every labelled bench guy resolves to a non-empty string
local labelled = 0
for mapId, list in pairs(benchGuys) do
  for _, h in ipairs(list) do
    if h.text then
      labelled = labelled + 1
      local text = resolve(Data, noFlags, h.text)
      check(type(text) == "string" and #text > 0,
            ("%s bench guy resolves (%s)"):format(mapId, h.text))
    end
  end
end
eq(labelled, 12, "all twelve BenchGuyTextPointers entries carry a label")

-- the one from the issue: the Pewter couch guy yawning about JIGGLYPUFF
do
  local pewter = benchGuys.PEWTER_POKECENTER and benchGuys.PEWTER_POKECENTER[1]
  check(pewter ~= nil, "Pewter bench guy entry exists")
  local text = pewter and resolve(Data, noFlags, pewter.text)
  check(text and text:find("JIGGLYPUFF", 1, true) ~= nil,
        "Pewter couch guy talks about JIGGLYPUFF (#248)")
  check(text and text:find("Snore", 1, true) ~= nil,
        "Pewter couch guy trails off snoring")
  -- bench_guys.asm only answers when the player faces the seat
  eq(pewter and pewter.facing, "left", "Pewter bench guy is faced from the left")
end

-- SaffronCityPokecenterBenchGuyText is text_asm, so it branches on the flag
do
  local before = resolve(Data, { flags = {} }, "SaffronCityPokecenterBenchGuyText")
  local after = resolve(Data,
    { flags = { EVENT_BEAT_SILPH_CO_GIOVANNI = true } },
    "SaffronCityPokecenterBenchGuyText")
  check(type(before) == "string" and #before > 0, "Saffron bench guy pre-Silph text")
  check(type(after) == "string" and #after > 0, "Saffron bench guy post-Silph text")
  check(before ~= after, "Saffron bench guy changes after Giovanni is beaten")
end

-- a label the table has never heard of stays nil rather than throwing
eq(resolve(Data, noFlags, "NoSuchBenchGuyText"), nil, "unknown label resolves to nil")
eq(resolve(Data, noFlags, nil), nil, "missing label resolves to nil")

S.finish()
