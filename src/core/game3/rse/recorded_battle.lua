-- pokeemerald/src/recorded_battle.c: Frontier battle recording into the save
-- (Frontier Pass "record battle") and playback of the saved battle.
--
-- A recorded battle is plain data: the seed of a battle-local LCRNG, the
-- player and foe snapshots, and per-turn checkpoints of {rng state, final
-- actions}. Playback restores the checkpoint rng and replays the stored
-- actions instead of asking the UI or AI, so the battle replays the same way
-- regardless of frame timing (the global Rng stream steps every frame).
local Rng32 = require("src.core.game3.rng")
local SaveSections = require("src.core.game3.save_sections")

local RB = {}

-- pokeemerald/src/recorded_battle.c:189 RecordedBattle_SetBattlerAction keeps
-- only the battler action fields. The engine also reads the fields below, so
-- they are kept too. user is kept only as a side name; the engine re-attaches
-- live battler tables on replay from the battler id.
local ACT_FIELDS = { "kind", "move", "slot", "target", "battler", "item", "action", "itemId", "moveSlot",
  "partySlot", "usedInMenu", "forfeit", "locked" }
local ACT_TABLE_FIELDS = { "meta", "pokeblock" }

-- Plain-data copy: drops functions, userdata and cycles so a record can be
-- stored in the save without carrying live battle objects.
local function plain(v, seen)
  local t = type(v)
  if t == "number" or t == "string" or t == "boolean" then return v end
  if t ~= "table" then return nil end
  seen = seen or {}
  if seen[v] then return nil end
  seen[v] = true
  local out = {}
  for k, x in pairs(v) do
    local kt = type(k)
    if kt == "number" or kt == "string" then
      local c = plain(x, seen)
      if c ~= nil then out[k] = c end
    end
  end
  seen[v] = nil
  return out
end

-- exported so the battle bridge and tower can take the same plain copy
RB.plain = plain

local function actionOf(a)
  if type(a) ~= "table" then return nil end
  local out = {}
  for _, f in ipairs(ACT_FIELDS) do
    local x = a[f]
    if type(x) == "number" or type(x) == "string" or type(x) == "boolean" then out[f] = x end
  end
  if type(a.user) == "string" then out.user = a.user end
  for _, f in ipairs(ACT_TABLE_FIELDS) do
    if type(a[f]) == "table" then out[f] = plain(a[f]) end
  end
  return out
end

local function actsOf(acts)
  local out = {}
  for k, a in pairs(acts or {}) do out[k] = actionOf(a) end
  return out
end

-- pokefirered/include/random.h:19 ISO_RANDOMIZE1 (used at pokefirered/src/random.c:11),
-- constants as src/core/game3/rng.lua
local MULT, ADD = 1103515245, 24691
local U32 = 4294967296

function RB.newRng(seed)
  local state = math.floor(tonumber(seed) or 0) % U32
  local function word()
    state = (Rng32.mulU32(state, MULT) + ADD) % U32
    return math.floor(state / 65536) % 65536
  end
  -- same call shape as the battle rng (battle/state.lua:353): () -> [0,1),
  -- (n) -> 1..n, (lo, hi) -> lo..hi
  local fn = function(lo, hi)
    if lo == nil and hi == nil then return word() / 65536 end
    if hi == nil then
      lo = math.floor(tonumber(lo) or 1)
      if lo <= 0 then return 0 end
      return 1 + (word() % lo)
    end
    lo = math.floor(tonumber(lo) or 0)
    hi = math.floor(tonumber(hi) or lo)
    if hi < lo then lo, hi = hi, lo end
    local span = hi - lo + 1
    if span <= 0 then return lo end
    return lo + (word() % span)
  end
  local obj = { seed = state, fn = fn }
  function obj:getState() return state end
  function obj:setState(v)
    state = math.floor(tonumber(v) or 0) % U32
    return true
  end
  return obj
end

local function validTurn(t)
  return type(t) == "table" and type(t.rng) == "number" and type(t.acts) == "table"
end

local function validReplace(r)
  return type(r) == "table" and type(r.battler) == "number" and type(r.slot) == "number"
end

-- rejects a save whose record is missing fields or has malformed entries
local function validRecord(r)
  if type(r) ~= "table" then return false end
  if type(r.version) ~= "string" or r.version == "" then return false end
  if (tonumber(r.battleFlags) or 0) == 0 then return false end
  if type(r.seed) ~= "number" or type(r.turns) ~= "table" or next(r.turns) == nil then return false end
  for k, t in pairs(r.turns) do
    if type(k) ~= "number" or not validTurn(t) then return false end
  end
  if r.replaces ~= nil then
    if type(r.replaces) ~= "table" then return false end
    for _, x in ipairs(r.replaces) do
      if not validReplace(x) then return false end
    end
  end
  return true
end

-- start flags kept in a record; the live handles the bridge adds are not data
local START_OPT_HANDLES = { "recorder", "replay", "rng", "done", "session" }

local function startOptsOf(opts)
  local out = RB.plain(opts) or {}
  for _, k in ipairs(START_OPT_HANDLES) do out[k] = nil end
  return out
end

