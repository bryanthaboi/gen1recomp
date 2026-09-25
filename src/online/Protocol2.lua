local Strings = require("src.core.Strings")
local Wire = require("src.link.Wire")

local Protocol2 = {}

Protocol2.VERSION = 2
Protocol2.PROTOCOL = 3

Protocol2.INTENTS = { battle = true, trade = true, tournament = true,
                      chat = true, card = true, minigame = true }
Protocol2.JOIN_AS = { player = true, spectator = true }

Protocol2.ACTIVITIES = { "battle_single", "battle_double", "battle_multi", "trade", "chat", "card",
  "watch", "tournament", "minigame_jump", "minigame_crush", "minigame_pick" }
Protocol2.ACTIVITY_RULESET = {
  battle_single = "g3_single", battle_double = "g3_double", battle_multi = "g3_multi",
  trade = "g3_link", chat = "g3_link", card = "g3_link",
  minigame_jump = "g3_link", minigame_crush = "g3_link", minigame_pick = "g3_link" }
Protocol2.ACTIVITY_INTENT = {
  battle_single = "battle", battle_double = "battle", battle_multi = "battle", trade = "trade",
  chat = "chat", card = "card", minigame_jump = "minigame", minigame_crush = "minigame",
  minigame_pick = "minigame" }
-- pokefirered/src/data/union_room.h:44
Protocol2.GROUP_CAPACITY = {
  battle_single = { 2, 2 }, battle_double = { 2, 2 }, trade = { 2, 2 }, battle_multi = { 4, 4 },
  minigame_jump = { 2, 5 }, minigame_crush = { 2, 5 }, minigame_pick = { 3, 5 } }
-- pokefirered/include/constants/union_room.h:21
Protocol2.CART_ACTIVITY = {
  battle_single = 1, battle_double = 2, battle_multi = 3, trade = 4, chat = 5, card = 8,
  minigame_jump = 9, minigame_crush = 10, minigame_pick = 11 }
Protocol2.LINK_GROUP_ACTIVITY = {
  [0] = "battle_single", [1] = "battle_double", [2] = "battle_multi", [3] = "trade",
  [4] = "minigame_jump", [5] = "minigame_crush", [6] = "minigame_pick" }
Protocol2.STATUSES = { idle = true, busy = true, trading = true, battling = true,
  chatting = true, recruiting = true }
Protocol2.WHERE = { launcher = true, game = true, union = true, direct = true }
Protocol2.G3_RULESETS = { "g3_single", "g3_double", "g3_multi", "g3_link" }
Protocol2.SEAT_ROLES = { [0] = "host", [1] = "guest", [2] = "seat2", [3] = "seat3", [4] = "seat4" }
Protocol2.PLAZA_KINDS = { union = true, wireless = true }
Protocol2.DIRECT_ACTIVITIES = { battle_single = true, battle_double = true,
  battle_multi = true, trade = true }

local ACTIVITY_SET = {}
for _, a in ipairs(Protocol2.ACTIVITIES) do ACTIVITY_SET[a] = true end
Protocol2.ACTIVITY_SET = ACTIVITY_SET

function Protocol2.seatRole(seat)
  return Protocol2.SEAT_ROLES[tonumber(seat) or -1]
end

function Protocol2.roleSeat(role)
  for seat, name in pairs(Protocol2.SEAT_ROLES) do
    if name == role then return seat end
  end
  return nil
end

local function build(msg)
  local out = Wire.sanitize(msg)
  return out
end

function Protocol2.lobbyHello(opts)
  opts = opts or {}
  return build({
    type = "lobby_hello",
    protocol = Protocol2.PROTOCOL,
    ticket = opts.ticket,
    name = opts.name,
    engineVersion = opts.engineVersion,
    platform = opts.platform,
    profiles = opts.profiles or {},
    presence = opts.presence,
  })
end

function Protocol2.setProfiles(list)
  return build({ type = "set_profiles", profiles = list or {} })
end

function Protocol2.presence(fields)
  fields = fields or {}
  return build({ type = "presence", where = fields.where, status = fields.status,
                 version = fields.version, engine = fields.engine,
                 board = fields.board })
