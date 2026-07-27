-- Driver: the Viridian caterpillar speech waits for the player (#250).
-- A manual eye check, not a pass/fail run -- nothing in this repo can judge
-- "the text went by too fast to read".
--
-- pokered evidence.  text/ViridianCity.asm spells the answer with three
-- different break markers, and they are not interchangeable:
--
--   ViridianCityYoungster2CaterpieAndWeedleDescriptionText::
--       text "CATERPIE has no"
--       line "poison, but"
--       cont "WEEDLE does."
--
--       para "Watch out for its"
--       line "POISON STING!"
--       done
--
-- src/render/TextBox.lua maps those to \n (second line), \v (scroll one
-- line, after the down-arrow and a button press) and \f (page break, clear
-- and wait).  This text is not in data/generated/text.lua -- pokered
-- declares it without the leading underscore the extractor keys on -- so
-- the port carries a literal fallback, and that fallback had spelled both
-- `cont` and `para` as plain \n.  Six lines then landed on one page with
-- nothing to wait on, so the whole speech scrolled past untouched.
--
-- Do NOT run this under POKEPORT_SPEED.  Fast-forward scales only the logic
-- clock while the typewriter and its SFX run on their own real-time
-- accumulator (src/core/Game.lua), which is precisely the pacing being
-- judged here.
--
--   POKEPORT_DRIVER=tests/drivers/caterpillar_text_bug250_test.lua POKEPORT_IDENTITY=bug250 love .
return function(game)
  local U = dofile("tests/drivers/util.lua")

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- ---- preconditions the eye cannot separate from the bug ----------------
  -- A missing handler, or an NPC who wandered off, both end in "no text",
  -- which is not the same failure as "text that does not wait".

  local MAP = "VIRIDIAN_CITY"
  local NPC = "VIRIDIANCITY_YOUNGSTER2"
  local TEXT = "TEXT_VIRIDIANCITY_YOUNGSTER2"

  local mapScripts = require("data.scripts.init")
  check("a hand-ported handler exists for " .. TEXT,
        mapScripts.talkScript(MAP, TEXT) ~= nil)

  -- the fix itself: the paginator has to find a page break and a scroll in
  -- the description, because that is what makes it wait for a button
  local TextBox = require("src.render.TextBox")
  local desc = "CATERPIE has no\npoison, but\vWEEDLE does.\fWatch out for its\nPOISON STING!"
  local pages = TextBox.paginate(desc)
  check("the description spans two pages (para -> \\f)", #pages == 2)
  check("page 1 is three lines (text + line + cont)",
        pages[1] ~= nil and #pages[1] == 3)
  check("page 2 is two lines (para + line)",
        pages[2] ~= nil and #pages[2] == 2)
  -- the wait itself: contBefore marks the line the box holds on until the
  -- player presses a button, which is the whole point of the fix
  check("line 3 waits for a button before scrolling in",
        pages.contBefore and pages.contBefore[1] and pages.contBefore[1][3] == true)

  U.teleport(game, MAP, 30, 26, "up")
  U.wait(30)

  local function target()
    for _, n in ipairs(game.overworld and game.overworld.npcs or {}) do
      if n.def and n.def.name == NPC then return n end
    end
    return nil
  end

  local npc = target()
  check("the youngster is loaded on " .. MAP, npc ~= nil)
  -- pin the wander: he strolls out from under the A press between reads
  if npc then npc.wanders = false end

  -- objects live at ../pokered/data/maps/objects/ViridianCity.asm and in
  -- data/generated/maps.lua; he is at (30,25), so (30,26) faces him.  If a
  -- map edit ever moves him, stand on any free walkable neighbour instead
  -- of parking the player at a wall.
  local function facingTarget()
    local ow = game.overworld
    if not (ow and npc) then return false end
    local fx, fy = ow.player:facingCell()
    return ow:npcAtCell(fx, fy) == npc
  end

  if npc and not facingTarget() then
    local ow = game.overworld
    for _, s in ipairs({ { 0, 1, "up" }, { 1, 0, "left" },
                         { -1, 0, "right" }, { 0, -1, "down" } }) do
      local cx, cy = npc.cellX + s[1], npc.cellY + s[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log("approach cell blocked, standing on", cx, cy, "facing", s[3])
        U.teleport(game, MAP, cx, cy, s[3])
        U.wait(10)
        break
      end
    end
  end
  check("player is standing in front of the youngster", facingTarget())

  U.log("........................................................")
  U.log("READ NOW: press A to talk, then answer YES to his question.")
  U.log("  RIGHT: the answer stops and waits for you three times. After")
  U.log("         'WEEDLE does.' the box waits with a down-arrow, then the")
  U.log("         page CLEARS before 'Watch out for its POISON STING!'.")
  U.log("  BUG #250 looks like: all six lines pouring past in one go, the")
  U.log("         box scrolling itself, and the conversation ending before")
  U.log("         you have pressed anything.")
  U.log("  ALSO WRONG: it waits but never clears the page (that is \\v where")
  U.log("         pokered has para), or it clears after every single line")
  U.log("         (that is \\f where pokered has line/cont).")
  U.log("Control case: answer NO instead and you should get the one-line")
  U.log("  'Oh, OK then!', which needs no waits at all.")
  U.log("Input is yours from here, so you can re-run the talk as often as")
  U.log("you like.")
  U.log("........................................................")

  while true do
    coroutine.yield()
  end
end
