#!/usr/bin/env luajit
-- pokefirered/src/item_use.c:286 FieldUseFunc_Rod
-- pokefirered/src/item_use.c:359 FieldUseFunc_PokeFlute
-- pokefirered/src/item_use.c:582 FieldUseFunc_BlackWhiteFlute
-- pokefirered/src/field_player_avatar.c:1679 StartFishing

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function finish()
  if failed > 0 then
    print("[test] FAILED " .. failed)
    os.exit(1)
  end
  print("[test] all passed")
  os.exit(0)
end

local GameVersion = require("src.core.GameVersion")
GameVersion.set("firered")

local Cache = require("tests.game3_cache")
local cacheRoot = Cache.mount("scripts/events.lua", { native = true })
if not cacheRoot then
  print("[skip] game3_field_items_test: " .. tostring(Cache.reason))
  os.exit(0)
end
print("[info] FireRed cache at " .. cacheRoot)

local Dataset = require("src.core.game3.dataset")
local Collision = require("src.core.game3.collision")
local Objects = require("src.core.game3.objects")
local Player = require("src.core.game3.player")
local Field = require("src.core.game3.field")
local Space = require("src.core.game3.scripting.space")
local Flags = require("src.core.game3.scripting.flags")
local ItemUse = require("src.core.game3.item_use")
local ItemsData = require("src.core.game3.items_data")
local Encounters = require("src.core.game3.encounters")
local Message = require("src.ui.game3.message")
local Rng = require("src.core.game3.rng")
local Runtime = require("src.core.game3.runtime")
local Bag = require("src.core.game3.bag")
local BagMenu = require("src.ui.game3.bag_menu")
local Game3 = require("src.core.Game3")

local selectInput = {
  wasPressed = function(_, key) return key == "select" end,
  isDown = function() return false end,
}
local bagInput = {
  _p = {},
  wasPressed = function(self, key) return self._p[key] == true end,
  isDown = function() return false end,
  press = function(self, key) self._p = { [key] = true } end,
}

local ITEM_OLD_ROD, ITEM_GOOD_ROD, ITEM_SUPER_ROD = 262, 263, 264
local ITEM_BLACK_FLUTE, ITEM_WHITE_FLUTE, ITEM_POKE_FLUTE = 42, 43, 350
local FLAG_SYS_WHITE_FLUTE_ACTIVE = 0x803
local FLAG_SYS_BLACK_FLUTE_ACTIVE = 0x804

local game = { data = {} }
Dataset.hydrate(game)
local session = { map = nil, flags = {}, vars = {}, party = {}, name = "RED", bag = Bag.new() }
game.session = session
Runtime.session = session
Bag.add(session.bag, ITEM_OLD_ROD, 1)
Bag.add(session.bag, ITEM_POKE_FLUTE, 1)

local function enterMap(mapId)
  local def = game.data.maps[mapId]
  if not def then return nil end
  Field._game = game
  Field._session = session
  session.map = mapId
  Field.running = true
  Field.locked = false
  Field.clearMetatiles()
  Space.activate(nil, mapId, game, nil)
  Collision.bindMap(game, mapId, def)
  Objects.loadMap(game, mapId, def)
  return def
end

local function standAt(x, y, facing)
  Player.moving = false
  Player.progress = 0
  Player.surfing = false
  Player.cellX, Player.cellY = x, y
  Player.targetX, Player.targetY = x, y
  Player.px, Player.py = x * 16, y * 16
  Player.facing = facing or "down"
end

print("[test] 1. the rods and flutes are the items pret says they are")
check(ItemsData.info(ITEM_OLD_ROD).name == "OLD ROD", "262 is the OLD ROD")
check(tonumber(ItemsData.info(ITEM_OLD_ROD).secondaryId) == 0, "its secondaryId is rod 0")
check(tonumber(ItemsData.info(ITEM_GOOD_ROD).secondaryId) == 1, "GOOD ROD is rod 1")
check(tonumber(ItemsData.info(ITEM_SUPER_ROD).secondaryId) == 2, "SUPER ROD is rod 2")
check(ItemsData.fieldUseKind(ITEM_OLD_ROD) == "key",
  "the pack files the rods under fieldUse key, which the old reject swallowed")
check(ItemsData.fieldUseKind(ITEM_WHITE_FLUTE) == "none",
  "and the WHITE FLUTE under fieldUse none")

