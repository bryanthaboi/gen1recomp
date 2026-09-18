-- GBA text → IR segments (glyphs + control codes FA/FB/FC/FD/FE/FF).

local TextIR = {}

-- FRLG English charmap (pret pokefirered/charmap.txt).
-- CRITICAL: Gen2 uses $F0 for ¥; FRLG uses $F0 for ':' and $B7 for ¥.
-- Mapping FRLG $F0 → "¥" produces BILL¥ / CELIO¥ in extracted text.
local CHARMAP = {
  [0x00] = " ",
  [0x1B] = "é", [0x06] = "É",
  [0x2D] = "&", [0x2E] = "+", [0x35] = "=",
  [0x5B] = "%", [0x5C] = "(", [0x5D] = ")",
  [0x85] = "<", [0x86] = ">",
  [0xA1] = "0", [0xA2] = "1", [0xA3] = "2", [0xA4] = "3", [0xA5] = "4",
  [0xA6] = "5", [0xA7] = "6", [0xA8] = "7", [0xA9] = "8", [0xAA] = "9",
  [0xAB] = "!", [0xAC] = "?", [0xAD] = ".", [0xAE] = "-", [0xAF] = "·",
  [0xB0] = "…", [0xB1] = "“", [0xB2] = "”", [0xB3] = "‘", [0xB4] = "'",
  [0xB5] = "♂", [0xB6] = "♀", [0xB7] = "¥", [0xB8] = ",", [0xB9] = "×",
  [0xBA] = "/",
  [0xBB] = "A", [0xBC] = "B", [0xBD] = "C", [0xBE] = "D", [0xBF] = "E",
  [0xC0] = "F", [0xC1] = "G", [0xC2] = "H", [0xC3] = "I", [0xC4] = "J",
  [0xC5] = "K", [0xC6] = "L", [0xC7] = "M", [0xC8] = "N", [0xC9] = "O",
  [0xCA] = "P", [0xCB] = "Q", [0xCC] = "R", [0xCD] = "S", [0xCE] = "T",
  [0xCF] = "U", [0xD0] = "V", [0xD1] = "W", [0xD2] = "X", [0xD3] = "Y",
  [0xD4] = "Z",
  [0xD5] = "a", [0xD6] = "b", [0xD7] = "c", [0xD8] = "d", [0xD9] = "e",
  [0xDA] = "f", [0xDB] = "g", [0xDC] = "h", [0xDD] = "i", [0xDE] = "j",
  [0xDF] = "k", [0xE0] = "l", [0xE1] = "m", [0xE2] = "n", [0xE3] = "o",
  [0xE4] = "p", [0xE5] = "q", [0xE6] = "r", [0xE7] = "s", [0xE8] = "t",
  [0xE9] = "u", [0xEA] = "v", [0xEB] = "w", [0xEC] = "x", [0xED] = "y",
  [0xEE] = "z",
  [0xF0] = ":", -- FRLG colon (NOT Gen2 yen)
}

TextIR.CHARMAP = CHARMAP
TextIR.CTRL = {
  SCROLL = 0xFA, -- \l
  PARA = 0xFB,   -- \p
  NL = 0xFE,     -- \n
  EOS = 0xFF,
  PLACEHOLDER = 0xFD,
  EXT = 0xFC,
}

-- FD nn placeholders (pret characters.h PLACEHOLDER_ID_*)
TextIR.PH = {
  [0x01] = "player",
  [0x02] = "strvar1",
  [0x03] = "strvar2",
  [0x04] = "strvar3",
  [0x06] = "rival",
}

