local Kit = require("src.ui.kit.Kit")
local Theme = require("src.ui.kit.Theme")
local Strings = require("src.core.Strings")
local Ui = require("src.import.online.Ui")

local PAL = Theme.PAL

local TradeScreen = {}

local function LV() return require("src.import.LauncherView") end
local function OP() return require("src.import.OnlinePanel") end
local function Client() return require("src.online.Client") end
local function Sprites() return require("src.online.OnlineSprites") end

local function rowId(side, row, at)
  local key = tostring(row.key or row.index or at):gsub("|", "-")
  return ("online-trade-%s-%s"):format(side, key)
end

local function column(imp, x, y, w, m, side, rows, onPick)
  local _, gap, tiny = Ui.pads(m)
  local rowH = math.max(m.rowH, Kit.tapMin())
  local cy = y
  if #rows == 0 then
    Kit.emptyBox(x, cy, w, rowH, Strings("No POKéMON here."))
    return rowH + gap
  end
  local sprites = Sprites()
  local iconSize = math.max(16, math.floor(rowH * 0.62))
  for at, row in ipairs(rows) do
    local pick = row.ref ~= nil and row.ref or row.index
    local ink = LV().rowHit(imp, x, cy, w, rowH, row.picked,
      rowId(side, row, at), function()
        if row.pickable == false then return end
        onPick(pick)
      end)
    local tx = x + math.floor(10 * m.s)
    local sprite = sprites.get(row.version, row.mon)
    if sprite and sprites.drawIcon(sprite, tx, cy + (rowH - iconSize) / 2,
        iconSize) then
      tx = tx + iconSize + math.floor(6 * m.s)
    end
    Kit.text("small", Kit.ellipsize("small", row.label,
      w - (tx - x) - math.floor(10 * m.s)), tx,
      cy + (rowH - Kit.textHeight("small")) / 2,
      (row.pickable == false) and PAL.faint or (ink or PAL.text))
    cy = cy + rowH + tiny
  end
  return (cy - y) + gap
end

local function localTrade(imp, x, y, w, m)
  local OnlinePanel = OP()
  local tr = OnlinePanel.tradeState(imp)
  local c = OnlinePanel.cache(imp)
  local _, gap, tiny = Ui.pads(m)
  local rowH = math.max(m.btnH, Kit.tapMin())
  local cy = y
  local colW = math.floor((w - gap) / 2)

  if #c.tradeSlots < 2 then
    Kit.emptyBox(x, cy, w, rowH * 2,
      Strings("Trading needs two saves on this machine."))
    return (rowH * 2) + gap
  end

  cy = cy + Ui.label(Strings("Saves"), x, cy) + tiny
  for i, side in ipairs({ "a", "b" }) do
    local entry = tr.sides[side]
    Ui.chooser(imp, x + (i - 1) * (colW + gap), cy, colW, rowH,
      "online-trade-slot-" .. side,
      entry and entry.label or Strings("Pick a save"),
      function() OnlinePanel.tradeCycleSide(imp, side, -1) end,
      function() OnlinePanel.tradeCycleSide(imp, side, 1) end)
  end
  cy = cy + rowH + gap

  local tallest = 0
  for i, side in ipairs({ "a", "b" }) do
    local sx = x + (i - 1) * (colW + gap)
    local view = OnlinePanel.tradeSideView(imp, side)
    local h
    if view and not view.handle then
      Kit.emptyBox(sx, cy, colW, rowH,
        tostring(view.reason or "that save can't be read"))
      h = rowH + gap
    else
      h = column(imp, sx, cy, colW, m, side, c.tradeRows[side] or {},
        function(ref) OnlinePanel.tradePick(imp, side, ref) end)
      if OnlinePanel.tradePcAllowed(imp, side) then
        LV().btn(imp, sx, cy + h, colW, rowH, "online-trade-pc-" .. side,
          Strings("From PC"),
          { kind = "ghost", font = "small",
            action = function()
              OnlinePanel.pcOpen(imp, { side = side })
            end })
        h = h + rowH + tiny
      end
    end
    tallest = math.max(tallest, h)
  end
  cy = cy + tallest

  LV().btn(imp, x, cy, w, rowH, "online-trade-preview", Strings("Preview"),
    { kind = "primary", font = "small",
      enabled = tr.picks.a ~= nil and tr.picks.b ~= nil,
      action = function() OnlinePanel.tradeModalPreview(imp) end })
  cy = cy + rowH + tiny

  if tr.status then
    cy = cy + Kit.textWrapped("small", tostring(tr.status), x, cy, w,
      tr.statusOk and PAL.green or PAL.yellow, 3) + tiny
  end
  return cy - y
end

