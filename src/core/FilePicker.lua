local Platform = require("src.core.Platform")
local HostShell = require("src.core.HostShell")

local FilePicker = {}

FilePicker.IMAGE = {
  label = "Image",
  exts = { "png", "jpg", "jpeg" },
  tempName = "pokeport_image_pick",
}

local function trim(value)
  return value and value:gsub("^%s+", ""):gsub("%s+$", "") or ""
end

local function shellSafe(s)
  s = tostring(s):gsub("%%", "%%%%")
  return s:gsub('"', '\\"'):gsub("'", "''")
end

local function commandOutput(command)
  if not Platform.canSpawnProcess() then return nil end
  local pipe = HostShell.popen(command)
  if not pipe then return nil end
  local result = pipe:read("*a")
  HostShell.pclose(pipe)
  result = trim(result)
  return result ~= "" and result or nil
end

local function appleTypes(exts)
  local out = {}
  for _, ext in ipairs(exts) do out[#out + 1] = '"' .. ext .. '"' end
  return table.concat(out, ", ")
end

local function windowsPatterns(exts)
  local out = {}
  for _, ext in ipairs(exts) do out[#out + 1] = "*." .. ext end
  return table.concat(out, ";")
end

local function globPatterns(exts)
  local out = {}
  for _, ext in ipairs(exts) do out[#out + 1] = "*." .. ext end
  return table.concat(out, " ")
end

function FilePicker.available()
  return Platform.canSpawnProcess()
end

function FilePicker.matches(name, kind)
  local lower = tostring(name or ""):lower()
  for _, ext in ipairs(kind.exts) do
    if lower:match("%." .. ext .. "$") then return true end
  end
  return false
end

function FilePicker.open(prompt, kind)
  if not Platform.canSpawnProcess() then return nil end
  local title = shellSafe(prompt)
  local platform = love.system.getOS()
  if platform == "OS X" then
    return commandOutput(
      ([[osascript -e 'POSIX path of (choose file with prompt "%s" of type {%s})' 2>/dev/null]])
        :format(title, appleTypes(kind.exts)))
  elseif platform == "Windows" then
    local script = table.concat({
      "Add-Type -AssemblyName System.Windows.Forms;",
      "$d=New-Object System.Windows.Forms.OpenFileDialog;",
      "$d.Title='" .. title .. "';",
      "$d.Filter='" .. kind.label .. " (" .. windowsPatterns(kind.exts) .. ")|"
        .. windowsPatterns(kind.exts) .. "|All files (*.*)|*.*';",
      "if($d.ShowDialog() -eq 'OK'){",
      "$n=[IO.Path]::GetFileName($d.FileName) -replace '[^\\x20-\\x7E]','_';",
      "$t=Join-Path $env:TEMP $n;",
      "Copy-Item -LiteralPath $d.FileName -Destination $t -Force;",
      "[Console]::OutputEncoding=[Text.Encoding]::UTF8;",
      "[Console]::Write($t)}",
    })
    return commandOutput(
      'powershell -NoProfile -STA -Command "' .. script .. '"')
  elseif platform == "Linux" then
    local path = commandOutput(
      ([[zenity --file-selection --title="%s" --file-filter="%s | %s" 2>/dev/null]])
        :format(title, kind.label, globPatterns(kind.exts)))
    if path then return path end
    return commandOutput(([[kdialog --getopenfilename "$HOME" "%s|%s" 2>/dev/null]])
      :format(globPatterns(kind.exts), kind.label))
  end
  return nil
end

function FilePicker.read(path)
  local file, openError = io.open(path, "rb")
  if not file then return nil, openError end
  local data = file:read("*a")
  file:close()
  if not data or data == "" then return nil, "empty file" end
  return data
end

function FilePicker.basename(path)
  return tostring(path or ""):match("([^/\\]+)$") or tostring(path or "")
end

return FilePicker
