-- The mon inspector: species, level, DVs and moves for whatever S.editingMon
-- points at (a party slot or a box slot), all recalculated through MonOps so
-- stats stay in sync with the Gen1 formulas.
--
-- This used to be a modal overlay floating over the party list, which hid the
-- roster you were comparing against.  It is now a permanent right-hand column
-- the Party and Boxes panels dock into (rule 1 of the design spec): the list
-- stays visible while you edit, and Escape clears the selection rather than
-- "closing a window".
--
-- #715 reflow: the inspector used to shrink its stat tiles and DV/move rows
-- against a vertical budget, and past a point the rows still ran over the
-- action buttons.  Sizes are fixed at readable values now; when the card is
-- too short for them the whole body scrolls (Kit.scrollPixels), and when it
-- is too narrow for the DV | moves split the two columns stack.  The clip
-- over the card doubles as the hit fence, so a control scrolled out of view
-- cannot take a stray tap.

local Theme = require("Theme")
local Ops = require("Ops")
local MonOps = require("MonOps")
local PAL = Theme.PAL
local Gen = require("Gen")

local MonEditor = {}

local DV_KEYS = { "attack", "defense", "speed", "special" }
local STAT_KEYS_G1 = {
  { key = "HP", field = "hp" },
  { key = "ATK", field = "attack" },
  { key = "DEF", field = "defense" },
  { key = "SPD", field = "speed" },
  { key = "SPC", field = "special" },
}
local STAT_KEYS_G2 = {
  { key = "HP", field = "hp" },
  { key = "ATK", field = "attack" },
  { key = "DEF", field = "defense" },
  { key = "SPA", field = "specialAttack" },
  { key = "SPD", field = "specialDefense" },
  { key = "SPE", field = "speed" },
}

-- Front sprites are read straight off the generated cache.  One image per
-- species, cached for the process: the old panel called newImage every frame,
-- which re-decoded a PNG sixty times a second.
local spriteCache = {}
function MonEditor.sprite(S, species)
  if not species then return nil end
  if spriteCache[species] ~= nil then return spriteCache[species] or nil end
  if Gen.ofState(S) == 3 then
    local okP, Pokemon = pcall(require, "src.core.game3.pokemon")
    if okP and Pokemon then
      local spId = tonumber(species) or (Pokemon.speciesFromName and Pokemon.speciesFromName(tostring(species)))
      if spId then
        local pic = (Pokemon.frontPic and Pokemon.frontPic(spId)) or (Pokemon.icon and Pokemon.icon(spId))
        if pic and pic.image then
          spriteCache[species] = pic.image
          return pic.image
        end
      end
    end
  end
  local def = S.data and S.data.pokemon and (S.data.pokemon[species] or (type(species) == "number" and S.data.pokemon[species]))
  local path = def and def.spriteFront
  if not path or not love.graphics.newImage then
    spriteCache[species] = false
    return nil
  end
  local ok, img = pcall(love.graphics.newImage, path)
  spriteCache[species] = ok and img or false
  return ok and img or nil
end

-- Draw a species sprite fitted into a box, or a dashed placeholder when the
-- cache has no art for it (a modded species, or a headless run).
function MonEditor.drawSprite(S, Kit, species, x, y, size)
  local img = MonEditor.sprite(S, species)
  if img and love.graphics.draw and img.getDimensions then
    local iw, ih = img:getDimensions()
    if iw > 0 and ih > 0 then
      local scale = math.min(size / iw, size / ih)
      love.graphics.setColor(1, 1, 1, 1)
      love.graphics.draw(img, x + (size - iw * scale) / 2,
        y + (size - ih * scale) / 2, 0, scale, scale)
      return
    end
  end
  Theme.col(PAL.blue, 0.1)
  love.graphics.rectangle("fill", x, y, size, size, 8 * Kit.scale, 8 * Kit.scale)
  Theme.col(PAL.cardBorder, 0.35)
  Theme.dashed(x, y, size, size, 8 * Kit.scale, 5 * Kit.scale, 4 * Kit.scale)
  Kit.textCenter("micro", tostring(species or "?"):sub(1, 3), x,
    y + size / 2 - Kit.textHeight("micro") / 2, size, PAL.muted)
end

-- Bars are scaled against 400 so a Lv100 legend fills roughly three quarters
-- and the differences between mons stay legible.
local STAT_SCALE = 400

-- The -5 -1 [Lv] +1 +5 stepper row plus the EXP readout, at (lx0, ly).
local function drawLevelRow(S, Kit, mon, lx0, ly)
  local s = Kit.scale
  local lh = 28 * s
  Kit.caption(lx0, ly + (lh - Kit.textHeight("caption")) / 2, "LEVEL")
  local lx = lx0 + 52 * s
  local bw = 40 * s
  for _, d in ipairs({ { "-5", -5 }, { "-1", -1 } }) do
    if Kit.stepper(lx, ly, bw, lh, d[1], { font = "small", radius = 7 * s }) then
      Ops.setLevel(S, mon, mon.level + d[2])
    end
    lx = lx + bw + 8 * s
  end
  Kit.textCenter("monoBig", tostring(mon.level), lx,
    ly + (lh - Kit.textHeight("monoBig")) / 2, 58 * s, PAL.heading)
  lx = lx + 58 * s + 8 * s
  for _, d in ipairs({ { "+1", 1 }, { "+5", 5 } }) do
    if Kit.stepper(lx, ly, bw, lh, d[1], { font = "small", radius = 7 * s }) then
      Ops.setLevel(S, mon, mon.level + d[2])
    end
    lx = lx + bw + 8 * s
  end
  Kit.text("mono", ("EXP %d"):format(Gen.exp(mon)), lx + 6 * s,
    ly + (lh - Kit.textHeight("mono")) / 2, PAL.muted)
  return lh
