-- CacheFs stays headless-safe: plain luajit has no love global, and the
-- modkit validate/pack driver reaches CacheFs.read through Data:load when
-- an optional generated module (audio) is missing from the checkout
-- (issue #850).  With no portable root and no love there is no save
-- directory to read from, so the read is a nil miss, not a crash.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check

check(_G.love == nil, "suite runs with no love global")

local CacheFs = require("src.import.CacheFs")

check(CacheFs.read("data/generated/audio.lua") == nil,
  "read is a nil miss headless, not a crash")
check(CacheFs.readActive("data/generated/audio.lua") == nil,
  "readActive is a nil miss headless, not a crash")
local loaded, loadErr = CacheFs.loadActive("data/generated/audio.lua")
check(loaded == nil, "loadActive is a nil miss headless, not a crash")
check(type(loadErr) == "string", "loadActive reports the miss")

T.finish()
