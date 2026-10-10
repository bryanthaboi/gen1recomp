-- scripts/PalletTown.asm:177-188
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("POKEPORT_SHOT_DIR") or os.getenv("SHOT_DIR") or "/tmp/shots"
  local TextBox = require("src.render.TextBox")

  local ok = true
  local function check(label, cond)
    if not cond then ok = false end
    U.log(cond and "PASS" or "FAIL", label)
  end
  local function done()
    love.event.quit(ok and 0 or 1)
  end

  local f = game.save.flags
  f.EVENT_FOLLOWED_OAK_INTO_LAB = nil
  f.EVENT_GOT_STARTER = nil
  U.teleport(game, "PALLET_TOWN", 10, 3, "up")
  local ow = game.stack:top()

  local box
  for _ = 1, 120 do
    table.insert(game.input.pressQueue, "up")
    game.input.state.up = true
    U.wait(1)
    local top = game.stack:top()
    if getmetatable(top) == TextBox then box = top break end
  end
  game.input.state.up = false
  check("hey wait text box opened", box ~= nil)
  if not box then return done() end

  local bubbleStart
  for _ = 1, 600 do
    if ow.emote and ow.emote.npc == ow.player then bubbleStart = true break end
    U.wait(1)
  end
  check("bubble appears while text box is up", bubbleStart ~= nil and game.stack:top() == box)
  if not bubbleStart then return done() end
  U.wait(30)
  check("text box still up mid-bubble", game.stack:top() == box)
  U.still(game, DIR .. "/2843_01_bubble_with_textbox.png")

  local boxGone, bubbleGone
  for _ = 1, 200 do
    U.wait(1)
    if not boxGone and game.stack:top() ~= box then boxGone = U.frame() end
    if not bubbleGone and not (ow.emote and ow.emote.npc == ow.player) then bubbleGone = U.frame() end
    if boxGone and bubbleGone then break end
  end
  local held = box.autoTimer and box.auto and (box.autoTimer - box.auto.delay)
  U.log("bubble frames under box", tostring(held))
  check("text box and bubble close on the same frame",
        boxGone ~= nil and boxGone == bubbleGone)
  check("bubble lasts 60 frames under the box", held == 60)
  U.still(game, DIR .. "/2843_02_box_and_bubble_gone.png")

  local oakShown = false
  for _ = 1, 60 do
    for _, n in ipairs(ow.npcs or {}) do
      if n.def and n.def.name == "PALLETTOWN_OAK" then oakShown = true end
    end
    if oakShown then break end
    U.wait(1)
  end
  check("oak appears after the bubble", oakShown)
  done()
end