end

-- Everything the level row needs in width, for the "does it fit beside the
-- sprite" decision.
local function levelRowWidth(Kit, mon)
  local s = Kit.scale
  return 52 * s + 2 * (40 * s + 8 * s) + 58 * s + 8 * s + 2 * (40 * s + 8 * s)
    + 6 * s + Kit.textWidth("mono", ("EXP %d"):format(Gen.exp(mon)))
end

local STAT_KEYS_G3 = {
  { key = "hp", label = "HP" },
  { key = "atk", label = "ATTACK" },
  { key = "def", label = "DEFENSE" },
  { key = "spa", label = "SP. ATK" },
  { key = "spd", label = "SP. DEF" },
  { key = "spe", label = "SPEED" },
}

local function totalEvsOf(mon)
  local evs = mon.evs or {}
  local total = 0
  for _, st in ipairs(STAT_KEYS_G3) do
    total = total + (tonumber(evs[st.key]) or 0)
  end
  return total
end

local function drawIvRowsG3(S, Kit, mon, cx, rowY, colW, rowH, rowGap)
  local s = Kit.scale
  mon.ivs = mon.ivs or { hp = 31, atk = 31, def = 31, spe = 31, spa = 31, spd = 31 }
  for i, st in ipairs(STAT_KEYS_G3) do
    local ry = rowY + (i - 1) * (rowH + rowGap)
    Theme.row(cx, ry, colW, rowH, 10 * s, 0.6)
    local v = (mon.ivs and mon.ivs[st.key]) or 0
    Kit.text("tiny", st.label, cx + 10 * s,
      ry + (rowH - Kit.textHeight("tiny")) / 2, PAL.muted)
    local btn = 26 * s
    local btnX = cx + colW - 10 * s - 3 * btn - 18 * s
    local meterX = cx + 66 * s
    local meterW = math.max(16 * s, btnX - meterX - 34 * s)
    Kit.meter(meterX, ry + (rowH - 8 * s) / 2, meterW, 8 * s, v / 31 * 100,
      v >= 31 and PAL.green or (v >= 20 and PAL.blue or PAL.steel))
    Kit.textRight("monoRow", tostring(v), meterX + meterW + 28 * s,
      ry + (rowH - Kit.textHeight("monoRow")) / 2, PAL.heading)
    if Kit.stepper(btnX, ry + (rowH - btn) / 2, btn, btn, "-") then
      Ops.setIv(S, mon, st.key, v - 1)
    end
    if Kit.stepper(btnX + btn + 6 * s, ry + (rowH - btn) / 2, btn, btn, "+") then
      Ops.setIv(S, mon, st.key, v + 1)
    end
    if Kit.button(btnX + 2 * btn + 12 * s, ry + (rowH - btn) / 2, btn, btn,
        "31", { kind = "good", font = "micro", radius = 6 * s }) then
      Ops.setIv(S, mon, st.key, 31)
    end
  end
end

local function drawEvRowsG3(S, Kit, mon, cx, rowY, colW, rowH, rowGap)
  local s = Kit.scale
  mon.evs = mon.evs or { hp = 0, atk = 0, def = 0, spe = 0, spa = 0, spd = 0 }
  for i, st in ipairs(STAT_KEYS_G3) do
    local ry = rowY + (i - 1) * (rowH + rowGap)
    Theme.row(cx, ry, colW, rowH, 10 * s, 0.6)
    local v = (mon.evs and mon.evs[st.key]) or 0
    Kit.text("tiny", st.label, cx + 10 * s,
      ry + (rowH - Kit.textHeight("tiny")) / 2, PAL.muted)

    local btn = 24 * s
    local rightX = cx + colW - 10 * s
    local b252W = 28 * s
    local b252X = rightX - b252W
    local p1X = b252X - 6 * s - btn
    local m1X = p1X - 6 * s - btn

    local meterX = cx + 66 * s
    local meterW = math.max(16 * s, m1X - meterX - 34 * s)
    Kit.meter(meterX, ry + (rowH - 8 * s) / 2, meterW, 8 * s, v / 255 * 100,
      v >= 252 and PAL.green or (v >= 100 and PAL.blue or PAL.steel))
    Kit.textRight("monoRow", tostring(v), meterX + meterW + 28 * s,
      ry + (rowH - Kit.textHeight("monoRow")) / 2, PAL.heading)

    if Kit.stepper(m1X, ry + (rowH - btn) / 2, btn, btn, "-") then
      Ops.setEv(S, mon, st.key, v - 1)
    end
    if Kit.stepper(p1X, ry + (rowH - btn) / 2, btn, btn, "+") then
      Ops.setEv(S, mon, st.key, v + 1)
    end
    if Kit.button(b252X, ry + (rowH - btn) / 2, b252W, btn,
        "252", { kind = "good", font = "micro", radius = 6 * s }) then
      Ops.setEv(S, mon, st.key, 252)
    end
  end
end

