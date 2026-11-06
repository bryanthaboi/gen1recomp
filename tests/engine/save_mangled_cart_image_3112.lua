package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local Gen2Save = require("src.save_convert.Gen2Save")
local GenSave = require("src.save_convert.GenSave")
local Gen3Save = require("src.save_convert.Gen3Save")
local SaveConvert = require("src.save_convert.SaveConvert")
local SaveData = require("src.core.SaveData")
local SaveSerializer = require("src.core.SaveSerializer")
local GameVersion = require("src.core.GameVersion")
local SaveFileIO = require("src.import.SaveFileIO")
local Pack = require("src.save_convert.gen3_port.imagepack")

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

local function fresh(version)
  local files = {}
  love.filesystem = memfs(files)
  SaveData.resetSlotState()
  GameVersion.set(version)
  return files
end

local function sameBytes(a, b, label)
  if a == b then return check(true, label) end
  if type(a) ~= "string" or type(b) ~= "string" then
    return check(false, label .. " -- got " .. type(a) .. " vs " .. type(b))
  end
  local at = 1
  while at <= math.min(#a, #b) and a:byte(at) == b:byte(at) do at = at + 1 end
  return check(false, ("%s -- lengths %d vs %d, first difference at offset 0x%X")
    :format(label, #a, #b, at - 1))
end

local function crlf(s) return (s:gsub("\n", "\r\n")) end

local function utf8Replace(s)
  local out, i, n = {}, 1, #s
  local function cont(at) local b = s:byte(at) return b and b >= 0x80 and b <= 0xBF end
  while i <= n do
    local b = s:byte(i)
    local need = b < 0x80 and 0 or (b >= 0xC2 and b <= 0xDF) and 1
      or (b >= 0xE0 and b <= 0xEF) and 2 or (b >= 0xF0 and b <= 0xF4) and 3 or -1
    local ok = need >= 0
    for k = 1, math.max(need, 0) do ok = ok and cont(i + k) end
    if ok then
      out[#out + 1] = s:sub(i, i + need)
      i = i + need + 1
    else
      out[#out + 1] = "\239\191\189"
      i = i + 1
    end
  end
  return table.concat(out)
end

local function dropped(text)
  return { open = function() return true end, read = function() return text end,
    getSize = function() return #text end, close = function() end }
end

local MANGLES = { { "UTF-8 replacement", utf8Replace } }

local function exported(files, version, slotId)
  return files[("exports/%s/gen1recomp-%s-%s.sav"):format(version, version, tostring(slotId))]
end

local function gen2Fixture(version)
  return require("tests.fixtures.save.gen2_sprite_metadata")({
    pokemon = { CHIKORITA = { index = 152, dex = 152 } }, moves = {}, items = {},
    maps = { PLAYERS_HOUSE_2F = {
      group = 24, map = 7, objectEventsAddr = 0x5CF0,
      width = 4, height = 3,
      blocks = { 4, 1, 3, 2, 5, 6, 5, 5, 5, 5, 7, 5 },
      objects = {
        { spriteId = 240, x = 4, y = 2, movement = 1, radius = { x = 0, y = 0 },
          hours = { -1, -1 }, palette = 0, type = 0, sight = 0,
          script = 0x5C5A, eventFlag = 1857 },
        { spriteId = 241, x = 4, y = 4, movement = 1, radius = { x = 0, y = 0 },
          hours = { -1, -1 }, palette = 0, type = 0, sight = 0,
          script = 0x5C54, eventFlag = 1858 },
      },
    } },
  }, version)
end

local function gen2Save()
  return {
    generation = 2,
    player = { name = "BRYAN", id = 0x0A0A, money = 3000, gender = "male" },
    rival = { name = "SILVER" }, mom = { name = "MOM" },
    position = { map = "PLAYERS_HOUSE_2F", x = 3, y = 3 },
    party = {}, boxes = {}, boxNames = {}, currentBox = 1,
  }
end

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local L = Gen2Save.layoutFor(version)
  local data = gen2Fixture(version)
  local image = assert(Gen2Save.encode(gen2Save(), version, nil, data))
  check(image:find("\n", 1, true) ~= nil, version .. ": the cart image carries a 0x0A byte")

  local cleanFiles = fresh(version)
  SaveConvert.setGen2DataStub(data)
  local ok, slotId = SaveFileIO.importToSlot(image, version, true)
  eq(ok, true, version .. ": the cart imports -- " .. tostring(slotId))
  local source = SaveData.readSlotSource(version, slotId) or ""
  local back = SaveSerializer.decode(source)
  sameBytes(back and back.rawImport, image, version .. ": the slot keeps the cart image")
  local cleanOk, _, cleanNote = SaveFileIO.exportActiveSlot(version)
  eq(cleanOk, true, version .. ": the untouched slot exports")
  local cleanOut = exported(cleanFiles, version, slotId)

  do
    local mangled = crlf(source)
    check(mangled ~= source, version .. " CRLF: the slot file really changed")
    local readBack = SaveSerializer.decode(mangled)
    sameBytes(readBack and readBack.rawImport, image,
      version .. " CRLF: the slot reads back the original cart image")
    local f2 = fresh(version)
    SaveConvert.setGen2DataStub(data)
    local iok, iid, info = SaveFileIO.importToSlot(dropped(mangled), version)
    eq(iok, true, version .. " CRLF: the .lua imports -- " .. tostring(iid))
    eq(info, nil, version .. " CRLF: with no damaged-image note")
    local stored = SaveSerializer.decode(SaveData.readSlotSource(version, iid) or "")
    sameBytes(stored and stored.rawImport, image, version .. " CRLF: the cart image is kept intact")
    local eok, eres, enote = SaveFileIO.exportActiveSlot(version)
    eq(eok, true, version .. " CRLF: the cartridge export succeeds -- " .. tostring(eres))
    check(enote == cleanNote and not tostring(enote):find("damaged", 1, true),
      version .. " CRLF: with no rebuild warning -- " .. tostring(enote))
    sameBytes(exported(f2, version, iid), cleanOut,
      version .. " CRLF: and writes the same cartridge as the untouched slot")
  end

  for _, m in ipairs(MANGLES) do
    local mangled = m[2](source)
    check(mangled ~= source, version .. " " .. m[1] .. ": the slot file really changed")
    local bad = SaveSerializer.decode(mangled)
    check(bad and type(bad.rawImport) == "string" and Gen2Save.liveImage(bad.rawImport, L) == nil,
      version .. " " .. m[1] .. ": the mangled slot still parses but its cart image no longer verifies")

    local f2 = fresh(version)
    SaveConvert.setGen2DataStub(data)
    local iok, iid, info = SaveFileIO.importToSlot(dropped(mangled), version)
    eq(iok, true, version .. " " .. m[1] .. ": the .lua imports -- " .. tostring(iid))
    eq(info and info.note, SaveFileIO.DAMAGED_CART_NOTE,
      version .. " " .. m[1] .. ": the import says the cart image was left out")
    local stored = SaveSerializer.decode(SaveData.readSlotSource(version, iid) or "")
    check(stored ~= nil and stored.rawImport == nil, version .. " " .. m[1] .. ": the damaged image is not stored")
    eq(stored and stored.player and stored.player.name, "BRYAN",
      version .. " " .. m[1] .. ": the playthrough itself is kept")
    local eok, eres = SaveFileIO.exportActiveSlot(version)
    eq(eok, true, version .. " " .. m[1] .. ": the cartridge export succeeds -- " .. tostring(eres))
    local out = exported(f2, version, iid)
    eq(out and Gen2Save.checksumValid(out, L), true, version .. " " .. m[1] .. ": and verifies")

    local direct, note = Gen2Save.encode(bad, version, nil, data)
    check(direct ~= nil, version .. " " .. m[1] .. ": encode over a damaged image builds a save -- " .. tostring(note))
    eq(note, Gen2Save.MSG.rebuilt, version .. " " .. m[1] .. ": and says it was rebuilt")
    local plain = {}
    for k, v in pairs(bad) do plain[k] = v end
    plain.rawImport = nil
    sameBytes(direct, (Gen2Save.encode(plain, version, nil, data)),
      version .. " " .. m[1] .. ": the rebuild is the no-template export")
    local viaConvert, convertNote = SaveConvert.exportSav(bad, version)
    check(viaConvert ~= nil, version .. " " .. m[1] .. ": SaveConvert exports it -- " .. tostring(convertNote))
    check(type(convertNote) == "string" and convertNote:find("was damaged", 1, true) ~= nil,
      version .. " " .. m[1] .. ": and carries the rebuild warning -- " .. tostring(convertNote))
  end
end

do
  local Fixtures = require("tests.fixtures.save.gen3_build")
  local K = require("tests.save_compat._codec")
  local cases = {}
  for _, c in ipairs(Fixtures.cases()) do cases[c.id] = c end
  for _, version in ipairs({ "firered", "emerald" }) do
    local c = cases["g3." .. version .. ".basic"]
    fresh(version)
    local ok, slotId = SaveFileIO.importToSlot(dropped(c.bytes), version)
    eq(ok, true, version .. ": the cart imports -- " .. tostring(slotId))
    local slot = SaveSerializer.decode(SaveData.readSlotSource(version, slotId) or "")
    check(slot and slot.modData and Gen3Save.forVersion(version).decode(Pack.unpack(slot.modData.cartImage)) ~= nil,
      version .. ": the slot keeps a verifying cart image")
      for _, badImage in ipairs({ "PKCI1:131072:AAAA", Pack.pack("broken image") }) do
      slot.modData.cartImage = badImage
      fresh(version)
      local iok, iid, info = SaveFileIO.importToSlot(dropped(SaveSerializer.encode(slot)), version)
      eq(iok, true, version .. ": the .lua imports -- " .. tostring(iid))
      eq(info and info.note, SaveFileIO.DAMAGED_CART_NOTE, version .. ": the import says the image was left out")
      local stored = SaveSerializer.decode(SaveData.readSlotSource(version, iid) or "")
      check(stored ~= nil and stored.modData ~= nil and stored.modData.cartImage == nil, version .. ": the damaged image is not stored")

      local save = assert(K.import(3, version, c.bytes))
      save.modData.cartImage = badImage
      local out, note = K.export(3, version, save, nil)
      check(out ~= nil, version .. ": a damaged embedded image still exports -- " .. tostring(note))
      check(type(note) == "string" and note:find(Gen3Save.forVersion(version).MSG.damagedTemplate, 1, true) ~= nil,
        version .. ": and says it was rebuilt -- " .. tostring(note))
      local bare = assert(K.import(3, version, c.bytes))
      bare.modData.cartImage = nil
      sameBytes(out, (K.export(3, version, bare, nil)), version .. ": the rebuild is the no-template export")
    end
  end
end

for _, version in ipairs({ "red", "yellow" }) do
  local K = require("tests.save_compat._codec")
  if not K.gen1Available({ version }) then
    print("[skip] " .. version .. " half needs data/generated/ for the Gen 1 save codec")
  else
    local data = K.gen1Data(version)
    local Pokemon = require("src.pokemon.Pokemon")
    local save = SaveData.newGame({})
    save.version = version
    save.player.name = "ASH"
    save.player.id = 0x0A0A
    save.player.map, save.player.x, save.player.y = "PALLET_TOWN", 5, 6
    save.party = { Pokemon.new(data, "CHARMANDER", 8) }
    local cart = assert(SaveConvert.exportSav(save, version))
    check(cart:find("\n", 1, true) ~= nil, version .. ": the cart image carries a 0x0A byte")

    fresh(version)
    local ok, slotId = SaveFileIO.importToSlot(dropped(cart), version)
    eq(ok, true, version .. ": the cart imports -- " .. tostring(slotId))
    local source = SaveData.readSlotSource(version, slotId) or ""
    local back = SaveSerializer.decode(source)
    sameBytes(back and back.rawImport, cart, version .. ": the slot keeps the cart image")

    do
      local mangled = crlf(source)
      local readBack = SaveSerializer.decode(mangled)
      sameBytes(readBack and readBack.rawImport, cart,
        version .. " CRLF: the slot reads back the original cart image")
      local files = fresh(version)
      local iok, iid, info = SaveFileIO.importToSlot(dropped(mangled), version)
      eq(iok, true, version .. " CRLF: the .lua imports -- " .. tostring(iid))
      eq(info, nil, version .. " CRLF: with no damaged-image note")
      local stored = SaveSerializer.decode(SaveData.readSlotSource(version, iid) or "")
      sameBytes(stored and stored.rawImport, cart, version .. " CRLF: the cart image is kept intact")
      local eok, eres, enote = SaveFileIO.exportActiveSlot(version)
      eq(eok, true, version .. " CRLF: the cartridge export succeeds -- " .. tostring(eres))
      check(not tostring(enote):find("rebuilt", 1, true),
        version .. " CRLF: with no rebuild warning -- " .. tostring(enote))
      local out = exported(files, version, iid)
      eq(out and GenSave.mainChecksumValid(out), true, version .. " CRLF: and verifies")
    end

    for _, m in ipairs(MANGLES) do
      local mangled = m[2](source)
      local bad = SaveSerializer.decode(mangled)
      check(bad and type(bad.rawImport) == "string" and GenSave.mainChecksumValid(bad.rawImport) ~= true,
        version .. " " .. m[1] .. ": the mangled slot still parses but its cart image no longer verifies")
      local files = fresh(version)
      local iok, iid, info = SaveFileIO.importToSlot(dropped(mangled), version)
      eq(iok, true, version .. " " .. m[1] .. ": the .lua imports -- " .. tostring(iid))
      eq(info and info.note, SaveFileIO.DAMAGED_CART_NOTE,
        version .. " " .. m[1] .. ": the import says the image was left out")
      local stored = SaveSerializer.decode(SaveData.readSlotSource(version, iid) or "")
      check(stored ~= nil and stored.rawImport == nil, version .. " " .. m[1] .. ": the damaged image is not stored")
      local eok, eres = SaveFileIO.exportActiveSlot(version)
      eq(eok, true, version .. " " .. m[1] .. ": the cartridge export succeeds -- " .. tostring(eres))
      local out = exported(files, version, iid)
      eq(out and GenSave.mainChecksumValid(out), true, version .. " " .. m[1] .. ": and verifies")
    end

    local damaged = cart:sub(1, 0x2600) .. string.char((cart:byte(0x2601) + 1) % 256) .. cart:sub(0x2602)
    eq(GenSave.mainChecksumValid(damaged), false, version .. ": a flipped main-data byte fails the checksum")
    local withBad = {}
    for k, v in pairs(back) do withBad[k] = v end
    withBad.rawImport = damaged
    local direct, note = GenSave.encode(withBad, data)
    eq(note, GenSave.MSG_REBUILT, version .. ": encode over a damaged image says it was rebuilt")
    withBad.rawImport = nil
    sameBytes(direct, (GenSave.encode(withBad, data)), version .. ": the rebuild is the no-template export")
  end
end

love.filesystem = realFS
SaveData.resetSlotState()
GameVersion.set("red")

T.finish("save mangled cart image")
