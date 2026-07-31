-- Voxel world mode: the camera angle and its tween.
--
-- Deliberately the same shape as src/render/Tilt.lua -- level 0 is off and
-- 1..3 are the same 15/35/50 degree ladder, eased the same way. What
-- differs is what the renderer does with the angle: tilt projects the flat
-- world canvas as one rigid plane, voxel mode drives a real 3D camera over
-- extruded terrain and voxel character models.
--
-- And because it is a real camera over real geometry, it has a rung tilt
-- could never have: 75 degrees, low enough to read as a diorama shot from
-- table height. Tilt's flat plane degenerates into a horizon line there,
-- but geometry only gets more of itself to show.
--
-- The LEVEL is not ours. The engine's render_pipelines plumbing owns it --
-- the options row, the hotkey, the ladder labels, persistence in
-- save.options.pipelines.voxel, and the mutual exclusion with tilt -- and
-- hands it to update() every frame. All this module keeps is the eased
-- ANGLE that level implies, because the tween is renderer state and only
-- the renderer knows what to do with a half-raised camera.
--
-- Purely presentational, like tilt and survey zoom: nothing here reaches
-- collision, movement, triggers or scripts.

local Voxel = {}

-- FULL is a PRESET, not another angle: one rung that puts the whole mode in
-- its intended state at once -- this camera, the miniature blur at full, the
-- horizon flat, the view fitted -- so a player who wants "the diorama" picks
-- it rather than assembling it from four rows. It sits directly after OFF
-- because that is the order those two get used in.
--
-- Its ANGLE is 35 degrees, the same as the rung of that name. The duplicate
-- in the table is deliberate: the ladder is a list of what each rung LOOKS
-- like, and two rungs may look the same while meaning different things.
Voxel.ANGLES_DEG = { 0, 35, 15, 35, 50, 75 }
Voxel.ANGLE_LABELS = { "OFF", "FULL", "15", "35", "50", "75" }
Voxel.MAX_LEVEL = #Voxel.ANGLES_DEG - 1

-- the rung FULL sits on, so nothing has to hunt for it by label
Voxel.FULL_LEVEL = 1

function Voxel.isFull(level)
  return (level or Voxel.level) == Voxel.FULL_LEVEL
end

-- ------- what the hotkey walks
--
-- The ANGLE rungs only, with FULL left out. The key is a display-mode
-- cycler: pressing it should change the camera and nothing else, and FULL
-- reaches in and rewrites four other settings. Landing on it by accident,
-- mid-walk, would silently turn the blur to maximum and flatten the horizon
-- with no indication that a keypress had done so. FULL stays on the OPTIONS
-- row, which is where a preset that changes other rows belongs.
Voxel.HOTKEY_ORDER = { 0, 2, 3, 4, 5 }   -- OFF, 15, 35, 50, 75

-- The rung a press moves to from `level`.
--
-- A level that is not on the key's path -- FULL, reached from the menu --
-- steps on from whichever rung shows the SAME camera it does. FULL is 35
-- degrees, so a press from it goes to 50 rather than back to 35, and the key
-- never appears to do nothing. Matched by ANGLE rather than by a hardcoded
-- rung, so retuning FULL moves the key's answer with it.
function Voxel.nextHotkeyLevel(level)
  level = level or Voxel.level
  local order = Voxel.HOTKEY_ORDER
  local at = nil
  for i, rung in ipairs(order) do
    if rung == level then at = i break end
  end
  if not at then
    local deg = Voxel.ANGLES_DEG[level + 1]
    for i, rung in ipairs(order) do
      if Voxel.ANGLES_DEG[rung + 1] == deg then at = i break end
    end
  end
  if not at then return order[1] end
  return order[at % #order + 1]
end

Voxel.level = 0
Voxel.angle = 0
Voxel.from = 0
Voxel.goal = 0
Voxel.t = 1

-- Whether the scene has terrain to show for the current map. VoxelScene
-- maintains it every frame; while the first mesh of a fresh toggle is
-- still building, update() holds the camera tween at flat -- the 2D
-- fallback IS the flat pose, so the switch waits invisibly instead of
-- tilting an empty stage (or, before builds went asynchronous, freezing
-- the whole frame for seconds).
Voxel.ready = true

Voxel.TWEEN_TIME = 0.25
-- Camera distance as a multiple of the view height, and the matching field
-- of view. Kept equal to Tilt.FOCAL so a given angle frames the world the
-- same way in both modes; Voxel3D derives the FOV from it.
Voxel.FOCAL = 1.0

local function ease(t)
  return t * t * (3 - 2 * t)
end

local function goalFor(level)
  return math.rad(Voxel.ANGLES_DEG[level + 1] or 0)
end

function Voxel.setLevel(level)
  level = math.floor(tonumber(level) or 0)
  if level < 0 then level = 0 end
  if level > Voxel.MAX_LEVEL then level = Voxel.MAX_LEVEL end
  local goal = goalFor(level)
  if goal ~= Voxel.goal or level ~= Voxel.level then
    Voxel.from = Voxel.angle
    Voxel.goal = goal
    Voxel.t = 0
    -- leaving flat: presume no terrain until the scene reports some, so
    -- the tween's very first frame already waits instead of easing over
    -- an empty stage (render() confirms readiness the same frame when
    -- the meshes are already cached)
    if Voxel.angle == 0 and goal > 0 then Voxel.ready = false end
  end
  Voxel.level = level
end

function Voxel.reset()
  Voxel.level, Voxel.angle = 0, 0
  Voxel.from, Voxel.goal, Voxel.t = 0, 0, 1
end

function Voxel.levelLabel(level)
  return Voxel.ANGLE_LABELS[(level or Voxel.level) + 1] or "OFF"
end

-- The pipeline's per-frame tick. `level` is what the engine currently has
-- the mode set to, so a hotkey press or an options row lands here as a new
-- goal to ease toward rather than as a jump.  dt is real frame time, so
-- fast-forward does not speed the camera up.
function Voxel.update(dt, level)
  if level ~= nil and level ~= Voxel.level then Voxel.setLevel(level) end
  -- hold at flat until there is geometry to tilt over; easing OUT (goal
  -- below the current angle) never waits
  if Voxel.angle == 0 and Voxel.goal > 0 and not Voxel.ready then
    return
  end
  if Voxel.t < 1 then
    Voxel.t = math.min(1, Voxel.t + dt / Voxel.TWEEN_TIME)
    Voxel.angle = Voxel.from + (Voxel.goal - Voxel.from) * ease(Voxel.t)
  else
    Voxel.angle = Voxel.goal
  end
end

-- True while voxel mode is on *or* still easing out -- i.e. whenever the
-- renderer must take the 3D path instead of the flat blit. Mirrors
-- Tilt.active so the two gate the same way.
function Voxel.active()
  return Voxel.level > 0 or Voxel.angle > 0
end

return Voxel
