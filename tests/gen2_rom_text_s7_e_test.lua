package.path = "./?.lua;./?/init.lua;" .. package.path

love = require("tests.love_stub")
require("src.core.Logger").warn = function() end

local S = require("tests.harness").suite("gen2 rom text s7 e")
local check, eq = S.check, S.eq

local Fixture = require("tests.fixture_data.gen2_rom_text_s7_e")
local Chrome = require("src.ui.gen2.Chrome")
local Boxes = require("src.core.gen2.Boxes")
local BoxMenu = require("src.ui.gen2.BoxMenu")
local ItemPcMenu = require("src.ui.gen2.ItemPcMenu")
local PartyMenu = require("src.ui.gen2.PartyMenu")
local PcMenu = require("src.ui.gen2.PcMenu")
local PokedexMenu = require("src.ui.gen2.PokedexMenu")
local SummaryMenu = require("src.ui.gen2.SummaryMenu")

local MARKED = {
  ["PCString_ChooseaPKMN"] = "PICK ONE",
  ["BillsPC_BoxName.PartyPKMN"] = "TEAM",
  ["SetDefaultBoxNames.Box"] = "CRATE",
  ["_PCWhatText"] = "HUH?{DONE}",
  ["PlayersPCMenuData.WithdrawItem"] = "TAKE STUFF",
  ["String_Egg"] = "OVUM",
  ["EggString"] = "OVUM PAGE",
  ["FiveQMarkString"] = "!!!!!",
  ["PrintTempMonStats.StatNames"] = "S1\nS2\nS3\nS4\nS5\n",
  ["Pokedex_DrawSearchScreenBG.Menu"] = "GO!!\nBACK",
  ["Pokedex_GetArea.String_SNest"] = " HOME",
  ["String_SEEN"] = "SPOTTED",
  ["Pokedex_DrawSearchScreenBG.Title#1"] = " LOOK \xe3\x81\xb6",
  ["Pokedex_DrawDexEntryScreenBG.Height"] = "HI  ?<ROCKET>??<DEXEND>",
  ["PokedexTypeSearchStrings#2"] = " BASIC  ",
  ["PlacePartyMonTMHMCompatibility.string_able"] = "CAN",
  ["MonMenuOptionStrings#1"] = "INFO",
  ["_BillsPC.strings#5"] = "BYE BYE",
  ["ScrollingMenu_UpdateDisplay.CancelString"] = "BACK OUT",
}

local function text(without)
  local out = {}
  for label, body in pairs(Fixture) do
    if type(body) == "string" then out[label] = body end
  end
  for label, body in pairs(MARKED) do out[label] = body end
  if without then out[without] = nil end
  return out
end

local function game(textTable)
  return {
    input = { wasPressed = function() return false end,
      isDown = function() return false end },
    save = { party = { { species = "CYNDAQUIL", nickname = "CYNDA",
      hp = 10, maxHp = 10, level = 5 } }, boxes = {}, boxNames = {},
      currentBox = 1, pcItems = {}, player = { name = "GOLD" } },
    data = { audio = {}, pokemon = {}, items = {}, moves = {},
      text = textTable },
    stack = { push = function() end, pop = function() end },
  }
end

