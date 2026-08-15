-- Visual proof for WIDE battle HUD regions composited in physical-window
-- space.  Captures the same deterministic battle with the legacy in-canvas
-- placement and the new window placement.  Every capture uses BATTLE SIZE =
-- FILL so the proof matches the target configuration.
--
--   POKEPORT_DRIVER=tests/drivers/wide_battle_window_hud_test.lua \
--     POKEPORT_IDENTITY=wide-window-hud POKEPORT_TOUCH=0 \
--     SHOT_DIR=/tmp/shots love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local BattleState = require("src.battle.BattleState")
  local Pokemon = require("src.pokemon.Pokemon")

  -- Exercise the real desktop-sized margins instead of a synthetic test
  -- window.  The game keeps its native-pixel FILL scaling inside this mode.
  love.window.setFullscreen(true, "desktop")
  U.wait(30)

  game.save.options.battleLayout = "wide"
  game.save.options.battleBg = "world"
  game.save.options.battleFit = "fill"
  game.save.party = { Pokemon.new(game.data, "MEW", 50) }
  U.teleport(game, "ROUTE_1", 5, 5, "down")
  U.wait(60)

  local battle = BattleState.newWild(game, "PIDGEY", 20,
    { onFinish = function() end })
  game.overworld:pushBattle(battle)
  U.wait(360)

  -- Pin the command screen so every capture compares identical battle state.
  battle.introSlide = 0
  battle.introBalls = nil
  battle.showEnemyTrainer = false
  battle.showPlayerBack = false
  battle.enemySendingOut = false
  battle.sendingOut = false
  battle.phase = "menu"
  battle.menuIndex = 1

  battle.windowHUD = false
  U.wait(3)
  U.shot(game, DIR .. "/wide_window_hud_0_legacy_fill.png")

  battle.windowHUD = true
  U.wait(3)
  U.shot(game, DIR .. "/wide_window_hud_1_window_fill.png")

  battle.phase = "moveSelect"
  battle.moveIndex = 1
  U.wait(3)
  U.shot(game, DIR .. "/wide_window_hud_2_moves_fill.png")

  battle.phase = "messages"
  battle:startMessage({ text = "WIDE HUD IN WINDOW SPACE" })
  U.wait(3)
  U.shot(game, DIR .. "/wide_window_hud_3_message_fill.png")

  -- Oak/old-man catch tutorials and ordinary battle ITEM actions push this
  -- opaque 160x144 list above the WIDE battle.  Its own field stays centred;
  -- the unused 304px owner margins must keep showing the world instead of
  -- becoming one full-window white clear.
  battle.phase = "menu"
  battle.current = nil
  -- Exercise the provider-backed case that exposed the real regression:
  -- the WIDE battle must still draw under this overlay even when BATTLE BG
  -- is not "world".  A deterministic window-sized surface stands in for the
  -- Dramaless/Stadium world override, and the wrapper below suppresses the
  -- native paper field exactly as those providers do.  If BattleState:draw
  -- is skipped, this surface is never presented and the screenshot goes all
  -- white again.
  game.save.options.battleBg = "black"
  local g = love.graphics
  local ww, wh = g.getDimensions()
  local provider = g.newCanvas(ww, wh)
  local previous = g.getCanvas()
  g.setCanvas(provider)
  g.clear(0.10, 0.12, 0.14, 1)
  g.setColor(0.18, 0.24, 0.20, 1)
  for x = 0, ww, 96 do g.rectangle("fill", x, 0, 48, wh) end
  g.setColor(0.28, 0.34, 0.30, 1)
  g.rectangle("fill", 0, wh * 0.58, ww, wh * 0.42)
  g.setColor(1, 1, 1, 1)
  g.setCanvas(previous)

  local nativeDraw = battle.draw
  battle.draw = function(self)
    self.game.renderer:setWorldOverride(provider)
    g.clear(0, 0, 0, 0)
    local rectangle = g.rectangle
    local fieldSuppressed = false
    g.rectangle = function(mode, x, y, w, h, ...)
      if not fieldSuppressed and mode == "fill"
          and x == 0 and y == 0 and w == 304 and h == 144 then
        fieldSuppressed = true
        return
      end
      return rectangle(mode, x, y, w, h, ...)
    end
    local ok, result = pcall(nativeDraw, self)
    g.rectangle = rectangle
    if not ok then error(result, 0) end
    return result
  end
  local ListMenu = require("src.ui.ListMenu")
  game.stack:push(ListMenu.new(game, "ITEMS", {
    { value = "POKE_BALL", label = "POKé BALL", right = "x1" },
  }, { script = function() end }))
  U.wait(3)
  U.shot(game, DIR .. "/wide_window_hud_4_item_overlay_fill.png")

  -- Captured-mon nickname entry is another opaque classic screen.  It must
  -- own the whole UI layer: the detached foe/player panels may not be
  -- composited afterward over its letter grid.
  game.stack:pop()
  local NamingScreen = require("src.ui.NamingScreen")
  game.stack:push(NamingScreen.new(game, {
    title = "NICKNAME?", maxLen = 10, onDone = function() end,
  }))
  U.wait(3)
  U.shot(game, DIR .. "/wide_window_hud_5_nickname_overlay_fill.png")

  U.log("WIDE window-HUD proof captured in " .. DIR)
  U.log("0 is the legacy 304x144 composition; 1-5 use physical-window HUD regions")
  while true do coroutine.yield() end
end