print("[test] 2. Pallet Town beach: CanFish")
local def = enterMap("FR_PALLET_TOWN")
check(def ~= nil, "FR_PALLET_TOWN is in the cache")
if not def then finish() end
standAt(7, 16, "up")
check(ItemUse.canFish() == false, "facing inland, the rod is refused")
local ok, kind, text = ItemUse.useField(session, session.bag, ITEM_OLD_ROD, nil)
check(ok == false and kind == "rod", "useField refuses it")
check(type(text) == "string" and text:find("time to use that", 1, true) ~= nil,
  "with gText_OakForbidsUseOfItemHere")
check(Field.isFishing() == false, "no fishing task started")
check(Message.isOpen() == false, "and useField itself printed nothing")
-- pokefirered/src/item_menu.c:2022 UseRegisteredKeyItemOnField
session.registeredItem = ITEM_OLD_ROD
Game3._handleRegisteredItem({ input = selectInput, session = session })
-- pokefirered/src/item_use.c:294 PrintNotTheTimeToUseThat
check(Message.isOpen() == true, "the refusal prints on the field instead of vanishing")
local guardA = 0
while Message.isOpen() and guardA < 40 do
  Message.advance()
  guardA = guardA + 1
end
check(Message.isOpen() == false, "one A press per page closes it")

standAt(7, 16, "down")
check(ItemUse.canFish() == true, "facing the water, the rod is allowed")
check(Encounters.hasFishingMons("FR_PALLET_TOWN") == true, "Pallet Town has fishing mons")

print("[test] 3. the dot game runs and misses")
local function seedFor(wantBite)
  for s = 1, 2000 do
    Rng.SeedRng(s)
    Rng.Random()
    if (((Rng.Random() % 2) == 0) == wantBite) then return s end
  end
  return nil
end

local missSeed = seedFor(false)
check(missSeed ~= nil, "found a seed whose second roll misses")
Rng.SeedRng(missSeed)
ok, kind = ItemUse.useField(session, session.bag, ITEM_OLD_ROD, nil)
check(ok == true and kind == "rod", "useField starts the rod")
check(Field.isFishing() == true, "a fishing task is running")
check(Player.fishing == true, "the player is holding the rod")
check(Field.locked == true, "field controls are locked")
check(Message.isOpen() == false, "no text box in the first second")

for _ = 1, 59 do Field.updateFishing() end
check(Message.isOpen() == false, "still none at 59 frames")
Field.updateFishing()
check(Message.isOpen() == true, "the box opens after 60 frames")

local dots = 0
local guard = 0
while Field.isFishing() and guard < 600 do
  guard = guard + 1
  Field.updateFishing()
  local page = Message.currentPage()
  local n = select(2, page:gsub("·", ""))
  if n > dots then dots = n end
  if page:find("nibble", 1, true) or page:find("hook", 1, true) then break end
end
check(dots >= 4 and dots <= 10, "between 4 and 10 dots were printed (" .. dots .. ")")
check(Message.currentPage():find("Not even a nibble", 1, true) ~= nil,
  "the miss prints Not even a nibble (" .. tostring(Message.currentPage()) .. ")")
check(Field.isFishing() == true, "the task waits for the player to close the box")
for _ = 1, 400 do
  if Message.isWaiting() then break end
  Message.tick()
end
Message.advance()
check(Field.isFishing() == false, "closing it ends the task")
check(Player.fishing == false, "the rod is put away")
check(Field.locked == false, "field controls are free again")

print("[test] 4. a bite reaches the hook message")
local biteSeed = seedFor(true)
check(biteSeed ~= nil, "found a seed whose second roll bites")
Rng.SeedRng(biteSeed)
ItemUse.useField(session, session.bag, ITEM_SUPER_ROD, nil)
check(Field.isFishing() == true, "the SUPER ROD starts a task too")
guard = 0
while Field.isFishing() and guard < 600 do
  guard = guard + 1
  Field.updateFishing()
  if Message.currentPage():find("hook", 1, true) then break end
end
check(Message.currentPage():find("A POKéMON's on the hook!", 1, true) ~= nil,
  "the bite prints gText_PokemonOnHook (" .. tostring(Message.currentPage()) .. ")")
Message.close()
Field._fishing = nil
Player.fishing = false
Field.locked = false

