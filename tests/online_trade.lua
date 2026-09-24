-- Launcher trade core (src/online/Trade.lua), ROM-free.
--   luajit tests/online_trade.lua
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
if not _G.love then _G.love = require("tests.love_stub") end

local SaveData = require("src.core.SaveData")
local SaveSerializer = require("src.core.SaveSerializer")
local Stats = require("src.pokemon.Stats")
local Mon = require("src.battle.gen2.Mon")
local Trade = require("src.online.Trade")

-- ------- in-memory persistence

local files = {}
local failWrite = nil

local fs = {
  getInfo = function(name) return files[name] and { type = "file" } or nil end,
  read = function(name) return files[name] end,
  write = function(name, body)
    if failWrite and name == failWrite then
      failWrite = nil
      return false, "disk full"
    end
    files[name] = body
    return true
  end,
  remove = function(name) files[name] = nil return true end,
  createDirectory = function() return true end,
  getDirectoryItems = function(dir)
    local prefix, out, seen = dir .. "/", {}, {}
    for name in pairs(files) do
      if name:sub(1, #prefix) == prefix then
        local head = name:sub(#prefix + 1):match("^[^/]+")
        if head and not seen[head] then
          seen[head] = true
          out[#out + 1] = head
        end
      end
    end
    table.sort(out)
    return out
  end,
}

local realPortableFs = SaveData.portableFs
SaveData.portableFs = function() return fs end

-- ------- synthetic datasets

local GEN1 = {
  pokemon = {
    KADABRA = { name = "KADABRA", growthRate = "MEDIUM_SLOW",
      baseStats = { hp = 40, attack = 35, defense = 30, speed = 105,
                    special = 120 },
      evolutions = { { method = "TRADE", species = "ALAKAZAM" } } },
    ALAKAZAM = { name = "ALAKAZAM", growthRate = "MEDIUM_SLOW",
      baseStats = { hp = 55, attack = 50, defense = 45, speed = 120,
                    special = 135 },
      evolutions = {} },
    PIKACHU = { name = "PIKACHU", growthRate = "MEDIUM_FAST",
      baseStats = { hp = 35, attack = 55, defense = 30, speed = 90,
                    special = 50 },
      evolutions = {} },
  },
  moves = { TACKLE = { name = "TACKLE", pp = 35 },
            PSYBEAM = { name = "PSYBEAM", pp = 20 } },
  items = { POTION = { name = "POTION" } },
  maps = { PALLET_TOWN = {} },
}

local GEN2 = {
  pokemon = {
    ONIX = { name = "ONIX",
      baseStats = { hp = 35, attack = 45, defense = 160, speed = 70,
                    specialAttack = 30, specialDefense = 45 },
      types = { "ROCK", "GROUND" },
      evolutions = { { method = "EVOLVE_TRADE", into = "STEELIX",
                       item = "METAL_COAT" } } },
    STEELIX = { name = "STEELIX",
      baseStats = { hp = 75, attack = 85, defense = 200, speed = 30,
                    specialAttack = 55, specialDefense = 65 },
      types = { "STEEL", "GROUND" }, evolutions = {} },
    MACHOKE = { name = "MACHOKE",
      baseStats = { hp = 80, attack = 100, defense = 70, speed = 45,
                    specialAttack = 50, specialDefense = 60 },
      types = { "FIGHTING" },
      evolutions = { { method = "EVOLVE_TRADE", into = "MACHAMP" } } },
    MACHAMP = { name = "MACHAMP",
      baseStats = { hp = 90, attack = 130, defense = 80, speed = 55,
                    specialAttack = 65, specialDefense = 85 },
      types = { "FIGHTING" }, evolutions = {} },
    TOTODILE = { name = "TOTODILE",
      baseStats = { hp = 50, attack = 65, defense = 64, speed = 43,
                    specialAttack = 44, specialDefense = 48 },
      types = { "WATER" }, evolutions = {} },
  },
  moves = { TACKLE = { name = "TACKLE", pp = 35 } },
  items = { METAL_COAT = { name = "METAL COAT" },
            LEFTOVERS = { name = "LEFTOVERS" },
            FLOWER_MAIL = { name = "FLOWER MAIL" } },
}

-- ------- fixtures

local function gen1Mon(species, level, extra)
  local def = GEN1.pokemon[species]
  local dvs = { attack = 15, defense = 15, speed = 15, special = 15 }
  dvs.hp = 15
  local statExp = { hp = 0, attack = 0, defense = 0, speed = 0, special = 0 }
  local stats = Stats.calc(def, level, dvs, statExp)
  local mon = { species = species, level = level, exp = level * level * level,
                dvs = dvs, statExp = statExp, stats = stats, hp = stats.hp,
                moves = { { id = "TACKLE", pp = 35 } },
                ot = "OAK", otId = 4242 }
  for key, value in pairs(extra or {}) do mon[key] = value end
  return mon
end

local function gen2Mon(species, level, extra)
  local def = GEN2.pokemon[species]
  local dvs = { attack = 15, defense = 15, speed = 15, special = 15 }
  dvs.hp = Mon.hpDV(dvs)
  local statExp = { hp = 0, attack = 0, defense = 0, speed = 0, special = 0 }
  local stats = Mon.stats(def.baseStats, dvs, level, statExp)
  local mon = { species = species, name = def.name, level = level,
                experience = level * level * level, dvs = dvs,
                statExp = statExp, stats = stats, hp = stats.hp,
                maxHp = stats.hp, types = def.types,
                moves = { { id = "TACKLE", pp = 35, maxPp = 35 } },
                happiness = 70, pokerus = 0, caughtLevel = level,
                ot = "SILVER", otId = 9 }
  for key, value in pairs(extra or {}) do mon[key] = value end
  return mon
end

local function gen1Save(name, party)
  return { version = "red", format = 1,
           player = { name = name, map = "PALLET_TOWN", x = 1, y = 1 },
           party = party, boxes = {}, inventory = {},
           pokedex = { seen = {}, owned = {} }, playTime = 0 }
end

local function gen2Save(name, party, mail, boxes)
  return { version = "gold", generation = 2, format = 7, boxes = boxes,
           player = { name = name, id = 9, badges = {}, kantoBadges = {} },
           party = party, pokedex = { seen = {}, caught = {} },
           scriptMem = {}, events = {}, mapScenes = {},
           playerState = "normal", lastDexMode = "NEW",
           mail = { party = mail or {}, box = {} },
           playTime = { hours = 0, minutes = 0, seconds = 0, frames = 0 } }
end

local function put(version, slotId, save)
  local path = "saves/" .. version .. "/" .. slotId .. ".lua"
  files[path] = SaveSerializer.encode(save)
  return path
end

local function open(version, slotId, data)
  local handle, reason = Trade.openSlot(version, slotId, nil, { data = data })
  assert(handle, tostring(reason))
  return handle
end

local function decodeAt(path)
  return SaveSerializer.decode(files[path])
end

-- ------- a live game is never traded into

do
  local previous = package.loaded["src.core.Data"]
  package.loaded["src.core.Data"] = { _pristineKeys = {} }
  put("red", "slot1", gen1Save("RED", { gen1Mon("PIKACHU", 20) }))
  local handle, reason = Trade.openSlot("red", "slot1")
  T.eq(handle, nil, "a slot cannot be opened while a game is live")
  T.eq(reason, "close the game first", "and the launcher says which")
  package.loaded["src.core.Data"] = previous
end

-- ------- a positive host signal refuses even with no dataset loaded

do
  files = {}
  put("red", "slot1", gen1Save("RED", { gen1Mon("KADABRA", 30) }))
  put("red", "slot2", gen1Save("BLUE", { gen1Mon("PIKACHU", 25) }))
  local plan = Trade.plan({ from = open("red", "slot1", GEN1), fromIndex = 1,
                            to = open("red", "slot2", GEN1), toIndex = 1 })
  T.check(plan ~= nil, "a plan is made while the launcher owns the machine")

  Trade.hostIsLive = function() return true end
  local handle, reason = Trade.openSlot("red", "slot1")
  T.eq(handle, nil, "a booted game refuses to open a slot")
  T.eq(reason, "close the game first", "and says why")
  local ok, why = Trade.commit(plan)
  T.eq(ok, false, "and refuses to commit one that was already planned")
  T.eq(why, "close the game first", "with the same reason")
  local inMount = Trade.withMountedData(GEN1, function()
    return Trade.gameIsLive()
  end)
  T.eq(inMount, true, "a mount cannot talk a live game away")
  Trade.hostIsLive = nil
  T.eq(Trade.gameIsLive(), false, "with the signal gone the launcher is free")
end

-- ------- the panel's cross-generation path: plan and commit inside a mount

do
  files = {}
  local pathA = put("red", "slot1", gen1Save("RED", { gen1Mon("KADABRA", 30) }))
  local pathB = put("gold", "slot1",
    gen2Save("GOLD", { gen2Mon("TOTODILE", 20) }))
  local beforeA, beforeB = files[pathA], files[pathB]
  local a = open("red", "slot1", GEN1)
  local b = open("gold", "slot1", GEN2)

  local convert = function(packed, _, toGen)
    if toGen == 2 then
      return { species = "TOTODILE", level = packed.level,
               experience = packed.exp, hp = 1, dvs = packed.dvs,
               statExp = packed.statExp, moves = packed.moves,
               ot = packed.ot, otId = packed.otId, happiness = 70 }
    end
    return { species = "PIKACHU", level = packed.level, exp = 8000,
             dvs = packed.dvs, statExp = packed.statExp, moves = packed.moves,
             ot = packed.ot, otId = packed.otId }
  end

  local previous = package.loaded["src.core.Data"]
  package.loaded["src.core.Data"] = { _pristineKeys = {} }
  local out, why = Trade.withMountedData(GEN1, function()
    local plan, reason = Trade.plan({ from = a, fromIndex = 1, to = b,
                                      toIndex = 1, convert = convert })
    if not plan then return { ok = false, reason = reason } end
    local ok, result = Trade.commit(plan)
    return { ok = ok, reason = result, plan = plan }
  end)
  package.loaded["src.core.Data"] = previous

  T.check(type(out) == "table", "the mounted run returns: " .. tostring(why))
  T.check(out.plan ~= nil, "the preview plans inside the mount")
  T.eq(out.ok, true,
    "and the confirm commits inside the same mount: " .. tostring(out.reason))
  T.check(files[pathA] ~= beforeA, "the Gen 1 save is rewritten")
  T.check(files[pathB] ~= beforeB, "and so is the Gen 2 one")
  T.eq(decodeAt(pathA).party[1].species, "PIKACHU",
    "the converted mon lands in the Gen 1 party")
  T.eq(decodeAt(pathB).party[1].species, "TOTODILE",
    "and the other one in the Gen 2 party")
end

-- ------- Gen 1 plan preview, OT and traded semantics

do
  files = {}
  local pathA = put("red", "slot1",
    gen1Save("RED", { gen1Mon("KADABRA", 30, { nickname = "ABRA-CAD" }) }))
  local pathB = put("red", "slot2",
    gen1Save("BLUE", { gen1Mon("PIKACHU", 25) }))
  local a = open("red", "slot1", GEN1)
  local b = open("red", "slot2", GEN1)
  T.eq(a.path, pathA, "the handle knows the file it came from")
  T.eq(a.generation, 1, "and the generation of the save")

  local plan, reason = Trade.plan({ from = a, fromIndex = 1,
                                    to = b, toIndex = 1 })
  T.check(plan ~= nil, "two Gen 1 party picks make a plan: " .. tostring(reason))
  T.eq(plan.get.species, "PIKACHU", "the giver receives the other mon")
  T.eq(plan.get.traded, true, "a received mon is marked traded")
  T.eq(plan.get.ot, "OAK", "and keeps the sender's OT name")
  T.eq(plan.get.otId, 4242, "and the sender's OT id")
  T.eq(plan.evolveA, nil, "PIKACHU has no trade evolution")
  T.eq(plan.evolveB, "ALAKAZAM", "KADABRA evolves on the receiving side")
  T.eq(plan.give.species, "ALAKAZAM", "so the receiver files the evolution")
  T.eq(plan.give.nickname, "ABRA-CAD",
    "a real nickname survives the evolution")
  T.eq(plan.give.stats.special,
    Stats.calc(GEN1.pokemon.ALAKAZAM, 30, plan.give.dvs, plan.give.statExp).special,
    "with stats recomputed for the new species")
  T.eq(files[pathA], SaveSerializer.encode(a.save),
    "planning writes nothing to the giver's file")
  T.eq(decodeAt(pathB).party[1].species, "PIKACHU",
    "and nothing to the receiver's")

  local warned = false
  for _, row in ipairs(plan.warnings) do
    if row.code == "evolve" and row.species == "ALAKAZAM" then warned = true end
  end
  T.check(warned, "the preview warns about the evolution")
end

-- ------- an un-nicknamed mon loses the old species name on evolving

do
  files = {}
  put("red", "slot1",
    gen1Save("RED", { gen1Mon("KADABRA", 30, { nickname = "KADABRA" }) }))
  put("red", "slot2", gen1Save("BLUE", { gen1Mon("PIKACHU", 25) }))
  local plan = Trade.plan({ from = open("red", "slot1", GEN1), fromIndex = 1,
                            to = open("red", "slot2", GEN1), toIndex = 1 })
  T.eq(plan.give.nickname, nil,
    "a nickname equal to the old species name is dropped")
end

-- ------- eggs and mail are never traded

do
  files = {}
  put("red", "slot1",
    gen1Save("RED", { gen1Mon("PIKACHU", 5, { isEgg = true }) }))
  put("red", "slot2", gen1Save("BLUE", { gen1Mon("PIKACHU", 25) }))
  local plan, reason = Trade.plan({ from = open("red", "slot1", GEN1),
    fromIndex = 1, to = open("red", "slot2", GEN1), toIndex = 1 })
  T.eq(plan, nil, "an EGG cannot be traded")
  T.eq(reason, "an EGG can't be traded", "and says so")

  files = {}
  put("gold", "slot1", gen2Save("GOLD", { gen2Mon("TOTODILE", 20) },
    { [1] = { type = "FLOWER_MAIL", message = "HI", author = "GOLD",
              authorId = 9, species = "TOTODILE" } }))
  put("gold", "slot2", gen2Save("SILVER", { gen2Mon("MACHOKE", 30) }))
  local mailPlan, mailReason = Trade.plan({
    from = open("gold", "slot1", GEN2), fromIndex = 1,
    to = open("gold", "slot2", GEN2), toIndex = 1 })
  T.eq(mailPlan, nil, "a mon carrying MAIL cannot leave")
  T.eq(mailReason, "take the MAIL first", "and the reason names the letter")

  files = {}
  put("gold", "slot1",
    gen2Save("GOLD", { gen2Mon("TOTODILE", 20, { item = "FLOWER_MAIL" }) }))
  put("gold", "slot2", gen2Save("SILVER", { gen2Mon("MACHOKE", 30) }))
  local heldPlan = Trade.plan({ from = open("gold", "slot1", GEN2),
    fromIndex = 1, to = open("gold", "slot2", GEN2), toIndex = 1 })
  T.eq(heldPlan, nil, "a mail item in the held slot counts too")
end

-- ------- a cross-generation pick asks for the converter

do
  files = {}
  put("red", "slot1", gen1Save("RED", { gen1Mon("PIKACHU", 25) }))
  put("gold", "slot1", gen2Save("GOLD", { gen2Mon("TOTODILE", 20) }))
  local a = open("red", "slot1", GEN1)
  local b = open("gold", "slot1", GEN2)
  local plan, reason = Trade.plan({ from = a, fromIndex = 1,
                                    to = b, toIndex = 1 })
  T.eq(plan, nil, "a Gen 1 to Gen 2 pick is not this package's job")
  T.eq(reason, "needs_conversion", "and names the missing step")

  local converted = Trade.plan({ from = a, fromIndex = 1, to = b, toIndex = 1,
    convert = function(packed, from, to)
      if to == 2 then
        return { species = "TOTODILE", level = packed.level,
                 experience = packed.exp, hp = 1,
                 dvs = packed.dvs, statExp = packed.statExp,
                 moves = packed.moves, ot = packed.ot, otId = packed.otId,
                 happiness = 70 }
      end
      return { species = "PIKACHU", level = packed.level, exp = 8000,
               dvs = packed.dvs, statExp = packed.statExp,
               moves = packed.moves, ot = packed.ot, otId = packed.otId }
    end })
  T.check(converted ~= nil, "a converter hook unblocks the same pick")
  T.eq(converted.get.species, "PIKACHU", "the Gen 1 side rebuilds Gen 1")
  T.eq(converted.give.species, "TOTODILE", "and the Gen 2 side rebuilds Gen 2")
end

-- ------- the same save is not two sides

do
  files = {}
  put("red", "slot1",
    gen1Save("RED", { gen1Mon("PIKACHU", 25), gen1Mon("KADABRA", 30) }))
  local a = open("red", "slot1", GEN1)
  local b = open("red", "slot1", GEN1)
  local plan, reason = Trade.plan({ from = a, fromIndex = 1,
                                    to = b, toIndex = 2 })
  T.eq(plan, nil, "one save cannot trade with itself")
  T.eq(reason, "that's the same save", "and says so")
end

-- ------- commit writes both files, marks the dex, and backs up first

do
  files = {}
  local pathA = put("red", "slot1", gen1Save("RED", { gen1Mon("KADABRA", 30) }))
  local pathB = put("red", "slot2", gen1Save("BLUE", { gen1Mon("PIKACHU", 25) }))
  local beforeA, beforeB = files[pathA], files[pathB]
  local a = open("red", "slot1", GEN1)
  local b = open("red", "slot2", GEN1)
  local plan = Trade.plan({ from = a, fromIndex = 1, to = b, toIndex = 1 })
  local ok, handles, backups = Trade.commit(plan)
  T.eq(ok, true, "the commit succeeds")
  T.eq(#handles, 2, "and hands back both rewritten saves")

  local diskA, diskB = decodeAt(pathA), decodeAt(pathB)
  T.eq(diskA.party[1].species, "PIKACHU", "the giver's slot holds the new mon")
  T.eq(diskB.party[1].species, "ALAKAZAM",
    "the receiver's slot holds the evolved one")
  T.eq(diskA.party[1].traded, true, "the received mon stays marked traded")
  T.eq(diskA.pokedex.seen.PIKACHU, true, "the receiver's dex sees it")
  T.eq(diskA.pokedex.owned.PIKACHU, true, "and owns it")
  T.eq(diskB.pokedex.owned.ALAKAZAM, true,
    "the evolved species is marked too")
  T.eq(diskB.pokedex.owned.KADABRA, true,
    "and so is the species that arrived")
  T.eq(files[pathA .. ".tmp"], nil, "no write witness is left behind")
  T.eq(files[pathB .. ".tmp"], nil, "on either side")
  T.eq(#backups, 2, "both files were backed up before the write")
  T.eq(files[backups[1]], beforeA, "the first backup is the old bytes")
  T.eq(files[backups[2]], beforeB, "and so is the second")
  T.eq(handles[1].party[1].species, "PIKACHU",
    "the returned handle reads the new party")
end

-- ------- a failed second write restores the first

do
  files = {}
  local pathA = put("red", "slot1", gen1Save("RED", { gen1Mon("KADABRA", 30) }))
  local pathB = put("red", "slot2", gen1Save("BLUE", { gen1Mon("PIKACHU", 25) }))
  local beforeA, beforeB = files[pathA], files[pathB]
  local plan = Trade.plan({ from = open("red", "slot1", GEN1), fromIndex = 1,
                            to = open("red", "slot2", GEN1), toIndex = 1 })
  failWrite = pathB
  local ok, reason = Trade.commit(plan)
  failWrite = nil
  T.eq(ok, false, "a half-written trade fails")
  T.check(reason ~= nil, "with a reason: " .. tostring(reason))
  T.eq(files[pathA], beforeA, "the first save is byte-identical to before")
  T.eq(files[pathB], beforeB, "and so is the second")
  T.eq(files[pathA .. ".tmp"], nil, "no witness survives the rollback")
  T.eq(files[pathA .. ".bak"], nil, "and no half-made backup either")
end

-- ------- a save that will not validate is never written

do
  files = {}
  local bad = gen1Save("BLUE", { gen1Mon("PIKACHU", 25) })
  bad.boxes = { { { species = "MISSINGNO", level = 5, moves = {} } } }
  local pathA = put("red", "slot1", gen1Save("RED", { gen1Mon("KADABRA", 30) }))
  local pathB = put("red", "slot2", bad)
  local beforeA, beforeB = files[pathA], files[pathB]
  local plan = Trade.plan({ from = open("red", "slot1", GEN1), fromIndex = 1,
                            to = open("red", "slot2", GEN1), toIndex = 1 })
  local ok, reason = Trade.commit(plan)
  T.eq(ok, false, "a save whose content this dataset cannot vouch for is refused")
  T.eq(reason, "that save didn't validate", "and says which check failed")
  T.eq(files[pathA], beforeA, "the other save is untouched")
  T.eq(files[pathB], beforeB, "and so is the one that failed")
end

-- ------- Gen 2: trade evolutions, held items and the dex

do
  files = {}
  local pathA = put("gold", "slot1",
    gen2Save("GOLD", { gen2Mon("ONIX", 30, { item = "METAL_COAT" }) }))
  local pathB = put("gold", "slot2",
    gen2Save("SILVER", { gen2Mon("MACHOKE", 30) }))
  local a = open("gold", "slot1", GEN2)
  local b = open("gold", "slot2", GEN2)
  T.eq(a.generation, 2, "a Gold save reads as generation 2")

  local plan, reason = Trade.plan({ from = a, fromIndex = 1,
                                    to = b, toIndex = 1 })
  T.check(plan ~= nil, "two Gen 2 picks make a plan: " .. tostring(reason))
  T.eq(plan.evolveB, "STEELIX", "a METAL COAT trade evolves ONIX")
  T.eq(plan.give.item, nil, "and the held item is consumed")
  T.eq(plan.evolveA, "MACHAMP", "MACHOKE evolves on any trade")
  T.eq(plan.get.traded, true, "the received Gen 2 mon is marked traded")
  T.eq(plan.get.ot, "SILVER", "and keeps its OT")
  T.eq(plan.get.happiness, 70, "and its happiness byte")

  local used = false
  for _, row in ipairs(plan.warnings) do
    if row.code == "item_used" then used = true end
  end
  T.check(used, "the preview warns that the item is eaten")

  local ok = Trade.commit(plan)
  T.eq(ok, true, "the Gen 2 commit succeeds")
  local diskA, diskB = decodeAt(pathA), decodeAt(pathB)
  T.eq(diskA.party[1].species, "MACHAMP", "the evolved mon lands in the party")
  T.eq(diskB.party[1].species, "STEELIX", "on both sides")
  T.eq(diskA.pokedex.caught.MACHAMP, true, "a Gen 2 dex marks caught")
  T.eq(diskA.pokedex.seen.MACHOKE, true, "and sees what arrived")
  T.eq(diskB.pokedex.caught.STEELIX, true, "the other side too")
end

-- ------- an EVERSTONE stops a Gen 2 trade evolution

do
  files = {}
  put("gold", "slot1",
    gen2Save("GOLD", { gen2Mon("MACHOKE", 30, { item = "EVERSTONE" }) }))
  put("gold", "slot2", gen2Save("SILVER", { gen2Mon("TOTODILE", 20) }))
  local data = {}
  for key, value in pairs(GEN2) do data[key] = value end
  data.items = { EVERSTONE = { name = "EVERSTONE" },
                 METAL_COAT = { name = "METAL COAT" } }
  local plan = Trade.plan({ from = open("gold", "slot1", data), fromIndex = 1,
                            to = open("gold", "slot2", data), toIndex = 1 })
  T.check(plan ~= nil, "the trade still happens")
  T.eq(plan.evolveB, nil, "but an EVERSTONE holder does not evolve")
  T.eq(plan.give.species, "MACHOKE", "and arrives unchanged")
  T.eq(plan.give.item, "EVERSTONE", "still holding the stone")
end

-- ------- a Gen 1 pick can come out of the PC

do
  files = {}
  local b = gen1Save("BLUE", { gen1Mon("PIKACHU", 25) })
  b.boxes = { {}, { gen1Mon("PIKACHU", 14) } }
  local pathA = put("red", "slot1", gen1Save("RED", { gen1Mon("KADABRA", 30) }))
  local pathB = put("red", "slot2", b)
  local boxRef = { where = "box", box = 2, index = 1 }
  local plan, reason = Trade.plan({ from = open("red", "slot1", GEN1),
    fromIndex = 1, to = open("red", "slot2", GEN1), toIndex = boxRef })
  T.check(plan ~= nil,
    "a party pick trades against one in the PC: " .. tostring(reason))
  T.eq(plan.get.level, 14, "the party side receives the boxed POKeMON")
  T.eq(plan.give.species, "ALAKAZAM",
    "and the box side still files the trade evolution")

  local ok, handles = Trade.commit(plan)
  T.eq(ok, true, "the commit goes through: " .. tostring(handles))
  local diskA, diskB = decodeAt(pathA), decodeAt(pathB)
  T.eq(diskA.party[1].level, 14, "the boxed mon lands in the other party")
  T.eq(diskA.party[1].traded, true, "marked traded like any other")
  T.eq(diskB.boxes[2][1].species, "ALAKAZAM",
    "and the box slot itself takes the evolution")
  T.eq(#diskB.boxes[2], 1, "the box keeps its length")
  T.eq(diskB.party[1].level, 25, "the box side's party is untouched")
  T.eq(diskB.pokedex.owned.ALAKAZAM, true, "a box pick marks the dex")
  T.eq(diskA.pokedex.owned.PIKACHU, true, "on both sides")
  T.eq(handles[2].boxes[2][1].species, "ALAKAZAM",
    "and the returned handle reads the rewritten boxes")
end

-- ------- box to box, with neither party touched

do
  files = {}
  local a = gen1Save("RED", { gen1Mon("PIKACHU", 25) })
  a.boxes = { { gen1Mon("KADABRA", 30) } }
  local b = gen1Save("BLUE", { gen1Mon("PIKACHU", 25) })
  b.boxes = { {}, {}, { gen1Mon("PIKACHU", 7), gen1Mon("PIKACHU", 9) } }
  local pathA = put("red", "slot1", a)
  local pathB = put("red", "slot2", b)
  local plan, reason = Trade.plan({
    from = open("red", "slot1", GEN1),
    fromIndex = { where = "box", box = 1, index = 1 },
    to = open("red", "slot2", GEN1),
    toIndex = { where = "box", box = 3, index = 2 } })
  T.check(plan ~= nil, "two PC picks make a plan: " .. tostring(reason))
  T.eq(Trade.commit(plan), true, "and commit")
  local diskA, diskB = decodeAt(pathA), decodeAt(pathB)
  T.eq(diskA.boxes[1][1].level, 9, "the first box slot holds what arrived")
  T.eq(diskB.boxes[3][2].species, "ALAKAZAM", "and the second the evolution")
  T.eq(diskB.boxes[3][1].level, 7, "the box's other slots are left alone")
  T.eq(diskA.party[1].level, 25, "neither party moved")
  T.eq(diskB.party[1].level, 25, "on either side")
end

-- ------- a boxed Gen 2 mon has no MAIL by definition

do
  files = {}
  local letter = { type = "FLOWER_MAIL", message = "HI", author = "GOLD",
                   authorId = 9, species = "TOTODILE" }
  local pathA = put("gold", "slot1",
    gen2Save("GOLD", { gen2Mon("TOTODILE", 20) }, { [1] = letter },
      { { gen2Mon("MACHOKE", 30, { item = "FLOWER_MAIL" }) } }))
  local pathB = put("gold", "slot2",
    gen2Save("SILVER", { gen2Mon("TOTODILE", 22) }))
  local blocked = Trade.plan({ from = open("gold", "slot1", GEN2),
    fromIndex = 1, to = open("gold", "slot2", GEN2), toIndex = 1 })
  T.eq(blocked, nil, "the party mon is still held back by its letter")

  local plan, reason = Trade.plan({ from = open("gold", "slot1", GEN2),
    fromIndex = { where = "box", box = 1, index = 1 },
    to = open("gold", "slot2", GEN2), toIndex = 1 })
  T.check(plan ~= nil,
    "the boxed one trades even so: " .. tostring(reason))
  T.eq(plan.give.species, "MACHAMP",
    "a Gen 2 box pick evolves on arrival like any other")
  T.eq(Trade.commit(plan), true, "and commits")
  local diskA, diskB = decodeAt(pathA), decodeAt(pathB)
  T.eq(diskA.boxes[1][1].level, 22, "the box slot takes what came back")
  T.eq(diskB.party[1].species, "MACHAMP", "and the party the evolution")
  T.eq(diskA.mail.party[1].message, "HI",
    "the party's letter is left where it was")
  T.eq(diskA.party[1].species, "TOTODILE", "and so is the mon holding it")
  T.eq(diskA.pokedex.caught.TOTODILE, true, "a Gen 2 box pick marks caught")
end

-- ------- a box source rolls back like any other

do
  files = {}
  local b = gen1Save("BLUE", { gen1Mon("PIKACHU", 25) })
  b.boxes = { { gen1Mon("PIKACHU", 14) } }
  local pathA = put("red", "slot1", gen1Save("RED", { gen1Mon("KADABRA", 30) }))
  local pathB = put("red", "slot2", b)
  local beforeA, beforeB = files[pathA], files[pathB]
  local plan = Trade.plan({ from = open("red", "slot1", GEN1), fromIndex = 1,
    to = open("red", "slot2", GEN1),
    toIndex = { where = "box", box = 1, index = 1 } })
  failWrite = pathB
  local ok, reason = Trade.commit(plan)
  failWrite = nil
  T.eq(ok, false, "a failed write on the box side fails the trade")
  T.check(reason ~= nil, "with a reason: " .. tostring(reason))
  T.eq(files[pathA], beforeA, "the party save is byte-identical to before")
  T.eq(files[pathB], beforeB, "and so is the one with the box")

  local bad = gen1Save("BLUE", { gen1Mon("PIKACHU", 25) })
  bad.boxes = { { gen1Mon("PIKACHU", 14) },
                { { species = "MISSINGNO", level = 5, moves = {} } } }
  files = {}
  local badA = put("red", "slot1", gen1Save("RED", { gen1Mon("KADABRA", 30) }))
  local badB = put("red", "slot2", bad)
  local beforeBadA, beforeBadB = files[badA], files[badB]
  local badPlan = Trade.plan({ from = open("red", "slot1", GEN1),
    fromIndex = 1, to = open("red", "slot2", GEN1),
    toIndex = { where = "box", box = 1, index = 1 } })
  local badOk, badWhy = Trade.commit(badPlan)
  T.eq(badOk, false, "a box trade into a save that will not validate is refused")
  T.eq(badWhy, "that save didn't validate", "with the same reason as a party one")
  T.eq(files[badA], beforeBadA, "and neither file is touched")
  T.eq(files[badB], beforeBadB, "on either side")
end

-- ------- an incoming mon can be filed into a box

do
  files = {}
  local b = gen1Save("BLUE", { gen1Mon("PIKACHU", 25) })
  b.boxes = { {}, { gen1Mon("PIKACHU", 14) } }
  local pathB = put("red", "slot2", b)
  local plan, reason = Trade.planIncoming({
    to = open("red", "slot2", GEN1),
    toIndex = { where = "box", box = 2, index = 1 },
    record = gen1Mon("KADABRA", 30) })
  T.check(plan ~= nil, "planIncoming takes a box ref: " .. tostring(reason))
  T.eq(plan.give.level, 14, "the mon that was in that box slot is the giver")
  T.eq(plan.get.species, "ALAKAZAM", "the arrival still evolves")
  T.eq(Trade.commit(plan), true, "and the one-sided commit lands")
  local disk = decodeAt(pathB)
  T.eq(disk.boxes[2][1].species, "ALAKAZAM", "in the box slot it was aimed at")
  T.eq(disk.party[1].level, 25, "leaving the party alone")

  local nope, why = Trade.planIncoming({ to = open("red", "slot2", GEN1),
    toIndex = { where = "box", box = 9, index = 4 },
    record = gen1Mon("PIKACHU", 5) })
  T.eq(nope, nil, "an empty box slot is not a trade target")
  T.eq(why, "that's not in the PC", "and the reason names the PC")
end

-- ------- a remote trade through the relay's commit barrier

local Relay = require("tests.online_trade_fakerelay")

local function remotePair(version, slotA, slotB, data, opts)
  local relay = Relay.new(opts)
  local rsA, rsB = relay:join(0, "A"), relay:join(1, "B")
  local remoteA = Trade.remote(open(version, slotA, data), rsA)
  local remoteB = Trade.remote(open(version, slotB, data), rsB)
  return relay, remoteA, remoteB, rsA, rsB
end

local function negotiate(remoteA, remoteB)
  remoteA:start()
  remoteB:start()
  remoteA:update()
  remoteB:update()
  remoteA:pick(1)
  remoteB:pick(1)
  remoteA:update()
  remoteB:update()
  remoteA:confirm(true)
  remoteB:confirm(true)
  remoteA:update()
  remoteB:update()
end

do
  files = {}
  local pathA = put("red", "slot1", gen1Save("RED", { gen1Mon("PIKACHU", 25) }))
  local pathB = put("red", "slot2",
    gen1Save("BLUE", { gen1Mon("KADABRA", 30) }))
  local relay, remoteA, remoteB = remotePair("red", "slot1", "slot2", GEN1)
  T.check(remoteA ~= nil and remoteB ~= nil, "both ends open an adapter")
  T.eq(remoteA.game.save, remoteA.handle.save,
    "the stub game the session reads is the handle's own save")

  remoteA:start()
  remoteB:start()
  remoteA:update()
  remoteB:update()
  T.eq(remoteA:stage(), "picking", "both sides have the other's party")

  remoteA:pick(1)
  remoteB:pick(1)
  remoteA:update()
  remoteB:update()
  local before = files[pathA]
  remoteA:confirm(true)
  remoteB:confirm(true)
  remoteA:update()
  remoteB:update()
  T.eq(remoteA:stage(), "commit_wait", "the negotiation completes into the barrier")
  T.eq(remoteB:stage(), "commit_wait", "on both ends")
  T.eq(relay.commits, 1, "the relay saw two equal digests")
  T.eq(files[pathA], before, "nothing is written before trade_commit arrives")
  local early = remoteA:commit()
  T.eq(early, false, "commit refuses before the relay committed")
  remoteA:update()
  remoteB:update()
  T.eq(remoteA:stage(), "committed", "trade_commit writes seat 0")
  T.eq(remoteB:stage(), "committed", "and seat 1")
  T.eq(remoteA:commit(), true, "commit reports the result it already has")
  T.eq(decodeAt(pathA).party[1].species, "ALAKAZAM",
    "the KADABRA arrives evolved")
  T.eq(decodeAt(pathB).party[1].species, "PIKACHU",
    "and the PIKACHU crosses the other way")
  T.eq(decodeAt(pathA).party[1].traded, true, "marked traded")
  T.eq(decodeAt(pathB).pokedex.owned.PIKACHU, true, "with the dex marked")
  remoteA:close()
  remoteB:close()
end

do
  files = {}
  local pathA = put("red", "slot1", gen1Save("RED", { gen1Mon("PIKACHU", 25) }))
  local pathB = put("red", "slot2",
    gen1Save("BLUE", { gen1Mon("KADABRA", 30) }))
  local diskA, diskB = files[pathA], files[pathB]
  local relay, remoteA, remoteB = remotePair("red", "slot1", "slot2", GEN1)
  local realPrepare = Trade.prepare
  Trade.prepare = function(plan)
    if plan.sides[1].handle == remoteB.handle then return false, "that save didn't validate" end
    return realPrepare(plan)
  end
  negotiate(remoteA, remoteB)
  remoteA:update()
  remoteB:update()
  Trade.prepare = realPrepare
  T.eq(remoteB:stage(), "cancelled", "a save that won't build backs out before the confirm")
  T.eq(remoteB.session.error, "that save didn't validate", "and says why")
  T.eq(relay.commits, 0, "so the relay never commits")
  T.eq(files[pathA], diskA, "and seat 0 writes nothing")
  T.eq(files[pathB], diskB, "nor seat 1")
end

do
  files = {}
  local pathA = put("red", "slot1", gen1Save("RED", { gen1Mon("PIKACHU", 25) }))
  local pathB = put("red", "slot2",
    gen1Save("BLUE", { gen1Mon("KADABRA", 30) }))
  local diskA, diskB = files[pathA], files[pathB]
  local relay, remoteA, remoteB, rsA = remotePair("red", "slot1", "slot2", GEN1)
  remoteA:start()
  remoteB:start()
  remoteA:update()
  remoteB:update()
  remoteA:pick(1)
  remoteB:pick(1)
  remoteA:update()
  remoteB:update()
  remoteB:confirm(true)
  remoteA:update()
  T.eq(remoteA:stage(), "confirming", "seat 0 still deciding")
  rsA.close()
  remoteB:update()
  T.eq(relay.aborts, 0, "no digest ever reached the relay")
  T.eq(remoteB:stage(), "cancelled", "the other trainer leaving calls it off")
  T.eq(remoteB.session.error, "the other trainer left", "and says so")
  T.eq(files[pathA], diskA, "a drop before commit writes nothing on seat 0")
  T.eq(files[pathB], diskB, "or seat 1")
end

do
  files = {}
  local pathA = put("red", "slot1", gen1Save("RED", { gen1Mon("PIKACHU", 25) }))
  local pathB = put("red", "slot2",
    gen1Save("BLUE", { gen1Mon("KADABRA", 30) }))
  local diskA, diskB = files[pathA], files[pathB]
  local relay, remoteA, remoteB = remotePair("red", "slot1", "slot2", GEN1, {
    tamper = function(seat, digest)
      if seat == 1 then return ("f"):rep(16) end
      return digest
    end })
  negotiate(remoteA, remoteB)
  remoteA:update()
  remoteB:update()
  T.eq(relay.aborts, 1, "unequal digests abort at the relay")
  T.eq(remoteA:stage(), "cancelled", "seat 0 cancels")
  T.eq(remoteA.session.error, "digest", "naming the digest")
  T.eq(files[pathA], diskA, "and writes nothing")
  T.eq(files[pathB], diskB, "on either side")
end

do
  files = {}
  local pathA = put("red", "slot1", gen1Save("RED", { gen1Mon("PIKACHU", 25) }))
  local pathB = put("red", "slot2",
    gen1Save("BLUE", { gen1Mon("KADABRA", 30) }))
  local _, remoteA, remoteB, _, rsB = remotePair("red", "slot1", "slot2", GEN1)
  negotiate(remoteA, remoteB)
  rsB.online = false
  remoteA:update()
  T.eq(remoteA:stage(), "committed", "seat 0 commits while seat 1 is dropped")
  remoteB:update()
  T.eq(remoteB:stage(), "commit_wait", "seat 1 waits through the drop")
  rsB.online = true
  remoteB:update()
  T.eq(remoteB:stage(), "committed", "and commits on the replay")
  T.eq(decodeAt(pathA).party[1].species, "ALAKAZAM", "both files are written")
  T.eq(decodeAt(pathB).party[1].species, "PIKACHU", "after a drop past the commit")
end

-- ------- a remote Gen 2 trade uses the Gen 2 codec

do
  files = {}
  local pathA = put("gold", "slot1",
    gen2Save("GOLD", { gen2Mon("TOTODILE", 20, { item = "LEFTOVERS" }) }))
  local pathB = put("gold", "slot2",
    gen2Save("SILVER", { gen2Mon("MACHOKE", 30) }))
  local _, remoteA, remoteB = remotePair("gold", "slot1", "slot2", GEN2)
  negotiate(remoteA, remoteB)
  T.eq(remoteB:stage(), "commit_wait", "the Gen 2 negotiation reaches the barrier")
  remoteA:update()
  remoteB:update()
  T.eq(remoteA:stage(), "committed", "and each side commits")
  T.eq(remoteB:stage(), "committed", "its own save")
  T.eq(decodeAt(pathA).party[1].species, "MACHAMP",
    "the MACHOKE arrives evolved")
  T.eq(decodeAt(pathB).party[1].species, "TOTODILE",
    "and the TOTODILE crosses back")
  T.eq(decodeAt(pathB).party[1].item, "LEFTOVERS",
    "still holding what it left with")
  remoteA:close()
  remoteB:close()
end

local LT = require("src.core.game3.link.trade")
local Protocol = require("src.link.Protocol")
local realWithDataset = Trade.withDataset

local function restart(relay)
  Trade._resolver, Trade._scanned = nil, false
  Trade._applied, Trade._journalPaths = {}, {}
  LT.outcomeClient = relay and relay:outcomeClient() or nil
  Trade.withDataset = function(version, fn)
    local data = version == "gold" and GEN2 or GEN1
    local ok, result = pcall(fn, data)
    if not ok then return nil, tostring(result) end
    return result
  end
  return LT.outcomeClient
end

local function settle(steps)
  for _ = 1, steps or 40 do
    if Trade.pumpPending(1000) == true then return true end
  end
  return false
end

local function journalAt(path)
  local body = files[Trade.journalPath(path)]
  local data = body and SaveData.decode(body) or nil
  return data and data.entries or nil
end

local function backupsOf(path)
  local n = 0
  for name in pairs(files) do
    if name:sub(1, #path + 11) == path .. ".trade-bak-" then n = n + 1 end
  end
  return n
end

do
  files = {}
  restart(nil)
  local pathA = put("red", "slot1", gen1Save("RED", { gen1Mon("PIKACHU", 25) }))
  local pathB = put("red", "slot2",
    gen1Save("BLUE", { gen1Mon("KADABRA", 30) }))
  local relay, remoteA, remoteB, _, rsB = remotePair("red", "slot1", "slot2", GEN1)
  negotiate(remoteA, remoteB)
  local jB = journalAt(pathB)
  T.eq(jB and #jB, 1, "seat 1 journals the trade before its confirm leaves")
  T.eq(jB and jB[1].room, relay.room, "keyed by the relay room")
  T.eq(jB and jB[1].digest, remoteB.digest, "and the digest it confirmed")
  T.eq(jB and jB[1].slotId, "slot2", "naming the save it belongs to")
  T.eq(jB and jB[1].sent.species, "KADABRA", "with the mon it sends")
  T.eq(jB and jB[1].record.species, "PIKACHU", "and the one it gets")
  T.check(journalAt(pathA) ~= nil, "seat 0 journals too")
  rsB.online = false
  remoteA:update()
  T.eq(remoteA:stage(), "committed", "seat 0 commits")
  T.eq(journalAt(pathA), nil, "and drops its journal after the save")
  remoteB:close()
  T.eq(decodeAt(pathB).party[1].species, "KADABRA",
    "seat 1 lost the link for good before trade_commit")

  local client = restart(relay)
  client.failNext = 1
  Trade.pumpPending(0)
  Trade.pumpPending(0)
  T.eq(#client.requests, 1, "the next launcher start asks the ledger")
  T.eq(client.requests[1].path, "/trade/outcome", "on the outcome route")
  T.eq(client.requests[1].room, relay.room, "for that room")
  T.eq(client.requests[1].digest, remoteB.digest, "and that digest")
  T.eq(client.requests[1].noAuth, true, "without an account")
  T.eq(decodeAt(pathB).party[1].species, "KADABRA", "an unreachable server changes nothing")
  T.check(journalAt(pathB) ~= nil, "and keeps the journal for a retry")
  T.eq(settle(), true, "the retry settles it")
  T.check(#client.requests >= 2, "after asking again")
  local disk = decodeAt(pathB)
  T.eq(disk.party[1].species, "PIKACHU", "the committed trade is applied to seat 1's save")
  T.eq(disk.party[1].traded, true, "as a traded mon")
  T.eq(disk.pokedex.owned.PIKACHU, true, "with the dex marked")
  T.eq(journalAt(pathB), nil, "and the journal is dropped")
  T.eq(backupsOf(pathB), 1, "the old file is backed up first")
  T.eq(decodeAt(pathA).party[1].species, "ALAKAZAM", "seat 0 keeps what it got")

  restart(relay)
  T.eq(settle(), false, "nothing is left to resolve")
  T.eq(decodeAt(pathB).party[1].species, "PIKACHU", "and nothing is applied twice")
end

do
  files = {}
  restart(nil)
  local pathA = put("red", "slot1", gen1Save("RED", { gen1Mon("PIKACHU", 25) }))
  local pathB = put("red", "slot2",
    gen1Save("BLUE", { gen1Mon("KADABRA", 30) }))
  local relay, remoteA, remoteB, _, rsB = remotePair("red", "slot1", "slot2", GEN1, {
    tamper = function(seat, digest)
      if seat == 0 then return ("f"):rep(16) end
      return digest
    end })
  negotiate(remoteA, remoteB)
  T.eq(relay.aborts, 1, "the relay aborts the round")
  rsB.online = false
  remoteA:update()
  T.eq(journalAt(pathA), nil, "a seat that hears trade_abort drops its journal")
  local before = files[pathB]
  remoteB:close()
  T.check(journalAt(pathB) ~= nil, "a seat that never heard it keeps one")
  local client = restart(relay)
  T.eq(settle(), true, "the ledger settles it")
  T.eq(#client.requests, 1, "in one ask")
  T.eq(files[pathB], before, "an aborted trade leaves the save alone")
  T.eq(journalAt(pathB), nil, "and drops the journal")
end

do
  files = {}
  restart(nil)
  put("red", "slot1", gen1Save("RED", { gen1Mon("PIKACHU", 25) }))
  local pathB = put("red", "slot2",
    gen1Save("BLUE", { gen1Mon("KADABRA", 30) }))
  put("red", "slot3", gen1Save("GREEN", { gen1Mon("PIKACHU", 9) }))
  local held = true
  local relay, remoteA, remoteB, _, rsB = remotePair("red", "slot1", "slot2", GEN1, {
    tamper = function(seat, digest)
      if held and seat == 0 then return nil end
      return digest
    end })
  negotiate(remoteA, remoteB)
  T.eq(relay.commits + relay.aborts, 0, "seat 0's confirm is still in flight")
  rsB.online = false
  remoteB:close()
  local client = restart(relay)
  Trade.pumpPending(0)
  Trade.pumpPending(0)
  T.eq(client.requests[1] and client.requests[1].digest, remoteB.digest, "the ledger is asked")
  T.eq(relay:outcome(relay.room, remoteB.digest), "open", "and says the round is open")
  T.eq(decodeAt(pathB).party[1].species, "KADABRA", "so nothing is applied yet")
  T.check(journalAt(pathB) ~= nil, "and the journal stays")
  local plan, why = Trade.plan({ from = open("red", "slot2", GEN1), fromIndex = 1,
    to = open("red", "slot3", GEN1), toIndex = 1 })
  T.eq(plan, nil, "a mon whose trade is unsettled can't be traded again")
  T.eq(why, "that POKéMON's last trade isn't settled yet", "and says why")
  held = false
  relay:_barrier(0, remoteB.digest)
  T.eq(relay.commits, 1, "the round commits late")
  T.eq(settle(), true, "the next ask settles it")
  T.eq(decodeAt(pathB).party[1].species, "PIKACHU", "applying the trade")
  T.eq(journalAt(pathB), nil, "and dropping the journal")
end

do
  files = {}
  restart(nil)
  local pathB = put("red", "slot2", gen1Save("BLUE", { gen1Mon("KADABRA", 30) }))
  local before = files[pathB]
  files[Trade.journalPath(pathB)] = SaveData.encode({ v = 1, entries = {
    { room = "r0123456789abcdef", digest = ("a"):rep(16), at = os.time() - 2 * 24 * 60 * 60,
      version = "red", slotId = "slot2", sent = Protocol.packMon(gen1Mon("KADABRA", 30)),
      record = gen1Mon("PIKACHU", 25) } } })
  local relay = Relay.new()
  local client = restart(relay)
  T.eq(settle(), true, "a journal older than a day settles")
  T.eq(#client.requests, 0, "without asking")
  T.eq(journalAt(pathB), nil, "by dropping it")
  T.eq(files[pathB], before, "and leaving the save alone")

  files[Trade.journalPath(pathB)] = SaveData.encode({ v = 1, entries = {
    { room = relay.room, digest = ("b"):rep(16), at = os.time(),
      version = "red", slotId = "slot2", sent = Protocol.packMon(gen1Mon("PIKACHU", 7)),
      record = gen1Mon("PIKACHU", 25) } } })
  relay.ledger[1] = { room = relay.room, n = 1, outcome = "commit", digests = { ("b"):rep(16) } }
  restart(relay)
  T.eq(settle(), true, "a commit whose sent mon is gone settles")
  T.eq(journalAt(pathB), nil, "by dropping the journal")
  T.eq(files[pathB], before, "without touching the save")
end

LT.outcomeClient = nil
Trade.withDataset = realWithDataset
Trade._resolver, Trade._scanned = nil, false
Trade._applied, Trade._journalPaths = {}, {}

SaveData.portableFs = realPortableFs

-- ------- backup pruning keeps the three most recent per slot

do
  local kept = {}
  local pruneFs = {
    getInfo = function(name) return kept[name] and { type = "file" } or nil end,
    read = function(name) return kept[name] end,
    write = function(name, body) kept[name] = body return true end,
    remove = function(name) kept[name] = nil return true end,
    createDirectory = function() return true end,
    getDirectoryItems = function(dir)
      local prefix, out = dir .. "/", {}
      for name in pairs(kept) do
        if name:sub(1, #prefix) == prefix then
          out[#out + 1] = name:sub(#prefix + 1)
        end
      end
      table.sort(out)
      return out
    end,
  }
  SaveData.portableFs = function() return pruneFs end

  local path = "saves/red/slot1.lua"
  kept[path] = "live"
  kept[path .. ".bak"] = "one back"
  for _, stamp in ipairs({ 100, 200, 300, 400, 500 }) do
    kept[("%s.trade-bak-%d"):format(path, stamp)] = "backup " .. stamp
  end
  kept["saves/red/slot2.lua.trade-bak-100"] = "another slot"

  T.eq(Trade.pruneBackups(path, 3), 2, "the two oldest backups are removed")
  T.eq(kept[path .. ".trade-bak-100"], nil, "the oldest is gone")
  T.eq(kept[path .. ".trade-bak-200"], nil, "and the next oldest")
  T.eq(kept[path .. ".trade-bak-300"], "backup 300", "three are kept")
  T.eq(kept[path .. ".trade-bak-500"], "backup 500", "the newest among them")
  T.eq(kept[path], "live", "the save itself is untouched")
  T.eq(kept[path .. ".bak"], "one back", "so is the ordinary .bak")
  T.eq(kept["saves/red/slot2.lua.trade-bak-100"], "another slot",
    "another slot's backups are not this slot's")
  T.eq(Trade.pruneBackups(path, 3), 0, "a second pass has nothing to remove")
  T.eq(Trade.pruneBackups("saves/red/slot9.lua", 3), 0,
    "a slot with no backups prunes nothing")
  T.eq(Trade.pruneBackups(nil, 3), 0, "and no path prunes nothing")

  SaveData.portableFs = realPortableFs
end

T.finish("online trade")
