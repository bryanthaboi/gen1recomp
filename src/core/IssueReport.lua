local SaveData = require("src.core.SaveData")
local Version = require("src.core.Version")

local IssueReport = {}

local FORM_URL = "https://github.com/bryanthaboi/gen1recomp/issues/new"
local TEMPLATE = "bug_report.yml"

local function clean(value)
  if value == nil then return nil end
  local text = tostring(value):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" or text == "unknown" or text == "Unknown" then return nil end
  return text
end

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d, e = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c, d, e
end

local function invoke(fn, ...)
  if type(fn) ~= "function" then return false end
  local ok, result = pcall(fn, ...)
  return ok, result
end

local function commandValue(command)
  if not io or type(io.popen) ~= "function" then return nil end
  local ok, pipe = pcall(io.popen, command, "r")
  if not ok or not pipe then return nil end
  local readOK, value = pcall(pipe.read, pipe, "*l")
  pcall(pipe.close, pipe)
  if not readOK then return nil end
  return clean(value)
end

local function percentEncode(value)
  local text = tostring(value or "")
  return (text:gsub("([^%w%-_%.~])", function(char)
    return ("%%%02X"):format(char:byte())
  end))
end

local function formOS(raw)
  local values = {
    ["OS X"] = "macOS",
    macOS = "macOS",
    Windows = "Windows",
    Linux = "Linux",
    Android = "Android",
    iOS = "iOS",
    NX = "Nintendo Switch",
    UWP = "Xbox",
    Xbox = "Xbox",
  }
  return values[raw] or ""
end

local function loveVersion()
  local major, minor, revision, codename = call(love and love.getVersion)
  if not major then return "" end
  local result = tostring(major) .. "." .. tostring(minor) .. "." .. tostring(revision)
  if codename and codename ~= "" then result = result .. " (" .. tostring(codename) .. ")" end
  return result
end

local function appVersion()
  local version = clean(Version.engine)
  if not version or version == "0.0.0" or version == "0.0.0-dev" then return "" end
  return version
end

local function deviceModel(rawOS, system)
  local model = clean(call(system.getModel))
  if model then return model end
  if rawOS == "OS X" or rawOS == "macOS" then
    return commandValue("sysctl -n hw.model 2>/dev/null")
  end
  if rawOS == "Windows" then
    return commandValue("powershell.exe -NoProfile -NonInteractive -Command \"(Get-CimInstance Win32_ComputerSystem).Model\" 2>NUL")
  end
  if rawOS == "Linux" then
    return commandValue("cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null")
      or commandValue("cat /sys/devices/virtual/dmi/id/model 2>/dev/null")
  end
  if rawOS == "Android" then
    return commandValue("getprop ro.product.model 2>/dev/null")
  end
  return nil
end

local function modRows(context)
  if context and type(context.mods) == "table" then return context.mods end
  local ok, LauncherMods = pcall(require, "src.mods.LauncherMods")
  if ok and LauncherMods and LauncherMods.list then
    local listed = call(LauncherMods.list)
    if type(listed) == "table" then return listed end
  end
  return {}
end

local function modNames(rows, safeMode)
  local enabled = {}
  for _, mod in ipairs(rows or {}) do
    if type(mod) == "table" then
      local name = clean(mod.name or mod.id)
      if name and not safeMode and mod.enabled == true then
        enabled[#enabled + 1] = name
      end
    end
  end
  table.sort(enabled)
  return enabled
end

local function metadata(options, context)
  local system = love and love.system or {}
  local graphics = love and love.graphics or {}
  local window = love and love.window or {}
  local rawOS = clean(call(system.getOS))
  local model = deviceModel(rawOS, system)
  local renderer, rendererVersion, _, rendererDevice = call(graphics.getRendererInfo)
  local width, height = call(graphics.getDimensions)
  local pixelWidth, pixelHeight = call(graphics.getPixelDimensions)
  local modeWidth, modeHeight, flags = call(window.getMode)
  local safeMode = SaveData.isSafeMode(options)
  local rows = modRows(context or {})
  local enabledMods = modNames(rows, safeMode)
  local lines = { "Diagnostics:" }
  local function add(label, value)
    value = clean(value)
    if value then lines[#lines + 1] = "- " .. label .. ": " .. value end
  end
  add("Platform", formOS(rawOS))
  local hardware = model
  if rendererDevice and rendererDevice ~= model then
    hardware = hardware and (hardware .. " (" .. rendererDevice .. ")") or rendererDevice
  end
  add("Device", hardware)
  local rendererDetails = clean(renderer)
  if rendererDetails and clean(rendererVersion) then
    rendererDetails = rendererDetails .. " " .. clean(rendererVersion)
  end
  add("Renderer", rendererDetails)
  local displayWidth, displayHeight = width or modeWidth or pixelWidth, height or modeHeight or pixelHeight
  if displayWidth and displayHeight then
    add("Display", tostring(displayWidth) .. "x" .. tostring(displayHeight))
  end
  if pixelWidth and pixelHeight
      and (pixelWidth ~= displayWidth or pixelHeight ~= displayHeight) then
    add("Pixel display", tostring(pixelWidth) .. "x" .. tostring(pixelHeight))
  end
  if flags and flags.fullscreen == true then add("Fullscreen", "yes") end
  local version = appVersion()
  add("App", version ~= "" and Version.title() or "gen1recomp")
  add("LÖVE", loveVersion())
  if safeMode then add("Safe mode", "on") end
  return {
    rawOS = rawOS,
    os = formOS(rawOS),
    device = model,
    version = version,
    safeMode = safeMode,
    enabledMods = enabledMods,
    metadata = table.concat(lines, "\n"),
  }
end

function IssueReport.build(options, context)
  options = options or SaveData.loadOptions()
  context = context or {}
  local info = metadata(options, context)
  local fields = {
    summary = "",
    mods_which = #info.enabledMods > 0 and table.concat(info.enabledMods, ", ") or "",
    version = info.version or "",
    location = "",
    screenshot = "",
    steps = "",
    expected = "",
    extra = info.metadata,
  }
  local params = {
    "template=" .. percentEncode(TEMPLATE),
    "title=" .. percentEncode("bug: replace this with a meaningful title"),
  }
  local order = { "summary", "mods_which",
    "version", "location", "screenshot", "steps", "expected", "extra" }
  for _, key in ipairs(order) do
    params[#params + 1] = key .. "=" .. percentEncode(fields[key])
  end
  return FORM_URL .. "?" .. table.concat(params, "&"), fields, info
end

function IssueReport.open(options, context)
  local url = IssueReport.build(options, context)
  local system = love and love.system or {}
  local opened, openResult = invoke(system.openURL, url)
  if opened and openResult ~= false then
    return true, url
  end
  local copied, copyResult = invoke(system.setClipboardText, url)
  if copied and copyResult ~= false then
    return true, url, "Issue URL copied to the clipboard."
  end
  local filesystem = love and love.filesystem or {}
  local written, writeResult = invoke(filesystem.write, "issue-report-url.txt", url)
  if written and writeResult ~= false then
    return true, url, "Issue URL saved to issue-report-url.txt."
  end
  return false, url, "No browser, clipboard, or writable save directory is available for the issue report."
end

IssueReport.percentEncode = percentEncode
IssueReport.metadata = metadata

return IssueReport