local function remoteTrade(imp, x, y, w, m)
  local OnlinePanel = OP()
  local st = OnlinePanel.state(imp)
  local tr = OnlinePanel.tradeState(imp)
  local _, gap, tiny = Ui.pads(m)
  local rowH = math.max(m.btnH, Kit.tapMin())
  local cy = y
  local colW = math.floor((w - gap) / 2)
  local online = Client().state() == "online"

  if tr.remote then
    local stage = tr.remote:stage()
    cy = cy + Kit.textWrapped("small", OnlinePanel.remoteStageText(stage),
      x, cy, w, PAL.heading, 2) + tiny
    local mine, theirs = OnlinePanel.remoteRows(tr.remote)
    local peer = tr.peerName or Strings("The other trainer")
    local give, get
    for _, row in ipairs(mine) do if row.picked then give = row.label end end
    for _, row in ipairs(theirs) do if row.picked then get = row.label end end
    if give or get then
      cy = cy + Kit.textWrapped("small",
        Strings("You give %s, you get %s", give or "...", get or "..."),
        x, cy, w, PAL.muted, 2) + tiny
    end
    local note = OnlinePanel.remoteNote(tr.remote)
    if note and stage == "picking" then
      cy = cy + Kit.textWrapped("small", note, x, cy, w, PAL.yellow, 2) + tiny
    end
    local third = math.floor((w - 2 * gap) / 3)
    LV().btn(imp, x, cy, third, rowH, "online-trade-yes", Strings("Confirm"),
      { kind = "primary", font = "small", enabled = stage == "confirming",
        action = function() OnlinePanel.remoteConfirm(imp, true) end })
    LV().btn(imp, x + third + gap, cy, third, rowH, "online-trade-no",
      Strings("Say no"),
      { kind = "ghost", font = "small", enabled = stage == "confirming",
        action = function() OnlinePanel.remoteConfirm(imp, false) end })
    LV().btn(imp, x + 2 * (third + gap), cy, third, rowH,
      "online-trade-cancel", Strings("Cancel"),
      { kind = "danger", font = "small",
        enabled = stage ~= "exchange" and stage ~= "commit_wait",
        action = function() OnlinePanel.remoteCancel(imp) end })
    cy = cy + rowH + gap
    Ui.label(Strings("Your POKéMON"), x, cy)
    cy = cy + Ui.label(Strings("%s's POKéMON", tostring(peer)),
      x + colW + gap, cy) + tiny
    local left = column(imp, x, cy, colW, m, "mine", mine, function(ref)
      OnlinePanel.remotePick(imp, ref)
    end)
    local right = column(imp, x + colW + gap, cy, colW, m, "theirs", theirs,
      function() end)
    cy = cy + math.max(left, right)
    return cy - y
  end

  local refusal = OnlinePanel.remoteTradeRefusal(imp)
  if refusal and st.slotId then
    cy = cy + Kit.textWrapped("small", refusal, x, cy, w, PAL.yellow, 3) + tiny
  end
  LV().btn(imp, x, cy, w, rowH, "online-trade-remote-start",
    Strings("Set up a trade"),
    { kind = "primary", font = "small", enabled = online,
      action = function() OnlinePanel.startWizard(imp, "tradeRemote") end })
  cy = cy + rowH + tiny

  local note = tr.remoteError or tr.remoteResult or tr.status
  if note then
    cy = cy + Kit.textWrapped("small", tostring(note), x, cy, w,
      tr.remoteError and PAL.red or PAL.muted, 3) + tiny
  end
  return cy - y
end

local MODES = {
  { id = "local", title = "On this device",
    note = "Trade between two saves on this device." },
  { id = "remote", title = "Over the internet",
    note = "Trade with another trainer over the relay." },
}

function TradeScreen.draw(imp, x, y, w, availH, m)
  local OnlinePanel = OP()
  local tr = OnlinePanel.tradeState(imp)
  local _, gap, tiny = Ui.pads(m)
  local rowH = math.max(m.btnH, Kit.tapMin())
  local cy = y + Ui.header(imp, x, y, w, m, Strings("Trade"))

  if tr.remote then tr.chosen = true end
  if not tr.chosen then
    local cardH = math.max(math.floor(74 * m.s), m.rowH * 2)
    if m.twoCol then
      local colW = math.floor((w - gap) / 2)
      for i, mode in ipairs(MODES) do
        local id = mode.id
        Ui.entryCard(imp, x + (i - 1) * (colW + gap), cy, colW, cardH,
          "online-trade-mode-" .. id, Strings(mode.title), Strings(mode.note),
          true, function()
            OnlinePanel.tradeMode(imp, id)
            tr.chosen = true
          end)
      end
      cy = cy + cardH + gap
    else
      for _, mode in ipairs(MODES) do
        local id = mode.id
        Ui.entryCard(imp, x, cy, w, cardH, "online-trade-mode-" .. id,
          Strings(mode.title), Strings(mode.note), true, function()
            OnlinePanel.tradeMode(imp, id)
            tr.chosen = true
          end)
        cy = cy + cardH + gap
      end
    end
    return cy - y
  end

  if not tr.remote then
    cy = cy + Ui.label(Strings("Trade with"), x, cy) + tiny
    local half = math.floor((w - gap) / 2)
    for i, mode in ipairs(MODES) do
      local id = mode.id
      if Kit.chip(x + (i - 1) * (half + gap), cy, half, rowH,
                  Strings(mode.title), tr.mode == id, PAL.lineStrong,
                  "online-trade-pick-" .. id) then
        LV().queueAction(imp, "online-trade-pick-" .. id, function()
          OnlinePanel.tradeMode(imp, id)
        end)
      end
    end
    cy = cy + rowH + gap
  end

  if tr.mode == "remote" then
    cy = cy + remoteTrade(imp, x, cy, w, m)
  else
    cy = cy + localTrade(imp, x, cy, w, m)
  end
  return cy - y