local function printed(draw)
  local out = {}
  local prior = Chrome.print
  Chrome.print = function(str) out[#out + 1] = tostring(str) end
  local ok, err = pcall(draw)
  Chrome.print = prior
  if not ok then error(err, 0) end
  return table.concat(out, "|")
end

do
  local g = game(text())
  local menu = BoxMenu.new(g, { save = g.save, mode = "deposit" })
  eq(menu:prompt(), "PICK ONE", "BoxMenu prompt is data.text.PCString_ChooseaPKMN")
  eq(menu:title(), "TEAM", "the deposit title is BillsPC_BoxName.PartyPKMN")
  local move = BoxMenu.new(g, { save = g.save, mode = "withdraw" })
  eq(move:title(), "CRATE1", "a default box name is SetDefaultBoxNames.Box plus its number")
  local bare = game(text("PCString_ChooseaPKMN"))
  local broken = BoxMenu.new(bare, { save = bare.save, mode = "deposit" })
  check(not pcall(broken.prompt, broken), "BoxMenu errors without PCString_ChooseaPKMN")
  check(not pcall(Boxes.defaultName, 1, { text = text("SetDefaultBoxNames.Box") }),
    "Boxes.defaultName errors without SetDefaultBoxNames.Box")
end

do
  local g = game(text())
  local pc = PcMenu.new(g, { save = g.save, bills = true })
  local out = printed(function() pc:drawPanel() end)
  check(out:find("HUH?", 1, true) ~= nil, "PcMenu prints data.text._PCWhatText")
  check(out:find("BYE BYE", 1, true) ~= nil, "and _BillsPC.strings#5")
  check(out:find("{DONE}", 1, true) == nil, "without its terminator")
  local bare = game(text("_PCWhatText"))
  local broken = PcMenu.new(bare, { save = bare.save, bills = true })
  check(not pcall(broken.drawPanel, broken), "PcMenu errors without _PCWhatText")
end

do
  local g = game(text())
  local pc = ItemPcMenu.new(g, { save = g.save })
  local out = printed(function() pc:drawPanel() end)
  check(out:find("TAKE STUFF", 1, true) ~= nil,
    "ItemPcMenu prints data.text[PlayersPCMenuData.WithdrawItem]")
  pc.phase = "withdraw"
  out = printed(function() pc:drawPanel() end)
  check(out:find("BACK OUT", 1, true) ~= nil,
    "the item list's CANCEL is ScrollingMenu_UpdateDisplay.CancelString")
  local bare = game(text("PlayersPCMenuData.WithdrawItem"))
  local broken = ItemPcMenu.new(bare, { save = bare.save })
  check(not pcall(broken.drawPanel, broken),
    "ItemPcMenu errors without PlayersPCMenuData.WithdrawItem")
end

do
  local data = { text = text() }
  eq(PartyMenu.rowFor({ isEgg = true }, nil, nil, data).name, "OVUM",
    "a party egg row is data.text.String_Egg")
  check(not pcall(PartyMenu.rowFor, { isEgg = true }, nil, nil,
    { text = text("String_Egg") }), "PartyMenu errors without String_Egg")
  local g = game(text())
  g.data.pokemon.CYNDAQUIL = { tmhm = { "SURF" } }
  local party = PartyMenu.new(g, { party = g.save.party, tmhm = { move = "SURF" } })
  eq(party:tmhmAble(g.save.party[1]), "CAN", "ABLE is PlacePartyMonTMHMCompatibility.string_able")
  eq(party:submenuItems(g.save.party[1])[1].label, "INFO",
    "the STATS row is MonMenuOptionStrings#1")
end

do
  local g = game(text())
  local egg = { isEgg = true, eggSteps = 1 }
  local screen = SummaryMenu.new(g, { mon = egg, save = g.save })
  local page = screen:eggPlacements()
  eq(SummaryMenu.at(page, 8, 1), "OVUM PAGE", "the egg page is data.text.EggString")
  eq(SummaryMenu.at(page, 11, 3), "!!!!!", "and FiveQMarkString")
  local blue = setmetatable({ game = g, mon = { stats = {} }, save = g.save },
    { __index = SummaryMenu }):bluePlacements()
  eq(SummaryMenu.at(blue, 11, 8), "S1", "stat names are PrintTempMonStats.StatNames")
  eq(SummaryMenu.at(blue, 11, 16), "S5", "all five of them")
  local bare = game(text("EggString"))
  local broken = SummaryMenu.new(bare, { mon = egg, save = bare.save })
  check(not pcall(broken.eggPlacements, broken), "SummaryMenu errors without EggString")
end

do
  local g = game(text())
  g.save.pokedex = { seen = {}, caught = {} }
  local dex = PokedexMenu.new(g, {})
  local drawn = {}
  dex.text = function(_, str, x, y) drawn[x .. ":" .. y] = str end
  dex.fill, dex.border, dex.tile = function() end, function() end, function() end
  local tiles = {}
  dex.tile = function(_, id, x, y) tiles[x .. ":" .. y] = id end
  dex:drawSearch()
  eq(drawn["3:13"], "GO!!", "the search menu is Pokedex_DrawSearchScreenBG.Menu")
  eq(drawn["3:15"], "BACK", "line two")
  eq(drawn["1:1"], " LOOK ", "the title is Pokedex_DrawSearchScreenBG.Title#1")
  eq(tiles["7:1"], 0x3c, "and its closing glyph draws as dex tile $3c")
  eq(drawn["9:4"], " BASIC  ", "the TYPE1 wheel is PokedexTypeSearchStrings#2")
  dex:drawMainBackground()
  eq(drawn["1:11"], "SPOTTED", "SEEN is String_SEEN")
  g.data.gen2Pokedex = { entries = { BULBASAUR = { dex = 1, height = 204, weight = 150 } } }
  dex.blank, dex.drawPic, dex.drawFootprint = dex.fill, dex.fill, dex.fill
  dex.cursorVisible = function() return false end
  dex:drawEntryBody({ species = "BULBASAUR" }, g.data.gen2Pokedex.entries.BULBASAUR)
  eq(drawn["9:7"], "HI  ?", ".Height prints up to its foot mark")
  eq(tiles["14:7"], 0x5e, "<ROCKET> is the dex sheet's foot mark")
  eq(tiles["17:7"], 0x5f, "<DEXEND> is the inch mark")
  local bare = game(text("Pokedex_DrawSearchScreenBG.Menu"))
  bare.save.pokedex = { seen = {}, caught = {} }
  local broken = PokedexMenu.new(bare, {})
  broken.text = dex.text
  broken.fill, broken.border, broken.tile = dex.fill, dex.border, dex.tile
  check(not pcall(broken.drawSearch, broken),
    "PokedexMenu errors without Pokedex_DrawSearchScreenBG.Menu")
end

S.finish()
