local Catalog = {}

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do
    table.insert(keys, k)
  end
  table.sort(keys)
  return keys
end

-- Gen 2's generated tables carry provenance scalars (generation, source)
-- beside the id-keyed records, so a wheel built from every key would offer
-- them as pickable entries.  #1466
local function sortedRecordKeys(t)
  local keys = {}
  for k, v in pairs(t or {}) do
    if type(v) == "table" then table.insert(keys, k) end
  end
  table.sort(keys)
  return keys
end

function Catalog.build(data)
  return {
    species = sortedRecordKeys(data.pokemon),
    items = sortedRecordKeys(data.items),
    moves = sortedRecordKeys(data.moves),
  }
end

-- Directory listing / file reading go through love.filesystem when it is
-- available, and only fall back to shelling out.  That is what makes the
-- Events tab work in a packaged build: data/scripts is inside the .love
-- archive, data/generated is mounted from the save directory, and mods live
-- under the save directory too -- none of which io.open can reach by relative
-- path.  The io.popen path stays for headless runs (tests/, plain lua) where
-- love.filesystem does not exist.
-- nil means "love.filesystem cannot see this directory", which is the signal
-- to fall through to the shell -- headless runs mount a stub filesystem that
-- knows nothing about the checkout, but their io.* can still read it.
local function loveListLua(dir)
  local fs = love and love.filesystem
  if not (fs and fs.getDirectoryItems and fs.getInfo) then return nil end
  if not fs.getInfo(dir) then return nil end
  local out = {}
  for _, name in ipairs(fs.getDirectoryItems(dir)) do
    if name:sub(-4) == ".lua" then out[#out + 1] = dir .. "/" .. name end
  end
  return out
end

local function shellListLua(dir)
  local out = {}
  if not (io and io.popen) then return out end
  if package.config:sub(1, 1) == "\\" then
    -- cmd has no ls; dir /b prints bare names, so re-attach the directory
    local ok, p = pcall(io.popen, string.format('dir /b "%s\\*.lua" 2>nul', dir))
    if ok and p then
      for line in p:lines() do
        if line ~= "" then table.insert(out, dir .. "/" .. line) end
      end
      p:close()
    end
    return out
  end
  local ok, p = pcall(io.popen, string.format('ls "%s"/*.lua 2>/dev/null', dir))
  if ok and p then
    for line in p:lines() do
      table.insert(out, line)
    end
    p:close()
  end
  return out
end

local function readText(path)
  local fs = love and love.filesystem
  if fs and fs.read and fs.getInfo and fs.getInfo(path) then
    local ok, body = pcall(fs.read, path)
    if ok and body then return body end
  end
  local f = io.open(path, "r")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  return body
end

-- extraDirs: loaded mods' roots, so MOD_-prefixed flags defined in mod
-- scripts show up beside the vanilla EVENT_ ones
function Catalog.scrapeEvents(scriptDir, headerPath, listFiles, extraDirs)
  listFiles = listFiles or function(dir)
    return loveListLua(dir) or shellListLua(dir) or {}
  end

  local found = {}
  local function eat(text)
    for name in text:gmatch("EVENT_[A-Z0-9_]+") do
      found[name] = true
    end
    for name in text:gmatch("MOD_[A-Z0-9_]+") do
      found[name] = true
    end
  end

  local dirs = {}
  if scriptDir then dirs[#dirs + 1] = scriptDir end
  for _, dir in ipairs(extraDirs or {}) do
    dirs[#dirs + 1] = dir
  end
  for _, dir in ipairs(dirs) do
    local files = listFiles(dir) or {}
    for _, path in ipairs(files) do
      local body = readText(path)
      if body then eat(body) end
    end
  end

  if headerPath then
    local body = readText(headerPath)
    if body then eat(body) end
  end

  return sortedKeys(found)
end

function Catalog.goldEventList(extraDirs)
  local names = {}
  local ok, flags = pcall(require, "src.core.gen2.FlagNames")
  if ok and flags and flags.events then
    for name in pairs(flags.events) do
      names[#names + 1] = name
    end
  end
  table.sort(names)
  local modFlags = Catalog.scrapeEvents(nil, nil, nil, extraDirs)
  local seen = {}
  for _, name in ipairs(names) do seen[name] = true end
  for _, name in ipairs(modFlags) do
    if not seen[name] then
      names[#names + 1] = name
      seen[name] = true
    end
  end
  return names
end

return Catalog
