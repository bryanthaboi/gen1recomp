-- Events panel: flags, defeated trainers, taken items, per-map object
-- visibility toggles, system/badges, and script variables.
-- All sections read/write through Ops so a flip is always dirty + narrated.

local Theme = require("Theme")
local Ops = require("Ops")
local Gen = require("Gen")
local Catalog = require("Catalog")
local PAL = Theme.PAL

local M = {}

local SUB_TABS_GEN1 = {
  { id = "flags",    label = "Flags" },
  { id = "trainers", label = "Trainers" },
  { id = "items",    label = "Items taken" },
  { id = "toggles",  label = "Object toggles" },
}

local SUB_TABS_GEN3 = {
  { id = "story",    label = "Story flags" },
  { id = "trainers", label = "Trainers" },
  { id = "items",    label = "Items taken" },
  { id = "toggles",  label = "Object toggles" },
  { id = "system",   label = "System & Badges" },
  { id = "vars",     label = "Variables" },
}

local HINTS_GEN1 = {
  flags    = "Story flags scraped from data/scripts and the trainer headers, plus any MOD_ flags a loaded mod defines.",
  trainers = "Keys look like MAP_obj_N (save.defeatedTrainers): checked means that trainer stays beaten.",
  items    = "Keys look like MAP_obj_N (save.itemsTaken): checked means that ground item is gone.",
  toggles  = "Per-map object visibility overrides (save.objectToggles), grouped by map.",
}

local HINTS_GEN3 = {
  story    = "Story and narrative event flags (NPC gifts, quest progress, boss clears, and mod flags).",
  trainers = "Trainer defeat flags (0x500 + trainerId): checked means that trainer stays beaten.",
  items    = "Overworld item balls (0x154-0x1FE) and hidden items (0x3E8-0x4A6): checked means item taken.",
  toggles  = "NPC, sprite, and obstacle hide flags (FLAG_HIDE_...): checked means the object is hidden.",
  system   = "System flags, Gym Badges (0x820-0x827), Running Shoes, National Dex, and Town Map fly points.",
  vars     = "16-bit script and story progression variables (save.vars, 0x4000-0x40FF).",
}

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

local function contains(haystack, needle)
  if needle == "" then return true end
  return tostring(haystack):lower():find(needle:lower(), 1, true) ~= nil
end

local function buildRowsGen3(S, filter)
  local tab = S.eventsTab
  if tab == "flags" then tab = "story" end
  local cats = S.game3Events or Catalog.game3Categories(S.modRoots)
  S.game3Events = cats
  local rows = {}

  if tab == "story" then
    for _, entry in ipairs(cats.story or {}) do
      local label = entry.label or entry.name
      if contains(label, filter) or contains(entry.name, filter) then
        rows[#rows + 1] = {
          label = label,
          checked = Gen.getFlag(S.save, entry.name or entry.id),
          set = function(on) Ops.setFlag(S, entry.name or entry.id, on) end,
        }
      end
    end
  elseif tab == "trainers" then
    for _, entry in ipairs(cats.trainers or {}) do
      if contains(entry.label, filter) or contains(entry.name, filter) or contains(string.format("0x%X", entry.flagId), filter) then
        rows[#rows + 1] = {
          label = entry.label,
          checked = Gen.getFlag(S.save, entry.flagId),
          set = function(on) Ops.setFlag(S, entry.flagId, on) end,
        }
      end
    end
  elseif tab == "items" then
    for _, entry in ipairs(cats.items or {}) do
      if contains(entry.label, filter) or contains(entry.name, filter) or contains(string.format("0x%X", entry.id), filter) then
        rows[#rows + 1] = {
          label = entry.label,
          checked = Gen.getFlag(S.save, entry.id or entry.name),
          set = function(on) Ops.setFlag(S, entry.id or entry.name, on) end,
        }
      end
    end
  elseif tab == "toggles" then
    for _, entry in ipairs(cats.toggles or {}) do
      if contains(entry.label, filter) or contains(entry.name, filter) or contains(string.format("0x%X", entry.id), filter) then
        rows[#rows + 1] = {
          label = entry.label,
          checked = Gen.getFlag(S.save, entry.id or entry.name),
          set = function(on) Ops.setFlag(S, entry.id or entry.name, on) end,
        }
      end
    end
  elseif tab == "system" then
    for _, entry in ipairs(cats.system or {}) do
      if contains(entry.label, filter) or contains(entry.name, filter) or contains(string.format("0x%X", entry.id), filter) then
        rows[#rows + 1] = {
          label = entry.label,
          checked = Gen.getFlag(S.save, entry.id or entry.name),
          set = function(on) Ops.setFlag(S, entry.id or entry.name, on) end,
        }
      end
    end
  elseif tab == "vars" then
    for _, entry in ipairs(cats.vars or {}) do
      if contains(entry.label, filter) or contains(entry.name, filter) or contains(string.format("0x%X", entry.id), filter) then
        local val = Gen.getVar(S.save, entry.id)
        rows[#rows + 1] = {
          isVar = true,
          label = entry.label,
          varId = entry.id,
          val = val,
          set = function(v) Ops.setVar(S, entry.id, v) end,
        }
      end
    end
  end

  return rows
end

