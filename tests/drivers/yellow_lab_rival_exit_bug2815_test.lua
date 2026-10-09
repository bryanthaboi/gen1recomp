-- pokeyellow scripts/OaksLab.asm:403-516
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local GameVersion = require("src.core.GameVersion")
  local Commands = require("src.script.Commands")
  local PF = require("src.world.PikachuFollower")
  local Pokemon = require("src.pokemon.Pokemon")
  local Sound = require("src.core.Sound")
  local TextBox = require("src.render.TextBox")

  local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/shots"
  local LAB = "OAKS_LAB"
  local RIVAL = 1
  local failed = false

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    if not ok then failed = true end
    return ok
  end
  local function finish()
    love.event.quit(failed and 1 or 0)
    while true do coroutine.yield() end
  end
  local function ow() return game.overworld end
  local function ctx()
    return { game = game, save = game.save, overworld = game.overworld }
  end

  if not check("running the Yellow cache", GameVersion.isYellow()) then finish() end

  local boxText = setmetatable({}, { __mode = "k" })
  local newBox = TextBox.new
  TextBox.new = function(g, text, onDone, opts)
    local box = newBox(g, text, onDone, opts)
    boxText[box] = type(text) == "string" and text or ""
    return box
  end
  local pikaCries = {}
  local playPika = Sound.playPikaCry
  Sound.playPikaCry = function(data, n)
    pikaCries[#pikaCries + 1] = n
    return playPika(data, n)
  end
  local plainCries = {}
  local playCry = Sound.playCry
  Sound.playCry = function(data, species, ...)
    plainCries[#plainCries + 1] = species
    return playCry(data, species, ...)
  end

  local flags = game.save.flags or {}
  game.save.flags = flags
  flags.EVENT_GOT_STARTER = true
  flags.EVENT_CHOSE_PIKACHU = true
  flags.EVENT_FOLLOWED_OAK_INTO_LAB = true
  flags.EVENT_FOLLOWED_OAK_INTO_LAB_2 = true
  flags.EVENT_BATTLED_RIVAL_IN_OAKS_LAB = nil
  flags.EVENT_OAK_ASKED_TO_CHOOSE_MON = true
  game.save.party = { Pokemon.new(game.data, "PIKACHU", 40) }
  game.save.party[1].moves = { { id = "THUNDERBOLT", pp = 15 } }
  game.save.onBike = false
  game.save.pikachuInBall = true

  U.teleport(game, LAB, 5, 5, "down")
  U.wait(10)
  Commands.show_object(ctx(), LAB, "OAKSLAB_OAK1")
  Commands.show_object(ctx(), LAB, "OAKSLAB_RIVAL")
  U.wait(5)
  U.hold(game, "down", 20)
  game.input.state.down = false

  local whatBox, rivalSteps, lastCell, lastStep = nil, {}, nil, nil
  local exiting = false
  for _ = 1, 6000 do
    local top = game.stack:top()
    local text = boxText[top]
    if text and text:find("What%?") and not text:find("look") then
      whatBox = top
      break
    end
    local o = game.overworld
    if top ~= o then
      if text and text:find("Smell") and not exiting then
        exiting = true
        plainCries, pikaCries = {}, {}
      end
      U.tap(game, "a")
      U.wait(2)
    else
      local rival = o:npcByIndex(RIVAL)
      if exiting and rival then
        local cell = rival.cellX .. "," .. rival.cellY
        if cell ~= lastCell then
          if lastCell then rivalSteps[#rivalSteps + 1] = lastStep end
          lastCell = cell
        end
        if rival.moving then lastStep = rival.stepFrames or 32 end
      end
      U.wait(1)
    end
  end

  U.log("rival exit step lengths:", table.concat(rivalSteps, " "))
  check("rival walked side, down, then the $04 steps", #rivalSteps >= 6)
  local fastTail = #rivalSteps >= 6
  for i = 3, #rivalSteps do
    if not rivalSteps[i] or rivalSteps[i] > 16 then fastTail = false end
  end
  check("the last five rival steps run at double speed", fastTail)
  check("the first two rival steps are normal speed",
        rivalSteps[1] and rivalSteps[1] > 16 and rivalSteps[2] and rivalSteps[2] > 16)

  if not check("the OAK: What? box came up", whatBox ~= nil) then finish() end
  check("no follower on the map while What? is typing", PF.current(ow()) == nil)

  U.wait(240)
  check("What? is still on screen 240 frames later with no input",
        game.stack:top() == whatBox)
  check("still no follower before the box is closed", PF.current(ow()) == nil)
  check("PikachuCry2 played for the What? line",
        #pikaCries == 1 and pikaCries[1] == 2)
  local defaultPika = false
  for _, s in ipairs(plainCries) do
    if s == "PIKACHU" then defaultPika = true end
  end
  check("no default PIKACHU cry played in the escape scene", not defaultPika)
  U.still(game, SHOT_DIR .. "/2815_01_what_waits_no_pikachu.png")

  U.tap(game, "a")
  local text2
  for _ = 1, 300 do
    local top = game.stack:top()
    if top ~= whatBox and boxText[top] and boxText[top]:find("look") then
      text2 = top
      break
    end
    U.wait(1)
  end
  check("Would you look at that! follows the A press", text2 ~= nil)
  check("the follower is on the map once What? closes", PF.current(ow()) ~= nil)
  U.wait(30)
  U.still(game, SHOT_DIR .. "/2815_02_look_at_that_pikachu_out.png")
  finish()
end
