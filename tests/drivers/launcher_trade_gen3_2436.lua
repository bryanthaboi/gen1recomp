return function(game)
  local U = dofile("tests/drivers/util.lua")
  local RomImporter = require("src.import.RomImporter")
  local OnlinePanel = require("src.import.OnlinePanel")
  local Transition = require("src.ui.kit.Transition")
  local Trade = require("src.online.Trade")
  local TeamPick = require("src.online.TeamPick")
  local OnlineSprites = require("src.online.OnlineSprites")

  local dir = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/online2436"
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

  Trade.hostIsLive = function() return false end
  local imp = RomImporter.new(function() end, { launcher = true })
  Transition.reduceMotion = true
  imp:_switchTab("online")
  OnlinePanel.go(imp, "trade")
  OnlinePanel.tradeMode(imp, "local")
  local tr = OnlinePanel.tradeState(imp)
  tr.chosen = true

  local fronts = {}
  local drawFront = OnlineSprites.drawFront
  OnlineSprites.drawFront = function(entry, x, y, box)
    local ok = drawFront(entry, x, y, box)
    fronts[#fronts + 1] = { ok = ok, x = x, y = y, box = box }
    return ok
  end

  local pending = nil
  love.draw = function()
    fronts = {}
    imp:draw()
    if game.capturePath and not pending then
      pending = game.capturePath
      game.capturePath = nil
    end
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
  local function shot(name)
    local path = dir .. "/" .. name
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
    expect(f ~= nil, "2436_shot " .. name)
    if f then f:close() end
  end

  local fr, lg
  for _, row in ipairs(OnlinePanel.tradeSlots(imp)) do
    if row.version == "firered" and row.slotId == "slot1" and not row.cartId then fr = row end
    if row.version == "leafgreen" and row.slotId == "slot1" and not row.cartId then lg = row end
  end
  expect(fr ~= nil and lg ~= nil, "2436_slots_listed")
  if not (fr and lg) then
    love.event.quit(1)
    return
  end
  OnlinePanel.tradeSetSide(imp, "a", fr)
  OnlinePanel.tradeSetSide(imp, "b", lg)
  step(10)
  expect(not OnlinePanel.tradePcAllowed(imp, "a"), "2436_gen3_party_only")
  local frBefore = TeamPick.readSlot("firered", "slot1").party[1]
  local lgBefore = TeamPick.readSlot("leafgreen", "slot1").party[1]
  OnlinePanel.tradePick(imp, "a", 1)
  OnlinePanel.tradePick(imp, "b", 1)
  step(20)
  shot("2436_slots_listed.png")

  local previewed = OnlinePanel.tradeModalPreview(imp)
  print("[2436] preview status: " .. tostring(tr.status))
  for _, line in ipairs(tr.lines or {}) do print("[2436] line: " .. tostring(line)) end
  expect(previewed, "2436_preview", tr.status)
  step(20)
  local modal = OnlinePanel.tradeModal(imp)
  for _, which in ipairs({ "give", "get" }) do
    local side = modal and modal[which]
    local sprite = side and OnlineSprites.get(side.version, side.mon)
    expect(sprite and sprite.front, "2436_preview_" .. which .. "_pic_loaded",
      side and side.mon and side.mon.species)
  end
  local previewPath = dir .. "/2436_trade_preview.png"
  expect(U.still(game, previewPath), "2436_shot 2436_trade_preview.png")
  local drawn = {}
  for i, f in ipairs(fronts) do drawn[i] = f end
  expect(#drawn == 2 and drawn[1].ok and drawn[2].ok, "2436_preview_pics_drawn", #drawn)
  local okImg, img = pcall(function()
    local f = assert(io.open(previewPath, "rb"))
    local bytes = f:read("*a")
    f:close()
    return love.image.newImageData(love.filesystem.newFileData(bytes, "p.png"))
  end)
  local dpi = love.graphics.getDPIScale and love.graphics.getDPIScale() or 1
  for i, f in ipairs(drawn) do
    local lit, total = 0, 0
    if okImg then
      local x0, y0 = math.floor(f.x * dpi), math.floor(f.y * dpi)
      local n = math.floor(f.box * dpi)
      local br, bg, bb = img:getPixel(x0, y0)
      for yy = y0, y0 + n - 1, 2 do
        for xx = x0, x0 + n - 1, 2 do
          if xx < img:getWidth() and yy < img:getHeight() then
            local r, g, b = img:getPixel(xx, yy)
            total = total + 1
            if math.abs(r - br) + math.abs(g - bg) + math.abs(b - bb) > 0.15 then
              lit = lit + 1
            end
          end
        end
      end
    end
    print(("[2436] preview pic %d box=%d lit=%d/%d"):format(i, f.box, lit, total))
    expect(total > 0 and lit >= total * 0.1, "2436_preview_pic_" .. i .. "_not_blank",
      ("%d/%d"):format(lit, total))
  end
  if not previewed then
    love.event.quit(1)
    return
  end

  local confirmed = OnlinePanel.tradeModalConfirm(imp)
  print("[2436] confirm status: " .. tostring(tr.status))
  expect(confirmed, "2436_confirm", tr.status)
  step(20)
  shot("2436_trade_result.png")

  local frSlot = TeamPick.readSlot("firered", "slot1")
  local lgSlot = TeamPick.readSlot("leafgreen", "slot1")
  local frMon = frSlot and frSlot.party[1]
  local lgMon = lgSlot and lgSlot.party[1]
  print(("[2436] firered party1 species=%s item=%s ot=%s friendship=%s"):format(
    tostring(frMon and frMon.species), tostring(frMon and frMon.item),
    tostring(frMon and frMon.otName), tostring(frMon and frMon.friendship)))
  print(("[2436] leafgreen party1 species=%s nick=%s ot=%s friendship=%s"):format(
    tostring(lgMon and lgMon.species), tostring(lgMon and lgMon.nickname),
    tostring(lgMon and lgMon.otName), tostring(lgMon and lgMon.friendship)))
  expect(frMon and frMon.species == 208, "2436_fr_got_steelix", frMon and frMon.species)
  expect(frMon and (tonumber(frMon.item) or 0) == 0, "2436_metal_coat_used", frMon and frMon.item)
  expect(frMon and frMon.otName == "LEAF", "2436_fr_ot_kept", frMon and frMon.otName)
  expect(frMon and frMon.friendship == 70, "2436_fr_friendship_70", frMon and frMon.friendship)
  expect(lgMon and lgMon.species == 65, "2436_lg_got_alakazam", lgMon and lgMon.species)
  expect(lgMon and lgMon.nickname == "ABRA CAD", "2436_lg_nickname_kept", lgMon and lgMon.nickname)
  expect(lgMon and lgMon.otName == "RED", "2436_lg_ot_kept", lgMon and lgMon.otName)
  local function same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return a == b end
    for k, v in pairs(a) do if not same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
  end
  for _, pair in ipairs({ { "fr", frMon, lgBefore }, { "lg", lgMon, frBefore } }) do
    local got, was = pair[2] or {}, pair[3] or {}
    expect(got.personality == was.personality and got.otId == was.otId,
      "2436_" .. pair[1] .. "_personality_otid_kept")
    expect(same(got.moves, was.moves) and same(got.pp, was.pp),
      "2436_" .. pair[1] .. "_moves_kept")
    expect(same(got.ivs, was.ivs) and same(got.evs, was.evs),
      "2436_" .. pair[1] .. "_ivs_evs_kept")
  end
  local frDex = frSlot and frSlot.save.dex or {}
  local lgDex = lgSlot and lgSlot.save.dex or {}
  expect((frDex.owned or {})[95] and (frDex.owned or {})[208], "2436_fr_dex_onix_steelix")
  expect((lgDex.owned or {})[64] and (lgDex.owned or {})[65], "2436_lg_dex_kadabra_alakazam")
  local Schema = require("src.core.game3.save_schema_firered")
  expect(pcall(Schema.fromSaveTable, frSlot and frSlot.save), "2436_fr_save_loads")
  expect(pcall(Schema.fromSaveTable, lgSlot and lgSlot.save), "2436_lg_save_loads")
  for _, pair in ipairs({ { "fr", frSlot, "LEAF" }, { "lg", lgSlot, "RED" } }) do
    local save = pair[2] and pair[2].save or {}
    local stats = type(save.gameStats) == "table" and save.gameStats or {}
    -- pokefirered/src/trade_scene.c:2606
    expect(tonumber(stats[21]) == 1, "2436_" .. pair[1] .. "_trade_stat", stats[21])
    local scenes = save.questLog and save.questLog.scenes or {}
    local scene = scenes[#scenes]
    local ev = scene and scene.events[#scene.events]
    print(("[2436] %s quest log %s S1=%s S2=%s S3=%s"):format(pair[1], tostring(ev and ev.key),
      tostring(ev and ev.args.S1), tostring(ev and ev.args.S2), tostring(ev and ev.args.S3)))
    -- pokefirered/src/trade_scene.c:2605
    expect(ev and ev.key == "TradedMon1ForPersonsMon2" and ev.args.S1 == pair[3],
      "2436_" .. pair[1] .. "_quest_log_link_traded", ev and ev.key)
  end

  love.event.quit(failed and 1 or 0)
end
