local U = require("tests.drivers.util")
local Common = require("tests.drivers.g3link_direct_common")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/g3link"

return function(game)
  print("PASS driver_started")
  local W = Common.new(game, "g3link_direct_choose", DIR)
  local result = W.result
  if not result(W.boot(), "new game reached the game3 field") then return W.finish() end
  W.session.trainerId = 24680
  W.Party.giveMon(W.session, 25, 12)
  W.Party.giveMon(W.session, 1, 10)
  W.useRelay()
  print("[driver] relay mode=" .. W.mode)

  W.Map.load(nil, game, Common.CENTER_2F, { x = 10, y = 4, facing = "up" })
  W.wait(60)
  W.Flags.setFlag(W.Space.store, W.ctx(), Common.FLAG_SYS_POKEDEX_GET, true)
  W.place(10, 4, "up")
  W.wait(12)
  result(W.Client.state() == "offline", "the Client starts offline")

  U.tap(game, "a")
  local asked = W.waitFor(function() return W.Link.connectPrompt ~= nil and W.Choice.active end, 8, 600)
  if not result(asked, "the Direct Corner attendant offers to connect") then
    W.frame("g3link_direct_connect_failed")
    return W.finish()
  end
  result(W.pageHas(W.Strings("Connect to the Wireless Club?")), "Connect to the Wireless Club?")
  W.wait(4)
  W.shot("g3link_direct_connect_prompt")
  U.tap(game, "a")
  local online = W.waitFor(function() return W.Link.connectPrompt == nil end, 10, 600)
  if not result(online and W.Client.state() == "online", "YES connects to the relay") then return W.finish() end

  local function atModes() return W.Direct.isOpen() and W.Direct.view == "modes" end
  local modes = W.drive(atModes, 30)
  if not result(modes, "TRADE CENTER > save > the AUTO / CHOOSE / SET PIN box") then
    W.frame("g3link_direct_modes_failed")
    return W.finish()
  end
  W.wait(10)
  W.shot("g3link_direct_modes")

  U.tap(game, "a")
  local waitText = W.RomText.plain("CableClub_Text_PleaseWaitBCancel")
  local waiting = W.waitFor(function()
    return W.Direct.isOpen() and W.Direct.view == "wait" and W.pageHas(waitText)
  end, 8, 300)
  result(waiting, "AUTO queues and shows the cart's wait box")
  local queued = W.waitFor(function()
    local d = W.Client.direct()
    return d ~= nil and d.queued == true and d.activity == "trade"
  end, 5, 120)
  result(queued, "direct_state: queued AUTO for trade")
  if W.mode == "fake" then
    local q = W.relay.queue["a0000001"]
    result(q ~= nil and q.auto == true, "the relay holds the AUTO queue entry")
  end
  W.waitFor(function() return W.Message.isWaiting() end, 5, 600)
  W.wait(20)
  W.shot("g3link_direct_auto_wait")
  U.tap(game, "b")
  result(W.drive(atModes, 15), "B leaves the queue and returns to the mode box")
  if W.mode == "fake" then result(W.relay.queue["a0000001"] == nil, "the queue entry is gone") end

  local blue = W.partner("b0000002", "BLUE", { name = "BLUE", trainerId = 8738, gender = 0, version = "leafgreen" })
  local green = W.partner("c0000003", "GREEN", { name = "GREEN", trainerId = 31337, gender = 1, version = "firered" })
  W.waitFor(function() return blue.online() and green.online() end, 8, 120)
  blue.queue({ activity = "trade", ruleset = "g3_link", auto = true, profile = W.withRuleset("g3_link"),
    avatar = blue.avatar, preview = { 4 } })
  green.queue({ activity = "trade", ruleset = "g3_link", auto = false, pin = "1357",
    profile = W.withRuleset("g3_link"), avatar = green.avatar, preview = { 7 } })
  W.wait(20)

  W.tap("down")
  W.tap("a")
  local chooseText = W.RomText.plain(W.RomText.key("gTexts_UR_ChooseTrainer", 3))
  local listed = W.waitFor(function()
    local D = W.Direct
    return D.isOpen() and D.view == "choose" and D.list and D.list.items[2] and D.list.items[2].row ~= nil
  end, 10, 300)
  if not result(listed, "CHOOSE lists the AUTO trainer and the PIN room") then
    local Json = require("src.link.Json")
    print("[driver] entries=" .. Json.encode(W.Client.directEntries("trade") or {}))
    print("[driver] RED direct=" .. Json.encode(W.Client.direct() or {}) .. " room="
      .. tostring(W.Client.room() and W.Client.room().room) .. " you=" .. Json.encode(W.Client.you() or {}))
    for _, P in ipairs({ blue, green }) do
      print("[driver] " .. P.name .. " online=" .. tostring(P.online())
        .. (P.C and (" err=" .. tostring(P.C.error()) .. " direct=" .. Json.encode(P.C.direct() or {})
          .. " room=" .. tostring(P.C.room() and P.C.room().room)) or ""))
    end
    W.frame("g3link_direct_choose_failed")
    return W.finish()
  end
  result(W.waitFor(function() return W.pageHas(chooseText) end, 5, 300), "Please choose the TRAINER to trade with.")
  local blueSlot, greenSlot
  for i = 1, 2 do
    local row = W.Direct.list.items[i].row
    if row.name == "BLUE" then blueSlot = i end
    if row.name == "GREEN" then greenSlot = i end
  end
  result(blueSlot and W.Direct.list.items[blueSlot].row.kind == "player", "BLUE is listed as an AUTO trainer")
  result(greenSlot and W.Direct.list.items[greenSlot].row.locked == true, "GREEN's room is listed with a lock")
  W.waitFor(function() return W.Message.isWaiting() end, 5, 600)
  W.shot("g3link_direct_choose_new")
  W.wait(80)
  if greenSlot and greenSlot > 1 then W.tap("down") end
  W.wait(10)
  W.shot("g3link_direct_choose_list")

  W.tap("a")
  result(W.waitFor(function() return W.PinEntry.isOpen() and W.PinEntry.mode == "enter" end, 5, 60),
    "a locked room opens the PIN entry")
  for _ = 1, 2 do W.tap("down") end
  W.tap("right")
  for _ = 1, 3 do W.tap("up") end
  W.wait(30)
  W.shot("g3link_direct_pin_enter")
  W.tap("start")
  W.tap("a")
  local wrong = W.waitFor(function()
    return not W.PinEntry.isOpen() and W.pageHas(W.Strings("The PIN didn't match."))
  end, 8, 300)
  result(wrong, "8300 is refused: The PIN didn't match.")
  W.waitFor(function() return W.Message.isWaiting() end, 5, 300)
  W.shot("g3link_direct_pin_wrong")
  W.tap("a")
  result(W.waitFor(function() return W.pageHas(chooseText) and not W.Direct.frozen end, 5, 300),
    "the wrong PIN fades back to the list")
  W.wait(10)
  W.tap("a")
  result(W.waitFor(function() return W.PinEntry.isOpen() and W.PinEntry.mode == "enter" end, 5, 60),
    "the locked room asks for the PIN again")

  local digits = { 1, 3, 5, 7 }
  for i, d in ipairs(digits) do
    for _ = 1, d do W.tap("up", 2) end
    if i < 4 then W.tap("right") end
  end
  W.tap("a")
  local paired = W.waitFor(function() return W.Link.link ~= nil end, 10, 300)
  if not result(paired, "the right PIN seats RED in GREEN's room and the link attaches") then
    W.frame("g3link_direct_join_failed")
    return W.finish()
  end
  result(W.Link.link.seat == 1, "RED joins as seat 1")
  W.sendHello(green, 0)
  local directed = W.RomText.plain("CableClub_Text_DirectYouToYourRoom")
  result(W.waitFor(function() return W.pageHas(directed:match("^[^\n]+")) end, 8, 300),
    "the attendant directs RED to the Trade Center")
  local warped = W.waitFor(function() return W.Space.mapId == Common.TRADE_CENTER end, 15, 900)
  if not result(warped, "RED walks into the Trade Center") then
    W.frame("g3link_direct_no_warp")
    return W.finish()
  end
  result(W.waitFor(function() return W.Link.link and W.Link.link:isReady() end, 8, 300),
    "the Game3 trade linkup handshake completed")
  W.wait(60)
  W.frame("g3link_direct_trade_linkup")
  local room = W.Client.room()
  result(room ~= nil and room.stage == "battling" and room.locked == true, "a locked direct room")
  W.finish()
end
