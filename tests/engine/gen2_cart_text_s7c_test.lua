package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.harness")
require("tests.fixture_data.gen2_engine_flags").bind("gold")
love = require("tests.love_stub")
require("src.core.Logger").warn = function() end

local Chrome = require("src.ui.gen2.Chrome")
local Fixture = require("tests.fixture_data.gen2_rom_text_s7_c")
local MainMenu = require("src.ui.gen2.MainMenu")
local NamingScreen = require("src.ui.gen2.NamingScreen")
local OptionsMenu = require("src.ui.gen2.OptionsMenu")
local Save = require("src.core.gen2.Save")
local SaveMenu = require("src.ui.gen2.SaveMenu")
local StartMenu = require("src.ui.gen2.StartMenu")
local TrainerCard = require("src.ui.gen2.TrainerCard")

local MARKED = {
  StringOptions = "OPT A\n        :\nOPT B\n        :\nOPT C\n        :\nOPT D\n"
    .. "        :\nOPT E\n        :\nOPT F\n        :\nOPT G\n        :KIND\nOPT X",
  ["Options_TextSpeed.Mid"] = "MEDIO",
  ["StartMenu.PokedexString"] = "DEXA",
  ["StartMenu.PokedexDesc"] = "uno\ndos",
  ["StartMenu.StatusString"] = "[{PLAYER}]",
  ["MainMenu.Strings#2"] = "NUEVO",
  ["MainMenu.Strings#3"] = "AJUSTE",
  _WouldYouLikeToSaveTheGameText = "Guardar\nahora?{DONE}",
  ["Continue_LoadMenuHeader.MenuData_NoDex#1"] = "JUGADOR {PLAYER}",
  ["NamingScreenJumptable.PlayerNameString"] = "TU NOMBRE?",
  ["TrainerCard_PrintTopHalfOfCard.Name_Money"] = "NOM/\n\nDINERO",
  ["TrainerCard_Page1_PrintDexCaught_GameTime.Badges"] = "  MEDALLAS\xe2\x96\xb6",
  CoinString = "FICHA",
}

