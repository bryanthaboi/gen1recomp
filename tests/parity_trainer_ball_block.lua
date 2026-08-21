-- Parity test: a ball thrown at a trainer's mon is blocked, animated, and
-- costs the turn (#291).  pokered engine/items/item_effects.asm:109-113
-- branches to ThrowBallAtTrainerMon before ItemUseText00 ever prints;
-- :2292-2303 plays TOSS_ANIM and prints the two block texts; animations.asm:
-- 2629-2637 .BlockBall is the plain arc whatever the ball tier; and the turn
-- is still spent (core.asm:2257-2259).  Pixels: the #291 driver.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local Data = require("src.core.Data")
if not (Data.pokemon and Data.pokemon.RATTATA) then Data:load() end
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)

local Pokemon = require("src.pokemon.Pokemon")
local BattleState = require("src.battle.BattleState")
local S = require("tests.harness").suite("parity trainer ball block")
local check, eq = S.check, S.eq

local function freshGame()
  return {
    data = Data,
    save = {
      party = { Pokemon.new(Data, "CHARIZARD", 50) },
      player = { name = "RED" },
      inventory = { POKE_BALL = 5, MASTER_BALL = 1 },
      options = { battleStyle = "set", battleAnim = "on" },
      pokedex = { seen = {}, owned = {} },
      flags = {},
      money = 0,
    },
    stack = { push = function() end, pop = function() end, top = function() end },
  }
end

