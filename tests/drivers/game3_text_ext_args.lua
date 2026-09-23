local U = require("tests.drivers.util")
local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/game3_text_ext_args"

local failures = 0
local function result(ok, label)
  print((ok and "PASS " or "FAIL ") .. label)
  if not ok then failures = failures + 1 end
  return ok
end

local function finish()
  if failures == 0 then
    print("PASS text_ext_args")
    love.event.quit(0)
  else
    print("FAIL text_ext_args failures=" .. failures)
    love.event.quit(1)
  end
end

return function(game)
  for _ = 1, 900 do
    if game.phase == "boot" and game.boot then break end
    U.wait(1)
  end

  game:_handleBootAction({ action = "new_game", name = "RED" })
  U.wait(240)

  local Runtime = require("src.core.game3.runtime")
  local Message = require("src.ui.game3.message")
  local FrlgFont = require("src.ui.game3.frlg_font")
  local TextIR = require("src.core.game3.scripting.text_ir")

  if not result(Runtime.getSession() ~= nil, "new game reached the game3 field") then return finish() end
  result(FrlgFont.measure("·") > 0, "latin_normal font is loaded from the cache")

  local dot = "·"
  -- pokefirered/src/field_player_avatar.c:1769
  local parts = {}
  for k = 0, 2 do parts[#parts + 1] = "\252\18" .. string.char(k * 12) .. dot end
  local dots = table.concat(parts)
  Message.showStay(dots, { speed = 0 })
  U.wait(2)
  result(#Message._pages == 1, "SKIP 0/12/24 dots stay on one page, pages=" .. #Message._pages)
  result(Message.currentPage() == dots, "the dot string reaches the printer byte-identical")
  result(FrlgFont.measure(Message.currentPage()) == 24 + FrlgFont.measure(dot),
    "third dot starts at x=24, width " .. FrlgFont.measure(Message.currentPage()))
  U.shot(game, DIR .. "/f3_fishing_dots_skip12.png")
  Message.close()
  U.wait(2)

  local words = {}
  for k = 1, 8 do words[#words + 1] = "word" .. k end
  local wide = table.concat(words, " ", 1, 4) .. " A\252\19\12B " .. table.concat(words, " ", 5, 8)
  Message.show(wide, { speed = 0 })
  U.wait(2)
  local joined = table.concat(Message._pages, "\f")
  result(joined:find("A\252\19\12B", 1, true) ~= nil, "CLEAR_TO 0x0C survives font-width wrapping")
  result(#Message._pages == 1, "wrapped two-line text stays on one page, pages=" .. #Message._pages)
  U.shot(game, DIR .. "/f3_clear_to_12_wrapped.png")
  Message.close()
  U.wait(2)

  for cmd, nargs in pairs(TextIR.EXT_ARGS) do
    for _, arg in ipairs({ 0x09, 0x0A, 0x0C, 0x0D, 0x20, 0x5C, 0x7B }) do
      local raw = dot .. "\252" .. string.char(cmd) .. string.rep(string.char(arg), nargs) .. dot
      Message.show(raw, { speed = 0 })
      if #Message._pages ~= 1 or Message._pages[1] ~= raw then
        result(false, string.format("cmd %02X arg %02X split into %d pages", cmd, arg, #Message._pages))
      end
      Message.close()
    end
  end
  result(true, "every ext code with a separator argument byte was checked")

  finish()
end
