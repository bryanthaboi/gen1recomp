-- LauncherMods.installZip: PK gate, FileData mount preference, path fallback.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("launcher mods installZip mount")
local eq = S.eq
local check = S.check

local MOD_ID = "mount_probe"
local ARCHIVE = {
  [MOD_ID .. "/manifest.json"] =
    ('{"id":"%s","name":"Mount Probe","version":"1.0.0","entry":"main.lua"}')
      :format(MOD_ID),
  [MOD_ID .. "/main.lua"] = "return function() end\n",
}

local files, dirs, arch = {}, {}, {}
local fileDataMounts, pathMounts, stagedTemps = 0, 0, {}
local stagedEver = false

local function resetFs()
  for k in pairs(files) do files[k] = nil end
  for k in pairs(dirs) do dirs[k] = nil end
  for k in pairs(arch) do arch[k] = nil end
  fileDataMounts, pathMounts = 0, 0
  stagedTemps = {}
  stagedEver = false
end

local function dirChild(key, name)
  if name == nil or name == "" then return key:match("^[^/]+") end
  local prefix = name .. "/"
  if key:sub(1, #prefix) ~= prefix then return nil end
  return key:sub(#prefix + 1):match("^[^/]+")
end

local function mapInfo(map, name, kind)
  if map[name] ~= nil then return { type = kind or "file" } end
  for key in pairs(map) do
    if dirChild(key, name) then return { type = "directory" } end
  end
  return nil
end

local vfs = {}

function vfs.write(name, data)
  files[name] = data
  if name:match("^mod_import_") then
    stagedTemps[name] = true
    stagedEver = true
  end
  return true
end

function vfs.read(name)
  if arch[name] ~= nil then return arch[name] end
  return files[name]
end

function vfs.remove(name)
  files[name] = nil
  dirs[name] = nil
  stagedTemps[name] = nil
  return true
end

function vfs.createDirectory(name)
  dirs[name] = true
  return true
end

function vfs.getInfo(name, kind)
  local info = mapInfo(arch, name)
    or mapInfo(files, name)
    or mapInfo(dirs, name, "directory")
  if info and kind and info.type ~= kind then return nil end
  return info
end

function vfs.getDirectoryItems(name)
  local seen, items = {}, {}
  local function add(child)
    if child and not seen[child] then
      seen[child] = true
      items[#items + 1] = child
    end
  end
  for key in pairs(arch) do add(dirChild(key, name)) end
  for key in pairs(files) do add(dirChild(key, name)) end
  for key in pairs(dirs) do add(dirChild(key, name)) end
  table.sort(items)
  return items
end

function vfs.mount(archive, point)
  if type(archive) == "table" and archive.__filedata then
    fileDataMounts = fileDataMounts + 1
  else
    pathMounts = pathMounts + 1
  end
  for rel, body in pairs(ARCHIVE) do
    arch[point .. "/" .. rel] = body
  end
  return true
end

function vfs.unmount()
  for k in pairs(arch) do arch[k] = nil end
  return true
end

function vfs.newFileData(data, name)
  return { __filedata = true, data = data, name = name }
end

function vfs.getSaveDirectory()
  return "/tmp/pokeport-install-zip-test"
end

function vfs.getSource()
  return nil
end

local savedFs = love.filesystem
local savedCacheFs = package.loaded["src.import.CacheFs"]
local savedLauncherMods = package.loaded["src.mods.LauncherMods"]
local savedSaveDataPortable = nil

local SaveData = require("src.core.SaveData")
savedSaveDataPortable = SaveData.portableBaseDir

local function freshMods()
  package.loaded["src.import.CacheFs"] = nil
  package.loaded["src.mods.LauncherMods"] = nil
  SaveData.portableBaseDir = function() return nil end
  return require("src.mods.LauncherMods")
end

love.filesystem = vfs
local LauncherMods = freshMods()

-- Reject non-PK / empty / AppleDouble-shaped bytes before mount
resetFs()
files["imports/mods/junk.zip"] = "\0\5\22\7AppleDouble"
local ok, err = LauncherMods.installZip("imports/mods/junk.zip")
check(not ok, "non-PK bytes are rejected")
check(tostring(err):find("not a zip file", 1, true),
  "rejection names not a zip file")
eq(fileDataMounts + pathMounts, 0, "invalid zip never mounts")

resetFs()
files["imports/mods/empty.zip"] = ""
ok, err = LauncherMods.installZip("imports/mods/empty.zip")
check(not ok, "empty file is rejected")
check(tostring(err):find("not a zip file", 1, true),
  "empty rejection is not a zip file")

-- Prefer FileData / in-memory mount for relative save-dir zips
resetFs()
files["imports/mods/good.zip"] = "PK\3\4relative-inbox"
ok, err = LauncherMods.installZip("imports/mods/good.zip")
check(ok == true, "PK zip installs via relative love.filesystem path ("
  .. tostring(err) .. ")")
eq(err, MOD_ID, "install reports manifest id")
eq(fileDataMounts, 1, "relative zip prefers FileData mount")
eq(pathMounts, 0, "relative zip does not fall back to path mount when FileData works")
local staged = 0
for _ in pairs(stagedTemps) do staged = staged + 1 end
eq(staged, 0, "FileData path leaves no staged temp zip")
check(files["mods/" .. MOD_ID .. "/manifest.json"] ~= nil,
  "install wrote manifest into mods/")

-- Fallback: no newFileData → stage temp + path mount
resetFs()
vfs.newFileData = nil
package.loaded["src.mods.LauncherMods"] = nil
package.loaded["src.import.CacheFs"] = nil
LauncherMods = freshMods()
files["imports/mods/fallback.zip"] = "PK\3\4fallback"
ok, err = LauncherMods.installZip("imports/mods/fallback.zip")
check(ok == true, "install still works without newFileData ("
  .. tostring(err) .. ")")
eq(fileDataMounts, 0, "no FileData mounts when API absent")
eq(pathMounts, 1, "falls back to path mount")
check(stagedEver, "fallback stages a mod_import_*.zip temp")
local leftover = 0
for _ in pairs(stagedTemps) do leftover = leftover + 1 end
eq(leftover, 0, "fallback cleans staged temp after install")

-- Restore
love.filesystem = savedFs
SaveData.portableBaseDir = savedSaveDataPortable
package.loaded["src.import.CacheFs"] = savedCacheFs
package.loaded["src.mods.LauncherMods"] = savedLauncherMods

S.finish()
