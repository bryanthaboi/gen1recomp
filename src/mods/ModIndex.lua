-- Community mod index consumer (the "Find mods" launcher tab).
--
-- An index is metadata only: a published index.json feed listing mods that
-- live in their authors' own repos.  Nothing here clones or vendors the index
-- repo -- the feed is the whole contract, and every install still goes through
-- the same LauncherMods.installZip path an "Import mod .zip" does, so a listing
-- buys a mod no trust it would not otherwise have.
--
-- Shape of the split mirrors src/mods/ModUpdate.lua, which this borrows its
-- host I/O from: everything above "host I/O" is pure (no love, no filesystem,
-- no network) so the engine tier can table-drive it, and the fetch/cache half
-- reaches for curl and options.lua.
--
-- Sources are never added automatically.  options.modIndexes is a player-built
-- list -- adding an index is a deliberate act of trusting whoever publishes it,
-- so the launcher ships with none and asks.
--
-- schema_version is a hard gate, not a hint: a bumped feed may reuse a field
-- name for something else, so an unknown version is refused outright rather
-- than parsed hopefully.

local ModIndex = {}
local AppMessage = require("src.core.AppMessage")

-- The feed is rebuilt on every push and refreshed nightly, so a day-old copy
-- is the worst a cached listing can be.  ModUpdate's six hours is tuned for a
-- single repo's releases; a whole index is heavier and changes more slowly.
ModIndex.CACHE_TTL = 24 * 60 * 60
ModIndex.SCHEMA_VERSION = 1

-- ------- pure: source resolution

