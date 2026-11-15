package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 s7 f2 rom text")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local Chrome = require("src.ui.gen2.Chrome")
local RomText = require("src.core.RomText")
local FIXTURE = require("tests.fixture_data.gen2_rom_text_s7_f2")

local BuenaPassword = require("src.ui.gen2.BuenaPassword")
local CardFlip = require("src.ui.gen2.CardFlip")
local ContestMenu = require("src.ui.gen2.ContestMenu")
local DayCareMenu = require("src.ui.gen2.DayCareMenu")
local DecorationMenu = require("src.ui.gen2.DecorationMenu")
local Decorations = require("src.core.gen2.Decorations")
local ElevatorMenu = require("src.ui.gen2.ElevatorMenu")
local HeldItemMenu = require("src.ui.gen2.HeldItemMenu")
local MailCompose = require("src.ui.gen2.MailCompose")
local MailMenu = require("src.ui.gen2.MailMenu")
local MailboxMenu = require("src.ui.gen2.MailboxMenu")
local MartMenu = require("src.ui.gen2.MartMenu")
local MoveTutor = require("src.ui.gen2.MoveTutor")
local SlotMachine = require("src.ui.gen2.SlotMachine")
local TradeAnimView = require("src.ui.gen2.TradeAnim")
local TradeMenu = require("src.ui.gen2.TradeMenu")
local UnownPrinter = require("src.ui.gen2.UnownPrinter")

local function tagged()
  local out = {}
  for label, text in pairs(FIXTURE) do
    if type(text) == "string" then out[label] = "~" .. text end
  end
  for label, text in pairs(FIXTURE.crystal) do out[label] = "~" .. text end
  return out
end

