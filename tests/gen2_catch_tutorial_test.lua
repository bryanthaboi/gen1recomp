-- The DUDE's catching tutorial (engine/events/catch_tutorial.asm,
-- engine/events/catch_tutorial_input.asm, and the BATTLETYPE_TUTORIAL arms in
-- engine/battle/core.asm / engine/items/item_effects.asm).
--   GOLD_CACHE="..." luajit tests/gen2_catch_tutorial_test.lua
--
-- ROM-free: the name swap, the DUDE's pack and the auto-input pacing are all
-- pure tables, and the battle screen is driven with a stub game so the whole
-- demo -- menu, pack, ball, catch -- runs here without a window.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 catch tutorial")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local AutoInput = require("src.core.gen2.AutoInput")
local CatchTutorial = require("src.core.gen2.CatchTutorial")
local Vm = require("src.script.gen2.Vm")

-- ---- .LoadDudeData --------------------------------------------------------
do
  eq(CatchTutorial.DUDE_NAME, "DUDE", "CatchTutorial.Dude is `db \"DUDE@\"`")
  eq(CatchTutorial.BATTLETYPE_TUTORIAL, 3,
    "BATTLETYPE_TUTORIAL is the fourth constant in the const_def 0 block")
  eq(CatchTutorial.PACK.POTION, 1, "wDudeNumItems holds one POTION")
  eq(CatchTutorial.PACK.POKE_BALL, 5,
    "and the ball's quantity byte is written from POKE_BALL itself, so the "
    .. "DUDE's pocket really does read x5")
  eq(CatchTutorial.BALL, "POKE_BALL",
    "and POKE_BALL is what DoItemEffect is handed whatever the pack returned")

  local dude = CatchTutorial.dudeSave()
  eq(dude.player.name, "DUDE", "the pack is drawn as the DUDE's")
  eq(dude.inventory.POTION, 1, "out of his own buffers")
  dude.inventory.POTION = 99
  eq(CatchTutorial.PACK.POTION, 1,
    "and each opening gets a copy, not the shared table")
end

-- ---- the name and option bracket ------------------------------------------
do
  local save = { player = { name = "GOLD" }, mom = { name = "MOM" } }
  local options = { textSpeed = "SLOW", battleScene = true }
  local state = CatchTutorial.begin(save, options)
  eq(save.player.name, "DUDE", "the player answers to DUDE for the demo")
  eq(save.mom.name, "GOLD",
    "with the real name parked in wMomsName, which is where the cart keeps it")
  eq(options.textSpeed, "MID", "TEXT_DELAY_MED for the length of the battle")
  eq(options.battleScene, true, "and no other option bit is touched")

  CatchTutorial.finish(save, options, state)
  eq(save.player.name, "GOLD", "the name comes back out of wMomsName")
  eq(options.textSpeed, "SLOW", "and wOptions is popped")
  eq(save.mom.name, "GOLD",
    "Mom's name is NOT restored: the cart has nowhere left to restore it from")
end

-- ---- the re-arms ----------------------------------------------------------
do
  -- Every re-arm in the ASM is guarded by `ld a, [wInputType] / or a`, so the
  -- DUDE only answers while a stream is already running.
  local ring = AutoInput.new()
  check(not CatchTutorial.rearm(ring, CatchTutorial.PROMPT_STREAM),
    "an unarmed ring is never taken over by a re-arm")
  ring:start(CatchTutorial.BATTLE_STREAM)
  check(CatchTutorial.rearm(ring, CatchTutorial.PROMPT_STREAM),
    "but the lockout stream counts as wInputType == AUTO_INPUT")
  check(not CatchTutorial.rearm(ring, "NO_SUCH_STREAM"),
    "and a stream the ROM does not have arms nothing")
end

do
  -- Frame-paced: PromptButton's loop delays a frame per iteration, so DUDE_A's
  -- 0x51 blank frames are exactly the beat between two lines of text.
  local ring = AutoInput.new()
  ring:start(CatchTutorial.BATTLE_STREAM)
  CatchTutorial.rearm(ring, CatchTutorial.PROMPT_STREAM)
  local blanks = 0
  while ring:advance() == AutoInput.NO_INPUT and blanks < 200 do
    blanks = blanks + 1
  end
  eq(blanks, 0x51, "the prompt stream is replayed frame for frame")
end

do
  -- Poll-paced: the battle menu picks ITEM with DOWN then A, and the runs of
  -- blank pairs between them are loop iterations on the cart.
  local ring = AutoInput.new()
  ring:start(CatchTutorial.BATTLE_STREAM)
  CatchTutorial.rearm(ring, CatchTutorial.MENU_STREAM, nil, true)
  eq(ring:advance(), AutoInput.PAD_DOWN, "DOWN lands on the next step")
  eq(ring:advance(), AutoInput.PAD_A, "and A on the one after it")
  check(ring:isActive(), "the stream parks rather than handing control back")

  CatchTutorial.rearm(ring, CatchTutorial.PACK_STREAM, nil, true)
  eq(ring:advance(), AutoInput.PAD_RIGHT,
    "the pack stream crosses to the BALL pocket")
  eq(ring:advance(), AutoInput.PAD_A, "and picks the POKE BALL")