local function trim(s)
  return (tostring(s):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Split "owner/repo" out of the several ways a player can name a GitHub repo.
local function githubSlug(url)
  local owner, repo = url:match("^https?://github%.com/([%w%-%.]+)/([%w%-%.]+)")
  if not owner then
    owner, repo = url:match("^([%w%-%.]+)/([%w%-%.]+)$")
  end
  if not owner then return nil end
  repo = repo:gsub("%.git$", "")
  return owner, repo
end

-- resolveSource(input) -> { feed, base, fallback, label } | nil, err
--
-- Players paste whichever URL they happened to have, so all four shapes of the
-- same index resolve to one source: the Pages root, the feed file itself, the
-- GitHub repo page, or a bare "owner/repo".  `base` is what relative thumbnail
-- and description_url paths resolve against, and it always keeps its trailing
-- slash so joinUrl can stay a concatenation.
--
-- The raw.githubusercontent fallback exists because Pages deploys lag a push
-- by a minute or two; it is only ever consulted when the feed fetch fails.
function ModIndex.resolveSource(input)
  if type(input) ~= "string" then return nil, AppMessage("Missing index URL") end
  local url = trim(input)
  if url == "" then return nil, AppMessage("Missing index URL") end

  local owner, repo = githubSlug(url)
  if owner then
    return {
      feed = ("https://%s.github.io/%s/data/index.json"):format(owner, repo),
      base = ("https://%s.github.io/%s/"):format(owner, repo),
      fallback = ("https://raw.githubusercontent.com/%s/%s/main/site/data/index.json")
        :format(owner, repo),
      label = owner .. "/" .. repo,
    }
  end

  if not url:match("^https?://") then
    return nil, AppMessage("The index must be an HTTP(S) URL or owner/repo")
  end

  -- A feed URL names the file; the Pages root is what is left once the
  -- "data/index.json" tail comes off (any other .json keeps only its folder).
  if url:match("%.json$") then
    local base = url:match("^(.*/)data/index%.json$") or url:match("^(.*/)")
    return { feed = url, base = base or url, label = ModIndex.labelFor(base or url) }
  end

  local base = url:match("/$") and url or (url .. "/")
  return {
    feed = base .. "data/index.json",
    base = base,
    label = ModIndex.labelFor(base),
  }
end

-- A short human name for a source row: "owner/repo" for a Pages host, else the
-- host plus first path segment.  Only ever cosmetic.
function ModIndex.labelFor(url)
  url = tostring(url or "")
  local owner, repo = url:match("^https?://([%w%-%.]+)%.github%.io/([%w%-%.]+)/")
  if owner then return owner .. "/" .. repo end
  local host, first = url:match("^https?://([^/]+)/([^/]*)")
  if host and first and first ~= "" then return host .. "/" .. first end
  return host or url
end

-- joinUrl(base, rel) -> absolute URL | nil
-- Relative feed paths resolve against the Pages root; an already-absolute one
-- is handed back untouched (the schema allows either), and anything else --
-- nil, "", a non-string -- is simply absent rather than an error, because a
-- missing thumbnail is not a broken index.
function ModIndex.joinUrl(base, rel)
  if type(rel) ~= "string" or rel == "" then return nil end
  if rel:match("^https?://") then return rel end
  if type(base) ~= "string" or base == "" then return nil end
  if not base:match("/$") then base = base .. "/" end
  return base .. (rel:gsub("^/", ""))
end

-- ------- pure: feed parsing

local function str(v)
  return type(v) == "string" and v or nil
end

local function strArray(v)
  local out = {}
  if type(v) == "table" then
    for _, entry in ipairs(v) do
      if type(entry) == "string" then out[#out + 1] = entry end
    end
  end
  return out
end

-- Decode one release blob from the feed's `latest` field into the same shape
-- ModUpdate.parseRelease produces, so LauncherMods.installFromRelease takes it
-- without a translation layer.
local function parseLatest(raw)
  if type(raw) ~= "table" then return nil end
  local zip = nil
  if type(raw.zip) == "table" and str(raw.zip.url) then
    zip = { name = str(raw.zip.name), url = raw.zip.url,
            size = tonumber(raw.zip.size) }
  end
  return {
    version = str(raw.version),
    tag = str(raw.tag),
    name = str(raw.name),
    prerelease = raw.prerelease == true,
    published_at = str(raw.published_at),
    zip = zip,
  }
end

local function parseEntry(raw)
  if type(raw) ~= "table" or not str(raw.id) then return nil end
  return {
    folder = str(raw.folder),
    id = raw.id,
    title = str(raw.title) or raw.id,
    author = str(raw.author),
    version = str(raw.version),
    summary = str(raw.summary) or "",
    categories = strArray(raw.categories),
    tags = strArray(raw.tags),
    license = str(raw.license),
    repo = str(raw.repo),
    github = str(raw.github),
    downloadURL = str(raw.downloadURL),
    api = tonumber(raw.api),
    game_version = str(raw.game_version),
    profile = str(raw.profile),
    affects_link = raw.affects_link == true,
    experimental = raw.experimental == true,
    permissions = strArray(raw.permissions),
    dependencies = raw.dependencies,
    conflicts = raw.conflicts,
    thumbnail = str(raw.thumbnail),
    description_url = str(raw.description_url),
    -- Optional release stats a feed author can publish: total downloads
    -- across all releases plus first/last release dates.  Additive-only,
    -- so a feed that carries them stays readable by every build that
    -- predates them (and one that does not still renders fine here).
    downloads = tonumber(raw.downloads),
    first_release = str(raw.first_release),
    last_release = str(raw.last_release),
    latest = parseLatest(raw.latest),
    update_check = str(raw.update_check) or "pending",
  }
end

-- parse(jsonText [, Json]) -> { schemaVersion, generatedAt, categories, mods }
--                          |  nil, err
-- Never throws: a truncated download, an HTML error page, or a feed from a
-- future schema all come back as a message the panel can print.
function ModIndex.parse(jsonText, Json)
  Json = Json or require("src.link.Json")
  local notJson = Json.describeUnexpected(jsonText)
  if notJson then return nil, notJson end
  local ok, result, err = pcall(function()
    local doc, decodeErr = Json.decode(jsonText)
    if type(doc) ~= "table" then
      return nil, decodeErr or AppMessage("index.json is not an object")
    end
    local schema = tonumber(doc.schema_version)
    if schema == nil then
      return nil, AppMessage("index.json has no schema_version")
    end
    if schema ~= ModIndex.SCHEMA_VERSION then
      return nil, AppMessage(
        "Index schema %d is not supported (this build reads %d)",
        schema, ModIndex.SCHEMA_VERSION)
    end
    if type(doc.mods) ~= "table" then
      return nil, AppMessage("index.json has no mods array")
    end
    local mods = {}
    for _, raw in ipairs(doc.mods) do
      local entry = parseEntry(raw)
      if entry then mods[#mods + 1] = entry end
    end
    return {
      schemaVersion = schema,
      generatedAt = str(doc.generated_at),
      categories = strArray(doc.categories),
      mods = mods,
    }
  end)
  if not ok then
    return nil, AppMessage("Could not read the index: %s", tostring(result))
  end
  return result, err
end

-- ------- pure: install resolution

-- installUrl(entry) -> url, kind  |  nil, reason
--
-- The same order the engine's zip import already implies: a verified release
-- asset first, then the author's fixed downloadURL.  A GitHub source-archive
-- URL is never invented -- codeload gives you the repo, not the built mod, and
-- the folder layout would be wrong even when the download succeeds.
function ModIndex.installUrl(entry)
  if type(entry) ~= "table" then return nil, AppMessage("No index entry") end
  if entry.update_check == "ok" and entry.latest and entry.latest.zip
      and entry.latest.zip.url then
    return entry.latest.zip.url, "release"
  end
  if entry.downloadURL and entry.downloadURL ~= "" then
    return entry.downloadURL, "download"
  end
  if entry.update_check == "off" then
    return nil, AppMessage("The author does not publish installable releases")
  end
  if entry.update_check == "no installable release" then
    return nil, AppMessage("No release with a .zip file yet")
  end
  if type(entry.update_check) == "string"
      and entry.update_check:match("^error") then
    return nil, entry.update_check
  end
  return nil, AppMessage("Nothing installable is listed")
end

function ModIndex.canInstall(entry)
  return ModIndex.installUrl(entry) ~= nil
end

-- The version to show on a card: the release the index resolved when it could
-- reach GitHub, else whatever meta.json declared.
function ModIndex.displayVersion(entry)
  if type(entry) ~= "table" then return "?" end
  if entry.update_check == "ok" and entry.latest and entry.latest.version then
    return entry.latest.version
  end
  return entry.version or "?"
end

-- The release table LauncherMods.installFromRelease wants.  A downloadURL
-- entry has no release behind it, so one is synthesised around the URL; the
-- installer still validates the manifest inside and still refuses a zip whose
-- id is not the one being installed.
function ModIndex.releaseFor(entry)
  local url, kind = ModIndex.installUrl(entry)
  if not url then return nil, kind end
  if kind == "release" then return entry.latest end
  return {
    version = ModIndex.displayVersion(entry),
    zip = { url = url, name = entry.id .. ".zip" },
  }
end

-- ------- pure: compatibility

-- compatIssues(entry, ctx) -> array of { level, text }
--
-- Soft gate by design: an index entry is metadata an author wrote, possibly
-- months ago, and hiding a mod because a range looks wrong is how a working
-- mod becomes invisible.  Everything here warns; the confirm dialog shows the
-- list and the player decides.  ctx carries { modApi, engineVersion,
-- installed = { id -> version }, enabled = { id -> true } }.
function ModIndex.compatIssues(entry, ctx)
  local out = {}
  if type(entry) ~= "table" then return out end
  ctx = ctx or {}
  local function warn(text) out[#out + 1] = { level = "warn", text = text } end

  local modApi = tonumber(ctx.modApi)
  if entry.api and modApi and entry.api > modApi then
    warn(AppMessage("Needs mod API %d; this build provides %d",
      entry.api, modApi))
  end

  if entry.game_version and ctx.engineVersion then
    local okSemver, Semver = pcall(require, "src.mods.Semver")
    if okSemver and not Semver.satisfies(ctx.engineVersion, entry.game_version) then
      warn(AppMessage("Needs engine %s (have %s)",
        entry.game_version, ctx.engineVersion))
    end
  end

  if entry.profile and entry.profile ~= "content" then
    warn(AppMessage("Profile '%s' changes engine behaviour beyond content",
      entry.profile))
  end
  if entry.affects_link then
    warn(AppMessage("Changes link play; both sides need the same mods"))
  end
  if entry.experimental then
    warn(AppMessage("Marked experimental by its author"))
  end

  for _, name in ipairs(entry.permissions or {}) do
    warn(AppMessage("Requests permission: %s", name))
  end

  -- dependencies / conflicts arrive as the manifest's own vocabulary: either
  -- an array of "id" / "id@<range>" strings or an id -> range map.
  local installed = ctx.installed or {}
  local function eachSpec(spec, fn)
    if type(spec) ~= "table" then return end
    for k, v in pairs(spec) do
      if type(k) == "number" and type(v) == "string" then
        local id, range = v:match("^([^@]+)@(.+)$")
        fn(id or v, range)
      elseif type(k) == "string" then
        fn(k, type(v) == "string" and v or nil)
      end
    end
  end

  eachSpec(entry.dependencies, function(id, range)
    if installed[id] == nil then
      local spec = id .. (range and (" " .. range) or "")
      warn(AppMessage("Needs %s (not installed)", spec))
    end
  end)
  eachSpec(entry.conflicts, function(id)
    if installed[id] ~= nil then
      warn(AppMessage("Conflicts with installed %s", id))
    end
  end)

  return out
end

-- ------- pure: search / filter

local function haystack(entry)
  return (tostring(entry.title or "") .. " " .. tostring(entry.author or "")
    .. " " .. tostring(entry.summary or "") .. " " .. tostring(entry.id or ""))
    :lower()
end

-- matches(entry, query) -> bool.  Every whitespace-separated term must appear
-- somewhere in title / author / summary / id, so typing more narrows.
function ModIndex.matches(entry, query)
  if type(query) ~= "string" or trim(query) == "" then return true end
  local hay = haystack(entry)
  for term in trim(query):lower():gmatch("%S+") do
    if not hay:find(term, 1, true) then return false end
  end
  return true
end

-- filter(mods, opts) -> a new array.  opts = { query, category, tag }.
-- Category and tag compare case-insensitively; feed order (already sorted by
-- title) is preserved.
function ModIndex.filter(mods, opts)
  opts = opts or {}
  local want = opts.category and tostring(opts.category):lower() or nil
  local wantTag = opts.tag and tostring(opts.tag):lower() or nil
  local out = {}
  for _, entry in ipairs(mods or {}) do
    local keep = ModIndex.matches(entry, opts.query)
    if keep and want then
      keep = false
      for _, c in ipairs(entry.categories or {}) do
        if tostring(c):lower() == want then keep = true; break end
      end
    end
    if keep and wantTag then
      keep = false
      for _, t in ipairs(entry.tags or {}) do
        if tostring(t):lower() == wantTag then keep = true; break end
      end
    end
    if keep then out[#out + 1] = entry end
  end
  return out
end

-- Every category actually used by a feed, in the feed's declared order, with
-- anything an entry names that the header forgot appended.  Drives the filter
-- row without hard-coding the vocabulary.
function ModIndex.categoriesIn(index)
  local out, seen = {}, {}
  if type(index) ~= "table" then return out end
  local used = {}
  for _, entry in ipairs(index.mods or {}) do
    for _, c in ipairs(entry.categories or {}) do used[c] = true end
  end
  for _, c in ipairs(index.categories or {}) do
    if used[c] and not seen[c] then seen[c] = true; out[#out + 1] = c end
  end
  for _, entry in ipairs(index.mods or {}) do
    for _, c in ipairs(entry.categories or {}) do
      if not seen[c] then seen[c] = true; out[#out + 1] = c end
    end
  end
  return out
end

-- ------- sources (options.modIndexes)

local function loadOptions()
  return require("src.core.SaveData").loadOptions()
end

-- The player's index list, normalised.  Rows are { url, feed, base, fallback,
-- label }; `url` is what they typed, kept so the row reads back the way they
-- entered it.
function ModIndex.sources()
  local ok, opts = pcall(loadOptions)
  if not ok or type(opts) ~= "table" then return {} end
  local out = {}
  for _, row in ipairs(opts.modIndexes or {}) do
    if type(row) == "table" and type(row.feed) == "string" then
      out[#out + 1] = row
    end
  end
  return out
end

-- addSource(input) -> row | nil, err.  Idempotent on the resolved feed URL, so
-- pasting the repo page and the Pages root in either order adds one source.
function ModIndex.addSource(input)
  local source, err = ModIndex.resolveSource(input)
  if not source then return nil, err end
  local ok, result, addErr = pcall(function()
    local SaveData = require("src.core.SaveData")
    local opts = loadOptions()
    opts.modIndexes = opts.modIndexes or {}
    for _, row in ipairs(opts.modIndexes) do
      if row.feed == source.feed then
        return nil, AppMessage("That index is already added")
      end
    end
    source.url = trim(input)
    opts.modIndexes[#opts.modIndexes + 1] = source
    SaveData.saveOptions(opts)
    return source
  end)
  if not ok then
    return nil, AppMessage("Could not save the index: %s", tostring(result))
  end
  return result, addErr
end

-- removeSource(feed) -> true | nil, err.  Drops the cached listing with it:
-- keeping a feed's mods around after its source is gone is how a stale card
-- outlives the index it came from.
function ModIndex.removeSource(feed)
  if type(feed) ~= "string" or feed == "" then
    return nil, AppMessage("Missing index")
  end
  local ok, result = pcall(function()
    local SaveData = require("src.core.SaveData")
    local opts = loadOptions()
    local kept, found = {}, false
    for _, row in ipairs(opts.modIndexes or {}) do
      if row.feed == feed then found = true else kept[#kept + 1] = row end
    end
    if not found then return nil end
    opts.modIndexes = kept
    if type(opts.modIndexCache) == "table" then opts.modIndexCache[feed] = nil end
    SaveData.saveOptions(opts)
    return true
  end)
  if not ok then return nil, tostring(result) end
  if not result then return nil, AppMessage("That index is not in the list") end
  return true
end

-- ------- cache (options.modIndexCache[feed])

function ModIndex.readCache(feed)
  if type(feed) ~= "string" or feed == "" then return nil end
  local ok, opts = pcall(loadOptions)
  if not ok or type(opts) ~= "table" then return nil end
  local entry = opts.modIndexCache and opts.modIndexCache[feed]
  if type(entry) ~= "table" or type(entry.checkedAt) ~= "number" then
    return nil
  end
  if type(entry.mods) ~= "table" then return nil end
  return entry
end

function ModIndex.cacheFresh(entry, now, ttl)
  now = now or os.time()
  ttl = ttl or ModIndex.CACHE_TTL
  return entry ~= nil and type(entry.checkedAt) == "number"
    and (now - entry.checkedAt) < ttl
end

function ModIndex.writeCache(feed, index)
  if type(feed) ~= "string" or feed == "" then return false end
  local ok = pcall(function()
    local SaveData = require("src.core.SaveData")
    local opts = loadOptions()
    opts.modIndexCache = opts.modIndexCache or {}
    opts.modIndexCache[feed] = {
      checkedAt = os.time(),
      generatedAt = index.generatedAt,
      categories = index.categories,
      mods = index.mods,
    }
    SaveData.saveOptions(opts)
  end)
  return ok
end

-- ------- host I/O (HostShell's transport: curl, or the Android JNI bridge)

-- Plain GET returning the body.  No GitHub Accept header: the feed and the
-- description markdown are static files on Pages, and the public feed is
-- explicitly unauthenticated.  The transport itself lives in
-- src/core/HostShell.lua because Android has no curl and has to fetch through
-- love.system.httpDownload instead (#597).
function ModIndex.httpGet(url)
  local HostShell = require("src.core.HostShell")
  if not HostShell.canFetch() then
    return nil, AppMessage("Network access is unavailable on this platform")
  end
  return HostShell.httpGet(url, "gen1recomp-mod-index")
end

-- fetch(source, opts) -> index, err, meta
-- index is the parse() table; meta is { fromCache, stale }.  opts.force skips
-- the 24h cache.  A failed live fetch falls back to whatever is cached, marked
-- stale, so going offline degrades the listing rather than emptying it.
function ModIndex.fetch(source, opts)
  opts = opts or {}
  if type(source) ~= "table" or type(source.feed) ~= "string" then
    return nil, AppMessage("Missing index source")
  end
  local feed = source.feed

  local function cached(stale)
    local entry = ModIndex.readCache(feed)
    if not entry then return nil end
    return {
      schemaVersion = ModIndex.SCHEMA_VERSION,
      generatedAt = entry.generatedAt,
      categories = entry.categories or {},
      mods = entry.mods or {},
    }, nil, { fromCache = true, stale = stale, checkedAt = entry.checkedAt }
  end

  if not opts.force then
    local entry = ModIndex.readCache(feed)
    if ModIndex.cacheFresh(entry) then return cached(false) end
  end

  local body, err = ModIndex.httpGet(feed)
  -- Pages deploys trail a push; the raw mirror is the same file, so a feed
  -- that 404s right after a release is worth one retry elsewhere before it
  -- counts as an outage.
  if not body and source.fallback then
    body = ModIndex.httpGet(source.fallback)
  end
  if not body then
    local index, _, meta = cached(true)
    if index then return index, nil, meta end
    return nil, err
  end

  local index, parseErr = ModIndex.parse(body)
  if not index then
    local stale, _, meta = cached(true)
    if stale then return stale, parseErr, meta end
    return nil, parseErr
  end
  ModIndex.writeCache(feed, index)
  return index, nil, { fromCache = false, checkedAt = os.time() }
end

-- ------- async fetch (the launcher's path; ModIndex.fetch above stays as the
-- synchronous one for tests and non-UI callers)
--
-- ModIndex.fetch blocks on curl, which on the render thread froze the Find
-- Mods tab for as long as the server took.  These three functions are the
-- same state machine driven a frame at a time over src/net/Fetch.lua:
--     local h = ModIndex.beginFetch(source, { force = true })
--     -- every frame:
--     local done, index, err, meta = ModIndex.pumpFetch(h)
-- pumpFetch returns done=false while the request is in flight.  The cache
-- rules are identical to the sync path: a fresh cache short-circuits the
-- network entirely (so the handle completes on its first pump), a failed
-- live fetch falls back to stale cache, and the fallback mirror gets one try
-- before the feed counts as an outage.
function ModIndex.beginFetch(source, opts)
  opts = opts or {}
  local h = { source = source, opts = opts, stage = "start" }
  if type(source) ~= "table" or type(source.feed) ~= "string" then
    h.stage, h.err = "done", AppMessage("Missing index source")
    return h
  end
  return h
end

-- Shared with the sync path's `cached` closure: read whatever is in the
-- options cache and shape it like a parsed index.
local function cachedIndex(feed, stale)
  local entry = ModIndex.readCache(feed)
  if not entry then return nil end
  return {
    schemaVersion = ModIndex.SCHEMA_VERSION,
    generatedAt = entry.generatedAt,
    categories = entry.categories or {},
    mods = entry.mods or {},
  }, nil, { fromCache = true, stale = stale, checkedAt = entry.checkedAt }
end

-- Returns done, index, err, meta.
function ModIndex.pumpFetch(h)
  if not h then return true, nil, AppMessage("Missing index request") end
  local Fetch = require("src.net.Fetch")
  local feed = h.source and h.source.feed

  if h.stage == "done" then
    return true, h.index, h.err, h.meta
  end

  if h.stage == "start" then
    if not h.opts.force then
      local entry = ModIndex.readCache(feed)
      if ModIndex.cacheFresh(entry) then
        h.index, h.err, h.meta = cachedIndex(feed, false)
        h.stage = "done"
        return true, h.index, h.err, h.meta
      end
    end
    h.job = Fetch.get(feed, { userAgent = "gen1recomp-mod-index" })
    h.stage = "feed"
    return false
  end

  local st = Fetch.poll(h.job)
  if st.status == "pending" then return false end
  Fetch.release(h.job)

  if st.status == "ok" and st.body then
    local index, parseErr = ModIndex.parse(st.body)
    if index then
      ModIndex.writeCache(feed, index)
      h.index, h.meta = index, { fromCache = false, checkedAt = os.time() }
      h.stage = "done"
      return true, h.index, nil, h.meta
    end
    -- A feed that parses badly is an outage as far as the UI is concerned.
    h.parseErr = parseErr
  end

  -- Pages deploys trail a push; the raw mirror is the same file, so a feed
  -- that fails right after a release is worth one retry elsewhere.
  if h.stage == "feed" and h.source.fallback then
    h.job = Fetch.get(h.source.fallback, { userAgent = "gen1recomp-mod-index" })
    h.stage = "fallback"
    return false
  end

  local index, _, meta = cachedIndex(feed, true)
  h.stage = "done"
  if index then
    h.index, h.meta = index, meta
    return true, index, nil, meta
  end
  h.err = h.parseErr or st.err or AppMessage("Could not download the index")
  return true, nil, h.err
end

-- Fetch a description_url / any index-relative text file.  Returns the raw
-- markdown; callers run it through ModUpdate.cleanBody for display.
function ModIndex.fetchText(url)
  if type(url) ~= "string" or url == "" then
    return nil, AppMessage("No description available")
  end
  return ModIndex.httpGet(url)
end

-- Download a thumbnail into the save directory and return the love.filesystem
-- relative path.  Reuses ModUpdate.downloadZip, which is a plain curl -o with
-- a non-empty-file check -- nothing in it is zip-specific.
function ModIndex.downloadThumbnail(url, modId)
  if type(url) ~= "string" or url == "" then
    return nil, AppMessage("No thumbnail available")
  end
  local ModUpdate = require("src.mods.ModUpdate")
  local ext = url:match("%.(%a%a%a?%a?)$") or "png"
  local name = ("mod_thumb_%s.%s"):format(tostring(modId):gsub("[^%w%-_]", "_"), ext)
  return ModUpdate.downloadZip(url, name)
end

return ModIndex
