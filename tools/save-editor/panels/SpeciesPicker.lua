-- Type-to-search species picker (#541).  The inspector used to change species
-- with a pair of arrows, which walked the catalog one entry at a time -- 151
-- taps to cross the dex -- and ran a full MonOps recalculation on whatever
-- record happened to be next, including records the Gen1 formulas cannot use.
-- This is the replacement: one modal list, filtered as you type, committing
-- through Ops.setSpecies so an unusable record refuses instead of crashing.
--
-- Modal is literal.  Kit hit-tests without a z-order, so App.draw raises
-- Kit.blockClicks over the chrome and the panel while this is open and lowers
-- it only for this overlay; nothing underneath can take the same tap.

local Theme = require("Theme")
local Ops = require("Ops")
local MonEditor = require("MonEditor")
local PAL = Theme.PAL

local Picker = {}

local FIELD_ID = "species-picker"

function Picker.results(S)
  local p = S.speciesPicker
  return Ops.speciesSearch(S, p and p.query or "")
end

-- One commit funnel for both of the picker's jobs: changing the inspected
-- mon's species, and the Boxes panel's add flow (mode "box-add"), which
-- creates a fresh Lv5 mon in the selected box instead (#715).  Either way an
-- unusable record refuses in the status bar rather than crashing (#541).
local function commit(S, id)
  local p = S.speciesPicker
  if p and p.mode == "box-add" then
    return Ops.boxAddSpecies(S, id)
  end
  return Ops.setSpecies(S, S.editingMon, id)
end

-- Enter commits the top match, which is the whole point of a search field.
function Picker.commitFirst(S, Kit)
  local hits = Picker.results(S)
  if not hits[1] then return Ops.say(S, "No species matches that") end
  local ok = commit(S, hits[1])
  if ok then Ops.closeSpeciesPicker(S, Kit) end
  return ok
end

function Picker.draw(S, Kit, width, height)
  local p = S.speciesPicker
  if not p then return end
  local s = Kit.scale

  -- The click that opened the picker is still the frame's click: the
  -- inspector dispatches earlier in App.draw than this overlay does, so
  -- without swallowing it the scrim below would read it as a tap outside and
  -- shut the picker in the same frame it went up.  App re-raises the shield
  -- at the top of the next frame, so leaving it up here is safe.
  if p.opened then
    p.opened = nil
    Kit.blockClicks = true
  end

  -- the scrim doubles as the "tap outside to cancel" target
  Theme.col(PAL.bgBot, 0.72)
  love.graphics.rectangle("fill", 0, 0, width, height)

  local w = math.min(width - 32 * s, 520 * s)
  local h = math.min(height - 32 * s, 560 * s)
  local x = (width - w) / 2
  local y = (height - h) / 2
  if Kit.press(0, 0, width, height) and not Kit.hit(x, y, w, h) then
    Ops.closeSpeciesPicker(S, Kit)
    return
  end

  Kit.card(x, y, w, h)
  local pad = 18 * s
  local cx, cy = x + pad, y + pad
  local inner = w - 2 * pad

  Kit.caption(cx, cy, p.mode == "box-add"
    and ("ADD TO BOX %d"):format(S.selectedBox or 1) or "CHOOSE A SPECIES")
  local closeW = 30 * s
  if Kit.button(x + w - pad - closeW, cy - 4 * s, closeW, 26 * s, "x",
      { font = "small", radius = 7 * s }) then
    Ops.closeSpeciesPicker(S, Kit)
    return
  end
  cy = cy + Kit.textHeight("caption") + 10 * s

  local fieldH = 34 * s
  p.query = Kit.textfield(FIELD_ID, cx, cy, inner, fieldH, p.query,
    "type a name, an id, or a dex number")
  cy = cy + fieldH + 10 * s

  local hits = Picker.results(S)
  local rowH = 40 * s
  local rowGap = 6 * s
  local pagerH = 30 * s
  local listH = (y + h - pad - pagerH - 10 * s) - cy
  local perPage = math.max(1, math.floor((listH + rowGap) / (rowH + rowGap)))
  p.offset = Theme.clamp(p.offset or 0, 0, math.max(0, #hits - perPage))
  -- wheel / touch drag scroll the modal list too; the shield is already
  -- lowered for this layer, so Kit.scroll works here and only here (#715)
  p.offset = Kit.scroll(cx, cy, inner, listH, p.offset, #hits, perPage)

  if #hits == 0 then
    Kit.emptyBox(cx, cy, inner, listH, "Nothing matches that.")
  else
    Kit.pushClip(cx, cy, inner, listH)
    for i = 1, perPage do
      local id = hits[p.offset + i]
      if not id then break end
      local ry = cy + (i - 1) * (rowH + rowGap)
      local def = S.data.pokemon[id]
      -- A record the formulas cannot use still lists, greyed: hiding it would
      -- make a modded species look like it never registered (#541).
      local usable = Ops.speciesUsable(S, id)
      -- box-add has no "current" species: nothing is being replaced
      local current = p.mode ~= "box-add"
        and (S.editingMon and S.editingMon.species == id) or false
      if Kit.row(cx, ry, inner, rowH, current, PAL.green, 9 * s) then
        if commit(S, id) then
          Ops.closeSpeciesPicker(S, Kit)
          Kit.popClip()
          return
        end
      end
      local icon = rowH - 4 * s
      MonEditor.drawSprite(S, Kit, id, cx + 6 * s, ry + 2 * s, icon)
      local tx = cx + 6 * s + icon + 8 * s
      local tail = usable and ("#%03d"):format(tonumber(def and def.dex) or 0)
        or "no data"
      local tailW = Kit.textWidth("tiny", tail)
      Kit.text("monoRow",
        Kit.ellipsize("monoRow", id, inner - (tx - cx) - tailW - 20 * s), tx,
        ry + (rowH - Kit.textHeight("monoRow")) / 2,
        usable and PAL.text or PAL.faint)
      Kit.textRight("tiny", tail, cx + inner - 10 * s,
        ry + (rowH - Kit.textHeight("tiny")) / 2, PAL.caption)
    end
    Kit.popClip()
    Kit.scrollbar(cx, cy, inner, listH, p.offset, #hits, perPage)
  end

  p.offset = Kit.pager(cx, y + h - pad - pagerH, inner, p.offset, #hits, perPage)
end

return Picker
