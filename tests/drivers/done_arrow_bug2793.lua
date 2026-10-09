-- home/text.asm:209 PromptText, :221 DoneText; home/joypad2.asm:55; home/window.asm:225

return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/shots"
  local TextBox = require("src.render.TextBox")

  local pass = true
  local function check(msg, cond)
    if cond then print("PASS " .. msg) else pass = false; print("FAIL " .. msg) end
  end
  local function topBox()
    local top = game.stack:top()
    return getmetatable(top) == TextBox and top or nil
  end
  local function finish()
    print(pass and "PASS all" or "FAIL see above")
    love.event.quit(pass and 0 or 1)
    U.wait(600)
  end
  local function waitFor(tb, fn, mash)
    for i = 1, 600 do
      if fn(tb) then return true end
      if mash and tb.waiting and i % 6 == 0 then U.tap(game, "a") end
      U.wait(1)
    end
    return false
  end
  local function close(tb)
    for _ = 1, 30 do
      if game.stack:top() ~= tb then return end
      U.tap(game, "a")
      U.wait(4)
    end
  end

  U.teleport(game, "PALLET_TOWN", 7, 10, "up")
  U.wait(10)

  local fedUp = game.data.text._OaksLabRivalFedUpWithWaitingText or ""
  check("rival fed-up text ends in done", fedUp:find("{DONE}%s*$") ~= nil)
  local tb = TextBox.new(game, fedUp)
  game.stack:push(tb)
  check("fed-up text reaches its cont wait", waitFor(tb, function(b) return b.waiting end))
  check("cont wait shows the arrow", tb:arrowVisible())
  tb.blink = 0
  U.still(game, DIR .. "/2793_01_fedup_cont_arrow.png")
  check("fed-up text finishes", waitFor(tb, function(b) return b.done end, true))
  U.wait(2)
  check("done end of fed-up text has no arrow", not tb:arrowVisible())
  tb.blink = 0
  U.still(game, DIR .. "/2793_02_fedup_done_no_arrow.png")
  close(tb)

  local great = game.data.text._OaksLabRivalAmIGreatOrWhatText or ""
  check("am-I-great text ends in prompt", great:find("{PROMPT}%s*$") ~= nil)
  tb = TextBox.new(game, great)
  game.stack:push(tb)
  check("prompt text finishes", waitFor(tb, function(b) return b.done end, true))
  U.wait(2)
  check("prompt end shows the arrow", tb:arrowVisible())
  tb.blink = 0
  U.still(game, DIR .. "/2793_03_prompt_arrow.png")
  close(tb)

  U.wait(10)
  U.tap(game, "a")
  U.wait(10)
  tb = topBox()
  check("pallet sign opened a text box", tb ~= nil)
  if not tb then return finish() end
  check("sign text finishes", waitFor(tb, function(b) return b.done end, true))
  U.wait(2)
  check("sign done end has no arrow", not tb:arrowVisible())
  tb.blink = 0
  U.still(game, DIR .. "/2793_04_sign_done_no_arrow.png")
  close(tb)

  finish()
end
