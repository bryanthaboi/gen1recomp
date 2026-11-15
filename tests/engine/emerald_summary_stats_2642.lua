package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("tests.harness").suite("Emerald summary stats #2642")
local Cache = require("tests.game3_cache")
local root = Cache.root("emerald", "rse/summary/manifest.lua")
if not root then print("[skip] #2642 summary: " .. tostring(Cache.reason)); T.finish(); return end
local manifestFile = assert(loadfile(root .. "/rse/summary/manifest.lua"))
local before = os.getenv("SUMMARY2642_BEFORE")
if before then
  for _, path in ipairs({ "src/core/game3/battle_bridge", "src/ui/game3/rse/summary_menu" }) do
    package.loaded[path:gsub("/", ".")] = assert(loadfile(before .. "/" .. path .. ".lua"))()
  end
end
local Dataset = require("src.core.game3.dataset")
Dataset.cacheRootOverride = root; Dataset.mountExtractRoots()
require("src.core.GameVersion").set("emerald")
local game = { data = {} }; Dataset.hydrate(game)
local Schema = require("src.core.game3.save_schema_firered")
local session = Schema.newGame({ version = "emerald", name = "MAY" })
game.session = session
local Runtime = require("src.core.game3.runtime")
Runtime.start(nil, game, session, { reason = "new_game" })
local Party = require("src.core.game3.party")
local Pokemon = require("src.core.game3.pokemon")
local Bridge = require("src.core.game3.battle_bridge")
local Battle = require("src.core.game3.battle")
local Experience = require("src.core.game3.battle.experience")
local Rse = require("src.ui.game3.rse.summary_menu")
local Kit = require("src.ui.game3.rse.scene_kit")
local PalText = require("src.ui.game3.rse.pal_text")
local Serializer = require("src.core.SaveSerializer")
local mapping = { atk = "attack", def = "defense", spe = "speed", spa = "spAtk", spd = "spDef" }
local drawSkills
for i = 1, 50 do
  local name, value = debug.getupvalue(Rse.draw, i)
  if not name then break end
  if name == "drawSkills" then drawSkills = value; break end
