return function(game)
  local U = dofile("tests/drivers/util.lua")
  local RomImporter = require("src.import.RomImporter")
  local OnlinePanel = require("src.import.OnlinePanel")
  local Transition = require("src.ui.kit.Transition")

  local dir = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR")
    or "/tmp/online2435"
  os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')
  love.window.setMode(1024, 768, { resizable = true, highdpi = true })
  U.wait(2)

  local failed = false
  local function expect(cond, label, why)
    if cond then
      print("PASS " .. label)
    else
      failed = true
      print("FAIL " .. label .. (why ~= nil and (": " .. tostring(why)) or ""))
    end
  end

  local function mon(species, name, nickname, level, extra)
    local m = { species = species, speciesId = species, name = name,
      nickname = nickname, level = level, hp = 20, maxHp = 20 }
    for k, v in pairs(extra or {}) do m[k] = v end
    return m
  end

  local lgParty = {
    mon(1, "BULBASAUR", "", 6),
    mon(16, "PIDGEY", "", 3),
    mon(1, "BULBASAUR", "EGG", 5, { isEgg = true }),
  }
  local frParty = {
    mon(4, "CHARMANDER", "CHAR", 6),
    mon(19, "RATTATA", "", 4),
  }
  local lgBox = mon(25, "PIKACHU", "", 7)

  local entryA = { version = "leafgreen", slotId = "slot1", generation = 3,
    label = "LeafGreen  slot1" }
  local entryB = { version = "firered", slotId = "slot1", generation = 3,
    label = "FireRed  slot1" }
  local handleA = { version = "leafgreen", generation = 3, slotId = "slot1",
    party = lgParty, save = { boxes = { { lgBox } } } }
  local handleB = { version = "firered", generation = 3, slotId = "slot1",
    party = frParty, save = { boxes = {} } }

  local imp = RomImporter.new(function() end, { launcher = true })
  Transition.reduceMotion = true
  imp:_switchTab("online")
  OnlinePanel.go(imp, "trade")
  local tr = OnlinePanel.tradeState(imp)
  tr.mode, tr.chosen = "local", true
  tr.sides.a, tr.sides.b = entryA, entryB
  tr.handles.a = { entry = entryA, handle = handleA }
  tr.handles.b = { entry = entryB, handle = handleB }
  tr.picks.a = { where = "box", box = 1, index = 1 }

  local pending = nil
  love.draw = function()
    local c = OnlinePanel.cache(imp)
    c.dirty.trade = false
    c.tradeSlots = { entryA, entryB }
    imp:draw()
    if pending then
      local path = pending
      pending = nil
      love.graphics.captureScreenshot(function(imagedata)
        local f = io.open(path, "wb")
        if f then f:write(imagedata:encode("png"):getString()) f:close() end
      end)
    end
  end
  local function step(n)
    for _ = 1, n do
      imp:update(1 / 60)
      coroutine.yield()
    end
  end

  step(10)
  local rows = OnlinePanel.cache(imp).tradeRows
  local function labels(side)
    local out = {}
    for _, row in ipairs(rows[side] or {}) do out[#out + 1] = row.label end
    return out
  end
  local a, b = labels("a"), labels("b")
  print("[2435] a: " .. table.concat(a, " / "))
  print("[2435] b: " .. table.concat(b, " / "))
  expect(a[1] == "BULBASAUR Lv6", "2435_lg_unnamed_species", a[1])
  expect(a[2] == "PIDGEY Lv3", "2435_lg_unnamed_second", a[2])
  expect(a[3] == "EGG Lv5", "2435_lg_egg", a[3])
  expect(a[4] == "PIKACHU Lv7  BOX 1", "2435_lg_pc_row", a[4])
  expect(b[1] == "CHAR Lv6", "2435_fr_nickname", b[1])
  expect(b[2] == "RATTATA Lv4", "2435_fr_unnamed", b[2])

  local path = dir .. "/2435_trade_local_gen3_names.png"
  os.remove(path)
  pending = path
  for _ = 1, 4000 do
    if not pending then break end
    coroutine.yield()
  end
  local f
  for _ = 1, 4000 do
    f = io.open(path, "rb")
    if f then break end
    coroutine.yield()
  end
  expect(f ~= nil, "2435_shot")
  if f then f:close() end

  love.event.quit(failed and 1 or 0)
end
