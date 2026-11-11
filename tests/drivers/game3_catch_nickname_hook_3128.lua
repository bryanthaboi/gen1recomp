local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("game3_catch_nickname_hook_3128",
  os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_catch_nickname_hook_3128")

local MOD = {
  ["mods/catch_nickname_repro/manifest.json"] = [[{
    "id": "catch_nickname_repro",
    "name": "catch.nickname repro",
    "version": "1.0.0",
    "api": 2,
    "entry": "main.lua",
    "games": ["gen1", "gen2", "gen3"]
  }]],
  ["mods/catch_nickname_repro/main.lua"] = [[
return function(mod)
  mod.exports.calls = 0
  mod.hooks:wrap("catch.nickname", function(next, mon, ctx)
    mod.log:info("catch.nickname called")
    mod.exports.calls = mod.exports.calls + 1
    return "SPIKE"
  end)
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
  local Bag = require("src.core.game3.bag")
  local BagMenu = require("src.ui.game3.bag_menu")
  local Message = require("src.ui.game3.message")
  local Choice = require("src.ui.game3.choice")
  local Naming = require("src.ui.game3.naming")
  local RseDex = require("src.ui.game3.rse.pokedex")
  local Dex = require("src.core.game3.dex")
  local Storage = require("src.core.game3.storage")
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
  local mod = loader.mods.catch_nickname_repro
  local out = loader.exports.catch_nickname_repro
  if not S.check(mod and not mod.failed and out ~= nil, "3128 repro mod loaded " .. version) then
    for _, e in ipairs(loader.errors) do S.note("loader error: " .. tostring(e)) end
    return S.finish()
  end

  local C = require("src.core.game3.constants").of(version)
  local function species(name) return C:require("species", "SPECIES_" .. name) end
  local starter = species(version == "emerald" and "TREECKO" or "CHARMANDER")
  local target = species(version == "emerald" and "WURMPLE" or "MAGIKARP")
  local pcTarget = species(version == "emerald" and "POOCHYENA" or "PIDGEY")
  local master = C:require("items", "ITEM_MASTER_BALL")
  session.party, session.dex = {}, Dex.new()
  Party.giveMon(session, starter, 12)
  if version == "emerald" then
    F.setVar("VAR_LITTLEROOT_INTRO_STATE", 7)
    F.setVar("VAR_LITTLEROOT_TOWN_STATE", 4)
    F.setVar("VAR_ROUTE101_STATE", 3)
    F.setFlag("FLAG_RESCUED_BIRCH", true)
  end
  S.check(F.goTo(game, version == "emerald" and "EM_ROUTE101" or "FR_ROUTE_1", 10, 10, "down"),
    "3128 approach map loaded")

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
    if not S.check(BagMenu.currentPocket() == "POKE_BALLS", "3128 bag reached Poke Balls") then return false end
    U.tap(game, "a")
    U.wait(20)
    U.tap(game, "a")
    U.wait(20)
    return true
  end

  local function capture(sp, pc, tag)
    local partyBefore = #session.party
    local callsBefore = out.calls
    if not S.check(Bridge.startWild(Runtime._mod, game, { species = sp, level = 3 }, { fade = false }) == true,
        tag .. " wild encounter started") then return false end
    local thrown, dexSeen, promptSeen, namingSeen, pcMessageSeen, pcText = false, false, false, false, false, nil
    for frame = 1, 12000 do
      if not Battle.isActive() then break end
      local phase = Battle._phase
      if phase == "command" and Ui._mode == "menu" and not thrown then
        thrown = true
        if not throw() then return false end
      elseif phase == "pokedex_reg" then
        dexSeen = true
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
      elseif phase == "catch_pc_msg" and not pcMessageSeen then
        pcMessageSeen = true
        pcText = tostring(Ui._log[#Ui._log] or "")
        for _ = 1, 600 do
          if Message.isOpen() and not Message.isTyping() then break end
          U.wait(1)
        end
        U.wait(10)
        S.check(S.still(game, "3128_01_transferred_to_pc_as_spike.png"), tag .. " PC transfer page shot")
      elseif Message.isOpen() and not Message.isTyping() and frame % 18 == 0 then
        U.tap(game, "a")
      else U.wait(1) end
    end
    S.check(not Battle.isActive(), tag .. " capture completed")
    S.check(dexSeen, tag .. " new-dex page shown before the hook")
    S.check(not promptSeen, tag .. " no nickname question")
    S.check(not namingSeen, tag .. " no naming screen")
    S.check(out.calls == callsBefore + 1, tag .. " hook ran once")
    local mon
    if pc then
      S.check(pcMessageSeen, tag .. " PC transfer page reached")
      S.check(pcText and pcText:find("SPIKE", 1, true) ~= nil, tag .. " PC transfer page names SPIKE")
      local storage = Storage.ensure(session)
      for _, box in ipairs(storage.boxes or {}) do
        for _, candidate in pairs(box.mons or {}) do
          if tonumber(candidate.species or candidate.speciesId) == sp then mon = candidate end
        end
      end
    else
      mon = session.party[partyBefore + 1]
    end
    S.check(mon and tonumber(mon.species or mon.speciesId) == sp, tag .. " mon reached " .. (pc and "the PC" or "the party"))
    S.check(mon and mon.nickname == "SPIKE", tag .. " mon is named SPIKE")
    U.wait(40)
    return not Battle.isActive()
  end

  if not capture(target, false, "3128 " .. version .. " party") then return S.finish() end
  while #session.party < 6 do Party.giveMon(session, starter, 12) end
  capture(pcTarget, true, "3128 " .. version .. " pc")
  S.finish()
end
