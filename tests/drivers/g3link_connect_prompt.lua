local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/g3link"

local CENTER_2F = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F"
-- pokefirered/include/constants/flags.h:1375
local FLAG_SYS_POKEDEX_GET = 0x829
-- pokefirered/include/constants/vars.h:328
local VAR_RESULT = 0x800D

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  local Link = package.loaded["src.core.game3.link"]
  if Link then pcall(Link.reset) end
  local Connect = package.loaded["src.online.Connect"]
  if Connect and Connect.disconnect then pcall(Connect.disconnect) end
  if failures == 0 then
    print("PASS g3link_connect_prompt")
    love.event.quit(0)
  else
    print("FAIL g3link_connect_prompt failures=" .. failures)
    love.event.quit(1)
  end
end

local function now() return love.timer.getTime() end

return function(game)
  print("PASS driver_started")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Player = require("src.core.game3.player")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Link = require("src.core.game3.link")
  local Strings = require("src.core.Strings")
  local RomText = require("src.core.game3.rom_text")
  local WirelessIcon = require("src.ui.game3.wireless_icon")
  local Client = require("src.online.Client")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  local function ctx() return Space.vm and Space.vm.ctx end
  local function getVar(id) return tonumber(Flags.getVar(Space.store, ctx(), id)) or 0 end
  local function place(x, y, facing)
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    game.session.x, game.session.y, game.session.facing = x, y, facing
  end
  local function busy()
    return (Space.vm and Space.vm:isRunning()) or Message.isOpen() or Choice.active
  end
  local function pageHas(text)
    local page = Message.isOpen() and Message.currentPage() or ""
    return page:find(text, 1, true) ~= nil
  end
  local function waitFor(cond, seconds, frames)
    local t0 = now()
    local n = 0
    while not cond() do
      U.wait(1)
      n = n + 1
      if now() - t0 > (seconds or 5) and n > (frames or 60) then return false end
    end
    return true
  end
  local function settle()
    local t0 = now()
    while busy() and now() - t0 < 8 do
      if Choice.active then
        U.tap(game, "b")
      elseif Message.isOpen() then
        U.tap(game, "a")
      end
      U.wait(8)
    end
  end
  local function talk()
    place(6, 4, "up")
    U.wait(12)
    U.tap(game, "a")
    return waitFor(function() return Link.connectPrompt ~= nil end, 5, 300)
  end

  Map.load(nil, game, CENTER_2F, { x = 6, y = 4, facing = "up" })
  U.wait(90)
  Flags.setFlag(Space.store, ctx(), FLAG_SYS_POKEDEX_GET, true)
  result(Space.mapId == CENTER_2F, "on the Viridian Pokemon Center 2F")
  result(Client.state() == "offline", "the Client starts offline")
  result(WirelessIcon.anim() == nil, "offline: no wireless icon")

  if not result(talk(), "the Union Room attendant asks to connect") then return finish() end
  result(pageHas(Strings("Connect to the Wireless Club?")), "with the connect question")
  result(waitFor(function() return Choice.active end, 5, 600), "YES/NO is offered")
  U.wait(4)
  U.still(game, DIR .. "/g3link_connect_prompt.png")

  U.tap(game, "down")
  U.wait(4)
  U.tap(game, "a")
  result(waitFor(function() return Link.connectPrompt == nil end, 3, 60), "NO resumes the script")
  result(getVar(VAR_RESULT) == 0, "IsWirelessAdapterConnected is FALSE after NO")
  local notConnected = RomText.plain("CableClub_Text_UnionRoomAdapterNotConnected"):match("^[^\n]+")
  result(waitFor(function() return pageHas(notConnected) end, 5, 300),
    "the cart's Union Room adapter text follows")
  waitFor(function() return not Message.isTyping() end, 5, 600)
  U.wait(4)
  U.still(game, DIR .. "/g3link_union_adapter_not_connected.png")
  settle()

  if not result(talk(), "talking again asks again") then return finish() end
  result(waitFor(function() return Choice.active end, 5, 600), "YES/NO again")
  U.tap(game, "a")

  if require("src.link.Handshake").linkModified(game) then
    print("[driver] this identity runs link-affecting mods: checking the mismatch path")
    local reason = Link.reasonText("mods"):match("^%S+%s+%S+")
    result(waitFor(function() return pageHas(reason) end, 3, 60), "the mods reason line is shown")
    result(Client.state() == "offline", "nothing connected")
    waitFor(function() return not Message.isTyping() end, 5, 600)
    U.wait(4)
    U.still(game, DIR .. "/g3link_mods_mismatch.png")
    local t0 = now()
    while Link.connectPrompt ~= nil and now() - t0 < 5 do
      U.tap(game, "a")
      U.wait(10)
    end
    result(getVar(VAR_RESULT) == 0, "IsWirelessAdapterConnected is FALSE for a modded game")
    result(waitFor(function() return pageHas(notConnected) end, 5, 300),
      "then the cart's adapter text")
    settle()
    print("PASS mods_mismatch")
    return finish()
  end

  local connecting = waitFor(function() return pageHas(Strings("Connecting...")) end, 3, 30)
  result(connecting, "Connecting... is shown")
  waitFor(function() return Message.isWaiting() or Link.connectPrompt == nil end, 2, 120)
  local okLoad, errLoad = pcall(WirelessIcon.load)
  print("[driver] icon load=" .. tostring(okLoad) .. " " .. tostring(errLoad)
    .. " map=" .. tostring(Space.mapId) .. " onLinkMap=" .. tostring(WirelessIcon.onLinkMap(Space.mapId)))
  result(WirelessIcon.anim() == "searching" or WirelessIcon.anim() == "3bars",
    "the wireless icon is up (" .. tostring(WirelessIcon.anim()) .. ")")
  U.still(game, DIR .. "/g3link_connecting.png")

  local online = waitFor(function() return Link.connectPrompt == nil end, 10, 600)
  print("[driver] client=" .. tostring(Client.state()) .. " err=" .. tostring(Client.error()))
  if not result(online, "the connection finished") then return finish() end
  result(Client.state() == "online", "the Client is online on the relay")
  result(Link.adapterConnected(), "the accepted profile is the live g3 profile")
  result(getVar(VAR_RESULT) == 1, "IsWirelessAdapterConnected is TRUE")
  local profiles = Client.profiles()
  result(#profiles == 1 and profiles[1].engine == 3 and profiles[1].rulesetId == "g3_link",
    "the session carries exactly the live g3_link profile")
  local welcome = RomText.plain("CableClub_Text_WelcomeUnionRoomEnter"):match("^[^\n]+")
  result(waitFor(function() return pageHas(welcome) end, 5, 300), "the attendant welcomes to the Union Room")
  result(WirelessIcon.anim() == "3bars", "online: three bars")
  U.wait(30)
  waitFor(function() return WirelessIcon.frame() == 4 end, 2, 60)
  U.shot(game, DIR .. "/g3link_union_welcome.png")
  settle()
  U.wait(30)
  if result(Space.mapId == CENTER_2F and not busy(), "back on the 2F field while online") then
    result(Client.state() == "online" and WirelessIcon.anim() == "3bars", "the field keeps the three-bar icon")
    waitFor(function() return WirelessIcon.frame() == 4 end, 2, 60)
    U.still(game, DIR .. "/g3link_online_field_icon.png")
  end

  Map.load(nil, game, "FR_PALLET_TOWN", { x = 5, y = 7, facing = "down" })
  U.wait(60)
  result(not WirelessIcon.onLinkMap(Space.mapId), "the icon stays off the field outside the 2F")
  finish()
end
