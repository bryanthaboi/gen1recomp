local Ops = require("Ops")
local Gen = require("Gen")
local P = require("Properties")
local MonOps = require("MonOps")
local Theme = require("Theme")
local PAL = Theme.PAL
local Motion = require("Motion")
local Chooser = require("Chooser")
local Touch = require("TouchEditor")
local Limits = require("ValueLimits")
local Named = require("NamedChoices")
local Legality = require("Legality")
local Form = require("Form")
local MonEditor = require("MonEditor")
local Body = {}

local SECTIONS = {
  { "main", "Main" },
  { "stats", "Stats" },
  { "moves", "Moves" },
  { "origin", "Origin" },
  { "extras", "Extras" },
  { "checks", "Checks" },
}
local NATURE_STATS = { "Atk", "Def", "Spe", "SpA", "SpD" }
local GENDER_NAMES = { M = "Male", F = "Female", male = "Male", female = "Female" }
local STAT_NAMES = {
  hp = "HP", atk = "Attack", def = "Defense", spa = "Sp. Atk", spd = "Sp. Def", spe = "Speed",
  attack = "Attack", defense = "Defense", speed = "Speed", special = "Special",
}
local STATUSES = {
  { "healthy", "Healthy" },
  { "SLP", "Asleep" },
  { "PSN", "Poisoned" },
  { "BRN", "Burned" },
  { "FRZ", "Frozen" },
  { "PAR", "Paralyzed" },
}

local function titleCase(str)
  str = tostring(str or "")
  if str:find("%l") then return str end
  return (str:lower():gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end))
end

local function typeName(S, t)
  if t == nil then return nil end
  if Gen.ofState(S) == 3 then
    if type(t) == "number" then
      local name
      for k, v in pairs(require("src.core.game3.battle.types").ID) do
        if v == t then name = k end
      end
      t = name or tostring(t)
    end
    t = tostring(t):gsub("^TYPE_", "")
    if t == "MYSTERY" then return "???" end
  else
    local ok, name = pcall(require("src.battle.TypeChart").displayName, t, S.data)
    if ok and name then t = name end
  end
  if t == "???" then return t end
  return titleCase(t)
end

local function hpColor(frac)
  if frac <= 0.2 then return PAL.red end
  if frac <= 0.5 then return PAL.yellow end
  return PAL.green
end

local function hint(C, id, x, y, w)
  local message = C.issues.fields[id]
  if not message then return 0 end
  return 6 * C.s + Touch.issue(C.Kit, message, x, y + 6 * C.s, w)
end

