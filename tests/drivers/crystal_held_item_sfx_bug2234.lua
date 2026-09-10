-- ../pokecrystal/engine/pokemon/party_menu.asm:694
-- ../pokecrystal/engine/pokemon/mon_submenu.asm:50
-- ../pokecrystal/engine/pokemon/mon_menu.asm:279
-- ../pokecrystal/home/menu.asm:381
--   POKEPORT_VERSION=crystal POKEPORT_IDENTITY=crystal-sep04 POKEPORT_TOUCH=0 \
--     POKEPORT_SHOT_DIR=<dir> \
--     POKEPORT_DRIVER=tests/drivers/crystal_held_item_sfx_bug2234.lua love .
local U = require("tests.drivers.util")
local Sound = require("src.core.Sound")
local Typer = require("src.ui.gen2.Typer")

local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/pokeport-shots"

return function(game)
  local fails = 0
  local function say(line) print("[2234] " .. line) end
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

  local clicks, played = 0, {}
  local realPlay = Sound.play
  Sound.play = function(data, name, ...)
    played[#played + 1] = name
    if name == "Sfx_ReadText2" then clicks = clicks + 1 end
    return realPlay(data, name, ...)
  end

  U.wait(45)
  local world = game.world
  if not ok(world and world.map, "the crystal world booted") then finish() end

  local Mon = require("src.battle.gen2.Mon")
  local Bag = require("src.inventory.Bag")
  local save = game.save
  save.party = { Mon.new(game.data, "CYNDAQUIL", 12) }
  save.party[1].item = "BERRY"
  ok(Bag.add(save, "POTION", 1, game.data), "a POTION is in the bag")
  if save.options then save.options.textSpeed = "MID" end

  tap("start")
  local menu = top()
  if not ok(menu and menu.screenId == "Gen2StartMenu", "START opened the menu") then
    finish()
  end
  for _ = 1, 10 do
    if menu.list:current().value == "pokemon" then break end
    tap("down")
  end
  tap("a")
  if not ok(waitFor("Gen2PartyMenu", 90), "POKeMON opened the party list") then
    finish()
  end
  local party = top()
  party.index = 1
  local before = clicks
  tap("a")
  ok(clicks == before + 1, "A on a party row clicks (" .. (clicks - before) .. ")")
  if not ok(party.submenu ~= nil, "and opened the mon submenu") then finish() end
  for i, item in ipairs(party.submenu.items) do
    if item.id == "ITEM" then party.submenu.index = i end
  end
  before = clicks
  tap("a")
  ok(clicks == before + 1, "A on ITEM clicks (" .. (clicks - before) .. ")")
  if not ok(waitFor("Gen2HeldItemMenu", 30), "ITEM opened GIVE / TAKE") then
    finish()
  end
  local held = top()
  held.index = 2
  before = clicks
  tap("a", 1)
  ok(clicks == before + 1, "A on TAKE clicks (" .. (clicks - before) .. ")")
  ok(held.typer ~= nil, "the took-item text has a typer")
  ok(Typer.typing(held), "and is still typing a frame later")
  U.shot(game, SHOT_DIR .. "/2234_01_took_berry_mid_type.png")
  ok(waitTyped(held), "the took-item text finished")
  ok(topId() == "Gen2HeldItemMenu", "and waited for the prompt")
  before = clicks
  tap("a")
  ok(clicks == before + 1, "dismissing it clicks (" .. (clicks - before) .. ")")
  ok(save.party[1].item == nil, "the berry left the mon")
  ok(topId() == "Gen2PartyMenu", "back on the party list")
  before = clicks
  tap("b")
  ok(clicks == before + 1, "B out of the list clicks (" .. (clicks - before) .. ")")
  for _ = 1, 30 do
    if topId() ~= "Gen2StartMenu" and topId() ~= "Gen2PartyMenu" then break end
    tap("b")
  end
  ok(top() == game.overworld or topId() == nil or world.map ~= nil,
    "the START menu closed")

  U.wait(30)
  for _ = 1, 5 do
    tap("start", 8)
    if topId() == "Gen2StartMenu" then break end
    U.wait(20)
  end
  menu = top()
  if not ok(menu and menu.screenId == "Gen2StartMenu",
      "START opened the menu again (top: " .. tostring(topId()) .. ")") then
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
  local potionRow
  for i, row in ipairs(pack.rows) do
    if row.id == "POTION" then potionRow = i end
  end
  if not ok(potionRow ~= nil, "the POTION is listed") then finish() end
  pack.index = potionRow
  pack:openSubmenu()
  for i, id in ipairs(pack.submenu.rows) do
    if id == "give" then pack.submenu.index = i end
  end
  tap("a")
  if not ok(waitFor("Gen2PartyMenu", 60), "GIVE asked To which PKMN?") then
    finish()
  end
  party = top()
  party.index = 1
  before = clicks
  tap("a", 1)
  ok(clicks == before + 1, "picking the mon clicks (" .. (clicks - before) .. ")")
  if not ok(waitFor("Gen2HeldItemMenu", 10), "the hold text opened") then finish() end
  held = top()
  ok(held.typer ~= nil, "the hold text has a typer")
  ok(Typer.typing(held), "and is still typing a frame later")
  U.shot(game, SHOT_DIR .. "/2234_02_is_now_holding_mid_type.png")
  ok(waitTyped(held), "the hold text finished")
  before = clicks
  tap("a")
  ok(clicks == before + 1, "dismissing it clicks (" .. (clicks - before) .. ")")
  ok(save.party[1].item == "POTION", "the mon holds the POTION")

  say("sfx played: " .. table.concat(played, ", "))
  Sound.play = realPlay
  finish()
end
