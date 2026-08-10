-- Save/load via love.filesystem.  Game progress lives in save.lua;
-- Options (audio, display, battle preferences) live in a separate
-- options.lua so they survive New Game and aren't tied to a save slot.
-- Both are plain Lua tables serialized as Lua source (deterministic
-- key order) and read back through SaveSerializer's data-only parser,
-- so a save can never execute code.
--
-- The load pipeline is read -> parse -> migrate -> validate/quarantine
-- -> restore; Game:restoreSave drives the last two phases with the
-- merged Data threaded in, because this module must not reach into
-- Data itself.

local Logger = require("src.core.Logger")
local Version = require("src.core.Version")
local SaveSerializer = require("src.core.SaveSerializer")
local Runtime = require("src.mods.Runtime")
local Semver = require("src.mods.Semver")
local Boxes = require("src.pokemon.Boxes")
local Stats = require("src.pokemon.Stats")
local Bag = require("src.inventory.Bag")
local Badges = require("src.inventory.Badges")

local GameVersion = require("src.core.GameVersion")

local SaveData = {}

-- Progress files carry the game-version suffix so Red / Blue / Yellow saves
-- coexist: Red keeps save.lua / .bak / .tmp exactly as before; Blue is
-- save_blue.lua and Yellow is save_yellow.lua (+ .bak/.tmp).  options.lua is
-- deliberately shared across versions (it holds global preferences and the
-- mod enable-state, not per-playthrough data).
local OPTIONS_FILENAME = "options.lua"
-- #828: options.lua is rewritten whole on every write (see saveOptions), and
-- unlike the progress files it had no staged copy, so a write interrupted
-- between the truncate and the flush -- the process replaced by
-- HostShell.restart on the way back to the launcher, an Android
-- external-storage volume that never flushed -- left a truncated or empty
-- file that loadOptions could only answer with defaults: every setting
-- "reset" at once.  Same .bak/.tmp witness names the save files use.
local OPTIONS_BACKUP_FILENAME = OPTIONS_FILENAME .. ".bak"
local OPTIONS_TMP_FILENAME = OPTIONS_FILENAME .. ".tmp"

-- Main / backup / staged-witness names for a version (defaults to the active
-- one).  The backup is a rolling copy and .tmp is the staged-write witness;
-- load promotes either when the main file is missing or fails to parse.
-- Forward-declared here so saveFilename (just below) and every save/load
-- caller share the one upvalue; the body is filled in under "save slots"
-- once the options IO it depends on exists, because it now resolves the
-- ACTIVE slot for a version rather than the fixed flat name.
local saveNames

-- The main save filename for a version -- used by the title screen's
-- CONTINUE gate so it looks for the right game's save.
function SaveData.saveFilename(version)
  local main = saveNames(version)
  return main
end

-- ------- portable mode
-- LÖVE's save directory is always the OS per-user path derived from the
-- identity (conf.lua), so it can't be relocated at runtime. Portable mode
-- instead drops a plain-Lua io.* filesystem next to the game whenever a
-- `portable.txt` marker sits beside the executable/source, letting a USB
-- copy carry its own save.lua/options.lua (and, through options.lua, the
-- mod enable-state) rather than leaving them on the host machine.
local PORTABLE_MARKER = "portable.txt"
local SEP = package.config:sub(1, 1)

local portableChecked = false
local portableBase = false      -- resolved base dir when active, else false
local portableFsCache = nil

local function pathExists(path)
  local f = io.open(path, "rb")
  if not f then return false end
  f:close()
  return true
end

-- an io.* filesystem exposing the love.filesystem subset the save/options
-- round-trip needs (getInfo/read/write/remove), rooted at `dir`
local function makePortableFs(dir)
  local function full(name) return dir .. SEP .. name end
  return {
    getInfo = function(name)
      if not pathExists(full(name)) then return nil end
      return { type = "file" }
    end,
    read = function(name)
      local f = io.open(full(name), "rb")
      if not f then return nil, "no file: " .. name end
      local data = f:read("*a")
      f:close()
      return data
    end,
    write = function(name, data)
      local f, err = io.open(full(name), "wb")
      if not f then return false, err end
      f:write(data)
      f:close()
      return true
    end,
    remove = function(name)
      os.remove(full(name))
      return true
    end,
    createDirectory = function(name)
      -- portable mode writes real files through io.*, which will not
      -- create missing parent directories; mkdir the tree so a slot path
      -- like "saves/red" exists before a write lands inside it
      local osPath = full(name):gsub("/", SEP)
      if SEP == "\\" then
        os.execute('mkdir "' .. osPath .. '" 2>nul')
      else
        os.execute('mkdir -p "' .. osPath .. '" 2>/dev/null')
      end
      return true
    end,
  }
end