-- Throw `ball` and drain the queue, recording what the player would see.
-- executeAction / endOfTurn are wrapped and counted: their absence is the
-- "free turn" half of the report.
local function throwAndRecord(b, ball)
  local rec = { anims = {}, texts = {}, actions = 0, endTurns = 0 }
  local realAction, realEnd = b.executeAction, b.endOfTurn
  b.executeAction = function(self, ...)
    rec.actions = rec.actions + 1
    return realAction(self, ...)
  end
  b.endOfTurn = function(self, ...)
    rec.endTurns = rec.endTurns + 1
    return realEnd(self, ...)
  end
  b.phase = "messages"      -- what openItems leaves behind before BagMenu
  b.afterQueue = "menu"
  b.nextInsert = 0
  local ok, err = pcall(function()
    b:throwBall(ball)
    local n = 0
    while #b.queue > 0 and n < 400 do
      n = n + 1
      local item = table.remove(b.queue, 1)
      if item.fn then
        b.nextInsert = 0
        item.fn()
      elseif item.anim then
        rec.anims[#rec.anims + 1] = item.anim
      elseif item.text then
        rec.texts[#rec.texts + 1] = item.text
      end
    end
  end)
  rec.ok, rec.err = ok, err
  return rec
end

local function joined(list) return table.concat(list, " | ") end

local function has(list, needle)
  for _, v in ipairs(list) do
    if v == needle or (type(v) == "string" and v:find(needle, 1, true)) then
      return true
    end
  end
  return false
end

-- ItemUseText00 is "<PLAYER> used\n<ITEM>!".  Anchor on the player name, or
-- the foe's own "Enemy RATTATA used TACKLE!" reads as the item line.
local function itemUseLine(texts)
  for _, t in ipairs(texts) do
    if t:find("^RED used") then return t end
  end
  return nil
end

local function indexOf(list, needle)
  for i, v in ipairs(list) do
    if v == needle or (type(v) == "string" and v:find(needle, 1, true)) then
      return i
    end
  end
  return nil
end

-- The ROM's own wording, used verbatim: a hard-coded copy is how the port
-- ended up with "The TRAINER" in upper case.
do
  check(type(Data.text._ThrowBallAtTrainerMonText1) == "string",
        "_ThrowBallAtTrainerMonText1 is in the generated text")
  check(type(Data.text._ThrowBallAtTrainerMonText2) == "string",
        "_ThrowBallAtTrainerMonText2 is in the generated text")
  check(Data.battle_anims and Data.battle_anims.moveAnims
        and Data.battle_anims.moveAnims.BLOCKBALL_ANIM ~= nil,
        "BLOCKBALL_ANIM has an extracted animation program")
  check(Data.battle_anims and Data.battle_anims.moveAnims
        and Data.battle_anims.moveAnims.TOSS_ANIM ~= nil,
        "TOSS_ANIM has an extracted animation program")
  if Data.audio then
    check(Data.audio.sfx and Data.audio.sfx.Faint_Thud ~= nil,
          "SFX_FAINT_THUD is in the generated audio")
  end
end

do
  local Game = freshGame()
  local b = BattleState.newTrainer(Game, "OPP_YOUNGSTER", 1)
  eq(b.kind, "trainer", "the fixture really is a trainer battle")
  local rec = throwAndRecord(b, "POKE_BALL")
  check(rec.ok, "the trainer throw pumped without error: " .. tostring(rec.err))

  -- ItemUseBall branches out before ItemUseText00.
  check(itemUseLine(rec.texts) == nil,
        "no \"<PLAYER> used <ITEM>!\" line in a trainer battle (#291): "
        .. joined(rec.texts))

  -- .BlockBall: the arc, then the block.
  check(has(rec.anims, "TOSS_ANIM"),
        "the toss arc is queued (#291): " .. joined(rec.anims))
  check(has(rec.anims, "BLOCKBALL_ANIM"),
        "the block animation is queued (#291): " .. joined(rec.anims))
  local toss, block = indexOf(rec.anims, "TOSS_ANIM"),
                      indexOf(rec.anims, "BLOCKBALL_ANIM")
  check(toss and block and toss < block, "the arc plays before the block")
  check(not has(rec.anims, "GREATTOSS_ANIM")
        and not has(rec.anims, "ULTRATOSS_ANIM"),
        ".BlockBall hardcodes the plain TOSS arc, not the per-tier one")

  -- The ROM's texts, in order, after the animation.
  eq(rec.texts[1], Data.text._ThrowBallAtTrainerMonText1,
     "the block line is the ROM's own text, lower-case \"trainer\" and all")
  eq(rec.texts[2], Data.text._ThrowBallAtTrainerMonText2,
     "followed by _ThrowBallAtTrainerMonText2")

  -- The turn is spent: this is the half that made a throw free scouting.
  eq(rec.actions, 1, "the foe takes its turn after the block (#291)")
  eq(rec.endTurns, 1, "and end-of-turn effects run (#291)")
end

-- .BlockBall ignores wCurItem for the arc it picks.  It still flickers OBP0
-- for a Master/Ultra toss, but that rides on the row's `ball` field.
do
  local Game = freshGame()
  local b = BattleState.newTrainer(Game, "OPP_YOUNGSTER", 1)
  local rec = throwAndRecord(b, "MASTER_BALL")
  check(rec.ok, "the Master Ball throw pumped without error")
  check(has(rec.anims, "TOSS_ANIM") and has(rec.anims, "BLOCKBALL_ANIM"),
        "a Master Ball is blocked with the same plain arc: " .. joined(rec.anims))
  check(itemUseLine(rec.texts) == nil,
        "and still prints no \"used\" line: " .. joined(rec.texts))
  eq(rec.actions, 1, "and still costs the turn")
end

-- Control: wIsInBattle == 1 in the wild, so ItemUseText00 does print and the
-- block branch is never reached.  If this regresses, every catch in the game
-- lost its "used" line.
do
  local Game = freshGame()
  local b = BattleState.newWild(Game, "PIDGEY", 8)
  eq(b.kind, "wild", "the control fixture is a wild battle")
  local rec = throwAndRecord(b, "POKE_BALL")
  check(rec.ok, "the wild throw pumped without error: " .. tostring(rec.err))
  check(itemUseLine(rec.texts) ~= nil,
        "a wild throw still prints \"RED used POKé BALL!\": " .. joined(rec.texts))
  check(not has(rec.anims, "BLOCKBALL_ANIM"),
        "and nothing blocks it: " .. joined(rec.anims))
  check(not has(rec.texts, "thief"), "no \"Don't be a thief!\" in the wild")
end

S.finish()
