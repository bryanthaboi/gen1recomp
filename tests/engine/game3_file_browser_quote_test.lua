-- The launcher file browser must not interpolate a path into a shell unescaped.
--
-- L3 regression: scanDirectory built
--   'ls -1ap "' .. dir:gsub('"', '\\"') .. '" 2>/dev/null'
-- so only a double quote was escaped.  A directory name containing $(...) or a
-- backtick executed as the user the moment it was entered in the ROM/mod picker.
-- HostShell.quote already escapes for the POSIX shell.
--   luajit tests/engine/game3_file_browser_quote_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local FileBrowser = require("src.ui.kit.FileBrowser")
local HostShell = require("src.core.HostShell")

-- This suite is about the shell path: a directory name has to reach `ls`
-- quoted.  A native enumerator (SaveData's FFI listing, used on desktop since
-- the Windows fix) bypasses the shell entirely, so opt out of it here; the
-- desktop listing has its own suite in file_browser_desktop_test.lua.
FileBrowser.nativeFs = {}

local realRomArchive = package.loaded["src.import.RomArchive"]
package.loaded["src.import.RomArchive"] = {
  capabilities = function() return { zip = true, z7 = false } end,
}

-- 1. Injection: a directory named with a command substitution must not run.
-- The marker must not pre-exist (os.tmpname creates its file, so name it here).
local marker = "/tmp/gen1recomp-inject-" .. tostring(os.time())
  .. "-" .. tostring(math.random(1000000))
check(io.open(marker, "r") == nil, "the injection marker does not exist before the call")
local hostile = "/tmp/gen1recomp-inject-$(touch " .. marker .. ")-x"
FileBrowser.setDirectory(hostile)
local created = io.open(marker, "r")
if created then created:close(); os.remove(marker) end
check(created == nil,
  "a command substitution in a directory name is not executed by the file browser")

-- 2. Shape: the listing command single-quotes the path (HostShell's POSIX form).
local captured
local realPopen = io.popen
io.popen = function(cmd)
  captured = cmd
  return { read = function() return "" end, close = function() end }
end
FileBrowser.setDirectory("/tmp/it's $(here)")
io.popen = realPopen

check(type(captured) == "string", "the browser still lists through the shell")
if type(captured) == "string" then
  local quoted = HostShell.quote("/tmp/it's $(here)")
  check(captured:find(quoted, 1, true) ~= nil,
    "the directory is passed through HostShell.quote (" .. tostring(captured) .. ")")
  check(captured:find("$(here)", 1, true) == nil or captured:find(quoted, 1, true) ~= nil,
    "the raw path is not left unquoted")
end

local realItems = love.filesystem.getDirectoryItems
local realInfo = love.filesystem.getInfo
local listing = { "images", "videos", "Red.gb", "Crystal.GBC", "FireRed.gba",
  "Emerald.GBA", "roms.zip", "pack.7z", "save.sav", "save.lua",
  "demo.g1rcart", "notes.txt" }
local function listingText()
  local out = {}
  for _, name in ipairs(listing) do
    out[#out + 1] = name .. ((name == "images" or name == "videos") and "/" or "")
  end
  return table.concat(out, "\n")
end
for _, backend in ipairs({ "shell", "love" }) do
  io.popen = function()
    return { read = function() return backend == "shell" and listingText() or "" end,
      close = function() end }
  end
  love.filesystem.getDirectoryItems = function() return listing end
  love.filesystem.getInfo = function(path)
    local name = path:match("[^/]+$")
    return { type = (name == "images" or name == "videos") and "directory" or "file" }
  end
  for _, button in ipairs({ "a", "start" }) do
    local picked, calls = nil, 0
    FileBrowser.open({ mode = "rom", initialPath = "/fixture/gba",
      onSelect = function(path) picked, calls = path, calls + 1 end })
    eq(#FileBrowser.entries, 8, backend .. " ROM list contains all supported suffixes")
    eq(FileBrowser.entries[1].name, "images", backend .. " directories sort first")
    eq(FileBrowser.entries[2].name, "videos", backend .. " second directory remains visible")
    local found = {}
    for i, entry in ipairs(FileBrowser.entries) do
      found[entry.name] = i
    end
    for _, name in ipairs({ "Red.gb", "Crystal.GBC", "FireRed.gba", "Emerald.GBA", "roms.zip" }) do
      check(found[name] ~= nil, backend .. " shows " .. name)
    end
    check(found["notes.txt"] == nil and found["save.sav"] == nil,
      backend .. " excludes unrelated files from ROM mode")
    check(found["pack.7z"] ~= nil,
      backend .. " lists .7z even when the platform caps disallow it")
    if found["FireRed.gba"] then
      FileBrowser.selectedIdx = found["FireRed.gba"]
      check(FileBrowser.gamepadpressed(button), backend .. " consumes " .. button)
      eq(picked, "/fixture/gba/FireRed.gba", backend .. " returns exact GBA path on " .. button)
      eq(calls, 1, backend .. " callback occurs once")
      check(not FileBrowser.active, backend .. " GBA selection closes modal")
      FileBrowser.gamepadpressed(button)
      eq(calls, 1, backend .. " inactive modal does not repeat callback")
    end
    FileBrowser.close()
  end
  for _, case in ipairs({ { "save", 4 }, { "mod", 3 }, { "cart", 3 } }) do
    FileBrowser.open({ mode = case[1], initialPath = "/fixture/gba" })
    eq(#FileBrowser.entries, case[2], backend .. " preserves " .. case[1] .. " filter")
    for _, entry in ipairs(FileBrowser.entries) do
      check(entry.name ~= "FireRed.gba" and entry.name ~= "Emerald.GBA",
        backend .. " " .. case[1] .. " excludes GBA ROMs")
    end
    FileBrowser.close()
  end
end
io.popen = realPopen
love.filesystem.getDirectoryItems = realItems
love.filesystem.getInfo = realInfo
package.loaded["src.import.RomArchive"] = realRomArchive
FileBrowser.nativeFs = nil

T.finish("game3_file_browser_quote_test")
