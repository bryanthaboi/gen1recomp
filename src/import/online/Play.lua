local Kit = require("src.ui.kit.Kit")
local Theme = require("src.ui.kit.Theme")
local Strings = require("src.core.Strings")
local Ui = require("src.import.online.Ui")

local PAL = Theme.PAL

local Play = {}

local function LV() return require("src.import.LauncherView") end
local function OP() return require("src.import.OnlinePanel") end
local function Client() return require("src.online.Client") end

function Play.yourLobby(imp, x, y, w, m)
  local OnlinePanel = OP()
  local c = OnlinePanel.cache(imp)
  local mine = c.mine
  if not mine then return 0 end
  local _, gap, tiny = Ui.pads(m)
  local rowH = math.max(m.rowH, Kit.tapMin())
  local btnH = math.max(m.btnH, Kit.tapMin())
  local h = rowH + btnH + tiny + math.floor(16 * m.s)
  Kit.card(x, y, w, h)
  local tx = x + math.floor(12 * m.s)
  local cy = y + math.floor(8 * m.s)
  Kit.textBold("small", Strings("Your lobby"), tx, cy, PAL.heading)
  if mine.locked then
    local tagH = math.floor(16 * m.s)
    local label = Strings("PRIVATE")
    Ui.lockTag(x + w - math.floor(12 * m.s) - Ui.lockTagWidth(tagH, label), cy,
      tagH, label)
  end
  cy = cy + Kit.textHeight("small") + tiny
  Kit.text("micro", Kit.ellipsize("micro",
    (mine.players or 0) < (mine.seats or 2)
      and Strings("Waiting for an opponent")
      or Strings("%d of %d trainers here", mine.players or 0, mine.seats or 2),
    w - math.floor(24 * m.s)), tx, cy, PAL.muted)
  cy = cy + Kit.textHeight("micro") + tiny
  local half = math.floor((w - math.floor(24 * m.s) - gap) / 2)
  LV().btn(imp, tx, cy, half, btnH, "online-mine-return", Strings("Return"),
    { kind = "primary", font = "small",
      action = function() OnlinePanel.go(imp, "room") end })
  LV().btn(imp, tx + half + gap, cy, half, btnH, "online-mine-close",
    Strings("Close"),
    { kind = "danger", font = "small",
      action = function()
        pcall(Client().closeRoom)
        OnlinePanel.invalidate(imp, "lobby")
      end })
  return h + gap
end

function Play.filters(imp, x, y, w, m)
  local OnlinePanel = OP()
  local _, gap, tiny = Ui.pads(m)
  local h = math.max(math.floor(26 * m.s), Kit.tapMin())
  local cy = y + Ui.label(Strings(OnlinePanel.FILTER_LABEL), x, y) + tiny
  local current = OnlinePanel.filter(imp)
  local n = #OnlinePanel.FILTERS
  local chipW = math.floor((w - gap * (n - 1)) / n)
  for i, filter in ipairs(OnlinePanel.FILTERS) do
    local id = filter.id
    if Kit.chip(x + (i - 1) * (chipW + gap), cy, chipW, h,
                Strings(filter.label), current == id, PAL.lineStrong,
                "online-filter-" .. id) then
      LV().queueAction(imp, "online-filter-" .. id, function()
        OnlinePanel.setFilter(imp, id)
      end)
    end
  end
  return (cy - y) + h + tiny
end

