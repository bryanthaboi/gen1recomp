#!/usr/bin/env luajit
-- Gen 3 MODS entry + FRLG mod-manager shell (docs/compose/spec/game3-mods-menu.md).
-- ROM-free: pure option rows, start-menu gating, ManagerState row models, and
-- the game3.stack push/close path. No GBA cache required.

package.path = "./?.lua;./?/init.lua;" .. package.path
local function romTextKey(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end
local function romTextPlain(key) return key end
package.loaded["src.core.game3.rom_text"] = {
  plain = romTextPlain, box = romTextPlain, ascii = romTextPlain, has = function() return true end,
  key = romTextKey, at = function(n, i, j) return romTextKey(n, i, j) end,
  count = function() return 0 end, list = function() return {} end,
  lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
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

print("[test] 1. OPTION row is always present with installed count")
local Rows = require("src.ui.game3.option_rows")
local function optionRow(ctx)
  for _, row in ipairs(Rows.build(ctx)) do
    if row.id == "mods" then return row end
  end
  return nil
end

local vanillaCtx = {
  options = { musicVol = 7, sfxVol = 7, musicFilter = 0, buttonMode = 0 },
  game = { modStatus = { available = {} } },
}
local modsRow = optionRow(vanillaCtx)
check(modsRow ~= nil, "mods row present on vanilla install")
check(modsRow and modsRow.activate ~= nil and modsRow.step == nil,
  "mods row is activate-only")
check(modsRow and tostring(modsRow.value(vanillaCtx)):find("0"), 
  "vanilla value reports 0 INSTALLED (got " ..
    tostring(modsRow and modsRow.value(vanillaCtx)) .. ")")

local withModsCtx = {
  options = vanillaCtx.options,
  game = {
    modStatus = {
      available = {
        { id = "a", name = "A", category = "TWEAK", enabled = true, state = "loaded" },
        { id = "b", name = "B", category = "TWEAK", enabled = true, state = "loaded" },
      },
    },
  },
}
local modsRow2 = optionRow(withModsCtx)
check(modsRow2 and tostring(modsRow2.value(withModsCtx)):find("2"),
  "value reports 2 INSTALLED")

local orderHasMods = false
for _, id in ipairs(Rows.ORDER) do
  if id == "mods" then orderHasMods = true end
end
check(orderHasMods, "mods listed in Rows.ORDER")

print("[test] 2. START menu MODS gate (normal field only)")
local StartMenu = require("src.ui.game3.start_menu")
local function entryIds()
  local out = {}
  for _, e in ipairs(StartMenu.ENTRIES or {}) do out[#out + 1] = e.id end
  return out
end
local function hasId(list, id)
  for _, v in ipairs(list) do
    if v == id then return true end
  end
  return false
end

StartMenu._game = { modStatus = { available = {} } }
StartMenu.show({ session = { bag = {}, party = {} }, game = StartMenu._game })
local ids = entryIds()
check(not hasId(ids, "mods"), "vanilla START has no MODS row")
check(hasId(ids, "option") and hasId(ids, "exit"), "vanilla START keeps OPTION/EXIT")
StartMenu.close(true)

StartMenu._game = {
  modStatus = {
    available = {
      { id = "a", name = "A", category = "TWEAK", enabled = true, state = "loaded" },
    },
  },
}
StartMenu.show({ session = { bag = {}, party = {} }, game = StartMenu._game })
ids = entryIds()
check(hasId(ids, "mods"), "START shows MODS when mods are discovered")
local oi, mi, ei
for i, id in ipairs(ids) do
  if id == "option" then oi = i end
  if id == "mods" then mi = i end
  if id == "exit" then ei = i end
end
check(oi and mi and ei and oi < mi and mi < ei, "MODS sits after OPTION, before EXIT")
StartMenu.close(true)

print("[test] 3. Manager list rows come from ManagerState.modRows")
local ManagerState = require("src.mods.ManagerState")
local statusStub = withModsCtx.game.modStatus
local modsStub = {
  status = function() return statusStub end,
}
local mgrGame = {
  modStatus = statusStub,
  mods = modsStub,
  save = { options = {} },
  stack = { pop = function() end },
  input = { wasPressed = function() return false end },
}
local mgr = ManagerState.new(mgrGame)
mgr:refresh()
local listRows = mgr:modRows()
local sawHeader, sawA = false, false
for _, row in ipairs(listRows) do
  if row.header then sawHeader = true end
  if row.mod and row.mod.id == "a" then sawA = true end
end
check(sawHeader and sawA, "modRows groups by category and lists mods")
check(mgr:rowsForScreen() ~= nil, "rowsForScreen exposes the model to Gen 3 chrome")

print("[test] 4. Toggle path still uses ManagerState.resolveToggle")
local r = ManagerState.resolveToggle({
  a = { id = "a", dependencySpecs = {}, conflictSpecs = {} },
}, "a", true, {})
check(r.apply.a == true, "resolveToggle enable lands on the target")
check(#r.alsoEnable == 0, "no phantom cascade for a leaf mod")

print("[test] 5. ModManager pushes/pops game3.stack")
local Stack = require("src.ui.game3.stack")
local ModManager = require("src.ui.game3.mod_manager")
local function stubGame(available)
  local status = { available = available or statusStub.available }
  return {
    modStatus = status,
    mods = { status = function() return status end },
    save = { options = {} },
    options = {},
    input = { wasPressed = function() return false end },
    writeOptions = function() end,
    returnToTitle = function() end,
  }
end
Stack.clear()
check(not ModManager.isOpen(), "closed before show")
local openerDepthAfterShow
do
  -- opener stays under the manager so B-close can return to it
  Stack.push("start", StartMenu, { hideBelow = false })
  ModManager.show({ game = stubGame() })
  openerDepthAfterShow = Stack.depth()
end
check(ModManager.isOpen(), "open after show")
check(Stack.has("mod_manager"), "mod_manager layer on the game3 stack")
check(openerDepthAfterShow == 2, "opener still on the stack under the manager")
ModManager.draw()
check(true, "draw with FRLG chrome did not raise")
ModManager.handleInput({ wasPressed = function() return false end })
check(ModManager.isOpen(), "inert input keeps the manager open")
-- B at the manager root is ManagerState:goBack → proxy stack:pop → close
ModManager.handleInput({
  wasPressed = function(_, btn) return btn == "b" end,
})
check(not ModManager.isOpen(), "B at root closes the manager")
check(not Stack.has("mod_manager"), "close pops the manager layer")
check(Stack.has("start") and Stack.depth() == 1,
  "stack depth returns to the opener")
Stack.clear()

print("[test] 6. START confirm and OPTION activate open the manager")
StartMenu._game = stubGame()
StartMenu.show({ session = { bag = {}, party = {} }, game = StartMenu._game })
local modsIndex
for i, e in ipairs(StartMenu.ENTRIES) do
  if e.id == "mods" then modsIndex = i end
end
check(modsIndex ~= nil, "MODS entry present before confirm")
StartMenu.cursor = modsIndex
StartMenu.confirm()
check(ModManager.isOpen() and Stack.has("mod_manager"),
  "START confirm on MODS opens the manager")
ModManager.close()
StartMenu.close(true)

local activateRow = optionRow(withModsCtx)
local activated = false
local actGame = stubGame()
activateRow.activate({ game = actGame, session = {}, options = vanillaCtx.options })
check(ModManager.isOpen(), "OPTION activate opens the manager")
ModManager.close()
check(not ModManager.isOpen(), "manager closed after OPTION path")

print("[test] 7. Link / Union / Safari start lists stay retail")
package.loaded["src.core.game3.link"] = { link = {}, inLinkRoom = function() return true end }
StartMenu.show({ session = { bag = {}, party = {} }, game = stubGame() })
check(not hasId(entryIds(), "mods"), "link start menu has no MODS")
StartMenu.close(true)
package.loaded["src.core.game3.link"] = nil

package.loaded["src.core.game3.map"] = { current = "FR_UNION_ROOM" }
StartMenu.show({ session = { bag = {}, party = {}, map = "FR_UNION_ROOM" }, game = stubGame() })
check(not hasId(entryIds(), "mods"), "union room start menu has no MODS")
StartMenu.close(true)
package.loaded["src.core.game3.map"] = nil

package.loaded["src.core.game3.safari"] = { isActive = function() return true end }
StartMenu.show({ session = { bag = {}, party = {} }, game = stubGame() })
check(not hasId(entryIds(), "mods"), "safari start menu has no MODS")
StartMenu.close(true)
package.loaded["src.core.game3.safari"] = nil

print("[test] 8. Nested NamingScreen / QuantityBox are bridged, not dropped")
local NamingScreen = require("src.ui.NamingScreen")
local QuantityBox = require("src.ui.QuantityBox")
local named, qtyDone = nil, nil
local g = stubGame()
ModManager.show({ game = g })
local mproxy = ModManager._mgr.game
mproxy.stack:push(NamingScreen.new(mproxy, {
  title = "NAME?", maxLen = 10,
  onDone = function(name) named = name end,
}))
check(named == nil and require("src.ui.game3.naming").isOpen(),
  "NamingScreen routes to Gen 3 naming modal")
require("src.ui.game3.naming").close("ALPHA")
check(named == "ALPHA", "naming onDone delivers the typed name")

mproxy.stack:push(QuantityBox.new(mproxy, {
  max = 9, start = 3,
  onDone = function(q) qtyDone = q end,
}))
check(ModManager._prompt and ModManager._prompt.kind == "qty",
  "QuantityBox becomes an FRLG qty prompt")
ModManager.handleInput({ wasPressed = function(_, b) return b == "a" end })
check(qtyDone == 3, "qty prompt confirms the current value")
ModManager.close()

print("[test] 9. APPLY & RESTART soft-returns to Gen 3 title")
local returned = false
local g2 = stubGame()
g2.returnToTitle = function() returned = true end
ModManager.show({ game = g2 })
ModManager._mgr:restartGame()
check(returned, "restartGame calls Game3:returnToTitle")
check(not ModManager.isOpen(), "restart closes the manager (open flag not stuck)")
-- A second show must work after restart without a manual close
ModManager.show({ game = stubGame() })
check(ModManager.isOpen(), "manager can re-open after APPLY & RESTART")
ModManager.close()

print("[test] 10. Options scroll uses ManagerState's 0-based window")
do
  local g3 = stubGame({
    { id = "o1", name = "O1", category = "TWEAK", enabled = true, state = "loaded" },
    { id = "o2", name = "O2", category = "TWEAK", enabled = true, state = "loaded" },
    { id = "o3", name = "O3", category = "TWEAK", enabled = true, state = "loaded" },
    { id = "o4", name = "O4", category = "TWEAK", enabled = true, state = "loaded" },
    { id = "o5", name = "O5", category = "TWEAK", enabled = true, state = "loaded" },
    { id = "o6", name = "O6", category = "TWEAK", enabled = true, state = "loaded" },
  })
  ModManager.show({ game = g3 })
  local m = ModManager._mgr
  m.screen = "options"
  m.optionRows = {
    { id = "a", label = "A", value = function() return "1" end },
    { id = "b", label = "B", value = function() return "2" end },
    { id = "c", label = "C", value = function() return "3" end },
    { id = "d", label = "D", value = function() return "4" end },
    { id = "e", label = "E", value = function() return "5" end },
    { id = "f", label = "F", value = function() return "6" end },
  }
  m.cursor = 5
  m.scroll = 1
  ModManager.draw()
  check(true, "options draw with 0-based scroll did not raise")
  check((m.scroll or 0) + 1 == 2, "options first row is scroll+1 (0-based scroll)")
  ModManager.close()
end

print("[test] 11. List view is a sticky 7-row window (not ManagerState's 11)")
do
  local many = {}
  for i = 1, 15 do
    many[i] = {
      id = "m" .. i, name = "M" .. i, category = "TWEAK",
      enabled = true, state = "loaded",
    }
  end
  ModManager.show({ game = stubGame(many) })
  local m = ModManager._mgr
  -- ManagerState clamps to LIST_ROWS=11; we must stay on a 7-row follow
  for step = 1, 8 do
    m:moveCursor(1)
  end
  ModManager.draw()
  local first = ModManager._viewFirst or 1
  check(m.cursor >= first and m.cursor <= first + 6,
    "cursor stays inside the 7-row view (cursor=" .. tostring(m.cursor) ..
      " first=" .. tostring(first) .. ")")
  check(first >= 1 and first <= m.cursor,
    "view scrolls one row at a time, cursor never parks off screen")
  ModManager.close()
end

print("[test] 12. New manager module does not draw with Gen 1 Font/Theme")
local src = io.open("src/ui/game3/mod_manager.lua", "r"):read("*a")
check(not src:find('require("src.render.Font")', 1, true),
  "no src.render.Font require")
check(not src:find('require("src.ui.Theme")', 1, true),
  "no src.ui.Theme require")
-- Match Gen 1 Font.draw, not FrlgFont.draw (shared substring).
check(not src:find("[^%w]Font%.draw"), "no Gen 1 Font.draw call")

if failed > 0 then
  print(string.format("[FAIL] %d check(s) failed", failed))
  os.exit(1)
end
print("ALL TESTS PASSED")
os.exit(0)
