package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local bit = require("bit")
local GenSave = require("src.save_convert.GenSave")
local SaveConvert = require("src.save_convert.SaveConvert")
local SaveData = require("src.core.SaveData")
local SaveSerializer = require("src.core.SaveSerializer")
local GameVersion = require("src.core.GameVersion")
local SaveFileIO = require("src.import.SaveFileIO")

local realFS = love.filesystem

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

local function fresh()
  local files = {}
  love.filesystem = memfs(files)
  SaveData.resetSlotState()
  GameVersion.set("red")
  return files
end

local function u16le(n) return string.char(n % 256, math.floor(n / 256) % 256) end
local function u32le(n) return u16le(n % 65536) .. u16le(math.floor(n / 65536) % 65536) end

-- src/save.c:614
local function gbaChecksum(data, size)
  local s = 0
  for i = 0, math.floor(size / 4) - 1 do
    local b1, b2, b3, b4 = data:byte(i * 4 + 1, i * 4 + 4)
    s = (s + b1 + b2 * 256 + b3 * 65536 + b4 * 16777216) % 4294967296
  end
  return (math.floor(s / 65536) + s) % 65536
end

-- src/save.c:54
local CHUNK = { 0xF24, 0xF80, 0xF80, 0xF80, 0xEE8, 0xF80, 0xF80, 0xF80,
  0xF80, 0xF80, 0xF80, 0xF80, 0xF80, 0x7D0 }

local function sector(id, counter, seed)
  local t = {}
  for i = 1, 3968 do t[i] = string.char((i * 7 + id * 13 + seed) % 256) end
  local data = table.concat(t)
  return data .. string.rep("\0", 116) .. u16le(id)
    .. u16le(gbaChecksum(data, CHUNK[id + 1])) .. u32le(0x08012025) .. u32le(counter)
end

