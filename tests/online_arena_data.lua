package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
love = love or require("tests.love_stub")

local Loader = require("src.mods.Loader")
local CartManifest = require("src.carts.CartManifest")
local SaveData = require("src.core.SaveData")
local SaveSerializer = require("src.core.SaveSerializer")
local GameVersion = require("src.core.GameVersion")
local ArenaData = require("src.online.ArenaData")
local TeamPick = require("src.online.TeamPick")

local function memfs(files)
  return {
    files = files,
    read = function(path) return files[path] end,
    write = function(path, content) files[path] = content return true end,
    remove = function(path) files[path] = nil return true end,
    getInfo = function(path)
      if files[path] then return { type = "file" } end
      local prefix = path .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then return { type = "directory" } end
      end
      return nil
    end,
    load = function(path)
      if not files[path] then return nil, "no file: " .. path end
      return load(files[path], path)
    end,
    createDirectory = function() return true end,
    getDirectoryItems = function(path)
      local seen, items = {}, {}
      local prefix = path .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then
          local child = key:sub(#prefix + 1):match("^[^/]+")
          if child and not seen[child] then
            seen[child] = true
            items[#items + 1] = child
          end
        end
      end
      table.sort(items)
      return items
    end,
  }
end

local MODS = {
  plain = {
    manifest = '{"id":"plain","name":"plain","version":"1.0.0",' ..
      '"entry":"main.lua","profile":"content"}',
    entry = [[
return function(mod)
  mod.content.pokemon:register("PLAIN", { name = "PLAIN" })
end
]],
  },
  espanol = {
    manifest = '{"id":"espanol","name":"espanol","version":"1.0.0",' ..
      '"entry":"main.lua","language":true,"category":"LANGUAGE"}',
    entry = [[
return function(mod)
  mod.content.strings:register("arena.hello", "HOLA")
end
]],
  },
  faux = {
    manifest = '{"id":"faux","name":"faux","version":"1.0.0",' ..
      '"entry":"main.lua","language":true}',
    entry = [[
return function(mod)
  mod.content.strings:register("arena.hi", "HELLO")
  mod.content.pokemon:register("FAUX", { name = "FAUX" })
end
]],
  },
}

local function install(options)
  local files = {
    ["options.lua"] = SaveSerializer.encode(options or {}),
  }
  for id, mod in pairs(MODS) do
    files["mods/" .. id .. "/manifest.json"] = mod.manifest
    files["mods/" .. id .. "/main.lua"] = mod.entry
  end
  SaveData.resetSlotState()
  SaveData.setCart(nil)
  GameVersion.set("red")
  return files
end

local function boot(files, opts)
  local data = { pokemon = {}, strings = {} }
  local loader = Loader.new({ fs = memfs(files) })
  local ok, reason = loader:load(data, opts)
  return loader, data, ok, reason
end

local function writeCart(files, tbl)
  local cart, err = CartManifest.parse(tbl)
  assert(cart, err)
  files["carts/" .. tbl.id .. CartManifest.EXT] = CartManifest.encode(cart)
  return cart
end

local function cartTable(id, seal, mods, order)
  return { id = id, title = id, version = "1.0.0", author = "tester",
           shell = "#102030", base = "red", seal = seal,
           mods = mods, load_order = order }
end

local function pin(id, version)
  return { id = id, source = "local", version = version or "1.0.0" }
end

-- ------- normal mode is unchanged

do
  local files = install({ modsByVersion = { red = { plain = false } } })
  local loader, data, ok = boot(files)
  T.check(ok, "a normal load with no arena mode still loads clean")
  T.eq(loader:status().arenaMode, "normal", "and reports the normal mode")
  T.eq(loader.mods.plain.enabled, false, "the player's disable flag decides")
  T.eq(loader.mods.espanol.enabled, true, "an enabled translation runs")
  T.eq(data.pokemon.PLAIN, nil, "a disabled mod merges nothing")
  T.eq(data.pokemon.FAUX.name, "FAUX", "an enabled content mod merges")
end

-- ------- disableAll keeps verified translations and nothing else

do
  local files = install({ safeMode = true,
                          modsByVersion = { red = { espanol = false } } })
  local before = files["options.lua"]
  local loader, data, ok = boot(files, { mode = "disableAll" })
  T.check(ok, "a disableAll load succeeds")
  T.eq(loader:status().arenaMode, "disableAll", "and reports its mode")
  T.eq(loader.safeMode, false, "safe mode is never read on an arena boot")
  T.eq(loader.mods.espanol.enabled, true,
    "a verified translation loads even though options disabled it")
  T.eq(loader.mods.plain.enabled, false, "a content mod is off")
  T.eq(data.pokemon.PLAIN, nil, "and merges nothing")
  T.eq(loader.mods.faux.enabled, false,
    "a mod that claims language but writes a species is unloaded")
  T.eq(data.pokemon.FAUX, nil, "and its ops never reach the merge")
  T.eq(data.strings["arena.hello"], "HOLA",
    "the verified translation's string is the one that merged")
  local order = table.concat(loader.order, ",")
  T.eq(order, "espanol", "only the translation is in the load order")
  T.eq(files["options.lua"], before, "options.lua is untouched byte for byte")
end

-- ------- disableAll with no translations installed

do
  local files = install({})
  files["mods/espanol/manifest.json"] = nil
  files["mods/espanol/main.lua"] = nil
  files["mods/faux/manifest.json"] = nil
  files["mods/faux/main.lua"] = nil
  local before = files["options.lua"]
  local loader, data, ok = boot(files, { mode = "disableAll" })
  T.check(ok, "a disableAll load with only content mods succeeds")
  T.eq(#loader.order, 0, "nothing loads")
  T.eq(data.pokemon.PLAIN, nil, "and nothing merges")
  T.eq(files["options.lua"], before, "options.lua is still untouched")
end

-- ------- an unknown mode is refused

do
  local files = install({})
  local _, _, ok, reason = boot(files, { mode = "nonsense" })
  T.eq(ok, false, "an unknown mode is refused")
  T.check(reason and reason:find("nonsense", 1, true) ~= nil,
    "and the reason names it")
end

-- ------- cartOnly runs exactly the cart's pins

do
  local files = install({ modsByVersion = { red = { plain = false } } })
  writeCart(files, cartTable("arena", "sealed", { pin("plain") }, { "plain" }))
  local before = files["options.lua"]
  local loader, data, ok = boot(files, { mode = "cartOnly", cartId = "arena" })
  T.check(ok, "a sealed cart arena loads")
  T.eq(loader:status().arenaMode, "cartOnly", "and reports its mode")
  T.eq(data.pokemon.PLAIN.name, "PLAIN",
    "the pinned mod runs even though the player switched it off")
  T.eq(loader.mods.espanol.enabled, false,
    "a mod the cart does not pin never runs, translation or not")
  T.eq(loader:cartStatus().enforced, true, "the cart is enforced")
  T.eq(files["options.lua"], before, "options.lua is untouched")
end

-- ------- cartOnly refuses a broken seal

do
  local files = install({})
  writeCart(files, cartTable("arena", "sealed", { pin("plain") }, { "plain" }))
  local _, _, ok, reason = boot(files,
    { mode = "cartOnly", cartId = "arena", sealBroken = true })
  T.eq(ok, false, "a broken seal cannot enter an arena")
  T.eq(reason, "this save's seal is broken", "and says so")
end

-- ------- cartOnly refuses a plan that cannot be enforced

do
  local files = install({})
  writeCart(files, cartTable("gap", "sealed", { pin("missing") }, { "missing" }))
  local _, _, ok, reason = boot(files, { mode = "cartOnly", cartId = "gap" })
  T.eq(ok, false, "a cart whose pins are not installed is refused")
  T.check(reason and reason:find("missing", 1, true) ~= nil,
    "and names the pin it cannot satisfy")

  local open = install({})
  writeCart(open, cartTable("loose", "open", { pin("plain") }, { "plain" }))
  local _, _, openOk, openReason = boot(open,
    { mode = "cartOnly", cartId = "loose" })
  T.eq(openOk, false, "an open cart is not a fixed identity")
  T.check(openReason and openReason:find("sealed", 1, true) ~= nil,
    "and the reason says so")

  local gone = install({})
  local _, _, goneOk, goneReason = boot(gone,
    { mode = "cartOnly", cartId = "nothere" })
  T.eq(goneOk, false, "an uninstalled cart is refused")
  T.check(goneReason ~= nil, "with a reason")
end

-- ------- ArenaData profile comparison

local function profile(overrides)
  local p = {
    engine = 1, version = "red", engineVersion = "1.2.3", apiVersion = 2,
    fingerprint = "abcd1234", rulesetId = "gen1_faithful", kind = "vanilla",
    rule = { partySize = 3 },
  }
  for key, value in pairs(overrides or {}) do p[key] = value end
  return p
end

do
  local a, b = profile(), profile()
  T.eq(ArenaData.equal(a, b), true, "two identical profiles are equal")
  T.eq(ArenaData.describeMismatch(a, b), nil, "and name no mismatch")

  b.rule = { partySize = 6, forceLevel = 50 }
  T.eq(ArenaData.equal(a, b), true, "the rule is not part of the identity")

  T.eq(ArenaData.equal(a, profile({ fingerprint = "ffff" })), false,
    "a different dataset is not equal")
  T.eq(ArenaData.describeMismatch(a, profile({ fingerprint = "ffff" })),
    "data differs", "and reports the dataset")
  T.eq(ArenaData.describeMismatch(a, profile({ engineVersion = "9.9.9" })),
    "engine version differs", "an engine release is named first")
  T.eq(ArenaData.equal(a, profile({ version = "blue" })), true,
    "red and blue share a link surface, so they pair")
  T.eq(ArenaData.equal(a, profile({ version = "yellow" })), true,
    "and so does yellow (#511)")
  T.eq(ArenaData.describeMismatch(a, profile({ rulesetId = "gen1_fixed" })),
    "ruleset differs", "and the ruleset")
  T.eq(ArenaData.describeMismatch(a, profile({ engine = 2 })),
    "engine differs", "and the generation")

  local cartA = profile({ kind = "cart",
    cart = { id = "arena", version = "1.0.0", hash = "h1" } })
  local cartB = profile({ kind = "cart",
    cart = { id = "arena", version = "1.0.0", hash = "h2" } })
  T.eq(ArenaData.equal(cartA, cartB), false, "two cart hashes must agree")
  T.eq(ArenaData.describeMismatch(cartA, cartB), "cart hash differs",
    "and the mismatch names the hash")
  T.eq(ArenaData.describeMismatch(cartA, a), "arena kind differs",
    "a cart arena is not a vanilla one")
  T.eq(ArenaData.equal(a, nil), false, "a missing profile is never equal")
end

-- ------- the cache key

do
  local Version = require("src.core.Version")
  T.eq(ArenaData.cacheKey("red", "vanilla", nil),
    "red|vanilla|-|" .. Version.engine,
    "a vanilla key uses - for the absent cart hash")
  T.eq(ArenaData.cacheKey("gold", "cart", "deadbeef"),
    "gold|cart|deadbeef|" .. Version.engine,
    "a cart key carries the cart hash")
end

-- ------- TeamPick.validate

local function mon(level, extra)
  local m = { species = "PIKACHU", level = level, hp = 20, moves = {},
              dvs = {}, statExp = {} }
  for key, value in pairs(extra or {}) do m[key] = value end
  return m
end

do
  local party = { mon(50), mon(50), mon(10), mon(60, { isEgg = true }) }
  local rule = { partySize = 3, minLevel = 20, maxLevel = 55 }

  T.eq(TeamPick.validate(party, { 1, 2 }, rule), false,
    "a short team is refused")
  T.eq(select(2, TeamPick.validate(party, { 1, 2 }, rule)),
    "this arena needs 3 Pokemon.", "with the count in the reason")
  T.eq(TeamPick.validate(party, { 1, 2, 1 }, rule), false,
    "the same slot twice is refused")
  T.eq(select(2, TeamPick.validate(party, { 1, 2, 1 }, rule)),
    "no doubles allowed.", "and says so")
  T.eq(TeamPick.validate(party, { 1, 2, 9 }, rule), false,
    "an index past the party is refused")
  T.eq(TeamPick.validate(party, { 1, 2, 3 }, rule), false,
    "an under-level mon is refused")
  T.eq(select(2, TeamPick.validate(party, { 1, 2, 3 }, rule)),
    "every Pokemon must be\nLv20 or higher.", "naming the floor")
  T.eq(TeamPick.validate(party, { 1, 2, 4 }, rule), false,
    "an EGG cannot be picked")
  T.eq(select(2, TeamPick.validate(party, { 1, 2, 4 }, rule)),
    "an EGG can't battle.", "and says so")

  local tall = { mon(50), mon(50), mon(90) }
  T.eq(TeamPick.validate(tall, { 1, 2, 3 }, rule), false,
    "an over-level mon is refused")
  T.eq(select(2, TeamPick.validate(tall, { 1, 2, 3 }, rule)),
    "every Pokemon must be\nLv55 or lower.", "naming the ceiling")
  T.eq(TeamPick.validate(tall, { 1, 2, 3 },
    { partySize = 3, minLevel = 20, maxLevel = 55, forceLevel = 50 }), true,
    "forceLevel rewrites every level, so the band no longer applies")

  T.eq(TeamPick.validate(party, { 3, 2, 1 }, { partySize = 3 }), true,
    "a rule with no level band takes any order")
  T.eq(TeamPick.validate(party, { 1 }, { partySize = 1 }), true,
    "a one-mon arena is legal")
  T.eq(TeamPick.validate({ mon(5, { hp = 0 }) }, { 1 }, { partySize = 1 }), true,
    "a fainted mon is legal: the lockstep copy is rebuilt from the wire")
  T.eq(TeamPick.validate(party, nil, { partySize = 3 }), false,
    "no team at all is refused")
end

-- ------- TeamPick.pack

do
  local party = { mon(50, { nickname = "ONE" }), mon(51, { nickname = "TWO" }),
                  mon(52, { nickname = "THREE" }) }
  local packed = TeamPick.pack(party, { 3, 1 }, 1)
  T.eq(#packed, 2, "only the chosen slots are packed")
  T.eq(packed[1].nickname, "THREE", "in the order the player chose")
  T.eq(packed[2].nickname, "ONE", "not in party order")
  T.eq(packed[1].level, 52, "carrying the mon's own fields")
  T.eq(packed[1].isEgg, nil, "the Gen 1 codec has no egg field")

  local gen2Party = {
    mon(50, { nickname = "GOLD", item = "LEFTOVERS", happiness = 70 }),
    mon(51, { nickname = "SILVER" }),
  }
  local packed2 = TeamPick.pack(gen2Party, { 2, 1 }, 2)
  T.eq(#packed2, 2, "the Gen 2 branch packs per mon")
  T.eq(packed2[1].nickname, "SILVER", "in the chosen order")
  T.eq(packed2[2].item, "LEFTOVERS", "carrying the held item")
  T.eq(packed2[2].happiness, 70, "and happiness, which Gen 1 has no room for")
  T.eq(packed2[1].exp, nil, "the Gen 2 codec spells experience differently")

  T.eq(#TeamPick.pack(party, {}, 1), 0, "an empty pick packs nothing")
end

-- ------- TeamPick.convert / packConverted (Time Capsule teams)

do
  local Stats = require("src.pokemon.Stats")
  local Mon = require("src.battle.gen2.Mon")

  local GEN1 = {
    pokemon = {
      PIKACHU = { name = "PIKACHU", growthRate = "MEDIUM_FAST",
        baseStats = { hp = 35, attack = 55, defense = 30, speed = 90,
                      special = 50 },
        types = { "ELECTRIC" }, evolutions = {} },
    },
    moves = { TACKLE = { name = "TACKLE", pp = 35 } },
    items = {},
  }
  local GEN2 = {
    pokemon = {
      PIKACHU = { name = "PIKACHU", growthRate = "MEDIUM_FAST",
        baseStats = { hp = 35, attack = 55, defense = 30, speed = 90,
                      specialAttack = 50, specialDefense = 40 },
        types = { "ELECTRIC" }, evolutions = {} },
      HOOTHOOT = { name = "HOOTHOOT", growthRate = "MEDIUM_FAST",
        baseStats = { hp = 60, attack = 30, defense = 30, speed = 50,
                      specialAttack = 36, specialDefense = 56 },
        types = { "NORMAL", "FLYING" }, evolutions = {} },
    },
    moves = { TACKLE = { name = "TACKLE", pp = 35 } },
    items = { LEFTOVERS = { name = "LEFTOVERS" } },
  }

  local function dvs()
    local d = { attack = 15, defense = 15, speed = 15, special = 15 }
    d.hp = Mon.hpDV(d)
    return d
  end
  local function statExp()
    return { hp = 0, attack = 0, defense = 0, speed = 0, special = 0 }
  end

  local function g1(species, level)
    local d, e = dvs(), statExp()
    local stats = Stats.calc(GEN1.pokemon[species], level, d, e)
    return { species = species, level = level, exp = level ^ 3, dvs = d,
             statExp = e, stats = stats, hp = stats.hp, maxHp = stats.hp,
             moves = { { id = "TACKLE", pp = 35 } }, ot = "RED", otId = 1 }
  end
  local function g2(species, level)
    local d, e = dvs(), statExp()
    local stats = Mon.stats(GEN2.pokemon[species].baseStats, d, level, e)
    return { species = species, level = level, experience = level ^ 3,
             dvs = d, statExp = e, stats = stats, hp = stats.hp,
             maxHp = stats.hp, types = GEN2.pokemon[species].types,
             moves = { { id = "TACKLE", pp = 35, maxPp = 35 } },
             happiness = 70, caughtLevel = level, ot = "GOLD", otId = 2 }
  end

  local byKey, rows = TeamPick.convert({ g1("PIKACHU", 20) }, 2, GEN1, GEN2)
  T.check(byKey["party|1"] ~= nil, "a Kanto mon crosses into Gen 2")
  T.eq(rows["party|1"].ok, true, "and the result row says so")
  T.check(#rows["party|1"].preview > 0, "with preview lines for the picker")
  T.eq(byKey["party|1"].happiness, 70, "friendship is set on arrival")
  T.eq(rows["party|1"].key, "party|1", "each row carries its source key")

  local intoOne, gen1Rows, refusals =
    TeamPick.convert({ g2("PIKACHU", 20), g2("HOOTHOOT", 20) }, 1, GEN2, GEN1)
  T.check(intoOne["party|1"] ~= nil, "a Gen 1 species crosses back")
  T.eq(intoOne["party|2"], nil, "a Johto species does not")
  T.eq(gen1Rows["party|2"].ok, false, "its row is a refusal")
  T.eq(refusals["party|2"], "species_too_new", "naming why")
  T.eq(gen1Rows["party|2"].preview[1], "SPECIES NOT IN GEN 1: HOOTHOOT",
    "in words the picker can show")

  local packed = TeamPick.packConverted(intoOne, { 1 }, 1)
  T.eq(#packed, 1, "packConverted packs the converted record")
  T.eq(packed[1].species, "PIKACHU", "keeping the species")
  T.eq(packed[1].happiness, nil, "through the Gen 1 codec")

  local none, why = TeamPick.packConverted(intoOne, { 1, 2 }, 1)
  T.eq(none, nil, "a refused mon cannot be packed into a team")
  T.eq(why, "that Pokemon cannot cross generations.", "and says why")

  local two = TeamPick.packConverted(byKey, { 1 }, 2)
  T.eq(#two, 1, "the Gen 2 branch packs per mon")
  T.eq(two[1].happiness, 70, "carrying what only Gen 2 records hold")

  -- a boxed mon converts through the same table, keyed by its own record
  local boxed = { party = { g2("PIKACHU", 20) },
    generation = 2,
    save = { boxes = { {}, { g2("HOOTHOOT", 20), g2("PIKACHU", 25) } } } }
  local boxKeys, boxRows = TeamPick.convert(boxed, 1, GEN2, GEN1)
  T.check(boxKeys["box|2|2"] ~= nil, "a boxed Kanto mon crosses too")
  T.eq(boxRows["box|2|1"].ok, false, "and a boxed Johto one is refused")
  local boxPacked = TeamPick.packConverted(boxKeys,
    { { where = "box", box = 2, index = 2 } }, 1)
  T.eq(#boxPacked, 1, "which packs from the box record")

  T.eq(#TeamPick.packConverted({}, {}, 1), 0, "an empty pick packs nothing")
end

-- ------- TeamPick.candidates and source-aware packing

do
  local SAVE = {
    party = { mon(50, { nickname = "ONE" }), mon(51, { nickname = "TWO" }) },
    boxes = { { mon(10, { nickname = "BOXA" }) }, {},
              { mon(12, { nickname = "BOXB" }),
                mon(13, { nickname = "BOXC" }) } },
  }
  local slot = { party = SAVE.party, save = SAVE, generation = 1 }
  local rows = TeamPick.candidates(slot)
  T.eq(#rows, 5, "candidates are the party plus every boxed POKeMON")
  T.eq(rows[1].where, "party", "the party comes first")
  T.eq(rows[1].source, "Party", "labelled as the party")
  T.eq(rows[3].where, "box", "then the boxes")
  T.eq(rows[3].box, 1, "in box order")
  T.eq(rows[3].source, "BOX 1", "each row named by its box")
  T.eq(rows[4].source, "BOX 3", "empty boxes contribute nothing")
  T.eq(rows[5].index, 2, "and the slot inside the box is kept")

  T.eq(TeamPick.refKey(rows[5]), "box|3|2", "a pick has a stable key")
  T.eq(TeamPick.refKey(1), "party|1",
    "a bare party index is the same key as its record")
  T.check(TeamPick.sameRef(1, { where = "party", index = 1 }),
    "so the two forms compare equal")

  T.eq(TeamPick.monAt(slot, { where = "box", box = 3, index = 2 }).nickname,
    "BOXC", "monAt reads the box the record names")
  T.eq(TeamPick.monAt(slot, 2).nickname, "TWO", "and the party by index")
  T.eq(TeamPick.monAt(slot, { where = "box", box = 2, index = 1 }), nil,
    "an empty box slot has no mon")

  local team = { { where = "box", box = 3, index = 2 }, 1 }
  local packed = TeamPick.pack(slot, team, 1)
  T.eq(#packed, 2, "a mixed team packs both sources")
  T.eq(packed[1].nickname, "BOXC", "in the order it was picked")
  T.eq(packed[2].nickname, "ONE", "party mon second")
  T.eq(TeamPick.validate(slot, team, { partySize = 2 }), true,
    "and validates as a two-mon team")
  T.eq(TeamPick.validate(slot,
    { { where = "box", box = 3, index = 2 },
      { where = "box", box = 3, index = 2 } }, { partySize = 2 }), false,
    "the same box slot twice is still a double")

  local gen2 = { party = {}, generation = 2,
    save = { boxes = { { mon(9, { nickname = "JOHTO" }) } },
             boxNames = { "TEAM" } } }
  local g2rows = TeamPick.candidates(gen2)
  T.eq(#g2rows, 1, "a Gen 2 save lists its boxes the same way")
  T.eq(g2rows[1].source, "TEAM", "under the name the player gave the box")
  T.eq(TeamPick.boxName({}, 2, 3), "BOX3", "an unnamed Gen 2 box is BOXn")
end

T.finish("online arena data")
