-- Android Storage Folder (src/core/G1RFolder.lua): Move Files must never
-- leave saves split between two folders.  It copies and verifies everything
-- first, switches the storage setting second and deletes the originals last,
-- so a copy that fails part-way leaves the originals, the setting and the
-- destination exactly as they were.  Runs the real G.move and SaveData over
-- real temp folders with love.system reporting Android.
--   luajit tests/engine/g1r_folder_move_test.lua

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("g1r folder move")
local check, eq = S.check, S.eq

local WIN = package.config:sub(1, 1) == "\\"

-- Android paths start with "/".  On Windows a drive-less path resolves on
-- the current drive, so the scratch folder lives under the checkout there.
local function scratchRoot()
  local stamp = ("g1r_move_test_%d_%d"):format(os.time(), math.random(1, 999999))
  if WIN then
    local pipe = io.popen("cd")
    local cwd = pipe and pipe:read("*l") or "."
    if pipe then pipe:close() end
    return (cwd:gsub("\\", "/"):gsub("^%a:", "")) .. "/.tmp_" .. stamp
  end
  return ((os.getenv("TMPDIR") or "/tmp"):gsub("/+$", "")) .. "/" .. stamp
end

local function mkdirp(path)
  if WIN then
    os.execute('mkdir "' .. path:gsub("/", "\\") .. '" 2>nul')
  else
    os.execute('mkdir -p "' .. path .. '" 2>/dev/null')
  end
end

local function rmrf(path)
  if WIN then
    os.execute('rmdir /s /q "' .. path:gsub("/", "\\") .. '" 2>nul')
  else
    os.execute('rm -rf "' .. path .. '" 2>/dev/null')
  end
end

local function put(path, body)
  mkdirp(path:match("^(.*)/[^/]+$"))
  local f = assert(io.open(path, "wb"))
  f:write(body)
  f:close()
end

