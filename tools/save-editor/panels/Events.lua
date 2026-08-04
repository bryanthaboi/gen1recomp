-- Events panel: flags, defeated trainers, taken items, and per-map object
-- visibility toggles.  All four sections read/write through Ops so a flip is
-- always dirty + narrated.
--
-- Sub-tabs are pills; the filter is a real Kit.textfield (the old panel
-- edge-detected love.keyboard state every frame because Kit had no input
-- widget, which swallowed every keystroke the rest of the app wanted); and
-- the rows are a two-column grid so twenty fit per page instead of ten.

local Theme = require("Theme")
local Ops = require("Ops")
local PAL = Theme.PAL

local M = {}

local SUB_TABS = {
  { id = "flags",    label = "Flags" },
  { id = "trainers", label = "Trainers" },
  { id = "items",    label = "Items taken" },
  { id = "toggles",  label = "Object toggles" },
}

local HINTS = {
  flags    = "Story flags scraped from data/scripts and the trainer headers, plus any MOD_ flags a loaded mod defines.",
  trainers = "Keys look like MAP_obj_N (save.defeatedTrainers): checked means that trainer stays beaten.",
  items    = "Keys look like MAP_obj_N (save.itemsTaken): checked means that ground item is gone.",
  toggles  = "Per-map object visibility overrides (save.objectToggles), grouped by map.",
}

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

local function contains(haystack, needle)
  if needle == "" then return true end
  return haystack:lower():find(needle:lower(), 1, true) ~= nil
end

