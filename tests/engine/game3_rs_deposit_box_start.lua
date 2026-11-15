package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq

require("tests.game3_cache").stubSpeciesNames()
require("tests.fixture_data.game3_items").install()
require("tests.fixture_data.game3_battle_moves").install()
package.loaded["src.core.game3.rom_text"] = {
  plain = function(key) return key end, box = function(key) return key end,
  ascii = function(key) return key end, has = function() return true end,
  key = function(n, i) return n .. "[" .. i .. "]" end,
  at = function(n, i) return n .. "[" .. i .. "]" end,
  count = function() return 0 end, list = function() return {} end,
  lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
}

package.loaded["src.ui.game3.rs.storage_visuals"] = {
  slotImages = function() return nil, nil end,
  textColors = function() return { fg = {}, shadow = {} } end,
}
local GameVersion = require("src.core.GameVersion")
local Storage = require("src.core.game3.storage")
local BoxStorageUI = require("src.ui.game3.box_storage_ui")
local Choose = require("src.ui.game3.storage_choose_box")

local function mon(species)
  return { species = species, speciesId = species, level = 5, hp = 20, maxHp = 20, moves = { 33 }, pp = { 35 } }
end

local function settle()
  for _ = 1, 600 do
    if not BoxStorageUI.isPresentationBusy() then break end
    BoxStorageUI.update(1 / 60)
  end
end

local function press(key)
  settle()
  BoxStorageUI.handleInput({
    wasPressed = function(_, k) return k == key end,
    isDown = function(_, k) return k == key end,
  })
  settle()
end

local function open(version)
  GameVersion.set(version)
  local session = { version = version, party = { mon(1), mon(4), mon(7), mon(10) } }
  Storage.ensure(session)
  BoxStorageUI.show({ session = session, subMode = "deposit" })
  BoxStorageUI._presentation = nil
  for _ = 1, 600 do
    if not BoxStorageUI.isPresentationBusy() then break end
    BoxStorageUI.update(1 / 60)
  end
  return session, Storage.ensure(session)
end

local function store(slot)
  BoxStorageUI.mode, BoxStorageUI.drawerOpen, BoxStorageUI.partyCursor = "party_drawer", true, slot
  press("a")
  eq(BoxStorageUI.mode, "action_menu", "A on a party mon opens its menu")
  eq((BoxStorageUI._activeActions or {})[BoxStorageUI.actionCursor], "STORE", "the cursor sits on STORE")
  press("a")
end

for _, version in ipairs({ "ruby", "sapphire" }) do
  print("[test] " .. version)
  local session, storage = open(version)
  storage.currentBox = 5
  -- pokeruby/src/pokemon_storage_system_2.c:187
  store(2)
  eq(BoxStorageUI.mode, "pick_box", version .. ": STORE asks which box")
  eq(BoxStorageUI._pickBox, 1, version .. ": the first deposit starts on BOX 1, not the current box")
  press("right"); press("right")
  press("a")
  eq(#session.party, 3, version .. ": A stores the mon")
  eq(Choose.boxCount(storage.boxes[3]), 1, version .. ": the mon went into BOX 3")

  -- pokeruby/src/pokemon_storage_system_2.c:896
  store(1)
  eq(BoxStorageUI._pickBox, 3, version .. ": the next deposit starts on the last box used")
  press("b")
  eq(#session.party, 3, version .. ": cancel stores nothing")

  for i = 1, 30 do storage.boxes[4].mons[i] = mon(16) end
  store(1)
  press("right")
  press("a")
  eq(BoxStorageUI.mode, "deposit_box_full", version .. ": a full box says so")
  press("a")
  eq(BoxStorageUI.mode, "pick_box", version .. ": A returns to the chooser")
  press("b")
  -- pokeruby/src/pokemon_storage_system_2.c:923
  store(1)
  eq(BoxStorageUI._pickBox, 4, version .. ": a full box choice is remembered too")
  press("b")

  -- pokeruby/src/pokemon_storage_system_2.c:1242
  BoxStorageUI.mode, BoxStorageUI.boxMenuCursor = "box_menu", 1
  press("a")
  eq(BoxStorageUI.mode, "pick_box", version .. ": JUMP opens the chooser")
  eq(BoxStorageUI._pickBox, 5, version .. ": the jump chooser starts on the current box")
  press("b")
  BoxStorageUI.reset()

  session, storage = open(version)
  storage.currentBox = 6
  store(1)
  eq(BoxStorageUI._pickBox, 1, version .. ": reopening the PC starts the deposit chooser on BOX 1 again")
  press("b")
  BoxStorageUI.reset()
end

T.finish("game3_rs_deposit_box_start")
