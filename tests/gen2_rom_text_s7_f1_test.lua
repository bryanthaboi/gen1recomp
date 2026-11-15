-- ../pokegold/engine/events/prof_oaks_pc.asm:107
-- ../pokegold/engine/events/pokecenter_pc.asm:15
-- ../pokegold/engine/events/mom.asm:567
-- ../pokegold/engine/events/fruit_trees.asm:98
-- ../pokegold/home/menu.asm:429
package.path = "./?.lua;./?/init.lua;" .. package.path

love = love or require("tests.love_stub")

local S = require("tests.harness").suite("gen2 rom text s7 f1")
require("tests.fixture_data.gen2_engine_flags").bind("gold")
local check, eq = S.check, S.eq

require("src.core.Logger").warn = function() end

local Fixture = require("tests.fixture_data.gen2_rom_text_s7_f1")
local Chrome = require("src.ui.gen2.Chrome")
local Events = require("src.world.gen2.Events")
local Specials = require("src.script.gen2.Specials")
local Vm = require("src.script.gen2.Vm")

local function marked(labels)
  local text = Fixture.text()
  for _, label in ipairs(labels) do text[label] = "ROM " .. label end
  return text
end

local function flat(pages)
  local out = {}
  for _, page in ipairs(pages or {}) do
    for _, line in ipairs(page) do out[#out + 1] = line end
  end
  return table.concat(out, "|")
end

local function newInput()
  local input = { pressed = {} }
  function input:wasPressed(button)
    if self.pressed[button] then
      self.pressed[button] = nil
      return true
    end
    return false
  end
  function input:isDown() return false end
  return input
end

local function centerGame(text, caught, events)
  local Save = require("src.core.gen2.Save")
  local save = Save.newGame({ playerName = "GOLD", trainerId = 1 })
  save.party[1] = { species = "CYNDAQUIL", hp = 20, maxHp = 20, level = 10 }
  save.engineFlags = { [11] = true }
  local dex = {}
  for i = 1, caught or 0 do dex["MON" .. i] = true end
  save.pokedex = { seen = dex, caught = dex }
  return { input = newInput(), save = save,
    data = { audio = {}, pokemon = {}, items = {}, text = text,
      gen2EventTables = events or Fixture.events() },
    stack = { push = function() end, pop = function() end,
      top = function() return nil end } }
end

do
  local CenterPcMenu = require("src.ui.gen2.CenterPcMenu")
  local text = Fixture.text()
  text._OakPCText2 = "ROM COMPLETION\nLEVEL{PROMPT}"
  text._OakPCText3 = "{STRBUF} ROM SEEN\n{STRBUF} ROM OWNED{DONE}"
  text.OakRating02 = "ROM RATING\nTWO{DONE}"
  local game = centerGame(text, 12)
  local pc = CenterPcMenu.new(game, { save = game.save })
  pc.message = nil
  pc:oakRate()
  eq(flat(pc.message.pages), "ROM COMPLETION|LEVEL|12 ROM SEEN|12 ROM OWNED|ROM RATING|TWO",
    "the rating pages are _OakPCText2, _OakPCText3 and OakRating02 out of data.text")
  eq(pc.message.pages[3].sfx, "Sfx_DexFanfareLessThan20",
    "the rating page carries OakRatings' fanfare")

  for _, label in ipairs({ "_OakPCText2", "_OakPCText3", "OakRating02" }) do
    local missing = centerGame(Fixture.without(label), 12)
    missing.data.gen2EventTables = Fixture.events()
    local menu = CenterPcMenu.new(missing, { save = missing.save })
    local ok, err = pcall(menu.oakRate, menu)
    check(not ok and tostring(err):find(label, 1, true) ~= nil,
      "a cache without " .. label .. " is an error, not a transcription")
  end

  local labels = {
    "PokemonCenterPC.String_BillsPC", "PokemonCenterPC.String_OaksPC",
    "PokemonCenterPC.String_TurnOff", "_PokecenterPCTurnOnText",
  }
  local rows = CenterPcMenu.new(centerGame(marked(labels)), {})
  local got = {}
  for _, entry in ipairs(rows.entries) do got[#got + 1] = entry.label end
  eq(table.concat(got, "|"),
    "ROM PokemonCenterPC.String_BillsPC|GOLD's PC|ROM PokemonCenterPC.String_OaksPC|"
      .. "ROM PokemonCenterPC.String_TurnOff",
    "the whose-PC rows are PokemonCenterPC's own strings")
  eq(flat(rows.message.pages), "ROM _PokecenterPCTurnOnText",
    "the boot line is _PokecenterPCTurnOnText")
  check(not pcall(CenterPcMenu.new, centerGame(Fixture.without("PokemonCenterPC.String_BillsPC")), {}),
    "a cache without the menu rows is an error")

  local printed = {}
  local realPrint, realBox, realCursor = Chrome.print, Chrome.box, Chrome.cursor
  Chrome.print = function(s) printed[#printed + 1] = s end
  Chrome.box = function() end
  Chrome.cursor = function() end
  local yn = CenterPcMenu.new(centerGame(marked({
    "YesNoMenuHeader.MenuData#1", "YesNoMenuHeader.MenuData#2" })), {})
  yn.message = nil
  yn.booted = false
  yn.confirm = { prompt = { "Q" }, choice = 1 }
  yn:drawPanel()
  Chrome.print, Chrome.box, Chrome.cursor = realPrint, realBox, realCursor
  local all = table.concat(printed, "|")
  check(all:find("ROM YesNoMenuHeader.MenuData#1", 1, true) ~= nil
    and all:find("ROM YesNoMenuHeader.MenuData#2", 1, true) ~= nil,
    "the PC's yes/no is YesNoMenuHeader's YES and NO")
end

do
  local text = marked({ "_OakPCText2", "OakRating01" })
  text._OakPCText3 = "{STRBUF}/{STRBUF} ROM COUNTS{DONE}"
  local function boot(data)
    local vm = Vm.new({}, {}, Events.new(), { specials = {
      save = function() return { pokedex = { seen = { A = true }, caught = {} } } end,
      data = function() return data end,
    } })
    vm.showTextFn = function() end
    local texts = {}
    vm.co = coroutine.create(function() Specials.HANDLERS.ProfOaksPCBoot(vm) end)
    local ok, req = coroutine.resume(vm.co)
    while true do
      if not ok then error(req, 0) end
      if req and req.kind == "text" then texts[#texts + 1] = req.text end
      if coroutine.status(vm.co) == "dead" then break end
      ok, req = coroutine.resume(vm.co)
    end
    return texts
  end
  eq(table.concat(boot({ text = text, gen2EventTables = Fixture.events() }), "|"),
    "ROM _OakPCText2|1/0 ROM COUNTS{DONE}|ROM OakRating01",
    "ProfOaksPCBoot prints the three pages through romLine")
  local moved = Fixture.events({ oakRatings = {
    { max = 255, sfx = "Sfx_CaughtMon", text = "OakRating07" } } })
  eq(boot({ text = marked({ "OakRating07" }), gen2EventTables = moved })[3], "ROM OakRating07",
    "the rating row comes from events.oakRatings, not a Lua table")
  local ok, err = pcall(boot, { text = text, gen2EventTables = {} })
  check(not ok and tostring(err):find("oakRatings", 1, true) ~= nil,
    "an events.lua without oakRatings is an error")
  check(not pcall(boot, { text = Fixture.without("OakRating01"), gen2EventTables = Fixture.events() }),
    "and a cache without the rating is an error")
end

do
  local function cut(handler, events, roll)
    local mon = { species = "CHIKORITA", happiness = 50 }
    local vm = Vm.new({}, {}, Events.new(), { specials = {
      party = function() return { mon } end,
      monName = function(sp) return sp end,
      selectPartyMon = function(_, done) done(1, mon) end,
      data = function() return { text = Fixture.text(), gen2EventTables = events } end,
    } })
    local saved = Specials.random
    Specials.random = function() return roll end
    local ok, err = pcall(Specials.HANDLERS[handler], vm)
    Specials.random = saved
    if not ok then error(err, 0) end
    return vm.scriptVar
  end
  eq(cut("OlderHaircutBrother", Fixture.events(), 0), 2,
    "the older brother's first row out of events.haircutTables answers 2")
  eq(cut("OlderHaircutBrother", Fixture.events({ haircutTables = {
    older = { { 255, 3, "OLDERCUT2" } }, younger = {}, daisy = {} } }), 0), 3,
    "the rows are events.haircutTables', not Specials'")
  check(not pcall(cut, "DaisysGrooming", {}, 0),
    "an events.lua without haircutTables is an error")
  eq(Specials.HAIRCUT_TABLES, nil, "no hand-typed HAIRCUT_TABLES")

  local GameVersion = require("src.core.GameVersion")
  local function kurtCancel(version, text)
    GameVersion.set(version)
    local rows
    local vm = Vm.new({}, {}, Events.new(), { specials = {
      save = function() return { inventory = { RED_APRICORN = 1 } } end,
      data = function() return { text = text } end,
      itemName = function(id) return id end,
      scriptMenu = function(header, done) rows = header.items done(0) end,
    } })
    local ok, err = pcall(Specials.HANDLERS.SelectApricornForKurt, vm)
    GameVersion.set("red")
    if not ok then error(err, 0) end
    return rows and rows[#rows]
  end
  eq(kurtCancel("gold", marked({ "Kurt_SelectApricorn.Cancel" })),
    "ROM Kurt_SelectApricorn.Cancel", "Gold's Kurt CANCEL is Kurt_SelectApricorn.Cancel")
  eq(kurtCancel("crystal", marked({ "ScrollingMenu_UpdateDisplay.CancelString" })),
    "ROM ScrollingMenu_UpdateDisplay.CancelString",
    "Crystal's is the scrolling menu's CancelString")
  check(not pcall(kurtCancel, "silver", Fixture.without("Kurt_SelectApricorn.Cancel")),
    "a cache without Kurt's CANCEL is an error")
end

do
  local function bank(data)
    local rec = { player = { money = 0 }, mom = { savedMoney = 0, active = true } }
    local vm = Vm.new({}, {}, Events.new(), { specials = {
      save = function() return rec end,
      data = function() return data end,
      money = function() return 0 end,
      setMoney = function() end,
    } })
    vm.showTextFn = function() end
    local texts, menus = {}, {}
    vm.co = coroutine.create(function() Specials.HANDLERS.BankOfMom(vm) end)
    local ok, req = coroutine.resume(vm.co)
    while true do
      if not ok then error(req, 0) end
      if req and req.kind == "text" then texts[#texts + 1] = req.text end
      if req and req.kind == "menu" then menus[#menus + 1] = req.header end
      if coroutine.status(vm.co) == "dead" then break end
      local answer = nil
      if req and req.kind == "yesorno" then answer = true end
      if req and req.kind == "menu" then answer = 4 end
      ok, req = coroutine.resume(vm.co, answer)
    end
    return texts, menus
  end
  local labels = { "_MomIsThisAboutYourMoneyText", "_MomBankWhatDoYouWantToDoText",
    "_MomJustDoWhatYouCanText", "BankOfMom_MenuHeader.MenuData#1",
    "BankOfMom_MenuHeader.MenuData#4" }
  local texts, menus = bank({ text = marked(labels) })
  eq(table.concat(texts, "|"),
    "ROM _MomIsThisAboutYourMoneyText|ROM _MomBankWhatDoYouWantToDoText|ROM _MomJustDoWhatYouCanText",
    "Mom's lines are the _Mom* labels out of data.text")
  eq(menus[1] and menus[1].items[1], "ROM BankOfMom_MenuHeader.MenuData#1",
    "GET is BankOfMom_MenuHeader's first row")
  eq(menus[1] and menus[1].items[4], "ROM BankOfMom_MenuHeader.MenuData#4",
    "CANCEL its last")
  check(not pcall(bank, { text = Fixture.without("_MomBankWhatDoYouWantToDoText") }),
    "a cache without Mom's bank text is an error")

  local BankOfMom = require("src.ui.gen2.BankOfMom")
  local printed = {}
  local realPrint, realBox = Chrome.print, Chrome.box
  Chrome.print = function(s) printed[#printed + 1] = s end
  Chrome.box = function() end
  local keypad = BankOfMom.new({ data = { text = marked({ "Mom_SavedString",
    "Mom_HeldString", "Mon_WithdrawString" }) } }, { kind = "withdraw" })
  keypad:drawPanel()
  Chrome.print, Chrome.box = realPrint, realBox
  local all = table.concat(printed, "|")
  check(all:find("ROM Mom_SavedString", 1, true) and all:find("ROM Mom_HeldString", 1, true)
    and all:find("ROM Mon_WithdrawString", 1, true),
    "the keypad's SAVED / HELD / WITHDRAW are mom.asm's strings")
end

do
  local function tree(data, picked)
    local log = {}
    local vm = Vm.new({ generation = 2, ["s:t"] = { { op = "fruittree", tree = 1 } } },
      {}, Events.new(), {
        showText = function(body, onDone)
          log[#log + 1] = body
          onDone()
        end,
        getItemName = function() return "PRZCUREBERRY" end,
        fruitTreeItem = function() return 158 end,
        fruitTreePicked = function() return picked end,
        giveItem = function() return true end,
        specials = { data = function() return data end },
      })
    vm:start("s:t")
    for _ = 1, 40 do
      if not vm:running() then break end
      vm:update()
    end
    return log
  end
  local text = marked({ "_FruitBearingTreeText", "_NothingHereText" })
  text._HeyItsFruitText = "ROM HEY {STRBUF}{DONE}"
  text._ObtainedFruitText = "ROM GOT {STRBUF}{DONE}"
  local log = tree({ text = text }, false)
  eq(log[1], "ROM _FruitBearingTreeText", "the tree opens on _FruitBearingTreeText")
  eq(log[2], "ROM HEY PRZCUREBERRY{DONE}", "then _HeyItsFruitText names the fruit")
  eq(log[3], "ROM GOT PRZCUREBERRY{DONE}", "and _ObtainedFruitText")
  eq(tree({ text = text }, true)[2], "ROM _NothingHereText",
    "a picked tree is _NothingHereText")
  local ok = pcall(tree, { text = Fixture.without("_FruitBearingTreeText") }, false)
  check(not ok, "a cache without the fruit tree text is an error")
end

do
  local PackMenu = require("src.ui.gen2.PackMenu")
  local printed = {}
  local real = { box = Chrome.box, printThrough = Chrome.printThrough,
    cursorThrough = Chrome.cursorThrough }
  Chrome.box = function() end
  Chrome.printThrough = function(s) printed[#printed + 1] = s end
  Chrome.cursorThrough = function() end
  local function yesNo(text)
    local fake = setmetatable({ game = { data = { text = text } },
      confirm = { choice = 1 } }, { __index = PackMenu })
    fake:drawYesNo()
  end
  yesNo(marked({ "YesNoMenuHeader.MenuData#1", "YesNoMenuHeader.MenuData#2" }))
  local shown = table.concat(printed, "|")
  local ok = pcall(yesNo, Fixture.without("YesNoMenuHeader.MenuData#2"))
  Chrome.box, Chrome.printThrough, Chrome.cursorThrough =
    real.box, real.printThrough, real.cursorThrough
  eq(shown, "ROM YesNoMenuHeader.MenuData#1|ROM YesNoMenuHeader.MenuData#2",
    "the PACK's YES/NO is YesNoMenuHeader's")
  check(not ok, "a cache without NO is an error")

  local noTiles = setmetatable({ gfx = { available = function() return false end } },
    { __index = PackMenu })
  local drew, err = pcall(noTiles.drawPanel, noTiles)
  check(not drew and tostring(err):find("PACK tiles", 1, true) ~= nil,
    "with no PACK tiles the screen is an error, not a plain-box fallback")
  for _, pocket in ipairs(PackMenu.POCKETS) do
    eq(pocket.label, nil, pocket.id .. " carries no hand-typed pocket label")
  end
end

do
  local text = marked({ "_PhoneClickText" })
  text._ReceivedItemText = "ROM RECEIVED {STRBUF}{DONE}"
  local log = {}
  local vm = Vm.new({ generation = 2, ["s:t"] = {
    { op = "hangup" },
    { op = "verbosegiveitem", item = 18, quantity = 1 },
  } }, {}, Events.new(), {
    showText = function(body, onDone)
      log[#log + 1] = body
      onDone()
    end,
    getItemName = function() return "POTION" end,
    giveItem = function() return true end,
    specials = { data = function() return { text = text } end },
  })
  vm:start("s:t")
  for _ = 1, 40 do
    if not vm:running() then break end
    vm:update()
  end
  eq(log[1], "ROM _PhoneClickText", "hangup's Click! is _PhoneClickText")
  eq(log[2], "ROM RECEIVED POTION{DONE}", "verbosegiveitem opens on _ReceivedItemText")
  eq(log[3], (Fixture.RAW._PutItemInPocketText:gsub("{STRBUF}", "POTION", 1)
      :gsub("{STRBUF}", Fixture.RAW["ItemPocketNames.Item"])),
    "and _PutItemInPocketText names the item and ItemPocketNames.Item")

  local record = { party = {} }
  local gift = Vm.new({}, {}, Events.new(), { specials = {
    party = function() return record.party end,
    save = function() return record end,
    data = function()
      return { text = marked({ "SpecialShuckleOT", "SpecialShuckleNickname" }),
        moves = { CONSTRICT = { name = "CONSTRICT", pp = 35 } },
        pokemon = { SHUCKLE = { name = "SHUCKLE", index = 213,
          growthRate = "MEDIUM_FAST",
          baseStats = { hp = 20, attack = 10, defense = 230, speed = 5,
            specialAttack = 10, specialDefense = 230 },
          levelMoves = { { level = 1, move = "CONSTRICT" } } } } }
    end,
  } })
  Specials.HANDLERS.GiveShuckle(gift)
  local mon = record.party[1] or {}
  eq(mon.ot, "ROM SpecialShuckleOT", "Mania's OT is SpecialShuckleOT")
  eq(mon.nickname, "ROM SpecialShuckleNickname", "SHUCKIE is SpecialShuckleNickname")

  local PhotoStudio = require("src.ui.gen2.PhotoStudio")
  local printed = {}
  local realPrint = Chrome.print
  Chrome.print = function(s) printed[#printed + 1] = s end
  local realClear, realTextbox = Chrome.clear, Chrome.textbox
  Chrome.clear = function() end
  Chrome.textbox = function() end
  local card = PhotoStudio.new({ data = { text = marked({ "PrintParty_OTString",
    "PrintParty_IDNoString", "PrintParty_MoveString", "PrintParty_NoMoveString" }) } },
    { mon = { species = "X", level = 5 }, playerName = "GOLD" })
  card.drawPic = function() end
  card:drawPanel()
  Chrome.print, Chrome.clear, Chrome.textbox = realPrint, realClear, realTextbox
  local all = table.concat(printed, "|")
  for _, label in ipairs({ "PrintParty_OTString", "PrintParty_IDNoString",
      "PrintParty_MoveString", "PrintParty_NoMoveString" }) do
    check(all:find("ROM " .. label, 1, true) ~= nil, "the photo card prints " .. label)
  end
end

S.finish()
