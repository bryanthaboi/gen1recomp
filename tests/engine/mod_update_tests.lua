-- Pure coverage for src/mods/ModUpdate.lua (zip picking, release parse, isNewer).
--   luajit tests/engine/mod_update_tests.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local ModUpdate = require("src.mods.ModUpdate")
local Json = require("src.link.Json")

do
  local assets = {
    { name = "readme.txt", browser_download_url = "https://x/r" },
    { name = "other-1.0.0.zip", browser_download_url = "https://x/o", size = 10 },
    { name = "coolmod-1.2.0.zip", browser_download_url = "https://x/c", size = 20 },
  }
  local pick = ModUpdate.pickZipAsset(assets, "coolmod", "1.2.0")
  eq(pick.name, "coolmod-1.2.0.zip", "prefers id-version.zip")
  eq(pick.url, "https://x/c", "returns the download URL")
end

do
  local assets = {
    { name = "payload.zip", browser_download_url = "https://x/p" },
  }
  local pick = ModUpdate.pickZipAsset(assets, "coolmod", "1.0.0")
  eq(pick.name, "payload.zip", "falls back to the first .zip")
end

do
  local body = Json.encode({
    {
      tag_name = "v1.2.0",
      name = "1.2.0",
      prerelease = false,
      assets = {
        { name = "demo-1.2.0.zip", browser_download_url = "https://x/d.zip",
          size = 99 },
      },
    },
    {
      tag_name = "v1.1.0",
      assets = {
        { name = "demo-1.1.0.zip", browser_download_url = "https://x/old.zip" },
      },
    },
    {
      tag_name = "notes-only",
      assets = {},
    },
  })
  local list = ModUpdate.parseReleases(body, "demo")
  eq(#list, 2, "releases without a zip are dropped")
  eq(list[1].version, "1.2.0", "keeps GitHub array order")
  eq(list[1].zip.url, "https://x/d.zip", "zip url is preserved")
end

check(ModUpdate.isNewer("1.0.0", "1.0.1"), "patch bump is newer")
check(not ModUpdate.isNewer("1.2.0", "1.1.9"), "older candidate is not newer")
check(not ModUpdate.isNewer("1.0.0", "1.0.0"), "same version is not newer")

eq(ModUpdate.apiLatestUrl("acme/mod"),
  "https://api.github.com/repos/acme/mod/releases/latest",
  "latest API URL")

-- soft-fail paths: garbage input must never throw
do
  local list, err = ModUpdate.parseReleases("{{{not json", "demo")
  check(list == nil and err ~= nil, "bad json returns nil, err")
  list, err = ModUpdate.parseReleases('{"message":"Not Found"}', "demo")
  check(list == nil and tostring(err):find("Not Found", 1, true),
    "GitHub error payload surfaces the message")
  list, err = ModUpdate.fetchReleases("", "demo")
  check(list == nil and err ~= nil, "empty repo soft-fails")
  local path, dlErr = ModUpdate.downloadZip("", "x.zip")
  check(path == nil and dlErr ~= nil, "empty url soft-fails")
end

-- the reported bug: a non-JSON answer (plain-text error, proxy/captive
-- prompt, outage message) used to leak the decoder's "unexpected character"
-- assert at the first byte of the body. The guard must name what the server
-- actually sent and never let that assert surface.
do
  local list, err = ModUpdate.parseReleases("Error: API rate limit exceeded", "demo")
  check(list == nil and err ~= nil, "plain-text error soft-fails")
  check(tostring(err):find("not JSON", 1, true) ~= nil
      and tostring(err):find("Error: API", 1, true) ~= nil,
    "plain-text error names the response and previews what it said")
  list, err = ModUpdate.parseReleases("<!DOCTYPE html><html>502 Bad Gateway</html>", "demo")
  check(list == nil and tostring(err):find("HTML", 1, true) ~= nil,
    "an HTML error page is named as such")
  list, err = ModUpdate.parseReleases("", "demo")
  check(list == nil and tostring(err):find("empty", 1, true) ~= nil,
    "an empty response is named")
  check(tostring(err):find("unexpected character", 1, true) == nil,
    "the decoder's assert never leaks into the message")
  list = ModUpdate.parseReleases(Json.encode({
    { tag_name = "v1.0.0", assets = {
        { name = "demo-1.0.0.zip", browser_download_url = "https://x/d.zip" } } },
  }), "demo")
  eq(#list, 1, "the guard lets real JSON through")
end

do
  local body = Json.encode({
    tag_name = "v2.0.0",
    body = "## Changes\n\n- **fixed** the [thing](http://x)\n\n<!-- note -->",
    assets = {
      { name = "demo-2.0.0.zip", browser_download_url = "https://x/d.zip" },
    },
  })
  local list = ModUpdate.parseReleases(body, "demo")
  eq(list[1].body:sub(1, 2), "##", "release body is kept raw")
  local cleaned = ModUpdate.cleanBody(list[1].body, 200)
  check(cleaned:find("fixed", 1, true) and cleaned:find("thing", 1, true),
    "cleanBody keeps readable text")
  check(not cleaned:find("http://", 1, true), "cleanBody strips link urls")
  check(not cleaned:find("<!--", 1, true), "cleanBody strips HTML comments")

  local status, best = ModUpdate.statusFor("1.0.0", list)
  eq(status, "available", "newer release reports available")
  eq(best.version, "2.0.0", "best release is the newer one")
  eq(ModUpdate.statusFor("2.0.0", list), "current", "matching version is current")

  check(ModUpdate.cacheFresh({ checkedAt = os.time() - 10 }),
    "fresh cache is within TTL")
  check(not ModUpdate.cacheFresh({ checkedAt = os.time() - ModUpdate.CACHE_TTL - 1 }),
    "expired cache is not fresh")

  local preview = ModUpdate.previewLine(list[1].body, 40)
  check(not preview:find("\n", 1, true), "previewLine collapses newlines")
  check(#preview <= 41, "previewLine respects maxChars (+ellipsis)")
  check(preview:find("Changes", 1, true), "previewLine keeps heading text")
end

-- downloads: per-release sum over every asset's download_count
do
  local body = Json.encode({
    {
      tag_name = "v1.2.0",
      assets = {
        { name = "demo-1.2.0.zip", browser_download_url = "https://x/d.zip",
          size = 99, download_count = 41 },
        { name = "demo-1.2.0.sha256", browser_download_url = "https://x/d.sha",
          download_count = 9 },
      },
    },
  })
  local list = ModUpdate.parseReleases(body, "demo")
  eq(list[1].downloads, 50, "downloads sums every asset, not just the zip")
end

-- published: the release date is kept as an ISO day
do
  local body = Json.encode({
    { tag_name = "v1.2.0", published_at = "2025-04-13T09:24:00Z",
      assets = { { name = "demo-1.2.0.zip",
        browser_download_url = "https://x/d.zip" } } },
  })
  local list = ModUpdate.parseReleases(body, "demo")
  eq(list[1].published, "2025-04-13", "published_at is reduced to the day")
  local noDate = ModUpdate.parseReleases(Json.encode({
    { tag_name = "v1.0.0",
      assets = { { name = "demo-1.0.0.zip",
        browser_download_url = "https://x/d.zip" } } },
  }), "demo")
  check(noDate[1].published == nil, "missing dates stay nil, never throw")
end

-- releaseDates: first and latest across releases
do
  local d = ModUpdate.releaseDates({
    { version = "1.0.0", published = "2024-05-31" },
    { version = "1.2.0", published = "2025-11-02" },
    { version = "1.1.0", published = "2025-01-15" },
  })
  eq(d.first, "2024-05-31", "first is the oldest release date")
  eq(d.latest, "2025-11-02", "latest is the newest release date")
  check(ModUpdate.releaseDates({ { version = "1.0.0" } }) == nil,
    "releases without dates report no data")
  check(ModUpdate.releaseDates({}) == nil, "empty list reports no data")
  check(ModUpdate.releaseDates(nil) == nil, "nil list reports no data")
end

-- totalDownloads: totals across releases; nil until data actually exists
do
  local new = {
    { version = "1.0.0", downloads = 41 },
    { version = "1.1.0", downloads = 9 },
  }
  local dl = ModUpdate.totalDownloads(new)
  eq(dl.total, 50, "totals across releases")
  eq(dl.releases, 2, "counts the releases")
  dl = ModUpdate.totalDownloads({ { version = "1.0.0", downloads = 0 } })
  eq(dl.total, 0, "a real zero stays zero")
  dl = ModUpdate.totalDownloads({ { version = "1.0.0" } })
  check(dl == nil, "pre-downloads cache rows report no data")
  check(ModUpdate.totalDownloads({}) == nil, "empty list reports no data")
  check(ModUpdate.totalDownloads(nil) == nil, "nil list reports no data")
end

-- formatCount: thousands separators, never throws
eq(ModUpdate.formatCount(0), "0", "zero formats plain")
eq(ModUpdate.formatCount(999), "999", "below 1000 formats plain")
eq(ModUpdate.formatCount(1000), "1,000", "1000 gets a separator")
eq(ModUpdate.formatCount(1234567), "1,234,567", "large counts group by 3")
eq(ModUpdate.formatCount("12345"), "12,345", "numeric strings are accepted")
eq(ModUpdate.formatCount(nil), "0", "nil formats as zero")
eq(ModUpdate.formatCount("garbage"), "0", "garbage formats as zero")

-- abbrevCount: what a browse card has room for
eq(ModUpdate.abbrevCount(0), "0", "zero abbreviates to itself")
eq(ModUpdate.abbrevCount(999), "999", "below 1000 stays exact")
eq(ModUpdate.abbrevCount(1000), "1k", "a round thousand drops its decimal")
eq(ModUpdate.abbrevCount(1578), "1.6k", "thousands round to one decimal")
eq(ModUpdate.abbrevCount(24000), "24k", "a round figure keeps no .0")
eq(ModUpdate.abbrevCount(999999), "1M", "no count ever reads as 1000k")
eq(ModUpdate.abbrevCount(1234567), "1.2M", "millions abbreviate too")
eq(ModUpdate.abbrevCount("1578"), "1.6k", "numeric strings are accepted")
eq(ModUpdate.abbrevCount(nil), "?", "an unknown count is not a zero")
eq(ModUpdate.abbrevCount("garbage"), "?", "garbage is unknown, not a zero")

-- downloadsShort / trendingLine: the card and detail forms
eq(ModUpdate.downloadsShort(1578), "1.6k downloads", "the card form abbreviates")
eq(ModUpdate.downloadsShort(0), "0 downloads", "a real zero is still stated")
eq(ModUpdate.downloadsShort(nil), "? downloads",
  "an unknown count says so rather than vanishing or reading as zero")
eq(ModUpdate.trendingLine(388, 30), "388 in the last 30 days",
  "the trending line names its window")
eq(ModUpdate.trendingLine(388, 12), "388 in the last 12 days",
  "a short window says so rather than claiming a month")
eq(ModUpdate.trendingLine(388, nil), "388 recently",
  "a count with no window still reads")
check(ModUpdate.trendingLine(nil, 30) == nil,
  "no trailing-window count means no trending line")

-- statsLine: the shared launcher row line, part by part
eq(ModUpdate.statsLine(1234567, "2024-05-31", "2026-07-01"),
  "1,234,567 downloads across all releases  -  Released 2024-05-31  -  Updated 2026-07-01",
  "full stats line")
eq(ModUpdate.statsLine(82, nil, nil),
  "82 downloads across all releases",
  "downloads alone")
eq(ModUpdate.statsLine(nil, "2024-05-31", "2026-07-01"),
  "Released 2024-05-31  -  Updated 2026-07-01",
  "dates alone")
eq(ModUpdate.statsLine(0, nil, nil),
  "0 downloads across all releases",
  "a real zero still shows")
check(ModUpdate.statsLine(nil, nil, nil) == nil,
  "no data at all means no line")

-- cacheUsable: a cache entry from before downloads existed must not be
-- trusted, everything current is
do
  local old = { checkedAt = os.time(),
    releases = { { version = "1.0.0", tag = "v1.0.0" } } }
  check(not ModUpdate.cacheUsable(old), "pre-downloads cache is unusable")
  local zero = { checkedAt = os.time(),
    releases = { { version = "1.0.0", downloads = 0 } } }
  check(ModUpdate.cacheUsable(zero), "current cache is usable even at zero")
  check(ModUpdate.cacheUsable({ checkedAt = os.time(), releases = {} }),
    "empty release list stays usable")
  check(not ModUpdate.cacheUsable(nil), "nil cache is unusable")
  check(not ModUpdate.cacheUsable({}), "cache without releases is unusable")
end

-- fetchReleases: an old-format cache entry is refetched once and rewritten
-- in the current format; a current one is served untouched
do
  local HostShell = require("src.core.HostShell")
  local realRead, realWrite = ModUpdate.readCache, ModUpdate.writeCache
  local realCanFetch, realHttpGet = HostShell.canFetch, HostShell.httpGet
  local cached, fetched
  ModUpdate.readCache = function() return cached end
  ModUpdate.writeCache = function(repo, releases)
    fetched = releases
    return true
  end
  HostShell.canFetch = function() return true end
  HostShell.httpGet = function()
    return Json.encode({ {
      tag_name = "v1.0.0",
      assets = { { name = "demo-1.0.0.zip",
        browser_download_url = "https://x/d.zip", download_count = 7 } },
    } })
  end

  cached = { checkedAt = os.time(),
    releases = { { version = "1.0.0", tag = "v1.0.0" } } }
  fetched = nil
  local list = ModUpdate.fetchReleases("acme/mod", "demo")
  check(fetched ~= nil, "old-format cache triggers a refetch")
  check(list[1].downloads == 7, "refetched release carries downloads")

  cached = { checkedAt = os.time(),
    releases = { { version = "1.0.0", tag = "v1.0.0", downloads = 0 } } }
  fetched = nil
  list = ModUpdate.fetchReleases("acme/mod", "demo")
  check(fetched == nil, "current cache is served without refetch")
  check(list[1].downloads == 0, "cached zero stays zero")

  ModUpdate.readCache, ModUpdate.writeCache = realRead, realWrite
  HostShell.canFetch, HostShell.httpGet = realCanFetch, realHttpGet
end

-- statsForReleases: one resolver over a release list, the FIND MODS path
do
  local stats = ModUpdate.statsForReleases({
    { version = "1.0.0", downloads = 41, published = "2024-05-31" },
    { version = "1.1.0", downloads = 9, published = "2025-11-02" },
  })
  eq(stats.total, 50, "total downloads across releases")
  eq(stats.first, "2024-05-31", "first release date")
  eq(stats.latest, "2025-11-02", "latest release date")
  check(ModUpdate.statsForReleases({ { version = "1.0.0" } }) == nil,
    "a list with neither counts nor dates resolves to nil")
  check(ModUpdate.statsForReleases(nil) == nil, "nil resolves to nil")
  local datesOnly = ModUpdate.statsForReleases({
    { version = "1.0.0", published = "2024-05-31" },
  })
  eq(datesOnly.total, nil, "dates without counts keep total nil")
  eq(datesOnly.first, "2024-05-31", "but keep the date")
end

print("ok mod_update_tests")
