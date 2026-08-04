local GameVersion = require("src.core.GameVersion")
local GamepadMap = require("src.core.GamepadMap")
local Strings = require("src.core.Strings")
local HostShell = require("src.core.HostShell")
local Platform = require("src.core.Platform")
local SafeArea = require("src.core.SafeArea")

local RomImporter = {}
RomImporter.__index = RomImporter

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

-- Cache generation tag; bump to force every imported version to re-extract.
-- v9: Yellow audio re-anchored on pokeyellow.sym (#522) -- stale caches
-- carry Red's bank $1f header, wave-table, and CryData offsets.
local CACHE_FORMAT = "rom-cache-v9:"
-- The completion marker is written under each version's cache prefix
-- (rom-cache.complete for Red, blue/rom-cache.complete for Blue).
local MARKER_PATH = "rom-cache.complete"

-- The marker a finished import writes for a version: the generation tag plus
-- that version's ROM hash, so both a format bump and a swapped ROM invalidate.
local function markerFor(version)
  return CACHE_FORMAT .. GameVersion.info(version).sha1
end
local COMMUNITY_URL = "https://bois.icu"
local TRUST_WARNING = "if you did not get this from bryanthaboi's github " ..
  "or a link from the discord that bryanthaboi himself posted, just know " ..
  "it might have been tampered with. go to the discord to verify " ..
  COMMUNITY_URL .. " (or click the logo above)"
local REQUIRED_FILES = {
  "data/generated/constants.lua",
  "data/generated/maps.lua",
  "data/generated/text.lua",
  "data/generated/field.lua",
  "data/generated/battle_anims.lua",
  "assets/generated/title/pokemon_logo.png",
  "assets/generated/fonts/font.png",
  "assets/generated/battle/front/pikachu.png",
  "assets/generated/battle/anims/move_anim_0.png",
  "assets/generated/battle/anims/move_anim_1.png",
  "assets/generated/audio/programs.bin",
}

-- Files only one version's cache carries.  A version that predates one of
-- them re-imports on its own, without dragging the other versions through a
-- CACHE_FORMAT bump.
local VERSION_REQUIRED_FILES = {
  yellow = {
    "assets/generated/battle/trainers/jessie_james.png", -- #439
    -- Oak's own back pic and the pikapic base frames only exist in caches
    -- built after their manifest symbols landed, so an older Yellow cache
    -- has to re-import to stop falling back to the old man's back pic and
    -- to the battle front pic (#557, #561).  Both are gated on manifest
    -- symbols in RomExtractor, so these markers must only ever list files
    -- tools/rom_manifest_yellow.json can actually produce -- otherwise the
    -- cache reads as incomplete and re-importing cannot clear it.
    "assets/generated/battle/profoakb.png",
    "assets/generated/pikachu/pikapic_1.png",
  },
}

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

-- CacheFs.exists checks the game folder directly for a portable install,
-- otherwise the save directory through love.filesystem.  It honors
-- CacheFs.prefix, so we point it at the version's cache subtree (Red at the
-- root, Blue under blue/).
local function allRequiredFilesExist(version)
  local CacheFs = require("src.import.CacheFs")
  local saved = CacheFs.prefix
  CacheFs.prefix = GameVersion.cachePrefix(version)
  local ok = true
  for _, path in ipairs(REQUIRED_FILES) do
    if not CacheFs.exists(path) then ok = false; break end
  end
  for _, path in ipairs(ok and VERSION_REQUIRED_FILES[version] or {}) do
    if not CacheFs.exists(path) then ok = false; break end
  end
  CacheFs.prefix = saved
  return ok
end

-- A developer checkout / Python build leaves Red's generated data in the
-- physfs SOURCE at the un-prefixed root; that is always current.  Only Red
-- ships this way (Blue is import-only), so this stays a Red-root check.
local function sourceTreeHasData()
  if not allRequiredFilesExist("red") or not love.filesystem.getRealDirectory then
    return false
  end
  local real = love.filesystem.getRealDirectory(REQUIRED_FILES[1])
  return real == love.filesystem.getSource()
end

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
  -- Purge each version's stale save-directory copy (Red at the root, Blue
  -- under blue/) so it cannot shadow the portable game-folder cache.
  for _, version in ipairs(GameVersion.ORDER) do
    local prefix = GameVersion.cachePrefix(version)
    if saveDirHas(prefix .. MARKER_PATH) or saveDirHas(prefix .. REQUIRED_FILES[1]) then
      removeTree(prefix .. "data/generated")
      removeTree(prefix .. "assets/generated")
      love.filesystem.remove(prefix .. MARKER_PATH)
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
  -- Red generated data in the physfs source (developer checkout / Python
  -- build) is always current; Blue is import-only and falls through to the
  -- version-marker gate.
  if version == "red" and sourceTreeHasData() then return true end
  local saved = CacheFs.prefix
  CacheFs.prefix = GameVersion.cachePrefix(version)
  local marker = CacheFs.read(MARKER_PATH)
  CacheFs.prefix = saved
  return marker == markerFor(version) and allRequiredFilesExist(version)
end

-- Load the import manifest for a version and confirm it matches that ROM.
local function decodeManifest(version)
  local path = GameVersion.info(version).manifest
  local raw, readError = love.filesystem.read(path)
  if not raw then error("ROM import metadata is missing: " .. tostring(readError)) end
  local Json = require("src.link.Json")
  local manifest, decodeError = Json.decode(raw)
  if not manifest then error("ROM import metadata is invalid: " .. tostring(decodeError)) end
  assert(manifest.romSha1 == GameVersion.info(version).sha1,
    "ROM import metadata version mismatch")
  return manifest
