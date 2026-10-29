package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local GameVersion = require("src.core.GameVersion")
local Strings = require("src.core.Strings")
local OptionsMenu = require("src.ui.OptionsMenu")
local BindingsMenu = require("src.ui.BindingsMenu")

local function newGame()
  local stack = { items = {} }
  function stack:push(s) self.items[#self.items + 1] = s end
  function stack:pop() return table.remove(self.items) end
  function stack:top() return self.items[#self.items] end
  local game = { data = {}, save = { options = {}, party = {},
                                     flags = {}, inventory = {} } }
  game.stack = stack
  game.input = { wasPressed = function() return false end,
                 isDown = function() return false end }
  function game:writeOptions() end
  return game
end

for _, version in ipairs({ "red", "blue", "yellow" }) do
  GameVersion.set(version)
  local game = newGame()
  local menu = OptionsMenu.new(game)
  local controls
  for _, row in ipairs(menu.view) do
    if row.id == "controls" then controls = row end
  end
  check(controls ~= nil, version .. ": CONTROLS card on the top level")
  if controls then
    local value = controls.value and controls.value(game)
    check(type(value) == "string" and value ~= "",
      version .. ": CONTROLS card has a second line")
    eq(value, Strings("%d OPTIONS", #BindingsMenu.BUTTONS),
      version .. ": CONTROLS caption counts the bindings screen rows")
    for _, row in ipairs(menu.view) do
      if row.group then
        local caption = row.value and row.value(game) or ""
        check(caption:match("^%d+ OPTIONS$") ~= nil,
          version .. ": " .. row.id .. " caption shape is N OPTIONS")
      end
    end
    eq(controls.step, nil, version .. ": CONTROLS still has no left/right step")
    controls.activate(game)
    check(getmetatable(game.stack:top()) == BindingsMenu,
      version .. ": CONTROLS still opens the bindings screen")
  end
end

local RomText = require("src.core.game3.rom_text")
RomText.at = function(n, i) return n .. "[" .. tostring(i) .. "]" end
RomText.count = function() return 0 end
RomText.plain = function(k) return tostring(k) end
local Rows = require("src.ui.game3.option_rows")

for _, version in ipairs({ "firered", "leafgreen", "emerald", "ruby", "sapphire" }) do
  GameVersion.set(version)
  local ctx = { options = {}, game = { options = {} }, session = {} }
  local view = Rows.group(Rows.build(ctx), function() end)
  local controls
  for _, row in ipairs(view) do
    if row.id == "controls" then controls = row end
  end
  check(controls ~= nil, version .. ": CONTROLS row on the Gen 3 option list")
  if controls then
    local value = controls.value and controls.value(ctx)
    eq(value, Strings("%d OPTIONS", #BindingsMenu.GEN3_BUTTONS),
      version .. ": CONTROLS caption counts the Gen 3 bindings screen rows")
    for _, row in ipairs(view) do
      if row.group then
        local caption = row.value and row.value(ctx) or ""
        check(caption:match("^%d+ OPTIONS$") ~= nil,
          version .. ": " .. row.id .. " caption shape is N OPTIONS")
      end
    end
    eq(controls.step, nil, version .. ": CONTROLS still has no left/right step")
  end
end

T.finish("options controls caption f3")