-- pokeemerald/src/recorded_battle.c:127 RecordedBattle_SetTrainerInfo and
-- :230 RecordedBattle_BufferNewBattlerData: start a record for one battle
function RB.beginRecording(sess, meta)
  meta = meta or {}
  -- seed from the global stream at battle start; the battle-local stream is
  -- then independent of the per-frame Rng.step
  local seed = Rng32.Random32()
  local rng = RB.newRng(seed)
  local version = sess and sess.version or require("src.core.game3.profile").active().id
  -- meta stays live: fields such as foe may be set after this call, and
  -- finish copies them then
  local rec = { rng = rng, meta = meta }
  local turns, replaces = {}, {}
  local foe, foeSet = nil, false
  local frozen = false

  -- the foe as actually fought, set after any trainer hook; overrides meta.foe
  function rec:setFoe(f)
    if frozen then return end
    foe, foeSet = RB.plain(f), true
  end

  -- one checkpoint per planned turn, taken before the engine plans it and
  -- after facility action overrides
  function rec:onTurn(turnNo, acts)
    if frozen then return end
    turns[turnNo] = { rng = rng:getState(), acts = actsOf(acts) }
  end

  -- faint replacements, in battle order
  function rec:onReplace(battlerId, slot)
    if frozen then return end
    replaces[#replaces + 1] = { battler = battlerId, slot = slot }
  end

  -- the record waits in RAM until the Frontier Pass copies it (SAVE_BATTLE);
  -- finishing freezes it so later callbacks cannot change it. A battle with no
  -- recorded turns leaves the previous pending record untouched.
  function rec:finish(s, result)
    frozen = true
    if next(turns) == nil then return nil end
    if result == "forfeited" then
      -- pokeemerald/src/battle_main.c:5062: a forfeited frontier battle is not recorded
      if s then require("src.core.game3.rse.frontier.util").frontier(s).disableRecordBattle = 1 end
      return nil
    end
    local record = {
      version = version,
      battleFlags = 1,
      seed = seed,
      kind = meta.kind,
      facility = meta.facility,
      lvlMode = meta.lvlMode,
      party = RB.plain(meta.party) or {},
      foe = foeSet and foe or RB.plain(meta.foe),
      startOpts = startOptsOf(meta.startOpts),
      turns = turns,
      replaces = replaces,
      result = result,
    }
    rec.record = record
    if s then s.pendingRecordedBattle = record end
    return record
  end

  return rec
end

-- playback side of beginRecording
function RB.beginReplay(record)
  local rng = RB.newRng(record.seed)
  local queues = {}
  for _, r in ipairs(record.replaces or {}) do
    local q = queues[r.battler] or {}
    queues[r.battler] = q
    q[#q + 1] = r.slot
  end
  local rep = { rng = rng, record = record }

  -- restores the checkpoint rng and returns the stored actions for the turn
  function rep:turn(turnNo)
    local t = record.turns[turnNo]
    if not t then return nil end
    rng:setState(t.rng)
    return actsOf(t.acts)
  end

  -- next faint replacement for this battler
  function rep:nextReplace(battlerId)
    local q = queues[battlerId]
    if not q or #q == 0 then return nil end
    return table.remove(q, 1)
  end

  return rep
end

-- pokeemerald/src/recorded_battle.c:286 CanCopyRecordedBattleSaveData
function RB.canCopy(s)
  return validRecord(s and s.recordedBattle)
end

-- pokeemerald/src/recorded_battle.c:319 MoveRecordedBattleToSaveData
function RB.moveToSaveData(s)
  local r = s and s.pendingRecordedBattle
  if not validRecord(r) then return false end
  s.recordedBattle = plain(r)
  return true
end

-- pokeemerald/src/recorded_battle.c:586 PlayRecordedBattle
-- onDone(result, err) runs exactly once: with the battle result when it ends,
-- or with nil and an error when playback cannot start
function RB.play(sess, onDone)
  local settled, starting, early = false, true, nil
  local function settle(result, err)
    if settled then return end
    settled = true
    if onDone then onDone(result, err) end
  end

  local record = sess and sess.recordedBattle
  if not validRecord(record) then
    settle(nil, "no recorded battle")
    return false
  end

  local function start()
    local rep = RB.beginReplay(record)
    local Runtime = require("src.core.game3.runtime")
    local BattleBridge = require("src.core.game3.battle_bridge")
    local opts = {}
    -- the recording's start flags, minus keys that play() or the bridge set itself
    local own = { done = true, rng = true, recorder = true, replay = true, session = true }
    for k, v in pairs(plain(record.startOpts) or {}) do
      if not own[k] then opts[k] = v end
    end
    opts.recordedParty = plain(record.party)
    opts.replay = rep
    opts.rng = rep.rng.fn
    opts.fade = false
    opts.done = function(result)
      -- the bridge reports a failed start through done before it returns, so
      -- hold that until the start call has returned
      if starting then
        early = { result = result }
        return
      end
      settle(result)
    end
    return BattleBridge.start(Runtime._mod, Runtime._game, plain(record.foe), opts)
  end

  local okCall, ok, err = pcall(start)
  starting = false
  if not okCall then
    settle(nil, tostring(ok))
    return false
  end
  if not ok then
    settle(nil, err or "battle start failed")
    return false
  end
  if early then settle(early.result) end
  return true
end

-- the record is a save section of its own
SaveSections.register("recordedBattle", SaveSections.fields({ "recordedBattle" }, function(s)
  s.recordedBattle = nil
end))

return RB
