-- TryQuickSave and the Crystal script VARs, in a real Crystal game.
--
--   POKEPORT_IDENTITY=f2-crystal POKEPORT_GAME=crystal POKEPORT_VERSION=crystal \
--     POKEPORT_SHOT_DIR=/tmp/f2 \
--     POKEPORT_DRIVER=tests/drivers/crystal_f2_save_and_vars.lua love .
--
-- A  ../pokecrystal/maps/BattleTower1F.asm:80-86 with NO monkeypatch: the
--    desk's own `writetext / yesorno`, then `special TryQuickSave` -- the
--    overwrite prompt, the SAVING pages and a real file on disk -- and the
--    room menu it can only reach on a TRUE.
-- B  ../pokecrystal/maps/RadioTower2F.asm:135-146: the correct password's
--    `readvar / addval 1 / writevar VAR_BLUECARDBALANCE`, through the real
--    World, over a save and a reload, and then BuenaPrize spending it.
local U = require("tests.drivers.util")

local BattleTowerMenu = require("src.ui.gen2.BattleTowerMenu")
local BuenaPassword = require("src.ui.gen2.BuenaPassword")
local Mon = require("src.battle.gen2.Mon")
local Save = require("src.core.gen2.Save")
local ScriptMenu = require("src.ui.gen2.ScriptMenu")
local Specials = require("src.script.gen2.Specials")

