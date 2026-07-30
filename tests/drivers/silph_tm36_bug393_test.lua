-- Manual check that the Silph Co 2F worker begs before handing over TM36 (#393).
-- pokered scripts/SilphCo2F.asm prints .PleaseTakeThisText (text/SilphCo2F.asm:1,
-- "Eeek!" / "No! Stop! Help!" ... "please take this!") before GiveItem; the port
-- had no such string in the cache, so the talk opened on "got TM36!".  Re-import
-- first (CACHE_FORMAT bump).  No POKEPORT_SPEED here: fast-forward
-- desynchronizes the item jingle from the box it belongs to.
--   SHOT_DIR=/tmp/shots POKEPORT_DRIVER=tests/drivers/silph_tm36_bug393_test.lua POKEPORT_IDENTITY=bug393 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"
  local TextBox = require("src.render.TextBox")
  local Bag = require("src.inventory.Bag")
  local mapScripts = require("data.scripts.init")

  -- pokered data/maps/objects/SilphCo2F.asm: SILPHCO2F_SILPH_WORKER_F stands at
  -- (10, 1) facing UP with row 0 walled off, so she is talked to from below.
  local MAP = "SILPH_CO_2F"
  local TEXT = "TEXT_SILPHCO2F_SILPH_WORKER_F"
  local WORKER = "SILPHCO2F_SILPH_WORKER_F"
  local PRE = "SilphCo2FSilphWorkerFPleaseTakeThisText"
  local STAND = { x = 10, y = 2, facing = "up" }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  -- the whole bug was a missing cache string, so say which half is wrong when
  -- the boxes come out empty
  local pre = game.data.text[PRE]
  check(PRE .. " is in the text cache", type(pre) == "string" and pre ~= "")
  if type(pre) == "string" then
    check("it is the scared line", pre:find("Eeek!", 1, true) ~= nil
            and pre:find("please take this!", 1, true) ~= nil)
    U.log("pre text reads:", (pre:gsub("[\n\011\012]", " / ")))
  end
  check(MAP .. "/" .. TEXT .. " runs a hand-ported script",
        type(mapScripts.talkScript(MAP, TEXT)) == "function")
  check("TM_SELFDESTRUCT is a known item",
        game.data.items.TM_SELFDESTRUCT ~= nil)

  -- a save that already has the TM takes the explanation-only branch
  if game.save.flags.EVENT_GOT_TM36 then
    game.save.flags.EVENT_GOT_TM36 = nil
    Bag.remove(game.save, "TM_SELFDESTRUCT", 1)
    U.log("EVENT_GOT_TM36 was already set; cleared it to replay the gift")
  end

  local vol = game.save.options and game.save.options.sfxVol
  if (vol or 0) == 0 then
    U.log("sfxVol is 0: the item jingle will be silent, raise it in OPTION first")
  else
    U.log("sfxVol", tostring(vol), "-- one Get_Item1 jingle, after the pleading")
  end

  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(10)

  local function workerIn(ow)
    for _, n in ipairs(ow.npcs or {}) do
      if n.def and n.def.name == WORKER then return n end
    end
    return nil
  end

  -- re-reads game.overworld: the fallback below teleports again, which rebuilds
  -- the state and its npc list
  local function facingTheWorker()
    local ow = game.overworld
    local her = ow and workerIn(ow)
    if not her then return false end
    local fx, fy = ow.player:facingCell()
    return ow:npcAtCell(fx, fy) == her
  end

  local ow = game.overworld
  local her = workerIn(ow)
  check("the worker is loaded on " .. MAP, her ~= nil)

  if her and not facingTheWorker() then
    -- a map edit or a mod moved her: stand on any free walkable neighbour.
    -- {dx, dy, facing} is the offset from her cell plus the way back at her.
    local sides = {
      { 0, 1, "up" }, { 0, -1, "down" }, { 1, 0, "left" }, { -1, 0, "right" },
    }
    for _, s in ipairs(sides) do
      local cx, cy = her.cellX + s[1], her.cellY + s[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log(("(%d, %d) is blocked, standing on"):format(STAND.x, STAND.y),
              cx, cy, "facing", s[3])
        U.teleport(game, MAP, cx, cy, s[3])
        U.wait(10)
        ow = game.overworld
        break
      end
    end
  end
  check("the player is facing her", facingTheWorker())

  local function boxText()
    local top = game.stack:top()
    if getmetatable(top) ~= TextBox then return nil end
    local out = {}
    for _, page in ipairs(top.pages or {}) do
      for _, line in ipairs(page) do out[#out + 1] = line end
    end
    return table.concat(out, " / ")
  end

  local function hasTm()
    return (game.save.inventory or {}).TM_SELFDESTRUCT ~= nil
  end

  U.tap(game, "a")
  U.wait(30)
  local first = boxText()
  check("A on her opens a text box", first ~= nil)
  if first then U.log("box 1 reads:", first) end
  check("the first box is the scared line, not the TM",
        first ~= nil and first:find("Eeek!", 1, true) ~= nil)
  check("and the TM is still hers while it is up", not hasTm())
  U.shot(game, DIR .. "/bug393_1_scared.png")

  -- read the rest of the conversation the way a player does
  for i = 2, 8 do
    U.tap(game, "a")
    U.wait(40)
    local t = boxText()
    if not t then break end
    U.log(("box %d reads:"):format(i), t)
    if t:find("TM36", 1, true) then
      U.shot(game, DIR .. "/bug393_2_tm36.png")
    end
  end
  check("TM36 ended up in the bag", hasTm())
  check("EVENT_GOT_TM36 is set", game.save.flags.EVENT_GOT_TM36 ~= nil)
  U.log("bag holds", tostring(Bag.slots(game.save)), "item kinds now")

  -- hand it back unclaimed so the pleading can be watched and heard live
  game.save.flags.EVENT_GOT_TM36 = nil
  Bag.remove(game.save, "TM_SELFDESTRUCT", 1)
  while getmetatable(game.stack:top()) == TextBox do
    U.tap(game, "a")
    U.wait(20)
  end
  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(10)
  U.log("the gift was rolled back; the pad is yours, press A on her")

  U.log("She should panic first: \"Eeek!/No! Stop! Help!\", then work out you")
  U.log("are not a Rocket and offer the TM, and only then the jingle plays and")
  U.log("the box says <PLAYER> got TM36!, followed by the SELFDESTRUCT warning.")
  U.log("Press A on her once more after that: straight to the warning, no panic.")

  while true do
    coroutine.yield()
  end
end
