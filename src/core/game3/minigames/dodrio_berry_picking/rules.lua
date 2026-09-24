local R = {}

-- pokefirered/src/dodrio_berry_picking.c:27
R.MAX_SCORE = 999990
R.MAX_BERRIES = 9999
R.PRIZE_SCORE = 3000
R.NUM_DIFFICULTIES = 7
R.MAX_FALL_DIST = 10
R.EAT_FALL_DIST = 7
R.NUM_STATUS_SQUARES = 10
R.RESULT_LIMIT = 20000
R.PLAYER_NONE = 0xFF
R.MAX_PLAYERS = 5
R.COLUMNS = 11
-- pokefirered/include/constants/items.h:181
R.FIRST_BERRY_INDEX = 133

-- pokefirered/src/dodrio_berry_picking.c:82
R.PICK_NONE, R.PICK_RIGHT, R.PICK_MIDDLE, R.PICK_LEFT, R.PICK_DISABLED = 0, 1, 2, 3, 4
-- pokefirered/src/dodrio_berry_picking.c:90
R.BERRY_BLUE, R.BERRY_GREEN, R.BERRY_GOLD, R.BERRY_MISSED, R.BERRY_PRIZE, R.BERRY_IN_ROW = 0, 1, 2, 3, 4, 5
-- pokefirered/src/dodrio_berry_picking.c:105
R.BS_NONE, R.BS_PICKED, R.BS_EATEN, R.BS_SQUISHED = 0, 1, 2, 3
-- pokefirered/src/dodrio_berry_picking.c:112
R.IN_NONE, R.IN_TRY_PICK, R.IN_PICKED, R.IN_ATE, R.IN_BAD_MISS = 0, 1, 2, 3, 4

R.PHASE_PLAY, R.PHASE_WAIT, R.PHASE_END = 0, 1, 2
-- pokefirered/src/dodrio_berry_picking.c:2867
R.PRIZE_RECEIVED, R.PRIZE_FILLED_BAG, R.PRIZE_NO_ROOM, R.NO_PRIZE = 0, 1, 2, 3

local band = bit.band

-- pokefirered/src/dodrio_berry_picking.c:2233
function R.activeColumns(n)
  if n == 1 then return 4, 7 end
  if n == 2 then return 3, 8 end
  if n == 3 then return 2, 9 end
  if n == 4 then return 1, 10 end
  return 0, 11
end

-- pokefirered/src/dodrio_berry_picking.c:4103
local DODRIO_X = {
  { 15 },
  { 12, 18 },
  { 15, 21, 9 },
  { 12, 18, 24, 6 },
  { 15, 21, 27, 3, 9 },
}

function R.dodrioX(pos, n)
  local row = DODRIO_X[n]
  return ((row and row[pos + 1]) or 0) * 8
end

-- pokefirered/src/dodrio_berry_picking.c:2406
local MISSED_BY = {
  [5] = { [0] = { 2, 3 }, { 3 }, { 3, 4 }, { 4 }, { 4, 0 }, { 0 }, { 0, 1 }, { 1 }, { 1, 2 }, { 2 } },
  [4] = { [1] = { 2, 3 }, [2] = { 3 }, [3] = { 3, 0 }, [4] = { 0 }, [5] = { 0, 1 }, [6] = { 1 },
          [7] = { 1, 2 }, [8] = { 2 } },
  [3] = { [2] = { 1, 2 }, [3] = { 2 }, [4] = { 2, 0 }, [5] = { 0 }, [6] = { 0, 1 }, [7] = { 1 } },
  [2] = { [3] = { 0, 1 }, [4] = { 0 }, [5] = { 0, 1 }, [6] = { 1 } },
}

R.MISSED_BY = MISSED_BY

local function zeros(n, v)
  local t = {}
  for i = 0, n - 1 do t[i] = v or 0 end
  return t
end

local function newResults()
  local res = {}
  for p = 0, R.MAX_PLAYERS - 1 do res[p] = zeros(6) end
  return res
end

R.newResults = newResults