end

function Protocol2.inviteToken(room)
  return build({ type = "invite_token", room = room })
end

function Protocol2.invite(to, activity, detail, profile)
  return build({ type = "invite", to = to, activity = activity,
                 detail = detail or {}, profile = profile })
end

function Protocol2.inviteReply(id, accept)
  return build({ type = "invite_reply", id = id, accept = accept == true })
end

Protocol2.PLAZA_CAP = 40

function Protocol2.plazaJoin(kind, profile, avatar, cap)
  return build({ type = "plaza_join", kind = kind, profile = profile,
                 avatar = avatar, cap = cap })
end

function Protocol2.plazaLeave(kind)
  return build({ type = "plaza_leave", kind = kind })
end

function Protocol2.groupOpen(activity, profile, avatar)
  return build({ type = "group_open", activity = activity, profile = profile,
                 avatar = avatar })
end

function Protocol2.groupList(activity, profile)
  return build({ type = "group_list", activity = activity, profile = profile })
end

function Protocol2.groupJoin(leader, profile, avatar)
  return build({ type = "group_join", leader = leader, profile = profile,
                 avatar = avatar })
end

function Protocol2.groupAccept(from, ok)
  return build({ type = "group_accept", from = from, ok = ok == true })
end

function Protocol2.groupLeave()
  return build({ type = "group_leave" })
end

function Protocol2.groupStart()
  return build({ type = "group_start" })
end

function Protocol2.directQueue(opts)
  opts = opts or {}
  return build({
    type = "direct_queue",
    activity = opts.activity,
    ruleset = opts.ruleset or Protocol2.ACTIVITY_RULESET[opts.activity or ""],
    auto = opts.auto == true,
    pin = opts.pin,
    profile = opts.profile,
    avatar = opts.avatar,
    preview = opts.preview or {},
  })
end

function Protocol2.directList(activity, profile)
  return build({ type = "direct_list", activity = activity, profile = profile })
end

function Protocol2.directLeave()
  return build({ type = "direct_leave" })
end

function Protocol2.resume(session, ack)
  return build({ type = "resume", session = session, ack = ack or 0 })
end

function Protocol2.advertise(intent, profile, note)
  return build({ type = "advertise", intent = intent, profile = profile,
                 note = note })
end

function Protocol2.unadvertise()
  return build({ type = "unadvertise" })
end

function Protocol2.roomCreate(opts)
  opts = opts or {}
  local private = opts.private == true
  return build({
    type = "room_create",
    intent = opts.intent or "battle",
    profile = opts.profile,
    playing = opts.playing ~= false,
    maxSpectators = opts.maxSpectators,
    private = private,
    pin = private and opts.pin or nil,
    seats = opts.seats or 2,
    auto = opts.auto == true,
    note = opts.note,
  })
end

function Protocol2.roomJoin(roomId, as, profile, pin, invite)
  return build({ type = "room_join", room = roomId, invite = invite,
                 as = as or "player", profile = profile, pin = pin })
end

function Protocol2.roomLeave()
  return build({ type = "room_leave" })
end

function Protocol2.roomReady(party, partyDigest)
  return build({ type = "room_ready", party = party or {},
                 partyDigest = partyDigest })
end

function Protocol2.roomMsg(seq, msg)
  return build({ type = "room_msg", seq = seq, msg = msg })
end

function Protocol2.roomAck(seq)
  return build({ type = "room_ack", seq = seq })
end

function Protocol2.roomReport(match, result)
  return build({ type = "room_report", match = match, result = result })
end

function Protocol2.forfeit(match)
  return build({ type = "forfeit", match = match })
end

function Protocol2.roomKick(id)
  return build({ type = "room_kick", id = id })
end

function Protocol2.roomClose()
  return build({ type = "room_close" })
end

function Protocol2.lobbyQuery()
  return build({ type = "lobby_query" })
end

Protocol2.SHOT_CLOCKS = { 3, 6, 9 }
Protocol2.TOUR_STAGES = { registering = true, running = true, finished = true }
Protocol2.TOUR_MATCH_STATES = { pending = true, live = true, done = true,
                                bye = true }

