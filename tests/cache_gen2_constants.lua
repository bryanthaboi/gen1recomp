local M = {}

function M.root(version)
  local home = os.getenv("HOME") or ""
  local bases = { home .. "/Library/Application Support/LOVE", home .. "/.local/share/love" }
  local ids = { os.getenv("POKEPORT_IDENTITY") or "", "g1r-" .. version, "pokeport-test-caches" }
  for _, base in ipairs(bases) do
    for _, id in ipairs(ids) do
      if id ~= "" then
        local root = base .. "/" .. id .. "/" .. version
        local f = io.open(root .. "/data/generated/constants.lua", "r")
        if f then
          f:close()
          return root
        end
      end
    end
  end
  return nil
end

function M.load(version)
  local root = M.root(version)
  if not root then return nil end
  local chunk = loadfile(root .. "/data/generated/constants.lua")
  local ok, constants = pcall(chunk or error)
  if ok and type(constants) == "table" then return constants, root end
  return nil
end

return M
