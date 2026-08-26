-- #1556: Bill's PC -- the deposit / withdraw / release cry, and the six
-- SFX_WRONG refusals (engine/pokemon/bills_pc.asm).
--
--   POKEPORT_IDENTITY=gold-dev POKEPORT_GAME=gold POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/gold_bug1556_billspc.lua \
--     perl -e 'alarm 420; exec @ARGV' \
--     python3 -c "import pty; pty.spawn(['love','.'])"
--   POKEPORT_SHOT_DIR=/tmp/gold-bug1556-billspc   (default)
--
-- Eight moments, each seeded, driven through the real screen and screenshotted.
-- The log names what sounded; the ear is the point.  DepositPokemon and
-- TryWithdrawPokemon both `call PlayMonCry` right after RemoveMonFromPartyOrBox
-- (:1762 and :1817), and PlayMonCry itself bails on an EGG
-- (home/pokemon.asm:113), so a boxed egg must move in silence.
--
-- The run ends with the PC screen open so a human takes the controls there.
local U = require("tests.drivers.util")

local Boxes = require("src.core.gen2.Boxes")
local Mon = require("src.battle.gen2.Mon")
local Screens = require("src.ui.Screens")
local Sound = require("src.core.Sound")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-bug1556-billspc"

  local heard = {}
  local realPlay, realCry = Sound.play, Sound.playCry
  Sound.play = function(data, name)
    heard[#heard + 1] = name
    return realPlay(data, name)
  end
  Sound.playCry = function(data, species, clip)
    heard[#heard + 1] = "cry:" .. tostring(species)
    return realCry(data, species, clip)
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

  U.wait(45)
  local w = game.world
  assert(w and w.map, "gold world did not boot")
  local save = game.save
  local data = game.data

  local function mon(species, level)
    return Mon.new(data, species, level)
  end

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

  local function fillBox(index, n, species)
    local box = Boxes.box(save, index)
    for i = #box, 1, -1 do box[i] = nil end
    for _ = 1, n do box[#box + 1] = mon(species or "RATTATA", 5) end
  end

  local function setParty(n, species)
    save.party = {}
    for _ = 1, n do save.party[#save.party + 1] = mon(species or "CYNDAQUIL", 10) end
  end

  save.currentBox = 1

  -- ---- 1. WITHDRAW a mon: its cry ------------------------------------------
  setParty(1)
  fillBox(1, 1, "PIDGEY")
  local menu = openBox("withdraw")
  reset()
  tap("a")              -- the submenu
  tap("a", 12)          -- WITHDRAW
  report("01 withdraw:", "cry:PIDGEY")
  U.shot(game, out .. "/01-withdraw-cry.png")
  tap("a")              -- clear anything on screen
  close()

  -- ---- 2. DEPOSIT it back: the cry again -----------------------------------
  setParty(3)
  save.party[#save.party + 1] = mon("PIDGEY", 5)
  fillBox(1, 0)
  menu = openBox("deposit")
  for _ = 1, 3 do tap("down") end
  reset()
  tap("a")
  tap("a", 12)          -- DEPOSIT
  report("02 deposit:", "cry:PIDGEY")
  U.shot(game, out .. "/02-deposit-cry.png")
  tap("a")
  close()

  -- ---- 3. WITHDRAW into a full party: SFX_WRONG (:1845) --------------------
  setParty(Boxes.PARTY_SIZE)
  fillBox(1, 1, "PIDGEY")
  menu = openBox("withdraw")
  reset()
  tap("a")
  tap("a", 12)
  report("03 withdraw, party full:", "Sfx_Wrong + \"You can't take any more\"")
  U.shot(game, out .. "/03-party-full.png")
  tap("a")
  close()

  -- ---- 4. DEPOSIT into a full box: SFX_WRONG (:1790) ----------------------
  setParty(3)
  fillBox(1, Boxes.MONS_PER_BOX)
  menu = openBox("deposit")
  reset()
  tap("a")
  tap("a", 12)
  report("04 deposit, box full:", "Sfx_Wrong + \"The BOX is full.\"")
  U.shot(game, out .. "/04-box-full.png")
  tap("a")
  close()

  -- ---- 5. DEPOSIT the last healthy mon: SFX_WRONG -------------------------
  setParty(2)
  save.party[2].hp = 0
  fillBox(1, 0)
  menu = openBox("deposit")
  reset()
  tap("a")
  tap("a", 12)
  report("05 deposit, last healthy:", "Sfx_Wrong + \"can't deposit the last\"")
  U.shot(game, out .. "/05-last-mon.png")
  tap("a")
  close()

  -- ---- 6. RELEASE a boxed mon: its cry (:1866) ----------------------------
  setParty(3)
  fillBox(1, 1, "SENTRET")
  menu = openBox("withdraw")
  reset()
  tap("select", 8)      -- RELEASE asks first
  tap("up")             -- the YES/NO box defaults to NO
  tap("a", 14)
  report("06 release:", "cry:SENTRET before \"was released.\"")
  U.shot(game, out .. "/06-release-cry.png")
  tap("a")
  close()

  -- ---- 7. RELEASE an EGG: SFX_WRONG, no cry (:1625) -----------------------
  setParty(3)
  fillBox(1, 0)
  local egg = mon("TOGEPI", 5)
  egg.isEgg = true
  Boxes.box(save, 1)[1] = egg
  menu = openBox("withdraw")
  reset()
  tap("select", 10)
  report("07 release an EGG:", "Sfx_Wrong, and NO cry:TOGEPI")
  U.shot(game, out .. "/07-release-egg.png")
  tap("a")
  close()

  -- ---- 8. MOVE into a full box: SFX_WRONG (:1567) -------------------------
  setParty(3)
  fillBox(1, 1, "HOOTHOOT")
  fillBox(2, Boxes.MONS_PER_BOX)
  menu = openBox("move")
  reset()
  tap("a")              -- the MOVE/STATS/CANCEL submenu
  tap("a", 8)           -- MOVE -> the insert cursor
  tap("right", 8)       -- box 2, which is full
  tap("a", 10)
  report("08 move into a full box:", "Sfx_Wrong + \"There's no room!\"")
  U.shot(game, out .. "/08-no-room.png")

  Sound.play, Sound.playCry = realPlay, realCry
  U.log("done -- the PC is open; the controls are yours")
end
