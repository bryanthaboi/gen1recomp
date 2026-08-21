-- Background worker for the self-update flow (driven by src/update/Check.lua).
--
-- Runs on a love.thread so no curl call, sha256 pass or archive probe ever
-- touches the render thread.  Talks over two channels:
--   "update_check_cmd"   in:  { cmd = "check" | "download" |
--                                "download_full" | "quit" }
--   "update_check_state" out: { status, latest, progress, error }
--
-- Transport is HostShell: curl via io.popen on desktop, the JNI
-- love.system.httpDownload bridge on Android (same path the mod catalog
-- already uses).  A missing transport, an HTTP error, or a hung download
-- degrades to "error"/"needs_full" rather than blocking or crashing the game.
--
-- Fresh love threads do not carry the "src.*" package searcher, so sibling
-- modules are pulled in with love.filesystem.load exactly like
-- src/core/chip_worker.lua does.  Semver and Boot are authored in parallel; we
-- load them defensively and degrade (a local semver fallback, a permissive
-- gate) if they are not present yet.

require("love.thread")
require("love.filesystem")
require("love.data")
require("love.timer")
require("love.system")

local function loadModule(path)
  local ok, chunk = pcall(love.filesystem.load, path)
  if not ok or type(chunk) ~= "function" then return nil end
  local ok2, mod = pcall(chunk)
  if not ok2 then return nil end
  return mod
end

local Json    = loadModule("src/link/Json.lua")
local Check   = loadModule("src/update/Check.lua")
local Version = loadModule("src/core/Version.lua")
local Semver  = loadModule("src/update/Semver.lua")
local HostShell = loadModule("src/core/HostShell.lua")
-- Boot's top-level require("src.update.Semver") cannot resolve in this thread
-- (no src.* searcher), which would leave Boot nil and the minShell gate
-- permanently permissive.  Seed the loaded table first so it resolves.
if Semver then package.loaded["src.update.Semver"] = Semver end
local Boot    = loadModule("src/update/Boot.lua")

local cmdCh   = love.thread.getChannel("update_check_cmd")
local stateCh = love.thread.getChannel("update_check_state")

-- The release chosen by the last check. Declare this before post() so status
-- messages consistently preserve its release notes instead of accidentally
-- reading a global named `pending`.
local pending = nil

local function post(t)
  if pending and type(t) == "table" and t.notes == nil then
    t.notes = pending.notes
  end
  stateCh:push(t)
end

local osName    = (love.system and love.system.getOS and love.system.getOS()) or ""
local isWindows = osName == "Windows"
local saveDir   = love.filesystem.getSaveDirectory()

local API_URL = "https://api.github.com/repos/bryanthaboi/gen1recomp/releases/latest"

-- ---------------------------------------------------------------------------
-- shell / fetch
-- ---------------------------------------------------------------------------

local UA = "gen1recomp-updater"
local GH_ACCEPT = "application/vnd.github+json"

local function shq(s)
  s = tostring(s)
  if isWindows then
    return '"' .. s:gsub('"', '') .. '"'
  end
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- Small text resources (release JSON, sums file) through HostShell so Android
-- hits the JNI bridge instead of a curl binary that is never on the device.
local function fetchText(url, accept)
  if not HostShell then return nil end
  local body = HostShell.httpGet(url, UA, accept)
  if type(body) ~= "string" or body == "" then return nil end
  return body
end

local function canFetch()
  return HostShell and HostShell.canFetch()
end

-- ---------------------------------------------------------------------------
-- version compare (Semver per contract item 5, with a local fallback)
-- ---------------------------------------------------------------------------

local function parseTriple(s)
  s = (tostring(s):gsub("^[vV]", ""))
  local a, b, c = s:match("^(%d+)%.(%d+)%.(%d+)")
  if not a then return nil end
  return { tonumber(a), tonumber(b), tonumber(c) }
end

-- -1 | 0 | 1 for a<b | a==b | a>b
local function compareVersions(a, b)
  if Semver and Semver.compare then
    local ok, r = pcall(Semver.compare, a, b)
    if ok and r ~= nil then return r end
  end
  local pa, pb = parseTriple(a), parseTriple(b)
  if not pa or not pb then return 0 end
  for i = 1, 3 do
    if pa[i] ~= pb[i] then return pa[i] < pb[i] and -1 or 1 end
  end
  return 0
end

-- ---------------------------------------------------------------------------
-- verification and the shell gate
-- ---------------------------------------------------------------------------

local function sha256hex(data)
  local digest = love.data.hash("sha256", data)
  if type(digest) == "userdata" and digest.getString then
    digest = digest:getString()
  end
  return love.data.encode("string", "hex", digest)
