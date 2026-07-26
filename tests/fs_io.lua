-- io-backed filesystem for the headless Loader (21-testing-and-ci
-- "headless loader seam").  Loader.new takes opts.fs; under plain luajit
-- there is no love.filesystem, so this adapter reads a real mod directory
-- off disk and lets discovery/topo-sort/merge run with no love at all.
--
-- Paths handed to the loader are repo-relative ("mods/example_mew_starter"),
-- the same strings love.filesystem would see, so a mod loaded through here
-- and one loaded in the game take identical code paths.

local FsIo = {}

-- shell-quote for the popen/os.execute probes; single quotes survive
-- spaces and the ' inside a name closes-escapes-reopens
local function quote(path)
  return "'" .. tostring(path):gsub("'", "'\\''") .. "'"
end

-- The suites also run on Windows checkouts, where cmd has no ls/find/test.
-- These probes pick the spelling the host shell understands; anything that
-- listed a directory through a bare Unix command silently returned nothing
-- there, and a tier built on an empty listing passes vacuously.
FsIo.isWindows = package.config:sub(1, 1) == "\\"

local function shellLines(cmd)
  local lines = {}
  local pipe = io.popen(cmd)
  if not pipe then return lines end
  for line in pipe:lines() do
    if line ~= "" then lines[#lines + 1] = line end
  end
  pipe:close()
  return lines
end

-- names directly inside path (files and directories mixed, like ls -1)
function FsIo.listDir(path)
  local cmd
  if FsIo.isWindows then
    cmd = 'dir /b "' .. tostring(path) .. '" 2>nul'
  else
    cmd = "ls -1 " .. quote(path) .. " 2>/dev/null"
  end
  local items = shellLines(cmd)
  table.sort(items)
  return items
end

-- every *.lua under dir, recursively, as forward-slash paths
function FsIo.luaFilesUnder(dir)
  local cmd
  if FsIo.isWindows then
    cmd = 'dir /b /s "' .. tostring(dir) .. '\\*.lua" 2>nul'
  else
    -- -L follows symlinks: a checkout that symlinks src/ (worktrees, the
    -- ROM-free CI probe) would otherwise scan nothing and hand every gate
    -- an empty catalog to pass vacuously against
    cmd = "find -L " .. quote(dir) .. " -name '*.lua' -type f 2>/dev/null"
  end
  local files = {}
  for _, line in ipairs(shellLines(cmd)) do
    files[#files + 1] = (line:gsub("\\", "/"))
  end
  table.sort(files)
  return files
end

-- full paths matching the shell's "prefix"* glob (e.g. save.lua.bak-*)
function FsIo.globPrefix(prefix)
  local dir, base = tostring(prefix):match("^(.*[/\\])([^/\\]*)$")
  if not dir then dir, base = "", tostring(prefix) end
  if dir == "" then dir = "." end
  local matches = {}
  for _, name in ipairs(FsIo.listDir(dir)) do
    if name:sub(1, #base) == base then
      matches[#matches + 1] = dir .. name
    end
  end
  return matches
end

-- existence probe that never shells out on Windows: directories do not
-- open() there at all, and rename-self succeeds for anything that exists
function FsIo.isDir(path)
  local handle = io.open(path, "rb")
  if handle then
    local probe = handle:read(1)
    handle:close()
    if probe ~= nil then return false end
    if FsIo.isWindows then return false end -- opened but empty: a file
  elseif FsIo.isWindows then
    return os.rename(path, path) == true
  end
  local ok = os.execute("test -d " .. quote(path))
  return ok == true or ok == 0
end

function FsIo.new(rootDir)
  local base = rootDir or "."

  local function abs(path)
    if path == nil or path == "" then return base end
    return base .. "/" .. path
  end

  local fs = {}

  function fs.read(path)
    local handle = io.open(abs(path), "rb")
    if not handle then return nil, "nofile" end
    local body = handle:read("*a")
    handle:close()
    return body
  end

  function fs.write(path, body)
    local handle = io.open(abs(path), "wb")
    if not handle then return false end
    handle:write(body)
    handle:close()
    return true
  end

  -- files answer without a shell; only the directory case pays for a probe
  function fs.getInfo(path)
    local handle = io.open(abs(path), "rb")
    if handle then
      local probe = handle:read(1)
      handle:close()
      -- a directory opens on some libc builds but reads nothing
      if probe ~= nil then return { type = "file" } end
    end
    if FsIo.isDir(abs(path)) then return { type = "directory" } end
    if handle then return { type = "file" } end
    return nil
  end

  function fs.load(path)
    return loadfile(abs(path))
  end

  function fs.getDirectoryItems(path)
    return FsIo.listDir(abs(path))
  end

  fs.root = base
  return fs
end

return FsIo