end

local function modalMon(m, entry, label, x, w, y, box)
  local sprites = Sprites()
  local sprite = entry and entry.mon
    and sprites.get(entry.version, entry.mon) or nil
  if sprite then
    sprites.drawFront(sprite, x + math.floor((w - box) / 2), y, box)
  end
  local cy = y + box + math.floor(4 * m.s)
  Kit.textCenter("micro", label, x, cy, w, PAL.faint)
  cy = cy + Kit.textHeight("micro") + math.floor(2 * m.s)
  Kit.textCenter("small",
    Kit.ellipsize("small", (entry and entry.label) or "?", w),
    x, cy, w, PAL.heading)
  return (cy + Kit.textHeight("small")) - y
end

function TradeScreen.drawModal(imp, m)
  local OnlinePanel = OP()
  local mo = OnlinePanel.tradeModal(imp)
  if not mo then return false end
  local pad = math.floor(18 * m.s)
  local gap = math.floor(8 * m.s)
  local w = math.floor(460 * m.s)
  local innerW = w - 2 * pad
  local btnH = math.max(m.btnH, Kit.tapMin())
  local box = math.floor(56 * m.s)
  local monH = box + math.floor(6 * m.s) + Kit.textHeight("micro")
    + Kit.textHeight("small")
  local result = mo.view == "result"
  local lines = result and (mo.resultLines or {}) or (mo.lines or {})
  local heading = result and (mo.message or "")
    or ((#lines > 0) and Strings("What changes") or nil)
  local linesH = heading and (Kit.textHeight("small") + math.floor(4 * m.s))
    or 0
  for _, line in ipairs(lines) do
    linesH = linesH + Kit.wrapHeight("small", tostring(line), innerW, 2)
      + math.floor(3 * m.s)
  end
  local h = pad + Kit.textHeight("button") + gap + monH + gap + linesH + gap
    + btnH + pad
  local px, py, pw, ph = LV().modalPanel(m, w, h)
  innerW = pw - 2 * pad
  local cy = py + pad
  Kit.textBold("button", Strings("Trade"), px + pad, cy, PAL.heading)
  cy = cy + Kit.textHeight("button") + gap

  local slotW = math.floor((innerW - gap) / 2)
  local left = modalMon(m, mo.give, Strings("Give"), px + pad, slotW, cy, box)
  local right = modalMon(m, mo.get, Strings("Get"),
    px + pad + slotW + gap, slotW, cy, box)
  cy = cy + math.max(left, right) + gap

  if heading then
    Kit.text("small", Kit.ellipsize("small", heading, innerW), px + pad, cy,
      result and (mo.ok and PAL.green or PAL.yellow) or PAL.detail)
    cy = cy + Kit.textHeight("small") + math.floor(4 * m.s)
  end
  for _, line in ipairs(lines) do
    cy = cy + Kit.textWrapped("small", tostring(line), px + pad, cy, innerW,
      PAL.muted, 2) + math.floor(3 * m.s)
  end

  cy = math.floor(py + ph - pad - btnH)
  if result then
    LV().btn(imp, px + pad, cy, innerW, btnH,
      OnlinePanel.TRADE_MODAL_DONE, Strings("Done"),
      { kind = "primary", font = "small",
        action = function() OnlinePanel.tradeModalClose(imp) end })
    return true
  end
  local half = math.floor((innerW - gap) / 2)
  LV().btn(imp, px + pad, cy, half, btnH,
    OnlinePanel.TRADE_MODAL_CANCEL, Strings("Cancel"),
    { kind = "ghost", font = "small",
      action = function() OnlinePanel.tradeModalClose(imp) end })
  LV().btn(imp, px + pad + half + gap, cy, innerW - half - gap, btnH,
    OnlinePanel.TRADE_MODAL_CONFIRM, Strings("Confirm"),
    { kind = "primary", font = "small",
      action = function() OnlinePanel.tradeModalConfirm(imp) end })
  return true
end

return TradeScreen
