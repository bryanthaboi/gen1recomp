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

local Bag = require("src.inventory.Bag")
local Theme = require("Theme")
local Ops = require("Ops")
local PAL = Theme.PAL

local M = {}

local MONEY_STEPS = { -1000, -100, 100, 1000 }

local function matches(id, query)
  if query == "" then return true end
  return id:lower():find(query:lower(), 1, true) ~= nil
end

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
  Kit.text("mono", Kit.ellipsize("mono", id, bx - qtyW - 30 * s - (x + 10 * s)),
    x + 10 * s, y + (h - Kit.textHeight("mono")) / 2, PAL.text)
  return clicked
end

function M.draw(S, Kit, x, y, w, h)
  local s = Kit.scale
  local gap = 20 * s
  local pad = 16 * s
  Ops.pcItems(S)

  local leftW = math.max(260 * s, math.min(320 * s, w * 0.26))
  local listW = (w - leftW - 2 * gap) / 2
  local bagX = x + leftW + gap
  local pcX = bagX + listW + gap

  -- ------------------------------------------------------------- money
  -- Money and badges are fixed-height so the picker gets every pixel left
  -- over: cycling through ~250 item ids in a two-row list was the thing that
  -- made the old panel unusable.
  local moneyH = pad * 2 + Kit.textHeight("caption") + 8 * s
    + Kit.textHeight("headline") + 10 * s + 30 * s
  Kit.card(x, y, leftW, moneyH)
  Kit.caption(x + pad, y + pad, "MONEY")
  local maxW = 74 * s
  if Kit.button(x + leftW - pad - maxW, y + pad - 4 * s, maxW, 26 * s, "Max out",
      { kind = "accent", font = "tiny", radius = 7 * s,
        enabled = (S.save.money or 0) < Ops.MONEY_MAX }) then
    Ops.maxMoney(S)
  end
  Kit.text("headline", ("$%d"):format(S.save.money or 0), x + pad,
    y + pad + Kit.textHeight("caption") + 8 * s, PAL.yellow)
  local mbY = y + moneyH - pad - 30 * s
  local mbW = (leftW - 2 * pad - 3 * 8 * s) / 4
  for i, delta in ipairs(MONEY_STEPS) do
    local label = (delta > 0 and "+" or "") .. tostring(delta)
    if Kit.button(x + pad + (i - 1) * (mbW + 8 * s), mbY, mbW, 30 * s, label,
        { kind = "accent", font = "tiny", radius = 8 * s }) then
      Ops.addMoney(S, delta)
    end
  end

  -- ------------------------------------------------------------ picker
  local badgeIds = Ops.badgeIds(S)
  local badgeCols = 4
  local badgeRows = math.ceil(#badgeIds / badgeCols)
  local badgeH = pad * 2 + Kit.textHeight("caption") + 10 * s
    + badgeRows * (28 * s + 7 * s) - 7 * s
  local pickY = y + moneyH + gap
  local pickH = h - moneyH - badgeH - 2 * gap
  Kit.card(x, pickY, leftW, pickH)
  Kit.caption(x + pad, pickY + pad, "ADD ITEM")
  local qy = pickY + pad + Kit.textHeight("caption") + 8 * s
  local prevQuery = S.itemQuery or ""
  S.itemQuery = Kit.textfield("item-query", x + pad, qy, leftW - 2 * pad, 32 * s,
    S.itemQuery or "", "search item ids...")
  -- a new query is a new list: keep the first hit on screen rather than
  -- leaving the view parked wherever the old result set had scrolled to
  if S.itemQuery ~= prevQuery then S.itemPickOffset = 0 end

  local choices = {}
  for _, id in ipairs(S.cat.items) do
    if not Ops.isBadgeId(id) and matches(id, S.itemQuery) then
      choices[#choices + 1] = id
    end
  end
  if not S.selectedItemId or not matches(S.selectedItemId, S.itemQuery) then
    S.selectedItemId = choices[1]
  end

  local addH = 32 * s
  local addY = pickY + pickH - pad - addH
  local listTop = qy + 32 * s + 10 * s
  local listBottom = addY - 10 * s
  local cRowH = 28 * s
  local cGap = 5 * s
  local visible = math.max(1, math.floor((listBottom - listTop) / (cRowH + cGap)))
  -- #595: the wheel drives the same offset a pager would, so the whole
  -- catalog is reachable with the mouse alone.  Kit.scroll clamps, which is
  -- also what pulls the view back when a narrower query shortens the list.
  S.itemPickOffset = Kit.scroll(x + pad, listTop, leftW - 2 * pad,
    listBottom - listTop, S.itemPickOffset or 0, #choices, visible)
  Kit.pushClip(x + pad, listTop, leftW - 2 * pad, listBottom - listTop)
  for i = 1, math.min(visible, #choices - S.itemPickOffset) do
    local id = choices[S.itemPickOffset + i]
    local ry = listTop + (i - 1) * (cRowH + cGap)
    if Kit.row(x + pad, ry, leftW - 2 * pad, cRowH, id == S.selectedItemId,
        PAL.green, 8 * s) then
      S.selectedItemId = id
      Ops.say(S, "Picked " .. id)
    end
    Kit.text("mono", Kit.ellipsize("mono", id, leftW - 2 * pad - 20 * s),
      x + pad + 10 * s, ry + (cRowH - Kit.textHeight("mono")) / 2, PAL.text)
  end
  Kit.popClip()
  -- the position counter rides the caption line, where it can never collide
  -- with the list body or the two add buttons below it
  if #choices > visible then
    Kit.textRight("micro", ("%d-%d of %d"):format(S.itemPickOffset + 1,
      math.min(S.itemPickOffset + visible, #choices), #choices),
      x + leftW - pad, pickY + pad, PAL.faint)
  elseif #choices == 0 then
    Kit.text("mono", "no item matches", x + pad + 10 * s, listTop + 8 * s, PAL.faint)
  end

  local halfW = (leftW - 2 * pad - 8 * s) / 2
  if Kit.button(x + pad, addY, halfW, addH, "-> Bag",
      { font = "small", radius = 8 * s, enabled = S.selectedItemId ~= nil }) then
    Ops.addToBag(S, S.selectedItemId)
  end
  if Kit.button(x + pad + halfW + 8 * s, addY, halfW, addH, "-> PC",
      { font = "small", radius = 8 * s, enabled = S.selectedItemId ~= nil }) then
    Ops.addToPc(S, S.selectedItemId)
  end

  -- ------------------------------------------------------------ badges
  local badgeY = y + h - badgeH
  Kit.card(x, badgeY, leftW, badgeH)
  local earned = 0
  for _, id in ipairs(badgeIds) do
    -- #515: truthy check, not `== true` -- the in-game grant path stores a
    -- number (see OverworldController.lua checkVictoryRewards), matching
    -- src/inventory/Badges.lua's own truthy read.
    if S.save.inventory[id] then earned = earned + 1 end
  end
  Kit.caption(x + pad, badgeY + pad, "BADGES")
  Kit.textRight("mono", ("%d/%d"):format(earned, #badgeIds), x + leftW - pad,
    badgeY + pad, PAL.caption)
  local bTop = badgeY + pad + Kit.textHeight("caption") + 10 * s
  local bW = (leftW - 2 * pad - (badgeCols - 1) * 7 * s) / badgeCols
  for i, id in ipairs(badgeIds) do
    local bc = (i - 1) % badgeCols
    local br = math.floor((i - 1) / badgeCols)
    local on = S.save.inventory[id]
    local short = id:gsub("BADGE$", "")
    if Kit.chip(x + pad + bc * (bW + 7 * s), bTop + br * (28 * s + 7 * s),
        bW, 28 * s, Kit.ellipsize("micro", short, bW - 8 * s), on,
        PAL.green, PAL.steel) then
      Ops.toggleBadge(S, id)
    end
  end

  -- --------------------------------------------------------------- bag
  local order = Bag.order(S.save)
  local capacity = Bag.capacity(S.data)
  Kit.card(bagX, y, listW, h)
  Kit.caption(bagX + pad, y + pad, "BAG")
  Kit.textRight("mono", ("%d/%d slots"):format(Bag.slots(S.save), capacity),
    bagX + listW - pad, y + pad, PAL.caption)
  local barY = y + pad + Kit.textHeight("caption") + 8 * s
  local slotFrac = Bag.slots(S.save) / capacity
  Kit.meter(bagX + pad, barY, listW - 2 * pad, 5 * s, slotFrac * 100,
    slotFrac >= 1 and PAL.yellow or PAL.blue)

  local pagerH = 30 * s
  local pagerY = y + h - pad - pagerH
  local rowsTop = barY + 5 * s + 12 * s
  local rowH = 36 * s
  local rowGap = 6 * s
  local perPage = math.max(1, math.floor((pagerY - 12 * s - rowsTop) / (rowH + rowGap)))
  S.bagOffset = Ops.clamp(S.bagOffset or 0, 0, math.max(0, #order - perPage))
  -- the wheel moves the same offset the pager below does (#595)
  S.bagOffset = Kit.scroll(bagX + pad, rowsTop, listW - 2 * pad,
    pagerY - 12 * s - rowsTop, S.bagOffset, #order, perPage)

  if #order == 0 then
    Kit.emptyBox(bagX + pad, rowsTop, listW - 2 * pad, 70 * s, "Bag is empty.")
  end
  for i = 1, math.min(perPage, #order - S.bagOffset) do
    local id = order[S.bagOffset + i]
    local ry = rowsTop + (i - 1) * (rowH + rowGap)
    if quantityRow(S, Kit, bagX + pad, ry, listW - 2 * pad, rowH, id,
        S.save.inventory[id] or 0, id == S.selectedBagId,
        function() Ops.bagAdjust(S, id, -1) end,
        function() Ops.bagAdjust(S, id, 1) end,
        function() Ops.bagDrop(S, id) end) then
      S.selectedBagId = id
      Ops.say(S, ("Selected %s in the bag"):format(id))
    end
  end
  S.bagOffset = Kit.pager(bagX + pad, pagerY, listW - 2 * pad, S.bagOffset,
    #order, perPage)

  -- -------------------------------------------------------- pc storage
  local pcOrder = Ops.pcOrder(S)
  Kit.card(pcX, y, listW, h)
  Kit.caption(pcX + pad, y + pad, "PC STORAGE")
  Kit.textRight("mono", ("%d kinds"):format(#pcOrder), pcX + listW - pad,
    y + pad, PAL.caption)
  S.pcOffset = Ops.clamp(S.pcOffset or 0, 0, math.max(0, #pcOrder - perPage))
  S.pcOffset = Kit.scroll(pcX + pad, rowsTop, listW - 2 * pad,
    pagerY - 12 * s - rowsTop, S.pcOffset, #pcOrder, perPage)
  if #pcOrder == 0 then
    Kit.emptyBox(pcX + pad, rowsTop, listW - 2 * pad, 70 * s,
      "PC storage is empty. Items sent here have no slot cap.")
  end
  for i = 1, math.min(perPage, #pcOrder - S.pcOffset) do
    local id = pcOrder[S.pcOffset + i]
    local ry = rowsTop + (i - 1) * (rowH + rowGap)
    if quantityRow(S, Kit, pcX + pad, ry, listW - 2 * pad, rowH, id,
        S.save.pcItems[id] or 0, id == S.selectedPcId,
        function() Ops.pcAdjust(S, id, -1) end,
        function() Ops.pcAdjust(S, id, 1) end,
        function() Ops.pcDrop(S, id) end) then
      S.selectedPcId = id
      Ops.say(S, ("Selected %s in PC storage"):format(id))
    end
  end
  S.pcOffset = Kit.pager(pcX + pad, pagerY, listW - 2 * pad, S.pcOffset,
    #pcOrder, perPage)
end

return M
