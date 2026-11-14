local TextClip = {}

local function utf8Len(b)
  if b >= 0xF0 and b <= 0xF4 then return 4 end
  if b >= 0xE0 then return 3 end
  if b >= 0xC2 and b <= 0xDF then return 2 end
  return 1
end

local function charEnd(s, i, n)
  local last = i
  local want = utf8Len(s:byte(i))
  while last - i + 1 < want and last < n do
    local c = s:byte(last + 1)
    if c < 0x80 or c > 0xBF then break end
    last = last + 1
  end
  return last
end

local function tagCells(name)
  local FrlgFont = require("src.ui.game3.frlg_font")
  local key = name:upper()
  local ids = FrlgFont.GLYPH_TAGS[key]
  if ids then return #ids end
  if FrlgFont.KEYPAD_TAGS[key] then return 1 end
  return nil
end

function TextClip.spans(s)
  local spans, i, n = {}, 1, #s
  while i <= n do
    local name = s:match("^{([^{}]*)}", i)
    local cells = name and tagCells(name)
    if cells then
      spans[#spans + 1] = { from = i, to = i + #name + 1, w = cells }
      i = i + #name + 2
    else
      local last = charEnd(s, i, n)
      spans[#spans + 1] = { from = i, to = last }
      i = last + 1
    end
  end
  return spans
end

function TextClip.clip(s, limit, split)
  if type(s) ~= "string" then return "" end
  s = s:gsub("%c", "")
  local stop, used = 0, 0
  for _, span in ipairs((split or TextClip.spans)(s)) do
    used = used + (span.w or 1)
    if used > limit then break end
    stop = span.to
  end
  return s:sub(1, stop)
end

return TextClip