local function expand_seg(seg, ctx)
  local t = seg.t
  if t == "text" then
    return seg.s
  elseif t == "player" then
    return (ctx and ctx.playerName) or "PLAYER"
  elseif t == "rival" then
    return (ctx and ctx.rivalName) or "RIVAL"
  elseif t == "strvar" then
    local sv = ctx and ctx.stringVars
    return (sv and sv[seg.n]) or ""
  elseif t == "tag" then
    return seg.tag
  elseif t == "ph" then
    -- Cached extracts may still store FD 06 as { t="ph", code=6 }.
    local code = tonumber(seg.code)
    local name = seg.name
    if code == 0x01 or name == "PLAYER" then
      return (ctx and ctx.playerName) or "PLAYER"
    end
    if code == 0x06 or name == "RIVAL" then
      return (ctx and ctx.rivalName) or "RIVAL"
    end
    if code and code >= 0x02 and code <= 0x04 then
      local sv = ctx and ctx.stringVars
      return (sv and sv[code - 1]) or ""
    end
    if name == "STR_VAR_1" or name == "STR_VAR_2" or name == "STR_VAR_3" then
      local n = tonumber(name:sub(-1)) or 1
      local sv = ctx and ctx.stringVars
      return (sv and sv[n]) or ""
    end
    if name and (name == "FONT_MALE" or name == "FONT_FEMALE" or name == "FONT_NORMAL"
        or name:find("^COLOR") or name:find("^SHADOW") or name:find("^HIGHLIGHT") or name:find("^BG")) then
      return "{" .. name .. "}"
    end
    return ""
  end
  return nil
end

TextIR.expandSeg = expand_seg

