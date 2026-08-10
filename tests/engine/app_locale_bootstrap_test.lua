-- ROM-free static guard for the early application-locale bootstrap.  Requiring
-- main.lua would start the whole LÖVE application, so pin the small startup
-- contract directly: load options once, apply locale first, then orientation,
-- all before the launcher/importer module is constructed.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")

local f = assert(io.open("main.lua", "rb"))
local body = f:read("*a")
f:close()

local loadLine = 'local startupOptions = require("src.core.SaveData").loadOptions()'
local localeLine = 'require("src.core.AppLocale").applyOptions(startupOptions)'
local orientationLine = 'require("src.core.Orientation").applyOptions(startupOptions)'
local importerLine = 'local RomImporter = require("src.import.RomImporter")'

local loadAt = assert(body:find(loadLine, 1, true), "startup options load is present")
local localeAt = assert(body:find(localeLine, 1, true), "early locale apply is present")
local orientationAt = assert(body:find(orientationLine, 1, true), "orientation reuses startup options")
local importerAt = assert(body:find(importerLine, 1, true), "launcher/importer construction is present")

T.check(loadAt < localeAt, "options load before locale apply")
T.check(localeAt < orientationAt, "locale applies before orientation")
T.check(orientationAt < importerAt, "bootstrap completes before launcher construction")

local _, loadCount = body:gsub(loadLine:gsub("([^%w])", "%%%1"), "")
T.eq(loadCount, 1, "startup options are loaded exactly once")

T.finish("app_locale_bootstrap")
