local MODULES = { "g3_ghost", "g3_e3a", "g3_e3b", "g3_e3c", "g3_dark", "g3_psychic" }

local out = {}
for _, name in ipairs(MODULES) do
  local ok, mod = pcall(require, "src.core.game3.battle.anim_port." .. name)
  if ok and type(mod) == "table" and mod.callbacks then
    for k, fn in pairs(mod.callbacks) do out[k] = fn end
  elseif not ok and not tostring(mod):find("module '[^']*' not found") then
    print("[battle.anim] " .. name .. ": " .. tostring(mod))
  end
end
return out
