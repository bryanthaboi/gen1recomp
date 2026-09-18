-- Disassemble FRLG script bytecode into command rows.

local Opcodes = require("src.core.game3.scripting.opcodes")

local Disasm = {}

local function u8(bytes, i)
  return bytes[i] or 0, i + 1
end

local function u16(bytes, i)
  local lo = bytes[i] or 0
  local hi = bytes[i + 1] or 0
  return lo + hi * 256, i + 2
end

local function u32(bytes, i)
  local a, b, c, d = bytes[i] or 0, bytes[i + 1] or 0, bytes[i + 2] or 0, bytes[i + 3] or 0
  return a + b * 256 + c * 65536 + d * 16777216, i + 4
end

--- Decode one command at offset. Returns row, nextIndex (1-based).
function Disasm.decodeOne(bytes, i)
  local opb
  opb, i = u8(bytes, i)
  local def = Opcodes.get(opb)
  if not def then
    return { op = "unknown", byte = opb }, i
  end
  local row = { op = def.name, opcode = opb }
  if def.name == "trainerbattle" then
    -- Variable-length (pret asm/macros/event.inc trainerbattle).
    -- Layout: type u8, trainer u16, local_id/flags u16, then type-dependent ptrs.
    local TRAINER_BATTLE_SINGLE = 0
    local TRAINER_BATTLE_CONTINUE_SCRIPT_NO_MUSIC = 1
    local TRAINER_BATTLE_CONTINUE_SCRIPT = 2
    local TRAINER_BATTLE_SINGLE_NO_INTRO_TEXT = 3
    local TRAINER_BATTLE_DOUBLE = 4
    local TRAINER_BATTLE_REMATCH = 5
    local TRAINER_BATTLE_CONTINUE_SCRIPT_DOUBLE = 6
    local TRAINER_BATTLE_REMATCH_DOUBLE = 7
    local TRAINER_BATTLE_CONTINUE_SCRIPT_DOUBLE_NO_MUSIC = 8
    local TRAINER_BATTLE_EARLY_RIVAL = 9

    local typ
    typ, i = u8(bytes, i)
    local trainer
    trainer, i = u16(bytes, i)
    local localId
    localId, i = u16(bytes, i)
    row.type = typ
    row.trainer = trainer
    row.localId = localId
    row[1] = trainer
    row[2] = localId

    local function read_ptr()
      local v
      v, i = u32(bytes, i)
      return v
    end

    if typ == TRAINER_BATTLE_SINGLE or typ == TRAINER_BATTLE_REMATCH then
      row.introText = read_ptr()
      row.defeatText = read_ptr()
    elseif typ == TRAINER_BATTLE_CONTINUE_SCRIPT
        or typ == TRAINER_BATTLE_CONTINUE_SCRIPT_NO_MUSIC then
      row.introText = read_ptr()
      row.defeatText = read_ptr()
      row.eventScript = read_ptr()
    elseif typ == TRAINER_BATTLE_SINGLE_NO_INTRO_TEXT then
      row.defeatText = read_ptr()
    elseif typ == TRAINER_BATTLE_DOUBLE or typ == TRAINER_BATTLE_REMATCH_DOUBLE then
      row.introText = read_ptr()
      row.defeatText = read_ptr()
      row.notEnoughText = read_ptr()
    elseif typ == TRAINER_BATTLE_CONTINUE_SCRIPT_DOUBLE
        or typ == TRAINER_BATTLE_CONTINUE_SCRIPT_DOUBLE_NO_MUSIC then
      row.introText = read_ptr()
      row.defeatText = read_ptr()
      row.notEnoughText = read_ptr()
      row.eventScript = read_ptr()
    elseif typ == TRAINER_BATTLE_EARLY_RIVAL then
      -- localId slot is rival flags; texts are defeat then victory.
      row.flags = localId
      row.defeatText = read_ptr()
      row.victoryText = read_ptr()
    else
      -- Unknown type: don't consume further; mark opaque so extract can stop.
      row.opaque = true
    end
    return row, i
  end
  for _, a in ipairs(def.args) do
    if a.kind == "byte" then
      local v
      v, i = u8(bytes, i)
      row[#row + 1] = v
    elseif a.kind == "half" then
      local v
      v, i = u16(bytes, i)
      row[#row + 1] = v
    elseif a.kind == "word" then
      local v
      v, i = u32(bytes, i)
      row[#row + 1] = v
    end
  end
  -- Named fields for common Tier A ops.
  if def.name == "loadword" then
    row.dest, row.value = row[1], row[2]
  elseif def.name == "callstd" or def.name == "gotostd" then
    row.std = row[1]
  elseif def.name == "setvar" or def.name == "compare_var_to_value" then
    row.var, row.value = row[1], row[2]
  elseif def.name == "setflag" or def.name == "clearflag" or def.name == "checkflag" then
    row.flag = row[1]
  elseif def.name == "goto" or def.name == "call" then
    row.target = row[1]
  elseif def.name == "goto_if" or def.name == "call_if" then
    row.cond, row.target = row[1], row[2]
  elseif def.name == "applymovement" then
    row.localId, row.movement = row[1], row[2]
  elseif def.name == "waitmovement" or def.name == "removeobject" or def.name == "addobject" then
    row.localId = row[1]
  elseif def.name == "message" then
    row.ptr = row[1]
  elseif def.name == "callnative" or def.name == "gotonative" then
    row.fn = row[1]
  elseif def.name == "special" then
    row.id = row[1]
  elseif def.name == "textcolor" then
    row.color = row[1]
  elseif def.name == "setworldmapflag" then
    row.flag = row[1]
  elseif def.name:find("^buffer", 1, true) then
    row.dest = row[1]
    row.src = row[2]
  end
  return row, i
end

--- Linear disasm until `end`/`return` or maxBytes.
function Disasm.decode(bytes, start, maxBytes)
  start = start or 1
  maxBytes = maxBytes or #bytes
  local rows = {}
  local i = start
  local limit = math.min(#bytes + 1, start + maxBytes)
  while i < limit do
    local row
    row, i = Disasm.decodeOne(bytes, i)
    rows[#rows + 1] = row
    if row.op == "end" or row.op == "return" or row.op == "unknown" then
      break
    end
  end
  return rows
end

--- Read movement stream until (and including) step_end 0xFE.
function Disasm.decodeMovement(bytes, start)
  start = start or 1
  local out = {}
  local i = start
  while i <= #bytes do
    local b = bytes[i]
    out[#out + 1] = b
    i = i + 1
    if b == Opcodes.STEP_END then break end
  end
  return out
end

--- Encode a small subset of Tier A command rows back to bytes (for tests).
function Disasm.encodeSimple(rows)
  local out = {}
  local function push(...)
    for j = 1, select("#", ...) do out[#out + 1] = select(j, ...) end
  end
  local function half(v)
    v = v % 65536
    push(v % 256, math.floor(v / 256))
  end
  local function word(v)
    v = v % 4294967296
    push(v % 256, math.floor(v / 256) % 256,
      math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256)
  end
  for _, row in ipairs(rows) do
    local name = row.op
    local found
    for byte, def in pairs(Opcodes.TABLE) do
      if def.name == name then found = byte; break end
    end
    if not found then error("unknown op " .. tostring(name)) end
    push(found)
    if name == "loadword" then
      push(row.dest or row[1] or 0)
      word(row.value or row[2] or 0)
    elseif name == "callstd" or name == "gotostd" then
      push(row.std or row[1] or 0)
    elseif name == "setvar" or name == "compare_var_to_value" then
      half(row.var or row[1] or 0)
      half(row.value or row[2] or 0)
    elseif name == "setflag" or name == "clearflag" or name == "checkflag"
        or name == "setworldmapflag" then
      half(row.flag or row[1] or 0)
    elseif name == "goto" or name == "call" then
      word(row.target or row[1] or 0)
    elseif name == "goto_if" or name == "call_if" then
      push(row.cond or row[1] or 0)
      word(row.target or row[2] or 0)
    elseif name == "applymovement" then
      half(row.localId or row[1] or 0)
      word(row.movement or row[2] or 0)
    elseif name == "waitmovement" or name == "removeobject" or name == "addobject" then
      half(row.localId or row[1] or 0)
    elseif name == "turnobject" then
      half(row.localId or row[1] or 0)
      push(row.direction or row[2] or 0)
    elseif name == "message" then
      word(row.ptr or row[1] or 0)
    elseif name == "callnative" then
      word(row.fn or row[1] or 0)
    elseif name == "special" then
      half(row.id or row[1] or 0)
    elseif name == "textcolor" then
      push(row.color or row[1] or 0)
    elseif name == "bufferspeciesname" or name == "bufferitemname"
        or name == "buffernumberstring" or name == "bufferstdstring"
        or name == "bufferpartymonnick" or name == "buffermovename"
        or name == "bufferdecorationname" then
      push(row.dest or row[1] or 0)
      half(row.src or row[2] or 0)
    elseif name == "bufferleadmonspeciesname" then
      push(row.dest or row[1] or 0)
    elseif name == "bufferstring" then
      push(row.dest or row[1] or 0)
      word(row.src or row[2] or 0)
    end
    -- zero-arg ops: end, lock, release, faceplayer, …
  end
  return out
end

return Disasm
