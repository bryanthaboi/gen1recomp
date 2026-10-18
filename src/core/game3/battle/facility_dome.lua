local State = require("src.core.game3.battle.state")

local Fac = {}
Fac.__index = Fac

function Fac.new()
  return setmetatable({ kind = "dome", lastMove = {} }, Fac)
end

function Fac:start(st)
  self.lastMove = {}
  -- playback leaves the live Dome record alone
  local sess = (not st.replay) and st.session or nil
  if sess then sess.frontierDomeLastMoves = { player = 0, opponent = 0 } end
end

local function num(mv)
  local n = tonumber(mv)
  if n then return n end
  local Moves = require("src.core.game3.battle.moves")
  return (mv and Moves.numForName and Moves.numForName(mv)) or 0
end

-- pokeemerald/src/battle_util.c:140
function Fac:resolveMove(st, ad, act, out, userRef, targetRef)
  local Engine = require("src.core.game3.battle.engine")
  local id = tonumber(act.battler) or ((act.user == "enemy" or (type(act.user) == "table" and act.user.side == "enemy")) and 1 or 0)
  local user = State.battler(st, id)
  local sess = (not st.replay) and st.session or nil
  if sess and user and user.mon and (tonumber(user.mon.hp) or 0) ~= 0 then
    local mv = num(user.expLockedMove or act.move)
    sess.frontierDomeLastMoves = sess.frontierDomeLastMoves or {}
    if id % 2 == 0 then sess.frontierDomeLastMoves.player = mv else sess.frontierDomeLastMoves.opponent = mv end
  end
  return Engine.resolveMove(userRef, targetRef, act.move, act.slot, ad, st, out)
end

local function allFainted(party)
  for _, mon in ipairs(party or {}) do
    if (tonumber(mon.species) or 0) ~= 0 and not mon.isEgg and (tonumber(mon.hp) or 0) > 0 then return false end
  end
  return true
end

-- pokeemerald/data/battle_scripts_1.s:2958
function Fac:finalResult(st, result)
  if result == "lose" and allFainted(st.foeParty) and allFainted(st.playerParty) then result = "draw" end
  local sess = (not st.replay) and st.session or nil
  if sess then
    sess.frontierDomeLastMoves = sess.frontierDomeLastMoves or {}
    sess.frontierDomeLastMoves.outcome = result
  end
  return result
end

return Fac
