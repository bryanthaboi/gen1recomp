-- src/script_menu.c:505
-- Keyed by listId (script operand). Each entry: { labels = {...}, left?, top? }.

local Strings = require("src.core.Strings")
local Multichoice = {}

Multichoice.LISTS = {}
Multichoice.CACHE_REL = "data/generated/gba/scripts/multichoice.lua"

Multichoice.COUNTS = {
  [0]=2, [1]=5, [2]=4, [3]=2, [4]=2, [5]=2, [6]=3, [7]=3,
  [8]=3, [9]=4, [10]=1, [11]=1, [12]=1, [13]=2, [14]=6, [15]=6,
  [16]=3, [17]=5, [18]=3, [19]=3, [20]=3, [21]=2, [22]=2, [23]=2,
  [24]=3, [25]=3, [26]=4, [27]=3, [28]=2, [29]=2, [30]=6, [31]=6,
  [32]=2, [33]=2, [34]=3, [35]=2, [36]=3, [37]=3, [38]=4, [39]=3,
  [40]=3, [41]=6, [42]=4, [43]=4, [44]=3, [45]=3, [46]=3, [47]=4,
  [48]=3, [49]=3, [50]=3, [51]=2, [52]=5, [53]=4, [54]=3, [55]=3,
  [56]=4, [57]=4, [58]=4, [59]=4, [60]=4, [61]=2, [62]=3, [63]=3,
  [64]=5,
}

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
  local readers = { read_from_dataset, read_from_cachefs, read_from_love, read_from_disk }
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

function Multichoice.resolve(listId, countHint)
  if not next(Multichoice.LISTS) then
    Multichoice.tryLoadCache()
  end
  local id = tonumber(listId) or 0
  local entry = Multichoice.LISTS[id]
  if entry and entry.labels and #entry.labels > 0 then
    return entry.labels, { left = entry.left, top = entry.top }
  end
  local n = Multichoice.COUNTS[id] or tonumber(countHint) or 3
  local labels = {}
  for i = 1, math.max(1, n) do
    labels[i] = Strings("OPTION %s", (i - 1))
  end
  return labels, { left = 20, top = 5 }
end

return Multichoice
