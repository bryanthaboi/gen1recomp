-- Party panel: the roster on the left, the mon inspector permanently docked
-- on the right, so the party stays visible while you edit one of its members.
--
-- Reorder lives on the row itself (the up/down pair appears on the selected
-- row) rather than in a bottom button strip, which leaves Add / Remove as the
-- only two panel-level verbs.
--
-- #715 reflow: side by side, the roster and the inspector need about 640
-- real px between them.  Anything narrower stacks the two cards (roster
-- above, inspector below) at full width instead of shrinking both into
-- unreadable slivers, and the roster body scrolls (wheel / touch drag /
-- Kit.scrollbar) rather than silently truncating past the fold.

local PartyMod = require("src.pokemon.Party")
local Theme = require("Theme")
local Ops = require("Ops")
local MonEditor = require("MonEditor")
local PAL = Theme.PAL

local Party = {}

-- Roster column width: the design's 460px at the reference size, but it gives
-- ground to the inspector on a narrow window so neither column collapses.
-- The 300px floor used to be absolute, which on a phone handed the roster
-- three quarters of the panel and left the inspector laying itself out at a
-- negative width (#497); the floor now yields to a share of what there is.
local function rosterWidth(w, s)
  return math.max(math.min(300 * s, w * 0.42), math.min(460 * s, w * 0.36))
end

-- HP colour follows the game's own health bar thresholds.
local function hpColor(frac)
  if frac <= 0.2 then return PAL.red end
  if frac <= 0.5 then return PAL.yellow end
  return PAL.green
end

local function drawRoster(S, Kit, x, y, listW, h)
  local s = Kit.scale
  Kit.card(x, y, listW, h)
  local pad = 18 * s
  local cx = x + pad
  local innerW = listW - 2 * pad

  Kit.caption(cx, y + pad, "PARTY")
  Kit.textRight("mono", ("%d/%d"):format(#S.save.party, PartyMod.MAX),
    cx + innerW, y + pad, PAL.caption)

  -- "+ Add mon" / "Remove" pinned to the card bottom; the roster fills above.
  local actH = 34 * s
  local actY = y + h - pad - actH
  local listTop = y + pad + Kit.textHeight("caption") + 12 * s
  local listH = actY - 12 * s - listTop

  if #S.save.party == 0 then
    Kit.emptyBox(cx, listTop, innerW, listH,
      "Party is empty - Add creates a Lv5 mon owned by the save's player.")
  else
    local rowH = 64 * s
    local rowGap = 8 * s
    S.selectedParty = Ops.clamp(S.selectedParty or 1, 1, #S.save.party)
    -- The list used to `break` past the fold, silently hiding party slots on
    -- a short window; it scrolls instead now (#715), same offset contract as
    -- every other list in the editor.
    local visible = math.max(1, math.floor((listH + rowGap) / (rowH + rowGap)))
    S.partyOffset = Kit.scroll(cx, listTop, innerW, listH,
      S.partyOffset or 0, #S.save.party, visible)
    Kit.pushClip(cx, listTop, innerW, listH)
    for i = 1, visible do
      local slot = S.partyOffset + i
      local mon = S.save.party[slot]
      if not mon then break end
      local ry = listTop + (i - 1) * (rowH + rowGap)
      local selected = (S.editingMon == mon)
      if Kit.row(cx, ry, innerW, rowH, selected, PAL.green) then
        Ops.selectParty(S, slot)
      end

      local rpad = 12 * s
      local icon = 44 * s
      MonEditor.drawSprite(S, Kit, mon.species, cx + rpad,
        ry + (rowH - icon) / 2, icon)

      -- right cluster first, so the name knows how much room it has left
      local rightW = 52 * s
      local chipH = 20 * s
      local lvText = ("Lv%d"):format(mon.level)
      local chipW = Kit.textWidth("tiny", lvText) + 14 * s
      local chipX = cx + innerW - rpad - chipW
      Theme.stroke(chipX, ry + 10 * s, chipW, chipH, 6 * s, PAL.cardBorder, 0.3, 1)
      Kit.textCenter("tiny", lvText, chipX,
        ry + 10 * s + (chipH - Kit.textHeight("tiny")) / 2, chipW, PAL.blueInk)
      if selected then
        local ab = 22 * s
        local aw = 24 * s
        local ax = cx + innerW - rpad - 2 * aw - 4 * s
        local ay = ry + rowH - 10 * s - ab
        if Kit.stepper(ax, ay, aw, ab, "^", { font = "tiny" }) then
          Ops.partyMove(S, -1)
        end
        if Kit.stepper(ax + aw + 4 * s, ay, aw, ab, "v", { font = "tiny" }) then
          Ops.partyMove(S, 1)
        end
        rightW = 2 * aw + 4 * s + rpad
      end

      local tx = cx + rpad + icon + 12 * s
      local tw = math.max(40 * s, (cx + innerW - rightW - 10 * s) - tx)
      local name = Kit.ellipsize("monoRow", mon.species, tw - 34 * s)
      Kit.text("monoRow", name, tx, ry + 10 * s, PAL.heading)
      Kit.text("tiny", ("#%d"):format(slot),
        tx + Kit.textWidth("monoRow", name) + 8 * s, ry + 12 * s, PAL.caption)

      local maxHp = (mon.stats and mon.stats.hp) or 1
      local frac = Ops.clamp((mon.hp or 0) / math.max(maxHp, 1), 0, 1)
      Kit.meter(tx, ry + rowH / 2 + 2 * s, tw, 6 * s, frac * 100, hpColor(frac))
      Kit.text("tiny", ("HP %d/%d"):format(mon.hp or 0, maxHp), tx,
        ry + rowH - 10 * s - Kit.textHeight("tiny"), PAL.muted)
    end
    Kit.popClip()
    Kit.scrollbar(cx, listTop, innerW, listH,
      S.partyOffset, #S.save.party, visible)
  end

  local halfW = (innerW - 10 * s) / 2
  if Kit.button(cx, actY, halfW, actH, "+ Add mon",
      { font = "small", radius = 9 * s,
        enabled = #S.save.party < PartyMod.MAX }) then
    Ops.partyAdd(S)
  end
  if Kit.button(cx + halfW + 10 * s, actY, halfW, actH,
      Ops.armLabel(S, "party-remove", "Remove"),
      { kind = "danger", font = "small", radius = 9 * s }) then
    Ops.partyRemove(S)
  end
end

function Party.draw(S, Kit, x, y, w, h)
  local s = Kit.scale
  local gap = 20 * s
  if w < 640 * s then
    -- stacked (#715): roster on top with enough height for a few rows, the
    -- inspector takes the rest and scrolls internally (see MonEditor)
    local rosterH = Theme.clamp(h * 0.42, 150 * s, 300 * s)
    drawRoster(S, Kit, x, y, w, rosterH)
    MonEditor.draw(S, Kit, x, y + rosterH + gap, w, h - rosterH - gap)
  else
    local listW = rosterWidth(w, s)
    drawRoster(S, Kit, x, y, listW, h)
    MonEditor.draw(S, Kit, x + listW + gap, y, w - listW - gap, h)
  end
end

return Party
