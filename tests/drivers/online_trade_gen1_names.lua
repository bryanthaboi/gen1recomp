return function(game)
  local U = dofile("tests/drivers/util.lua")
  local RomImporter = require("src.import.RomImporter")
  local OnlinePanel = require("src.import.OnlinePanel")
  local Transition = require("src.ui.kit.Transition")

  local dir = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR")
    or "/tmp/online_gen1_names"
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

  local function mon(species, level, nickname)
    return { species = species, level = level, nickname = nickname,
      hp = 20, maxHp = 20 }
  end

  local redParty = {
    mon("MR_MIME", 20), mon("NIDORAN_M", 5), mon("NIDORAN_F", 6),
    mon("FARFETCHD", 9), mon("MR_MIME", 21, "MIMEY"),
  }
  local goldParty = { mon("MR__MIME", 22), mon("HO_OH", 40) }
  local redBox = mon("NIDORAN_F", 7)

  local entryA = { version = "red", slotId = "slot1", generation = 1,
    label = "Red  slot1" }
  local entryB = { version = "gold", slotId = "slot1", generation = 2,
    label = "Gold  slot1" }
  local handleA = { version = "red", generation = 1, slotId = "slot1",
    party = redParty, save = { boxes = { { redBox } } } }
  local handleB = { version = "gold", generation = 2, slotId = "slot1",
    party = goldParty, save = { boxes = {} } }

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
  local rows = OnlinePanel.cache(imp).tradeRows or {}
  local function labels(side)
    local out = {}
    for _, row in ipairs(rows[side] or {}) do out[#out + 1] = row.label end
    return out
  end
  local a, b = labels("a"), labels("b")
  print("[names] a: " .. table.concat(a, " / "))
  print("[names] b: " .. table.concat(b, " / "))
  expect(a[1] == "MR.MIME Lv20", "names_red_mr_mime", a[1])
  expect(a[2] == "NIDORAN♂ Lv5", "names_red_nidoran_m", a[2])
  expect(a[3] == "NIDORAN♀ Lv6", "names_red_nidoran_f", a[3])
  expect(a[4] == "FARFETCH'D Lv9", "names_red_farfetchd", a[4])
  expect(a[5] == "MIMEY Lv21", "names_red_nickname", a[5])
  expect(type(a[6]) == "string" and a[6]:sub(1, #"NIDORAN♀ Lv7") == "NIDORAN♀ Lv7",
    "names_red_pc_row", a[6])
  expect(b[1] == "MR.MIME Lv22", "names_gold_mr_mime", b[1])
  expect(b[2] == "HO-OH Lv40", "names_gold_ho_oh", b[2])

  local lines = OnlinePanel.tradeLines({
    sides = { { role = "b", handle = handleB,
      sent = goldParty[2], received = mon("SLOWPOKE", 30),
      record = mon("SLOWKING", 30), evolveTo = "SLOWKING" } },
    warnings = { { code = "item_used", slot = "slot1", item = "KINGS_ROCK" } },
  }, { b = "GOLD" })
  print("[names] lines: " .. table.concat(lines, " / "))
  expect(lines[3] == "KING'S ROCK is used up.", "names_gold_kings_rock", lines[3])

  local fonts = require("src.ui.kit.Theme").fonts(1)
  local glyphsOk = true
  for _, key in ipairs({ "tiny", "small", "tile", "button", "title" }) do
    local face = fonts[key]
    if not (face and face:hasGlyphs("♂♀é'.")) then glyphsOk = false end
  end
  expect(glyphsOk, "names_font_gender_glyphs")

  local path = dir .. "/mrmime_trade_local_gen1_names.png"
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
  expect(f ~= nil, "names_shot")
  if f then f:close() end

  love.event.quit(failed and 1 or 0)
end
