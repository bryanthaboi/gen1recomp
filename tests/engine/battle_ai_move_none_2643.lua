package.path = "./?.lua;./?/init.lua;" .. package.path
love = require("tests.love_stub")
local T = require("tests.harness").suite("Battle AI MOVE_NONE #2643")
local version = os.getenv("AI2643_EDITION") or "emerald"
local Cache = require("tests.game3_cache")
local root = Cache.root(version, "pokemon/battle_moves.lua")
if not root then print("[skip] #2643 battle AI: " .. tostring(Cache.reason)); T.finish(); return end
local candidate = os.getenv("AI2643_CANDIDATE")
if candidate then package.preload["src.core.game3.battle.ai_cmds"] = assert(loadfile(candidate)) end
require("src.core.GameVersion").set(version)
require("src.import.gba.versions").select(version)
local Dataset = require("src.core.game3.dataset"); Dataset.cacheRootOverride = root
require("src.core.game3.profile").reset()
local C = require("src.core.game3.constants").of(version)
local Pokemon = require("src.core.game3.pokemon"); Pokemon.install(nil)
local Space = require("src.core.game3.scripting.space")
Space.store = { flags = {}, vars = {} }
local sess = { version = version, trainerId = 12345, party = {}, flags = Space.store.flags, vars = Space.store.vars }
local Runtime = require("src.core.game3.runtime"); local sessionFn = Runtime.getSession
Runtime.getSession = function() return sess end
local D = require("src.core.game3.rse.frontier.trainers")
local State = require("src.core.game3.battle.state")
local Moves = require("src.core.game3.battle.moves")
local Ai = require("src.core.game3.battle.ai")
local Cmds = require("src.core.game3.battle.ai_cmds")
local Palace = require("src.core.game3.battle.facility_palace")
local Engine = require("src.core.game3.battle.engine")
local none = assert(Pokemon.battleMove(0))
T.eq(none.power, 0, "actual ROM MOVE_NONE power")
T.eq(none.type, 0, "actual ROM MOVE_NONE normal type")
T.eq(none.effect, 0, "actual ROM MOVE_NONE hit effect")
T.raises(function() Moves.get(0) end, "no ROM name", "MOVE_NONE stays invalid as named action")
T.raises(function() Moves.get(9999) end, "no ROM move row", "invalid real action remains strict")
for _, command in ipairs({ "get_move_power_from_result", "get_move_type_from_result", "get_move_effect_from_result" }) do
  local vm = { ip = 1, funcResult = 0 }
  local ok, err = pcall(Cmds.CMD[command], vm, {})
  T.check(ok, "actual source result sentinel command " .. command .. " " .. tostring(err))
  T.check(ok and vm.funcResult == none[command:find("power") and "power" or command:find("type") and "type" or "effect"], "ROM row drives " .. command)
end
local full = { "MOVE_TACKLE", "MOVE_GROWL", "MOVE_PROTECT", "MOVE_SURF" }
local counter = { "MOVE_TACKLE", "MOVE_GROWL", "MOVE_PROTECT", "MOVE_COUNTER" }
local function mon(labels, padding)
  local m = D.createMon(C:require("species", "SPECIES_SWAMPERT"), 50, 20, 3, 99)
  local moves = {}; for i, name in ipairs(labels) do moves[i] = C:require("moves", name) end
  D.setMoves(m, moves)
  if padding ~= nil then for i = #moves + 1, 4 do m.moves[i] = padding; m.pp[i] = 0; m.maxPp[i] = 0 end end
  return m
end
local function state(labels, padding, double)
  local player, foe = { mon(labels, padding) }, { mon(full) }
  if double then player[2], foe[2] = mon(labels, padding), mon(full) end
  local st = State.new({ playerParty = player, foeParty = foe, double = double })
  st.session, st.aiFlags, st.trainerItems = sess, 7, { 0, 0, 0, 0 }
  st.rng = function(lo) return lo or 0 end
  return st
end
local get, zeroLookups = Moves.get, 0
Moves.get = function(id) if id == 0 then zeroLookups = zeroLookups + 1 end; return get(id) end
local Damage = require("src.core.game3.battle.damage")
local damage, noneDamage, realDamage = Damage.calc, 0, 0
Damage.calc = function(user, target, id, opts)
  if id == nil or id == 0 or id == "" then noneDamage = noneDamage + 1 else realDamage = realDamage + 1 end
  return damage(user, target, id, opts)
end
for _, case in ipairs({
  { "compact partial", { "MOVE_TACKLE" } }, { "valid full", full }, { "first-turn Counter", counter },
  { "numeric padding", { "MOVE_TACKLE" }, 0 }, { "empty string padding", { "MOVE_TACKLE" }, "" },
  { "double Counter", counter, nil, true },
}) do
  for _, kind in ipairs(version == "emerald" and { "ordinary", "Palace" } or { "ordinary" }) do
    local st = state(case[2], case[3], case[4])
    T.check(not st.enemy.lastMove and not st.player.lastMove, case[1] .. " initial last move absent")
    local limitations = Engine.moveLimitations
    local fac = Palace.new(); fac:start(st)
    local ok, result = pcall(function()
      if kind == "ordinary" then return Ai.chooseMove(st, { battler = 0 }) end
      local a = { kind = "move", slot = 1, move = st.player.mon.moves[1] }
      local b = { kind = "move", slot = 1, move = st.enemy.mon.moves[1] }
      fac:actions(st, a, b)
      return a
    end)
    T.check(ok, case[1] .. " " .. kind .. " evaluates real imported scripts " .. tostring(result))
    T.check(ok and result and result.move ~= 0 and result.slot and st.player.mon.moves[result.slot] ~= 0,
      case[1] .. " " .. kind .. " returns only real move action")
    T.check(Engine.moveLimitations == limitations, case[1] .. " " .. kind .. " restores mask hook")
  end
end
T.eq(zeroLookups, 0, "AI metadata and empty slots never construct a named zero move")
T.eq(noneDamage, 0, "MOVE_NONE and absent slots never reach real damage calculation")
T.check(realDamage > 0, "real move damage remains evaluated")
Damage.calc = damage
Moves.get = get
local cache = Dataset.cache(); local read = cache.read
local rows, loaded, chunk, chunkCache = Moves._rom, Moves._romLoaded, Moves._romChunk, Moves._romChunkCache
Moves._rom, Moves._romLoaded, Moves._romChunk, Moves._romChunkCache = nil, false, nil, nil
cache.read = function(self, path) if path:find("pokemon/battle_moves.lua", 1, true) then return nil end; return read(self, path) end
T.raises(function() Cmds.move_power(0) end, "cache", "sentinel metadata refuses missing required ROM pack")
T.raises(function() Cmds.move_power(0) end, "cache", "sentinel metadata still refuses after failed pack lookup")
cache.read = read; Moves._rom, Moves._romLoaded, Moves._romChunk, Moves._romChunkCache = rows, loaded, chunk, chunkCache
local battleRows = Pokemon._battleMoves
local withoutNone = {}; for id, row in pairs(battleRows) do if id ~= 0 then withoutNone[id] = row end end
Pokemon._battleMoves = withoutNone
T.raises(function() Cmds.move_power(0) end, nil, "missing ROM sentinel cannot silently use builtin row")
Pokemon._battleMoves = battleRows
T.raises(function() Cmds.move_power(9999) end, "no ROM move row", "invalid nonzero AI metadata stays strict")
Runtime.getSession = sessionFn
T.finish()
