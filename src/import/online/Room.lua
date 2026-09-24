local Kit = require("src.ui.kit.Kit")
local Theme = require("src.ui.kit.Theme")
local Strings = require("src.core.Strings")
local Ui = require("src.import.online.Ui")

local PAL = Theme.PAL

local Room = {}

local function LV() return require("src.import.LauncherView") end
local function OP() return require("src.import.OnlinePanel") end
local function Client() return require("src.online.Client") end

Room.TRADE_STAGE_TEXT = {
  waiting = "Waiting for the other trainer",
  ready = "Both trainers are here",
  battling = "Trade in progress",
  ended = "Trade over",
}

Room.STAGE_TEXT = {
  waiting = "Waiting for a challenger",
  ready = "Both trainers are picking a team",
  battling = "Battle in progress",
  ended = "Match over",
}

Room.GEN3_STAGE_TEXT = {
  waiting = "Waiting for trainers",
  ready = "Everyone is here",
  battling = "Battle in progress",
  ended = "Match over",
}

function Room.codeCard(imp, x, y, w, m, code, idPrefix, copied)
  local _, gap = Ui.pads(m)
  local rowH = math.max(m.rowH, Kit.tapMin())
  local btnH = math.max(m.btnH, Kit.tapMin())
  local copyW = math.floor(80 * m.s)
  Kit.card(x, y, w, rowH)
  Kit.text("title", tostring(code or "------"), x + math.floor(12 * m.s),
    y + (rowH - Kit.textHeight("title")) / 2, PAL.heading)
  LV().btn(imp, x + w - copyW - math.floor(8 * m.s), y + (rowH - btnH) / 2,
    copyW, btnH, idPrefix .. "-copy", Strings("Copy"),
    { kind = "ghost", font = "small",
      action = function()
        if love.system and love.system.setClipboardText then
          pcall(love.system.setClipboardText, tostring(code or ""))
        end
        local st = OP().state(imp)
        st.status, st.statusOk = Strings(copied), true
      end })
  return rowH + gap
end

local function seated(players, seat)
  for i = 1, #players do
    local p = players[i]
    if (tonumber(p.seat) or (i - 1)) == seat then return p end
  end
  return nil
end