function Protocol2.shotClock(value)
  local want = tonumber(value)
  if not want then return Protocol2.SHOT_CLOCKS[2] end
  local best, bestGap = Protocol2.SHOT_CLOCKS[2], math.huge
  for _, allowed in ipairs(Protocol2.SHOT_CLOCKS) do
    local gap = math.abs(allowed - want)
    if gap < bestGap then best, bestGap = allowed, gap end
  end
  return best
end

function Protocol2.tourCreate(opts)
  opts = opts or {}
  return build({
    type = "tour_create",
    profile = opts.profile,
    rule = opts.rule,
    playing = opts.playing ~= false,
    shotClock = Protocol2.shotClock(opts.shotClock),
    maxSpectators = opts.maxSpectators,
    party = opts.party,
    partyDigest = opts.partyDigest,
    public = opts.public ~= false,
    note = opts.note,
  })
end

function Protocol2.tourJoin(opts, as, profile, party, partyDigest)
  if type(opts) ~= "table" then
    local ref = opts
    opts = { as = as, profile = profile, party = party, partyDigest = partyDigest }
    if Wire.tourId(ref) then opts.tour = ref else opts.code = ref end
  end
  return build({
    type = "tour_join",
    tour = opts.tour,
    code = opts.code,
    as = opts.as or "player",
    profile = opts.profile,
    party = opts.party,
    partyDigest = opts.partyDigest,
  })
end

function Protocol2.tourLeave()
  return build({ type = "tour_leave" })
end

function Protocol2.tourStart()
  return build({ type = "tour_start" })
end

function Protocol2.tourKick(id)
  return build({ type = "tour_kick", id = id })
end

function Protocol2.tourClose()
  return build({ type = "tour_close" })
end

Protocol2.CLIENT_TYPES = {
  lobby_hello = true, ping = true, pong = true, resume = true,
  advertise = true, unadvertise = true, room_create = true,
  room_join = true, room_leave = true, room_ready = true,
  room_msg = true, room_ack = true, room_report = true, forfeit = true,
  room_kick = true, room_close = true, lobby_query = true,
  tour_create = true, tour_join = true, tour_leave = true,
  tour_start = true, tour_kick = true, tour_close = true,
  set_profiles = true, presence = true, invite_token = true, invite = true,
  invite_reply = true, plaza_join = true, plaza_leave = true,
  group_open = true, group_list = true, group_join = true, group_accept = true,
  group_leave = true, group_start = true, direct_queue = true,
  direct_list = true, direct_leave = true,
}

Protocol2.SERVER_TYPES = {
  lobby_welcome = true, lobby_list = true, lobby_delta = true,
  room_state = true, room_replay = true, room_msg = true,
  room_deadline = true, room_result = true, room_closed = true,
  match_start = true, match_start_spectate = true, join_error = true,
  ping = true, pong = true,
  tour_state = true, tour_match = true, tour_match_spectate = true,
  tour_bye = true, tour_deadline = true, tour_over = true,
  tour_closed = true,
  upgrade_required = true, invite_token = true, invite_sent = true,
  invite_in = true, invite_closed = true, plaza_state = true,
  plaza_delta = true, plaza_counts = true, group_state = true,
  group_request = true, group_list = true, group_closed = true,
  direct_state = true, direct_list = true,
}

Protocol2.RELAY_INNER = { trade_commit = true, trade_abort = true,
                          game3_mg_leader = true }

Protocol2.RESULTS = { win = true, lose = true, draw = true }

local VALIDATORS = {}

VALIDATORS.lobby_welcome = function(m)
  if type(m.session) ~= "string" or m.session == "" then
    return nil, "lobby_welcome without a session id"
  end
  if type(m.you) ~= "table" then return nil, "lobby_welcome without you" end
  return m
end

VALIDATORS.lobby_list = function(m)
  if type(m.entries) ~= "table" then return nil, "lobby_list without entries" end
  return m
end

local DELTA_LISTS = { "added", "removed", "changed", "add", "update", "remove" }

