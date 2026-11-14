-- ../pokecrystal/engine/items/item_effects.asm:609-682
-- ../pokecrystal/data/text/common_3.asm:1233-1237

local U = require("tests.drivers.util")
local Mon = require("src.battle.gen2.Mon")
local Boxes = require("src.core.gen2.Boxes")

return function(game)
  local dir = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gen2_sent_to_pc_nickname"
  local version = tostring(game.save.version)
  local failures = 0
  local function check(ok, label, detail)
    print((ok and "PASS " or "FAIL ") .. label .. (detail and (" " .. tostring(detail)) or ""))
    if not ok then failures = failures + 1 end
    return ok
  end
  local function finish()
    print((failures == 0 and "PASS" or "FAIL") .. " gen2_sent_to_pc_nickname " .. version
      .. " failures=" .. failures)
    love.event.quit(failures == 0 and 0 or 1)
    while true do U.wait(10) end
  end

  U.wait(45)
  local world = game.world
  if not check(world and world.map, "world booted") then return finish() end

  local function battleScreen()
    for _ = 1, 900 do
      local top = game.stack:top()
      if top and top.battle then return top end
      U.wait(1)
    end
  end

  local function catchToBox(species, typed, tag)
    game.save.party = {}
    for i = 1, 6 do game.save.party[i] = Mon.new(game.data, "CYNDAQUIL", 30) end
    game.save.pokedex = game.save.pokedex or { seen = {}, caught = {} }
    game.save.pokedex.caught[species] = true
    local wild = Mon.new(game.data, species, 3)
    if not check(world:startBattle({ wild = wild }), tag .. " wild battle started") then return end
    local screen = battleScreen()
    if not check(screen ~= nil, tag .. " battle screen up") then return end
    for _ = 1, 400 do
      if screen.phase == "menu" and #screen.queue == 0 and not screen.anim then break end
      U.tap(game, "a")
      U.wait(3)
    end
    screen:useItem("MASTER_BALL")

    local asked, named, pcText, pcScreen, pcHud = false, false, nil, nil, nil
    for _ = 1, 2000 do
      if screen.phase == "done" or game.stack:top() == world then break end
      local top = game.stack:top()
      if top ~= screen and top and top.maxLength and not named then
        named = true
        U.wait(30)
        for ch in typed:gmatch(".") do top:addCharacter(ch) end
        U.wait(10)
        U.still(game, dir .. "/p5_" .. tag .. "_01_naming_" .. typed:lower() .. ".png")
        top:accept()
      end
      local asking = screen.phase == "ask-nickname"
      if asking then
        asked = true
        if (screen.messageTimer or 0) > 0 or typed ~= "" then
          U.tap(game, "a")
        else
          U.tap(game, "b")
        end
      end
      local msg = type(screen.message) == "string" and screen.message:gsub("\n", " ") or ""
      if not pcText and msg:find("sent to BILL's PC", 1, true) then
        pcText = msg
        pcScreen = screen.captureScreen or "battle"
        pcHud = screen:enemyHudName(screen:activeMon("enemy"))
        U.wait(90)
        U.still(game, dir .. "/p5_" .. tag .. "_02_pc_line_over_" .. pcScreen .. ".png")
      end
      if not asking then U.tap(game, "a") end
      U.wait(3)
    end

    check(asked, tag .. " AskGiveNicknameText shown")
    local box = Boxes.box(game.save, game.save.currentBox or 1)
    local head = box and box[1]
    check(head == wild, tag .. " catch heads the current box")
    local want = typed ~= "" and typed or species
    check(head and (head.nickname or species) == want, tag .. " boxed name is " .. want,
      head and head.nickname)
    check(pcText ~= nil and pcText:find(want .. " was sent to BILL's PC.", 1, true) == 1,
      tag .. " BallSentToPCText names " .. want, pcText)
    check(pcHud == species, tag .. " enemy HUD reads the species under the PC line", pcHud)
    if typed ~= "" then
      check(named, tag .. " naming screen opened and " .. typed .. " typed")
      check(pcScreen == "naming", tag .. " PC line prints over the naming screen", pcScreen)
    else
      check(pcScreen == "battle", tag .. " PC line prints over the battle scene", pcScreen)
    end
    for _ = 1, 600 do
      local top = game.stack:top()
      if not (top and top.battle) then break end
      U.tap(game, "a")
      U.wait(1)
    end
    U.wait(30)
  end

  game.save.inventory = { MASTER_BALL = 5 }
  catchToBox("SENTRET", "SPARKY", "yes")
  catchToBox("PIDGEY", "", "no")
  finish()
end
