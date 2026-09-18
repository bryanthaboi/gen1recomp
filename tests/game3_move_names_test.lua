-- Unit tests for robust Move Name resolution across numbers, strings, and wrapped tables.

local Moves = require("src.core.game3.battle.moves")
local Pokemon = require("src.core.game3.pokemon")
local PartyView = require("src.core.game3.battle.party_view")

local checksPassed = 0
local function check(cond, msg)
  if not cond then
    error("[FAIL] " .. tostring(msg))
  end
  checksPassed = checksPassed + 1
  print("[ok] " .. tostring(msg))
end

print("[test] 1. Numeric Move IDs")
check(Moves.displayName(15) == "CUT", "Moves.displayName(15) == 'CUT'")
check(Moves.displayName(33) == "TACKLE", "Moves.displayName(33) == 'TACKLE'")
check(Moves.displayName(45) == "GROWL", "Moves.displayName(45) == 'GROWL'")
check(Pokemon.moveName(15) == "CUT", "Pokemon.moveName(15) == 'CUT'")
check(Pokemon.moveName(33) == "TACKLE", "Pokemon.moveName(33) == 'TACKLE'")

print("[test] 2. String Move Names / Keys")
check(Moves.displayName("CUT") == "CUT", "Moves.displayName('CUT') == 'CUT'")
check(Moves.displayName("TACKLE") == "TACKLE", "Moves.displayName('TACKLE') == 'TACKLE'")
check(Moves.displayName("THUNDER_SHOCK") == "THUNDERSHOCK" or Moves.displayName("THUNDER_SHOCK") == "THUNDER SHOCK", "Thunder shock name handled")
check(Pokemon.moveName("CUT") == "CUT", "Pokemon.moveName('CUT') == 'CUT'")
check(Pokemon.moveName("TACKLE") == "TACKLE", "Pokemon.moveName('TACKLE') == 'TACKLE'")

print("[test] 3. Wrapped Table Move Objects (e.g. { id = 15, pp = 30 }, { id = 'CUT' })")
check(Moves.displayName({ id = 15, pp = 30 }) == "CUT", "Moves.displayName({ id = 15, pp = 30 }) == 'CUT'")
check(Moves.displayName({ id = "CUT", pp = 30 }) == "CUT", "Moves.displayName({ id = 'CUT', pp = 30 }) == 'CUT'")
check(Moves.displayName({ move = 15 }) == "CUT", "Moves.displayName({ move = 15 }) == 'CUT'")
check(Moves.displayName({ name = "CUT" }) == "CUT", "Moves.displayName({ name = 'CUT' }) == 'CUT'")
check(Pokemon.moveName({ id = 15, pp = 30 }) == "CUT", "Pokemon.moveName({ id = 15, pp = 30 }) == 'CUT'")
check(Pokemon.moveName({ id = "CUT" }) == "CUT", "Pokemon.moveName({ id = 'CUT' }) == 'CUT'")

print("[test] 4. PartyView.fromSession with Table Moves")
local rawParty = {
  {
    species = 1,
    level = 10,
    moves = {
      33,
      45,
      { id = 15, pp = 30 },
      { id = "GROWL", pp = 40 },
    },
    pp = { 35, 40, 30, 40 },
  }
}

local battleParty, remap = PartyView.fromSession(rawParty, nil)
local mon = battleParty[1]
check(mon ~= nil, "Battle party constructed")
check(mon.moves[1] == 33, "Slot 1 move is 33 (Tackle)")
check(mon.moves[2] == 45, "Slot 2 move is 45 (Growl)")
check(mon.moves[3] == 15, "Slot 3 move table unwrapped to 15 (Cut)")
check(mon.moves[4] == "GROWL" or mon.moves[4] == 45, "Slot 4 move table unwrapped to Growl")
check(Moves.displayName(mon.moves[1]) == "TACKLE", "Slot 1 displays as TACKLE")
check(Moves.displayName(mon.moves[2]) == "GROWL", "Slot 2 displays as GROWL")
check(Moves.displayName(mon.moves[3]) == "CUT", "Slot 3 displays as CUT (not table: 0x...)")
check(Moves.displayName(mon.moves[4]) == "GROWL", "Slot 4 displays as GROWL")

print(string.format("\nAll %d move name resolution tests passed successfully!", checksPassed))
