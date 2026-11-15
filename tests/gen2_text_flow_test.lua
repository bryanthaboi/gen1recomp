-- Script text flow around the intro stretch: Mom's clock ladder confirms in
-- text (InitialSetDSTFlag / InitialClearDSTFlag, engine/rtc/timeset.asm), the
-- NameRival special parks the officer until the keyboard closes
-- (engine/events/specials.asm NameRival), <RIVAL> resolves off the Gold save,
-- Mom's leaving speech keeps the cart's page waits (data/text/common_1.asm
-- _MomLeavingText1), and a stale wStringBuffer2 never leaks into a complete
-- text (the "Obtained the POKeDEX!PSNCUREBERRY!" splice).  The catching
-- tutorial's map-music restore and the Sprout Tower scene's sfx ids ride
-- along: same lane, same seams.
--
--   GOLD_CACHE=".../gold" luajit tests/gen2_text_flow_test.lua
--
-- Everything is ROM-free except the Sprout Tower row pins, which SKIP.
package.path = "./?.lua;./?/init.lua;" .. package.path

local S = require("tests.harness").suite("gen2 text flow")
local check, eq = S.check, S.eq

love = require("tests.love_stub")

local Vm = require("src.script.gen2.Vm")
local Events = require("src.world.gen2.Events")
local ROM_TEXT = require("tests.fixtures.gen2_rom_text").text()
local Specials = require("src.script.gen2.Specials")
local TextBox = require("src.render.TextBox")

