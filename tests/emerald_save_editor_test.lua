package.path = "./?.lua;./?/init.lua;" .. package.path .. ";./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua"

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local GameVersion = require("src.core.GameVersion")
GameVersion.set("emerald")
require("src.import.gba.versions").select("emerald")

require("tests.game3_cache").mount("emerald")
local Dataset = require("src.core.game3.dataset")
local cache = Dataset.cache()
if not cache:read("data/generated/gba/native/manifest.lua") or not cache:read("data/generated/gba/items/pack.lua") then
  print("emerald_save_editor_test: skipped (no Emerald cache for identity "
    .. tostring(os.getenv("POKEPORT_IDENTITY") or "pokemon-love2d") .. ")")
  os.exit(0)
end
Dataset.mountExtractRoots()
Dataset.hydrate({ data = {} })

local Gen = require("Gen")
local Gen3Flags = require("Gen3Flags")
local Catalog = require("Catalog")
local G3 = require("Game3Adapter")
local Ops = require("Ops")
local State = require("State")
local Flags = require("src.core.game3.scripting.flags")
local Schema = require("src.core.game3.save_schema_firered")
local C = require("src.core.game3.constants").of("emerald")
local ItemsData = require("src.core.game3.items_data")
ItemsData.ensureModel()

local F = C.flags.byName
eq(Gen3Flags.rseGame(), "emerald", "editor sees the Emerald layout")

local cats = Gen3Flags.categories()
eq(#cats.trainers, C:require("trainers", "TRAINERS_COUNT") - 1, "one trainer flag per Emerald trainer")
eq(cats.trainers[1].flagId, F.TRAINER_FLAGS_START + 1, "trainer 1 flag")
eq(cats.trainers[1].name, "TRAINER_SAWYER_1", "trainer names from the Emerald opponents table")
local function find(list, name)
  for _, e in ipairs(list) do if e.name == name then return e end end
  return nil
end
check(find(cats.system, "FLAG_BADGE01_GET") ~= nil, "badge flag in system")
eq(find(cats.system, "FLAG_BADGE01_GET").id, 0x867, "Stone Badge flag id")
check(find(cats.system, "FLAG_DAILY_SECRET_BASE") ~= nil, "daily flags listed with system")
check(find(cats.items, "FLAG_ITEM_ROUTE_102_POTION") ~= nil, "item ball flags")
local hidden = 0
for _, e in ipairs(cats.items) do if e.name:find("^FLAG_HIDDEN_ITEM_") then hidden = hidden + 1 end end
check(hidden > 50, "hidden item flags (" .. hidden .. ")")
check(find(cats.toggles, "FLAG_HIDE_LITTLEROOT_TOWN_FAT_MAN") ~= nil or #cats.toggles > 100, "hide flags as toggles")
check(find(cats.vars, "VAR_NATIONAL_DEX") ~= nil, "Emerald vars listed")
eq(find(cats.vars, "VAR_NATIONAL_DEX").id, 0x4046, "VAR_NATIONAL_DEX id")
for _, e in ipairs(cats.story) do
  if type(e.id) == "number" and e.id >= F.TRAINER_FLAGS_START and e.id <= F.TRAINER_FLAGS_END then
    check(false, "trainer flag leaked into story: " .. e.name)
  end
end
local events = Catalog.game3EventList()
local has = false
for _, n in ipairs(events) do if n == "FLAG_SYS_NATIONAL_DEX" then has = true end end
check(has, "event list comes from the Emerald flag table")

local save = Schema.newGame({ version = "emerald", name = "MAY", gender = 1 })
eq(Gen.of(save), 3, "Emerald save is generation 3")
eq(Gen.of({ version = "emerald" }), 3, "Emerald version tag alone is generation 3")
local ids = Gen.badgeIds(save)
eq(ids[1], "STONEBADGE", "first Emerald badge")
eq(ids[8], "RAINBADGE", "eighth Emerald badge")
eq(Gen.toggleBadge(save, "STONEBADGE"), true, "toggle Stone Badge on")
eq(save.flags[0x867], true, "Stone Badge writes 0x867")
eq(save.flags[0x820], nil, "not the FireRed Boulder Badge flag")
Gen.setFlag(save, "FLAG_SYS_B_DASH", true)
eq(save.flags[F.FLAG_SYS_B_DASH], true, "named flag resolves through the Emerald table (0x8C0)")
Gen.setVar(save, "VAR_STARTER_MON", 2)
eq(save.vars[0x4023], 2, "VAR_STARTER_MON is 0x4023 on Emerald")
eq(Gen.getVar(save, "VAR_STARTER_MON"), 2, "named var reads back")

eq(G3.pcItemsCount(), 50, "Emerald PC holds 50 items")
local data = { items = {} }
local S = State.new()
S.data = data
S.save = save
S.version = "emerald"
G3.hydrate(data, S.save)
local potion = C:require("items", "ITEM_POTION")
local tm01 = C:require("items", "ITEM_TM01")
local cheri = C:require("items", "ITEM_CHERI_BERRY")
check(G3.change(data, S.save, false, { { id = potion, qty = 99 } }), "99 Potions fit one slot")
check(not G3.change(data, S.save, false, { { id = potion, qty = 150 } }), "150 Potions refused (99 per slot)")
check(G3.change(data, S.save, false, { { id = cheri, qty = 500 } }), "berries stack to 999")
check(G3.change(data, S.save, false, { { id = tm01, qty = 1 } }), "TM01 added")
local tmCase = false
for _, slot in ipairs(S.save.bag.pockets.KEY_ITEMS or {}) do
  if slot.id == ItemsData.ITEM_TM_CASE then tmCase = true end
end
check(not tmCase, "no phantom TM Case on Emerald")
local pcList = {}
for i = 1, 50 do pcList[#pcList + 1] = { id = i, qty = 1 } end
S.save.storage.items = pcList
G3.project(data, S.save)
check(not G3.change(data, S.save, true, { { id = 200, qty = 1 } }), "a 51st PC stack is refused")

Ops.toggleNationalDex(S)
eq(S.save.flags[F.FLAG_SYS_NATIONAL_DEX], true, "National Dex toggle sets FLAG_SYS_NATIONAL_DEX (0x896)")
eq(S.save.vars[0x4046], 0x302, "National Dex toggle sets VAR_NATIONAL_DEX 0x302")
eq(S.save.flags[0x829], nil, "no FireRed POKEDEX_GET write")

local SaveConvert = require("src.save_convert.SaveConvert")
local Gen3Save = require("src.save_convert.Gen3Save")
local out = assert(SaveConvert.exportSav(G3.export(S.save), "emerald", nil))
local c = assert(Gen3Save.forVersion("emerald").decode(out))
eq(c.name, "MAY", "edited save exports to an Emerald cart")
eq(c.dexNationalMagic, 0xDA, "national magic 0xDA exported")
local badge = false
for _, id in ipairs(c.flags) do if id == 0x867 then badge = true end end
check(badge, "Stone Badge exported")
local potions = 0
for _, it in ipairs(c.pockets.ITEMS) do if it.id == potion then potions = potions + it.qty end end
eq(potions, 99, "Potions exported")

T.finish("emerald_save_editor")
