-- #1711: FLY is an animation, not a warp.  .FlyScript hides the map's objects
-- and runs FlyFromAnim before WarpToSpawnPoint and FlyToAnim after the
-- newloadmap (../pokegold/engine/events/overworld.asm:595-609, and the two
-- animations at engine/events/field_moves.asm:300 and :334).  Flown the way a
-- player flies: START > POKeMON > FLY out of New Bark Town.
--
--   POKEPORT_IDENTITY=gold-dev POKEPORT_GAME=gold POKEPORT_TOUCH=0 \
--     POKEPORT_DRIVER=tests/drivers/gold_fly_anim_bug1711_test.lua \
--     POKEPORT_SHOT_DIR=/tmp/gold-fly \
--     perl -e 'alarm 240; exec @ARGV' \
--     python3 -c "import pty; pty.spawn(['love','.'])"
--
-- Do not add POKEPORT_SPEED.  It scales the logic clock only, and the beat
-- being judged here is SFX_FLY against the wingbeat, which is audio against
-- logic -- fast-forward pulls those two apart.
local U = require("tests.drivers.util")

local FieldMoves = require("src.world.gen2.FieldMoves")
local Mon = require("src.battle.gen2.Mon")

local FLY_SPECIES = "PIDGEOTTO"

return function(game)
  local out = os.getenv("POKEPORT_SHOT_DIR") or "/tmp/gold-fly"
  local fails = 0

  local function ok(cond, msg)
    if cond then
      print("[fly] ok   " .. msg)
    else
      fails = fails + 1
      print("[fly] FAIL " .. msg)
    end
    return cond
  end

  local function tap(btn) U.tap(game, btn) U.wait(3) end
  local function top() return game.stack:top() end

  U.wait(45)
  local world = game.world
  local save, data = game.save, game.data
  if not ok(world and world.map, "gold booted into the overworld") then
    error("gold fly: no world")
  end

  local opts = save.options or {}
  local sfxVol = opts.sfxVol or 7
  if sfxVol == 0 then
    U.log("SFX volume is 0, so this run is silent whether the fix works or")
    U.log("not. turn it up in OPTIONS and run again before judging the sound.")
  end
  ok(sfxVol > 0, ("SFX volume is %d"):format(sfxVol))

  -- The wingbeat itself: no Sfx_Fly in the cache and the whole flight is
  -- silent, which sounds exactly like the bug.
  local audio = data and data.audio
  local flySfx = world:sfxIdNamed("Sfx_Fly", 0x18)
  local flySfxName = audio and audio.sfxOrder and audio.sfxOrder[flySfx + 1]
  ok(flySfxName == "Sfx_Fly" and audio.sfx and audio.sfx[flySfxName] ~= nil,
    ("the cache has Sfx_Fly at id %d"):format(flySfx))

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

  -- FlyFunction_InitGFX's GetSpeciesIcon: no icon row for the species and
  -- World:startFlyAnim refuses, which is the old instant warp back again.
  local icons = data and data.gen2Icons
  local iconId = icons and icons.species and icons.species[FLY_SPECIES]
  local entry = iconId and icons.icons and icons.icons[iconId]
  ok(entry and entry.image ~= nil,
    ("%s flies on %s (%s)"):format(FLY_SPECIES, tostring(iconId),
      tostring(entry and entry.image)))

  -- New Bark Town: a TOWN, so CheckOutdoorMap passes, and it keeps two objects
  -- in view for HideSprites to take away -- the teacher at (6,8) and the
  -- fisher at (12,9), ../pokecrystal/maps/NewBarkTown.asm:301-304.  Scene 1 is
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
  ok(#world.npcs > 0,
    ("with %d object(s) on the map to hide"):format(#world.npcs))

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
  local takeoffX, takeoffY = p.cellX, p.cellY

  -- Count the wingbeats, and only the ones the animation itself asks for.
  local sfxFrom, sfxTo = 0, 0
  local realPlaySfx = world.playSfx
  world.playSfx = function(self, id)
    local fa = self.flyAnim
    if fa and id == flySfx then
      if fa.phase == "to" then sfxTo = sfxTo + 1 else sfxFrom = sfxFrom + 1 end
    end
    return realPlaySfx(self, id)
  end

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
    error("gold fly: no start menu")
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
    error("gold fly: no party list")
  end
  tap("a")
  local sub = party.submenu
  if not ok(sub ~= nil, "and A opened the action submenu") then
    error("gold fly: no submenu")
  end
  local flyRow
  for index, item in ipairs(sub.items) do
    if item.id == "FLY" then flyRow = index end
  end
  if not ok(flyRow ~= nil, "which lists FLY") then
    error("gold fly: the submenu has no FLY row")
  end
  for _ = 1, #sub.items do
    if sub.index == flyRow then break end
    tap("down")
  end
  tap("a")
  U.wait(10)

  local picker = top()
  if not ok(picker and picker.screenId == "Gen2Pokegear" and picker.fly,
      "FLY opened the destination map") then
    error("gold fly: no picker")
  end
  -- _FlyMap's .HandleDPad walks the visited rows; up is the next one along,
  -- so one press leaves New Bark for the town after it.
  tap("up")
  U.wait(6)
  local destination = picker:flyRow()
  -- Landmark names carry TownMap_ConvertLineBreakCharacters' own <LF>, which
  -- would break a log line in half.
  ok(destination ~= nil, ("picked %s (%s)"):format(
    (tostring(destination and destination.name):gsub("%s+", " ")),
    tostring(destination and destination.spawn)))

  -- A commits, and .FlyScript starts on this map, not the far one.
  U.tap(game, "a")
  U.wait(3)
  if not ok(world.flyAnim ~= nil and world.flyAnim.phase == "from",
      "A started FlyFromAnim over the map being left") then
    error("gold fly: the flight collapsed into a warp")
  end
  ok(world:busy(), "and the world is frozen under it, as the callasm is")

  local hoverFrames, minY, maxSwing = 0, 0, 0
  local toAmpFirst, toAmpLast, sawTo = nil, nil, false
  local shots = { hover = false, climb = false, drop = false }
  for _ = 1, 900 do
    local fa = world.flyAnim
    if fa and fa.phase == "from" then
      if (fa.hover or 0) > 0 then hoverFrames = hoverFrames + 1 end
      minY = math.min(minY, fa.y or 0)
      maxSwing = math.max(maxSwing, math.abs(fa.xoff or 0))
      if not shots.hover and hoverFrames >= 20 then
        shots.hover = true
        U.shot(game, out .. "/01-fly-hover.png")
      elseif not shots.climb and (fa.y or 0) <= -40 then
        shots.climb = true
        U.shot(game, out .. "/02-fly-climb.png")
      end
    elseif fa then
      sawTo = true
      toAmpFirst = toAmpFirst or fa.amp
      toAmpLast = fa.amp
      -- Mid-drop, not the first frame of it: the swing opens at 11 * 8 px, so
      -- the icon starts the descent most of a screen off to one side.
      if not shots.drop and (fa.y or 0) >= -44 and (fa.y or 0) <= -16 then
        shots.drop = true
        U.shot(game, out .. "/03-fly-drop.png")
      end
    elseif sawTo then
      break
    end
    U.wait(1)
  end

  -- FlyFromAnim: 0x40 frames on the tile, then 2px a frame off the top with
  -- Sprites_Cosine widening the swing (engine/events/field_moves.asm:300-333).
  ok(hoverFrames >= 48,
    ("the icon held the take-off tile for %d frames"):format(hoverFrames))
  ok(minY <= -84, ("and climbed %d px off it"):format(-minY))
  ok(maxSwing >= 32, ("swinging up to %d px wide"):format(maxSwing))
  -- Nine beats going up (left 128 down to 64, every eighth), one coming down.
  ok(sfxFrom == 9, ("SFX_FLY flapped %d times on the way up"):format(sfxFrom))
  ok(sfxTo == 1, ("and %d time on the way down"):format(sfxTo))
  ok(sawTo, "FlyToAnim ran on the far side of the warp")
  ok(toAmpFirst and toAmpLast and toAmpLast < toAmpFirst,
    ("with its swing damping from %s to %s"):format(tostring(toAmpFirst),
      tostring(toAmpLast)))
  ok(shots.hover and shots.climb and shots.drop,
    "hover, climb and drop are all shot")

  U.wait(30)
  ok(world.flyAnim == nil, "the animation is over")
  ok(world.map.id ~= "NEW_BARK_TOWN",
    ("and the player landed on %s at (%d,%d)"):format(world.map.id,
      p.cellX, p.cellY))
  ok(not world:busy(), "with the controls handed back")
  U.shot(game, out .. "/04-fly-landed.png")
  ok(world.player.spriteYOffset == 0 or world.player.spriteYOffset == nil,
    "standing flat on the tile, not still lifted")

  U.log(("flew %s out of New Bark Town from (%d,%d) for you (#1711). the"):
    format(FLY_SPECIES, takeoffX, takeoffY))
  U.log("player's own sprite and every other object on the map should vanish")
  U.log("the moment A is pressed, replaced by the mon's 16x16 party icon on")
  U.log("that same tile, wings beating four times a second under a chirp of")
  U.log("SFX_FLY, for about a second. only then does it climb off the top of")
  U.log("the screen in a widening swing, and only then does the screen fade.")
  U.log("on the far side the icon falls back in from above, its swing damping")
  U.log("out, one more chirp, and the player pops in standing.")
  U.log("shots are in " .. out .. ".")
  U.log("the player still visible on the tile while the icon flies is the near")
  U.log("miss for the hide; an icon sitting dead still for two seconds and")
  U.log("then jumping is the hover without the climb.")
  if fails > 0 then
    U.log(("%d assertion(s) failed above -- read those before the pictures.")
      :format(fails))
  end
  U.log("the party still holds a flyer and the badge, so FLY again from the")
  U.log("menu whenever you want another look. the controls are yours.")

  while true do
    coroutine.yield()
  end
end
