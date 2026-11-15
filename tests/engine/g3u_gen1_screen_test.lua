package.path = "./?.lua;./?/init.lua;" .. package.path
love = love or require("tests.love_stub")
local T = require("tests.harness")
local F = require("tests.engine._g3u_fixture")
local Table = require("src.battle.g3u.Table")
local BattleSession = require("src.online.union.BattleSession")
local L = require("tests.support.g3u_loopback")
local G = require("src.ui.g3u.Gen1Screen")

local data = { pokemon = {}, moves = {}, text = setmetatable({
  _CriticalHitText = "FIX CRIT{PROMPT}",
  _EnemyMonFaintedText = "FIX FOE {RAM:wEnemyMonNick}\nDOWN{PROMPT}",
  _TrainerDefeatedText = "{PLAYER} FIX BEAT\n{RAM:wTrainerName}!{PROMPT}",
  _FlewUpHighText = "\nFIX FLEW{PROMPT}",
}, { __index = dofile("tests/fixture_data/text.lua") }) }
for n = 1, 151 do data.pokemon["MON" .. n] = { dex = n, name = "MON" .. n } end
for i = 1, 165 do
  data.moves["MV" .. i] = { index = i, name = "MOVE" .. i, effect = (i == 7) and "BURN_SIDE_EFFECT1" or "NO_ADDITIONAL_EFFECT" }
end

local t1 = assert(Table.build(F.gen1()))
local p0 = { F.record(t1, 25, { 33, 7, 45 }), F.record(t1, 6, { 33 }, 50, { nickname = "BLAZE" }) }
local p1 = { F.record(t1, 95, { 33, 89 }), F.record(t1, 143, { 33 }) }

local ctx = assert(G.newCtx(data, 0, { [0] = p0, [1] = p1 }, { me = "RED", foe = "GARY" }))
T.eq(ctx.mons[0][1].species, "MON25", "national 25 maps to the cache species key")
T.eq(ctx.mons[0][1].moves[2].id, "MV7", "move id 7 maps to the cache move key")
T.eq(ctx.mons[0][1].stats.special, p0[1].spAtk, "Special shows the record's Sp. Atk")
T.eq(ctx.mons[0][2].nickname, "BLAZE", "a real nickname is kept")
T.eq(ctx.mons[0][1].nickname, nil, "a species-name nickname falls back to the cache name")

