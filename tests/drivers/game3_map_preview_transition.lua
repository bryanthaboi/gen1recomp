local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_map_preview_transition"

return function(game)
  local failures = 0
  local function pass(label) print("PASS " .. label) end
  local function fail(label, why)
    failures = failures + 1
    print("FAIL " .. label .. (why and (" " .. why) or ""))
  end
  local function check(ok, label, why) if ok then pass(label) else fail(label, why) end end

  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Party = require("src.core.game3.party")
  local Field = require("src.core.game3.field")
  local Warp = require("src.core.game3.warp")
  local MPS = require("src.ui.game3.map_preview_screen")
  local Cave = require("src.ui.game3.cave_transition")
  local Fade = require("src.ui.game3.fade")
  local MapCatalog = require("src.import.gba.map_catalog")

  local session = Runtime.getSession()
  if not session then print("FAIL no session") love.event.quit(1) return end
  session.party = {}
  Party.giveMon(session, 6, 50)

  local function placeAt(mapId, x, y, facing)
    Map.load(nil, game, mapId, { x = x, y = y, facing = facing or "down" })
    if game.session then
      game.session.x, game.session.y, game.session.facing = x, y, facing or "down"
    end
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing or "down"
    MPS.dismiss()
    Field.locked = false
    U.wait(30)
  end

  local gate = MapCatalog.pretToEngine("Route2_ViridianForest_SouthEntrance")
  local forest = MapCatalog.pretToEngine("ViridianForest")
  local r4 = MapCatalog.pretToEngine("Route4")
  local moon = MapCatalog.pretToEngine("MtMoon_1F")

  local function probeNameWindow()
    local canvas = love.graphics.newCanvas(240, 160)
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.origin()
    love.graphics.clear(0, 0, 0, 1)
    MPS.draw()
    love.graphics.setCanvas()
    love.graphics.pop()
    local data = canvas:newImageData()
    local black, grey, white = 0, 0, 0
    for y = 0, 15 do
      for x = 0, 103 do
        local r, g, b = data:getPixel(x, y)
        r, g, b = math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)
        if r == 0 and g == 0 and b == 0 then black = black + 1
        elseif r == 214 and g == 214 and b == 214 then grey = grey + 1
        elseif r == 247 and g == 247 and b == 255 then white = white + 1 end
      end
    end
    data:release()
    canvas:release()
    return black, grey, white
  end

  local function forestRun(label, opts)
    opts = opts or {}
    placeAt(gate, 7, 2, "up")
    Warp.request(nil, game, forest, 29, 61, "up")
    local hold, dissolve, lockedAll, dur = 0, 0, true, nil
    local shotHold, shotMid = false, false
    for _ = 1, 900 do
      U.wait(1)
      if MPS.isForestActive() then
        if MPS._state == MPS.STATE.HOLD and not Fade.isActive() then
          hold = hold + 1
          dur = MPS._duration
          if opts.shots and not shotHold and hold == 30 then
            shotHold = true
            U.still(game, DIR .. "/pv_forest_hold_black_surround.png")
            local black, grey, white = probeNameWindow()
            print(string.format("[pv] name window black=%d grey=%d white=%d", black, grey, white))
            -- src/menu2.c:469
            check(black > 0 and grey > 0 and grey < 2 * black and white > black + grey,
              "forest_name_black_text_grey_shadow",
              ("black=%d grey=%d white=%d"):format(black, grey, white))
          end
        elseif MPS._state == MPS.STATE.FADE_OUT then
          dissolve = dissolve + 1
          if opts.shots and not shotMid and dissolve == 24 then
            shotMid = true
            print(string.format("[pv] mid-dissolve eva=%d evb=%d", MPS._eva, MPS._evb))
            U.still(game, DIR .. "/pv_forest_mid_dissolve.png")
          end
        end
        if not Field.locked then lockedAll = false end
      elseif hold > 0 then
        break
      end
    end
    U.wait(2)
    print(string.format("[pv] %s dur=%s hold=%d dissolve=%d lockedAll=%s lockedAfter=%s",
      label, tostring(dur), hold, dissolve, tostring(lockedAll), tostring(Field.locked)))
    return dur, hold, dissolve, lockedAll
  end

  local dur1, hold1, diss1, locked1 = forestRun("forest first")
  check(dur1 == 120 and hold1 + 1 == 121, "forest_first_visit_hold_120", "dur=" .. tostring(dur1) .. " hold=" .. hold1)
  check(diss1 == 47, "forest_dissolve_47_frames", "dissolve=" .. diss1)
  check(locked1, "forest_field_locked_during_preview")
  check(not Field.locked, "forest_field_unlocked_after_preview")

  local dur2, hold2 = forestRun("forest repeat")
  check(dur2 == 40 and hold2 + 1 == 41, "forest_repeat_visit_hold_40", "dur=" .. tostring(dur2) .. " hold=" .. hold2)

  placeAt(gate, 7, 2, "up")
  Warp.request(nil, game, forest, 29, 61, "up")
  for _ = 1, 400 do
    U.wait(1)
    if MPS.isForestActive() and MPS._state == MPS.STATE.HOLD and not Fade.isActive() then break end
  end
  local y0 = Player.cellY
  U.hold(game, "up", 20)
  check(Player.cellY == y0 and MPS.isForestActive(), "forest_walk_blocked_during_hold",
    "y0=" .. tostring(y0) .. " y=" .. tostring(Player.cellY))
  for _ = 1, 300 do U.wait(1) if not MPS.isActive() then break end end

  forestRun("forest shots", { shots = true })

  local function caveRun(label, opts)
    opts = opts or {}
    placeAt(r4, 19, 6, "up")
    Warp.request(nil, game, moon, 18, 36, "up")
    local counts = { black = 0, fadein = 0, hold = 0, white = 0, flash = 0 }
    local dur, started, shots = nil, false, {}
    for _ = 1, 900 do
      U.wait(1)
      local c = MPS._cave
      if c then
        started = true
        if opts.holdB then game.input.state.b = true end
        if c.step <= 2 then counts.black = counts.black + 1
        elseif c.step == 3 then counts.fadein = counts.fadein + 1
        elseif c.step == 4 then
          counts.hold = counts.hold + 1
          dur = c.duration
          if opts.shots and counts.hold == 30 and not shots.hold then
            shots.hold = true
            U.still(game, DIR .. "/pv_mtmoon_cave_preview.png")
          end
        elseif c.step == 5 then
          counts.white = counts.white + 1
          if opts.shots and counts.white == 7 and not shots.white then
            shots.white = true
            U.still(game, DIR .. "/pv_mtmoon_fade_to_white.png")
          end
        end
      elseif Cave.isActive() then
        counts.flash = counts.flash + 1
        local run = Cave._run
        if opts.shots and run and run.task == "2" and run.d2 == 8 and not shots.flash then
          shots.flash = true
          U.still(game, DIR .. "/pv_mtmoon_flash_mid.png")
        end
        if opts.shots and run and run.task == "3" and run.d1 == 8 and not shots.dim then
          shots.dim = true
          U.still(game, DIR .. "/pv_mtmoon_flash_dimming.png")
        end
      elseif started then
        break
      end
    end
    game.input.state.b = false
    for _ = 1, 120 do U.wait(1) if not Warp.isBusy() then break end end
    print(string.format("[pv] %s dur=%s black=%d fadein=%d hold=%d white=%d flash=%d map=%s",
      label, tostring(dur), counts.black, counts.fadein, counts.hold, counts.white, counts.flash,
      tostring(Map.current)))
    return dur, counts
  end

  local cd1, c1 = caveRun("mtmoon first")
  check(cd1 == 120 and c1.hold == 121, "mtmoon_first_visit_hold_120", "dur=" .. tostring(cd1) .. " hold=" .. c1.hold)
  -- pokefirered/src/fldeff_flash.c:199 CB2_ChangeMapMain
  check(c1.fadein == 15, "mtmoon_fade_in_15_frames", "fadein=" .. c1.fadein)
  check(c1.white == 11, "mtmoon_fade_to_white_11_frames", "white=" .. c1.white)
  check(c1.flash == 27, "mtmoon_flash_27_frames", "flash=" .. c1.flash)
  check(Map.current == moon, "mtmoon_map_loaded_after_flash", tostring(Map.current))

  local cd2, c2 = caveRun("mtmoon repeat")
  check(cd2 == 40 and c2.hold == 41, "mtmoon_repeat_visit_hold_40", "dur=" .. tostring(cd2) .. " hold=" .. c2.hold)

  local _, c3 = caveRun("mtmoon b skip", { holdB = true })
  check(c3.hold == 1, "mtmoon_b_skips_hold", "hold=" .. c3.hold)

  caveRun("mtmoon shots", { shots = true })

  placeAt(moon, 18, 36, "down")
  Warp.request(nil, game, r4, 19, 6, "down")
  local exitFrames = 0
  for _ = 1, 300 do
    U.wait(1)
    if Cave.isActive() then exitFrames = exitFrames + 1
    elseif exitFrames > 0 then break end
  end
  print("[pv] exit flash frames=" .. exitFrames)
  check(exitFrames == 38, "cave_exit_flash_38_frames", "frames=" .. exitFrames)

  love.event.quit(failures == 0 and 0 or 1)
end
