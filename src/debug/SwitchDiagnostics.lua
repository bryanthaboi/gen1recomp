-- Opt-in Switch diagnostics: ring buffer + ≤1 Hz flush when switch-debug.txt exists.
-- Never logs ROM/save bytes — see spec SWNX-13/28.

local SwitchDiagnostics = {}

local MARKER = "switch-debug.txt"
local LOG_FILE = "switch.log"
local ERROR_LOG = "lua-error.log"
local ERROR_LOG_ROTATED = "lua-error.log.1"
local ERROR_LOG_MAX = 32 * 1024
local FLUSH_INTERVAL = 1.0
local RING_SIZE = 64

local enabled = nil
local buffer = {}
local bufCount = 0
local lastFlushAt = -math.huge
local identityLine = nil

local function fs()
  return love and love.filesystem
end

local function redactString(s)
  if type(s) ~= "string" then return s end
  -- Keep printable ASCII + TAB/LF/CR so Lua stack traces remain readable.
  -- Reject NULs and other C0 controls, and high bytes (ROM/binary dumps).
  for i = 1, #s do
    local b = s:byte(i)
    if b == 0 then return "<redacted>" end
    if b < 32 and b ~= 9 and b ~= 10 and b ~= 13 then return "<redacted>" end
    if b > 126 then return "<redacted>" end
  end
  if #s > 8192 then return s:sub(1, 8192) .. "...<truncated>" end
  return s
end

local function sanitize(value, depth)
  depth = depth or 0
  if depth > 4 then return "<deep>" end
  local t = type(value)
  if t == "string" then return redactString(value) end
  if t == "number" or t == "boolean" or value == nil then return value end
  if t == "table" then
    local out = {}
    for k, v in pairs(value) do
      local key = type(k) == "string" and k or tostring(k)
      if key:lower():find("rom") or key:lower():find("save") then
        out[key] = "<redacted>"
      else
        out[key] = sanitize(v, depth + 1)
      end
    end
    return out
  end
  return tostring(value)
end

local function encodePayload(payload)
  if payload == nil then return "" end
  if type(payload) == "string" then return redactString(payload) end
  local parts = {}
  for k, v in pairs(sanitize(payload)) do
    parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
  end
  table.sort(parts)
  return table.concat(parts, " ")
end

function SwitchDiagnostics._resetForTests()
  enabled = nil
  buffer = {}
  bufCount = 0
  lastFlushAt = -math.huge
  identityLine = nil
  local filesystem = fs()
  if filesystem then
    filesystem.remove(ERROR_LOG)
    filesystem.remove(ERROR_LOG_ROTATED)
  end
end

function SwitchDiagnostics.isEnabled()
  if enabled ~= nil then return enabled end
  local filesystem = fs()
  if not filesystem then
    enabled = false
    return false
  end
  enabled = filesystem.getInfo(MARKER) ~= nil
  return enabled
end

function SwitchDiagnostics.identityOverlay()
  if identityLine then return identityLine end
  local gitCommit = os.getenv("POKEPORT_GIT_COMMIT") or "unknown"
  local loveNxTag = "11.5-nx1"
  local buildVersion = "dev"
  local filesystem = fs()
  if filesystem then
    local raw = filesystem.read("build-info.json")
    if raw and raw ~= "" then
      local ver = raw:match('"version"%s*:%s*"([^"]+)"')
      if ver then buildVersion = ver end
      local tag = raw:match('"loveNxTag"%s*:%s*"([^"]+)"')
      if tag then loveNxTag = tag end
      local commit = raw:match('"gitCommit"%s*:%s*"([^"]+)"')
      if commit then gitCommit = commit end
    end
  end
  identityLine = ("gitCommit=%s loveNxTag=%s buildVersion=%s os=%s"):format(
    gitCommit, loveNxTag, buildVersion,
    love and love.system and love.system.getOS() or "unknown")
  return identityLine
end

function SwitchDiagnostics.onEvent(kind, payload)
  if not SwitchDiagnostics.isEnabled() then return end
  bufCount = bufCount + 1
  local slot = ((bufCount - 1) % RING_SIZE) + 1
  buffer[slot] = ("%s %s"):format(tostring(kind), encodePayload(payload))
end

function SwitchDiagnostics.onJoystickEvent(kind, joystick, button, extra)
  if not SwitchDiagnostics.isEnabled() then return end
  local payload = { button = button }
  if joystick then
    if joystick.getGUID then payload.guid = joystick:getGUID() end
    if joystick.isGamepad then payload.isGamepad = joystick:isGamepad() end
    if joystick.getName then payload.name = joystick:getName() end
  end
  if extra then
    for k, v in pairs(extra) do payload[k] = v end
  end
  SwitchDiagnostics.onEvent(kind, payload)
end

function SwitchDiagnostics.logLuaError(msg)
  local filesystem = fs()
  if not filesystem then return nil end

  local text = redactString(tostring(msg or "unknown error"))
  local existing = filesystem.read(ERROR_LOG) or ""
  if #existing > ERROR_LOG_MAX then
    filesystem.write(ERROR_LOG_ROTATED, existing)
    existing = ""
  end

  local stamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
  local line = ("[%s] %s\n"):format(stamp, text)
  filesystem.write(ERROR_LOG, existing .. line .. SwitchDiagnostics.identityOverlay() .. "\n")

  return "Details saved to lua-error.log in the save directory."
