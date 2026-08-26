-- Optional dataset absence is a handled API result, while a previously valid
-- view disappearing and malformed cache content remain actionable warnings.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Fixture = require("tests.modkit.dataset_view_fixture")
local DatasetViews = require("src.mods.DatasetViews")
local GameVersion = require("src.core.GameVersion")
local Logger = require("src.core.Logger")

local previousWarn = Logger.warn
local warnings = {}
Logger.warn = function(fmt, ...)
  warnings[#warnings + 1] = select("#", ...) > 0
    and string.format(fmt, ...) or fmt
end

local ok, err = xpcall(function()
  local unavailable = DatasetViews.new(T.sdk.memfs({}))
  local unknown, unknownReason = unavailable:open("missing-version")
  T.eq(unknown, nil, "unknown version has no view")
  T.eq(unknownReason, "unknown_version", "unknown version returns its reason")
  local absent, absentReason = unavailable:open("gold")
  T.eq(absent, nil, "missing optional Gold dataset has no view")
  T.eq(absentReason, "not_imported", "missing optional Gold returns its reason")
  T.eq(#warnings, 0, "unknown and initially absent datasets do not warn")

  local files = {}
  Fixture.cache(files, "gold")
  local service = DatasetViews.new(T.sdk.memfs(files))
  local view = assert(service:open("gold"))
  files[GameVersion.cachePrefix("gold") .. "rom-cache.complete"] = nil
  T.eq(view.assets:path("assets/generated/missing.png"), nil,
    "a stale view closes when its imported dataset disappears")
  T.eq(#warnings, 1, "a previously valid view disappearing still warns")
  T.check(warnings[1]:find("dataset gold unavailable", 1, true) ~= nil,
    "the stale-view warning identifies the unavailable dataset")

  warnings = {}
  local malformedFiles = {}
  Fixture.cache(malformedFiles, "gold", { pokemon = "not generated data" })
  local malformed = assert(DatasetViews.new(T.sdk.memfs(malformedFiles)):open("gold"))
  T.eq(#warnings, 0, "lazy open does not warn before malformed data is read")
  T.eq(malformed.content.pokemon:get("FIXMON"), nil,
    "malformed generated data fails closed")
  T.eq(#warnings, 1, "malformed generated data still warns")
  T.check(warnings[1]:find("dataset gold cache rejected", 1, true) ~= nil,
    "the malformed-cache warning identifies cache rejection")
  T.check(warnings[1]:find("pokemon:", 1, true) ~= nil,
    "the malformed-cache warning keeps actionable module detail")
end, debug.traceback)

Logger.warn = previousWarn
if not ok then error(err, 0) end

T.finish("dataset_views_warning_policy")
