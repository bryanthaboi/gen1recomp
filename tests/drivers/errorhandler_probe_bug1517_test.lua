-- Driver: #1517's other half, the error handler that hid the crash.
--
-- boot.lua's deferErrhand picks `love.errorhandler or love.errhand`, so a
-- love.errorhandler that returns nil ends love.run's `while func do` loop and
-- the process leaves to the OS with no error screen and nothing on stdout.
-- LOVE 11.5 pre-populates love.errhand only, so main.lua capturing
-- love.errorhandler captured nil and every Lua error in every shipped build
-- exited silently.  Measured on the installed 11.5:
--   love.errorhandler type: nil / love.errhand type: function
--
-- Nothing here can be a unit test: the deliverable is whether a human sees
-- LOVE's blue error screen or an app that vanishes.
--
--   POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/errorhandler_probe_bug1517_test.lua love .
--
-- Pre-fix: the window closes on the first drawn frame after the probe arms,
-- exit 1, no output.  Post-fix: the blue screen reads "bug1517: error-handler
-- probe" plus the lua-error.log hint, and stays up until it is dismissed.
return function(game)
  local U = dofile("tests/drivers/util.lua")

  U.log("[1517] love.errorhandler at boot was: "
          .. (rawget(love, "errorhandler") and "a function" or "nil"))
  U.log("[1517] love.errhand is: " .. type(rawget(love, "errhand")))

  U.wait(30)

  -- Raise from a draw callback, not from this coroutine: main.lua resumes the
  -- driver under coroutine.resume and prints its errors itself, which is the
  -- one path that does NOT reach love.errorhandler.  StateStack:draw only
  -- calls the states it is actually holding, so the probe goes on the live
  -- top state rather than on game.overworld, which is not on the stack while
  -- the title screen or the load menu is up.
  local target = game.stack:top()
  U.log("[1517] arming the probe on " .. tostring(target and target.screenId))
  local realDraw = target.draw
  target.draw = function(self, ...)
    if realDraw then realDraw(self, ...) end
    error("bug1517: error-handler probe")
  end

  U.log("[1517] armed; the next drawn frame raises from love.draw")
  U.log("[1517] you should now see LOVE's blue error screen, not a closed app")
  while true do coroutine.yield() end
end
