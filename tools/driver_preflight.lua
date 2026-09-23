local script = arg[0] or "tools/driver_preflight.lua"
local root = script:match("^(.*)/tools/[^/]+$")
  or (script:match("^tools/[^/]+$") and ".")
  or (script:match("^(.*)/[^/]+$") and (script:match("^(.*)/[^/]+$") .. "/.."))
  or ".."
package.path = root .. "/?.lua;" .. root .. "/?/init.lua;" .. package.path

local HELP = [[
usage: luajit tools/driver_preflight.lua <identity> <version> [--identity-only]

Prints READY or STALE <reason> for a POKEPORT_IDENTITY cache, using the
same checks as CacheContract.isReady. Without --identity-only a complete
source-tree data/generated also counts as READY. Exits 0 when READY.
]]

local identity, version = arg[1], arg[2]
if identity == "-h" or identity == "--help" then
  io.stdout:write(HELP)
  os.exit(0)
end
local identityOnly = arg[3] == "--identity-only"
if not identity or not version then
  io.stderr:write(HELP)
  os.exit(2)
end

local GameVersion = require("src.core.GameVersion")
local CacheContract = require("src.import.CacheContract")

if not GameVersion.VERSIONS[version] then
  print("STALE unknown version " .. version)
  os.exit(1)
end

local home = os.getenv("HOME") or ""
local function isDir(path)
  local f = io.open(path .. "/.", "rb")
  if f then f:close() return true end
  return false
end
local function hostOs()
  if jit and jit.os then return jit.os end
  local p = io.popen("uname -s 2>/dev/null")
  local name = p and p:read("*l") or ""
  if p then p:close() end
  if name == "Darwin" then return "OSX" end
  if name == "" and package.config:sub(1, 1) == "\\" then return "Windows" end
  return "Linux"
end

local saveDir
local osName = hostOs()
if osName == "OSX" then
  saveDir = home .. "/Library/Application Support/LOVE/" .. identity
elseif osName == "Windows" then
  saveDir = (os.getenv("APPDATA") or (home .. "/AppData/Roaming")) .. "/LOVE/" .. identity
else
  local xdg = os.getenv("XDG_DATA_HOME")
  if not xdg or xdg == "" then xdg = home .. "/.local/share" end
  saveDir = xdg .. "/love/" .. identity
end

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

local function isFile(path)
  local f = io.open(path, "rb")
  if not f then return false end
  local data, err = f:read(0)
  f:close()
  return data ~= nil or err == nil
end

local function sourceTreeHasData()
  local prefix = version == "red" and "" or GameVersion.cachePrefix(version)
  local required, isOverride = CacheContract.requiredFilesFor(version)
  for _, path in ipairs(required) do
    if not isFile(root .. "/" .. prefix .. path) then return false end
  end
  if not isOverride then
    for _, path in ipairs(CacheContract.VERSION_REQUIRED_FILES[version] or {}) do
      if not isFile(root .. "/" .. prefix .. path) then return false end
    end
  end
  return true
end

local fs = { prefix = "" }
function fs.exists(rel) return isFile(saveDir .. "/" .. fs.prefix .. rel) end
function fs.read(rel) return readFile(saveDir .. "/" .. fs.prefix .. rel) end

if not identityOnly and sourceTreeHasData() then
  print("READY source tree")
  os.exit(0)
end
if not isDir(saveDir) then
  print("STALE identity missing " .. saveDir)
  os.exit(1)
end
local marker, readError = CacheContract.readMarker(version, fs)
if readError or marker == nil then
  print("STALE marker missing")
  os.exit(1)
end
if not CacheContract.markerMatches(version, marker) then
  print("STALE marker mismatch " .. tostring(marker) .. " want " .. CacheContract.formatFor(version))
  os.exit(1)
end
if not CacheContract.cacheVersionCurrent(version, fs) then
  local raw = fs.read(GameVersion.cachePrefix(version) .. "data/generated/gba/meta.json") or ""
  print("STALE gba cache_version " .. tostring(raw:match('"cache_version"%s*:%s*(%d+)'))
    .. " want " .. tostring(require("src.import.gba.versions").CACHE_VERSION))
  os.exit(1)
end
local complete, missing = CacheContract.allRequiredFilesExist(version, fs)
if not complete then
  print("STALE missing " .. tostring(missing))
  os.exit(1)
end
print("READY")
