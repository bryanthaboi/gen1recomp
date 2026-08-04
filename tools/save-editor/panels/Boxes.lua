-- Boxes panel: the 12 PC boxes as a real grid rather than the old 20-row
-- text list.  Three columns at full width:
--   box strip   which boxes have room, so you can see where a deposit lands
--   the grid    empty cells are dashed and clickable
--   party dock  the deposit source and withdraw target, both in one place
--
-- Selecting a slot points S.editingMon at it, so switching to the Party tab
-- keeps inspecting the same mon.
--
-- #715 reflow: the three columns need about 900 real px.  Below that the
-- panel stacks the grid over the party dock at full width and drops the box
-- strip (the grid header's < > steppers and Box N counter cover its job).
-- The grid's column count adapts to the width it actually gets, the dock's
-- roster scrolls, and the action labels shorten when the row is tight, so
-- no button ever paints over its neighbour.
--
-- Adding a mon opens the same searchable species picker the inspector uses
-- (see SpeciesPicker.lua / Ops.openBoxAddPicker): the picked species lands
-- in the selected box as a Lv5 mon built by the same MonOps path partyAdd
-- uses, so its stats, exp and moves are consistent.

local BoxesMod = require("src.pokemon.Boxes")
local PartyMod = require("src.pokemon.Party")
local Theme = require("Theme")
local Ops = require("Ops")
local PAL = Theme.PAL

local M = {}

local COLS = 5

local function drawStrip(S, Kit, boxes, x, y, stripW, h)
  local s = Kit.scale
  local pad = 16 * s
  Kit.card(x, y, stripW, h)
  Kit.caption(x + pad, y + pad, ("BOXES . %d"):format(BoxesMod.COUNT))
  local stripTop = y + pad + Kit.textHeight("caption") + 10 * s
  local stripInner = stripW - 2 * pad
  local bRowH = math.min(30 * s, math.max(22 * s,
    (h - (stripTop - y) - pad - (BoxesMod.COUNT - 1) * 6 * s) / BoxesMod.COUNT))
  for i = 1, BoxesMod.COUNT do
    local ry = stripTop + (i - 1) * (bRowH + 6 * s)
    if ry + bRowH > y + h - pad then break end
    if Kit.row(x + pad, ry, stripInner, bRowH, i == S.selectedBox, PAL.blue, 9 * s) then
      Ops.selectBox(S, i)
    end
    local fill = #boxes[i]
    Kit.text("mono", ("Box %d"):format(i), x + pad + 10 * s,
      ry + (bRowH - Kit.textHeight("mono")) / 2, PAL.text)
    local countW = Kit.textWidth("tiny", tostring(fill))
    Kit.textRight("tiny", tostring(fill), x + pad + stripInner - 10 * s,
      ry + (bRowH - Kit.textHeight("tiny")) / 2, PAL.caption)
    local mx = x + pad + stripInner - 10 * s - countW - 8 * s - 44 * s
    Kit.meter(mx, ry + (bRowH - 5 * s) / 2, 44 * s, 5 * s,
      fill / BoxesMod.CAPACITY * 100, fill >= BoxesMod.CAPACITY and PAL.yellow or PAL.blue)
  end
end

local function drawGrid(S, Kit, box, gridX, y, gridW, h)
  local s = Kit.scale
  Kit.card(gridX, y, gridW, h)
  local gpad = 18 * s
  local gx = gridX + gpad
  local ginner = gridW - 2 * gpad
  local headH = 30 * s
  Kit.text("tab", ("Box %d"):format(S.selectedBox), gx,
    y + gpad + (headH - Kit.textHeight("tab")) / 2, PAL.heading)
  local titleW = Kit.textWidth("tab", ("Box %d"):format(S.selectedBox))
  Kit.text("mono", ("%d/%d"):format(#box, BoxesMod.CAPACITY),
    gx + titleW + 14 * s, y + gpad + (headH - Kit.textHeight("mono")) / 2, PAL.caption)
  local navW = 34 * s
  if Kit.stepper(gx + ginner - 2 * navW - 8 * s, y + gpad, navW, headH, "<",
      { radius = 8 * s }) then
    Ops.stepBox(S, -1)
  end
  if Kit.stepper(gx + ginner - navW, y + gpad, navW, headH, ">",
      { radius = 8 * s }) then
    Ops.stepBox(S, 1)
  end

  -- Bottom action row, measured before it is drawn (#715): full labels when
  -- they fit side by side, short verbs when they do not, so Withdraw / Add /
  -- Release can never stack on each other the way the fixed offsets did.
  local actH = 34 * s
  local actY = y + h - gpad - actH
  local wdLabel, addLabel = "Withdraw to party", "+ Add mon here"
  local relLabel = Ops.armLabel(S, "box-release", "Release")
  local function widths()
    return Kit.textWidth("small", wdLabel) + 22 * s,
           Kit.textWidth("small", addLabel) + 22 * s,
           Kit.textWidth("small", relLabel) + 22 * s
  end
  local wdW, addW, relW = widths()
  if wdW + addW + relW + 20 * s > ginner then
    wdLabel, addLabel = "Withdraw", "+ Add"
    wdW, addW, relW = widths()
  end
  if Kit.button(gx, actY, wdW, actH, wdLabel,
      { font = "small", radius = 9 * s,
        enabled = #S.save.party < PartyMod.MAX }) then
    Ops.withdraw(S)
  end
  if Kit.button(gx + wdW + 10 * s, actY, addW, actH, addLabel,
      { font = "small", radius = 9 * s,
        enabled = #box < BoxesMod.CAPACITY }) then
    Ops.openBoxAddPicker(S, Kit)
  end
  if Kit.button(gx + ginner - relW, actY, relW, actH, relLabel,
      { kind = "danger", font = "small", radius = 9 * s }) then
    Ops.release(S)
  end

  -- ------------------------------------------------------------- the grid
  local gridTop = y + gpad + headH + 14 * s
  local gridH = actY - 14 * s - gridTop
  local cellGap = 10 * s
  -- Columns adapt to the real width (#715): a cell needs ~86px before its
  -- name reads, so a narrow card gets fewer, taller-stacked columns instead
  -- of five slivers.
  local cols = math.max(2, math.min(COLS,
    math.floor((ginner + cellGap) / (86 * s + cellGap))))
  local rows = math.ceil(BoxesMod.CAPACITY / cols)
  local cellW = math.max(0, (ginner - cellGap * (cols - 1)) / cols)
  -- floor at Kit's 26px tap target so a short window shrinks the cells but
  -- never inverts them (#715); overflow clips inside the grid body rather
  -- than running over the action row, and the clip fences the hit tests
  local cellH = math.max(26 * s,
    math.min((gridH - cellGap * (rows - 1)) / rows, 110 * s))

  Kit.pushClip(gx, gridTop, ginner, gridH)
  for i = 1, BoxesMod.CAPACITY do
    local cc = (i - 1) % cols
    local cr = math.floor((i - 1) / cols)
    local bx = gx + cc * (cellW + cellGap)
    local by = gridTop + cr * (cellH + cellGap)
    local mon = box[i]
    local selected = (i == S.selectedBoxSlot) and mon ~= nil
    if mon then
      if Kit.row(bx, by, cellW, cellH, selected, PAL.green, 11 * s) then
        Ops.selectBoxSlot(S, i)
      end
      Kit.text("micro", tostring(i), bx + 10 * s, by + 8 * s, PAL.faint)
      Kit.textRight("micro", ("Lv%d"):format(mon.level), bx + cellW - 10 * s,
        by + 8 * s, PAL.caption)
      Kit.textCenter("mono",
        Kit.ellipsize("mono", mon.species, cellW - 12 * s), bx,
        by + cellH / 2 - Kit.textHeight("mono") / 2, cellW, PAL.text)
    else
      -- empty slots are dashed and clickable: clicking one opens the species
      -- picker to add a mon there
      Theme.col(PAL.cardBorder, Kit.hover(bx, by, cellW, cellH) and 0.6 or 0.32)
      Theme.dashed(bx, by, cellW, cellH, 11 * s, 6 * s, 5 * s)
      Kit.text("micro", tostring(i), bx + 10 * s, by + 8 * s, PAL.faint)
      Kit.textCenter("micro", "+", bx, by + cellH / 2 - Kit.textHeight("micro") / 2,
        cellW, PAL.faint)
      if Kit.press(bx, by, cellW, cellH) then
        S.selectedBoxSlot = math.min(i, #box + 1)
        Ops.openBoxAddPicker(S, Kit)
      end
    end
  end
  Kit.popClip()
end

local function drawDock(S, Kit, dx, y, dockW, h)
  local s = Kit.scale
  local pad = 16 * s
  Kit.card(dx, y, dockW, h)
  Kit.caption(dx + pad, y + pad, "PARTY DOCK")
  Kit.textRight("mono", ("%d/%d"):format(#S.save.party, PartyMod.MAX),
    dx + dockW - pad, y + pad, PAL.caption)
  local dTop = y + pad + Kit.textHeight("caption") + 10 * s
  local dInner = dockW - 2 * pad
  local dRowH = 34 * s
  local dGap = 7 * s

  -- Deposit is pinned to the card bottom and the roster scrolls above it
  -- (#715): six party rows used to be laid out unconditionally and the
  -- button drawn below them, which on a short card walked both straight out
  -- of the card.
  local depH = 36 * s
  local depY = y + h - pad - depH
  local listH = math.max(0, depY - 10 * s - dTop)

  if #S.save.party == 0 then
    Kit.emptyBox(dx + pad, dTop, dInner, math.min(listH, 70 * s), "Party is empty.")
  else
    local visible = math.max(1, math.floor((listH + dGap) / (dRowH + dGap)))
    S.dockOffset = Kit.scroll(dx + pad, dTop, dInner, listH,
      S.dockOffset or 0, #S.save.party, visible)
    Kit.pushClip(dx + pad, dTop, dInner, listH)
    for i = 1, visible do
      local slot = S.dockOffset + i
      local mon = S.save.party[slot]
      if not mon then break end
      local ry = dTop + (i - 1) * (dRowH + dGap)
      if Kit.row(dx + pad, ry, dInner, dRowH, S.editingMon == mon, PAL.green, 9 * s) then
        Ops.selectParty(S, slot)
      end
      local lv = ("Lv%d"):format(mon.level)
      local lvW = Kit.textWidth("tiny", lv)
      Kit.textRight("tiny", lv, dx + pad + dInner - 10 * s,
        ry + (dRowH - Kit.textHeight("tiny")) / 2, PAL.caption)
      Kit.text("mono", Kit.ellipsize("mono", mon.species, dInner - 30 * s - lvW),
        dx + pad + 10 * s, ry + (dRowH - Kit.textHeight("mono")) / 2, PAL.text)
    end
    Kit.popClip()
    Kit.scrollbar(dx + pad, dTop, dInner, listH,
      S.dockOffset, #S.save.party, math.max(1, math.floor((listH + dGap) / (dRowH + dGap))))
  end

  if Kit.button(dx + pad, depY, dInner, depH, "Deposit selected slot",
      { kind = "accent", font = "small", radius = 9 * s,
        enabled = #S.save.party > 0 }) then
    Ops.deposit(S)
  end
end

function M.draw(S, Kit, x, y, w, h)
  local s = Kit.scale
  local gap = 20 * s

  S.selectedBox = Ops.clamp(S.selectedBox or 1, 1, BoxesMod.COUNT)
  S.save.currentBox = S.selectedBox
  local boxes = Ops.boxes(S)
  local box = boxes[S.selectedBox]

  if w < 900 * s then
    -- stacked (#715): grid over dock, strip dropped (see the header comment)
    local dockH = Theme.clamp(h * 0.38, 140 * s, 320 * s)
    drawGrid(S, Kit, box, x, y, w, h - dockH - gap)
    drawDock(S, Kit, x, y + h - dockH, w, dockH)
  else
    local stripW = math.max(150 * s, math.min(200 * s, w * 0.16))
    local dockW = math.max(220 * s, math.min(300 * s, w * 0.22))
    local gridW = w - stripW - dockW - 2 * gap
    drawStrip(S, Kit, boxes, x, y, stripW, h)
    drawGrid(S, Kit, box, x + stripW + gap, y, gridW, h)
    drawDock(S, Kit, x + w - dockW, y, dockW, h)
  end
end

return M