function Room.playersCard(imp, x, y, w, m, room, trade)
  local OnlinePanel = OP()
  local _, gap, tiny = Ui.pads(m)
  local pad = math.floor(12 * m.s)
  local lineH = math.max(Kit.textHeight("small"), math.floor(18 * m.s))
  local players = room.players or {}
  local seats = tonumber(room.seats) or 2
  local headH = Kit.textHeight("small")
  local h = pad + headH + tiny + seats * (lineH + tiny) + pad - tiny
  Kit.card(x, y, w, h)
  local cx, cy = x + pad, y + pad
  Kit.textBold("small", Strings("Players"), cx, cy, PAL.heading)
  local right = x + w - pad
  local tagH = math.floor(16 * m.s)
  local count = ("%d/%d"):format(#players, seats)
  local countW = Kit.textWidth("micro", count)
  Kit.text("micro", count, right - countW,
    cy + (headH - Kit.textHeight("micro")) / 2, PAL.muted)
  right = right - countW - math.floor(8 * m.s)
  if room.locked then
    local label = Strings("PRIVATE")
    local tw = Ui.lockTagWidth(tagH, label)
    Ui.lockTag(right - tw, cy + (headH - tagH) / 2, tagH, label)
  end
  cy = cy + headH + tiny
  local me = OnlinePanel.mySeatId()
  local tagW = math.floor(74 * m.s)
  for seat = 0, seats - 1 do
    local player = seated(players, seat)
    if seats == 4 then
      local side = seat % 2 == 0 and Strings("TEAM A") or Strings("TEAM B")
      local tagX = right + countW + math.floor(8 * m.s) - tagW
      Kit.tag(tagX, cy + (lineH - math.floor(16 * m.s)) / 2, tagW,
        math.floor(16 * m.s), side, seat % 2 == 0 and PAL.lineStrong or PAL.line)
    end
    if player then
      local text = tostring(player.name or "?")
      if player.verified then text = text .. "  *" end
      if me and player.id == me then text = text .. Strings("  (you)") end
      if player.online == false then text = text .. Strings("  (away)") end
      Kit.text("small", Kit.ellipsize("small", text, w - 2 * pad - tagW),
        cx, cy + (lineH - Kit.textHeight("small")) / 2, PAL.heading)
      if not trade and seats ~= 4 then
        Kit.tag(right + countW + math.floor(8 * m.s) - tagW,
          cy + (lineH - math.floor(16 * m.s)) / 2, tagW, math.floor(16 * m.s),
          player.ready and "READY" or "PICKING",
          player.ready and PAL.green or PAL.line)
      end
    else
      Kit.text("small", Strings("Open seat"), cx,
        cy + (lineH - Kit.textHeight("small")) / 2, PAL.faint)
    end
    cy = cy + lineH + tiny
  end
  return h + gap
end

function Room.stage(room)
  local stage = tostring(room.stage or "waiting")
  if stage == "waiting" or stage == "ready" then
    stage = #(room.players or {}) < (tonumber(room.seats) or 2) and "waiting"
      or "ready"
  end
  return stage
end

function Room.stageText(room)
  local stage = Room.stage(room)
  local trade = tostring(room.intent or "battle") == "trade"
  local gen3 = tonumber(room.engine) == 3
  local text = trade and (Room.TRADE_STAGE_TEXT[stage] or stage)
    or (gen3 and Room.GEN3_STAGE_TEXT[stage]) or (Room.STAGE_TEXT[stage] or stage)
  return Strings(text)
end

function Room.draw(imp, x, y, w, availH, m)
  local OnlinePanel = OP()
  local st = OnlinePanel.state(imp)
  local client = Client()
  local room = client.room()
  local _, gap, tiny = Ui.pads(m)
  local rowH = math.max(m.rowH, Kit.tapMin())
  local btnH = math.max(m.btnH, Kit.tapMin())

  if not room then
    local pending = st.pending
    local line = Strings("You are not in a room.")
    local target = st.joinTarget
    local name = type(target) == "table" and target.name or nil
    if st.joinWant or st.inviteJoin or (pending and not pending.done
        and (pending.id or pending.inviteToken or pending.kind == "join")) then
      line = name and Strings("Joining %s...", tostring(name))
        or Strings("Joining the room...")
    elseif pending and not pending.done then
      line = Strings("Creating the room...")
    end
    local cy = y + Ui.header(imp, x, y, w, m, Strings("Room"))
    Kit.emptyBox(x, cy, w, rowH * 2, line)
    cy = cy + rowH * 2 + tiny
    cy = cy + Ui.statusLine(imp, x, cy, w, m)
    return cy - y
  end

  local stage = Room.stage(room)
  local trade = tostring(room.intent or "battle") == "trade"
  local gen3 = tonumber(room.engine) == 3
  local cy = y + Ui.header(imp, x, y, w, m,
    trade and Strings("Trade room") or Strings("Room"),
    Room.stageText(room), PAL.lineStrong)
  cy = cy + Room.playersCard(imp, x, cy, w, m, room, trade or gen3)
  if room.locked and #(room.players or {}) < (tonumber(room.seats) or 2) then
    cy = cy + Kit.textWrapped("small",
      Strings("Tell the trainer you want the PIN, or invite them from Play."),
      x, cy, w, PAL.muted, 2) + tiny
  end

  if not trade then
    local rule = room.profile and room.profile.rule
    cy = cy + Ui.label(Strings("Rules"), x, cy) + tiny
    cy = cy + Kit.textWrapped("small",
      Strings("%s  -  %s", OnlinePanel.arenaText(room.profile or {}),
        OnlinePanel.ruleText(rule)), x, cy, w, PAL.muted, 1) + tiny
  end

  local deadline = not trade and room.deadlines
    and (room.deadlines.ready or room.deadlines.shot)
  if type(deadline) == "number" then
    local left = OnlinePanel.countdown(deadline, client.serverTime() or 0)
    if left then
      cy = cy + Kit.textWrapped("small", Strings("%ds left", left), x, cy, w,
        left <= 10 and PAL.red or PAL.muted, 1) + tiny
    end
  end

  if OnlinePanel.lastResult then
    cy = cy + Kit.textWrapped("small",
      Strings(OnlinePanel.RESULT_TEXT[OnlinePanel.lastResult]
        or "The match ended."), x, cy, w, PAL.green, 1) + tiny
  end

  local need = st.roomCart
  if need then
    cy = cy + Kit.textWrapped("small",
      Strings("This room plays the %s cart.", tostring(need.id)),
      x, cy, w, PAL.yellow, 2) + tiny
    LV().btn(imp, x, cy, w, btnH, "online-install-cart",
      st.cartInstall and Strings("Installing...") or Strings("Install cart"),
      { kind = "accent", font = "small", enabled = st.cartInstall == nil,
        action = function() OnlinePanel.installCart(imp, need) end })
    cy = cy + btnH + gap
  end

  local me = OnlinePanel.mySeatId()
  local hosting = me ~= nil and room.host == me
  local playing = false
  for _, player in ipairs(room.players or {}) do
    if me and player.id == me then playing = true end
  end

  if playing and not trade and stage ~= "battling"
      and not OnlinePanel.setupComplete(imp) then
    LV().btn(imp, x, cy, w, btnH, "online-room-team", Strings("Pick your team"),
      { kind = "accent", font = "small",
        action = function() OnlinePanel.pickTeamInRoom(imp) end })
    cy = cy + btnH + gap
  end

  if trade then
    cy = cy + Kit.textWrapped("small",
      (#(room.players or {}) < 2)
        and Strings("Waiting for the other trainer.")
        or Strings("Opening the trade..."),
      x, cy, w, PAL.muted, 2) + tiny
    LV().btn(imp, x, cy, w, btnH, "online-leave",
      st.confirmLeave and Strings("Really leave?") or Strings("Leave"),
      { kind = "danger", font = "small",
        action = function()
          if not st.confirmLeave then
            st.confirmLeave = true
            return
          end
          st.confirmLeave, st.ready = nil, false
          client.leaveRoom()
          OnlinePanel.clearPresence()
          OnlinePanel.go(imp, "trade")
        end })
    cy = cy + btnH + tiny
    cy = cy + Ui.statusLine(imp, x, cy, w, m)
    return cy - y
  end

  local spectators = room.spectators or {}
  cy = cy + Ui.label(Strings("Spectators (%d)", #spectators), x, cy) + gap

  local function leave()
    if not st.confirmLeave then
      st.confirmLeave = true
      return
    end
    st.confirmLeave, st.ready = nil, false
    client.leaveRoom()
    OnlinePanel.clearPresence()
    OnlinePanel.go(imp, "play")
  end

  if gen3 then
    if stage == "waiting" or stage == "ready" then
      local open = (tonumber(room.seats) or 2) - #(room.players or {})
      cy = cy + Kit.textWrapped("small", open == 1
        and Strings("The battle starts when the last seat is taken.")
        or Strings("The battle starts when all %d seats are taken.",
          tonumber(room.seats) or 2),
        x, cy, w, PAL.muted, 2) + tiny
    end
    LV().btn(imp, x, cy, w, btnH, "online-leave",
      st.confirmLeave and Strings("Really leave?") or Strings("Leave"),
      { kind = "danger", font = "small", action = leave })
    cy = cy + btnH + tiny
  else
    local rematch = OnlinePanel.lastResult ~= nil and stage ~= "battling"
    local half = math.floor((w - gap) / 2)
    LV().btn(imp, x, cy, half, btnH, "online-ready",
      st.ready and Strings("Unready")
        or (rematch and Strings("Rematch") or Strings("Ready")),
      { kind = st.ready and "ghost" or "primary", font = "small",
        enabled = playing and stage ~= "battling",
        action = function()
          if st.ready then
            OnlinePanel.unready(imp)
          else
            OnlinePanel.sendReady(imp)
          end
        end })
    LV().btn(imp, x + half + gap, cy, half, btnH, "online-leave",
      st.confirmLeave and Strings("Really leave?") or Strings("Leave"),
      { kind = "danger", font = "small", action = leave })
    cy = cy + btnH + tiny
  end

  if hosting then
    LV().btn(imp, x, cy, w, btnH, "online-host-more",
      st.hostMore and Strings("Hide host controls")
        or Strings("Host controls"),
      { kind = "ghost", font = "small",
        action = function() st.hostMore = not st.hostMore end })
    cy = cy + btnH + tiny
    if st.hostMore then
      for _, watcher in ipairs(spectators) do
        local kickW = math.floor(64 * m.s)
        Kit.text("small", Kit.ellipsize("small",
          tostring(watcher.name or "?"), w - kickW), x + math.floor(10 * m.s),
          cy + math.floor(4 * m.s), PAL.muted)
        local id = watcher.id
        LV().btn(imp, x + w - kickW, cy, kickW, btnH,
          "online-kick-" .. tostring(id), Strings("Kick"),
          { kind = "danger", font = "small",
            action = function()
              if type(client.kick) == "function" then pcall(client.kick, id) end
            end })
        cy = cy + btnH + tiny
      end
      LV().btn(imp, x, cy, w, btnH, "online-close-room",
        Strings("Close the room"),
        { kind = "danger", font = "small",
          action = function()
            pcall(client.closeRoom)
            OnlinePanel.go(imp, "play")
          end })
      cy = cy + btnH + tiny
    end
  end
  cy = cy + Ui.statusLine(imp, x, cy, w, m)
  return cy - y
end

return Room
