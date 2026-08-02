-- Manual check on the Viridian School blackboard headings layout (#591).
-- pokered engine/events/hidden_events/school_blackboard.asm .blackboardLoop draws
-- a 12x8 box and places StatusAilmentText1 at hlcoord 1,2 and StatusAilmentText2 at
-- hlcoord 6,2, with ViridianSchoolBlackboardText2 (data/text/text_2.asm, `done`)
-- still on screen under it.  Logic half: tests/parity_viridian_school_blackboard_bug503.lua.
--   POKEPORT_DRIVER=tests/drivers/school_blackboard_bug591_test.lua POKEPORT_IDENTITY=bug591 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .   (no POKEPORT_SPEED: fast-forward desyncs audio/logic ordering)
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local TextBox = require("src.render.TextBox")
  -- data/scripts/init.lua, not src/script/MapScripts.lua: OverworldController
  -- requires it lazily on the first map load, so the flavor registrations are
  -- not in place yet when the driver starts
  local MapScripts = require("data.scripts.init")

  local MAP = "VIRIDIAN_SCHOOL_HOUSE"
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  -- pokered data/events/hidden_events.asm:164, hidden_events_for
  -- VIRIDIAN_SCHOOL_HOUSE: hidden_text_predef 3, 0 is the blackboard on the
  -- north wall.  That cell is the wall itself, so the stand cell is the
  -- walkable one below it, looking up (data/maps/objects/ViridianSchoolHouse.asm
  -- puts the two warps at (2,7)/(3,7) and no object in the way).
  local BOARD = { x = 3, y = 0 }
  local STAND = { x = 3, y = 1, facing = "up" }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local hooks = MapScripts.get(MAP)
  check(MAP .. " registers an onInteract hook",
        hooks ~= nil and type(hooks.onInteract) == "function")
  -- a renamed extractor label reads on screen as "A did nothing", which is the
  -- #503 failure and not the layout question this driver is about
  for _, key in ipairs({ "_ViridianSchoolBlackboardText1",
      "_ViridianSchoolBlackboardText2", "_ViridianBlackboardSleepText",
      "_ViridianBlackboardPoisonText", "_ViridianBlackboardPrlzText",
      "_ViridianBlackboardBurnText", "_ViridianBlackboardFrozenText" }) do
    local s = game.data.text[key]
    check(key .. " resolves to a string", type(s) == "string" and s ~= "")
  end

  local opts = game.save.options or {}
  U.log("audio device present:", love.audio ~= nil,
        "  SFX VOL (0-7):", tostring(opts.sfxVol))
  if not love.audio or opts.sfxVol == 0 then
    U.log("WARNING: sfx output is off, so the Press_AB beep on every heading pick",
          "will be silent; raise SFX VOL in OPTION first")
  end

  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(10)
  local ow = game.overworld
  check("map " .. MAP .. " loaded", ow ~= nil and ow.map ~= nil)
  check("the blackboard cell is solid, as the wall it hangs on",
        ow ~= nil and not ow.map:isWalkableCell(BOARD.x, BOARD.y))

  -- a map edit or a mod could move the board: any walkable neighbour will do,
  -- {dx, dy, facing} is the offset from the board plus the look back at it
  local SIDES = {
    { 0, 1, "up" }, { 0, -1, "down" }, { 1, 0, "left" }, { -1, 0, "right" },
  }
  local function facingBoard()
    local p = game.overworld.player
    local fx, fy = p:facingCell()
    return fx == BOARD.x and fy == BOARD.y
  end
  if not facingBoard() then
    for _, s in ipairs(SIDES) do
      local cx, cy = BOARD.x + s[1], BOARD.y + s[2]
      if game.overworld.map:isWalkableCell(cx, cy)
         and not game.overworld:npcAtCell(cx, cy) then
        U.log(("(%d,%d) was not faced from the stand cell, standing on")
                :format(BOARD.x, BOARD.y), cx, cy, "facing", s[3])
        U.teleport(game, MAP, cx, cy, s[3])
        U.wait(10)
        break
      end
    end
  end
  check("standing where the blackboard is faced", facingBoard())

  local function boxText(box)
    local out = {}
    for _, page in ipairs(box.pages or {}) do
      for _, line in ipairs(page) do out[#out + 1] = line end
    end
    return table.concat(out, " / ")
  end

  -- the headings list is the flavor script's own StatusBoard, not a TextBox and
  -- not src/ui/Menu.lua (which has no second column), so identify it by .labels
  local function board()
    local top = game.stack:top()
    if top and top.labels and top.selection then return top end
    return nil
  end
  local function reachBoard()
    for _ = 1, 60 do
      if board() then return true end
      U.tap(game, "a")
      U.wait(8)
    end
    return false
  end

  U.tap(game, "a")
  U.wait(30)
  local top = game.stack:top()
  check("A on the blackboard opened a text box", getmetatable(top) == TextBox)
  if getmetatable(top) == TextBox then
    U.log("intro box reads:", boxText(top))
    check("it is _ViridianSchoolBlackboardText1",
          boxText(top):find("blackboard", 1, true) ~= nil)
  end

  check("the intro clears into the headings list", reachBoard())
  local b = board()
  if b then
    local labels = {}
    for i, label in ipairs(b.labels) do labels[i] = (label:gsub("^%s+", "")) end
    U.log("list rows:", table.concat(labels, " / "))
    check("SLP/PSN/PAR then BRN/FRZ/QUIT, in ViridianBlackboardStatusPointers order",
          table.concat(labels, "/") == "SLP/PSN/PAR/BRN/FRZ/QUIT")
    -- the whole point of #591: the prompt box is held open underneath rather
    -- than dismissed before the list goes up
    local under = game.stack.states[#game.stack.states - 1]
    check("the prompt box is still on the stack under the list",
          getmetatable(under) == TextBox and under.stay ~= nil)
    if getmetatable(under) == TextBox then
      U.log("prompt under the list reads:", boxText(under))
    end
    U.shot(game, SHOT_DIR .. "/bug591_blackboard_list.png")
  end

  if b then
    U.tap(game, "right")
    U.wait(10)
    check("RIGHT keeps the row and lands on BRN (wMenuItemOffset 3)",
          b:selection() == 4)
    U.shot(game, SHOT_DIR .. "/bug591_right_column.png")
    U.tap(game, "down")
    U.wait(10)
    check("DOWN inside the right column reaches FRZ", b:selection() == 5)
    U.shot(game, SHOT_DIR .. "/bug591_right_down.png")

    U.tap(game, "a")
    U.wait(30)
    top = game.stack:top()
    check("A on FRZ prints its blurb", getmetatable(top) == TextBox)
    if getmetatable(top) == TextBox then
      U.log("FRZ blurb reads:", boxText(top))
      check("it is _ViridianBlackboardFrozenText, the entry RIGHT+DOWN points at",
            boxText(top):find("frozen", 1, true) ~= nil)
    end
    U.shot(game, SHOT_DIR .. "/bug591_frz_blurb.png")

    check("the blurb loops back to the list (jp .blackboardLoop)", reachBoard())
    -- wCurrentMenuItem / wMenuItemOffset are never cleared inside the loop, so
    -- the cursor comes back where it was left
    check("the cursor comes back on FRZ, not reset to SLP",
          board() ~= nil and board():selection() == 5)
    U.shot(game, SHOT_DIR .. "/bug591_back_to_list.png")
    U.log("screenshots in", SHOT_DIR)
  end

  U.log("The list on screen is the moment: a 12x8 box in the top-left with two")
  U.log("columns, SLP/PSN/PAR and BRN/FRZ/QUIT on the same three rows, and the")
  U.log("\"Which heading do you want to read?\" box still up at the bottom with no")
  U.log("blinking arrow in it.  The near-miss to watch for is the prompt vanishing")
  U.log("(or blinking) once the list appears, and a cursor sitting on the S of SLP")
  U.log("instead of the blank in front of it.  RIGHT/LEFT jump columns keeping the")
  U.log("row, UP/DOWN stop at the ends without wrapping, and QUIT or B should drop")
  U.log("both boxes and let you walk again with no stale dialogue left behind.")

  while true do
    coroutine.yield()
  end
end
