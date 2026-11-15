package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")

local failed = 0
local function check(cond, msg)
  if cond then print("[ok] " .. msg) else failed = failed + 1; print("[FAIL] " .. msg) end
end

local ROOTS = { "src/core/game3", "src/ui/game3" }
local VERSIONS = { "firered", "leafgreen", "emerald", "ruby", "sapphire" }
local ALLOW = {
  ["Would you like to forfeit the match\nand quit now?"] = true,
  ["Please come again!"] = true,
}

local ESC = { n = "\n", t = "\t", r = "\r", ["\\"] = "\\", ['"'] = '"', ["'"] = "'" }

local function readQuoted(src, i, q)
  local out, j = {}, i
  while j <= #src do
    local c = src:sub(j, j)
    if c == "\\" then
      local n = src:sub(j + 1, j + 1)
      local d = src:match("^%d%d?%d?", j + 1)
      if d then
        out[#out + 1] = string.char(tonumber(d))
        j = j + 1 + #d
      else
        out[#out + 1] = ESC[n] or n
        j = j + 2
      end
    elseif c == q then
      return table.concat(out), j
    elseif c == "\n" then
      return nil, j
    else
      out[#out + 1] = c
      j = j + 1
    end
  end
  return nil, j
end

local function literals(src, file, out)
  local pos = 1
  while true do
    local s, e = src:find("Strings%(%s*[\"']", pos)
    if not s then break end
    local q = src:sub(e, e)
    local text, stop = readQuoted(src, e + 1, q)
    if text then
      local line = select(2, src:sub(1, s):gsub("\n", "")) + 1
      out[#out + 1] = { text = text, where = file .. ":" .. line }
    end
    pos = (stop or e) + 1
  end
end

local function normalize(text)
  return (tostring(text):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

local function sentence(norm)
  if norm:find("[%.%?!]$") or norm:sub(-3) == "\226\128\166" then return true end
  return select(2, norm:gsub(" ", "")) >= 2
end

local function duplicates(lits, romTexts)
  local hits = {}
  for _, lit in ipairs(lits) do
    local norm = normalize(lit.text)
    if not ALLOW[lit.text] and not lit.text:find("%", 1, true) and sentence(norm) and romTexts[norm] then
      hits[#hits + 1] = { where = lit.where, text = lit.text, key = romTexts[norm] }
    end
  end
  return hits
end

local function sourceLiterals()
  local out = {}
  for _, root in ipairs(ROOTS) do
    local p = io.popen('find "' .. root .. '" -name "*.lua" | sort')
    for file in p:lines() do
      local f = assert(io.open(file, "rb"))
      literals(f:read("*a"), file, out)
      f:close()
    end
    p:close()
  end
  return out
end

do
  local lits = {}
  literals([[
local a = Strings("Would you like to forfeit the match\nand quit now?")
local b = Strings('Port only line.')
local c = Strings("%s wants to battle!", name)
local d = Strings( "Can't use that here." )
]], "fixture.lua", lits)
  check(#lits == 4, "scanner finds every Strings() literal in the fixture")
  check(lits[1].text == "Would you like to forfeit the match\nand quit now?", "scanner decodes \\n escapes")
  check(lits[4].where == "fixture.lua:4", "scanner reports file:line")
  local rom = { [normalize("Can't use that here.")] = "gText_CantUseHere",
    [normalize("Would you like to forfeit the match\nand quit now?")] = "STRINGID_QUESTIONFORFEITMATCH" }
  local hits = duplicates(lits, rom)
  check(#hits == 1 and hits[1].key == "gText_CantUseHere", "a literal equal to ROM text is flagged")

  local all = sourceLiterals()
  check(#all > 100, "source scan sees the Gen 3 Strings() literals (" .. #all .. ")")
  local known = {
    [normalize("This can't be used right now.")] = "port",
    [normalize("An EGG can't be used on.")] = "port",
    [normalize("You can't dismount your BIKE here.")] = "gText_CantDismountBike",
    [normalize("Can't use that here.")] = "gText_CantUseHere",
    [normalize("Which move?")] = "gText_WhichMoveToForget",
  }
  local stale = duplicates(all, known)
  for _, h in ipairs(stale) do print("[info] " .. h.where .. " " .. string.format("%q", h.text)) end
  check(#stale == 0, "no removed hand-typed Gen 3 line is back in src/core/game3 or src/ui/game3")
end

local function cacheRoot(version)
  local home = os.getenv("HOME")
  if not home then return nil end
  local ids = {}
  local env = os.getenv("POKEPORT_IDENTITY")
  if env and env ~= "" then ids[#ids + 1] = env end
  ids[#ids + 1] = "g1r-" .. version
  for _, base in ipairs({ home .. "/Library/Application Support/LOVE", home .. "/.local/share/love" }) do
    for _, id in ipairs(ids) do
      local root = base .. "/" .. id .. "/" .. version .. "/data/generated/gba"
      local f = io.open(root .. "/scripts/text.lua", "rb")
      if f then f:close() return root end
    end
  end
  return nil
end

local function romTexts(version, root)
  local Cache = require("tests.game3_cache")
  require("src.core.game3.profile").reset()
  require("src.core.GameVersion").set(version)
  local Dataset = require("src.core.game3.dataset")
  Dataset.cacheRootOverride = root
  Dataset.mountExtractRoots()
  local bundle = require("src.import.gba.extract_scripts").loadBundle(Cache.cache(), root, { allowIncomplete = true })
  if not (bundle and bundle.text) then return nil end
  local TextIR = require("src.core.game3.scripting.text_ir")
  local out = {}
  for key, ir in pairs(bundle.text) do
    local ok, plain = pcall(TextIR.toPlain, ir, {})
    if ok and type(plain) == "string" then
      local norm = normalize(plain)
      if #norm > 0 and (out[norm] == nil or key < out[norm]) then out[norm] = key end
    end
  end
  return out
end

local lits = sourceLiterals()
local mounted = 0
for _, version in ipairs(VERSIONS) do
  local root = cacheRoot(version)
  if not root then
    print("[skip] " .. version .. ": no imported cache")
  else
    local texts = romTexts(version, root)
    if not texts then
      print("[skip] " .. version .. ": cache has no script text bundle")
    else
      mounted = mounted + 1
      local hits = duplicates(lits, texts)
      for _, h in ipairs(hits) do
        print(("[info] %s %s %q equals ROM %s"):format(version, h.where, h.text, h.key))
      end
      check(#hits == 0, version .. ": no Strings() literal duplicates ROM text")
    end
  end
end
if mounted == 0 then print("[skip] ROM duplicate scan: no Gen 3 cache found") end

if failed > 0 then print(failed .. " failure(s)") os.exit(1) end
print("all passed")
