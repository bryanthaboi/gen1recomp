package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
if not _G.love then _G.love = require("tests.love_stub") end

local Cache = require("tests.game3_cache")
local frRoot = Cache.mount("meta.json")
if not frRoot then
  print("[skip] online_arena_data_gen3: " .. tostring(Cache.reason))
  os.exit(0)
end

local function exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

local function versionRoot(identity, version)
  local home = os.getenv("HOME") or ""
  for _, base in ipairs({ home .. "/Library/Application Support/LOVE/",
                          home .. "/.local/share/love/" }) do
    local root = base .. identity .. "/" .. version .. "/data/generated/gba"
    if exists(root .. "/meta.json") then return root end
  end
  return nil
end

local lgIdentity = os.getenv("POKEPORT_IDENTITY_LG")
local ROOTS = {
  firered = frRoot,
  leafgreen = lgIdentity and versionRoot(lgIdentity, "leafgreen") or nil,
}

local stubRead = love.filesystem.read
love.filesystem.read = function(name)
  for version, root in pairs(ROOTS) do
    local rel = name:match("^" .. version .. "/data/generated/gba/(.*)$")
    if rel then
      local f = io.open(root .. "/" .. rel, "rb")
      if not f then return nil end
      local body = f:read("*a")
      f:close()
      return body
    end
  end
  return stubRead(name)
end

local files = {}
local memfs = {
  getInfo = function(name) return files[name] and { type = "file" } or nil end,
  read = function(name) return files[name] end,
  write = function(name, body) files[name] = body return true end,
  remove = function(name) files[name] = nil return true end,
  createDirectory = function() return true end,
  getDirectoryItems = function() return {} end,
}
local SaveData = require("src.core.SaveData")
SaveData.portableFs = function() return memfs end

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")
local ArenaData = require("src.online.ArenaData")
local ArenaBoot = require("src.online.ArenaBoot")
local TeamPick = require("src.online.TeamPick")
local Protocol2 = require("src.online.Protocol2")
local Pokemon = require("src.core.game3.pokemon")
local Party = require("src.core.game3.party")
local Schema = require("src.core.game3.save_schema_firered")
local Trade = require("src.online.Trade")
Pokemon.install(nil)

local fr, why = ArenaData.profile("firered", "vanilla", nil, { partySize = 6 })
T.check(fr ~= nil, "FireRed has an arena profile: " .. tostring(why))
T.eq(fr and fr.engine, 3, "engine 3")
T.eq(fr and fr.kind, "vanilla", "vanilla")
T.eq(fr and fr.rulesetId, "g3_single", "g3_single by default")
T.eq(fr and fr.rule.partySize, 6, "the rule rides along")
T.check(fr and type(fr.fingerprint) == "string" and #fr.fingerprint == 16,
  "a real Gen 3 fingerprint")
T.eq(GameVersion.get(), "firered", "the active version is restored")

local double = ArenaData.profile("firered", "vanilla", nil, nil, "g3_double")
T.eq(double and double.rulesetId, "g3_double", "a ruleset can be asked for")
T.eq(double and double.fingerprint, fr and fr.fingerprint, "from the cached entry")
local bad, badWhy = ArenaData.profile("firered", "vanilla", nil, nil, "gen1_faithful")
T.eq(bad, nil, "a Gen 1 ruleset is not a Gen 3 one")
T.eq(badWhy, "unknown ruleset", "and says so")
local cart, cartWhy = ArenaData.profile("firered", "cart", "kanto_plus")
T.eq(cart, nil, "no cart arenas for Gen 3")
T.eq(cartWhy, "that game has no online carts", "and says so")
T.same(ArenaData.rulesetIds("firered"), Protocol2.G3_RULESETS, "Gen 3 rulesets come from Protocol2")
T.eq(ArenaData.rulesetFor("battle_multi"), "g3_multi", "a multi battle uses g3_multi")
T.eq(ArenaData.rulesetFor("trade"), "g3_link", "a trade uses g3_link")
local multi = ArenaData.withRuleset(fr, "g3_multi")
T.eq(multi.rulesetId, "g3_multi", "withRuleset swaps the ruleset")
T.eq(fr.rulesetId, "g3_single", "on a copy")
T.eq(multi.fingerprint, fr.fingerprint, "keeping the fingerprint")

local live, liveWhy = ArenaData.liveProfile3({ data = { generation = 3 }, version = "firered" })
T.check(live ~= nil, "a vanilla live game has a profile: " .. tostring(liveWhy))
T.check(ArenaData.equal(live, ArenaData.profile("firered", "vanilla", nil, nil)),
  "the live profile equals the launcher's")
local modded = { data = { generation = 3 }, version = "firered",
  mods = { status = function()
    return { loaded = { { id = "rebalance", version = "1.0", affects_link = true } } }
  end, content = {} } }
local none, modWhy = ArenaData.liveProfile3(modded)
T.eq(none, nil, "a link-modded game has no profile")
T.eq(modWhy, "mods", "and says mods")
local lang = { data = { generation = 3 }, version = "firered",
  mods = { status = function()
    return { loaded = { { id = "espanol", version = "1.0", affects_link = false,
      language = true } } }
  end, content = {} } }
local langProfile = ArenaData.liveProfile3(lang, "g3_link")
T.check(langProfile ~= nil and langProfile.fingerprint == fr.fingerprint,
  "a translation leaves the fingerprint alone")

