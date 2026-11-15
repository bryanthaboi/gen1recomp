-- The six Gen 2-only content registries, end to end: held_items,
-- phone_contacts, decorations, apricorns, landmarks and radio_channels.
--
-- Three claims, and the third is the one that makes the other two worth
-- anything:
--
--   1. the routing is symmetrical.  Schemas.GEN2 says where a shared registry
--      lands on Gold; Schemas.GEN1 is its mirror, and these six are gated
--      under GEN ONE -- Red has no phone, no radio and no held items, so a
--      write there is taken, dropped and reported rather than merged into a
--      namespace nothing on Red would read.
--   2. the vanilla records are the literals they replaced, byte for byte.  A
--      registry that seeds a different record than the module used to hold is
--      a behaviour change wearing a refactor's clothes.
--   3. the CONSUMER reads through the registry.  A registry nothing reads is
--      the silent no-op this whole design exists to prevent, so each one is
--      driven from a mod's own registration through to the routine the game
--      calls: Decorations.attributes, Phone.CONTACTS, Apricorns.ballFor,
--      Nests.landmarkId, MapRadio.channelRecord and, for held_items, the
--      write-back onto data.items that src/battle/gen2/Battle.lua:heldEffect
--      reads.
--
-- ROM-free: the generation is injected through the loader (T.sdk.loadMods
-- opts.generation), the way tests/engine/gate_gen2_mod_api.lua does.

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Schemas = require("src.mods.Schemas")
local ItemEffects = require("src.core.gen2.ItemEffects")
local Phone = require("src.core.gen2.Phone")
local Decorations = require("src.core.gen2.Decorations")
local Apricorns = require("src.core.gen2.Apricorns")
local Nests = require("src.core.gen2.Nests")
local MapRadio = require("src.ui.gen2.MapRadio")
local Pokegear = require("src.ui.gen2.Pokegear")

local NAMES = { "held_items", "phone_contacts", "decorations", "apricorns",
                "landmarks", "radio_channels" }

local PATHS = {
  held_items = "gen2HeldItems",
  phone_contacts = "gen2PhoneContacts",
  decorations = "gen2Decorations",
  apricorns = "gen2Apricorns",
  landmarks = "gen2Landmarks.landmarks",
  radio_channels = "gen2RadioChannels",
}

-- ------- 1. the mirror of Schemas.GEN2

for _, name in ipairs(NAMES) do
  local spec = Schemas.REGISTRIES[name]
  T.check(spec ~= nil, "the catalog declares it: " .. name)
  T.eq(spec.target, nil,
    "a Gen 2-only registry carries no Gen 1 target: " .. name)
  T.eq(Schemas.targetFor(name, spec, 1), nil,
    "and none is invented for Gen 1: " .. name)
  T.eq(Schemas.gatedFor(name, 1), true, "gated under Gen 1: " .. name)
  T.eq(Schemas.targetFor(name, spec, 2), PATHS[name],
    "routed to its Gen 2 path: " .. name)
  T.eq(Schemas.gatedFor(name, 2), false, "not gated under Gen 2: " .. name)
  T.check(spec.example ~= nil, "and documents a call: " .. name)
end

-- the mirror holds in the other direction too: nothing shared is gated under
-- Gen 1, which is what would break if a routing row were put in the wrong
-- table
for name, spec in pairs(Schemas.REGISTRIES) do
  if Schemas.GEN1[name] == nil then
    T.eq(Schemas.targetFor(name, spec, 1), spec.target,
      "a registry with no Gen 1 routing row keeps its target: " .. name)
    T.eq(Schemas.gatedFor(name, 1), false,
      "and is not gated under Gen 1: " .. name)
  end
end

for name in pairs(Schemas.GEN1) do
  T.check(Schemas.REGISTRIES[name] ~= nil,
    "Schemas.GEN1 names a real registry: " .. name)
end

