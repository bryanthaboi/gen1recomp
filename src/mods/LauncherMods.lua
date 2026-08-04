-- Launcher-side mod surface (18/launcher redesign): the mods panel runs
-- BEFORE Game:load, so this NEVER loads a mod entry chunk -- it scans
-- manifests only.  The full loader (src/mods/Loader.lua) still owns the real
-- load at boot; this reads the same options.mods enable-state the loader
-- writes, derives per-mod status with the pure ManagerState.resolveToggle,
-- installs a dropped/chosen .zip into a "mods/<id>/" tree, and uninstalls a
-- mod by removing that tree + clearing options.mods[id].
--
-- Where that tree lives is CacheFs's call, not love.filesystem's: a portable
-- install (portable.txt beside the executable) keeps its mods in the game
-- folder like everything else it owns, and only the OS save directory
-- otherwise (#330 -- love.filesystem.write always resolves to the save dir,
-- so the installer used to strand every mod in appdata).  Reads stay on
-- love.filesystem: the portable folder is on the physfs read path either way
-- (it IS the source for a `love <gamedir>` run, and CacheFs mounts it for a
-- fused build), which is why those mods still loaded while landing in the
-- wrong place.
--
-- The same split decides where a mod is FOUND, and that has a sharp edge: a
-- non-portable install never reads the game folder at all, so a mod unzipped
-- next to the executable -- where most games would want it -- is not wrong so
-- much as invisible, with an empty panel and no error to explain it.
-- adoptStrays looks in those folders anyway (a scoped mount that comes down
-- again, CacheFs.withMounted) and copies what it finds into the tree the game
-- really reads, so the mistake costs a line of notice rather than a support
-- thread.
--
-- Split in two: the pure derivation (deriveList, locateRoot, pickStrays) has
-- no love and no filesystem, so the engine tier can table-drive it; the
-- discovery, install, uninstall, and stray-scan paths reach for
-- love.filesystem and SaveData.

local Manifest = require("src.mods.Manifest")
local ManagerState = require("src.mods.ManagerState")
local Semver = require("src.mods.Semver")
local Version = require("src.core.Version")
local SaveData = require("src.core.SaveData")
local CacheFs = require("src.import.CacheFs")

local LauncherMods = {}

-- ------- pure status derivation

