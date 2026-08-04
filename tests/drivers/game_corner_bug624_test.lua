-- Eyes on the Celadon Game Corner counters: the coin clerk's MONEY/COIN
-- windows and his question staying up under YES/NO (#624), then a prize
-- counter's three-prize window and its confirmation (#623).
-- Oracle: scripts/GameCorner.asm GameCornerClerk1Text + GameCornerDrawCoinBox,
-- engine/events/prize_menu.asm CeladonPrizeMenu / HandlePrizeChoice.
-- No POKEPORT_SPEED here: it scales only the logic clock while audio runs on
-- its own accumulator, so the menu beeps drift out of the presses.
--   POKEPORT_DRIVER=tests/drivers/game_corner_bug624_test.lua POKEPORT_IDENTITY=bug624 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local ChoiceBox = require("src.ui.ChoiceBox")
  local ListMenu = require("src.ui.ListMenu")
  local TextBox = require("src.render.TextBox")
  local mapScripts = require("data.scripts.init")

  local SHOT_DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local ok = true

  local function check(label, pass)
    U.log(pass and "PASS" or "FAIL", label)
    ok = ok and pass and true or false
    return pass
  end

  -- Read a page, press A, read the next one: tapping blind at a fixed rate
  -- drops presses, because a TextBox only takes A once it has finished
  -- typing (self.waiting).  Runs until `pred` holds or the frames run out.
  local function mashUntil(pred, frames)
    for _ = 1, frames or 900 do
      if pred() then return true end
      local top = game.stack:top()
      if top and (top.waiting or top.done
                  or getmetatable(top) == ChoiceBox) then
        U.tap(game, "a")
      else
        U.wait(1)
      end
    end
    return pred()
  end

  local function topIsChoice()
    return getmetatable(game.stack:top()) == ChoiceBox
  end

  -- ---------------------------------------------------------------- wiring
  -- a renamed text id, a dropped vendor binding and an unresolvable string
  -- all look exactly like the bug from the outside: nothing on screen
  local clerk = mapScripts.talkScript("GAME_CORNER", "TEXT_GAMECORNER_CLERK1")
  check("the coin clerk has a hand-ported handler", type(clerk) == "function")

  local vendors = {}
  for i = 1, 3 do
    vendors[i] = mapScripts.talkScript("GAME_CORNER_PRIZE_ROOM",
                   "TEXT_GAMECORNERPRIZEROOM_PRIZE_VENDOR_" .. i)
  end
  check("all three prize counters have handlers",
        type(vendors[1]) == "function" and type(vendors[2]) == "function"
        and type(vendors[3]) == "function")
  -- GetPrizeMenuId indexes PrizeDifferentMenuPtrs off the vendor's text id,
  -- so the three counters must not share one closure (#623)
  check("each counter is its own window, not one shared list",
        vendors[1] ~= vendors[2] and vendors[2] ~= vendors[3]
        and vendors[1] ~= vendors[3])

  local t = game.data.text
  local NEEDED = {
    "_GameCornerClerk1DoYouNeedSomeGameCoinsText",
    "_ExchangeCoinsForPrizesText", "_SoYouWantPrizeText",
    "_SorryNeedMoreCoinsText", "_OopsYouDontHaveEnoughRoomText",
    "_OhFineThenText",
  }
  local missing = {}
  for _, key in ipairs(NEEDED) do
    if type(t[key]) ~= "string" or t[key] == "" then
      missing[#missing + 1] = key
    end
  end
  check("every counter line resolves out of the cache (no silent fallback): "
        .. (#missing == 0 and "all present" or table.concat(missing, ", ")),
        #missing == 0)

  local vol = game.save.options and game.save.options.sfxVol
  if vol == 0 then
    U.log("sfx volume is 0, so the menu beeps under all this are muted.")
  end

  -- --------------------------------------------------------------- wallet
  -- enough of both to reach every branch: ¥1000 buys coins, 500 coins buys
  -- the cheapest mon on vendor 1 (ABRA, 180)
  game.save.money = 3000
  game.save.coins = 500
  game.save.inventory.COIN_CASE = 1

  -- ------------------------------------------------------------ the clerk
  -- pokered data/maps/objects/GameCorner.asm: GAMECORNER_CLERK1 stands at
  -- (5, 6) facing DOWN, so the approach is the cell below him.
  local function clerkNpc()
    for _, n in ipairs((game.overworld or {}).npcs or {}) do
      if n.def and n.def.name == "GAMECORNER_CLERK1" then return n end
    end
    return nil
  end

  local function facingClerk()
    local ow = game.overworld
    local man = ow and clerkNpc()
    if not man then return false end
    local fx, fy = ow.player:facingCell()
    return ow:npcAtCell(fx, fy) == man
  end

  U.teleport(game, "GAME_CORNER", 5, 7, "up")
  U.wait(10)
  local man = clerkNpc()
  check("the clerk object loaded on GAME_CORNER", man ~= nil)
  if man and not facingClerk() then
    -- a map edit moved him: take any free walkable neighbour instead of
    -- talking to a wall.  {dx, dy, facing} is the offset from the clerk to
    -- the stand cell plus the way to look back at him.
    local sides = {
      { 0, 1, "up" }, { 0, -1, "down" }, { 1, 0, "left" }, { -1, 0, "right" },
    }
    local ow = game.overworld
    for _, s in ipairs(sides) do
      local cx, cy = man.cellX + s[1], man.cellY + s[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log("(5, 7) is not against the clerk any more, standing on",
              cx, cy, "facing", s[3])
        U.teleport(game, "GAME_CORNER", cx, cy, s[3])
        U.wait(10)
        break
      end
    end
  end
  check("standing at the coin counter", facingClerk())

  U.tap(game, "a")
  U.wait(20)
  -- GameCornerDrawCoinBox is a plain TextBoxBorder with no input of its own:
  -- it has to sit under the dialogue for the whole exchange, i.e. the state
  -- pushed straight on top of the overworld draws and never updates (#624)
  local coinBox = game.stack.states[2]
  check("a draw-only MONEY/COIN window is under the conversation",
        game.stack.states[1] == game.overworld and type(coinBox) == "table"
        and coinBox.draw ~= nil and coinBox.update == nil)

  -- read through the offer the way a player does; it runs three pages
  check("the offer ends in a YES/NO box", mashUntil(topIsChoice, 900))
  -- the question used to close before the prompt opened; opts.choice keeps
  -- the box that asked it on screen underneath (#624)
  local under = game.stack.states[#game.stack.states - 1]
  check("the question is still on screen under YES/NO",
        getmetatable(under) == TextBox)
  check("captured the coin counter",
        U.shot(game, SHOT_DIR .. "/bug624_coin_clerk.png"))

  -- answer NO and let the goodbye line close itself out
  U.tap(game, "down")
  U.wait(6)
  mashUntil(function() return game.stack:top() == game.overworld end, 600)
  check("declining puts the coin window away with the dialogue",
        game.stack:top() == game.overworld and game.save.money == 3000)

  -- ------------------------------------------------------- a prize window
  -- pokered data/maps/objects/GameCornerPrizeRoom.asm: PRIZE_VENDOR_1 is a
  -- bg event at (2, 2), read by facing up from the tile below it.
  local SIGN = "TEXT_GAMECORNERPRIZEROOM_PRIZE_VENDOR_1"
  local function facingVendor()
    local ow = game.overworld
    if not ow then return false end
    local fx, fy = ow.player:facingCell()
    local sign = ow.map:signAtCell(fx, fy)
    return sign ~= nil and sign.text == SIGN
  end

  U.teleport(game, "GAME_CORNER_PRIZE_ROOM", 2, 3, "up")
  U.wait(10)
  if not facingVendor() then
    local ow = game.overworld
    local sides = {
      { 0, 1, "up" }, { 0, -1, "down" }, { 1, 0, "left" }, { -1, 0, "right" },
    }
    for _, s in ipairs(sides) do
      local cx, cy = 2 + s[1], 2 + s[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log("(2, 3) no longer reads the first counter, standing on",
              cx, cy, "facing", s[3])
        U.teleport(game, "GAME_CORNER_PRIZE_ROOM", cx, cy, s[3])
        U.wait(10)
        break
      end
    end
  end
  check("standing at the first prize counter", facingVendor())

  U.tap(game, "a")
  U.wait(20)
  local function listUp()
    return getmetatable(game.stack:top()) == ListMenu
  end
  mashUntil(listUp, 600)
  local list = listUp() and game.stack:top() or nil
  check("the exchange line opens a prize list", list ~= nil)

  if list then
    -- wMaxMenuItem is 3: this counter's three prizes and NO THANKS, never
    -- the whole catalogue (#623)
    local rows = list.items or {}
    local names = {}
    for _, item in ipairs(rows) do
      names[#names + 1] = item.label ..
        (item.right and (" " .. item.right) or "")
    end
    U.log("counter 1 offers:", table.concat(names, ", "))
    check("four rows: three prizes and NO THANKS", #rows == 4)
    check("the last row is the NO THANKS exit",
          rows[4] ~= nil and rows[4].label == "NO THANKS"
          and rows[4].value == nil)
    local priced = true
    for i = 1, math.min(3, #rows) do
      if not (rows[i].value and tonumber(rows[i].right)) then priced = false end
    end
    check("each prize names a real species or TM and a coin price", priced)
    check("captured the prize list",
          U.shot(game, SHOT_DIR .. "/bug623_prize_list.png"))

    -- take the top prize so the confirmation comes up
    U.tap(game, "a")
    U.wait(12)
    check("picking a prize asks before it takes the coins",
          mashUntil(topIsChoice, 600))
    local ask = game.stack.states[#game.stack.states - 1]
    local said = ""
    if getmetatable(ask) == TextBox then
      for _, page in ipairs(ask.pages or {}) do
        for _, l in ipairs(page) do said = said .. " " .. l end
      end
    end
    U.log("it asks:", (said:gsub("^%s+", "")))
    check("the question names the prize, not {RAM:wNameBuffer}",
          said:find("wNameBuffer", 1, true) == nil
          and rows[1] ~= nil and said:find(rows[1].label:match("^%S+"), 1, true)
              ~= nil)
    check("captured the confirmation",
          U.shot(game, SHOT_DIR .. "/bug623_prize_confirm.png"))
  end

  U.log(ok and "checks are green, the screen is worth looking at."
           or "something above says FAIL, do not trust what is on screen.")
  U.log("shots are in " .. SHOT_DIR .. ".")
  U.log("")
  U.log("on screen is counter 1's confirmation (#623): three prizes and NO")
  U.log("THANKS, and a YES/NO over \"So, you want ABRA?\" with nothing bought")
  U.log("yet. Answer either way and the conversation ends, then talk to the")
  U.log("counters again; each of the three sells its own window.")
  U.log("the clerk shot (#624) is the other half: the question still typed")
  U.log("out under the YES/NO, MONEY ¥3000 and COIN 500 in the top-right")
  U.log("window. the near-miss to look for is that window going stale, still")
  U.log("reading ¥3000 after the 50 coins are bought.")
  U.log("the prize list is still full-screen and the YES/NO lands on top of")
  U.log("the third row. the small windowed menu half of #623 was left alone.")

  while true do
    coroutine.yield()
  end
end