end

-- Confirm the save-dir file `rel` hashes to the sum listed for `payloadName`.
local function verifyPayload(rel, payloadName, sumsText)
  local want = Check.parseSums(sumsText, payloadName)
  if not want then return false, "no checksum for " .. payloadName end
  local data = love.filesystem.read(rel)
  if not data then return false, "cannot read downloaded payload" end
  if sha256hex(data):lower() ~= want:lower() then
    return false, "checksum mismatch"
  end
  return true
end

local function verifyFullPackage(rel, assetName, sumsText)
  return verifyPayload(rel, assetName, sumsText)
end

-- true = ok to run, false = payload needs a newer shell (needs_full).  When Boot
-- cannot probe (module missing during parallel dev, or a probe failure) we allow
-- it: Boot.run's crash-guard handles a payload that turns out unrunnable.
local function gatePasses(rel)
  if not (Boot and Boot.probePayload) then return true end
  local info = Boot.probePayload(rel)
  if not info then return true end
  local shell = (Version and Version.shell) or 1
  local payloadHost = (Version and Version.payloadHost) or "love"
  if info.payloadHost and info.payloadHost ~= payloadHost then return false, "payload_host" end
  if info.minShell and info.minShell > shell then return false, "min_shell" end
  if Boot.canHost and not Boot.canHost(info, shell, payloadHost) then return false, "shell_gate" end
  return true
end

local function persistFullRequirement(rel, reason)
  if not (rel and rel.version and Json) then return end
  local full = rel.full
  local record = {
    version = rel.version,
    reason = reason or "full_package_required",
    full = full and { name = rel.fullName, url = full.url, size = full.size } or nil,
  }
  pcall(function()
    love.filesystem.createDirectory("updates")
    love.filesystem.write("updates/full-update.json", Json.encode(record))
  end)
end

local function postFullRequirement(rel, reason)
  persistFullRequirement(rel, reason)
  post({ status = "needs_full", latest = rel and rel.version, reason = reason,
    full = rel and rel.full and { name = rel.fullName, url = rel.full.url, size = rel.full.size } or nil })
end

local function clearFullRequirement()
  pcall(function() love.filesystem.remove("updates/full-update.json") end)
end

local function cacheNotes(ver, notes)
  if not (ver and type(notes) == "string" and notes ~= "" and Json) then return end
  if not (love and love.filesystem) then return end
  pcall(function()
    love.filesystem.createDirectory("updates")
    local cachePath = "updates/notes_cache.json"
    local existing = {}
    if love.filesystem.getInfo and love.filesystem.getInfo(cachePath) then
      local text = love.filesystem.read(cachePath)
      if text then
        local ok, doc = pcall(Json.decode, text)
        if ok and type(doc) == "table" then existing = doc end
      end
    end
    existing[ver] = notes
    local ok, encoded = pcall(Json.encode, existing)
    if ok and encoded then
      love.filesystem.write(cachePath, encoded)
    end
  end)
end

-- ---------------------------------------------------------------------------
-- check
-- ---------------------------------------------------------------------------

local function doCheck(target)
  post({ status = "checking" })

  if not canFetch() then
    -- No curl and no JNI bridge: the chip becomes "Open releases" so a tap
    -- still does something instead of retrying a check that cannot succeed.
    post({ status = "needs_full" })
    return
  end

  local body = fetchText(API_URL, GH_ACCEPT)
  if not body then
    post({ status = "error", error = "release check failed" })
    return
  end

  local rel, perr = Check.parseRelease(body, Json, target)
  if not rel then
    post({ status = "error", error = perr or "bad release json" })
    return
  end
  pending = rel
  if rel.version and type(rel.notes) == "string" and rel.notes ~= "" then
    cacheNotes(rel.version, rel.notes)
  end

  -- Unstamped dev build: the working tree always looks "newer", so never
  -- pester the developer with an update (contract item, Check design).
  local currentEngine = (Version and Version.engine) or "0.0.0-dev"
  if currentEngine == "0.0.0-dev" then
    post({ status = "uptodate", latest = rel.version })
    return
  end

  if compareVersions(rel.version, currentEngine) <= 0 then
    -- We are now running a native shell at least as new as GitHub's latest
    -- release, so a former minShell/payloadHost prompt no longer applies.
    clearFullRequirement()
    post({ status = "uptodate", latest = rel.version })
    return
  end

  -- A newer release, but without the .love payload or its sums we cannot do an
  -- in-place update: send the user to the full installers.
  if not (rel.payload and rel.payload.url and rel.sums and rel.sums.url) then
    postFullRequirement(rel, "payload_missing")
    return
  end

  -- Already downloaded on a previous run?  Verify and gate it rather than
  -- pulling the bytes again.
  local finalRel = "updates/" .. rel.payloadName
  if love.filesystem.getInfo(finalRel) then
    local sums = fetchText(rel.sums.url)
    if sums and verifyPayload(finalRel, rel.payloadName, sums) then
      local allowed, reason = gatePasses(finalRel)
      if allowed == false then
        love.filesystem.remove(finalRel)
        postFullRequirement(rel, reason)
        return
      end
      post({ status = "ready", latest = rel.version })
      return
    end
    -- stale / corrupt: drop it and offer a fresh download
    love.filesystem.remove(finalRel)
  end

  post({ status = "available", latest = rel.version })
