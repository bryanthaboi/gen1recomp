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
  mode = "rom", -- "rom", "save", "mod", "all"
  currentDir = "/",
  entries = {},
  selectedIdx = 1,
  page = 1,
  perPage = 8,
  onSelect = nil,
  onCancel = nil,
  shortcutIdx = 1,
}

local SHORTCUTS = {
  { label = "SD Card", path = "/mnt/SDCARD" },
  { label = "GB ROMs", path = "/roms/gb" },
  { label = "GBC ROMs", path = "/roms/gbc" },
  { label = "Ports", path = "/roms/ports" },
  { label = "Game Dir", path = "." },
  { label = "Storage", path = "/storage" },
  { label = "Userdata", path = "/userdata/roms" },
  { label = "Root /", path = "/" },
}

local function findSdCardRoot()
  local candidates = {
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
  for _, path in ipairs(candidates) do
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

local function normalizePath(p)
  if not p or p == "" then return "/" end
  p = p:gsub("\\", "/")
  if p:sub(1, 1) ~= "/" and p:sub(1, 2) ~= "./" and p:sub(1, 3) ~= "../" then
    p = "/" .. p
  end
  p = p:gsub("/+", "/")
  return p
end

local function parentDir(p)
  p = normalizePath(p)
  if p == "/" or p == "." then return "/" end
  local parent = p:match("^(.*)/[^/]+/?$")
  if not parent or parent == "" then return "/" end
  return parent
end

local function isMatchingFilter(name, isDir, mode)
  if isDir then return true end
  local ext = name:match("%.([^.]+)$")
  if not ext then return (mode == "all") end
  ext = ext:lower()
  if mode == "rom" then
    return (ext == "gb" or ext == "gbc" or ext == "zip")
  elseif mode == "save" then
    return (ext == "sav" or ext == "lua")
  elseif mode == "mod" then
    return (ext == "zip")
  end
  return true
end

local function scanDirectory(dir, mode)
  dir = normalizePath(dir)
  local entries = {}

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
              path = (dir == "/" and "/" .. cleanName) or (dir .. "/" .. cleanName),
            })
          end
        end
      end
    end
  end

  if #entries == 0 and love and love.filesystem and love.filesystem.getDirectoryItems then
    local okFs, items = pcall(love.filesystem.getDirectoryItems, dir)
    if okFs and items then
      for _, name in ipairs(items) do
        local full = (dir == "/" and "/" .. name) or (dir .. "/" .. name)
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
  FileBrowser.selectedIdx = 1
  FileBrowser.page = 1

  local initPath = opts.initialPath or findSdCardRoot()
  FileBrowser.currentDir = initPath
  FileBrowser.entries = scanDirectory(FileBrowser.currentDir, FileBrowser.mode)
  if #FileBrowser.entries == 0 and initPath ~= "/" then
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
  FileBrowser.shortcutIdx = (FileBrowser.shortcutIdx % #SHORTCUTS) + 1
  local target = SHORTCUTS[FileBrowser.shortcutIdx]
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
    if FileBrowser.currentDir ~= "/" and FileBrowser.currentDir ~= "." then
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
