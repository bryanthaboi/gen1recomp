-- Manual check on the Celadon Mansion roof house blackboard and pamphlet (#391).
-- pokered data/events/hidden_events.asm CELADON_MANSION_ROOF_HOUSE declares both
-- with hidden_text_predef (LinkCableHelp, TMNotebook), which the extractor never
-- parsed, so both A presses were dead.  The data half is in
-- tests/parity_celadon_roof_readables.lua.
--   POKEPORT_DRIVER=tests/drivers/celadon_roof_readables_bug391_test.lua POKEPORT_IDENTITY=bug391 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .   (no POKEPORT_SPEED: fast-forward desyncs audio)
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local TextBox = require("src.render.TextBox")
  local Menu = require("src.ui.Menu")
  -- data/scripts/init.lua, not src/script/MapScripts.lua: OverworldController
  -- requires it lazily on the first map load, so the registrations it makes
  -- are not in place yet when the driver starts
  local MapScripts = require("data.scripts.init")

  local MAP = "CELADON_MANSION_ROOF_HOUSE"
  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  -- hidden_events.asm: hidden_text_predef 3, 4 (pamphlet on the table) and
  -- 3, 0 / 4, 0 (blackboard in the north wall).  Both target cells are solid,
  -- so the stand cell is the walkable one below, facing up.
  local PAMPHLET = { x = 3, y = 4 }
  local BLACKBOARD = { x = 3, y = 0 }
  local BLACKBOARD_ALT = { x = 4, y = 0 }
  local BALL = { x = 4, y = 3 }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  local hooks = MapScripts.get(MAP)
  check(MAP .. " registers an onInteract hook",
        hooks ~= nil and type(hooks.onInteract) == "function")
  check("the Eevee ball talk entry is still registered",
        hooks ~= nil and hooks.talk ~= nil
          and hooks.talk.TEXT_CELADONMANSION_ROOF_HOUSE_EEVEE_POKEBALL ~= nil)
  for _, key in ipairs({ "_LinkCableHelpText1", "_LinkCableHelpText2",
      "_LinkCableInfoText1", "_LinkCableInfoText2", "_LinkCableInfoText3" }) do
    local s = game.data.text[key]
    check(key .. " resolves to a string", type(s) == "string" and s ~= "")
  end

  local opts = game.save.options or {}
  U.log("audio device present:", love.audio ~= nil,
        "  SFX VOL (0-7):", tostring(opts.sfxVol))
  if not love.audio or opts.sfxVol == 0 then
    U.log("WARNING: sfx output is off, so the menu beeps and the wall bonk will",
          "not be audible; raise SFX VOL in OPTION first")
  end

  -- reach the pamphlet: warps land at (2,7)/(3,7), so start below the table
  U.teleport(game, MAP, PAMPHLET.x, PAMPHLET.y + 2, "up")
  U.wait(10)
  local ow = game.overworld
  check("map " .. MAP .. " loaded", ow ~= nil and ow.map ~= nil)
  check("the pamphlet cell is solid, as the table it sits on",
        not ow.map:isWalkableCell(PAMPHLET.x, PAMPHLET.y))
  check("the blackboard cell is solid, as the wall it hangs on",
        not ow.map:isWalkableCell(BLACKBOARD.x, BLACKBOARD.y))
  U.hold(game, "up", 20)
  U.wait(10)

  -- a map edit or a mod could move the table: any walkable neighbour will do,
  -- {dx, dy, facing} is the offset from the readable plus the look back at it
  local SIDES = {
    { 0, 1, "up" }, { 0, -1, "down" }, { 1, 0, "left" }, { -1, 0, "right" },
  }
  -- alt is the blackboard's second cell: hidden_text_predef declares 3,0 and
  -- 4,0 with the same handler, so either one facing up is the right spot
  local function faceCell(cell, alt)
    local p = game.overworld.player
    local fx, fy = p:facingCell()
    if fx == cell.x and fy == cell.y then return true end
    if alt and fx == alt.x and fy == alt.y then return true end
    for _, s in ipairs(SIDES) do
      local cx, cy = cell.x + s[1], cell.y + s[2]
      if game.overworld.map:isWalkableCell(cx, cy)
         and not game.overworld:npcAtCell(cx, cy) then
        U.log(("(%d,%d) was not faced from where the walk ended, standing on")
                :format(cell.x, cell.y), cx, cy, "facing", s[3])
        U.teleport(game, MAP, cx, cy, s[3])
        U.wait(10)
        return true
      end
    end
    return false
  end

  local function boxText(box)
    local out = {}
    for _, page in ipairs(box.pages or {}) do
      for _, line in ipairs(page) do out[#out + 1] = line end
    end
    return table.concat(out, " / ")
  end

  check("standing where the pamphlet is faced", faceCell(PAMPHLET))
  U.tap(game, "a")
  U.wait(30)
  local top = game.stack:top()
  local isBox = getmetatable(top) == TextBox
  check("A on the pamphlet opened a text box", isBox)
  if isBox then
    U.log("box reads:", boxText(top))
    check("it is the TM pamphlet, not the generic bookshelf line",
          boxText(top):find("pamphlet", 1, true) ~= nil)
    U.shot(game, SHOT_DIR .. "/bug391_pamphlet.png")
  end
  -- clear the box: five pages of TMNotebookText, then back to the overworld
  for _ = 1, 40 do
    if game.stack:top() == game.overworld then break end
    U.tap(game, "a")
    U.wait(8)
  end
  check("the pamphlet closed and gave the overworld back",
        game.stack:top() == game.overworld)

  -- reach the blackboard: the table blocks column 3 between the two, so restart
  -- from the row below the wall rather than walking the long way around it
  U.teleport(game, MAP, BLACKBOARD.x, BLACKBOARD.y + 2, "up")
  U.hold(game, "up", 20) -- one step onto row 1, then a bonk on the north wall
  U.wait(10)
  U.log("walked to", game.overworld.player.cellX, game.overworld.player.cellY,
        "facing", game.overworld.player.facing)
  check("standing where the blackboard is faced",
        faceCell(BLACKBOARD, BLACKBOARD_ALT))
  U.tap(game, "a")
  U.wait(30)
  top = game.stack:top()
  isBox = getmetatable(top) == TextBox
  check("A on the blackboard opened a text box", isBox)
  if isBox then
    U.log("box reads:", boxText(top))
    check("it is _LinkCableHelpText1",
          boxText(top):find("TRAINER TIPS", 1, true) ~= nil)
  end
  -- through the intro and the prompt into the heading menu
  local menu
  for _ = 1, 40 do
    local t = game.stack:top()
    if getmetatable(t) == Menu then menu = t break end
    U.tap(game, "a")
    U.wait(8)
  end
  check("the prompt opened the heading menu", menu ~= nil)
  if menu then
    local labels = {}
    for i, item in ipairs(menu.items or {}) do labels[i] = item.label end
    U.log("menu rows:", table.concat(labels, " / "))
    check("four rows in HowToLinkText order",
          table.concat(labels, "/")
            == "HOW TO LINK/COLOSSEUM/TRADE CENTER/STOP READING")
    U.shot(game, SHOT_DIR .. "/bug391_blackboard_menu.png")
    U.log("captured", SHOT_DIR .. "/bug391_blackboard_menu.png")
  end

  U.log("The heading menu on screen is the moment to eyeball: a 15x10 box in")
  U.log("the top-left corner, four rows, nothing clipped.  Pick a heading and")
  U.log("its blurb prints, then the prompt and this menu should come back.")
  U.log("B or STOP READING drops you back outside and you can walk again.")
  U.log(("Then stand at (%d,%d) facing down and press A: the ball on the table")
          :format(BALL.x, BALL.y - 1))
  U.log("still hands over EEVEE, since the same script file changed.")

  while true do
    coroutine.yield()
  end
end