end

-- ---------------------------------------------------------------------------
-- download
-- ---------------------------------------------------------------------------

-- Launch curl in the background writing `partAbs`, touching `doneAbs` when it
-- exits.  Returns without waiting so the caller can poll the growing file for
-- progress.  We deliberately do not capture curl's exit code: an incomplete or
-- failed transfer simply fails the checksum below, which is the real gate.
local function launchDownload(url, partAbs, doneAbs)
  if isWindows then
    -- a tiny batch file sidesteps cmd.exe's nested-quote madness
    local batRel = "updates/dl.bat"
    love.filesystem.write(batRel,
      "@echo off\r\n"
      -- start /b hands the child our cwd, the install folder, and the
      -- detached cmd.exe held that folder un-movable for the rest of the
      -- transfer after the game exited (#727).  Every path below is
      -- absolute, so park the child in its own directory (the save dir).
      .. "cd /d \"%~dp0\"\r\n"
      .. "curl -fsSL --connect-timeout 15 --max-time 900 -o \""
      .. partAbs .. "\" \"" .. url .. "\"\r\n"
      .. "type nul > \"" .. doneAbs .. "\"\r\n")
    os.execute('start "" /b ' .. shq(saveDir .. "/" .. batRel))
  else
    -- ( ... ) & backgrounds the whole group so os.execute returns at once
    os.execute("( " .. HostShell.envPrefix() .. "curl -fsSL --connect-timeout 15 --max-time 900 -o "
      .. shq(partAbs) .. " " .. shq(url)
      .. " ; touch " .. shq(doneAbs) .. " ) >/dev/null 2>&1 &")
  end
end

local function doDownload()
  if not (pending and pending.payload and pending.payload.url) then
    post({ status = "error", error = "nothing to download" })
    return
  end
  local rel = pending
  post({ status = "downloading", latest = rel.version, progress = 0 })

  love.filesystem.createDirectory("updates")
  local partRel  = "updates/" .. rel.payloadName .. ".part"
  local doneRel  = "updates/" .. rel.payloadName .. ".done"
  local finalRel = "updates/" .. rel.payloadName
  love.filesystem.remove(partRel)
  love.filesystem.remove(doneRel)

  local partAbs = saveDir .. "/updates/" .. rel.payloadName .. ".part"
  local doneAbs = saveDir .. "/updates/" .. rel.payloadName .. ".done"
  local size    = rel.payload.size or 0

  if HostShell and HostShell.haveCurl() then
    launchDownload(rel.payload.url, partAbs, doneAbs)

    -- poll the .part size for progress until curl drops the done-marker; a
    -- stalled or run-away transfer breaks out and lets verification fail cleanly
    local waited, lastSize, lastChange = 0, -1, 0
    while true do
      -- A queued quit means the window already closed.  Bail so the join in
      -- Check.shutdown does not hold the dead window's process (and, on
      -- Windows, its folder) open for up to the whole transfer (#727).  The
      -- quit stays on the channel for the command loop; the detached curl
      -- times out on its own and the next launch's doCheck verifies and
      -- re-offers whatever landed.
      local peeked = cmdCh:peek()
      if type(peeked) == "table" and peeked.cmd == "quit" then return end
      if love.filesystem.getInfo(doneRel) then break end
      local pinfo = love.filesystem.getInfo(partRel)
      local cur = (pinfo and pinfo.size) or 0
      if size > 0 then
        local p = cur / size
        if p > 0.999 then p = 0.999 end -- 1.0 is reserved for "ready"
        post({ status = "downloading", latest = rel.version, progress = p })
      else
        post({ status = "downloading", latest = rel.version })
      end
      if cur ~= lastSize then lastSize, lastChange = cur, waited end
      if waited - lastChange > 60 then break end -- 60s with no growth: give up
      if waited > 960 then break end             -- absolute ceiling
      love.timer.sleep(0.25)
      waited = waited + 0.25
    end
    love.filesystem.remove(doneRel)
  else
    -- Android JNI bridge: blocking write, same as fetch_worker.  Progress
    -- cannot be sampled from inside httpDownload.
    local ok = HostShell and HostShell.httpDownload(
      rel.payload.url, partAbs, UA, nil, 900)
    if not ok then
      love.filesystem.remove(partRel)
      post({ status = "error", error = "download failed" })
      return
    end
    post({ status = "downloading", latest = rel.version, progress = 0.999 })
  end

  local sums = fetchText(rel.sums and rel.sums.url or "")
  if not sums then
    love.filesystem.remove(partRel)
    post({ status = "error", error = "checksum fetch failed" })
    return
  end

  local ok, verr = verifyPayload(partRel, rel.payloadName, sums)
  if not ok then
    love.filesystem.remove(partRel)
    post({ status = "error", error = verr or "verification failed" })
    return
  end

  local allowed, reason = gatePasses(partRel)
  if allowed == false then
    love.filesystem.remove(partRel)
    postFullRequirement(rel, reason)
    return
  end

  -- finalize: rename the verified .part to its real name (fall back to a
  -- love.filesystem copy if os.rename is unavailable on this platform)
  if not os.rename(partAbs, saveDir .. "/updates/" .. rel.payloadName) then
    local data = love.filesystem.read(partRel)
    if not data then
      post({ status = "error", error = "finalize failed" })
      return
    end
    love.filesystem.write(finalRel, data)
    love.filesystem.remove(partRel)
  end

  post({ status = "ready", latest = rel.version })
end

-- Full native-package download. At present Android consumes the verified file
-- through its Package Installer bridge. Other platforms retain the same
-- release metadata and fall back to their platform-specific external update
-- channel rather than attempting to overwrite a running executable.
local function doDownloadFull()
  if not (pending and pending.full and pending.full.url and pending.fullName
      and pending.sums and pending.sums.url) then
    post({ status = "error", error = "full package is unavailable" })
    return
  end

  local rel = pending
  local asset = rel.full
  local name = rel.fullName
  love.filesystem.createDirectory("updates")
  local partRel = "updates/" .. name .. ".part"
  local doneRel = "updates/" .. name
  local partAbs = saveDir .. "/" .. partRel
  local doneAbs = saveDir .. "/" .. doneRel
  love.filesystem.remove(partRel)
  love.filesystem.remove(doneRel)
  post({ status = "full_downloading", latest = rel.version, progress = 0,
    reason = "full_package_required", full = { name = name, url = asset.url, size = asset.size } })

  local ok = HostShell and HostShell.httpDownload(asset.url, partAbs, UA, nil, 900)
  if not ok then
    love.filesystem.remove(partRel)
    postFullRequirement(rel, "full_download_failed")
    return
  end

  local sums = fetchText(rel.sums.url)
  if not sums then
    love.filesystem.remove(partRel)
    postFullRequirement(rel, "full_checksum_fetch_failed")
    return
  end
  local valid, err = verifyFullPackage(partRel, name, sums)
  if not valid then
    love.filesystem.remove(partRel)
    post({ status = "error", error = err or "full package verification failed" })
    return
  end
  if not os.rename(partAbs, doneAbs) then
    local data = love.filesystem.read(partRel)
    if not data then
      post({ status = "error", error = "full package finalize failed" })
      return
    end
    love.filesystem.write(doneRel, data)
    love.filesystem.remove(partRel)
  end
  persistFullRequirement(rel, "full_package_required")
  post({ status = "full_ready", latest = rel.version, reason = "full_package_required",
    full = { name = name, url = asset.url, size = asset.size, path = doneAbs } })
end

-- ---------------------------------------------------------------------------
-- command loop
-- ---------------------------------------------------------------------------

while true do
  local cmd = cmdCh:demand() -- blocks until the main thread pushes work
  if type(cmd) == "table" then
    if cmd.cmd == "quit" then
      break
    elseif cmd.cmd == "check" then
      local ok, err = pcall(doCheck, cmd.target)
      if not ok then post({ status = "error", error = tostring(err) }) end
    elseif cmd.cmd == "download" then
      local ok, err = pcall(doDownload)
      if not ok then post({ status = "error", error = tostring(err) }) end
    elseif cmd.cmd == "download_full" then
      local ok, err = pcall(doDownloadFull)
      if not ok then post({ status = "error", error = tostring(err) }) end
    end
  end
end
