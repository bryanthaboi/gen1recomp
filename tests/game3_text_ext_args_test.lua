package.path = "./?.lua;./?/init.lua;" .. package.path

local TextIR = require("src.core.game3.scripting.text_ir")
local Message = require("src.ui.game3.message")
local FrlgFont = require("src.ui.game3.frlg_font")

local fails = 0
local function check(cond, label)
  if cond then
    print("[ok] " .. label)
  else
    fails = fails + 1
    print("[FAIL] " .. label)
  end
end

local function hex(s)
  return (s:gsub(".", function(c) return string.format("%02X ", c:byte()) end))
end

local DOT = "\194\183"
local SEPS = { 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0x5C, 0x7B, 0x7D }

local bad = {}
for cmd = 0x01, 0x18 do
  local nargs = TextIR.EXT_ARGS[cmd] or 0
  for _, sep in ipairs(SEPS) do
    local code = "\252" .. string.char(cmd) .. string.rep(string.char(sep), nargs)
    local raw = DOT .. code .. DOT
    Message.show(raw, { speed = 0 })
    if #Message._pages ~= 1 or Message._pages[1] ~= raw then
      bad[#bad + 1] = string.format("cmd %02X arg %02X -> %d pages [%s]", cmd, sep, #Message._pages,
        hex(table.concat(Message._pages, "|")))
    end
    Message.close()
  end
end
for _, b in ipairs(bad) do print("  " .. b) end
check(#bad == 0, "Message.show keeps every EXT_CTRL_CODE argument byte on one page")

local tail = "abc\252\19\12"
Message.show(tail, { speed = 0 })
check(#Message._pages == 1 and Message._pages[1] == tail, "trailing CLEAR_TO 0x0C is not trimmed as a page break")
Message.close()

local parts = {}
for k = 0, 2 do parts[#parts + 1] = "\252\18" .. string.char(k * 12) .. DOT end
local dots = table.concat(parts)
Message.showStay(dots, { speed = 0 })
check(#Message._pages == 1 and Message._pages[1] == dots, "fishing SKIP k*12 dots print on one page")
Message.close()

Message.show("one\ftwo\252\19\12three", { speed = 0 })
check(#Message._pages == 2 and Message._pages[2] == "two\252\19\12three", "a bare \\f still breaks pages")
Message.close()

local pages = TextIR.splitPages("a\f\252\17\12b\f", true)
check(#pages == 3 and pages[1] == "a" and pages[2] == "\252\17\12b" and pages[3] == "",
  "splitPages keepEmpty skips ext args and keeps empty tail")
pages = TextIR.splitPages("\f\252\17\12\f")
check(#pages == 1 and pages[1] == "\252\17\12", "splitPages drops empty pages by default")

local ir = TextIR.fromAscii("x\252\19\13y")
check(ir[1].t == "text" and ir[1].s == "x\252\19\13y" and ir[2].t == "eos", "fromAscii keeps CLEAR_TO 0x0D and the next glyph")
ir = TextIR.fromAscii("{\252\19\125z")
check(ir[1].t == "text" and ir[1].s == "{\252\19\125z", "fromAscii does not close a tag on an ext argument")
ir = TextIR.fromAscii("\252\10a\\nb")
check(ir[1].s == "\252\10a" and ir[2].t == "nl", "fromAscii keeps WAIT_SE (cmd 0x0A) as a code")

local long = {}
for k = 1, 30 do long[#long + 1] = "word" end
local wide = table.concat(long, " ", 1, 15) .. "\252\17\32" .. table.concat(long, " ", 16, 30)
local box = TextIR.toTextBox(TextIR.fromAscii(wide), { maxWidth = 208 })
check(box:find("\252\17\32", 1, true) ~= nil, "wrapping a wide line keeps CLEAR 0x20 intact")

local wrapped = FrlgFont.wrap("ab\252\19\12cd\\nef", 200)
check(wrapped == "ab\252\19\12cd\nef", "FrlgFont.wrap keeps CLEAR_TO 0x0C")
check(TextIR.restoreExt(TextIR.protectExt(dots)) == dots, "protectExt/restoreExt round-trip")

if fails > 0 then
  print(fails .. " failure(s)")
  os.exit(1)
end
print("game3_text_ext_args_test: all passed")
