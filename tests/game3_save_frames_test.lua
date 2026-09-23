#!/usr/bin/env luajit
-- pokefirered/src/start_menu.c:971, :628, src/new_menu_helpers.c:648

package.path = "./?.lua;./?/init.lua;" .. package.path
local ROM_TEXT = {}
local function romTextKey(n, i, j) return j and (n .. "[" .. i .. "][" .. j .. "]") or (n .. "[" .. i .. "]") end
local function romTextPlain(key, ctx) return ((ROM_TEXT[key] or key):gsub("{PLAYER}", ctx and ctx.playerName or "")) end
package.loaded["src.core.game3.rom_text"] = {
  plain = romTextPlain, box = romTextPlain, ascii = romTextPlain, has = function() return true end,
  key = romTextKey, at = function(n, i, j, ctx) return romTextPlain(romTextKey(n, i, j), ctx) end,
  count = function() return 0 end, list = function() return {} end,
  lazy = function(map) return setmetatable({}, { __index = function(_, k) return map[k] end }) end,
}
love = require("tests.love_stub")

local failed = 0
local function check(cond, msg)
  if cond then
    print("[ok] " .. msg)
  else
    failed = failed + 1
    print("[FAIL] " .. msg)
  end
end

local Chrome = require("src.ui.game3.chrome")
local FrlgFont = require("src.ui.game3.frlg_font")
local Window = require("src.ui.game3.window")
local SaveMenu = require("src.ui.game3.save_menu")

local calls = {}
local function record(kind)
  return function(tx, ty, tw, th)
    calls[#calls + 1] = { kind = kind, tx = tx, ty = ty, tw = tw, th = th }
  end
end

Chrome.stdFrame = record("user")
Chrome.fixedStdFrame = record("std")
Chrome.dialogueFrame = record("dialogue")
Chrome.userFrame = function(frameType, tx, ty, tw, th)
  calls[#calls + 1] = { kind = "user", tx = tx, ty = ty, tw = tw, th = th }
end
FrlgFont.draw = function() end
FrlgFont.measure = function(text) return #tostring(text) * 6 end
Window.cursorPx = function() end

SaveMenu._session = { name = "RED", mapName = "PALLET TOWN" }
SaveMenu.open = true
SaveMenu._phase = "confirm"
SaveMenu.cursor = 1
SaveMenu.draw()

check(#calls == 3, "the save dialog draws three frames (" .. #calls .. ")")

local stats, dialogue, yesno = calls[1], calls[2], calls[3]

check(stats and stats.kind == "std",
  "save stats window uses the fixed std frame, not the user frame ("
    .. tostring(stats and stats.kind) .. ")")
check(stats and stats.tx == 1 and stats.ty == 1 and stats.tw == 14 and stats.th == 9,
  "save stats window sits at sSaveStatsWindowTemplate (1,1,14,9)")

check(dialogue and dialogue.kind == "dialogue",
  "save message box uses the dialogue frame (" .. tostring(dialogue and dialogue.kind) .. ")")

check(yesno and yesno.kind == "user",
  "YES/NO uses the user-selected std frame (" .. tostring(yesno and yesno.kind) .. ")")
check(yesno and yesno.tx == 21 and yesno.ty == 9 and yesno.tw == 6 and yesno.th == 4,
  "YES/NO sits at sYesNo_WindowTemplate (21,9,6,4)")

calls = {}
SaveMenu._phase = "saving"
SaveMenu.draw()
check(#calls == 2 and calls[1].kind == "std" and calls[2].kind == "dialogue",
  "the saving phase drops YES/NO and keeps the other two frames")

SaveMenu.open = false
print(("game3_save_frames_test: %s (%d failed)"):format(failed == 0 and "PASS" or "FAIL", failed))
if failed > 0 then os.exit(1) end
