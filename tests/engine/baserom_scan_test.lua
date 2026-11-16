package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.harness")
local check, eq = T.check, T.eq

local HASH = {
  red = "ea9bcae617fdf159b045185467ae58b2e4a48b9a",
  blue = "d7037c83e1ae5b39bde3c30787637ba1d4c48ce2",
  yellow = "cc7d03262ebfaf2f06772c1a480c7d9d5f4a38e1",
}

-- The importer hashes through love.data; answer from the first eight bytes.
local TAG_HASH = {
  ["red00000"] = HASH.red,
  ["blue0000"] = HASH.blue,
  ["yell0000"] = HASH.yellow,
}
love.data = love.data or {}
love.data.hash = function(_, data)
  return TAG_HASH[data:sub(1, 8)] or "0000000000000000000000000000000000000000"
end
love.data.encode = function(_, _, digest) return digest end

local Importer = require("src.import.RomImporter")

local MIB = 1024 * 1024

-- Only the tag matters; nothing in the scan reads a header.
local function romBytes(tag, size)
  return tag .. string.rep("\0", size - #tag)
end

local function scan(imp)
  for _ = 1, 20 do
    local state = imp.baseRomScan and imp.baseRomScan.state
    if not state or state == "done" then break end
    imp:_stepBaseRomScan()
  end
end

local function newImporter()
  local imp = Importer.new(function() end, { launcher = true })
  for version in pairs(imp.ready) do imp.ready[version] = false end
  return imp
end

-- 1. SHA-1 decides, whatever the file is called ------------------------------

love.filesystem.write("baseroms/rom-a.gb", romBytes("red00000", MIB))
love.filesystem.write("baseroms/Pokemon - Red Version (USA, Europe).gb",
  romBytes("blue0000", MIB))

local imp = newImporter()
check(imp.baseRomDiscovery, "desktop launcher enables baseroms discovery")
eq(imp.baseRomDirHint, "/tmp/pokeport-stub-save/baseroms",
  "the hint names the save-dir baseroms folder")
scan(imp)

check(imp.baseRoms.red ~= nil, "an arbitrarily named Red dump is detected")
eq(imp.baseRoms.red and imp.baseRoms.red.name, "rom-a.gb",
  "and the record keeps the file it came from")
check(imp.baseRoms.blue ~= nil, "the second dump is detected too")
eq(imp.baseRoms.blue and imp.baseRoms.blue.name,
  "Pokemon - Red Version (USA, Europe).gb",
  "a Red filename over Blue bytes is still Blue")
eq(imp.baseRomScan and imp.baseRomScan.state, "done", "the scan finished")

love.filesystem.remove("baseroms/rom-a.gb")
love.filesystem.remove("baseroms/Pokemon - Red Version (USA, Europe).gb")

-- 2. An unknown hash is not guessed at --------------------------------------

-- 1 MiB could be Red, Blue or Yellow, so size alone must not pick one.
love.filesystem.write("baseroms/rom.gb", romBytes("unk00000", MIB))

imp = newImporter()
scan(imp)

eq(next(imp.baseRoms), nil, "a file with an unrecognised hash is not assigned")
check(imp.notice ~= nil, "the launcher explains why the tab stays empty")
eq(imp.notice and imp.notice.status, "Could not identify a ROM in baseroms/.",
  "the notice names the problem")
eq(imp.notice and imp.notice.version, "red",
  "and it lands on a tab that is still missing a ROM")

-- A size match is not evidence either: startData would refuse the import.
imp = newImporter()
imp.ready.blue = true
imp.ready.yellow = true
scan(imp)

eq(next(imp.baseRoms), nil, "the last remaining cart is still not guessed at")
eq(imp.notice and imp.notice.version, "red", "and the notice still points at it")

-- The notice renders on the tab it names, not the tab that is open.
imp = newImporter()
imp.tab = "box"
scan(imp)
eq(imp.notice and imp.notice.version, "red",
  "an unidentifiable file seen from the Box tab lands on a game tab")

love.filesystem.remove("baseroms/rom.gb")

-- 3. The card says the hash is what matched ---------------------------------

love.filesystem.write("baseroms/rom-a.gb", romBytes("red00000", MIB))
love.filesystem.write("baseroms/rom-b.gb", romBytes("blue0000", MIB))

imp = newImporter()
scan(imp)

local LauncherView = require("src.import.LauncherView")
local GameVersion = require("src.core.GameVersion")
local model = LauncherView._romModel(imp, "red", GameVersion.info("red"), false, false)
eq(model and model.state, "Compatible ROM found", "the card announces the detected ROM")
eq(model and model.detail, "Found in baseroms/: rom-a.gb (SHA-1)",
  "the card names the file and the evidence")
eq(model and model.label, "Import detected ROM",
  "the button imports the detected file")

love.filesystem.remove("baseroms/rom-a.gb")
love.filesystem.remove("baseroms/rom-b.gb")

-- 4. Size gates the read ----------------------------------------------------

-- No cart is 3 MiB, so reading and hashing it would be pure waste.
love.filesystem.write("baseroms/big.gba", string.rep("\0", 3 * MIB))

local reads = 0
local realRead = love.filesystem.read
love.filesystem.read = function(...) reads = reads + 1 return realRead(...) end

imp = newImporter()
reads = 0
scan(imp)

eq(reads, 0, "a file whose size matches no cart is never read")
eq(next(imp.baseRoms), nil, "and nothing is assigned from it")

love.filesystem.read = realRead
love.filesystem.remove("baseroms/big.gba")

-- 5. A cart that is already imported is not offered again -------------------

love.filesystem.write("baseroms/rom-a.gb", romBytes("red00000", MIB))

imp = newImporter()
imp.ready.red = true
scan(imp)

eq(imp.baseRoms.red, nil, "an already imported cart is not offered again")
eq(imp.notice, nil, "and its own file raises no notice")

love.filesystem.remove("baseroms/rom-a.gb")

-- 6. The mount and the native walk see the same file once -------------------

local SaveData = require("src.core.SaveData")
local realFolders, realList, realStat =
  SaveData.gameFolders, SaveData.listNative, SaveData.statNative
SaveData.gameFolders = function() return { "/tmp/other-game" } end
SaveData.listNative = function() return { "rom-a.gb" } end
SaveData.statNative = function() return { type = "file", size = MIB } end

love.filesystem.write("baseroms/rom-a.gb", romBytes("red00000", MIB))
imp = newImporter()
scan(imp)
eq(imp.baseRomScan and #(imp.baseRomScan.entries or {}), 1,
  "a checkout mounts baseroms/, so the native copy of one name is skipped")
love.filesystem.remove("baseroms/rom-a.gb")

SaveData.gameFolders, SaveData.listNative, SaveData.statNative =
  realFolders, realList, realStat

-- 7. Desktop does not create the folder, and handhelds do not scan ----------

local created = 0
local realCreate = love.filesystem.createDirectory
love.filesystem.createDirectory = function(...)
  created = created + 1
  return realCreate(...)
end
imp = newImporter()
scan(imp)
eq(created, 0, "a desktop launch does not create an empty baseroms/")
love.filesystem.createDirectory = realCreate

local realGetenv = os.getenv
os.getenv = function(name)
  if name == "HANDHELD" then return "1" end
  return realGetenv(name)
end
imp = newImporter()
check(not imp.baseRomDiscovery, "a handheld does not scan baseroms/")
os.getenv = realGetenv

T.finish("baserom scan")
