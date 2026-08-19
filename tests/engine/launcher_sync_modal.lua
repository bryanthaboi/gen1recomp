package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
local check, eq = T.check, T.eq
love = love or require("tests.love_stub")

love.graphics.setLineJoin = love.graphics.setLineJoin or function() end
love.graphics.polygon = love.graphics.polygon or function() end
love.graphics.newShader = love.graphics.newShader or function() return {} end

local Kit = require("src.ui.kit.Kit")
local RomImporter = require("src.import.RomImporter")
local LauncherView = require("src.import.LauncherView")

local function read(path)
  local f = assert(io.open(path, "r"))
  local src = f:read("*a")
  f:close()
  return src
end

eq(RomImporter.syncDigits("1234-5678"), "12345678",
   "the dash people read the code with is not part of it")
eq(RomImporter.syncDigits(" 12 34 "), "1234", "spaces are dropped")
eq(RomImporter.syncDigits("abc9"), "9", "letters cannot enter a digit code")
eq(RomImporter.syncDigits("123456789012"), "12345678",
   "a code is eight digits and no more")
eq(RomImporter.syncDigits(nil), "", "an empty field stays empty")

eq(RomImporter.syncShareCode("abc234"), "ABC234", "share codes are upper case")
eq(RomImporter.syncShareCode("A1B0C-D"), "ABCD",
   "1 and 0 are not in the share alphabet")
eq(RomImporter.syncShareCode("ABCDEFGH"), "ABCDEF",
   "a share code is six characters")

