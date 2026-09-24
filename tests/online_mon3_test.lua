package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
if not _G.love then _G.love = require("tests.love_stub") end

local Cache = require("tests.game3_cache")
if not Cache.mount("meta.json") then
  print("[skip] online_mon3: " .. tostring(Cache.reason))
  os.exit(0)
end

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")
local Pokemon = require("src.core.game3.pokemon")
local Party = require("src.core.game3.party")
local SummaryData = require("src.core.game3.summary_data")
local Protocol = require("src.link.Protocol")
local Json = require("src.link.Json")
Pokemon.install(nil)
T.check(Pokemon._names ~= nil, "FireRed species tables load from the cache")

local DATA = { pokemon = Pokemon }
local STRICT = { strict = true }

local function copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = copy(v) end
  return out
end

local function wire(packed)
  return Json.decode(Json.encode(packed))
end

local session = { party = {}, name = "RED", trainerId = 24680, secretId = 1357, gender = 0 }
local function give(species, level, extra)
  local ok, _, mon = Party.giveMon(session, species, level)
  assert(ok and mon, "giveMon " .. tostring(species))
  for k, v in pairs(extra or {}) do mon[k] = v end
  Pokemon.applyStats(mon)
  session.party = {}
  return mon
end

local function hostile(base, edit)
  local p = copy(base)
  edit(p)
  return p
end

local function refused(packed, reason, label)
  local mon, why = Protocol.unpackMon3(DATA, packed, STRICT)
  T.eq(mon, nil, label .. " is refused")
  T.eq(why, reason, label .. " names " .. reason)
end

do
  local pika = give(25, 12, { item = 13, heldItem = 13, nickname = "SPARKY",
    evs = { hp = 4, atk = 10, def = 0, spe = 252, spa = 0, spd = 0 } })
  local packed = Protocol.packMon3(pika)
  local keys = { "species", "nickname", "level", "exp", "hp", "status", "personality",
    "otId", "otSecretId", "otName", "otGender", "nature", "ability", "gender", "ivs",
    "evs", "moves", "item", "friendship", "pokerus", "metLocation", "metLevel",
    "metGame", "pokeball", "ribbons", "markings", "isEgg", "fatefulEncounter",
    "eggCycles" }
  for _, key in ipairs(keys) do
    T.check(packed[key] ~= nil, "packMon3 always emits " .. key)
  end
  T.eq(packed.status, "", "a healthy mon's status is the empty string")
  T.eq(packed.item, 13, "the held item rides along")
  T.eq(packed.otSecretId, 1357, "the secret id rides along")

  local got, why = Protocol.unpackMon3(DATA, wire(packed), STRICT)
  T.check(got ~= nil, "a legit party mon survives a strict round trip: " .. tostring(why))
  T.eq(got.species, 25, "species")
  T.eq(got.level, 12, "level")
  T.eq(got.exp, pika.exp, "exp")
  T.eq(got.personality, pika.personality, "personality")
  T.eq(got.nickname, "SPARKY", "nickname")
  T.eq(got.otName, "RED", "OT name")
  T.eq(got.ot, "RED", "OT alias")
  T.eq(got.otId, 24680, "OT id")
  T.eq(got.nature, pika.nature, "nature")
  T.eq(got.gender, pika.gender, "gender")
  T.eq(got.ability, pika.ability, "ability")
  T.eq(got.abilityId, pika.ability, "ability id alias")
  T.same(got.ivs, pika.ivs, "IVs")
  T.same(got.evs, pika.evs, "EVs")
  T.same(got.moves, pika.moves, "move ids")
  T.same(got.pp, pika.pp, "PP")
  T.same(got.maxPp, pika.maxPp, "max PP")
  T.eq(got.item, 13, "item")
  T.eq(got.heldItem, 13, "heldItem alias")
  T.eq(got.maxHp, pika.maxHp, "max HP recomputed identically")
  T.eq(got.attack, pika.attack, "attack recomputed identically")
  T.eq(got.speed, pika.speed, "speed recomputed identically")
  T.eq(got.speciesNumbering, "internal", "internal numbering")
  T.eq(got.name, Pokemon.name(25), "name from the ROM")
  T.eq(got.status, nil, "empty status reads back as nil")
  T.eq(got.isEgg, false, "not an egg")
  T.check(got.stats and got.stats.hp == got.maxHp, "save_mon.normalize filled the stats block")

  local tampered = copy(packed)
  tampered.attack, tampered.maxHp = 999, 999
  local t2 = Protocol.unpackMon3(DATA, tampered, STRICT)
  T.eq(t2 and t2.attack, pika.attack, "wire stat fields are never read")

  local hurt = copy(packed)
  hurt.hp = 9999
  local h = Protocol.unpackMon3(DATA, hurt, STRICT)
  T.eq(h and h.hp, pika.maxHp, "hp is clamped to the computed max")

  local forced = Protocol.unpackMon3(DATA, packed, { strict = true, forceLevel = 50 })
  T.eq(forced and forced.level, 50, "forceLevel sets the level")
  T.eq(forced and forced.exp, SummaryData.expForLevel(Pokemon.growthRate(25), 50),
    "and the exp to that level's minimum")
  T.eq(forced and forced.hp, forced and forced.maxHp, "a forced level starts at full HP")
