-- RomExtractorGen2 NAMED_TEXT and the screens that print it.
-- ROM-free: `luajit tests/gen2_common_text_test.lua`.
package.path = "./?.lua;./?/init.lua;" .. package.path

love = love or {}
love.graphics = love.graphics or {
  getColor = function() return 1, 1, 1, 1 end,
  setColor = function() end,
  rectangle = function() end,
  print = function() end,
  printf = function() end,
  draw = function() end,
  newQuad = function() return {} end,
  newImage = function() return nil end,
  getShader = function() return nil end,
  setShader = function() end,
  newShader = function() error("no shaders in this harness") end,
  getDimensions = function() return 160, 144 end,
  push = function() end, pop = function() end,
  translate = function() end, scale = function() end,
  circle = function() end, clear = function() end,
}
love.math = love.math or { random = function(a, b) return b and a or 1 end }
love.image = love.image or {}
love.filesystem = love.filesystem or {
  load = function() return nil end,
  getInfo = function() return nil end,
  read = function() return nil end,
  write = function() return true end,
  remove = function() return true end,
}
love.timer = love.timer or { getTime = function() return 0 end }

local S = require("tests.harness").suite("gen2 common text")
local check, eq = S.check, S.eq

require("src.core.Logger").warn = function() end

local CommonText = require("src.core.gen2.CommonText")
local ContestMenu = require("src.ui.gen2.ContestMenu")
local DayCareMenu = require("src.ui.gen2.DayCareMenu")
local HallOfFame = require("src.ui.gen2.HallOfFame")
local HeldItemMenu = require("src.ui.gen2.HeldItemMenu")
local MailMenu = require("src.ui.gen2.MailMenu")
local MailboxMenu = require("src.ui.gen2.MailboxMenu")
local MartMenu = require("src.ui.gen2.MartMenu")
local Fixture = require("tests.fixtures.gen2_common_text")

local RAW = Fixture.RAW
local TEXT = Fixture.text()

