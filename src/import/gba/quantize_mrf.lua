-- Multi-label Potts MRF via α-expansion + Dinic max-flow (pure Lua).
-- Assigns Gen2 codebook indices to 8×8 quads with edge-gated spatial smoothness.
-- Mid reuse: majority vote across map placements (known limitation).

local QuantizeLab = require("src.import.gba.quantize_lab")

local QuantizeMrf = {}

-- Locked after synthetic λ/EDGE_DE sweep (coupled knobs).
QuantizeMrf.LAMBDA = 40.0
QuantizeMrf.EDGE_DE = 18.0
QuantizeMrf.EXPANSIONS = 3
QuantizeMrf.ENABLED = false

----------------------------------------------------------------------
-- Dinic max-flow
----------------------------------------------------------------------

local function dinic_new()
  return { head = {}, to = {}, rev = {}, cap = {}, next = {}, n = 0, e = 0 }
end

local function dinic_add_node(g)
  g.n = g.n + 1
  g.head[g.n] = 0
  return g.n
end

local function dinic_link(g, a, b, cap)
  g.e = g.e + 1
  local ei = g.e
  g.to[ei] = b
  g.cap[ei] = cap
  g.next[ei] = g.head[a] or 0
  g.head[a] = ei
  return ei
end

local function dinic_add_edge_pair(g, u, v, cap_uv, cap_vu)
  local e1 = dinic_link(g, u, v, cap_uv)
  local e2 = dinic_link(g, v, u, cap_vu)
  g.rev[e1] = e2
  g.rev[e2] = e1
end

local function dinic_add_tweights(g, i, cap_source, cap_sink, src, snk)
  if cap_source and cap_source > 0 then
    dinic_add_edge_pair(g, src, i, cap_source, 0)
  end
  if cap_sink and cap_sink > 0 then
    dinic_add_edge_pair(g, i, snk, cap_sink, 0)
  end
end

