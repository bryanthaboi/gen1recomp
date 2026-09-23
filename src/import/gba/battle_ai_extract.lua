-- src/battle_ai_script_commands.c:147, data/battle_ai_scripts.s:17

local Versions = require("src.import.gba.versions")

local BattleAiExtract = {}

BattleAiExtract.FORMAT_VERSION = 2
BattleAiExtract.CACHE_SUB = "battle_ai"
BattleAiExtract.FILE = "pack.lua"

local B, S, H, W, P, L, LH = "b", "s", "h", "w", "p", "l", "lh"

-- asm/macros/battle_ai_script.inc:1
local OPS = {
  [0x00] = { "if_random_less_than", { "value", B }, { "target", P } },
  [0x01] = { "if_random_greater_than", { "value", B }, { "target", P } },
  -- src/battle_ai_script_commands.c:509
  [0x02] = { "if_random_equal", { "value", B }, { "target", P } },
  [0x03] = { "if_random_not_equal", { "value", B }, { "target", P } },
  [0x04] = { "score", { "delta", S } },
  [0x05] = { "if_hp_less_than", { "battler", B }, { "percent", B }, { "target", P } },
  [0x06] = { "if_hp_more_than", { "battler", B }, { "percent", B }, { "target", P } },
  [0x07] = { "if_hp_equal", { "battler", B }, { "percent", B }, { "target", P } },
  [0x08] = { "if_hp_not_equal", { "battler", B }, { "percent", B }, { "target", P } },
  [0x09] = { "if_status", { "battler", B }, { "status", W }, { "target", P } },
  [0x0A] = { "if_not_status", { "battler", B }, { "status", W }, { "target", P } },
  [0x0B] = { "if_status2", { "battler", B }, { "status", W }, { "target", P } },
  [0x0C] = { "if_not_status2", { "battler", B }, { "status", W }, { "target", P } },
  [0x0D] = { "if_status3", { "battler", B }, { "status", W }, { "target", P } },
  [0x0E] = { "if_not_status3", { "battler", B }, { "status", W }, { "target", P } },
  [0x0F] = { "if_side_affecting", { "battler", B }, { "status", W }, { "target", P } },
  [0x10] = { "if_not_side_affecting", { "battler", B }, { "status", W }, { "target", P } },
  [0x11] = { "if_less_than", { "value", B }, { "target", P } },
  [0x12] = { "if_more_than", { "value", B }, { "target", P } },
  [0x13] = { "if_equal", { "value", B }, { "target", P } },
  [0x14] = { "if_not_equal", { "value", B }, { "target", P } },
  [0x15] = { "if_less_than_ptr", { "ptr", W }, { "target", P } },
  [0x16] = { "if_more_than_ptr", { "ptr", W }, { "target", P } },
  [0x17] = { "if_equal_ptr", { "ptr", W }, { "target", P } },
  [0x18] = { "if_not_equal_ptr", { "ptr", W }, { "target", P } },
  [0x19] = { "if_move", { "move", H }, { "target", P } },
  [0x1A] = { "if_not_move", { "move", H }, { "target", P } },
  [0x1B] = { "if_in_bytes", { "list", L }, { "target", P } },
  [0x1C] = { "if_not_in_bytes", { "list", L }, { "target", P } },
  [0x1D] = { "if_in_hwords", { "list", LH }, { "target", P } },
  [0x1E] = { "if_not_in_hwords", { "list", LH }, { "target", P } },
  [0x1F] = { "if_user_has_attacking_move", { "target", P } },
  [0x20] = { "if_user_has_no_attacking_moves", { "target", P } },
  [0x21] = { "get_turn_count" },
  [0x22] = { "get_type", { "which", B } },
  [0x23] = { "get_considered_move_power" },
  [0x24] = { "get_how_powerful_move_is" },
  [0x25] = { "get_last_used_move", { "battler", B } },
  [0x26] = { "if_equal_", { "value", B }, { "target", P } },
  [0x27] = { "if_not_equal_", { "value", B }, { "target", P } },
  [0x28] = { "if_would_go_first", { "battler", B }, { "target", P } },
  [0x29] = { "if_would_not_go_first", { "battler", B }, { "target", P } },
  [0x2A] = { "ai_2a" },
  [0x2B] = { "ai_2b" },
  [0x2C] = { "count_alive_pokemon", { "battler", B } },
  [0x2D] = { "get_considered_move" },
  [0x2E] = { "get_considered_move_effect" },
  [0x2F] = { "get_ability", { "battler", B } },
  [0x30] = { "get_highest_type_effectiveness" },
  [0x31] = { "if_type_effectiveness", { "effectiveness", B }, { "target", P } },
  [0x32] = { "ai_32" },
  [0x33] = { "ai_33" },
  [0x34] = { "if_status_in_party", { "battler", B }, { "status", W }, { "target", P } },
  [0x35] = { "if_status_not_in_party", { "battler", B }, { "status", W }, { "target", P } },
  [0x36] = { "get_weather" },
  [0x37] = { "if_effect", { "effect", B }, { "target", P } },
  [0x38] = { "if_not_effect", { "effect", B }, { "target", P } },
  [0x39] = { "if_stat_level_less_than", { "battler", B }, { "stat", B }, { "level", B }, { "target", P } },
  [0x3A] = { "if_stat_level_more_than", { "battler", B }, { "stat", B }, { "level", B }, { "target", P } },
  [0x3B] = { "if_stat_level_equal", { "battler", B }, { "stat", B }, { "level", B }, { "target", P } },
  [0x3C] = { "if_stat_level_not_equal", { "battler", B }, { "stat", B }, { "level", B }, { "target", P } },
  [0x3D] = { "if_can_faint", { "target", P } },
  [0x3E] = { "if_cant_faint", { "target", P } },
  [0x3F] = { "if_has_move", { "battler", B }, { "move", H }, { "target", P } },
  [0x40] = { "if_doesnt_have_move", { "battler", B }, { "move", H }, { "target", P } },
  [0x41] = { "if_has_move_with_effect", { "battler", B }, { "effect", B }, { "target", P } },
  [0x42] = { "if_doesnt_have_move_with_effect", { "battler", B }, { "effect", B }, { "target", P } },
  [0x43] = { "if_any_move_disabled_or_encored", { "battler", B }, { "which", B }, { "target", P } },
  [0x44] = { "if_curr_move_disabled_or_encored", { "battler", B }, { "target", P } },
  [0x45] = { "flee" },
  [0x46] = { "if_random_safari_flee", { "target", P } },
  [0x47] = { "watch" },
  [0x48] = { "get_hold_effect", { "battler", B } },
  [0x49] = { "get_gender", { "battler", B } },
  [0x4A] = { "is_first_turn_for", { "battler", B } },
  [0x4B] = { "get_stockpile_count", { "battler", B } },
  [0x4C] = { "is_double_battle" },
  [0x4D] = { "get_used_held_item", { "battler", B } },
  [0x4E] = { "get_move_type_from_result" },
  [0x4F] = { "get_move_power_from_result" },
  [0x50] = { "get_move_effect_from_result" },
  [0x51] = { "get_protect_count", { "battler", B } },
  [0x52] = { "ai_52" },
  [0x53] = { "ai_53" },
  [0x54] = { "ai_54" },
  [0x55] = { "ai_55" },
  [0x56] = { "ai_56" },
  [0x57] = { "ai_57" },
  [0x58] = { "call", { "target", P } },
  [0x59] = { "goto", { "target", P } },
  [0x5A] = { "end" },
  [0x5B] = { "if_level_cond", { "cond", B }, { "target", P } },
  [0x5C] = { "if_target_taunted", { "target", P } },
  [0x5D] = { "if_target_not_taunted", { "target", P } },
}
BattleAiExtract.OPS = OPS

