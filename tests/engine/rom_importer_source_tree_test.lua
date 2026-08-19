-- sourceTreeHasData must use each version's required-file list.  Gold's
-- cache has no Gen 1 trade art / pikachu.png; validating it against
-- REQUIRED_FILES made a Gold source tree look incomplete forever.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check = T.check

local f = assert(io.open("src/import/RomImporter.lua", "r"))
local src = f:read("*a")
f:close()

local start = src:find("local function sourceTreeHasData", 1, true)
check(start ~= nil, "sourceTreeHasData is defined")
local finish = src:find("\nfunction RomImporter.isReady", start, true)
check(finish ~= nil, "sourceTreeHasData ends before isReady")
local body = src:sub(start, finish)

check(body:find("requiredFilesFor", 1, true) ~= nil,
  "sourceTreeHasData uses requiredFilesFor (Gold override, not Gen 1 only)")
check(body:find("ipairs(REQUIRED_FILES)", 1, true) == nil,
  "sourceTreeHasData does not iterate the Gen 1 REQUIRED_FILES list raw")

local helperStart = src:find("local function requiredFilesFor", 1, true)
check(helperStart ~= nil, "requiredFilesFor helper exists")
local helper = src:sub(helperStart, start)
check(helper:find("VERSION_REQUIRED_FILES_OVERRIDE", 1, true) ~= nil,
  "requiredFilesFor consults VERSION_REQUIRED_FILES_OVERRIDE")
check(src:find('"assets/generated/battle/hud/balls.png"', 1, true) ~= nil,
  "Gold caches require the trainer HUD ball sheet")

T.finish()
