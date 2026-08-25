-- FIND MODS download counts: the index feed publishes them per listing, so
-- the panel reads the one fetch it already made instead of asking GitHub per
-- mod (that fan-out is what blew the hourly API limit in _findStatsCached's
-- own comment).  This pins the resolver's precedence, the unknown-is-not-zero
-- rule the card and the sorts both depend on, and the Trending wiring.
--   luajit tests/engine/launcher_mod_downloads.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

-- No launcher test may reach the network: beginFetchReleases is the only door
-- out of _requestFindStats, and counting the calls is the assertion.
local ModUpdate = require("src.mods.ModUpdate")
local fetched = {}
ModUpdate.beginFetchReleases = function(repo, id)
  fetched[#fetched + 1] = id
  return { stage = "done" }
end

local RomImporter = require("src.import.RomImporter")
local function launcher()
  return setmetatable({ tab = "find" }, RomImporter)
end

local function entry(id, downloads, github)
  return { id = id, title = id, downloads = downloads, github = github }
end

-- ------- the feed's counts win, and cost nothing

do
  local ri = launcher()
  local e = entry("counted", { total = 1578, recent = 388, window_days = 30,
                               as_of = "2026-08-18T05:17:00.000Z" },
                  "someone/counted")
  local stats = ri:_findStats(e)
  eq(stats.total, 1578, "the feed's total is what the card shows")
  eq(stats.recent, 388, "the trailing-window count rides along")
  eq(stats.windowDays, 30, "so does the window it covers")
  eq(stats.asOf, "2026-08-18T05:17:00.000Z", "and when the index read it")
  eq(#fetched, 0, "a listing with a published total asks GitHub for nothing")
end

-- A bare number is what a cache written before the object shipped holds; it
-- is read back through the same resolver rather than migrated.
do
  local ri = launcher()
  eq(ri:_findStats(entry("legacy", 4321, "someone/legacy")).total, 4321,
     "a cached scalar count still resolves")
  eq(#fetched, 0, "and still costs no request")
end

-- Whole-list, not page-by-page: sorting calls the cached read for every entry
-- in the index, so all of them have to resolve from the feed alone.  A
-- listing the feed dates but does not count still resolves, off `latest`.
do
  local ri = launcher()
  local dated = { id = "dated", title = "Dated", github = "someone/dated",
                  latest = { version = "1.0.0",
                             published_at = "2026-08-11T17:19:00Z" } }
  local stats = ri:_findStats(dated)
  eq(stats.latest, "2026-08-11", "the feed's own release blob dates the row")
  eq(#fetched, 0, "with no repo fetch to wait on")
  eq(ModUpdate.datesLine(stats.first, stats.latest), "Updated 2026-08-11",
     "and the card states what it knows instead of a Released ?")
end

-- ------- unknown is unknown: null falls through to the repo, as any other
-- missing feed stat does, and a listing with no repo resolves to no counts
-- rather than to zero.

do
  local ri = launcher()
  check(ri:_findStats(entry("nulled", nil, "someone/nulled")) == nil,
        "a null count is not an answer")
  ri:_requestFindStats(entry("nulled", nil, "someone/nulled"))
  eq(#fetched, 1, "which is the fetch the panel already made for dates")

  local bare = launcher()
  local stats = bare:_findStats(entry("no-repo", nil, nil))
  check(stats ~= nil and stats.total == nil,
        "a listing with neither counts nor a repo is resolved-but-unknown")
  check(stats.recent == nil, "and has nothing to trend on")
  eq(#fetched, 1, "and the explicit scheduler queues nothing without a repo")
end

-- A real zero is not unknown: the index has seen the releases and counted
-- none.  The card prints it and the sort ranks it above the unknowns.
do
  local ri = launcher()
  local stats = ri:_findStats(entry("zero", { total = 0 }, "someone/zero"))
  eq(stats.total, 0, "a counted zero survives as a number")
  eq(ModUpdate.downloadsShort(stats.total), "0 downloads",
     "and prints as zero rather than as a dash")
end

-- ------- the panel wiring around those numbers

local view = (function()
  local f = assert(io.open("src/import/LauncherView.lua", "r"))
  local src = f:read("*a")
  f:close()
  return src
end)()

check(view:find('key = "trending"', 1, true) ~= nil,
      "a Trending sort exists")
check(view:find('sortKey == "trending" then return stats and stats.recent or %-1'),
      "Trending orders by the trailing-window count, unknown last")
check(view:find('sortKey == "popularity" then return stats and stats.total or %-1'),
      "Most downloaded orders by the total, unknown last")
-- Trending has no meaning on the installed-mods tab, and the persisted key is
-- shared, so that panel has to degrade rather than sort on nothing.
check(view:find('if scope == "find" then', 1, true) ~= nil,
      "Trending is offered only where the feed's counts exist")
check(view:find('sortKey == "trending" and scope ~= "find"', 1, true) ~= nil,
      "the MODS tab falls back when the shared sort key is FIND-only")
check(view:find('sortKey or "popularity"', 1, true) ~= nil,
      "the default sort is unchanged")
check(view:find("downloadsShort", 1, true) ~= nil,
      "the browse card prints the abbreviated count")

T.finish("launcher_mod_downloads")