end

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
-- then hangs the mouse on the next.  So pump until no button is held, letting
-- SDL see the release and let go first; bounded, so a stuck button costs a
-- moment and never the launcher.  pump() only drains OS events into LOVE's
-- queue -- it dispatches nothing -- so there is no reentry into mousepressed
-- and the release is still delivered normally on the next frame.
local function releasePointerGrab()
  if not (love.mouse and love.mouse.isDown and love.event and love.event.pump
      and love.timer) then
    return
  end
  local deadline = love.timer.getTime() + 1
  while love.mouse.isDown(1, 2, 3) do
    love.event.pump()
    if love.timer.getTime() > deadline then break end
    love.timer.sleep(0.005)
  end
end

local function commandOutput(command)
  if not Platform.canSpawnProcess() then return nil end
  releasePointerGrab()
  local pipe = HostShell.popen(command)
  if not pipe then return nil end
  local result = pipe:read("*a")
  pipe:close()
  result = trim(result)
  return result ~= "" and result or nil
end

local IMPORTS_DIR = "imports"
local MODS_INBOX_DIR = "imports/mods"
local SAVES_INBOX_DIR = "imports/saves"
local ROM_BYTES = 1024 * 1024

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

-- NX mod zip inbox (separate from ROM imports/). Parent imports/ first —
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
-- Parent imports/ then imports/saves/ first — createDirectory is not nested.
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
    -- but is not a ROM — rescan would try it first and block the real dump).
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

local function listZipPaths(dir)
  local paths = {}
  for _, name in ipairs(love.filesystem.getDirectoryItems(dir) or {}) do
    -- Skip AppleDouble / hidden junk from Mac MTP (._foo.zip ends in .zip
    -- but is not a PhysFS archive — mount fails with "could not be opened").
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
    -- but is not a real battery save — import would fail and invent noise).
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
      text = Strings("Already imported — %d file(s) skipped. Check SAVE SLOT.",
        skipCount),
    }
  end
end

