-- pokered/scripts/SaffronCity.asm:76
-- pokered/home/text.asm:525
--   POKEPORT_DRIVER=tests/drivers/saffron_pidgeot_cry_bug2262_test.lua POKEPORT_IDENTITY=red-sep04 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or os.getenv("POKEPORT_SHOT_DIR") or "/tmp/shots"
  local Sound = require("src.core.Sound")
  local TextBox = require("src.render.TextBox")

  local ok = true
  local function check(label, pass)
    U.log(pass and "PASS" or "FAIL", label)
    if not pass then ok = false end
    return pass
  end
  local function finish()
    U.log(ok and "PASS saffron_pidgeot_cry_2262" or "FAIL saffron_pidgeot_cry_2262")
    love.event.quit(ok and 0 or 1)
    while true do coroutine.yield() end
  end

  U.newGame(game)
  if not check("new game reached the overworld", game.overworld ~= nil) then finish() end

  local cries = {}
  local realPlayCry = Sound.playCry
  Sound.playCry = function(data, species, ...)
    cries[#cries + 1] = { species = species, frame = U.frame() }
    return realPlayCry(data, species, ...)
  end
  game.save.flags.EVENT_BEAT_SILPH_CO_GIOVANNI = true
  U.teleport(game, "SAFFRON_CITY", 31, 13, "up")
  U.wait(30)

  local pidgeot
  for _, n in ipairs(game.overworld.npcs or {}) do
    if n.def and n.def.name == "SAFFRONCITY_PIDGEOT" then pidgeot = n end
  end
  if not check("pidgeot is on SAFFRON_CITY after Silph", pidgeot ~= nil) then finish() end

  U.tap(game, "a")

  local box, typedFrame
  for _ = 1, 600 do
    local top = game.stack:top()
    if getmetatable(top) == TextBox then
      box = top
      if top.done then typedFrame = U.frame() break end
    end
    U.wait(1)
  end
  if not check("pidgeot line opened a text box", box ~= nil) then finish() end
  check("pidgeot line finished typing", typedFrame ~= nil)

  for _ = 1, 30 do
    if #cries > 0 then break end
    U.wait(1)
  end
  check("PIDGEOT cry played", #cries == 1 and cries[1].species == "PIDGEOT")
  check("cry started after typing finished",
    cries[1] ~= nil and typedFrame ~= nil and cries[1].frame >= typedFrame)
  U.shot(game, DIR .. "/2262_01_pidgeot_cry_box.png")

  U.wait(180)
  check("box holds for A/B after the cry", game.stack:top() == box)
  U.shot(game, DIR .. "/2262_02_pidgeot_box_waits_for_a.png")

  U.tap(game, "a")
  for _ = 1, 120 do
    if game.stack:top() == game.overworld then break end
    U.wait(1)
  end
  check("A closes the pidgeot box", game.stack:top() == game.overworld)

  Sound.playCry = realPlayCry
  finish()
end
