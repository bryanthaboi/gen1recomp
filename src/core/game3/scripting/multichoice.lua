-- src/script_menu.c:505
-- Keyed by listId (script operand). Each entry: { labels = {...}, left?, top? }.

local Multichoice = {}

Multichoice.LISTS = {}
Multichoice.OVERRIDES = {}
Multichoice.CACHE_REL = "data/generated/gba/scripts/multichoice.lua"

--- Override/merge from extract cache if present.
function Multichoice.loadExtract(tbl)
  if type(tbl) ~= "table" then return end
  for id, entry in pairs(tbl) do
    local n = tonumber(id) or id
    if type(entry) == "table" and entry.labels then
      Multichoice.LISTS[n] = entry
    elseif type(entry) == "table" and entry[1] then
      Multichoice.LISTS[n] = { labels = entry }
    end
  end
end

local function parse_lists(src)
  if type(src) ~= "string" or #src == 0 then return nil end
  local chunk = (load or loadstring)(src, "@" .. Multichoice.CACHE_REL, "t", {})
  if not chunk then return nil end
  local ok, data = pcall(chunk)
  if ok and type(data) == "table" then return data end
  return nil
end

local function read_from_dataset()
  local okD, Dataset = pcall(require, "src.core.game3.dataset")
  if not (okD and Dataset and Dataset.cache) then return nil end
  local okC, cache = pcall(Dataset.cache)
  if not (okC and cache and cache.read) then return nil end
  local okR, src = pcall(cache.read, cache, Multichoice.CACHE_REL)
  if okR then return src end
  return nil
end

local function read_from_cachefs()
  local ok, CacheFs = pcall(require, "src.import.CacheFs")
  if not (ok and CacheFs and CacheFs.readActive) then return nil end
  local okR, src = pcall(CacheFs.readActive, Multichoice.CACHE_REL)
  if okR then return src end
  return nil
end

local function read_from_love()
  if not (love and love.filesystem and love.filesystem.read) then return nil end
  local ok, src = pcall(love.filesystem.read, Multichoice.CACHE_REL)
  if ok then return src end
  return nil
end

local function read_from_disk()
  local okE, Extract = pcall(require, "src.import.gba.extract_island1")
  local root = (okE and Extract and Extract.CACHE_ROOT) or "data/generated/gba"
  local f = io.open(root .. "/scripts/multichoice.lua", "rb")
  if not f then return nil end
  local src = f:read("*a")
  f:close()
  return src
end

function Multichoice.tryLoadCache()
  local okE, Extract = pcall(require, "src.import.gba.extract_island1")
  local customRoot = okE and Extract and Extract.CACHE_ROOT and Extract.CACHE_ROOT ~= "data/generated/gba"
  local readers
  if customRoot then
    readers = { read_from_disk }
  else
    readers = { read_from_disk, read_from_dataset, read_from_cachefs, read_from_love }
  end
  for _, reader in ipairs(readers) do
    local data = parse_lists(reader())
    if data then
      Multichoice.loadExtract(data)
      return true
    end
  end
  return false
end

-- Preload cache immediately
Multichoice.tryLoadCache()

function Multichoice.resolve(listId)
  if not next(Multichoice.LISTS) then
    Multichoice.tryLoadCache()
  end
  local id = tonumber(listId) or 0
  local entry = Multichoice.LISTS[id]
  if entry and entry.labels and #entry.labels > 0 then
    return entry.labels, { left = entry.left, top = entry.top }
  end
  error(("multichoice list %d is not in the cache"):format(id), 2)
end

return Multichoice
