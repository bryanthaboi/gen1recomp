local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_cut_grass_2470"
local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end
local function finish()
  result(failures == 0, "game3_cut_grass_2470")
  love.event.quit(failures == 0 and 0 or 1)
end

return function(game)
  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not result(game.phase == "boot" and game.boot ~= nil, "boot_ready") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Collision = require("src.core.game3.collision")
  local Field = require("src.core.game3.field")
  local FieldMoves = require("src.core.game3.field_moves")
  local Party = require("src.core.game3.party")
  local Objects = require("src.core.game3.objects")
  require("src.core.game3.encounters").onStep = function() return nil end
  require("src.core.game3.trainer_sight").check = function() return false end
  local session = Runtime.getSession()
  if not result(session ~= nil, "new_game_reached_field") then return finish() end
  session.party = {}
  Party.giveMon(session, 29, 20)
  local mon = session.party[1]

  local function place(map, x, y)
    Map.load(Runtime._mod, game, map, { x = x, y = y, facing = "down" })
    Player.surfing, Player.biking = false, false
    U.wait(60)
    return Map.current == map and Player.cellX == x and Player.cellY == y
  end
  local function layout() return Map.currentDef().midLayout end
  local function findPatch(map)
    if Map.current ~= map then place(map, 0, 0) end
    local L = game.data.maps[map].midLayout
    for y = 1, L.height - 2 do
      for x = 1, L.width - 2 do
        local ok = true
        for dy = -1, 1 do
          for dx = -1, 1 do
            local cx, cy = x + dx, y + dy
            if L:midAt(cx, cy) ~= 0x00D or L:elevAt(cx, cy) ~= 3 or Objects.at(cx, cy) then ok = false end
          end
        end
        if ok then return x, y end
      end
    end
  end
  local function cut()
    local store = { flags = {}, vars = {} }
    require("src.core.game3.scripting.flags").setFlag(store, nil, FieldMoves.BADGE_FLAGS.CUT, true)
    local res = FieldMoves.cutFromMenu({ mon = mon, party = session.party, store = store,
      hasCuttableGrass = Collision.isGrass(Player.cellX, Player.cellY) })
    if not result(res and res.ok and res.action == "cut_grass", "party_menu_picks_cut_grass") then return false end
    Field.executeFieldMove(res)
    for _ = 1, 600 do
      if not Field.locked then break end
      U.wait(1)
    end
    U.wait(20)
    return not Field.locked
  end
  local function all3x3(cx, cy, fn)
    for dy = -1, 1 do
      for dx = -1, 1 do
        if not fn(cx + dx, cy + dy) then return false end
      end
    end
    return true
  end

  local MAP = "FR_ROUTE_1"
  local x, y = findPatch(MAP)
  if not result(x ~= nil, "route1_grass_patch_found") then return finish() end
  print(("[driver] %s grass patch centre (%d,%d)"):format(MAP, x, y))
  if not result(place(MAP, x, y), "placed_in_grass") then return finish() end
  result(all3x3(x, y, function(cx, cy) return Collision.isGrass(cx, cy) end), "3x3_is_grass_before")
  result(U.still(game, DIR .. "/2470_route1_grass_before_cut.png"), "shot_before")
  result(cut(), "cut_finished")
  local L = layout()
  result(all3x3(x, y, function(cx, cy) return L:midAt(cx, cy) == 0x001 end), "3x3_mowed_to_plain_mowed")
  result(all3x3(x, y, function(cx, cy) return not Collision.isGrass(cx, cy) end), "3x3_no_longer_grass")
  result(require("src.core.game3.field_effects")._fx == nil, "tall_grass_overlay_gone_from_player")
  result(U.still(game, DIR .. "/2470_route1_grass_mowed.png"), "shot_mowed")

  place(MAP, x, y)
  L = layout()
  result(all3x3(x, y, function(cx, cy) return L:midAt(cx, cy) == 0x00D and Collision.isGrass(cx, cy) end),
    "grass_grows_back_on_reload")

  local VF = "FR_VIRIDIAN_FOREST"
  local vf = game.data.maps[VF] and game.data.maps[VF].midLayout
  local tx, ty
  if vf then
    for yy = 1, vf.height - 2 do
      for xx = 1, vf.width - 2 do
        if not tx and vf:midAt(xx, yy) == 0x284 and vf:elevAt(xx, yy) == 3
            and vf:midAt(xx, yy - 1) == 0x00D and vf:elevAt(xx, yy - 1) == 3 then
          tx, ty = xx, yy
        end
      end
    end
  end
  if tx then
    print(("[driver] %s 0x284 at (%d,%d)"):format(VF, tx, ty))
    if result(place(VF, tx, ty - 1), "placed_above_huge_tree_grass") then
      result(cut(), "forest_cut_finished")
      result(layout():midAt(tx, ty) == 0x281, "viridian_forest_0x284_mowed_to_0x281")
      result(U.still(game, DIR .. "/2470_viridian_forest_huge_tree_mowed.png"), "shot_forest")
    end
  else
    result(false, "viridian_forest_0x284_cell_found")
  end
  finish()
end
