local GameVersion = require("src.core.GameVersion")
local SaveData = require("src.core.SaveData")

local RomSources = {}

RomSources.KEEP_DIR = "roms"

local function records(opts)
  local t = type(opts) == "table" and opts.romSources or nil
  return type(t) == "table" and t or {}
end

local function sha1(data)
  local digest = love.data.hash("sha1", data)
  if type(digest) == "userdata" and digest.getString then
    digest = digest:getString()
  end
  return love.data.encode("string", "hex", digest)
end

function RomSources.promptsAllowed()
  if os.getenv("POKEPORT_AUTOPILOT") or os.getenv("POKEPORT_DRIVER") then
    return false
  end
  if os.getenv("POKEPORT_IMPORT_ONLY") == "1" then return false end
  if os.getenv("POKEPORT_IMPORT_ROM") then return false end
  return true
end

function RomSources.isAbsolute(path)
  if type(path) ~= "string" or path == "" then return false end
  return path:sub(1, 1) == "/" or path:match("^%a:[/\\]") ~= nil
    or path:sub(1, 2) == "\\\\"
end

function RomSources.absolute(path)
  if type(path) ~= "string" or path == "" then return nil end
  if RomSources.isAbsolute(path) then return path end
  local cwd = love.filesystem.getWorkingDirectory
    and love.filesystem.getWorkingDirectory()
  if type(cwd) ~= "string" or cwd == "" then return nil end
  return cwd:gsub("[/\\]$", "") .. "/" .. path:gsub("^%./", "")
end

