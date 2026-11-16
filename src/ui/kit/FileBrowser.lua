-- Immediate-mode in-launcher File Browser for handhelds and gamepads.
-- Allows navigating directories to pick ROM files (.gb/.gbc), import save files (.sav),
-- and select mod/skin archives (.zip) without requiring host desktop GUI pickers (zenity/kdialog).

local Theme = require("src.ui.kit.Theme")
local HostShell = require("src.core.HostShell")

-- POSIX shell quoting for the ls/test commands below.  HostShell.quote is the
-- shared helper, but the launcher may run where HostShell is a minimal shim
-- (the NX gate), so fall back to the same escaping locally.
local function shQuote(path)
  if HostShell and type(HostShell.quote) == "function" then
    return HostShell.quote(path)
  end
  return "'" .. tostring(path):gsub("'", "'\\''") .. "'"
end
local PAL = Theme.PAL
local Kit = nil
local function getKit()
  if not Kit then Kit = require("src.ui.kit.Kit") end
  return Kit
end

local FileBrowser = {
  active = false,
  title = "Select File",
  mode = "rom", -- "rom", "save", "mod", "cart", "all"
  currentDir = "/",
  entries = {},
  selectedIdx = 1,
  page = 1,
  perPage = 8,
  onSelect = nil,
  onCancel = nil,
  shortcutIdx = 1,
  -- Test seam: replaces SaveData's native FS (listNative, statNative, ...).
  nativeFs = nil,
}

-- ------- paths
-- Windows paths keep their drive letter (C:/roms, not /C:/roms).
local function stripTrailingSlash(p)
  if #p > 1 and p:sub(-1) == "/" and not p:match("^%a:/$") then
    return p:sub(1, -2)
  end
  return p
end

local function normalizePath(p)
  if not p or p == "" then return "/" end
  p = p:gsub("\\", "/"):gsub("/+", "/")
  if p == "." or p == "./" then return "." end
  if p:match("^%a:$") then return p .. "/" end
  if p:match("^%a:/") then return stripTrailingSlash(p) end
  if p:sub(1, 1) ~= "/" and p:sub(1, 2) ~= "./" and p:sub(1, 3) ~= "../" then
    p = "/" .. p
  end
  return stripTrailingSlash(p)
end

local function parentDir(p)
  p = normalizePath(p)
  if p == "/" or p == "." then return "/" end
  if p:match("^%a:/$") then return p end
  local parent = p:match("^(.*)/[^/]+$")
  if not parent or parent == "" then return "/" end
  if parent:match("^%a:$") then return parent .. "/" end
  return parent
end

local function joinPath(dir, name)
  if dir == "/" then return "/" .. name end
  if dir:sub(-1) == "/" then return dir .. name end
  return dir .. "/" .. name
end

local function isRootPath(p)
  p = normalizePath(p)
  return p == "/" or p == "." or p:match("^%a:/$") ~= nil
end

-- ------- filesystem access
-- love.filesystem only reaches the save directory, so absolute paths need the
-- native enumerator in SaveData.
local nativeFs, nativeProbed = nil, false
local function getNativeFs()
  -- Test seam: a stub table overrides the real module.
  if type(FileBrowser.nativeFs) == "table" then return FileBrowser.nativeFs end
  if nativeProbed then return nativeFs end
  nativeProbed = true
  local ok, SaveData = pcall(require, "src.core.SaveData")
  if ok and type(SaveData) == "table"
      and type(SaveData.listNative) == "function"
      and type(SaveData.statNative) == "function" then
    nativeFs = SaveData
  end
  return nativeFs
end

local function osName()
  return (love and love.system and love.system.getOS and love.system.getOS()) or ""
end

local function isWindows() return osName() == "Windows" end

-- A handheld keeps its ROMs on an SD card, not in the game folder.
local function isHandheldEnv()
  return os.getenv("HANDHELD") == "1" or os.getenv("PORTMASTER") == "1"
    or os.getenv("POKEPORT_HANDHELD") == "1" or os.getenv("TRIMUI") == "1"
    or os.getenv("MUOS") == "1" or os.getenv("KNULLI") == "1"
end

local function isDesktopShell()
  local o = osName()
  return (o == "Windows" or o == "Linux" or o == "OS X") and not isHandheldEnv()
