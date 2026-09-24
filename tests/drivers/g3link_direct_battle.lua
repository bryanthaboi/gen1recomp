local U = require("tests.drivers.util")
local Common = require("tests.drivers.g3link_direct_common")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/g3link"

return function(game)
  print("PASS driver_started")
  local W = Common.new(game, "g3link_direct_battle", DIR)
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
  W.Link.connect()
  if not result(W.waitFor(function() return W.Link.adapterConnected() end, 10, 300),
      "online on the relay with the live profile") then
    return W.finish()
  end

  W.wait(12)
  U.tap(game, "a")
  local t0 = Common.now()
  while not W.Choice.active and Common.now() - t0 < 10 do
    if W.Message.isOpen() and W.Message.isWaiting() then U.tap(game, "a") end
    W.wait(4)
  end
  if not result(W.Choice.active, "TRADE CENTER / COLOSSEUM") then
    W.frame("g3link_direct_battle_attendant_failed")
    return W.finish()
  end
  W.tap("down")
  W.tap("a")
  local function atModes() return W.Direct.isOpen() and W.Direct.view == "modes" end
  if not result(W.drive(atModes, 30), "COLOSSEUM > SINGLE BATTLE > save > the mode box") then
    W.frame("g3link_direct_battle_modes_failed")
    return W.finish()
  end
  W.tap("down")
  W.tap("down")
  W.tap("a")
  if not result(W.waitFor(function() return W.PinEntry.isOpen() and W.PinEntry.mode == "set" end, 5, 60),
      "SET PIN opens the PIN entry") then
    return W.finish()
  end
  local digits = { 2, 4, 6, 8 }
  for i, d in ipairs(digits) do
    for _ = 1, d do W.tap("up", 2) end
    if i < 4 then W.tap("right") end
  end
  W.wait(24)
  W.shot("g3link_direct_pin_set")
  W.tap("a")
  result(W.waitFor(function()
    return W.pageHas(W.Strings("Use this PIN?")) and W.Choice.active
  end, 5, 300), "Use this PIN?")
  W.wait(6)
  W.shot("g3link_direct_pin_use")
  W.tap("a")
  result(W.waitFor(function()
    return W.pageHas(W.Strings("Let AUTO players join?")) and W.Choice.active
  end, 5, 300), "Let AUTO players join?")
  W.wait(6)
  W.shot("g3link_direct_pin_auto")
  W.tap("a")

  local hosting = W.waitFor(function()
    local d = W.Client.direct()
    return d ~= nil and d.hosting ~= nil and W.Direct.isOpen() and W.Direct.view == "wait"
  end, 8, 300)
  if not result(hosting, "direct_state: hosting a PIN room") then
    W.frame("g3link_direct_pin_host_failed")
    return W.finish()
  end
  local room = W.Client.room()
  result(room ~= nil and room.locked == true, "the room is locked")
  result(room ~= nil and room.auto == true, "and open to AUTO players")
  W.waitFor(function() return W.Message.isWaiting() end, 5, 600)
  W.wait(10)
  W.shot("g3link_direct_pin_hosting")

  local blue = W.partner("b0000002", "BLUE", { name = "BLUE", trainerId = 8738, gender = 0, version = "leafgreen" })
  W.waitFor(function() return blue.online() end, 8, 120)
  blue.queue({ activity = "battle_single", ruleset = "g3_single", auto = true,
    profile = W.withRuleset("g3_single"), avatar = blue.avatar, preview = { 4 } })
  local paired = W.waitFor(function() return W.Link.link ~= nil end, 10, 300)
  if not result(paired, "an AUTO trainer pairs into the PIN room without the PIN") then
    W.frame("g3link_direct_battle_pair_failed")
    return W.finish()
  end
  result(W.Link.link.seat == 0, "the host keeps seat 0")
  W.sendHello(blue, 1)
  local warped = W.waitFor(function() return W.Space.mapId == Common.COLOSSEUM end, 15, 900)
  if not result(warped, "RED walks into the Colosseum") then
    W.frame("g3link_direct_battle_no_warp")
    return W.finish()
  end
  result(W.waitFor(function() return W.Link.link and W.Link.link:isReady() end, 8, 300),
    "the Game3 battle linkup handshake completed")
  W.wait(60)
  W.frame("g3link_direct_battle_linkup")
  room = W.Client.room()
  result(room ~= nil and room.stage == "battling" and room.match ~= nil, "match_start dealt")
  W.finish()
end
