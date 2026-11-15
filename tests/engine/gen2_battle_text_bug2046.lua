-- ../pokecrystal/home/text.asm:660 StdBattleTextbox -> PrintText
-- ../pokecrystal/home/print_text.asm:1 PrintLetterDelay
-- ../pokecrystal/engine/battle/core.asm:9119 BattleStartMessage

package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")

local T = require("tests.harness")
local eq, check = T.eq, T.check

require("src.core.Logger").warn = function() end

local Battle = require("src.battle.gen2.Battle")
local BattleState = require("src.ui.gen2.BattleState")

local function newInput()
  local input = { pressed = {}, held = {} }
  function input:press(button) self.pressed[button] = true end
  function input:wasPressed(button)
    if self.pressed[button] then
      self.pressed[button] = nil
      return true
    end
    return false
  end
  function input:isDown(button) return self.held[button] == true end
  return input
end

local function newScreen(opts)
  opts = opts or {}
  local input = newInput()
  local game = {
    input = input,
    save = { options = { textSpeed = opts.speed or "MID" } },
    data = {},
  }
  local screen = setmetatable({
    game = game,
    queue = {},
    phase = "resolving",
    slideFrame = 999,
    message = opts.message,
    messageTimer = opts.timer or 0,
    picHidden = {},
    advanced = 0,
    updateAlarm = function() end,
    stepFrontAnim = function() end,
    stepHpAnim = function() return false end,
    stepExpAnim = function() return false end,
    nextPage = function() return false end,
    advanceQueue = function(self) self.advanced = self.advanced + 1 end,
  }, { __index = BattleState })
  return screen, input
end

do
  local screen, input = newScreen({ message = "ABCDE", timer = 48 })
  check(screen:syncTyper(), "the line has not been printed yet")
  eq(screen:messageLines()[1], "", "so the box is empty on the frame it opens")
  eq(screen.typer.total, 5, "five glyphs to spend")

  for _ = 1, 3 do screen:update(1 / 60) end
  eq(screen.typer.shown, 1, "MID lands one glyph every three frames")
  eq(screen:messageLines()[1], "A", "and the box holds exactly that prefix")
  eq(screen.advanced, 0, "the queue does not move while PrintText is running")

  input:press("a")
  screen:update(1 / 60)
  eq(screen.messageTimer, 48, "A during the print does not page the box")
  check(screen.typer.shown <= 2, "and does not dump the rest of the line")

  for _ = 1, 60 do
    if screen.typer:done() then break end
    screen:update(1 / 60)
  end
  check(screen.typer:done(), "the line finishes on its own")
  eq(screen:messageLines()[1], "ABCDE", "with every glyph up")
  eq(screen.advanced, 0, "and it still waits on PromptButton")

  input:press("a")
  screen:update(1 / 60)
  eq(screen.messageTimer, 0, "now A pages it")
end

do
  local screen, input = newScreen({ message = "ABCDE", speed = "SLOW" })
  input.held.a = true
  local frames = 0
  for _ = 1, 60 do
    if screen.typer and screen.typer:done() then break end
    screen:update(1 / 60)
    frames = frames + 1
  end
  check(screen.typer:done(), "a held A prints the line")
  eq(frames, 5, "at one glyph a frame, not one page a press")
end

do
  local screen = newScreen({ message = "TACKLE!", timer = 0 })
  screen:update(1 / 60)
  eq(screen.advanced, 0, "a move line is typed before the next event")
  for _ = 1, 100 do
    if screen.advanced > 0 then break end
    screen:update(1 / 60)
  end
  check(screen.typer:done(), "the line is whole")
  eq(screen.advanced, 1, "and only then does the queue advance")
end

do
  local long = "The hooked MAGIKARP attacked the whole party at once!"
  local screen = newScreen({ message = long })
  check(screen:syncTyper(), "a long line still types")
  check(#screen.typer.page <= 2,
    "PrintTextboxText has two rows and Paragraph clears the third")
end

