local Strings = require("src.core.Strings")

local G = {}

local INTERNAL = "/storage/emulated/0"
G.PRESETS = {
  "",
  INTERNAL .. "/G1R",
  INTERNAL .. "/Documents/G1R",
  INTERNAL .. "/Download/G1R",
}
G.ROOTS = {
  "^(/storage/emulated/%d+)(.*)$",
  "^(/storage/[^/]+)(.*)$",
  "^(/sdcard)(.*)$",
}
local NOT_VOLUMES = { ["/storage/emulated"] = true, ["/storage/self"] = true }
local SHARED = {
  alarms = true, android = true, audiobooks = true, dcim = true, documents = true,
  download = true, downloads = true, movies = true, music = true, notifications = true,
  pictures = true, podcasts = true, recordings = true, ringtones = true,
}
local CONFLICT_DIR = "_from_previous_location"
local MARKER = "portable.txt"
local PROBE = ".g1r_probe.tmp"
local CHUNK = 1024 * 1024

local function SD() return require("src.core.SaveData") end

local function log(msg)
  local ok, Logger = pcall(require, "src.core.Logger")
  if ok and type(Logger) == "table" and type(Logger.info) == "function" then
    pcall(Logger.info, "%s", "G1R Folder: " .. tostring(msg))
  end
end

local function messageBox(title, msg, kind)
  pcall(love.window.showMessageBox, title, msg, kind or "info")
end

local function accessHelp()
  return Strings("Give gen1recomp access to your storage:\nAndroid 10 and older: Settings > Apps > gen1recomp > Permissions > Storage > Allow.\nAndroid 11 and newer: Settings > Apps > gen1recomp > All files access (or search Settings for \"all files\") > Allow.")
end

function G.supported()
  return SD().isAndroid()
end

function G.canRequestAccess()
  return type(love.system) == "table" and type(love.system.requestStorageAccess) == "function"
end

function G.requestAccess()
  if not G.canRequestAccess() then return "unavailable" end
  local ok, result = pcall(love.system.requestStorageAccess)
  if ok and (result == "granted" or result == "settings" or result == "dialog") then
    return result
  end
  return "unavailable"
end

function G.pretty(path)
  if not path or path == "" then return Strings("App storage") end
  if path == INTERNAL then return Strings("Internal storage") end
  local rest = path:match("^/storage/emulated/0/(.+)$")
  if rest then return "Internal/" .. rest end
  return path
end

function G.normalize(text)
  text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
  text = text:gsub("\\", "/")
  if text == "" then return nil end
  local lower = text:lower()
  if lower == "app storage" or lower == "app" then return "" end
  if text:sub(1, 1) ~= "/" then
    if lower:sub(1, 17) == "internal storage/" then
      text = text:sub(18)
    elseif lower:sub(1, 9) == "internal/" then
      text = text:sub(10)
    end
    text = INTERNAL .. "/" .. text
  end
  text = text:gsub("/+", "/"):gsub("/$", "")
  if text == "" then return nil end
  for seg in text:gmatch("[^/]+") do
    if seg == ".." or seg == "." then return nil end
  end
  return text
end

function G.unsafeTarget(path)
  if not path or path == "" then return nil end
  local volume, rest
  for _, pattern in ipairs(G.ROOTS) do
    volume, rest = path:match(pattern)
    if volume then break end
  end
  if not volume or NOT_VOLUMES[volume] then
    return Strings("%s isn't on the phone's storage. Pick a folder such as Internal/G1R.", G.pretty(path))
  end
  local first, count = nil, 0
  for seg in rest:gmatch("[^/]+") do
    count = count + 1
    if count == 1 then first = seg:lower() end
  end
  if count == 0 or first == "android" or (count == 1 and SHARED[first]) then
    local suggestion = (count == 1 and first ~= "android") and (path .. "/G1R") or (volume .. "/G1R")
    return Strings("%s is shared with other apps. Pick a folder of its own instead, such as %s.",
      G.pretty(path), G.pretty(suggestion))
  end
  return nil
end

