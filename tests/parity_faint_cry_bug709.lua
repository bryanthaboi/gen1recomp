-- Parity test: the faint sound sequence matches pokered, per side.
--
--   RemoveFaintedPlayerMon (engine/battle/core.asm:1003-1045): the player
--   mon's faint plays its ordinary species cry (PlayCry) -- no Faint_Fall.
--
--   FaintEnemyPokemon (engine/battle/core.asm:732-796): the enemy faint
--   plays NO species cry; trainer battles play SFX_FAINT_FALL, wait for it
--   to finish, then SFX_FAINT_THUD.  Wild battles skip both and go
--   straight to the victory music (.wild_win).
--
-- The port previously played the species cry AND Faint_Fall on every
-- faint, so a fainted enemy sounded its full battle cry and a fainted
-- player mon got the fall whistle the hardware never plays (#709).
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()
local Font = require("src.render.Font")
Font.load(Data)
local TypeChart = require("src.battle.TypeChart")
TypeChart.load(Data)
local Pokemon = require("src.pokemon.Pokemon")
local SaveData = require("src.core.SaveData")
local BattleState = require("src.battle.BattleState")
local Sound = require("src.core.Sound")

-- record cries and sfx instead of sounding them
local cries, sfx = {}, {}
Sound.playCry = function(_, species) cries[#cries + 1] = species end
Sound.play = function(_, name) sfx[#sfx + 1] = name end

local function freshGame()
  local save = SaveData.newGame()
  save.player.name = "RED"
  save.player.rival = "GARY"
  save.party = { Pokemon.new(Data, "FIXMON_A", 30) }
  return { data = Data, save = save,
           input = { wasPressed = function() return false end,
                     wasJustPressed = function() return false end },
           stack = { top = function() return nil end,
                     push = function() end, pop = function() end } }
end

local function reset()
  cries, sfx = {}, {}
end

-- pump the queue until it drains or the faint sounds have all fired (the
-- faint's sounds are actNext rows ahead of the faint text, which needs a
-- text input stub this driver does not bother to provide)
local function pump(battle, expectedSounds)
  local count = expectedSounds or 0
  local seen = 0
  for _ = 1, 60 do
    local before = #sfx
    local ok = pcall(battle.updateQueue, battle)
    if not ok then return false end
    if #sfx > before then seen = #sfx end
    if seen >= count then return true end
  end
  return false
end

-- player mon faint: only the species cry, no Faint_Fall
do
  reset()
  local game = freshGame()
  local battle = BattleState.newTrainer(game, "OPP_FIX_YOUNGSTER", 1)
  battle.participants = {}
  battle.playVictoryMusic = function() end
  battle:onFaint(battle.player)
  pump(battle, 1)
  T.eq(cries[1], "FIXMON_A", "the player mon's faint plays its species cry")
  T.eq(#cries, 1, "no other cry on the player faint")
  for _, name in ipairs(sfx) do
    T.check(name ~= "Faint_Fall",
            "the player faint never plays Faint_Fall (#709)")
  end
end

-- enemy faint, trainer battle: Faint_Fall then Faint_Thud, no species cry
do
  reset()
  local game = freshGame()
  local battle = BattleState.newTrainer(game, "OPP_FIX_YOUNGSTER", 1)
  battle.participants = {}
  battle.playVictoryMusic = function() end
  battle:onFaint(battle.enemy)
  pump(battle, 2)
  T.eq(#cries, 0, "the enemy faint plays no species cry")
  local fall, thud = false, false
  for i, name in ipairs(sfx) do
    if name == "Faint_Fall" then
      T.check(not fall, "Faint_Fall plays once")
      fall = true
      T.check(not thud, "Faint_Fall precedes Faint_Thud")
    elseif name == "Faint_Thud" then
      thud = true
    end
  end
  T.check(fall and thud, "trainer enemy faint plays Faint_Fall and Faint_Thud")
end

-- enemy faint, wild battle: no faint sfx at all (victory music only)
do
  reset()
  local game = freshGame()
  local battle = BattleState.newWild(game, "FIXMON_B", 5)
  battle.participants = {}
  battle.playVictoryMusic = function() end
  battle:onFaint(battle.enemy)
  pump(battle)
  T.eq(#cries, 0, "the wild enemy faint plays no species cry")
  for _, name in ipairs(sfx) do
    T.check(name ~= "Faint_Fall" and name ~= "Faint_Thud",
            "the wild enemy faint plays no faint sfx (.wild_win)")
  end
end

T.finish("parity faint cry bug709")
