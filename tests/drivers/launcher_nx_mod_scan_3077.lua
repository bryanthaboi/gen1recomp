return function()
  local U = dofile("tests/drivers/util.lua")
  local RomImporter = require("src.import.RomImporter")
  local Platform = require("src.core.Platform")
  local fs = love.filesystem
  local writeDelay = (tonumber(os.getenv("POKEPORT_3077_WRITE_MS")) or 1) / 1000
  local bit = require("bit")

  local crcTable = {}
  for i = 0, 255 do
    local c = i
    for _ = 1, 8 do
      if bit.band(c, 1) == 1 then c = bit.bxor(0xEDB88320, bit.rshift(c, 1)) else c = bit.rshift(c, 1) end
    end
    crcTable[i] = c
  end
  local function crc32(s)
    local c = 0xFFFFFFFF
    for i = 1, #s do
      c = bit.bxor(crcTable[bit.band(bit.bxor(c, s:byte(i)), 0xFF)], bit.rshift(c, 8))
    end
    c = bit.bnot(c)
    if c < 0 then c = c + 0x100000000 end
    return c
  end
  local function u16(n) return string.char(n % 256, math.floor(n / 256) % 256) end
  local function u32(n)
    return string.char(n % 256, math.floor(n / 256) % 256,
      math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
  end
  local function storedZip(entries)
    local out, central, offset = {}, {}, 0
    for _, e in ipairs(entries) do
      local crc, size = crc32(e[2]), #e[2]
      local head = u32(0x04034b50) .. u16(20) .. u16(0) .. u16(0) .. u16(0) .. u16(0x21)
        .. u32(crc) .. u32(size) .. u32(size) .. u16(#e[1]) .. u16(0) .. e[1]
      out[#out + 1] = head
      out[#out + 1] = e[2]
      central[#central + 1] = u32(0x02014b50) .. u16(20) .. u16(20) .. u16(0) .. u16(0)
        .. u16(0) .. u16(0x21) .. u32(crc) .. u32(size) .. u32(size) .. u16(#e[1])
        .. u16(0) .. u16(0) .. u16(0) .. u16(0) .. u32(0) .. u32(offset) .. e[1]
      offset = offset + #head + size
    end
    local cd = table.concat(central)
    out[#out + 1] = cd
    out[#out + 1] = u32(0x06054b50) .. u16(0) .. u16(0) .. u16(#entries) .. u16(#entries)
      .. u32(#cd) .. u32(offset) .. u16(0)
    return table.concat(out)
  end
  local function modZip(id, n)
    local entries = {
      { id .. "/manifest.json", ('{"id":"%s","name":"%s","version":"1.0.0","entry":"main.lua"}'):format(id, id) },
      { id .. "/main.lua", "return function() end\n" },
    }
    for i = 1, n do
      entries[#entries + 1] = { ("%s/assets/%02d/f%04d.bin"):format(id, i % 40, i),
        (("%04d"):format(i)):rep(256) }
    end
    return storedZip(entries)
  end
  fs.createDirectory("imports/mods")
  fs.remove("imports/mods/.installed")
  fs.remove("mods/small_mod_3077/manifest.json")
  fs.remove("mods/big_mod_3077/manifest.json")
  fs.write("imports/mods/small_mod.zip", modZip("small_mod_3077", 1))
  fs.write("imports/mods/big_mod.zip", modZip("big_mod_3077", 3000))

  local zipReads = 0
  local origRead, origWrite, origNewFile = fs.read, fs.write, fs.newFile
  fs.read = function(name, ...)
    if type(name) == "string" and name:lower():match("%.zip$") then zipReads = zipReads + 1 end
    return origRead(name, ...)
  end
  fs.newFile = function(name, ...)
    if type(name) == "string" and name:lower():match("%.zip$") then zipReads = zipReads + 1 end
    return origNewFile(name, ...)
  end
  fs.write = function(...)
    if writeDelay > 0 then love.timer.sleep(writeDelay) end
    return origWrite(...)
  end

  local realIsNX, realTransfer = Platform.isNX, Platform.inboxTransfer
  Platform.isNX = function() return true end
  Platform.inboxTransfer = function() return "mtp" end

  local importer = RomImporter.new(function() end, { launcher = true })
  importer.isNX, importer.inboxImport, importer.tab = true, true, "mods"

  local failed = false
  local function expect(ok, label, detail)
    U.log((ok and "PASS " or "FAIL ") .. label .. (detail and ("  " .. tostring(detail)) or ""))
    if not ok then failed = true end
  end

  local function scan(label)
    zipReads = 0
    local t0 = love.timer.getTime()
    importer:chooseMod()
    local press = love.timer.getTime() - t0
    local worst = press
    local frames = 1
    while importer._inboxJob and importer._pumpInboxJob do
      U.wait(1)
      local f0 = love.timer.getTime()
      local job = importer._inboxJob
      local before = job and job.install and job.install.progress and job.install.progress.done
      local idx = job and job.index
      importer:_pumpInboxJob()
      local dt = love.timer.getTime() - f0
      if dt > 0.02 then
        local after = job and job.install and job.install.progress and job.install.progress.done
        U.log(string.format("SLOW frame=%d %.1fms idx=%s progress %s -> %s", frames, dt * 1000, tostring(idx), tostring(before), tostring(after)))
      end
      worst = math.max(worst, dt)
      frames = frames + 1
    end
    U.log(string.format("TIME %-30s press=%.1fms frames=%d worst_frame=%.1fms zip_reads=%d notice=%s",
      label, press * 1000, frames, worst * 1000, zipReads,
      (importer.modNotice and importer.modNotice.text or "nil"):gsub("\n", " | ")))
    return worst, zipReads
  end

  U.wait(2)
  local inbox = fs.getDirectoryItems("imports/mods") or {}
  expect(#inbox >= 2, "inbox_has_test_zips", #inbox)

  local w1 = scan("first scan (small + big)")
  expect(fs.getInfo("mods/big_mod_3077/manifest.json") ~= nil, "big_mod_installed")
  expect(fs.getInfo("mods/small_mod_3077/manifest.json") ~= nil, "small_mod_installed")
  expect(w1 < 0.05, "first_scan_frames_under_50ms", string.format("%.1fms", w1 * 1000))

  local w2, r2 = scan("second scan (both installed)")
  expect(r2 == 0, "second_scan_reads_no_zip", r2)
  expect(w2 < 0.05, "second_scan_under_50ms", string.format("%.1fms", w2 * 1000))

  fs.remove("mods/big_mod_3077/manifest.json")
  local w3 = scan("big partial (no manifest)")
  expect(fs.getInfo("mods/big_mod_3077/manifest.json") ~= nil, "partial_tree_reinstalled")
  expect(w3 < 0.05, "partial_rescan_frames_under_50ms", string.format("%.1fms", w3 * 1000))

  Platform.isNX, Platform.inboxTransfer = realIsNX, realTransfer
  fs.read, fs.write, fs.newFile = origRead, origWrite, origNewFile
  love.event.quit(failed and 1 or 0)
end
