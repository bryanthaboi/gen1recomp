local Kit = require("src.ui.kit.Kit")
local Theme = require("src.ui.kit.Theme")
local Strings = require("src.core.Strings")
local GameVersion = require("src.core.GameVersion")
local Ui = require("src.import.online.Ui")

local PAL = Theme.PAL

local Wizard = {}

local function LV() return require("src.import.LauncherView") end
local function OP() return require("src.import.OnlinePanel") end
local function Sprites() return require("src.online.OnlineSprites") end

local SPECTATOR_CHOICES = { 0, 4, 8, 16 }

Wizard.SPECTATOR_CHOICES = SPECTATOR_CHOICES

local function chipRow(imp, x, y, w, m, label, id, options, isOn, onPick)
  local _, gap, tiny = Ui.pads(m)
  local h = math.max(m.btnH, Kit.tapMin())
  local cy = y
  if label then cy = cy + Ui.label(label, x, cy) + tiny end
  local n = math.max(1, #options)
  local perRow = math.min(n, (m.twoCol and 4) or 2)
  local chipW = math.floor((w - gap * (perRow - 1)) / perRow)
  local col = 0
  for _, option in ipairs(options) do
    local cx = x + (col % perRow) * (chipW + gap)
    local key = id .. "-" .. tostring(option.id)
    if Kit.chip(cx, cy, chipW, h, Kit.ellipsize("small", option.label, chipW),
                isOn(option), PAL.lineStrong, key) then
      local pick = option
      LV().queueAction(imp, key, function() onPick(pick) end)
    end
    col = col + 1
    if col % perRow == 0 then cy = cy + h + tiny end
  end
  if col % perRow ~= 0 then cy = cy + h + tiny end
  return (cy - y) + gap - tiny
end

Wizard.chipRow = chipRow

-- ------------------------------------------------------------------ steps

local function stepGame(imp, x, y, w, m)
  local OnlinePanel = OP()
  local st = OnlinePanel.state(imp)
  local c = OnlinePanel.cache(imp)
  local _, gap = Ui.pads(m)
  local cy = y
  local versions = OnlinePanel.readyVersions(imp)
  if #versions == 0 then
    Kit.emptyBox(x, cy, w, math.max(m.rowH, Kit.tapMin()),
      Strings("Import a game first."))
    return math.max(m.rowH, Kit.tapMin()) + gap
  end
  local options = {}
  for _, id in ipairs(versions) do
    local info = GameVersion.info(id)
    options[#options + 1] = { id = id, label = (info and info.name) or id }
  end
  cy = cy + chipRow(imp, x, cy, w, m, Strings("Game"), "online-game", options,
    function(option) return option.id == OnlinePanel.selectedVersion(imp) end,
    function(option)
      st.version, st.slotId, st.cartId, st.team = option.id, nil, nil, {}
      st.slotRead, st.ready, st.kind = nil, false, "vanilla"
      st.versionPicked = true
      OnlinePanel.invalidate(imp)
    end)

  local arena = { { id = "vanilla", label = Strings("Vanilla") } }
  for _, row in ipairs(c.carts) do
    arena[#arena + 1] = { id = row.id, label = row.title, cart = true }
  end
  cy = cy + chipRow(imp, x, cy, w, m, Strings("Arena"), "online-arena", arena,
    function(option)
      if option.cart then return st.kind == "cart" and st.cartId == option.id end
      return st.kind ~= "cart"
    end,
    function(option)
      if option.cart then
        st.kind, st.cartId = "cart", option.id
      else
        st.kind, st.cartId = "vanilla", nil
      end
      st.slotId, st.team, st.slotRead, st.ready = nil, {}, nil, false
      OnlinePanel.invalidate(imp)
    end)
  if #c.carts == 0 then
    cy = cy + Kit.textWrapped("micro",
      Strings("No sealed carts on this machine."), x, cy, w, PAL.faint, 1)
      + gap
  end
  return cy - y
end

local function stepSave(imp, x, y, w, availH, m)
  local OnlinePanel = OP()
  local st = OnlinePanel.state(imp)
  local c = OnlinePanel.cache(imp)
  local _, gap, tiny = Ui.pads(m)
  local rowH = math.max(m.rowH, Kit.tapMin())
  local cy = y + Ui.label(Strings("Save"), x, y) + tiny
  if #c.slots == 0 then
    Kit.emptyBox(x, cy, w, rowH, Strings("No save in this game yet."))
    return (cy - y) + rowH + gap
  end
  imp._pages = imp._pages or {}
  local pageKey = "online-slots"
  local perPage = Kit.rowsThatFit(math.max(rowH * 2, availH), rowH, tiny, 2, 6)
  local first, last, pageNow = Kit.pageBounds(imp._pages[pageKey] or 1,
    #c.slots, perPage)
  imp._pages[pageKey] = pageNow
  for i = first, last do
    local row = c.slots[i]
    local id = row.id
    local ink = LV().rowHit(imp, x, cy, w, rowH, st.slotId == id,
      "online-slot-" .. id, function()
        st.slotId, st.team, st.slotRead, st.ready = id, {}, nil, false
        OnlinePanel.invalidate(imp, "party", "summary")
      end)
    Kit.text("small", Kit.ellipsize("small", row.label,
      w - math.floor(20 * m.s)), x + math.floor(10 * m.s),
      cy + math.floor(5 * m.s), ink or PAL.heading)
    Kit.text("micro", row.sub, x + math.floor(10 * m.s),
      cy + rowH - Kit.textHeight("micro") - math.floor(5 * m.s), PAL.muted)
    cy = cy + rowH + tiny
  end
  if #c.slots > perPage then
    local page, ph = Kit.pager(x, cy, w, pageNow, #c.slots, perPage, pageKey)
    imp._pages[pageKey] = page
    cy = cy + ph
  end
  return (cy - y) + gap
end

function Wizard.monRow(imp, row, x, y, w, m, onPick)
  local rowH = math.max(m.rowH, Kit.tapMin())
  local sprites = Sprites()
  local iconSize = math.max(16, math.floor(rowH * 0.62))
  local ink = LV().rowHit(imp, x, y, w, rowH, row.order ~= nil,
    "online-mon-" .. row.key, onPick)
  local tx = x + math.floor(10 * m.s)
  local sprite = sprites.get(row.version, row.mon)
  if sprite and sprites.drawIcon(sprite, tx, y + (rowH - iconSize) / 2,
      iconSize) then
    tx = tx + iconSize + math.floor(6 * m.s)
  end
  if row.order then
    Kit.textBold("small", ("%d."):format(row.order), tx,
      y + (rowH - Kit.textHeight("small")) / 2, ink or PAL.heading)
    tx = tx + math.floor(20 * m.s)
  end
  local textW = w - (tx - x) - math.floor(10 * m.s)
  Kit.text("small", Kit.ellipsize("small", row.label, textW), tx,
    y + math.floor(5 * m.s),
    row.refused and PAL.faint or (ink or PAL.text))
  local sub = row.note or ((row.where == "box") and row.source or nil)
  if sub then
    Kit.text("micro", Kit.ellipsize("micro", sub, textW), tx,
      y + rowH - Kit.textHeight("micro") - math.floor(5 * m.s),
      row.refused and PAL.red or PAL.faint)
  end
  return rowH
end

local function stepTeam(imp, x, y, w, m)
  local OnlinePanel = OP()
  local st = OnlinePanel.state(imp)
  local c = OnlinePanel.cache(imp)
  local _, gap, tiny = Ui.pads(m)
  local rowH = math.max(m.rowH, Kit.tapMin())
  local btnH = math.max(m.btnH, Kit.tapMin())
  local cy = y

  local generations = OnlinePanel.installedGenerations(imp)
  if #generations > 1 and OnlinePanel.crossGen(imp) then
    cy = cy + Kit.textWrapped("small",
      Strings("Time Capsule: your team is converted for %s.",
        tostring(OnlinePanel.engineVersion(imp) or "?")),
      x, cy, w, PAL.yellow, 2) + tiny
  end

  local target = st.wizard and st.wizard.kind == "join" and st.joinTarget
  if target and type(target.rule) == "table" then
    local want, have = OnlinePanel.teamCap(imp), #(st.team or {})
    cy = cy + Kit.textWrapped("small",
      Strings("Pick %d POKeMON (%d of %d picked)  -  %s", want, have, want,
        OnlinePanel.ruleText(target.rule)),
      x, cy, w, have == want and PAL.green or PAL.yellow, 2) + tiny
  end
  cy = cy + Ui.label(Strings("Your party"), x, cy) + tiny
  if #c.party == 0 then
    Kit.emptyBox(x, cy, w, rowH,
      c.partyReason or Strings("That save has no POKeMON."))
    cy = cy + rowH + tiny
  else
    local box = math.floor(56 * m.s)
    local listW = w - box - gap
    local listY = cy
    for _, row in ipairs(c.party) do
      local ref = row.ref
      cy = cy + Wizard.monRow(imp, row, x, cy, listW, m, function()
        st.focusMon = row.key
        if row.refused then return end
        OnlinePanel.toggleTeam(st.team, ref, OnlinePanel.teamCap(imp))
        st.ready = false
        OnlinePanel.invalidate(imp, "party", "summary")
      end) + tiny
    end
    local focus
    for _, row in ipairs(c.party) do
      if row.key == st.focusMon then focus = row end
    end
    focus = focus or c.team[1] or c.party[1]
    if focus then
      local sprite = Sprites().get(focus.version, focus.mon)
      if sprite then
        Sprites().drawFront(sprite, x + listW + gap, listY, box)
        Kit.text("micro", Kit.ellipsize("micro",
          OP().gen3Name(focus.mon)
            or OP().speciesText(focus.version, focus.mon.species), box),
          x + listW + gap,
          listY + box, PAL.faint)
      end
    end
  end

  LV().btn(imp, x, cy, w, btnH, "online-team-pc", Strings("From PC"),
    { kind = "ghost", font = "small", enabled = st.slotId ~= nil,
      action = function() OnlinePanel.pcOpen(imp) end })
  cy = cy + btnH + gap

  cy = cy + Ui.label(Strings("Picked (%d)", #(st.team or {})), x, cy) + tiny
  if #(c.team or {}) == 0 then
    Kit.emptyBox(x, cy, w, rowH,
      Strings("Tap a POKeMON above, or pull one out of the PC."))
    cy = cy + rowH + tiny
  else
    for _, row in ipairs(c.team) do
      if row then
        local ref = row.ref
        cy = cy + Wizard.monRow(imp, row, x, cy, w, m, function()
          OnlinePanel.toggleTeam(st.team, ref, OnlinePanel.TEAM_MAX)
          OnlinePanel.invalidate(imp, "party", "summary")
        end) + tiny
      end
    end
  end
  if c.teamNote and not c.teamOk then
    cy = cy + Kit.textWrapped("small", tostring(c.teamNote):gsub("\n", " "),
      x, cy, w, PAL.yellow, 2) + tiny
  end
  return (cy - y) + gap
end

local function stepRules(imp, x, y, w, m)
  local OnlinePanel = OP()
  local st = OnlinePanel.state(imp)
  local _, gap, tiny = Ui.pads(m)
  local rowH = math.max(m.btnH, Kit.tapMin())
  local cy = y
  local rule = OnlinePanel.ruleFor(imp)
  local function bump()
    OnlinePanel.editRule(imp)
    st.ready = false
    OnlinePanel.invalidate(imp, "party", "summary")
  end
  local third = m.twoCol and math.floor((w - 2 * gap) / 3) or w

  cy = cy + Ui.label(Strings("How many POKeMON each"), x, cy) + tiny
  Ui.chooser(imp, x, cy, third, rowH, "online-size",
    ("%d v %d"):format(rule.partySize or 1, rule.partySize or 1),
    function()
      rule.partySize = Ui.cycle(OnlinePanel.SIZES, rule.partySize, -1)
      bump()
    end,
    function()
      rule.partySize = Ui.cycle(OnlinePanel.SIZES, rule.partySize, 1)
      bump()
    end)
  cy = cy + rowH + gap

  cy = cy + Ui.label(Strings("Levels"), x, cy) + tiny
  local col2 = m.twoCol and (x + third + gap) or x
  local row2 = m.twoCol and cy or (cy + rowH + tiny)
  Ui.chooser(imp, x, cy, third, rowH, "online-min",
    rule.minLevel and ("Lv%d+"):format(rule.minLevel) or Strings("Any min"),
    function()
      rule.minLevel = Ui.cycle(OnlinePanel.LEVELS, rule.minLevel, -1)
      bump()
    end,
    function()
      rule.minLevel = Ui.cycle(OnlinePanel.LEVELS, rule.minLevel, 1)
      bump()
    end)
  Ui.chooser(imp, col2, row2, third, rowH, "online-max",
    rule.maxLevel and ("Lv%d-"):format(rule.maxLevel) or Strings("Any max"),
    function()
      rule.maxLevel = Ui.cycle(OnlinePanel.LEVELS, rule.maxLevel, -1)
      bump()
    end,
    function()
      rule.maxLevel = Ui.cycle(OnlinePanel.LEVELS, rule.maxLevel, 1)
      bump()
    end)
  cy = row2 + rowH + gap

  cy = cy + Ui.label(Strings("Force every level"), x, cy) + tiny
  Ui.chooser(imp, x, cy, third, rowH, "online-force",
    rule.forceLevel and ("All Lv%d"):format(rule.forceLevel)
      or Strings("Own levels"),
    function()
      rule.forceLevel = Ui.cycle(OnlinePanel.FORCE_LEVELS, rule.forceLevel, -1)
      bump()
    end,
    function()
      rule.forceLevel = Ui.cycle(OnlinePanel.FORCE_LEVELS, rule.forceLevel, 1)
      bump()
    end)
  cy = cy + rowH + gap
  return cy - y
end

local function stepVisibility(imp, x, y, w, m)
  local OnlinePanel = OP()
  local st = OnlinePanel.state(imp)
  local _, gap, tiny = Ui.pads(m)
  local btnH = math.max(m.btnH, Kit.tapMin())
  local cy = y
  cy = cy + chipRow(imp, x, cy, w, m, Strings("Visibility"), "online-visible",
    { { id = "public", label = Strings("Public") },
      { id = "code", label = Strings("Code only") } },
    function(option)
      if option.id == "public" then return st.public ~= false end
      return st.public == false
    end,
    function(option) st.public = option.id == "public" end)
  cy = cy + Kit.textWrapped("micro", st.public == false
    and Strings("Only trainers you give the code to can join.")
    or Strings("Anyone browsing Play sees this lobby."),
    x, cy, w, PAL.faint, 2) + gap
  cy = cy + Ui.label(Strings("Note (optional)"), x, cy) + tiny
  Ui.field(imp, x, cy, w, btnH, "online-note", st.note,
    Strings("Say something, like first to three"),
    imp._onlineFocus == "online-note", function(text) st.note = text end)
  cy = cy + btnH + gap
  return cy - y
end

local function stepPlaying(imp, x, y, w, m)
  local OnlinePanel = OP()
  local st = OnlinePanel.state(imp)
  local _, gap = Ui.pads(m)
  local cy = y + chipRow(imp, x, y, w, m, Strings("Your seat"),
    "online-tour-playing",
    { { id = "play", label = Strings("Play in it") },
      { id = "organize", label = Strings("Organize and watch") } },
    function(option)
      if option.id == "play" then return st.tourPlaying ~= false end
      return st.tourPlaying == false
    end,
    function(option)
      st.tourPlaying = option.id == "play"
      OnlinePanel.invalidate(imp, "summary")
    end)
  cy = cy + Kit.textWrapped("micro", st.tourPlaying == false
    and Strings("You run the bracket and never take a seat in it.")
    or Strings("You take one of the seats in the bracket."),
    x, cy, w, PAL.faint, 2) + gap
  return cy - y
end

local function stepShotClock(imp, x, y, w, m)
  local OnlinePanel = OP()
  local st = OnlinePanel.state(imp)
  local _, gap = Ui.pads(m)
  local options = {}
  for _, seconds in ipairs(OnlinePanel.SHOT_CLOCKS) do
    options[#options + 1] = { id = seconds,
      label = Strings("%d seconds", seconds) }
  end
  local cy = y + chipRow(imp, x, y, w, m, Strings("Thinking time a move"),
    "online-shot", options,
    function(option) return option.id == st.tourShotClock end,
    function(option) st.tourShotClock = option.id end)
  cy = cy + Kit.textWrapped("micro",
    Strings("Thinking time for each move. Run out and the move is picked for you."),
    x, cy, w, PAL.faint, 2) + gap
  return cy - y
end

local function stepSpectators(imp, x, y, w, m)
  local OnlinePanel = OP()
  local st = OnlinePanel.state(imp)
  local _, gap = Ui.pads(m)
  local options = {}
  for _, n in ipairs(SPECTATOR_CHOICES) do
    options[#options + 1] = { id = n,
      label = (n == 0) and Strings("None") or Strings("Up to %d", n) }
  end
  local cy = y + chipRow(imp, x, y, w, m, Strings("How many can watch"),
    "online-spectators", options,
    function(option) return option.id == (tonumber(st.tourSpectators) or 0) end,
    function(option) st.tourSpectators = option.id end)
  cy = cy + Kit.textWrapped("micro",
    Strings("How many people can watch the bracket play out."),
    x, cy, w, PAL.faint, 2) + gap
  return cy - y
end

local function stepRole(imp, x, y, w, m)
  local OnlinePanel = OP()
  local st = OnlinePanel.state(imp)
  local tr = OnlinePanel.tradeState(imp)
  local _, gap, tiny = Ui.pads(m)
  local btnH = math.max(m.btnH, Kit.tapMin())
  local cy = y + chipRow(imp, x, y, w, m, Strings("Trade"), "online-trade-role",
    { { id = "host", label = Strings("Host a trade") },
      { id = "join", label = Strings("Join with a code") } },
    function(option) return option.id == (st.tradeRole or "host") end,
    function(option) st.tradeRole = option.id end)
  if (st.tradeRole or "host") == "join" then
    cy = cy + Ui.label(Strings("Trade code"), x, cy) + tiny
    Ui.field(imp, x, cy, w, btnH, "online-trade-code", tr.code,
      Strings("Six characters"), imp._onlineFocus == "online-trade-code",
      function(text) tr.code = OnlinePanel.sanitizeCode(text) end)
    cy = cy + btnH + gap
  else
    cy = cy + Kit.textWrapped("micro",
      Strings("You get a code to give the other trainer."),
      x, cy, w, PAL.faint, 2) + gap
  end
  local refusal = OnlinePanel.remoteTradeRefusal(imp)
  if refusal then
    cy = cy + Kit.textWrapped("small", refusal, x, cy, w, PAL.yellow, 2) + gap
  end
  return cy - y
end

local function stepSummary(imp, x, y, w, m)
  local OnlinePanel = OP()
  local _, gap, tiny = Ui.pads(m)
  local rowH = math.max(m.rowH, Kit.tapMin())
  local btnH = math.max(m.btnH, Kit.tapMin())
  local changeW = math.floor(84 * m.s)
  local cy = y
  for _, answer in ipairs(OnlinePanel.wizardAnswers(imp)) do
    Kit.card(x, cy, w, rowH, "badge")
    local tx = x + math.floor(10 * m.s)
    Kit.text("micro", answer.label, tx, cy + math.floor(5 * m.s), PAL.muted)
    Kit.text("small", Kit.ellipsize("small", answer.value,
      w - changeW - math.floor(28 * m.s)), tx,
      cy + rowH - Kit.textHeight("small") - math.floor(5 * m.s), PAL.heading)
    local step = answer.step
    LV().btn(imp, x + w - changeW - math.floor(8 * m.s),
      cy + (rowH - btnH) / 2, changeW, btnH,
      "online-change-" .. step, Strings("Change"),
      { kind = "ghost", font = "small",
        action = function() OnlinePanel.wizardTo(imp, step) end })
    cy = cy + rowH + tiny
  end
  return (cy - y) + gap
end

local BODIES = {
  game = function(imp, x, y, w, availH, m) return stepGame(imp, x, y, w, m) end,
  save = stepSave,
  team = function(imp, x, y, w, availH, m) return stepTeam(imp, x, y, w, m) end,
  rules = function(imp, x, y, w, availH, m) return stepRules(imp, x, y, w, m) end,
  visibility = function(imp, x, y, w, availH, m)
    return stepVisibility(imp, x, y, w, m)
  end,
  playing = function(imp, x, y, w, availH, m)
    return stepPlaying(imp, x, y, w, m)
  end,
  shotclock = function(imp, x, y, w, availH, m)
    return stepShotClock(imp, x, y, w, m)
  end,
  spectators = function(imp, x, y, w, availH, m)
    return stepSpectators(imp, x, y, w, m)
  end,
  role = function(imp, x, y, w, availH, m) return stepRole(imp, x, y, w, m) end,
  summary = function(imp, x, y, w, availH, m)
    return stepSummary(imp, x, y, w, m)
  end,
}

Wizard.BODIES = BODIES

function Wizard.draw(imp, x, y, w, availH, m)
  local OnlinePanel = OP()
  local _, gap, tiny = Ui.pads(m)
  local btnH = math.max(m.btnH, Kit.tapMin())
  local def = OnlinePanel.wizardDef(imp)
  if not def then
    local cy = y + Ui.header(imp, x, y, w, m, Strings("Set up"))
    Kit.emptyBox(x, cy, w, m.rowH * 2, Strings("Nothing to set up."))
    return (cy - y) + m.rowH * 2
  end
  local id, at, total = OnlinePanel.wizardStep(imp)
  local cy = y + Ui.header(imp, x, y, w, m, Strings(def.title),
    ("%d/%d"):format(at or 1, total or 1), PAL.lineStrong)
  Kit.textBold("button", Strings(OnlinePanel.STEP_TITLE[id] or id), x, cy,
    PAL.heading)
  cy = cy + Kit.textHeight("button") + tiny

  local body = math.max(m.rowH * 2, availH - (cy - y) - btnH * 2)
  local run = BODIES[id] or BODIES.summary
  cy = cy + run(imp, x, cy, w, body, m)

  local last = (at or 1) >= (total or 1)
  local half = math.floor((w - gap) / 2)
  LV().btn(imp, x, cy, half, btnH, "online-wizard-back", Strings("Back"),
    { kind = "ghost", font = "small",
      action = function() OnlinePanel.wizardBack(imp) end })
  LV().btn(imp, x + half + gap, cy, w - half - gap, btnH,
    "online-wizard-next",
    last and Strings(def.confirm) or Strings("Next"),
    { kind = "primary", font = "small",
      enabled = OnlinePanel.wizardReady(imp),
      action = function() OnlinePanel.wizardNext(imp) end })
  cy = cy + btnH + tiny
  cy = cy + Ui.statusLine(imp, x, cy, w, m)
  return cy - y
end

return Wizard
