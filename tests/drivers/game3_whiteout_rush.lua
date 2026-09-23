local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_whiteout_rush"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS game3_whiteout_rush")
    love.event.quit(0)
  else
    print("FAIL game3_whiteout_rush failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end
  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Map = require("src.core.game3.map")
  local Player = require("src.core.game3.player")
  local Field = require("src.core.game3.field")
  local Space = require("src.core.game3.scripting.space")
  local Flags = require("src.core.game3.scripting.flags")
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Rush = require("src.ui.game3.whiteout_rush")
  local Message = package.loaded["src.ui.game3.message"] or require("src.ui.game3.message")
  local MapCatalog = require("src.import.gba.map_catalog")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  BattleBridge.installWhiteoutIntercept(nil, game)
  session.party = {}
  Party.giveMon(session, 6, 20)

  local function page()
    return string.upper(Message.currentPage and Message.currentPage() or "")
  end
  local function vmBusy()
    return Space.vm and Space.vm.isRunning and Space.vm:isRunning()
  end

  local E4 = { "FLAG_DEFEATED_LORELEI", "FLAG_DEFEATED_BRUNO", "FLAG_DEFEATED_AGATHA",
    "FLAG_DEFEATED_LANCE", "FLAG_DEFEATED_CHAMP" }

  local function whiteout(healId, pretMap, label)
    Field.setRespawn(healId)
    for _, name in ipairs(E4) do Flags.setFlag(Space.store, nil, Flags.IDS[name], true) end
    Flags.setFlag(Space.store, nil, Flags.trainerFlagId(438), true)
    Flags.setVar(Space.store, nil, Flags.IDS.VAR_MAP_SCENE_POKEMON_LEAGUE, 2)
    session.money = 3000
    local loss = math.min(BattleBridge.calcMoneyLossFrlg(session, game.save), 3000)
    for _, mon in ipairs(session.party) do mon.hp = 0 end
    BattleBridge._whiteoutHook()
    U.wait(2)
    local want = MapCatalog.pretToEngine(pretMap)
    result(Map.current == want, label .. ": respawned in " .. tostring(want))
    result(session.money == 3000 - loss, label .. ": lost " .. loss .. " money (" .. tostring(session.money) .. ")")
    local cleared = true
    for _, name in ipairs(E4) do
      if Flags.getFlag(Space.store, nil, Flags.IDS[name]) then cleared = false end
    end
    result(cleared, label .. ": FLAG_DEFEATED_LORELEI..CHAMP cleared")
    result(not Flags.getFlag(Space.store, nil, Flags.trainerFlagId(438)), label .. ": champion trainer flag cleared")
    result(Flags.getVar(Space.store, nil, Flags.IDS.VAR_MAP_SCENE_POKEMON_LEAGUE) == 0,
      label .. ": VAR_MAP_SCENE_POKEMON_LEAGUE reset")
    result(Player.facing == "up", label .. ": player faces north")
    result(Rush.phase() == "hold", label .. ": screen held black before the message")
    for _ = 1, 600 do
      if Rush.phase() == "wait" then break end
      U.wait(1)
    end
    return Rush.phase() == "wait"
  end

  local function runScene(label, want, shot, doneCheck)
    U.tap(game, "a")
    local seen = false
    for _ = 1, 900 do
      if page():find(want, 1, true) then seen = true break end
      if Message.isOpen() and Message.isTyping() then Message.skipReveal() end
      if Message.isOpen() and Message.isWaiting() then U.tap(game, "a") end
      U.wait(2)
    end
    result(seen, label .. ": '" .. want .. "' shown after the fade in")
    if seen then
      Message.skipReveal()
      U.wait(4)
      result(U.shot(game, DIR .. "/" .. shot), label .. ": screenshot " .. shot)
    end
    local pages = {}
    for _ = 1, 2400 do
      if not Message.isOpen() and not vmBusy() and not Field.locked then break end
      if Message.isOpen() then pages[#pages + 1] = page() end
      if Message.isOpen() and Message.isTyping() then Message.skipReveal() end
      if Message.isOpen() and Message.isWaiting() then U.tap(game, "a") end
      U.wait(2)
    end
    result(not vmBusy() and not Field.locked, label .. ": scene ended and released the player")
    if doneCheck then result(doneCheck(table.concat(pages, "|")), label .. ": follow-up text") end
  end

  if result(whiteout(2, "ViridianCity_PokemonCenter_1F", "center"), "center: scurried text finished printing") then
    result((Rush.text() or ""):find("scurried to a POKéMON CENTER", 1, true) ~= nil, "center: scurried to a POKéMON CENTER text")
    result(U.shot(game, DIR .. "/spec_whiteout_scurried_center.png"), "center: screenshot spec_whiteout_scurried_center")
    runScene("center", "FIRST, YOU SHOULD RESTORE", "spec_whiteout_nurse_restore.png", function(all)
      return all:find("BUY SOME POTIONS", 1, true) ~= nil
    end)
  end

  if result(whiteout(1, "PalletTown_PlayersHouse_1F", "home"), "home: scurried text finished printing") then
    result((Rush.text() or ""):find("scurried back home", 1, true) ~= nil, "home: scurried back home text")
    result(U.shot(game, DIR .. "/spec_whiteout_scurried_home.png"), "home: screenshot spec_whiteout_scurried_home")
    runScene("home", "WELCOME HOME", "spec_whiteout_mom_welcome.png", function(all)
      return all:find("MAKE ME PROUD", 1, true) ~= nil
    end)
  end
  local healed = true
  for _, mon in ipairs(session.party) do
    if (mon.hp or 0) <= 0 then healed = false end
  end
  result(healed, "party healed after the whiteout scenes")
  return finish()
end
