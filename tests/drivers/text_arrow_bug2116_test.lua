-- (text/PalletTown.asm:44)
-- show, on the second text row (home/text.asm:214)
--   SHOT_DIR=/tmp/bug2116 POKEPORT_DRIVER=tests/drivers/text_arrow_bug2116_test.lua \
--   POKEPORT_IDENTITY=<a v11 cache> POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local TextBox = require("src.render.TextBox")

  local pass = true
  local function check(msg, cond)
    if cond then U.log("PASS: " .. msg) else pass = false; U.log("FAIL: " .. msg) end
  end
  local function box()
    local top = game.stack:top()
    return getmetatable(top) == TextBox and top or nil
  end

  -- bg_event 7, 9 (data/maps/objects/PalletTown.asm:16)
  U.teleport(game, "PALLET_TOWN", 7, 10, "up")
  U.wait(8)
  U.tap(game, "a")
  U.wait(10)

  local tb = box()
  check("the sign opened a text box", tb ~= nil)
  if not tb then U.log("RESULT: SEE FAILURES ABOVE") return end

  U.log("_PalletTownSignText = "
        .. string.format("%q", tostring(game.data.text._PalletTownSignText)))
  check("the extracted line ends in a done marker",
        (game.data.text._PalletTownSignText or ""):find("{DONE}", 1, true) ~= nil)

  -- the `cont` wait: home/text.asm:263
  local sawCont = false
  for _ = 1, 400 do
    if tb.waiting then sawCont = true break end
    U.wait(1)
  end
  check("the cont page waits on the arrow", sawCont)
  if sawCont then
    local x, y = tb:arrowPos()
    U.log(("arrowPos = %d,%d  line2Y = %d"):format(x, y, tb.line2Y))
    check("the arrow is drawn at the cont wait", tb:arrowVisible())
    check("column 18 (x=144)", x == 144)
    check("row 16 (y=128), the second text row", y == 128 and y == tb.line2Y)
    tb.blink = 0
    U.shot(game, DIR .. "/bug2116_1_cont_arrow.png")
  end

  for _ = 1, 120 do
    if tb.done then break end
    U.tap(game, "a")
    U.wait(4)
  end
  check("the text finished", tb.done == true)
  -- home/text_script.asm:96 -> home/joypad2.asm:71-72
  check("a `done` text still blinks the arrow", tb:arrowVisible())
  -- home/joypad2.asm:90-92
  check("and closes without SFX_PRESS_AB", tb.waitButton == true)
  tb.blink = 0
  U.shot(game, DIR .. "/bug2116_2_done_arrow_no_beep.png")

  U.log(pass and "RESULT: ALL PASS" or "RESULT: SEE FAILURES ABOVE")
  U.log("bug2116_1_cont_arrow.png: the blinking triangle sits on the same")
  U.log("row as the second line of text, not jammed on the bottom border.")
  U.log("bug2116_2_done_arrow_no_beep.png: the final page of a `done` text")
  U.log("still shows the triangle -- WaitForTextScrollButtonPress blinks it")
  U.log("for every Gen 1 text; only the A-press beep is missing.")
  U.log("Shots are in " .. DIR)
end
