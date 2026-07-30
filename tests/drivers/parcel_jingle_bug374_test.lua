-- Ear check on the Viridian Mart parcel jingle (#374): the key-item fanfare
-- used to fire when the box opened, two pages early.  pokered carries it as a
-- text command inside the gift text (scripts/ViridianMart.asm
-- sound_get_key_item, home/text.asm TextCommand_SOUND), so it lands after the
-- last character.  Do not set POKEPORT_SPEED: fast-forward scales the logic
-- clock only, so audio and text desynchronize and the check means nothing.
--   POKEPORT_DRIVER=tests/drivers/parcel_jingle_bug374_test.lua POKEPORT_IDENTITY=bug374 POKEPORT_TOUCH=0 POKEPORT_VERSION=red love .
return function(game)
  local U = dofile("tests/drivers/util.lua")
  local Flags = require("src.script.Flags")
  local DIR = os.getenv("SHOT_DIR") or "/tmp/shots"

  local MAP = "VIRIDIAN_MART"
  local QUEST = "_ViridianMartClerkParcelQuestText"
  -- pokered data/maps/objects/ViridianMart.asm: warp_event 3, 7 is the door;
  -- ViridianMartDefaultScript's .PlayerMovement walks left 1 / up 2 from it to
  -- the counter, so the driver only has to stand on the mat.
  local STAND = { x = 3, y = 7, facing = "up" }

  local function check(label, ok)
    U.log(ok and "PASS" or "FAIL", label)
    return ok
  end

  Flags.set(game.save, "EVENT_GOT_STARTER")
  game.save.flags.EVENT_GOT_OAKS_PARCEL = nil
  game.save.flags.EVENT_OAK_GOT_PARCEL = nil
  check("starter flag set, both parcel flags clear",
        Flags.get(game.save, "EVENT_GOT_STARTER")
        and not Flags.get(game.save, "EVENT_GOT_OAKS_PARCEL")
        and not Flags.get(game.save, "EVENT_OAK_GOT_PARCEL"))

  -- the whole point of the bug: the gift text is the three-page quest, so the
  -- jingle has two pages of typing to be early over
  local text = game.data.text[QUEST]
  check(QUEST .. " resolves", type(text) == "string" and text ~= "")
  local pages = 1
  for _ in tostring(text):gmatch("\f") do pages = pages + 1 end
  check("the quest text is three pages", pages == 3)
  local last = tostring(text):match("([^\f]*)$") or ""
  check("its last page is the got-parcel line",
        last:find("PARCEL", 1, true) ~= nil)

  local sfx = game.data.audio and game.data.audio.sfx
  check("Get_Key_Item is in the sfx table", sfx ~= nil and sfx.Get_Key_Item ~= nil)
  local parcel = game.data.items.OAKS_PARCEL
  check("OAKS_PARCEL is a key item (picks Get_Key_Item over Get_Item1)",
        parcel ~= nil and parcel.keyItem == true)

  local story = require("data.scripts.story")
  local gift
  for _, row in ipairs(story.VIRIDIAN_MART.talk.TEXT_VIRIDIANMART_CLERK) do
    if row[1] == "give_item" and row[2] == "OAKS_PARCEL" then gift = row end
  end
  check("the clerk's give_item row passes the quest text",
        gift ~= nil and gift[4] == QUEST)

  local vol = game.save.options and game.save.options.sfxVol
  if vol == 0 then
    U.log("SFX VOLUME IS 0. Nothing will be audible. Raise it in OPTION and rerun.")
  else
    check("sfx volume is audible (" .. tostring(vol) .. ")", vol ~= 0)
  end

  U.teleport(game, MAP, STAND.x, STAND.y, STAND.facing)
  U.wait(10)
  local ow = game.overworld
  if ow and not ow.map:isWalkableCell(STAND.x, STAND.y) then
    -- a map edit or a mod moved the mat: any free walkable neighbour of the
    -- door still lands inside the shop, and the clerk's script drives the walk
    local sides = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
    for _, s in ipairs(sides) do
      local cx, cy = STAND.x + s[1], STAND.y + s[2]
      if ow.map:isWalkableCell(cx, cy) and not ow:npcAtCell(cx, cy) then
        U.log(("door cell (%d, %d) is blocked, standing on"):format(STAND.x, STAND.y),
              cx, cy)
        U.teleport(game, MAP, cx, cy, STAND.facing)
        ow = game.overworld
        U.wait(10)
        break
      end
    end
  end
  check("standing in " .. MAP, ow ~= nil and ow.map.id == MAP)
  U.wait(50)

  U.tap(game, "a") U.wait(40)   -- the clerk's "you came from PALLET" page
  U.tap(game, "a") U.wait(90)   -- simulated walk to the counter, quest page 1
  U.tap(game, "a") U.wait(60)   -- page 2
  U.tap(game, "a") U.wait(180)  -- last page types out, the jingle belongs here
  U.shot(game, DIR .. "/374_parcel.png")
  U.log("captured", DIR .. "/374_parcel.png")

  U.log("The fanfare should start only after \"got / OAK's PARCEL!\" has")
  U.log("finished typing, the music ducks under it, and A is ignored until it")
  U.log("ends; then the arrow blinks and A closes the box.  The pad is yours:")
  U.log("clear both parcel flags and walk back in the door to hear it again.")

  while true do
    coroutine.yield()
  end
end
