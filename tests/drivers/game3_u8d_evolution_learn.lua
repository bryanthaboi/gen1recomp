local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp"

return function(game)
  local fails = 0
  local function check(cond, label)
    if cond then
      print("PASS " .. label)
    else
      fails = fails + 1
      print("FAIL " .. label)
    end
    return cond
  end
  local function finish()
    if fails == 0 then
      print("PASS u8d evolution scene learn move")
      love.event.quit(0)
    else
      print("FAIL u8d evolution scene learn move")
      love.event.quit(1)
    end
  end

  U.wait(30)
  local Schema = require("src.core.game3.save_schema_firered")
  local Party = require("src.core.game3.party")
  local Pokemon = require("src.core.game3.pokemon")
  local Runtime = require("src.core.game3.runtime")
  local Audio = require("src.core.game3.audio")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local SummaryMenu = require("src.ui.game3.summary_menu")
  local EvolutionScene = require("src.ui.game3.evolution_scene")

  local session = Schema.newGame({ name = "RED", rivalName = "BLUE", gender = 0 })
  session.party = {}
  Party.giveMon(session, 11, 10)
  Party.giveMon(session, 11, 10)
  session.party[1].moves = { 106, 33, 81, 1 }
  session.party[1].pp = { 30, 35, 40, 35 }
  session.party[1].maxPp = { 30, 35, 40, 35 }
  session.party[2].moves = { 106, 33 }
  session.party[2].pp = { 30, 35 }
  session.party[2].maxPp = { 30, 35 }
  session.map = "FR_ROUTE_1"
  session.x = 10
  session.y = 20
  session.flags = session.flags or {}
  game:_enterField(session, "new_game")
  U.wait(90)

  local live = Runtime.getSession() or session
  local learnset = Pokemon.movesLearnedAt(12, 10)
  local hasConf = false
  for _, m in ipairs(learnset) do if m == 93 then hasConf = true end end
  if not check(hasConf, "u8d BUTTERFREE learns CONFUSION at 10 in the cache") then return finish() end

  local CONF = Pokemon.moveName(93) or "CONFUSION"
  local pages = {}
  local lastPage
  local function page()
    return (Message.isOpen() and Message.currentPage and Message.currentPage()) or ""
  end
  local function track()
    local p = page()
    if p ~= lastPage then
      lastPage = p
      if p ~= "" then
        pages[#pages + 1] = p
        print("[u8d] page: " .. p:gsub("\n", " / "))
      end
    end
  end
  local function seen(needle)
    local n = 0
    for _, p in ipairs(pages) do
      if p:find(needle, 1, true) then n = n + 1 end
    end
    return n
  end
  local function advanceUntil(pred, limit)
    for f = 1, limit do
      U.wait(1)
      track()
      if pred() then return true end
      if f % 6 == 0 and not Choice.active and not Message._stay and not SummaryMenu.isOpen() then U.tap(game, "a") end
    end
    return false
  end
  local function yesNoWith(needle)
    return function()
      return Choice.active and Choice.kind == "yesno" and Message.isWaiting()
        and page():find(needle, 1, true) ~= nil
    end
  end

  local mon = live.party[1]
  local result
  EvolutionScene.start(mon, 12, {
    session = live, canStop = false, savedSong = Audio._mapSong,
    onDone = function(r) result = r end,
  })

  if not check(advanceUntil(yesNoWith("Delete a move to make"), 3000), "u8d TRYTOLEARNMOVE3 prompt with Yes/No") then
    U.shot(game, DIR .. "/u8d_98_no_try3.png")
    return finish()
  end
  check(seen("is trying to") >= 1 and seen("can't learn") >= 1, "u8d TRYTOLEARNMOVE1 and TRYTOLEARNMOVE2 shown first")
  local preName, postName = Pokemon.name(11) or "METAPOD", Pokemon.name(12) or "BUTTERFREE"
  check(seen("Congratulations! Your " .. preName .. "\nevolved into " .. postName .. "!") == 1
    and seen("Your " .. postName .. "\nevolved") == 0,
    "u8d congrats names the pre-evo " .. preName .. ", not " .. postName)
  check(seen("wants to learn") == 0 and seen("Should a move be deleted") == 0, "u8d no field party-menu wording")
  check(Choice.style == "battle" and Choice.left == 24 and Choice.top == 9, "u8d battle Yes/No window at 24,9")
  U.shot(game, DIR .. "/u8d_01_evo_try3_yesno.png")
  U.tap(game, "down")
  U.wait(2)
  U.tap(game, "a")

  if not check(advanceUntil(yesNoWith("Stop learning"), 600), "u8d NO opens Stop learning prompt") then
    U.shot(game, DIR .. "/u8d_98_no_stop.png")
    return finish()
  end
  U.shot(game, DIR .. "/u8d_02_evo_stop_learning.png")
  U.tap(game, "down")
  U.wait(2)
  U.tap(game, "a")

  if not check(advanceUntil(yesNoWith("Delete a move to make"), 900), "u8d NO to stop re-asks") then
    U.shot(game, DIR .. "/u8d_98_no_reask.png")
    return finish()
  end
  check(seen("is trying to") >= 2 and seen("can't learn") >= 2, "u8d re-ask reprints TRYTOLEARNMOVE1 and 2")
  U.tap(game, "a")

  if not check(advanceUntil(function()
    return SummaryMenu.isOpen() and SummaryMenu._mode == "select_move"
  end, 300), "u8d YES opens summary move select") then
    U.shot(game, DIR .. "/u8d_98_no_summary.png")
    return finish()
  end
  check(SummaryMenu._moveToLearn == 93, "u8d summary fifth move is CONFUSION")
  U.wait(20)
  U.shot(game, DIR .. "/u8d_03_evo_summary_select_move.png")
  U.tap(game, "a")

  local learnedShot = false
  local learnedLastSeen
  local ok = advanceUntil(function()
    local p = page()
    if p:find("learned", 1, true) and p:find(CONF, 1, true) then
      if not learnedShot and Message.isWaiting() then
        learnedShot = true
        U.shot(game, DIR .. "/u8d_04_evo_learned_confusion.png")
      end
      learnedLastSeen = U.frame()
    end
    return result ~= nil
  end, 1200)
  check(ok and result == "evolved", "u8d forget-path scene finished evolved")
  check(seen("Poof!") >= 1 and seen("forgot") >= 1 and seen("And") >= 1, "u8d 123POOF, PKMNFORGOTMOVE, ANDELLIPSIS shown")
  check(learnedShot, "u8d PKMNLEARNEDMOVE CONFUSION shown")
  check(mon.species == 12 and mon.moves[1] == 93, "u8d CONFUSION replaced HARDEN on BUTTERFREE")
  local gap = learnedLastSeen and (U.frame() - learnedLastSeen) or -1
  check(gap >= 0x40, "u8d scene held 0x40 frames after the learned text (" .. tostring(gap) .. ")")
  U.wait(30)

  pages = {}
  lastPage = nil
  result = nil
  local mon2 = live.party[2]
  EvolutionScene.start(mon2, 12, {
    session = live, canStop = false, savedSong = Audio._mapSong,
    onDone = function(r) result = r end,
  })
  learnedLastSeen = nil
  local learned2 = false
  ok = advanceUntil(function()
    local p = page()
    if p:find("learned", 1, true) and p:find(CONF, 1, true) then
      learned2 = true
      learnedLastSeen = U.frame()
    end
    return result ~= nil
  end, 3000)
  check(ok and result == "evolved" and learned2, "u8d free-slot scene learned CONFUSION and finished")
  check(mon2.moves[3] == 93 and seen("is trying to") == 0, "u8d free slot taught without the replace prompts")
  gap = learnedLastSeen and (U.frame() - learnedLastSeen) or -1
  check(gap >= 0x40, "u8d free-slot scene held 0x40 frames after the learned text (" .. tostring(gap) .. ")")
  U.wait(20)
  U.shot(game, DIR .. "/u8d_05_back_on_field.png")
  check(not EvolutionScene.isOpen(), "u8d evolution scene closed")

  finish()
end
