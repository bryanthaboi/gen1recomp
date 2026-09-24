local WorkerFs = {}

function WorkerFs.normalize(prefix)
  if type(prefix) == "string" and prefix ~= "" then return prefix end
  return nil
end

function WorkerFs.prefix()
  if not require("src.core.Platform").isNX() then return nil end
  return WorkerFs.normalize(require("src.core.GameVersion").cachePrefix())
end

function WorkerFs.read(prefix, rel, fs)
  fs = fs or love.filesystem
  prefix = WorkerFs.normalize(prefix)
  if prefix then
    local bytes = fs.read(prefix .. rel)
    if bytes then return bytes end
  end
  return fs.read(rel)
end

function WorkerFs.cache(prefix, fs)
  local cache = { prefix = WorkerFs.normalize(prefix) }
  function cache:setPrefix(p)
    self.prefix = WorkerFs.normalize(p)
  end
  function cache:read(rel)
    return WorkerFs.read(self.prefix, rel, fs)
  end
  return cache
end

return WorkerFs
