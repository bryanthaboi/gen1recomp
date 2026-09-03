local GameVersion = require("src.core.GameVersion")
local GamepadMap = require("src.core.GamepadMap")
local Logger = require("src.core.Logger")
local Strings = require("src.core.Strings")
local HostShell = require("src.core.HostShell")
local Platform = require("src.core.Platform")
local SafeArea = require("src.core.SafeArea")

local RomImporter = {}
RomImporter.__index = RomImporter

local PICK_COMPLETE_FILENAME = "pick_complete.flag"
local finishDirectRequiredImport

-- love.system.pickFile is a NATIVE BRIDGE, not part of LÖVE: it exists only on
-- builds that compiled one (Android, and iOS builds patched by
-- mobile/ios/patch_love_src.py). A build without it must fall back to the
-- copy-it-into-the-save-folder flow that every caller below already has --
-- calling the nil field instead took the whole app down the moment the player
-- pressed Import ROM:
--
--   src/import/RomImporter.lua: attempt to call field 'pickFile' (a nil value)
--
-- love.system.createFile was already guarded this way at its one call site;
-- these three were not. Every caller here treats `false` as "no picker
-- available" and shows its own notice, so a missing bridge now degrades to
-- exactly the path a picker-less Android device has always taken.
local function pickFile(...)
  local fn = love.system.pickFile
  if not fn then return false end
  return fn(...) and true or false
end

local CART_SCOPE = "cart_"

local function cartOfScope(scope)
  if type(scope) ~= "string" then return nil end
  return scope:match("^cart_(.+)$")
end

local CacheContract = require("src.import.CacheContract")
local Transition = require("src.ui.kit.Transition")
local COMMUNITY_URL = "https://bois.icu"

