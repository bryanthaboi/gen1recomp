-- Parity test, Bill's House PC + Route25ToggleBillsScript (#120).
--
-- asm sources:
--   engine/events/hidden_events/bills_house_pc.asm (BillsHousePC /
--     BillsHousePokemonList: after EVENT_LEFT_BILLS_HOUSE_AFTER_HELPING
--     the PC opens EEVEE/FLAREON/JOLTEON/VAPOREON; before that the
--     teleporter monitor text or cell-separator cutscene)
--   scripts/Route25.asm (Route25ToggleBillsScript: first Route 25 load
--     after EVENT_MET_BILL_2 + EVENT_GOT_SS_TICKET sets
--     EVENT_LEFT_BILLS_HOUSE_AFTER_HELPING, hides BILL1 / nugget-bridge
--     guy, shows BILL2; mid-quest leave resets the separator flag)
--
-- Self-contained: run via `luajit tests/parity_bills_pc.lua`; also
-- dofile'd by tests/run_tests.lua's aggregator.
package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end
local Data = require("src.core.Data")
if not (Data.maps and Data.maps.PALLET_TOWN) then Data:load() end
local S = require("tests.harness").suite("parity bills pc")
local check, eq = S.check, S.eq

local OW = require("src.world.OverworldController")
local SaveData = require("src.core.SaveData")
local story = require("data.scripts.story")

local function getUpvalue(fn, name)
  local i = 1
  while true do
    local n, v = debug.getupvalue(fn, i)
    if not n then return nil end
    if n == name then return v end
    i = i + 1
  end
end
local function setUpvalue(fn, name, val)
  local i = 1
  while true do
    local n = debug.getupvalue(fn, i)
    if not n then return false end
    if n == name then debug.setupvalue(fn, i, val); return true end
    i = i + 1
  end
end

