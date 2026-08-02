local GameVersion = require("src.core.GameVersion")
local Strings = require("src.core.Strings")
local HostShell = require("src.core.HostShell")
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
  releasePointerGrab()
  local pipe = HostShell.popen(command)
  if not pipe then return nil end
  local result = pipe:read("*a")
  pipe:close()
  result = trim(result)
  return result ~= "" and result or nil
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
  local prompt = "Choose your " .. promptName .. " ROM"
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
      -- write the pick as UTF-8: the console's OEM codepage would mangle
      -- non-ASCII names (Pokémon -> Pok\x82mon) and crash any text draw
      -- that shows them (#325)
      "if($d.ShowDialog() -eq 'OK'){[Console]::OutputEncoding=[Text.Encoding]::UTF8; [Console]::Write($d.FileName)}",
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
  local prompt = Strings("Choose a mod .zip")
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
  local prompt = Strings("Choose a .sav save file")
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
      -- UTF-8, like the ROM and mod pickers (#325)
      "if($d.ShowDialog() -eq 'OK'){[Console]::OutputEncoding=[Text.Encoding]::UTF8; [Console]::Write($d.FileName)}",
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
  local mobileOS = love.system.getOS()
  local android = mobileOS == "Android" or mobileOS == "iOS"
  local CacheFs = require("src.import.CacheFs")
  local self = setmetatable({
    onComplete = onComplete,
    launcher = opts.launcher or false,
    forceImport = opts.forceImport or false,
    onEditSave = opts.onEditSave,
    onEditTouchControls = opts.onEditTouchControls,
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
    pickPending = android or nil,
    -- Android drag: the launcher is handed no move events at all (main.lua
    -- forwards neither touchmoved nor mousemoved while it is up), and its mouse
    -- emulation is what "no reliable pointer polling" below refers to.
    -- love.touch IS pollable, so where it exists a touch drag can be resolved
    -- inside draw the same way the desktop mouse is.  Where it does not, every
    -- Android path stays exactly as it was: act on press, never arm.
    touchPollable = android and love.touch ~= nil
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
  if android and needRom then
    local name, data = findPendingRom(self.ready)
    if name then
      self:startData(data, name)
    else
      -- The picker runs as its own activity and Android may kill us while it
      -- is up, so a rejected pick can outlive the focus handler (#442).
      consumePickedRomError(self)
    end
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

  -- On Linux handhelds a gamepad is usually already connected at boot; arm
  -- the virtual cursor immediately so the player does not have to press a
  -- button before seeing something move.
  if self.launcher and love.system.getOS() == "Linux"
      and love.joystick and love.joystick.getJoystickCount
      and love.joystick.getJoystickCount() > 0 then
    self:_activatePadCursor()
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
    if self.android and type(displayName) == "string"
        and not displayName:find("[/\\]") then
      love.filesystem.remove(displayName)
    end
    self.importing = nil
    self.workState = "complete"
    self.completeVersion = version
    self.status = "Ready"
    self.detail = "Starting " .. info.displayName .. "..."
    self.progress = 1
    if self.launcher then
      -- Stay on the launcher; the player presses Play to boot the new game.
      return
    end
    self._handedOff = true
    resetPointerCursor(self)
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
function RomImporter:chooseMod()
  if self.workState == "working" then return end
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
function RomImporter:chooseSaveImport(version)
  if self.workState == "working" then return end
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
function RomImporter:exportSave(version)
  if self.workState == "working" then return end
  local ok, res = require("src.import.SaveFileIO").exportActiveSlot(version)
  if not ok then
    self.saveNotice[version] = { ok = false, text = tostring(res) }
    return
  end
  if self.android then
    local rel = res:match("exports[/\\][^/\\]+$")
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

function RomImporter:_cycleTab(delta)
  local order = { "red", "blue", "yellow", "mods", "find" }
  local idx = 1
  for i, id in ipairs(order) do
    if id == self.tab then idx = i; break end
  end
  idx = ((idx - 1 + delta) % #order) + 1
  self.tab = order[idx]
  self._slotPress = nil
  self._modPress = nil
  self._findSearchFocus = false
  self:_disarmTextInput()
end

function RomImporter:_updatePadCursor(dt)
  -- Real mouse motion yields the pad cursor so desktop users keep a normal
  -- pointer after bumping a stick once.
  local mx, my = love.mouse.getPosition()
  if self._lastMouseX and self._padCursorActive then
    if math.abs(mx - self._lastMouseX) > 3 or math.abs(my - self._lastMouseY) > 3 then
      self._padCursorActive = false
    end
  end
  self._lastMouseX, self._lastMouseY = mx, my

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
  end

  -- Right stick scrolls the active list (save slots or mods), or the whole page
  -- when it is the thing that overflows.
  local ry = self._padAxis.righty or 0
  if math.abs(ry) > PAD_DEAD then
    self:_activatePadCursor()
    local step = -ry * 480 * dt
    local maxPage = self._pageMax or 0
    if maxPage > 0 then
      self.pageScroll = math.max(0, math.min(maxPage, (self.pageScroll or 0) + step))
    elseif self.tab == "mods" then
      local maxS = self._modMax or 0
      if maxS > 0 then
        local next = (self.modScroll or 0) + step
        self.modScroll = math.max(0, math.min(maxS, next))
      end
    elseif self.tab == "find" then
      local maxS = self._findMax or 0
      if maxS > 0 then
        local next = (self.findScroll or 0) + step
        self.findScroll = math.max(0, math.min(maxS, next))
      end
    elseif GameVersion.VERSIONS[self.tab] then
      local maxS = (self._slotMax and self._slotMax[self.tab]) or 0
      if maxS > 0 then
        local next = (self.slotScroll[self.tab] or 0) + step
        self.slotScroll[self.tab] = math.max(0, math.min(maxS, next))
      end
    end
  end
end

function RomImporter:gamepadpressed(_, button)
  self:_activatePadCursor()
  if button == "a" then
    -- Instant click at the virtual pointer (same path as a mouse/touch tap).
    self:mousepressed(self._padCursor.x, self._padCursor.y, 1)
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
      if self.ready[version] then self:play(version) else self:choose(version) end
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

-- Same gate as src/core/Input.lua's isMappedPad: a pad SDL can map already
-- reached gamepadpressed this frame, so re-entering it from the raw event
-- would fire the virtual cursor's click twice off one A press (#620).
local function isMappedPad(joystick)
  return joystick ~= nil and joystick.isGamepad ~= nil and joystick:isGamepad()
end

function RomImporter:joystickpressed(joystick, button)
  if isMappedPad(joystick) then return end
  if button == 1 then self:gamepadpressed(joystick, "a") end
end

function RomImporter:joystickreleased(joystick, button)
  if isMappedPad(joystick) then return end
  if button == 1 then self:gamepadreleased(joystick, "a") end
end

function RomImporter:joystickaxis(joystick, axis, value)
  if isMappedPad(joystick) then return end
  if axis == 1 then
    self:gamepadaxis(joystick, "leftx", value)
  elseif axis == 2 then
    self:gamepadaxis(joystick, "lefty", value)
  end
end

function RomImporter:joystickhat(joystick, hat, direction)
  if isMappedPad(joystick) then return end
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

-- set the current draw colour from a PAL triple (0-255), with optional alpha 0-1
local function col(c, a)
  love.graphics.setColor(c[1] / 255, c[2] / 255, c[3] / 255, a or 1)
end

-- Faux-bold: the launcher's UI font ships no bold face, so 800-weight text
-- (headings, buttons) is thickened with a second sub-pixel pass.
local function printfB(text, x, y, w, align)
  love.graphics.printf(text, x, y, w, align)
  love.graphics.printf(text, x + 0.6, y, w, align)
end
local function printB(text, x, y)
  love.graphics.print(text, x, y)
  love.graphics.print(text, x + 0.6, y)
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

-- One reusable unit quad, recoloured per call, for every vertical gradient
-- fill (LOVE has no gradient primitive and a per-frame newMesh would churn
-- the GPU).  Callers set the blend mode; this only touches colour + geometry.
local gradMesh
local function setGrad(cTop, cBot, aTop, aBot)
  if not gradMesh then gradMesh = love.graphics.newMesh(4, "fan", "dynamic") end
  gradMesh:setVertices({
    { 0, 0, 0, 0, cTop[1] / 255, cTop[2] / 255, cTop[3] / 255, aTop },
    { 1, 0, 1, 0, cTop[1] / 255, cTop[2] / 255, cTop[3] / 255, aTop },
    { 1, 1, 1, 1, cBot[1] / 255, cBot[2] / 255, cBot[3] / 255, aBot },
    { 0, 1, 0, 1, cBot[1] / 255, cBot[2] / 255, cBot[3] / 255, aBot },
  })
end
local function fillGrad(x, y, w, h, cTop, cBot, aTop, aBot)
  setGrad(cTop, cBot, aTop, aBot)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(gradMesh, x, y, 0, w, h)
end
-- vertical gradient clipped to a rounded rectangle (via the stencil buffer)
local function fillGradRounded(x, y, w, h, r, cTop, cBot, aTop, aBot)
  love.graphics.stencil(function()
    love.graphics.rectangle("fill", x, y, w, h, r, r)
  end, "replace", 1)
  love.graphics.setStencilTest("greater", 0)
  fillGrad(x, y, w, h, cTop, cBot, aTop, aBot)
  love.graphics.setStencilTest()
end

-- Soft additive neon halo around a rounded rect.  LOVE has no blur, so stack
-- progressively larger, fainter translucent rounded rects.
local function neonGlow(x, y, w, h, r, c, strength)
  strength = math.max(0, strength)
  if strength == 0 then return end
  love.graphics.setBlendMode("add")
  local layers = 7
  for i = 1, layers do
    local g = i * 2.4
    love.graphics.setColor(c[1] / 255, c[2] / 255, c[3] / 255,
      strength * 0.05 * (1 - (i - 1) / layers))
    love.graphics.rectangle("fill", x - g, y - g, w + 2 * g, h + 2 * g, r + g, r + g)
  end
  love.graphics.setBlendMode("alpha")
end

-- A white shine band that sweeps across an active button, clipped to its
-- rounded shape.  phase is 0..1 (left of the button -> right of it).
local shineMesh
local function buttonShine(x, y, w, h, r, phase)
  if not shineMesh then
    -- triangle strip: three columns (transparent, white, transparent)
    shineMesh = love.graphics.newMesh({
      { 0,   0, 0,   0, 1, 1, 1, 0 },
      { 0,   1, 0,   1, 1, 1, 1, 0 },
      { 0.5, 0, 0.5, 0, 1, 1, 1, 0.5 },
      { 0.5, 1, 0.5, 1, 1, 1, 1, 0.5 },
      { 1,   0, 1,   0, 1, 1, 1, 0 },
      { 1,   1, 1,   1, 1, 1, 1, 0 },
    }, "strip", "static")
  end
  local bandW = w * 0.6
  local bx = x - bandW + phase * (w + bandW)
  love.graphics.stencil(function()
    love.graphics.rectangle("fill", x, y, w, h, r, r)
  end, "replace", 1)
  love.graphics.setStencilTest("greater", 0)
  love.graphics.setBlendMode("add")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(shineMesh, bx, y, 0, bandW, h)
  love.graphics.setBlendMode("alpha")
  love.graphics.setStencilTest()
end

-- Draw letterspaced text (the UI font has no tracking control): advance glyph
-- by glyph.  Returns the total drawn width so a caller can align to it.
local function printSpaced(font, text, x, y, spacing)
  local cx = x
  for i = 1, #text do
    local ch = text:sub(i, i)
    love.graphics.print(ch, cx, y)
    cx = cx + font:getWidth(ch) + spacing
  end
  return math.max(0, cx - x - spacing)
end

-- Clip text to a pixel width, appending an ellipsis when it overflows (the UI
-- font has no built-in truncation).  Used for save-slot names / meta lines.
-- Drops whole UTF-8 codepoints (never mid-byte) so Font:getWidth cannot see
-- a truncated multi-byte sequence and throw "UTF-8 decoding error".
local function ellipsize(font, text, maxW)
  text = tostring(text or "")
  if maxW <= 0 or font:getWidth(text) <= maxW then return text end
  local ell = "..."
  local ew = font:getWidth(ell)
  while #text > 0 and font:getWidth(text) + ew > maxW do
    text = utf8Back(text)
  end
  return text .. ell
end

-- Stroke a rounded rectangle as a dashed outline (LOVE has no dashed line):
-- sample the path into a polyline -- corners as short arcs -- then walk it,
-- toggling on/off every dash/gap.  Used for the "+ New save slot" button and
-- the empty-slots box.  Caller sets colour + line width.
local function dashedRoundRect(x, y, w, h, r, dash, gap)
  r = math.min(r, w / 2, h / 2)
  local seg = 4
  local pts = {}
  local function arc(cx, cy, a0, a1)
    for i = 0, seg do
      local a = a0 + (a1 - a0) * (i / seg)
      pts[#pts + 1] = cx + math.cos(a) * r
      pts[#pts + 1] = cy + math.sin(a) * r
    end
  end
  arc(x + w - r, y + r, -math.pi / 2, 0)
  arc(x + w - r, y + h - r, 0, math.pi / 2)
  arc(x + r, y + h - r, math.pi / 2, math.pi)
  arc(x + r, y + r, math.pi, math.pi * 1.5)
  pts[#pts + 1] = pts[1]; pts[#pts + 1] = pts[2]   -- close the loop
  local remaining, drawing = dash, true
  for i = 1, #pts - 2, 2 do
    local x1, y1 = pts[i], pts[i + 1]
    local dx, dy = pts[i + 2] - x1, pts[i + 3] - y1
    local segLen = math.sqrt(dx * dx + dy * dy)
    local pos = 0
    while pos < segLen do
      local step = math.min(remaining, segLen - pos)
      if drawing then
        local t0, t1 = pos / segLen, (pos + step) / segLen
        love.graphics.line(x1 + dx * t0, y1 + dy * t0, x1 + dx * t1, y1 + dy * t1)
      end
      pos = pos + step
      remaining = remaining - step
      if remaining <= 0.0001 then
        drawing = not drawing
        remaining = drawing and dash or gap
      end
    end
  end
end

-- The redesign's standard content card: a faint top-lit blue tint fading into
-- a dark interior, with a thin cool-gray border.  Shared by the ROM / SAVE
-- FILES / SAVE SLOT cards and the mod cards so every panel matches.
local function roundedCard(x, y, w, h, r)
  fillGradRounded(x, y, w, h, r, PAL.blue, PAL.cardBlue, 0.08, 0.5)
  love.graphics.setLineWidth(1)
  col(PAL.cardBorder, 0.28)
  love.graphics.rectangle("line", x, y, w, h, r, r)
end

-- {top, bottom} of the scrolling page viewport, or nil while the page fits and
-- nothing scrolls.  Written once per frame by draw(); read by the two hit tests
-- (`inside` for clicks, `_ptIn` for hover) so a control scrolled out from under
-- the pinned header, or past the window bottom, stops responding at the moment
-- it stops being visible.  Rects that live in the pinned header carry
-- `pinned = true` and are exempt.
local pageBand = nil

-- Page-scroll arithmetic, kept pure (no love, no self) so the engine tier can
-- pin it: given how tall the column under the tab bar wants to be and how much
-- room is left under it, say whether the page scrolls, where it sits, and how
-- far it can go.  A window that grew back pulls the offset down with it rather
-- than leaving the page parked past its own end.
function RomImporter.pageScrollFor(naturalH, viewportH, scroll)
  local maxPage = math.max(0, (naturalH or 0) - math.max(0, viewportH or 0))
  return maxPage > 0, clamp(scroll or 0, 0, maxPage), maxPage
end

-- Every hit rect mousepressed dispatches on, cleared before any panel draws:
-- each rect is rebuilt only by the panel that draws its control, so whatever a
-- frame does not draw must not stay clickable.  Missing the Delete rects here
-- let a click on the mods tab land on the game tab's save Delete label (#433).
function RomImporter:_resetFrameRects()
  self.romButtonRect = nil
  self.playButtonRect = nil
  self.tabRects = {}
  -- Rebuilt only by the active version's SAVE SLOT panel, so the mods tab (or a
  -- version with no panel drawn this frame) cannot inherit last frame's rows.
  self.slotRects = nil
  self.slotEditRects = nil
  self.slotDeleteRects = nil
  self.newSlotRect = nil
  -- Rebuilt only by the mods panel; nil elsewhere so a game tab cannot inherit
  -- last frame's mod toggles / Delete labels / import button.
  self.modRects = nil
  self.modDeleteRects = nil
  self.modImportRect = nil
  -- Enable all / Disable all share that header and the same rule (#647): they
  -- are only drawn when the row is wide enough, so a stale rect would otherwise
  -- stay clickable over whatever the next tab (or the next window size) draws.
  self.modEnableAllRect = nil
  self.modDisableAllRect = nil
  -- Same rule as the toggles above, and it started to bite once FIND MODS gave
  -- the mods tab a neighbour: these two were rebuilt by the mods panel but
  -- never cleared, so switching tabs left the last mod row's Update / Versions
  -- labels clickable over whatever the next tab drew there (#433's shape).
  self.modUpdateRects = nil
  self.modVersionsRects = nil
  -- Rebuilt only by the FIND MODS panel.
  self.findAddRect = nil
  self.findRefreshRect = nil
  self.findSearchRect = nil
  self.findCatRects = nil
  self.findInstallRects = nil
  self.findDetailRects = nil
  self.findRepoRects = nil
  self.findSourceRemoveRects = nil
  -- Rebuilt only by the active game panel's SAVE FILES card; nil elsewhere so
  -- the mods tab cannot inherit last frame's save Import/Export/open-folder hits.
  self.saveImportRect = nil
  self.saveExportRect = nil
  self.saveFolderRect = nil
  -- Rebuilt only by the active game panel; nil elsewhere so the mods tab
  -- cannot inherit last frame's Touch Controls button.
  self.touchControlsRect = nil
end

function RomImporter:draw()
  -- Full window for immersive backdrop; safe rect for interactive chrome so
  -- notch / Dynamic Island / home indicator / Android cutouts are respected.
  local fullW, fullH = love.graphics.getDimensions()
  local ox, oy, width, height = SafeArea.rect()
  local s = clamp(height / 768, 0.7, 1.6)
  local pulse = self.pulse
  self._s = s

  -- Hover state.  Desktop mouse, or the gamepad virtual cursor on handhelds
  -- (Android stays touch-only -- no hover).  Panel methods read the pointer +
  -- set self._anyHover through self:_hover; the cursor is set at the end.
  -- Reset the per-frame hit rects so a tab with no controls (mods) cannot
  -- inherit last frame's game-panel buttons.
  if self._padCursorActive then
    self._mx, self._my = self._padCursor.x, self._padCursor.y
  else
    self._mx, self._my = love.mouse.getPosition()
  end
  self._hoverEnabled = self._padCursorActive or not self.android
  self._anyHover = false
  self:_resetFrameRects()

  -- Fonts + size-dependent scenery, rebuilt only when the window / safe
  -- area changes (rotation, resize, inset changes).
  local fontKey = ("%dx%d@%d,%d"):format(fullW, fullH, ox, oy)
  if self.fontKey ~= fontKey then
    self.fontKey = fontKey
    local function f(px) return love.graphics.newFont(math.max(8, math.floor(px + 0.5))) end
    self.headFont     = f(19 * s)
    self.detailFont   = f(14 * s)
    self.buttonFont   = f(19 * s)
    self.hintFont     = f(13 * s)
    self.warningFont  = f(11 * s)
    -- redesign faces
    self.gameNameFont = f(26 * s)   -- game / "Mods" heading
    self.pillFont     = f(13 * s)   -- status pill
    self.labelFont    = f(12 * s)   -- letterspaced ROM / SAVE FILES / SAVE SLOT
    self.stateFont    = f(16 * s)   -- ROM state line
    self.saveBtnFont  = f(14 * s)   -- glassy card buttons
    self.chipFont     = f(20 * s)   -- R / B / Y tab letters
    self.tabLabelFont = f(14 * s)   -- active tab label
    self.readyFont    = f(12 * s)   -- "N of 3 ready"
    self.playFont     = f(20 * s)   -- Play button
    self.slotNameFont = f(15 * s)   -- save-slot player name / "NEW GAME"

    -- Background: a radial gradient (bright navy at top-centre -> near black).
    -- A triangle fan from the top-centre gives the radial falloff; the screen
    -- is cleared to the outer colour first so the corners it does not reach
    -- match seamlessly.  Sized to the full window so unsafe edges stay filled.
    do
      local cx, cy = fullW / 2, 0
      local rx, ry = fullW * 1.3, fullH * 1.08
      local n = 72
      local verts = { { cx, cy, 0, 0,
        PAL.bgTop[1] / 255, PAL.bgTop[2] / 255, PAL.bgTop[3] / 255, 1 } }
      for i = 0, n do
        local a = (i / n) * math.pi * 2
        verts[#verts + 1] = { cx + math.cos(a) * rx, cy + math.sin(a) * ry, 0, 0,
          PAL.bgBot[1] / 255, PAL.bgBot[2] / 255, PAL.bgBot[3] / 255, 1 }
      end
      self.bgMesh = love.graphics.newMesh(verts, "fan", "static")
    end

    -- CRT vignette: a gentle edge darkening, centred slightly above the middle.
    do
      local cx, cy = fullW / 2, fullH * 0.45
      local rx, ry = fullW * 0.78, fullH * 0.78
      local n = 72
      local verts = { { cx, cy, 0, 0, 0, 0, 0, 0 } }
      for i = 0, n do
        local a = (i / n) * math.pi * 2
        verts[#verts + 1] =
          { cx + math.cos(a) * rx, cy + math.sin(a) * ry, 0, 0, 0, 0, 0, 0.32 }
      end
      self.vignetteMesh = love.graphics.newMesh(verts, "fan", "static")
    end

    -- CRT scanlines: a 1px dark line every 3px, baked into a tiny tile and
    -- drawn once with a repeat-wrapped quad (one draw call, correct alpha).
    if not self.scanlineImage then
      local id = love.image.newImageData(1, 3)
      id:setPixel(0, 0, 0, 0, 0, 0.08)
      id:setPixel(0, 1, 0, 0, 0, 0)
      id:setPixel(0, 2, 0, 0, 0, 0)
      self.scanlineImage = love.graphics.newImage(id)
      self.scanlineImage:setWrap("repeat", "repeat")
      self.scanlineImage:setFilter("nearest", "nearest")
    end
    self.scanlineQuad = love.graphics.newQuad(0, 0, fullW, fullH, 1, 3)
  end

  -- Invert shader: the Boi's Club Games mark is dark ink; on this dark panel it
  -- is rendered white (the design's filter:invert(1)).  Built lazily so a
  -- headless require never needs a GL context.
  self.invertShader = self.invertShader or love.graphics.newShader([[
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
      vec4 p = Texel(tex, tc);
      return vec4((vec3(1.0) - p.rgb) * color.rgb, p.a * color.a);
    }
  ]])

  -- Shine shader: the same white sweep the active buttons get, but clipped to
  -- the logo's own shape (a soft band brightens the pixels it crosses; fully
  -- transparent pixels stay transparent).
  self.shineShader = self.shineShader or love.graphics.newShader([[
    extern number shinePos;
    extern number shineW;
    vec4 effect(vec4 color, Image tex, vec2 tc, vec2 sc) {
      vec4 p = Texel(tex, tc);
      float band = smoothstep(shineW, 0.0, abs(tc.x - shinePos));
      return vec4(p.rgb + band * 0.55, p.a) * color;
    }
  ]])

  -- background (full window — unsafe edges stay painted)
  col(PAL.bgBot)
  love.graphics.rectangle("fill", 0, 0, fullW, fullH)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(self.bgMesh)

  -- Centered content container (max ~1440 scaled units on very wide windows)
  -- with a responsive side gutter; every column below derives from these.
  -- Origin is the safe-area top-left so chrome clears device insets.
  local appW = math.min(width, 1440 * s)
  local appX = ox + (width - appW) / 2
  local padH = clamp(appW * 0.03, 12 * s, 26 * s)
  local third = appW / 3

  -- tricolor strip (Red | Blue | Yellow), 6px tall, with a soft downward bloom
  local stripH = math.max(4, 6 * s)
  local stripY = oy
  local segs = {
    { PAL.red,  appX,             third },
    { PAL.blue, appX + third,     third },
    { PAL.gold, appX + 2 * third, appW - 2 * third },
  }
  love.graphics.setBlendMode("add")
  for _, seg in ipairs(segs) do
    fillGrad(seg[2], stripY + stripH, seg[3], stripH * 3.6, seg[1], seg[1], 0.30, 0.0)
  end
  love.graphics.setBlendMode("alpha")
  for _, seg in ipairs(segs) do
    col(seg[1]); love.graphics.rectangle("fill", seg[2], stripY, seg[3], stripH)
  end

  -- Footer (Boi's Club Games logo + trust warning), measured first so the
  -- content region knows where it must stop.  Only its height is fixed here:
  -- it is laid out from a top edge further down, which is the window bottom
  -- while the page fits and the end of the scrolled content when it does not.
  local warningWidth = math.min(appW - 32 * s, 640 * s)
  local _, warningLines = self.warningFont:getWrap(TRUST_WARNING, warningWidth)
  local warningH = #warningLines * self.warningFont:getHeight()
  local bcgW, bcgH = self.bcg:getDimensions()
  local bcgScale = math.min(math.min(appW - 48 * s, 190 * s) / bcgW, height * 0.06 / bcgH)
  local bcgDW, bcgDH = bcgW * bcgScale, bcgH * bcgScale
  local footerH = 10 * s + bcgDH + 6 * s + warningH + 12 * s

  -- Logo: centred over the strip, width clamped, gentle bob + glow pulse.  The
  -- resting metrics fix the tab bar's top so the layout never shifts as it bobs.
  local logoW, logoH = self.logo:getDimensions()
  local logoTargetW = math.max(math.min(180 * s, appW - 32 * s),
    math.min(330 * s, appW - 32 * s))
  local logoScale = math.min(logoTargetW / logoW, height * 0.15 / logoH)
  local logoDW, logoDH = logoW * logoScale, logoH * logoScale
  local logoY = stripY + stripH + 14 * s

  -- Tab bar: R/B/Y/divider/MODS chips (label + underline on the active one),
  -- with "N of 3 ready" right-aligned.
  local chip = 44 * s
  local tabBarY = logoY + logoDH + 6 * s
  local tabBarH = chip + 22 * s

  -- Self-updater banner state: computed up front so its band can be reserved
  -- above the footer, then drawn after the content below.  Only the four
  -- actionable states surface anything.
  local upStatus, upLatest, upProgress
  if self.Check then
    local ok, st = pcall(self.Check.state)
    st = (ok and type(st) == "table") and st or nil
    local status = st and st.status
    if status == "available" or status == "downloading"
        or status == "ready" or status == "needs_full" then
      upStatus, upLatest, upProgress = status, st.latest, st.progress
    end
  end
  local bannerActive = upStatus ~= nil
  local bannerH = 46 * s

  -- Content region: from below the tab bar down to the footer, minus the
  -- updater band when one is showing.
  local contentTop = tabBarY + tabBarH + 16 * s
  local bannerBand = bannerActive and (bannerH + 20 * s) or 6 * s
  local cX = appX + padH
  local cW = appW - 2 * padH
  local contentBottom = oy + height - footerH - bannerBand
  local cH = math.max(0, contentBottom - contentTop)

  -- Page scroll.  Everything under the tab bar -- panel, updater banner and
  -- footer -- is one column: too short a window scrolls it instead of letting
  -- the panel run under a footer pinned to the window bottom (a stacked
  -- single-column layout on a phone-shaped window overflows by a card or two).
  -- The panels report their natural height as they draw, so the decision reads
  -- the previous frame's measurement, the same one-frame settle the slot and
  -- mod lists already rely on.  While the page fits, `paged` is false and every
  -- measurement below is what it always was.
  local viewportH = math.max(0, oy + height - contentTop)
  self._panelNaturalH = self._panelNaturalH or {}
  local naturalH = (self._panelNaturalH[self.tab] or 0) + bannerBand + footerH
  local paged, pageScroll, maxPage =
    RomImporter.pageScrollFor(naturalH, viewportH, self.pageScroll)
  self.pageScroll, self._pageMax = pageScroll, maxPage
  -- read by the hit tests; a scrolled control is live only inside the viewport
  pageBand = paged and { contentTop, oy + height } or nil

  -- tab bar (rebuilds self.tabRects).  Pinned: it is the launcher's navigation,
  -- and it sits above the scrolling viewport.
  self:_drawTabBar(cX, tabBarY, cW, tabBarH, chip)

  local panelY = contentTop - (paged and self.pageScroll or 0)
  if paged then
    love.graphics.setScissor(math.floor(appX), math.floor(contentTop),
      math.ceil(appW), math.ceil(viewportH))
  end

  -- content: game panel for a version tab, mods panel for the mods tab
  local panelH
  if self.tab == "mods" then
    panelH = self:_drawModsPanel(cX, panelY, cW, cH, paged)
  elseif self.tab == "find" then
    panelH = self:_drawFindPanel(cX, panelY, cW, cH, paged)
  else
    panelH = self:_drawGamePanel(self.tab, cX, panelY, cW, cH, paged)
  end
  panelH = panelH or 0
  self._panelNaturalH[self.tab] = panelH

  -- The updater band and the footer follow the content: pinned to the window
  -- bottom while the page fits, riding at the end of the scroll when it does not.
  local bandTop = paged and (panelY + panelH) or contentBottom
  local footerTop = bandTop + bannerBand

  -- Self-updater banner: a compact pill centred in the reserved band just above
  -- the footer, on every tab.  Same green "Play" treatment on its CTA.
  self.updateButton = nil
  if bannerActive then
    local bannerW = math.min(appW - 32 * s, 560 * s)
    local bx = appX + (appW - bannerW) / 2
    local by = bandTop + math.max(0, (footerTop - bandTop - bannerH) / 2)
    local r = 12 * s
    local accent = PAL.gold

    neonGlow(bx, by, bannerW, bannerH, r, accent, 0.28)
    fillGradRounded(bx, by, bannerW, bannerH, r, accent, PAL.bgBot, 0.14, 0.6)
    love.graphics.setLineWidth(math.max(1, 1.2 * s))
    col(accent, 0.5)
    love.graphics.rectangle("line", bx, by, bannerW, bannerH, r, r)

    local padX = 16 * s
    local innerX = bx + padX
    local innerW = bannerW - 2 * padX

    local function actionButton(label)
      love.graphics.setFont(self.detailFont)
      local bw = math.min(innerW * 0.62, self.detailFont:getWidth(label) + 34 * s)
      local bh = bannerH - 12 * s
      local abx = bx + bannerW - padX - bw
      local aby = by + (bannerH - bh) / 2
      local br = 9 * s
      local rect = { x = abx, y = aby, width = bw, height = bh }
      local hot = self:_hover(rect)
      local gp = 0.5 + 0.5 * math.sin(pulse * 2 * math.pi / 2.4)
      neonGlow(abx, aby, bw, bh, br, PAL.playTop, (0.6 + 0.25 * gp) * (hot and 1.7 or 1))
      fillGradRounded(abx, aby, bw, bh, br, PAL.playTop, PAL.playBot, 1, 1)
      if hot then
        love.graphics.setBlendMode("add")
        love.graphics.setColor(1, 1, 1, 0.12)
        love.graphics.rectangle("fill", abx, aby, bw, bh, br, br)
        love.graphics.setBlendMode("alpha")
      end
      buttonShine(abx, aby, bw, bh, br, (pulse % 2.8) / 2.8)
      love.graphics.setFont(self.detailFont)
      col(PAL.playInk)
      printfB(label, abx, aby + (bh - self.detailFont:getHeight()) / 2, bw, "center")
      return rect
    end

    local function message(text, reserveW)
      love.graphics.setFont(self.detailFont)
      col(PAL.heading)
      love.graphics.printf(text, innerX,
        by + (bannerH - self.detailFont:getHeight()) / 2,
        math.max(1, innerW - reserveW - 12 * s), "left")
    end

    if upStatus == "available" then
      local rect = actionButton("Update")
      self.updateButton = { x = rect.x, y = rect.y, width = rect.width,
        height = rect.height, action = "download" }
      message(upLatest and ("Update v" .. upLatest .. " available")
        or Strings("An update is available"), rect.width)
    elseif upStatus == "needs_full" then
      local rect = actionButton("Open releases")
      self.updateButton = { x = rect.x, y = rect.y, width = rect.width,
        height = rect.height, action = "openurl" }
      message("A new version needs a fresh download", rect.width)
    elseif upStatus == "ready" then
      local rect = actionButton("Restart to update")
      self.updateButton = { x = rect.x, y = rect.y, width = rect.width,
        height = rect.height, action = "restart" }
      message("Update downloaded", rect.width)
    elseif upStatus == "downloading" then
      love.graphics.setFont(self.hintFont)
      col(PAL.detail)
      love.graphics.print("Downloading update", innerX, by + 7 * s)
      local h2 = math.max(8, 10 * s)
      local track = by + bannerH - h2 - 8 * s
      col(PAL.bgBot, 0.85)
      love.graphics.rectangle("fill", innerX, track, innerW, h2, h2 / 2, h2 / 2)
      local pw = innerW * clamp(upProgress or 0, 0, 1)
      if pw > h2 then
        neonGlow(innerX, track, pw, h2, h2 / 2, accent, 0.6)
        col(accent)
        love.graphics.rectangle("fill", innerX, track, pw, h2, h2 / 2, h2 / 2)
      end
    end
  end

  -- footer: a hairline top border, the BCG mark (inverted to white, glowing
  -- brighter on hover) + the trust warning with its live bois.icu link.  Laid
  -- out downward from footerTop, so the same code serves the pinned and the
  -- scrolled position.
  love.graphics.setLineWidth(1)
  col(PAL.cardBorder, 0.18)
  love.graphics.line(appX + padH, footerTop, appX + appW - padH, footerTop)

  local bcgX, bcgY = appX + (appW - bcgDW) / 2, footerTop + 10 * s
  local warningY = bcgY + bcgDH + 6 * s
  self.bcgButton = { x = bcgX, y = bcgY, width = bcgDW, height = bcgDH }

  local bcgHot = self:_hover(self.bcgButton)
  love.graphics.setShader(self.invertShader)
  love.graphics.setBlendMode("add")
  love.graphics.setColor(1, 1, 1, bcgHot and 0.5 or 0.22)
  love.graphics.draw(self.bcg, bcgX - bcgDW * 0.02, bcgY - bcgDH * 0.02, 0,
    bcgScale * 1.04, bcgScale * 1.04)
  love.graphics.setBlendMode("alpha")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(self.bcg, bcgX, bcgY, 0, bcgScale, bcgScale)
  love.graphics.setShader()

  love.graphics.setFont(self.warningFont)
  col(PAL.warning)
  local wrapX = appX + (appW - warningWidth) / 2
  love.graphics.printf(TRUST_WARNING, wrapX, warningY, warningWidth, "center")
  self.linkUrlRect = nil
  do
    local lh = self.warningFont:getHeight()
    local _, lines = self.warningFont:getWrap(TRUST_WARNING, warningWidth)
    for i, line in ipairs(lines) do
      local sidx = line:find(COMMUNITY_URL, 1, true)
      if sidx then
        local before = line:sub(1, sidx - 1)
        local lineW = self.warningFont:getWidth(line)
        local ux = wrapX + (warningWidth - lineW) / 2 + self.warningFont:getWidth(before)
        local uy = warningY + (i - 1) * lh
        local uw = self.warningFont:getWidth(COMMUNITY_URL)
        self.linkUrlRect = { x = ux, y = uy, width = uw, height = lh }
        local linkHot = self:_hover(self.linkUrlRect)
        col(linkHot and PAL.linkHover or PAL.link)
        love.graphics.print(COMMUNITY_URL, ux, uy)
        love.graphics.setLineWidth(1)
        love.graphics.line(ux, uy + lh - 1, ux + uw, uy + lh - 1)
        break
      end
    end
  end

  -- End of the scrolling column; the logo and the page scrollbar are pinned and
  -- draw outside it.
  if paged then love.graphics.setScissor() end

  -- logo, over the split, with a gentle bob + gold glow + sweeping shine
  local bob = math.sin(pulse * (2 * math.pi / 4)) * 6 * s
  local lx, ly = ox + (width - logoDW) / 2, logoY + bob
  love.graphics.setBlendMode("add")
  love.graphics.setColor(1, 0.85, 0.2, 0.16 + 0.12 * (0.5 + 0.5 * math.sin(pulse * 1.6)))
  love.graphics.draw(self.logo, ox + (width - logoDW * 1.05) / 2, ly - logoDH * 0.025, 0,
    logoScale * 1.05, logoScale * 1.05)
  love.graphics.setBlendMode("alpha")
  local shineW = 0.16
  self.shineShader:send("shinePos", -shineW + ((pulse % 2.8) / 2.8) * (1 + 2 * shineW))
  self.shineShader:send("shineW", shineW)
  love.graphics.setShader(self.shineShader)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(self.logo, lx, ly, 0, logoScale, logoScale)
  love.graphics.setShader()

  -- page scrollbar: the same thin thumb the lists use, against the app edge
  if paged then
    local thumbH = math.max(24 * s, viewportH * (viewportH / naturalH))
    local thumbY = contentTop + (viewportH - thumbH) * (self.pageScroll / maxPage)
    col(PAL.cardBorder, 0.35)
    love.graphics.rectangle("fill", appX + appW - padH * 0.5, thumbY, 3 * s, thumbH,
      1.5 * s, 1.5 * s)
  end

  -- CRT scanlines + vignette, over everything
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(self.scanlineImage, self.scanlineQuad, 0, 0)
  love.graphics.draw(self.vignetteMesh)
  love.graphics.setColor(1, 1, 1, 1)

  -- drag-to-scroll the save-slot list (polls the pointer; no move/release
  -- events reach the launcher, so click-vs-drag is resolved here)
  self:_updateSlotDrag()

  -- save-slot rename modal (#205), drawn over everything
  if self._rename then
    col(PAL.bgBot, 0.72)
    love.graphics.rectangle("fill", 0, 0, fullW, fullH)
    local dw = math.min(appW - 32 * s, 420 * s)
    local dh = 128 * s
    local dx = appX + (appW - dw) / 2
    local dy = oy + (height - dh) / 2
    local rr = 12 * s
    neonGlow(dx, dy, dw, dh, rr, PAL.green, 0.4)
    fillGradRounded(dx, dy, dw, dh, rr, PAL.slotBg, PAL.slotBg, 0.85, 0.85)
    love.graphics.setLineWidth(math.max(1, 1.2 * s))
    col(PAL.green, 0.5)
    love.graphics.rectangle("line", dx, dy, dw, dh, rr, rr)

    love.graphics.setFont(self.slotNameFont)
    col(PAL.white)
    love.graphics.print(Strings("Name save slot"), dx + 16 * s, dy + 14 * s)

    -- the field: bordered strip, current text, blinking caret on the pulse
    local fx, fy = dx + 16 * s, dy + 44 * s
    local fw, fh = dw - 32 * s, 30 * s
    col(PAL.bgBot, 0.9)
    love.graphics.rectangle("fill", fx, fy, fw, fh, 8 * s, 8 * s)
    love.graphics.setLineWidth(math.max(1, s))
    col(PAL.cardBorder, 0.45)
    love.graphics.rectangle("line", fx, fy, fw, fh, 8 * s, 8 * s)
    love.graphics.setFont(self.detailFont)
    col(PAL.heading)
    local shown = ellipsize(self.detailFont, self._rename.text, fw - 20 * s)
    love.graphics.print(shown, fx + 10 * s, fy + (fh - self.detailFont:getHeight()) / 2)
    if (self.pulse * 2 % 1) < 0.5 then
      local cx = fx + 10 * s + self.detailFont:getWidth(shown) + 2 * s
      col(PAL.green)
      love.graphics.rectangle("fill", cx, fy + 6 * s, math.max(1, 1.5 * s),
        fh - 12 * s)
    end

    love.graphics.setFont(self.hintFont)
    col(PAL.detail)
    printfB(Strings("Enter to save - Esc to cancel - empty clears"),
      dx + 16 * s, dy + dh - 30 * s, dw - 32 * s, "left")
  end

  -- "Add an index" prompt: the same field as the rename modal, sized for a URL
  -- and with the caret pinned to the tail so a long one stays readable while
  -- it is typed.
  if self._indexPrompt then
    col(PAL.bgBot, 0.72)
    love.graphics.rectangle("fill", 0, 0, fullW, fullH)
    local dw = math.min(appW - 32 * s, 520 * s)
    local dh = 176 * s
    local dx = appX + (appW - dw) / 2
    local dy = oy + (height - dh) / 2
    local rr = 12 * s
    neonGlow(dx, dy, dw, dh, rr, PAL.modDot, 0.4)
    fillGradRounded(dx, dy, dw, dh, rr, PAL.slotBg, PAL.slotBg, 0.9, 0.9)
    love.graphics.setLineWidth(math.max(1, 1.2 * s))
    col(PAL.modDot, 0.55)
    love.graphics.rectangle("line", dx, dy, dw, dh, rr, rr)

    love.graphics.setFont(self.slotNameFont)
    col(PAL.white)
    love.graphics.print(Strings("Add a mod index"), dx + 16 * s, dy + 14 * s)
    love.graphics.setFont(self.hintFont)
    col(PAL.detail)
    love.graphics.printf(
      Strings("Paste the index URL, or its owner/repo."),
      dx + 16 * s, dy + 40 * s, dw - 32 * s, "left")

    local fx, fy = dx + 16 * s, dy + 66 * s
    local fw, fh = dw - 32 * s, 32 * s
    col(PAL.bgBot, 0.9)
    love.graphics.rectangle("fill", fx, fy, fw, fh, 8 * s, 8 * s)
    love.graphics.setLineWidth(math.max(1, s))
    col(PAL.cardBorder, 0.45)
    love.graphics.rectangle("line", fx, fy, fw, fh, 8 * s, 8 * s)
    love.graphics.setFont(self.hintFont)
    col(PAL.heading)
    -- keep the END of the URL visible: the interesting half is the tail
    local text = self._indexPrompt.text or ""
    local maxW = fw - 20 * s
    local shown = text
    while #shown > 0 and self.hintFont:getWidth(shown) > maxW do
      shown = shown:sub(2)
    end
    love.graphics.print(shown, fx + 10 * s,
      fy + (fh - self.hintFont:getHeight()) / 2)
    if (self.pulse * 2 % 1) < 0.5 then
      col(PAL.modDot)
      love.graphics.rectangle("fill",
        fx + 10 * s + self.hintFont:getWidth(shown) + 2 * s,
        fy + 7 * s, math.max(1, 1.5 * s), fh - 14 * s)
    end

    -- PASTE under the field: a touch screen has no ctrl+V, and an index URL
    -- is not something anyone retypes on a soft keyboard (#578).  This rect
    -- is the one click mousepressed honors while the prompt is up; pinned so
    -- page-scroll banding never eats the tap.
    self._indexPasteRect = self:_chipButton(fx + fw - 84 * s, fy + fh + 8 * s,
      Strings("Paste"), { w = 84 * s, h = 28 * s, kind = "accent" })
    self._indexPasteRect.pinned = true

    love.graphics.setFont(self.hintFont)
    col(PAL.warning)
    printfB(Strings("Enter to add - Esc to cancel"),
      dx + 16 * s, dy + dh - 32 * s, dw - 32 * s, "left")
  end

  -- Mod confirm / versions / release-notes / index-details overlays
  if self._modConfirm or self._modVersions or self._modReleaseNotes
      or self._findDetails then
    col(PAL.bgBot, 0.72)
    love.graphics.rectangle("fill", 0, 0, fullW, fullH)
  end
  if self._modConfirm then
    local c = self._modConfirm
    local dw = math.min(appW - 32 * s, 400 * s)
    local lineH = self.hintFont:getHeight() + 4 * s
    local dh = 36 * s + (#c.lines) * lineH + 56 * s
    local dx = appX + (appW - dw) / 2
    local dy = oy + (height - dh) / 2
    local rr = 12 * s
    fillGradRounded(dx, dy, dw, dh, rr, PAL.slotBg, PAL.slotBg, 0.92, 0.92)
    love.graphics.setLineWidth(math.max(1, 1.2 * s))
    col((c.kind == "update") and PAL.green or PAL.gold, 0.65)
    love.graphics.rectangle("line", dx, dy, dw, dh, rr, rr)
    love.graphics.setFont(self.slotNameFont)
    col(PAL.white)
    love.graphics.printf(c.title or "Confirm", dx + 16 * s, dy + 14 * s,
      dw - 32 * s, "left")
    love.graphics.setFont(self.hintFont)
    col(PAL.detail)
    local ty = dy + 42 * s
    for _, line in ipairs(c.lines) do
      love.graphics.printf(line, dx + 16 * s, ty, dw - 32 * s, "left")
      ty = ty + lineH
    end
    local btnH = 34 * s
    local btnW = (dw - 48 * s) / 2
    local by = dy + dh - btnH - 14 * s
    self._modConfirmYes = { x = dx + 16 * s, y = by, width = btnW, height = btnH }
    self._modConfirmNo = { x = dx + dw - 16 * s - btnW, y = by,
      width = btnW, height = btnH }
    local yhot = self:_hover(self._modConfirmYes)
    local nhot = self:_hover(self._modConfirmNo)
    fillGradRounded(self._modConfirmYes.x, by, btnW, btnH, 8 * s,
      PAL.playTop, PAL.playBot, yhot and 1 or 0.85, yhot and 1 or 0.85)
    col(PAL.disabled, nhot and 0.55 or 0.35)
    love.graphics.rectangle("fill", self._modConfirmNo.x, by, btnW, btnH, 8 * s, 8 * s)
    love.graphics.setFont(self.saveBtnFont)
    col(PAL.white)
    printfB(c.yesLabel or "OK", self._modConfirmYes.x,
      by + (btnH - self.saveBtnFont:getHeight()) / 2, btnW, "center")
    col(PAL.detail)
    printfB("Cancel", self._modConfirmNo.x, by + (btnH - self.saveBtnFont:getHeight()) / 2,
      btnW, "center")
  elseif self._modReleaseNotes then
    local n = self._modReleaseNotes
    local ModUpdate = require("src.mods.ModUpdate")
    local dw = math.min(appW - 32 * s, 480 * s)
    local dh = math.min(height - 48 * s, 360 * s)
    local dx = appX + (appW - dw) / 2
    local dy = oy + (height - dh) / 2
    local rr = 12 * s
    fillGradRounded(dx, dy, dw, dh, rr, PAL.slotBg, PAL.slotBg, 0.92, 0.92)
    love.graphics.setLineWidth(math.max(1, 1.2 * s))
    col(PAL.green, 0.5)
    love.graphics.rectangle("line", dx, dy, dw, dh, rr, rr)
    love.graphics.setFont(self.slotNameFont)
    col(PAL.white)
    love.graphics.printf("v" .. tostring(n.version) .. " notes",
      dx + 16 * s, dy + 12 * s, dw - 32 * s, "left")
    local body = ModUpdate.cleanBody(n.body or "", 0)
    if body == "" then body = "(No release notes.)" end
    love.graphics.setFont(self.hintFont)
    col(PAL.detail)
    local textTop = dy + 44 * s
    local textH = dh - 44 * s - 52 * s
    love.graphics.setScissor(math.floor(dx + 16 * s), math.floor(textTop),
      math.ceil(dw - 32 * s), math.ceil(textH))
    love.graphics.printf(body, dx + 16 * s, textTop - (n.scroll or 0),
      dw - 32 * s, "left")
    love.graphics.setScissor()
    local closeW = self.hintFont:getWidth("Close") + 28 * s
    local closeH = 30 * s
    self._modReleaseNotesClose = {
      x = dx + (dw - closeW) / 2, y = dy + dh - closeH - 12 * s,
      width = closeW, height = closeH,
    }
    local chot = self:_hover(self._modReleaseNotesClose)
    col(PAL.disabled, chot and 0.55 or 0.35)
    love.graphics.rectangle("fill", self._modReleaseNotesClose.x,
      self._modReleaseNotesClose.y, closeW, closeH, 8 * s, 8 * s)
    col(PAL.detail)
    printfB("Close", self._modReleaseNotesClose.x,
      self._modReleaseNotesClose.y + (closeH - self.hintFont:getHeight()) / 2,
      closeW, "center")
  elseif self._findDetails then
    -- The index's description markdown, stripped by the same cleanBody a
    -- release changelog goes through.  There is no markdown renderer in the
    -- engine and a listing does not warrant one: the point is to read what the
    -- author wrote before installing, not to reproduce their formatting.
    local d = self._findDetails
    local ModUpdate = require("src.mods.ModUpdate")
    local dw = math.min(appW - 32 * s, 520 * s)
    local dh = math.min(height - 48 * s, 420 * s)
    local dx = appX + (appW - dw) / 2
    local dy = oy + (height - dh) / 2
    local rr = 12 * s
    fillGradRounded(dx, dy, dw, dh, rr, PAL.slotBg, PAL.slotBg, 0.94, 0.94)
    love.graphics.setLineWidth(math.max(1, 1.2 * s))
    col(PAL.modDot, 0.5)
    love.graphics.rectangle("line", dx, dy, dw, dh, rr, rr)
    love.graphics.setFont(self.slotNameFont)
    col(PAL.white)
    love.graphics.printf(ellipsize(self.slotNameFont, d.title, dw - 32 * s),
      dx + 16 * s, dy + 12 * s, dw - 32 * s, "left")
    local body = ModUpdate.cleanBody(d.body or "", 0)
    if body == "" then body = "(No description.)" end
    love.graphics.setFont(self.hintFont)
    col(PAL.detail)
    local textTop = dy + 44 * s
    local textH = dh - 44 * s - 52 * s
    local _, lines = self.hintFont:getWrap(body, dw - 32 * s)
    local bodyH = #lines * self.hintFont:getHeight()
    d.max = math.max(0, bodyH - textH)
    d.scroll = clamp(d.scroll or 0, 0, d.max)
    love.graphics.setScissor(math.floor(dx + 16 * s), math.floor(textTop),
      math.ceil(dw - 32 * s), math.ceil(textH))
    love.graphics.printf(body, dx + 16 * s, textTop - d.scroll,
      dw - 32 * s, "left")
    love.graphics.setScissor()
    local closeW = self.hintFont:getWidth("Close") + 28 * s
    local closeH = 30 * s
    self._findDetailsClose = {
      x = dx + (dw - closeW) / 2, y = dy + dh - closeH - 12 * s,
      width = closeW, height = closeH,
    }
    local chot = self:_hover(self._findDetailsClose)
    col(PAL.disabled, chot and 0.55 or 0.35)
    love.graphics.rectangle("fill", self._findDetailsClose.x,
      self._findDetailsClose.y, closeW, closeH, 8 * s, 8 * s)
    col(PAL.detail)
    printfB("Close", self._findDetailsClose.x,
      self._findDetailsClose.y + (closeH - self.hintFont:getHeight()) / 2,
      closeW, "center")
  elseif self._modVersions then
    local ModUpdate = require("src.mods.ModUpdate")
    local v = self._modVersions
    local dw = math.min(appW - 40 * s, 520 * s)
    local pad = 16 * s
    local headerH = 56 * s
    local rowH = 52 * s
    local footerH = 48 * s
    local listN = math.min(6, math.max(0, #v.releases))
    local listH = math.max(rowH, listN * rowH)
    local dh = headerH + listH + footerH
    dh = math.min(dh, height - 40 * s)
    -- recompute how many rows fit under the clamped dialog height
    local fitN = math.max(1, math.floor((dh - headerH - footerH) / rowH))
    listN = math.min(listN, fitN)
    listH = listN * rowH
    dh = headerH + listH + footerH
    local dx = appX + (appW - dw) / 2
    local dy = oy + (height - dh) / 2
    local rr = 12 * s
    fillGradRounded(dx, dy, dw, dh, rr, PAL.slotBg, PAL.slotBg, 0.96, 0.96)
    love.graphics.setLineWidth(math.max(1, 1.2 * s))
    col(PAL.green, 0.5)
    love.graphics.rectangle("line", dx, dy, dw, dh, rr, rr)

    love.graphics.setFont(self.slotNameFont)
    col(PAL.white)
    love.graphics.printf("Other versions: " .. tostring(v.name),
      dx + pad, dy + 10 * s, dw - pad * 2, "left")
    love.graphics.setFont(self.hintFont)
    local info = self:_modUpdateInfo(v.id)
    local statusTxt = "Installed: v" .. tostring(v.current)
    local statusCol = PAL.detail
    if info and info.status == "available" then
      statusTxt = statusTxt .. "  -  Update v" .. tostring(info.latest)
      statusCol = PAL.playTop
    elseif info and info.status == "current" then
      statusTxt = statusTxt .. "  -  Up to date"
      statusCol = PAL.playTop
    end
    col(statusCol)
    love.graphics.printf(statusTxt, dx + pad, dy + 34 * s, dw - pad * 2, "left")

    self._modVersionRects = {}
    self._modVersionNotesRects = {}
    local listTop = dy + headerH
    local notesW = self.hintFont:getWidth("Read more") + 20 * s
    local installW = self.hintFont:getWidth("Install") + 20 * s
    local btnH = 26 * s
    -- clip the list to the band above the footer so nothing can paint over Close
    love.graphics.setScissor(math.floor(dx + 2 * s), math.floor(listTop),
      math.ceil(dw - 4 * s), math.ceil(listH))
    for i = 1, listN do
      local rel = v.releases[i]
      local ly = listTop + (i - 1) * rowH
      local rect = { x = dx + 12 * s, y = ly + 2 * s, width = dw - 24 * s,
        height = rowH - 6 * s, release = rel }
      col(PAL.bgBot, 0.45)
      love.graphics.rectangle("fill", rect.x, rect.y, rect.width, rect.height, 8 * s, 8 * s)
      love.graphics.setLineWidth(1)
      col(PAL.cardBorder, 0.35)
      love.graphics.rectangle("line", rect.x, rect.y, rect.width, rect.height, 8 * s, 8 * s)

      love.graphics.setFont(self.hintFont)
      local label = "v" .. rel.version
      if rel.version == v.current then label = label .. " (installed)" end
      if rel.prerelease then label = label .. " pre" end
      col(rel.version == v.current and PAL.warning or PAL.white)
      love.graphics.print(label, rect.x + 12 * s, rect.y + 6 * s)

      -- one-line ellipsized preview only (never wrap changelog into the row)
      local btnStackW = 0
      local hasNotes = type(rel.body) == "string" and rel.body:match("%S")
      local canInstall = rel.version ~= v.current
      if hasNotes then btnStackW = btnStackW + notesW end
      if canInstall then btnStackW = btnStackW + (hasNotes and 8 * s or 0) + installW end
      local previewW = math.max(24 * s, rect.width - 24 * s - btnStackW - 12 * s)
      local preview = ModUpdate.previewLine(rel.body or "", 90)
      if preview ~= "" then
        col(PAL.detail)
        love.graphics.print(
          ellipsize(self.hintFont, preview, previewW),
          rect.x + 12 * s,
          rect.y + 6 * s + self.hintFont:getHeight() + 2 * s)
      end

      local btnY = rect.y + (rect.height - btnH) / 2
      local bx = rect.x + rect.width - 10 * s
      if canInstall then
        bx = bx - installW
        local irect = self:_chipButton(bx, btnY, "Install", {
          w = installW, h = btnH, id = v.id, kind = "accent",
        })
        irect.release = rel
        self._modVersionRects[#self._modVersionRects + 1] = irect
        bx = bx - 8 * s
      end
      if hasNotes then
        bx = bx - notesW
        local nrect = self:_chipButton(bx, btnY, "Read more", {
          w = notesW, h = btnH, id = v.id, kind = "neutral",
        })
        nrect.release = rel
        self._modVersionNotesRects[#self._modVersionNotesRects + 1] = nrect
      end
    end
    love.graphics.setScissor()

    -- opaque footer so list content can never bleed under Close
    local footerY = dy + dh - footerH
    col(PAL.slotBg, 1)
    love.graphics.rectangle("fill", dx + 2 * s, footerY, dw - 4 * s, footerH - 2 * s)
    local closeW = self.hintFont:getWidth("Close") + 32 * s
    local closeH = 32 * s
    self._modVersionsClose = {
      x = dx + (dw - closeW) / 2,
      y = footerY + (footerH - closeH) / 2 - 2 * s,
      width = closeW, height = closeH,
    }
    local chot = self:_hover(self._modVersionsClose)
    col(PAL.disabled, chot and 0.55 or 0.35)
    love.graphics.rectangle("fill", self._modVersionsClose.x,
      self._modVersionsClose.y, closeW, closeH, 8 * s, 8 * s)
    love.graphics.setFont(self.hintFont)
    col(PAL.detail)
    printfB("Close", self._modVersionsClose.x,
      self._modVersionsClose.y + (closeH - self.hintFont:getHeight()) / 2,
      closeW, "center")
  end

  -- pointer cursor over any interactive element (desktop only)
  if self._hoverEnabled and not self._padCursorActive
      and love.mouse.isCursorSupported and love.mouse.isCursorSupported() then
    if self._anyHover then
      if not self.handCursor then
        local ok, cursor = pcall(love.mouse.getSystemCursor, "hand")
        if ok then self.handCursor = cursor end
      end
      if self.handCursor then love.mouse.setCursor(self.handCursor) end
    else
      resetPointerCursor(self)
    end
  end

  -- Gamepad virtual cursor (drawn last so it sits above the CRT overlay).
  if self._padCursorActive then
    local x, y = self._padCursor.x, self._padCursor.y
    local hot = self._anyHover
    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setLineWidth(1)
    -- Drop shadow
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.polygon("fill",
      x + 2, y + 2, x + 2, y + 22, x + 8, y + 16, x + 14, y + 26,
      x + 18, y + 24, x + 11, y + 14, x + 20, y + 14)
    -- Pointer body
    if hot then
      love.graphics.setColor(0.25, 0.95, 0.55, 1)
    else
      love.graphics.setColor(1, 1, 1, 1)
    end
    love.graphics.polygon("fill",
      x, y, x, y + 20, x + 6, y + 14, x + 12, y + 24,
      x + 16, y + 22, x + 9, y + 12, x + 18, y + 12)
    love.graphics.setColor(0.05, 0.07, 0.12, 1)
    love.graphics.polygon("line",
      x, y, x, y + 20, x + 6, y + 14, x + 12, y + 24,
      x + 16, y + 22, x + 9, y + 12, x + 18, y + 12)
    love.graphics.pop()
  end
end

local function inside(r, x, y)
  if not (r and x >= r.x and x <= r.x + r.width and y >= r.y and y <= r.y + r.height) then
    return false
  end
  -- Page-scroll mode: only the header is pinned, so any other rect is a
  -- scrolled one and is live only where the viewport actually shows it.
  if pageBand and not r.pinned and (y < pageBand[1] or y > pageBand[2]) then
    return false
  end
  return true
end

-- A Delete label is armed by one click and commits on a second one on the same
-- target; it disarms on any other press and after this many seconds, because
-- nothing in the launcher can undo a delete (#433).
local DELETE_CONFIRM_SECONDS = 4

local function armedDelete(a, kind, id, version)
  return a ~= nil and a.kind == kind and a.id == id and a.version == version
    and (love.timer.getTime() - a.t) <= DELETE_CONFIRM_SECONDS
end

function RomImporter:mousepressed(x, y, button)
  if self._rename then return end -- the rename modal swallows all clicks
  -- The add-index prompt swallows clicks too, except its PASTE button: a
  -- touch screen has no ctrl+V, so the button is the only paste path (#578).
  if self._indexPrompt then
    if button == 1 and inside(self._indexPasteRect, x, y) then
      self:_pasteIndexUrl()
    end
    return
  end
  -- Mod confirm / versions / release-notes modals swallow clicks too.
  if self._modConfirm then
    if button ~= 1 then return end
    if inside(self._modConfirmYes, x, y) then
      local c = self._modConfirm
      self._modConfirm = nil
      -- An index install carries its whole entry: the confirm is the only
      -- place the compatibility warnings were shown, so the install must not
      -- be reachable by any other route.
      if c.indexEntry then
        self:_findInstall(c.indexEntry)
      elseif c.kind == "update" then
        self:_confirmModUpdate(c.id, c.release)
      elseif c.kind == "enableAll" then
        self:_setAllMods(true, true)
      else
        self:_toggleMod(c.id, true)
      end
    elseif inside(self._modConfirmNo, x, y) then
      self._modConfirm = nil
    end
    return
  end
  if self._modReleaseNotes then
    if button ~= 1 then return end
    if inside(self._modReleaseNotesClose, x, y) then
      self._modReleaseNotes = nil
    end
    return
  end
  if self._findDetails then
    if button ~= 1 then return end
    if inside(self._findDetailsClose, x, y) then
      self._findDetails = nil
    end
    return
  end
  if self._modVersions then
    if button ~= 1 then return end
    if inside(self._modVersionsClose, x, y) then
      self._modVersions = nil
      return
    end
    for _, r in ipairs(self._modVersionNotesRects or {}) do
      if inside(r, x, y) and r.release then
        self._modReleaseNotes = {
          version = r.release.version,
          body = r.release.body or "",
          scroll = 0,
        }
        return
      end
    end
    for _, r in ipairs(self._modVersionRects or {}) do
      if inside(r, x, y) and r.release then
        self:_installModVersion(self._modVersions.id, r.release)
        return
      end
    end
    return
  end
  -- Whether a press can be ARMED and resolved on release, which needs a
  -- pollable pointer: always on desktop, on Android only where love.touch is.
  local armDrag = (not self.android) or self.touchPollable
  -- right-click a save-slot row to rename it (#205); desktop only (touch
  -- has no secondary button)
  if button == 2 then
    if not self.android and self.workState ~= "working" then
      for _, r in ipairs(self.slotRects or {}) do
        if inside(r, x, y) then
          self:_beginRename(self.panelVersion, r.id)
          return
        end
      end
    end
    return
  end
  if button ~= 1 then return end
  -- Any press that is not the second click on an armed Delete disarms it, so
  -- take the arm off self up front and let the Delete loops below re-arm.
  local armed = self._confirmDelete
  self._confirmDelete = nil
  if inside(self.bcgButton, x, y) or inside(self.linkUrlRect, x, y) then
    love.system.openURL(COMMUNITY_URL)
    return
  end
  -- Self-updater banner (touch routes here through love.touchpressed too).
  -- Kept ahead of the "working" guard so it stays live during a ROM import.
  if inside(self.updateButton, x, y) then
    local action = self.updateButton.action
    if action == "download" and self.Check then
      pcall(self.Check.download)
    elseif action == "restart" then
      HostShell.restart()
    elseif action == "openurl" and self.Check then
      love.system.openURL(self.Check.releaseUrl())
    end
    return
  end
  -- Tab chips switch panels even mid-import so the player can look around
  -- while a ROM extracts.
  for _, t in ipairs(self.tabRects or {}) do
    if inside(t, x, y) then
      self.tab = t.id
      self._slotPress = nil   -- drop any half-started slot drag on tab change
      self._modPress = nil    -- and any half-started mod toggle press
      self._pagePress = nil   -- and any half-started page pan
      self._findSearchFocus = false  -- and the search caret, now off screen
      self:_disarmTextInput()
      -- Each tab is its own column of a different length; carrying one tab's
      -- offset into another lands somewhere arbitrary.
      self.pageScroll = 0
      return
    end
  end
  if self.workState == "working" then return end
  -- Active game panel's controls (only the shown version has live hit rects).
  if inside(self.playButtonRect, x, y) then
    self:play(self.panelVersion); return
  end
  if inside(self.romButtonRect, x, y) then
    local version = self.panelVersion
    if self.ready[version] then self:reimport(version) else self:choose(version) end
    return
  end
  -- SAVE FILES card: Import save / Export save, and the open-folder affordance
  -- shown on the notice line after a successful export.
  if inside(self.saveImportRect, x, y) then
    self:chooseSaveImport(self.panelVersion); return
  end
  if inside(self.saveExportRect, x, y) then
    self:exportSave(self.panelVersion); return
  end
  if inside(self.saveFolderRect, x, y) then
    if self.saveFolderRect.dir then
      love.system.openURL(fileUrl(self.saveFolderRect.dir))
    end
    return
  end
  if inside(self.touchControlsRect, x, y) then
    if self.onEditTouchControls then self.onEditTouchControls() end
    return
  end
  -- SAVE SLOT rows / Edit / Delete.  The two labels are checked first so a tap
  -- on either never also selects the row.  A press only ARMS a row click:
  -- _updateSlotDrag commits it on release when the pointer did not move (a
  -- moved pointer scrolls instead).  Android arms too wherever love.touch can
  -- be polled; without that there is nothing to resolve a release with, so it
  -- keeps selecting on press.  Edit and Delete fire immediately (small fixed
  -- targets, no scroll conflict).
  for _, r in ipairs(self.slotDeleteRects or {}) do
    if inside(r, x, y) then
      if armedDelete(armed, "slot", r.id, self.panelVersion) then
        self:_deleteSlot(self.panelVersion, r.id)
      else
        self._confirmDelete = { kind = "slot", id = r.id,
          version = self.panelVersion, t = love.timer.getTime() }
      end
      return
    end
  end
  for _, r in ipairs(self.slotEditRects or {}) do
    if inside(r, x, y) then
      if self.onEditSave then self.onEditSave(self.panelVersion, r.id) end
      return
    end
  end
  for _, r in ipairs(self.slotRects or {}) do
    if inside(r, x, y) then
      if not armDrag then
        self:_selectSlot(self.panelVersion, r.id)
      else
        self._slotPress = { version = self.panelVersion, id = r.id, y0 = y,
          scroll0 = self.slotScroll[self.panelVersion] or 0,
          pageScroll0 = self.pageScroll or 0, moved = false }
      end
      return
    end
  end
  if inside(self.newSlotRect, x, y) then
    self:_newSlot(self.panelVersion); return
  end
  -- Mods panel: the import button dispatches on press (fixed header, no scroll
  -- conflict); Delete fires immediately; a toggle switch, which lives in the
  -- scrollable list, only ARMS a press so _updateSlotDrag can tell a click from
  -- a drag-scroll (Android, with no pointer polling, toggles on press).
  if inside(self.modImportRect, x, y) then
    self:chooseMod(); return
  end
  -- Enable all / Disable all sit in that same fixed header, so they dispatch on
  -- press like the import button rather than arming a drag (#647).
  if inside(self.modEnableAllRect, x, y) then
    self:_setAllMods(true); return
  end
  if inside(self.modDisableAllRect, x, y) then
    self:_setAllMods(false); return
  end
  for _, r in ipairs(self.modDeleteRects or {}) do
    if inside(r, x, y) then
      if armedDelete(armed, "mod", r.id, nil) then
        self:_deleteMod(r.id)
      else
        self._confirmDelete = { kind = "mod", id = r.id, t = love.timer.getTime() }
      end
      return
    end
  end
  for _, r in ipairs(self.modUpdateRects or {}) do
    if inside(r, x, y) then
      self:_modGithubAction(r.id, "update")
      return
    end
  end
  for _, r in ipairs(self.modVersionsRects or {}) do
    if inside(r, x, y) then
      self:_modGithubAction(r.id, "versions")
      return
    end
  end
  for _, r in ipairs(self.modRects or {}) do
    if inside(r, x, y) then
      if not armDrag then
        self:_toggleMod(r.id)
      else
        self._modPress = { id = r.id, y0 = y, scroll0 = self.modScroll or 0,
          pageScroll0 = self.pageScroll or 0, moved = false }
      end
      return
    end
  end
  -- FIND MODS panel.  Everything here dispatches on press: none of it is a
  -- toggle that a drag-scroll could be mistaken for, and the search field wants
  -- focus the instant it is touched.
  if inside(self.findAddRect, x, y) then
    self:_promptAddIndex(); return
  end
  if inside(self.findRefreshRect, x, y) then
    self._findSearchFocus = false
    self:_disarmTextInput()
    self:_refreshFind(true)
    return
  end
  if inside(self.findSearchRect, x, y) then
    self._findSearchFocus = true
    self:_armTextInput()
    return
  end
  for _, r in ipairs(self.findSourceRemoveRects or {}) do
    if inside(r, x, y) then self:_removeIndex(r.id); return end
  end
  for _, r in ipairs(self.findCatRects or {}) do
    if inside(r, x, y) then
      -- the "All" chip carries the empty id; every other chip toggles itself
      -- off when it is already the filter, so a second tap is the way back
      self.findCategory = (r.id ~= "" and self.findCategory ~= r.id) and r.id or nil
      self.findScroll = 0
      return
    end
  end
  for _, r in ipairs(self.findDetailRects or {}) do
    if inside(r, x, y) and r.entry then self:_findShowDetails(r.entry); return end
  end
  for _, r in ipairs(self.findRepoRects or {}) do
    if inside(r, x, y) and r.entry and r.entry.repo then
      love.system.openURL(r.entry.repo)
      return
    end
  end
  for _, r in ipairs(self.findInstallRects or {}) do
    if inside(r, x, y) and r.entry then self:_findConfirmInstall(r.entry); return end
  end
  -- A press anywhere else on the tab drops the search caret, so the field does
  -- not silently keep eating keystrokes once the player has moved on.
  if self.tab == "find" and self._findSearchFocus then
    self._findSearchFocus = false
    self:_disarmTextInput()
  end
  -- Nothing was hit.  On a scrolling page that is a press on empty background,
  -- which is the natural place to grab and pan from.
  if armDrag and (self._pageMax or 0) > 0 then
    self._pagePress = { y0 = y, scroll0 = self.pageScroll or 0 }
  end
end

function RomImporter:keypressed(key)
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
      if self.ready[version] then self:play(version) else self:choose(version) end
    end
  end
end

-- ------- Redesign panel rendering (FirstRun.dc.html) ------------------------
-- These run inside draw(): they read the per-frame pointer through self:_hover
-- and self._s, and set the hit rects mousepressed dispatches (self.tabRects,
-- self.romButtonRect, self.playButtonRect, self.panelVersion).

function RomImporter:_ptIn(r)
  local mx, my = self._mx, self._my
  if not (r and mx >= r.x and mx <= r.x + r.width and my >= r.y and my <= r.y + r.height) then
    return false
  end
  -- Same clip the click path applies, so nothing glows outside the viewport.
  if pageBand and not r.pinned and (my < pageBand[1] or my > pageBand[2]) then
    return false
  end
  return true
end

function RomImporter:_hover(r)
  local hot = self._hoverEnabled and self:_ptIn(r) or false
  if hot then self._anyHover = true end
  return hot
end

-- A glassy white-on-dark button (ROM import + the disabled SAVE FILES pair).
-- Returns its hit rect when live, or nil when disabled (inert).
function RomImporter:_glassyButton(x, y, w, h, label, font, enabled)
  local s = self._s
  local r = 10 * s
  love.graphics.setFont(font)
  if enabled == false then
    col(PAL.disabled, 0.25)
    love.graphics.rectangle("fill", x, y, w, h, r, r)
    love.graphics.setLineWidth(1)
    col(PAL.disabledInk, 0.3)
    love.graphics.rectangle("line", x, y, w, h, r, r)
    col(PAL.disabledInk)
    printfB(label, x, y + (h - font:getHeight()) / 2, w, "center")
    return nil
  end
  local rect = { x = x, y = y, width = w, height = h }
  local hot = self:_hover(rect)
  fillGradRounded(x, y, w, h, r, PAL.white, PAL.white, hot and 0.24 or 0.16, 0.04)
  love.graphics.setLineWidth(1)
  col(PAL.white, 0.18)
  love.graphics.rectangle("line", x, y, w, h, r, r)
  col(PAL.white)
  printfB(label, x, y + (h - font:getHeight()) / 2, w, "center")
  return rect
end

-- Compact pill button for row actions (Edit / Delete / Update / Versions).
-- kind: "neutral" (default), "accent" (green), "danger" (red), "dangerArmed"
-- (filled confirm). Returns the hit rect; opts.id is copied onto it.
function RomImporter:_chipButton(x, y, label, opts)
  opts = opts or {}
  local s = self._s
  local font = opts.font or self.hintFont
  local padX = opts.padX or (12 * s)
  local h = opts.h or (font:getHeight() + 10 * s)
  love.graphics.setFont(font)
  local w = opts.w or (font:getWidth(label) + 2 * padX)
  local r = opts.r or math.min(8 * s, h / 2)
  local kind = opts.kind or "neutral"
  local rect = { x = x, y = y, width = w, height = h, id = opts.id }
  local hot = self:_hover(rect)

  if kind == "dangerArmed" then
    fillGradRounded(x, y, w, h, r, PAL.chooseTop, PAL.chooseBot,
      hot and 1 or 0.92, hot and 1 or 0.92)
    col(PAL.white)
  elseif kind == "danger" then
    col(PAL.chooseTop, hot and 0.28 or 0.14)
    love.graphics.rectangle("fill", x, y, w, h, r, r)
    love.graphics.setLineWidth(math.max(1, s))
    col(PAL.chooseTop, hot and 0.95 or 0.7)
    love.graphics.rectangle("line", x, y, w, h, r, r)
    col(hot and PAL.white or PAL.chooseTop)
  elseif kind == "accent" then
    col(PAL.playTop, hot and 0.28 or 0.12)
    love.graphics.rectangle("fill", x, y, w, h, r, r)
    love.graphics.setLineWidth(math.max(1, s))
    col(PAL.playTop, hot and 0.95 or 0.65)
    love.graphics.rectangle("line", x, y, w, h, r, r)
    col(hot and PAL.white or PAL.playTop)
  else
    fillGradRounded(x, y, w, h, r, PAL.white, PAL.white,
      hot and 0.22 or 0.12, 0.04)
    love.graphics.setLineWidth(math.max(1, s))
    col(PAL.white, hot and 0.35 or 0.18)
    love.graphics.rectangle("line", x, y, w, h, r, r)
    col(PAL.white)
  end
  printfB(label, x, y + (h - font:getHeight()) / 2, w, "center")
  return rect
end

-- The tall green Play button (ready) or a disabled placeholder.  Sets
-- self.playButtonRect.
function RomImporter:_playButton(x, y, w, h, gameName, ready, locked)
  local s, pulse = self._s, self.pulse
  local r = 12 * s
  love.graphics.setFont(self.playFont)
  if ready then
    local rect = { x = x, y = y, width = w, height = h }
    local hot = self:_hover(rect)
    local g = 0.5 + 0.5 * math.sin(pulse * 2 * math.pi / 2.4)
    neonGlow(x, y, w, h, r, PAL.playTop, (0.7 + 0.25 * g) * (hot and 1.6 or 1))
    fillGradRounded(x, y, w, h, r, PAL.playTop, PAL.playBot, 1, 1)
    if hot then
      love.graphics.setBlendMode("add")
      love.graphics.setColor(1, 1, 1, 0.12)
      love.graphics.rectangle("fill", x, y, w, h, r, r)
      love.graphics.setBlendMode("alpha")
    end
    buttonShine(x, y, w, h, r, (pulse % 2.8) / 2.8)
    local label = "Play " .. gameName
    local tw = self.playFont:getWidth(label)
    local tri = self.playFont:getHeight() * 0.55
    local groupW = tri + 12 * s + tw
    local gx = x + (w - groupW) / 2
    local gy = y + h / 2
    col(PAL.playInk)
    love.graphics.polygon("fill", gx, gy - tri / 2, gx, gy + tri / 2, gx + tri * 0.9, gy)
    printB(label, gx + tri + 12 * s, y + (h - self.playFont:getHeight()) / 2)
    self.playButtonRect = rect
  else
    col(PAL.disabled, 0.3)
    love.graphics.rectangle("fill", x, y, w, h, r, r)
    love.graphics.setLineWidth(1)
    col(PAL.disabledInk, 0.3)
    love.graphics.rectangle("line", x, y, w, h, r, r)
    col(PAL.disabledInk)
    local label = locked and "Coming soon" or Strings("Import a ROM to play")
    printfB(label, x, y + (h - self.playFont:getHeight()) / 2, w, "center")
    self.playButtonRect = nil
  end
end

-- The R/B/Y/divider/MODS chip row.  Only the active tab shows its label +
-- underline; the rest are dimmed.  Rebuilds self.tabRects (chip squares).
function RomImporter:_drawTabBar(x, y, w, h, chip)
  local s, pulse = self._s, self.pulse
  local tabs = {
    { id = "red",    letter = "R", top = PAL.chipRedTop,  bot = PAL.chipRedBot,
      under = PAL.red,    label = Strings("RED"),    ink = PAL.white },
    { id = "blue",   letter = "B", top = PAL.chipBlueTop, bot = PAL.chipBlueBot,
      under = PAL.blue,   label = Strings("BLUE"),   ink = PAL.white },
    { id = "yellow", letter = "Y", top = PAL.chipGoldTop, bot = PAL.chipGoldBot,
      under = PAL.gold,   label = Strings("YELLOW"), ink = PAL.chipInkGold },
    { id = "mods",   mods = true,  top = PAL.chipModTop,  bot = PAL.chipModBot,
      under = PAL.modDot, label = Strings("MODS") },
    -- Browsing a community index sits beside the installed list rather than
    -- inside it: one answers "what do I have", the other "what is out there",
    -- and the second is empty until the player adds an index of their own.
    { id = "find",   find = true,  top = PAL.chipModTop,  bot = PAL.chipModBot,
      under = PAL.modDot, label = Strings("FIND MODS") },
  }
  local gap = 10 * s
  local r = 12 * s
  local chipY = y + (h - chip) / 2 - 2 * s
  local underY = y + h - 3 * s
  local cursorX = x
  for _, t in ipairs(tabs) do
    if t.mods then
      -- divider between the game chips and MODS
      col(PAL.cardBorder, 0.25)
      love.graphics.rectangle("fill", cursorX, y + (h - 34 * s) / 2,
        math.max(1, 1 * s), 34 * s)
      cursorX = cursorX + gap + 6 * s
    end
    local active = self.tab == t.id
    -- chip body
    fillGradRounded(cursorX, chipY, chip, chip, r, t.top, t.bot, 1, 1)
    if t.mods then
      local d = 5 * s
      local gd = 3 * s
      local grid = 3 * d + 2 * gd
      local gx = cursorX + (chip - grid) / 2
      local gy = chipY + (chip - grid) / 2
      col(PAL.modDot)
      for row = 0, 2 do
        for c2 = 0, 2 do
          love.graphics.rectangle("fill", gx + c2 * (d + gd), gy + row * (d + gd), d, d)
        end
      end
    elseif t.find then
      -- magnifier: a ring plus a handle running down-right out of it
      local cr = chip * 0.20
      local ccx = cursorX + chip / 2 - cr * 0.35
      local ccy = chipY + chip / 2 - cr * 0.35
      col(PAL.modDot)
      love.graphics.setLineWidth(math.max(1.5, 2 * s))
      love.graphics.circle("line", ccx, ccy, cr)
      local d = cr * 0.72
      love.graphics.line(ccx + d, ccy + d, ccx + d + cr * 0.9, ccy + d + cr * 0.9)
      love.graphics.setLineWidth(1)
    else
      love.graphics.setFont(self.chipFont)
      col(t.ink)
      printfB(t.letter, cursorX, chipY + (chip - self.chipFont:getHeight()) / 2, chip, "center")
    end
    if not active then
      col(PAL.bgBot, 0.62)
      love.graphics.rectangle("fill", cursorX, chipY, chip, chip, r, r)
    end
    -- pinned: the tab bar never scrolls, so it stays live above the viewport
    self.tabRects[#self.tabRects + 1] =
      { x = cursorX, y = chipY, width = chip, height = chip, id = t.id, pinned = true }
    local segEnd = cursorX + chip
    if active then
      love.graphics.setFont(self.tabLabelFont)
      col(PAL.white)
      local labelX = cursorX + chip + gap
      local lw = printSpaced(self.tabLabelFont, t.label, labelX,
        y + (h - self.tabLabelFont:getHeight()) / 2, 2 * s)
      segEnd = labelX + lw
      neonGlow(cursorX, underY, segEnd - cursorX, 3 * s, 2 * s, t.under, 0.45)
      col(t.under)
      love.graphics.rectangle("fill", cursorX, underY, segEnd - cursorX, 3 * s)
    end
    cursorX = segEnd + gap
  end
  -- "N of 3 ready" (Red + Blue + Yellow once in GameVersion.ORDER)
  local ready = 0
  for _, v in ipairs(GameVersion.ORDER) do if self.ready[v] then ready = ready + 1 end end
  love.graphics.setFont(self.readyFont)
  local label = Strings("%d of 3 ready", ready)
  local lw = self.readyFont:getWidth(label)
  if x + w - lw > cursorX + 8 * s then
    col(PAL.labelGray)
    love.graphics.print(label, x + w - lw, y + h - self.readyFont:getHeight() - 6 * s)
  end
  love.graphics.setLineWidth(1)
  col(PAL.cardBorder, 0.22)
  love.graphics.line(x, y + h, x + w, y + h)
end

-- One version's game panel: header (name + status pill), then a responsive
-- two-column grid (left: ROM + SAVE FILES cards + Play; right: SAVE SLOT).
-- `paged`: the whole page is scrolling (see draw()), so nothing stretches to
-- fill `h` -- Play sits right under the SAVE FILES card instead of being pinned
-- to the column bottom, and the slot card takes its natural height.  Returns
-- the panel's natural height either way, which is what draw() measures the page
-- against on the next frame.
function RomImporter:_drawGamePanel(version, x, y, w, h, paged)
  local s, pulse = self._s, self.pulse
  self.panelVersion = version
  -- Defensive: only lock when the version is absent from GameVersion (never
  -- solely because id == "yellow").
  local info = GameVersion.info(version)
  local locked = info == nil
  local gameName = info and (info.launcherName or info.displayName)
                   or tostring(version)
  local ready = (not locked) and self.ready[version] or false

  -- header: name + status pill
  love.graphics.setFont(self.gameNameFont)
  col(PAL.white)
  printB(gameName, x, y)
  local nameW = self.gameNameFont:getWidth(gameName)
  local pill
  if ready then pill = { text = "GOOD TO GO", c = PAL.green }
  elseif locked then pill = { text = "COMING SOON", c = PAL.disabledInk }
  else pill = { text = "ROM REQUIRED", c = PAL.gold } end
  love.graphics.setFont(self.pillFont)
  local pw = self.pillFont:getWidth(pill.text) + 24 * s
  local ph = self.pillFont:getHeight() + 8 * s
  local px = x + nameW + 14 * s
  local py = y + (self.gameNameFont:getHeight() - ph) / 2
  col(pill.c, 0.1)
  love.graphics.rectangle("fill", px, py, pw, ph, ph / 2, ph / 2)
  love.graphics.setLineWidth(1)
  col(pill.c, 0.55)
  love.graphics.rectangle("line", px, py, pw, ph, ph / 2, ph / 2)
  col(pill.c)
  printfB(pill.text, px, py + (ph - self.pillFont:getHeight()) / 2, pw, "center")

  local headerH = math.max(self.gameNameFont:getHeight(), ph)
  local bodyTop = y + headerH + 14 * s
  local bodyH = math.max(0, (y + h) - bodyTop)

  -- responsive grid: two columns when they comfortably fit, else stacked
  local colGap = 18 * s
  local twoCol = w >= (300 * s * 2 + colGap)
  local colW = twoCol and (w - colGap) / 2 or w
  local leftX = x
  local rightX = twoCol and (x + colW + colGap) or x

  -- ROM card contents by state (rehomes the existing import flow)
  local dropHint = self.android and "Copy the .gb/.gbc via USB."
    or Strings("Or drop the .gb/.gbc file here.")
  local accent = version == "yellow" and PAL.gold
    or (version == "red" and PAL.red or PAL.blue)
  local romState, romDetail, romBtnLabel, romBtnEnabled, romProgress
  if locked then
    romState, romDetail = "Not supported yet", "Support for this game is on the way."
    romBtnLabel, romBtnEnabled = "Import unavailable", false
  else
    local importing = self.importing == version
    local erroring = self.workState == "error" and self.errorVersion == version
    local notice = self.notice and self.notice.version == version and self.notice
    if importing and (self.workState == "working" or self.workState == "complete") then
      romState = self.status or "Importing"
      romDetail = self.detail or ""
      romProgress = self.progress or 0
    elseif ready then
      romState = self.romName[version] or Strings("ROM imported")
      romDetail = "Verified."
      romBtnLabel, romBtnEnabled = "Re-import ROM", true
    elseif erroring then
      romState = "Import failed"
      romDetail = self.detail or Strings("That ROM could not be imported.")
      romBtnLabel, romBtnEnabled = "Import ROM", true
    elseif notice then
      romState = "No ROM imported"
      romDetail = trim((notice.status or "") .. " " .. (notice.detail or ""))
      romBtnLabel, romBtnEnabled = "Import ROM", true
    elseif self.returning[version] then
      romState = "Update required"
      romDetail = "This build needs a few more things from your "
        .. info.label .. " ROM. Re-import to continue."
      romBtnLabel, romBtnEnabled = "Re-import ROM", true
    else
      romState = "No ROM imported"
      romDetail = "The ROM is verified before any files are created. " .. dropHint
      romBtnLabel, romBtnEnabled = "Import ROM", true
    end
  end

  -- card metrics
  local pad = 16 * s
  local innerW = colW - 2 * pad
  local labelH = self.labelFont:getHeight()
  love.graphics.setFont(self.stateFont)
  local _, stl = self.stateFont:getWrap(romState, innerW)
  local stateH = math.max(1, #stl) * self.stateFont:getHeight()
  love.graphics.setFont(self.hintFont)
  local _, dtl = self.hintFont:getWrap(romDetail, innerW)
  local detailH = math.max(1, #dtl) * self.hintFont:getHeight()
  local btnH = math.max(40 * s, self.saveBtnFont:getHeight() + 22 * s)
  local romCardH = pad + labelH + 10 * s + stateH + 5 * s + detailH + 14 * s + btnH + pad

  -- SAVE FILES card: Import save is live once the ROM is imported (playable);
  -- Export save is live only when the active slot actually holds a save.  The
  -- hint line doubles as the last import/export outcome (green ok / red error).
  local sfImportEnabled, sfExportEnabled = false, false
  if not locked then
    self:_ensureSlots(version)
    sfImportEnabled = ready and true or false
    local activeId = self.activeSlot[version]
    for _, sl in ipairs(self.slots[version] or {}) do
      if sl.id == activeId and sl.exists then sfExportEnabled = true; break end
    end
  end
  local sfNotice = (not locked) and self.saveNotice[version] or nil
  local sfHintText, sfHintCol
  if sfNotice then
    sfHintText, sfHintCol = sfNotice.text, (sfNotice.ok and PAL.green or PAL.red)
  elseif locked then
    sfHintText, sfHintCol = "Not available yet.", PAL.warning
  elseif self.android then
    sfHintText, sfHintCol =
      "Import or export a .sav with the system file picker.", PAL.warning
  else
    sfHintText, sfHintCol =
      "Import a .sav to a new slot, or export the active slot.", PAL.warning
  end

  local sfBtnH = math.max(38 * s, self.saveBtnFont:getHeight() + 20 * s)
  love.graphics.setFont(self.hintFont)
  local _, sfHl = self.hintFont:getWrap(sfHintText, innerW)
  local sfHintH = math.max(1, #sfHl) * self.hintFont:getHeight()
  local sfFolderH = (sfNotice and sfNotice.dir) and (self.hintFont:getHeight() + 4 * s) or 0
  local saveFilesH = pad + labelH + 10 * s + sfBtnH + 6 * s + sfHintH + sfFolderH + pad
  local playH = math.max(50 * s, self.playFont:getHeight() + 30 * s)
  -- Touch Controls editor entry (layout + permanent disable).  Drawn whenever
  -- the host supplied onEditTouchControls; height reserved only then so a
  -- scripted/headless importer without the callback stays compact.
  local touchBtnH = self.onEditTouchControls
    and math.max(38 * s, self.saveBtnFont:getHeight() + 20 * s) or 0
  local touchGap = self.onEditTouchControls and (12 * s) or 0

  -- vertical placement of the left column
  local romY = bodyTop
  local saveFilesY = romY + romCardH + 12 * s
  local leftNaturalH = romCardH + 12 * s + saveFilesH + touchGap + touchBtnH
    + 12 * s + playH
  local playY, touchY
  if twoCol and not paged then
    -- Play pinned to the column bottom; Touch Controls sits just above it
    playY = bodyTop + bodyH - playH
    touchY = playY - touchGap - touchBtnH
  else
    touchY = saveFilesY + saveFilesH + touchGap
    playY = touchY + touchBtnH + 12 * s
  end

  -- ROM card
  roundedCard(leftX, romY, colW, romCardH, 16 * s)
  local ix, iy = leftX + pad, romY + pad
  love.graphics.setFont(self.labelFont)
  col(PAL.labelGray)
  printSpaced(self.labelFont, "ROM", ix, iy, 2 * s)
  iy = iy + labelH + 10 * s
  love.graphics.setFont(self.stateFont)
  col(PAL.white)
  printfB(romState, ix, iy, innerW, "left")
  iy = iy + stateH + 5 * s
  love.graphics.setFont(self.hintFont)
  col(PAL.detail)
  love.graphics.printf(romDetail, ix, iy, innerW, "left")
  iy = iy + detailH + 14 * s
  if romProgress ~= nil then
    local barH = math.max(8, 10 * s)
    local track = iy + (btnH - barH) / 2
    col(PAL.bgBot, 0.85)
    love.graphics.rectangle("fill", ix, track, innerW, barH, barH / 2, barH / 2)
    local pw2 = innerW * clamp(romProgress, 0, 1)
    if pw2 > barH then
      neonGlow(ix, track, pw2, barH, barH / 2, accent, 0.6)
      col(accent)
      love.graphics.rectangle("fill", ix, track, pw2, barH, barH / 2, barH / 2)
    end
  else
    self.romButtonRect =
      self:_glassyButton(ix, iy, innerW, btnH, romBtnLabel, self.saveBtnFont, romBtnEnabled)
  end

  -- SAVE FILES card: Import save (new slot) + Export save (active slot), with an
  -- outcome/hint line under them and an open-folder affordance after an export.
  roundedCard(leftX, saveFilesY, colW, saveFilesH, 16 * s)
  ix, iy = leftX + pad, saveFilesY + pad
  love.graphics.setFont(self.labelFont)
  col(PAL.labelGray)
  printSpaced(self.labelFont, "SAVE FILES", ix, iy, 2 * s)
  iy = iy + labelH + 10 * s
  local bGap = 10 * s
  local halfW = (innerW - bGap) / 2
  self.saveImportRect =
    self:_glassyButton(ix, iy, halfW, sfBtnH, "Import save", self.saveBtnFont, sfImportEnabled)
  self.saveExportRect = self:_glassyButton(ix + halfW + bGap, iy, halfW, sfBtnH,
    "Export save", self.saveBtnFont, sfExportEnabled)
  iy = iy + sfBtnH + 6 * s
  love.graphics.setFont(self.hintFont)
  col(sfHintCol)
  love.graphics.printf(sfHintText, ix, iy, innerW, "left")
  iy = iy + sfHintH
  if sfNotice and sfNotice.dir then
    iy = iy + 4 * s
    love.graphics.setFont(self.hintFont)
    local label = Strings("Open folder")
    local lw = self.hintFont:getWidth(label)
    local frect = { x = ix, y = iy, width = lw, height = self.hintFont:getHeight(),
      dir = sfNotice.dir }
    local fhot = self:_hover(frect)
    col(fhot and PAL.linkHover or PAL.link)
    love.graphics.print(label, ix, iy)
    love.graphics.setLineWidth(1)
    love.graphics.line(ix, iy + self.hintFont:getHeight() - 1, ix + lw,
      iy + self.hintFont:getHeight() - 1)
    self.saveFolderRect = frect
  end

  -- Touch Controls: open the drag-to-reposition / disable editor (#327).
  if self.onEditTouchControls and touchBtnH > 0 then
    self.touchControlsRect = self:_glassyButton(
      leftX, touchY, colW, touchBtnH, "Touch Controls", self.saveBtnFont, true)
  end

  -- Play button
  self:_playButton(leftX, playY, colW, playH, gameName, ready, locked)

  -- SAVE SLOT card (right column, or stacked below Play when single-column).
  -- Skip only when the version is absent from GameVersion (no save backend).
  local slotNaturalH = 0
  if not locked then
    if twoCol then
      _, slotNaturalH = self:_drawSaveSlotPanel(version, rightX, bodyTop, colW, bodyH, paged)
    else
      local slotY = playY + playH + 12 * s
      local slotH = math.max(160 * s, (bodyTop + bodyH) - slotY)
      _, slotNaturalH = self:_drawSaveSlotPanel(version, leftX, slotY, colW, slotH, paged)
    end
  end

  -- Natural height: side by side the two columns overlap, stacked they add up.
  -- Measured from the panel's own top (y), so draw() can compare it against the
  -- viewport without knowing anything about the cards inside.
  local bodyNaturalH
  if twoCol then
    bodyNaturalH = math.max(leftNaturalH, slotNaturalH)
  elseif locked then
    bodyNaturalH = leftNaturalH
  else
    bodyNaturalH = leftNaturalH + 12 * s + slotNaturalH
  end
  return (bodyTop - y) + bodyNaturalH
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

-- Poll the pointer once per frame to drive drag-scroll + deferred click on the
-- save-slot list.  main.lua forwards neither move nor release events to the
-- launcher, so a press only ARMS a click (see mousepressed) and this resolves
-- it: a pointer that moved past the threshold scrolls; one that did not, on
-- release, selects.  Desktop only -- Android selects on press instead.
-- Where the pointer is this frame and whether it is held, read by polling
-- because no move event ever reaches the launcher: the mouse on desktop, the
-- first active touch on Android.  A nil y means "nothing to read" -- the
-- release branches below do not need one.
function RomImporter:_pointerHold()
  if not self.android then return love.mouse.isDown(1), self._my end
  if not self.touchPollable then return false, nil end
  local ok, list = pcall(love.touch.getTouches)
  if not ok or type(list) ~= "table" or list[1] == nil then return false, nil end
  local ok2, _, ty = pcall(love.touch.getPosition, list[1])
  if not ok2 or type(ty) ~= "number" then return false, nil end
  return true, ty
end

function RomImporter:_updateSlotDrag()
  if self.android and not self.touchPollable then return end
  local down, py = self:_pointerHold()
  py = py or self._my
  local maxPage = self._pageMax or 0

  -- A press on empty background pans the page while it overflows.  Nothing is
  -- armed by it, so there is no release action to resolve.
  local pp = self._pagePress
  if pp then
    if down then
      if maxPage > 0 then
        self.pageScroll = clamp(pp.scroll0 - (py - pp.y0), 0, maxPage)
      end
    else
      self._pagePress = nil
    end
  end

  local p = self._slotPress
  if p then
    if down then
      local d = py - p.y0
      if math.abs(d) > 4 * (self._s or 1) then p.moved = true end
      if p.moved then
        -- Paged, the list has no scroll of its own: the drag pans the page, so
        -- a swipe that starts on a slot row behaves like one starting beside it.
        if maxPage > 0 then
          self.pageScroll = clamp(p.pageScroll0 - d, 0, maxPage)
        else
          local maxS = (self._slotMax and self._slotMax[p.version]) or 0
          self.slotScroll[p.version] = clamp(p.scroll0 - d, 0, maxS)
        end
      end
    else
      if not p.moved then self:_selectSlot(p.version, p.id) end
      self._slotPress = nil
    end
  end
  -- The same click-vs-drag resolution for the mods list: a moved pointer scrolls
  -- the list, a still one toggles the armed mod on release.
  local mp = self._modPress
  if mp then
    if down then
      local d = py - mp.y0
      if math.abs(d) > 4 * (self._s or 1) then mp.moved = true end
      if mp.moved then
        if maxPage > 0 then
          self.pageScroll = clamp(mp.pageScroll0 - d, 0, maxPage)
        else
          self.modScroll = clamp(mp.scroll0 - d, 0, self._modMax or 0)
        end
      end
    else
      if not mp.moved then self:_toggleMod(mp.id) end
      self._modPress = nil
    end
  end
end

-- Mouse wheel over a game tab scrolls its save-slot list (installed onto the
-- global love.wheelmoved in new(); see the chain there).  Clamped to the last
-- content extent draw computed for that version.
function RomImporter:wheelmoved(_, dy)
  local step = 48 * (self._s or 1)
  -- An open modal owns the wheel: the page behind it is not what the player is
  -- looking at, and a long description is the one thing here that needs it.
  if self._findDetails then
    self._findDetails.scroll = clamp(
      (self._findDetails.scroll or 0) - dy * step, 0, self._findDetails.max or 0)
    return
  end
  -- An overflowing page scrolls as a whole; the panels' own lists are flattened
  -- in that mode, so there is never a second scroll region competing for this.
  local maxPage = self._pageMax or 0
  if maxPage > 0 then
    self.pageScroll = clamp((self.pageScroll or 0) - dy * step, 0, maxPage)
    return
  end
  if self.tab == "mods" then
    local maxS = self._modMax or 0
    if maxS <= 0 then return end
    self.modScroll = clamp((self.modScroll or 0) - dy * step, 0, maxS)
    return
  end
  if self.tab == "find" then
    local maxS = self._findMax or 0
    if maxS <= 0 then return end
    self.findScroll = clamp((self.findScroll or 0) - dy * step, 0, maxS)
    return
  end
  local version = self.panelVersion
  if not version or self.tab ~= version then return end
  local maxS = (self._slotMax and self._slotMax[version]) or 0
  if maxS <= 0 then return end
  self.slotScroll[version] = clamp((self.slotScroll[version] or 0) - dy * step, 0, maxS)
end

-- SAVE SLOT card: header ("SAVE SLOT" + "N slots"), a scrollable list of slot
-- rows (name + meta, LOADED pill on the active one), and a dashed "+ New save
-- slot" button pinned to the bottom.  Empty registries show a dashed hint box.
-- `paged` (the whole launcher page is scrolling, see draw()) drops the inner
-- scroll region: the card grows to its natural height, every row is drawn, and
-- the page's own scrollbar is the only one on screen.  Returns the height the
-- card actually took, which is what the caller measures the page against.
function RomImporter:_drawSaveSlotPanel(version, x, y, w, h, paged)
  local s = self._s
  local pad = 16 * s
  self:_ensureSlots(version)
  local slots = self.slots[version] or {}
  local active = self.activeSlot[version]
  local n = #slots

  -- Row metrics up front: the natural height needs them, and the natural height
  -- decides the card's height before anything is drawn.
  local labelH = self.labelFont:getHeight()
  local newBtnH = math.max(38 * s, self.saveBtnFont:getHeight() + 18 * s)
  local nameH = self.slotNameFont:getHeight()
  local metaH = self.labelFont:getHeight()
  local rowPadV = 10 * s
  local chipBtnH = self.hintFont:getHeight() + 10 * s
  -- LOADED sits top-right; Edit/Delete sit bottom-right -- row must fit both
  -- without stacking on the same y (chip buttons are taller than the old text).
  local loadedH = self.warningFont:getHeight() + 6 * s
  local rowH = math.max(rowPadV * 2 + nameH + 4 * s + metaH,
    rowPadV + loadedH + 4 * s + chipBtnH + rowPadV)
  local rowGap = 8 * s
  local rr = 12 * s
  local btnGap = 8 * s
  -- an empty registry shows a fixed-height dashed hint box instead of rows
  local totalH = (n > 0) and (n * rowH + (n - 1) * rowGap) or (96 * s)
  local naturalH = pad + labelH + 12 * s + totalH + 10 * s + newBtnH + pad
  if paged then h = naturalH end

  roundedCard(x, y, w, h, 16 * s)

  -- header: "SAVE SLOT" (left) + "N slots" / "1 slot" (right)
  love.graphics.setFont(self.labelFont)
  col(PAL.labelGray)
  printSpaced(self.labelFont, "SAVE SLOT", x + pad, y + pad, 2 * s)
  local countTxt = (n == 1) and "1 slot" or (n .. " slots")
  local cw = self.labelFont:getWidth(countTxt)
  love.graphics.print(countTxt, x + w - pad - cw, y + pad)

  local listTop = y + pad + labelH + 12 * s

  -- "+ New save slot" pinned to the card bottom; the list fills the gap above.
  local newBtnY = y + h - pad - newBtnH
  local listBottom = newBtnY - 10 * s
  local listH = math.max(0, listBottom - listTop)
  local rx, rw = x + pad, w - 2 * pad

  if n == 0 then
    -- empty state: a dashed box with the centred hint
    love.graphics.setLineWidth(math.max(1, 1 * s))
    col(PAL.cardBorder, 0.45)
    dashedRoundRect(rx, listTop, rw, listH, 12 * s, 7 * s, 5 * s)
    love.graphics.setFont(self.hintFont)
    col(PAL.warning)
    love.graphics.printf("No saves yet - start a new game or import one.",
      rx + 12 * s, listTop + listH / 2 - self.hintFont:getHeight() / 2,
      rw - 24 * s, "center")
    self.slotRects = {}
    self.slotDeleteRects = {}
    self.slotEditRects = {}
  elseif listH > 0 then
    -- clamp scroll against the current content extent, and stash the max so the
    -- wheel handler (which has no geometry) can clamp against the same value.
    -- Paged, listH already equals totalH, so this is 0 and the wheel falls
    -- through to the page scroll.
    local maxScroll = math.max(0, totalH - listH)
    self._slotMax = self._slotMax or {}
    self._slotMax[version] = maxScroll
    local scroll = clamp(self.slotScroll[version] or 0, 0, maxScroll)
    self.slotScroll[version] = scroll

    self.slotRects = {}
    self.slotDeleteRects = {}
    self.slotEditRects = {}
    -- Paged, the page viewport's scissor is already set and nothing here
    -- overflows the card, so leave it alone rather than replace and clear it.
    if not paged then
      love.graphics.setScissor(math.floor(rx), math.floor(listTop),
        math.ceil(rw), math.ceil(listH))
    end
    for i, slot in ipairs(slots) do
      local ry = listTop - scroll + (i - 1) * (rowH + rowGap)
      if ry + rowH >= listTop and ry <= listBottom then
        local selected = slot.id == active
        if selected then neonGlow(rx, ry, rw, rowH, rr, PAL.green, 0.5) end
        fillGradRounded(rx, ry, rw, rowH, rr, PAL.slotBg, PAL.slotBg, 0.6, 0.6)
        love.graphics.setLineWidth(math.max(1, (selected and 1.5 or 1) * s))
        col(selected and PAL.green or PAL.cardBorder, selected and 0.9 or 0.22)
        love.graphics.rectangle("line", rx, ry, rw, rowH, rr, rr)

        -- Edit + Delete chip buttons (bottom-right row). Delete arms on the
        -- first click and asks "Sure?" on the second; width stays on "Delete"
        -- so the row never reflows (#433).
        love.graphics.setFont(self.hintFont)
        local darmed = armedDelete(self._confirmDelete, "slot", slot.id, version)
        local delLabel = darmed and "Sure?" or "Delete"
        local delW = self.hintFont:getWidth("Delete") + 24 * s
        local delX = rx + rw - 12 * s - delW
        local delY = ry + rowH - rowPadV - chipBtnH
        local drect = self:_chipButton(delX, delY, delLabel, {
          w = delW, h = chipBtnH, id = slot.id,
          kind = darmed and "dangerArmed" or "danger",
        })
        local rightReserve = delW + 18 * s

        -- Edit, immediately left of Delete: opens the bundled save editor on
        -- this slot's file. Only when the host supplied onEditSave and the
        -- slot actually holds a save.
        local erect = nil
        if self.onEditSave and slot.exists then
          local edW = self.hintFont:getWidth("Edit") + 24 * s
          local edX = delX - btnGap - edW
          erect = self:_chipButton(edX, delY, "Edit", {
            w = edW, h = chipBtnH, id = slot.id, kind = "accent",
          })
          rightReserve = rightReserve + edW + btnGap + 6 * s
        end

        -- LOADED pill top-right (above the button row, never over Delete)
        local pillW = 0
        if selected then
          love.graphics.setFont(self.warningFont)
          local pText = "LOADED"
          local pw = self.warningFont:getWidth(pText) + 14 * s
          local ph = loadedH
          local ppx = rx + rw - 12 * s - pw
          local ppy = ry + rowPadV
          col(PAL.green)
          love.graphics.rectangle("fill", ppx, ppy, pw, ph, ph / 2, ph / 2)
          col(PAL.playInk)
          printfB(pText, ppx, ppy + (ph - self.warningFont:getHeight()) / 2, pw, "center")
          pillW = pw + 10 * s
        end

        love.graphics.setFont(self.slotNameFont)
        col(PAL.white)
        -- a custom label (#205) wins over the player name; both ellipsize
        local name = slot.label or slot.name or Strings("NEW GAME")
        printB(ellipsize(self.slotNameFont, name, rw - 24 * s - math.max(pillW, rightReserve)),
          rx + 12 * s, ry + rowPadV)

        local metaTxt
        if slot.exists and slot.meta then
          metaTxt = Strings("%d badges - %s - %d caught", slot.meta.badges or 0, slot.meta.timeText or "0:00",
            slot.meta.dexCount or 0)
        else
          metaTxt = "empty slot"
        end
        love.graphics.setFont(self.labelFont)
        col(PAL.warning)
        love.graphics.print(ellipsize(self.labelFont, metaTxt, rw - 24 * s - rightReserve),
          rx + 12 * s, ry + rowPadV + nameH + 4 * s)

        -- clip the hit rect to the visible list band so a partly-scrolled row
        -- is only clickable where it actually shows
        local vy = math.max(ry, listTop)
        local vy2 = math.min(ry + rowH, listBottom)
        if vy2 > vy then
          self.slotRects[#self.slotRects + 1] =
            { x = rx, y = vy, width = rw, height = vy2 - vy, id = slot.id }
        end
        local dvy = math.max(drect.y, listTop)
        local dvy2 = math.min(drect.y + drect.height, listBottom)
        if dvy2 > dvy then
          self.slotDeleteRects[#self.slotDeleteRects + 1] =
            { x = drect.x, y = dvy, width = drect.width, height = dvy2 - dvy, id = slot.id }
        end
        if erect then
          local evy = math.max(erect.y, listTop)
          local evy2 = math.min(erect.y + erect.height, listBottom)
          if evy2 > evy then
            self.slotEditRects[#self.slotEditRects + 1] =
              { x = erect.x, y = evy, width = erect.width, height = evy2 - evy,
                id = slot.id }
          end
        end
      end
    end
    if not paged then love.graphics.setScissor() end

    -- thin scrollbar thumb when the list overflows
    if maxScroll > 0 then
      local trackH = listH
      local thumbH = math.max(24 * s, trackH * (listH / totalH))
      local thumbY = listTop + (trackH - thumbH) * (scroll / maxScroll)
      col(PAL.cardBorder, 0.35)
      love.graphics.rectangle("fill", rx + rw - 3 * s, thumbY, 3 * s, thumbH,
        1.5 * s, 1.5 * s)
    end
  end

  -- "+ New save slot" (dashed, transparent) pinned to the bottom
  local nrect = { x = rx, y = newBtnY, width = rw, height = newBtnH }
  local nhot = self:_hover(nrect)
  love.graphics.setLineWidth(math.max(1, 1.4 * s))
  col(PAL.cardBorder, nhot and 0.7 or 0.45)
  dashedRoundRect(nrect.x, nrect.y, nrect.width, nrect.height, 10 * s, 6 * s, 5 * s)
  love.graphics.setFont(self.saveBtnFont)
  col(PAL.detail, nhot and 1 or 0.9)
  printfB("+ New save slot", nrect.x,
    nrect.y + (newBtnH - self.saveBtnFont:getHeight()) / 2, nrect.width, "center")
  self.newSlotRect = nrect
  return h, naturalH
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

-- The status-chip label + colour for a mod row (deriveList's status verdict).
local function modStatusChip(status)
  if status == "ok" then return "Ready", PAL.green end
  if status == "conflict" then return "Conflict", PAL.red end
  return "Incompatible", PAL.gold   -- "warn": bad range or missing dependency
end

-- MODS panel.  Header ("Mods" + "N of M enabled" + "Import mod .zip"), an
-- install-result / drag-drop notice line, then a scrollable list of mod cards
-- (name + badge chip + description, a status chip, and a toggle switch).  An
-- empty install shows a friendly dashed hint box.
-- `paged` behaves as it does on the game panel: no inner scroll region, the
-- card list is drawn whole, and the returned natural height is what draw()
-- measures the page against.
function RomImporter:_drawModsPanel(x, y, w, h, paged)
  local s = self._s
  self:_ensureMods()
  local mods = self.mods or {}

  -- header: "Mods" + "N of M enabled" (left) and "Import mod .zip" (right)
  love.graphics.setFont(self.gameNameFont)
  col(PAL.white)
  printB("Mods", x, y)
  local nameW = self.gameNameFont:getWidth("Mods")
  local headerH = self.gameNameFont:getHeight()

  local enabledCount = 0
  for _, m in ipairs(mods) do if m.enabled then enabledCount = enabledCount + 1 end end
  love.graphics.setFont(self.hintFont)
  col(PAL.warning)
  local countText = Strings("%d of %d enabled", enabledCount, #mods)
  local countX = x + nameW + 14 * s
  love.graphics.print(countText, countX,
    y + (headerH - self.hintFont:getHeight()) / 2)

  local btnLabel = "Import mod .zip"
  local btnH = math.max(38 * s, self.saveBtnFont:getHeight() + 20 * s)
  local btnW = math.min(w * 0.5, self.saveBtnFont:getWidth(btnLabel) + 40 * s)
  local btnX = x + w - btnW
  local btnY = y + (headerH - btnH) / 2
  self.modImportRect =
    self:_glassyButton(btnX, btnY, btnW, btnH, btnLabel, self.saveBtnFont, true)

  -- Enable all / Disable all (#647): bulk switches beside Import mod .zip, so
  -- coming back from a cable-club session (which asks for a vanilla fingerprint,
  -- src/link/Fingerprint.lua) costs one click instead of one switch per mod.
  -- The header is a single row shared with the count, so the chips are dropped
  -- rather than overlapped when the column is too narrow to hold them (a
  -- phone-width layout); the per-mod switches below are always the full path.
  self.modEnableAllRect, self.modDisableAllRect = nil, nil
  if #mods > 0 then
    local enaLabel, disLabel = Strings("Enable all"), Strings("Disable all")
    love.graphics.setFont(self.hintFont)
    local bulkH = self.hintFont:getHeight() + 10 * s
    local bulkY = y + (headerH - bulkH) / 2
    local enaW = self.hintFont:getWidth(enaLabel) + 24 * s
    local disW = self.hintFont:getWidth(disLabel) + 24 * s
    local bulkGap = 8 * s
    local room = btnX - (countX + self.hintFont:getWidth(countText) + bulkGap)
    if room >= enaW + disW + 2 * bulkGap then
      local disX = btnX - bulkGap - disW
      local enaX = disX - bulkGap - enaW
      self.modEnableAllRect =
        self:_chipButton(enaX, bulkY, enaLabel, { w = enaW, h = bulkH })
      self.modDisableAllRect =
        self:_chipButton(disX, bulkY, disLabel, { w = disW, h = bulkH })
    end
  end

  local top = y + headerH + 14 * s

  -- notice line: the last install/delete result, else the platform hint
  love.graphics.setFont(self.hintFont)
  if self.modNotice then
    col(self.modNotice.ok and PAL.green or PAL.red)
    love.graphics.printf(self.modNotice.text, x, top, w, "left")
  else
    col(PAL.warning)
    love.graphics.printf(self.android and "Or copy a mod .zip via USB."
      or Strings("Or drop a mod .zip onto the window."), x, top, w, "left")
  end
  top = top + self.hintFont:getHeight() + 12 * s

  local listH = math.max(0, (y + h) - top)

  -- empty state: a dashed box with a centred hint
  if #mods == 0 then
    local boxH = paged and (120 * s) or math.min(listH, 120 * s)
    love.graphics.setLineWidth(math.max(1, 1 * s))
    col(PAL.cardBorder, 0.45)
    dashedRoundRect(x, top, w, boxH, 14 * s, 7 * s, 5 * s)
    love.graphics.setFont(self.hintFont)
    col(PAL.warning)
    local emptyHint = self.android
      and "No mods installed - tap Import mod .zip to add one."
      or Strings("No mods installed - drop a mod .zip here to add one.")
    love.graphics.printf(emptyHint,
      x + 16 * s, top + boxH / 2 - self.hintFont:getHeight() / 2, w - 32 * s, "center")
    self.modRects = {}
    self.modDeleteRects = {}
    self.modUpdateRects = {}
    self.modVersionsRects = {}
    self._modMax = 0
    return (top - y) + boxH
  end

  -- card metrics: status + toggle top-right; action chip-buttons in one row
  -- under the body (Update / Versions / Delete when github is set).
  local padH, padV = 16 * s, 14 * s
  local cardGap, cardR = 10 * s, 14 * s
  local tw, th = 52 * s, 28 * s
  local innerW = w - 2 * padH
  local chipH = self.hintFont:getHeight() + 8 * s
  local btnH = self.hintFont:getHeight() + 10 * s
  local btnGap = 8 * s

  love.graphics.setFont(self.stateFont)
  local nameH = self.stateFont:getHeight()

  -- pre-pass: per-card layout + total height, so scroll can clamp to content
  local layout, total = {}, 0
  for i, m in ipairs(mods) do
    local chipText = modStatusChip(m.status)
    local chipW = self.hintFont:getWidth(chipText) + 20 * s
    local delW = self.hintFont:getWidth("Delete") + 24 * s
    local verW = self.hintFont:getWidth("Versions") + 24 * s
    local hasGh = m.github and m.github ~= ""
    local info = hasGh and self:_modUpdateInfo(m.id) or nil
    local updLabel = "Check for updates"
    local updateKind = "neutral"
    -- checkLine: always on the mod row for github mods so the check result
    -- is visible without relying on the top-of-panel notice.
    local checkLine = nil
    local checkLineColor = PAL.detail
    if info and info.status == "available" then
      updLabel = "Update"
      updateKind = "accent"
      checkLine = "Checked for updates - v" .. tostring(info.latest) .. " available"
      checkLineColor = PAL.playTop
    elseif info and info.status == "current" then
      updLabel = "Check again"
      checkLine = "Checked for updates - up to date"
      checkLineColor = PAL.playTop
    elseif info and info.status == "error" then
      checkLine = "Checked for updates - failed"
      checkLineColor = PAL.chooseTop
    elseif hasGh then
      checkLine = "Not checked for updates yet"
      checkLineColor = PAL.warning
    end
    local updW = self.hintFont:getWidth(updLabel) + 24 * s
    local btnRowW = delW
    if hasGh then btnRowW = updW + btnGap + verW + btnGap + delW end
    local clusterW = math.max(chipW, tw)
    local leftW = math.max(40 * s, innerW - clusterW - 14 * s)
    local descH = 0
    if m.description ~= "" then
      love.graphics.setFont(self.hintFont)
      local _, dl = self.hintFont:getWrap(m.description, leftW)
      descH = math.max(1, #dl) * self.hintFont:getHeight()
    end
    local clusterH = chipH + 6 * s + th
    local metaH = self.hintFont:getHeight() + 2 * s
    if checkLine then
      metaH = metaH + self.hintFont:getHeight() + 2 * s
    end
    if descH > 0 then
      metaH = metaH + self.hintFont:getHeight() + 2 * s + descH
    end
    local bodyH = math.max(nameH + 4 * s + metaH, clusterH)
    local cardH = padV * 2 + bodyH + 10 * s + btnH
    layout[i] = { h = cardH, leftW = leftW, clusterW = clusterW,
      chipText = chipText, chipW = chipW, delW = delW,
      updW = updW, verW = verW, hasGh = hasGh, clusterH = clusterH,
      btnRowW = btnRowW, bodyH = bodyH, updLabel = updLabel,
      updateKind = updateKind, checkLine = checkLine,
      checkLineColor = checkLineColor }
    total = total + cardH
  end
  total = total + (#mods - 1) * cardGap

  -- Paged, the list band is the list itself: nothing to clip, nothing to scroll
  -- here, and the page's scrollbar covers the overflow.
  if paged then listH = total end
  local maxScroll = math.max(0, total - listH)
  self._modMax = maxScroll
  local scroll = clamp(self.modScroll or 0, 0, maxScroll)
  self.modScroll = scroll
  self.modRects = {}
  self.modDeleteRects = {}
  self.modUpdateRects = {}
  self.modVersionsRects = {}

  if not paged then
    love.graphics.setScissor(math.floor(x), math.floor(top),
      math.ceil(w), math.ceil(listH))
  end
  local cy = top - scroll
  for i, m in ipairs(mods) do
    local L = layout[i]
    local cardH = L.h
    if cy + cardH >= top and cy <= top + listH then
      roundedCard(x, cy, w, cardH, cardR)
      local nx = x + padH
      local ny = cy + padV

      -- name (ellipsized to leave room for the badge chip) + badge chip
      love.graphics.setFont(self.warningFont)
      local badgeTW = self.warningFont:getWidth(m.badge)
      local badgeW = badgeTW + 12 * s
      local badgeH = self.warningFont:getHeight() + 6 * s
      love.graphics.setFont(self.stateFont)
      col(PAL.white)
      local drawnName = ellipsize(self.stateFont, m.name, L.leftW - badgeW - 8 * s)
      printB(drawnName, nx, ny)
      local bxx = nx + self.stateFont:getWidth(drawnName) + 8 * s
      local byy = ny + (nameH - badgeH) / 2
      love.graphics.setLineWidth(1)
      col(PAL.cardBorder, 0.5)
      love.graphics.rectangle("line", bxx, byy, badgeW, badgeH, 5 * s, 5 * s)
      love.graphics.setFont(self.warningFont)
      col(m.experimental and PAL.gold or PAL.warning)
      love.graphics.print(m.badge, bxx + 6 * s,
        byy + (badgeH - self.warningFont:getHeight()) / 2)

      -- version + check status line + description under the name
      love.graphics.setFont(self.hintFont)
      col(PAL.detail)
      local metaY = ny + nameH + 4 * s
      love.graphics.print("v" .. tostring(m.version or "?"), nx, metaY)
      metaY = metaY + self.hintFont:getHeight() + 2 * s
      if L.checkLine then
        col(L.checkLineColor or PAL.detail)
        love.graphics.print(
          ellipsize(self.hintFont, L.checkLine, L.leftW), nx, metaY)
        metaY = metaY + self.hintFont:getHeight() + 2 * s
      end
      if m.description ~= "" then
        col(PAL.detail)
        love.graphics.printf(m.description, nx, metaY, L.leftW, "left")
      end

      -- right cluster: status chip + toggle (action buttons are a bottom row)
      local clusterX = x + w - padH - L.clusterW
      local clusterY = cy + padV
      local _, chipColor = modStatusChip(m.status)
      local chipX = clusterX + (L.clusterW - L.chipW) / 2
      col(chipColor, 0.1)
      love.graphics.rectangle("fill", chipX, clusterY, L.chipW, chipH, chipH / 2, chipH / 2)
      love.graphics.setLineWidth(1)
      col(chipColor, 0.55)
      love.graphics.rectangle("line", chipX, clusterY, L.chipW, chipH, chipH / 2, chipH / 2)
      love.graphics.setFont(self.hintFont)
      col(chipColor)
      printfB(L.chipText, chipX,
        clusterY + (chipH - self.hintFont:getHeight()) / 2, L.chipW, "center")

      -- toggle switch (ON = green gradient + glow, knob right; OFF = gray, left)
      local tx = clusterX + (L.clusterW - tw) / 2
      local ty = clusterY + chipH + 6 * s
      local rr = th / 2
      local trect = { x = tx - 6 * s, y = ty - 6 * s,
        width = tw + 12 * s, height = th + 12 * s, id = m.id }
      self:_hover(trect)
      if m.enabled then
        neonGlow(tx, ty, tw, th, rr, PAL.green, 0.45)
        fillGradRounded(tx, ty, tw, th, rr, PAL.playTop, PAL.playBot, 1, 1)
      else
        col(PAL.disabled, 0.35)
        love.graphics.rectangle("fill", tx, ty, tw, th, rr, rr)
      end
      local kd = th - 6 * s
      local kcx = m.enabled and (tx + tw - 3 * s - kd / 2) or (tx + 3 * s + kd / 2)
      col(PAL.white)
      love.graphics.circle("fill", kcx, ty + th / 2, kd / 2)

      -- Action chip-buttons in one right-aligned row under the body
      local btnY = cy + cardH - padV - btnH
      local btnX = x + w - padH - L.btnRowW
      local darmed = armedDelete(self._confirmDelete, "mod", m.id, nil)
      local function clipHit(rect, bucket)
        if not rect then return end
        local vy = math.max(rect.y, top)
        local vy2 = math.min(rect.y + rect.height, top + listH)
        if vy2 > vy then
          bucket[#bucket + 1] = {
            x = rect.x, y = vy, width = rect.width, height = vy2 - vy,
            id = rect.id,
          }
        end
      end
      if L.hasGh then
        local urect = self:_chipButton(btnX, btnY, L.updLabel, {
          w = L.updW, h = btnH, id = m.id, kind = L.updateKind or "neutral",
        })
        clipHit(urect, self.modUpdateRects)
        btnX = btnX + L.updW + btnGap
        local vrect = self:_chipButton(btnX, btnY, "Versions", {
          w = L.verW, h = btnH, id = m.id, kind = "neutral",
        })
        clipHit(vrect, self.modVersionsRects)
        btnX = btnX + L.verW + btnGap
      end
      local drect = self:_chipButton(btnX, btnY, darmed and "Sure?" or "Delete", {
        w = L.delW, h = btnH, id = m.id,
        kind = darmed and "dangerArmed" or "danger",
      })
      clipHit(drect, self.modDeleteRects)

      -- toggle hit rect clipped to the visible list band
      local vy = math.max(trect.y, top)
      local vy2 = math.min(trect.y + trect.height, top + listH)
      if vy2 > vy then
        self.modRects[#self.modRects + 1] =
          { x = trect.x, y = vy, width = trect.width, height = vy2 - vy, id = m.id }
      end
    end
    cy = cy + cardH + cardGap
  end
  if not paged then love.graphics.setScissor() end

  -- thin scrollbar thumb when the list overflows
  if maxScroll > 0 then
    local thumbH = math.max(24 * s, listH * (listH / total))
    local thumbY = top + (listH - thumbH) * (scroll / maxScroll)
    col(PAL.cardBorder, 0.35)
    love.graphics.rectangle("fill", x + w - 3 * s, thumbY, 3 * s, thumbH, 1.5 * s, 1.5 * s)
  end
  return (top - y) + total
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
function RomImporter:_refreshFind(force)
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

-- The label + colour for an entry's install state, given what is installed.
local function findActionFor(entry, installedVersion)
  local ModIndex = require("src.mods.ModIndex")
  if not ModIndex.canInstall(entry) then
    return nil, "Not installable from this index"
  end
  if not installedVersion then return "Install", nil end
  local listed = ModIndex.displayVersion(entry)
  local ModUpdate = require("src.mods.ModUpdate")
  if type(installedVersion) == "string"
      and ModUpdate.isNewer(installedVersion, listed) then
    return "Update", "Installed v" .. installedVersion
  end
  return "Reinstall", "Installed v" .. tostring(installedVersion)
end

-- FIND MODS panel.  Header ("Find Mods" + count + Refresh / Add an index),
-- notice line, the source list, a search field and category chips, then the
-- listing.  With no index added at all it collapses to a single dashed prompt.
-- `paged` behaves as everywhere else: no inner scroll region, the list is drawn
-- whole, and the returned natural height is what draw() measures the page on.
function RomImporter:_drawFindPanel(x, y, w, h, paged)
  local s = self._s
  self._findThumbFetched = false
  self:_ensureFind()
  self:_ensureMods()
  local ModIndex = require("src.mods.ModIndex")
  local sources = self.findSources or {}
  local rows = self:_findRows()
  local total = #((self.findIndex and self.findIndex.mods) or {})

  self.findCatRects = {}
  self.findInstallRects = {}
  self.findDetailRects = {}
  self.findRepoRects = {}
  self.findSourceRemoveRects = {}

  -- header
  love.graphics.setFont(self.gameNameFont)
  col(PAL.white)
  printB("Find Mods", x, y)
  local nameW = self.gameNameFont:getWidth("Find Mods")
  local headerH = self.gameNameFont:getHeight()
  if #sources > 0 then
    love.graphics.setFont(self.hintFont)
    col(PAL.warning)
    local countLabel = (#rows == total)
      and Strings("%d mods listed", total)
      or Strings("%d of %d mods", #rows, total)
    love.graphics.print(countLabel, x + nameW + 14 * s,
      y + (headerH - self.hintFont:getHeight()) / 2)
  end

  local btnH = math.max(38 * s, self.saveBtnFont:getHeight() + 20 * s)
  local btnY = y + (headerH - btnH) / 2
  local addLabel = (#sources == 0) and "Add an index" or "Add index"
  local addW = math.min(w * 0.45, self.saveBtnFont:getWidth(addLabel) + 40 * s)
  local addX = x + w - addW
  self.findAddRect =
    self:_glassyButton(addX, btnY, addW, btnH, addLabel, self.saveBtnFont, true)
  if #sources > 0 then
    local refLabel = "Refresh"
    local refW = math.min(w * 0.3, self.saveBtnFont:getWidth(refLabel) + 36 * s)
    self.findRefreshRect = self:_glassyButton(addX - refW - 8 * s, btnY,
      refW, btnH, refLabel, self.saveBtnFont, true)
  end

  local top = y + headerH + 14 * s

  -- notice line: the last add / refresh / install result, else the standing
  -- reminder that a listing is not a review
  love.graphics.setFont(self.hintFont)
  if self.findNotice then
    col(self.findNotice.ok and PAL.green or PAL.red)
    love.graphics.printf(self.findNotice.text, x, top, w, "left")
  else
    col(PAL.warning)
    love.graphics.printf(
      Strings("Mods here are listed, not reviewed - read the source and trust the author."),
      x, top, w, "left")
  end
  top = top + self.hintFont:getHeight() + 12 * s

  -- no index: one dashed prompt and nothing else.  This is the whole tab until
  -- the player names a feed.
  if #sources == 0 then
    local boxH = 150 * s
    love.graphics.setLineWidth(math.max(1, 1 * s))
    col(PAL.cardBorder, 0.45)
    dashedRoundRect(x, top, w, boxH, 14 * s, 7 * s, 5 * s)
    love.graphics.setFont(self.stateFont)
    col(PAL.heading)
    printfB(Strings("No mod index added"), x + 16 * s, top + boxH / 2
      - self.stateFont:getHeight(), w - 32 * s, "center")
    love.graphics.setFont(self.hintFont)
    col(PAL.warning)
    love.graphics.printf(
      Strings("Add an index to browse mods. An index is a published list; paste its URL or its owner/repo."),
      x + 24 * s, top + boxH / 2 + 4 * s, w - 48 * s, "center")
    self._findMax = 0
    return (top - y) + boxH
  end

  -- source rows: which indexes are feeding this list, each with a Remove
  local srcH = self.hintFont:getHeight() + 10 * s
  for _, source in ipairs(sources) do
    love.graphics.setFont(self.hintFont)
    col(PAL.detail)
    local remW = self.hintFont:getWidth("Remove") + 20 * s
    love.graphics.print(
      ellipsize(self.hintFont, source.label or source.feed, w - remW - 20 * s),
      x + 2 * s, top + 5 * s)
    local rrect = self:_chipButton(x + w - remW, top, "Remove", {
      w = remW, h = srcH, id = source.feed, kind = "danger",
    })
    self.findSourceRemoveRects[#self.findSourceRemoveRects + 1] = rrect
    top = top + srcH + 4 * s
  end
  top = top + 6 * s

  -- search field: click to focus, type to filter.  Not a modal -- the results
  -- have to move while the player types or the field is guesswork.
  local fieldH = 30 * s
  local focused = self._findSearchFocus == true
  col(PAL.bgBot, 0.9)
  love.graphics.rectangle("fill", x, top, w, fieldH, 8 * s, 8 * s)
  love.graphics.setLineWidth(math.max(1, s))
  col(focused and PAL.green or PAL.cardBorder, focused and 0.7 or 0.45)
  love.graphics.rectangle("line", x, top, w, fieldH, 8 * s, 8 * s)
  love.graphics.setFont(self.detailFont)
  local query = self.findQuery or ""
  if query == "" and not focused then
    col(PAL.disabledInk)
    love.graphics.print(Strings("Search mods"), x + 10 * s,
      top + (fieldH - self.detailFont:getHeight()) / 2)
  else
    col(PAL.heading)
    local shown = ellipsize(self.detailFont, query, w - 20 * s)
    love.graphics.print(shown, x + 10 * s,
      top + (fieldH - self.detailFont:getHeight()) / 2)
    if focused and (self.pulse * 2 % 1) < 0.5 then
      col(PAL.green)
      love.graphics.rectangle("fill",
        x + 10 * s + self.detailFont:getWidth(shown) + 2 * s,
        top + 6 * s, math.max(1, 1.5 * s), fieldH - 12 * s)
    end
  end
  self.findSearchRect = { x = x, y = top, width = w, height = fieldH }
  self:_hover(self.findSearchRect)
  top = top + fieldH + 10 * s

  -- category chips: "All" plus whatever the feeds actually use
  local cats = (self.findIndex and self.findIndex.categories) or {}
  if #cats > 0 then
    local chipH = self.hintFont:getHeight() + 8 * s
    local cx, cy = x, top
    local function catChip(label, id, active)
      local cw = self.hintFont:getWidth(label) + 20 * s
      if cx + cw > x + w and cx > x then
        cx = x
        cy = cy + chipH + 6 * s
      end
      local rect = { x = cx, y = cy, width = cw, height = chipH, id = id }
      local hot = self:_hover(rect)
      col(active and PAL.green or PAL.cardBorder, active and 0.18 or 0.10)
      love.graphics.rectangle("fill", cx, cy, cw, chipH, chipH / 2, chipH / 2)
      love.graphics.setLineWidth(1)
      col(active and PAL.green or PAL.cardBorder, active and 0.6 or 0.35)
      love.graphics.rectangle("line", cx, cy, cw, chipH, chipH / 2, chipH / 2)
      love.graphics.setFont(self.hintFont)
      col(active and PAL.green or (hot and PAL.heading or PAL.detail))
      printfB(label, cx, cy + (chipH - self.hintFont:getHeight()) / 2, cw, "center")
      self.findCatRects[#self.findCatRects + 1] = rect
      cx = cx + cw + 6 * s
    end
    catChip("All", "", self.findCategory == nil)
    for _, c in ipairs(cats) do
      catChip(c, c, self.findCategory == c)
    end
    top = cy + chipH + 12 * s
  end

  local listH = math.max(0, (y + h) - top)

  if #rows == 0 then
    local boxH = paged and (110 * s) or math.min(listH, 110 * s)
    love.graphics.setLineWidth(math.max(1, 1 * s))
    col(PAL.cardBorder, 0.45)
    dashedRoundRect(x, top, w, boxH, 14 * s, 7 * s, 5 * s)
    love.graphics.setFont(self.hintFont)
    col(PAL.warning)
    local hint = (total == 0)
      and Strings("This index lists no mods yet.")
      or Strings("No mods match that search.")
    love.graphics.printf(hint, x + 16 * s,
      top + boxH / 2 - self.hintFont:getHeight() / 2, w - 32 * s, "center")
    self._findMax = 0
    return (top - y) + boxH
  end

  -- card metrics.  The thumbnail column is fixed whether or not a given entry
  -- has one, so rows stay aligned down the list.
  local padH, padV = 16 * s, 14 * s
  local cardGap, cardR = 10 * s, 14 * s
  local thumbW = 64 * s
  local innerW = w - 2 * padH
  local chipH = self.hintFont:getHeight() + 8 * s
  local rowBtnH = self.hintFont:getHeight() + 10 * s
  local btnGap = 8 * s
  local installed = self:_findInstalledMap()

  love.graphics.setFont(self.stateFont)
  local nameH = self.stateFont:getHeight()

  local layout, totalH = {}, 0
  for i, entry in ipairs(rows) do
    local action, note = findActionFor(entry, installed[entry.id])
    local detW = self.hintFont:getWidth("Details") + 24 * s
    local repoW = entry.repo and (self.hintFont:getWidth("Source") + 24 * s) or 0
    local actW = action and (self.hintFont:getWidth(action) + 24 * s) or 0
    local btnRowW = detW
    if repoW > 0 then btnRowW = btnRowW + btnGap + repoW end
    if actW > 0 then btnRowW = btnRowW + btnGap + actW end
    local leftX = thumbW + 12 * s
    local textW = math.max(60 * s, innerW - leftX)
    local summaryH = 0
    if entry.summary ~= "" then
      local _, sl = self.hintFont:getWrap(entry.summary, textW)
      summaryH = math.max(1, #sl) * self.hintFont:getHeight()
    end
    local metaH = self.hintFont:getHeight() + 2 * s   -- version + author
    if note then metaH = metaH + self.hintFont:getHeight() + 2 * s end
    if summaryH > 0 then metaH = metaH + 2 * s + summaryH end
    local bodyH = math.max(nameH + 4 * s + metaH, thumbW)
    local cardH = padV * 2 + bodyH + 10 * s + rowBtnH
    layout[i] = { h = cardH, textW = textW, leftX = leftX, action = action,
      note = note, detW = detW, repoW = repoW, actW = actW,
      btnRowW = btnRowW, summaryH = summaryH }
    totalH = totalH + cardH
  end
  totalH = totalH + (#rows - 1) * cardGap

  if paged then listH = totalH end
  local maxScroll = math.max(0, totalH - listH)
  self._findMax = maxScroll
  local scroll = clamp(self.findScroll or 0, 0, maxScroll)
  self.findScroll = scroll

  if not paged then
    love.graphics.setScissor(math.floor(x), math.floor(top),
      math.ceil(w), math.ceil(listH))
  end
  local cy = top - scroll
  for i, entry in ipairs(rows) do
    local L = layout[i]
    local cardH = L.h
    if cy + cardH >= top and cy <= top + listH then
      roundedCard(x, cy, w, cardH, cardR)
      local nx = x + padH
      local ny = cy + padV

      -- thumbnail, or a placeholder tile so the text column never shifts
      local image = self:_findThumb(entry)
      if image then
        local iw, ih = image:getDimensions()
        local fit = math.min(thumbW / iw, thumbW / ih)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(image, nx + (thumbW - iw * fit) / 2,
          ny + (thumbW - ih * fit) / 2, 0, fit, fit)
      else
        col(PAL.cardBorder, 0.18)
        love.graphics.rectangle("fill", nx, ny, thumbW, thumbW, 8 * s, 8 * s)
        love.graphics.setFont(self.warningFont)
        col(PAL.disabledInk)
        printfB("MOD", nx, ny + (thumbW - self.warningFont:getHeight()) / 2,
          thumbW, "center")
      end

      local tx = nx + L.leftX
      love.graphics.setFont(self.stateFont)
      col(PAL.white)
      printB(ellipsize(self.stateFont, entry.title or entry.id, L.textW), tx, ny)

      love.graphics.setFont(self.hintFont)
      col(PAL.detail)
      local metaY = ny + nameH + 4 * s
      local meta = "v" .. tostring(ModIndex.displayVersion(entry))
      if entry.author then meta = meta .. "  -  " .. entry.author end
      if entry.categories[1] then meta = meta .. "  -  " .. entry.categories[1] end
      love.graphics.print(ellipsize(self.hintFont, meta, L.textW), tx, metaY)
      metaY = metaY + self.hintFont:getHeight() + 2 * s
      if L.note then
        col(PAL.playTop)
        love.graphics.print(ellipsize(self.hintFont, L.note, L.textW), tx, metaY)
        metaY = metaY + self.hintFont:getHeight() + 2 * s
      end
      if L.summaryH > 0 then
        col(PAL.detail)
        love.graphics.printf(entry.summary, tx, metaY + 2 * s, L.textW, "left")
      end

      -- An entry the index could not resolve a download for still shows: a
      -- broken upstream is worth seeing, and hiding it reads as "no such mod".
      if not L.action then
        local warnChipW = self.hintFont:getWidth("Unavailable") + 20 * s
        local wx = x + w - padH - warnChipW
        col(PAL.gold, 0.1)
        love.graphics.rectangle("fill", wx, cy + padV, warnChipW, chipH,
          chipH / 2, chipH / 2)
        love.graphics.setLineWidth(1)
        col(PAL.gold, 0.55)
        love.graphics.rectangle("line", wx, cy + padV, warnChipW, chipH,
          chipH / 2, chipH / 2)
        love.graphics.setFont(self.hintFont)
        col(PAL.gold)
        printfB("Unavailable", wx,
          cy + padV + (chipH - self.hintFont:getHeight()) / 2,
          warnChipW, "center")
      end

      -- action row, clipped to the visible band exactly like the mods panel
      local by = cy + cardH - padV - rowBtnH
      local bx = x + w - padH - L.btnRowW
      local function clipHit(rect, bucket)
        if not rect then return end
        local vy = math.max(rect.y, top)
        local vy2 = math.min(rect.y + rect.height, top + listH)
        if vy2 > vy then
          bucket[#bucket + 1] = { x = rect.x, y = vy, width = rect.width,
            height = vy2 - vy, id = rect.id, entry = entry }
        end
      end
      local drect = self:_chipButton(bx, by, "Details", {
        w = L.detW, h = rowBtnH, id = entry.id, kind = "neutral",
      })
      clipHit(drect, self.findDetailRects)
      bx = bx + L.detW + btnGap
      if L.repoW > 0 then
        local rrect = self:_chipButton(bx, by, "Source", {
          w = L.repoW, h = rowBtnH, id = entry.id, kind = "neutral",
        })
        clipHit(rrect, self.findRepoRects)
        bx = bx + L.repoW + btnGap
      end
      if L.action then
        local arect = self:_chipButton(bx, by, L.action, {
          w = L.actW, h = rowBtnH, id = entry.id, kind = "accent",
        })
        clipHit(arect, self.findInstallRects)
      end
    end
    cy = cy + cardH + cardGap
  end
  if not paged then love.graphics.setScissor() end

  if maxScroll > 0 then
    local thumbH = math.max(24 * s, listH * (listH / totalH))
    local thumbY = top + (listH - thumbH) * (scroll / maxScroll)
    col(PAL.cardBorder, 0.35)
    love.graphics.rectangle("fill", x + w - 3 * s, thumbY, 3 * s, thumbH,
      1.5 * s, 1.5 * s)
  end
  return (top - y) + totalH
end

return RomImporter