-- ------- the Gen 2 dataset these merge into
--
-- data.gen2Constants.phoneContactOrder is the phone id space, verbatim from
-- the ROM manifest (the four PHONE_UNUSED rows are the const_skip holes).
local PHONE_ORDER = {
  "PHONE_00", "PHONE_MOM", "PHONE_OAK", "PHONE_BILL", "PHONE_ELM",
  "PHONE_SCHOOLBOY_JACK", "PHONE_POKEFAN_BEVERLY", "PHONE_SAILOR_HUEY",
  "PHONE_UNUSED", "PHONE_UNUSED", "PHONE_UNUSED",
  "PHONE_COOLTRAINERM_GAVEN", "PHONE_COOLTRAINERF_BETH",
  "PHONE_BIRDKEEPER_JOSE", "PHONE_COOLTRAINERF_REENA", "PHONE_YOUNGSTER_JOEY",
  "PHONE_BUG_CATCHER_WADE", "PHONE_FISHER_RALPH", "PHONE_PICNICKER_LIZ",
  "PHONE_HIKER_ANTHONY", "PHONE_CAMPER_TODD", "PHONE_PICNICKER_GINA",
  "PHONE_JUGGLER_IRWIN", "PHONE_BUG_CATCHER_ARNIE", "PHONE_SCHOOLBOY_ALAN",
  "PHONE_UNUSED", "PHONE_LASS_DANA", "PHONE_SCHOOLBOY_CHAD",
  "PHONE_POKEFANM_DEREK", "PHONE_FISHER_CHRIS", "PHONE_POKEMANIAC_BRENT",
  "PHONE_PICNICKER_TIFFANY", "PHONE_BIRDKEEPER_VANCE", "PHONE_FISHER_WILTON",
  "PHONE_BLACKBELT_KENJI", "PHONE_HIKER_PARRY", "PHONE_PICNICKER_ERIN",
}

-- two landmark records in the cache's own shape (index = the map header byte)
local function landmarkTable()
  return {
    order = { "LANDMARK_SPECIAL", "LANDMARK_FIX_TOWN" },
    landmarks = {
      LANDMARK_SPECIAL = { id = "LANDMARK_SPECIAL", name = "SPECIAL",
                           x = 0, y = 0, index = 0 },
      LANDMARK_FIX_TOWN = { id = "LANDMARK_FIX_TOWN", name = "FIX\nTOWN",
                            x = 4, y = 5, index = 1 },
    },
  }
end

local function goldData()
  local data = T.fixtures.fresh()
  -- an item that holds something, so held_items has a row to seed from
  data.items.FIX_LEFTOVERS = {
    id = "FIX_LEFTOVERS", index = 90, name = "FIX LEFTOVERS", price = 0,
    heldEffect = "HELD_LEFTOVERS", heldParameter = 0,
  }
  data.items.RED_APRICORN = { id = "RED_APRICORN", index = 91,
                              name = "RED APRICORN", price = 0 }
  data.items.LEVEL_BALL = { id = "LEVEL_BALL", index = 92, ball = true,
                            name = "LEVEL BALL", price = 0 }
  data.items.ULTRA_BALL = { id = "ULTRA_BALL", index = 93, ball = true,
                            name = "ULTRA BALL", price = 0 }
  -- the fixture maps under the key Gold keeps them at, so a contact's `map`
  -- resolves against the same id space src/world/gen2/World.lua walks
  data.gen2Maps = data.maps
  local PHONE = require("tests.fixtures.gen2_phone_events")
  data.gen2Constants = { phoneContactOrder = PHONE_ORDER,
    trainerClassOrder = PHONE.constants.trainerClassOrder,
    trainerClassMembers = PHONE.constants.trainerClassMembers,
    rematchFlags = PHONE.constants.rematchFlags }
  data.gen2EventTables = require("src.mods.Merge").deepCopy(PHONE.events)
  data.gen2Landmarks = landmarkTable()
  -- src/core/Game2.lua:load builds this before mods:load; the harness
  -- stands in for that boot step
  data.gen2HeldItems = ItemEffects.heldItemsFrom(data.items)
  data.text = data.text or {}
  for label, body in pairs(require("tests.fixture_data.gen2_rom_text_s7_g").text()) do
    data.text[label] = body
  end
  return data
end

local function memfsFor(body, extra)
  local manifest = [[{
    "id": "fix_gen2_content",
    "name": "Fixture Gen 2 Content",
    "version": "1.0.0",
    "entry": "main.lua",
    "api": 2,
    "gen2compat": true
  }]]
  local files = { ["mods/fix_gen2_content/manifest.json"] = manifest,
                  ["mods/fix_gen2_content/main.lua"] = body }
  for path, text in pairs(extra or {}) do files[path] = text end
  return T.sdk.memfs(files)