-- Each sub-tab reduces to the same shape: a list of rows, where a row knows
-- how to read its checked state, render a label, and write a flip back.
local function buildRows(S)
  local tab = S.eventsTab
  local filter = S.eventFilter or ""
  local rows = {}
  if tab == "flags" then
    for _, name in ipairs(S.events or {}) do
      if contains(name, filter) then
        rows[#rows + 1] = {
          label = name,
          checked = S.save.flags[name] == true,
          set = function(on) Ops.setFlag(S, name, on) end,
        }
      end
    end
  elseif tab == "trainers" or tab == "items" then
    local key = (tab == "trainers") and "defeatedTrainers" or "itemsTaken"
    S.save[key] = S.save[key] or {}
    local t = S.save[key]
    for _, k in ipairs(sortedKeys(t)) do
      if contains(k, filter) then
        rows[#rows + 1] = {
          label = k,
          checked = t[k] == true,
          set = function(on) Ops.setKey(S, key, k, on) end,
        }
      end
    end
  else
    S.save.objectToggles = S.save.objectToggles or {}
    local toggles = S.save.objectToggles
    for _, mapId in ipairs(sortedKeys(toggles)) do
      local mapRows = {}
      for _, name in ipairs(sortedKeys(toggles[mapId])) do
        if contains(name, filter) or contains(mapId, filter) then
          mapRows[#mapRows + 1] = {
            label = name,
            checked = toggles[mapId][name] == true,
            set = function(on) Ops.setToggle(S, mapId, name, on) end,
          }
        end
      end
      if #mapRows > 0 then
        rows[#rows + 1] = { header = true, label = "[" .. mapId .. "]" }
        for _, r in ipairs(mapRows) do rows[#rows + 1] = r end
      end
    end
  end
  return rows
end

function M.draw(S, Kit, x, y, w, h)
  local s = Kit.scale
  local pad = 20 * s
  S.eventsTab = S.eventsTab or "flags"
  S.eventFilter = S.eventFilter or ""

  Kit.card(x, y, w, h)
  local cx = x + pad
  local inner = w - 2 * pad

  -- ------------------------------------------------------------ sub-tabs
  -- The pills flow left to right and WRAP when the card is too narrow to
  -- hold all four on one line (#715): a fixed row used to run the last pill
  -- past the card edge.
  local pillH = 32 * s
  local px, py = cx, y + pad
  for _, t in ipairs(SUB_TABS) do
    local pw = Kit.textWidth("small", t.label) + 32 * s
    if px > cx and px + pw > cx + inner then
      px = cx
      py = py + pillH + 8 * s
    end
    local active = (S.eventsTab == t.id)
    Theme.col(PAL.rowBg, 0.6)
    love.graphics.rectangle("fill", px, py, pw, pillH, pillH / 2, pillH / 2)
    Theme.stroke(px, py, pw, pillH, pillH / 2,
      active and PAL.blue or PAL.cardBorder, active and 0.8 or 0.24,
      active and 1.5 * s or 1)
    Kit.textCenter("small", t.label, px, py + (pillH - Kit.textHeight("small")) / 2,
      pw, active and PAL.heading or PAL.muted)
    if Kit.press(px, py, pw, pillH) then
      S.eventsTab = t.id
      S.eventsOffset = 0
      Ops.disarm(S)
      Ops.say(S, HINTS[t.id])
    end
    px = px + pw + 10 * s
  end

  -- The filter shares the last pill row when there is room for at least a
  -- usable field beside the pills; on a narrow window it wraps onto its own
  -- row instead of painting over the last pill (#715).
  local clearW = 74 * s
  local filterY = py
  local availF = cx + inner - clearW - 10 * s - px - 10 * s
  if availF < 120 * s then
    filterY = py + pillH + 8 * s
    availF = inner - clearW - 10 * s
  end
  local fieldW = math.min(280 * s, math.max(120 * s, availF))
  local fieldX = cx + inner - clearW - 10 * s - fieldW
  S.eventFilter = Kit.textfield("event-filter", fieldX, filterY, fieldW, pillH,
    S.eventFilter, "filter keys...")
  if Kit.button(cx + inner - clearW, filterY, clearW, pillH, "Clear",
      { kind = "accent", font = "small", radius = 8 * s,
        enabled = S.eventFilter ~= "" }) then
    S.eventFilter = ""
    Kit.blur()
    Ops.say(S, "Filter cleared")
  end

  local hintY = filterY + pillH + 10 * s
  Kit.text("small", Kit.ellipsize("small", HINTS[S.eventsTab] or "", inner),
    cx, hintY, PAL.caption)

  -- ---------------------------------------------------------- row grid
  local rows = buildRows(S)
  local pagerH = 30 * s
  local pagerY = y + h - pad - pagerH
  local gridTop = hintY + Kit.textHeight("small") + 14 * s
  local rowH = 34 * s
  local rowGap = 8 * s
  local colGap = 20 * s
  -- two columns need ~460 logical px before the checkbox labels read; a
  -- phone gets one full-width column instead of two crushed ones (#715)
  local cols = (inner >= 460 * s) and 2 or 1
  local colW = (inner - colGap * (cols - 1)) / cols
  local gridH = pagerY - 12 * s - gridTop
  local perCol = math.max(1, math.floor(gridH / (rowH + rowGap)))
  local perPage = perCol * cols

  S.eventsOffset = Ops.clamp(S.eventsOffset or 0, 0, math.max(0, #rows - perPage))
  -- wheel / touch drag move whole grid rows, same contract as the pager (#715)
  S.eventsOffset = Kit.scroll(cx, gridTop, inner, gridH, S.eventsOffset,
    #rows, perPage, cols)

  if #rows == 0 then
    Kit.emptyBox(cx, gridTop, inner, math.min(gridH, 80 * s),
      S.eventFilter ~= "" and "No key matches that filter."
        or "Nothing recorded here yet.")
  end
  -- clip the grid body: on a window too short for even one row the partial
  -- row clips (and its hit test is fenced) instead of covering the pager (#715)
  Kit.pushClip(cx, gridTop, inner, gridH)
  for i = 1, math.min(perPage, #rows - S.eventsOffset) do
    local row = rows[S.eventsOffset + i]
    local ci = (i - 1) % cols
    local ri = math.floor((i - 1) / cols)
    local rx = cx + ci * (colW + colGap)
    local ry = gridTop + ri * (rowH + rowGap)
    if row.header then
      -- a map heading inside the toggles list: not a checkbox, so it must
      -- not look clickable
      Kit.text("mono", Kit.ellipsize("mono", row.label, colW),
        rx + 4 * s, ry + (rowH - Kit.textHeight("mono")) / 2, PAL.caption)
    else
      local newChecked, changed = Kit.checkbox(rx, ry, colW, rowH,
        row.checked, row.label)
      if changed then row.set(newChecked) end
    end
  end
  Kit.popClip()

  Kit.scrollbar(cx, gridTop, inner, gridH, S.eventsOffset, #rows, perPage)

  -- "Clear all" only makes sense for the two key tables the editor owns
  -- wholesale; flags and object toggles are cleared one row at a time.  Its
  -- width is reserved BEFORE the pager draws, so the pager's counter yields
  -- to the button instead of running underneath it (#715).
  local clearKey = (S.eventsTab == "trainers" and "defeatedTrainers")
    or (S.eventsTab == "items" and "itemsTaken") or nil
  local clearBw = 0
  if clearKey then
    local label = (S.eventsTab == "trainers") and "Clear all trainers"
      or "Clear all items taken"
    clearBw = Kit.textWidth("small", label) + 32 * s
    if Kit.button(cx + inner - clearBw, pagerY, clearBw, pagerH,
        Ops.armLabel(S, "clear-" .. clearKey, label),
        { kind = "danger", font = "small", radius = 8 * s }) then
      Ops.clearTable(S, clearKey, label:gsub("^Clear all ", ""))
    end
    clearBw = clearBw + 10 * s
  end
  S.eventsOffset = Kit.pager(cx, pagerY, inner - clearBw, S.eventsOffset,
    #rows, perPage)
end

return M
