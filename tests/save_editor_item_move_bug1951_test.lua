package.path = package.path .. ";./?.lua;./?/init.lua;./tools/save-editor/?.lua"
  .. ";./tools/save-editor/panels/?.lua"

love = require("tests.love_stub")

local passed, failed = 0, 0

local function check(cond, msg)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print("FAIL: " .. msg)
  end
end

local function eq(a, b, msg)
  check(a == b, msg .. string.format(" (got %s, want %s)", tostring(a), tostring(b)))
end

print("== save editor item move tests (#1951) ==")

local Ops = require("Ops")
local State = require("State")
local Catalog = require("Catalog")
local Gen = require("Gen")
local Bag = require("src.inventory.Bag")
local SaveData = require("src.core.SaveData")
local G3 = require("Game3Adapter")

local function has(list, id)
  for _, v in ipairs(list or {}) do if v == id then return true end end
  return false
end

local Data = require("src.core.Data")
Data:load()

local function red()
  local S = State.new()
  S.data = Data
  S.cat = Catalog.build(Data)
  S.save = SaveData.newGame()
  S.save.inventory, S.save.bagOrder, S.save.pcItems = {}, nil, {}
  return S
end

local function fillers(S, n, skip)
  local out = {}
  for _, id in ipairs(S.cat.items) do
    if #out >= n then break end
    if not Ops.isBadgeId(id) and not (skip and skip[id]) then out[#out + 1] = id end
  end
  return out
end

check(type(Ops.bagToPc) == "function" and type(Ops.pcToBag) == "function"
  and type(Ops.moveCount) == "function", "gen1: move ops exist")

do
  local S = red()
  Bag.add(S.save, "POTION", 30, S.data)
  S.selectedBagId = "POTION"
  local ok = Ops.bagToPc and Ops.bagToPc(S, "POTION")
  check(ok == true, "gen1: bagToPc succeeds")
  eq(S.save.inventory.POTION, nil, "gen1: whole stack leaves the bag")
  check(not has(S.save.bagOrder, "POTION"), "gen1: bagOrder drops the moved id")
  eq(S.save.pcItems.POTION, 30, "gen1: PC gets the stack")
  check(S.dirty == true, "gen1: a move marks dirty")
  eq(S.selectedBagId, nil, "gen1: a vanished bag row is deselected")

  S.dirty = false
  ok = Ops.pcToBag and Ops.pcToBag(S, "POTION")
  check(ok == true, "gen1: pcToBag succeeds")
  eq(S.save.pcItems.POTION, nil, "gen1: PC stack empties")
  eq(S.save.inventory.POTION, 30, "gen1: bag gets the stack back")
  check(has(Bag.order(S.save, S.data), "POTION"), "gen1: bag order has the id again")
  check(S.dirty == true, "gen1: pcToBag marks dirty")
end

do
  local S = red()
  Bag.add(S.save, "POTION", 30, S.data)
  S.save.pcItems.POTION = 90
  eq(Ops.moveCount and Ops.moveCount(S, true, "POTION"), 9, "gen1: move clamps to the 99 stack")
  check(Ops.bagToPc and Ops.bagToPc(S, "POTION") == true, "gen1: clamped bagToPc succeeds")
  eq(S.save.pcItems.POTION, 99, "gen1: PC tops out at 99")
  eq(S.save.inventory.POTION, 21, "gen1: remainder stays in the bag")
  check(tostring(S.status):find("21 left in the bag", 1, true) ~= nil,
    "gen1: status names the remainder: " .. tostring(S.status))
  S.dirty = false
  eq(Ops.moveCount and Ops.moveCount(S, true, "POTION"), 0, "gen1: nothing more fits")
  check(Ops.bagToPc and Ops.bagToPc(S, "POTION") == false, "gen1: full PC stack refuses")
  check(S.dirty == false, "gen1: refusal does not dirty")
end

do
  local S = red()
  local ids = fillers(S, 51, { POTION = true })
  for i = 1, 50 do S.save.pcItems[ids[i]] = 1 end
  Bag.add(S.save, "POTION", 5, S.data)
  S.dirty = false
  check(Ops.bagToPc and Ops.bagToPc(S, "POTION") == false, "gen1: 51st PC stack refused")
  eq(S.save.pcItems.POTION, nil, "gen1: refused move leaves PC untouched")
  eq(S.save.inventory.POTION, 5, "gen1: refused move leaves the bag untouched")
  check(S.dirty == false, "gen1: refused move not dirty")
  check(Ops.addToPc(S, ids[51]) == false, "gen1: addToPc refuses a 51st PC id")
  eq(S.save.pcItems[ids[51]], nil, "gen1: refused addToPc leaves no entry")
  check(Ops.addToPc(S, ids[1]) == true, "gen1: addToPc still grows an existing stack")
end

do
  local S = red()
  local ids = fillers(S, 20, { POTION = true, ULTRA_BALL = true })
  for i = 1, 20 do Bag.add(S.save, ids[i], 1, S.data) end
  S.save.pcItems.ULTRA_BALL = 5
  S.dirty = false
  check(Ops.pcToBag and Ops.pcToBag(S, "ULTRA_BALL") == false, "gen1: full bag refuses pcToBag")
  eq(S.save.pcItems.ULTRA_BALL, 5, "gen1: refused pcToBag leaves PC")
  eq(S.save.inventory.ULTRA_BALL, nil, "gen1: refused pcToBag adds nothing")
  check(tostring(S.status):find("Bag is full", 1, true) ~= nil, "gen1: status says bag is full")
  check(S.dirty == false, "gen1: refused pcToBag not dirty")
  Bag.remove(S.save, ids[20], 1)
  check(Ops.pcToBag and Ops.pcToBag(S, "ULTRA_BALL") == true, "gen1: pcToBag works once a slot frees")
  eq(S.save.inventory.ULTRA_BALL, 5, "gen1: bag gets all 5")
end

do
  local S = red()
  Bag.add(S.save, "BICYCLE", 1, S.data)
  check(Ops.bagToPc and Ops.bagToPc(S, "BICYCLE") == true, "gen1: key item deposits")
  eq(S.save.pcItems.BICYCLE, 1, "gen1: BICYCLE in PC")
  check(Ops.pcToBag and Ops.pcToBag(S, "BICYCLE") == true, "gen1: key item withdraws")
  eq(S.save.inventory.BICYCLE, 1, "gen1: BICYCLE back in bag")
  S.save.inventory.BOULDERBADGE = true
  eq(Ops.moveCount and Ops.moveCount(S, true, "BOULDERBADGE"), 0, "gen1: badges never move")
end

do
  local S = red()
  Bag.add(S.save, "POTION", 30, S.data)
  S.save.pcItems.ANTIDOTE = 4
  S.save.pcOrder = { "ANTIDOTE" }
  if Ops.bagToPc then Ops.bagToPc(S, "POTION") end
  if Ops.pcToBag then Ops.pcToBag(S, "ANTIDOTE") end
  local back = assert(SaveData.decode(SaveData.encode(S.save)))
  eq(back.pcItems.POTION, 30, "gen1: moved PC stack survives encode")
  eq(back.pcItems.ANTIDOTE, nil, "gen1: withdrawn PC stack gone after encode")
  eq(back.inventory.ANTIDOTE, 4, "gen1: withdrawn stack in bag after encode")
  local GenSave = require("src.save_convert.GenSave")
  GenSave.setCharmap(loadfile("src/save_convert/data/charmap.lua")())
  local okE, bytes = pcall(GenSave.encode, back, Data)
  check(okE and type(bytes) == "string", "gen1: .sav encode runs: " .. tostring(bytes))
  if okE and type(bytes) == "string" then
    local okD, dec = pcall(GenSave.decode, bytes, Data)
    check(okD and type(dec) == "table", "gen1: .sav decode runs: " .. tostring(dec))
    if okD and type(dec) == "table" then
      local sav = dec.save or dec
      eq(sav.pcItems and sav.pcItems.POTION, 30, "gen1: .sav round trip keeps the moved stack")
      eq(sav.pcItems and sav.pcItems.ANTIDOTE, nil, "gen1: .sav round trip drops the stale pcOrder id")
      eq(sav.inventory and sav.inventory.ANTIDOTE, 4, "gen1: .sav round trip keeps the withdrawn stack")
    end
  end
end

do
  local GameVersion = require("src.core.GameVersion")
  local Save2 = require("src.core.gen2.Save")
  local data2 = {
    pokemon = {}, moves = {}, maps = {},
    items = {
      POTION = { pocket = "ITEM", index = 20, name = "POTION" },
      MASTER_BALL = { pocket = "BALL", index = 1, name = "MASTER BALL" },
      BICYCLE = { pocket = "KEY_ITEM", index = 6, name = "BICYCLE" },
      HM_01 = { pocket = "TM_HM", index = 249, name = "HM01" },
    },
  }
  local function gold()
    local prior = GameVersion.get()
    GameVersion.set("gold")
    local S = State.new()
    S.data = data2
    S.cat = Catalog.build(data2)
    S.save = Save2.newGame()
    S.version = "gold"
    S.save.inventory, S.save.bagOrder, S.save.pcItems = {}, nil, {}
    GameVersion.set(prior)
    return S
  end

  local S = gold()
  eq(Gen.ofState(S), 2, "gen2: fixture is gen 2")
  for i = 1, 20 do Bag.add(S.save, "FILLER_" .. i, 1, S.data) end
  S.save.pcItems.MASTER_BALL = 3
  S.save.pcItems.POTION = 4
  check(Ops.pcToBag and Ops.pcToBag(S, "MASTER_BALL") == true, "gen2: BALL pocket free while ITEM is full")
  eq(S.save.inventory.MASTER_BALL, 3, "gen2: MASTER_BALL in bag")
  S.dirty = false
  check(Ops.pcToBag and Ops.pcToBag(S, "POTION") == false, "gen2: 21st ITEM pocket id refused")
  eq(S.save.pcItems.POTION, 4, "gen2: refused ITEM withdraw leaves PC")
  check(S.dirty == false, "gen2: refused withdraw not dirty")

  S = gold()
  S.save.pcItems.POTION = 150
  check(Ops.pcToBag and Ops.pcToBag(S, "POTION") == true, "gen2: 150 PC potions withdraw")
  eq(S.save.inventory.POTION, 99, "gen2: bag takes one 99 stack")
  eq(S.save.pcItems.POTION, 51, "gen2: 51 stay in PC")

  S = gold()
  Bag.add(S.save, "HM_01", 1, S.data)
  check(Ops.bagToPc and Ops.bagToPc(S, "HM_01") == true, "gen2: HM deposits")
  eq(S.save.pcItems.HM_01, 1, "gen2: HM_01 in PC")
  check(Ops.pcToBag and Ops.pcToBag(S, "HM_01") == true, "gen2: HM withdraws")
  eq(S.save.inventory.HM_01, 1, "gen2: HM_01 back in bag")

  S = gold()
  for i = 1, 49 do S.save.pcItems["FILLER_" .. i] = 1 end
  S.save.pcItems.POTION = 99
  Bag.add(S.save, "POTION", 5, S.data)
  S.dirty = false
  check(Ops.bagToPc and Ops.bagToPc(S, "POTION") == false, "gen2: move needing a 51st PC stack refused")
  eq(S.save.inventory.POTION, 5, "gen2: refused deposit leaves bag")

  S = gold()
  Ops.addToPc(S, "BICYCLE")
  S.dirty = false
  check(Ops.addToPc(S, "BICYCLE") == false, "gen2: second key item add refused")
  eq(S.save.pcItems.BICYCLE, 1, "gen2: key item in PC stays x1")
  check(S.dirty == false, "gen2: refused key item add not dirty")
  Ops.pcAdjust(S, "BICYCLE", 1)
  eq(S.save.pcItems.BICYCLE, 1, "gen2: key item + stays x1")

  S = gold()
  S.save.pcItems.BICYCLE = 3
  eq(Ops.moveCount(S, false, "BICYCLE"), 1, "gen2: key item withdraw count is 1")
  check(Ops.pcToBag(S, "BICYCLE") == true, "gen2: key item withdraws")
  eq(S.save.inventory.BICYCLE, 1, "gen2: key item lands in the bag x1")
  eq(S.save.pcItems.BICYCLE, 2, "gen2: key item withdraw takes only 1")
  eq(Ops.moveCount(S, false, "BICYCLE"), 0, "gen2: held key item cannot withdraw again")

  S = gold()
  Bag.add(S.save, "BICYCLE", 1, S.data)
  S.save.pcItems.BICYCLE = 1
  eq(Ops.moveCount(S, true, "BICYCLE"), 0, "gen2: key item deposit cannot stack past 1")
end

do
  local Schema = require("src.core.game3.save_schema_firered")
  local Copy = require("src.mods.Merge").deepCopy
  local function deq(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(a) do if not deq(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
  end
  local mock = {}
  Gen.bindGame3Data(mock)
  local function fire()
    local save = Schema.newGame({ name = "RED" })
    save.bag.pockets.ITEMS, save.bag.pockets.POKE_BALLS = {}, {}
    save.bag.pockets.TM_CASE, save.bag.pockets.KEY_ITEMS = {}, {}
    save.storage.items = {}
    local S = { data = mock, version = "firered", save = save, cat = Catalog.build(mock, save, "firered") }
    Gen.hydrateSave(mock, save)
    return S
  end

  eq(G3.PC_ITEMS_COUNT, 30, "gen3: editor PC cap is FRLG PC_ITEMS_COUNT")

  local S = fire()
  Ops.addToBag(S, "POTION"); Ops.bagAdjust(S, "POTION", 9)
  eq(S.save.inventory["13"], 10, "gen3: seeded 10 potions")
  check(Ops.bagToPc and Ops.bagToPc(S, "POTION") == true, "gen3: bagToPc succeeds")
  eq(S.save.inventory["13"], nil, "gen3: projection bag empty")
  eq(S.save.pcItems["13"], 10, "gen3: projection PC 10")
  eq(#S.save.bag.pockets.ITEMS, 0, "gen3: native ITEMS pocket emptied")
  eq(S.save.storage.items[1] and S.save.storage.items[1].qty, 10, "gen3: native storage slot written")
  check(Ops.pcToBag and Ops.pcToBag(S, "13") == true, "gen3: pcToBag succeeds")
  eq(S.save.inventory["13"], 10, "gen3: back in bag")
  eq(#S.save.storage.items, 0, "gen3: native storage emptied")

  S = fire()
  for i = 1, 42 do S.save.bag.pockets.ITEMS[i] = { id = 2000 + i, qty = 1 } end
  S.save.storage.items = { { id = 13, qty = 5 } }
  Gen.hydrateSave(mock, S.save)
  local before = Copy(S.save)
  S.dirty = false
  check(Ops.pcToBag and Ops.pcToBag(S, "13") == false, "gen3: full ITEMS pocket refuses")
  check(deq(S.save, before), "gen3: refused withdraw rolls back fully")
  check(S.dirty == false, "gen3: refused withdraw not dirty")

  S = fire()
  for i = 1, 30 do S.save.storage.items[i] = { id = 2000 + i, qty = 1 } end
  S.save.bag.pockets.ITEMS = { { id = 13, qty = 3 } }
  Gen.hydrateSave(mock, S.save)
  before = Copy(S.save)
  S.dirty = false
  check(Ops.bagToPc and Ops.bagToPc(S, "13") == false, "gen3: 31st PC slot refused")
  check(deq(S.save, before), "gen3: refused deposit rolls back fully")
  check(Ops.addToPc(S, "POTION") == false, "gen3: addToPc refuses a 31st PC slot")
  check(deq(S.save, before), "gen3: refused addToPc rolls back fully")

  S = fire()
  S.save.storage.items = { { id = 289, qty = 1 } }
  Gen.hydrateSave(mock, S.save)
  check(Ops.pcToBag and Ops.pcToBag(S, "289") == true, "gen3: TM withdraws")
  check(S.save.inventory["364"] == 1, "gen3: TM withdraw adds TM_CASE")
  eq(S.save.inventory["289"], 1, "gen3: TM01 in bag")
  eq(Ops.moveCount and Ops.moveCount(S, true, "364"), 0, "gen3: TM_CASE itself cannot go to PC")
  local out = G3.export(S.save)
  check(type(out.bag) == "table" and out.pcItems == nil, "gen3: export drops the flat projection")
  local tmSlot = out.bag.pockets.TM_CASE and out.bag.pockets.TM_CASE[1]
  eq(tmSlot and tmSlot.id, 289, "gen3: export keeps TM01 in the TM_CASE pocket")

  S = fire()
  S.save.bag.pockets.ITEMS = { { id = 13, qty = 999 } }
  S.save.storage.items = { { id = 13, qty = 990 } }
  Gen.hydrateSave(mock, S.save)
  eq(Ops.moveCount and Ops.moveCount(S, true, "13"), 9, "gen3: move clamps to the 999 stack")
  check(Ops.bagToPc and Ops.bagToPc(S, "13") == true, "gen3: clamped move succeeds")
  eq(S.save.pcItems["13"], 999, "gen3: PC tops out at 999")
  eq(S.save.inventory["13"], 990, "gen3: remainder stays in the bag")
end

do
  local Kit = require("Kit")
  local App = require("App")
  local oldDim = love.graphics.getDimensions
  for _, size in ipairs({ { 1280, 720 }, { 500, 800 } }) do
    love.graphics.getDimensions = function() return size[1], size[2] end
    local path = os.tmpname() .. "-bug1951.lua"
    local seed = SaveData.newGame()
    seed.inventory, seed.bagOrder = { POTION = 30 }, { "POTION" }
    seed.pcItems = { ULTRA_BALL = 5 }
    local f = assert(io.open(path, "wb")); f:write(SaveData.encode(seed)); f:close()
    App.load(path, { version = "red" })
    local S = App.getState()
    S.tab = "items"
    local rects = {}
    local real = Kit.button
    Kit.button = function(x, y, w, h, label, opts)
      if label == "PC" or label == "BAG" then
        rects[#rects + 1] = { label = label, x = x, y = y, w = w, h = h,
          enabled = not (opts and opts.enabled == false) }
      end
      return real(x, y, w, h, label, opts)
    end
    local pcBtn, bagBtn
    local function capture()
      rects = {}
      App.draw()
      pcBtn, bagBtn = nil, nil
      for _, r in ipairs(rects) do
        if r.label == "PC" then pcBtn = r elseif r.label == "BAG" then bagBtn = r end
      end
    end
    capture()
    if pcBtn and pcBtn.y > size[2] - 60 then
      S.itemsScroll = pcBtn.y - 120
      capture()
      capture()
    end
    local tag = ("%dx%d"):format(size[1], size[2])
    check(pcBtn ~= nil and pcBtn.enabled, tag .. " panel: bag row has an enabled PC button")
    check(bagBtn ~= nil and bagBtn.enabled, tag .. " panel: PC row has an enabled BAG button")
    if pcBtn then
      App.mousepressed(pcBtn.x + pcBtn.w / 2, pcBtn.y + pcBtn.h / 2, 1)
      App.draw()
      eq(S.save.pcItems.POTION, 30, tag .. " panel: PC click moved the potions")
      eq(S.save.inventory.POTION, nil, tag .. " panel: bag row emptied")
      check(tostring(S.status):find("Moved 30", 1, true) ~= nil,
        tag .. " panel: move status is not clobbered by row select: " .. tostring(S.status))
    end
    Kit.button = real
    App.unload()
    os.remove(path)
  end
  love.graphics.getDimensions = oldDim
end

print(string.format("save editor item move tests: %d passed, %d failed", passed, failed))
if failed > 0 then os.exit(1) end
