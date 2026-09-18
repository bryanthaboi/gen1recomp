-- Multichoice list strings for Sevii scripts (pret gMultichoiceLists subset).
-- Filled for Island 1 / common FRLG lists; expand via ROM extract later.
-- Keyed by listId (script operand). Each entry: { labels = {...}, left?, top? }.

local Multichoice = {}

-- Common FRLG list ids used on Sevii / centers (approximate; extract overrides).
Multichoice.LISTS = {
  -- Generic YES/NO style already uses Choice.yesNo; keep lists for multichoice ops.
  [0] = { labels = { "YES", "NO" }, left = 22, top = 8 },
  [1] = { labels = { "SEE YA!", "INFO" }, left = 20, top = 6 },
  [2] = { labels = { "ONE ISLAND", "TWO ISLAND", "THREE ISLAND", "EXIT" }, left = 14, top = 4 },
  [3] = { labels = { "FOUR ISLAND", "FIVE ISLAND", "SIX ISLAND", "SEVEN ISLAND", "EXIT" }, left = 12, top = 3 },
  [4] = { labels = { "TRADE CENTER", "COLOSSEUM", "EVOLUTION", "EXIT" }, left = 14, top = 5 },
  [5] = { labels = { "JOIN ROOM", "INFO", "EXIT" }, left = 18, top = 6 },
  [6] = { labels = { "POKéMON JUMP", "DODRIO BERRY", "EXIT" }, left = 16, top = 6 },
  [7] = { labels = { "YES", "NO" }, left = 22, top = 8 },
  [8] = { labels = { "NORMAL", "DIRECT", "EXIT" }, left = 18, top = 6 },
  [9] = { labels = { "MAKE A GROUP", "ACCEPT INVITE", "EXIT" }, left = 14, top = 6 },
  -- Ferry / island travel (Sevii)
  [10] = { labels = { "VERMILION", "ONE ISLAND", "EXIT" }, left = 16, top = 6 },
  [11] = { labels = { "ONE ISLAND", "TWO ISLAND", "THREE ISLAND", "EXIT" }, left = 14, top = 4 },
  [12] = { labels = { "GO ON", "INFO", "EXIT" }, left = 18, top = 6 },
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

function Multichoice.tryLoadCache()
  local ok, data = pcall(require, "src.import.gba.multichoice_data_stub")
  if ok and type(data) == "table" then
    Multichoice.loadExtract(data)
    return true
  end
  -- CacheFS fallback for offline / test loads.
  local Extract = require("src.import.gba.extract_island1")
  local root = (Extract.CACHE_ROOT or "data/generated/gba") .. "/scripts/multichoice.lua"
  local chunk = loadfile(root)
  if chunk then
    local d = chunk()
    if type(d) == "table" then Multichoice.loadExtract(d) return true end
  end
  return false
end

function Multichoice.resolve(listId, countHint)
  Multichoice.tryLoadCache()
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
