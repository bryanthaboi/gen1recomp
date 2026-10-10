-- Background love.thread worker for parallel Gen 3 extraction stages.
-- Cross-platform: sets up love.filesystem searcher so NX, UWP, Android, iOS,
-- and Desktop fused packages reliably resolve required modules.

pcall(require, "love.filesystem")
pcall(require, "love.image")
pcall(require, "love.math")
pcall(require, "love.system")
pcall(require, "love.timer")
pcall(require, "love.data")

-- Ensure fresh thread Lua state resolves "src.*" via love.filesystem on all platforms:
table.insert(package.searchers or package.loaders, 1, function(modname)
  local path = modname:gsub("%.", "/") .. ".lua"
  if love and love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo(path) then
    return assert(love.filesystem.load(path))
  end
  local initPath = modname:gsub("%.", "/") .. "/init.lua"
  if love and love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo(initPath) then
    return assert(love.filesystem.load(initPath))
  end
end)

require("src.import.ImportGc").tune()

local task_name, prefix, romData, sha1, ch_name = ...

local ch = love and love.thread and love.thread.getChannel and love.thread.getChannel(ch_name)

local ok, err = pcall(function()
  local GameVersion = require("src.core.GameVersion")
  local version = GameVersion.forSha1(sha1)
  assert(version and GameVersion.generation(version) == 3, "unknown gen 3 ROM sha1 " .. tostring(sha1))
  GameVersion.set(version)
  local CacheFs = require("src.import.CacheFs")
  CacheFs.prefix = prefix or ""

  local RomExtractorGen3 = require("src.import.RomExtractorGen3")
  local ext = RomExtractorGen3.new(romData, nil, function(progress, total, stage, current, stageTotal)
    if ch then
      local frac = (progress or 0) / math.max(total or 1000, 1)
      ch:push({
        type = "progress",
        task = task_name,
        fraction = frac,
        stage = stage,
        current = current,
        stageTotal = stageTotal,
      })
    end
  end, sha1)

  local t0 = (love and love.timer and love.timer.getTime()) or os.clock()
  local res, detail = ext:runTask(task_name, sha1)

  local dt = ((love and love.timer and love.timer.getTime()) or os.clock()) - t0
  print(string.format("[worker %s] completed in %.3fs (res=%s)", task_name, dt, tostring(res)))

  assert(res ~= false, detail or (task_name .. " extraction failed"))
  collectgarbage("collect")
  return res
end)

if ch then
  ch:push({
    type = "done",
    task = task_name,
    ok = ok,
    error = (not ok) and tostring(err) or nil,
  })
end
