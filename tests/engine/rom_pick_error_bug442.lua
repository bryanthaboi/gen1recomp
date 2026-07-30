-- #442: an Android pick that cannot be used must say so.  GameActivity writes
-- pick_error.flag when it has no readable stream for the chosen URI, and a pick
-- it did copy but the importer refuses (wrong size, unknown SHA-1) has to reach
-- startData's messages instead of leaving the launcher silent with the file
-- stuck on disk.  Covers the routing, the removal, and the #167 carve-out for a
-- cart that is merely already imported.
--   luajit tests/engine/rom_pick_error_bug442.lua

package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

local GameVersion = require("src.core.GameVersion")
local RomImporter = require("src.import.RomImporter")

local MiB = 1024 * 1024
local redData = string.rep("R", MiB)
local hackData = string.rep("X", MiB)          -- 1 MiB, matches no known cart
local shortData = string.rep("R", MiB / 2)     -- trimmed dump
local UNKNOWN_SHA1 = "0000000000000000000000000000000000000000"

-- Map the fake blobs onto real version ids by first byte, so no crypto library
-- is needed headless (same trick as tests/rom_importer_android_pick_test.lua).
love.data = { hash = function(_, data) return { tag = data:sub(1, 1) } end }
love.data.encode = function(_, _, digest)
  if type(digest) == "table" and digest.tag == "R" then
    return GameVersion.info("red").sha1
  end
  return UNKNOWN_SHA1
end
love.filesystem.getSaveDirectory = function() return "/sdcard/pokeport/save" end

