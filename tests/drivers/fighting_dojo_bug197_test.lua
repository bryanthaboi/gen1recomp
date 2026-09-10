-- scripts/FightingDojo.asm
-- data/events/hidden_events.asm:526-531
--   POKEPORT_SHOT_DIR=/tmp/dojo POKEPORT_DRIVER=tests/drivers/fighting_dojo_bug197_test.lua \
--   POKEPORT_IDENTITY=bug197 POKEPORT_TOUCH=0 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local TextBox = require("src.render.TextBox")
  local ChoiceBox = require("src.ui.ChoiceBox")
  local OW = require("src.world.OverworldController")
  local Pokemon = require("src.pokemon.Pokemon")
  local Commands = require("src.script.Commands")

  local failures = {}
  local function check(cond, msg)
    if cond then U.log("ok:", msg) else
      table.insert(failures, msg)
      U.log("FAIL:", msg)
    end
    return cond
  end

  local function topIsTextBox() return getmetatable(game.stack:top()) == TextBox end
  local function topIsChoice() return getmetatable(game.stack:top()) == ChoiceBox end

  local function currentPageText()
    local top = game.stack:top()
    if getmetatable(top) ~= TextBox then return "" end
    local page = top.pages and top.pages[top.pageIndex]
    if not page then return "" end
    return table.concat(page, "\n")
  end

  local function pageReady()
    local top = game.stack:top()
    if getmetatable(top) ~= TextBox then return false end
    return top.waiting or top.done
  end

  -- let the current page finish typing WITHOUT advancing past it
  local function waitReadyPage()
    for _ = 1, 200 do
      if pageReady() then break end
      U.wait(2)
    end
    return currentPageText()
  end

  local function mashUntil(cond, cap)
    for _ = 1, (cap or 200) do
      if cond() then return true end
      U.tap(game, "a")
      U.wait(2)
    end
    return cond()
  end

  -- advance text pages until a ready page contains `want`; stops before
  -- blowing past a choice box
  local function sawText(want)
    return mashUntil(function()
      if topIsChoice() then return false end
      if not pageReady() then return false end
      return currentPageText():find(want, 1, true) ~= nil
    end, 150)
  end

  local function npcByName(ow, name)
    for _, n in ipairs(ow.npcs) do
      if n.def and n.def.name == name then return n end
    end
  end

  local function resetDojo(x, y, facing, flags)
    while game.stack:top() do game.stack:pop() end
    -- the four blackbelts are not under test; retire them so only the
    -- master (or the balls/poster) can react in each scenario
    game.save.flags = {
      EVENT_BEAT_FIGHTING_DOJO_TRAINER_0 = true,
      EVENT_BEAT_FIGHTING_DOJO_TRAINER_1 = true,
      EVENT_BEAT_FIGHTING_DOJO_TRAINER_2 = true,
      EVENT_BEAT_FIGHTING_DOJO_TRAINER_3 = true,
    }
    game.save.defeatedTrainers = {}
    game.save.objectToggles = {}
    game.save.itemsTaken = {}
    game.save.inventory = game.save.inventory or {}
    game.save.player.name = game.save.player.name or "RED"
    -- one healthy mon: enough for a battle to construct, room for a prize
    game.save.party = { Pokemon.new(game.data, "CHARIZARD", 50) }
    for k, v in pairs(flags or {}) do game.save.flags[k] = v end
    game.stack:push(OW, "FIGHTING_DOJO", x, y, facing or "up")
    U.wait(5)
    return game.stack:top()
  end

  ------------------------------------------------------------------
  -- BUG1/2/3 header seed sanity (deterministic, no battle needed)
  ------------------------------------------------------------------
  local hdr = game.data:trainerHeader("FightingDojo", 1)
  check(hdr ~= nil, "BUG1/2/3: Karate Master trainer header (index 1) exists")
  check(hdr and (hdr.range or 0) == 0,
    "BUG1: master relies on the exact-tile gate, not trainer sight")
  check(hdr and hdr.won ~= nil, "BUG2: master has a won (defeat) text")
  check(hdr and hdr.after ~= nil, "BUG3: master has an after (re-talk) text")

  ------------------------------------------------------------------
  -- BUG1: exact gate. Start just north of the tile to the Master's left,
  -- then step down once. The four blackbelts are cleared so only he reacts.
  ------------------------------------------------------------------
  local ow = resetDojo(4, 2, "down", {})
  U.shot(game, DIR .. "/dojo_1_before.png")
  U.tap(game, "down")
  U.wait(30)
  local engaged = topIsTextBox()
  U.log("gate dialogue open:", tostring(engaged))
  U.shot(game, DIR .. "/dojo_2_aggro.png")
  check(engaged, "BUG1: Karate Master stops the player at his left")

  ------------------------------------------------------------------
  -- BUG3: talk to the already-beaten master -> "Stay and train..." and
  -- NOT the "I am the LEADER here!" pre-battle challenge.
  ------------------------------------------------------------------
  -- talk from (4,3) facing right: beside the master (5,3), off his DOWN
  -- sight line so he can't (post-fix) aggro before we set him defeated
  ow = resetDojo(4, 3, "right", { EVENT_BEAT_KARATE_MASTER = true })
  game.save.defeatedTrainers["FIGHTING_DOJO_obj_1"] = true
  local master = npcByName(ow, "FIGHTINGDOJO_KARATE_MASTER")
  if check(master ~= nil, "BUG3: master npc present") then
    ow:talkTo(master)
    local first = waitReadyPage()
    check(not first:find("LEADER", 1, true) and not first:find("Grunt", 1, true),
      "BUG3: beaten master no longer shows the challenge (page1='" .. first .. "')")
    check(sawText("Stay and train"),
      "BUG3: beaten master says 'Stay and train at Karate with us!'")
    U.shot(game, DIR .. "/dojo_3_retalk.png")
    mashUntil(function() return game.stack:top() == ow end)
  end

  ------------------------------------------------------------------
  -- BUG2: the post-battle prize speech (run the same reward path a win
  -- takes; EVENT_BEAT_KARATE_MASTER must be unset so it prints).
  ------------------------------------------------------------------
  ow = resetDojo(4, 9, "up", {})
  ow:checkVictoryRewards("OPP_BLACKBELT", 1)
  U.wait(5)
  check(sawText("prized"),
    "BUG2: win shows the '...prized fighting POKeMON!' prize offer")
  U.shot(game, DIR .. "/dojo_2_prize.png")
  mashUntil(function() return game.stack:top() == ow end)

  ------------------------------------------------------------------
  -- BUG4 (verify-only): the Hitmonlee ball shows the species' Pokedex
  -- entry first (DisplayPokedex, #853), then the Gen1 descriptor prompt
  -- ("You want the hard kicking HITMONLEE?").
  ------------------------------------------------------------------
  ow = resetDojo(4, 2, "up", { EVENT_BEAT_KARATE_MASTER = true })
  local leeBall = npcByName(ow, "FIGHTINGDOJO_HITMONLEE_POKE_BALL")
  local chanBall = npcByName(ow, "FIGHTINGDOJO_HITMONCHAN_POKE_BALL")
  check(leeBall ~= nil and chanBall ~= nil, "BUG5: both prize balls on the mat")
  if leeBall then
    ow:talkTo(leeBall)
    check(sawText("hard kicking") or sawText("HITMONLEE"),
      "BUG4: ball asks the Gen1 descriptor prompt after the dex entry")
    U.shot(game, DIR .. "/dojo_4_prompt.png")
    ------------------------------------------------------------------
    -- BUG5: choose YES -> only the chosen ball vanishes; the other stays
    -- and, when talked to, gives the "Better not get greedy..." refusal.
    ------------------------------------------------------------------
    mashUntil(topIsChoice)
    U.tap(game, "a") -- YES (index 1)
    mashUntil(function() return game.stack:top() == ow end)
    check(game.save.flags.EVENT_GOT_HITMONLEE == true, "BUG5: received HITMONLEE")
    local leeGone = npcByName(ow, "FIGHTINGDOJO_HITMONLEE_POKE_BALL") == nil
    local chanStays = npcByName(ow, "FIGHTINGDOJO_HITMONCHAN_POKE_BALL") ~= nil
    check(leeGone, "BUG5: the chosen HITMONLEE ball is removed")
    check(chanStays, "BUG5: the other (HITMONCHAN) ball stays on the mat")
    U.shot(game, DIR .. "/dojo_5_onegone.png")
    if chanStays then
      ow:talkTo(npcByName(ow, "FIGHTINGDOJO_HITMONCHAN_POKE_BALL"))
      check(sawText("greedy"), "BUG5: remaining ball gives the greedy refusal")
      check(not game.save.flags.EVENT_GOT_HITMONCHAN,
        "BUG5: talking the other ball does NOT hand a second POKeMON")
      U.shot(game, DIR .. "/dojo_5_greedy.png")
      mashUntil(function() return game.stack:top() == ow end)
    end
  end

  ------------------------------------------------------------------
  -- BUG6: the north-wall poster.  A claimed prize frees its ball cell, so
  -- stand on (4,1) facing up and read the poster above it.
  ------------------------------------------------------------------
  ow = resetDojo(4, 1, "up",
    { EVENT_BEAT_KARATE_MASTER = true, EVENT_GOT_HITMONLEE = true })
  Commands.hide_object({ game = game, save = game.save, overworld = ow },
                       "FIGHTING_DOJO", "FIGHTINGDOJO_HITMONLEE_POKE_BALL")
  U.wait(3)
  U.shot(game, DIR .. "/dojo_6_before.png")
  ow:interact()
  check(sawText("Enemies on every"),
    "BUG6: the poster prints 'Enemies on every side!'")
  U.shot(game, DIR .. "/dojo_6_poster.png")
  mashUntil(function() return game.stack:top() == ow end)

  ow = resetDojo(5, 1, "up",
    { EVENT_BEAT_KARATE_MASTER = true, EVENT_GOT_HITMONCHAN = true })
  Commands.hide_object({ game = game, save = game.save, overworld = ow },
                       "FIGHTING_DOJO", "FIGHTINGDOJO_HITMONCHAN_POKE_BALL")
  U.wait(3)
  ow:interact()
  check(sawText("What goes around"),
    "#2251: the (5,0) poster prints 'What goes around comes around!'")
  U.shot(game, DIR .. "/2251_01_what_goes_around_poster.png")
  mashUntil(function() return game.stack:top() == ow end)

  for i, sx in ipairs({ 3, 6 }) do
    ow = resetDojo(sx, 10, "up", {})
    ow:interact()
    check(sawText("FIGHTING DOJO"),
      "#2251: the statue at (" .. sx .. ",9) prints 'FIGHTING DOJO'")
    U.shot(game, DIR .. "/2251_0" .. (i + 1) .. "_statue_" .. sx .. "_fighting_dojo.png")
    mashUntil(function() return game.stack:top() == ow end)
  end

  ------------------------------------------------------------------
  U.log("fighting_dojo_bug197_test: failures =", #failures)
  for _, m in ipairs(failures) do U.log("  -", m) end
  if #failures == 0 then
    U.log("PASS fighting_dojo_bug197_test")
    love.event.quit(0)
  else
    U.log("FAIL fighting_dojo_bug197_test")
    love.event.quit(1)
  end
end
