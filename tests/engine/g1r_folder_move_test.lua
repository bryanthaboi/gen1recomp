package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("g1r folder move")
local check, eq = S.check, S.eq

local WIN = package.config:sub(1, 1) == "\\"

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

local skippedDirChecks = 0
local function checkGone(paths, msg)
  if WIN then skippedDirChecks = skippedDirChecks + 1 return end
  for _, path in ipairs(paths) do
    if isDir(path) then check(false, msg .. " (" .. path .. " is still there)") return end
  end
  check(true, msg)
end

local function has(text, part)
  return type(text) == "string" and text:find(part, 1, true) ~= nil
end

local BIG = {}
for i = 0, 255 do BIG[#BIG + 1] = string.char(i) end
BIG = table.concat(BIG):rep(5 * 1024)

local ROOT = scratchRoot()
local APP = ROOT .. "/app"
local POINTER = APP .. "/g1r_storage_folder.txt"
local UNREACHABLE = WIN and "/nonexistent_drive_zz:/G1R" or "/proc/g1r_unreachable/G1R"
rmrf(ROOT)

local quits, boxes, pressButton = 0, {}, 2
love.system = love.system or {}
love.system.getOS = function() return "Android" end
love.system.requestStorageAccess = nil
love.filesystem = love.filesystem or {}
love.filesystem.getSaveDirectory = function() return APP end
love.filesystem.read = function(name) return get(APP .. "/" .. name) end
love.filesystem.write = function(name, body) put(APP .. "/" .. name, body); return true end
love.filesystem.remove = function(name) return os.remove(APP .. "/" .. name) ~= nil end
love.window = love.window or {}
love.window.showMessageBox = function(title, msg, buttons)
  boxes[#boxes + 1] = { title = title, msg = msg, buttons = type(buttons) == "table" and buttons or nil }
  return pressButton
end
love.event = love.event or {}
love.event.quit = function() quits = quits + 1 end
local realWrite = love.filesystem.write

local function fresh()
  package.loaded["src.core.SaveData"] = nil
  package.loaded["src.core.G1RFolder"] = nil
  local SaveData, G = require("src.core.SaveData"), require("src.core.G1RFolder")
  table.insert(G.ROOTS, 1, "^(" .. ROOT:gsub("%p", "%%%0") .. ")(.*)$")
  return SaveData, G
end

local ORIGINALS = {
  ["options.lua"] = "opts = 1",
  ["save/red.sav"] = "red save",
  ["save/blue.sav"] = "blue save",
  ["cache/rom.bin"] = BIG,
}
for rel, body in pairs(ORIGINALS) do put(APP .. "/" .. rel, body) end

local function originalsIntact(base, what)
  for rel, body in pairs(ORIGINALS) do
    check(get(base .. "/" .. rel) == body, what .. ": " .. rel .. " still in place, unchanged")
  end
end

local function noCopies(dest, what)
  for rel in pairs(ORIGINALS) do
    check(get(dest .. "/" .. rel) == nil, what .. ": no copy of " .. rel .. " left behind")
  end
end

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

do
  local _, G = fresh()
  for _, path in ipairs({
    "/storage/emulated/0/G1R", "/storage/emulated/0/Download/G1R",
    "/storage/emulated/0/Documents/G1R", "/storage/1A2B-3C4D/G1R", "/sdcard/Games/G1R",
  }) do
    eq(G.unsafeTarget(path), nil, path .. " is allowed")
  end
  for _, preset in ipairs(G.PRESETS) do
    eq(G.unsafeTarget(preset), nil, "preset " .. preset .. " is allowed")
  end
  for _, path in ipairs({
    "/storage/emulated/0", "/storage/emulated/0/Download", "/storage/emulated/0/download",
    "/storage/emulated/0/Documents", "/storage/emulated/0/DCIM", "/storage/emulated/0/Pictures",
    "/storage/emulated/0/Android", "/storage/emulated/0/Android/data/some.app",
    "/storage/1A2B-3C4D", "/storage/emulated", "/sdcard", "/data/data/some.app", "/",
  }) do
    check(type(G.unsafeTarget(path)) == "string", path .. " is refused")
  end
  check(has(G.unsafeTarget("/storage/emulated/0/Download"), "Internal/Download/G1R"),
    "a shared folder suggests a folder of its own inside it")
  eq(G.normalize("Internal/Download"), "/storage/emulated/0/Download", "typed paths normalize")
end

do
  local _, G = fresh()
  for _, dest in ipairs({ ROOT, ROOT .. "/Download", ROOT .. "/Android/data/x" }) do
    local ok, msg = G.move(dest)
    eq(ok, false, "moving into " .. dest .. " is refused")
    check(type(msg) == "string", "with a reason")
  end
  check(not isDir(ROOT .. "/Download"), "a refused shared folder is not even created")
  originalsIntact(APP, "shared folder refused")
  check(get(POINTER) == nil, "the storage setting was not switched")
end

do
  local dest = ROOT .. "/phone/Stuff"
  put(dest .. "/notes.txt", "player's own file")
  put(dest .. "/photo.jpg", "a photo")
  local _, G = fresh()
  local ok, msg = G.move(dest)
  eq(ok, false, "a folder with unrelated files is refused")
  check(has(msg, "already has other files"), "and says why: " .. tostring(msg))
  originalsIntact(APP, "unrelated files")
  noCopies(dest, "unrelated files")
  eq(get(dest .. "/notes.txt"), "player's own file", "the player's files are untouched")
  eq(get(dest .. "/photo.jpg"), "a photo", "all of them")
  check(get(dest .. "/portable.txt") == nil, "no portable.txt was written")
  check(get(POINTER) == nil, "the storage setting was not switched")
end

do
  local SaveData, G = fresh()
  local dest = ROOT .. "/phone/G1R"
  local calls = failNthCopy(G, 3)
  local ok, msg = G.move(dest)
  eq(ok, false, "a failed copy fails the move")
  check(has(msg, "nothing was moved"), "and says nothing was moved: " .. tostring(msg))
  check(calls() == 3, "two copies were made before the third failed")
  originalsIntact(APP, "failed copy")
  noCopies(dest, "failed copy")
  check(get(POINTER) == nil, "the storage setting was not switched")
  checkGone({ dest }, "the new folder it created was removed again")
  check(SaveData.portableBaseDir() == nil, "the game still uses the app's own storage")
end

do
  local dest = ROOT .. "/phone/OldRecomp"
  put(dest .. "/portable.txt", "")
  put(dest .. "/old.sav", "an older save")
  local _, G = fresh()
  failNthCopy(G, 2)
  local ok = G.move(dest)
  eq(ok, false, "a failed copy into an earlier Recomp folder fails")
  originalsIntact(APP, "earlier Recomp folder")
  noCopies(dest, "earlier Recomp folder")
  eq(get(dest .. "/old.sav"), "an older save", "the folder's own files are untouched")
  eq(get(dest .. "/portable.txt"), "", "its portable.txt is kept")
  checkGone({ dest .. "/save", dest .. "/cache" }, "the subfolders made for the copies are gone")
  check(get(POINTER) == nil, "the storage setting was not switched")
end

do
  local dest = ROOT .. "/phone/NoSetting"
  local _, G = fresh()
  love.filesystem.write = function() return false end
  local ok, msg = G.move(dest)
  love.filesystem.write = realWrite
  eq(ok, false, "a setting that can't be saved fails the move")
  check(has(msg, "nothing was moved"), "and says nothing was moved: " .. tostring(msg))
  originalsIntact(APP, "setting not saved")
  noCopies(dest, "setting not saved")
  check(get(dest .. "/portable.txt") == nil, "no portable.txt was left behind")
  checkGone({ dest }, "its folder was removed again")
end

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
  SaveData = fresh()
  eq(SaveData.portableBaseDir(), FIRST, "the next launch uses the new folder")
end

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

do
  local dest = ROOT .. "/phone/Retry"
  put(dest .. "/options.lua", ORIGINALS["options.lua"])
  put(dest .. "/save/red.sav", "a different red save")
  local _, G = fresh()
  local ok, moved = G.move(dest)
  eq(ok, true, "a folder holding only an interrupted move's files is accepted")
  eq(moved, 4, "it still accounts for all four files")
  eq(get(dest .. "/options.lua"), ORIGINALS["options.lua"], "the identical copy is reused")
  check(get(dest .. "/_from_previous_location/options.lua") == nil,
    "an identical file is not copied a second time")
  eq(get(dest .. "/save/red.sav"), "a different red save", "a different file is never overwritten")
  eq(get(dest .. "/_from_previous_location/save/red.sav"), "red save", "ours goes beside it instead")
  check(get(FIRST .. "/options.lua") == nil, "the originals are gone from the old folder")
  eq(get(POINTER), dest .. "\n", "the setting points at the new folder")
end

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

do
  local _, G = fresh()
  local rows = G.settingsRows()
  eq(rows[1].label, "Storage Folder", "row labels go through Strings")
  boxes = {}
  rows[2].setText("Internal/Download")
  check(#boxes == 1 and has(boxes[1].msg, "shared with other apps"), "typing a shared folder is refused")
  check(not has(rows[2].value(), "Download"), "and the pick is unchanged")

  local dest = ROOT .. "/phone/Rows"
  rows[2].setText(dest)
  eq(rows[2].value(), dest, "typing a folder of its own picks it")

  local asked = 0
  love.system.requestStorageAccess = function() asked = asked + 1 return "settings" end
  boxes = {}
  rows[3].action()
  eq(asked, 1, "Move asks for storage access first")
  check(has(boxes[1] and boxes[1].msg, "screen that just opened"), "and explains the settings screen")
  check(not isDir(dest), "nothing moves while access is being turned on")

  love.system.requestStorageAccess = function() asked = asked + 1 return "dialog" end
  boxes = {}
  rows[3].action()
  eq(#boxes, 0, "the permission dialog is left on screen by itself")
  check(not isDir(dest), "nothing moves while the dialog is up")
  local quitsBefore = quits
  rows[3].action()
  check(isDir(dest) and get(dest .. "/options.lua") == "opts = 1", "pressing Move again moves the files")
  eq(quits, quitsBefore + 1, "and closes the game afterwards")
  love.system.requestStorageAccess = nil
  local _, G2 = fresh()
  eq(G2.move(""), true, "moved back to app storage for the next checks")
end

do
  put(POINTER, UNREACHABLE .. "\n")
  local _, G = fresh()
  boxes, pressButton = {}, 2
  eq(G.ensure(), false, "Continue carries on when the folder can't be reached")
  check(boxes[1] and boxes[1].buttons and boxes[1].buttons[3] == nil,
    "without the bridge there is no Allow access button")
  check(has(boxes[1] and boxes[1].msg, "All files access"), "and the steps are spelled out instead")

  love.system.requestStorageAccess = function() return "settings" end
  _, G = fresh()
  boxes, pressButton = {}, 3
  local quitsBefore = quits
  eq(G.ensure(), true, "Allow access opens the settings screen and closes the game")
  eq(boxes[1].buttons[3], "Allow access", "the button is offered when the bridge exists")
  eq(quits, quitsBefore + 1, "the game quits so it starts fresh with access")

  love.system.requestStorageAccess = function() return "dialog" end
  _, G = fresh()
  boxes, pressButton = {}, 3
  eq(G.ensure(), false, "the in-game permission dialog keeps the game running")
  love.system.requestStorageAccess = nil
  pressButton = 2
  os.remove(POINTER)
end

if skippedDirChecks > 0 then
  print(("(%d empty-folder cleanup checks skipped: Windows remove() keeps directories)")
    :format(skippedDirChecks))
end
rmrf(ROOT)
S.finish()
