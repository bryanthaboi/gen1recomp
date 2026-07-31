-- Overworld battles: the over-the-shoulder camera and its parallax drift.
--
-- The two mons are PINNED to their cells: each pic is drawn wherever its
-- patch of ground projects to, not at a fixed screen slot. So the camera is
-- not decoration -- it is the thing that decides where the fight appears,
-- and it has to put those two patches of ground exactly where the battle
-- screen wants its two pics:
--
--     the player's mon   (26, 96)    back pic, feet on the text box, well left
--     the enemy's mon   (124, 56)    front pic, bottom of the 7x7 slot
--
-- Four screen coordinates, so four equations. The rig below is the solution:
-- SIDE / BACK / HEIGHT place the eye relative to the arena's midpoint, LOOK
-- aims it, and FRAME_H sets the lens, and together they land both marks
-- within a thousandth of a pixel of the targets. They are not hand-picked
-- numbers that looked about right -- they came out of a solver, and the
-- suite reprojects them so a future edit either still lands or says so.
--
-- East is what decides which mon is on which side. The arena axis runs north
-- (the enemy) to south (the player's mon), and a camera east of that axis
-- sees the near end swing LEFT and the far end RIGHT -- the layout arrived
-- at by standing in the right place rather than by mirroring anything.
--
-- ------- and two more equations, from the pixels
--
-- The pics are pixel art and their size on screen is not something the mod
-- gets to choose: 56 pixels for a front pic, 64 for a back one. And a mon has
-- to stand in ONE OVERWORLD SQUARE, or it towers over the houses and gives
-- away that the world behind it is a picture. Together those say the square
-- each mon stands on must project to about the width of its own pic, which is
-- two more equations for the same six unknowns -- and they are what set the
-- distance.
--
-- The answer is a LONG LENS FROM A LOW STANCE: twelve degrees above the
-- floor, twelve degrees wide, from five blocks back. Not a stylistic choice
-- -- it is what a 56-pixel sprite standing on a 16-pixel tile forces on a
-- 160-pixel screen. Roughly three tiles fit across the frame, so the camera
-- has to be far away and zoomed in rather than near and wide. That is the
-- DEFAULT rig, and every map that can take it gets it.
--
-- ------- the exception: rooms too small to stand back from
--
-- Five blocks back is further than some rooms are wide. A gym is about ten
-- cells across, so on one the eye lands OUTSIDE the map, where the border
-- ring the engine draws round every map -- extruded into a cliff by this mode
-- -- crosses the near Pokemon wherever it stands. Three gyms could not be
-- staged anywhere at all for that reason.
--
-- So there is a second rig, and an arena asks for it by name (cam = "wide"
-- in data/battle_arenas.lua). It comes in to about four cells with the lens
-- opened up to match: an ordinary 44-degree shot that fits inside the room.
-- The mons render smaller for it -- a bit over half a tile rather than a
-- whole one -- which is the price. Both rigs are solved against the SAME four
-- anchors, so the composition is identical either way; only the lens and the
-- distance differ, which is what makes it safe to pick per map.
--
-- Rooms too small for the long lens are the reason it exists, but it is not
-- only for them: an area that simply reads better with more of itself in
-- shot can ask for it too.
--
-- Purely presentational, like everything else in this mod: the camera looks
-- at the map, and nothing it does reaches collision, movement or scripts.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local BattleCam = {}

-- ------- the rig, in world pixels (a map cell is 16, a block 32)
--
-- Solved against the four anchors and two spans above, with the two mons 48
-- world pixels (three cells) apart -- BattleArena.SHAPES is where that gap is
-- set, and changing it invalidates these.

-- `frameH` is how much world the frame is tall enough to hold at the aim
-- distance, which together with that distance is the lens.
-- Named for the LENS, because that is what an author is choosing between
-- when they look at a shot and decide it wants more room in it.
BattleCam.RIGS = {
  -- the default: a long 11.5-degree lens from five blocks back, which is
  -- what makes one tile big enough to stand a 56-pixel mon on
  tele = {
    side = 78.79, back = 144.96, height = 37.88,
    lookX = -0.26, lookY = 0.34, frameH = 34.11,
  },
  -- 44 degrees from four cells: fits inside a room the long lens cannot
  -- stand back from, and shows more of anywhere else, at the cost of a
  -- smaller pair
  wide = {
    side = 41.98, back = 41.16, height = 28.48,
    lookX = -3.24, lookY = -1.35, frameH = 55.62,
  },
}

BattleCam.DEFAULT_RIG = "tele"

-- The rig an arena asks for, falling back to the default for anything that
-- does not ask (and for a name that is not one of the two).
function BattleCam.rigFor(arena)
  local want = arena and arena.cam
  return BattleCam.RIGS[want] or BattleCam.RIGS[BattleCam.DEFAULT_RIG]
end

-- ------- the drift
--
-- A slow orbit about the arena's vertical axis. Rotating about a point
-- BETWEEN the two mons is what makes it parallax rather than a pan: the mons
-- are pinned to the ground, so the near one slides one way across the frame
-- and the far one slides the OTHER, by the amount their difference in
-- distance implies. Over a full swing that is about eight pixels of relative
-- movement -- plainly visible as depth, far too slow to fight the fight.
-- The angle is small because the lens is long: two degrees of orbit is seven
-- pixels of travel through an eleven-degree field of view.
--
-- Under it, a much smaller breath in and out along the same line, on an
-- unrelated period, so the pair never returns to the same pose on any cycle
-- a battle is long enough to show. A DOLLY rather than a pan of the aim:
-- moving the aim point would slide both mons the same way, which with pinned
-- pics is just the whole picture walking sideways. Changing the DISTANCE
-- moves them apart and back together about the frame's centre, which is the
-- same depth cue the orbit gives, from the other axis.
BattleCam.PAN_YAW = math.rad(2)   -- half-angle of the orbit
BattleCam.PAN_PERIOD = 26         -- seconds for one there-and-back
BattleCam.PAN_DOLLY = 0.02        -- how far the eye breathes, as a fraction
BattleCam.DOLLY_PERIOD = 37

BattleCam.t = 0

function BattleCam.reset()
  BattleCam.t = 0
end

-- Real frame time, like every other presentational tween in this mod: a
-- fast-forwarded battle must not spin the camera.
function BattleCam.update(dt)
  BattleCam.t = BattleCam.t + (dt or 0)
  -- keep the phase small forever rather than letting a long session lose
  -- float precision in the sines below
  local wrap = BattleCam.PAN_PERIOD * BattleCam.DOLLY_PERIOD
  if BattleCam.t > wrap then BattleCam.t = BattleCam.t - wrap end
end

local function phase(t, period)
  return math.sin(2 * math.pi * t / period)
end

-- The camera for `arena` this instant: the record Voxel3D.camera takes, plus
-- the pitch the pull and the sun frustum want (measured from straight down,
-- the same convention Voxel.angle uses).
--
-- `fov` here frames the GB's 160x144. A caller rendering at window
-- resolution widens it for the extra picture around that frame -- see
-- BattleScene.letterboxFov, which is what keeps the pins exact at any window
-- size.
--
-- `groundY` is the height of the arena floor, so a fight staged on a ledge
-- or a raised walkway is shot from above THAT rather than from inside it.
function BattleCam.rig(arena, groundY)
  groundY = groundY or 0
  local R = BattleCam.rigFor(arena)
  local mx, mz = arena.mid[1], arena.mid[2]

  local yaw = BattleCam.PAN_YAW * phase(BattleCam.t, BattleCam.PAN_PERIOD)
  local c, s = math.cos(yaw), math.sin(yaw)
  -- the breath scales the whole offset, height included, so the eye moves
  -- along its own line to the arena and the pitch of the shot never changes
  local k = 1 + BattleCam.PAN_DOLLY
              * phase(BattleCam.t, BattleCam.DOLLY_PERIOD)
  local dx = (R.side * c - R.back * s) * k
  local dz = (R.side * s + R.back * c) * k

  local eye = { mx + dx, groundY + R.height * k, mz + dz }
  local focus = { mx + R.lookX, groundY + R.lookY, mz }

  local ex = eye[1] - focus[1]
  local ey = eye[2] - focus[2]
  local ez = eye[3] - focus[3]
  local dist = math.max(1, math.sqrt(ex * ex + ey * ey + ez * ez))
  local horiz = math.sqrt(ex * ex + ez * ez)

  return {
    eye = eye,
    focus = focus,
    fov = 2 * math.atan((R.frameH / 2) / dist),
    -- the world curve is a free-roam flourish that bends the horizon away
    -- from the player; a fixed camera on a staged shot has no player to bend
    -- around, and the bend would tip the arena floor out from under the mons
    -- the pics are pinned to
    curve = 0,
  }, math.atan2(horiz, math.max(1e-3, ey))
end

return BattleCam
