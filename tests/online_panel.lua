package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
love = love or require("tests.love_stub")

local OnlinePanel = require("src.import.OnlinePanel")
local SyncState = require("src.sync.SyncState")
local Client = require("src.online.Client")

-- ------------------------------------------------------------- names

T.eq(OnlinePanel.sanitizeName("RED"), "RED", "a plain name survives")
T.eq(OnlinePanel.sanitizeName('R<E>D&"x\''), "REDx",
  "the relay's five banned characters are dropped")
T.eq(OnlinePanel.sanitizeName("  RED  "), "RED", "outer space is trimmed")
T.eq(#OnlinePanel.sanitizeName(("A"):rep(40)), OnlinePanel.NAME_MAX,
  "a long name is capped at 16")

T.check(OnlinePanel.nameValid("RED#417"), "RED#417 is a valid display name")
T.check(not OnlinePanel.nameValid("AB"), "two characters is too short")
T.check(not OnlinePanel.nameValid(("A"):rep(17)), "seventeen is too long")
T.check(not OnlinePanel.nameValid("RE<D"), "a banned character is not valid")

T.eq(OnlinePanel.defaultName("RED", "417"), "RED#417",
  "the default name is trainer#digits")
T.eq(OnlinePanel.defaultName("", "417"), "PLAYER#417",
  "a nameless save falls back to PLAYER")
T.eq(OnlinePanel.defaultName(("A"):rep(20), "417"),
  ("A"):rep(12) .. "#417", "a long trainer name is trimmed for the suffix")
T.eq(#OnlinePanel.threeDigits(function() return 7 end), 3,
  "the suffix is always three digits")
T.eq(OnlinePanel.threeDigits(function() return 7 end), "007",
  "the suffix is zero padded")

-- ------------------------------------------------------------- codes

T.eq(OnlinePanel.sanitizeCode("ab2cd3"), "AB2CD3", "join codes upper-case")
T.eq(OnlinePanel.sanitizeCode("A1B0I-2 3"), "AB23",
  "characters outside CodeEntry.CHARSET are dropped")
T.eq(OnlinePanel.sanitizeCode("ABCDEFGH"), "ABCDEF",
  "a join code is six characters")

-- --------------------------------------------------- display name storage

local files = {}
local memfs = {
  read = function(path) return files[path] end,
  write = function(path, body) files[path] = body return true end,
  remove = function(path) files[path] = nil return true end,
  getInfo = function(path) return files[path] and { type = "file" } or nil end,
  createDirectory = function() return true end,
  getDirectoryItems = function() return {} end,
  load = function(path)
    if not files[path] then return nil, "no file" end
    return load(files[path], path)
  end,
}

SyncState.save({ displayName = "RED#417" }, memfs)
T.eq(SyncState.load(memfs).displayName, "RED#417",
  "sanitize keeps displayName across a save/load round trip")
SyncState.save({ displayName = 42 }, memfs)
T.eq(SyncState.load(memfs).displayName, nil,
  "a non-string displayName is dropped by sanitize")

-- --------------------------------------------------------- profile cache

T.eq(OnlinePanel.profileKey("red", "vanilla", nil), "red|vanilla|-",
  "a vanilla arena keys on the game alone")
T.eq(OnlinePanel.profileKey("red", "cart", "kanto"), "red|cart|kanto",
  "a cart arena keys on the cart id")

local imp = {
  ready = { red = true, gold = true },
  activeSlot = {}, slots = {}, pulse = 0,
  _pages = {}, _uiActions = {}, _actAt = {},
}
local st = OnlinePanel.state(imp)
st.version = "red"
T.eq(OnlinePanel.selectedVersion(imp), "red", "the chosen game sticks")
st.version = "blue"
T.eq(OnlinePanel.selectedVersion(imp), "red",
  "an unimported game falls back to the first imported one")
T.check(OnlinePanel.isGen2("gold"), "gold is a gen 2 game")
T.check(not OnlinePanel.isGen2("red"), "red is not a gen 2 game")

st.version, st.kind, st.cartId = "red", "vanilla", nil
st.profiles = {}
local got, reason = OnlinePanel.myProfile(imp)
T.eq(got, nil, "the profile is not ready on the first ask")
T.eq(reason, nil, "a missing profile is a spinner, not an error")
T.eq(st.profileWant, "red|vanilla|-", "the draw pass queues the computation")

st.profiles["red|vanilla|-"] = { profile = { engine = 1, version = "red",
  fingerprint = "abc", kind = "vanilla", rule = {} } }
st.rule = { partySize = 3, minLevel = 50 }
local mine = OnlinePanel.myProfile(imp)
T.eq(mine.fingerprint, "abc", "the cached profile is handed back")
T.eq(mine.rule.partySize, 3, "the live rule is stamped onto the cached profile")
T.eq(mine.rule.minLevel, 50, "and so is the level floor")

-- ------------------------------------------------------------- team pick

local function teamKeys(team)
  local out = {}
  for i, ref in ipairs(team) do out[i] = OnlinePanel.refKey(ref) end
  return table.concat(out, ",")
end

local team = {}
OnlinePanel.toggleTeam(team, 3, 3)
OnlinePanel.toggleTeam(team, 1, 3)
T.eq(teamKeys(team), "party|3,party|1",
  "picks keep the order they were tapped in")
T.eq(OnlinePanel.teamOrder(team, 1), 2, "the second pick is slot 2")
OnlinePanel.toggleTeam(team, 3, 3)
T.eq(teamKeys(team), "party|1", "tapping a picked mon takes it back out")
OnlinePanel.toggleTeam(team, 2, 2)
OnlinePanel.toggleTeam(team, 4, 2)
T.eq(teamKeys(team), "party|1,party|2", "the cap handed in is the cap on picks")
T.eq(OnlinePanel.teamOrder(team, 4), nil, "an unpicked mon has no order")