end
assert(drawSkills)
local manifest = manifestFile()
local oldPal, oldImage = PalText.draw, Kit.image
local function columns(mon)
  local left, right
  PalText.draw = function(text)
    if type(text) ~= "string" or not text:find("\n", 1, true) then return end
    local nums = {}; for n in text:gmatch("%d+") do nums[#nums + 1] = tonumber(n) end
    if text:find("/", 1, true) then left = nums else right = nums end
  end
  Kit.image = function() return nil end
  drawSkills(manifest, { _party = { mon }, _cursor = 1 }, mon)
  PalText.draw, Kit.image = oldPal, oldImage
  return left, right
end
local function rendered(mon, wanted, label)
  local left, right = columns(mon)
  T.check(left and right, label .. " both actual Skills columns")
  T.check(left and left[3] == wanted.atk and left[4] == wanted.def, label .. " current attack/defense")
  T.check(right and right[1] == wanted.spa and right[2] == wanted.spd and right[3] == wanted.spe, label .. " current special/speed")
end
local ok, _, mon = Party.giveMon(session, 277, 5)
assert(ok and mon)
mon.customCounter = 4095; mon.customData = { tag = "opaque", nested = { sentinel = 17 } }
local identity, opaque = mon, mon.customData
local ivs = Serializer.encode(mon.ivs)
local BattleStart = Battle.start
Battle.start = function(opts) opts.autoFight = false; return BattleStart(opts) end
for _, level in ipairs({ 7, 9 }) do
  T.check(Bridge.start(nil, game, { species = 129, level = 100, moves = { 150 }, pp = { 40 } },
    { wild = true, headless = true, fade = false }), "actual native bridge starts level " .. level)
  local src = assert(Bridge._battleParty[1])
  Experience.apply(src, Experience.expForLevel(src, level) - src.exp)
  local wanted = {}; for short, long in pairs(mapping) do wanted[short] = src[long] end
  Bridge.finishPending("win")
  T.eq(mon.level, level, "actual finish writes awarded level " .. level)
  T.check(session.party[1] == identity and mon.customData == opaque and mon.customCounter == 4095,
    "production writeback preserves mon/opaque identity " .. level)
  T.eq(Serializer.encode(mon.ivs), ivs, "production writeback preserves IVs " .. level)
  for short, long in pairs(mapping) do
    T.eq(mon[long], wanted[short], "production current canonical " .. long .. " level " .. level)
    T.eq(mon[short], wanted[short], "production current alias " .. short .. " level " .. level)
  end
  rendered(mon, wanted, "production level " .. level)
  local native = assert(Serializer.decode(Serializer.encode(session)))
  for short, long in pairs(mapping) do T.eq(native.party[1][short], wanted[short], "native serializer current " .. short) end
  rendered(native.party[1], wanted, "native serializer level " .. level)
end
Battle.start = BattleStart
local wanted = {}; for short, long in pairs(mapping) do wanted[short] = mon[long] end
mon.stats = { atk = 1, def = 2, spe = 3, spa = 4, spd = 5, attack = 6, defense = 7, speed = 8, spAtk = 9, spDef = 10 }
local stale = Serializer.encode(mon.stats)
rendered(mon, wanted, "canonical overrides stale nested and alias shapes")
T.eq(Serializer.encode(mon.stats), stale, "Skills draw leaves opaque nested stats untouched")
local fake = { hp = 0, maxHp = 0, stats = {} }
for short, long in pairs(mapping) do fake[long] = 0; fake[short] = 77; fake.stats[short] = 88; fake.stats[long] = 99 end
rendered(fake, { atk = 0, def = 0, spe = 0, spa = 0, spd = 0 }, "canonical zero is authoritative")
for _, shape in ipairs({ "top short", "nested short", "nested long" }) do
  local legacy = { hp = 10, maxHp = 20, stats = {} }
  local values = { atk = 11, def = 12, spe = 13, spa = 14, spd = 15 }
  for short, long in pairs(mapping) do
    if shape == "top short" then legacy[short] = values[short]
    elseif shape == "nested short" then legacy.stats[short] = values[short]
    else legacy.stats[long] = values[short] end
  end
  rendered(legacy, values, "legacy " .. shape)
end
local codec = require("src.save_convert.Gen3Save").forVersion("emerald")
local cart = assert(codec.fromPortMon(mon, { trainerId = session.trainerId or 1, secretId = session.secretId or 0 }, true))
local decoded = assert(codec.decodePartyMon(codec.encodePartyMon(cart)))
for _, key in ipairs({ "attack", "defense", "speed", "spAtk", "spDef" }) do
  T.eq(decoded[key], mon[key], "actual 100-byte SRAM party codec current " .. key)
end
local saveTable = Schema.toSaveTable(session)
local SaveData = require("src.core.SaveData")
local portable = SaveData.portableFs
SaveData.portableFs = function() return love.filesystem end
T.check(SaveData.save(saveTable), "actual native save uses only in-memory filesystem")
local restored = assert(SaveData.load("emerald"))
SaveData.portableFs = portable
for short, long in pairs(mapping) do T.eq(restored.party[1][short], mon[long], "actual native loaded alias " .. short) end
T.eq(restored.party[1].customData.nested.sentinel, 17, "actual native load preserves opaque nested metadata")
local flash = assert(codec.exportPort(saveTable, { version = "emerald", metGame = 3,
  toNational = Pokemon.national, speciesFromNational = Pokemon.speciesFromNational,
  mapLayoutId = function(group, num)
    local f = assert(io.open(root .. "/map_tree/maps/" .. group .. "_" .. num .. "/header.json", "rb"))
    local s = f:read("*a"); f:close(); return tonumber(s:match('"layoutId"%s*:%s*(%d+)'))
  end,
  healWarp = function()
    return codec.cartWarp({ map = "EM_LITTLEROOT_TOWN_MAYS_HOUSE_2F", warpId = -1, x = 4, y = 2 })
  end,
  itemId = function(id) return tonumber(id) end }))
T.eq(#flash, 0x20000, "actual Emerald export creates complete flash image")
local flashMon = assert(codec.decode(flash)).party[1]
for _, key in ipairs({ "attack", "defense", "speed", "spAtk", "spDef" }) do
  T.eq(flashMon[key], mon[key], "full checksummed Emerald SRAM export current " .. key)
end
T.finish()
