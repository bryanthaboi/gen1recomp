-- Launcher-side mod surface (18/launcher redesign): the mods panel runs
-- BEFORE Game:load, so this NEVER loads a mod entry chunk -- it scans
-- manifests only.  The full loader (src/mods/Loader.lua) still owns the real
-- load at boot; this reads the same options.mods enable-state the loader
-- writes, derives per-mod status with the pure ManagerState.resolveToggle,
-- installs a dropped/chosen .zip into the save-dir "mods/<id>/" tree, and
-- uninstalls a mod by removing that tree + clearing options.mods[id].
--
-- Split in two: the pure derivation (deriveList, locateRoot) has no love and
-- no filesystem, so the engine tier can table-drive it; the discovery,
-- install, and uninstall paths reach for love.filesystem and SaveData.

local Manifest = require("src.mods.Manifest")
local ManagerState = require("src.mods.ManagerState")
local Semver = require("src.mods.Semver")
local Version = require("src.core.Version")
local SaveData = require("src.core.SaveData")

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
    -- missing entry means enabled, matching the loader's default
    if mods[m.id] ~= false then enabledSet[m.id] = true end
  end

  local out = {}
  for _, m in ipairs(ordered) do
    local enabled = enabledSet[m.id] == true
    local status, detail = statusFor(byId, m.id, enabledSet, enabled)
    local raw = m.raw or {}
    out[#out + 1] = {
      id = m.id,
      name = m.name or m.id,
      version = m.version,
      -- category, then profile, then a generic fallback -- uppercased
      badge = tostring(raw.category or m.profile or "MOD"):upper(),
      description = m.description or "",
      enabled = enabled,
      status = status,
      statusDetail = detail,
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
  if not fs.getInfo("mods") then return out end
  local seen = {}
  for _, name in ipairs(fs.getDirectoryItems("mods")) do
    local path = "mods/" .. name
    local info = fs.getInfo(path)
    if info and info.type == "directory" then
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
  local options = SaveData.loadOptions()
  return LauncherMods.deriveList(discover(), options)
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

-- ------- install (love.filesystem)

-- Read a .zip source into bytes.  A string is an external absolute path (like
-- a chosen ROM) read with io.*, falling back to a save-dir-relative
-- love.filesystem read; a love DroppedFile is opened the way RomImporter
-- ingests dropped ROMs.
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

local function copyTree(src, dst)
  local fs = love.filesystem
  if not fs.createDirectory(dst) then
    return nil, "could not create " .. dst
  end
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
      local ok, err = fs.write(d, data)
      if not ok then return nil, "could not write " .. name .. ": " .. tostring(err) end
    end
  end
  return true
end

local function removeTree(path)
  local fs = love.filesystem
  local info = fs.getInfo(path)
  if not info then return end
  if info.type == "directory" then
    for _, child in ipairs(fs.getDirectoryItems(path)) do
      removeTree(path .. "/" .. child)
    end
  end
  fs.remove(path)
end

-- installZip(source) -> true, id  |  nil, errString
-- source is an external path or a love DroppedFile.  The archive is validated
-- BEFORE anything is copied; every path unmounts and clears the staged temp
-- file, and a failed copy rolls its partial tree back.  A dropped file outside
-- the save dir is staged into a save-dir temp first, because
-- love.filesystem.mount only reaches a save-directory-relative path.
function LauncherMods.installZip(source)
  if not (love and love.filesystem) then
    return nil, "mod install needs LOVE"
  end
  local fs = love.filesystem
  local data, readErr = readArchive(source)
  if not data then return nil, readErr end

  -- stage into a save-dir temp so mount can reach it
  local tmp = ("mod_import_%d_%d.zip"):format(os.time(), math.random(0, 999999))
  local ok, writeErr = fs.write(tmp, data)
  if not ok then
    return nil, "could not stage the .zip: " .. tostring(writeErr)
  end
  local mount = "mod_import_mount"
  if not fs.mount(tmp, mount) then
    fs.remove(tmp)
    return nil, "that .zip could not be opened"
  end
  local function cleanup()
    pcall(fs.unmount, tmp)
    fs.remove(tmp)
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

  -- reject a duplicate before touching the mods tree
  local dest = "mods/" .. manifest.id
  if fs.getInfo(dest) then
    cleanup()
    return nil, "a mod named '" .. manifest.id .. "' is already installed"
  end

  fs.createDirectory("mods")
  local copied, copyErr = copyTree(root, dest)
  if not copied then
    removeTree(dest)
    cleanup()
    return nil, copyErr or "could not copy the mod files"
  end
  cleanup()
  return true, manifest.id
end

-- uninstall(id) -> true  |  nil, errString
-- Removes mods/<id>/ from the save directory and clears options.mods[id] so the
-- loader and in-game manager no longer see it.  Rejects unknown / missing ids.
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
  removeTree(dest)
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
