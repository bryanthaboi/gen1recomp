-- ../pokegold/engine/pokemon/breeding.asm:355 .Text_HatchEgg
-- ../pokegold/engine/events/move_deleter.asm:62
-- ../pokegold/engine/events/name_rater.asm:181
-- ../pokegold/engine/items/pack.asm:311 MenuHeader_UsableKeyItem
package.path = "./?.lua;./?/init.lua;" .. package.path

love = love or require("tests.love_stub")

local S = require("tests.harness").suite("gen2 rom text s6")
local check, eq = S.check, S.eq

require("src.core.Logger").warn = function() end

local CommonFixture = require("tests.fixtures.gen2_common_text")
local RomFixture = require("tests.fixtures.gen2_rom_text")

do
  local World = require("src.world.gen2.World")
  local text = CommonFixture.text()
  text[text.labels.Text_BreedHuh] = "ROM HUH\f"
  text[text.labels._BreedEggHatchText] = "{STRBUF} ROM HATCH"
  text[text.labels._BreedAskNicknameText] = "ROM NAME {STRBUF}?{DONE}"
  local shown, asked = {}, nil
  local fake = {
    game = { save = {}, data = {} },
    text = text,
    showText = function(_, body, onDone)
      shown[#shown + 1] = body
      if onDone then onDone() end
    end,
    caughtDataOpts = function() return {} end,
    playSfxNamed = function() end,
    restoreMapMusic = function() end,
  }
  function fake:askYesNo(onChoose)
    asked = self.lastText
    onChoose(false)
  end
  package.loaded["src.core.gen2.Breeding"] = {
    readyToHatch = function() return { 1 } end,
    hatch = function() return { species = "TOGEPI" }, {} end,
  }
  World.hatchEggs(fake)
  package.loaded["src.core.gen2.Breeding"] = nil
  eq(shown[1], "ROM HUH\f", "the hatch opens on Text_BreedHuh from text.lua")
  eq(shown[2], "TOGEPI ROM HATCH", "_BreedEggHatchText names the hatchling")
  eq(asked, "ROM NAME TOGEPI?{DONE}", "the nickname question is _BreedAskNicknameText")
  fake.text = { labels = {} }
  check(not pcall(World.hatchEggs, fake), "a text.lua with no hatch labels is an error")
end

do
  local Specials = require("src.script.gen2.Specials")
  local Vm = require("src.script.gen2.Vm")
  local Events = require("src.world.gen2.Events")
  local function drive(handler, hooks, answers, text)
    hooks.data = function() return { text = text } end
    local texts, ai = {}, 0
    local vm = Vm.new({}, {}, Events.new(), { specials = hooks })
    vm.showTextFn = function() end
    vm.co = coroutine.create(function() Specials.HANDLERS[handler](vm) end)
    local ok, req = coroutine.resume(vm.co)
    while true do
      if not ok then error(req) end
      local answer
      if req and req.kind == "text" then texts[#texts + 1] = req.text end
      if req and req.kind == "yesorno" then ai = ai + 1 answer = answers[ai] end
      if coroutine.status(vm.co) == "dead" then break end
      ok, req = coroutine.resume(vm.co, answer)
    end
    return texts
  end
  local text = RomFixture.text({
    _DeleterIntroText = "ROM DELETER INTRO{DONE}",
    _DeleterNoComeAgainText = "ROM DELETER NO{DONE}",
    _NameRaterHelloText = "ROM RATER HELLO{DONE}",
    _NameRaterComeAgainText = "ROM RATER BYE{DONE}",
  })
  local texts = drive("MoveDeletion", {}, { false }, text)
  eq(texts[1], "ROM DELETER INTRO{DONE}", "MoveDeletion reads _DeleterIntroText")
  eq(texts[2], "ROM DELETER NO{DONE}", "and _DeleterNoComeAgainText")
  texts = drive("NameRater", {}, { false }, text)
  eq(texts[1], "ROM RATER HELLO{DONE}", "NameRater reads _NameRaterHelloText")
  eq(texts[2], "ROM RATER BYE{DONE}", "and _NameRaterComeAgainText")
  check(not pcall(drive, "MoveDeletion", {}, { false }, {}),
    "a rom_text.lua with no deleter text is an error")
  check(not pcall(drive, "NameRater", {}, { false }, {}),
    "a rom_text.lua with no rater text is an error")
end

do
  local PackMenu = require("src.ui.gen2.PackMenu")
  local events = { packSubmenu = { "R-USE", "R-GIVE", "R-TOSS", "R-SEL", "R-QUIT" } }
  local game = { data = { audio = {}, pokemon = {}, items = {}, gen2EventTables = events,
    gen2Text = CommonFixture.text(),
    text = RomFixture.text({ _AskThrowAwayText = "ROM TOSS\nHOW MANY?{DONE}" }) },
    save = { inventory = {}, player = { name = "GOLD" } } }
  local pack = setmetatable({ game = game }, PackMenu)
  eq(pack:submenuLabel("toss"), "R-TOSS", "the submenu's TOSS row is MenuHeader_UsableKeyItem's")
  eq(pack:submenuLabel("quit"), "R-QUIT", "and QUIT")
  eq(pack:romText("_AskThrowAwayText"), "ROM TOSS\nHOW MANY?",
    "TossMenu's question is _AskThrowAwayText")
  game.data.gen2EventTables = {}
  check(not pcall(pack.submenuLabel, pack, "use"), "no packSubmenu in events.lua is an error")
  game.data.text = {}
  check(not pcall(pack.romText, pack, "_AskThrowAwayText"), "no rom_text label is an error")
end

check(not pcall(require, "src.ui.gen2.PrizeMenu"),
  "no prize counter module: the counters are script")

S.finish()
