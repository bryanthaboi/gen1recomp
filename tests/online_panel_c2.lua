package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
love = love or require("tests.love_stub")

local OnlinePanel = require("src.import.OnlinePanel")
local Kit = require("src.ui.kit.Kit")
local Layout = require("src.ui.kit.Layout")
local TeamPick = require("src.online.TeamPick")
local FakeRelay = require("tests.support.fake_relay")

package.loaded["src.online.Client"] = nil
local Client = require("src.online.Client")

local function patch(tbl, fields)
  local keys, saved = {}, {}
  for k, v in pairs(fields) do
    keys[#keys + 1] = k
    saved[k] = tbl[k]
    tbl[k] = v
  end
  return function()
    for _, k in ipairs(keys) do tbl[k] = saved[k] end
  end
end

local function copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

local FR = { engine = 3, version = "firered", engineVersion = "1.0.0", apiVersion = 4,
  fingerprint = "g3fp", rulesetId = "g3_single", kind = "vanilla",
  rule = { partySize = 3 } }

local function profileWith(version, ruleset, size)
  local p = copy(FR)
  p.version = version
  p.rulesetId = ruleset
  p.rule = { partySize = size or 3 }
  return p
end

local PARTY = {
  { species = 6, level = 50, moves = { 53 } },
  { species = 9, level = 50, moves = { 57 } },
  { species = 3, level = 50, moves = { 76 } },
  { species = 25, level = 40, moves = { 85 } },
}

local function packedStub(_, team)
  local out = {}
  for _, ref in ipairs(team or {}) do
    local index = type(ref) == "table" and ref.index or ref
    local mon = PARTY[tonumber(index) or 0]
    if mon then out[#out + 1] = { species = mon.species, level = mon.level } end
  end
  return out
end

local function newImp(ready)
  return { ready = ready or { firered = true, leafgreen = true, red = true },
    activeSlot = {}, slots = {}, pulse = 0, _pages = {}, _uiActions = {}, _actAt = {} }
end

local function setUp(imp, teamSize)
  local st = OnlinePanel.state(imp)
  st.version, st.slotId, st.setupDone, st.kind = "firered", "slot1", true, "vanilla"
  st.team = {}
  for i = 1, teamSize or 3 do st.team[i] = { where = "party", index = i } end
  st.profiles["firered|vanilla|-"] = { profile = copy(FR) }
  st.slotRead = { key = "firered|slot1|-",
    data = { generation = 3, party = PARTY, save = { party = PARTY } } }
  return st
end

local function drawWith(fn, width, height)
  Kit.layout(width or 1280, height or 800)
  Kit.beginFrame(-1, -1, false, 0)
  local m = Layout.metrics(1200)
  local ok, res = pcall(fn, m)
  Kit.endFrame()
  if not ok then print(res) end
  return ok, res, m
end

local function screenDraw(imp)
  return drawWith(function(m)
    return OnlinePanel.buildOnlinePanel(imp, m.contentX, m.top + 100,
      m.contentW, math.max(200, m.h - 200), m)
  end)
end

local function labels(fn)
  Kit.audit = {}
  local ok = fn()
  local out = {}
  for _, row in ipairs(Kit.audit) do
    if row.label then out[#out + 1] = tostring(row.label) end
  end
  Kit.audit = nil
  return ok, table.concat(out, "|")
end


do
  local imp = newImp()
  local st = setUp(imp)
  T.check(OnlinePanel.isGen3(imp), "a FireRed save plays engine 3")
  T.eq(OnlinePanel.ruleset(imp), "g3_single", "a single battle by default")
  T.eq(OnlinePanel.myProfile(imp).rulesetId, "g3_single", "and the profile says so")
  T.check(OnlinePanel.setRuleset(imp, "g3_double"), "a double battle can be picked")
  local double = OnlinePanel.myProfile(imp)
  T.eq(double.rulesetId, "g3_double", "the profile follows the pick")
  T.eq(double.fingerprint, FR.fingerprint, "on the same data")
  T.eq(st.profiles["firered|vanilla|-"].profile.rulesetId, "g3_single",
    "without touching the cached single profile")
  T.eq(OnlinePanel.myProfile(imp), double, "and the variant is reused, not rebuilt")
  T.check(not OnlinePanel.setRuleset(imp, "g3_link"), "the trade ruleset is not a battle")
  T.check(not OnlinePanel.setRuleset(imp, "gen1_faithful"), "nor a Gen 1 one")
  T.eq(OnlinePanel.roomOptions(imp, "battle", double, 8).seats, 2, "a double has 2 seats")

  st.team = { { where = "party", index = 1 } }
  T.eq(OnlinePanel.formatMismatch(imp, "g3_double"),
    "A double battle needs at least 2 POKéMON.", "a double needs two")
  st.team = { { where = "party", index = 1 }, { where = "party", index = 2 },
              { where = "party", index = 3 }, { where = "party", index = 4 } }
  OnlinePanel.setRuleset(imp, "g3_multi")
  T.eq(#st.team, 3, "a multi battle trims the team to three")
  T.eq(OnlinePanel.formatMismatch(imp, "g3_multi"), nil, "which is what it needs")
  T.eq(OnlinePanel.ruleFor(imp).partySize, 3, "the rule is 3 v 3")
  local multi = OnlinePanel.myProfile(imp)
  T.eq(multi.rulesetId, "g3_multi", "the profile is a multi one")
  T.eq(multi.rule.partySize, 3, "with 3 each")
  T.eq(OnlinePanel.roomOptions(imp, "battle", multi, 8).seats, 4, "and 4 seats")
  T.eq(OnlinePanel.teamCap(imp), 3, "the team picker stops at three")
  st.team = { { where = "party", index = 1 } }
  T.check(OnlinePanel.formatMismatch(imp, "g3_multi") ~= nil,
    "one POKeMON is not a multi team")
  T.eq(OnlinePanel.tradeProfile(imp).rulesetId, "g3_link", "trades use the link ruleset")

  local red = newImp({ red = true })
  local rst = OnlinePanel.state(red)
  rst.version = "red"
  rst.profiles["red|vanilla|-"] = { profile = { engine = 1, version = "red",
    kind = "vanilla", fingerprint = "r", rulesetId = "gen1_faithful", rule = {} } }
  T.eq(OnlinePanel.ruleset(red), nil, "Gen 1 has no battle formats")
  T.eq(OnlinePanel.myProfile(red).rulesetId, "gen1_faithful", "its profile is untouched")
  T.eq(OnlinePanel.tradeProfile(red).rulesetId, "gen1_faithful", "trades too")
end


do
  local imp = newImp()
  local st = setUp(imp)
  OnlinePanel.startWizard(imp, "hostBattle")
  local steps = table.concat(OnlinePanel.wizardSteps(imp), ",")
  T.eq(steps, "game,format,save,team,rules,visibility,summary",
    "a Gen 3 host wizard asks which battle")
  OnlinePanel.wizardTo(imp, "format")
  local ok, seen = labels(function() return screenDraw(imp) end)
  T.check(ok, "the format step draws")
  T.check(seen:find("Multi battle", 1, true) ~= nil, "offering the multi battle")
  OnlinePanel.setRuleset(imp, "g3_double")
  local answers = {}
  for _, row in ipairs(OnlinePanel.wizardAnswers(imp)) do answers[row.step] = row.value end
  T.eq(answers.format, "Double battle", "the summary names the battle")
  st.team = { { where = "party", index = 1 } }
  OnlinePanel.wizardTo(imp, "team")
  T.check(not OnlinePanel.wizardReady(imp), "one POKeMON can't go on to a double")
  st.team = { { where = "party", index = 1 }, { where = "party", index = 2 } }
  T.check(OnlinePanel.wizardReady(imp), "two can")
  OnlinePanel.setRuleset(imp, "g3_multi")
  OnlinePanel.wizardTo(imp, "rules")
  T.check(screenDraw(imp), "the multi rules step draws a fixed 3 v 3")
  OnlinePanel.home(imp)

  OnlinePanel.startWizard(imp, "hostTournament")
  T.eq(OnlinePanel.ruleset(imp), "g3_single", "a tournament wizard drops a multi pick")
  OnlinePanel.wizardTo(imp, "format")
  ok, seen = labels(function() return screenDraw(imp) end)
  T.check(ok, "the tournament format step draws")
  T.check(seen:find("Multi battle", 1, true) == nil, "without the multi battle")
  OnlinePanel.home(imp)

  local red = newImp({ red = true })
  local rst = OnlinePanel.state(red)
  rst.version = "red"
  OnlinePanel.startWizard(red, "hostBattle")
  T.check(not table.concat(OnlinePanel.wizardSteps(red), ","):find("format", 1, true),
    "Gen 1 skips the format step")
  OnlinePanel.home(red)
end


do
  local imp = newImp()
  local st = setUp(imp)
  local LOBBY = {
    { id = "00000011", name = "LEAF", online = true, where = "union", status = "idle",
      engine = 3, version = "leafgreen", room = "r0000000000000011", open = true,
      intent = "battle", stage = "waiting", spectators = 0, players = 1, seats = 2,
      profile = profileWith("leafgreen", "g3_double", 3) },
    { id = "00000012", name = "GOLD", online = true, where = "direct", status = "idle",
      engine = 3, version = "firered", room = "r0000000000000012", open = true,
      intent = "battle", stage = "waiting", spectators = 0, players = 2, seats = 4,
      profile = profileWith("firered", "g3_multi", 3) },
    { id = "00000013", name = "KRIS", online = true, where = "game", status = "busy",
      engine = 3, version = "firered" },
    { id = "00000014", name = "MAY", online = true, where = "launcher", status = "idle",
      engine = 3, version = "firered", room = "r0000000000000014", open = true,
      intent = "trade", stage = "waiting", spectators = 0, players = 1, seats = 2,
      profile = profileWith("firered", "g3_link", 3) },
    { id = "00000015", name = "BLUE", online = true, where = "launcher", status = "idle",
      engine = 1, version = "red" },
    { id = "00000016", name = "WALLY", online = true, where = "union", status = "idle",
      engine = 3, version = "leafgreen", room = "r0000000000000016", open = false,
      intent = "battle", stage = "battling", spectators = 1, maxSpectators = 8,
      players = 4, seats = 4, profile = profileWith("leafgreen", "g3_multi", 3) },
  }
  local joined, created
  local restore = patch(Client, {
    state = function() return "online" end,
    you = function() return { id = "me", name = "RED" } end,
    lobby = function() return LOBBY end,
    openRooms = function()
      local out = {}
      for _, e in ipairs(LOBBY) do if e.open then out[#out + 1] = e end end
      return out
    end,
    watchable = function()
      local out = {}
      for _, e in ipairs(LOBBY) do if e.stage == "battling" then out[#out + 1] = e end end
      return out
    end,
    counts = function() return { players = 7, openRooms = 3 } end,
    room = function() return nil end,
    tournament = function() return nil end,
    serverTime = function() return 0 end,
    joinRoom = function(room, as, profile, pin)
      joined = { room = room, as = as, profile = profile, pin = pin }
      return { id = room, done = false }
    end,
    createRoom = function(opts) created = opts return { done = false } end,
    setProfiles = function(list) return list end,
  })
  st.filter = "gen3"
  OnlinePanel.invalidate(imp, "lobby")
  local c = OnlinePanel.refresh(imp)
  T.eq(#c.rooms, 3, "the Gen 3 filter keeps the three open Gen 3 lobbies")
  local byId = {}
  for _, row in ipairs(c.rooms) do byId[row.id] = row end
  local leaf = byId["00000011"]
  T.eq(leaf.game, "LeafGreen", "a LeafGreen row says LeafGreen")
  T.eq(leaf.where, "Union Room", "and where the trainer is")
  T.eq(leaf.arena, "Double battle", "and which battle")
  T.eq(leaf.reason, nil, "a single-battle launcher can still join a double")
  local multi = byId["00000012"]
  T.eq(multi.where, "Direct Corner", "a Direct Corner host reads so")
  T.eq(multi.seatsText, "2/4 trainers", "a multi row counts its four seats")
  T.eq(byId["00000014"].arena, "Trade", "a Gen 3 trade row says Trade")
  local players = {}
  for _, row in ipairs(c.players) do players[row.name] = row end
  T.eq(players.KRIS.reason, "playing", "a trainer out in the field can't be invited")
  T.eq(players.LEAF.reason, nil, "one in the Union Room can")
  T.eq(players.LEAF.where, "Union Room", "and the row says where")
  T.eq(players.BLUE, nil, "the Gen 3 filter hides a Red trainer")
  T.eq(#c.watch, 1, "the running multi battle is watchable")
  T.eq(c.watch[1].seatsText, "4/4 trainers", "with its four trainers")

  st.list = "rooms"
  OnlinePanel.go(imp, "play")
  local ok, seen = labels(function() return screenDraw(imp) end)
  T.check(ok, "Play draws the Gen 3 lobbies")
  T.check(seen:find("Join", 1, true) ~= nil, "with Join buttons")
  OnlinePanel.go(imp, "watch")
  T.check(screenDraw(imp), "Watch draws the multi battle")

  local restorePack = patch(TeamPick, { pack = packedStub })
  st.team = { { where = "party", index = 1 }, { where = "party", index = 2 },
              { where = "party", index = 3 } }
  OnlinePanel.startJoin(imp, OnlinePanel.targetFor(leaf, "player"))
  T.eq(OnlinePanel.ruleset(imp), "g3_double", "joining a double switches the battle")
  T.eq(OnlinePanel.wizardStep(imp), "summary", "a ready team goes straight to the summary")
  OnlinePanel.wizardFinish(imp)
  T.eq(OnlinePanel.screen(imp), "room", "and joins")
  T.eq(joined and joined.profile.rulesetId, "g3_double", "sending a double profile")
  T.eq(joined and joined.room, "r0000000000000011", "for that room")

  joined = nil
  OnlinePanel.home(imp)
  st.team = { { where = "party", index = 1 } }
  OnlinePanel.startJoin(imp, OnlinePanel.targetFor(multi, "player"))
  T.eq(OnlinePanel.ruleset(imp), "g3_multi", "a multi lobby switches to multi")
  T.eq(OnlinePanel.screen(imp), "wizard", "one POKeMON sends the joiner to the team step")
  T.eq(OnlinePanel.teamCap(imp), 3, "which asks for three")
  st.team = { { where = "party", index = 1 }, { where = "party", index = 2 },
              { where = "party", index = 3 } }
  OnlinePanel.joinFromWizard(imp)
  T.eq(joined and joined.profile.rulesetId, "g3_multi", "the join carries a multi profile")

  joined = nil
  OnlinePanel.home(imp)
  OnlinePanel.spectate(imp, c.watch[1])
  T.eq(joined and joined.as, "spectator", "Watch joins as a spectator")
  T.eq(joined and joined.profile.rulesetId, "g3_multi", "with the room's ruleset")

  OnlinePanel.home(imp)
  OnlinePanel.setRuleset(imp, "g3_single")
  T.eq(OnlinePanel.remoteTradeRefusal(imp), nil, "FireRed can trade over the internet")
  T.check(OnlinePanel.hostTrade(imp), "a FireRed trade is hosted")
  T.eq(created and created.intent, "trade", "as a trade room")
  T.eq(created and created.profile.rulesetId, "g3_link", "on the link ruleset")
  T.eq(created and created.seats, 2, "with two seats")
  joined = nil
  OnlinePanel.tradeState(imp).target = { room = "r0000000000000014", name = "MAY" }
  OnlinePanel.joinTrade(imp)
  T.eq(joined and joined.profile.rulesetId, "g3_link", "joining a Gen 3 trade uses it too")
  T.eq(OnlinePanel.autoReadyTrade(imp, { intent = "trade", engine = 3, stage = "waiting",
    players = { { id = "me" }, { id = "x" } } }), false,
    "a Gen 3 trade room never sends room_ready")
  restorePack()
  restore()
end


do
  local imp = newImp()
  local st = setUp(imp)
  local restorePack = patch(TeamPick, { pack = packedStub })
  local reports = 0
  local session = { send = function() end, poll = function() return {} end,
    close = function() end }
  local restore = patch(Client, {
    roomSession = function() return session end,
    report = function() reports = reports + 1 end,
    role = function() return "host" end,
  })
  local payload = { room = "r0000000000000001", match = "r0000000000000001-m1",
    role = "host", seat = 0, seats = 2, engine = 3, seed = 77,
    profile = profileWith("firered", "g3_double", 3),
    players = { { id = "me", name = "RED", seat = 0 }, { id = "b", name = "LEAF", seat = 1 } } }
  local spec, why = OnlinePanel.buildSpec(imp, payload)
  T.check(spec ~= nil, "a Gen 3 battle builds an arena spec: " .. tostring(why))
  if spec then
    T.eq(spec.mode, "double", "for a double battle")
    T.eq(spec.seat, 0, "on seat 0")
    T.eq(spec.seats, 2, "of two")
    T.eq(#spec.myParty, 3, "with the picked party packed")
    T.eq(type(spec.myParty[1].species), "number", "as Gen 3 mons")
    T.eq(spec.slotId, "slot1", "from the picked save")
    T.eq(#spec.players, 2, "naming both trainers")
    spec.onDone("win")
    T.eq(OnlinePanel.lastResult, "win", "the result shows in the launcher")
    T.eq(reports, 0, "but the arena reports it, not the launcher")
  end

  local multi = { room = "r0000000000000002", match = "m", role = "seat2", seat = 2,
    seats = 4, engine = 3, seed = 5, profile = profileWith("firered", "g3_multi", 3),
    players = { { id = "a", seat = 0 }, { id = "b", seat = 1 }, { id = "me", seat = 2 },
                { id = "d", seat = 3 } } }
  st.team = { { where = "party", index = 1 }, { where = "party", index = 2 },
              { where = "party", index = 3 }, { where = "party", index = 4 } }
  spec, why = OnlinePanel.buildSpec(imp, multi)
  T.check(spec ~= nil, "a multi seat builds a spec: " .. tostring(why))
  if spec then
    T.eq(spec.mode, "multi", "for a multi battle")
    T.eq(spec.seat, 2, "on seat 2")
    T.eq(spec.seats, 4, "of four")
    T.eq(#spec.myParty, 3, "sending only three, as the rule says")
  end

  local watch = { room = "r0000000000000003", match = "m", role = "spectator", seats = 4,
    engine = 3, seed = 9, profile = profileWith("leafgreen", "g3_multi", 3), players = {} }
  st.slotId = nil
  spec, why = OnlinePanel.buildSpec(imp, watch)
  T.check(spec ~= nil, "a spectator spec needs no save: " .. tostring(why))
  if spec then
    T.eq(spec.seat, nil, "and has no seat")
    T.eq(spec.myParty, nil, "and sends no party")
  end
  st.slotId = "slot1"

  local played
  imp.playArena = function(_, version, cartId, s)
    played = { version = version, cartId = cartId, spec = s }
    return true
  end
  local restoreRoom = patch(Client, {
    room = function() return { room = payload.room, intent = "battle", engine = 3,
      profile = payload.profile, players = payload.players, seats = 2, stage = "battling" } end,
    tournament = function() return nil end,
    state = function() return "online" end,
  })
  st.team = { { where = "party", index = 1 }, { where = "party", index = 2 } }
  OnlinePanel._pendingStart = payload
  OnlinePanel.update(imp, 1 / 60)
  T.check(played ~= nil, "match_start boots the arena")
  T.eq(played and played.version, "firered", "in FireRed")
  T.eq(played and played.cartId, nil, "with no cart")
  T.eq(played and played.spec.mode, "double", "running the double battle")
  restoreRoom()
  imp.playArena = nil
  restore()
  restorePack()
end


do
  local imp = newImp()
  local st = setUp(imp)
  local tr = OnlinePanel.tradeState(imp)
  tr.mode, tr.chosen = "remote", true
  local canceled, closed, left = 0, 0, 0
  local stage = "picking"
  local remote = {
    handle = { path = "save.lua", version = "firered", generation = 3, party = PARTY },
    session = { theirParty = { PARTY[4] }, peerName = "LEAF" },
    lastResult = "partner_canceled",
    stage = function() return stage end,
    update = function() return stage end,
    canPick = function(_, index) return index ~= 2 end,
    cancelPick = function() canceled = canceled + 1 return true end,
    close = function() closed = closed + 1 end,
  }
  tr.remote = remote
  local mine, theirs = OnlinePanel.remoteRows(remote)
  T.eq(#mine, 4, "the Gen 3 party is listed")
  T.eq(mine[2].pickable, false, "a mon the cart refuses can't be picked")
  T.eq(mine[1].pickable, true, "the others can")
  T.eq(#theirs, 1, "the other trainer's party is listed")
  T.eq(OnlinePanel.remoteNote(remote), "The other trainer called off the trade.",
    "a partner cancel back to the menu is said")
  T.eq(OnlinePanel.remoteStageText("commit_wait"), "Saving the trade on both sides",
    "the barrier wait has words")
  local restore = patch(Client, {
    state = function() return "online" end,
    leaveRoom = function() left = left + 1 return true end,
    room = function() return nil end,
    tournament = function() return nil end,
  })
  OnlinePanel.go(imp, "trade")
  T.check(screenDraw(imp), "the Gen 3 remote trade draws")
  T.check(OnlinePanel.remoteCancel(imp), "Cancel while picking")
  T.eq(canceled, 1, "asks the cart's cancel, not a hang-up")
  T.eq(closed, 0, "so the link stays up")

  stage = "cancelled"
  remote.session.error = "digest"
  OnlinePanel.pumpRemoteTrade(imp, 1 / 60)
  T.eq(tr.remote, nil, "a cancelled trade closes")
  T.eq(tr.remoteResult, "The two games disagreed about the trade, so nothing changed.",
    "and says why")

  stage = "committed"
  local saved = 0
  imp.savesChanged = function() saved = saved + 1 end
  remote.commitResult = { true }
  tr.remote, tr.remoteDone = remote, false
  OnlinePanel.pumpRemoteTrade(imp, 1 / 60)
  T.eq(st.status, "Trade complete.", "a committed trade says so")
  T.eq(OnlinePanel.screen(imp), "home", "and goes home")
  T.eq(saved, 1, "refreshing the save list")
  restore()
end


do
  local imp = newImp()
  local st = setUp(imp)
  local replies = {}
  local restore = patch(Client, {
    state = function() return "online" end,
    serverTime = function() return 1000 end,
    replyInvite = function(id, ok) replies[#replies + 1] = { id = id, ok = ok } return true end,
    room = function() return nil end,
    tournament = function() return nil end,
    setProfiles = function(list) return list end,
  })
  OnlinePanel.inviteIn(imp, { id = "i1", activity = "chat", expiresAt = 20000,
    from = { id = "u1", name = "LEAF", where = "union",
             avatar = { name = "LEAF", trainerId = 1, gender = 1, version = "leafgreen" } } })
  T.eq(OnlinePanel.toast(imp), nil, "a chat invite never toasts in the launcher")
  T.eq(replies[1] and replies[1].ok, false, "it is declined for the sender")
  T.eq(st.status, "LEAF wanted to chat. Chats happen in the Union Room.", "and explained")

  local player = { id = "u2", name = "LEAF", engine = 3, version = "leafgreen" }
  local acts = table.concat(OnlinePanel.activitiesFor(imp, player), ",")
  T.eq(acts, "battle_single,battle_double,trade", "a Gen 3 trainer gets both battles and a trade")

  OnlinePanel.inviteIn(imp, { id = "i2", activity = "battle_double", expiresAt = 20000,
    detail = {}, from = { id = "u2", name = "LEAF", where = "union" } })
  T.check(OnlinePanel.toast(imp) ~= nil, "a double battle invite toasts")
  st.team = { { where = "party", index = 1 } }
  st.ruleset = nil
  OnlinePanel.toastAction(imp, "accept")
  T.eq(OnlinePanel.ruleset(imp), "g3_double", "accepting switches to a double")
  T.eq(OnlinePanel.screen(imp), "wizard", "a one-mon team goes to the team step first")
  T.check(not OnlinePanel.wizardReady(imp) or OnlinePanel.wizardStep(imp) ~= "team",
    "which won't pass with one POKeMON")
  OnlinePanel.home(imp)

  local red = newImp({ red = true })
  setUp(red)
  OnlinePanel.state(red).version = "red"
  local usable, why = OnlinePanel.inviteUsable(red, { id = "i3", activity = "trade",
    from = { id = "u3", name = "MAY", where = "direct" } })
  T.eq(usable, false, "a launcher with no Gen 3 game can't answer a Gen 3 invite")
  T.eq(why, "MAY plays FireRed or LeafGreen. Import one to answer.", "and says so")
  restore()
end


do
  local imp = newImp()
  local st = setUp(imp)
  local restorePack = patch(TeamPick, { pack = packedStub })
  local joins, created = {}, nil
  local TOURS = {
    { id = "00000021", name = "LEAF", online = true, where = "launcher", engine = 3,
      version = "leafgreen", tour = "t0000000000000021", open = true,
      intent = "tournament", stage = "registering",
      profile = profileWith("leafgreen", "g3_double", 3) },
  }
  local restore = patch(Client, {
    state = function() return "online" end,
    you = function() return { id = "me", name = "RED" } end,
    lobby = function() return TOURS end,
    openRooms = function() return TOURS end,
    watchable = function() return TOURS end,
    counts = function() return { players = 2, openRooms = 1 } end,
    room = function() return nil end,
    tournament = function() return nil end,
    serverTime = function() return 0 end,
    createTournament = function(opts) created = opts return { done = false } end,
    joinTournament = function(opts)
      joins[#joins + 1] = opts
      return { done = false, kind = "tournament" }
    end,
    setProfiles = function(list) return list end,
  })
  st.ruleset = "g3_multi"
  T.check(not OnlinePanel.hostTournament(imp), "a multi battle can't host a tournament")
  T.eq(st.status, "Multi battles can't be played in a tournament.", "and says why")
  OnlinePanel.setRuleset(imp, "g3_double")
  T.check(OnlinePanel.hostTournament(imp), "a double battle can")
  T.eq(created and created.profile.rulesetId, "g3_double", "with a double profile")
  T.eq(created and #created.party, 3, "and the packed team")
  OnlinePanel.home(imp)

  OnlinePanel.setRuleset(imp, "g3_single")
  T.check(OnlinePanel.joinTournament(imp, { tour = "t0000000000000021" }, "player"),
    "a listed double tournament is joined")
  T.eq(joins[1] and joins[1].profile.rulesetId, "g3_double", "with its ruleset")
  T.eq(OnlinePanel.ruleset(imp), "g3_double", "switching the launcher's battle")

  st.ruleset = "g3_multi"
  T.check(OnlinePanel.joinTournament(imp, { code = "TQ2RA3" }, "player"),
    "a private code is joined")
  T.eq(joins[2] and joins[2].profile.rulesetId, "g3_single",
    "a multi pick falls back to a single for a bracket")
  local pending = { tourTarget = { code = "TQ2RA3" }, tourAs = "player",
    tourRuleset = "g3_single", reason = "profile_mismatch", field = "rulesetId",
    error = "x", done = true }
  T.check(OnlinePanel.retryTourRuleset(imp, pending), "a ruleset mismatch retries once")
  T.eq(joins[3] and joins[3].profile.rulesetId, "g3_double", "as a double")
  pending.tourRetried = true
  T.check(not OnlinePanel.retryTourRuleset(imp, pending), "but only once")

  local tour = { tour = "t0000000000000021", stage = "registering", creator = "x",
    profile = profileWith("leafgreen", "g3_double", 3), rule = { partySize = 3 },
    players = { { id = "x", name = "LEAF" } }, spectators = {}, bracket = {} }
  local restoreTour = patch(Client, { tournament = function() return tour end })
  OnlinePanel.go(imp, "tournament")
  local ok, seen = labels(function() return screenDraw(imp) end)
  T.check(ok, "the Gen 3 tournament screen draws")
  restoreTour()
  restore()
  restorePack()
end


local function freshClient(relay, s)
  local saved = package.loaded["src.online.Client"]
  package.loaded["src.online.Client"] = nil
  local C = require("src.online.Client")
  package.loaded["src.online.Client"] = saved
  C.reset()
  C.configure({ relayAddress = "fake:1", connect = function() return s.transport end })
  return C
end

local function launcherClient(relay, s)
  Client.reset()
  Client.configure({ relayAddress = "fake:1", connect = function() return s.transport end })
  OnlinePanel._hooked = nil
  OnlinePanel._events = {}
  OnlinePanel._pendingStart = nil
  return Client
end

local function flow(peers)
  local relay = FakeRelay.new()
  local sL = relay:seat("a0000001", "RED")
  local L = launcherClient(relay, sL)
  local imp = newImp()
  local st = setUp(imp)
  local played
  imp.playArena = function(_, version, cartId, spec)
    played = { version = version, cartId = cartId, spec = spec }
    return true
  end
  local others = {}
  for i, name in ipairs(peers) do
    local s = relay:seat(("b%07d"):format(i), name)
    others[i] = freshClient(relay, s)
  end
  local function step(n)
    for _ = 1, n or 1 do
      relay:pump()
      L.update(0)
      for _, C in ipairs(others) do C.update(0) end
      relay:pump()
      OnlinePanel.update(imp, 1 / 60)
    end
  end
  L.connect({ name = "RED", profiles = { copy(FR) } })
  for i, C in ipairs(others) do
    C.connect({ name = peers[i], profiles = { profileWith("leafgreen", "g3_single", 3) } })
  end
  step(3)
  return { relay = relay, L = L, imp = imp, st = st, peers = others, step = step,
    played = function() return played end }
end

do
  local restorePack = patch(TeamPick, { pack = packedStub })
  local f = flow({ "LEAF" })
  T.eq(f.L.state(), "online", "the launcher is on the fake relay")
  OnlinePanel.setRuleset(f.imp, "g3_double")
  f.st.team = { { where = "party", index = 1 }, { where = "party", index = 2 } }
  T.check(OnlinePanel.hostBattle(f.imp), "the launcher hosts a Gen 3 double battle")
  f.step(3)
  local room = f.L.room()
  T.check(room ~= nil, "the room exists")
  T.eq(room and room.profile.rulesetId, "g3_double", "as a double")
  T.eq(room and room.seats, 2, "with two seats")
  local G = f.peers[1]
  G.joinRoom(room.room, "player", profileWith("leafgreen", "g3_double", 2))
  f.step(4)
  T.eq(G.role(), "guest", "the LeafGreen trainer takes seat 1")
  local played = f.played()
  T.check(played ~= nil, "filling the room boots the launcher's arena")
  T.eq(played and played.spec.mode, "double", "a double battle")
  T.eq(played and played.spec.seat, 0, "on the host seat")
  T.eq(played and played.spec.seed, 424242, "on the relay's seed")
  T.eq(played and played.spec.room, room and room.room, "for that room")
  restorePack()
end

do
  local restorePack = patch(TeamPick, { pack = packedStub })
  local f = flow({ "LEAF", "GOLD", "KRIS" })
  OnlinePanel.setRuleset(f.imp, "g3_multi")
  f.st.team = { { where = "party", index = 1 }, { where = "party", index = 2 },
                { where = "party", index = 3 } }
  T.check(OnlinePanel.hostBattle(f.imp), "the launcher hosts a multi battle")
  f.step(3)
  local room = f.L.room()
  T.eq(room and room.seats, 4, "the multi room has four seats")
  OnlinePanel.go(f.imp, "room")
  local ok, seen = labels(function() return screenDraw(f.imp) end)
  T.check(ok, "the multi room screen draws")
  T.check(seen:find("Ready", 1, true) == nil, "with no Ready button")
  for _, C in ipairs(f.peers) do
    C.joinRoom(room.room, "player", profileWith("leafgreen", "g3_multi", 3))
    f.step(2)
  end
  f.step(3)
  T.eq(f.peers[3].role(), "seat3", "the fourth trainer sits on seat 3")
  local played = f.played()
  T.check(played ~= nil, "the fourth seat starts the multi battle")
  T.eq(played and played.spec.seats, 4, "for four trainers")
  T.eq(played and played.spec.mode, "multi", "as a multi battle")
  T.eq(played and #played.spec.players, 4, "naming all four")
  restorePack()
end

do
  local f = flow({ "LEAF", "GOLD", "KRIS", "MAY" })
  local host = f.peers[1]
  local multi = profileWith("leafgreen", "g3_multi", 3)
  host.createRoom({ intent = "battle", profile = multi, playing = true, maxSpectators = 8,
    private = false, seats = 4, auto = false })
  f.step(3)
  local room = host.room()
  f.st.joinTarget = { room = room.room, engine = 3, rulesetId = "g3_multi", as = "spectator" }
  T.check(OnlinePanel.joinRoom(f.imp, room.room, "spectator"), "the launcher watches a multi")
  f.step(3)
  for i = 2, 4 do
    f.peers[i].joinRoom(room.room, "player", multi)
    f.step(2)
  end
  f.step(3)
  local played = f.played()
  T.check(played ~= nil, "the full multi opens the spectator arena")
  T.eq(played and played.spec.role, "spectator", "as a spectator")
  T.eq(played and played.spec.seats, 4, "of all four seats")
  T.eq(played and played.spec.seat, nil, "without a seat")
end

do
  local restorePack = patch(TeamPick, { pack = packedStub })
  local f = flow({ "LEAF" })
  local U = f.peers[1]
  U.joinPlaza("union", profileWith("leafgreen", "g3_link", 3),
    { name = "LEAF", trainerId = 222, gender = 1, version = "leafgreen" })
  f.step(2)
  local inviteIn
  U.on("invite_in", function(msg) inviteIn = msg end)
  f.st.team = { { where = "party", index = 1 }, { where = "party", index = 2 } }
  T.check(OnlinePanel.startInvite(f.imp, { id = "b0000001", name = "LEAF", engine = 3,
    version = "leafgreen" }, "battle_double"), "the launcher invites a Union Room trainer")
  f.step(3)
  T.check(inviteIn ~= nil, "the in-game trainer hears the invite")
  T.eq(inviteIn and inviteIn.activity, "battle_double", "for a double battle")
  T.eq(inviteIn and inviteIn.detail and inviteIn.detail.ruleset, "g3_double",
    "carrying the ruleset")
  U.replyInvite(inviteIn.id, true)
  f.step(4)
  T.eq(U.role(), "guest", "accepting seats the in-game trainer")
  local played = f.played()
  T.check(played ~= nil, "and the launcher's arena boots")
  T.eq(played and played.spec.mode, "double", "into the double battle")
  restorePack()
end

do
  local restorePack = patch(TeamPick, { pack = packedStub })
  local f = flow({ "LEAF" })
  local U = f.peers[1]
  U.joinPlaza("union", profileWith("leafgreen", "g3_link", 3),
    { name = "LEAF", trainerId = 222, gender = 1, version = "leafgreen" })
  f.step(2)
  local closed
  U.on("invite_closed", function(msg) closed = msg end)
  U.invite("a0000001", "chat", {}, profileWith("leafgreen", "g3_link", 3))
  f.step(4)
  T.eq(closed and closed.why, "declined", "a chat invite to the launcher is turned down")
  T.eq(OnlinePanel.toast(f.imp), nil, "without a toast")

  closed = nil
  f.st.team = { { where = "party", index = 1 } }
  U.invite("a0000001", "battle_single", { ruleset = "g3_single" },
    profileWith("leafgreen", "g3_single", 3))
  f.step(4)
  local toast = OnlinePanel.toast(f.imp)
  T.check(toast ~= nil, "a battle invite from the Union Room toasts in the launcher")
  T.check(toast and OnlinePanel.inviteLine(toast):find("LEAF", 1, true) ~= nil,
    "naming the in-game trainer")
  OnlinePanel.toastAction(f.imp, "accept")
  f.step(5)
  T.eq(f.L.role(), "guest", "accepting seats the launcher")
  local played = f.played()
  T.check(played ~= nil, "and boots the arena")
  T.eq(played and played.spec.seat, 1, "on seat 1")
  T.eq(played and played.spec.mode, "single", "for a single battle")
  restorePack()
end


do
  local OnlineSprites = require("src.online.OnlineSprites")
  local Wizard = require("src.import.online.Wizard")
  local fronts = 0
  local restore = patch(OnlineSprites, {
    get = function() return { key = "firered|6|0", icon = false, front = {} } end,
    drawIcon = function() return false end,
    drawFront = function() fronts = fronts + 1 return true end,
  })
  local imp = { ready = { firered = true }, activeSlot = {}, slots = {},
    pulse = 0, _pages = {}, _uiActions = {}, _actAt = {} }
  Kit.layout(1280, 800)
  Kit.beginFrame(-1, -1, false, 0)
  local m = Layout.metrics(1200)
  Wizard.monRow(imp, { key = "p1", version = "firered", mon = { species = 6 },
    label = "CHARIZARD Lv52" }, 20, 20, 600, m, function() end)
  Kit.endFrame()
  restore()
  T.eq(fronts, 0, "a party row with no icon never falls back to a front pic")
end

local Cache = require("tests.game3_cache")
if not Cache.mount("meta.json") then
  print("[skip] online_panel_c2 trade over the fake relay: " .. tostring(Cache.reason))
  T.finish("online panel c2")
  return
end

do
  local GameVersion = require("src.core.GameVersion")
  GameVersion.set("firered")
  local SaveData = require("src.core.SaveData")
  local Trade = require("src.online.Trade")
  local Pokemon = require("src.core.game3.pokemon")
  local Party = require("src.core.game3.party")
  local Schema = require("src.core.game3.save_schema_firered")
  local RelayTransport = require("src.core.game3.link.relay_transport")
  local Fingerprint = require("src.link.Fingerprint")
  Pokemon.install(nil)

  local files = {}
  local restoreFs = patch(SaveData, { portableFs = function()
    return {
      getInfo = function(name) return files[name] and { type = "file" } or nil end,
      read = function(name) return files[name] end,
      write = function(name, body) files[name] = body return true end,
      remove = function(name) files[name] = nil return true end,
      createDirectory = function() return true end,
    }
  end })

  local cache = require("src.core.game3.dataset").cache()
  local fp = Fingerprint.compute({ generation = 3,
    gen3Inputs = Fingerprint.gen3Inputs(function(rel) return cache:read(rel) end) }, {}, 3)
  local LINK = copy(FR)
  LINK.fingerprint, LINK.rulesetId = fp, "g3_link"

  local function makeSave(version, name, trainerId, mons)
    local session = Schema.newGame({ version = version, name = name, rngSeed = trainerId })
    session.trainerId = trainerId
    session.dex.nationalUnlocked = true
    session.party = {}
    for _, row in ipairs(mons) do assert(Party.giveMon(session, row.species, row.level)) end
    return SaveData.decode(SaveData.encode(Schema.toSaveTable(session)))
  end
  local DATA = { generation = 3, Pokemon = Pokemon, pokemon = Pokemon }
  local function handle(version, slotId, save)
    local path = Trade.slotPath(version, slotId)
    files[path] = SaveData.encode(save)
    return { version = version, generation = 3, slotId = slotId, save = save,
             path = path, party = save.party, data = DATA }
  end
  local hL = handle("firered", "slot1", makeSave("firered", "RED", 11111,
    { { species = 64, level = 30 }, { species = 25, level = 12 } }))
  local hP = handle("leafgreen", "slot2", makeSave("leafgreen", "LEAF", 22222,
    { { species = 95, level = 25 }, { species = 1, level = 8 } }))
  local diskL = files[hL.path]
  local restoreOpen = patch(Trade, { openSlot = function() return hL end })

  local relay = FakeRelay.new()
  local sL = relay:seat("a0000001", "RED")
  local sP = relay:seat("b0000001", "LEAF")
  local L = launcherClient(relay, sL)
  local P = freshClient(relay, sP)
  local imp = newImp()
  local st = setUp(imp)
  st.profiles["firered|vanilla|-"] = { profile = copy(LINK) }
  st.slotRead = nil
  local peer
  local function step(n, until_)
    for _ = 1, n or 1 do
      relay:pump()
      L.update(0)
      P.update(0)
      relay:pump()
      OnlinePanel.update(imp, 1 / 60)
      if peer then peer:update(1 / 60) end
      if until_ and until_() then return true end
    end
    return until_ == nil or until_()
  end
  L.connect({ name = "RED", profiles = { copy(LINK) } })
  P.connect({ name = "LEAF", profiles = { copy(LINK) } })
  step(3)
  T.check(OnlinePanel.hostTrade(imp), "the launcher hosts a FireRed trade")
  step(3)
  local room = L.room()
  T.eq(room and room.profile.rulesetId, "g3_link", "on the link ruleset")
  local link = copy(LINK)
  link.version = "leafgreen"
  P.joinRoom(room.room, "player", link)
  step(3)
  local rsP = P.roomSession()
  peer = Trade.remote(hP, rsP, { transport = RelayTransport.new(rsP, { client = P }) })
  peer:start()
  local tr = OnlinePanel.tradeState(imp)
  T.check(step(300, function()
    return tr.remote and tr.remote:stage() == "picking" and peer:stage() == "picking"
  end), "both sides reach the trade menu: " .. tostring(tr.remote and tr.remote:stage())
    .. "/" .. tostring(peer:stage()))
  T.eq(OnlinePanel.screen(imp), "trade", "the launcher shows the Trade screen")
  local mine, theirs = OnlinePanel.remoteRows(tr.remote)
  T.eq(#theirs, 2, "listing the LeafGreen party")
  T.check(mine[1] and mine[1].pickable, "and the launcher's own POKeMON")
  T.check(screenDraw(imp), "the live Gen 3 trade draws")
  T.check(OnlinePanel.remotePick(imp, 1), "the launcher offers its first POKeMON")
  T.check(peer:pick(1), "the peer offers its first")
  T.check(step(200, function()
    return tr.remote:stage() == "confirming" and peer:stage() == "confirming"
  end), "both are asked to confirm")
  OnlinePanel.remoteConfirm(imp, true)
  peer:confirm(true)
  T.check(step(300, function() return st.status == "Trade complete." end),
    "the relay commit finishes the trade: " .. tostring(st.status) .. " "
      .. tostring(tr.remoteResult))
  T.check(files[hL.path] ~= diskL, "the launcher's save was written after the commit")
  T.eq(peer:stage(), "committed", "the peer committed too")
  restoreOpen()
  restoreFs()
end

T.finish("online panel c2")
