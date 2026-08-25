-- #1712: the FLY map's cursor is the flying mon's party icon, not the MAP
-- card's arrow.  FlyMap's .MapHud calls TownMapMon, which reads wCurPartyMon
-- and spawns SPRITE_ANIM_OBJ_PARTY_MON on that species' icon
-- (../pokecrystal/engine/pokegear/pokegear.asm:2326, :2708-2721).  Reached the
-- way a player reaches it: START > POKeMON > FLY, standing in New Bark Town.
--
--   POKEPORT_IDENTITY=gold-dev POKEPORT_GAME=gold POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/gold_flymap_cursor_bug1712_test.lua \
--     POKEPORT_SHOT_DIR=/tmp/gold-flymap \
--     perl -e 'alarm 240; exec @ARGV' \
--     python3 -c "import pty; pty.spawn(['love','.'])"
--
-- Do not add POKEPORT_SPEED: the icon's two-frame beat is half of what is
-- being judged here, and the logic clock is the only thing speed scales.
local U = require("tests.drivers.util")

local FieldMoves = require("src.world.gen2.FieldMoves")
local Mon = require("src.battle.gen2.Mon")

local FLY_SPECIES = "PIDGEOTTO"

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-flymap"
  local fails = 0

  local function ok(cond, msg)
    if cond then
      print("[flymap] ok   " .. msg)
    else
      fails = fails + 1
      print("[flymap] FAIL " .. msg)
    end
    return cond
  end

  local function tap(btn) U.tap(game, btn) U.wait(3) end
  local function top() return game.stack:top() end

  U.wait(45)
  local world = game.world
  local save, data = game.save, game.data
  if not ok(world and world.map, "gold booted into the overworld") then
    error("gold flymap: no world")
  end

  -- FlyFunction .TryFly is CheckBadge STORMBADGE then CheckOutdoorMap
  -- (../pokegold/engine/events/overworld.asm:544-551).
  save.player = save.player or {}
  if type(save.player.badges) ~= "table" then save.player.badges = {} end
  save.player.badges.STORM = true
  save.engineFlags = save.engineFlags or {}
  for _, row in ipairs(FieldMoves.FLYPOINTS) do
    save.engineFlags[row.flag] = true
  end

  -- Mon.learnMove refuses a fifth move (src/battle/gen2/Mon.lua:650), and a
  -- level-24 PIDGEOTTO already knows four.
  local flyer = Mon.new(data, FLY_SPECIES, 24)
  table.remove(flyer.moves, 1)
  Mon.learnMove(flyer, "FLY", data)
  save.party = { flyer }
  local knowsFly = false
  for _, entry in ipairs(flyer.moves or {}) do
    if entry.id == "FLY" then knowsFly = true end
  end
  ok(knowsFly, FLY_SPECIES .. " knows FLY")

  -- The asset side, which fails exactly as silently as the bug: no icon row
  -- for the species and drawFlyMonCursor gives the arrow back.
  local icons = data and data.gen2Icons
  local iconId = icons and icons.species and icons.species[FLY_SPECIES]
  local entry = iconId and icons.icons and icons.icons[iconId]
  ok(iconId ~= nil, "the cache maps " .. FLY_SPECIES .. " to an icon ("
    .. tostring(iconId) .. ")")
  ok(entry and entry.image ~= nil, "and that icon has a sheet ("
    .. tostring(entry and entry.image) .. ")")
  if entry and entry.image and love.filesystem.getInfo then
    ok(love.filesystem.getInfo(entry.image) ~= nil,
      "and the sheet is on disk")
  end

  -- New Bark Town is a TOWN, so TryFly's CheckOutdoorMap passes, and it has
  -- two wandering objects to watch -- the teacher at (6,8) and the fisher at
  -- (12,9), ../pokecrystal/maps/NewBarkTown.asm:301-304.  Scene 1 is
  -- SCENE_NEWBARKTOWN_NOOP, so the teacher's coord event stays out of the way.
  world.mapScenes = world.mapScenes or {}
  world.mapScenes.NEW_BARK_TOWN = 1
  world:setMap("NEW_BARK_TOWN", 9, 8, "down")
  U.wait(15)
  local p = world.player
  local function free(cx, cy)
    return world.map:isWalkable(cx, cy) and not world:npcAt(cx, cy)
  end
  local DIRS = { down = { 0, 1 }, up = { 0, -1 }, left = { -1, 0 },
    right = { 1, 0 } }
  if not free(p.cellX, p.cellY) then
    for _, d in pairs(DIRS) do
      if free(9 + d[1], 8 + d[2]) then
        world:setMap("NEW_BARK_TOWN", 9 + d[1], 8 + d[2], "down")
        U.wait(10)
        break
      end
    end
  end
  ok(world.map.id == "NEW_BARK_TOWN" and free(p.cellX, p.cellY),
    ("standing free on New Bark Town (%d,%d)"):format(p.cellX, p.cellY))
  ok((world.map.def and world.map.def.environment) == "TOWN",
    "which is a TOWN, so FLY is allowed here")

  -- One real step through the pad, on a free neighbour.
  local fromX, fromY = p.cellX, p.cellY
  for name, d in pairs(DIRS) do
    if free(fromX + d[1], fromY + d[2]) then
      U.hold(game, name, 24)
      break
    end
  end
  U.wait(8)
  ok(p.cellX ~= fromX or p.cellY ~= fromY,
    ("the pad walked the player from (%d,%d) to (%d,%d)")
      :format(fromX, fromY, p.cellX, p.cellY))

  -- START > POKeMON.  CheckMenuOW only runs while nothing else owns the frame
  -- (../pokegold/engine/overworld/events.asm), so wait the map's own settling
  -- out rather than pressing into it.
  for _ = 1, 240 do
    if not world:busy() then break end
    U.wait(2)
  end
  local menu
  for _ = 1, 10 do
    tap("start")
    menu = top()
    if menu and menu.screenId == "Gen2StartMenu" then break end
    U.wait(6)
  end
  if not ok(menu and menu.screenId == "Gen2StartMenu",
      "START opened the menu (top is "
      .. tostring(menu and (menu.screenId or "?")) .. ")") then
    error("gold flymap: no start menu")
  end
  for _ = 1, 10 do
    if menu.list:current().value == "pokemon" then break end
    tap("down")
  end
  ok(menu.list:current().value == "pokemon", "the cursor found POKeMON")
  tap("a")

  local party = top()
  if not ok(party and party.screenId == "Gen2PartyMenu",
      "POKeMON opened the party list") then
    error("gold flymap: no party list")
  end

  -- A on the flyer, then down the submenu to its FLY row.
  tap("a")
  local sub = party.submenu
  if not ok(sub ~= nil, "and A opened the action submenu") then
    error("gold flymap: no submenu")
  end
  local flyRow
  for index, item in ipairs(sub.items) do
    if item.id == "FLY" then flyRow = index end
  end
  if not ok(flyRow ~= nil, "which lists FLY") then
    error("gold flymap: the submenu has no FLY row")
  end
  for _ = 1, #sub.items do
    if sub.index == flyRow then break end
    tap("down")
  end
  ok(sub.index == flyRow, "the cursor found FLY")
  tap("a")
  U.wait(10)

  local picker = top()
  if not ok(picker and picker.screenId == "Gen2Pokegear",
      "FLY opened the town map") then
    error("gold flymap: FLY did not open the picker")
  end
  ok(picker.fly ~= nil and #picker.fly > 0,
    "in _FlyMap dress, with " .. tostring(picker.fly and #picker.fly)
    .. " flypoints to walk")
  -- wCurPartyMon, as TownMapMon reads it (World:openFlyMap's flyMon).
  ok(picker.flyMon == flyer, "and it was handed the mon that used the move")
  ok(picker.icons ~= nil, "and it can see the icon table")

  U.wait(12)
  ok(picker.flyMonIcon ~= nil and picker.flyMonIcon ~= false,
    "the mon icon loaded for the cursor")
  -- No objColors, no OBP bake, and the bake is what keys colour 0 transparent
  -- (src/render/SpriteRenderer.lua:243): the icon would sit in a white box.
  ok(picker.flyMonIcon and picker.flyMonIcon.objColors ~= nil,
    "with an OBJ palette baked onto it")

  -- Landmark names carry TownMap_ConvertLineBreakCharacters' own <LF>, which
  -- would break a log line in half.
  local function flat(entry)
    return (tostring(entry and entry.name):gsub("%s+", " "))
  end

  local before = picker:mapLandmark()
  local player = picker:playerLandmark()
  ok(before and before.x and before.y, "the cursor is on " .. flat(before))
  U.shot(game, out .. "/01-flymap-newbark.png")

  tap("up")
  U.wait(8)
  local after = picker:mapLandmark()
  ok(after and (after.x ~= before.x or after.y ~= before.y),
    ("up walked the cursor to %s at (%s,%s)"):format(flat(after),
      tostring(after and after.x), tostring(after and after.y)))
  ok(picker:playerLandmark() == player,
    "and the player's own icon stayed where it was")
  U.shot(game, out .. "/02-flymap-cherrygrove.png")

  U.log("flew the party list into the FLY map for you (#1712). the cursor over")
  U.log("the highlighted town should be " .. FLY_SPECIES .. "'s 16x16 party")
  U.log("icon, red like the little Chris icon parked on New Bark, swapping")
  U.log("between its two frames about twice a second, and it moves with")
  U.log("up/down while Chris stays put. shots are in " .. out .. ".")
  U.log("the arrow cursor instead of a mon is the bug. a mon in a solid white")
  U.log("box is the near miss -- the icon is right, the palette bake is not.")
  if fails > 0 then
    U.log(("%d assertion(s) failed above; the picture below is not worth")
      :format(fails))
    U.log("reading until those are green.")
  end
  U.log("the picker is open and the controls are yours.")

  while true do
    coroutine.yield()
  end
end