end

do
  local mon = give(64, 30)
  mon.moves = { [1] = 93, [3] = 60 }
  mon.pp = { [1] = 20, [3] = 22 }
  mon.maxPp = { [1] = 25, [3] = 22 }
  mon.item, mon.heldItem = nil, nil
  local packed = Protocol.packMon3(mon)
  T.eq(#packed.moves, 2, "a move list with a hole packs dense")
  T.eq(packed.moves[1].id, 93, "first move")
  T.eq(packed.moves[2].id, 60, "second move closes the gap")
  T.eq(packed.moves[1].ppUps, 0, "PP ups inferred from max PP")
  T.eq(packed.item, 0, "no held item packs as 0")
  local encoded = Json.encode(packed)
  T.check(encoded:find('"item":0', 1, true) ~= nil, "and item survives JSON")
  local back = Json.decode(encoded)
  T.eq(#back.moves, 2, "no hole truncates the JSON array")

  local up = give(64, 30)
  up.moves = { 93 }
  local base = Pokemon.movePp(93)
  up.ppBonusesPacked = 3
  up.pp = { base + math.floor(base * 20 * 3 / 100) }
  up.maxPp = { base + math.floor(base * 20 * 3 / 100) }
  local upPacked = Protocol.packMon3(up)
  T.eq(upPacked.moves[1].ppUps, 3, "packed PP bonuses ride as ppUps")
  local upGot = Protocol.unpackMon3(DATA, wire(upPacked), STRICT)
  T.eq(upGot and upGot.maxPp[1], up.maxPp[1], "PP Max survives the trip")
  T.eq(upGot and upGot.ppBonusesPacked, 3, "into the engine's packed bonuses")
end

do
  local egg
  local ok, _, got = Party.giveEgg(session, 175)
  egg = got
  session.party = {}
  T.check(ok and egg ~= nil, "a Togepi egg is made")
  egg.eggCycles = 10
  local packed = Protocol.packMon3(egg)
  T.eq(packed.isEgg, true, "the egg flag rides along")
  T.eq(packed.eggCycles, 10, "with its cycles")
  local back, why = Protocol.unpackMon3(DATA, wire(packed), STRICT)
  T.check(back ~= nil, "a legit egg survives a strict trip: " .. tostring(why))
  T.eq(back and back.isEgg, true, "still an egg")

  refused(hostile(packed, function(p) p.moves[1] = { id = 354, pp = 5, ppUps = 0 } end),
    "bad egg", "an egg knowing PSYCHO BOOST")
  local mewtwo = hostile(packed, function(p)
    p.species = 150
    p.gender = "U"
    p.ability = Pokemon.abilities(150)[1]
    p.moves = { { id = 93, pp = 25, ppUps = 0 } }
    p.exp = SummaryData.expForLevel(Pokemon.growthRate(150), p.level)
  end)
  refused(mewtwo, "bad egg", "a Mewtwo egg")
  local pika = give(25, 5)
  local pikaEgg = Protocol.packMon3(pika)
  pikaEgg.isEgg, pikaEgg.eggCycles = true, 10
  pikaEgg.level, pikaEgg.exp = 5, SummaryData.expForLevel(Pokemon.growthRate(25), 5)
  refused(pikaEgg, "bad egg", "a Pikachu egg, which only Pichu hatches from")
end

do
  local Breeding = require("src.core.game3.breeding")
  local noIncense = { mons = {} }
  for _, pair in ipairs({ { 350, 183, "MARILL" }, { 360, 202, "WOBBUFFET" } }) do
    local species = Breeding.alterEggSpeciesWithIncenseItem(pair[1], noIncense)
    T.eq(species, pair[2], "without incense the cart breeds a " .. pair[3] .. " egg")
    local ok, _, egg = Party.giveEgg(session, species)
    session.party = {}
    T.check(ok and egg ~= nil, "a " .. pair[3] .. " egg is made")
    local back, why = Protocol.unpackMon3(DATA, wire(Protocol.packMon3(egg)), STRICT)
    T.check(back ~= nil, "a bred " .. pair[3] .. " egg survives a strict trip: " .. tostring(why))
  end
  local marill = Protocol.packMon3(give(183, 5))
  local marillEgg = hostile(marill, function(p) p.isEgg, p.eggCycles = true, 10 end)
  T.check(Protocol.unpackMon3(DATA, wire(marillEgg), STRICT) ~= nil,
    "a MARILL egg passes the species rule")
  local pikaEgg = hostile(Protocol.packMon3(give(25, 5)), function(p)
    p.isEgg, p.eggCycles = true, 10
  end)
  refused(pikaEgg, "bad egg", "while other evolved-species eggs stay refused")
end

do
  local base = Protocol.packMon3(give(25, 20))
  refused("PIKACHU", "bad mon", "a string")
  refused(hostile(base, function(p) p.species = 0 end), "unknown species", "species 0")
  refused(hostile(base, function(p) p.species = 260 end), "unknown species", "an old Unown slot")
  refused(hostile(base, function(p) p.species = 412 end), "unknown species", "the egg species id")
  refused(hostile(base, function(p) p.species = 9999 end), "unknown species", "species 9999")
  refused(hostile(base, function(p) p.species = "PIKACHU" end), "unknown species", "a named species")
  refused(hostile(base, function(p) p.level = 0 end), "bad level", "level 0")
  refused(hostile(base, function(p) p.level = 101 end), "bad level", "level 101")
  refused(hostile(base, function(p) p.level = 100 end), "bad level", "level 100 on level 20 exp")
  refused(hostile(base, function(p) p.moves[1].id = 0 end), "bad move", "move 0")
  refused(hostile(base, function(p) p.moves[1].id = 355 end), "bad move", "move 355")
  refused(hostile(base, function(p) p.moves = {} end), "bad move", "no moves")
  refused(hostile(base, function(p)
    p.moves = { p.moves[1], copy(p.moves[1]) }
  end), "bad move", "a duplicate move")
  refused(hostile(base, function(p) p.moves[1].pp = 99 end), "bad move", "PP over the max")
  refused(hostile(base, function(p) p.moves[1].ppUps = 4 end), "bad move", "four PP ups")
  refused(hostile(base, function(p)
    for i = 1, 5 do p.moves[i] = { id = i, pp = 1, ppUps = 0 } end
  end), "bad move", "five moves")
  refused(hostile(base, function(p) p.item = 375 end), "bad item", "item 375")
  refused(hostile(base, function(p) p.item = -1 end), "bad item", "item -1")
  refused(hostile(base, function(p) p.ivs.atk = 32 end), "bad ivs", "an IV of 32")
  refused(hostile(base, function(p) p.evs.spe = 256 end), "bad evs", "an EV of 256")
  refused(hostile(base, function(p)
    p.evs = { hp = 255, atk = 255, def = 1, spe = 0, spa = 0, spd = 0 }
  end), "bad evs", "511 total EVs")
  refused(hostile(base, function(p) p.nature = (p.nature + 1) % 25 end),
    "nature mismatch", "a nature the personality can't give")
  refused(hostile(base, function(p) p.gender = p.gender == "M" and "F" or "M" end),
    "gender mismatch", "a flipped gender")
  refused(hostile(base, function(p) p.ability = 1 end), "bad ability", "STENCH on Pikachu")
  refused(hostile(base, function(p) p.otName = "ABCDEFGH" end), "bad ot", "an 8-letter OT")
  refused(hostile(base, function(p) p.otId = 70000 end), "bad ot", "an OT id past 65535")
  refused(hostile(base, function(p) p.otGender = 2 end), "bad ot", "OT gender 2")
  refused(hostile(base, function(p) p.nickname = "ABCDEFGHIJK" end), "bad nickname",
    "an 11-letter nickname")
  refused(hostile(base, function(p) p.nickname = "A\nB" end), "bad nickname",
    "a nickname with a control character")

  local accent = Protocol.unpackMon3(DATA, hostile(base, function(p) p.nickname = "POKéMONéé" end),
    STRICT)
  T.eq(accent and accent.nickname, "POKéMONéé", "names count characters, not bytes")

  local loose = Protocol.unpackMon3(DATA, hostile(base, function(p)
    p.ivs.atk, p.level, p.item = 40, 150, 999
  end), { strict = false })
  T.eq(loose and loose.ivs.atk, 31, "non-strict clamps an IV")
  T.eq(loose and loose.level, 100, "and a level")
  T.eq(loose and loose.item, 374, "and an item")
  local unknown, why = Protocol.unpackMon3(DATA, hostile(base, function(p) p.species = 9999 end),
    { strict = false })
  T.eq(unknown, nil, "non-strict still refuses an unknown species")
  T.eq(why, "unknown species", "by name")
end

do
  local failures, total = {}, 0
  for species = 1, 411 do
    if Pokemon.isInternalSpecies(species) then
      for _, level in ipairs({ 1, 5, 37, 100 }) do
        total = total + 1
        local packed = Protocol.packMon3(give(species, level))
        local got, why = Protocol.unpackMon3(DATA, wire(packed), STRICT)
        if not got then failures[#failures + 1] = ("%d@%d:%s"):format(species, level, why) end
      end
    end
  end
  T.check(total > 1500, "the sweep covers every species")
  T.eq(#failures, 0, "every species at every level round-trips strictly: "
    .. table.concat(failures, " ", 1, math.min(#failures, 8)))
end

do
  T.eq(Protocol.canonical({ b = 1, a = { 2, 3 }, c = "x\"y" }), '{"a":[2,3],"b":1,"c":"x\\"y"}',
    "canonical JSON sorts keys and escapes like Json")
  T.eq(Protocol.canonical({ n = 2.9, t = true, f = false, e = {} }),
    '{"e":[],"f":false,"n":2,"t":true}', "integers only, booleans, empty tables as arrays")
  local a = Protocol.packMon3(give(25, 20))
  local b = Protocol.packMon3(give(64, 30))
  local wa, wb = Protocol.wireMon3(a), Protocol.wireMon3(b)
  local d = Protocol.tradeDigest(wa, wb)
  T.check(type(d) == "string" and d:match("^[0-9a-f]+$") and #d == 16, "the digest is 16 hex")
  T.eq(Protocol.tradeDigest(wa, wb), d, "the digest is stable")
  T.check(Protocol.tradeDigest(wb, wa) ~= d, "seat order matters")
  T.eq(Protocol.tradeDigest(wire(wa), wire(wb)), d, "a JSON trip does not move it")
  T.eq(Protocol.tradeDigest(Protocol.wireMon3(wire(wa)), Protocol.wireMon3(wire(wb))), d,
    "nor does sanitizing it again on the far side")
  local other = copy(wa)
  other.personality = (other.personality + 1) % 4294967296
  T.check(Protocol.tradeDigest(other, wb) ~= d, "any field change moves the digest")
  T.eq(#Protocol.packParty3({ give(25, 5), give(1, 5), give(4, 5) }, { 3, 1 }), 2,
    "packParty3 packs the chosen slots")
end

T.finish()