end

do
  -- skipIdle never eats a press, and never eats the $ff pair a stream parks
  -- on -- that pair is the lockout, not a pause.
  local ring = AutoInput.new()
  ring:start({ AutoInput.PAD_A, 0x00, AutoInput.NO_INPUT, 0xff })
  check(not ring:skipIdle(), "a stream that opens on a press is left alone")
  eq(ring:advance(), AutoInput.PAD_A, "and still presses it")
  check(not ring:skipIdle(), "the parked $ff pair is not skippable")
  check(ring:isActive(), "so the controller stays taken")
end

-- ---- Script_catchtutorial -------------------------------------------------
do
  -- Script_catchtutorial: one operand byte into wBattleType, then
  -- farcall CatchTutorial, then `jp Script_reloadmap`.  CatchTutorial itself
  -- brackets StartBattle in StartAutoInput / StopAutoInput.
  local order, got = {}, nil
  local vm = Vm.new({
    ["s:t"] = {
      { op = "setval", value = 5 },
      { op = "loadwildmon", args = { 19, 5 } },
      { op = "catchtutorial", args = { 3 } },
      { op = "writetext", text = "AFTER" },
      { op = "end" },
    },
  }, {}, nil, {
    autoInputStream = function(name) order[#order + 1] = "start:" .. name end,
    stopAutoInput = function() order[#order + 1] = "stop" end,
    reloadMap = function() order[#order + 1] = "reload" end,
    showText = function(_body, done)
      order[#order + 1] = "text"
      done()
    end,
    catchTutorial = function(wild, battleType, onDone)
      order[#order + 1] = "battle"
      got = { wild = wild, battleType = battleType }
      onDone()
    end,
  })
  vm:start("s:t")
  eq(table.concat(order, ","),
    "start:CATCH_TUTORIAL,battle,stop,reload",
    "the battle runs inside the lockout, and the script parks on the "
    .. "map reload")
  check(vm:running(), "catchtutorial is not a terminator")
  vm:update()
  eq(table.concat(order, ","),
    "start:CATCH_TUTORIAL,battle,stop,reload,text",
    "and the script continues once the map setup has run")
  eq(got and got.battleType, 3, "wBattleType is the command's own byte")
  eq(got and got.wild and got.wild.species, 19,
    "and the wild mon is the one loadwildmon left behind")
  eq(got.wild.level, 5, "at the level it named")
  eq(vm.scriptVar, 5, "catchtutorial leaves wScriptVar alone")
  eq(vm.wildMon, nil,
    "and consumes the pair, so a later startbattle cannot inherit it")
end

do
  -- With no hook there is nothing to park on: the bracket collapses and the
  -- command still ends where the ASM ends it.
  local order = {}
  local vm = Vm.new({
    ["s:t"] = { { op = "catchtutorial", args = { 3 } }, { op = "end" } },
  }, {}, nil, {
    autoInputStream = function(name) order[#order + 1] = "start:" .. name end,
    stopAutoInput = function() order[#order + 1] = "stop" end,
    reloadMap = function() order[#order + 1] = "reload" end,
  })
  vm:start("s:t")
  eq(table.concat(order, ","), "start:CATCH_TUTORIAL,stop,reload",
    "the lockout still closes before the map reload")
end

-- ---- the demo battle itself -----------------------------------------------
-- BattleState with a stub game: no window, but the real update loop, the real
-- auto-input ring and the real Input edge detection, so the DUDE plays the
-- whole thing exactly as he would on screen.
local Battle = require("src.battle.gen2.Battle")
local BattleState = require("src.ui.gen2.BattleState")
local BattleAnimView = require("src.ui.gen2.BattleAnimView")
local Input = require("src.core.Input")
local PackMenu = require("src.ui.gen2.PackMenu")

local function tutorialScreen()
  Input:init()
  local ring = AutoInput.new()
  local pushed = {}
  local save = {
    player = { name = "DUDE" },
    party = { { species = "CYNDAQUIL", level = 5, hp = 20, maxHp = 20 } },
    inventory = { POKE_BALL = 3 },
    pokedex = { seen = {}, caught = {} },
  }
  local data = {
    pokemon = { RATTATA = { catchRate = 255 } },
    items = { POKE_BALL = { pocket = "BALL", name = "POKe BALL", index = 5 },
              POTION = { pocket = "ITEM", name = "POTION", index = 17 } },
  }
  local game = {
    data = data,
    save = save,
    input = Input,
    autoInput = ring,
    options = {},
    stack = {
      push = function(_, screen) pushed[#pushed + 1] = screen end,
      pop = function() table.remove(pushed) end,
    },
  }
  -- BATTLETYPE_TUTORIAL fights with an empty party: no mon is ever sent out.
  local battle = Battle.new({ data = data, party = {},
    wild = { species = "RATTATA", level = 5, hp = 19, maxHp = 19 } })
  local outcome
  local screen = BattleState.new(game, {
    battle = battle,
    save = save,
    tutorial = true,
    onDone = function(result) outcome = result end,
  })
  -- The 72-frame sliding intro reads no input at all.
  for _ = 1, BattleAnimView.SLIDE_FRAMES do screen:update(1 / 60) end
  return screen, ring, save, function() return outcome end, pushed, game
end

do
  local screen, ring, _, _, _ = tutorialScreen()
  eq(screen.battle.player, nil, "the tutorial opens with no mon out")
  check(screen.showPlayerTrainer,
    "so the player's box keeps a trainer back-pic for the whole battle")
  -- CatchTutorial armed the lockout before StartBattle.
  ring:start(CatchTutorial.BATTLE_STREAM, Input)

  -- "Wild RATTATA appeared!" goes up on the step that drains the queue, and
  -- the DUDE is handed the prompt on the first step that waits on it.
  screen:update(1 / 60)
  eq(screen.message, "Wild RATTATA appeared!", "the intro line is the cart's")
  for _ = 1, 400 do
    if not screen:syncTyper() then break end
    screen:update(1 / 60)
  end
  screen:update(1 / 60)
  eq(ring.bytes, AutoInput.STREAMS.DUDE_A,
    "and DudeAutoInput_A is armed to answer it")
  local before = ring.pos
  screen:update(1 / 60)
  eq(ring.pos, before,
    "a wait that spans many steps arms the stream once, not once a step")
  check(screen.messageTimer > 0,
    "and the line does NOT time out: PromptButton waits for the button")
end

do
  -- The whole demo, driven by nothing but the ring: enough steps for the
  -- prompt beat on each line plus the menu and pack presses.
  local screen, ring, save, outcomeOf, pushed = tutorialScreen()
  ring:start(CatchTutorial.BATTLE_STREAM, Input)
  local sawPack, sawBallPocket, chosen = false, false, nil
  for _ = 1, 600 do
    ring:step(Input)
    Input:step()
    local top = pushed[#pushed]
    if top and getmetatable(top) == PackMenu then
      sawPack = true
      top:update(1 / 60)
      -- DudeAutoInput_RightA's RIGHT is the pocket cross; its A picks the row
      -- the cursor is sitting on, which in the BALL pocket is the POKE BALL.
      if top:pocket().id == "BALL" then
        sawBallPocket = true
        chosen = top.rows[top.index] and top.rows[top.index].id
      end
    else
      screen:update(1 / 60)
    end
    if outcomeOf() then break end
  end
  check(sawPack, "the DUDE opens his own pack, as BattleMenu_Pack .tutorial does")
  check(sawBallPocket, "crosses to the BALL pocket")
  eq(chosen, "POKE_BALL", "and lands on the POKE BALL")
  eq(outcomeOf(), "caught", "and the ball catches")
  eq(screen.message, "Gotcha! RATTATA was caught!", "with the cart's line")
  eq(#save.party, 1, "nothing is added to the party")
  eq(save.pokedex.caught.RATTATA, nil, "nothing is written to the Pokedex")
  eq(save.inventory.POKE_BALL, 3, "and no ball leaves the player's bag")
end

-- ---- the call sites -------------------------------------------------------
-- World needs a map, a stack and a VM to construct, so the wiring that reaches
-- all of the above is asserted by reading it: a call site that is not spelled
-- out in the file is not there at all.
local function sourceOf(path)
  local f = io.open(path, "r")
  if not f then return nil end
  local body = f:read("*a")
  f:close()
  return body
end

do
  local world = sourceOf("src/world/gen2/World.lua")
  check(world ~= nil, "World's source is readable")
  for _, wanted in ipairs({
      "catchTutorial = function(wild, battleType, onDone)",
      "self:startCatchTutorial(wild, battleType, onDone)",
      "function World:startCatchTutorial",
      "CatchTutorial.begin(save, game and game.options)",
      "CatchTutorial.finish(save, game and game.options, state)",
      "tutorial = true,",
      "tutorial = opts.tutorial,",
    }) do
    check(world:find(wanted, 1, true) ~= nil, "World has " .. wanted)
  end

  local vmSource = sourceOf("src/script/gen2/Vm.lua")
  check(vmSource ~= nil, "the VM's source is readable")
  for _, wanted in ipairs({
      "catchTutorialFn = hooks.catchTutorial,",
      'req.kind == "catchtutorial"',
    }) do
    check(vmSource:find(wanted, 1, true) ~= nil, "the VM has " .. wanted)
  end

  -- GetTrainerBackpic's "Special exception for Dude".
  local extractor = sourceOf("src/import/RomExtractorGen2.lua")
  check(extractor ~= nil, "the extractor's source is readable")
  check(extractor:find('self.symbols["DudeBackpic"]', 1, true) ~= nil,
    "the extractor rips DudeBackpic")
  check(extractor:find('hud.dudeBack = "assets/generated/battle/dude_back.png"',
    1, true) ~= nil, "and the battle screen has a path to look it up by")
end

S.finish()