local function flat(pages)
  local out = {}
  for _, page in ipairs(pages or {}) do out[#out + 1] = table.concat(page, "|") end
  return table.concat(out, "/")
end

-- ---- CommonText itself ----------------------------------------------------
do
  eq(CommonText.get(TEXT, "_MartHowManyText"), "How many?{DONE}",
    "a label resolves through text.labels without consuming its terminator")
  eq(CommonText.get(TEXT, "_WhatShouldIRaiseText"),
    "What should I\nraise for you?{PROMPT}",
    "a prompt label retains its distinct terminator")
  check(not pcall(CommonText.get, TEXT, "_NoSuchText"),
    "an unknown label is an error")
  check(not pcall(CommonText.get, {}, "_MartHowManyText"),
    "and so is a cache with no labels table at all")
  check(not pcall(CommonText.of, nil, "_MartHowManyText"),
    "as is no text at all")
  eq(CommonText.get(TEXT, "_DaycareDummyText"), nil,
    "a genuinely empty label is nil")

  local pages = CommonText.pages("one\ntwo\vthree\ffour{DONE}")
  eq(#pages, 3, "para and cont each end a page")
  eq(table.concat(pages[1], "|"), "one|two", "line is the second row")
  eq(table.concat(pages[2], "|"), "two|three", "cont scrolls the row up")
  eq(table.concat(pages[3], "|"), "four", "para starts an empty box")
  eq(#CommonText.pages("just one line"), 1, "a bare string is one page")

  local price = CommonText.of(TEXT, "_MartFinalPriceText", { 2, "POTION", 600 })
  eq(table.concat(price[1], "|"), "2 POTION(S)|will be ¥600.",
    "{NUM} then {STRBUF} then {NUM}")
  local bargain = CommonText.of(TEXT, "_BargainShopFinalPriceText",
    { "POTION", 600 })
  eq(table.concat(bargain[1], "|"), "POTION costs|¥600. Want it?",
    "{STRBUF} then {NUM}")
  local egg = CommonText.of(TEXT, "_ReceivedEggText", { player = "GOLD" })
  eq(table.concat(egg[1], "|"), "GOLD received|the EGG!", "{PLAYER} by name")
  local unset = CommonText.of(TEXT, "_IllRaiseYourMonText", {})
  eq(table.concat(unset[1], "|"), "OK. I'll raise|your .",
    "a marker with no value prints nothing")

  check(not pcall(CommonText.texts, TEXT, { a = "_NoSuchText" }),
    "a screen table naming a label the cache lacks is an error")
end

-- ---- the Day-Care ---------------------------------------------------------
do
  eq(DayCareMenu.TEXT, nil, "no Day-Care transcription")
  local screen = DayCareMenu.new(nil,
    { save = { daycare = {} }, side = "man", text = TEXT })
  local seen = 0
  for key, label in pairs(DayCareMenu.LABELS) do
    seen = seen + 1
    check(RAW[label] ~= nil, label .. " is in the fixture")
    check(screen.TEXT[key] ~= nil, key .. " comes from text.lua")
  end
  eq(seen, 26, "every Day-Care string the screen says is a label")
  eq(flat(screen.TEXT.deposit("NICK")), "OK. I'll raise|your NICK.",
    "_IllRaiseYourMonText fills the nickname")
  eq(flat(screen.TEXT.hasGrown("NICK", 2, 300)),
    "Your NICK|has grown a lot./By level, it's|grown by 2./"
    .. "If you want your|POKéMON back, it/POKéMON back, it|will cost ¥300.",
    "_YourMonHasGrownText fills the name, levels and price in order")
  eq(flat(screen.TEXT.gotBack("GOLD", "NICK")), "GOLD got back|NICK.",
    "_GotBackMonText takes {PLAYER} by name and the mon by {STRBUF}")
  check(not pcall(DayCareMenu.new, nil,
      { save = { daycare = {} }, side = "man" }),
    "a Day-Care with no text.lua is an error, not a transcription")
end

-- ---- the POKeMART ---------------------------------------------------------
local MARTS = { lists = { {} }, bargain = {} }
do
  eq(MartMenu.TEXTS, nil, "no POKeMART transcription")
  local seen = 0
  for kind, labels in pairs(MartMenu.LABELS) do
    if kind ~= "SELL" then
      local screen = MartMenu.new(nil, { martType = kind, text = TEXT,
        save = { money = 1000 }, marts = MARTS })
      for key, label in pairs(labels) do
        seen = seen + 1
        check(RAW[label] ~= nil, label .. " is in the fixture")
        check(screen.text[key] ~= nil,
          ("%s.%s comes from text.lua"):format(kind, key))
      end
    end
  end
  local standard = MartMenu.new(nil, { martType = "STANDARD", text = TEXT,
    save = { money = 1000 }, marts = MARTS })
  for key, label in pairs(MartMenu.LABELS.SELL) do
    seen = seen + 1
    check(RAW[label] ~= nil, label .. " is in the fixture")
    check(standard.sellText[key] ~= nil, ("SELL.%s comes from text.lua"):format(key))
  end
  eq(seen, 33, "every clerk line the screen says is a label")
  eq(table.concat(standard.text.welcome, "|"), "Welcome! How may I|help you?",
    "the welcome line is one screenful")
  eq(table.concat(standard.text.howMany, "|"), "How many?",
    "and so is How many?")
  eq(flat(standard.text.finalPrice(2, "POTION", 600)),
    "2 POTION(S)|will be ¥600.", "_MartFinalPriceText fills qty, name, total")
  eq(flat(standard.sellText.bought("POTION", 600)), "Got ¥600 for|POTION(S).",
    "_MartBoughtText leads with the price")
  local bargain = MartMenu.new(nil, { martType = "BARGAIN", text = TEXT,
    save = { money = 1000 }, marts = MARTS })
  eq(flat(bargain.text.finalPrice(1, "NUGGET", 4500)),
    "NUGGET costs|¥4500. Want it?", "the bargain shop names the item first")
  check(not pcall(MartMenu.new, nil, { martType = "STANDARD",
      save = { money = 1000 }, marts = MARTS }),
    "a mart with no text.lua is an error, not a transcription")
end

do
  for name, M in pairs({ MailboxMenu = MailboxMenu, MailMenu = MailMenu,
      HeldItemMenu = HeldItemMenu }) do
    eq(M.TEXT, nil, name .. " has no transcription")
    for _, label in pairs(M.LABELS) do
      check(RAW[label] ~= nil, label .. " is in the fixture")
    end
  end
  local mail = MailMenu.new(nil, { save = { party = {} }, text = TEXT })
  eq(flat(mail.TEXT.detached("NICK")), "MAIL detached from|NICK.",
    "_MailDetachedText fills the nickname")
  local held = HeldItemMenu.new(nil, { save = { party = {} }, text = TEXT })
  eq(flat(held.TEXT.hold("NICK", "BERRY")), "Made NICK|hold BERRY.",
    "_PokemonHoldItemText fills mon then item")
  eq(flat(held.TEXT.swapped("NICK", "BERRY", "MAIL")),
    "Took NICK's|BERRY and/made it hold|MAIL.",
    "_PokemonSwapItemText pages at its para")
  eq(flat(held.TEXT.cantHold), "This item can't be|held.", "_ItemCantHeldText")
  check(not pcall(HeldItemMenu.new, nil, { save = { party = {} } }),
    "a held-item menu with no text.lua is an error")
  check(not pcall(MailMenu.new, nil, { save = { party = {} } }),
    "and so is a mail menu")
end

-- ---- the Hall of Fame -----------------------------------------------------
do
  eq(HallOfFame.NEW_FAMER, nil, "no Hall of Fame transcription")
  local induct = HallOfFame.headerPlacements("induct", 1, TEXT)
  eq(HallOfFame.at(induct, 1, 2), RAW["AnimateHallOfFame.String_NewHallOfFamer"],
    "the induction header is .String_NewHallOfFamer")
  local viewed = HallOfFame.headerPlacements("view", 12, TEXT)
  eq(HallOfFame.at(viewed, 1, 2), RAW["_HallOfFamePC.TimeFamer"],
    "the PC viewer's header is .TimeFamer")
  eq(HallOfFame.at(viewed, 2, 2), " 12", "the win count lands on its spaces")
  local master = HallOfFame.headerPlacements("view", 100000, TEXT)
  eq(HallOfFame.at(master, 1, 2), RAW["_HallOfFamePC.HOFMaster"],
    "and .HOFMaster past the cap")
  check(not pcall(HallOfFame.headerPlacements, "induct", 1),
    "no text.lua is an error, not a constant")
end

do
  eq(ContestMenu.TEXT, nil, "no contest transcription")
  local t = ContestMenu.texts(TEXT)
  eq(t.stock, " STOCK <PK><MN> ", ".Stock keeps its spaces and the two tiles")
  eq(t.this, " THIS <PK><MN> ", ".This")
  eq(t.health, "HEALTH", ".Health")
  eq(t.askSwitch, "Switch POKéMON?", "_ContestAskSwitchText")
  check(not pcall(ContestMenu.texts, nil), "no text.lua is an error")
end

-- ---- against the cache ----------------------------------------------------
do
  local cacheDir = os.getenv("GOLD_CACHE")
  if not cacheDir then
    local home = os.getenv("HOME") or ""
    for _, base in ipairs({ home .. "/Library/Application Support/LOVE",
        home .. "/.local/share/love" }) do
      for _, id in ipairs({ os.getenv("POKEPORT_IDENTITY") or "", "g1r-gold" }) do
        local root = base .. "/" .. id .. "/gold"
        local f = id ~= "" and io.open(root .. "/data/generated/text.lua", "r")
        if f then
          f:close()
          cacheDir = cacheDir or root
        end
      end
    end
  end
  local textFile = cacheDir and loadfile(cacheDir .. "/data/generated/text.lua")
  if not textFile then
    print("[skip] no Gold cache")
  else
    local text = textFile()
    local missing = {}
    for label, want in pairs(RAW) do
      local key = text.labels and text.labels[label]
      if not key then missing[#missing + 1] = label end
      eq(key and text[key], want, label .. ": the cache carries the ROM string")
    end
    eq(table.concat(missing, ", "), "", "every seeded label is in the cache")
  end
end

S.finish()
