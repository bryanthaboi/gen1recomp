#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function finish()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local Extract = require("src.import.gba.extract_scripts")
local TextIR = require("src.core.game3.scripting.text_ir")
local Opcodes = require("src.core.game3.scripting.opcodes")
local Braille = require("src.ui.game3.braille")

local BATTLE = { battle = setmetatable({}, { __index = function() return "" end }) }
local function plain(ir)
  return TextIR.toPlain(ir or {}, BATTLE) or ""
end

local BRAILLE_INC = "../pokefirered/data/text/braille.inc"
local PRET_LABEL, PRET_BODIES = {}, {}
do
  local f = io.open(BRAILLE_INC, "rb")
  if f then
    local src = f:read("*a")
    f:close()
    for label, body in src:gmatch("(Braille_Text_[%w_]+)::%s*\n%s*%.braille%s+\"(.-)%$\"") do
      PRET_LABEL[label] = body
      PRET_BODIES[#PRET_BODIES + 1] = body
    end
  end
end
local havePret = #PRET_BODIES > 0

local function checkText(got, label, msg)
  local want = PRET_LABEL[label]
  if not want then
    print("[skip] " .. msg .. ": no " .. BRAILLE_INC)
    return
  end
  check(got == want, msg .. ", got " .. string.format("%q", got))
end

print("[test] 1. the braille charmap is the inverse of pret's braille encoder")
local map = Extract.BRAILLE_CHARMAP
check(type(map) == "table", "ExtractScripts.BRAILLE_CHARMAP exists")
check(type(Extract.decodeBraille) == "function", "ExtractScripts.decodeBraille exists")
if type(map) ~= "table" or type(Extract.decodeBraille) ~= "function" then finish() end
local entries = 0
local badInverse = nil
for code, ch in pairs(map or {}) do
  entries = entries + 1
  if Braille.CODE[ch] ~= code then
    badInverse = badInverse or string.format("0x%02X -> %q re-encodes to %s", code, ch,
      tostring(Braille.CODE[ch]))
  end
end
-- include/characters.h:285
check(entries == 39, "39 meaningful braille codes mapped (got " .. entries .. ")")
check(badInverse == nil, "every code round-trips through Braille.CODE: " .. tostring(badInverse))
check(map[0x00] == " " and map[0x01] == "A" and map[0x39] == "Z" and map[0x3A] == "#",
  "space, A, Z and the number indicator")
check(map[0x02] == nil and map[0x08] == nil and map[0x3D] == nil,
  "the meaningless dot combinations stay unmapped")

print("[test] 2. decodeBraille on raw cart bytes")
-- data/text/braille.inc:47
local EVERYTHING = { 0x09, 0x35, 0x09, 0x1D, 0x3B, 0x1E, 0x0D, 0x06, 0x1B, 0x0F, 0xFF }
local ir = Extract.decodeBraille(EVERYTHING)
checkText(plain(ir), "Braille_Text_Everything", "0x09 0x35 ... 0x0F decodes to pret's literal")
check(ir[#ir] and ir[#ir].t == "eos", "0xFF terminates the string")
-- data/text/braille.inc:50
local HAS_MEANING = { 0x0D, 0x01, 0x16, 0x00, 0x13, 0x09, 0x01, 0x1B, 0x06, 0x1B, 0x0F, 0xFF }
checkText(plain(Extract.decodeBraille(HAS_MEANING)), "Braille_Text_HasMeaning1",
  "0x00 is a space, not a terminator")
local nl = Extract.decodeBraille({ 0x31, 0x17, 0xFE, 0x0B, 0x19, 0x2E, 0x1B, 0xFF })
if havePret then
  check(plain(nl) == PRET_LABEL.Braille_Text_Up .. "\n" .. PRET_LABEL.Braille_Text_Down,
    "0xFE is a line break, got " .. string.format("%q", plain(nl)))
else
  print("[skip] the 0xFE line break check: no " .. BRAILLE_INC)
end
check(plain(Extract.decodeBraille({ 0x3D, 0xFF })) == "?",
  "an unmapped dot combination falls through to ?")

print("[test] 3. the same bytes through the latin charmap are the old garbage")
check(plain(TextIR.decode(EVERYTHING)) ~= plain(Extract.decodeBraille(EVERYTHING)),
  "TextIR.decode still reads braille bytes as latin, so the braille path has to be separate")

print("[test] 4. bfsFromSeeds remaps both braille opcodes")
local BRAILLE_AT = 0x40
local LATIN_AT = 0x60
local buf = {}
local function put(off, ...)
  local bytes = { ... }
  for i = 1, #bytes do buf[off + i] = bytes[i] end
end
local function putPtr(off, addr)
  put(off, addr % 256, math.floor(addr / 256) % 256,
    math.floor(addr / 65536) % 256, math.floor(addr / 16777216) % 256)
end
-- data/script_cmd_table.inc:107,124,215
put(0, 0x78); putPtr(1, 0x08000000 + BRAILLE_AT)
put(5, 0xD3); putPtr(6, 0x08000000 + BRAILLE_AT)
put(10, 0x67); putPtr(11, 0x08000000 + LATIN_AT)
put(15, 0x02)
for i = 1, #EVERYTHING do buf[BRAILLE_AT + i] = EVERYTHING[i] end
put(LATIN_AT, 0xBB, 0xBC, 0xBD, 0xFF)

local rom = {}
rom.size = 0x100
function rom:get(off)
  if off < 0 or off >= self.size then error(("ROM OOB 0x%X"):format(off)) end
  return buf[off + 1] or 0
end
function rom:readBytes(off, len)
  local out = {}
  for i = 0, len - 1 do
    if off + i >= self.size then break end
    out[i + 1] = self:get(off + i)
  end
  return out
end
function rom:ptrOffset(ptr)
  if ptr < 0x08000000 or ptr >= 0x0A000000 then return nil end
  return ptr - 0x08000000
end

local bfs = Extract.bfsFromSeeds(rom, { 0x08000000 })
local rows = bfs.scripts[Opcodes.key(0x08000000)]
check(type(rows) == "table" and #rows == 4, "the stub script disassembled into 4 rows")
local bKey = Opcodes.key(0x08000000 + BRAILLE_AT)
local lKey = Opcodes.key(0x08000000 + LATIN_AT)
check(rows[1] and rows[1].op == "braillemessage" and rows[1][1] == bKey and rows[1].ptr == bKey,
  "braillemessage operand remapped to " .. bKey)
check(rows[2] and rows[2].op == "getbraillestringwidth" and rows[2][1] == bKey
  and rows[2].ptr == bKey,
  "getbraillestringwidth operand remapped instead of staying a raw ROM pointer")
checkText(plain(bfs.text[bKey]), "Braille_Text_Everything",
  "the braille body decoded with the braille charmap")
check(plain(bfs.text[lKey]) == "ABC",
  "the neighbouring latin message still decodes with the latin charmap, got "
  .. plain(bfs.text[lKey]))

print("[test] 5. the cart itself")
local romPath = "../pokefirered/pokefirered.gba"
local f = io.open(romPath, "rb")
if not f then
  print("[skip] cart byte check: no " .. romPath)
else
  -- data/text/braille.inc:46
  f:seek("set", 0x1A92C5)
  local raw = f:read(11) or ""
  f:close()
  local bytes = {}
  for i = 1, #raw do bytes[i] = raw:byte(i) end
  checkText(plain(Extract.decodeBraille(bytes)), "Braille_Text_Everything",
    "ROM 0x1A92C5 decodes to pret's literal")
end

print("[test] 6. the imported cache")
local Cache = require("tests.game3_cache")
local bundle = Cache.bundle("scripts/scripts.lua")
if not bundle then
  print("[skip] game3_stitchimp_braille_text_test cache checks: " .. tostring(Cache.reason))
  finish()
end

local brailleKeys, order = {}, {}
for _, script in pairs(bundle.scripts or {}) do
  if type(script) == "table" then
    for _, row in ipairs(script) do
      if type(row) == "table"
          and (row.op == "braillemessage" or row.op == "getbraillestringwidth") then
        local key = row.ptr or row[1]
        if not brailleKeys[key] then
          brailleKeys[key] = {}
          order[#order + 1] = key
        end
        brailleKeys[key][row.op] = (brailleKeys[key][row.op] or 0) + 1
      end
    end
  end
end
table.sort(order)
if havePret then
  check(#order == #PRET_BODIES,
    #PRET_BODIES .. " distinct braille strings reached by the BFS (got " .. #order .. ")")
else
  print("[skip] the braille string count: no " .. BRAILLE_INC)
end

local rawOperand, missing, unmapped, mismatch = nil, nil, nil, nil
local seen = {}
for _, key in ipairs(order) do
  if type(key) ~= "string" then
    rawOperand = rawOperand or tostring(key)
  else
    local body = plain(bundle.text[key])
    if body == "" then
      missing = missing or key
    else
      seen[body] = (seen[body] or 0) + 1
      for ch in body:gmatch("[^\n]") do
        if Braille.CODE[ch] == nil then
          unmapped = unmapped or (key .. " has " .. string.format("%q", ch))
        end
      end
      local glyphs = Braille.countGlyphs(body)
      local want = select(2, body:gsub("[^\n]", ""))
      if glyphs ~= want then
        mismatch = mismatch or (key .. " " .. glyphs .. " glyphs for " .. want .. " chars")
      end
    end
  end
end
check(rawOperand == nil, "no braille operand left as a raw ROM pointer: " .. tostring(rawOperand))
check(missing == nil, "every braille key has a body in scripts/text.lua: " .. tostring(missing))
check(unmapped == nil,
  "every decoded glyph is a braille character the wall can draw: " .. tostring(unmapped))
check(mismatch == nil,
  "Braille.encode gives one glyph per decoded character: " .. tostring(mismatch))

if havePret then
  local wantCount = {}
  for _, body in ipairs(PRET_BODIES) do wantCount[body] = (wantCount[body] or 0) + 1 end
  local absent, duped = nil, nil
  for body, n in pairs(wantCount) do
    if not seen[body] then
      absent = absent or body
    elseif seen[body] ~= n then
      duped = duped or string.format("%q cached %d times, pret writes it %d", body, seen[body], n)
    end
  end
  check(absent == nil,
    "every pret .braille literal is in the cache verbatim: " .. tostring(absent))
  check(duped == nil,
    "each repeated literal is its own string in the cache: " .. tostring(duped))
else
  print("[skip] the cache against pret's literals: no " .. BRAILLE_INC)
end

-- asm/macros/event.inc:1845
local paired = 0
for _, key in ipairs(order) do
  local ops = brailleKeys[key]
  if ops.braillemessage and ops.getbraillestringwidth then paired = paired + 1 end
end
check(paired == 22, "22 braillemessage_wait pairs share a text key (got " .. paired .. ")")

local lowercase = 0
for _, t in pairs(bundle.text or {}) do
  if type(t) == "table" and plain(t):find("%l") then lowercase = lowercase + 1 end
end
check(lowercase > 1000,
  "the latin text pack is untouched, " .. lowercase .. " entries still have lowercase")

finish()
