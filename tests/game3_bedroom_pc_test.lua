#!/usr/bin/env luajit
-- pokefirered/src/player_pc.c:151 BedroomPC, pokefirered/src/player_pc.c:100 gNewGamePCItems

package.path = "./?.lua;./?/init.lua;" .. package.path
package.loaded["src.core.game3.rom_text"] = { plain = function(key) return key end, box = function(key) return key end }

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

package.loaded["src.ui.game3.stack"] = {
  push = function() end,
  pop = function() end,
  busy = function() return false end,
  drawOrder = function() return {} end,
}
package.loaded["src.core.game3.audio"] = {
  playSe = function() end,
  playCry = function() end,
}

print("[test] 1. BedroomPC special id + handler")
local Std = require("src.core.game3.scripting.stdscripts")
check(Std.SPECIAL.BedroomPC == 249, "BedroomPC = 249 (got " .. tostring(Std.SPECIAL.BedroomPC) .. ")")
local Natives = require("src.core.game3.scripting.natives")
check(Natives.ALLOW["special:249"] ~= nil, "special:249 handler registered")

print("[test] 2. special 249 yields into openPc with bedroom opts")
local gotOpts, gotDone
local ctx = { mode = "bytecode", status = "running", specialVars = {} }
local PcAnim = require("src.core.game3.pc_anim")
local mtSets = {}
PcAnim.setter(function(x, y, mid, imp)
  mtSets[#mtSets + 1] = { x = x, y = y, mid = mid, imp = imp }
end)
local realPlayer = package.loaded["src.core.game3.player"]
package.loaded["src.core.game3.player"] = { cellX = 1, cellY = 2, facing = "up" }
local adapters = {
  openPc = function(done, opts)
    gotDone = done
    gotOpts = opts
  end,
  log = function() end,
}
local yielded = Natives.special(ctx, 249, adapters)
check(yielded == true, "special 249 yields")
check(type(gotOpts) == "table" and gotOpts.bedroom == true, "openPc got bedroom=true")
check(ctx.nativePoll and ctx.nativePoll() == false, "native wait pending while PC open")
if gotDone then gotDone() end
check(ctx.nativePoll and ctx.nativePoll() == true, "native wait finishes on close")
local last = mtSets[#mtSets]
check(ctx.specialVars[0x8004] == 1, "ShutDownPC sets VAR_0x8004 = 1")
check(last and last.x == 1 and last.y == 1 and last.mid == 0x28F and last.imp == true,
  "bedroom close swaps PC at (1,1) to PlayersPCOff 0x28F")

print("[test] 3. host openPc routes bedroom into player_pc with closeOnExit")
do
  local shown
  local realPc = package.loaded["src.ui.game3.pc_menu"]
  local realRt = package.loaded["src.core.game3.runtime"]
  package.loaded["src.ui.game3.pc_menu"] = { show = function(o) shown = o end }
  package.loaded["src.core.game3.runtime"] = {
    isActive = function() return true end,
    getSession = function() return {} end,
  }
  local okA, Adapters = pcall(require, "src.core.game3.scripting.adapters")
  local okH, host = false, nil
  if okA then
    okH, host = pcall(Adapters.host, nil, {}, nil)
  end
  check(okH and host and host.openPc, "Adapters.host builds openPc")
  if okH and host and host.openPc then
    host.openPc(function() end, { bedroom = true })
    check(shown and shown.startMode == "player_pc" and shown.closeOnExit == true,
      "bedroom -> startMode player_pc, closeOnExit")
    shown = nil
    host.openPc(function() end)
    check(shown and shown.startMode == nil and not shown.closeOnExit, "no opts -> root hub")
  end
  package.loaded["src.ui.game3.pc_menu"] = realPc
  package.loaded["src.core.game3.runtime"] = realRt
end

print("[test] 4. PcMenu bedroom mode: starts in player_pc, B and TURN OFF close")
local PcMenu = require("src.ui.game3.pc_menu")
local function input(btn)
  return { wasPressed = function(_, b) return b == btn end }
end

local closed = 0
PcMenu.show({ session = {}, onClose = function() closed = closed + 1 end,
  startMode = "player_pc", closeOnExit = true })
check(PcMenu.mode == "player_pc", "starts in player_pc (got " .. tostring(PcMenu.mode) .. ")")
check(PcMenu._status == "What would you like to do?", "status What would you like to do?")
PcMenu.handleInput(input("b"))
check(not PcMenu.isOpen() and closed == 1, "B closes bedroom PC and fires onClose")

PcMenu.show({ session = {}, onClose = function() closed = closed + 1 end,
  startMode = "player_pc", closeOnExit = true })
PcMenu.handleInput(input("up"))
check(PcMenu.cursor == 1, "top menu does not wrap up")
PcMenu.handleInput(input("down"))
PcMenu.handleInput(input("down"))
PcMenu.handleInput(input("down"))
check(PcMenu.cursor == 3, "cursor on TURN OFF, no wrap down")
PcMenu.handleInput(input("a"))
check(not PcMenu.isOpen() and closed == 2, "TURN OFF closes bedroom PC")

PcMenu.show({ session = {}, onClose = function() closed = closed + 1 end })
check(PcMenu.mode == "root", "default show opens root hub")
PcMenu.cursor = 2
PcMenu.handleInput(input("a"))
check(PcMenu.mode == "player_pc", "hub -> player_pc")
PcMenu.handleInput(input("b"))
check(PcMenu.isOpen() and PcMenu.mode == "root" and closed == 2, "hub player_pc B returns to root")
PcMenu.close()

print("[test] 5. New game seeds PC POTION; withdraw moves it to bag; save round-trip")
local Schema = require("src.core.game3.save_schema_firered")
local Bag = require("src.core.game3.bag")
local Storage = require("src.core.game3.storage")
local session = Schema.newGame({ rngSeed = 1 })
local it = session.storage and session.storage.items and session.storage.items[1]
check(it and it.id == 13 and it.qty == 1, "newGame storage.items[1] = POTION x1")
check(session.storage and #session.storage.items == 1, "exactly one PC item")

local saved = Schema.toSaveTable(session)
check(type(saved.storage) == "table" and saved.storage.items[1] and saved.storage.items[1].id == 13,
  "toSaveTable writes storage")
local restored = Schema.fromSaveTable(saved)
check(restored.storage and restored.storage.items[1] and restored.storage.items[1].id == 13,
  "fromSaveTable restores storage")
local legacy = Schema.fromSaveTable({ map = "FR_PALLET_TOWN", x = 1, y = 1 })
check(legacy.storage and legacy.storage.items[1] and legacy.storage.items[1].id == 13, "legacy save without storage gets seeded POTION")

check(Storage.withdrawItem(session, 1, 1) == true, "withdrawItem POTION ok")
check(Bag.has(session.bag, 13, 1), "bag has POTION")
check(#session.storage.items == 0, "PC storage empty after withdraw")

print("[test] 6. cart labels, descriptions, MAILBOX, no TOSS")
local function joined(list)
  local t = {}
  for i, a in ipairs(list) do t[i] = a.label end
  return table.concat(t, "/")
end
check(joined(PcMenu.TOP_ACTIONS) == "ITEM STORAGE/MAILBOX/TURN OFF",
  "top menu labels (got " .. joined(PcMenu.TOP_ACTIONS) .. ")")
check(joined(PcMenu.ITEM_STORAGE_ACTIONS) == "WITHDRAW ITEM/DEPOSIT ITEM/CANCEL",
  "item storage labels (got " .. joined(PcMenu.ITEM_STORAGE_ACTIONS) .. ")")

local seLog = {}
package.loaded["src.core.game3.audio"].playSe = function(id) seLog[#seLog + 1] = id end
local s6 = { bag = Bag.new(), storage = Storage.new() }
s6.storage.items = {} -- clear to test empty WITHDRAW message
local closed6 = 0
PcMenu.show({ session = s6, startMode = "player_pc", closeOnExit = true,
  onClose = function() closed6 = closed6 + 1 end })
check(#seLog == 0, "bedroom PC open plays no SE_PC_LOGIN")
PcMenu.handleInput(input("a"))
check(PcMenu.mode == "item_storage" and PcMenu.cursor == 1
  and PcMenu._status == "Take out items from the PC.", "ITEM STORAGE -> submenu, WITHDRAW desc")
PcMenu.handleInput(input("up"))
check(PcMenu.cursor == 1, "submenu does not wrap up")
PcMenu.handleInput(input("down"))
check(PcMenu._status == "Store items in the PC.", "DEPOSIT desc")
PcMenu.handleInput(input("down"))
check(PcMenu._status == "Go back to the\nprevious menu.", "CANCEL desc")
PcMenu.handleInput(input("down"))
check(PcMenu.cursor == 3, "submenu does not wrap down")
PcMenu.handleInput(input("up"))
PcMenu.handleInput(input("up"))
PcMenu.handleInput(input("a"))
check(PcMenu.mode == "msg" and PcMenu._status == "There are no items.", "empty WITHDRAW -> There are no items.")
PcMenu.handleInput(input("a"))
check(PcMenu.mode == "item_storage" and PcMenu.cursor == 1
  and PcMenu._status == "Take out items from the PC.", "no-items message returns to submenu")
PcMenu.handleInput(input("b"))
check(PcMenu.mode == "player_pc" and PcMenu.cursor == 1
  and PcMenu._status == "What would you like to do?", "B in submenu returns to top menu")
PcMenu.handleInput(input("down"))
PcMenu.handleInput(input("a"))
check(PcMenu.mode == "msg" and PcMenu._status == "There's no MAIL here.", "MAILBOX -> There's no MAIL here.")
PcMenu.handleInput(input("a"))
check(PcMenu.mode == "player_pc" and PcMenu.cursor == 1
  and PcMenu._status == "What would you like to do?", "mail message returns to top menu")
s6.storage.items[1] = { id = 13, qty = 1 }
PcMenu.handleInput(input("a"))
PcMenu.handleInput(input("a"))
check(PcMenu.mode == "withdraw_item", "WITHDRAW ITEM opens PC item list")
PcMenu.handleInput(input("a"))
check(PcMenu.mode == "msg" and Bag.has(s6.bag, 13, 1), "POTION withdrawn")
PcMenu.handleInput(input("a"))
check(PcMenu.mode == "item_storage" and PcMenu.cursor == 1, "after withdraw back in ITEM STORAGE")
PcMenu.handleInput(input("b"))
PcMenu.handleInput(input("b"))
check(not PcMenu.isOpen() and closed6 == 1, "B at top menu turns the PC off")
package.loaded["src.core.game3.audio"].playSe = function() end

print("[test] 7. AnimatePcTurnOn flicker / AnimatePcTurnOff")
mtSets = {}
local actx = { specialVars = { [0x8004] = 1 } }
check(Natives.special(actx, Std.SPECIAL.AnimatePcTurnOn, { log = function() end }) == false,
  "AnimatePcTurnOn does not block the script")
local frames = {}
for f = 1, 40 do
  local before = #mtSets
  PcAnim.update()
  if #mtSets > before then frames[#frames + 1] = f end
end
local mids = {}
for i, s in ipairs(mtSets) do mids[i] = string.format("%X@%d,%d", s.mid, s.x, s.y) end
check(table.concat(mids, " ") == "28A@1,1 28F@1,1 28A@1,1 28F@1,1 28A@1,1",
  "flicker on/off/on/off/on (got " .. table.concat(mids, " ") .. ")")
check(table.concat(frames, ",") == "7,13,19,25,31", "flicker every 6 frames (got " .. table.concat(frames, ",") .. ")")
check(PcAnim.task == nil, "turn-on task ends after 5 swaps")
mtSets = {}
Natives.special({ specialVars = { [0x8004] = 0 } }, Std.SPECIAL.AnimatePcTurnOff, { log = function() end })
check(mtSets[1] and mtSets[1].mid == 0x062, "center PC turn off uses Building_PCOff 0x062")
package.loaded["src.core.game3.player"] = { cellX = 5, cellY = 5, facing = "left" }
mtSets = {}
PcAnim.turnOff({ specialVars = { [0x8004] = 0 } })
check(mtSets[1] and mtSets[1].x == 4 and mtSets[1].y == 4, "facing west targets (x-1, y-1)")
package.loaded["src.core.game3.player"] = realPlayer
PcAnim.setter(nil)

do
  local realMap = package.loaded["src.core.game3.map"]
  local realTs = package.loaded["src.core.game3.tileset_native"]
  package.loaded["src.core.game3.map"] = { currentDef = function() return { pair = "players_house" } end }
  package.loaded["src.core.game3.tileset_native"] = {
    ready = function() return true end,
    get = function() return { midToSlot = { [0x28F] = 7 } } end,
  }
  check(PcAnim.drawable(0x28F) == true, "drawable: mid in the pair atlas")
  check(PcAnim.drawable(0x28A) == false, "drawable: mid missing from atlas would draw the black void slot")
  package.loaded["src.core.game3.map"] = realMap
  package.loaded["src.core.game3.tileset_native"] = realTs
end

do
  local NativePack = require("src.import.gba.native_pack")
  local grids = {
    FR_PLAYERS_HOUSE_2F = { pair = "player_house", cells = { { mid = 0x280 }, { mid = 0x28F } } },
    SEVII_ONE_ISLAND_POKECENTER = { pair = "network", cells = { { mid = 0x062 } } },
    FR_PALLET_TOWN = { pair = "pallet_outdoor", cells = { { mid = 0x001 } } },
  }
  local function has(list, mid)
    for _, m in ipairs(list) do if m == mid then return true end end
    return false
  end
  local ph = NativePack.collectMidsForPair(grids, {}, "player_house")
  check(has(ph, 0x28F) and has(ph, 0x28A), "atlas mids: bedroom PC off 0x28F brings PlayersPCOn 0x28A")
  local net = NativePack.collectMidsForPair(grids, {}, "network")
  check(has(net, 0x062) and has(net, 0x063), "atlas mids: center PC off 0x062 brings Building_PCOn 0x063")
  local pal = NativePack.collectMidsForPair(grids, {}, "pallet_outdoor")
  check(not has(pal, 0x063) and not has(pal, 0x28A), "atlas mids: no PC on mids without a PC off mid")
end

print("[test] 8. one PC table: session.storage, legacy pc migration, sidecar")
local ng = Schema.newGame({ rngSeed = 2 })
check(ng.pc == nil, "newGame has no session.pc")
check(Schema.toSaveTable(ng).pc == nil, "save table writes no pc")
local mig = Schema.fromSaveTable({ map = "FR_PALLET_TOWN", x = 1, y = 1,
  pc = { items = { { id = 13, qty = 2 } }, mons = { { species = 16, level = 4 } } } })
check(mig.pc == nil and mig.storage and mig.storage.items[1] and mig.storage.items[1].id == 13
  and mig.storage.items[1].qty == 2, "legacy pc.items migrated into storage")
check(mig.storage and Storage.countTotalMons(mig.storage) == 1 and mig.storage.boxes[1].mons[1].species == 16,
  "legacy pc.mons migrated into box 1")
local both = Schema.fromSaveTable({
  storage = { items = { { id = 17, qty = 1 } }, boxes = { [1] = { mons = { [1] = { species = 25 } } } } },
  pc = { items = { { id = 13, qty = 2 } }, mons = { { species = 16 } } },
})
check(#both.storage.items == 1 and both.storage.items[1].id == 17, "storage items win over stale pc items")
check(Storage.countTotalMons(both.storage) == 1 and both.storage.boxes[1].mons[1].species == 25,
  "no duplicate box mons from stale pc.mons")
local okB, Bridge = pcall(require, "src.core.game3.bridge")
check(okB, "bridge loads")
if okB then
  local sc = { pc = { items = { { id = 13, qty = 9 } } } }
  Bridge.storageToSidecar(sc, { storage = mig.storage })
  check(sc.pc == nil and sc.storage and sc.storage.items[1].qty == 2 and sc.storage.boxes[1].mons[1].species == 16,
    "sidecar keeps storage and drops pc")
  local back = Storage.restore(sc.storage, sc.pc)
  check(back and back.items[1].id == 13 and Storage.countTotalMons(back) == 1, "sidecar storage restores")
  local legacySc = Storage.restore(nil, { items = { { id = 13, qty = 1 } } })
  check(legacySc and legacySc.items[1].id == 13, "sidecar with only pc migrates")
end
local okC, Catching = pcall(require, "src.core.game3.battle.catching")
local okD, Dex = pcall(require, "src.core.game3.dex")
if okC and okD then
  local cs = { name = "RED", id = 1, dex = Dex.new(), party = {} }
  for i = 1, 6 do cs.party[i] = { species = 1, level = 5, hp = 20, maxHp = 20 } end
  local okS, res = pcall(Catching.storeCaught, cs, { species = 16, mon = { species = 16, level = 4, hp = 5, maxHp = 18 } }, 4)
  check(okS and res.location == "pc" and cs.pc == nil and Storage.countTotalMons(cs.storage) == 1,
    "catch with full party writes only session.storage")
else
  check(false, "catching/dex load")
end

if failed == 0 then
  print("\nAll game3 bedroom PC tests passed.")
  os.exit(0)
else
  print("\n" .. failed .. " bedroom PC test(s) failed.")
  os.exit(1)
end
