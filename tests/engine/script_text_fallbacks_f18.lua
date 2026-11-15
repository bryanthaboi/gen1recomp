--   luajit tests/engine/script_text_fallbacks_f18.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")

local function readAll(p)
  local f = assert(io.open(p, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

local function listLua(dir)
  local out = {}
  local p = io.popen('find "' .. dir .. '" -name "*.lua" | sort')
  for line in p:lines() do out[#out + 1] = line end
  p:close()
  return out
end

local function lineOf(s, pos)
  local n = 1
  for _ in s:sub(1, pos - 1):gmatch("\n") do n = n + 1 end
  return n
end

local function stripComments(s)
  s = s:gsub("%-%-%[(=*)%[.-%]%1%]", function(c) return (c:gsub("[^\n]", " ")) end)
  local out = {}
  for line in (s .. "\n"):gmatch("(.-)\n") do
    local i, inStr = 1, nil
    local cut = #line + 1
    while i <= #line do
      local c = line:sub(i, i)
      if inStr then
        if c == "\\" then i = i + 1 elseif c == inStr then inStr = nil end
      elseif c == '"' or c == "'" then
        inStr = c
      elseif line:sub(i, i + 1) == "--" then
        cut = i
        break
      end
      i = i + 1
    end
    out[#out + 1] = line:sub(1, cut - 1) .. string.rep(" ", #line - cut + 1)
  end
  return table.concat(out, "\n")
end

local function isProse(val)
  return type(val) == "string" and val:find("%a%a") ~= nil
    and (val:find("%s") ~= nil or val:find("[!?.]$") ~= nil)
end

local function literalAt(s, q)
  local quote = s:sub(q, q)
  local i = q + 1
  while i <= #s do
    local c = s:sub(i, i)
    if c == "\\" then i = i + 2 elseif c == quote then break else i = i + 1 end
  end
  local lit = s:sub(q, i)
  local ok, val = pcall(function() return assert(loadstring("return " .. lit))() end)
  return ok and val or nil, i
end

local hits = {}
local function hit(file, s, pos, what)
  hits[#hits + 1] = ("%s:%d %s"):format(file, lineOf(s, pos), what)
end

local LOOKUP_ENDS = {
  "[Tt]ext%s*%[[^%]]*%]%s*$", "%f[%w_]t%s*%[[^%]]*%]%s*$",
  "[Tt]ext%s*%.%s*_[%w_]+%s*$", "%f[%w_]t%._[%w_]+%s*$",
}
local function endsInLookup(before)
  for _, pat in ipairs(LOOKUP_ENDS) do
    if before:find(pat) then return true end
  end
  return false
end

local function scan(file, raw)
  local s = stripComments(raw)
  local pos = 1
  while true do
    local a, e = s:find("%f[%w]or%s*%(?%s*[\"']", pos)
    if not a then break end
    local val, stop = literalAt(s, e)
    if isProse(val) then
      hit(file, s, a, "or <prose literal>")
    elseif type(val) == "string" and not val:find("^_%u") and not val:find("^TEXT_") then
      local before = s:sub(math.max(1, a - 160), a - 1)
      local lineStart = before:match(".*\n()") or 1
      local line = before:sub(lineStart)
      if endsInLookup(before) then
        hit(file, s, a, "text lookup or <literal>")
      elseif line:find("TextBox%.new%s*%(") or line:find("show_text") then
        hit(file, s, a, "text box argument or <literal>")
      end
    end
    pos = stop + 1
  end
  pos = 1
  while true do
    local a, e = s:find("%f[%w]or%s*%(?%s*Strings%s*%(", pos)
    if not a then break end
    local before = s:sub(math.max(1, a - 120), a - 1)
    if before:find("%._[%w_]+%s*%)?%s*$") or before:find("[Tt]ext%s*%[[^%]]*%]%s*%)?%s*$")
       or before:find("raw%s*$") then
      hit(file, s, a, "or Strings(...)")
    end
    pos = e + 1
  end
  for _, pat in ipairs({ "%f[%w_][%w_]*[Ff]allback%f[^%w_]", "%f[%w_]fb%f[^%w_]" }) do
    pos = 1
    while true do
      local a, e = s:find(pat, pos)
      if not a then break end
      hit(file, s, a, "fallback parameter " .. s:sub(a, e))
      pos = e + 1
    end
  end
  pos = 1
  while true do
    local a, e = s:find("data%.text%s+or%s+{%s*}", pos)
    if not a then break end
    hit(file, s, a, "data.text or {}")
    pos = e + 1
  end
  pos = 1
  while true do
    local a, e, name = s:find("%f[%w]or%s*%(?%s*([%a_][%w_%.]*)", pos)
    if not a then break end
    local before = s:sub(math.max(1, a - 160), a - 1)
    local after = s:sub(e + 1, e + 2)
    if endsInLookup(before) and name ~= "nil" and name ~= "false" and name ~= "Strings"
       and not name:find("^[Tt]ext$") and not name:find("^t$")
       and not (name:find("^[Tt]ext%.") or name:find("^t%.")) and not after:find("^%s*%[") then
      hit(file, s, a, "text lookup or variable " .. name)
    end
    pos = e + 1
  end
  pos = 1
  while true do
    local a, e, name = s:find("%f[%w]if%s+not%s+([%a_][%w_%.%[%]\"']*)%s+then%s", pos)
    if not a then break end
    local body = s:sub(e + 1, e + 240)
    local plain = name:gsub("%p", "%%%0")
    local _, ae = body:find("^%s*" .. plain .. "%s*=%s*")
    if ae then
      local rest = body:sub(ae + 1)
      if rest:find("^[\"']") or rest:find("^%[%[") or rest:find("^Strings%s*%(") then
        hit(file, s, a, "if not " .. name .. " then <literal>")
      end
    end
    pos = e + 1
  end
end

local files = listLua("data/scripts")
files[#files + 1] = "src/script/Commands.lua"
for _, file in ipairs(files) do scan(file, readAll(file)) end

for _, h in ipairs(hits) do print("  " .. h) end
T.eq(#hits, 0, "no hand-typed text fallbacks in Gen 1 scripts")

local probes = {
  { 'local s = t[label] or default\n', "variable after a text lookup" },
  { 'local s = data.text._FooText or msg\n', "variable after a dotted text lookup" },
  { 'local s = text[id]\nif not s then s = "Hello there!" end\n', "if not s then <prose>" },
  { 'local s = text[id]\nif not s then\n  s = Strings("OK")\nend\n', "if not s then Strings(...)" },
  { 'local s = text[id]\nif not s then s = "" end\n', "if not s then empty literal" },
}
for _, probe in ipairs(probes) do
  local before = #hits
  scan("probe", probe[1])
  T.check(#hits > before, "scanner catches " .. probe[2])
  for i = #hits, before + 1, -1 do hits[i] = nil end
end
local cleanBefore = #hits
scan("probe", 'local s = text[a] or text[b]\nlocal u = t[x] or nil\nif not s then s = text._Other end\n')
T.eq(#hits - cleanBefore, 0, "scanner leaves label-to-label lookups alone")

love = love or require("tests.love_stub")
package.loaded["src.render.TextBox"] = {
  new = function(_, text) return { text = text } end,
  substitute = function(_, text) return text end,
}
local Commands = require("src.script.Commands")
local shown
local ctx = {
  game = { data = { text = { _Known = "known{DONE}" } },
           stack = { push = function(_, box) shown = box end } },
  runner = { yield = function() end, resume = function() end },
}
local okKnown, errKnown = pcall(Commands.show_text, ctx, "_Known")
T.check(okKnown, "show_text prints a cached label: " .. tostring(errKnown))
shown = nil
local ok = pcall(Commands.show_text, ctx, "_NotARealLabel")
T.check(not ok and shown == nil, "show_text errors on an unknown label")

for _, literal in ipairs({ "Thanks", "......", "...", "OK", "Zzz", "PIKACHU", "42" }) do
  shown = nil
  local okLit, errLit = pcall(Commands.show_text, ctx, Commands.modText(literal))
  T.check(okLit and shown and shown.text == literal, "mod show_text prints literal " .. literal .. ": " .. tostring(errLit))
  shown = nil
  local okAsk, errAsk = pcall(Commands.ask, ctx, Commands.modText(literal))
  T.check(okAsk and shown and shown.text == literal, "mod ask prints literal " .. literal .. ": " .. tostring(errAsk))
  ctx.endBattleText = nil
  local okEnd, errEnd = pcall(Commands.save_end_battle_text, ctx, Commands.modText(literal))
  T.check(okEnd and ctx.endBattleText == literal, "mod save_end_battle_text arms literal " .. literal .. ": " .. tostring(errEnd))
  shown = nil
  local okRaw, errRaw = pcall(Commands.show_text, ctx, literal)
  T.check(okRaw and shown and shown.text == literal, "unattributed show_text prints " .. literal .. ": " .. tostring(errRaw))
  shown = nil
  local okRawAsk, errRawAsk = pcall(Commands.ask, ctx, literal)
  T.check(okRawAsk and shown and shown.text == literal, "unattributed ask prints " .. literal .. ": " .. tostring(errRawAsk))
  ctx.endBattleText = nil
  local okRawEnd, errRawEnd = pcall(Commands.save_end_battle_text, ctx, literal)
  T.check(okRawEnd and ctx.endBattleText == literal,
    "unattributed save_end_battle_text arms " .. literal .. ": " .. tostring(errRawEnd))
end

for _, id in ipairs({ "_NotARealLabel", "TEXT_NOT_REAL", "NotARealText", "NotARealText3", "NotARealString",
                      "Foo.bar", "TradeCanceledTypo" }) do
  shown = nil
  T.check(not pcall(Commands.show_text, ctx, id) and shown == nil, "pret-shaped id " .. id .. " stays strict")
  T.check(not pcall(Commands.save_end_battle_text, ctx, id), "pret-shaped id " .. id .. " stays strict for save_end_battle_text")
end
for _, lit in ipairs({ "OK", "Thanks", "...", "PIKACHU", "Zzz", "42", "Hello!", "Text me", "BROCK", "Pikachu" }) do
  T.check(not Commands.isTextLabel(lit), "common literal " .. lit .. " is not label-shaped")
end

do
  local WorldAPI = require("src.world.WorldAPI")
  local ScriptRunner = require("src.script.ScriptRunner")
  local boxes = {}
  package.loaded["src.render.TextBox"].new = function(_, text, done)
    local b = { text = text, done = done } boxes[#boxes + 1] = b return b
  end
  local game = { data = { text = {}, resolveText = function() return nil end },
                 save = { flags = {} }, stack = { states = {} } }
  function game.stack:push(s) self.states[#self.states + 1] = s end
  local ow = { isOverworld = true, map = { id = "PROBE_MAP", def = { label = "ProbeMap" } }, scriptMoves = {} }
  ow.runner = ScriptRunner.new(game, ow)
  game.stack.states[1] = ow
  game.overworld = ow
  local queued = WorldAPI.new(game, "probe_mod"):queueScript({ { "show_text", "OK" }, { "set_flag", "PROBE_AFTER" } })
  local first = boxes[1] and boxes[1].text
  if boxes[1] then boxes[1].done() end
  T.check(queued and first == "OK" and game.save.flags.PROBE_AFTER == true,
    "api 2 mod.world:queueScript show_text OK prints and the next row runs")
  package.loaded["src.render.TextBox"].new = function(_, text) return { text = text } end
end

local saveRoots = {
  (os.getenv("HOME") or "") .. "/Library/Application Support/LOVE/",
  (os.getenv("XDG_DATA_HOME") or ((os.getenv("HOME") or "") .. "/.local/share")) .. "/love/",
}
for _, v in ipairs({ "red", "blue", "yellow" }) do
  local cached
  for _, root in ipairs(saveRoots) do
    local okLoad, t = pcall(dofile, root .. "g1r-" .. v .. "/" .. v .. "/data/generated/text.lua")
    if okLoad and type(t) == "table" then cached = t break end
  end
  if not cached then
    print("[skip] no g1r-" .. v .. " text cache")
  else
    local odd, n = {}, 0
    for k in pairs(cached) do
      n = n + 1
      if not Commands.isTextLabel(k) then odd[#odd + 1] = k end
    end
    table.sort(odd)
    T.check(n > 0 and #odd == 0, ("every %s text label is label-shaped (%d labels, odd: %s)"):format(
      v, n, table.concat(odd, " ")))
  end
end
shown = nil
pcall(Commands.show_text, ctx, Commands.modText("_Known"))
T.eq(shown and shown.text, "known{DONE}", "mod show_text still resolves a cached label")
ctx.endBattleText = nil
pcall(Commands.save_end_battle_text, ctx, Commands.modText("_Known"))
T.eq(ctx.endBattleText, "known{DONE}", "mod save_end_battle_text still resolves a cached label")
T.check(not pcall(Commands.save_end_battle_text, ctx, "_NotARealLabel"), "save_end_battle_text errors on an unknown label")

ctx.source = { modId = "probe" }
for _, literal in ipairs({ "...", "OK", "PIKACHU", "42" }) do
  shown = nil
  local okRow, errRow = pcall(Commands.show_text, ctx, literal)
  T.check(okRow and shown and shown.text == literal, "mod-owned map script row prints " .. literal .. ": " .. tostring(errRow))
  ctx.endBattleText = nil
  local okEnd, errEnd = pcall(Commands.save_end_battle_text, ctx, literal)
  T.check(okEnd and ctx.endBattleText == literal, "mod-owned save_end_battle_text arms " .. literal .. ": " .. tostring(errEnd))
end
shown = nil
pcall(Commands.show_text, ctx, "_Known")
T.eq(shown and shown.text, "known{DONE}", "mod-owned map script row still resolves a cached label")
ctx.source = nil

local adapter = readAll("src/mods/UnifiedScripts.lua")
T.check(adapter:find("Commands.show_text, ctx, Commands.modText(value)", 1, true) ~= nil,
  "Gen 1 mod show/ask rows mark their text as mod text")
T.check(adapter:find('row[1] == "save_end_battle_text"', 1, true) ~= nil,
  "Gen 1 mod save_end_battle_text rows mark their text as mod text")

T.finish()