end

local function nativeList(dir)
  local fs = getNativeFs()
  if not (fs and type(fs.listNative) == "function") then return nil end
  local ok, names = pcall(fs.listNative, dir)
  if not ok or type(names) ~= "table" then return nil end
  return names
end

local function nativeStat(path)
  local fs = getNativeFs()
  if not (fs and type(fs.statNative) == "function") then return nil end
  local ok, st = pcall(fs.statNative, path)
  if not ok then return nil end
  return st
end

local function isDirectory(path)
  local fs = getNativeFs()
  if fs and type(fs.isDirNative) == "function" then
    local ok, yes = pcall(fs.isDirNative, path)
    if ok and yes ~= nil then return yes and true or false end
  end
  local st = nativeStat(path)
  return st ~= nil and st.type == "directory"
end

-- Where the SD-card mounts would be on a handheld.
local SD_CARD_CANDIDATES = {
  "/mnt/SDCARD",
  "/mnt/sdcard",
  "/mnt/mmc",
  "/sdcard",
  "/roms",
  "/storage/roms",
  "/userdata/roms",
  "/storage",
  "/userdata",
}

-- The first existing folder from SaveData.gameFolders(), or the save directory.
local function desktopStartDir()
  local fs = getNativeFs()
  if fs and type(fs.gameFolders) == "function" then
    local ok, folders = pcall(fs.gameFolders)
    if ok and type(folders) == "table" then
      for _, dir in ipairs(folders) do
        if type(dir) == "string" and dir ~= "" then
          local norm = normalizePath(dir)
          if isDirectory(norm) then return norm end
        end
      end
    end
  end
  if love and love.filesystem and love.filesystem.getSaveDirectory then
    local dir = love.filesystem.getSaveDirectory()
    if type(dir) == "string" and dir ~= "" then return normalizePath(dir) end
  end
  return nil
end

-- baseroms/ in any game folder; it is not always the first one gameFolders()
-- returns.
local function romDropDir()
  local fs = getNativeFs()
  if not (fs and type(fs.gameFolders) == "function") then return nil end
  local ok, folders = pcall(fs.gameFolders)
  if not ok or type(folders) ~= "table" then return nil end
  for _, dir in ipairs(folders) do
    if type(dir) == "string" and dir ~= "" then
      local roms = joinPath(normalizePath(dir), "baseroms")
      if isDirectory(roms) then return roms end
    end
  end
  return nil
end

local function findSdCardRoot()
  if isDesktopShell() then
    local dir = desktopStartDir()
    if dir then return dir end
    -- No native enumerator: the POSIX probes below would only fail on Windows.
    if isWindows() then return "/" end
  end
  for _, path in ipairs(SD_CARD_CANDIDATES) do
    local ok, h = pcall(io.popen, string.format("test -d %s && echo \"yes\"", shQuote(path)))
    if ok and h then
      local res = h:read("*a")
      h:close()
      if res and res:match("yes") then
        return path
      end
    end
  end
  return "/"
end

local HANDHELD_SHORTCUTS = {
  { label = "SD Card", path = "/mnt/SDCARD" },
  { label = "GB ROMs", path = "/roms/gb" },
  { label = "GBC ROMs", path = "/roms/gbc" },
  { label = "Ports", path = "/roms/ports" },
  { label = "Game Dir", path = "." },
  { label = "Storage", path = "/storage" },
  { label = "Userdata", path = "/userdata/roms" },
  { label = "Root /", path = "/" },
}

