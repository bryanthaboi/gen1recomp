return function(game)
  local U = dofile("tests/drivers/util.lua")
  local RomImporter = require("src.import.RomImporter")
  local SaveData = require("src.core.SaveData")
  local Loader = require("src.mods.Loader")
  local Kit = require("src.ui.kit.Kit")

  local dir = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR")
    or "/tmp/modorder2177"
  os.execute('mkdir -p "' .. dir .. '" 2>/dev/null')
  local winW = tonumber(os.getenv("DRIVER_W")) or 1024
  local winH = tonumber(os.getenv("DRIVER_H")) or 768
  local tag = winW < 600 and "phone" or "desktop"
  love.window.setMode(winW, winH, { resizable = true, highdpi = true })
  U.wait(2)

  local failed = false
  local function pass(label) print("PASS " .. label) end
  local function fail(label, why)
    failed = true
    print("FAIL " .. label .. (why and (": " .. tostring(why)) or ""))
  end
  local function expect(cond, label, why)
    if cond then pass(label) else fail(label, why) end
  end

  local fs = love.filesystem
  local IDS = { "driver_order_a", "driver_order_b" }
  local NAMES = { driver_order_a = "AAAA", driver_order_b = "BBBB" }
  local function plant()
    for _, id in ipairs(IDS) do
      fs.createDirectory("mods/" .. id)
      fs.write("mods/" .. id .. "/manifest.json", ([[{"id":"%s","name":"Order %s",
        "version":"1.0.0","entry":"main.lua","priority":-100,
        "games":["red","blue","yellow"]}]]):format(id, NAMES[id]))
      fs.write("mods/" .. id .. "/main.lua", ([[
return function(mod)
  mod.content.pokemon:override("PIKACHU", { name = "%s" })
end
]]):format(NAMES[id]))
    end
  end
  local function unplant()
    for _, id in ipairs(IDS) do
      fs.remove("mods/" .. id .. "/manifest.json")
      fs.remove("mods/" .. id .. "/main.lua")
      fs.remove("mods/" .. id)
    end
  end
  local function setOrder(list)
    local opts = SaveData.loadOptions()
    SaveData.setModOrder(opts, list)
    opts.modSort = nil
    SaveData.saveOptions(opts)
  end

  unplant()
  plant()
  setOrder({})

  local imp = RomImporter.new(function() end, { launcher = true })
  imp:_switchTab("mods")
  imp.modSort = "order"
  imp:_refreshMods()
  U.wait(3)

  local buttons = {}
  local realButton = Kit.button
  Kit.button = function(x, y, w, h, label, opts)
    if opts and opts.id then
      buttons[opts.id] = { label = tostring(label), opts = opts, y = y }
    end
    return realButton(x, y, w, h, label, opts)
  end
  local pending = nil
  local drawn = 0
  love.draw = function()
    drawn = drawn + 1
    buttons = {}
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
      local seen = drawn
      repeat coroutine.yield() until drawn > seen
    end
  end
  local function shot(name)
    name = name:gsub("%.png$", "_" .. tag .. ".png")
    pending = dir .. "/" .. name
    for _ = 1, 90 do
      if not pending then break end
      step(1)
    end
    step(3)
    local f = io.open(dir .. "/" .. name, "rb")
    U.log(f and "shot" or "FAIL shot", name)
    if f then f:close() end
  end
  local function press(id)
    local b = buttons[id]
    if not b or b.opts.enabled == false then return false end
    imp:runActions({ { key = id, fn = b.opts.action, keepArm = b.opts.keepArm } })
    return true
  end
  local function visiblePos(id)
    for i, m in ipairs(imp.mods or {}) do
      local n = 0
      for _, o in ipairs(imp.mods) do
        if (o.loadRank or 0) < (m.loadRank or 0) then n = n + 1 end
      end
      if m.id == id then return n + 1 end
    end
  end
  local function savedBefore(a, b)
    local list = SaveData.modOrder(SaveData.loadOptions())
    local ia, ib
    for i, v in ipairs(list) do
      if v == a then ia = i end
      if v == b then ib = i end
    end
    return ia and ib and ia < ib
  end
  local function realBoot()
    local proxy = setmetatable({
      getDirectoryItems = function(path)
        if path == "mods" then return { IDS[1], IDS[2] } end
        return fs.getDirectoryItems(path)
      end,
    }, { __index = fs })
    local base = game and game.data and game.data.pokemon
      and game.data.pokemon.PIKACHU
    local copy = {}
    for k, v in pairs(base or { name = "PIKACHU" }) do copy[k] = v end
    local data = { pokemon = { PIKACHU = copy } }
    local loader = Loader.new({ fs = proxy })
    local ok, err = pcall(loader.load, loader, data)
    if not ok then return nil, nil, err end
    return table.concat(loader.order or {}, ","), data.pokemon.PIKACHU.name
  end

  step(4)
  expect(visiblePos(IDS[1]) == 1 and visiblePos(IDS[2]) == 2,
    "initial_order_by_priority_then_id",
    tostring(visiblePos(IDS[1])) .. "," .. tostring(visiblePos(IDS[2])))
  expect(buttons["mod-up-driver_order_a"] and buttons["mod-down-driver_order_a"],
    "row_has_up_down")
  expect(buttons["mod-up-driver_order_a"]
    and buttons["mod-up-driver_order_a"].opts.enabled == false,
    "first_row_up_disabled")
  local order0, name0 = realBoot()
  expect(order0 == "driver_order_a,driver_order_b" and name0 == "BBBB",
    "loader_default_b_last_wins", tostring(order0) .. " " .. tostring(name0))
  shot("2177_01_mods_sorted_by_load_order.png")

  expect(press("mod-down-driver_order_a"), "press_down_on_a")
  step(4)
  expect(savedBefore(IDS[2], IDS[1]), "saved_order_b_before_a")
  expect(visiblePos(IDS[1]) == 2, "list_shows_a_second")
  expect(imp.modNotice and imp.modNotice.ok
    and tostring(imp.modNotice.text):find("position 2", 1, true),
    "notice_moved_to_position", imp.modNotice and imp.modNotice.text)
  local order1, name1 = realBoot()
  expect(order1 == "driver_order_b,driver_order_a" and name1 == "AAAA",
    "loader_follows_player_order_a_wins", tostring(order1) .. " " .. tostring(name1))
  shot("2177_02_a_moved_down.png")

  imp._modActions = IDS[1]
  step(4)
  expect(buttons["modact-up"] and buttons["modact-down"]
    and buttons["modact-top"] and buttons["modact-bottom"],
    "details_has_move_buttons")
  expect(buttons["modact-top"] and buttons["modact-top"].opts.enabled ~= false,
    "details_move_to_top_enabled")
  shot("2177_03_details_move_buttons.png")
  expect(press("modact-top"), "press_move_to_top")
  step(4)
  imp._modActions = nil
  expect(savedBefore(IDS[1], IDS[2]), "saved_order_a_first_again")
  local order2, name2 = realBoot()
  expect(order2 == "driver_order_a,driver_order_b" and name2 == "BBBB",
    "loader_swapped_back_b_wins", tostring(order2) .. " " .. tostring(name2))

  imp._sortPopup = "mods"
  step(4)
  expect(buttons["sortpop-order"] ~= nil and buttons["sortpop-reset-order"] ~= nil,
    "sort_modal_offers_load_order_and_reset")
  expect(press("sortpop-reset-order"), "press_reset_order")
  step(4)
  expect(#SaveData.modOrder(SaveData.loadOptions()) == 0, "reset_clears_saved_order")

  Kit.button = realButton
  unplant()
  setOrder({})
  U.log("done")
  love.event.quit(failed and 1 or 0)
end