local function drawDvRows(S, Kit, mon, cx, rowY, colW, rowH, rowGap)
  local s = Kit.scale
  mon.dvs = mon.dvs or { attack = 0, defense = 0, speed = 0, special = 0, hp = 0 }
  for i, key in ipairs(DV_KEYS) do
    local ry = rowY + (i - 1) * (rowH + rowGap)
    Theme.row(cx, ry, colW, rowH, 10 * s, 0.6)
    local v = (mon.dvs and mon.dvs[key]) or 0
    Kit.text("tiny", key:upper(), cx + 10 * s,
      ry + (rowH - Kit.textHeight("tiny")) / 2, PAL.muted)
    local btn = 26 * s
    local btnX = cx + colW - 10 * s - 3 * btn - 18 * s
    local meterX = cx + 66 * s
    local meterW = math.max(20 * s, btnX - meterX - 34 * s)
    Kit.meter(meterX, ry + (rowH - 8 * s) / 2, meterW, 8 * s, v / 15 * 100,
      v >= 15 and PAL.green or (v >= 10 and PAL.blue or PAL.steel))
    Kit.textRight("monoRow", tostring(v), meterX + meterW + 28 * s,
      ry + (rowH - Kit.textHeight("monoRow")) / 2, PAL.heading)
    if Kit.stepper(btnX, ry + (rowH - btn) / 2, btn, btn, "-") then
      Ops.setDv(S, mon, key, v - 1)
    end
    if Kit.stepper(btnX + btn + 6 * s, ry + (rowH - btn) / 2, btn, btn, "+") then
      Ops.setDv(S, mon, key, v + 1)
    end
    if Kit.button(btnX + 2 * btn + 12 * s, ry + (rowH - btn) / 2, btn, btn,
        "15", { kind = "good", font = "micro", radius = 6 * s }) then
      Ops.setDv(S, mon, key, 15)
    end
  end
end

-- engine/pokemon/caught_data.asm:168-199
local CAUGHT_BY = { { "-", "none" }, { "BOY", "boy" }, { "GIRL", "girl" } }

local function drawCaughtRows(S, Kit, mon, cx, y, inner, row)
  local s = Kit.scale
  local chipH = 22 * s
  local gap = 6 * s
  local tinyH = Kit.textHeight("tiny")

  Kit.text("tiny", "CAUGHT", cx, y + (row - tinyH) / 2, PAL.caption)
  local timeX = cx + 62 * s
  local timeW = math.max(34 * s, (cx + inner - timeX - 3 * gap) / 4)
  for i, label in ipairs(Ops.CAUGHT_TIMES) do
    if Kit.chip(timeX + (i - 1) * (timeW + gap), y + (row - chipH) / 2,
        timeW, chipH, label, (mon.caughtTime or 0) == i - 1, PAL.blue, PAL.steel) then
      Ops.setCaughtTime(S, mon, i - 1)
    end
  end
  y = y + row + gap

  local btn = 24 * s
  local lvX = cx + inner - 2 * btn - gap
  if Kit.stepper(lvX, y + (row - btn) / 2, btn, btn, "-", { font = "small" }) then
    Ops.setCaughtLevel(S, mon, (mon.caughtLevel or 0) - 1)
  end
  if Kit.stepper(lvX + btn + gap, y + (row - btn) / 2, btn, btn, "+",
      { font = "small" }) then
    Ops.setCaughtLevel(S, mon, (mon.caughtLevel or 0) + 1)
  end
  Kit.textRight("tiny", ("MET LV %d"):format(mon.caughtLevel or 0), lvX - 10 * s,
    y + (row - tinyH) / 2, PAL.text)
  Kit.text("tiny", "OT", cx, y + (row - tinyH) / 2, PAL.caption)
  local otX = cx + 26 * s
  local otW = math.max(30 * s, (inner * 0.42 - 26 * s - 2 * gap) / 3)
  for i, pair in ipairs(CAUGHT_BY) do
    if Kit.chip(otX + (i - 1) * (otW + gap), y + (row - chipH) / 2, otW, chipH,
        pair[1], (mon.caughtByGender or "none") == pair[2], PAL.blue, PAL.steel) then
      Ops.setCaughtByGender(S, mon, pair[2])
    end
  end
  y = y + row + gap

  local whereX = cx + inner - 3 * btn - 2 * gap
  if Kit.stepper(whereX, y + (row - btn) / 2, btn, btn, "-", { font = "small" }) then
    Ops.setCaughtLocation(S, mon, (mon.caughtLocation or 0) - 1)
  end
  if Kit.stepper(whereX + btn + gap, y + (row - btn) / 2, btn, btn, "+",
      { font = "small" }) then
    Ops.setCaughtLocation(S, mon, (mon.caughtLocation or 0) + 1)
  end
  if Kit.button(whereX + 2 * (btn + gap), y + (row - btn) / 2, btn, btn, "0",
      { kind = "danger", font = "micro", radius = 6 * s }) then
    Ops.setCaughtLocation(S, mon, 0)
  end
  local where = ("WHERE %s"):format(Gen.landmarkName(S.data, mon.caughtLocation or 0))
  Kit.text("tiny", Kit.ellipsize("tiny", where, whereX - 10 * s - cx), cx,
    y + (row - tinyH) / 2, PAL.text)
  return y + row + gap
end

