-- The Pokecenter heal machine and the POKeMART shelf, in the running game.
--
--   POKEPORT_IDENTITY=goldshopfix POKEPORT_GAME=gold POKEPORT_GOLD_HOUR=10 \
--     POKEPORT_DRIVER=tests/drivers/gold_heal_mart_shots.lua \
--     perl -e 'alarm 300; exec @ARGV' \
--     python3 -c "import pty; pty.spawn(['love','.'])"
--
-- Two things this is watching for:
--   * PokecenterNurseScript's `special HealMachineAnim` used to be a bare
--     (wrong) sfx: the balls, the flashing and MUSIC_HEAL all have to appear,
--     ON the machine at the counter's left end, and the nurse's next line
--     must wait for the last flash
--   * a mart clerk's shelf came from data/generated/marts.lua being absent,
--     so every shop opened empty: Cherrygrove must stock its four items with
--     ItemAttributes prices and a purchase must move money and the PACK
--
-- Shots land in /tmp/gold-heal-mart.
local U = require("tests.drivers.util")
local Typer = require("src.ui.gen2.Typer")

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-heal-mart"
  local fails = 0

  local function ok(cond, msg)
    if cond then print("[healmart] ok   " .. msg)
    else fails = fails + 1 print("[healmart] FAIL " .. msg) end
    return cond
  end

  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    U.wait(2)
    game.input.state[button] = false
    U.wait(frames or 4)
  end

  local function waitFor(pred, frames)
    for _ = 1, frames or 600 do
      if pred() then return true end
      U.wait(1)
    end
    return pred() and true or false
  end

  U.wait(45)
  local w = game.world
  assert(w and w.map, "gold world did not boot")
  local save = game.save

  -- A party worth three balls on the machine, all hurt so the heal is real.
  local Mon = require("src.battle.gen2.Mon")
  save.party = {}
  for _, species in ipairs({ "CYNDAQUIL", "PIDGEY", "RATTATA" }) do
    local mon = Mon.new(game.data, species, 10)
    mon.hp = 1
    save.party[#save.party + 1] = mon
  end
  save.player = save.player or {}
  save.player.money = 5000

  -- ------------------------------------------------------------- the nurse
  w:setMap("CHERRYGROVE_POKECENTER_1F", 3, 3, "up")
  U.wait(20)
  U.shot(game, out .. "/00-pokecenter.png")

  -- Talk across the counter, then hold A through the greeting and the
  -- yes/no (YES is the default), stopping the moment the machine starts.
  tap("a", 6)
  local sawAnim, sawBalls, sawFlash, sawJingle = false, 0, false, false
  local Music = require("src.core.Music")
  for _ = 1, 60 * 30 do
    local ha = w.healAnim
    if ha then
      sawAnim = true
      if ha.lit > sawBalls then
        sawBalls = ha.lit
        U.still(game, ("%s/01-ball-%d.png"):format(out, ha.lit))
      end
      if ha.phase == "flash" and not sawFlash and ha.rotation ~= 0 then
        sawFlash = true
        U.still(game, out .. "/02-flash.png")
      end
      if Music.current() == "Music_HealPokemon" then sawJingle = true end
      U.wait(1)
    elseif sawAnim then
      break
    else
      tap("a", 2)
    end
  end
  ok(sawAnim, "the heal machine animation ran")
  ok(sawBalls == 3, "one ball per party member landed (" .. sawBalls .. ")")
  ok(sawFlash, "the machine flashed its palette")
  ok(sawJingle, "MUSIC_HEAL played over the flashing")
  U.shot(game, out .. "/03-after-flash.png")

  -- The script is still mid-conversation ("thank you for waiting"); page out.
  for _ = 1, 40 do
    if not w:busy() then break end
    tap("a", 4)
  end
  local healed = true
  for _, mon in ipairs(save.party) do
    if (mon.hp or 0) < (mon.maxHp or 1) then healed = false end
  end
  ok(healed, "the party left the counter at full HP")
  U.shot(game, out .. "/04-healed.png")

  -- -------------------------------------------------------------- the mart
  w:setMap("CHERRYGROVE_MART", 2, 3, "left")
  U.wait(20)
  tap("a", 6)
  -- Page the welcome line until the BUY/SELL/QUIT screen owns the stack.
  local mart
  for _ = 1, 120 do
    local top = game.stack and game.stack:top()
    if top and top.martType then mart = top break end
    tap("a", 3)
  end
  if not ok(mart ~= nil, "the clerk opened the mart screen") then
    U.shot(game, out .. "/05-no-mart.png")
    print(("[healmart] %d failures"):format(fails))
    love.event.quit(fails == 0 and 0 or 1)
    return
  end
  U.shot(game, out .. "/05-mart-top.png")

  ok(#mart.entries == 4, "Cherrygrove stocks four items ("
    .. #mart.entries .. ")")
  ok(mart.entries[1] and mart.entries[1].id == "POTION"
    and mart.entries[1].price == 300,
    "POTION at the ROM's own 300 leads the shelf")

  tap("a", 2) -- BUY
  ok(waitFor(function() return mart.phase == "buy" end),
    "BUY opened the shelf")
  U.shot(game, out .. "/06-buy-list.png")
  tap("a", 2) -- pick POTION -> quantity
  ok(waitFor(function() return mart.phase == "buyQuantity" end),
    "POTION opened the quantity box")
  tap("up", 2) -- x2
  ok(waitFor(function() return mart.qty == 2 end), "the quantity stepped to 2")
  U.shot(game, out .. "/07-quantity.png")
  tap("a", 2) -- how many -> confirm
  local function onYesNo()
    local c = mart.confirm
    return c and c.page >= #c.pages and not Typer.typing(mart)
  end
  for _ = 1, 20 do
    if onYesNo() or not mart.confirm then break end
    waitFor(function() return not Typer.typing(mart) end)
    if onYesNo() then break end
    tap("a", 2)
  end
  ok(onYesNo() and mart.confirm.choice == 1,
    "the final-price line sits on its YES/NO with YES lit")
  U.shot(game, out .. "/08-confirm.png")
  tap("a", 2) -- YES
  ok(waitFor(function()
    return mart.message ~= nil and not Typer.typing(mart)
  end), "the clerk's here-you-are line finished printing")
  U.shot(game, out .. "/09-bought.png")
  for _ = 1, 20 do
    if not mart.message then break end
    waitFor(function() return not Typer.typing(mart) end)
    tap("a", 2)
  end

  ok((save.inventory and save.inventory.POTION) == 2,
    "two POTIONs landed in the PACK")
  ok(save.player.money == 5000 - 600,
    "the till took 600 (money " .. tostring(save.player.money) .. ")")

  -- Leave: B out of the list, then QUIT + the come-again line.
  tap("b", 2)
  ok(waitFor(function() return mart.phase == "top" end),
    "B left the shelf for BUY/SELL/QUIT")
  tap("b", 2)
  for _ = 1, 20 do
    if game.stack:top() ~= mart then break end
    waitFor(function() return not Typer.typing(mart) end)
    tap("a", 2)
  end
  ok(waitFor(function() return game.stack:top() ~= mart end),
    "the come-again line closed the mart")
  U.shot(game, out .. "/10-outside.png")

  print(("[healmart] %d failures"):format(fails))
  love.event.quit(fails == 0 and 0 or 1)
end
