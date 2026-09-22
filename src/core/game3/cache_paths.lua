local CachePaths = {}

CachePaths.CACHE_ROOT = "data/generated/gba"
CachePaths.NATIVE_ROOT = "data/generated/gba/native"

function CachePaths.setRoot(root)
  if type(root) ~= "string" or root == "" then return false end
  CachePaths.CACHE_ROOT = root
  CachePaths.NATIVE_ROOT = root .. "/native"
  return true
end

function CachePaths.reset()
  CachePaths.CACHE_ROOT = "data/generated/gba"
  CachePaths.NATIVE_ROOT = "data/generated/gba/native"
end

return CachePaths