local function drawMoveRows(S, Kit, mon, rightX, rowY, colW, rowH, rowGap)
  local s = Kit.scale
  for slot = 1, 4 do
    local ry = rowY + (slot - 1) * (rowH + rowGap)
    Theme.row(rightX, ry, colW, rowH, 10 * s, 0.6)
    local mv = mon.moves and mon.moves[slot]
    local clear = Kit.tapMin()
    local clearX = rightX + colW - 8 * s - clear

    local mvId = nil
    if type(mv) == "table" then
      mvId = (S.data and S.data.moves and S.data.moves[mv.id] and S.data.moves[mv.id].name) or mv.id or mv.name
    elseif type(mv) == "number" then
      mvId = S.data and S.data.moves and S.data.moves[mv] and S.data.moves[mv].name
      if not mvId then
        local okP, PokemonG3 = pcall(require, "src.core.game3.pokemon")
        if okP and PokemonG3 and PokemonG3.moveName then
          mvId = PokemonG3.moveName(mv)
        end
      end
    elseif type(mv) == "string" then
      mvId = mv
    end

    Kit.text("mono", tostring(slot), rightX + 10 * s,
      ry + (rowH - Kit.textHeight("mono")) / 2, PAL.faint)

    if mv then
      local basePp = MonOps.getBasePp(S.data, mon, slot)
      local ppUps = MonOps.getPpUps(mon, slot)
      local maxPp = (mon.maxPp and mon.maxPp[slot]) or (type(mv) == "table" and mv.maxPp) or MonOps.calcMaxPp(basePp, ppUps)
      local currentPp = (type(mv) == "table" and mv.pp) or (mon.pp and mon.pp[slot]) or maxPp

      local ppUpW = 44 * s
      local btnH = 22 * s
      local ppUpX = clearX - 6 * s - ppUpW
      local plusX = ppUpX - 4 * s - btnH
      local minusX = plusX - 4 * s - btnH

      -- PP Up button
      local upLabel = ("+PP %d"):format(ppUps)
      if Kit.button(ppUpX, ry + (rowH - btnH) / 2, ppUpW, btnH, upLabel,
          { kind = ppUps > 0 and "accent" or "ghost", font = "micro", radius = 5 * s }) then
        Ops.setPpUps(S, mon, slot, (ppUps + 1) % 4)
      end

      -- Steppers for current PP
      if Kit.stepper(minusX, ry + (rowH - btnH) / 2, btnH, btnH, "-", { font = "small" }) then
        Ops.setPp(S, mon, slot, currentPp - 1)
      end
      if Kit.stepper(plusX, ry + (rowH - btnH) / 2, btnH, btnH, "+", { font = "small" }) then
        Ops.setPp(S, mon, slot, currentPp + 1)
      end

      local ppText = ("%d/%d"):format(currentPp, maxPp)
      local ppW = Kit.textWidth("tiny", ppText)
      local ppColor = currentPp == 0 and PAL.red or (currentPp < maxPp and PAL.caption or PAL.text)
      Kit.textRight("tiny", ppText, minusX - 6 * s,
        ry + (rowH - Kit.textHeight("tiny")) / 2, ppColor)

      local nameX = rightX + 28 * s
      local nameW = math.max(20 * s, minusX - 10 * s - ppW - nameX)
      Kit.text("monoRow", Kit.ellipsize("monoRow", mvId or "-- --", nameW),
        nameX, ry + (rowH - Kit.textHeight("monoRow")) / 2, PAL.text)

      -- Press on move name opens picker
      if Kit.press(rightX, ry, math.max(0, minusX - 8 * s - rightX), rowH) then
        Ops.openMovePicker(S, Kit, slot)
      end

      -- Clear move button
      if Kit.button(clearX, ry + (rowH - clear) / 2, clear, clear, "x",
          { kind = "danger", font = "tiny", radius = 6 * s }) then
        Ops.clearMove(S, mon, slot)
      end
    else
      local nameX = rightX + 28 * s
      local nameW = math.max(20 * s, clearX - 8 * s - nameX)
      Kit.text("monoRow", Kit.ellipsize("monoRow", "-- --", nameW),
        nameX, ry + (rowH - Kit.textHeight("monoRow")) / 2, PAL.faint)

      if Kit.press(rightX, ry, clearX - rightX - 4 * s, rowH) then
        Ops.openMovePicker(S, Kit, slot)
      end
    end
  end
end

