-- Storage Folder (Android).
--
-- Android starts out in the app's own storage, as before.  The launcher's Settings > Launcher Options gain three rows:
--   Storage Folder  pick App storage or a preset folder (arrows)
--   Custom Folder   type any folder instead ("Internal/..." or a full path)
--   Move Files      move everything to the picked folder, then close
-- The choice is kept in g1r_storage_folder.txt in the app's own storage
-- (SaveData.androidFolder), and the folder works through Recomp's portable
-- mode.  Folders outside the app need "All files access".

local G = {}

local INTERNAL = "/storage/emulated/0"
G.PRESETS = {
  "",
  INTERNAL .. "/G1R",
  INTERNAL .. "/Documents/G1R",
  INTERNAL .. "/Download/G1R",
}
local CONFLICT_DIR = "_from_previous_location"
local CHUNK = 1024 * 1024
local ACCESS_HELP = "Give gen1recomp access to your storage:\n"
  .. "Android 10 and older: Settings > Apps > gen1recomp > Permissions > Storage > Allow.\n"
  .. "Android 11 and newer: Settings > Apps > gen1recomp > All files access "
  .. "(or search Settings for \"all files\") > Allow."

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

function G.supported()
  return SD().isAndroid()
end

-- "" / nil = the app's own storage
function G.pretty(path)
  if not path or path == "" then return "App storage" end
  if path == INTERNAL then return "Internal storage" end
  local rest = path:match("^/storage/emulated/0/(.+)$")
  if rest then return "Internal/" .. rest end
  return path
end

-- What the player typed -> a full path, "" for app storage, nil if unusable.
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

local function writable(dir)
  local path = dir .. "/.g1r_probe.tmp"
  local f = io.open(path, "wb")
  if not f then return false end
  local ok = f:write("ok") ~= nil
  f:close()
  os.remove(path)
  return ok
end

-- True when both files hold the same bytes.  Read in chunks so a large ROM
-- cache file is never held in memory twice.
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

-- Copy src to dst, then read both back: true only if the copy is verified.
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
-- The copy step G.move uses; tests swap it to simulate a failed copy.
G._copyFile = copyFile

local function parentOf(path)
  return path:match("^(.*)/[^/]+$")
end