if ROOTS.leafgreen then
  local lg = ArenaData.profile("leafgreen", "vanilla", nil, nil)
  T.eq(lg and lg.fingerprint, fr.fingerprint, "LeafGreen's profile hashes like FireRed's")
  T.check(ArenaData.equal(lg, fr), "and the two profiles match (version is not compared)")
else
  print("[skip] LeafGreen half: set POKEPORT_IDENTITY_LG")
end

do
  local session = Schema.newGame({ version = "firered", name = "RED", rngSeed = 5 })
  session.trainerId = 4242
  session.party = {}
  assert(Party.giveMon(session, 25, 20))
  assert(Party.giveMon(session, 1, 15))
  local Storage = require("src.core.game3.storage")
  local _, _, boxed = Party.giveMon({ party = {}, name = "RED", trainerId = 4242 }, 6, 50)
  local _, _, boxedEgg = Party.giveEgg({ party = {}, name = "RED", trainerId = 4242 }, 175)
  session.storage = session.storage or Storage.new()
  session.storage.boxes[2].mons[5] = boxed
  session.storage.boxes[2].name = "FIRE"
  session.storage.boxes[3].mons[30] = boxedEgg
  local save = Schema.toSaveTable(session)
  files[Trade.slotPath("firered", "slot1")] = SaveData.encode(save)

  local slot, slotWhy = TeamPick.readSlot("firered", "slot1")
  T.check(slot ~= nil, "a FireRed slot reads: " .. tostring(slotWhy))
  T.eq(slot and slot.generation, 3, "as Gen 3")
  T.eq(slot and slot.trainerName, "RED", "with the trainer name")
  T.eq(slot and #slot.party, 2, "and its party")
  local rows = TeamPick.candidates(slot)
  T.eq(#rows, 4, "candidates are the party plus every boxed mon")
  T.eq(rows[3].where, "box", "boxes follow the party")
  T.eq(rows[3].box, 2, "in box order")
  T.eq(rows[3].index, 5, "keeping the slot inside a sparse box")
  T.eq(rows[3].source, "FIRE", "named by the player's box name")
  T.eq(rows[4].index, 30, "the last slot of a box is reached")
  T.eq(rows[4].source, "BOX 3", "an unnamed box reads BOX n")
  local team = { { where = "box", box = 2, index = 5 }, 1 }
  T.eq(TeamPick.validate(slot, team, { partySize = 2 }), true, "a mixed team validates")
  T.eq(TeamPick.validate(slot, { { where = "box", box = 3, index = 30 } }, { partySize = 1 }),
    false, "an egg can't battle")
  local packed = TeamPick.pack(slot, team, 3)
  T.eq(#packed, 2, "a mixed team packs")
  T.eq(packed[1].species, 6, "the boxed Charizard first")
  T.eq(packed[2].species, 25, "then the party Pikachu")
  T.eq(packed[1].item, 0, "item always present")

  local spec, specWhy = ArenaBoot.spec({
    profile = ArenaData.withRuleset(fr, "g3_single"),
    role = "guest", seat = 1, seats = 2, slotId = "slot1", team = team, seed = 7,
    match = "r0123456789abcdef-m1", room = "r0123456789abcdef",
    players = { { id = "b", name = "LEAF", seat = 1 }, { id = "a", name = "RED", seat = 0 } },
    myParty = packed,
    session = { send = function() end, poll = function() return {} end, close = function() end },
  })
  T.check(spec ~= nil, "an engine 3 arena spec validates: " .. tostring(specWhy))
  T.eq(spec and spec.mode, "single", "mode from the ruleset")
  T.eq(spec and spec.seat, 1, "seat kept")
  T.eq(spec and spec.players[1].seat, 0, "players sorted by seat")
  T.eq(spec and ArenaBoot.packOwnParty(nil, spec), packed, "myParty is used as sent")
  local multiSpec = ArenaBoot.spec({
    profile = ArenaData.withRuleset(fr, "g3_multi"), role = "seat3", seat = 3, seats = 4,
    slotId = "slot1", seed = 7,
    session = { send = function() end, poll = function() return {} end, close = function() end },
  })
  T.eq(multiSpec and multiSpec.mode, "multi", "a 4-seat multi spec validates")
  local wrong = ArenaBoot.spec({
    profile = ArenaData.withRuleset(fr, "g3_multi"), role = "guest", seat = 1, seats = 2,
    slotId = "slot1", seed = 7,
    session = { send = function() end, poll = function() return {} end, close = function() end },
  })
  T.eq(wrong, nil, "a 2-seat multi is refused")
  local linkSpec = ArenaBoot.spec({
    profile = ArenaData.withRuleset(fr, "g3_link"), role = "host", seat = 0, seats = 2,
    slotId = "slot1", seed = 7,
    session = { send = function() end, poll = function() return {} end, close = function() end },
  })
  T.eq(linkSpec, nil, "g3_link is not a battle arena")
  local own = ArenaBoot.packOwnParty({ session = { party = session.party } },
    { profile = fr, role = "host", team = { 2 } })
  T.eq(own and #own, 1, "packOwnParty packs the chosen Gen 3 mons")
  T.eq(own and own[1].species, 1, "as packMon3")
  local missing, missingWhy = ArenaBoot.packOwnParty({ session = { party = session.party } },
    { profile = fr, role = "host", team = { 1, { where = "box", box = 1, index = 1 } } })
  T.eq(missing, nil, "a team ref the save can't resolve sends nothing")
  T.eq(missingWhy, "that team isn't in this save", "and says why instead of sending party slots")
end

T.finish()
