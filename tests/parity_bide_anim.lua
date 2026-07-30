-- Parity test: which animation BIDE plays on which turn (#375).  BIDE is a
-- ResidualEffects2 entry (data/battle/residual_effects_2.asm:18), so the
-- ordinary PlayMoveAnimation is skipped on the storing turn and BideEffect
-- (engine/battle/effects.asm:764-789) ends on
-- `ldh a, [hWhoseTurn] / add XSTATITEM_ANIM / jp PlayBattleAnimation2`:
-- the X-item spiral, duplicated for the enemy side.  BIDE's own hit
-- animation belongs to .UnleashEnergy (engine/battle/core.asm:3501-3529),
-- which re-points wPlayerMoveNum at BIDE and rejoins
-- HandleIfPlayerMoveMissed, i.e. after UnleashedEnergyText and before the
-- HP bar drains.  The accuracy half of the release is in tests/parity_J.lua.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not (Data.moves and Data.moves.BIDE) then Data:load() end
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)

local Font = require("src.render.Font")
if not pcall(Font.encode, "A") then Font.load(Data) end

local Game = require("src.core.Game")
Game.data = Data
Game.save = require("src.core.SaveData").newGame()

local Pokemon = require("src.pokemon.Pokemon")
local BattleState = require("src.battle.BattleState")
local S = require("tests.harness").suite("parity bide anim")
local check, eq = S.check, S.eq

local function freshBattle()
  Game.save.party = { Pokemon.new(Data, "BULBASAUR", 20) }
  local tb = BattleState.newWild(Game, "PIDGEY", 10)
  tb.queue, tb.nextInsert = {}, 0
  return tb
end

