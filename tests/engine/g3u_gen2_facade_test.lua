package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local F = require("tests.engine._g3u_fixture")
local L = require("tests.support.g3u_loopback")
local Table = require("src.battle.g3u.Table")
local BattleSession = require("src.online.union.BattleSession")
local Battle = require("src.battle.gen2.Battle")
local Strings = require("src.core.Strings")

local okLoad, Gen2Facade = pcall(require, "src.ui.g3u.Gen2Facade")
T.check(okLoad, "src.ui.g3u.Gen2Facade loads: " .. tostring(not okLoad and Gen2Facade or ""))
if not okLoad then T.finish("g3u gen2 facade") return end

local function readFile(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

local function uiMembers()
  local src = readFile("src/ui/gen2/BattleState.lua")
  src = src:gsub("%-%-%[%[.-%]%]", "")
  local lines = {}
  for raw in (src .. "\n"):gmatch("([^\n]*)\n") do
    local line = raw:gsub('"[^"]*"', '""'):gsub("'[^']*'", "''"):gsub("%-%-.*$", "")
    lines[#lines + 1] = line
  end
  src = table.concat(lines, "\n")
  local methods, fields, hooks = {}, {}, {}
  for name in src:gmatch("%f[%w_]battle:([%a_][%w_]*)%s*%(") do methods[name] = true end
  for name in src:gmatch("%f[%w_]battle%.([%a_][%w_]*)") do fields[name] = true end
  for name in src:gmatch("self%.link%.([%a_][%w_]*)") do hooks[name] = true end
  return methods, fields, hooks
end

local function dataFixture()
  local pokemon, moves = {}, {}
  for n = 1, 251 do
    pokemon[("MON%03d"):format(n)] = { dex = n, name = ("MON%03d"):format(n), types = { "NORMAL" } }
  end
  for id = 1, 251 do
    moves[("MOVE%03d"):format(id)] = { index = id, name = ("MOVE%03d"):format(id) }
  end
  pokemon.growthRates = {}
  return { pokemon = pokemon, moves = moves, text = require("tests.fixture_data.gen2_rom_text_s7_b").text() }
end

local game = { data = dataFixture(), save = { player = { name = "GOLD" } } }
local t2 = assert(Table.build(F.gen2(), 2))

local function pair(p0, p1, seed)
  local netA, netB = L.pair()
  local go = { seed = seed or 11, size = 6 }
  local gens = { [0] = 2, [1] = 3 }
  local names = { [0] = "GOLD", [1] = "MAY" }
  local me = BattleSession.new({ net = netA, seat = 0, go = go, gens = gens, data = F.gen2(), records = p0,
    names = names })
  local bot = BattleSession.new({ net = netB, seat = 1, go = go, gens = gens, records = p1, names = names })
  return me, bot
end

local function pumpBoth(me, bot, facade, n)
  local out = {}
  for _ = 1, n or 4 do
    me:update()
    bot:update()
    for _, e in ipairs(facade:translate(me:events())) do out[#out + 1] = e end
  end
  return out
end

local function find(list, pred)
  for _, e in ipairs(list) do if pred(e) then return e end end
  return nil
end

do
  local methods, fields, hooks = uiMembers()
  local nM, nF = 0, 0
  local listed = {}
  for _, k in ipairs(Gen2Facade.FIELDS) do listed[k] = true end
  local mine = { F.record(t2, 25, { 33, 85 }), F.record(t2, 1, { 33 }) }
  local foe = { F.record(t2, 4, { 33 }) }
  local me, bot = pair(mine, foe)
  local facade = Gen2Facade.new(game, me, { names = { me = "GOLD", foe = "MAY" } })
  pumpBoth(me, bot, facade)
  for name in pairs(methods) do
    nM = nM + 1
    T.check(type(facade[name]) == "function", "facade method battle:" .. name .. " exists")
  end
  for _, name in ipairs(Gen2Facade.METHODS) do
    T.check(type(facade[name]) == "function", "declared method " .. name .. " is a function")
  end
  for name in pairs(fields) do
    nF = nF + 1
    T.check(listed[name] == true, "UI field battle." .. name .. " is in Gen2Facade.FIELDS")
  end
  for _, name in ipairs(Gen2Facade.FIELDS) do
    T.check(facade[name] ~= nil or Gen2Facade.NILABLE[name], "field " .. name .. " is set")
  end
  T.check(nM >= 15 and nF >= 12, ("grep found the UI members (%d methods, %d fields)"):format(nM, nF))
  T.check(type(facade.player) == "table" and type(facade.enemy) == "table", "player and enemy are views")
  T.check(type(facade.random) == "function", "random is a function")
  T.check(type(facade.trainer) == "table" and facade.trainer.name == "MAY", "trainer carries the foe name")
  local h = facade:hooks()
  for name in pairs(hooks) do
    if name ~= "forcedPrompt" then
      T.check(type(h[name]) == "function", "link hook " .. name .. " exists")
    end
  end
end

do
  local mine = { F.record(t2, 25, { 33, 85 }, 50, { nickname = "SPARKY" }), F.record(t2, 1, { 33 }) }
  local foe = { F.record(t2, 4, { 33 }), F.record(t2, 7, { 33 }) }
  local me, bot = pair(mine, foe)
  local facade = Gen2Facade.new(game, me, { names = { me = "GOLD", foe = "MAY" } })
  pumpBoth(me, bot, facade)
  T.check(facade.ready, "ready builds the views")
  T.eq(#facade.party, 2, "my party has both mons")
  T.eq(#facade.enemyParty, 2, "foe party has both mons")
  T.eq(facade.player.species, "MON025", "species key from the active cache by national dex")
  T.eq(facade.player.nickname, "SPARKY", "nickname from the record")
  T.eq(facade.enemy.nickname, "MON004", "no nickname: species name from the active cache")
  T.eq(facade.player.moves[1].id, "MOVE033", "move ids map to the active cache keys")
  T.eq(facade.awaiting, "move", "the first prompt arms the move menu")
  T.check(facade:hasUsableMoves(facade.player), "usable moves while choosing")
  local legalSlots = {}
  for _, a in ipairs(me:legal()) do if a.kind == "move" then legalSlots[a.slot] = true end end
  for i, mv in ipairs(facade.player.moves) do
    T.eq(facade:moveDisabled(facade.player, mv.id), not legalSlots[i], "move " .. i .. " disabled iff not legal")
  end
  T.check(facade:moveDisabled(facade.player, "MOVE099"), "a move the mon does not have is refused")
  T.eq(facade:switchLocked(), false, "switching is open with a bench")
  T.eq(facade:lockedInMove(facade.player), nil, "nothing is locked in")

  local refused
  local s = { phase = "moves", queue = {} }
  function s.refuseMenu(_, text) refused = text end
  function s.refuseSwitch() refused = "switch" end
  local h = facade:hooks()
  h.menuChoice(s, "item")
  T.check(refused ~= nil, "items are refused")
  refused = nil
  T.eq(h.menuChoice(s, "run"), true, "first RUN only warns")
  T.eq(me.phase, "choose", "first RUN does not forfeit")
  T.eq(h.menuChoice(s, "fight"), false, "FIGHT falls through to the native menu")
  h.submit(s, { kind = "move", move = facade.player.moves[1].id })
  T.eq(me.phase, "wait", "the move menu submits the legal slot")
  T.eq(s.phase, "link-wait", "the screen waits for the peer")
  local bstep = L.bot(bot, { seed = 3 })
  local out = {}
  for _ = 1, 6 do
    bstep()
    me:update()
    for _, e in ipairs(facade:translate(me:events())) do out[#out + 1] = e end
  end
  local mv = find(out, function(e) return e.kind == "move" and e.side == "player" end)
  T.check(mv and mv.move == "MOVE033" and type(mv.text) == "string" and mv.text:find("SPARKY"),
    "USEDMOVE + move merge into one Gen 2 move event with text")
  T.check(find(out, function(e) return e.kind == "damage" and e.side == "enemy" and e.hp ~= nil end) ~= nil,
    "a hit becomes a damage event with the new hp")
  T.eq(facade.awaiting, "move", "the next prompt arms the menu again")
end

do
  local mine = { F.record(t2, 25, { 33 }, 5), F.record(t2, 1, { 33 }) }
  local foe = { F.record(t2, 143, { 33 }, 100) }
  local me, bot = pair(mine, foe, 5)
  local facade = Gen2Facade.new(game, me, {})
  pumpBoth(me, bot, facade)
  local s = { phase = "moves", queue = {} }
  local refused
  function s.refuseMenu(_, text) refused = text end
  function s.refuseSwitch() refused = "switch" end
  local h = facade:hooks()
  h.submit(s, { kind = "move", move = facade.player.moves[1].id })
  local bstep = L.bot(bot, { seed = 1 })
  local out = {}
  for _ = 1, 6 do
    bstep()
    me:update()
    for _, e in ipairs(facade:translate(me:events())) do out[#out + 1] = e end
  end
  local fe = find(out, function(e) return e.kind == "faint" and e.side == "player" end)
  T.check(fe and fe.text:find("fainted"), "faint carries its line")
  local dupes = 0
  for _, e in ipairs(out) do
    if e.kind == "message" and e.text and e.text:find("fainted") then dupes = dupes + 1 end
  end
  T.eq(dupes, 0, "the engine faint line is not repeated")
  T.check(find(out, function(e) return e.kind == "choose-switch" end) ~= nil, "my replacement prompt opens the party")
  T.eq(facade.awaiting, "replace", "awaiting a replacement")
  refused = nil
  h.forcedSwitch(s, 1)
  T.eq(refused, "switch", "the fainted lead cannot be sent back")
  T.eq(h.forcedSwitch(s, 2), true, "a legal replacement is accepted")
  out = pumpBoth(me, bot, facade, 4)
  local send = find(out, function(e) return e.kind == "send" and e.side == "player" end)
  T.check(send and send.mon == facade.party[2] and send.text:find("Go!"), "the replacement sends out with Go!")
  T.check(facade.player == facade.party[2], "battle.player follows the replacement")
end

do
  local function fakeBs(legal)
    return { seat = 0, names = { [0] = "GOLD", [1] = "MAY" }, seed = 1,
      legal = function() return legal end, choose = function() return true end }
  end
  local recs = { F.record(t2, 25, { 33, 85, 1 }), F.record(t2, 1, { 33 }) }
  local bs = fakeBs({ { kind = "move", slot = 2, locked = true }, { kind = "forfeit" } })
  local facade = Gen2Facade.new(game, bs, {})
  facade:translate({ { kind = "ready", parties = { [0] = recs, [1] = { recs[2] } } },
    { kind = "sendout", side = 0, index = 1, reason = "start" }, { kind = "sendout", side = 1, index = 1, reason = "start" },
    { kind = "prompt", what = "move", turn = 1 } })
  T.eq(facade:lockedInMove(facade.player), "MOVE085", "a locked action names its move for auto-submit")
  local act = facade:actionFor({ kind = "move", move = "MOVE033" })
  T.check(act and act.slot == 2, "any submit maps to the locked action")
  T.eq(facade:switchLocked(), true, "no switch actions means switching is locked")

  bs = fakeBs({ { kind = "move", slot = 0 }, { kind = "forfeit" } })
  facade = Gen2Facade.new(game, bs, {})
  facade:translate({ { kind = "ready", parties = { [0] = recs, [1] = { recs[2] } } },
    { kind = "prompt", what = "move", turn = 1 } })
  T.eq(facade:hasUsableMoves(facade.player), false, "only Struggle left")
  act = facade:actionFor({ kind = "move", move = Battle.STRUGGLE })
  T.check(act and act.slot == 0, "STRUGGLE submits slot 0")

  local ev = facade:translate({
    { kind = "msg", id = "STRINGID_USEDMOVE", fill = { atk = { side = 1, index = 1 }, currentMove = { move = 33 } } },
    { kind = "msg", id = "STRINGID_ATTACKMISSED", fill = { atk = { side = 1, index = 1 } } },
    { kind = "hp", side = 0, from = facade.player.hp, to = facade.player.hp - 5, max = facade.player.maxHp },
    { kind = "hp", side = 0, from = facade.player.hp - 5, to = facade.player.hp - 2, max = facade.player.maxHp },
    { kind = "status", side = 0, status = "PSN" },
    { kind = "anim", anim = "status", name = "POISON", user = 0, target = 0 },
    { kind = "status", side = 1, status = "NONE" },
    { kind = "weather", weather = "RAINY", turns = 5 },
    { kind = "msg", id = "STRINGID_STARTEDTORAIN", fill = {} },
    { kind = "msg", id = "STRINGID_DEFENDERSSTATFELL", fill = { def = { side = 1, index = 1 }, stat = "spAtk", delta = -2 } },
    { kind = "msg", id = "STRINGID_NOT_A_REAL_ID", fill = { atk = { side = 7 } } },
    { kind = "msg", id = "STRINGID_PKMNHURTBY", fill = { atk = "nonsense" } },
    { kind = "withdraw", side = 1, index = 1, reason = "switch" },
    { kind = "sendout", side = 1, index = 1, reason = "switch" },
    { kind = "faint", side = 1 },
    { kind = "msg", id = "STRINGID_TARGETFAINTED", fill = { def = { side = 1, index = 1 } } },
    { kind = "need_replacement", side = 1, reason = "faint" },
    { kind = "end", result = { winner = 0, why = "faint" } },
  })
  local miss = ev[1]
  T.check(miss.kind == "move" and miss.missed and miss.text:find("MAY") == nil and miss.text:find("MON001"),
    "USEDMOVE with no move anim is a missed move line")
  T.check(ev[2].kind == "message" and ev[2].text:find("missed"), "ATTACKMISSED text")
  T.check(ev[3].kind == "damage" and ev[3].anim == false and ev[3].amount == 5, "non-hit damage has no shake")
  T.check(ev[4].kind == "heal" and ev[4].amount == 3, "hp up is a heal")
  T.check(ev[5].kind == "status" and ev[5].status == "poison" and ev[5].side == "player", "PSN -> poison")
  T.check(ev[6].kind == "damage" and ev[6].anim == "ANIM_PSN" and ev[6].amount == 0 and ev[6].animSide == "player",
    "status anim -> Gen 2 ANIM_PSN on the afflicted side")
  T.check(ev[7].kind == "status" and ev[7].status == false, "NONE clears the status")
  T.eq(facade.weather, "rain", "weather event sets the Gen 2 weather")
  T.eq(ev[8].text, "A downpour\nstarted!", "weather line is the Gen 2 game's own")
  T.check(ev[9].text:find("SPCL.ATK") and ev[9].text:find("sharply fell"), "stat text uses Gen 2 stat names")
  T.check(ev[10].kind == "message" and ev[10].text:find("?", 1, true), "unknown ids drop, broken fills print ?")
  T.check(ev[11].kind == "message" and ev[11].text:find("withdrew"), "enemy withdraw line")
  T.check(ev[12].kind == "send" and ev[12].side == "enemy" and ev[12].text:find("sent out"), "enemy sendout line")
  T.check(ev[13].kind == "faint" and ev[13].side == "enemy", "faint event")
  T.check(ev[14].kind == "message" and ev[14].text:find("defeated"), "win line")
  T.check(ev[15].kind == "trainer-return", "the trainer slides back in on a win")
  T.eq(#ev, 15, "no extra events")
  T.check(facade.over and facade.outcome == "win", "end sets over and outcome")
  T.eq(ev[2].text, "Enemy MON001's\nattack missed!", "ATTACKMISSED is AttackMissedText")
  T.eq(ev[11].text, "MAY\nwithdrew\vMON001!", "enemy withdraw is EnemyWithdrewText")
  T.eq(ev[13].text, "Enemy MON001\nfainted!", "enemy faint is BattleText_EnemyMonFainted")
  T.eq(ev[14].text, "MAY\nwas defeated!", "win line is BattleText_EnemyWasDefeated")

  local full = { atk = { side = 1, index = 1 }, def = { side = 0, index = 1 }, eff = { side = 0, index = 1 },
    scrActive = { side = 0, index = 1 }, buff1 = 33, buff2 = 4, currentMove = 33, stat = "atk", delta = 1 }
  local PORT_ONLY = { STRINGID_PKMNALREADYHASBURN = true, STRINGID_PKMNFATIGUECONFUSION = true }
  for id, fn in pairs(Gen2Facade.MSG) do
    local fill = full
    if id == "STRINGID_STATSWONTINCREASE" or id == "STRINGID_STATSWONTDECREASE" then
      fill = setmetatable({ buff1 = "atk" }, { __index = full })
    end
    local ok, text = pcall(fn, facade, fill)
    T.check(ok and type(text) == "string" and text ~= "", id .. " renders from the cache: " .. tostring(text))
    T.check(not (ok and tostring(text):find("{%u+}")), id .. " fills every slot")
    if not PORT_ONLY[id] and id ~= "STRINGID_PKMNSXWOREOFF" then
      local dataless = setmetatable({ data = {} }, { __index = facade })
      T.check(not pcall(fn, dataless, fill), id .. " reads the cache")
    end
  end

  facade = Gen2Facade.new(game, bs, {})
  facade:translate({ { kind = "ready", parties = { [0] = recs, [1] = { recs[2] } } } })
  local d = facade:translate({ { kind = "over", outcome = "draw", why = "desync", detail = 3 } })
  T.check(d[1] and d[1].text == Strings(Gen2Facade.TEXT.desync), "desync shows an original line")
  T.check(facade.over and facade.outcome == "draw", "desync ends as a draw")
  facade = Gen2Facade.new(game, bs, { names = { foe = "MAY" } })
  facade:translate({ { kind = "ready", parties = { [0] = recs, [1] = { recs[2] } } } })
  d = facade:translate({ { kind = "over", outcome = "draw", why = "disconnect" } })
  T.check(d[1] and d[1].text:find("MAY"), "disconnect names the peer")
  local b = Gen2Facade.banner()
  T.check(b[1].text == "UNION RULES!" and b[2].text:find("GEN 3 battle rules") and b[2].text:find("held items"),
    "union rules banner wording")
end

T.finish("g3u gen2 facade")
