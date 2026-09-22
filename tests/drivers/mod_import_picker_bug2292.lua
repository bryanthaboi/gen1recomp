return function(game)
  local U = dofile("tests/drivers/util.lua")
  local RomImporter = require("src.import.RomImporter")
  local HostPicker = require("src.core.HostPicker")
  local Platform = require("src.core.Platform")

  local dir = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR")
    or "/tmp/modpicker2292"
  os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')
  love.window.setMode(1024, 768, { resizable = true, highdpi = true })
  U.wait(2)

  local failed = false
  local function expect(cond, label, why)
    if cond then
      print("PASS " .. label)
    else
      failed = true
      print("FAIL " .. label .. (why and (": " .. tostring(why)) or ""))
    end
  end

  local MOD_ID = "picker_probe_2292"
  local zipPath = dir .. "/" .. MOD_ID .. ".zip"
  local stage = dir .. "/" .. MOD_ID
  os.remove(zipPath)
  os.execute('rm -rf "' .. stage .. '" && mkdir -p "' .. stage .. '"')
  local mf = io.open(stage .. "/manifest.json", "wb")
  if mf then
    mf:write('{"id":"' .. MOD_ID .. '","name":"Picker Probe","version":"1.0.0",'
      .. '"entry":"main.lua","category":"GAMEPLAY","games":["gen1"],'
      .. '"description":"Installed through the async mod picker."}')
    mf:close()
  end
  local ml = io.open(stage .. "/main.lua", "wb")
  if ml then ml:write("return {}\n") ml:close() end
  os.execute('cd "' .. stage .. '" && zip -qr "' .. zipPath .. '" . 2>/dev/null')
  os.execute('rm -rf "' .. stage .. '"')
  local zf = io.open(zipPath, "rb")
  expect(zf ~= nil, "fixture_zip_built", zipPath)
  if zf then zf:close() end

  local realGetOS = love.system.getOS
  local realStart = HostPicker.start
  local realPickFile = love.system.pickFile
  local starts, captured = 0, {}
  local fakeCommand = nil
  HostPicker.start = function(commands)
    starts = starts + 1
    captured = commands
    return realStart({ fakeCommand })
  end

  local function newLauncher()
    local imp = RomImporter.new(function() end, { launcher = true })
    imp.safeMode = false
    imp._refreshFindSources = function(self) self.findSources = {} end
    imp._refreshFind = function() end
    imp._pumpFindFetch = function() end
    imp._findFetch = nil
    imp.findLoaded = true
    imp.findIndex = { mods = {}, carts = {} }
    imp:_switchTab("mods")
    return imp
  end

  local imp
  local frames = 0
  local pending = nil
  love.draw = function()
    if imp then imp:draw() end
    if pending then
      local path = pending
      pending = nil
      love.graphics.captureScreenshot(function(imagedata)
        local f = io.open(path, "wb")
        if f then f:write(imagedata:encode("png"):getString()) f:close() end
      end)
    end
  end
  local function step(n)
    for _ = 1, n do
      if imp then imp:update(1 / 60) end
      frames = frames + 1
      coroutine.yield()
    end
  end
  local function shot(name)
    pending = dir .. "/" .. name
    for _ = 1, 30 do
      if not pending then break end
      step(1)
    end
    step(2)
    local f = io.open(dir .. "/" .. name, "rb")
    U.log(f and "shot" or "FAIL shot", name)
    if f then f:close() end
  end
  local function clickImportAsWindows()
    love.system.getOS = function() return "Windows" end
    Platform._resetForTests()
    local t0 = love.timer.getTime()
    imp:chooseMod()
    local spent = love.timer.getTime() - t0
    love.system.getOS = realGetOS
    Platform._resetForTests()
    return spent
  end

  imp = newLauncher()
  step(20)

  fakeCommand = "sleep 3; printf '%s' '" .. zipPath .. "'"
  local spent = clickImportAsWindows()
  expect(spent < 0.5, "click_returns_immediately", ("%.3fs"):format(spent))
  expect(imp._hostPick ~= nil, "picker_pending_same_frame")
  expect(starts == 1, "one_worker_started", starts)
  local cmd = captured and captured[1] or ""
  expect(cmd:find("$o.TopMost=$true;", 1, true) ~= nil
    and cmd:find("ShowDialog($o)", 1, true) ~= nil, "windows_dialog_owned_topmost")
  local before = frames
  step(30)
  clickImportAsWindows()
  expect(starts == 1, "second_click_ignored_while_open", starts)
  shot("2292_01_waiting_for_picker.png")
  expect(imp._hostPick ~= nil and frames - before >= 30,
    "launcher_keeps_running_while_dialog_open", frames - before)
  expect(imp.modNotice and tostring(imp.modNotice.text):find("file dialog", 1, true) ~= nil
    and tostring(imp.modNotice.text):find("taskbar", 1, true) == nil,
    "waiting_notice_shown", imp.modNotice and imp.modNotice.text)
  local clicked = 0
  imp:runActions({ { key = "play-red", fn = function() clicked = clicked + 1 end } })
  expect(clicked == 0, "launcher_clicks_blocked_while_open", clicked)
  imp:play("red", true)
  expect(imp._launchFade == nil, "play_blocked_while_open")
  for _ = 1, 600 do
    if not imp._hostPick then break end
    step(1)
  end
  expect(imp._hostPick == nil, "pick_answer_consumed")
  expect(frames - before >= 150, "frames_advanced_through_dialog", frames - before)
  expect(imp.modNotice and imp.modNotice.ok == true
    and tostring(imp.modNotice.text):find("Installed", 1, true) ~= nil,
    "picked_mod_installed", imp.modNotice and imp.modNotice.text)
  local listed = false
  for _, row in ipairs(imp.mods or {}) do
    if row.id == MOD_ID then listed = true end
  end
  expect(listed, "mod_in_list")
  step(20)
  shot("2292_02_mod_installed_from_picker.png")

  fakeCommand = "sleep 1"
  clickImportAsWindows()
  expect(imp._hostPick ~= nil, "cancel_run_pending")
  for _ = 1, 300 do
    if not imp._hostPick then break end
    step(1)
  end
  expect(imp._hostPick == nil and imp.modNotice == nil, "cancel_clears_picker")
  step(10)
  shot("2292_03_cancel_back_to_mods.png")

  pcall(function() require("src.mods.LauncherMods").uninstall(MOD_ID) end)

  love.filesystem.write("stray_2292.zip", "PK\3\4 not a mod")
  imp = newLauncher()
  imp.android = true
  local pickCalls = 0
  love.system.pickFile = function() pickCalls = pickCalls + 1 return true end
  love.system.getOS = function() return "Android" end
  imp:chooseMod()
  love.system.getOS = realGetOS
  expect(pickCalls == 1, "android_stray_zip_not_installed_picker_opened", pickCalls)
  expect(love.filesystem.getInfo("stray_2292.zip") ~= nil, "android_stray_zip_left_alone")
  step(200)
  expect(imp.modNotice == nil, "android_no_notice_before_4s")
  step(60)
  expect(imp.modNotice and imp.modNotice.ok == false
    and tostring(imp.modNotice.text):find("did not open", 1, true) ~= nil
    and tostring(imp.modNotice.text):find("imports/mods", 1, true) ~= nil,
    "android_picker_did_not_open_notice", imp.modNotice and imp.modNotice.text)
  step(10)
  shot("2292_04_android_picker_did_not_open.png")

  love.filesystem.createDirectory("imports/mods")
  local inboxZip = "imports/mods/" .. MOD_ID .. ".zip"
  local zr = io.open(zipPath, "rb")
  local bytes = zr and zr:read("*a") or ""
  if zr then zr:close() end
  love.filesystem.write(inboxZip, bytes)
  pickCalls = 0
  love.system.getOS = function() return "Android" end
  imp:chooseMod()
  love.system.getOS = realGetOS
  expect(pickCalls == 0 and imp._modInboxInstall ~= nil, "android_inbox_install_queued", pickCalls)
  expect(imp.modNotice and tostring(imp.modNotice.text):find("Installing", 1, true) ~= nil,
    "android_inbox_notice_before_install", imp.modNotice and imp.modNotice.text)
  pending = dir .. "/2292_05_android_installing_from_inbox.png"
  step(1)
  local f5 = io.open(dir .. "/2292_05_android_installing_from_inbox.png", "rb")
  U.log(f5 and "shot" or "FAIL shot", "2292_05_android_installing_from_inbox.png")
  if f5 then f5:close() end
  step(3)
  local inboxListed = false
  for _, row in ipairs(imp.mods or {}) do
    if row.id == MOD_ID then inboxListed = true end
  end
  expect(imp._modInboxInstall == nil and inboxListed, "android_inbox_installed_next_frame",
    imp.modNotice and imp.modNotice.text)
  love.filesystem.remove(inboxZip)
  pcall(function() require("src.mods.LauncherMods").uninstall(MOD_ID) end)

  love.filesystem.remove("stray_2292.zip")
  love.system.pickFile = realPickFile
  HostPicker.start = realStart
  imp = nil
  os.remove(zipPath)
  U.log("done")
  love.event.quit(failed and 1 or 0)
end
