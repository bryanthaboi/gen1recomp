local U = require("tests.drivers.util")

return function(game)
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/shots_1951"
  os.execute('mkdir -p "' .. DIR .. '" 2>/dev/null')
  local fails = 0
  local function check(label, cond)
    print((cond and "PASS " or "FAIL ") .. label)
    if not cond then fails = fails + 1 end
    return cond
  end

  local ok, err = xpcall(function()
    U.wait(30)
    package.path = package.path .. ";./tools/save-editor/?.lua;./tools/save-editor/panels/?.lua"
    local SaveData = require("src.core.SaveData")
    local App = require("tools.save-editor.App")
    local Kit = require("Kit")

    local W, H = 1280, 720
    local realDim = love.graphics.getDimensions
    local realSafe = love.window.getSafeArea
    local canvas = love.graphics.newCanvas(W, H)

    local rects = {}
    local realButton = Kit.button
    Kit.button = function(x, y, w, h, label, opts)
      if label == "PC" or label == "BAG" then
        rects[#rects + 1] = { label = label, x = x, y = y, w = w, h = h,
          enabled = not (opts and opts.enabled == false) }
      end
      return realButton(x, y, w, h, label, opts)
    end

    local function frame(shotName)
      rects = {}
      love.graphics.getDimensions = function() return W, H end
      love.window.getSafeArea = function() return 0, 0, W, H end
      love.graphics.push("all")
      love.graphics.setCanvas(canvas)
      love.graphics.clear(0, 0, 0, 1)
      App.draw()
      love.graphics.setCanvas()
      love.graphics.pop()
      love.graphics.getDimensions = realDim
      love.window.getSafeArea = realSafe
      if shotName then
        local fd = canvas:newImageData():encode("png")
        local f = io.open(DIR .. "/" .. shotName .. ".png", "wb")
        if f then f:write(fd:getString()) f:close() end
      end
      U.wait(1)
    end

    local function find(label)
      for _, r in ipairs(rects) do
        if r.label == label then return r end
      end
    end

    local function click(r)
      App.mousepressed(r.x + r.w / 2, r.y + r.h / 2, 1)
      frame()
    end

    local seed = SaveData.newGame()
    seed.inventory, seed.bagOrder = { POTION = 30 }, { "POTION" }
    local fill = { "ANTIDOTE", "BURN_HEAL", "ICE_HEAL", "AWAKENING", "PARLYZ_HEAL",
      "FULL_HEAL", "REVIVE", "MAX_REVIVE", "ESCAPE_ROPE", "REPEL", "SUPER_REPEL",
      "MAX_REPEL", "FIRE_STONE", "THUNDER_STONE", "WATER_STONE", "LEAF_STONE",
      "MOON_STONE", "RARE_CANDY", "NUGGET" }
    for _, id in ipairs(fill) do
      seed.inventory[id] = 1
      seed.bagOrder[#seed.bagOrder + 1] = id
    end
    seed.pcItems = { POTION = 90, ULTRA_BALL = 5 }
    local path = os.tmpname() .. "-bug1951.lua"
    local f = assert(io.open(path, "wb")); f:write(SaveData.encode(seed)); f:close()

    App.load(path, { version = "red", embedded = true })
    local S = App.getState()
    S.tab = "items"
    frame(); frame("1951_01_items_tab_before_move")

    local bagCount = 0
    for _, id in ipairs(S.save.bagOrder or {}) do bagCount = bagCount + 1 end
    check("1951 bag starts at 20/20 slots", bagCount == 20)
    local pcBtn = find("PC")
    local bagBtn = find("BAG")
    check("1951 bag rows carry a PC button", pcBtn ~= nil and pcBtn.enabled)
    check("1951 PC rows carry a BAG button", bagBtn ~= nil)

    if pcBtn then
      click(pcBtn)
      frame("1951_02_potion_moved_21_left")
      check("1951 PC POTION tops out at 99", S.save.pcItems.POTION == 99)
      check("1951 bag POTION keeps the 21 that did not fit", S.save.inventory.POTION == 21)
      check("1951 status names the remainder: " .. tostring(S.status),
        tostring(S.status):find("21 left in the bag", 1, true) ~= nil)
    end

    S.pcSort = "name"
    frame()
    local ultra
    local order = require("Ops").pcOrder(S)
    local ultraIdx
    for i, id in ipairs(order) do if id == "ULTRA_BALL" then ultraIdx = i end end
    local bagRects = {}
    for _, r in ipairs(rects) do if r.label == "BAG" then bagRects[#bagRects + 1] = r end end
    ultra = ultraIdx and bagRects[ultraIdx]
    check("1951 ULTRA_BALL row has a BAG button", ultra ~= nil)
    if ultra then
      click(ultra)
      frame("1951_03_bag_full_refused")
      check("1951 full bag refuses ULTRA_BALL", S.save.inventory.ULTRA_BALL == nil
        and S.save.pcItems.ULTRA_BALL == 5)
      check("1951 status says the bag is full: " .. tostring(S.status),
        tostring(S.status):find("Bag is full", 1, true) ~= nil)
      require("Ops").bagDrop(S, "NUGGET")
      frame()
      bagRects = {}
      for _, r in ipairs(rects) do if r.label == "BAG" then bagRects[#bagRects + 1] = r end end
      order = require("Ops").pcOrder(S)
      for i, id in ipairs(order) do if id == "ULTRA_BALL" then ultraIdx = i end end
      ultra = bagRects[ultraIdx]
      if ultra then click(ultra) end
      frame("1951_04_ultra_ball_withdrawn")
      check("1951 ULTRA_BALL withdraws once a slot frees",
        S.save.inventory.ULTRA_BALL == 5 and S.save.pcItems.ULTRA_BALL == nil)
    end

    W, H = 500, 800
    canvas = love.graphics.newCanvas(W, H)
    frame(); frame()
    pcBtn = find("PC")
    if pcBtn and pcBtn.y > H - 60 then
      S.itemsScroll = pcBtn.y - 160
      frame(); frame()
    end
    frame("1951_05_phone_layout_move_buttons")
    pcBtn = find("PC")
    check("1951 phone layout keeps the PC button inside the row", pcBtn ~= nil
      and pcBtn.x >= 0 and pcBtn.x + pcBtn.w <= W)

    Kit.button = realButton
    App.unload()
    os.remove(path)
  end, debug.traceback)
  if not ok then
    print("FAIL 1951 driver error " .. tostring(err))
    fails = fails + 1
  end
  if fails == 0 then print("PASS save_editor_item_move_bug1951") end
  love.event.quit(fails == 0 and 0 or 1)
end
