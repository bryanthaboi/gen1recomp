local function identities()
  local ids = { "g1r-yellow", "pokeport-test-caches" }
  local own = os.getenv("POKEPORT_IDENTITY")
  if own and own ~= "" then table.insert(ids, 1, own) end
  return ids
end

return function(name)
  local home = os.getenv("HOME")
  if not home or home == "" then return nil end
  for _, base in ipairs({ home .. "/Library/Application Support/LOVE", home .. "/.local/share/love" }) do
    for _, id in ipairs(identities()) do
      local root = base .. "/" .. id .. "/yellow/"
      local chunk = loadfile(root .. "data/generated/" .. (name or "field") .. ".lua")
      if chunk then
        local ok, mod = pcall(chunk)
        if ok and type(mod) == "table" and (name or mod.pikachu) then return mod, root end
      end
    end
  end
  return nil
end
