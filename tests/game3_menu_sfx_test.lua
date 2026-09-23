#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.fixture_data.game3_items").install()
require("tests.fixture_data.game3_map_sections").install()
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

local SE_SELECT, SE_WIN_OPEN, SE_EXIT, SE_FAILURE, SE_SHOP = 5, 6, 9, 26, 248

local played = {}
package.loaded["src.core.game3.audio"] = {
  playSe = function(id) played[#played + 1] = id end,
  playSong = function() end,
  playFanfare = function() end,
  stopAll = function() end,
  waitSe = function(_, cb) if cb then cb() end end,
}
package.loaded["src.ui.game3.stack"] = {
  push = function() end,
  pop = function() end,
  contains = function() return false end,
  top = function() return nil end,
}

print("[test] 1. Start menu close plays SE_SELECT (start_menu.c:1005)")
local StartMenu = require("src.ui.game3.start_menu")
played = {}
StartMenu.close()
check(#played == 1 and played[1] == SE_SELECT,
  "StartMenu.close -> SE_SELECT only (got " .. table.concat(played, ",") .. ")")

print("[test] 2. Backing out of the EXIT confirm with B is silent (menu.c:381)")
StartMenu._confirmExit = true
played = {}
StartMenu.cancel()
check(#played == 0, "StartMenu.cancel on confirm -> silence (got " .. table.concat(played, ",") .. ")")

print("[test] 3. Save dialog opens silently (start_menu.c:518)")
local SaveMenu = require("src.ui.game3.save_menu")
played = {}
SaveMenu.show({})
check(#played == 0, "SaveMenu.show -> silence (got " .. table.concat(played, ",") .. ")")

print("[test] 4. Save dialog NO plays SE_SELECT, B is silent (menu.c:373/381)")
SaveMenu.show({})
SaveMenu.cursor = 2
played = {}
SaveMenu.confirm()
check(#played == 1 and played[1] == SE_SELECT,
  "SaveMenu NO -> SE_SELECT only (got " .. table.concat(played, ",") .. ")")
SaveMenu.show({})
played = {}
SaveMenu.cancel()
check(#played == 0, "SaveMenu B press -> silence (got " .. table.concat(played, ",") .. ")")

print("[test] 4b. Dismissing the saved message is silent (start_menu.c:583)")
StartMenu.open = true
SaveMenu.show({})
SaveMenu._phase = "saved"
played = {}
SaveMenu.confirm()
check(#played == 0, "SaveMenu saved-phase A -> silence (got " .. table.concat(played, ",") .. ")")
check(StartMenu.open == false, "saved-phase dismissal still tears the start menu down")
StartMenu.open = true
SaveMenu.show({})
SaveMenu._phase = "saved"
played = {}
SaveMenu.cancel()
check(#played == 0, "SaveMenu saved-phase B -> silence (got " .. table.concat(played, ",") .. ")")
StartMenu.open = false

print("[test] 5. Shop menu opens silently and quits with SE_SELECT (shop.c:213/265)")
local ShopMenu = require("src.ui.game3.shop_menu")
played = {}
ShopMenu.show({ items = {}, session = {} })
check(#played == 0, "ShopMenu.show -> silence (got " .. table.concat(played, ",") .. ")")
played = {}
ShopMenu.close()
check(#played == 0, "ShopMenu.close -> silence (the A/B press sounds, not the teardown)")

print("[test] 5b. Purchase YES plays SE_SELECT, SE_SHOP follows the message (shop.c:999)")
local function shop_input(map)
  return { wasPressed = function(_, k) return map[k] == true end,
           isDown = function(_, k) return map[k] == true end }
end
local Bag = require("src.core.game3.bag")
local shopSession = { money = 5000, bag = Bag.new() }
ShopMenu.show({ items = { 4 }, session = shopSession })
ShopMenu.mode = "buy_confirm"
ShopMenu._pending = { id = 4, price = 200, name = "POKe BALL" }
ShopMenu.qty = 1
ShopMenu.yesNoCursor = 1
played = {}
ShopMenu.handleInput(shop_input({ a = true }))
check(ShopMenu.mode == "buy_msg" and shopSession.money == 4800, "purchase committed")
check(#played == 1 and played[1] == SE_SELECT,
  "YES frame -> SE_SELECT only (got " .. table.concat(played, ",") .. ")")
local waited = 0
while #played == 1 and waited < 600 do
  ShopMenu.handleInput(shop_input({}))
  waited = waited + 1
end
check(#played == 2 and played[2] == SE_SHOP and waited > 1,
  "SE_SHOP lands " .. waited .. " frames later (got " .. table.concat(played, ",") .. ")")
played = {}
ShopMenu.handleInput(shop_input({ a = true }))
check(ShopMenu.mode == "buy" and #played == 1 and played[1] == SE_SELECT,
  "message dismissal -> SE_SELECT only (got " .. table.concat(played, ",") .. ")")
ShopMenu.mode = "buy_confirm"
ShopMenu._pending = { id = 4, price = 200, name = "POKe BALL" }
ShopMenu.qty = 1
ShopMenu.yesNoCursor = 1
ShopMenu.handleInput(shop_input({ a = true }))
played = {}
ShopMenu.handleInput(shop_input({ a = true }))
check(ShopMenu.mode == "buy" and #played == 1 and played[1] == SE_SHOP,
  "early dismissal still plays SE_SHOP exactly once (got " .. table.concat(played, ",") .. ")")
ShopMenu.close()

print("[test] 6. Generic yes/no cancel plays SE_SELECT (menu_helpers.c:57)")
local Choice = require("src.ui.game3.choice")
Choice.active = true
Choice.kind = "yesno"
Choice.options = { "YES", "NO" }
Choice.cursor = 1
Choice.ignoreBPress = false
Choice.done = nil
played = {}
Choice.cancel()
check(#played == 1 and played[1] == SE_SELECT,
  "Choice.cancel -> SE_SELECT only (got " .. table.concat(played, ",") .. ")")

print("[test] 7. No game3 UI source plays SE_EXIT")
local UI_SOURCES = {
  "src/ui/game3/start_menu.lua",
  "src/ui/game3/save_menu.lua",
  "src/ui/game3/shop_menu.lua",
  "src/ui/game3/choice.lua",
  "src/ui/game3/bag_menu.lua",
  "src/ui/game3/party_menu.lua",
  "src/ui/game3/berry_pouch.lua",
  "src/ui/game3/tm_case.lua",
  "src/ui/game3/box_storage_ui.lua",
  "src/ui/game3/pc_menu.lua",
  "src/ui/game3/summary_menu.lua",
  "src/ui/game3/region_map.lua",
  "src/ui/game3/release_seq.lua",
}
for _, path in ipairs(UI_SOURCES) do
  local f = io.open(path, "r")
  if not f then
    check(false, "missing source " .. path)
  else
    local src = f:read("*a")
    f:close()
    local hits = {}
    local lineNo = 0
    for line in (src .. "\n"):gmatch("([^\n]*)\n") do
      lineNo = lineNo + 1
      local code = line:gsub("%-%-.*$", "")
      if code:find("se%(9%)") or code:find("playSe%(%s*9%s*%)") or code:find("SE_EXIT") then
        hits[#hits + 1] = tostring(lineNo)
      end
    end
    check(#hits == 0, path .. " has no SE_EXIT site (lines " .. table.concat(hits, ",") .. ")")
  end
end

print("[test] 8. SE_EXIT still owned by the warp/door path (field_fadetransition.c:541)")
for _, path in ipairs({ "src/core/game3/warp.lua", "src/core/game3/doors.lua" }) do
  local f = assert(io.open(path, "r"))
  local src = f:read("*a")
  f:close()
  check(src:find("SE_EXIT") ~= nil, path .. " still references SE_EXIT")
end

print("[test] 9. One-shot SEs bake to their natural end (battle_anim_special.c:1200)")
local captured = nil
package.loaded["src.core.game3.m4a_player"] = {
  mixQuantum = function() return 256 end,
  loadPack = function() return {} end,
  songInfo = function(_, id) return { kind = "se", player = 2, hasGoto = false, id = id } end,
  start = function() return true end,
  bakeSlot = function(_, opts) captured = opts; return { 0 }, { 0 } end,
  renderBuffered = function() return {}, {} end,
  updateSlot = function() end,
}
package.loaded["src.core.game3.audio"] = nil
local Audio = require("src.core.game3.audio")
Audio._ready = true
Audio._pack = {}
Audio.playSe(319)
check(captured ~= nil, "playSe reached Player.bakeSlot")
check(captured and captured.maxSec and captured.maxSec >= 4.6,
  "MUS_CAUGHT_INTRO bake ceiling covers the full cue (maxSec = "
    .. tostring(captured and captured.maxSec) .. ")")

if failed > 0 then
  print(string.format("\n%d check(s) failed", failed))
  os.exit(1)
end
print("\nall menu SFX checks passed")