local pushed = {}
local stackStub = {
  push = function(_, item)
    pushed[#pushed + 1] = item
  end,
}
local textBoxStub = {
  new = function(_, text, onDone)
    local box = { kind = "text", text = text, onDone = onDone }
    if onDone then onDone() end
    return box
  end,
}
local menuStub = {
  new = function(_, items, opts)
    return { kind = "menu", items = items, opts = opts or {} }
  end,
}
local screensStub = {
  push = function(_, id, species)
    pushed[#pushed + 1] = { kind = "screen", id = id, species = species }
  end,
}

local fakeGame = {
  data = Data,
  save = SaveData.newGame(),
  stack = stackStub,
}
check(setUpvalue(OW.billsHousePC, "TextBox", textBoxStub), "TextBox upvalue")
check(setUpvalue(OW.billsHousePC, "Game", fakeGame), "Game upvalue for PC")
-- Screens is only referenced from billsHousePokemonList
check(setUpvalue(OW.billsHousePokemonList, "Screens", screensStub),
      "Screens upvalue on pokemon list")
check(setUpvalue(OW.billsHousePokemonList, "Game", fakeGame),
      "Game upvalue on pokemon list")
check(setUpvalue(OW.billsHousePokemonList, "TextBox", textBoxStub),
      "TextBox upvalue on pokemon list")

-- Menu is required inside billsHousePokemonList; stub via package.loaded
local realMenu = package.loaded["src.ui.Menu"]
package.loaded["src.ui.Menu"] = menuStub

local queued
local fakeSelf = setmetatable({
  queueScript = function(_, script, extra) queued = { script, extra } end,
  billsHouseBillExits = function() end,
}, { __index = OW })

local function resetFlags()
  fakeGame.save = SaveData.newGame()
  setUpvalue(OW.billsHousePC, "Game", fakeGame)
  pushed = {}
end

local function lastPush()
  return pushed[#pushed]
end

local function runPC()
  pushed = {}
  fakeSelf:billsHousePC()
end

-- === 1) default: teleporter monitor text ===
resetFlags()
runPC()
eq(lastPush() and lastPush().kind, "text", "default PC is a text box")
check(tostring(lastPush().text):find("TELEPORTER", 1, true)
      or tostring(lastPush().text):find("displayed on the", 1, true),
      "default PC shows monitor text")

-- === 2) Bill in machine, separator not used yet: initiated text ===
resetFlags()
fakeGame.save.flags.EVENT_BILL_SAID_USE_CELL_SEPARATOR = true
local musicStopped = false
local realMusic = package.loaded["src.core.Music"]
package.loaded["src.core.Music"] = {
  stop = function() musicStopped = true end,
  playMap = function() end,
}
local realSound = package.loaded["src.core.Sound"]
package.loaded["src.core.Sound"] = {
  play = function() end,
  playCry = function() end,
}
queued = nil
runPC()
check(musicStopped, "cell separator stops map music")
check(tostring(lastPush().text):find("Cell", 1, true)
      or tostring(lastPush().text):find("TELEPORTER", 1, true),
      "separator path prints initiated text")

-- bills_house_pc.asm:14-40 plus BillsHouseInitiatedText's text_asm at :51-63:
-- 268 delay frames, and every PlaySound is followed by WaitForSoundToFinish
-- before the next delay starts.
local wantSeparator = {
  { "wait", 16 },
  { "play_sound", "Switch" }, { "wait_sound" },
  { "wait", 60 },
  { "wait", 32 },
  { "play_sound", "Tink" }, { "wait_sound" },
  { "wait", 80 },
  { "play_sound", "Shrink" }, { "wait_sound" },
  { "wait", 48 },
  { "play_sound", "Tink" }, { "wait_sound" },
  { "wait", 32 },
  { "play_sound", "Get_Item1" }, { "wait_sound" },
}
check(queued ~= nil, "the separator queues its cutscene script")
local gotRows, delayFrames = {}, 0
for _, row in ipairs(queued and queued[1] or {}) do
  gotRows[#gotRows + 1] = table.concat({ tostring(row[1]), tostring(row[2]) }, " ")
  if row[1] == "wait" then delayFrames = delayFrames + row[2] end
end
local wantRows = {}
for _, row in ipairs(wantSeparator) do
  wantRows[#wantRows + 1] = table.concat({ tostring(row[1]), tostring(row[2]) }, " ")
end
eq(table.concat(gotRows, " | "), table.concat(wantRows, " | "),
   "the separator chain matches bills_house_pc.asm delay for delay")
eq(delayFrames, 268, "268 delay frames, DelayFrames call for DelayFrames call")
check(not fakeGame.save.flags.EVENT_USED_CELL_SEPARATOR_ON_BILL,
      "SetEvent waits for the chain, not the text box")
queued[2].onDone()
check(fakeGame.save.flags.EVENT_USED_CELL_SEPARATOR_ON_BILL,
      "separator path sets EVENT_USED_CELL_SEPARATOR_ON_BILL")

-- === 3) after separator, before leaving: monitor text again ===
resetFlags()
fakeGame.save.flags.EVENT_BILL_SAID_USE_CELL_SEPARATOR = true
fakeGame.save.flags.EVENT_USED_CELL_SEPARATOR_ON_BILL = true
fakeGame.save.flags.EVENT_MET_BILL = true
runPC()
check(tostring(lastPush().text):find("TELEPORTER", 1, true)
      or tostring(lastPush().text):find("displayed on the", 1, true),
      "post-separator pre-leave PC shows monitor text")

-- === 4) after leaving: Eevee collection menu ===
resetFlags()
fakeGame.save.flags.EVENT_LEFT_BILLS_HOUSE_AFTER_HELPING = true
runPC()
local menu
for _, p in ipairs(pushed) do
  if p.kind == "menu" then menu = p break end
end
check(menu ~= nil, "post-leave PC opens a menu")
local labels = {}
for _, item in ipairs(menu.items) do labels[#labels + 1] = item.label end
eq(table.concat(labels, ","), "EEVEE,FLAREON,JOLTEON,VAPOREON,CANCEL",
   "Eevee collection lists the four mons + CANCEL")

-- selecting EEVEE marks seen and opens DexEntryMenu without closing list
fakeGame.save.pokedex = { seen = {}, owned = {} }
menu.items[1].onSelect()
check(fakeGame.save.pokedex.seen.EEVEE, "viewing marks EEVEE seen")
local dexPush
for i = #pushed, 1, -1 do
  if pushed[i].kind == "screen" then dexPush = pushed[i] break end
end
eq(dexPush and dexPush.id, "DexEntryMenu", "selection opens DexEntryMenu")
eq(dexPush and dexPush.species, "EEVEE", "DexEntryMenu gets EEVEE")
check(menu.items[1].keepOpen, "dex pick keeps the list open")

-- === 5) Route25ToggleBillsScript ===
local toggles = {}
local Commands = require("src.script.Commands")
local realHide, realShow = Commands.hide_object, Commands.show_object
Commands.hide_object = function(_, mapId, name)
  toggles[mapId .. ":" .. name] = false
end
Commands.show_object = function(_, mapId, name)
  toggles[mapId .. ":" .. name] = true
end

local function runRoute25(flags)
  toggles = {}
  local save = SaveData.newGame()
  for k, v in pairs(flags) do save.flags[k] = v end
  story.ROUTE_25.onEnter({ save = save }, {})
  return save.flags, toggles
end

local f, t = runRoute25({})
check(not f.EVENT_LEFT_BILLS_HOUSE_AFTER_HELPING,
      "no leave flag before meeting Bill")
check(t["BILLS_HOUSE:BILLSHOUSE_BILL_POKEMON"] == true,
      "mid-quest leave restores monster Bill")
check(f.EVENT_BILL_SAID_USE_CELL_SEPARATOR == nil,
      "mid-quest leave clears separator arming flag")

f, t = runRoute25({ EVENT_MET_BILL_2 = true })
check(not f.EVENT_LEFT_BILLS_HOUSE_AFTER_HELPING,
      "MET_BILL_2 without ticket does not arm leave flag")

f, t = runRoute25({
  EVENT_MET_BILL_2 = true,
  EVENT_GOT_SS_TICKET = true,
})
check(f.EVENT_LEFT_BILLS_HOUSE_AFTER_HELPING,
      "ticket + MET_BILL_2 arms EVENT_LEFT_BILLS_HOUSE_AFTER_HELPING")
eq(t["BILLS_HOUSE:BILLSHOUSE_BILL1"], false, "hides SS-Ticket Bill")
eq(t["BILLS_HOUSE:BILLSHOUSE_BILL2"], true, "shows rare-POKéMON Bill")
eq(t["ROUTE_24:ROUTE24_COOLTRAINER_M1"], false, "hides nugget-bridge guy")

f, t = runRoute25({
  EVENT_LEFT_BILLS_HOUSE_AFTER_HELPING = true,
  EVENT_MET_BILL_2 = true,
  EVENT_GOT_SS_TICKET = true,
})
eq(next(t), nil, "already-left Route 25 enter is a no-op")

-- pokeyellow scripts/BillsHouse.asm:211 and :232; pokered's
-- BillsHouseCleanupScript (scripts/BillsHouse.asm:96) has neither state.
local GameVersion = require("src.core.GameVersion")
local realVersion = GameVersion.current

local function newScene()
  local said
  local self = setmetatable({
    map = { id = "BILLS_HOUSE", def = { label = "BillsHouse" } },
    player = { cellX = 1, cellY = 5, facing = "up" },
    scriptMoves = {},
    showMapText = function(_, textConst, npc)
      said = { textConst = textConst, npc = npc }
    end,
  }, { __index = OW })
  return self, function() return said end
end

local function drain(s)
  local guard = 0
  while #s.scriptMoves > 0 and guard < 32 do
    local mv = table.remove(s.scriptMoves, 1)
    if mv.onDone then mv.onDone() end
    guard = guard + 1
  end
end

GameVersion.current = "red"
local scene, saidOf = newScene()
scene:billsHouseSSTicketScene({ facing = "left" })
eq(#scene.scriptMoves, 0, "Red/Blue queue no forced walk after Bill exits")
eq(saidOf(), nil, "Red/Blue never auto-open the SS Ticket text")

GameVersion.current = "yellow"
scene, saidOf = newScene()
local billNpc = { facing = "left", def = { name = "BILLSHOUSE_BILL1" } }
scene:billsHouseSSTicketScene(billNpc)
eq(#scene.scriptMoves, 1, "Yellow queues the simulated walk")
eq(scene.scriptMoves[1].entity, scene.player, "the forced walk moves the player")
eq(scene.scriptMoves[1].dir, "right", "RLE_1e219 is PAD_RIGHT")
eq(scene.scriptMoves[1].remaining, 3, "RLE_1e219 runs three steps")
eq(scene.scriptMoves[1].collide, nil, "the simulated walk is unconditional")
eq(saidOf(), nil, "the text waits for the walk to finish")
drain(scene)
eq(scene.player.facing, "up", "player ends facing up (SPRITE_FACING_UP)")
eq(billNpc.facing, "down", "BILL1 is turned down before the text")
eq(saidOf() and saidOf().textConst, "TEXT_BILLSHOUSE_BILL_SS_TICKET",
   "the ticket text opens with no A press")
eq(saidOf() and saidOf().npc, billNpc, "the text runs as BILL1")

scene, saidOf = newScene()
scene:billsHouseSSTicketScene(nil)
eq(#scene.scriptMoves, 0, "no walk without BILL1")
eq(saidOf() and saidOf().textConst, "TEXT_BILLSHOUSE_BILL_SS_TICKET",
   "the ticket text still opens without BILL1")

package.loaded["src.core.Music"] = { stop = function() end, playMap = function() end }
local ticketBill = "unset"
local exitSelf = setmetatable({
  map = { id = "BILLS_HOUSE", def = { label = "BillsHouse" } },
  player = { cellX = 1, cellY = 5, facing = "up" },
  scriptMoves = {},
  npcs = { { def = { name = "BILLSHOUSE_BILL1" }, facing = "down" } },
  billsHouseSSTicketScene = function(_, b) ticketBill = b end,
}, { __index = OW })
fakeGame.save = SaveData.newGame()
setUpvalue(OW.billsHousePC, "Game", fakeGame)
exitSelf:billsHouseBillExits()
drain(exitSelf)
check(fakeGame.save.flags.EVENT_MET_BILL_2, "Bill's exit sets EVENT_MET_BILL_2")
eq(ticketBill, exitSelf.npcs[1], "the exit walk hands BILL1 to the ticket scene")

GameVersion.current = realVersion

Commands.hide_object = realHide
Commands.show_object = realShow
package.loaded["src.ui.Menu"] = realMenu
package.loaded["src.core.Music"] = realMusic
package.loaded["src.core.Sound"] = realSound

S.finish()