local function dinic_maxflow(g, src, snk)
  local level, iter = {}, {}

  local function bfs()
    for i = 1, g.n do level[i] = -1 end
    local q, qh = { src }, 1
    level[src] = 0
    while qh <= #q do
      local v = q[qh]
      qh = qh + 1
      local e = g.head[v]
      while e ~= 0 do
        local w = g.to[e]
        if g.cap[e] > 0 and level[w] < 0 then
          level[w] = level[v] + 1
          q[#q + 1] = w
        end
        e = g.next[e]
      end
    end
    return level[snk] >= 0
  end

  local function dfs(v, f)
    if v == snk then return f end
    local e = iter[v]
    while e ~= 0 do
      local w = g.to[e]
      if g.cap[e] > 0 and level[v] < level[w] then
        local d = dfs(w, math.min(f, g.cap[e]))
        if d > 0 then
          g.cap[e] = g.cap[e] - d
          g.cap[g.rev[e]] = g.cap[g.rev[e]] + d
          return d
        end
      end
      e = g.next[e]
      iter[v] = e
    end
    return 0
  end

  local flow = 0
  while bfs() do
    for i = 1, g.n do iter[i] = g.head[i] or 0 end
    while true do
      local f = dfs(src, 1e100)
      if f <= 0 then break end
      flow = flow + f
    end
  end
  return flow
end

local function dinic_in_source_set(g, src, node)
  local seen, q, qh = {}, { src }, 1
  seen[src] = true
  while qh <= #q do
    local v = q[qh]
    qh = qh + 1
    if v == node then return true end
    local e = g.head[v]
    while e ~= 0 do
      local w = g.to[e]
      if g.cap[e] > 0 and not seen[w] then
        seen[w] = true
        q[#q + 1] = w
      end
      e = g.next[e]
    end
  end
  return false
end

----------------------------------------------------------------------
-- Potts + seam gating
----------------------------------------------------------------------

local function potts(a, b, lam)
  if a == b then return 0 end
  return lam
end

local function seam_de(bufA, bufB, dir)
  local sum, n = 0, 0
  if dir == "E" then
    for y = 0, 7 do
      sum = sum + QuantizeLab.pixelDeltaE(bufA[y * 8 + 8] or 0, bufB[y * 8 + 1] or 0)
      n = n + 1
    end
  else
    for x = 1, 8 do
      sum = sum + QuantizeLab.pixelDeltaE(bufA[7 * 8 + x] or 0, bufB[x] or 0)
      n = n + 1
    end
  end
  return (n > 0) and (sum / n) or 0
end

local function edge_lambda(bufA, bufB, dir, baseLam, edgeDe)
  if seam_de(bufA, bufB, dir) >= edgeDe then return 0 end
  return baseLam
end

----------------------------------------------------------------------
-- α-expansion (Kolmogorov add_term2)
----------------------------------------------------------------------

local function alpha_expand_once(nodes, edges, labels, alpha)
  local n = #nodes
  local g = dinic_new()
  local src = dinic_add_node(g)
  local snk = dinic_add_node(g)
  local gid = {}

  -- Binary: S-set (source-reachable) → take α; T-set → keep old label.
  for i = 1, n do
    if labels[i] ~= alpha then
      gid[i] = dinic_add_node(g)
      local keep = nodes[i].data[labels[i]] or 0
      local take = nodes[i].data[alpha] or 0
      dinic_add_tweights(g, gid[i], keep, take, src, snk)
    end
  end

  local function add_term2(x, y, A, B, C, D)
    -- E00=A E01=B E10=C E11=D; require A+D <= B+C
    if A + D > B + C + 1e-6 then return end
    dinic_add_tweights(g, x, D, A, src, snk)
    B = B - A
    C = C - D
    if B < 0 then
      dinic_add_tweights(g, x, 0, -B, src, snk)
      dinic_add_tweights(g, y, 0, -B, src, snk)
      B = 0
    end
    if C < 0 then
      dinic_add_tweights(g, x, -C, 0, src, snk)
      dinic_add_tweights(g, y, -C, 0, src, snk)
      C = 0
    end
    if B > 0 or C > 0 then
      dinic_add_edge_pair(g, x, y, B, C)
    end
  end

  for _, ed in ipairs(edges) do
    local i, j, eLam = ed.a, ed.b, ed.lam
    if eLam > 0 then
      local Li, Lj = labels[i], labels[j]
      local E00 = potts(Li, Lj, eLam)
      local E01 = potts(Li, alpha, eLam)
      local E10 = potts(alpha, Lj, eLam)
      local E11 = 0
      if Li == alpha and Lj == alpha then
        -- both frozen
      elseif Li == alpha then
        if gid[j] then dinic_add_tweights(g, gid[j], E10, E11, src, snk) end
      elseif Lj == alpha then
        if gid[i] then dinic_add_tweights(g, gid[i], E01, E11, src, snk) end
      elseif gid[i] and gid[j] then
        add_term2(gid[i], gid[j], E00, E01, E10, E11)
      end
    end
  end

  dinic_maxflow(g, src, snk)

  local changed = false
  for i = 1, n do
    if gid[i] and dinic_in_source_set(g, src, gid[i]) and labels[i] ~= alpha then
      labels[i] = alpha
      changed = true
    end
  end
  return changed
end

function QuantizeMrf.expand(nodes, edges, labels, nLabels, expansions)
  expansions = expansions or QuantizeMrf.EXPANSIONS
  for i = 1, #nodes do
    if not labels[i] then labels[i] = 1 end
  end
  for _ = 1, expansions do
    local any = false
    for alpha = 1, nLabels do
      if alpha_expand_once(nodes, edges, labels, alpha) then any = true end
    end
    if not any then break end
  end
  return labels
end

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function QuantizeMrf.assignPlacements(placements, codebook, opts)
  opts = opts or {}
  local lam = opts.lambda or QuantizeMrf.LAMBDA
  local edgeDe = opts.edgeDe or QuantizeMrf.EDGE_DE
  local enabled = opts.enabled
  if enabled == nil then enabled = QuantizeMrf.ENABLED end
  local pair = opts.pair or ""
  local nLab = #codebook
  if nLab == 0 or #placements == 0 then
    return {}, { nodes = 0, labels = 0, ms = 0, mode = "empty" }
  end

  local t0 = os.clock()
  local nodes, labels = {}, {}
  for i, p in ipairs(placements) do
    local reqCat = nil
    if p.category and QuantizeLab.terrainFamily(p.category) then
      reqCat = p.category
    end
    local assignOpts = {
      requireCategory = reqCat,
      itemCategory = p.category,
      crossCatPenalty = QuantizeLab.OUTDOOR_CROSS_CAT_PENALTY,
    }
    local data = {}
    for li = 1, nLab do
      local cost = QuantizeLab.quadRampError(
        p.buf, p.pal, codebook[li].ramp, codebook[li].frlgSlot)
      if reqCat and not QuantizeLab.entryHasCategory(codebook[li], reqCat) then
        cost = cost + 1e6
      end
      -- Grass/path must not soft-land on water/sand materials via MRF.
      if p.category and QuantizeLab.OUTDOOR_GRASS_CATS[p.category] then
        local e = codebook[li]
        if QuantizeLab.entryHasCategory(e, "WATER")
          or QuantizeLab.entryHasCategory(e, "SAND")
          or e.primaryCategory == "WATER"
          or e.primaryCategory == "SAND" then
          cost = cost + QuantizeLab.OUTDOOR_CROSS_CAT_PENALTY
        end
      end
      data[li] = cost
    end
    nodes[i] = { data = data, buf = p.buf }
    labels[i] = QuantizeLab.bestCodebookIndex(p.buf, p.pal, codebook, pair, assignOpts)
  end

  if not enabled then
    return labels, {
      nodes = #nodes, labels = nLab,
      ms = (os.clock() - t0) * 1000, mode = "unary",
    }
  end

  local at = {}
  for i, p in ipairs(placements) do
    if p.gx and p.gy then
      local key = tostring(p.mapId or "") .. ":" .. p.gx .. "," .. p.gy
      at[key] = i
    end
  end

  local edges = {}
  local function link(a, b, dir)
    if a > b then return end
    edges[#edges + 1] = {
      a = a, b = b,
      lam = edge_lambda(placements[a].buf, placements[b].buf, dir, lam, edgeDe),
    }
  end
  for i, p in ipairs(placements) do
    if p.gx and p.gy then
      local base = tostring(p.mapId or "") .. ":"
      local east = at[base .. (p.gx + 1) .. "," .. p.gy]
      local south = at[base .. p.gx .. "," .. (p.gy + 1)]
      if east then link(i, east, "E") end
      if south then link(i, south, "S") end
    end
  end

  QuantizeMrf.expand(nodes, edges, labels, nLab, opts.expansions)

  return labels, {
    nodes = #nodes, edges = #edges, labels = nLab,
    ms = (os.clock() - t0) * 1000, mode = "mrf",
  }
end

-- Majority label per (mid, q); stable tie-break by earliest ord.
-- Known limitation: multi-context mids collapse to one assignment.
function QuantizeMrf.majorityPerMid(placements, labels)
  local tallies = {}
  for i, p in ipairs(placements) do
    local mid, q, lab = p.mid, p.q, labels[i]
    tallies[mid] = tallies[mid] or {}
    local t = tallies[mid][q]
    if not t then
      t = { counts = {}, best = lab, bestN = 0, bestOrd = p.ord or i }
      tallies[mid][q] = t
    end
    t.counts[lab] = (t.counts[lab] or 0) + 1
    local n, ord = t.counts[lab], p.ord or i
    if n > t.bestN
      or (n == t.bestN and lab < t.best)
      or (n == t.bestN and lab == t.best and ord < t.bestOrd) then
      t.best, t.bestN, t.bestOrd = lab, n, ord
    end
  end
  local out = {}
  for mid, qs in pairs(tallies) do
    out[mid] = {}
    for q, t in pairs(qs) do out[mid][q] = t.best end
  end
  return out
end

QuantizeMrf._dinic_new = dinic_new
QuantizeMrf._dinic_add_node = dinic_add_node
QuantizeMrf._dinic_add_edge_pair = dinic_add_edge_pair
QuantizeMrf._dinic_add_tweights = dinic_add_tweights
QuantizeMrf._dinic_maxflow = dinic_maxflow
QuantizeMrf._dinic_in_source_set = dinic_in_source_set
QuantizeMrf._seam_de = seam_de
QuantizeMrf._alpha_expand_once = alpha_expand_once

return QuantizeMrf
