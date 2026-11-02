local Kit = require("src.ui.kit.Kit")
local Theme = require("src.ui.kit.Theme")
local Strings = require("src.core.Strings")
local GameVersion = require("src.core.GameVersion")
local Service = require("src.box.Service")
local Store = require("src.box.Store")
local Records = require("src.box.Records")
local Catalog = require("src.box.Catalog")
local Sprites = require("src.online.OnlineSprites")
local Icons = require("src.ui.kit.Icons")
local Animation = require("src.box.Animation")
local UI = require("src.import.BoxUI")

local PAL = Theme.PAL
local BoxPanel = {}
local function LV() return require("src.import.LauncherView") end

local function readPC(s)
  s.pcRows, s.pcBody, s.pcSave = {}, nil, nil
  local source = s.sources[s.sourceIndex]
  if not source or not s.service then return end
  local save, why, body = s.service:read(source)
  if not save then s.notice, s.noticeKind = why, "error"; return end
  s.pcSave, s.pcBody = save, body
  local generation = GameVersion.generation(source.version)
  for _, row in ipairs(Records.candidates(save, generation)) do
    row.entry = { version = source.version, generation = generation, mon = row.mon,
      display = Catalog.describe(source.version, row.mon) }
    row.key = Records.key(row)
    s.pcRows[#s.pcRows + 1] = row
  end
end

function BoxPanel.refresh(imp)
  UI.close(imp)
  require("src.ui.kit.Transition").clear("box")
  Catalog.reset()
  local previous = imp._boxState or {}
  local service, why = Service.open()
  local s = { service = service, notice = why or (service and service.recoveryNotice), noticeKind = why and "error" or "info",
    sources = Service.sources(),
    sourceIndex = 1, box = previous.box or 1,
    pcBox = previous.pcBox or 1, query = previous.query or "", sort = previous.sort or "slot",
    selectedBox = {}, selectedPC = {}, pageBox = 1, pagePC = 1, sourcePage = 1, filterQuery = previous.filterQuery,
    filters = previous.filters, view = previous.view or "box", multi = previous.multi ~= false,
    toolsPage = previous.toolsPage ~= "Themes" and previous.toolsPage or nil, toolsOpen = previous.toolsOpen,
    organizers = previous.organizers, stageDraft = previous.stageDraft, stageDrafts = previous.stageDrafts,
    stageUndo = previous.stageUndo, stageIndex = previous.stageIndex, stagePiece = previous.stagePiece,
    stageSection = previous.stageSection }
  local was = previous.sources and previous.sources[previous.sourceIndex]
  if was then
    for i, source in ipairs(s.sources) do
      if source.path == was.path and source.slotId == was.slotId then s.sourceIndex = i; break end
    end
  end
  local current = s.sources[s.sourceIndex]
  local total = current and GameVersion.generation(current.version) == 1 and 12 or 14
  if type(s.pcBox) ~= "number" or s.pcBox < 0 or s.pcBox > total then s.pcBox = 1 end
  imp._boxState = s
  readPC(s)
  if service and previous.service and previous.service.body == service.body and previous.selectedBox then
    s.selectedBox = previous.selectedBox
  end
  if s.pcBody and previous.pcBody == s.pcBody and previous.selectedPC and was and current
      and was.path == current.path and was.slotId == current.slotId then
    s.selectedPC = previous.selectedPC
  end
  return s
end

local function state(imp)
  return imp._boxState or BoxPanel.refresh(imp)
end

local function animateInspection(s)
  Animation.release(s.animation)
  s.animationEntry, s.animation = s.inspect, Animation.new(s.inspect)
end

local function checkDisk(s, dt)
  s._diskCheck = (s._diskCheck or 1) + math.max(0, dt or 0)
  local fs = s.service and s.service.fs
  if s._diskCheck < 1 or not fs or not fs.getInfo or not fs.read then return end
  s._diskCheck = 0
  local ok, info = pcall(fs.getInfo, Store.PATH)
  local sig = ok and type(info) == "table" and (tostring(info.size) .. ":" .. tostring(info.modtime)) or "none"
  if sig == s._diskSig and s._diskBody == s.service.body then return end
  s._diskSig, s._diskBody = sig, s.service.body
  local stale = fs.read(Store.PATH) ~= s.service.body
  if stale and not s.diskStale then
    s.notice, s.noticeKind, s.noticeSticky, s._latestBackup = "Box changed outside this screen. Reload before making changes.", "error", true, nil
  end
  s.diskStale = stale or nil
end

function BoxPanel.update(imp, dt)
  local s = imp._boxState
  if not s then return end
  checkDisk(s, dt)
  s.artTime = (s.artTime or 0) + math.max(0, dt or 0)
  if s.migrationFetch then require("src.import.BoxTools").update(s) end
  if s.animationEntry ~= s.inspect or s.animation and s.animation.released then animateInspection(s) end
  Animation.update(s.animation, dt)
  local Showcase = require("src.box.Showcase")
  if not s.toolsPage or s.toolsPage == "Pokémon" then
    local warehouse = s.service and s.service.state
    Showcase.ensureMusic(warehouse and Showcase.boxMusic(warehouse, warehouse.boxes[s.box]) or "Silent", "box")
  else
    local _, owner = Showcase.currentMusic()
    if owner == "box" then Showcase.stopMusic() end
  end
end

local function selected(t)
  local out = {}
  for _, ref in pairs(t) do out[#out + 1] = ref end
  table.sort(out, function(a, b)
    if a.where ~= b.where then return (a.where or "box") < (b.where or "box") end
    if (a.box or 0) ~= (b.box or 0) then return (a.box or 0) < (b.box or 0) end
    return (a.index or a.slot or 0) < (b.index or b.slot or 0)
  end)
  return out
end

local function perform(imp, operation, text)
  local s = state(imp)
  local called, ok, why = pcall(operation)
  if not called then why, ok = ok, nil end
  s._latestBackup = nil
  if not ok then
    s.notice, s.noticeKind = tostring(why or "Box operation failed."), "error"
    local beforeBox, beforePC = s.service and s.service.body, s.pcBody
    if s.service then
      local recovered, err = Service.open(s.service.fs)
      s.service = recovered
      if not recovered then s.notice = s.notice .. " " .. tostring(err) end
    end
    readPC(s)
    if not s.service or s.service.body ~= beforeBox or s.pcBody ~= beforePC then
      Animation.release(s.animation)
      s.animation, s.animationEntry = nil, nil
      s.selectedBox, s.selectedPC, s.moving, s.movingPC = {}, {}, nil, nil
      s.inspect, s.inspectKind, s.inspectRef, s.summary = nil, nil, nil, nil
    end
    return false
  end
  s.notice, s.noticeKind = text, "ok"
  require("src.box.Cry").stop()
  Animation.release(s.animation)
  s.animation, s.animationEntry = nil, nil
  s.selectedBox, s.selectedPC, s.moving, s.movingPC, s.inspect = {}, {}, nil, nil, nil
  s._filteredBox, s._filteredPC, s.motionFrom, s._giftProgress = nil, nil, nil, nil
  require("src.ui.kit.Transition").clear("box")
  readPC(s)
  if imp.savesChanged then
    local source = s.sources[s.sourceIndex]
    if source then imp:savesChanged(source.cartId and "cart_" .. tostring(source.cartId) or source.version) end
  end
  return true
end

function BoxPanel.importGCI(imp, bytes, why)
  local s = state(imp)
  if not bytes then s.notice, s.noticeKind = why or "The file could not be read.", "error"; return false end
  if not s.service then return false end
  return perform(imp, function() return s.service:importGCI(bytes) end, "Native Pokémon Box save imported.")
end

local function button(imp, x, y, w, h, id, text, action, active, disabled, icon)
  icon = icon or ({ summary = "eye", ["summary-back"] = "arrow-left", reload = "rotate-ccw",
    ["view-box"] = "package", ["view-pc"] = "monitor", multi = "check",
    deposit = "download", withdraw = "upload", ["select-visible"] = "check", ["clear-selection"] = "x",
    move = "arrow-left-right", rename = "pencil" })[id]
  return LV().btn(imp, x, y, w, h, "box-" .. id, Strings(text), {
    kind = active and "primary" or "ghost", font = "small",
    face = id == "multi" and "selection" or nil, active = active,
    enabled = not disabled, action = action, icon = icon,
  })
end

local function choose(imp, x, y, w, h, id, text, previous, nextOne, pick)
  local bw, gap = Kit.tapMin(), 4 * Kit.scale
  button(imp, x, y, bw, h, id .. "-prev", "", previous, false, false, "chevron-left")
  button(imp, x + w - bw, y, bw, h, id .. "-next", "", nextOne, false, false, "chevron-right")
  if pick then
    UI.button(imp, x + bw + gap, y, w - 2 * (bw + gap), h, id .. "-picker", text, pick,
      { face = "bare", trailingIcon = "chevron-down" })
  else
    Kit.textCenterBold("small", Kit.ellipsize("small", text, w - 2 * (bw + gap)),
      x + bw + gap, y + (h - Kit.textHeight("small")) / 2, w - 2 * (bw + gap), PAL.heading)
  end
end

local function rowsForPC(s)
  local cached = s._filteredPC
  if cached and cached.rows == s.pcRows and cached.box == s.pcBox and cached.query == s.query then
    return cached.result
  end
  local out, bySlot = {}, {}
  local matches = require("src.box.Search").compile(s.query)
  for _, row in ipairs(s.pcRows) do
    if (s.pcBox == 0 and row.where == "party") or (row.where == "box" and row.box == s.pcBox) then
      if s.query ~= "" then
        if matches(row.entry, row.source) then out[#out + 1] = row end
      else bySlot[row.index] = row end
    end
  end
  if s.query == "" then
    local source = s.sources[s.sourceIndex]
    local capacity = s.pcBox == 0 and 6 or source and GameVersion.generation(source.version) == 3 and 30 or 20
    for i = 1, capacity do
      local ref = { where = s.pcBox == 0 and "party" or "box", box = s.pcBox, index = i }
      ref.key = Records.key(ref)
      out[i] = bySlot[i] or ref
    end
  end
  s._filteredPC = { rows = s.pcRows, box = s.pcBox, query = s.query, result = out }
  return out
end

local function rowsForBox(s)
  local cached = s._filteredBox
  if cached and cached.state == s.service.state and cached.box == s.box
      and cached.query == s.query and cached.sort == s.sort then return cached.result end
  local out = {}
  if s.query ~= "" then
    out = Store.search(s.service.state, s.query, s.sort)
  elseif s.sort ~= "slot" then
    for _, row in ipairs(Store.search(s.service.state, "", s.sort)) do
      if row.box == s.box then out[#out + 1] = row end
    end
  else
    for slot = 1, Store.SLOTS do
      out[#out + 1] = { box = s.box, slot = slot, entry = Store.at(s.service.state, s.box, slot) }
    end
  end
  s._filteredBox = { state = s.service.state, box = s.box, query = s.query, sort = s.sort, result = out }
  return out
end

local function count(selection)
  local n = 0
  for _ in pairs(selection) do n = n + 1 end
  return n
end

local function panel(x, y, w, h, accent)
  Theme.fillRounded(x + 4, y + 7, w, h, PAL.inverse, 0.5, Theme.cardRadius())
  Theme.card(x, y, w, h, { shadow = true, stroke = accent or PAL.line, strokeA = 0.65, strokeW = 2 })
end

local function art(entry, x, y, size, small, s)
  local image, version = Catalog.art(entry)
  if not image then
    Kit.textCenterBold("small", "?", x, y + (size - Kit.textHeight("small")) / 2, size, PAL.muted)
    return
  end
  local sw, sh = size * 0.58, math.max(3, size * 0.085)
  if love.graphics.ellipse then
    Theme.col(PAL.inverse, 0.35)
    love.graphics.ellipse("fill", x + size / 2, y + size * 0.86, sw / 2, sh / 2)
  else Theme.fillRounded(x + (size - sw) / 2, y + size * 0.82, sw, sh, PAL.inverse, 0.35, sh / 2) end
  if small then
    local frame = version == "emerald" and math.floor((s.artTime or 0) * 4) or 0
    if Sprites.drawIcon(image, x, y, size, frame) then return end
  end
  if not small and s.animationEntry == entry and Animation.draw(s.animation, x, y, size) then return end
  if not Sprites.drawFront(image, x, y, size) then Sprites.drawIcon(image, x, y, size) end
end

local function checkBadge(x, y, size, checked, accent)
  if checked then
    Theme.fillRounded(x, y, size, size, accent or PAL.green, 1, 4)
    Icons.draw("check", x + 2, y + 2, size - 4, PAL.inverse, 1)
  else
    Theme.fillRounded(x, y, size, size, PAL.bg, 0.95, 4)
    Theme.strokeRounded(x, y, size, size, PAL.line, 0.6, 1, 4)
  end
end

local function inspectEntry(s, kind, row)
  s.inspect, s.inspectKind, s.inspectRef = row.entry, kind, row
  animateInspection(s)
  require("src.box.Cry").play(row.entry)
end

local function openSummary(s, imp)
  if imp then UI.change(imp, s, "summary", true) else s.summary = true end
  Kit.blur()
  animateInspection(s)
  require("src.box.Cry").play(s.inspect)
end

local function selectEntry(s, kind, row)
  local key = kind == "pc" and row.key or (row.box .. ":" .. row.slot)
  local selection = kind == "pc" and s.selectedPC or s.selectedBox
  if s.multi == false then
    local was = selection[key] ~= nil
    s.selectedPC, s.selectedBox = {}, {}
    if was then return end
    selection = kind == "pc" and s.selectedPC or s.selectedBox
  end
  if selection[key] then selection[key] = nil
  elseif kind == "pc" then selection[key] = { where = row.where, box = row.box, index = row.index }
  else selection[key] = { box = row.box, slot = row.slot } end
  inspectEntry(s, kind, row)
end

local function gridMetrics(w, m)
  local gap = math.max(3, math.floor(4 * m.s))
  local cols = w >= 620 * m.s and 12 or w >= 390 * m.s and 6 or 4
  local cellW = (w - (cols - 1) * gap) / cols
  local cellH = math.max(Kit.tapMin() + 6, math.min(cellW, (cols == 12 and 50 or 68) * m.s))
  return cols, gap, cellW, cellH, cols == 12 and Store.SLOTS or cols * 6
end

local function visibleRows(s, kind, w, m)
  local rows = kind == "pc" and rowsForPC(s) or rowsForBox(s)
  local _, _, _, _, perPage = gridMetrics(w, m)
  local first, last, page = Kit.pageBounds(kind == "pc" and s.pagePC or s.pageBox, #rows, perPage)
  return rows, first, last, page, perPage
end

local function grid(imp, s, kind, x, y, w, m)
  local rows, first, last, page, perPage = visibleRows(s, kind, w, m)
  local cols, gap, cellW, cellH = gridMetrics(w, m)
  local pageKey = kind == "pc" and "pagePC" or "pageBox"
  s[pageKey] = page
  local selection = kind == "pc" and s.selectedPC or s.selectedBox
  for i = first, last do
    local row, index = rows[i], i - first
    local entry = row.entry
    local cx = x + (index % cols) * (cellW + gap)
    local cy = y + math.floor(index / cols) * (cellH + gap)
    local key = kind == "pc" and row.key or (row.box .. ":" .. row.slot)
    local chosen = selection[key] ~= nil
    local focused = s.inspect == entry and entry ~= nil
    local emptyTarget = not entry and (kind == "box" and s.moving or kind == "pc" and s.movingPC)
    local id = "box-" .. kind .. "-" .. key
    local hot = entry and Kit.hover(cx, cy, cellW, cellH)
    local ring = Kit._ringShown and Kit.focusId == id
    if chosen or focused or hot or ring then
      local color = chosen and PAL.green or (focused or ring) and PAL.blue or PAL.line
      Theme.col(color, chosen and 0.3 or 0.15)
      if love.graphics.ellipse then
        love.graphics.ellipse("fill", cx + cellW / 2, cy + cellH * 0.7, cellW * 0.43, cellH * 0.28)
      else
        Theme.fillRounded(cx + 4, cy + cellH * 0.4, cellW - 8, cellH * 0.56, color, 0.2, 12)
      end
    end
    LV().btn(imp, cx, cy, cellW, cellH, id, "", {
      face = "bare", ring = false,
      enabled = entry ~= nil or not not emptyTarget, action = function()
        if kind == "box" and s.moving then
          local from = s.moving
          return perform(imp, function() return s.service:moveGroup(from, row.box, row.slot) end,
            "Pokémon moved.")
        end
        if kind == "pc" and s.movingPC then
          local from, source = s.movingPC, s.sources[s.sourceIndex]
          s.movingPC = nil
          return perform(imp, function()
            return s.service:movePC(source, from, { where = row.where, box = row.box, index = row.index }, s.pcBody)
          end, "Pokémon moved.")
        end
        selectEntry(s, kind, row)
      end,
    })
    if entry then
      local size = math.min(cellW - 2, cellH - 2)
      art(entry, cx + (cellW - size) / 2, cy + (cellH - size) / 2, size, true, s)
      local badge = math.max(12, math.min(18 * m.s, cellW * 0.27))
      checkBadge(cx + cellW - badge - 4, cy + 4, badge, chosen)
      if entry.display.shiny then Icons.draw("award", cx + 3, cy + 2, badge, PAL.yellow, 1) end
    else
      Kit.textCenter("micro", tostring(row.slot or row.index), cx,
        cy + (cellH - Kit.textHeight("micro")) / 2, cellW, PAL.faint)
    end
  end
  local nrows = math.max(1, math.ceil((last - first + 1) / cols))
  local height = nrows * (cellH + gap)
  if #rows == 0 then
    Kit.textWrapped("small", Strings("No Pokémon match this view."), x + 8, y + 10, w - 16, PAL.muted, 2)
  end
  if #rows > perPage then
    local h = Kit.tapMin()
    choose(imp, x, y + height, w, h, kind .. "-page",
      ("%d–%d / %d"):format(first, last, #rows),
      function() s[pageKey] = math.max(1, page - 1) end,
      function() s[pageKey] = math.min(math.ceil(#rows / perPage), page + 1) end)
    height = height + h + gap
  end
  return height
end

local TYPE_COLORS = {
  FIRE = PAL.railFireRed, WATER = PAL.buttonBlue, GRASS = PAL.railLeafGreen,
  ELECTRIC = PAL.yellow, POISON = PAL.buttonPurple, PSYCHIC = PAL.buttonPurple,
  ICE = PAL.blue, BUG = PAL.green, DRAGON = PAL.buttonPurple,
}

local function typeBadges(types, x, y, w, m, measure)
  local seen, names = {}, {}
  for name in tostring(types):gmatch("[^/]+") do
    name = name:match("^%s*(.-)%s*$"):upper()
    if name ~= "" and not seen[name] then names[#names + 1], seen[name] = name, true end
  end
  local h, gap, cx, cy = Kit.textHeight("micro") + 8 * m.s, 4 * m.s, x, y
  for _, name in ipairs(names) do
    local bw = math.min(w, Kit.textWidth("micro", name) + 16 * m.s)
    if cx > x and cx + bw > x + w then cx, cy = x, cy + h + gap end
    local color = TYPE_COLORS[name] or PAL.raised
    if not measure then
      Kit.tag(cx, cy, bw, h, name, color, {
        fill = true, bold = true, ink = (color == PAL.yellow or color == PAL.green) and PAL.inverse or PAL.heading,
      })
    end
    cx = cx + bw + gap
  end
  return #names == 0 and 0 or cy + h - y
end

local function detail(imp, s, x, y, w, m, compact, inspectOnly)
  local entry, pad = s.inspect, 12 * m.s
  local gap = 6 * m.s
  if not entry then
    local h = compact and 58 * m.s or 304 * m.s
    panel(x, y, w, h)
    if not compact then
      Icons.draw("package", x + (w - 64 * m.s) / 2, y + 54 * m.s, 64 * m.s, PAL.muted, 0.65)
    end
    Kit.textWrapped("small", Strings("Select a Pokémon to see it here."), x + pad,
      y + (compact and 12 or 148) * m.s, w - 2 * pad, PAL.muted, 2)
    return h
  end
  local name = tostring(entry.display.species)
  local nickname = entry.display.name ~= entry.display.species and tostring(entry.display.name) or nil
  local size = compact and math.max(128, 108 * m.s) or math.min(w - 2 * pad, 140 * m.s)
  local tw = compact and w - 2 * pad - size - gap or w - 2 * pad
  local item = entry.display.item ~= "" and entry.display.item or Strings("No held item")
  local fieldH = Kit.textHeight("button") + typeBadges(entry.display.types, 0, 0, tw, m, true)
    + Kit.wrapHeight("micro", item, tw, 2) + 3 * gap
  if nickname then fieldH = fieldH + Kit.wrapHeight("micro", nickname, tw, 2) + gap end
  local headerH = 48 * m.s
  local top = headerH + 8 * m.s
  local h = math.max((compact and 166 or 315) * m.s,
    top + (compact and math.max(size, fieldH + gap + Kit.tapMin())
      or size + gap + fieldH + Kit.textHeight("micro") + gap + Kit.tapMin()) + pad)
  if inspectOnly then
    h = compact and top + math.max(size, 3 * m.s + fieldH) + pad or h - Kit.tapMin() - gap
  end
  panel(x, y, w, h, PAL.blue)
  Theme.fillRounded(x + 2, y + 2, w - 4, headerH, PAL.raised, 1, 7)
  local dex = entry.display.national and ("#" .. ("%03d"):format(entry.display.national)) or ""
  local nameH, dexH = Kit.textHeight("button"), Kit.textHeight("micro")
  local headerY = y + 2 + (headerH - nameH - dexH - 2 * m.s) / 2
  Kit.textCenterBold("button", Kit.ellipsize("button", name, w - 2 * pad), x + pad, headerY, w - 2 * pad, PAL.heading)
  Kit.textCenter("micro", dex, x + pad, headerY + nameH + 2 * m.s, w - 2 * pad, PAL.muted)
  local ax = compact and x + pad or x + (w - size) / 2
  local ay = y + top
  Theme.fillRounded(ax, ay, size, size, PAL.bg, 1, 7)
  art(entry, ax, ay, size, false, s)
  local tx = compact and ax + size + gap or x + pad
  local ty = compact and ay + 3 * m.s or ay + size + gap
  Kit.textBold("button", "Lv. " .. tostring(entry.display.level), tx, ty, PAL.heading)
  ty = ty + Kit.textHeight("button") + gap
  ty = ty + typeBadges(entry.display.types, tx, ty, tw, m) + gap
  ty = ty + Kit.textWrapped("micro", item, tx, ty, tw, PAL.text, 2) + gap
  if nickname then ty = ty + Kit.textWrapped("micro", nickname, tx, ty, tw, PAL.heading, 2) + gap end
  if not compact then
    local origin = GameVersion.info(entry.version).label
    Kit.text("micro", origin .. (entry.display.egg and " · Egg" or entry.display.shiny and " · Shiny" or ""), tx, ty, PAL.muted)
  end
  local by = y + h - Kit.tapMin() - pad
  if not inspectOnly then button(imp, compact and tx or x + pad, by, compact and tw or w - 2 * pad, Kit.tapMin(),
    "summary", "Summary", function() openSummary(s, imp) end) end
  return h
end

local function summary(imp, s, x, y, w, m)
  local entry = s.inspect
  if not entry then return 0 end
  local top, gap = y, 8 * m.s
  local Details = require("src.import.BoxDetails")
  s.summarySection = s.summarySection or "Overview"
  local sectionH = math.max(m.btnH, Kit.tapMin())
  UI.dropdown(imp, x, y, w - sectionH - gap, sectionH, "summary-section", s.summarySection,
    UI.values(Details.SECTIONS, nil, "book-open"), s.summarySection,
    function(value) UI.change(imp, s, "summarySection", value) end, "book-open")
  UI.button(imp, x + w - sectionH, y, sectionH, sectionH, "summary-section-next", "", function()
    local sections, at = Details.SECTIONS, 1
    for i, name in ipairs(sections) do if name == s.summarySection then at = i end end
    UI.change(imp, s, "summarySection", sections[at % #sections + 1])
  end, { face = "invert", icon = "arrow-right" })
  y = y + sectionH + gap
  if w >= 740 * m.s then
    local cardW = math.min(w * .25, 280 * m.s)
    local cardH = detail(imp, s, x, y, cardW, m, false, true)
    local fx, fw = x + cardW + 2 * gap, w - cardW - 2 * gap
    local fieldsH = Details.draw(imp, entry, s.summarySection, fx, y, fw, m)
    y = y + math.max(cardH, fieldsH) + gap
  else
    y = y + detail(imp, s, x, y, w, m, true, true) + gap
    y = y + Details.draw(imp, entry, s.summarySection, x, y, w, m) + gap
  end
  local context = s.inspectKind == "pc" and rowsForPC(s) or rowsForBox(s)
  local neighbors, position = {}, 1
  for _, row in ipairs(context) do
    if row.entry then
      neighbors[#neighbors + 1] = row
      if row.entry == entry then position = #neighbors end
    end
  end
  local navW = (w - 2 * gap) / 3
  button(imp, x + navW + gap, y, navW, m.btnH, "summary-prev", "Previous", function()
    local row = neighbors[position - 1]
    if row then inspectEntry(s, s.inspectKind or "box", row) end
  end, false, position <= 1, "chevron-left")
  button(imp, x, y, navW, m.btnH, "summary-back", "Box", function() UI.change(imp, s, "summary", nil, -1) end)
  button(imp, x + 2 * (navW + gap), y, navW, m.btnH, "summary-next", "Next", function()
    local row = neighbors[position + 1]
    if row then inspectEntry(s, s.inspectKind or "box", row) end
  end, false, position >= #neighbors, "chevron-right")
  return y + m.btnH - top
end

local function boxName(s)
  if s.view ~= "pc" then return s.service.state.boxes[s.box].name end
  if s.pcBox == 0 then return Strings("Party") end
  local source = s.sources[s.sourceIndex]
  local name = s.pcSave and (GameVersion.generation(source.version) == 3
    and s.pcSave.storage and s.pcSave.storage.boxes and s.pcSave.storage.boxes[s.pcBox]
      and s.pcSave.storage.boxes[s.pcBox].name
    or s.pcSave.boxNames and s.pcSave.boxNames[s.pcBox])
  return name or "PC BOX " .. s.pcBox
end

local function changeBox(imp, s, delta)
  if s.view == "pc" then
    local source = s.sources[s.sourceIndex]
    local total = source and GameVersion.generation(source.version) == 1 and 12 or 14
    UI.change(imp, s, "pcBox", (s.pcBox + delta) % (total + 1), delta); s.pagePC = 1
  else
    UI.change(imp, s, "box", (s.box - 1 + delta) % Store.BOXES + 1, delta); s.pageBox, s.railFirst = 1, nil
  end
end

local function thumbnail(imp, s, x, y, w, h, m, kind, box)
  local active = s.view == kind and (kind == "pc" or s.box == box)
  local accent = kind == "pc" and PAL.blue or PAL.green
  panel(x, y, w, h, active and accent or nil)
  LV().btn(imp, x, y, w, h, "box-thumb-" .. kind .. "-" .. (box or 0), "", {
    face = "invert", fill = active and PAL.raised or PAL.surface, ring = false,
    action = function()
      if s.view ~= kind then UI.change(imp, s, "view", kind, kind == "pc" and 1 or -1)
      elseif box then UI.change(imp, s, "box", box, box >= s.box and 1 or -1) end
      s.summary = nil; if box then s.box, s.pageBox = box, 1 end
    end,
  })
  if active then Theme.strokeRounded(x + 1, y + 1, w - 2, h - 2, accent, 1, 3, 8) end
  local source = s.sources[s.sourceIndex]
  local label = kind == "pc" and (source and GameVersion.info(source.version).label .. " PC" or "Game PC") or s.service.state.boxes[box].name
  Kit.textCenterBold("micro", Kit.ellipsize("micro", label, w - 10), x + 5, y + 5 * m.s, w - 10, active and accent or PAL.heading)
  local entries, occupied, capacity = {}, 0, Store.SLOTS
  if kind == "pc" then
    capacity = s.pcBox == 0 and 6 or s.sources[s.sourceIndex]
      and GameVersion.generation(s.sources[s.sourceIndex].version) == 3 and 30 or 20
    for _, row in ipairs(s.pcRows) do
      if (s.pcBox == 0 and row.where == "party") or row.where == "box" and row.box == s.pcBox then
        entries[row.index] = row.entry; occupied = occupied + 1
      end
    end
  else
    entries = s.service.state.boxes[box].mons
    for _ in pairs(entries) do occupied = occupied + 1 end
  end
  local cols = kind == "pc" and 6 or 10
  local pad, gy = 8 * m.s, y + 27 * m.s
  local cw = (w - 2 * pad) / cols
  local gh = h - 50 * m.s
  local ch = gh / math.ceil(capacity / cols)
  for i = 1, capacity do
    local gx = x + pad + ((i - 1) % cols) * cw
    local yy = gy + math.floor((i - 1) / cols) * ch
    local entry = entries[i]
    if entry then
      local size = math.min(cw, ch)
      art(entry, gx + (cw - size) / 2, yy, size, true, s)
    else
      Theme.fillRounded(gx + cw / 2 - 1, yy + ch / 2 - 1, 2, 2, PAL.line, 0.25, 1)
    end
  end
  Kit.textCenter("micro", occupied .. " / " .. capacity, x, y + h - 20 * m.s, w, PAL.muted)
end

local function boxRail(imp, s, x, y, w, m)
  local gap, h = 8 * m.s, 120 * m.s
  local n = w >= 760 * m.s and 5 or w >= 500 * m.s and 4 or 2
  local storageN = n - 1
  local first = s.railFirst or math.floor((s.box - 1) / storageN) * storageN + 1
  first = math.max(1, math.min(first, Store.BOXES - storageN + 1))
  s.railFirst = first
  Kit.textBold("small", Strings("Your boxes"), x, y, PAL.heading)
  local bw = Kit.tapMin()
  button(imp, x + w - 2 * bw - gap, y, bw, bw, "rail-prev", "",
    function() s.railFirst = math.max(1, first - storageN) end, false, first == 1, "chevron-left")
  button(imp, x + w - bw, y, bw, bw, "rail-next", "",
    function() s.railFirst = math.min(Store.BOXES - storageN + 1, first + storageN) end,
    false, first + storageN > Store.BOXES, "chevron-right")
  y = y + bw + gap
  local tw = (w - (n - 1) * gap) / n
  thumbnail(imp, s, x, y, tw, h, m, "pc")
  for i = 1, storageN do thumbnail(imp, s, x + i * (tw + gap), y, tw, h, m, "box", first + i - 1) end
  return bw + gap + h + gap
end

local function locations(s, pc, party)
  local options = {}
  if pc then
    local source = s.sources[s.sourceIndex]
    local total = source and GameVersion.generation(source.version) == 1 and 12 or 14
    if party then options[#options + 1] = { id = 0, label = "Party", icon = "users" } end
    for b = 1, total do options[#options + 1] = { id = b, label = "PC box " .. b, icon = "monitor" } end
  else
    for b, box in ipairs(s.service.state.boxes) do
      local n = 0; for _ in pairs(box.mons) do n = n + 1 end
      options[#options + 1] = { id = b, label = box.name .. " · " .. n .. "/60", icon = "package" }
    end
  end
  return options
end

local function controls(imp, s, x, y, w, m, gridW)
  local gap, h = 6 * m.s, math.max(Kit.tapMin(), 32 * m.s)
  local kind = s.view == "pc" and "pc" or "box"
  local selection = kind == "pc" and s.selectedPC or s.selectedBox
  local source, n = s.sources[s.sourceIndex], count(selection)
  local top = y
  local target = kind == "pc" and s.service.state.boxes[s.box].name
    or (s.pcBox == 0 and "Choose a PC box" or "PC box " .. s.pcBox)
  local game = source and GameVersion.info(source.version).label or "game"
  UI.dropdown(imp, x, y, w, h, "transfer-target", "To: " .. (kind == "box" and game .. " · " or "") .. target,
    locations(s, kind == "box", false), kind == "pc" and s.box or s.pcBox, function(value)
      if kind == "pc" then s.box, s.railFirst = value, nil else s.pcBox = value end
    end, kind == "pc" and "package" or "monitor")
  y = y + h + gap
  local label = kind == "pc" and ("Store %d in Box"):format(n) or ("Send %d to game"):format(n)
  local compact = w < 560 * m.s
  local multiW, selectW = 86 * m.s, 145 * m.s
  local primaryW = compact and w - multiW - gap or w - multiW - selectW - h - 3 * gap
  button(imp, x, y, primaryW, h, kind == "pc" and "deposit" or "withdraw", label, function()
    local refs = selected(selection)
    local function transfer(repair)
      perform(imp, function()
        if kind == "pc" then return s.service:deposit(source, refs, s.box, s.pcBody, repair) end
        return s.service:withdraw(source, refs, s.pcBox, repair)
      end, repair and (kind == "pc" and "Pokémon repaired and deposited." or "Pokémon repaired and withdrawn.")
        or (kind == "pc" and "Pokémon deposited." or "Pokémon withdrawn."))
    end
    local illegal = s.service:audit(source, refs, kind)
    if #illegal == 0 then return transfer(false) end
    local options = {}
    for _, row in ipairs(illegal) do
      local fixes = {}
      for _, fix in ipairs(row.fixes) do fixes[#fixes + 1] = fix.label end
      options[#options + 1] = { id = "info-" .. #options, label = tostring(row.name) .. ": " .. table.concat(fixes, ", "),
        icon = "triangle-alert", disabled = true }
    end
    options[#options + 1] = { id = "repair", label = kind == "pc" and "Repair and store" or "Repair and send", icon = "check" }
    options[#options + 1] = { id = "cancel", label = "Cancel", icon = "x" }
    UI.open(imp, #illegal == 1 and "Repair illegal Pokémon?" or ("Repair %d illegal Pokémon?"):format(#illegal),
      options, nil, function(id) if id == "repair" then transfer(true) end end)
  end, true, n == 0 or not source or kind == "box" and s.pcBox == 0)
  button(imp, x + primaryW + gap, y, 86 * m.s, h, "multi", "Multi",
    function() s.multi = s.multi == false end, s.multi ~= false)
  local bx = x + primaryW + multiW + 2 * gap
  if compact then y = y + h + gap; bx = x end
  local clearW = h
  button(imp, bx, y, compact and w - clearW - gap or selectW, h, "select-visible", "Select visible", function()
    local rows, first, last = visibleRows(s, kind, gridW, m)
    for i = first, last do
      local row = rows[i]
      if row.entry then
        local key = kind == "pc" and row.key or row.box .. ":" .. row.slot
        selection[key] = kind == "pc" and { where = row.where, box = row.box, index = row.index }
          or { box = row.box, slot = row.slot }
      end
    end
    s.multi = true
  end)
  button(imp, x + w - clearW, y, clearW, h, "clear-selection", "", function()
    s.selectedPC, s.selectedBox = {}, {}
  end, false, count(s.selectedPC) + count(s.selectedBox) == 0)
  return y + h + gap - top
end

local function drawBody(imp, s, x, y, w, _, m)
  s.view = s.view or "box"
  local top, gap, pad = y, 8 * m.s, 10 * m.s
  local rowH = math.max(Kit.tapMin(), 32 * m.s)
  Kit.textBold("button", Strings(s.summary and "SUMMARY" or "BOX"), x, y, PAL.heading)
  if s.service then
    Kit.textRight("small", ("%d / %d"):format(Store.count(s.service.state), Store.BOXES * Store.SLOTS), x + w, y + 3, PAL.muted)
  end
  y = y + Kit.textHeight("button") + gap
  if s.notice and not s.service then y = y + Kit.textWrapped("small", Strings(s.notice), x, y, w, PAL.red, 3) + gap end
  local queryAffectsPage = not s.summary and (not s.toolsPage or s.toolsPage=="List"
    or s.toolsPage=="Filters" or s.toolsPage=="Showcase"
    or s.toolsPage=="Arrange" and s.arrangeSection=="Move")
  if queryAffectsPage and s.query and s.query ~= "" then
    local filtered = s.filterQuery == s.query
    local label = filtered and "Filters applied" or ("Search: " .. s.query)
    Icons.draw(filtered and "list-filter" or "search", x, y, 14 * m.s, PAL.blue, 1)
    Kit.text("micro", Kit.ellipsize("micro", label, w - 24 * m.s), x + 22 * m.s, y, PAL.muted)
    y = y + Kit.textHeight("micro") + gap
  end
  if s.service and s.summary then return y - top + summary(imp, s, x, y, w, m) end
  local source = s.sources[s.sourceIndex]
  local wide = w >= 740 * m.s
  local tools = require("src.import.BoxTools")
  local inlineTools = wide and s.service and not s.summary
  local sourceW = inlineTools and (w - gap) * .58 or w
  local headerH = inlineTools and math.max(m.btnH, rowH) or rowH
  local options = {}; for i, save in ipairs(s.sources) do options[i] = { id = i, label = save.label, icon = "gamepad-2" } end
  UI.dropdown(imp, x, y, sourceW - headerH - gap, headerH, "choose-save", source and "Game: " .. source.label or "Choose a game",
    options, s.sourceIndex, function(index)
      if index == s.sourceIndex then return end
      UI.change(imp, s, "sourceIndex", index)
      s.pcBox, s.pagePC, s.selectedPC, s.movingPC = 1, 1, {}, nil
      if s.inspectKind == "pc" then s.inspect, s.inspectKind, s.inspectRef = nil, nil, nil end
      if not s.toolsPage then s.view = "pc" end
      readPC(s)
    end, "gamepad-2")
  button(imp, x + sourceW - headerH, y, headerH, headerH, "reload", "", function() BoxPanel.refresh(imp) end)
  if not s.service then return y + headerH - top end
  if inlineTools then tools.navigation(imp, s, x + sourceW + gap, y, w - sourceW - gap, m) end
  y = y + headerH + gap
  local toolsH, toolsPage = tools.draw(imp, s, x, y, w, m, {
    button = button, perform = perform, selected = selected, selectEntry = selectEntry,
    openSummary = function(target) openSummary(target, imp) end,
    navigationDone = inlineTools,
  })
  y = y + toolsH
  if toolsPage then return y - top end
  local optionW = 112 * m.s
  local qx, qy, qw = x, y, w - optionW - 2 * rowH - 3 * gap
  local query = Kit.textfield("box-search", qx, qy, qw, rowH, s.query, Strings("Search Pokémon"))
  if query ~= s.query then s.query, s.pageBox, s.pagePC = query, 1, 1 end
  UI.button(imp, x + qw + gap, y, rowH, rowH, "sort", "", function()
    local tools = require("src.import.BoxTools")
    UI.open(imp, "Sort", UI.values(tools.SORTS, tools.SORT_LABELS, "arrow-up-down"), s.sort,
      function(value) s.sort, s.pageBox = value, 1 end)
  end, { icon = "arrow-up-down" })
  UI.button(imp, x + qw + rowH + 2 * gap, y, rowH, rowH, "filters", "", function()
    UI.change(imp, s, "toolsPage", "Filters")
  end, { icon = "list-filter" })
  local actionOptions = {
    { label = "Rename this Box", icon = "pencil", action = function()
      require("src.import.BoxPrompt").open(imp, "Box name", s.service.state.boxes[s.box].name, 32,
        function(value) perform(imp, function() return s.service:rename(s.box, value) end, "Box renamed.") end)
    end },
    { label = "Select whole Box", icon = "check", action = function()
      s.selectedBox, s.multi = {}, true
      for slot in pairs(s.service.state.boxes[s.box].mons) do s.selectedBox[s.box .. ":" .. slot] = { box = s.box, slot = slot } end
    end },
    { label = "Box theme", icon = "paintbrush", action = function()
      local box = s.service.state.boxes[s.box]
      local options = UI.values(Store.THEMES, nil, "paintbrush")
      for _, option in ipairs(options) do option.disabled = option.id == "Showcase" and not box.wallpaper end
      for index, stage in pairs(s.service.state.stages or {}) do
        options[#options + 1] = { label = "Stage " .. index .. " · " .. stage.name, icon = "paintbrush", action = function()
          perform(imp, function() return s.service:exportStage(index, s.box) end, "Showcase wallpaper saved.")
        end }
      end
      UI.open(imp, "Box theme", options, box.theme or "Launcher", function(theme)
        perform(imp, function() return s.service:theme(s.box, theme, theme == "Showcase" and box.wallpaper or nil) end, "Theme saved.")
      end)
    end },
  }
  UI.dropdown(imp, x + w - optionW, y, optionW, rowH, "options", "Options", actionOptions, nil, nil, "ellipsis")
  y = qy + rowH + gap
  local kind = s.view == "pc" and "pc" or "box"
  local selection = kind == "pc" and s.selectedPC or s.selectedBox
  local mainY = y
  local detailW = wide and math.min(w * 0.22, 230 * m.s) or w
  local gx, gw = wide and x + detailW + gap or x, wide and w - detailW - gap or w
  local detailH
  if wide then detailH = detail(imp, s, x, y, detailW, m, false)
  else y = y + detail(imp, s, x, y, w, m, true) + gap end
  local stageY = y
  local gridW = gw - 2 * pad
  local rows, first, last = visibleRows(s, kind, gridW, m)
  local cols, cg, _, ch, perPage = gridMetrics(gridW, m)
  local gridH = math.max(1, math.ceil((last - first + 1) / cols)) * (ch + cg)
  if #rows > perPage then gridH = gridH + Kit.tapMin() + cg end
  local stageH = 2 * pad + (wide and rowH + gap or 2 * (rowH + gap)) + gridH
  panel(gx, stageY, gw, stageH, kind == "box" and PAL.green or PAL.blue)
  if kind == "box" then
    require("src.box.Themes").draw(s.service.state.boxes[s.box], gx + pad, stageY + pad,
      gw - 2 * pad, stageH - 2 * pad, m.s)
  end
  local tabW = wide and 140 * m.s or (gw - 2 * pad - gap) / 2
  button(imp, gx + pad, y + pad, tabW, rowH, "view-box", "Box storage", function() UI.change(imp, s, "view", "box", -1) end, kind == "box")
  button(imp, gx + pad + tabW + gap, y + pad, tabW, rowH, "view-pc", "Game PC", function() UI.change(imp, s, "view", "pc", 1) end, kind == "pc")
  local selectorX, selectorW = gx + pad, gridW
  if wide then selectorX = selectorX + 2 * (tabW + gap); selectorW = gridW - 2 * (tabW + gap) end
  local selectorY = y + pad + (wide and 0 or rowH + gap)
  local movingKey = kind == "pc" and "movingPC" or "moving"
  if s[movingKey] or count(selection) > 0 then
    local moving = s[movingKey]
    local moveW = math.min(150 * m.s, selectorW * .3)
    if moving then
      local glow = 0.45 + 0.4 * math.sin(Kit.time * 5)
      Theme.strokeRounded(selectorX - 3, selectorY - 3, moveW + 6, rowH + 6, PAL.yellow, glow, 3 * m.s)
    end
    button(imp, selectorX, selectorY, moveW, rowH, "move", moving and "Move where?" or "Move", function()
      if s[movingKey] then return end
      s[movingKey] = selected(selection); s.query = ""
      if kind == "box" then s.sort = "slot" end
      s.notice, s.noticeKind = kind == "box" and "Pick the first destination slot. Occupied slots swap back."
        or "Pick a slot. The Pokémon fill that slot and the next free ones.", "info"
    end, moving ~= nil)
    local used = moveW + gap
    if moving then
      local cancelW = math.min(110 * m.s, selectorW * .2)
      LV().btn(imp, selectorX + used, selectorY, cancelW, rowH, "box-move-cancel", Strings("Cancel"), {
        kind = "danger", font = "small", icon = "x",
        action = function() s[movingKey] = nil; UI.toast(imp, nil) end,
      })
      used = used + cancelW + gap
    end
    selectorX, selectorW = selectorX + used, selectorW - used
  end
  local suffix = " · " .. count(selection) .. " selected"
  local titleW = selectorW - 2 * (Kit.tapMin() + 4 * Kit.scale)
  local title = Kit.ellipsize("small", boxName(s), math.max(0, titleW - Kit.textWidth("small", suffix))) .. suffix
  choose(imp, selectorX, selectorY, selectorW, rowH, "active-box", title,
    function() changeBox(imp, s, -1) end, function() changeBox(imp, s, 1) end, function()
      local pc = s.view == "pc"
      UI.open(imp, pc and "Game PC" or "Box storage", locations(s, pc, true), pc and s.pcBox or s.box, function(value)
        UI.change(imp, s, pc and "pcBox" or "box", value)
        s.pageBox, s.pagePC, s.railFirst = 1, 1, nil
      end)
    end)
  y = selectorY + rowH + gap
  grid(imp, s, kind, gx + pad, y, gridW, m)
  y = (wide and math.max(stageY + stageH, mainY + detailH) or stageY + stageH) + gap
  y = y + controls(imp, s, x, y, w, m, gridW)
  y = y + boxRail(imp, s, x, y, w, m)
  return y - top
end

function BoxPanel.draw(imp, x, y, w, h, m)
  local current = state(imp)
  if current.notice and current.service then
    UI.toast(imp, current.notice, current.noticeKind, current.noticeSticky)
    current.notice, current.noticeKind, current.noticeSticky = nil, nil, nil
  end
  local f=imp._boxOrganizerFooter
  if f and imp._boxState==f.s and f.s.toolsPage=="Arrange" then
    Kit.occlude(f.x,f.y-10*m.s,f.w,f.h+20*m.s)
  end
  imp._boxOrganizerFooter = nil
  return UI.pages(imp, state(imp), x, y, w, h, m, drawBody)
end

function BoxPanel.textinput(imp, text)
  if imp._boxPopup then
    if Kit.focus == "box-chooser-filter" then Kit.textinput(text) end
    return true
  end
  if imp.tab ~= "box" or Kit.focus ~= "box-search" then return false end
  Kit.textinput(text)
  return true
end

function BoxPanel.keypressed(imp, key)
  if imp.tab ~= "box" or Kit.focus ~= "box-search" then return false end
  Kit.keypressed(key)
  return true
end

return BoxPanel