VALIDATORS.lobby_delta = function(m)
  for _, key in ipairs(DELTA_LISTS) do
    if type(m[key]) == "table" and #m[key] > 0 then return m end
  end
  if type(m.op) == "string"
     and (type(m.entry) == "table" or type(m.id) == "string") then
    return m
  end
  return nil, "empty lobby_delta"
end

VALIDATORS.room_state = function(m)
  if type(m.room) ~= "string" then return nil, "room_state without a room id" end
  if type(m.players) ~= "table" then return nil, "room_state without players" end
  return m
end

VALIDATORS.upgrade_required = function(m)
  return m
end

VALIDATORS.invite_token = function(m)
  if type(m.room) ~= "string" then return nil, "invite_token without a room id" end
  if type(m.token) ~= "string" then return nil, "invite_token without a token" end
  return m
end

VALIDATORS.invite_sent = function(m)
  if type(m.id) ~= "string" then return nil, "invite_sent without an id" end
  return m
end

VALIDATORS.invite_in = function(m)
  if type(m.id) ~= "string" then return nil, "invite_in without an id" end
  if type(m.from) ~= "table" or type(m.from.id) ~= "string" then
    return nil, "invite_in without a sender"
  end
  if type(m.activity) ~= "string" then return nil, "invite_in without an activity" end
  return m
end

VALIDATORS.invite_closed = function(m)
  if type(m.why) ~= "string" or m.why == "" then
    return nil, "invite_closed without a why"
  end
  if type(m.id) ~= "string" and type(m.to) ~= "string" then
    return nil, "invite_closed without an id"
  end
  return m
end

VALIDATORS.plaza_state = function(m)
  if type(m.members) ~= "table" then return nil, "plaza_state without members" end
  if type(m.kind) ~= "string" then return nil, "plaza_state without a kind" end
  if m.rev ~= nil and type(m.rev) ~= "number" then return nil, "plaza_state rev is not a number" end
  if m.cap ~= nil and type(m.cap) ~= "number" then return nil, "plaza_state cap is not a number" end
  return m
end

VALIDATORS.plaza_delta = function(m)
  if type(m.kind) ~= "string" then return nil, "plaza_delta without a kind" end
  if m.rev ~= nil and type(m.rev) ~= "number" then return nil, "plaza_delta rev is not a number" end
  return m
end

VALIDATORS.group_state = function(m)
  if type(m.leader) ~= "string" then return nil, "group_state without a leader" end
  if type(m.members) ~= "table" then return nil, "group_state without members" end
  return m
end

VALIDATORS.group_request = function(m)
  if type(m.from) ~= "string" then return nil, "group_request without a sender" end
  return m
end

VALIDATORS.group_list = function(m)
  if type(m.groups) ~= "table" then return nil, "group_list without groups" end
  return m
end

VALIDATORS.group_closed = function(m)
  if type(m.leader) ~= "string" then return nil, "group_closed without a leader" end
  return m
end

VALIDATORS.direct_list = function(m)
  if type(m.entries) ~= "table" then return nil, "direct_list without entries" end
  return m
end

VALIDATORS.direct_state = function(m)
  return m
end

VALIDATORS.room_replay = function(m)
  if type(m.msgs) ~= "table" then return nil, "room_replay without msgs" end
  return m
end

VALIDATORS.room_msg = function(m)
  if type(m.msg) ~= "table" or type(m.msg.type) ~= "string" then
    return nil, "room_msg without an inner message"
  end
  if type(m.seq) ~= "number" then return nil, "room_msg without a seq" end
  return m
end

VALIDATORS.room_deadline = function(m)
  if type(m.kind) ~= "string" then return nil, "room_deadline without a kind" end
  if type(m.at) ~= "number" then return nil, "room_deadline without a time" end
  return m
end

VALIDATORS.match_start = function(m)
  if type(m.role) ~= "string" or m.role == "" then
    return nil, "match_start without a role"
  end
  if type(m.match) ~= "string" or m.match == "" then
    return nil, "match_start without a match token"
  end
  if type(m.room) ~= "string" then return nil, "match_start without a room id" end
  return m
end

VALIDATORS.match_start_spectate = function(m)
  if type(m.match) ~= "string" or m.match == "" then
    return nil, "match_start without a match token"
  end
  if type(m.room) ~= "string" then return nil, "match_start without a room id" end
  return m
