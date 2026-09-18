-- Extract FRLG flag and var constants, new game reset states, and badge mappings
-- from pret pokefirered headers into Lua tables.

local FlagsExtract = {}

local function strip_comments(val)
  return val:gsub("/%*.-%*/", ""):gsub("//.*$", ""):gsub("%s+$", "")
end

local function parse_header_files(files)
  local raw_defs = {}
  local order = {}
  for _, filepath in ipairs(files) do
    local f = io.open(filepath, "r")
    if f then
      for line in f:lines() do
        local name, val = line:match("^%s*#define%s+([%w_]+)%s+(.+)%s*$")
        if name and val then
          val = strip_comments(val)
          if not raw_defs[name] then
            order[#order + 1] = name
          end
          raw_defs[name] = val
        end
      end
      f:close()
    end
  end

  local evaluated = {}
  local function eval_val(val, depth)
    depth = depth or 0
    if depth > 30 then return nil end
    val = val:gsub("%s+", "")
    local n = tonumber(val)
    if n then return n end
    local changed = true
    local expr = val
    while changed do
      changed = false
      expr = expr:gsub("([%a_][%w_]*)", function(id)
        if evaluated[id] ~= nil then
          changed = true
          return tostring(evaluated[id])
        elseif raw_defs[id] then
          local v = eval_val(raw_defs[id], depth + 1)
          if v ~= nil then
            evaluated[id] = v
            changed = true
            return tostring(v)
          end
        end
        return id
      end)
    end
    local chunk = loadstring("return " .. expr)
    if chunk then
      local ok, res = pcall(chunk)
      if ok and type(res) == "number" then
        return res
      end
    end
    return nil
  end

  for _, name in ipairs(order) do
    local val = eval_val(raw_defs[name])
    if val ~= nil then
      evaluated[name] = val
    end
  end
  return evaluated, order
end

local function parse_reset_script(filepath, flags_map, vars_map)
  local f = io.open(filepath, "r")
  if not f then return {}, {} end
  local in_reset = false
  local hide_flags = {}
  local set_vars = {}
  for line in f:lines() do
    if line:find("^EventScript_ResetAllMapFlags::") then
      in_reset = true
    elseif in_reset then
      if line:find("^%s*end") then
        break
      end
      local flag = line:match("^%s*setflag%s+([%w_]+)")
      if flag then
        local id = flags_map[flag]
        if id then
          hide_flags[#hide_flags + 1] = { name = flag, id = id }
        end
      end
      local var, val = line:match("^%s*setvar%s+([%w_]+)%s*,%s*(%d+)")
      if var and val then
        local id = vars_map[var]
        if id then
          set_vars[#set_vars + 1] = { name = var, id = id, value = tonumber(val) }
        end
      end
    end
  end
  f:close()
  return hide_flags, set_vars
end

function FlagsExtract.extract(opts)
  opts = opts or {}
  local root = opts.root or "pokefirered"

  local flag_headers = {
    root .. "/include/constants/opponents.h",
    root .. "/include/constants/trainers.h",
    root .. "/include/constants/flags.h",
  }
  local var_headers = {
    root .. "/include/constants/vars.h",
  }

  local raw_flags_map, flag_names = parse_header_files(flag_headers)
  local raw_vars_map, var_names = parse_header_files(var_headers)
  local hide_flags, reset_vars = parse_reset_script(root .. "/data/event_scripts.s", raw_flags_map, raw_vars_map)

  local flags_map = {}
  local flags_by_id = {}
  for _, name in ipairs(flag_names) do
    local id = raw_flags_map[name]
    if id and (name:find("^FLAG_") or name:find("FLAGS") or name == "NUM_BADGES") then
      flags_map[name] = id
      if not flags_by_id[id] and name:find("^FLAG_") then
        flags_by_id[id] = name
      end
    end
  end

  local vars_map = {}
  local vars_by_id = {}
  for _, name in ipairs(var_names) do
    local id = raw_vars_map[name]
    if id and (name:find("^VAR_") or name:find("VARS")) then
      vars_map[name] = id
      if not vars_by_id[id] and name:find("^VAR_") then
        vars_by_id[id] = name
      end
    end
  end

  local badges = {
    { num = 1, flag = flags_map.FLAG_BADGE01_GET or 0x820, name = "BOULDER", gym = "PEWTER", fieldMove = "FLASH" },
    { num = 2, flag = flags_map.FLAG_BADGE02_GET or 0x821, name = "CASCADE", gym = "CERULEAN", fieldMove = "CUT" },
    { num = 3, flag = flags_map.FLAG_BADGE03_GET or 0x822, name = "THUNDER", gym = "VERMILION", fieldMove = "FLY" },
    { num = 4, flag = flags_map.FLAG_BADGE04_GET or 0x823, name = "RAINBOW", gym = "CELADON", fieldMove = "STRENGTH" },
    { num = 5, flag = flags_map.FLAG_BADGE05_GET or 0x824, name = "SOUL", gym = "FUCHSIA", fieldMove = "SURF" },
    { num = 6, flag = flags_map.FLAG_BADGE06_GET or 0x825, name = "MARSH", gym = "SAFFRON", fieldMove = "ROCK_SMASH" },
    { num = 7, flag = flags_map.FLAG_BADGE07_GET or 0x826, name = "VOLCANO", gym = "CINNABAR", fieldMove = "WATERFALL" },
    { num = 8, flag = flags_map.FLAG_BADGE08_GET or 0x827, name = "EARTH", gym = "VIRIDIAN", fieldMove = "DIVE" },
  }

  local new_game_hide_ids = {}
  for _, hf in ipairs(hide_flags) do
    new_game_hide_ids[#new_game_hide_ids + 1] = hf.id
  end

  return {
    flags = flags_map,
    flagsById = flags_by_id,
    vars = vars_map,
    varsById = vars_by_id,
    newGameHideFlags = new_game_hide_ids,
    newGameResetList = hide_flags,
    newGameResetVars = reset_vars,
    badges = badges,
  }
end

function FlagsExtract.generateLuaSource(data)
  local lines = {}
  lines[#lines + 1] = "-- Auto-generated from pret/pokefirered constants. DO NOT EDIT DIRECTLY."
  lines[#lines + 1] = "local FlagsTable = {}"
  lines[#lines + 1] = ""
  lines[#lines + 1] = "FlagsTable.FLAGS = {"

  local flag_keys = {}
  for k in pairs(data.flags) do flag_keys[#flag_keys + 1] = k end
  table.sort(flag_keys)
  for _, k in ipairs(flag_keys) do
    local v = data.flags[k]
    lines[#lines + 1] = string.format("  %s = 0x%X,", k, v)
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""

  lines[#lines + 1] = "FlagsTable.FLAGS_BY_ID = {"
  local flag_ids = {}
  for id in pairs(data.flagsById) do flag_ids[#flag_ids + 1] = id end
  table.sort(flag_ids)
  for _, id in ipairs(flag_ids) do
    lines[#lines + 1] = string.format("  [0x%X] = %q,", id, data.flagsById[id])
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""

  lines[#lines + 1] = "FlagsTable.VARS = {"
  local var_keys = {}
  for k in pairs(data.vars) do var_keys[#var_keys + 1] = k end
  table.sort(var_keys)
  for _, k in ipairs(var_keys) do
    local v = data.vars[k]
    lines[#lines + 1] = string.format("  %s = 0x%X,", k, v)
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""

  lines[#lines + 1] = "FlagsTable.VARS_BY_ID = {"
  local var_ids = {}
  for id in pairs(data.varsById) do var_ids[#var_ids + 1] = id end
  table.sort(var_ids)
  for _, id in ipairs(var_ids) do
    lines[#lines + 1] = string.format("  [0x%X] = %q,", id, data.varsById[id])
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""

  lines[#lines + 1] = "FlagsTable.NEW_GAME_HIDE_FLAGS = {"
  for _, id in ipairs(data.newGameHideFlags) do
    local name = data.flagsById[id] or "UNKNOWN"
    lines[#lines + 1] = string.format("  0x%03X, -- %s (%d)", id, name, id)
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""

  lines[#lines + 1] = "FlagsTable.NEW_GAME_RESET_VARS = {"
  for _, v in ipairs(data.newGameResetVars) do
    lines[#lines + 1] = string.format("  { id = 0x%X, value = %d, name = %q },", v.id, v.value, v.name)
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""

  lines[#lines + 1] = "FlagsTable.BADGES = {"
  for _, b in ipairs(data.badges) do
    lines[#lines + 1] = string.format(
      "  { num = %d, flag = 0x%X, name = %q, gym = %q, fieldMove = %q },",
      b.num, b.flag, b.name, b.gym, b.fieldMove
    )
  end
  lines[#lines + 1] = "}"
  lines[#lines + 1] = ""

  lines[#lines + 1] = "return FlagsTable"
  lines[#lines + 1] = ""
  return table.concat(lines, "\n")
end

function FlagsExtract.write(cache, root, data)
  data = data or FlagsExtract.extract()
  -- A release does not ship a pret checkout. Keep the bundled definitions
  -- when optional headers are absent; never rewrite engine source on import.
  if not next(data.flags or {}) or not next(data.vars or {}) then
    local bundled = require("src.core.game3.scripting.flags_table")
    data = {
      flags = bundled.FLAGS, flagsById = bundled.FLAGS_BY_ID,
      vars = bundled.VARS, varsById = bundled.VARS_BY_ID,
      newGameHideFlags = bundled.NEW_GAME_HIDE_FLAGS,
      newGameResetVars = bundled.NEW_GAME_RESET_VARS, badges = bundled.BADGES,
    }
  end
  local src = FlagsExtract.generateLuaSource(data)
  if cache and cache.write then
    cache:write((root or "data/generated/gba") .. "/flags_table.lua", src)
  end
  return true
end

return FlagsExtract