print("[test] 5. the POKé FLUTE wakes sleeping party mons")
session.party = {
  { species = 1, level = 10, hp = 20, maxHp = 20, status = "SLP", sleep = 3 },
  { species = 4, level = 10, hp = 20, maxHp = 20 },
}
ok, kind, text = ItemUse.useField(session, session.bag, ITEM_POKE_FLUTE, nil)
check(ok == true and kind == "flute", "the flute plays")
check(session.party[1].status == nil and (tonumber(session.party[1].sleep) or 0) == 0,
  "the sleeping mon woke up")
check(type(text) == "string" and text:find("awakened", 1, true) ~= nil,
  "it prints gText_PokeFluteAwakenedMon")
check(Message.isOpen() == false, "useField itself printed nothing")

session.party[1].status = "SLP"
session.party[1].sleep = 3
-- pokefirered/src/data/items.h:5318 ITEM_POKE_FLUTE registrability 0
BagMenu.show(session, { session = session, bag = session.bag, pocket = "KEY_ITEMS" })
BagMenu.settle()
for i, r in ipairs(BagMenu.list()) do
  if ItemsData.toNumericId(r.id) == ITEM_POKE_FLUTE then BagMenu.cursor = i end
end
bagInput:press("a")
BagMenu.handleInput(bagInput)
check(BagMenu.mode == "action", "the flute opens the item's action menu")
for k, a in ipairs(BagMenu.ACTIONS) do
  if a == "USE" then BagMenu.actionCursor = k end
end
bagInput:press("a")
BagMenu.handleInput(bagInput)
BagMenu.settle()
check(session.party[1].status == nil and (tonumber(session.party[1].sleep) or 0) == 0,
  "the bag USE woke the mon too")
-- pokefirered/src/item_use.c:374 DisplayItemMessageInBag
check(BagMenu.isOpen() == true and BagMenu.mode == "message",
  "and the box is on screen, not dropped on the floor")
check(Message.isOpen() == false, "nothing escaped to the field message box")
local pages = {}
local guardF = 0
while BagMenu.mode == "message" and guardF < 40 do
  pages[#pages + 1] = tostring(BagMenu.messageText)
  bagInput:press("a")
  BagMenu.handleInput(bagInput)
  guardF = guardF + 1
end
check(table.concat(pages, "\n"):find("awakened", 1, true) ~= nil,
  "gText_PokeFluteAwakenedMon is one of the bag's pages")
check(BagMenu.mode == "list", "paging through it returns to the item list")
BagMenu.close()
ok, kind, text = ItemUse.useField(session, session.bag, ITEM_POKE_FLUTE, nil)
check(ok == true and text:find("catchy tune", 1, true) ~= nil,
  "with nobody asleep it prints gText_PlayedPokeFluteCatchy")

print("[test] 6. the WHITE and BLACK FLUTES move the encounter rate")
local base = Encounters.encounterRate(20, { ignoreAbility = true })
ok, kind, text = ItemUse.useField(session, session.bag, ITEM_WHITE_FLUTE, nil)
check(ok == true and kind == "flute", "the WHITE FLUTE is usable")
check(text:find("lured", 1, true) ~= nil, "it prints gText_UsedVar2WildLured")
check(Flags.getFlag(Space.store, nil, FLAG_SYS_WHITE_FLUTE_ACTIVE) == true,
  "FLAG_SYS_WHITE_FLUTE_ACTIVE is set")
check(Flags.getFlag(Space.store, nil, FLAG_SYS_BLACK_FLUTE_ACTIVE) == false,
  "FLAG_SYS_BLACK_FLUTE_ACTIVE is clear")
local lured = Encounters.encounterRate(20, { ignoreAbility = true })
check(lured == base + math.floor(base / 2),
  "the rate rises by half (" .. base .. " -> " .. lured .. ")")

ok, kind, text = ItemUse.useField(session, session.bag, ITEM_BLACK_FLUTE, nil)
check(ok == true and text:find("repelled", 1, true) ~= nil,
  "the BLACK FLUTE prints gText_UsedVar2WildRepelled")
check(Flags.getFlag(Space.store, nil, FLAG_SYS_BLACK_FLUTE_ACTIVE) == true,
  "FLAG_SYS_BLACK_FLUTE_ACTIVE is set")
check(Flags.getFlag(Space.store, nil, FLAG_SYS_WHITE_FLUTE_ACTIVE) == false,
  "and the white one was cleared, pret FlagClear")
local repelled = Encounters.encounterRate(20, { ignoreAbility = true })
check(repelled == math.floor(base / 2),
  "the rate halves (" .. base .. " -> " .. repelled .. ")")

finish()
