return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local MODE = os.getenv("PROBE_MODE") or "log"
  local Pokemon = require("src.pokemon.Pokemon")
  local TextBox = require("src.render.TextBox")
  local Music = require("src.core.Music")

  local mon = Pokemon.new(game.data, "CHARMANDER", 12)
  mon.hp = 3
  table.insert(game.save.party, mon)
  local mon2 = Pokemon.new(game.data, "PIDGEY", 8)
  mon2.hp = 1
  table.insert(game.save.party, mon2)
  require("src.script.Flags").set(game.save, "EVENT_GOT_STARTER")

  U.teleport(game, "REDS_HOUSE_1F", 5, 5, "up")
  local ow = game.overworld

  local function topIsText()
    return getmetatable(game.stack:top()) == TextBox
  end

  U.tap(game, "a")
  U.wait(20)
  local started = false
  for _ = 1, 400 do
    if ow.fadeOverlay then started = true break end
    U.tap(game, "a")
    U.wait(3)
  end
  U.log("fade started:", started, "at frame", U.frame())
  local t0 = U.frame()

  if MODE == "log" then
    local prev
    for _ = 1, 900 do
      local ov = ow.fadeOverlay
      local a = ov and ov.alpha or nil
      local bgp = ov and ov.bgp and ov:bgp()
      local line = string.format(
        "f=%d alpha=%s bgp=%s color=%s jingle=%s text=%s",
        U.frame() - t0, a and string.format("%.3f", a) or "nil",
        bgp and string.format("%02X", bgp) or "--",
        ov and tostring(ov.color) or "-",
        tostring(Music.oneShotPlaying()), tostring(topIsText()))
      if line:gsub("^f=%d+ ", "") ~= prev then
        prev = line:gsub("^f=%d+ ", "")
        U.log("TRACE", line)
      end
      if not ov and U.frame() - t0 > 30 and topIsText() then
        U.log("TRACE done at", U.frame() - t0)
        break
      end
      U.wait(1)
    end
    U.log("probe log PASS")
    love.event.quit(0)
    return
  end

  local n = 0
  local function burst(count, gap, tag)
    for _ = 1, count do
      n = n + 1
      local ov = ow.fadeOverlay
      local name = string.format("%s/heal_f%03d_%s_a%s.png", DIR,
        U.frame() - t0, tag,
        ov and string.format("%02d", math.floor((ov.alpha or 0) * 99)) or "xx")
      U.shot(game, name)
      if gap > 0 then U.wait(gap) end
    end
  end

  burst(10, 1, "fadeout")
  burst(8, 12, "held")
  burst(10, 30, "hold2")
  for _ = 1, 900 do
    if not Music.oneShotPlaying() then break end
    U.wait(1)
  end
  burst(12, 1, "fadein")
  U.wait(10)
  n = n + 1
  U.shot(game, string.format("%s/heal_f%03d_after.png", DIR, U.frame() - t0))
  for _ = 1, 200 do
    if topIsText() then break end
    U.wait(1)
  end
  U.shot(game, string.format("%s/heal_f%03d_greattext.png", DIR, U.frame() - t0))
  U.log("shots taken:", n)
  love.event.quit(0)
end