-- The handheld list is meaningless on a desktop (/mnt/SDCARD does not exist).
local function desktopShortcuts()
  local out, seen = {}, {}
  local function add(label, path)
    if type(path) ~= "string" or path == "" then return end
    local norm = normalizePath(path)
    if seen[norm] then return end
    seen[norm] = true
    out[#out + 1] = { label = label, path = norm }
  end
  local start = desktopStartDir()
  add("Game Dir", start)
  local fs = getNativeFs()
  if fs and type(fs.gameFolders) == "function" then
    local ok, folders = pcall(fs.gameFolders)
    if ok and type(folders) == "table" then
      for i = 2, #folders do add("Game Dir " .. i, folders[i]) end
    end
  end
  add("baseroms/", romDropDir())
  if love and love.filesystem and love.filesystem.getSaveDirectory then
    add("Save Dir", love.filesystem.getSaveDirectory())
  end
  if #out == 0 then return HANDHELD_SHORTCUTS end
  return out
end

local function shortcuts()
  if isDesktopShell() then return desktopShortcuts() end
  return HANDHELD_SHORTCUTS
end

local function isMatchingFilter(name, isDir, mode)
  if isDir then return true end
  local ext = name:match("%.([^.]+)$")
  if not ext then return (mode == "all") end
  ext = ext:lower()
  if mode == "rom" then
    return ext == "gb" or ext == "gbc" or ext == "gba" or ext == "agb"
      or ext == "bin" or ext == "zip" or ext == "7z"
  elseif mode == "save" then
    return (ext == "sav" or ext == "srm" or ext == "lua")
  elseif mode == "box" then
    return (ext == "gci" or ext == "sav")
  elseif mode == "mod" then
    return (ext == "zip")
  elseif mode == "cart" then
    return (ext == "g1rcart")
  end
  return true
end

local function scanDirectory(dir, mode)
  dir = normalizePath(dir)
  local entries = {}

  local names = nativeList(dir)
  if names then
    for _, name in ipairs(names) do
      local path = joinPath(dir, name)
      local isDir = isDirectory(path)
      if isMatchingFilter(name, isDir, mode) then
        table.insert(entries, { name = name, isDir = isDir, path = path })
      end
    end
  elseif not isWindows() then
    local ok, handle = pcall(io.popen, string.format("ls -1ap %s 2>/dev/null", shQuote(dir)))
    if ok and handle then
      local output = handle:read("*a")
      handle:close()
      if output and #output > 0 then
        for line in output:gmatch("[^\r\n]+") do
          if line ~= "./" and line ~= "../" and line ~= "." and line ~= ".." then
            local isDir = (line:sub(-1) == "/")
            local cleanName = isDir and line:sub(1, -2) or line
            if isMatchingFilter(cleanName, isDir, mode) then
              table.insert(entries, {
                name = cleanName,
                isDir = isDir,
                path = joinPath(dir, cleanName),
              })
            end
          end
        end
      end
    end
  end

  if #entries == 0 and love and love.filesystem and love.filesystem.getDirectoryItems then
    local okFs, items = pcall(love.filesystem.getDirectoryItems, dir)
    if okFs and items then
      for _, name in ipairs(items) do
        local full = joinPath(dir, name)
        local info = love.filesystem.getInfo and love.filesystem.getInfo(full)
        local isDir = info and info.type == "directory"
        if isMatchingFilter(name, isDir, mode) then
          table.insert(entries, {
            name = name,
            isDir = isDir,
            path = full,
          })
        end
      end
    end
  end

  table.sort(entries, function(a, b)
    if a.isDir ~= b.isDir then
      return a.isDir
    end
    return a.name:lower() < b.name:lower()
  end)

  return entries
end

function FileBrowser.open(opts)
  opts = opts or {}
  FileBrowser.active = true
  FileBrowser.title = opts.title or "Select File"
  FileBrowser.mode = opts.mode or "rom"
  FileBrowser.onSelect = opts.onSelect
  FileBrowser.onCancel = opts.onCancel
  FileBrowser.hint = opts.hint
  FileBrowser.selectedIdx = 1
  FileBrowser.page = 1

  local initPath = opts.initialPath
  if not initPath then
    initPath = findSdCardRoot()
    if opts.mode == "rom" then
      initPath = romDropDir() or initPath
    end
  end
  FileBrowser.currentDir = normalizePath(initPath)
  FileBrowser.entries = scanDirectory(FileBrowser.currentDir, FileBrowser.mode)
  -- "/" is an SD-card notion; on a desktop it is the drive root.
  if #FileBrowser.entries == 0 and initPath ~= "/" and not isDesktopShell() then
    FileBrowser.currentDir = "/"
    FileBrowser.entries = scanDirectory(FileBrowser.currentDir, FileBrowser.mode)
  end
end

function FileBrowser.close(path)
  if not FileBrowser.active then return end
  local onSelect = FileBrowser.onSelect
  local onCancel = FileBrowser.onCancel
  FileBrowser.active = false
  FileBrowser.onSelect = nil
  FileBrowser.onCancel = nil
  FileBrowser.hint = nil
  if path and onSelect then
    onSelect(path)
  elseif not path and onCancel then
    onCancel()
  end
end

function FileBrowser.setDirectory(dir)
  FileBrowser.currentDir = normalizePath(dir)
  FileBrowser.entries = scanDirectory(FileBrowser.currentDir, FileBrowser.mode)
  FileBrowser.selectedIdx = 1
  FileBrowser.page = 1
end

function FileBrowser.cycleShortcut()
  local list = shortcuts()
  if #list == 0 then return end
  FileBrowser.shortcutIdx = (FileBrowser.shortcutIdx % #list) + 1
  local target = list[FileBrowser.shortcutIdx]
  FileBrowser.setDirectory(target.path)
end

function FileBrowser.gamepadpressed(button)
  if not FileBrowser.active then return false end

  local total = #FileBrowser.entries
  local perPage = FileBrowser.perPage
  local maxPage = math.max(1, math.ceil(total / perPage))

  if button == "dpup" then
    if FileBrowser.selectedIdx > 1 then
      FileBrowser.selectedIdx = FileBrowser.selectedIdx - 1
      FileBrowser.page = math.floor((FileBrowser.selectedIdx - 1) / perPage) + 1
    end
    return true
  elseif button == "dpdown" then
    if FileBrowser.selectedIdx < total then
      FileBrowser.selectedIdx = FileBrowser.selectedIdx + 1
      FileBrowser.page = math.floor((FileBrowser.selectedIdx - 1) / perPage) + 1
    end
    return true
  elseif button == "dpleft" or button == "leftshoulder" or button == "triggerleft" or button == "lefttrigger" or button == "l2" then
    if FileBrowser.page > 1 then
      FileBrowser.page = FileBrowser.page - 1
      FileBrowser.selectedIdx = (FileBrowser.page - 1) * perPage + 1
    end
    return true
  elseif button == "dpright" or button == "rightshoulder" or button == "triggerright" or button == "righttrigger" or button == "r2" then
    if FileBrowser.page < maxPage then
      FileBrowser.page = FileBrowser.page + 1
      FileBrowser.selectedIdx = math.min(total, (FileBrowser.page - 1) * perPage + 1)
    end
    return true
  elseif button == "a" or button == "start" then
    local entry = FileBrowser.entries[FileBrowser.selectedIdx]
    if entry then
      if entry.isDir then
        FileBrowser.setDirectory(entry.path)
      else
        FileBrowser.close(entry.path)
      end
    end
    return true
  elseif button == "b" then
    if not isRootPath(FileBrowser.currentDir) then
      FileBrowser.setDirectory(parentDir(FileBrowser.currentDir))
    else
      FileBrowser.close(nil)
    end
    return true
  elseif button == "x" then
    FileBrowser.cycleShortcut()
    return true
  elseif button == "back" or button == "select" then
    FileBrowser.close(nil)
    return true
  end

  return true
end

function FileBrowser.keypressed(key)
  if not FileBrowser.active then return false end
  if key == "escape" then
    FileBrowser.close(nil)
    return true
  elseif key == "up" then
    return FileBrowser.gamepadpressed("dpup")
  elseif key == "down" then
    return FileBrowser.gamepadpressed("dpdown")
  elseif key == "left" then
    return FileBrowser.gamepadpressed("dpleft")
  elseif key == "right" then
    return FileBrowser.gamepadpressed("dpright")
  elseif key == "return" then
    return FileBrowser.gamepadpressed("a")
  elseif key == "backspace" then
    return FileBrowser.gamepadpressed("b")
  end
  return false
end

function FileBrowser.draw(m)
  if not FileBrowser.active then return end

  local Kit = getKit()
  local s = m and m.s or Kit.scale or 1
  local W = (m and m.W) or (love.graphics and love.graphics.getWidth()) or 640
  local H = (m and m.H) or (love.graphics and love.graphics.getHeight()) or 480

  Theme.fill(0, 0, W, H, PAL.bg, 0.94)
  Kit.blockClicks = true

  local pad = math.floor(14 * s)
  local modalW = math.floor(math.min(560 * s, W - 20 * s))
  local modalH = math.floor(math.min(420 * s, H - 20 * s))
  local px = math.floor((W - modalW) / 2)
  local py = math.floor((H - modalH) / 2)

  Kit.card(px, py, modalW, modalH, true)

  local cy = py + pad
  -- Header
  Kit.text("button", FileBrowser.title, px + pad, cy, PAL.heading)
  Kit.tag(px + modalW - pad - math.floor(60 * s), cy, math.floor(60 * s), math.floor(18 * s),
    FileBrowser.mode:upper(), PAL.blue)

  cy = cy + Kit.textHeight("button") + math.floor(6 * s)

  -- Breadcrumb / Current directory bar
  local pathBarH = math.floor(24 * s)
  Theme.fillRounded(px + pad, cy, modalW - 2 * pad, pathBarH, PAL.bg, 1)
  Theme.strokeRounded(px + pad, cy, modalW - 2 * pad, pathBarH, PAL.line, Theme.A.hairline, 1)
  local pathStr = Kit.ellipsizeLeft("small", FileBrowser.currentDir, modalW - 4 * pad)
  Kit.text("small", pathStr, px + pad + math.floor(6 * s), cy + math.floor(4 * s), PAL.heading)

  cy = cy + pathBarH + math.floor(8 * s)

  if FileBrowser.hint then
    cy = cy + Kit.textWrapped("micro", FileBrowser.hint, px + pad, cy, modalW - 2 * pad,
      PAL.red, 2) + math.floor(6 * s)
  end

  -- File / Directory List
  local total = #FileBrowser.entries
  local perPage = FileBrowser.perPage
  local startIdx = (FileBrowser.page - 1) * perPage + 1
  local endIdx = math.min(total, startIdx + perPage - 1)
  local rowH = math.floor(26 * s)
  local rowGap = math.floor(3 * s)

  if total == 0 then
    Theme.fillRounded(px + pad, cy, modalW - 2 * pad, rowH * 4, PAL.bg, 1)
    Kit.textCenter("small", "No files found in this folder.", px + pad, cy + rowH * 1.5, modalW - 2 * pad, PAL.muted)
    cy = cy + rowH * 4 + math.floor(8 * s)
  else
    for i = startIdx, endIdx do
      local entry = FileBrowser.entries[i]
      local isSel = (FileBrowser.selectedIdx == i)
      local rx = px + pad
      local rw = modalW - 2 * pad

      if Kit.press(rx, cy, rw, rowH) then
        FileBrowser.selectedIdx = i
        if entry.isDir then
          FileBrowser.setDirectory(entry.path)
        else
          FileBrowser.close(entry.path)
        end
      end

      if isSel then
        Theme.fillRounded(rx, cy, rw, rowH, PAL.ink, 1)
        local icon = entry.isDir and "[DIR] " or "[FILE] "
        Kit.text("small", icon .. entry.name, rx + math.floor(8 * s), cy + math.floor(4 * s), PAL.inverse)
      else
        Theme.fillRounded(rx, cy, rw, rowH, PAL.surface, 1)
        Theme.strokeRounded(rx, cy, rw, rowH, PAL.line, Theme.A.hairline, 1)
        local icon = entry.isDir and "[DIR] " or "[FILE] "
        local col = entry.isDir and PAL.blue or PAL.text
        Kit.text("small", icon .. entry.name, rx + math.floor(8 * s), cy + math.floor(4 * s), col)
      end

      cy = cy + rowH + rowGap
    end
  end

  -- Pager info & Controls guide
  local bottomY = py + modalH - pad - math.floor(18 * s)
  local pageInfo = string.format("Page %d of %d (%d items)", FileBrowser.page, math.max(1, math.ceil(total / perPage)), total)
  Kit.text("micro", pageInfo, px + pad, bottomY, PAL.muted)

  local guide = "A: Open/Select  B: Parent  X: Shortcut  Start: Confirm  Select: Cancel"
  Kit.textRight("micro", guide, px + modalW - pad, bottomY, PAL.muted)

  Kit.blockClicks = false
end

return FileBrowser
