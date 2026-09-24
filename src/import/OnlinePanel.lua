
local Kit = require("src.ui.kit.Kit")
local Theme = require("src.ui.kit.Theme")
local Transition = require("src.ui.kit.Transition")
local Strings = require("src.core.Strings")
local GameVersion = require("src.core.GameVersion")

local PAL = Theme.PAL

local EMPTY = {}

local OnlinePanel = {}

OnlinePanel.NAME_MIN = 3
OnlinePanel.NAME_MAX = 16
OnlinePanel.NOTE_MAX = 48
OnlinePanel.CODE_LEN = 6

OnlinePanel.SIZES = { 1, 2, 3, 4, 5, 6 }
OnlinePanel.FORCE_LEVELS = { false, 50, 100 }

local LEVELS = { false }
for level = 5, 100, 5 do LEVELS[#LEVELS + 1] = level end
OnlinePanel.LEVELS = LEVELS

local STAGE_TEXT = {
  waiting = "Waiting for a challenger",
  ready = "Both trainers are picking a team",
  battling = "Battle in progress",
  ended = "Match over",
}

local TOUR_STAGE_TEXT = {
  registering = "Waiting for trainers",
  running = "Bracket in progress",
  finished = "Tournament over",
}

OnlinePanel.SHOT_CLOCKS = { 3, 6, 9 }
OnlinePanel.TOUR_MAX_PLAYERS = 16

local function LV()
  return require("src.import.LauncherView")
end

local Connect = require("src.online.Connect")

OnlinePanel.sanitizeName = Connect.sanitizeName
OnlinePanel.nameValid = Connect.nameValid
OnlinePanel.threeDigits = Connect.threeDigits
OnlinePanel.defaultName = Connect.defaultName

OnlinePanel.PIN_LEN = 4

function OnlinePanel.sanitizePin(text)
  local out = {}
  for digit in tostring(text or ""):gmatch("%d") do
    out[#out + 1] = digit
    if #out >= OnlinePanel.PIN_LEN then break end
  end
  return table.concat(out)
end

function OnlinePanel.pinValid(pin)
  return type(pin) == "string" and #pin == OnlinePanel.PIN_LEN
    and pin:match("^%d%d%d%d$") ~= nil
end

function OnlinePanel.sanitizeCode(text)
  local CodeEntry = require("src.link.CodeEntry")
  local charset = CodeEntry.CHARSET
  local out = {}
  for char in tostring(text or ""):upper():gmatch(".") do
    if charset:find(char, 1, true) then
      out[#out + 1] = char
      if #out >= OnlinePanel.CODE_LEN then break end
    end
  end
  return table.concat(out)
end

function OnlinePanel.state(imp)
  local st = imp._online
  if not st then
    st = {
      version = nil, slotId = nil, cartId = nil, kind = "vanilla",
      rule = { partySize = 1, minLevel = nil, maxLevel = nil, forceLevel = nil },
      ruleEdited = false,
      ruleset = nil,
      team = {},
      note = "", tourCode = "", private = false, pin = "",
      name = nil, nameDraft = nil,
      profiles = {}, profileWant = nil, profileBusy = nil,
      slotRead = nil,
      section = "battle",
      engine = nil, converted = nil, convertWant = nil,
      trade = nil, roomCart = nil, roomCartKey = nil, cartInstall = nil,
      status = nil, statusOk = false,
      ready = false,
      list = "rooms",
      invites = {}, outgoing = nil,
      pending = nil,
      tourPlaying = true,
      tourShotClock = 6,
      tourSpectators = 8,
      wizard = nil,
      filter = "all",
    }
    imp._online = st
  end
  return st
end

function OnlinePanel.readyVersions(imp)
  local out = {}
  for _, version in ipairs(GameVersion.ORDER) do
    if imp.ready and imp.ready[version] then out[#out + 1] = version end
  end
  return out
end

function OnlinePanel.headerVersion(imp)
  local scope = type(imp) == "table" and imp.modScope or nil
  if scope and imp.ready and imp.ready[scope] then return scope end
  return nil
end

function OnlinePanel.selectedVersion(imp)
  local st = OnlinePanel.state(imp)
  local header = OnlinePanel.headerVersion(imp)
  if header and header ~= st.version and not st.versionPicked
      and not st.roomPicked and not st.wizard and not st.pending
      and not st.joinWant and not st.hadRoom then
    st.version, st.slotId, st.cartId, st.team = header, nil, nil, {}
    st.slotRead, st.ready, st.kind = nil, false, "vanilla"
    OnlinePanel.invalidate(imp)
    return st.version
  end
  if st.version and imp.ready and imp.ready[st.version] then return st.version end
  local list = OnlinePanel.readyVersions(imp)
  st.version = header or list[1]
  return st.version
end

function OnlinePanel.isGen2(version)
  return GameVersion.generation(version) == 2
end

function OnlinePanel.scopeOf(imp)
  local st = OnlinePanel.state(imp)
  if st.cartId then return "cart:" .. st.cartId end
  return OnlinePanel.selectedVersion(imp)
end

local function cartOf(imp)
  return OnlinePanel.state(imp).cartId
end

function OnlinePanel.scopeFor(version, cartId)
  if cartId then return "cart_" .. tostring(cartId) end
  return version
end

function OnlinePanel.slotsIn(imp, version, cartId)
  if not version then return {} end
  local scope = OnlinePanel.scopeFor(version, cartId)
  if type(imp) == "table" and type(imp.slots) == "table" then
    if imp.slots[scope] == nil and type(imp._ensureSlots) == "function" then
      pcall(imp._ensureSlots, imp, scope)
    end
    local rows = imp.slots[scope]
    return type(rows) == "table" and rows or {}
  end
  local SaveData = require("src.core.SaveData")
  local ok, rows
  if cartId then
    ok, rows = pcall(SaveData.listCartSlots, cartId)
  else
    ok, rows = pcall(SaveData.listSlots, version)
  end
  if not ok or type(rows) ~= "table" then return {} end
  return rows
end

function OnlinePanel.cartsIn(imp, version)
  if not version then return {} end
  if type(imp) == "table" and type(imp._ensureCarts) == "function" then
    local ok, rows = pcall(imp._ensureCarts, imp, version)
    if ok and type(rows) == "table" then return rows end
    return {}
  end
  local ok, rows = pcall(require("src.carts.CartStore").listFor, version)
  return (ok and type(rows) == "table") and rows or {}
end

function OnlinePanel.sealedCarts(imp, version)
  local out = {}
  for _, row in ipairs(OnlinePanel.cartsIn(imp, version)) do
    if row.seal == "sealed" then out[#out + 1] = row end
  end
  return out
end

function OnlinePanel.slotRows(imp)
  local version = OnlinePanel.selectedVersion(imp)
  if not version then return {} end
  return OnlinePanel.slotsIn(imp, version, cartOf(imp))
end

function OnlinePanel.trainerNameFor(imp, version)
  if not version then return nil end
  local SaveData = require("src.core.SaveData")
  local ok, rows = pcall(SaveData.listSlots, version)
  if not ok or type(rows) ~= "table" then return nil end
  local active = imp.activeSlot and imp.activeSlot[version] or nil
  for _, row in ipairs(rows) do
    if row.exists and (active == nil or row.id == active) then
      if row.name and row.name ~= "" then return row.name end
    end
  end
  for _, row in ipairs(rows) do
    if row.name and row.name ~= "" then return row.name end
  end
  return nil
end

OnlinePanel.storedName = Connect.storedName
OnlinePanel.persistName = Connect.persistName
OnlinePanel.linked = Connect.linked

function OnlinePanel.ensureName(imp)
  local st = OnlinePanel.state(imp)
  local known = Connect.name()
  if known then
    st.name = known
    return known
  end
  local version = OnlinePanel.selectedVersion(imp)
  st.name = Connect.ensureName(function()
    return OnlinePanel.trainerNameFor(imp, version)
  end, version)
  return st.name
end

function OnlinePanel.setName(imp, text)
  local st = OnlinePanel.state(imp)
  local ok, why = Connect.setName(text,
    { syncClient = OnlinePanel.syncClient(imp) })
  if not ok then
    st.status = why
    st.statusOk = false
    return false, "name too short"
  end
  st.name = Connect.name()
  return true
end

function OnlinePanel.syncClient(imp)
  local engine = type(imp) == "table" and imp._syncEngine and imp:_syncEngine()
    or nil
  if engine and engine.client then return engine.client end
  return nil
end

function OnlinePanel.profileKey(version, kind, cartId)
  return tostring(version) .. "|" .. tostring(kind or "vanilla")
    .. "|" .. tostring(cartId or "-")
end

local function copyRule(rule)
  return { partySize = rule.partySize, minLevel = rule.minLevel,
           maxLevel = rule.maxLevel, forceLevel = rule.forceLevel }
end

-- ------------------------------------------------- room engine (Time Capsule)

function OnlinePanel.installedGenerations(imp)
  local out, order = {}, {}
  for _, version in ipairs(OnlinePanel.readyVersions(imp)) do
    local generation = GameVersion.generation(version)
    if not out[generation] then
      out[generation] = true
      order[#order + 1] = generation
    end
  end
  table.sort(order)
  return order, out
end

function OnlinePanel.engineVersionFor(imp, generation)
  for _, version in ipairs(OnlinePanel.readyVersions(imp)) do
    if GameVersion.generation(version) == generation then return version end
  end
  return nil
end

function OnlinePanel.saveGeneration(imp)
  local version = OnlinePanel.selectedVersion(imp)
  if not version then return 1 end
  return GameVersion.generation(version)
end

function OnlinePanel.roomEngine(imp)
  local st = OnlinePanel.state(imp)
  local want = tonumber(st.engine)
  if want ~= 1 and want ~= 2 then return OnlinePanel.saveGeneration(imp) end
  if not OnlinePanel.engineVersionFor(imp, want) then
    return OnlinePanel.saveGeneration(imp)
  end
  return want
end

function OnlinePanel.engineVersion(imp)
  local engine = OnlinePanel.roomEngine(imp)
  local version = OnlinePanel.selectedVersion(imp)
  if version and GameVersion.generation(version) == engine then return version end
  return OnlinePanel.engineVersionFor(imp, engine)
end

function OnlinePanel.crossGen(imp)
  local version = OnlinePanel.selectedVersion(imp)
  if not version then return false end
  return GameVersion.generation(version) ~= OnlinePanel.roomEngine(imp)
end

function OnlinePanel.setEngine(imp, generation)
  local st = OnlinePanel.state(imp)
  if generation ~= nil and not OnlinePanel.engineVersionFor(imp, generation) then
    st.status, st.statusOk =
      Strings("That generation is not imported yet."), false
    return false
  end
  st.engine = generation
  st.team, st.ready = {}, false
  st.converted, st.convertWant = nil, nil
  return true
end

OnlinePanel.G3_FORMATS = {
  { id = "g3_single", label = "Single battle",
    note = "One POKéMON out on each side." },
  { id = "g3_double", label = "Double battle",
    note = "Two POKéMON out on each side. Bring at least 2." },
  { id = "g3_multi", label = "Multi battle",
    note = "Four trainers in two teams of two. Each brings 3 POKéMON." },
}

OnlinePanel.FORMAT_TEXT = {
  g3_single = "Single battle", g3_double = "Double battle",
  g3_multi = "Multi battle", g3_link = "Trade",
}

OnlinePanel.TOUR_FORMATS = { g3_single = true, g3_double = true }
OnlinePanel.MULTI_TEAM = 3
OnlinePanel.DOUBLE_MIN = 2
OnlinePanel.TRADE_RULESET = "g3_link"

function OnlinePanel.formatKnown(id)
  for _, row in ipairs(OnlinePanel.G3_FORMATS) do
    if row.id == id then return true end
  end
  return false
end

function OnlinePanel.isGen3(imp)
  return OnlinePanel.roomEngine(imp) == 3
end

function OnlinePanel.ruleset(imp)
  if not OnlinePanel.isGen3(imp) then return nil end
  local st = OnlinePanel.state(imp)
  if OnlinePanel.formatKnown(st.ruleset) then return st.ruleset end
  return "g3_single"
end

function OnlinePanel.setRuleset(imp, id)
  if not OnlinePanel.formatKnown(id) then return false end
  local st = OnlinePanel.state(imp)
  if st.ruleset == id then return true end
  st.ruleset = id
  st.ready = false
  if id == "g3_multi" then
    while #(st.team or {}) > OnlinePanel.MULTI_TEAM do table.remove(st.team) end
  end
  OnlinePanel.invalidate(imp, "party", "summary")
  return true
end

local function variant(hit, ruleset, rule)
  hit.variants = hit.variants or {}
  local v = hit.variants[ruleset]
  if not v then
    local ArenaData = require("src.online.ArenaData")
    local ok, copy = pcall(ArenaData.withRuleset, hit.profile, ruleset)
    if not ok or type(copy) ~= "table" then return hit.profile end
    v = copy
    hit.variants[ruleset] = v
  end
  v.rule = copyRule(rule)
  return v
end

function OnlinePanel.myProfile(imp)
  local st = OnlinePanel.state(imp)
  local version = OnlinePanel.engineVersion(imp)
  if not version then return nil, Strings("Import a game first.") end
  local cross = OnlinePanel.crossGen(imp)
  local kind = cross and "vanilla" or st.kind
  local cartId = st.cartId
  if cross then cartId = nil end
  local key = OnlinePanel.profileKey(version, kind, cartId)
  local hit = st.profiles[key]
  if not hit then
    st.profileWant = key
    return nil, nil
  end
  if not hit.profile then return nil, hit.reason end
  hit.profile.rule = copyRule(st.rule)
  local ruleset = OnlinePanel.ruleset(imp)
  if ruleset == "g3_multi" then hit.profile.rule.partySize = OnlinePanel.MULTI_TEAM end
  if ruleset and hit.profile.rulesetId ~= ruleset then
    return variant(hit, ruleset, hit.profile.rule)
  end
  return hit.profile
end

function OnlinePanel.profileFor(imp, rulesetId)
  local profile, reason = OnlinePanel.myProfile(imp)
  if not profile then return nil, reason end
  if tonumber(profile.engine) ~= 3 or type(rulesetId) ~= "string"
      or profile.rulesetId == rulesetId then
    return profile
  end
  local st = OnlinePanel.state(imp)
  local hit = st.profiles[OnlinePanel.profileKeyFor(imp) or ""]
  if not hit or not hit.profile then return profile end
  return variant(hit, rulesetId, profile.rule)
end

function OnlinePanel.tradeProfile(imp)
  if OnlinePanel.isGen3(imp) then
    return OnlinePanel.profileFor(imp, OnlinePanel.TRADE_RULESET)
  end
  return OnlinePanel.myProfile(imp)
end

-- pokefirered/src/pokemon.c:3769
function OnlinePanel.formatMismatch(imp, ruleset)
  local st = OnlinePanel.state(imp)
  local n = #(st.team or {})
  if ruleset == "g3_double" and n < OnlinePanel.DOUBLE_MIN then
    return Strings("A double battle needs at least %d POKéMON.",
      OnlinePanel.DOUBLE_MIN)
  end
  -- pokefirered/data/scripts/cable_club.inc:592
  if ruleset == "g3_multi" and n ~= OnlinePanel.MULTI_TEAM then
    return Strings("A multi battle needs exactly %d POKéMON.",
      OnlinePanel.MULTI_TEAM)
  end
  return nil
end

function OnlinePanel.computeProfile(imp, key)
  local st = OnlinePanel.state(imp)
  local version, kind, cartId = key:match("^([^|]*)|([^|]*)|(.*)$")
  if cartId == "-" then cartId = nil end
  local ArenaData = require("src.online.ArenaData")
  local ok, profile, reason = pcall(ArenaData.profile, version, kind, cartId,
    st.rule)
  if not ok then
    st.profiles[key] = { profile = nil, reason = tostring(profile) }
  else
    st.profiles[key] = { profile = profile, reason = reason }
  end
  st.profilesRev = (st.profilesRev or 0) + 1
  st.profileWant = nil
  return st.profiles[key]
end

function OnlinePanel.readTeamSlot(imp)
  local st = OnlinePanel.state(imp)
  local version = OnlinePanel.selectedVersion(imp)
  if not version or not st.slotId then return nil, Strings("Pick a save first.") end
  local key = table.concat({ version, st.slotId, st.cartId or "-" }, "|")
  if st.slotRead and st.slotRead.key == key then
    return st.slotRead.data, st.slotRead.reason
  end
  local TeamPick = require("src.online.TeamPick")
  local ok, data, reason = pcall(TeamPick.readSlot, version, st.slotId, st.cartId)
  if not ok then data, reason = nil, tostring(data) end
  st.slotRead = { key = key, data = data, reason = reason }
  return data, reason
end

OnlinePanel.TEAM_MAX = 6

local function TeamPickMod()
  return require("src.online.TeamPick")
end

function OnlinePanel.refKey(ref)
  return TeamPickMod().refKey(ref)
end

local function asRef(ref)
  if type(ref) == "number" then return { where = "party", index = ref } end
  return ref
end

OnlinePanel.asRef = asRef

function OnlinePanel.toggleTeam(team, ref, maxSize)
  if type(team) ~= "table" then return {} end
  ref = asRef(ref)
  if type(ref) ~= "table" then return team end
  local key = OnlinePanel.refKey(ref)
  for i = 1, #team do
    if OnlinePanel.refKey(team[i]) == key then
      table.remove(team, i)
      return team
    end
  end
  local cap = tonumber(maxSize) or OnlinePanel.TEAM_MAX
  if cap > OnlinePanel.TEAM_MAX then cap = OnlinePanel.TEAM_MAX end
  if #team >= cap then return team end
  team[#team + 1] = ref
  return team
end

function OnlinePanel.teamOrder(team, ref)
  local key = OnlinePanel.refKey(asRef(ref))
  for i = 1, #(team or {}) do
    if OnlinePanel.refKey(team[i]) == key then return i end
  end
  return nil
end

function OnlinePanel.teamHasBox(team)
  for _, ref in ipairs(team or {}) do
    if type(ref) == "table" and ref.where == "box" then return true end
  end
  return false
end

function OnlinePanel.teamIndices(team)
  local out = {}
  for _, ref in ipairs(team or {}) do
    local r = asRef(ref)
    if type(r) ~= "table" or r.where == "box" then return nil end
    out[#out + 1] = tonumber(r.index)
  end
  if #out == 0 then return nil end
  return out
end

function OnlinePanel.validateTeam(imp)
  local st = OnlinePanel.state(imp)
  local pick, reason = OnlinePanel.readTeamSlot(imp)
  if not pick then return false, reason or Strings("Pick a save first.") end
  local TeamPick = TeamPickMod()
  local free = { minLevel = nil, maxLevel = nil, forceLevel = st.rule.forceLevel,
                 partySize = #(st.team or {}) }
  local ok, why = TeamPick.validate(pick, st.team, free)
  if not ok then return false, why end
  local conv = OnlinePanel.convertedTeam(imp)
  if not conv then return true end
  for _, ref in ipairs(st.team) do
    if not conv.byKey[OnlinePanel.refKey(ref)] then
      return false, Strings("One of those can't cross generations.")
    end
  end
  return true
end

function OnlinePanel.ruleFor(imp)
  local st = OnlinePanel.state(imp)
  if OnlinePanel.ruleset(imp) == "g3_multi" then
    st.rule.partySize = OnlinePanel.MULTI_TEAM
  elseif not st.ruleEdited then
    st.rule.partySize = math.max(1, #(st.team or {}))
  end
  return st.rule
end

function OnlinePanel.editRule(imp)
  local st = OnlinePanel.state(imp)
  st.ruleEdited = true
  return st.rule
end

function OnlinePanel.ruleMismatch(imp, rule, what)
  local st = OnlinePanel.state(imp)
  rule = type(rule) == "table" and rule or {}
  local team = st.team or {}
  local want = tonumber(rule.partySize)
  if want and #team ~= want then
    return Strings("%s needs %d POKéMON, you picked %d.",
      what or Strings("This room"), want, #team)
  end
  local pick = OnlinePanel.readTeamSlot(imp)
  if not pick then return nil end
  local ok, why = TeamPickMod().validate(pick, team, rule)
  if ok then return nil end
  return tostring(why):gsub("\n", " ")
end

-- ------- Time Capsule team preview

function OnlinePanel.convertParty(party, fromVersion, toVersion)
  local Trade = require("src.online.Trade")
  local TeamPick = require("src.online.TeamPick")
  local fromGen = GameVersion.generation(fromVersion)
  local toGen = GameVersion.generation(toVersion)
  if fromGen == toGen then return nil, "same generation" end
  if fromGen == 3 or toGen == 3 then return nil, TeamPick.NO_TIME_CAPSULE end
  local gen1Version = (fromGen == 1) and fromVersion or toVersion
  local gen2Version = (fromGen == 2) and fromVersion or toVersion
  local gen2Data, err = Trade.withDataset(gen2Version, function(d) return d end)
  if not gen2Data then return nil, tostring(err) end
  local out
  local ok, why = Trade.withDataset(gen1Version, function(gen1Data)
    local fromData = (fromGen == 1) and gen1Data or gen2Data
    local toData = (toGen == 1) and gen1Data or gen2Data
    local byKey, rows = TeamPick.convert(party, toGen, fromData, toData)
    out = { byKey = byKey, rows = rows, generation = toGen }
    return true
  end)
  if not ok then return nil, tostring(why) end
  return out
end

function OnlinePanel.convertKey(imp)
  local st = OnlinePanel.state(imp)
  if not OnlinePanel.crossGen(imp) then return nil end
  if not st.slotId then return nil end
  return table.concat({ OnlinePanel.selectedVersion(imp) or "-", st.slotId,
    st.cartId or "-", OnlinePanel.engineVersion(imp) or "-" }, "|")
end

function OnlinePanel.convertedTeam(imp)
  local st = OnlinePanel.state(imp)
  local key = OnlinePanel.convertKey(imp)
  if not key then
    st.converted, st.convertWant = nil, nil
    return nil
  end
  local hit = st.converted
  if hit and hit.key == key then return hit.data, hit.reason end
  st.convertWant = key
  return nil, nil
end

function OnlinePanel.computeConverted(imp, key)
  local st = OnlinePanel.state(imp)
  local pick, reason = OnlinePanel.readTeamSlot(imp)
  if not pick then
    st.converted = { key = key, data = nil, reason = reason }
    st.convertWant = nil
    return st.converted
  end
  local data, why = OnlinePanel.convertParty(pick,
    OnlinePanel.selectedVersion(imp), OnlinePanel.engineVersion(imp))
  st.converted = { key = key, data = data, reason = why }
  st.convertWant = nil
  return st.converted
end

local function convRow(imp, ref)
  local conv = OnlinePanel.convertedTeam(imp)
  if not conv then return nil end
  return (conv.rows or {})[OnlinePanel.refKey(asRef(ref))]
end

function OnlinePanel.monRefusal(imp, ref)
  local row = convRow(imp, ref)
  if not row or row.ok then return nil end
  return row.reason or "refused", row.preview
end

function OnlinePanel.monPreview(imp, ref)
  local row = convRow(imp, ref)
  return row and row.preview or nil
end

function OnlinePanel.packForRoom(imp, source, team, generation)
  local TeamPick = require("src.online.TeamPick")
  local conv = OnlinePanel.convertedTeam(imp)
  if not conv then return TeamPick.pack(source, team, generation) end
  return TeamPick.packConverted(conv.byKey, team, conv.generation)
end

local function serialise(value, out)
  local kind = type(value)
  if kind == "table" then
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    out[#out + 1] = "{"
    for _, key in ipairs(keys) do
      out[#out + 1] = tostring(key) .. "="
      serialise(value[key], out)
      out[#out + 1] = ";"
    end
    out[#out + 1] = "}"
  else
    out[#out + 1] = tostring(value)
  end
end

function OnlinePanel.partyDigest(packed)
  local Fingerprint = require("src.link.Fingerprint")
  local out = {}
  serialise(packed or {}, out)
  return Fingerprint.digest(table.concat(out))
end

function OnlinePanel.alignedProfile(theirs, mine)
  if type(theirs) ~= "table" or type(mine) ~= "table" then return mine end
  if tonumber(mine.engine) ~= 3 or tonumber(theirs.engine) ~= 3 then return mine end
  if mine.rulesetId == theirs.rulesetId then return mine end
  local out = {}
  for k, v in pairs(mine) do out[k] = v end
  out.rulesetId = theirs.rulesetId
  return out
end

function OnlinePanel.joinReason(entry, myProfile)
  if type(entry) ~= "table" then return "no listing" end
  if type(myProfile) ~= "table" then return "pick a game first" end
  myProfile = OnlinePanel.alignedProfile(entry.profile, myProfile)
  local ArenaData = require("src.online.ArenaData")
  if ArenaData.equal(entry.profile, myProfile) then return nil end
  return ArenaData.describeMismatch(entry.profile, myProfile) or "that game differs"
end

function OnlinePanel.ruleText(rule)
  rule = type(rule) == "table" and rule or {}
  local parts = { ("%d v %d"):format(rule.partySize or 6, rule.partySize or 6) }
  if rule.forceLevel then
    parts[#parts + 1] = ("all Lv%d"):format(rule.forceLevel)
  else
    if rule.minLevel then parts[#parts + 1] = ("Lv%d+"):format(rule.minLevel) end
    if rule.maxLevel then parts[#parts + 1] = ("Lv%d-"):format(rule.maxLevel) end
  end
  return table.concat(parts, ", ")
end

function OnlinePanel.formatText(profile)
  if type(profile) ~= "table" or tonumber(profile.engine) ~= 3 then return nil end
  local text = OnlinePanel.FORMAT_TEXT[tostring(profile.rulesetId)]
  return text and Strings(text) or nil
end

function OnlinePanel.arenaText(profile)
  if type(profile) ~= "table" then return "" end
  local format = OnlinePanel.formatText(profile)
  if format then return format end
  if profile.kind == "cart" and profile.cart then
    return tostring(profile.cart.id)
  end
  return "vanilla"
end

local function Client()
  return require("src.online.Client")
end

local function nowSeconds()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end

OnlinePanel.nowSeconds = nowSeconds

OnlinePanel.PROFILES_MAX = 12

local G3_EXTRA = { "g3_double", "g3_link" }

function OnlinePanel.lobbyProfiles(imp, first)
  local st = OnlinePanel.state(imp)
  local out, seen = {}, {}
  local function add(p)
    if type(p) ~= "table" or #out >= OnlinePanel.PROFILES_MAX then return end
    local key = table.concat({ tostring(p.version), tostring(p.kind),
      tostring(p.rulesetId), tostring(p.fingerprint),
      tostring(p.cart and p.cart.id) }, "|")
    if seen[key] then return end
    seen[key] = true
    out[#out + 1] = p
  end
  add(first)
  local key = st.profileWant == nil and OnlinePanel.profileKeyFor(imp) or nil
  local hit = key and st.profiles[key]
  if hit and hit.profile then add(hit.profile) end
  local ArenaData = package.loaded["src.online.ArenaData"]
  for _, version in ipairs(OnlinePanel.readyVersions(imp)) do
    local row = st.profiles[OnlinePanel.profileKey(version, "vanilla", nil)]
    if row and row.profile then
      add(row.profile)
      if tonumber(row.profile.engine) == 3 and ArenaData
          and type(ArenaData.withRuleset) == "function" then
        for _, ruleset in ipairs(G3_EXTRA) do
          local ok, copy = pcall(ArenaData.withRuleset, row.profile, ruleset)
          if ok then add(copy) end
        end
      end
    end
  end
  return out
end

function OnlinePanel.profileKeyFor(imp)
  local st = OnlinePanel.state(imp)
  local version = OnlinePanel.engineVersion(imp)
  if not version then return nil end
  local cross = OnlinePanel.crossGen(imp)
  return OnlinePanel.profileKey(version, cross and "vanilla" or st.kind,
    (not cross) and st.cartId or nil)
end

function OnlinePanel.pumpLobbyProfiles(imp)
  local st = OnlinePanel.state(imp)
  local client = Client()
  if client.state() ~= "online" then return false end
  for _, version in ipairs(OnlinePanel.readyVersions(imp)) do
    local key = OnlinePanel.profileKey(version, "vanilla", nil)
    if not st.profiles[key] then
      OnlinePanel.computeProfile(imp, key)
      return true
    end
  end
  local session = type(client.sessionId) == "function" and client.sessionId() or nil
  local seen = st.profilesSeen
  if seen and seen.rev == (st.profilesRev or 0) and seen.first == st.lastPushed
      and seen.session == session then
    return false
  end
  st.profilesSeen = { rev = st.profilesRev or 0, first = st.lastPushed,
                      session = session }
  local list = OnlinePanel.lobbyProfiles(imp, st.lastPushed)
  local parts = {}
  for i, p in ipairs(list) do
    parts[i] = tostring(p.version) .. ":" .. tostring(p.rulesetId) .. ":"
      .. tostring(p.fingerprint)
  end
  local key = table.concat(parts, ",")
  if key == st.profilesKey then return false end
  st.profilesKey = key
  if type(client.setProfiles) == "function" then pcall(client.setProfiles, list) end
  return true
end

function OnlinePanel.pushProfile(profile, imp)
  local client = Client()
  if type(client.setProfiles) ~= "function" then return false end
  local list = { profile }
  if imp and imp._online and profile then
    imp._online.lastPushed = profile
    list = OnlinePanel.lobbyProfiles(imp, profile)
    imp._online.profilesKey = nil
  end
  return client.setProfiles(profile and list or {})
end

local ensureHooks
local finishTo

function OnlinePanel.mySeatId()
  local you = Client().you()
  return type(you) == "table" and you.id or nil
end

function OnlinePanel.resultText(msg)
  if type(msg) ~= "table" then return nil end
  if msg.youWon == true then return "win" end
  local winner = msg.winnerId
  if winner == nil then winner = msg.winner end
  if winner == nil or winner == false then return "draw" end
  local me = OnlinePanel.mySeatId()
  if me == nil then return "ended" end
  if winner == me then return "win" end
  return "lose"
end

OnlinePanel.RESULT_TEXT = {
  win = "You won.", lose = "You lost.", draw = "It was a draw.",
  ended = "The match ended.", error = "The match ended early.",
}

function OnlinePanel.recordResult(result)
  if type(result) ~= "string" then return end
  OnlinePanel.lastResult = result
  local client = Client()
  if type(client.report) ~= "function" then return end
  if client.role() == "spectator" then return end
  pcall(client.report, result)
end

function OnlinePanel.noteResult(result)
  if type(result) ~= "string" then return end
  OnlinePanel.lastResult = result
end

-- -------------------------------------------------------------------- trade

local function Sprites()
  return require("src.online.OnlineSprites")
end

function OnlinePanel.primeSprites(imp)
  local st = OnlinePanel.state(imp)
  local version = OnlinePanel.selectedVersion(imp)
  local key = table.concat({ version or "-", st.slotId or "-",
    st.cartId or "-", imp._pcPicker and "pc" or "-" }, "|")
  if st.spriteKey == key then return false end
  st.spriteKey = key
  local pick = st.slotId and OnlinePanel.readTeamSlot(imp) or nil
  local keep = {}
  if version then keep[#keep + 1] = version end
  local tr = st.trade
  for _, side in ipairs({ "a", "b" }) do
    local entry = tr and tr.sides and tr.sides[side]
    if entry then keep[#keep + 1] = entry.version end
  end
  Sprites().keepOnly(keep)
  if pick then
    Sprites().prime(version, pick.party)
    if imp._pcPicker then
      local TeamPick = require("src.online.TeamPick")
      local mons = {}
      for _, row in ipairs(TeamPick.candidates(pick)) do
        if row.where == "box" then mons[#mons + 1] = row.mon end
      end
      Sprites().prime(version, mons)
    end
  end
  return true
end

local nameTables = {}

local function nameTable(version, kind)
  if version == nil then return nil end
  local key = tostring(version) .. "|" .. kind
  local hit = nameTables[key]
  if hit == nil then
    hit = false
    local path = ("data/generated/%s.lua"):format(kind)
    local bytes = Sprites().readBytes(version, path)
    local chunk = bytes and (loadstring or load)(bytes, "@" .. path)
    local ok, rows = false, nil
    if chunk then ok, rows = pcall(chunk) end
    if ok and type(rows) == "table" then
      hit = {}
      for id, row in pairs(rows) do
        if type(row) == "table" and type(row.name) == "string" then
          hit[id] = row.name
        end
      end
    end
    nameTables[key] = hit
  end
  return hit or nil
end

function OnlinePanel.resetNames()
  nameTables = {}
end

local function speciesText(version, species)
  if species == nil then return "?" end
  local names = type(species) == "string" and nameTable(version, "pokemon")
  return (names and names[species]) or tostring(species)
end

OnlinePanel.speciesText = speciesText

local function itemText(version, item)
  if item == nil then return "?" end
  local names = type(item) == "string" and nameTable(version, "items")
  return (names and names[item]) or tostring(item)
end

local function gen3Name(mon)
  if type(mon) ~= "table" or type(mon.species) ~= "number" then return nil end
  return require("src.core.game3.pokemon").savedName(mon) or "?"
end

OnlinePanel.gen3Name = gen3Name

local function monSpecies(mon, version)
  local g3 = gen3Name(mon)
  if g3 then return g3 end
  if mon.species == nil then return tostring(mon.name or "?") end
  return speciesText(version, mon.species)
end

local function monName(mon, version)
  local g3 = gen3Name(mon)
  if g3 then return g3 end
  local nick = mon.nickname
  if type(nick) == "string" and nick ~= "" then return nick end
  return monSpecies(mon, version)
end

OnlinePanel.monName = monName

local function monLabel(mon, version)
  if type(mon) ~= "table" then return "?" end
  return ("%s Lv%d"):format(monName(mon, version), tonumber(mon.level) or 0)
end

OnlinePanel.monLabel = monLabel

OnlinePanel.TRADE_STAGE_TEXT = {
  waitRecords = "Comparing POKéMON with the other game",
  waitParty = "Waiting for the other party",
  picking = "Tap the POKéMON you want to trade",
  waitPick = "Waiting for the other trainer to pick",
  confirming = "Confirm the trade",
  done = "Trade complete",
  cancelled = "The trade was called off",
  handshake = "Linking up with the other game",
  seat = "Linking up with the other game",
  waitConfirm = "Waiting for the other trainer to confirm",
  exchange = "Trading",
  commit_wait = "Saving the trade on both sides",
  committed = "Trade complete",
}

OnlinePanel.TRADE_RESULT_TEXT = {
  partner_canceled = "The other trainer called off the trade.",
  player_canceled = "The trade was called off.",
  trade_canceled = "The trade was called off.",
  both_canceled = "You both called off the trade.",
  bad_mon = "That POKéMON can't be traded.",
  partner_invalid = "That POKéMON can't be traded.",
  no_mon = "That POKéMON can't be traded.",
  digest = "The two games disagreed about the trade, so nothing changed.",
  timeout = "The other trainer didn't confirm in time, so nothing changed.",
  left = "The other trainer left, so nothing changed.",
  ["the other trainer left"] = "The other trainer left, so nothing changed.",
}

function OnlinePanel.tradeResultText(why)
  if why == nil then return nil end
  local text = OnlinePanel.TRADE_RESULT_TEXT[tostring(why)]
  if text then return Strings(text) end
  return tostring(why)
end

function OnlinePanel.remoteStageText(stage)
  local text = OnlinePanel.TRADE_STAGE_TEXT[tostring(stage)]
  return Strings(text or tostring(stage))
end

function OnlinePanel.tradeState(imp)
  local st = OnlinePanel.state(imp)
  if not st.trade then
    st.trade = {
      mode = "local",
      sides = {}, picks = {}, handles = {},
      plan = nil, lines = nil, convertLines = nil,
      status = nil, statusOk = false,
      remote = nil, remoteError = nil, remoteResult = nil,
    }
  end
  return st.trade
end

function OnlinePanel.sameSlot(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  return a.version == b.version and a.slotId == b.slotId
    and a.cartId == b.cartId
end

function OnlinePanel.tradeSlots(imp)
  local out = {}
  for _, version in ipairs(OnlinePanel.readyVersions(imp)) do
    local info = GameVersion.info(version)
    local gameName = (info and (info.launcherName or info.label)) or version
    for _, row in ipairs(OnlinePanel.slotsIn(imp, version, nil)) do
      if row.exists then
        out[#out + 1] = { version = version, slotId = row.id, cartId = nil,
          generation = GameVersion.generation(version),
          label = ("%s  %s"):format(gameName,
            tostring(row.label or row.name or row.id)) }
      end
    end
    for _, cart in ipairs(OnlinePanel.sealedCarts(imp, version)) do
      for _, row in ipairs(OnlinePanel.slotsIn(imp, version, cart.id)) do
        if row.exists and not row.sealBroken then
          out[#out + 1] = { version = version, slotId = row.id,
            cartId = cart.id, generation = GameVersion.generation(version),
            label = ("%s  %s"):format(tostring(cart.title or cart.id),
              tostring(row.label or row.name or row.id)) }
        end
      end
    end
  end
  return out
end

function OnlinePanel.tradeSideView(imp, side)
  local tr = OnlinePanel.tradeState(imp)
  local hit = tr.handles[side]
  if hit and OnlinePanel.sameSlot(hit.entry, tr.sides[side]) then return hit end
  return nil
end

function OnlinePanel.tradeOpen(imp, side)
  local tr = OnlinePanel.tradeState(imp)
  local entry = tr.sides[side]
  if type(entry) ~= "table" then
    tr.handles[side] = nil
    return nil, Strings("Pick a save on both sides.")
  end
  local Trade = require("src.online.Trade")
  local ok, handle, reason = pcall(Trade.openSlot, entry.version, entry.slotId,
    entry.cartId)
  if not ok then handle, reason = nil, tostring(handle) end
  tr.handles[side] = { entry = entry, handle = handle, reason = reason }
  if handle then Sprites().prime(entry.version, handle.party) end
  return handle, reason
end

function OnlinePanel.tradeSetSide(imp, side, entry)
  local tr = OnlinePanel.tradeState(imp)
  if side ~= "a" and side ~= "b" then return false, "unknown side" end
  local other = tr.sides[side == "a" and "b" or "a"]
  if entry and OnlinePanel.sameSlot(entry, other) then
    tr.status, tr.statusOk = Strings("Pick two different saves."), false
    return false, "same slot"
  end
  tr.sides[side] = entry
  tr.picks[side] = nil
  tr.plan, tr.lines, tr.convertLines = nil, nil, nil
  tr.handles[side] = nil
  if entry then OnlinePanel.tradeOpen(imp, side) end
  return true
end

function OnlinePanel.tradeCycleSide(imp, side, delta)
  local tr = OnlinePanel.tradeState(imp)
  local rows = OnlinePanel.tradeSlots(imp)
  if #rows == 0 then return false end
  local at = 0
  for i, row in ipairs(rows) do
    if OnlinePanel.sameSlot(row, tr.sides[side]) then at = i end
  end
  for _ = 1, #rows do
    at = ((at - 1 + (delta or 1)) % #rows) + 1
    local row = rows[at]
    if not OnlinePanel.sameSlot(row, tr.sides[side == "a" and "b" or "a"]) then
      return OnlinePanel.tradeSetSide(imp, side, row)
    end
  end
  return false
end

function OnlinePanel.tradePick(imp, side, ref)
  local tr = OnlinePanel.tradeState(imp)
  local as = asRef(ref)
  if type(as) == "table" and as.where ~= "box" then ref = tonumber(as.index) end
  local key = type(as) == "table" and OnlinePanel.refKey(as) or nil
  local had = tr.picks[side]
  if key and had and OnlinePanel.refKey(asRef(had)) == key then
    tr.picks[side] = nil
  else
    tr.picks[side] = ref
  end
  tr.plan, tr.lines, tr.convertLines = nil, nil, nil
  return tr.picks[side]
end

function OnlinePanel.tradePickKey(imp, side)
  local pick = OnlinePanel.tradeState(imp).picks[side]
  if pick == nil then return nil end
  return OnlinePanel.refKey(asRef(pick))
end

function OnlinePanel.tradeBoxName(handle, box)
  return TeamPickMod().boxName(handle.save, handle.generation, box)
end

local function boxRow(handle, entry, order)
  local mon = entry.mon
  local maxHp = tonumber(mon.maxHp or (mon.stats and mon.stats.hp)) or 0
  return {
    ref = { where = "box", box = entry.box, index = entry.index },
    key = OnlinePanel.refKey(entry),
    mon = mon, version = handle.version, where = "box",
    source = entry.source or OnlinePanel.tradeBoxName(handle, entry.box),
    order = order,
    name = monName(mon, handle.version),
    label = ("%s  Lv%d  %d/%d HP"):format(
      monSpecies(mon, handle.version), tonumber(mon.level) or 0,
      tonumber(mon.hp) or 0, maxHp),
  }
end

function OnlinePanel.tradeBoxRow(handle, ref)
  if type(handle) ~= "table" or type(ref) ~= "table" then return nil end
  local mon = TeamPickMod().monAt(handle, ref)
  if type(mon) ~= "table" then return nil end
  local row = boxRow(handle, { box = ref.box, index = ref.index, mon = mon,
    where = "box" }, 1)
  row.label = ("%s  %s"):format(OnlinePanel.monLabel(mon, handle.version),
    row.source)
  row.picked, row.pickable = true, not mon.isEgg
  return row
end

function OnlinePanel.tradeBoxRows(imp, side)
  local view = OnlinePanel.tradeSideView(imp, side)
  local handle = view and view.handle or nil
  if not handle then return {} end
  local picked = OnlinePanel.tradePickKey(imp, side)
  local out = {}
  for _, entry in ipairs(TeamPickMod().candidates(handle)) do
    if entry.where == "box" then
      local row = boxRow(handle, entry, nil)
      if row.key == picked then row.order = 1 end
      out[#out + 1] = row
    end
  end
  return out
end

function OnlinePanel.tradePcAllowed(imp, side)
  local tr = OnlinePanel.tradeState(imp)
  if tr.mode ~= "local" or tr.remote then return false end
  local view = OnlinePanel.tradeSideView(imp, side)
  local handle = view and view.handle
  -- pokefirered/src/trade.c:945
  return handle ~= nil and handle.generation ~= 3
end

function OnlinePanel.tradeMode(imp, mode)
  local tr = OnlinePanel.tradeState(imp)
  if mode ~= "local" and mode ~= "remote" then return false end
  if tr.mode == mode then return true end
  tr.mode = mode
  tr.plan, tr.lines, tr.convertLines = nil, nil, nil
  tr.status, tr.statusOk = nil, false
  return true
end

function OnlinePanel.tradeRun(imp, fn)
  local tr = OnlinePanel.tradeState(imp)
  local a = OnlinePanel.tradeSideView(imp, "a")
  local b = OnlinePanel.tradeSideView(imp, "b")
  local A, B = a and a.handle, b and b.handle
  if not A or not B then
    return nil, (a and a.reason) or (b and b.reason)
      or Strings("Pick a save on both sides.")
  end
  tr.convertLines = {}
  if A.generation == B.generation then
    local ok, out, why = pcall(fn, nil)
    if not ok then return nil, tostring(out) end
    return out, why
  end
  local Convert = require("src.online.Convert")
  local Trade = require("src.online.Trade")
  local g1 = (A.generation == 1) and A or B
  local g2 = (A.generation == 2) and A or B
  if g1.generation ~= 1 or g2.generation ~= 2 then
    return nil, Strings("Those two games can't trade.")
  end
  local gen2Data, err = Trade.withDataset(g2.version, function(d) return d end)
  if not gen2Data then return nil, tostring(err) end
  local out, why
  local ran, e = Trade.withDataset(g1.version, function(gen1Data)
    g1.data, g2.data = gen1Data, gen2Data
    out, why = fn(function(packed, fromGen, toGen)
      local fromData = (fromGen == 1) and gen1Data or gen2Data
      local toData = (toGen == 1) and gen1Data or gen2Data
      local lines, legal = Convert.preview(packed, fromGen, toGen, fromData,
        toData)
      tr.convertLines[#tr.convertLines + 1] =
        { toGen = toGen, lines = lines, ok = legal ~= false }
      if toGen == 2 then
        local mon, report = Convert.toGen2(packed, gen1Data, gen2Data)
        if mon then return mon end
        return nil, report
      end
      local mon, reason = Convert.toGen1(packed, gen2Data, gen1Data)
      if mon then return mon end
      return nil, reason
    end)
    return true
  end)
  g1.data, g2.data = nil, nil
  if not ran then return nil, tostring(e) end
  return out, why
end

local function sideVersion(side)
  return type(side) == "table" and type(side.handle) == "table"
    and side.handle.version or nil
end

local function evolveLine(side)
  local version = sideVersion(side)
  return Strings("%s evolves into %s",
    side.fromName or speciesText(version, (side.received or {}).species),
    side.evolveName or speciesText(version, side.evolveTo))
end

local function usedUpLine(plan, row)
  local name = row.itemName
  if not name then
    for _, side in ipairs(plan.sides or {}) do
      local handle = type(side) == "table" and side.handle
      if type(handle) == "table" and handle.slotId == row.slot then
        name = itemText(handle.version, row.item)
        if name ~= tostring(row.item) then break end
      end
    end
  end
  return Strings("%s is used up.", name or itemText(nil, row.item))
end

function OnlinePanel.tradeLines(plan, labels, convertLines)
  local out = {}
  if type(plan) ~= "table" then return out end
  labels = type(labels) == "table" and labels or {}
  for _, side in ipairs(plan.sides or {}) do
    local who = labels[side.role or "a"] or Strings("You")
    local version = sideVersion(side)
    out[#out + 1] = Strings("%s gives %s and gets %s", who,
      monLabel(side.sent, version),
      monLabel(side.received or side.record, version))
    if side.evolveTo then out[#out + 1] = evolveLine(side) end
  end
  for _, row in ipairs(plan.warnings or {}) do
    if row.code == "item_used" then out[#out + 1] = usedUpLine(plan, row) end
  end
  for _, row in ipairs(convertLines or {}) do
    for _, line in ipairs(row.lines or {}) do out[#out + 1] = line end
  end
  return out
end

function OnlinePanel.tradePreview(imp)
  local tr = OnlinePanel.tradeState(imp)
  tr.plan, tr.lines = nil, nil
  if not (tr.picks.a and tr.picks.b) then
    tr.status, tr.statusOk = Strings("Tap a POKéMON on each side."), false
    return false
  end
  local Trade = require("src.online.Trade")
  local a, b = OnlinePanel.tradeSideView(imp, "a"), OnlinePanel.tradeSideView(imp, "b")
  local plan, reason = OnlinePanel.tradeRun(imp, function(convert)
    return Trade.plan({ from = a.handle, to = b.handle,
      fromIndex = tr.picks.a, toIndex = tr.picks.b, convert = convert })
  end)
  if not plan then
    local said = tostring(reason or "that trade can't be made")
    for _, row in ipairs(tr.convertLines or {}) do
      if row.ok == false and row.lines and row.lines[1] then
        said = row.lines[1]
        break
      end
    end
    tr.status, tr.statusOk = said, false
    return false
  end
  tr.plan = plan
  for _, side in ipairs(plan.sides or {}) do
    local version = side.handle and side.handle.version
    Sprites().prime(version, { side.sent, side.received or side.record })
  end
  tr.lines = OnlinePanel.tradeLines(plan,
    { a = (tr.sides.a or {}).label, b = (tr.sides.b or {}).label },
    tr.convertLines)
  tr.status, tr.statusOk = Strings("Check the trade, then confirm."), true
  return true
end

function OnlinePanel.tradeConfirm(imp)
  local st = OnlinePanel.state(imp)
  local tr = OnlinePanel.tradeState(imp)
  if not tr.plan then
    tr.status, tr.statusOk = Strings("Preview the trade first."), false
    return false
  end
  local Trade = require("src.online.Trade")
  local plan = tr.plan
  local res, why = OnlinePanel.tradeRun(imp, function()
    local ok, result, backups = Trade.commit(plan)
    return { ok = ok, result = result, backups = backups }
  end)
  if type(res) ~= "table" then
    tr.status, tr.statusOk = tostring(why or "that trade didn't go through"), false
    return false
  end
  if not res.ok then
    tr.status, tr.statusOk = tostring(res.result), false
    return false
  end
  for _, side in ipairs(plan.sides or {}) do
    pcall(Trade.pruneBackups, side.handle.path, 3)
  end
  tr.plan, tr.lines, tr.convertLines = nil, nil, nil
  tr.picks = {}
  tr.handles = {}
  st.slotRead, st.converted, st.convertWant = nil, nil, nil
  OnlinePanel.tradeOpen(imp, "a")
  OnlinePanel.tradeOpen(imp, "b")
  if type(imp) == "table" and type(imp.savesChanged) == "function" then
    for _, side in ipairs({ tr.sides.a, tr.sides.b }) do
      if side then
        pcall(imp.savesChanged, imp,
          OnlinePanel.scopeFor(side.version, side.cartId))
      end
    end
  end
  tr.status, tr.statusOk = Strings("Trade complete."), true
  return true
end

-- ------- the preview / confirm modal

function OnlinePanel.tradeChangeLines(plan, convertLines)
  local out = {}
  if type(plan) ~= "table" then return out end
  for _, side in ipairs(plan.sides or {}) do
    if side.evolveTo then out[#out + 1] = evolveLine(side) end
  end
  for _, row in ipairs(plan.warnings or {}) do
    if row.code == "item_used" then out[#out + 1] = usedUpLine(plan, row) end
  end
  for _, row in ipairs(convertLines or {}) do
    for _, line in ipairs(row.lines or {}) do out[#out + 1] = line end
  end
  return out
end

function OnlinePanel.tradeResultLines(plan, labels)
  local out = {}
  if type(plan) ~= "table" then return out end
  labels = type(labels) == "table" and labels or {}
  for _, side in ipairs(plan.sides or {}) do
    local who = labels[side.role or "a"] or Strings("You")
    out[#out + 1] = Strings("%s now holds %s", who,
      monLabel(side.record or side.received, sideVersion(side)))
  end
  return out
end

local function modalSide(plan, role)
  for _, side in ipairs((plan or {}).sides or {}) do
    if side.role == role then return side end
  end
  return nil
end

function OnlinePanel.tradeModal(imp)
  return type(imp) == "table" and imp._tradeModal or nil
end

OnlinePanel.TRADE_MODAL_CANCEL = "online-trade-modal-cancel"
OnlinePanel.TRADE_MODAL_CONFIRM = "online-trade-modal-confirm"
OnlinePanel.TRADE_MODAL_DONE = "online-trade-modal-done"

function OnlinePanel.tradeModalOpen(imp)
  local tr = OnlinePanel.tradeState(imp)
  if not tr.plan then return false end
  local side = modalSide(tr.plan, "a") or (tr.plan.sides or {})[1]
  if not side then return false end
  local version = side.handle and side.handle.version
  local give, get = side.sent, side.received or side.record
  for _, row in ipairs(tr.plan.sides or {}) do
    Sprites().prime(row.handle and row.handle.version,
      { row.sent, row.received or row.record })
  end
  imp._tradeModal = {
    view = "preview",
    give = { mon = give, version = version, label = monLabel(give, version) },
    get = { mon = get, version = version, label = monLabel(get, version) },
    lines = OnlinePanel.tradeChangeLines(tr.plan, tr.convertLines),
    labels = { a = (tr.sides.a or {}).label, b = (tr.sides.b or {}).label },
    ok = false, message = nil, resultLines = nil,
  }
  Kit.setFocus(OnlinePanel.TRADE_MODAL_CANCEL)
  return true
end

function OnlinePanel.tradeModalPreview(imp)
  if not OnlinePanel.tradePreview(imp) then return false end
  return OnlinePanel.tradeModalOpen(imp)
end

function OnlinePanel.tradeModalClose(imp)
  if type(imp) ~= "table" or not imp._tradeModal then return false end
  imp._tradeModal = nil
  Kit.setFocus(nil)
  return true
end

function OnlinePanel.tradeModalConfirm(imp)
  local mo = OnlinePanel.tradeModal(imp)
  if not mo or mo.view ~= "preview" then return false end
  local tr = OnlinePanel.tradeState(imp)
  local plan = tr.plan
  local ok = OnlinePanel.tradeConfirm(imp)
  mo.view = "result"
  mo.ok = ok == true
  mo.message = ok and Strings("Traded.") or tostring(tr.status or "")
  mo.resultLines = ok and OnlinePanel.tradeResultLines(plan, mo.labels) or {}
  Kit.setFocus(OnlinePanel.TRADE_MODAL_DONE)
  return mo.ok
end

function OnlinePanel.tradeModalAction(imp, action)
  local mo = OnlinePanel.tradeModal(imp)
  if not mo then return false end
  if action == "b" then return OnlinePanel.tradeModalClose(imp) end
  if action ~= "a" then return false end
  if mo.view == "result" then return OnlinePanel.tradeModalClose(imp) end
  OnlinePanel.tradeModalConfirm(imp)
  return true
end

-- ------- remote trade

function OnlinePanel.remoteTradeRefusal(imp)
  if OnlinePanel.crossGen(imp) then
    return Strings("Both players need the same game generation for now.")
  end
  local st = OnlinePanel.state(imp)
  if not st.slotId then return Strings("Pick a save first.") end
  return nil
end

function OnlinePanel.hostTrade(imp)
  local st = OnlinePanel.state(imp)
  local tr = OnlinePanel.tradeState(imp)
  local why = OnlinePanel.remoteTradeRefusal(imp)
  if why then
    tr.status, tr.statusOk = why, false
    st.status, st.statusOk = why, false
    return false
  end
  ensureHooks()
  local profile, reason = OnlinePanel.tradeProfile(imp)
  if not profile then
    tr.status, tr.statusOk = reason or Strings("Reading your game..."), false
    st.status, st.statusOk = tr.status, false
    return false
  end
  st.pending = Client().createRoom(OnlinePanel.roomOptions(imp, "trade",
    profile, 0))
  OnlinePanel.stampPending(st.pending)
  tr.status, tr.statusOk = Strings("Waiting for the other trainer."), true
  return true
end

function OnlinePanel.joinTrade(imp, target)
  local tr = OnlinePanel.tradeState(imp)
  local why = OnlinePanel.remoteTradeRefusal(imp)
  if why then
    tr.status, tr.statusOk = why, false
    return false
  end
  target = target or tr.target
  if type(target) ~= "table" or not target.room then
    tr.status, tr.statusOk = Strings("Pick a trade to join."), false
    return false
  end
  return OnlinePanel.joinRoom(imp, target.room, "player", target.pin)
end

function OnlinePanel.beginRemoteTrade(imp, payload)
  local st = OnlinePanel.state(imp)
  local tr = OnlinePanel.tradeState(imp)
  tr.mode, tr.chosen = "remote", true
  OnlinePanel.go(imp, "trade")
  tr.remote, tr.remoteError, tr.remoteResult = nil, nil, nil
  tr.remoteDone, tr.peerPrimed = false, false
  local why = OnlinePanel.remoteTradeRefusal(imp)
  if why then
    tr.remoteError = why
    pcall(function() Client().leaveRoom() end)
    return false
  end
  local Trade = require("src.online.Trade")
  local ok, handle, reason = pcall(Trade.openSlot,
    OnlinePanel.selectedVersion(imp), st.slotId, st.cartId)
  if not ok then handle, reason = nil, tostring(handle) end
  if not handle then
    tr.remoteError = tostring(reason)
    pcall(function() Client().leaveRoom() end)
    return false
  end
  local remote, err = Trade.remote(handle, Client().roomSession(),
    { peerName = payload and payload.peerName, strict = true })
  if not remote then
    tr.remoteError = tostring(err)
    pcall(function() Client().leaveRoom() end)
    return false
  end
  tr.remote = remote
  tr.peerName = (payload and payload.peerName) or Strings("The other trainer")
  Sprites().prime(handle.version, handle.party)
  local started = pcall(function() remote:start() end)
  if not started then
    tr.remoteError = Strings("The trade didn't start.")
    OnlinePanel.endRemoteTrade(imp)
    return false
  end
  return true
end

function OnlinePanel.endRemoteTrade(imp)
  local st = OnlinePanel.state(imp)
  local tr = OnlinePanel.tradeState(imp)
  local remote = tr.remote
  tr.remote = nil
  tr.handles = {}
  st.ready, st.slotRead = false, nil
  if remote then pcall(function() remote:close() end) end
  pcall(function() Client().leaveRoom() end)
  OnlinePanel.clearPresence()
end

function OnlinePanel.remoteRows(remote)
  local mine, theirs = {}, {}
  if type(remote) ~= "table" then return mine, theirs end
  local session = remote.session
  if type(session) ~= "table" then return mine, theirs end
  local party = (type(remote.handle) == "table" and remote.handle.party) or {}
  local version = type(remote.handle) == "table" and remote.handle.version or nil
  for index, mon in ipairs(party) do
    local pickable = true
    if type(remote.canPick) == "function" then
      local ok, allowed = pcall(remote.canPick, remote, index)
      pickable = ok and allowed == true
    elseif type(session.canPick) == "function" then
      local ok, allowed = pcall(session.canPick, session, index)
      pickable = ok and allowed == true
    end
    mine[#mine + 1] = { index = index, ref = index,
      key = "party|" .. index, label = monLabel(mon, version), mon = mon,
      version = version,
      pickable = pickable, picked = session.myPick == index }
  end
  for index, mon in ipairs(session.theirParty or {}) do
    theirs[#theirs + 1] = { index = index, ref = index,
      key = "party|" .. index, label = monLabel(mon, version), mon = mon,
      version = version,
      picked = session.theirPick == index }
  end
  return mine, theirs
end

function OnlinePanel.remotePick(imp, index)
  local tr = OnlinePanel.tradeState(imp)
  if not tr.remote then return false end
  local ok, done, reason = pcall(function() return tr.remote:pick(index) end)
  if not ok then
    tr.remoteError = tostring(done)
    return false
  end
  if not done then
    tr.status, tr.statusOk = tostring(reason), false
    return false
  end
  return true
end

function OnlinePanel.remoteConfirm(imp, yes)
  local tr = OnlinePanel.tradeState(imp)
  if not tr.remote then return false end
  return (pcall(function() tr.remote:confirm(yes and true or false) end))
end

function OnlinePanel.remoteCancel(imp)
  local tr = OnlinePanel.tradeState(imp)
  local remote = tr.remote
  if not remote then return false end
  local stage = remote:stage()
  if type(remote.cancelPick) == "function"
      and (stage == "picking" or stage == "waitPick") then
    local ok, sent = pcall(remote.cancelPick, remote)
    if ok and sent then return true end
  end
  OnlinePanel.endRemoteTrade(imp)
  return true
end

function OnlinePanel.remoteNote(remote)
  if type(remote) ~= "table" then return nil end
  local why = remote.lastResult
  if why == nil then return nil end
  if remote.lastRefusal and (why == "bad_mon" or why == "partner_invalid") then
    return Strings("That POKéMON can't be traded: %s", tostring(remote.lastRefusal))
  end
  return OnlinePanel.tradeResultText(why)
end

function OnlinePanel.pumpRemoteTrade(imp, dt)
  local st = OnlinePanel.state(imp)
  local tr = st.trade
  if not tr or not tr.remote then return end
  local ok, stage = pcall(function() return tr.remote:update(dt or 0) end)
  if not ok then
    tr.remoteError = tostring(stage)
    OnlinePanel.endRemoteTrade(imp)
    return
  end
  local session = tr.remote.session
  local peerCount = session and type(session.theirParty) == "table"
    and #session.theirParty or 0
  if peerCount > 0 and tr.peerPrimed ~= peerCount then
    tr.peerPrimed = peerCount
    Sprites().prime(tr.remote.handle.version, session.theirParty)
  end
  if tr.remoteDone then return end
  if stage == "committed" then
    tr.remoteDone = true
    local result = tr.remote.commitResult or {}
    if result[1] then
      pcall(require("src.online.Trade").pruneBackups,
        tr.remote.handle.path, 3)
      tr.remoteResult = Strings("Trade complete.")
      if type(imp) == "table" and type(imp.savesChanged) == "function" then
        local entry = tr.remote.handle
        pcall(imp.savesChanged, imp, OnlinePanel.scopeFor(entry.version, entry.cartId))
      end
      OnlinePanel.endRemoteTrade(imp)
      OnlinePanel.home(imp)
      st.status, st.statusOk = tr.remoteResult, true
      return
    end
    tr.remoteResult = tostring(result[2] or Strings("The trade didn't save."))
    OnlinePanel.endRemoteTrade(imp)
  elseif stage == "cancelled" then
    tr.remoteDone = true
    tr.remoteResult = OnlinePanel.tradeResultText((tr.remote.session or {}).error)
      or Strings("The trade was called off.")
    OnlinePanel.endRemoteTrade(imp)
  end
end

-- ------- installing a room's cart

function OnlinePanel.cartNeed(profile)
  if type(profile) ~= "table" or profile.kind ~= "cart" then return nil end
  local cart = profile.cart
  if type(cart) ~= "table" or type(cart.id) ~= "string" then return nil end
  local CartStore = require("src.carts.CartStore")
  local ok, got, hash = pcall(CartStore.get, cart.id)
  if not ok or not got then
    return { id = cart.id, version = cart.version, base = profile.version,
             reason = "missing" }
  end
  if type(cart.hash) == "string" and hash ~= cart.hash then
    return { id = cart.id, version = cart.version, base = profile.version,
             reason = "hash" }
  end
  return nil
end

function OnlinePanel.installCart(imp, need)
  local st = OnlinePanel.state(imp)
  if type(need) ~= "table" then return false end
  if type(imp.installCartForOnline) ~= "function" then
    st.status, st.statusOk = Strings("This build can't install carts."), false
    return false
  end
  st.cartInstall = { id = need.id }
  local started = imp:installCartForOnline(need.id, need.base,
    function(ok, text)
      st.cartInstall = nil
      st.status, st.statusOk = tostring(text), ok == true
      st.profiles, st.profileWant = {}, nil
      st.roomCart, st.roomCartKey = nil, nil
    end)
  if not started then st.cartInstall = nil end
  return started and true or false
end

-- ------------------------------------------------------------- tournaments

function OnlinePanel.tourPlayerMap(tour)
  local out = {}
  for _, player in ipairs(type(tour) == "table" and tour.players or {}) do
    if player.id then out[player.id] = player end
  end
  return out
end

function OnlinePanel.tourName(tour, id)
  if id == nil then return nil end
  local player = OnlinePanel.tourPlayerMap(tour)[id]
  if player and player.name then return player.name end
  return tostring(id)
end

function OnlinePanel.liveMatch(tour)
  if type(tour) ~= "table" then return nil end
  for _, round in ipairs(tour.bracket or {}) do
    for _, entry in ipairs(round.matches or {}) do
      if entry.state == "live"
         or (tour.live ~= nil and entry.match == tour.live) then
        return entry, round.round
      end
    end
  end
  return nil
end

function OnlinePanel.bracketColumns(tour)
  local columns = {}
  if type(tour) ~= "table" then return columns end
  local live = OnlinePanel.liveMatch(tour)
  for _, round in ipairs(tour.bracket or {}) do
    local column = { round = round.round or (#columns + 1), matches = {} }
    for _, entry in ipairs(round.matches or {}) do
      column.matches[#column.matches + 1] = {
        match = entry.match,
        a = entry.a, b = entry.b,
        aName = OnlinePanel.tourName(tour, entry.a),
        bName = OnlinePanel.tourName(tour, entry.b),
        winner = entry.winner,
        winnerName = OnlinePanel.tourName(tour, entry.winner),
        how = entry.how,
        state = entry.state or "pending",
        bye = entry.state == "bye" or (entry.a ~= nil and entry.b == nil),
        live = live ~= nil and entry.match ~= nil and entry.match == live.match,
      }
    end
    columns[#columns + 1] = column
  end
  table.sort(columns, function(a, b) return (a.round or 0) < (b.round or 0) end)
  return columns
end

function OnlinePanel.matchText(entry)
  if type(entry) ~= "table" then return "" end
  if entry.bye and not entry.b then
    return ("%s  bye"):format(tostring(entry.aName or "?"))
  end
  return ("%s vs %s"):format(tostring(entry.aName or "?"),
                             tostring(entry.bName or "?"))
end

function OnlinePanel.bannerText(tour, myId)
  if type(tour) ~= "table" then return nil end
  local live = OnlinePanel.liveMatch(tour)
  if live then
    if myId ~= nil and (live.a == myId or live.b == myId) then
      return Strings("You play next")
    end
    local a = OnlinePanel.tourName(tour, live.a) or "?"
    local b = OnlinePanel.tourName(tour, live.b) or "?"
    return Strings("Watching: %s vs %s", a, b)
  end
  if tour.stage == "finished" then
    local champion = tour.championName
      or OnlinePanel.tourName(tour, tour.champion)
    if champion then return Strings("Champion: %s", champion) end
    return Strings("Tournament over")
  end
  return nil
end

function OnlinePanel.creatorControls(tour, myId)
  local out = { isCreator = false, canStart = false, canKick = false,
                canClose = false, players = 0 }
  if type(tour) ~= "table" then return out end
  out.players = #(tour.players or {})
  out.isCreator = myId ~= nil and tour.creator == myId
  if not out.isCreator then return out end
  out.canStart = tour.stage == "registering" and out.players >= 2
  out.canKick = tour.stage ~= "finished"
  out.canClose = true
  return out
end

function OnlinePanel.countdown(at, nowMs)
  if type(at) ~= "number" or type(nowMs) ~= "number" then return nil end
  return math.max(0, math.floor((at - nowMs) / 1000 + 0.5))
end

function OnlinePanel.tourDeadline(tour)
  if type(tour) ~= "table" then return nil end
  local deadlines = tour.deadlines or {}
  local at = deadlines.shot or deadlines.result or deadlines.ready
  if type(at) ~= "number" then return nil end
  return OnlinePanel.countdown(at, Client().serverTime() or 0)
end

function OnlinePanel.packTeam(imp)
  local st = OnlinePanel.state(imp)
  local pick, reason = OnlinePanel.readTeamSlot(imp)
  if not pick then return nil, nil, reason or Strings("Pick a save first.") end
  local TeamPick = require("src.online.TeamPick")
  local ok, why = TeamPick.validate(pick, st.team, OnlinePanel.ruleFor(imp))
  if not ok then return nil, nil, why end
  local packed, packErr =
    OnlinePanel.packForRoom(imp, pick, st.team, pick.generation)
  if not packed then return nil, nil, packErr end
  return packed, OnlinePanel.partyDigest(packed)
end

function OnlinePanel.hostTournament(imp)
  local st = OnlinePanel.state(imp)
  ensureHooks()
  local ruleset = OnlinePanel.ruleset(imp)
  if ruleset and not OnlinePanel.TOUR_FORMATS[ruleset] then
    st.status, st.statusOk =
      Strings("Multi battles can't be played in a tournament."), false
    return false
  end
  local rule = OnlinePanel.ruleFor(imp)
  local profile, reason = OnlinePanel.myProfile(imp)
  if not profile then
    st.status, st.statusOk = reason or Strings("Reading your game..."), false
    return false
  end
  local packed, digest
  if st.tourPlaying ~= false then
    local why = OnlinePanel.ruleMismatch(imp, rule, Strings("Your rule"))
      or OnlinePanel.formatMismatch(imp, ruleset)
    if why then
      st.status, st.statusOk = why, false
      return false
    end
    packed, digest, why = OnlinePanel.packTeam(imp)
    if not packed then
      st.status, st.statusOk = why, false
      return false
    end
  end
  st.setupDone = true
  st.pending = Client().createTournament({
    profile = profile,
    rule = copyRule(rule),
    playing = st.tourPlaying ~= false,
    shotClock = st.tourShotClock,
    maxSpectators = tonumber(st.tourSpectators) or 0,
    party = packed,
    partyDigest = digest,
    public = st.tourPublic ~= false,
  })
  OnlinePanel.stampPending(st.pending)
  finishTo(imp, "tournament")
  return true
end

function OnlinePanel.tourTarget(target)
  if type(target) == "string" then
    local code = OnlinePanel.sanitizeCode(target)
    if #code == OnlinePanel.CODE_LEN then return { code = code } end
    return nil
  end
  if type(target) ~= "table" then return nil end
  if type(target.tour) == "string" and target.tour ~= "" then
    return { tour = target.tour }
  end
  if type(target.code) == "string" then
    local code = OnlinePanel.sanitizeCode(target.code)
    if #code == OnlinePanel.CODE_LEN then return { code = code } end
  end
  return nil
end

function OnlinePanel.joinTournament(imp, target, as)
  local st = OnlinePanel.state(imp)
  local want = OnlinePanel.tourTarget(target)
  if not want then
    st.status, st.statusOk = Strings("Tournament codes are 6 characters."), false
    return false
  end
  ensureHooks()
  local current = OnlinePanel.ruleset(imp)
  if current and not OnlinePanel.TOUR_FORMATS[current] then
    OnlinePanel.setRuleset(imp, "g3_single")
  end
  local listed = want.tour and OnlinePanel.findEntry("tour", want.tour) or nil
  local listedProfile = listed and listed.profile or nil
  if type(listedProfile) == "table" and OnlinePanel.formatKnown(listedProfile.rulesetId)
      and OnlinePanel.isGen3(imp) then
    OnlinePanel.setRuleset(imp, listedProfile.rulesetId)
  end
  local packed, digest
  if as ~= "spectator" then
    local why = OnlinePanel.formatMismatch(imp, OnlinePanel.ruleset(imp))
    if why then
      st.status, st.statusOk = why, false
      return false
    end
    packed, digest, why = OnlinePanel.packTeam(imp)
    if not packed then
      st.status, st.statusOk = why, false
      return false
    end
  end
  local profile = OnlinePanel.myProfile(imp)
  if type(listedProfile) == "table" and OnlinePanel.formatKnown(listedProfile.rulesetId) then
    profile = OnlinePanel.profileFor(imp, listedProfile.rulesetId) or profile
  end
  st.pending = Client().joinTournament({ tour = want.tour, code = want.code,
    as = as or "player", party = packed, partyDigest = digest,
    profile = profile })
  OnlinePanel.stampPending(st.pending)
  if type(st.pending) == "table" then
    st.pending.tourTarget = want
    st.pending.tourAs = as or "player"
    st.pending.tourRuleset = profile and profile.rulesetId or nil
  end
  return true
end

function OnlinePanel.retryTourRuleset(imp, pending)
  if type(pending) ~= "table" or not pending.tourTarget then return false end
  if pending.reason ~= "profile_mismatch" or pending.field ~= "rulesetId" then
    return false
  end
  if pending.tourRetried then return false end
  local tried = pending.tourRuleset
  if not OnlinePanel.TOUR_FORMATS[tostring(tried)] then return false end
  local other = tried == "g3_single" and "g3_double" or "g3_single"
  local st = OnlinePanel.state(imp)
  OnlinePanel.setRuleset(imp, other)
  local ok = OnlinePanel.joinTournament(imp, pending.tourTarget, pending.tourAs)
  if ok and st.pending then st.pending.tourRetried = true end
  return ok
end

function OnlinePanel.leaveTournament(imp)
  local st = OnlinePanel.state(imp)
  st.ready = false
  Client().leaveTournament()
  OnlinePanel.clearPresence()
  return true
end

ensureHooks = function()
  if OnlinePanel._hooked then return end
  OnlinePanel._hooked = true
  local client = Client()
  OnlinePanel._lobbyRev = 0
  client.on("lobby", function()
    OnlinePanel._lobbyRev = (OnlinePanel._lobbyRev or 0) + 1
  end)
  client.on("state", function()
    OnlinePanel._lobbyRev = (OnlinePanel._lobbyRev or 0) + 1
  end)
  client.on("match_start", function(payload)
    OnlinePanel._pendingStart = payload
  end)
  client.on("match_end", function(msg)
    local room = client.room()
    if room and room.intent == "trade" then return end
    OnlinePanel.lastResult = OnlinePanel.resultText(msg)
  end)
  client.on("tour_match", function(payload)
    OnlinePanel.tourNotice = Strings("You play next")
    OnlinePanel._tourMatch = payload
  end)
  client.on("tour_spectate", function(payload)
    OnlinePanel.tourNotice = nil
    OnlinePanel._tourMatch = payload
  end)
  client.on("tour_bye", function()
    OnlinePanel.tourNotice = Strings("You have a bye this round.")
  end)
  client.on("error", function(e)
    if type(e) ~= "table" then return end
    if e.scope == "tournament" then
      OnlinePanel.tourNotice = e.text
      OnlinePanel._tourClosed = e.text
    elseif e.scope == "room" and e.reason == "resume_incomplete" then
      OnlinePanel._roomLost = Strings("Connection lost, left the room.")
    elseif e.scope == "join" and e.reason ~= "bad_pin"
        and e.reason ~= "pin_required" and e.reason ~= "pin_locked" then
      OnlinePanel._joinError = e.text
    end
  end)
  client.on("tour_over", function(payload)
    OnlinePanel.tourNotice = payload.champion
      and Strings("Champion: %s", tostring(payload.champion))
      or Strings("Tournament over")
  end)
  client.on("invite_in", function(msg)
    local q = OnlinePanel._events
    q[#q + 1] = { kind = "in", msg = msg }
  end)
  client.on("invite_closed", function(msg)
    local q = OnlinePanel._events
    q[#q + 1] = { kind = "closed", msg = msg }
  end)
  client.on("invite_token", function(msg)
    local have = OnlinePanel._tokenFor
    if type(msg) == "table" and have and have.room == msg.room then
      have.token = msg.token
      have.expiresAt = tonumber(msg.expiresAt)
    end
  end)
end

OnlinePanel._events = {}

function OnlinePanel.drainEvents(imp)
  local q = OnlinePanel._events
  if #q == 0 then return end
  OnlinePanel._events = {}
  for _, ev in ipairs(q) do
    if ev.kind == "in" then
      OnlinePanel.inviteIn(imp, ev.msg)
    elseif ev.kind == "closed" then
      OnlinePanel.inviteClosed(imp, ev.msg)
    end
  end
end

function OnlinePanel.connectOptions(imp)
  local version = OnlinePanel.selectedVersion(imp)
  return {
    source = "launcher",
    version = version,
    trainerName = function() return OnlinePanel.trainerNameFor(imp, version) end,
    profiles = OnlinePanel.lobbyProfiles(imp),
    presence = { where = "launcher", status = "idle",
                 version = version or "" },
    relayAddress = OnlinePanel.relayAddress,
    syncClient = OnlinePanel.syncClient(imp),
  }
end

function OnlinePanel.doConnect(imp)
  local st = OnlinePanel.state(imp)
  OnlinePanel.ensureName(imp)
  local ok, err = Connect.doConnect(OnlinePanel.connectOptions(imp))
  if not ok then
    st.status = tostring(err or "the relay didn't answer")
    st.statusOk = false
  else
    st.status, st.statusOk = nil, false
  end
  return ok
end

function OnlinePanel.connect(imp)
  local st = OnlinePanel.state(imp)
  ensureHooks()
  OnlinePanel.ensureName(imp)
  OnlinePanel.armDiscord()
  local ok, err = Connect.start(OnlinePanel.connectOptions(imp))
  if not ok then
    st.status = tostring(err or "the relay didn't answer")
    st.statusOk = false
  else
    st.status, st.statusOk = nil, false
  end
  return ok
end

function OnlinePanel.disconnect(imp)
  local st = OnlinePanel.state(imp)
  st.ready = false
  Connect.disconnect()
  OnlinePanel.clearPresence()
end

local function Presence()
  local ok, mod = pcall(require, "src.core.DiscordPresence")
  if ok and type(mod) == "table" then return mod end
  return nil
end

function OnlinePanel.armDiscord()
  local presence = Presence()
  if not presence then return false end
  presence.joinHandler = function(token)
    OnlinePanel._discordInvite = token
    return true
  end
  if type(presence.ensureLauncher) == "function" then
    pcall(presence.ensureLauncher)
  end
  return true
end

function OnlinePanel.clearPresence()
  OnlinePanel._presenceKey = nil
  OnlinePanel._tokenFor = nil
  local presence = Presence()
  if presence and type(presence.setJoinSecret) == "function" then
    pcall(presence.setJoinSecret, nil)
  end
end

OnlinePanel.TOKEN_MARGIN = 60000

function OnlinePanel.wantToken(roomId)
  local have = OnlinePanel._tokenFor
  if have and have.room == roomId then
    if have.token == nil then return false end
    local now = Client().serverTime() or 0
    if (have.expiresAt or 0) - now > OnlinePanel.TOKEN_MARGIN then return false end
  end
  local client = Client()
  if type(client.inviteToken) ~= "function" then return false end
  OnlinePanel._tokenFor = { room = roomId, token = nil }
  pcall(client.inviteToken, roomId)
  return true
end

function OnlinePanel.pushPresence(room)
  local players = #(room.players or {})
  local seats = tonumber(room.seats) or 2
  local open = players < seats and (room.stage == "waiting"
    or room.stage == "ready")
  if not open then
    if OnlinePanel._presenceKey ~= nil then OnlinePanel.clearPresence() end
    return
  end
  local live = Presence()
  if not (live and type(live.enabled) == "function" and live.enabled()) then
    return
  end
  OnlinePanel.wantToken(room.room)
  local have = OnlinePanel._tokenFor
  local token = have and have.room == room.room and have.token or nil
  local key = tostring(token) .. "/" .. players .. "/" .. seats
  if OnlinePanel._presenceKey == key then return end
  local presence = Presence()
  if not presence or type(presence.setJoinSecret) ~= "function" then return end
  OnlinePanel._presenceKey = key
  pcall(presence.setJoinSecret, token, players, seats)
end

function OnlinePanel.partyRefusal(imp, packed)
  local st = OnlinePanel.state(imp)
  if st.kind == "cart" or st.cartId then return nil end
  if OnlinePanel.isGen3(imp) then return nil end
  local version = OnlinePanel.engineVersion(imp)
  if not version then return nil end
  local ok, known = pcall(function()
    return require("src.online.ArenaData").speciesIds(version)
  end)
  if not ok or type(known) ~= "table" then return nil end
  for _, mon in ipairs(packed or {}) do
    local id = type(mon) == "table" and mon.species or nil
    if id and not known[id] then
      return Strings("%s is not in the vanilla game, so it cannot go online.",
        tostring(id))
    end
  end
  return nil
end

function OnlinePanel.sendReady(imp)
  local st = OnlinePanel.state(imp)
  local pick, reason = OnlinePanel.readTeamSlot(imp)
  if not pick then
    st.status, st.statusOk = reason or Strings("Pick a save first."), false
    return false, reason
  end
  local TeamPick = require("src.online.TeamPick")
  local packed, why
  local room = Client().room()
  if room and room.intent == "trade" then
    local all = {}
    for index = 1, #pick.party do all[index] = index end
    packed, why = TeamPick.pack(pick, all, pick.generation)
  else
    local ok
    local room2 = Client().room()
    local rule = (room2 and room2.profile and room2.profile.rule)
      or OnlinePanel.ruleFor(imp)
    ok, why = TeamPick.validate(pick, st.team, rule)
    if not ok then
      st.status, st.statusOk = why, false
      return false, why
    end
    packed, why = OnlinePanel.packForRoom(imp, pick, st.team,
      pick.generation)
  end
  if not packed then
    st.status, st.statusOk = tostring(why), false
    return false, why
  end
  local refusal = OnlinePanel.partyRefusal(imp, packed)
  if refusal then
    st.status, st.statusOk = refusal, false
    return false, refusal
  end
  Client().ready(packed, OnlinePanel.partyDigest(packed))
  st.ready = true
  st.status, st.statusOk = Strings("Ready. Waiting for the other trainer."), true
  return true
end

function OnlinePanel.unready(imp)
  local st = OnlinePanel.state(imp)
  st.ready = false
  Client().ready({}, nil)
end

function OnlinePanel.specTeam3(team, size)
  local out = {}
  for _, ref in ipairs(team or {}) do
    if #out >= size then break end
    local r = asRef(ref)
    if type(r) == "table" and r.where == "box" then
      out[#out + 1] = { where = "box", box = tonumber(r.box), index = tonumber(r.index) }
    elseif type(r) == "table" then
      out[#out + 1] = tonumber(r.index)
    end
  end
  return out
end

function OnlinePanel.buildSpec3(imp, payload, profile, opts)
  local st = OnlinePanel.state(imp)
  local client = opts.client or Client()
  local ArenaBoot = require("src.online.ArenaBoot")
  local spectating = payload.role == "spectator"
  local rule = type(profile.rule) == "table" and profile.rule or {}
  local size = math.max(1, math.min(OnlinePanel.TEAM_MAX,
    tonumber(rule.partySize) or OnlinePanel.TEAM_MAX))
  local team, myParty
  if not spectating then
    local pick, reason = OnlinePanel.readTeamSlot(imp)
    if not pick then return nil, reason or Strings("Pick a save first.") end
    if #(st.team or {}) == 0 then return nil, Strings("Pick your team first.") end
    local refs = {}
    for i = 1, math.min(#st.team, size) do refs[i] = st.team[i] end
    local packed, why = require("src.online.TeamPick").pack(pick, refs, 3)
    if not packed then return nil, why end
    myParty = packed
    team = OnlinePanel.specTeam3(refs, size)
  end
  return ArenaBoot.spec({
    profile = profile,
    role = payload.role,
    seat = (not spectating) and tonumber(payload.seat) or nil,
    seats = tonumber(payload.seats) or 2,
    slotId = (not spectating) and st.slotId or nil,
    team = team,
    myParty = myParty,
    seed = payload.seed,
    match = payload.match,
    room = payload.room,
    players = payload.players,
    session = opts.session or client.roomSession(),
    onDone = OnlinePanel.noteResult,
  })
end

function OnlinePanel.buildSpec(imp, payload, opts)
  opts = opts or {}
  local st = OnlinePanel.state(imp)
  local client = opts.client or Client()
  local ArenaBoot = require("src.online.ArenaBoot")
  local profile = payload.profile or OnlinePanel.myProfile(imp)
  if type(profile) == "table" and tonumber(profile.engine) == 3 then
    return OnlinePanel.buildSpec3(imp, payload, profile, opts)
  end
  local refs = nil
  if payload.role ~= "spectator" and #st.team > 0 then refs = st.team end
  local team, myParty = nil, nil
  if refs then
    team = OnlinePanel.teamIndices(refs)
    local cross = OnlinePanel.crossGen(imp)
    if cross or team == nil then
      local pick = OnlinePanel.readTeamSlot(imp)
      local packed, packErr = OnlinePanel.packForRoom(imp, pick or {}, refs,
        cross and nil or (pick and pick.generation))
      if not packed then
        return nil, packErr or "that team can't cross generations"
      end
      myParty = packed
    end
  end
  return ArenaBoot.spec({
    profile = profile,
    role = payload.role,
    slotId = st.slotId,
    team = team,
    myParty = myParty,
    seed = payload.seed,
    peerName = payload.peerName,
    hostName = payload.hostName,
    guestName = payload.guestName,
    theirParty = payload.theirParty,
    hostParty = payload.hostParty,
    guestParty = payload.guestParty,
    session = opts.session or client.roomSession(),
    onDone = OnlinePanel.recordResult,
  })
end
-- ------------------------------------------------------------- navigation

OnlinePanel.SCREENS = {
  home = true, play = true, wizard = true, room = true, watch = true,
  tournament = true, trade = true,
}

OnlinePanel.WIZARDS = {
  hostBattle = { title = "Host a battle", confirm = "Host the battle",
    steps = { "game", "format", "save", "team", "rules", "visibility",
              "summary" } },
  hostTournament = { title = "Host a tournament",
    confirm = "Host the tournament",
    steps = { "game", "format", "save", "playing", "team", "rules",
              "shotclock", "spectators", "tourvisibility", "summary" } },
  join = { title = "Join a battle", confirm = "Join", resume = true,
    steps = { "game", "save", "team", "summary" } },
  invite = { title = "Send an invite", confirm = "Send invite", resume = true,
    steps = { "game", "save", "team", "summary" } },
  accept = { title = "Accept an invite", confirm = "Accept", resume = true,
    steps = { "game", "save", "team", "summary" } },
  tradeRemote = { title = "Trade online", confirm = "Go",
    steps = { "game", "save", "role", "visibility", "summary" } },
}

OnlinePanel.STEP_TITLE = {
  game = "Which game?",
  save = "Which save?",
  team = "Pick your team",
  rules = "Battle rules",
  visibility = "Who can find this lobby?",
  playing = "Are you playing?",
  shotclock = "Shot clock",
  spectators = "Spectators",
  role = "Host or join?",
  tourvisibility = "Who can join?",
  format = "Which kind of battle?",
  summary = "Check this over",
}

OnlinePanel.STEP_LABEL = {
  game = "Game", format = "Battle", save = "Save", team = "Team", rules = "Rules",
  visibility = "Visibility", playing = "Playing", shotclock = "Shot clock",
  spectators = "Spectators", role = "Trade", tourvisibility = "Visibility",
}

function OnlinePanel.nav(imp)
  local st = OnlinePanel.state(imp)
  if type(st.stack) ~= "table" or #st.stack == 0 then st.stack = { "home" } end
  return st.stack
end

function OnlinePanel.screen(imp)
  local stack = OnlinePanel.nav(imp)
  return stack[#stack]
end

local function entered(imp, id)
  local st = OnlinePanel.state(imp)
  local c = OnlinePanel.cache(imp)
  imp._tradeModal = nil
  imp._pcPicker = nil
  imp._invitePicker = nil
  st.status, st.statusOk = nil, false
  st.confirmLeave = nil
  if id == "play" or id == "watch" or id == "tournament" then
    c.dirty.lobby = true
  elseif id == "trade" then
    c.dirty.trade = true
    local tr = st.trade
    if tr and not tr.remote then
      tr.status, tr.remoteResult, tr.remoteError = nil, nil, nil
    end
  elseif id == "wizard" then
    c.dirty.slots, c.dirty.party = true, true
  end
end

function OnlinePanel.go(imp, id)
  if not OnlinePanel.SCREENS[id] then return false end
  local stack = OnlinePanel.nav(imp)
  if stack[#stack] == id then return true end
  local from = stack[#stack]
  for i = 1, #stack do
    if stack[i] == id then
      for _ = #stack, i + 1, -1 do table.remove(stack) end
      Transition.start("online", "pop", { dir = -1, from = from, to = id })
      entered(imp, id)
      return true
    end
  end
  stack[#stack + 1] = id
  Transition.start("online", "push", { dir = 1, from = from, to = id })
  entered(imp, id)
  return true
end

local function leaveScreen(imp, from)
  local st = OnlinePanel.state(imp)
  local tr = st.trade
  if from == "trade" and tr and tr.remote then
    OnlinePanel.endRemoteTrade(imp)
  elseif from == "room" and Client().room() then
    st.ready, st.confirmLeave = false, nil
    Client().leaveRoom()
    OnlinePanel.clearPresence()
  end
end

function OnlinePanel.back(imp)
  local st = imp and imp._online
  if not st then return false end
  if imp._pinModal then return OnlinePanel.pinClose(imp) end
  if imp._invitePicker then return OnlinePanel.invitePickerClose(imp) end
  if imp._pcPicker then return OnlinePanel.pcClose(imp) end
  if imp._tradeModal then return OnlinePanel.tradeModalClose(imp) end
  if OnlinePanel.screen(imp) == "wizard" and st.wizard
      and (st.wizard.at or 1) > 1 then
    return OnlinePanel.wizardBack(imp)
  end
  local stack = OnlinePanel.nav(imp)
  if #stack <= 1 then return false end
  local from = table.remove(stack)
  st.wizard = nil
  Transition.start("online", "pop", { dir = -1, from = from,
    to = stack[#stack] })
  entered(imp, stack[#stack])
  leaveScreen(imp, from)
  return true
end

function OnlinePanel.home(imp)
  local st = OnlinePanel.state(imp)
  local stack = OnlinePanel.nav(imp)
  local from = stack[#stack]
  for _ = #stack, 2, -1 do table.remove(stack) end
  st.wizard = nil
  if from ~= "home" then
    Transition.start("online", "pop", { dir = -1, from = from, to = "home" })
  end
  entered(imp, "home")
  local tr = st.trade
  leaveScreen(imp, (tr and tr.remote) and "trade" or "room")
  return true
end

function OnlinePanel.setupComplete(imp)
  local st = OnlinePanel.state(imp)
  if not OnlinePanel.selectedVersion(imp) then return false end
  if not st.slotId then return false end
  if #(st.team or {}) == 0 then return false end
  return st.setupDone == true
end

-- ---------------------------------------------------------------- wizards

function OnlinePanel.wizardActivity(imp)
  local st = OnlinePanel.state(imp)
  local w = st.wizard
  if not w then return nil end
  if w.kind == "invite" and type(st.inviteTarget) == "table" then
    return st.inviteTarget.activity
  end
  if w.kind == "accept" and type(st.acceptTarget) == "table" then
    return st.acceptTarget.activity
  end
  return nil
end

function OnlinePanel.startWizard(imp, kind, opts)
  local st = OnlinePanel.state(imp)
  if not OnlinePanel.WIZARDS[kind] then return false end
  if kind == "hostTournament" and st.ruleset
      and not OnlinePanel.TOUR_FORMATS[st.ruleset] then
    st.ruleset = "g3_single"
  end
  if kind == "hostBattle" or kind == "tradeRemote" then
    st.private, st.pin = false, ""
  end
  st.wizard = { kind = kind, at = 1, show = {}, opts = opts or {} }
  st.status, st.statusOk = nil, false
  OnlinePanel.go(imp, "wizard")
  return true
end

function OnlinePanel.wizard(imp)
  local st = imp and imp._online
  return st and st.wizard or nil
end

function OnlinePanel.wizardDef(imp)
  local w = OnlinePanel.wizard(imp)
  return w and OnlinePanel.WIZARDS[w.kind] or nil
end

local function tradeJoinStep(st, id)
  return id == "visibility" and st.wizard and st.wizard.kind == "tradeRemote"
    and st.tradeRole == "join"
end

function OnlinePanel.wizardSteps(imp)
  local st = OnlinePanel.state(imp)
  local w, def = st.wizard, OnlinePanel.wizardDef(imp)
  if not w or not def then return {} end
  local out = {}
  for _, id in ipairs(def.steps) do
    local skip = false
    if tradeJoinStep(st, id) then
      skip = true
    elseif id == "format" then
      skip = not OnlinePanel.isGen3(imp)
    elseif id == "team" and OnlinePanel.wizardActivity(imp) == "trade" then
      skip = true
    elseif id == "team" and w.kind == "hostTournament"
        and st.tourPlaying == false then
      skip = true
    elseif def.resume and id ~= "summary" and not w.show[id]
        and st.setupDone == true then
      if id == "game" then skip = OnlinePanel.selectedVersion(imp) ~= nil end
      if id == "save" then skip = st.slotId ~= nil end
      if id == "team" then skip = #(st.team or {}) > 0 end
    end
    if not skip then out[#out + 1] = id end
  end
  if #out == 0 then out[1] = "summary" end
  return out
end

function OnlinePanel.wizardStep(imp)
  local w = OnlinePanel.wizard(imp)
  if not w then return nil end
  local steps = OnlinePanel.wizardSteps(imp)
  local at = math.max(1, math.min(tonumber(w.at) or 1, #steps))
  w.at = at
  return steps[at], at, #steps
end

function OnlinePanel.wizardReady(imp)
  local st = OnlinePanel.state(imp)
  local id = OnlinePanel.wizardStep(imp)
  if id == "game" then return OnlinePanel.selectedVersion(imp) ~= nil end
  if id == "save" then return st.slotId ~= nil end
  if id == "team" then
    local n = #(st.team or {})
    if n == 0 then return false end
    local w, target = st.wizard, st.joinTarget
    if w and w.kind == "join" and type(target) == "table"
        and type(target.rule) == "table" and tonumber(target.rule.partySize) then
      return n == OnlinePanel.teamCap(imp)
    end
    if OnlinePanel.formatMismatch(imp, OnlinePanel.ruleset(imp)) then return false end
    return true
  end
  if id == "role" then
    if st.tradeRole == "join" then
      local target = OnlinePanel.tradeState(imp).target
      return type(target) == "table" and target.room ~= nil
    end
    return (st.tradeRole or "host") == "host"
  end
  if id == "visibility" then
    return st.private ~= true or OnlinePanel.pinValid(st.pin)
  end
  return true
end

local function enterStep(imp, id)
  local st = OnlinePanel.state(imp)
  if id == "rules" and not st.ruleEdited then
    st.rule.partySize = math.max(1, #(st.team or {}))
  end
end

function OnlinePanel.wizardNext(imp)
  local st = OnlinePanel.state(imp)
  local w = st.wizard
  if not w then return false end
  if not OnlinePanel.wizardReady(imp) then return false end
  local steps = OnlinePanel.wizardSteps(imp)
  if w.at >= #steps then return OnlinePanel.wizardFinish(imp) end
  local fromAt = w.at
  w.at = w.at + 1
  Transition.start("online", "push", { dir = 1, from = "wizard",
    fromAt = fromAt, to = "wizard" })
  enterStep(imp, steps[w.at])
  st.status, st.statusOk = nil, false
  return true
end

function OnlinePanel.wizardBack(imp)
  local st = OnlinePanel.state(imp)
  local w = st.wizard
  if not w then return false end
  if (w.at or 1) <= 1 then
    st.wizard = nil
    local stack = OnlinePanel.nav(imp)
    if #stack <= 1 then return false end
    local from = table.remove(stack)
    Transition.start("online", "pop", { dir = -1, from = from,
      to = stack[#stack] })
    entered(imp, stack[#stack])
    return true
  end
  local fromAt = w.at
  w.at = w.at - 1
  Transition.start("online", "pop", { dir = -1, from = "wizard",
    fromAt = fromAt, to = "wizard" })
  st.status, st.statusOk = nil, false
  return true
end

function OnlinePanel.wizardTo(imp, id)
  local w = OnlinePanel.wizard(imp)
  if not w then return false end
  w.show[id] = true
  local steps = OnlinePanel.wizardSteps(imp)
  for i, step in ipairs(steps) do
    if step == id then
      local fromAt = w.at or 1
      w.at = i
      if i ~= fromAt then
        Transition.start("online", i > fromAt and "push" or "pop",
          { dir = i > fromAt and 1 or -1, from = "wizard", fromAt = fromAt,
            to = "wizard" })
      end
      enterStep(imp, id)
      return true
    end
  end
  return false
end

function OnlinePanel.wizardAnswers(imp)
  local st = OnlinePanel.state(imp)
  local def = OnlinePanel.wizardDef(imp)
  if not def then return {} end
  local c = OnlinePanel.cache(imp)
  local out = {}
  for _, id in ipairs(def.steps) do
    local value
    if id == "game" then
      local version = OnlinePanel.selectedVersion(imp)
      local info = version and GameVersion.info(version)
      value = (info and (info.launcherName or info.name)) or version
        or Strings("none")
      if st.cartId then value = tostring(value) .. " / " .. tostring(st.cartId) end
    elseif id == "save" then
      value = st.slotId or Strings("none")
      for _, row in ipairs(c.slots or {}) do
        if row.id == st.slotId then value = row.label end
      end
    elseif id == "team" and OnlinePanel.wizardActivity(imp) ~= "trade" then
      local names = {}
      for _, row in ipairs(c.team or {}) do
        names[#names + 1] = row and row.name or "?"
      end
      value = (#names > 0) and table.concat(names, ", ") or Strings("none")
    elseif id == "rules" then
      value = OnlinePanel.ruleText(OnlinePanel.ruleFor(imp))
    elseif id == "format" then
      local ruleset = OnlinePanel.ruleset(imp)
      value = ruleset and Strings(OnlinePanel.FORMAT_TEXT[ruleset] or ruleset) or nil
    elseif id == "visibility" and not tradeJoinStep(st, id) then
      value = (st.private == true) and Strings("Private")
        or Strings("Public")
      if st.note and st.note ~= "" then
        value = tostring(value) .. ' - "' .. tostring(st.note) .. '"'
      end
    elseif id == "tourvisibility" then
      value = (st.tourPublic == false) and Strings("Private (code)")
        or Strings("Public")
    elseif id == "playing" then
      value = (st.tourPlaying == false) and Strings("Organize and watch")
        or Strings("Play in it")
    elseif id == "shotclock" then
      value = Strings("%d seconds a move", st.tourShotClock or 6)
    elseif id == "spectators" then
      value = (tonumber(st.tourSpectators) or 0) > 0
        and Strings("Up to %d", st.tourSpectators)
        or Strings("No spectators")
    elseif id == "role" then
      local target = OnlinePanel.tradeState(imp).target
      value = (st.tradeRole == "join")
        and Strings("Join %s", tostring(type(target) == "table"
          and target.name or "?")) or Strings("Host a trade")
    end
    if value ~= nil then
      out[#out + 1] = { step = id,
        label = Strings(OnlinePanel.STEP_LABEL[id] or id),
        value = tostring(value) }
    end
  end
  return out
end

finishTo = function(imp, screen)
  local st = OnlinePanel.state(imp)
  st.wizard = nil
  local stack = OnlinePanel.nav(imp)
  while #stack > 1 and stack[#stack] == "wizard" do table.remove(stack) end
  return OnlinePanel.go(imp, screen)
end

function OnlinePanel.hostBattle(imp)
  local st = OnlinePanel.state(imp)
  ensureHooks()
  local rule = OnlinePanel.ruleFor(imp)
  local why = OnlinePanel.ruleMismatch(imp, rule, Strings("Your rule"))
    or OnlinePanel.formatMismatch(imp, OnlinePanel.ruleset(imp))
  if why then
    st.status, st.statusOk = why, false
    return false, why
  end
  local profile, reason = OnlinePanel.myProfile(imp)
  if not profile then
    st.status, st.statusOk = reason or Strings("Reading your game..."), false
    return false
  end
  st.setupDone = true
  st.pending = Client().createRoom(OnlinePanel.roomOptions(imp, "battle",
    profile, 8))
  OnlinePanel.stampPending(st.pending)
  finishTo(imp, "room")
  return true
end

function OnlinePanel.roomOptions(imp, intent, profile, maxSpectators)
  local st = OnlinePanel.state(imp)
  local private = st.private == true and OnlinePanel.pinValid(st.pin)
  local seats = 2
  if type(profile) == "table" and profile.rulesetId == "g3_multi" then seats = 4 end
  return {
    intent = intent, profile = profile, playing = true,
    maxSpectators = maxSpectators, private = private,
    pin = private and st.pin or nil, seats = seats, auto = false,
    note = (st.note ~= "" and st.note) or nil,
  }
end

function OnlinePanel.stampPending(pending)
  if type(pending) == "table" and pending.at == nil then
    pending.at = nowSeconds()
  end
  return pending
end

function OnlinePanel.findEntry(field, value)
  if value == nil then return nil end
  for _, entry in ipairs(Client().lobby() or EMPTY) do
    if entry[field] == value then return entry end
  end
  return nil
end

function OnlinePanel.targetFor(entry, as)
  if type(entry) ~= "table" then return nil end
  local profile = entry.profile or entry.profileTable
  local tournament = entry.tour ~= nil or entry.intent == "tournament"
  return {
    room = (not tournament) and (entry.room or nil) or nil,
    tour = tournament and (entry.tour or nil) or nil,
    rule = entry.ruleTable or (type(profile) == "table" and profile.rule) or nil,
    as = as or "player",
    tournament = tournament,
    locked = entry.locked == true,
    name = entry.name,
    version = entry.version or (type(profile) == "table" and profile.version)
      or nil,
    engine = type(profile) == "table" and tonumber(profile.engine) or nil,
    rulesetId = type(profile) == "table" and profile.rulesetId or nil,
    intent = entry.intent,
  }
end

function OnlinePanel.applyTarget(imp, target)
  if type(target) ~= "table" then return end
  if target.engine == 3 and target.as ~= "spectator"
      and OnlinePanel.formatKnown(target.rulesetId) then
    if OnlinePanel.engineVersionFor(imp, 3) then
      OnlinePanel.alignEngine(imp, 3, target.version)
    end
    OnlinePanel.setRuleset(imp, target.rulesetId)
  end
end

function OnlinePanel.startJoin(imp, target, rule, as, tournament)
  local st = OnlinePanel.state(imp)
  if type(target) == "string" then
    local entry = OnlinePanel.findEntry("room", target)
      or OnlinePanel.findEntry("tour", target)
    target = entry and OnlinePanel.targetFor(entry, as)
      or { room = target, as = as or "player" }
  end
  if type(target) ~= "table" or not (target.room or target.tour or target.code) then
    st.status, st.statusOk = Strings("That lobby is gone."), false
    return false
  end
  target.as = as or target.as or "player"
  if type(rule) == "table" then target.rule = rule end
  if tournament then target.tournament = true end
  if target.tournament or target.tour or target.code then
    target.tournament = true
  end
  st.joinTarget = target
  OnlinePanel.applyTarget(imp, target)
  if target.as == "spectator" and not target.tournament then
    if target.locked and not target.pin then
      return OnlinePanel.pinOpen(imp, target)
    end
    return OnlinePanel.joinTargetNow(imp)
  end
  if target.locked and not target.pin and OnlinePanel.setupComplete(imp) then
    return OnlinePanel.pinOpen(imp, target)
  end
  return OnlinePanel.startWizard(imp, "join")
end

function OnlinePanel.teamCap(imp)
  local st = OnlinePanel.state(imp)
  local w, target = st.wizard, st.joinTarget
  if w and w.kind == "join" and type(target) == "table"
      and type(target.rule) == "table" then
    local n = tonumber(target.rule.partySize)
    if n then return math.max(1, math.min(n, OnlinePanel.TEAM_MAX)) end
  end
  if OnlinePanel.ruleset(imp) == "g3_multi" then return OnlinePanel.MULTI_TEAM end
  return OnlinePanel.TEAM_MAX
end

function OnlinePanel.startJoinTournament(imp, target, rule)
  if type(target) == "string" then
    local want = OnlinePanel.tourTarget(target)
    if not want then
      local st = OnlinePanel.state(imp)
      st.status, st.statusOk = Strings("Tournament codes are 6 characters."), false
      return false
    end
    target = want
  end
  return OnlinePanel.startJoin(imp, target, rule, "player", true)
end

function OnlinePanel.joinTargetNow(imp)
  local st = OnlinePanel.state(imp)
  local target = st.joinTarget
  if type(target) ~= "table" then return false end
  if target.tournament then
    local ok = OnlinePanel.joinTournament(imp,
      { tour = target.tour, code = target.code }, target.as)
    if ok then finishTo(imp, "tournament") end
    return ok
  end
  local ok = OnlinePanel.joinRoom(imp, target.room, target.as, target.pin)
  if ok then finishTo(imp, "room") end
  return ok
end

function OnlinePanel.pickTeamInRoom(imp)
  local st = OnlinePanel.state(imp)
  local room = Client().room()
  if not room then return false end
  st.joinTarget = { room = room.room, inRoom = true, as = "player",
    rule = type(room.profile) == "table" and room.profile.rule or nil }
  return OnlinePanel.startWizard(imp, "join")
end

function OnlinePanel.joinFromWizard(imp)
  local st = OnlinePanel.state(imp)
  local target = st.joinTarget
  if type(target) ~= "table" then return false end
  if target.as ~= "spectator" then
    local why = OnlinePanel.ruleMismatch(imp, target.rule, Strings("This room"))
      or (target.engine == 3 and OnlinePanel.formatMismatch(imp, target.rulesetId))
      or nil
    if why then
      st.status, st.statusOk = why, false
      st.ruleBlock = true
      return false, why
    end
  end
  st.ruleBlock = nil
  st.setupDone = true
  if target.inRoom then
    finishTo(imp, "room")
    return true
  end
  if target.locked and not target.pin and not target.tournament then
    return OnlinePanel.pinOpen(imp, target)
  end
  return OnlinePanel.joinTargetNow(imp)
end

function OnlinePanel.wizardFinish(imp)
  local st = OnlinePanel.state(imp)
  local w = st.wizard
  if not w then return false end
  if w.kind == "hostBattle" then return OnlinePanel.hostBattle(imp) end
  if w.kind == "hostTournament" then return OnlinePanel.hostTournament(imp) end
  if w.kind == "join" then return OnlinePanel.joinFromWizard(imp) end
  if w.kind == "invite" then
    st.setupDone = true
    local ok = OnlinePanel.sendInvite(imp)
    if ok then
      local said, good = st.status, st.statusOk
      finishTo(imp, "play")
      st.status, st.statusOk = said, good
    end
    return ok
  end
  if w.kind == "accept" then
    st.setupDone = true
    local invite = st.acceptTarget
    if not OnlinePanel.inviteOpen(invite) then
      st.acceptTarget = nil
      finishTo(imp, "play")
      st.status, st.statusOk = Strings("That invite ran out."), false
      return false
    end
    return OnlinePanel.acceptNow(imp, invite)
  end
  if w.kind == "tradeRemote" then
    local tr = OnlinePanel.tradeState(imp)
    st.setupDone = true
    if st.tradeRole == "join" then
      local target = tr.target
      if type(target) == "table" and target.locked and not target.pin then
        st.joinTarget = { room = target.room, as = "player", locked = true,
                          name = target.name, trade = true }
        return OnlinePanel.pinOpen(imp, st.joinTarget)
      end
      if not OnlinePanel.joinTrade(imp, target) then return false end
      finishTo(imp, "room")
      return true
    end
    if not OnlinePanel.hostTrade(imp) then return false end
    finishTo(imp, "room")
    return true
  end
  return false
end

OnlinePanel.PIN_FIELD = "online-pin"
OnlinePanel.PIN_ENTER = "online-pin-enter"
OnlinePanel.PIN_CANCEL = "online-pin-cancel"

function OnlinePanel.pinModal(imp)
  return type(imp) == "table" and imp._pinModal or nil
end

OnlinePanel._pinLockout = {}

local function lockoutFor(target)
  local room = type(target) == "table" and target.room or nil
  return room and OnlinePanel._pinLockout[room] or nil
end

function OnlinePanel.pinOpen(imp, target, err, pin)
  if type(imp) ~= "table" then return false end
  local was = imp._pinModal
  imp._pinModal = {
    target = target,
    pin = OnlinePanel.sanitizePin(pin
      or (was and was.target == target and was.pin) or ""),
    error = err,
    retryAt = (was and was.target == target and was.retryAt) or lockoutFor(target),
  }
  imp._onlineFocus = OnlinePanel.PIN_FIELD
  if type(imp._armTextInput) == "function" then pcall(imp._armTextInput, imp) end
  Kit.setFocus(OnlinePanel.PIN_FIELD)
  return true
end

function OnlinePanel.pinClose(imp)
  if type(imp) ~= "table" or not imp._pinModal then return false end
  imp._pinModal = nil
  if imp._onlineFocus == OnlinePanel.PIN_FIELD then
    imp._onlineFocus = nil
    if type(imp._disarmTextInput) == "function" then
      pcall(imp._disarmTextInput, imp)
    end
  end
  Kit.setFocus(nil)
  return true
end

function OnlinePanel.pinLocked(imp)
  local mo = OnlinePanel.pinModal(imp)
  if not mo or not mo.retryAt then return false end
  local now = Client().serverTime() or 0
  if now >= mo.retryAt then
    mo.retryAt = nil
    local room = type(mo.target) == "table" and mo.target.room or nil
    if room then OnlinePanel._pinLockout[room] = nil end
    return false
  end
  return true
end

function OnlinePanel.pinType(imp, text)
  local mo = OnlinePanel.pinModal(imp)
  if not mo then return false end
  mo.pin = OnlinePanel.sanitizePin((mo.pin or "") .. tostring(text or ""))
  return true
end

function OnlinePanel.pinBack(imp)
  local mo = OnlinePanel.pinModal(imp)
  if not mo then return false end
  mo.pin = (mo.pin or ""):sub(1, -2)
  return true
end

function OnlinePanel.pinSubmit(imp)
  local st = OnlinePanel.state(imp)
  local mo = OnlinePanel.pinModal(imp)
  if not mo then return false end
  if OnlinePanel.pinLocked(imp) then return false end
  if not OnlinePanel.pinValid(mo.pin) then
    mo.error = Strings("A PIN is 4 digits.")
    return false
  end
  local target = mo.target or st.joinTarget
  if type(target) ~= "table" then
    OnlinePanel.pinClose(imp)
    return false
  end
  target.pin = mo.pin
  st.joinTarget = target
  mo.error = nil
  mo.sent = true
  if target.as ~= "spectator" and not OnlinePanel.setupComplete(imp)
      and not target.trade then
    OnlinePanel.pinClose(imp)
    return OnlinePanel.startWizard(imp, "join")
  end
  local ok = OnlinePanel.joinTargetNow(imp)
  if ok then
    if st.pending then st.pending.pinTarget = target end
    OnlinePanel.pinClose(imp)
  end
  return ok
end

function OnlinePanel.pinAction(imp, action)
  if not OnlinePanel.pinModal(imp) then return false end
  if action == "b" then return OnlinePanel.pinClose(imp) end
  if action == "a" then OnlinePanel.pinSubmit(imp) return true end
  return false
end

function OnlinePanel.retryAtText(retryAt)
  local now = Client().serverTime() or 0
  local mins = math.max(1, math.ceil(((tonumber(retryAt) or now) - now) / 60000))
  return Strings("Too many tries. Try again in %d min.", mins)
end

function OnlinePanel.pinFailed(imp, pending)
  local target = pending.pinTarget or (OnlinePanel.state(imp).joinTarget)
  if type(target) ~= "table" then return false end
  local typed = target.pin
  target.pin = nil
  local reason = pending.reason
  local err
  if reason == "bad_pin" then
    local left = tonumber(pending.triesLeft)
    err = (left == 1 and Strings("That PIN didn't match. 1 try left."))
      or (left and Strings("That PIN didn't match. %d tries left.", left))
      or Strings("That PIN didn't match.")
  elseif reason == "pin_locked" then
    err = OnlinePanel.retryAtText(pending.retryAt)
  else
    err = Strings("This lobby needs its PIN.")
  end
  OnlinePanel.pinOpen(imp, target, err, typed)
  if reason == "pin_locked" and imp._pinModal then
    local retryAt = tonumber(pending.retryAt)
      or ((Client().serverTime() or 0) + 600000)
    imp._pinModal.retryAt = retryAt
    if target.room then OnlinePanel._pinLockout[target.room] = retryAt end
  end
  return true
end

OnlinePanel.INVITE_TTL = 20000

OnlinePanel.ACTIVITY_TEXT = {
  battle_single = "a battle", battle_double = "a double battle",
  battle_multi = "a multi battle", trade = "a trade", chat = "a chat",
  card = "a card swap", watch = "watch a match", tournament = "a tournament",
  minigame_jump = "POKéMON Jump", minigame_crush = "Berry Crush",
  minigame_pick = "Dodrio Berry Picking",
}

OnlinePanel.ACTIVITY_LABEL = {
  battle_single = "Battle", battle_double = "Double battle", trade = "Trade",
  watch = "Watch my match", tournament = "Join my tournament",
}

OnlinePanel.WHERE_TEXT = {
  launcher = "Launcher", game = "In game", union = "Union Room",
  direct = "Direct Corner",
}

local NEEDS_TEAM = { battle_single = true, battle_double = true,
  battle_multi = true, tournament = true }
local NEEDS_SAVE = { trade = true }

OnlinePanel.NEEDS_TEAM = NEEDS_TEAM

function OnlinePanel.inviteLine(invite)
  if type(invite) ~= "table" then return "" end
  local from = type(invite.from) == "table" and invite.from or EMPTY
  local what = OnlinePanel.ACTIVITY_TEXT[tostring(invite.activity)]
    or tostring(invite.activity)
  if invite.activity == "watch" then
    return Strings("%s invites you to watch a match.", tostring(from.name or "?"))
  end
  return Strings("%s invites you to %s.", tostring(from.name or "?"), Strings(what))
end

function OnlinePanel.inviteOpen(invite)
  if type(invite) ~= "table" or invite.closed then return false end
  local at = tonumber(invite.expiresAt)
  if at and (Client().serverTime() or 0) >= at then return false end
  return true
end

function OnlinePanel.inviteLeft(invite)
  local at = type(invite) == "table" and tonumber(invite.expiresAt) or nil
  if not at then return 1 end
  local left = (at - (Client().serverTime() or 0)) / OnlinePanel.INVITE_TTL
  return math.max(0, math.min(1, left))
end

function OnlinePanel.toast(imp)
  local st = type(imp) == "table" and imp._online or nil
  if not st then return nil end
  local list = st.invites
  for i = 1, #list do
    if not list[i].closed and not list[i].answered then return list[i] end
  end
  return nil
end

function OnlinePanel.activitiesFor(imp, player)
  local out = {}
  if type(player) ~= "table" then return out end
  local engine = tonumber(player.engine) or 0
  local ok = engine >= 1 and engine <= 3
    and OnlinePanel.engineVersionFor(imp, engine) ~= nil
  if ok then
    if engine ~= 2 or OnlinePanel.gen2Battles() then
      out[#out + 1] = "battle_single"
    end
    if engine == 3 then out[#out + 1] = "battle_double" end
    out[#out + 1] = "trade"
  end
  local place = player.place or player.where
  if place == "union" or place == "direct" then return out end
  local client = Client()
  local room = client.room()
  if room and room.room and room.intent ~= "trade" then
    out[#out + 1] = "watch"
  end
  local tour = client.tournament()
  if tour and tour.tour and tour.stage == "registering" then
    out[#out + 1] = "tournament"
  end
  return out
end

function OnlinePanel.invitePickerOpen(imp, player)
  if type(imp) ~= "table" or type(player) ~= "table" then return false end
  imp._invitePicker = { player = player,
    activities = OnlinePanel.activitiesFor(imp, player) }
  Kit.setFocus("online-invite-cancel")
  return true
end

function OnlinePanel.invitePickerClose(imp)
  if type(imp) ~= "table" or not imp._invitePicker then return false end
  imp._invitePicker = nil
  Kit.setFocus(nil)
  return true
end

local function alignEngine(imp, engine, version)
  local st = OnlinePanel.state(imp)
  engine = tonumber(engine)
  if not engine then return true end
  local current = OnlinePanel.selectedVersion(imp)
  if current and GameVersion.generation(current) == engine then return true end
  local want = (version and imp.ready and imp.ready[version]) and version
    or OnlinePanel.engineVersionFor(imp, engine)
  if not want then return false end
  st.version, st.slotId, st.cartId, st.team = want, nil, nil, {}
  st.slotRead, st.ready, st.kind, st.engine = nil, false, "vanilla", nil
  st.versionPicked = true
  st.setupDone = false
  OnlinePanel.invalidate(imp)
  return true
end

OnlinePanel.alignEngine = alignEngine

function OnlinePanel.inviteReady(imp, activity)
  local st = OnlinePanel.state(imp)
  if activity == "watch" then return true end
  if NEEDS_TEAM[activity] then
    return OnlinePanel.setupComplete(imp)
      and OnlinePanel.formatMismatch(imp, OnlinePanel.ruleset(imp)) == nil
  end
  if NEEDS_SAVE[activity] then
    return OnlinePanel.selectedVersion(imp) ~= nil and st.slotId ~= nil
  end
  return true
end

function OnlinePanel.startInvite(imp, player, activity)
  local st = OnlinePanel.state(imp)
  OnlinePanel.invitePickerClose(imp)
  if type(player) ~= "table" or type(activity) ~= "string" then return false end
  st.inviteTarget = { id = player.id, name = player.name, activity = activity,
                      engine = player.engine, version = player.version }
  if activity ~= "watch" and activity ~= "tournament" then
    if not alignEngine(imp, player.engine, player.version) then
      st.status, st.statusOk = Strings("Import that game first."), false
      return false
    end
    if tonumber(player.engine) == 3 then
      local ruleset = require("src.online.Protocol2").ACTIVITY_RULESET[activity]
      if OnlinePanel.formatKnown(ruleset) then OnlinePanel.setRuleset(imp, ruleset) end
    end
  end
  if OnlinePanel.inviteReady(imp, activity) then
    return OnlinePanel.sendInvite(imp)
  end
  return OnlinePanel.startWizard(imp, "invite")
end

function OnlinePanel.inviteProfile(imp, activity)
  if activity == "watch" or activity == "tournament" then
    local room = Client().room()
    local tour = Client().tournament()
    local p = (room and room.profile) or (tour and tour.profile)
    if p then return p end
  end
  local profile, reason = OnlinePanel.myProfile(imp)
  if not profile then return nil, reason end
  if tonumber(profile.engine) ~= 3 then return profile end
  local ruleset = require("src.online.Protocol2").ACTIVITY_RULESET[activity]
  return OnlinePanel.profileFor(imp, ruleset)
end

function OnlinePanel.sendInvite(imp)
  local st = OnlinePanel.state(imp)
  local target = st.inviteTarget
  if type(target) ~= "table" then return false end
  local client = Client()
  if type(client.invite) ~= "function" then
    st.status, st.statusOk = Strings("This build can't send invites."), false
    return false
  end
  ensureHooks()
  local profile, reason = OnlinePanel.inviteProfile(imp, target.activity)
  if not profile then
    st.status, st.statusOk = reason or Strings("Reading your game..."), false
    return false
  end
  local detail = {}
  if target.activity == "watch" then
    local room = client.room()
    detail.room = room and room.room or nil
  elseif target.activity == "tournament" then
    local tour = client.tournament()
    detail.tour = tour and tour.tour or nil
  elseif profile.rulesetId then
    detail.ruleset = profile.rulesetId
  end
  OnlinePanel.pushProfile(profile, imp)
  st.outgoing = client.invite(target.id, target.activity, detail, profile)
  st.outgoingName = target.name
  st.status, st.statusOk = Strings("Invite sent to %s.", tostring(target.name or "?")),
    true
  return st.outgoing ~= nil
end

function OnlinePanel.inviteClosedText(msg)
  local ok, Protocol2 = pcall(require, "src.online.Protocol2")
  if ok and type(Protocol2.inviteClosedText) == "function" then
    local got, text = pcall(Protocol2.inviteClosedText, msg)
    if got and type(text) == "string" and text ~= "" then return text end
  end
  local why = type(msg) == "table" and msg.why or msg
  if why == "declined" then return Strings("They said no.") end
  if why == "timeout" then return Strings("No answer.") end
  if why == "busy" then return Strings("They are busy right now.") end
  if why == "offline" or why == "target_left" then
    return Strings("They went offline.")
  end
  if why == "profile_mismatch" then
    return Strings("Your games don't match.")
  end
  return Strings("The invite was called off.")
end

local function needsSetup(imp, invite)
  local activity = invite and invite.activity
  return not OnlinePanel.inviteReady(imp, activity)
end

function OnlinePanel.acceptNow(imp, invite)
  local st = OnlinePanel.state(imp)
  if not OnlinePanel.inviteOpen(invite) then
    st.status, st.statusOk = Strings("That invite ran out."), false
    return false
  end
  local client = Client()
  if type(client.replyInvite) ~= "function" then return false end
  ensureHooks()
  local profile = invite.activity ~= "watch"
    and OnlinePanel.inviteProfile(imp, invite.activity) or nil
  if profile then OnlinePanel.pushProfile(profile, imp) end
  invite.answered = true
  st.acceptTarget = nil
  OnlinePanel.syncToast(imp)
  if type(imp.tab) == "string" and imp.tab ~= "online"
      and type(imp._switchTab) == "function" then
    pcall(imp._switchTab, imp, "online")
  end
  local sent = client.replyInvite(invite.id, true)
  if invite.activity == "tournament" then
    local detail = type(invite.detail) == "table" and invite.detail or EMPTY
    st.joinTarget = { tour = detail.tour, tournament = true, as = "player" }
    if detail.tour and OnlinePanel.joinTournament(imp, { tour = detail.tour },
        "player") then
      finishTo(imp, "tournament")
    end
    return sent ~= false
  end
  st.accepted = { id = invite.id, activity = invite.activity }
  if st.wizard then finishTo(imp, "play") end
  st.status, st.statusOk = Strings("Joining %s...",
    tostring((invite.from or EMPTY).name or "?")), true
  return sent ~= false
end

function OnlinePanel.acceptInvite(imp, invite)
  local st = OnlinePanel.state(imp)
  if not OnlinePanel.inviteOpen(invite) then return false end
  if OnlinePanel.inviteEngine(invite) == 3 then
    local from = type(invite.from) == "table" and invite.from or EMPTY
    local version = type(from.avatar) == "table" and from.avatar.version or nil
    alignEngine(imp, 3, version)
    local ruleset = require("src.online.Protocol2").ACTIVITY_RULESET[invite.activity]
    local detail = type(invite.detail) == "table" and invite.detail or EMPTY
    if OnlinePanel.formatKnown(detail.ruleset) then ruleset = detail.ruleset end
    if OnlinePanel.formatKnown(ruleset) then OnlinePanel.setRuleset(imp, ruleset) end
  end
  if needsSetup(imp, invite) then
    st.acceptTarget = invite
    invite.answered = true
    OnlinePanel.syncToast(imp)
    if type(imp.tab) == "string" and imp.tab ~= "online"
        and type(imp._switchTab) == "function" then
      pcall(imp._switchTab, imp, "online")
    end
    return OnlinePanel.startWizard(imp, "accept")
  end
  return OnlinePanel.acceptNow(imp, invite)
end

function OnlinePanel.declineInvite(imp, invite)
  if type(invite) ~= "table" then return false end
  invite.answered = true
  local client = Client()
  if type(client.replyInvite) == "function" then
    pcall(client.replyInvite, invite.id, false)
  end
  if type(imp) == "table" and imp._online then OnlinePanel.syncToast(imp) end
  return true
end

OnlinePanel.LAUNCHER_ACTIVITIES = {
  battle_single = true, battle_double = true, trade = true, watch = true,
  tournament = true,
}

OnlinePanel.GAME_ONLY_TEXT = {
  chat = "%s wanted to chat. Chats happen in the Union Room.",
  card = "%s wanted to swap trainer cards. That happens in the Union Room.",
  battle_multi = "%s wanted a multi battle. Join one from Play instead.",
  minigame_jump = "%s asked you to play POKéMON Jump. That happens in game.",
  minigame_crush = "%s asked you to play Berry Crush. That happens in game.",
  minigame_pick = "%s asked you to play Dodrio Berry Picking. That happens in game.",
}

function OnlinePanel.inviteEngine(invite)
  if type(invite) ~= "table" then return nil end
  local detail = type(invite.detail) == "table" and invite.detail or EMPTY
  if type(detail.ruleset) == "string" and detail.ruleset:match("^g3_") then return 3 end
  local from = type(invite.from) == "table" and invite.from or EMPTY
  if from.where == "union" or from.where == "direct" then return 3 end
  if type(from.avatar) == "table" then return 3 end
  if invite.activity == "battle_double" or invite.activity == "chat"
      or invite.activity == "card" then
    return 3
  end
  return nil
end

function OnlinePanel.inviteUsable(imp, invite)
  if type(invite) ~= "table" then return false, nil end
  local from = type(invite.from) == "table" and invite.from or EMPTY
  local name = tostring(from.name or "?")
  if not OnlinePanel.LAUNCHER_ACTIVITIES[tostring(invite.activity)] then
    local text = OnlinePanel.GAME_ONLY_TEXT[tostring(invite.activity)]
      or "%s sent an invite this launcher can't answer."
    return false, Strings(text, name)
  end
  if OnlinePanel.inviteEngine(invite) == 3 and invite.activity ~= "watch"
      and invite.activity ~= "tournament"
      and not OnlinePanel.engineVersionFor(imp, 3) then
    return false, Strings("%s plays FireRed or LeafGreen. Import one to answer.", name)
  end
  return true, nil
end

function OnlinePanel.inviteIn(imp, msg)
  local st = OnlinePanel.state(imp)
  if type(msg) ~= "table" or msg.id == nil then return end
  for _, have in ipairs(st.invites) do
    if have.id == msg.id then return end
  end
  local usable, why = OnlinePanel.inviteUsable(imp, msg)
  if not usable then
    local client = Client()
    if type(client.replyInvite) == "function" then
      pcall(client.replyInvite, msg.id, false)
    end
    st.status, st.statusOk = why, false
    return
  end
  local copy = {}
  for k, v in pairs(msg) do copy[k] = v end
  copy.line = OnlinePanel.inviteLine(copy)
  st.invites[#st.invites + 1] = copy
  OnlinePanel.syncToast(imp)
end

local TOAST_SLIDE = { duration = 0.22 }

function OnlinePanel.syncToast(imp)
  local st = OnlinePanel.state(imp)
  local head = OnlinePanel.toast(imp)
  local id = head and head.id or nil
  if id == st.toastId then return false end
  st.toastId = id
  if id ~= nil then Transition.start("toast", "in", TOAST_SLIDE) end
  return id ~= nil
end

function OnlinePanel.inviteClosed(imp, msg)
  local st = OnlinePanel.state(imp)
  if type(msg) ~= "table" then return end
  for i = #st.invites, 1, -1 do
    if st.invites[i].id == msg.id then
      st.invites[i].closed = true
      table.remove(st.invites, i)
    end
  end
  if st.acceptTarget and st.acceptTarget.id == msg.id
      and msg.why ~= "accepted" then
    st.acceptTarget = nil
    st.status, st.statusOk = Strings("That invite ran out."), false
  end
  OnlinePanel.syncToast(imp)
  local out = st.outgoing
  local mine = out and ((out.id ~= nil and out.id == msg.id)
    or (out.id == nil and msg.to ~= nil and msg.to == out.to
      and (msg.activity == nil or msg.activity == out.activity)))
  if mine then
    if msg.why == "accepted" or msg.why == "crossed" then
      st.status, st.statusOk = Strings("%s accepted.",
        tostring(st.outgoingName or "?")), true
    else
      st.status, st.statusOk = OnlinePanel.inviteClosedText(msg), false
    end
    st.outgoing = nil
  end
end

function OnlinePanel.pruneInvites(imp)
  local st = OnlinePanel.state(imp)
  for i = #st.invites, 1, -1 do
    local invite = st.invites[i]
    if not OnlinePanel.inviteOpen(invite)
        or (invite.answered and invite ~= st.acceptTarget) then
      table.remove(st.invites, i)
    end
  end
  OnlinePanel.syncToast(imp)
end

function OnlinePanel.toastAction(imp, action)
  local invite = OnlinePanel.toast(imp)
  if not invite then return false end
  if action == "accept" then return OnlinePanel.acceptInvite(imp, invite) end
  if action == "decline" then return OnlinePanel.declineInvite(imp, invite) end
  return false
end

-- --------------------------------------------------------- the PC picker

OnlinePanel.PC_FIELD = "online-pc-filter"
OnlinePanel.PC_CLOSE = "online-pc-close"

function OnlinePanel.pcPicker(imp)
  return type(imp) == "table" and imp._pcPicker or nil
end

function OnlinePanel.pcOpen(imp, opts)
  opts = opts or {}
  local side = opts.side
  if side and not OnlinePanel.tradePcAllowed(imp, side) then return false end
  imp._pcPicker = { query = "", page = 1, side = side }
  OnlinePanel.invalidate(imp, "party")
  Kit.setFocus(OnlinePanel.PC_CLOSE)
  return true
end

function OnlinePanel.pcClose(imp)
  if type(imp) ~= "table" or not imp._pcPicker then return false end
  imp._pcPicker = nil
  if imp._onlineFocus == OnlinePanel.PC_FIELD then
    imp._onlineFocus = nil
    if type(imp._disarmTextInput) == "function" then
      pcall(imp._disarmTextInput, imp)
    end
  end
  Kit.setFocus(nil)
  return true
end

function OnlinePanel.pcQuery(imp, text)
  local pc = OnlinePanel.pcPicker(imp)
  if not pc then return false end
  pc.query = tostring(text or ""):sub(1, 24)
  pc.page = 1
  return true
end

local function matches(row, needle)
  if needle == "" then return true end
  local mon = row.mon or {}
  local hay = table.concat({ tostring(row.name or ""),
    tostring(mon.species or ""), tostring(row.source or "") }, " "):upper()
  return hay:find(needle, 1, true) ~= nil
end

function OnlinePanel.pcRows(imp)
  local pc = OnlinePanel.pcPicker(imp)
  local c = OnlinePanel.cache(imp)
  if not pc then return EMPTY end
  local needle = tostring(pc.query or ""):upper()
  local out = {}
  for _, row in ipairs((pc.side and c.tradePc or c.pc) or EMPTY) do
    if matches(row, needle) then out[#out + 1] = row end
  end
  return out
end

function OnlinePanel.pcPick(imp, row)
  local st = OnlinePanel.state(imp)
  if type(row) ~= "table" then return false end
  local pc = OnlinePanel.pcPicker(imp)
  if pc and pc.side then
    OnlinePanel.tradePick(imp, pc.side, row.ref or row)
    OnlinePanel.pcClose(imp)
    return true
  end
  OnlinePanel.toggleTeam(st.team, row.ref or row, OnlinePanel.TEAM_MAX)
  st.ready = false
  OnlinePanel.invalidate(imp, "party", "summary")
  return true
end

function OnlinePanel.pcAction(imp, action)
  if not OnlinePanel.pcPicker(imp) then return false end
  if action == "b" then return OnlinePanel.pcClose(imp) end
  return false
end

OnlinePanel.HOST_PIN_FIELD = "online-host-pin"
OnlinePanel.TOUR_CODE_FIELD = "online-tour-code"

function OnlinePanel.fieldType(imp, key, text)
  local st = OnlinePanel.state(imp)
  text = tostring(text or "")
  if key == "online-name" then
    st.nameDraft = OnlinePanel.sanitizeName((st.nameDraft or "") .. text)
  elseif key == "online-note" then
    local note = (st.note or "") .. text
    while #note > OnlinePanel.NOTE_MAX do note = OnlinePanel.dropLast(note) end
    st.note = note
  elseif key == OnlinePanel.TOUR_CODE_FIELD then
    st.tourCode = OnlinePanel.sanitizeCode((st.tourCode or "") .. text)
  elseif key == OnlinePanel.HOST_PIN_FIELD then
    st.pin = OnlinePanel.sanitizePin((st.pin or "") .. text)
  elseif key == OnlinePanel.PIN_FIELD then
    OnlinePanel.pinType(imp, text)
  elseif key == OnlinePanel.PC_FIELD then
    local pc = OnlinePanel.pcPicker(imp)
    OnlinePanel.pcQuery(imp, ((pc and pc.query) or "") .. text)
  else
    return false
  end
  return true
end

local function dropLast(text)
  text = tostring(text or "")
  local cut = #text
  while cut > 0 do
    local b = text:byte(cut)
    cut = cut - 1
    if b < 0x80 or b >= 0xC0 then break end
  end
  return text:sub(1, cut)
end

OnlinePanel.dropLast = dropLast

function OnlinePanel.fieldBack(imp, key)
  local st = OnlinePanel.state(imp)
  if key == "online-name" then
    st.nameDraft = dropLast(st.nameDraft)
  elseif key == "online-note" then
    st.note = dropLast(st.note)
  elseif key == OnlinePanel.TOUR_CODE_FIELD then
    st.tourCode = dropLast(st.tourCode)
  elseif key == OnlinePanel.HOST_PIN_FIELD then
    st.pin = dropLast(st.pin)
  elseif key == OnlinePanel.PIN_FIELD then
    OnlinePanel.pinBack(imp)
  elseif key == OnlinePanel.PC_FIELD then
    local pc = OnlinePanel.pcPicker(imp)
    OnlinePanel.pcQuery(imp, dropLast((pc and pc.query) or ""))
  else
    return false
  end
  return true
end

function OnlinePanel.inviteToken(link)
  if type(link) == "table" then link = link.invite end
  if type(link) ~= "string" then return nil end
  link = link:lower()
  if link:match("^%x+$") and #link == 32 then return link end
  return nil
end

function OnlinePanel.deepLink(imp, link, as)
  local st = OnlinePanel.state(imp)
  local token = OnlinePanel.inviteToken(link)
  if not token then return false end
  ensureHooks()
  st.inviteJoin = { token = token, as = as or "player", at = nowSeconds() }
  if Connect.state() ~= "online" then
    if Connect.state() == "offline" or Connect.state() == "error" then
      OnlinePanel.connect(imp)
    end
    return true
  end
  return OnlinePanel.joinByInvite(imp)
end

function OnlinePanel.joinByInvite(imp)
  local st = OnlinePanel.state(imp)
  local want = st.inviteJoin
  if type(want) ~= "table" then return false end
  local client = Client()
  if type(client.joinRoomByInvite) ~= "function" then
    st.inviteJoin = nil
    return false
  end
  local profile = OnlinePanel.myProfile(imp)
  st.inviteJoin = nil
  if profile then OnlinePanel.pushProfile(profile, imp) end
  st.pending = client.joinRoomByInvite(want.token, want.as, profile)
  OnlinePanel.stampPending(st.pending)
  if st.pending then
    st.pending.inviteToken = want.token
    st.pending.inviteAs = want.as
  end
  OnlinePanel.go(imp, "room")
  return st.pending ~= nil
end

-- ------------------------------------------------------------- gen 2 gate

function OnlinePanel.gen2Battles()
  local hit = OnlinePanel._gen2Battles
  if hit ~= nil then return hit end
  local ok, mod = pcall(require, "src.link.LinkBattle2")
  hit = ok and type(mod) == "table" and type(mod.newHost) == "function"
  OnlinePanel._gen2Battles = hit
  return hit
end

function OnlinePanel.canBattleWith(version)
  if not version then return false end
  if OnlinePanel.isGen2(version) then return OnlinePanel.gen2Battles() end
  return true
end

-- --------------------------------------------------------------- filters

OnlinePanel.FILTERS = {
  { id = "all", label = "All" },
  { id = "gen1", label = "Gen 1" },
  { id = "gen2", label = "Gen 2" },
  { id = "gen3", label = "Gen 3" },
  { id = "vanilla", label = "Vanilla" },
  { id = "carts", label = "Carts" },
}

OnlinePanel.FILTER_LABEL = "Show:"
OnlinePanel.FILTER_AT = 8

function OnlinePanel.filter(imp)
  local st = OnlinePanel.state(imp)
  for _, row in ipairs(OnlinePanel.FILTERS) do
    if row.id == st.filter then return st.filter end
  end
  st.filter = "all"
  return st.filter
end

function OnlinePanel.setFilter(imp, id)
  local st = OnlinePanel.state(imp)
  for _, row in ipairs(OnlinePanel.FILTERS) do
    if row.id == id then
      st.filter = id
      OnlinePanel.cache(imp).dirty.lobby = true
      return true
    end
  end
  return false
end

function OnlinePanel.entryPasses(filter, entry)
  if type(filter) == "table" then filter = filter.id or "all" end
  if filter == nil or filter == "all" then return true end
  local profile = type(entry) == "table" and entry.profile or nil
  if type(profile) ~= "table" then
    local engine = type(entry) == "table" and tonumber(entry.engine) or nil
    if not engine or engine == 0 then return true end
    profile = { engine = engine }
  end
  local generation = tonumber(profile.engine)
    or GameVersion.generation(profile.version) or 1
  if filter == "gen1" then return generation == 1 end
  if filter == "gen2" then return generation == 2 end
  if filter == "gen3" then return generation == 3 end
  if filter == "carts" then return profile.kind == "cart" end
  if filter == "vanilla" then return profile.kind ~= "cart" end
  return true
end

-- ----------------------------------------------------------------- caches

local function newCache()
  return {
    dirty = { slots = true, carts = true, party = true, lobby = true,
              trade = true, summary = true },
    slots = {}, carts = {}, party = {}, pc = {}, team = {},
    rooms = {}, watch = {}, tours = {}, players = {}, mine = nil,
    tradeSlots = {}, tradeRows = { a = {}, b = {} },
    tradePc = EMPTY, tradePcKey = nil,
    counts = { players = 0, lobbies = 0 },
    summary = "", teamNote = nil, teamOk = false, partyReason = nil,
    selKey = nil, slotsRef = nil, slotsScope = nil,
    lobbyRev = -1, teamKey = nil, tradeKey = nil, pcKey = nil,
  }
end

function OnlinePanel.cache(imp)
  local st = OnlinePanel.state(imp)
  if not st.cache then st.cache = newCache() end
  return st.cache
end

function OnlinePanel.invalidate(imp, ...)
  local c = OnlinePanel.cache(imp)
  local n = select("#", ...)
  if n == 0 then
    for key in pairs(c.dirty) do c.dirty[key] = true end
    return c
  end
  for i = 1, n do c.dirty[select(i, ...)] = true end
  return c
end

function OnlinePanel.selectionKey(imp)
  local st = OnlinePanel.state(imp)
  return table.concat({ tostring(OnlinePanel.selectedVersion(imp)),
    tostring(st.cartId), tostring(st.kind), tostring(st.slotId),
    tostring(st.engine) }, "|")
end

local function refreshCarts(imp, c)
  if not c.dirty.carts then return end
  c.dirty.carts = false
  local version = OnlinePanel.selectedVersion(imp)
  local rows = OnlinePanel.sealedCarts(imp, version)
  c.carts = {}
  for _, row in ipairs(rows) do
    c.carts[#c.carts + 1] = { id = row.id,
      title = tostring(row.title or row.id) }
  end
end

local function refreshSlots(imp, c)
  local st = OnlinePanel.state(imp)
  local version = OnlinePanel.selectedVersion(imp)
  local scope = OnlinePanel.scopeFor(version, st.cartId)
  local ref = (type(imp.slots) == "table") and imp.slots[scope] or nil
  if scope ~= c.slotsScope or ref ~= c.slotsRef then c.dirty.slots = true end
  if not c.dirty.slots then return end
  c.dirty.slots = false
  local rows = OnlinePanel.slotsIn(imp, version, st.cartId)
  c.slotsScope = scope
  c.slotsRef = (type(imp.slots) == "table") and imp.slots[scope] or nil
  c.slots = {}
  for _, row in ipairs(rows) do
    if row.exists and not (st.cartId and row.sealBroken) then
      c.slots[#c.slots + 1] = {
        id = row.id,
        label = tostring(row.label or row.name or row.id),
        sub = ("%d badges"):format((row.meta and row.meta.badges) or 0),
      }
    end
  end
  local found = false
  for _, row in ipairs(c.slots) do
    if row.id == st.slotId then found = true end
  end
  if not found and st.slotId and #c.slots > 0 then
    st.slotId, st.team, st.slotRead = nil, {}, nil
    c.dirty.party = true
  end
end

local function teamKeyOf(team)
  local out = {}
  for i, ref in ipairs(team or {}) do out[i] = OnlinePanel.refKey(ref) end
  return table.concat(out, ",")
end

OnlinePanel.teamKey = teamKeyOf

local function partyKey(imp)
  local st = OnlinePanel.state(imp)
  return table.concat({ OnlinePanel.selectionKey(imp), teamKeyOf(st.team),
    tostring(st.rule.partySize), tostring(st.rule.minLevel),
    tostring(st.rule.maxLevel), tostring(st.rule.forceLevel),
    tostring(st.converted and st.converted.key) }, "|")
end

local function monRow(imp, entry, version)
  local st = OnlinePanel.state(imp)
  local mon = entry.mon or {}
  local refused, preview = OnlinePanel.monRefusal(imp, entry)
  local maxHp = tonumber(mon.maxHp or (mon.stats and mon.stats.hp)) or 0
  return {
    ref = { where = entry.where, box = entry.box, index = entry.index },
    key = OnlinePanel.refKey(entry),
    mon = mon,
    version = version,
    where = entry.where,
    source = entry.source,
    order = OnlinePanel.teamOrder(st.team, entry),
    name = monName(mon, version),
    label = ("%s  Lv%d  %d/%d HP"):format(
      monSpecies(mon, version), tonumber(mon.level) or 0,
      tonumber(mon.hp) or 0, maxHp),
    note = preview and preview[1] or nil,
    refused = refused,
  }
end

local function refreshParty(imp, c)
  local st = OnlinePanel.state(imp)
  local key = partyKey(imp)
  if key == c.teamKey and not c.dirty.party then return end
  c.dirty.party = false
  c.teamKey = key
  local version = OnlinePanel.selectedVersion(imp)
  c.party, c.pc, c.team = {}, {}, {}
  c.partyReason = nil
  c.teamOk, c.teamNote = true, nil
  if not st.slotId then
    c.partyReason = Strings("Pick a save first.")
    return
  end
  local pick, reason = OnlinePanel.readTeamSlot(imp)
  if not pick then
    c.partyReason = reason or Strings("Pick a save first.")
    return
  end
  local TeamPick = require("src.online.TeamPick")
  local byKey = {}
  for _, entry in ipairs(TeamPick.candidates(pick)) do
    local row = monRow(imp, entry, version)
    byKey[row.key] = row
    if entry.where == "party" then
      c.party[#c.party + 1] = row
    else
      c.pc[#c.pc + 1] = row
    end
  end
  for i, ref in ipairs(st.team or {}) do
    c.team[i] = byKey[OnlinePanel.refKey(ref)]
  end
  local ok, why = OnlinePanel.validateTeam(imp)
  c.teamOk, c.teamNote = ok, why
end

local function refreshSummary(imp, c)
  local st = OnlinePanel.state(imp)
  local key = OnlinePanel.selectionKey(imp) .. "|" .. #(st.team or {})
  if key == c.summaryKey then return end
  c.summaryKey = key
  local version = OnlinePanel.selectedVersion(imp)
  if not version then
    c.summary = Strings("No game imported yet.")
    return
  end
  local info = GameVersion.info(version)
  local parts = { tostring((info and (info.launcherName or info.name)) or version) }
  parts[#parts + 1] = st.slotId and tostring(st.slotId) or Strings("no save")
  parts[#parts + 1] = ("%d mons"):format(#(st.team or {}))
  local cart = nil
  for _, row in ipairs(c.carts) do
    if row.id == st.cartId then cart = row.title end
  end
  parts[#parts + 1] = cart or Strings("Vanilla")
  c.summary = table.concat(parts, " - ")
end

function OnlinePanel.gameName(version)
  if version == nil or version == "" then return "?" end
  local info = GameVersion.info(version)
  return tostring((info and (info.label or info.launcherName)) or version)
end

function OnlinePanel.whereText(entry)
  local where = type(entry) == "table" and entry.where or nil
  local text = OnlinePanel.WHERE_TEXT[tostring(where)]
  return text and Strings(text) or nil
end

function OnlinePanel.invitable(entry, me)
  if type(entry) ~= "table" then return false end
  if me ~= nil and entry.id == me then return false end
  if entry.online == false then return false end
  if entry.where == "game" then return false end
  local status = entry.status
  return status == nil or status == "idle" or status == "recruiting" or status == "waiting"
end

local function playerRow(imp, entry, me)
  local version = entry.version
  if (version == nil or version == "") and type(entry.profile) == "table" then
    version = entry.profile.version
  end
  local engine = tonumber(entry.engine) or 0
  if engine == 0 and version and version ~= "" then
    engine = GameVersion.generation(version) or 0
  end
  local reason = nil
  if not OnlinePanel.invitable(entry, me) then
    reason = entry.where == "game" and Strings("playing")
      or Strings(tostring(entry.status or "busy"))
  elseif engine == 0 or not OnlinePanel.engineVersionFor(imp, engine) then
    reason = Strings("needs a game you haven't imported")
  end
  return {
    id = tostring(entry.id),
    name = tostring(entry.name or "?"),
    verified = entry.verified == true,
    engine = engine,
    version = version,
    game = OnlinePanel.gameName(version),
    where = OnlinePanel.whereText(entry) or "",
    place = entry.where,
    status = tostring(entry.status or "idle"),
    reason = reason,
  }
end

OnlinePanel.playerRow = playerRow

local function roomRow(imp, entry, profile, mine)
  local ep = entry.profile or EMPTY
  local reason = OnlinePanel.joinReason(entry, profile)
  return {
    id = tostring(entry.id),
    room = entry.room,
    tour = entry.tour,
    locked = entry.locked == true,
    version = ep.version,
    where = OnlinePanel.whereText(entry),
    players = tonumber(entry.players) or nil,
    seats = tonumber(entry.seats) or nil,
    name = tostring(entry.name or "?"),
    verified = entry.verified == true,
    intent = tostring(entry.intent or "battle"),
    game = OnlinePanel.gameName(ep.version),
    arena = OnlinePanel.arenaText(ep),
    rule = OnlinePanel.ruleText(ep.rule),
    ruleTable = ep.rule,
    spectators = tonumber(entry.spectators) or 0,
    engine = tonumber(ep.engine) or tonumber(entry.engine) or nil,
    rulesetId = ep.rulesetId,
    profile = entry.profile,
    format = OnlinePanel.formatText(ep),
    seatsText = (tonumber(entry.seats) or 2) > 2
      and Strings("%d/%d trainers", tonumber(entry.players) or 0,
        tonumber(entry.seats)) or nil,
    stage = tostring(entry.stage or "waiting"),
    sub = ("%s  %s  %s"):format(OnlinePanel.gameName(ep.version),
      OnlinePanel.arenaText(ep), OnlinePanel.ruleText(ep.rule)),
    note = (entry.note ~= nil and entry.note ~= "") and tostring(entry.note)
      or nil,
    mine = mine == true,
    reason = reason,
  }
end

local function lobbyKey(imp, open, watch, profile)
  return table.concat({ tostring(OnlinePanel._lobbyRev or 0),
    tostring(#open), tostring(#watch),
    tostring(profile and profile.fingerprint),
    tostring(profile and profile.version), tostring(profile and profile.kind),
    OnlinePanel.filter(imp) }, "|")
end

local function refreshLobby(imp, c)
  local client = Client()
  local online = client.state() == "online"
  local open = (online and type(client.openRooms) == "function")
    and client.openRooms() or EMPTY
  local watch = (online and type(client.watchable) == "function")
    and client.watchable() or EMPTY
  local profile = OnlinePanel.myProfile(imp)
  local key = lobbyKey(imp, open, watch, profile)
  if key == c.lobbyKey and not c.dirty.lobby then return end
  c.dirty.lobby = false
  c.lobbyKey = key
  local filter = OnlinePanel.filter(imp)
  local me = OnlinePanel.mySeatId()
  c.rooms, c.watch, c.tours, c.players = {}, {}, {}, {}
  for _, entry in ipairs(open) do
    if entry.id ~= me and OnlinePanel.entryPasses(filter, entry) then
      if entry.intent == "tournament" or entry.tour ~= nil then
        c.tours[#c.tours + 1] = roomRow(imp, entry, profile)
      else
        c.rooms[#c.rooms + 1] = roomRow(imp, entry, profile)
      end
    end
  end
  local everyone = online and client.lobby() or EMPTY
  for _, entry in ipairs(everyone) do
    if entry.id ~= me and entry.online ~= false
        and OnlinePanel.entryPasses(filter, entry) then
      c.players[#c.players + 1] = playerRow(imp, entry, me)
    end
  end
  for _, entry in ipairs(watch) do
    if entry.id ~= me and OnlinePanel.entryPasses(filter, entry) then
      c.watch[#c.watch + 1] = roomRow(imp, entry, profile)
    end
  end
  local counts = (type(client.counts) == "function") and client.counts() or nil
  c.counts.players = (counts and tonumber(counts.players)) or 0
  c.counts.lobbies = (counts and tonumber(counts.openRooms)) or #c.rooms
  local room = client.room()
  if room and room.intent ~= "tournament" then
    c.mine = {
      room = room.room,
      locked = room.locked == true,
      stage = tostring(room.stage or "waiting"),
      intent = tostring(room.intent or "battle"),
      players = #(room.players or {}),
      seats = tonumber(room.seats) or 2,
      hosting = me ~= nil and room.host == me,
    }
  else
    c.mine = nil
  end
end

local function refreshTradePc(imp, c)
  local pc = OnlinePanel.pcPicker(imp)
  local side = pc and pc.side or nil
  if not side then
    c.tradePc, c.tradePcKey = EMPTY, nil
    return
  end
  local entry = OnlinePanel.tradeState(imp).sides[side]
  local key = table.concat({ side, tostring(entry and entry.version),
    tostring(entry and entry.slotId), tostring(entry and entry.cartId),
    tostring(OnlinePanel.tradePickKey(imp, side)) }, "|")
  if key == c.tradePcKey then return end
  c.tradePcKey = key
  c.tradePc = OnlinePanel.tradeBoxRows(imp, side)
  local mons = {}
  for _, row in ipairs(c.tradePc) do mons[#mons + 1] = row.mon end
  local view = OnlinePanel.tradeSideView(imp, side)
  if view and view.handle then Sprites().prime(view.handle.version, mons) end
end

local function refreshTrade(imp, c)
  local tr = imp._online and imp._online.trade
  if c.dirty.trade then
    c.dirty.trade = false
    c.tradeSlots = OnlinePanel.tradeSlots(imp)
  end
  if not tr then return end
  for _, side in ipairs({ "a", "b" }) do
    local view = OnlinePanel.tradeSideView(imp, side)
    local handle = view and view.handle or nil
    local picked = OnlinePanel.tradePickKey(imp, side)
    local rows = {}
    if handle then
      for index, mon in ipairs(handle.party or {}) do
        local key = OnlinePanel.refKey({ where = "party", index = index })
        rows[#rows + 1] = { ref = index, key = key,
          label = OnlinePanel.monLabel(mon, handle.version),
          mon = mon, version = handle.version, source = Strings("Party"),
          picked = picked == key, pickable = not mon.isEgg }
      end
      local pick = tr.picks[side]
      if type(pick) == "table" and pick.where == "box" then
        local row = OnlinePanel.tradeBoxRow(handle, pick)
        if row then rows[#rows + 1] = row end
      end
    end
    c.tradeRows[side] = rows
  end
  refreshTradePc(imp, c)
end

function OnlinePanel.refresh(imp)
  local c = OnlinePanel.cache(imp)
  local key = OnlinePanel.selectionKey(imp)
  if key ~= c.selKey then
    c.selKey = key
    c.dirty.slots, c.dirty.carts = true, true
    c.dirty.party, c.dirty.summary, c.dirty.lobby = true, true, true
  end
  refreshCarts(imp, c)
  refreshSlots(imp, c)
  refreshParty(imp, c)
  refreshSummary(imp, c)
  refreshLobby(imp, c)
  refreshTrade(imp, c)
  return c
end

-- ------------------------------------------------------------------ route

local function route(imp)
  local st = OnlinePanel.state(imp)
  local room = Client().room()
  local tour = Client().tournament()
  local key = (tour and ("T" .. tostring(tour.tour or tour.code)))
    or (room and ("R" .. tostring(room.room)))
    or nil
  if key == st.routeKey then return end
  st.routeKey = key
  if room and type(room.profile) == "table" then
    OnlinePanel.alignToProfile(imp, room.profile, true)
  end
  if tour then
    OnlinePanel.go(imp, "tournament")
  elseif room then
    local tr = st.trade
    if room.intent == "trade" and tr and tr.remote then
      OnlinePanel.go(imp, "trade")
    else
      OnlinePanel.go(imp, "room")
    end
  else
    local stack = OnlinePanel.nav(imp)
    while #stack > 1 and (stack[#stack] == "room"
        or stack[#stack] == "tournament") do
      table.remove(stack)
    end
  end
end

function OnlinePanel.update(imp, dt)
  local st = imp._online
  if not st then return end
  ensureHooks()
  local notice = Connect.takeNotice()
  if notice then st.status, st.statusOk = notice, false end
  OnlinePanel.drainEvents(imp)
  if st.profileWant and not st.profiles[st.profileWant] then
    OnlinePanel.computeProfile(imp, st.profileWant)
  else
    OnlinePanel.pumpLobbyProfiles(imp)
  end
  OnlinePanel.pruneInvites(imp)
  if OnlinePanel._discordInvite then
    local token = OnlinePanel._discordInvite
    OnlinePanel._discordInvite = nil
    OnlinePanel.deepLink(imp, { invite = token }, "player")
  end
  if st.inviteJoin and Connect.state() == "online" then
    OnlinePanel.joinByInvite(imp)
  elseif st.inviteJoin and nowSeconds() - (st.inviteJoin.at or 0)
      > OnlinePanel.JOIN_WAIT then
    st.inviteJoin = nil
    st.status, st.statusOk = Strings("Couldn't reach the lobby to join."), false
  end
  local presence = Presence()
  if presence and not st.discordArmed and not presence.launcherArmed
      and Connect.state() == "online" then
    st.discordArmed = true
    OnlinePanel.armDiscord()
  end
  if presence and type(presence.update) == "function"
      and presence.launcherArmed then
    pcall(presence.update, dt)
  end
  if st.convertWant then
    OnlinePanel.computeConverted(imp, st.convertWant)
  end
  OnlinePanel.primeSprites(imp)
  if type(imp.pumpOnlineCartInstall) == "function" then
    pcall(imp.pumpOnlineCartInstall, imp)
  end
  OnlinePanel.pumpRemoteTrade(imp, dt)
  if OnlinePanel._tourClosed then
    st.status, st.statusOk = OnlinePanel._tourClosed, false
    OnlinePanel._tourClosed = nil
  end
  if OnlinePanel._roomLost then
    local notice = OnlinePanel._roomLost
    OnlinePanel._roomLost = nil
    st.ready, st.confirmLeave = false, nil
    OnlinePanel.go(imp, "play")
    st.status, st.statusOk = notice, false
  end
  if OnlinePanel._joinError then
    st.status, st.statusOk = tostring(OnlinePanel._joinError), false
    OnlinePanel._joinError = nil
  end
  if st.joinWant then
    local want = st.joinWant
    if OnlinePanel.myProfile(imp) then
      st.joinWant = nil
      if OnlinePanel.joinRoom(imp, want.room, want.as, want.pin) then
        if st.wizard then finishTo(imp, "room") else OnlinePanel.go(imp, "room") end
      end
    elseif nowSeconds() > (want.at or 0) then
      st.joinWant = nil
      st.status, st.statusOk =
        Strings("Couldn't read your game, so the join was not sent."), false
    end
  end
  if st.pending and not st.pending.done and st.pending.at
      and nowSeconds() - st.pending.at > OnlinePanel.JOIN_WAIT then
    st.pending.error = Strings("The relay didn't answer.")
    st.pending.done = true
  end
  if st.pending and st.pending.done then
    local pending = st.pending
    st.pending = nil
    OnlinePanel.pendingDone(imp, pending)
  end
  local room = Client().room()
  local tour = Client().tournament()
  if tour then
    if st.hadRoom and OnlinePanel._presenceKey ~= nil then
      OnlinePanel.clearPresence()
    end
  elseif room then
    OnlinePanel.pushPresence(room)
  elseif st.hadRoom then
    OnlinePanel.clearPresence()
  end
  st.hadRoom = room ~= nil or tour ~= nil
  if st.roomPicked and not st.hadRoom and not st.pending
      and not st.joinWant then
    st.roomPicked = nil
  end
  local cartKey = room and tostring(room.room) or nil
  if cartKey ~= st.roomCartKey then
    st.roomCartKey = cartKey
    st.roomCart = room and OnlinePanel.cartNeed(room.profile) or nil
  end
  route(imp)
  OnlinePanel.autoReadyTrade(imp, room)
  OnlinePanel.refresh(imp)
  local start = OnlinePanel._pendingStart
  if start then
    if room and room.intent == "trade" then
      OnlinePanel._pendingStart = nil
      OnlinePanel.beginRemoteTrade(imp, start)
    elseif imp.playArena then
      OnlinePanel._pendingStart = nil
      local spec, err = OnlinePanel.buildSpec(imp, start)
      if spec then
        OnlinePanel.lastResult = nil
        local cartId = st.cartId
        if OnlinePanel.crossGen(imp) or tonumber(start.engine) == 3 then cartId = nil end
        imp:playArena(OnlinePanel.arenaVersion(imp, start), cartId, spec)
      else
        st.status, st.statusOk = tostring(err), false
        if tonumber(start.engine) == 3 then
          pcall(function() Client().leaveRoom() end)
        end
      end
    end
  end
end

function OnlinePanel.arenaVersion(imp, start)
  if type(start) == "table" and tonumber(start.engine) == 3 then
    local version = OnlinePanel.selectedVersion(imp)
    if version and GameVersion.generation(version) == 3 then return version end
    return OnlinePanel.engineVersionFor(imp, 3)
  end
  return OnlinePanel.engineVersion(imp)
end

function OnlinePanel.autoReadyTrade(imp, room)
  local st = OnlinePanel.state(imp)
  if not room or room.intent ~= "trade" then return false end
  if tonumber(room.engine) == 3 then return false end
  if st.trade and st.trade.remote then return false end
  if room.stage ~= "waiting" and room.stage ~= "ready" then return false end
  local players = room.players or {}
  if #players < 2 then return false end
  local you = type(Client().you) == "function" and Client().you() or nil
  local me = you and you.id
  local mine
  for _, p in ipairs(players) do
    if me ~= nil and p.id == me then mine = p end
  end
  if not mine or mine.ready then return false end
  local now = (love and love.timer and love.timer.getTime and love.timer.getTime())
    or os.time()
  if (st.autoReadyAt or 0) > now then return false end
  st.autoReadyAt = now + 3
  return OnlinePanel.sendReady(imp)
end

function OnlinePanel.alignToProfile(imp, p, soft)
  local st = OnlinePanel.state(imp)
  if type(p) ~= "table" or not p.version then return false end
  if tonumber(p.engine) == 3 and OnlinePanel.formatKnown(p.rulesetId) then
    st.ruleset = p.rulesetId
  end
  if tonumber(p.engine) == 3 then
    local current = OnlinePanel.selectedVersion(imp)
    if current and GameVersion.generation(current) == 3 then
      st.roomPicked = true
      return true
    end
  end
  if tonumber(p.engine) == 3 and not (imp.ready and imp.ready[p.version]) then
    local other = OnlinePanel.engineVersionFor(imp, 3)
    if other then
      local copy = {}
      for k, v in pairs(p) do copy[k] = v end
      copy.version = other
      p = copy
    end
  end
  if not (imp.ready and imp.ready[p.version]) then return false end
  local kind = p.kind or "vanilla"
  local cartId = p.cart and p.cart.id or nil
  if soft then
    local current = OnlinePanel.selectedVersion(imp)
    if current and GameVersion.generation(current)
        == GameVersion.generation(p.version) then
      return true
    end
  end
  st.roomPicked = true
  if p.version ~= st.version or kind ~= st.kind or cartId ~= st.cartId then
    st.version, st.kind, st.cartId = p.version, kind, cartId
    st.slotId, st.team, st.slotRead, st.ready = nil, {}, nil, false
    OnlinePanel.invalidate(imp)
  end
  return true
end

function OnlinePanel.alignToRoom(imp, roomId)
  local entry = OnlinePanel.findEntry("room", roomId)
  if not entry then return false end
  return OnlinePanel.alignToProfile(imp, entry.profile)
end

function OnlinePanel.spectate(imp, row)
  if type(row) ~= "table" then return false end
  local target = OnlinePanel.targetFor(row, "spectator")
  if not target then return false end
  if target.tournament then
    local st = OnlinePanel.state(imp)
    st.joinTarget = target
    local ok = OnlinePanel.joinTournament(imp, { tour = target.tour },
      "spectator")
    if ok then OnlinePanel.go(imp, "tournament") end
    return ok
  end
  OnlinePanel.alignToRoom(imp, target.room)
  return OnlinePanel.startJoin(imp, target, nil, "spectator")
end

OnlinePanel.JOIN_WAIT = 15

function OnlinePanel.roomRuleset(imp, roomId)
  local entry = OnlinePanel.findEntry("room", roomId)
  local p = entry and entry.profile or nil
  if type(p) == "table" and tonumber(p.engine) == 3 and type(p.rulesetId) == "string" then
    return p.rulesetId
  end
  local st = OnlinePanel.state(imp)
  local target = st.joinTarget
  if type(target) == "table" and target.room == roomId and target.engine == 3
      and type(target.rulesetId) == "string" then
    return target.rulesetId
  end
  local tr = st.trade
  if type(tr) == "table" and type(tr.target) == "table" and tr.target.room == roomId
      and OnlinePanel.isGen3(imp) then
    return OnlinePanel.TRADE_RULESET
  end
  return nil
end

function OnlinePanel.joinRoom(imp, roomId, as, pin)
  local st = OnlinePanel.state(imp)
  if type(roomId) ~= "string" or roomId == "" then
    st.joinWant = nil
    st.status, st.statusOk = Strings("That lobby is gone."), false
    return false
  end
  ensureHooks()
  local profile, reason = OnlinePanel.myProfile(imp)
  if not profile then
    st.joinWant = { room = roomId, as = as or "player", pin = pin,
                    at = nowSeconds() + OnlinePanel.JOIN_WAIT }
    st.status, st.statusOk = reason or Strings("Reading your game..."), false
    return false
  end
  local want = OnlinePanel.roomRuleset(imp, roomId)
  if want then profile = OnlinePanel.profileFor(imp, want) or profile end
  st.joinWant = nil
  OnlinePanel.pushProfile(profile, imp)
  st.pending = Client().joinRoom(roomId, as or "player", profile, pin)
  OnlinePanel.stampPending(st.pending)
  if type(st.pending) == "table" and pin then
    st.pending.pinTarget = st.joinTarget
  end
  return true
end

local PIN_REASONS = { bad_pin = true, pin_required = true, pin_locked = true }

function OnlinePanel.pendingDone(imp, pending)
  local st = OnlinePanel.state(imp)
  if not pending.error then return end
  if PIN_REASONS[pending.reason] then
    if OnlinePanel.screen(imp) == "room" and not Client().room() then
      OnlinePanel.go(imp, "play")
    end
    OnlinePanel.pinFailed(imp, pending)
    return
  end
  if OnlinePanel.retryTourRuleset(imp, pending) then
    OnlinePanel._joinError = nil
    st.status, st.statusOk = nil, false
    return
  end
  if pending.reason == "full" and pending.inviteToken
      and pending.inviteAs ~= "spectator" then
    st.inviteJoin = { token = pending.inviteToken, as = "spectator",
                      at = nowSeconds() }
    OnlinePanel.joinByInvite(imp)
    return
  end
  if OnlinePanel.screen(imp) == "room" and not Client().room() then
    OnlinePanel.go(imp, "play")
  end
  st.status, st.statusOk = tostring(pending.error), false
end

-- ---------------------------------------------------------------- screens

local SCREEN_MODULES = {
  home = "src.import.online.Home",
  play = "src.import.online.Play",
  wizard = "src.import.online.Wizard",
  room = "src.import.online.Room",
  watch = "src.import.online.Watch",
  tournament = "src.import.online.Tournaments",
  trade = "src.import.online.TradeScreen",
}

local function shotDemo(imp)
  if OnlinePanel._shotArmed then return end
  local want = os.getenv("POKEPORT_ONLINE_SHOT")
  if not want or want == "" then return end
  OnlinePanel._shotArmed = true
  local module = os.getenv("POKEPORT_ONLINE_SHOT_MODULE")
  if not module or not module:match("^tests%.drivers%.online_[%w_]+$") then
    module = "tests.drivers.online_shot"
  end
  local ok, demo = pcall(require, module)
  if ok and type(demo) == "function" then pcall(demo, OnlinePanel, imp, want) end
end

local function drawScreen(imp, id, x, y, w, availH, m, dx, atStep)
  local screen = require(SCREEN_MODULES[id] or SCREEN_MODULES.home)
  local wiz = atStep and OnlinePanel.wizard(imp) or nil
  local wasAt = wiz and wiz.at or nil
  if wiz then wiz.at = atStep end
  if dx ~= 0 then
    love.graphics.push()
    love.graphics.translate(dx, 0)
  end
  local h = screen.draw(imp, x, y, w, availH, m)
  if dx ~= 0 then love.graphics.pop() end
  if wiz then wiz.at = wasAt end
  return h
end

function OnlinePanel.buildOnlinePanel(imp, x, y, w, availH, m)
  OnlinePanel.state(imp)
  ensureHooks()
  shotDemo(imp)
  local id = OnlinePanel.screen(imp)
  local tr = Transition.get("online")
  if not tr then return drawScreen(imp, id, x, y, w, availH, m, 0, nil) end
  local p = Transition.progress("online")
  local dir = tr.dir >= 0 and 1 or -1
  if tr.from then
    pcall(drawScreen, imp, tr.from, x, y, w, availH, m, -dir * p * w,
      tr.fromAt)
  end
  return drawScreen(imp, id, x, y, w, availH, m, dir * (1 - p) * w, nil)
end

return OnlinePanel
