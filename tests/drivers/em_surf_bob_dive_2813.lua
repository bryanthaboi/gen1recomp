local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/em_surf_bob_dive_2813"

local failures = 0
local function check(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  print((failures == 0 and "PASS" or "FAIL") .. " em_surf_bob_dive_2813 failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  if not check(game.boot ~= nil, "boot reached") then return finish() end
  game:_handleBootAction({ action = "new_game", name = "BRENDAN", gender = 0 })
  U.wait(60)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Warp = require("src.core.game3.warp")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Party = require("src.core.game3.party")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local ShowMon = require("src.core.game3.field_move_show_mon")
  local FieldEffects = require("src.core.game3.field_effects")
  local C = require("src.core.game3.constants").of("emerald")
  local session = Runtime.getSession()
  if not check(session ~= nil, "field session exists") then return finish() end
  local IDS = Flags.forVersion("emerald").IDS

  session.party = {}
  Party.giveMon(session, C.species.byName.SPECIES_WAILMER, 40, "WAILMER")
  local m = session.party[1]
  m.moves = { C.moves.byName.MOVE_DIVE, C.moves.byName.MOVE_SURF, C.moves.byName.MOVE_WATER_GUN, C.moves.byName.MOVE_REST }
  m.pp = { 10, 15, 25, 10 }
  Flags.setFlag(Space.store, nil, IDS.FLAG_BADGE05_GET, true)
  Flags.setFlag(Space.store, nil, IDS.FLAG_BADGE07_GET, true)

  local function mapNow() local s = Runtime.getSession(); return s and s.map end

  local function place(mapId, x, y, facing, surfing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing })
    local s = Runtime.getSession()
    s.x, s.y, s.facing = x, y, facing
    Player.surfing = surfing == true
    require("src.core.game3.field").unlock()
    U.wait(20)
  end

  local function sample(n, shots)
    local ys, blobs, lo, hi, seenAt = {}, {}, 99, -99, {}
    for i = 1, n do
      U.wait(1)
      local y = Player.spriteYOffset or 0
      ys[i], blobs[i] = y, FieldEffects.surfBlobY2()
      lo, hi = math.min(lo, y), math.max(hi, y)
      if shots and shots[y] and not seenAt[y] then
        seenAt[y] = true
        U.still(game, DIR .. "/" .. shots[y])
      end
    end
    return ys, blobs, lo, hi
  end

  place("EM_ROUTE124", 10, 3, "down", true)
  U.wait(40)
  local ys, blobs, lo, hi = sample(64, { [0] = "2813_01_surf_bob_rest.png", [-4] = "2813_02_surf_bob_peak.png" })
  print("[driver] surf y2: " .. table.concat(ys, ","))
  check(lo == -4 and hi == 0, string.format("surfing bob spans 0..-4 (got %d..%d)", hi, lo))
  local synced = true
  for i = 1, #ys do if ys[i] ~= blobs[i] then synced = false end end
  check(synced, "player sprite and surf blob share y2 every frame")
  local runs, last, len = {}, nil, 0
  for i = 1, #ys do
    if ys[i] == last then len = len + 1 else if last then runs[#runs + 1] = len end last, len = ys[i], 1 end
  end
  local steady = #runs >= 4
  for i = 2, #runs do if runs[i] ~= 4 then steady = false end end
  check(steady, "bob steps one pixel every 4 frames")

  local movingYs = {}
  for _ = 1, 40 do
    table.insert(game.input.pressQueue, "left")
    game.input.state.left = true
    U.wait(1)
    if Player.moving then movingYs[#movingYs + 1] = Player.spriteYOffset or 0 end
  end
  game.input.state.left = false
  local movedBob, smooth = false, true
  for i, y in ipairs(movingYs) do
    if y ~= 0 then movedBob = true end
    if i > 1 and math.abs(y - movingYs[i - 1]) > 1 then smooth = false end
  end
  check(#movingYs > 0 and movedBob, "bob keeps running while swimming (" .. table.concat(movingYs, ",") .. ")")
  check(smooth, "bob never snaps back to 0 between swim steps")
  for _ = 1, 40 do if not Player.moving then break end U.wait(1) end

  place("EM_ROUTE124", 10, 3, "down", true)
  U.wait(10)
  U.tap(game, "a")
  local posed, cutin, shotCut = false, false, false
  for _ = 1, 1500 do
    if mapNow() == "EM_UNDERWATER_ROUTE124" and not Warp.isBusy() then break end
    if (Player.fieldMoveAnim or 0) > 0 then posed = true end
    if ShowMon.isActive() then
      if not cutin then U.still(game, DIR .. "/2813_03_dive_start_no_pose.png") end
      cutin = true
      if not shotCut and ShowMon._fx and ShowMon._fx.sprite and ShowMon._fx.sprite.state == "wait" then
        shotCut = true
        U.still(game, DIR .. "/2813_04_dive_cutin.png")
      end
    end
    if Choice.isOpen and Choice.isOpen() then
      U.tap(game, "a")
    elseif Message.isOpen and Message.isOpen() then
      U.tap(game, "a")
      U.wait(3)
    else
      U.wait(1)
    end
  end
  check(cutin, "Dive shows the field move mon")
  check(not posed, "Dive never puts the player in the field move pose")
  check(mapNow() == "EM_UNDERWATER_ROUTE124", "dive warps underwater (" .. tostring(mapNow()) .. ")")
  U.wait(30)
  check(Player.underwater == true, "avatar is underwater")

  ys, _, lo, hi = sample(64, { [0] = "2813_05_underwater_bob_rest.png", [4] = "2813_06_underwater_bob_low.png" })
  print("[driver] underwater y2: " .. table.concat(ys, ","))
  check(lo == 0 and hi == 4, string.format("underwater bob spans 0..+4 (got %d..%d)", lo, hi))

  finish()
end