-- A hard-dependency / conflict / version verdict for one manifest.  mods is
-- the id -> validated-manifest map resolveToggle reads (its dependencySpecs,
-- conflictSpecs, version and game_version are exactly the fields the loader's
-- Manifest.validate produced); enabledSet is the current desired enable-set.
local function statusFor(mods, id, enabledSet, enabled)
  local m = mods[id]
  -- conflict only bites an enabled mod: resolveToggle's conflict list is
  -- bidirectional (this mod's conflicts spec vs an enabled other, and an
  -- enabled other's spec vs this mod), which is exactly the launcher chip.
  if enabled then
    local r = ManagerState.resolveToggle(mods, id, true, enabledSet)
    if #r.conflicts > 0 then
      local otherId = r.conflicts[1]
      local other = mods[otherId]
      return "conflict",
        "Conflicts with " .. ((other and other.name) or otherId)
    end
  end
  -- warn: the engine is outside the mod's game_version range
  if m.game_version
      and not Semver.satisfies(Version.engine, m.game_version) then
    return "warn", "Needs engine " .. m.game_version
      .. " (have " .. Version.engine .. ")"
  end
  -- warn: a hard dependency is absent, switched off, or the wrong version.
  -- resolveToggle would cascade-enable a merely-disabled dep rather than flag
  -- it, so the disabled case is judged straight off the manifest here.
  for _, spec in ipairs(m.dependencySpecs or {}) do
    local dep = mods[spec.id]
    if not dep then
      return "warn", "Needs " .. spec.id .. " (not installed)"
    elseif not enabledSet[spec.id] then
      return "warn", "Needs " .. spec.id .. " (disabled)"
    elseif spec.range
        and not Semver.satisfies(dep.version, spec.range) then
      return "warn", "Needs " .. spec.id .. " " .. spec.range
    end
  end
  return "ok", "Ready"
end

-- deriveList(manifests, options) -> the panel row list, pure.
-- manifests is an array of validated manifests (Manifest.validate output);
-- options is the options table (only options.mods is read).  Rows come back
-- sorted by id so the panel order is stable.
function LauncherMods.deriveList(manifests, options)
  local mods = options and options.mods or {}
  local ordered = {}
  for _, m in ipairs(manifests) do ordered[#ordered + 1] = m end
  table.sort(ordered, function(a, b) return a.id < b.id end)

  local byId, enabledSet = {}, {}
  for _, m in ipairs(ordered) do
    byId[m.id] = m
    -- missing entry means enabled, matching the loader -- except experimental
    -- mods, which stay off until the player opts in
    if mods[m.id] == false then
      -- stay off
    elseif mods[m.id] == true then
      enabledSet[m.id] = true
    elseif not m.experimental then
      enabledSet[m.id] = true
    end
  end

  local out = {}
  for _, m in ipairs(ordered) do
    local enabled = enabledSet[m.id] == true
    local status, detail = statusFor(byId, m.id, enabledSet, enabled)
    local raw = m.raw or {}
    local badge = tostring(raw.category or m.profile or "MOD"):upper()
    if m.experimental then badge = "EXPERIMENTAL" end
    out[#out + 1] = {
      id = m.id,
      name = m.name or m.id,
      version = m.version,
      badge = badge,
      description = m.description or "",
      enabled = enabled,
      status = status,
      statusDetail = detail,
      github = m.github,
      experimental = m.experimental == true,
    }
  end
  return out
end

-- locateRoot(paths) -> the mod-root prefix inside a mounted archive, pure.
-- paths is a shallow listing: top-level file names as-is, and for a top-level
-- directory a "<dir>/manifest.json" entry when it holds one.  Returns "" when
-- the manifest sits at the archive root, "<dir>" when a single top-level
-- folder holds it, or nil + a user-presentable reason.
function LauncherMods.locateRoot(paths)
  for _, p in ipairs(paths) do
    if p == "manifest.json" then return "" end
  end
  local topDirs, seen, hasManifest = {}, {}, {}
  for _, p in ipairs(paths) do
    local top, rest = p:match("^([^/]+)/(.+)$")
    if top then
      if not seen[top] then
        seen[top] = true
        topDirs[#topDirs + 1] = top
      end
      if rest == "manifest.json" then hasManifest[top] = true end
    end
  end
  if #topDirs == 1 and hasManifest[topDirs[1]] then return topDirs[1] end
  if #topDirs > 1 then
    return nil, "the .zip must contain a single mod folder"
  end
  return nil, "no manifest.json found in the .zip"
end

-- pickStrays(found, installed) -> the rows worth adopting, pure.
-- found is an array of { id, name, folder, path } in scan order (game folder
-- order, then directory order); installed is the id -> true set of what the
-- game can already see.  An installed id is dropped -- the player has a
-- working copy and the loose folder is just where they first put it -- and a
-- duplicate id across two game folders keeps the first, the same first-wins
-- rule discover() uses.  Sorted by id so the notice reads the same every time.
function LauncherMods.pickStrays(found, installed)
  installed = installed or {}
  local out, seen = {}, {}
  for _, row in ipairs(found or {}) do
    local id = row.id
    if id and not installed[id] and not seen[id] then
      seen[id] = true
      out[#out + 1] = { id = id, name = row.name or id,
                        folder = row.folder, path = row.path }
    end
  end
  table.sort(out, function(a, b) return a.id < b.id end)
  return out
end

-- isReadableRoot(folder, source, cacheRoot) -> is folder already on the
-- physfs read path, pure.  source is love.filesystem.getSource(), cacheRoot
-- the mounted portable game folder (CacheFs.root()); a fused build has both,
-- and they are different paths (the archive inside the executable vs the
-- folder beside it).  Either one's mods/ is readable already, so nothing in
-- it is a stray -- and the portable folder must additionally never be handed
-- to CacheFs.withMounted: PHYSFS_mount reports success for a directory
-- already in the search path WITHOUT adding a second entry, so the paired
-- unmount tears down the one real mount and the panel loses every mod in the
-- game folder (#413).
function LauncherMods.isReadableRoot(folder, source, cacheRoot)
  if not folder or folder == "" then return false end
  return folder == source or folder == cacheRoot
end

-- ------- discovery (love.filesystem)

local function decodeManifest(raw, path)
  local Json = require("src.link.Json")
  local data, decodeErr = Json.decode(raw)
  if not data then return nil, decodeErr end
  local ok, manifest = pcall(Manifest.validate, data, path)
  if not ok then return nil, manifest end
  return manifest
end

-- Scan "mods/" one level deep for valid manifests (mirrors Loader:_discover,
-- but validates only -- no entry chunk is ever loaded).  First id wins on a
-- duplicate.  Returns an array of validated manifests.
local function discover()
  local fs = love and love.filesystem
  local out = {}
  if not (fs and fs.getInfo and fs.getDirectoryItems) then return out end
  -- A fused portable build keeps its mods in the game folder next to the
  -- executable; resolving the cache root is what mounts that folder onto the
  -- physfs read path, so this is what makes those mods enumerable at all
  -- (#330).  A source run needs nothing (the game folder IS the source), and
  -- the launcher's readiness check has usually resolved it already; the call
  -- is cached and idempotent.
  CacheFs.root()
  if not fs.getInfo("mods") then return out end
  local seen = {}
  for _, name in ipairs(fs.getDirectoryItems("mods")) do
    local path = "mods/" .. name
    local info = fs.getInfo(path)
    -- a dev-linked mod dir (ln -s) reports type "symlink" even with
    -- setSymlinksEnabled(true); see the matching note in Loader:_discover.
    if info and (info.type == "directory" or info.type == "symlink") then
      local raw = fs.read(path .. "/manifest.json")
      if raw then
        local manifest = decodeManifest(raw, path)
        if manifest and not seen[manifest.id] then
          seen[manifest.id] = true
          out[#out + 1] = manifest
        end
      end
    end
  end
  return out
end

-- list() -> the mods-panel rows for the current install.  Reads the same
-- options.mods enable-state the loader persists, so a toggle here is what the
-- game sees on its next boot.
function LauncherMods.list()
  local ok, result = pcall(function()
    local options = SaveData.loadOptions()
    return LauncherMods.deriveList(discover(), options)
  end)
  if not ok then
    -- a single bad options/mod file must not blank the launcher
    return {}
  end
  return result or {}
end

-- ------- pre-boot translation strings
--
-- The launcher draws before Game:load, so the loader has not run and Strings
-- has no catalog.  #767/#791 routed the launcher's text through Strings, but
-- nothing filled the catalog this early, so a translation mod still could not
-- reach the launcher however complete it was -- and no restart helped, because
-- the ordering is the same on every launch.
--
-- This fills it, and deliberately does the smallest thing that can: one
-- declarative file per enabled mod, lang/strings.lua, and never the entry
-- chunk.  That keeps the promise the rest of this module is built on -- no mod
-- behaviour runs before the game boots -- because a catalog is data.
--
-- It is still a mod-authored chunk, so it runs with an empty environment: a
-- plain `return { ... }` evaluates fine, while anything reaching for love, io
-- or os raises and is skipped rather than being trusted this early.
--
-- Game:load calls Strings.load(Data) again after the real merge, which
-- replaces whatever this installed, so the two never disagree for long.
local STRINGS_CATALOG = "lang/strings.lua"

local function readStringsCatalog(path)
  local fs = love and love.filesystem
  if not (fs and fs.read) then return nil end
  local rel = path .. "/" .. STRINGS_CATALOG
  local raw = fs.read(rel)
  if type(raw) ~= "string" or raw == "" then return nil end
  local chunk = loadstring(raw, "@" .. rel)
  if not chunk then return nil end
  -- Lua 5.1/LuaJIT: no _ENV, so setfenv is the sandbox.
  if setfenv then setfenv(chunk, {}) end
  local ok, result = pcall(chunk)
  if not ok or type(result) ~= "table" then return nil end
  return result
end

-- deriveStrings(rows, byId, read) -> the merged catalog, pure.
-- rows is deriveList's output, byId the id -> manifest map, and read(path) a
-- reader returning that mod's catalog table (or nil).  Split out so the engine
-- tier can table-drive the enable/precedence rules with no filesystem.
function LauncherMods.deriveStrings(rows, byId, read)
  local out, any = {}, false
  for _, row in ipairs(rows or {}) do
    local manifest = row.enabled and byId and byId[row.id] or nil
    local catalog = manifest and manifest.path and read(manifest.path)
    for source, value in pairs(catalog or {}) do
      -- an empty value means "not translated yet", never "translate to
      -- blank" -- the same rule the mod's own loader applies
      if type(source) == "string" and type(value) == "string"
          and value ~= "" then
        out[source] = value
        any = true
      end
    end
  end
  return any and out or nil
end

-- translationStrings() -> a source -> translation map for the launcher, or nil
-- when no enabled mod ships one.  Enable-state and ordering are deriveList's,
-- so a mod that wins a key here wins it at boot too.
function LauncherMods.translationStrings()
  local ok, merged = pcall(function()
    local manifests = discover()
    if #manifests == 0 then return nil end
    local rows = LauncherMods.deriveList(manifests, SaveData.loadOptions())
    local byId = {}
    for _, m in ipairs(manifests) do byId[m.id] = m end
    return LauncherMods.deriveStrings(rows, byId, readStringsCatalog)
  end)
  if not ok then return nil end
  return merged
end

-- setEnabled(id, enabled): persist options.mods[id] in the exact shape
-- Loader:_saveState writes (a plain boolean), so the running game and the
-- in-game ManagerState pick it up unchanged.
function LauncherMods.setEnabled(id, enabled)
  local options = SaveData.loadOptions()
  options.mods = options.mods or {}
  options.mods[id] = enabled and true or false
  SaveData.saveOptions(options)
  return true
end

-- setAllEnabled(ids, enabled): the launcher's Enable all / Disable all buttons
-- (#647).  Writes exactly the options.mods shape setEnabled does, but loads and
-- saves once for the whole list: saveOptions rewrites the whole options file per
-- call, so looping setEnabled over a big mods folder is one disk write per mod
-- and leaves a half-applied state behind if one of them fails.
function LauncherMods.setAllEnabled(ids, enabled)
  local options = SaveData.loadOptions()
  options.mods = options.mods or {}
  for _, id in ipairs(ids or {}) do
    options.mods[id] = enabled and true or false
  end
  SaveData.saveOptions(options)
  return true
end

-- ------- install (love.filesystem)

-- Read a .zip source into bytes.  Save-dir-relative paths (inbox /
-- picked_mod.zip) prefer love.filesystem so NX/Android never hit a cwd-relative
-- io.open that can see a different file than PhysFS.  Absolute host paths
-- (desktop picker) still use io.*.  DroppedFile matches RomImporter ROM drops.
local function isHostAbsolutePath(path)
  return type(path) == "string" and (
      path:match("^/")
      or path:match("^%a:[/\\]")
      or path:match("^[Ss][Dd][Mm][Cc]:")
    )
end

local function readArchive(source)
  local t = type(source)
  if (t == "userdata" or t == "table") and type(source.open) == "function" then
    local ok = source:open("r")
    if not ok then return nil, "could not open the dropped file" end
    local data = source:read(source:getSize())
    source:close()
    if not data then return nil, "the dropped file could not be read" end
    return data
  end
  if t == "string" then
    if not isHostAbsolutePath(source) and love and love.filesystem then
      local data = love.filesystem.read(source)
      if data then return data end
    end
    local f = io.open(source, "rb")
    if f then
      local data = f:read("*a")
      f:close()
      if not data then return nil, "could not read " .. source end
      return data
    end
    if love and love.filesystem then
      local data = love.filesystem.read(source)
      if data then return data end
    end
    return nil, "could not open " .. source
  end
  return nil, "unsupported archive source"
end

-- Local PK\3\4 / empty-file check before mount (corrupt MTP / AppleDouble).
local function zipLooksValid(data)
  if type(data) ~= "string" or #data < 4 then return false end
  return data:sub(1, 2) == "PK"
end

-- Shallow listing of a mounted archive shaped for locateRoot: files by name,
-- and for each top-level directory a "<dir>/manifest.json" marker only when it
-- actually holds one (so a lone folder with no manifest still reads as empty).
local function topLevelPaths(mount)
  local fs = love.filesystem
  local paths = {}
  for _, name in ipairs(fs.getDirectoryItems(mount)) do
    local info = fs.getInfo(mount .. "/" .. name)
    if info and info.type == "directory" then
      if fs.getInfo(mount .. "/" .. name .. "/manifest.json", "file") then
        paths[#paths + 1] = name .. "/manifest.json"
      end
    else
      paths[#paths + 1] = name
    end
  end
  return paths
end

-- Copy the mounted archive subtree at `src` to the install path `dst`.  Reads
-- come from love.filesystem (the .zip is mounted there); every write goes
-- through CacheFs so it lands in the portable game folder when portable.txt is
-- in play and in the OS save directory otherwise (#330).  No explicit mkdir:
-- CacheFs.write creates the parent chain on both paths, which also means an
-- empty folder inside the .zip is simply not carried over (it holds nothing).
local function copyTree(src, dst)
  local fs = love.filesystem
  for _, name in ipairs(fs.getDirectoryItems(src)) do
    local s = src .. "/" .. name
    local d = dst .. "/" .. name
    local info = fs.getInfo(s)
    if info and info.type == "directory" then
      local ok, err = copyTree(s, d)
      if not ok then return nil, err end
    else
      local data = fs.read(s)
      if data == nil then return nil, "could not read " .. name end
      local ok, err = CacheFs.write(d, data)
      if not ok then return nil, "could not write " .. name .. ": " .. tostring(err) end
    end
  end
  return true
end

-- Delete an installed mod subtree.  Enumeration stays on love.filesystem (the
-- portable game folder is on its read path), but the deletes go through
-- CacheFs so a portable install's real files actually go away instead of
-- love.filesystem no-opping outside the save directory (#330).  Directories
-- are removed after their children, since rmdir refuses a non-empty one.
local function removeTree(path)
  local fs = love.filesystem
  local info = fs.getInfo(path)
  if not info then return end
  if info.type == "directory" then
    for _, child in ipairs(fs.getDirectoryItems(path)) do
      removeTree(path .. "/" .. child)
    end
    CacheFs.removeDir(path)
  else
    CacheFs.remove(path)
  end
  -- A portable install can still be carrying a pre-#330 copy in the OS save
  -- directory, which is where every install used to land and which physfs
  -- searches first.  CacheFs only touched the game folder, so clear the
  -- save-directory twin too or that copy would keep the mod alive; outside
  -- portable mode this repeats the delete CacheFs just did and no-ops.
  fs.remove(path)
end

-- ------- strays: mods dropped beside the game that it cannot see

-- love.filesystem looks in two places for "mods/": the save directory, and --
-- portable installs only -- the game folder, which CacheFs mounts.  A player
-- who unzips a mod next to the executable of an ordinary install, which is
-- where very nearly every other game would want it, gets no error and no mod.
-- The MODS panel simply stays empty, and there is nothing on screen to
-- suggest the files are twenty centimetres away in the wrong folder.
--
-- The scan mounts each game folder at a private mount point just long enough
-- to list mods/ inside it and drops it again (CacheFs.withMounted), so the
-- read path the game actually runs on is never touched and a stray can never
-- shadow a real file.
local STRAY_MOUNT = "stray_scan"

-- Run fn(mountedModsRoot) for each game folder that has a readable mods/
-- directory, one mount at a time.  Folders already on the read path are
-- skipped (isReadableRoot): the physfs source, which is every `love <gamedir>`
-- dev run, and the portable game folder CacheFs mounted, where re-mounting is
-- what used to drop the mount (#413).
local function eachStrayRoot(fn)
  local SaveData_ = require("src.core.SaveData")
  local fs = love and love.filesystem
  if not fs then return end
  local source = fs.getSource and fs.getSource()
  local cacheRoot = CacheFs.root()
  local seen = {}
  for _, folder in ipairs(SaveData_.gameFolders() or {}) do
    if not seen[folder]
      and not LauncherMods.isReadableRoot(folder, source, cacheRoot) then
      seen[folder] = true
      CacheFs.withMounted(folder, STRAY_MOUNT, function()
        local root = STRAY_MOUNT .. "/mods"
        if fs.getInfo(root) then fn(root, folder) end
      end)
    end
  end
end

-- Every valid mod folder sitting in a game folder's mods/, in scan order.
-- Only reads.  The rows carry the mounted path, which is live for the length
-- of the mount and dead after it -- copying has to happen inside the same
-- scan, which is why adoption is a flag here rather than a second pass.
local function findStrays(fs, adopt, installed)
  local found, adopted = {}, {}
  eachStrayRoot(function(root, folder)
    local batch = {}
    for _, name in ipairs(fs.getDirectoryItems(root)) do
      local path = root .. "/" .. name
      local info = fs.getInfo(path)
      if info and info.type == "directory" then
        local raw = fs.read(path .. "/manifest.json")
        local manifest = raw and decodeManifest(raw, path)
        if manifest then
          batch[#batch + 1] = { id = manifest.id,
                                name = manifest.name or manifest.id,
                                folder = folder, path = path }
        end
      end
    end
    -- filtered per mount, so a copy only ever runs for a row that survived
    -- the pure rules -- and so the second game folder sees the first one's
    -- ids as taken
    for _, row in ipairs(LauncherMods.pickStrays(batch, installed)) do
      if adopt then
        -- same root pin installZip uses: the mods tree is shared by Red and
        -- Blue, never version-prefixed (#330)
        local savedPrefix = CacheFs.prefix
        CacheFs.prefix = ""
        local dest = "mods/" .. row.id
        local copied, copyErr = copyTree(row.path, dest)
        if not copied then removeTree(dest) end
        CacheFs.prefix = savedPrefix
        if not copied then row.err = copyErr or "could not copy the files" end
      end
      installed[row.id] = true
      row.path = nil                    -- dead once this mount comes down
      adopted[#adopted + 1] = row
      found[#found + 1] = row
    end
  end)
  return LauncherMods.pickStrays(found, {})
end

-- The strays, optionally adopted.  A folder whose id the game can already see
-- is left out: the player has a working copy, and the loose one is just where
-- they first put it.  Rows that failed to copy come back with .err set.
local function scanStrays(adopt)
  local fs = love and love.filesystem
  if not fs then return {} end
  local installed = {}
  for _, m in ipairs(discover()) do installed[m.id] = true end
  return findStrays(fs, adopt, installed)
end

-- strays() -> the rows, nothing copied.
function LauncherMods.strays() return scanStrays(false) end

-- adoptStrays() -> the rows, each one copied into the mods tree the game
-- really reads (rows carrying .err failed).  Idempotent: a second call finds
-- the ids installed and returns nothing, so the panel can run this on every
-- open without duplicating anything or nagging twice.  The loose folder is
-- deliberately left where it is -- deleting files outside the save directory
-- on the player's behalf is not this function's call to make.
function LauncherMods.adoptStrays() return scanStrays(true) end

-- installZip(source [, opts]) -> true, id  |  nil, errString
-- source is an external path or a love DroppedFile.  The archive is validated
-- BEFORE anything is copied; every path unmounts and clears the staged temp
-- file, and a failed copy rolls its partial tree back.  A dropped file outside
-- the save dir is staged into a save-dir temp first, because
-- love.filesystem.mount only reaches a save-directory-relative path.
-- opts.replace = true uninstalls an existing same-id mod first (updates /
-- rollbacks).  opts.expectId, when set, refuses a zip whose manifest id differs.
function LauncherMods.installZip(source, opts)
  local ok, result, err = pcall(LauncherMods._installZipInner, source, opts)
  if not ok then return nil, "import failed: " .. tostring(result) end
  return result, err
end

function LauncherMods._installZipInner(source, opts)
  opts = opts or {}
  if not (love and love.filesystem) then
    return nil, "mod install needs LOVE"
  end
  local fs = love.filesystem
  local data, readErr = readArchive(source)
  if not data then return nil, readErr end
  if not zipLooksValid(data) then
    local label = type(source) == "string" and (source:match("[^/\\]+$") or source)
      or "archive"
    return nil, "not a zip file: " .. tostring(label)
      .. " (need a real .zip; skip Mac ._ files from MTP)"
  end

  -- Prefer in-memory mount (PHYSFS_mountMemory via FileData). Avoids Horizon's
  -- "file already open" failure when write-then-mount reopens a save-dir zip.
  local mount = "mod_import_mount"
  local tmp = nil
  local mountKey = nil
  local mounted = false
  if fs.newFileData then
    local archiveName = ("mod_import_%d_%d.zip"):format(
      os.time(), math.random(0, 999999))
    local okFd, fd = pcall(fs.newFileData, data, archiveName)
    if okFd and fd and fs.mount(fd, mount) then
      mounted = true
      mountKey = fd
    end
  end
  if not mounted then
    -- Fallback: stage into a save-dir temp so path-mount can reach it.
    tmp = ("mod_import_%d_%d.zip"):format(os.time(), math.random(0, 999999))
    local ok, writeErr = fs.write(tmp, data)
    if not ok then
      return nil, "could not stage the .zip: " .. tostring(writeErr)
    end
    if not fs.mount(tmp, mount) then
      fs.remove(tmp)
      return nil, "that .zip could not be opened"
    end
    mountKey = tmp
  end
  local function cleanup()
    pcall(fs.unmount, mountKey)
    if tmp then fs.remove(tmp) end
  end

  local prefix, rootErr = LauncherMods.locateRoot(topLevelPaths(mount))
  if not prefix then
    cleanup()
    return nil, rootErr
  end
  local root = prefix == "" and mount or (mount .. "/" .. prefix)

  local raw = fs.read(root .. "/manifest.json")
  if not raw then
    cleanup()
    return nil, "the .zip has no readable manifest.json"
  end
  local manifest, manifestErr = decodeManifest(raw, root)
  if not manifest then
    cleanup()
    return nil, "invalid mod manifest: " .. tostring(manifestErr)
  end
  if opts.expectId and manifest.id ~= opts.expectId then
    cleanup()
    return nil, ("zip is for '%s', expected '%s'")
      :format(manifest.id, opts.expectId)
  end

  local dest = "mods/" .. manifest.id
  if fs.getInfo(dest) then
    if not opts.replace then
      cleanup()
      return nil, "a mod named '" .. manifest.id .. "' is already installed"
    end
    -- drop the old tree before copy; enable-flag is preserved (uninstall
    -- would clear it, which would surprise an update)
    local savedPrefix = CacheFs.prefix
    CacheFs.prefix = ""
    removeTree(dest)
    CacheFs.prefix = savedPrefix
  end

  -- CacheFs.prefix steers ROM-cache writes into a version subtree (blue/...);
  -- the mods tree is shared by Red and Blue, so pin the prefix to the root for
  -- the copy and the rollback, then hand back whatever the launcher had set
  -- (an import coroutine leaves it pointed at that version -- RomImporter.lua).
  -- No fs.createDirectory("mods") here any more: CacheFs.write creates the
  -- parent chain in both homes, and doing it through love.filesystem would
  -- only ever make the directory in the save dir (#330).
  local savedPrefix = CacheFs.prefix
  CacheFs.prefix = ""
  local copied, copyErr = copyTree(root, dest)
  if not copied then removeTree(dest) end
  CacheFs.prefix = savedPrefix
  if not copied then
    cleanup()
    return nil, copyErr or "could not copy the mod files"
  end
  cleanup()
  return true, manifest.id
end

-- Install (or replace) a mod from a GitHub release zip URL.
-- Returns true, version  |  nil, errString. Soft-fails: download / install /
-- cleanup errors never throw into the launcher UI.
function LauncherMods.installFromRelease(modId, release)
  local ok, result, err = pcall(function()
    if type(modId) ~= "string" or modId == "" then
      return nil, "missing mod id"
    end
    if type(release) ~= "table" or not release.zip or not release.zip.url then
      return nil, "release has no downloadable .zip"
    end
    local ModUpdate = require("src.mods.ModUpdate")
    local tmpName = ("mod_update_%s_%s.zip"):format(
      tostring(modId), tostring(release.version or os.time()))
    local localPath, dlErr = ModUpdate.downloadZip(release.zip.url, tmpName)
    if not localPath then return nil, dlErr end
    local installed, res = LauncherMods.installZip(localPath, {
      replace = true, expectId = modId,
    })
    pcall(love.filesystem.remove, localPath)
    if not installed then return nil, res end
    return true, release.version or res
  end)
  if not ok then return nil, "install failed: " .. tostring(result) end
  return result, err
end

-- Install a mod listed in a community index (src/mods/ModIndex.lua).
-- The index only ever tells us WHERE the zip is; resolving that URL is
-- ModIndex's job and installing it is installFromRelease's, so this is the
-- seam between them and nothing about the archive is special-cased.  expectId
-- comes from the listing, so a feed that points an entry at somebody else's
-- zip fails the manifest check instead of installing the wrong mod.
-- Returns true, version | nil, errString.
function LauncherMods.installFromIndex(entry)
  local ok, result, err = pcall(function()
    if type(entry) ~= "table" or type(entry.id) ~= "string" then
      return nil, "index entry has no mod id"
    end
    local ModIndex = require("src.mods.ModIndex")
    local release, why = ModIndex.releaseFor(entry)
    if not release then
      return nil, why or "this mod cannot be installed from the index"
    end
    return LauncherMods.installFromRelease(entry.id, release)
  end)
  if not ok then return nil, "install failed: " .. tostring(result) end
  return result, err
end

-- uninstall(id) -> true  |  nil, errString
-- Removes mods/<id>/ from wherever it was installed (the portable game folder
-- or the save directory, CacheFs decides -- #330) and clears options.mods[id]
-- so the loader and in-game manager no longer see it.  Rejects missing ids.
-- Does not touch other mods' enable state.
function LauncherMods.uninstall(id)
  if type(id) ~= "string" or id == "" then
    return nil, "missing mod id"
  end
  if id:find("[/\\]") or id == "." or id == ".." then
    return nil, "invalid mod id"
  end
  if not (love and love.filesystem) then
    return nil, "mod uninstall needs LOVE"
  end
  local fs = love.filesystem
  local dest = "mods/" .. id
  if not fs.getInfo(dest) then
    return nil, "mod '" .. id .. "' is not installed"
  end
  -- same root pin as installZip: the mods tree is not version-prefixed (#330)
  local savedPrefix = CacheFs.prefix
  CacheFs.prefix = ""
  removeTree(dest)
  CacheFs.prefix = savedPrefix
  -- Drop the enable flag so a reinstall of the same id starts from the
  -- loader's default (enabled) rather than a stale false.
  local options = SaveData.loadOptions()
  if options.mods and options.mods[id] ~= nil then
    options.mods[id] = nil
    SaveData.saveOptions(options)
  end
  return true
end

return LauncherMods