local TERMINAL = { ["end"] = true, ["goto"] = true, flee = true, watch = true }

local function label(off)
  return string.format("0x%06X", off)
end

local function target_offset(rom, ptr, at)
  local off = rom:ptrOffset(ptr)
  if not off then
    error(string.format("battle_ai: bad pointer 0x%08X at 0x%06X", ptr, at))
  end
  return off
end

local function read_list(rom, off, hword)
  local out, i = {}, 0
  while true do
    local v = hword and rom:u16(off + i * 2) or rom:get(off + i)
    out[#out + 1] = v
    i = i + 1
    if v == (hword and 0xFFFF or 0xFF) then return out end
    if i > 512 then error(string.format("battle_ai: unterminated list at 0x%06X", off)) end
  end
end

local function decode_body(rom, start, queue, data)
  local body, off = {}, start
  while true do
    local opcode = rom:get(off)
    local spec = OPS[opcode]
    if not spec then
      error(string.format("battle_ai: unknown command 0x%02X at 0x%06X", opcode, off))
    end
    local ir = { op = spec[1] }
    local at = off + 1
    for i = 2, #spec do
      local field, kind = spec[i][1], spec[i][2]
      if kind == B then
        ir[field] = rom:get(at)
        at = at + 1
      elseif kind == S then
        local v = rom:get(at)
        ir[field] = v >= 128 and v - 256 or v
        at = at + 1
      elseif kind == H then
        ir[field] = rom:u16(at)
        at = at + 2
      elseif kind == W then
        ir[field] = rom:u32(at)
        at = at + 4
      elseif kind == P then
        local dest = target_offset(rom, rom:u32(at), at)
        ir[field] = label(dest)
        queue[#queue + 1] = dest
        at = at + 4
      else
        local dest = target_offset(rom, rom:u32(at), at)
        local name = label(dest)
        data[name] = data[name] or read_list(rom, dest, kind == LH)
        ir[field] = name
        at = at + 4
      end
    end
    body[#body + 1] = ir
    off = at
    if TERMINAL[ir.op] then return body end
  end
end

function BattleAiExtract.extract(rom)
  local scripts, data, tableNames, queue = {}, {}, {}, {}
  for i = 0, Versions.BATTLE_AI_SCRIPT_COUNT - 1 do
    local at = Versions.BATTLE_AI_SCRIPTS_TABLE + i * 4
    local entry = target_offset(rom, rom:u32(at), at)
    tableNames[i + 1] = label(entry)
    queue[#queue + 1] = entry
  end
  local head = 1
  while head <= #queue do
    local off = queue[head]
    head = head + 1
    local name = label(off)
    if not scripts[name] then
      scripts[name] = decode_body(rom, off, queue, data)
    end
  end
  return {
    version = BattleAiExtract.FORMAT_VERSION,
    table = tableNames,
    scripts = scripts,
    data = data,
  }
end

function BattleAiExtract.ready(cache, root)
  local rel = (root or "data/generated/gba") .. "/" .. BattleAiExtract.CACHE_SUB .. "/" .. BattleAiExtract.FILE
  return (cache and cache.exists and cache:exists(rel)) and true or false
end

function BattleAiExtract.run(rom, cache, opts)
  opts = opts or {}
  local serialize = require("src.import.gba.extract_scripts").serialize_lua
  local rel = (opts.cacheRoot or "data/generated/gba") .. "/" .. BattleAiExtract.CACHE_SUB
    .. "/" .. BattleAiExtract.FILE
  local pack = BattleAiExtract.extract(rom)
  cache:write(rel, "return " .. serialize(pack) .. "\n")
  local count = 0
  for _ in pairs(pack.scripts) do count = count + 1 end
  print(string.format("[battle_ai_extract] %d entry scripts, %d bodies -> %s",
    #pack.table, count, rel))
  return { path = rel, scriptCount = count, tableCount = #pack.table, pack = pack }
end

return BattleAiExtract
