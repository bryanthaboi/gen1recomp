local Kit = require("src.ui.kit.Kit")
local Theme = require("src.ui.kit.Theme")
local Strings = require("src.core.Strings")
local Ui = require("src.import.online.Ui")
local Room = require("src.import.online.Room")

local PAL = Theme.PAL

local Tournaments = {}

local function LV() return require("src.import.LauncherView") end
local function OP() return require("src.import.OnlinePanel") end
local function Client() return require("src.online.Client") end

Tournaments.STAGE_TEXT = {
  registering = "Waiting for trainers",
  running = "Bracket in progress",
  finished = "Tournament over",
}

function Tournaments.bracket(imp, x, y, w, m, tour)
  local OnlinePanel = OP()
  local gap = math.floor(6 * m.s)
  local columns = OnlinePanel.bracketColumns(tour)
  local cardH = math.floor(34 * m.s)
  if #columns == 0 then
    Kit.emptyBox(x, y, w, cardH,
      Strings("The bracket is drawn when the tournament starts."))
    return cardH
  end
  local minColW = math.floor(96 * m.s)
  local fit = math.max(1, math.floor((w + gap) / (minColW + gap)))
  local shown = math.min(#columns, fit)
  local first = 1
  if shown < #columns then
    first = math.max(1, math.min(#columns - shown + 1, tonumber(tour.round) or 1))
  end
  local colW = math.floor((w - gap * (shown - 1)) / shown)
  local tallest = 0
  for i = 0, shown - 1 do
    local column = columns[first + i]
    local cx = x + i * (colW + gap)
    local cy = y
    Kit.text("micro", Strings("Round %d", column.round or (first + i)), cx, cy,
      PAL.faint)
    cy = cy + Kit.textHeight("micro") + math.floor(3 * m.s)
    for _, entry in ipairs(column.matches) do
      Kit.card(cx, cy, colW, cardH, entry.live and "badge" or nil)
      if entry.live then
        Theme.stroke(cx, cy, colW, cardH, PAL.green, Theme.A.focus, 2)
      end
      local pad = math.floor(6 * m.s)
      local ink = PAL.text
      if entry.state == "done" then ink = PAL.muted end
      if entry.live then ink = PAL.heading end
      Kit.text("micro",
        Kit.ellipsize("micro", OnlinePanel.matchText(entry), colW - 2 * pad),
        cx + pad, cy + math.floor(4 * m.s), ink)
      local sub
      if entry.bye and not entry.b then
        sub = Strings("bye")
      elseif entry.winnerName then
        sub = entry.how and ("%s  (%s)"):format(entry.winnerName, entry.how)
          or entry.winnerName
      elseif entry.live then
        sub = Strings("live")
      else
        sub = Strings("pending")
      end
      Kit.text("micro", Kit.ellipsize("micro", sub, colW - 2 * pad),
        cx + pad, cy + cardH - Kit.textHeight("micro") - math.floor(4 * m.s),
        entry.live and PAL.green or PAL.faint)
      cy = cy + cardH + math.floor(4 * m.s)
    end
    tallest = math.max(tallest, cy - y)
  end
  return tallest
end

local function lobbyView(imp, x, y, w, m)
  local OnlinePanel = OP()
  local st = OnlinePanel.state(imp)
  local _, gap, tiny = Ui.pads(m)
  local btnH = math.max(m.btnH, Kit.tapMin())
  local online = Client().state() == "online"
  local profile = OnlinePanel.myProfile(imp)
  local version = OnlinePanel.engineVersion(imp)
  local canPlay = online and profile ~= nil
    and OnlinePanel.canBattleWith(version)
  local c = OnlinePanel.cache(imp)
  local rowH = math.max(m.rowH, Kit.tapMin())
  local cy = y

  LV().btn(imp, x, cy, w, btnH, "online-tour-host",
    Strings("Host a tournament"),
    { kind = "primary", font = "small", enabled = online and profile ~= nil,
      action = function()
        OnlinePanel.startWizard(imp, "hostTournament")
      end })
  cy = cy + btnH + gap

  cy = cy + Ui.label(Strings("Join private tournament"), x, cy) + tiny
  local codeW = math.floor(w * 0.5)
  local field = OnlinePanel.TOUR_CODE_FIELD
  local code = st.tourCode or ""
  Ui.field(imp, x, cy, codeW, btnH, field, code,
    Strings("Six characters"), imp._onlineFocus == field,
    function(text) st.tourCode = OnlinePanel.sanitizeCode(text) end)
  local restW = math.floor((w - codeW - 2 * gap) / 2)
  local full = #code == OnlinePanel.CODE_LEN
  LV().btn(imp, x + codeW + gap, cy, restW, btnH, "online-tour-join",
    Strings("Join"),
    { kind = "accent", font = "small", enabled = canPlay and full,
      action = function()
        OnlinePanel.startJoinTournament(imp, { code = st.tourCode })
      end })
  LV().btn(imp, x + codeW + restW + 2 * gap, cy, restW, btnH,
    "online-tour-watch", Strings("Watch"),
    { kind = "ghost", font = "small", enabled = online and full,
      action = function()
        OnlinePanel.joinTournament(imp, { code = st.tourCode }, "spectator")
      end })
  cy = cy + btnH + gap

  local rows = c.tours or {}
  cy = cy + Ui.label(Strings("Open tournaments"), x, cy) + tiny
  if #rows == 0 then
    Kit.emptyBox(x, cy, w, rowH, online
      and Strings("No public tournaments right now.")
      or Strings("Connect to see open tournaments."))
    return (cy + rowH + gap) - y
  end
  local actW = math.floor(64 * m.s)
  for _, row in ipairs(rows) do
    local ink = LV().rowHit(imp, x, cy, w, rowH, false,
      "online-tour-row-" .. row.id, nil)
    local tx = x + math.floor(10 * m.s)
    local textW = w - 2 * actW - math.floor(30 * m.s)
    Kit.text("small", Kit.ellipsize("small", row.name, textW), tx,
      cy + math.floor(5 * m.s), ink or PAL.heading)
    Kit.text("micro", Kit.ellipsize("micro", row.sub, textW), tx,
      cy + rowH - Kit.textHeight("micro") - math.floor(5 * m.s), PAL.muted)
    local tourId, rule = row.tour, row.ruleTable
    LV().btn(imp, x + w - 2 * actW - gap - math.floor(6 * m.s),
      cy + (rowH - btnH) / 2, actW, btnH, "online-tour-join-" .. row.id,
      Strings("Join"),
      { kind = "accent", font = "small",
        enabled = canPlay and row.stage == "waiting" and row.reason == nil,
        action = function()
          OnlinePanel.startJoinTournament(imp, { tour = tourId, name = row.name },
            rule)
        end })
    LV().btn(imp, x + w - actW - math.floor(6 * m.s), cy + (rowH - btnH) / 2,
      actW, btnH, "online-tour-watch-" .. row.id, Strings("Watch"),
      { kind = "ghost", font = "small", enabled = online,
        action = function()
          OnlinePanel.joinTournament(imp, { tour = tourId }, "spectator")
        end })
    cy = cy + rowH + tiny
  end
  return (cy + gap) - y
end

function Tournaments.draw(imp, x, y, w, availH, m)
  local OnlinePanel = OP()
  local st = OnlinePanel.state(imp)
  local client = Client()
  local tour = client.tournament()
  local _, gap, tiny = Ui.pads(m)
  local rowH = math.max(m.rowH, Kit.tapMin())
  local btnH = math.max(m.btnH, Kit.tapMin())

  if not tour then
    local cy = y + Ui.header(imp, x, y, w, m, Strings("Tournaments"))
    cy = cy + lobbyView(imp, x, cy, w, m)
    cy = cy + Ui.statusLine(imp, x, cy, w, m)
    return cy - y
  end

  local me = OnlinePanel.mySeatId()
  local controls = OnlinePanel.creatorControls(tour, me)
  local stage = tostring(tour.stage or "registering")
  local cy = y + Ui.header(imp, x, y, w, m, Strings("Tournament"),
    Strings(Tournaments.STAGE_TEXT[stage] or stage), PAL.lineStrong)

  local format = OnlinePanel.formatText(tour.profile)
  if format then
    cy = cy + Kit.textWrapped("small", Strings("%s  -  %s", format,
      OnlinePanel.ruleText(tour.rule or (tour.profile and tour.profile.rule))),
      x, cy, w, PAL.muted, 1) + tiny
  end
  local banner = OnlinePanel.bannerText(tour, me) or OnlinePanel.tourNotice
  if banner then
    cy = cy + Kit.textWrapped("small", banner, x, cy, w, PAL.green, 2) + tiny
  end
  local left = OnlinePanel.tourDeadline(tour)
  if left then
    cy = cy + Kit.textWrapped("small", Strings("%ds left", left), x, cy, w,
      left <= 10 and PAL.red or PAL.muted, 1) + tiny
  end

  cy = cy + Tournaments.bracket(imp, x, cy, w, m, tour) + gap

  if controls.isCreator and type(tour.code) == "string" and tour.code ~= "" then
    cy = cy + Ui.label(Strings("Private tournament code"), x, cy) + tiny
    cy = cy + Room.codeCard(imp, x, cy, w, m, tour.code, "online-tour",
      "Tournament code copied.")
    cy = cy + Kit.textWrapped("small",
      Strings("Give this code to the trainers you want in."), x, cy, w,
      PAL.muted, 2) + tiny
  end
  cy = cy + Ui.label(Strings("Players (%d) - spectators (%d)",
    #(tour.players or {}), #(tour.spectators or {})), x, cy) + tiny

  for _, player in ipairs(tour.players or {}) do
    local kickW = math.floor(64 * m.s)
    local wide = controls.canKick and player.id ~= me and st.hostMore
    local text = tostring(player.name or "?")
    if player.verified then text = text .. "  *" end
    if player.eliminated then text = text .. Strings("  (out)") end
    if player.online == false then text = text .. Strings("  (away)") end
    Kit.text("small", Kit.ellipsize("small", text,
      w - (wide and kickW or 0) - math.floor(20 * m.s)),
      x + math.floor(10 * m.s), cy,
      player.eliminated and PAL.faint or PAL.text)
    if wide then
      local id = player.id
      LV().btn(imp, x + w - kickW, cy - math.floor(4 * m.s), kickW, btnH,
        "online-tour-kick-" .. tostring(id), Strings("Kick"),
        { kind = "danger", font = "small",
          action = function() pcall(client.kickFromTournament, id) end })
      cy = cy + btnH + tiny
    else
      cy = cy + Kit.textHeight("small") + tiny
    end
  end
  cy = cy + gap

  local third = math.floor((w - 2 * gap) / 3)
  LV().btn(imp, x, cy, third, btnH, "online-tour-start", Strings("Start"),
    { kind = "primary", font = "small", enabled = controls.canStart,
      action = function() pcall(client.startTournament) end })
  LV().btn(imp, x + third + gap, cy, third, btnH, "online-tour-more",
    st.hostMore and Strings("Hide host") or Strings("Host controls"),
    { kind = "ghost", font = "small", enabled = controls.isCreator,
      action = function() st.hostMore = not st.hostMore end })
  LV().btn(imp, x + 2 * (third + gap), cy, third, btnH, "online-tour-leave",
    Strings("Leave"),
    { kind = "danger", font = "small",
      action = function()
        OnlinePanel.leaveTournament(imp)
        OnlinePanel.go(imp, "play")
      end })
  cy = cy + btnH + tiny
  if st.hostMore and controls.canClose then
    LV().btn(imp, x, cy, w, btnH, "online-tour-close",
      Strings("Close the tournament"),
      { kind = "danger", font = "small",
        action = function() pcall(client.closeTournament) end })
    cy = cy + btnH + tiny
  end
  cy = cy + Ui.statusLine(imp, x, cy, w, m)
  return cy - y
end

return Tournaments
