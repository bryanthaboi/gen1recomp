-- Desktop listing in the in-launcher file browser.
--   luajit tests/engine/file_browser_desktop_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local FileBrowser = require("src.ui.kit.FileBrowser")

-- Windows-shaped tree keyed by the normalized path the browser builds.  An
-- unknown directory lists as empty rather than nil, which is the "no native
-- enumerator" signal.
local tree = {
  ["C:/roms"] = { "Red.gb", "notes.txt", "baseroms" },
  ["C:/roms/baseroms"] = { "yellow.gbc" },
  ["C:/game"] = { "baseroms", "options.lua" },
  ["C:/game/baseroms"] = { "red.gb", "blue.gb" },
}
local statCalls = 0
local fakeFs = {
  listNative = function(dir) return tree[dir] or {} end,
  isDirNative = function(path) return tree[path] ~= nil end,
  statNative = function(path)
    statCalls = statCalls + 1
    if tree[path] then return { type = "directory" } end
    return { type = "file", size = 1024 }
  end,
  gameFolders = function() return { "C:\\game" } end,
}
FileBrowser.nativeFs = fakeFs

local popenCalls = 0
local realPopen = io.popen
io.popen = function()
  popenCalls = popenCalls + 1
  return { read = function() return "" end, close = function() end }
end

-- 1. Listing
FileBrowser.open({ mode = "rom", initialPath = "C:\\roms" })
eq(FileBrowser.currentDir, "C:/roms", "a backslash drive path normalizes to C:/roms")
eq(#FileBrowser.entries, 2, "ROM mode hides notes.txt")
eq(FileBrowser.entries[1].name, "baseroms", "directories sort before files")
check(FileBrowser.entries[1].isDir == true, "a directory entry is flagged as one")
eq(FileBrowser.entries[2].path, "C:/roms/Red.gb", "the picked path is dir/name with a slash")
eq(popenCalls, 0, "a native listing does not shell out")
eq(statCalls, 0, "listing does not stat, and so never opens, each entry")

-- 2. Fallback when the platform has no cheap type probe
fakeFs.isDirNative = nil
FileBrowser.open({ mode = "rom", initialPath = "C:/roms" })
check(FileBrowser.entries[1].isDir == true, "without isDirNative the listing falls back to stat")
fakeFs.isDirNative = function(path) return tree[path] ~= nil end
FileBrowser.close()

-- 3. Selection
local picked
FileBrowser.open({ mode = "rom", initialPath = "C:/roms",
  onSelect = function(path) picked = path end })
FileBrowser.selectedIdx = 2
check(FileBrowser.gamepadpressed("a"), "A is consumed by the modal")
eq(picked, "C:/roms/Red.gb", "selection returns the file path")
check(not FileBrowser.active, "selecting closes the modal")

-- 4. Parent navigation stops at the drive root
FileBrowser.open({ mode = "rom", initialPath = "C:/roms" })
check(FileBrowser.gamepadpressed("b"), "B is consumed by the modal")
eq(FileBrowser.currentDir, "C:/", "B from C:/roms goes to the drive root")
FileBrowser.gamepadpressed("b")
check(not FileBrowser.active, "B at the drive root closes the modal")

-- 5. Default start folder
FileBrowser.open({ mode = "rom" })
eq(FileBrowser.currentDir, "C:/game/baseroms", "ROM mode opens baseroms/ when it exists")
eq(#FileBrowser.entries, 2, "both ROMs in baseroms/ are listed")
FileBrowser.close()
FileBrowser.open({ mode = "mod" })
eq(FileBrowser.currentDir, "C:/game", "other modes open the game folder")
check((FileBrowser.entries[1] or {}).name == "baseroms",
  "the drop folder is reachable from the game folder")

-- 6. Shortcuts
local visited = {}
for _ = 1, 4 do
  FileBrowser.cycleShortcut()
  visited[FileBrowser.currentDir] = true
end
check(visited["C:/game"] == true, "Game Dir is a desktop shortcut")
check(visited["/mnt/SDCARD"] == nil, "handheld mounts are not offered on a desktop")

-- 7. Windows never runs the POSIX probes, with no native enumerator at all
FileBrowser.nativeFs = {}
local realOS = love.system.getOS
love.system.getOS = function() return "Windows" end
popenCalls = 0
FileBrowser.open({ mode = "rom", initialPath = "C:/nowhere" })
eq(popenCalls, 0, "Windows never shells out to test/ls")
eq(#FileBrowser.entries, 0, "an unreadable folder lists nothing")
eq(FileBrowser.currentDir, "C:/nowhere",
  "Windows does not fall back to the drive root when a folder is empty")
FileBrowser.close()

popenCalls = 0
FileBrowser.open({ mode = "rom" })
eq(popenCalls, 0, "the starting folder is never probed through the shell on Windows")
love.system.getOS = realOS

io.popen = realPopen
FileBrowser.nativeFs = nil
FileBrowser.close()

T.finish("file_browser_desktop_test")
