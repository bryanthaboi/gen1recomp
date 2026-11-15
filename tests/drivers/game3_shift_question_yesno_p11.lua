local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("game3_shift_question_yesno_p11",
  os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_shift_question_yesno_p11")

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Battle = require("src.core.game3.battle")
  local Bridge = require("src.core.game3.battle_bridge")
  local Ui = require("src.core.game3.battle.ui")
  local Party = require("src.core.game3.party")
  local Options = require("src.core.game3.options")
  local Message = require("src.ui.game3.message")
  local Anim = require("src.core.game3.battle.anim")
  local Chrome = require("src.ui.game3.chrome")
  local BattleText = require("src.core.game3.battle.battle_text")
  local Adapter = require("src.core.game3.battle.adapter")
  local session = Runtime.getSession()
  local version = session.version

  local C = require("src.core.game3.constants").of(version)
  local function species(name) return C:require("species", "SPECIES_" .. name) end
  local rse = version == "emerald" or version == "ruby" or version == "sapphire"
  local starter = species(rse and "TREECKO" or "CHARMANDER")
  local foe1 = species(rse and "ZIGZAGOON" or "PIDGEY")
  local foe2 = species(rse and "POOCHYENA" or "RATTATA")
  local nextName = rse and "POOCHYENA" or "RATTATA"
  if version == "emerald" then
    F.setVar("VAR_LITTLEROOT_INTRO_STATE", 7)
    F.setVar("VAR_LITTLEROOT_TOWN_STATE", 4)
    F.setVar("VAR_ROUTE101_STATE", 3)
    F.setFlag("FLAG_RESCUED_BIRCH", true)
  end
  local mapId = rse and (tostring(session.map):match("^(%u+)_") .. "_ROUTE101") or "FR_ROUTE_1"
  S.check(F.goTo(game, mapId, 10, 10, "down"), "p11 approach map loaded " .. version)

  session.party = {}
  Party.giveMon(session, starter, 40)
  Party.giveMon(session, starter, 20)
  Options.ensure(session).battleStyle = 0

  local function page()
    if not Message.isOpen() then return "" end
    return ((Message.currentPage() or ""):gsub("\n", " "))
  end
  local function atCommand()
    return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu"
  end

  local arrows = { first = 0, yesno = 0, auto = 0 }
  local counting
  local realArrow = Chrome.promptArrow
  Chrome.promptArrow = function(...)
    if counting then arrows[counting] = arrows[counting] + 1 end
    return realArrow(...)
  end

  local seen = {}
  local f, lastTap = 0, 0
  local function observe()
    if Battle._phase ~= "shift_prompt" then return end
    seen.prompted = true
    local choice = Ui.choiceActive() and true or false
    local p = page()
    if Message.isOpen() and Message.isWaiting() and p:find("about to use", 1, true) and not seen.firstShot then
      seen.firstPage = p
      seen.choiceOnFirst = choice
      counting = "first"
      U.wait(4)
      seen.firstShot = S.still(game, "p11_01_about_to_use_page.png")
      counting = nil
    end
    if choice and not seen.yesnoShot then
      U.wait(6)
      seen.choicePage = page()
      seen.msgOpen = Message.isOpen()
      counting = "yesno"
      seen.yesnoShot = S.still(game, "p11_02_question_beside_yesno.png")
      counting = nil
    end
  end
  local function pump(stop, limit)
    for _ = 1, limit or 6000 do
      f = f + 1
      observe()
      if stop() then return true end
      if Ui.choiceActive() then
        U.wait(8)
        U.tap(game, "b")
        U.wait(8)
      elseif Ui.dialogPending() and f - lastTap >= 14 then
        lastTap = f
        U.tap(game, "a")
      else
        U.wait(1)
      end
    end
    return stop()
  end

  local ok, err = Bridge.start(Runtime._mod, game,
    { trainerId = 326, party = { { species = foe1, level = 5 }, { species = foe2, level = 5 } } },
    { wild = false, trainerId = 326, fade = false })
  if not S.check(ok == true, "p11 trainer battle started " .. tostring(err or "")) then return S.finish() end
  if not S.check(pump(atCommand), "p11 reached the command menu vs foe 1") then return S.finish() end
  local st = Battle.getState()
  for _, m in ipairs(st.foeParty or {}) do
    m.moves = { 150, 0, 0, 0 }
    m.pp = { 40, 0, 0, 0 }
    m.hp = 1
  end
  st.enemy.mon.hp = 1
  local ep = Anim.present("enemy")
  if ep then ep.displayHp = 1 end
  local mon = st.player.mon
  mon.moves[1] = 129
  mon.pp = mon.pp or {}
  mon.pp[1] = 20
  Ui._pendingCommand = { kind = "move", move = 129, slot = 1, user = "player" }
  Ui._mode = "none"

  local replaced = pump(function() return atCommand() and st.enemy and st.enemy.partyIndex == 2 end)

  S.check(seen.prompted, "p11 SHIFT offered the switch after the faint")
  S.check(seen.firstPage ~= nil and seen.firstPage:find(nextName, 1, true) ~= nil,
    "p11 first page names " .. nextName .. ": " .. tostring(seen.firstPage))
  S.check(seen.firstPage ~= nil and not seen.choiceOnFirst, "p11 YES/NO stays shut on the about to use page")
  S.check(seen.yesnoShot ~= nil, "p11 YES/NO box opened")
  S.check(seen.msgOpen == true and (seen.choicePage or ""):find("change", 1, true) ~= nil
      and (seen.choicePage or ""):find("POK", 1, true) ~= nil,
    "p11 question text on screen while YES/NO is open: " .. tostring(seen.choicePage))
  S.check(replaced, "p11 NO sent the second foe out")
  -- pokefirered/src/text.c:864
  S.check(arrows.first > 0, "p11 down arrow on the about to use page (" .. arrows.first .. " arrow draws)")
  S.check(seen.yesnoShot ~= nil and arrows.yesno == 0,
    "p11 no down arrow beside YES/NO (" .. arrows.yesno .. " arrow draws)")

  if replaced then
    local text = BattleText.get("STRINGID_PKMNOBTAINEDXYOBTAINEDZ",
      Adapter.fill(st, { atk = "A", def = "B", buff1 = "LEFTOVERS", buff2 = "ORAN BERRY" }))
    st.link = true
    Ui._mode = "none"
    Ui.push(text)
    local onFirst, advanced, pages = false, false, nil
    for _ = 1, 600 do
      U.wait(1)
      Ui.pump()
      if Message.isOpen() and Message._stay then
        pages = #(Message._pages or {})
        if Message._page == 1 and pages > 1 and Message.isWaiting() then
          if not onFirst then
            onFirst = true
            counting = "auto"
            U.wait(4)
            S.still(game, "p11_03_link_autoscroll_page1.png")
            counting = nil
          end
        elseif onFirst and Message._page > 1 then
          advanced = true
          break
        end
      end
    end
    counting = nil
    st.link = nil
    S.check(onFirst, "p11 link battle text waits on page 1 of " .. tostring(pages))
    -- pokefirered/src/text.c:537
    S.check(advanced, "p11 link battle page 1 auto-scrolled with no input")
    -- pokefirered/src/text.c:553
    S.check(onFirst and arrows.auto == 0,
      "p11 no down arrow on the link auto-scroll page (" .. arrows.auto .. " arrow draws)")
  end
  Chrome.promptArrow = realArrow
  S.finish()
end