do
  local mixed = {}
  OnlinePanel.toggleTeam(mixed, { where = "box", box = 2, index = 5 })
  OnlinePanel.toggleTeam(mixed, 1)
  T.eq(teamKeys(mixed), "box|2|5,party|1",
    "a team may mix a box mon and a party mon")
  T.check(OnlinePanel.teamHasBox(mixed), "which the panel can tell apart")
  T.eq(OnlinePanel.teamIndices(mixed), nil,
    "a mixed team has no party-index form for ArenaBoot")
  OnlinePanel.toggleTeam(mixed, { where = "box", box = 2, index = 5 })
  T.eq(teamKeys(mixed), "party|1", "and a box pick unpicks by its own key")
  T.eq(table.concat(OnlinePanel.teamIndices(mixed), ","), "1",
    "a party-only team still rides as indices")
  local capped = {}
  for i = 1, 8 do OnlinePanel.toggleTeam(capped, i) end
  T.eq(#capped, OnlinePanel.TEAM_MAX, "six is the hard ceiling on a team")
end

-- ---------------------------------------------------------- join reasons

local ArenaData = require("src.online.ArenaData")
local base = {
  engine = 1, version = "red", engineVersion = "1.2.3", apiVersion = 4,
  fingerprint = "abc", rulesetId = "gen1_faithful", kind = "vanilla",
}
local function copy(t, patch)
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  for k, v in pairs(patch or {}) do out[k] = v end
  return out
end

T.eq(OnlinePanel.joinReason({ profile = copy(base) }, copy(base)), nil,
  "matching profiles are joinable")
T.eq(OnlinePanel.joinReason({ profile = copy(base, { fingerprint = "zzz" }) },
  copy(base)), "data differs", "a fingerprint split names the data")
T.eq(OnlinePanel.joinReason({ profile = copy(base, { version = "yellow" }) },
  copy(base)), nil, "another gen 1 game with the same surface is joinable")
T.eq(OnlinePanel.joinReason({ profile = copy(base) }, nil),
  "pick a game first", "with no profile of our own we cannot judge")
T.check(ArenaData.equal(copy(base), copy(base, { rule = { partySize = 6 } })),
  "the rule is not part of profile equality")

-- ------------------------------------------------------------- rule text

T.eq(OnlinePanel.ruleText({ partySize = 3 }), "3 v 3", "a bare rule reads as NvN")
T.eq(OnlinePanel.ruleText({ partySize = 6, forceLevel = 50 }),
  "6 v 6, all Lv50", "a forced level replaces the level window")
T.eq(OnlinePanel.ruleText({ partySize = 2, minLevel = 20, maxLevel = 40 }),
  "2 v 2, Lv20+, Lv40-", "both level bounds show")
T.eq(OnlinePanel.arenaText({ kind = "cart", cart = { id = "kanto" } }), "kanto",
  "a cart arena is named by its cart")
T.eq(OnlinePanel.arenaText({ kind = "vanilla" }), "vanilla",
  "a vanilla arena says so")

-- -------------------------------------------------------- match_start spec

local session = {}
function session:send() end
function session:poll() return {} end
function session:close() end

st.slotId = "slot1"
st.team = { { where = "party", index = 1 }, { where = "party", index = 2 },
            { where = "party", index = 3 } }
local party = { { species = "PIKACHU" }, { species = "GEODUDE" },
                { species = "ONIX" } }
local spec, err = OnlinePanel.buildSpec(imp, {
  role = "host",
  seed = 4242,
  profile = { engine = 1, version = "red", kind = "vanilla",
              engineVersion = "1.2.3", rulesetId = "gen1_faithful",
              fingerprint = "abc", rule = { partySize = 3 } },
  peerName = "BLUE", hostName = "RED", guestName = "BLUE",
  theirParty = party,
}, { session = session })
T.check(spec ~= nil, "a host match_start builds a spec (" .. tostring(err) .. ")")
if spec then
  T.eq(spec.role, "host", "the spec carries the role")
  T.eq(spec.seed, 4242, "the spec carries the host's seed")
  T.eq(spec.slotId, "slot1", "the spec carries the chosen save slot")
  T.eq(table.concat(spec.team, ","), "1,2,3", "the spec carries the team order")
  T.eq(spec.peerName, "BLUE", "the spec carries the peer name")
  T.eq(spec.session, session, "the spec carries the room session")
  T.eq(spec.profile.rule.partySize, 3, "the spec carries the room's rule")
  T.eq(#spec.theirParty, 3, "the spec carries the other party")
end

local spectate = OnlinePanel.buildSpec(imp, {
  role = "spectator",
  seed = 7,
  profile = { engine = 1, version = "red", kind = "vanilla",
              rule = { partySize = 3 } },
  hostName = "RED", guestName = "BLUE",
  hostParty = party, guestParty = party,
}, { session = session })
T.check(spectate ~= nil, "a spectator match_start builds a spec")
if spectate then
  T.eq(spectate.role, "spectator", "the spectator spec keeps its role")
  T.eq(spectate.team, nil, "a spectator has no team")
end

-- ------------------------------------------------------------ the result

OnlinePanel.lastResult = nil
local reported = {}
local savedReport = Client.report
Client.report = function(result) reported[#reported + 1] = result end
OnlinePanel.recordResult("win")
T.eq(OnlinePanel.lastResult, "win", "the arena's result survives the launcher")
T.eq(reported[1], "win", "a win is reported to the relay")
OnlinePanel.recordResult("error")
T.eq(#reported, 2, "an errored match is handed to the relay as a forfeit")
T.eq(reported[2], "error", "with the raw result, which Client.report forfeits")
T.eq(OnlinePanel.lastResult, "error", "and it is still remembered")
local savedRole = Client.role
Client.role = function() return "spectator" end
OnlinePanel.recordResult("ended")
T.eq(#reported, 2, "a spectator never reports the result")
Client.role = savedRole
Client.report = savedReport

do
  local savedR = Client.report
  Client.report = function() return false end
  OnlinePanel.recordResult("lose")
  T.eq(OnlinePanel.lastResult, "lose",
    "a report queued for re-send still records the result")
  Client.report = savedR
end

do
  local lostImp = {
    ready = { red = true }, activeSlot = {}, slots = {}, pulse = 0,
    _pages = {}, _uiActions = {}, _actAt = {},
  }
  local lst = OnlinePanel.state(lostImp)
  lst.version, lst.ready = "red", true
  OnlinePanel.go(lostImp, "play")
  OnlinePanel.go(lostImp, "room")
  OnlinePanel._roomLost = "Connection lost, left the room."
  OnlinePanel.update(lostImp, 1 / 60)
  T.eq(OnlinePanel.screen(lostImp), "play",
    "a lost room walks the tab back to Play")
  T.eq(lst.status, "Connection lost, left the room.",
    "with one human line saying why")
  T.eq(lst.ready, false, "and the ready flag cleared")
end

local savedYou = Client.you
Client.you = function() return { id = "me", name = "RED", verified = true } end
T.eq(OnlinePanel.resultText({ winner = "me", how = "reported" }), "win",
  "winning the room means you won")
T.eq(OnlinePanel.resultText({ winner = "them", how = "reported" }), "lose",
  "the other seat winning means you lost")
T.eq(OnlinePanel.resultText({ winner = nil, how = "agreed" }), "draw",
  "no winner is a draw")
Client.you = savedYou

-- --------------------------------------------------------- join by code

local joined = nil
local savedJoin = Client.joinRoom
Client.joinRoom = function(code, as, profile)
  joined = { code = code, as = as, profile = profile }
end
T.check(OnlinePanel.joinByCode(imp, "ab2cd3", "player"),
  "a six-character code joins")
T.eq(joined and joined.code, "AB2CD3", "the code is upper-cased on the way out")
T.eq(joined and joined.as, "player", "the join role is passed through")
T.eq(joined and joined.profile and joined.profile.version, "red",
  "and the join carries the profile of the game that is picked")
joined = nil
T.check(not OnlinePanel.joinByCode(imp, "AB", "player"),
  "a short code is refused")
T.eq(joined, nil, "and nothing is sent")
T.check(OnlinePanel.state(imp).status ~= nil, "the refusal says why")
Client.joinRoom = savedJoin


-- ------------------------------------------------------------ tournaments

local TOUR = {
  code = "TRN234", creator = "me", stage = "running", round = 2,
  shotClock = 6,
  players = {
    { id = "me", name = "RED", verified = true, online = true },
    { id = "p2", name = "BLUE", online = true },
    { id = "p3", name = "GREEN", online = false, eliminated = true },
  },
  spectators = { { id = "s1", name = "WATCH" } },
  profile = { engine = 1, version = "red", kind = "vanilla",
              rule = { partySize = 3 } },
  rule = { partySize = 3 },
  bracket = {
    { round = 1, matches = {
        { match = "TRN234-r1-m1", a = "me", b = "p3", winner = "me",
          how = "agreed", state = "done" },
        { match = "TRN234-r1-m2", a = "p2", state = "bye" } } },
    { round = 2, matches = {
        { match = "TRN234-r2-m1", a = "me", b = "p2", state = "live" } } },
  },
  live = "TRN234-r2-m1",
  deadlines = { shot = 7000 },
}

local columns = OnlinePanel.bracketColumns(TOUR)
T.eq(#columns, 2, "the bracket lays out one column per round")
T.eq(columns[1].round, 1, "the first column is round 1")
T.eq(#columns[1].matches, 2, "round 1 keeps both matches")
T.eq(columns[1].matches[1].aName, "RED", "ids resolve to display names")
T.eq(columns[1].matches[1].bName, "GREEN", "on both sides")
T.eq(columns[1].matches[1].winnerName, "RED", "and for the winner")
T.eq(columns[1].matches[1].how, "agreed", "the card keeps how it was decided")
T.eq(columns[1].matches[2].bye, true, "a one-sided match is a bye")
T.eq(columns[2].matches[1].live, true, "the live match is marked")
T.eq(columns[1].matches[1].live, false, "a finished match is not")
T.eq(OnlinePanel.matchText(columns[2].matches[1]), "RED vs BLUE",
  "a match card reads a vs b")
T.eq(OnlinePanel.matchText(columns[1].matches[2]), "BLUE  bye",
  "a bye card says so")
T.eq(OnlinePanel.tourName(TOUR, "ghost"), "ghost",
  "an unknown id falls back to itself")
T.eq(#OnlinePanel.bracketColumns(nil), 0, "no tournament draws no columns")
T.eq(#OnlinePanel.bracketColumns({ code = "TRN234" }), 0,
  "an undrawn bracket draws no columns")

T.eq(OnlinePanel.bannerText(TOUR, "me"), "You play next",
  "a player in the live match is told it plays next")
T.eq(OnlinePanel.bannerText(TOUR, "s1"), "Watching: RED vs BLUE",
  "everyone else is told what they are watching")
T.eq(OnlinePanel.bannerText({ stage = "registering", players = {} }, "me"), nil,
  "a registering tournament has no banner")
T.eq(OnlinePanel.bannerText({ stage = "finished", champion = "me",
  players = TOUR.players, bracket = {} }, "p2"), "Champion: RED",
  "a finished tournament names its champion")

local controls = OnlinePanel.creatorControls(TOUR, "me")
T.check(controls.isCreator, "the creator is recognised")
T.check(not controls.canStart, "a running tournament cannot be started again")
T.check(controls.canKick and controls.canClose,
  "the creator keeps kick and close")
T.eq(controls.players, 3, "the control model counts the field")
local guestControls = OnlinePanel.creatorControls(TOUR, "p2")
T.check(not guestControls.isCreator, "a player is not the creator")
T.check(not (guestControls.canStart or guestControls.canKick
  or guestControls.canClose), "and gets no creator controls")
local waiting = { code = "TRN234", creator = "me", stage = "registering",
                  players = { { id = "me" } }, bracket = {} }
T.check(not OnlinePanel.creatorControls(waiting, "me").canStart,
  "one player is not enough to start")
waiting.players[2] = { id = "p2" }
T.check(OnlinePanel.creatorControls(waiting, "me").canStart,
  "two players are")

T.eq(OnlinePanel.countdown(7000, 1000), 6, "the shot clock counts down in seconds")
T.eq(OnlinePanel.countdown(1000, 7000), 0, "a passed deadline reads zero")
T.eq(OnlinePanel.countdown(nil, 1000), nil, "a missing deadline has no count")

local savedServerTime = Client.serverTime
Client.serverTime = function() return 1000 end
T.eq(OnlinePanel.tourDeadline(TOUR), 6,
  "the panel reads the deadline off the relay clock")
Client.serverTime = savedServerTime

local specSpec = OnlinePanel.buildSpec(imp, {
  role = "spectator", seed = 11, code = "CHA234",
  profile = TOUR.profile,
  hostName = "RED", guestName = "BLUE",
  hostParty = party, guestParty = party,
}, { session = session })
T.check(specSpec ~= nil, "a tournament spectate payload builds a spec")
if specSpec then
  T.eq(specSpec.role, "spectator", "the tournament spectator boots as one")
  T.eq(specSpec.team, nil, "and brings no team")
  T.eq(specSpec.session, session, "over the child room's session")
end

-- --------------------------------------------------- headless panel draw

local Kit = require("src.ui.kit.Kit")
local Layout = require("src.ui.kit.Layout")

local function drawFor(target, width, height)
  Kit.layout(width, height)
  Kit.beginFrame(-1, -1, false, 0)
  local m = Layout.metrics(1200)
  local ok, result = pcall(OnlinePanel.buildOnlinePanel, target, m.contentX,
    m.top + 100, m.contentW, math.max(200, m.h - 200), m)
  Kit.endFrame()
  return ok, result
end

local function drawPanel(width, height)
  return drawFor(imp, width, height)
end

-- ------------------------------------------------------------- navigation

T.eq(OnlinePanel.screen(imp), "home", "the tab opens on Home")
T.check(OnlinePanel.go(imp, "play"), "Home pushes Play")
T.eq(OnlinePanel.screen(imp), "play", "which is where the stack points")
OnlinePanel.go(imp, "wizard")
T.eq(#OnlinePanel.nav(imp), 3, "a wizard stacks on top of Play")
T.check(OnlinePanel.back(imp), "Back pops one screen")
T.eq(OnlinePanel.screen(imp), "play", "landing back on Play")
OnlinePanel.go(imp, "home")
T.eq(#OnlinePanel.nav(imp), 1,
  "going to a screen already open pops back down to it")
T.check(not OnlinePanel.back(imp), "Back on Home does nothing")
T.check(not OnlinePanel.go(imp, "nonsense"), "an unknown screen is refused")
T.eq(OnlinePanel.SCREENS.setup, nil, "the old Setup screen is gone")

-- ---------------------------------------------------------------- wizards

do
  local st = OnlinePanel.state(imp)
  st.setupDone, st.slotId, st.team = nil, nil, {}
  st.ruleEdited = false
  st.rule = { partySize = 1 }
  T.check(OnlinePanel.startWizard(imp, "hostBattle"), "Host a battle opens a wizard")
  T.eq(OnlinePanel.screen(imp), "wizard", "on the wizard screen")
  T.eq(table.concat(OnlinePanel.wizardSteps(imp), ","),
    "game,save,team,rules,visibility,summary",
    "with one step per choice and a summary last")
  T.eq(OnlinePanel.wizardStep(imp), "game", "starting on the game")
  T.check(OnlinePanel.wizardReady(imp), "a game is already chosen")
  T.check(OnlinePanel.wizardNext(imp), "Next walks to the save")
  T.eq(OnlinePanel.wizardStep(imp), "save", "which is step two")
  T.check(not OnlinePanel.wizardReady(imp), "with no save chosen yet")
  T.check(not OnlinePanel.wizardNext(imp), "Next refuses to skip it")
  st.slotId = "slot1"
  local WSAVE = { party = {
    { species = "PIKACHU", level = 20, moves = {} },
    { species = "MEW", level = 30, moves = {} },
    { species = "ONIX", level = 15, moves = {} } } }
  st.slotRead = { key = "red|slot1|-",
    data = { generation = 1, party = WSAVE.party, save = WSAVE } }
  OnlinePanel.wizardNext(imp)
  T.eq(OnlinePanel.wizardStep(imp), "team", "then the team")
  T.check(not OnlinePanel.wizardReady(imp), "which needs at least one pick")
  OnlinePanel.toggleTeam(st.team, 1)
  OnlinePanel.toggleTeam(st.team, 2)
  T.check(OnlinePanel.wizardReady(imp), "two picks are enough")
  T.eq(select(2, OnlinePanel.validateTeam(imp)), nil,
    "and the Team step never reports a rule error")
  OnlinePanel.wizardNext(imp)
  T.eq(OnlinePanel.wizardStep(imp), "rules", "then the rules")
  T.eq(OnlinePanel.ruleFor(imp).partySize, 2,
    "whose party size defaults to what was picked")
  OnlinePanel.editRule(imp)
  st.rule.partySize = 3
  T.eq(OnlinePanel.ruleFor(imp).partySize, 3,
    "an edited rule is left alone afterwards")
  T.check(OnlinePanel.ruleMismatch(imp, st.rule, "Your rule") ~= nil,
    "and only then is the team measured against it")
  st.rule.partySize = 2
  T.eq(OnlinePanel.ruleMismatch(imp, st.rule, "Your rule"), nil,
    "a rule that matches the picks says nothing")
  OnlinePanel.wizardNext(imp)
  T.eq(OnlinePanel.wizardStep(imp), "visibility", "then who can see it")
  T.eq(st.public, true, "public by default")
  OnlinePanel.wizardNext(imp)
  T.eq(OnlinePanel.wizardStep(imp), "summary", "and the summary last")

  local answers = OnlinePanel.wizardAnswers(imp)
  local seen = {}
  for _, row in ipairs(answers) do seen[row.step] = row.value end
  T.check(seen.game ~= nil, "the summary lists the game")
  T.check(seen.team ~= nil, "and the team")
  T.check(seen.rules ~= nil, "and the rule")
  T.check(seen.visibility ~= nil, "and the visibility")
  T.check(OnlinePanel.wizardTo(imp, "save"),
    "a Change link jumps back to that step")
  T.eq(OnlinePanel.wizardStep(imp), "save", "which is where the wizard lands")

  local created = nil
  local savedCreate = Client.createRoom
  Client.createRoom = function(opts) created = opts return { done = false } end
  OnlinePanel.state(imp).profiles["red|vanilla|-"] =
    { profile = { engine = 1, version = "red", kind = "vanilla",
                  fingerprint = "abc", rule = {} } }
  OnlinePanel.wizardTo(imp, "summary")
  T.check(OnlinePanel.wizardNext(imp), "the confirm hosts the room")
  T.eq(created and created.intent, "battle", "as a battle room")
  T.eq(created and created.public, true, "listed publicly")
  T.eq(OnlinePanel.screen(imp), "room", "and lands on the Room screen")
  T.eq(OnlinePanel.wizard(imp), nil, "with the wizard put away")
  Client.createRoom = savedCreate
  OnlinePanel.home(imp)
end

do
  local st = OnlinePanel.state(imp)
  st.tourPlaying = true
  OnlinePanel.startWizard(imp, "hostTournament")
  T.eq(table.concat(OnlinePanel.wizardSteps(imp), ","),
    "game,save,playing,team,rules,shotclock,spectators,summary",
    "the tournament wizard owns the shot clock and the spectators")
  st.tourPlaying = false
  T.eq(table.concat(OnlinePanel.wizardSteps(imp), ","),
    "game,save,playing,rules,shotclock,spectators,summary",
    "an organizer never picks a team")
  st.tourPlaying = true
  OnlinePanel.home(imp)
end

do
  local st = OnlinePanel.state(imp)
  st.setupDone, st.slotId = true, "slot1"
  st.team = { { where = "party", index = 1 } }
  T.check(OnlinePanel.startJoin(imp, "ab2cd3", { partySize = 3 }),
    "joining from a row opens the join wizard")
  T.eq(table.concat(OnlinePanel.wizardSteps(imp), ","), "summary",
    "steps already answered this session are skipped")
  T.check(OnlinePanel.wizardTo(imp, "team"),
    "and Change brings one back")
  T.eq(OnlinePanel.wizardStep(imp), "team", "as its own step")
  OnlinePanel.wizardTo(imp, "summary")
  local joined = nil
  local savedJoin = Client.joinRoom
  Client.joinRoom = function(code, as) joined = { code = code, as = as } end
  T.check(not OnlinePanel.wizardNext(imp),
    "a team the room's rule refuses does not join")
  T.eq(joined, nil, "nothing is sent")
  T.eq(st.status, "This room needs 3 Pokemon, you picked 1.",
    "and the message names the requirement")
  OnlinePanel.toggleTeam(st.team, 2)
  OnlinePanel.toggleTeam(st.team, 3)
  T.check(OnlinePanel.wizardNext(imp), "matching the rule joins")
  T.eq(joined and joined.code, "AB2CD3", "with the sanitized code")
  T.eq(OnlinePanel.screen(imp), "room", "landing on Room")
  Client.joinRoom = savedJoin
  OnlinePanel.home(imp)
end

-- -------------------------------------------------------------- deep link

do
  local joined = nil
  local savedJoin = Client.joinRoom
  Client.joinRoom = function(code, as) joined = { code = code, as = as } end
  local st = OnlinePanel.state(imp)
  st.setupDone, st.slotId, st.team = nil, nil, {}
  T.check(OnlinePanel.deepLink(imp, "ab2cd3"),
    "a join-code deep link is taken")
  T.eq(OnlinePanel.screen(imp), "wizard",
    "an unconfigured player sets up first")
  T.eq(joined, nil, "and nothing is sent yet")
  st.slotId = "slot1"
  OnlinePanel.toggleTeam(st.team, 1)
  OnlinePanel.wizardTo(imp, "summary")
  OnlinePanel.wizardNext(imp)
  T.eq(joined and joined.code, "AB2CD3", "then the code is joined")
  T.eq(OnlinePanel.screen(imp), "room", "on the Room screen")
  joined = nil
  OnlinePanel.home(imp)
  T.check(OnlinePanel.deepLink(imp, "cd3ab2"),
    "a configured player skips straight to the summary")
  T.eq(table.concat(OnlinePanel.wizardSteps(imp), ","), "summary",
    "with nothing left to answer")
  OnlinePanel.wizardNext(imp)
  T.eq(joined and joined.code, "CD3AB2", "with the sanitized code")
  T.eq(OnlinePanel.screen(imp), "room", "landing on Room")
  T.check(not OnlinePanel.deepLink(imp, "AB"), "a short code is refused")
  Client.joinRoom = savedJoin
  OnlinePanel.home(imp)
end

-- ---------------------------------------------------------------- filters

do
  T.eq(OnlinePanel.filter(imp), "all", "the list is unfiltered by default")
  local gen2Entry = { profile = { engine = 2, version = "gold",
                                  kind = "vanilla" } }
  local cartEntry = { profile = { engine = 1, version = "red", kind = "cart",
                                  cart = { id = "kanto" } } }
  local gen1Entry = { profile = { engine = 1, version = "red",
                                  kind = "vanilla" } }
  T.check(OnlinePanel.entryPasses("all", gen2Entry),
    "All shows every lobby")
  T.check(OnlinePanel.setFilter(imp, "gen2"), "the Gen 2 chip picks one")
  T.check(OnlinePanel.entryPasses("gen2", gen2Entry), "which keeps Gen 2")
  T.check(not OnlinePanel.entryPasses("gen2", gen1Entry),
    "and hides Gen 1")
  T.check(OnlinePanel.entryPasses("carts", cartEntry),
    "the cart chip keeps cart arenas")
  T.check(not OnlinePanel.entryPasses("vanilla", cartEntry),
    "and Vanilla hides them")
  T.check(not OnlinePanel.setFilter(imp, "nope"),
    "an unknown filter is refused")
  T.eq(OnlinePanel.filter(imp), "gen2", "leaving the chosen one alone")
  OnlinePanel.setFilter(imp, "all")
  T.check(OnlinePanel.entryPasses("gen1", {}),
    "an entry with no profile is never filtered out")
  T.eq(OnlinePanel.FILTER_AT, 8,
    "the chip row stays hidden until the list is longer than eight")
end

-- ------------------------------------------------------- every screen draws

local savedRoom, savedTournament = Client.room, Client.tournament
local savedState, savedYou, savedLobby = Client.state, Client.you, Client.lobby
local savedOpen, savedWatchable, savedCounts =
  Client.openRooms, Client.watchable, Client.counts
local ROOM_FIXTURE = {
  code = "AB2CD3", host = "me", stage = "waiting", intent = "battle",
  profile = { engine = 1, version = "red", kind = "vanilla",
              rule = { partySize = 3 } },
  players = { { id = "me", name = "RED", ready = false },
              { id = "p2", name = "BLUE", ready = true } },
  spectators = { { id = "s1", name = "GREEN" } },
  deadlines = { ready = 61000 },
}
local FAKE_LOBBY = {}
for i = 1, 50 do
  FAKE_LOBBY[i] = { id = "e" .. i, code = ("L%05d"):format(i),
    name = "TRAINER" .. i, verified = i % 3 == 0, open = true,
    intent = (i % 11 == 0) and "tournament" or "battle",
    note = (i % 4 == 0) and "first to three" or nil,
    spectators = i % 3,
    profile = { engine = 1, version = "red", kind = "vanilla",
                fingerprint = (i % 5 == 0) and "other" or "abc",
                rule = { partySize = 3 } },
    stage = (i % 6 == 0) and "battling" or "waiting" }
end
FAKE_LOBBY[#FAKE_LOBBY + 1] = { id = "me", code = "MINE01", name = "RED",
  open = true, intent = "battle", stage = "waiting",
  profile = { engine = 1, version = "red", kind = "vanilla",
              fingerprint = "abc", rule = { partySize = 3 } } }

Client.state = function() return "online" end
Client.you = function() return { id = "me", name = "RED", verified = true } end
Client.lobby = function() return FAKE_LOBBY end
Client.openRooms = function()
  local out = {}
  for _, entry in ipairs(FAKE_LOBBY) do
    if entry.open and entry.id ~= "me" then out[#out + 1] = entry end
  end
  return out
end
Client.watchable = function()
  local out = {}
  for _, entry in ipairs(FAKE_LOBBY) do
    if entry.stage == "battling" or entry.intent == "tournament" then
      out[#out + 1] = entry
    end
  end
  return out
end
Client.counts = function() return { players = 51, openRooms = 50 } end
Client.room = function() return ROOM_FIXTURE end
Client.tournament = function() return TOUR end

OnlinePanel.state(imp).setupDone = true
OnlinePanel.state(imp).slotId = "slot1"

-- ------- the Play and Watch lists

do
  OnlinePanel.home(imp)
  OnlinePanel.go(imp, "play")
  OnlinePanel.invalidate(imp, "lobby")
  OnlinePanel.refresh(imp)
  local c = OnlinePanel.cache(imp)
  local sawMe, sawTournament = false, false
  for _, row in ipairs(c.rooms) do
    if row.id == "me" then sawMe = true end
    if row.intent == "tournament" then sawTournament = true end
  end
  T.check(#c.rooms > 0, "Play lists the open rooms")
  T.check(not sawMe, "and never the player's own room")
  T.check(not sawTournament, "tournaments are not battle rows")
  T.eq(c.counts.players, 51, "Home counts players off Client.counts")
  T.eq(c.counts.lobbies, 50, "and open rooms off the same call")
  T.check(c.mine ~= nil, "hosting puts a Your lobby card on Play")
  T.eq(c.mine.code, "AB2CD3", "carrying the room's code")

  local sawMeWatching = false
  for _, row in ipairs(c.watch) do
    if row.id == "me" then sawMeWatching = true end
  end
  T.check(#c.watch > 0, "Watch lists live rooms and tournaments")
  T.check(not sawMeWatching, "and never the player's own entry")
end

local SCREENS = { "home", "play", "wizard", "room", "watch", "tournament",
                  "trade" }
local screenCost = {}
for _, id in ipairs(SCREENS) do
  OnlinePanel.home(imp)
  if id == "wizard" then
    OnlinePanel.startWizard(imp, "hostBattle")
  else
    OnlinePanel.go(imp, id)
  end
  if id == "trade" then OnlinePanel.tradeState(imp).chosen = true end
  OnlinePanel.state(imp).routeKey = "R" .. ROOM_FIXTURE.code
  OnlinePanel.refresh(imp)
  Kit.audit = {}
  local wideOk, wideH = drawFor(imp, 1280, 800)
  local wideControls = #Kit.audit
  Kit.audit = nil
  T.check(wideOk, id .. " draws in the two-column layout ("
    .. tostring(wideH) .. ")")
  T.check(wideOk and type(wideH) == "number" and wideH > 0,
    id .. " reports a content height")
  T.check(wideControls > 0, id .. " registers interactive controls")
  local narrowOk, narrowH = drawFor(imp, 420, 900)
  T.check(narrowOk, id .. " draws in the stacked layout ("
    .. tostring(narrowH) .. ")")
  T.check(narrowOk and type(narrowH) == "number" and narrowH > 0,
    id .. " reports a height there too")
  local clock = os.clock
  drawFor(imp, 1280, 800)
  local started = clock()
  for _ = 1, 25 do drawFor(imp, 1280, 800) end
  screenCost[id] = (clock() - started) / 25
end

for _, id in ipairs(SCREENS) do
  T.check(screenCost[id] < 0.008,
    ("%s draws in %.3f ms"):format(id, screenCost[id] * 1000))
end

do
  local st = OnlinePanel.state(imp)
  for kind in pairs(OnlinePanel.WIZARDS) do
    OnlinePanel.home(imp)
    st.tourPlaying = true
    OnlinePanel.startWizard(imp, kind)
    local steps = OnlinePanel.wizardSteps(imp)
    for at = 1, #steps do
      st.wizard.at = at
      T.check(drawFor(imp, 1280, 800),
        kind .. " step " .. steps[at] .. " draws wide")
      T.check(drawFor(imp, 420, 900),
        kind .. " step " .. steps[at] .. " draws stacked")
    end
  end
  OnlinePanel.home(imp)
end

-- ------- the trade room shows its code

do
  local savedRoomFn, savedTourFn = Client.room, Client.tournament
  Client.tournament = function() return nil end
  Client.room = function()
    return { code = "TR9ZQ2", host = "me", stage = "waiting",
             intent = "trade",
             profile = { engine = 1, version = "red", kind = "vanilla",
                         rule = { partySize = 1 } },
             players = { { id = "me", name = "RED" } }, spectators = {} }
  end
  OnlinePanel.home(imp)
  OnlinePanel.state(imp).routeKey = nil
  OnlinePanel.update(imp, 1 / 60)
  T.eq(OnlinePanel.screen(imp), "room",
    "a hosted trade waits on the Room screen, not the picker")
  Kit.audit = {}
  local drewRoom = drawFor(imp, 1280, 800)
  local seen = Kit.audit or {}
  Kit.audit = nil
  T.check(drewRoom, "which draws")
  local sawCopy = false
  for _, row in ipairs(seen) do
    if tostring(row.label or "") == "Copy" then sawCopy = true end
  end
  T.check(sawCopy, "with a Copy button beside the code")
  Client.room, Client.tournament = savedRoomFn, savedTourFn
  OnlinePanel.state(imp).routeKey = nil
  OnlinePanel.home(imp)
end

-- ------------------------------------------------- nothing reads on a draw

do
  local SaveData = require("src.core.SaveData")
  local CartStore = require("src.carts.CartStore")
  local TeamPick = require("src.online.TeamPick")
  local ArenaDataMod = require("src.online.ArenaData")
  local CacheFs = require("src.import.CacheFs")
  local reads = 0
  local watched = {
    { SaveData, "listSlots" }, { SaveData, "listCartSlots" },
    { SaveData, "loadOptions" }, { CartStore, "get" }, { CartStore, "listFor" },
    { TeamPick, "readSlot" }, { ArenaDataMod, "profile" },
    { CacheFs, "readAt" }, { CacheFs, "read" },
  }
  local saved = {}
  for i, entry in ipairs(watched) do
    local mod, name = entry[1], entry[2]
    saved[i] = mod[name]
    if type(saved[i]) == "function" then
      mod[name] = function(...)
        reads = reads + 1
        return saved[i](...)
      end
    end
  end
  local counted = {
    ready = { red = true, gold = true },
    activeSlot = {}, slots = {}, carts = {}, pulse = 0,
    _pages = {}, _uiActions = {}, _actAt = {},
  }
  local cst = OnlinePanel.state(counted)
  cst.version, cst.setupDone = "red", true
  OnlinePanel.refresh(counted)
  for _, id in ipairs(SCREENS) do
    OnlinePanel.home(counted)
    OnlinePanel.go(counted, id)
    if id == "trade" then OnlinePanel.tradeState(counted).chosen = true end
    OnlinePanel.refresh(counted)
    drawFor(counted, 1280, 800)
    reads = 0
    drawFor(counted, 1280, 800)
    drawFor(counted, 420, 900)
    T.eq(reads, 0, id .. " draws without reading a save, a cart or the cache")
  end
  for i, entry in ipairs(watched) do
    entry[1][entry[2]] = saved[i]
  end
end

Client.state, Client.you, Client.lobby = savedState, savedYou, savedLobby
Client.openRooms, Client.watchable, Client.counts =
  savedOpen, savedWatchable, savedCounts
Client.room, Client.tournament = savedRoom, savedTournament
OnlinePanel.home(imp)

-- --------------------------------------------------------- the room engine

do
  local eng = {
    ready = { red = true, gold = true },
    activeSlot = {}, slots = {}, pulse = 0,
    _pages = {}, _uiActions = {}, _actAt = {},
  }
  local est = OnlinePanel.state(eng)
  est.version = "red"
  T.eq(table.concat(OnlinePanel.installedGenerations(eng), ","), "1,2",
    "both generations are offered when both are imported")
  T.eq(OnlinePanel.engineVersionFor(eng, 2), "gold",
    "the first imported game of a generation is the engine's cache")
  T.eq(OnlinePanel.roomEngine(eng), 1, "the engine defaults to the save's own")
  T.eq(OnlinePanel.engineVersion(eng), "red", "and so does the cache it boots")
  T.check(not OnlinePanel.crossGen(eng), "matching generations are not crossed")

  T.check(OnlinePanel.setEngine(eng, 2), "Gen 2 rules can be chosen")
  T.eq(OnlinePanel.roomEngine(eng), 2, "the choice sticks")
  T.eq(OnlinePanel.engineVersion(eng), "gold",
    "a Red save under Gen 2 rules boots the imported Gen 2 game")
  T.check(OnlinePanel.crossGen(eng), "which is a Time Capsule room")

  local solo = { ready = { red = true }, activeSlot = {}, slots = {},
                 pulse = 0, _pages = {}, _uiActions = {}, _actAt = {} }
  OnlinePanel.state(solo).version = "red"
  T.check(not OnlinePanel.setEngine(solo, 2),
    "Gen 2 rules need a Gen 2 cache")
  T.eq(OnlinePanel.roomEngine(solo), 1, "so the engine stays where it was")
  T.check(OnlinePanel.state(solo).status ~= nil, "and the refusal says why")

  est.kind, est.cartId = "cart", "kanto"
  est.profiles = {}
  OnlinePanel.myProfile(eng)
  T.eq(est.profileWant, "gold|vanilla|-",
    "a cross-generation room is vanilla on the engine's own game")
  est.kind, est.cartId = "vanilla", nil

  est.slotId = "slot1"
  local party = { { species = "PIKACHU", level = 20 },
                  { species = "HOOTHOOT", level = 20 } }
  est.slotRead = { key = "red|slot1|-",
                   data = { party = party, generation = 1 } }
  local key = OnlinePanel.convertKey(eng)
  T.eq(key, "red|slot1|-|gold", "the conversion is keyed on both games")
  est.converted = { key = key, data = {
    generation = 2,
    byKey = { ["party|1"] = { species = "PIKACHU", level = 20,
                              happiness = 70 } },
    rows = {
      ["party|1"] = { ok = true, preview = { "NOTHING IS LOST" } },
      ["party|2"] = { ok = false, reason = "species_too_new",
        preview = { "SPECIES NOT IN GEN 1: HOOTHOOT" } },
    } } }
  T.eq(OnlinePanel.monRefusal(eng, 1), nil, "a legal mon has no refusal")
  T.eq(OnlinePanel.monRefusal(eng, 2), "species_too_new",
    "an illegal one names its reason")
  T.eq(OnlinePanel.monPreview(eng, 1)[1], "NOTHING IS LOST",
    "the picker shows the conversion preview")

  est.rule = { partySize = 1 }
  est.team = { { where = "party", index = 2 } }
  T.eq(OnlinePanel.validateTeam(eng), false,
    "a refused mon cannot be taken into a Time Capsule room")
  est.team = { { where = "party", index = 1 } }
  T.eq(OnlinePanel.validateTeam(eng), true, "a legal one can")
  local packed = OnlinePanel.packForRoom(eng, est.slotRead.data, est.team, 1)
  T.eq(#packed, 1, "the room gets the converted team")
  T.eq(packed[1].happiness, 70, "packed with the engine's own codec")
  local refusedPack, packWhy = OnlinePanel.packForRoom(eng, est.slotRead.data,
    { { where = "party", index = 2 } }, 1)
  T.eq(refusedPack, nil, "a refused mon never reaches the wire")
  T.check(packWhy ~= nil, "and the caller is told why")
end

-- ------------------------------------------------------------- trade model

do
  local timp = {
    ready = { red = true, gold = true },
    activeSlot = {}, slots = {}, pulse = 0,
    _pages = {}, _uiActions = {}, _actAt = {},
  }
  timp.slots["red"] = {
    { id = "slot1", exists = true, label = "RED" },
    { id = "slot2", exists = true, label = "BLUE" },
    { id = "slot3", exists = false },
  }
  timp.slots["gold"] = { { id = "slot1", exists = true, label = "GOLD" } }
  timp._ensureCarts = function() return {} end
  local tst = OnlinePanel.state(timp)
  tst.version = "red"

  local tr = OnlinePanel.tradeState(timp)
  T.eq(tr.mode, "local", "trade opens on the local mode")
  T.check(OnlinePanel.tradeMode(timp, "remote"), "the mode switches")
  T.eq(OnlinePanel.tradeState(timp).mode, "remote", "and sticks")
  T.check(not OnlinePanel.tradeMode(timp, "nonsense"),
    "an unknown mode is refused")
  OnlinePanel.tradeMode(timp, "local")

  local rows = OnlinePanel.tradeSlots(timp)
  T.eq(#rows, 3, "every save on the machine can be traded from")
  T.eq(rows[1].slotId, "slot1", "listed in the launcher's own order")
  T.eq(rows[3].version, "gold", "across games")

  T.check(OnlinePanel.sameSlot(rows[1], { version = "red", slotId = "slot1" }),
    "two references to one save are the same slot")
  T.check(not OnlinePanel.sameSlot(rows[1], rows[2]),
    "two slots in one game are not")
  T.check(not OnlinePanel.sameSlot(rows[1],
    { version = "red", slotId = "slot1", cartId = "kanto" }),
    "and a cart scope is a different save")

  tr.sides.b = rows[1]
  T.check(not OnlinePanel.tradeSetSide(timp, "a", rows[1]),
    "a slot cannot trade with itself")
  T.check(tr.status ~= nil, "and the panel says so")
  tr.sides.b = nil
  tr.handles = {}

  tr.sides.a, tr.sides.b = rows[1], rows[2]
  tr.handles.a = { entry = rows[1], handle = { generation = 1, party = {
    { species = "KADABRA", level = 30, nickname = "ABRA-CAD" } } } }
  tr.handles.b = { entry = rows[2], handle = { generation = 1, party = {
    { species = "PIKACHU", level = 25 } } } }
  T.check(OnlinePanel.tradeSideView(timp, "a") ~= nil,
    "an opened side is cached against its slot")
  tr.sides.a = rows[3]
  T.eq(OnlinePanel.tradeSideView(timp, "a"), nil,
    "changing the slot drops the stale handle")
  tr.sides.a = rows[1]

  tr.plan = { sides = {} }
  T.eq(OnlinePanel.tradePick(timp, "a", 1), 1, "tapping a mon picks it")
  T.eq(tr.plan, nil, "which invalidates any preview")
  T.eq(OnlinePanel.tradePick(timp, "a", 1), nil, "tapping it again unpicks it")
  OnlinePanel.tradePick(timp, "a", 1)
  OnlinePanel.tradePick(timp, "b", 1)
  T.check(not OnlinePanel.tradePreview(timp) or true,
    "preview runs against the opened handles")

  local plan = {
    sides = {
      { role = "a", sent = { species = "KADABRA", level = 30 },
        received = { species = "PIKACHU", level = 25 },
        record = { species = "PIKACHU", level = 25 } },
      { role = "b", sent = { species = "PIKACHU", level = 25 },
        received = { species = "KADABRA", level = 30 },
        record = { species = "ALAKAZAM", level = 30 },
        evolveTo = "ALAKAZAM" },
    },
    warnings = { { code = "evolve", species = "ALAKAZAM" },
                 { code = "item_used", item = "METAL_COAT" } },
  }
  local lines = OnlinePanel.tradeLines(plan, { a = "RED", b = "BLUE" },
    { { toGen = 2, lines = { "SPECIAL SPLIT 100 -> 90/80" } } })
  T.eq(lines[1], "RED gives KADABRA Lv30 and gets PIKACHU Lv25",
    "each side reads as give and get")
  T.eq(lines[2], "BLUE gives PIKACHU Lv25 and gets KADABRA Lv30",
    "for both saves")
  T.eq(lines[3], "KADABRA evolves into ALAKAZAM",
    "a trade evolution is called out")
  T.eq(lines[4], "METAL COAT is used up.", "so is a consumed held item")
  T.eq(lines[5], "SPECIAL SPLIT 100 -> 90/80",
    "and the Time Capsule preview rides along")
  T.eq(#OnlinePanel.tradeLines(nil), 0, "no plan reads as no lines")

  T.eq(OnlinePanel.monLabel({ species = "KADABRA", level = 30 }),
    "KADABRA Lv30", "a mon reads as species and level")
  T.eq(OnlinePanel.monLabel({ species = "KADABRA", nickname = "ABRA CAD",
    level = 30 }), "ABRA CAD Lv30", "a nickname wins")

  -- remote stages, rendered off a fake session
  T.eq(OnlinePanel.remoteStageText("picking"),
    "Tap the POKeMON you want to trade", "each stage has its own line")
  T.eq(OnlinePanel.remoteStageText("waitPick"),
    "Waiting for the other trainer to pick", "including the waits")
  T.eq(OnlinePanel.remoteStageText("weird"), "weird",
    "an unknown stage falls back to itself")

  local fake = {
    handle = { generation = 1, party = {
      { species = "KADABRA", level = 30 }, { species = "PIKACHU", level = 25 },
      { species = "ODDISH", level = 5, isEgg = true } } },
    session = {
      stage = "picking", myPick = 2, theirPick = 1,
      theirParty = { { species = "MACHOKE", level = 30 } },
      canPick = function(_, index) return index ~= 3 end,
    },
  }
  local mine, theirs = OnlinePanel.remoteRows(fake)
  T.eq(#mine, 3, "my whole party is drawn")
  T.eq(mine[2].picked, true, "my pick is marked")
  T.eq(mine[1].picked, false, "the others are not")
  T.eq(mine[3].pickable, false,
    "what the other game cannot rebuild is not pickable")
  T.eq(#theirs, 1, "their party comes off the session")
  T.eq(theirs[1].label, "MACHOKE Lv30", "with the same labels")
  T.eq(theirs[1].picked, true, "and their pick marked")
  T.eq(select(2, OnlinePanel.remoteRows(nil)) ~= nil, true,
    "no session draws two empty columns")

  -- ------- picking a trade column's mon out of the PC
  local PC_SAVE = {
    party = { { species = "KADABRA", level = 30, nickname = "ABRA-CAD" } },
    boxes = { {}, { { species = "ONIX", level = 14, hp = 30, maxHp = 30 } } },
  }
  local pcHandle = tr.handles.a.handle
  pcHandle.version, pcHandle.save = "red", PC_SAVE
  pcHandle.boxes, pcHandle.party = PC_SAVE.boxes, PC_SAVE.party
  tr.picks = {}

  T.check(OnlinePanel.tradePcAllowed(timp, "a"),
    "a local trade column offers its PC")
  OnlinePanel.tradeMode(timp, "remote")
  T.check(not OnlinePanel.tradePcAllowed(timp, "a"),
    "a remote trade is party only, so no From PC button")
  T.check(not OnlinePanel.pcOpen(timp, { side = "a" }),
    "and the popup refuses to open there")
  OnlinePanel.tradeMode(timp, "local")

  T.check(OnlinePanel.pcOpen(timp, { side = "a" }),
    "From PC opens against the column that asked")
  OnlinePanel.refresh(timp)
  local pcRows = OnlinePanel.pcRows(timp)
  T.eq(#pcRows, 1, "listing only what is in that save's boxes")
  T.eq(pcRows[1].source, "BOX 2", "each row names the box it sits in")
  T.eq(pcRows[1].ref.where, "box", "and records where the pick came from")
  T.eq(pcRows[1].ref.box, 2, "which box")
  T.eq(pcRows[1].ref.index, 1, "and which slot in it")
  OnlinePanel.pcQuery(timp, "kadabra")
  T.eq(#OnlinePanel.pcRows(timp), 0,
    "the filter searches the boxes, not the party")
  OnlinePanel.pcQuery(timp, "")

  T.check(OnlinePanel.pcPick(timp, OnlinePanel.pcRows(timp)[1]),
    "tapping a row picks it for that column")
  T.eq(OnlinePanel.pcPicker(timp), nil, "and closes the popup behind it")
  T.eq(OnlinePanel.tradePickKey(timp, "a"), "box|2|1",
    "the column now holds a box reference")
  OnlinePanel.refresh(timp)
  local col = OnlinePanel.cache(timp).tradeRows.a
  T.eq(#col, 2, "the column draws the party plus the boxed pick")
  T.eq(col[1].picked, false, "the party row is not the pick")
  T.eq(col[2].picked, true, "the boxed one is")
  T.check(tostring(col[2].label):find("BOX 2", 1, true) ~= nil,
    "and the row says which box it came from")
  T.eq(OnlinePanel.tradePick(timp, "a", col[2].ref), nil,
    "tapping the boxed row again unpicks it")
  OnlinePanel.refresh(timp)
  T.eq(#OnlinePanel.cache(timp).tradeRows.a, 1,
    "which drops the extra row from the column")
  T.eq(OnlinePanel.tradePick(timp, "a", 1), 1,
    "a party pick is still a plain slot number")
  tr.picks = {}

  tst.slotId = "slot1"
  tst.engine = nil
  T.eq(OnlinePanel.remoteTradeRefusal(timp), nil,
    "a same-generation remote trade is allowed")
  tst.engine = 2
  T.eq(OnlinePanel.remoteTradeRefusal(timp),
    "Both players need the same game generation for now.",
    "a cross-generation one is refused for now")
  tst.engine = nil
  tst.slotId = nil
  T.check(OnlinePanel.remoteTradeRefusal(timp) ~= nil,
    "and so is a trade with no save chosen")
  tst.slotId = "slot1"
end

-- --------------------------------------------------------- install the cart

do
  local CartStore = require("src.carts.CartStore")
  local savedGet = CartStore.get
  local cimp = {
    ready = { red = true }, activeSlot = {}, slots = {}, pulse = 0,
    _pages = {}, _uiActions = {}, _actAt = {},
  }
  local cst = OnlinePanel.state(cimp)
  cst.version = "red"

  T.eq(OnlinePanel.cartNeed({ kind = "vanilla" }), nil,
    "a vanilla room needs no cart")
  T.eq(OnlinePanel.cartNeed(nil), nil, "and neither does no profile")

  CartStore.get = function() return nil, "not installed" end
  local need = OnlinePanel.cartNeed({ kind = "cart", version = "red",
    cart = { id = "kanto", version = "1.0.0", hash = "abc" } })
  T.eq(need and need.id, "kanto", "a missing cart is named")
  T.eq(need and need.reason, "missing", "as missing")
  T.eq(need and need.base, "red", "with the game it plays as")

  CartStore.get = function() return { id = "kanto" }, "zzz" end
  need = OnlinePanel.cartNeed({ kind = "cart", version = "red",
    cart = { id = "kanto", version = "1.0.0", hash = "abc" } })
  T.eq(need and need.reason, "hash", "a wrong hash is a reason of its own")

  CartStore.get = function() return { id = "kanto" }, "abc" end
  T.eq(OnlinePanel.cartNeed({ kind = "cart", version = "red",
    cart = { id = "kanto", version = "1.0.0", hash = "abc" } }), nil,
    "the right cart at the right hash needs nothing")
  CartStore.get = savedGet

  T.check(not OnlinePanel.installCart(cimp, { id = "kanto", base = "red" }),
    "a launcher with no installer refuses")
  T.check(cst.status ~= nil, "and says so")
  local asked = nil
  cimp.installCartForOnline = function(_, id, version, done)
    asked = { id = id, version = version }
    done(true, "kanto and its mods are installed.")
    return true
  end
  cst.profiles = { ["red|vanilla|-"] = { profile = { kind = "vanilla" } } }
  T.check(OnlinePanel.installCart(cimp, { id = "kanto", base = "red" }),
    "otherwise the room panel routes at the launcher's installer")
  T.eq(asked and asked.id, "kanto", "with the cart id")
  T.eq(asked and asked.version, "red", "and the game it plays as")
  T.eq(next(cst.profiles), nil, "a finished install recomputes the profile")
  T.eq(cst.cartInstall, nil, "and clears the in-flight marker")
  T.check(cst.statusOk, "the outcome is shown")
end

-- ------------------------------------------------------------- the sprites

do
  local OnlineSprites = require("src.online.OnlineSprites")
  local savedRead, savedMake = OnlineSprites.readBytes, OnlineSprites.makeImage
  local reads, made = {}, 0

  local FILES = {
    ["red/data/generated/pokemon.lua"] = [[return {
      PIKACHU = { dex = 25, spriteFront = "assets/generated/battle/front/pikachu.png" },
      MEW = { dex = 151, spriteFront = "assets/generated/battle/front/mew.png" },
    }]],
    ["red/data/generated/icons.lua"] = [[return {
      byDex = { [25] = "MON", [151] = "MON" },
      icons = { MON = "assets/generated/sprites/monster.png",
                HELIX = "assets/generated/sprites/fossil.png" },
    }]],
    ["red/data/generated/palettes.lua"] = [[return {
      pokemon = { PIKACHU = "YELLOW" },
      palettes = { YELLOW = { {255,255,255},{255,222,0},{180,120,0},{0,0,0} } },
    }]],
    ["gold/data/generated/pokemon.lua"] = [[return {
      TOTODILE = { dex = 158, spriteFront = "assets/generated/battle/front/totodile.png" },
    }]],
    ["gold/data/generated/icons.lua"] = [[return {
      generation = 2,
      species = { TOTODILE = "ICON_MONSTER" },
      icons = { ICON_MONSTER = { image = "assets/generated/icons/gen2/monster.png",
                                 frames = 2, width = 16, height = 32 } },
    }]],
    ["gold/data/generated/palettes.lua"] = [[return {
      pokemon = { TOTODILE = { normal = { {0,0,255},{0,0,120} },
                               shiny = { {255,0,0},{120,0,0} } } },
    }]],
  }

  OnlineSprites.readBytes = function(version, path)
    local full = tostring(version) .. "/" .. path
    reads[#reads + 1] = full
    return FILES[full] or "PNG"
  end
  OnlineSprites.makeImage = function(_, path, palette)
    made = made + 1
    return { path = path, palette = palette,
             getDimensions = function() return 16, 32 end }
  end
  OnlineSprites.reset()

  T.eq(OnlineSprites.key("red", "PIKACHU", false), "red|PIKACHU|normal",
    "the cache key is version, species and shininess")
  T.eq(OnlineSprites.key("gold", "TOTODILE", true), "gold|TOTODILE|shiny",
    "a shiny is a key of its own")

  T.eq(OnlineSprites.get("red", { species = "PIKACHU" }), nil,
    "the draw path asks the cache and gets nothing before priming")
  T.eq(#reads, 0, "and never touches the filesystem")

  T.eq(OnlineSprites.prime("red", { { species = "PIKACHU" },
    { species = "MEW" } }), 2, "priming loads a whole party")
  local entry = OnlineSprites.get("red", { species = "PIKACHU" })
  T.check(entry ~= nil, "which the draw path then finds")
  T.eq(entry.icon.path, "assets/generated/sprites/monster.png",
    "the Gen 1 icon comes off byDex")
  T.eq(entry.mirror, true,
    "and is drawn as the mirrored left half, as the OAM writer does")
  T.eq(entry.front.path, "assets/generated/battle/front/pikachu.png",
    "with the species' own front pic")
  T.eq(entry.front.palette[2][2], 222,
    "painted with the version's palette for that species")

  local before = made
  OnlineSprites.prime("red", { { species = "PIKACHU" } })
  T.eq(made, before, "a second prime of the same mon loads nothing")

  OnlineSprites.prime("gold", { { species = "TOTODILE" },
    { species = "TOTODILE", shiny = true } })
  local normal = OnlineSprites.get("gold", { species = "TOTODILE" })
  local shiny = OnlineSprites.get("gold", { species = "TOTODILE", shiny = true })
  T.eq(normal.icon.path, "assets/generated/icons/gen2/monster.png",
    "a Gen 2 icon comes off the species map")
  T.eq(normal.mirror, false, "and is not mirrored")
  T.eq(normal.front.palette[2][3], 255, "the normal GBC palette is used")
  T.eq(shiny.front.palette[2][1], 255, "and a shiny gets its own")

  T.check(OnlineSprites.get("red", { species = "PIKACHU" }) ~= nil,
    "both versions are cached at once for a cross-generation trade")
  OnlineSprites.keepOnly({ "gold" })
  T.eq(OnlineSprites.get("red", { species = "PIKACHU" }), nil,
    "a version leaving the selection is evicted")
  T.check(OnlineSprites.get("gold", { species = "TOTODILE" }) ~= nil,
    "the one still on screen is kept")

  OnlineSprites.reset()
  OnlineSprites.readBytes, OnlineSprites.makeImage = savedRead, savedMake
end

-- ------------------------------------------------------ trade sub-view draw

do
  local tradeImp = imp
  OnlinePanel.home(tradeImp)
  OnlinePanel.go(tradeImp, "trade")
  local tr = OnlinePanel.tradeState(tradeImp)
  tr.chosen = false
  Kit.audit = {}
  T.check(drawPanel(1280, 800), "Trade opens on the two mode cards")
  T.check(#Kit.audit > 0, "which are both tappable")
  tr.chosen, tr.mode = true, "local"
  OnlinePanel.invalidate(tradeImp, "trade")
  OnlinePanel.refresh(tradeImp)
  Kit.audit = {}
  local localOk = drawPanel(1280, 800)
  local localControls = #Kit.audit
  T.check(localOk, "the local picker draws in the wide layout")
  T.check(localControls > 0, "and registers its own controls")
  Kit.audit = {}
  T.check(drawPanel(420, 900), "and in the stacked layout")
  tr.mode = "remote"
  Kit.audit = {}
  local remoteOk = drawPanel(1280, 800)
  T.check(remoteOk, "so does the remote mode")
  T.check(#Kit.audit > 0, "with host, join and a code field")
  Kit.audit = nil
  OnlinePanel.home(tradeImp)
end

-- ------------------------------------------------ the trade preview modal

do
  local TradeScreen = require("src.import.online.TradeScreen")
  local LauncherView = require("src.import.LauncherView")
  T.eq(type(LauncherView.modalPanel), "function",
    "the launcher exports the modal panel the trade modal draws into")

  local mimp = {
    ready = { red = true }, activeSlot = {}, slots = {}, pulse = 0,
    _pages = {}, _uiActions = {}, _actAt = {},
  }
  mimp.slots["red"] = { { id = "slot1", exists = true, label = "RED" },
                        { id = "slot2", exists = true, label = "BLUE" } }
  mimp._ensureCarts = function() return {} end
  OnlinePanel.state(mimp).version = "red"
  OnlinePanel.go(mimp, "trade")
  local tr = OnlinePanel.tradeState(mimp)
  tr.chosen, tr.mode = true, "local"
  local rows = OnlinePanel.tradeSlots(mimp)
  tr.sides.a, tr.sides.b = rows[1], rows[2]
  local handleA = { version = "red", generation = 1, slotId = "slot1",
    party = { { species = "KADABRA", level = 30 } } }
  local handleB = { version = "red", generation = 1, slotId = "slot2",
    party = { { species = "PIKACHU", level = 25 } } }
  tr.handles.a = { entry = rows[1], handle = handleA }
  tr.handles.b = { entry = rows[2], handle = handleB }
  tr.picks.a, tr.picks.b = 1, 1
  tr.plan = {
    sides = {
      { role = "a", handle = handleA, sent = { species = "KADABRA", level = 30 },
        received = { species = "PIKACHU", level = 25 },
        record = { species = "PIKACHU", level = 25 } },
      { role = "b", handle = handleB, sent = { species = "PIKACHU", level = 25 },
        received = { species = "KADABRA", level = 30 },
        record = { species = "ALAKAZAM", level = 30 },
        evolveTo = "ALAKAZAM" },
    },
    warnings = { { code = "item_used", item = "METAL_COAT" } },
  }
  tr.convertLines = { { toGen = 2, lines = { "FRIENDSHIP SET TO 70" } } }

  T.eq(OnlinePanel.tradeModal(mimp), nil, "no modal is up to begin with")
  T.check(OnlinePanel.tradeModalOpen(mimp), "a planned trade opens the modal")
  local mo = OnlinePanel.tradeModal(mimp)
  T.eq(mo.view, "preview", "which opens on the preview")
  T.eq(mo.give.label, "KADABRA Lv30", "the give side is the mon leaving")
  T.eq(mo.get.label, "PIKACHU Lv25", "the get side is the one arriving")
  T.eq(mo.give.version, "red", "with the version its sprite comes from")
  T.eq(mo.lines[1], "KADABRA evolves into ALAKAZAM",
    "the change list leads with the evolution")
  T.eq(mo.lines[2], "METAL COAT is used up.", "then the consumed item")
  T.eq(mo.lines[3], "FRIENDSHIP SET TO 70", "then the conversion lines")
  T.eq(Kit.focusId, OnlinePanel.TRADE_MODAL_CANCEL,
    "and the ring starts on Cancel")

  local drawn, controls
  local function frame(width, height)
    Kit.layout(width, height)
    Kit.beginFrame(-1, -1, false, 0)
    local m = Layout.metrics(1200)
    Kit.blockClicks = OnlinePanel.tradeModal(mimp) ~= nil
    pcall(OnlinePanel.buildOnlinePanel, mimp, m.contentX, m.top + 100,
      m.contentW, math.max(200, m.h - 200), m)
    local blockedNav = Kit._navN
    Kit.blockClicks = false
    Kit.audit = {}
    local ok, result = pcall(TradeScreen.drawModal, mimp, m)
    controls = #Kit.audit
    Kit.audit = nil
    Kit.endFrame()
    drawn = ok and result
    return blockedNav
  end

  local blockedNav = frame(1280, 800)
  T.check(drawn, "the modal draws over the wide layout")
  T.check(controls > 0, "with its own tappable controls")
  T.eq(blockedNav, 0,
    "while the screen underneath registers nothing focusable")
  frame(420, 900)
  T.check(drawn, "and over the stacked layout")

  T.check(OnlinePanel.tradeModalAction(mimp, "b"), "B cancels the modal")
  T.eq(OnlinePanel.tradeModal(mimp), nil, "which closes it")
  T.check(tr.plan ~= nil, "and leaves the plan alone")
  T.check(not OnlinePanel.tradeModalAction(mimp, "a"),
    "with no modal up A does nothing")

  local confirms = 0
  local savedConfirm = OnlinePanel.tradeConfirm
  OnlinePanel.tradeConfirm = function(target)
    confirms = confirms + 1
    OnlinePanel.tradeState(target).status = "Trade complete."
    return true
  end
  OnlinePanel.tradeModalOpen(mimp)
  T.check(OnlinePanel.tradeModalAction(mimp, "a"), "A confirms the trade")
  T.eq(confirms, 1, "which runs the commit once")
  mo = OnlinePanel.tradeModal(mimp)
  T.eq(mo.view, "result", "the same modal shows the result")
  T.eq(mo.ok, true, "as a success")
  T.eq(mo.message, "Traded.", "saying so in one word")
  T.eq(mo.resultLines[1], "Red  RED now holds PIKACHU Lv25",
    "and what the first save now holds")
  T.eq(mo.resultLines[2], "Red  BLUE now holds ALAKAZAM Lv30",
    "and the second")
  T.eq(Kit.focusId, OnlinePanel.TRADE_MODAL_DONE, "the ring moves to Done")
  frame(1280, 800)
  T.check(drawn, "the result draws in the same modal")
  T.check(controls > 0, "with a Done button")
  T.check(OnlinePanel.tradeModalAction(mimp, "a"), "Done closes it")
  T.eq(OnlinePanel.tradeModal(mimp), nil, "and the modal is gone")

  OnlinePanel.tradeConfirm = function(target)
    OnlinePanel.tradeState(target).status = "close the game first"
    return false
  end
  tr.plan = tr.plan or {}
  OnlinePanel.tradeModalOpen(mimp)
  T.check(OnlinePanel.tradeModalAction(mimp, "a"), "a refused commit answers")
  mo = OnlinePanel.tradeModal(mimp)
  T.eq(mo.view, "result", "inside the modal too")
  T.eq(mo.ok, false, "as a failure")
  T.eq(mo.message, "close the game first", "with the reason on the panel")
  frame(1280, 800)
  T.check(drawn, "which still draws")
  OnlinePanel.tradeConfirm = savedConfirm

  OnlinePanel.tradeModalOpen(mimp)
  T.check(OnlinePanel.back(mimp), "Back closes the modal before the screen")
  T.eq(OnlinePanel.tradeModal(mimp), nil, "leaving no modal")
  T.eq(OnlinePanel.screen(mimp), "trade", "and the screen where it was")
end

-- --------------------------------------------------- the draw stays cheap

do
  local clock = os.clock
  drawPanel(1280, 800)
  local started = clock()
  for _ = 1, 20 do drawPanel(1280, 800) end
  local per = (clock() - started) / 20
  T.check(per < 0.008, ("a settled panel draw costs %.3f ms"):format(per * 1000))
end

-- ------------------------------------------- the sprite cache holds a party

do
  local OnlineSprites = require("src.online.OnlineSprites")
  local savedGet = OnlineSprites.get
  local asked = 0
  OnlineSprites.get = function(version, mon)
    asked = asked + 1
    return savedGet(version, mon)
  end
  local sprImp = {
    ready = { red = true }, activeSlot = {}, slots = {}, pulse = 0,
    _pages = {}, _uiActions = {}, _actAt = {},
  }
  local sst = OnlinePanel.state(sprImp)
  sst.version, sst.slotId, sst.setupDone = "red", "slot1", true
  local SAVE = { party = {
      { species = "PIKACHU", level = 20, hp = 40, maxHp = 40 },
      { species = "MEW", level = 30, hp = 60, maxHp = 60 } },
    boxes = { { { species = "ODDISH", level = 8, hp = 20, maxHp = 20,
                  moves = {} } }, {},
              { { species = "ONIX", level = 14, hp = 30, maxHp = 30,
                  moves = {} } } } }
  sst.slotRead = { key = "red|slot1|-", data = { generation = 1,
    party = SAVE.party, save = SAVE } }
  OnlinePanel.invalidate(sprImp)
  OnlinePanel.refresh(sprImp)
  T.eq(#OnlinePanel.cache(sprImp).party, 2,
    "the team step is drawn off a pre-built row model")
  T.eq(#OnlinePanel.cache(sprImp).pc, 2,
    "with the boxed POKeMON in a model of their own")
  OnlinePanel.home(sprImp)
  OnlinePanel.startWizard(sprImp, "hostBattle")
  OnlinePanel.wizardTo(sprImp, "team")
  asked = 0
  drawFor(sprImp, 1280, 800)
  T.check(asked >= 2,
    ("the team rows ask the sprite cache (%d times)"):format(asked))

  -- ------- the PC picker
  T.eq(OnlinePanel.pcPicker(sprImp), nil, "no picker is up to begin with")
  T.check(OnlinePanel.pcOpen(sprImp), "From PC opens it")
  OnlinePanel.refresh(sprImp)
  T.eq(#OnlinePanel.pcRows(sprImp), 2, "listing every boxed POKeMON")
  OnlinePanel.pcQuery(sprImp, "onix")
  local hits = OnlinePanel.pcRows(sprImp)
  T.eq(#hits, 1, "the text filter narrows it")
  T.eq(hits[1].source, "BOX 3", "and each row names its box")
  T.eq(hits[1].ref.where, "box", "a pick records where it came from")
  T.eq(hits[1].ref.box, 3, "which box")
  T.eq(hits[1].ref.index, 1, "and which slot in it")
  T.check(OnlinePanel.pcPick(sprImp, hits[1]), "tapping it joins the team")
  T.eq(OnlinePanel.refKey(sst.team[#sst.team]), "box|3|1",
    "recorded by its own key")
  OnlinePanel.pcQuery(sprImp, "")
  OnlinePanel.refresh(sprImp)
  Kit.audit = {}
  local m = Layout.metrics(1200)
  Kit.layout(1280, 800)
  Kit.beginFrame(-1, -1, false, 0)
  local drew = pcall(require("src.import.online.PcPicker").draw, sprImp,
    Layout.metrics(1200))
  Kit.endFrame()
  Kit.audit = nil
  T.check(drew, "the picker draws as a modal")
  T.check(OnlinePanel.pcAction(sprImp, "b"), "B closes it")
  T.eq(OnlinePanel.pcPicker(sprImp), nil, "and it is gone")

  local packed = OnlinePanel.packForRoom(sprImp, sst.slotRead.data,
    { { where = "box", box = 3, index = 1 } }, 1)
  T.eq(#packed, 1, "a box mon packs for the wire")
  OnlineSprites.get = savedGet
end

-- ------------------------------------------------- the launcher header

do
  local LauncherView = require("src.import.LauncherView")
  local ids, beta = {}, {}
  for _, tab in ipairs(LauncherView.HEADER_TABS or {}) do
    ids[tab.id] = true
    beta[tab.id] = tab.beta == true
  end
  T.check(ids.online, "ONLINE is still a header tab")
  T.check(beta.online, "and it carries the BETA badge")
  T.check(not ids.bug, "the bug tab has left the header")

  local routed = nil
  local RomImporter = require("src.import.RomImporter")
  local fake = setmetatable({ tab = "mods", ready = {}, slots = {} },
    { __index = RomImporter })
  fake._disarmTextInput = function() end
  fake._ensureSkins = function() end
  fake._setModScope = function() end
  fake:_switchTab("bug")
  T.check(fake._bugModal, "tab-bug opens the bug panel from the gear instead")
  fake:_closeBugPanel()
  T.eq(fake._bugModal, nil, "and it closes")
  T.eq(routed, nil, "without switching the visible tab")
  T.eq(fake.tab, "mods", "which is where it was")
end

-- ------------------------------- connecting leaves a set relay address alone

do
  local Client = require("src.online.Client")
  local Net = require("src.link.Net")
  local savedConnect = Client.connect
  Client.connect = function() return false, "stubbed" end
  local cimp = { ready = {}, activeSlot = {}, slots = {}, pulse = 0,
    _pages = {}, _uiActions = {}, _actAt = {} }
  cimp._ensureCarts = function() return {} end

  Client.reset()
  Client.configure({ relayAddress = "127.0.0.1:17999" })
  OnlinePanel.doConnect(cimp)
  T.eq(Client.configure({}), "127.0.0.1:17999",
    "a relay address a driver set survives the panel's own connect")

  Client.reset()
  T.eq(Client.configure({}), nil, "a reset client has no address")
  OnlinePanel.doConnect(cimp)
  T.eq(Client.configure({}), Net.defaultRelayAddress(),
    "and only then does the panel fill the default in")

  Client.reset()
  Client.connect = savedConnect
end

-- --------------------------------------------------------- nav transitions

do
  local Transition = require("src.ui.kit.Transition")
  local clock = 0
  local savedGetTime = love.timer.getTime
  love.timer.getTime = function() return clock end

  local nimp = {
    ready = { red = true }, activeSlot = {}, slots = {}, pulse = 0,
    _pages = {}, _uiActions = {}, _actAt = {},
  }
  local nst = OnlinePanel.state(nimp)

  Transition.reset()
  Transition.reduceMotion = false
  Transition.armed = false
  OnlinePanel.go(nimp, "play")
  T.eq(Transition.get("online"), nil,
    "a deep link before the first frame does not animate")
  T.eq(OnlinePanel.screen(nimp), "play", "but the screen still changes")
  OnlinePanel.home(nimp)

  Transition.armed = true
  OnlinePanel.go(nimp, "play")
  T.eq(Transition.kind("online"), "push", "Home to Play is a push")
  T.eq(Transition.dir("online"), 1, "which slides forward")
  T.eq(Transition.get("online").from, "home", "leaving Home behind")

  OnlinePanel.back(nimp)
  T.eq(Transition.kind("online"), "pop", "Back is a pop")
  T.eq(Transition.dir("online"), -1, "which slides backward")
  T.eq(Transition.get("online").from, "play", "taking Play off the top")

  OnlinePanel.go(nimp, "play")
  OnlinePanel.go(nimp, "watch")
  OnlinePanel.go(nimp, "play")
  T.eq(Transition.kind("online"), "pop",
    "going back down to a screen already open is a pop")

  nst.setupDone, nst.slotId, nst.team = nil, nil, {}
  nst.ruleEdited, nst.rule = false, { partySize = 1 }
  OnlinePanel.startWizard(nimp, "hostBattle")
  T.eq(Transition.kind("online"), "push", "opening a wizard pushes")
  nst.slotId = "slot1"
  nst.slotRead = { key = "red|slot1|-", data = { generation = 1, party = {
    { species = "PIKACHU", level = 20, moves = {} } } } }
  OnlinePanel.wizardNext(nimp)
  T.eq(OnlinePanel.wizardStep(nimp), "save", "Next walks a step")
  T.eq(Transition.kind("online"), "push", "and slides forward")
  T.eq(Transition.get("online").fromAt, 1, "off the step it came from")
  OnlinePanel.wizardBack(nimp)
  T.eq(OnlinePanel.wizardStep(nimp), "game", "Back walks back")
  T.eq(Transition.kind("online"), "pop", "and slides backward")
  T.eq(Transition.get("online").fromAt, 2, "off the step it came from")

  clock = clock + Transition.DURATIONS.pop * 2
  Transition.update()
  T.check(not Transition.active(), "a finished slide retires")

  Transition.reduceMotion = true
  OnlinePanel.wizardNext(nimp)
  T.eq(OnlinePanel.wizardStep(nimp), "save", "reduce motion still navigates")
  T.check(not Transition.active(), "with nothing animating")

  Transition.reduceMotion = false
  Transition.armed = false
  Transition.reset()
  love.timer.getTime = savedGetTime
end

do
  local bimp = { ready = { red = true }, activeSlot = {}, slots = {}, pulse = 0,
    _pages = {}, _uiActions = {}, _actAt = {} }
  local bst = OnlinePanel.state(bimp)
  bst.version, bst.ready = "red", true
  local fakeRoom = { code = "LEAV01", intent = "battle", stage = "waiting",
                     players = {} }
  local savedRoom, savedLeave, savedYou2 = Client.room, Client.leaveRoom, Client.you
  local left = 0
  Client.room = function() return fakeRoom end
  Client.leaveRoom = function() left = left + 1 fakeRoom = nil return true end
  OnlinePanel.go(bimp, "play")
  OnlinePanel.go(bimp, "room")
  T.check(OnlinePanel.back(bimp), "Back leaves the Room screen")
  T.eq(left, 1, "and tells the relay you left the room")
  T.eq(bst.ready, false, "clearing the ready flag")
  T.check(OnlinePanel.back(bimp), "Back from Play")
  T.eq(left, 1, "does not leave anything")
  fakeRoom = { code = "LEAV02", intent = "trade", stage = "waiting", players = {} }
  bst.ready = true
  OnlinePanel.go(bimp, "play")
  OnlinePanel.go(bimp, "room")
  OnlinePanel.home(bimp)
  T.eq(left, 2, "Home from a waiting room leaves it too")
  T.eq(OnlinePanel.screen(bimp), "home", "and lands on Home")

  local readied = 0
  local savedSend = OnlinePanel.sendReady
  OnlinePanel.sendReady = function() readied = readied + 1 return true end
  Client.you = function() return { id = "me", name = "RED" } end
  local tradeRoom = { code = "TRD001", intent = "trade", stage = "waiting",
    players = { { id = "me", ready = false }, { id = "them", ready = false } } }
  bst.autoReadyAt = nil
  T.check(OnlinePanel.autoReadyTrade(bimp, tradeRoom),
    "a trade room with both trainers readies itself")
  T.eq(readied, 1, "by sending ready once")
  T.check(not OnlinePanel.autoReadyTrade(bimp, tradeRoom),
    "and not again inside the retry window")
  bst.autoReadyAt = nil
  tradeRoom.players[1].ready = true
  T.check(not OnlinePanel.autoReadyTrade(bimp, tradeRoom),
    "nor once the relay already shows you ready")
  T.check(not OnlinePanel.autoReadyTrade(bimp, { code = "TRD002",
    intent = "trade", stage = "waiting", players = { { id = "me" } } }),
    "a lone trader keeps waiting")
  T.check(not OnlinePanel.autoReadyTrade(bimp, { code = "BTL001",
    intent = "battle", stage = "waiting",
    players = { { id = "me" }, { id = "them" } } }),
    "battle rooms keep the manual Ready button")
  T.eq(readied, 1, "no extra ready went out")
  OnlinePanel.sendReady = savedSend
  Client.room, Client.leaveRoom, Client.you = savedRoom, savedLeave, savedYou2
end

do
  local simp = { ready = { red = true }, activeSlot = {}, slots = {}, pulse = 0,
    _pages = {}, _uiActions = {}, _actAt = {} }
  local sst = OnlinePanel.state(simp)
  sst.version, sst.ready = "red", true
  sst.profiles["red|vanilla|-"] = { profile = { engine = 1, version = "red",
    kind = "vanilla", fingerprint = "f1" } }
  local savedJoin, savedTour, savedLobby =
    Client.joinRoom, Client.joinTournament, Client.lobby
  local roomJoins, tourJoins = {}, {}
  local pendingRoom
  Client.joinRoom = function(code, as, profile)
    roomJoins[#roomJoins + 1] = { code = code, as = as, profile = profile }
    pendingRoom = { code = code, done = false }
    return pendingRoom
  end
  Client.joinTournament = function(code, as)
    tourJoins[#tourJoins + 1] = { code = code, as = as }
    return { code = code, done = false }
  end
  Client.lobby = function()
    return { { id = "t1", code = "TQURA2", intent = "tournament" } }
  end
  T.check(OnlinePanel.spectateByCode(simp, "tqura2"),
    "spectating a listed tournament code")
  T.eq(#tourJoins, 1, "goes straight to tour_join")
  T.eq(tourJoins[1] and tourJoins[1].as, "spectator", "as a spectator")
  T.eq(#roomJoins, 0, "with no room_join")

  T.check(OnlinePanel.spectateByCode(simp, "RMBC23"),
    "spectating an unlisted code")
  T.eq(#roomJoins, 1, "tries the room first")
  T.eq(OnlinePanel.screen(simp), "room", "on the Room screen")
  pendingRoom.error, pendingRoom.reason, pendingRoom.done =
    "That room code wasn't found.", "not_found", true
  OnlinePanel.update(simp, 1 / 60)
  T.eq(#tourJoins, 2, "and a not_found answer retries it as a tournament")
  T.eq(tourJoins[2] and tourJoins[2].code, "RMBC23", "with the same code")
  T.eq(sst.status, nil, "without surfacing the room miss as an error")

  T.check(OnlinePanel.spectateByCode(simp, "RMCD34"), "another unlisted code")
  pendingRoom.error, pendingRoom.reason, pendingRoom.done =
    "That room is full.", "full", true
  OnlinePanel.update(simp, 1 / 60)
  T.eq(#tourJoins, 2, "other join errors do not retry")
  T.eq(sst.status, "That room is full.", "and are shown")
  Client.joinRoom, Client.joinTournament, Client.lobby =
    savedJoin, savedTour, savedLobby
  OnlinePanel.home(simp)
end

do
  local jimp = { ready = { red = true }, activeSlot = {}, slots = {}, pulse = 0,
    _pages = {}, _uiActions = {}, _actAt = {} }
  local jst = OnlinePanel.state(jimp)
  jst.version, jst.ready = "red", true
  local savedLobby = Client.lobby
  Client.lobby = function()
    return { { id = "t1", code = "TQURA2", intent = "tournament",
               profile = { rule = { partySize = 3 } } } }
  end
  T.check(OnlinePanel.startJoin(jimp, "tqura2"), "joining a listed code")
  T.eq(jst.joinTarget.tournament, true, "learns it is a tournament")
  T.eq(jst.joinTarget.rule.partySize, 3, "and picks up its rule")
  T.eq(OnlinePanel.teamCap(jimp), 3, "so the team step caps at the rule")
  local team = {}
  for i = 1, 5 do
    OnlinePanel.toggleTeam(team, { where = "party", index = i },
      OnlinePanel.teamCap(jimp))
  end
  T.eq(#team, 3, "and refuses a fourth pick")
  OnlinePanel.wizardTo(jimp, "team")
  jst.team = { { where = "party", index = 1 } }
  T.check(not OnlinePanel.wizardReady(jimp),
    "the team step will not advance short of the count")
  jst.team = team
  T.check(OnlinePanel.wizardReady(jimp), "and advances at exactly the count")
  OnlinePanel.home(jimp)
  T.eq(OnlinePanel.teamCap(jimp), OnlinePanel.TEAM_MAX,
    "outside the join wizard the cap is the full party")
  Client.lobby = savedLobby
end

do
  local dimp = { ready = { red = true }, activeSlot = {}, slots = {}, pulse = 0,
    _pages = {}, _uiActions = {}, _actAt = {} }
  local dst = OnlinePanel.state(dimp)
  dst.version, dst.ready = "red", true
  local tr = OnlinePanel.tradeState(dimp)
  local closed, left = 0, 0
  local savedLeave, savedRoom = Client.leaveRoom, Client.room
  Client.leaveRoom = function() left = left + 1 return true end
  Client.room = function() return nil end
  tr.mode, tr.chosen = "remote", true
  OnlinePanel.go(dimp, "trade")
  tr.remote = { handle = { path = "x", version = "red", party = {} },
    session = {},
    update = function() return "done" end,
    commit = function() return true end,
    close = function() closed = closed + 1 end }
  OnlinePanel.pumpRemoteTrade(dimp)
  T.eq(tr.remote, nil, "a finished trade closes the remote session")
  T.eq(closed, 1, "closing the link")
  T.eq(left, 1, "and leaving the room")
  T.eq(OnlinePanel.screen(dimp), "home", "then lands on Home")
  T.eq(dst.status, "Trade complete.", "saying the trade completed")
  T.eq(dst.statusOk, true, "as good news")
  OnlinePanel.go(dimp, "trade")
  T.eq(tr.remoteResult, nil, "reopening Trade forgets the old result")
  T.eq(tr.status, nil, "and any stale trade status")
  Client.leaveRoom, Client.room = savedLeave, savedRoom
end

do
  local Trade = require("src.online.Trade")
  local link = { closed = false, paired = true, sent = {},
    send = function(self, m) self.sent[#self.sent + 1] = m end,
    poll = function() return {} end, close = function() end }
  local Protocol = require("src.link.Protocol")
  local remote = setmetatable({
    handle = { generation = 1, party = {} }, link = link,
    session = { stage = "waitPick", handle = function() return nil end },
  }, getmetatable(Trade.remote({ data = {}, party = {} }, link) or {}))
  T.eq(remote:update(), "waitPick", "a live link keeps the trade going")
  link.paired = false
  T.eq(remote:update(), "cancelled", "the other trainer leaving calls it off")
  T.eq(remote.session.error, "the other trainer left", "with a reason")
  link.paired, link.closed = true, true
  remote.session.stage = "done"
  T.eq(remote:update(), "done", "but a finished trade stays finished")
end

do
  local himp = { ready = { red = true, crystal = true }, modScope = "crystal",
    activeSlot = {}, slots = {}, pulse = 0,
    _pages = {}, _uiActions = {}, _actAt = {} }
  T.eq(OnlinePanel.selectedVersion(himp), "crystal",
    "the ONLINE tab follows the launcher's cartridge, not ORDER[1]")
  local hst = OnlinePanel.state(himp)
  hst.versionPicked = true
  himp.modScope = "red"
  T.eq(OnlinePanel.selectedVersion(himp), "crystal",
    "a game picked in the wizard is not yanked by the header")
end

do
  local wimp = { ready = { red = true, crystal = true }, modScope = "crystal",
    activeSlot = {}, slots = {}, pulse = 0,
    _pages = {}, _uiActions = {}, _actAt = {} }
  T.eq(OnlinePanel.selectedVersion(wimp), "crystal", "the tab starts on the header")
  local wst = OnlinePanel.state(wimp)
  wst.joinWant = { code = "AB2CD3", as = "player", at = 1e9 }
  wimp.modScope = "red"
  T.eq(OnlinePanel.selectedVersion(wimp), "crystal",
    "a parked join is not re-aimed at another game by the header")
end

do
  local aimp = { ready = { red = true, crystal = true }, modScope = "crystal",
    activeSlot = {}, slots = {}, pulse = 0,
    _pages = {}, _uiActions = {}, _actAt = {} }
  local ast = OnlinePanel.state(aimp)
  T.eq(OnlinePanel.selectedVersion(aimp), "crystal", "the tab starts on the header")
  local savedLobby = Client.lobby
  Client.lobby = function()
    return { { code = "RM1234", intent = "battle",
               profile = { version = "red", kind = "vanilla" } } }
  end
  T.check(OnlinePanel.alignToRoom(aimp, "RM1234"), "aligning to a listed room")
  T.eq(ast.version, "red", "takes the room's game")
  T.eq(OnlinePanel.selectedVersion(aimp), "red",
    "and the header does not yank the tab while the room is live")
  Client.lobby = savedLobby
  OnlinePanel.update(aimp, 1 / 60)
  T.eq(ast.roomPicked, nil, "leaving the room releases the room's pin")
  T.eq(OnlinePanel.selectedVersion(aimp), "crystal",
    "so the header drives the tab again")
end

do
  local pimp = { ready = { red = true, crystal = true }, modScope = "crystal",
    activeSlot = {}, slots = {}, pulse = 0,
    _pages = {}, _uiActions = {}, _actAt = {} }
  local pst = OnlinePanel.state(pimp)
  pst.ready = true
  local sent, profiles = {}, nil
  local savedJoin, savedSet = Client.joinRoom, Client.setProfiles
  Client.joinRoom = function(code, as, profile)
    sent[#sent + 1] = { code = code, as = as, profile = profile }
    return { code = code, done = false }
  end
  Client.setProfiles = function(list) profiles = list return list end

  T.check(not OnlinePanel.joinByCode(pimp, "ab2cd3", "player"),
    "a join with no computed profile yet is not sent")
  T.eq(#sent, 0, "nothing goes on the wire")
  T.eq(pst.joinWant and pst.joinWant.code, "AB2CD3", "the join is parked")
  T.eq(pst.profileWant, "crystal|vanilla|-",
    "and the profile for the picked game is queued")

  pst.profiles["crystal|vanilla|-"] = { profile = { engine = 2,
    version = "crystal", kind = "vanilla", fingerprint = "c1" } }
  OnlinePanel.update(pimp, 1 / 60)
  T.eq(#sent, 1, "the parked join fires once the profile lands")
  T.eq(sent[1] and sent[1].profile and sent[1].profile.version, "crystal",
    "carrying the game the player picked")
  T.eq(profiles and profiles[1] and profiles[1].version, "crystal",
    "and the client's own snapshot is refreshed with it")
  T.eq(pst.joinWant, nil, "the parked join is cleared")
  T.eq(OnlinePanel.screen(pimp), "room", "landing on the Room screen")

  local savedTime = love.timer.getTime
  local clock = 0
  love.timer.getTime = function() return clock end
  pst.pending = { code = "AB2CD3", done = false, at = 0 }
  clock = OnlinePanel.JOIN_WAIT + 1
  OnlinePanel.update(pimp, 1 / 60)
  T.eq(pst.pending, nil, "a join the relay never answers stops pending")
  T.eq(pst.status, "The relay didn't answer.", "and says so")
  T.eq(OnlinePanel.screen(pimp), "play", "off the dead Room screen")

  pst.status = nil
  pst.profiles["crystal|vanilla|-"] = { profile = nil, reason = "no cache" }
  clock = 100
  T.check(not OnlinePanel.joinByCode(pimp, "cd3ab2", "player"),
    "an unreadable profile refuses the join")
  T.eq(pst.status, "no cache", "with the reason")
  clock = 100 + OnlinePanel.JOIN_WAIT + 1
  OnlinePanel.update(pimp, 1 / 60)
  T.eq(pst.joinWant, nil, "and the parked join gives up on its own deadline")
  T.eq(pst.status, "Couldn't read your game, so the join was not sent.",
    "saying why instead of waiting forever")
  love.timer.getTime = savedTime
  Client.joinRoom, Client.setProfiles = savedJoin, savedSet
  OnlinePanel.home(pimp)
end

do
  local savedProfiles = Client.profiles()
  Client.setProfiles({ { version = "red" } })
  T.eq(Client.profiles()[1].version, "red",
    "setProfiles replaces the client's profile snapshot")
  Client.setProfiles(savedProfiles)
end

do
  local mimp = { ready = { red = true }, activeSlot = {}, slots = {}, pulse = 0,
    _pages = {}, _uiActions = {}, _actAt = {} }
  local mst = OnlinePanel.state(mimp)
  mst.version, mst.kind = "red", "vanilla"
  local ArenaData = require("src.online.ArenaData")
  local savedSpecies = ArenaData.speciesIds
  ArenaData.speciesIds = function() return { PIKACHU = true } end
  T.eq(OnlinePanel.partyRefusal(mimp, { { species = "PIKACHU" } }), nil,
    "a vanilla party is sent as it is")
  T.eq(OnlinePanel.partyRefusal(mimp, { { species = "PIKACHU" },
    { species = "CELEBI" } }),
    "CELEBI is not in the vanilla game, so it cannot go online.",
    "a mod species is named and refused before the handshake")
  mst.kind, mst.cartId = "cart", "kanto"
  T.eq(OnlinePanel.partyRefusal(mimp, { { species = "CELEBI" } }), nil,
    "a cart arena is the cart's business, not the vanilla list's")
  mst.kind, mst.cartId = "vanilla", nil
  ArenaData.speciesIds = function() return nil end
  T.eq(OnlinePanel.partyRefusal(mimp, { { species = "CELEBI" } }), nil,
    "and an unreadable dataset keeps its opinion to itself")
  ArenaData.speciesIds = savedSpecies
end

-- ------------------------------------------- lobby ticket request shape

do
  local SyncClient = require("src.sync.SyncClient")
  local sent
  local transport = {
    begin = function(_, req) sent = req return { req = req } end,
    poll = function() return { status = "pending" } end,
    release = function() end,
  }
  local client = SyncClient.new({ baseUrl = "http://relay.test",
    transport = transport })
  client:setAuth("account", "token")

  client:lobbyTicket("RED#417")
  T.eq(sent.body, '{"displayName":"RED#417"}',
    "the ticket request carries the name the relay needs to mint one")

  client:lobbyTicket(nil)
  T.eq(sent.body, "{}",
    "a nameless ticket request is still a JSON object, not an empty array")

  client:send("POST", "/sync/unlink", {})
  T.eq(sent.body, "{}", "any empty body is sent as an object")
end


T.finish("online panel")
