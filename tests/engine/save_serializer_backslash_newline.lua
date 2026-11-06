package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

local SaveSerializer = require("src.core.SaveSerializer")

local function viaLua(src)
  local fn = assert(loadstring(src))
  return fn()
end

for _, case in ipairs({
  { "backslash LF", '"a\\\nb"' },
  { "backslash CR", '"a\\\rb"' },
  { "backslash CR LF", '"a\\\r\nb"' },
  { "backslash LF CR", '"a\\\n\rb"' },
  { "two escaped LFs", '"a\\\n\\\nb"' },
  { "escaped CR LF then escaped LF", '"a\\\r\n\\\nb"' },
  { "escaped LF CR then escaped CR", '"a\\\n\r\\\rb"' },
}) do
  local src = "return { s = " .. case[2] .. " }"
  local want = viaLua(src).s
  local got = SaveSerializer.decode(src)
  eq(got and got.s, want, case[1] .. ": reads the same string Lua does")
end

local all = {}
for b = 0, 255 do all[#all + 1] = string.char(b) end
local bytes = table.concat(all) .. "\n\n\r\n\r\r\n"
local written = SaveSerializer.encode({ blob = bytes })

for _, hop in ipairs({
  { "as written", function(s) return s end },
  { "LF to CRLF", function(s) return (s:gsub("\n", "\r\n")) end },
  { "LF to CR", function(s) return (s:gsub("\n", "\r")) end },
  { "LF to LFCR", function(s) return (s:gsub("\n", "\n\r")) end },
}) do
  local back, err = SaveSerializer.decode(hop[2](written))
  check(back ~= nil, hop[1] .. ": the slot parses -- " .. tostring(err))
  local blob = back and back.blob
  check(blob == bytes, ("%s: every byte comes back (%s bytes vs %d)")
    :format(hop[1], tostring(blob and #blob), #bytes))
end

eq(SaveSerializer.encode({ a = "x\ny\r\0\200", b = { 1, true }, n = 0.5 }),
  'return {\n  a = "x\\\ny\\13\\0\200",\n  b = {\n    [1] = 1,\n    [2] = true,\n  },\n  n = 0.5,\n}\n',
  "the writer output is unchanged")

T.finish("save serializer backslash newline")