local function flush_text(out, buf)
  if buf and #buf > 0 then
    out[#out + 1] = { t = "text", s = table.concat(buf) }
  end
end

--- Decode raw GBA string bytes (table of ints or string) into IR.
function TextIR.decode(bytes)
  local out, buf = {}, {}
  local i, n = 1, #bytes
  local function b(idx)
    if type(bytes) == "string" then return bytes:byte(idx) end
    return bytes[idx]
  end
  while i <= n do
    local c = b(i)
    if c == 0xFF then
      flush_text(out, buf); buf = {}
      out[#out + 1] = { t = "eos" }
      break
    elseif c == 0xFE then
      flush_text(out, buf); buf = {}
      out[#out + 1] = { t = "nl" }
      i = i + 1
    elseif c == 0xFA then
      flush_text(out, buf); buf = {}
      out[#out + 1] = { t = "scroll" }
      i = i + 1
    elseif c == 0xFB then
      flush_text(out, buf); buf = {}
      out[#out + 1] = { t = "para" }
      i = i + 1
    elseif c == 0xFD then
      flush_text(out, buf); buf = {}
      local nn = b(i + 1) or 0
      if nn == 0x01 then
        out[#out + 1] = { t = "player" }
      elseif nn == 0x06 then
        out[#out + 1] = { t = "rival" }
      elseif nn >= 0x02 and nn <= 0x04 then
        out[#out + 1] = { t = "strvar", n = nn - 1 }
      else
        out[#out + 1] = { t = "ph", code = nn }
      end
      i = i + 2
    elseif c == 0xFC then
      flush_text(out, buf); buf = {}
      local cmd = b(i + 1) or 0
      local skip = 2
      if cmd == 0x01 or cmd == 0x02 or cmd == 0x03 or cmd == 0x05 or cmd == 0x06
          or cmd == 0x08 or cmd == 0x0C or cmd == 0x0D or cmd == 0x0E or cmd == 0x0F
          or cmd == 0x11 or cmd == 0x12 or cmd == 0x13 or cmd == 0x14 then
        skip = 3
      elseif cmd == 0x04 or cmd == 0x0B or cmd == 0x10 then
        skip = 5
        if cmd == 0x0B or cmd == 0x10 then skip = 4 end
      end
      out[#out + 1] = { t = "ext", cmd = cmd, raw = (type(bytes) == "string" and bytes:sub(i, i + skip - 1)) }
      i = i + skip
    else
      local g = CHARMAP[c]
      if g then
        buf[#buf + 1] = g
        i = i + 1
      elseif c == 0x53 then
        -- PK glyph; next byte 0x54 continues as PKMN (pret charmap)
        local n = b(i + 1)
        if n == 0x54 then
          buf[#buf + 1] = "POKé"
          i = i + 2
        else
          buf[#buf + 1] = "PK"
          i = i + 1
        end
      else
        buf[#buf + 1] = "?"
        i = i + 1
      end
    end
  end
  flush_text(out, buf)
  return out
end

--- Build IR from pret-style ASCII with \n \p \l {PLAYER} {STR_VAR_1} …
function TextIR.fromAscii(s)
  local out, buf = {}, {}
  local i = 1
  while i <= #s do
    local ch = s:sub(i, i)
    if ch == "\\" and i < #s then
      local n = s:sub(i + 1, i + 1)
      flush_text(out, buf); buf = {}
      if n == "n" then out[#out + 1] = { t = "nl" }
      elseif n == "p" then out[#out + 1] = { t = "para" }
      elseif n == "l" then out[#out + 1] = { t = "scroll" }
      elseif n == "f" then out[#out + 1] = { t = "para" }
      else buf[#buf + 1] = "\\" .. n end
      i = i + 2
    elseif ch == "\n" then
      flush_text(out, buf); buf = {}
      out[#out + 1] = { t = "nl" }
      i = i + 1
    elseif ch == "\f" then
      flush_text(out, buf); buf = {}
      out[#out + 1] = { t = "para" }
      i = i + 1
    elseif ch == "\r" then
      i = i + 1
    elseif ch == "{" then
      local j = s:find("}", i)
      if not j then
        buf[#buf + 1] = ch; i = i + 1
      else
        flush_text(out, buf); buf = {}
        local name = s:sub(i + 1, j - 1)
        if name == "PLAYER" then
          out[#out + 1] = { t = "player" }
        elseif name == "RIVAL" then
          out[#out + 1] = { t = "rival" }
        elseif name == "STR_VAR_1" then
          out[#out + 1] = { t = "strvar", n = 1 }
        elseif name == "STR_VAR_2" then
          out[#out + 1] = { t = "strvar", n = 2 }
        elseif name == "STR_VAR_3" then
          out[#out + 1] = { t = "strvar", n = 3 }
        elseif name == "FONT_MALE" or name == "FONT_FEMALE" or name == "FONT_NORMAL"
            or name:find("^COLOR") or name:find("^SHADOW") or name:find("^HIGHLIGHT") or name:find("^BG") then
          out[#out + 1] = { t = "tag", tag = "{" .. name .. "}" }
        else
          out[#out + 1] = { t = "ph", name = name }
        end
        i = j + 1
      end
    else
      buf[#buf + 1] = ch
      i = i + 1
    end
  end
  flush_text(out, buf)
  out[#out + 1] = { t = "eos" }
  return out
end

--- Expand IR to printable pages for host textbox (list of strings).
-- Yields on scroll/para; caller advances. stringVars/player/rival from ctx.
function TextIR.expandPage(ir, startIdx, ctx)
  local parts = {}
  local i = startIdx or 1
  while i <= #ir do
    local seg = ir[i]
    local t = seg.t
    if t == "nl" then
      parts[#parts + 1] = "\n"
    elseif t == "para" or t == "scroll" then
      return table.concat(parts), i + 1, t
    elseif t == "eos" then
      return table.concat(parts), i + 1, "eos"
    elseif t == "ext" then
      -- ignore for v1 printer
    else
      local s = expand_seg(seg, ctx)
      if s then parts[#parts + 1] = s end
    end
    i = i + 1
  end
  return table.concat(parts), i, "eos"
end

function TextIR.toPlain(ir, ctx)
  local pages, idx, kind = {}, 1, nil
  repeat
    local page
    page, idx, kind = TextIR.expandPage(ir, idx, ctx)
    if page and #page > 0 then pages[#pages + 1] = page end
  until kind == "eos" or not kind
  return table.concat(pages, "\n\n")
end

local function wrap_subline(lineStr, maxW)
  if not lineStr or lineStr == "" then return { "" } end
  maxW = maxW or 208
  local okF, FrlgFont = pcall(require, "src.ui.game3.frlg_font")
  if okF and FrlgFont and FrlgFont.measure then
    local curW = FrlgFont.measure(lineStr)
    if curW <= maxW then
      return { lineStr }
    end
    local spaceW = FrlgFont.measure(" ")
    local words = {}
    for word in lineStr:gmatch("%S+") do
      words[#words + 1] = word
    end
    if #words == 0 then return { "" } end
    local out = {}
    local cur = words[1]
    local curLineWidth = FrlgFont.measure(cur)
    for i = 2, #words do
      local w = words[i]
      local wW = FrlgFont.measure(w)
      if curLineWidth + spaceW + wW <= maxW then
        cur = cur .. " " .. w
        curLineWidth = curLineWidth + spaceW + wW
      else
        out[#out + 1] = cur
        cur = w
        curLineWidth = wW
      end
    end
    out[#out + 1] = cur
    return out
  else
    local maxChars = math.floor(maxW / 6)
    if #lineStr <= maxChars then return { lineStr } end
    local words = {}
    for word in lineStr:gmatch("%S+") do words[#words + 1] = word end
    if #words == 0 then return { "" } end
    local out = {}
    local cur = words[1]
    for i = 2, #words do
      local w = words[i]
      if #cur + 1 + #w <= maxChars then
        cur = cur .. " " .. w
      else
        out[#out + 1] = cur
        cur = w
      end
    end
    out[#out + 1] = cur
    return out
  end
end

--- Host TextBox string: always tap-per-page of at most two lines.
-- `\n` joins the pair inside a page; `\f` clears for the next pair (wait A).
-- Never emits `\v` CONT scroll — Gen1 column budgets make one-line scroll feel
-- too fast. GBA `\p` / `\l` both force a page boundary like a filled pair.
function TextIR.toTextBox(ir, ctx)
  local maxW = (type(ctx) == "table" and ctx.maxWidth) or 208
  local lines, buf = {}, {}
  local function flush(hard)
    lines[#lines + 1] = { s = table.concat(buf), hard = hard }
    buf = {}
  end
  for _, seg in ipairs(ir or {}) do
    local t = seg.t
    local expanded = expand_seg(seg, ctx)
    if expanded ~= nil then
      buf[#buf + 1] = expanded
    elseif t == "nl" then
      flush(false)
    elseif t == "para" or t == "scroll" then
      flush(true)
    elseif t == "eos" then
      if #buf > 0 then flush(false) end
    end
  end
  if #buf > 0 then flush(false) end

  local splitLines = {}
  for _, row in ipairs(lines) do
    local text = row.s or ""
    local hard = row.hard
    local sub = {}
    for line in (text .. "\n"):gmatch("(.-)\r?\n") do
      sub[#sub + 1] = line
    end
    if #sub == 0 then sub = { "" } end
    for si, lineStr in ipairs(sub) do
      local isLastSub = (si == #sub)
      local wrappedList = wrap_subline(lineStr, maxW)
      for wi, wLine in ipairs(wrappedList) do
        local isLastWrap = (wi == #wrappedList)
        splitLines[#splitLines + 1] = {
          s = wLine,
          hard = (isLastSub and isLastWrap) and hard or false,
        }
      end
    end
  end

  local parts = {}
  local onPage = 0
  for _, row in ipairs(splitLines) do
    if row.s ~= "" or row.hard then
      if onPage >= 2 then
        if #parts > 0 then parts[#parts + 1] = "\f" end
        onPage = 0
      elseif onPage > 0 then
        parts[#parts + 1] = "\n"
      end
      if row.s ~= "" then
        parts[#parts + 1] = row.s
        onPage = onPage + 1
      end
      if row.hard then
        onPage = 2 -- next line starts a fresh cleared page
      end
    end
  end
  local s = table.concat(parts)
  return s:gsub("^\f+", ""):gsub("\f+$", "")
end

return TextIR
