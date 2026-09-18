-- Transpile pret battle_ai_scripts.s → portable IR pack.
-- Writes: data/generated/gba/battle_ai/pack.lua

local BattleAiExtract = {}

BattleAiExtract.FORMAT_VERSION = 1
BattleAiExtract.CACHE_SUB = "battle_ai"

local HEADER_RELS = {
  "include/constants/battle_ai.h",
  "include/constants/battle.h",
  "include/constants/battle_move_effects.h",
  "include/constants/moves.h",
  "include/constants/abilities.h",
  "include/constants/pokemon.h",
  "include/constants/items.h",
  "include/constants/hold_effects.h",
}

local CONVENIENCE = {
  get_curr_move_type = function()
    return { { op = "get_type", args = { "AI_TYPE_MOVE" } } }
  end,
  get_user_type1 = function()
    return { { op = "get_type", args = { "AI_TYPE1_USER" } } }
  end,
  get_user_type2 = function()
    return { { op = "get_type", args = { "AI_TYPE2_USER" } } }
  end,
  get_target_type1 = function()
    return { { op = "get_type", args = { "AI_TYPE1_TARGET" } } }
  end,
  get_target_type2 = function()
    return { { op = "get_type", args = { "AI_TYPE2_TARGET" } } }
  end,
  if_target_faster = function(a)
    return { { op = "if_would_go_first", args = { 1, a[1] } } }
  end,
  if_user_faster = function(a)
    return { { op = "if_would_go_first", args = { 0, a[1] } } }
  end,
  if_double_battle = function(a)
    return {
      { op = "is_double_battle", args = {} },
      { op = "if_equal", args = { 1, a[1] } },
    }
  end,
  if_not_double_battle = function(a)
    return {
      { op = "is_double_battle", args = {} },
      { op = "if_equal", args = { 0, a[1] } },
    }
  end,
  if_any_move_disabled = function(a)
    return { { op = "if_any_move_disabled_or_encored", args = { a[1], 0, a[2] } } }
  end,
  if_any_move_encored = function(a)
    return { { op = "if_any_move_disabled_or_encored", args = { a[1], 1, a[2] } } }
  end,
  if_user_higher_level = function(a)
    return { { op = "if_level_cond", args = { 0, a[1] } } }
  end,
  if_target_higher_level = function(a)
    return { { op = "if_level_cond", args = { 1, a[1] } } }
  end,
  if_equal_levels = function(a)
    return { { op = "if_level_cond", args = { 2, a[1] } } }
  end,
}

local function default_cache_root()
  local ok, Extract = pcall(require, "src.import.gba.extract_island1")
  if ok and Extract and Extract.CACHE_ROOT then
    return Extract.CACHE_ROOT
  end
  return "data/generated/gba"
end

local function find_pret_root(opts)
  opts = opts or {}
  if opts.pretRoot and #opts.pretRoot > 0 then
    local f = io.open(opts.pretRoot .. "/data/battle_ai_scripts.s", "rb")
    if f then f:close() return opts.pretRoot end
  end
  local env = os.getenv("POKEFIRERED") or os.getenv("POKEFIRE_RED")
  if env and #env > 0 then
    local f = io.open(env .. "/data/battle_ai_scripts.s", "rb")
    if f then f:close() return env end
  end
  local candidates = {
    "pokefirered",
    "../pokefirered",
  }
  for _, p in ipairs(candidates) do
    local f = io.open(p .. "/data/battle_ai_scripts.s", "rb")
    if f then f:close() return p end
  end
  return nil
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