-- the rows this suite cares about, in queue order: text lines and anim names
local function trace(tb)
  local out = {}
  for _, row in ipairs(tb.queue) do
    if row.text then
      out[#out + 1] = { text = (row.text:gsub("\n", " ")) }
    elseif row.anim then
      out[#out + 1] = { anim = row.anim, isPlayer = row.attackerIsPlayer }
    elseif row.drain then
      out[#out + 1] = { drain = true }
    end
  end
  return out
end

local function indexOfAnim(rows, name)
  for i, r in ipairs(rows) do
    if r.anim == name then return i end
  end
  return nil
end

local function indexOfText(rows, needle)
  for i, r in ipairs(rows) do
    if r.text and r.text:find(needle, 1, true) then return i end
  end
  return nil
end

local function anyAnim(rows, name)
  return indexOfAnim(rows, name) ~= nil
end

-- the three animations this behavior needs must actually be in the cache, or
-- AnimPlayer:start warns and plays nothing
do
  local anims = Data.battle_anims and Data.battle_anims.moveAnims
  check(anims ~= nil, "battle_anims carries moveAnims")
  if anims then
    check(anims.BIDE ~= nil, "BIDE has an animation")
    check(anims.XSTATITEM_ANIM ~= nil, "XSTATITEM_ANIM has an animation")
    check(anims.XSTATITEM_DUPLICATE_ANIM ~= nil,
          "XSTATITEM_DUPLICATE_ANIM has an animation")
  end
end

-- storing turn, player side: used-BIDE line, X-item spiral, storing line.
-- The bug queued BIDE's hit row (sound = "BIDE", subanim 4) here instead.
do
  local tb = freshBattle()
  tb:performMove(tb.player, tb.enemy, { id = "BIDE", pp = 10 }, false)
  local rows = trace(tb)
  eq(tb.player.bideTurns ~= nil, true, "the storing turn locks BIDE in")
  eq(tb.player.bideDamage, 0, "and zeroes the accumulator")
  check(not anyAnim(rows, "BIDE"),
        "BIDE's own animation does not play on the storing turn (#375)")
  local spiral = indexOfAnim(rows, "XSTATITEM_ANIM")
  check(spiral ~= nil, "the storing turn plays XSTATITEM_ANIM")
  eq(rows[spiral] and rows[spiral].isPlayer, true,
     "on the player's side of the field")
  local used = indexOfText(rows, "used BIDE!")
  local storing = indexOfText(rows, "storing energy!")
  check(used and spiral and used < spiral,
        "the spiral comes after the used-BIDE line")
  check(spiral and storing and spiral < storing,
        "and before the storing-energy line")
  check(tb.moveAnimRow == nil, "the peeled move-anim row is not left dangling")
  check(not anyAnim(rows, "XSTATITEM_DUPLICATE_ANIM"),
        "the player never gets the enemy-side duplicate")
end

-- enemy side: PlayBattleAnimation2 adds hWhoseTurn, so the foe gets
-- XSTATITEM_DUPLICATE_ANIM (AttackAnimationPointers[174])
do
  local tb = freshBattle()
  tb:performMove(tb.enemy, tb.player, { id = "BIDE", pp = 10 }, false)
  local rows = trace(tb)
  check(not anyAnim(rows, "BIDE"),
        "the foe's storing turn is animation-free of BIDE too")
  check(not anyAnim(rows, "XSTATITEM_ANIM"),
        "and does not borrow the player row")
  local dup = indexOfAnim(rows, "XSTATITEM_DUPLICATE_ANIM")
  check(dup ~= nil, "the foe's storing turn plays XSTATITEM_DUPLICATE_ANIM")
  check(dup and not rows[dup].isPlayer, "attributed to the enemy side")
end

-- locked turns: .BideCheck decrements with no text of its own in pokered and
-- no animation either; the port prints the storing line, and that is all
do
  local tb = freshBattle()
  tb.player.bideTurns = 3
  tb.player.bideDamage = 0
  tb:continueBide(tb.player, tb.enemy)
  local rows = trace(tb)
  eq(tb.player.bideTurns, 2, "a locked turn just counts down")
  check(indexOfText(rows, "storing energy!") ~= nil, "and reprints the line")
  for _, r in ipairs(rows) do
    check(r.anim == nil, "no animation on a locked turn: " .. tostring(r.anim))
  end
end

-- release turn: text, then BIDE's animation, then the bar drains
do
  local tb = freshBattle()
  tb.enemy.mon.stats.hp = 200
  tb.enemy.mon.hp = 200
  tb.player.bideTurns = 1
  tb.player.bideDamage = 40
  tb:continueBide(tb.player, tb.enemy)
  local rows = trace(tb)
  eq(tb.enemy.mon.hp, 120, "the release deals bideDamage*2")
  local unleashed = indexOfText(rows, "unleashed energy!")
  local hit = indexOfAnim(rows, "BIDE")
  check(unleashed ~= nil, "the release prints UnleashedEnergyText")
  check(hit ~= nil, "the release plays BIDE's own animation (#375)")
  eq(rows[hit] and rows[hit].isPlayer, true, "from the player's side")
  check(unleashed and hit and unleashed < hit,
        "the animation follows the text")
  local drainAt
  for i, r in ipairs(rows) do
    if r.drain then drainAt = i; break end
  end
  check(drainAt ~= nil, "the HP bar drain is queued")
  check(hit and drainAt and hit < drainAt,
        "and the animation runs before the bar moves")
  check(not anyAnim(rows, "XSTATITEM_ANIM"),
        "the release is not the X-item spiral")
end

-- zero stored damage sets wMoveMissed, so the failure path stays anim-free
do
  local tb = freshBattle()
  local hpBefore = tb.enemy.mon.hp
  tb.player.bideTurns = 1
  tb.player.bideDamage = 0
  tb:continueBide(tb.player, tb.enemy)
  local rows = trace(tb)
  eq(tb.enemy.mon.hp, hpBefore, "nothing stored means no damage")
  check(indexOfText(rows, "But, it failed!") ~= nil, "it prints the failure")
  check(not anyAnim(rows, "BIDE"), "and plays no animation")
end

S.finish()
