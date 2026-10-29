package.path = "./?.lua;./?/init.lua;" .. package.path
if not _G.love then _G.love = require("tests.love_stub") end

local T = require("tests.harness")
local check, eq = T.check, T.eq

local ShaderFX = require("src.render.ShaderFX")
local Pipelines = require("src.render.Pipelines")
local RomText = require("src.core.game3.rom_text")
local Rows = require("src.ui.game3.option_rows")
local ShaderFXMenu = require("src.ui.game3.shaderfx_menu")

local saved = {}
local function stub(mod, key, fn)
  saved[#saved + 1] = { mod, key, mod[key] }
  mod[key] = fn
end

stub(RomText, "at", function() return "ROW" end)
stub(RomText, "count", function() return 3 end)
stub(RomText, "plain", function() return "TEXT" end)

local fake = { name = "fake-lcd.slangp", converted = true }
local active = {}
local activated = {}
stub(ShaderFX, "list", function() return { fake } end)
stub(ShaderFX, "canConvert", function() return false end)
stub(ShaderFX, "clearBridgeQuarantine", function() end)
stub(ShaderFX, "activeEntry", function(slot) return active[slot] end)
stub(ShaderFX, "activate", function(slot, entry)
  activated[#activated + 1] = slot
  active[slot] = entry
  return true
end)
stub(ShaderFX, "deactivate", function(slot)
  if slot then active[slot] = nil else active = {} end
end)

local function ids(list)
  local out = {}
  for _, r in ipairs(list) do out[r.id] = r end
  return out
end

do
  local rows = ids(Rows.build({ options = {} }))
  check(rows.shaderfx ~= nil, "Gen 3 OPTION lists SHADER FX")
  check(rows.shaderfx2 ~= nil, "Gen 3 OPTION lists SHADER FX 2")
  local grouped
  for _, g in ipairs(Rows.GROUPS) do
    if g.id == "group.graphics" then grouped = table.concat(g.members, ",") end
  end
  check(grouped and grouped:find("shaderfx2", 1, true) ~= nil,
    "both shader rows sit under GRAPHICS")
  eq(rows.shaderfx.value(), "OFF", "an empty slot reads OFF")
end

local function input(keys)
  local pressed = {}
  for _, k in ipairs(keys) do pressed[k] = true end
  return { wasPressed = function(_, k) return pressed[k] == true end }
end

do
  local writes = 0
  local game = { options = {}, writeOptions = function() writes = writes + 1 end }
  ShaderFXMenu.show({ game = game, slot = "main" })
  check(ShaderFXMenu.isOpen(), "A on SHADER FX opens the picker")
  ShaderFXMenu.handleInput(input({ "down" }))
  ShaderFXMenu.handleInput(input({ "a" }))
  eq(activated[1], "main", "A on a converted preset activates the main slot")
  eq(game.options.shaderfx, "fake-lcd.slangp", "the choice persists under options.shaderfx")
  check(writes >= 1, "the choice is written to options storage")
  check(not ShaderFXMenu.isOpen(), "choosing closes the picker back to OPTION")
  eq(ShaderFXMenu.slotLabel("main"), "FAKE-LCD", "the row shows the preset name")
end

do
  local game = { options = { shaderfxSecondary = "fake-lcd.slangp" }, writeOptions = function() end }
  active.secondary = fake
  ShaderFXMenu.show({ game = game })
  ShaderFXMenu.handleInput(input({ "down" }))
  ShaderFXMenu.handleInput(input({ "a" }))
  check(ShaderFXMenu.isOpen(), "the slot list opens the SHADER FX 2 picker")
  ShaderFXMenu.handleInput(input({ "up" }))
  ShaderFXMenu.handleInput(input({ "a" }))
  check(active.secondary == nil, "OFF clears the secondary slot")
  eq(game.options.shaderfxSecondary, nil, "OFF clears options.shaderfxSecondary")
  check(ShaderFXMenu.isOpen(), "the slot list stays open after a pick")
  ShaderFXMenu.handleInput(input({ "b" }))
  check(not ShaderFXMenu.isOpen(), "B on the slot list closes it")
end

do
  local data = { render_pipelines = {
    grade = { label = "GRADE", present = function(c) return c end },
    voxel = { label = "VOXEL", drawWorld = function() end },
  } }
  Pipelines.install(data)
  local rows = ids(Rows.build({ options = {} }))
  check(rows["pipeline:grade"] ~= nil, "a mod post-process pipeline gets a Gen 3 row")
  -- Gen 3 has a world pass since docs/rfcs/0022, so a world-only pipeline is
  -- a real display mode there and gets its row like any other
  check(rows["pipeline:voxel"] ~= nil, "a world-only pipeline is offered on Gen 3")
  local opts = {}
  rows["pipeline:grade"].step({ options = opts }, 1)
  eq(opts.pipelines and opts.pipelines.grade, 1, "the row persists its level")
  check(Pipelines.wantsPresent(), "the Gen 3 present pass picks the pipeline up")
  Pipelines.install(nil)
end

do
  local Kit = require("src.ui.game3.rse.scene_kit")
  local Stack = require("src.ui.game3.stack")
  local Chrome = require("src.ui.game3.chrome")
  local rsRows = {}
  for i, t in ipairs({ "TEXT SPEED", "BATTLE SCENE", "BATTLE STYLE", "SOUND", "BUTTON MODE", "FRAME", "CANCEL" }) do
    rsRows[i] = { text = t, x = 32, y = 24 + i * 16, choices = {} }
  end
  stub(Kit, "manifest", function(sub)
    if sub == "rse/menus" then return { layout = "rs", option = { rows = rsRows, title = "OPTION" } } end
  end)
  stub(Stack, "push", function() end)
  stub(Stack, "pop", function() end)
  stub(Chrome, "setFrameType", function() end)
  local Menu = require("src.ui.game3.rs.option_menu")
  local writes = 0
  local game = { options = {}, writeOptions = function() writes = writes + 1 end }
  Menu.show({ game = game, session = { version = "ruby", engineOptions = game.options } })
  for _ = 1, 40 do Menu.update() end
  local top = Menu._pages[1]
  local seen = {}
  for i, r in ipairs(top.rows) do seen[r.id] = i end
  local order = {}
  for _, id in ipairs(Rows.ORDER) do if seen[id] then order[#order + 1] = id end end
  for i, id in ipairs(order) do eq(top.rows[i].id, id, "RS OPTION top row " .. i .. " follows Emerald's grouped order") end
  check(seen["group.speed"] and seen["group.graphics"] and seen["group.audio"] and seen["group.battle"]
    and seen["controls"] and seen["mods"], "RS OPTION carries the Emerald pages")
  check(seen["textSpeed"] == nil and seen["sound"] == nil and seen["frameType"] == nil,
    "RS cart rows move into their Emerald groups")
  eq(top.rows[seen["buttonMode"]].native, 5, "BUTTON MODE stays a native cart row on the top page")
  check(seen["eventTickets"] == nil, "RS skips Emerald-only rows")
  Menu.handleInput(input({ "select" }))
  check(not ShaderFXMenu.isOpen(), "SELECT is not a hidden SHADER FX shortcut")
  for _ = 1, seen["group.graphics"] - 1 do Menu.handleInput(input({ "down" })) end
  Menu.handleInput(input({ "a" }))
  local graphics = Menu._pages[#Menu._pages]
  check(#Menu._pages == 2, "A on GRAPHICS opens its page")
  local si, fi
  for i, r in ipairs(graphics.rows) do
    if r.id == "shaderfx" then si = i end
    if r.id == "frameType" and r.native == 6 then fi = i end
  end
  check(fi ~= nil, "RS GRAPHICS carries the native FRAME row")
  check(si ~= nil, "RS GRAPHICS lists SHADER FX")
  for _ = 1, (fi or 1) - 1 do Menu.handleInput(input({ "down" })) end
  Menu.handleInput(input({ "right" }))
  eq(Menu._pending.frameType, 1, "RIGHT on the grouped FRAME row steps the pending frame")
  graphics.index = 1
  for _ = 1, (si or 1) - 1 do Menu.handleInput(input({ "down" })) end
  Menu.handleInput(input({ "a" }))
  check(ShaderFXMenu.isOpen(), "A on the visible SHADER FX row opens the picker")
  ShaderFXMenu.close()
  Menu.handleInput(input({ "b" }))
  check(#Menu._pages == 1, "B on a port page returns to the native list")
  Menu.handleInput(input({ "b" }))
  for _ = 1, 40 do Menu.update() end
  check(not Menu.isOpen(), "B on the native list saves and closes")
end

do
  local Game3 = require("src.core.Game3")
  local applied, deactivated = 0, false
  local okApply = ShaderFX.applyOptions
  local okDeact = ShaderFX.deactivate
  ShaderFX.applyOptions = function() applied = applied + 1 return false end
  ShaderFX.deactivate = function() deactivated = true end
  local game = setmetatable({ options = { performance = "low" } }, { __index = Game3 })
  pcall(Game3.applyOptions, game, game.options)
  eq(applied, 1, "Game3:applyOptions restores the persisted shader presets")
  check(deactivated, "a performance tier without SHADER FX switches it off live")
  ShaderFX.applyOptions, ShaderFX.deactivate = okApply, okDeact
end

for i = #saved, 1, -1 do
  local s = saved[i]
  s[1][s[2]] = s[3]
end

T.finish("game3 shaderfx options")