local printed
local noop = function() end
Chrome.print = function(text) printed[#printed + 1] = text end
Chrome.printThrough = Chrome.print
for _, name in ipairs({ "box", "textbox", "cursor", "clear" }) do
  Chrome[name] = noop
end

local function capture(fn)
  printed = {}
  fn()
  return printed
end

local function has(list, want)
  for _, v in ipairs(list) do if v == want then return true end end
  return false
end

local function gameWith(text)
  return { data = { text = text }, input = { wasPressed = function() return false end } }
end

local TEXT = tagged()
local GAME = gameWith(TEXT)
local BARE = gameWith({})

local function prints(name, fn, labels)
  local out = capture(function() fn(GAME) end)
  for _, label in ipairs(labels) do
    check(has(out, TEXT[label]), ("%s prints data.text[%s]"):format(name, label))
  end
  check(not pcall(fn, BARE), name .. " errors without its labels")
end

local YES, NO = "YesNoMenuHeader.MenuData#1", "YesNoMenuHeader.MenuData#2"

for name, screen in pairs({
  MartMenu = MartMenu, MailboxMenu = MailboxMenu, MailMenu = MailMenu,
  HeldItemMenu = HeldItemMenu, DayCareMenu = DayCareMenu, TradeMenu = TradeMenu,
}) do
  prints(name .. " YES/NO", function(game)
    screen.drawYesNo({ game = game }, 1)
  end, { YES, NO })
end

prints("ContestMenu YES/NO", function(game)
  ContestMenu.drawYesNo({ game = game, choice = 1 })
end, { YES, NO })

prints("MailboxMenu submenu", function(game)
  MailboxMenu.drawSubmenu({ game = game, submenu = { index = 1 } })
end, { "MailboxPC.SubMenuData#1", "MailboxPC.SubMenuData#2",
  "MailboxPC.SubMenuData#3", "MailboxPC.SubMenuData#4" })

prints("MailMenu READ/TAKE/QUIT", function(game)
  MailMenu.drawPanel({ game = game, index = 1 })
end, { "MonMailAction.MenuData#1", "MonMailAction.MenuData#2",
  "MonMailAction.MenuData#3" })

prints("HeldItemMenu GIVE/TAKE", function(game)
  HeldItemMenu.drawPanel({ game = game, index = 1 })
end, { "GiveTakeItemMenuData.Items#1", "GiveTakeItemMenuData.Items#2" })

prints("DecorationMenu categories", function(game)
  setmetatable({ game = game, mode = "category", index = 1,
    categories = Decorations.CATEGORIES }, DecorationMenu):drawPanel()
end, { "_PlayerDecorationMenu.bed", "_PlayerDecorationMenu.carpet",
  "_PlayerDecorationMenu.plant", "_PlayerDecorationMenu.poster",
  "_PlayerDecorationMenu.game", "_PlayerDecorationMenu.ornament",
  "_PlayerDecorationMenu.big_doll", "_PlayerDecorationMenu.exit" })

prints("DecorationMenu sides", function(game)
  local screen = setmetatable({ game = game, mode = "side", sideIndex = 1 },
    DecorationMenu)
  screen:drawPanel()
end, { "DecoSideMenuHeader.MenuData#1", "DecoSideMenuHeader.MenuData#2",
  "DecoSideMenuHeader.MenuData#3" })

do
  local said
  local screen = setmetatable({ game = GAME }, DecorationMenu)
  screen.say = function(_, pages) said = pages end
  screen:openCategory({ id = 1, members = {} })
  eq(said and said[1], "~There's nothing to\nchoose.",
    "an empty category says _NothingToChooseText")
  local bare = setmetatable({ game = BARE, say = noop }, DecorationMenu)
  check(not pcall(bare.openCategory, bare, { id = 1, members = {} }),
    "and errors without it")
end

do
  local said
  local game = gameWith(TEXT)
  game.say = function(_, body) said = body end
  local screen = setmetatable({ game = game, view = {}, move = "FLAMETHROWER",
    moveName = "FLAMETHROWER", playSfx = noop }, MoveTutor)
  screen:picked({ species = "PIDGEY", nickname = "BIRD", moves = {} })
  eq(said, RomText(game.data, "_TMHMNotCompatibleText", nil,
    "FLAMETHROWER", "BIRD", "FLAMETHROWER"),
    "the tutor refusal is _TMHMNotCompatibleText")
  check(said and said:find("^~FLAMETHROWER is\nnot compatible\vwith BIRD") ~= nil,
    "with the move and the nickname in the cart's order")
  screen.view = { PIDGEY = { tmhm = { "FLAMETHROWER" } } }
  screen:picked({ species = "PIDGEY", nickname = "BIRD",
    moves = { { id = "FLAMETHROWER" } } })
  eq(said, "~BIRD knows\nFLAMETHROWER.{PROMPT}", "and a known move is _KnowsMoveText")
  local bareGame = gameWith({})
  bareGame.say = noop
  screen.game = bareGame
  check(not pcall(screen.picked, screen, { species = "PIDGEY", nickname = "BIRD",
    moves = { { id = "FLAMETHROWER" } } }), "and errors without it")
end

prints("ElevatorMenu Now on:", function(game)
  ElevatorMenu.drawPanel({ data = game.data, origin = 1, index = 1, scroll = 0,
    floors = { { floorId = 4 } }, floorNames = { "B4F", "B3F", "B2F", "B1F", "1F" } })
end, { "Elevator_CurrentFloorText" })

prints("BuenaPassword Points", function(game)
  BuenaPassword.drawPrizePanel({ data = game.data, prizes = {}, scroll = 0,
    index = 1, balance = 3 })
end, { "PrintBlueCardBalance.Points_string" })

prints("UnownPrinter title / Do what? / VACANT", function(game)
  local screen = setmetatable({ game = game, index = 26 }, UnownPrinter)
  screen:drawPanel()
end, { "AlphRuinsStampString", "UnownDexDoWhatString", "UnownDexVacantString" })

do
  local save = { player = { coins = 0 } }
  local flip = CardFlip.new(GAME, { save = save, random = function() return 0 end })
  eq(table.concat(flip.lines, "\n"), "~Play with three\ncoins?",
    "card flip opens on _CardFlipPlayWithThreeCoinsText")
  flip.drawBoard, flip.drawCards = noop, noop
  local out = capture(function() flip:drawPanel() end)
  check(has(out, TEXT["CardFlip_PrintCoinBalance.CoinStr"]), "card flip prints its COIN label")
  check(has(out, TEXT[YES]) and has(out, TEXT[NO]), "and its YES/NO")
  for key, label in pairs(CardFlip.LABELS) do
    local want = TEXT[label]:gsub("{DONE}", ""):gsub("{PROMPT}", "")
    eq(table.concat(CardFlip.lines(GAME.data, key), "\n"), want,
      "card flip " .. key .. " is " .. label)
  end
  check(not pcall(CardFlip.new, BARE, { save = save }), "card flip errors without its text")
end

do
  local save = { player = { coins = 0 } }
  local slots = SlotMachine.new(GAME, { save = save, random = function() return 0 end })
  slots.drawBackground, slots.drawReels, slots.drawOverlays = noop, noop, noop
  local out = capture(function() slots:drawPanel() end)
  check(has(out, "~Bet how many") and has(out, "coins?"),
    "the slot bet box is _SlotsBetHowManyCoinsText")
  for i = 1, 3 do
    check(has(out, TEXT["Slots_AskBet.MenuData#" .. i]),
      "and bet row " .. i .. " is Slots_AskBet.MenuData#" .. i)
  end
  slots.phase, slots.againChoice = "again", 1
  out = capture(function() slots:drawPanel() end)
  check(has(out, "~Play again?"), "play again is _SlotsPlayAgainText")
  check(has(out, TEXT[YES]) and has(out, TEXT[NO]), "with the YES/NO labels")
  slots.matched = SlotMachine.CHERRY
  slots:beginPayout()
  eq(slots.message[1], "    ~lined up!", "the payout line leaves room for the symbol")
  eq(slots.message[2], "Won 6 coins!", "and fills _SlotsLinedUpText's STRBUF")
  local bare = SlotMachine.new(BARE, { save = save })
  bare.drawBackground, bare.drawReels, bare.drawOverlays = noop, noop, noop
  check(not pcall(bare.drawPanel, bare), "the slot machine errors without its text")
end

prints("MartMenu BUY/SELL/QUIT", function(game)
  setmetatable({ game = game, topIndex = 1 }, MartMenu):drawTopMenu()
end, { "MenuHeader_BuySell.MenuData#1", "MenuHeader_BuySell.MenuData#2",
  "MenuHeader_BuySell.MenuData#3" })

prints("MartMenu buy list CANCEL", function(game)
  setmetatable({ game = game, entries = {}, scroll = 0, index = 1 }, MartMenu):drawBuyList()
end, { "ScrollingMenu_UpdateDisplay.CancelString" })

do
  local out = capture(function()
    setmetatable({ game = GAME, index = 0, drawPic = noop }, UnownPrinter):drawPanel()
  end)
  check(has(out, "A~ PRINT") and has(out, "B CANCEL") and has(out, "\xe2\x86\x90 PREVIOUS"),
    "the printer menu is UnownDexMenuString#1 with the bold A/B stand-ins")
end

prints("TradeAnim stats template", function(game)
  TradeAnimView.drawStats({ data = game.data }, { name = "X", otName = "Y" }, 0)
end, {})
do
  local out = capture(function()
    TradeAnimView.drawStats({ data = GAME.data }, { name = "X", otName = "Y" }, 0)
  end)
  check(has(out, "~\xe2\x94\x80\xe2\x94\x80\xe2\x94\x80 \xc2\xb7.") and has(out, "OT/")
    and has(out, "\xe2\x80\x9d\xc2\xb7."), "the trade stats template is TrademonStats_MonTemplate.OTMonData")
end

do
  local data = { text = {} }
  for label, text in pairs(FIXTURE) do
    if type(text) == "string" then data.text[label] = text end
  end
  local screen = MailCompose.new({ data = data }, {})
  eq(table.concat(screen.upper[5], " "), data.text["MailEntry_Uppercase#5"],
    "the mail keyboard is MailEntry_Uppercase cell for cell")
  eq(screen.lowerKeys.bottom, data.text["MailEntry_Lowercase#6"],
    "and its strip is MailEntry_Lowercase#6")
  check(not pcall(MailCompose.new, BARE, {}), "and errors without it")
end

S.finish()
