-- GitHub release helpers for mod auto-update / other-versions.
-- Pure parsing is love-free; fetch/download use HostShell + curl when available.
-- Release lists are cached in options.modUpdateCache for CACHE_TTL seconds
-- (default 6 hours). The launcher owns UI and install.

local ModUpdate = {}

ModUpdate.CACHE_TTL = 6 * 60 * 60  -- six hours

local function stripV(tag)
  return (tostring(tag):gsub("^[vV]", ""))
end

-- Prefer "<id>-<version>.zip", then any "<id>*.zip", then the first .zip.
function ModUpdate.pickZipAsset(assets, modId, version)
  if type(assets) ~= "table" then return nil end
  local prefer = nil
  if modId and version then
    prefer = tostring(modId) .. "-" .. tostring(version) .. ".zip"
  end
  local idPrefix, idPrefixZip, anyZip = nil, nil, nil
  if modId then idPrefix = tostring(modId):lower() end
  for _, a in ipairs(assets) do
    if type(a) == "table" and type(a.name) == "string" then
      local name = a.name
      if name:lower():match("%.zip$") then
        local row = {
          name = name,
          url = a.browser_download_url,
          size = tonumber(a.size),
        }
        if prefer and name == prefer then return row end
        if idPrefix and not idPrefixZip
            and name:lower():find(idPrefix, 1, true) == 1 then
          idPrefixZip = row
        end
        if not anyZip then anyZip = row end
      end
    end
  end
  return idPrefixZip or anyZip
end

