-- Pokedex panel: a completion header with seen / owned meters and the bulk
-- actions, then a four-column species grid where each row carries two
-- independent toggle chips.
--
-- The game's implications are enforced in Ops (owning implies seen, un-seeing
-- clears owned), so a hand-edited dex can never end up in a state the running
-- game would reject.

local Theme = require("Theme")
local Ops = require("Ops")
local PAL = Theme.PAL

local M = {}

-- Grid columns adapt to the card width: four at the design size, fewer on a
-- phone so the name and the two chips stay readable instead of shearing into
-- each other (#715).  180 logical px is the narrowest a row reads at.
local MAX_COLS = 4
local function colsFor(inner, s)
  return math.max(1, math.min(MAX_COLS, math.floor(inner / (180 * s))))
end

function M.draw(S, Kit, x, y, w, h)
  local s = Kit.scale
  local pad = 20 * s
  local dex = Ops.dex(S)
  local species = S.cat.species
  local seen, owned, total = Ops.dexCounts(S)

  Kit.card(x, y, w, h)
  local cx = x + pad
  local inner = w - 2 * pad

  -- ------------------------------------------------------------- header
  Kit.caption(cx, y + pad, "POKEDEX")
  Kit.text("headline", ("%d / %d owned"):format(owned, total), cx,
    y + pad + Kit.textHeight("caption") + 4 * s, PAL.heading)
  local headH = Kit.textHeight("caption") + 4 * s + Kit.textHeight("headline")
  local headW = math.max(Kit.captionWidth("POKEDEX"),
    Kit.textWidth("headline", ("%d / %d owned"):format(owned, total)))

  -- bulk actions, measured first (#715): at full width they sit right-aligned
  -- on the headline; on a narrower card they take rows of their own below it
  -- and FLOW, wrapping to further rows when even one is too narrow, so the
  -- cluster can never paint over the headline or over itself.
  local actH = 34 * s
  local buttons = {
    { label = "Own party + boxes", kind = "ghost", fn = Ops.dexStamp },
    { label = "See all", kind = "accent", fn = Ops.dexSeeAll },
    { label = "Own all", kind = "good", fn = Ops.dexOwnAll },
    { label = Ops.armLabel(S, "dex-clear", "Wipe dex"), kind = "danger",
      fn = Ops.dexClear },
  }
  local clusterW = -10 * s
  for _, b in ipairs(buttons) do
    clusterW = clusterW + 10 * s + Kit.textWidth("small", b.label) + 32 * s
  end
  local ownRow = clusterW > inner - headW - 24 * s
  local actRows = 1
  local rightEdge = cx + inner
  if not ownRow then
    local actY = y + pad + (headH - actH) / 2
    for i = #buttons, 1, -1 do
      local b = buttons[i]
      local bw = Kit.textWidth("small", b.label) + 32 * s
      rightEdge = rightEdge - bw
      if Kit.button(rightEdge, actY, bw, actH, b.label,
          { kind = b.kind, font = "small", radius = 9 * s }) then
        b.fn(S)
      end
      rightEdge = rightEdge - 10 * s
    end
    rightEdge = rightEdge + 10 * s
  else
    local bx = cx
    local by = y + pad + headH + 10 * s
    for _, b in ipairs(buttons) do
      local bw = Kit.textWidth("small", b.label) + 32 * s
      if bx > cx and bx + bw > cx + inner then
        bx = cx
        by = by + actH + 8 * s
        actRows = actRows + 1
      end
      if Kit.button(bx, by, bw, actH, b.label,
          { kind = b.kind, font = "small", radius = 9 * s }) then
        b.fn(S)
      end
      bx = bx + bw + 10 * s
    end
  end

  -- the two completion meters fill whatever the header leaves between the
  -- headline and the button cluster (the full line, when the cluster wrapped)
  local meterX = cx + headW + 24 * s
  local meterW = (ownRow and cx + inner or rightEdge) - 24 * s - meterX
  if meterW > 120 * s then
    local my = y + pad
    Kit.text("tiny", "SEEN", meterX, my, PAL.caption)
    Kit.textRight("tiny", ("%d/%d"):format(seen, total), meterX + meterW, my, PAL.caption)
    Kit.meter(meterX, my + Kit.textHeight("tiny") + 4 * s, meterW, 7 * s,
      seen / math.max(total, 1) * 100, PAL.blue)
    local my2 = my + Kit.textHeight("tiny") + 4 * s + 7 * s + 10 * s
    Kit.text("tiny", "OWNED", meterX, my2, PAL.caption)
    Kit.textRight("tiny", ("%d/%d"):format(owned, total), meterX + meterW, my2, PAL.caption)
    Kit.meter(meterX, my2 + Kit.textHeight("tiny") + 4 * s, meterW, 7 * s,
      owned / math.max(total, 1) * 100, PAL.green)
  end

  -- --------------------------------------------------------- species grid
  local cols = colsFor(inner, s)
  local pagerH = 30 * s
  local pagerY = y + h - pad - pagerH
  local gridTop = y + pad + headH + 18 * s
    + (ownRow and actRows * (actH + 8 * s) + 2 * s or 0)
  local rowH = 38 * s
  local rowGap = 8 * s
  local colGap = 16 * s
  local colW = (inner - colGap * (cols - 1)) / cols
  local gridH = pagerY - 12 * s - gridTop
  local perCol = math.max(1, math.floor(gridH / (rowH + rowGap)))
  local perPage = perCol * cols
  S.dexOffset = Ops.clamp(S.dexOffset or 0, 0, math.max(0, #species - perPage))
  -- wheel / touch drag move whole grid rows so the columns never shear (#715)
  S.dexOffset = Kit.scroll(cx, gridTop, inner, gridH, S.dexOffset,
    #species, perPage, cols)

  local chipW = 46 * s
  local chipH = 22 * s
  -- clip the grid body so a too-short window clips the last partial row
  -- (and fences its hits) instead of drawing it over the pager (#715)
  Kit.pushClip(cx, gridTop, inner, gridH)
  for i = 1, math.min(perPage, #species - S.dexOffset) do
    local id = species[S.dexOffset + i]
    local ci = (i - 1) % cols
    local ri = math.floor((i - 1) / cols)
    local rx = cx + ci * (colW + colGap)
    local ry = gridTop + ri * (rowH + rowGap)
    local isSeen = dex.seen[id] == true
    local isOwned = dex.owned[id] == true

    Theme.row(rx, ry, colW, rowH, 9 * s, 0.6)
    local def = S.data.pokemon[id]
    Kit.text("micro", ("%03d"):format(def and def.dex or 0), rx + 10 * s,
      ry + (rowH - Kit.textHeight("micro")) / 2, PAL.faint)
    local nameX = rx + 44 * s
    local nameW = colW - 10 * s - 2 * (chipW + 6 * s) - (nameX - rx)
    Kit.text("mono", Kit.ellipsize("mono", id, nameW), nameX,
      ry + (rowH - Kit.textHeight("mono")) / 2,
      isOwned and PAL.text or (isSeen and PAL.muted or PAL.faint))

    local sx = rx + colW - 10 * s - 2 * chipW - 6 * s
    if Kit.chip(sx, ry + (rowH - chipH) / 2, chipW, chipH, "SEEN", isSeen,
        PAL.blue, PAL.steel) then
      Ops.dexSeen(S, id, not isSeen)
    end
    if Kit.chip(sx + chipW + 6 * s, ry + (rowH - chipH) / 2, chipW, chipH, "OWN",
        isOwned, PAL.green, PAL.steel) then
      Ops.dexOwned(S, id, not isOwned)
    end
  end
  Kit.popClip()

  Kit.scrollbar(cx, gridTop, inner, gridH, S.dexOffset, #species, perPage)
  S.dexOffset = Kit.pager(cx, pagerY, inner, S.dexOffset, #species, perPage)
end

return M