end

-- ------- 2. parity: the seeded record IS the literal
--
-- Compared field by field against the module's own table rather than against
-- a copy of it, so a record that gained or lost a key fails here.
local function sameRecord(got, want, label)
  if type(got) ~= "table" or type(want) ~= "table" then
    return T.eq(got, want, label)
  end
  local ok = true
  for key, value in pairs(want) do
    if got[key] ~= value then ok = false end
  end
  for key in pairs(got) do
    if want[key] == nil then ok = false end
  end
  return T.check(ok, label)
end

do
  local run = T.sdk.loadNone({ data = goldData(), generation = 2 })
  T.eq(#run.errors, 0, "a zero-mod Gold load reports no errors")

  local decorations = run.data.gen2Decorations
  T.check(decorations ~= nil, "the decorations merge target appears")
  local rows = 0
  for decoId, attr in pairs(Decorations.ATTRIBUTES) do
    rows = rows + 1
    sameRecord(decorations[Decorations.idFor(decoId)], attr,
      "vanilla decoration is the attribute row: deco:" .. decoId)
  end
  T.eq(rows, 53, "every attribute row is registered")

  local contacts = run.data.gen2PhoneContacts
  T.check(contacts ~= nil, "the phone_contacts merge target appears")
  Phone.useRegistry({ gen2EventTables = run.data.gen2EventTables,
    gen2Constants = run.data.gen2Constants })
  sameRecord(contacts.PHONE_YOUNGSTER_JOEY, Phone.CONTACTS[15],
    "vanilla contact is the PhoneContacts row: PHONE_YOUNGSTER_JOEY")
  sameRecord(contacts.PHONE_MOM, Phone.CONTACTS[1],
    "and the non-trainer rows too: PHONE_MOM")
  T.eq(contacts.PHONE_UNUSED, nil,
    "the const_skip holes are not registered under one shared id")

  local apricorns = run.data.gen2Apricorns
  T.check(apricorns ~= nil, "the apricorns merge target appears")
  sameRecord(apricorns.RED_APRICORN, Apricorns.row("RED_APRICORN"),
    "vanilla apricorn is the ApricornBalls row: RED_APRICORN")
  T.eq(apricorns.RED_APRICORN.ball, "LEVEL_BALL",
    "and it still hands back the LEVEL BALL")

  local channels = run.data.gen2RadioChannels
  T.check(channels ~= nil, "the radio_channels merge target appears")
  T.eq(channels.OAKS_POKEMON_TALK and channels.OAKS_POKEMON_TALK.channel, 1,
    "OAK's POKEMON TALK keeps its dial position")
  T.eq(channels.ROCKET_RADIO and channels.ROCKET_RADIO.channel, 8,
    "and ROCKET RADIO keeps its own")
  T.eq(channels.POKE_FLUTE_RADIO and channels.POKE_FLUTE_RADIO.name,
    "POKé FLUTE", "Pokegear-only stations are seeded in the same registry")

  -- held_items and landmarks merge onto a table that already existed, so the
  -- claim there is that the merge left it exactly as it found it
  T.eq(run.data.gen2HeldItems.FIX_LEFTOVERS.heldEffect, "HELD_LEFTOVERS",
    "the held_items view still holds the item's own effect")
  T.eq(ItemEffects.applyHeldItems(run.data,
         ItemEffects.heldSnapshot(run.data.gen2HeldItems)), 0,
    "and a mod-free merge writes nothing back onto data.items")
  T.eq(run.data.gen2Landmarks.landmarks.LANDMARK_FIX_TOWN.x, 4,
    "the landmark records are the cache's own")

  run.release()
end

-- ------- 3. the consumers, driven from a mod's registration

do
  local data = goldData()
  local run = T.sdk.loadMods({ "mods/fix_gen2_content" }, {
    fs = memfsFor([[
      local mod = ...
      -- an existing row edited, and a new one registered, for each registry
      mod.content.decorations:patch("deco:2", { name = "COZY" })
      mod.content.phone_contacts:patch("PHONE_YOUNGSTER_JOEY",
        { map = "FIX_ROUTE", name = "JOJO" })
      mod.content.apricorns:override("RED_APRICORN",
        { apricorn = "RED_APRICORN", ball = "ULTRA_BALL", event = 600,
          index = 1 })
      mod.content.landmarks:patch("LANDMARK_FIX_TOWN", { x = 9 })
      mod.content.landmarks:register("LANDMARK_MOD_ISLE",
        { id = "LANDMARK_MOD_ISLE", name = "MOD\nISLE", x = 1, y = 2,
          index = 7 })
      mod.content.radio_channels:register("PIRATE_RADIO",
        { channel = 9, name = "PIRATE RADIO" })
      mod.content.radio_channels:patch("POKE_FLUTE_RADIO",
        { name = "FLÛTE RADIO" })
      mod.content.held_items:patch("FIX_LEFTOVERS", { heldParameter = 7 })
    ]]),
    data = data,
    generation = 2,
  })
  T.eq(#run.errors, 0,
    "the mod loads clean (" .. table.concat(run.errors, "; ") .. ")")

  -- decorations: Decorations.attributes is the one read point every caller
  -- (and src/ui/gen2/DecorationMenu.lua) comes through
  Decorations.useRegistry(run.data)
  T.eq(Decorations.attributes(2).name, "COZY",
    "decorations: the merged row is what attributes() answers")
  T.eq(Decorations.attributes(2).flag, Decorations.ATTRIBUTES[2].flag,
    "and the fields the patch left alone are the cart's own")
  T.eq(Decorations.name(2, nil), "COZY BED",
    "so GetDecoName's port spells the merged row")

  -- phone: the merged rows are folded onto the contact table every lookup in
  -- src/core/gen2/Phone.lua keys by
  Phone.useRegistry(run.data)
  T.eq(Phone.CONTACTS[15].map, "FIX_ROUTE",
    "phone_contacts: the merged row reaches the contact table")
  T.eq(Phone.CONTACTS[15].class, "YOUNGSTER",
    "and the untouched fields survive the patch")
  T.eq(Phone.contactName(15, data.gen2Trainers), "JOJO",
    "and the registry's display name overrides trainer-table presentation")
  -- the cache overlay runs from src/world/gen2/World.lua AFTER this, and must
  -- not undo it
  Phone.useExtracted({ phone = { [15] = { map = "ROUTE_30",
                                          trainerClass = 22, number = 1,
                                          calleeTime = 7, callerTime = 7,
                                          callee = "41:0001",
                                          caller = "41:0002" } },
                       phoneScripts = {}, phoneNames = {}, specialCalls = {},
                       permanentNumbers = { 1, 4 } })
  T.eq(Phone.CONTACTS[15].map, "FIX_ROUTE",
    "and the cache overlay does not undo it")

  -- apricorns: Kurt hands back what the registry says he does
  Apricorns.useRegistry(run.data)
  T.eq(Apricorns.ballFor("RED_APRICORN"), "ULTRA_BALL",
    "apricorns: the merged row is the ball Kurt makes")
  T.eq(Apricorns.apricornFor("ULTRA_BALL"), "RED_APRICORN",
    "and the reverse lookup follows it")
  T.eq(#Apricorns.BALLS, 7, "the table is still the seven rows")
  T.eq(Apricorns.BALLS[1].apricorn, "RED_APRICORN",
    "in the ApricornBalls order the menu walks")

  -- landmarks: the registry answers the map header's byte, including for an
  -- index the extractor's `order` list has never heard of
  T.eq(Nests.landmarkId(run.data, 1), "LANDMARK_FIX_TOWN",
    "landmarks: a vanilla index still resolves")
  T.eq(Nests.landmark(run.data, 1).x, 9,
    "and the patch reaches the record the town map draws")
  T.eq(Nests.landmarkId(run.data, 7), "LANDMARK_MOD_ISLE",
    "a registered landmark resolves at its own index")
  -- and a registered landmark cannot shadow a vanilla one by claiming its
  -- byte: the cache's own row keeps its slot, so the answer does not depend
  -- on pairs() order.  A fresh table, because the index map is memoized per
  -- landmarks table and the run's is already built.
  local shadowed = landmarkTable()
  shadowed.landmarks.LANDMARK_AAA_SHADOW = {
    id = "LANDMARK_AAA_SHADOW", name = "AAA", x = 0, y = 0, index = 1,
  }
  T.eq(Nests.landmarkId({ gen2Landmarks = shadowed }, 1), "LANDMARK_FIX_TOWN",
    "a second record at a taken index does not displace the cache's own")
  local twoNew = landmarkTable()
  twoNew.landmarks.LANDMARK_MOD_B = { id = "LANDMARK_MOD_B", name = "B",
                                      x = 0, y = 0, index = 7 }
  twoNew.landmarks.LANDMARK_MOD_A = { id = "LANDMARK_MOD_A", name = "A",
                                      x = 0, y = 0, index = 7 }
  T.eq(Nests.landmarkId({ gen2Landmarks = twoNew }, 7), "LANDMARK_MOD_A",
    "and two registered records at one index resolve the same way every boot")

  -- radio: a registered station is on the dial
  local record, station = MapRadio.channelRecord(run.data, 9)
  T.eq(station, "PIRATE_RADIO", "radio_channels: the new station is on the dial")
  T.eq(record and record.name, "PIRATE RADIO", "with its own name")
  T.eq(select(2, MapRadio.channelRecord(run.data, 8)), "ROCKET_RADIO",
    "and the vanilla positions are unmoved")
  local gear = setmetatable({ game = { data = run.data } }, Pokegear)
  T.eq(gear:stationName("POKE_FLUTE_RADIO"), "FLÛTE RADIO",
    "and the Pokegear reads a patched built-in name from that same registry")

  -- held items: the merged row is written back onto the item record, which is
  -- what src/battle/gen2/Battle.lua:itemDef reads
  local applied = ItemEffects.applyHeldItems(run.data,
    ItemEffects.heldSnapshot({ FIX_LEFTOVERS = { heldEffect = "HELD_LEFTOVERS",
                                                 heldParameter = 0 } }))
  T.eq(applied, 1, "held_items: one item record changed")
  T.eq(run.data.items.FIX_LEFTOVERS.heldParameter, 7,
    "and the battle's own read sees the merged parameter")
  T.eq(run.data.items.FIX_LEFTOVERS.heldEffect, "HELD_LEFTOVERS",
    "with the effect the patch left alone")
  T.eq(ItemEffects.heldItemFor("FIX_LEFTOVERS", run.data).heldParameter, 7,
    "and heldItemFor answers from the merged table")

  run.release()
  -- module statics are process-wide; put them back before the next case
  Phone.useRegistry(nil)
  Decorations.useRegistry(nil)
end

-- A real loader keeps record semantics for the built-in radio ids: register
-- collides, while the patch above succeeds and preserves the untouched
-- channel.  This guards the distinction between content replacement and
-- localization at the consumer.
do
  local run = T.sdk.loadMods({ "mods/fix_gen2_content" }, {
    fs = memfsFor([[
      local mod = ...
      mod.content.radio_channels:register("POKE_FLUTE_RADIO",
        { channel = 7, name = "SHADOW" })
    ]]),
    data = goldData(), generation = 2,
  })
  local collided = false
  for _, message in ipairs(run.errors) do
    if message:find("radio_channels already registered: POKE_FLUTE_RADIO", 1,
        true) then collided = true end
  end
  T.check(collided, "registering over a built-in radio station is rejected")
  run.release()
end

-- ------- 4. the mirror case, through a real load
--
-- A Red boot takes the write, drops it and says so.  Not fatal: a mod that
-- supports both games registers its Gold content unconditionally and should
-- still load the half that applies.

do
  local run = T.sdk.loadMods({ "mods/fix_gen2_content" }, {
    fs = memfsFor([[
      local mod = ...
      mod.content.pokemon:patch("FIXMON_A", { catchRate = 77 })
      mod.content.decorations:patch("deco:2", { name = "COZY" })
      mod.content.radio_channels:register("PIRATE_RADIO", { channel = 9 })
    ]]),
    generation = 1,
  })
  T.eq(run.data.pokemon.FIXMON_A.catchRate, 77,
    "Gen 1: the shared registry still merged")
  T.eq(run.data.gen2Decorations, nil,
    "Gen 1: a Gen 2-only registry merges nothing")
  T.eq(run.data.decorations, nil,
    "Gen 1: and invents no namespace of its own")
  local told = {}
  for _, message in ipairs(run.errors) do
    if message:match("decorations") then told.decorations = true end
    if message:match("radio_channels") then told.radio = true end
  end
  T.check(told.decorations and told.radio,
    "Gen 1: both dropped registrations are reported, not silent")
  run.release()
end

T.finish("gen2_content_registries")