end

VALIDATORS.room_closed = function(m)
  if type(m.reason) ~= "string" or m.reason == "" then
    return nil, "room_closed without a reason"
  end
  return m
end

VALIDATORS.room_result = function(m)
  if type(m.how) ~= "string" then return nil, "room_result without how" end
  return m
end

VALIDATORS.tour_state = function(m)
  if type(m.tour) ~= "string" then
    return nil, "tour_state without a tournament id"
  end
  if type(m.players) ~= "table" then return nil, "tour_state without players" end
  if type(m.bracket) ~= "table" then return nil, "tour_state without a bracket" end
  if not Protocol2.TOUR_STAGES[m.stage or ""] then
    return nil, "tour_state without a stage"
  end
  return m
end

VALIDATORS.tour_match = function(m)
  if type(m.match) ~= "string" or m.match == "" then
    return nil, "tour_match without a match token"
  end
  if type(m.room) ~= "string" then
    return nil, "tour_match without a child room id"
  end
  return m
end

VALIDATORS.tour_match_spectate = VALIDATORS.tour_match

VALIDATORS.tour_bye = function(m)
  if type(m.match) ~= "string" or m.match == "" then
    return nil, "tour_bye without a match token"
  end
  return m
end

VALIDATORS.tour_deadline = function(m)
  if type(m.kind) ~= "string" or m.kind == "" then
    return nil, "tour_deadline without a kind"
  end
  if type(m.at) ~= "number" then return nil, "tour_deadline without a time" end
  return m
end

VALIDATORS.tour_closed = function(m)
  if type(m.reason) ~= "string" or m.reason == "" then
    return nil, "tour_closed without a reason"
  end
  return m
end

VALIDATORS.tour_over = function(m)
  if type(m.tour) ~= "string" then
    return nil, "tour_over without a tournament id"
  end
  return m
end

VALIDATORS.join_error = function(m)
  if type(m.reason) ~= "string" or m.reason == "" then
    return nil, "join_error without a reason"
  end
  return m
end

Protocol2.VALIDATORS = VALIDATORS

function Protocol2.validate(raw)
  if type(raw) ~= "table" then return nil, "not a table" end
  local msg = Wire.sanitize(raw)
  if not msg then return nil, "failed sanitize" end
  local validator = VALIDATORS[msg.type]
  if not validator then return msg end
  local ok, reason = validator(msg)
  if not ok then return nil, reason end
  return ok
end

local REASONS = {
  not_found = Strings.source("That room wasn't found."),
  full = Strings.source("That room is full."),
  expired = Strings.source("That room has expired."),
  profile_mismatch = Strings.source("Your game doesn't match the room."),
  rule_violation = Strings.source("Your team doesn't meet the room's rule."),
  spectate_late = Strings.source("That match is too far along to watch."),
  bad_ticket = Strings.source("The relay didn't accept your sign-in."),
  lobby_disabled = Strings.source("This relay isn't running online play."),
  resume_unknown = Strings.source("The relay forgot your session."),
  resume_expired = Strings.source("You were away too long to rejoin."),
  already_in_room = Strings.source("You're already in a room."),
  spectators_full = Strings.source("That room has all the spectators it can take."),
  bad_profile = Strings.source("The relay couldn't read your game's profile."),
  bad_party = Strings.source("The relay couldn't read your team."),
  party_ineligible = Strings.source("Your team doesn't meet the room's rule."),
  tour_not_found = Strings.source("That tournament wasn't found."),
  tour_started = Strings.source("That tournament has already started."),
  tour_full = Strings.source("That tournament is full."),
  not_creator = Strings.source("Only the tournament's creator can do that."),
  bad_room = Strings.source("That room wasn't found."),
  bad_pin = Strings.source("The PIN didn't match."),
  pin_required = Strings.source("That room needs a PIN."),
  pin_locked = Strings.source("Too many tries. Please try again later."),
  bad_seats = Strings.source("That room can't have that many players."),
  bad_stage = Strings.source("That room isn't taking that right now."),
  invite_expired = Strings.source("That invite has expired."),
  tour_private = Strings.source("That tournament is private."),
  group_not_found = Strings.source("That group is gone."),
  group_full = Strings.source("That group is full."),
  group_below_min = Strings.source("The group needs more members."),
  not_leader = Strings.source("Only the group's leader can do that."),
  already_in_group = Strings.source("You're already in a group."),
  bad_activity = Strings.source("That activity isn't available."),
  already_queued = Strings.source("You're already waiting for a partner."),
  rate_limited = Strings.source("Too many requests. Please wait a moment."),
}

