package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq
local Theme = require("src.ui.kit.Theme")
local Manifest = require("src.mods.Manifest")
local LauncherMods = require("src.mods.LauncherMods")

local function decode(s)
  local cps, i, n = {}, 1, #s
  while i <= n do
    local b = s:byte(i)
    local len, cp
    if b < 0x80 then len, cp = 1, b
    elseif b >= 0xC2 and b < 0xE0 then len, cp = 2, b - 0xC0
    elseif b >= 0xE0 and b < 0xF0 then len, cp = 3, b - 0xE0
    elseif b >= 0xF0 and b < 0xF5 then len, cp = 4, b - 0xF0
    else error("UTF-8 decoding error") end
    if i + len - 1 > n then error("UTF-8 decoding error") end
    for k = i + 1, i + len - 1 do
      local c = s:byte(k)
      if c < 0x80 or c >= 0xC0 then error("UTF-8 decoding error") end
      cp = cp * 64 + (c - 0x80)
    end
    cps[#cps + 1] = cp
    i = i + len
  end
  return cps
end

local function glyphW(cp)
  if cp == 0x301 then return 0 end
  if cp < 0x80 then return 3 + cp % 5 end
  return 9 + cp % 4
end

local font = { calls = 0 }
function font:getWidth(s)
  self.calls = self.calls + 1
  local w = 0
  for _, cp in ipairs(decode(s)) do w = w + glyphW(cp) end
  return w
end

local function safeWidth(f, s)
  local ok, w = pcall(f.getWidth, f, s)
  return ok and w or math.huge
end

local function prevCharStart(s, i)
  local j = i - 1
  while j > 1 do
    local b = s:byte(j)
    if b < 0x80 or b >= 0xC0 then break end
    j = j - 1
  end
  return j
end

local function nextCharStart(s, i)
  local j = i + 1
  while j <= #s do
    local b = s:byte(j)
    if b < 0x80 or b >= 0xC0 then break end
    j = j + 1
  end
  return j
end

local function oldEllipsize(f, text, maxW)
  text = tostring(text or "")
  if not f then return text end
  if maxW <= 0 then return "" end
  if safeWidth(f, text) <= maxW then return text end
  local ell = "..."
  local ew = safeWidth(f, ell)
  local last = #text + 1
  while last > 1 do
    last = prevCharStart(text, last)
    local head = text:sub(1, last - 1)
    if safeWidth(f, head) + ew <= maxW then return head .. ell end
  end
  return ell
end

local function oldEllipsizeLeft(f, text, maxW)
  text = tostring(text or "")
  if not f then return text end
  if maxW <= 0 then return "" end
  if safeWidth(f, text) <= maxW then return text end
  local ell = "..."
  local ew = safeWidth(f, ell)
  local i = 1
  while i <= #text do
    i = nextCharStart(text, i)
    local tail = text:sub(i)
    if safeWidth(f, tail) + ew <= maxW then return ell .. tail end
  end
  return ell
end

local samples = {
  "",
  "a",
  "abc",
  "The quick brown fox jumps over the lazy dog",
  "\227\131\157\227\130\177\227\131\131\227\131\136\227\131\162\227\131\179\227\130\185\227\130\191\227\131\188",
  "Pok\195\169mon caf\195\169 \240\159\148\165 fire \240\159\148\165!",
  "e\204\129e\204\129e\204\129e\204\129 combining marks",
  "ab\128cd\128ef lone continuation bytes",
  "abc\195 truncated lead",
  "tail cut \226\130",
  "\255\254 bad leads up front then text",
  "mid \195a bad then more text after it",
  "\128\128 leading continuations",
  "line one\nline two\nline three",
  string.rep("wide\227\131\157", 20),
}

local mismatches, compared = 0, 0
for _, s in ipairs(samples) do
  for w = -1, 220, 3 do
    local a, b = oldEllipsize(font, s, w), Theme.ellipsize(font, s, w)
    local c, d = oldEllipsizeLeft(font, s, w), Theme.ellipsizeLeft(font, s, w)
    compared = compared + 2
    if a ~= b then
      mismatches = mismatches + 1
      if mismatches <= 5 then
        print(("ellipsize mismatch w=%d %q: old %q new %q"):format(w, s, a, b))
      end
    end
    if c ~= d then
      mismatches = mismatches + 1
      if mismatches <= 5 then
        print(("ellipsizeLeft mismatch w=%d %q: old %q new %q"):format(w, s, c, d))
      end
    end
  end
end
eq(mismatches, 0, ("ellipsize and ellipsizeLeft match the per-codepoint reference on %d cases"):format(compared))

eq(Theme.ellipsize(nil, "abc", 10), "abc", "no font returns the text untouched")
eq(Theme.ellipsize(font, "abc", 0), "", "a zero budget means nothing fits")
eq(Theme.ellipsizeLeft(font, "abc", 0), "", "a zero budget means nothing fits on the left too")
eq(Theme.ellipsize(font, "abc", font:getWidth("abc")), "abc", "an exact fit is returned untouched")

local unit = "Install this mod by dropping it in mods/. \227\131\157\227\130\177 "
local long = string.rep(unit, math.ceil(20000 / #unit)):sub(1, 20000)
while long:byte(#long) >= 0x80 do long = long:sub(1, -2) end

font.calls = 0
local cut = Theme.ellipsize(font, long, 300)
local rightCalls = font.calls
check(rightCalls <= 40,
  ("ellipsize on a 20000-byte string makes at most 40 getWidth calls (made %d)"):format(rightCalls))
eq(cut, oldEllipsize(font, long, 300), "the long-string right cut matches the reference")
check(safeWidth(font, cut) <= 300, "the long-string right cut fits the budget")

font.calls = 0
local cutL = Theme.ellipsizeLeft(font, long, 300)
local leftCalls = font.calls
check(leftCalls <= 40,
  ("ellipsizeLeft on a 20000-byte string makes at most 40 getWidth calls (made %d)"):format(leftCalls))
eq(cutL, oldEllipsizeLeft(font, long, 300), "the long-string left cut matches the reference")

do
  local readme = "\n\n   # Big Mod   \n\nInstall it.\nmore"
  local m = Manifest.validate({ id = "readme", name = "Readme Mod", version = "1.0.0",
    entry = "m.lua", description = readme })
  local row = LauncherMods.deriveList({ m }, { mods = {} })[1]
  eq(row.description, "# Big Mod", "the row keeps the first non-blank line, trimmed")
  eq(row.manifest.description, readme, "the manifest keeps the full description")

  local wall = "  " .. string.rep("\227\131\157", 400)
  local m2 = Manifest.validate({ id = "wall", name = "Wall", version = "1.0.0",
    entry = "m.lua", description = wall })
  local row2 = LauncherMods.deriveList({ m2 }, { mods = {} })[1]
  check(#row2.description <= 300 and #row2.description >= 297,
    ("a one-line wall of text is capped near 300 bytes for the row (got %d)"):format(#row2.description))
  check(pcall(decode, row2.description), "the capped row text is still valid UTF-8")
  eq(row2.description, wall:sub(3, #row2.description + 2), "the cap keeps a prefix")

  local m3 = Manifest.validate({ id = "short", name = "Short", version = "1.0.0",
    entry = "m.lua", description = "Adds a run button." })
  eq(LauncherMods.deriveList({ m3 }, { mods = {} })[1].description,
    "Adds a run button.", "a short description is unchanged")
end

T.finish("ui_kit_ellipsize_cost")
