-- Items panel: money, the shared item picker, badges, the configurable bag
-- (Bag.add/remove, ordered by Bag.order) and PC item storage (a plain
-- S.save.pcItems dict with no slot cap).
--
-- The picker is a searchable list rather than the old pair of arrows that
-- cycled one id at a time through ~250 items, which was the single worst
-- interaction in the editor.  It scrolls under the mouse wheel too (#595):
-- typing used to be the only way to reach an id past the first screenful.
-- Badges sit in the wallet column as toggle chips because they are boolean
-- inventory flags, not stackable items, and must not look like quantity rows.
--
-- #715 reflow: side by side the wallet column plus the two quantity lists
-- need about 900 real px (a quantity row's -/+/x cluster alone is ~110px).
-- Below that the five cards stack in one full-width column that scrolls in
-- pixels (Kit.scrollPixels); the inner lists keep their own wheel/drag
-- regions, which claim the notch first when the pointer is over them.

local Bag = require("src.inventory.Bag")
local Theme = require("Theme")
local Ops = require("Ops")
local Gen = require("Gen")
local PAL = Theme.PAL

local M = {}

local MONEY_STEPS = { -1000, -100, 100, 1000 }

-- One quantity row shape, shared by the bag and the PC list: id, qty, then
-- the -/+/drop cluster.  Returns true when the row body was clicked.
local function quantityRow(S, Kit, x, y, w, h, id, qty, selected, onMinus, onPlus, onDrop)
  local s = Kit.scale
  local clicked = Kit.row(x, y, w, h, selected, PAL.blue, 9 * s)
  local btn = 24 * s
  local bx = x + w - 10 * s - 3 * btn - 2 * (6 * s)
  if Kit.stepper(bx, y + (h - btn) / 2, btn, btn, "-", { font = "small" }) then
    onMinus()
  end
  if Kit.stepper(bx + btn + 6 * s, y + (h - btn) / 2, btn, btn, "+",
      { font = "small" }) then
    onPlus()
  end
  if Kit.button(bx + 2 * (btn + 6 * s), y + (h - btn) / 2, btn, btn, "x",
      { kind = "danger", font = "tiny", radius = 6 * s }) then
    onDrop()
  end
  local qtyText = ("x%d"):format(qty)
  local qtyW = Kit.textWidth("monoRow", qtyText)
  Kit.textRight("monoRow", qtyText, bx - 10 * s,
    y + (h - Kit.textHeight("monoRow")) / 2, PAL.heading)
  local label = id
  if Gen.of(S.save) == 2 then
    label = (Bag.pocketOf(id, S.data) or "ITEM") .. "  " .. id
  end
  Kit.text("mono", Kit.ellipsize("mono", label, bx - qtyW - 30 * s - (x + 10 * s)),
    x + 10 * s, y + (h - Kit.textHeight("mono")) / 2, PAL.text)
  return clicked
end

-- ---------------------------------------------------------------- sections
-- Each card is a function of its own rect so the wide (three column) and the
-- stacked (#715) layouts are the same drawing code with different geometry.

local function moneyHeight(Kit, s, pad, S)
  local h = pad * 2 + Kit.textHeight("caption") + 8 * s
    + Kit.textHeight("headline") + 10 * s + 30 * s
  if S and Gen.of(S.save) == 2 then
    h = h + 28 * s
  end
  return h
end

local function drawMoney(S, Kit, x, y, w, h)
  local s = Kit.scale
  local pad = 16 * s
  Kit.card(x, y, w, h)
  Kit.caption(x + pad, y + pad, "MONEY")
  local maxW = 74 * s
  if Kit.button(x + w - pad - maxW, y + pad - 4 * s, maxW, 26 * s, "Max out",
      { kind = "accent", font = "tiny", radius = 7 * s,
        enabled = Gen.money(S.save) < Ops.MONEY_MAX }) then
    Ops.maxMoney(S)
  end
  Kit.text("headline", ("$%d"):format(Gen.money(S.save)), x + pad,
    y + pad + Kit.textHeight("caption") + 8 * s, PAL.yellow)
  if Gen.of(S.save) == 2 then
    Kit.text("mono", ("COINS %d"):format(Gen.coins(S.save)), x + pad + 160 * s,
      y + pad + Kit.textHeight("caption") + 8 * s, PAL.muted)
    if Kit.button(x + w - pad - 74 * s, y + pad + 26 * s, 74 * s, 22 * s, "+100 coins",
        { kind = "ghost", font = "tiny", radius = 6 * s }) then
      Ops.addCoins(S, 100)
    end
  end
  local mbY = y + h - pad - 30 * s
  local mbW = (w - 2 * pad - 3 * 8 * s) / 4
  for i, delta in ipairs(MONEY_STEPS) do
    local label = (delta > 0 and "+" or "") .. tostring(delta)
    if Kit.button(x + pad + (i - 1) * (mbW + 8 * s), mbY, mbW, 30 * s, label,
        { kind = "accent", font = "tiny", radius = 8 * s }) then
      Ops.addMoney(S, delta)
    end
  end
end

-- engine/menus/init_gender.asm:55-56
local GENDERS = { { "BOY", "male" }, { "GIRL", "female" } }

local function trainerHeight(Kit, s, pad)
  return pad * 2 + Kit.textHeight("caption") + 10 * s + 28 * s
end

local function drawTrainer(S, Kit, x, y, w, h)
  local s = Kit.scale
  local pad = 16 * s
  Kit.card(x, y, w, h)
  Kit.caption(x + pad, y + pad, "TRAINER")
  Kit.textRight("mono", tostring((S.save.player and S.save.player.name) or "?"),
    x + w - pad, y + pad, PAL.caption)
  local cy = y + pad + Kit.textHeight("caption") + 10 * s
  local chipW = (w - 2 * pad - 8 * s) / 2
  local gender = Gen.playerGender(S.save)
  for i, pair in ipairs(GENDERS) do
    if Kit.chip(x + pad + (i - 1) * (chipW + 8 * s), cy, chipW, 28 * s,
        pair[1], gender == pair[2], PAL.green, PAL.steel) then
      Ops.setPlayerGender(S, pair[2])
    end
  end
end

local BADGE_COLS = 4

local function badgeHeight(S, Kit, s, pad)
  local badgeRows = math.ceil(#Ops.badgeIds(S) / BADGE_COLS)
  return pad * 2 + Kit.textHeight("caption") + 10 * s
    + badgeRows * (28 * s + 7 * s) - 7 * s
end

local function drawBadges(S, Kit, x, y, w, h)
  local s = Kit.scale
  local pad = 16 * s
  local badgeIds = Ops.badgeIds(S)
  Kit.card(x, y, w, h)
  local earned = 0
  for _, id in ipairs(badgeIds) do
    if Gen.hasBadge(S.save, id) then earned = earned + 1 end
  end
  Kit.caption(x + pad, y + pad, "BADGES")
  Kit.textRight("mono", ("%d/%d"):format(earned, #badgeIds), x + w - pad,
    y + pad, PAL.caption)
  local bTop = y + pad + Kit.textHeight("caption") + 10 * s
  local bW = (w - 2 * pad - (BADGE_COLS - 1) * 7 * s) / BADGE_COLS
  for i, id in ipairs(badgeIds) do
    local bc = (i - 1) % BADGE_COLS
    local br = math.floor((i - 1) / BADGE_COLS)
    local on = Gen.hasBadge(S.save, id)
    local short = id:gsub("BADGE$", "")
    if Kit.chip(x + pad + bc * (bW + 7 * s), bTop + br * (28 * s + 7 * s),
        bW, 28 * s, Kit.ellipsize("micro", short, bW - 8 * s), on,
        PAL.green, PAL.steel) then
      Ops.toggleBadge(S, id)
    end
  end
end

-- The "add an item" card.  It used to hold the whole catalog inline: a search
-- field plus a scrolling list, sharing this tab's height with the bag and PC
-- lists beside it, which on a phone left about three catalog rows visible.
-- Adding a Pokemon was already a full-screen modal; adding an item now opens
-- the same kind (panels/ItemPicker.lua), so this card is just the door.
local function drawPicker(S, Kit, x, y, w, h)
  local s = Kit.scale
  local pad = 16 * s
  Kit.card(x, y, w, h)
  Kit.caption(x + pad, y + pad, "ADD ITEM")
  local cy = y + pad + Kit.textHeight("caption") + 10 * s
  local inner = w - 2 * pad

  Kit.text("mono", Kit.ellipsize("mono",
    "Search the full item list and add to the bag or the PC.", inner),
    x + pad, cy, PAL.muted)
  cy = cy + Kit.textHeight("mono") + 12 * s

  local btnH = math.max(34 * s, 34)
  local half = (inner - 8 * s) / 2
  if Kit.button(x + pad, cy, half, btnH, "+ Add to bag",
      { font = "small", kind = "primary" }) then
    Ops.openItemPicker(S, Kit, "bag")
  end
  if Kit.button(x + pad + half + 8 * s, cy, half, btnH, "+ Add to PC",
      { font = "small", kind = "accent" }) then
    Ops.openItemPicker(S, Kit, "pc")
  end
end

-- The bag and PC cards share one shape: a caption line, an optional meter,
-- a quantity-row list with wheel/drag + pager.
local function drawQuantityCard(S, Kit, x, y, w, h, cfg)
  local s = Kit.scale
  local pad = 16 * s
  Kit.card(x, y, w, h)
  Kit.caption(x + pad, y + pad, cfg.title)
  Kit.textRight("mono", cfg.counter, x + w - pad, y + pad, PAL.caption)
  local rowsTop = y + pad + Kit.textHeight("caption") + 8 * s
  if cfg.meterFrac then
    Kit.meter(x + pad, rowsTop, w - 2 * pad, 5 * s, cfg.meterFrac * 100,
      cfg.meterFrac >= 1 and PAL.yellow or PAL.blue)
    rowsTop = rowsTop + 5 * s + 12 * s
  else
    rowsTop = rowsTop + 12 * s
  end

  local pagerH = 30 * s
  local pagerY = y + h - pad - pagerH
  local rowH = 36 * s
  local rowGap = 6 * s
  local listH = pagerY - 12 * s - rowsTop
  local perPage = math.max(1, math.floor(listH / (rowH + rowGap)))
  local order = cfg.order
  local offset = Ops.clamp(cfg.offset or 0, 0, math.max(0, #order - perPage))
  -- the wheel moves the same offset the pager below does (#595)
  offset = Kit.scroll(x + pad, rowsTop, w - 2 * pad, listH, offset, #order, perPage)

  if #order == 0 then
    Kit.emptyBox(x + pad, rowsTop, w - 2 * pad, math.min(listH, 70 * s), cfg.empty)
  end
  Kit.pushClip(x + pad, rowsTop, w - 2 * pad, listH)
  for i = 1, math.min(perPage, #order - offset) do
    local id = order[offset + i]
    local ry = rowsTop + (i - 1) * (rowH + rowGap)
    if quantityRow(S, Kit, x + pad, ry, w - 2 * pad, rowH, id,
        cfg.qty(id), id == cfg.selected(),
        function() cfg.adjust(id, -1) end,
        function() cfg.adjust(id, 1) end,
        function() cfg.drop(id) end) then
      cfg.select(id)
    end
  end
  Kit.popClip()
  Kit.scrollbar(x + pad, rowsTop, w - 2 * pad, listH, offset, #order, perPage)
  return Kit.pager(x + pad, pagerY, w - 2 * pad, offset, #order, perPage)
end

local function drawBag(S, Kit, x, y, w, h)
  local order = Bag.order(S.save)
  local capacity = Bag.capacity(S.data)
  S.bagOffset = drawQuantityCard(S, Kit, x, y, w, h, {
    title = "BAG",
    counter = ("%d/%d slots"):format(Bag.slots(S.save), capacity),
    meterFrac = Bag.slots(S.save) / capacity,
    order = order,
    offset = S.bagOffset,
    empty = "Bag is empty.",
    qty = function(id) return S.save.inventory[id] or 0 end,
    selected = function() return S.selectedBagId end,
    select = function(id)
      S.selectedBagId = id
      Ops.say(S, ("Selected %s in the bag"):format(id))
    end,
    adjust = function(id, d) Ops.bagAdjust(S, id, d) end,
    drop = function(id) Ops.bagDrop(S, id) end,
  })
end

local function drawPc(S, Kit, x, y, w, h)
  local pcOrder = Ops.pcOrder(S)
  S.pcOffset = drawQuantityCard(S, Kit, x, y, w, h, {
    title = "PC STORAGE",
    counter = ("%d kinds"):format(#pcOrder),
    order = pcOrder,
    offset = S.pcOffset,
    empty = "PC storage is empty. Items sent here have no slot cap.",
    qty = function(id) return S.save.pcItems[id] or 0 end,
    selected = function() return S.selectedPcId end,
    select = function(id)
      S.selectedPcId = id
      Ops.say(S, ("Selected %s in PC storage"):format(id))
    end,
    adjust = function(id, d) Ops.pcAdjust(S, id, d) end,
    drop = function(id) Ops.pcDrop(S, id) end,
  })
end

function M.draw(S, Kit, x, y, w, h)
  local s = Kit.scale
  local gap = 20 * s
  local pad = 16 * s
  Ops.pcItems(S)

  if w < 900 * s then
    -- stacked (#715): one full-width column, scrolled in pixels.  The offset
    -- from LAST frame's scrollPixels call positions this frame, and the call
    -- itself comes after the cards so their inner lists claim the wheel or a
    -- drag over their own bodies first.
    local off = Theme.clamp(S.itemsScroll or 0, 0,
      math.max(0, (S._itemsContentH or 0) - h))
    local moneyH = moneyHeight(Kit, s, pad, S)
    local badgeH = badgeHeight(S, Kit, s, pad)
    local pickH = 280 * s
    local listH = 300 * s
    Kit.pushClip(x, y, w, h)
    local cy = y - off
    if Gen.hasPlayerGender(S.save, S.version) then
      local trainerH = trainerHeight(Kit, s, pad)
      drawTrainer(S, Kit, x, cy, w, trainerH); cy = cy + trainerH + gap
    end
    drawMoney(S, Kit, x, cy, w, moneyH);      cy = cy + moneyH + gap
    drawPicker(S, Kit, x, cy, w, pickH);      cy = cy + pickH + gap
    drawBadges(S, Kit, x, cy, w, badgeH);     cy = cy + badgeH + gap
    drawBag(S, Kit, x, cy, w, listH);         cy = cy + listH + gap
    drawPc(S, Kit, x, cy, w, listH);          cy = cy + listH
    Kit.popClip()
    S._itemsContentH = (cy + off) - y
    S.itemsScroll = Kit.scrollPixels(x, y, w, h, off, S._itemsContentH)
    return
  end

  local leftW = math.max(260 * s, math.min(320 * s, w * 0.26))
  local listW = (w - leftW - 2 * gap) / 2
  local bagX = x + leftW + gap
  local pcX = bagX + listW + gap

  -- Money and badges are fixed-height so the picker gets every pixel left
  -- over: cycling through ~250 item ids in a two-row list was the thing that
  -- made the old panel unusable.
  local moneyH = moneyHeight(Kit, s, pad, S)
  local badgeH = badgeHeight(S, Kit, s, pad)
  local topH = 0
  if Gen.hasPlayerGender(S.save, S.version) then
    topH = trainerHeight(Kit, s, pad) + gap
    drawTrainer(S, Kit, x, y, leftW, topH - gap)
  end
  drawMoney(S, Kit, x, y + topH, leftW, moneyH)
  drawPicker(S, Kit, x, y + topH + moneyH + gap, leftW,
    h - topH - moneyH - badgeH - 2 * gap)
  drawBadges(S, Kit, x, y + h - badgeH, leftW, badgeH)
  drawBag(S, Kit, bagX, y, listW, h)
  drawPc(S, Kit, pcX, y, listW, h)
end

return M