local TAB_ORDER, TAB_AT = {}, {}
local function tabOrder()
  if #TAB_ORDER == 0 then
    for _, version in ipairs(GameVersion.ORDER) do
      TAB_ORDER[#TAB_ORDER + 1] = version
    end
    local okView, View = pcall(require, "src.import.LauncherView")
    if okView then
      for _, t in ipairs(View.HEADER_TABS or {}) do
        TAB_ORDER[#TAB_ORDER + 1] = t.id
      end
    end
    for i, id in ipairs(TAB_ORDER) do TAB_AT[id] = i end
  end
  return TAB_AT
end
local TRUST_WARNING = "if you did not get this from bryanthaboi's github " ..
  "or a link from the discord that bryanthaboi himself posted, just know " ..
  "it might have been tampered with. go to the discord to verify " ..
  COMMUNITY_URL .. " (or click the logo above)"
-- "Split-screen ROM selector" first-run palette (matches the FirstRun mockup):
-- a dark neon arcade panel, one column per game.
-- Red, Blue, and Yellow share the same importer flow once listed in
-- GameVersion.VERSIONS.  Values are 0-255 RGB; alpha is applied per draw.
local PAL = {
  -- radial background gradient (bright navy at top-centre -> near black)
  bgTop       = { 22, 34, 74 },   -- #16224a
  bgBot       = { 7, 11, 29 },    -- #070b1d
  -- neon accents, one per cartridge
  red         = { 255, 60, 72 },  -- rgb(255,60,72)
  blue        = { 70, 150, 255 }, -- rgb(70,150,255)
  gold        = { 255, 203, 5 },  -- rgb(255,203,5)
  -- card interiors (the dark colour the accent tint fades into)
  cardRed     = { 20, 12, 26 },   -- #140c1a
  cardBlue    = { 12, 18, 40 },   -- #0c1228
  cardGold    = { 30, 22, 8 },    -- #1e1608
  -- text
  heading     = { 255, 255, 255 },
  detail      = { 198, 208, 230 }, -- #c6d0e6
  warning     = { 159, 176, 208 }, -- #9fb0d0
  link        = { 127, 208, 255 }, -- #7fd0ff, the bois.icu link
  linkHover   = { 191, 234, 255 }, -- #bfeaff, brighter on hover
  white       = { 255, 255, 255 },
  -- "Play" button (green gradient) + its ink
  playTop     = { 62, 224, 138 }, -- #3ee08a
  playBot     = { 22, 163, 90 },  -- #16a35a
  playInk     = { 6, 32, 18 },    -- #062012
  -- "Choose ROM" button (red gradient)
  chooseTop   = { 255, 83, 97 },  -- #ff5361
  chooseBot   = { 214, 31, 44 },  -- #d61f2c
  -- disabled "Coming soon" button
  disabled    = { 120, 132, 158 },
  disabledInk = { 149, 161, 189 }, -- #95a1bd
  -- redesign (FirstRun.dc.html): tab chrome, cards, status pills
  green       = { 62, 224, 138 },  -- #3ee08a  "GOOD TO GO" / toggle-on / LOADED
  greenDark   = { 22, 163, 90 },   -- #16a35a
  labelGray   = { 143, 163, 200 }, -- #8fa3c8  letterspaced ROM / SAVE FILES labels
  cardBorder  = { 120, 150, 220 }, -- rgba(120,150,220,*) card + divider strokes
  slotBg      = { 9, 14, 34 },     -- rgba(9,14,34,0.6) save-slot row interior
  modDot      = { 159, 180, 221 }, -- #9fb4dd  MODS chip grid dots + underline
  -- tab-chip gradients (top -> bottom)
  chipRedTop  = { 255, 92, 103 },  -- #ff5c67
  chipRedBot  = { 181, 35, 42 },   -- #b5232a
  chipBlueTop = { 106, 168, 255 }, -- #6aa8ff
  chipBlueBot = { 30, 86, 168 },   -- #1e56a8
  chipGoldTop = { 255, 217, 74 },  -- #ffd94a
  chipGoldBot = { 199, 154, 0 },   -- #c79a00
  chipModTop  = { 61, 74, 109 },   -- #3d4a6d
  chipModBot  = { 32, 42, 69 },    -- #202a45
  chipInkGold = { 58, 44, 0 },     -- #3a2c00  dark "Y" on the gold chip
}

-- ------- ROM cache location
--
-- The extracted cache (data/generated, assets/generated) plus the
-- rom-cache.complete marker normally live in LÖVE's per-user OS save
-- directory.  A portable install instead keeps them in the game folder next
-- to the executable (the folder holding portable.txt), so nothing is left on
-- the host machine.  Every cache write/read/remove goes through CacheFs,
-- which writes that folder with io.* and makes it readable (mounting it via
-- PhysFS for a fused build) -- there is no mirror step and no per-file
-- os.execute (issue #74: that flashed a console window per file on Windows
-- and froze the app).

-- Remove a cache subtree from the OS save directory.  The realDirectory
-- guard keeps this from ever deleting the game folder (portable installs
-- read the cache from there) or a developer's checked-out source tree.
local function removeTree(path)
  local info = love.filesystem.getInfo(path)
  if not info then return end
  if info.type == "directory" then
    for _, child in ipairs(love.filesystem.getDirectoryItems(path)) do
      removeTree(path .. "/" .. child)
    end
  end
  if love.filesystem.getRealDirectory
      and love.filesystem.getRealDirectory(path)
        ~= love.filesystem.getSaveDirectory() then
    return
  end
  local ok, err = love.filesystem.remove(path)
  if ok == false then
    error("could not remove stale cache: " .. tostring(err))
  end
end

-- Portable installs read the cache from the game folder.  Any copy an
-- earlier non-portable run -- or the pre-#74 build, which always wrote the
-- cache to the save directory and only mirrored it out -- left behind would
-- shadow it, because physfs searches the save directory before the source.
-- Clear it out once, and only when a remnant is actually present so a clean
-- install pays nothing.
local saveDirPurged = false
local function purgeSaveDirCache()
  if saveDirPurged then return end
  saveDirPurged = true
  local saveDir = love.filesystem.getSaveDirectory()
  local function saveDirHas(rel)
    local f = io.open(saveDir .. "/" .. rel, "rb")
    if not f then return false end
    f:close()
    return true
  end
  -- Purge each version's stale save-directory copy (under its red/ / blue/
  -- / yellow/ / gold/ prefix) so it cannot shadow the portable game-folder cache.
  for _, version in ipairs(GameVersion.ORDER) do
    local prefix = GameVersion.cachePrefix(version)
    local required = CacheContract.requiredFilesFor(version)
    local hasRequired = false
    for _, path in ipairs(required) do
      if saveDirHas(prefix .. path) then hasRequired = true; break end
    end
    if saveDirHas(prefix .. CacheContract.MARKER_PATH) or hasRequired then
      removeTree(prefix .. "data/generated")
      removeTree(prefix .. "assets/generated")
      love.filesystem.remove(prefix .. CacheContract.MARKER_PATH)
    end
  end
end

-- Whether a given game version's ROM has already been imported and cached.
function RomImporter.isReady(version)
  version = version or "red"
  local CacheFs = require("src.import.CacheFs")
  if CacheFs.root() then
    -- Portable: the cache lives in the game folder next to the executable
    -- (mounted onto the read path for a fused build).  Drop any stale
    -- save-directory copy that would otherwise shadow it at runtime.
    purgeSaveDirCache()
  end
  return CacheContract.isReady(version, CacheFs)
end

function RomImporter.syncAndroidShortcuts(activeVersion)
  if not (love.system and love.system.getOS and love.system.getOS() == "Android"
      and love.system.updateShortcuts) then
    return false
  end

  local allVersions = GameVersion.ORDER
  local ready = {}
  local seen = {}

  if activeVersion and RomImporter.isReady(activeVersion) then
    table.insert(ready, activeVersion)
    seen[activeVersion] = true
  end

  for _, v in ipairs(allVersions) do
    if not seen[v] and RomImporter.isReady(v) then
      table.insert(ready, v)
      seen[v] = true
      if #ready >= 4 then break end
    end
  end

  return love.system.updateShortcuts(ready)
end

-- Load the import manifest for a version and confirm it matches that ROM.
local function sha1(data)
  local digest = love.data.hash("sha1", data)
  if type(digest) == "userdata" and digest.getString then
    digest = digest:getString()
  end
  return love.data.encode("string", "hex", digest)
end

local function readExternalPath(path)
  local file, openError = io.open(path, "rb")
  if not file then return nil, openError end
  local data = file:read("*a")
  file:close()
  return data
end

local function externalFileSize(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local size = file:seek("end")
  file:close()
  return size
end

local function openImportSource(path)
  -- Desktop picker paths live outside LÖVE's virtual filesystem. Prefer the
  -- native file handle so a 1.46 GiB disc is never copied to a temp file or
  -- read into one Lua string before validation.
  local native = io.open(path, "rb")
  if native then
    local size, sizeErr = native:seek("end")
    if size == nil or size == false then
      native:close()
      return nil, sizeErr or "could not determine source file size"
    end
    local reset, resetErr = native:seek("set", 0)
    if reset == nil or reset == false then
      native:close()
      return nil, resetErr or "could not rewind source file"
    end
    return {
      size = size,
      read = function(_, n) return native:read(n) end,
      close = function() native:close() end,
    }
  end
  if love and love.filesystem and love.filesystem.newFile then
    local file, makeErr = love.filesystem.newFile(path)
    if not file then return nil, makeErr or "could not open source file" end
    local ok, openErr = file:open("r")
    if not ok then return nil, openErr or "could not open source file" end
    local size = file.getSize and file:getSize() or nil
    return {
      size = size,
      read = function(_, n) return file:read(n) end,
      close = function() file:close() end,
    }
  end
  return nil, "streaming source access is unavailable"
end
local function streamRequiredImport(manifest, importId, source)
  local RequiredImports = require("src.mods.RequiredImports")
  local spec = RequiredImports.spec(manifest, importId)
  if not spec then return nil, "Import declaration was not found." end
  if spec.format == "n64" then
    return nil, "streaming canonicalization is unavailable for N64 imports"
  end
  local input, openErr = openImportSource(source)
  if not input then return nil, openErr end
  local sizeErr = RequiredImports.sizeError(spec, input.size, false)
  if sizeErr then input:close(); return nil, sizeErr end

  local CacheFs = require("src.import.CacheFs")
  local destination = RequiredImports.path(manifest, spec)
  local savedPrefix = CacheFs.prefix
  local output
  local inputClosed, outputClosed = false, false

  local function closeInput()
    if inputClosed then return end
    inputClosed = true
    pcall(function() input:close() end)
  end

  local function closeOutput()
    if outputClosed or not output then return end
    outputClosed = true
    pcall(function() output:close() end)
  end

  local resultOk, resultDetail
  CacheFs.prefix = ""
  local ran, thrown = xpcall(function()
    CacheFs.remove(RequiredImports.receiptPath(manifest, spec))
    CacheFs.remove(destination)
    local makeErr
    output, makeErr = CacheFs.openWrite(destination)
    if not output then
      resultDetail = makeErr or "could not create imported file"
      return
    end

    local MD5 = require("src.mods.StreamMD5")
    local md5 = MD5.new()
    local total, chunkBytes = 0, 4 * 1024 * 1024
    while true do
      local chunk = input:read(chunkBytes)
      if not chunk or #chunk == 0 then break end
      md5:update(chunk)
      local wrote, writeErr = output:write(chunk)
      if wrote == false or wrote == nil then
        resultDetail = "could not copy import: "
.. tostring(writeErr or "write failed")
        return
      end
      total = total + #chunk
      if #chunk < chunkBytes then break end
    end

    closeInput()
    closeOutput()
    if input.size and total ~= input.size then
      resultDetail = ("source read ended early (expected %d bytes, copied %d)")
        :format(input.size, total)
      return
    end
    local storedSizeErr = RequiredImports.sizeError(spec, total, true)
    if storedSizeErr then resultDetail = storedSizeErr; return end
    local digest = md5:final()

    -- acceptStoredDigest uses the normal engine path/receipt rules, so
    -- restore the caller's prefix before handing control to it.
    CacheFs.prefix = savedPrefix
    local accepted, detail = RequiredImports.acceptStoredDigest(
      manifest, importId, digest, love.filesystem)
    if not accepted then resultDetail = detail; return end
    resultOk, resultDetail = true, detail
  end, function(err)
    if debug and debug.traceback then
      return debug.traceback(tostring(err), 2)
    end
    return tostring(err)
  end)

  -- finally: resource handles and the process-global CacheFs prefix must
  -- be restored even when a read/hash/write helper raises a Lua error.
  closeInput()
  closeOutput()
  CacheFs.prefix = ""
  if not ran or not resultOk then
    pcall(function() CacheFs.remove(destination) end)
  end
  CacheFs.prefix = savedPrefix

  if not ran then
    return nil, "could not copy import: " .. tostring(thrown)
  end
  if not resultOk then return nil, resultDetail end
  return true, resultDetail
end
local function readDroppedFile(file)
  local ok, openError = file:open("r")
  if not ok then return nil, openError end
  local data, readError = file:read(file:getSize())
  file:close()
  return data, readError
end

local function trim(value)
  return value and value:gsub("^%s+", ""):gsub("%s+$", "") or ""
end

-- Turn a filesystem path into a well-formed file:// URI for love.system.openURL.
-- openURL feeds SDL_OpenURL, whose macOS backend ([NSURL URLWithString:]) returns
-- nil for any unencoded space -- and the default save dir lives under
-- "Application Support" -- so the click silently no-ops on real macOS installs.
-- Windows needs forward slashes and a leading slash on the drive path so the
-- authority is empty (file:///C:/...), not a hostname.  Percent-encode the rest
-- (spaces -> %20) but keep the unreserved set plus "/" and ":" (drive letter and
-- path separators stay literal so the shell resolves the folder).
local function fileUrl(path)
  path = tostring(path):gsub("\\", "/")
  if path:sub(1, 1) ~= "/" then path = "/" .. path end
  local encoded = path:gsub("[^%w%-%._~/:]", function(c)
    return string.format("%%%02X", string.byte(c))
  end)
  return "file://" .. encoded
end

-- The native pickers below block the whole loop inside io.popen, and they are
-- opened straight out of mousepressed -- with the button still physically
-- down.  SDL auto-captures the pointer for the length of a press (on X11 an
-- XGrabPointer with owner_events) and only drops that capture when it
-- processes the matching button-up, which it cannot do while we sit in popen
-- and never pump.  The grab then outlives the click and every pointer event
-- over the file chooser is still routed to our window: the dialog draws and
-- keyboard-navigates (keyboard focus is a separate grab) but ignores the
-- mouse entirely -- issue #254 on Linux.  Whether it bites is a race with how
-- long the click was held, which is why the same build picks one ROM fine and
-- then hangs the mouse on the next.
--
-- The release itself now lives in HostShell.releasePointerGrab, called from
-- HostShell.popen, so every host spawn inherits it and not just the three
-- pickers here.  It stays a single release point on purpose: this file used
-- to run its own copy first, and each copy carries its own one-second bound,
-- so keeping both made a stuck button cost two seconds instead of one.

local function commandOutput(command)
  if not Platform.canSpawnProcess() then return nil end
  local pipe = HostShell.popen(command)
  if not pipe then return nil end
  local result = pipe:read("*a")
  -- HostShell.pclose, never pipe:close(): closing a pipe outside the spawn
  -- lock can free a FILE while a worker thread's popen is walking the stream
  -- list, which deadlocks that thread for good (see HostShell).
  HostShell.pclose(pipe)
  HostShell.pumpHostEvents()
  result = trim(result)
  return result ~= "" and result or nil
end

local IMPORTS_DIR = "imports"
local BASE_ROMS_DIR = "baseroms"
local MODS_INBOX_DIR = "imports/mods"
local SAVES_INBOX_DIR = "imports/saves"
local ROM_BYTES_GEN1 = 1024 * 1024
local ROM_BYTES_GEN2 = 2 * 1024 * 1024
-- Historical alias: Gen 1 helpers and tests still refer to ROM_BYTES.
local ROM_BYTES = ROM_BYTES_GEN1

local function isAcceptedRomSize(n)
  return n == ROM_BYTES_GEN1 or n == ROM_BYTES_GEN2
end

local function cartLabels(generation)
  local out = {}
  for _, id in ipairs(GameVersion.ORDER) do
    if generation == nil or GameVersion.generation(id) == generation then
      out[#out + 1] = GameVersion.info(id).label
    end
  end
  return out
end

local function cartsSlashed(generation)
  return table.concat(cartLabels(generation), "/")
end

local function cartsProse()
  local names = cartLabels(nil)
  local last = table.remove(names)
  if #names == 0 then return last end
  return table.concat(names, ", ") .. ", or " .. last
end

local function savesInboxDir(version)
  return SAVES_INBOX_DIR .. "/" .. tostring(version)
end

local function savesImportedHashesPath(version)
  return savesInboxDir(version) .. "/.imported-sha1"
end

local function exportsDir(version)
  return "exports/" .. tostring(version)
end

-- Strip only a validated sdmc:/ prefix for OpenMTP/DBI relative paths.
function RomImporter.mtpHintPath(saveDir)
  if type(saveDir) ~= "string" then return "" end
  if saveDir:sub(1, 6) == "sdmc:/" then return saveDir:sub(7) end
  return saveDir
end

function RomImporter:ensureImportsDir()
  local info = love.filesystem.getInfo(IMPORTS_DIR)
  if info and info.type == "directory" then return true end
  if info then return false end
  if love.filesystem.createDirectory then
    return love.filesystem.createDirectory(IMPORTS_DIR)
  end
  return false
end

-- NX mod zip inbox (separate from ROM imports/). Parent imports/ first --
-- love.filesystem.createDirectory does not create nested parents.
function RomImporter:ensureModsInboxDir()
  self:ensureImportsDir()
  local info = love.filesystem.getInfo(MODS_INBOX_DIR)
  if info and info.type == "directory" then return true end
  if info then return false end
  if love.filesystem.createDirectory then
    return love.filesystem.createDirectory(MODS_INBOX_DIR)
  end
  return false
end

-- NX raw .sav inbox per game: imports/saves/{red,blue,yellow}/.
-- Parent imports/ then imports/saves/ first -- createDirectory is not nested.
-- Creates all three version folders so MTP browsing shows where each game goes.
function RomImporter:ensureSavesInboxDir(version)
  self:ensureImportsDir()
  local info = love.filesystem.getInfo(SAVES_INBOX_DIR)
  if info and info.type ~= "directory" then return false end
  if not info then
    if not (love.filesystem.createDirectory
        and love.filesystem.createDirectory(SAVES_INBOX_DIR)) then
      return false
    end
  end
  for v in pairs(GameVersion.VERSIONS) do
    local dir = savesInboxDir(v)
    local vInfo = love.filesystem.getInfo(dir)
    if vInfo and vInfo.type ~= "directory" then return false end
    if not vInfo then
      if not (love.filesystem.createDirectory
          and love.filesystem.createDirectory(dir)) then
        return false
      end
    end
  end
  return true
end

function RomImporter:_setNxInboxNotice(version)
  version = version or self.tab or "red"
  local saveDir = love.filesystem.getSaveDirectory()
  local rel = RomImporter.mtpHintPath(saveDir)
  if rel ~= "" and rel:sub(-1) ~= "/" then rel = rel .. "/" end
  self.notice = {
    version = version,
    status = Strings("Copy your .gb/.gbc into:"),
    detail = Strings("%s/imports/\nDBI MTP → 1: SD Card/%simports/", saveDir, rel),
  }
end

function RomImporter:_setNxModsInboxNotice()
  local saveDir = love.filesystem.getSaveDirectory()
  local rel = RomImporter.mtpHintPath(saveDir)
  if rel ~= "" and rel:sub(-1) ~= "/" then rel = rel .. "/" end
  self.modNotice = {
    ok = true,
    text = Strings("Copy your .zip into:\n%s/imports/mods/\nDBI MTP → 1: SD Card/%simports/mods/",
      saveDir, rel),
  }
end

function RomImporter:_resolveSaveVersion(version)
  version = version or self.panelVersion or self.tab
  if GameVersion.VERSIONS[version] then return version end
  return self:_savedropTarget()
end

function RomImporter:_setNxSavesInboxNotice(version)
  version = self:_resolveSaveVersion(version)
  local inbox = savesInboxDir(version)
  local saveDir = love.filesystem.getSaveDirectory()
  local rel = RomImporter.mtpHintPath(saveDir)
  if rel ~= "" and rel:sub(-1) ~= "/" then rel = rel .. "/" end
  local game = GameVersion.info(version).displayName
  self.saveNotice = self.saveNotice or {}
  self.saveNotice[version] = {
    ok = true,
    text = Strings("Copy your %s .sav into:\n%s/%s/\nDBI MTP → 1: SD Card/%s%s/",
      game, saveDir, inbox, rel, inbox),
  }
end

local function listRomPaths(dir)
  local paths = {}
  for _, name in ipairs(love.filesystem.getDirectoryItems(dir) or {}) do
    -- Skip AppleDouble / hidden junk from Mac MTP (._cart.gb ends in .gb
    -- but is not a ROM -- rescan would try it first and block the real dump).
    if name:sub(1, 1) ~= "." then
      local path = (dir == "" or dir == "/") and name or (dir .. "/" .. name)
      if name:lower():match("%.gbc?$")
          and love.filesystem.getInfo(path, "file") then
        paths[#paths + 1] = path
      end
    end
  end
  return paths
end

local function baseRomScanSatisfied(self)
  for _, version in ipairs(GameVersion.ORDER) do
    if not self.ready[version] and not self.baseRoms[version] then
      return false
    end
  end
  return true
end

function RomImporter:_queueBaseRomScan()
  if not self.baseRomDiscovery then return end
  if baseRomScanSatisfied(self) then
    self.baseRomScan = { state = "done" }
    return
  end
  self.baseRomScan = { state = "queued", index = 1 }
end

function RomImporter:_stepBaseRomScan()
  local scan = self.baseRomScan
  if not scan or scan.state == "done" or self.workState == "working" then
    return
  end
  if scan.state == "queued" then
    local info = love.filesystem.getInfo(BASE_ROMS_DIR)
    if not info and love.filesystem.createDirectory then
      love.filesystem.createDirectory(BASE_ROMS_DIR)
    end
    scan.paths = listRomPaths(BASE_ROMS_DIR)
    table.sort(scan.paths)
    scan.state = "running"
  end

  local path = scan.paths[scan.index]
  if not path then
    scan.state = "done"
    return
  end
  scan.index = scan.index + 1

  local info = love.filesystem.getInfo(path, "file")
  if info and isAcceptedRomSize(info.size) then
    local data = love.filesystem.read(path)
    if type(data) == "string" and isAcceptedRomSize(#data) then
      local version = GameVersion.forSha1(sha1(data))
      if version and not self.ready[version] and not self.baseRoms[version] then
        self.baseRoms[version] = {
          path = path,
          name = path:match("[^/\\]+$") or path,
        }
      end
    end
  end

  if baseRomScanSatisfied(self) or not scan.paths[scan.index] then
    scan.state = "done"
  end
end

local function listZipPaths(dir)
  local paths = {}
  for _, name in ipairs(love.filesystem.getDirectoryItems(dir) or {}) do
    -- Skip AppleDouble / hidden junk from Mac MTP (._foo.zip ends in .zip
    -- but is not a PhysFS archive -- mount fails with "could not be opened").
    if name:sub(1, 1) ~= "." then
      local path = (dir == "" or dir == "/") and name or (dir .. "/" .. name)
      if name:lower():match("%.zip$")
          and love.filesystem.getInfo(path, "file") then
        paths[#paths + 1] = path
      end
    end
  end
  return paths
end

local function listSavPaths(dir)
  local paths = {}
  for _, name in ipairs(love.filesystem.getDirectoryItems(dir) or {}) do
    -- Skip AppleDouble / hidden junk from Mac MTP (._foo.sav ends in .sav
    -- but is not a real battery save -- import would fail and invent noise).
    if name:sub(1, 1) ~= "." then
      local path = (dir == "" or dir == "/") and name or (dir .. "/" .. name)
      if name:lower():match("%.sav$")
          and love.filesystem.getInfo(path, "file") then
        paths[#paths + 1] = path
      end
    end
  end
  return paths
end

function RomImporter:scanInbox()
  local paths = {}
  for _, path in ipairs(listRomPaths(IMPORTS_DIR)) do
    paths[#paths + 1] = path
  end
  for _, path in ipairs(listRomPaths("")) do
  -- Root scan is second; imports/ entries were already collected above.
    paths[#paths + 1] = path
  end
  return paths
end

-- NX mods inbox: only *.zip under imports/mods/ (never ROM extensions).
function RomImporter:scanModsInbox()
  self:ensureModsInboxDir()
  return listZipPaths(MODS_INBOX_DIR)
end

-- NX saves inbox: only non-hidden *.sav under imports/saves/<version>/.
function RomImporter:scanSavesInbox(version)
  version = self:_resolveSaveVersion(version)
  self:ensureSavesInboxDir(version)
  return listSavPaths(savesInboxDir(version))
end

local function loadImportedSavHashes(version)
  local set = {}
  local raw = love.filesystem.read(savesImportedHashesPath(version))
  if type(raw) ~= "string" then return set end
  for line in raw:gmatch("[^\r\n]+") do
    local h = line:match("^(%x+)$")
    if h then set[h] = true end
  end
  return set
end

local function appendImportedSavHash(version, hash)
  if type(hash) ~= "string" or hash == "" then return end
  local path = savesImportedHashesPath(version)
  local prev = love.filesystem.read(path) or ""
  if prev:find(hash, 1, true) then return end
  love.filesystem.write(path, prev .. hash .. string.char(10))
end

-- Keep bytes for the player (MTP recovery) but stop matching %.sav$ on rescan.
local function retireImportedSav(path)
  if type(path) ~= "string" or path == "" then return false end
  local data = love.filesystem.read(path)
  if type(data) ~= "string" then return false end
  local dest = path .. ".imported"
  if love.filesystem.getInfo(dest) then
    dest = path .. ".imported." .. tostring(os.time())
  end
  if not love.filesystem.write(dest, data) then return false end
  love.filesystem.remove(path)
  return true
end

-- Rescan imports/mods/: install each .zip via _installMod / installZip.
-- Never deletes inbox zips (success or failure). Empty inbox → MTP notice.
function RomImporter:rescanModsAction()
  if self.workState == "working" then return end
  self.tab = "mods"
  self:ensureModsInboxDir()
  local candidates = self:scanModsInbox()
  if #candidates == 0 then
    self:_setNxModsInboxNotice()
    return
  end
  local anyOk = false
  local lastOk = nil
  local lastFail = nil
  local failCount = 0
  for _, path in ipairs(candidates) do
    -- Reuse _installMod carefully: it must not remove the inbox source.
    self:_installMod(path)
    if self.modNotice and self.modNotice.ok then
      anyOk = true
      lastOk = self.modNotice
    else
      failCount = failCount + 1
      lastFail = self.modNotice
    end
  end
  -- Success wins overall ok=true so a leftover MTP junk sibling cannot hide
  -- a good install; still append the last failure so a real broken zip is
  -- visible beside the success line.
  if anyOk and lastFail then
    local okText = (lastOk and lastOk.text) or "Installed"
    local failText = (lastFail and lastFail.text) or "unknown error"
    self.modNotice = {
      ok = true,
      text = Strings("%s\n(%d failed: %s)", okText, failCount, failText),
    }
  elseif anyOk then
    self.modNotice = lastOk
  elseif lastFail then
    self.modNotice = lastFail
  end
end

-- Rescan imports/saves/<version>/: import each new .sav via _importSave.
-- Failure retains the original .sav. Success records a per-game content hash
-- and retires the file to `*.sav.imported` so a second Import save cannot clone
-- slots (bytes stay in the inbox for MTP recovery). Already-hashed content
-- is skipped even under a new filename. Empty / AppleDouble-only → MTP notice.
function RomImporter:rescanSavesAction(version)
  if self.workState == "working" then return end
  version = self:_resolveSaveVersion(version)
  self:ensureSavesInboxDir(version)
  local candidates = self:scanSavesInbox(version)
  if #candidates == 0 then
    self:_setNxSavesInboxNotice(version)
    return
  end
  local seenHashes = loadImportedSavHashes(version)
  local okCount, failCount, skipCount = 0, 0, 0
  local lastOk, lastFail = nil, nil
  local gameLabel = GameVersion.info(version).displayName
  for _, path in ipairs(candidates) do
    local data = love.filesystem.read(path)
    local hash = (type(data) == "string" and data ~= "") and sha1(data) or nil
    if hash and seenHashes[hash] then
      skipCount = skipCount + 1
      -- Leftover live .sav after a prior success: retire without re-importing.
      retireImportedSav(path)
    else
      self:_importSave(version, path)
      local notice = self.saveNotice and self.saveNotice[version]
      if notice and notice.ok then
        okCount = okCount + 1
        lastOk = notice
        if hash then
          seenHashes[hash] = true
          appendImportedSavHash(version, hash)
        end
        retireImportedSav(path)
      else
        failCount = failCount + 1
        lastFail = notice
      end
    end
  end
  if okCount > 0 then
    local okText
    if okCount == 1 and lastOk then
      okText = Strings("%s (%s tab)", lastOk.text, gameLabel)
    else
      okText = Strings("Imported %d saves into %s. Active: %s.",
        okCount, gameLabel, tostring(self.activeSlot[version]))
    end
    if failCount > 0 then
      local failText = (lastFail and lastFail.text) or "unknown error"
      okText = Strings("%s\n(%d failed: %s)", okText, failCount, failText)
    end
    if skipCount > 0 then
      okText = Strings("%s\n(%d already imported, skipped)", okText, skipCount)
    end
    self.saveNotice[version] = { ok = true, text = okText }
  elseif failCount > 0 then
    self.saveNotice[version] = lastFail
  elseif skipCount > 0 then
    self.saveNotice[version] = {
      ok = true,
      text = Strings("Already imported: %d file(s) skipped. Check SAVE SLOT.",
        skipCount),
    }
  end
end

-- NX "Scan again" on a game tab: import only the dump whose SHA-1 matches
-- that tab. A shared imports/ inbox often holds Red+Blue+Yellow at once;
-- picking the first pending file would jump Yellow → Red (and switch the
-- launcher tab via startData). Other known dumps stay for their own tabs.
-- Junk (wrong size / unknown hash) still surfaces when nothing matches the
-- tab and no other known dump is present -- same feedback as before for a
-- lone bad file.
function RomImporter:rescanAction(version)
  if self.workState == "working" then return end
  version = version or self.tab or "red"
  self.chooseVersion = version
  self:ensureImportsDir()
  local ready = self.ready
  local candidates = self:scanInbox()
  local targetReady = false
  local sawOtherVersion = false
  local junkData, junkName = nil, nil
  for _, path in ipairs(candidates) do
    local data = love.filesystem.read(path)
    local displayName = path:match("[^/\\]+$") or path
    if type(data) ~= "string" then
      self:setError("The file could not be read: " .. displayName, version)
      return
    end
    if not isAcceptedRomSize(#data) then
      if not junkData then junkData, junkName = data, displayName end
    else
      local romVersion = GameVersion.forSha1(sha1(data))
      if not romVersion then
        if not junkData then junkData, junkName = data, displayName end
      elseif romVersion ~= version then
        sawOtherVersion = true
      elseif ready[romVersion] then
        targetReady = true
      else
        self:startData(data, displayName)
        return
      end
    end
  end
  if targetReady then
    self.notice = {
      version = version,
      status = Strings("No new ROM found."),
      detail = Strings("Already-imported dumps are ignored. Add another version or "
        .. "delete the copy when finished."),
    }
    return
  end
  if junkData and not sawOtherVersion then
    self:startData(junkData, junkName)
    return
  end
  if #candidates > 0 then
    local label = GameVersion.info(version).displayName
    self.notice = {
      version = version,
      status = Strings("No matching ROM found."),
      detail = Strings(
        "%s is matched by SHA-1 on this tab. Other dumps in imports/ stay "
          .. "for their own tabs; open that game and Scan again.", label),
    }
    return
  end
  self:_setNxInboxNotice(version)
end

function RomImporter:_romAction(version)
  if self.isNX then
    if self.ready[version] then self:reimport(version)
    else self:rescanAction(version) end
  elseif self.ready[version] then self:reimport(version)
  else self:choose(version) end
end

-- Sanitize a string before it is interpolated into a picker shell command:
--   * "%" would be eaten as a string.format directive (#665);
--   * '"' would break the AppleScript / zenity double-quoted argument and
--     "'" the surrounding single-quoted shell string.
local function shellSafe(s)
  s = tostring(s):gsub("%%", "%%%%")
  return s:gsub('"', '\\"'):gsub("'", "''")
end

-- LOVE 11.5 on Android has no native file picker (love.window.showFileDialog
-- is a LOVE 12 nightly-only addition) and never fires love.filedropped, so
-- neither desktop path below works there. conf.lua points the Android save
-- directory at the app's external-files folder instead (readable/writable
-- via USB or a file manager, no runtime permission needed), and this scans
-- it directly through love.filesystem -- already mounted at the physfs
-- root, so no io.* absolute-path handling is needed.
--
-- Only a .gb/.gbc whose SHA maps to a version that is not yet ready counts as
-- pending.  GameActivity always writes the SAF pick to picked_rom.gb, so a
-- naive "first ROM wins" scan would re-import Red when the player tries to
-- add Blue (issue #167).  Yellow and Gold carts are typically .gbc (Gold is
-- 2 MiB).
-- `wanted` narrows the scan to one version.  A Choose names the cart it is
-- for, so without it several dumps sitting in the save directory answered in
-- listing order and the selection was dropped: picking Red imported Blue
-- (#1274).  The callers that are not a Choose, the Android USB-drop scans,
-- pass nothing and still take the first pending cart of any version.
local function findPendingRom(ready, wanted)
  for _, name in ipairs(love.filesystem.getDirectoryItems("")) do
    if name:lower():match("%.gbc?$") and love.filesystem.getInfo(name, "file") then
      local data = love.filesystem.read(name)
      if type(data) == "string" and isAcceptedRomSize(#data) then
        local version = GameVersion.forSha1(sha1(data))
        if version and not ready[version]
            and (wanted == nil or version == wanted) then
          return name, data
        end
      end
    end
  end
  return nil
end

local function importPendingRom(self)
  local name, data = findPendingRom(self.ready, self.chooseVersion)
  if not name then return false end
  self:startData(data, name)
  return true
end

-- GameActivity always writes the SAF pick to picked_rom.gb, so a leftover
-- under that exact basename is the file the player just chose and
-- findPendingRom silently refused: wrong size, or a hacked/overdumped cart
-- whose SHA-1 matches no known version ([b]/[BF] dumps never will).  Route it
-- through startData so the launcher says which of the two it was instead of
-- staying on "No ROM imported" with no message at all (issue #442), and drop
-- the file so the next tap starts from a clean slate.  A cart that is simply
-- already imported is not an error -- #167 skips it on purpose -- so leave
-- that one alone.
local function consumePickedRomError(self)
  local preferred = "picked_rom.gb"
  if not love.filesystem.getInfo(preferred, "file") then return false end
  local data = love.filesystem.read(preferred)
  if type(data) == "string" and isAcceptedRomSize(#data) then
    local version = GameVersion.forSha1(sha1(data))
    if version and self.ready[version] then return false end
  end
  love.filesystem.remove(preferred)
  if type(data) ~= "string" then
    self:setError("The picked file could not be read. Reopen the picker and "
      .. "choose the ROM with the Files (Documents) app.")
    return true
  end
  self:startData(data, preferred)
  return true
end

-- Android SAF writes mod picks to picked_mod.zip; USB copies may use any
-- .zip basename at the save-dir root.  preferAny=true also accepts those USB
-- copies (Choose / Import); focus only consumes the SAF basename so a random
-- leftover archive is never auto-installed on every refocus.
local function findPendingMod(preferAny, skip)
  local preferred = "picked_mod.zip"
  if love.filesystem.getInfo(preferred, "file") then
    return preferred
  end
  if not preferAny then return nil end
  for _, name in ipairs(love.filesystem.getDirectoryItems("")) do
    if name:lower():match("%.zip$") and not (skip and skip[name])
        and love.filesystem.getInfo(name, "file") then
      return name
    end
  end
  return nil
end

-- Same pattern as findPendingMod for battery saves (picked_save.sav / *.sav).
local function findPendingSav(preferAny, skip)
  local preferred = "picked_save.sav"
  if love.filesystem.getInfo(preferred, "file") then
    return preferred
  end
  if not preferAny then return nil end
  for _, name in ipairs(love.filesystem.getDirectoryItems("")) do
    if name:lower():match("%.sav$") and not (skip and skip[name])
        and love.filesystem.getInfo(name, "file") then
      return name
    end
  end
  return nil
end

local function pickerHasKind(kind)
  local fn = love.system.pickFileKinds
  if type(fn) ~= "function" then return false end
  local ok, kinds = pcall(fn)
  if not ok or type(kinds) ~= "string" then return false end
  for token in kinds:gmatch("[^,%s]+") do
    if token == kind then return true end
  end
  return false
end

local function findPendingRequiredImport(self)
  local names = { "picked_required_import.bin", "picked_stadium.z64" }
  -- Builds released before required_import was added to the Android JNI bridge
  -- only understand the long-standing "rom" picker kind.  While a required
  -- import request is in flight, it is safe to treat its staging name as a
  -- dependency file: the pending IDs below select the same validation/copy
  -- path as a current bridge.  Never scan picked_rom.gb otherwise, since that
  -- remains reserved for an ordinary game-ROM import.
  if self and self.requiredImportLegacyRomPick
      and self.pickerPendingKind == "required_import" then
    names[#names + 1] = "picked_rom.gb"
  end
  for _, name in ipairs(names) do
    if love.filesystem.getInfo(name, "file") then return name end
  end
  return nil
end

-- Retire an Android pick once it has been through the installer / importer,
-- whether or not it worked: a pick left on disk wins the scans above forever,
-- so the next tap re-runs the same failing file and the picker never reopens
-- (#420).  The SAF basename is GameActivity's own copy of the pick and is
-- always deleted; a USB copy is the player's file, so a failed one is only
-- skipped for the rest of the session.
local function consumePick(self, name, safName, ok)
  if ok or name == safName then
    love.filesystem.remove(name)
    return
  end
  self.pickSkip = self.pickSkip or {}
  self.pickSkip[name] = true
end

local function chooseRom(promptName)
  promptName = promptName or "Pokemon"
  local prompt = shellSafe("Choose your " .. promptName .. " ROM")
  local platform = love.system.getOS()
  if platform == "OS X" then
    return commandOutput(
      ([[osascript -e 'POSIX path of (choose file with prompt "%s" of type {"gb", "gbc"})' 2>/dev/null]])
        :format(prompt))
  elseif platform == "Windows" then
    local script = table.concat({
      "Add-Type -AssemblyName System.Windows.Forms;",
      "$d=New-Object System.Windows.Forms.OpenFileDialog;",
      "$d.Title='" .. prompt .. "';",
      "$d.Filter='Game Boy ROM (*.gb;*.gbc)|*.gb;*.gbc|All files (*.*)|*.*';",
      -- copy the pick to a plain-ASCII temp name and answer with that:
      -- the console's OEM codepage would mangle a non-ASCII path
      -- (Pokémon -> Pok\x82mon) and io.open on Windows needs ANSI bytes,
      -- so returning the original name both crashed the notice draw and
      -- could never have opened the file (#325, #665)
      "if($d.ShowDialog() -eq 'OK'){",
      "$t=Join-Path $env:TEMP 'pokeport_rom_pick.gb';",
      "Copy-Item -LiteralPath $d.FileName -Destination $t -Force;",
      "[Console]::OutputEncoding=[Text.Encoding]::UTF8;",
      "[Console]::Write($t)}",
    })
    return commandOutput(
      'powershell -NoProfile -STA -Command "' .. script .. '"')
  elseif platform == "Linux" then
    local path = commandOutput(
      ([[zenity --file-selection --title="%s" --file-filter="Game Boy ROM | *.gb *.gbc" 2>/dev/null]])
        :format(prompt))
    if path then return path end
    return commandOutput(
      [[kdialog --getopenfilename "$HOME" "*.gb *.gbc|Game Boy ROM" 2>/dev/null]])
  end
  return nil
end

-- Open a native picker for a mod .zip (mirrors chooseRom's per-OS dialogs).
-- Returns the chosen absolute path or nil.  Android uses love.system.pickFile
-- ("mod") instead -- see RomImporter:chooseMod.
local function chooseZip()
  local prompt = shellSafe(Strings("Choose a mod .zip"))
  local platform = love.system.getOS()
  if platform == "OS X" then
    return commandOutput(
      ([[osascript -e 'POSIX path of (choose file with prompt "%s" of type {"zip"})' 2>/dev/null]])
        :format(prompt))
  elseif platform == "Windows" then
    local script = table.concat({
      "Add-Type -AssemblyName System.Windows.Forms;",
      "$d=New-Object System.Windows.Forms.OpenFileDialog;",
      "$d.Title='" .. prompt .. "';",
      "$d.Filter='Mod archive (*.zip)|*.zip|All files (*.*)|*.*';",
      -- copy the pick to a plain-ASCII temp name and answer with that:
      -- the console's OEM codepage would mangle a non-ASCII path
      -- (Pokémon -> Pok\x82mon) and io.open on Windows needs ANSI bytes,
      -- so returning the original name both crashed the notice draw and
      -- could never have opened the file (#325)
      "if($d.ShowDialog() -eq 'OK'){",
      "$t=Join-Path $env:TEMP 'pokeport_mod_pick.zip';",
      "Copy-Item -LiteralPath $d.FileName -Destination $t -Force;",
      "[Console]::OutputEncoding=[Text.Encoding]::UTF8;",
      "[Console]::Write($t)}",
    })
    return commandOutput(
      'powershell -NoProfile -STA -Command "' .. script .. '"')
  elseif platform == "Linux" then
    local path = commandOutput(
      ([[zenity --file-selection --title="%s" --file-filter="Mod archive | *.zip" 2>/dev/null]])
        :format(prompt))
    if path then return path end
    return commandOutput(
      [[kdialog --getopenfilename "$HOME" "*.zip|Mod archive" 2>/dev/null]])
  end
  return nil
end

local function chooseSkinZip()
  local prompt = shellSafe(Strings("Choose a skin .zip or .deltaskin"))
  local platform = love.system.getOS()
  if platform == "OS X" then
    return commandOutput(
      ([[osascript -e 'POSIX path of (choose file with prompt "%s" of type {"zip", "deltaskin"})' 2>/dev/null]])
        :format(prompt))
  elseif platform == "Windows" then
    local script = table.concat({
      "Add-Type -AssemblyName System.Windows.Forms;",
      "$d=New-Object System.Windows.Forms.OpenFileDialog;",
      "$d.Title='" .. prompt .. "';",
      "$d.Filter='Skin archive (*.zip;*.deltaskin)|*.zip;*.deltaskin|All files (*.*)|*.*';",
      "if($d.ShowDialog() -eq 'OK'){",
      "$n=[IO.Path]::GetFileName($d.FileName) -replace '[^\\x20-\\x7E]','_';",
      "$t=Join-Path $env:TEMP $n;",
      "Copy-Item -LiteralPath $d.FileName -Destination $t -Force;",
      "[Console]::OutputEncoding=[Text.Encoding]::UTF8;",
      "[Console]::Write($t)}",
    })
    return commandOutput(
      'powershell -NoProfile -STA -Command "' .. script .. '"')
  elseif platform == "Linux" then
    local path = commandOutput(
      ([[zenity --file-selection --title="%s" --file-filter="Skin archive | *.zip *.deltaskin" 2>/dev/null]])
        :format(prompt))
    if path then return path end
    return commandOutput(
      [[kdialog --getopenfilename "$HOME" "*.zip *.deltaskin|Skin archive" 2>/dev/null]])
  end
  return nil
end

-- Open a native picker for a raw .sav battery save (mirrors chooseZip's per-OS
-- dialogs).  Returns the chosen absolute path or nil.  Android uses
-- love.system.pickFile("sav") instead -- see RomImporter:chooseSaveImport.
local function chooseSav()
  local prompt = shellSafe(Strings("Choose a .sav save file"))
  local platform = love.system.getOS()
  if platform == "OS X" then
    return commandOutput(
      ([[osascript -e 'POSIX path of (choose file with prompt "%s" of type {"sav"})' 2>/dev/null]])
        :format(prompt))
  elseif platform == "Windows" then
    local script = table.concat({
      "Add-Type -AssemblyName System.Windows.Forms;",
      "$d=New-Object System.Windows.Forms.OpenFileDialog;",
      "$d.Title='" .. prompt .. "';",
      "$d.Filter='Game Boy save (*.sav)|*.sav|All files (*.*)|*.*';",
      -- copy the pick to a plain-ASCII temp name: io.open on Windows
      -- needs ANSI bytes, so a non-ASCII path (Pokémon -> Pok\x82mon)
      -- could never have been opened (#325, #665)
      "if($d.ShowDialog() -eq 'OK'){",
      "$t=Join-Path $env:TEMP 'pokeport_sav_pick.sav';",
      "Copy-Item -LiteralPath $d.FileName -Destination $t -Force;",
      "[Console]::OutputEncoding=[Text.Encoding]::UTF8;",
      "[Console]::Write($t)}",
    })
    return commandOutput(
      'powershell -NoProfile -STA -Command "' .. script .. '"')
  elseif platform == "Linux" then
    local path = commandOutput(
      ([[zenity --file-selection --title="%s" --file-filter="Game Boy save | *.sav" 2>/dev/null]])
        :format(prompt))
    if path then return path end
    return commandOutput(
      [[kdialog --getopenfilename "$HOME" "*.sav|Game Boy save" 2>/dev/null]])
  end
  return nil
end

-- Generic user-supplied dependency picker. Keep the native prompt entirely
-- engine-owned: manifest labels are untrusted and must never enter shell
-- command templates. The LÖVE modal already shows the specific import name.
local function chooseRequiredFile()
  local prompt = shellSafe(Strings("Choose required mod file"))
  local platform = love.system.getOS()
  if platform == "OS X" then
    return commandOutput(
      ([[osascript -e 'POSIX path of (choose file with prompt "%s")' 2>/dev/null]])
        :format(prompt))
  elseif platform == "Windows" then
    local script = table.concat({
      "Add-Type -AssemblyName System.Windows.Forms;",
      "$d=New-Object System.Windows.Forms.OpenFileDialog;",
      "$d.Title='" .. prompt .. "';",
      "$d.Filter='All files (*.*)|*.*';",
      -- Required imports can be multi-gigabyte optical-disc images. Do NOT
      -- stage them through %TEMP%: that doubles free-space requirements and a
      -- failed Copy-Item can leave a plausible-looking truncated temp file.
      -- Stream the selected source directly into the mod-owned destination.
      "if($d.ShowDialog() -eq 'OK'){",
      "[Console]::OutputEncoding=[Text.Encoding]::UTF8;",
      "[Console]::Write($d.FileName)}",
    })
    return commandOutput(
      'powershell -NoProfile -STA -Command "' .. script .. '"')
  elseif platform == "Linux" then
    local path = commandOutput(
      ([[zenity --file-selection --title="%s" 2>/dev/null]]):format(prompt))
    if path then return path end
    return commandOutput([[kdialog --getopenfilename "$HOME" 2>/dev/null]])
  end
  return nil
end

-- The self-updater only surfaces on the real distributed build: a fused,
-- interactive launcher with no scripted-run override.  A dev / source checkout
-- (unfused, where Boot.run already no-ops) or an autopilot / driver /
-- import-only run all skip the release check so headless and CI runs never spin
-- up the background worker or reach out to the network.
local function updaterAllowed()
  if not Platform.networkValidated() then return false end
  local isHandheld = os.getenv("HANDHELD") == "1" or os.getenv("PORTMASTER") == "1"
    or os.getenv("POKEPORT_HANDHELD") == "1" or os.getenv("TRIMUI") == "1"
    or os.getenv("MUOS") == "1" or os.getenv("KNULLI") == "1"
  if not (love.filesystem.isFused and love.filesystem.isFused()) and not isHandheld then
    return false
  end
  if os.getenv("POKEPORT_AUTOPILOT") or os.getenv("POKEPORT_DRIVER") then return false end
  if os.getenv("POKEPORT_IMPORT_ONLY") == "1" then return false end
  return true
end

-- #835: which column the launcher opens on.  `tab` starts at the --game
-- shortcut's version (LaunchOptions.pendingTab) or Red; this then prefers the
-- game play() last handed off, so relaunching lands on the game that was last
-- played instead of always Red.  An explicit --game still wins, and a
-- remembered version whose cache is gone or stale is ignored, since opening a
-- column with no Play button would read as the launcher losing the import.
-- Called from new() once self.ready is filled, which is what that check needs.
function RomImporter:_applyLastVersionTab()
  local okOpt, opts = pcall(function()
    return require("src.core.SaveData").loadOptions()
  end)
  self:_restoreActiveCarts(okOpt and opts or nil)
  local okLO, LO = pcall(require, "src.core.LaunchOptions")
  if okLO and LO.pendingTab then return end
  if os.getenv("POKEPORT_LAUNCHER_TAB") then return end
  local last = okOpt and opts and opts.lastVersion
  if last and GameVersion.VERSIONS[last] and self.ready[last] then
    self.tab = last
  end
end

-- The launcher runs each GameVersion as an independent tab.  Each dropped or
-- chosen ROM is routed to its version by SHA-1, extracted into that version's
-- own cache (Red at the root, Blue under blue/, Yellow under yellow/), so all
-- can be imported and played side by side.  onComplete(version, cartId) hands
-- the chosen game -- and the custom cart its page is showing, if any -- off to
-- boot.
-- opts: launcher (a fresh import stays on the launcher instead of auto-booting),
-- forceImport (treat every version as not-yet-imported, so re-import is forced),
-- onEditSave(version, slotId) (host handler for the Edit affordance on a save
-- row -- main.lua opens the bundled save editor on that slot; when it is not
-- supplied the Edit label is not drawn at all),
-- onEditTouchControls() (host handler for the Touch Controls button -- main.lua
-- opens the layout editor; when it is not supplied the button is not drawn).
function RomImporter.new(onComplete, opts)
  opts = opts or {}
  -- iOS rides the same mobile import flows as Android: the save-dir
  -- pending-file scan plus love.system.pickFile / createFile, provided
  -- natively by the Swift GRPickerBridge (mobile/ios/native/).  The flag
  -- keeps its historical name so every Android call site stays untouched.
  -- NX uses a separate save-directory inbox (isNX / romImportMode) and must
  -- never set android or take the mobile delete-after-import path.
  local mobileOS = love.system.getOS()
  local isNX = Platform.isNX()
  local romImportMode = Platform.romImportMode()
  local mobileFileBridge = mobileOS == "Android" or mobileOS == "iOS"
  local android = mobileFileBridge
  local CacheFs = require("src.import.CacheFs")
  local self = setmetatable({
    onComplete = onComplete,
    launcher = opts.launcher or false,
    forceImport = opts.forceImport or false,
    onEditSave = opts.onEditSave,
    onEditTouchControls = opts.onEditTouchControls,
    onOpenSkinStudio = opts.onOpenSkinStudio,
    isNX = isNX,
    romImportMode = romImportMode,
    mobileFileBridge = mobileFileBridge,
    android = android,
    ios = mobileOS == "iOS",
    nativePicker = romImportMode == "native-picker",
    baseRomDiscovery = opts.launcher and Platform.isUWP(),
    baseRoms = {},
    baseRomScan = nil,
    -- One startup poll pass on both mobiles.  iOS: files dropped through the
    -- Files app are swept into the save dir before Lua boots (GRBootstrap) with
    -- no love.focus event necessarily following.  Android: the SAF picker is a
    -- separate activity, and Android is free to destroy GameActivity while it
    -- is up (memory pressure, or "Don't keep activities"), so the app RESTARTS
    -- instead of resuming and the love.focus(true) that would have consumed the
    -- pick never arrives.  The file is sitting in the save dir either way, so
    -- boot armed and let the first poll tick consume it, rather than making the
    -- player tap Import a second time to trigger the scan by hand (#553).
    pickPending = mobileFileBridge or nil,
    -- Mobile drag-scroll goes through FlexLove.touch* (main.lua forwards the
    -- full touch stream while the launcher is up). love.touch remains pollable
    -- for click hit-testing inside EventHandler.
    touchPollable = mobileFileBridge and love.touch ~= nil
      and love.touch.getTouches ~= nil and love.touch.getPosition ~= nil,
    -- Active launcher tab: "red"/"blue"/"yellow"/"mods"/"find".  A --game
    -- shortcut for a version that is not importable yet lands here, so the
    -- player at least arrives on the tab they asked for (src/core/LaunchOptions).
    tab = (function()
      local okLO, LO = pcall(require, "src.core.LaunchOptions")
      return (okLO and LO.pendingTab) or os.getenv("POKEPORT_LAUNCHER_TAB") or "red"
    end)(),
    logo = love.graphics.newImage("assets/logo/logo.png"),
    bcg = love.graphics.newImage("assets/logo/bcg.png"),
    ready = {}, returning = {}, romName = {},
    importing = nil,      -- the version currently extracting, or nil
    workState = nil,      -- "working" / "complete" / "error" for that import
    errorVersion = nil,   -- which column shows the current error
    notice = nil,         -- { version, status, detail } transient hint (Android)
    status = "", detail = "", progress = 0,
    stageCurrent = 0, stageTotal = 1, pulse = 0,
    -- SAVE SLOT panel state (pass 2): each keyed by version.  slots is the
    -- cached SaveData.listSlots array (refreshed lazily on first draw and after
    -- any slot mutation); activeSlot drives the LOADED pill; slotScroll is the
    -- per-version list scroll offset (px), clamped against content in draw.
    slots = {}, activeSlot = {}, slotScroll = {},
    carts = {}, activeCart = {},
    -- SAVE FILES card state: the last import/export result per version, shown as
    -- a green/red notice line under the Import save / Export save buttons.  A
    -- successful export carries { dir } so the notice can offer an open-folder
    -- affordance (desktop love.system.openURL).
    saveNotice = {},
    -- MODS panel state (pass 3): mods is the cached LauncherMods.list() array
    -- (refreshed lazily on first draw and after any toggle/install/delete);
    -- modNotice is the last install/delete result { ok, text }.
    -- requiredImportNotice stays inside the imported-files modal so validation
    -- failures are visible beside the file picker that caused them.
    mods = nil, modNotice = nil, issueNotice = nil,
    requiredImportNotice = nil,
    -- Which game the MODS panel is answering for (a GameVersion id, nil =
    -- every game).  Rows resolve their enable-state and their "runs here"
    -- verdict against it (src/mods/ModTargets.lua).
    modScope = nil,
    -- FIND MODS panel state (src/mods/ModIndex.lua).  findLoaded gates the
    -- first fetch the way `mods = nil` gates the mods list, but it is a flag
    -- rather than a nil listing because "no index added" is a legitimate
    -- loaded state and must not re-fetch every frame.  findSources is the
    -- player's index list from options; findIndex is the merged listing;
    -- _findThumbs caches one image per mod id (false = fetched and failed).
    findLoaded = false, findSources = nil, findIndex = nil,
    findInstalled = nil, findScroll = 0, findNotice = nil, findQuery = "",
    findCategory = nil, _findSearchFocus = false, _findThumbs = nil,
    _findVisibleEntries = nil,
    -- Which half of the feed the panel is browsing.  Mods by default: carts
    -- are the newer, much shorter list, and a feed may carry none at all.
    findKind = "mods", findBase = nil,
    findGame = nil,
    skinUrl = "", _skinUrlFocus = false,
    -- Page scroll offset (px) for the column under the tab bar -- panel, updater
    -- banner and footer -- used only while that column is taller than the window
    -- (see draw()).  Clamped against content in draw, reset on a tab change.
    pageScroll = 0,
    -- Android SAF: which game tab should receive the next picked_save.sav when
    -- focus consumes it (set by chooseSaveImport before opening the picker).
    androidPendingVersion = nil,
    -- Android SAF create-document: which game's SAVE FILES card should show
    -- "Save exported." when export_done.flag appears on focus.
    androidPendingExportVersion = nil,
    pickerPendingKind = nil,
    pickerPendingVersion = nil,
    -- Virtual pointer for handhelds / gamepads (Anbernic stock OS has no
    -- mouse).  D-pad + left stick move it; A clicks; shoulders cycle tabs;
    -- right stick scrolls the save-slot / mods lists.
    _padCursor = { x = 0, y = 0 },
    _padCursorActive = false,
    _padAxis = { leftx = 0, lefty = 0, righty = 0 },
    _padDir = {},
    _rawHatDirs = {},
    _padInited = false,
  }, RomImporter)

  -- Pre-#899 installs keep Red's extracted cache at the save-dir root; move
  -- it under red/ before the readiness loop looks for red/ paths, or every
  -- such install would read as "never imported" and demand the ROM again.
  CacheFs.migrateLegacyRedCache()

  for _, version in ipairs(GameVersion.ORDER) do
    local info = GameVersion.info(version)
    local ready = RomImporter.isReady(version) and not self.forceImport
    self.ready[version] = ready
    -- a marker present but for an older cache generation / different ROM means
    -- "update required" (re-import) rather than a clean first-run choose
    local marker = CacheContract.readMarker(version, CacheFs)
    self.returning[version] =
      (not ready) and marker ~= nil and not CacheContract.markerMatches(version, marker)
    self.romName[version] = "pokemon_" .. info.id
      .. ((info.id == "yellow" or GameVersion.generation(version) == 2)
        and ".gbc" or ".gb")
  end
  RomImporter.syncAndroidShortcuts()
  Transition.reset()
  Transition.armed = false
  local okMotion, motionOpts = pcall(function()
    return require("src.core.SaveData").loadOptions()
  end)
  Transition.reduceMotion = os.getenv("POKEPORT_REDUCE_MOTION") == "1"
    or opts.reduceMotion == true
    or (okMotion and type(motionOpts) == "table"
      and motionOpts.reduceMotion == true) or false
  self:_applyLastVersionTab()
  if type(opts.initialTab) == "string" and opts.initialTab ~= "" then
    self:_switchTab(opts.initialTab)
  end
  if type(opts.joinCode) == "string" and opts.joinCode ~= "" then
    self:_switchTab("online")
    local okOnline, OnlinePanel = pcall(require, "src.import.OnlinePanel")
    if okOnline then pcall(OnlinePanel.deepLink, self, opts.joinCode, "player") end
  end
  self:_queueBaseRomScan()

  -- Android: import a save-dir .gb/.gbc that is not yet ready (USB drop or a
  -- leftover SAF pick), routed by SHA-1.  Already-imported carts are skipped
  -- so a stale picked_rom.gb cannot block another version.
  local needRom = false
  for _, version in ipairs(GameVersion.ORDER) do
    if not self.ready[version] then needRom = true; break end
  end
  if mobileFileBridge and needRom then
    local name, data = findPendingRom(self.ready)
    if name then
      self:startData(data, name)
    else
      -- The picker runs as its own activity and Android may kill us while it
      -- is up, so a rejected pick can outlive the focus handler (#442).
      consumePickedRomError(self)
    end
  elseif self.isNX and self.launcher then
    self:ensureImportsDir()
    self:_setNxInboxNotice()
  end

  -- Mouse-wheel scroll for the save-slot / mods lists.  main.lua (off limits)
  -- swallows love.wheelmoved while the launcher is up and never forwards it
  -- here, so the interactive launcher chains the global handler once,
  -- non-destructively: our scroll runs first, then the previous handler (which
  -- no-ops while the Importer is live and resumes feeding the game after
  -- handoff).  Only the interactive launcher installs this; the scripted /
  -- import-only paths (launcher = false) leave the handler untouched.
  if self.launcher and love and love.wheelmoved then
    local prevWheel = love.wheelmoved
    love.wheelmoved = function(dx, dy)
      if not self._handedOff then pcall(self.wheelmoved, self, dx, dy) end
      if prevWheel then return prevWheel(dx, dy) end
    end
  end

  -- Self-updater: the interactive launcher on a real fused build kicks off one
  -- async release check as it comes up; the top-right update control polls
  -- Check.state() and glows when there is something to do.  Held behind pcall
  -- so a broken or absent updater can never take the launcher down with it.
  if self.launcher and updaterAllowed() then
    local ok, Check = pcall(require, "src.update.Check")
    if ok and Check then
      self.Check = Check
      pcall(Check.start)
    end
  end

  -- PREWARM.  Start the mod-index fetch at boot rather than when the Find
  -- Mods tab is first opened.  The work is identical either way, but doing it
  -- now means it overlaps the time the user spends looking at the game tab,
  -- so the tab is already populated when they reach it instead of greeting
  -- them with a loader.  Nothing here blocks: the fetch pool is off-thread
  -- and _pumpFindFetch collects the result whenever it lands.
  --
  -- Deliberately NOT behind the blocking overlay: the user did not ask for
  -- this and must be able to use the launcher while it runs, so _busy is
  -- cleared straight back out.  An explicit Refresh press still shows one.
  if self.launcher then
    pcall(function()
      self:_refreshFindSources()
      if #(self.findSources or {}) > 0 then
        self:_refreshFind(false)
        self:_clearBusy()
      end
    end)
  end

  -- On Linux handhelds / NX a gamepad is usually already connected at boot;
  -- arm the virtual cursor immediately so the player does not have to press a
  -- button before seeing something move.  Desktop keeps the cursor latent
  -- until the first stick bump so a plugged DualSense does not steal the mouse.
  if self.launcher and love.joystick and love.joystick.getJoystickCount
      and love.joystick.getJoystickCount() > 0 then
    local osName = (love.system and love.system.getOS and love.system.getOS()) or ""
    if osName == "Linux" or self.isNX then
      self:_activatePadCursor()
    end
  end

  if GameVersion.VERSIONS[self.tab] then
    self.modScope = self.tab
  end

  return self
end

-- The system picker runs as a separate top activity, so LOVE's own
-- love.focus/love.visible pause while it's up (see main.lua) -- once the
-- player returns here with a file picked, GameActivity has already copied
-- it into the save directory, so a pending-file rescan on refocus picks it
-- up without the player needing to tap the button again.  Mod and save SAF
-- drops (picked_mod.zip / picked_save.sav) are consumed first so a leftover
-- ROM pick cannot steal the focus path when both games are already ready.
-- NOTE (iOS): do NOT clear pickPending here.  The picker's dismissal focus
-- event can arrive before the Swift delegate has finished copying the pick
-- into the save dir; if this scan runs early and finds nothing, the poll in
-- _pollPickedFiles must stay armed so it consumes the file when it lands
-- moments later (it clears pickPending itself once something is found).
function RomImporter:focus(f)
  if not f then
    self._activeTouch = nil
    self._pagePress = nil
    self._slotPress = nil
    self._modPress = nil
    return
  end
  if type(self._sync) == "table" then
    pcall(self._sync.noteResumed, self._sync)
  end
  if not (f and self.android and self.workState ~= "working") then return end
  -- SAF create-document finished: GameActivity wrote export_done.flag.
  if love.filesystem.getInfo("export_done.flag", "file") then
    love.filesystem.remove("export_done.flag")
    love.filesystem.remove("pending_export.sav")
    if self.androidPendingCartExport then
      self.androidPendingCartExport = nil
      self._cartNotice = Strings("Cart exported.")
      return
    end
    local version = self.androidPendingExportVersion or self:_savedropTarget()
    self.androidPendingExportVersion = nil
    self.saveNotice[version] = { ok = true, text = "Save exported." }
    if self.tab == "mods" then self.tab = version end
    return
  end
  -- The SAF pick failed inside GameActivity, which wrote pick_error.flag with
  -- the destination basename in it: some OEM shells (ColorOS) let a third-party
  -- archive manager win the ACTION_OPEN_DOCUMENT chooser and hand back a URI
  -- this app has no permission to read, and until #442 that returned to a
  -- launcher that said nothing at all.
  local pickError = love.filesystem.getInfo("pick_error.flag", "file")
    and love.filesystem.read("pick_error.flag")
  if pickError then
    love.filesystem.remove("pick_error.flag")
    local text
    if pickError:find("cancelled:", 1, true) == 1 then
      text = "The file manager did not return a file. Try a different file "
        .. "manager, or copy it into: " .. love.filesystem.getSaveDirectory()
    else
      text = "Could not read the picked file. Reopen the picker and choose "
        .. "it with the Files (Documents) app, or copy it into: "
        .. love.filesystem.getSaveDirectory()
    end
    local legacyRequiredPick = self.requiredImportLegacyRomPick
      and self.pickerPendingKind == "required_import"
    if self.pickerPendingKind == "required_import"
        or pickError:find("picked_required_import", 1, true)
        or pickError:find("picked_stadium", 1, true)
        or pickError:find("/baseroms/", 1, true)
        or pickError:find("\\baseroms\\", 1, true)
        or (legacyRequiredPick and pickError:find("picked_rom", 1, true)) then
      self.modNotice = { ok = false, text = text }
      self.pickerPendingKind = nil
      self.pickerPendingModId = nil
      self.pickerPendingImportId = nil
      self.requiredImportLegacyRomPick = nil
    elseif pickError:find("picked_mod", 1, true) then
      if self.pickerPendingKind == "skin" then
        self.pickerPendingKind = nil
        self._skinNotice = { ok = false, text = text }
      else
        self.modNotice = { ok = false, text = text }
      end
    elseif pickError:find("picked_save", 1, true) then
      local version = self.androidPendingVersion or self:_savedropTarget()
      self.androidPendingVersion = nil
      self.saveNotice[version] = { ok = false, text = text }
    else
      self:setError(text)
    end
    return
  end

  -- Current mobile bridge: the native picker has already streamed a raw
  -- dependency into mods/<id>/baseroms and published its digest/size marker.
  local completedRequired = love.filesystem.getInfo(PICK_COMPLETE_FILENAME, "file")
    and love.filesystem.read(PICK_COMPLETE_FILENAME)
  if completedRequired then
    love.filesystem.remove(PICK_COMPLETE_FILENAME)
    self.pickPending = nil
    finishDirectRequiredImport(self, completedRequired)
    self.pickerPendingKind = nil
    self.pickerPendingModId = nil
    self.pickerPendingImportId = nil
    self.requiredImportLegacyRomPick = nil
    return
  end

  local requiredName = findPendingRequiredImport(self)
  if requiredName then
    local modId, importId = self.pickerPendingModId, self.pickerPendingImportId
    self.pickerPendingKind = nil
    self.pickerPendingModId, self.pickerPendingImportId = nil, nil
    self.requiredImportLegacyRomPick = nil
    local imported = modId and importId
      and self:_importRequiredSource(modId, importId, requiredName)
    consumePick(self, requiredName, requiredName, imported)
    if not modId or not importId then
      self.modNotice = { ok = false,
        text = "A picked dependency file had no pending mod request and was discarded." }
    end
    return
  end
  local modName = findPendingMod(false, self.pickSkip)
  if modName then
    if self.pickerPendingKind == "skin" then
      self.pickerPendingKind = nil
      self:_installSkinZip(modName)
      consumePick(self, modName, "picked_mod.zip",
        self._skinNotice and self._skinNotice.ok)
      return
    end
    self:_installMod(modName)
    consumePick(self, modName, "picked_mod.zip",
      self.modNotice and self.modNotice.ok)
    return
  end
  local savName = findPendingSav(false, self.pickSkip)
  if savName then
    local version = self.androidPendingVersion or self:_savedropTarget()
    self.androidPendingVersion = nil
    self:_importSave(version, savName)
    consumePick(self, savName, "picked_save.sav",
      self.saveNotice[version] and self.saveNotice[version].ok)
    return
  end
  for _, v in ipairs(GameVersion.ORDER) do
    if not self.ready[v] then
      local name, data = findPendingRom(self.ready)
      if name then
        self:startData(data, name)
      else
        consumePickedRomError(self)
      end
      return
    end
  end
end

function RomImporter:setError(message, version)
  require("src.import.CacheFs").prefix = ""
  self.workState = "error"
  self.errorVersion = version or self.importing or self.chooseVersion or "red"
  self.importing = nil
  self.notice = nil
  self.status = "That ROM could not be imported"
  self.detail = tostring(message)
  self.progress = 0
  self.worker = nil
  -- Dropping the job stops collection; the next import clears the channels.
  self._extract = nil
  self.romData = nil
  -- A headless import has no launcher to read this off: POKEPORT_IMPORT_ONLY
  -- only ever quits from onComplete, so an import that fails here would sit in
  -- the error state forever and look to a build script (or a person) exactly
  -- like a hang.  Log what broke and exit non-zero instead.  Logger, not a
  -- literal write: this is a diagnostic for whoever ran the import, never text
  -- a player sees, so it is deliberately not a translated string.
  if os.getenv("POKEPORT_IMPORT_ONLY") == "1" then
    Logger.error("import failed: %s", tostring(message))
    love.event.quit(1)
  end
end

-- draw() may leave the system hand cursor set while hovering a Play /
-- Choose control.  Once the importer is torn down that draw path stops
-- running, so restore the arrow before handing off to boot (issue #114).
local function resetPointerCursor(self)
  if self.android then return end
  if not (love.mouse.isCursorSupported and love.mouse.isCursorSupported()) then
    return
  end
  if not self.arrowCursor then
    local ok, cursor = pcall(love.mouse.getSystemCursor, "arrow")
    if not ok then return end
    self.arrowCursor = cursor
  end
  love.mouse.setCursor(self.arrowCursor)
end

-- Verify + extract a ROM.  The version is decided by the ROM's own SHA-1, so
-- dropping a Red, Blue, or Yellow cart into any column always lands in the
-- right one.
function RomImporter:startData(data, displayName)
  if self.workState == "working" then return end
  if type(data) ~= "string" then
    self:setError("The selected file could not be read.")
    return
  end
  if not isAcceptedRomSize(#data) then
    self:setError(("Expected a 1 MiB Game Boy ROM (%s) or a "
      .. "2 MiB Game Boy Color ROM (%s); this file is %.2f MiB.")
      :format(cartsSlashed(1), cartsSlashed(2), #data / 1024 / 1024))
    return
  end
  local actualHash = sha1(data)
  local version = GameVersion.forSha1(actualHash)
  if not version then
    self:setError(("Unsupported ROM (SHA-1 %s). This needs a clean US Pokemon "
      .. "%s dump; patched, trimmed or "
      .. "\"fixed\" dumps "
      .. "(tagged [b] or [BF]) never verify."):format(actualHash, cartsProse()))
    return
  end
  self.romSha1 = actualHash
  local info = GameVersion.info(version)

  -- Bring the launcher to this version's tab so its progress bar is on screen
  -- (a dropped cart is routed by SHA-1 regardless of which tab was showing).
  if GameVersion.VERSIONS[self.tab] then
    self.tab = version
  end
  self.importing = version
  self.workState = "working"
  self.notice = nil
  self.status = "Verifying " .. info.displayName
  self.detail = displayName or info.displayName
  self.progress = 0
  self.romData = data
  self.status = "Preparing private game data"

  -- Clear this version's previous cache from both homes before anything
  -- writes.  Stays on the main thread so delete-then-fill-then-mark keeps one
  -- owner; the prefix is restored at once because the worker sets its own.
  local CacheFs = require("src.import.CacheFs")
  local prefix = info.cachePrefix
  local savedPrefix = CacheFs.prefix
  CacheFs.prefix = prefix
  local cleared, clearError = pcall(function()
    removeTree(prefix .. "data/generated")
    removeTree(prefix .. "assets/generated")
    love.filesystem.remove(prefix .. CacheContract.MARKER_PATH)
    CacheFs.removeTree("data/generated")
    CacheFs.removeTree("assets/generated")
    CacheFs.remove(CacheContract.MARKER_PATH)
  end)
  CacheFs.prefix = savedPrefix
  if not cleared then
    self:setError(tostring(clearError), version)
    return
  end

  if self:_startExtractThread(version, prefix, data, displayName) then return end
  self:_startExtractCoroutine(version, info, prefix, displayName)
end

-- False when threads are unavailable, so the coroutine path still covers
-- that host.  POKEPORT_NO_THREAD=1 forces it, which is the only way to
-- exercise the fallback on a desktop.
function RomImporter:_startExtractThread(version, prefix, data, displayName)
  if os.getenv("POKEPORT_NO_THREAD") == "1" then return false end
  if not (love.thread and love.thread.newThread) then return false end
  local ok, thread = pcall(love.thread.newThread, "src/import/ExtractThread.lua")
  if not ok or not thread then return false end
  local progressName = "rom_import_progress"
  local resultName = "rom_import_result"
  love.thread.getChannel(progressName):clear()
  love.thread.getChannel(resultName):clear()
  local started = pcall(thread.start, thread, version, prefix, data,
    progressName, resultName, self.romSha1)
  if not started then return false end
  self._extract = {
    thread = thread, version = version, prefix = prefix,
    displayName = displayName,
    progress = love.thread.getChannel(progressName),
    result = love.thread.getChannel(resultName),
  }
  -- The worker owns the bytes now; drop ours so the 1-2 MiB string can go.
  self.romData = nil
  return true
end

function RomImporter:_startExtractCoroutine(version, info, prefix, displayName)
  self.worker = coroutine.create(function()
    coroutine.yield()
    local CacheFs = require("src.import.CacheFs")
    CacheFs.prefix = prefix
    local manifest = require("src.import.RomManifest").decode(version)
    local RomExtractor = GameVersion.generation(version) == 2
      and require("src.import.RomExtractorGen2")
      or require("src.import.RomExtractor")
    local extractor = RomExtractor.new(self.romData, manifest,
      function(progress, total, stage, current, stageTotal)
        self.status = stage
        self.progress = progress / total
        self.stageCurrent = current
        self.stageTotal = stageTotal
        coroutine.yield()
      end, self.romSha1)
    extractor:run()
    CacheFs.prefix = ""   -- restore the default so later writes stay at the root
    self.romData = nil
    collectgarbage("collect")
    self:_completeImport(version, prefix, displayName)
  end)
end

-- Everything after the tree is filled, shared by both worker paths.  Raises
-- on a failed marker write; the thread path calls it inside a pcall.
function RomImporter:_completeImport(version, prefix, displayName)
  local info = GameVersion.info(version)
  local CacheFs = require("src.import.CacheFs")
  -- Written last: the marker is what isReady() checks, so it must only
  -- appear once every required file is in place.
  local savedPrefix = CacheFs.prefix
  CacheFs.prefix = prefix
  local ok, writeError = CacheContract.publish(version, CacheFs, self.romSha1)
  CacheFs.prefix = savedPrefix
  if not ok then
    error("could not finish the private cache: " .. tostring(writeError))
  end
  self.ready[version] = true
  self.returning[version] = false
  self.romName[version] = (displayName
    and (displayName:match("[^/\\]+$") or displayName)) or self.romName[version]
  -- Android: drop the consumed save-dir .gb/.gbc (picked_rom.gb or a USB copy)
  -- so the next Choose / focus cannot treat it as a fresh pending ROM.
  if self.mobileFileBridge and type(displayName) == "string"
      and not displayName:find("[/\\]") then
    love.filesystem.remove(displayName)
  end
  self.importing = nil
  self.workState = "complete"
  self.completeVersion = version
  self.status = "Ready"
  RomImporter.syncAndroidShortcuts(version)
  -- NX launcher stays put: keep the imports/ cleanup hint instead of
  -- overwriting it with a "Starting…" line that never boots from here.
  if self.launcher and self.isNX and type(displayName) == "string" then
    self.detail = Strings("%s imported. You may delete the copy from "
      .. "imports/ when finished.", displayName)
  else
    self.detail = "Starting " .. info.displayName .. "..."
  end
  self.progress = 1
  if self.launcher then
    -- Stay on the launcher; the player presses Play to boot the new game.
    return
  end
  self._handedOff = true
  resetPointerCursor(self)
  if self._flex then require("src.import.LauncherView").detach(self) end
  if self.onComplete then self.onComplete(version) end
end

-- Drain the worker's progress and finish when it reports done.  One
-- non-blocking poll per frame, like the other _pump* collectors above.
function RomImporter:_pumpExtract()
  local job = self._extract
  if not job then return end
  local msg = job.progress:pop()
  while msg do
    self.status = msg.stage
    self.progress = msg.progress / msg.total
    self.stageCurrent = msg.current
    self.stageTotal = msg.stageTotal
    msg = job.progress:pop()
  end
  local res = job.result:pop()
  if not res then
    -- A thread that died before pushing a result would strand the loader.
    local threadError = job.thread.getError and job.thread:getError()
    if threadError then
      self._extract = nil
      self:setError(tostring(threadError), job.version)
    end
    return
  end
  self._extract = nil
  if not res.ok then
    self:setError(tostring(res.error), job.version)
    return
  end
  local ok, err = pcall(self._completeImport, self, job.version, job.prefix,
    job.displayName)
  if not ok then self:setError(tostring(err), job.version) end
end

function RomImporter:startPath(path)
  if not path then return end
  local data, readError = readExternalPath(path)
  if not data then
    self:setError("Could not read the selected file: " .. tostring(readError))
    return
  end
  self:startData(data, path:match("[^/\\]+$") or path)
end

function RomImporter:filedropped(file)
  if self.workState == "working" then return end
  -- A dropped .zip is a mod archive: hand it straight to the mods installer
  -- (which mounts + validates it).  A .deltaskin is only ever a skin, and
  -- everything else is treated as a ROM.  The dropped file itself is passed
  -- through -- installZip opens it the same way readDroppedFile does here.
  local name = file:getFilename() or ""
  if name:lower():match("%.deltaskin$") then
    self:_installSkinZip(file)
    return
  end
  if name:lower():match("%.zip$") then
    -- On the SKINS tab a zip is a skin; everywhere else it is a mod archive.
    if self.tab == "skins" then
      self:_installSkinZip(file)
    else
      self:_installMod(file)
    end
    return
  end
  -- A dropped .sav is a battery save: import it to a new slot for the active
  -- game tab (see _savedropTarget for the tab-selection rule).  It never steals
  -- .gb/.zip routing above.
  if name:lower():match("%.sav$") then
    self:_importSave(self:_savedropTarget(), file)
    return
  end
  local data, readError = readDroppedFile(file)
  if not data then
    self:setError("Could not read the dropped file: " .. tostring(readError))
    return
  end
  self:startData(data, file:getFilename())
end

-- Install a mod .zip from a picker path or a dropped file, then surface the
-- result on the mods panel (switching to it so the notice is visible).  The
-- source is whatever LauncherMods.installZip accepts: an absolute path string
-- or a love DroppedFile.
function RomImporter:_installMod(source)
  if self.workState == "working" then return end
  self.tab = "mods"
  local ok, installed, res, manifest = pcall(function()
    local LauncherMods = require("src.mods.LauncherMods")
    return LauncherMods.installZip(source)
  end)
  if not ok then
    self.modNotice = { ok = false,
      text = "Import failed: " .. tostring(installed) }
    return
  end
  if installed then
    pcall(self._refreshMods, self)
    self.modNotice = { ok = true, text = "Installed " .. tostring(res) }
    local LauncherMods = require("src.mods.LauncherMods")
    local checkTarget = manifest
    if not checkTarget and type(res) == "string" then
      checkTarget = { id = res }
    end
    if checkTarget and LauncherMods.checkDependencies then
      local depCheck = LauncherMods.checkDependencies(checkTarget)
      if depCheck and depCheck.hasIssues then
        self._modDepResolver = depCheck
      end
    end
  else
    self.modNotice = { ok = false, text = tostring(res) }
  end
end

-- Remove an installed mod from the save-dir mods/ tree and refresh the panel.
function RomImporter:_deleteMod(id)
  if self.workState == "working" then return end
  local ok, deleted, res = pcall(function()
    local LauncherMods = require("src.mods.LauncherMods")
    return LauncherMods.uninstall(id)
  end)
  if not ok then
    self.modNotice = { ok = false,
      text = "Delete failed: " .. tostring(deleted) }
    return
  end
  if deleted then
    pcall(self._refreshMods, self)
    self.modNotice = { ok = true, text = "Deleted " .. tostring(id) }
  else
    self.modNotice = { ok = false, text = tostring(res) }
  end
end

-- "Import mod .zip" button: open a native picker and install the pick.
-- Android mirrors ROM import: scan for a pending .zip in the save dir (USB
-- or a fresh SAF drop), else love.system.pickFile("mod") -> picked_mod.zip
-- which focus/Choose consumes on return.
-- NX: no HostShell/desktop picker -- rescan imports/mods/ inbox instead.
function RomImporter:chooseMod()
  if self.workState == "working" then return end
  if self.isNX then
    self:ensureModsInboxDir()
    self:rescanModsAction()
    return
  end
  if self.nativePicker and love.system.getPickedFile then
    self.pickerPendingKind = "mod"
    if not pickFile("mod") then
      self.pickerPendingKind = nil
      self.modNotice = { ok = false, text = "Could not open the file picker." }
    end
    return
  end
  if self.android then
    local name = findPendingMod(true, self.pickSkip)
    if name then
      self:_installMod(name)
      consumePick(self, name, "picked_mod.zip",
        self.modNotice and self.modNotice.ok)
      return
    end
    if not pickFile("mod") then
      self.modNotice = { ok = false,
        text = "Could not open the file picker. Copy a mod .zip via USB." }
    else
      self.pickPending = true
      self.pickTimer = 0
    end
    return
  end
  local isHandheld = os.getenv("HANDHELD") == "1" or os.getenv("PORTMASTER") == "1"
    or os.getenv("POKEPORT_HANDHELD") == "1" or os.getenv("TRIMUI") == "1"
    or os.getenv("MUOS") == "1" or os.getenv("KNULLI") == "1"

  if isHandheld then
    local okKit, Kit = pcall(require, "src.ui.kit.Kit")
    if okKit and Kit.FileBrowser then
      self._padCursorActive = false
      Kit.FileBrowser.open({
        title = "Select Mod (.zip)",
        mode = "mod",
        onSelect = function(pickedPath)
          self:_installMod(pickedPath)
        end,
      })
      return
    end
  end

  local path = chooseZip()
  if path then
    self:_installMod(path)
    return
  end
  local okKit, Kit = pcall(require, "src.ui.kit.Kit")
  if okKit and Kit.FileBrowser then
    self._padCursorActive = false
    Kit.FileBrowser.open({
      title = "Select Mod (.zip)",
      mode = "mod",
      onSelect = function(pickedPath)
        self:_installMod(pickedPath)
      end,
    })
    return
  end
end

local function requiredManifest(self, modId)
  for _, row in ipairs(self.mods or {}) do
    if row.id == modId then return row.manifest, row end
  end
  return nil
end

local function requiredSpec(manifest, importId)
  for _, candidate in ipairs(require("src.mods.RequiredImports").specs(manifest)) do
    if candidate.id == importId then return candidate end
  end
  return nil
end

local function requiredImportNotice(self, modId, importId, text)
  self.requiredImportNotice = {
    modId = modId,
    importId = importId,
    text = tostring(text),
  }
end

-- Current Android/iOS bridges can stream a raw required import directly from
-- the system document provider into its engine-owned baseroms destination.
-- The bridge hashes/counts the same bytes and then publishes this tiny marker:
--   v1\n<relative destination>\n<md5>\n<byte count>\n
-- Older mobile builds still stage picked_required_import.bin, so this is an
-- additive completion path rather than a replacement for the legacy one.
local function directRequiredImportTarget(self, marker)
  local fields = {}
  for line in tostring(marker or ""):gmatch("[^\r\n]+") do
    fields[#fields + 1] = line
    if #fields > 4 then break end
  end
  local version, path, digest, count = fields[1], fields[2], fields[3], fields[4]
  if version ~= "v1" or not path or not digest or not count or #digest ~= 32
      or not digest:match("^%x+$") or not count:match("^%d+$") then
    return nil, "The completed dependency marker was malformed."
  end
  digest = digest:lower()
  count = tonumber(count)
  if not count then return nil, "The completed dependency size was invalid." end

  if not self.mods and self._refreshMods then pcall(self._refreshMods, self) end
  local RequiredImports = require("src.mods.RequiredImports")

  local function matchRow(row, wantedImportId)
    local manifest = row and row.manifest
    if not manifest then return nil end
    for _, spec in ipairs(RequiredImports.specs(manifest)) do
      if (not wantedImportId or spec.id == wantedImportId)
          and RequiredImports.path(manifest, spec) == path then
        return manifest, spec, row.id or manifest.id
      end
    end
    return nil
  end

  -- Normal resume: bind the marker to exactly the request that opened picker.
  if self.pickerPendingModId and self.pickerPendingImportId then
    for _, row in ipairs(self.mods or {}) do
      if row.id == self.pickerPendingModId then
        local manifest, spec, modId = matchRow(row, self.pickerPendingImportId)
        if manifest then return path, digest, count, manifest, spec, modId end
      end
    end
    return nil, "The completed dependency did not match the pending import request."
  end

  -- Android may recreate GameActivity while DocumentsUI is open. If Lua was
  -- restarted too, recover by the exact engine-owned destination. The path
  -- includes the mod id and only a manifest-declared import can match it.
  for _, row in ipairs(self.mods or {}) do
    local manifest, spec, modId = matchRow(row)
    if manifest then return path, digest, count, manifest, spec, modId end
  end
  return nil, "The completed dependency did not match an installed mod request."
end

finishDirectRequiredImport = function(self, marker)
  local path, digestOrErr, nativeSize, manifest, spec, modId =
    directRequiredImportTarget(self, marker)
  if not path then
    self.modNotice = { ok = false, text = tostring(digestOrErr) }
    return nil
  end
  local digest = digestOrErr
  local RequiredImports = require("src.mods.RequiredImports")
  local info = love.filesystem.getInfo(path, "file")
  if not info or type(info.size) ~= "number" then
    requiredImportNotice(self, modId, spec.id,
      "The completed dependency file was not found.")
    self.modNotice = nil
    return nil
  end
  if info.size ~= nativeSize then
    love.filesystem.remove(path)
    if RequiredImports.receiptPath then
      love.filesystem.remove(RequiredImports.receiptPath(manifest, spec))
    end
    requiredImportNotice(self, modId, spec.id,
      ("Dependency copy size changed after completion (expected %d bytes, found %d).")
        :format(nativeSize, info.size))
    self.modNotice = nil
    return nil
  end
  local sizeErr = RequiredImports.sizeError(spec, info.size, true)
  if sizeErr then
    love.filesystem.remove(path)
    if RequiredImports.receiptPath then
      love.filesystem.remove(RequiredImports.receiptPath(manifest, spec))
    end
    requiredImportNotice(self, modId, spec.id, sizeErr)
    self.modNotice = nil
    return nil
  end

  -- No second 665 MiB / 1.46 GiB read: native calculated this digest while
  -- streaming the selected document into the one final copy.
  local ok, detail = RequiredImports.acceptStoredDigest(
    manifest, spec.id, digest, love.filesystem)
  if not ok then
    love.filesystem.remove(path)
    if RequiredImports.receiptPath then
      love.filesystem.remove(RequiredImports.receiptPath(manifest, spec))
    end
    requiredImportNotice(self, modId, spec.id, detail)
    self.modNotice = nil
    return nil
  end

  self.requiredImportNotice = nil
  self.modNotice = { ok = true, text = "Imported " .. tostring(spec.id)
    .. " for " .. tostring(manifest.name or manifest.id) .. "." }
  self:_refreshMods()
  return true
end

function RomImporter:_importRequiredData(modId, importId, data)
  local manifest = requiredManifest(self, modId)
  if not manifest then
    self.modNotice = { ok = false, text = "Required import failed: mod not found." }
    return nil
  end
  local ok, result = require("src.mods.RequiredImports")
    .importData(manifest, importId, data)
  if ok then
    self.requiredImportNotice = nil
    self.modNotice = { ok = true, text = "Imported " .. tostring(importId)
      .. " for " .. tostring(manifest.name or manifest.id) .. "." }
    self:_refreshMods()
    return true
  end
  -- Keep validation feedback on the imported-files page.  A general Mods-page
  -- notice is hidden by this modal and made MD5 failures especially easy to miss.
  requiredImportNotice(self, modId, importId, result)
  self.modNotice = nil
  return nil
end

function RomImporter:_importRequiredSource(modId, importId, source, confirmed)
  local manifest = requiredManifest(self, modId)
  local spec = manifest and requiredSpec(manifest, importId)
  if not spec then
    requiredImportNotice(self, modId, importId, "Import declaration was not found.")
    self.modNotice = nil
    return nil
  end
  local RequiredImports = require("src.mods.RequiredImports")
  -- A desktop picker returns a host path. Ask the host file handle first;
  -- love.filesystem.getInfo is only authoritative for virtual/save paths.
  local size = externalFileSize(source)
  if not size then
    local info = love.filesystem.getInfo(source, "file")
    size = info and info.size or nil
  end
  local sizeErr = RequiredImports.sizeError(spec, size, false)
  if sizeErr then
    requiredImportNotice(self, modId, importId, sizeErr)
    self.modNotice = nil
    return nil
  end
  if not confirmed and type(size) == "number"
      and size > RequiredImports.LARGE_WARN_BYTES then
    self._modConfirm = {
      kind = "largeImport",
      modId = modId, importId = importId, source = source,
      title = Strings("Large import"),
      lines = {
        Strings("This is a large import (%s).",
          RequiredImports.sizeLabel(size)),
        Strings("Please ensure you have enough space on your"),
        Strings("device before doing this."),
      },
      yesLabel = Strings("I understand"),
    }
    return nil
  end
  if spec.format ~= "n64" and (size == nil
      or size > RequiredImports.LARGE_WARN_BYTES) then
    local ok, result = streamRequiredImport(manifest, importId, source)
    if ok then
      self.requiredImportNotice = nil
      self.modNotice = { ok = true, text = "Imported " .. tostring(importId)
        .. " for " .. tostring(manifest.name or manifest.id) .. "." }
      self:_refreshMods()
      return true
    end
    requiredImportNotice(self, modId, importId, result)
    self.modNotice = nil
    return nil
  end
  local data = love.filesystem.read(source)
  if not data then data = readExternalPath(source) end
  if not data then
    requiredImportNotice(self, modId, importId, "Could not read the selected file.")
    self.modNotice = nil
    return nil
  end
  return self:_importRequiredData(modId, importId, data)
end

function RomImporter:_removeRequiredImport(modId, importId)
  local manifest = requiredManifest(self, modId)
  if not manifest then return end
  local ok, err = require("src.mods.RequiredImports").remove(manifest, importId)
  if ok then
    self.requiredImportNotice = nil
    self.modNotice = { ok = true, text = "Deleted " .. tostring(importId) .. "." }
    self:_refreshMods()
  else
    requiredImportNotice(self, modId, importId, err)
    self.modNotice = nil
  end
end

-- Select and validate one manifest-declared file.  NX has no host picker, so
-- its equivalent is an engine-owned imports/baseroms inbox that can be filled
-- over MTP; every other native/mobile picker lands on the same validation path.
function RomImporter:chooseRequiredImport(modId, importId)
  if self.workState == "working" then return end
  local manifest = requiredManifest(self, modId)
  if not manifest then return end
  local spec = requiredSpec(manifest, importId)
  if not spec then return end

  if self.isNX then
    local inbox = "imports/baseroms"
    love.filesystem.createDirectory(inbox)
    local lastError
    for _, name in ipairs(love.filesystem.getDirectoryItems(inbox) or {}) do
      if name:sub(1, 1) ~= "." then
        local path = inbox .. "/" .. name
        local info = love.filesystem.getInfo(path, "file")
        local RequiredImports = require("src.mods.RequiredImports")
        local sizeErr = info
          and RequiredImports.sizeError(spec, info.size, false)
        if info and not sizeErr
            and info.size > RequiredImports.LARGE_WARN_BYTES then
          return self:_importRequiredSource(modId, importId, path)
        end
        local data = not sizeErr and love.filesystem.read(path) or nil
        if data and self:_importRequiredData(modId, importId, data) then return end
        if sizeErr then lastError = sizeErr
        elseif self.requiredImportNotice
            and self.requiredImportNotice.modId == modId
            and self.requiredImportNotice.importId == importId then
          lastError = self.requiredImportNotice.text
        end
      end
    end
    requiredImportNotice(self, modId, importId, lastError
      or "No matching file in imports/baseroms/. Copy it there over MTP, then try again.")
    self.modNotice = nil
    return
  end
  if self.nativePicker then
    -- Android 13+ uses the Storage Access Framework for both paths.  Some
    -- Android 15 installs carry the newer Lua launcher with an older native
    -- bridge, however, so they do not advertise required_import yet.  Fall
    -- back to that bridge's known "rom" picker and quarantine its result by
    -- the pending required-import IDs. iOS has a different asynchronous
    -- bridge and deliberately keeps the explicit capability requirement.
    local legacyAndroidPicker = self.mobileFileBridge
      and love.system.getOS() == "Android"
      and not pickerHasKind("required_import")
    if self.mobileFileBridge and not pickerHasKind("required_import")
        and not legacyAndroidPicker then
      requiredImportNotice(self, modId, importId,
        "This app build cannot pick required mod files yet. Update the app and try again.")
      self.modNotice = nil
      return
    end
    self.pickerPendingKind = "required_import"
    self.pickerPendingModId = modId
    self.pickerPendingImportId = importId
    self.requiredImportLegacyRomPick = legacyAndroidPicker or nil
    -- Raw imports can go straight to their final private destination on current
    -- Android/iOS bridges. N64 stays on staging because the launcher still has
    -- to canonicalize byte order/copier headers before storing it.
    local directDestination = (self.mobileFileBridge and not legacyAndroidPicker
        and spec.format ~= "n64"
        and type(manifest.path) == "string" and manifest.path ~= "")
      and require("src.mods.RequiredImports").path(manifest, spec) or nil
    if not pickFile(legacyAndroidPicker and "rom" or "required_import",
        directDestination) then
      self.pickerPendingKind = nil
      self.pickerPendingModId = nil
      self.pickerPendingImportId = nil
      self.requiredImportLegacyRomPick = nil
      requiredImportNotice(self, modId, importId, "Could not open the file picker.")
      self.modNotice = nil
    elseif self.android then
      self.pickPending = true
      self.pickTimer = 0
    end
    return
  end

  local path = chooseRequiredFile()
  if path then self:_importRequiredSource(modId, importId, path) end
end

-- Which game a dropped .sav imports into: a .sav has no version signature of
-- its own, so it lands on the active game tab.  When a non-game tab (mods) is
-- showing, default to red -- the always-present first game -- rather than
-- guess.
function RomImporter:_savedropTarget()
  local v = self.tab
  if GameVersion.VERSIONS[v] then return v end
  return "red"
end

-- Import a raw .sav into a fresh slot for a version, from a picker path or a
-- dropped file, and surface the outcome on that game's SAVE FILES card.  Brings
-- the target tab forward so the notice (and, on success, the new active slot)
-- is visible.  Requires the ROM to be imported first, since a save is only
-- playable with its game's data present.
function RomImporter:_importSave(version, source, force)
  if self.workState == "working" then return end
  if GameVersion.VERSIONS[self.tab] or self.tab == "mods" then
    self.tab = version
  end
  if not self.ready[version] then
    self.saveNotice[version] = { ok = false, text = "Import the "
      .. GameVersion.info(version).displayName .. " ROM before importing a save." }
    return
  end
  local ok, res, info = require("src.import.SaveFileIO").importToSlot(source, version, force)
  if ok then
    self:_refreshSlots(version)
    self.activeSlot[version] = res
    self.slotScroll[version] = math.huge   -- pin the new row on screen (clamped in draw)
    self.saveNotice[version] = { ok = true, text = "Imported save into " .. tostring(res) .. "." }
    return
  end
  if res == nil and info and info.needsConfirm then
    -- A .sav larger than 32 KB whose first 32768 bytes checksum: the surplus
    -- is almost certainly an emulator RTC footer, so ask before truncating.
    -- The yes arm re-enters with force=true; cancel leaves the file untouched.
    self._modConfirm = {
      kind = "importOversize",
      version = version,
      source = source,
      title = "Oversized save file",
      lines = {
        ("This save is %d bytes; a cartridge save is exactly %d bytes (32 KB).")
          :format(info.size, 32768),
        "It may come from a ROM that saved the battery image with an emulator.",
        "The extra bytes would be discarded.",
        "Import it anyway?",
      },
      yesLabel = "Import anyway",
    }
    return
  end
  self.saveNotice[version] = { ok = false, text = tostring(res) }
end

-- "Import save" button: open a native .sav picker and import the pick.
-- Android mirrors ROM / mod import via love.system.pickFile("sav").
-- NX: no HostShell/desktop picker -- rescan imports/saves/ inbox instead.
function RomImporter:chooseSaveImport(version)
  if self.workState == "working" then return end
  version = self:_resolveSaveVersion(version)
  if self.isNX then
    self:ensureSavesInboxDir(version)
    self:rescanSavesAction(version)
    return
  end
  if self.nativePicker and love.system.getPickedFile then
    self.pickerPendingKind = "sav"
    self.pickerPendingVersion = version
    if not pickFile("sav") then
      self.pickerPendingKind = nil
      self.pickerPendingVersion = nil
      self.saveNotice[version] = { ok = false, text = "Could not open the file picker." }
    end
    return
  end
  if self.android then
    local name = findPendingSav(true, self.pickSkip)
    if name then
      self.androidPendingVersion = version
      self:_importSave(version, name)
      consumePick(self, name, "picked_save.sav",
        self.saveNotice[version] and self.saveNotice[version].ok)
      return
    end
    self.androidPendingVersion = version
    if not pickFile("sav") then
      self.androidPendingVersion = nil
      self.saveNotice[version] = { ok = false,
        text = "Could not open the file picker. Copy a .sav via USB." }
    else
      self.pickPending = true
      self.pickTimer = 0
    end
    return
  end
  local isHandheld = os.getenv("HANDHELD") == "1" or os.getenv("PORTMASTER") == "1"
    or os.getenv("POKEPORT_HANDHELD") == "1" or os.getenv("TRIMUI") == "1"
    or os.getenv("MUOS") == "1" or os.getenv("KNULLI") == "1"

  if isHandheld then
    local okKit, Kit = pcall(require, "src.ui.kit.Kit")
    if okKit and Kit.FileBrowser then
      self._padCursorActive = false
      Kit.FileBrowser.open({
        title = "Select Save (.sav)",
        mode = "save",
        onSelect = function(pickedPath)
          self:_importSave(version, pickedPath)
        end,
      })
      return
    end
  end

  local path = chooseSav()
  if path then
    self:_importSave(version, path)
    return
  end
  local okKit, Kit = pcall(require, "src.ui.kit.Kit")
  if okKit and Kit.FileBrowser then
    self._padCursorActive = false
    Kit.FileBrowser.open({
      title = "Select Save (.sav)",
      mode = "save",
      onSelect = function(pickedPath)
        self:_importSave(version, pickedPath)
      end,
    })
    return
  end
end

-- "Export save" button: write the active slot back out to a raw .sav in the save
-- directory's exports/ folder.  On desktop, show the path with an open-folder
-- affordance.  On Android, stage pending_export.sav and open the system
-- create-document picker (love.system.createFile) so the player can save to
-- Downloads / Drive / etc. -- the app-private exports/ path is not useful there.
-- NX: surface exports path + MTP hint; do not rely on openURL / open-folder.
function RomImporter:exportSave(version)
  if self.workState == "working" then return end
  version = self:_resolveSaveVersion(version)
  local ok, res = require("src.import.SaveFileIO").exportActiveSlot(version)
  if not ok then
    self.saveNotice[version] = { ok = false, text = tostring(res) }
    return
  end
  if self.isNX then
    local saveDir = love.filesystem.getSaveDirectory()
    local rel = RomImporter.mtpHintPath(saveDir)
    if rel ~= "" and rel:sub(-1) ~= "/" then rel = rel .. "/" end
    local outDir = exportsDir(version)
    self.saveNotice[version] = {
      ok = true,
      text = Strings("Exported to %s\nDBI MTP → 1: SD Card/%s%s/", res, rel, outDir),
    }
    return
  end
  if self.android then
    local rel = res:match("(exports[/\\].+%.[Ss][Aa][Vv])$")
      or res:match("(exports[/\\].+)$")
    local data = rel and love.filesystem.read(rel)
    if not data then
      self.saveNotice[version] = { ok = false,
        text = "Exported, but could not stage the file for the picker." }
      return
    end
    local suggested = rel:match("[^/\\]+$") or "export.sav"
    local wrote, writeErr = love.filesystem.write("pending_export.sav", data)
    if not wrote then
      self.saveNotice[version] = { ok = false,
        text = "Could not stage the export: " .. tostring(writeErr) }
      return
    end
    self.androidPendingExportVersion = version
    if love.system.createFile and love.system.createFile(suggested, love.filesystem.getSaveDirectory()) then
      self.pickPending = true
      self.pickTimer = 0
      self.saveNotice[version] = { ok = true,
        text = "Pick where to save " .. suggested .. "..." }
    else
      self.androidPendingExportVersion = nil
      self.saveNotice[version] = { ok = true,
        text = "Exported inside the app folder (picker unavailable)." }
    end
    return
  end
  local dir = res:match("^(.*)[/\\][^/\\]+$")
  self.saveNotice[version] = { ok = true, text = "Exported to " .. res, dir = dir }
end

-- Delete a save slot from the registry and disk, then refresh the panel.  If the
-- deleted slot was active, SaveData.deleteSlot points active at another slot.
function RomImporter:_deleteSlot(scope, id)
  if self.workState == "working" then return end
  local SaveData = require("src.core.SaveData")
  local cart = cartOfScope(scope)
  local ok, err
  if cart then
    ok, err = SaveData.deleteCartSlot(cart, id)
  else
    ok, err = SaveData.deleteSlot(scope, id)
  end
  if ok then
    self:_refreshSlots(scope)
    self.saveNotice[scope] = { ok = true, text = "Deleted " .. tostring(id) .. "." }
  else
    self.saveNotice[scope] = { ok = false, text = tostring(err) }
  end
end

-- Open a picker (or, on Android, scan the external folder) for a column.  The
-- version argument only titles the dialog and steers error/notice text; the
-- picked ROM is still routed by its SHA-1, so choosing a Blue cart in the Red
-- column imports Blue.
function RomImporter:choose(version)
  if self.workState == "working" then return end
  self.chooseVersion = version or "red"
  if self.isNX then
    -- Same path as the Scan again button: rescan imports/ (or show MTP hint).
    self:rescanAction(self.chooseVersion)
    return
  end
  local baseRom = self.baseRomDiscovery and self.baseRoms[self.chooseVersion]
  if baseRom then
    self.baseRoms[self.chooseVersion] = nil
    local data = love.filesystem.read(baseRom.path)
    if not data then
      self.notice = {
        version = self.chooseVersion,
        status = "The detected ROM is no longer available.",
        detail = "Choose Import ROM to select it another way.",
      }
      return
    end
    self:startData(data, baseRom.name)
    return
  end
  if self.nativePicker and love.system.getPickedFile then
    self.pickerPendingKind = "rom"
    if not pickFile("rom") then
      self.pickerPendingKind = nil
      self:setError("Could not open the file picker.")
    end
    return
  end
  if self.android then
    -- Prefer a not-yet-imported .gb/.gbc already in the save dir (USB copy, or
    -- a fresh SAF pick).  Never reuse an already-imported cart's file -- that
    -- was the #167 failure mode (second Choose just re-extracted Red).  This
    -- is a Choose, so it takes the cart that was asked for and nothing else.
    local name, data = findPendingRom(self.ready, self.chooseVersion)
    if name then
      self:startData(data, name)
    elseif consumePickedRomError(self) then
      return   -- a rejected pick explains itself instead of silently reopening
    elseif not pickFile() then
      -- Picker unavailable (API < 19, or no document-picker app installed):
      -- fall back to the USB folder-drop path as a friendly notice, not an
      -- error (which would read as a rejected file).
      self.notice = {
        version = self.chooseVersion,
        status = "No picker available, copy your ROM into:",
        detail = love.filesystem.getSaveDirectory(),
      }
    else
      self.pickPending = true
      self.pickTimer = 0
    end
    return
  end
  local isHandheld = os.getenv("HANDHELD") == "1" or os.getenv("PORTMASTER") == "1"
    or os.getenv("POKEPORT_HANDHELD") == "1" or os.getenv("TRIMUI") == "1"
    or os.getenv("MUOS") == "1" or os.getenv("KNULLI") == "1"

  if isHandheld then
    if importPendingRom(self) then return end
    local okKit, Kit = pcall(require, "src.ui.kit.Kit")
    if okKit and Kit.FileBrowser then
      self._padCursorActive = false
      Kit.FileBrowser.open({
        title = "Select " .. (GameVersion.info(self.chooseVersion).displayName or "ROM"),
        mode = "rom",
        onSelect = function(pickedPath)
          self:startPath(pickedPath)
        end,
      })
      return
    end
  end

  local path = chooseRom(GameVersion.info(self.chooseVersion).displayName)
  if path then
    self:startPath(path)
    return
  end
  if importPendingRom(self) then return end
  local okKit, Kit = pcall(require, "src.ui.kit.Kit")
  if okKit and Kit.FileBrowser then
    self._padCursorActive = false
    Kit.FileBrowser.open({
      title = "Select " .. (GameVersion.info(self.chooseVersion).displayName or "ROM"),
      mode = "rom",
      onSelect = function(pickedPath)
        self:startPath(pickedPath)
      end,
    })
    return
  end
  if love.system.getOS() == "Linux" then
    local where = love.filesystem.getSourceBaseDirectory
      and love.filesystem.getSourceBaseDirectory()
      or love.filesystem.getSource and love.filesystem.getSource()
      or "the game folder"
    self.notice = {
      version = self.chooseVersion,
      status = "No file picker. Copy your .gb/.gbc into:",
      detail = where,
    }
    return
  end
  if love.system.getOS() ~= "OS X" and love.system.getOS() ~= "Windows" then
    self:setError("File selection is unavailable here. Drop the .gb/.gbc file onto the window.")
  end
end

-- Poll the save dir for a delivered pick (picked_rom.gb / picked_mod.zip /
-- picked_save.sav / export_done.flag) and run the same import path a refocus
-- runs.  Both mobiles need this, for different reasons:
--
--   iOS     the document picker is an in-process modal sheet, so there is no
--           love.focus(true) when it dismisses -- nothing else would consume it.
--   Android the SAF picker IS a separate activity and normally does refocus,
--           but Android may destroy GameActivity while it is up, in which case
--           the app restarts and that focus event never comes.  Polling makes
--           the outcome the same either way instead of leaving the pick on disk
--           for the next tap to find, which is what made users import twice and
--           what made it look random: it depends on memory pressure (#553).
--
-- Deliberately NO timeout.  A version of this disarmed the poll after 120s so a
-- cancelled picker would stop scanning, which was wrong on iOS: the picker there
-- is an in-process modal sheet, so update() keeps running while it is open and
-- the window burned down while the player was still browsing Files.  The pick
-- then landed with nothing armed to consume it, and because every path here is
-- silent on success the import just did not happen, with no error shown.  A
-- half-second directory listing on a menu screen is far cheaper than an import
-- that vanishes, so the poll stays armed until something is actually consumed.

function RomImporter:_pollPickedFiles(dt)
  if not self.pickPending then return end
  if self.workState == "working" then return end
  self.pickTimer = (self.pickTimer or 0) + dt
  if self.pickTimer < 0.5 then return end
  self.pickTimer = 0
  -- The Swift bridge reports a failed pick copy through pick_error.txt;
  -- surface it on whichever tab the player is looking at rather than
  -- letting the pick silently do nothing.
  local pickError = love.filesystem.read("pick_error.txt")
  if pickError then
    love.filesystem.remove("pick_error.txt")
    self.pickPending = nil
    self.modNotice = { ok = false, text = pickError }
    self.notice = { version = self.chooseVersion or "red",
                    status = "File import failed:", detail = pickError }
    return
  end
  local found = love.filesystem.getInfo("export_done.flag", "file") ~= nil
    or love.filesystem.getInfo("pick_error.flag", "file") ~= nil
    or love.filesystem.getInfo(PICK_COMPLETE_FILENAME, "file") ~= nil
  if not found then
    for _, name in ipairs(love.filesystem.getDirectoryItems("")) do
      local n = name:lower()
      if n:match("%.gbc?$") or n == "picked_mod.zip" or n == "picked_save.sav"
          or n == "picked_required_import.bin" or n == "picked_stadium.z64" then
        found = true
        break
      end
    end
  end
  if found then
    self.pickPending = nil
    self:focus(true)
  end
end

function RomImporter:update(dt)
  self.pulse = self.pulse + dt
  if not Transition.armed then
    self._motionFrames = (self._motionFrames or 0) + 1
    if self._motionFrames > 1 then Transition.armed = true end
  end
  if self._launchFade then
    self._launchFade.elapsed = self._launchFade.elapsed + dt
    if self._launchFade.elapsed >= self._launchFade.duration then
      local version = self._launchFade.version
      self._launchFade = nil
      self:play(version)
      return
    end
  end
  self:_updatePadCursor(dt)
  self:_stepBaseRomScan()
  -- Pump the FlexLove view (input polling + the queued click actions).  The
  -- flag is only set once draw() has built a tree, so headless runs and the
  -- test tier never touch the toolkit.
  if self._flex then
    require("src.import.LauncherView").update(self, dt)
  end
  -- Drive every in-flight async fetch.  These are the operations that used to
  -- run synchronously inside draw and freeze the window; each pump is a
  -- non-blocking channel poll, so a frame with nothing in flight costs
  -- nothing.  They run whether or not the view is up, so a refresh started
  -- before a tab switch still completes.
  self:_pumpFindFetch()
  self:_pumpFindDetails()
  self:_pumpModInfoFetch()
  self:_queueFindEnrichment()
  self:_pumpFindStats()
  self:_pumpFindThumbs()
  self:_pumpSkinFetch()
  self:_pumpSync(dt)
  self:_pumpOnline(dt)
  self:_pumpModCheck()
  self:_pumpModInstall()
  self:_pumpCartInstall()
  self:_pumpCartFill()
  self:_pumpUpdateAll()
  self:_pumpExtract()
  -- Dev harness: POKEPORT_LAUNCHER_SHOT=/path.png resizes the window from
  -- POKEPORT_WIN=WxH, lets the view settle, then captures one frame and
  -- quits, so a scripted run can see the real launcher at any window shape
  -- (the frame drivers all bypass the interactive launcher).
  local shot = os.getenv("POKEPORT_LAUNCHER_SHOT")
  if shot and not self._shotDone then
    if not self._shotSized then
      self._shotSized = true
      if os.getenv("POKEPORT_REDUCE_MOTION") ~= "0" then
        Transition.reduceMotion = true
      end
      local w, h = (os.getenv("POKEPORT_WIN") or ""):match("^(%d+)x(%d+)$")
      if w and love.window and love.window.setMode then
        pcall(love.window.setMode, tonumber(w), tonumber(h),
          { resizable = true })
      end
      local tab = os.getenv("POKEPORT_LAUNCHER_TAB")
      if tab and tab ~= "" then self:_switchTab(tab) end
      -- POKEPORT_LAUNCHER_CONFIRM=1 arms a representative install confirm so
      -- a capture can see the modal (it is otherwise only reachable by click)
      if os.getenv("POKEPORT_LAUNCHER_CONFIRM") == "1" then
        self._modConfirm = {
          kind = "update",
          title = "Install mod",
          yesLabel = "Install",
          lines = { "JP GREEN - Poketto Monsuta Midori v0.4.4",
                    "by bryanthaboi",
                    "Mods are not reviewed - trust the author." },
        }
      end
      -- POKEPORT_LAUNCHER_SETTINGS=1 opens the gear panel, the other layout
      -- a capture cannot otherwise reach without a click.  Pair it with
      -- POKEPORT_LAUNCHER_SETTINGS_PAGE to land on a page past the first.
      if os.getenv("POKEPORT_LAUNCHER_SETTINGS") == "1" then
        self:_openSettings()
      end
      if os.getenv("POKEPORT_LAUNCHER_BUG") == "1" then
        self:_openBugPanel()
      end
      -- POKEPORT_LAUNCHER_FIND_KIND=mods|carts picks which half of the feed
      -- the FIND tab is browsing; the switch is otherwise only a click.
      local findKind = os.getenv("POKEPORT_LAUNCHER_FIND_KIND")
      if findKind and findKind ~= "" then self:_setFindKind(findKind) end
      local query = os.getenv("POKEPORT_LAUNCHER_QUERY")
      if query and query ~= "" then
        self.findQuery = query
        self._findSearchFocus = true
      end
      -- POKEPORT_LAUNCHER_TYPE feeds one character per frame through the
      -- real textinput path, reproducing typed (per-frame growing) text
      -- rather than text set once before the first frame.
      self._shotType = os.getenv("POKEPORT_LAUNCHER_TYPE")
      if self._shotType and self._shotType ~= "" then
        self._findSearchFocus = true
        self._shotTypeAt = 0
      end
    end
    if self._shotType and self._shotTypeAt then
      self._shotTypeAt = self._shotTypeAt + 1
      if self._shotTypeAt % 3 == 0 then
        local n = math.floor(self._shotTypeAt / 3)
        if n <= #self._shotType then
          self:textinput(self._shotType:sub(n, n))
        end
      end
      if os.getenv("POKEPORT_LAUNCHER_SETTINGS") == "1" then
        self:_openSettings()
      end
    end
    self._shotTimer = (self._shotTimer or 0) + dt
    -- POKEPORT_WIN2=WxH resizes mid-run, with UI state already settled, so
    -- the capture exercises the live-resize path and not just first boot.
    if not self._shotResized and self._shotTimer > 0.6 then
      self._shotResized = true
      local w2, h2 = (os.getenv("POKEPORT_WIN2") or ""):match("^(%d+)x(%d+)$")
      if w2 and love.window and love.window.setMode then
        pcall(love.window.setMode, tonumber(w2), tonumber(h2),
          { resizable = true })
      end
    end
    local motion = os.getenv("POKEPORT_LAUNCHER_MOTION")
    if motion and motion ~= "" and not self._shotMotionAt
        and self._shotTimer > 0.9 then
      self._shotMotionAt = 0
      local ms = tonumber(os.getenv("POKEPORT_MOTION_MS") or "")
      if ms and ms > 0 then
        for kind in pairs(Transition.DURATIONS) do
          Transition.DURATIONS[kind] = ms / 1000
        end
      end
      if motion:match("^go:") then
        local okOP, OP = pcall(require, "src.import.OnlinePanel")
        if okOP then OP.go(self, motion:sub(4)) end
      elseif motion == "modal-close" then
        self._modConfirm = nil
      elseif motion == "modal" then
        self._modConfirm = {
          kind = "update", title = "Install mod", yesLabel = "Install",
          lines = { "JP GREEN - Poketto Monsuta Midori v0.4.4",
                    "by bryanthaboi",
                    "Mods are not reviewed - trust the author." },
        }
      else
        self:_switchTab(motion)
      end
    end
    if self._shotMotionAt then
      self._shotMotionAt = self._shotMotionAt + 1
      local want = tonumber(os.getenv("POKEPORT_LAUNCHER_SHOT_SEQ") or "4") or 4
      if self._shotMotionAt <= want then
        local path = (shot:gsub("%.png$", ""))
          .. "-" .. self._shotMotionAt .. ".png"
        love.graphics.captureScreenshot(function(imagedata)
          local fd = imagedata:encode("png")
          local f = io.open(path, "wb")
          if f then f:write(fd:getString()) f:close() end
        end)
      else
        self._shotDone = true
        love.event.quit()
      end
    elseif self._shotTimer > 1.2 then
      self._shotDone = true
      love.graphics.captureScreenshot(function(imagedata)
        local fd = imagedata:encode("png")
        local f = io.open(shot, "wb")
        if f then f:write(fd:getString()) f:close() end
        love.event.quit()
      end)
    end
  end
  if self.nativePicker and love.system.getPickedFile and self.workState ~= "working" then
    local path = love.system.getPickedFile()
    if path then
      local kind = self.pickerPendingKind or "rom"
      local version = self.pickerPendingVersion
      self.pickerPendingKind = nil
      self.pickerPendingVersion = nil
      if kind == "required_import" then
        local modId, importId = self.pickerPendingModId, self.pickerPendingImportId
        self.pickerPendingModId, self.pickerPendingImportId = nil, nil
        if modId and importId then self:_importRequiredSource(modId, importId, path) end
        if Platform.isUWP() then os.remove(path) end
      elseif kind == "mod" then
        self:_installMod(path)
        if Platform.isUWP() and self.modNotice and self.modNotice.ok then
          os.remove(path)
        end
      elseif kind == "skin" then
        self:_installSkinZip(path)
        if Platform.isUWP() and self._skinNotice and self._skinNotice.ok then
          os.remove(path)
        end
      elseif kind == "sav" then
        local target = version or self:_savedropTarget()
        self:_importSave(target, path)
        if Platform.isUWP() and self.saveNotice[target] and self.saveNotice[target].ok then
          os.remove(path)
        end
      else
        self:startPath(path)
        if Platform.isUWP() then os.remove(path) end
      end
    elseif love.system.getPickError then
      local errorText = love.system.getPickError()
      if errorText then
        local kind = self.pickerPendingKind or "rom"
        local version = self.pickerPendingVersion or self:_savedropTarget()
        self.pickerPendingKind = nil
        self.pickerPendingVersion = nil
        if kind == "required_import" then
          self.modNotice = { ok = false, text = errorText }
          self.pickerPendingModId, self.pickerPendingImportId = nil, nil
        elseif kind == "mod" then
          self.modNotice = { ok = false, text = errorText }
        elseif kind == "skin" then
          self._skinNotice = { ok = false, text = errorText }
        elseif kind == "sav" then
          self.saveNotice[version] = { ok = false, text = errorText }
        else
          self:setError(errorText)
        end
      end
    end
  end
  self:_pollPickedFiles(dt)
  if self.workState ~= "working" or not self.worker then return end
  local started = love.timer.getTime()
  repeat
    local ok, workerError = coroutine.resume(self.worker)
    if not ok then
      print(debug.traceback(self.worker, tostring(workerError)))
      self:setError(tostring(workerError))
      return
    end
    if coroutine.status(self.worker) == "dead" then
      self.worker = nil
      return
    end
  until love.timer.getTime() - started >= 0.008
end

-- ------- gamepad virtual cursor (handheld / PortMaster) --------------------
local PAD_DEAD = 0.28
local PAD_SPEED = 560   -- px/s at full stick deflection
local PAD_DPAD_SPEED = 420

function RomImporter:_consolePointerHost()
  return (self.isNX or Platform.isUWP()) and true or false
end

function RomImporter:_activatePadCursor()
  if self._padCursorActive then return end
  local ox, oy, w, h = SafeArea.rect()
  if not self._padInited then
    self._padCursor.x = ox + w * 0.5
    self._padCursor.y = oy + h * 0.45
    self._padInited = true
  end
  self._padCursorActive = true
end

-- NX: FlexLove hover/hit-test polls love.mouse.getPosition every interactive
-- element. Warping via setPosition every stick frame is expensive on love-nx
-- and makes the virtual cursor lag. Expose the pad pointer through a getPosition
-- shim instead; desktop keeps the setPosition path unchanged.
function RomImporter:_ensureNxPointerBridge()
  if not self:_consolePointerHost() or self._nxPointerBridge then return end
  if not (love and love.mouse and love.mouse.getPosition) then return end
  self._nxRealGetPosition = love.mouse.getPosition
  local importer = self
  love.mouse.getPosition = function()
    if importer._padCursorActive then
      return importer._padCursor.x, importer._padCursor.y
    end
    return importer._nxRealGetPosition()
  end
  self._nxPointerBridge = true
end

function RomImporter:_restoreNxPointerBridge()
  if not self._nxPointerBridge then return end
  if love and love.mouse and self._nxRealGetPosition then
    love.mouse.getPosition = self._nxRealGetPosition
  end
  self._nxPointerBridge = false
  self._nxRealGetPosition = nil
end

-- NX only: drop the getPosition shim + hide the virtual cursor before a host
-- takes over input (embedded save editor). Desktop is a no-op.
function RomImporter:parkNxPointerForHost()
  if not self:_consolePointerHost() then return end
  self._padCursorActive = false
  self:_restoreNxPointerBridge()
end

-- Temporary overlay handoff (Edit Save / Touch Controls): restore the system
-- arrow cursor, hide the virtual pad pointer, tear down FlexLove when the
-- view is already loaded, and drop the NX getPosition shim.  Play uses
-- resetPointerCursor + detach directly because it never returns here.
function RomImporter:prepareOverlayHandoff()
  resetPointerCursor(self)
  self._padCursorActive = false
  self:_forgetActiveSkin()
  -- Avoid requiring LauncherView from headless unit tests (no luautf8).  In
  -- a real session draw() has already loaded it, so detach runs normally.
  if self._flex and package.loaded["src.import.LauncherView"] then
    require("src.import.LauncherView").detach(self)
  else
    self._flex = nil
    self:parkNxPointerForHost()
  end
end

-- EXIT GAME / Close editor leave the confirming finger still down, often
-- sitting where Import Save is drawn.  The launcher must not treat that
-- leftover hold as a new press once a short suppress window expires
-- (#2079): update() would then arm on the still-down pointer and the
-- later lift would open the system file picker.  Swallow this gesture
-- (held mouse, already-down touches) and debounce clicks briefly.
local RETURN_POINTER_HOLD = 0.5

function RomImporter:ignoreReturningPointer()
  local now = 0
  if love.timer and love.timer.getTime then
    now = love.timer.getTime()
  end
  self._suppressClickUntil = now + RETURN_POINTER_HOLD
  self._suppressMouseUntil = now + RETURN_POINTER_HOLD
  self._clickPt = nil
  self._mouseAt = nil
  self._touchAt = nil
  -- Already-down is not a rising edge.  Always mark the poll as held so
  -- the first frame after remount cannot mint a press from a leftover.
  self._prevMouseDown = true
  local ignore = {}
  if love.touch and love.touch.getTouches then
    local ok, ids = pcall(love.touch.getTouches)
    if ok and type(ids) == "table" then
      for i = 1, #ids do
        ignore[tostring(ids[i])] = true
      end
    end
  end
  self._ignoreTouch = ignore
  if package.loaded["src.ui.kit.Kit"] then
    local Kit = require("src.ui.kit.Kit")
    if Kit.dragEnd then pcall(Kit.dragEnd) end
  end
end

-- After an overlay closes: re-arm the pad cursor when a stick is already
-- connected so NX / handhelds are not stranded without a pointer until the
-- next stick bump (same class of bug as opening Touch Controls).
function RomImporter:resumeAfterOverlay()
  self:ignoreReturningPointer()
  if not self.launcher then return end
  if not (love.joystick and love.joystick.getJoystickCount) then return end
  if love.joystick.getJoystickCount() <= 0 then return end
  local osName = (love.system and love.system.getOS and love.system.getOS()) or ""
  if osName == "Linux" or self.isNX then
    self:_activatePadCursor()
  end
end

function RomImporter:_cycleTab(delta)
  local order = { "mods", "find", "skins" }
  for i = #GameVersion.ORDER, 1, -1 do
    table.insert(order, 1, GameVersion.ORDER[i])
  end
  local idx = 1
  for i, id in ipairs(order) do
    if id == self.tab then idx = i; break end
  end
  self:_switchTab(order[((idx - 1 + delta) % #order) + 1])
end

local STICK_NAV_ON = 0.5
local STICK_NAV_OFF = 0.3
local STICK_NAV_DELAY = 0.28
local STICK_NAV_REPEAT = 0.12

function RomImporter:_stickNavDir()
  local nav = self._stickNav
  local on = (nav and nav.dir) and STICK_NAV_OFF or STICK_NAV_ON
  local ax = self._padAxis.leftx or 0
  local ay = self._padAxis.lefty or 0
  if math.abs(ax) >= math.abs(ay) then
    if math.abs(ax) > on then return ax > 0 and "right" or "left" end
  else
    if math.abs(ay) > on then return ay > 0 and "down" or "up" end
  end
  if self._padDir.dpleft then return "left" end
  if self._padDir.dpright then return "right" end
  if self._padDir.dpup then return "up" end
  if self._padDir.dpdown then return "down" end
  return nil
end

function RomImporter:_navigateWithStick(dt, Kit)
  local nav = self._stickNav
  if not nav then nav = {}; self._stickNav = nav end
  local dir = self:_stickNavDir()
  if not dir then
    nav.dir, nav.t, nav.fired = nil, 0, false
    return
  end
  if nav.dir ~= dir then
    nav.dir, nav.t, nav.fired = dir, 0, false
    if Kit then Kit.navigate(dir) end
    return
  end
  nav.t = (nav.t or 0) + dt
  if nav.t >= (nav.fired and STICK_NAV_REPEAT or STICK_NAV_DELAY) then
    nav.t, nav.fired = 0, true
    if Kit then Kit.navigate(dir) end
  end
end

function RomImporter:_updatePadCursor(dt)
  local okKit, Kit = pcall(require, "src.ui.kit.Kit")
  if okKit then
    if (Kit.FileBrowser and Kit.FileBrowser.active)
        or (Kit.VirtualKeyboard and Kit.VirtualKeyboard.active) then
      return
    end
  end

  if self:_consolePointerHost() then
    self:_ensureNxPointerBridge()
    -- Cap dt so a hitch in the FlexLove immediate-mode frame does not fling
    -- the cursor; desktop keeps raw dt (setPosition path already smooth there).
    if dt > 1 / 30 then dt = 1 / 30 end
  end

  -- Real mouse motion yields the pad cursor so desktop users keep a normal
  -- pointer after bumping a stick once. On NX this must stay off: love-nx /
  -- SDL often drifts the system mouse with the stick (or touch), and axis
  -- events are not every frame, so yield+reactivate flickers the overlay.
  if not self:_consolePointerHost() then
    local mx, my = love.mouse.getPosition()
    if self._lastMouseX and self._padCursorActive then
      if math.abs(mx - self._lastMouseX) > 3 or math.abs(my - self._lastMouseY) > 3 then
        self._padCursorActive = false
      end
    end
    self._lastMouseX, self._lastMouseY = mx, my
  end

  if not self._padCursorActive and not self.isNX
      and (Platform.isUWP() or self._padNavChosen) then
    self:_navigateWithStick(dt, okKit and Kit or nil)
    local scrollY = self._padAxis.righty or 0
    if math.abs(scrollY) > PAD_DEAD and self._flex then
      require("src.import.LauncherView").wheelmoved(self, 0, -scrollY * 8 * dt)
    end
    return
  end
  self._stickNav = nil

  local ax = self._padAxis.leftx or 0
  local ay = self._padAxis.lefty or 0
  local dx, dy = 0, 0
  if math.abs(ax) > PAD_DEAD then dx = dx + ax end
  if math.abs(ay) > PAD_DEAD then dy = dy + ay end
  if self._padDir.dpleft then dx = dx - 1 end
  if self._padDir.dpright then dx = dx + 1 end
  if self._padDir.dpup then dy = dy - 1 end
  if self._padDir.dpdown then dy = dy + 1 end

  if dx ~= 0 or dy ~= 0 then
    self:_activatePadCursor()
    local mag = math.sqrt(dx * dx + dy * dy)
    if mag > 1 then dx, dy = dx / mag, dy / mag end
    local speed = (math.abs(ax) > PAD_DEAD or math.abs(ay) > PAD_DEAD)
      and PAD_SPEED or PAD_DPAD_SPEED
    local ox, oy, w, h = SafeArea.rect()
    local nx = self._padCursor.x + dx * speed * dt
    local ny = self._padCursor.y + dy * speed * dt
    self._padCursor.x = math.max(ox, math.min(ox + w, nx))
    self._padCursor.y = math.max(oy, math.min(oy + h, ny))
    local overY = 0
    if ny > oy + h then overY = ny - (oy + h)
    elseif ny < oy then overY = ny - oy end
    if math.abs(ay) > PAD_DEAD and not self._padStickCentered then overY = 0 end
    if overY ~= 0 and self._flex then
      require("src.import.LauncherView").wheelmoved(self, 0, -overY / 48)
    end
    if not self:_consolePointerHost() and love.mouse.setPosition then
      pcall(love.mouse.setPosition, self._padCursor.x, self._padCursor.y)
      self._lastMouseX, self._lastMouseY = self._padCursor.x, self._padCursor.y
    end
  end

  local ry = self._padAxis.righty or 0
  if math.abs(ry) > PAD_DEAD and self._flex then
    self:_activatePadCursor()
    require("src.import.LauncherView").wheelmoved(self, 0, -ry * 8 * dt)
  end
end

function RomImporter:gamepadpressed(_, button)
  if Transition.active() then return end
  local action =(GamepadMap.mapLauncherButton and GamepadMap.mapLauncherButton(button)) or button
  local okKit, Kit = pcall(require, "src.ui.kit.Kit")
  if okKit then
    if Kit.VirtualKeyboard and Kit.VirtualKeyboard.active then
      if Kit.VirtualKeyboard.gamepadpressed(action) then return end
    end
    if Kit.FileBrowser and Kit.FileBrowser.active then
      if Kit.FileBrowser.gamepadpressed(action) then return end
    end
  end

  -- Y button toggle between Native Controller Navigation and Virtual Pointer Cursor:
  if action == "y" or button == "y" then
    self._padCursorActive = not self._padCursorActive
    self._padNavChosen = not self._padCursorActive
    if okKit then Kit._ringShown = not self._padCursorActive end
    self._cursorModeToast = self._padCursorActive and "Cursor Navigation [Y]" or "Controller Menu Navigation [Y]"
    self._cursorModeToastTime = love.timer.getTime()
    return
  end

  -- Select button: toggle Virtual Keyboard on handhelds
  if button == "back" or button == "select" or action == "select" then
    local isHandheld = os.getenv("HANDHELD") == "1" or os.getenv("PORTMASTER") == "1"
      or os.getenv("POKEPORT_HANDHELD") == "1" or os.getenv("TRIMUI") == "1"
      or os.getenv("MUOS") == "1" or os.getenv("KNULLI") == "1"
      or os.getenv("POKEPORT_SBC") == "1" or os.getenv("ANBERNIC") == "1"
    if not isHandheld then return end
    if okKit and Kit.VirtualKeyboard then
      if Kit.VirtualKeyboard.active then
        Kit.VirtualKeyboard.close(false)
        return
      end
      if self._indexPrompt then
        Kit.VirtualKeyboard.open({
          text = self._indexPrompt.text or "",
          title = "Add a mod index",
          onDone = function(newText, confirmed)
            if confirmed and self._indexPrompt then self._indexPrompt.text = newText end
          end
        })
        return
      elseif self._rename then
        Kit.VirtualKeyboard.open({
          text = self._rename.text or "",
          title = "Name save slot",
          onDone = function(newText, confirmed)
            if confirmed and self._rename then self._rename.text = newText end
          end
        })
        return
      elseif self._profileRenamePrompt then
        Kit.VirtualKeyboard.open({
          text = self._profileRenamePrompt.text or "",
          title = "Rename profile",
          onDone = function(newText, confirmed)
            if confirmed and self._profileRenamePrompt then self._profileRenamePrompt.text = newText end
          end
        })
        return
      elseif self._profileSavePrompt then
        Kit.VirtualKeyboard.open({
          text = self._profileSavePrompt.text or "",
          title = "Save mod profile",
          onDone = function(newText, confirmed)
            if confirmed and self._profileSavePrompt then self._profileSavePrompt.text = newText end
          end
        })
        return
      elseif self._settingsText then
        Kit.VirtualKeyboard.open({
          text = self._settingsText.text or "",
          title = (self._settingsText.row and self._settingsText.row.label) or "Edit Text",
          onDone = function(newText, confirmed)
            if confirmed and self._settingsText then self._settingsText.text = newText end
          end
        })
        return
      elseif self.tab == "find" then
        Kit.VirtualKeyboard.open({
          text = self.findQuery or "",
          title = "Search Mods",
          onDone = function(newText, confirmed)
            if confirmed then
              self.findQuery = newText
              if self._refreshFind then self:_refreshFind() end
            end
          end
        })
        return
      else
        Kit.VirtualKeyboard.open({
          text = "",
          title = "Virtual Keyboard",
          onDone = function() end
        })
        return
      end
    end
  end

  -- Shoulder buttons: cycle tabs
  if button == "leftshoulder" then
    self:_cycleTab(-1)
    return
  elseif button == "rightshoulder" then
    self:_cycleTab(1)
    return
  end

  -- Triggers (L2 / R2): fast scroll content / lists up and down
  if button == "triggerleft" or button == "lefttrigger" or button == "l2"
      or action == "triggerleft" or action == "l2" then
    require("src.import.LauncherView").wheelmoved(self, 0, 4)
    return
  elseif button == "triggerright" or button == "righttrigger" or button == "r2"
      or action == "triggerright" or action == "r2" then
    require("src.import.LauncherView").wheelmoved(self, 0, -4)
    return
  end

  -- Start button: Play / Choose ROM
  if button == "start" then
    if self.workState == "working" then return end
    local version = self.tab
    if GameVersion.VERSIONS[version] then
      if self.ready[version] then self:play(version) else self:_romAction(version) end
    end
    return
  end

  if not self._padCursorActive and not self.isNX then
    if okKit then Kit._ringShown = true end
    if action == "a" then
      if okKit and Kit.focusId then
        Kit.activateFocused()
      elseif self._flex then
        require("src.import.LauncherView").clickAt(self,
          self._padCursor.x, self._padCursor.y)
      end
      return
    elseif action == "b" then
      if self._bugModal then self:_closeBugPanel(); return end
      if self.tab == "online" then
        local okOnline, OnlinePanel = pcall(require, "src.import.OnlinePanel")
        if okOnline and OnlinePanel.back(self) then return end
      end
      if self._indexPrompt then self._indexPrompt = nil; self:_disarmTextInput(); return
      elseif self._rename then self._rename = nil; self:_disarmTextInput(); return
      elseif self._profileRenamePrompt then self._profileRenamePrompt = nil; self:_disarmTextInput(); return
      elseif self._profileSavePrompt then self._profileSavePrompt = nil; self:_disarmTextInput(); return
      elseif self._settingsText then self._settingsText = nil; self:_disarmTextInput(); return
      end
    elseif button == "dpup" or action == "dpup" then
      if okKit then Kit.navigate("up") end
      return
    elseif button == "dpdown" or action == "dpdown" then
      if okKit then Kit.navigate("down") end
      return
    elseif button == "dpleft" or action == "dpleft" then
      if okKit then Kit.navigate("left") end
      return
    elseif button == "dpright" or action == "dpright" then
      if okKit then Kit.navigate("right") end
      return
    end
  else
    self:_activatePadCursor()
    if action == "a" then
      if self._flex then
        require("src.import.LauncherView").clickAt(self,
          self._padCursor.x, self._padCursor.y)
      end
    elseif action == "b" then
      if self._bugModal then self:_closeBugPanel(); return end
      if self.tab == "online" then
        local okOnline, OnlinePanel = pcall(require, "src.import.OnlinePanel")
        if okOnline and OnlinePanel.back(self) then return end
      end
      if self._indexPrompt then self._indexPrompt = nil; self:_disarmTextInput(); return
      elseif self._rename then self._rename = nil; self:_disarmTextInput(); return
      elseif self._profileRenamePrompt then self._profileRenamePrompt = nil; self:_disarmTextInput(); return
      elseif self._profileSavePrompt then self._profileSavePrompt = nil; self:_disarmTextInput(); return
      elseif self._settingsText then self._settingsText = nil; self:_disarmTextInput(); return
      end
    elseif button == "dpup" or button == "dpdown"
        or button == "dpleft" or button == "dpright" then
      self._padDir[button] = true
    end
  end
end

function RomImporter:gamepadreleased(_, button)
  if button == "dpup" or button == "dpdown"
      or button == "dpleft" or button == "dpright" then
    self._padDir[button] = nil
  end
end

function RomImporter:gamepadaxis(_, axis, value)
  if axis == "leftx" or axis == "lefty" or axis == "righty" then
    self._padAxis[axis] = value
    if self._padCursorActive and math.abs(value) > PAD_DEAD then
      self:_activatePadCursor()
    elseif axis == "lefty" and math.abs(value) <= PAD_DEAD then
      self._padStickCentered = true
    end
  elseif axis == "triggerleft" or axis == "lefttrigger" then
    if value > 0.4 then
      if not self._l2TriggerActive then
        require("src.import.LauncherView").wheelmoved(self, 0, 4)
        self._l2TriggerActive = true
      end
    elseif value < 0.2 then
      self._l2TriggerActive = false
    end
  elseif axis == "triggerright" or axis == "righttrigger" then
    if value > 0.4 then
      if not self._r2TriggerActive then
        require("src.import.LauncherView").wheelmoved(self, 0, -4)
        self._r2TriggerActive = true
      end
    elseif value < 0.2 then
      self._r2TriggerActive = false
    end
  end
end

-- Same gate as src/core/Input.lua: a pad SDL can map already reached
-- gamepadpressed this frame, so re-entering it from the raw event would
-- fire the virtual cursor's click twice off one A press (#620).
function RomImporter:joystickpressed(joystick, button)
  if GamepadMap.ignoreRawForJoystick(joystick) then return end
  if GamepadMap.isAccelerometer(joystick) then return end
  local padButton = GamepadMap.mapRawToGamepadButton(button)
  if padButton then self:gamepadpressed(joystick, padButton) end
end

function RomImporter:joystickreleased(joystick, button)
  if GamepadMap.ignoreRawForJoystick(joystick) then return end
  if GamepadMap.isAccelerometer(joystick) then return end
  local padButton = GamepadMap.mapRawToGamepadButton(button)
  if padButton then self:gamepadreleased(joystick, padButton) end
end

function RomImporter:joystickaxis(joystick, axis, value)
  if GamepadMap.ignoreRawForJoystick(joystick) then return end
  if GamepadMap.isAccelerometer(joystick) then return end
  if axis == 1 then
    self:gamepadaxis(joystick, "leftx", value)
  elseif axis == 2 then
    self:gamepadaxis(joystick, "lefty", value)
  elseif axis == 3 or axis == 5 then
    if value > 0.4 then
      if not self._l2RawActive then
        require("src.import.LauncherView").wheelmoved(self, 0, 4)
        self._l2RawActive = true
      end
    elseif value < 0.2 then
      self._l2RawActive = false
    end
  elseif axis == 4 or axis == 6 then
    if value > 0.4 then
      if not self._r2RawActive then
        require("src.import.LauncherView").wheelmoved(self, 0, -4)
        self._r2RawActive = true
      end
    elseif value < 0.2 then
      self._r2RawActive = false
    end
  end
end

function RomImporter:joystickhat(joystick, hat, direction)
  if GamepadMap.ignoreRawForJoystick(joystick) then return end
  if GamepadMap.isAccelerometer(joystick) then return end
  for _, dir in ipairs(self._rawHatDirs[hat] or {}) do
    self._padDir[dir] = nil
  end
  local dirs = ({
    u = { "dpup" }, d = { "dpdown" }, l = { "dpleft" }, r = { "dpright" },
    lu = { "dpleft", "dpup" }, ru = { "dpright", "dpup" },
    ld = { "dpleft", "dpdown" }, rd = { "dpright", "dpdown" },
  })[direction] or {}
  for _, dir in ipairs(dirs) do self._padDir[dir] = true end
  self._rawHatDirs[hat] = dirs
end

-- Player pressed Play on a game whose ROM is imported: hand off to boot.
function RomImporter:play(version, fade)
  if self.workState == "working" then return end
  if not self.ready[version] then return end
  if fade then
    if not self._launchFade then
      self._launchFade = { version = version, elapsed = 0, duration = 0.24 }
    end
    return
  end
  self._handedOff = true
  -- #835: remember the game being launched so the next launcher start opens on
  -- its column (_applyLastVersionTab).  It rides options.lua rather than a file
  -- of its own, so portable installs and POKEPORT_IDENTITY sandboxes keep it
  -- with the rest of the launcher's persisted state.  A failed write only
  -- costs the memory of the choice, so it must never block the boot.
  local cartId = self.activeCart and self.activeCart[version] or nil
  pcall(function()
    local SaveData = require("src.core.SaveData")
    local opts = SaveData.loadOptions()
    opts.lastVersion = version
    local map = self:_activeCartMap()
    opts.activeCart = next(map) ~= nil and map or nil
    SaveData.saveOptions(opts)
  end)
  resetPointerCursor(self)
  -- The game draws with raw love.graphics from here on; drop the view's
  -- element tree and canvases before the handoff.
  if self._flex then require("src.import.LauncherView").detach(self) end
  if self.onComplete then self.onComplete(version, cartId) end
end

function RomImporter:_activeCartMap()
  local out = {}
  for version, id in pairs(self.activeCart or {}) do
    if GameVersion.VERSIONS[version] and type(id) == "string" then
      out[version] = id
    end
  end
  return out
end

-- "re-import" a column: drop it back to the choose/drop state so a fresh ROM
-- can be selected (the extract replaces that version's cache).
function RomImporter:reimport(version)
  if self.workState == "working" then return end
  if not self.ready[version] then return end
  self.ready[version] = false
  self.returning[version] = false
  self.chooseVersion = version
  if self.baseRomDiscovery then
    self.baseRoms[version] = nil
    self:_queueBaseRomScan()
  end
end

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

-- UTF-8 helpers for the slot-rename field (#205).  The `utf8` library only
-- exists inside LOVE (plain luajit, which loads this module in tests, has
-- none), so codepoint walking is done by hand -- the same lead-byte width
-- classes GenSave's encodeName uses.  utf8Back drops the last codepoint;
-- utf8Cap truncates to maxChars whole codepoints.
local function utf8Back(t)
  local i = #t
  while i > 0 do
    local b = t:byte(i)
    i = i - 1
    if b < 0x80 or b >= 0xC0 then break end -- lead or ASCII: dropped, done
  end
  return t:sub(1, i)
end
local function utf8Cap(t, maxChars)
  local count, i = 0, 1
  while i <= #t do
    count = count + 1
    if count > maxChars then return t:sub(1, i - 1) end
    local b = t:byte(i)
    i = i + ((b < 0x80) and 1 or (b < 0xE0) and 2 or (b < 0xF0) and 3 or 4)
  end
  return t
end

-- Page-scroll arithmetic, kept pure (no love, no self) so the engine tier can
-- pin it: given how tall the column under the tab bar wants to be and how much
-- room is left under it, say whether the page scrolls, where it sits, and how
-- far it can go.  A window that grew back pulls the offset down with it rather
-- than leaving the page parked past its own end.
function RomImporter.pageScrollFor(naturalH, viewportH, scroll)
  local maxPage = math.max(0, (naturalH or 0) - math.max(0, viewportH or 0))
  return maxPage > 0, clamp(scroll or 0, 0, maxPage), maxPage
end


-- The whole launcher surface is the FlexLove view (src/import/LauncherView):
-- it rebuilds the element tree from this importer's state every frame and
-- renders it.  Required lazily so a headless test require of this module
-- never loads the UI toolkit.
-- Dev harness: POKEPORT_LAUNCHER_PROF=<frames> times the view's build+draw
-- for that many frames, prints mean/median/p95/worst to stdout and quits.
-- Pair with POKEPORT_LAUNCHER_TAB / POKEPORT_WIN to profile a specific panel.
local profN, profSamples = tonumber(os.getenv("POKEPORT_LAUNCHER_PROF") or ""), {}

function RomImporter:draw()
  local View = require("src.import.LauncherView")
  if not profN then return View.draw(self) end
  local t0 = love.timer.getTime()
  View.draw(self)
  profSamples[#profSamples + 1] = (love.timer.getTime() - t0) * 1000
  if #profSamples >= profN + 30 then
    local s = {}
    for i = 31, #profSamples do s[#s + 1] = profSamples[i] end -- drop warmup
    table.sort(s)
    local sum = 0
    for _, v in ipairs(s) do sum = sum + v end
    io.stderr:write(("PROF frames=%d mean=%.2fms median=%.2fms p95=%.2fms worst=%.2fms\n")
      :format(#s, sum / #s, s[math.ceil(#s * 0.5)], s[math.ceil(#s * 0.95)], s[#s]))
    io.stderr:flush()
    love.event.quit()
  end
end

-- Nothing in the launcher can undo a delete, so every Delete control asks
-- twice: the first press arms it, a second press on the SAME target inside
-- the window commits, and any other queued action disarms it (#433; the view
-- routes every non-delete action through a disarm).
local DELETE_CONFIRM_SECONDS = 4

function RomImporter:pressDelete(kind, id, version, commit)
  local a = self._confirmDelete
  self._confirmDelete = nil
  if a ~= nil and a.kind == kind and a.id == id and a.version == version
      and (love.timer.getTime() - a.t) <= DELETE_CONFIRM_SECONDS then
    commit()
    return true
  end
  self._confirmDelete = { kind = kind, id = id, version = version,
    t = love.timer.getTime() }
  return false
end

-- Drain one frame's queued launcher actions; LauncherView.update hands the
-- batch straight over.  A touch tap fires on EVERY element whose bounds hold
-- the finger, not only the topmost one: FlexLove gates its mouse path on
-- Context.findInteractiveAtPosition (libs/flexlove/modules/behaviors/
-- Clickable.lua) but polls touches per element with a bare bounds test
-- (EventHandler:processTouchEvents), so a phone tap on a save row's Delete
-- chip also lands on the row behind it.  Control keys inside a row are the
-- row's key plus "-<what>", so a row's own action is dropped whenever a
-- control inside that row queued in the same batch, and #433's disarm runs
-- here instead of at queue time.  Without both halves an Android tap on
-- Delete selected the slot and wiped the arm it had just set, so a secondary
-- slot became the loaded one and could never be deleted (#780).
function RomImporter:runActions(queue)
  for i = 1, #queue do
    local entry = queue[i]
    local key = type(entry.key) == "string" and entry.key or ""
    local superseded = false
    for j = 1, #queue do
      local other = queue[j]
      if j ~= i and type(other.key) == "string"
          and other.key:sub(1, #key + 1) == key .. "-" then
        superseded = true
        break
      end
    end
    if not superseded then
      if not entry.keepArm then self._confirmDelete = nil end
      local ok, err = pcall(entry.fn)
      if not ok then print("launcher action error: " .. tostring(err)) end
    end
  end
end

-- Clicks are polled inside FlexLove (mouse + love.touch); host-forwarded
-- mousepressed mints no click, so Android's synthesized mouse path cannot
-- double-fire a tap (#553).  It DOES hand the pointer back from the pad
-- cursor (#781): a Linux boot with a joystick present arms it (see the
-- getJoystickCount block in new()), and while it is active
-- LauncherView.update refuses to mint mouse clicks, so a real press must
-- win the pointer back even when the polled motion yield misses (X11
-- multi-monitor coords).  Same contract as PadCursor.yieldToPointer for
-- the overlay hosts.  Touch move/press/release must still reach
-- FlexLove.touch* or scroll containers never drag on phones.
function RomImporter:mousepressed(x, y, button)
  self._padCursorActive = false
  local okKit, Kit = pcall(require, "src.ui.kit.Kit")
  if okKit then Kit.pointerUsed() end
  if button ~= 1 or not self._flex then return end
  require("src.import.LauncherView").mousepressed(self, x, y)
end

function RomImporter:touchpressed(id, x, y, dx, dy, pressure)
  local okKit, Kit = pcall(require, "src.ui.kit.Kit")
  if okKit then Kit.pointerUsed() end
  if not self._flex then return end
  require("src.import.LauncherView").touchpressed(
    self, id, x, y, dx, dy, pressure)
end

function RomImporter:touchmoved(id, x, y, dx, dy, pressure)
  if not self._flex then return end
  require("src.import.LauncherView").touchmoved(
    self, id, x, y, dx, dy, pressure)
end

function RomImporter:touchreleased(id, x, y, dx, dy, pressure)
  if not self._flex then return end
  require("src.import.LauncherView").touchreleased(
    self, id, x, y, dx, dy, pressure)
end

-- Switch the active tab (chips, shoulder buttons).  The find search caret and
-- the soft keyboard drop with the panel they belonged to; each tab's scroll
-- offset persists inside the view's per-tab scroll container.
function RomImporter:_switchTab(id)
  if id == "bug" then return self:_openBugPanel() end
  if self.tab and self.tab ~= id then
    local at = tabOrder()
    Transition.start("tabs", "tab", {
      dir = ((at[id] or 0) >= (at[self.tab] or 0)) and 1 or -1,
      from = self.tab, to = id,
    })
  end
  self.tab = id
  if id ~= "find" then self._findVisibleEntries = nil end
  self._findSearchFocus = false
  self._skinUrlFocus = false
  self._onlineFocus = nil
  self:_disarmTextInput()
  -- the skins list is cheap and can change behind the launcher's back
  -- (an export, a hand-dropped folder), so re-read it on every visit
  if id == "skins" then self:_ensureSkins(true) end
  if GameVersion.VERSIONS[id] then
    self:_setModScope(id)
  end
end

-- ------- skins tab (touch skins + the desktop Skin Studio)

function RomImporter:_ensureSkins(force)
  if self._skins and not force then return self._skins end
  local TouchSkin = require("src.core.TouchSkin")
  local out = {}
  for _, entry in ipairs(TouchSkin.list()) do
    local skin = TouchSkin.load(entry.root, entry.id)
    local page = skin and skin.pages[1]
    local controls = 0
    for _, ctl in ipairs(page and page.controls or {}) do
      if not ctl.decorative then controls = controls + 1 end
    end
    out[#out + 1] = {
      id = entry.id,
      source = entry.source,
      format = skin and skin.format or nil,
      pages = skin and #skin.pages or 0,
      controls = controls,
      -- The launcher owns the visual skin picker, so retain the already
      -- loaded first-page bezel for its preview card instead of decoding it
      -- again every frame.
      preview = page and page.image or nil,
      screen = page ~= nil
        and (page.viewport ~= nil or page.screenFit == "remainder"),
      ok = skin ~= nil,
    }
  end
  self._skins = out
  return out
end

function RomImporter:_forgetActiveSkin()
  self._activeSkinCache = nil
end

function RomImporter:_activeSkin()
  if self._activeSkinCache == nil then
    local opts = require("src.core.SaveData").loadOptions()
    local tc = type(opts.touchControls) == "table" and opts.touchControls or {}
    self._activeSkinCache = (tc.enabled ~= false and tc.skin) or false
  end
  return self._activeSkinCache or nil
end

function RomImporter:_useSkin(id)
  local SaveData = require("src.core.SaveData")
  local opts = SaveData.loadOptions()
  local tc = type(opts.touchControls) == "table" and opts.touchControls or {}
  tc.enabled = true
  tc.skin = id
  opts.touchControls = tc
  SaveData.saveOptions(opts)
  self:_forgetActiveSkin()
  self._skinNotice = {
    ok = true,
    text = id and ("Now using " .. id) or "Now using the built-in pad",
  }
end

function RomImporter:_disableSkins()
  local SaveData = require("src.core.SaveData")
  local opts = SaveData.loadOptions()
  local tc = type(opts.touchControls) == "table" and opts.touchControls or {}
  -- `enabled` is the pad's own switch, not a skins switch: turning a skin off
  -- has to leave the built-in pad on, which is what the notice promises.  A
  -- skin can only be active while the pad is enabled, so this never overrides
  -- a player who turned the pad off deliberately.
  tc.enabled, tc.skin = true, nil
  opts.touchControls = tc
  SaveData.saveOptions(opts)
  self:_forgetActiveSkin()
  self._skinNotice = { ok = true, text = "Skins are off. Mobile will use the built-in pad when needed." }
end

function RomImporter:_installSkinZip(source)
  if self.workState == "working" then return end
  self.tab = "skins"
  local name, data, readError
  if type(source) == "string" then
    name = source
    if not source:match("^/") and not source:match("^%a:[/\\]")
        and not source:match("^[Ss][Dd][Mm][Cc]:") then
      data = love.filesystem.read(source)
    end
    if not data then data, readError = readExternalPath(source) end
    if not data then data = love.filesystem.read(source) end
  else
    name = source:getFilename() or ""
    data, readError = readDroppedFile(source)
  end
  if not data then
    self._skinNotice = { ok = false,
      text = "Could not read the skin archive: "
        .. tostring(readError or name) }
    return
  end
  self:_installSkinData(name, data)
end

local MAX_SKIN_URL = 300
local SKIN_TEMP_DIR = "skins/_download"

function RomImporter.skinUrlName(url)
  local path = tostring(url or ""):gsub("[?#].*$", "")
  local base = (path:match("([^/\\]+)$") or ""):gsub("[^%w%._%-]", "_")
  local ext = base:match("%.([%w]+)$")
  if not ext then
    return (base ~= "" and base or "skin") .. ".zip"
  end
  ext = ext:lower()
  local TouchSkin = require("src.core.TouchSkin")
  if TouchSkin.ARCHIVE_EXTS[ext] or ext == "cfg" then return base end
  return (base:gsub("%.[%w]+$", "")) .. ".zip"
end

function RomImporter.wrapSkinPayload(name, data)
  name = tostring(name or "")
  if not name:lower():match("%.cfg$") then return name, data end
  if not data then return name, data end
  if data:sub(1, 2) == "PK" then
    return (name:gsub("%.[Cc][Ff][Gg]$", "")) .. ".zip", data
  end
  local blob = require("src.core.SkinZip").encode({
    { name = "overlay.cfg", data = data },
  })
  return (name:gsub("%.[Cc][Ff][Gg]$", "")) .. ".zip", blob
end

function RomImporter:_installSkinData(name, data)
  local TouchSkin = require("src.core.TouchSkin")
  if not data or data == "" then
    self._skinNotice = { ok = false, text = Strings("The skin file was empty.") }
    return nil
  end
  local wrappedName, payload = RomImporter.wrapSkinPayload(name, data)
  local id, note = TouchSkin.installArchive(wrappedName, payload)
  self:_ensureSkins(true)
  if not id then
    self._skinNotice = { ok = false, text = "Import failed: " .. tostring(note) }
    return nil
  end
  local text = "Imported " .. id
  if type(note) == "table" and note[1] then
    text = text .. ": " .. tostring(note[1])
  end
  self._skinNotice = { ok = true, text = text }
  return id
end

function RomImporter:_toggleSkinUrlFocus()
  self._skinUrlFocus = not self._skinUrlFocus
  if self._skinUrlFocus then
    self:_armTextInput()
  else
    self:_disarmTextInput()
  end
end

function RomImporter:_pasteSkinUrl()
  local ok, text = pcall(love.system.getClipboardText)
  if ok and type(text) == "string" then
    self.skinUrl = utf8Cap((self.skinUrl or "") .. text:gsub("%s", ""),
      MAX_SKIN_URL)
  end
end

function RomImporter:_addSkinFromUrl(url)
  if self._skinFetch then return false end
  url = tostring(url or self.skinUrl or ""):gsub("%s", "")
  if url == "" then
    self._skinNotice = { ok = false,
      text = Strings("Paste a link to a skin archive first.") }
    return false
  end
  if not url:match("^https?://") then
    self._skinNotice = { ok = false,
      text = Strings("A skin link has to start with http:// or https://") }
    return false
  end
  if not require("src.core.Platform").canFetchRemote() then
    self._skinNotice = { ok = false,
      text = Strings("Downloading needs a network transport this build has not got.") }
    return false
  end
  local name = RomImporter.skinUrlName(url)
  local Fetch = require("src.net.Fetch")
  self._skinFetch = {
    url = url, name = name, dest = SKIN_TEMP_DIR .. "/" .. name,
    job = Fetch.download(url, SKIN_TEMP_DIR .. "/" .. name,
      { userAgent = "gen1recomp-skin", maxSeconds = 90 }),
  }
  self._skinNotice = { ok = true, text = Strings("Downloading %s...", name) }
  return true
end

function RomImporter:_pumpSkinFetch()
  local f = self._skinFetch
  if not f then return end
  local Fetch = require("src.net.Fetch")
  local st = Fetch.poll(f.job)
  if st.status == "pending" then
    self._skinFetchProgress = st.progress
    return
  end
  Fetch.release(f.job)
  self._skinFetch, self._skinFetchProgress = nil, nil
  if st.status ~= "ok" or not st.path then
    self._skinNotice = { ok = false,
      text = "Download failed: " .. tostring(st.err or "no data") }
    return
  end
  local data = love.filesystem.read(st.path)
  love.filesystem.remove(st.path)
  if self:_installSkinData(f.name, data) then
    self.skinUrl = ""
  end
end

function RomImporter:_exportSkin(id, kind)
  local TouchSkin = require("src.core.TouchSkin")
  local entry = id and TouchSkin.find(id)
  if not entry then
    self._skinNotice = { ok = false, text = Strings("That skin is gone.") }
    return nil
  end
  local skin = TouchSkin.load(entry.root, entry.id)
  if not skin then
    self._skinNotice = { ok = false,
      text = Strings("Could not read %s", tostring(id)) }
    return nil
  end
  local path, missing, warnings
  if kind == "retroarch" then
    path, missing = TouchSkin.exportRetroArch(skin)
  elseif kind == "delta" then
    path, missing, warnings = TouchSkin.exportDelta(skin)
  else
    path, missing = TouchSkin.export(skin)
  end
  if not path then
    self._skinNotice = { ok = false,
      text = "Export failed: " .. tostring(missing) }
    return nil
  end
  local dir = love.filesystem.getSaveDirectory
    and love.filesystem.getSaveDirectory() or nil
  self._skinExport = { path = path, dir = dir }
  local text = Strings("Exported to %s", (dir and (dir .. "/") or "") .. path)
  if type(missing) == "table" and missing[1] then
    text = text .. " (" .. #missing .. " image(s) missing)"
  end
  if type(warnings) == "table" and warnings[1] then
    text = text .. " " .. tostring(warnings[1])
  end
  self._skinNotice = { ok = true, text = text }
  return path
end

function RomImporter:_revealSkinExport()
  local e = self._skinExport
  if not e or not e.dir then return false end
  if love.system and love.system.openURL then
    pcall(love.system.openURL, fileUrl(e.dir))
  end
  return true
end

local MAX_SYNC_CODE = 8
local MAX_SHARE_CODE = 6

function RomImporter.syncDigits(text)
  local digits = tostring(text or ""):gsub("[^%d]", "")
  return digits:sub(1, MAX_SYNC_CODE)
end

function RomImporter.syncShareCode(text)
  local out = tostring(text or ""):upper():gsub("[^A-Z2-9]", "")
  return out:sub(1, MAX_SHARE_CODE)
end

function RomImporter:_syncDeviceLabel()
  local name = love.system and love.system.getOS and love.system.getOS()
  if type(name) ~= "string" or name == "" then return "device" end
  return name
end

function RomImporter:_syncEngine()
  if self._sync ~= nil then return self._sync or nil end
  local ok, SyncEngine = pcall(require, "src.sync.SyncEngine")
  if not ok or type(SyncEngine) ~= "table" then
    self._sync = false
    return nil
  end
  local made, eng = pcall(SyncEngine.shared)
  if not made or type(eng) ~= "table" then
    self._sync = false
    return nil
  end
  self._sync = eng
  return eng
end

function RomImporter:_syncSupported()
  if self._syncTransportOk ~= nil then return self._syncTransportOk end
  local ok, HostShell = pcall(require, "src.core.HostShell")
  if not ok or type(HostShell) ~= "table"
      or type(HostShell.canHttpRequest) ~= "function" then
    self._syncTransportOk = true
    return true
  end
  local asked, can = pcall(HostShell.canHttpRequest)
  self._syncTransportOk = (not asked) or (can and true or false)
  return self._syncTransportOk
end

function RomImporter:_pumpOnline(dt)
  if not self._online then return end
  local ok, OnlinePanel = pcall(require, "src.import.OnlinePanel")
  if not ok then return end
  pcall(OnlinePanel.update, self, dt)
end

function RomImporter:_pumpSync(dt)
  if self._sync == nil then
    if not self.launcher or self._syncBooted then return end
    if not self:_syncSupported() then return end
    self._syncBooted = true
    local booted = self:_syncEngine()
    if booted and booted.state.enabled and booted:linked() then
      pcall(booted.syncNow, booted)
    end
  end
  local eng = self._sync
  if not eng then return end
  pcall(eng.update, eng, dt)
  if eng.changed then
    eng.changed = nil
    local rows = eng.lastDownloads
    eng.lastDownloads = nil
    for _, row in ipairs(type(rows) == "table" and rows or {}) do
      self:_syncNoteDownload(row)
    end
  end
  if eng.phase == "conflict" and eng.conflicts and #eng.conflicts > 0 then
    if not self._syncModal and not self._syncConflictShown then
      self._syncConflictShown = true
      self:_openSync()
    end
  else
    self._syncConflictShown = nil
  end
end

function RomImporter:_syncNoteDownload(row)
  local version = type(row) == "table" and row.version
  if type(version) ~= "string" or not GameVersion.VERSIONS[version] then return end
  local cart = type(row.cart) == "string" and row.cart ~= "" and row.cart or nil
  local scope = cart and (CART_SCOPE .. cart) or version
  self:_refreshSlots(scope)
  if row.created then self.slotScroll[scope] = math.huge end
  local from = row.device and (" from " .. tostring(row.device)) or ""
  local what
  if cart then
    local ok, found = pcall(self._cartById, self, version, cart)
    what = (ok and type(found) == "table" and found.title) or cart
  end
  self.saveNotice[scope] = { ok = true,
    text = what
      and ("Downloaded a %s save%s into %s."):format(
        tostring(what), from, tostring(row.slot))
      or ("Downloaded a save%s into %s."):format(from, tostring(row.slot)) }
end

function RomImporter:_openSync()
  self:_syncEngine()
  self._syncModal = self._syncModal
    or { view = "home", code1 = "", code2 = "", share = "", withOptions = true }
  self._syncFocus = nil
  self:_disarmTextInput()
end

function RomImporter:_closeSync()
  self._syncModal = nil
  self._syncFocus = nil
  self:_disarmTextInput()
end

function RomImporter:_syncView(view)
  if not self._syncModal then return end
  self._syncModal.view = view
  self._syncFocus = nil
  self:_disarmTextInput()
end

function RomImporter:_syncFocusField(field)
  if not self._syncModal then return end
  if self._syncFocus == field then
    self._syncFocus = nil
    self:_disarmTextInput()
    return
  end
  self._syncFocus = field
  self:_armTextInput()
end

function RomImporter:_syncTypeInto(field, text)
  local mo = self._syncModal
  if not mo or not field then return end
  if field == "share" then
    mo.share = RomImporter.syncShareCode((mo.share or "") .. tostring(text or ""))
  else
    mo[field] = RomImporter.syncDigits((mo[field] or "") .. tostring(text or ""))
  end
end

function RomImporter:_syncPaste()
  local field = self._syncFocus
  if not field then return end
  local ok, text = pcall(love.system.getClipboardText)
  if ok and type(text) == "string" then self:_syncTypeInto(field, text) end
end

function RomImporter:_syncCreate()
  local eng = self:_syncEngine()
  if not eng then return false end
  return eng:createAccount(self:_syncDeviceLabel())
end

function RomImporter:_syncLink()
  local eng, mo = self:_syncEngine(), self._syncModal
  if not eng or not mo then return false end
  local ok = eng:linkDevice(mo.code1, mo.code2, self:_syncDeviceLabel())
  if ok then
    mo.code1, mo.code2, mo.view = "", "", "home"
    self._syncFocus = nil
    self:_disarmTextInput()
  end
  return ok
end

function RomImporter:_syncNow()
  local eng = self:_syncEngine()
  if not eng then return false end
  return eng:syncNow()
end

function RomImporter:_syncUnlink()
  local eng = self:_syncEngine()
  if not eng then return false end
  eng:unlink()
  if self._syncModal then self._syncModal.view = "home" end
  return true
end

function RomImporter:_syncUnlinkDevice(deviceId)
  local eng = self:_syncEngine()
  if not eng or type(eng.unlinkDevice) ~= "function" then return false end
  return eng:unlinkDevice(deviceId)
end

function RomImporter:_syncShareMods()
  local eng, mo = self:_syncEngine(), self._syncModal
  if not eng then return false end
  return eng:shareMods(mo and mo.withOptions ~= false)
end

function RomImporter:_syncToggleShareOptions()
  local mo = self._syncModal
  if not mo then return false end
  mo.withOptions = not (mo.withOptions ~= false)
  return mo.withOptions
end

function RomImporter:_syncAnswerModOptions(importThem)
  local eng = self:_syncEngine()
  if not eng or type(eng.answerModOptions) ~= "function" then return false end
  return eng:answerModOptions(importThem)
end

function RomImporter:_syncGetShare()
  local eng, mo = self:_syncEngine(), self._syncModal
  if not eng or not mo then return false end
  return eng:fetchShare(mo.share or "")
end

function RomImporter:_syncApplyMods()
  local eng, mo = self:_syncEngine(), self._syncModal
  if not eng then return false end
  local ok, err = eng:applyModPlan(function(done, total, label, finished)
    if not mo then return end
    if finished then
      mo.progress = nil
      if self._refreshMods then self:_refreshMods() end
    else
      mo.progress = { done = done, total = total, label = label }
    end
  end)
  if mo then mo.progress = nil end
  if ok and self._refreshMods then self:_refreshMods() end
  return ok, err
end

function RomImporter:_syncResolve(key, choice)
  local eng = self:_syncEngine()
  if not eng then return false end
  return eng:resolveConflict(key, choice)
end

function RomImporter:_skinsImportButtonLabel()
  if self.isNX then return Strings("Scan again") end
  return Strings("Import skin .zip")
end

function RomImporter:chooseSkin()
  if self.workState == "working" then return end
  if self.isNX then
    local found = #self:_ensureSkins(true)
    self._skinNotice = { ok = true, text = Strings(
      "%d skins found. Copy a skin .zip into %s/ over MTP, then scan again.",
      found, require("src.core.TouchSkin").USER_ROOT) }
    return
  end
  if self.nativePicker and love.system.getPickedFile then
    self.pickerPendingKind = "skin"
    if not pickFile("mod") then
      self.pickerPendingKind = nil
      self._skinNotice = { ok = false, text = "Could not open the file picker." }
    end
    return
  end
  if self.android then
    local name = findPendingMod(true, self.pickSkip)
    if name then
      self:_installSkinZip(name)
      consumePick(self, name, "picked_mod.zip",
        self._skinNotice and self._skinNotice.ok)
      return
    end
    self.pickerPendingKind = "skin"
    if not pickFile("mod") then
      self.pickerPendingKind = nil
      self._skinNotice = { ok = false,
        text = "Could not open the file picker. Copy a skin .zip via USB." }
    else
      self.pickPending = true
      self.pickTimer = 0
    end
    return
  end
  local path = chooseSkinZip()
  if path then self:_installSkinZip(path) end
end

function RomImporter:_toggleFindSearchFocus()
  self._findSearchFocus = not self._findSearchFocus
  if self._findSearchFocus then
    self:_armTextInput()
  else
    self:_disarmTextInput()
  end
end

-- ------- settings gear (options.lua + enabled mods' option schemas)

function RomImporter:_openBugPanel()
  self._settings = nil
  self._bugModal = true
  return true
end

function RomImporter:_closeBugPanel()
  self._bugModal = nil
  return true
end

function RomImporter:_openSettings()
  -- The touch-overlay editor is a host screen, so the model gets it as a
  -- hook rather than reaching for main.lua's handler itself.  Closing the
  -- settings panel FIRST persists the pending edits (_closeSettings saves)
  -- and leaves no modal behind the editor to return to.
  -- The tab rides along: the editor persists the layout into that game's own
  -- option block, and Gold's is not the flat Gen 1 one (#1100).
  local hooks = {}
  local version = self.tab
  if self.onEditTouchControls then
    local version = self.tab
    hooks.editTouchControls = function()
      self:_closeSettings()
      self.onEditTouchControls(version)
    end
  end
  if self.onOpenSkinStudio then
    local version = self.tab
    hooks.openSkinStudio = function(skinId)
      self:_closeSettings()
      self.onOpenSkinStudio(version, skinId)
    end
  end
  -- The tab the gear was opened on decides the row set: Gold reads a
  -- different option block entirely, and offering it Gen 1's rows meant a
  -- dozen controls that changed nothing (see LauncherSettings.gen2Rows).
  local ok, model = pcall(function()
    return require("src.import.LauncherSettings").open(hooks, version)
  end)
  if ok and model then
    self._settings = model
  end
end

-- Quit from the launcher's own X.  It goes through love.event.quit so main.lua's
-- love.quit hook still runs: that is where the worker threads are shut down
-- (#339) and where a launcher close is told apart from a running game's (#785).
function RomImporter:_quitApp()
  if love.event and love.event.quit then love.event.quit() end
end

function RomImporter:_closeSettings()
  local model = self._settings
  if model then
    model.save()
  end
  self._settings = nil
  self:_forgetActiveSkin()
end

function RomImporter:_safeModeEnabled()
  if self.safeMode == nil then
    local SaveData = require("src.core.SaveData")
    self.safeMode = SaveData.isSafeMode(SaveData.loadOptions())
  end
  return self.safeMode == true
end

function RomImporter:_toggleSafeMode()
  local SaveData = require("src.core.SaveData")
  local options = SaveData.loadOptions()
  local enabled = not SaveData.isSafeMode(options)
  SaveData.setSafeMode(options, enabled)
  SaveData.saveOptions(options)
  self.safeMode = enabled
  self.mods = nil
  self.findInstalled = nil
  self._modSortCache = nil
  self._cartCaptureCache = nil
  self._modInfoFetch = nil
  self.modNotice = nil
end

function RomImporter:_reportIssue(options, version)
  self.issueNotice = nil
  local ok, IssueReport = pcall(require, "src.core.IssueReport")
  if not ok then
    self.issueNotice = { ok = false, text = "Could not prepare the issue report." }
    return false
  end
  local opened, url, reason = IssueReport.open(options, {
    version = version,
    mods = self.mods,
  })
  if not opened then
    self.issueNotice = { ok = false, text = reason or "Could not open the issue report." }
    return false
  end
  self._lastIssueReportURL = url
  if reason then self.issueNotice = { ok = true, text = reason } end
  return true
end

function RomImporter:_commitSettingsText()
  local st = self._settingsText
  self._settingsText = nil
  self:_disarmTextInput()
  if st and st.row.setText then
    st.row.setText(st.text)
    if self._settings then self._settings.save() end
  end
end

-- The view's open-folder affordance needs the same file:// encoding the old
-- notice line used.
-- Desktop picks a .cart file; everywhere else CartStore's stray scan already
-- adopts anything dropped in the folder, so we just point at it.
function RomImporter:_resyncPointerAfterDialog()
  self._mouseAt = nil
  self._clickPt = nil
  self._prevMouseDown = (love and love.mouse and love.mouse.isDown
    and love.mouse.isDown(1)) and true or false
end

function RomImporter:importCartFile(version)
  local CartStore = require("src.carts.CartStore")
  local FilePicker = require("src.core.FilePicker")
  if not FilePicker.available() then
    local dir = self:cartsDir()
    self._cartNotice = dir
      and Strings("Drop .cart files in %s, then reopen this list.", dir)
      or Strings("No filesystem available to import from.")
    return false
  end
  local path = FilePicker.open("Choose a cart",
    { label = "Cart", exts = { CartStore.EXT:gsub("^%.", "") } })
  self:_resyncPointerAfterDialog()
  if not path then return false end
  local bytes = FilePicker.read(path)
  if not bytes then
    self._cartNotice = Strings("Could not read %s", FilePicker.basename(path))
    return false
  end
  local cart, err = CartStore.install(bytes)
  if not cart then
    self._cartNotice = Strings("That cart could not be imported: %s",
      tostring(err))
    return false
  end
  self:_refreshCarts(version)
  self._cartNotice = Strings("Imported %s. It is in this list now.",
    tostring(cart.title or cart.id))
  return true
end

-- The real OS path of the cart folder, so the launcher can open it and so a
-- player can drop a .cart in by hand.
function RomImporter:cartsDir()
  local CartStore = require("src.carts.CartStore")
  local fs = love and love.filesystem
  if not fs then return nil end
  if fs.createDirectory then pcall(fs.createDirectory, CartStore.DIR) end
  local base = fs.getSaveDirectory and fs.getSaveDirectory()
  if not base or base == "" then return nil end
  return base .. "/" .. CartStore.DIR
end

function RomImporter:fileUrl(path)
  return fileUrl(path)
end

function RomImporter:keypressed(key)
  if Transition.active() then return end
  local okKit, Kit = pcall(require, "src.ui.kit.Kit")
  if okKit then
    if Kit.FileBrowser and Kit.FileBrowser.active then
      if Kit.FileBrowser.keypressed(key) then return end
    end
    if Kit.VirtualKeyboard and Kit.VirtualKeyboard.active then
      if Kit.VirtualKeyboard.keypressed(key) then return end
    end
  end
  if self._profileSavePrompt then
    if key == "backspace" then
      self._profileSavePrompt.text = utf8Back(self._profileSavePrompt.text or "")
    elseif key == "return" or key == "kpenter" then
      local txt = self._profileSavePrompt and self._profileSavePrompt.text
      if txt and txt ~= "" then
        local LauncherMods = require("src.mods.LauncherMods")
        LauncherMods.saveProfile(txt)
        self._profileSavePrompt = nil
        self:_disarmTextInput()
        if self._refreshMods then self:_refreshMods() end
      end
    elseif key == "escape" then
      self._profileSavePrompt = nil
      self:_disarmTextInput()
    end
    return
  end
  if self._profileRenamePrompt then
    if key == "backspace" then
      self._profileRenamePrompt.text = utf8Back(self._profileRenamePrompt.text or "")
    elseif key == "return" or key == "kpenter" then
      local txt = self._profileRenamePrompt and self._profileRenamePrompt.text
      local old = self._profileRenamePrompt and self._profileRenamePrompt.oldName
      if txt and txt ~= "" and old then
        local LauncherMods = require("src.mods.LauncherMods")
        LauncherMods.renameProfile(old, txt)
        self._profileRenamePrompt = nil
        self:_disarmTextInput()
        if self._refreshMods then self:_refreshMods() end
      end
    elseif key == "escape" then
      self._profileRenamePrompt = nil
      self:_disarmTextInput()
    end
    return
  end
  if self._cartSave then
    if key == "backspace" then
      self._cartSave.text = utf8Back(self._cartSave.text)
      self._cartSave.error = nil
    elseif key == "return" or key == "kpenter" then
      self:_commitCartSave()
    elseif key == "escape" then
      self:_cancelCartSave()
    end
    return
  end
  if self._settingsText then
    if key == "backspace" then
      self._settingsText.text = utf8Back(self._settingsText.text)
    elseif key == "return" or key == "kpenter" then
      self:_commitSettingsText()
    elseif key == "escape" then
      self._settingsText = nil
      self:_disarmTextInput()
    end
    return
  end
  if self._settings then
    if key == "escape" then self:_closeSettings() end
    return
  end
  if self._syncModal then
    local field = self._syncFocus
    if field then
      local mo = self._syncModal
      if key == "backspace" then
        mo[field] = tostring(mo[field] or ""):sub(1, -2)
      elseif key == "return" or key == "kpenter" or key == "escape" then
        self._syncFocus = nil
        self:_disarmTextInput()
      elseif key == "v"
          and love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui") then
        self:_syncPaste()
      end
      return
    end
    if self._flex and require("src.import.LauncherView").keypressed(self, key) then
      return
    end
    if key == "escape" then self:_closeSync() end
    return
  end
  if self._rename then
    if key == "backspace" then
      self._rename.text = utf8Back(self._rename.text)
    elseif key == "return" or key == "kpenter" then
      self:_commitRename()
    elseif key == "escape" then
      self._rename = nil
      self:_disarmTextInput()
    end
    return
  end
  if self._indexPrompt then
    if key == "backspace" then
      self._indexPrompt.text = utf8Back(self._indexPrompt.text)
    elseif key == "return" or key == "kpenter" then
      self:_commitAddIndex()
    elseif key == "escape" then
      self._indexPrompt = nil
      self:_disarmTextInput()
    elseif key == "v" and (love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui")) then
      -- an index URL is long and comes from a browser: typing it out by hand
      -- is the difference between adding one and giving up
      self:_pasteIndexUrl()
    end
    return
  end
  if self._modConfirm or self._modVersions or self._modReleaseNotes
      or self._findDetails or self._appPatchNotes then
    -- Focus navigation belongs to the visible modal as well as the launcher
    -- beneath it. Route arrows and an already-armed confirm before this guard
    -- returns; unarmed Enter still falls through to the modal guard. Keep this
    -- inside the modal branch so text fields retain exclusive keyboard input.
    if self._flex and require("src.import.LauncherView").keypressed(self, key) then
      return
    end
    if key == "escape" then
      if self._findDetails then
        self._findDetails = nil
        self:_cancelFindDetails()
      elseif self._modReleaseNotes then
        self._modReleaseNotes = nil
      elseif self._appPatchNotes then
        self._appPatchNotes = nil
      else
        self._modConfirm = nil
        self._modVersions = nil
      end
    end
    return
  end
  if self._cartPopup then
    if self._flex and require("src.import.LauncherView").keypressed(self, key) then
      return
    end
    if key == "escape" then self._cartPopup = nil end
    return
  end
  if self._bugModal and key == "escape" then
    self:_closeBugPanel()
    return
  end
  if self._pcPicker and key == "escape" and not self._onlineFocus then
    require("src.import.OnlinePanel").pcClose(self)
    return
  end
  if self._onlineFocus then
    local OnlinePanel = require("src.import.OnlinePanel")
    local st = OnlinePanel.state(self)
    local field = self._onlineFocus
    if key == "backspace" then
      if field == "online-name" then
        st.nameDraft = utf8Back(st.nameDraft or "")
      elseif field == "online-note" then
        st.note = utf8Back(st.note or "")
      elseif field == "online-code" then
        st.joinCode = utf8Back(st.joinCode or "")
      elseif field == "online-trade-code" then
        local tr = OnlinePanel.tradeState(self)
        tr.code = utf8Back(tr.code or "")
      elseif field == OnlinePanel.PC_FIELD then
        local pc = OnlinePanel.pcPicker(self)
        OnlinePanel.pcQuery(self, utf8Back((pc and pc.query) or ""))
      end
    elseif key == "return" or key == "kpenter" then
      self:_commitOnlineField()
    elseif key == "escape" then
      self._onlineFocus = nil
      st.nameDraft = nil
      self:_disarmTextInput()
    end
    return
  end
  if self._skinUrlFocus then
    if key == "backspace" then
      self.skinUrl = utf8Back(self.skinUrl or "")
    elseif key == "return" or key == "kpenter" then
      self._skinUrlFocus = false
      self:_disarmTextInput()
      self:_addSkinFromUrl()
    elseif key == "escape" then
      self._skinUrlFocus = false
      self:_disarmTextInput()
    elseif key == "v" and love.keyboard.isDown("lctrl", "rctrl", "lgui", "rgui") then
      self:_pasteSkinUrl()
    end
    return
  end
  if self._findSearchFocus then
    if key == "backspace" then
      self.findQuery = utf8Back(self.findQuery or "")
      self.findScroll = 0
    elseif key == "escape" or key == "return" or key == "kpenter" then
      self._findSearchFocus = false
      self:_disarmTextInput()
    end
    return
  end
  if key == "escape" and self.tab == "online" then
    local okOnline, OnlinePanel = pcall(require, "src.import.OnlinePanel")
    if okOnline and OnlinePanel.back(self) then return end
  end
  if self.workState == "working" then return end
  -- Keyboard focus ring: arrows move it, Enter activates it -- but only once
  -- the arrows have been used, so the long-standing "Enter plays the visible
  -- game" shortcut below still works for anyone who never touches the ring.
  if self._flex and require("src.import.LauncherView").keypressed(self, key) then
    return
  end
  if key == "return" or key == "space" or key == "kpenter" then
    -- Enter acts on the visible game tab: Play if its ROM is ready, otherwise
    -- open its picker.  The mods tab has no keyboard action.
    local version = self.tab
    if GameVersion.VERSIONS[version] then
      if self.ready[version] then self:play(version) else self:_romAction(version) end
    end
  end
end

-- list, not index: index reads only the registry, so a .g1rcart dropped into
-- the carts folder by hand would never appear.  list adopts strays and heals
-- the registry, and this is cached per version so it parses once.
function RomImporter:_refreshCarts(version)
  local out = {}
  local ok, rows = pcall(function()
    return require("src.carts.CartStore").listFor(version)
  end)
  if ok and type(rows) == "table" then
    for _, row in ipairs(rows) do out[#out + 1] = row end
  end
  self.carts[version] = out
  -- The FIND panel's installed-cart map spans every game, so it goes stale
  -- on any cart change, not just this version's.
  self._findCartMap = nil
  return out
end

function RomImporter:_ensureCarts(version)
  return self.carts[version] or self:_refreshCarts(version)
end

function RomImporter:_cartById(version, id)
  if type(id) ~= "string" then return nil end
  for _, row in ipairs(self:_ensureCarts(version)) do
    if row.id == id then return row end
  end
  return nil
end

function RomImporter:activeCartRow(version)
  local id = self.activeCart[version]
  if not id then return nil end
  return self:_cartById(version, id)
end

function RomImporter:slotScope(version)
  local id = self.activeCart[version]
  if id then return CART_SCOPE .. id end
  return version
end

function RomImporter:_selectCart(version, id)
  self._cartPopup = nil
  self._cartNotice = nil
  self.cartFillNotice = nil
  if id ~= nil and not self:_cartById(version, id) then return end
  self.activeCart[version] = id
  self._cartPlan = nil
  -- the MODS panel answers for the cart now, so its cached rows are stale
  self.mods, self._modSortCache, self._cartCaptureCache = nil, nil, nil
  local scope = self:slotScope(version)
  self.slots[scope] = nil
  self.slotScroll[scope] = nil
  if self._pages then self._pages["slots-" .. scope] = 1 end
end

function RomImporter:_cartSealSlot(version)
  local id = self.activeCart and self.activeCart[version] or nil
  if not id then return nil, nil end
  local scope = self:slotScope(version)
  self:_ensureSlots(scope)
  local active = self.activeSlot[scope]
  for _, slot in ipairs(self.slots[scope] or {}) do
    if slot.id == active then return slot, scope end
  end
  return nil, scope
end

function RomImporter:cartPlan(version, listed)
  local id = self.activeCart and self.activeCart[version] or nil
  if not id then return nil, nil end
  local slot = self:_cartSealSlot(version)
  local broken = (slot and slot.sealBroken == true) or false
  local key = table.concat(
    { id, tostring(slot and slot.id), tostring(broken) }, "|")
  local cached = self._cartPlan
  if cached and cached.key == key then return cached.report, slot end
  local installed = {}
  pcall(function()
    local rows = listed or require("src.mods.LauncherMods").list(version) or {}
    for _, row in ipairs(rows) do
      local manifest = type(row.manifest) == "table" and row.manifest or row
      if type(manifest.id) == "string" then
        installed[manifest.id] =
          { id = manifest.id, version = manifest.version }
      end
    end
  end)
  local ok, cart = pcall(function()
    return require("src.carts.CartStore").get(id)
  end)
  if not ok or type(cart) ~= "table" then cart = nil end
  local report = require("src.mods.Loader").planCart(cart, installed, broken)
  report.id = id
  self._cartPlan = { key = key, report = report }
  return report, slot
end

function RomImporter:pressBreakSeal(version)
  local slot, scope = self:_cartSealSlot(version)
  if not scope then return false end
  return self:pressDelete("seal", slot and slot.id or nil, scope, function()
    self:breakCartSeal(version)
  end)
end

function RomImporter:breakCartSeal(version)
  local id = self.activeCart and self.activeCart[version] or nil
  if not id then return false end
  local SaveData = require("src.core.SaveData")
  local scope = self:slotScope(version)
  self:_ensureSlots(scope)
  local slotId = self.activeSlot[scope]
  if type(slotId) ~= "string" then
    slotId = SaveData.createCartSlot(id)
    if type(slotId) ~= "string" then return false end
    SaveData.setActiveCartSlot(id, slotId)
  end
  local ok = SaveData.markSlotSealBroken(id, slotId)
  self:_refreshSlots(scope)
  self.activeSlot[scope] = slotId
  self._cartPlan = nil
  return ok and true or false
end

-- ------- installing the mods a cart pins
--
-- The other way out of a refusal: fetch every pin at the version the cart
-- names, verified against the sha256 it recorded, instead of breaking the seal.

local function pinSameVersion(want, have)
  local Semver = require("src.mods.Semver")
  local order = Semver.compare(want, have)
  if order ~= nil then return order == 0 end
  return want == have
end

-- Why a pin cannot be fetched.  Only a github pin carries a repo, a version
-- and an archive hash, which is all three things an install needs.
local function pinUnresolvable(pin)
  local source = type(pin) == "table" and pin.source or nil
  if source == "gamebanana" then
    return "is pinned to a GameBanana file, which the launcher cannot download"
  end
  if source == "local" then
    return "is pinned to a copy on the machine that built the cart, so there is nothing to download"
  end
  if source ~= "github" then
    return "carries no source the launcher can install from"
  end
  if type(pin.repo) ~= "string" or pin.repo == "" then
    return "names no GitHub repository"
  end
  if type(pin.version) ~= "string" or pin.version == "" then
    return "names no version to install"
  end
  if type(pin.sha256) ~= "string" or #pin.sha256 ~= 64 then
    return "records no sha256, so its archive could not be verified"
  end
  return nil
end

-- The pins the player cannot satisfy: absent, or installed at some other
-- version.  A mismatch needs the PINNED version, so it queues like a gap.
function RomImporter:cartFillRows(version)
  local report = self:cartPlan(version)
  if type(report) ~= "table" then return {} end
  local rows = {}
  for _, row in ipairs(report.missing or {}) do
    rows[#rows + 1] = { id = row.id, version = row.version,
      pin = (report.pins or {})[row.id] }
  end
  for _, row in ipairs(report.mismatched or {}) do
    rows[#rows + 1] = { id = row.id, version = row.version,
      installed = row.installed, pin = (report.pins or {})[row.id] }
  end
  return rows
end

-- A configured index already knows where a mod's archive lives, so it saves a
-- round trip -- but only when it points at exactly the pinned version.
function RomImporter:_cartPinIndexRelease(row)
  local mods = self.findIndex and self.findIndex.mods or nil
  if type(mods) ~= "table" then return nil end
  local ModIndex = require("src.mods.ModIndex")
  for _, entry in ipairs(mods) do
    if type(entry) == "table" and entry.id == row.id
        and pinSameVersion(row.version, ModIndex.displayVersion(entry)) then
      local release = ModIndex.releaseFor(entry)
      if type(release) == "table" and release.zip and release.zip.url then
        return release
      end
    end
  end
  return nil
end

function RomImporter:pressInstallCartMods(version)
  if self._cartFill or self._modInstall or self._cartInstall
      or self._updateAll then return false end
  local rows = self:cartFillRows(version)
  if #rows == 0 then return false end
  self.cartFillNotice = nil
  self._cartFill = { version = version, rows = rows, index = 0,
    installed = 0, failures = {}, stage = "next" }
  self:_pumpCartFill()
  return true
end

function RomImporter:_cartFillFailed(msg)
  local job = self._cartFill
  if not job then return end
  local row = job.row
  job.failures[#job.failures + 1] =
    ("%s %s"):format(tostring(row and row.id or "?"), tostring(msg))
  job.stage = "next"
end

function RomImporter:_finishCartFill()
  local job = self._cartFill
  self._cartFill = nil
  self:_clearBusy()
  -- Re-plan against what is on disk now, so the card answers for itself.
  self._cartPlan = nil
  pcall(self._refreshMods, self)
  if not job then return end
  if #job.failures == 0 then
    self.cartFillNotice = { ok = true,
      text = Strings("Installed %d of the mods this cart pins.", job.installed) }
    return
  end
  self.cartFillNotice = { ok = false, failures = job.failures,
    text = Strings("Installed %d of %d. %d could not be installed:",
      job.installed, #job.rows, #job.failures) }
end

function RomImporter:_pumpCartFill()
  local job = self._cartFill
  if not job then return end
  local ModUpdate = require("src.mods.ModUpdate")

  if job.stage == "next" then
    job.index = job.index + 1
    job.row = job.rows[job.index]
    if not job.row then return self:_finishCartFill() end
    local pin = job.row.pin
    local why = pinUnresolvable(pin)
    if why then return self:_cartFillFailed(why) end
    local release = self:_cartPinIndexRelease(job.row)
    if release then
      job.release, job.stage = release, "install"
      return
    end
    job.fetch = ModUpdate.beginFetchReleases(pin.repo, job.row.id,
      { force = true })
    job.stage = "fetch"
    self:_setBusy(Strings("Finding %s v%s", tostring(job.row.id),
      tostring(job.row.version)))
    return
  end

  if job.stage == "fetch" then
    local done, releases, err = ModUpdate.pumpFetchReleases(job.fetch)
    if not done then return end
    job.fetch = nil
    if type(releases) ~= "table" then
      return self:_cartFillFailed("could not be looked up: "
        .. tostring(err or "release check failed"))
    end
    local pick
    for _, rel in ipairs(releases) do
      if type(rel) == "table" and pinSameVersion(job.row.version, rel.version) then
        pick = rel
        break
      end
    end
    if not pick then
      return self:_cartFillFailed(("has no release tagged v%s")
        :format(tostring(job.row.version)))
    end
    if not (pick.zip and pick.zip.url) then
      return self:_cartFillFailed(("v%s has no .zip asset")
        :format(tostring(job.row.version)))
    end
    job.release, job.stage = pick, "install"
    return
  end

  if job.stage == "install" then
    if self._modInstall then return end
    local row = job.row
    job.stage = "installing"
    self:_beginModInstall({
      modId = row.id, name = row.id, release = job.release,
      verb = "Installed", notice = "cart", sha256 = row.pin.sha256,
      done = function(ok, text)
        if ok then
          job.installed = job.installed + 1
          job.stage = "next"
        else
          self:_cartFillFailed(text)
        end
      end,
    })
  end
end

function RomImporter:_restoreActiveCarts(opts)
  local saved = opts and opts.activeCart
  if type(saved) ~= "table" then return end
  for version, id in pairs(saved) do
    if GameVersion.VERSIONS[version] and type(id) == "string"
        and self:_cartById(version, id) then
      self.activeCart[version] = id
    end
  end
end

local CART_RAIL = { red = "railRed", blue = "railBlue", yellow = "railGold",
                    gold = "railAmber", silver = "railSilver" }
local CART_START_VERSION = "1.0.0"

local function cartShellHex(version)
  local Theme = require("src.ui.kit.Theme")
  local col = Theme.PAL[CART_RAIL[version] or ""] or Theme.PAL.green
  return ("#%02x%02x%02x"):format(col[1] or 0, col[2] or 0, col[3] or 0)
end

local function cartIdFromTitle(title)
  local CartManifest = require("src.carts.CartManifest")
  local id = tostring(title or ""):lower():gsub("[^%w]+", "_")
  id = id:sub(1, CartManifest.MAX_ID):gsub("^_+", ""):gsub("_+$", "")
  if id == "" then return nil end
  return id
end

local function cartModRows(imp, version)
  local LauncherMods = require("src.mods.LauncherMods")
  local rows, kept = LauncherMods.list(version) or {}, {}
  for _, row in ipairs(rows) do
    if row.targetsHere ~= false then kept[#kept + 1] = row end
  end
  return kept
end

-- Every mod that targets this game, switched on or off: CartStore.capture
-- pins the off ones too, so they are part of the cart it would write.
function RomImporter:_cartCaptureCount(version)
  if not GameVersion.VERSIONS[version] then return 0 end
  local cache = self._cartCaptureCache
  if cache and cache.version == version then return cache.n end
  local n = #cartModRows(self, version)
  self._cartCaptureCache = { version = version, n = n }
  return n
end

function RomImporter:_cartAuthor()
  local SaveData = require("src.core.SaveData")
  local ok, opts = pcall(SaveData.loadOptions)
  local sync = ok and type(opts) == "table" and opts.saveSync or nil
  local label = type(sync) == "table" and sync.deviceLabel or nil
  if type(label) == "string" and label:match("%S") then return label end
  return Strings("Unknown")
end

function RomImporter:_cartSaveId()
  local st = self._cartSave
  if not st then return nil end
  return cartIdFromTitle(st.text)
end

local function cartIdentity(st, id, title)
  return { id = id, title = title, version = st.cartVersion,
           author = st.author, base = st.version,
           shell = st.shell, seal = "sealed" }
end

function RomImporter:_beginCartSave(version)
  if not GameVersion.VERSIONS[version] then return end
  local LauncherMods = require("src.mods.LauncherMods")
  local CartStore = require("src.carts.CartStore")
  local st = {
    version = version, text = "", author = self:_cartAuthor(),
    cartVersion = CART_START_VERSION, shell = cartShellHex(version),
    mods = cartModRows(self, version),
    modOptions = LauncherMods.modOptions(),
    unresolved = {}, publishable = false,
  }
  st.count = #st.mods
  local cart, unresolved = CartStore.capture(
    cartIdentity(st, "preview", "Preview"), st.mods, st.modOptions)
  if cart then
    st.unresolved = unresolved or {}
    local CartManifest = require("src.carts.CartManifest")
    st.publishable = CartManifest.publishable(cart) and true or false
  else
    st.error = tostring(unresolved)
  end
  self._cartSave = st
  self:_armTextInput()
end

function RomImporter:_cancelCartSave()
  self._cartSave = nil
  self:_disarmTextInput()
end

function RomImporter:_commitCartSave()
  local st = self._cartSave
  if not st then return end
  local CartManifest = require("src.carts.CartManifest")
  local CartStore = require("src.carts.CartStore")
  local title = tostring(st.text or ""):match("^%s*(.-)%s*$")
  if title == "" then
    st.error = Strings("Type a title for this cart.")
    return
  end
  local id = cartIdFromTitle(title)
  if not id then
    st.error = Strings("That title has no letters or numbers to build an id from.")
    return
  end
  local existing = CartStore.get(id)
  if existing then
    st.error = Strings("%s already uses the id %s. Pick a different title.",
      tostring(existing.title), id)
    return
  end
  local cart, unresolved = CartStore.capture(
    cartIdentity(st, id, title), st.mods, st.modOptions)
  if not cart then
    st.error = tostring(unresolved)
    return
  end
  st.unresolved = unresolved or {}
  st.publishable = CartManifest.publishable(cart) and true or false
  local ok, err = CartStore.install(CartManifest.encode(cart))
  if not ok then
    st.error = tostring(err)
    return
  end
  local version = st.version
  self._cartSave = nil
  self:_disarmTextInput()
  self:_refreshCarts(version)
  self._cartPopup = version
  self._cartNotice = Strings("Saved %s. It is in this list now.", title)
end

function RomImporter:exportCart(id)
  if self.workState == "working" then return end
  local CartStore = require("src.carts.CartStore")
  local SaveData = require("src.core.SaveData")
  local bytes, err = CartStore.export(id)
  if type(bytes) ~= "string" then
    self._cartNotice = tostring(err or "that cart could not be read")
    return
  end
  local fs = SaveData.portableFs() or (love and love.filesystem)
  if not (fs and fs.write) then
    self._cartNotice = Strings("No filesystem available to export to.")
    return
  end
  if fs.createDirectory then
    fs.createDirectory("exports")
    fs.createDirectory("exports/carts")
  end
  local rel = "exports/carts/" .. id .. CartStore.EXT
  local wrote, writeErr = fs.write(rel, bytes)
  if not wrote then
    self._cartNotice = Strings("Could not write the export: %s", tostring(writeErr))
    return
  end
  local abs, portableBase = rel, SaveData.portableBaseDir()
  if portableBase then
    local sep = package.config:sub(1, 1)
    abs = portableBase .. sep .. rel:gsub("/", sep)
  else
    local base = fs.getSaveDirectory and fs.getSaveDirectory() or ""
    if base ~= "" then abs = base .. "/" .. rel end
  end
  if self.isNX then
    local hint = RomImporter.mtpHintPath(love.filesystem.getSaveDirectory())
    if hint ~= "" and hint:sub(-1) ~= "/" then hint = hint .. "/" end
    self._cartNotice =
      Strings("Exported to %s\nDBI MTP → 1: SD Card/%sexports/carts/", abs, hint)
    return
  end
  if self.android then
    local suggested = id .. CartStore.EXT
    local staged = love.filesystem.write("pending_export.sav", bytes)
    if staged and love.system.createFile
        and love.system.createFile(suggested, love.filesystem.getSaveDirectory()) then
      self.pickPending = true
      self.pickTimer = 0
      self.androidPendingCartExport = true
      self._cartNotice = Strings("Pick where to save %s...", suggested)
    else
      self._cartNotice = Strings("Exported inside the app folder: %s", abs)
    end
    return
  end
  self._cartNotice = Strings("Exported to %s", abs)
end

-- Reload a scope's slot list + active id from SaveData (the source of truth).
-- Cheap enough to call on any mutation; the per-frame draw only calls it lazily
-- through _ensureSlots so a still list costs nothing after the first paint.
function RomImporter:_refreshSlots(scope)
  local SaveData = require("src.core.SaveData")
  local cart = cartOfScope(scope)
  if cart then
    self.slots[scope] = SaveData.listCartSlots(cart) or {}
    local opts = SaveData.loadOptions()
    local reg = opts.cartSlots and opts.cartSlots[cart]
    self.activeSlot[scope] =
      reg and (reg.active or (reg.list and reg.list[1])) or nil
    return
  end
  self.slots[scope] = SaveData.listSlots(scope) or {}
  local opts = SaveData.loadOptions()
  local reg = opts.saveSlots and opts.saveSlots[scope]
  -- fall back to the first slot as the shown "loaded" one when the registry
  -- has a list but no explicit active id (matches saveNames' own resolution)
  self.activeSlot[scope] = reg and (reg.active or reg.list[1]) or nil
end

function RomImporter:_ensureSlots(scope)
  if not self.slots[scope] then self:_refreshSlots(scope) end
end

-- The host calls this when the save editor closes: the edited slot's player
-- name, badge count and dex total all feed the cached row summary, so it has
-- to be re-read rather than trusted across the round trip.
function RomImporter:savesChanged(version)
  self:_refreshSlots(version)
end

-- Point the active slot at id (persisted immediately, per the contract) and
-- reflect it in the LOADED pill without a full relist.
function RomImporter:_selectSlot(scope, id)
  local SaveData = require("src.core.SaveData")
  local cart = cartOfScope(scope)
  if cart then
    SaveData.setActiveCartSlot(cart, id)
  else
    SaveData.setActiveSlot(scope, id)
  end
  self.activeSlot[scope] = id
end

-- Inline slot rename (#205): right-click arms a modal text field; Enter
-- commits through SaveData.renameSlot (empty clears the label), Esc cancels.
-- While it is up, keypressed/textinput/mousepressed all route here first.
local MAX_SLOT_LABEL = 24
-- Long enough for a Pages URL with a deep path; short enough that a paste of
-- something that is not a URL at all cannot fill options.lua.
local MAX_INDEX_URL = 200
local MAX_FIND_QUERY = 48

-- Mobile LOVE only delivers love.textinput while setTextInput(true) is armed,
-- and arming it is also what raises the soft keyboard, so a cabled USB
-- keyboard is just as dead without it (#578).  Every site that opens one of
-- the launcher's three text fields (_rename, _indexPrompt, _findSearchFocus)
-- arms through here, and every site that closes one disarms.  Desktop has
-- text input on by default and the save editor hosted from this launcher
-- depends on it staying on (tools/save-editor/Kit.lua, #529), so disarm only
-- lowers on mobile -- setTextInput is global SDL state, not per-widget.
function RomImporter:_armTextInput()
  if love.keyboard and love.keyboard.setTextInput then
    pcall(love.keyboard.setTextInput, true)
  end
end

function RomImporter:_disarmTextInput()
  if not self.android then return end
  if love.keyboard and love.keyboard.setTextInput then
    pcall(love.keyboard.setTextInput, false)
  end
end

function RomImporter:_focusOnlineField(key)
  self._onlineFocus = key
  local OnlinePanel = require("src.import.OnlinePanel")
  local st = OnlinePanel.state(self)
  if key == "online-name" then st.nameDraft = st.name or "" end
  self:_armTextInput()
end

function RomImporter:_commitOnlineField()
  local key = self._onlineFocus
  self._onlineFocus = nil
  self:_disarmTextInput()
  if key ~= "online-name" then return end
  local OnlinePanel = require("src.import.OnlinePanel")
  local st = OnlinePanel.state(self)
  OnlinePanel.setName(self, st.nameDraft or "")
  st.nameDraft = nil
end

function RomImporter:playArena(version, cartId, spec)
  if not version or not spec then return false end
  self._handedOff = true
  resetPointerCursor(self)
  if self._flex then require("src.import.LauncherView").detach(self) end
  if self.onComplete then self.onComplete(version, cartId, { arena = spec }) end
  return true
end

function RomImporter:_blurPanelFields()
  if self._pcPicker then return end
  if self._onlineFocus then
    self:_commitOnlineField()
    return
  end
  if not (self._findSearchFocus or self._skinUrlFocus) then return end
  if self._indexPrompt or self._rename or self._settingsText
      or self._profileSavePrompt or self._profileRenamePrompt
      or (self._syncModal and self._syncFocus) then
    return
  end
  self._findSearchFocus = false
  self._skinUrlFocus = false
  self:_disarmTextInput()
end

function RomImporter:_beginRename(scope, id)
  local label
  for _, slot in ipairs(self.slots[scope] or {}) do
    if slot.id == id then label = slot.label break end
  end
  self._rename = { version = scope, id = id, text = label or "" }
  self._slotPress = nil -- cancel any armed click/drag on the list
  self:_armTextInput()
end

function RomImporter:_commitRename()
  local r = self._rename
  if not r then return end
  self._rename = nil
  self:_disarmTextInput()
  local SaveData = require("src.core.SaveData")
  local cart = cartOfScope(r.version)
  if cart then
    SaveData.renameCartSlot(cart, r.id, r.text)
  else
    SaveData.renameSlot(r.version, r.id, r.text)
  end
  self:_refreshSlots(r.version)
end

function RomImporter:textinput(text)
  if self._syncModal and self._syncFocus then
    self:_syncTypeInto(self._syncFocus, text)
    return
  end
  if self._profileSavePrompt then
    self._profileSavePrompt.text = utf8Cap((self._profileSavePrompt.text or "") .. text, MAX_SLOT_LABEL)
    return
  end
  if self._profileRenamePrompt then
    self._profileRenamePrompt.text = utf8Cap((self._profileRenamePrompt.text or "") .. text, MAX_SLOT_LABEL)
    return
  end
  if self._cartSave then
    local CartManifest = require("src.carts.CartManifest")
    self._cartSave.text =
      utf8Cap(self._cartSave.text .. text, CartManifest.MAX_TITLE)
    self._cartSave.error = nil
    return
  end
  if self._settingsText then
    local st = self._settingsText
    st.text = utf8Cap(st.text .. text, st.maxLen or MAX_SLOT_LABEL)
    return
  end
  if self._indexPrompt then
    -- URLs never contain a literal space, and a pasted one usually arrives
    -- with a stray newline attached
    self._indexPrompt.text =
      utf8Cap(self._indexPrompt.text .. text:gsub("%s", ""), MAX_INDEX_URL)
    return
  end
  if self._onlineFocus then
    local OnlinePanel = require("src.import.OnlinePanel")
    local st = OnlinePanel.state(self)
    if self._onlineFocus == "online-name" then
      st.nameDraft = OnlinePanel.sanitizeName((st.nameDraft or "") .. text)
    elseif self._onlineFocus == "online-note" then
      st.note = utf8Cap((st.note or "") .. text, OnlinePanel.NOTE_MAX)
    elseif self._onlineFocus == "online-code" then
      st.joinCode = OnlinePanel.sanitizeCode((st.joinCode or "") .. text)
    elseif self._onlineFocus == "online-trade-code" then
      local tr = OnlinePanel.tradeState(self)
      tr.code = OnlinePanel.sanitizeCode((tr.code or "") .. text)
    elseif self._onlineFocus == OnlinePanel.PC_FIELD then
      local pc = OnlinePanel.pcPicker(self)
      OnlinePanel.pcQuery(self, ((pc and pc.query) or "") .. text)
    end
    return
  end
  if self._skinUrlFocus then
    self.skinUrl = utf8Cap((self.skinUrl or "") .. text:gsub("%s", ""),
      MAX_SKIN_URL)
    return
  end
  if self._findSearchFocus then
    self.findQuery = utf8Cap((self.findQuery or "") .. text, MAX_FIND_QUERY)
    self.findScroll = 0
    return
  end
  if not self._rename then return end
  self._rename.text = utf8Cap(self._rename.text .. text, MAX_SLOT_LABEL)
end

-- Clipboard into the index prompt, shared by ctrl/cmd+V and the prompt's
-- on-screen PASTE button (#578).  Same rule as typed input: URLs never
-- contain a literal space, and a pasted one usually arrives with a stray
-- newline attached.
function RomImporter:_pasteIndexUrl()
  if not self._indexPrompt then return end
  local ok, text = pcall(love.system.getClipboardText)
  if ok and type(text) == "string" then
    self._indexPrompt.text =
      utf8Cap(self._indexPrompt.text .. text:gsub("%s", ""), MAX_INDEX_URL)
  end
end

-- "+ New save slot": register an empty slot, make it active, relist, and pin the
-- scroll to the bottom (clamped next draw) so the new row is on screen.
function RomImporter:_newSlot(scope)
  local SaveData = require("src.core.SaveData")
  local cart = cartOfScope(scope)
  local id
  if cart then
    id = SaveData.createCartSlot(cart)
    if id then SaveData.setActiveCartSlot(cart, id) end
  else
    id = SaveData.createSlot(scope)
    SaveData.setActiveSlot(scope, id)
  end
  self:_refreshSlots(scope)
  self.activeSlot[scope] = id
  self.slotScroll[scope] = math.huge
end

-- Mouse wheel: forwarded into the FlexLove view (installed onto the global
-- love.wheelmoved in new(); see the chain there).  Scroll containers and the
-- modal scrollers all resolve inside the toolkit.
function RomImporter:wheelmoved(dx, dy)
  if not self._flex then return end
  require("src.import.LauncherView").wheelmoved(self, dx, dy)
end

-- Reload the mods list from LauncherMods (the source of truth: it reads the
-- same options.mods enable-state the loader persists).  Cheap enough to call on
-- any toggle / install; the per-frame draw calls it lazily through _ensureMods
-- so a still list costs nothing after the first paint.
function RomImporter:_refreshMods()
  local LauncherMods = require("src.mods.LauncherMods")
  local SaveData = require("src.core.SaveData")
  self._cartPlan = nil
  self._profileCache = nil
  self._cartCaptureCache = nil
  self.findInstalled = nil
  self.safeMode = SaveData.isSafeMode(SaveData.loadOptions())
  -- Once per session, ahead of the first listing: pull in any mod the player
  -- unzipped beside the executable, which an ordinary (non-portable) install
  -- has no way to read.  It happens here rather than behind a button because
  -- the failure being fixed is one where nothing on screen suggests there is
  -- anything to press -- the panel just comes up empty.  Guarded so a toggle
  -- or a delete does not re-scan; adoptStrays is idempotent regardless.
  if not self.modStraysChecked then
    self.modStraysChecked = true
    local imported, failed = {}, {}
    for _, s in ipairs(LauncherMods.adoptStrays() or {}) do
      table.insert(s.err and failed or imported, s.id)
    end
    -- the failure wins the notice: an import that worked speaks for itself in
    -- the list right below it, one that did not is the only word they get
    if #imported > 0 then
      self.modNotice = { ok = true,
        text = "Imported from the game folder: " .. table.concat(imported, ", ") }
    end
    if #failed > 0 then
      self.modNotice = { ok = false,
        text = "Found beside the game but could not import: "
               .. table.concat(failed, ", ") }
    end
  end
  local listed = LauncherMods.list(self.modScope) or {}
  self.mods = listed
  if self.modScope then
    local kept = {}
    for _, m in ipairs(listed) do
      if m.targetsHere ~= false then kept[#kept + 1] = m end
    end
    self.mods = kept
    self._cartCaptureCache = { version = self.modScope, n = #kept }
  end
  -- a pin is judged against the whole listing: the cart named it, so it is
  -- listed even where the game filter above would have dropped it
  local cartId, report = self:modCartPlan(listed)
  if cartId then self.mods = self:_cartPinRows(cartId, report, listed) end
end

-- The cart the MODS panel is answering for, with the plan that resolves its
-- pins, or nil when the panel is on a base game.
function RomImporter:modCartPlan(listed)
  local version = self.modScope
  if not version then return nil end
  local id = self.activeCart and self.activeCart[version] or nil
  if not id then return nil end
  local report = self:cartPlan(version, listed)
  if type(report) ~= "table" or type(report.pins) ~= "table" then return nil end
  return id, report, version
end

function RomImporter:cartPinsNote(cartId, cartReport)
  if not cartId then return nil end
  return Strings(
    "%s decides which mods run. Switch its pins one at a time, or pick the base game above.",
    (cartReport and cartReport.title) or cartId)
end

local function missingPinRow(imp, id, pin)
  local version = type(pin) == "table" and pin.version or nil
  return { id = id, name = id, version = version, badge = "MOD",
           description = "", enabled = false, status = "missing",
           statusDetail = Strings("Pinned by this cart but not installed"),
           experimental = false, targetsHere = true,
           manifest = { id = id, version = version },
           dependencySpecs = {}, requiredImports = {}, imports = {},
           missingRequiredImports = 0, missingOptionalImports = 0,
           safeMode = imp.safeMode == true, cartMissing = true }
end

-- The pinned set, resolved exactly as Loader:_applyCart resolves it: the
-- cart's own switch, overridden by the player's answer only where the seal
-- hands that switch over (Loader.pinTogglable).
function RomImporter:_cartPinRows(cartId, report, rows)
  local CartManifest = require("src.carts.CartManifest")
  local Loader = require("src.mods.Loader")
  local SaveData = require("src.core.SaveData")
  local byId = {}
  for _, row in ipairs(rows or {}) do byId[row.id] = row end
  local options = SaveData.loadOptions()
  local out = {}
  for _, id in ipairs(report.order or {}) do
    local pin = report.pins[id]
    local source = byId[id]
    -- a copy: the listing's own row still answers for the base game
    local row = {}
    if source then
      for key, value in pairs(source) do row[key] = value end
      row.cartMissing = nil
    else
      row = missingPinRow(self, id, pin)
    end
    local togglable = Loader.pinTogglable(report, pin)
    local on = CartManifest.modEnabled(pin)
    if togglable then
      local chosen = SaveData.cartModEnabled(options, cartId, id)
      if type(chosen) == "boolean" then on = chosen end
    end
    row.cartId, row.cartSeal = cartId, report.seal
    row.cartTitle = report.title or cartId
    row.cartPin, row.cartTogglable = true, togglable and not row.cartMissing
    row.cartBase = self.modScope
    -- a pin nothing provides cannot run, whatever the cart asked for
    row.enabled = on and not self.safeMode and not row.cartMissing
    -- one cart, one game: the per-game checkbox row is not this row's answer
    row.enabledByVersion = nil
    out[#out + 1] = row
  end
  return out
end

-- Point the MODS panel at one game (or nil for all of them) and relist, so
-- every row's status is answered for that game.
function RomImporter:_setModScope(version)
  self.modScope = GameVersion.VERSIONS[version] and version or nil
  self:_refreshMods()
end

function RomImporter:_ensureMods()
  if not self.mods then self:_refreshMods() end
end

-- Resolve GitHub status for every installed mod that declares a github field.
-- This is deliberately opt-in: only the explicit "Check for updates" action
-- calls it. Opening, scrolling, toggling, or relisting the MODS tab must not
-- create a burst of release work behind the list. force=true bypasses the 6h
-- cache on every repo. Results live on self.modUpdateInfo[id] = {
-- status, latest, best, releases } and resolve asynchronously across frames.
function RomImporter:_syncModUpdateInfo(force)
  local ModUpdate = require("src.mods.ModUpdate")
  self.modUpdateInfo = self.modUpdateInfo or {}
  local pending = {}
  for _, m in ipairs(self.mods or {}) do
    if m.github and m.github ~= "" then
      pending[#pending + 1] = { mod = m,
        h = ModUpdate.beginFetchReleases(m.github, m.id, { force = force == true }) }
    else
      self.modUpdateInfo[m.id] = nil
    end
  end
  self._modInfoFetch = (#pending > 0) and pending or nil
  -- Bump immediately so a mod that lost its github field (or a list that
  -- shrank) is reflected without waiting on the network.
  self._modUpdateRev = (self._modUpdateRev or 0) + 1
end

-- Drive in-flight release checks one frame at a time.  Called from update().
-- Deliberately NOT behind the blocking overlay: this is background enrichment
-- of rows that are already usable, so the list stays interactive while the
-- download counts and update badges fill in.  Individual rows show their own
-- inline spinner instead.
function RomImporter:_pumpModInfoFetch()
  local pending = self._modInfoFetch
  if not pending then return end
  local ModUpdate = require("src.mods.ModUpdate")
  local remaining, changed = {}, false
  for _, item in ipairs(pending) do
    local m = item.mod
    local ok, done, releases, err = pcall(ModUpdate.pumpFetchReleases, item.h)
    if not ok then
      self.modUpdateInfo[m.id] = { status = "error", err = tostring(done) }
      changed = true
    elseif done then
      changed = true
      if releases then
        local status, best = ModUpdate.statusFor(m.version, releases)
        local cached = ModUpdate.readCache(m.github)
        self.modUpdateInfo[m.id] = {
          status = status,
          latest = best and best.version or nil,
          best = best,
          releases = releases,
          downloads = ModUpdate.totalDownloads(releases),
          dates = ModUpdate.releaseDates(releases),
          err = nil,
          checkedAt = (cached and cached.checkedAt) or os.time(),
        }
      else
        self.modUpdateInfo[m.id] = {
          status = "error", latest = nil, best = nil, releases = nil,
          err = tostring(err),
        }
      end
    else
      remaining[#remaining + 1] = item
    end
  end
  self._modInfoFetch = (#remaining > 0) and remaining or nil
  if changed then
    -- Bump so the view's sorted-list cache (keyed on this revision) rebuilds
    -- when release/download data actually changes, not every frame.
    self._modUpdateRev = (self._modUpdateRev or 0) + 1
  end
end

-- True while any mod's release check is still in flight, so a row can show
-- an inline spinner instead of "Not checked for updates yet".
function RomImporter:_modInfoPending(id)
  for _, item in ipairs(self._modInfoFetch or {}) do
    if item.mod.id == id then return true end
  end
  return false
end

function RomImporter:_modUpdateInfo(id)
  return self.modUpdateInfo and self.modUpdateInfo[id] or nil
end

function RomImporter:_rejudgeModUpdate(id, fallbackVersion)
  if type(id) ~= "string" then return end
  local info = self:_modUpdateInfo(id)
  local releases = info and info.releases
  if type(releases) ~= "table" or #releases == 0 then return end
  local installed
  for _, m in ipairs(self.mods or {}) do
    if m.id == id then installed = m.version break end
  end
  installed = installed or fallbackVersion
  if type(installed) ~= "string" or installed == "" then return end
  local ModUpdate = require("src.mods.ModUpdate")
  local status, best = ModUpdate.statusFor(installed, releases)
  info.status = status
  info.latest = best and best.version or nil
  info.best = best
  info.err = nil
  self._modUpdateRev = (self._modUpdateRev or 0) + 1
  for _, item in ipairs(self._modInfoFetch or {}) do
    if item.mod and item.mod.id == id then item.mod.version = installed end
  end
end

-- Flip one game's mod flag (persisted via LauncherMods.setEnabled) and relist
-- so that game's checkbox and status chips reflect the new resolution.
-- Enabling an experimental mod arms a confirmation for that same game.
function RomImporter:_toggleMod(id, confirmed, version)
  if self.safeMode then
    self.modNotice = { ok = false, text = "Safe mode is active. Turn it off in the Bug tab to change mods." }
    return
  end
  local cartId, cartReport = self:modCartPlan()
  if cartId then
    self:_toggleCartMod(cartId, cartReport, id, confirmed)
    return
  end
  local LauncherMods = require("src.mods.LauncherMods")
  local cur, experimental = false, false
  for _, m in ipairs(self.mods or {}) do
    if m.id == id then
      if version and m.enabledByVersion then
        cur = m.enabledByVersion[version] == true
      else
        cur = m.enabled
      end
      experimental = m.experimental == true
      break
    end
  end
  local want = not cur
  if want and experimental and not confirmed then
    self._modConfirm = {
      kind = "experimental", id = id, version = version,
      title = "Experimental mod",
      yesLabel = "Enable",
      lines = {
        "This mod is marked experimental.",
        "It may be unfinished or unstable.",
        "Enable it anyway?",
      },
    }
    return
  end
  self._modConfirm = nil
  LauncherMods.setEnabled(id, want, version or self.modScope)
  self:_refreshMods()
end

-- A cart's pin is switched in the cart's own scope, never in the per-game
-- flags, and only where the seal hands that switch over.  Loader.pinTogglable
-- is the single authority on that, in the launcher as in the game.
function RomImporter:_toggleCartMod(cartId, report, id, confirmed)
  local CartManifest = require("src.carts.CartManifest")
  local Loader = require("src.mods.Loader")
  local SaveData = require("src.core.SaveData")
  local title = (report and report.title) or cartId
  local pin = report and report.pins and report.pins[id] or nil
  if not pin then
    self.modNotice = { ok = false, text = Strings(
      "%s decides which mods run. A cart's mod set cannot be added to or taken from.",
      title) }
    return
  end
  local row
  for _, m in ipairs(self.mods or {}) do
    if m.id == id then row = m break end
  end
  if row and row.cartMissing then
    self.modNotice = { ok = false, text = Strings(
      "%s pins %s, but it is not installed.", title, id) }
    return
  end
  if not Loader.pinTogglable(report, pin) then
    self.modNotice = { ok = false, text = Strings(
      "%s is sealed: its mods run exactly as pinned. Break the seal on the cart's own page to change that.",
      title) }
    return
  end
  local on = CartManifest.modEnabled(pin)
  local chosen = SaveData.cartModEnabled(SaveData.loadOptions(), cartId, id)
  if type(chosen) == "boolean" then on = chosen end
  local want = not on
  if want and row and row.experimental and not confirmed then
    self._modConfirm = {
      kind = "experimental", id = id, version = self.modScope,
      title = "Experimental mod",
      yesLabel = "Enable",
      lines = {
        "This mod is marked experimental.",
        "It may be unfinished or unstable.",
        "Enable it anyway?",
      },
    }
    return
  end
  self._modConfirm = nil
  SaveData.setCartModEnabled(cartId, id, want)
  self:_refreshMods()
  local name = (row and row.name) or id
  self.modNotice = { ok = true, text = want
    and Strings("Switched %s on for %s.", name, title)
    or Strings("Switched %s off for %s.", name, title) }
end

-- Enable all / Disable all (#647).  One options write for the whole list
-- (LauncherMods.setAllEnabled) and one relist afterwards, so the count, the
-- switches and every status chip resolve together instead of per mod.
-- Enabling routes through the same experimental confirm _toggleMod arms: that
-- opt-in is the only warning an experimental mod ever gets, and a bulk button
-- must not be the way around it.  Disabling needs no confirm -- it is the
-- recovery action, and Delete is the only destructive one on this panel.
-- An active cart owns its mod set, so the bulk buttons are refused there
-- rather than becoming a way to add to it or empty it.
function RomImporter:_setAllMods(want, confirmed)
  if self.safeMode then
    self.modNotice = { ok = false, text = "Safe mode is active. Turn it off in the Bug tab to change mods." }
    return
  end
  local cartId, cartReport = self:modCartPlan()
  if cartId then
    self.modNotice = { ok = false, text = self:cartPinsNote(cartId, cartReport) }
    return
  end
  local LauncherMods = require("src.mods.LauncherMods")
  local ids, experimental = {}, false
  for _, m in ipairs(self.mods or {}) do
    local mismatched = m.enabled ~= want
    if not self.modScope and type(m.enabledByVersion) == "table" then
      mismatched = false
      for _, game in ipairs(GameVersion.ORDER) do
        if m.enabledByVersion[game] ~= want then
          mismatched = true
          break
        end
      end
    end
    if mismatched then
      ids[#ids + 1] = m.id
      if want and m.experimental then experimental = true end
    end
  end
  if #ids == 0 then
    self.modNotice = { ok = true, text = want
      and Strings("Every mod is already enabled.")
      or Strings("Every mod is already disabled.") }
    return
  end
  if want and experimental and not confirmed then
    self._modConfirm = {
      kind = "enableAll",
      title = "Experimental mods",
      yesLabel = "Enable all",
      lines = {
        "Some of these mods are marked experimental.",
        "They may be unfinished or unstable.",
        "Enable everything anyway?",
      },
    }
    return
  end
  self._modConfirm = nil
  LauncherMods.setAllEnabled(ids, want, self.modScope)
  self:_refreshMods()
  self.modNotice = { ok = true, text = want
    and Strings("Enabled %d mods.", #ids)
    or Strings("Disabled %d mods.", #ids) }
end

-- GitHub Update / Check for updates / Versions. Soft-fails into modNotice.
-- Update button: when a newer release is known, confirm then install; when
-- already current, force-refresh the 6h cache and report / offer update.
function RomImporter:_modGithubAction(id, action)
  -- canFetchRemote, not networkValidated: the self-updater's gate used to
  -- stand in for this one, which cost Xbox the whole mod catalog rather than
  -- just the self-update it actually cannot do (#876).  Say what still works
  -- while we are here, since the native picker is live on every platform that
  -- lands in this branch.
  if not Platform.canFetchRemote() then
    self.modNotice = { ok = false,
      text = "Remote mod download is unavailable on this platform. Install a mod .zip from storage instead." }
    return
  end
  local ModUpdate = require("src.mods.ModUpdate")
  local row
  for _, m in ipairs(self.mods or {}) do
    if m.id == id then row = m; break end
  end
  if not row or not row.github then
    self.modNotice = { ok = false, text = "This mod has no github field" }
    return
  end

  -- Update, when we already know a newer release exists, needs no network:
  -- confirm straight away off the cached info.
  if action ~= "versions" then
    local info = self:_modUpdateInfo(id)
    if info and info.status == "available" and info.best then
      self._modConfirm = {
        kind = "update", id = row.id, release = info.best,
        title = "Update available",
        yesLabel = "Update",
        lines = {
          "Update " .. row.name .. "?",
          "Installed v" .. tostring(row.version),
          "Latest v" .. tostring(info.best.version),
        },
      }
      return
    end
  end

  -- ASYNC (was a blocking fetch).  Both remaining paths -- listing versions
  -- and a manual re-check -- hit the GitHub API, which is exactly the call
  -- that used to freeze the launcher mid-click.  One job at a time.
  if self._modCheck then return end
  self._modCheck = {
    id = row.id, name = row.name, github = row.github,
    version = row.version, action = action,
    h = ModUpdate.beginFetchReleases(row.github, row.id,
      { force = action ~= "versions" }),
  }
  self:_setBusy(action == "versions" and Strings("Loading versions")
    or Strings("Checking for updates"), row.name)
end

-- Drive the in-flight per-mod release check.  Called from _pumpModInfoFetch's
-- neighbourhood in update(); kept separate because this one IS behind the
-- blocking overlay (the user pressed a button and is waiting on the answer).
function RomImporter:_pumpModCheck()
  local job = self._modCheck
  if not job then return end
  local ModUpdate = require("src.mods.ModUpdate")
  local ok, done, releases, err = pcall(ModUpdate.pumpFetchReleases, job.h)
  if ok and not done then return end
  self._modCheck = nil
  self:_clearBusy()
  if not ok then
    self._modVersions = nil
    self.modNotice = { ok = false, text = "Update failed: " .. tostring(done) }
    return
  end
  if not releases then
    self.modNotice = { ok = false, text = tostring(err) }
    return
  end
  if #releases == 0 then
    self.modNotice = { ok = false, text = "No .zip releases found" }
    return
  end

  local status, best = ModUpdate.statusFor(job.version, releases)
  self.modUpdateInfo = self.modUpdateInfo or {}
  self.modUpdateInfo[job.id] = {
    status = status, latest = best and best.version, best = best,
    releases = releases, checkedAt = os.time(),
    downloads = ModUpdate.totalDownloads(releases),
    dates = ModUpdate.releaseDates(releases),
  }
  self._modUpdateRev = (self._modUpdateRev or 0) + 1

  if job.action == "versions" then
    self._modVersions = {
      id = job.id, name = job.name, current = job.version,
      releases = releases, page = 1,
    }
    self.modNotice = nil
    return
  end

  if status == "available" and best then
    self.modNotice = { ok = true,
      text = job.name .. ": new version available (v" .. best.version .. ")" }
    self._modConfirm = {
      kind = "update", id = job.id, release = best,
      title = "Update available",
      yesLabel = "Update",
      lines = {
        "Update " .. job.name .. "?",
        "Installed v" .. tostring(job.version),
        "Latest v" .. tostring(best.version),
      },
    }
  else
    self.modNotice = { ok = true,
      text = job.name .. " is up to date (v" .. tostring(job.version) .. ")" }
  end
end

-- ------- mod install / update (async download, blocking unzip)
--
-- The download is the slow half and now runs on the fetch pool behind a
-- non-dismissable loader; unzipping the finished archive is fast and stays
-- on the main thread, where love.filesystem belongs.  All three entry points
-- (update a mod, install a specific version, install from an index) funnel
-- into one in-flight job, so two installs can never race for the same id.
--
-- `spec` = { modId, name, release, notice = "mod"|"find"|"cart", verb, entry,
--            sha256, done }
-- `sha256` gates the unzip; `done(ok, text)` fires on either outcome so a
-- queue can drive one install at a time.
function RomImporter:_beginModInstall(spec)
  if self._modInstall or self._cartInstall then return end
  local ModIndex = require("src.mods.ModIndex")
  local release = spec.release
  -- An index entry only tells us WHERE the zip is; resolving that is
  -- ModIndex's job, exactly as in the synchronous path.
  if not release and spec.entry then
    local resolved, why = ModIndex.releaseFor(spec.entry)
    if not resolved then
      self:_modInstallFailed(spec, why or "this mod cannot be installed")
      return
    end
    release = resolved
  end
  if type(release) ~= "table" or not release.zip or not release.zip.url then
    self:_modInstallFailed(spec, "release has no downloadable .zip")
    return
  end
  local version = release.version or os.time()
  local tmpName = ("mod_update_%s_%s.zip"):format(tostring(spec.modId),
    tostring(version))
  local ModUpdate = require("src.mods.ModUpdate")
  self._modInstall = {
    spec = spec, release = release, version = release.version,
    h = ModUpdate.beginDownloadZip(release.zip.url, tmpName,
      release.zip.size),
  }
  self:_setBusy(Strings("Downloading %s", tostring(spec.name or spec.modId)),
    "v" .. tostring(release.version or "?"))
end

function RomImporter:_modInstallFailed(spec, msg)
  if not spec.quiet then
    local notice = { ok = false, text = tostring(msg) }
    if spec.notice == "find" then self.findNotice = notice
    elseif spec.notice ~= "cart" then self.modNotice = notice end
  end
  self:_clearBusy()
  if spec.done then spec.done(false, tostring(msg)) end
end

local function sha256hex(data)
  local digest = love.data.hash("sha256", data)
  if type(digest) == "userdata" and digest.getString then
    digest = digest:getString()
  end
  return love.data.encode("string", "hex", digest)
end

-- A cart pin records the sha256 of the archive it was built against.  A hash
-- that does not match is a different build, so nothing is installed.
function RomImporter.verifyArchiveSha256(path, want)
  if type(want) ~= "string" or not want:lower():match("^%x+$")
      or #want ~= 64 then
    return false, "the cart records no usable sha256 for this mod"
  end
  local ok, data = pcall(love.filesystem.read, path)
  if not ok or type(data) ~= "string" or data == "" then
    return false, "the downloaded archive could not be read back"
  end
  local hashed, got = pcall(sha256hex, data)
  if not hashed or type(got) ~= "string" then
    return false, "this platform cannot hash the archive, so it was not installed"
  end
  if got:lower() ~= want:lower() then
    return false, ("archive sha256 %s does not match the pinned %s")
      :format(got:sub(1, 12), want:sub(1, 12))
  end
  return true
end

function RomImporter:_pumpModInstall()
  local job = self._modInstall
  if not job then return end
  local ModUpdate = require("src.mods.ModUpdate")
  local ok, done, path, err, progress = pcall(ModUpdate.pumpDownloadZip, job.h)
  if ok and not done then
    -- Feed real download progress into the overlay when the size is known.
    if progress and self._busy then self._busy.progress = progress end
    return
  end
  self._modInstall = nil
  local spec = job.spec
  if not ok then
    self:_modInstallFailed(spec, "download failed: " .. tostring(done))
    return
  end
  if not path then
    self:_modInstallFailed(spec, err or "download failed")
    return
  end
  -- Hash gate before the unzip: a pinned archive that does not match the cart
  -- is thrown away rather than installed.
  if spec.sha256 then
    local verified, why = RomImporter.verifyArchiveSha256(path, spec.sha256)
    if not verified then
      pcall(love.filesystem.remove, path)
      self:_modInstallFailed(spec, why)
      return
    end
  end
  -- Unzip + manifest check.  Fast, and it must run here: love.filesystem
  -- writes are main-thread only.
  self:_setBusy(Strings("Installing %s", tostring(spec.name or spec.modId)))
  local LauncherMods = require("src.mods.LauncherMods")
  local ran, res, resErr = pcall(LauncherMods.installDownloadedZip,
    spec.modId, path, job.version)
  self:_clearBusy()
  if not ran then
    self:_modInstallFailed(spec, "install failed: " .. tostring(res))
    return
  end
  if not res then
    self:_modInstallFailed(spec, resErr or "install failed")
    return
  end
  -- The installed list is what the Install / Installed labels read, so it has
  -- to be re-derived before the next paint or the card lies.
  pcall(self._refreshMods, self)
  self:_rejudgeModUpdate(spec.modId, resErr or job.version)
  local shown = tostring(resErr or job.version or "")
  local text = ("%s %s %s"):format(spec.verb or "Installed",
    tostring(spec.name or spec.modId), shown)
  if spec.quiet then
  elseif spec.notice == "find" then
    self.findNotice = { ok = true, text = text }
  elseif spec.notice ~= "cart" then
    self.modNotice = { ok = true, text = text }
  end
  -- A cart pins its whole load order, so the dependency modal would only
  -- interrupt the queue that is already installing the rest of it.
  if spec.notice ~= "cart" and not spec.quiet then
    local depCheck = LauncherMods.checkDependencies({ id = spec.modId })
    if depCheck and depCheck.hasIssues then
      self._modDepResolver = depCheck
    end
  end
  if spec.done then spec.done(true, text) end
end

-- ------- cart install from an index listing
--
-- A cart is one .g1rcart file, so the bytes go whole to CartStore.install and
-- never through the mod installer.  Shares the mod job's single-in-flight
-- rule: either entry point refuses while the other is running.
function RomImporter:_beginCartInstall(entry, spec)
  if self._modInstall or self._cartInstall then return end
  if self._updateAll and not (spec and spec.fromUpdateAll) then return end
  local ModIndex = require("src.mods.ModIndex")
  local release, why = ModIndex.releaseFor(entry)
  if type(release) ~= "table" or not (release.zip and release.zip.url) then
    local text = ("%s: %s"):format(tostring(entry.title or entry.id),
      tostring(why or "this cart has no downloadable release"))
    if not (spec and spec.quiet) then
      self.findNotice = { ok = false, text = text }
    end
    if spec and spec.done then spec.done(false, text) end
    return
  end
  local ModUpdate = require("src.mods.ModUpdate")
  local version = release.version or entry.version or os.time()
  local tmpName = ("cart_install_%s_%s%s"):format(
    tostring(entry.id):gsub("[^%w%-_]", "_"), tostring(version),
    require("src.carts.CartStore").EXT)
  self._cartInstall = {
    entry = entry, version = release.version or entry.version,
    quiet = spec and spec.quiet or nil, done = spec and spec.done or nil,
    h = ModUpdate.beginDownloadZip(release.zip.url, tmpName, release.zip.size),
  }
  self:_setBusy(Strings("Downloading %s", tostring(entry.title or entry.id)),
    "v" .. tostring(release.version or entry.version or "?"))
end

function RomImporter:_cartInstallFailed(msg, job)
  job = job or self._cartInstall
  self._cartInstall = nil
  self:_clearBusy()
  if not (job and job.quiet) then
    self.findNotice = { ok = false, text = tostring(msg) }
  end
  if job and job.done then job.done(false, tostring(msg)) end
end

function RomImporter:_pumpCartInstall()
  local job = self._cartInstall
  if not job then return end
  local ModUpdate = require("src.mods.ModUpdate")
  local ok, done, path, err, progress = pcall(ModUpdate.pumpDownloadZip, job.h)
  if ok and not done then
    if progress and self._busy then self._busy.progress = progress end
    return
  end
  local entry = job.entry
  local name = tostring(entry.title or entry.id)
  if not ok then
    return self:_cartInstallFailed(name .. ": download failed: " .. tostring(done))
  end
  if not path then
    return self:_cartInstallFailed(name .. ": " .. tostring(err or "download failed"))
  end
  self._cartInstall = nil
  local read, bytes = pcall(love.filesystem.read, path)
  pcall(love.filesystem.remove, path)
  if not read or type(bytes) ~= "string" or bytes == "" then
    return self:_cartInstallFailed(name .. ": the download could not be read back",
      job)
  end
  self:_setBusy(Strings("Installing %s", name))
  local CartStore = require("src.carts.CartStore")
  local ran, cart, installErr = pcall(CartStore.install, bytes)
  self:_clearBusy()
  if not ran then
    return self:_cartInstallFailed(name .. ": install failed: " .. tostring(cart),
      job)
  end
  if not cart then
    return self:_cartInstallFailed(name .. ": " .. tostring(installErr), job)
  end
  -- _refreshCarts caches per version, so the Custom Carts list for the game
  -- this cart plays as would keep its pre-install copy until a relaunch.
  -- The label art is cached per cart too, and a reinstall can repaint it.
  self:_refreshCarts(cart.base)
  self._cartPlan = nil
  self._cartridgeLabels = nil
  if not job.quiet then
    self.findNotice = { ok = true,
      text = Strings("Installed %s v%s. It is in this game's cart list now.",
        tostring(cart.title or cart.id), tostring(cart.version or "?")) }
    self:_offerCartPins(cart)
  end
  if job.done then job.done(true, tostring(cart.version or "?")) end
end

-- The pins a cart is missing, answered without disturbing whichever cart the
-- player currently has selected for that game.
function RomImporter:_cartPinsMissing(version, id)
  local wasCart = self.activeCart[version]
  local wasPlan = self._cartPlan
  self.activeCart[version] = id
  self._cartPlan = nil
  local ok, rows = pcall(self.cartFillRows, self, version)
  self.activeCart[version] = wasCart
  self._cartPlan = wasPlan
  return (ok and type(rows) == "table") and rows or {}
end

-- A cart whose pins are missing will not start, so ask once rather than
-- dead-end, and route a yes at the existing hash-verified fill queue.
function RomImporter:_offerCartPins(cart)
  local rows = self:_cartPinsMissing(cart.base, cart.id)
  if #rows == 0 then return end
  local info = GameVersion.info(cart.base)
  local title = tostring(cart.title or cart.id)
  self._modConfirm = {
    kind = "cartPins", version = cart.base, id = cart.id,
    title = "Install this cart's mods",
    yesLabel = "Install",
    lines = {
      ("%s pins %d mod(s) you do not have."):format(title, #rows),
      "Install them now? Each one is checked against the cart's own hash.",
      ("This selects %s as the cart for %s."):format(title,
        tostring((info and (info.launcherName or info.displayName))
          or cart.base)),
    },
  }
end

-- The confirm's yes.  The cart being filled has to be the selected one, which
-- is what cartFillRows and pressInstallCartMods both answer for.
function RomImporter:_installCartPins(version, id)
  self:_selectCart(version, id)
  self:pressInstallCartMods(version)
end

-- ------- one-call cart install for the ONLINE tab
function RomImporter:installCartForOnline(cartId, version, onDone)
  if type(cartId) ~= "string" or cartId == "" then
    if onDone then onDone(false, "no cart was named") end
    return false
  end
  if self._onlineCart then return false end
  self._onlineCart = { id = cartId, base = version, done = onDone,
                       stage = "index" }
  self:_ensureFind()
  return true
end

function RomImporter:_finishOnlineCart(ok, text)
  local job = self._onlineCart
  self._onlineCart = nil
  if job and job.done then pcall(job.done, ok, text) end
end

function RomImporter:pumpOnlineCartInstall()
  local job = self._onlineCart
  if not job then return end
  local CartStore = require("src.carts.CartStore")

  if job.stage == "index" then
    if self._findFetch then return end
    if not self.findLoaded then
      self:_ensureFind()
      return
    end
    local entry
    for _, row in ipairs((self.findIndex and self.findIndex.carts) or {}) do
      if row.id == job.id then
        entry = row
        break
      end
    end
    if not entry then
      return self:_finishOnlineCart(false,
        Strings("No mod index lists a cart called %s.", tostring(job.id)))
    end
    if self._modInstall or self._cartInstall then return end
    self.findNotice = nil
    self:_beginCartInstall(entry)
    if not self._cartInstall then
      return self:_finishOnlineCart(false,
        tostring((self.findNotice and self.findNotice.text)
          or "that cart has no download"))
    end
    job.stage = "download"
    return
  end

  if job.stage == "download" then
    if self._cartInstall then return end
    local ok, cart = pcall(CartStore.get, job.id)
    if not ok or type(cart) ~= "table" then
      return self:_finishOnlineCart(false,
        tostring((self.findNotice and self.findNotice.text)
          or "that cart did not install"))
    end
    self._modConfirm = nil
    job.base = cart.base
    job.title = cart.title or cart.id
    if #self:_cartPinsMissing(cart.base, job.id) == 0 then
      return self:_finishOnlineCart(true,
        Strings("%s is installed.", tostring(job.title)))
    end
    self:_installCartPins(cart.base, job.id)
    job.stage = "pins"
    return
  end

  if job.stage == "pins" then
    if self._cartFill then return end
    if #self:_cartPinsMissing(job.base, job.id) > 0 then
      return self:_finishOnlineCart(false,
        tostring((self.cartFillNotice and self.cartFillNotice.text)
          or "some of this cart's mods could not be installed"))
    end
    return self:_finishOnlineCart(true,
      Strings("%s and its mods are installed.", tostring(job.title or job.id)))
  end
end

-- Start an async pull for a single dependency
function RomImporter:_startDepPull(dep)
  if not dep or not dep.github then return end
  self._depPullState = self._depPullState or {}
  local hFetch = require("src.mods.ModUpdate").beginFetchReleases(dep.github, dep.id, { force = true })
  self._depPullState[dep.id] = {
    dep = dep,
    stage = "fetching",
    fetchHandle = hFetch,
  }
end

-- Pump all in-flight dependency pulls
function RomImporter:_pumpDepPulls()
  if not self._depPullState then return end
  local ModUpdate = require("src.mods.ModUpdate")
  local LauncherMods = require("src.mods.LauncherMods")

  for depId, state in pairs(self._depPullState) do
    if state.stage == "fetching" then
      local done, releases, err = ModUpdate.pumpFetchReleases(state.fetchHandle)
      if done then
        if err or not releases or #releases == 0 then
          state.stage = "error"
          state.err = err or "No downloadable releases found on GitHub"
        else
          local rel = releases[1]
          if not rel or not rel.zip or not rel.zip.url then
            state.stage = "error"
            state.err = "Latest release has no downloadable .zip asset"
          else
            local tmpName = ("dep_%s_%s.zip"):format(depId, tostring(rel.version or os.time()))
            state.dlHandle = ModUpdate.beginDownloadZip(rel.zip.url, tmpName, rel.zip.size)
            state.stage = "downloading"
            state.targetVersion = rel.version
          end
        end
      end
    elseif state.stage == "downloading" then
      local done, localPath, err, progress = ModUpdate.pumpDownloadZip(state.dlHandle)
      state.progress = progress
      if done then
        if err or not localPath then
          state.stage = "error"
          state.err = err or "Download failed"
        else
          state.stage = "installing"
          local okInst, versionRes = LauncherMods.installDownloadedZip(depId, localPath, state.targetVersion)
          if okInst then
            state.stage = "done"
            pcall(self._refreshMods, self)
            if self._modDepResolver and self._modDepResolver.targetMod then
              local updated = LauncherMods.checkDependencies(self._modDepResolver.targetMod)
              self._modDepResolver = updated
            end
          else
            state.stage = "error"
            state.err = tostring(versionRes or "Installation failed")
          end
        end
      end
    end
  end
end

function RomImporter:_confirmModUpdate(modId, release)
  local row
  for _, m in ipairs(self.mods or {}) do
    if m.id == modId then row = m; break end
  end
  self:_beginModInstall({
    modId = modId, name = row and row.name or modId,
    release = release, verb = "Updated", notice = "mod",
  })
end

function RomImporter:_installModVersion(modId, release)
  self._modVersions = nil
  self._modReleaseNotes = nil
  self:_beginModInstall({
    modId = modId, name = modId, release = release,
    verb = "Installed", notice = "mod",
  })
end


local function repoKey(...)
  local Manifest = require("src.mods.Manifest")
  for i = 1, select("#", ...) do
    local value = select(i, ...)
    if type(value) == "string" and value ~= "" then
      local ok, key = pcall(Manifest.parseGithub, value)
      if ok and type(key) == "string" then return key:lower() end
    end
  end
  return nil
end

function RomImporter:_updateAllCartRows()
  local feed = (self.findIndex and self.findIndex.carts) or nil
  local seen = self:_findInstalledCarts()
  local cache = self._cartUpdateCache
  if cache and cache.feed == feed and cache.seen == seen then
    return cache.rows
  end
  local rows = {}
  self._cartUpdateCache = { feed = feed, seen = seen, rows = rows }
  if type(feed) ~= "table" or #feed == 0 then return rows end
  local listed = {}
  for _, entry in ipairs(feed) do
    if type(entry) == "table" and entry.id and seen[entry.id] then
      listed[entry.id] = entry
    end
  end
  if next(listed) == nil then return rows end
  local ok, installed = pcall(function()
    return require("src.carts.CartStore").list()
  end)
  if not ok or type(installed) ~= "table" then return rows end
  local ModIndex = require("src.mods.ModIndex")
  local ModUpdate = require("src.mods.ModUpdate")
  for _, row in ipairs(installed) do
    local entry = listed[row.id]
    local mine = row.cart and repoKey(row.cart.repo)
    if entry and mine and mine == repoKey(entry.github, entry.repo)
        and ModIndex.canInstall(entry)
        and ModUpdate.isNewer(row.version, ModIndex.displayVersion(entry)) then
      rows[#rows + 1] = { kind = "cart", id = row.id, entry = entry,
                          name = row.title or row.id, from = row.version,
                          to = ModIndex.displayVersion(entry) }
    end
  end
  return rows
end

function RomImporter:_updateAllRows()
  local rows = {}
  if not (self.modCartPlan and self:modCartPlan()) then
    for _, m in ipairs(self.mods or {}) do
      local info = self:_modUpdateInfo(m.id)
      if info and info.status == "available" and info.best
          and info.best.zip and info.best.zip.url then
        rows[#rows + 1] = { kind = "mod", id = m.id, name = m.name,
                            release = info.best, from = m.version }
      end
    end
  end
  for _, row in ipairs(self:_updateAllCartRows()) do rows[#rows + 1] = row end
  return rows
end

function RomImporter:updateAllAvailable()
  if self.safeMode then return false end
  if self._updateAll or self._modInstall or self._cartInstall
      or self._cartFill then return false end
  return true
end

function RomImporter:pressUpdateAllMods()
  if not self:updateAllAvailable() then return false end
  if not Platform.canFetchRemote() then
    self.modNotice = { ok = false,
      text = "Remote mod download is unavailable on this platform. Install a mod .zip from storage instead." }
    return false
  end
  self._updateAll = { stage = "check", index = 0, updated = 0,
                      updatedIds = {}, updatedCarts = {}, failures = {} }
  self.modNotice = nil
  self:_syncModUpdateInfo(true)
  self:_ensureFind()
  self:_setBusy(Strings("Checking for updates"), nil,
    function() self:_cancelUpdateAll() end)
  self:_pumpUpdateAll()
  return true
end

function RomImporter:_cancelUpdateAll()
  local job = self._updateAll
  if not job or job.cancelled then return end
  job.cancelled = true
  if self._modInstall or self._cartInstall then
    self:_setBusy(Strings("Finishing the last download"))
  else
    self:_finishUpdateAll(true)
  end
end

function RomImporter:_pumpUpdateAll()
  local job = self._updateAll
  if not job then return end

  if job.stage == "check" then
    if self._modInfoFetch or self._findFetch then return end
    job.rows = self:_updateAllRows()
    job.total = #job.rows
    if job.cancelled or job.total == 0 then
      return self:_finishUpdateAll(job.cancelled)
    end
    job.stage = "next"
    return
  end

  if job.stage ~= "next" then return end
  if job.cancelled then return self:_finishUpdateAll(true) end
  if self._modInstall or self._cartInstall then return end
  job.index = job.index + 1
  local row = job.rows[job.index]
  if not row then return self:_finishUpdateAll() end
  job.stage = "installing"
  local function finished(ok, text)
    if ok then
      job.updated = job.updated + 1
      if row.kind == "cart" then
        job.updatedCarts[#job.updatedCarts + 1] =
          { id = row.id, base = row.entry and row.entry.base,
            name = row.name or row.id }
      else
        job.updatedIds[#job.updatedIds + 1] = row.id
      end
    else
      job.failures[#job.failures + 1] =
        ("%s: %s"):format(tostring(row.name or row.id), tostring(text))
    end
    job.stage = "next"
  end
  if row.kind == "cart" then
    self:_beginCartInstall(row.entry,
      { quiet = true, fromUpdateAll = true, done = finished })
  else
    self:_beginModInstall({
      modId = row.id, name = row.name, release = row.release,
      verb = "Updated", notice = "mod", quiet = true, done = finished,
    })
  end
  if self._modInstall or self._cartInstall then
    self:_setBusy(Strings("Updating %s (%d of %d)",
      tostring(row.name or row.id), job.index, job.total),
      "v" .. tostring(row.to or (row.release and row.release.version) or "?"),
      function() self:_cancelUpdateAll() end)
  elseif job.stage == "installing" then
    job.stage = "next"
  end
end

function RomImporter:_finishUpdateAll(cancelled)
  local job = self._updateAll
  self._updateAll = nil
  self:_clearBusy()
  pcall(self._refreshMods, self)
  if not job then return end
  if cancelled then
    self.modNotice = { ok = true, failures = job.failures,
      text = Strings("Stopped after updating %d items.", job.updated) }
  elseif (job.total or 0) == 0 then
    self.modNotice = { ok = true, text = Strings("Everything is up to date.") }
  elseif #job.failures == 0 then
    self.modNotice = { ok = true,
      text = Strings("Updated %d items.", job.updated) }
  else
    self.modNotice = { ok = false, failures = job.failures,
      text = Strings("Updated %d of %d. %d failed:", job.updated, job.total,
        #job.failures) }
  end
  for _, cart in ipairs(job.updatedCarts or {}) do
    if cart.base then
      local missing = #self:_cartPinsMissing(cart.base, cart.id)
      if missing > 0 then
        local lines = self.modNotice.failures or {}
        lines[#lines + 1] = Strings(
          "%s now pins %d mod(s) you do not have. Open it in Custom Carts to install them.",
          tostring(cart.name), missing)
        self.modNotice.failures = lines
      end
    end
  end
  local LauncherMods = require("src.mods.LauncherMods")
  for _, id in ipairs(job.updatedIds or {}) do
    local ok, depCheck = pcall(LauncherMods.checkDependencies, { id = id })
    if ok and depCheck and depCheck.hasIssues then
      self._modDepResolver = depCheck
      break
    end
  end
end


-- NX / desktop / Android labels and inbox hints for the FlexLove view.
function RomImporter:_modsImportButtonLabel()
  if self.isNX then return Strings("Scan again") end
  return Strings("Import mod .zip")
end

function RomImporter:_modsDefaultHint()
  if self.isNX then
    local saveDir = love.filesystem.getSaveDirectory()
    local rel = RomImporter.mtpHintPath(saveDir)
    if rel ~= "" and rel:sub(-1) ~= "/" then rel = rel .. "/" end
    return Strings("Copy a .zip via MTP into %s/imports/mods/\n"
      .. "DBI MTP → 1: SD Card/%simports/mods/", saveDir, rel)
  end
  if self.android then return Strings("Or copy a mod .zip via USB.") end
  return Strings("Or drop a mod .zip onto the window.")
end

function RomImporter:_savesDefaultHint(version)
  if self.isNX then
    version = self:_resolveSaveVersion(version)
    local inbox = savesInboxDir(version)
    local saveDir = love.filesystem.getSaveDirectory()
    local rel = RomImporter.mtpHintPath(saveDir)
    if rel ~= "" and rel:sub(-1) ~= "/" then rel = rel .. "/" end
    local game = GameVersion.info(version).displayName
    return Strings("Copy a %s .sav via MTP into %s/%s/\n"
      .. "DBI MTP → 1: SD Card/%s%s/", game, saveDir, inbox, rel, inbox)
  end
  if self.android then
    return Strings("Import or export a .sav with the system file picker.")
  end
  return Strings("Import a .sav to a new slot, or export the active slot.")
end

function RomImporter:_modsEmptyHint()
  if self.isNX then
    return Strings("No mods installed - copy a .zip into imports/mods/ "
      .. "and tap Scan again.")
  end
  if self.android then
    return "No mods installed - tap Import mod .zip to add one."
  end
  return Strings("No mods installed - drop a mod .zip here to add one.")
end

-- ------- FIND MODS: browsing a community mod index -------------------------
--
-- The index is metadata only (src/mods/ModIndex.lua): it says where a mod's
-- zip lives, and the install runs through exactly the same path "Import mod
-- .zip" does.  Nothing here is automatic -- no index ships with the launcher,
-- and the tab stays an empty "Add an index" prompt until the player names one,
-- because subscribing to somebody's list of mods is a trust decision and not a
-- default.
--
-- Fetching is the same synchronous curl the update checks already use, cached
-- in options for a day, so the first open of the tab costs one round trip and
-- every later one is free until the player hits Refresh.

-- The sources list, reloaded from options.  Cheap; called whenever the panel
-- has reason to think the list changed.
function RomImporter:_refreshFindSources()
  local ModIndex = require("src.mods.ModIndex")
  local ok, rows = pcall(ModIndex.sources)
  self.findSources = ok and rows or {}
end

-- Fetch every source and merge into one listing.  First source wins on a
-- duplicate id, matching how the mod loader resolves two mods with one id --
-- there is one "nuzlocke" as far as the installer is concerned, so the panel
-- must not offer two.  Per-source failures are collected rather than fatal: an
-- index that is down should cost its own rows, not everybody else's.
-- ASYNC (was synchronous).  Every source used to be fetched with a blocking
-- curl call inside the draw path, so opening Find Mods froze the window for
-- as long as the slowest index took -- measured at over two minutes on a
-- cold open, with no spinner, because the frame that would have drawn one
-- never ran.  The fetch now starts here and completes across later frames in
-- _pumpFindFetch.  Only an explicit Refresh is blocking; boot prewarm and the
-- first visit keep the launcher interactive while the listing arrives.
function RomImporter:_refreshFind(force)
  -- The notice is the fix, not the gate (#876).  This branch used to return an
  -- empty listing silently, and because the player had by then added a source,
  -- the panel skipped its "No mod index added" card and rendered the merged
  -- listing empty state instead: a valid feed reported as "This index lists no
  -- mods yet."  Every other failure on this panel surfaces through findNotice,
  -- and this one has to as well, or adding an index looks like it worked and
  -- the index looks empty.
  if not Platform.canFetchRemote() then
    self.findLoaded = true
    self.findIndex = { mods = {}, carts = {}, categories = {}, baseGames = {} }
    self.findNotice = { ok = false,
      text = "Mod indexes cannot be fetched on this platform. Install a mod .zip from storage instead." }
    return
  end
  local ModIndex = require("src.mods.ModIndex")
  self:_refreshFindSources()
  local sources = self.findSources or {}
  if #sources == 0 then
    self.findIndex = { mods = {}, carts = {}, categories = {}, baseGames = {} }
    self.findLoaded = true
    return
  end
  -- One in-flight refresh at a time: a second Refresh press while the first
  -- is running would double-count every row into the merge.
  if self._findFetch then return end
  local handles = {}
  for i, source in ipairs(sources) do
    handles[i] = { source = source,
      h = ModIndex.beginFetch(source, { force = force == true }) }
  end
  self._findFetch = {
    handles = handles, force = force == true,
    mods = {}, seen = {}, cats = {}, catSeen = {}, errs = {},
    carts = {}, cartSeen = {}, bases = {}, baseSeen = {},
    stale = false, oldest = nil, at = 1,
  }
  if force == true then
    self:_setBusy(Strings("Fetching mod index"),
      #sources == 1 and (sources[1].label or sources[1].feed)
        or Strings("%d indexes", #sources))
  end
end

-- Drive the in-flight index fetch one frame at a time.  Called from update().
function RomImporter:_pumpFindFetch()
  local f = self._findFetch
  if not f then return end
  local ModIndex = require("src.mods.ModIndex")

  -- Pump every handle each frame; they run concurrently on the fetch pool.
  local allDone = true
  for _, item in ipairs(f.handles) do
    if not item.done then
      local ok, done, index, err, meta = pcall(ModIndex.pumpFetch, item.h)
      if not ok then
        item.done = true
        f.errs[#f.errs + 1] = (item.source.label or item.source.feed)
          .. ": " .. tostring(done)
      elseif done then
        item.done = true
        if not index then
          f.errs[#f.errs + 1] = (item.source.label or item.source.feed)
            .. ": " .. tostring(err)
        else
          item.index, item.meta = index, meta
        end
      else
        allDone = false
      end
    end
  end
  self._busyCount = nil
  if not allDone then return end

  -- Merge in SOURCE ORDER, not completion order: first source wins on a
  -- duplicate id, matching how the mod loader resolves two mods with one id,
  -- and that rule has to be stable regardless of which index answered first.
  for _, item in ipairs(f.handles) do
    local index, meta, source = item.index, item.meta, item.source
    if index then
      if meta and meta.stale then f.stale = true end
      if meta and meta.checkedAt then
        f.oldest = math.min(f.oldest or meta.checkedAt, meta.checkedAt)
      end
      for _, entry in ipairs(index.mods or {}) do
        if not f.seen[entry.id] then
          f.seen[entry.id] = true
          entry._source = source.label or source.feed
          entry._base = source.base
          f.mods[#f.mods + 1] = entry
        end
      end
      -- Carts merge on the same first-source-wins rule, in their own id
      -- space: a cart and a mod may share an id without shadowing each other.
      for _, entry in ipairs(index.carts or {}) do
        if not f.cartSeen[entry.id] then
          f.cartSeen[entry.id] = true
          entry._source = source.label or source.feed
          entry._base = source.base
          f.carts[#f.carts + 1] = entry
        end
      end
      for _, c in ipairs(ModIndex.categoriesIn(index)) do
        if not f.catSeen[c] then
          f.catSeen[c] = true
          f.cats[#f.cats + 1] = c
        end
      end
      for _, b in ipairs(ModIndex.baseGamesIn(index)) do
        if not f.baseSeen[b] then
          f.baseSeen[b] = true
          f.bases[#f.bases + 1] = b
        end
      end
    end
  end

  self.findIndex = { mods = f.mods, carts = f.carts, categories = f.cats,
                     baseGames = f.bases, stale = f.stale,
                     checkedAt = f.oldest }
  self.findLoaded = true
  if #f.errs > 0 then
    self.findNotice = { ok = false, text = table.concat(f.errs, "  -  ") }
  elseif f.force then
    self.findNotice = { ok = true,
      text = (#f.carts > 0)
        and Strings("Refreshed - %d mods and %d carts listed", #f.mods, #f.carts)
        or Strings("Refreshed - %d mods listed", #f.mods) }
  end
  -- A category that no longer exists after a refresh would filter everything
  -- away with no way back except guessing.  Same for a base game.
  if self.findCategory and not f.catSeen[self.findCategory] then
    self.findCategory = nil
  end
  if self.findBase and not f.baseSeen[self.findBase] then
    self.findBase = nil
  end
  self.findPage = 1
  self._findFetch = nil
  self:_clearBusy()
end

-- Clearing rebinds used to live here, behind a button on the game panel.  It
-- is now the RESET REBINDS row of the settings model
-- (src/import/LauncherSettings.lua), which edits the same options table the
-- rest of that panel does and saves through the same save() -- one control
-- for a setting that was never per-game in the first place.

-- ------- busy state (drives the non-dismissable loader overlay)
-- Anything that makes the user wait sets this; LauncherView renders it as a
-- blocking overlay so no operation can ever run invisibly.
function RomImporter:_setBusy(title, detail, cancel)
  self._busy = { title = title, detail = detail, cancel = cancel }
end

function RomImporter:_clearBusy()
  self._busy = nil
end

function RomImporter:_ensureFind()
  if not self.findLoaded then
    self:_refreshFindSources()
    if #(self.findSources or {}) == 0 then
      -- Nothing to fetch, but the panel is loaded: the empty state is the
      -- answer, not a pending request.
      self.findIndex = { mods = {}, carts = {}, categories = {}, baseGames = {} }
      self.findLoaded = true
    else
      self:_refreshFind(false)
    end
  end
end

-- Whether the FIND panel is browsing carts rather than mods.
function RomImporter:findingCarts()
  return self.findKind == "carts"
end

-- The switch itself.  Query survives the flip; the category / base filter
-- does not, because neither vocabulary applies to the other list.
function RomImporter:_setFindKind(kind)
  kind = (kind == "carts") and "carts" or "mods"
  if self.findKind == kind then return end
  self.findKind = kind
  self._findRowsCache = nil
  self._findSortCache = nil
  if self._pages then self._pages["find"] = 1 end
  self.findPage = 1
end

-- The rows the filters leave, and the installed-mod context the compatibility
-- warnings are judged against.
function RomImporter:_findRows()
  local carts = self:findingCarts()
  local all = (self.findIndex
    and (carts and self.findIndex.carts or self.findIndex.mods)) or {}
  -- The view asks every frame (immediate mode); only re-filter when the
  -- index, query, or filter actually changed.
  local c = self._findRowsCache
  if c and c.src == all and c.query == self.findQuery
      and c.category == self.findCategory and c.base == self.findBase
      and c.game == self.findGame then
    return c.rows
  end
  local ModIndex = require("src.mods.ModIndex")
  local rows = ModIndex.filter(all, {
    query = self.findQuery,
    category = (not carts) and self.findCategory or nil,
    base = carts and self.findBase or nil,
    game = self.findGame,
  })
  self._findRowsCache = { src = all, query = self.findQuery,
    category = self.findCategory, base = self.findBase,
    game = self.findGame, rows = rows }
  return rows
end

function RomImporter:_setFindGame(token)
  if token == "all" then token = nil end
  if self.findGame == token then return end
  self.findGame = token
  self._findRowsCache = nil
  self._findSortCache = nil
  if self._pages then self._pages["find"] = 1 end
  self.findPage = 1
end

function RomImporter:_findInstalledMap()
  if self:findingCarts() then return self:_findInstalledCarts() end
  if self.findInstalled then return self.findInstalled end
  local LauncherMods = require("src.mods.LauncherMods")
  if self.mods then
    self.findInstalled = {}
    for _, m in ipairs(self.mods) do
      self.findInstalled[m.id] = m.version or true
    end
  else
    self.findInstalled = LauncherMods.installedVersions() or {}
  end
  return self.findInstalled
end

-- id -> installed version for every cart on disk, whatever game it plays as.
-- Cached because the row loop asks once per frame.
function RomImporter:_findInstalledCarts()
  if self._findCartMap then return self._findCartMap end
  local map = {}
  local ok, rows = pcall(function()
    return require("src.carts.CartStore").index()
  end)
  if ok and type(rows) == "table" then
    for _, row in ipairs(rows) do map[row.id] = row.version or true end
  end
  self._findCartMap = map
  return map
end

-- Read the cached thumbnail for a card.  Starting a download is deliberately
-- separate: immediate-mode draw may call this for every visible row, but it
-- must not mutate the fetch queue or perform network work.
function RomImporter:_findThumb(entry)
  self._findThumbs = self._findThumbs or {}
  local cached = self._findThumbs[entry.id]
  if cached ~= nil then return cached or nil end
  local ModIndex = require("src.mods.ModIndex")
  local url = ModIndex.joinUrl(entry._base, entry.thumbnail)
  if not url then
    self._findThumbs[entry.id] = false
    return nil
  end
  return nil
end

-- Queue one thumbnail after draw has recorded the visible rows.  The fetch
-- pool runs off-thread; only the finished image decode stays in update().
function RomImporter:_startFindThumb(entry)
  self._findThumbs = self._findThumbs or {}
  if self._findThumbs[entry.id] ~= nil then return end
  local ModIndex = require("src.mods.ModIndex")
  local url = ModIndex.joinUrl(entry._base, entry.thumbnail)
  if not url then
    self._findThumbs[entry.id] = false
    return
  end
  -- ASYNC (was one blocking download per frame).  Only rows on the current
  -- page ever ask, so pagination already bounds this to a page's worth of
  -- requests; the fetch pool runs them off-thread and the card shows its
  -- placeholder until the image lands.
  self._findThumbFetch = self._findThumbFetch or {}
  if not self._findThumbFetch[entry.id] then
    local ext = url:match("%.(%a%a%a?%a?)$") or "png"
    local name = ("mod_thumb_%s.%s")
      :format(tostring(entry.id):gsub("[^%w%-_]", "_"), ext)
    local Fetch = require("src.net.Fetch")
    self._findThumbFetch[entry.id] = {
      -- A short ceiling on purpose: a page of these is queued at once, and
      -- each one's ceiling is part of the worst case for closing the window
      -- (Fetch.shutdown).  A thumbnail that has not arrived in 15s is not
      -- worth holding the process open for -- the card shows its placeholder.
      job = Fetch.download(url, name,
        { userAgent = "gen1recomp-mod-index", maxSeconds = 15 }),
    }
  end
  return nil
end

-- Turn finished thumbnail downloads into images.  Called from update(), so
-- love.graphics.newImage runs on the render thread where it belongs.
-- love.graphics.newImage decodes the PNG and uploads it, both on the render
-- thread.  A page's worth of thumbnails landing in the same frame did that
-- many times back to back and dropped the frame, so only this many are
-- decoded per pass; the rest keep their spinner one frame longer.
local THUMB_DECODES_PER_FRAME = 2

function RomImporter:_pumpFindThumbs()
  local pending = self._findThumbFetch
  if not pending then return end
  local Fetch = require("src.net.Fetch")
  local decoded = 0
  for id, item in pairs(pending) do
    if decoded >= THUMB_DECODES_PER_FRAME then break end
    local st = Fetch.poll(item.job)
    if st.status ~= "pending" then
      Fetch.release(item.job)
      pending[id] = nil
      local image
      if st.status == "ok" and st.path then
        local ok, img = pcall(love.graphics.newImage, st.path)
        image = ok and img or nil
        decoded = decoded + 1
      end
      self._findThumbs = self._findThumbs or {}
      self._findThumbs[id] = image or false
    end
  end
  if next(pending) == nil then self._findThumbFetch = nil end
end

-- Release stats for a FIND MODS row, resolved the same way the MODS tab
-- does it: the mod's own GitHub releases through ModUpdate's cached fetch,
-- so an installed mod's repo is instant and every result lands in
-- options.modUpdateCache for six hours.  A feed that publishes stats wins
-- outright (fresher, zero network); otherwise the repo is fetched, one
-- entry per frame so opening the tab cannot stall for the whole listing.
-- The result is memoized per id for the session; a repo with no releases
-- or a failed fetch resolves to an empty table so it is tried once.
-- PURE read: whatever is already known for a row, or nil.  Resolving a
-- feed-published stat or a repo-less entry is memoization, not network, so it
-- stays here; nothing in this function can start a fetch.  That matters
-- because the sort comparator calls it for EVERY entry -- when queueing lived
-- in here, sorting a 500-mod index by Popularity queued 500 GitHub requests
-- on the first frame, blew the hourly rate limit, and the failures then
-- re-queued together every 60s for as long as the tab was open.
function RomImporter:_findStatsCached(entry)
  self._findStatsCache = self._findStatsCache or {}
  local cached = self._findStatsCache[entry.id]
  if cached then
    if cached.done or (cached.retryAt and os.time() < cached.retryAt) then
      return cached
    end
    return nil   -- retry window open; _requestFindStats decides what to do
  end
  local ModIndex = require("src.mods.ModIndex")
  local dl = ModIndex.downloadStats(entry)
  local dates = ModIndex.releaseDates(entry)
  if dl or dates then
    cached = { total = dl and dl.total, recent = dl and dl.recent,
               windowDays = dl and dl.window_days, asOf = dl and dl.as_of,
               first = dates and dates.first, latest = dates and dates.latest,
               done = true }
    self._findStatsCache[entry.id] = cached
    return cached
  end
  if not entry.github or entry.github == "" then
    cached = { done = true }
    self._findStatsCache[entry.id] = cached
    return cached
  end
  return nil
end

-- Queue one row's release fetch.  Only rows actually on the page call this --
-- the rule _findThumb already follows -- so the fan-out is a page, not the
-- whole index.
function RomImporter:_requestFindStats(entry)
  if self:_findStatsCached(entry) then return end
  if not entry.github or entry.github == "" then return end
  local cached = self._findStatsCache[entry.id]
  if cached then
    if cached.retryAt and os.time() >= cached.retryAt then
      self._findStatsCache[entry.id] = nil   -- retry window open, refetch
    else
      return
    end
  end
  self._findStatsPending = self._findStatsPending or {}
  if self._findStatsPending[entry.id] then return end
  local ModUpdate = require("src.mods.ModUpdate")
  self._findStatsPending[entry.id] = {
    id = entry.id,
    h = ModUpdate.beginFetchReleases(entry.github, entry.id, {}),
  }
end

-- Read-only accessor for a row being drawn or shown in the detail modal.
-- Network work is scheduled by _queueFindEnrichment from update().
function RomImporter:_findStats(entry)
  return self:_findStatsCached(entry)
end

-- How many rows are still waiting on a release check, for the panel's
-- progress line.
function RomImporter:_findStatsPendingCount()
  local n = 0
  for _ in pairs(self._findStatsPending or {}) do n = n + 1 end
  return n
end

function RomImporter:_findStatsPendingFor(id)
  return (self._findStatsPending and self._findStatsPending[id]) ~= nil
end

function RomImporter:_findThumbPending(id)
  return (self._findThumbFetch and self._findThumbFetch[id]) ~= nil
end

-- Draw records the visible page in _findVisibleEntries.  Queue only a small
-- batch from that snapshot during update(), keeping network scheduling out of
-- the immediate-mode render path and preventing a large index from creating a
-- burst of thumbnail/GitHub work in one frame.
local FIND_ENRICH_PER_FRAME = 2

function RomImporter:_queueFindEnrichment()
  if self.tab ~= "find" or not self.findLoaded then return end
  local visible = self._findVisibleEntries
  if not visible then return end
  local thumbnails, stats = 0, 0
  for _, entry in ipairs(visible) do
    if thumbnails < FIND_ENRICH_PER_FRAME
        and self:_findThumb(entry) == nil
        and not self:_findThumbPending(entry.id) then
      self:_startFindThumb(entry)
      thumbnails = thumbnails + 1
    end
    if stats < FIND_ENRICH_PER_FRAME
        and self:_findStatsCached(entry) == nil
        and entry.github and entry.github ~= ""
        and not self:_findStatsPendingFor(entry.id) then
      self:_requestFindStats(entry)
      stats = stats + 1
    end
    if thumbnails >= FIND_ENRICH_PER_FRAME
        and stats >= FIND_ENRICH_PER_FRAME then
      break
    end
  end
end

-- Drive in-flight FIND MODS stats lookups.  Called from update().
function RomImporter:_pumpFindStats()
  local pending = self._findStatsPending
  if not pending then return end
  local ModUpdate = require("src.mods.ModUpdate")
  for id, item in pairs(pending) do
    local ok, done, releases, err = pcall(ModUpdate.pumpFetchReleases, item.h)
    if not ok or done then
      pending[id] = nil
      local stats = (ok and releases) and ModUpdate.statsForReleases(releases) or nil
      local cached
      if stats then
        cached = { total = stats.total, first = stats.first,
                   latest = stats.latest, done = true }
      else
        -- A repo that does not exist is permanent; every other failure (the
        -- hourly API rate limit, a hiccup) is retried in a minute so rows can
        -- recover without restarting the launcher.
        local permanent = tostring(ok and err or done)
          :find("Not Found", 1, true) ~= nil
        cached = { done = permanent, retryAt = os.time() + 60 }
      end
      self._findStatsCache = self._findStatsCache or {}
      self._findStatsCache[id] = cached
      -- The FIND list's sort cache is keyed on this revision; without the
      -- bump a Popularity/date sort stays frozen in the order of the first
      -- frame (no stats yet = name order) even after every fetch lands.
      self._findStatsRev = (self._findStatsRev or 0) + 1
    end
  end
  if next(pending) == nil then self._findStatsPending = nil end
end

-- Open the "add an index" text prompt.  Deliberately a typed URL rather than a
-- picked-from-a-list affair: there is no blessed index, and presenting one
-- would make the launcher's choice look like an endorsement.
function RomImporter:_promptAddIndex()
  self._indexPrompt = { text = "" }
  self:_armTextInput()
end

function RomImporter:_commitAddIndex()
  local prompt = self._indexPrompt
  self._indexPrompt = nil
  self:_disarmTextInput()
  if not prompt then return end
  local ModIndex = require("src.mods.ModIndex")
  local row, err = ModIndex.addSource(prompt.text or "")
  if not row then
    self.findNotice = { ok = false, text = tostring(err) }
    return
  end
  self.findNotice = { ok = true, text = Strings("Added %s", row.label or row.feed) }
  self.findLoaded = false
  self:_ensureFind()
end

function RomImporter:_removeIndex(feed)
  local ModIndex = require("src.mods.ModIndex")
  local ok, err = ModIndex.removeSource(feed)
  if not ok then
    self.findNotice = { ok = false, text = tostring(err) }
    return
  end
  self.findNotice = { ok = true, text = Strings("Index removed") }
  self.findLoaded = false
  self:_ensureFind()
end

-- Fetch and show an entry's description markdown.  Loaded on demand, never
-- with the listing: a feed of any size would otherwise be one request per mod.
function RomImporter:_findShowDetails(entry)
  local ModIndex = require("src.mods.ModIndex")
  local url = ModIndex.joinUrl(entry._base, entry.description_url)
  self:_cancelFindDetails()
  self._findDetails = {
    title = entry.title or entry.id,
    body = entry.summary or "",
    loading = url ~= nil,
    scroll = 0,
  }
  if url then
    self._findDetailsFetch = ModIndex.beginFetchText(url)
  end
end

function RomImporter:_cancelFindDetails()
  local h = self._findDetailsFetch
  if not h then return end
  self._findDetailsFetch = nil
  pcall(require("src.mods.ModIndex").cancelFetchText, h)
end

function RomImporter:_pumpFindDetails()
  local h = self._findDetailsFetch
  if not h then return end
  if not self._findDetails then
    self:_cancelFindDetails()
    return
  end
  local ok, done, text = pcall(require("src.mods.ModIndex").pumpFetchText, h)
  if ok and not done then return end
  self._findDetailsFetch = nil
  local d = self._findDetails
  if not d then return end
  d.loading = false
  if ok and type(text) == "string" and text ~= "" then d.body = text end
end

-- Arm the install confirm.  The compatibility list is the whole point of the
-- dialog: the panel deliberately does not hide an incompatible mod (an index
-- entry can be months stale, and a hidden mod looks like a missing one), so
-- this is where the player is told what the author declared before anything
-- is downloaded.
function RomImporter:_findConfirmInstall(entry)
  local ModIndex = require("src.mods.ModIndex")
  local Version = require("src.core.Version")
  local url, why = ModIndex.installUrl(entry)
  if not url then
    self.findNotice = { ok = false,
      text = (entry.title or entry.id) .. ": " .. tostring(why) }
    return
  end
  if ModIndex.isCart(entry) then
    return self:_findConfirmCartInstall(entry)
  end
  local installed = self:_findInstalledMap()
  local issues = ModIndex.compatIssues(entry, {
    modApi = Version.modApi,
    engineVersion = Version.engine,
    installed = installed,
  })
  local version = ModIndex.displayVersion(entry)
  local lines = { (entry.title or entry.id) .. " v" .. tostring(version) }
  if entry.author then lines[#lines + 1] = "by " .. entry.author end
  local have = installed[entry.id]
  if have then
    lines[#lines + 1] = "Replaces installed v" .. tostring(have)
  end
  for _, issue in ipairs(issues) do
    lines[#lines + 1] = "! " .. issue.text
  end
  lines[#lines + 1] = "Mods are not reviewed - trust the author."
  self._modConfirm = {
    kind = (#issues > 0) and "warn" or "update",
    indexEntry = entry,
    title = have and "Reinstall mod" or "Install mod",
    yesLabel = have and "Reinstall" or "Install",
    lines = lines,
  }
end

-- The cart twin of the confirm above.  The pinned list is what the player is
-- agreeing to; installing the cart installs none of it.
function RomImporter:_findConfirmCartInstall(entry)
  local ModIndex = require("src.mods.ModIndex")
  local Version = require("src.core.Version")
  local issues = ModIndex.compatIssues(entry, {
    modApi = Version.modApi,
    engineVersion = Version.engine,
    installed = self:_findInstalledMap(),
  })
  local version = ModIndex.displayVersion(entry)
  local info = GameVersion.info(entry.base)
  local lines = { (entry.title or entry.id) .. " v" .. tostring(version) }
  if entry.author then lines[#lines + 1] = "by " .. entry.author end
  lines[#lines + 1] = "Plays as "
    .. tostring((info and (info.launcherName or info.displayName)) or entry.base)
    .. " - " .. tostring(entry.seal)
  lines[#lines + 1] = ("Pins %d mod(s), installed separately from its page")
    :format(#(entry.mods or {}))
  local have = self:_findInstalledCarts()[entry.id]
  if have then
    lines[#lines + 1] = "Replaces installed v" .. tostring(have)
  end
  for _, issue in ipairs(issues) do
    lines[#lines + 1] = "! " .. issue.text
  end
  lines[#lines + 1] = "Carts are not reviewed - trust the author."
  self._modConfirm = {
    kind = (#issues > 0) and "warn" or "update",
    indexEntry = entry,
    title = have and "Reinstall cart" or "Install cart",
    yesLabel = have and "Reinstall" or "Install",
    lines = lines,
  }
end

function RomImporter:_findInstall(entry)
  local ModIndex = require("src.mods.ModIndex")
  if ModIndex.isCart(entry) then return self:_beginCartInstall(entry) end
  self:_beginModInstall({
    modId = entry.id, name = entry.title or entry.id, entry = entry,
    verb = "Installed", notice = "find",
  })
end

return RomImporter