function R.checkTables(T)
  assert(type(T) == "table", "dodrio_berry_picking/tables.lua is missing")
  for _, k in ipairs({ "active_column_map", "head_to_column_map", "neighbor_map", "player_id_at_column",
    "unshared_columns", "berry_fall_delays", "tree_border_x", "difficulty_thresholds", "prize_berry_ids",
    "berry_score_multipliers", "cloud_start", "cloud_move_delays", "berry_icon_x", "results_x", "results_y",
    "ranking_y", "name_window_coords", "text_colors" }) do
    assert(type(T[k]) == "table", "dodrio_berry_picking/tables.lua has no " .. k)
  end
  return T
end

function R.activeColumn(T, n, p, i)
  return T.active_column_map[n][p + 1][i + 1]
end

function R.headColumn(T, n, p, pick)
  return T.head_to_column_map[n][p + 1][pick + 1]
end

local function playerAtColumn(st, column)
  return st.T.player_id_at_column[st.n][column + 1]
end

-- pokefirered/src/dodrio_berry_picking.c:632
local function fallDelay(T, stage, id)
  local rows = T.berry_fall_delays
  local flat = stage * 3 + id
  local row = rows[math.floor(flat / 3) + 1]
  return (row and row[flat % 3 + 1]) or 0
end

local function delayStage(st, column)
  local d = st.difficulty[playerAtColumn(st, column)] or 0
  local stage = math.floor(d / R.NUM_DIFFICULTIES)
  if stage >= 2 then stage = 2 end
  return stage
end

local function nextRandom(st)
  return st.rng:next()
end

-- pokefirered/src/dodrio_berry_picking.c:757
function R.new(T, n, rng)
  R.checkTables(T)
  assert(n >= 1 and n <= R.MAX_PLAYERS, "bad player count")
  local st = {
    T = T, n = n, rng = rng,
    phase = R.PHASE_PLAY,
    ids = zeros(R.COLUMNS), fall = zeros(R.COLUMNS), echo = zeros(R.COLUMNS),
    state = zeros(R.COLUMNS), fallTimer = zeros(R.COLUMNS), newTimer = zeros(R.COLUMNS),
    eatTimer = zeros(R.COLUMNS), eatenBy = zeros(R.COLUMNS), prev = zeros(R.COLUMNS),
    att0 = zeros(R.COLUMNS, R.PLAYER_NONE), att1 = zeros(R.COLUMNS, R.PLAYER_NONE),
    pick = zeros(R.MAX_PLAYERS), ate = zeros(R.MAX_PLAYERS), missed = zeros(R.MAX_PLAYERS),
    inputState = zeros(R.MAX_PLAYERS), inputDelay = zeros(R.MAX_PLAYERS),
    difficulty = zeros(R.MAX_PLAYERS), eaten = zeros(R.MAX_PLAYERS), ack = zeros(R.MAX_PLAYERS),
    res = newResults(),
    gray = 0, falling = false, inRow = 0, maxInRow = 0, prize = 0,
  }
  st.start, st.stop = R.activeColumns(n)
  R.setRandomPrize(st)
  R.initFirstWave(st)
  return st
end

-- pokefirered/src/dodrio_berry_picking.c:2610
function R.setRandomPrize(st)
  local set = 0
  if st.n == 4 then set = 1 elseif st.n == 5 then set = 2 end
  local idx = nextRandom(st) % 10
  st.prize = st.T.prize_berry_ids[set + 1][idx + 1]
  for p = 0, R.MAX_PLAYERS - 1 do st.res[p][R.BERRY_PRIZE] = st.prize end
end

-- pokefirered/src/dodrio_berry_picking.c:1873
function R.initFirstWave(st)
  for i = st.start, st.stop - 1 do
    st.fall[i] = (i % 2 == 0) and 1 or 0
    st.ids[i] = R.BERRY_BLUE
  end
end

-- pokefirered/src/dodrio_berry_picking.c:2544
local function updateInRow(st, picked)
  if st.n ~= R.MAX_PLAYERS then return end
  if picked then
    st.inRow = st.inRow + 1
    if st.inRow > st.maxInRow then st.maxInRow = st.inRow end
    if st.inRow > R.MAX_BERRIES then st.inRow = R.MAX_BERRIES end
  else
    if st.inRow > st.maxInRow then st.maxInRow = st.inRow end
    st.inRow = 0
  end
end