local function get(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  return body
end

local function isDir(path)
  return require("src.core.SaveData").statNative(path) ~= nil
end

-- G.move clears empty folders with os.remove, which is C remove(): on POSIX
-- (Android, where this runs, and Linux CI) that removes an empty directory,
-- but the Windows C runtime only removes files.  Windows checkouts skip just
-- the folder-cleanup checks; every file check still runs.
local skippedDirChecks = 0
local function checkGone(paths, msg)
  if WIN then skippedDirChecks = skippedDirChecks + 1 return end
  for _, path in ipairs(paths) do
    if isDir(path) then check(false, msg .. " (" .. path .. " is still there)") return end
  end
  check(true, msg)
end

-- every byte value, and big enough to need more than one copy chunk
local BIG = {}
for i = 0, 255 do BIG[#BIG + 1] = string.char(i) end
BIG = table.concat(BIG):rep(5 * 1024) -- 1.25 MB

local ROOT = scratchRoot()
local APP = ROOT .. "/app"
local POINTER = APP .. "/g1r_storage_folder.txt"
rmrf(ROOT)

local quits = 0
love.system = love.system or {}
love.system.getOS = function() return "Android" end
love.filesystem = love.filesystem or {}
love.filesystem.getSaveDirectory = function() return APP end
love.filesystem.read = function(name) return get(APP .. "/" .. name) end
love.filesystem.write = function(name, body) put(APP .. "/" .. name, body); return true end
love.filesystem.remove = function(name) return os.remove(APP .. "/" .. name) ~= nil end
love.window = love.window or {}
love.window.showMessageBox = function() return 2 end
love.event = love.event or {}
love.event.quit = function() quits = quits + 1 end
local realWrite = love.filesystem.write

-- SaveData caches the storage folder and portable mode per process, as the
-- game does per launch, so each step reloads both like a fresh start.
local function fresh()
  package.loaded["src.core.SaveData"] = nil
  package.loaded["src.core.G1RFolder"] = nil
  return require("src.core.SaveData"), require("src.core.G1RFolder")
end

local ORIGINALS = {
  ["options.lua"] = "opts = 1",
  ["save/red.sav"] = "red save",
  ["save/blue.sav"] = "blue save",
  ["cache/rom.bin"] = BIG,
}
local function seedApp()
  for rel, body in pairs(ORIGINALS) do put(APP .. "/" .. rel, body) end
end
local function originalsIntact(base, what)
  for rel, body in pairs(ORIGINALS) do
    check(get(base .. "/" .. rel) == body, what .. ": " .. rel .. " still in place, unchanged")
  end
end

-- Fail the Nth copy after writing a partial file, like a full disk would.
local function failNthCopy(G, n)
  local real, calls = G._copyFile, 0
  G._copyFile = function(src, dst)
    calls = calls + 1
    if calls == n then
      put(dst, "partial")
      return false
    end
    return real(src, dst)
  end
  return function() return calls end
end

-- ------- a failed copy into a new folder changes nothing

do
  seedApp()
  local SaveData, G = fresh()
  local dest = ROOT .. "/phone/G1R"
  local calls = failNthCopy(G, 3)
  local ok, msg = G.move(dest)
  eq(ok, false, "a failed copy fails the move")
  check(type(msg) == "string" and msg:find("nothing was moved", 1, true) ~= nil,
    "and says nothing was moved: " .. tostring(msg))
  check(calls() == 3, "two copies were made before the third failed")
  originalsIntact(APP, "failed copy")
  check(get(POINTER) == nil, "the storage setting was not switched")
  for rel in pairs(ORIGINALS) do
    check(get(dest .. "/" .. rel) == nil, "no copy of " .. rel .. " was left in the new folder")
  end
  checkGone({ dest }, "the new folder it created was removed again")
  check(SaveData.portableBaseDir() == nil, "the game still uses the app's own storage")
end

-- ------- a failed copy into a folder that already had files keeps them

do
  local dest = ROOT .. "/phone/Existing"
  put(dest .. "/notes.txt", "player's own file")
  local _, G = fresh()
  failNthCopy(G, 2)
  local ok = G.move(dest)
  eq(ok, false, "a failed copy into an existing folder fails")
  originalsIntact(APP, "existing folder")
  eq(get(dest .. "/notes.txt"), "player's own file", "the folder's own file is untouched")
  for rel in pairs(ORIGINALS) do
    check(get(dest .. "/" .. rel) == nil, "no copy of " .. rel .. " was left behind")
  end
  checkGone({ dest .. "/save", dest .. "/cache" }, "the subfolders made for the copies are gone")
  check(isDir(dest), "the folder that was already there is kept")
  check(get(dest .. "/portable.txt") == nil, "no portable.txt was written")
  check(get(POINTER) == nil, "the storage setting was not switched")
end

-- ------- the setting failing to save also changes nothing

do
  local dest = ROOT .. "/phone/NoSetting"
  local _, G = fresh()
  love.filesystem.write = function() return false end
  local ok, msg = G.move(dest)
  love.filesystem.write = realWrite
  eq(ok, false, "a setting that can't be saved fails the move")
  check(type(msg) == "string" and msg:find("nothing was moved", 1, true) ~= nil,
    "and says nothing was moved: " .. tostring(msg))
  originalsIntact(APP, "setting not saved")
  for rel in pairs(ORIGINALS) do
    check(get(dest .. "/" .. rel) == nil, "no copy of " .. rel .. " was left behind")
  end
  check(get(dest .. "/portable.txt") == nil, "no portable.txt was left behind")
  checkGone({ dest }, "its folder was removed again")
end

-- ------- a complete move: copy, switch, then delete the originals

local FIRST = ROOT .. "/phone/First"
do
  local SaveData, G = fresh()
  local ok, moved, leftover = G.move(FIRST)
  eq(ok, true, "the move succeeds")
  eq(moved, 4, "all four files moved")
  eq(leftover, 0, "no originals left behind")
  originalsIntact(FIRST, "moved")
  for rel in pairs(ORIGINALS) do
    check(get(APP .. "/" .. rel) == nil, rel .. " is gone from the old folder")
  end
  checkGone({ APP .. "/save", APP .. "/cache" }, "the old, now empty subfolders are gone")
  eq(get(POINTER), FIRST .. "\n", "the storage setting points at the new folder")
  eq(get(FIRST .. "/portable.txt"), "", "the new folder is marked for portable mode")
  check(SaveData.portableBaseDir() == nil or SaveData.portableBaseDir() == APP,
    "this launch still had the old folder")
  SaveData = fresh()
  eq(SaveData.portableBaseDir(), FIRST, "the next launch uses the new folder")
end

-- ------- a failed copy while already using a folder keeps that folder

do
  local _, G = fresh()
  failNthCopy(G, 2)
  local ok = G.move(ROOT .. "/phone/Second")
  eq(ok, false, "a failed move from a storage folder fails")
  originalsIntact(FIRST, "storage folder")
  eq(get(POINTER), FIRST .. "\n", "the setting still points at the current folder")
  local SaveData = fresh()
  eq(SaveData.portableBaseDir(), FIRST, "and the game keeps using it")
end

-- ------- a move that was cut short and run again doesn't duplicate files

do
  local dest = ROOT .. "/phone/Retry"
  put(dest .. "/options.lua", ORIGINALS["options.lua"]) -- copied before the cut
  put(dest .. "/save/red.sav", "a different red save") -- the player's own file
  local _, G = fresh()
  local ok, moved = G.move(dest)
  eq(ok, true, "the second attempt succeeds")
  eq(moved, 4, "it still accounts for all four files")
  eq(get(dest .. "/options.lua"), ORIGINALS["options.lua"], "the identical copy is reused")
  check(get(dest .. "/_from_previous_location/options.lua") == nil,
    "an identical file is not copied a second time")
  eq(get(dest .. "/save/red.sav"), "a different red save", "a different file is never overwritten")
  eq(get(dest .. "/_from_previous_location/save/red.sav"), "red save",
    "ours goes beside it instead")
  check(get(FIRST .. "/options.lua") == nil, "the originals are gone from the old folder")
  eq(get(POINTER), dest .. "\n", "the setting points at the new folder")
end

-- ------- moving back to the app's own storage clears the setting

do
  local SaveData, G = fresh()
  eq(SaveData.portableBaseDir(), ROOT .. "/phone/Retry", "starts in the storage folder")
  local ok = G.move("")
  eq(ok, true, "moving back succeeds")
  eq(get(POINTER), nil, "the storage setting is cleared")
  eq(get(APP .. "/cache/rom.bin"), BIG, "the big file came back intact")
  SaveData = fresh()
  eq(SaveData.portableBaseDir(), nil, "the next launch uses the app's own storage")
end

eq(quits, 0, "G.move itself never quits the game")
if skippedDirChecks > 0 then
  print(("(%d empty-folder cleanup checks skipped: Windows remove() keeps directories)")
    :format(skippedDirChecks))
end
rmrf(ROOT)
S.finish()
