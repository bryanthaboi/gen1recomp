local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_surf_music_2423"
local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end
local function finish()
  result(failures == 0, "game3_surf_music_2423")
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
  local Audio = require("src.core.game3.audio")
  local Field = require("src.core.game3.field")
  local ItemUse = require("src.core.game3.item_use")
  local Party = require("src.core.game3.party")
  local ShowMon = require("src.core.game3.field_move_show_mon")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  require("src.core.game3.encounters").onStep = function() return nil end
  require("src.core.game3.trainer_sight").check = function() return false end
  local session = Runtime.getSession()
  if not result(session ~= nil, "new_game_reached_field") then return finish() end
  session.party = {}
  Party.giveMon(session, 131, 40)
  local mon = session.party[1]

  local function song() return Audio._currentSong and Audio._currentSong.id end
  local function waitSong(id, frames)
    for _ = 1, frames or 400 do
      if song() == id and not Audio._fadeOut then return true end
      U.wait(1)
    end
    return song() == id
  end
  local function place(map, x, y, facing, surfing)
    Player.surfing = false
    Map.load(Runtime._mod, game, map, { x = x, y = y, facing = facing })
    if surfing then Player.surfing, Player.elevation = true, 1 end
    U.wait(60)
  end
  local function settle()
    for _ = 1, 120 do
      if not Player.moving and not Field.locked then break end
      U.wait(1)
    end
  end

  place("FR_ROUTE_19", 7, 11, "left", true)
  result(Collision.isWater(7, 11) and not Collision.isWater(6, 11), "route19_rock_cell_not_water")
  for _ = 1, 20 do U.hold(game, "left", 1) end
  settle()
  result(Player.cellX == 7 and Player.cellY == 11 and Player.surfing, "2423_surf_into_rock_blocked")
  U.shot(game, DIR .. "/2423_rock_blocked.png")
  Player.facing = "left"
  result(ItemUse.canFish() == false, "2423_fishing_refuses_rock")
  Player.facing = "down"
  result(ItemUse.canFish() == true, "2423_fishing_open_water_ok")

  place("FR_ROUTE_19", 9, 12, "left", false)
  local mapSong = Audio._mapSong
  result(mapSong ~= nil and mapSong ~= Audio.MUS_SURF and song() == mapSong, "route19_map_song_" .. tostring(mapSong))

  Field.executeFieldMove({ action = "surf", mon = mon })
  local shot = false
  for _ = 1, 400 do
    local fx = ShowMon._fx
    if fx and fx.sprite and fx.sprite.state == "wait" and not shot then
      shot = U.shot(game, DIR .. "/2423_surf_show_mon.png")
    end
    if not ShowMon.isActive() and Player.surfing and not Player.moving then break end
    U.wait(1)
  end
  result(shot, "2423_surf_show_mon_shot")
  settle()
  result(Player.surfing and Player.cellX == 8 and Player.cellY == 12, "surf_started")
  result(waitSong(Audio.MUS_SURF), "2423_surf_music_305 (" .. tostring(song()) .. ")")
  result(Audio._mapSong == mapSong, "2423_map_song_kept")

  local ok = BattleBridge.startWild(Runtime._mod, game, { species = 129, level = 5 }, { fade = false })
  result(ok == true, "wild_battle_on_water_started")
  for _ = 1, 240 do
    if Battle.isActive() then break end
    U.wait(1)
  end
  U.wait(60)
  BattleBridge.finishPending("run")
  for _ = 1, 240 do
    if not Battle.isActive() then break end
    U.wait(1)
  end
  U.wait(30)
  result(waitSong(Audio.MUS_SURF, 120), "2423_battle_on_water_back_to_305 (" .. tostring(song()) .. ")")

  for _ = 1, 30 do
    U.hold(game, "right", 1)
    if Player.moving then break end
  end
  settle()
  result(not Player.surfing and Player.cellX == 9, "dismounted")
  result(waitSong(mapSong), "2423_dismount_map_song_back (" .. tostring(song()) .. ")")

  ItemUse.useBike(session)
  result(Player.biking == true, "bike_on")
  result(waitSong(Audio.MUS_CYCLING), "2423_bike_music_282 (" .. tostring(song()) .. ")")
  result(Audio._savedSong == Audio.MUS_CYCLING, "bike_saved_song")
  ItemUse.useBike(session)
  result(Player.biking == false, "bike_off")
  result(waitSong(mapSong, 60), "2423_bike_off_map_song (" .. tostring(song()) .. ")")

  place("FR_ROUTE_23", 7, 150, "up", false)
  local r23 = Audio._mapSong
  result(Audio.canOverrideMapMusic(Audio.MUS_SURF) == false
    and Audio.canOverrideMapMusic(Audio.MUS_CYCLING) == false, "2423_route23_blocks_ride_music")
  local biked = ItemUse.useBike(session)
  U.wait(30)
  result(biked == true and Player.biking and Audio._savedSong == nil and song() == r23,
    "2423_route23_bike_keeps_map_song")
  if Player.biking then ItemUse.useBike(session) end

  place("FR_ROUTE_19", 9, 12, "up", false)
  Field.executeFieldMove({ action = "cut_grass", mon = mon })
  shot = false
  for _ = 1, 400 do
    local fx = ShowMon._fx
    if fx and fx.sprite and fx.sprite.state == "wait" and not shot then
      shot = U.shot(game, DIR .. "/2423_cut_show_mon.png")
    end
    if not ShowMon.isActive() and not Field.locked then break end
    U.wait(1)
  end
  result(shot, "2423_cut_show_mon_shot")

  place("FR_PLAYERS_HOUSE_1F", 5, 5, "down", false)
  Field.executeFieldMove({ action = "sweet_scent", mon = mon })
  shot = false
  for _ = 1, 400 do
    local fx = ShowMon._fx
    if fx and fx.sprite and fx.sprite.state == "wait" and not shot then
      shot = U.shot(game, DIR .. "/2423_show_mon_indoors.png")
    end
    if not ShowMon.isActive() then break end
    U.wait(1)
  end
  result(shot, "2423_indoor_show_mon_shot")
  U.wait(120)

  finish()
end
