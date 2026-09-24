local RomText = require("src.core.game3.rom_text")

local Status = {}

-- pokefirered/src/wireless_communication_status_screen.c:27
Status.GROUPTYPE = { TRADE = 1, BATTLE = 2, UNION = 3, TOTAL = 4 }
Status.NUM_GROUPTYPES = 4

local function union()
  return require("src.core.game3.link.union_room")
end

local function link()
  return require("src.core.game3.link")
end

-- pokefirered/src/wireless_communication_status_screen.c:140 sActivityGroupInfo
function Status.table()
  local A = union().ACTIVITY
  local U = union().IN_UNION_ROOM
  local G = Status.GROUPTYPE
  return {
    { A.BATTLE_SINGLE, G.BATTLE, 2 },
    { A.BATTLE_DOUBLE, G.BATTLE, 2 },
    { A.BATTLE_MULTI, G.BATTLE, 4 },
    { A.TRADE, G.TRADE, 2 },
    { A.WONDER_CARD, G.TOTAL, 2 },
    { A.WONDER_NEWS, G.TOTAL, 2 },
    { A.POKEMON_JUMP, nil, 0 },
    { A.BERRY_CRUSH, nil, 0 },
    { A.BERRY_PICK, nil, 0 },
    { A.SEARCH, nil, 0 },
    { A.SPIN_TRADE, G.TRADE, 0 },
    { A.ITEM_TRADE, nil, 0 },
    { A.RECORD_CORNER, nil, 0 },
    { A.NONE + U, G.UNION, 1 },
    { A.BATTLE_SINGLE + U, G.UNION, 2 },
    { A.TRADE + U, G.UNION, 2 },
    { A.CHAT + U, G.UNION, 0 },
    { A.CARD + U, G.UNION, 2 },
    { A.PLYRTALK + U, G.UNION, 1 },
    { A.NPCTALK + U, G.UNION, 2 },
    { A.ACCEPT + U, G.UNION, 1 },
    { A.DECLINE + U, G.UNION, 1 },
  }
end

-- pokefirered/src/wireless_communication_status_screen.c:388 CountPlayersInGroupAndGetActivity
function Status.countInto(counts, entry)
  local activity = tonumber(entry and entry.activity)
  if activity == nil then return counts end
  local members = math.max(1, math.floor(tonumber(entry.members) or 1))
  for _, row in ipairs(Status.table()) do
    if row[1] == activity then
      local group = row[2]
      if group then
        local players = row[3]
        if players == 0 then players = members end
        counts[group] = (counts[group] or 0) + players
      end
      break
    end
  end
  return counts
end

-- pokefirered/src/wireless_communication_status_screen.c:472 UpdateCommunicationCounts
function Status.counts(entries)
  local counts = { 0, 0, 0, 0 }
  for _, entry in ipairs(entries or {}) do
    Status.countInto(counts, entry)
  end
  local G = Status.GROUPTYPE
  -- pokefirered/src/wireless_communication_status_screen.c:505 the retail total drops GROUPTYPE_TOTAL
  counts[G.TOTAL] = counts[G.TRADE] + counts[G.BATTLE] + counts[G.UNION]
  return counts
end

-- pokefirered/src/union_room.c:2674 UR_STATE_INIT_LINK
function Status.entries()
  local Union = union()
  local out = {}
  local A = Union.ACTIVITY
  local U = Union.IN_UNION_ROOM
  if Union.isActive() then
    local activity = A.NONE + U
    local raw = tonumber(Union.activity)
    if raw and raw >= U then activity = raw end
    out[#out + 1] = { activity = activity, members = 1 }
    for _, row in ipairs(Union.list()) do
      out[#out + 1] = { activity = tonumber(row.activity) or (A.NONE + U), members = 1 }
    end
    return out
  end
  local L = link()
  local live = L.link
  if not (live and live.isOpen and live:isOpen()) then return out end
  local LB = package.loaded["src.core.game3.link.battle"]
  local LT = package.loaded["src.core.game3.link.trade"]
  if LB and LB.isActive and LB.isActive() then
    local activity = A.BATTLE_SINGLE
    if LB.mode == L.USING.DOUBLE_BATTLE then
      activity = A.BATTLE_DOUBLE
    elseif LB.mode == L.USING.MULTI_BATTLE then
      activity = A.BATTLE_MULTI
    end
    out[#out + 1] = { activity = activity, members = 2 }
  elseif LT and LT.isActive and LT.isActive() then
    out[#out + 1] = { activity = A.TRADE, members = 2 }
  end
  return out
end

-- pokefirered/src/wireless_communication_status_screen.c:127 sHeaderTexts
Status.HEADER = RomText.lazy({
  [0] = "sHeaderTexts[0]",
  "sHeaderTexts[1]",
  "sHeaderTexts[2]",
  "sHeaderTexts[3]",
  "sHeaderTexts[4]",
})

-- pokefirered/src/wireless_communication_status_screen.c:505
function Status.fromPlaza(pc)
  local G = Status.GROUPTYPE
  local counts = { 0, 0, 0, 0 }
  if type(pc) == "table" then
    counts[G.TRADE] = math.max(0, math.floor(tonumber(pc.trade) or 0))
    counts[G.BATTLE] = math.max(0, math.floor(tonumber(pc.battle) or 0))
    counts[G.UNION] = math.max(0, math.floor(tonumber(pc.union) or 0))
    counts[G.TOTAL] = math.max(0, math.floor(tonumber(pc.total)
      or (counts[G.TRADE] + counts[G.BATTLE] + counts[G.UNION])))
  end
  return counts
end

function Status.relayCounts()
  local L = link()
  if not L.adapterConnected() then return nil end
  return Status.fromPlaza(L.clientCall("plazaCounts"))
end

function Status.rows()
  local counts = Status.relayCounts() or Status.counts(Status.entries())
  local out = {}
  for i = 1, Status.NUM_GROUPTYPES do
    out[i] = { label = Status.HEADER[i], count = counts[i] or 0, total = i == Status.GROUPTYPE.TOTAL }
  end
  return out
end

return Status