end

function SwitchDiagnostics.maybeFlush(force, now)
  if not SwitchDiagnostics.isEnabled() then return end
  now = now or (love and love.timer and love.timer.getTime() or 0)
  if not force and (now - lastFlushAt) < FLUSH_INTERVAL then return end
  lastFlushAt = now

  local filesystem = fs()
  if not filesystem then return end

  local lines = { SwitchDiagnostics.identityOverlay(), "---" }
  local start = math.max(1, bufCount - RING_SIZE + 1)
  for i = start, bufCount do
    local slot = ((i - 1) % RING_SIZE) + 1
    if buffer[slot] then lines[#lines + 1] = buffer[slot] end
  end
  filesystem.write(LOG_FILE, table.concat(lines, "\n") .. "\n")
end

-- One-shot NX asset probe written on every Play. No ROM/save bytes — only
-- paths, sizes, resolve results, and whether newImage/newImageData open.
-- Pull sdmc:.../pokemon-love2d/nx-asset-probe.log after a Yellow boot.
local PROBE_LOG = "nx-asset-probe.log"

local function probeInfo(filesystem, path)
  local info = filesystem.getInfo(path)
  if not info then return "missing" end
  local size = info.size
  if size == nil then
    local bytes = filesystem.read(path)
    size = type(bytes) == "string" and #bytes or -1
  end
  return ("type=%s size=%s"):format(tostring(info.type), tostring(size))
end

local function probeOpen(kind, path)
  if kind == "image" then
    local ok, err = pcall(love.graphics.newImage, path)
    return ok and "ok" or ("FAIL " .. tostring(err):gsub("%s+", " "):sub(1, 160))
  end
  if not (love.image and love.image.newImageData) then return "skip-no-imageData" end
  local ok, err = pcall(love.image.newImageData, path)
  return ok and "ok" or ("FAIL " .. tostring(err):gsub("%s+", " "):sub(1, 160))
end

function SwitchDiagnostics.probeAssets(version)
  local Platform = require("src.core.Platform")
  if not Platform.isNX() then return end
  local filesystem = fs()
  if not filesystem then return end

  local GameVersion = require("src.core.GameVersion")
  local Assets = require("src.render.Assets")
  local prefix = GameVersion.cachePrefix(version or GameVersion.get())
  local lines = {
    SwitchDiagnostics.identityOverlay(),
    "probe=nx-asset",
    "version=" .. tostring(version or GameVersion.get()),
    "cachePrefix=" .. tostring(prefix),
    "isNX=" .. tostring(Platform.isNX()),
    "saveDir=" .. tostring(filesystem.getSaveDirectory and filesystem.getSaveDirectory() or "?"),
  }

  local samples = {
    "assets/generated/fonts/font.png",
    "assets/generated/tilesets/reds_house.png",
    "assets/generated/sprites/red.png",
    "assets/generated/sprites/monster.png",
    "data/generated/maps.lua",
    "data/generated/oak_speech.lua",
    "data/generated/font.lua",
  }
  for _, path in ipairs(samples) do
    local versioned = prefix ~= "" and (prefix .. path) or path
    local resolved = Assets.resolve(path)
    lines[#lines + 1] = ("--- %s"):format(path)
    lines[#lines + 1] = "unprefixed=" .. probeInfo(filesystem, path)
    if prefix ~= "" then
      lines[#lines + 1] = "versioned=" .. probeInfo(filesystem, versioned)
    end
    lines[#lines + 1] = "resolve=" .. tostring(resolved)
    if path:sub(-4) == ".lua" then
      local CacheFs = require("src.import.CacheFs")
      local loaded, err = CacheFs.loadActive(path)
      lines[#lines + 1] = "loadActive=" .. (loaded ~= nil and "ok"
        or ("FAIL " .. tostring(err):gsub("%s+", " "):sub(1, 160)))
    else
      lines[#lines + 1] = "newImage=" .. probeOpen("image", resolved)
      lines[#lines + 1] = "newImageData=" .. probeOpen("imageData", resolved)
      if prefix ~= "" and resolved ~= versioned then
        lines[#lines + 1] = "newImage_versioned=" .. probeOpen("image", versioned)
        lines[#lines + 1] = "newImageData_versioned=" .. probeOpen("imageData", versioned)
      end
    end
  end

  -- Shallow listing so we can see if the extract tree exists at all.
  local roots = { "yellow", "blue", "gold", "silver", "assets",
    "yellow/assets/generated",
    "yellow/assets/generated/sprites", "blue/assets/generated/sprites",
    "gold/assets/generated", "gold/assets/generated/sprites",
    "gold/data/generated", "silver/assets/generated",
    "silver/data/generated" }
  for _, dir in ipairs(roots) do
    local info = filesystem.getInfo(dir)
    if info and info.type == "directory" and filesystem.getDirectoryItems then
      local items = filesystem.getDirectoryItems(dir) or {}
      local n = math.min(8, #items)
      local head = {}
      for i = 1, n do head[i] = items[i] end
      lines[#lines + 1] = ("list %s count=%d head=%s"):format(
        dir, #items, table.concat(head, ","))
    else
      lines[#lines + 1] = ("list %s %s"):format(dir, info and info.type or "missing")
    end
  end

  filesystem.write(PROBE_LOG, table.concat(lines, "\n") .. "\n")
end

return SwitchDiagnostics