local VAR_BLUECARDBALANCE = 0x18
local VAR_BUENASPASSWORD = 0x19

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/crystal-f2"
  local fails, shots = 0, 0

  local function say(line)
    print("[driver] " .. line)
    io.stdout:flush()
  end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "OK   " or "FAIL ") .. line)
  end
  local function shot(name)
    shots = shots + 1
    U.shot(game, ("%s/%02d-%s.png"):format(out, shots, name))
  end
  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    U.wait(2)
    game.input.state[button] = false
    U.wait(frames or 4)
  end
  local function top() return game.stack:top() end

  U.wait(60)
  local world = game.world
  assert(world and world.map, "crystal world did not boot")
  local save = game.save

  ok(Specials.STUB_REASONS.TryQuickSave == nil,
    "TryQuickSave is a handler, not a stub")
  ok(Specials.STUB_REASONS.SampleKenjiBreakCountdown == nil,
    "SampleKenjiBreakCountdown is a handler too")

  --------------------------------------------------------------- section B
  say("--- B: Buena's Blue Card, over a save and a reload")

  ok(world:setMap("RADIO_TOWER_2F", 5, 5, "down") == true, "on RADIO_TOWER_2F")
  U.wait(30)

  local crystal = Save.crystalState(save)
  crystal.buenaPassword.balance = 0
  crystal.buenaPassword.word = 0x00
  crystal.buenaPassword.day = nil

  -- The three rows the correct-answer arm runs, straight off the extracted
  -- opcode table, so the round trip is World:readVar -> Vm -> World:writeVar.
  local function awardPoint()
    local started = world.vm:start({
      { op = "readvar", var = VAR_BLUECARDBALANCE },
      { op = "addval", args = { 1 } },
      { op = "writevar", var = VAR_BLUECARDBALANCE },
    })
    ok(started == true, "the award rows started (vm idle)")
    for _ = 1, 120 do
      if not world.vm:running() then break end
      U.wait(1)
    end
  end
  for _ = 1, 3 do awardPoint() end
  say("blue card balance: " .. tostring(world:readVar(VAR_BLUECARDBALANCE)))
  ok(world:readVar(VAR_BLUECARDBALANCE) == 3,
    "three correct passwords are three points")
  ok(crystal.buenaPassword.balance == 3, "and the points are in save.crystal")

  -- The password itself is a RETVAR_ADDR_DE row too; BuenasPassword parks the
  -- day's roll there through the same writevar path.
  world:writeVar(VAR_BUENASPASSWORD, 0x24)
  ok(world:readVar(VAR_BUENASPASSWORD) == 0x24, "wBuenasPassword reads back")

  -- The map load that used to eat it: scriptVars is rebuilt empty at
  -- World.lua:579.
  ok(world:setMap("RADIO_TOWER_1F", 5, 5, "down") == true, "walked downstairs")
  U.wait(20)
  ok(world:readVar(VAR_BLUECARDBALANCE) == 3, "a map load does not eat it")

  ok(game:writeSave() ~= false, "saved with the balance on it")
  local reloaded = Save.load(save.version)
  local reloadedBalance = reloaded and reloaded.crystal
    and reloaded.crystal.buenaPassword
    and reloaded.crystal.buenaPassword.balance
  say("reloaded blue card balance: " .. tostring(reloadedBalance))
  ok(reloadedBalance == 3, "and it survives a save and a reload")
  ok(reloaded and reloaded.crystal.buenaPassword.word == 0x24,
    "so does the password")

  -- BuenaPrize, which could never dispense anything on a balance of 0.
  -- data/items/buena_prizes.asm's first row is ULTRA_BALL at 2 points.
  save.inventory = save.inventory or {}
  save.inventory.ULTRA_BALL = nil
  local prizeIndex
  for index, name in ipairs(world.vm.specialOrder or {}) do
    if name == "BuenaPrize" then prizeIndex = index - 1 break end
  end
  ok(prizeIndex ~= nil, "BuenaPrize is in constants.specialOrder")
  world.vm:start({ { op = "special", id = prizeIndex } })
  local sawPrizeMenu = false
  for _ = 1, 300 do
    if not world.vm:running() and top() == nil then break end
    if getmetatable(top()) == BuenaPassword then
      if not sawPrizeMenu then
        sawPrizeMenu = true
        say("prize menu balance shown: " .. tostring(top().balance))
        shot("prize-menu")
        tap("a", 6) -- ULTRA BALL
      else
        tap("b", 6) -- second pass: leave the shop
      end
    else
      tap("a", 4)
    end
  end
  ok(sawPrizeMenu, "BuenaPrize opened its list")
  say("ULTRA_BALL x" .. tostring(save.inventory.ULTRA_BALL)
    .. " balance=" .. tostring(world:readVar(VAR_BLUECARDBALANCE)))
  ok((save.inventory.ULTRA_BALL or 0) >= 1, "the prize was handed over")
  ok(world:readVar(VAR_BLUECARDBALANCE) == 1, "and two points were spent")
  shot("after-prize")

  --------------------------------------------------------------- section A
  say("--- A: the Battle Tower desk, with the real TryQuickSave")

  -- A file has to already exist for AskOverwriteSaveFile to have anything to
  -- ask about (`ld a, [wSaveFileExists] / and a / jr z, .erase`).
  ok(game:writeSave() ~= false, "a first save is on disk")
  ok(Save.exists(save.version), "Save.exists agrees")

  save.party = {}
  for _, row in ipairs({ { "TYPHLOSION", 20 }, { "FERALIGATR", 20 },
      { "MEGANIUM", 20 } }) do
    local mon = Mon.new(game.data, row[1], row[2])
    save.party[#save.party + 1] = mon
  end

  for _ = 1, 40 do
    if top() == nil then break end
    tap("b", 2)
  end
  ok(world:setMap("BATTLE_TOWER_1F", 7, 7, "up") == true, "on BATTLE_TOWER_1F")
  U.wait(40)
  shot("tower-lobby")

  local function isMenu() return getmetatable(top()) == ScriptMenu end
  local function isRoomMenu() return getmetatable(top()) == BattleTowerMenu end

  local reached = false
  for _ = 1, 200 do
    if isMenu() then reached = true break end
    if world.choicebox then tap("b", 4) else tap("a", 4) end
  end
  ok(reached, "the receptionist reaches Menu_ChallengeExplanationCancel")
  tap("a", 6) -- CHALLENGE

  -- Two yes/no prompts now, not one: Text_SaveBeforeEnteringBattleRoom and
  -- then AskOverwriteSaveFile's own, which the stub never asked.
  local prompts, pages = 0, {}
  for _ = 1, 240 do
    if isRoomMenu() then break end
    if world.choicebox then
      prompts = prompts + 1
      shot("prompt-" .. prompts)
      say("prompt " .. prompts .. ": " .. tostring(world.lastText))
      tap("a", 6)
    else
      local body = world.lastText
      if type(body) == "string" and body ~= "" and pages[#pages] ~= body then
        pages[#pages + 1] = body
      end
      tap("a", 4)
    end
  end
  say("pages: " .. table.concat(pages, " | "))
  ok(prompts >= 2,
    "AskOverwriteSaveFile asked its own question (" .. prompts .. " prompts)")
  local joined = table.concat(pages, " | ")
  ok(joined:find("SAVING", 1, true) ~= nil, "the SAVING page was shown")
  ok(joined:find("saved", 1, true) ~= nil, "and SavedTheGameText")
  ok(isRoomMenu(), "TryQuickSave answered TRUE and the room menu opened")
  shot("room-menu")

  local onDisk = Save.load(save.version)
  ok(onDisk ~= nil, "the challenge's own save reached disk")
  ok(onDisk and onDisk.position and onDisk.position.map == "BATTLE_TOWER_1F",
    "and it was written from the lobby: "
    .. tostring(onDisk and onDisk.position and onDisk.position.map))

  -- The room menu's own header is STATICMENU_DISABLE_B, so the way out of the
  -- desk is forward: pick a room and let the walk to the elevator finish.
  for _ = 1, 400 do
    if not world:busy() and top() == nil then break end
    tap("a", 4)
  end
  say("map after the desk: " .. tostring(world.map and world.map.id))
  for _ = 1, 40 do
    if top() == nil then break end
    game.stack:pop()
  end

  say(fails == 0 and "PASS" or (fails .. " FAILURES"))
  love.event.quit(fails == 0 and 0 or 1)
end
