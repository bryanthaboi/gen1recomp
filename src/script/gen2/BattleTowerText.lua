-- ../pokecrystal/engine/events/battle_tower/trainer_text.asm:1-84

local BattleTower = require("src.core.gen2.BattleTower")

local M = {}

-- ../pokecrystal/constants/battle_tower_constants.asm:49-53
M.INTRO, M.WIN, M.LOSS = 1, 2, 3

-- trainer_text.asm:10-28
function M.gender(text, trainer)
  local key
  if text.genderByName then
    key = trainer.nameRaw and trainer.nameRaw[6] or 0
  else
    key = trainer.class or 0
  end
  local byte = text.classGenders[(key - 1) % 256 + 1] or 0
  return byte ~= 0 and "female" or "male"
end

-- trainer_text.asm:29-49
function M.roll(set, random)
  local value = random(set.mask + 1) - 1
  if value >= set.count then value = value - set.count end
  return value
end

function M.set(text, trainer)
  return M.gender(text, trainer) == "female" and text.female or text.male
end

-- trainer_text.asm:51-79: `kind` is the BATTLETOWERTEXT_* byte and `index`
-- the stored wBT_TrainerTextIndex.
function M.pick(roster, trainerIndex, kind, index)
  if not roster then return nil end
  local text = roster.text
  if type(text) ~= "table" then error("trainers.lua battleTower has no text", 2) end
  local trainer = roster.trainers[(trainerIndex or 0) + 1]
  if not trainer then return nil end
  local set = M.set(text, trainer)
  local list = (kind == M.INTRO and set.intro)
    or (kind == M.WIN and set.playerLost)
    or (kind == M.LOSS and set.playerWon)
  return list and list[(index or 0) + 1] or nil
end

-- ../pokecrystal/engine/overworld/scripting.asm:447-452 over the VM's drawn
-- opponent; INTRO rolls wBT_TrainerTextIndex (trainer_text.asm:52-56).
function M.forVm(vm, kind, random)
  local hooks = vm.specials or {}
  local roster = BattleTower.roster(hooks.data and hooks.data())
  local opponent = vm.btOpponent
  if not (roster and opponent) then return nil end
  if type(roster.text) ~= "table" then
    error("trainers.lua battleTower has no text", 2)
  end
  local trainer = roster.trainers[opponent.index + 1]
  if not trainer then return nil end
  if kind == M.INTRO then
    vm.btTextIndex = M.roll(M.set(roster.text, trainer), random)
  end
  return M.pick(roster, opponent.index, kind, vm.btTextIndex or 0)
end

return M