-- pokefirered/src/dodrio_berry_picking.c:2406
local function incrementResult(st, berryArg, column, player)
  if berryArg ~= R.BERRY_MISSED then
    local id = st.echo[column]
    local r = st.res[player]
    if r[id] < R.RESULT_LIMIT then r[id] = r[id] + 1 end
    return
  end
  local byCol = MISSED_BY[st.n]
  local who = byCol and byCol[column]
  if not who then return end
  for _, p in ipairs(who) do
    st.res[p][R.BERRY_MISSED] = band(st.res[p][R.BERRY_MISSED] + 1, 0xFFFF)
  end
end

-- pokefirered/src/dodrio_berry_picking.c:2326
local function tryIncrementDifficulty(st, p)
  local d = st.difficulty[p]
  local th = st.T.difficulty_thresholds[d % R.NUM_DIFFICULTIES + 1]
    + math.floor(d / R.NUM_DIFFICULTIES) * 100
  th = band(th, 0xFF)
  if st.eaten[p] >= th then st.difficulty[p] = band(d + 1, 0xFF) end
end

-- pokefirered/src/dodrio_berry_picking.c:2369
local function berryIdByDifficulty(st, difficulty, column)
  local prevId = st.prev[column]
  local m = difficulty % R.NUM_DIFFICULTIES
  if m == 1 then return R.BERRY_GREEN end
  if m == 2 then return R.BERRY_GOLD end
  if m == 3 then return prevId == R.BERRY_BLUE and R.BERRY_GREEN or R.BERRY_BLUE end
  if m == 4 then return prevId == R.BERRY_BLUE and R.BERRY_GOLD or R.BERRY_BLUE end
  if m == 5 then return prevId == R.BERRY_GOLD and R.BERRY_GREEN or R.BERRY_GOLD end
  if m == 6 then
    if prevId == R.BERRY_BLUE then return R.BERRY_GREEN end
    if prevId == R.BERRY_GREEN then return R.BERRY_GOLD end
    return R.BERRY_BLUE
  end
  return R.BERRY_BLUE
end

R.berryIdByDifficulty = berryIdByDifficulty

-- pokefirered/src/dodrio_berry_picking.c:2341
local function newBerryId(st, player, column)
  local T, n = st.T, st.n
  local nb = T.neighbor_map[n][player + 1]
  local left, middle, right = nb[1], nb[2], nb[3]
  local unshared = T.unshared_columns[n]
  for i = 1, #unshared do
    local c = unshared[i]
    if c == 0 then break end
    if column == c then return berryIdByDifficulty(st, st.difficulty[middle], column) end
  end
  local hi
  if st.difficulty[left] > st.difficulty[middle] then hi = st.difficulty[left] else hi = st.difficulty[middle] end
  if st.difficulty[right] > hi then hi = st.difficulty[right] end
  return berryIdByDifficulty(st, hi, column)
end

R.newBerryId = newBerryId

-- pokefirered/src/dodrio_berry_picking.c:2011
local function tryPickBerry(st, p, pickState, column)
  local pick = 0
  if pickState == R.PICK_MIDDLE then pick = 1 elseif pickState == R.PICK_RIGHT then pick = 2 end
  local head = R.headColumn(st.T, st.n, p, pick)
  local f = st.fall[column]
  if f == R.EAT_FALL_DIST - 1 or f == R.EAT_FALL_DIST then
    if column == head then
      if st.state[column] == R.BS_PICKED or st.state[column] == R.BS_EATEN then
        st.missed[p] = 1
        return false
      end
      return true
    end
  elseif column == head then
    st.inputState[p] = R.IN_BAD_MISS
    st.missed[p] = 1
  end
  return false
end

R.tryPickBerry = tryPickBerry

local function mapColumn(j)
  if j >= 10 then return j - 10 end
  return j
end

