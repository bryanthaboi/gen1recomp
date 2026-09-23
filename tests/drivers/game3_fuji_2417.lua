local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_fuji_2417"

-- pokefirered/include/constants/flags.h:68
local FLAG_HIDE_TOWER_FUJI = 0x034
local FLAG_HIDE_POKEHOUSE_FUJI = 0x035
-- pokefirered/include/constants/flags.h:110
local FLAG_HIDE_TOWER_ROCKET_1 = 0x05E
-- pokefirered/include/constants/flags.h:147
local FLAG_HIDE_TOWER_ROCKET_2 = 0x083
local FLAG_HIDE_TOWER_ROCKET_3 = 0x084
-- pokefirered/include/constants/flags.h:597
local FLAG_RESCUED_MR_FUJI = 0x23C
-- pokefirered/include/constants/items.h:422
local ITEM_POKE_FLUTE = 350
-- pokefirered/data/maps/PokemonTower_7F/map.json:18
local FUJI = 1

return function(game)
  local failures = 0
  local function check(ok, label)
    print((ok and "PASS " or "FAIL ") .. label)
    if not ok then failures = failures + 1 end
    return ok
  end
  local function finish() love.event.quit(failures == 0 and 0 or 1) end
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)
  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Objects = require("src.core.game3.objects")
  local Bag = require("src.core.game3.bag")
  local Message = require("src.ui.game3.message")
  local session = Runtime.getSession()
  if not check(session ~= nil, "fuji_new_game") then return finish() end
  local function place(x, y, facing)
    Player.moving, Player.progress = false, 0
    Player.cellX, Player.cellY, Player.targetX, Player.targetY = x, y, x, y
    Player.px, Player.py, Player.facing = x * 16, y * 16, facing
    session.x, session.y, session.facing = x, y, facing
  end
  local function getFlag(id) return Flags.getFlag(Space.store, Space.vm and Space.vm.ctx, id) end
  for _, f in ipairs({ FLAG_HIDE_TOWER_ROCKET_1, FLAG_HIDE_TOWER_ROCKET_2, FLAG_HIDE_TOWER_ROCKET_3,
      FLAG_HIDE_POKEHOUSE_FUJI }) do
    Flags.setFlag(Space.store, Space.vm and Space.vm.ctx, f, true)
  end
  Map.load(nil, game, "FR_POKEMON_TOWER_7F", { x = 11, y = 5, facing = "up" })
  place(11, 5, "up")
  U.wait(90)
  local fuji = Objects.find(FUJI)
  if not check(fuji ~= nil and fuji.visible, "fuji_present_on_7f") then return finish() end
  U.tap(game, "a")
  local opened = false
  for _ = 1, 240 do
    if Message.isOpen() then opened = true break end
    U.wait(1)
  end
  if not check(opened, "fuji_text_opened") then return finish() end
  U.wait(40)
  fuji = Objects.find(FUJI)
  check(getFlag(FLAG_HIDE_TOWER_FUJI), "fuji_hide_flag_set_before_text")
  check(fuji ~= nil and fuji.visible and not fuji.hidden, "fuji_visible_during_text")
  check(U.shot(game, DIR .. "/2417_fuji_text_visible.png"), "fuji_text_screenshot_written")
  local arrived = false
  for _ = 1, 400 do
    if Runtime.getSession().map == "FR_LAVENDER_TOWN_VOLUNTEER_POKEMON_HOUSE"
        and not Space.vm:isRunning() then
      arrived = true
      break
    end
    if Message.isOpen() then U.tap(game, "a") end
    U.wait(6)
  end
  if not check(arrived, "fuji_warp_to_volunteer_house") then return finish() end
  U.wait(90)
  session = Runtime.getSession()
  check(Player.cellX == 4 and Player.cellY == 7, "fuji_player_at_house_4_7")
  local houseFuji = Objects.find(FUJI)
  check(houseFuji ~= nil and houseFuji.visible and houseFuji.cellX == 3 and houseFuji.cellY == 3,
    "fuji_present_in_house")
  check(getFlag(FLAG_RESCUED_MR_FUJI) and not getFlag(FLAG_HIDE_POKEHOUSE_FUJI), "fuji_rescue_flags")
  check(U.shot(game, DIR .. "/2417_fuji_in_volunteer_house.png"), "fuji_house_screenshot_written")
  place(3, 4, "up")
  U.wait(10)
  U.tap(game, "a")
  local gotFlute = false
  for _ = 1, 400 do
    if Bag.has(session.bag, ITEM_POKE_FLUTE, 1) then gotFlute = true end
    if gotFlute and not Message.isOpen() and not Space.vm:isRunning() then break end
    if Message.isOpen() then U.tap(game, "a") end
    U.wait(6)
  end
  check(gotFlute, "fuji_gives_poke_flute")
  Map.load(nil, game, "FR_POKEMON_TOWER_7F", { x = 11, y = 5, facing = "up" })
  place(11, 5, "up")
  U.wait(90)
  local gone = Objects.find(FUJI)
  check(gone == nil or not gone.visible, "fuji_absent_on_7f_reload")
  finish()
end
