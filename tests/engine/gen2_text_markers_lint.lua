-- macros/scripts/text.asm:11 (line / cont / para)

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local check = T.check
local Data = T.fixtures.fresh()
require("src.render.Font").load(Data)
local TextBox = require("src.render.TextBox")

local FILES = {
  "src/script/gen2/Specials.lua",
  "src/script/gen2/specials/battle_tower.lua",
  "src/script/gen2/specials/crystal_extras.lua",
  "src/script/gen2/specials/crystal_story.lua",
  "src/script/gen2/specials/unown_words.lua",
}

local KNOWN = {}

local ESC = { n = "\n", v = "\v", f = "\f", t = "\t", r = "\r",
  ["\\"] = "\\", ['"'] = '"', ["'"] = "'" }

local function unescape(raw)
  return (raw:gsub("\\(.)", function(c) return ESC[c] or ("\\" .. c) end))
end

local function pageIsPlayable(page, conts)
  if #page <= 2 then return true end
  for i = 3, #page do
    if not (conts and conts[i]) then return false end
  end
  return true
end

local function literals(src)
  local out = {}
  local i, line = 1, 1
  local n = #src
  while i <= n do
    local c = src:sub(i, i)
    if c == "\n" then
      line = line + 1
      i = i + 1
    elseif src:sub(i, i + 1) == "--" then
      i = (src:find("\n", i, true) or n + 1)
    elseif c == '"' or c == "'" then
      local j = i + 1
      while j <= n do
        local d = src:sub(j, j)
        if d == "\\" then j = j + 2
        elseif d == c then break
        else j = j + 1 end
      end
      out[#out + 1] = { line = line, text = unescape(src:sub(i + 1, j - 1)) }
      i = j + 1
    else
      i = i + 1
    end
  end
  return out
end

local function unplayable(text)
  local pages = TextBox.paginate((text:gsub("{[%w_]+}", "X")))
  for p, page in ipairs(pages) do
    if not pageIsPlayable(page, pages.contBefore[p]) then return p, #page end
  end
end

local seenKnown = {}
local swept = 0
for _, path in ipairs(FILES) do
  local f = assert(io.open(path, "r"), path)
  local src = f:read("*a")
  f:close()
  for _, lit in ipairs(literals(src)) do
    if lit.text:find("\n", 1, true) then
      swept = swept + 1
      local page, lines = unplayable(lit.text)
      local label = ("%s:%d %q"):format(path, lit.line, lit.text:sub(1, 48))
      if KNOWN[lit.text] then
        seenKnown[lit.text] = true
        check(page ~= nil, label .. " is still on the KNOWN list for a reason")
      else
        check(page == nil, label .. (page and
          (": page %d runs %d lines with no cont/para mark"):format(page, lines)
          or ""))
      end
    end
  end
end

check(swept <= 1, ("%d multi-line literals left; the specials print the cache's text"):format(swept))
for text in pairs(KNOWN) do
  check(seenKnown[text], ("KNOWN entry still present in source: %q"):format(text:sub(1, 40)))
end

T.finish("gen2 text markers lint")
