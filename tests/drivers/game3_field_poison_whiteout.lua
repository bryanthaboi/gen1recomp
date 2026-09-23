local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_field_poison_whiteout"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS game3_field_poison_whiteout")
    love.event.quit(0)
  else
    print("FAIL game3_field_poison_whiteout failures=" .. failures)
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
  local Party = require("src.core.game3.party")
  local BattleBridge = require("src.core.game3.battle_bridge")
  local Rush = require("src.ui.game3.whiteout_rush")
  local Message = package.loaded["src.ui.game3.message"] or require("src.ui.game3.message")
  local MapCatalog = require("src.import.gba.map_catalog")

  local session = Runtime.getSession()
  if not result(session ~= nil, "new game reached the game3 field") then return finish() end
  session.party = {}
  Party.giveMon(session, 1, 12)
  Party.giveMon(session, 4, 10)
  for _, mon in ipairs(session.party) do
    mon.hp = 1
    mon.status = "PSN"
  end
  session.money = 3000
  Field.setRespawn(2)
  local loss = math.min(BattleBridge.calcMoneyLossFrlg(session, game.save), 3000)
  session.vars[0x4040] = 3

  local startX, startY = Player.cellX, Player.cellY
  for _, dir in ipairs({ "left", "right", "down", "up" }) do
    U.hold(game, dir, 20)
    U.wait(10)
    if Player.cellX ~= startX or Player.cellY ~= startY then break end
  end
  result(Player.cellX ~= startX or Player.cellY ~= startY, "took a poisoned step")

  local function page()
    return Message.currentPage and Message.currentPage() or ""
  end
  local faints, lostShown = {}, false
  local want = string.format("panicked and lost ¥%d…", loss)
  for _ = 1, 1200 do
    local p = page()
    if Message.isOpen() and p:find("fainted…", 1, true) then
      local name = p:match("^(.-) fainted")
      if name and faints[#faints] ~= name then faints[#faints + 1] = name end
    end
    if Message.isOpen() and p:find(want, 1, true) then lostShown = true break end
    if Message.isOpen() and Message.isTyping() then Message.skipReveal() end
    if Message.isOpen() and Message.isWaiting() then U.tap(game, "a") end
    U.wait(2)
  end
  result(#faints == 2, "both fainted… messages shown before the whiteout (" .. table.concat(faints, ",") .. ")")
  if result(lostShown, "field whiteout text: '" .. want .. "'") then
    Message.skipReveal()
    U.wait(4)
    result(U.shot(game, DIR .. "/spec_field_poison_lost_money.png"), "screenshot spec_field_poison_lost_money")
  end

  for _ = 1, 900 do
    if Rush.isActive() then break end
    if Message.isOpen() and Message.isTyping() then Message.skipReveal() end
    if Message.isOpen() and Message.isWaiting() then U.tap(game, "a") end
    U.wait(2)
  end
  result(Rush.isActive(), "music faded, screen went black and CB2_WhiteOut ran")
  local center = MapCatalog.pretToEngine("ViridianCity_PokemonCenter_1F")
  result(Map.current == center, "respawned in " .. tostring(center))
  result(session.money == 3000 - loss, "money after whiteout " .. tostring(session.money))
  local healed = true
  for _, mon in ipairs(session.party) do
    if (mon.hp or 0) <= 0 or mon.status then healed = false end
    for i, pp in ipairs(mon.pp or {}) do
      if mon.maxPp and mon.maxPp[i] and pp ~= mon.maxPp[i] then healed = false end
    end
  end
  result(healed, "party fully healed (HP, status, PP)")
  return finish()
end