-- NX "Scan again" on a game tab: import only the dump whose SHA-1 matches
-- that tab. A shared imports/ inbox often holds Red+Blue+Yellow at once;
-- picking the first pending file would jump Yellow → Red (and switch the
-- launcher tab via startData). Other known dumps stay for their own tabs.
-- Junk (wrong size / unknown hash) still surfaces when nothing matches the
-- tab and no other known dump is present — same feedback as before for a
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
    if #data ~= ROM_BYTES then
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
          .. "for their own tabs — open that game and Scan again.", label),
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
-- add Blue (issue #167).  Yellow carts are typically .gbc.
local function findPendingRom(ready)
  for _, name in ipairs(love.filesystem.getDirectoryItems("")) do
    if name:lower():match("%.gbc?$") and love.filesystem.getInfo(name, "file") then
      local data = love.filesystem.read(name)
      if type(data) == "string" and #data == 1024 * 1024 then
        local version = GameVersion.forSha1(sha1(data))
        if version and not ready[version] then
          return name, data
        end
      end
    end
  end
  return nil
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
  if type(data) == "string" and #data == 1024 * 1024 then
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

-- The self-updater only surfaces on the real distributed build: a fused,
-- interactive launcher with no scripted-run override.  A dev / source checkout
-- (unfused, where Boot.run already no-ops) or an autopilot / driver /
-- import-only run all skip the release check so headless and CI runs never spin
-- up the background worker or reach out to the network.
local function updaterAllowed()
  if not Platform.networkValidated() then return false end
  if not (love.filesystem.isFused and love.filesystem.isFused()) then return false end
  if os.getenv("POKEPORT_AUTOPILOT") or os.getenv("POKEPORT_DRIVER") then return false end
  if os.getenv("POKEPORT_IMPORT_ONLY") == "1" then return false end
  return true
end

-- The launcher runs each GameVersion as an independent tab.  Each dropped or
-- chosen ROM is routed to its version by SHA-1, extracted into that version's
-- own cache (Red at the root, Blue under blue/, Yellow under yellow/), so all
-- can be imported and played side by side.  onComplete(version) hands the
-- chosen game off to boot.
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
    isNX = isNX,
    romImportMode = romImportMode,
    mobileFileBridge = mobileFileBridge,
    android = android,
    ios = mobileOS == "iOS",
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
    tab = "red",          -- active launcher tab: "red"/"blue"/"yellow"/"mods"
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
    -- SAVE FILES card state: the last import/export result per version, shown as
    -- a green/red notice line under the Import save / Export save buttons.  A
    -- successful export carries { dir } so the notice can offer an open-folder
    -- affordance (desktop love.system.openURL).
    saveNotice = {},
    -- MODS panel state (pass 3): mods is the cached LauncherMods.list() array
    -- (refreshed lazily on first draw and after any toggle/install/delete);
    -- modScroll is the list scroll offset (px, clamped in draw); modNotice is
    -- the last install/delete result { ok, text } shown as a line above the list.
    mods = nil, modScroll = 0, modNotice = nil,
    -- FIND MODS panel state (src/mods/ModIndex.lua).  findLoaded gates the
    -- first fetch the way `mods = nil` gates the mods list, but it is a flag
    -- rather than a nil listing because "no index added" is a legitimate
    -- loaded state and must not re-fetch every frame.  findSources is the
    -- player's index list from options; findIndex is the merged listing;
    -- _findThumbs caches one image per mod id (false = fetched and failed).
    findLoaded = false, findSources = nil, findIndex = nil,
    findScroll = 0, findNotice = nil, findQuery = "", findCategory = nil,
    _findSearchFocus = false, _findThumbs = nil,
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
    iosPendingKind = nil,
    iosPendingVersion = nil,
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

  for _, version in ipairs(GameVersion.ORDER) do
    local info = GameVersion.info(version)
    local ready = RomImporter.isReady(version) and not self.forceImport
    self.ready[version] = ready
    -- a marker present but for an older cache generation / different ROM means
    -- "update required" (re-import) rather than a clean first-run choose
    local saved = CacheFs.prefix
    CacheFs.prefix = info.cachePrefix
    local marker = CacheFs.read(MARKER_PATH)
    CacheFs.prefix = saved
    self.returning[version] =
      (not ready) and marker ~= nil and marker ~= markerFor(version)
    self.romName[version] = "pokemon_" .. info.id
      .. (info.id == "yellow" and ".gbc" or ".gb")
  end

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
  -- async release check as it comes up; draw() polls Check.state() to render an
  -- unobtrusive banner beneath the columns.  Held behind pcall so a broken or
  -- absent updater can never take the launcher down with it.
  if self.launcher and updaterAllowed() then
    local ok, Check = pcall(require, "src.update.Check")
    if ok and Check then
      self.Check = Check
      pcall(Check.start)
    end
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
  if not (f and self.android and self.workState ~= "working") then return end
  -- SAF create-document finished: GameActivity wrote export_done.flag.
  if love.filesystem.getInfo("export_done.flag", "file") then
    love.filesystem.remove("export_done.flag")
    love.filesystem.remove("pending_export.sav")
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
    local text = "Could not read the picked file. Reopen the picker and choose "
      .. "it with the Files (Documents) app, or copy it into: "
      .. love.filesystem.getSaveDirectory()
    if pickError:find("picked_mod", 1, true) then
      self.modNotice = { ok = false, text = text }
    elseif pickError:find("picked_save", 1, true) then
      local version = self.androidPendingVersion or self:_savedropTarget()
      self.androidPendingVersion = nil
      self.saveNotice[version] = { ok = false, text = text }
    else
      self:setError(text)
    end
    return
  end
  local modName = findPendingMod(false, self.pickSkip)
  if modName then
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
  self.romData = nil
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
  if #data ~= 1024 * 1024 then
    self:setError(("Expected a 1 MiB Game Boy ROM; this file is %.2f MiB.")
      :format(#data / 1024 / 1024))
    return
  end
  local actualHash = sha1(data)
  local version = GameVersion.forSha1(actualHash)
  if not version then
    self:setError(("Unsupported ROM (SHA-1 %s). This needs a clean US Pokemon "
      .. "Red, Blue, or Yellow dump; patched, trimmed or \"fixed\" dumps "
      .. "(tagged [b] or [BF]) never verify."):format(actualHash))
    return
  end
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
  self.worker = coroutine.create(function()
    self.status = "Preparing private game data"
    coroutine.yield()
    -- Redirect every cache write to this version's subtree, then clear only
    -- that version's previous cache from both homes (save directory and, for
    -- a portable install, the game folder).  The other version is untouched.
    local CacheFs = require("src.import.CacheFs")
    local prefix = info.cachePrefix
    CacheFs.prefix = prefix
    removeTree(prefix .. "data/generated")
    removeTree(prefix .. "assets/generated")
    love.filesystem.remove(prefix .. MARKER_PATH)
    CacheFs.removeTree("data/generated")
    CacheFs.removeTree("assets/generated")
    CacheFs.remove(MARKER_PATH)

    local manifest = decodeManifest(version)
    local RomExtractor = require("src.import.RomExtractor")
    local extractor = RomExtractor.new(self.romData, manifest,
      function(progress, total, stage, current, stageTotal)
        self.status = stage
        self.progress = progress / total
        self.stageCurrent = current
        self.stageTotal = stageTotal
        coroutine.yield()
      end)
    extractor:run()
    self.romData = nil
    collectgarbage("collect")
    -- Written last: the marker is what isReady() checks, so it must only
    -- appear once every required file is in place.
    local ok, writeError = CacheFs.write(MARKER_PATH, markerFor(version))
    CacheFs.prefix = ""   -- restore the default so later writes stay at the root
    if not ok then error("could not finish the private cache: " .. tostring(writeError)) end
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
  end)
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
  -- (which mounts + validates it).  Everything else is treated as a ROM.  The
  -- dropped file itself is passed through -- installZip opens it the same way
  -- readDroppedFile does here.
  local name = file:getFilename() or ""
  if name:lower():match("%.zip$") then
    self:_installMod(file)
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
  local ok, installed, res = pcall(function()
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
-- NX: no HostShell/desktop picker — rescan imports/mods/ inbox instead.
function RomImporter:chooseMod()
  if self.workState == "working" then return end
  if self.isNX then
    self:ensureModsInboxDir()
    self:rescanModsAction()
    return
  end
  if self.ios and love.system.getPickedFile then
    self.iosPendingKind = "mod"
    if not pickFile("mod") then
      self.iosPendingKind = nil
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
  local path = chooseZip()
  if path then self:_installMod(path) end
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
function RomImporter:_importSave(version, source)
  if self.workState == "working" then return end
  if GameVersion.VERSIONS[self.tab] or self.tab == "mods" then
    self.tab = version
  end
  if not self.ready[version] then
    self.saveNotice[version] = { ok = false, text = "Import the "
      .. GameVersion.info(version).displayName .. " ROM before importing a save." }
    return
  end
  local ok, res = require("src.import.SaveFileIO").importToSlot(source, version)
  if ok then
    self:_refreshSlots(version)
    self.activeSlot[version] = res
    self.slotScroll[version] = math.huge   -- pin the new row on screen (clamped in draw)
    self.saveNotice[version] = { ok = true, text = "Imported save into " .. tostring(res) .. "." }
  else
    self.saveNotice[version] = { ok = false, text = tostring(res) }
  end
end

-- "Import save" button: open a native .sav picker and import the pick.
-- Android mirrors ROM / mod import via love.system.pickFile("sav").
-- NX: no HostShell/desktop picker — rescan imports/saves/ inbox instead.
function RomImporter:chooseSaveImport(version)
  if self.workState == "working" then return end
  version = self:_resolveSaveVersion(version)
  if self.isNX then
    self:ensureSavesInboxDir(version)
    self:rescanSavesAction(version)
    return
  end
  if self.ios and love.system.getPickedFile then
    self.iosPendingKind = "sav"
    self.iosPendingVersion = version
    if not pickFile("sav") then
      self.iosPendingKind = nil
      self.iosPendingVersion = nil
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
  local path = chooseSav()
  if path then self:_importSave(version, path) end
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
function RomImporter:_deleteSlot(version, id)
  if self.workState == "working" then return end
  local SaveData = require("src.core.SaveData")
  local ok, err = SaveData.deleteSlot(version, id)
  if ok then
    self:_refreshSlots(version)
    self.saveNotice[version] = { ok = true, text = "Deleted " .. tostring(id) .. "." }
  else
    self.saveNotice[version] = { ok = false, text = tostring(err) }
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
  if self.ios and love.system.getPickedFile then
    self.iosPendingKind = "rom"
    if not pickFile("rom") then
      self.iosPendingKind = nil
      self:setError("Could not open the file picker.")
    end
    return
  end
  if self.android then
    -- Prefer a not-yet-imported .gb/.gbc already in the save dir (USB copy, or
    -- a fresh SAF pick).  Never reuse an already-imported cart's file -- that
    -- was the #167 failure mode (second Choose just re-extracted Red).
    local name, data = findPendingRom(self.ready)
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
  local path = chooseRom(GameVersion.info(self.chooseVersion).displayName)
  if path then
    self:startPath(path)
    return
  end
  -- Handheld Linux (Anbernic stock OS / PortMaster) rarely has zenity or
  -- kdialog.  Fall back to the same "drop a .gb/.gbc next to the game" scan
  -- used on Android, which works when the game is launched as an unpacked
  -- directory (see build-rg34xxsp.sh).
  local name, data = findPendingRom(self.ready)
  if name then
    self:startData(data, name)
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
  if not found then
    for _, name in ipairs(love.filesystem.getDirectoryItems("")) do
      local n = name:lower()
      if n:match("%.gbc?$") or n == "picked_mod.zip" or n == "picked_save.sav" then
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
  self:_updatePadCursor(dt)
  -- Pump the FlexLove view (input polling + the queued click actions).  The
  -- flag is only set once draw() has built a tree, so headless runs and the
  -- test tier never touch the toolkit.
  if self._flex then
    require("src.import.LauncherView").update(self, dt)
  end
  -- Dev harness: POKEPORT_LAUNCHER_SHOT=/path.png resizes the window from
  -- POKEPORT_WIN=WxH, lets the view settle, then captures one frame and
  -- quits, so a scripted run can see the real launcher at any window shape
  -- (the frame drivers all bypass the interactive launcher).
  local shot = os.getenv("POKEPORT_LAUNCHER_SHOT")
  if shot and not self._shotDone then
    if not self._shotSized then
      self._shotSized = true
      local w, h = (os.getenv("POKEPORT_WIN") or ""):match("^(%d+)x(%d+)$")
      if w and love.window and love.window.setMode then
        pcall(love.window.setMode, tonumber(w), tonumber(h),
          { resizable = true })
      end
      local tab = os.getenv("POKEPORT_LAUNCHER_TAB")
      if tab and tab ~= "" then self:_switchTab(tab) end
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
    if self._shotTimer > 1.2 then
      self._shotDone = true
      love.graphics.captureScreenshot(function(imagedata)
        local fd = imagedata:encode("png")
        local f = io.open(shot, "wb")
        if f then f:write(fd:getString()) f:close() end
        love.event.quit()
      end)
    end
  end
  if self.ios and love.system.getPickedFile and self.workState ~= "working" then
    local path = love.system.getPickedFile()
    if path then
      local kind = self.iosPendingKind or "rom"
      local version = self.iosPendingVersion
      self.iosPendingKind = nil
      self.iosPendingVersion = nil
      if kind == "mod" then
        self:_installMod(path)
      elseif kind == "sav" then
        self:_importSave(version or self:_savedropTarget(), path)
      else
        self:startPath(path)
      end
    elseif love.system.getPickError then
      local errorText = love.system.getPickError()
      if errorText then
        local kind = self.iosPendingKind or "rom"
        local version = self.iosPendingVersion or self:_savedropTarget()
        self.iosPendingKind = nil
        self.iosPendingVersion = nil
        if kind == "mod" then
          self.modNotice = { ok = false, text = errorText }
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
  if not self.isNX or self._nxPointerBridge then return end
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
  if not self.isNX then return end
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
  -- Avoid requiring LauncherView from headless unit tests (no luautf8).  In
  -- a real session draw() has already loaded it, so detach runs normally.
  if self._flex and package.loaded["src.import.LauncherView"] then
    require("src.import.LauncherView").detach(self)
  else
    self._flex = nil
    self:parkNxPointerForHost()
  end
end

-- After an overlay closes: re-arm the pad cursor when a stick is already
-- connected so NX / handhelds are not stranded without a pointer until the
-- next stick bump (same class of bug as opening Touch Controls).
function RomImporter:resumeAfterOverlay()
  if not self.launcher then return end
  if not (love.joystick and love.joystick.getJoystickCount) then return end
  if love.joystick.getJoystickCount() <= 0 then return end
  local osName = (love.system and love.system.getOS and love.system.getOS()) or ""
  if osName == "Linux" or self.isNX then
    self:_activatePadCursor()
  end
end

function RomImporter:_cycleTab(delta)
  local order = { "red", "blue", "yellow", "mods", "find" }
  local idx = 1
  for i, id in ipairs(order) do
    if id == self.tab then idx = i; break end
  end
  self:_switchTab(order[((idx - 1 + delta) % #order) + 1])
end

function RomImporter:_updatePadCursor(dt)
  if self.isNX then
    self:_ensureNxPointerBridge()
    -- Cap dt so a hitch in the FlexLove immediate-mode frame does not fling
    -- the cursor; desktop keeps raw dt (setPosition path already smooth there).
    if dt > 1 / 30 then dt = 1 / 30 end
  end

  -- Real mouse motion yields the pad cursor so desktop users keep a normal
  -- pointer after bumping a stick once. On NX this must stay off: love-nx /
  -- SDL often drifts the system mouse with the stick (or touch), and axis
  -- events are not every frame, so yield+reactivate flickers the overlay.
  if not self.isNX then
    local mx, my = love.mouse.getPosition()
    if self._lastMouseX and self._padCursorActive then
      if math.abs(mx - self._lastMouseX) > 3 or math.abs(my - self._lastMouseY) > 3 then
        self._padCursorActive = false
      end
    end
    self._lastMouseX, self._lastMouseY = mx, my
  end

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
    -- Desktop: FlexLove polls the real mouse, so warp it with the pad pointer.
    -- NX: the getPosition bridge already returns pad coords — skip setPosition.
    if not self.isNX and love.mouse.setPosition then
      pcall(love.mouse.setPosition, self._padCursor.x, self._padCursor.y)
      self._lastMouseX, self._lastMouseY = self._padCursor.x, self._padCursor.y
    end
  end

  -- Right stick scrolls whatever the pad pointer sits over, through the
  -- view's wheel path, so the page and the modal scrollers all behave like a
  -- mouse wheel would.
  local ry = self._padAxis.righty or 0
  if math.abs(ry) > PAD_DEAD and self._flex then
    self:_activatePadCursor()
    require("src.import.LauncherView").wheelmoved(self, 0, -ry * 8 * dt)
  end
end

function RomImporter:gamepadpressed(_, button)
  self:_activatePadCursor()
  -- Map through GamepadMap so NX swaps SDL face labels to Nintendo A/B.
  local action = GamepadMap.mapGamepadButton(button)
  if action == "a" then
    -- Instant click at the virtual pointer: dispatched straight into the
    -- view, since the launcher no longer hit-tests presses itself.
    if self._flex then
      require("src.import.LauncherView").clickAt(self,
        self._padCursor.x, self._padCursor.y)
    end
  elseif button == "leftshoulder" then
    self:_cycleTab(-1)
  elseif button == "rightshoulder" then
    self:_cycleTab(1)
  elseif button == "dpup" or button == "dpdown"
      or button == "dpleft" or button == "dpright" then
    self._padDir[button] = true
  elseif button == "start" or button == "back" then
    -- Start / Select: Play if ready, else Choose ROM on the active game tab.
    if self.workState == "working" then return end
    local version = self.tab
    if GameVersion.VERSIONS[version] then
      if self.ready[version] then self:play(version) else self:_romAction(version) end
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
    if math.abs(value) > PAD_DEAD then self:_activatePadCursor() end
  end
end

-- Same gate as src/core/Input.lua: a pad SDL can map already reached
-- gamepadpressed this frame, so re-entering it from the raw event would
-- fire the virtual cursor's click twice off one A press (#620).
function RomImporter:joystickpressed(joystick, button)
  if GamepadMap.ignoreRawForJoystick(joystick) then return end
  local padButton = GamepadMap.mapRawToGamepadButton(button)
  if padButton then self:gamepadpressed(joystick, padButton) end
end

function RomImporter:joystickreleased(joystick, button)
  if GamepadMap.ignoreRawForJoystick(joystick) then return end
  local padButton = GamepadMap.mapRawToGamepadButton(button)
  if padButton then self:gamepadreleased(joystick, padButton) end
end

function RomImporter:joystickaxis(joystick, axis, value)
  if GamepadMap.ignoreRawForJoystick(joystick) then return end
  if axis == 1 then
    self:gamepadaxis(joystick, "leftx", value)
  elseif axis == 2 then
    self:gamepadaxis(joystick, "lefty", value)
  end
end

function RomImporter:joystickhat(joystick, hat, direction)
  if GamepadMap.ignoreRawForJoystick(joystick) then return end
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
  if #dirs > 0 then self:_activatePadCursor() end
end

-- Player pressed Play on a game whose ROM is imported: hand off to boot.
function RomImporter:play(version)
  if self.workState == "working" then return end
  if not self.ready[version] then return end
  self._handedOff = true
  resetPointerCursor(self)
  -- The game draws with raw love.graphics from here on; drop the view's
  -- element tree and canvases before the handoff.
  if self._flex then require("src.import.LauncherView").detach(self) end
  if self.onComplete then self.onComplete(version) end
end

-- "re-import" a column: drop it back to the choose/drop state so a fresh ROM
-- can be selected (the extract replaces that version's cache).
function RomImporter:reimport(version)
  if self.workState == "working" then return end
  if not self.ready[version] then return end
  self.ready[version] = false
  self.returning[version] = false
  self.chooseVersion = version
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
function RomImporter:draw()
  require("src.import.LauncherView").draw(self)
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

-- Clicks are polled inside FlexLove (mouse + love.touch); host-forwarded
-- mousepressed stays inert so Android's synthesized mouse path cannot
-- double-fire a tap (#553).  Touch move/press/release must still reach
-- FlexLove.touch* or scroll containers never drag on phones.
function RomImporter:mousepressed() end

function RomImporter:touchpressed(id, x, y, dx, dy, pressure)
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
  self.tab = id
  self._findSearchFocus = false
  self:_disarmTextInput()
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

function RomImporter:_openSettings()
  local ok, model = pcall(function()
    return require("src.import.LauncherSettings").open()
  end)
  if ok and model then self._settings = model end
end

function RomImporter:_closeSettings()
  if self._settings then self._settings.save() end
  self._settings = nil
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
function RomImporter:fileUrl(path)
  return fileUrl(path)
end

function RomImporter:keypressed(key)
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
      or self._findDetails then
    if key == "escape" then
      if self._findDetails then
        self._findDetails = nil
      elseif self._modReleaseNotes then
        self._modReleaseNotes = nil
      else
        self._modConfirm = nil
        self._modVersions = nil
      end
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
  if self.workState == "working" then return end
  if key == "return" or key == "space" or key == "kpenter" then
    -- Enter acts on the visible game tab: Play if its ROM is ready, otherwise
    -- open its picker.  The mods tab has no keyboard action.
    local version = self.tab
    if GameVersion.VERSIONS[version] then
      if self.ready[version] then self:play(version) else self:_romAction(version) end
    end
  end
end
-- Reload a version's slot list + active id from SaveData (the source of truth).
-- Cheap enough to call on any mutation; the per-frame draw only calls it lazily
-- through _ensureSlots so a still list costs nothing after the first paint.
function RomImporter:_refreshSlots(version)
  local SaveData = require("src.core.SaveData")
  self.slots[version] = SaveData.listSlots(version) or {}
  local opts = SaveData.loadOptions()
  local reg = opts.saveSlots and opts.saveSlots[version]
  -- fall back to the first slot as the shown "loaded" one when the registry
  -- has a list but no explicit active id (matches saveNames' own resolution)
  self.activeSlot[version] = reg and (reg.active or reg.list[1]) or nil
end

function RomImporter:_ensureSlots(version)
  if not self.slots[version] then self:_refreshSlots(version) end
end

-- The host calls this when the save editor closes: the edited slot's player
-- name, badge count and dex total all feed the cached row summary, so it has
-- to be re-read rather than trusted across the round trip.
function RomImporter:savesChanged(version)
  self:_refreshSlots(version)
end

-- Point the active slot at id (persisted immediately, per the contract) and
-- reflect it in the LOADED pill without a full relist.
function RomImporter:_selectSlot(version, id)
  require("src.core.SaveData").setActiveSlot(version, id)
  self.activeSlot[version] = id
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

function RomImporter:_beginRename(version, id)
  local label
  for _, slot in ipairs(self.slots[version] or {}) do
    if slot.id == id then label = slot.label break end
  end
  self._rename = { version = version, id = id, text = label or "" }
  self._slotPress = nil -- cancel any armed click/drag on the list
  self:_armTextInput()
end

function RomImporter:_commitRename()
  local r = self._rename
  if not r then return end
  self._rename = nil
  self:_disarmTextInput()
  require("src.core.SaveData").renameSlot(r.version, r.id, r.text)
  self:_refreshSlots(r.version)
end

function RomImporter:textinput(text)
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
function RomImporter:_newSlot(version)
  local SaveData = require("src.core.SaveData")
  local id = SaveData.createSlot(version)
  SaveData.setActiveSlot(version, id)
  self:_refreshSlots(version)
  self.activeSlot[version] = id
  self.slotScroll[version] = math.huge
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
  self.mods = LauncherMods.list() or {}
  self:_syncModUpdateInfo(false)
end

function RomImporter:_ensureMods()
  if not self.mods then self:_refreshMods() end
end

-- Resolve cached (or freshly fetched) GitHub status for every mod that
-- declares a github field. force=true bypasses the 6h cache on every repo.
-- Results live on self.modUpdateInfo[id] = { status, latest, best, releases }.
function RomImporter:_syncModUpdateInfo(force)
  local ModUpdate = require("src.mods.ModUpdate")
  self.modUpdateInfo = self.modUpdateInfo or {}
  for _, m in ipairs(self.mods or {}) do
    if m.github and m.github ~= "" then
      local ok, packed = pcall(function()
        local releases, err, meta = ModUpdate.fetchReleases(m.github, m.id, {
          force = force == true,
        })
        local cached = ModUpdate.readCache(m.github)
        return {
          releases = releases,
          err = err,
          meta = meta,
          checkedAt = (cached and cached.checkedAt) or os.time(),
        }
      end)
      if not ok then
        self.modUpdateInfo[m.id] = {
          status = "error", err = tostring(packed),
        }
      elseif packed.releases then
        local status, best = ModUpdate.statusFor(m.version, packed.releases)
        self.modUpdateInfo[m.id] = {
          status = status,
          latest = best and best.version or nil,
          best = best,
          releases = packed.releases,
          err = nil,
          checkedAt = packed.checkedAt or os.time(),
        }
      else
        self.modUpdateInfo[m.id] = {
          status = "error",
          latest = nil,
          best = nil,
          releases = nil,
          err = tostring(packed.err),
        }
      end
    else
      self.modUpdateInfo[m.id] = nil
    end
  end
end

function RomImporter:_modUpdateInfo(id)
  return self.modUpdateInfo and self.modUpdateInfo[id] or nil
end

-- Flip a mod's enabled flag (persisted via LauncherMods.setEnabled) and relist
-- so the toggle, count, and every status chip reflect the new resolution.
-- Enabling an experimental mod arms a confirm first.
function RomImporter:_toggleMod(id, confirmed)
  local LauncherMods = require("src.mods.LauncherMods")
  local cur, experimental = false, false
  for _, m in ipairs(self.mods or {}) do
    if m.id == id then
      cur = m.enabled
      experimental = m.experimental == true
      break
    end
  end
  local want = not cur
  if want and experimental and not confirmed then
    self._modConfirm = {
      kind = "experimental", id = id,
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
  LauncherMods.setEnabled(id, want)
  self:_refreshMods()
end

-- Enable all / Disable all (#647).  One options write for the whole list
-- (LauncherMods.setAllEnabled) and one relist afterwards, so the count, the
-- switches and every status chip resolve together instead of per mod.
-- Enabling routes through the same experimental confirm _toggleMod arms: that
-- opt-in is the only warning an experimental mod ever gets, and a bulk button
-- must not be the way around it.  Disabling needs no confirm -- it is the
-- recovery action, and Delete is the only destructive one on this panel.
function RomImporter:_setAllMods(want, confirmed)
  local LauncherMods = require("src.mods.LauncherMods")
  local ids, experimental = {}, false
  for _, m in ipairs(self.mods or {}) do
    if m.enabled ~= want then
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
  LauncherMods.setAllEnabled(ids, want)
  self:_refreshMods()
  self.modNotice = { ok = true, text = want
    and Strings("Enabled %d mods.", #ids)
    or Strings("Disabled %d mods.", #ids) }
end

-- GitHub Update / Check for updates / Versions. Soft-fails into modNotice.
-- Update button: when a newer release is known, confirm then install; when
-- already current, force-refresh the 6h cache and report / offer update.
function RomImporter:_modGithubAction(id, action)
  if not Platform.networkValidated() then
    self.modNotice = { ok = false,
      text = "Remote mod download is unavailable on this platform." }
    return
  end
  local ran, err = pcall(function()
    local ModUpdate = require("src.mods.ModUpdate")
    local row
    for _, m in ipairs(self.mods or {}) do
      if m.id == id then row = m; break end
    end
    if not row or not row.github then
      self.modNotice = { ok = false, text = "This mod has no github field" }
      return
    end

    if action == "versions" then
      self.modNotice = { ok = true, text = "Loading versions..." }
      local releases, fetchErr = ModUpdate.fetchReleases(row.github, row.id, {})
      if not releases then
        self.modNotice = { ok = false, text = tostring(fetchErr) }
        return
      end
      local status, best = ModUpdate.statusFor(row.version, releases)
      self.modUpdateInfo = self.modUpdateInfo or {}
      self.modUpdateInfo[row.id] = {
        status = status, latest = best and best.version, best = best,
        releases = releases,
      }
      self._modVersions = {
        id = row.id, name = row.name, current = row.version,
        releases = releases, scroll = 0,
      }
      self.modNotice = nil
      return
    end

    -- update / check
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

    -- Manual check (or first click when status is current/unknown/error)
    self.modNotice = { ok = true, text = "Checking " .. row.github .. "..." }
    local releases, fetchErr = ModUpdate.fetchReleases(row.github, row.id, {
      force = true,
    })
    if not releases then
      self.modNotice = { ok = false, text = tostring(fetchErr) }
      return
    end
    if #releases == 0 then
      self.modNotice = { ok = false, text = "No .zip releases found" }
      return
    end
    local status, best = ModUpdate.statusFor(row.version, releases)
    self.modUpdateInfo = self.modUpdateInfo or {}
    self.modUpdateInfo[row.id] = {
      status = status, latest = best and best.version, best = best,
      releases = releases, checkedAt = os.time(),
    }
    if status == "available" and best then
      self.modNotice = { ok = true,
        text = row.name .. ": new version available (v" .. best.version .. ")" }
      self._modConfirm = {
        kind = "update", id = row.id, release = best,
        title = "Update available",
        yesLabel = "Update",
        lines = {
          "Update " .. row.name .. "?",
          "Installed v" .. tostring(row.version),
          "Latest v" .. tostring(best.version),
        },
      }
    else
      self.modNotice = { ok = true,
        text = row.name .. " is up to date (v"
          .. tostring(row.version) .. ")" }
    end
  end)
  if not ran then
    self._modVersions = nil
    self.modNotice = { ok = false,
      text = "Update failed: " .. tostring(err) }
  end
end

function RomImporter:_confirmModUpdate(modId, release)
  local row
  for _, m in ipairs(self.mods or {}) do
    if m.id == modId then row = m; break end
  end
  local name = row and row.name or modId
  self.modNotice = { ok = true,
    text = "Downloading " .. tostring(release and release.version or "?") .. "..." }
  local ran, err = pcall(function()
    local LauncherMods = require("src.mods.LauncherMods")
    local ok, res = LauncherMods.installFromRelease(modId, release)
    if ok then
      pcall(self._refreshMods, self)
      self.modNotice = { ok = true,
        text = "Updated " .. name .. " to " .. tostring(res) }
    else
      self.modNotice = { ok = false, text = tostring(res) }
    end
  end)
  if not ran then
    self.modNotice = { ok = false, text = "Update failed: " .. tostring(err) }
  end
end

function RomImporter:_installModVersion(modId, release)
  self._modVersions = nil
  self._modReleaseNotes = nil
  local version = release and release.version or "?"
  self.modNotice = { ok = true, text = "Downloading " .. tostring(version) .. "..." }
  local ran, err = pcall(function()
    local LauncherMods = require("src.mods.LauncherMods")
    local ok, res = LauncherMods.installFromRelease(modId, release)
    if ok then
      pcall(self._refreshMods, self)
      self.modNotice = { ok = true,
        text = "Installed " .. tostring(modId) .. " " .. tostring(res) }
    else
      self.modNotice = { ok = false, text = tostring(res) }
    end
  end)
  if not ran then
    self.modNotice = { ok = false,
      text = "Install failed: " .. tostring(err) }
  end
end


-- NX / desktop / Android labels and inbox hints for the FlexLove view.
function RomImporter:_modsImportButtonLabel()
  if self.isNX then return Strings("Scan again") end
  return "Import mod .zip"
end

function RomImporter:_modsDefaultHint()
  if self.isNX then
    local saveDir = love.filesystem.getSaveDirectory()
    local rel = RomImporter.mtpHintPath(saveDir)
    if rel ~= "" and rel:sub(-1) ~= "/" then rel = rel .. "/" end
    return Strings("Copy a .zip via MTP into %s/imports/mods/\n"
      .. "DBI MTP → 1: SD Card/%simports/mods/", saveDir, rel)
  end
  if self.android then return "Or copy a mod .zip via USB." end
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
    return "Import or export a .sav with the system file picker."
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
-- .zip" does.  The project's own index (bryanthaboi/gen1recomp-mod-index)
-- ships pre-added for every install -- it tops ModIndex.sources() until the
-- player removes it, which opts out permanently -- and any number of other
-- indexes can be added beside it.
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
function RomImporter:_refreshFind(force)
  if not Platform.networkValidated() then
    self.findLoaded = true
    self.findIndex = { mods = {}, categories = {} }
    return
  end
  local ModIndex = require("src.mods.ModIndex")
  self:_refreshFindSources()
  local mods, seen, cats, catSeen, errs = {}, {}, {}, {}, {}
  local stale, oldest = false, nil
  for _, source in ipairs(self.findSources or {}) do
    local ok, index, err, meta = pcall(function()
      return ModIndex.fetch(source, { force = force == true })
    end)
    if not ok then
      errs[#errs + 1] = (source.label or source.feed) .. ": " .. tostring(index)
    elseif not index then
      errs[#errs + 1] = (source.label or source.feed) .. ": " .. tostring(err)
    else
      if meta and meta.stale then stale = true end
      if meta and meta.checkedAt then
        oldest = math.min(oldest or meta.checkedAt, meta.checkedAt)
      end
      for _, entry in ipairs(index.mods or {}) do
        if not seen[entry.id] then
          seen[entry.id] = true
          entry._source = source.label or source.feed
          entry._base = source.base
          mods[#mods + 1] = entry
        end
      end
      for _, c in ipairs(ModIndex.categoriesIn(index)) do
        if not catSeen[c] then catSeen[c] = true; cats[#cats + 1] = c end
      end
    end
  end
  self.findIndex = { mods = mods, categories = cats, stale = stale,
                     checkedAt = oldest }
  self.findLoaded = true
  if #errs > 0 then
    self.findNotice = { ok = false, text = table.concat(errs, "  -  ") }
  elseif force then
    self.findNotice = { ok = true,
      text = Strings("Refreshed - %d mods listed", #mods) }
  end
  -- A category that no longer exists after a refresh would filter everything
  -- away with no way back except guessing.
  if self.findCategory and not catSeen[self.findCategory] then
    self.findCategory = nil
  end
end

function RomImporter:_ensureFind()
  if not self.findLoaded then
    self:_refreshFindSources()
    if #(self.findSources or {}) == 0 then
      -- Nothing to fetch, but the panel is loaded: the empty state is the
      -- answer, not a pending request.
      self.findIndex = { mods = {}, categories = {} }
      self.findLoaded = true
    else
      self:_refreshFind(false)
    end
  end
end

-- The rows the filters leave, and the installed-mod context the compatibility
-- warnings are judged against.
function RomImporter:_findRows()
  local ModIndex = require("src.mods.ModIndex")
  local all = (self.findIndex and self.findIndex.mods) or {}
  return ModIndex.filter(all, {
    query = self.findQuery,
    category = self.findCategory,
  })
end

function RomImporter:_findInstalledMap()
  local map = {}
  for _, m in ipairs(self.mods or {}) do map[m.id] = m.version or true end
  return map
end

-- One thumbnail per frame, and only for a card actually on screen: the fetch
-- is a blocking curl, so downloading a whole listing's worth on open would
-- stall the launcher for as many seconds as there are mods.  A failure is
-- remembered as `false` so a broken URL is tried once, not every frame.
function RomImporter:_findThumb(entry)
  self._findThumbs = self._findThumbs or {}
  local cached = self._findThumbs[entry.id]
  if cached ~= nil then return cached or nil end
  if self._findThumbFetched then return nil end   -- budget spent this frame
  local ModIndex = require("src.mods.ModIndex")
  local url = ModIndex.joinUrl(entry._base, entry.thumbnail)
  if not url then
    self._findThumbs[entry.id] = false
    return nil
  end
  self._findThumbFetched = true
  local ok, image = pcall(function()
    local path, err = ModIndex.downloadThumbnail(url, entry.id)
    if not path then error(err or "download failed", 0) end
    return love.graphics.newImage(path)
  end)
  self._findThumbs[entry.id] = ok and image or false
  return ok and image or nil
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
  local body = entry.summary or ""
  if url then
    local ok, text = pcall(ModIndex.fetchText, url)
    if ok and type(text) == "string" and text ~= "" then body = text end
  end
  self._findDetails = {
    title = entry.title or entry.id,
    body = body,
    scroll = 0,
  }
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

function RomImporter:_findInstall(entry)
  local name = entry.title or entry.id
  self.findNotice = { ok = true, text = Strings("Downloading %s...", name) }
  local ran, err = pcall(function()
    local LauncherMods = require("src.mods.LauncherMods")
    local ok, res = LauncherMods.installFromIndex(entry)
    if ok then
      -- The installed list is what the Install / Installed labels read, so it
      -- has to be re-derived before the next paint or the card lies.
      pcall(self._refreshMods, self)
      self.findNotice = { ok = true,
        text = Strings("Installed %s %s", name, tostring(res)) }
    else
      self.findNotice = { ok = false, text = tostring(res) }
    end
  end)
  if not ran then
    self.findNotice = { ok = false, text = "Install failed: " .. tostring(err) }
  end
end

return RomImporter