-- pokefirered/src/dodrio_berry_picking.c:1890
local function handlePickBerries(st)
  if st.gray >= R.NUM_STATUS_SQUARES then return end
  for p = 0, st.n - 1 do
    local ps = st.pick[p]
    if ps ~= R.PICK_NONE and st.inputState[p] == R.IN_TRY_PICK then
      for j = st.start, st.stop - 1 do
        local column = mapColumn(j)
        if st.att0[column] == p or st.att1[column] == p then break end
        if tryPickBerry(st, p, ps, column) then
          if st.att0[column] == R.PLAYER_NONE then
            st.att0[column] = p
            st.inputState[p] = R.IN_PICKED
            st.state[column] = R.BS_PICKED
          elseif st.att1[column] == R.PLAYER_NONE then
            st.att1[column] = p
            st.inputState[p] = R.IN_PICKED
            st.state[column] = R.BS_PICKED
          end
          break
        end
        if st.missed[p] == 1 then break end
      end
    end
  end
  for j = st.start, st.stop - 1 do
    local column = mapColumn(j)
    if st.state[column] == R.BS_PICKED then
      local remaining = fallDelay(st.T, delayStage(st, column), st.echo[column]) - st.fallTimer[column]
      if remaining < 6 then st.eatTimer[column] = band(st.eatTimer[column] + remaining, 0xFF) end
      st.eatTimer[column] = band(st.eatTimer[column] + 1, 0xFF)
      if st.eatTimer[column] >= 6 then
        st.eatTimer[column] = 0
        local a0, a1 = st.att0[column], st.att1[column]
        if not (a0 == R.PLAYER_NONE and a1 == R.PLAYER_NONE) then
          local picked, lost = nil, R.PLAYER_NONE
          if a0 ~= R.PLAYER_NONE and a1 == R.PLAYER_NONE then
            picked = a0
          elseif band(nextRandom(st), 1) == 0 then
            picked, lost = a0, a1
          else
            picked, lost = a1, a0
          end
          if picked ~= R.PLAYER_NONE then
            st.fall[column] = R.EAT_FALL_DIST
            st.state[column] = R.BS_EATEN
            st.inputState[picked] = R.IN_ATE
            st.eatenBy[column] = picked
            st.ate[picked] = 1
            if lost ~= R.PLAYER_NONE then st.missed[lost] = 1 end
            st.eaten[picked] = band(st.eaten[picked] + 1, 0xFFFF)
            incrementResult(st, R.BERRY_BLUE, column, picked)
            updateInRow(st, true)
            tryIncrementDifficulty(st, picked)
            st.prev[column] = st.ids[column]
            st.ids[column] = R.BERRY_MISSED
          end
          st.att0[column] = R.PLAYER_NONE
          st.att1[column] = R.PLAYER_NONE
        end
      end
    end
  end
end

-- pokefirered/src/dodrio_berry_picking.c:2064
local function updateFallingBerries(st)
  st.falling = false
  local otherMissed = false
  for i = st.start, st.stop - 2 do
    local s = st.state[i]
    if s == R.BS_NONE or s == R.BS_PICKED then
      st.falling = true
      if st.fall[i] >= R.MAX_FALL_DIST then
        st.fall[i] = R.MAX_FALL_DIST
        st.state[i] = R.BS_SQUISHED
        if st.gray < R.NUM_STATUS_SQUARES or otherMissed then
          otherMissed = true
          if st.gray < R.NUM_STATUS_SQUARES then st.gray = st.gray + 1 end
          incrementResult(st, R.BERRY_MISSED, i, 0)
          updateInRow(st, false)
        end
      else
        local delay = fallDelay(st.T, delayStage(st, i), st.ids[i])
        st.fallTimer[i] = band(st.fallTimer[i] + 1, 0xFF)
        if st.fallTimer[i] >= delay then
          st.fall[i] = st.fall[i] + 1
          st.fallTimer[i] = 0
        end
        handlePickBerries(st)
      end
    elseif s == R.BS_EATEN then
      st.newTimer[i] = band(st.newTimer[i] + 1, 0xFF)
      if st.newTimer[i] >= 20 then
        st.ate[st.eatenBy[i]] = 0
        st.newTimer[i] = 0
        st.fallTimer[i] = 0
        st.state[i] = R.BS_NONE
        st.fall[i] = 1
        st.ids[i] = newBerryId(st, playerAtColumn(st, i), i)
      end
    elseif s == R.BS_SQUISHED then
      st.newTimer[i] = band(st.newTimer[i] + 1, 0xFF)
      if st.newTimer[i] >= 20 and st.gray < R.NUM_STATUS_SQUARES then
        st.newTimer[i] = 0
        st.fallTimer[i] = 0
        st.state[i] = R.BS_NONE
        st.fall[i] = 1
        st.prev[i] = st.ids[i]
        st.ids[i] = newBerryId(st, playerAtColumn(st, i), i)
      end
    end
  end
end

