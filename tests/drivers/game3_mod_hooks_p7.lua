local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("game3_mod_hooks_p7", os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_mod_hooks_p7")

local MOD = {
  ["mods/p7_parity/manifest.json"] = [[{
    "id": "p7_parity",
    "name": "p7 parity",
    "version": "1.0.0",
    "api": 2,
    "entry": "main.lua",
    "games": ["gen1", "gen2", "gen3"]
  }]],
  ["mods/p7_parity/main.lua"] = [[
return function(mod)
  local e = mod.exports
  e.style, e.full, e.gifts = 0, 0, {}
  mod.hooks:wrap("battle.style", function(next, battle)
    e.style = e.style + 1
    e.styleArg = battle
    return e.styleAnswer or "set"
  end)
  mod.hooks:wrap("catch.party_full", function(next, ctx)
    e.full = e.full + 1
    e.claimed = ctx.mon
    return true
  end)
  mod.events:on("pokemon.before_give", function(gift)
    e.gifts[#e.gifts + 1] = { species = gift.species, speciesId = gift.speciesId, isEgg = gift.isEgg }
    if not gift.isEgg and e.giftTarget then
      gift.species, gift.nickname = e.giftTarget, "SPIKE"
    end
  end)
  mod.events:on("pokemon.caught", function(payload) e.destination = payload.destination end)
end
]],
}

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Battle = require("src.core.game3.battle")
  local Bridge = require("src.core.game3.battle_bridge")
  local Ui = require("src.core.game3.battle.ui")
  local Party = require("src.core.game3.party")
  local Options = require("src.core.game3.options")
  local Bag = require("src.core.game3.bag")
  local BagMenu = require("src.ui.game3.bag_menu")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Naming = require("src.ui.game3.naming")
  local RseDex = require("src.ui.game3.rse.pokedex")
  local Dex = require("src.core.game3.dex")
  local Storage = require("src.core.game3.storage")
  local Space = require("src.core.game3.scripting.space")
  local Anim = require("src.core.game3.battle.anim")
  local Loader = require("src.mods.Loader")
  local Sdk = require("tests.modkit.sdk")
  local session = Runtime.getSession()
  local version = session.version

  local loader = Loader.new({ fs = Sdk.memfs(MOD), generation = 3, version = version, dev = true })
  loader.game = game
  local data = {}
  for key, value in pairs(game.data or {}) do data[key] = value end
  for key in pairs(require("src.mods.Builtins").namespaceRoots(3)) do data[key] = nil end
  loader:load(data)
  local mod = loader.mods.p7_parity
  local out = loader.exports.p7_parity
  if not S.check(mod and not mod.failed and out ~= nil, "p7 mod loaded " .. version) then
    for _, e in ipairs(loader.errors) do S.note("loader error: " .. tostring(e)) end
    return S.finish()
  end

  local C = require("src.core.game3.constants").of(version)
  local function species(name) return C:require("species", "SPECIES_" .. name) end
  local starter = species(version == "emerald" and "TREECKO" or "CHARMANDER")
  local giftSp = species(version == "emerald" and "WURMPLE" or "MAGIKARP")
  local eggSp = species(version == "emerald" and "WYNAUT" or "TOGEPI")
  local pidgey = species(version == "emerald" and "ZIGZAGOON" or "PIDGEY")
  local pcTarget = species(version == "emerald" and "POOCHYENA" or "RATTATA")
  local master = C:require("items", "ITEM_MASTER_BALL")
  session.party, session.dex = {}, Dex.new()
  Party.giveMon(session, starter, 30)
  if version == "emerald" then
    F.setVar("VAR_LITTLEROOT_INTRO_STATE", 7)
    F.setVar("VAR_LITTLEROOT_TOWN_STATE", 4)
    F.setVar("VAR_ROUTE101_STATE", 3)
    F.setFlag("FLAG_RESCUED_BIRCH", true)
  end
  S.check(F.goTo(game, version == "emerald" and "EM_ROUTE101" or "FR_ROUTE_1", 10, 10, "down"),
    "p7 approach map loaded")

  out.giftTarget = pidgey
  Space.vm.scripts.P7_Gifts = {
    { op = "givemon", [1] = giftSp, [2] = 10, [3] = 0 },
    { op = "giveegg", [1] = eggSp },
    { op = "end" },
  }
  if S.check(Space.startScript("P7_Gifts"), "p7 gift script started") then
    for _ = 1, 600 do
      if not Space.vm:isRunning() then break end
      U.wait(1)
    end
    S.check(not Space.vm:isRunning(), "p7 gift script finished")
    local gift, egg = out.gifts[1], out.gifts[2]
    S.check(gift and gift.speciesId == giftSp and gift.isEgg == false,
      "p7 givemon raised pokemon.before_give with isEgg false")
    S.check(egg and egg.speciesId == eggSp and egg.isEgg == true,
      "p7 giveegg raised pokemon.before_give with isEgg true")
    local mon, eggMon = session.party[2], session.party[3]
    S.check(mon and tonumber(mon.species or mon.speciesId) == pidgey, "p7 givemon gave the rewritten species")
    S.check(mon and mon.nickname == "SPIKE", "p7 givemon named the gift SPIKE")
    S.check(eggMon and eggMon.isEgg and tonumber(eggMon.species or eggMon.speciesId) == eggSp,
      "p7 giveegg gave the egg")
  end

  local function throw()
    Bag.add(session.bag, master, 1)
    U.tap(game, "right")
    U.wait(12)
    U.tap(game, "a")
    U.wait(60)
    for _ = 1, 6 do
      if BagMenu.currentPocket() == "POKE_BALLS" then break end
      U.tap(game, "right")
      U.wait(32)
    end
    if not S.check(BagMenu.currentPocket() == "POKE_BALLS", "p7 bag reached Poke Balls") then return false end
    U.tap(game, "a")
    U.wait(20)
    U.tap(game, "a")
    U.wait(20)
    return true
  end

  session.party = {}
  for _ = 1, 6 do Party.giveMon(session, starter, 30) end
  local storedBefore = Storage.countTotalMons(Storage.ensure(session))
  if S.check(Bridge.startWild(Runtime._mod, game, { species = pcTarget, level = 3 }, { fade = false }) == true,
      "p7 wild encounter started") then
    local thrown, promptSeen, namingSeen, pcSeen = false, false, false, false
    for frame = 1, 12000 do
      if not Battle.isActive() then break end
      local phase = Battle._phase
      if phase == "command" and Ui._mode == "menu" and not thrown then
        thrown = true
        if not throw() then return S.finish() end
      elseif phase == "pokedex_reg" then
        local ds = RseDex.active()
        if version == "emerald" and ds and ds.fn == "caughtInput" then
          U.tap(game, "a")
        elseif version ~= "emerald" and frame % 18 == 0 then
          U.tap(game, "a")
        else U.wait(1) end
      elseif phase == "catch_dex_return" then
        U.wait(1)
      elseif phase == "catch_nickname_prompt" then
        promptSeen = true
        if Choice.isOpen() then U.tap(game, "b") end
        U.wait(1)
      elseif Naming.isOpen() then
        namingSeen = true
        U.tap(game, "b")
        U.wait(4)
      elseif phase == "catch_pc_msg" then
        pcSeen = true
        U.tap(game, "a")
        U.wait(4)
      elseif Message.isOpen() and not Message.isTyping() and frame % 18 == 0 then
        U.tap(game, "a")
      else U.wait(1) end
    end
    S.check(not Battle.isActive(), "p7 capture completed")
    S.check(out.full == 1, "p7 catch.party_full ran once on a 6/6 catch")
    S.check(out.claimed ~= nil and tonumber(out.claimed.species) == pcTarget, "p7 catch.party_full ctx.mon is the catch")
    S.check(#session.party == 6, "p7 claimed catch left the party at six")
    S.check(Storage.countTotalMons(Storage.ensure(session)) == storedBefore, "p7 claimed catch stored nothing in the PC")
    S.check(not pcSeen, "p7 claimed catch showed no PC transfer page")
    S.check(not promptSeen and not namingSeen, "p7 claimed catch asked no nickname")
    S.check(out.destination == "mod", "p7 pokemon.caught reported destination mod")
  end
  U.wait(40)

  local nextName = version == "emerald" and "POOCHYENA" or "RATTATA"
  local f, lastTap = 0, 0
  local watch
  local function atCommand()
    return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu"
  end
  local function observe()
    if not watch then return end
    if Battle._phase == "shift_prompt" then watch.prompted = true end
    local choice = Ui.choiceActive and Ui.choiceActive() and true or false
    if watch.answer == "shift" and Battle._phase == "shift_prompt" and choice and not watch.shot then
      U.wait(4)
      watch.choiceText = Message.isOpen() and (Message.currentPage() or ""):gsub("\n", " ") or nil
      watch.shotPage = watch.choiceText
      watch.shot = S.still(game, watch.shotName)
      watch.choiceAfterShot = Ui.choiceActive() and true or false
      return
    end
    if not (Message.isOpen() and Message.isWaiting()) then return end
    local page = (Message.currentPage() or ""):gsub("\n", " ")
    if page:find("change", 1, true) then watch.question = true end
    if not watch.firstPage and page:find(nextName, 1, true) then watch.firstPage = page end
    if Battle._phase == "shift_prompt" and not watch.aboutPage and page:find("about to use", 1, true) then
      watch.aboutPage, watch.aboutChoice = page, choice
    end
    if watch.shot then return end
    if watch.answer == "set" and watch.firstPage then
      U.wait(4)
      watch.shotPage, watch.shotChoice = page, choice
      watch.shot = S.still(game, watch.shotName)
    end
  end
  local function pump(stop, limit)
    for _ = 1, limit or 6000 do
      f = f + 1
      observe()
      if stop() then return true end
      if Ui.choiceActive and Ui.choiceActive() then
        U.wait(8)
        U.tap(game, "b")
        U.wait(8)
      elseif Ui.dialogPending and Ui.dialogPending() and f - lastTap >= 14 then
        lastTap = f
        U.tap(game, "a")
      else
        U.wait(1)
      end
    end
    return stop()
  end
  local function swift(st)
    local mon = st.player.mon
    mon.moves[1] = 129
    mon.pp = mon.pp or {}
    mon.pp[1] = 20
    Ui._pendingCommand = { kind = "move", move = 129, slot = 1, user = "player" }
    Ui._mode = "none"
  end

  local function trainerBattle(answer, shotName)
    out.styleAnswer = answer
    watch = { answer = answer, shotName = shotName, prompted = false, question = false, shot = false }
    session.party = {}
    Party.giveMon(session, starter, 40)
    Party.giveMon(session, starter, 20)
    Options.ensure(session).battleStyle = 0
    local ok, err = Bridge.start(Runtime._mod, game,
      { trainerId = 326, party = { { species = pidgey, level = 5 }, { species = pcTarget, level = 5 } } },
      { wild = false, trainerId = 326, fade = false })
    if not S.check(ok == true, "p7 " .. answer .. " trainer battle started " .. tostring(err or "")) then return watch end
    S.check(pump(atCommand), "p7 " .. answer .. " reached the command menu vs foe 1")
    local st = Battle.getState()
    watch.st = st
    if not st then return watch end
    for _, m in ipairs(st.foeParty or {}) do
      m.moves = { 150, 0, 0, 0 }
      m.pp = { 40, 0, 0, 0 }
      m.hp = 1
    end
    st.enemy.mon.hp = 1
    local ep = Anim.present("enemy")
    if ep then ep.displayHp = 1 end
    watch.styleBefore = out.style
    swift(st)
    watch.replaced = pump(function()
      return atCommand() and st.enemy and st.enemy.partyIndex == 2
    end)
    return watch
  end

  local set = trainerBattle("set", "p7_02_set_first_page_after_faint_has_no_question.png")
  S.check(set.replaced, "p7 the second foe came out")
  S.check(set.styleBefore and out.style > set.styleBefore, "p7 battle.style was consulted on the replacement")
  S.check(set.st ~= nil and out.styleArg == set.st, "p7 battle.style got the battle state")
  S.check(not set.prompted, "p7 set skipped the shift prompt under SHIFT")
  S.check(set.firstPage ~= nil and not set.firstPage:find("about to use", 1, true),
    "p7 set first page naming " .. nextName .. " after the faint is the send-out line: " .. tostring(set.firstPage))
  S.check(set.shot and not set.question and not set.shotChoice,
    "p7 set no change POKEMON question on screen after the faint")
  if not set.replaced then return S.finish() end
  if set.st.enemy and set.st.enemy.mon then set.st.enemy.mon.hp = 1 end
  swift(set.st)
  watch = nil
  if not S.check(pump(function() return not Battle.isActive() end, 9000), "p7 set battle won and closed") then
    return S.finish()
  end
  U.wait(40)

  local shift = trainerBattle("shift", "p7_01_shift_asks_will_you_change_after_faint.png")
  S.check(shift.prompted, "p7 shift control offered the switch")
  S.check(shift.aboutPage ~= nil and shift.aboutPage:find(nextName, 1, true) ~= nil and not shift.aboutChoice,
    "p7 shift control page 1 waits with the YES/NO box shut: " .. tostring(shift.aboutPage))
  S.check(shift.shot and shift.choiceAfterShot and shift.choiceText ~= nil
      and shift.choiceText:find("change", 1, true) ~= nil and shift.choiceText:find("POK", 1, true) ~= nil,
    "p7 shift control shows the change POKEMON question beside the YES/NO box after the faint: "
      .. tostring(shift.choiceText))
  S.check(shift.replaced, "p7 shift control sent the second foe out after NO")
  S.finish()
end
