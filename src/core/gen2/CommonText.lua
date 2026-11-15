-- The strings an ENGINE routine prints, looked up by their pokegold label.
--
-- data/generated/text.lua is keyed by "bank:addr", because every string in it
-- was found by following a script pointer.  The Day-Care, the POKeMART and the
-- Hall of Fame are printed by asm instead (`ld hl, .SomeText / call
-- PrintText`), so RomExtractorGen2's NAMED_TEXT seeds the walker at those
-- symbols by name and writes text.labels[label] -> that key.  This is the
-- lookup on the other side of that table: a screen asks for
-- "_MartWelcomeText" and never for an address, so a repointed string still
-- resolves.
--
-- `pages` puts the decoded stream back into the shape the Gen 2 speech box
-- draws it in -- up to two lines per screenful -- following home/text.asm:
--
--   \n  `line` / `next`: the box's second row.
--   \f  `para`: PlaceString clears the box, so the next screenful starts empty.
--   \v  `cont`: the box SCROLLS one row, so the line that was on the bottom
--       row is now on the top one and the new text lands under it.  That is
--       why a `cont` shows up here as a page whose first line repeats the
--       previous page's second.
--
-- `fill` substitutes the markers the decoder leaves behind for the values the
-- cart splices at runtime: {STRBUF} for a TX_RAM name and {NUM} for a
-- TX_DECIMAL PrintNum field, both in the order they appear, plus the named
-- {PLAYER} / {RIVAL}.

local CommonText = {}

function CommonText.get(text, label)
  if type(text) ~= "table" then error("text.lua is missing", 2) end
  local labels = text.labels
  if type(labels) ~= "table" then error("text.lua has no labels", 2) end
  local key = labels[tostring(label)]
  if not key then error("text.lua has no label " .. tostring(label), 2) end
  local body = text[key]
  if type(body) ~= "string" then
    error("text.lua has no string for " .. tostring(label), 2)
  end
  if body == "" then return nil end
  return body
end

-- ../pokecrystal/home/text.asm:548 PromptText, :566 DoneText
function CommonText.plain(body)
  if type(body) ~= "string" then return body end
  return (body:gsub("{DONE}", ""):gsub("{PROMPT}", ""))
end

-- One page is an array of one or two lines.
function CommonText.pages(body)
  body = CommonText.plain(body)
  if type(body) ~= "string" or body == "" then return nil end
  local out = {}
  local top, bottom = "", nil
  local function flush()
    if bottom then
      out[#out + 1] = { top, bottom }
    else
      out[#out + 1] = { top }
    end
  end
  local i = 1
  while i <= #body do
    local marker = body:find("[\n\f\v\r]", i)
    local chunk = body:sub(i, (marker or (#body + 1)) - 1)
    if bottom then
      bottom = bottom .. chunk
    else
      top = top .. chunk
    end
    if not marker then break end
    local m = body:sub(marker, marker)
    if m == "\n" then
      bottom = bottom or ""
    elseif m == "\f" then
      flush()
      top, bottom = "", nil
    else
      flush()
      top, bottom = bottom or "", ""
    end
    i = marker + 1
  end
  flush()
  return out
end

-- values: an array consumed in order by {STRBUF} and {NUM}, and optionally
-- values.player / values.rival for the two named markers.
function CommonText.fill(pages, values)
  if not pages then return nil end
  values = values or {}
  local next_ = 1
  -- One pass over both markers, because the order they are CONSUMED in is the
  -- order they appear in: _MartFinalPriceText opens on its {NUM} and
  -- _BargainShopFinalPriceText on its {STRBUF}, and filling one kind before
  -- the other would swap the price and the item name on one of them.
  local function marker(name)
    if name == "PLAYER" or name == "RIVAL" then
      return values[name:lower()] or ("{" .. name .. "}")
    end
    if name ~= "STRBUF" and name ~= "NUM" then return "{" .. name .. "}" end
    local v = values[next_]
    next_ = next_ + 1
    return v ~= nil and tostring(v) or ""
  end
  local out = {}
  for p, page in ipairs(pages) do
    local lines = {}
    for l, line in ipairs(page) do
      lines[l] = (line:gsub("{(%u+)}", marker))
    end
    out[p] = lines
  end
  return out
end

function CommonText.of(text, label, values)
  local pages = CommonText.pages(CommonText.get(text, label))
  if not pages then return nil end
  if values then return CommonText.fill(pages, values) end
  return pages
end

function CommonText.texts(text, labels, fill, single)
  local out = {}
  for key, label in pairs(labels) do
    local list = CommonText.of(text, label)
    if not list then error("text.lua has an empty " .. label, 2) end
    local f = fill and (fill[key] or fill[label])
    if f then
      out[key] = function(...) return CommonText.fill(list, f(...)) end
    elseif single and single[key] then
      out[key] = list[1]
    else
      out[key] = list
    end
  end
  return out
end

return CommonText
