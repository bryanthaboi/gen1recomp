local Kit = require("src.ui.kit.Kit")
local Theme = require("src.ui.kit.Theme")
local Strings = require("src.core.Strings")
local Ui = require("src.import.online.Ui")

local PAL = Theme.PAL

local Watch = {}

local function LV() return require("src.import.LauncherView") end
local function OP() return require("src.import.OnlinePanel") end
local function Client() return require("src.online.Client") end

function Watch.draw(imp, x, y, w, availH, m)
  local OnlinePanel = OP()
  local c = OnlinePanel.cache(imp)
  local _, gap, tiny = Ui.pads(m)
  local rowH = math.max(m.rowH, Kit.tapMin())
  local btnH = math.max(m.btnH, Kit.tapMin())
  local online = Client().state() == "online"

  local cy = y + Ui.header(imp, x, y, w, m, Strings("Watch"),
    online and "ONLINE" or "OFFLINE", online and PAL.green or PAL.line)

  local rows = c.watch
  cy = cy + Ui.label(Strings("Live now"), x, cy) + tiny
  if #rows == 0 then
    Kit.emptyBox(x, cy, w, rowH * 2, online
      and Strings("Nothing to watch yet. Check back soon.")
      or Strings("Connect to see who is playing."))
    cy = cy + rowH * 2 + gap
  else
    imp._pages = imp._pages or {}
    local pageKey = "online-watch"
    local perPage = Kit.rowsThatFit(math.max(rowH * 2,
      availH - (cy - y) - btnH), rowH, tiny, 2, 8)
    local first, last, pageNow = Kit.pageBounds(imp._pages[pageKey] or 1,
      #rows, perPage)
    imp._pages[pageKey] = pageNow
    local watchW = math.floor(88 * m.s)
    for i = first, last do
      local row = rows[i]
      local ink = LV().rowHit(imp, x, cy, w, rowH, false,
        "online-watch-" .. row.id, nil)
      local tx = x + math.floor(10 * m.s)
      local textW = w - watchW - math.floor(24 * m.s)
      local nameX = tx
      if row.locked then
        local size = math.floor(14 * m.s)
        Ui.lock(tx, cy + math.floor(5 * m.s)
          + (Kit.textHeight("small") - size) / 2, size, PAL.yellow)
        nameX = tx + size + math.floor(6 * m.s)
      end
      Kit.text("small", Kit.ellipsize("small", row.name, textW - (nameX - tx)),
        nameX, cy + math.floor(5 * m.s), ink or PAL.heading)
      local tournament = row.intent == "tournament" or row.tour ~= nil
      local sub = ("%s  %s  %s  %s"):format(row.game, row.arena, row.rule,
        tournament and Strings("tournament")
          or Strings("%d watching", row.spectators))
      if row.seatsText then sub = sub .. "  " .. row.seatsText end
      if row.where then sub = row.where .. "  " .. sub end
      Kit.text("micro", Kit.ellipsize("micro", sub, textW), tx,
        cy + rowH - Kit.textHeight("micro") - math.floor(5 * m.s), PAL.muted)
      local pick = row
      LV().btn(imp, x + w - watchW - math.floor(6 * m.s),
        cy + (rowH - btnH) / 2, watchW, btnH, "online-watch-go-" .. row.id,
        tournament and Strings("Watch") or Strings("Spectate"),
        { kind = "accent", font = "small", enabled = online,
          icon = row.locked and "lock" or nil,
          action = function() OnlinePanel.spectate(imp, pick) end })
      cy = cy + rowH + tiny
    end
    if #rows > perPage then
      local page, ph = Kit.pager(x, cy, w, pageNow, #rows, perPage, pageKey)
      imp._pages[pageKey] = page
      cy = cy + ph
    end
    cy = cy + gap
  end

  cy = cy + Ui.statusLine(imp, x, cy, w, m)
  return cy - y
end

return Watch
