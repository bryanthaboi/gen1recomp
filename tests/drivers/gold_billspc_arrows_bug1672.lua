-- #1672: Bill's PC MOVE screen -- the box-name arrows.
--
--   POKEPORT_IDENTITY=gold-dev POKEPORT_GAME=gold POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/gold_billspc_arrows_bug1672.lua \
--     perl -e 'alarm 420; exec @ARGV' \
--     python3 -c "import pty; pty.spawn(['love','.'])"
--   POKEPORT_SHOT_DIR=/tmp/gold-bug1672-arrows   (default)
--
-- BillsPC_MoveMonWOMail_BoxNameAndArrows writes $5f at hlcoord 8, 1 and $5e at
-- hlcoord 19, 1 (engine/pokemon/bills_pc.asm:957-963), replacing the box-name
-- Textbox's own side borders.  Only _MovePKMNWithoutMail calls it: .Init (:545)
-- and .PrepInsertCursor (:698).  The withdraw (:299) and deposit (:56) inits
-- call bare BillsPC_BoxName (:965) and are the negative controls here.
--
-- What to look for in each shot: a solid LEFT-pointing triangle in the left
-- border of the name box and a solid RIGHT-pointing one in the right border,
-- both level with the name, on every move-mode shot and on neither of the last
-- two.  Getting them the wrong way round is the failure this exists to catch.
--
-- The run ends with the MOVE screen open so a human takes the controls there.
local U = require("tests.drivers.util")

local Boxes = require("src.core.gen2.Boxes")
local Mon = require("src.battle.gen2.Mon")
local Screens = require("src.ui.Screens")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-bug1672-arrows"

  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    U.wait(2)
    game.input.state[button] = false
    U.wait(frames or 6)
  end

  U.wait(45)
  assert(game.world and game.world.map, "gold world did not boot")
  local save, data = game.save, game.data

  local function mon(species, level) return Mon.new(data, species, level) end

  -- IsAnyMonHoldingMail refuses the whole screen (src/ui/gen2/PcMenu.lua:303),
  -- so the seeded party carries no mail.
  save.party = {}
  for _, species in ipairs({ "CYNDAQUIL", "PIDGEY", "SENTRET" }) do
    save.party[#save.party + 1] = mon(species, 12)
  end
  local stored = Boxes.box(save, 1)
  for i = #stored, 1, -1 do stored[i] = nil end
  for i, species in ipairs({ "GEODUDE", "ZUBAT", "RATTATA" }) do
    stored[i] = mon(species, 10 + i)
  end
  Boxes.rename(save, 1, "GRASS")
  save.currentBox = 1

  local function openBox(mode)
    Screens.push(game, "Gen2BoxMenu", {
      save = save, mode = mode,
      onClose = function() game.stack:pop() end,
    })
    U.wait(8)
    return game.stack:top()
  end

  local function close()
    while game.stack:top() and game.stack:top().submenuRows do
      game.stack:pop()
    end
    U.wait(4)
  end

  -- ---- 1. the move list on a renamed box -----------------------------------
  local menu = openBox("move")
  U.log("01 move, box GRASS:", "want both arrows flanking GRASS on row 1")
  U.shot(game, out .. "/01-move-box.png")

  -- ---- 2. LEFT onto the PARTY ----------------------------------------------
  -- BillsPC_BoxName's `.party` arm; only the move screen ever loads box 0.
  tap("left")
  U.log("02 move, PARTY:", "boxIndex " .. tostring(menu.boxIndex) ..
    ", want 0 and both arrows still up")
  U.shot(game, out .. "/02-move-party.png")
  tap("right")

  -- ---- 3. the MOVE / STATS / CANCEL submenu --------------------------------
  tap("a")
  U.log("03 submenu:", "phase " .. tostring(menu.phase) ..
    ", want submenu and both arrows still up")
  U.shot(game, out .. "/03-move-submenu.png")

  -- ---- 4. the insert cursor (.PrepInsertCursor rewrites them) --------------
  tap("a", 10)
  U.log("04 insert:", "phase " .. tostring(menu.phase) ..
    ", want insert and both arrows still up")
  U.shot(game, out .. "/04-move-insert.png")
  close()

  -- ---- 5/6. the negative controls ------------------------------------------
  openBox("withdraw")
  U.log("05 withdraw:", "want plain border tiles, NO arrows")
  U.shot(game, out .. "/05-withdraw-none.png")
  close()

  openBox("deposit")
  U.log("06 deposit:", "want plain border tiles, NO arrows")
  U.shot(game, out .. "/06-deposit-none.png")
  close()

  openBox("move")
  U.log("done -- the MOVE screen is open; the controls are yours")
end
