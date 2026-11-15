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

function TextClip.charmapSplit(charmap, pages)
  local byFirst = {}
  local function bucket(e)
    if type(e) == "table" and type(e.seq) == "string" and #e.seq > 1 then
      local b = e.seq:byte(1)
      byFirst[b] = byFirst[b] or {}
      table.insert(byFirst[b], e.seq)
    end
  end
  for _, e in ipairs(type(charmap) == "table" and charmap or {}) do bucket(e) end
  for _, page in pairs(type(pages) == "table" and pages or {}) do
    for _, e in ipairs(type(page) == "table" and type(page.charmap) == "table"
        and page.charmap or {}) do
      bucket(e)
    end
  end
  for _, l in pairs(byFirst) do table.sort(l, function(a, b) return #a > #b end) end
  local function split(s)
    local spans, i, n = {}, 1, #s
    while i <= n do
      local last
      for _, seq in ipairs(byFirst[s:byte(i)] or {}) do
        if s:sub(i, i + #seq - 1) == seq then
          last = i + #seq - 1
          break
        end
      end
      last = last or charEnd(s, i, n)
      spans[#spans + 1] = { from = i, to = last }
      i = last + 1
    end
    return spans
  end
  return split
end

function TextClip.scrub(s)
  if type(s) ~= "string" then return s end
  local out, i, n = {}, 1, #s
  while i <= n do
    local b = s:byte(i)
    local want = (b < 0x80 and 1) or (b >= 0xC2 and b <= 0xDF and 2)
      or (b >= 0xE0 and b <= 0xEF and 3) or (b >= 0xF0 and b <= 0xF4 and 4) or 0
    local ok = want > 0 and i + want - 1 <= n
    for j = i + 1, ok and i + want - 1 or i do
      local c = s:byte(j)
      if c < 0x80 or c > 0xBF then ok = false break end
    end
    if ok then
      out[#out + 1] = s:sub(i, i + want - 1)
      i = i + want
    else
      i = i + 1
    end
  end
  return table.concat(out)
end

return TextClip
