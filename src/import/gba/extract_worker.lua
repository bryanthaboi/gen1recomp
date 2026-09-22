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

local task_name, prefix, romData, sha1, ch_name = ...

local ch = love and love.thread and love.thread.getChannel and love.thread.getChannel(ch_name)

local ok, err = pcall(function()
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

  local res, detail
  if task_name == "gba" then
    res, detail = ext:runGbaExtract(sha1)
  elseif task_name == "pokemon" then
    res, detail = ext:runPokemonExtract(sha1)
  elseif task_name == "aux" then
    res, detail = ext:runAuxExtracts(sha1)
  elseif task_name == "intro_audio" then
    res, detail = ext:runIntroAudio(sha1)
  else
    error("unknown extract task: " .. tostring(task_name))
  end

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
