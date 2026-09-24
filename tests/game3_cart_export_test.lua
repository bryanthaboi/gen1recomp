#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local GAME = require("tests.game3_cart_cache").mountOrSkip("game3_cart_export_test")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function unrle(s)
  local out = {}
  for tok in s:gmatch("%S+") do
    local k, n = tok:match("^([ZF])(%x+)$")
    if k then
      out[#out + 1] = string.rep(k == "Z" and "\0" or "\255", tonumber(n, 16))
    else
      out[#out + 1] = (tok:gsub("%x%x", function(h) return string.char(tonumber(h, 16)) end))
    end
  end
  return table.concat(out)
end

local function memfs(files)
  return {
    files = files,
    write = function(path, content) files[path] = content return true end,
    read = function(path) return files[path] end,
    remove = function(path) files[path] = nil return true end,
    getInfo = function(path)
      if files[path] then return { type = "file" } end
      local prefix = path .. "/"
      for key in pairs(files) do
        if key:sub(1, #prefix) == prefix then return { type = "directory" } end
      end
      return nil
    end,
    createDirectory = function() return true end,
    getSaveDirectory = function() return "/fake/save" end,
  }
end

local SaveData = require("src.core.SaveData")
local GameVersion = require("src.core.GameVersion")
local SaveFileIO = require("src.import.SaveFileIO")
local SaveConvert = require("src.save_convert.SaveConvert")
local Gen3Save = require("src.save_convert.Gen3Save")
local L = require("src.save_convert.Gen3Layout")
local Schema = require("src.core.game3.save_schema_firered")
local Party = require("src.core.game3.party")
local Pokemon = require("src.core.game3.pokemon")

local CART = unrle(require("tests.fixture_data.gen3_saves").images.fr_rich_game)
local realFs = love.filesystem

local function fresh(version)
  local files = {}
  love.filesystem = memfs(files)
  SaveData.resetSlotState()
  GameVersion.set(version)
  return files
end

local function exported(files, version)
  local ok, path = SaveFileIO.exportActiveSlot(version)
  check(ok == true, version .. " exportActiveSlot succeeds (" .. tostring(path) .. ")")
  return files[("exports/%s/gen1recomp-%s-%s.sav"):format(version, version, tostring(SaveData.activeSlot(version)))]
end

for _, version in ipairs({ "firered", "leafgreen" }) do
  local files = fresh(version)
  files["picked.sav"] = CART
  local ok, slotId = SaveFileIO.importToSlot("picked.sav", version)
  check(ok == true, version .. " imports the cart (" .. tostring(slotId) .. ")")
  local bytes = exported(files, version)
  check(type(bytes) == "string" and #bytes == L.FLASH_SIZE, version .. " cart slot exports a 128K .sav")
  local a, b = assert(Gen3Save.readBlocks(CART)), bytes and Gen3Save.readBlocks(bytes)
  check(b and b.counter == a.counter + 1, version .. " export is the cart's next save")
  local same = b and b.storage == a.storage and b.sb1:sub(0x15) == a.sb1:sub(0x15) and b.sb1:sub(1, 0xC) == a.sb1:sub(1, 0xC)
  check(same, version .. " the cart template's bytes survive outside the continue warp")
  local c = bytes and Gen3Save.decode(bytes)
  check(c and c.specialSaveWarpFlags == L.CONTINUE_GAME_WARP, version .. " export continues through the continue-game warp")
end

do
  local files = fresh(GAME)
  local s = Schema.newGame({ version = GAME, name = "PORT", rivalName = "RIVAL", rngSeed = 2444 })
  Party.giveMon(s, 4, 5)
  Party.giveMon(s, 277, 7, "TREE")
  s.party[1].status, s.party[1].hp = "PAR", 7
  s.map, s.x, s.y = "FR_PALLET_TOWN", 12, 16
  s.money = 4321
  local Mail = require("src.core.game3.mail")
  local mailId = Mail.giveMailToMon(s, s.party[2], 121)
  Mail.slot(s, mailId).words[1] = 1234
  s.dex.nationalUnlocked = true
  local slot = SaveData.createSlot(GAME)
  check(SaveData.writeSlot(GAME, slot, Schema.toSaveTable(s)) == true, "port-born slot written")
  SaveData.setActiveSlot(GAME, slot)
  local bytes = exported(files, GAME)
  local c = bytes and Gen3Save.decode(bytes)
  check(c ~= nil, "the port-born export decodes as a valid FireRed flash")
  if c then
    check(c.counter == 1 and c.frlgMarker == 1, "fresh first save with the FRLG marker")
    check(c.location.group == 3 and c.location.num == 0 and c.posX == 12 and c.posY == 16, "Pallet Town 12,16")
    check((c.mapLayoutId or 0) > 0, "map layout id from the cached map header (" .. tostring(c.mapLayoutId) .. ")")
    check(c.continueGameWarp.group == 3 and c.continueGameWarp.num == 0 and c.specialSaveWarpFlags == 1, "continue warp")
    local h = c.lastHealLocation
    check(h.group == 3 and h.num == 0 and h.x == 6 and h.y == 8, "Mom's house respawn saves as the Pallet heal location (6,8)")
    check(c.money == 4321 and c.name == "PORT" and c.rivalName == "RIVAL", "trainer data")
    check(c.trainerId == s.trainerId % 65536 and c.secretId == s.secretId % 65536, "TID/SID")
    check(#c.party == 2, "party size")
    local p1, m1 = c.party[1], s.party[1]
    check(p1.checksumOk and p1.species == 4 and p1.level == 5 and p1.hp == 7 and p1.status == L.STATUS.PAR,
      "Charmander Lv5 7 HP paralysed")
    check(p1.maxHp == m1.maxHp and p1.attack == m1.attack and p1.speed == m1.speed, "party stats are the port's")
    check(p1.nickname == Pokemon.name(4), "the unnamed starter carries its species name")
    check(p1.personality == m1.personality and p1.exp == m1.exp, "personality and exp")
    check(c.party[2].species == 277 and c.party[2].nickname == "TREE", "Treecko nickname")
    local owned = {}
    for _, i in ipairs(c.dexOwned) do owned[i + 1] = true end
    check(owned[Pokemon.national(277)] and owned[4], "dex bits use the national numbers from the cache")
    check(c.storage.boxes[1].name == "BOX1" and c.storage.boxes[1].wallpaper == 0, "default box 1 like the cart")
    check(c.party[2].mail == mailId and c.mail[mailId + 1].itemId == 121 and c.mail[mailId + 1].words[1] == 1234,
      "the port mon's letter exports at its mail index")
    check(c.party[1].mail == L.MAIL_NONE, "a mon without mail exports MAIL_NONE")
    check(c.dexNationalMagic == L.NATIONAL_DEX.magic, "the port's National Dex unlock exports the magic")
    check(c.fameChecker[1].pickState == L.FCPICKSTATE_COLORED, "Fame Checker starts with Oak like a new cart")
    check(c.registeredTexts[1] ~= "" and c.registeredTexts[1] ~= nil, "registered texts come from the ROM text (" .. tostring(c.registeredTexts[1]) .. ")")
    check(c.trainerTowerBest[1] == L.TRAINER_TOWER_MAX_TIME, "Trainer Tower has no time yet")
    local back = assert(SaveConvert.importSav(bytes, GAME, GAME))
    check(back.party[1].species == 4 and back.party[1].level == 5 and back.money == 4321, "re-import of the export")
    check(back.party[2].mail == mailId and back.mail[mailId + 1].words[1] == 1234, "re-import keeps the letter")
  end
end

do
  local files = fresh(GAME)
  files["picked.sav"] = CART
  local ok, slot = SaveFileIO.importToSlot("picked.sav", GAME)
  check(ok == true, "cart imported for the NEW GAME case")
  local cartFile = ("saves/%s/%s.cart"):format(GAME, slot)
  check(files[cartFile] ~= nil, "the import keeps the cart beside the slot")
  local s = Schema.newGame({ version = GAME, name = "NEWBIE", rivalName = "RIVAL", rngSeed = 7 })
  s.map, s.x, s.y = "FR_PALLET_TOWN", 12, 16
  check(SaveData.save(Schema.toSaveTable(s)) ~= false, "NEW GAME saves over the imported slot")
  check(SaveData.activeSlot(GAME) == slot, "the same slot is active")
  check(files[cartFile] == nil, "NEW GAME over the slot drops the old cart")
  local bytes = exported(files, GAME)
  local c = bytes and Gen3Save.decode(bytes)
  check(c and c.name == "NEWBIE" and c.counter == 1 and #c.hallOfFame == 0, "the export is a first save of the new player")

  files = fresh(GAME)
  files["picked.sav"] = CART
  ok, slot = SaveFileIO.importToSlot("picked.sav", GAME)
  local keep = SaveData.load(GAME)
  check(SaveData.save(keep) ~= false, "the imported player saves again")
  check(files[("saves/%s/%s.cart"):format(GAME, slot)] ~= nil, "the imported player keeps the cart")
end

love.filesystem = realFs
print(failed == 0 and "game3_cart_export_test: all passed" or ("game3_cart_export_test: " .. failed .. " failed"))
os.exit(failed == 0 and 0 or 1)
