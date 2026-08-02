-- Sandbox: boot straight into the facility with a ready party, and hand the
-- controls back to you.  No playthrough to Celadon required.
--
--   POKEPORT_DRIVER=mods/celadon_battle_facility/tests/sandbox_driver.lua love .
--
-- Knobs, all optional:
--   CBF_LEVEL=40     party level, which is what the opponents scale to
--   CBF_TOKENS=20    BATTLE PT in the bag, for testing the prize counter
--   CBF_UNLOCK=all   which tiers are pre-cleared: all | silver | none
--   CBF_WHERE=in     start inside the lobby, or `out` on Celadon's lawn
--
-- Unlike the other drivers this one never returns.  A driver that returns
-- quits the game (main.lua love.event.quit on a dead coroutine), so it parks
-- in a yield loop instead and normal input keeps working.
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Pokemon = require("src.pokemon.Pokemon")
  local Bag = require("src.inventory.Bag")

  local FACILITY = "CELADON_BATTLE_FACILITY"
  local level = tonumber(os.getenv("CBF_LEVEL")) or 40
  local tokens = tonumber(os.getenv("CBF_TOKENS")) or 20
  local unlock = os.getenv("CBF_UNLOCK") or "all"
  local where = os.getenv("CBF_WHERE") or "in"

  if not game.data.maps[FACILITY] then
    U.log("the mod is not loaded -- enable celadon_battle_facility (F10) first")
    while true do coroutine.yield() end
  end

  -- Deliberately not U.newGame: that auto-mashes through Oak's speech, which
  -- is 1200-odd frames of waiting before you get the controls.  Teleporting
  -- pushes a fresh overworld directly, which is all a sandbox needs.
  game.save.flags = game.save.flags or {}
  game.save.flags.EVENT_GOT_STARTER = true

  -- a full six, so a seven-round GOLD run has something to spend
  for i = #game.save.party, 1, -1 do table.remove(game.save.party, i) end
  for _, species in ipairs({ "CHARIZARD", "BLASTOISE", "VENUSAUR",
                             "ALAKAZAM", "SNORLAX", "LAPRAS" }) do
    table.insert(game.save.party, Pokemon.new(game.data, species, level))
  end

  Bag.add(game.save, "CBF_TOKEN", tokens, game.data)
  Bag.add(game.save, "FULL_RESTORE", 10, game.data)

  -- Pre-clear tiers so SILVER and GOLD can be reached without grinding up to
  -- them.  The mod gates on its own save bucket, which lives here.
  if unlock ~= "none" then
    local bucket = game.mods.modSave.celadon_battle_facility or {}
    local bests = { bronze = 1 }
    if unlock == "all" then bests.silver = 1 end
    bucket.bests = bests
    bucket.best_streak = (unlock == "all") and 5 or 3
    game.mods.modSave.celadon_battle_facility = bucket
  end

  if where == "out" then
    U.teleport(game, "CELADON_CITY", 6, 22, "up")
  else
    U.teleport(game, FACILITY, 6, 8, "up")
  end

  U.log(("sandbox ready: party L%d, %d BATTLE PT, unlock=%s, at %s")
    :format(level, tokens, unlock, where == "out" and "Celadon" or "the lobby"))
  U.log("greeter is straight up; clerk upper-left, records upper-right.")

  -- park forever: the game keeps updating and the keyboard is yours
  while true do coroutine.yield() end
end
