package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq
local GameVersion = require("src.core.GameVersion")

GameVersion.set("emerald")
require("src.import.gba.versions").select("emerald")
require("tests.game3_cache").mount("emerald")
local Dataset = require("src.core.game3.dataset")
local cache = Dataset.cache()
if not cache:read("data/generated/gba/native/manifest.lua") or not cache:read("data/generated/gba/pokemon/national.lua") then
  print("[skip] emerald_engine_pret_defaults_test: no Emerald cache for identity "
    .. tostring(os.getenv("POKEPORT_IDENTITY") or "pokemon-love2d"))
  os.exit(0)
end
Dataset.mountExtractRoots()
Dataset.hydrate({ data = {} })

local Profile = require("src.core.game3.profile")
local Storage = require("src.core.game3.storage")
local Schema = require("src.core.game3.save_schema_firered")
local Dex = require("src.core.game3.dex")
local OldMan = require("src.core.game3.rse.old_man")
local List = require("src.ui.game3.rse.pokedex_list")

local em = Profile.of("emerald")
eq(em.bag.pcItems, 50, "PC_ITEMS_COUNT (pokeemerald/include/constants/global.h:50)")
eq(em.bag.capacity.ITEMS, 30, "BAG_ITEMS_COUNT")
eq(em.bag.capacity.KEY_ITEMS, 30, "BAG_KEYITEMS_COUNT")
eq(em.bag.capacity.POKE_BALLS, 16, "BAG_POKEBALLS_COUNT")
eq(em.bag.capacity.TM_CASE, 64, "BAG_TMHM_COUNT")
eq(em.bag.capacity.BERRY_POUCH, 46, "BAG_BERRIES_COUNT")
eq(Storage.pcItemsCount({ version = "emerald" }), 50, "Storage honours the Emerald PC capacity")

for b = 1, Storage.TOTAL_BOXES_COUNT do
  eq(Storage.new().boxes[b].wallpaper, ((b - 1) % 4) + 1, "box " .. b .. " default wallpaper is boxId % (MAX_DEFAULT_WALLPAPER + 1)")
end

local session = Schema.newGame({ version = "emerald", name = "TEST" })
Dex.enableNational(session)
eq(session.pokedex and session.pokedex.mode, List.DEX_MODE_NATIONAL, "EnableNationalPokedex sets mode national")
eq(session.pokedex and session.pokedex.order, 0, "and order numerical")
session.pokedex.order = List.ORDER_ALPHABETICAL
local back = Schema.fromSaveTable(Schema.toSaveTable(session))
eq(back.pokedex and back.pokedex.mode, List.DEX_MODE_NATIONAL, "dex mode survives save and load")
eq(back.pokedex and back.pokedex.order, List.ORDER_ALPHABETICAL, "dex order survives save and load")

local bard = OldMan.set({ trainerId = 0, version = "emerald" })
eq(bard.id, OldMan.BARD, "trainer id 0 picks the bard")
for i = 1, OldMan.NUM_BARD_SONG_WORDS do
  eq(bard.newSongLyrics[i], 0, "SetupBard leaves newSongLyrics[" .. i .. "] zeroed")
end
local teller = OldMan.set({ trainerId = 6, version = "emerald" })
eq(teller.id, OldMan.STORYTELLER, "trainer id 6 picks the storyteller")
for i = 1, OldMan.NUM_STORYTELLER_TALES do
  eq(teller.language[i], 0, "StorytellerSetup leaves language[" .. i .. "] zeroed")
end

T.finish()
