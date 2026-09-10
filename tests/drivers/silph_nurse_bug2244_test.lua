-- ../pokered/text/SilphCo9F.asm:1
-- ../pokered/data/maps/objects/SilphCo9F.asm:20
--   POKEPORT_VERSION=red POKEPORT_IDENTITY=<sandbox> POKEPORT_TOUCH=0 \
--     POKEPORT_SHOT_DIR=<dir> POKEPORT_DRIVER=tests/drivers/silph_nurse_bug2244_test.lua love .
local U = require("tests.drivers.util")
local TextBox = require("src.render.TextBox")

local SHOT_DIR = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/pokeport-shots"

return function(game)
  local fails = 0
  local function say(line) print("[2244] " .. line) end
  local function ok(cond, line)
    if not cond then fails = fails + 1 end
    say((cond and "PASS " or "FAIL ") .. line)
  end
  local function topIs(mt) return getmetatable(game.stack:top()) == mt end

  local function waitForTextBox(frames)
    for _ = 1, frames do
      if topIs(TextBox) then return game.stack:top() end
      U.wait(1)
    end
    return nil
  end

  local function waitUntilPrompt(box, frames)
    for _ = 1, frames do
      if not topIs(TextBox) then return false end
      if box.waiting or box.done then return true end
      U.wait(1)
    end
    return box.waiting or box.done
  end

  local function shownLines(box)
    local page = box.pages[box.pageIndex] or {}
    local out = {}
    for i = 1, box.lineIndex do out[#out + 1] = page[i] end
    return table.concat(out, " / ")
  end

  local function finish()
    say(fails == 0 and "all claims passed" or (fails .. " claims failed"))
    love.event.quit(fails == 0 and 0 or 1)
    while true do U.wait(60) end
  end

  U.wait(10)
  game.save.flags.EVENT_BEAT_SILPH_CO_GIOVANNI = nil
  U.teleport(game, "SILPH_CO_9F", 3, 15, "up")
  U.wait(10)
  U.tap(game, "a")

  local box = waitForTextBox(120)
  ok(box ~= nil, "nurse opened a TextBox")
  if not box then return finish() end

  ok(waitUntilPrompt(box, 400), "tired text reached its first wait")
  local shown = shownLines(box)
  ok(box.waiting and box.contAdvance,
     "box holds on the cont arrow before 'quick nap!' (" .. shown .. ")")
  ok(shown:find("You should take a", 1, true) and not shown:find("quick nap!", 1, true),
     "'quick nap!' has not scrolled in yet")
  for _ = 1, 60 do
    if box.blink < 20 then break end
    U.wait(1)
  end
  U.shot(game, SHOT_DIR .. "/2244_01_take_a_cont_arrow.png")

  U.tap(game, "a")
  U.wait(3)
  ok(waitUntilPrompt(box, 400), "tired text reached its prompt after A")
  ok(shownLines(box):find("quick nap!", 1, true) ~= nil,
     "'quick nap!' scrolled in after the button")
  ok(box.done and not box.waiting, "final line waits on the {PROMPT} arrow")

  finish()
end