-- ---- the DST ladder confirms in text ---------------------------------------
-- PlayersHouse1F's MeetMomScript: writetext IsItDSTText / yesorno / special /
-- yesorno / iffalse back to the top.  The special prints "<time> DST, is that
-- OK?" (or the plain time for the clear arm) into the open box, so the second
-- yesorno has its own question; silent handlers left it hanging on IsItDST,
-- which read as Mom asking about daylight saving over and over.
local function dstVm(record)
  local shown = {}
  local answers, ai = {}, 0
  local vm = Vm.new({
    ["s:ladder"] = {
      { op = "writetext", text = "t:isdst" },
      { op = "yesorno" },
      { op = "iffalse", script = "s:wrong" },
      { op = "special", id = 0 }, -- InitialSetDSTFlag
      { op = "yesorno" },
      { op = "iffalse", script = "s:ladder" },
      { op = "end" },
    },
    ["s:wrong"] = {
      { op = "special", id = 1 }, -- InitialClearDSTFlag
      { op = "yesorno" },
      { op = "iffalse", script = "s:ladder" },
      { op = "end" },
    },
  }, { ["t:isdst"] = "Is it Daylight\nSaving Time now?" }, Events.new(), {
    specialOrder = { "InitialSetDSTFlag", "InitialClearDSTFlag" },
    specials = {
      save = function() return record end,
      world = { hour = function() return 10 end },
      data = function() return { text = ROM_TEXT } end,
    },
    showText = function(body, onDone)
      shown[#shown + 1] = body
      onDone()
    end,
    yesorno = function(onDone)
      ai = ai + 1
      onDone(answers[ai])
    end,
  })
  return vm, shown, answers
end

do
  local record = {}
  local vm, shown, answers = dstVm(record)
  answers[1], answers[2] = true, true -- yes it is DST, yes that is OK
  check(vm:start("s:ladder"), "the ladder runs")
  for _ = 1, 10 do vm:update() end
  check(not vm:running(), "and settles on a double yes")
  eq(#shown, 2, "two pages: the question and the confirmation")
  -- The minutes are the host clock's, so the pin is a pattern.
  check(shown[2]:match("^10:%d%d DST,\nis that OK%?{DONE}$") ~= nil,
    "the set arm prints the time and .DSTIsThatOKText")
  eq(record.rtc and record.rtc.dst, true, "and DST_F is set")
end

do
  local record = {}
  local vm, shown, answers = dstVm(record)
  -- no it is not DST, no that is not OK (loop), no again, yes that is OK
  answers[1], answers[2] = false, false
  answers[3], answers[4] = false, true
  check(vm:start("s:ladder"), "the ladder runs again")
  for _ = 1, 20 do vm:update() end
  check(not vm:running(), "a refused confirmation loops and then settles")
  eq(#shown, 4, "question, confirm, question again, confirm again")
  check(shown[2]:match("^10:%d%d,\nis that OK%?{DONE}$") ~= nil,
    "the clear arm prints the time and .TimeAskOkayText")
  eq(shown[3], shown[1], "the loop re-asks the cart's own question")
  eq(record.rtc and record.rtc.dst, false, "and DST_F ends clear")
end

-- ---- NameRival parks the officer -------------------------------------------
do
  local shown = {}
  local nameDone = nil
  local vm = Vm.new({
    ["s:cop"] = {
      { op = "opentext" },
      { op = "writetext", text = "t:one" },
      { op = "promptbutton" },
      { op = "special", id = 0 }, -- NameRival
      { op = "writetext", text = "t:two" },
      { op = "closetext" },
      { op = "end" },
    },
  }, {
    ["t:one"] = "His POKeMON was one of ours.",
    ["t:two"] = "OK! So {RIVAL}\nwas his name.",
  }, Events.new(), {
    specialOrder = { "NameRival" },
    nameRival = function(done) nameDone = done end,
    showText = function(body, onDone)
      shown[#shown + 1] = body
      onDone()
    end,
  })
  check(vm:start("s:cop"), "the officer's script starts")
  for _ = 1, 6 do vm:update() end
  check(vm:running(), "the script is PARKED on the naming screen")
  eq(#shown, 1, "the follow-up line has not printed under the keyboard")
  check(nameDone ~= nil, "the naming screen was opened")
  nameDone("KAMON")
  for _ = 1, 6 do vm:update() end
  check(not vm:running(), "the close of the keyboard resumes the officer")
  eq(shown[2], "OK! So {RIVAL}\nwas his name.",
    "and only then does his line print")
end

-- ---- World:nameRival stores the typed name, and empty keeps the default ----
do
  local World = require("src.world.gen2.World")
  local Screens = require("src.ui.Screens")
  local function rig()
    local pushed = {}
    local game = {
      data = { screens = {
        Gen2NamingScreen = function(_, opts)
          pushed.opts = opts
          return { opts = opts }
        end,
      } },
      save = { player = { name = "GOLD" }, rival = { name = "SILVER" } },
      stack = { push = function() end, pop = function() end },
    }
    return World.new(game), game, pushed
  end

  local world, game, pushed = rig()
  local got = nil
  world:nameRival(function(name) got = name end)
  check(pushed.opts ~= nil, "the keyboard screen went up")
  pushed.opts.onDone("KAMON")
  eq(game.save.rival.name, "KAMON", "the typed name lands in save.rival.name")
  eq(got, "KAMON", "and the script's resume sees it")

  Screens.invalidate()
  local world2, game2, pushed2 = rig()
  world2:nameRival(function() end)
  pushed2.opts.onDone("")
  eq(game2.save.rival.name, "SILVER",
    "an empty entry keeps InitName's version default")
  Screens.invalidate()

  -- The rig above hand-seeds "SILVER", which the real New Game never does:
  -- InitializeNPCNames seeds "???" and NameRival's InitName is what puts
  -- SILVER there.  Both flavours of blank -- empty and all spaces, which
  -- _InitString treats identically (home/string.asm:6-30) -- have to write
  -- the default themselves.
  for _, entry in ipairs({ "", "   " }) do
    local world3, game3, pushed3 = rig()
    game3.save.rival = { name = "???" }
    world3:nameRival(function() end)
    pushed3.opts.onDone(entry)
    eq(game3.save.rival.name, "SILVER",
      ("a blank entry (%q) over the \"???\" seed still lands on SILVER")
        :format(entry))
    Screens.invalidate()
  end
end

-- ---- <RIVAL> resolves off the Gold save ------------------------------------
do
  local gold = { data = {},
    save = { player = { name = "GOLD" }, rival = { name = "KAMON" } } }
  eq(TextBox.substitute(gold, "So {RIVAL} it is."), "So KAMON it is.",
    "a Gold save's rival name feeds the token")
  local red = { data = {}, save = { player = { name = "RED", rival = "GARY" } } }
  eq(TextBox.substitute(red, "{RIVAL}!"), "GARY!",
    "a Gen 1 save still reads player.rival")
  local bare = { data = {}, save = { player = {} } }
  eq(TextBox.substitute(bare, "{RIVAL}"), "BLUE",
    "only a save with neither falls back to BLUE")
  local goldBare = { data = {}, save = { generation = 2, player = {} } }
  eq(TextBox.substitute(goldBare, "{RIVAL}"), "???",
    "a Gold save with no rival record reads InitializeNPCNames' \"???\", not BLUE")
end

-- ---- the yes/no lookahead reaches the text hook -----------------------------
-- Script_yesorno is `call YesNoBox` with nothing between it and the page it
-- prompts over (engine/overworld/scripting.asm:366), and a `writetext` whose
-- next row is `yesorno` ends in `done` -- DoneText returns with no
-- PromptButton (home/text.asm:484).  So the VM hands the one-command lookahead
-- to the text hook as its THIRD argument, and World's hook has to take it:
-- declared with two parameters it was silently dropped, which cost a button
-- press the cart never asks for and re-printed the question under the prompt.
do
  local function stayFor(after)
    local seen
    local vm = Vm.new({
      ["s:ask"] = {
        { op = "writetext", text = "t:q" },
        { op = after },
        { op = "end" },
      },
    }, { ["t:q"] = "Would you like me\nto show you how?" }, Events.new(), {
      showText = function(_body, onDone, stay)
        seen = stay
        onDone()
      end,
      yesorno = function(onChoose) onChoose(true) end,
    })
    vm:start("s:ask")
    for _ = 1, 200 do
      if not vm:running() then break end
      vm:update()
    end
    return seen
  end
  eq(stayFor("yesorno"), true, "a writetext in front of yesorno holds its box")
  eq(stayFor("waitbutton"), false, "one in front of waitbutton does not")
end

-- ---- Mom's leaving speech keeps its page waits ------------------------------
-- _MomLeavingText1 is nine `para` pages on the cart; transcribed as one page
-- of stacked lines it typed itself out to the money prompt with no button in
-- between.  The handler is driven for real and the FIRST page it shows is
-- paginated with the shipped TextBox rules.
do
  local rec = { player = { money = 3000 }, mom = { savedMoney = 0 } }
  local texts, stays = {}, {}
  local vm = Vm.new({}, {}, Events.new(), {
    specials = {
      save = function() return rec end,
      data = function()
        return { text = require("tests.fixture_data.gen2_rom_text_s7_f1").text() }
      end,
      money = function() return 0 end,
      setMoney = function() end,
    },
  })
  vm.showTextFn = function() end
  vm.co = coroutine.create(function() Specials.HANDLERS.BankOfMom(vm) end)
  local ok, req = coroutine.resume(vm.co)
  while true do
    if not ok then error(req) end
    if req and req.kind == "text" then
      texts[#texts + 1] = req.text
      stays[#texts] = req.stay
    end
    if coroutine.status(vm.co) == "dead" then break end
    ok, req = coroutine.resume(vm.co, req and req.kind == "yesorno" or nil)
  end
  check(#texts >= 3, "the first-visit conversation ran")
  -- .InitializeBank is `PrintText MomLeavingText1 / call YesNoBox`
  -- (engine/events/mom.asm:50-53) with nothing between the two, and the text
  -- ends `done` -- so the box stays up and the prompt goes over it.  Vm's
  -- one-command lookahead cannot see this: the script row being run is the
  -- `special` itself, so the handler says it (Specials showRawHeld).
  check(stays[1] == true, "the page in front of Mom's prompt holds its box")
  check(not stays[2], "the page behind it, with no prompt after, does not")
  local pages = TextBox.paginate(texts[1], 18)
  eq(#pages, 9, "MomLeavingText1 is nine pages, one per cart `para`")
  for index, page in ipairs(pages) do
    check(#page <= 2,
      ("page %d holds at most the box's two lines"):format(index))
  end
  eq(pages[1][1], "Wow, that's a cute", "page one is the cart's opener")
  eq(pages[9][2], "save your money?",
    "and the money question is the last page, behind eight button waits")
end

-- ---- a stale string buffer stays out of complete texts ---------------------
-- CopyName1 never clears wStringBuffer2, so the berry picked outside is still
-- in it when Oak hands over the POKeDEX; only a {STRBUF} marker may read it.
do
  local shown = {}
  local vm = Vm.new({
    ["s:oak"] = {
      { op = "getitemname", item = 77 },
      { op = "writetext", text = "t:dex" },
      { op = "writetext", text = "t:buf" },
      { op = "end" },
    },
  }, {
    ["t:dex"] = "{PLAYER} received\nPOKeDEX!",
    ["t:buf"] = "{PLAYER} received\n{STRBUF}.",
  }, Events.new(), {
    showText = function(body, onDone)
      shown[#shown + 1] = body
      onDone()
    end,
    getItemName = function() return "PSNCUREBERRY" end,
  })
  check(vm:start("s:oak"), "Oak's handover runs")
  for _ = 1, 6 do vm:update() end
  eq(shown[1], "{PLAYER} received\nPOKeDEX!",
    "a complete text prints untouched, stale buffer and all")
  check(shown[1]:find("PSNCUREBERRY", 1, true) == nil,
    "the berry name cannot splice itself in")
  eq(shown[2], "{PLAYER} received\nPSNCUREBERRY.",
    "while a real {STRBUF} marker still reads the buffer")
end

-- ---- the catching tutorial gives the route its music back -------------------
-- CatchTutorial wraps an ordinary battle, and startBattle's onDone runs
-- RestartMapMusic (Script_reloadmapafterbattle) -- so when the DUDE's demo
-- ends, wMapMusic (Route 29's theme) comes back without a map change.  Real
-- Music module, real startBattle; only the two battle screens are registry
-- fakes and love.audio is a stub source factory.
do
  local World = require("src.world.gen2.World")
  local Screens = require("src.ui.Screens")
  local Music = require("src.core.Music")

  local function fakeSource()
    return {
      setLooping = function() end, setVolume = function() end,
      setFilter = function() end, play = function() end,
      stop = function() end, pause = function() end,
      isPlaying = function() return false end,
    }
  end
  love.audio = { newSource = function() return fakeSource() end }

  local battleDone = nil
  local game
  game = {
    data = {
      pokemon = { RATTATA = { name = "RATTATA", index = 21,
        baseStats = { hp = 30, attack = 56, defense = 35, speed = 72,
          specialAttack = 25, specialDefense = 35 },
        types = { "NORMAL", "NORMAL" },
        levelMoves = { { level = 1, move = "TACKLE" } } } },
      moves = { TACKLE = { name = "TACKLE", pp = 35, power = 40,
        type = "NORMAL", accuracy = 255 } },
      items = {},
      audio = { runtime = true,
        songs = { Music_Route29 = { file = "route29.ogg" },
          Music_JohtoWildBattle = { file = "wild.ogg" } },
        mapSongs = { ROUTE_29 = "Music_Route29" } },
      screens = {
        Gen2BattleTransition = function(_, opts)
          -- The wipe finishes instantly here; onDone pushes the battle.
          opts.onDone()
          return {}
        end,
        Gen2BattleState = function(_, opts)
          battleDone = opts.onDone
          return {}
        end,
      },
    },
    save = { player = { name = "GOLD" }, mom = { name = "MOM" },
      party = {}, inventory = {} },
    options = {},
    stack = { push = function() end, pop = function() end },
  }
  local world = World.new(game)
  game.world = world
  world.map = { id = "ROUTE_29", def = { environment = "ROUTE" } }
  world.daytime = "DAY"

  Music.playMap(game.data, "ROUTE_29")
  eq(Music.current(), "Music_Route29", "Route 29's theme is playing")

  local finished = false
  check(world:startCatchTutorial({ species = 21, level = 5 }, 3, function()
    finished = true
  end), "the DUDE's demo battle opens")
  eq(Music.current(), "Music_JohtoWildBattle",
    "the battle theme took the channels")
  check(battleDone ~= nil, "the battle screen is up")
  battleDone("win")
  check(finished, "the tutorial handed the script back")
  eq(Music.current(), "Music_Route29",
    "and Route 29's theme resumed in place, no map change needed")

  Music.stop()
  love.audio = nil
  Screens.invalidate()
end

-- ---- the Sprout Tower scene's sfx are the cart's ---------------------------
-- maps/SproutTower3F.asm really does play SFX_TACKLE + SFX_ELEVATOR twice
-- while the great pillar sways (that IS the elevator rumble), and Silver's
-- Escape Rope exit is SFX_WARP_TO.  Pin the extracted rows to the labels so a
-- repointed sfx table cannot quietly swap the cues.
do
  local cache = os.getenv("GOLD_CACHE")
  if not cache then
    local home = os.getenv("HOME") or ""
    cache = home .. "/Library/Application Support/LOVE/gold-dev/gold"
  end
  local scripts = (function()
    local chunk = loadfile(cache .. "/data/generated/scripts.lua")
    return chunk and chunk()
  end)()
  local audio = (function()
    local chunk = loadfile(cache .. "/data/generated/audio.lua")
    return chunk and chunk()
  end)()
  if not (scripts and audio and audio.sfxOrder) then
    check(true, "gold cache absent (SKIP Sprout Tower sfx pins)")
  else
    local rows = scripts["42:444b"]
    check(type(rows) == "table", "the rival scene extracted")
    local sounds = {}
    for _, row in ipairs(rows or {}) do
      if row.op == "playsound" then
        sounds[#sounds + 1] = audio.sfxOrder[(row.id or 0) + 1]
      end
    end
    eq(table.concat(sounds, ","),
      "Sfx_Tackle,Sfx_Elevator,Sfx_Tackle,Sfx_Elevator,Sfx_WarpTo",
      "tackle + elevator sway twice, then the Escape Rope warp")
  end
end

-- pokecrystal data/text/common_3.asm:1464, pokegold data/text/common_1.asm:1562
do
  local function pageIsPlayable(page, conts)
    if #page <= 2 then return true end
    for i = 3, #page do
      if not (conts and conts[i]) then return false end
    end
    return true
  end

  local function assertPlayable(label, text)
    local pages = TextBox.paginate(text, 18)
    for i, page in ipairs(pages) do
      check(pageIsPlayable(page, pages.contBefore and pages.contBefore[i]),
        ("%s: page %d never runs past the box unattended"):format(label, i))
    end
    return pages
  end

  local function drive(handler, specials, answers)
    local texts, stays = {}, {}
    local ai = 0
    if specials.data == nil then
      specials.data = function() return { text = ROM_TEXT } end
    end
    local vm = Vm.new({}, {}, Events.new(), { specials = specials })
    vm.showTextFn = function() end
    vm.co = coroutine.create(function() Specials.HANDLERS[handler](vm) end)
    local ok, req = coroutine.resume(vm.co)
    while true do
      if not ok then error(req) end
      local answer = nil
      if req and req.kind == "text" then
        texts[#texts + 1] = req.text
        stays[#texts] = req.stay
      elseif req and req.kind == "yesorno" then
        ai = ai + 1
        answer = answers[ai]
      end
      if coroutine.status(vm.co) == "dead" then break end
      ok, req = coroutine.resume(vm.co, answer)
    end
    return texts, stays
  end

  -- pokecrystal engine/events/move_deleter.asm:2-4
  local texts, stays = drive("MoveDeletion", {}, { true })
  eq(#texts, 3, "the deleter's intro, the mon prompt, then the decline")
  check(stays[1] == true, "the intro's last page holds under the YES/NO")
  local intro = assertPlayable("_DeleterIntroText", texts[1])
  eq(#intro, 3, "the intro is three pages, one per cart `para` (#2095)")
  for i, page in ipairs(intro) do
    check(#page <= 2,
      ("intro page %d holds at most the box's two lines"):format(i))
  end
  eq(intro[3][2], "POKéMON forget?", "the question is the last page")
  assertPlayable("_DeleterWhichMonText", texts[2])
  assertPlayable("_DeleterDeclinedText", texts[3])

  -- pokecrystal engine/events/name_rater.asm:3-5
  local rate = {
    save = function() return { player = { name = "GOLD", id = 1 } } end,
  }
  rate.selectPartyMon = function(_, done)
    done(1, { nickname = "SPOT", ot = "SOMEONE", otId = 2 })
  end
  texts, stays = drive("NameRater", rate, { true })
  eq(#texts, 3, "hello, the pick prompt, then the traded-mon verdict")
  check(stays[1] == true, "hello's last page holds under the YES/NO")
  local hello = assertPlayable("_NameRaterHelloText", texts[1])
  eq(#hello, 3, "hello is three pages, one per cart `para` (#2095)")
  local which = assertPlayable("_NameRaterWhichMonText", texts[2])
  eq(#which, 1, "the pick prompt is one page")
  eq(#which[1], 3, "of three lines")
  check(which.contBefore[1][3] == true,
    "whose third scrolls in on a button press, not on its own")
  assertPlayable("_NameRaterPerfectNameText", texts[3])

  rate.selectPartyMon = function(_, done) done(1, { nickname = "SPOT" }) end
  rate.renameMon = function(_, done) done("REX") end
  texts, stays = drive("NameRater", rate, { true, true })
  eq(#texts, 6, "hello, pick, offer, keyboard prompt, named, finished")
  check(stays[3] == true, "the rename offer holds under its YES/NO")
  assertPlayable("_NameRaterBetterNameText", texts[3])
  assertPlayable("_NameRaterWhatNameText", texts[4])
  local named = assertPlayable("_NameRaterNamedText", texts[5])
  check(named.contBefore[1][3] == true, "the new name waits for a press")
  assertPlayable("_NameRaterFinishedText", texts[6])

  rate.renameMon = function(_, done) done("SPOT") end
  texts = drive("NameRater", rate, { true, true })
  eq(#texts, 6, "a re-typed name still runs the full conversation")
  assertPlayable("_NameRaterSameNameText", texts[6])
end

S.finish()
