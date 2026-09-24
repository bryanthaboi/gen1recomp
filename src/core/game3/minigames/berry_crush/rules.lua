local R = {}

-- pokefirered/src/berry_crush.c:34
R.MAX_TIME = 10 * 60 * 60
-- pokefirered/src/berry_crush.c:49
R.CRUSHER_START_Y = -104
-- pokefirered/include/constants/items.h:181
R.FIRST_BERRY = 133
R.LAST_BERRY = 175
R.NUM_BERRIES = R.LAST_BERRY - R.FIRST_BERRY + 1
R.MAX_PLAYERS = 5
-- pokefirered/src/berry_crush.c:176
R.F_INPUT_HIT_B = 2
R.F_INPUT_HIT_SYNC = 4
-- pokefirered/src/berry_crush.c:183
R.INPUT_STATE_HIT = 1
R.INPUT_STATE_HIT_SYNC = 2
-- pokefirered/src/berry_crush.c:142
R.PAGE_PRESSES = 0
R.PAGE_RANDOM = 1
R.PAGE_CRUSHING = 2
-- pokefirered/src/berry_crush.c:152
R.RANDOM_NEATNESS = 0
R.RANDOM_COOPERATIVE = 1
R.RANDOM_POWER = 2
R.NUM_RANDOM_PAGES = 3

local floor = math.floor

local function trunc(a, b)
  if b == 0 then return 0 end
  local q = a / b
  if q >= 0 then return floor(q) end
  return -floor(-q)
end

local function wrap(v, bits)
  local m = 2 ^ bits
  return v % m
end

local function s16(v)
  v = wrap(v, 16)
  if v >= 0x8000 then v = v - 0x10000 end
  return v
end

local function u16(v) return wrap(v, 16) end
local function u8(v) return wrap(v, 8) end

local function shr(v, n) return floor(v / 2 ^ n) end

R.trunc, R.s16, R.u16, R.u8, R.shr = trunc, s16, u16, u8, shr

-- pokefirered/src/math_util.c:52
function R.q24div(x, y)
  if y == 0 then return 0 end
  return trunc(x * 256, y)
end

-- pokefirered/src/math_util.c:24
function R.q24mul(x, y)
  return trunc(x * y, 256)
end

-- pokefirered/src/math_util.c:43
function R.qnsDiv(s, x, y)
  if y == 0 then return 0 end
  return s16(trunc(x * 2 ^ s, y))
end

-- pokefirered/src/math_util.c:14
function R.qnsMul(s, x, y)
  return s16(trunc(x * y, 2 ^ s))
end

function R.qns(s, n) return s16(floor(n * 2 ^ s)) end

function R.berryIndex(itemId)
  itemId = tonumber(itemId)
  if not itemId or itemId < R.FIRST_BERRY or itemId > R.LAST_BERRY then return nil end
  return itemId - R.FIRST_BERRY
end

function R.newPlayer()
  -- pokefirered/src/berry_crush.c:2452
  return { np = 0, ns = 0, st = 0, mx = 0, td = 1, it = 0, fl = 0, sn = 0, is = 0 }
end

-- pokefirered/src/berry_crush.c:2424
function R.newState(n)
  local st = {
    n = n, ph = 1, berries = {}, held = {}, pl = {},
    lt = 0, timer = 0, tp = 0, ta = 0, targetDepth = 0, powder = 0,
    sc = 0, bc = 0, nb = 0, nc = -1, sa = 0, bs = false, nd = 0,
    gc = 0, gi = 0, gn = 0, gv = false, endGame = false,
    lastT = -1, lastEg = false, ended = nil,
    round = 0, gone = {}, ld = nil, res = nil,
  }
  for p = 1, n do
    st.berries[p] = -1
    st.held[p] = 0
    st.pl[p] = R.newPlayer()
  end
  return st
end

-- pokefirered/src/berry_crush.c:2333
function R.nextRound(st)
  local nxt = R.newState(st.n)
  nxt.round = st.round + 1
  nxt.ld = st.ld
  for p = 1, st.n do
    nxt.gone[p] = st.gone[p]
    nxt.pl[p].sn = st.pl[p].sn
  end
  return nxt
end

