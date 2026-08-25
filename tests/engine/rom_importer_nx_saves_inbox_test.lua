-- NX saves .sav inbox: ensure imports/saves/, MTP hint, AppleDouble/retain/
-- retire-on-success + hash dedupe (NXSAV + RES harden).
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("rom importer NX saves inbox")
local eq = S.eq
local check = S.check

local RomImporter = require("src.import.RomImporter")

love.data = love.data or {}
love.system = love.system or {}
love.filesystem = love.filesystem or {}

local saved = {
  hash = love.data.hash,
  encode = love.data.encode,
  getOS = love.system.getOS,
  getSaveDirectory = love.filesystem.getSaveDirectory,
  createDirectory = love.filesystem.createDirectory,
  remove = love.filesystem.remove,
}

-- Deterministic fake sha1 so content-hash dedupe is testable headless.
love.data.hash = function(_, data)
  return data
end
love.data.encode = function(_, _, digest)
  local s = type(digest) == "string" and digest or tostring(digest)
  local hex = {}
  for i = 1, #s do
    hex[#hex + 1] = string.format("%02x", s:byte(i))
  end
  local h = table.concat(hex)
  if #h < 40 then h = h .. string.rep("0", 40 - #h) end
  return h:sub(1, 40)
end

love.system.getOS = function() return "NX" end
love.filesystem.getSaveDirectory = function()
  return "sdmc:/switch/gen1recomp/pokemon-love2d"
end

local createdDirs = {}
love.filesystem.createDirectory = function(name)
  createdDirs[name] = true
  return true
end

local removed = {}
love.filesystem.remove = function(name)
  removed[name] = true
  return saved.remove(name)
end

package.loaded["src.core.Platform"] = nil
package.loaded["src.import.RomImporter"] = nil
RomImporter = require("src.import.RomImporter")
local GameVersion = require("src.core.GameVersion")

local function clearSavesInbox()
  for _, ver in ipairs(GameVersion.ORDER) do
    local dir = "imports/saves/" .. ver
    for _, name in ipairs(love.filesystem.getDirectoryItems(dir) or {}) do
      love.filesystem.remove(dir .. "/" .. name)
    end
    love.filesystem.remove(dir .. "/.imported-sha1")
  end
  for _, name in ipairs(love.filesystem.getDirectoryItems("imports/saves") or {}) do
    love.filesystem.remove("imports/saves/" .. name)
  end
  for _, name in ipairs(love.filesystem.getDirectoryItems("imports/mods") or {}) do
    love.filesystem.remove("imports/mods/" .. name)
  end
  for _, name in ipairs(love.filesystem.getDirectoryItems("imports") or {}) do
    love.filesystem.remove("imports/" .. name)
  end
end

local function freshImporter()
  clearSavesInbox()
  createdDirs = {}
  removed = {}
  package.loaded["src.import.RomImporter"] = nil
  RomImporter = require("src.import.RomImporter")
  return setmetatable({
    isNX = true,
    android = false,
    launcher = true,
    workState = nil,
    tab = "red",
    panelVersion = "red",
    saveNotice = {},
    ready = { red = true, blue = false, yellow = false },
    activeSlot = {},
    slotScroll = {},
    slots = {},
    ensureImportsDir = RomImporter.ensureImportsDir,
    ensureSavesInboxDir = RomImporter.ensureSavesInboxDir,
    ensureModsInboxDir = RomImporter.ensureModsInboxDir,
    _setNxSavesInboxNotice = RomImporter._setNxSavesInboxNotice,
    _resolveSaveVersion = RomImporter._resolveSaveVersion,
    scanSavesInbox = RomImporter.scanSavesInbox,
    scanModsInbox = RomImporter.scanModsInbox,
    scanInbox = RomImporter.scanInbox,
    rescanSavesAction = RomImporter.rescanSavesAction,
    chooseSaveImport = RomImporter.chooseSaveImport,
    exportSave = RomImporter.exportSave,
    _importSave = RomImporter._importSave,
    _savedropTarget = RomImporter._savedropTarget,
    _savesDefaultHint = RomImporter._savesDefaultHint,
    _refreshSlots = function(self, version)
      self._refreshed = (self._refreshed or 0) + 1
      self._refreshVersion = version
    end,
  }, RomImporter)
end

-- RES-07: fixture uses isNX=true, android=false
local ri = freshImporter()
eq(ri.isNX, true, "RES-07: fixture isNX=true")
eq(ri.android, false, "RES-07: fixture android=false")

-- RES-01: ensureSavesInboxDir creates imports/, imports/saves/, and per-game dirs
createdDirs = {}
ri = freshImporter()
ri:ensureSavesInboxDir("red")
check(createdDirs.imports == true,
  "RES-01: ensureSavesInboxDir creates parent imports/")
check(createdDirs["imports/saves"] == true,
  "RES-01: ensureSavesInboxDir creates imports/saves/")
check(createdDirs["imports/saves/red"] == true,
  "RES-01: ensureSavesInboxDir creates imports/saves/red/")
check(createdDirs["imports/saves/blue"] == true,
  "RES-01: ensureSavesInboxDir creates imports/saves/blue/")
check(createdDirs["imports/saves/yellow"] == true,
  "RES-01: ensureSavesInboxDir creates imports/saves/yellow/")
check(createdDirs["imports/saves/gold"] == true,
  "RES-01: ensureSavesInboxDir creates imports/saves/gold/")
check(createdDirs["imports/saves/silver"] == true,
  "RES-01: ensureSavesInboxDir creates imports/saves/silver/")

-- NXSAV-02: notice/hint includes save dir + per-game imports/saves/<version>/ MTP path
ri = freshImporter()
ri:_setNxSavesInboxNotice("red")
check(ri.saveNotice.red ~= nil, "NX saves inbox notice is set")
check(ri.saveNotice.red.text:find("sdmc:/switch/gen1recomp/pokemon-love2d/imports/saves/red/", 1, true),
  "saves notice contains runtime save path + imports/saves/red/")
check(ri.saveNotice.red.text:find("DBI MTP", 1, true) ~= nil,
  "saves notice contains OpenMTP-oriented hint")
check(ri.saveNotice.red.text:find("imports/saves/red/", 1, true),
  "hint uses per-game imports/saves/red/ path")

-- NXSAV-01 / RES-08: scanSavesInbox returns only *.sav under imports/saves/<version>/
ri = freshImporter()
love.filesystem.write("imports/saves/red/valid.sav", string.rep("S", 32))
love.filesystem.write("imports/saves/red/readme.txt", "nope")
love.filesystem.write("imports/saves/red/cart.gb", string.rep("R", 16))
love.filesystem.write("imports/saves/red/pack.zip", "ZIP")
love.filesystem.write("imports/saves/blue/other.sav", "WRONGGAME")
love.filesystem.write("imports/other.sav", "WRONGDIR")
local savs = ri:scanSavesInbox("red")
eq(#savs, 1, "scanSavesInbox returns one .sav candidate for red")
eq(savs[1], "imports/saves/red/valid.sav", "scanSavesInbox path is under imports/saves/red/")

-- RES-08: ROM scanInbox must not treat imports/saves/*.sav as ROM
ri = freshImporter()
love.filesystem.write("imports/saves/red/cart.sav", string.rep("S", 32))
love.filesystem.write("imports/saves/red/dump.gb", string.rep("G", 16))
local roms = ri:scanInbox()
for _, path in ipairs(roms) do
  check(not path:lower():match("%.sav$"),
    "ROM scanInbox ignores .sav: " .. tostring(path))
  check(not path:find("imports/saves/", 1, true),
    "ROM scanInbox ignores imports/saves/: " .. tostring(path))
end

-- RES-08: mod scanModsInbox ignores .sav
ri = freshImporter()
ri:ensureModsInboxDir()
love.filesystem.write("imports/mods/mod.zip", "ZIP")
love.filesystem.write("imports/saves/red/slot.sav", string.rep("S", 32))
local zips = ri:scanModsInbox()
for _, path in ipairs(zips) do
  check(not path:lower():match("%.sav$"),
    "mod scanModsInbox ignores .sav: " .. tostring(path))
end
eq(#zips, 1, "mod scanModsInbox still finds only its zip")

-- Stub SaveFileIO.importToSlot for rescan tests
local importCalls = {}
local importBehavior = {} -- path -> {ok=bool, id=string|err}
package.loaded["src.import.SaveFileIO"] = {
  importToSlot = function(source, version)
    importCalls[#importCalls + 1] = { source = source, version = version }
    local b = importBehavior[source]
    if not b then return false, "unexpected source: " .. tostring(source) end
    if b.ok then return true, b.id or "slot-1" end
    return false, b.err or "bad sav"
  end,
  exportActiveSlot = function()
    return false, "no save"
  end,
}

-- RES-04: empty inbox rescan → MTP notice, no import
ri = freshImporter()
importCalls = {}
ri:rescanSavesAction("red")
eq(#importCalls, 0, "empty saves inbox does not call importToSlot")
check(ri.saveNotice.red ~= nil, "RES-04: empty rescan sets saveNotice")
check(ri.saveNotice.red.text:find("imports/saves/red/", 1, true),
  "empty rescan shows saves MTP notice")

-- RES-02: AppleDouble-only inbox ≡ empty
ri = freshImporter()
importCalls = {}
love.filesystem.write("imports/saves/red/._foo.sav", "APPL")
ri:rescanSavesAction("red")
eq(#importCalls, 0, "RES-02: AppleDouble-only does not import")
check(ri.saveNotice.red ~= nil and ri.saveNotice.red.text:find("imports/saves/red/", 1, true),
  "RES-02: AppleDouble-only shows MTP notice")

-- NXSAV-03 / RES-05: success → refresh; bytes kept as *.sav.imported (not re-scanned)
ri = freshImporter()
importCalls = {}
removed = {}
love.filesystem.write("imports/saves/red/good.sav", "GOODSAV")
importBehavior["imports/saves/red/good.sav"] = { ok = true, id = "slot-good" }
ri:rescanSavesAction("red")
eq(#importCalls, 1, "success path calls importToSlot once")
eq(importCalls[1].source, "imports/saves/red/good.sav", "importToSlot receives inbox path")
eq(importCalls[1].version, "red", "importToSlot uses panel version")
check(ri._refreshed and ri._refreshed >= 1, "success refreshes slots")
check(ri.saveNotice.red and ri.saveNotice.red.ok, "success sets ok notice")
check(ri.saveNotice.red.text:find("Pokemon Red", 1, true)
    or ri.saveNotice.red.text:find("Red", 1, true),
  "success notice names the game tab")
check(love.filesystem.getInfo("imports/saves/red/good.sav") == nil,
  "RES-05: success retires live .sav (no longer a candidate)")
check(love.filesystem.read("imports/saves/red/good.sav.imported") == "GOODSAV",
  "RES-05: success keeps bytes under .sav.imported")
check(love.filesystem.getInfo("imports/saves/red/.imported-sha1") ~= nil,
  "success records content hash ledger")

-- Re-press Import save must not clone slots (hash ledger + retired file)
ri = freshImporter()
importCalls = {}
love.filesystem.write("imports/saves/red/again.sav", "SAMEBYTES")
importBehavior["imports/saves/red/again.sav"] = { ok = true, id = "slot-1" }
ri:rescanSavesAction("red")
eq(#importCalls, 1, "first import of again.sav")
-- Put the same bytes back under a new name (player re-copied / renamed)
love.filesystem.write("imports/saves/red/again-copy.sav", "SAMEBYTES")
importBehavior["imports/saves/red/again-copy.sav"] = { ok = true, id = "slot-clone" }
importCalls = {}
ri:rescanSavesAction("red")
eq(#importCalls, 0, "harden: same content hash is not imported again")
check(ri.saveNotice.red and ri.saveNotice.red.ok,
  "harden: already-imported skip sets ok notice")
check(ri.saveNotice.red.text:find("Already imported", 1, true)
    or ri.saveNotice.red.text:find("skipped", 1, true),
  "harden: notice explains skip")
check(love.filesystem.getInfo("imports/saves/red/again-copy.sav") == nil,
  "harden: leftover duplicate .sav is retired without importing")

-- NXSAV-04 / RES-05: failure → clear notice; .sav retained as-is
ri = freshImporter()
importCalls = {}
removed = {}
love.filesystem.write("imports/saves/red/bad.sav", "BADSAV")
importBehavior["imports/saves/red/bad.sav"] = { ok = false, err = "save file must be 32768 bytes" }
ri:rescanSavesAction("red")
eq(#importCalls, 1, "failure path still attempts importToSlot")
check(ri.saveNotice.red and not ri.saveNotice.red.ok, "failure sets clear error notice")
check(ri.saveNotice.red.text:find("32768", 1, true),
  "failure notice includes import error")
check(not removed["imports/saves/red/bad.sav"], "RES-05: failure does not remove inbox .sav")
check(love.filesystem.read("imports/saves/red/bad.sav") == "BADSAV",
  "RES-05: failure leaves .sav in inbox")

-- Mixed valid/invalid: attempt each; bad retained, good retired
ri = freshImporter()
importCalls = {}
removed = {}
love.filesystem.write("imports/saves/red/a-bad.sav", "BAD")
love.filesystem.write("imports/saves/red/b-good.sav", "GOOD")
importBehavior["imports/saves/red/a-bad.sav"] = { ok = false, err = "bad checksum" }
importBehavior["imports/saves/red/b-good.sav"] = { ok = true, id = "slot-b" }
ri:rescanSavesAction("red")
eq(#importCalls, 2, "mixed inbox attempts each .sav")
check(love.filesystem.read("imports/saves/red/a-bad.sav") == "BAD",
  "mixed: bad .sav retained")
check(love.filesystem.getInfo("imports/saves/red/b-good.sav") == nil,
  "mixed: good .sav retired")
check(love.filesystem.read("imports/saves/red/b-good.sav.imported") == "GOOD",
  "mixed: good bytes kept as .imported")
check(ri.saveNotice.red and ri.saveNotice.red.ok, "mixed keeps overall success when one imports")
check(ri.saveNotice.red.text:find("failed", 1, true),
  "mixed success notice still surfaces sibling failure")
check(ri.saveNotice.red.text:find("bad checksum", 1, true),
  "mixed success notice includes the failure reason")

-- Multi-success notice names count + active slot (not only last ok line)
ri = freshImporter()
importCalls = {}
love.filesystem.write("imports/saves/red/one.sav", "ONE")
love.filesystem.write("imports/saves/red/two.sav", "TWO")
importBehavior["imports/saves/red/one.sav"] = { ok = true, id = "slot-one" }
importBehavior["imports/saves/red/two.sav"] = { ok = true, id = "slot-two" }
ri:rescanSavesAction("red")
eq(#importCalls, 2, "multi-success imports each distinct .sav")
check(ri.saveNotice.red.text:find("Imported 2 saves", 1, true),
  "multi-success notice reports count")
check(ri.saveNotice.red.text:find("Active:", 1, true),
  "multi-success notice reports active slot")
eq(ri.activeSlot.red, "slot-two", "multi-success leaves last import active")

-- RES-03: Mac MTP AppleDouble (._*.sav) must not be import candidates
ri = freshImporter()
importCalls = {}
love.filesystem.write("imports/saves/red/._cart.sav", "APPL")
love.filesystem.write("imports/saves/red/cart.sav", "GOOD")
importBehavior["imports/saves/red/cart.sav"] = { ok = true, id = "slot-cart" }
ri:rescanSavesAction("red")
eq(#importCalls, 1, "RES-03: AppleDouble ._*.sav is skipped")
eq(importCalls[1].source, "imports/saves/red/cart.sav",
  "only the real .sav is imported")
check(ri.saveNotice.red and ri.saveNotice.red.ok, "AppleDouble skip still shows import success")
check(not (ri.saveNotice.red.text or ""):find("failed", 1, true),
  "RES-03: AppleDouble-only sibling does not invent a mixed failure line")

-- RES-06: NX chooseSaveImport must not call HostShell / chooseSav path
local hostShellCalls = 0
package.loaded["src.core.HostShell"] = {
  run = function()
    hostShellCalls = hostShellCalls + 1
    error("HostShell must not run on NX chooseSaveImport")
  end,
  popen = function()
    hostShellCalls = hostShellCalls + 1
    error("HostShell.popen must not run on NX chooseSaveImport")
  end,
  available = function() return false end,
}
-- Re-require so chooseSav sees the stubbed HostShell if it were reached.
package.loaded["src.import.RomImporter"] = nil
RomImporter = require("src.import.RomImporter")
ri = freshImporter()
hostShellCalls = 0
ri:chooseSaveImport("red")
eq(hostShellCalls, 0, "RES-06: NX chooseSaveImport does not require HostShell")

-- NXSAV-05: chooseSaveImport on NX rescans inbox
ri = freshImporter()
importCalls = {}
hostShellCalls = 0
love.filesystem.write("imports/saves/red/from-choose.sav", "CHOOSE")
importBehavior["imports/saves/red/from-choose.sav"] = { ok = true, id = "slot-choose" }
ri:chooseSaveImport("red")
eq(hostShellCalls, 0, "NX chooseSaveImport does not use HostShell")
eq(#importCalls, 1, "NX chooseSaveImport rescans and imports inbox .sav")
eq(importCalls[1].source, "imports/saves/red/from-choose.sav",
  "NX chooseSaveImport imports from imports/saves/red/")
check(ri.saveNotice.red and ri.saveNotice.red.ok, "NX chooseSaveImport success notice")

-- Empty chooseSaveImport still sets notice (RES-04 via Import save button)
ri = freshImporter()
importCalls = {}
ri:chooseSaveImport("red")
eq(#importCalls, 0, "empty NX chooseSaveImport does not import")
check(ri.saveNotice.red ~= nil and ri.saveNotice.red.text:find("imports/saves/red/", 1, true),
  "empty NX chooseSaveImport sets MTP notice")

-- Edge: ROM not ready → refuse with existing notice (no silent no-op)
ri = freshImporter()
importCalls = {}
removed = {}
ri.ready.red = false
love.filesystem.write("imports/saves/red/need-rom.sav", "NEEDROM")
importBehavior["imports/saves/red/need-rom.sav"] = { ok = true, id = "should-not-import" }
ri:chooseSaveImport("red")
eq(#importCalls, 0, "ROM-not-ready: chooseSaveImport does not call importToSlot")
check(ri.saveNotice.red and not ri.saveNotice.red.ok,
  "ROM-not-ready: chooseSaveImport sets error notice")
check(ri.saveNotice.red.text:find("Import the Pokemon Red ROM before importing a save", 1, true),
  "ROM-not-ready: notice tells player to import ROM first")
check(not removed["imports/saves/red/need-rom.sav"],
  "ROM-not-ready: retains inbox .sav")
check(love.filesystem.read("imports/saves/red/need-rom.sav") == "NEEDROM",
  "ROM-not-ready: leaves .sav bytes in inbox")

ri = freshImporter()
importCalls = {}
ri.ready.red = false
love.filesystem.write("imports/saves/red/need-rom2.sav", "NEEDROM2")
importBehavior["imports/saves/red/need-rom2.sav"] = { ok = true, id = "should-not" }
ri:rescanSavesAction("red")
eq(#importCalls, 0, "ROM-not-ready: rescan does not call importToSlot")
check(ri.saveNotice.red and not ri.saveNotice.red.ok,
  "ROM-not-ready: rescan sets error notice")
check(ri.saveNotice.red.text:find("Import the Pokemon Red ROM before importing a save", 1, true),
  "ROM-not-ready: rescan surfaces ROM-first notice")

-- Edge: workState == "working" → Import/rescan no-op without clearing notice
ri = freshImporter()
importCalls = {}
ri.saveNotice.red = { ok = true, text = "PRESERVE_ME" }
ri.workState = "working"
love.filesystem.write("imports/saves/red/busy.sav", "BUSY")
importBehavior["imports/saves/red/busy.sav"] = { ok = true, id = "slot-busy" }
ri:chooseSaveImport("red")
eq(#importCalls, 0, "workState working: chooseSaveImport does not import")
eq(ri.saveNotice.red.text, "PRESERVE_ME",
  "workState working: chooseSaveImport leaves saveNotice unchanged")
ri:rescanSavesAction("red")
eq(#importCalls, 0, "workState working: rescanSavesAction does not import")
eq(ri.saveNotice.red.text, "PRESERVE_ME",
  "workState working: rescanSavesAction leaves saveNotice unchanged")

-- RES-11 / NXSAV-07: NX default SAVE FILES hint mentions per-game inbox
ri = freshImporter()
local defaultHint = ri:_savesDefaultHint("red")
check(defaultHint:find("imports/saves/red/", 1, true),
  "RES-11: NX default hint mentions imports/saves/red/")
check(defaultHint:find("DBI MTP", 1, true),
  "RES-11: NX default hint mentions DBI MTP")
check(not defaultHint:find("system file picker", 1, true),
  "RES-11: NX default hint is not desktop picker wording")

-- Desktop keeps picker-oriented default hint (non-NX)
local desk = setmetatable({
  isNX = false, android = false,
  _savesDefaultHint = RomImporter._savesDefaultHint,
}, RomImporter)
check(desk:_savesDefaultHint():find("new slot", 1, true),
  "desktop default save hint stays picker/drop-oriented")

-- RES-09 / NXSAV-08/09: NX exportSave success notice + no openURL / no dir
local exportCalls = {}
local openURLCalls = 0
love.system.openURL = function()
  openURLCalls = openURLCalls + 1
  error("openURL must not run on NX exportSave")
end
package.loaded["src.import.SaveFileIO"] = {
  importToSlot = function(source, version)
    importCalls[#importCalls + 1] = { source = source, version = version }
    local b = importBehavior[source]
    if not b then return false, "unexpected source: " .. tostring(source) end
    if b.ok then return true, b.id or "slot-1" end
    return false, b.err or "bad sav"
  end,
  exportActiveSlot = function(version)
    exportCalls[#exportCalls + 1] = version
    return true, "sdmc:/switch/gen1recomp/pokemon-love2d/exports/red/gen1recomp-red-slot-1.sav"
  end,
}
ri = freshImporter()
exportCalls = {}
openURLCalls = 0
ri:exportSave("red")
eq(#exportCalls, 1, "NXSAV-08: exportSave calls exportActiveSlot")
eq(exportCalls[1], "red", "exportSave passes panel version")
check(ri.saveNotice.red and ri.saveNotice.red.ok, "NXSAV-09: export success sets ok notice")
check(ri.saveNotice.red.text:find("exports", 1, true),
  "RES-09: export notice mentions exports path")
check(ri.saveNotice.red.text:find("DBI MTP", 1, true),
  "RES-09: export notice mentions MTP hint")
check(ri.saveNotice.red.dir == nil,
  "RES-09: NX export does not set open-folder dir")
eq(openURLCalls, 0, "RES-09: NX exportSave does not call openURL")

-- Export failure still sets notice (not silent)
package.loaded["src.import.SaveFileIO"] = {
  importToSlot = function() return false, "unused" end,
  exportActiveSlot = function() return false, "No save in the active slot." end,
}
ri = freshImporter()
ri:exportSave("red")
check(ri.saveNotice.red and not ri.saveNotice.red.ok,
  "export failure sets clear error notice")
check(ri.saveNotice.red.text:find("No save", 1, true),
  "export failure notice includes reason")

-- Edge: workState == "working" → exportSave no-op without clearing notice
package.loaded["src.import.SaveFileIO"] = {
  importToSlot = function() return false, "unused" end,
  exportActiveSlot = function(version)
    exportCalls[#exportCalls + 1] = version
    return true, "exports/should-not-export.sav"
  end,
}
ri = freshImporter()
exportCalls = {}
ri.saveNotice.red = { ok = true, text = "PRESERVE_EXPORT" }
ri.workState = "working"
ri:exportSave("red")
eq(#exportCalls, 0, "workState working: exportSave does not call exportActiveSlot")
eq(ri.saveNotice.red.text, "PRESERVE_EXPORT",
  "workState working: exportSave leaves saveNotice unchanged")

-- Cleanup + restore stubs
clearSavesInbox()
love.filesystem.remove("imports/other.sav")
package.loaded["src.import.SaveFileIO"] = nil
package.loaded["src.core.HostShell"] = nil
love.data.hash = saved.hash
love.data.encode = saved.encode
love.system.getOS = saved.getOS
love.system.openURL = nil
love.filesystem.getSaveDirectory = saved.getSaveDirectory
love.filesystem.createDirectory = saved.createDirectory
love.filesystem.remove = saved.remove
package.loaded["src.core.Platform"] = nil
package.loaded["src.import.RomImporter"] = nil

S.finish()
