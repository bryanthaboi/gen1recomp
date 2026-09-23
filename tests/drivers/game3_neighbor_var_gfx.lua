local U = require("tests.drivers.util")

local failed = false
local function check(label, cond, detail)
  print((cond and "PASS " or "FAIL ") .. label .. (detail and (" " .. detail) or ""))
  if not cond then failed = true end
end

local function shotPath(name)
  local dir = os.getenv("POKEPORT_SHOT_DIR")
  if not dir or dir == "" then return nil end
  return dir .. "/" .. name
end

local function ghost(mapId, lid)
  local Ghosts = require("src.core.game3.ghosts")
  local pool = Ghosts._pools[mapId]
  return pool and pool.byId[lid]
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)
  local Map = require("src.core.game3.map")
  local ok, err = pcall(function()
    love.window.setMode(700, 1300, { resizable = true })
    U.wait(10)
    Map.load(nil, game, "FR_ROUTE_2", { x = 9, y = 79, facing = "down" })
    U.wait(60)
    local eo = ghost("FR_VIRIDIAN_CITY", 4)
    check("viridian_old_man_ghost", eo ~= nil)
    if eo then
      check("viridian_old_man_lying_gfx", eo.graphicsId == 34, "gid=" .. tostring(eo.graphicsId))
      check("viridian_old_man_moved", eo.cellX == 21 and eo.cellY == 11,
        tostring(eo.cellX) .. "," .. tostring(eo.cellY))
      check("viridian_old_man_drawn", not eo.invisible)
    end
    local p = shotPath("gfxv_route2_viridian_old_man.png")
    if p then U.shot(game, p) end
    U.wait(10)

    love.window.setMode(1700, 800, { resizable = true })
    U.wait(10)
    Map.load(nil, game, "FR_ROUTE_18", { x = 60, y = 0, facing = "right" })
    U.wait(60)
    local st
    local pool = require("src.core.game3.ghosts")._pools["FR_FUCHSIA_CITY"]
    for _, lid in ipairs(pool and pool.order or {}) do
      local o = pool.byId[lid]
      local raw = tonumber(o.def and (o.def.graphicsId or o.def.graphics))
      if raw and raw >= 240 then st = o end
    end
    check("fuchsia_statue_ghost", st ~= nil)
    if st then
      check("fuchsia_statue_kabuto_gfx", st.graphicsId == 147, "gid=" .. tostring(st.graphicsId))
      check("fuchsia_statue_drawn", not st.invisible)
    end
    p = shotPath("gfxv_route18_fuchsia_kabuto.png")
    if p then U.shot(game, p) end
    U.wait(10)
  end)
  if not ok then check("driver_error", false, tostring(err)) end
  love.event.quit(failed and 1 or 0)
end