local CLOSED_REASONS = {
  kicked = Strings.source("The host removed you from the room."),
  closed = Strings.source("The host closed the room."),
  idle = Strings.source("The room was closed for being idle."),
  backlog = Strings.source("You fell too far behind to keep watching."),
}

local TOUR_CLOSED_REASONS = {
  kicked = Strings.source("The creator removed you from the tournament."),
  closed = Strings.source("The creator closed the tournament."),
  idle = Strings.source("The tournament was closed for being idle."),
}

local INVITE_CLOSED = {
  accepted = Strings.source("The invite was accepted."),
  crossed = Strings.source("The invite was accepted."),
  declined = Strings.source("The invite was declined."),
  timeout = Strings.source("There was no answer."),
  busy = Strings.source("That trainer appears to be busy."),
  offline = Strings.source("That trainer isn't online."),
  self = Strings.source("You can't invite yourself."),
  target_left = Strings.source("That trainer left."),
  sender_left = Strings.source("The other trainer left."),
  rate_limited = Strings.source("Too many invites. Please wait a moment."),
  profile_mismatch = Strings.source("Your games don't match."),
  bad_activity = Strings.source("That activity isn't available."),
  no_room = Strings.source("That room is gone."),
  no_group = Strings.source("That group is gone."),
  group_full = Strings.source("That group is full."),
}

Protocol2.UPGRADE_TEXT = Strings.source("This build is too old for online play. Please update.")

function Protocol2.tourClosedText(msg)
  local reason = type(msg) == "table" and msg.reason or tostring(msg)
  local text = TOUR_CLOSED_REASONS[reason]
  if text then return Strings(text) end
  return Strings("The tournament closed: %s", tostring(reason))
end

function Protocol2.roomClosedText(msg)
  local reason = type(msg) == "table" and msg.reason or tostring(msg)
  local text = CLOSED_REASONS[reason]
  if text then return Strings(text) end
  return Strings("The room closed: %s", tostring(reason))
end

function Protocol2.joinErrorText(msg, nowMs)
  local reason = type(msg) == "table" and msg.reason or tostring(msg)
  local text = REASONS[reason] and Strings(REASONS[reason])
    or Strings("Couldn't join: %s", tostring(reason))
  local tries = type(msg) == "table" and msg.triesLeft or nil
  if reason == "bad_pin" and type(tries) == "number" then
    text = text .. " " .. Strings("Tries left: %d.", tries)
  end
  local retryAt = type(msg) == "table" and msg.retryAt or nil
  if reason == "pin_locked" and type(retryAt) == "number" and type(nowMs) == "number"
     and retryAt > nowMs then
    text = text .. " " .. Strings("Try again in %d min.", math.ceil((retryAt - nowMs) / 60000))
  end
  local detail = type(msg) == "table" and msg.detail or nil
  if detail and detail ~= "" then return text .. " (" .. detail .. ")" end
  return text
end

function Protocol2.inviteClosedText(msg)
  local why = type(msg) == "table" and msg.why or tostring(msg)
  local text = INVITE_CLOSED[why] and Strings(INVITE_CLOSED[why])
    or Strings("The invite closed: %s", tostring(why))
  local detail = type(msg) == "table" and msg.detail or nil
  if detail and detail ~= "" then return text .. " (" .. detail .. ")" end
  return text
end

function Protocol2.upgradeText(msg)
  local text = type(msg) == "table" and msg.text or nil
  if type(text) == "string" and text ~= "" then return text end
  return Strings(Protocol2.UPGRADE_TEXT)
end

return Protocol2