local function only(rows, op)
  T.eq(#rows, 1, "one row for " .. op)
  return rows[1] or {}
end

local r = only(G.rowsFor({ kind = "msg", id = "STRINGID_USEDMOVE",
  fill = { atk = { side = 0, index = 1 }, currentMove = { move = 33 } } }, ctx), "my used move")
T.eq(r.op, "say", "used move is a message")
T.eq(r.text, "MON25\nused MOVE33!", "my used move names my mon and the cache move")
T.eq(r.auto, true, "used move does not wait for a button")
r = only(G.rowsFor({ kind = "msg", id = "STRINGID_USEDMOVE",
  fill = { atk = { side = 1, index = 1 }, currentMove = { move = 89 } } }, ctx), "foe used move")
T.eq(r.text, "Enemy MON95\nused MOVE89!", "the foe's mon gets the Enemy prefix")
r = only(G.rowsFor({ kind = "msg", id = "STRINGID_CRITICALHIT", fill = {} }, ctx), "crit")
T.eq(r.text, "FIX CRIT{PROMPT}", "a msg with a cart equivalent reads the cache label")
r = only(G.rowsFor({ kind = "msg", id = "STRINGID_TARGETFAINTED", fill = { def = { side = 1, index = 1 } } }, ctx), "foe faint text")
T.eq(r.text, "FIX FOE MON95\nDOWN{PROMPT}", "foe faint text fills the cache label")
r = only(G.rowsFor({ kind = "msg", id = "STRINGID_PKMNFLEWHIGH", fill = { atk = { side = 0, index = 1 } } }, ctx), "fly")
T.eq(r.text, "MON25\nFIX FLEW{PROMPT}", "charge text is the user plus the cache fragment")
r = only(G.rowsFor({ kind = "msg", id = "STRINGID_DEFENDERSSTATFELL",
  fill = { def = { side = 1, index = 1 }, stat = "spDef", delta = -2 } }, ctx), "stat fell")
T.eq(r.text, "Enemy MON95's\nSPECIAL\ngreatly fell!{PROMPT}", "Sp. Def drop reads as SPECIAL in Gen 1 register")
local rows = G.rowsFor({ kind = "msg", id = "STRINGID_PKMNFASTASLEEP", fill = { atk = { side = 0, index = 1 } } }, ctx)
T.eq(#rows, 2, "fast asleep gives text and the sleep anim")
T.eq(rows[1].op, "anim", "my sleeping mon's anim plays before the text")
T.eq(rows[1].name, "SLP_PLAYER_ANIM", "player side sleep anim")
rows = G.rowsFor({ kind = "msg", id = "STRINGID_PKMNISCONFUSED", fill = { atk = { side = 1, index = 1 } } }, ctx)
T.eq(rows[1].op, "say", "foe confusion text first")
T.eq(rows[2].name, "CONF_ANIM", "foe confusion anim after")
T.eq(#G.rowsFor({ kind = "msg", id = "STRINGID_SOMETHINGNEW", fill = {} }, ctx), 0, "unknown ids are skipped")
T.eq(#G.rowsFor({ kind = "msg", id = "STRINGID_ATTACKMISSED", fill = {} }, ctx), 0, "missing battler skips the line")
T.eq(#G.rowsFor({ kind = "msg", id = "STRINGID_PKMNSXWOREOFF", fill = { atk = "enemy" } }, ctx), 0,
  "Gen 3 only lines are skipped")
T.eq(#G.rowsFor({ kind = "msg", id = "STRINGID_ATTACKMISSED", fill = { atk = "enemy" } }, ctx), 1,
  "a string battler ref resolves by side")

local mv = only(G.rowsFor({ kind = "move", moveId = 7, user = 0, target = 1, turn = 0 }, ctx), "move")
T.eq(mv.op, "move", "move event is an anim row")
T.eq(mv.move, "MV7", "anim keyed by the cache move key")
local rest = { { kind = "msg", id = "STRINGID_SUPEREFFECTIVE", fill = {} } }
local hp = only(G.rowsFor({ kind = "hp", side = 1, from = 100, to = 60, max = 100, hit = true }, ctx, rest, 1), "hp")
T.eq(hp.op, "hp", "hp event is an hp row")
T.eq(hp.to, 60, "hp row carries the event value")
T.eq(hp.index, 1, "hp row targets the active foe mon")
T.eq(mv.hit and mv.hit.animType, 5, "my added-effect hit shakes lightly")
T.eq(mv.hit and mv.hit.sfx.sound, "Super_Effective", "effectiveness picks the hit sound")
local mv2 = only(G.rowsFor({ kind = "move", moveId = 33, user = 1, target = 0 }, ctx), "foe move")
G.rowsFor({ kind = "hp", side = 0, from = 100, to = 90, max = 100, hit = true }, ctx, {}, 1)
T.eq(mv2.hit and mv2.hit.animType, 1, "a plain foe hit shakes the screen")
T.eq(mv2.hit and mv2.hit.sfx.sound, "Damage", "neutral hit sound")
local heal = G.rowsFor({ kind = "hp", side = 0, from = 50, to = 90, max = 100 }, ctx)
T.eq(heal[1].to, 90, "a heal is an hp row too")

r = only(G.rowsFor({ kind = "status", side = 1, status = "TOX" }, ctx), "status")
T.eq(r.status, "PSN", "toxic shows as PSN in Gen 1")
r = only(G.rowsFor({ kind = "status", side = 1, status = "NONE" }, ctx), "status clear")
T.eq(r.status, nil, "NONE clears the status")
r = only(G.rowsFor({ kind = "stage", side = 0, stat = "attack", delta = 2 }, ctx), "stage")
T.eq(r.op, "stage", "stage event kept as a display-only row")
r = only(G.rowsFor({ kind = "faint", side = 1 }, ctx), "faint")
T.eq(r.op, "faint", "faint event is a faint row")
T.eq(#G.rowsFor({ kind = "withdraw", side = 1, index = 1, reason = "switch" }, ctx), 0, "a fainted mon withdraws silently")
r = only(G.rowsFor({ kind = "sendout", side = 1, index = 2, reason = "switch" }, ctx), "sendout")
T.eq(r.op, "sendout", "replacement is a sendout row")
T.eq(ctx.active[1], 2, "sendout moves the active index")
r = only(G.rowsFor({ kind = "withdraw", side = 0, index = 1, reason = "switch" }, ctx), "withdraw")
T.eq(r.op, "withdraw", "a voluntary switch withdraws with text")
T.eq(#G.rowsFor({ kind = "sendout", side = 0, index = 1, reason = "start" }, ctx), 0, "start send-out is the intro's")
for _, k in ipairs({ "weather", "anim", "need_replacement", "end", "ready" }) do
  T.eq(#G.rowsFor({ kind = k, side = 0, result = {} }, ctx), 0, k .. " needs no row")
end
T.eq(#G.rowsFor({ kind = "sendout", side = 0, index = 9, reason = "switch" }, ctx), 0, "bad index does not crash")
T.eq(#G.rowsFor(nil, ctx), 0, "nil event does not crash")

local m = G.menuFor({ { kind = "move", slot = 1 }, { kind = "move", slot = 3 }, { kind = "switch", index = 2 },
  { kind = "forfeit" } })
T.check(m.slots[1] and m.slots[3] and not m.slots[2], "only legal move slots are selectable")
T.check(m.switches[2] and not m.switches[1], "switches limited to legal indices")
T.check(m.forfeit and not m.struggle and not m.locked, "forfeit offered, no struggle or lock")
m = G.menuFor({ { kind = "move", slot = 0 }, { kind = "forfeit" } })
T.check(m.struggle and not m.any, "no usable move means Struggle")
m = G.menuFor({ { kind = "move", slot = 2, locked = true }, { kind = "forfeit" } })
T.eq(m.locked and m.locked.slot, 2, "locked move auto submits")
m = G.menuFor({ { kind = "switch", index = 3 }, { kind = "switch", index = 4 } })
T.check(m.switches[3] and m.switches[4] and not m.any, "replacement menu limited to legal indices")

local function texts(rs) local o = {} for _, x in ipairs(rs) do o[#o + 1] = x.text end return table.concat(o, "|") end
T.eq(texts(G.endRows({ outcome = "win", why = "faint" }, ctx)), "RED FIX BEAT\nGARY!{PROMPT}", "win line from the cache")
T.eq(texts(G.endRows({ outcome = "lose", why = "faint" }, ctx)), "RED lost to\nGARY!{PROMPT}", "lose line")
T.eq(texts(G.endRows({ outcome = "win", why = "forfeit" }, ctx)), "GARY forfeited\nthe match!|RED FIX BEAT\nGARY!{PROMPT}",
  "foe forfeit then win")
T.eq(texts(G.endRows({ outcome = "draw", why = "desync" }, ctx)), "The link was\nlost.", "desync line")
T.eq(texts(G.endRows({ outcome = "draw", why = "disconnect" }, ctx)), "The link was\nlost.", "disconnect line")
T.eq(texts(G.endRows({ outcome = "draw", why = "error" }, ctx)), "The battle can't\ncontinue.", "error line")

local function stream(seed)
  local a, b = L.pair()
  local go = { seed = seed, size = 2 }
  local gens = { [0] = 1, [1] = 3 }
  local me = BattleSession.new({ net = a, seat = 0, go = go, gens = gens, data = F.gen1(), records = p0,
    names = { [0] = "RED", [1] = "BOT" }, now = function() return 0 end })
  local bot = BattleSession.new({ net = b, seat = 1, go = go, gens = gens, records = p1,
    names = { [0] = "RED", [1] = "BOT" }, now = function() return 0 end })
  local stepMe, stepBot = L.bot(me, { seed = seed, switches = true }), L.bot(bot, { seed = seed + 1 })
  local evs = {}
  for _ = 1, 3000 do
    stepMe()
    stepBot()
    for _, e in ipairs(me:events()) do evs[#evs + 1] = e end
    if me.result and bot.result then break end
  end
  return evs, me
end

local seen, said, errs = {}, 0, 0
for seed = 1, 12 do
  local evs, me = stream(seed)
  T.check(me.result ~= nil, "loopback battle " .. seed .. " ends")
  local c
  for i, e in ipairs(evs) do
    if e.kind == "ready" then
      c = assert(G.newCtx(data, 0, e.parties, { me = "RED", foe = "BOT" }))
    elseif c then
      local rest = { unpack(evs, i + 1) }
      local ok, rs = pcall(G.rowsFor, e, c, rest, 1)
      if not ok then errs = errs + 1 end
      for _, x in ipairs(ok and rs or {}) do
        seen[x.op] = true
        if x.op == "say" then said = said + 1 end
      end
    end
  end
end
T.eq(errs, 0, "every streamed event maps without an error")
for _, op in ipairs({ "say", "move", "hp", "faint", "sendout" }) do
  T.check(seen[op], "the stream produced " .. op .. " rows")
end
T.check(said > 50, "streamed msgs became text (" .. said .. ")")

T.finish()
