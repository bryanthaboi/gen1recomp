-- #1556: the field jingles that ride a TX_SOUND at the end of a string --
-- RARE CANDY's level-up, "X learned MOVE!", the trophy -- plus the TM/HM
-- refusals, which are `call PlaySFX` next to the message instead.
--
--   POKEPORT_IDENTITY=gold-dev POKEPORT_GAME=gold POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/gold_bug1556_fanfare.lua \
--     perl -e 'alarm 420; exec @ARGV' \
--     python3 -c "import pty; pty.spawn(['love','.'])"
--   POKEPORT_SHOT_DIR=/tmp/gold-bug1556-fanfare   (default)
--
-- The one deliberate SILENCE is moment 4: TeachTMHM's `.compatible` arm is
-- `callfar KnowsMove / jr c, .nope` (engine/items/tmhm.asm:139-140) with no
-- PlaySFX at all, so "X already knows MOVE!" must stay mute.  Only the
-- INCOMPATIBLE arm rings (:131).
--
-- The box is supposed to HOLD for the fanfare before it takes a button:
-- TextCommand_SOUND is PlaySFX then WaitSFX (home/text.asm), which
-- TextBox.soundOpts models with auto.wait.
local U = require("tests.drivers.util")

local Mon = require("src.battle.gen2.Mon")
local PackMenu = require("src.ui.gen2.PackMenu")
local Sound = require("src.core.Sound")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-bug1556-fanfare"

  local heard = {}
  local realPlay = Sound.play
  Sound.play = function(data, name)
    heard[#heard + 1] = name
    return realPlay(data, name)
  end
  local function reset() heard = {} end
  local function report(label, want)
    U.log(label, #heard > 0 and table.concat(heard, ", ") or "(silence)")
    U.log("   want:", want)
  end

  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    U.wait(2)
    game.input.state[button] = false
    U.wait(frames or 6)
  end

  -- TextCommand_SOUND rings when the box FINISHES printing (home/text.asm),
  -- so a report taken mid-print reads as silence.
  local function awaitSfx(name, frames)
    for _ = 1, (frames or 90) do
      for _, n in ipairs(heard) do if n == name then return true end end
      U.wait(2)
    end
    return false
  end

  U.wait(45)
  local w = game.world
  assert(w and w.map, "gold world did not boot")
  local save, data = game.save, game.data

  local SPECIES = "CYNDAQUIL"
  local def = data.pokemon and data.pokemon[SPECIES]
  assert(def, "the cache carries no " .. SPECIES)

  -- Which TMs this species may and may not learn, straight off its BASE_TMHM.
  local canLearn, cannotLearn = nil, nil
  local allowed = {}
  for _, moveId in ipairs(def.tmhm or {}) do allowed[moveId] = true end
  local tmIds = {}
  for itemId, item in pairs(data.items or {}) do
    if type(item) == "table" and item.teaches
        and tostring(itemId):sub(1, 3) == "TM_" then
      tmIds[#tmIds + 1] = itemId
    end
  end
  table.sort(tmIds)
  for _, itemId in ipairs(tmIds) do
    if allowed[data.items[itemId].teaches] then
      canLearn = canLearn or itemId
    else
      cannotLearn = cannotLearn or itemId
    end
  end
  U.log("TM that fits:", tostring(canLearn),
        "-- TM that does not:", tostring(cannotLearn))

  local function seed()
    local mon = Mon.new(data, SPECIES, 12)
    save.party = { mon }
    return mon
  end

  local function openPack()
    local pack = PackMenu.new(game, {
      save = save, world = w, onClose = function() end })
    game.stack:push(pack)
    U.wait(6)
    return pack
  end

  local field = game.overworld or game.stack:top()
  local function popToField()
    for _ = 1, 12 do
      if game.stack:top() == field or not game.stack:top() then break end
      game.stack:pop()
      U.wait(2)
    end
  end

  -- ---- 1. RARE CANDY: "X grew to level N!" + the level-up fanfare ---------
  local mon = seed()
  save.inventory = { RARE_CANDY = 2 }
  reset()
  game:usePartyItem("RARE_CANDY")
  U.wait(8)
  tap("a", 30)          -- the party pick
  awaitSfx("Sfx_DexFanfare5079")
  report("01 rare candy:", "Sfx_DexFanfare5079 under \"grew to level 13!\"")
  U.shot(game, out .. "/01-rare-candy.png")
  tap("a", 10)
  popToField()

  -- ---- 2. a TM the mon CAN learn: "X learned MOVE!" + the fanfare ---------
  if canLearn then
    mon = seed()
    -- A full moveset diverts into MoveAskForgetText (engine/pokemon/learn.asm:
    -- 110-137); the direct-learn arm is what carries the fanfare.
    while #mon.moves > 2 do table.remove(mon.moves) end
    save.inventory = { [canLearn] = 1 }
    local pack = openPack()
    reset()
    pack:openTeachParty({ id = canLearn })
    U.wait(10)
    tap("a", 30)        -- the party pick
    awaitSfx("Sfx_DexFanfare5079")
    report("02 TM " .. canLearn .. ":",
           "Sfx_DexFanfare5079 under \"learned ...!\"")
    U.shot(game, out .. "/02-tm-learned.png")
    tap("a", 10)
    popToField()
  else
    U.log("SKIP 02 -- no TM in this cache that " .. SPECIES .. " can learn")
  end

  -- ---- 3. a TM the mon CANNOT learn: SFX_WRONG (tmhm.asm:131) ------------
  if cannotLearn then
    mon = seed()
    save.inventory = { [cannotLearn] = 1 }
    local pack = openPack()
    reset()
    pack:openTeachParty({ id = cannotLearn })
    U.wait(10)
    tap("a", 20)
    report("03 TM " .. cannotLearn .. ":",
           "Sfx_Wrong under \"can't learn ...!\"")
    U.shot(game, out .. "/03-tm-refused.png")
    tap("a", 10)
    popToField()
  else
    U.log("SKIP 03 -- every TM in this cache fits " .. SPECIES)
  end

  -- ---- 4. a TM the mon ALREADY KNOWS: SILENCE ----------------------------
  if canLearn then
    mon = seed()
    local moveId = data.items[canLearn].teaches
    mon.moves = mon.moves or {}
    mon.moves[1] = { id = moveId, pp = 10, maxPp = 10 }
    save.inventory = { [canLearn] = 1 }
    local pack = openPack()
    reset()
    pack:openTeachParty({ id = canLearn })
    U.wait(10)
    tap("a", 20)
    report("04 TM already known:", "SILENCE -- KnowsMove has no PlaySFX")
    U.shot(game, out .. "/04-tm-already-known.png")
    tap("a", 10)
    popToField()
  end

  -- ---- 5. a TM on an EGG: SFX_WRONG (tmhm.asm:104-111), a regression -----
  if canLearn then
    mon = seed()
    mon.isEgg = true
    save.inventory = { [canLearn] = 1 }
    local pack = openPack()
    reset()
    pack:openTeachParty({ id = canLearn })
    U.wait(10)
    tap("a", 20)
    report("05 TM on an EGG:", "Sfx_Wrong, and the list stays up")
    U.shot(game, out .. "/05-tm-egg.png")
    tap("b", 6)
    popToField()
  end

  -- ---- 6. the trophy box: _SentTrophyHomeText's fanfare ------------------
  if data.items and data.items.NORMAL_BOX then
    seed()
    save.inventory = { NORMAL_BOX = 1 }
    save.decorations = save.decorations or {}
    local pack = openPack()
    pack:rebuild()
    local row
    for index, entry in ipairs(pack.rows) do
      if entry.id == "NORMAL_BOX" then row = index end
    end
    if row then
      pack.index = row
      reset()
      pack:useSelected()
      U.wait(20)
      report("06 trophy box:", "Sfx_DexFanfare5079 with the trophy line")
      U.shot(game, out .. "/06-trophy.png")
      tap("a", 6)
    else
      U.log("SKIP 06 -- the NORMAL BOX is not in the ITEM pocket here")
    end
    popToField()
  else
    U.log("SKIP 06 -- this cache has no NORMAL_BOX")
  end

  Sound.play = realPlay
  U.log("done -- the controls are yours")
end
