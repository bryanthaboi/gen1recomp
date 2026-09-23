#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").mountOrSkip("summary_partner_gender")

local failed = 0
local function eq(a, b, msg)
  if a == b then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print(string.format("[FAIL] %s (%s ~= %s)", msg, tostring(a), tostring(b)))
  end
end

require("src.core.GameVersion").set("firered")

local SummaryData = require("src.core.game3.summary_data")

eq(SummaryData.gender({ species = 25, level = 14, personality = 175 }), "M",
  "wire PIKACHU with no gender field reads male from personality")
eq(SummaryData.gender({ species = 25, level = 14, personality = 3 }), "F",
  "wire PIKACHU with a low personality byte reads female")
eq(SummaryData.gender({ species = 113, level = 20, personality = 250 }), "F",
  "female-only CHANSEY reads female")
eq(SummaryData.gender({ species = 81, level = 20, personality = 250 }), "",
  "genderless MAGNEMITE has no symbol")
eq(SummaryData.gender({ species = 25, gender = "F", personality = 175 }), "F",
  "an explicit gender field still wins")

if failed > 0 then
  print(failed .. " failure(s)")
  os.exit(1)
end
print("summary partner gender: all passed")