local function writable(dir)
  local path = dir .. "/" .. PROBE
  local f = io.open(path, "wb")
  if not f then return false end
  local ok = f:write("ok") ~= nil
  f:close()
  os.remove(path)
  return ok
end

local function sameFile(a, b)
  local fa = io.open(a, "rb")
  if not fa then return false end
  local fb = io.open(b, "rb")
  if not fb then fa:close() return false end
  local same = true
  while true do
    local x, y = fa:read(CHUNK), fb:read(CHUNK)
    if x ~= y then same = false break end
    if not x then break end
  end
  fa:close()
  fb:close()
  return same
end

local function copyFile(src, dst)
  local fin = io.open(src, "rb")
  if not fin then return false end
  local fout = io.open(dst, "wb")
  if not fout then fin:close() return false end
  local ok = true
  while true do
    local block = fin:read(CHUNK)
    if not block then break end
    if fout:write(block) == nil then ok = false break end
  end
  fin:close()
  if not fout:close() then ok = false end
  return ok and sameFile(src, dst)
end
G._copyFile = copyFile

local function parentOf(path)
  return path:match("^(.*)/[^/]+$")
end

local function foreignEntry(SaveData, dir, ours)
  local names = SaveData.listNative(dir) or {}
  for _, name in ipairs(names) do
    if name == MARKER then return nil end
  end
  for _, name in ipairs(names) do
    if not ours[name] and name ~= PROBE and name:sub(1, #CONFLICT_DIR) ~= CONFLICT_DIR then
      return name
    end
  end
  return nil
end

function G.move(target)
  local SaveData = SD()
  local saveDir = love.filesystem.getSaveDirectory()
  local from = SaveData.portableBaseDir() or saveDir
  local to = (target and target ~= "") and target or saveDir
  local function where(dir) return G.pretty(dir ~= saveDir and dir or "") end
  if from == to then
    return false, Strings("Your files are already in %s.", G.pretty(target))
  end
  if to ~= saveDir then
    local unsafe = G.unsafeTarget(to)
    if unsafe then return false, unsafe end
  end
  if to:sub(1, #from + 1) == from .. "/" or from:sub(1, #to + 1) == to .. "/" then
    return false, Strings("Pick a folder that isn't inside the current one, or the other way round.")
  end
  local toExisted = SaveData.statNative(to) ~= nil
  SaveData.mkdirNative(to)
  if not writable(to) then
    if not toExisted then os.remove(to) end
    return false, Strings("Can't write to %s.", G.pretty(target)) .. "\n\n" .. accessHelp()
  end
  if SaveData.listNative(from) == nil then
    if not toExisted then os.remove(to) end
    return false, Strings("Can't read the folder your files are in now.")
  end

  local files, srcDirs, claimed, ours = {}, {}, {}, {}
  local function taken(path)
    return claimed[path] or SaveData.statNative(path) ~= nil
  end
  local planError
  local function walk(rel)
    local abs = rel == "" and from or (from .. "/" .. rel)
    for _, name in ipairs(SaveData.listNative(abs) or {}) do
      if planError then return end
      local relPath = rel == "" and name or (rel .. "/" .. name)
      local skip = rel == "" and (name == "updates" or name:match("^picked_") ~= nil
        or name == SaveData.STORAGE_POINTER or name == MARKER
        or name:match("^%.write_probe") ~= nil or name == PROBE)
      if not skip then
        if rel == "" then ours[name] = true end
        local srcPath = from .. "/" .. relPath
        local st = SaveData.statNative(srcPath)
        if st and st.type == "directory" then
          walk(relPath)
          srcDirs[#srcDirs + 1] = srcPath
        elseif st then
          local dst = to .. "/" .. relPath
          local reuse = false
          if taken(dst) then
            if not claimed[dst] and sameFile(srcPath, dst) then
              reuse = true
            else
              dst = nil
              for n = 1, 99 do
                local dir = n == 1 and CONFLICT_DIR or (CONFLICT_DIR .. "_" .. n)
                local candidate = to .. "/" .. dir .. "/" .. relPath
                if not taken(candidate) then dst = candidate break end
              end
              if not dst then
                planError = Strings("There's no room for another copy of %s in %s.",
                  relPath, G.pretty(target))
                return
              end
            end
          end
          claimed[dst] = true
          files[#files + 1] = { src = srcPath, dst = dst, rel = relPath, reuse = reuse }
        end
      end
    end
  end
  walk("")
  if planError then
    if not toExisted then os.remove(to) end
    return false, planError .. " " .. Strings("Nothing was moved.")
  end
  if to ~= saveDir then
    local foreign = foreignEntry(SaveData, to, ours)
    if foreign then
      return false, Strings("%s already has other files in it, such as %s. Pick an empty folder or a new one.",
        G.pretty(target), foreign)
    end
  end

  local copied, madeDirs = {}, {}
  local function undo()
    for i = #copied, 1, -1 do os.remove(copied[i]) end
    table.sort(madeDirs, function(a, b) return #a > #b end)
    for _, dir in ipairs(madeDirs) do os.remove(dir) end
    if not toExisted then os.remove(to) end
  end
  local function makeParent(path)
    local parent = parentOf(path)
    local missing, p = {}, parent
    while p and p ~= to and #p > #to and not SaveData.statNative(p) do
      missing[#missing + 1] = p
      p = parentOf(p)
    end
    SaveData.mkdirNative(parent)
    for _, dir in ipairs(missing) do madeDirs[#madeDirs + 1] = dir end
  end

  for _, file in ipairs(files) do
    if not file.reuse then
      makeParent(file.dst)
      if G._copyFile(file.src, file.dst) then
        copied[#copied + 1] = file.dst
      else
        os.remove(file.dst)
        undo()
        log("move stopped, copy failed: " .. file.rel)
        return false, Strings("Couldn't copy %s to %s, so nothing was moved. Your files are still in %s.",
          file.rel, G.pretty(target), where(from))
      end
    end
  end

  local switched
  if to == saveDir then
    pcall(love.filesystem.remove, SaveData.STORAGE_POINTER)
    local okR, left = pcall(love.filesystem.read, SaveData.STORAGE_POINTER)
    switched = not (okR and type(left) == "string")
  else
    local marker = to .. "/" .. MARKER
    local hadMarker = SaveData.statNative(marker) ~= nil
    local f = hadMarker and true or io.open(marker, "wb")
    if f and f ~= true then f:close() end
    local okW, wrote = pcall(love.filesystem.write, SaveData.STORAGE_POINTER, to .. "\n")
    switched = f and okW and wrote and true or false
    if not switched and not hadMarker then os.remove(marker) end
  end
  if not switched then
    undo()
    return false, Strings("The storage setting couldn't be saved, so nothing was moved. Your files are still in %s.",
      where(from))
  end

  local leftover = 0
  for _, file in ipairs(files) do
    if not os.remove(file.src) then
      leftover = leftover + 1
      log("copied, but the original couldn't be deleted: " .. file.rel)
    end
  end
  for i = #srcDirs, 1, -1 do os.remove(srcDirs[i]) end
  log(("moved %d file(s) from %s to %s, %d original(s) left behind")
    :format(#files, from, to, leftover))
  return true, #files, leftover
end

function G.ensure()
  if not G.supported() then return false end
  local SaveData = SD()
  local folder = SaveData.androidFolder()
  if not folder or SaveData.isPortable() then return false end
  local canAsk = G.canRequestAccess()
  local msg = Strings("Your storage folder is set to %s, but Gen1 Recomp can't reach it right now.", G.pretty(folder))
    .. "\n\n" .. (canAsk
      and Strings("Press Allow access and turn storage access back on, then close and open the game again.")
      or (accessHelp() .. " " .. Strings("Then open the game again.")))
    .. "\n\n" .. Strings("Continue uses the app's own storage this time, so your saves may look missing until access is back.")
  local buttons = { Strings("Quit"), Strings("Continue"), escapebutton = 2 }
  if canAsk then buttons[3] = Strings("Allow access") end
  local ok, pressed = pcall(love.window.showMessageBox, Strings("Storage folder"), msg, buttons, "warning")
  if not ok then return false end
  if pressed == 1 then
    love.event.quit()
    return true
  end
  if pressed == 3 then
    local access = G.requestAccess()
    if access == "settings" then
      love.event.quit()
      return true
    elseif access == "granted" then
      messageBox(Strings("Storage folder"), Strings("Storage access is already on, but %s still can't be reached. Check that the folder and the storage it's on are still there.", G.pretty(folder)), "warning")
    end
  end
  return false
end

function G.settingsRows()
  local SaveData = SD()
  local current = SaveData.androidFolder() or ""
  local pending = current ~= "" and current or G.PRESETS[2]
  local askedDialog = false
  local moveRow

  local function refresh()
    if pending == current then
      moveRow.confirm = nil
      return
    end
    moveRow.confirm = {
      title = Strings("Move files?"),
      lines = {
        Strings("Move everything to %s?", G.pretty(pending)),
        Strings("Files already in that folder are kept. Anything with the same name goes into %s.", CONFLICT_DIR),
        Strings("This can take a little while. Gen1 Recomp closes when it's done."),
      },
    }
  end

  local function options()
    local list, found = {}, false
    for _, p in ipairs(G.PRESETS) do
      list[#list + 1] = p
      if p == pending then found = true end
    end
    if not found then list[#list + 1] = pending end
    return list
  end

  local rows = {}
  rows[#rows + 1] = {
    label = Strings("Storage Folder"),
    note = Strings("Where saves, options, mods and the ROM cache are kept. Pick a folder (or type one in Custom Folder), then press Move. Now: %s.", G.pretty(current)),
    value = function()
      if pending == current then return Strings("%s (now)", G.pretty(pending)) end
      return G.pretty(pending)
    end,
    step = function(dir)
      local list, idx = options(), 1
      for i, p in ipairs(list) do
        if p == pending then idx = i end
      end
      idx = ((idx - 1 + (dir or 1)) % #list) + 1
      pending = list[idx]
      refresh()
      return false
    end,
  }
  rows[#rows + 1] = {
    label = Strings("Custom Folder"),
    editText = { maxLen = 120 },
    value = function() return G.pretty(pending) end,
    setText = function(text)
      local p = G.normalize(text)
      local unsafe = p and p ~= "" and G.unsafeTarget(p)
      if not p then
        messageBox(Strings("Storage folder"), Strings("That isn't a folder this can use. Try something like Internal/Games/G1R."), "warning")
      elseif unsafe then
        messageBox(Strings("Storage folder"), unsafe, "warning")
      else
        pending = p
        refresh()
      end
      return false
    end,
  }
  moveRow = {
    label = Strings("Move Files"),
    actionLabel = Strings("Move"),
    danger = true,
    confirm = { title = Strings("Move files?"), lines = {} },
    action = function()
      if pending == current then
        messageBox(Strings("Storage folder"), Strings("Your files are already in %s.", G.pretty(current))
          .. "\n\n" .. Strings("Use the arrows on Storage Folder (or type one in Custom Folder) to pick where they should go, then press Move."), "info")
        return false
      end
      if pending ~= "" then
        local access = G.requestAccess()
        if access == "settings" then
          messageBox(Strings("Storage folder"), Strings("Turn on storage access for gen1recomp on the screen that just opened, then come back and press Move again."), "info")
          return false
        elseif access == "dialog" and not askedDialog then
          askedDialog = true
          return false
        end
      end
      local ok, done, moved, leftover = pcall(G.move, pending)
      if not ok then
        messageBox(Strings("Storage folder"), Strings("Something went wrong: %s", tostring(done)), "error")
      elseif not done then
        messageBox(Strings("Storage folder"), tostring(moved), "warning")
      else
        local msg = Strings("Moved %d file(s) to %s.", moved, G.pretty(pending))
        if leftover > 0 then
          msg = msg .. "\n" .. Strings("%d old file(s) couldn't be deleted from the previous folder. They're extra copies and safe to delete.", leftover)
        end
        msg = msg .. "\n\n" .. Strings("Gen1 Recomp will close now. Open it again to use the new folder.")
        messageBox(Strings("Storage folder"), msg, "info")
        love.event.quit()
      end
      return false
    end,
  }
  rows[#rows + 1] = moveRow
  refresh()
  return rows
end

return G
