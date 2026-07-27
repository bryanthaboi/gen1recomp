-- Ratchet: player-visible text in the engine stays reachable from a mod.
--
-- Every string the engine writes itself goes through src/core/Strings.lua so
-- a translation can replace it (#186, #245).  That is easy to land once and
-- easy to erode: the next battle message someone adds is a bare literal
-- unless something notices, and nothing notices, because a bare literal
-- works perfectly in English.
--
-- So this gate re-runs the sweep's own test.  In the files whose job is
-- drawing text, a literal carrying a line marker (\n, \f, \v) has to be
-- inside a Strings(...) or Strings.source(...) call.  The exceptions below
-- are the shapes that legitimately carry a marker without being prose, and
-- the list only shrinks: an entry that no longer matches anything fails too,
-- so it cannot rot into a standing excuse.
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local FsIo = require("tests.fs_io")

-- Files that put text in front of the player.  Everywhere else the same
-- literal shapes are ids, log lines, wire framing and asset paths.
local WATCHED_DIRS = {
  "src/battle", "src/world", "src/ui", "src/inventory", "src/pokemon",
  "src/script",
}
local WATCHED_FILES = {
  "src/link/LinkState.lua", "src/link/LinkBattle.lua",
  "src/link/Tournament.lua", "src/link/Net.lua",
  "src/mods/ManagerState.lua", "src/import/RomImporter.lua",
  "src/core/DiscordPresence.lua",
}

-- A marker in one of these is not prose.  Keep the reason with the rule:
-- a bare pattern list is unreviewable six months from now.
local ALLOWED = {
  { pattern = "gmatch", why = "iterating lines, the marker is the separator" },
  { pattern = "gsub", why = "rewriting markers, not printing them" },
  { pattern = ":find%(", why = "searching for a marker" },
  { pattern = ":match%(", why = "matching on a marker" },
  { pattern = "table%.concat", why = "joining pages with \\f" },
  { pattern = '%.%. "\\f"', why = "page-join glue between two texts" },
  { pattern = "error%(", why = "a developer error, never drawn" },
  { pattern = "Logger%.", why = "a log line, never drawn" },
  { pattern = '== "\\v"', why = "comparing against a marker, not printing it" },
  { pattern = "txBuf", why = "newline-delimited wire framing, not text" },
}

-- Whole files inside a watched directory that are exempt, with the reason.
local EXEMPT_FILES = {
  ["src/ui/OakSpeech.lua"] =
    "the _OakSpeech* literals are fallbacks for extracted text ids, so they "
    .. "are already translatable through the text registry",
}

local function isAllowed(line)
  for _, rule in ipairs(ALLOWED) do
    if line:find(rule.pattern) then return rule end
  end
  return nil
end

-- Blank out every Strings(...) / Strings.source(...) call span, parens
-- balanced, so a call wrapped across lines counts as covered.  A per-line
-- test reported the continuation lines of three real calls as misses.
local function stripStringsCalls(body)
  local out, i, n = {}, 1, #body
  while i <= n do
    local s, e = body:find("Strings%.?s?o?u?r?c?e?%(", i)
    if not s then out[#out + 1] = body:sub(i) break end
    out[#out + 1] = body:sub(i, s - 1)
    local depth, j = 0, body:find("%(", s)
    while j and j <= n do
      local c = body:sub(j, j)
      if c == "(" then depth = depth + 1
      elseif c == ")" then
        depth = depth - 1
        if depth == 0 then break end
      end
      j = j + 1
    end
    j = j or n
    -- keep the newlines so reported line numbers stay honest
    out[#out + 1] = (body:sub(s, j):gsub("[^\n]", ""))
    i = j + 1
  end
  return table.concat(out)
end

-- literals carrying a line marker, ignoring ones already inside a Strings call
local function offenders(body)
  body = stripStringsCalls(body)
  local out = {}
  local lineno = 0
  for line in (body .. "\n"):gmatch("(.-)\n") do
    lineno = lineno + 1
    local code = line:gsub("^%s*", "")
    local isComment = code:sub(1, 2) == "--"
    if not isComment then
      -- a double-quoted literal containing \n, \f or \v
      for literal in line:gmatch('"[^"]*"') do
        if literal:find("\\[nfv]") and not isAllowed(line) then
          out[#out + 1] = { line = lineno, text = code:sub(1, 90) }
          break
        end
      end
    end
  end
  return out
end

local files = {}
for _, dir in ipairs(WATCHED_DIRS) do
  for _, path in ipairs(FsIo.luaFilesUnder(dir)) do files[#files + 1] = path end
end
for _, path in ipairs(WATCHED_FILES) do files[#files + 1] = path end

T.check(#files > 20, "the gate actually found the watched files")

local usedRules, bad = {}, {}
local scanned = 0
for _, path in ipairs(files) do
  if not EXEMPT_FILES[path] then
    local handle = io.open(path, "rb")
    if handle then
      local body = handle:read("*a")
      handle:close()
      scanned = scanned + 1
      for _, hit in ipairs(offenders(body)) do
        bad[#bad + 1] = ("%s:%d  %s"):format(path, hit.line, hit.text)
      end
      -- track which allowances are still earning their place
      for line in (body .. "\n"):gmatch("(.-)\n") do
        local rule = isAllowed(line)
        if rule then usedRules[rule.pattern] = true end
      end
    end
  end
end

T.check(scanned > 20, "the gate read the files it listed")
T.check(#bad == 0,
  ("%d player-visible literal(s) are not routed through Strings(...):\n  %s")
    :format(#bad, table.concat(bad, "\n  ")))

-- the ratchet half: an allowance nothing matches any more is dead weight
for _, rule in ipairs(ALLOWED) do
  T.check(usedRules[rule.pattern] ~= nil,
    ("the %q allowance (%s) matches nothing any more -- delete it")
      :format(rule.pattern, rule.why))
end

for path, why in pairs(EXEMPT_FILES) do
  local handle = io.open(path, "rb")
  T.check(handle ~= nil, ("exempt file %s still exists (%s)"):format(path, why))
  if handle then handle:close() end
end

T.finish("gate_strings_coverage")