local pickCalls = {}
love.system = {
  getOS = function() return "Android" end,
  pickFile = function(kind)
    pickCalls[#pickCalls + 1] = kind or "rom"
    return true
  end,
}

-- Pre-fix these paths leave the launcher untouched, so read the message
-- defensively: every check should report, not blow up on the first nil.
local function detail(ri) return tostring(ri.detail or "") end

local function clearSaveDir()
  for _, name in ipairs(love.filesystem.getDirectoryItems("")) do
    love.filesystem.remove(name)
  end
end

-- Only the fields the Android focus / choose / chooseMod paths read.  _installMod
-- is stubbed per case because the outcome it reports is what consumePick keys on.
local function freshImporter(opts)
  opts = opts or {}
  pickCalls = {}
  return setmetatable({
    android = true,
    launcher = true,
    workState = nil,
    tab = opts.tab or "red",
    ready = { red = opts.redReady and true or false, blue = false, yellow = false },
    saveNotice = {},
    modNotice = nil,
    notice = nil,
    slotScroll = {},
    activeSlot = {},
    _installMod = function(self, name)
      self._installed = name
      self.modNotice = { ok = opts.modOk and true or false, text = "install result" }
    end,
    _importSave = function(self, version, name)
      self._imported = { version = version, name = name }
      self.saveNotice[version] = { ok = false, text = "import result" }
    end,
  }, RomImporter)
end

-- ------- pick_error.flag: GameActivity could not read the chosen URI at all

do
  clearSaveDir()
  love.filesystem.write("pick_error.flag", "picked_rom.gb")
  local ri = freshImporter({})
  ri:focus(true)
  eq(ri.workState, "error", "an unreadable ROM pick lands on the error state")
  check(detail(ri):find("Could not read the picked file", 1, true),
    "the ROM notice names the unreadable pick")
  check(detail(ri):find("/sdcard/pokeport/save", 1, true),
    "the notice offers the save dir as the copy-it-yourself fallback")
  eq(love.filesystem.getInfo("pick_error.flag"), nil,
    "the flag is consumed, so refocusing does not re-report it")
end

do
  clearSaveDir()
  love.filesystem.write("pick_error.flag", "picked_mod.zip")
  local ri = freshImporter({})
  ri:focus(true)
  check(ri.modNotice ~= nil and ri.modNotice.ok == false,
    "an unreadable mod pick reports on the mods panel")
  eq(ri.workState, nil, "a failed mod pick does not error out the ROM panel")
end

do
  clearSaveDir()
  love.filesystem.write("pick_error.flag", "picked_save.sav")
  local ri = freshImporter({ redReady = true, tab = "mods" })
  ri.androidPendingVersion = "blue"
  ri:focus(true)
  check(ri.saveNotice.blue ~= nil and ri.saveNotice.blue.ok == false,
    "an unreadable save pick reports on the game it was picked for")
  eq(ri.androidPendingVersion, nil, "the pending save target is consumed with it")
end

-- ------- a pick that copied fine but the importer refuses

do
  clearSaveDir()
  love.filesystem.write("picked_rom.gb", shortData)
  local ri = freshImporter({})
  ri:focus(true)
  eq(ri.workState, "error", "a trimmed pick reports instead of staying silent")
  check(detail(ri):find("1 MiB", 1, true), "the wrong-size message names the size")
  eq(love.filesystem.getInfo("picked_rom.gb"), nil,
    "the refused pick is dropped so the next tap starts clean")
end

do
  clearSaveDir()
  love.filesystem.write("picked_rom.gb", hackData)
  local ri = freshImporter({})
  ri:focus(true)
  eq(ri.workState, "error", "a cart matching no known SHA-1 reports")
  check(detail(ri):find(UNKNOWN_SHA1, 1, true), "the message quotes the hash")
  check(detail(ri):find("[b] or [BF]", 1, true),
    "the message names the dump tags that can never verify")
  eq(love.filesystem.getInfo("picked_rom.gb"), nil, "the bad dump is dropped")
end

do
  clearSaveDir()
  love.filesystem.write("picked_rom.gb", redData)
  local ri = freshImporter({ redReady = true })
  ri:focus(true)
  eq(ri.workState, nil, "an already-imported cart is not an error (#167)")
  check(love.filesystem.getInfo("picked_rom.gb") ~= nil,
    "#167's leftover is left alone, not reported and deleted")
end

do
  clearSaveDir()
  love.filesystem.write("picked_rom.gb", redData)
  local read = love.filesystem.read
  love.filesystem.read = function(name)
    if name == "picked_rom.gb" then return nil end
    return read(name)
  end
  local ri = freshImporter({})
  ri:focus(true)
  love.filesystem.read = read
  eq(ri.workState, "error", "a pick present but unreadable from Lua reports too")
  check(detail(ri):find("could not be read", 1, true),
    "the unreadable-file message points at the picker")
end

-- Choose must explain the refused pick rather than reopening the picker over it.
do
  clearSaveDir()
  love.filesystem.write("picked_rom.gb", hackData)
  local ri = freshImporter({})
  ri:choose("blue")
  eq(#pickCalls, 0, "Choose reports the refused pick before reopening the picker")
  eq(ri.workState, "error", "Choose surfaces the same message focus does")
end

-- ------- a rejected pick must not wall off the branches under it

do
  clearSaveDir()
  love.filesystem.write("picked_mod.zip", "not a zip")
  love.filesystem.write("picked_rom.gb", shortData)
  local ri = freshImporter({})
  ri:focus(true)
  eq(ri._installed, "picked_mod.zip", "the mod branch runs first")
  eq(love.filesystem.getInfo("picked_mod.zip"), nil,
    "a rejected SAF mod pick is retired, not left to win every refocus")
  ri:focus(true)
  eq(ri.workState, "error", "the next focus reaches the ROM pick under it")
end

-- A USB copy is the player's own file: keep it, but stop retrying it this session.
do
  clearSaveDir()
  love.filesystem.write("mymod.zip", "not a zip")
  local ri = freshImporter({})
  ri:chooseMod()
  eq(ri._installed, "mymod.zip", "Import Mod picks up a USB copy")
  check(love.filesystem.getInfo("mymod.zip") ~= nil, "the player's own file stays")
  ri:chooseMod()
  eq(#pickCalls, 1, "the second tap opens the picker instead of retrying it")
  eq(pickCalls[1], "mod", "and asks for a mod archive")
end

clearSaveDir()
T.finish()