-- pokefirered/src/dodrio_berry_picking.c:1493
local function recvInputs(st, presses)
  for p = 0, st.n - 1 do
    local inp = presses and presses[p]
    local fresh = false
    if type(inp) == "table" then
      local k = tonumber(inp.n)
      if k and k % 256 ~= st.ack[p] then
        st.ack[p] = k % 256
        fresh = true
      end
    end
    if st.inputState[p] == R.IN_NONE then
      local d = fresh and tonumber(inp.d) or R.PICK_NONE
      if d == R.PICK_RIGHT or d == R.PICK_MIDDLE or d == R.PICK_LEFT then
        st.pick[p] = d
      else
        st.pick[p] = R.PICK_NONE
      end
    end
  end
  for p = 0, st.n - 1 do
    if st.pick[p] ~= R.PICK_NONE and st.inputState[p] == R.IN_NONE then
      st.inputState[p] = R.IN_TRY_PICK
    end
    local is = st.inputState[p]
    local limit = (is == R.IN_BAD_MISS) and 40 or ((is ~= R.IN_NONE) and 6 or nil)
    if limit then
      st.inputDelay[p] = st.inputDelay[p] + 1
      if st.inputDelay[p] >= limit then
        st.inputDelay[p] = 0
        st.inputState[p] = R.IN_NONE
        st.pick[p] = R.PICK_NONE
        st.ate[p] = 0
        st.missed[p] = 0
      end
    end
  end
end

-- pokefirered/src/dodrio_berry_picking.c:2566
local function setMaxInRow(st)
  for p = 0, st.n - 1 do st.res[p][R.BERRY_IN_ROW] = st.maxInRow end
end

-- pokefirered/src/dodrio_berry_picking.c:968
function R.step(st, presses)
  if st.phase == R.PHASE_END then return st end
  if st.phase == R.PHASE_PLAY then
    recvInputs(st, presses)
    if st.gray >= R.NUM_STATUS_SQUARES then st.phase = R.PHASE_WAIT end
    updateFallingBerries(st)
  else
    updateFallingBerries(st)
    if st.gray >= R.NUM_STATUS_SQUARES and not st.falling then
      st.gray = R.NUM_STATUS_SQUARES
      setMaxInRow(st)
      st.phase = R.PHASE_END
    end
  end
  for c = 0, R.COLUMNS - 1 do st.echo[c] = st.ids[c] end
  return st
end

function R.ended(st)
  return st.phase == R.PHASE_END
end

function R.emptyView(n)
  return {
    n = n,
    ids = zeros(R.COLUMNS), fall = zeros(R.COLUMNS),
    pick = zeros(R.MAX_PLAYERS), ate = zeros(R.MAX_PLAYERS), missed = zeros(R.MAX_PLAYERS),
    ack = zeros(R.MAX_PLAYERS),
    gray = 0, falling = false, ph = R.PHASE_PLAY, live = false,
  }
end

-- pokefirered/src/dodrio_berry_picking_comm.c:156
function R.view(st, out)
  local v = out or R.emptyView(st.n)
  for c = 0, 9 do
    v.ids[c] = st.ids[c]
    v.fall[c] = st.fall[c]
  end
  v.ids[10], v.fall[10] = v.ids[0], v.fall[0]
  for p = 0, R.MAX_PLAYERS - 1 do
    v.pick[p] = band(st.pick[p], 3)
    v.ate[p] = st.ate[p]
    v.missed[p] = st.missed[p]
    v.ack[p] = st.ack[p]
  end
  v.gray = st.gray
  v.falling = st.falling
  v.ph = st.phase
  v.live = true
  return v
end

local HEX = "0123456789abcdef"

