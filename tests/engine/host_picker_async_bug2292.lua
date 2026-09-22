package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local S = require("tests.harness").suite("mod import picker off the main thread (#2292)")
local check, eq = S.check, S.eq

local Platform = require("src.core.Platform")
local HostPicker = require("src.core.HostPicker")
local RomImporter = require("src.import.RomImporter")

love.system = love.system or {}
local saved = {
  getOS = love.system.getOS,
  pickFile = love.system.pickFile,
  pickFileKinds = love.system.pickFileKinds,
  thread = love.thread,
  mouse = love.mouse,
  popen = io.popen,
  fsLoad = love.filesystem.load,
}

local channels = {}
local function channel(name)
  if channels[name] then return channels[name] end
  local ch = { q = {} }
  function ch:push(v) self.q[#self.q + 1] = v end
  function ch:pop() return table.remove(self.q, 1) end
  function ch:clear() self.q = {} end
  function ch:performAtomic(fn, ...) return fn(self, ...) end
  channels[name] = ch
  return ch
end

local started = {}
local threadStub = {
  getChannel = channel,
  newThread = function(path)
    local th = { path = path }
    function th:start(...)
      self.args = { ... }
      started[#started + 1] = self
    end
    function th:getError() return self.err end
    return th
  end,
}

local popens = {}
local popenAnswer = ""
io.popen = function(command)
  popens[#popens + 1] = command
  return {
    read = function() return popenAnswer end,
    close = function() return true end,
  }
end
love.mouse = nil

local function useOS(name)
  love.system.getOS = function() return name end
  Platform._resetForTests()
end

local function desktopImporter()
  local ri = setmetatable({
    android = false,
    workState = nil,
    tab = "red",
    ready = { red = true, blue = true },
    saveNotice = {},
    installs = {},
    browsers = 0,
  }, RomImporter)
  ri._installMod = function(self, path) self.installs[#self.installs + 1] = path end
  ri._openModBrowser = function(self) self.browsers = self.browsers + 1 return true end
  return ri
end

local function run()
  useOS("Windows")
  love.thread = threadStub
  HostPicker._reset()
  started, popens = {}, {}
  local ri = desktopImporter()
  ri:chooseMod()
  eq(#popens, 0, "Import mod .zip spawns no process on the main thread")
  eq(#started, 1, "one picker worker starts")
  check(ri._hostPick ~= nil, "the importer remembers the open picker")
  eq(#ri.installs, 0, "nothing is installed while the dialog is open")
  check(ri.modNotice and ri.modNotice.ok == true
      and tostring(ri.modNotice.text):find("file dialog", 1, true) ~= nil
      and tostring(ri.modNotice.text):find("taskbar", 1, true) == nil,
    "the Mods tab says the dialog is open without pointing at a missing taskbar button")
  eq(ri.tab, "mods", "the Mods tab stays in front")

  local th = started[1]
  eq(th and th.path, "src/core/host_picker_worker.lua", "the worker is the host picker")
  local commands = th and th.args[2] or {}
  eq(type(commands), "table", "the worker receives the command list")
  local command = commands[1] or ""
  check(command:find("powershell", 1, true) == 1, "the worker runs the PowerShell dialog")
  check(command:find("$o.TopMost=$true;", 1, true) ~= nil,
    "the dialog gets a TopMost owner form")
  check(command:find("ShowDialog($o)", 1, true) ~= nil,
    "the dialog is shown owned by that form")
  check(command:find("ShowDialog()", 1, true) == nil, "no ownerless ShowDialog")
  local body = command:match('%-Command "(.*)"$') or ""
  check(body ~= "" and body:find('"', 1, true) == nil,
    "the -Command body has no double quote to break the cmd wrapper")

  ri:chooseMod()
  eq(#started, 1, "a second click while the dialog is open starts nothing")
  local ran = 0
  ri:runActions({ { key = "rom-red", fn = function() ran = ran + 1 end } })
  eq(ran, 0, "launcher clicks are dropped while the dialog is open")
  ri:play("red", true)
  eq(ri._launchFade, nil, "Play does not start while the dialog is open")
  eq(#popens, 0, "no second dialog opens on the main thread")

  ri:_pumpHostPick()
  check(ri._hostPick ~= nil, "no answer yet: still waiting")

  channel(HostPicker.RESULT):push({ id = th.args[1],
    output = "C:/Temp/pokeport_mod_pick.zip" })
  ri:_pumpHostPick()
  eq(ri._hostPick, nil, "the answer clears the pending pick")
  eq(#ri.installs, 1, "the pick is installed once")
  eq(ri.installs[1], "C:/Temp/pokeport_mod_pick.zip", "with the path the worker returned")
  eq(#popens, 0, "and the main thread still spawned nothing")

  started = {}
  ri = desktopImporter()
  ri:chooseMod()
  channel(HostPicker.RESULT):push({ id = started[1].args[1] })
  ri:_pumpHostPick()
  eq(ri._hostPick, nil, "a cancelled dialog clears the pending pick")
  eq(#ri.installs, 0, "and installs nothing")
  eq(ri.browsers, 0, "and does not open the fallback browser over the cancel")
  eq(ri.modNotice, nil, "the waiting notice is cleared")

  started = {}
  ri = desktopImporter()
  ri:chooseMod()
  started[1].err = "boom"
  ri:_pumpHostPick()
  eq(ri._hostPick, nil, "a dead worker clears the pending pick")
  eq(ri.browsers, 1, "and falls back to the in-app browser")

  love.thread = nil
  HostPicker._reset()
  started, popens = {}, {}
  popenAnswer = "C:\\Temp\\pokeport_mod_pick.zip\r\n"
  ri = desktopImporter()
  ri:chooseMod()
  eq(#started, 0, "without threads no worker is started")
  eq(#popens, 1, "the picker runs synchronously instead")
  eq(ri.installs[1], "C:\\Temp\\pokeport_mod_pick.zip", "and its pick is installed")
  popenAnswer = ""

  love.thread = threadStub
  local savedLoaded = {}
  for _, m in ipairs({ "love.thread", "love.filesystem", "love.system" }) do
    savedLoaded[m] = package.loaded[m]
    package.loaded[m] = package.loaded[m] or true
  end
  love.filesystem.load = function(path) return loadfile(path) end
  popens = {}
  local answers = { "", "  /home/p/mod.zip\n" }
  io.popen = function(cmd)
    popens[#popens + 1] = cmd
    local a = answers[#popens] or ""
    return { read = function() return a end, close = function() return true end }
  end
  useOS("Linux")
  local worker = assert(loadfile("src/core/host_picker_worker.lua"))
  worker(42, { "zenity x", "kdialog y" }, "picker_test_chan")
  local msg = channel("picker_test_chan"):pop()
  check(msg ~= nil, "the worker posts one result")
  eq(msg and msg.id, 42, "tagged with its job id")
  eq(msg and msg.output, "/home/p/mod.zip", "the first non-empty answer, trimmed")
  eq(#popens, 2, "an empty first answer tries the next command")
  for m, v in pairs(savedLoaded) do package.loaded[m] = v end
  love.filesystem.load = saved.fsLoad

  for _, path in ipairs({ "src/import/RomImporter.lua", "src/core/FilePicker.lua",
      "tools/save-editor/SaveIO.lua" }) do
    local f = io.open(path, "rb")
    local src = f and f:read("*a") or ""
    if f then f:close() end
    check(src ~= "", path .. " is readable")
    check(src:find("ShowDialog()", 1, true) == nil,
      path .. " has no ownerless ShowDialog()")
    check(src:find("ShowDialog($o)", 1, true) ~= nil
        or src:find("HostPicker.WIN_SHOW", 1, true) ~= nil,
      path .. " shows its dialog owned by a TopMost form")
  end
  check(HostPicker.WIN_OPEN_DIALOG:find('"', 1, true) == nil
      and HostPicker.WIN_SHOW:find('"', 1, true) == nil,
    "the shared dialog prefix is double-quote free")
end

local function androidRun()
  useOS("Android")
  love.thread = nil
  local pickCalls = {}
  love.system.pickFile = function(kind)
    pickCalls[#pickCalls + 1] = kind or "rom"
    return true
  end
  love.system.pickFileKinds = function() return "rom,mod,sav" end
  local function androidImporter()
    local ri = setmetatable({
      android = true,
      workState = nil,
      tab = "mods",
      ready = { red = true, blue = true },
      saveNotice = {},
      installs = {},
    }, RomImporter)
    ri._installMod = function(self, source)
      self.installs[#self.installs + 1] = source
      self.modNotice = { ok = true, text = "Installed test" }
    end
    ri._refreshMods = function() end
    return ri
  end

  love.filesystem.write("foo.zip", "PK\0junk")
  local ri = androidImporter()
  ri:chooseMod()
  eq(#ri.installs, 0, "a stray .zip at the save root is not installed on tap")
  eq(#pickCalls, 1, "the tap opens the picker instead")
  eq(pickCalls[1], "mod", "asking for a mod archive")
  check(love.filesystem.getInfo("foo.zip") ~= nil, "the player's file is left alone")
  love.filesystem.remove("foo.zip")

  pickCalls = {}
  love.filesystem.write("picked_mod.zip", "PK\0saf")
  ri = androidImporter()
  ri:chooseMod()
  eq(ri.installs[1], "picked_mod.zip", "the SAF drop picked_mod.zip still installs on tap")
  eq(#pickCalls, 0, "without reopening the picker")
  check(love.filesystem.getInfo("picked_mod.zip") == nil, "and is retired")

  pickCalls = {}
  ri = androidImporter()
  ri:chooseMod()
  eq(#pickCalls, 1, "the picker is asked to open")
  for _ = 1, 200 do ri:_pumpModPickOpen(1 / 60) end
  eq(ri.modNotice, nil, "no notice before four seconds")
  for _ = 1, 60 do ri:_pumpModPickOpen(1 / 60) end
  check(ri.modNotice and ri.modNotice.ok == false,
    "four seconds with no focus loss reports the picker did not open")
  local text = ri.modNotice and tostring(ri.modNotice.text) or ""
  check(text:find("did not open", 1, true) ~= nil, "saying so")
  check(text:find(love.filesystem.getSaveDirectory() .. "/imports/mods/", 1, true) ~= nil,
    "and pointing at the imports/mods folder")
  local shown = ri.modNotice
  for _ = 1, 600 do ri:_pumpModPickOpen(1 / 60) end
  eq(ri.modNotice, shown, "the notice is shown once")

  love.filesystem.write("imports/mods/fix.zip", "PK\0inbox")
  pickCalls = {}
  local before = #ri.installs
  ri:chooseMod()
  eq(#pickCalls, 0, "after a stalled picker the next tap reads imports/mods")
  eq(#ri.installs, before, "the inbox install waits a frame")
  check(ri.modNotice and tostring(ri.modNotice.text):find("imports/mods", 1, true) ~= nil,
    "so the installing notice is drawn first")
  ri:chooseMod()
  eq(#pickCalls, 0, "a tap while the inbox install is queued opens nothing")
  ri:_pumpModInboxInstall()
  eq(#ri.installs, before, "still waiting on the frame the tap landed")
  ri:_pumpModInboxInstall()
  eq(ri.installs[#ri.installs], "imports/mods/fix.zip", "and installs the inbox copy")
  pickCalls = {}
  ri:chooseMod()
  eq(#pickCalls, 1, "the tap after that opens the picker again")
  love.filesystem.remove("imports/mods/fix.zip")

  ri = androidImporter()
  ri:chooseMod()
  for _ = 1, 30 do ri:_pumpModPickOpen(1 / 60) end
  ri:focus(false)
  for _ = 1, 600 do ri:_pumpModPickOpen(1 / 60) end
  eq(ri.modNotice, nil, "an opened picker (focus lost) never reports a failure")

  ri = androidImporter()
  ri:chooseMod()
  ri:_pumpModPickOpen(30)
  eq(ri.modNotice, nil, "one huge dt does not fire the notice")

  love.system.pickFile = function() return false end
  ri = androidImporter()
  ri:chooseMod()
  check(ri.modNotice and ri.modNotice.ok == false
      and tostring(ri.modNotice.text):find("/imports/mods/", 1, true) ~= nil,
    "a refused picker points at imports/mods")

  useOS("iOS")
  love.system.pickFile = function() return true end
  ri = androidImporter()
  ri:chooseMod()
  for _ = 1, 600 do ri:_pumpModPickOpen(1 / 60) end
  eq(ri.modNotice, nil, "iOS never reports a picker that did not open")
end

local ok, err = pcall(run)
if not ok then check(false, "desktop suite raised: " .. tostring(err)) end
ok, err = pcall(androidRun)
if not ok then check(false, "android suite raised: " .. tostring(err)) end

love.system.getOS = saved.getOS
love.system.pickFile = saved.pickFile
love.system.pickFileKinds = saved.pickFileKinds
love.thread = saved.thread
love.mouse = saved.mouse
io.popen = saved.popen
love.filesystem.load = saved.fsLoad
Platform._resetForTests()
HostPicker._reset()
love.filesystem.remove("foo.zip")
love.filesystem.remove("picked_mod.zip")
love.filesystem.remove("imports/mods/fix.zip")

S.finish()