-- Move everything from where the files live now to `target` ("" = the app's
-- own storage), in an order that never leaves saves split between folders:
--   1. copy every file and verify each copy against its original
--   2. only then switch the storage setting to the new folder
--   3. only then delete the originals
-- If any copy or the switch fails, the copies made so far are removed again,
-- the setting is left alone, and every original is still where it was.
-- A file already in the new folder is never overwritten: ours goes into
-- _from_previous_location instead, unless it holds the same bytes (left
-- there by an earlier attempt), in which case it is reused.
-- Returns true, moved, leftover  or  false, message.  `leftover` counts
-- originals that were copied but couldn't be deleted afterwards.
function G.move(target)
  local SaveData = SD()
  local saveDir = love.filesystem.getSaveDirectory()
  local from = SaveData.portableBaseDir() or saveDir
  local to = (target and target ~= "") and target or saveDir
  local function where(dir) return G.pretty(dir ~= saveDir and dir or "") end
  if from == to then
    return false, "Your files are already in " .. G.pretty(target) .. "."
  end
  if to:sub(1, #from + 1) == from .. "/" or from:sub(1, #to + 1) == to .. "/" then
    return false, "Pick a folder that isn't inside the current one, or the other way round."
  end
  local toExisted = SaveData.statNative(to) ~= nil
  SaveData.mkdirNative(to)
  if not writable(to) then
    if not toExisted then os.remove(to) end
    return false, "Can't write to " .. G.pretty(target) .. ".\n\n" .. ACCESS_HELP
  end
  if SaveData.listNative(from) == nil then
    if not toExisted then os.remove(to) end
    return false, "Can't read the folder your files are in now."
  end

  -- What to move, and where each copy goes.  `claimed` keeps two files from
  -- being planned onto the same destination.
  local files, srcDirs, claimed = {}, {}, {}
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
        or name == SaveData.STORAGE_POINTER or name == "portable.txt"
        or name:match("^%.write_probe") ~= nil or name == ".g1r_probe.tmp")
      if not skip then
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
                planError = "There's no room for another copy of " .. relPath
                  .. " in " .. G.pretty(target) .. "."
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
    return false, planError .. " Nothing was moved."
  end

  -- Undo a failed move: remove the copies and the folders made for them.
  local copied, madeDirs = {}, {}
  local function undo()
    for i = #copied, 1, -1 do os.remove(copied[i]) end
    table.sort(madeDirs, function(a, b) return #a > #b end) -- deepest first
    for _, dir in ipairs(madeDirs) do os.remove(dir) end -- only empty ones go
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

  -- 1. Copy and verify.  The originals are not touched.
  for _, file in ipairs(files) do
    if not file.reuse then
      makeParent(file.dst)
      if G._copyFile(file.src, file.dst) then
        copied[#copied + 1] = file.dst
      else
        os.remove(file.dst)
        undo()
        log("move stopped, copy failed: " .. file.rel)
        return false, "Couldn't copy " .. file.rel .. " to " .. G.pretty(target)
          .. ", so nothing was moved. Your files are still in " .. where(from) .. "."
      end
    end
  end

  -- 2. Switch the storage setting.  Until this succeeds the game still uses
  -- the old folder, which still holds everything.
  local switched
  if to == saveDir then
    pcall(love.filesystem.remove, SaveData.STORAGE_POINTER)
    local okR, left = pcall(love.filesystem.read, SaveData.STORAGE_POINTER)
    switched = not (okR and type(left) == "string")
  else
    local marker = to .. "/portable.txt"
    local hadMarker = SaveData.statNative(marker) ~= nil
    local f = hadMarker and true or io.open(marker, "wb")
    if f and f ~= true then f:close() end
    local okW, wrote = pcall(love.filesystem.write, SaveData.STORAGE_POINTER, to .. "\n")
    switched = f and okW and wrote and true or false
    if not switched and not hadMarker then os.remove(marker) end
  end
  if not switched then
    undo()
    return false, "The storage setting couldn't be saved, so nothing was moved. "
      .. "Your files are still in " .. where(from) .. "."
  end

  -- 3. Everything is safely in the new folder and in use: delete the originals.
  local leftover = 0
  for _, file in ipairs(files) do
    if not os.remove(file.src) then
      leftover = leftover + 1
      log("copied, but the original couldn't be deleted: " .. file.rel)
    end
  end
  for i = #srcDirs, 1, -1 do os.remove(srcDirs[i]) end -- only empty ones go
  log(("moved %d file(s) from %s to %s, %d original(s) left behind")
    :format(#files, from, to, leftover))
  return true, #files, leftover
end

-- Boot check: a folder is chosen but can't be reached (access turned off).
-- Returns true when the player chose Quit.
function G.ensure()
  if not G.supported() then return false end
  local SaveData = SD()
  local folder = SaveData.androidFolder()
  if not folder or SaveData.isPortable() then return false end
  local msg = "Your storage folder is set to " .. G.pretty(folder)
    .. ", but Gen1 Recomp can't reach it right now.\n\n" .. ACCESS_HELP
    .. " Then open the game again.\n\nContinue uses the app's own storage this time, "
    .. "so your saves may look missing until access is back."
  local ok, pressed = pcall(love.window.showMessageBox, "Storage folder", msg,
    { "Quit", "Continue", escapebutton = 2 }, "warning")
  if ok and pressed == 1 then
    love.event.quit()
    return true
  end
  return false
end

-- Rows for the launcher's Launcher Options section.
function G.settingsRows()
  local SaveData = SD()
  local current = SaveData.androidFolder() or ""
  -- Start on the first folder that isn't where the files are now, so Move
  -- does something useful even before the arrows are touched.
  local pending = current ~= "" and current or G.PRESETS[2]
  local moveRow

  local function refresh()
    if pending == current then
      moveRow.confirm = nil -- nothing to move: Move explains instead
      return
    end
    moveRow.confirm = { title = "Move files?" }
    moveRow.confirm.lines = {
      "Move everything to " .. G.pretty(pending) .. "?",
      "Files already in that folder are kept. Anything with the same name goes into "
        .. CONFLICT_DIR .. ".",
      "This can take a little while. Gen1 Recomp closes when it's done.",
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
    label = "Storage Folder",
    note = "Where saves, options, mods and the ROM cache are kept. Pick a folder "
      .. "(or type one in Custom Folder), then press Move. Now: " .. G.pretty(current) .. ".",
    value = function()
      return G.pretty(pending) .. (pending == current and " (now)" or "")
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
    label = "Custom Folder",
    editText = { maxLen = 120 },
    value = function() return G.pretty(pending) end,
    setText = function(text)
      local p = G.normalize(text)
      if p then
        pending = p
        refresh()
      else
        messageBox("Storage folder", "That isn't a folder this can use. Try something like "
          .. "Internal/Games/G1R.", "warning")
      end
      return false
    end,
  }
  moveRow = {
    label = "Move Files",
    actionLabel = "Move",
    danger = true,
    confirm = { title = "Move files?", lines = {} },
    action = function()
      if pending == current then
        messageBox("Storage folder", "Your files are already in " .. G.pretty(current)
          .. ".\n\nUse the arrows on Storage Folder (or type one in Custom Folder) to "
          .. "pick where they should go, then press Move.", "info")
        return false
      end
      local ok, done, moved, leftover = pcall(G.move, pending)
      if not ok then
        messageBox("Storage folder", "Something went wrong: " .. tostring(done), "error")
      elseif not done then
        messageBox("Storage folder", tostring(moved), "warning")
      else
        local msg = ("Moved %d file(s) to %s."):format(moved, G.pretty(pending))
        if leftover > 0 then
          msg = msg .. ("\n%d old file(s) couldn't be deleted from the previous folder. "
            .. "They're extra copies and safe to delete."):format(leftover)
        end
        msg = msg .. "\n\nGen1 Recomp will close now. Open it again to use the new folder."
        messageBox("Storage folder", msg, "info")
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
