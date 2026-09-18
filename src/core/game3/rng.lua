-- Pret FireRed LCRNG (include/random.h + src/random.c + wild_encounter.c).
-- ISO C rand-style: state = state * 1103515245 + C; return state >> 16.

local Rng = {}

local U32 = 4294967296
local RAND_MULT = 1103515245
local ADD1 = 24691 -- ISO_RANDOMIZE1
local ADD2 = 12345 -- ISO_RANDOMIZE2

-- Exact u32 multiply via 16×16 split (doubles lose low bits above 2^53).
function Rng.mulU32(a, b)
  a = math.floor(tonumber(a) or 0) % U32
  b = math.floor(tonumber(b) or 0) % U32
  local aL, aH = a % 65536, math.floor(a / 65536) % 65536
  local bL, bH = b % 65536, math.floor(b / 65536) % 65536
  return (aL * bL + ((aL * bH + aH * bL) % 65536) * 65536) % U32
end

local function u32(n)
  return math.floor(tonumber(n) or 0) % U32
end

local function u16(n)
  return math.floor(tonumber(n) or 0) % 65536
end

Rng._value = 0  -- gRngValue
Rng._value2 = 0 -- gRng2Value
Rng._wild = 0   -- sWildEncounterData.rngState

local function iso1(val)
  return (Rng.mulU32(val, RAND_MULT) + ADD1) % U32
end

local function iso2(val)
  return (Rng.mulU32(val, RAND_MULT) + ADD2) % U32
end

--- Pret Random(): advance gRngValue with ISO_RANDOMIZE1, return high 16 bits.
function Rng.Random()
  Rng._value = iso1(Rng._value)
  return math.floor(Rng._value / 65536) % 65536
end

--- Step RNG state once per frame (matching GBA VBlank / main loop UpdateRng).
function Rng.step()
  return Rng.Random()
end

--- Perturb the RNG state with hardware timer entropy (on boot, continue, or key presses).
function Rng.perturb(entropy)
  if entropy == nil then
    if love and love.timer and love.timer.getTime then
      entropy = math.floor(love.timer.getTime() * 1000000) % 65536
    elseif love and love.timer and love.timer.getFPS then
      entropy = (os.time() * 1000 + math.floor(os.clock() * 1000000)) % 65536
    else
      entropy = (os.time() * 997 + math.floor(os.clock() * 1000000)) % 65536
    end
  end
  Rng._value = (Rng._value + u16(entropy)) % U32
  return Rng.Random()
end

--- Pret SeedRng(u16): gRngValue = seed (zero-extended).
function Rng.SeedRng(seed)
  Rng._value = u16(seed)
end

--- Pret Random32(): (Random() | (Random() << 16)).
function Rng.Random32()
  local lo = Rng.Random()
  local hi = Rng.Random()
  return lo + hi * 65536
end

--- Pret Random2() (emerald-shaped; FR header declares it).
function Rng.Random2()
  Rng._value2 = iso1(Rng._value2)
  return math.floor(Rng._value2 / 65536) % 65536
end

function Rng.SeedRng2(seed)
  Rng._value2 = u16(seed)
end

--- pret WildEncounterRandom / SeedWildEncounterRng (ISO_RANDOMIZE2).
function Rng.WildEncounterRandom()
  Rng._wild = iso2(Rng._wild)
  return math.floor(Rng._wild / 65536) % 65536
end

function Rng.SeedWildEncounterRng(seed)
  Rng._wild = u16(seed)
end

--- Random() % n (pret style). n <= 0 → 0.
function Rng.mod(n)
  n = math.floor(tonumber(n) or 0)
  if n <= 0 then return 0 end
  return Rng.Random() % n
end

--- Drop-in for math.random used by battle adapter:
-- compat() → [0,1), compat(n) → 1..n, compat(lo,hi) → lo..hi inclusive.
function Rng.compat(lo, hi)
  if lo == nil and hi == nil then
    return Rng.Random() / 65536
  end
  if hi == nil then
    lo = math.floor(tonumber(lo) or 1)
    if lo <= 0 then return 0 end
    return 1 + (Rng.Random() % lo)
  end
  lo = math.floor(tonumber(lo) or 0)
  hi = math.floor(tonumber(hi) or lo)
  if hi < lo then lo, hi = hi, lo end
  local span = hi - lo + 1
  if span <= 0 then return lo end
  return lo + (Rng.Random() % span)
end

function Rng.getState()
  return {
    value = Rng._value,
    value2 = Rng._value2,
    wild = Rng._wild,
  }
end

function Rng.setState(st)
  if type(st) ~= "table" then return end
  if st.value ~= nil then Rng._value = u32(st.value) end
  if st.value2 ~= nil then Rng._value2 = u32(st.value2) end
  if st.wild ~= nil then Rng._wild = u32(st.wild) end
end

--- pret SeedRngAndSetTrainerId analogue: seed from a 16-bit timer-ish value.
-- Returns the seed used (trainer id lower).
function Rng.seedFromTimer(opts)
  opts = opts or {}
  local val = opts.seed
  if val == nil then
    if love and love.timer and love.timer.getTime then
      val = math.floor(love.timer.getTime() * 1000000) % 65536
    elseif love and love.timer and love.timer.getFPS then
      val = (os.time() * 1000 + (os.clock() * 1000)) % 65536
    else
      val = (os.time() * 997 + math.floor(os.clock() * 1000)) % 65536
    end
  end
  val = u16(val)
  Rng.SeedRng(val)
  return val
end

--- New-game / post-title init: timer seed + wild stream from Random().
function Rng.seedNewGame(opts)
  local trainerId = Rng.seedFromTimer(opts)
  Rng.SeedWildEncounterRng(Rng.Random())
  return trainerId
end

--- Sync module state into a game3 session table for save.
function Rng.captureToSession(session)
  if type(session) ~= "table" then return end
  session.rng = Rng.getState()
end

--- Restore from session (Continue). Missing fields leave current state.
function Rng.restoreFromSession(session)
  if type(session) ~= "table" or type(session.rng) ~= "table" then
    return false
  end
  Rng.setState(session.rng)
  return true
end

return Rng
