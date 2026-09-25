local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/g3link"

local CENTER_2F = "FR_VIRIDIAN_CITY_POKEMON_CENTER_2F"
local Plaza = require("src.core.game3.link.union_plaza_map")
-- pokefirered/include/constants/flags.h:1375
local FLAG_SYS_POKEDEX_GET = 0x829
local ROLE = os.getenv("B4_ROLE") or "A"
local NAMES = { A = "ALICE", B = "BOB", C = "CAROL" }
local NAME = NAMES[ROLE]
-- pokefirered/include/constants/species.h:10
local CHARIZARD, CATERPIE, BULBASAUR = 6, 10, 1

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. "[" .. ROLE .. "] " .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  local Link = package.loaded["src.core.game3.link"]
  if Link then pcall(Link.reset) end
  local Client = package.loaded["src.online.Client"]
  if Client then pcall(Client.disconnect) end
  print((failures == 0 and "PASS" or "FAIL") .. " g3link_union_plaza_live role=" .. ROLE .. " failures=" .. failures)
  love.event.quit(failures == 0 and 0 or 1)
  coroutine.yield()
end

local function now() return love.timer.getTime() end

return function(game)
  print("PASS driver_started")
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = NAME })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Player = require("src.core.game3.player")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Party = require("src.core.game3.party")
  local Link = require("src.core.game3.link")
  local Union = require("src.core.game3.link.union_room")
  local LB = require("src.core.game3.link.battle")
  local Chat = require("src.core.game3.link.chat")
  local Screen = require("src.ui.game3.union_room")
  local Client = require("src.online.Client")
  local Natives = require("src.core.game3.scripting.natives")
  local MapCatalog = require("src.import.gba.map_catalog")

  local session = Runtime.getSession()
  session.name = NAME
  if ROLE == "A" then Party.giveMon(session, CHARIZARD, 70)
  elseif ROLE == "B" then Party.giveMon(session, CATERPIE, 3)
  else Party.giveMon(session, BULBASAUR, 5) end

  local function ctx() return Space.vm and Space.vm.ctx end
  local function place(x, y, facing)
    Player.cellX, Player.cellY = x, y
    Player.px, Player.py = x * 16, y * 16
    Player.targetX, Player.targetY = x, y
    Player.facing = facing
    game.session.x, game.session.y, game.session.facing = x, y, facing
  end
  local function waitFor(cond, seconds, onFrame)
    local t0 = now()
    while not cond() do
      if onFrame then onFrame() end
      U.wait(1)
      if now() - t0 > (seconds or 5) then return false end
    end
    return true
  end
  local function pageThrough()
    if Message.isOpen() and Message.isWaiting() and (Message._page or 1) < #(Message._pages or {}) then
      U.tap(game, "a")
    end
  end
  local function findByName(name)
    for slot = 1, Plaza.CAP do
      local p = Union.players[slot]
      if p and not p.gone and p.name == name then return slot, p end
    end
    return nil
  end
  local function talkTo(slot)
    local x, y = Plaza.cellFor(slot)
    place(x, y + 1, "up")
    U.wait(4)
    U.tap(game, "a")
  end
  local function mashBattle(seconds)
    local sawBattle = waitFor(function() return LB.state == "battle" end, 30, pageThrough)
    if not sawBattle then return false, false end
    local t0, k = now(), 0
    while LB.state == "battle" or LB.state == "setup" do
      k = k + 1
      if k % 8 == 0 then U.tap(game, "a") else U.wait(1) end
      if now() - t0 > seconds then return true, false end
    end
    return true, waitFor(function() return Union.state == "main" end, 30, function()
      if Message.isOpen() then U.tap(game, "a") end
    end)
  end

  local live = Link.liveProfile()
  if not result(live ~= nil, "live g3 profile (vanilla)") then return finish() end
  Link.connect()
  if not result(waitFor(function() return Client.state() == "online" end, 20), "online on the local relay") then
    print("[driver] client state=" .. tostring(Client.state()) .. " err=" .. tostring(Client.error()))
    return finish()
  end

  Map.load(nil, game, CENTER_2F, { x = 5, y = 1, facing = "up" })
  U.wait(30)
  Flags.setFlag(Space.store, ctx(), FLAG_SYS_POKEDEX_GET, true)
  place(5, 1, "up")
  U.wait(5)
  -- pokefirered/data/specials.inc:12
  Natives.special(ctx(), 0x01, Space.vm.adapters)
  local slotKey = MapCatalog.slotKeyFor("FR_UNION_ROOM") or ""
  local group, num = slotKey:match("(%d+)%D+(%d+)")
  -- pokefirered/data/scripts/cable_club.inc:797
  Space.vm.adapters.warp(tonumber(group), tonumber(num), 0xFF, 7, 11, function() end, "warpspinenter")
  if not result(waitFor(function() return Space.mapId == Plaza.MAP_ID and Union.state == "main" end, 30),
      "entered the plaza over the real relay") then
    return finish()
  end
  result(waitFor(function() return Client.plaza() ~= nil end, 10), "plaza_state from the relay")
  local mySlot = Client.plaza() and Client.plaza().you
  print("[driver] " .. ROLE .. " slot=" .. tostring(mySlot) .. " instance=" .. tostring(Client.plaza() and Client.plaza().instance)
    .. " cap=" .. tostring(Client.plaza() and Client.plaza().cap) .. " rev=" .. tostring(Client.plaza() and Client.plaza().rev))
  result(Client.plaza() and Client.plaza().cap == 40, "the relay reports a 40-cap plaza")

  if ROLE == "A" then
    local slotB
    result(waitFor(function() slotB = findByName("BOB") return slotB ~= nil end, 60), "BOB appears in the plaza")
    if not slotB then return finish() end
    U.wait(60)
    local bx, by = Plaza.cellFor(slotB)
    print("[driver] A sees BOB on slot " .. slotB .. " cell " .. bx .. "," .. by)
    U.still(game, DIR .. "/live_a_sees_bob.png")
    talkTo(slotB)
    result(waitFor(function() return Screen.isOpen() and Screen.mode == "activity" end, 10, pageThrough),
      "talking to BOB opens the do-something prompt")
    Screen.cursor = 2
    U.tap(game, "a")
    local started, back = mashBattle(180)
    result(started, "the battle with BOB started")
    result(back, "the battle ended and ALICE is back in the Union Room")
    result(waitFor(function() return Space.mapId == Plaza.MAP_ID end, 10), "still on the plaza map")
    U.wait(90)
    local slotB2 = findByName("BOB")
    result(Client.plaza() and Client.plaza().you == mySlot, "ALICE kept slot " .. tostring(mySlot))
    result(slotB2 == slotB, "BOB is back on slot " .. tostring(slotB))
    local v = Union.vobj(slotB)
    result(v and v.visible and v.x == bx and v.y == by, "BOB's avatar stands on the same cell")
    U.still(game, DIR .. "/live_a_after_battle.png")
    U.wait(120)
    talkTo(slotB)
    result(waitFor(function() return Screen.isOpen() and Screen.mode == "activity" end, 10, pageThrough),
      "BOB's menu again")
    Screen.cursor = 3
    U.tap(game, "a")
    result(waitFor(function() return Chat.isActive() end, 40, pageThrough), "ALICE and BOB are chatting")
    local three = waitFor(function()
      local room = Client.room()
      return room and room.players and #room.players >= 3
    end, 120)
    result(three, "CAROL joined the chat")
    U.wait(120)
    U.still(game, DIR .. "/live_a_chat_three.png")
    Chat.stop("left")
    waitFor(function() return Union.state == "main" end, 10)
  elseif ROLE == "B" then
    result(waitFor(function() return Choice.active end, 120, pageThrough), "ALICE's battle request rings BOB")
    U.wait(10)
    U.tap(game, "a")
    local started, back = mashBattle(180)
    result(started, "the battle with ALICE started")
    result(back, "BOB is back in the Union Room")
    U.wait(90)
    result(Client.plaza() and Client.plaza().you == mySlot, "BOB kept slot " .. tostring(mySlot))
    local slotA = findByName("ALICE")
    local ax, ay = Plaza.cellFor(slotA or 0)
    local v = slotA and Union.vobj(slotA)
    result(v and v.visible and v.x == ax and v.y == ay, "ALICE's avatar stands on her cell")
    U.still(game, DIR .. "/live_b_after_battle.png")
    result(waitFor(function() return Choice.active end, 120, pageThrough), "ALICE's chat request rings BOB")
    U.wait(10)
    U.tap(game, "a")
    result(waitFor(function() return Chat.isActive() end, 40, pageThrough), "BOB is chatting")
    waitFor(function()
      local room = Client.room()
      return room and room.players and #room.players >= 3
    end, 120)
    waitFor(function() return not Chat.isActive() end, 60)
    Chat.stop("left")
    waitFor(function() return Union.state == "main" end, 10)
  else
    local slotB
    result(waitFor(function()
      slotB = findByName("BOB")
      local p = slotB and Union.players[slotB]
      return p and (p.activity % Union.IN_UNION_ROOM) == Union.ACTIVITY.CHAT
    end, 300), "CAROL sees BOB chatting")
    if not slotB then return finish() end
    U.wait(30)
    talkTo(slotB)
    result(waitFor(function() return Choice.active end, 15, pageThrough), "the join-chat prompt")
    U.still(game, DIR .. "/live_c_join_prompt.png")
    U.tap(game, "a")
    result(waitFor(function() return Chat.isActive() end, 40, pageThrough), "CAROL joined the chat")
    U.wait(120)
    U.still(game, DIR .. "/live_c_chat.png")
    Chat.stop("left")
    waitFor(function() return Union.state == "main" end, 10)
  end
  finish()
end
