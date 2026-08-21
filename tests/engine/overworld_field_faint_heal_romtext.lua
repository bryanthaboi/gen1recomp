-- Two OverworldController.lua messages used to be bare Lua literals:
-- applyFieldPoison()'s "%s\nfainted!" (the third of three collapsed
-- fainted-message ROM strings, _PokemonFaintedText) and
-- useSoftboiledFieldMove()'s "It won't have\nany effect."/"%s's HP\nwas
-- restored!" (the same _ItemUseNoEffectText/_PotionText labels
-- ItemEffects.lua's real potion message already uses -- _PotionText's
-- second slot is the actual amount healed, which the old literal never
-- showed at all).
--
-- Uses the debug.setupvalue technique already established in
-- oaks_pc_flow.lua to fake the module-level Game/TextBox upvalues
-- ROM-free, without going through the heavy OverworldState:enter().
package.path = "./?.lua;./?/init.lua;" .. package.path

local T = require("tests.modkit")
local Data = T.fixtures.fresh()

local SaveData = require("src.core.SaveData")
local Pokemon = require("src.pokemon.Pokemon")
local OW = require("src.world.OverworldController")

local function setUpvalue(fn, name, val)
  local i = 1
  while true do
    local n = debug.getupvalue(fn, i)
    if not n then return false end
    if n == name then debug.setupvalue(fn, i, val); return true end
    i = i + 1
  end
end

local pushed = {}
local textBoxStub = {
  new = function(_, text, onDone, opts)
    return { text = text, onDone = onDone, opts = opts }
  end,
}
local realSound = package.loaded["src.core.Sound"]
package.loaded["src.core.Sound"] = { play = function() end, playCry = function() end }

local function mkGame()
  local save = SaveData.newGame()
  save.party = { Pokemon.new(Data, "FIXMON_A", 20) }
  pushed = {}
  return {
    data = Data, save = save,
    stack = { push = function(_, item) pushed[#pushed + 1] = item end },
  }
end

for _, name in ipairs({ "applyFieldPoison", "useSoftboiledFieldMove" }) do
  T.check(setUpvalue(OW[name], "Game", mkGame()), ("Game upvalue on %s"):format(name))
  T.check(setUpvalue(OW[name], "TextBox", textBoxStub), ("TextBox upvalue on %s"):format(name))
end

local fakeSelf = setmetatable({}, { __index = OW })

-- ---- applyFieldPoison: _PokemonFaintedText ----
do
  local game = mkGame()
  setUpvalue(OW.applyFieldPoison, "Game", game)
  local mon = game.save.party[1]
  mon.status = "PSN"
  mon.hp = 1 -- one poison tick (1 dmg by default) faints it
  game.save.poisonSteps = 3 -- (3+1) % 4 == 0: this step ticks poison

  Data.text._PokemonFaintedText = "FAKE {RAM:wNameBuffer} FAKE!"
  fakeSelf:applyFieldPoison()
  T.eq(pushed[1] and pushed[1].text, "FAKE " .. (mon.nickname or "FIXMON A") .. " FAKE!",
    "a translated _PokemonFaintedText reaches the field-poison faint message")
  Data.text._PokemonFaintedText = nil
end

-- vanilla: no catalog entry, English literal
do
  local game = mkGame()
  setUpvalue(OW.applyFieldPoison, "Game", game)
  local mon = game.save.party[1]
  mon.status = "PSN"
  mon.hp = 1
  game.save.poisonSteps = 3

  fakeSelf:applyFieldPoison()
  T.eq(pushed[1] and pushed[1].text,
    (mon.nickname or "FIXMON A") .. "\nfainted!",
    "no catalog entry falls back to the English fainted literal")
end

-- ---- useSoftboiledFieldMove: _ItemUseNoEffectText / _PotionText ----
do
  local game = mkGame()
  setUpvalue(OW.useSoftboiledFieldMove, "Game", game)
  local user = Pokemon.new(Data, "FIXMON_A", 20)
  local target = Pokemon.new(Data, "FIXMON_B", 20)
  target.hp = target.stats.hp -- already full: no effect

  Data.text._ItemUseNoEffectText = "FAKE-NOEFFECT!"
  local ok = fakeSelf:useSoftboiledFieldMove(user, target)
  T.check(ok == false, "a full-HP target reports no effect")
  T.eq(pushed[1] and pushed[1].text, "FAKE-NOEFFECT!",
    "a translated _ItemUseNoEffectText reaches the no-effect message")
  Data.text._ItemUseNoEffectText = nil
end

do
  local game = mkGame()
  setUpvalue(OW.useSoftboiledFieldMove, "Game", game)
  local user = Pokemon.new(Data, "FIXMON_A", 20)
  local target = Pokemon.new(Data, "FIXMON_B", 20)
  target.hp = target.stats.hp - 10 -- missing exactly 10 HP

  Data.text._PotionText = "FAKE {RAM:wNameBuffer} healed {NUM:wHPBarHPDifference, 2, 3}!"
  local ok = fakeSelf:useSoftboiledFieldMove(user, target)
  T.check(ok == true, "a damaged target heals successfully")
  T.eq(pushed[1] and pushed[1].text,
    "FAKE " .. (target.nickname or "FIXMON B") .. " healed 10!",
    "a translated _PotionText reaches the heal message, amount included")
  Data.text._PotionText = nil
end

-- vanilla: no catalog entry, the fallback's single %s slot still fills
-- correctly (the amount is silently dropped by design, same as
-- ItemEffects.lua's own _PotionText fallback -- not a regression, this
-- matches the pre-fix literal's behavior exactly)
do
  local game = mkGame()
  setUpvalue(OW.useSoftboiledFieldMove, "Game", game)
  local user = Pokemon.new(Data, "FIXMON_A", 20)
  local target = Pokemon.new(Data, "FIXMON_B", 20)
  target.hp = target.stats.hp - 10
  local ok = fakeSelf:useSoftboiledFieldMove(user, target)
  T.check(ok == true, "a damaged target heals successfully (vanilla)")
  T.eq(pushed[1] and pushed[1].text,
    (target.nickname or "FIXMON B") .. "'s HP\nwas restored!",
    "no catalog entry falls back to the English literal (no amount shown)")
end

package.loaded["src.core.Sound"] = realSound
T.finish("overworld_field_faint_heal_romtext")
