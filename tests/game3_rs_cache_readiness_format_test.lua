#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local Readiness = require("src.import.gba.rs.cache_readiness")
local BattleChromeExtract = require("src.import.gba.battle_chrome_extract")

local battle
for _, spec in ipairs(Readiness.MODULES) do
  if spec[1] == "pokemon/battle/manifest.lua" then battle = spec end
end

if not battle then
  print("FAIL rs readiness has no battle manifest entry")
  os.exit(1)
end
if battle[2].format ~= BattleChromeExtract.FORMAT_VERSION then
  print(string.format("FAIL rs readiness wants battle manifest format %s, extractor writes %s",
    tostring(battle[2].format), tostring(BattleChromeExtract.FORMAT_VERSION)))
  os.exit(1)
end
print("PASS rs readiness battle manifest format matches the extractor")
