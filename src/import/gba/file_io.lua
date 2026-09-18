-- File-backed mod.imports / mod.cache shim for offline extract (dev CLI).

local FileIO = {}

function FileIO.makeImports(path, md5, id)
  id = id or "firered"
  local f = assert(io.open(path, "rb"))
  local size = f:seek("end")
  f:seek("set", 0)
  local imports = {}
  function imports:info(want)
    if want ~= id then return nil, "undeclared" end
    return { id = id, size = size, md5 = md5, file = path }
  end
  function imports:read(want, offset, length)
    if want ~= id then return nil, "undeclared" end
    f:seek("set", offset)
    local data = f:read(length)
    if not data or #data ~= length then return nil, "short read" end
    return data
  end
  function imports:_close()
    f:close()
  end
  return imports
end

function FileIO.makeCache(root)
  local lfs_ok, lfs = pcall(require, "lfs")
  local function mkdir_p(dir)
    if lfs_ok then
      local path = dir:sub(1, 1) == "/" and "" or nil
      for part in dir:gmatch("[^/]+") do
        path = path and (path .. "/" .. part) or part
        lfs.mkdir(path)
      end
    else
      os.execute("mkdir -p '" .. dir:gsub("'", "'\\''") .. "'")
    end
  end
  mkdir_p(root)
  local cache = {}
  function cache:write(rel, bytes)
    local path = root .. "/" .. rel
    local parent = path:match("^(.*)/[^/]+$")
    if parent then mkdir_p(parent) end
    local f = assert(io.open(path, "wb"))
    f:write(bytes)
    f:close()
    return true
  end
  function cache:read(rel)
    local f = io.open(root .. "/" .. rel, "rb")
    if not f then return nil end
    local d = f:read("*a")
    f:close()
    return d
  end
  function cache:exists(rel)
    local f = io.open(root .. "/" .. rel, "rb")
    if f then f:close() return true end
    return false
  end
  function cache:info(rel)
    if self:exists(rel) then return { type = "file" } end
    return nil
  end
  return cache
end

return FileIO
