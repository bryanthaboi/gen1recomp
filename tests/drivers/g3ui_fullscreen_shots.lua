local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/g3ui_fullscreen"

local BULBASAUR, CHARMANDER = 1, 4

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS g3ui_fullscreen_shots")
    love.event.quit(0)
  else
    print("FAIL g3ui_fullscreen_shots failures=" .. failures)
    love.event.quit(1)
  end
end

local function fakeChannel()
  local ch = { relay = true, sent = {}, inbox = {}, playerList = { { seat = 0, name = "RED" }, { seat = 1, name = "BLUE" } } }
  function ch:send(msg) self.sent[#self.sent + 1] = msg end
  function ch:take(t)
    for i, m in ipairs(self.inbox) do
      if m.type == t then return table.remove(self.inbox, i) end
    end
    return nil
  end
  function ch:seat() return 0 end
  function ch:players() return self.playerList end
  function ch:closed() return false end
  function ch:leave() end
  return ch
end

return function(game)
  print("PASS driver_started")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Party = require("src.core.game3.party")
  local Stack = require("src.ui.game3.stack")
  local Renderer = require("src.render.Renderer")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local PartyMenu = require("src.ui.game3.party_menu")
  local TrainerCard = require("src.ui.game3.trainer_card")
  local LinkMenu = require("src.ui.game3.link_menu")
  local Chat = require("src.core.game3.link.chat")
  local UnionChat = require("src.ui.game3.union_chat")

  local worldPasses = 0
  local beginWorldPass = Renderer.beginWorldPass
  Renderer.beginWorldPass = function(self, ...)
    worldPasses = worldPasses + 1
    return beginWorldPass(self, ...)
  end
  local frames = 0
  local beginFrame = Renderer.beginFrame
  Renderer.beginFrame = function(self, ...)
    frames = frames + 1
    return beginFrame(self, ...)
  end
  local function worldRan()
    worldPasses, frames = 0, 0
    for _ = 1, 4000 do
      if frames >= 3 then break end
      U.wait(1)
    end
    return worldPasses > 0
  end

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  Party.giveMon(session, BULBASAUR, 12)
  Party.giveMon(session, CHARMANDER, 10)
  U.wait(30)

  U.shot(game, DIR .. "/g3ui_field.png")
  result(worldRan() and not Stack.fullscreen(), "bare field keeps the world pass")

  Message.show("Would you like to do something?")
  U.wait(90)
  Choice.yesNo(function() end)
  U.wait(20)
  U.shot(game, DIR .. "/g3ui_yesno.png")
  result(Choice.left == 21 and Choice.top == 9 and worldRan(),
    "field yes/no at 21,9 over the world pass")
  Choice.reset()
  Message.close()
  U.wait(10)

  local function screen(label, open, close)
    open()
    U.wait(90)
    U.shot(game, DIR .. "/g3ui_" .. label .. ".png")
    result(Stack.fullscreen() and not worldRan(), label .. " skips the world pass")
    close()
    U.wait(30)
  end

  screen("party_menu", function() PartyMenu.show(session.party, nil, { session = session }) end, PartyMenu.close)
  screen("trainer_card", function() TrainerCard.show({ session = session }) end, TrainerCard.close)
  screen("wireless_monitor", function() LinkMenu.show({}) end, LinkMenu.close)

  local function pixelAt(image, x, y)
    local canvas = love.graphics.newCanvas(240, 160)
    love.graphics.push("all")
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(image, 0, 0)
    love.graphics.pop()
    local r, g, b = canvas:newImageData():getPixel(x, y)
    return string.format("%d,%d,%d", r * 255 + 0.5, g * 255 + 0.5, b * 255 + 0.5)
  end
  local art = LinkMenu.loadArt()
  local steady = art ~= nil
  local base = art and pixelAt(art.image, 100, 40)
  local barPixels = { { 72, 153 }, { 90, 154 }, { 165, 153 } }
  local barSeen = {}
  for i = 1, #barPixels do barSeen[i] = { n = 0 } end
  for k = 0, LinkMenu.ANIM_COUNT - 1 do
    local image = art and LinkMenu.variant(k)
    if art and pixelAt(image, 100, 40) ~= base then steady = false end
    for i, p in ipairs(barPixels) do
      local c = image and pixelAt(image, p[1], p[2]) or "nil"
      if not barSeen[i][c] then
        barSeen[i][c] = true
        barSeen[i].n = barSeen[i].n + 1
      end
    end
  end
  result(steady, "the monitor grid keeps its colour through every CyclePalette step (" .. tostring(base) .. ")")
  local flowing = art ~= nil
  local counts = {}
  for i = 1, #barPixels do
    counts[i] = tostring(barSeen[i].n)
    if barSeen[i].n < 2 then flowing = false end
  end
  result(flowing, "the y 153-154 wave bars change colour across CyclePalette steps (distinct " ..
    table.concat(counts, "/") .. ")")
  screen("union_chat", function()
    Chat.start({ channel = fakeChannel(), onDone = function() end })
  end, function()
    Chat.reset()
    UnionChat.close()
  end)

  U.shot(game, DIR .. "/g3ui_field_after.png")
  result(worldRan() and not Stack.fullscreen(), "field returns with the world pass")

  local Map = require("src.core.game3.map")
  Map.load(nil, game, "FR_PALLET_TOWN", { x = 12, y = 10, facing = "down" })
  U.wait(60)
  local wx, wy = love.window.getPosition()
  love.window.updateMode(1600, 768, { x = wx, y = wy })
  U.wait(60)
  local ww = love.graphics.getWidth()
  result(ww == 1600, "the window is wide (" .. tostring(ww) .. ")")
  U.shot(game, DIR .. "/g3ui_wide_field.png")
  result(worldRan() and not Stack.fullscreen(), "wide field fills the side strips with the world pass")
  screen("wide_party_menu", function() PartyMenu.show(session.party, nil, { session = session }) end, PartyMenu.close)
  screen("wide_trainer_card", function() TrainerCard.show({ session = session }) end, TrainerCard.close)
  screen("wide_wireless_monitor", function() LinkMenu.show({}) end, LinkMenu.close)
  screen("wide_union_chat", function()
    Chat.start({ channel = fakeChannel(), onDone = function() end })
  end, function()
    Chat.reset()
    UnionChat.close()
  end)
  finish()
end
