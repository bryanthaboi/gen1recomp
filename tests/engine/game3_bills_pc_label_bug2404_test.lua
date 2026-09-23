#!/usr/bin/env luajit
-- pokefirered/src/script_menu.c:1027, pokefirered/data/maps/Route25_SeaCottage/scripts.inc:105

package.path = "./?.lua;./?/init.lua;" .. package.path

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

package.loaded["src.ui.game3.stack"] = {
  push = function() end,
  pop = function() end,
  busy = function() return false end,
  drawOrder = function() return {} end,
}
package.loaded["src.core.game3.audio"] = {
  playSe = function() end,
  playCry = function() end,
}
package.loaded["src.core.game3.rom_text"] = { plain = function(key) return key end, box = function(key) return key end }

local drawn = {}
package.loaded["src.ui.game3.window"] = setmetatable({
  printPx = function(text) drawn[#drawn + 1] = text end,
  template = function() return {} end,
}, { __index = function() return function() end end })

local Flags = require("src.core.game3.scripting.flags")
local Space = require("src.core.game3.scripting.space")
local PcMenu = require("src.ui.game3.pc_menu")

local function label(session)
  PcMenu.show({ session = session })
  PcMenu.mode = "root"
  drawn = {}
  PcMenu.draw()
  PcMenu.close()
  local got = drawn[1]
  if PcMenu.storageLabel then
    check(PcMenu.storageLabel(session) == got, "storageLabel matches drawn row")
  end
  return got
end

print("[test] 1. fresh store: SOMEONE'S PC")
local store = Flags.newStore()
Space.store = store
local session = { flags = {} }
check(label(session) == "SOMEONE'S PC", "no flags -> SOMEONE'S PC (got " .. tostring(label(session)) .. ")")

print("[test] 2. FLAG_SYS_POKEMON_GET (0x828) alone stays SOMEONE'S PC")
Flags.setFlag(store, nil, 0x828, true)
session.flags = Flags.serialize(store).flags
check(label(session) == "SOMEONE'S PC", "0x828 -> SOMEONE'S PC (got " .. tostring(label(session)) .. ")")

print("[test] 3. FLAG_SYS_NOT_SOMEONES_PC in the live store: BILL'S PC")
Flags.setFlag(store, nil, "FLAG_SYS_NOT_SOMEONES_PC", true)
check(Flags.getFlag(store, nil, 0x834), "setFlag by name lands on 0x834")
check(label(session) == "BILL'S PC", "live 0x834 -> BILL'S PC (got " .. tostring(label(session)) .. ")")

print("[test] 4. post-load snapshot (string keys, no live store): BILL'S PC")
local snap = Flags.serialize(store).flags
Space.store = nil
check(label({ flags = snap }) == "BILL'S PC", "serialized 0x834 -> BILL'S PC (got " .. tostring(label({ flags = snap })) .. ")")

print("[test] 5. snapshot without 0x834: SOMEONE'S PC")
check(label({ flags = { ["2088"] = true } }) == "SOMEONE'S PC", "serialized 0x828 only -> SOMEONE'S PC")

print(("game3_bills_pc_label_bug2404_test: %s (%d failed)"):format(failed == 0 and "PASS" or "FAIL", failed))
if failed > 0 then os.exit(1) end
