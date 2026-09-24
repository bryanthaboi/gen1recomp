local Cache = require("tests.game3_cache")

local M = {}

local function readable(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

local function current(root)
  local f = io.open(root .. "/meta.json", "rb")
  if not f then return false end
  local src = f:read("*a") or ""
  f:close()
  local v = tonumber(src:match('"cache_version"%s*:%s*(%d+)'))
  return v == require("src.import.gba.versions").CACHE_VERSION
end

local function leafgreenRoot()
  local home, identity = os.getenv("HOME"), os.getenv("POKEPORT_IDENTITY")
  if not (home and identity and identity ~= "") then return nil end
  for _, base in ipairs({ home .. "/Library/Application Support/LOVE", home .. "/.local/share/love" }) do
    local root = base .. "/" .. identity .. "/leafgreen/data/generated/gba"
    if readable(root .. "/meta.json") and current(root) then return root end
  end
  return nil
end

function M.mountOrSkip(label)
  local root = Cache.mount()
  if root then
    print("[info] FireRed cache at " .. root)
    return "firered", root
  end
  root = leafgreenRoot()
  if not root then
    print("[skip] " .. tostring(label) .. ": " .. tostring(Cache.reason or "no imported FireRed/LeafGreen cache found"))
    os.exit(0)
  end
  local Dataset = require("src.core.game3.dataset")
  Dataset.cacheRootOverride = root
  Dataset.mountExtractRoots()
  print("[info] LeafGreen cache at " .. root)
  return "leafgreen", root
end

return M
