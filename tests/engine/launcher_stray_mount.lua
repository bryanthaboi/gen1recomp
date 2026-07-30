-- The launcher's stray-mod scan must not borrow a game folder that is already
-- on the physfs read path: PHYSFS_mount succeeds for such a folder without
-- adding a search-path entry, so the paired unmount drops the mount the
-- portable cache and its mods/ live on, and the MODS panel empties (#413).
-- Runs the real SaveData.gameFolders / LauncherMods scan over a fused macOS
-- layout, with a search path that copies those physfs semantics.
--   luajit tests/engine/launcher_stray_mount.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

-- scripts/build.sh mac layout: the game is an archive inside the .app, the
-- player's portable folder is the one holding the .app.
local PORTABLE = "/Users/p/Games"
local APP = PORTABLE .. "/gen1recomp.app"
local SOURCE = APP .. "/Contents/Resources/game.love"
local BASE = APP .. "/Contents/MacOS"

love.system = love.system or {}
love.system.getOS = function() return "OS X" end
love.filesystem.getSource = function() return SOURCE end
love.filesystem.getSourceBaseDirectory = function() return BASE end

local CacheFs = require("src.import.CacheFs")
local SaveData = require("src.core.SaveData")
local LauncherMods = require("src.mods.LauncherMods")

-- ------- isReadableRoot: the two folders a fused build can already read

do
  check(LauncherMods.isReadableRoot(SOURCE, SOURCE, PORTABLE),
    "the physfs source is already readable")
  check(LauncherMods.isReadableRoot(PORTABLE, SOURCE, PORTABLE),
    "so is the portable folder CacheFs mounted")
  check(not LauncherMods.isReadableRoot(BASE, SOURCE, PORTABLE),
    "a folder beside them is not, so it still needs a scan mount")
  check(not LauncherMods.isReadableRoot(nil, SOURCE, PORTABLE),
    "no folder is not a readable folder")
  check(not LauncherMods.isReadableRoot("", SOURCE, PORTABLE),
    "nor is an empty path, which would match an unresolved cache root")
  check(not LauncherMods.isReadableRoot(PORTABLE, SOURCE, nil),
    "with no cache root mounted the portable folder is scannable again")
end

-- ------- withMounted answers "could not look", never "nothing there"

do
  eq(CacheFs.withMounted("", "stray_scan", function() return "ran" end), nil,
    "an empty dir is refused without running fn")
end

-- ------- the scan over that layout leaves the portable mount standing

do
  eq(SaveData.gameFolders()[1], PORTABLE,
    "the folder holding the .app is the first game folder")

  -- PHYSFS_mount on a directory already in the search path bails with success
  -- and adds nothing (physfs 2.x and 3.x alike), while PHYSFS_unmount removes
  -- whatever entry is there -- so a borrowed mount of an already-mounted
  -- folder costs the caller the real one.
  local searchPath = { [PORTABLE] = true }
  local mounted = {}
  CacheFs.root = function() return PORTABLE end
  CacheFs.withMounted = function(dir, mountPoint, fn)
    mounted[#mounted + 1] = dir
    if not searchPath[dir] then searchPath[dir] = true end
    local res = fn()
    searchPath[dir] = nil
    return res
  end

  LauncherMods.strays()

  check(searchPath[PORTABLE],
    "the portable folder is still mounted after the stray scan")
  for _, dir in ipairs(mounted) do
    check(dir ~= PORTABLE, "the scan never remounts the portable folder")
    check(dir ~= SOURCE, "nor the source, whose mods/ is readable already")
  end
  eq(mounted[1], BASE,
    "the folders that do need a mount are still scanned")
end

T.finish("launcher stray scan mount")