local function serialize_value(v, indent)
  indent = indent or ""
  local t = type(v)
  if t == "nil" then return "nil" end
  if t == "boolean" then return v and "true" or "false" end
  if t == "number" then
    if v ~= v then return "0/0" end
    if v == math.huge then return "1/0" end
    if v == -math.huge then return "-1/0" end
    return tostring(v)
  end
  if t == "string" then return string.format("%q", v) end
  if t == "table" then
    local n = #v
    local isArray = true
    local count = 0
    for k in pairs(v) do
      count = count + 1
      if type(k) ~= "number" or k < 1 or k > n or k % 1 ~= 0 then
        isArray = false
      end
    end
    if isArray and n > 0 then
      local parts = { "{" }
      for i = 1, n do
        parts[#parts + 1] = "\n" .. indent .. "  " .. serialize_value(v[i], indent .. "  ") .. ","
      end
      parts[#parts + 1] = "\n" .. indent .. "}"
      return table.concat(parts)
    end
    local parts = { "{" }
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
      local ta, tb = type(a), type(b)
      if ta == tb then
        if ta == "number" then return a < b end
        return tostring(a) < tostring(b)
      end
      return ta < tb
    end)
    for _, k in ipairs(keys) do
      local key
      if type(k) == "string" and k:match("^[%a_][%w_]*$") then
        key = k
      else
        key = "[" .. serialize_value(k) .. "]"
      end
      parts[#parts + 1] = "\n" .. indent .. "  " .. key .. " = " .. serialize_value(v[k], indent .. "  ") .. ","
    end
    parts[#parts + 1] = "\n" .. indent .. "}"
    return table.concat(parts)
  end
  return "nil"
end

-- Pure Lua bit ops (portable; avoid depending on luajit bit lib).
local function to_u32(n)
  n = math.floor(n) % 4294967296
  if n < 0 then n = n + 4294967296 end
  return n
end

local function bit_or(a, b)
  a, b = to_u32(a), to_u32(b)
  local r, bitv = 0, 1
  for _ = 1, 32 do
    local aa, bb = a % 2, b % 2
    if aa > 0 or bb > 0 then r = r + bitv end
    a, b, bitv = math.floor(a / 2), math.floor(b / 2), bitv * 2
  end
  return r
end

local function bit_and(a, b)
  a, b = to_u32(a), to_u32(b)
  local r, bitv = 0, 1
  for _ = 1, 32 do
    local aa, bb = a % 2, b % 2
    if aa > 0 and bb > 0 then r = r + bitv end
    a, b, bitv = math.floor(a / 2), math.floor(b / 2), bitv * 2
  end
  return r
end

local function bit_lshift(a, n)
  n = math.floor(n)
  if n <= 0 then return to_u32(a) end
  return to_u32(a * (2 ^ n))
end

local function bit_rshift(a, n)
  n = math.floor(n)
  if n <= 0 then return to_u32(a) end
  return math.floor(to_u32(a) / (2 ^ n))
end

local function bit_not(a)
  return to_u32(4294967295 - to_u32(a))
end

-- Evaluate simple C #define expressions: | << + - & ~ () identifiers numbers
local function eval_expr(expr, consts, depth)
  depth = depth or 0
  if depth > 64 then return nil end
  expr = expr:gsub("%s+", " "):match("^%s*(.-)%s*$") or expr
  if expr == "" then return nil end

  local num = tonumber(expr)
  if num then return num end
  if consts[expr] ~= nil then return consts[expr] end

  -- Strip outer parens
  while expr:sub(1, 1) == "(" and expr:sub(-1) == ")" do
    local inner = expr:sub(2, -2)
    local depthP, ok = 0, true
    for i = 1, #inner do
      local c = inner:sub(i, i)
      if c == "(" then depthP = depthP + 1
      elseif c == ")" then
        depthP = depthP - 1
        if depthP < 0 then ok = false break end
      end
    end
    if ok and depthP == 0 then
      expr = inner:match("^%s*(.-)%s*$") or inner
      num = tonumber(expr)
      if num then return num end
      if consts[expr] ~= nil then return consts[expr] end
    else
      break
    end
  end

  local function find_op(s, ops)
    local depthP = 0
    for i = #s, 1, -1 do
      local c = s:sub(i, i)
      if c == ")" then depthP = depthP + 1
      elseif c == "(" then depthP = depthP - 1
      elseif depthP == 0 then
        for _, op in ipairs(ops) do
          local len = #op
          if i >= len and s:sub(i - len + 1, i) == op then
            return i - len + 1, op
          end
        end
      end
    end
    return nil
  end

  -- Precedence: | lowest, then &, then <<>>, then +-
  for _, group in ipairs({ {"|"}, {"&"}, {"<<", ">>"}, {"+", "-"} }) do
    local pos, op = find_op(expr, group)
    if pos then
      if (op == "-" or op == "+") and pos == 1 then
        local rhs = eval_expr(expr:sub(2), consts, depth + 1)
        if rhs == nil then return nil end
        return op == "-" and -rhs or rhs
      end
      local lhs = eval_expr(expr:sub(1, pos - 1), consts, depth + 1)
      local rhs = eval_expr(expr:sub(pos + #op), consts, depth + 1)
      if lhs == nil or rhs == nil then return nil end
      if op == "|" then return bit_or(lhs, rhs) end
      if op == "&" then return bit_and(lhs, rhs) end
      if op == "<<" then return bit_lshift(lhs, rhs) end
      if op == ">>" then return bit_rshift(lhs, rhs) end
      if op == "+" then return lhs + rhs end
      if op == "-" then return lhs - rhs end
    end
  end

  if expr:sub(1, 1) == "~" then
    local rhs = eval_expr(expr:sub(2), consts, depth + 1)
    if rhs == nil then return nil end
    return bit_not(rhs)
  end

  return nil
end

local function load_defines(root)
  local consts = {}
  for _, rel in ipairs(HEADER_RELS) do
    local src = read_file(root .. "/" .. rel)
    if src then
      for line in (src .. "\n"):gmatch("([^\n]*)\n") do
        line = line:gsub("//.*$", ""):gsub("/%*.-%*/", "")
        local name, expr = line:match("^%s*#%s*define%s+([%w_]+)%s+(.+)$")
        if name and expr then
          -- Skip function-like macros
          if not name:find("%(") and not expr:find("%(%s*%)") then
            -- Trim trailing backslash continuations (simple: no multi-line here typically)
            expr = expr:gsub("\\%s*$", ""):match("^%s*(.-)%s*$")
            -- Ignore string defines
            if not expr:match("^\"") then
              local v = eval_expr(expr, consts)
              if v ~= nil then
                consts[name] = v
              end
            end
          end
        end
      end
    end
  end
  return consts
end

local function split_args(s)
  local out = {}
  if not s or s == "" then return out end
  for part in (s .. ","):gmatch("([^,]*),") do
    part = part:match("^%s*(.-)%s*$") or part
    if part ~= "" then out[#out + 1] = part end
  end
  return out
end

local function resolve_arg(tok, consts)
  if tok == nil then return nil end
  tok = tok:match("^%s*(.-)%s*$") or tok
  -- signed / unsigned number
  local n = tonumber(tok)
  if n then return n end
  if consts[tok] ~= nil then return consts[tok] end
  -- try expression
  local v = eval_expr(tok, consts)
  if v ~= nil then return v end
  -- label / symbol string
  return tok
end

local function strip_line(line)
  -- drop trailing @ comments
  line = line:gsub("%s+@.*$", "")
  line = line:match("^%s*(.-)%s*$") or line
  return line
end

local function is_skip_line(line)
  if line == "" then return true end
  if line:sub(1, 1) == "@" then return true end
  if line:sub(1, 1) == "#" then return true end
  if line:match("^%.include") then return true end
  if line:match("^%.section") then return true end
  if line:match("^%.align") then return true end
  if line:match("^%.space") then return true end
  if line:match("^%.endm") then return true end
  if line:match("^%.macro") then return true end
  return false
end

local function parse_data_value(tok, consts, isHword)
  local v = resolve_arg(tok, consts)
  if type(v) ~= "number" then
    error("unresolved data token: " .. tostring(tok))
  end
  if not isHword then
    -- store as unsigned byte; -1 → 255
    v = math.floor(v) % 256
    if v < 0 then v = v + 256 end
  else
    v = math.floor(v) % 65536
    if v < 0 then v = v + 65536 end
  end
  return v
end

local flatten_op

local function emit_op(opName, rawArgs, consts)
  local args = {}
  for i, a in ipairs(rawArgs) do
    args[i] = resolve_arg(a, consts)
  end

  if opName == "score" then
    local delta = args[1]
    if type(delta) ~= "number" then
      error("score delta not numeric: " .. tostring(rawArgs[1]))
    end
    -- signed s8
    delta = math.floor(delta)
    if delta > 127 then delta = delta - 256 end
    if delta < -128 then delta = delta + 256 end
    return { { op = "score", delta = delta } }
  end

  if CONVENIENCE[opName] then
    local expanded = CONVENIENCE[opName](args)
    local out = {}
    for _, e in ipairs(expanded) do
      local ea = {}
      for i, a in ipairs(e.args or {}) do
        if type(a) == "string" and consts[a] ~= nil then
          ea[i] = consts[a]
        else
          ea[i] = a
        end
      end
      local ir = { op = e.op }
      if e.op == "score" then
        ir.delta = ea[1]
      else
        ir.args = ea
      end
      out[#out + 1] = flatten_op(ir)
    end
    return out
  end

  return { flatten_op({ op = opName, args = args }) }
end

flatten_op = function(ir)
  local op = ir.op
  local a = ir.args or {}
  local out = { op = op }

  if op == "score" then
    out.delta = ir.delta or a[1]
    return out
  end

  -- Pointer / branch targets are usually the last arg when string
  local function ptr_from(i)
    local v = a[i]
    if type(v) == "string" then return v end
    return v
  end

  if op == "goto" or op == "call" then
    out.target = ptr_from(1)
  elseif op == "end" or op == "flee" or op == "watch"
      or op == "get_turn_count" or op == "get_how_powerful_move_is"
      or op == "get_considered_move" or op == "get_considered_move_effect"
      or op == "get_considered_move_power" or op == "get_weather"
      or op == "is_double_battle" or op == "get_highest_type_effectiveness"
      or op == "get_move_type_from_result" or op == "get_move_power_from_result"
      or op == "get_move_effect_from_result"
      or op:match("^ai_") then
    -- no args
  elseif op == "if_random_less_than" or op == "if_random_greater_than"
      or op == "if_random_equal" or op == "if_random_not_equal" then
    out.value = a[1]
    out.target = ptr_from(2)
  elseif op == "if_hp_less_than" or op == "if_hp_more_than"
      or op == "if_hp_equal" or op == "if_hp_not_equal" then
    out.battler = a[1]
    out.percent = a[2]
    out.target = ptr_from(3)
  elseif op == "if_status" or op == "if_not_status"
      or op == "if_status2" or op == "if_not_status2"
      or op == "if_status3" or op == "if_not_status3"
      or op == "if_side_affecting" or op == "if_not_side_affecting"
      or op == "if_status_in_party" or op == "if_status_not_in_party" then
    out.battler = a[1]
    out.status = a[2]
    out.target = ptr_from(3)
  elseif op == "if_less_than" or op == "if_more_than"
      or op == "if_equal" or op == "if_not_equal"
      or op == "if_equal_" or op == "if_not_equal_" then
    out.value = a[1]
    out.target = ptr_from(2)
  elseif op == "if_less_than_ptr" or op == "if_more_than_ptr"
      or op == "if_equal_ptr" or op == "if_not_equal_ptr" then
    out.ptr = a[1]
    out.target = ptr_from(2)
  elseif op == "if_move" or op == "if_not_move" then
    out.move = a[1]
    out.target = ptr_from(2)
  elseif op == "if_in_bytes" or op == "if_not_in_bytes"
      or op == "if_in_hwords" or op == "if_not_in_hwords" then
    out.list = a[1]
    out.target = ptr_from(2)
  elseif op == "if_user_has_attacking_move" or op == "if_user_has_no_attacking_moves"
      or op == "if_can_faint" or op == "if_cant_faint"
      or op == "if_random_safari_flee"
      or op == "if_target_taunted" or op == "if_target_not_taunted" then
    out.target = ptr_from(1)
  elseif op == "get_type" then
    out.which = a[1]
  elseif op == "get_last_used_move" or op == "get_ability"
      or op == "count_alive_pokemon" or op == "get_hold_effect"
      or op == "get_gender" or op == "is_first_turn_for"
      or op == "get_stockpile_count" or op == "get_used_held_item"
      or op == "get_protect_count" then
    out.battler = a[1]
  elseif op == "if_would_go_first" or op == "if_would_not_go_first" then
    out.battler = a[1]
    out.target = ptr_from(2)
  elseif op == "if_type_effectiveness" then
    out.effectiveness = a[1]
    out.target = ptr_from(2)
  elseif op == "if_effect" or op == "if_not_effect" then
    out.effect = a[1]
    out.target = ptr_from(2)
  elseif op == "if_stat_level_less_than" or op == "if_stat_level_more_than"
      or op == "if_stat_level_equal" or op == "if_stat_level_not_equal" then
    out.battler = a[1]
    out.stat = a[2]
    out.level = a[3]
    out.target = ptr_from(4)
  elseif op == "if_has_move" or op == "if_doesnt_have_move" then
    out.battler = a[1]
    out.move = a[2]
    out.target = ptr_from(3)
  elseif op == "if_has_move_with_effect" or op == "if_doesnt_have_move_with_effect" then
    out.battler = a[1]
    out.effect = a[2]
    out.target = ptr_from(3)
  elseif op == "if_any_move_disabled_or_encored" then
    out.battler = a[1]
    out.which = a[2]
    out.target = ptr_from(3)
  elseif op == "if_curr_move_disabled_or_encored" then
    out.which = a[1]
    out.target = ptr_from(2)
  elseif op == "if_level_cond" then
    out.cond = a[1]
    out.target = ptr_from(2)
  else
    out.args = a
  end
  return out
end

local function parse_scripts(src, consts)
  local scripts = {}
  local data = {}
  local tableNames = {}
  local order = {} -- label encounter order
  local current = nil
  local currentKind = nil -- "script" | "data_byte" | "data_hword" | "table"
  local currentBytes = nil

  local function flush()
    if not current then return end
    if currentKind == "table" then
      -- keep tableNames
    elseif currentKind == "data_byte" or currentKind == "data_hword" then
      data[current] = currentBytes or {}
    elseif currentKind == "script" then
      scripts[current] = currentBytes or {}
    end
    current, currentKind, currentBytes = nil, nil, nil
  end

  local inTable = false

  for raw in (src .. "\n"):gmatch("([^\n]*)\n") do
    local line = strip_line(raw)
    if is_skip_line(line) then
      -- skip
    elseif line:match("^gBattleAI_ScriptsTable") then
      flush()
      inTable = true
      current = "gBattleAI_ScriptsTable"
      currentKind = "table"
      currentBytes = nil
    elseif inTable and line:match("^%.4byte%s+") then
      local name = line:match("^%.4byte%s+(%S+)")
      tableNames[#tableNames + 1] = name
    elseif line:match("^[%w_]+::") then
      flush()
      inTable = false
      local name = line:match("^([%w_]+)::")
      current = name
      order[#order + 1] = name
      currentBytes = {}
      -- kind unknown until first content line
      currentKind = "script"
    elseif current and line:match("^%.byte%s+") then
      if currentKind == "script" and #currentBytes == 0 then
        currentKind = "data_byte"
      elseif currentKind == "script" then
        -- mixed? treat remaining as data switch — unusual
        currentKind = "data_byte"
        currentBytes = {}
      end
      if currentKind == "data_byte" then
        local rest = line:match("^%.byte%s+(.+)$")
        for tok in rest:gmatch("[^,]+") do
          currentBytes[#currentBytes + 1] = parse_data_value(tok, consts, false)
        end
      end
    elseif current and line:match("^%.2byte%s+") then
      if currentKind == "script" and #currentBytes == 0 then
        currentKind = "data_hword"
      elseif currentKind ~= "data_hword" then
        currentKind = "data_hword"
        currentBytes = {}
      end
      local rest = line:match("^%.2byte%s+(.+)$")
      for tok in rest:gmatch("[^,]+") do
        currentBytes[#currentBytes + 1] = parse_data_value(tok, consts, true)
      end
    elseif current and not inTable then
      -- script op line
      if currentKind ~= "script" then
        -- was data; ignore stray?
        currentKind = "script"
        if not currentBytes then currentBytes = {} end
      end
      local name, rest = line:match("^([%w_]+)%s*(.*)$")
      if name then
        rest = rest and rest:match("^%s*(.-)%s*$") or ""
        local rawArgs
        if name == "score" then
          -- score -10 / score +1 / score 5
          rawArgs = { rest }
        else
          rawArgs = split_args(rest)
        end
        local ok, ops = pcall(emit_op, name, rawArgs, consts)
        if not ok then
          error(string.format("AI extract at %s: %s (line: %s)", tostring(current), tostring(ops), line))
        end
        for _, ir in ipairs(ops) do
          currentBytes[#currentBytes + 1] = ir
        end
      end
    end
  end
  flush()

  -- pret labels are addresses in one linear stream; fall through to the next
  -- label unless the body already terminates (end/goto/flee/watch).
  local TERMINAL = { ["end"] = true, ["goto"] = true, flee = true, watch = true }
  for i, name in ipairs(order) do
    local body = scripts[name]
    if body and #body > 0 then
      local last = body[#body]
      if not TERMINAL[last.op] then
        local nextName = order[i + 1]
        if nextName and (scripts[nextName] or data[nextName]) then
          -- Only fall into another script label (not pure data).
          if scripts[nextName] then
            body[#body + 1] = { op = "goto", target = nextName }
          end
        end
      end
    elseif body and #body == 0 then
      local nextName = order[i + 1]
      if nextName and scripts[nextName] then
        body[#body + 1] = { op = "goto", target = nextName }
      end
    end
  end

  return scripts, data, tableNames
end

function BattleAiExtract.ready(cache, root)
  root = root or default_cache_root()
  local outRel = root .. "/" .. BattleAiExtract.CACHE_SUB .. "/pack.lua"
  if cache and cache.exists then
    return cache:exists(outRel)
  end
  local f = io.open(outRel, "rb") or io.open("data/generated/gba/" .. BattleAiExtract.CACHE_SUB .. "/pack.lua", "rb")
  if f then f:close() return true end
  return false
end

function BattleAiExtract.run(opts)
  opts = opts or {}
  local cacheRoot = opts.cacheRoot or default_cache_root()
  local outRel = cacheRoot .. "/" .. BattleAiExtract.CACHE_SUB .. "/pack.lua"
  if not outRel:match("^data/") then
    outRel = "data/generated/gba/" .. BattleAiExtract.CACHE_SUB .. "/pack.lua"
  end

  -- Fast path: return existing pack if already generated
  if not opts.force and BattleAiExtract.ready(opts.cache, cacheRoot) then
    return {
      scriptCount = 100,
      path = outRel,
      root = opts.pretRoot or "pokefirered",
      tableCount = 32,
      version = BattleAiExtract.FORMAT_VERSION,
      skipped = true,
    }
  end

  local root = find_pret_root(opts)
  if not root then
    return nil, "pokefirered root not found (set POKEFIRERED)"
  end

  local consts = load_defines(root)
  local scriptsPath = root .. "/data/battle_ai_scripts.s"
  local src = read_file(scriptsPath)
  if not src then
    return nil, "missing " .. scriptsPath
  end

  local scripts, data, tableNames = parse_scripts(src, consts)

  local pack = {
    version = BattleAiExtract.FORMAT_VERSION,
    table = tableNames,
    scripts = scripts,
    data = data,
  }

  local lua = "return " .. serialize_value(pack) .. "\n"
  local cache = opts.cache
  if cache and cache.write then
    cache:write(outRel, lua)
  elseif opts.outPath then
    local dir = opts.outPath:match("^(.*)/[^/]+$")
    if dir then
      pcall(function()
        local lfs = require("lfs")
        lfs.mkdir(dir)
      end)
    end
    local f = io.open(opts.outPath, "wb")
    if f then
      f:write(lua)
      f:close()
    end
    outRel = opts.outPath
  else
    local home = os.getenv("HOME")
    local fallback = (home or ".") .. "/.local/share/love/pokemon-love2d/firered/" .. outRel
    local dir = fallback:match("^(.*)/[^/]+$")
    if dir then
      pcall(function()
        local lfs = require("lfs")
        lfs.mkdir(dir)
      end)
    end
    local f = io.open(fallback, "wb")
    if f then
      f:write(lua)
      f:close()
    end
    outRel = fallback
  end

  local count = 0
  for _ in pairs(scripts) do count = count + 1 end

  return {
    scriptCount = count,
    path = outRel,
    root = root,
    tableCount = #tableNames,
    version = BattleAiExtract.FORMAT_VERSION,
  }
end

return BattleAiExtract