local function buildRowsGen1(S, filter)
  local tab = S.eventsTab
  local rows = {}
  if tab == "flags" or tab == "story" then
    for _, name in ipairs(S.events or {}) do
      if contains(name, filter) then
        rows[#rows + 1] = {
          label = name,
          checked = Gen.getFlag(S.save, name),
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

local function buildRows(S)
  local filter = S.eventFilter or ""
  if Gen.of(S.save) == 3 then
    return buildRowsGen3(S, filter)
  end
  return buildRowsGen1(S, filter)
end

function M.draw(S, Kit, x, y, w, h)
  local s = Kit.scale
  local pad = 20 * s
  local gen = Gen.of(S.save)

  if gen == 3 then
    if not S.eventsTab or S.eventsTab == "flags" then S.eventsTab = "story" end
  else
    if not S.eventsTab or S.eventsTab == "story" or S.eventsTab == "system" or S.eventsTab == "vars" then
      S.eventsTab = "flags"
    end
  end
  S.eventFilter = S.eventFilter or ""

  Kit.card(x, y, w, h)
  local cx = x + pad
  local inner = w - 2 * pad

  -- ------------------------------------------------------------ sub-tabs
  local pillH = 32 * s
  local px, py = cx, y + pad
  local pills = SUB_TABS_GEN1
  local hints = HINTS_GEN1
  if gen == 3 then
    pills = SUB_TABS_GEN3
    hints = HINTS_GEN3
  elseif gen == 2 then
    pills = { SUB_TABS_GEN1[1] }
    if S.eventsTab ~= "flags" then S.eventsTab = "flags" end
  end

  for _, t in ipairs(pills) do
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
      Ops.say(S, hints[t.id] or "")
    end
    px = px + pw + 10 * s
  end

  -- The filter shares the last pill row when there is room for at least a
  -- usable field beside the pills; on a narrow window it wraps onto its own row
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
  Kit.text("small", Kit.ellipsize("small", hints[S.eventsTab] or "", inner),
    cx, hintY, PAL.caption)

  -- ---------------------------------------------------------- row grid
  local rows = buildRows(S)
  local pagerH = 30 * s
  local pagerY = y + h - pad - pagerH
  local gridTop = hintY + Kit.textHeight("small") + 14 * s
  local rowH = 34 * s
  local rowGap = 8 * s
  local colGap = 20 * s
  local cols = (inner >= 460 * s) and 2 or 1
  local colW = (inner - colGap * (cols - 1)) / cols
  local gridH = pagerY - 12 * s - gridTop
  local perCol = math.max(1, math.floor(gridH / (rowH + rowGap)))
  local perPage = perCol * cols

  S.eventsOffset = Ops.clamp(S.eventsOffset or 0, 0, math.max(0, #rows - perPage))
  S.eventsOffset = Kit.scroll(cx, gridTop, inner, gridH, S.eventsOffset,
    #rows, perPage, cols)

  if #rows == 0 then
    Kit.emptyBox(cx, gridTop, inner, math.min(gridH, 80 * s),
      S.eventFilter ~= "" and "No key matches that filter."
        or "Nothing recorded here yet.")
  end

  Kit.pushClip(cx, gridTop, inner, gridH)
  for i = 1, math.min(perPage, #rows - S.eventsOffset) do
    local row = rows[S.eventsOffset + i]
    local ci = (i - 1) % cols
    local ri = math.floor((i - 1) / cols)
    local rx = cx + ci * (colW + colGap)
    local ry = gridTop + ri * (rowH + rowGap)
    if row.header then
      Kit.text("mono", Kit.ellipsize("mono", row.label, colW),
        rx + 4 * s, ry + (rowH - Kit.textHeight("mono")) / 2, PAL.caption)
    elseif row.isVar then
      Kit.row(rx, ry, colW, rowH, false, nil, 9 * s)
      local valW = 100 * s
      local lblW = colW - valW - 16 * s
      Kit.text("mono", Kit.ellipsize("mono", row.label, lblW), rx + 12 * s,
        ry + (rowH - Kit.textHeight("mono")) / 2, PAL.text)
      local btnW = 22 * s
      local btnH = 22 * s
      local by = ry + (rowH - btnH) / 2
      local bx = rx + colW - valW - 8 * s
      if Kit.stepper(bx, by, btnW, btnH, "-", { font = "small", radius = 4 * s, enabled = row.val > 0 }) then
        row.set(math.max(0, row.val - 1))
      end
      Kit.textCenter("mono", tostring(row.val), bx + btnW,
        ry + (rowH - Kit.textHeight("mono")) / 2, valW - 2 * btnW, PAL.heading)
      if Kit.stepper(bx + valW - btnW, by, btnW, btnH, "+", { font = "small", radius = 4 * s, enabled = row.val < 65535 }) then
        row.set(math.min(65535, row.val + 1))
      end
    else
      local newChecked, changed = Kit.checkbox(rx, ry, colW, rowH,
        row.checked, row.label)
      if changed then row.set(newChecked) end
    end
  end
  Kit.popClip()

  Kit.scrollbar(cx, gridTop, inner, gridH, S.eventsOffset, #rows, perPage)

  -- "Clear all" button
  local clearKey = (S.eventsTab == "trainers" and "trainers")
    or (S.eventsTab == "items" and "items")
    or (gen == 3 and S.eventsTab == "toggles" and "toggles")
    or nil
  local clearBw = 0
  if clearKey then
    local label = (S.eventsTab == "trainers") and "Clear all trainers"
      or (S.eventsTab == "items") and "Clear all items taken"
      or "Clear all toggles"
    clearBw = Kit.textWidth("small", label) + 32 * s
    local armKey = "clear-" .. clearKey
    if Kit.button(cx + inner - clearBw, pagerY, clearBw, pagerH,
        Ops.armLabel(S, armKey, label),
        { kind = "danger", font = "small", radius = 8 * s }) then
      if clearKey == "trainers" then
        Ops.clearTrainers(S)
      elseif clearKey == "items" then
        Ops.clearItems(S)
      elseif clearKey == "toggles" then
        Ops.clearToggles(S)
      end
    end
    clearBw = clearBw + 10 * s
  end
  S.eventsOffset = Kit.pager(cx, pagerY, inner - clearBw, S.eventsOffset,
    #rows, perPage)
end

return M
