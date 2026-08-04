-- Routes ROM-derived cache I/O (data/generated, assets/generated and the
-- rom-cache.complete marker) to the right place.
--
-- Normally the cache lives in LÖVE's per-user OS save directory and is
-- written through love.filesystem.  In portable mode it lives in the game
-- folder next to the executable instead (the folder holding portable.txt --
-- see SaveData), so nothing is left on the host machine.  That folder is
-- written with raw io.* (love.filesystem can only write to the save dir) and
-- read back through love.filesystem, require and love.graphics.newImage --
-- which works because the folder is on the physfs read path:
--
--   * Source runs (`love <gamedir>`, what the Play-* launchers use): the
--     folder IS the physfs source, so it is already readable.
--   * Fused builds (the packaged .app/.exe): the folder sits next to the
--     executable and is NOT normally readable, so CacheFs mounts it onto the
--     read path via PhysFS.  love.filesystem.mount refuses external folders,
--     but the underlying PHYSFS_mount (exported from love's framework) allows
--     them; we call it through LuaJIT's FFI.
--
-- Directories in the portable folder are created with a plain mkdir syscall
-- via FFI rather than os.execute, so importing never flashes a console window
-- on Windows (issue #74 -- the old per-file `os.execute("mkdir")` froze the
-- app behind a storm of one-frame cmd.exe windows).
--
-- Portable mode is desktop-only (Windows/Linux/macOS); on Android/iOS the
-- source is a read-only package with no game folder to write into, so
-- SaveData.isPortable() is false there and this module falls back to the
-- ordinary love.filesystem/save-directory behaviour.

local CacheFs = {}

local SEP = package.config:sub(1, 1)

-- Cache-relative paths are prefixed with this before every read/write, so a
-- Blue/Yellow import lands under its GameVersion.cachePrefix (blue/, yellow/)
-- while a Red import keeps the historical root.  The launcher sets it per
-- import / per readiness check; it stays "" for Red.  Runtime *reads*
-- (require / newImage) do NOT go through here -- CacheFs.mountVersion overlays
-- the active version's subtree onto the un-prefixed paths instead.
CacheFs.prefix = ""

local function withPrefix(rel)
  local p = CacheFs.prefix
  if p == nil or p == "" then return rel end
  return p .. rel
end

-- lazily-resolved windowless mkdir: function(absolutePath) or false when
-- FFI is unavailable (the cache then stays on the save directory)
local mkdirFn = nil

local function resolveMkdir()
  if mkdirFn ~= nil then return mkdirFn end
  mkdirFn = false
  local ok, ffi = pcall(require, "ffi")
  if not ok then return mkdirFn end
  if ffi.os == "Windows" then
    -- kernel32 is reliably resolvable through ffi.C on Windows (the engine
    -- already binds it in DiscordPresence); CreateDirectoryA returns
    -- nonzero on success and 0 when the directory already exists -- both
    -- fine, the result is ignored.
    pcall(ffi.cdef,
      "int CreateDirectoryA(const char *lpPathName, void *lpSecurityAttributes);")
    local resolved = pcall(function() return ffi.C.CreateDirectoryA end)
    if resolved then
      mkdirFn = function(path) pcall(ffi.C.CreateDirectoryA, path, nil) end
    end
  else
    pcall(ffi.cdef, "int mkdir(const char *pathname, unsigned int mode);")
    local resolved = pcall(function() return ffi.C.mkdir end)
    if resolved then
      mkdirFn = function(path) pcall(ffi.C.mkdir, path, 493) end -- 0755
    end
  end
  return mkdirFn
end

-- Lazily-resolved windowless rmdir, the mirror of resolveMkdir above:
-- function(absolutePath) or false when FFI is unavailable.  Both syscalls
-- refuse a non-empty directory, so a caller has to delete the files first.
local rmdirFn = nil

local function resolveRmdir()
  if rmdirFn ~= nil then return rmdirFn end
  rmdirFn = false
  local ok, ffi = pcall(require, "ffi")
  if not ok then return rmdirFn end
  if ffi.os == "Windows" then
    pcall(ffi.cdef, "int RemoveDirectoryA(const char *lpPathName);")
    local resolved = pcall(function() return ffi.C.RemoveDirectoryA end)
    if resolved then
      rmdirFn = function(path) pcall(ffi.C.RemoveDirectoryA, path) end
    end
  else
    pcall(ffi.cdef, "int rmdir(const char *pathname);")
    local resolved = pcall(function() return ffi.C.rmdir end)
    if resolved then
      rmdirFn = function(path) pcall(ffi.C.rmdir, path) end
    end
  end
  return rmdirFn
end

-- Mount an external directory onto the physfs read path (appended, so the
-- game's own source always wins a name clash).  Returns true on success.
--
-- PHYSFS_mount is exported by love's own binary.  How ffi finds it differs
-- per platform: on macOS/Linux the symbol is in the default namespace, so
-- ffi.C resolves it; on Windows it lives in love.dll, which ffi.C does NOT
-- search, so love.dll is loaded explicitly with ffi.load("love").  Try the
-- default first, then love.
local physfsMountFn = nil
local function resolveMount()
  if physfsMountFn ~= nil then return physfsMountFn end
  physfsMountFn = false
  local ok, ffi = pcall(require, "ffi")
  if not ok then return physfsMountFn end
  pcall(ffi.cdef,
    "int PHYSFS_mount(const char *newDir, const char *mountPoint, int appendToPath);")
  local libs = {
    function() return ffi.C end,
    function() return ffi.load("love") end,
  }
  for _, getlib in ipairs(libs) do
    local okl, lib = pcall(getlib)
    if okl and lib then
      local oks, fn = pcall(function() return lib.PHYSFS_mount end)
      if oks and fn then
        physfsMountFn = function(d, mountPoint, append)
          if append == nil then append = true end
          local okr, ret = pcall(fn, d, mountPoint or "", append and 1 or 0)
          return okr and ret ~= 0
        end
        break
      end
    end
  end
  return physfsMountFn
end

-- append (default true): the game's own source wins a name clash, matching
-- how the portable cache root has always been mounted.  Pass false to
-- prepend, so the mounted tree wins -- used to overlay the active version's
-- cache on top of the root (Red) copy and the source.
local function mountReadable(dir, append)
  local fn = resolveMount()
  if not fn then return false end
  return fn(dir, "", append)
end

-- PHYSFS_unmount, resolved the same way PHYSFS_mount is.  Only
-- CacheFs.unmountVersion needs it: the launcher can open the save editor on
-- one game's cache and then Play the other, and an overlay left mounted
-- would win the read path for the rest of the process.
local physfsUnmountFn = nil
local function resolveUnmount()
  if physfsUnmountFn ~= nil then return physfsUnmountFn end
  physfsUnmountFn = false
  local ok, ffi = pcall(require, "ffi")
  if not ok then return physfsUnmountFn end
  pcall(ffi.cdef, "int PHYSFS_unmount(const char *oldDir);")
  local libs = {
    function() return ffi.C end,
    function() return ffi.load("love") end,
  }
  for _, getlib in ipairs(libs) do
    local okl, lib = pcall(getlib)
    if okl and lib then
      local oks, fn = pcall(function() return lib.PHYSFS_unmount end)
      if oks and fn then
        physfsUnmountFn = function(d)
          local okr, ret = pcall(fn, d)
          return okr and ret ~= 0
        end
        break
      end
    end
  end
  return physfsUnmountFn
end

-- PHYSFS_getMountPoint, resolved the same way: a non-NULL return means `dir`
-- is already somewhere in the search path.  withMounted needs it because
-- PHYSFS_mount reports success for an already-mounted directory without
-- adding a second entry, so its unmount would drop a mount it did not make
-- (#413).
local physfsMountPointFn = nil
local function resolveMountPoint()
  if physfsMountPointFn ~= nil then return physfsMountPointFn end
  physfsMountPointFn = false
  local ok, ffi = pcall(require, "ffi")
  if not ok then return physfsMountPointFn end
  pcall(ffi.cdef, "const char *PHYSFS_getMountPoint(const char *dir);")
  local libs = {
    function() return ffi.C end,
    function() return ffi.load("love") end,
  }
  for _, getlib in ipairs(libs) do
    local okl, lib = pcall(getlib)
    if okl and lib then
      local oks, fn = pcall(function() return lib.PHYSFS_getMountPoint end)
      if oks and fn then
        physfsMountPointFn = function(d)
          local okr, ret = pcall(fn, d)
          return okr and ret ~= nil and ret ~= ffi.NULL
        end
        break
      end
    end
  end
  return physfsMountPointFn
end

-- The portable game folder when the cache should live there, else nil.
-- Resolved (and, for a fused build, mounted) once and cached.  Requires a
-- desktop portable install (SaveData) and a working windowless mkdir.
local portableRoot = nil
local portableResolved = false
local function resolvePortableRoot()
  if portableResolved then return portableRoot end
  portableResolved = true
  portableRoot = nil
  if not resolveMkdir() then return nil end
  local base = require("src.core.SaveData").portableBaseDir()
  if not base then return nil end
  if love.filesystem.getSource and base == love.filesystem.getSource() then
    -- source run: the folder is already the physfs source
    portableRoot = base
  elseif mountReadable(base) then
    -- fused build: base is next to the executable; mount it so io.* writes
    -- there are visible to love.filesystem/require/newImage
    portableRoot = base
  end
  return portableRoot
end

function CacheFs.root()
  return resolvePortableRoot()
end

local function realPath(root, rel)
  return root .. SEP .. rel:gsub("/", SEP)
end

-- create every parent directory of `rel` under `root` (best effort; an
-- already-existing directory is fine, a genuine failure surfaces when the
-- subsequent io.open write fails)
local function ensureParents(root, rel)
  local mkdir = resolveMkdir()
  if not mkdir then return end
  local parts = {}
  for part in rel:gmatch("[^/]+") do parts[#parts + 1] = part end
  local cur = root
  for i = 1, #parts - 1 do
    cur = cur .. SEP .. parts[i]
    mkdir(cur)
  end
end

-- write cache-relative `rel` (forward-slash path) with the given bytes;
-- returns ok, err like love.filesystem.write
function CacheFs.write(rel, data)
  rel = withPrefix(rel)
  local root = CacheFs.root()
  if root then
    ensureParents(root, rel)
    local f, err = io.open(realPath(root, rel), "wb")
    if not f then return false, err end
    f:write(data)
    f:close()
    return true
  end
  local parent = rel:match("^(.*)/[^/]+$")
  if parent and not love.filesystem.createDirectory(parent) then
    local info = love.filesystem.getInfo(parent)
    local reason = info and ("a " .. info.type .. " already exists there")
      or "unknown reason"
    return false, "could not create " .. parent .. ": " .. reason
  end
  return love.filesystem.write(rel, data)
end

-- read cache-relative `rel`; returns the bytes or nil
function CacheFs.read(rel)
  rel = withPrefix(rel)
  local root = CacheFs.root()
  if root then
    local f = io.open(realPath(root, rel), "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
  end
  return love.filesystem.read(rel)
end

-- Read cache-relative `rel` for the active GameVersion when PhysFS may hide
-- prefixed Blue/Yellow trees (fused NX mount hole). Same order Data:load
-- already used: active version prefix with CacheFs.prefix cleared, then
-- `rel` under the caller's CacheFs.prefix. Returns the bytes or nil.
function CacheFs.readActive(rel)
  local GameVersion = require("src.core.GameVersion")
  local prefix = GameVersion.cachePrefix()
  local saved = CacheFs.prefix
  CacheFs.prefix = ""
  local bytes = CacheFs.read(prefix .. rel)
  CacheFs.prefix = saved
  if type(bytes) ~= "string" then
    bytes = CacheFs.read(rel)
  end
  if type(bytes) == "string" then return bytes end
  return nil
end

-- does cache-relative `rel` exist as a file?
function CacheFs.exists(rel)
  rel = withPrefix(rel)
  local root = CacheFs.root()
  if root then
    local f = io.open(realPath(root, rel), "rb")
    if not f then return false end
    f:close()
    return true
  end
  return love.filesystem.getInfo(rel, "file") ~= nil
end

-- remove a single cache-relative file
function CacheFs.remove(rel)
  rel = withPrefix(rel)
  local root = CacheFs.root()
  if root then
    os.remove(realPath(root, rel))
    return
  end
  love.filesystem.remove(rel)
end

-- Remove a single cache-relative directory once its files are gone.  Needed
-- because os.remove cannot delete a directory on Windows and
-- love.filesystem.remove never reaches outside the save directory, so the
-- portable game folder gets the same FFI-syscall treatment as its mkdir
-- (issue #74: os.execute would flash a console window per call).  Used by the
-- mod installer so an uninstall leaves nothing behind (#330).
function CacheFs.removeDir(rel)
  rel = withPrefix(rel)
  local root = CacheFs.root()
  if root then
    local rmdir = resolveRmdir()
    if rmdir then rmdir(realPath(root, rel)) end
    return
  end
  love.filesystem.remove(rel)
end

-- Remove the game-folder copy of a cache subtree before a fresh import, so a
-- cache-format bump does not leave orphaned files behind.  No-op when the
-- portable cache is inactive (the save-directory copy is cleared by
-- RomImporter's own removeTree).  The tree is enumerated through
-- love.filesystem (the game folder is mounted) and the real files deleted
-- with os.remove; empty directories are harmless and left in place.
function CacheFs.removeTree(rel)
  rel = withPrefix(rel)
  local root = CacheFs.root()
  if not root then return end
  local function walk(r)
    local info = love.filesystem.getInfo(r)
    if not info then return end
    if info.type == "directory" then
      for _, child in ipairs(love.filesystem.getDirectoryItems(r)) do
        walk(r .. "/" .. child)
      end
    else
      os.remove(realPath(root, r))
    end
  end
  walk(rel)
end

-- Overlay the active version's extracted cache onto the un-prefixed read
-- paths, so require("data.generated.*") and love.graphics.newImage(
-- "assets/generated/*") resolve to that version's files.
--
-- Non-Red versions live under blue/ / yellow/ in the save directory.  On
-- desktop fused+portable we PHYSFS_mount that folder by absolute path.  On
-- NX (and any host without a working FFI mount) love.filesystem.mount of
-- the save-dir-relative name must succeed, or Play boots with Red's paths
-- and Data:load dies.  Always also prepend-mount the version's
-- data/generated + assets/generated onto the un-prefixed paths so PhysFS
-- directory non-merge (archive data/ vs save generated) cannot hide them.
local function mountGeneratedTrees(prefix)
  prefix = prefix or ""
  if not (love and love.filesystem and love.filesystem.mount) then
    return false
  end
  local mounted = false
  local pairs_ = {
    { prefix .. "data/generated", "data/generated" },
    { prefix .. "assets/generated", "assets/generated" },
  }
  for _, item in ipairs(pairs_) do
    local src, dest = item[1], item[2]
    if love.filesystem.getInfo(src, "directory") then
      if love.filesystem.mount(src, dest, false) then
        mounted = true
      end
    end
  end
  return mounted
end

function CacheFs.mountVersion(version)
  local prefix = require("src.core.GameVersion").cachePrefix(version)
  local sub = prefix:gsub("/+$", "")

  -- Save-dir relative mount first (NX / no-FFI). Prepend so blue|yellow win.
  if sub ~= "" and love.filesystem.mount
      and love.filesystem.getInfo(sub, "directory") then
    love.filesystem.mount(sub, "", false)
  end

  -- Portable / desktop fused: absolute PHYSFS_mount of the version folder.
  if sub ~= "" then
    local base = CacheFs.root()
    if not base and love.filesystem.getSaveDirectory then
      base = love.filesystem.getSaveDirectory()
    end
    if base then
      mountReadable(base .. SEP .. sub, false)
    end
  end

  -- Version-scoped generated trees → un-prefixed paths (Red prefix is "").
  mountGeneratedTrees(prefix)
  return true
end

-- Undo mountVersion.  A process normally mounts exactly one version and then
-- boots it, but the launcher can open the save editor on a Blue/Yellow save,
-- close it, and press Play on Red: with that version's subtree still
-- prepended, Red's require("data.generated.*") and its generated art would
-- silently resolve to the other game's files.  Callers must also drop the
-- generated modules from package.loaded (src.core.Data:unloadGenerated) --
-- unmounting alone only fixes the read path, not what require already cached.
--
-- Returns true when nothing was mounted or the unmount took.  Red is a no-op
-- because its cache lives at the root and was never overlaid.
function CacheFs.unmountVersion(version)
  local prefix = require("src.core.GameVersion").cachePrefix(version)
  if prefix == "" then return true end
  local sub = prefix:gsub("/+$", "")
  local base = CacheFs.root()
  if not base and love.filesystem.getSaveDirectory then
    base = love.filesystem.getSaveDirectory()
  end
  local done = false
  local fn = resolveUnmount()
  if fn and base then
    done = fn(base .. SEP .. sub) or done
  end
  -- also drop the love.filesystem.mount fallback, which registers the folder
  -- under its bare name rather than its absolute path
  if love.filesystem.unmount then
    done = love.filesystem.unmount(sub) or done
  end
  return done
end

-- Mount `dir` at `mountPoint` for the length of `fn()`, then take it back off
-- the read path and hand back whatever fn returned.
--
-- Every other mount here is permanent and lands at the physfs root: this one
-- exists to *look* at a folder the game has deliberately not mounted, which
-- is a different job.  The mods panel uses it to read a mods/ folder sitting
-- beside the executable of a non-portable install (LauncherMods.strays).
-- Because it unmounts again, and because a non-empty mountPoint keeps the
-- tree in its own corner of the namespace while it is up, a folder inspected
-- this way can never shadow a game file or change what the running game
-- resolves -- which is what makes it safe to point at a folder whose contents
-- nobody has validated.
--
-- Returns nil when the mount is unavailable (no ffi, no PHYSFS symbol, the
-- mount was refused, or `dir` is already on the read path), which callers must
-- treat as "could not look", not as "nothing there".  An error inside fn still
-- unmounts before it propagates.
function CacheFs.withMounted(dir, mountPoint, fn)
  if not dir or dir == "" then return nil end
  local mount, unmount = resolveMount(), resolveUnmount()
  if not (mount and unmount) then return nil end
  -- A directory already in the search path cannot be borrowed: PHYSFS_mount
  -- returns success without adding an entry, and the unmount below would then
  -- remove the mount somebody else is relying on -- for the portable game
  -- folder, the one that makes its cache and mods readable at all (#413)
  local mountedAt = resolveMountPoint()
  if mountedAt and mountedAt(dir) then return nil end
  if not mount(dir, mountPoint, true) then return nil end
  local ok, res = pcall(fn)
  unmount(dir)
  if not ok then error(res, 0) end
  return res
end

return CacheFs