local function fakeEngine(over)
  local eng = {
    phase = "idle", status = "Ready", conflicts = {}, state = { enabled = true },
    calls = {},
    isLinked = false,
    linked = function(self) return self.isLinked end,
    busy = function(self) return self.isBusy == true end,
    createAccount = function(self, label)
      self.calls[#self.calls + 1] = { "create", label }
      self.isLinked = true
      self.codes = { code1 = "1234-5678", code2 = "8765-4321" }
      return true
    end,
    linkDevice = function(self, a, b, label)
      self.calls[#self.calls + 1] = { "link", a, b, label }
      if #tostring(a) ~= 8 or #tostring(b) ~= 8 then return false end
      self.isLinked = true
      return true
    end,
    syncNow = function(self)
      self.calls[#self.calls + 1] = { "syncNow" }
      return true
    end,
    unlink = function(self)
      self.calls[#self.calls + 1] = { "unlink" }
      self.isLinked, self.codes = false, nil
      return true
    end,
    shareMods = function(self)
      self.calls[#self.calls + 1] = { "shareMods" }
      self.shareCode = "K7QW3M"
      return true
    end,
    fetchShare = function(self, code)
      self.calls[#self.calls + 1] = { "fetchShare", code }
      return true
    end,
    applyModPlan = function(self, progress)
      self.calls[#self.calls + 1] = { "applyModPlan" }
      if progress then progress(1, 2, "a") progress(2, 2, "b") end
      return true
    end,
    resolveConflict = function(self, key, choice)
      self.calls[#self.calls + 1] = { "resolve", key, choice }
      return true
    end,
  }
  for k, v in pairs(over or {}) do eng[k] = v end
  return eng
end

local function launcher(eng)
  local imp = RomImporter.new(function() end, { launcher = true })
  imp._sync = eng
  imp._syncTransportOk = true
  return imp
end

local eng = fakeEngine()
local imp = launcher(eng)

eq(imp._syncModal, nil, "the modal is closed until the header button opens it")
imp:_openSync()
check(imp._syncModal ~= nil, "the header button opens the modal")
eq(imp._syncModal.view, "home", "and lands on the home view")
eq(imp._syncFocus, nil, "with no field taking the keyboard")

imp:_syncView("link")
eq(imp._syncModal.view, "link", "Link this device swaps the view")
imp:_syncFocusField("code1")
eq(imp._syncFocus, "code1", "tapping a field focuses it")
imp:textinput("12ab34")
eq(imp._syncModal.code1, "1234", "typed letters never reach a code field")
imp:textinput("5678")
eq(imp._syncModal.code1, "12345678", "the field fills to eight digits")
imp:textinput("9")
eq(imp._syncModal.code1, "12345678", "and refuses a ninth")
imp:keypressed("backspace")
eq(imp._syncModal.code1, "1234567", "backspace drops one digit")
imp:textinput("8")

imp:_syncFocusField("code2")
eq(imp._syncFocus, "code2", "focus moves to the second code")
eq(imp._syncModal.code1, "12345678", "without disturbing the first")
imp:_syncFocusField("code2")
eq(imp._syncFocus, nil, "tapping the focused field again releases it")
imp:_syncFocusField("code2")
imp:textinput("87654321")

imp:_syncLink()
eq(eng.calls[#eng.calls][1], "link", "Link sends both codes to the engine")
eq(eng.calls[#eng.calls][2], "12345678", "the first code as typed")
eq(eng.calls[#eng.calls][3], "87654321", "and the second")
eq(imp._syncModal.view, "home", "a linked device comes back to the home view")
eq(imp._syncModal.code1, "", "and the codes are not left lying in the field")
eq(imp._syncModal.code2, "", "either of them")
eq(imp._syncFocus, nil, "with the keyboard released")

local short = launcher(fakeEngine())
short:_openSync()
short:_syncView("link")
short._syncModal.code1, short._syncModal.code2 = "1234", "87654321"
eq(short:_syncLink(), false, "a short code does not link")
eq(short._syncModal.code1, "1234",
   "and what was typed stays put to be corrected")

imp:_syncFocusField("code1")
imp:keypressed("escape")
eq(imp._syncFocus, nil, "escape out of a field releases the keyboard")
check(imp._syncModal ~= nil, "and leaves the modal up")
imp:keypressed("escape")
eq(imp._syncModal, nil, "escape closes the modal")

imp:_openSync()
imp:_syncView("mods")
imp:_syncShareMods()
eq(eng.shareCode, "K7QW3M", "Share mod list asks the engine for a code")
imp:_syncFocusField("share")
imp:textinput("k7qw3m")
eq(imp._syncModal.share, "K7QW3M", "a typed share code is normalized")
imp:_syncGetShare()
eq(eng.calls[#eng.calls][2], "K7QW3M", "and handed to the engine as typed")
imp._syncModal.progress = nil
imp:_syncApplyMods()
eq(imp._syncModal.progress, nil,
   "the progress line is cleared once the apply returns")

imp:_syncResolve("red/abc", "both")
eq(eng.calls[#eng.calls][1], "resolve", "the conflict buttons call the engine")
eq(eng.calls[#eng.calls][3], "both", "with the choice the player pressed")

imp:_syncUnlink()
eq(eng.isLinked, false, "Unlink drops the device")
eq(imp._syncModal.view, "home", "and the modal returns to the home view")

local bare = RomImporter.new(function() end, { launcher = true })
bare._sync = false
bare._syncTransportOk = true
bare:_openSync()
check(bare._syncModal ~= nil, "the modal opens without an engine")
bare:_closeSync()
eq(bare._syncModal, nil, "and closes again")

local function controls(imp2)
  love.graphics.getDimensions = function() return 900, 780 end
  love.graphics.getPixelDimensions = love.graphics.getDimensions
  Kit.audit = {}
  local ok, err = pcall(LauncherView.draw, imp2)
  local labels = {}
  for _, r in ipairs(Kit.audit or {}) do
    if r.class == "control" then labels[r.label] = true end
  end
  Kit.audit = nil
  check(ok, "the sync modal draws: " .. tostring(err))
  return labels
end

local rEng = fakeEngine()
local rImp = launcher(rEng)
rImp:_openSync()
local labels = controls(rImp)
check(labels["Create sync account"], "an unlinked device is offered an account")
check(labels["Link this device"], "and the link road")

rEng:createAccount("mac")
labels = controls(rImp)
check(labels["Sync now"], "a linked device can sync on demand")
check(labels["Unlink this device"], "and unlink")
check(labels["Share or get a mod list"], "and reach the mod list road")

rImp:_syncView("link")
labels = controls(rImp)
check(labels["Back"], "the link view can back out")

rImp:_syncView("mods")
rEng.shareCode = "K7QW3M"
rEng.modPlan = { indexes = { "https://x" }, toInstall = { { id = "a" } },
  toEnable = {}, missing = {} }
labels = controls(rImp)
check(labels["Share mod list"], "the mod view shares a list")
check(labels["Get mod list"], "and fetches one")
check(labels["Apply these mods"], "a fetched plan can be applied")

rImp:_syncView("home")
rEng.devices = {
  { id = "0a1b2c3d", label = "OS X", current = true },
  { id = "99998888", label = "Android" },
}
labels = controls(rImp)
check(labels["Unlink Android"], "the other linked devices can be revoked here")
check(labels["OS X  \194\183  this device"],
      "and this one is named rather than offered twice")

local devRows = LauncherView.syncDeviceRows(rEng)
eq(#devRows, 2, "the modal reads the device list off the engine")
eq(devRows[1].current, true, "knowing which one is this device")
eq(#LauncherView.syncDeviceRows({}), 0,
   "an engine that has not synced yet lists nothing")

local offline = launcher(fakeEngine())
offline._syncTransportOk = false
offline:_openSync()
labels = controls(offline)
check(not labels["Create sync account"],
      "a device with no way to send signed requests is not offered an account")
check(labels["Close"], "it just explains itself and closes")

rEng.devices = nil
rEng.phase = "conflict"
rEng.conflicts = { {
  key = "red/abc", version = "red", overlap = true,
  localMeta = { savedAt = 1700000000, sessionStart = 1699999000,
    summary = { name = "ASH", badges = 3, timeText = "5:42", dexCount = 40 } },
  remoteMeta = { savedAt = 1700000500, sessionStart = 1699999500,
    summary = { name = "ASH", badges = 4, timeText = "6:10", dexCount = 44 } },
} }
labels = controls(rImp)
check(labels["Keep this device"], "a conflict offers this device")
check(labels["Keep the other device"], "the other device")
check(labels["Keep both"], "and keeping both")
check(not labels["Sync now"],
      "a conflict takes over the modal until it is answered")

local side = LauncherView.syncSideText({ savedAt = 1700000000,
  summary = { name = "ASH", badges = 3, timeText = "5:42", dexCount = 40 } })
check(side:find("ASH", 1, true) ~= nil, "a side summary names the trainer")
check(side:find("3 badges", 1, true) ~= nil, "counts badges")
check(side:find("5:42", 1, true) ~= nil, "and shows play time")
eq(LauncherView.syncSideText(nil), "no details",
   "a side with no metadata says so rather than drawing blank")

local quiet = launcher(fakeEngine())
quiet:_pumpSync(0.016)
eq(quiet._syncModal, nil, "a quiet auto-sync never interrupts the launcher")

local raised = launcher(fakeEngine({ phase = "conflict",
  conflicts = { { key = "red/abc", version = "red" } } }))
raised:_pumpSync(0.016)
check(raised._syncModal ~= nil,
      "a conflict found by the boot sync opens the prompt on its own")
raised:_closeSync()
raised:_pumpSync(0.016)
eq(raised._syncModal, nil,
   "and a prompt the player dismissed does not reopen every frame")

local view = read("src/import/LauncherView.lua")
local impSrc = read("src/import/RomImporter.lua")

check(view:find('"tab-sync"', 1, true) ~= nil,
      "the header tab row carries a Save Sync button")
local header = view:match("local HEADER_TABS = %{(.-)%}\n")
check(header and header:find('id = "skins"', 1, true) ~= nil,
      "and it sits beside the skins tab")
check(view:find('"BETA"', 1, true) ~= nil,
      "the button and the modal are labelled BETA")
check(view:find("buildSyncModal", 1, true) ~= nil,
      "the sync UI is a modal, so it works from any tab")
local modals = view:match("local function modalUp%(imp%)(.-)\nend")
check(modals and modals:find("_syncModal", 1, true) ~= nil,
      "the modal raises the click shield like every other one")
check(view:find("if imp._syncModal then buildSyncModal", 1, true) ~= nil,
      "and buildModals routes it")

check(impSrc:find("_pumpSync(dt)", 1, true) ~= nil,
      "the launcher pumps the sync engine every frame")
local pump = impSrc:match("function RomImporter:_pumpSync%(dt%)(.-)\nend\n")
check(pump and pump:find("self.launcher", 1, true) ~= nil,
      "only the interactive launcher boots an engine of its own")
check(impSrc:find("_syncTypeInto", 1, true) ~= nil,
      "text input is routed through the code filter")

T.finish("launcher_sync_modal")