function RomSources.shortPath(path)
  if type(path) ~= "string" then return "" end
  local parts = {}
  for part in path:gmatch("[^/\\]+") do parts[#parts + 1] = part end
  if #parts <= 2 then return path end
  return parts[#parts - 1] .. "/" .. parts[#parts]
end

function RomSources.privateDir()
  local okOs, os_ = pcall(love.system.getOS)
  if not okOs or os_ ~= "iOS" then return nil end
  local okDir, save = pcall(love.filesystem.getSaveDirectory)
  if not okDir or type(save) ~= "string" then return nil end
  local root = save:match("^(.*)/Documents/?$")
  if not root then return nil end
  return root .. "/Library"
end

local function keptName(version)
  local gen = GameVersion.generation(version)
  local ext = ".gb"
  if gen == 3 then
    ext = ".gba"
  elseif version == "yellow" or gen == 2 then
    ext = ".gbc"
  end
  return version .. ext
end

RomSources.PRIVATE_PREFIX = "@library/"

function RomSources.keptPath(version)
  if RomSources.privateDir() then
    local identity = love.filesystem.getIdentity and love.filesystem.getIdentity()
      or "game"
    return RomSources.PRIVATE_PREFIX .. "kept-rom-" .. tostring(identity) .. "-"
      .. keptName(version)
  end
  return RomSources.KEEP_DIR .. "/" .. keptName(version)
end

local function nativePath(path)
  local prefix = RomSources.PRIVATE_PREFIX
  if path:sub(1, #prefix) == prefix then
    local dir = RomSources.privateDir()
    if not dir then return nil end
    return dir .. "/" .. path:sub(#prefix + 1)
  end
  if RomSources.isAbsolute(path) then return path end
  return nil
end

function RomSources.readKept(path)
  if type(path) ~= "string" then return nil end
  local native = nativePath(path)
  if native then
    local file = io.open(native, "rb")
    if not file then return nil end
    local data = file:read("*a")
    file:close()
    return data
  end
  local data = love.filesystem.read(path)
  return type(data) == "string" and data or nil
end

function RomSources.keptExists(path)
  if type(path) ~= "string" then return false end
  local native = nativePath(path)
  if native then
    local file = io.open(native, "rb")
    if not file then return false end
    file:close()
    return true
  end
  return love.filesystem.getInfo(path, "file") ~= nil
end

function RomSources.removeKept(path)
  if type(path) ~= "string" then return end
  local native = nativePath(path)
  if native then
    os.remove(native)
  elseif path:sub(1, #RomSources.PRIVATE_PREFIX) ~= RomSources.PRIVATE_PREFIX then
    love.filesystem.remove(path)
  end
end

local function writeKept(path, data)
  local native = nativePath(path)
  if native then
    local file = io.open(native, "wb")
    if not file then return false end
    local ok = file:write(data)
    file:close()
    return ok ~= nil
  end
  love.filesystem.createDirectory(RomSources.KEEP_DIR)
  return love.filesystem.write(path, data) == true
end

function RomSources.get(version, opts)
  local rec = records(opts or SaveData.loadOptions())[version]
  return type(rec) == "table" and rec or nil
end

function RomSources.remember(version, rec)
  local all = {}
  for k, v in pairs(records(SaveData.loadOptions())) do all[k] = v end
  all[version] = rec
  return SaveData.saveOptions({ romSources = all })
end

function RomSources.keep(version, data)
  local path = RomSources.keptPath(version)
  if not writeKept(path, data) then return nil end
  return path
end

function RomSources.migrateKept(opts)
  opts = opts or SaveData.loadOptions()
  local changed, all = false, {}
  for version, rec in pairs(records(opts)) do
    all[version] = rec
    if type(rec) == "table" and rec.kept and type(rec.path) == "string" then
      local want = RomSources.keptPath(version)
      if rec.path ~= want then
        local data = RomSources.readKept(rec.path)
        if data and writeKept(want, data) then
          RomSources.removeKept(rec.path)
          local moved = {}
          for k, v in pairs(rec) do moved[k] = v end
          moved.path = want
          all[version] = moved
          changed = true
        end
      end
    end
  end
  if changed then
    local fs = love.filesystem
    if fs.getInfo(RomSources.KEEP_DIR, "directory")
        and #fs.getDirectoryItems(RomSources.KEEP_DIR) == 0 then
      fs.remove(RomSources.KEEP_DIR)
    end
    SaveData.saveOptions({ romSources = all })
  end
  return changed
end

function RomSources.autoReimport(opts)
  opts = opts or SaveData.loadOptions()
  return type(opts) == "table" and opts.autoReimport == true
end

function RomSources.setAutoReimport(on)
  return SaveData.saveOptions({ autoReimport = on == true })
end

function RomSources.forgetAll(opts)
  for _, rec in pairs(records(opts)) do
    if type(rec) == "table" and rec.kept and type(rec.path) == "string" then
      RomSources.removeKept(rec.path)
    end
  end
  for version in pairs(GameVersion.VERSIONS) do
    local path = RomSources.keptPath(version)
    if nativePath(path) then RomSources.removeKept(path) end
  end
  if love.filesystem.getInfo(RomSources.KEEP_DIR, "directory") then
    for _, name in ipairs(love.filesystem.getDirectoryItems(RomSources.KEEP_DIR)) do
      love.filesystem.remove(RomSources.KEEP_DIR .. "/" .. name)
    end
    love.filesystem.remove(RomSources.KEEP_DIR)
  end
  opts.romSources = nil
end

function RomSources.count(opts)
  local n = 0
  for _, rec in pairs(records(opts)) do
    if type(rec) == "table" then n = n + 1 end
  end
  return n
end

local function readSource(rec)
  if rec.kept then return RomSources.readKept(rec.path) end
  local file = io.open(rec.path, "rb")
  if not file then return nil end
  local data = file:read("*a")
  file:close()
  return data
end

function RomSources.candidate(version, mobile, opts)
  local rec = RomSources.get(version, opts)
  if not rec or type(rec.sha1) ~= "string" then return nil end
  if type(rec.path) ~= "string" then
    if mobile then return { pick = true } end
    return nil
  end
  local ok, data = pcall(readSource, rec)
  local okHash, digest = false, nil
  if ok and data then okHash, digest = pcall(sha1, data) end
  if not okHash or digest ~= rec.sha1 then
    if rec.kept then return { pick = true, broken = true } end
    return nil
  end
  return { path = rec.path, kept = rec.kept == true }
end

function RomSources.drop(version)
  local opts = SaveData.loadOptions()
  local rec = records(opts)[version]
  if type(rec) == "table" and rec.kept and type(rec.path) == "string" then
    RomSources.removeKept(rec.path)
  end
  local all = {}
  for k, v in pairs(records(opts)) do
    if k ~= version then all[k] = v end
  end
  return SaveData.saveOptions({ romSources = all })
end

return RomSources
