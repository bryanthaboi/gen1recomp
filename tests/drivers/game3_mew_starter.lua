local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_mew_starter"

local MEW, CHARMANDER = 151, 4
local VAR_TEMP_2 = 0x4002
local VAR_OAKS_LAB_SCENE = 0x4055

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS game3_mew_starter")
    love.event.quit(0)
  else
    print("FAIL game3_mew_starter failures=" .. failures)
    love.event.quit(1)
  end
end

local function endsWith(s, tail)
  return type(s) == "string" and s:sub(-#tail) == tail
end

return function(game)
  for _ = 1, 600 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  local loader = game.mods
  local mod = loader and loader.mods and loader.mods.example_mew_starter
  if not result(mod ~= nil and mod.enabled and mod.state == "loaded",
      "example_mew_starter loaded on firered (state=" .. tostring(mod and mod.state)
      .. " skip=" .. tostring(mod and mod.skipReason) .. ")") then
    return finish()
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(180)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Pokemon = require("src.core.game3.pokemon")
  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the field") then return finish() end
  session.party = {}

  Map.load(nil, game, "FR_OAKS_LAB", { x = 8, y = 5, facing = "up" })
  game.session.x, game.session.y, game.session.facing = 8, 5, "up"
  U.wait(90)
  session = Runtime.getSession()

  result(Space.vm ~= nil and Space.store ~= nil, "script VM active in FR_OAKS_LAB")
  Flags.setVar(Space.store, Space.vm.ctx, VAR_OAKS_LAB_SCENE, 2)

  local Objects = require("src.core.game3.objects")
  local ball
  for _, lid in ipairs(Objects.listActive()) do
    local eo = Objects.find(lid)
    if eo and eo.scriptKey == "g3:08169dae" then ball = eo end
  end
  if not result(ball ~= nil, "Charmander ball object on the table") then return finish() end
  Map.load(nil, game, "FR_OAKS_LAB", { x = ball.cellX, y = ball.cellY + 1, facing = "up" })
  game.session.x, game.session.y, game.session.facing = ball.cellX, ball.cellY + 1, "up"
  U.wait(60)
  Flags.setVar(Space.store, Space.vm.ctx, VAR_OAKS_LAB_SCENE, 2)
  U.tap(game, "a")
  U.wait(10)
  result(Space.vm ~= nil and Space.vm:isRunning(), "Charmander ball script started by A press")

  local confirmShot = false
  for _ = 1, 900 do
    if session.party and session.party[1] then break end
    local Choice = package.loaded["src.ui.game3.choice"]
    if not confirmShot and Choice and Choice.active and Choice.kind == "yesno" then
      U.wait(30)
      U.shot(game, DIR .. "/00_confirm.png")
      confirmShot = true
    end
    U.tap(game, "a")
    U.wait(3)
  end
  result(Flags.getVar(Space.store, Space.vm.ctx, VAR_TEMP_2) == MEW,
    "the starter species var follows the gift (VAR_TEMP_2 == MEW)")

  U.wait(150)
  U.shot(game, DIR .. "/00_received.png")
  U.wait(2)
  local mon = session.party and session.party[1]
  if not result(mon ~= nil, "a starter was given") then return finish() end
  result(mon.species == MEW, "party[1] species is MEW (got " .. tostring(mon.species) .. ")")
  result(mon.level == 20, "party[1] level is 20 (got " .. tostring(mon.level) .. ")")
  result(mon.nickname == "HOGHEAD",
    "party[1] nickname is HOGHEAD (got " .. tostring(mon.nickname) .. ")")
  result(#session.party == 1, "exactly one mon in the party")

  for _ = 1, 1500 do
    if not (Space.vm and Space.vm:isRunning()) then break end
    U.tap(game, "b")
    U.wait(3)
  end
  result(not (Space.vm and Space.vm:isRunning()), "starter script finished")
  result(session.party[1] and session.party[1].nickname == "HOGHEAD",
    "nickname survived the rest of the script")
  local gone = Objects.find(ball.localId)
  result(gone == nil or gone.hidden or not gone.visible, "Charmander ball removed from the table")

  local front = Pokemon.frontPic(MEW)
  local back = Pokemon.backPic(MEW)
  result(front and endsWith(front.path, "mew_front_inverted_64.png"),
    "MEW front pic is the inverted 64x64 (" .. tostring(front and front.path) .. ")")
  result(back and endsWith(back.path, "mew_back_inverted_64.png"),
    "MEW back pic is the inverted 64x64 (" .. tostring(back and back.path) .. ")")
  local char = Pokemon.frontPic(CHARMANDER)
  result(char and char.path == nil, "CHARMANDER front pic stays vanilla")

  local PartyMenu = require("src.ui.game3.party_menu")
  PartyMenu.show(session.party, { session = session })
  U.wait(150)
  result(U.shot(game, DIR .. "/01_party.png"), "party screenshot")
  PartyMenu.close()
  U.wait(10)

  local SummaryMenu = require("src.ui.game3.summary_menu")
  SummaryMenu.openMenu(session.party, 1, { session = session })
  U.wait(150)
  result(U.shot(game, DIR .. "/02_summary_front.png"), "summary screenshot")
  SummaryMenu.close()
  U.wait(20)

  local BattleBridge = require("src.core.game3.battle_bridge")
  local Battle = require("src.core.game3.battle")
  local Anim = require("src.core.game3.battle.anim")
  local Ui = require("src.core.game3.battle.ui")
  local ok, err = BattleBridge.startWild(Runtime._mod, game, { species = 16, level = 3 }, { fade = false })
  if not result(ok == true, "wild battle started " .. tostring(err or "")) then return finish() end

  local ready = false
  for _ = 1, 3000 do
    if Ui._mode == "menu" and not Anim.busy() then ready = true break end
    if Ui.dialogPending and Ui.dialogPending() then U.tap(game, "a") else U.wait(1) end
  end
  result(ready, "battle reached the action menu")
  U.wait(20)
  local st = Battle._st
  local pSpecies = st and st.player and (st.player.species or (st.player.mon and st.player.mon.species))
  result(pSpecies == MEW, "player battler is MEW (got " .. tostring(pSpecies) .. ")")
  result(U.shot(game, DIR .. "/03_battle_back.png"), "battle screenshot (inverted back pic)")

  if BattleBridge.finishPending then BattleBridge.finishPending("run") end
  U.wait(30)
  finish()
end
