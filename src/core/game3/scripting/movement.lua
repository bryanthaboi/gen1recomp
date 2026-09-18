-- Async movement tracker + FRLG movement-action decode.
-- activeMoves[localId]; done on step_end 0xFE. LocalId 0xFF = player.

local Opcodes = require("src.core.game3.scripting.opcodes")

local Movement = {}

Movement.LOCALID_PLAYER = Opcodes.LOCALID_PLAYER
Movement.STEP_END = Opcodes.STEP_END

-- FRLG MOVEMENT_ACTION_* names used by curated fallback content / tests.
Movement.CMD = {
  FACE_DOWN = 0x00,
  FACE_UP = 0x01,
  FACE_LEFT = 0x02,
  FACE_RIGHT = 0x03,
  WALK_SLOWER_DOWN = 0x08,
  WALK_SLOWER_UP = 0x09,
  WALK_SLOWER_LEFT = 0x0A,
  WALK_SLOWER_RIGHT = 0x0B,
  WALK_SLOW_DOWN = 0x0C,
  WALK_SLOW_UP = 0x0D,
  WALK_SLOW_LEFT = 0x0E,
  WALK_SLOW_RIGHT = 0x0F,
  WALK_DOWN = 0x10, -- WALK_NORMAL_*
  WALK_UP = 0x11,
  WALK_LEFT = 0x12,
  WALK_RIGHT = 0x13,
  DELAY_16 = 0x1C,
  WALK_FAST_DOWN = 0x1D,
  WALK_FAST_UP = 0x1E,
  WALK_FAST_LEFT = 0x1F,
  WALK_FAST_RIGHT = 0x20,
  SET_INVISIBLE = 0x60,
  SET_VISIBLE = 0x61,
  EMOTE_EXCLAMATION = 0x62,
  EMOTE_QUESTION = 0x63,
  EMOTE_X = 0x64,
  EMOTE_DOUBLE_EXCLAMATION = 0x65,
  EMOTE_SMILE = 0x66,
  STEP_END = 0xFE,
}

local DIR = { [0] = "down", [1] = "up", [2] = "left", [3] = "right" }

-- FRLG MOVEMENT_ACTION_* (include/constants/event_object_movement.h).
-- Older Emerald-ish 0x08 walk_normal tables are wrong for FireRed.
function Movement.decodeAction(b)
  b = tonumber(b) or 0
  if b == Movement.STEP_END or b == 0xFF then
    return { kind = "end" }
  end
  if b <= 0x07 then
    return { kind = "turn", dir = DIR[b % 4] }
  end
  -- Walk slower / slow / normal (0x08–0x13): four dirs each.
  if b >= 0x08 and b <= 0x13 then
    return { kind = "step", dir = DIR[(b - 0x08) % 4] }
  end
  -- Delay 1 / 2 / 4 / 8 / 16 frames (scaled up for host step rate).
  if b >= 0x18 and b <= 0x1C then
    local frames = ({ [0x18] = 2, [0x19] = 4, [0x1A] = 8, [0x1B] = 16, [0x1C] = 32 })[b]
    return { kind = "sleep", frames = frames or 8 }
  end
  -- Walk fast / in-place / faster walks → step or turn-in-place.
  if b >= 0x1D and b <= 0x20 then
    return { kind = "step", dir = DIR[b - 0x1D] }
  end
  if b >= 0x21 and b <= 0x30 then
    return { kind = "turn", dir = DIR[(b - 0x21) % 4] }
  end
  if b >= 0x35 and b <= 0x38 then
    return { kind = "step", dir = DIR[b - 0x35] }
  end
  if b >= 0x39 and b <= 0x3C then
    return { kind = "step", dir = DIR[b - 0x39] }
  end
  if b == 0x60 then return { kind = "hide" } end
  if b == 0x61 then return { kind = "show" } end
  -- Emotes: 60 frames animation in pokefirered (sAnimCmd_ExclamationMark1 etc.)
  if b == 0x62 then return { kind = "emote", emoteType = "exclamation", frames = 60 } end
  if b == 0x63 then return { kind = "emote", emoteType = "question", frames = 60 } end
  if b == 0x64 then return { kind = "emote", emoteType = "x", frames = 60 } end
  if b == 0x65 then return { kind = "emote", emoteType = "double_exclamation", frames = 60 } end
  if b == 0x66 then return { kind = "emote", emoteType = "smile", frames = 60 } end
  -- MOVEMENT_ACTION_NURSE_JOY_BOW_DOWN (0x5B): ANIM_NURSE_BOW ≈ 48 frames.
  if b == 0x5B then
    return { kind = "bow", frames = 48 }
  end
  return { kind = "nop" }
end

function Movement.actionsFromBytes(bytes)
  local out = {}
  if type(bytes) ~= "table" then return out end
  for i = 1, #bytes do
    local act = Movement.decodeAction(bytes[i])
    if act.kind == "end" then break end
    if act.kind ~= "nop" then out[#out + 1] = act end
  end
  return out
end

function Movement.start(ctx, localId, bytes, adapters)
  localId = tonumber(localId) or 0
  local stream = bytes
  if type(bytes) == "string" then
    stream = adapters and adapters.lookupMovement and adapters.lookupMovement(bytes)
  end
  if type(stream) ~= "table" then
    stream = { Movement.STEP_END }
  end
  local entry = {
    bytes = stream,
    index = 1,
    done = false,
    hostHandle = nil,
  }
  ctx.activeMoves[localId] = entry
  if adapters and adapters.applyMovement then
    entry.hostHandle = adapters.applyMovement(localId, stream, function()
      entry.done = true
    end)
  else
    -- Instant-complete stub (unit tests / no host).
    for i = 1, #stream do
      if stream[i] == Movement.STEP_END then
        entry.done = true
        break
      end
    end
    if not entry.done and #stream == 0 then entry.done = true end
  end
  return entry
end

function Movement.tick(ctx, adapters)
  for localId, entry in pairs(ctx.activeMoves) do
    if not entry.done and adapters and adapters.pollMovement then
      if adapters.pollMovement(localId, entry) then
        entry.done = true
      end
    end
  end
end

function Movement.isDone(ctx, localId)
  localId = tonumber(localId) or 0
  -- waitmovement 0 waits for all
  if localId == 0 then
    for _, entry in pairs(ctx.activeMoves) do
      if not entry.done then return false end
    end
    return true
  end
  local entry = ctx.activeMoves[localId]
  if not entry then return true end
  return entry.done == true
end

--- Drop finished tracks so the next waitmovement 0 is not confused by leftovers.
function Movement.pruneDone(ctx)
  if not ctx or not ctx.activeMoves then return end
  local keep = {}
  for lid, entry in pairs(ctx.activeMoves) do
    if entry and not entry.done then
      keep[lid] = entry
    end
  end
  ctx.activeMoves = keep
end

function Movement.makePoll(ctx, localId, adapters)
  return function()
    Movement.tick(ctx, adapters)
    local done = Movement.isDone(ctx, localId)
    if done then Movement.pruneDone(ctx) end
    return done
  end
end

--- Ensure extracted movement ends with 0xFE (include terminator).
function Movement.ensureTerminated(bytes)
  local out = {}
  for i = 1, #bytes do
    out[i] = bytes[i]
    if bytes[i] == Movement.STEP_END then
      return out
    end
  end
  out[#out + 1] = Movement.STEP_END
  return out
end

return Movement
