local GameVersion = require("src.core.GameVersion")
local Strings = require("src.core.Strings")
local HostShell = require("src.core.HostShell")

local RomImporter = {}
RomImporter.__index = RomImporter

-- Cache generation tag; bump to force every imported version to re-extract.
local CACHE_FORMAT = "rom-cache-v8:"
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

-- "Split-screen ROM selector" first-run palette (matches FirstRun.dc.html from
-- the Claude Design project): a dark neon arcade panel, one column per game.
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

-- Android SAF writes mod picks to picked_mod.zip; USB copies may use any
-- .zip basename at the save-dir root.  preferAny=true also accepts those USB
-- copies (Choose / Import); focus only consumes the SAF basename so a random
-- leftover archive is never auto-installed on every refocus.
local function findPendingMod(preferAny)
  local preferred = "picked_mod.zip"
  if love.filesystem.getInfo(preferred, "file") then
    return preferred
  end
  if not preferAny then return nil end
  for _, name in ipairs(love.filesystem.getDirectoryItems("")) do
    if name:lower():match("%.zip$") and love.filesystem.getInfo(name, "file") then
      return name
    end
  end
  return nil
end

-- Same pattern as findPendingMod for battery saves (picked_save.sav / *.sav).
local function findPendingSav(preferAny)
  local preferred = "picked_save.sav"
  if love.filesystem.getInfo(preferred, "file") then
    return preferred
  end
  if not preferAny then return nil end
  for _, name in ipairs(love.filesystem.getDirectoryItems("")) do
    if name:lower():match("%.sav$") and love.filesystem.getInfo(name, "file") then
      return name
    end
  end
  return nil
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
-- supplied the Edit label is not drawn at all).
function RomImporter.new(onComplete, opts)
  opts = opts or {}
  local android = love.system.getOS() == "Android"
  local CacheFs = require("src.import.CacheFs")
  local self = setmetatable({
    onComplete = onComplete,
    launcher = opts.launcher or false,
    forceImport = opts.forceImport or false,
    onEditSave = opts.onEditSave,
    android = android,
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
    -- Virtual pointer for handhelds / gamepads (Anbernic stock OS has no
    -- mouse).  D-pad + left stick move it; A clicks; shoulders cycle tabs;
    -- right stick scrolls the save-slot / mods lists.
    _padCursor = { x = 0, y = 0 },
    _padCursorActive = false,
    _padAxis = { leftx = 0, lefty = 0, righty = 0 },
    _padDir = {},
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
    if name then self:startData(data, name) end
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
  local modName = findPendingMod(false)
  if modName then
    self:_installMod(modName)
    if self.modNotice and self.modNotice.ok then
      love.filesystem.remove(modName)
    end
    return
  end
  local savName = findPendingSav(false)
  if savName then
    local version = self.androidPendingVersion or self:_savedropTarget()
    self.androidPendingVersion = nil
    self:_importSave(version, savName)
    if self.saveNotice[version] and self.saveNotice[version].ok then
      love.filesystem.remove(savName)
    end
    return
  end
  for _, v in ipairs(GameVersion.ORDER) do
    if not self.ready[v] then
      local name, data = findPendingRom(self.ready)
      if name then self:startData(data, name) end
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
  self.arrowCursor = self.arrowCursor or love.mouse.getSystemCursor("arrow")
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
    self:setError(("Unsupported ROM (SHA-1 %s). Use an unmodified US Pokemon "
      .. "Red, Blue, or Yellow ROM."):format(actualHash))
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
  local LauncherMods = require("src.mods.LauncherMods")
  local ok, res = LauncherMods.installZip(source)
  if ok then
    self:_refreshMods()
    self.modNotice = { ok = true, text = "Installed " .. tostring(res) }
  else
    self.modNotice = { ok = false, text = tostring(res) }
  end
  self.tab = "mods"
end

-- Remove an installed mod from the save-dir mods/ tree and refresh the panel.
function RomImporter:_deleteMod(id)
  if self.workState == "working" then return end
  local LauncherMods = require("src.mods.LauncherMods")
  local ok, res = LauncherMods.uninstall(id)
  if ok then
    self:_refreshMods()
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
  if self.android then
    local name = findPendingMod(true)
    if name then
      self:_installMod(name)
      if self.modNotice and self.modNotice.ok then
        love.filesystem.remove(name)
      end
      return
    end
    if not love.system.pickFile("mod") then
      self.modNotice = { ok = false,
        text = "Could not open the file picker. Copy a mod .zip via USB." }
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
  if self.android then
    local name = findPendingSav(true)
    if name then
      self.androidPendingVersion = version
      self:_importSave(version, name)
      if self.saveNotice[version] and self.saveNotice[version].ok then
        love.filesystem.remove(name)
      end
      return
    end
    self.androidPendingVersion = version
    if not love.system.pickFile("sav") then
      self.androidPendingVersion = nil
      self.saveNotice[version] = { ok = false,
        text = "Could not open the file picker. Copy a .sav via USB." }
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
    if love.system.createFile and love.system.createFile(suggested) then
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
  if self.android then
    -- Prefer a not-yet-imported .gb/.gbc already in the save dir (USB copy, or
    -- a fresh SAF pick).  Never reuse an already-imported cart's file -- that
    -- was the #167 failure mode (second Choose just re-extracted Red).
    local name, data = findPendingRom(self.ready)
    if name then
      self:startData(data, name)
    elseif not love.system.pickFile() then
      -- Picker unavailable (API < 19, or no document-picker app installed):
      -- fall back to the USB folder-drop path as a friendly notice, not an
      -- error (which would read as a rejected file).
      self.notice = {
        version = self.chooseVersion,
        status = "No picker available, copy your ROM into:",
        detail = love.filesystem.getSaveDirectory(),
      }
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

function RomImporter:update(dt)
  self.pulse = self.pulse + dt
  self:_updatePadCursor(dt)
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
  local w, h = love.graphics.getDimensions()
  if not self._padInited then
    self._padCursor.x = w * 0.5
    self._padCursor.y = h * 0.45
    self._padInited = true
  end
  self._padCursorActive = true
end

function RomImporter:_cycleTab(delta)
  local order = { "red", "blue", "yellow", "mods" }
  local idx = 1
  for i, id in ipairs(order) do
    if id == self.tab then idx = i; break end
  end
  idx = ((idx - 1 + delta) % #order) + 1
  self.tab = order[idx]
  self._slotPress = nil
  self._modPress = nil
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
    local w, h = love.graphics.getDimensions()
    local nx = self._padCursor.x + dx * speed * dt
    local ny = self._padCursor.y + dy * speed * dt
    self._padCursor.x = math.max(0, math.min(w, nx))
    self._padCursor.y = math.max(0, math.min(h, ny))
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
local function ellipsize(font, text, maxW)
  text = tostring(text or "")
  if maxW <= 0 or font:getWidth(text) <= maxW then return text end
  local ell = "..."
  local ew = font:getWidth(ell)
  while #text > 0 and font:getWidth(text) + ew > maxW do
    text = text:sub(1, #text - 1)
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

function RomImporter:draw()
  local width, height = love.graphics.getDimensions()
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
  self.romButtonRect = nil
  self.playButtonRect = nil
  self.tabRects = {}
  -- Rebuilt only by the active version's SAVE SLOT panel, so the mods tab (or a
  -- version with no panel drawn this frame) cannot inherit last frame's rows.
  self.slotRects = nil
  self.slotEditRects = nil
  self.newSlotRect = nil
  -- Rebuilt only by the mods panel; nil elsewhere so a game tab cannot inherit
  -- last frame's mod toggles / import button.
  self.modRects = nil
  self.modImportRect = nil
  -- Rebuilt only by the active game panel's SAVE FILES card; nil elsewhere so
  -- the mods tab cannot inherit last frame's save Import/Export/open-folder hits.
  self.saveImportRect = nil
  self.saveExportRect = nil
  self.saveFolderRect = nil

  -- Fonts + size-dependent scenery, rebuilt only when the window size changes.
  local fontKey = ("%dx%d"):format(width, height)
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
    -- match seamlessly.
    do
      local cx, cy = width / 2, 0
      local rx, ry = width * 1.3, height * 1.08
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
      local cx, cy = width / 2, height * 0.45
      local rx, ry = width * 0.78, height * 0.78
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
    self.scanlineQuad = love.graphics.newQuad(0, 0, width, height, 1, 3)
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

  -- background
  col(PAL.bgBot)
  love.graphics.rectangle("fill", 0, 0, width, height)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(self.bgMesh)

  -- Centered content container (max ~1440 scaled units on very wide windows)
  -- with a responsive side gutter; every column below derives from these.
  local appW = math.min(width, 1440 * s)
  local appX = (width - appW) / 2
  local padH = clamp(appW * 0.03, 12 * s, 26 * s)
  local third = appW / 3

  -- tricolor strip (Red | Blue | Yellow), 6px tall, with a soft downward bloom
  local stripH = math.max(4, 6 * s)
  local segs = {
    { PAL.red,  appX,             third },
    { PAL.blue, appX + third,     third },
    { PAL.gold, appX + 2 * third, appW - 2 * third },
  }
  love.graphics.setBlendMode("add")
  for _, seg in ipairs(segs) do
    fillGrad(seg[2], stripH, seg[3], stripH * 3.6, seg[1], seg[1], 0.30, 0.0)
  end
  love.graphics.setBlendMode("alpha")
  for _, seg in ipairs(segs) do
    col(seg[1]); love.graphics.rectangle("fill", seg[2], 0, seg[3], stripH)
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
  local logoY = stripH + 14 * s

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
  local contentBottom = height - footerH - bannerBand
  local cH = math.max(0, contentBottom - contentTop)

  -- Page scroll.  Everything under the tab bar -- panel, updater banner and
  -- footer -- is one column: too short a window scrolls it instead of letting
  -- the panel run under a footer pinned to the window bottom (a stacked
  -- single-column layout on a phone-shaped window overflows by a card or two).
  -- The panels report their natural height as they draw, so the decision reads
  -- the previous frame's measurement, the same one-frame settle the slot and
  -- mod lists already rely on.  While the page fits, `paged` is false and every
  -- measurement below is what it always was.
  local viewportH = math.max(0, height - contentTop)
  self._panelNaturalH = self._panelNaturalH or {}
  local naturalH = (self._panelNaturalH[self.tab] or 0) + bannerBand + footerH
  local paged, pageScroll, maxPage =
    RomImporter.pageScrollFor(naturalH, viewportH, self.pageScroll)
  self.pageScroll, self._pageMax = pageScroll, maxPage
  -- read by the hit tests; a scrolled control is live only inside the viewport
  pageBand = paged and { contentTop, height } or nil

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
  local lx, ly = (width - logoDW) / 2, logoY + bob
  love.graphics.setBlendMode("add")
  love.graphics.setColor(1, 0.85, 0.2, 0.16 + 0.12 * (0.5 + 0.5 * math.sin(pulse * 1.6)))
  love.graphics.draw(self.logo, (width - logoDW * 1.05) / 2, ly - logoDH * 0.025, 0,
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
    love.graphics.rectangle("fill", 0, 0, width, height)
    local dw = math.min(appW - 32 * s, 420 * s)
    local dh = 128 * s
    local dx = appX + (appW - dw) / 2
    local dy = (height - dh) / 2
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

  -- pointer cursor over any interactive element (desktop only)
  if self._hoverEnabled and not self._padCursorActive
      and love.mouse.isCursorSupported and love.mouse.isCursorSupported() then
    if self._anyHover then
      self.handCursor = self.handCursor or love.mouse.getSystemCursor("hand")
      love.mouse.setCursor(self.handCursor)
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

function RomImporter:mousepressed(x, y, button)
  if self._rename then return end -- the rename modal swallows all clicks
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
  -- SAVE SLOT rows / Edit / Delete.  The two labels are checked first so a tap
  -- on either never also selects the row.  A press only ARMS a row click:
  -- _updateSlotDrag commits it on release when the pointer did not move (a
  -- moved pointer scrolls instead).  Android arms too wherever love.touch can
  -- be polled; without that there is nothing to resolve a release with, so it
  -- keeps selecting on press.  Edit and Delete fire immediately (small fixed
  -- targets, no scroll conflict).
  for _, r in ipairs(self.slotDeleteRects or {}) do
    if inside(r, x, y) then
      self:_deleteSlot(self.panelVersion, r.id)
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
  for _, r in ipairs(self.modDeleteRects or {}) do
    if inside(r, x, y) then
      self:_deleteMod(r.id)
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

  -- vertical placement of the left column
  local romY = bodyTop
  local saveFilesY = romY + romCardH + 12 * s
  local leftNaturalH = romCardH + 12 * s + saveFilesH + 12 * s + playH
  local playY
  if twoCol and not paged then
    playY = bodyTop + bodyH - playH        -- pinned to the column's bottom
  else
    playY = saveFilesY + saveFilesH + 12 * s
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

function RomImporter:_beginRename(version, id)
  local label
  for _, slot in ipairs(self.slots[version] or {}) do
    if slot.id == id then label = slot.label break end
  end
  self._rename = { version = version, id = id, text = label or "" }
  self._slotPress = nil -- cancel any armed click/drag on the list
end

function RomImporter:_commitRename()
  local r = self._rename
  if not r then return end
  self._rename = nil
  require("src.core.SaveData").renameSlot(r.version, r.id, r.text)
  self:_refreshSlots(r.version)
end

function RomImporter:textinput(text)
  if not self._rename then return end
  self._rename.text = utf8Cap(self._rename.text .. text, MAX_SLOT_LABEL)
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
  local rowH = rowPadV * 2 + nameH + 4 * s + metaH
  local rowGap = 8 * s
  local rr = 12 * s
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

        -- Delete label (bottom-right); reserve its width so name/meta don't overlap
        love.graphics.setFont(self.hintFont)
        local delText = "Delete"
        local delW = self.hintFont:getWidth(delText)
        local delH = self.hintFont:getHeight()
        local delX = rx + rw - 12 * s - delW
        local delY = ry + rowH - rowPadV - delH
        local drect = { x = delX - 6 * s, y = delY - 4 * s,
          width = delW + 12 * s, height = delH + 8 * s, id = slot.id }
        local dhot = self:_hover(drect)
        col(dhot and PAL.red or PAL.warning)
        love.graphics.print(delText, delX, delY)
        local rightReserve = delW + 18 * s

        -- Edit label, immediately left of Delete: opens the bundled save
        -- editor (tools/save-editor) on this slot's file.  Only drawn when the
        -- host supplied onEditSave and the slot actually holds a save -- there
        -- is nothing to edit in an empty slot, and offering it would open the
        -- editor on a new-game stub the player never asked for.
        local erect = nil
        if self.onEditSave and slot.exists then
          local edText = "Edit"
          local edW = self.hintFont:getWidth(edText)
          local edX = delX - 14 * s - edW
          erect = { x = edX - 6 * s, y = delY - 4 * s,
            width = edW + 12 * s, height = delH + 8 * s, id = slot.id }
          local ehot = self:_hover(erect)
          col(ehot and PAL.blue or PAL.warning)
          love.graphics.print(edText, edX, delY)
          rightReserve = rightReserve + edW + 20 * s
        end

        -- LOADED pill (top-right of the active row), then reserve its width
        local pillW = 0
        if selected then
          love.graphics.setFont(self.warningFont)
          local pText = "LOADED"
          local pw = self.warningFont:getWidth(pText) + 14 * s
          local ph = self.warningFont:getHeight() + 6 * s
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
end

function RomImporter:_ensureMods()
  if not self.mods then self:_refreshMods() end
end

-- Flip a mod's enabled flag (persisted via LauncherMods.setEnabled) and relist
-- so the toggle, count, and every status chip reflect the new resolution.
function RomImporter:_toggleMod(id)
  local LauncherMods = require("src.mods.LauncherMods")
  local cur = false
  for _, m in ipairs(self.mods or {}) do
    if m.id == id then cur = m.enabled; break end
  end
  LauncherMods.setEnabled(id, not cur)
  self:_refreshMods()
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
  love.graphics.print(Strings("%d of %d enabled", enabledCount, #mods),
    x + nameW + 14 * s, y + (headerH - self.hintFont:getHeight()) / 2)

  local btnLabel = "Import mod .zip"
  local btnH = math.max(38 * s, self.saveBtnFont:getHeight() + 20 * s)
  local btnW = math.min(w * 0.5, self.saveBtnFont:getWidth(btnLabel) + 40 * s)
  local btnX = x + w - btnW
  local btnY = y + (headerH - btnH) / 2
  self.modImportRect =
    self:_glassyButton(btnX, btnY, btnW, btnH, btnLabel, self.saveBtnFont, true)

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
    self._modMax = 0
    return (top - y) + boxH
  end

  -- card metrics (design: rounded 14, padding 14x16; toggle 56x28; Delete under)
  local padH, padV = 16 * s, 14 * s
  local cardGap, cardR = 10 * s, 14 * s
  local tw, th = 52 * s, 28 * s
  local innerW = w - 2 * padH
  local chipH = self.hintFont:getHeight() + 8 * s
  local delH = self.hintFont:getHeight()
  local clusterH = chipH + 6 * s + th + 6 * s + delH

  love.graphics.setFont(self.stateFont)
  local nameH = self.stateFont:getHeight()

  -- pre-pass: per-card layout + total height, so scroll can clamp to content
  local layout, total = {}, 0
  for i, m in ipairs(mods) do
    local chipText = modStatusChip(m.status)
    local chipW = self.hintFont:getWidth(chipText) + 20 * s
    local delW = self.hintFont:getWidth("Delete")
    local clusterW = math.max(chipW, tw, delW)
    local leftW = math.max(40 * s, innerW - clusterW - 14 * s)
    local descH = 0
    if m.description ~= "" then
      love.graphics.setFont(self.hintFont)
      local _, dl = self.hintFont:getWrap(m.description, leftW)
      descH = math.max(1, #dl) * self.hintFont:getHeight()
    end
    local contentH = padV * 2 + nameH + (descH > 0 and (6 * s + descH) or 0)
    local cardH = math.max(contentH, padV * 2 + clusterH)
    layout[i] = { h = cardH, leftW = leftW, clusterW = clusterW,
      chipText = chipText, chipW = chipW, delW = delW }
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
      col(PAL.warning)
      love.graphics.print(m.badge, bxx + 6 * s,
        byy + (badgeH - self.warningFont:getHeight()) / 2)

      -- description under the name, wrapped in the left block
      if m.description ~= "" then
        love.graphics.setFont(self.hintFont)
        col(PAL.detail)
        love.graphics.printf(m.description, nx, ny + nameH + 6 * s, L.leftW, "left")
      end

      -- right cluster: status chip, toggle, Delete -- vertically centred
      local clusterX = x + w - padH - L.clusterW
      local clusterY = cy + (cardH - clusterH) / 2
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

      -- Delete under the toggle
      local delX = clusterX + (L.clusterW - L.delW) / 2
      local delY = ty + th + 6 * s
      local drect = { x = delX - 6 * s, y = delY - 2 * s,
        width = L.delW + 12 * s, height = delH + 4 * s, id = m.id }
      local dhot = self:_hover(drect)
      love.graphics.setFont(self.hintFont)
      col(dhot and PAL.red or PAL.warning)
      love.graphics.print("Delete", delX, delY)

      -- hit rects clipped to the visible list band
      local vy = math.max(trect.y, top)
      local vy2 = math.min(trect.y + trect.height, top + listH)
      if vy2 > vy then
        self.modRects[#self.modRects + 1] =
          { x = trect.x, y = vy, width = trect.width, height = vy2 - vy, id = m.id }
      end
      local dvy = math.max(drect.y, top)
      local dvy2 = math.min(drect.y + drect.height, top + listH)
      if dvy2 > dvy then
        self.modDeleteRects[#self.modDeleteRects + 1] =
          { x = drect.x, y = dvy, width = drect.width, height = dvy2 - dvy, id = m.id }
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

return RomImporter