do
  local S7B = require("tests.fixture_data.gen2_rom_text_s7_b")
  local gold = { text = S7B.text() }
  local crystal = { text = S7B.text(nil, "crystal") }
  eq(BattleState.battleStartText(gold, "RATTATA", nil), "Wild RATTATA\nappeared!",
    "WildPokemonAppearedText is the default arm")
  eq(BattleState.battleStartText(gold, "MAGIKARP", Battle.BATTLETYPE_FISH),
    "The hooked\nMAGIKARP\vattacked!", "HookedPokemonAttackedText for a rod")
  eq(BattleState.battleStartText(gold, "HERACROSS", Battle.BATTLETYPE_TREE),
    "HERACROSS fell\nout of the tree!", "PokemonFellFromTreeText for a headbutt")
  eq(BattleState.battleStartText(crystal, "CELEBI", Battle.BATTLETYPE_CELEBI),
    "Wild CELEBI\nappeared!", "WildCelebiAppearedText reads the same")
  eq(BattleState.battleStartText(gold, "MAGIKARP", "fish"),
    "The hooked\nMAGIKARP\vattacked!", "the string form folds onto the byte")
  eq(BattleState.battleStartText({ text = S7B.text({
    WildPokemonAppearedText = "Un {STRBUF}\nsauvage!{PROMPT}" }) }, "RATTATA", nil),
    "Un RATTATA\nsauvage!", "the line is the cache's, not a Lua literal")
  check(not pcall(BattleState.battleStartText,
    { text = S7B.without("WildPokemonAppearedText") }, "RATTATA", nil),
    "a cache without WildPokemonAppearedText is an error")
end

do
  local asleep = { species = "EXEGGCUTE", status = "sleep" }
  local awake = { species = "HERACROSS" }
  check(BattleState.sleepingTreeMon(asleep, Battle.BATTLETYPE_TREE),
    "a tree mon that entered asleep skips .cry_no_anim")
  check(not BattleState.sleepingTreeMon(awake, Battle.BATTLETYPE_TREE),
    "an awake one still cries")
  check(not BattleState.sleepingTreeMon(asleep, Battle.BATTLETYPE_FISH),
    "and the check returns nc for every other battle type")
  check(not BattleState.sleepingTreeMon(asleep, nil), "including none at all")
end

do
  eq(Battle.battleTypeId("fish"), Battle.BATTLETYPE_FISH, "\"fish\" is 4")
  eq(Battle.battleTypeId("tree"), Battle.BATTLETYPE_TREE, "\"tree\" is 8")
  eq(Battle.battleTypeId(Battle.BATTLETYPE_TRAP), Battle.BATTLETYPE_TRAP,
    "a byte passes through")
  eq(Battle.battleTypeId(nil), nil, "and no type stays no type")
  local battle = Battle.new({ data = {}, party = {}, battleType = "tree" })
  eq(battle.battleType, Battle.BATTLETYPE_TREE,
    "so only the byte leaves Battle.new")
end

do
  local ditto = { species = "DITTO", hp = 20, maxHp = 20, level = 26 }
  local screen = setmetatable({
    queue = {}, shownMon = { enemy = ditto, player = false },
  }, { __index = BattleState })
  ditto.species = "PARASECT"
  local event = { kind = "transform", side = "enemy", mon = ditto,
    species = "PARASECT", from = "DITTO" }
  screen:push(event)
  eq(screen:activeMon("enemy").species, "DITTO",
    "the side keeps drawing what it was until the event is read")
  eq(screen:activeMon("enemy").hp, 20, "with the live HP behind it")
  screen.shownMon.enemy = event.mon
  eq(screen:activeMon("enemy").species, "PARASECT",
    "and takes the copy when the transform is consumed")
end

-- ../pokecrystal/home/text.asm:660 StdBattleTextbox
do
  local screen = newScreen({ message = "ABCDE" })
  screen.advanceQueue = nil
  screen.battle = {}
  screen.evolvable = {}
  screen.queue = { { kind = "message", text = "ABCDE" } }
  screen:syncTyper()
  for _ = 1, 60 do
    if screen.typer:done() then break end
    screen:update(1 / 60)
  end
  eq(screen:messageLines()[1], "ABCDE", "the first line is whole")
  screen:advanceQueue()
  eq(screen.message, "ABCDE", "the queued line reads the same")
  screen:syncTyper()
  eq(screen.typer.shown, 0, "and it types again from no glyphs")
  eq(screen:messageLines()[1], "", "over an empty box")
end

T.finish("gen2_battle_text_bug2046")