local function stack()
  local s = { items = {} }
  function s:push(x) self.items[#self.items + 1] = x; return x end
  function s:pop() self.items[#self.items] = nil end
  function s:top() return self.items[#self.items] end
  return s
end

local function game(text, save)
  return { data = { text = text }, save = save, stack = stack(),
    options = Save.defaultOptions() }
end

local function capture(fn)
  local printed = {}
  local realPrint, realThrough = Chrome.print, Chrome.printThrough
  Chrome.print = function(text, tx, ty) printed[#printed + 1] = { text, tx, ty } end
  Chrome.printThrough = function(text, tx, ty)
    printed[#printed + 1] = { text, tx, ty }
    return 0
  end
  local ok, err = pcall(fn)
  Chrome.print, Chrome.printThrough = realPrint, realThrough
  if not ok then error(err, 0) end
  return printed
end

local function at(printed, tx, ty)
  for _, row in ipairs(printed) do
    if row[2] == tx and row[3] == ty then return row[1] end
  end
end

local text = Fixture.text(MARKED)

-- engine/menus/options_menu.asm:74 StringOptions
do
  local options = Save.defaultOptions()
  options.textSpeed = "MID"
  local menu = OptionsMenu.new(game(text), { options = options })
  local page = menu:focusRow("textSpeed")
  local printed = capture(function() page:drawPanel() end)
  T.eq(at(printed, 2, 2), "OPT A", "OPTION prints StringOptions line 1 as TEXT SPEED")
  T.eq(at(printed, 10, 3), ":", "and the colon StringOptions puts eight columns in")
  T.eq(at(printed, 11, 3), "MEDIO", "and Options_TextSpeed.Mid as its value")
  local cancel
  for _, row in ipairs(menu.rows) do if row.cancel then cancel = row end end
  T.eq(cancel and cancel.label, "OPT X", "the cancel row is StringOptions line 15")
  T.raises(function() OptionsMenu.new(game(Fixture.without("StringOptions"))) end,
    "StringOptions", "OPTION without StringOptions is an error")
end

-- engine/menus/start_menu.asm:189-233
do
  local save = Save.newGame({ playerName = "ANA" })
  save.pokedexReceived = true
  local menu = StartMenu.new(game(text, save), { save = save })
  local byId = {}
  for _, item in ipairs(menu.items) do byId[item.value] = item end
  T.eq(byId.pokedex and byId.pokedex.label, "DEXA", "START prints StartMenu.PokedexString")
  T.eq(byId.pokedex and byId.pokedex.desc[2], "dos", "and .PokedexDesc line by line")
  T.eq(byId.status and byId.status.label, "[ANA]", "and .StatusString with <PLAYER> filled")
  T.raises(function()
    StartMenu.new(game(Fixture.without("StartMenu.PokedexString"), save), { save = save })
  end, "StartMenu.PokedexString", "START without the label is an error")
end

-- engine/menus/main_menu.asm:67
do
  local menu = MainMenu.new(game(text), { hasSave = false, save = false })
  T.eq(menu.list.items[1].label, "NUEVO", "the intro menu prints MainMenu.Strings#2")
  T.eq(menu.list.items[2].label, "AJUSTE", "and #3")
  T.raises(function()
    MainMenu.new(game(Fixture.without("MainMenu.Strings#2")), { hasSave = false, save = false })
  end, "MainMenu.Strings#2", "the intro menu without it is an error")
end

-- data/text/common_2.asm:1274, engine/menus/intro_menu.asm:423
do
  local save = Save.newGame({ playerName = "ANA" })
  local menu = SaveMenu.new(game(text, save), { save = save, existed = false,
    writer = function() return true end })
  T.eq(menu:promptText(), "Guardar\nahora?", "SAVE asks _WouldYouLikeToSaveTheGameText")
  T.eq(SaveMenu.panelLabels({ text = text }, "ANA")[1], "JUGADOR ANA",
    "and the panel's first row is MenuData_NoDex#1 with <PLAYER>")
  local bare = SaveMenu.new(game(Fixture.without("_WouldYouLikeToSaveTheGameText"), save),
    { save = save, existed = false })
  T.raises(function() bare:promptText() end, "_WouldYouLikeToSaveTheGameText",
    "SAVE without it is an error")
end

-- engine/menus/naming_screen.asm:132
do
  local data = require("tests.fixtures.gen2_naming").fill({ text = text })
  local naming = NamingScreen.new({ data = data }, { type = "player" })
  T.eq(naming.prompt, "TU NOMBRE?", "the naming screen prints .PlayerNameString")
  local bare = require("tests.fixtures.gen2_naming").fill({
    text = Fixture.without("NamingScreenJumptable.PlayerNameString") })
  T.raises(function() NamingScreen.new({ data = bare }, { type = "player" }) end,
    "PlayerNameString", "and errors without it")
end

-- data/text/name_input_chars.asm:18 NameInputUpper, data/player_names.asm:25
do
  local NamePick = require("src.ui.gen2.NamePick")
  local keyed = Fixture.text({
    ["NameInputUpper#1"] = "Q W E R T Y U I O",
    ["NameInputUpper#5"] = "abcde  DEL   FIN ",
    ["PlayerNameArray#5"] = "NOMBRE",
  })
  local naming = NamingScreen.new({ data = require("tests.fixtures.gen2_naming").fill({
    text = keyed }) }, { type = "player" })
  T.eq(naming:characterAt(0, 0), "Q", "the keyboard's first cell is NameInputUpper#1's")
  T.eq(naming:board().bottom[1].text, "abcde", "the case label is NameInputUpper#5's")
  T.eq(naming:board().bottom[3].tx, 15, "and END lands where that row puts it")
  T.raises(function()
    NamingScreen.new({ data = require("tests.fixtures.gen2_naming").fill({
      text = Fixture.without("NameInputUpper#1") }) }, { type = "player" })
  end, "NameInputUpper#1", "the naming screen without a keyboard row is an error")
  local pick = NamePick.new({ data = { text = keyed } }, {})
  T.eq(pick.title, "NOMBRE", "the name menu's title is PlayerNameArray#5")
  T.raises(function() NamePick.new({ data = { text = Fixture.without("PlayerNameArray#5") } }, {}) end,
    "PlayerNameArray#5", "and errors without it")
end

-- engine/menus/trainer_card.asm:269, :313
do
  local CARD = { trainerCard = require("tests.fixture_data.gen2_trainer_card_s7_c").gold }
  local card = TrainerCard.new(game(text), { save = { player = { name = "ANA" } },
    menuGfx = CARD })
  local priorQuad = love.graphics.newQuad
  love.graphics.newQuad = function(x, y, w, h)
    return { getViewport = function() return x, y, w, h end }
  end
  local printed = capture(function() card:drawCard() end)
  love.graphics.newQuad = priorQuad
  T.eq(at(printed, 2, 2), "NOM/", "the card prints .Name_Money's first line")
  T.eq(at(printed, 2, 6), "DINERO", "and its third two rows further down")
  T.eq(at(printed, 12, 15), "MEDALLAS", "and .Badges at the cart's column")
  T.raises(function()
    TrainerCard.new(game(Fixture.without("TrainerCard_PrintTopHalfOfCard.Name_Money")),
      { menuGfx = CARD })
  end, "Name_Money", "and errors without it")
end

-- engine/menus/menu_2.asm:108 CoinString
do
  local printed = capture(function() Chrome.coinBalanceBox({ text = text }, 7) end)
  T.eq(at(printed, 12, 0), "FICHA", "the coin box prints CoinString")
  T.raises(function() Chrome.coinBalanceBox({ text = Fixture.without("CoinString") }, 7) end,
    "CoinString", "and errors without it")
end

T.finish("gen2 cart text s7c")
