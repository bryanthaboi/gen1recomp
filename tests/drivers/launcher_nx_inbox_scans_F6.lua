return function()
  local U = dofile("tests/drivers/util.lua")
  local RomImporter = require("src.import.RomImporter")
  local Platform = require("src.core.Platform")
  local fs = love.filesystem
  local MiB = 1024 * 1024

  local failed = false
  local function expect(ok, label, detail)
    U.log((ok and "PASS " or "FAIL ") .. label .. (detail and ("  " .. tostring(detail)) or ""))
    if not ok then failed = true end
  end

  local romFiles = { "imports/f6_a.gba", "imports/f6_b.gba", "imports/f6_c.gba" }
  local savFiles = {}
  fs.createDirectory("imports")
  fs.createDirectory("imports/saves")
  fs.createDirectory("imports/saves/red")
  for i, path in ipairs(romFiles) do
    fs.write(path, string.char(0x40 + i):rep(16 * MiB))
  end
  for i = 1, 24 do
    local path = ("imports/saves/red/f6_%02d.sav"):format(i)
    savFiles[#savFiles + 1] = path
    fs.write(path, string.char(0x40 + i):rep(32768))
  end

  local realIsNX, realTransfer = Platform.isNX, Platform.inboxTransfer
  Platform.isNX = function() return true end
  Platform.inboxTransfer = function() return "mtp" end

  local importer = RomImporter.new(function() end, { launcher = true })
  importer.isNX, importer.inboxImport, importer.tab = true, true, "red"

  local function run(label, start)
    local t0 = love.timer.getTime()
    start()
    local press = love.timer.getTime() - t0
    local worst, frames = press, 1
    while importer._inboxJob and importer._pumpInboxJob do
      U.wait(1)
      local f0 = love.timer.getTime()
      importer:_pumpInboxJob()
      worst = math.max(worst, love.timer.getTime() - f0)
      frames = frames + 1
    end
    U.log(string.format("TIME %-12s press=%.1fms frames=%d worst_frame=%.1fms",
      label, press * 1000, frames, worst * 1000))
    return press, worst, frames
  end

  U.wait(2)
  local probe = string.char(0x50):rep(16 * MiB)
  local h0 = love.timer.getTime()
  love.data.hash("sha1", table.concat({ probe }))
  local hashUnit = love.timer.getTime() - h0
  probe = nil
  collectgarbage("collect")
  local limit = 0.02 + 1.5 * hashUnit
  U.log(string.format("TIME one 16 MiB concat+sha1 = %.1fms, frame limit %.1fms",
    hashUnit * 1000, limit * 1000))
  local romPress, romWorst, romFrames = run("rom scan", function() importer:rescanAction("red") end)
  expect(romPress < limit, "rom_scan_press_under_one_dump_hash", string.format("%.1fms", romPress * 1000))
  expect(romWorst < limit, "rom_scan_frames_under_one_dump_hash", string.format("%.1fms", romWorst * 1000))
  expect(romFrames > 3, "rom_scan_spans_frames", romFrames)
  expect(importer.workState == "error" and tostring(importer.detail):find("Unsupported ROM", 1, true) ~= nil,
    "rom_scan_rejects_unknown_dump", importer.detail)
  importer.workState, importer.detail, importer.notice = nil, nil, nil

  local savPress, savWorst, savFrames = run("save scan", function() importer:chooseSaveImport("red") end)
  expect(savPress < 0.05, "save_scan_press_under_50ms", string.format("%.1fms", savPress * 1000))
  expect(savWorst < 0.05, "save_scan_frames_under_50ms", string.format("%.1fms", savWorst * 1000))
  expect(savFrames > 2, "save_scan_spans_frames", savFrames)
  local notice = importer.saveNotice and importer.saveNotice.red
  expect(notice ~= nil and not tostring(notice.text):find("Importing", 1, true),
    "save_scan_reports_result", notice and notice.text)

  for _, path in ipairs(romFiles) do fs.remove(path) end
  for _, path in ipairs(savFiles) do
    fs.remove(path)
    fs.remove(path .. ".imported")
  end
  fs.remove("imports/.scanned")
  Platform.isNX, Platform.inboxTransfer = realIsNX, realTransfer
  love.event.quit(failed and 1 or 0)
end
