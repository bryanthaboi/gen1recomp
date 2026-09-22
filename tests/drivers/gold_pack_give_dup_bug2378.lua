-- ../pokegold/engine/items/pack.asm:562
-- ../pokegold/engine/pokemon/mon_menu.asm:270
--   POKEPORT_VERSION=gold POKEPORT_IDENTITY=<identity> POKEPORT_TOUCH=0 \
--     POKEPORT_SHOT_DIR=<dir> \
--     POKEPORT_DRIVER=tests/drivers/gold_pack_give_dup_bug2378.lua love .
local U = require("tests.drivers.util")
local Typer = require("src.ui.gen2.Typer")

local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/pokeport-shots"

return function(game)
  local fails = 0
  local function say(line) print("[2378] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
    return cond
  end
  local function finish()
    say(fails == 0 and "all claims passed" or (fails .. " claims failed"))
    love.event.quit(fails == 0 and 0 or 1)
    while true do U.wait(60) end
  end

  local function tap(button, frames)
    game.input.pressQueue[#game.input.pressQueue + 1] = button
    game.input.state[button] = true
    U.wait(2)
    game.input.state[button] = false
    U.wait(frames or 4)
  end
  local function top() return game.stack:top() end
  local function topId() local s = top() return s and s.screenId or nil end
  local function waitFor(id, limit)
    for _ = 1, limit or 120 do
      if topId() == id then return true end
      U.wait(1)
    end
    return false
  end
  local function waitTyped(state, limit)
    for _ = 1, limit or 600 do
      if not Typer.typing(state) then return true end
      U.wait(1)
    end
    return false
  end
  local function drainHeld(held)
    for _ = 1, 8 do
      if top() ~= held or not (held.message or held.confirm) then return end
      waitTyped(held)
      tap("a", 6)
    end
  end

  U.wait(60)
  local world = game.world
  if not ok(world and world.map, "the gold world booted") then finish() end
  world:warpToMapId("NEW_BARK_TOWN", 13, 6, "down")
  U.wait(60)

  local Mon = require("src.battle.gen2.Mon")
  local save = game.save
  save.party = { Mon.new(game.data, "CYNDAQUIL", 12),
    Mon.new(game.data, "TOTODILE", 12) }
  save.party[1].item = nil
  save.party[2].item = nil
  save.inventory.BERRY = nil
  local Bag = require("src.inventory.Bag")
  ok(Bag.add(save, "BERRY", 1, game.data), "one BERRY is in the bag")
  if save.options then save.options.textSpeed = "FAST" end

  local function berries()
    local n = save.inventory.BERRY or 0
    for _, mon in ipairs(save.party) do
      if mon.item == "BERRY" then n = n + 1 end
    end
    return n
  end

  tap("start", 8)
  local menu = top()
  if not ok(menu and menu.screenId == "Gen2StartMenu", "START opened the menu") then
    finish()
  end
  for _ = 1, 10 do
    if menu.list:current().value == "pack" then break end
    tap("down")
  end
  tap("a")
  if not ok(waitFor("Gen2PackMenu", 90), "PACK opened") then finish() end
  local pack = top()
  for _ = 1, 4 do
    if pack:pocket().id == "ITEM" then break end
    tap("right")
  end
  ok(pack:pocket().id == "ITEM", "on the ITEM pocket")

  local function giveBerryTo(slot)
    local rowIndex
    for i, row in ipairs(pack.rows) do
      if row.id == "BERRY" then rowIndex = i end
    end
    if not ok(rowIndex ~= nil, "the BERRY is listed") then finish() end
    pack.index = rowIndex
    pack:openSubmenu()
    for i, id in ipairs(pack.submenu.rows) do
      if id == "give" then pack.submenu.index = i end
    end
    tap("a")
    if not ok(waitFor("Gen2PartyMenu", 60), "GIVE asked To which PKMN?") then
      finish()
    end
    local party = top()
    party.index = slot
    tap("a", 1)
    if not ok(waitFor("Gen2HeldItemMenu", 10), "the give text opened") then
      finish()
    end
    drainHeld(top())
    U.wait(10)
  end

  giveBerryTo(2)
  ok(save.party[2].item == "BERRY", "slot 2 holds the BERRY")
  ok(topId() == "Gen2PackMenu",
    "empty-hand give lands back on the PACK (top: " .. tostring(topId()) .. ")")
  local listed = false
  for _, row in ipairs(pack.rows) do
    if row.id == "BERRY" then listed = true end
  end
  ok(not listed, "and the PACK no longer lists a BERRY")
  ok(berries() == 1, "one BERRY in total (" .. berries() .. ")")
  U.shot(game, SHOT_DIR .. "/2378_01_pack_back_after_give.png")

  save.party[1].item = "BERRY"
  Bag.add(save, "BERRY", 1, game.data)
  pack:rebuild()
  local before = berries()
  giveBerryTo(1)
  ok(topId() == "Gen2PackMenu",
    "swap give lands back on the PACK (top: " .. tostring(topId()) .. ")")
  ok(save.party[1].item == "BERRY", "slot 1 still holds a BERRY")
  ok((save.inventory.BERRY or 0) == 1, "the bag got the old BERRY back")
  ok(berries() == before, "no BERRY was minted (" .. berries() .. " of "
    .. before .. ")")
  U.shot(game, SHOT_DIR .. "/2378_02_pack_back_after_swap.png")

  for _ = 1, 10 do
    if top() == game.overworld or topId() == nil then break end
    tap("b", 8)
  end
  finish()
end
