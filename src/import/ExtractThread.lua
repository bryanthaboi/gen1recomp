-- ROM extraction, off the main thread.  The extractor's require closure needs
-- only love.filesystem, love.image, love.math and love.system, none of which
-- are main-thread-only, so it runs here instead of as a coroutine the frame
-- loop resumed for 8ms out of every 16.7ms.
--
-- The caller clears the stale cache and writes the completion marker itself;
-- this only fills the tree between those two steps, so the "marker appears
-- last" order isReady() depends on stays on one thread.

require("love.filesystem")
require("love.image")
require("love.math")
require("love.system")
require("love.timer")

local version, prefix, romData, progressName, resultName = ...

local progressChannel = love.thread.getChannel(progressName)
local resultChannel = love.thread.getChannel(resultName)

-- RomExtractor:tick fires per item, thousands of times per import; a channel
-- push each would cost more than the work it reports.
local PROGRESS_HZ = 20

local ok, err = pcall(function()
  local CacheFs = require("src.import.CacheFs")
  CacheFs.prefix = prefix

  local manifest = require("src.import.RomManifest").decode(version)
  local RomExtractor =
    require("src.core.GameVersion").generation(version) == 2
    and require("src.import.RomExtractorGen2")
    or require("src.import.RomExtractor")

  local lastPush, lastStage = 0, nil
  local extractor = RomExtractor.new(romData, manifest,
    function(progress, total, stage, current, stageTotal)
      local now = love.timer.getTime()
      -- Stage changes always go through, or the caption goes stale.
      if stage ~= lastStage or now - lastPush >= 1 / PROGRESS_HZ then
        lastPush, lastStage = now, stage
        progressChannel:push({
          progress = progress, total = total, stage = stage,
          current = current, stageTotal = stageTotal,
        })
      end
    end)
  extractor:run()
end)

resultChannel:push({ ok = ok, error = ok and nil or tostring(err) })