local function gbaFlash(size, counter)
  local out = {}
  for slot = 0, 1 do
    local c = counter - (slot == counter % 2 and 0 or 1)
    local rot = c % 14
    for i = 0, 13 do out[#out + 1] = sector((i - rot) % 14, c, slot) end
  end
  local s = table.concat(out) .. string.rep("\255", 4 * 0x1000)
  if size > #s then s = s .. string.rep("\255", size - #s) end
  return s:sub(1, size)
end

local OFF = GenSave.OFFSETS
local function forgeGen1Checksum(bytes)
  local sum = 0
  for i = OFF.checksumStart, OFF.checksumEnd - 1 do
    sum = bit.band(sum + bytes:byte(i + 1), 0xFF)
  end
  local want = bit.band(bit.bnot(sum), 0xFF)
  return bytes:sub(1, OFF.mainChecksum) .. string.char(want)
    .. bytes:sub(OFF.mainChecksum + 2)
end

local function writeTmp(files, name, bytes)
  files[name] = bytes
  return name
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

local Gen3Save = require("src.save_convert.Gen3Save")
local FR_CART = unrle(require("tests.fixture_data.gen3_saves").images.fr_rich_game)

for _, version in ipairs({ "firered", "leafgreen" }) do
  for _, shape in ipairs({
    { "128K flash", FR_CART },
    { "128K + RTC trailer", FR_CART .. string.rep("\0", 16) },
    { "64K flash", FR_CART:sub(1, 65536) },
  }) do
    local files = fresh()
    local path = writeTmp(files, "picked_save.sav", shape[2])
    local ok, slotId, info = SaveFileIO.importToSlot(path, version)
    eq(ok, true, version .. " " .. shape[1] .. " cart save imports (" .. tostring(slotId) .. ")")
    check(info == nil, version .. " " .. shape[1] .. " never asks to confirm")
    eq(#SaveData.listSlots(version), 1, version .. " " .. shape[1] .. " creates one slot")
    eq(SaveData.activeSlot(version), slotId, version .. " " .. shape[1] .. " is made active")
    eq(files[("saves/%s/%s.cart"):format(version, tostring(slotId))], shape[2],
      version .. " " .. shape[1] .. " keeps the cart image beside the slot")
    local back = SaveSerializer.decode(SaveData.readSlotSource(version, slotId) or "")
    eq(back and back.version, version, version .. " " .. shape[1] .. " slot is tagged " .. version)
    eq(back and back.money, 123456, version .. " " .. shape[1] .. " money")
    eq(back and back.party and #back.party, 4, version .. " " .. shape[1] .. " party")
    eq(back and back.map, "FR_PLAYERS_HOUSE_2F", version .. " " .. shape[1] .. " map")
    local exOk, exRes = SaveFileIO.exportActiveSlot(version)
    if exOk then
      local out = files[("exports/%s/gen1recomp-%s-%s.sav"):format(version, version, tostring(slotId))]
      local c = out and Gen3Save.decode(out)
      eq(c and c.money, 123456, version .. " " .. shape[1] .. " cart export decodes as a FireRed/LeafGreen save")
    else
      eq(exRes, Gen3Save.MSG.noData, version .. " " .. shape[1] .. " cart export without game data says so")
    end
  end
  for _, shape in ipairs({
    { "32K", FR_CART:sub(1, 32768), Gen3Save.MSG.size:format(32768) },
    { "synthetic flash", gbaFlash(131072, 7), Gen3Save.MSG.notFrlg },
    { "forged Gen 1 checksum", forgeGen1Checksum(gbaFlash(131072, 7)), Gen3Save.MSG.notFrlg },
  }) do
    local files = fresh()
    local path = writeTmp(files, "picked_save.sav", shape[2])
    local ok, msg, info = SaveFileIO.importToSlot(path, version, true)
    eq(ok, false, version .. " " .. shape[1] .. " is refused")
    eq(msg, shape[3], version .. " " .. shape[1] .. " gets its own sentence")
    check(info == nil, version .. " " .. shape[1] .. " never asks to import anyway")
    check(not tostring(msg):find("checksum"),
      version .. " " .. shape[1] .. " is not described as a checksum failure")
    eq(#SaveData.listSlots(version), 0, version .. " " .. shape[1] .. " creates no slot")
  end
end

for _, version in ipairs({ "firered", "leafgreen" }) do
  local files = fresh()
  GameVersion.set(version)
  local ok, slotId = SaveFileIO.importToSlot(writeTmp(files, "picked_save.sav", FR_CART), version)
  eq(ok, true, version .. " cart imported for the stale-template check")
  local cartFile = ("saves/%s/%s.cart"):format(version, tostring(slotId))
  local same = SaveSerializer.decode(SaveData.readSlotSource(version, slotId))
  check(SaveData.save(same) ~= false, version .. " the imported player saves")
  check(files[cartFile] ~= nil, version .. " the imported player's cart stays")
  local newbie = { engine = "game3", version = version, generation = 3, name = "NEWBIE", trainerId = 1, secretId = 2,
    party = {}, map = "FR_PLAYERS_HOUSE_2F", x = 3, y = 6 }
  check(SaveData.save(newbie) ~= false, version .. " NEW GAME saves over the imported slot")
  eq(SaveData.activeSlot(version), slotId, version .. " the NEW GAME wrote the imported slot")
  eq(files[cartFile], nil, version .. " NEW GAME over the slot drops the old player's cart")
  files[cartFile] = FR_CART
  eq(SaveFileIO.dropStaleCart(version, slotId, newbie), true, version .. " dropStaleCart removes another player's cart")
  files[cartFile] = FR_CART
  eq(SaveFileIO.dropStaleCart(version, slotId, same), false, version .. " dropStaleCart keeps the player's own cart")
end

do
  local forged = forgeGen1Checksum(gbaFlash(131072, 7))
  eq(GenSave.mainChecksumValid(forged), true, "the forged flash passes the raw Gen 1 rule")
  eq(SaveConvert.mainChecksumValid(forged, "firered"), nil,
    "SaveConvert never runs the Gen 1 rule for FireRed")
  eq(SaveConvert.mainChecksumValid(forged, "red"), nil,
    "SaveConvert never runs the Gen 1 rule over a GBA flash image")
  eq(SaveConvert.mainChecksumValid(forged), nil,
    "SaveConvert never runs the Gen 1 rule over a GBA flash image (no game)")
  eq(SaveConvert.importSupported("firered"), true, "FireRed cart import is supported")
  eq(SaveConvert.importSupported("leafgreen"), true, "LeafGreen cart import is supported")
  eq(SaveConvert.importSupported("red"), true, "Red cart import stays supported")
  eq(SaveConvert.importSupported("crystal"), true, "Crystal cart import stays supported")
  local sav, err = SaveConvert.importSav(FR_CART, "firered", "firered")
  check(sav ~= nil, "importSav converts a FireRed cart (" .. tostring(err) .. ")")
  local lg = SaveConvert.importSav(FR_CART, "leafgreen", "leafgreen")
  check(lg ~= nil, "the same cart converts for LeafGreen")
end

for _, target in ipairs({ "red", "yellow", "gold", "crystal" }) do
  local files = fresh()
  local path = writeTmp(files, "picked_save.sav", forgeGen1Checksum(gbaFlash(131072, 7)))
  local ok, msg, info = SaveFileIO.importToSlot(path, target, true)
  eq(ok, false, "a GBA flash image is refused for " .. target)
  eq(msg, SaveConvert.GEN3_FLASH_MISMATCH, "a GBA flash image is named as one for " .. target)
  check(info == nil, "a GBA flash image never reaches the oversize confirm for " .. target)
  eq(#SaveData.listSlots(target), 0, "a GBA flash image creates no " .. target .. " slot")
end

local function sampleSave(version)
  local gen = GameVersion.generation(version)
  local save = {
    version = version,
    party = { { species = "BULBASAUR", level = 7, nickname = "BULBY" } },
    money = 1234,
    name = "ASH",
    meta = { format = 5, mods = {}, playthroughId = "pt-" .. version },
  }
  if gen >= 2 then save.generation = gen end
  if gen == 3 then save.engine = "game3" end
  return save
end

for _, version in ipairs(GameVersion.ORDER) do
  local files = fresh()
  local original = sampleSave(version)
  local src = SaveData.createSlot(version)
  eq(SaveData.writeSlot(version, src, original), true, version .. " source slot written")
  local ok, exported = SaveFileIO.exportLuaSlot(version, src)
  eq(ok, true, version .. " exportLuaSlot succeeds")
  local rel = tostring(exported):match("(exports/.+)$")
  check(rel ~= nil and files[rel] ~= nil, version .. " export lands in exports/")
  local imported, slotId = SaveFileIO.importToSlot(rel, version)
  eq(imported, true, version .. " the .lua export imports back (" .. tostring(slotId) .. ")")
  check(slotId ~= nil and slotId ~= src, version .. " the import is a new slot")
  eq(SaveData.activeSlot(version), slotId, version .. " the imported slot is made active")
  local back = SaveSerializer.decode(SaveData.readSlotSource(version, slotId) or "")
  eq(back and SaveSerializer.encode(back), SaveSerializer.encode(original),
    version .. " the imported slot matches the exported save")
end

local mismatches = {
  { "leafgreen", "firered" }, { "firered", "leafgreen" }, { "red", "firered" },
  { "firered", "red" }, { "gold", "crystal" }, { "crystal", "gold" },
  { "red", "blue" }, { "yellow", "gold" },
}
for _, pair in ipairs(mismatches) do
  local from, to = pair[1], pair[2]
  local files = fresh()
  local path = writeTmp(files, "picked_save.sav", SaveSerializer.encode(sampleSave(from)))
  local ok, msg = SaveFileIO.importToSlot(path, to)
  eq(ok, false, from .. " .lua save is refused for " .. to)
  eq(msg, ("That save is for %s, not %s."):format(GameVersion.info(from).displayName,
    GameVersion.info(to).displayName), from .. " -> " .. to .. " names both games")
  eq(#SaveData.listSlots(to), 0, from .. " -> " .. to .. " creates no slot")
end

do
  local files = fresh()
  local forged = sampleSave("firered")
  forged.engine = "gen1"
  local path = writeTmp(files, "picked_save.sav", SaveSerializer.encode(forged))
  local ok = SaveFileIO.importToSlot(path, "firered")
  eq(ok, false, "an engine tag that disagrees with the game is refused")
end

do
  local files = fresh()
  _G.__pwned = nil
  for label, body in pairs({
    call = "return { version = \"firered\", generation = 3, engine = \"game3\","
      .. " party = {}, x = (function() __pwned = true end)() }",
    expr = "return { version = \"red\", party = {}, money = 1 + 1 }",
    trailing = "return { version = \"red\", party = {} } __pwned = true",
    notsave = "return { version = \"red\" }",
    scalar = "return 42",
  }) do
    local path = writeTmp(files, "picked_save.sav", body)
    local ok, msg = SaveFileIO.importToSlot(path, label == "call" and "firered" or "red")
    eq(ok, false, "hostile .lua (" .. label .. ") is refused")
    check(type(msg) == "string" and not msg:find("checksum"),
      "hostile .lua (" .. label .. ") is not described as a checksum failure")
  end
  eq(_G.__pwned, nil, "no imported text was executed")
  eq(#SaveData.listSlots("red"), 0, "hostile .lua creates no red slot")
  eq(#SaveData.listSlots("firered"), 0, "hostile .lua creates no firered slot")
end

local function saveWithJunk(junk)
  return "return { version = \"red\", party = {}, junk = " .. junk .. " }"
end

do
  local files = fresh()
  local groups = {}
  for g = 1, 300 do
    local row = {}
    for i = 1, 1000 do row[i] = "[" .. i .. "]={}" end
    groups[g] = "[" .. g .. "]={" .. table.concat(row, ",") .. "}"
  end
  local body = saveWithJunk("{" .. table.concat(groups, ",") .. "}")
  check(#body < 16 * 1024 * 1024, "the empty-table flood fits under the byte cap")
  local path = writeTmp(files, "picked_save.sav", body)
  local started = os.clock()
  local ok, msg = SaveFileIO.importToSlot(path, "red")
  eq(ok, false, "a .lua of 300k empty tables is refused")
  check(type(msg) == "string" and msg:find("too many values") ~= nil,
    "the refusal names the value cap (" .. tostring(msg) .. ")")
  check(os.clock() - started < 2, "the flood is refused quickly")
  eq(#SaveData.listSlots("red"), 0, "the flood creates no slot")
end

do
  local files = fresh()
  local row = {}
  for i = 1, 20000 do row[i] = "[" .. i .. "]=0" end
  local path = writeTmp(files, "picked_save.sav", saveWithJunk("{" .. table.concat(row, ",") .. "}"))
  local ok, msg = SaveFileIO.importToSlot(path, "red")
  eq(ok, false, "a .lua with a 20000-entry table is refused")
  check(type(msg) == "string" and msg:find("too many table entries") ~= nil,
    "the refusal names the table-entry cap (" .. tostring(msg) .. ")")
end

do
  local files = fresh()
  local big = sampleSave("firered")
  big.boxes = {}
  for b = 1, 14 do
    local box = {}
    for s = 1, 30 do
      box[s] = { species = "PIKACHU", level = 50, moves = { "THUNDERBOLT", "SURF", "FLY", "DIG" },
        ivs = { 1, 2, 3, 4, 5, 6 }, evs = { 1, 2, 3, 4, 5, 6 } }
    end
    big.boxes[b] = box
  end
  big.flags = {}
  for i = 1, 4000 do big.flags["F" .. i] = true end
  local path = writeTmp(files, "picked_save.sav", SaveSerializer.encode(big))
  local ok, slotId = SaveFileIO.importToSlot(path, "firered")
  eq(ok, true, "a full-boxes save still imports under the caps (" .. tostring(slotId) .. ")")
end

love.filesystem = realFS

do
  local RomImporter = require("src.import.RomImporter")
  local picks = {}
  love.system = {
    getOS = function() return "Android" end,
    pickFile = function(kind) picks[#picks + 1] = kind or "rom" return true end,
  }
  love.filesystem.getSaveDirectory = function() return "/sdcard/pokeport/save" end
  for _, name in ipairs(love.filesystem.getDirectoryItems("")) do
    love.filesystem.remove(name)
  end
  love.filesystem.write("pending_export.sav", SaveSerializer.encode(sampleSave("firered")))
  local imports = {}
  local ri = setmetatable({
    android = true, tab = "firered", ready = { firered = true }, saveNotice = {},
    _importSave = function(self, version, name)
      imports[#imports + 1] = name
      self.saveNotice[version] = { ok = true, text = "imported" }
    end,
  }, RomImporter)
  ri:chooseSaveImport("firered")
  eq(#imports, 0, "a staged pending_export.sav is not imported by Import save")
  eq(picks[1], "sav", "Import save opens the picker instead")

  love.filesystem.write("pokemon_red.sav", "usb copy")
  imports, picks = {}, {}
  ri:chooseSaveImport("firered")
  eq(imports[1], "pokemon_red.sav", "a real USB .sav beside it is still picked up")
  for _, name in ipairs(love.filesystem.getDirectoryItems("")) do
    love.filesystem.remove(name)
  end

  local function droppedFile(name, body)
    return {
      getFilename = function() return name end,
      open = function() return true end,
      read = function() return body end,
      getSize = function() return #body end,
      close = function() end,
    }
  end
  for _, tab in ipairs({ "mods", "skins" }) do
    local routed, romData = {}, {}
    local drop = setmetatable({
      tab = tab, ready = {}, saveNotice = {},
      _importSave = function(_, version) routed[#routed + 1] = version end,
      startData = function(_, data, name) romData[#romData + 1] = name end,
    }, RomImporter)
    drop:filedropped(droppedFile("/Users/x/mods/cool/main.lua", "return { id = \"cool\" }"))
    eq(#routed, 0, "a .lua dropped on the " .. tab .. " tab is not routed to save import")
    eq(drop.tab, tab, "the " .. tab .. " tab stays active")
    eq(romData[1], "/Users/x/mods/cool/main.lua", "it keeps the pre-existing non-save drop path")
  end
  do
    local routed = {}
    local drop = setmetatable({
      tab = "firered", ready = {}, saveNotice = {},
      _importSave = function(_, version) routed[#routed + 1] = version end,
      startData = function() end,
    }, RomImporter)
    drop:filedropped(droppedFile("save.lua", SaveSerializer.encode(sampleSave("firered"))))
    eq(routed[1], "firered", "a .lua dropped on a game tab still goes to save import")
  end
end

T.finish("save_lua_import")