-- Byte-length cut that never lands mid UTF-8 codepoint.
local function utf8Cut(s, maxBytes)
  if type(s) ~= "string" or maxBytes <= 0 then return "" end
  if #s <= maxBytes then return s end
  s = s:sub(1, maxBytes)
  -- Drop trailing continuation bytes (10xxxxxx).
  while #s > 0 do
    local b = s:byte(#s)
    if b < 0x80 or b >= 0xC0 then break end
    s = s:sub(1, #s - 1)
  end
  -- Drop a lead byte whose continuation was truncated away.
  if #s > 0 then
    local b = s:byte(#s)
    if b >= 0xC0 then
      s = s:sub(1, #s - 1)
    end
  end
  return s
end

-- Strip common markdown / HTML noise for the launcher changelog preview.
function ModUpdate.cleanBody(text, maxChars)
  if type(text) ~= "string" or text == "" then return "" end
  local s = text
  s = s:gsub("\r\n", "\n"):gsub("\r", "\n")
  s = s:gsub("<!%-%-.-%-%->", "")
  s = s:gsub("<[^>]+>", "")
  s = s:gsub("%[%!%[[^%]]*%]%([^%)]*%)%]", "") -- images ![alt](url)
  s = s:gsub("%[([^%]]+)%]%([^%)]+%)", "%1")   -- links [text](url) -> text
  s = s:gsub("```[^\n]*\n(.-)```", "%1")
  s = s:gsub("`([^`]+)`", "%1")
  s = s:gsub("^#+%s*", "", 1)
  s = s:gsub("\n#+%s*", "\n")
  s = s:gsub("%*%*([^*]+)%*%*", "%1")
  s = s:gsub("%*([^*]+)%*", "%1")
  s = s:gsub("__([^_]+)__", "%1")
  s = s:gsub("_([^_]+)_", "%1")
  s = s:gsub("^\n+", ""):gsub("\n+$", "")
  s = s:gsub("\n\n\n+", "\n\n")
  maxChars = tonumber(maxChars) or 0
  if maxChars > 0 and #s > maxChars then
    -- ASCII "..." (not U+2026) so later pixel ellipsize stays byte-safe.
    s = utf8Cut(s, maxChars):gsub("%s+%S*$", "") .. "..."
  end
  return s
end

-- One-line preview for tight UI rows: cleaned, newlines collapsed, ellipsized.
function ModUpdate.previewLine(text, maxChars)
  local s = ModUpdate.cleanBody(text, 0)
  if s == "" then return "" end
  s = s:gsub("\n+", " "):gsub("%s+", " ")
  s = s:match("^%s*(.-)%s*$") or s
  maxChars = tonumber(maxChars) or 80
  if #s > maxChars then
    s = utf8Cut(s, maxChars):gsub("%s+%S*$", "") .. "..."
  end
  return s
end

-- Decode one GitHub release object into { version, tag, zip, prerelease,
-- name, body, downloads }. `downloads` is the sum of every asset's
-- download_count, GitHub's own measure of a release's downloads.
function ModUpdate.parseRelease(doc, modId)
  if type(doc) ~= "table" or not doc.tag_name then
    return nil, "no tag_name in release"
  end
  local version = stripV(doc.tag_name)
  if not version:match("^%d+%.%d+%.%d+") then
    return nil, "release tag is not semver-like: " .. tostring(doc.tag_name)
  end
  local triple = version:match("^(%d+%.%d+%.%d+)")
  local zip = ModUpdate.pickZipAsset(doc.assets, modId, triple)
  local body = type(doc.body) == "string" and doc.body or ""
  local downloads = 0
  if type(doc.assets) == "table" then
    for _, a in ipairs(doc.assets) do
      local d = type(a) == "table" and tonumber(a.download_count)
      if d and d > 0 then downloads = downloads + d end
    end
  end
  return {
    version = triple,
    tag = tostring(doc.tag_name),
    zip = zip,
    prerelease = doc.prerelease == true,
    name = type(doc.name) == "string" and doc.name or triple,
    body = body,
    downloads = downloads,
    published = (doc.published_at or doc.created_at or ""):match("^(%d+%-%d+%-%d+)"),
  }
end

-- Decode a releases array (GET /repos/.../releases) into a sorted list
-- (newest first). Releases without a .zip asset are dropped. Never throws.
function ModUpdate.parseReleases(jsonText, modId, Json)
  local ok, result, err = pcall(function()
    Json = Json or require("src.link.Json")
    local doc, decodeErr = Json.decode(jsonText)
    if type(doc) ~= "table" then
      return nil, decodeErr or "releases json is not an array"
    end
    if type(doc.message) == "string" and not doc.tag_name and not doc[1] then
      return nil, "GitHub: " .. doc.message
    end
    if doc.tag_name then
      local one, oneErr = ModUpdate.parseRelease(doc, modId)
      if not one then return nil, oneErr end
      if not one.zip then return nil, "latest release has no .zip asset" end
      return { one }
    end
    local out = {}
    for _, entry in ipairs(doc) do
      local rel = ModUpdate.parseRelease(entry, modId)
      if rel and rel.zip then out[#out + 1] = rel end
    end
    return out
  end)
  if not ok then return nil, "could not parse releases: " .. tostring(result) end
  return result, err
end

function ModUpdate.apiReleasesUrl(repo)
  return "https://api.github.com/repos/" .. repo .. "/releases?per_page=100"
end

function ModUpdate.apiLatestUrl(repo)
  return "https://api.github.com/repos/" .. repo .. "/releases/latest"
end

function ModUpdate.isNewer(installed, candidate)
  local Semver = require("src.mods.Semver")
  if type(installed) ~= "string" or type(candidate) ~= "string" then
    return false
  end
  local a, b = Semver.parse(installed), Semver.parse(candidate)
  if not a or not b then return false end
  return Semver.compare(candidate, installed) > 0
end

-- Newest non-prerelease, else newest overall.
function ModUpdate.pickBest(releases)
  if type(releases) ~= "table" or #releases == 0 then return nil end
  for _, rel in ipairs(releases) do
    if not rel.prerelease then return rel end
  end
  return releases[1]
end

-- Sum of per-release download counts.  Returns nil when no release carries
-- the field (a cache entry written before downloads existed), else
-- { total = <sum>, releases = <release count> } so a caller can tell a
-- real "0 downloads" apart from "no data yet".
function ModUpdate.totalDownloads(releases)
  if type(releases) ~= "table" or #releases == 0 then return nil end
  local total, hasData = 0, false
  for _, rel in ipairs(releases) do
    local d = type(rel) == "table" and tonumber(rel.downloads)
    if d then
      hasData = true
      total = total + d
    end
  end
  if not hasData then return nil end
  return { total = total, releases = #releases }
end

-- First and latest release dates ("YYYY-MM-DD", ISO strings compare in
-- calendar order).  Returns nil when no release carries a date -- same
-- "no data yet" rule as totalDownloads.
function ModUpdate.releaseDates(releases)
  if type(releases) ~= "table" or #releases == 0 then return nil end
  local first, latest, has = nil, nil, false
  for _, rel in ipairs(releases) do
    local p = type(rel) == "table" and rel.published
    if type(p) == "string" and p ~= "" then
      has = true
      if not first or p < first then first = p end
      if not latest or p > latest then latest = p end
    end
  end
  if not has then return nil end
  return { first = first, latest = latest }
end

-- Thousands-separated count for the launcher ("12,345"), plain for small
-- numbers.  Never throws; garbage in, "0" out.
function ModUpdate.formatCount(n)
  n = tonumber(n)
  if not n or n ~= n or n < 0 then return "0" end
  local s = tostring(math.floor(n))
  s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (s:gsub("^,", ""))
end

-- ------- cache (options.modUpdateCache[repo])

local function cacheStore()
  local SaveData = require("src.core.SaveData")
  local opts = SaveData.loadOptions()
  opts.modUpdateCache = opts.modUpdateCache or {}
  return opts
end

function ModUpdate.readCache(repo)
  if type(repo) ~= "string" or repo == "" then return nil end
  local ok, opts = pcall(function()
    return require("src.core.SaveData").loadOptions()
  end)
  if not ok or type(opts) ~= "table" then return nil end
  local entry = opts.modUpdateCache and opts.modUpdateCache[repo]
  if type(entry) ~= "table" or type(entry.checkedAt) ~= "number" then
    return nil
  end
  if type(entry.releases) ~= "table" then return nil end
  return entry
end

function ModUpdate.cacheFresh(entry, now, ttl)
  now = now or os.time()
  ttl = ttl or ModUpdate.CACHE_TTL
  return entry and type(entry.checkedAt) == "number"
    and (now - entry.checkedAt) < ttl
end

-- A cache entry written before download counts existed carries no
-- `downloads` on any release.  It is provably stale -- parseRelease always
-- sets the field now -- so treat it as expired: the next fetch rewrites
-- the entry in the current format, one refetch per repo, and the launcher's
-- download line stops hiding behind an old cache.
function ModUpdate.cacheUsable(cached)
  if type(cached) ~= "table" or type(cached.releases) ~= "table" then
    return false
  end
  if #cached.releases == 0 then return true end
  for _, rel in ipairs(cached.releases) do
    if tonumber(rel.downloads) then return true end
  end
  return false
end

function ModUpdate.writeCache(repo, releases)
  if type(repo) ~= "string" or repo == "" then return false end
  local ok = pcall(function()
    local SaveData = require("src.core.SaveData")
    local opts = cacheStore()
    local best = ModUpdate.pickBest(releases)
    -- Persist a lean copy: enough to paint the UI and reinstall without
    -- re-fetching within the TTL.
    local lean = {}
    for i, rel in ipairs(releases or {}) do
      lean[i] = {
        version = rel.version,
        tag = rel.tag,
        name = rel.name,
        prerelease = rel.prerelease == true,
        body = type(rel.body) == "string" and rel.body or "",
        downloads = tonumber(rel.downloads) or 0,
        published = rel.published,
        zip = rel.zip and {
          name = rel.zip.name,
          url = rel.zip.url,
          size = rel.zip.size,
        } or nil,
      }
    end
    opts.modUpdateCache[repo] = {
      checkedAt = os.time(),
      latest = best and best.version or nil,
      releases = lean,
    }
    SaveData.saveOptions(opts)
  end)
  return ok
end

-- Status vs an installed version using a cache entry / release list.
-- Returns "available" | "current" | "unknown".
function ModUpdate.statusFor(installedVersion, releases)
  local best = ModUpdate.pickBest(releases)
  if not best then return "unknown", nil end
  if ModUpdate.isNewer(installedVersion, best.version) then
    return "available", best
  end
  return "current", best
end

-- ------- host I/O (HostShell's transport: curl, or the Android JNI bridge)

-- GitHub's API wants a User-Agent and answers the versioned Accept.
local function apiFetch(url)
  local HostShell = require("src.core.HostShell")
  return HostShell.httpGet(url, "gen1recomp-mod-updater",
    "application/vnd.github+json")
end

-- Still just the curl probe it always was.  "Can we fetch at all" is
-- HostShell.canFetch, which also knows about the Android bridge (#597); every
-- gate below asks that instead.
function ModUpdate.haveCurl()
  local HostShell = require("src.core.HostShell")
  return HostShell.haveCurl()
end

-- Fetch release list. opts.force bypasses the 6h cache.
-- Returns releases, err, meta where meta = { fromCache = bool }.
function ModUpdate.fetchReleases(repo, modId, opts)
  opts = opts or {}
  if type(repo) ~= "string" or repo == "" then
    return nil, "missing github repo"
  end
  if not opts.force then
    local cached = ModUpdate.readCache(repo)
    if ModUpdate.cacheFresh(cached) and ModUpdate.cacheUsable(cached) then
      return cached.releases, nil, { fromCache = true }
    end
  end
  local HostShell = require("src.core.HostShell")
  if not HostShell.canFetch() then
    -- Stale cache is better than nothing when offline
    local cached = ModUpdate.readCache(repo)
    if cached and cached.releases then
      return cached.releases, nil, { fromCache = true, stale = true }
    end
    return nil, "no network transport on this platform"
  end
  local body, curlErr = apiFetch(ModUpdate.apiReleasesUrl(repo))
  if not body then
    local cached = ModUpdate.readCache(repo)
    if cached and cached.releases then
      return cached.releases, nil, { fromCache = true, stale = true }
    end
    return nil, curlErr
  end
  local list, parseErr = ModUpdate.parseReleases(body, modId)
  if not list then return nil, parseErr end
  ModUpdate.writeCache(repo, list)
  return list, nil, { fromCache = false }
end

function ModUpdate.downloadZip(url, destName)
  if type(url) ~= "string" or url == "" then
    return nil, "missing download url"
  end
  if not (love and love.filesystem) then
    return nil, "download needs LOVE"
  end
  local HostShell = require("src.core.HostShell")
  if not HostShell.canFetch() then
    return nil, "no network transport on this platform"
  end
  local name = destName or ("mod_update_" .. tostring(os.time()) .. ".zip")
  name = tostring(name):gsub("[/\\]", "_")
  local saveOk, saveDir = pcall(function()
    return love.filesystem.getSaveDirectory()
  end)
  if not saveOk or not saveDir or saveDir == "" then
    return nil, "no save directory"
  end
  local abs = saveDir .. "/" .. name
  -- Either transport can fail quietly; the getInfo size check below is what
  -- actually decides whether we got a file (#597).
  HostShell.httpDownload(url, abs, "gen1recomp-mod-updater")
  local infoOk, info = pcall(love.filesystem.getInfo, name)
  if not infoOk or not info or (info.size or 0) == 0 then
    pcall(love.filesystem.remove, name)
    return nil, "download failed"
  end
  return name
end

return ModUpdate