local function hex(v, width)
  local out = {}
  for i = width - 1, 0, -1 do
    local d = math.floor(v / 16 ^ i) % 16
    out[#out + 1] = HEX:sub(d + 1, d + 1)
  end
  return table.concat(out)
end

local function unhex(s, pos, width)
  local v = 0
  for i = 0, width - 1 do
    local ch = s:sub(pos + i, pos + i)
    local d = HEX:find(ch, 1, true)
    if not d then return nil end
    v = v * 16 + (d - 1)
  end
  return v
end

local function att(v)
  if v == R.PLAYER_NONE then return 15 end
  return v
end

local function unatt(v)
  if v == 15 then return R.PLAYER_NONE end
  return v
end

function R.encode(st)
  local a, b, c = {}, {}, {}
  for _, key in ipairs({ "ids", "fall", "state", "prev" }) do
    for i = 0, 9 do a[#a + 1] = hex(st[key][i], 1) end
  end
  for i = 0, 9 do b[#b + 1] = hex(st.eatenBy[i], 1) end
  for i = 0, 9 do b[#b + 1] = hex(att(st.att0[i]), 1) end
  for i = 0, 9 do b[#b + 1] = hex(att(st.att1[i]), 1) end
  for _, key in ipairs({ "fallTimer", "newTimer", "eatTimer" }) do
    for i = 0, 9 do c[#c + 1] = hex(st[key][i], 2) end
  end
  local p = {}
  for k = 0, st.n - 1 do
    local r = st.res[k]
    p[k + 1] = table.concat({
      hex(st.pick[k], 1), hex(st.ate[k], 1), hex(st.missed[k], 1), hex(st.inputState[k], 1),
      hex(st.inputDelay[k], 2), hex(st.difficulty[k], 2), hex(st.eaten[k], 4),
      hex(r[0], 4), hex(r[1], 4), hex(r[2], 4), hex(r[3], 4), hex(st.ack[k], 2),
    })
  end
  return {
    a = table.concat(a), b = table.concat(b), c = table.concat(c), p = p,
    g = st.gray, fl = st.falling and 1 or 0, r = st.inRow, x = st.maxInRow,
    z = st.prize, q = st.rng and st.rng.state or 0, ph = st.phase,
  }
end

function R.decode(T, n, s, rng)
  if type(s) ~= "table" or type(s.a) ~= "string" or type(s.b) ~= "string" or type(s.c) ~= "string"
      or type(s.p) ~= "table" or #s.a ~= 40 or #s.b ~= 30 or #s.c ~= 60 then
    return nil
  end
  local st = R.new(T, n, { state = 0, next = function() return 0 end })
  st.rng = rng
  local pos = 1
  for _, key in ipairs({ "ids", "fall", "state", "prev" }) do
    for i = 0, 9 do
      st[key][i] = unhex(s.a, pos, 1) or 0
      pos = pos + 1
    end
  end
  pos = 1
  for i = 0, 9 do st.eatenBy[i] = unhex(s.b, pos, 1) or 0 pos = pos + 1 end
  for i = 0, 9 do st.att0[i] = unatt(unhex(s.b, pos, 1) or 15) pos = pos + 1 end
  for i = 0, 9 do st.att1[i] = unatt(unhex(s.b, pos, 1) or 15) pos = pos + 1 end
  pos = 1
  for _, key in ipairs({ "fallTimer", "newTimer", "eatTimer" }) do
    for i = 0, 9 do
      st[key][i] = unhex(s.c, pos, 2) or 0
      pos = pos + 2
    end
  end
  st.ids[10], st.fall[10] = st.ids[0], st.fall[0]
  for k = 0, n - 1 do
    local ps = s.p[k + 1]
    if type(ps) == "string" and #ps == 30 then
      st.pick[k] = unhex(ps, 1, 1) or 0
      st.ate[k] = unhex(ps, 2, 1) or 0
      st.missed[k] = unhex(ps, 3, 1) or 0
      st.inputState[k] = unhex(ps, 4, 1) or 0
      st.inputDelay[k] = unhex(ps, 5, 2) or 0
      st.difficulty[k] = unhex(ps, 7, 2) or 0
      st.eaten[k] = unhex(ps, 9, 4) or 0
      local r = st.res[k]
      r[0] = unhex(ps, 13, 4) or 0
      r[1] = unhex(ps, 17, 4) or 0
      r[2] = unhex(ps, 21, 4) or 0
      r[3] = unhex(ps, 25, 4) or 0
      st.ack[k] = unhex(ps, 29, 2) or 0
    end
  end
  st.gray = tonumber(s.g) or 0
  st.falling = tonumber(s.fl) == 1
  st.inRow = tonumber(s.r) or 0
  st.maxInRow = tonumber(s.x) or 0
  st.prize = tonumber(s.z) or st.prize
  st.phase = tonumber(s.ph) or R.PHASE_PLAY
  for p = 0, R.MAX_PLAYERS - 1 do st.res[p][R.BERRY_PRIZE] = st.prize end
  if st.phase == R.PHASE_END then
    for p = 0, n - 1 do st.res[p][R.BERRY_IN_ROW] = st.maxInRow end
  end
  for c = 0, R.COLUMNS - 1 do st.echo[c] = st.ids[c] end
  if rng and s.q then rng.state = (tonumber(s.q) or 0) % 0x100000000 end
  return st
end

-- pokefirered/src/dodrio_berry_picking.c:2722
function R.score(T, r)
  local mult = T.berry_score_multipliers
  local score = 0
  for i = 0, 2 do score = score + (r[i] or 0) * mult[i + 1] end
  local lost = (r[R.BERRY_MISSED] or 0) * mult[R.BERRY_MISSED + 1]
  if score <= lost then return 0 end
  return score - lost
end

-- pokefirered/src/dodrio_berry_picking.c:2740
function R.highestScore(T, res, n)
  local hi = R.score(T, res[0])
  for p = 1, n - 1 do
    local s = R.score(T, res[p])
    if s > hi then hi = s end
  end
  return math.min(hi, R.MAX_SCORE)
end

-- pokefirered/src/dodrio_berry_picking.c:2754
function R.highestResult(res, n, id)
  local hi = res[0][id] or 0
  for p = 0, n - 1 do
    if (res[p][id] or 0) > hi then hi = res[p][id] end
  end
  return hi
end

-- pokefirered/src/dodrio_berry_picking.c:2625
function R.berriesPicked(r)
  return math.min((r[0] or 0) + (r[1] or 0) + (r[2] or 0), R.MAX_BERRIES)
end

-- pokefirered/src/dodrio_berry_picking.c:2794
function R.scoreResults(T, res, n)
  local out = {}
  local raw = {}
  for p = 0, n - 1 do
    raw[p + 1] = R.score(T, res[p])
    out[p] = { ranking = 0, score = math.min(raw[p + 1], R.MAX_SCORE) }
  end
  table.sort(raw, function(x, y) return x > y end)
  local ranking, nextRanking, ranked = 0, 0, 0
  local guard = 0
  repeat
    local score = raw[ranking + 1]
    local cur = nextRanking
    for p = 0, n - 1 do
      if score == out[p].score then
        out[p].ranking = cur
        nextRanking = nextRanking + 1
        ranked = ranked + 1
      end
    end
    ranking = nextRanking
    guard = guard + 1
  until ranked >= n or guard > n
  return out
end

-- pokefirered/src/dodrio_berry_picking.c:4417
function R.rankedOrder(T, res, n)
  local sr = R.scoreResults(T, res, n)
  local order = { [0] = 0, 1, 2, 3, 4 }
  for p = 0, n - 1 do order[p] = p end
  if R.highestScore(T, res, n) ~= 0 then
    local ranking, ranked = 0, 0
    local guard = 0
    repeat
      for p = 0, n - 1 do
        if sr[p].ranking == ranking then
          order[ranked] = p
          ranked = ranked + 1
        end
      end
      ranking = ranked
      guard = guard + 1
    until ranked >= n or guard > n
  end
  for p = 0, n - 1 do
    if sr[p].score == 0 then sr[p].ranking = n - 1 end
  end
  local rows = {}
  for i = 0, n - 1 do
    local p = order[i]
    rows[#rows + 1] = { player = p, ranking = sr[p].ranking, score = sr[p].score }
  end
  return rows
end

function R.prizeItem(prize)
  return (tonumber(prize) or 0) + R.FIRST_BERRY_INDEX
end

function R.newStatusBar()
  return { flash = 0, frames = zeros(R.NUM_STATUS_SQUARES) }
end

-- pokefirered/src/dodrio_berry_picking.c:3821
function R.updateStatusBar(bar, numEmpty)
  local frames = bar.frames
  if numEmpty > R.NUM_STATUS_SQUARES then
    for i = 0, 9 do frames[i] = 1 end
    return frames
  end
  local i = 0
  while i < R.NUM_STATUS_SQUARES - numEmpty do
    if numEmpty > 6 then
      bar.flash = band(bar.flash + (numEmpty - 6), 0xFFFF)
      if bar.flash > 30 then
        bar.flash = 0
      elseif bar.flash > 10 then
        frames[i] = 2
      else
        frames[i] = 0
      end
    else
      frames[i] = 0
    end
    i = i + 1
  end
  for k = i, 9 do frames[k] = 1 end
  return frames
end

return R