local function speciesTypes(C)
  local S, mon = C.S, C.mon
  local out = {}
  if C.g == 3 then
    local t = require("src.core.game3.pokemon").types(mon.species)
    out[1] = typeName(S, t[1])
    if t[2] ~= t[1] then out[2] = typeName(S, t[2]) end
    return out
  end
  local t = (C.def and C.def.types) or mon.types or {}
  for i, v in ipairs(t) do
    if i == 1 or v ~= t[1] then out[#out + 1] = typeName(S, v) end
  end
  return out
end

local function natureOf(mon)
  return mon.nature or (tonumber(mon.personality) or 0) % 25
end

local function natureName(id)
  local ok, name = pcall(function() return require("src.core.game3.summary_data").NATURES[id] end)
  return ok and name and titleCase(name) or tostring(id)
end

-- src/pokemon.c:1365
local function natureEffect(id)
  id = tonumber(id) or 0
  local up, down = math.floor(id / 5) + 1, id % 5 + 1
  if up == down or not NATURE_STATS[up] then return "No stat change" end
  return "+" .. NATURE_STATS[up] .. "  -" .. NATURE_STATS[down]
end

local function genderOf(C)
  local mon = C.mon
  if C.g == 3 then
    return mon.gender or require("src.core.game3.pokemon").gender(mon.species, tonumber(mon.personality) or 0)
  elseif C.g == 2 then
    local ok, gender = pcall(require("src.core.gen2.Breeding").gender, C.def, mon.dvs)
    return ok and gender or nil
  end
end

local function speciesName(C)
  local def = C.def
  return (def and def.name) or tostring(C.mon.species or C.mon.speciesId)
end

local function savedStatus(mon)
  local status = mon.status or "healthy"
  if type(status) == "number" then
    status = ({ [0] = "healthy", [8] = "PSN", [16] = "BRN", [32] = "FRZ", [64] = "PAR", [128] = "TOX" })[status]
      or (status >= 1 and status <= 7 and "SLP") or status
  end
  return status
end

local function heroActions(C)
  local S, mon = C.S, C.mon
  local list = {}
  if C.g == 3 then
    local shiny = MonEditor.isShiny(S, mon)
    list[#list + 1] = { "Shiny", function()
      Ops.setShiny(S, mon, not shiny)
    end, {
      kind = shiny and "warn" or "ghost",
      icon = "sparkles",
      iconInk = not shiny and PAL.yellow or nil,
      invalid = C.issues.fields.shiny ~= nil,
      id = "shiny",
    } }
  end
  list[#list + 1] = { "Full heal", function()
    Ops.healMon(S, mon)
  end, { kind = "ghost", icon = "heart", iconInk = PAL.green } }
  return list
end

local function metaLine(C)
  local mon = C.mon
  local parts = { "Lv " .. tostring(mon.level or "?") }
  if C.g == 3 then parts[#parts + 1] = natureName(natureOf(mon)) end
  local gender = GENDER_NAMES[genderOf(C) or ""]
  if gender then parts[#parts + 1] = gender end
  return table.concat(parts, " · ")
end

local function drawHero(C, x, y, w, stacked)
  local S, Kit, mon, s = C.S, C.Kit, C.mon, C.s
  local box = math.floor((stacked and 96 or 92) * s)
  local actions = heroActions(C)
  local actW, gap = 0, 10 * s
  for i, a in ipairs(actions) do
    actW = actW + Kit.buttonWidth(a[1], { font = "button", icon = a[3].icon }, C.row) + (i > 1 and gap or 0)
  end
  local inline = not stacked and w - box - actW - 36 * s >= 240 * s
  local tx, ty = x + box + 18 * s, y
  local textW = inline and (w - box - actW - 36 * s) or (w - box - 18 * s)
  if stacked then
    tx, ty, textW = x, y + box + 16 * s, w
  end
  Theme.fillRounded(x, y, box, box, PAL.rowBg, 0.7, Theme.radius())
  Theme.stroke(x, y, box, box, Theme.radius(), PAL.cardBorder, 0.3, 1)
  MonEditor.drawSprite(S, Kit, mon.species, x + 6 * s, y + 6 * s, box - 12 * s, mon)

  local def = C.def or {}
  local dex = def.dex or def.national
  local dexStr = dex and ("#" .. tostring(dex)) or nil
  local dexW = dexStr and Kit.textWidth("button", dexStr) + 12 * s or 0
  local name = Kit.ellipsize("title", MonEditor.displayName(S, mon), math.max(40 * s, textW - dexW))
  Kit.textBold("title", name, tx, ty, PAL.heading)
  if dexStr then
    Kit.text("button", dexStr, tx + Kit.textWidth("title", name) + 12 * s,
      ty + Kit.textHeight("title") - Kit.textHeight("button") - 2 * s, PAL.muted)
  end
  ty = ty + Kit.textHeight("title") + 8 * s

  local chipH = math.floor(Kit.textHeight("small") + 10 * s)
  local cx = tx
  for _, t in ipairs(speciesTypes(C)) do
    local cw = Kit.textWidth("small", t) + 18 * s
    if cx > tx and cx + cw > tx + textW then
      cx, ty = tx, ty + chipH + 6 * s
    end
    Theme.fillRounded(cx, ty, cw, chipH, PAL.rowBg, 0.8, 7 * s)
    Theme.strokeRounded(cx, ty, cw, chipH, PAL.line, 0.45, 1, 7 * s)
    Kit.textCenterBold("small", t, cx, ty + (chipH - Kit.textHeight("small")) / 2, cw, PAL.heading)
    cx = cx + cw + 8 * s
  end
  local meta = metaLine(C)
  if cx > tx and cx + Kit.textWidth("small", meta) > tx + textW then
    cx, ty = tx, ty + chipH + 6 * s
  end
  Kit.text("small", Kit.ellipsize("small", meta, tx + textW - cx), cx, ty + (chipH - Kit.textHeight("small")) / 2, PAL.muted)
  ty = ty + chipH + 12 * s

  local maxHp = mon.maxHp or (mon.stats and mon.stats.hp) or 0
  local hp = tonumber(mon.hp) or 0
  local hpText = ("HP %d/%d"):format(hp, maxHp)
  local barW = math.max(60 * s, math.min(400 * s, textW - Kit.textWidth("small", hpText) - 14 * s))
  local frac = Theme.clamp(hp / math.max(1, maxHp), 0, 1)
  Kit.meter(tx, ty + (Kit.textHeight("small") - 6 * s) / 2, barW, 6 * s, frac * 100, hpColor(frac))
  Kit.text("small", hpText, tx + barW + 14 * s, ty, PAL.muted)
  ty = ty + Kit.textHeight("small")
  local bottom = math.max(y + box, ty)

  if inline then
    local ax, ay = x + w - actW, y + math.max(0, (box - C.row) / 2 - 8 * s)
    for _, a in ipairs(actions) do
      local opts = {}
      for k, v in pairs(a[3]) do opts[k] = v end
      opts.font = "button"
      local bw = Kit.buttonWidth(a[1], opts, C.row)
      if Kit.button(ax, ay, bw, C.row, a[1], opts) then a[2]() end
      ax = ax + bw + gap
    end
  else
    local fy = bottom + 16 * s
    bottom = fy + Form.flow(Kit, nil, actions, x, fy, w)
  end
  local shiny = C.issues.fields.shiny
  if shiny then bottom = bottom + hint(C, "shiny", x, bottom, w) end
  return bottom - y
end

local function sectionOptions(C)
  local list = {}
  for _, e in ipairs(SECTIONS) do
    local errors = C.issues.sections[e[1]] or 0
    list[#list + 1] = {
      e[1], e[2],
      errors = errors,
      icon = errors > 0 and "triangle-alert" or C.Kit.navigationIcon(e[2]),
    }
  end
  return list
end

local function drawNav(C, x, y, w, stacked)
  local S, Kit = C.S, C.Kit
  local options = sectionOptions(C)
  local function pick(value, index)
    if stacked then
      local keep = S._navKeep or 0
      S.monSection = value
      Kit.blur()
      Ops.disarm(S)
      S.propertyChoice = nil
      S.inspectorScroll = keep
      return
    end
    local old = 1
    for i, o in ipairs(options) do
      if o[1] == S.monSection then old = i end
    end
    Motion.change(S, "monSection", value, index >= old and 1 or -1)
  end
  if Form.tabs(S, Kit, "monSection", options, x, y, w, C.row, pick) then return end
  Chooser.navigation(S, Kit, "monSection", "Pokemon section", options, x, y,
    math.min(w, 360 * C.s), C.row, stacked and function()
      S.inspectorScroll = S._navKeep or 0
    end or nil)
end

local function identityColumn(C, x, y, w)
  local S, Kit, mon, g, s, row, issues = C.S, C.Kit, C.mon, C.g, C.s, C.row, C.issues
  local gap, block = 10 * s, 22 * s
  local cy = y + Kit.caption(x, y, "IDENTITY") + 16 * s

  cy = cy + Form.label(Kit, "Species", x, cy, w, nil, issues.fields.species and PAL.red)
  local chOpts = { font = "button", icon = "pencil", id = "change-species" }
  local chW = Kit.buttonWidth("Change", chOpts, row)
  Form.box(Kit, x, cy, w - chW - gap, row, speciesName(C), issues.fields.species ~= nil)
  if Kit.button(x + w - chW, cy, chW, row, "Change", chOpts) then
    Ops.openSpeciesPicker(S, Kit)
  end
  cy = cy + row
  cy = cy + hint(C, "species", x, cy, w) + block

  if S.nicknameMon ~= mon then
    S.nicknameMon, S.nicknameDraft, S._nickFocus = mon, mon.nickname or "", nil
  end
  local focused = Kit.focus == "mon-nickname"
  if S._nickFocus == mon and not focused then
    S._nickFocus = nil
    if (S.nicknameDraft or "") ~= (mon.nickname or "") then
      Ops.setNickname(S, mon, S.nicknameDraft)
      S.nicknameDraft = mon.nickname or ""
    end
  end
  if focused then S._nickFocus = mon end
  local count = Ops.nicknameLength(S.nicknameDraft or "") .. "/" .. Ops.NICKNAME_MAX
  cy = cy + Form.label(Kit, "Nickname", x, cy, w, count, issues.fields.nickname and PAL.red)
  if C.contentTop then
    S._fieldOffset = { id = "mon-nickname", off = cy - C.contentTop, h = row }
  end
  S.nicknameDraft = Kit.textfield("mon-nickname", x, cy, w, row, S.nicknameDraft or "", "None (uses species name)", {
    invalid = issues.fields.nickname ~= nil,
    sanitize = function(v)
      return Ops.nicknameSanitize(S, v)
    end,
  })
  cy = cy + row
  cy = cy + hint(C, "nickname", x, cy, w) + block

  local function unownForm(help)
    local letter = Ops.unownForm(S, mon)
    if letter == nil then return end
    cy = cy + Form.label(Kit, "Unown form", x, cy, w, nil, issues.fields.form and PAL.red)
    cy = cy + Form.select(S, Kit, "form", "Unown form", letter, Ops.unownFormOptions(S), x, cy, w, function(v)
      return Ops.setUnownForm(S, mon, v)
    end, issues.fields.form, help)
    cy = cy + hint(C, "form", x, cy, w) + block
  end

  if g == 3 then
    local Pokemon = require("src.core.game3.pokemon")
    local nature = natureOf(mon)
    local natures = {}
    for id = 0, 24 do
      natures[#natures + 1] = { id, natureName(id) }
    end
    local slot = mon.abilityNum or (tonumber(mon.personality) or 0) % 2
    local abilities = {}
    for i, id in ipairs(Pokemon.abilities(mon.species)) do
      if id and id ~= 0 then
        abilities[#abilities + 1] = { i - 1, titleCase(Pokemon.abilityName(id)) }
      end
    end
    local half = w >= 340 * s
    local hw = half and (w - 16 * s) / 2 or w
    local top = cy
    cy = cy + Form.label(Kit, "Nature", x, cy, hw, nil, issues.fields.nature and PAL.red)
    cy = cy + Form.select(S, Kit, "nature", "Nature", nature, natures, x, cy, hw, function(v)
      return Ops.setNature(S, mon, v)
    end, issues.fields.nature)
    cy = cy + 8 * s
    Kit.text("small", natureEffect(nature), x, cy, PAL.muted)
    cy = cy + Kit.textHeight("small")
    cy = cy + hint(C, "nature", x, cy, hw)
    local ax, ay = x, cy + block
    if half then ax, ay = x + hw + 16 * s, top end
    ay = ay + Form.label(Kit, "Ability", ax, ay, hw, nil, issues.fields.ability and PAL.red)
    ay = ay + Form.select(S, Kit, "ability", "Ability", slot, abilities, ax, ay, hw, function(v)
      return Ops.setAbility(S, mon, v)
    end, issues.fields.ability)
    ay = ay + hint(C, "ability", ax, ay, hw)
    cy = math.max(cy, ay) + block

    local gender = genderOf(C)
    local ratio = (Pokemon.speciesMeta(mon.species) or {}).genderRatio or 255
    local genders = ratio == 255 and { { "U", "Genderless" } }
      or ratio == 0 and { { "M", "Male" } }
      or ratio == 254 and { { "F", "Female" } }
      or { { "M", "Male" }, { "F", "Female" } }
    cy = cy + Form.label(Kit, "Gender", x, cy, w, nil, issues.fields.gender and PAL.red)
    if #genders == 1 then
      Form.box(Kit, x, cy, w, row, genders[1][2], issues.fields.gender ~= nil)
    else
      Form.segmented(Kit, "gender", genders, gender, x, cy, w, row, function(v)
        return Ops.setMonGender(S, mon, v)
      end, issues.fields.gender)
    end
    cy = cy + row
    cy = cy + hint(C, "gender", x, cy, w) + block
  end

  if g >= 2 then
    local heldId = mon.heldItem or mon.item
    local held = S.data.items and S.data.items[heldId]
    local hasItem = heldId ~= nil and heldId ~= 0
    local heldName = held and held.name or (hasItem and tostring(heldId)) or "None"
    cy = cy + Form.label(Kit, "Held item", x, cy, w, nil, issues.fields.heldItem and PAL.red)
    local itemOpts = { font = "button", icon = "pencil", id = "change-item" }
    local itemW = Kit.buttonWidth("Change", itemOpts, row)
    Form.box(Kit, x, cy, w - itemW - row - 2 * gap, row, heldName, issues.fields.heldItem ~= nil,
      not hasItem and PAL.muted or nil)
    if Kit.button(x + w - row - gap - itemW, cy, itemW, row, "Change", itemOpts) then
      Ops.openItemPicker(S, Kit, "held")
    end
    if Kit.iconButton(x + w - row, cy, row, row, "x", "Clear held item", { kind = "danger", enabled = hasItem }) then
      Ops.setHeldItem(S, mon, nil)
    end
    cy = cy + row
    cy = cy + hint(C, "heldItem", x, cy, w) + block
  end

  if g == 3 then
    unownForm("Keeps nature and shininess. Changes the personality value.")
  elseif g == 2 then
    local d = P.find(S, "pokerus")
    cy = cy + Form.label(Kit, "Pokérus", x, cy, w, nil, issues.fields.pokerus and PAL.red)
    cy = cy + Form.select(S, Kit, "pokerus", "Pokérus", mon.pokerus or 0, Named.property(S, d), x, cy, w, function(v)
      return Ops.setPokerus(S, mon, v)
    end, issues.fields.pokerus)
    cy = cy + hint(C, "pokerus", x, cy, w) + block
    local isUnown = Ops.unownForm(S, mon) ~= nil
    unownForm("Rewrites the middle bits of the DVs. Only I and V can be shiny.")
    cy = cy + Kit.textWrapped("small", isUnown and "Gender and shininess follow DVs. Picking a form rewrites the middle DV bits."
      or "Gender and shininess follow DVs.", x, cy, w, PAL.muted)
    cy = cy + hint(C, "gender", x, cy, w)
    cy = cy + hint(C, "shiny", x, cy, w)
    if not isUnown then cy = cy + hint(C, "form", x, cy, w) end
    cy = cy + block
  end
  return cy - block
end

local function conditionColumn(C, x, y, w)
  local S, Kit, mon, g, s, issues = C.S, C.Kit, C.mon, C.g, C.s, C.issues
  local block = 22 * s
  local cy = y + Kit.caption(x, y, "LEVEL & CONDITION") + 16 * s
  local function num(id, title, value, apply)
    cy = cy + Form.numberRow(S, Kit, id, title, value, Limits.mon(S, mon, id), x, cy, w, apply, issues.fields[id]) + block
  end
  num("level", "Level", mon.level, function(n)
    if not Legality.integer(n, 1, 100) then
      return Ops.say(S, "Level must be a whole number from 1 to 100")
    end
    return Ops.setLevel(S, mon, n)
  end)
  num("experience", "Experience", Gen.exp(mon), function(n)
    return Ops.setExperience(S, mon, n)
  end)
  num("current-hp", "Current HP", mon.hp or 0, function(n)
    return Ops.setCurrentHp(S, mon, n)
  end)
  if g >= 2 then
    num("friendship", "Friendship", mon.friendship or mon.happiness or 0, function(n)
      if not Legality.integer(n, 0, 255) then
        return Ops.say(S, "Friendship must be 0-255")
      end
      return Ops.setHappiness(S, mon, n)
    end)
  end
  local statuses = {}
  for i, st in ipairs(STATUSES) do statuses[i] = st end
  if g >= 2 then statuses[#statuses + 1] = { "TOX", "Badly poisoned" } end
  cy = cy + Form.label(Kit, "Status", x, cy, w, nil, issues.fields.status and PAL.red)
  cy = cy + Form.select(S, Kit, "status", "Status", savedStatus(mon), statuses, x, cy, w, function(v)
    return Ops.setMonStatus(S, mon, v ~= "healthy" and v or nil)
  end, issues.fields.status)
  cy = cy + hint(C, "status", x, cy, w)
  return cy
end

local function mainBody(C, x, y, w)
  local s = C.s
  local two = w >= 600 * s
  local colGap = 32 * s
  local cw = two and (w - colGap) / 2 or w
  local left = identityColumn(C, x, y, cw)
  local right = conditionColumn(C, two and x + cw + colGap or x, two and y or left + 30 * s, cw)
  return math.max(left, right) - y
end

local function statsBody(C, x, y, w)
  local S, Kit, mon, g, s, issues = C.S, C.Kit, C.mon, C.g, C.s, C.issues
  local block = 22 * s
  local cy = y
  local keys = g == 3 and { "hp", "atk", "def", "spa", "spd", "spe" }
    or { "hp", "attack", "defense", "speed", "special" }
  local stats = mon.stats or {}
  local calcColor = issues.fields.calculated and PAL.red or PAL.heading
  cy = cy + Kit.caption(x, cy, "CALCULATED") + 12 * s
  local line = ("HP %s  ·  Atk %s  ·  Def %s  ·  Spe %s"):format(
    tostring(stats.hp or mon.maxHp or "?"),
    tostring(stats.attack or mon.attack or "?"),
    tostring(stats.defense or mon.defense or "?"),
    tostring(stats.speed or mon.speed or "?"))
  line = line .. "  ·  " .. (g == 1 and ("Special " .. tostring(stats.special or "?"))
    or ("SpA " .. tostring(stats.specialAttack or stats.spAtk or mon.spAtk or "?")
      .. "  ·  SpD " .. tostring(stats.specialDefense or stats.spDef or mon.spDef or "?")))
  cy = cy + Kit.textWrapped("button", line, x, cy, w, calcColor)
  cy = cy + hint(C, "calculated", x, cy, w) + 8 * s
  cy = cy + Kit.textWrapped("small", g == 3 and "IVs 0-31. EVs 0-255 with a total limit of 510."
    or "DVs 0-15. HP DV follows the other DVs. Stat experience 0-65535.", x, cy, w, PAL.muted)
  if g == 3 then
    local total = Limits.evTotal(mon)
    cy = cy + 6 * s + Kit.textWrapped("small", "EVs: " .. total .. " / 510  ·  " .. math.max(0, 510 - total) .. " free",
      x, cy + 6 * s, w, total > 510 and PAL.red or PAL.green)
  else
    cy = cy + 6 * s + Kit.textWrapped("small", "HP DV: " .. tostring(mon.dvs and mon.dvs.hp or 0) .. " / 15 · follows the other DVs",
      x, cy + 6 * s, w, issues.fields["dv-hp"] and PAL.red or PAL.muted)
    cy = cy + hint(C, "dv-hp", x, cy, w)
  end
  cy = cy + block
  local two = w >= 560 * s
  local colGap = 32 * s
  local cw = two and (w - colGap) / 2 or w
  local function num(id, title, value, apply, nx, ny)
    return Form.numberRow(S, Kit, id, title, value, Limits.mon(S, mon, id), nx, ny, cw, apply, issues.fields[id])
  end
  for _, k in ipairs(keys) do
    local left, right
    if g == 3 then
      left = { "iv-" .. k, STAT_NAMES[k] .. " IV", mon.ivs and mon.ivs[k] or 0, function(n)
        return Ops.setIv(S, mon, k, n)
      end }
      right = { "ev-" .. k, STAT_NAMES[k] .. " EV", mon.evs and mon.evs[k] or 0, function(n)
        return Ops.setEv(S, mon, k, n)
      end }
    else
      if k ~= "hp" then
        left = { "dv-" .. k, STAT_NAMES[k] .. " DV", mon.dvs and mon.dvs[k] or 0, function(n)
          return Ops.setDv(S, mon, k, n)
        end }
      end
      right = { "se-" .. k, STAT_NAMES[k] .. " stat experience", mon.statExp and mon.statExp[k] or 0, function(n)
        return Ops.setStatExp(S, mon, k, n)
      end }
    end
    if left and two then
      local lh = num(left[1], left[2], left[3], left[4], x, cy)
      local rh = num(right[1], right[2], right[3], right[4], x + cw + colGap, cy)
      cy = cy + math.max(lh, rh) + block
    else
      if left then cy = cy + num(left[1], left[2], left[3], left[4], x, cy) + block end
      cy = cy + num(right[1], right[2], right[3], right[4], x, cy) + block
    end
  end
  return cy - block - y
end

local function moveInfo(C, slot)
  local S, mon = C.S, C.mon
  local mv = mon.moves and mon.moves[slot]
  local id = type(mv) == "table" and (mv.moveId or mv.id) or mv
  local md = id and S.data.moves and S.data.moves[id]
  local info = { slot = slot, id = id, md = md, empty = id == nil or id == 0 }
  if not info.empty then
    info.pp = tonumber(type(mv) == "table" and mv.pp or mon.pp and mon.pp[slot]) or 0
    info.ups = MonOps.getPpUps(mon, slot)
    info.base = MonOps.getBasePp(S.data, mon, slot)
    info.max = MonOps.calcMaxPp(info.base, info.ups, C.g)
    local t = md and typeName(S, md.type)
    info.sub = (t and (t .. " · ") or "") .. "base PP " .. tostring(info.base or "?")
  else
    info.sub = "No move in this slot"
  end
  info.name = md and md.name or (info.empty and "Empty" or tostring(id))
  return info
end

local function moveCardLayout(C, info, w)
  local Kit, s, row = C.Kit, C.s, C.row
  local pad, gap = 16 * s, 10 * s
  local iw = w - 2 * pad
  local badge = math.floor(30 * s)
  local label = info.empty and "Choose" or "Change"
  local btnOpts = { font = "button", icon = info.empty and "plus" or "pencil", id = "move-" .. info.slot }
  local btnW = Kit.buttonWidth(label, btnOpts, row)
  local xW = info.empty and 0 or row + gap
  local nameW = iw - badge - 12 * s - btnW - xW - gap
  if nameW < 80 * s then
    btnOpts.iconOnly, btnW = true, row
    nameW = iw - badge - 12 * s - btnW - xW - gap
  end
  local subH = Form.wrapH(Kit, "small", info.sub, nameW)
  local headH = math.max(row, Kit.textHeight("button") + 2 * s + subH)
  local L = { pad = pad, gap = gap, iw = iw, badge = badge, label = label, btnOpts = btnOpts, btnW = btnW,
    xW = xW, nameW = nameW, headH = headH }
  local h = pad + headH
  local issues = C.issues.fields
  h = h + Form.issueH(Kit, issues["move" .. info.slot], iw) + (issues["move" .. info.slot] and 6 * s or 0)
  if not info.empty then
    local upsLabelW = Kit.textWidth("small", "PP Ups") + 16 * s
    local maxUps = Limits.mon(C.S, C.mon, "ppup-" .. info.slot).hi
    L.maxUps = maxUps
    L.segW = math.max(Kit.tapMin() * (maxUps + 1), math.min(iw - upsLabelW, 56 * s * (maxUps + 1)))
    L.upsBelow = iw - upsLabelW < L.segW
    h = h + 16 * s + Form.labelH(C.Kit) + row
    h = h + Form.issueH(Kit, issues["pp-" .. info.slot], iw) + (issues["pp-" .. info.slot] and 6 * s or 0)
    h = h + 12 * s + (L.upsBelow and Form.labelH(C.Kit) + row or row)
    h = h + Form.issueH(Kit, issues["ppup-" .. info.slot], iw) + (issues["ppup-" .. info.slot] and 6 * s or 0)
  end
  L.h = h + pad
  return L
end

local function drawMoveCard(C, info, L, x, y, w, h)
  local S, Kit, mon, s, row, issues = C.S, C.Kit, C.mon, C.s, C.row, C.issues.fields
  local slot = info.slot
  local invalid = issues["move" .. slot] or issues["pp-" .. slot] or issues["ppup-" .. slot]
  Theme.fillRounded(x, y, w, h, PAL.rowBg, 0.55, Theme.radius())
  Theme.stroke(x, y, w, h, Theme.radius(), invalid and PAL.red or PAL.cardBorder, invalid and 0.9 or 0.3,
    invalid and 2 * s or 1)
  local ix, cy = x + L.pad, y + L.pad
  local by = cy + (math.min(L.headH, row) - L.badge) / 2
  Theme.strokeRounded(ix, by, L.badge, L.badge, PAL.line, 0.5, 1, 7 * s)
  Kit.textCenter("small", tostring(slot), ix, by + (L.badge - Kit.textHeight("small")) / 2, L.badge, PAL.text)
  local nx = ix + L.badge + 12 * s
  local nameColor = info.empty and PAL.muted or (issues["move" .. slot] and PAL.red or PAL.heading)
  local nameY = cy + math.max(0, (L.headH - Kit.textHeight("button") - 2 * s - Form.wrapH(Kit, "small", info.sub, L.nameW)) / 2)
  Kit.textBold("button", Kit.ellipsize("button", info.name, L.nameW), nx, nameY, nameColor)
  Kit.textWrapped("small", info.sub, nx, nameY + Kit.textHeight("button") + 2 * s, L.nameW, PAL.muted)
  local bx = ix + L.iw - L.xW - L.btnW
  local btnY = cy + (math.min(L.headH, row) - row) / 2
  if Kit.button(bx, btnY, L.btnW, row, L.label, L.btnOpts) then
    Ops.openMovePicker(S, Kit, slot)
  end
  if not info.empty and Kit.iconButton(ix + L.iw - row, btnY, row, row, "x", "Clear slot " .. slot, { kind = "danger" }) then
    Ops.clearMove(S, mon, slot)
  end
  cy = cy + L.headH
  cy = cy + hint(C, "move" .. slot, ix, cy, L.iw)
  if info.empty then return end
  cy = cy + 16 * s
  local ppIssue = issues["pp-" .. slot]
  Form.label(Kit, "PP", ix, cy, L.iw, info.pp .. " / " .. info.max, ppIssue and PAL.red, ppIssue and PAL.red or PAL.text)
  cy = cy + Form.labelH(Kit)
  Form.slider(S, Kit, "pp-" .. slot, info.pp, Limits.mon(S, mon, "pp-" .. slot), ix, cy, L.iw, row, function(n)
    return Ops.setPp(S, mon, slot, n)
  end, ppIssue)
  cy = cy + row
  cy = cy + hint(C, "pp-" .. slot, ix, cy, L.iw) + 12 * s
  local upsIssue = issues["ppup-" .. slot]
  local options = {}
  for i = 0, L.maxUps do options[#options + 1] = { i, tostring(i) } end
  local function apply(v)
    return Ops.setPpUps(S, mon, slot, v)
  end
  if L.upsBelow then
    cy = cy + Form.label(Kit, "PP Ups", ix, cy, L.iw, nil, upsIssue and PAL.red)
    Form.segmented(Kit, "ppup-" .. slot, options, info.ups, ix, cy, L.iw, row, apply, upsIssue)
  else
    Kit.text("small", "PP Ups", ix, cy + (row - Kit.textHeight("small")) / 2, upsIssue and PAL.red or PAL.muted)
    Form.segmented(Kit, "ppup-" .. slot, options, info.ups, ix + L.iw - L.segW, cy, L.segW, row, apply, upsIssue)
  end
  cy = cy + row
  hint(C, "ppup-" .. slot, ix, cy, L.iw)
end

local function movesBody(C, x, y, w)
  local s = C.s
  local gap = 16 * s
  local cols = w >= 3 * 300 * s + 2 * gap and 3 or w >= 2 * 280 * s + gap and 2 or 1
  local cw = (w - (cols - 1) * gap) / cols
  local cy = y
  for first = 1, 4, cols do
    local infos, layouts, rowH = {}, {}, 0
    for slot = first, math.min(4, first + cols - 1) do
      infos[#infos + 1] = moveInfo(C, slot)
      layouts[#layouts + 1] = moveCardLayout(C, infos[#infos], cw)
      rowH = math.max(rowH, layouts[#layouts].h)
    end
    for i, info in ipairs(infos) do
      drawMoveCard(C, info, layouts[i], x + (i - 1) * (cw + gap), cy, cw, info.empty and layouts[i].h or rowH)
    end
    cy = cy + rowH + gap
  end
  return cy - gap - y
end

local function listBody(C, x, y, w, section)
  local S, Kit, mon, g, s, issues, report = C.S, C.Kit, C.mon, C.g, C.s, C.issues, C.report
  local gap, block = 10 * s, 22 * s
  local cy, tail = y, 0
  local function space(n)
    cy, tail = cy + n, n
  end
  local function text(str, color)
    cy = cy + Kit.textWrapped("small", str, x, cy, w, color or PAL.muted)
    space(gap)
  end
  local function item(d, ix, iy, iw)
    local issue = issues.fields[d.key]
    if d.toggle then
      local on = P.get(mon, d)
      on = on == true or on == 1
      local shown = issue and tostring(P.get(mon, d)) or (on and "ON" or "OFF")
      local label = d.label .. ": " .. shown
      local opts = { face = "selection", active = on, font = "small", invalid = issue ~= nil }
      local height = Kit.buttonHeight(label, iw, opts)
      if Kit.button(ix, iy, iw, height, label, opts) then
        Ops.setMonProperty(S, mon, d.key, not on)
      end
      return height + hint(C, d.key, ix, iy + height, iw), gap
    elseif Named.property(S, d) then
      local h = Form.label(Kit, d.label, ix, iy, iw, nil, issue and PAL.red)
      h = h + Form.select(S, Kit, d.key, d.label, P.get(mon, d), Named.property(S, d), ix, iy + h, iw, function(v)
        return Ops.setMonProperty(S, mon, d.key, v)
      end, issue)
      return h + hint(C, d.key, ix, iy + h, iw), block
    end
    local value = P.get(mon, d)
    if type(value) == "number" then
      local label = d.label:gsub(" %(.-%)", "")
      return Form.numberRow(S, Kit, d.key, label, value, Limits.mon(S, mon, d.key), ix, iy, iw, function(n)
        return Ops.setMonProperty(S, mon, d.key, n)
      end, issue), block
    end
    local h = Form.label(Kit, d.label, ix, iy, iw, nil, issue and PAL.red)
    Form.box(Kit, ix, iy + h, iw, C.row, tostring(value or ""), issue ~= nil)
    return h + C.row + hint(C, d.key, ix, iy + h + C.row, iw), block
  end
  local function props(list)
    local cols = w >= 600 * s and 2 or 1
    local colGap = 32 * s
    local cw = (w - (cols - 1) * colGap) / cols
    local col, rowH, rowSpace = 0, 0, 0
    for _, d in ipairs(list) do
      local h, after = item(d, x + col * (cw + colGap), cy, cw)
      rowH, rowSpace = math.max(rowH, h), math.max(rowSpace, after)
      col = col + 1
      if col == cols then
        cy = cy + rowH
        space(rowSpace)
        col, rowH, rowSpace = 0, 0, 0
      end
    end
    if col > 0 then
      cy = cy + rowH
      space(rowSpace)
    end
  end
  if section == "origin" then
    props(P.identity(S))
    if g == 2 and Gen.hasCaughtData(S.save, S.version) then
      cy = cy + Form.label(Kit, "Caught by", x, cy, w)
      Form.segmented(Kit, "caught-by", { { "boy", "Boy" }, { "girl", "Girl" } }, mon.caughtByGender, x, cy, w, C.row,
        function(v)
          return Ops.setCaughtByGender(S, mon, v)
        end)
      cy = cy + C.row
      space(block)
    end
  elseif section == "extras" then
    if g == 3 then
      text("Contest conditions", issues.fields.contest and PAL.red or PAL.heading)
      cy = cy + hint(C, "contest", x, cy - gap, w)
      props(P.contest)
      text("Ribbons: setting a ribbon does not establish award or event eligibility.", issues.fields.ribbons and PAL.red or PAL.heading)
      cy = cy + hint(C, "ribbons", x, cy - gap, w)
      props(P.ribbons)
    else
      text("This generation has no contest conditions or ribbons.")
    end
  else
    text(report.errors > 0 and (report.errors .. " property errors") or "Values pass. Origin still needs checking.",
      report.errors > 0 and PAL.red or PAL.yellow)
    for _, check in ipairs(report.checks) do
      text(check.kind:upper() .. ": " .. check.message,
        check.kind == "error" and PAL.red or check.kind == "pass" and PAL.green or PAL.yellow)
    end
  end
  return cy - tail - y
end

local function sectionBody(C, x, y, w)
  local section = C.S.monSection
  local cy = y
  if C.report.errors > 0 and section ~= "checks" then
    cy = cy + C.Kit.textWrapped("small", C.report.errors .. " saved value errors. Check the red fields.", x, cy, w, PAL.red)
      + 16 * C.s
  end
  if section == "main" then
    return cy - y + mainBody(C, x, cy, w)
  elseif section == "stats" then
    return cy - y + statsBody(C, x, cy, w)
  elseif section == "moves" then
    return cy - y + movesBody(C, x, cy, w)
  end
  return cy - y + listBody(C, x, cy, w, section)
end

local function sectionTools(C)
  local S, mon, g = C.S, C.mon, C.g
  local section = S.monSection
  if section == "main" then
    return "TOOLS", {
      { "Max out", function() Ops.maxMon(S, mon) end, { icon = "chevrons-up", iconInk = PAL.green } },
      { "Fix errors", function() Ops.fixMonErrors(S, mon) end, { icon = "shield-check", iconInk = PAL.green } },
      { "Randomize", function() Ops.randomizeMon(S, mon) end, { icon = "shuffle", iconInk = PAL.blue } },
      { "Clone to a box", function() Ops.cloneMonToBox(S, mon) end, { icon = "copy" } },
    }
  elseif section == "stats" then
    if g == 3 then
      return "STAT TOOLS", {
        { "Max all IVs", function() Ops.maxIvs(S, mon) end, { icon = "chevrons-up", iconInk = PAL.green } },
        { "Clear EVs", function() Ops.clearEvs(S, mon) end, { icon = "x", iconInk = PAL.red } },
      }
    end
    return "STAT TOOLS", {
      { "Max all DVs", function() Ops.maxDvs(S, mon) end, { icon = "chevrons-up", iconInk = PAL.green } },
      { "Max stat training", function() Ops.maxStatExp(S, mon) end, { icon = "chevrons-up", iconInk = PAL.green } },
    }
  elseif section == "moves" then
    local recommend = Ops.recommendState(S, mon)
    return "MOVE TOOLS", {
      { "Max all PP", function() Ops.maxAllPpUps(S, mon) end, { icon = "chevrons-up", iconInk = PAL.green } },
      { ({ pending = "Fetching recommended moveset...", none = "No recommended moveset" })[recommend]
        or "Recommended moveset", function() Ops.recommendMoves(S, mon) end,
        { icon = "sparkles", iconInk = PAL.blue, enabled = recommend == "ready" } },
      { "Reset to learnset", function() Ops.resetMoves(S, mon) end, { icon = "rotate-ccw" } },
    }
  elseif section == "checks" then
    return "TOOLS", {
      { "Fix errors", function() Ops.fixMonErrors(S, mon) end, { icon = "shield-check", iconInk = PAL.green } },
    }
  end
end

local function resetForm(S, Kit, mon)
  if S.formMon ~= mon then
    S.formMon, S.monDrafts, S.inspectorScroll = mon, {}, 0
    S.propertyChoice, S.valueEdit, S._slider = nil, nil, nil
    if Kit.focus and (Kit.focus:match("^property%-") or Kit.focus:match("^value%-edit")) then
      Kit.blur()
    end
  end
end

local function scrollRegion(S, Kit, x, y, w, h)
  if S._slider and S._slider.live then Kit._dragDelta = 0 end
  local key = tostring(Kit._fontKey) .. ":" .. w .. ":" .. h
  if S._formLayoutKey ~= key then
    local scroll = S.inspectorScroll or 0
    local oldMax = math.max(0, (S._formHeight or 0) - (S._formViewHeight or h))
    S._stickBottom = scroll > 0 and scroll >= oldMax - 1
    S._formLayoutKey = key
  end
  if S._stickBottom then return end
  S.inspectorScroll = Kit.scrollPixels(x, y, w, h, S.inspectorScroll or 0, S._formHeight or 0)
end

local function revealFocus(S, Kit, viewH)
  local fo = S._fieldOffset
  if not Kit.focus then
    S._revealedFocus = nil
    return
  end
  if S._revealedFocus == Kit.focus or not fo or fo.id ~= Kit.focus then return end
  S._revealedFocus = Kit.focus
  local scroll = S.inspectorScroll or 0
  if fo.off < scroll or fo.off + fo.h > scroll + viewH then
    S.inspectorScroll = Ops.clamp(fo.off - 12 * Kit.scale, 0, math.max(0, (S._formHeight or 0) - viewH))
  end
end

local function settleScroll(S, contentH, viewH)
  S._formHeight, S._formViewHeight = contentH, viewH
  local max = math.max(0, contentH - viewH)
  S.inspectorScroll = S._stickBottom and max or Ops.clamp(S.inspectorScroll or 0, 0, max)
  S._stickBottom = nil
end

local function drawFixed(C, x, y, w, h)
  local S, Kit, s, row = C.S, C.Kit, C.s, C.row
  local pad = 20 * s
  local cx, inner = x + pad, w - 2 * pad
  local heroH = drawHero(C, cx, y + pad, inner, false)
  local navY = y + pad + heroH + 10 * s
  drawNav(C, cx - 4 * s, navY, inner + 4 * s, false)
  Theme.col(PAL.cardBorder, 0.25)
  love.graphics.rectangle("fill", x, navY + row, w, 1)
  local caption, tools = sectionTools(C)
  local footerH = tools and Form.flowH(Kit, caption, tools, inner) + 2 * 14 * s or 0
  local bodyY = navY + row + 1
  local bodyH = math.max(0, y + h - footerH - bodyY)
  Motion.pages(S, Kit, "monSection", x, bodyY, w, bodyH, function(st, kit, px, py, pw, ph)
    local top = py + 20 * s
    local viewH = math.max(0, ph - 20 * s)
    scrollRegion(st, kit, px + pad, top, pw - 2 * pad, viewH)
    revealFocus(st, kit, viewH)
    kit.pushClip(px + pad, top, pw - 2 * pad, viewH)
    C.contentTop = top - (st.inspectorScroll or 0)
    local contentH = sectionBody(C, px + pad, C.contentTop, pw - 2 * pad) + 20 * s
    kit.popClip()
    settleScroll(st, contentH, viewH)
    kit.scrollbar(px + pad, top, pw - 2 * pad, viewH, st.inspectorScroll, contentH, viewH)
  end)
  if tools then
    local fy = y + h - footerH
    Theme.col(PAL.cardBorder, 0.25)
    love.graphics.rectangle("fill", x, fy, w, 1)
    Form.flow(Kit, caption, tools, cx, fy + 14 * s, inner)
  end
end

local function drawStacked(C, x, y, w, h, prelude)
  local S, Kit, s, row = C.S, C.Kit, C.s, C.row
  local pad = (prelude and 18 or 16) * s
  local edge = prelude and 0 or 12 * s
  if not prelude then Kit.card(x, y, w, h) end
  local vx, vy, vw, vh = x + edge, y + edge, w - 2 * edge, h - 2 * edge
  scrollRegion(S, Kit, vx, vy, vw, vh)
  revealFocus(S, Kit, vh)
  Kit.pushClip(vx, vy, vw, vh)
  local top = vy - (S.inspectorScroll or 0)
  C.contentTop = top
  local cy = top
  local cw = prelude and vw - 12 * s or vw
  if prelude then
    cy = cy + prelude(vx, cy, cw) + 16 * s
  end
  local cardTop = cy
  if prelude then Kit.card(vx, cardTop, cw, S._stackCardH or vh) end
  local cx, inner = vx + pad, cw - 2 * pad
  if C.mon then
    cy = cy + pad
    cy = cy + drawHero(C, cx, cy, inner, inner < 560 * s) + 14 * s
    S._navOffset = cy - top
    S._navKeep = math.min(S.inspectorScroll or 0, S._navOffset)
    drawNav(C, cx - 4 * s, cy, inner + 4 * s, true)
    cy = cy + row
    Theme.col(PAL.cardBorder, 0.25)
    love.graphics.rectangle("fill", vx, cy, cw, 1)
    cy = cy + 20 * s
    cy = cy + sectionBody(C, cx, cy, inner) + 20 * s
    local caption, tools = sectionTools(C)
    if tools then
      Theme.col(PAL.cardBorder, 0.25)
      love.graphics.rectangle("fill", vx, cy, cw, 1)
      cy = cy + 14 * s
      cy = cy + Form.flow(Kit, caption, tools, cx, cy, inner) + 14 * s
    end
  else
    cy = cy + pad
    cy = cy + Kit.textWrapped("button", "Select a Pokemon to edit its properties, stats, moves and origin.",
      cx, cy, inner, PAL.muted) + pad
  end
  S._stackCardH = cy - cardTop
  Kit.popClip()
  local contentH = cy - top
  settleScroll(S, contentH, vh)
  Kit.scrollbar(vx + vw - 7 * s, vy, 0, vh, S.inspectorScroll, contentH, vh)
end

function Body.stacked(Kit, w, h)
  return w < 600 * Kit.scale or h < 520 * Kit.scale
end

function Body.draw(S, Kit, x, y, w, h, prelude)
  local mon = S.editingMon
  local s = Kit.scale
  local C = { S = S, Kit = Kit, mon = mon, g = Gen.ofState(S), s = s, row = Kit.controlH() }
  if mon then
    C.report = Legality.mon(S, mon)
    C.issues = Legality.highlights(C.report, mon)
    C.def = (S.data and S.data.pokemon and S.data.pokemon[mon.species or mon.speciesId]) or nil
  end
  resetForm(S, Kit, mon)
  S.monSection = S.monSection or "main"
  if prelude or Body.stacked(Kit, w, h) or not mon then
    return drawStacked(C, x, y, w, h, prelude)
  end
  Kit.card(x, y, w, h)
  drawFixed(C, x, y, w, h)
end

return Body
