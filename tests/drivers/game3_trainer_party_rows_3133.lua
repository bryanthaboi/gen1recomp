local U = require("tests.drivers.util")
local F = require("tests.drivers.em_fa_util")
local S = F.new("game3_trainer_party_rows_3133",
  os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_trainer_party_rows_3133")

local MOD = {
  ["mods/trainer_party_nick_repro/manifest.json"] = [[{
    "id": "trainer_party_nick_repro",
    "name": "trainer.party nickname repro",
    "version": "1.0.0",
    "api": 2,
    "entry": "main.lua",
    "games": ["gen1", "gen2", "gen3"]
  }]],
  ["mods/trainer_party_nick_repro/main.lua"] = [[
return function(mod)
  mod.exports.calls = 0
  mod.hooks:wrap("trainer.party", function(next, class, index, party)
    local rows = next(class, index, party)
    local out = {}
    for i, row in ipairs(rows) do
      local copy = setmetatable({}, getmetatable(row))
      for k, v in pairs(row) do copy[k] = v end
      copy.nickname = "ROWNICK" .. i
      if mod.exports.heldItem then copy.heldItem = mod.exports.heldItem end
      out[i] = copy
    end
    mod.exports.calls = mod.exports.calls + 1
    return out
  end)
end
]],
}

local TRAINER_VICTOR = 292
local MOVE_GROWL, MOVE_SWIFT, MOVE_SPLASH = 45, 129, 150

return function(game)
  if not F.boot(game, S) then return S.finish() end
  local Runtime = require("src.core.game3.runtime")
  local Battle = require("src.core.game3.battle")
  local Bridge = require("src.core.game3.battle_bridge")
  local State = require("src.core.game3.battle.state")
  local Ui = require("src.core.game3.battle.ui")
  local Anim = require("src.core.game3.battle.anim")
  local Party = require("src.core.game3.party")
  local Options = require("src.core.game3.options")
  local Trainers = require("src.core.game3.scripting.trainers")
  local Message = require("src.ui.game3.message")
  local Loader = require("src.mods.Loader")
  local Sdk = require("tests.modkit.sdk")
  local session = Runtime.getSession()
  local version = session.version
  local tag = "3133 " .. version

  local loader = Loader.new({ fs = Sdk.memfs(MOD), generation = 3, version = version, dev = true })
  loader.game = game
  local data = {}
  for key, value in pairs(game.data or {}) do data[key] = value end
  for key in pairs(require("src.mods.Builtins").namespaceRoots(3)) do data[key] = nil end
  loader:load(data)
  local mod = loader.mods.trainer_party_nick_repro
  local out = loader.exports.trainer_party_nick_repro
  if not S.check(mod and not mod.failed and out ~= nil, tag .. " repro mod loaded") then
    for _, e in ipairs(loader.errors) do S.note("loader error: " .. tostring(e)) end
    return S.finish()
  end

  local C = require("src.core.game3.constants").of(version)
  local function species(name) return C:require("species", "SPECIES_" .. name) end
  local oran = C:require("items", "ITEM_ORAN_BERRY")

  local trainerId
  if version == "emerald" then
    trainerId = TRAINER_VICTOR
    local cart = Trainers.foeFromId(trainerId)
    S.check(cart and cart.party and tonumber(cart.party[1].heldItem) == oran
      and tonumber(cart.party[2].heldItem) == oran, "3134 emerald cart rows carry ORAN BERRY")
  else
    for id = 1, 900 do
      local foe = Trainers.foeFromId(id)
      if foe and foe.party and #foe.party >= 2 and not foe.doubleBattle then trainerId = id break end
    end
    out.heldItem = oran
  end
  if not S.check(trainerId ~= nil, tag .. " trainer picked " .. tostring(trainerId)) then return S.finish() end

  session.party = {}
  Party.giveMon(session, species(version == "emerald" and "TREECKO" or "CHARMANDER"), 40)
  Party.giveMon(session, species(version == "emerald" and "TORCHIC" or "SQUIRTLE"), 30)
  Options.ensure(session).battleStyle = 0
  S.check(F.goTo(game, version == "emerald" and "EM_ROUTE101" or "FR_ROUTE_1", 10, 10, "down"),
    tag .. " approach map loaded")

  local ok, err = Bridge.start(Runtime._mod, game, Trainers.foeFromId(trainerId),
    { wild = false, trainerId = trainerId, fade = false })
  if not S.check(ok == true, tag .. " trainer battle started " .. tostring(err or "")) then return S.finish() end
  S.check(out.calls == 1, tag .. " trainer.party hook ran once")

  local f, lastTap, choiceKey = 0, 0, "a"
  local function at_command()
    return Battle.isActive() and Battle._phase == "command" and Ui._mode == "menu"
  end
  local function logged(needle)
    for _, t in ipairs(Ui.log()) do
      if tostring(t):find(needle, 1, true) then return tostring(t) end
    end
    return nil
  end
  local function shown(needle, limit)
    for _ = 1, limit or 600 do
      if Message.isOpen() and not Message.isTyping()
          and tostring(Message.currentPage()):find(needle, 1, true) then return true end
      U.wait(1)
    end
    return false
  end
  local function pump(stop, limit)
    for _ = 1, limit or 6000 do
      f = f + 1
      if stop() then return true end
      if not Battle.isActive() then return false end
      if Ui.choiceActive and Ui.choiceActive() then
        U.wait(8)
        U.tap(game, choiceKey)
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
  local function command(move)
    local mon = Battle.getState().player.mon
    mon.moves[1] = move
    mon.pp = mon.pp or {}
    mon.pp[1] = 20
    Ui._pendingCommand = { kind = "move", move = move, slot = 1, user = "player" }
    Ui._mode = "none"
  end
  local function setFoeHp(hp)
    local st = Battle.getState()
    st.enemy.mon.hp = hp
    local present = Anim.present("enemy")
    if present then present.displayHp = hp end
  end

  if not S.check(pump(at_command), tag .. " reached the command menu") then return S.finish() end
  local st = Battle.getState()
  for _, m in ipairs(st.foeParty or {}) do
    m.moves = { MOVE_SPLASH, 0, 0, 0 }
    m.pp = { 40, 0, 0, 0 }
  end
  st.enemy.mon.moves = { MOVE_SPLASH, 0, 0, 0 }
  st.enemy.mon.pp = { 40, 0, 0, 0 }

  S.check(st.enemy.mon.nickname == "ROWNICK1", tag .. " lead nickname is ROWNICK1 ("
    .. tostring(st.enemy.mon.nickname) .. ")")
  S.check(State.displayName(st.enemy) == "ROWNICK1", tag .. " battle names the lead ROWNICK1")
  S.check(logged("ROWNICK1") ~= nil, tag .. " send-out line says ROWNICK1")
  S.check(tonumber(st.enemy.mon.item) == oran, "3134 " .. version .. " lead holds ORAN BERRY ("
    .. tostring(st.enemy.mon.item) .. ")")
  U.wait(20)
  S.check(S.still(game, "3133_01_lead_hp_box_reads_rownick1.png"), tag .. " lead HP box shot")

  local maxHp = tonumber(st.enemy.mon.maxHp) or 0
  local low = math.max(1, math.floor(maxHp / 2) - 1)
  setFoeHp(low)
  command(MOVE_GROWL)
  local berryTried, berryShot = false, false
  S.check(pump(function()
    if not berryTried and logged("BERRY") then
      berryTried = true
      berryShot = shown("BERRY", 400) and S.still(game, "3134_02_foe_oran_berry_restored_health.png")
    end
    return berryTried and at_command()
  end), "3134 " .. version .. " foe ORAN BERRY activated")
  S.check(berryShot, "3134 " .. version .. " berry message shot")
  local berryLine = logged("BERRY")
  S.note("berry line: " .. tostring(berryLine):gsub("\n", " "))
  S.check(berryLine ~= nil and berryLine:find("ROWNICK1", 1, true) ~= nil,
    tag .. " berry line names ROWNICK1")
  S.check((tonumber(st.enemy.mon.hp) or 0) > low, "3134 " .. version .. " foe HP rose from " .. low
    .. " to " .. tostring(st.enemy.mon.hp))
  S.check((tonumber(st.enemy.mon.item) or 0) == 0, "3134 " .. version .. " berry was consumed")

  setFoeHp(1)
  command(MOVE_SWIFT)
  if S.check(pump(function() return Battle._phase == "shift_prompt" end),
      tag .. " shift prompt offered after the lead fainted") then
    local prompt = tostring(Ui.log()[#Ui.log()] or "")
    S.note("shift prompt: " .. prompt:gsub("\n", " "))
    S.check(prompt:find("ROWNICK2", 1, true) ~= nil, tag .. " about-to-use line says ROWNICK2")
    S.check(shown("ROWNICK2", 600) and S.still(game, "3133_03_about_to_use_rownick2.png"),
      tag .. " about-to-use shot")
  end

  choiceKey = "b"
  if S.check(pump(function() return at_command() and st.enemy.partyIndex == 2 end),
      tag .. " second Pokemon sent out") then
    S.check(State.displayName(st.enemy) == "ROWNICK2", tag .. " battle names the second ROWNICK2")
    S.check(tonumber(st.enemy.mon.item) == oran, "3134 " .. version .. " second Pokemon holds ORAN BERRY ("
      .. tostring(st.enemy.mon.item) .. ")")
    U.wait(20)
    S.check(S.still(game, "3133_04_second_hp_box_reads_rownick2.png"), tag .. " second HP box shot")
  end
  S.finish()
end