function R.encodeResults(res, n)
  local out = {
    res.time or 0, res.silk or 0, res.powder or 0, res.page or 0, res.total or 0, res.timeUp and 1 or 0,
  }
  for p = 1, n do
    out[#out + 1] = (res.presses and res.presses[p]) or 0
    out[#out + 1] = (res.random and res.random[p]) or 0
  end
  return out
end

function R.decodeResults(r, n)
  if type(r) ~= "table" then return nil end
  local function at(i) return floor(tonumber(r[i]) or 0) end
  local res = {
    time = at(1), silk = at(2), powder = at(3), page = at(4) % R.NUM_RANDOM_PAGES, total = at(5),
    timeUp = at(6) == 1, presses = {}, random = {},
  }
  for p = 1, n do
    res.presses[p] = at(6 + (p - 1) * 2 + 1)
    res.random[p] = at(6 + (p - 1) * 2 + 2)
  end
  res.speed = R.pressingSpeed(res.time, res.total)
  return res
end

-- pokefirered/src/berry_crush.c:1393
function R.setBerries(st, T, berries)
  st.ta, st.powder = 0, 0
  for p = 1, st.n do
    local b = tonumber(berries[p]) or -1
    st.berries[p] = b
    local row = b >= 0 and T.berry_data[b + 1] or nil
    if row then
      st.ta = st.ta + row.difficulty
      st.powder = st.powder + row.powder
    end
  end
  st.ta = s16(st.ta)
  st.targetDepth = R.q24div(st.ta * 256, 32 * 256)
end

local function band(a, b)
  local r, bit = 0, 1
  while a > 0 and b > 0 do
    if a % 2 == 1 and b % 2 == 1 then r = r + bit end
    a, b, bit = floor(a / 2), floor(b / 2), bit * 2
  end
  return r
end
R.band = band

-- pokefirered/src/berry_crush.c:1557
function R.partnerInput(st, pressed, T)
  local n = st.n
  local num = 0
  for p = 1, n do
    local pl = st.pl[p]
    if pressed[p] then
      pl.is = R.INPUT_STATE_HIT
      pl.np = u16(pl.np + 1)
      num = num + 1
      local diff = u16(st.timer - pl.it)
      if diff >= pl.td - 1 and diff <= pl.td + 1 then
        pl.st = u16(pl.st + 1)
        pl.td = diff
        if pl.st > pl.mx then pl.mx = pl.st end
      else
        pl.st = 0
        pl.td = diff
      end
      pl.it = st.timer
      pl.fl = pl.fl + 1
      if pl.fl > R.F_INPUT_HIT_B then pl.fl = 0 end
    else
      pl.is = 0
    end
  end
  if num > 1 then
    for p = 1, n do
      local pl = st.pl[p]
      if pl.is ~= 0 then
        if band(pl.is, R.INPUT_STATE_HIT_SYNC) == 0 then pl.is = pl.is + R.INPUT_STATE_HIT_SYNC end
        pl.ns = u16(pl.ns + 1)
      end
    end
  end
  if num == 0 then return end
  st.bc = s16(st.bc + num)
  num = num + T.sync_press_bonus[num]
  st.sc = s16(st.sc + num)
  st.tp = s16(st.tp + num)
  if st.ta - st.tp > 0 then
    local temp = R.q24div(st.tp * 256, st.targetDepth)
    st.nd = u8(shr(temp, 8))
    return
  end
  st.nd = 32
  st.endGame = true
end

-- pokefirered/src/berry_crush.c:1644
function R.buildLocalState(st, T)
  local num, flags = 0, 0
  for p = 1, st.n do
    local pl = st.pl[p]
    if pl.is ~= 0 then
      num = num + 1
      local r1 = pl.fl + 1
      if band(pl.is, 2) ~= 0 then r1 = r1 + 4 end
      flags = flags + r1 * 2 ^ (3 * (p - 1))
    end
  end
  flags = u16(flags)
  if num == 0 then
    if st.gv then st.gc = st.gc + 1 end
  elseif st.gv then
    if num ~= st.gi then
      st.gi = num - 1
      st.gn = T.vibration[num][1]
    else
      st.gc = st.gc + 1
    end
  else
    st.gc = 0
    st.gi = num - 1
    st.gn = T.vibration[num][1]
    st.gv = true
  end
  local vib = 0
  if st.gv then
    if st.gc >= st.gn then
      st.gc, st.gi, st.gn, st.gv = 0, 0, 0, false
      vib = 0
    else
      vib = T.vibration[st.gi + 1][st.gc + 2]
    end
  end
  return { t = u16(st.lt), d = st.nd, v = vib, fl = flags }
end

-- pokefirered/src/berry_crush.c:1711
function R.playerInput(st, T, rec)
  local n = st.n
  if st.timer % 30 == 0 then
    if st.bc > T.big_sparkle_thresholds[n - 1] then
      st.nb = s16(st.nb + 1)
      st.bs = true
    else
      st.bs = false
    end
    st.bc = 0
    st.nc = s16(st.nc + 1)
  end
  if st.timer % 15 == 0 then
    local th = T.sparkle_thresholds[n - 1]
    if st.sc < th[1] then
      st.sa = 0
    elseif st.sc < th[2] then
      st.sa = 1
    elseif st.sc < th[3] then
      st.sc = 2
    elseif st.sc < th[4] then
      st.sc = 3
    else
      st.sa = 4
    end
    st.sc = 0
  end
  if st.timer >= R.MAX_TIME then st.endGame = true end
  rec.big = st.bs
  rec.sa = st.sa
  rec.eg = st.endGame
  return rec
end

-- pokefirered/src/berry_crush.c:1825
function R.leaderFrame(st, pressed, T)
  st.endGame = false
  st.lt = u16(st.lt + 1)
  R.partnerInput(st, pressed, T)
  local rec = R.buildLocalState(st, T)
  R.playerInput(st, T, rec)
  st.lastT = rec.t
  st.lastEg = rec.eg
  return rec
end

function R.encodeRecord(rec, out)
  out[#out + 1] = rec.t
  out[#out + 1] = rec.d
  out[#out + 1] = rec.v
  out[#out + 1] = rec.fl
  out[#out + 1] = (rec.sa or 0) * 4 + (rec.big and 2 or 0) + (rec.eg and 1 or 0)
  return out
end

function R.decodeRecords(q)
  local out = {}
  if type(q) ~= "table" then return out end
  local i = 1
  while q[i + 4] ~= nil do
    local x = floor(tonumber(q[i + 4]) or 0)
    out[#out + 1] = {
      t = floor(tonumber(q[i]) or 0), d = floor(tonumber(q[i + 1]) or 0),
      v = floor(tonumber(q[i + 2]) or 0), fl = floor(tonumber(q[i + 3]) or 0),
      sa = floor(x / 4) % 8, big = floor(x / 2) % 2 == 1, eg = x % 2 == 1,
    }
    i = i + 5
  end
  return out
end

function R.recordFlags(rec, p)
  return floor(rec.fl / 2 ^ (3 * (p - 1))) % 8
end

-- pokefirered/src/berry_crush.c:2119
function R.rank(presses, random)
  local n = #presses
  local s0, s1, r0, r1 = {}, {}, {}, {}
  for i = 1, n do
    s0[i], s1[i] = presses[i], random[i]
    r0[i], r1[i] = i, i
  end
  for i = 1, n - 1 do
    for j = n, i + 1, -1 do
      if s0[j - 1] < s0[j] then
        s0[j], s0[j - 1] = s0[j - 1], s0[j]
        r0[j], r0[j - 1] = r0[j - 1], r0[j]
      end
      if s1[j - 1] < s1[j] then
        s1[j], s1[j - 1] = s1[j - 1], s1[j]
        r1[j], r1[j - 1] = r1[j - 1], r1[j]
      end
    end
  end
  return s0, r0, s1, r1
end

-- pokefirered/src/berry_crush.c:2024
function R.tabulate(st, pageId)
  local n, timer = st.n, st.timer
  local res = { time = timer, page = pageId, total = 0, presses = {}, random = {} }
  local temp1 = R.q24mul(st.nb * 256, 50 * 256)
  temp1 = R.q24div(temp1, st.nc * 256) + 50 * 256
  temp1 = shr(temp1, 8)
  res.silk = band(temp1, 0x7F)
  temp1 = R.q24div(temp1 * 256, 100 * 256)
  local temp2 = (st.powder * n) * 256
  temp2 = R.q24mul(temp2, temp1)
  res.powder = shr(temp2, 8)
  for p = 1, n do
    local pl = st.pl[p]
    res.presses[p] = pl.np
    res.total = res.total + pl.np
    local held = math.min(tonumber(st.held[p]) or 0, timer)
    local t2 = 0
    if pageId == R.RANDOM_NEATNESS then
      if pl.np ~= 0 then t2 = R.q24div(R.q24mul(pl.mx * 256, 100 * 256), pl.np * 256) end
    elseif pageId == R.RANDOM_COOPERATIVE then
      if pl.np ~= 0 then t2 = R.q24div(R.q24mul(pl.ns * 256, 100 * 256), pl.np * 256) end
    else
      if pl.np == 0 then
        t2 = 0
      elseif held >= timer then
        t2 = 100 * 256
      else
        t2 = R.q24div(R.q24mul(held * 256, 100 * 256), timer * 256)
      end
    end
    res.random[p] = u16(shr(t2, 4))
  end
  res.total = u16(res.total)
  return res
end

-- pokefirered/src/berry_crush.c:1049
function R.pressingSpeed(time, totalPresses)
  local t = R.q24div((tonumber(time) or 0) * 256, 60 * 256)
  return R.q24div((tonumber(totalPresses) or 0) * 256, t) % 0x10000
end

function R.fraction(bits, nbits, T)
  local score = 0
  local tbl = T and T.pressing_speed_table
  for j = 0, nbits - 1 do
    if floor(bits / 2 ^ (nbits - 1 - j)) % 2 == 1 then
      score = score + (tbl and tbl[j + 1] or 0)
    end
  end
  return floor(score / 1000000)
end

-- pokefirered/src/berry_crush.c:2878
function R.framesToMinSec(frames, T)
  frames = floor(tonumber(frames) or 0)
  local minutes = floor(frames / 3600)
  local secs = floor((frames % 3600) / 60)
  local fracQ = R.qnsMul(8, R.qns(8, frames % 60), R.qns(8, 0.016666667))
  return minutes, secs, R.fraction(fracQ % 256, 8, T)
end

return R