-- Every folder a player might reasonably call "the game folder", best first:
-- the packaged-app container, the folder holding the executable, then the
-- source itself.  Portable mode is the case where one of these holds the
-- marker; the list itself is just locations, marker or not, which is also
-- what the mods panel needs to notice a mod dropped beside the game by hand
-- (LauncherMods.strays).  Empty on Android/iOS and outside LOVE.
function SaveData.gameFolders()
  if not (love and love.filesystem) then return {} end
  -- Desktop only: portable mode carries the save (and, since issue #74, the
  -- ROM cache) in the game folder next to the executable/source.  On
  -- Android/iOS the source is a read-only package with no such folder, so
  -- portable mode never applies there.
  if love.system and love.system.getOS then
    local osName = love.system.getOS()
    if osName ~= "Windows" and osName ~= "Linux" and osName ~= "OS X" then
      return {}
    end
  end
  local src = love.filesystem.getSource and love.filesystem.getSource()
  local sbd = love.filesystem.getSourceBaseDirectory
    and love.filesystem.getSourceBaseDirectory()
  -- A packaged macOS build nests the game inside gen1recomp.app/Contents/
  -- Resources, so getSource()/getSourceBaseDirectory() point INSIDE the
  -- bundle -- not where the player drops portable.txt (next to the .app).
  -- Recover the folder containing the .app so a packaged app finds its
  -- marker.  On Windows/Linux the executable is not a bundle, so this is nil
  -- and the plain source-base directory (next to the .exe/AppImage) is used.
  local function parentDir(path)
    return path and path:match("^(.*)/[^/]+$") or nil
  end
  local function appContainer(path)
    return parentDir(path and path:match("^(.*%.app)/Contents/"))
  end
  -- The Linux AppImage build works similarly to macOs, but the runtime mounts
  -- the squashfs at a temp path, and that becomes the base directory.
  -- The runtime exports the real .AppImage path in $APPIMAGE, so we get the
  -- base dir from there.
  local function appImageContainer()
    return parentDir(os.getenv("APPIMAGE"))
  end
  -- Order: the packaged-app containing folder (macOS .app / Linux AppImage),
  -- then the source-base directory (next to a packaged .exe), then the source
  -- itself (a `love <gamedir>` run drops portable.txt in the game folder).
  -- Built by appending so a nil (e.g. no .app in the path) never truncates
  -- the ipairs scan.
  local candidates = {}
  local appDir = appContainer(src) or appContainer(sbd) or appImageContainer()
  if appDir then candidates[#candidates + 1] = appDir end
  if sbd and sbd ~= "" then candidates[#candidates + 1] = sbd end
  if src and src ~= "" then candidates[#candidates + 1] = src end
  return candidates
end

-- The game folder carrying portable.txt, or false.  First candidate holding
-- the marker wins.
local function detectPortable()
  if portableChecked then return portableBase end
  portableChecked = true
  portableBase = false
  for _, base in ipairs(SaveData.gameFolders()) do
    if pathExists(base .. SEP .. PORTABLE_MARKER) then
      portableBase = base
      break
    end
  end
  return portableBase
end

function SaveData.isPortable()
  return detectPortable() ~= false
end

-- the raw portable-folder path (for callers building their own nested
-- paths, e.g. the ROM-derived asset cache), or nil when portable mode
-- is off
function SaveData.portableBaseDir()
  return detectPortable() or nil
end

-- the io.* filesystem for the active portable folder, or nil when off
function SaveData.portableFs()
  local base = detectPortable()
  if not base then return nil end
  if not portableFsCache then portableFsCache = makePortableFs(base) end
  return portableFsCache
end

-- Resolve the filesystem a persistent read/write should land on: an
-- explicitly injected non-love fs (headless tests, the mod loader's stub)
-- always wins; otherwise portable mode reroutes off the OS save directory.
local function persistFs(fs)
  if fs and love and love.filesystem and fs ~= love.filesystem then
    return fs
  end
  return SaveData.portableFs() or fs or (love and love.filesystem)
end

-- Engine-owned persistence routing for subsystems that must follow the same
-- standard/portable root as saves without exposing raw filesystem access to a
-- mod. An explicitly injected headless filesystem still wins for tests.
function SaveData.persistenceFs(fs)
  return persistFs(fs)
end

-- Port + original Options menu defaults.  Missing keys on load are filled
-- from this table so old options.lua files stay compatible.
function SaveData.defaultOptions()
  return {
    -- textSpeed 3 = MEDIUM, matching InitOptions' TEXT_DELAY_MEDIUM
    -- in wOptions (engine/menus/main_menu.asm)
    textSpeed = 3,
    animations = true,
    battleStyle = "shift",
    -- battle screen composition: og (the 160x144 original) | wide
    -- (304x144, src/battle/WideBattle.lua)
    battleLayout = "og",
    -- BATTLE SIZE: "fixed" = the classic integer-scaled letterbox; "fill" =
    -- scale the battle surface to the window so it fills vertically.  See
    -- BattleState:wantsFillScale.
    battleFit = "fixed",
    -- BATTLE BG: what fills the screen behind and around the battle.
    -- "white" = the display mode's paper shade (the classic look),
    -- "black" = plain black bars, "world" = the frozen overworld showing
    -- through, dimmed.  See BattleState:bgMode.
    battleBg = "white",
    -- UI LAYOUT: "centered" = a fixed letterbox.  Every element sits where it
    -- was drawn in the 160x144 canvas and the UI does not follow the survey
    -- zoom, so nothing moves or resizes under the player.  The original
    -- composition.  "dynamic" = the dialogue box docks to the window's bottom
    -- edge, the START menu to its top right, and the UI steps down with the
    -- zoom.  Centered is the default: dynamic reads better zoomed out, but it
    -- moves the screen furniture, so it is opt-in.
    -- See Game.dynamicUI, Renderer:setUIAnchor and Renderer:uiScale.
    uiLayout = "centered",
    ruleset = "gen1_faithful",
    -- 0-7 like the GB's NR50 master volume
    musicVol = 7,
    sfxVol = 7,
    -- Yellow only: 0-7 trim for Pikachu's PCM voice clips on top of sfxVol
    -- (the PIKACHU VOL row appears only on Yellow; see Sound.lua)
    pikaVol = 7,
    musicFilter = 0,
    -- Per-category logic fast-forward multiplier (RFC 0007); audio is
    -- unaffected (GameSpeed.lua). Superseded from a single "speed" field --
    -- mergeOptions migrates an old save's value into all three below.
    speedOverworld = 1,
    speedBattle = 1,
    speedMenu = 1,
    -- port display options (OptionsMenu / hotkeys 2/3/4/5)
    colors = "gbc",
    tilt = 0,
    gbcfx = 0,
    -- survey zoom offset from window fit scale (0 = FIT); see Zoom.lua
    zoom = 0,
    -- OVERWORLD beyond-edge fill: trees | water | black
    voidFill = "trees",
    -- windowed | borderless (desktop fullscreen); ignored on mobile
    videoMode = "windowed",
    -- lock the window to an exact 160x144 multiple, 1..4 (0 = OFF); see
    -- src/core/FaithfulRes.lua.  Ignored on mobile.
    faithfulRes = 0,
    -- hard render frame-rate cap; render-only pacing (issue #88, FrameCap.lua)
    fpsCap = 60,
    -- graphics performance tier: auto | high | balanced | low.  "auto"
    -- picks a default from the device (ARM handhelds/phones drop the heavy
    -- extras); scales TILT / GBC FX / survey ZOOM / FPS but never game
    -- logic.  See src/core/Performance.lua.
    performance = "auto",
    -- Per-pipeline display levels, keyed by render_pipelines id (see
    -- src/render/Pipelines.lua).  A level for a mod that is not installed
    -- is kept rather than pruned, so re-enabling the mod restores the mode
    -- the player left it in.
    pipelines = {},
    -- Native mod enablement is an installation option, not save-slot data.
    -- Missing entries mean enabled so newly installed mods work by default.
    mods = {},
    -- Named setups the player can switch between (#593; src/mods/ModProfile.lua
    -- owns the shape, src/mods/ManagerState.lua the UI): each row is
    -- { name, enabled = {id=bool}, options = {id={k=v}}, slots = {version=slotId} }.
    -- activeProfile names the row the live set currently matches (nil for
    -- ad-hoc, so it has no default entry here; mergeOptions preserves it).
    -- modProfilesSeeded records that the pre-profiles setup was already
    -- migrated into PROFILE 1, so deleting every profile does not re-seed one.
    modProfiles = {},
    modProfilesSeeded = false,
    -- GitHub release checks for mods with a manifest "github" field
    -- (src/mods/ModUpdate.lua). Keyed by owner/repo; TTL is six hours.
    modUpdateCache = {},
    -- Community mod indexes the player has chosen to browse
    -- (src/mods/ModIndex.lua), in the order they added them.  Empty by
    -- default and never populated automatically: adding an index is how a
    -- player says they trust whoever publishes it, so the launcher asks
    -- rather than shipping one.  Rows are { url, feed, base, fallback,
    -- label }.
    modIndexes = {},
    -- Parsed index listings keyed by feed URL; TTL is 24 hours, matching how
    -- often the feeds themselves rebuild.
    modIndexCache = {},
    -- On-screen touch overlay (Android/iOS; see src/core/TouchControls.lua).
    -- enabled=false hides it permanently (distinct from auto-hide-on-gamepad).
    -- layouts.portrait / layouts.landscape each hold optional normalized
    -- centers {x=0..1, y=0..1} per control (dpad/a/b/start/select) plus a
    -- size scale; nil positions mean that orientation draws the default
    -- layout (#633).  Pre-#633 files stored one top-level positions table;
    -- TouchControls.normalizeConfig folds it into both orientations on load.
    touchControls = { enabled = true },
    -- Haptic feedback level for on-screen pad presses (#806):
    -- off | light | medium | heavy, mapped to a love.system.vibrate
    -- duration in src/core/TouchControls.lua.  LIGHT by default, like the
    -- overlay itself defaulting on, so an options.lua predating this key
    -- gets the tick without going looking for the row.  Inert wherever the
    -- overlay never appears (desktop) or LOVE has no vibrator.
    haptics = "light",
  }
end

-- Merge loaded keys over defaults (shallow).  Unknown keys are kept so
-- future options aren't dropped by older builds writing the file back.
function SaveData.mergeOptions(loaded)
  local opts = SaveData.defaultOptions()
  if type(loaded) == "table" then
    for k, v in pairs(loaded) do
      opts[k] = v
    end
    -- RFC 0007 migration: a save from before per-category GAME SPEED still
    -- has a single "speed" and none of the three new fields, so seed all
    -- three from it -- an existing player's fast-forward preference
    -- carries over instead of two of the three categories silently
    -- resetting to 1X. "speed" is dropped on the way out (not kept as a
    -- stale alias), so a re-save never re-triggers this migration.
    if loaded.speed ~= nil and loaded.speedOverworld == nil
        and loaded.speedBattle == nil and loaded.speedMenu == nil then
      opts.speedOverworld = loaded.speed
      opts.speedBattle = loaded.speed
      opts.speedMenu = loaded.speed
    end
    opts.speed = nil
  end
  return opts
end

function SaveData.encode(data)
  return SaveSerializer.encode(data)
end

function SaveData.decode(str)
  return SaveSerializer.decode(str)
end

local function readTable(fs, name)
  if not fs.getInfo(name) then return nil, "no file: " .. name end
  local body = fs.read(name)
  if type(body) ~= "string" then return nil, "unreadable: " .. name end
  return SaveSerializer.decode(body)
end

-- Deep-copy a value folded in from the on-disk decode so the returned
-- options table never aliases the file's nested tables (SaveData must not
-- depend on src/mods/Merge.lua for this).  Options data is plain tables of
-- strings/numbers/booleans/tables, so a cycle guard is belt-and-braces.
local function deepCopy(v, seen)
  if type(v) ~= "table" then return v end
  seen = seen or {}
  if seen[v] then return seen[v] end
  local copy = {}
  seen[v] = copy
  for k, val in pairs(v) do
    copy[deepCopy(k, seen)] = deepCopy(val, seen)
  end
  return copy
end

-- the stub filesystem some headless harnesses inject has no remove; a
-- lingering tmp/bak there is harmless
local function remove(fs, name)
  if fs.remove then fs.remove(name) end
end

-- ------- options

-- Both take an optional fs (write/getInfo/read) defaulting to
-- love.filesystem, so the mod loader's injected filesystem can carry the
-- options round-trip headless (no love global).
function SaveData.saveOptions(opts, fs)
  fs = persistFs(fs)
  -- #932: options.lua is a WHOLE-FILE rewrite, so a caller that hands over a
  -- PARTIAL table (just the keys it changed) would silently drop every key it
  -- does not mention -- launcher-only keys like lastVersion, and keys the
  -- launcher set (battleBg, tilt...) all fall back to defaults.  Read the
  -- on-disk file FIRST and fold caller-absent values underneath, so a delta
  -- write changes only what it names.
  --
  -- A table holding EVERY defaultOptions key is a full snapshot
  -- (loadOptions() results, game.save.options, the RESET REBINDS /
  -- activeProfile-drop paths) and stays authoritative: its absent keys are
  -- deliberate deletions, so nothing folds for it.  Partial tables get every
  -- on-disk key they do not provide folded in (deep-copied so the caller's
  -- table is never aliased).  This is the reconciling rule: bindings and
  -- activeProfile -- not defaultOptions members -- can be deleted by their
  -- sites precisely because those sites always write full tables.
  local onDisk = readTable(fs, OPTIONS_FILENAME)
  local isFull = type(opts) == "table"
  if isFull then
    for k in pairs(SaveData.defaultOptions()) do
      if opts[k] == nil then isFull = false break end
    end
  end
  if not isFull then
    local merged = {}
    if type(opts) == "table" then
      for k, v in pairs(opts) do merged[k] = v end
    end
    if type(onDisk) == "table" then
      for k, v in pairs(onDisk) do
        if k ~= "modOptions" and merged[k] == nil then
          merged[k] = deepCopy(v)
        end
      end
    end
    opts = merged
  end
  opts = SaveData.mergeOptions(opts)
  -- modOptions is per-mod nested state: fold the on-disk sub-tree
  -- underneath (newest value winning per key) so one caller's partial
  -- write cannot clobber another mod's persisted keys.  Every other
  -- option stays on the shallow path.
  if type(onDisk) == "table" and type(onDisk.modOptions) == "table" then
    local merged = {}
    for modId, bucket in pairs(onDisk.modOptions) do
      merged[modId] = bucket
    end
    for modId, bucket in pairs(opts.modOptions or {}) do
      if type(bucket) == "table" and type(merged[modId]) == "table" then
        for k, v in pairs(bucket) do merged[modId][k] = v end
      else
        merged[modId] = bucket
      end
    end
    opts.modOptions = merged
  end
  local encoded = SaveSerializer.encode(opts)
  -- Stage the new bytes and roll the last good file aside BEFORE the main
  -- write truncates it, the same tmp/bak dance SaveData.save uses for
  -- progress: whatever ends the process mid-write, one of the three copies
  -- is complete and loadOptions promotes it instead of falling back to
  -- defaults (#828).
  local ok, err = fs.write(OPTIONS_TMP_FILENAME, encoded)
  if not ok then
    Logger.error("options save failed: %s", tostring(err))
    return nil
  end
  local prev = fs.getInfo(OPTIONS_FILENAME) and fs.read(OPTIONS_FILENAME)
  if type(prev) == "string" and prev ~= "" and prev ~= encoded then
    fs.write(OPTIONS_BACKUP_FILENAME, prev)
  end
  ok, err = fs.write(OPTIONS_FILENAME, encoded)
  if not ok then
    Logger.error("options save failed: %s", tostring(err))
    return nil
  end
  -- #828: settings "reset" on Android and Steam Deck with nothing in the log.
  -- Every options write is a WHOLE-FILE rewrite, so a write that reports
  -- success without the bytes landing (an external-storage volume that went
  -- away mid-session, a read-only or full save dir) is indistinguishable from
  -- "the launcher never saved".  Read the file back and fail loudly instead:
  -- callers already treat nil as a failed write, and the log line is what the
  -- next report from those platforms needs to carry.
  local wrote = fs.getInfo(OPTIONS_FILENAME) and fs.read(OPTIONS_FILENAME)
  if wrote ~= encoded then
    Logger.error("options save did not land (%d bytes written, %s on disk)",
      #encoded, type(wrote) == "string" and tostring(#wrote) or "nothing")
    return nil
  end
  -- #828: roll the backup FORWARD to the bytes just verified.  The
  -- pre-write roll above only preserves the previous file for a death
  -- during this rewrite; at rest the backup must hold the newest verified
  -- state, because the hard teardown out of a game session (HostShell's
  -- restartApp kill on Android, execv on a SteamOS AppImage) can eat the
  -- main file outright and loadOptions then promotes this copy.  The
  -- encoder is key-sorted, so the follow-up rewrites a play session makes
  -- (play()'s lastVersion stamp, the in-game save flush) are byte-identical
  -- and skip the conditional roll -- without this line the backup still
  -- held the file from BEFORE the launcher's change, and recovery reverted
  -- the just-changed setting (BATTLE LAYOUT back to OG).
  fs.write(OPTIONS_BACKUP_FILENAME, encoded)
  -- the staged witness has served its purpose; the main file is verified
  remove(fs, OPTIONS_TMP_FILENAME)
  return opts
end

function SaveData.loadOptions(fs)
  fs = persistFs(fs)
  local data, err = readTable(fs, OPTIONS_FILENAME)
  if not data then
    if fs.getInfo(OPTIONS_FILENAME) then
      Logger.error("options load failed: %s", tostring(err))
    end
    -- #828: answering defaults here is what "closing the game reset all my
    -- settings" looked like -- one interrupted whole-file rewrite and every
    -- preference, the mod enable-state and the slot registry were gone.
    -- Promote the staged copy, then the rolled-aside backup, exactly as
    -- SaveData.load does for progress, and heal the main file from whichever
    -- one parsed.
    local recovered = readTable(fs, OPTIONS_TMP_FILENAME)
    local from = "tmp"
    if not recovered then
      recovered = readTable(fs, OPTIONS_BACKUP_FILENAME)
      from = "bak"
    end
    if recovered then
      Logger.warn("options.lua %s; recovered from %s copy",
        fs.getInfo(OPTIONS_FILENAME) and "corrupt" or "missing", from)
      if fs.write then
        fs.write(OPTIONS_FILENAME, SaveSerializer.encode(recovered))
      end
      return SaveData.mergeOptions(recovered)
    end
    return SaveData.defaultOptions()
  end
  return SaveData.mergeOptions(data)
end

-- ------- save slots

-- A version's playthroughs live in numbered slots under saves/<version>/;
-- the active slot is where in-game SAVE and CONTINUE land.  The registry
-- (the ordered slot list plus which one is active) persists in options.lua
-- under options.saveSlots[version]; the active slot is also cached
-- process-wide (like GameVersion.current) so the hot saveNames path does
-- not re-read options every call.  A false cache entry means "no slot in
-- use" and the flat legacy path (save.lua / save_blue.lua / save_yellow.lua)
-- is used, which keeps a brand-new install and every pre-slots caller
-- working unchanged.
local activeSlotCache = {}   -- version -> slotId in use, or false when none
local slotsChecked = {}      -- version -> true once resolved this process
-- At most one New Game can be the live candidate for a first public tool
-- request. A single strong reference models that runtime fact without adding
-- marker data to the save or retaining abandoned playthrough tables.
local freshPlaythrough

local function slotDir(version) return "saves/" .. version end

local function slotNames(version, id)
  local main = slotDir(version) .. "/" .. id .. ".lua"
  return main, main .. ".bak", main .. ".tmp"
end

-- the pre-slots flat names a version always used (save.lua for Red,
-- save_blue.lua / save_yellow.lua for the others); still the destination
-- before any slot exists
local function legacyNames(version)
  local main = "save" .. GameVersion.saveSuffix(version) .. ".lua"
  return main, main .. ".bak", main .. ".tmp"
end

-- Slot resolution is only meaningful for versions GameVersion actually knows
-- (red / blue / yellow).  An unknown id has no info entry and therefore no
-- saveSuffix; resolving its legacy names would index a nil info table and
-- crash.  Treat any unknown version as having no slots so the slot APIs
-- degrade to empty/no-op instead.
local function knownVersion(version)
  return GameVersion.info(version) ~= nil
end

-- Create the parent directory of a slot path when the fs supports it.
-- love.filesystem.createDirectory makes the whole tree; the injected memfs
-- stub keys files by full path and exposes no such method, so this is a
-- no-op there.
local function ensureParentDir(fs, name)
  local dir = name:match("^(.*)/[^/]+$")
  if dir and fs.createDirectory then fs.createDirectory(dir) end
end

-- Decode a slot's save using the same recovery order load() uses -- main,
-- then the .tmp write-witness, then the .bak -- so a slot mid-crash still
-- summarizes.  nil when nothing readable is present.
local function decodeSlot(fs, version, id)
  local main, bak, tmp = slotNames(version, id)
  local data = fs.getInfo(main) and SaveSerializer.decode(fs.read(main) or "")
  if data then return data end
  data = fs.getInfo(tmp) and SaveSerializer.decode(fs.read(tmp) or "")
  if data then return data end
  data = fs.getInfo(bak) and SaveSerializer.decode(fs.read(bak) or "")
  return data or nil
end

-- One-time legacy consolidation: a pre-slots install has a flat save file
-- (+ .bak) and no saves/<version>/ registry.  Copy both into slot1, verify
-- the copy reads back, then remove the originals and register slot1 as the
-- active slot.  Returns the new slot id, or nil when there is nothing to
-- migrate or the copy could not be verified (originals left in place so no
-- data is ever lost to a failed move).
local function tryMigrateLegacy(version, fs)
  local lmain, lbak, ltmp = legacyNames(version)
  local mainBody = fs.getInfo(lmain) and fs.read(lmain)
  local bakBody = fs.getInfo(lbak) and fs.read(lbak)
  if not (mainBody or bakBody) then return nil end
  local id = "slot1"
  local dmain, dbak = slotNames(version, id)
  ensureParentDir(fs, dmain)
  if mainBody then fs.write(dmain, mainBody) end
  if bakBody then fs.write(dbak, bakBody) end
  -- refuse to delete the originals unless the new slot is loadable (from
  -- the main copy or, failing that, the backup)
  if not decodeSlot(fs, version, id) then return nil end
  remove(fs, lmain)
  remove(fs, lbak)
  remove(fs, ltmp)
  local opts = SaveData.loadOptions(fs)
  opts.saveSlots = opts.saveSlots or {}
  opts.saveSlots[version] = { list = { id }, active = id }
  SaveData.saveOptions(opts, fs)
  return id
end

-- Resolve (once per version per process) which slot in-game saves use: an
-- existing registry wins; otherwise a lazy legacy migration may create
-- slot1; otherwise false, meaning the flat legacy path.
local function ensureVersionSlots(version, fs)
  if slotsChecked[version] then return end
  slotsChecked[version] = true
  if not knownVersion(version) then
    activeSlotCache[version] = false
    return
  end
  local opts = SaveData.loadOptions(fs)
  local reg = opts.saveSlots and opts.saveSlots[version]
  if reg and type(reg.list) == "table" and #reg.list > 0 then
    activeSlotCache[version] = reg.active or reg.list[1]
    return
  end
  activeSlotCache[version] = tryMigrateLegacy(version, fs) or false
end

-- (body for the forward-declared saveNames.)  Resolves the ACTIVE slot for
-- the version, falling back to the flat legacy names when no slot is in use.
function saveNames(version)
  version = version or GameVersion.get()
  local fs = persistFs(nil)
  ensureVersionSlots(version, fs)
  local slot = activeSlotCache[version]
  if slot then return slotNames(version, slot) end
  return legacyNames(version)
end

-- Pure extraction of the launcher's per-slot summary from a decoded save,
-- factored out so it is unit-testable with no filesystem: the player name
-- (nil for an empty slot) and { badges, timeText, dexCount } -- the same
-- fields the title screen's ContinueInfo derives.  Badges resolve against
-- the vanilla gym list (launcher has no loaded Data), which is what the
-- flat launcher meta line needs.
function SaveData.slotSummary(save)
  if type(save) ~= "table" then return nil, nil end
  local name = save.player and save.player.name or nil
  local dexCount = 0
  for _ in pairs((save.pokedex and save.pokedex.owned) or {}) do
    dexCount = dexCount + 1
  end
  local t = math.floor(save.playTime or 0)
  local timeText = ("%d:%02d"):format(math.floor(t / 3600),
                                      math.floor(t / 60) % 60)
  return name, {
    badges = Badges.count(nil, save),
    timeText = timeText,
    dexCount = dexCount,
  }
end

-- The absolute on-disk path of a slot's save file, for the one caller that
-- cannot go through love.filesystem: the save editor reads and writes with
-- raw io.* so it can also open a file the player dragged in from anywhere.
-- Resolves against the same root persistFs would write to -- the portable
-- game folder when portable mode is on, otherwise LOVE's save directory --
-- so Edit on a launcher save row lands on the file the game actually plays.
-- nil when neither root is available (headless tests with an injected fs).
function SaveData.slotDiskPath(version, slotId)
  version = version or GameVersion.get()
  if not knownVersion(version) or not slotId then return nil end
  local base = SaveData.portableBaseDir()
    or (love and love.filesystem and love.filesystem.getSaveDirectory
        and love.filesystem.getSaveDirectory())
  if not base then return nil end
  local sep = package.config:sub(1, 1)
  local rel = select(1, slotNames(version, slotId))
  return base .. sep .. rel:gsub("/", sep)
end

-- Slots visible to the launcher: every registered slot for a version, each
-- with whether it holds a save and the cheap summary above.  A fresh
-- install with nothing registered returns an empty array; a legacy install
-- is migrated to slot1 first.
function SaveData.listSlots(version)
  version = version or GameVersion.get()
  if not knownVersion(version) then return {} end
  local fs = persistFs(nil)
  ensureVersionSlots(version, fs)
  local opts = SaveData.loadOptions(fs)
  local reg = opts.saveSlots and opts.saveSlots[version]
  local list = (reg and reg.list) or {}
  local out = {}
  for _, id in ipairs(list) do
    local save = decodeSlot(fs, version, id)
    local name, meta = SaveData.slotSummary(save)
    out[#out + 1] = { id = id, exists = save ~= nil, name = name, meta = meta,
                      label = reg.names and reg.names[id] or nil }
  end
  return out
end

-- Give a registered slot a custom label (#205: "a way to name save slots so
-- you can see that in the launcher").  The label lives in the options
-- registry next to list/active, never in the save file itself, so renaming
-- needs no save rewrite and an empty slot can be labeled too.  The label is
-- trimmed; an empty (or whitespace-only) one clears it.  Returns true, or
-- false + an error string when the id is not registered.
function SaveData.renameSlot(version, slotId, name)
  version = version or GameVersion.get()
  if not knownVersion(version) then return false, "unknown version" end
  if type(slotId) ~= "string" or slotId == "" then
    return false, "missing slot id"
  end
  local fs = persistFs(nil)
  local opts = SaveData.loadOptions(fs)
  opts.saveSlots = opts.saveSlots or {}
  local reg = opts.saveSlots[version]
  if not reg or not reg.list then return false, "slot not registered" end
  local found = false
  for _, id in ipairs(reg.list) do
    if id == slotId then found = true break end
  end
  if not found then return false, "slot not registered" end
  local label = type(name) == "string" and name:match("^%s*(.-)%s*$") or nil
  if label == "" then label = nil end
  reg.names = reg.names or {}
  reg.names[slotId] = label
  if next(reg.names) == nil then reg.names = nil end
  opts.saveSlots[version] = reg
  SaveData.saveOptions(opts, fs)
  return true
end

-- Point the active slot at slotId (registering it if new) and persist the
-- choice to options.lua; also update the process-global cache so the very
-- next save/load lands in the chosen slot.
function SaveData.setActiveSlot(version, slotId)
  version = version or GameVersion.get()
  if not knownVersion(version) then return nil end
  local fs = persistFs(nil)
  local opts = SaveData.loadOptions(fs)
  opts.saveSlots = opts.saveSlots or {}
  local reg = opts.saveSlots[version] or { list = {}, active = nil }
  local found = false
  for _, id in ipairs(reg.list) do
    if id == slotId then found = true break end
  end
  if not found then reg.list[#reg.list + 1] = slotId end
  reg.active = slotId
  opts.saveSlots[version] = reg
  SaveData.saveOptions(opts, fs)
  slotsChecked[version] = true
  activeSlotCache[version] = slotId
  return slotId
end

-- Register a new empty slot for the version and return its id.  Does NOT
-- write a save file and does NOT change the active slot: an empty slot
-- means the title screen offers NEW GAME only.  Ids are "slot%d+",
-- allocated one past the highest existing number so a reused id can never
-- collide with a lingering file.
function SaveData.createSlot(version)
  version = version or GameVersion.get()
  if not knownVersion(version) then return nil end
  local fs = persistFs(nil)
  ensureVersionSlots(version, fs)
  local opts = SaveData.loadOptions(fs)
  opts.saveSlots = opts.saveSlots or {}
  local reg = opts.saveSlots[version] or { list = {}, active = nil }
  local maxN = 0
  for _, id in ipairs(reg.list) do
    local n = tonumber(tostring(id):match("^slot(%d+)$"))
    if n and n > maxN then maxN = n end
  end
  local id = "slot" .. (maxN + 1)
  reg.list[#reg.list + 1] = id
  opts.saveSlots[version] = reg
  SaveData.saveOptions(opts, fs)
  return id
end

-- The active slot id in use for a version (resolved once per process like
-- saveNames does), or nil when none is registered and the flat legacy path is
-- in use.  Public so the launcher's save Import/Export glue can name an export
-- after the slot it came from without reaching into the private cache.
function SaveData.activeSlot(version)
  version = version or GameVersion.get()
  if not knownVersion(version) then return nil end
  local fs = persistFs(nil)
  ensureVersionSlots(version, fs)
  return activeSlotCache[version] or nil
end

-- Write saveTable into an existing slot's file (SaveSerializer.encode), through
-- the same fs seam every other save/load call uses (so portable mode keeps
-- working) and the same .tmp-witness / .bak recovery discipline SaveData.save
-- uses for the flat path.  Used by the launcher's save-import glue, which has
-- already registered the slot via createSlot but written no bytes yet; unlike
-- SaveData.save this targets a specific slot and never rebuilds meta or touches
-- options.  Returns true, or false + an error string on a failed write.
function SaveData.writeSlot(version, slotId, saveTable)
  version = version or GameVersion.get()
  if not knownVersion(version) then return false, "unknown version" end
  if type(slotId) ~= "string" then return false, "missing slot id" end
  if type(saveTable) ~= "table" then return false, "missing save table" end
  local main, bak, tmp = slotNames(version, slotId)
  local encoded = SaveSerializer.encode(saveTable)
  local fs = persistFs(nil)
  ensureParentDir(fs, main)
  if fs.getInfo(main) then
    local prev = fs.read(main)
    if prev then fs.write(bak, prev) end
  end
  local ok, err = fs.write(tmp, encoded)
  if not ok then return false, err end
  remove(fs, main)
  ok, err = fs.write(main, encoded)
  if not ok then return false, err end
  remove(fs, tmp)
  return true
end

-- Delete a registered slot: remove its main/.bak/.tmp files, drop it from the
-- options registry, and if it was active point active at another remaining
-- slot (or clear active when the list is empty).  Returns true, or false +
-- an error string when the id is unknown / not registered.
function SaveData.deleteSlot(version, slotId)
  version = version or GameVersion.get()
  if not knownVersion(version) then return false, "unknown version" end
  if type(slotId) ~= "string" or slotId == "" then
    return false, "missing slot id"
  end
  local fs = persistFs(nil)
  ensureVersionSlots(version, fs)
  local opts = SaveData.loadOptions(fs)
  opts.saveSlots = opts.saveSlots or {}
  local reg = opts.saveSlots[version]
  if not reg or not reg.list then return false, "slot not registered" end
  local found, idx = false, nil
  for i, id in ipairs(reg.list) do
    if id == slotId then found = true; idx = i; break end
  end
  if not found then return false, "slot not registered" end

  local main, bak, tmp = slotNames(version, slotId)
  remove(fs, main)
  remove(fs, bak)
  remove(fs, tmp)

  table.remove(reg.list, idx)
  if reg.names then reg.names[slotId] = nil end
  if reg.active == slotId then
    reg.active = reg.list[1]  -- may be nil when the list is now empty
  end
  opts.saveSlots[version] = reg
  SaveData.saveOptions(opts, fs)
  slotsChecked[version] = true
  activeSlotCache[version] = reg.active or false
  return true
end

-- Test seam: drop the process-global slot cache so a suite can exercise
-- migration/resolution against a freshly injected filesystem.  Unused by
-- the game, which resolves each version exactly once per boot.
function SaveData.resetSlotState()
  for k in pairs(activeSlotCache) do activeSlotCache[k] = nil end
  for k in pairs(slotsChecked) do slotsChecked[k] = nil end
  freshPlaythrough = nil
end

-- ------- opaque playthrough identity

-- An id must never perturb the engine's gameplay RNG: savestate tools need
-- repeatable random outcomes, and allocating persistence scope is not gameplay.
-- Combine wall/process time, a process-local sequence and a fresh table address
-- into four hex words. This is an opaque collision-resistant identifier, not a
-- secret or a player-visible value.
local playthroughSeq = 0

local function word(n)
  return math.floor(tonumber(n) or 0) % 4294967296
end

function SaveData.newPlaythroughId()
  playthroughSeq = playthroughSeq + 1
  local address = tostring({}):match("0x(%x+)") or "0"
  local addressLo = tonumber(address:sub(-8), 16) or 0
  local clock = math.floor((os.clock() or 0) * 1000000)
  return ("%08x%08x%08x%08x"):format(
    word(os.time()), word(clock), word(addressLo), word(playthroughSeq))
end

local function playthroughScope(version, injectedFs)
  version = version or GameVersion.get()
  local fs = persistFs(injectedFs)
  ensureVersionSlots(version, fs)
  return activeSlotCache[version] or "legacy"
end

local function rememberPlaythroughId(save, opts, injectedFs)
  local meta = type(save) == "table" and save.meta
  local id = type(meta) == "table" and meta.playthroughId
  if type(id) ~= "string" or id == "" then return opts, false end
  local version = save.version or GameVersion.get()
  local scope = playthroughScope(version, injectedFs)
  opts = opts or SaveData.loadOptions(injectedFs)
  opts.playthroughIds = opts.playthroughIds or {}
  opts.playthroughIds[version] = opts.playthroughIds[version] or {}
  local changed = opts.playthroughIds[version][scope] ~= id
  opts.playthroughIds[version][scope] = id
  return opts, changed
end

-- Return an existing save identity or give a pre-identity save a stable one.
-- Legacy backfill lives in options.lua until the next normal SAVE stamps the id
-- into progress, so installing a tool mod never rewrites the player's checkpoint.
function SaveData.ensurePlaythroughId(save, injectedFs)
  if type(save) ~= "table" then return nil end
  save.meta = type(save.meta) == "table" and save.meta or {}
  local id = save.meta.playthroughId
  if type(id) == "string" and id ~= "" then return id end

  local version = save.version or GameVersion.get()
  local scope = playthroughScope(version, injectedFs)
  local opts = SaveData.loadOptions(injectedFs)
  local isFresh = save == freshPlaythrough
  if isFresh then freshPlaythrough = nil end
  local byVersion = opts.playthroughIds and opts.playthroughIds[version]
  id = not isFresh and byVersion and byVersion[scope] or nil
  if type(id) ~= "string" or id == "" then
    id = SaveData.newPlaythroughId()
    opts.playthroughIds = opts.playthroughIds or {}
    opts.playthroughIds[version] = opts.playthroughIds[version] or {}
    opts.playthroughIds[version][scope] = id
    SaveData.saveOptions(opts, injectedFs)
  end
  save.meta.playthroughId = id
  return id
end

-- ------- meta

-- the version/engine/mod-set stamp every v2 save carries; mods is the
-- loaded list sorted by id and is the ground truth for the load-time
-- mod-set diff.  A nil mods list keeps the previous stamp's set so a
-- headless writer (the save editor) never wipes it.
function SaveData.buildMeta(mods, previous)
  local list
  if mods ~= nil then
    list = {}
    for _, mod in ipairs(mods) do
      list[#list + 1] = { id = mod.id, version = mod.version, api = mod.api }
    end
    table.sort(list, function(a, b) return a.id < b.id end)
  else
    list = (type(previous) == "table" and previous.mods) or {}
  end
  return {
    format = Version.saveFormat,
    engine = Version.engine,
    savedAt = os.time(),
    playthroughId = type(previous) == "table" and previous.playthroughId or nil,
    mods = list,
  }
end

-- {added, removed, changed} between the set that wrote the save
-- (meta.mods) and the active loaded set; all three empty on a vanilla
-- load under vanilla
function SaveData.modsDiff(save, activeMods)
  local stored = {}
  for _, entry in ipairs((save.meta and save.meta.mods) or {}) do
    if type(entry) == "table" and entry.id then
      stored[entry.id] = entry.version or ""
    end
  end
  local diff = { added = {}, removed = {}, changed = {} }
  for _, mod in ipairs(activeMods or {}) do
    local was = stored[mod.id]
    if was == nil then
      diff.added[#diff.added + 1] = mod.id
    elseif was ~= mod.version then
      diff.changed[#diff.changed + 1] = { id = mod.id, from = was, to = mod.version }
    end
    stored[mod.id] = nil
  end
  for id in pairs(stored) do diff.removed[#diff.removed + 1] = id end
  table.sort(diff.added)
  table.sort(diff.removed)
  table.sort(diff.changed, function(a, b) return a.id < b.id end)
  return diff
end

-- one-line load notice for a non-empty diff ("This save was made with
-- 2 mods; 1 is no longer active"); nil when empty so a vanilla load
-- stays silent
function SaveData.modsDiffNotice(diff, meta)
  if type(diff) ~= "table" then return nil end
  local removed = #(diff.removed or {})
  local changed = #(diff.changed or {})
  local added = #(diff.added or {})
  if removed == 0 and changed == 0 and added == 0 then return nil end
  local wrote = #((type(meta) == "table" and meta.mods) or {})
  local parts = {}
  if removed > 0 then
    parts[#parts + 1] = removed .. (removed == 1 and " is" or " are") .. " no longer active"
  end
  if changed > 0 then
    parts[#parts + 1] = changed .. " changed version"
  end
  if added > 0 then
    parts[#parts + 1] = added .. " newly active"
  end
  return ("This save was made with %d mod%s; %s"):format(
    wrote, wrote == 1 and "" or "s", table.concat(parts, ", "))
end

-- ------- migrations

-- Ordered engine steps keyed on meta.format, each reproducing the inline
-- migration it replaced; a save already at the current format skips them
-- all.  Mod chains (recorded by Loader from mod.migrations:add) replay
-- against the version stored in meta.mods, in semver order, before the
-- validation pass -- so a mod repairs its own data instead of watching
-- it get quarantined.
local coreMigrations = {}

function SaveData.addCoreMigration(fromFormat, fn)
  coreMigrations[#coreMigrations + 1] =
    { from = fromFormat, seq = #coreMigrations + 1, fn = fn }
end

local function storedVersion(save, modId)
  for _, entry in ipairs((save.meta and save.meta.mods) or {}) do
    if type(entry) == "table" and entry.id == modId then
      return entry.version
    end
  end
  return nil
end

local function semverLt(a, b)
  local order = Semver.compare(a, b)
  return order ~= nil and order < 0
end

function SaveData.runMigrations(save, modChains, activeMods)
  table.sort(coreMigrations, function(a, b)
    if a.from ~= b.from then return a.from < b.from end
    return a.seq < b.seq
  end)
  -- every step whose from-format the save has not passed yet runs, in
  -- (from, registration) order; a save at the current format runs none
  local fmt = (save.meta and save.meta.format) or 1
  for _, m in ipairs(coreMigrations) do
    if m.from >= fmt then m.fn(save) end
  end
  -- a save that predates meta records an empty mod set: an old vanilla
  -- save becomes a v2 vanilla save
  save.meta = save.meta or { mods = {} }
  save.meta.format = Version.saveFormat
  for _, active in ipairs(activeMods or {}) do
    local modSave = save.modData and save.modData[active.id]
    local recorded = modChains and modChains[active.id]
    if modSave and recorded then
      local chain = {}
      for _, m in ipairs(recorded) do chain[#chain + 1] = m end
      table.sort(chain, function(a, b) return semverLt(a.since, b.since) end)
      local stored = storedVersion(save, active.id) or "0.0.0"
      for _, m in ipairs(chain) do
        if semverLt(stored, m.since) and not semverLt(active.version, m.since) then
          -- a throwing migration is skipped, not fatal: it would otherwise
          -- re-raise on every load and lock the player out of the save
          local ok, err = pcall(m.apply, modSave, save)
          if not ok then
            Logger.error("[%s] migration %s: %s -- skipped",
              active.id, tostring(m.since), tostring(err))
            break
          end
        end
      end
    end
  end
  return save
end

-- saves from before the trainer ID existed: backfill once on load
-- (like the OT backfill for old saves)
SaveData.addCoreMigration(1, function(save)
  if save.player and not save.player.id then
    save.player.id = math.random(0, 65535)
  end
end)

-- saves from before EVENT_BEAT_ROUTE12/16_SNORLAX existed: the object
-- was already hidden (Snorlax beaten) but the flag was never added,
-- and it can never be set again since the hidden object is
-- unreachable -- backfill it from the toggle so it isn't stuck forever
SaveData.addCoreMigration(1, function(save)
  if save.objectToggles and save.flags then
    local snorlaxRoutes = {
      { map = "ROUTE_12", obj = "ROUTE12_SNORLAX", flag = "EVENT_BEAT_ROUTE12_SNORLAX" },
      { map = "ROUTE_16", obj = "ROUTE16_SNORLAX", flag = "EVENT_BEAT_ROUTE16_SNORLAX" },
    }
    for _, r in ipairs(snorlaxRoutes) do
      local toggles = save.objectToggles[r.map]
      if toggles and toggles[r.obj] == false and not save.flags[r.flag] then
        save.flags[r.flag] = true
      end
    end
  end
end)

-- Migrate options that still live inside an old save.lua into the
-- standalone options file (once); load always re-attaches options.lua
-- afterwards either way
SaveData.addCoreMigration(1, function(save)
  if type(save.options) == "table"
      and not persistFs(nil).getInfo(OPTIONS_FILENAME) then
    SaveData.saveOptions(save.options)
  end
end)

-- settle the box shape (single `box` list -> 12 boxes) before the
-- validation pass walks it; Boxes keeps the lazy ensure for play paths
SaveData.addCoreMigration(1, function(save)
  Boxes.ensure(save)
end)

-- game version (Red vs Blue) prep: saves written before Blue support
-- existed carry no `version` tag, and Red is the only game that ever
-- shipped, so default every untagged save to Red.  from=2 so it catches
-- every pre-bump save (format 1 and 2) and is skipped once re-stamped to
-- the current format.
SaveData.addCoreMigration(2, function(save)
  if not save.version then
    save.version = "red"
  end
end)

-- #131 / follow-up to #50: Game Corner poster grunt used to stay on the
-- floor after defeat (defeatedTrainers only).  The #50 script now hides
-- him via objectToggles, but saves that already beat him never got the
-- toggle -- he still blocks the hideout switch.  from=3 so every pre-4
-- save reconciles once, then is skipped after re-stamp.
SaveData.addCoreMigration(3, function(save)
  local defeated = save.defeatedTrainers
  if not defeated or not defeated["GAME_CORNER_obj_11"] then return end
  save.objectToggles = save.objectToggles or {}
  local mapToggles = save.objectToggles.GAME_CORNER
  if not mapToggles then
    mapToggles = {}
    save.objectToggles.GAME_CORNER = mapToggles
  end
  if mapToggles.GAMECORNER_ROCKET ~= false then
    mapToggles.GAMECORNER_ROCKET = false
  end
end)

-- ------- write

-- Game progress only; options are written separately via saveOptions.
-- If `data.options` is present it is also flushed to options.lua so an
-- F1 / in-game save keeps the live settings in sync, then stripped from
-- the game file.  mods (when given) refreshes the meta stamp; the write
-- itself rolls the last good save into .bak and stages the new bytes as
-- a .tmp witness before the swap, so a crash mid-write is recoverable.
function SaveData.save(data, mods)
  -- write to the file matching this save's own version, not just the active
  -- one, so Blue/Yellow playthroughs land in save_blue.lua / save_yellow.lua
  local FILENAME, BACKUP_FILENAME, TMP_FILENAME = saveNames(data.version)
  if data.options then
    local opts = data.options
    if data.meta and data.meta.playthroughId then
      opts = rememberPlaythroughId(data, data.options)
    end
    data.options = opts
    SaveData.saveOptions(opts)
  elseif data.meta and data.meta.playthroughId then
    local opts, changed = rememberPlaythroughId(data)
    if changed then SaveData.saveOptions(opts) end
  end
  if mods ~= nil or data.meta == nil then
    data.meta = SaveData.buildMeta(mods, data.meta)
  end
  local gameOnly = {}
  for k, v in pairs(data) do
    if k ~= "options" then gameOnly[k] = v end
  end
  local encoded = SaveSerializer.encode(gameOnly)
  local fs = persistFs(nil)
  -- the active slot may live in saves/<version>/, which must exist before
  -- the .tmp/.bak/main writes land (a no-op for the flat legacy path)
  ensureParentDir(fs, FILENAME)
  if fs.getInfo(FILENAME) then
    local prev = fs.read(FILENAME)
    if prev then fs.write(BACKUP_FILENAME, prev) end
  end
  local ok, err = fs.write(TMP_FILENAME, encoded)
  if not ok then
    Logger.error("save failed: %s", tostring(err))
    return false
  end
  -- love.filesystem has no atomic rename: remove + rewrite, with the
  -- .tmp copy as the recovery witness in between
  remove(fs, FILENAME)
  ok, err = fs.write(FILENAME, encoded)
  if not ok then
    Logger.error("save failed: %s", tostring(err))
    return false
  end
  remove(fs, TMP_FILENAME)
  Logger.info("saved game")
  return true
end

-- ------- read

-- returns the parsed save plus "tmp"/"bak" when the main file was gone
-- or corrupt and a staged/backup copy was promoted; Game surfaces the
-- recovery on the load report
function SaveData.load(version)
  -- version defaults to the active game (set at boot from the launcher);
  -- an explicit version lets callers/tests load a specific game's save.
  local FILENAME, BACKUP_FILENAME, TMP_FILENAME = saveNames(version)
  local fs = persistFs(nil)
  local data, err = readTable(fs, FILENAME)
  local recovered
  if not data then
    local tmp = readTable(fs, TMP_FILENAME)
    if tmp then
      data, recovered = tmp, "tmp"
    else
      local bak = readTable(fs, BACKUP_FILENAME)
      if bak then data, recovered = bak, "bak" end
    end
    if data then
      Logger.warn("save.lua %s; recovered from %s copy",
        fs.getInfo(FILENAME) and "corrupt" or "missing", recovered)
      fs.write(FILENAME, SaveSerializer.encode(data))
    end
  end
  if not data then
    if fs.getInfo(FILENAME) then
      Logger.error("load failed: %s", tostring(err))
    end
    return nil
  end
  SaveData.runMigrations(data)
  data.options = SaveData.loadOptions()
  Logger.info("loaded save")
  return data, recovered
end

-- ------- validation and quarantine

local function known(tbl, id)
  return id ~= nil and type(tbl) == "table" and tbl[id] ~= nil
end

-- only out-of-range values move; a vanilla save passes through untouched
local function clamp(n, lo, hi, fallback)
  if type(n) ~= "number" then return fallback end
  if n < lo then return lo end
  if n > hi then return hi end
  return n
end

local function ensureOrphaned(save)
  if not save.orphaned then
    save.orphaned = { mons = {}, items = {} }
  end
  save.orphaned.mons = save.orphaned.mons or {}
  save.orphaned.items = save.orphaned.items or {}
  return save.orphaned
end

-- quarantined ids whose content reappeared (mod re-enabled) go home
-- again: mons through the PC deposit, items through the bag with the PC
-- as overflow
local function reclaim(save, data, report)
  local orphaned = save.orphaned
  if not orphaned then return end
  for i = #(orphaned.mons or {}), 1, -1 do
    local mon = orphaned.mons[i]
    if type(mon) == "table" and known(data.pokemon, mon.species) then
      table.remove(orphaned.mons, i)
      local box = Boxes.deposit(save, mon)
      if box then
        report.restoredMons[#report.restoredMons + 1] =
          { species = mon.species, box = box }
      else
        -- every box full: stays quarantined rather than vanishing
        table.insert(orphaned.mons, i, mon)
      end
    end
  end
  for i = #(orphaned.items or {}), 1, -1 do
    local entry = orphaned.items[i]
    if type(entry) == "table" and known(data.items, entry.id) then
      table.remove(orphaned.items, i)
      if entry.from == "pcItems" or type(save.inventory) ~= "table"
          or not Bag.add(save, entry.id, entry.count or 1, data) then
        save.pcItems = save.pcItems or {}
        save.pcItems[entry.id] = (save.pcItems[entry.id] or 0) + (entry.count or 1)
      end
      report.restoredItems[#report.restoredItems + 1] =
        { id = entry.id, count = entry.count or 1 }
    end
  end
end

-- mirrors Protocol.unpackMon's clamp discipline for the fields play
-- indexes; the level floor widens to 1 because a freshly caught level-1
-- mon can legitimately sit in a save
local function scrubKnownMon(mon, data)
  if type(mon.dvs) == "table" then
    for stat, v in pairs(mon.dvs) do mon.dvs[stat] = clamp(v, 0, 15, 0) end
  end
  if type(mon.statExp) == "table" then
    for stat, v in pairs(mon.statExp) do mon.statExp[stat] = clamp(v, 0, 65535, 0) end
  end
  mon.level = clamp(mon.level, 1, 100, 1)
  -- Box mons imported from a real .sav carry NO stat block: box_struct stops
  -- before MON_LEVEL/MON_STATS, so src/save_convert/GenSave.lua decodeMon
  -- only fills `stats` for party slots.  Every HP-bar draw then nil-indexes
  -- mon.stats: the status screen opened in the box (#233) and the party list
  -- after withdrawing one (#304).  The original derives them on demand
  -- (status_screen.asm:66-76, add_mon.asm _MoveMon); deriving once here means
  -- every later reader (menus, battle, items, SGB bar zones, the link
  -- fingerprint) sees a party-shaped mon.  Runs after the level clamp above
  -- so the derived stats use a sane level.  A save that already has stats is
  -- untouched.
  Stats.ensure(data.pokemon and data.pokemon[mon.species], mon)
  local moves = mon.moves
  if type(moves) ~= "table" then return end
  local hadMoves = #moves > 0
  for j = #moves, 1, -1 do
    local slot = moves[j]
    local id = type(slot) == "table" and slot.id or slot
    if not known(data.moves, id) then table.remove(moves, j) end
  end
  while #moves > 4 do table.remove(moves) end
  if hadMoves and #moves == 0 then
    -- data-driven repair so a total conversion without TACKLE still heals
    local fallback = (data.constants and data.constants.fallbackMove) or "TACKLE"
    local def = data.moves and data.moves[fallback]
    if def then
      moves[1] = { id = fallback, pp = def.pp }
    end
  end
end

local function scrubMonList(list, where, save, data, report)
  if type(list) ~= "table" then return end
  for i = #list, 1, -1 do
    local mon = list[i]
    if type(mon) ~= "table" or not known(data.pokemon, mon.species) then
      table.remove(list, i)
      ensureOrphaned(save)
      save.orphaned.mons[#save.orphaned.mons + 1] = mon
      report.lostMons[#report.lostMons + 1] =
        { species = type(mon) == "table" and mon.species or nil, from = where }
    else
      scrubKnownMon(mon, data)
    end
  end
end

local function scrubItemMap(map, where, save, data, report)
  if type(map) ~= "table" then return end
  for id, count in pairs(map) do
    if not known(data.items, id) then
      map[id] = nil
      ensureOrphaned(save)
      save.orphaned.items[#save.orphaned.items + 1] =
        { id = id, count = count, from = where }
      report.lostItems[#report.lostItems + 1] =
        { id = id, count = count, from = where }
    end
  end
end

local function scrubMaps(save, data, report)
  local boot = (data.field and data.field.boot) or {}
  local spawn = { map = boot.startMap or "REDS_HOUSE_2F",
                  x = boot.startX or 3, y = boot.startY or 6 }
  -- heal point first, so the player fallback below always lands somewhere
  -- valid; boot's heal cell (threaded from field.boot) is the last resort
  if save.lastHeal and not known(data.maps, save.lastHeal.map) then
    local heal = boot.lastHeal or spawn
    report.remappedMaps[#report.remappedMaps + 1] =
      { id = save.lastHeal.map, to = heal.map, field = "lastHeal" }
    save.lastHeal = { map = heal.map, x = heal.x, y = heal.y }
  end
  if save.player and not known(data.maps, save.player.map) then
    local heal = save.lastHeal or spawn
    report.remappedMaps[#report.remappedMaps + 1] =
      { id = save.player.map, to = heal.map, field = "player" }
    save.player.map, save.player.x, save.player.y = heal.map, heal.x, heal.y
  end
  if save.lastOutdoor and not known(data.maps, save.lastOutdoor.id) then
    report.remappedMaps[#report.remappedMaps + 1] =
      { id = save.lastOutdoor.id, field = "lastOutdoor" }
    save.lastOutdoor = nil
  end
  if save.lastHeal and type(save.lastHeal.outdoor) == "table"
      and not known(data.maps, save.lastHeal.outdoor.id) then
    save.lastHeal.outdoor = nil
  end
end

-- Walks every content id the save references against the merged data and
-- quarantines unknowns instead of letting them nil-index later: mons move
-- to save.orphaned (the LOST box), items are removed with a report row,
-- locations fall back to the heal point.  Reclaims quarantined content
-- whose id reappeared first.  On a mod-free save every membership test
-- passes and the save comes back untouched.
function SaveData.validate(save, data)
  local report = { lostMons = {}, lostItems = {}, remappedMaps = {},
                   restoredMons = {}, restoredItems = {} }
  reclaim(save, data, report)
  scrubMonList(save.party, "party", save, data, report)
  for b, box in ipairs(save.boxes or {}) do
    scrubMonList(box, "box " .. b, save, data, report)
  end
  local daycare = save.daycare
  if type(daycare) == "table" and type(daycare.mon) == "table" then
    if not known(data.pokemon, daycare.mon.species) then
      ensureOrphaned(save)
      save.orphaned.mons[#save.orphaned.mons + 1] = daycare.mon
      report.lostMons[#report.lostMons + 1] =
        { species = daycare.mon.species, from = "daycare" }
      daycare.mon = nil
    else
      scrubKnownMon(daycare.mon, data)
    end
  end
  scrubItemMap(save.inventory, "inventory", save, data, report)
  scrubItemMap(save.pcItems, "pcItems", save, data, report)
  if type(save.bagOrder) == "table" then
    for i = #save.bagOrder, 1, -1 do
      if not known(data.items, save.bagOrder[i]) then
        table.remove(save.bagOrder, i)
      end
    end
  end
  scrubMaps(save, data, report)
  local dex = save.pokedex
  if type(dex) == "table" then
    for _, key in ipairs({ "seen", "owned" }) do
      if type(dex[key]) == "table" then
        for id in pairs(dex[key]) do
          if not known(data.pokemon, id) then dex[key][id] = nil end
        end
      end
    end
  end
  -- hall of fame rosters keep their shape: an unknown species blanks in
  -- place so the team stays the size it won at, with the rest of the mon
  -- (level etc.) intact for display
  for _, entry in ipairs(save.hallOfFame or {}) do
    if type(entry) == "table" then
      for i = 1, #entry do
        local mon = entry[i]
        if type(mon) == "table" and mon.species ~= nil
            and not known(data.pokemon, mon.species) then
          mon.species = nil
        end
      end
    end
  end
  -- an empty quarantine leaves no residue, so a vanilla save re-encodes
  -- byte-identically
  local orphaned = save.orphaned
  if orphaned and #(orphaned.mons or {}) == 0 and #(orphaned.items or {}) == 0 then
    save.orphaned = nil
  end
  return report
end

function SaveData.emptyReport(report)
  -- a bare validate report (the save editor's probe) carries no modsDiff;
  -- restoreSave attaches one so a version bump alone still surfaces
  local diff = report.modsDiff
  return #report.lostMons == 0 and #report.lostItems == 0
    and #report.remappedMaps == 0 and #report.restoredMons == 0
    and #report.restoredItems == 0 and not report.recovered
    and (not diff or (#diff.added == 0 and #diff.removed == 0 and #diff.changed == 0))
end

-- ------- new game

-- boot is Data.field.boot, threaded in by Game: this module must not reach
-- into Data itself.  Every read falls back to the Red literal it replaced,
-- so an absent or partial config still produces the vanilla new game.
-- Where blackouts and ESCAPE ROPE return to for a given boot config.
--
-- In vanilla this is NOT the spawn. wLastBlackoutMap is zero-filled at new
-- game and PALLET_TOWN is map 0, so the player starts in the bedroom
-- (special_warps.asm NewGameWarp) but blacks out to Pallet Town's fly_warp
-- cell (5, 6). A world that moves the spawn without naming a heal point
-- keeps the two together -- it may have no Pallet Town at all.
--
-- Shared with the Hall of Fame reset, which pokered writes as a literal
-- (HallOfFameResetEventsAndSaveScript: wLastBlackoutMap := PALLET_TOWN)
-- rather than deriving from the spawn.
function SaveData.defaultHeal(boot)
  boot = type(boot) == "table" and boot or {}
  local h = boot.lastHeal
  if h then return { map = h.map, x = h.x, y = h.y } end
  local map = boot.startMap or "REDS_HOUSE_2F"
  if map == "REDS_HOUSE_2F" then return { map = "PALLET_TOWN", x = 5, y = 6 } end
  return { map = map, x = boot.startX or 3, y = boot.startY or 6 }
end

-- Post-credits home (issue #103).  pokered left the player in HALL_OF_FAME
-- after jp Init; this port relocates CONTINUE instead, and retargets
-- LAST_MAP exits (Red's house mats) at the heal-point town so leaving the
-- house does not dump the player back at Indigo Plateau.
--
-- The landing spot is the blackout point, not the NewGameWarp bedroom:
-- HallOfFameResetEventsAndSaveScript sets wLastBlackoutMap := PALLET_TOWN,
-- so resuming puts the player outside the front door.  Spawning them back
-- in the upstairs bedroom was a port-only detour (#253).  Non-vanilla
-- spawns are unaffected -- defaultHeal returns boot's own start map for
-- those, which is what the bedroom branch resolved to anyway.
-- Marks postGameHomeOk so a later intentional HoF save is not relocated.
function SaveData.applyPostGameHome(save, boot)
  boot = type(boot) == "table" and boot or {}
  local heal = SaveData.defaultHeal(boot)
  save.lastHeal = { map = heal.map, x = heal.x, y = heal.y }
  save.lastOutdoor = { id = heal.map, x = heal.x, y = heal.y }
  save.player = save.player or {}
  save.player.map = heal.map
  save.player.x = heal.x
  save.player.y = heal.y
  save.player.facing = boot.startFacing or "down"
  save.postGameHomeOk = true
  return heal
end

-- Softlocked 0.1.11 saves: still standing in HALL_OF_FAME after credits,
-- with lastOutdoor on Indigo.  One-shot rescue on CONTINUE.
function SaveData.needsPostGameRescue(save)
  if not (save and save.player and save.player.map == "HALL_OF_FAME") then
    return false
  end
  if save.postGameHomeOk then return false end
  local hof = save.hallOfFame
  return type(hof) == "table" and #hof > 0
end

function SaveData.newGame(boot)
  boot = type(boot) == "table" and boot or {}
  local map = boot.startMap or "REDS_HOUSE_2F"
  local x, y = boot.startX or 3, boot.startY or 6
  local heal = SaveData.defaultHeal(boot)
  local save = {
    meta = { format = Version.saveFormat, mods = {} },
    -- which game this playthrough is (Red vs Blue).  Only Red ships today;
    -- boot carries the choice once Blue support lands.
    version = boot.version or "red",
    player = {
      map = map,
      x = x,
      y = y,
      facing = boot.startFacing or "down",
      name = boot.playerName or "RED",
      rival = boot.rivalName or "BLUE",
      -- 16-bit trainer ID rolled at new game (wPlayerID, filled from
      -- hRandomAdd in OakSpeech)
      id = math.random(0, 65535),
    },
    flags = {},
    inventory = {},
    -- Vanilla Gen1 seeds one Potion in the player's item PC
    -- (wBoxItems / players_pc.asm); existing saves keep whatever they
    -- already have -- this only applies to New Game.
    pcItems = { POTION = 1 },
    party = {},
    box = {},
    money = boot.startMoney or 3000,
    defeatedTrainers = {},
    pokedex = { seen = {}, owned = {} },
    -- where blackouts and ESCAPE ROPE return to (updated by nurses);
    -- copied, never aliased, so a save never writes back into Data
    lastHeal = { map = heal.map or map, x = heal.x or x, y = heal.y or y },
    -- Interiors inherit the SGB palette of the last outdoor map. wLastMap
    -- is zero-filled at new game and PALLET_TOWN is map 0, so before the
    -- player has ever been outdoors that palette is Pallet Town's -- which
    -- matters because the vanilla spawn (REDS_HOUSE_2F) is itself indoors.
    -- Without this the palette falls through to the ROUTE default.
    lastOutdoor = { id = heal.map or map, x = heal.x or x, y = heal.y or y },
    repelSteps = 0,
    -- per-mod persistence (mod.save) lives under here, keyed by mod id
    modData = {},
    -- Live options from options.lua (or defaults); New Game keeps the
    -- player's audio/display/battle preferences.
    options = SaveData.loadOptions(),
  }
  -- a total conversion reshapes the skeleton (spawn, party, money)
  -- before anything reads it; unhooked this returns save unchanged. Keep the
  -- "fresh playthrough" marker outside the serialized table so a later tool
  -- request can distinguish two unsaved New Games sharing one vanilla slot.
  save = Runtime.call("save.new_game", function(s) return s end, save)
  freshPlaythrough = save
  return save
end

return SaveData
