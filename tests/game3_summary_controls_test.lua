#!/usr/bin/env luajit

package.path = "./?.lua;./?/init.lua;" .. package.path
require("tests.game3_cache").mountOrSkip("summary_controls")

local failed = 0
local function eq(a, b, msg)
  if a == b then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print(string.format("[FAIL] %s (%s ~= %s)", msg, tostring(a), tostring(b)))
  end
end

require("src.core.GameVersion").set("firered")

package.loaded["src.core.game3.audio"] = {
  playSe = function() end,
  playCry = function() end,
  playSong = function() end,
  stopAll = function() end,
}

local gfx = setmetatable({}, { __index = function() return function() end end })
gfx.newQuad = function() return {} end
gfx.newImage = function() return nil end
gfx.getWidth = function() return 240 end
gfx.getHeight = function() return 160 end
_G.love = { graphics = gfx, timer = { getTime = function() return 0 end } }

local RomText = require("src.core.game3.rom_text")
local SummaryMenu = require("src.ui.game3.summary_menu")

local PICK = RomText.plain("gText_PokeSum_Controls_Pick")
local PICK_SWITCH = RomText.plain("gText_PokeSum_Controls_PickSwitch")
local PAGE_MOVES_INFO = 3

local battleActive = false
package.loaded["src.core.game3.battle"] = { isActive = function() return battleActive end }

local function controls(mode)
  SummaryMenu._mode = mode
  local s = SummaryMenu.controlsString(PAGE_MOVES_INFO, false)
  SummaryMenu._mode = nil
  return s
end

battleActive = false
eq(controls("select_move"), PICK_SWITCH, "select-move mode outside battle shows PickSwitch")
eq(controls(nil), PICK_SWITCH, "normal-mode move detail outside battle shows PickSwitch")
eq(controls("party"), PICK_SWITCH, "party-mode move detail outside battle shows PickSwitch")
eq(controls("trade"), PICK, "link trade move detail shows Pick")

battleActive = true
eq(controls("select_move"), PICK, "select-move mode in battle shows Pick")
eq(controls(nil), PICK, "normal-mode move detail in battle shows Pick")
eq(controls("party"), PICK, "party-mode move detail in battle shows Pick")

if failed > 0 then
  print(failed .. " failure(s)")
  os.exit(1)
end
print("summary controls: all passed")
