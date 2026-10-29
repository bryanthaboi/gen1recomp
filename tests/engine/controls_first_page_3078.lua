package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local OptionRows = require("src.ui.OptionRows")
local Gen1Options = require("src.ui.OptionsMenu")
local Gen2Options = require("src.ui.gen2.OptionsMenu")
local LauncherSettings = require("src.import.LauncherSettings")

local function newStack()
  local stack = { items = {} }
  function stack:push(s) self.items[#self.items + 1] = s end
  function stack:pop() return table.remove(self.items) end
  function stack:top() return self.items[#self.items] end
  return stack
end

local function gen1Game()
  local game = { data = {}, save = { options = {}, party = {},
                                     flags = {}, inventory = {} } }
  game.stack = newStack()
  game.input = { wasPressed = function() return false end,
                 isDown = function() return false end }
  function game:writeOptions() end
  return game
end

local function gen2Game()
  local game = { data = { audio = { sfx = {} } }, options = {} }
  game.stack = newStack()
  game.input = { wasPressed = function() return false end }
  return game
end

local function indexOf(view, id)
  for i, row in ipairs(view) do
    if row.id == id then return i end
  end
end

local realGetOS = love.system.getOS
local realGetenv = os.getenv

local function withPlatform(osName, touchEnv, fn)
  love.system.getOS = function() return osName end
  os.getenv = function(k)
    if k == "POKEPORT_TOUCH" then return touchEnv end
    return realGetenv(k)
  end
  local ok, err = pcall(fn)
  love.system.getOS = realGetOS
  os.getenv = realGetenv
  if not ok then error(err, 0) end
end

local platforms = {
  { "OS X", "0" }, { "OS X", "1" }, { "Android", nil }, { "iOS", nil },
}

for _, p in ipairs(platforms) do
  local tag = p[1] .. " touch=" .. tostring(p[2])
  withPlatform(p[1], p[2], function()
    for _, version in ipairs({ "red", "blue", "yellow" }) do
      GameVersion.set(version)
      local menu = Gen1Options.new(gen1Game())
      local i = indexOf(menu.view, "controls")
      check(i ~= nil, version .. " " .. tag .. ": CONTROLS is on the top level")
      check(i and i <= OptionRows.VISIBLE,
        version .. " " .. tag .. ": CONTROLS within the first "
        .. OptionRows.VISIBLE .. " rows (got " .. tostring(i) .. ")")
      eq(OptionRows.clampScroll(i or 99, 0, #menu.view, #menu.view + 1), 0,
        version .. " " .. tag .. ": cursor on CONTROLS needs no scroll")
      for _, id in ipairs({ "group.speed", "group.video", "group.graphics",
                            "group.audio", "performance", "group.battle",
                            "group.extras", "mods" }) do
        check(indexOf(menu.view, id) ~= nil,
          version .. " " .. tag .. ": " .. id .. " still on the top level")
      end
      eq(indexOf(menu.view, "group.speed"), 1,
        version .. " " .. tag .. ": SPEED still leads")
    end

    for _, version in ipairs({ "gold", "silver", "crystal" }) do
      GameVersion.set(version)
      local game = gen2Game()
      local menu = Gen2Options.new(game, { options = game.options })
      local view = menu:visible()
      local i = indexOf(view, "controls")
      check(i ~= nil, version .. " " .. tag .. ": CONTROLS is on the top level")
      menu.index, menu.scroll = 1, 0
      menu:ensureVisible()
      local firstPage = menu:layout(0)
      local onFirst = false
      for _, entry in ipairs(firstPage) do
        if entry.index == i then onFirst = true end
      end
      check(onFirst, version .. " " .. tag .. ": CONTROLS drawn on the first page ("
        .. #firstPage .. " rows, CONTROLS at " .. tostring(i) .. ")")
      eq(firstPage[2] and firstPage[2].row.id, "controls",
        version .. " " .. tag .. ": CONTROLS second on the first page")
      menu.index = i or #view
      menu.scroll = 0
      menu:ensureVisible()
      eq(menu.scroll, 0, version .. " " .. tag .. ": cursor on CONTROLS needs no scroll")
      for _, id in ipairs({ "group.speed", "group.video", "group.graphics",
                            "group.audio", "performance", "group.battle",
                            "group.extras" }) do
        check(indexOf(view, id) ~= nil,
          version .. " " .. tag .. ": " .. id .. " still on the top level")
      end
      eq(indexOf(view, "group.speed"), 1,
        version .. " " .. tag .. ": SPEED still leads")
      check(view[#view].cancel == true, version .. " " .. tag .. ": BACK stays last")
    end
  end)
end

local RomText = require("src.core.game3.rom_text")
RomText.at = function() return "ROW" end
RomText.count = function() return 3 end
RomText.plain = function() return "TEXT" end
local Kit = require("src.ui.game3.rse.scene_kit")
local rsRows = {}
for i, t in ipairs({ "TEXT SPEED", "BATTLE SCENE", "BATTLE STYLE", "SOUND",
                     "BUTTON MODE", "FRAME", "CANCEL" }) do
  rsRows[i] = { text = t, x = 32, y = 24 + i * 16, choices = {} }
end
Kit.manifest = function(sub)
  if sub == "rse/menus" then
    return { layout = "rs", option = { rows = rsRows, title = "OPTION" } }
  end
end
require("src.ui.game3.chrome").setFrameType = function() end
local Screens = require("src.ui.game3.screens")
local Stack = require("src.ui.game3.stack")

local GEN3_VISIBLE_ROWS = 7

local function gen3Input(key)
  return { wasPressed = function(_, k) return k == key end }
end

local gen3Menus = {
  ["src.ui.game3.option_menu"] = {
    top = function(m) return m._pages[1] end,
    down = function(m) m.move(1) end,
  },
  ["src.ui.game3.rse.option_menu"] = {
    top = function(m) return m._st.pages[1] end,
    down = function(m) m.handleInput(gen3Input("down")) end,
  },
  ["src.ui.game3.rs.option_menu"] = {
    top = function(m) return m._pages[1] end,
    down = function(m) m.handleInput(gen3Input("down")) end,
    settle = function(m) for _ = 1, 40 do m.update() end end,
  },
}

for _, p in ipairs(platforms) do
  local tag = p[1] .. " touch=" .. tostring(p[2])
  withPlatform(p[1], p[2], function()
    for _, version in ipairs({ "firered", "leafgreen", "emerald", "ruby", "sapphire" }) do
      local session = { version = version }
      local path = Screens.path("option", session)
      local how = gen3Menus[path]
      check(how ~= nil, version .. " " .. tag .. ": OPTION routes to a known menu (" .. tostring(path) .. ")")
      if how then
        Stack.clear()
        local menu = require(path)
        local game = { options = {}, writeOptions = function() end }
        menu.show({ game = game, session = { version = version, engineOptions = game.options } })
        if how.settle then how.settle(menu) end
        local top = how.top(menu)
        local i = indexOf(top.rows, "controls")
        check(i ~= nil, version .. " " .. tag .. ": CONTROLS is on the top level")
        check(i and i <= GEN3_VISIBLE_ROWS,
          version .. " " .. tag .. ": CONTROLS within the first "
          .. GEN3_VISIBLE_ROWS .. " rows (got " .. tostring(i) .. ")")
        for _ = 1, (i or #top.rows) - 1 do how.down(menu) end
        eq(top.index, i, version .. " " .. tag .. ": cursor reaches CONTROLS")
        eq(top.scroll, 0, version .. " " .. tag .. ": cursor on CONTROLS needs no scroll")
        for _, id in ipairs({ "group.speed", "group.video", "group.graphics",
                              "group.audio", "group.battle", "group.extras",
                              "buttonMode", "mods" }) do
          check(indexOf(top.rows, id) ~= nil,
            version .. " " .. tag .. ": " .. id .. " still on the top level")
        end
        eq(indexOf(top.rows, "group.speed"), 1,
          version .. " " .. tag .. ": SPEED still leads")
        menu.close()
        Stack.clear()
      end
    end
  end)
end

local function findRow(model, label)
  for _, section in ipairs(model.sections) do
    for _, row in ipairs(section.rows) do
      if row.label == label then return row end
    end
  end
end

local TouchControls = require("src.core.TouchControls")
local Gen2Save = require("src.core.gen2.Save")
local Game3 = require("src.core.Game3")

local function same(a, b)
  if type(a) ~= "table" or type(b) ~= "table" then return a == b end
  for k, v in pairs(a) do if not same(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local STOCK = TouchControls.normalizeConfig(nil).layouts

local function dragged(x)
  return { landscape = { positions = { dpad = { x = x, y = 0.5 } }, scale = 1.3 } }
end

local function seedTouch(opts)
  opts.bindings = { a = { key = "z" } }
  opts.touchControls = { enabled = false, skin = "gb_anim", layouts = dragged(0.9) }
  opts.gold = type(opts.gold) == "table" and opts.gold or {}
  opts.gold.bindings = { speedUp = false, b = { key = "x" } }
  opts.gold.touchControls = { layouts = dragged(0.5) }
  opts.game3 = { touchControls = { layouts = dragged(0.3) } }
end

local function gen1Layout(opts)
  return TouchControls.normalizeConfig(opts.touchControls).layouts
end

local function gen2Layout(opts)
  return TouchControls.normalizeConfig(Gen2Save.touchControls(opts)).layouts
end

local function gen3Config(opts)
  local got
  local game = setmetatable({
    touchControls = { applyOptions = function(_, o) got = o end },
  }, { __index = Game3 })
  Game3.applyTouchOptions(game, opts)
  return TouchControls.normalizeConfig(got and got.touchControls)
end

local function resetOn(version, mutate)
  local model = LauncherSettings.open({}, version)
  local reset = findRow(model, "RESET REBINDS")
  check(reset ~= nil and type(reset.action) == "function",
    version .. " gear offers RESET REBINDS")
  seedTouch(model.opts)
  if mutate then mutate(model.opts) end
  local before = {
    red = gen1Layout(model.opts),
    gold = gen2Layout(model.opts),
    g3 = gen3Config(model.opts).layouts,
  }
  if reset then reset.action() end
  return model.opts, before
end

for _, version in ipairs({ "gold", "silver", "crystal" }) do
  local opts, before = resetOn(version)
  eq(opts.gold.bindings, nil, version .. " reset clears gold.bindings")
  check(type(opts.bindings) == "table" and opts.bindings.a ~= nil,
    version .. " reset leaves the Gen 1 bindings alone")
  check(same(gen2Layout(opts), STOCK), version .. " reset puts Gen 2 on the stock layout")
  check(same(gen1Layout(opts), before.red), version .. " reset leaves the Red layout alone")
  check(same(gen3Config(opts).layouts, before.g3),
    version .. " reset leaves the Gen 3 layout alone")
  eq(opts.touchControls.enabled, false, version .. " reset keeps the TOUCH PAD switch")
  eq(opts.touchControls.skin, "gb_anim", version .. " reset keeps the skin")

  opts = resetOn(version, function(o)
    o.gold.touchControls = { positions = { dpad = { x = 0.5, y = 0.5 } }, scale = 1.4 }
  end)
  check(same(gen2Layout(opts), STOCK),
    version .. " reset clears a migrated legacy positions layout")
end

for _, version in ipairs({ "red", "blue", "yellow" }) do
  local opts, before = resetOn(version)
  eq(opts.bindings, nil, version .. " reset clears the Gen 1 bindings")
  check(same(gen1Layout(opts), STOCK), version .. " reset puts Gen 1 on the stock layout")
  check(opts.gold.bindings and opts.gold.bindings.speedUp == false,
    version .. " reset leaves gold.bindings alone")
  check(same(gen2Layout(opts), before.gold), version .. " reset leaves the Gold layout alone")
  check(same(gen3Config(opts).layouts, before.g3),
    version .. " reset leaves the Gen 3 layout alone")
  eq(opts.touchControls.enabled, false, version .. " reset keeps the TOUCH PAD switch")
  eq(opts.touchControls.skin, "gb_anim", version .. " reset keeps the skin")

  opts = resetOn(version, function(o)
    o.touchControls.layouts = nil
    o.touchControls.positions = { dpad = { x = 0.9, y = 0.1 } }
    o.touchControls.scale = 1.4
  end)
  check(same(gen1Layout(opts), STOCK),
    version .. " reset clears a legacy positions layout")
end

for _, version in ipairs({ "firered", "leafgreen", "emerald", "ruby", "sapphire" }) do
  local opts, before = resetOn(version)
  eq(opts.bindings, nil, version .. " reset clears the flat bindings Gen 3 reads")
  local cfg = gen3Config(opts)
  check(same(cfg.layouts, STOCK), version .. " reset puts Gen 3 on the stock layout")
  eq(cfg.enabled, false, version .. " reset keeps the TOUCH PAD switch")
  eq(cfg.skin, "gb_anim", version .. " reset keeps the skin")
  check(same(gen1Layout(opts), before.red), version .. " reset leaves the Red layout alone")
  check(opts.gold.bindings and opts.gold.bindings.speedUp == false,
    version .. " reset leaves gold.bindings alone")
  check(same(gen2Layout(opts), before.gold), version .. " reset leaves the Gold layout alone")

  opts = resetOn(version, function(o) o.game3 = nil end)
  check(same(gen3Config(opts).layouts, STOCK),
    version .. " reset without a game3 block does not fall back to the Red layout")
end

T.finish("controls first page 3078")
