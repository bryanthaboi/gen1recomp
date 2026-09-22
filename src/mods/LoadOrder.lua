local SaveData = require("src.core.SaveData")

local LoadOrder = {}

local function priorityOf(entry)
  local p = entry and (entry.priority or (entry.manifest and entry.manifest.priority))
  return tonumber(p) or 0
end

function LoadOrder.byPriority(entries)
  local list = {}
  for _, e in ipairs(entries or {}) do
    if type(e) == "table" and type(e.id) == "string" then list[#list + 1] = e end
  end
  table.sort(list, function(a, b)
    local pa, pb = priorityOf(a), priorityOf(b)
    if pa == pb then return a.id < b.id end
    return pa < pb
  end)
  local ids = {}
  for i, e in ipairs(list) do ids[i] = e.id end
  return ids
end

function LoadOrder.materialize(saved, entries)
  local listed = SaveData.modOrder({ modOrder = saved })
  local seen, prio = {}, {}
  for _, id in ipairs(listed) do seen[id] = true end
  for _, e in ipairs(entries or {}) do
    if type(e) == "table" and type(e.id) == "string" then prio[e.id] = priorityOf(e) end
  end
  local tail = {}
  for _, id in ipairs(LoadOrder.byPriority(entries)) do
    if not seen[id] then
      seen[id] = true
      tail[#tail + 1] = id
    end
  end
  local out, t = {}, 1
  for _, id in ipairs(listed) do
    local p = prio[id]
    if p then
      while tail[t] and prio[tail[t]] < p do
        out[#out + 1] = tail[t]
        t = t + 1
      end
    end
    out[#out + 1] = id
  end
  for i = t, #tail do out[#out + 1] = tail[i] end
  return out
end

function LoadOrder.rank(list)
  local rank = {}
  local clean = SaveData.modOrder({ modOrder = list })
  for i, id in ipairs(clean) do rank[id] = i end
  return rank, #clean + 1
end

function LoadOrder.move(list, id, delta)
  local out, at = {}, nil
  for i, v in ipairs(list or {}) do
    out[i] = v
    if v == id then at = i end
  end
  if not at or #out < 2 then return out, false end
  local to = at + (tonumber(delta) or 0)
  if to ~= to then return out, false end
  to = math.max(1, math.min(#out, to))
  if to == at then return out, false end
  table.remove(out, at)
  table.insert(out, to, id)
  return out, true
end

function LoadOrder.moveWithin(full, visible, id, delta)
  local shown = {}
  for _, v in ipairs(visible or full or {}) do shown[v] = true end
  local sub = {}
  for _, v in ipairs(full or {}) do
    if shown[v] then sub[#sub + 1] = v end
  end
  local moved, changed = LoadOrder.move(sub, id, delta)
  if not changed then
    local copy = {}
    for i, v in ipairs(full or {}) do copy[i] = v end
    return copy, false
  end
  local out, k = {}, 0
  for i, v in ipairs(full) do
    if shown[v] then
      k = k + 1
      out[i] = moved[k]
    else
      out[i] = v
    end
  end
  return out, true
end

function LoadOrder.position(list, id)
  for i, v in ipairs(list or {}) do
    if v == id then return i end
  end
  return nil
end

return LoadOrder
