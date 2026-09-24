-- Shared helpers for POKEPORT_DRIVER scripts (frame-stepped coroutines
-- run by main.lua under xvfb for scripted screenshots).

local U = {}

local frame = 0

function U.wait(n)
  for _ = 1, n do
    frame = frame + 1
    coroutine.yield()
  end
end

-- tap a button for one frame, then release it (the driver has no
-- keyreleased, so an unreleased button would stay held forever and
-- shadow later directional input)
function U.tap(game, btn)
  table.insert(game.input.pressQueue, btn)
  U.wait(1)
  game.input.state[btn] = false
end

-- hold a direction for n frames
function U.hold(game, btn, n)
  for _ = 1, n do
    table.insert(game.input.pressQueue, btn)
    game.input.state[btn] = true
    coroutine.yield()
  end
  game.input.state[btn] = false
end

-- Returns true when the screenshot actually reached disk.
--
-- main.lua writes the capture with a plain `io.open(path, "wb")` guarded by
-- `if f then`, so a missing parent directory (the usual case: SHOT_DIR points
-- somewhere that was never created) silently writes nothing.  A driver that
-- logs "captured" on that path sends the reader off to look at a file that is
-- not there, which is the one thing a screenshot check must never do -- so
-- make the directory first, then confirm the file exists.
function U.shot(game, path)
  local dir = path:match("^(.*)[/\\][^/\\]+$")
  if dir and dir ~= "" then
    os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')
  end
  os.remove(path)
  game.capturePath = path
  -- love.draw consumes capturePath once per rendered frame, but fast runs
  -- (POKEPORT_SPEED) step the driver many times per render; spin until the
  -- capture lands so later actions can't outrun it
  for _ = 1, 4000 do
    if not game.capturePath then break end
    frame = frame + 1
    coroutine.yield()
  end
  for _ = 1, 4000 do
    local f = io.open(path, "rb")
    if f then f:close() return true end
    frame = frame + 1
    coroutine.yield()
  end
  U.log("FAIL screenshot did not reach disk:", path)
  return false
end

function U.still(game, path)
  local update = rawget(game, "update")
  game.update = function() end
  local ok = U.shot(game, path)
  game.update = update
  return ok
end

-- skip the intro movie + title into a fresh overworld game
function U.newGame(game)
  U.wait(5)
  U.tap(game, "start") -- skip intro movie
  U.wait(10)
  local title = game.stack:top()
  for _ = 1, 60 do
    U.tap(game, "a")
    U.wait(5)
    if game.stack:top() ~= title then break end
  end
  -- menu: CONTINUE may or may not exist; NEW GAME is first without a save
  U.tap(game, "a")
  U.wait(10)
  -- Oak speech: mash through text + naming (presets pick first = RED).
  -- The closing shrink-away beat (~103 frames) is not skippable, like
  -- the DelayFrames chain it ports, so leave headroom.
  local reached = false
  for _ = 1, 2000 do
    U.tap(game, "a")
    U.wait(2)
    if game.overworld and game.stack:top() == game.overworld then reached = true break end
  end
  if not reached then print("FAIL newGame never reached the overworld") end
  U.wait(10)
  return reached
end

-- jump straight into the overworld at a position, bypassing the intro
function U.teleport(game, mapId, x, y, facing)
  while game.stack:top() do game.stack:pop() end
  local OverworldState = require("src.world.OverworldController")
  game.stack:push(OverworldState, mapId, x, y, facing or "down")
  U.wait(5)
end

function U.log(...)
  print("[driver]", ...)
end

function U.frame() return frame end

-- pokefirered/src/field_screen_effect.c:387 Task_RushInjuredPokemonToCenter
function U.clearWhiteoutRush(game)
  local Rush = require("src.ui.game3.whiteout_rush")
  local Message = require("src.ui.game3.message")
  local Space = require("src.core.game3.scripting.space")
  local Field = require("src.core.game3.field")
  for _ = 1, 600 do
    if Rush.phase() == "wait" then break end
    U.wait(1)
  end
  U.tap(game, "a")
  for _ = 1, 2400 do
    local busy = Space.vm and Space.vm:isRunning()
    if not Rush.isActive() and not Message.isOpen() and not busy and not Field.locked then break end
    if Message.isOpen() and Message.isTyping() then Message.skipReveal() end
    if Message.isOpen() and Message.isWaiting() then U.tap(game, "a") end
    U.wait(2)
  end
end

return U
