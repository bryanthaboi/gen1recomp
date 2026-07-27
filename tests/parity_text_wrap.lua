-- Parity test: the dialogue box soft-wraps on glyphs, not bytes.
-- Self-contained: run via `luajit tests/parity_text_wrap.lua`; also
-- dofile'd by tests/run_tests.lua's aggregator.
--
-- TextBox.paginate used to compare `#line` against maxCols.  `#` is a byte
-- count, and 604 of the extracted strings carry a multi-byte charmap
-- sequence: "é" in POKéMON and POKéDEX, "♂"/"♀" on the NIDORANs, "×".
-- So the box measured "I study POKéMON as" as 19 wide and broke a line
-- that draws 18 glyphs, and when no space was in reach it cut *inside* the
-- é, leaving two invalid bytes that Font.encode renders as two spaces.
--
-- Both symptoms are English-only bugs, but the same arithmetic is what
-- decides whether a translation mod can wrap at all: a kana page measured
-- in bytes wraps every fourth glyph (#186, #245).  So the assertions here
-- come in two halves: the vanilla lines that must stop wrapping, and the
-- non-ASCII shapes a translator will actually hand the box.

package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end

local S = require("tests.harness").suite("parity text wrap")
local check, eq = S.check, S.eq

local Font = require("src.render.Font")
Font.load(Data)
local TextBox = require("src.render.TextBox")

local COLS = 18

-- An oracle independent of Font.split: count UTF-8 lead bytes.  Valid for
-- the extracted text because none of it spells a multi-char ASCII ligature
-- (`<PK>`, `'d`); the ligature cases below are asserted separately.
local function codepoints(s)
  local n = 0
  for i = 1, #s do
    local b = s:byte(i)
    if b < 0x80 or b > 0xBF then n = n + 1 end
  end
  return n
end

-- Whole-string UTF-8 validity.  Note this is not "the last byte is a lead
-- byte": a well-formed 3-byte kana ends on a continuation byte by
-- definition.  What a torn cut leaves behind is a sequence whose
-- continuation bytes are missing or orphaned, which is what this catches.
local function isValidUtf8(s)
  local i, n = 1, #s
  while i <= n do
    local b = s:byte(i)
    local extra
    if b < 0x80 then extra = 0
    elseif b >= 0xC2 and b <= 0xDF then extra = 1
    elseif b >= 0xE0 and b <= 0xEF then extra = 2
    elseif b >= 0xF0 and b <= 0xF4 then extra = 3
    else return false end -- a bare continuation byte, or an invalid lead
    if i + extra > n then return false end
    for k = i + 1, i + extra do
      local c = s:byte(k)
      if c < 0x80 or c > 0xBF then return false end
    end
    i = i + extra + 1
  end
  return true
end

-- ---------- Font.split is a partition, not a filter ----------

do
  for _, sample in ipairs({
    "POKéMON", "NIDORAN♂", "A", "", "<PK><MN>", "12 × 34", "I'd like that",
    "たたかう", "Une créature",
  }) do
    local rebuilt = {}
    for _, span in ipairs(Font.split(sample)) do
      rebuilt[#rebuilt + 1] = sample:sub(span.from, span.to)
    end
    eq(table.concat(rebuilt), sample, ("split round-trips %q"):format(sample))
  end

  eq(#Font.split("POKéMON"), 7, "POKéMON is 7 glyphs (8 bytes)")
  eq(#Font.split("NIDORAN♂"), 8, "NIDORAN♂ is 8 glyphs (10 bytes)")
  eq(#Font.split("<PK><MN>"), 2, "the PK/MN ligatures are one glyph each")
  eq(#Font.split("I'd"), 2, "the 'd ligature is one glyph")
end

-- ---------- the vanilla lines that were breaking ----------

-- Every line the extractor already broke for us fits the box by design.
-- Any of them that paginate splits again is a line the player sees wrapped
-- in a place the original never wrapped it.
do
  local spurious = {}
  for id, text in pairs(Data.text) do
    if type(text) == "string" then
      for line in (text .. "\n"):gmatch("(.-)[\n\11\12]") do
        if line ~= "" and codepoints(line) <= COLS then
          local pages = TextBox.paginate(line, COLS)
          if #pages[1] > 1 then
            spurious[#spurious + 1] = ("%s: %q"):format(id, line)
          end
        end
      end
    end
  end
  eq(#spurious, 0, "no extracted line that fits in 18 glyphs gets re-wrapped"
     .. (spurious[1] and (" (e.g. " .. spurious[1] .. ")") or ""))
end

-- The named ones, so a regression names itself instead of showing a count.
do
  for _, line in ipairs({
    "I study POKéMON as",       -- _OaksLabScientistText
    "A sleeping POKéMON",       -- _Route12SnorlaxText
    "POKéMON are living",       -- _BluesHouseDaisyWalkingText
    "POKé FLUTE awakens",       -- _CeladonPokecenterGentlemanText
    "How's your POKéDEX",       -- _PokemonTower2FRivalHowsYourDexText
  }) do
    eq(#line, 19, ("%q really is 19 bytes"):format(line))
    eq(codepoints(line), 18, ("%q really is 18 glyphs"):format(line))
    local pages = TextBox.paginate(line, COLS)
    eq(#pages[1], 1, ("%q stays on one line"):format(line))
  end
end

-- ---------- ASCII behaviour is untouched ----------

-- The fix must not move a single pure-ASCII break, or every hand-ported
-- script that was tuned against the old wrap shifts under it.
do
  local function byteWrap(line, maxCols)
    local out = {}
    while #line > maxCols do
      local cut = maxCols
      for i = maxCols, 1, -1 do
        if line:sub(i, i) == " " then cut = i break end
      end
      out[#out + 1] = line:sub(1, cut)
      line = line:sub(cut + 1)
    end
    out[#out + 1] = line
    return out
  end

  for _, line in ipairs({
    "ABCDEFGH IJKLMNOPQ",
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ",
    "the quick brown fox jumps over the lazy dog",
    "SUPERLONGWORDWITHNOSPACESATALLHERE and more",
    "trailing space at the end ",
    "short",
  }) do
    local want = byteWrap(line, COLS)
    local got = TextBox.paginate(line, COLS)[1]
    eq(#got, #want, ("ASCII %q wraps into the same number of lines"):format(line))
    for i = 1, math.max(#got, #want) do
      eq(got[i], want[i], ("ASCII %q line %d is unchanged"):format(line, i))
    end
  end
end

-- ---------- what a translation actually hands the box ----------

do
  -- French: accented Latin, spaces to break on.  Measured in bytes this
  -- broke after "créature"; measured in glyphs it fills the box.
  local fr = "Une créature très étrange apparait"
  local lines = TextBox.paginate(fr, COLS)[1]
  for i, line in ipairs(lines) do
    check(codepoints(line) <= COLS,
          ("french line %d fits in 18 glyphs (got %d)"):format(i, codepoints(line)))
    check(isValidUtf8(line),
          ("french line %d is not cut mid-character"):format(i))
  end

  -- Japanese: 3-byte kana and no spaces at all, the worst case for a
  -- byte-wise cut.  Byte wrapping gave 6 glyphs a line.
  local jp = "ポケモンずかんをかんせいさせてください"
  local jpLines = TextBox.paginate(jp, COLS)[1]
  eq(#jpLines, 2, "19 kana with no spaces wrap into two lines, not four")
  eq(codepoints(jpLines[1]), COLS, "the first kana line is a full 18 glyphs")
  for i, line in ipairs(jpLines) do
    check(isValidUtf8(line),
          ("kana line %d is not cut mid-character"):format(i))
  end

  -- The exact shape that used to tear a character in half: 17 ASCII then a
  -- 2-byte char, so the byte-18 cut landed inside it.
  local torn = "ABCDEFGHIJKLMNOPQétrange"
  local tornLines = TextBox.paginate(torn, COLS)[1]
  for i, line in ipairs(tornLines) do
    check(isValidUtf8(line),
          ("torn line %d is not cut mid-character"):format(i))
  end
  eq(table.concat(tornLines), torn, "wrapping loses no bytes")
end

-- A glyph wider than the whole box still has to advance, or pushLine spins.
do
  local pages = TextBox.paginate("ありがとう", 1)
  check(#pages[1] >= 5, "a one-column box still emits one glyph per line")
end

S.finish()
