#!/usr/bin/env luajit
package.path = "./?.lua;./?/init.lua;" .. package.path
local function romTextKey(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end
local function romTextPlain(key) return key end
package.loaded["src.core.game3.rom_text"] = {
  plain = romTextPlain, box = romTextPlain, ascii = romTextPlain, has = function() return true end,
  key = romTextKey, at = function(n, i, j) return romTextKey(n, i, j) end,
  count = function() return 0 end, list = function() return {} end,
  lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
  overrides = {}, ir = function() return {} end,
}

local love = _G.love or require("tests.love_stub")
_G.love = love

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local function try(label, fn)
  local ok, err = pcall(fn)
  if not ok then
    failed = failed + 1
    print("[FAIL] " .. label .. " raised: " .. tostring(err))
  end
end

local Input = require("src.core.Input")
local Stack = require("src.ui.game3.stack")
local Rows = require("src.ui.game3.option_rows")
local BindingsMenu = require("src.ui.BindingsMenu")

local function tap(btn)
  Input:sourcePress(btn, "test")
  Input:sourceRelease(btn, "test")
end

local function stepInput()
  Input:step()
end

local function newGame()
  local g = { options = {}, input = Input, wrote = 0, written = nil }
  function g:writeOptions()
    self.wrote = self.wrote + 1
    local copy = {}
    for k, v in pairs(self.options.bindings or {}) do
      copy[k] = type(v) == "table" and { key = v.key, pad = v.pad } or v
    end
    self.written = copy
  end
  return g
end

local function ctxFor(game)
  return {
    options = game.options,
    game = game,
    session = {},
  }
end

print("[test] 1. CONTROLS row exists and sits on the first page")
try("rows", function()
  local game = newGame()
  local flat = Rows.build(ctxFor(game))
  local row
  for _, r in ipairs(flat) do if r.id == "controls" then row = r end end
  check(row ~= nil, "Rows.build has a controls row")
  check(row and row.activate ~= nil and row.step == nil, "controls row is activate-only")
  local view = Rows.group(flat, function() end)
  local si, ci
  for i, r in ipairs(view) do
    if r.id == "group.speed" then si = i end
    if r.id == "controls" then ci = i end
  end
  check(ci ~= nil and ci <= 7, "grouped view puts controls on the first 7-row page")
  check(si and ci and ci == si + 1, "grouped view puts controls right after SPEED")
  check(require("src.ui.game3.screens").DEFAULT.controls == "src.ui.game3.controls_menu",
    "controls registered in Screens.DEFAULT")
end)

print("[test] 2. FRLG option menu A on CONTROLS opens the screen")
try("frlg", function()
  Input:init()
  Stack.clear()
  local game = newGame()
  local OptionMenu = require("src.ui.game3.option_menu")
  OptionMenu.show({ game = game })
  local p = OptionMenu._pages[#OptionMenu._pages]
  for i, r in ipairs(p.rows) do if r.id == "controls" then p.index = i end end
  check(p.rows[p.index] and p.rows[p.index].id == "controls", "FRLG top page lists CONTROLS")
  OptionMenu.confirm()
  check(Stack.top() and Stack.top().id == "controls", "FRLG confirm pushes the controls screen")
  local Controls = require("src.ui.game3.controls_menu")
  Controls.close()
  check(Stack.top() and Stack.top().id == "option", "closing returns to the option menu")
  OptionMenu.close()
  Stack.clear()
end)

print("[test] 3. Emerald option menu A on CONTROLS opens the screen")
try("emerald", function()
  Input:init()
  Stack.clear()
  local game = newGame()
  local Em = require("src.ui.game3.rse.option_menu")
  Em.show({ game = game })
  local p = Em._st.pages[#Em._st.pages]
  for i, r in ipairs(p.rows) do if r.id == "controls" then p.index = i end end
  check(p.rows[p.index] and p.rows[p.index].id == "controls", "Emerald top page lists CONTROLS")
  Em.handleInput({ wasPressed = function(_, b) return b == "a" end })
  check(Stack.top() and Stack.top().id == "controls", "Emerald A pushes the controls screen")
  require("src.ui.game3.controls_menu").close()
  Em.close()
  Stack.clear()
end)

local Controls = require("src.ui.game3.controls_menu")

local function rowIndex(id)
  for i, it in ipairs(Controls._bm.items) do
    if it.button.id == id then return i end
  end
end

print("[test] 4. Gen 3 rows: L/R and trigger speed buttons")
try("gen3 rows", function()
  Input:init()
  Stack.clear()
  local game = newGame()
  Controls.show({ game = game, options = game.options })
  local bm = Controls._bm
  check(#bm.items == 12, "12 rows on Gen 3")
  check(rowIndex("l") and rowIndex("r"), "L and R rows present")
  check(bm.items[rowIndex("l")].right == "Q/LB", "L shows Q/LB (got " .. tostring(bm.items[rowIndex("l")].right) .. ")")
  check(bm.items[rowIndex("speedUp")].right == "1/R2", "SPEED + shows 1/R2")
  check(bm.items[rowIndex("speedDown")].right == "0/L2", "SPEED - shows 0/L2")
  try("draw", function() Controls.draw() end)
  Controls.close()
end)

print("[test] 5. Rebind persists into options and applies on close")
try("rebind", function()
  Input:init()
  Stack.clear()
  local game = newGame()
  Controls.show({ game = game, options = game.options })
  local bm = Controls._bm
  bm.index = rowIndex("l")
  tap("a"); stepInput(); Controls.handleInput(Input)
  check(bm.capture ~= nil and Input.captureArmed, "A arms the capture")
  try("capture draw", function() Controls.draw() end)
  Input:keypressed("k"); stepInput(); Controls.handleInput(Input)
  Input:keyreleased("k"); stepInput(); Controls.handleInput(Input)
  check(game.options.bindings and game.options.bindings.l and game.options.bindings.l.key == "k",
    "options.bindings.l.key == k")
  check(game.wrote >= 1 and game.written and game.written.l and game.written.l.key == "k",
    "writeOptions persisted the rebind")
  check(Input.keyBindings.k == nil, "live map waits for close")
  tap("b"); stepInput(); Controls.handleInput(Input)
  check(not Controls.open and not Stack.has("controls"), "B closes the screen")
  check(Input.keyBindings.k == "l", "close applies K = L to the live map")
  Input:init()
  Input:applyBindings(game.written)
  check(Input.keyBindings.k == "l", "reloaded options reach the same map")
end)

print("[test] 6. Touch B cancels a pending capture")
try("touch cancel", function()
  Input:init()
  Stack.clear()
  local game = newGame()
  Controls.show({ game = game, options = game.options })
  local bm = Controls._bm
  tap("a"); stepInput(); Controls.handleInput(Input)
  check(bm.capture ~= nil, "capture armed")
  Input:overlayPressed("b"); stepInput(); Controls.handleInput(Input)
  Input:overlayReleased("b")
  check(bm.capture == nil and not Input.captureArmed, "touch B disarms the capture")
  check(Controls.open, "screen stays open")
  check(game.options.bindings == nil, "no binding written")
  Input:keypressed("x"); stepInput(); Controls.handleInput(Input)
  Input:keyreleased("x")
  check(not Controls.open, "keyboard B still closes when no capture is armed")
end)

print("[test] 7. START then YES clears every binding")
try("reset", function()
  Input:init()
  Stack.clear()
  local game = newGame()
  game.options.bindings = { a = { key = "k" } }
  Controls.show({ game = game, options = game.options })
  tap("start"); stepInput(); Controls.handleInput(Input)
  check(Controls._confirm ~= nil, "START opens the confirm")
  try("confirm draw", function() Controls.draw() end)
  tap("up"); stepInput(); Controls.handleInput(Input)
  tap("a"); stepInput(); Controls.handleInput(Input)
  check(game.options.bindings == nil, "YES clears options.bindings")
  check(Controls.open, "screen stays open after reset")
  Controls.close()
end)

print("[test] 8. Game3 hotkeys and pad speed skip while a capture is armed")
try("hotkeys", function()
  local Game3 = require("src.core.Game3")
  Input:init()
  local hot, speed = 0, 0
  local fake = setmetatable({
    input = Input,
    _hotkey = function() hot = hot + 1 return true end,
    _cycleSpeed = function() speed = speed + 1 end,
  }, { __index = Game3 })
  Game3.keypressed(fake, "1")
  check(hot == 1, "unarmed: 1 runs the hotkey")
  Input:armCapture()
  Game3.keypressed(fake, "1")
  check(hot == 1, "armed: 1 skips the hotkey")
  local ev = Input:takeCaptureEvents()
  check(ev and ev[1] and ev[1].kind == "key" and ev[1].value == "1", "armed: 1 reaches the capture")
  Input:disarmCapture()
  Game3._padPressedBody(fake, nil, "triggerright")
  check(speed == 1, "unarmed: R2 cycles speed")
  Input:armCapture()
  Game3._padPressedBody(fake, nil, "triggerright")
  check(speed == 1, "armed: R2 skips the speed shortcut")
  ev = Input:takeCaptureEvents()
  check(ev and ev[1] and ev[1].kind == "pad" and ev[1].value == "triggerright", "armed: R2 reaches the capture")
  Input:disarmCapture()
  Input:init()
end)

print("[test] 8b. A key bound to a button presses the button, not the hotkey")
try("bound hotkey", function()
  local Game3 = require("src.core.Game3")
  Input:init()
  local hot = 0
  local fake = setmetatable({
    input = Input,
    _hotkey = function() hot = hot + 1 return true end,
  }, { __index = Game3 })
  Input:applyBindings({ l = { key = "1" }, a = { key = "f1" } })
  Game3.keypressed(fake, "1")
  check(hot == 0, "bound 1 skips the hotkey")
  check(Input:isDown("l"), "bound 1 holds L")
  Game3.keyreleased(fake, "1")
  check(not Input:isDown("l"), "releasing 1 releases L")
  Game3.keypressed(fake, "f1")
  check(hot == 0 and Input:isDown("a"), "bound F1 presses A instead of quick save")
  Game3.keyreleased(fake, "f1")
  Game3.keypressed(fake, "2")
  check(hot == 1, "unbound 2 still runs the hotkey")
  Game3.keypressed(fake, "f2")
  check(hot == 2, "unbound F2 still runs the hotkey")
  Input:armCapture()
  Game3.keypressed(fake, "2")
  check(hot == 2, "armed capture still skips the hotkey")
  Input:takeCaptureEvents()
  Input:disarmCapture()
  Input:init()
  Game3.keypressed(fake, "1")
  check(hot == 3, "after reset to defaults 1 is a hotkey again")
  Input:init()
end)

print("[test] 9. Gen 1/2 BindingsMenu rows unchanged")
try("gen1", function()
  local g = { save = { options = {} }, input = Input,
    stack = { push = function() end, pop = function() end } }
  local bm = BindingsMenu.new(g)
  local ids = {}
  for _, it in ipairs(bm.items) do ids[#ids + 1] = it.button.id end
  check(table.concat(ids, ",") == "up,down,left,right,a,b,start,select,speedDown,speedUp",
    "Gen 1 row order unchanged")
  check(bm.rows == 6, "Gen 1 keeps 6 visible rows")
  check(bm.items[9].right == "0/LB" and bm.items[10].right == "1/RB", "Gen 1 speed rows show 0/LB and 1/RB")
end)

print("[test] 9b. Binding the speed key to a button leaves the speed rows alone")
try("speed key swap", function()
  local g = { save = { options = {} }, input = Input,
    stack = { push = function() end, pop = function() end } }
  function g:writeOptions() end
  local bm = BindingsMenu.new(g)
  bm:beginCapture(bm.items[5])
  bm:captureKey("1")
  bm:captureKeyRelease("1")
  local b = g.save.options.bindings
  check(b and b.a and b.a.key == "1", "A takes the 1 key")
  check(b and b.speedUp == nil, "SPEED + keeps its pad binding")
  check(bm.items[10].right == "1/RB", "SPEED + row still reads 1/RB")
  bm:beginCapture(bm.items[6])
  bm:captureKey("0")
  bm:captureKeyRelease("0")
  check(b.speedDown == nil, "SPEED - keeps its pad binding")
  check(b.b and b.b.key == "0", "B takes the 0 key")
  Input:init()
end)

print("[test] 10. controls screen never draws with Gen 1 Font")
do
  local src = io.open("src/ui/game3/controls_menu.lua", "r"):read("*a")
  check(not src:find('require("src.render.Font")', 1, true), "no src.render.Font require")
  check(not src:find("[^%w]Font%.draw"), "no Gen 1 Font.draw call")
end

Stack.clear()
Input:init()
if failed > 0 then
  print(string.format("[FAIL] %d check(s) failed", failed))
  os.exit(1)
end
print("ALL TESTS PASSED")
os.exit(0)
