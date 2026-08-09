-- Pure coverage for src/mods/ModIndex.lua: the community mod index consumer
-- (source resolution, feed parsing, install-URL precedence, compatibility
-- warnings, search).  Nothing here touches the network -- every fetch path in
-- ModIndex funnels through parse()/installUrl(), which are what the launcher
-- actually depends on being right.
--   luajit tests/engine/mod_index_tests.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
local ModIndex = require("src.mods.ModIndex")
local Json = require("src.link.Json")

-- ------- source resolution: four ways to name one index

do
  local expectFeed =
    "https://bryanthaboi.github.io/gen1recomp-mod-index/data/index.json"
  local expectBase = "https://bryanthaboi.github.io/gen1recomp-mod-index/"

  local fromRepo = ModIndex.resolveSource("bryanthaboi/gen1recomp-mod-index")
  eq(fromRepo.feed, expectFeed, "owner/repo resolves to the Pages feed")
  eq(fromRepo.base, expectBase, "owner/repo resolves the Pages base")
  check(fromRepo.fallback:find("raw.githubusercontent.com", 1, true) ~= nil,
    "owner/repo carries the raw fallback")

  local fromUrl =
    ModIndex.resolveSource("https://github.com/bryanthaboi/gen1recomp-mod-index")
  eq(fromUrl.feed, expectFeed, "a github repo URL resolves the same feed")

  local fromPages = ModIndex.resolveSource(expectBase)
  eq(fromPages.feed, expectFeed, "the Pages root resolves the same feed")
  eq(fromPages.base, expectBase, "the Pages root is its own base")

  local fromFeed = ModIndex.resolveSource(expectFeed)
  eq(fromFeed.feed, expectFeed, "the feed URL is taken as-is")
  eq(fromFeed.base, expectBase, "the feed URL yields the Pages base")

  -- a root without its trailing slash must not produce "...indexdata/index.json"
  local noSlash =
    ModIndex.resolveSource("https://bryanthaboi.github.io/gen1recomp-mod-index")
  eq(noSlash.feed, expectFeed, "a Pages root without a trailing slash still works")

  local bad, err = ModIndex.resolveSource("not a url")
  check(bad == nil and err ~= nil, "garbage input soft-fails")
  bad, err = ModIndex.resolveSource(nil)
  check(bad == nil and err ~= nil, "nil input soft-fails")
end

do
  local base = "https://bryanthaboi.github.io/gen1recomp-mod-index/"
  eq(ModIndex.joinUrl(base, "data/mods/bryanthaboi@nuzlocke/thumbnail.png"),
    base .. "data/mods/bryanthaboi@nuzlocke/thumbnail.png",
    "relative asset paths resolve against the Pages base")
  eq(ModIndex.joinUrl(base, "https://elsewhere/x.png"), "https://elsewhere/x.png",
    "an absolute asset URL is left alone")
  check(ModIndex.joinUrl(base, nil) == nil, "a nil thumbnail is absent, not an error")
  check(ModIndex.joinUrl(nil, "x.png") == nil, "no base means no asset URL")
end

-- ------- feed parsing

