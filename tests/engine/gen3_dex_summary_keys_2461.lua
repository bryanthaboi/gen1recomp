package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local eq = T.eq
love = love or require("tests.love_stub")

local Dex = require("src.core.game3.dex")

do
  local save = { dex = { caught = { [1] = true, [4] = true, NOT_A_SPECIES_2461 = true, [200] = true } } }
  eq(Dex.nationalEnabled(save), false, "national dex off")
  eq(Dex.summaryCount(save), 2, "unresolvable string key is not counted on the Kanto gate")
  save.dex.national = true
  eq(Dex.summaryCount(save), 3, "unresolvable string key is not counted on the national gate")
end

do
  local save = { dex = { owned = { ["7"] = true, ["152"] = true } } }
  eq(Dex.summaryCount(save), 1, "numeric string keys still honour the Kanto gate")
end

T.finish("gen3_dex_summary_keys_2461")
if T.failures > 0 then os.exit(1) end
