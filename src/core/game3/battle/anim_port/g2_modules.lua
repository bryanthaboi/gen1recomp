local P = require("src.core.game3.battle.anim_port.g2_pret")

local NAMES = { "g2_dragon", "g2_fight", "g2_fire", "g2_flying", "g2_effects2a", "g2_effects2b", "g2_effects2c" }

local M = { cb = {}, tasks = {} }

for _, n in ipairs(NAMES) do
  local ok, mod = pcall(require, "src.core.game3.battle.anim_port." .. n)
  if ok and type(mod) == "table" then
    for k, fn in pairs(mod.cb or {}) do
      P.CB[k] = fn
      M.cb[k] = P.cb(fn)
    end
    for k, fn in pairs(mod.tasks or {}) do
      M.tasks[k] = fn
    end
  elseif not ok and not tostring(mod):find("not found") then
    print("[battle.anim] " .. n .. ": " .. tostring(mod))
  end
end

return M