function Play.roomList(imp, x, y, w, availH, m, rows, idPrefix, action, label)
  local _, gap, tiny = Ui.pads(m)
  local rowH = math.max(m.rowH, Kit.tapMin())
  local btnH = math.max(m.btnH, Kit.tapMin())
  local online = Client().state() == "online"
  local cy = y
  if #rows == 0 then
    Kit.emptyBox(x, cy, w, rowH * 2, online
      and Strings("No open lobbies right now. Host one and it shows up here.")
      or Strings("Connect to see who is playing."))
    return (rowH * 2) + gap
  end
  imp._pages = imp._pages or {}
  local pageKey = idPrefix
  local perPage = Kit.rowsThatFit(math.max(rowH * 2, availH), rowH, tiny, 2, 10)
  local first, last, pageNow = Kit.pageBounds(imp._pages[pageKey] or 1,
    #rows, perPage)
  imp._pages[pageKey] = pageNow
  local joinW = math.floor(84 * m.s)
  for i = first, last do
    local row = rows[i]
    local ink = LV().rowHit(imp, x, cy, w, rowH, false,
      idPrefix .. "-" .. row.id, nil)
    local tx = x + math.floor(10 * m.s)
    local textW = w - joinW - math.floor(24 * m.s)
    local nameX = tx
    if row.locked then
      local size = math.floor(14 * m.s)
      Ui.lock(tx, cy + math.floor(5 * m.s)
        + (Kit.textHeight("small") - size) / 2, size,
        row.reason and PAL.faint or PAL.yellow)
      nameX = tx + size + math.floor(6 * m.s)
    end
    local nameW = textW - (nameX - tx)
    Kit.text("small", Kit.ellipsize("small", row.name, nameW), nameX,
      cy + math.floor(5 * m.s),
      row.reason and PAL.faint or (ink or PAL.heading))
    if row.verified then
      local bw = math.floor(16 * m.s)
      Kit.tag(nameX + Kit.textWidth("small", row.name) + math.floor(6 * m.s),
        cy + math.floor(5 * m.s), bw, math.floor(14 * m.s), "*", PAL.green)
    end
    local sub = row.reason and Strings("Can't join: %s", row.reason)
      or (row.intent == "trade" and ("%s  %s"):format(row.game, row.arena))
      or ("%s  %s  %s  %s"):format(row.game, row.arena, row.rule,
        Strings("%d watching", row.spectators))
    if not row.reason and row.where then sub = row.where .. "  " .. sub end
    if not row.reason and row.seatsText then sub = sub .. "  " .. row.seatsText end
    if not row.reason and row.note then sub = sub .. "  " .. row.note end
    Kit.text("micro", Kit.ellipsize("micro", sub, textW), tx,
      cy + rowH - Kit.textHeight("micro") - math.floor(5 * m.s),
      row.reason and PAL.yellow or PAL.muted)
    if row.reason == nil then
      local rule = row.ruleTable
      LV().btn(imp, x + w - joinW - math.floor(6 * m.s),
        cy + (rowH - btnH) / 2, joinW, btnH, idPrefix .. "-go-" .. row.id,
        Strings(label),
        { kind = "accent", font = "small", enabled = online,
          icon = row.locked and "lock" or nil,
          action = function() action(row, rule) end })
    end
    cy = cy + rowH + tiny
  end
  if #rows > perPage then
    local page, ph = Kit.pager(x, cy, w, pageNow, #rows, perPage, pageKey)
    imp._pages[pageKey] = page
    cy = cy + ph
  end
  return (cy - y) + gap
end

Play.LISTS = {
  { id = "rooms", label = "Open lobbies" },
  { id = "players", label = "Trainers" },
}

function Play.listChips(imp, x, y, w, m)
  local OnlinePanel = OP()
  local st = OnlinePanel.state(imp)
  local _, gap, tiny = Ui.pads(m)
  local h = math.max(math.floor(26 * m.s), Kit.tapMin())
  local cy = y + Ui.label(Strings("List:"), x, y) + tiny
  local n = #Play.LISTS
  local chipW = math.floor((w - gap * (n - 1)) / n)
  local current = st.list == "players" and "players" or "rooms"
  for i, list in ipairs(Play.LISTS) do
    local id = list.id
    local key = "online-list-" .. id
    if Kit.chip(x + (i - 1) * (chipW + gap), cy, chipW, h,
                Strings(list.label), current == id, PAL.lineStrong, key) then
      LV().queueAction(imp, key, function()
        st.list = id
        OnlinePanel.invalidate(imp, "lobby")
      end)
    end
  end
  return (cy - y) + h + gap
end

function Play.playerList(imp, x, y, w, availH, m, rows)
  local OnlinePanel = OP()
  local _, gap, tiny = Ui.pads(m)
  local rowH = math.max(m.rowH, Kit.tapMin())
  local btnH = math.max(m.btnH, Kit.tapMin())
  local online = Client().state() == "online"
  local cy = y
  if #rows == 0 then
    Kit.emptyBox(x, cy, w, rowH * 2, online
      and Strings("Nobody else is online right now.")
      or Strings("Connect to see who is playing."))
    return (rowH * 2) + gap
  end
  imp._pages = imp._pages or {}
  local pageKey = "online-players"
  local perPage = Kit.rowsThatFit(math.max(rowH * 2, availH), rowH, tiny, 2, 10)
  local first, last, pageNow = Kit.pageBounds(imp._pages[pageKey] or 1,
    #rows, perPage)
  imp._pages[pageKey] = pageNow
  local actW = math.floor(96 * m.s)
  for i = first, last do
    local row = rows[i]
    local ink = LV().rowHit(imp, x, cy, w, rowH, false,
      "online-player-" .. row.id, nil)
    local tx = x + math.floor(10 * m.s)
    local textW = w - actW - math.floor(24 * m.s)
    Kit.text("small", Kit.ellipsize("small", row.name, textW), tx,
      cy + math.floor(5 * m.s), row.reason and PAL.faint or (ink or PAL.heading))
    if row.verified then
      local bw = math.floor(16 * m.s)
      Kit.tag(tx + Kit.textWidth("small", row.name) + math.floor(6 * m.s),
        cy + math.floor(5 * m.s), bw, math.floor(14 * m.s), "*", PAL.green)
    end
    local parts = { row.game }
    if row.where ~= "" then parts[#parts + 1] = row.where end
    if row.reason then parts[#parts + 1] = row.reason end
    Kit.text("micro", Kit.ellipsize("micro", table.concat(parts, "  "), textW), tx,
      cy + rowH - Kit.textHeight("micro") - math.floor(5 * m.s),
      row.reason and PAL.faint or PAL.muted)
    local player = row
    LV().btn(imp, x + w - actW - math.floor(6 * m.s), cy + (rowH - btnH) / 2,
      actW, btnH, "online-invite-" .. row.id, Strings("Invite"),
      { kind = "accent", font = "small", icon = "mail",
        enabled = online and row.reason == nil,
        action = function() OnlinePanel.invitePickerOpen(imp, player) end })
    cy = cy + rowH + tiny
  end
  if #rows > perPage then
    local page, ph = Kit.pager(x, cy, w, pageNow, #rows, perPage, pageKey)
    imp._pages[pageKey] = page
    cy = cy + ph
  end
  return (cy - y) + gap
end

function Play.draw(imp, x, y, w, availH, m)
  local OnlinePanel = OP()
  local st = OnlinePanel.state(imp)
  local c = OnlinePanel.cache(imp)
  local client = Client()
  local _, gap, tiny = Ui.pads(m)
  local btnH = math.max(m.btnH, Kit.tapMin())
  local online = client.state() == "online"
  local version = OnlinePanel.engineVersion(imp)
  local profile = OnlinePanel.myProfile(imp)
  local canBattle = online and OnlinePanel.canBattleWith(version)

  local cy = y + Ui.header(imp, x, y, w, m, Strings("Play"),
    online and "ONLINE" or "OFFLINE", online and PAL.green or PAL.line)

  cy = cy + Play.yourLobby(imp, x, cy, w, m)

  if version and OnlinePanel.isGen2(version) and not OnlinePanel.gen2Battles() then
    cy = cy + Kit.textWrapped("small",
      Strings("Gen 2 battles come later; you can still browse and trade."),
      x, cy, w, PAL.yellow, 2) + tiny
  end

  LV().btn(imp, x, cy, w, btnH, "online-host", Strings("Host a battle"),
    { kind = "primary", font = "small", enabled = canBattle,
      action = function() OnlinePanel.startWizard(imp, "hostBattle") end })
  cy = cy + btnH + gap

  cy = cy + Play.listChips(imp, x, cy, w, m)
  local showPlayers = st.list == "players"
  local rows = showPlayers and c.players or c.rooms
  if #rows > OnlinePanel.FILTER_AT then
    cy = cy + Play.filters(imp, x, cy, w, m)
  end

  if showPlayers then
    cy = cy + Play.playerList(imp, x, cy, w,
      math.max(m.rowH * 2, availH - (cy - y) - btnH * 2), m, rows)
  else
    cy = cy + Play.roomList(imp, x, cy, w,
      math.max(m.rowH * 2, availH - (cy - y) - btnH * 2), m, rows,
      "online-entry", function(row)
        OnlinePanel.startJoin(imp, OnlinePanel.targetFor(row, "player"))
      end, "Join")
  end

  LV().btn(imp, x, cy, w, btnH, "online-tour-open",
    Strings("Host a tournament"),
    { kind = "ghost", font = "small", enabled = online and profile ~= nil,
      action = function() OnlinePanel.startWizard(imp, "hostTournament") end })
  cy = cy + btnH + tiny
  cy = cy + Ui.statusLine(imp, x, cy, w, m)
  return cy - y
end

return Play
