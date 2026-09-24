local Kit = require("src.ui.kit.Kit")
local Theme = require("src.ui.kit.Theme")
local Strings = require("src.core.Strings")
local Ui = require("src.import.online.Ui")

local PAL = Theme.PAL

local Home = {}

local function LV() return require("src.import.LauncherView") end
local function OP() return require("src.import.OnlinePanel") end
local function Client() return require("src.online.Client") end

local STATE_TEXT = {
  online = "Connected to the lobby.",
  connecting = "Connecting...",
  reconnecting = "Reconnecting...",
  ticket = "Signing in...",
}

function Home.identity(imp, x, y, w, m)
  local OnlinePanel = OP()
  local st = OnlinePanel.state(imp)
  local client = Client()
  local pad, gap = Ui.pads(m)
  local rowH = math.max(m.btnH, Kit.tapMin())
  local Connect = require("src.online.Connect")
  local state = Connect.state()
  local you = client.you()
  local verified = type(you) == "table" and you.verified == true
  local offline = state == "offline" or state == "error"
  local upgrade = Connect.upgradeText()
  local statusLine = upgrade or st.status
  if not statusLine then
    if state == "error" then
      statusLine = tostring(Connect.error() or "Disconnected.")
    else
      statusLine = Strings(STATE_TEXT[state]
        or "Offline. Connect to see who is playing.")
    end
  end
  local statusH = Kit.wrapHeight("small", statusLine, w - 2 * pad, 2)
  local stacked = not m.twoCol
  local cardH = pad + Kit.textHeight("small") + gap + rowH + gap + statusH + pad
  if stacked then cardH = cardH + rowH + gap end

  Kit.card(x, y, w, cardH)
  local cx, cy = x + pad, y + pad
  local inner = w - 2 * pad
  cy = cy + Ui.label(Strings("Display name"), cx, cy) + gap

  local connectLabel = offline and Strings("Connect") or Strings("Disconnect")
  local connectW = math.min(math.floor(inner * (stacked and 0.5 or 0.4)),
    Kit.textWidth("small", connectLabel) + math.floor(36 * m.s))
  local pillW = math.floor(64 * m.s)
  local badgeW = verified and (Kit.textWidth("micro", "VERIFIED")
    + math.floor(18 * m.s)) or 0
  local fieldW = stacked and inner
    or math.max(math.floor(60 * m.s),
      inner - connectW - badgeW - pillW - 3 * gap)

  local editing = imp._onlineFocus == "online-name"
  local shown = editing and (st.nameDraft or "") or OnlinePanel.ensureName(imp)
  Ui.field(imp, cx, cy, fieldW, rowH, "online-name", shown,
    Strings("Display name"), editing, function(text)
      OnlinePanel.setName(imp, text)
    end)
  if stacked then cy = cy + rowH + gap end
  local px = stacked and cx or (cx + fieldW + gap)
  local badgeY = cy + math.floor((rowH - 18 * m.s) / 2)
  if verified then
    Kit.tag(px, badgeY, badgeW, math.floor(18 * m.s), "VERIFIED", PAL.green,
      { fill = true, bold = true })
    px = px + badgeW + gap
  end
  Kit.tag(px, badgeY, pillW, math.floor(18 * m.s),
    offline and "OFFLINE" or "ONLINE", offline and PAL.line or PAL.green)
  LV().btn(imp, x + w - pad - connectW, cy, connectW, rowH, "online-connect",
    connectLabel, {
      kind = offline and "primary" or "ghost", font = "small",
      enabled = state ~= "ticket" and upgrade == nil,
      action = function()
        if offline then
          OnlinePanel.connect(imp)
        else
          OnlinePanel.disconnect(imp)
        end
      end })
  cy = cy + rowH + gap
  Kit.textWrapped("small", statusLine, cx, cy, inner,
    upgrade and PAL.red or (st.statusOk and PAL.green
      or (state == "error" and PAL.red or PAL.muted)), 2)
  return cardH
end

local CARDS = {
  { id = "play", title = "Play",
    note = "Find an open lobby or host your own battle." },
  { id = "watch", title = "Watch",
    note = "Open matches and running tournaments to spectate." },
  { id = "trade", title = "Trade",
    note = "Swap POKéMON with another save or another trainer." },
}

function Home.countsText(players, lobbies)
  players, lobbies = tonumber(players) or 0, tonumber(lobbies) or 0
  return (players == 1 and Strings("1 player online")
      or Strings("%d players online", players)) .. ", "
    .. (lobbies == 1 and Strings("1 open lobby")
      or Strings("%d open lobbies", lobbies))
end

function Home.draw(imp, x, y, w, availH, m)
  local OnlinePanel = OP()
  local c = OnlinePanel.cache(imp)
  local pad, gap = Ui.pads(m)
  local online = Client().state() == "online"
  local cy = y + Home.identity(imp, x, y, w, m) + gap

  if online then
    Kit.text("small", Home.countsText(c.counts.players, c.counts.lobbies),
      x, cy, PAL.heading)
  else
    Kit.text("small", Strings("Connect to see who is playing."), x, cy,
      PAL.muted)
  end
  cy = cy + Kit.textHeight("small") + gap

  local cardH = math.max(math.floor(74 * m.s), m.rowH * 2)
  if m.twoCol then
    local colW = math.floor((w - 2 * gap) / 3)
    for i, card in ipairs(CARDS) do
      local cx = x + (i - 1) * (colW + gap)
      Ui.entryCard(imp, cx, cy, colW, cardH, "online-go-" .. card.id,
        Strings(card.title), Strings(card.note),
        online or card.id == "trade",
        function() OnlinePanel.go(imp, card.id) end)
    end
    cy = cy + cardH
  else
    for _, card in ipairs(CARDS) do
      Ui.entryCard(imp, x, cy, w, cardH, "online-go-" .. card.id,
        Strings(card.title), Strings(card.note),
        online or card.id == "trade",
        function() OnlinePanel.go(imp, card.id) end)
      cy = cy + cardH + gap
    end
    cy = cy - gap
  end
  cy = cy + gap
  return (cy - y) + pad
end

return Home
