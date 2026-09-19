-- Multichoice list strings for Sevii scripts (pret gMultichoiceLists subset).
-- Filled for Island 1 / common FRLG lists; expand via ROM extract later.
-- Keyed by listId (script operand). Each entry: { labels = {...}, left?, top? }.

local Multichoice = {}

Multichoice.LISTS = {}

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

function Multichoice.tryLoadCache()
  local ok, data = pcall(require, "src.import.gba.multichoice_data_stub")
  if ok and type(data) == "table" then
    Multichoice.loadExtract(data)
    return true
  end
  -- CacheFS fallback for offline / test loads.
  local okE, Extract = pcall(require, "src.import.gba.extract_island1")
  local root = ((okE and Extract and Extract.CACHE_ROOT) or "data/generated/gba") .. "/scripts/multichoice.lua"
  local chunk = loadfile(root)
  if chunk then
    local d = chunk()
    if type(d) == "table" then Multichoice.loadExtract(d) return true end
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
  -- Fallback synthetic labels (legacy).
  local n = tonumber(countHint) or 3
  local labels = {}
  for i = 1, math.max(1, n) do
    labels[i] = "OPTION " .. (i - 1)
  end
  return labels, { left = 20, top = 5 }
end

return Multichoice
