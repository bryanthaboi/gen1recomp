local U = require("tests.drivers.util")
local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. "flash2762 " .. label)
  if not ok then failures = failures + 1 end
  return ok
end
local function finish()
  print((failures == 0 and "PASS " or "FAIL ") .. "flash2762_native failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end
return function(game)
  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.phase == "boot" and game.boot ~= nil, "boot_ready") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "FLASH" })
  U.wait(180)
  local Runtime = require("src.core.game3.runtime")
  local session = Runtime.getSession()
  if not check(session ~= nil, "field_session_ready") then return finish() end
  local version = session.version
  local Profile = require("src.core.game3.profile").of(version)
  local rse = Profile.family == "rse"
  local Map = require("src.core.game3.map")
  local Field = require("src.core.game3.field")
  local View = require("src.core.game3.field_view")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Moves = require("src.core.game3.field_moves")
  local ShowMon = require("src.core.game3.field_move_show_mon")
  local Party = require("src.ui.game3.party_menu")
  local Pokemon = require("src.core.game3.pokemon")
  local Text = require("src.core.game3.rom_text")
  require("src.core.game3.encounters").onStep = function() return nil end
  require("src.core.game3.trainer_sight").check = function() return false end
  local species = assert(Pokemon.speciesFromName("PIKACHU"))
  local move = Moves.MOVES.FLASH
  local mon = { species = species, nickname = "FLASH", level = 20, moves = { move }, pp = { 20 }, personality = 0 }
  Pokemon.applyStats(mon, session)
  mon.hp = mon.maxHp
  session.party = { mon }
  Flags.setFlag(Space.store, nil, Moves.badgeFlag("FLASH"), true)
  local maps = game.data.maps
  local function mapNamed(suffix)
    for id in pairs(maps) do
      if id:sub(-#suffix) == suffix then return id end
    end
    return nil
  end
  local first = assert(mapNamed(rse and "GRANITE_CAVE_B1F" or "ROCK_TUNNEL_1F"))
  local second = assert(mapNamed(rse and "GRANITE_CAVE_B2F" or "ROCK_TUNNEL_B1F"))
  local outdoors = assert(mapNamed(rse and "DEWFORD_TOWN" or "PALLET_TOWN"))
  local shots = os.getenv("POKEPORT_SHOT_DIR")
  local function load(id)
    local def = maps[id]
    local warp = def.warps and def.warps[1]
    local x, y = warp and warp.x or 8, warp and warp.y or 8
    Map.load(Runtime._mod, game, id, { x = x, y = y, facing = "down" })
    U.wait(90)
    return check(Map.current == id, "loaded_" .. id)
  end
  local function selectFlash()
    Party.show(session.party, nil, { session = session })
    U.wait(40)
    U.tap(game, "a")
    U.wait(3)
    local index
    for i, name in ipairs(Party.ACTIONS) do if name == "FLASH" then index = i end end
    if not check(index ~= nil and Party.mode == "action", "known_flash_action_available") then return false end
    Party.actionCursor = index
    U.tap(game, "a")
    return true
  end
  if not load(first) then return finish() end
  check(tonumber(Map.currentDef().cave) == 1 and not Flags.getFlag(Space.store, nil, Moves.SYS_FLAGS.FLASH_ACTIVE),
    "initial_dark_cave_without_flash")
  if not selectFlash() then return finish() end
  check(ShowMon.isActive() and Field.locked, "show_mon_then_animation_lock")
  for _ = 1, 900 do
    if not ShowMon.isActive() and not Field.locked and not Space.vm:isRunning() then break end
    U.wait(1)
  end
  check(not Field.locked and not ShowMon.isActive() and not Space.vm:isRunning(), "animation_end_unlocks_field")
  check(View.getFlashLevel() == (rse and 1 or 0), "first_use_cart_level")
  check(View.flashRadius() == (rse and 72 or nil), "first_use_cart_radius")
  if shots then check(U.still(game, shots .. "/2762_01_first_flash.png"), "first_flash_frame_captured") end
  if not load(second) then return finish() end
  check(Flags.getFlag(Space.store, nil, Moves.SYS_FLAGS.FLASH_ACTIVE)
    and View.getFlashLevel() == (rse and 1 or 0), "floor_change_preserves_flash")
  if not selectFlash() then return finish() end
  local key = (version == "ruby" or version == "sapphire") and "OtherText_CantUseThatHere" or "gText_InUseAlready_PM"
  check(Party.mode == "message" and Party._messageText == Text.ascii(key), "repeated_flash_exact_cached_prompt")
  check(Flags.getFlag(Space.store, nil, Moves.SYS_FLAGS.FLASH_ACTIVE)
    and View.getFlashLevel() == (rse and 1 or 0), "rejection_keeps_flash_state")
  if shots then check(U.still(game, shots .. "/2762_02_repeated_flash_prompt.png"), "repeat_prompt_frame_captured") end
  Party.close()
  if not load(outdoors) then return finish() end
  check(not Flags.getFlag(Space.store, nil, Moves.SYS_FLAGS.FLASH_ACTIVE), "outdoors_clears_flash")
  if not load(first) then return finish() end
  if not selectFlash() then return finish() end
  for _ = 1, 900 do
    if not ShowMon.isActive() and not Field.locked and not Space.vm:isRunning() then break end
    U.wait(1)
  end
  check(Flags.getFlag(Space.store, nil, Moves.SYS_FLAGS.FLASH_ACTIVE) and not Field.locked
    and View.getFlashLevel() == (rse and 1 or 0), "cave_return_flash_usable")
  finish()
end
