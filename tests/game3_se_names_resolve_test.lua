#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path

local SE = require("src.core.game3.se_ids")
local Constants = require("src.core.game3.constants")
local GameVersion = require("src.core.GameVersion")

local ROOTS = { "src/core/game3", "src/ui/game3", "src/world/game3", "src/battle/game3", "src/core/Game3.lua" }
local SKIP = { "/constants/", "/syms/", "src/core/game3/se_ids%.lua$" }

local FILE_GAMES = {
  ["src/core/game3/battle/facility_arena.lua"] = { "emerald" },
  ["src/core/game3/rse/event_islands.lua"] = { "emerald" },
  ["src/ui/game3/rse/pokenav/call_window.lua"] = { "emerald" },
  ["src/ui/game3/rse/pokenav/match_call.lua"] = { "emerald" },
  ["src/core/game3/battle/level_up_streaks.lua"] = { "firered" },
  ["src/core/game3/ss_anne_cutscene.lua"] = { "firered" },
  ["src/ui/game3/bag_menu.lua"] = { "firered" },
  ["src/ui/game3/region_map.lua"] = { "firered" },
  ["src/ui/game3/slot_machine.lua"] = { "firered" },
  ["src/ui/game3/pokedex.lua"] = { "firered" },
  ["src/ui/game3/trainer_card.lua"] = { "firered", "emerald" },
}

local function path_games(path)
  if FILE_GAMES[path] then return FILE_GAMES[path] end
  if path:find("/rse/") or path:find("_rse[%._]") then return { "emerald", "ruby" } end
  if path:find("/rs/") or path:find("/rs[%._]") or path:find("_rs[%._]") then return { "ruby" } end
  if path:find("emerald") then return { "emerald" } end
  if path:find("firered") or path:find("leafgreen") or path:find("frlg") then return { "firered" } end
  if path:find("ruby") or path:find("sapphire") then return { "ruby" } end
  return nil
end

local function list_files()
  local out = {}
  local p = io.popen("find " .. table.concat(ROOTS, " ") .. " -type f -name '*.lua' | LC_ALL=C sort")
  for f in p:lines() do
    local skip = false
    for _, pat in ipairs(SKIP) do
      if f:find(pat) then skip = true end
    end
    if not skip then out[#out + 1] = f end
  end
  p:close()
  return out
end

local function strip_comment(line)
  if line:match("^%s*%-%-") then return "" end
  return (line:gsub("%-%-[^\"']*$", ""))
end

local sites = {}
local function add(file, ln, name, keyed)
  sites[#sites + 1] = { file = file, line = ln, name = name, keyed = keyed }
end

local tables = {}
local tableOrder = {}
local function add_keyed(file, tline, ln, key, name)
  local id = file .. ":" .. tline
  local t = tables[id]
  if not t then
    t = { file = file, line = tline, games = {} }
    tables[id] = t
    tableOrder[#tableOrder + 1] = id
  end
  t.games[Constants.gameKey(key)] = name or false
  if name then add(file, ln, name, Constants.gameKey(key)) end
end

for _, file in ipairs(list_files()) do
  local fh = assert(io.open(file, "rb"))
  local src = fh:read("*a")
  fh:close()
  local ln, tline = 0, 0
  for raw in (src .. "\n"):gmatch("(.-)\r?\n") do
    ln = ln + 1
    local line = strip_comment(raw)
    if line:match("=%s*{%s*$") then tline = ln end
    local fkey = line:match("^%s*([%a_][%w_]*)%s*=%s*false%s*,?%s*$")
    if fkey and Constants.GAMES[fkey] then add_keyed(file, tline, ln, fkey, nil) end
    for pos, name in line:gmatch("()[\"'](SE_[%w_]+)[\"']") do
      local key = line:sub(1, pos - 1):match("([%a_][%w_]*)%s*=%s*$")
      if key and Constants.GAMES[key] then
        add_keyed(file, tline, ln, key, name)
      else
        add(file, ln, name)
      end
    end
    for name in line:gmatch("SE%.(SE_[%w_]+)") do add(file, ln, name) end
    for name in line:gmatch("se_ids[\"']%)%.(SE_[%w_]+)") do add(file, ln, name) end
  end
end

local versions = {}
for _, id in ipairs(GameVersion.ORDER) do
  if Constants.GAMES[id] then versions[#versions + 1] = id end
end

local failures, checked, falseEntries = 0, 0, 0
local GAME_KEYS = {}
for _, id in ipairs(versions) do GAME_KEYS[Constants.gameKey(id)] = true end
for _, id in ipairs(tableOrder) do
  local t = tables[id]
  local games = path_games(t.file)
  local need = {}
  if games then
    for _, g in ipairs(games) do need[g] = true end
  else
    for g in pairs(GAME_KEYS) do need[g] = true end
  end
  for g in pairs(need) do
    checked = checked + 1
    local v = t.games[g]
    if v == nil then
      failures = failures + 1
      print(string.format("FAIL %s:%d per-game SE table has no %s entry", t.file, t.line, g))
    elseif v == false then
      falseEntries = falseEntries + 1
    end
  end
end

for _, version in ipairs(versions) do
  SE.select(version)
  local key = Constants.gameKey(version)
  for _, s in ipairs(sites) do
    local runs
    if s.keyed then
      runs = s.keyed == key
    else
      local games = path_games(s.file)
      runs = games == nil
      for _, g in ipairs(games or {}) do
        if g == key then runs = true end
      end
    end
    if runs then
      checked = checked + 1
      if SE[s.name] == nil then
        failures = failures + 1
        print(string.format("FAIL %s: %s:%d plays %s, which %s's songs.h does not define",
          version, s.file, s.line, s.name, key))
      end
    end
  end
end
SE.select("firered")

if checked < 500 then
  failures = failures + 1
  print("FAIL only " .. checked .. " SE literal checks ran; the source walk found too little")
end

if failures > 0 then
  print(string.format("%d unresolved SE names", failures))
  os.exit(1)
end
if falseEntries < 1 then
  print("FAIL no per-game `<game> = false` SE entry found; the table walk is broken")
  os.exit(1)
end
print(string.format("PASS every gen3 SE literal resolves in each version that runs it (%d checks, %d per-game tables, %d no-SE entries, %d versions)",
  checked, #tableOrder, falseEntries, #versions))