function MonEditor.draw(S, Kit, x, y, w, h)
  local s = Kit.scale
  Kit.card(x, y, w, h)
  local mon = S.editingMon
  local pad = 18 * s
  if not mon then
    -- The inspector column is always drawn, so it explains itself rather
    -- than collapsing and reflowing the panel underneath it.
    local tw = math.min(w - 40 * s, 340 * s)
    Kit.textCenter("button",
      "Pick a slot on the left to inspect it. Every change here re-runs the " ..
      "stat formulas, so HP and stats stay legal.",
      x + (w - tw) / 2, y + h / 2 - Kit.textHeight("button"), tw, PAL.muted)
    return
  end

  mon.dvs = mon.dvs or { attack = 0, defense = 0, speed = 0, special = 0, hp = 0 }
  local def = (S.data and S.data.pokemon and (S.data.pokemon[mon.species] or S.data.pokemon[mon.speciesId])) or {}
  local inner = w - 2 * pad
  local capH = Kit.textHeight("caption")
  local titleH = Kit.textHeight("title")

  -- Reflow decisions, all against real pixels (#715): the DV | moves split
  -- needs ~470px of card interior; below that the two stacks go one above
  -- the other.  A narrow card also drops the sprite to 64px so the header
  -- text keeps room.
  local narrow = inner < 470 * s
  local sprite = (narrow and 64 or 96) * s
  local rowH = math.max(Kit.tapMin(), 30 * s)
  local rowGap = 8 * s
  local cellH = 52 * s
  local actH = math.max(Kit.tapMin(), 34 * s)

  local hw = inner - sprite - 18 * s
  local levelInHeader = hw >= levelRowWidth(Kit, mon)
  local headerH
  if levelInHeader then
    headerH = math.max(sprite, titleH + 14 * s + 28 * s)
  else
    -- the level row does not fit beside the sprite: it drops below the
    -- header block at full card width instead of painting over the sprite
    headerH = math.max(sprite, titleH) + 12 * s + 28 * s
  end

  local isG3 = Gen.ofState(S) == 3
  local colRowsH = (isG3 and 6 or 4) * (rowH + rowGap) - rowGap
  local movesRowsH = 4 * (rowH + rowGap) - rowGap
  local colsH
  if isG3 then
    if narrow then
      colsH = (capH + 10 * s + colRowsH) * 2 + (capH + 10 * s + movesRowsH) + 28 * s + 10 * s + actH
    else
      colsH = (capH + 10 * s + colRowsH) + 14 * s + (capH + 10 * s + movesRowsH) + 12 * s + actH
    end
  else
    if narrow then
      colsH = (capH + 10 * s + colRowsH) * 2 + 14 * s + 10 * s + actH
    else
      colsH = capH + 10 * s + colRowsH + 12 * s + actH
    end
  end
  -- the nickname section: a caption line (with the Clear button on it) plus
  -- the field + Set row
  local extraH = 0
  if Gen.ofState(S) == 3 then
    extraH = 154 * s
  elseif Gen.ofState(S) == 2 then
    extraH = 88 * s
  end
  if Gen.hasCaughtData(S.save, S.version) then extraH = extraH + 102 * s end
  local nickFieldH = 30 * s
  local contentH = pad + headerH + 18 * s
    + capH + 10 * s + nickFieldH + 18 * s
    + capH + 10 * s + cellH + 18 * s
    + extraH
    + colsH + pad

  -- Called before the widgets so this frame already draws at the updated
  -- offset; any list-free card body is fair game for the drag (#715).
  S.inspectorScroll = Kit.scrollPixels(x, y, w, h, S.inspectorScroll, contentH)
  Kit.pushClip(x, y, w, h)
  local cx = x + pad
  local cy = y + pad - S.inspectorScroll

  -- ---------------------------------------------------------- header row
  MonEditor.drawSprite(S, Kit, mon.species or mon.speciesId, cx, cy, sprite)
  local hx = cx + sprite + 18 * s

  -- One control instead of a pair of arrows: cycling walked the catalog an
  -- entry at a time (151 taps to cross the dex) and ran a full MonOps
  -- recalculation on every step, including on records the Gen1 formulas
  -- cannot use, which is what crashed the editor (#541).  This opens the
  -- searchable picker; the species name itself is a second, larger target.
  local pickH = 30 * s
  local pickW = math.min(150 * s, math.max(90 * s, hw * 0.6))
  local px = hx + hw - pickW
  local py = cy + (titleH - pickH) / 2

  -- the species name yields to the button instead of running under it (#715)
  local spName = (type(mon.species) == "string" and mon.species) or def.name or tostring(mon.species or "POKEMON")
  local name = Kit.ellipsize("title", spName, math.max(40 * s, px - hx - 12 * s))
  Kit.text("title", name, hx, cy, PAL.heading)
  local nameW = Kit.textWidth("title", name)
  if nameW + Kit.textWidth("tiny", "#000") + 12 * s < px - hx - 12 * s then
    Kit.text("tiny", ("#%03d"):format(tonumber(def and def.dex) or (tonumber(mon.speciesId) or 0)), hx + nameW + 12 * s,
      cy + titleH - Kit.textHeight("tiny") - 2 * s, PAL.caption)
  end

  local openPicker = Kit.button(px, py, pickW, pickH, "Change species",
    { kind = "accent", font = "small", radius = 8 * s })
  if not openPicker then
    openPicker = Kit.press(hx, cy, math.max(0, px - hx - 10 * s), titleH)
  end
  if openPicker then Ops.openSpeciesPicker(S, Kit) end

  -- level stepper: -5 -1 [Lv] +1 +5, matching MonOps.setLevel's 1..100 clamp
  if levelInHeader then
    drawLevelRow(S, Kit, mon, hx, cy + titleH + 14 * s)
  else
    drawLevelRow(S, Kit, mon, cx, cy + math.max(sprite, titleH) + 12 * s)
  end

  -- ---------------------------------------------------------- nickname
  -- Editing the field is a draft (S.nicknameDraft) held on the mon it belongs
  -- to; Set / Enter commit it through Ops.setNickname, which clears on an
  -- empty value, and Clear goes through Ops.clearNickname.  The draft resets
  -- when the selection moves so one mon's typing can never leak onto another.
  local nickY = cy + headerH + 18 * s
  Kit.caption(cx, nickY, "NICKNAME")
  local clearW = 74 * s
  local clearH = 24 * s
  if Kit.button(cx + inner - clearW, nickY + (capH - clearH) / 2, clearW, clearH,
      "Clear", { kind = "danger", font = "micro", radius = 6 * s }) then
    Ops.clearNickname(S, mon)
    S.nicknameDraft = ""
  end
  local fieldY = nickY + capH + 10 * s
  local setW = 64 * s
  local fieldW = inner - setW - 10 * s
  if S.nicknameMon ~= mon then
    local switching = S.nicknameMon ~= nil
    S.nicknameMon = mon
    S.nicknameDraft = mon.nickname or ""
    -- a still-focused field would keep appending keystrokes to the newly
    -- selected mon; the selection move counts as leaving the field.  The
    -- first sync (nicknameMon starts nil) never blurs: the species picker
    -- owns focus when it opens, and blurring there drops the player's typing.
    if switching and Kit.focus == "mon-nickname" then Kit.blur() end
  end
  S.nicknameDraft = Kit.textfield("mon-nickname", cx, fieldY, fieldW, nickFieldH,
    S.nicknameDraft or "", "no nickname",
    { sanitize = function(value) return Ops.nicknameSanitize(S, value) end })
  if Kit.button(cx + fieldW + 10 * s, fieldY, setW, nickFieldH, "Set",
      { kind = "accent", font = "small", radius = 8 * s }) then
    if Ops.setNickname(S, mon, S.nicknameDraft) then
      S.nicknameDraft = mon.nickname or ""
    end
  end

  -- ------------------------------------------------------- derived stats
  local statsY = nickY + capH + 10 * s + nickFieldH + 18 * s
  if isG3 then
    Kit.caption(cx, statsY, "STATS . recalculated from level + IVs + EVs + nature")
  else
    Kit.caption(cx, statsY, "STATS . recalculated from level + DVs")
  end
  statsY = statsY + capH + 10 * s
  local STAT_KEYS = Gen.ofState(S) >= 2 and STAT_KEYS_G2 or STAT_KEYS_G1
  local gap = 12 * s
  local cellW = (inner - gap * (#STAT_KEYS - 1)) / #STAT_KEYS
  for i, st in ipairs(STAT_KEYS) do
    local bx = cx + (i - 1) * (cellW + gap)
    Theme.row(bx, statsY, cellW, cellH, 10 * s, 0.6)
    local value = (mon.stats and (mon.stats[st.field] or mon.stats[st.field:lower()])) or mon[st.field] or 0
    Kit.text("micro", st.key, bx + 12 * s, statsY + 8 * s, PAL.caption)
    Kit.text("stat", tostring(value), bx + 12 * s,
      statsY + 8 * s + Kit.textHeight("micro") + 2 * s, PAL.heading)
    Kit.meter(bx + 12 * s, statsY + cellH - 12 * s, cellW - 24 * s, 5 * s,
      value / STAT_SCALE * 100, PAL.blue)
  end

  -- --------------------------------------------------- DVs | moves split
  local colY = statsY + cellH + 18 * s
  if Gen.ofState(S) == 3 then
    local extraY = colY
    Kit.caption(cx, extraY, "FIRE RED CHARACTERISTICS . PID " .. string.format("0x%08X", mon.personality or 0))
    extraY = extraY + capH + 8 * s
    local row = 28 * s

    -- Held item row
    local heldId = mon.heldItem or mon.item
    local heldName = heldId and (S.data and S.data.items and S.data.items[heldId] and (S.data.items[heldId].name or S.data.items[heldId].id)) or tostring(heldId or "none")
    Kit.text("tiny", "HELD " .. tostring(heldName), cx, extraY, PAL.text)
    if heldId then
      if Kit.button(cx + inner - 70 * s, extraY, 70 * s, row, "Clear item",
          { kind = "danger", font = "tiny", radius = 6 * s }) then
        Ops.setHeldItem(S, mon, nil)
      end
    end
    extraY = extraY + row + 6 * s

    -- Nature and Friendship
    local SummaryData = package.loaded["src.core.game3.summary_data"] or require("src.core.game3.summary_data")
    local natureIdx = mon.nature or ((mon.personality or 0) % 25)
    local okN, nName = pcall(function() return SummaryData.NATURES[natureIdx] end)
    local natureName = (okN and nName) or ("Nature " .. natureIdx)
    Kit.text("tiny", "NATURE " .. natureName, cx, extraY, PAL.text)
    if Kit.stepper(cx + 140 * s, extraY, 28 * s, row, "<", { font = "small" }) then
      Ops.setNature(S, mon, (natureIdx - 1 + 25) % 25)
    end
    if Kit.stepper(cx + 174 * s, extraY, 28 * s, row, ">", { font = "small" }) then
      Ops.setNature(S, mon, (natureIdx + 1) % 25)
    end

    local friendVal = mon.friendship or mon.happiness or 70
    Kit.text("tiny", ("FRIENDSHIP %d"):format(friendVal), cx + 220 * s, extraY, PAL.text)
    if Kit.stepper(cx + 340 * s, extraY, 28 * s, row, "-", { font = "small" }) then
      Ops.setHappiness(S, mon, friendVal - 10)
    end
    if Kit.stepper(cx + 374 * s, extraY, 28 * s, row, "+", { font = "small" }) then
      Ops.setHappiness(S, mon, friendVal + 10)
    end
    extraY = extraY + row + 6 * s

    -- Ability, Gender, Shiny
    local PokemonG3 = require("src.core.game3.pokemon")
    local abilitySlot = ((mon.personality or 0) % 2)
    local abilityId = mon.ability or PokemonG3.abilityId(mon.speciesId or mon.species, mon.personality or 0)
    local abName = PokemonG3.abilityName and PokemonG3.abilityName(abilityId) or ("Ability " .. (abilitySlot + 1))
    if Kit.button(cx, extraY, 150 * s, row, abName .. " (Slot " .. (abilitySlot + 1) .. ")",
        { kind = "accent", font = "micro", radius = 6 * s }) then
      Ops.setAbility(S, mon, (abilitySlot + 1) % 2)
    end

    local curGender = mon.gender or PokemonG3.gender(mon.speciesId or mon.species, mon.personality or 0)
    local genderLabel = curGender == "M" and "♂ MALE" or (curGender == "F" and "♀ FEMALE" or "— GENDERLESS")
    if Kit.button(cx + 160 * s, extraY, 110 * s, row, genderLabel,
        { kind = "ghost", font = "micro", radius = 6 * s }) then
      local nextG = curGender == "M" and "F" or (curGender == "F" and "M" or "U")
      Ops.setMonGender(S, mon, nextG)
    end

    local isShiny = SummaryData.isShiny(mon)
    if Kit.chip(cx + 280 * s, extraY, 80 * s, row, "★ SHINY", isShiny, PAL.yellow, PAL.steel) then
      Ops.setShiny(S, mon, not isShiny)
    end
    extraY = extraY + row + 12 * s
    colY = extraY
  elseif Gen.ofState(S) == 2 then
    local extraY = colY
    Kit.caption(cx, extraY, Gen.editionLabel(S.save, S.version))
    extraY = extraY + capH + 8 * s
    local row = 28 * s
    Kit.text("tiny", "HELD " .. tostring(mon.item or "none"), cx, extraY, PAL.text)
    if Kit.button(cx + inner - 70 * s, extraY, 70 * s, row, "Clear item",
        { kind = "danger", font = "tiny", radius = 6 * s }) then
      Ops.setHeldItem(S, mon, nil)
    end
    extraY = extraY + row + 6 * s
    Kit.text("tiny", ("HAPPINESS %d"):format(mon.happiness or 0), cx, extraY, PAL.text)
    if Kit.stepper(cx + 140 * s, extraY, 28 * s, row, "-", { font = "small" }) then
      Ops.setHappiness(S, mon, (mon.happiness or 0) - 10)
    end
    if Kit.stepper(cx + 174 * s, extraY, 28 * s, row, "+", { font = "small" }) then
      Ops.setHappiness(S, mon, (mon.happiness or 0) + 10)
    end
    Kit.text("tiny", ("PKRS %d"):format(mon.pokerus or 0), cx + 220 * s, extraY, PAL.text)
    if Kit.stepper(cx + 300 * s, extraY, 28 * s, row, "-", { font = "small" }) then
      Ops.setPokerus(S, mon, (mon.pokerus or 0) - 1)
    end
    if Kit.stepper(cx + 334 * s, extraY, 28 * s, row, "+", { font = "small" }) then
      Ops.setPokerus(S, mon, (mon.pokerus or 0) + 1)
    end
    extraY = extraY + row + 4 * s
    local bits = {}
    if mon.gender then bits[#bits + 1] = mon.gender end
    if mon.shiny then bits[#bits + 1] = "shiny" end
    if mon.unownLetter then bits[#bits + 1] = "Unown " .. tostring(mon.unownLetter) end
    Kit.text("tiny", table.concat(bits, "  ") ~= "" and table.concat(bits, "  ")
      or "gender/shiny follow DVs", cx, extraY, PAL.caption)
    extraY = extraY + 22 * s
    if Gen.hasCaughtData(S.save, S.version) then
      extraY = drawCaughtRows(S, Kit, mon, cx, extraY, inner, row)
    end
    colY = extraY
  end
  if isG3 then
    local ivEvRowsH = 6 * (rowH + rowGap) - rowGap
    local mRowsH = 4 * (rowH + rowGap) - rowGap
    local totalEvs = totalEvsOf(mon)

    if narrow then
      -- 1. IVs section
      Kit.caption(cx, colY, "IVs (0-31)")
      local maxIvW = 84 * s
      local maxIvH = 22 * s
      if Kit.button(cx + inner - maxIvW, colY + (capH - maxIvH) / 2, maxIvW, maxIvH,
          "Max all (31)", { kind = "good", font = "micro", radius = 6 * s }) then
        Ops.maxIvs(S, mon)
      end
      local ivRowY = colY + capH + 10 * s
      drawIvRowsG3(S, Kit, mon, cx, ivRowY, inner, rowH, rowGap)

      -- 2. EVs section
      local evY = ivRowY + ivEvRowsH + 14 * s
      Kit.caption(cx, evY, "EVs (0-255)")
      local clearEvW = 54 * s
      local clearEvH = 22 * s
      if Kit.button(cx + inner - clearEvW, evY + (capH - clearEvH) / 2, clearEvW, clearEvH,
          "Clear", { kind = "danger", font = "micro", radius = 6 * s }) then
        Ops.clearEvs(S, mon)
      end
      local evTotalText = ("TOTAL %d / 510"):format(totalEvs)
      Kit.textRight("tiny", evTotalText, cx + inner - clearEvW - 10 * s,
        evY + (capH - Kit.textHeight("tiny")) / 2, totalEvs >= 510 and PAL.green or PAL.caption)
      local evRowY = evY + capH + 10 * s
      drawEvRowsG3(S, Kit, mon, cx, evRowY, inner, rowH, rowGap)

      -- 3. Moves section
      local movesY = evRowY + ivEvRowsH + 14 * s
      Kit.caption(cx, movesY, "MOVES")
      local maxPpW = 84 * s
      local maxPpH = 22 * s
      if Kit.button(cx + inner - maxPpW, movesY + (capH - maxPpH) / 2, maxPpW, maxPpH,
          "Max all PP", { kind = "good", font = "micro", radius = 6 * s }) then
        Ops.maxAllPpUps(S, mon)
      end
      Kit.textRight("tiny", "click a slot to search", cx + inner - maxPpW - 10 * s,
        movesY + (capH - Kit.textHeight("tiny")) / 2, PAL.caption)
      local mRowY = movesY + capH + 10 * s
      drawMoveRows(S, Kit, mon, cx, mRowY, inner, rowH, rowGap)

      local actY = mRowY + mRowsH + 10 * s
      local actW = (inner - 10 * s) / 2
      if Kit.button(cx, actY, actW, actH, "Reset to learnset",
          { font = "small", radius = 9 * s }) then
        Ops.resetMoves(S, mon)
      end
      if Kit.button(cx + actW + 10 * s, actY, actW, actH, "Full heal",
          { kind = "good", font = "small", radius = 9 * s }) then
        Ops.healMon(S, mon)
      end
    else
      local colGap = 18 * s
      local colW = (inner - colGap) / 2
      local rightX = cx + colW + colGap

      -- Left: IVs
      Kit.caption(cx, colY, "IVs (0-31)")
      local maxIvW = 84 * s
      local maxIvH = 22 * s
      if Kit.button(cx + colW - maxIvW, colY + (capH - maxIvH) / 2, maxIvW, maxIvH,
          "Max all (31)", { kind = "good", font = "micro", radius = 6 * s }) then
        Ops.maxIvs(S, mon)
      end
      local ivRowY = colY + capH + 10 * s
      drawIvRowsG3(S, Kit, mon, cx, ivRowY, colW, rowH, rowGap)

      -- Right: EVs
      Kit.caption(rightX, colY, "EVs (0-255)")
      local clearEvW = 54 * s
      local clearEvH = 22 * s
      if Kit.button(rightX + colW - clearEvW, colY + (capH - clearEvH) / 2, clearEvW, clearEvH,
          "Clear", { kind = "danger", font = "micro", radius = 6 * s }) then
        Ops.clearEvs(S, mon)
      end
      local evTotalText = ("TOTAL %d / 510"):format(totalEvs)
      Kit.textRight("tiny", evTotalText, rightX + colW - clearEvW - 10 * s,
        colY + (capH - Kit.textHeight("tiny")) / 2, totalEvs >= 510 and PAL.green or PAL.caption)
      drawEvRowsG3(S, Kit, mon, rightX, ivRowY, colW, rowH, rowGap)

      -- Moves Section below IVs and EVs
      local movesY = ivRowY + ivEvRowsH + 14 * s
      Kit.caption(cx, movesY, "MOVES")
      local maxPpW = 84 * s
      local maxPpH = 22 * s
      if Kit.button(cx + inner - maxPpW, movesY + (capH - maxPpH) / 2, maxPpW, maxPpH,
          "Max all PP", { kind = "good", font = "micro", radius = 6 * s }) then
        Ops.maxAllPpUps(S, mon)
      end
      Kit.textRight("tiny", "click a slot to search", cx + inner - maxPpW - 10 * s,
        movesY + (capH - Kit.textHeight("tiny")) / 2, PAL.caption)
      local mRowY = movesY + capH + 10 * s
      drawMoveRows(S, Kit, mon, cx, mRowY, inner, rowH, rowGap)

      local actY = mRowY + mRowsH + 12 * s
      local actW = (inner - 10 * s) / 2
      if Kit.button(cx, actY, actW, actH, "Reset to learnset",
          { font = "small", radius = 9 * s }) then
        Ops.resetMoves(S, mon)
      end
      if Kit.button(cx + actW + 10 * s, actY, actW, actH, "Full heal",
          { kind = "good", font = "small", radius = 9 * s }) then
        Ops.healMon(S, mon)
      end
    end
  elseif narrow then
    -- stacked: DVs first, then moves, then the two actions side by side at
    -- full width (#715)
    Kit.caption(cx, colY, "DVs")
    Kit.textRight("tiny", ("HP DV auto-derived . %d"):format((mon.dvs and mon.dvs.hp) or 0),
      cx + inner, colY, PAL.caption)
    local rowY = colY + capH + 10 * s
    drawDvRows(S, Kit, mon, cx, rowY, inner, rowH, rowGap)

    local movesY = rowY + colRowsH + 14 * s
    Kit.caption(cx, movesY, "MOVES")
    local maxPpW = 84 * s
    local maxPpH = 22 * s
    if Kit.button(cx + inner - maxPpW, movesY + (capH - maxPpH) / 2, maxPpW, maxPpH,
        "Max all PP", { kind = "good", font = "micro", radius = 6 * s }) then
      Ops.maxAllPpUps(S, mon)
    end
    Kit.textRight("tiny", "click a slot to search", cx + inner - maxPpW - 10 * s,
      movesY + (capH - Kit.textHeight("tiny")) / 2, PAL.caption)
    local mRowY = movesY + capH + 10 * s
    drawMoveRows(S, Kit, mon, cx, mRowY, inner, rowH, rowGap)

    local actY = mRowY + colRowsH + 10 * s
    local actW = (inner - 10 * s) / 2
    if Kit.button(cx, actY, actW, actH, "Reset to learnset",
        { font = "small", radius = 9 * s }) then
      Ops.resetMoves(S, mon)
    end
    if Kit.button(cx + actW + 10 * s, actY, actW, actH, "Full heal",
        { kind = "good", font = "small", radius = 9 * s }) then
      Ops.healMon(S, mon)
    end
  else
    local colGap = 18 * s
    local colW = (inner - colGap) / 2
    local rightX = cx + colW + colGap

    Kit.caption(cx, colY, "DVs")
    Kit.textRight("tiny", ("HP DV auto-derived . %d"):format((mon.dvs and mon.dvs.hp) or 0),
      cx + colW, colY, PAL.caption)
    Kit.caption(rightX, colY, "MOVES")
    local maxPpW = 84 * s
    local maxPpH = 22 * s
    if Kit.button(rightX + colW - maxPpW, colY + (capH - maxPpH) / 2, maxPpW, maxPpH,
        "Max all PP", { kind = "good", font = "micro", radius = 6 * s }) then
      Ops.maxAllPpUps(S, mon)
    end
    Kit.textRight("tiny", "click a slot to search", rightX + colW - maxPpW - 10 * s,
      colY + (capH - Kit.textHeight("tiny")) / 2, PAL.caption)

    local rowY = colY + capH + 10 * s
    drawDvRows(S, Kit, mon, cx, rowY, colW, rowH, rowGap)
    drawMoveRows(S, Kit, mon, rightX, rowY, colW, rowH, rowGap)

    local actY = rowY + colRowsH + 12 * s
    local actW = (colW - 10 * s) / 2
    if Kit.button(rightX, actY, actW, actH, "Reset to learnset",
        { font = "small", radius = 9 * s }) then
      Ops.resetMoves(S, mon)
    end
    if Kit.button(rightX + actW + 10 * s, actY, actW, actH, "Full heal",
        { kind = "good", font = "small", radius = 9 * s }) then
      Ops.healMon(S, mon)
    end
  end
  Kit.popClip()
end

return MonEditor
