local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_soft_reset_overlays"
local MODE = os.getenv("S2_MODE") or "new_game"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS soft_reset_overlays " .. MODE)
    love.event.quit(0)
  else
    print("FAIL soft_reset_overlays " .. MODE .. " failures=" .. failures)
    love.event.quit(1)
  end
end

local function waitBoot(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then return true end
    U.wait(1)
  end
  return false
end

local function enterField(game)
  if MODE == "continue" then
    game:_handleBootAction({ action = "continue" })
    for _ = 1, 3000 do
      if game.phase == "field" then break end
      if game.phase == "quest_log" and game.questPlayback then game.questPlayback.done = true end
      U.wait(1)
    end
  else
    game:_handleBootAction({ action = "new_game", name = "RED" })
  end
  U.wait(240)
end

local function run(game)
  waitBoot(game)
  if MODE == "continue" then
    game:_handleBootAction({ action = "new_game", name = "RED" })
    U.wait(240)
    pcall(function() game:saveGame() end)
    game.softResetRequested = true
    U.wait(2)
    waitBoot(game)
  end
  enterField(game)
  local Runtime = require("src.core.game3.runtime")
  local Player = require("src.core.game3.player")
  local Hud = require("src.ui.game3.hud")
  local Field = require("src.core.game3.field")
  local Task = require("src.core.game3.task")
  local Fade = require("src.ui.game3.fade")
  local CaveTransition = require("src.ui.game3.cave_transition")
  local MapPreviewScreen = require("src.ui.game3.map_preview_screen")
  local MapSectionsExtract = require("src.import.gba.map_sections_extract")
  local Sea = require("src.ui.game3.seagallop")
  local StartMenu = require("src.ui.game3.start_menu")
  local MonPic = require("src.ui.game3.mon_pic")
  local BattleTransition = require("src.core.game3.battle_transition")
  local Battle = require("src.core.game3.battle")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local ShowMon = require("src.core.game3.field_move_show_mon")
  local PokecenterHeal = require("src.core.game3.pokecenter_heal")
  local StepEvents = require("src.core.game3.step_events")
  if not result(Runtime.getSession() ~= nil, "reached the field") then return end
  local function giveParty()
    local session = Runtime.getSession()
    session.party = {}
    require("src.core.game3.party").giveMon(session, 39, 20)
  end
  local function sec(id) return MapSectionsExtract.ID_TO_SECTION[id] end

  local function tryMove()
    local x0, y0 = Player.cellX, Player.cellY
    for _, d in ipairs({ "down", "left", "right", "up" }) do
      U.hold(game, d, 24)
      U.wait(24)
      if Player.cellX ~= x0 or Player.cellY ~= y0 then return true, d end
    end
    return false
  end

  local scenarios = {
    { name = "control", setup = function() end, active = function() return false end },
    { name = "cave_transition", setup = function(fired)
        CaveTransition.start("enter", function() fired.cb = true end)
        U.wait(8)
      end, active = function() return CaveTransition.isActive() end },
    { name = "cave_preview", setup = function(fired)
        MapPreviewScreen.runCave(sec("MAPSEC_MT_MOON"), function() fired.cb = true end)
        U.wait(30)
      end, active = function() return MapPreviewScreen.isActive() end },
    { name = "forest_preview", setup = function()
        MapPreviewScreen.show(sec("MAPSEC_VIRIDIAN_FOREST"))
        U.wait(20)
      end, active = function() return MapPreviewScreen.isActive() end },
    { name = "seagallop", setup = function(fired)
        Sea.start(0, 1, function() fired.cb = true end, function() fired.cb = true end)
        U.wait(30)
      end, active = function() return Sea.isActive() end },
    { name = "start_menu", setup = function()
        U.tap(game, "start")
        U.wait(12)
        U.tap(game, "down")
        U.wait(6)
        U.tap(game, "down")
        U.wait(6)
        print("[s2] start_menu cursor before reset=" .. tostring(StartMenu.cursor))
      end, active = function() return StartMenu.isOpen() end,
      after = function()
        result(StartMenu.cursor == 1, "start_menu: cursor back on the top entry after " .. MODE
          .. " (cursor=" .. tostring(StartMenu.cursor) .. ")")
      end },
    { name = "step_event_message", setup = function()
        local session = Runtime.getSession()
        session.repelSteps = 1
        session.vars[0x4020] = 1
        StepEvents.onRepelStep(session, game)
        U.wait(20)
      end, active = function() return StepEvents.busy() end },
    { name = "step_event_tick", setup = function(fired)
        StepEvents.queueEvent({ type = "probe", run = function() end,
          tick = function() fired.cb = true end })
        U.wait(5)
      end, active = function() return StepEvents.busy() end },
    { name = "mon_pic", setup = function()
        MonPic.show(25)
        U.wait(5)
      end, active = function() return MonPic.isActive() end },
    { name = "battle_transition", setup = function(fired)
        giveParty()
        BattleBridge.start(Runtime._mod, game,
          { species = 129, level = 5, moves = { 150 }, pp = { 40 }, item = 0 },
          { wild = true, done = function() fired.cb = true end })
        U.wait(20)
      end, active = function() return BattleTransition.isActive() or Battle.isActive() end },
    { name = "battle_active", setup = function(fired)
        giveParty()
        BattleBridge.start(Runtime._mod, game,
          { species = 129, level = 5, moves = { 150 }, pp = { 40 }, item = 0 },
          { wild = true, fade = false, done = function() fired.cb = true end })
        for _ = 1, 600 do
          if Battle.isActive() then break end
          U.wait(1)
        end
        U.wait(60)
      end, active = function() return Battle.isActive() or BattleTransition.isActive() end },
    { name = "task", setup = function(fired)
        Task.spawn(function(t) if t.frames > 400 then fired.cb = true return true end end)
        U.wait(5)
      end, active = function() return Task.count() > 0 end },
    { name = "bag_menu", setup = function()
        U.tap(game, "start")
        U.wait(12)
        U.tap(game, "a")
        U.wait(60)
      end, active = function()
        local B = package.loaded["src.ui.game3.bag_menu"]
        return (B and B.isOpen()) or StartMenu.isOpen()
      end },
    { name = "pokecenter_heal", setup = function()
        giveParty()
        PokecenterHeal.start()
        U.wait(10)
      end, active = function() return PokecenterHeal.isActive() end },
    { name = "show_mon", setup = function(fired)
        ShowMon.start(25, {}, function() fired.cb = true end)
        U.wait(10)
      end, active = function() return ShowMon.isActive() end },
    { name = "hud_wait_button", setup = function(fired)
        Hud.armWaitButton(function() fired.cb = true end)
        U.wait(5)
      end, active = function() return Hud._waitButton ~= nil end },
    { name = "fade", setup = function(fired)
        Fade.begin(Fade.MODE.TO_BLACK, 1, function() fired.cb = true end)
        U.wait(5)
      end, active = function() return Fade.isActive() end },
  }

  for _, sc in ipairs(scenarios) do
    local fired = {}
    sc.setup(fired)
    local was = sc.active()
    print("[s2] " .. sc.name .. " active before reset=" .. tostring(was))
    if sc.name ~= "control" then result(was, sc.name .. ": overlay up before the reset") end
    fired.cb = nil
    game.softResetRequested = true
    U.wait(2)
    result(waitBoot(game), sc.name .. ": soft reset returned to the title")
    enterField(game)
    local still = sc.active()
    result(not still, sc.name .. ": overlay gone after " .. MODE .. " (active=" .. tostring(still) .. ")")
    result(not fired.cb, sc.name .. ": stale callback did not fire into the new session")
    if sc.after then sc.after() end
    local moved, dir = tryMove()
    result(moved, sc.name .. ": player can move (" .. tostring(dir) .. ") busy=" .. tostring(Hud.busy())
      .. " menu=" .. tostring(Hud.isMenuOpen()) .. " locked=" .. tostring(Field.locked)
      .. " tasks=" .. tostring(Task.count()) .. " battle=" .. tostring(Battle.isActive()))
    U.shot(game, DIR .. "/soft_reset_" .. sc.name .. "_" .. MODE .. "_after.png")
    if StartMenu.isOpen() then StartMenu.close(true) end
    require("src.ui.game3.stack").clear()
    if Battle.isActive() then pcall(Battle.abort, "run") end
    if BattleTransition.isActive() then BattleTransition.abort() end
    MonPic.hide()
    local BM = package.loaded["src.ui.game3.bag_menu"]
    if BM and BM.isOpen() then pcall(BM.close) end
    if BM then BM.open = false end
    StartMenu.open = false
    PokecenterHeal._fx = nil
    ShowMon._fx = nil
    Hud.clearWaitButton()
    Task.clear()
    StepEvents.flush()
    U.wait(30)
  end
end

return function(game)
  local ok, err = pcall(run, game)
  if not ok then result(false, "driver error: " .. tostring(err)) end
  finish()
end