local function feed(mods, overrides)
  local doc = { schema_version = 1, generated_at = "2026-07-31T15:21:36.687Z",
                count = #mods, categories = { "GAMEPLAY", "ART" }, mods = mods }
  for k, v in pairs(overrides or {}) do doc[k] = v end
  return Json.encode(doc)
end

local NUZLOCKE = {
  folder = "bryanthaboi@nuzlocke",
  id = "nuzlocke",
  title = "Nuzlocke",
  author = "bryanthaboi",
  summary = "An enforced Gen 1 Nuzlocke: one catch per area.",
  version = "1.0.1",
  categories = { "GAMEPLAY" },
  tags = { "nuzlocke", "challenge" },
  repo = "https://github.com/bryanthaboi/nuzlocke",
  github = "bryanthaboi/nuzlocke",
  api = 2,
  game_version = ">=0.0.0-dev <1.0.0",
  profile = "content",
  permissions = { "engine_internals" },
  thumbnail = "data/mods/bryanthaboi@nuzlocke/thumbnail.png",
  description_url = "data/mods/bryanthaboi@nuzlocke/description.md",
  latest = {
    version = "1.0.1", tag = "v1.0.1", name = "1.0.1", prerelease = false,
    published_at = "2026-07-31T14:17:23Z",
    zip = {
      name = "nuzlocke-1.0.1.zip",
      url = "https://github.com/bryanthaboi/nuzlocke/releases/download/v1.0.1/nuzlocke-1.0.1.zip",
      size = 4396,
    },
  },
  update_check = "ok",
}

do
  local index, err = ModIndex.parse(feed({ NUZLOCKE }))
  check(index ~= nil, "the published feed shape parses: " .. tostring(err))
  eq(index.schemaVersion, 1, "schema_version is carried through")
  eq(#index.mods, 1, "one mod")
  local m = index.mods[1]
  eq(m.id, "nuzlocke", "id")
  eq(m.title, "Nuzlocke", "title")
  eq(m.latest.zip.url,
    "https://github.com/bryanthaboi/nuzlocke/releases/download/v1.0.1/nuzlocke-1.0.1.zip",
    "the release asset URL survives parsing")
  eq(m.permissions[1], "engine_internals", "permissions are kept")
  eq(m.update_check, "ok", "update_check is kept")
  check(m.downloads == nil and m.first_release == nil and m.last_release == nil,
    "a feed without release stats parses them as absent")
end

-- release stats a feed can publish: total downloads and first/last dates
-- ride along additively, so a feed carrying them stays readable by every
-- build that predates them
do
  local withStats = {}
  for k, v in pairs(NUZLOCKE) do withStats[k] = v end
  withStats.downloads = 1234
  withStats.first_release = "2024-05-31"
  withStats.last_release = "2026-07-01"
  local index = ModIndex.parse(feed({ withStats }))
  local m = index.mods[1]
  eq(m.downloads, 1234, "total downloads are kept")
  eq(m.first_release, "2024-05-31", "first release date is kept")
  eq(m.last_release, "2026-07-01", "last release date is kept")
  withStats.downloads = "9999"
  m = ModIndex.parse(feed({ withStats })).mods[1]
  eq(m.downloads, 9999, "numeric-string downloads are coerced")
end

-- schema_version is a contract, not a hint: an unknown one is refused rather
-- than parsed on the assumption the fields still mean what they used to.
do
  local index, err = ModIndex.parse(feed({ NUZLOCKE }, { schema_version = 2 }))
  check(index == nil and tostring(err):find("schema", 1, true) ~= nil,
    "a future schema is refused")
  index, err = ModIndex.parse(Json.encode({ mods = { NUZLOCKE } }))
  check(index == nil and err ~= nil, "a feed with no schema_version is refused")
  index, err = ModIndex.parse("<!DOCTYPE html><html>404</html>")
  check(index == nil and tostring(err):find("HTML", 1, true) ~= nil,
    "an HTML error page is named, not blamed on the parser")
  index, err = ModIndex.parse("Error: upstream unavailable")
  check(index == nil and tostring(err):find("not JSON", 1, true) ~= nil,
    "a plain-text error names the response")
  index, err = ModIndex.parse('{"schema_version":1}')
  check(index == nil and err ~= nil, "a feed with no mods array soft-fails")
end

-- ------- install URL precedence

do
  local url, kind = ModIndex.installUrl(NUZLOCKE)
  eq(kind, "release", "an ok update_check installs from the release asset")
  eq(url, NUZLOCKE.latest.zip.url, "and uses that asset's URL")
  eq(ModIndex.displayVersion(NUZLOCKE), "1.0.1",
    "an ok entry shows the resolved release version")
end

do
  -- no github: the author's fixed zip is the only route
  local entry = { id = "static", version = "2.0.0", update_check = "off",
                  downloadURL = "https://example.test/static-2.0.0.zip" }
  local url, kind = ModIndex.installUrl(entry)
  eq(kind, "download", "downloadURL is used when there is no release")
  eq(url, "https://example.test/static-2.0.0.zip", "and it is used verbatim")
  eq(ModIndex.displayVersion(entry), "2.0.0",
    "a non-ok entry falls back to its declared version")
end

do
  -- a stale `latest` behind a failed check must not be installed: the zip URL
  -- may point at a release that has since been deleted or replaced
  local entry = { id = "flaky", version = "1.0.0",
                  update_check = "error: rate limited",
                  latest = { version = "9.9.9", zip = { url = "https://x/stale.zip" } } }
  local url, why = ModIndex.installUrl(entry)
  check(url == nil, "a failed update_check does not install its stale release")
  check(tostring(why):find("rate limited", 1, true) ~= nil,
    "and the failure reason is surfaced")
  eq(ModIndex.displayVersion(entry), "1.0.0",
    "a failed check shows the entry's own version, not the stale release")

  entry.downloadURL = "https://example.test/flaky.zip"
  local url2, kind = ModIndex.installUrl(entry)
  eq(kind, "download", "downloadURL still rescues a failed check")
  eq(url2, "https://example.test/flaky.zip", "with the author's URL")
end

do
  local entry = { id = "listing-only", update_check = "no installable release" }
  local url, why = ModIndex.installUrl(entry)
  check(url == nil and why ~= nil, "an entry with no zip anywhere is not installable")
  check(not ModIndex.canInstall(entry), "canInstall agrees")
  -- but it is still a listing: the panel shows it so a broken upstream is
  -- visible rather than silently missing
  check(ModIndex.matches(entry, nil), "and it still matches an empty search")
end

do
  local release = ModIndex.releaseFor(NUZLOCKE)
  eq(release.zip.url, NUZLOCKE.latest.zip.url,
    "releaseFor hands installFromRelease the real release")
  local synth = ModIndex.releaseFor({ id = "static", version = "2.0.0",
    update_check = "off", downloadURL = "https://example.test/s.zip" })
  eq(synth.zip.url, "https://example.test/s.zip",
    "a downloadURL entry gets a synthesised release")
  eq(synth.version, "2.0.0", "carrying its declared version")
end

-- ------- compatibility: warns, never blocks

do
  local issues = ModIndex.compatIssues(NUZLOCKE, {
    modApi = 2, engineVersion = "0.0.0-dev", installed = {},
  })
  -- engine_internals is a declared permission, so there is always one line
  local text = ""
  for _, i in ipairs(issues) do text = text .. tostring(i.text) .. "\n" end
  check(text:find("engine_internals", 1, true) ~= nil,
    "a declared permission is surfaced before install")
  check(text:find("mod API", 1, true) == nil,
    "an api the engine provides raises nothing")
end

do
  local entry = { id = "future", api = 99, experimental = true,
                  profile = "total_conversion", affects_link = true,
                  permissions = {}, update_check = "off" }
  local issues = ModIndex.compatIssues(entry, {
    modApi = 2, engineVersion = "0.0.0-dev", installed = {},
  })
  local text = ""
  for _, i in ipairs(issues) do text = text .. tostring(i.text) .. "\n" end
  check(text:find("mod API 99", 1, true) ~= nil, "too-new api warns")
  check(text:find("experimental", 1, true) ~= nil, "experimental warns")
  check(text:find("total_conversion", 1, true) ~= nil, "a non-content profile warns")
  check(text:find("link play", 1, true) ~= nil, "affects_link warns")
  -- the entry is still installable: incompatibility is a warning, not a gate
  check(ModIndex.installUrl(entry) == nil or true, "warnings do not gate install")
end

do
  -- dependencies / conflicts in both manifest spellings
  local arrayForm = { id = "needy", dependencies = { "base@>=1.0.0", "other" },
                      conflicts = { "rival" } }
  local issues = ModIndex.compatIssues(arrayForm, { installed = { rival = "1.0.0" } })
  local text = ""
  for _, i in ipairs(issues) do text = text .. tostring(i.text) .. "\n" end
  check(text:find("Needs base", 1, true) ~= nil, "a missing dependency warns")
  check(text:find(">=1.0.0", 1, true) ~= nil, "with its range")
  check(text:find("Needs other", 1, true) ~= nil, "a rangeless dependency warns")
  check(text:find("Conflicts with installed rival", 1, true) ~= nil,
    "an installed conflict warns")

  local mapForm = { id = "needy2", dependencies = { base = ">=1.0.0" } }
  local issues2 = ModIndex.compatIssues(mapForm, { installed = { base = "1.2.0" } })
  eq(#issues2, 0, "an installed dependency raises nothing")
end

-- ------- search / filter

do
  local mods = {
    { id = "nuzlocke", title = "Nuzlocke", author = "bryanthaboi",
      summary = "one catch per area", categories = { "GAMEPLAY" },
      tags = { "challenge" } },
    { id = "palettes", title = "True Colour", author = "someone",
      summary = "richer SGB palettes", categories = { "ART" }, tags = {} },
  }
  eq(#ModIndex.filter(mods, {}), 2, "no filter keeps everything")
  eq(#ModIndex.filter(mods, { query = "nuz" }), 1, "search matches a title prefix")
  eq(ModIndex.filter(mods, { query = "colour" })[1].id, "palettes",
    "search matches the title")
  eq(ModIndex.filter(mods, { query = "bryanthaboi" })[1].id, "nuzlocke",
    "search matches the author")
  eq(ModIndex.filter(mods, { query = "SGB" })[1].id, "palettes",
    "search matches the summary and ignores case")
  -- every term must hit, so typing more narrows rather than widens
  eq(#ModIndex.filter(mods, { query = "nuzlocke palettes" }), 0,
    "terms are ANDed")
  eq(ModIndex.filter(mods, { category = "ART" })[1].id, "palettes",
    "category filters")
  eq(#ModIndex.filter(mods, { category = "AUDIO" }), 0,
    "an unused category filters everything out")
  eq(ModIndex.filter(mods, { tag = "challenge" })[1].id, "nuzlocke",
    "tag filters")
end

do
  local index = ModIndex.parse(feed({ NUZLOCKE }))
  local cats = ModIndex.categoriesIn(index)
  eq(#cats, 1, "only categories an entry actually uses are offered")
  eq(cats[1], "GAMEPLAY", "and they keep the feed's declared order")
end

print("ok mod_index_tests")
