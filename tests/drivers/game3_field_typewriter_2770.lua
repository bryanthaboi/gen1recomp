local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fc_util").new("game3_field_typewriter_2770")

return function(game)
  if not F.boot(game) then return F.finish() end
  local Runtime = require("src.core.game3.runtime")
  local session = Runtime.getSession()
  local Options = require("src.core.game3.options")
  local Message = require("src.ui.game3.message")
  local Objects = require("src.core.game3.objects")
  local Player = require("src.core.game3.player")
  local Field = require("src.core.game3.field")
  local Space = require("src.core.game3.scripting.space")
  local Map = require("src.core.game3.map")
  local Fade = require("src.ui.game3.fade")
  local mapId = session.version == "emerald" and "EM_OLDALE_TOWN_POKEMON_CENTER_1F"
    or (session.version == "ruby" and "RU_OLDALE_TOWN_POKEMON_CENTER_1F")
    or (session.version == "sapphire" and "SA_OLDALE_TOWN_POKEMON_CENTER_1F")
    or "FR_VIRIDIAN_CITY_POKEMON_CENTER_1F"
  local function waitFor(pred, limit)
    for _ = 1, limit do
      if pred() then return true end
      U.wait(1)
    end
    return pred()
  end
  local function opened(tag, press)
    Map.load(nil, game, mapId, { x = 7, y = 7, facing = "up" })
    if not F.check(waitFor(function()
        return not Field.locked and not Fade.active and not (Space.vm and Space.vm:isRunning())
      end, 600), tag .. " map settles") then return nil end
    local eo = Objects.find(2)
    if not F.check(eo ~= nil, tag .. " npc exists") then return nil end
    eo.frozen = true
    Player.reset(eo.cellX, eo.cellY + 1, "up")
    Player.syncToHost(game)
    U.wait(2)
    press()
    if not F.check(waitFor(function() return Message.isOpen() end, 120), tag .. " message opens") then return nil end
    return true
  end
  local function closeOut()
    for _ = 1, 200 do
      if not Message.isOpen() and not (Space.vm and Space.vm:isRunning()) and not Field.locked then return end
      U.tap(game, "b")
      U.wait(2)
    end
  end
  for speed = 0, 2 do
    Options.set(session, "textSpeed", speed)
    local tag = session.version .. " speed" .. speed
    if opened(tag .. " tap", function() U.tap(game, "a") end) then
      local first = Message._revealed
      F.check(Message.isTyping() and first < Message._total,
        tag .. " opening A leaves page typing (revealed " .. first .. "/" .. Message._total .. ")")
      if speed == 0 then F.shot(game, "2770_" .. session.version .. "_01_typing.png", true) end
      F.check(waitFor(Message.isWaiting, 1600), tag .. " page finishes typing")
      if speed == 0 then F.shot(game, "2770_" .. session.version .. "_02_done.png", true) end
      closeOut()
    end
    if speed < 2 and opened(tag .. " hold", function()
        table.insert(game.input.pressQueue, "a")
        game.input.state.a = true
        U.wait(8)
      end) then
      U.wait(4)
      game.input.state.a = false
      F.check(Message.isTyping() and Message._revealed < 6,
        tag .. " held opening A does not speed up print (revealed " .. Message._revealed .. ")")
      closeOut()
    end
  end
  F.finish()
end
