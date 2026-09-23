#!/usr/bin/env luajit
-- pokefirered/data/scripts/pc.inc:1

package.path = "./?.lua;./?/init.lua;" .. package.path
package.loaded["src.core.game3.rom_text"] = {
  plain = function(key) return key end, box = function(key) return key end,
  ascii = function(key) return key end, has = function() return true end,
  key = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
  at = function(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end,
  count = function() return 0 end, list = function() return {} end,
  lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
}

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local events = {}
package.loaded["src.ui.game3.stack"] = {
  push = function() end,
  pop = function() end,
  busy = function() return false end,
  drawOrder = function() return {} end,
}
package.loaded["src.core.game3.audio"] = {
  playSe = function(id) events[#events + 1] = "se" .. tostring(id) end,
  playCry = function() end,
}

local function input(key)
  return { wasPressed = function(_, k) return k == key end, isDown = function() return false end }
end

local function seOnly()
  local out = {}
  for _, e in ipairs(events) do
    if e:sub(1, 2) == "se" then out[#out + 1] = e end
  end
  return table.concat(out, ",")
end

local Player = require("src.core.game3.player")
Player.cellX, Player.cellY, Player.facing = 5, 10, "up"
local PcAnim = require("src.core.game3.pc_anim")
PcAnim.setter(function() end)
local realTurnOn = PcAnim.turnOn
PcAnim.turnOn = function(...)
  events[#events + 1] = "anim_on"
  return realTurnOn(...)
end

local Std = require("src.core.game3.scripting.stdscripts")
local PcMenu = require("src.ui.game3.pc_menu")
local Bag = require("src.core.game3.bag")
local Storage = require("src.core.game3.storage")
local function session() return { bag = Bag.new(), storage = Storage.new(), name = "RED" } end

print("[test] 2. Center PC flow (pc.inc fixture): ON, menu, storage LOGIN, menu again, LOG OFF")
local Vm = require("src.core.game3.scripting.vm")
local Adapters = require("src.core.game3.scripting.adapters")
local Fixture = require("tests.fixture_data.game3_pc_scripts")
local picks = { 1, 3 }
local results = {}
local vm = Vm.new({
  scripts = Fixture.SCRIPTS,
  text = Fixture.TEXT,
  adapters = Adapters.stub({
    onMessage = function() events[#events + 1] = "msg" end,
    openPc = function(done, opts)
      local mode = opts and opts.mode
      events[#events + 1] = mode or "pc"
      if mode ~= "select" then return done() end
      PcMenu.show({ session = session(), startMode = "select", silentClose = true,
        onClose = function(r) results[#results + 1] = r; done(r) end })
      PcMenu.cursor = table.remove(picks, 1)
      PcMenu.handleInput(input("a"))
    end,
  }),
})
check(vm:start("EventScript_PC") == true, "vm started EventScript_PC")
local steps = 0
while vm:isRunning() and steps < 200 do vm:step(); steps = steps + 1 end
check(not vm:isRunning(), "EventScript_PC completed")
local seq = table.concat(events, ",")
local want = "anim_on,se4,msg,msg,select,se5,se2,msg,msg,storage,msg,select,se5,se3"
check(seq == want, "ordered events " .. want .. " (got " .. seq .. ")")
check(results[1] == 0 and results[2] == 2, "CreatePCMenu returns row indexes 0 then 2 (got "
  .. tostring(results[1]) .. "," .. tostring(results[2]) .. ")")

local function flagged(dex, clear)
  local s = session()
  s.flags = {}
  local Space = package.loaded["src.core.game3.scripting.space"]
  local stores = { s }
  if Space and Space.store then Space.store.flags = Space.store.flags or {}; stores[2] = Space.store end
  for _, st in ipairs(stores) do
    st.flags[0x829] = dex or nil
    st.flags[0x82C] = clear or nil
  end
  return s
end

local function rowIds()
  local ids = {}
  for _, r in ipairs(PcMenu._rootEntries()) do ids[#ids + 1] = r.id end
  return table.concat(ids, ",")
end

print("[test] 3. root rows gate on POKEDEX_GET / GAME_CLEAR (script_menu.c:1006)")
for _, c in ipairs({
  { false, false, "storage,player,quit" },
  { true, false, "storage,player,oak,quit" },
  { true, true, "storage,player,oak,hall,quit" },
  { false, true, "storage,player,oak,hall,quit" },
}) do
  PcMenu.show({ session = flagged(c[1], c[2]) })
  local got = rowIds()
  check(got == c[3], string.format("dex=%s clear=%s rows %s (got %s)", tostring(c[1]), tostring(c[2]), c[3], got))
  PcMenu.close()
end

print("[test] 4. CreatePCMenu: open plays nothing; A plays SELECT only and returns the row index")
for i, id in ipairs({ "storage", "player", "oak", "hall" }) do
  local s = flagged(true, true)
  events = {}
  local got
  PcMenu.show({ session = s, startMode = "select", silentClose = true, onClose = function(r) got = r end })
  check(seOnly() == "", id .. ": root open plays no SE")
  PcMenu.cursor = i
  check(PcMenu._rootEntries()[i].id == id, id .. " is root row " .. i)
  PcMenu.handleInput(input("a"))
  check(seOnly() == "se5", id .. ": A plays se5 (got " .. seOnly() .. ")")
  check(got == i - 1, id .. ": VAR_RESULT " .. (i - 1) .. " (got " .. tostring(got) .. ")")
end

print("[test] 5. CreatePCMenu LOG OFF returns its row, B returns SCR_MENU_CANCEL")
for _, c in ipairs({ { false, false, 3 }, { true, false, 4 }, { true, true, 5 } }) do
  events = {}
  local got
  PcMenu.show({ session = flagged(c[1], c[2]), startMode = "select", silentClose = true,
    onClose = function(r) got = r end })
  PcMenu.cursor = c[3]
  check(PcMenu._rootEntries()[c[3]].id == "quit", "LOG OFF is row " .. c[3])
  PcMenu.handleInput(input("a"))
  check(seOnly() == "se5", "LOG OFF row " .. c[3] .. " plays se5 (got " .. seOnly() .. ")")
  check(got == c[3] - 1, "LOG OFF row " .. c[3] .. " returns " .. (c[3] - 1) .. " (got " .. tostring(got) .. ")")
end
events = {}
local cancel
PcMenu.show({ session = flagged(false, false), startMode = "select", silentClose = true,
  onClose = function(r) cancel = r end })
PcMenu.handleInput(input("b"))
check(seOnly() == "se5", "B plays se5 (got " .. seOnly() .. ")")
check(cancel == 127, "B returns 127 (got " .. tostring(cancel) .. ")")

print("[test] 6. bedroom player_pc open plays nothing")
events = {}
PcMenu.show({ session = session(), startMode = "player_pc", closeOnExit = true })
check(seOnly() == "", "bedroom open plays no SE")
events = {}
PcMenu.handleInput(input("b"))
check(seOnly() == "se5,se3", "bedroom TURN OFF plays se5,se3 once (got " .. seOnly() .. ")")

print("[test] 7. Hud.openPc boots with SE_PC_ON")
local okHud, Hud = pcall(require, "src.ui.game3.hud")
check(okHud, "hud loads (" .. tostring(okHud and "" or Hud) .. ")")
if okHud then
  events = {}
  Hud.openPc(nil, session())
  check(seOnly() == "se4", "Hud.openPc plays se4 (got " .. seOnly() .. ")")
  PcMenu.close()
end

if failed > 0 then
  print(string.format("[FAIL] %d check(s) failed", failed))
  os.exit(1)
end
print("[ok] all checks passed")
