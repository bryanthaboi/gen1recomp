package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("launcher mods inbox scan budget")
local eq = S.eq
local check = S.check

local files, dirs, arch = {}, {}, {}
local ARCHIVES = {}
local counts = {}
local now = 0
local WRITE_COST = 0.001

local function bump(name) counts[name] = (counts[name] or 0) + 1 end
local function resetCounts() for k in pairs(counts) do counts[k] = nil end end
local function count(name) return counts[name] or 0 end

local function dirChild(key, name)
  if name == nil or name == "" then return key:match("^[^/]+") end
  local prefix = name .. "/"
  if key:sub(1, #prefix) ~= prefix then return nil end
  return key:sub(#prefix + 1):match("^[^/]+")
end

local function mapInfo(map, name, kind)
  if map[name] ~= nil then
    local body = map[name]
    return { type = kind or "file", size = type(body) == "string" and #body or 0, modtime = 1700000000 }
  end
  for key in pairs(map) do
    if dirChild(key, name) then return { type = "directory" } end
  end
  return nil
end

local vfs = {}

local throwOn
local readCostPerMiB = 0
local MiB = 1024 * 1024

local function readCost(name, body)
  if type(body) ~= "string" then return end
  now = now + readCostPerMiB * #body / MiB
  local ext = name:lower():match("%.([%w]+)$")
  if ext then bump("read_" .. ext) end
end

function vfs.write(name, data)
  now = now + WRITE_COST
  bump("write")
  if throwOn and name:find(throwOn, 1, true) then
    throwOn = nil
    error("simulated sd fault")
  end
  files[name] = data
  return true
end

function vfs.read(name)
  if name:lower():match("%.zip$") then bump("zipRead") end
  if arch[name] ~= nil then return arch[name] end
  readCost(name, files[name])
  return files[name]
end

function vfs.remove(name)
  files[name] = nil
  dirs[name] = nil
  return true
end

function vfs.createDirectory(name)
  dirs[name] = true
  return true
end

function vfs.getInfo(name, kind)
  local info = mapInfo(arch, name) or mapInfo(files, name) or mapInfo(dirs, name, "directory")
  if info and kind and info.type ~= kind then return nil end
  return info
end

function vfs.getDirectoryItems(name)
  local seen, items = {}, {}
  local function add(child)
    if child and not seen[child] then
      seen[child] = true
      items[#items + 1] = child
    end
  end
  for key in pairs(arch) do add(dirChild(key, name)) end
  for key in pairs(files) do add(dirChild(key, name)) end
  for key in pairs(dirs) do add(dirChild(key, name)) end
  table.sort(items)
  return items
end

local mountedAt = {}

function vfs.mount(archive, point)
  bump("mount")
  local data = type(archive) == "table" and archive.data or files[archive]
  local contents = ARCHIVES[data]
  if not contents then return false end
  mountedAt[archive] = point
  for rel, body in pairs(contents) do arch[point .. "/" .. rel] = body end
  return true
end

function vfs.unmount(archive)
  local point = mountedAt[archive]
  mountedAt[archive] = nil
  if not point then return true end
  for k in pairs(arch) do
    if k:sub(1, #point + 1) == point .. "/" then arch[k] = nil end
  end
  return true
end

function vfs.newFileData(data, name)
  bump("newFileData")
  return { __filedata = true, data = data, name = name }
end

function vfs.newFile(name)
  if name:lower():match("%.zip$") then bump("zipOpen") end
  local openExt = name:lower():match("%.([%w]+)$")
  if openExt then bump("open_" .. openExt) end
  local f = { pos = 1 }
  function f:open(mode)
    if mode == "r" and files[name] == nil then return false, "missing" end
    return true
  end
  function f:read(n)
    local out = (files[name] or ""):sub(self.pos, self.pos + n - 1)
    self.pos = self.pos + #out
    readCost(name, out)
    return out, #out
  end
  function f:close()
    self.closed = true
    return true
  end
  vfs.lastFile = f
  return f
end

function vfs.getSaveDirectory() return "sdmc:/switch/gen1recomp/pokemon-love2d" end
function vfs.getSource() return nil end

local function manifestFor(id)
  return ('{"id":"%s","name":"%s","version":"1.0.0","entry":"main.lua"}'):format(id, id)
end

local function makeArchive(id, nFiles)
  local contents = { [id .. "/manifest.json"] = manifestFor(id), [id .. "/main.lua"] = "return {}\n" }
  for i = 1, nFiles do
    contents[("%s/assets/%02d/f%04d.bin"):format(id, i % 40, i)] = ("x"):rep(16)
  end
  local bytes = "PK\3\4" .. id .. ("z"):rep(nFiles)
  ARCHIVES[bytes] = contents
  return bytes
end

local saved = {
  fs = love.filesystem,
  timer = love.timer,
  getOS = love.system and love.system.getOS,
}
local SaveData = require("src.core.SaveData")
local savedPortable = SaveData.portableBaseDir
SaveData.portableBaseDir = function() return nil end
love.filesystem = vfs
love.timer = { getTime = function() return now end }
love.system = love.system or {}
love.system.getOS = function() return "NX" end
package.loaded["src.core.Platform"] = nil
package.loaded["src.import.CacheFs"] = nil
package.loaded["src.mods.LauncherMods"] = nil
package.loaded["src.import.RomImporter"] = nil
local CacheFs = require("src.import.CacheFs")
local LauncherMods = require("src.mods.LauncherMods")
local RomImporter = require("src.import.RomImporter")
local GameVersion = require("src.core.GameVersion")

local function importer()
  return setmetatable({
    isNX = true, android = false, launcher = true,
    tab = "mods", mods = {},
    ready = { red = false, blue = false, yellow = false },
    _refreshMods = function(self) self._refreshed = (self._refreshed or 0) + 1 end,
  }, RomImporter)
end

local BUDGET = LauncherMods.STEP_BUDGET or 0.008

local function press(ri)
  local t0 = now
  ri:chooseMod()
  return now - t0
end

local function pumpAll(ri, limit)
  local frames, worst = 0, 0
  while ri._inboxJob and frames < (limit or 100000) do
    local t0 = now
    if ri._pumpInboxJob then ri:_pumpInboxJob() else break end
    worst = math.max(worst, now - t0)
    frames = frames + 1
  end
  return frames, worst
end

files["imports/mods/small_mod.zip"] = makeArchive("small_mod", 3)
local ri = importer()
press(ri)
pumpAll(ri)
check(files["mods/small_mod/manifest.json"] ~= nil, "first scan installs the inbox zip")
check(ri.modNotice and ri.modNotice.ok and tostring(ri.modNotice.text):find("small_mod", 1, true),
  "first scan reports the install")

resetCounts()
ri = importer()
press(ri)
pumpAll(ri)
eq(count("zipRead") + count("zipOpen"), 0, "second scan reads no archive bytes")
eq(count("newFileData"), 0, "second scan builds no FileData")
eq(count("mount"), 0, "second scan mounts nothing")
check(ri.modNotice and ri.modNotice.ok and not tostring(ri.modNotice.text):find("already installed'", 1, true),
  "second scan notice is not an install error")

files["mods/small_mod/manifest.json"] = nil
resetCounts()
ri = importer()
press(ri)
pumpAll(ri)
check(count("newFileData") >= 1, "a tree without manifest.json counts as not installed")
check(files["mods/small_mod/manifest.json"] ~= nil, "manifest-less tree is reinstalled")

files["imports/mods/a_bad.zip"] = "not a zip at all"
files["imports/mods/big_mod.zip"] = makeArchive("big_mod", 2000)
CacheFs.prefix = "red/"
resetCounts()
ri = importer()
local pressCost = press(ri)
check(pressCost <= 2 * BUDGET, ("the press costs at most 2x budget (%.3fs)"):format(pressCost))
check(ri._inboxJob ~= nil, "a big zip leaves a scan job running after the press")
check(files["mods/big_mod/manifest.json"] == nil, "manifest is not written during the press")
eq(CacheFs.prefix, "red/", "CacheFs.prefix is the caller's between frames")
eq(ri.modScanBusy and ri:modScanBusy(), true, "modScanBusy reports the job")
eq(ri.modScanBusy and ri:_modsImportButtonLabel(), "Installing...", "import button reads Installing... while busy")

local job = ri._inboxJob
local reads = count("zipRead") + count("zipOpen")
local idx = job and job.index
ri:chooseMod()
check(ri._inboxJob == job and (job == nil or job.index == idx), "second press while scanning keeps the same job")
eq(count("zipRead") + count("zipOpen"), reads, "second press while scanning reads nothing")

local prefixOk = true
local frames, worst = 0, 0
while ri._inboxJob and frames < 100000 do
  local t0 = now
  ri:_pumpInboxJob()
  worst = math.max(worst, now - t0)
  frames = frames + 1
  if CacheFs.prefix ~= "red/" then prefixOk = false end
end
check(frames > 10, ("the install spans many frames (%d)"):format(frames))
check(worst <= 2 * BUDGET, ("no frame exceeds 2x budget (%.4fs)"):format(worst))
check(prefixOk, "CacheFs.prefix is restored at every frame boundary")
CacheFs.prefix = ""
check(files["mods/big_mod/manifest.json"] ~= nil, "big zip installs once pumped")
check(files["mods/big_mod/assets/00/f2000.bin"] ~= nil, "every file of the big zip is copied")
check(ri.modNotice and ri.modNotice.ok, "mixed scan keeps overall success")
check(tostring(ri.modNotice.text):find("big_mod", 1, true), "notice names the installed mod")
check(tostring(ri.modNotice.text):find("not a zip file", 1, true), "bad zip still reported beside success")
check((ri._refreshed or 0) == 1, "mods list refreshed once per scan")

resetCounts()
ri = importer()
press(ri)
pumpAll(ri)
eq(count("zipRead") + count("zipOpen"), 1, "next scan re-reads only the bad zip")
eq(count("newFileData"), 0, "next scan mounts no installed zip")

files["imports/mods/dup.zip"] = makeArchive("small_mod", 1)
resetCounts()
ri = importer()
press(ri)
pumpAll(ri)
check(ri.modNotice and tostring(ri.modNotice.text):find("already installed", 1, true),
  "a zip for an installed id reports the conflict once")
resetCounts()
ri = importer()
press(ri)
pumpAll(ri)
eq(count("newFileData"), 0, "conflicting zip is not read again")
eq(count("zipRead") + count("zipOpen"), 1, "only the bad zip is read again")

files["imports/mods/a_bad.zip"] = nil
ri = importer()
press(ri)
pumpAll(ri)
check(ri.modNotice and ri.modNotice.ok == false
    and tostring(ri.modNotice.text):find("a mod named 'small_mod' is already installed", 1, true),
  "a skipped conflicting zip still reports the conflict", ri.modNotice and ri.modNotice.text)
files["imports/mods/dup.zip"] = makeArchive("small_mod", 2)
resetCounts()
ri = importer()
press(ri)
pumpAll(ri)
eq(count("newFileData"), 1, "a changed conflicting zip is read again")
files["imports/mods/dup.zip"] = nil

local function liveMounts()
  local n = 0
  for _ in pairs(mountedAt) do n = n + 1 end
  return n
end

local function freshBig(id, n)
  for k in pairs(files) do
    if k:sub(1, #("mods/" .. id .. "/")) == "mods/" .. id .. "/" then files[k] = nil end
  end
  files["imports/mods/" .. id .. ".zip"] = makeArchive(id, n)
end

freshBig("play_mod", 400)
CacheFs.prefix = "red/"
ri = importer()
ri.ready.red = true
local launched = 0
ri.onComplete = function() launched = launched + 1 end
press(ri)
check(ri._inboxJob ~= nil, "play test: scan is running")
ri.tab = "red"
pcall(ri.play, ri, "red")
check(ri._handedOff ~= true and launched == 0, "play is blocked while a mod scan runs")
eq(ri.tab, "mods", "a blocked play shows the mods tab")
check(ri._inboxJob ~= nil, "a blocked play keeps the scan running")
pumpAll(ri)
check(files["mods/play_mod/manifest.json"] ~= nil, "the scan finishes after a blocked play")

freshBig("arena_mod", 400)
ri = importer()
ri.onComplete = function() launched = launched + 1 end
press(ri)
check(ri._inboxJob ~= nil and liveMounts() == 1, "arena test: scan is running with one mount")
pcall(ri.playArena, ri, "red", nil, { arena = true })
check(ri._inboxJob == nil, "an arena start cancels the scan")
eq(liveMounts(), 0, "a cancelled scan unmounts its archive")
eq(CacheFs.prefix, "red/", "a cancelled scan leaves the caller's CacheFs.prefix")
check(files["mods/arena_mod/manifest.json"] == nil, "a cancelled scan writes no manifest")

local dropped = importer()
press(dropped)
check(dropped._inboxJob ~= nil and liveMounts() == 1, "a scan is running when its launcher is dropped")
dropped = nil
collectgarbage("collect")
files["imports/mods/arena_mod.zip"] = nil
files["imports/mods/late_mod.zip"] = makeArchive("late_mod", 2)
ri = importer()
press(ri)
pumpAll(ri)
check(files["mods/late_mod/manifest.json"] ~= nil,
  "the next scan installs after an abandoned one", ri.modNotice and ri.modNotice.text)
eq(liveMounts(), 0, "the abandoned scan's archive is released")

freshBig("fault_mod", 400)
files["imports/mods/zz_after.zip"] = makeArchive("zz_after", 2)
throwOn = "fault_mod/assets/00/f0200.bin"
ri = importer()
press(ri)
local faultPrefixOk = true
local guard = 0
while ri._inboxJob and guard < 100000 do
  ri:_pumpInboxJob()
  if CacheFs.prefix ~= "red/" then faultPrefixOk = false end
  guard = guard + 1
end
check(throwOn == nil, "the fault fired mid-copy")
check(faultPrefixOk, "an error mid-job restores CacheFs.prefix")
eq(liveMounts(), 0, "an error mid-job unmounts the archive")
check(ri.modNotice and tostring(ri.modNotice.text):find("simulated sd fault", 1, true),
  "an error mid-job is reported", ri.modNotice and ri.modNotice.text)
check(files["mods/zz_after/manifest.json"] ~= nil, "the scan continues after an error mid-job")
CacheFs.prefix = ""

local direct = LauncherMods.beginInstallZip and LauncherMods.beginInstallZip("imports/mods/big_mod.zip",
  { replace = true, expectId = "big_mod" })
if direct then
  local steps, state, ok, id = 0, nil, nil, nil
  repeat
    local t0 = now
    state, ok, id = LauncherMods.stepInstall(direct, BUDGET)
    worst = math.max(worst, now - t0)
    steps = steps + 1
  until state == "done" or steps > 100000
  check(steps > 1 and ok == true and id == "big_mod", "stepInstall replaces in several steps")
  local syncOk, syncId = LauncherMods.installZip("imports/mods/big_mod.zip", { replace = true })
  check(syncOk == true and syncId == "big_mod", "blocking installZip still works")
else
  check(false, "LauncherMods.beginInstallZip exists")
end

for k in pairs(files) do
  if k:match("^imports/mods/[^/]+%.zip$") then files[k] = nil end
end
local capBytes = LauncherMods.NX_MAX_ZIP_BYTES or 64 * MiB
local hugeBytes = "PK\3\4huge_mod" .. ("z"):rep(capBytes)
ARCHIVES[hugeBytes] = { ["huge_mod/manifest.json"] = manifestFor("huge_mod"),
  ["huge_mod/main.lua"] = "return {}\n" }
files["imports/mods/huge_mod.zip"] = hugeBytes
resetCounts()
ri = importer()
press(ri)
pumpAll(ri)
eq(count("zipRead") + count("zipOpen"), 0, "an oversized zip on Switch is never read")
eq(count("newFileData"), 0, "an oversized zip on Switch builds no FileData")
check(files["mods/huge_mod/manifest.json"] == nil, "an oversized zip on Switch is not installed")
check(ri.modNotice and ri.modNotice.ok == false
    and tostring(ri.modNotice.text):find("huge_mod.zip", 1, true)
    and tostring(ri.modNotice.text):find("64 MiB or smaller", 1, true),
  "the oversized zip notice names the file and the 64 MiB limit", ri.modNotice and ri.modNotice.text)
files["imports/mods/huge_mod.zip"] = nil
ARCHIVES[hugeBytes] = nil
hugeBytes = nil
collectgarbage("collect")
local underBytes = "PK\3\4under_mod" .. ("z"):rep(4096)
ARCHIVES[underBytes] = { ["under_mod/manifest.json"] = manifestFor("under_mod"),
  ["under_mod/main.lua"] = "return {}\n" }
files["imports/mods/under_mod.zip"] = underBytes
ri = importer()
press(ri)
pumpAll(ri)
check(files["mods/under_mod/manifest.json"] ~= nil, "a zip under the Switch cap still installs")
files["imports/mods/under_mod.zip"] = nil

love.data = love.data or {}
local savedData = { hash = love.data.hash, encode = love.data.encode }
love.data.hash = function(_, d) return "h" .. d:sub(1, 8) end
love.data.encode = function(_, _, digest) return digest end
readCostPerMiB = 0.004

local savedSaveFileIO = package.loaded["src.import.SaveFileIO"]
local imported = {}
package.loaded["src.import.SaveFileIO"] = {
  importToSlot = function(source)
    now = now + 0.003
    imported[#imported + 1] = source
    return true, "slot" .. #imported
  end,
}

local function gameImporter(version)
  local gi = importer()
  gi.tab = version
  gi.panelVersion = version
  gi.ready[version] = true
  gi.saveNotice, gi.activeSlot, gi.slotScroll, gi.carts = {}, {}, {}, {}
  gi._refreshSlots = function() end
  return gi
end

for i = 1, 10 do
  files[("imports/saves/red/s%02d.sav"):format(i)] = ("S%02d"):format(i) .. ("\0"):rep(32765)
end
ri = gameImporter("red")
local t0 = now
ri:chooseSaveImport("red")
local saveCost = now - t0
check(saveCost <= 2 * BUDGET, ("a 10-save scan press costs at most 2x budget (%.3fs)"):format(saveCost))
check(ri._inboxJob ~= nil and ri._inboxJob.kind == "saves", "a 10-save scan leaves a job running")
local seen = #imported
local saveJob = ri._inboxJob
ri:chooseSaveImport("red")
check(ri._inboxJob == saveJob and #imported == seen, "a second save press during the scan does nothing")
ri.tab = "mods"
ri.onComplete = function() launched = launched + 1 end
local before = launched
pcall(ri.play, ri, "red")
check(ri._handedOff ~= true and launched == before, "play is blocked while a save scan runs")
eq(ri.tab, "red", "a blocked play shows the save scan's game tab")
local sFrames, sWorst = pumpAll(ri)
check(sFrames > 2, ("the save scan spans several frames (%d)"):format(sFrames))
check(sWorst <= 2 * BUDGET, ("no save scan frame exceeds 2x budget (%.4fs)"):format(sWorst))
eq(#imported, 10, "every inbox save is imported once")
check(files["imports/saves/red/s01.sav"] == nil and files["imports/saves/red/s01.sav.imported"] ~= nil,
  "imported saves are retired")
check(ri.saveNotice.red and ri.saveNotice.red.ok
    and tostring(ri.saveNotice.red.text):find("Imported 10 saves", 1, true),
  "the save scan reports every import", ri.saveNotice.red and ri.saveNotice.red.text)

local savedCartStore = package.loaded["src.carts.CartStore"]
local cartRefresh = {}
package.loaded["src.carts.CartStore"] = {
  DIR = "carts",
  fileFor = function(id) return "carts/" .. id .. ".g1rcart" end,
  install = function(bytes)
    now = now + 0.005
    local id, base = bytes:match("^CART:([%w_]+):(%w+)")
    if not id then return nil, "BAD CART" end
    files["carts/" .. id .. ".g1rcart"] = bytes
    return { id = id, title = id, base = base }
  end,
  listFor = function(version)
    cartRefresh[version] = (cartRefresh[version] or 0) + 1
    return {}
  end,
}
for i = 1, 10 do
  files[("imports/carts/c%02d.g1rcart"):format(i)] = ("CART:c%02d:%s:"):format(i,
    i <= 5 and "red" or "blue") .. ("x"):rep(4096)
end
ri = gameImporter("red")
t0 = now
local cartRet = ri:importCartFile("red")
local cartCost = now - t0
check(cartCost <= 2 * BUDGET, ("a 10-cart scan press costs at most 2x budget (%.3fs)"):format(cartCost))
check(cartRet == true and ri._inboxJob ~= nil and ri._inboxJob.kind == "carts",
  "a 10-cart scan leaves a job running")
local cFrames, cWorst = pumpAll(ri)
check(cFrames > 2, ("the cart scan spans several frames (%d)"):format(cFrames))
check(cWorst <= 2 * BUDGET, ("no cart scan frame exceeds 2x budget (%.4fs)"):format(cWorst))
check(files["carts/c01.g1rcart"] ~= nil and files["carts/c10.g1rcart"] ~= nil, "every inbox cart is installed")
eq(cartRefresh.red, 1, "the red cart list is refreshed once per scan")
eq(cartRefresh.blue, 1, "the blue cart list is refreshed once per scan")
check(ri._cartNotice and tostring(ri._cartNotice):find("c10", 1, true), "the cart scan reports the last import",
  ri._cartNotice)
resetCounts()
ri = gameImporter("red")
ri:importCartFile("red")
pumpAll(ri)
eq(count("read_g1rcart"), 0, "a second cart scan reads no imported cart")
check(ri._cartNotice and tostring(ri._cartNotice):find("already imported", 1, true),
  "a second cart scan says every cart is imported", ri._cartNotice)

local ROM_TAGS = { F = "firered", L = "leafgreen", E = "emerald", R = "red" }
local function romImporter()
  local gi = gameImporter("red")
  gi.ready.red = false
  gi._versionForSha1 = function(_, h) return ROM_TAGS[h:sub(2, 2)] end
  gi.startData = function(self, data, name) self._started = { name = name, size = #data } end
  gi.setError = function(self, message) self._romError = message end
  return gi
end
files["imports/fr.gba"] = "F" .. ("\0"):rep(16 * MiB - 1)
files["imports/lg.gba"] = "L" .. ("\0"):rep(16 * MiB - 1)
files["imports/em.gba"] = "E" .. ("\0"):rep(16 * MiB - 1)
resetCounts()
ri = romImporter()
t0 = now
ri:rescanAction("red")
local romCost = now - t0
check(romCost <= 2 * BUDGET, ("a 48 MiB ROM inbox press costs at most 2x budget (%.3fs)"):format(romCost))
check(ri._inboxJob ~= nil and ri._inboxJob.kind == "roms", "a 48 MiB ROM inbox leaves a scan job running")
check(ri.notice and ri.notice.scanning and ri.notice.version == "red", "the ROM scan shows progress on its tab")
local romJob = ri._inboxJob
ri:rescanAction("red")
check(ri._inboxJob == romJob, "a second ROM press during the scan keeps the same job")
local rFrames, rWorst = pumpAll(ri)
check(rFrames > 10, ("the ROM scan spans many frames (%d)"):format(rFrames))
check(rWorst <= 2 * BUDGET, ("no ROM scan frame exceeds 2x budget (%.4fs)"):format(rWorst))
eq(count("read_gba") >= 3, true, "the first ROM scan reads every dump")
check(ri.notice and tostring(ri.notice.status):find("No matching ROM", 1, true),
  "the ROM scan ends with the no-match notice", ri.notice and ri.notice.status)
check(ri._started == nil, "no import starts without a matching dump")
resetCounts()
ri = romImporter()
ri:rescanAction("red")
pumpAll(ri)
eq(count("read_gba"), 0, "a second ROM scan reads no dump it already identified")
check(ri.notice and tostring(ri.notice.status):find("No matching ROM", 1, true),
  "a second ROM scan gives the same notice")
files["imports/red.gb"] = "R" .. ("\0"):rep(MiB - 1)
ri = romImporter()
ri:rescanAction("red")
pumpAll(ri)
check(ri._started and ri._started.name == "red.gb" and ri._started.size == MiB,
  "the ROM scan starts the matching dump")
files["imports/red.gb"] = nil
files["imports/fr.gba"] = files["imports/fr.gba"] .. "\1"
ri = romImporter()
ri.onComplete = function() end
ri:rescanAction("red")
local arenaJob = ri._inboxJob
local openFile = vfs.lastFile
check(arenaJob ~= nil and openFile ~= nil and not openFile.closed, "a ROM scan holds a dump open between frames")
pcall(ri.playArena, ri, "red", nil, { arena = true })
check(ri._inboxJob == nil, "an arena start cancels the ROM scan")
check(openFile and openFile.closed == true, "a cancelled ROM scan closes its file")
files["imports/fr.gba"], files["imports/lg.gba"], files["imports/em.gba"] = nil, nil, nil
collectgarbage("collect")

files["imports/xa.gba"] = "X" .. ("\0"):rep(16 * MiB - 1)
files["imports/xb.gba"] = "Y" .. ("\0"):rep(16 * MiB - 1)
resetCounts()
ri = romImporter()
ri:rescanAction("red")
pumpAll(ri)
eq(count("open_gba"), 2, "the first scan reads each unknown dump")
check(ri._started and ri._started.name == "xa.gba", "the first scan hands the unknown dump to the importer")
resetCounts()
ri = romImporter()
ri:rescanAction("red")
pumpAll(ri)
eq(count("open_gba"), 0, "a second scan reads no unknown dump it already hashed")
check(ri._started == nil and tostring(ri._romError):find("Unsupported ROM (SHA-1 hX", 1, true),
  "a second scan reports the same unsupported dump", ri._romError)
files["imports/xa.gba"] = "X" .. ("\0"):rep(16 * MiB - 2) .. "\1\1"
resetCounts()
ri = romImporter()
ri:rescanAction("red")
pumpAll(ri)
eq(count("open_gba"), 1, "a changed unknown dump is read again")
files["imports/xa.gba"], files["imports/xb.gba"] = nil, nil
collectgarbage("collect")

local savedModUpdate = package.loaded["src.mods.ModUpdate"]
local downloads = 0
package.loaded["src.mods.ModUpdate"] = {
  downloadZip = function() downloads = downloads + 1 return nil, "no network" end,
  beginDownloadZip = function() downloads = downloads + 1 return { stage = "done" } end,
}
local bigRelease = { version = "2.0.0", zip = { url = "https://example.invalid/big.zip",
  size = (LauncherMods.NX_MAX_ZIP_BYTES or 64 * MiB) + 1 } }
local relOk, relErr = LauncherMods.installFromRelease("giant_mod", bigRelease)
check(relOk == nil and downloads == 0, "an oversized release is refused before downloading", relErr)
check(tostring(relErr):find("giant_mod", 1, true) and tostring(relErr):find("64 MiB", 1, true),
  "the release refusal names the mod and the limit", relErr)
ri = importer()
ri._setBusy = function() end
ri._clearBusy = function() end
pcall(ri._beginModInstall, ri, { modId = "giant_mod", name = "Giant Mod", release = bigRelease })
check(downloads == 0 and ri._modInstall == nil, "the launcher download refuses an oversized release first")
check(ri.modNotice and tostring(ri.modNotice.text):find("Giant Mod", 1, true),
  "the launcher refusal names the mod", ri.modNotice and ri.modNotice.text)
local tmpBig = "PK\3\4giant" .. ("z"):rep(LauncherMods.NX_MAX_ZIP_BYTES or 64 * MiB)
files["mod_update_giant_mod_2.0.0.zip"] = tmpBig
local dlOk, dlErr = LauncherMods.installDownloadedZip("giant_mod", "mod_update_giant_mod_2.0.0.zip", "2.0.0")
check(dlOk == nil and tostring(dlErr):find("giant_mod is", 1, true)
    and not tostring(dlErr):find("mod_update_", 1, true),
  "a downloaded oversized zip is named by its mod, not the temp file", dlErr)
files["mod_update_giant_mod_2.0.0.zip"] = nil
tmpBig = nil
collectgarbage("collect")
package.loaded["src.mods.ModUpdate"] = savedModUpdate

package.loaded["src.import.SaveFileIO"] = {
  importToSlot = function(source, _, force)
    if source:find("big", 1, true) and not force then
      now = now + 0.009
      return nil, nil, { needsConfirm = true, size = 40000 }
    end
    imported[#imported + 1] = source
    return true, "slot" .. #imported
  end,
}
for k in pairs(files) do
  if k:match("^imports/saves/red/") then files[k] = nil end
end
files["imports/saves/red/big.sav"] = "B" .. ("\0"):rep(39999)
local importedBefore = #imported
ri = gameImporter("red")
ri:chooseSaveImport("red")
pumpAll(ri)
check(ri._modConfirm and ri._modConfirm.kind == "importOversize", "an oversized inbox save asks first")
check(not (ri.saveNotice.red and tostring(ri.saveNotice.red.text):find("Importing", 1, true)),
  "no stale progress notice is left under the oversize prompt", ri.saveNotice.red and ri.saveNotice.red.text)
local confirm = ri._modConfirm
ri._modConfirm = nil
ri:_importSave(confirm.version, confirm.source, true)
eq(#imported, importedBefore + 1, "a yes imports the oversized save once")
check(files["imports/saves/red/big.sav"] == nil and files["imports/saves/red/big.sav.imported"] ~= nil,
  "a forced inbox import retires the save")
ri = gameImporter("red")
ri:chooseSaveImport("red")
pumpAll(ri)
check(ri._modConfirm == nil, "the next scan does not prompt for the retired save")
eq(#imported, importedBefore + 1, "the next scan imports nothing again")

local LauncherView = require("src.import.LauncherView")
files["imports/mods/busy_mod.zip"] = makeArchive("busy_mod", 400)
ri = gameImporter("red")
ri.ready.blue = false
ri.returning, ri.baseRoms = {}, {}
press(ri)
check(ri._inboxJob ~= nil, "busy test: a mod scan is running")
local mdl = LauncherView._romModel and LauncherView._romModel(ri, "blue", GameVersion.info("blue"), false, false)
check(mdl and mdl.enabled == false, "the ROM button on another tab is disabled while a scan runs")
check(mdl and tostring(mdl.detail):find("busy_mod", 1, true), "the ROM card shows the running scan",
  mdl and mdl.detail)
ri.workState, ri.errorVersion, ri.detail = "error", "blue", "old failure"
mdl = LauncherView._romModel and LauncherView._romModel(ri, "blue", GameVersion.info("blue"), false, false)
check(mdl and mdl.enabled == false, "an errored tab's ROM button is disabled while a scan runs")
ri.workState = nil
ri:reimport("red")
eq(ri.ready.red, true, "a re-import during a scan leaves the game ready")
pumpAll(ri)
mdl = LauncherView._romModel and LauncherView._romModel(ri, "blue", GameVersion.info("blue"), false, false)
check(mdl and mdl.enabled == true, "the ROM button comes back after the scan")
files["imports/mods/busy_mod.zip"] = nil

readCostPerMiB = 0
love.data.hash, love.data.encode = savedData.hash, savedData.encode
package.loaded["src.import.SaveFileIO"] = savedSaveFileIO
package.loaded["src.carts.CartStore"] = savedCartStore

love.filesystem = saved.fs
love.timer = saved.timer
love.system.getOS = saved.getOS
SaveData.portableBaseDir = savedPortable
package.loaded["src.core.Platform"] = nil
package.loaded["src.import.CacheFs"] = nil
package.loaded["src.mods.LauncherMods"] = nil
package.loaded["src.import.RomImporter"] = nil

S.finish()
